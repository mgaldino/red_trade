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
import stat
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

URI_UNRESERVED = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
)
URI_SUB_DELIMITERS = frozenset("!$&'()*+,;=")
URI_PATH_CHARACTERS = URI_UNRESERVED | URI_SUB_DELIMITERS | frozenset(":@/")
URI_QUERY_FRAGMENT_CHARACTERS = URI_PATH_CHARACTERS | frozenset("?")
HEX_DIGITS = frozenset("0123456789ABCDEFabcdef")


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


class FrozenDestinationConflictError(RuntimeError):
    """A competing frozen destination exists with unexpected bytes."""


class FrozenArchiveValidationError(RuntimeError):
    """The frozen archive or its author-owned ledger failed validation."""


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


def _inspect_regular_file(path: Path) -> tuple[str, int]:
    """Hash and size one regular file through a no-follow descriptor."""

    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    with os.fdopen(descriptor, "rb") as handle:
        file_stat = os.fstat(handle.fileno())
        if not stat.S_ISREG(file_stat.st_mode):
            raise ValueError(f"Expected a regular file: {path}")
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest(), file_stat.st_size


def _sha256_regular_file(path: Path) -> str:
    """Hash one regular file through a no-follow descriptor."""

    return _inspect_regular_file(path)[0]


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    """Read a UTF-8 CSV ledger and preserve all fields as strings."""

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _valid_uri_component(value: str, allowed: frozenset[str]) -> bool:
    """Validate one ASCII RFC 3986 component, including percent escapes."""

    index = 0
    while index < len(value):
        character = value[index]
        if character == "%":
            if (
                index + 2 >= len(value)
                or value[index + 1] not in HEX_DIGITS
                or value[index + 2] not in HEX_DIGITS
            ):
                return False
            index += 3
            continue
        if character not in allowed:
            return False
        index += 1
    return True


