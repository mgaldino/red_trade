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
import ipaddress
import json
import logging
import math
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import BinaryIO, Iterable


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


@dataclass(frozen=True)
class AcquisitionBatch:
    """Results and immutable staging directory for one acquisition run."""

    results: tuple[AcquisitionResult, ...]
    staging_dir: Path | None


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


def validate_http_url(value: str) -> str:
    """Return a normalized HTTP(S) URL or reject unsupported locations."""

    if (
        not isinstance(value, str)
        or not value
        or "\\" in value
        or any(character.isspace() or ord(character) < 32 for character in value)
        or re.search(r"%(?![0-9A-Fa-f]{2})", value)
    ):
        raise ValueError(f"Invalid HTTP(S) URL: {value!r}")
    parsed = urllib.parse.urlsplit(value)
    if (
        parsed.scheme.lower() not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
    ):
        raise ValueError(f"Only HTTP(S) URLs with a hostname are allowed: {value!r}")
    try:
        port = parsed.port
    except ValueError as error:
        raise ValueError(f"Invalid HTTP(S) port in URL: {value!r}") from error
    if port == 0:
        raise ValueError(f"HTTP(S) port must be between 1 and 65535: {value!r}")
    hostname = parsed.hostname
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        try:
            ascii_hostname = hostname.encode("idna").decode("ascii")
        except UnicodeError as error:
            raise ValueError(f"Invalid HTTP(S) hostname: {value!r}") from error
        labels = ascii_hostname.split(".")
        if (
            len(ascii_hostname.encode("ascii")) > 253
            or any(
                not label
                or len(label.encode("ascii")) > 63
                or re.fullmatch(
                    r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?",
                    label,
                )
                is None
                for label in labels
            )
        ):
            raise ValueError(f"Invalid HTTP(S) hostname: {value!r}")
    return value


def validate_acquisition_options(
    *,
    timeout_seconds: int,
    retries: int,
    backoff_seconds: float,
) -> None:
    """Validate retry controls before any acquisition or cached-file return."""

    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")
    if retries < 1:
        raise ValueError("retries must be at least 1")
    if not math.isfinite(backoff_seconds) or backoff_seconds < 0:
        raise ValueError("backoff_seconds must be finite and nonnegative")


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
    allow_unmanifested: bool = False,
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
    row_paths: list[tuple[dict[str, str], Path, str]] = []
    for row in rows:
        validate_http_url(row["url"])
        archive_url = row.get("archive_url", "").strip()
        if archive_url:
            validate_http_url(archive_url)
        path = _safe_repo_path(root, raw_dir, row["raw_file"])
        relative = path.relative_to(raw_dir.resolve()).as_posix()
        row_paths.append((row, path, relative))
    ledger_relatives = {relative for _, _, relative in row_paths}
    for relative, expected in entries.items():
        path = raw_dir / relative
        if not path.is_file():
            if allow_missing and relative in ledger_relatives:
                continue
            raise FileNotFoundError(f"Manifested raw file is absent: {path}")
        observed = sha256(path)
        if observed != expected:
            raise ValueError(
                f"Raw SHA-256 mismatch for {path}: expected {expected}, got {observed}"
            )

    for _, path, relative in row_paths:
        if not path.is_file() and not allow_missing:
            raise FileNotFoundError(f"Ledger raw_file is absent: {path}")
        if relative not in entries and not allow_unmanifested:
            raise ValueError(f"Ledger raw_file is not in checksum manifest: {relative}")
        if relative not in entries and path.exists():
            raise ValueError(
                "Unmanifested acquisition paths must not already exist: "
                f"{relative}"
            )
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


def _write_bytes_exclusive(path: Path, value: bytes) -> None:
    """Create a new file atomically with respect to competing creators."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(value)


def _write_text_exclusive(path: Path, value: str) -> None:
    """Create a UTF-8 text file without any overwrite window."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="") as handle:
        handle.write(value)


