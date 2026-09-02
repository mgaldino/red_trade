#!/usr/bin/env python3
"""Shared acquisition-only utilities for the status-evidence collectors.

The functions in this module may access HTTP only after the caller receives an
explicit ``--acquire`` flag. They never write processed coding or appendix
tables. Existing raw responses are immutable: a present file is reused and is
never overwritten.
"""

from __future__ import annotations

import csv
import hashlib
import json
import logging
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class AcquisitionResult:
    """One immutable acquisition attempt or cached-file observation."""

    source_id: str
    url: str
    status: str
    status_code: int | None
    content_type: str
    raw_file: str
    size_bytes: int
    error: str
    accessed_at: str


def utc_now() -> str:
    """Return an ISO-8601 UTC timestamp without fractional seconds."""

    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def sha256(path: Path) -> str:
    """Compute SHA-256 without loading a whole file into memory."""

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    """Read a UTF-8 CSV ledger and preserve all fields as strings."""

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _safe_repo_path(root: Path, raw_dir: Path, value: str) -> Path:
    """Resolve a repository-relative raw path and reject path traversal."""

    if not value or Path(value).is_absolute():
        raise ValueError(f"raw_file must be a non-empty relative path: {value!r}")
    root_resolved = root.resolve()
    raw_resolved = raw_dir.resolve()
    path = (root_resolved / value).resolve()
    if path != raw_resolved and raw_resolved not in path.parents:
        raise ValueError(f"raw_file escapes the collector raw directory: {value}")
    return path