def validate_http_url(value: str) -> str:
    """Return an ASCII HTTP(S) URI with DNS or IPv4 authority."""

    if (
        not isinstance(value, str)
        or not value
        or any(ord(character) < 33 or ord(character) > 126 for character in value)
    ):
        raise ValueError(f"Invalid HTTP(S) URL: {value!r}")
    try:
        parsed = urllib.parse.urlsplit(value)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise ValueError(f"Invalid HTTP(S) URL: {value!r}") from error
    if (
        parsed.scheme.lower() not in {"http", "https"}
        or not hostname
        or parsed.username is not None
        or parsed.password is not None
        or not _valid_uri_component(parsed.path, URI_PATH_CHARACTERS)
        or not _valid_uri_component(
            parsed.query,
            URI_QUERY_FRAGMENT_CHARACTERS,
        )
        or not _valid_uri_component(
            parsed.fragment,
            URI_QUERY_FRAGMENT_CHARACTERS,
        )
    ):
        raise ValueError(f"Invalid HTTP(S) URI components: {value!r}")
    if port == 0:
        raise ValueError(f"HTTP(S) port must be between 1 and 65535: {value!r}")
    ipv4_lexeme = re.fullmatch(r"[0-9]+(?:\.[0-9]+){3}", hostname) is not None
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        if ipv4_lexeme:
            raise ValueError(f"Invalid canonical IPv4 address: {value!r}")
        labels = hostname.split(".")
        if (
            len(hostname.encode("ascii")) > 253
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
    else:
        if address.version != 4:
            raise ValueError(f"Only DNS or IPv4 hostnames are allowed: {value!r}")
    expected_authority = hostname
    if port is not None:
        expected_authority = f"{expected_authority}:{port}"
    if parsed.netloc.lower() != expected_authority.lower():
        raise ValueError(f"Invalid HTTP(S) authority: {value!r}")
    return value


class HttpOnlyRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Revalidate every redirect and reject non-HTTP(S) destinations."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_http_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


HTTP_ONLY_OPENER = urllib.request.build_opener(HttpOnlyRedirectHandler())


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


def _reject_symlink_parents(raw_root: Path, path: Path) -> None:
    """Reject existing symlinks or non-directories before a raw leaf."""

    try:
        relative = path.relative_to(raw_root)
    except ValueError as error:
        raise ValueError(
            f"Raw path escapes its contracted directory: {path}"
        ) from error
    current = raw_root
    for part in relative.parts[:-1]:
        current = current / part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            break
        if stat.S_ISLNK(mode):
            raise ValueError(f"Raw path has a symlink parent: {current}")
        if not stat.S_ISDIR(mode):
            raise ValueError(f"Raw path parent is not a directory: {current}")


def _safe_repo_path(root: Path, raw_dir: Path, value: str) -> Path:
    """Return a lexical raw path without resolving its final component."""

    relative_path = Path(value)
    if (
        not value
        or relative_path.is_absolute()
        or ".." in relative_path.parts
    ):
        raise ValueError(f"raw_file must be a non-empty relative path: {value!r}")
    root_resolved = root.resolve()
    raw_resolved = raw_dir.resolve()
    path = root_resolved.joinpath(*relative_path.parts)
    try:
        relative = path.relative_to(raw_resolved)
    except ValueError as error:
        raise ValueError(
            f"raw_file escapes the collector raw directory: {value}"
        ) from error
    if not relative.parts:
        raise ValueError(f"raw_file must identify a file below raw_dir: {value}")
    _reject_symlink_parents(raw_resolved, path)
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
        raw_resolved = raw_dir.resolve()
        path = raw_resolved.joinpath(*relative_path.parts)
        if not relative_path.parts:
            raise ValueError(f"Checksum path must identify a file: {relative}")
        _reject_symlink_parents(raw_resolved, path)
        entries[normalized] = digest
    return entries


def _validate_frozen_archive(
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
        path = raw_dir.resolve().joinpath(*Path(relative).parts)
        _reject_symlink_parents(raw_dir.resolve(), path)
        if not os.path.lexists(path):
            if allow_missing and relative in ledger_relatives:
                continue
            raise FileNotFoundError(f"Manifested raw file is absent: {path}")
        try:
            observed = _sha256_regular_file(path)
        except (OSError, ValueError) as error:
            raise ValueError(
                f"Manifested raw path is not a safe regular file: {path}"
            ) from error
        if observed != expected:
            raise ValueError(
                f"Raw SHA-256 mismatch for {path}: expected {expected}, got {observed}"
            )

    for _, path, relative in row_paths:
        path_present = os.path.lexists(path)
        if not path_present and not allow_missing:
            raise FileNotFoundError(f"Ledger raw_file is absent: {path}")
        if relative not in entries and not allow_unmanifested:
            raise ValueError(f"Ledger raw_file is not in checksum manifest: {relative}")
        if relative not in entries and path_present:
            raise ValueError(
                "Unmanifested acquisition paths must not already exist: "
                f"{relative}"
            )
    return rows


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
    """Validate a frozen archive and expose a typed preflight failure."""

    try:
        return _validate_frozen_archive(
            root=root,
            ledger_path=ledger_path,
            raw_dir=raw_dir,
            manifest_path=manifest_path,
            expected_entries=expected_entries,
            allow_missing=allow_missing,
            allow_unmanifested=allow_unmanifested,
        )
    except FrozenArchiveValidationError:
        raise
    except Exception as error:
        raise FrozenArchiveValidationError(
            f"Frozen archive validation failed: {error}"
        ) from error


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
) -> str:
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
        return "hash_mismatch"
    try:
        os.link(candidate, destination, follow_symlinks=False)
    except FileExistsError as error:
        try:
            destination_hash = _sha256_regular_file(destination)
        except (OSError, ValueError) as validation_error:
            raise FrozenDestinationConflictError(
                f"Cannot safely validate competing raw file: {destination}"
            ) from validation_error
        if destination_hash != expected_hash:
            raise FrozenDestinationConflictError(
                "Competing raw file does not match its frozen SHA-256: "
                f"{destination}"
            ) from error
        candidate.unlink()
        return "concurrent_match"
    if _sha256_regular_file(destination) != expected_hash:
        raise FrozenDestinationConflictError(
            "Promoted raw file does not match its frozen SHA-256: "
            f"{destination}"
        )
    candidate.unlink()
    return "promoted"


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
            with HTTP_ONLY_OPENER.open(request, timeout=timeout_seconds) as response:
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
        size_bytes=len(last_error.encode("utf-8")),
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


def _acquire_ledger_row(
    *,
    root: Path,
    raw_dir: Path,
    row: dict[str, str],
    index: int,
    staging_dir: Path | None,
    user_agent: str,
    timeout_seconds: int,
    retries: int,
    backoff_seconds: float,
    frozen_entries: dict[str, str],
) -> AcquisitionResult:
    """Acquire or reuse one row without mutating manifests or competitors."""

    source_id = _source_id(row, index)
    raw_path = _safe_repo_path(root, raw_dir, row["raw_file"])
    relative = raw_path.relative_to(raw_dir.resolve()).as_posix()
    expected_hash = frozen_entries.get(relative)
    if os.path.lexists(raw_path):
        try:
            observed_hash, observed_size = _inspect_regular_file(raw_path)
        except FileNotFoundError:
            observed_hash = None
            observed_size = 0
        except (OSError, ValueError) as error:
            return AcquisitionResult(
                source_id=source_id,
                url=row["url"],
                status="destination_conflict_cached",
                status_code=None,
                content_type="",
                raw_file=str(raw_path.relative_to(root.resolve())),
                size_bytes=0,
                error=f"Cannot safely validate competing raw file: {error!r}",
                accessed_at=utc_now(),
            )
        if observed_hash is not None and (
            expected_hash is None or observed_hash != expected_hash
        ):
            return AcquisitionResult(
                source_id=source_id,
                url=row["url"],
                status="destination_conflict_cached",
                status_code=None,
                content_type="",
                raw_file=str(raw_path.relative_to(root.resolve())),
                size_bytes=raw_path.lstat().st_size,
                error=(
                    "Competing raw file has no frozen SHA-256."
                    if expected_hash is None
                    else "Competing raw file does not match its frozen SHA-256."
                ),
                accessed_at=utc_now(),
            )
    else:
        observed_hash = None
    if observed_hash is not None:
        metadata = _load_existing_metadata(raw_path)
        original_status = str(
            metadata.get("fetch_status") or metadata.get("status") or ""
        ).strip()
        if not original_status:
            original_status = (
                "error" if raw_path.name.endswith(".error.txt") else "ok"
            )
        status_code_value = metadata.get("status_code")
        try:
            status_code = (
                int(status_code_value)
                if status_code_value not in (None, "")
                else None
            )
        except (TypeError, ValueError):
            status_code = None
        return AcquisitionResult(
            source_id=source_id,
            url=row["url"],
            status=f"cached_{original_status.removeprefix('cached_')}",
            status_code=status_code,
            content_type=str(metadata.get("content_type") or ""),
            raw_file=str(raw_path.relative_to(root.resolve())),
            size_bytes=observed_size,
            error=str(metadata.get("error") or ""),
            accessed_at=utc_now(),
        )

    if staging_dir is None:
        raise RuntimeError("Missing staging directory for pending acquisition")
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

    result_error = fetched.error
    if expected_hash is None:
        status = f"new_source_staged_{fetched.status}"
        final_path = actual_path
    else:
        try:
            promotion = _copy_verified_exclusive(
                actual_path,
                raw_path,
                expected_hash,
            )
        except FrozenDestinationConflictError as error:
            status = f"destination_conflict_staged_{fetched.status}"
            final_path = actual_path
            result_error = "; ".join(
                value for value in (fetched.error, str(error)) if value
            )
        else:
            if promotion == "promoted":
                status = f"recovered_frozen_{fetched.status}"
                final_path = raw_path
            elif promotion == "concurrent_match":
                status = f"recovered_frozen_concurrent_{fetched.status}"
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
        error=result_error,
        accessed_at=fetched.accessed_at,
    )
    _write_metadata_sidecar(
        actual_path,
        result,
        iso3c=row["iso3c"],
        fetch_url=download_url,
    )
    return result


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
        if not os.path.lexists(
            _safe_repo_path(root, raw_dir, row["raw_file"])
        )
    ]
    staging_dir = create_staging_directory(raw_dir) if pending else None
    results: list[AcquisitionResult] = []
    for index, row in enumerate(rows, start=1):
        try:
            result = _acquire_ledger_row(
                root=root,
                raw_dir=raw_dir,
                row=row,
                index=index,
                staging_dir=staging_dir,
                user_agent=user_agent,
                timeout_seconds=timeout_seconds,
                retries=retries,
                backoff_seconds=backoff_seconds,
                frozen_entries=frozen_entries,
            )
        except Exception as error:  # preserve the run before reporting failure
            LOGGER.exception("Acquisition row failed for %s", _source_id(row, index))
            result = AcquisitionResult(
                source_id=_source_id(row, index),
                url=row.get("url", ""),
                status="internal_error",
                status_code=None,
                content_type="",
                raw_file="",
                size_bytes=0,
                error=repr(error),
                accessed_at=utc_now(),
            )
        results.append(result)
    batch = AcquisitionBatch(results=tuple(results), staging_dir=staging_dir)
    if staging_dir is not None:
        try:
            write_json_log(staging_dir / "fetch_log.json", batch.results)
        finally:
            write_staging_manifest(staging_dir)
    return batch


def acquisition_result_is_blocking(result: AcquisitionResult) -> bool:
    """Identify acquisition outcomes that require author review or retry."""

    return (
        result.status.startswith("hash_mismatch_")
        or result.status.startswith("destination_conflict_")
        or result.status == "internal_error"
        or result.status.endswith("_http_error")
        or result.status.endswith("_error")
    )


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