def _write_stream_exclusive(path: Path, stream: BinaryIO) -> int:
    """Publish a complete stream without deleting pathnames after failures.

    Bytes first go to a run-unique partial file. A successful hard link then
    publishes exactly that completed inode at ``path`` without overwriting a
    competing creator. Failed partials are deliberately retained as audit
    evidence inside the unique acquisition-staging directory.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(f".{path.name}.partial-{uuid.uuid4().hex}")
    size = 0
    with partial.open("xb") as handle:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            handle.write(chunk)
            size += len(chunk)
        handle.flush()
        os.fsync(handle.fileno())
    os.link(partial, path, follow_symlinks=False)
    partial.unlink()
    return size


def _copy_verified_exclusive(
    source: Path,
    destination: Path,
    expected_hash: str,
) -> bool:
    """Promote only bytes copied and hashed from one open source descriptor.

    A complete promotion candidate is built beside the staged source. Its hash
    is computed during that same descriptor-bound copy. Only a matching
    candidate is hard-linked into the missing frozen path. The destination is
    then hashed independently. No failure path unlinks the contracted raw
    pathname, so a concurrent creator can never be removed by cleanup.
    """

    destination.parent.mkdir(parents=True, exist_ok=True)
    candidate = source.with_name(
        f".{source.name}.promotion-candidate-{uuid.uuid4().hex}"
    )
    digest = hashlib.sha256()
    with source.open("rb") as source_handle, candidate.open("xb") as target:
        while True:
            chunk = source_handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            target.write(chunk)
        target.flush()
        os.fsync(target.fileno())
    if digest.hexdigest() != expected_hash:
        return False
    os.link(candidate, destination, follow_symlinks=False)
    if sha256(destination) != expected_hash:
        raise RuntimeError(
            "Promoted raw file does not match its frozen SHA-256: "
            f"{destination}"
        )
    candidate.unlink()
    return True


def create_staging_directory(raw_dir: Path) -> Path:
    """Create an immutable, collision-resistant directory for one fetch run."""

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    run_id = f"{timestamp}_{uuid.uuid4().hex}"
    staging_dir = raw_dir.resolve() / "acquisition_staging" / run_id
    staging_dir.mkdir(parents=True, exist_ok=False)
    return staging_dir


def _write_metadata_sidecar(
    raw_path: Path,
    result: AcquisitionResult,
    *,
    iso3c: str,
    fetch_url: str,
) -> None:
    """Archive metadata for a new fetch without replacing an older sidecar."""

    target = _metadata_path(raw_path)
    payload = {
        **result.__dict__,
        "iso3c": iso3c,
        "fetch_url": fetch_url,
    }
    _write_text_exclusive(
        target,
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
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

    validate_http_url(url)
    validate_acquisition_options(
        timeout_seconds=timeout_seconds,
        retries=retries,
        backoff_seconds=backoff_seconds,
    )
    if output_path.exists():
        raise FileExistsError(f"Refusing to overwrite raw file: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    accessed_at = utc_now()
    last_error = ""
    for attempt in range(1, retries + 1):
        request = urllib.request.Request(url, headers={"User-Agent": user_agent})
        try:
            with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                status_code = getattr(response, "status", None)
                content_type = response.headers.get("Content-Type", "")
                size_bytes = _write_stream_exclusive(output_path, response)
            return AcquisitionResult(
                source_id="",
                url=url,
                status="ok",
                status_code=status_code,
                content_type=content_type,
                raw_file="",
                size_bytes=size_bytes,
                error="",
                accessed_at=accessed_at,
            )
        except urllib.error.HTTPError as error:
            size_bytes = _write_stream_exclusive(output_path, error)
            return AcquisitionResult(
                source_id="",
                url=url,
                status="http_error",
                status_code=error.code,
                content_type=error.headers.get("Content-Type", ""),
                raw_file="",
                size_bytes=size_bytes,
                error=str(error),
                accessed_at=accessed_at,
            )
        except (OSError, TimeoutError, urllib.error.URLError) as error:
            last_error = repr(error)
        if attempt < retries:
            time.sleep(backoff_seconds * (2 ** (attempt - 1)))

    error_path = output_path.with_suffix(output_path.suffix + ".error.txt")
    _write_text_exclusive(error_path, last_error)
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
    frozen_entries: dict[str, str],
) -> AcquisitionBatch:
    """Acquire absent ledger files into immutable staging.

    A missing file already declared by the frozen manifest is restored to its
    contracted path only when the staged bytes match the frozen SHA-256. A new,
    unmanifested source remains in staging until a separate authorial refreeze.
    """

    validate_acquisition_options(
        timeout_seconds=timeout_seconds,
        retries=retries,
        backoff_seconds=backoff_seconds,
    )
    rows = list(rows)
    pending = [
        row
        for row in rows
        if not _safe_repo_path(root, raw_dir, row["raw_file"]).is_file()
    ]
    staging_dir = create_staging_directory(raw_dir) if pending else None
    results: list[AcquisitionResult] = []
    for index, row in enumerate(rows, start=1):
        source_id = _source_id(row, index)
        raw_path = _safe_repo_path(root, raw_dir, row["raw_file"])
        if raw_path.is_file():
            metadata = _load_existing_metadata(raw_path)
            original_status = str(
                metadata.get("fetch_status") or metadata.get("status") or ""
            ).strip()
            if not original_status:
                original_status = (
                    "error" if raw_path.name.endswith(".error.txt") else "ok"
                )
            status = f"cached_{original_status.removeprefix('cached_')}"
            status_code_value = metadata.get("status_code")
            try:
                status_code = (
                    int(status_code_value)
                    if status_code_value not in (None, "")
                    else None
                )
            except (TypeError, ValueError):
                status_code = None
            results.append(
                AcquisitionResult(
                    source_id=source_id,
                    url=row["url"],
                    status=status,
                    status_code=status_code,
                    content_type=str(metadata.get("content_type") or ""),
                    raw_file=str(raw_path.relative_to(root.resolve())),
                    size_bytes=raw_path.stat().st_size,
                    error=str(metadata.get("error") or ""),
                    accessed_at=utc_now(),
                )
            )
            continue

        if staging_dir is None:
            raise RuntimeError("Missing staging directory for pending acquisition")
        relative = raw_path.relative_to(raw_dir.resolve()).as_posix()
        metadata = _load_existing_metadata(raw_path)
        download_url = str(metadata.get("fetch_url") or row["url"])
        validate_http_url(download_url)
        staged_pointer = staging_dir / relative
        body_path = _body_path(staged_pointer)
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
                raise RuntimeError(
                    f"Missing error artifact after failed fetch: {body_path}"
                )
            actual_path = candidates[-1]
        expected_hash = frozen_entries.get(relative)
        if expected_hash is None:
            status = f"new_source_staged_{fetched.status}"
            final_path = actual_path
        elif _copy_verified_exclusive(actual_path, raw_path, expected_hash):
            status = f"recovered_frozen_{fetched.status}"
            final_path = raw_path
        else:
            status = f"hash_mismatch_staged_{fetched.status}"
            final_path = actual_path
        result = AcquisitionResult(
            source_id=source_id,
            url=row["url"],
            status=status,
            status_code=fetched.status_code,
            content_type=fetched.content_type,
            raw_file=str(final_path.relative_to(root.resolve())),
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
    return AcquisitionBatch(results=tuple(results), staging_dir=staging_dir)


def write_json_log(path: Path, results: Iterable[AcquisitionResult]) -> None:
    """Write one run-scoped acquisition log with exclusive creation."""

    payload = [result.__dict__ for result in results]
    _write_text_exclusive(
        path,
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    )


def write_staging_manifest(staging_dir: Path) -> Path:
    """Create a run-scoped manifest without mutating the frozen manifest."""

    manifest_path = staging_dir / "checksums.sha256"
    lines = []
    for path in sorted(staging_dir.rglob("*")):
        if path.is_file() and path != manifest_path:
            relative = path.relative_to(staging_dir).as_posix()
            lines.append(f"{sha256(path)}  {relative}")
    _write_text_exclusive(manifest_path, "\n".join(lines) + "\n")
    return manifest_path