def read_checksum_manifest(manifest_path: Path, raw_dir: Path) -> dict[str, str]:
    """Parse the standard ``SHA256  relative/path`` manifest safely."""

    entries: dict[str, str] = {}
    for line_number, line in enumerate(
        manifest_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line.strip():
            continue
        parts = line.split("  ", maxsplit=1)
        if len(parts) != 2:
            raise ValueError(
                f"Malformed checksum line {line_number} in {manifest_path}"
            )
        digest, relative = parts
        if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            raise ValueError(
                f"Invalid SHA-256 on line {line_number} in {manifest_path}"
            )
        relative_path = Path(relative)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise ValueError(
                f"Unsafe checksum path on line {line_number}: {relative}"
            )
        normalized = relative_path.as_posix()
        if normalized in entries:
            raise ValueError(f"Duplicate checksum path: {normalized}")
        path = (raw_dir / relative_path).resolve()
        if raw_dir.resolve() not in path.parents:
            raise ValueError(f"Checksum path escapes raw directory: {relative}")
        entries[normalized] = digest
    return entries


def validate_frozen_archive(
    *,
    root: Path,
    ledger_path: Path,
    raw_dir: Path,
    manifest_path: Path,
    expected_entries: int,
    allow_missing: bool = False,
) -> list[dict[str, str]]:
    """Validate the ledger, every manifest entry, and every ledger raw pointer."""

    rows = read_csv_rows(ledger_path)
    if not rows:
        raise ValueError(f"Evidence ledger is empty: {ledger_path}")
    required = {"iso3c", "url", "raw_file"}
    missing = sorted(required - set(rows[0]))
    if missing:
        raise ValueError(f"Evidence ledger misses columns: {', '.join(missing)}")

    entries = read_checksum_manifest(manifest_path, raw_dir)
    if len(entries) != expected_entries:
        raise ValueError(
            f"Expected {expected_entries} checksum entries in {manifest_path}, "
            f"found {len(entries)}"
        )
    for relative, expected in entries.items():
        path = raw_dir / relative
        if not path.is_file():
            if allow_missing:
                continue
            raise FileNotFoundError(f"Manifested raw file is absent: {path}")
        observed = sha256(path)
        if observed != expected:
            raise ValueError(
                f"Raw SHA-256 mismatch for {path}: expected {expected}, got {observed}"
            )

    for row in rows:
        path = _safe_repo_path(root, raw_dir, row["raw_file"])
        relative = path.relative_to(raw_dir.resolve()).as_posix()
        if not path.is_file() and not allow_missing:
            raise FileNotFoundError(f"Ledger raw_file is absent: {path}")
        if relative not in entries:
            raise ValueError(f"Ledger raw_file is not in checksum manifest: {relative}")
    return rows


def _metadata_path(raw_path: Path) -> Path:
    """Return the historical sidecar name for a raw body or error file."""

    name = raw_path.name
    if name.endswith(".error.txt"):
        name = name[: -len(".error.txt")]
    suffix = Path(name).suffix
    stem = name[: -len(suffix)] if suffix else name
    return raw_path.with_name(f"{stem}.metadata.json")


def _load_existing_metadata(raw_path: Path) -> dict[str, object]:
    path = _metadata_path(raw_path)
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _body_path(raw_path: Path) -> Path:
    """Map a historical error pointer to the intended response-body path."""

    if raw_path.name.endswith(".error.txt"):
        return raw_path.with_name(raw_path.name[: -len(".error.txt")])
    return raw_path


def _write_metadata_sidecar(
    raw_path: Path,
    result: AcquisitionResult,
    *,
    iso3c: str,
    fetch_url: str,
) -> None:
    """Archive metadata for a new fetch without replacing an older sidecar."""

    target = _metadata_path(raw_path)
    if target.exists():
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        target = target.with_name(f"{target.stem}_{timestamp}{target.suffix}")
    payload = {
        **result.__dict__,
        "iso3c": iso3c,
        "fetch_url": fetch_url,
    }
    target.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def request_missing_url(
    *,
    url: str,
    output_path: Path,
    user_agent: str,
    timeout_seconds: int,
    retries: int,
    backoff_seconds: float,
) -> AcquisitionResult:
    """Fetch one missing URL with retry/backoff and without overwriting raw data."""

    if output_path.exists():
        raise FileExistsError(f"Refusing to overwrite raw file: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    accessed_at = utc_now()
    last_error = ""
    for attempt in range(1, retries + 1):
        request = urllib.request.Request(url, headers={"User-Agent": user_agent})
        try:
            with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                body = response.read()
                status_code = getattr(response, "status", None)
                content_type = response.headers.get("Content-Type", "")
            output_path.write_bytes(body)
            return AcquisitionResult(
                source_id="",
                url=url,
                status="ok",
                status_code=status_code,
                content_type=content_type,
                raw_file="",
                size_bytes=len(body),
                error="",
                accessed_at=accessed_at,
            )
        except urllib.error.HTTPError as error:
            body = error.read()
            if body:
                output_path.write_bytes(body)
                return AcquisitionResult(
                    source_id="",
                    url=url,
                    status="http_error",
                    status_code=error.code,
                    content_type=error.headers.get("Content-Type", ""),
                    raw_file="",
                    size_bytes=len(body),
                    error=str(error),
                    accessed_at=accessed_at,
                )
            last_error = repr(error)
        except (OSError, TimeoutError, urllib.error.URLError) as error:
            last_error = repr(error)
        if attempt < retries:
            time.sleep(backoff_seconds * (2 ** (attempt - 1)))

    error_path = output_path.with_suffix(output_path.suffix + ".error.txt")
    if error_path.exists():
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        error_path = output_path.with_suffix(
            output_path.suffix + f".{timestamp}.error.txt"
        )
    error_path.write_text(last_error, encoding="utf-8")
    return AcquisitionResult(
        source_id="",
        url=url,
        status="error",
        status_code=None,
        content_type="",
        raw_file="",
        size_bytes=0,
        error=last_error,
        accessed_at=accessed_at,
    )


def _source_id(row: dict[str, str], index: int) -> str:
    value = row.get("source_id", "").strip()
    if value:
        return value
    raw_name = Path(row["raw_file"]).name
    for suffix in (".error.txt", ".metadata.json", ".html", ".htm", ".pdf", ".txt"):
        if raw_name.endswith(suffix):
            raw_name = raw_name[: -len(suffix)]
            break
    return raw_name or f"source_{index:03d}"


def acquire_missing_ledger_files(
    *,
    root: Path,
    raw_dir: Path,
    rows: Iterable[dict[str, str]],
    user_agent: str,
    timeout_seconds: int,
    retries: int,
    backoff_seconds: float,
) -> list[AcquisitionResult]:
    """Acquire only absent ledger files; present raw data are immutable."""

    results: list[AcquisitionResult] = []
    for index, row in enumerate(rows, start=1):
        source_id = _source_id(row, index)
        raw_path = _safe_repo_path(root, raw_dir, row["raw_file"])
        if raw_path.is_file():
            status = "cached_error" if raw_path.name.endswith(".error.txt") else "cached_ok"
            results.append(
                AcquisitionResult(
                    source_id=source_id,
                    url=row["url"],
                    status=status,
                    status_code=None,
                    content_type="",
                    raw_file=str(raw_path.relative_to(root.resolve())),
                    size_bytes=raw_path.stat().st_size,
                    error="",
                    accessed_at=utc_now(),
                )
            )
            continue

        metadata = _load_existing_metadata(raw_path)
        download_url = str(metadata.get("fetch_url") or row["url"])
        body_path = _body_path(raw_path)
        LOGGER.info("Fetching missing source %s", source_id)
        fetched = request_missing_url(
            url=download_url,
            output_path=body_path,
            user_agent=user_agent,
            timeout_seconds=timeout_seconds,
            retries=retries,
            backoff_seconds=backoff_seconds,
        )
        actual_path = body_path
        if fetched.status == "error":
            candidates = sorted(body_path.parent.glob(body_path.name + "*.error.txt"))
            if not candidates:
                raise RuntimeError(f"Missing error artifact after failed fetch: {body_path}")
            actual_path = candidates[-1]
        result = AcquisitionResult(
            source_id=source_id,
            url=row["url"],
            status=fetched.status,
            status_code=fetched.status_code,
            content_type=fetched.content_type,
            raw_file=str(actual_path.relative_to(root.resolve())),
            size_bytes=fetched.size_bytes,
            error=fetched.error,
            accessed_at=fetched.accessed_at,
        )
        _write_metadata_sidecar(
            actual_path,
            result,
            iso3c=row["iso3c"],
            fetch_url=download_url,
        )
        results.append(result)
    return results


def write_json_log(path: Path, results: Iterable[AcquisitionResult]) -> None:
    """Write an acquisition log; never overwrite a historical log."""

    payload = [result.__dict__ for result in results]
    target = path
    if target.exists():
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        target = path.with_name(f"{path.stem}_{timestamp}{path.suffix}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_checksum_manifest(manifest_path: Path, raw_dir: Path) -> None:
    """Regenerate the raw checksum manifest after a deliberate acquisition."""

    lines = []
    for path in sorted(raw_dir.rglob("*")):
        if path.is_file() and path != manifest_path:
            lines.append(f"{sha256(path)}  {path.relative_to(raw_dir).as_posix()}")
    manifest_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
