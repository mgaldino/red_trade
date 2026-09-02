#!/usr/bin/env python3
"""Static and fixture tests for acquisition-only status-evidence collectors."""

from __future__ import annotations

import ast
import argparse
import csv
import hashlib
import importlib.util
import json
import math
import os
import sys
import tempfile
import urllib.request
from email.message import Message
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIAGNOSTICS = ROOT / "scripts" / "diagnostics"
sys.path.insert(0, str(DIAGNOSTICS))

import status_evidence_acquisition as acquisition  # noqa: E402


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")


def expect_error(function, message: str) -> None:
    try:
        function()
    except Exception:
        print(f"PASS: {message}")
        return
    raise AssertionError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def main_calls(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    function = next(
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "main"
    )
    calls: set[str] = set()
    for node in ast.walk(function):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            calls.add(node.func.id)
        elif isinstance(node.func, ast.Attribute):
            calls.add(node.func.attr)
    return calls


def write_fixture_ledger(path: Path, raw_file: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["source_id", "iso3c", "url", "raw_file"],
        )
        writer.writeheader()
        writer.writerow(
            {
                "source_id": "fixture",
                "iso3c": "BRA",
                "url": "https://example.invalid/source",
                "raw_file": raw_file,
            }
        )


def load_collector(path: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load collector: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def run_entrypoint_tests() -> None:
    original_validate = acquisition.validate_frozen_archive
    original_acquire = acquisition.acquire_missing_ledger_files
    try:
        acquisition.validate_frozen_archive = lambda **kwargs: []

        def reject_acquisition(**kwargs):
            raise AssertionError("default main reached the acquisition function")

        acquisition.acquire_missing_ledger_files = reject_acquisition
        for index, filename in enumerate(
            (
                "collect_status_cue_salience_sources.py",
                "collect_ex_top1_salience_sources.py",
            ),
            start=1,
        ):
            collector = load_collector(
                DIAGNOSTICS / filename,
                f"status_evidence_collector_fixture_{index}",
            )
            collector.parse_args = lambda: argparse.Namespace(
                acquire=False,
                timeout=20,
                retries=3,
                backoff=1.0,
            )
            expect(collector.main() == 0, f"{filename} default is read-only")
    finally:
        acquisition.validate_frozen_archive = original_validate
        acquisition.acquire_missing_ledger_files = original_acquire


def run_entrypoint_acquisition_fixture_tests() -> None:
    """Exercise both real ``main(acquire=True)`` integrations without HTTP."""

    original_request = acquisition.request_missing_url

    def fake_request_missing_url(**kwargs):
        acquisition._write_bytes_exclusive(kwargs["output_path"], b"entrypoint")
        return acquisition.AcquisitionResult(
            source_id="",
            url=kwargs["url"],
            status="ok",
            status_code=200,
            content_type="text/html",
            raw_file="",
            size_bytes=len(b"entrypoint"),
            error="",
            accessed_at="2026-09-02T00:00:00+00:00",
        )

    acquisition.request_missing_url = fake_request_missing_url
    try:
        with tempfile.TemporaryDirectory(
            prefix="status_evidence_entrypoints_"
        ) as temp:
            fixture_root = Path(temp)
            for index, filename in enumerate(
                (
                    "collect_status_cue_salience_sources.py",
                    "collect_ex_top1_salience_sources.py",
                ),
                start=1,
            ):
                root = fixture_root / f"collector_{index}"
                raw_dir = root / "data" / "raw" / "fixture"
                raw_dir.mkdir(parents=True)
                ledger = root / "ledger.csv"
                raw_file = "data/raw/fixture/missing.html"
                write_fixture_ledger(ledger, raw_file)
                manifest = raw_dir / "checksums.sha256"
                frozen_manifest = (
                    f"{sha256_bytes(b'entrypoint')}  missing.html\n"
                )
                manifest.write_text(frozen_manifest, encoding="utf-8")

                collector = load_collector(
                    DIAGNOSTICS / filename,
                    f"status_evidence_collector_acquire_fixture_{index}",
                )
                collector.ROOT = root
                collector.RAW_DIR = raw_dir
                collector.EVIDENCE_CSV = ledger
                collector.CHECKSUMS = manifest
                collector.EXPECTED_MANIFEST_ENTRIES = 1
                collector.parse_args = lambda: argparse.Namespace(
                    acquire=True,
                    timeout=1,
                    retries=1,
                    backoff=0.0,
                )
                exit_code = collector.main()
                staging_runs = list(
                    (raw_dir / "acquisition_staging").iterdir()
                )
                expect(
                    exit_code == 0
                    and (raw_dir / "missing.html").read_bytes()
                    == b"entrypoint"
                    and manifest.read_text(encoding="utf-8")
                    == frozen_manifest
                    and len(staging_runs) == 1
                    and (staging_runs[0] / "fetch_log.json").is_file()
                    and (staging_runs[0] / "checksums.sha256").is_file(),
                    f"{filename} --acquire path is covered end to end offline",
                )
    finally:
        acquisition.request_missing_url = original_request


def run_entrypoint_preexisting_conflict_tests() -> None:
    """Require exit code 2 for conflicts present before collector preflight."""

    original_acquire = acquisition.acquire_missing_ledger_files

    def reject_acquisition(**kwargs):
        raise AssertionError("preflight conflict reached acquisition")

    acquisition.acquire_missing_ledger_files = reject_acquisition
    try:
        with tempfile.TemporaryDirectory(
            prefix="status_evidence_preexisting_conflict_"
        ) as temp:
            fixture_root = Path(temp)
            for collector_index, filename in enumerate(
                (
                    "collect_status_cue_salience_sources.py",
                    "collect_ex_top1_salience_sources.py",
                ),
                start=1,
            ):
                for case in (
                    "hash_mismatch",
                    "unmanifested",
                    "symlink_matching",
                    "dangling_symlink",
                ):
                    root = fixture_root / f"collector_{collector_index}_{case}"
                    raw_dir = root / "data" / "raw" / "fixture"
                    raw_dir.mkdir(parents=True)
                    raw_path = raw_dir / "source.html"
                    ledger = root / "ledger.csv"
                    write_fixture_ledger(
                        ledger,
                        "data/raw/fixture/source.html",
                    )
                    manifest = raw_dir / "checksums.sha256"
                    if case == "unmanifested":
                        raw_path.write_bytes(b"conflict")
                        frozen_manifest = ""
                        expected_manifest_entries = 0
                    elif case == "symlink_matching":
                        (raw_dir / "other.html").write_bytes(b"expected")
                        raw_path.symlink_to("other.html")
                        frozen_manifest = (
                            f"{sha256_bytes(b'expected')}  source.html\n"
                            f"{sha256_bytes(b'expected')}  other.html\n"
                        )
                        expected_manifest_entries = 2
                    elif case == "dangling_symlink":
                        raw_path.symlink_to("absent.html")
                        frozen_manifest = (
                            f"{sha256_bytes(b'expected')}  source.html\n"
                        )
                        expected_manifest_entries = 1
                    else:
                        raw_path.write_bytes(b"conflict")
                        frozen_manifest = (
                            f"{sha256_bytes(b'expected')}  source.html\n"
                        )
                        expected_manifest_entries = 1
                    manifest.write_text(frozen_manifest, encoding="utf-8")

                    collector = load_collector(
                        DIAGNOSTICS / filename,
                        (
                            "status_evidence_collector_preexisting_"
                            f"{collector_index}_{case}"
                        ),
                    )
                    collector.ROOT = root
                    collector.RAW_DIR = raw_dir
                    collector.EVIDENCE_CSV = ledger
                    collector.CHECKSUMS = manifest
                    collector.EXPECTED_MANIFEST_ENTRIES = (
                        expected_manifest_entries
                    )
                    collector.parse_args = lambda: argparse.Namespace(
                        acquire=True,
                        timeout=1,
                        retries=1,
                        backoff=0.0,
                    )
                    exit_code = collector.main()
                    if case in {"hash_mismatch", "unmanifested"}:
                        competitor_preserved = (
                            raw_path.read_bytes() == b"conflict"
                        )
                    else:
                        expected_link = (
                            "other.html"
                            if case == "symlink_matching"
                            else "absent.html"
                        )
                        competitor_preserved = (
                            raw_path.is_symlink()
                            and os.readlink(raw_path) == expected_link
                        )
                    expect(
                        exit_code == 2
                        and competitor_preserved
                        and manifest.read_text(encoding="utf-8")
                        == frozen_manifest
                        and not (raw_dir / "acquisition_staging").exists(),
                        (
                            f"{filename} returns 2 for preexisting {case} "
                            "without changing the archive"
                        ),
                    )
    finally:
        acquisition.acquire_missing_ledger_files = original_acquire


def run_entrypoint_preprocessing_race_tests() -> None:
    """Exercise regular and symlink publication before row processing."""

    original_create = acquisition.create_staging_directory
    original_request = acquisition.request_missing_url

    def reject_request(**kwargs):
        raise AssertionError("preprocessing race unexpectedly reached HTTP")

    acquisition.request_missing_url = reject_request
    try:
        with tempfile.TemporaryDirectory(
            prefix="status_evidence_preprocessing_race_"
        ) as temp:
            fixture_root = Path(temp)
            for collector_index, filename in enumerate(
                (
                    "collect_status_cue_salience_sources.py",
                    "collect_ex_top1_salience_sources.py",
                ),
                start=1,
            ):
                for case, expected_exit in (
                    ("matching", 0),
                    ("conflicting", 2),
                    ("unmanifested", 2),
                    ("symlink_matching", 2),
                    ("dangling_symlink", 2),
                ):
                    root = fixture_root / f"collector_{collector_index}_{case}"
                    raw_dir = root / "data" / "raw" / "fixture"
                    raw_dir.mkdir(parents=True)
                    raw_path = raw_dir / "missing.html"
                    ledger = root / "ledger.csv"
                    write_fixture_ledger(
                        ledger,
                        "data/raw/fixture/missing.html",
                    )
                    manifest = raw_dir / "checksums.sha256"
                    if case == "unmanifested":
                        frozen_manifest = ""
                        expected_manifest_entries = 0
                    elif case == "symlink_matching":
                        (raw_dir / "other.html").write_bytes(b"expected")
                        frozen_manifest = (
                            f"{sha256_bytes(b'expected')}  missing.html\n"
                            f"{sha256_bytes(b'expected')}  other.html\n"
                        )
                        expected_manifest_entries = 2
                    else:
                        frozen_manifest = (
                            f"{sha256_bytes(b'expected')}  missing.html\n"
                        )
                        expected_manifest_entries = 1
                    manifest.write_text(frozen_manifest, encoding="utf-8")

                    def create_and_publish(directory):
                        staging = original_create(directory)
                        if case == "matching":
                            raw_path.write_bytes(b"expected")
                        elif case in {"conflicting", "unmanifested"}:
                            raw_path.write_bytes(b"conflict")
                        elif case == "symlink_matching":
                            raw_path.symlink_to("other.html")
                        else:
                            raw_path.symlink_to("absent.html")
                        return staging

                    acquisition.create_staging_directory = create_and_publish
                    collector = load_collector(
                        DIAGNOSTICS / filename,
                        (
                            "status_evidence_collector_preprocessing_race_"
                            f"{collector_index}_{case}"
                        ),
                    )
                    collector.ROOT = root
                    collector.RAW_DIR = raw_dir
                    collector.EVIDENCE_CSV = ledger
                    collector.CHECKSUMS = manifest
                    collector.EXPECTED_MANIFEST_ENTRIES = (
                        expected_manifest_entries
                    )
                    collector.parse_args = lambda: argparse.Namespace(
                        acquire=True,
                        timeout=1,
                        retries=1,
                        backoff=0.0,
                    )
                    exit_code = collector.main()
                    staging_runs = list(
                        (raw_dir / "acquisition_staging").iterdir()
                    )
                    log = json.loads(
                        (staging_runs[0] / "fetch_log.json").read_text(
                            encoding="utf-8"
                        )
                    )
                    expected_status = (
                        "cached_ok"
                        if case == "matching"
                        else "destination_conflict_cached"
                    )
                    if case == "matching":
                        competitor_preserved = (
                            raw_path.read_bytes() == b"expected"
                        )
                    elif case in {"conflicting", "unmanifested"}:
                        competitor_preserved = (
                            raw_path.read_bytes() == b"conflict"
                        )
                    else:
                        expected_link = (
                            "other.html"
                            if case == "symlink_matching"
                            else "absent.html"
                        )
                        competitor_preserved = (
                            raw_path.is_symlink()
                            and os.readlink(raw_path) == expected_link
                        )
                    expect(
                        exit_code == expected_exit
                        and competitor_preserved
                        and manifest.read_text(encoding="utf-8")
                        == frozen_manifest
                        and len(staging_runs) == 1
                        and log[0]["status"] == expected_status
                        and (staging_runs[0] / "checksums.sha256").is_file(),
                        (
                            f"{filename} classifies a {case} pre-row "
                            "publication and returns the contracted exit code"
                        ),
                    )
    finally:
        acquisition.create_staging_directory = original_create
        acquisition.request_missing_url = original_request


def run_fixture_tests() -> None:
    with tempfile.TemporaryDirectory(prefix="status_evidence_python_") as temp:
        root = Path(temp)
        raw_dir = root / "data" / "raw" / "fixture"
        raw_dir.mkdir(parents=True)
        body = raw_dir / "source.html"
        body.write_bytes(b"frozen fixture\n")
        manifest = raw_dir / "checksums.sha256"
        manifest.write_text(
            f"{sha256_bytes(body.read_bytes())}  source.html\n",
            encoding="utf-8",
        )
        ledger = root / "ledger.csv"
        write_fixture_ledger(ledger, "data/raw/fixture/source.html")

        rows = acquisition.validate_frozen_archive(
            root=root,
            ledger_path=ledger,
            raw_dir=raw_dir,
            manifest_path=manifest,
            expected_entries=1,
        )
        expect(len(rows) == 1, "fixture archive and ledger validate")

        alias = raw_dir / "alias.html"
        alias.symlink_to("source.html")
        manifest.write_text(
            f"{sha256_bytes(body.read_bytes())}  alias.html\n",
            encoding="utf-8",
        )
        write_fixture_ledger(ledger, "data/raw/fixture/alias.html")
        expect_error(
            lambda: acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=1,
            ),
            "manifested symlink is rejected even when target bytes match",
        )
        alias.unlink()

        alias.symlink_to("absent.html")
        expect_error(
            lambda: acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=1,
                allow_missing=True,
            ),
            "manifested dangling symlink is a conflict rather than missing",
        )
        alias.unlink()

        parent_target = raw_dir / "parent_target"
        parent_target.mkdir()
        (parent_target / "source.html").write_bytes(body.read_bytes())
        (raw_dir / "linked_parent").symlink_to("parent_target")
        manifest.write_text(
            f"{sha256_bytes(body.read_bytes())}  linked_parent/source.html\n",
            encoding="utf-8",
        )
        write_fixture_ledger(
            ledger,
            "data/raw/fixture/linked_parent/source.html",
        )
        expect_error(
            lambda: acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=1,
            ),
            "raw pointers with symlink parents are rejected",
        )

        original = body.read_bytes()
        manifest.write_text(
            f"{sha256_bytes(original)}  source.html\n",
            encoding="utf-8",
        )
        write_fixture_ledger(ledger, "data/raw/fixture/source.html")
        entries = acquisition.read_checksum_manifest(manifest, raw_dir)
        batch = acquisition.acquire_missing_ledger_files(
            root=root,
            raw_dir=raw_dir,
            rows=rows,
            user_agent="fixture/1.0",
            timeout_seconds=1,
            retries=1,
            backoff_seconds=0,
            frozen_entries=entries,
        )
        expect(
            batch.results[0].status == "cached_ok"
            and batch.staging_dir is None
            and body.read_bytes() == original,
            "present raw files are reused without overwrite",
        )

        body.write_bytes(b"tampered\n")
        expect_error(
            lambda: acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=1,
            ),
            "tampered raw content is rejected",
        )

        body.write_bytes(original)
        write_fixture_ledger(ledger, "data/raw/fixture/../escape.html")
        expect_error(
            lambda: acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=1,
                allow_missing=True,
            ),
            "ledger path traversal is rejected",
        )

        missing = raw_dir / "missing.html"
        manifest.write_text(
            f"{sha256_bytes(b'future')}  missing.html\n",
            encoding="utf-8",
        )
        write_fixture_ledger(ledger, "data/raw/fixture/missing.html")
        rows = acquisition.validate_frozen_archive(
            root=root,
            ledger_path=ledger,
            raw_dir=raw_dir,
            manifest_path=manifest,
            expected_entries=1,
            allow_missing=True,
        )
        expect(
            len(rows) == 1 and not missing.exists(),
            "explicit acquisition mode may validate a manifested missing file",
        )
        original_request = acquisition.request_missing_url
        frozen_manifest = manifest.read_bytes()

        def fake_request_missing_url(**kwargs):
            with kwargs["output_path"].open("xb") as handle:
                handle.write(b"future")
            return acquisition.AcquisitionResult(
                source_id="",
                url=kwargs["url"],
                status="ok",
                status_code=200,
                content_type="text/html",
                raw_file="",
                size_bytes=6,
                error="",
                accessed_at="2026-09-02T00:00:00+00:00",
            )

        acquisition.request_missing_url = fake_request_missing_url
        try:
            batch = acquisition.acquire_missing_ledger_files(
                root=root,
                raw_dir=raw_dir,
                rows=rows,
                user_agent="fixture/1.0",
                timeout_seconds=1,
                retries=1,
                backoff_seconds=0,
                frozen_entries=acquisition.read_checksum_manifest(
                    manifest,
                    raw_dir,
                ),
            )
        finally:
            acquisition.request_missing_url = original_request
        expect(
            batch.results[0].status == "recovered_frozen_ok"
            and missing.read_bytes() == b"future",
            "matching staged bytes restore a manifested missing raw file",
        )
        expect(batch.staging_dir is not None, "acquisition uses a unique staging run")
        expect(
            any(batch.staging_dir.rglob("missing.metadata.json")),
            "new acquisition archives metadata only in staging",
        )
        staging_manifest = batch.staging_dir / "checksums.sha256"
        expect(
            (batch.staging_dir / "fetch_log.json").is_file()
            and staging_manifest.is_file()
            and manifest.read_bytes() == frozen_manifest,
            "run log and staging manifest leave the frozen manifest immutable",
        )
        rows = acquisition.validate_frozen_archive(
            root=root,
            ledger_path=ledger,
            raw_dir=raw_dir,
            manifest_path=manifest,
            expected_entries=1,
        )
        expect(len(rows) == 1, "restored frozen archive validates on the next run")


def run_staging_failure_tests() -> None:
    with tempfile.TemporaryDirectory(prefix="status_evidence_staging_") as temp:
        root = Path(temp)
        raw_dir = root / "data" / "raw" / "fixture"
        raw_dir.mkdir(parents=True)
        manifest = raw_dir / "checksums.sha256"
        manifest.write_text(
            f"{sha256_bytes(b'expected')}  missing.html\n",
            encoding="utf-8",
        )
        ledger = root / "ledger.csv"
        write_fixture_ledger(ledger, "data/raw/fixture/missing.html")
        rows = acquisition.validate_frozen_archive(
            root=root,
            ledger_path=ledger,
            raw_dir=raw_dir,
            manifest_path=manifest,
            expected_entries=1,
            allow_missing=True,
        )
        original_manifest = manifest.read_bytes()
        original_request = acquisition.request_missing_url

        def fake_changed_request(**kwargs):
            with kwargs["output_path"].open("xb") as handle:
                handle.write(b"changed")
            return acquisition.AcquisitionResult(
                source_id="",
                url=kwargs["url"],
                status="ok",
                status_code=200,
                content_type="text/html",
                raw_file="",
                size_bytes=7,
                error="",
                accessed_at="2026-09-02T00:00:00+00:00",
            )

        acquisition.request_missing_url = fake_changed_request
        try:
            batch = acquisition.acquire_missing_ledger_files(
                root=root,
                raw_dir=raw_dir,
                rows=rows,
                user_agent="fixture/1.0",
                timeout_seconds=1,
                retries=1,
                backoff_seconds=0,
                frozen_entries=acquisition.read_checksum_manifest(
                    manifest,
                    raw_dir,
                ),
            )
        finally:
            acquisition.request_missing_url = original_request
        expect(
            batch.results[0].status == "hash_mismatch_staged_ok"
            and not (raw_dir / "missing.html").exists()
            and manifest.read_bytes() == original_manifest,
            "changed recovery stays staged and cannot refreeze the baseline",
        )

        anchor = raw_dir / "anchor.txt"
        anchor.write_bytes(b"anchor")
        manifest.write_text(
            f"{sha256_bytes(b'anchor')}  anchor.txt\n",
            encoding="utf-8",
        )
        write_fixture_ledger(ledger, "data/raw/fixture/new_source.html")
        rows = acquisition.validate_frozen_archive(
            root=root,
            ledger_path=ledger,
            raw_dir=raw_dir,
            manifest_path=manifest,
            expected_entries=1,
            allow_missing=True,
            allow_unmanifested=True,
        )
        original_request = acquisition.request_missing_url
        acquisition.request_missing_url = fake_changed_request
        try:
            batch = acquisition.acquire_missing_ledger_files(
                root=root,
                raw_dir=raw_dir,
                rows=rows,
                user_agent="fixture/1.0",
                timeout_seconds=1,
                retries=1,
                backoff_seconds=0,
                frozen_entries=acquisition.read_checksum_manifest(
                    manifest,
                    raw_dir,
                ),
            )
        finally:
            acquisition.request_missing_url = original_request
        expect(
            batch.results[0].status == "new_source_staged_ok"
            and not (raw_dir / "new_source.html").exists(),
            "new unmanifested sources require a separate authorial refreeze",
        )


def run_batch_finalization_failure_tests() -> None:
    """Keep a complete audit record for conflicts and unexpected row failures."""

    with tempfile.TemporaryDirectory(prefix="status_evidence_finalization_") as temp:
        fixture_root = Path(temp)
        for case in ("destination_conflict", "internal_error"):
            root = fixture_root / case
            raw_dir = root / "data" / "raw" / "fixture"
            raw_dir.mkdir(parents=True)
            raw_path = raw_dir / "missing.html"
            manifest = raw_dir / "checksums.sha256"
            manifest.write_text(
                f"{sha256_bytes(b'expected')}  missing.html\n",
                encoding="utf-8",
            )
            ledger = root / "ledger.csv"
            write_fixture_ledger(ledger, "data/raw/fixture/missing.html")
            rows = acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=1,
                allow_missing=True,
            )
            original_request = acquisition.request_missing_url

            def fake_request(**kwargs):
                if case == "internal_error":
                    raise RuntimeError("fixture row failure")
                kwargs["output_path"].parent.mkdir(parents=True, exist_ok=True)
                kwargs["output_path"].write_bytes(b"expected")
                raw_path.write_bytes(b"competing")
                return acquisition.AcquisitionResult(
                    source_id="",
                    url=kwargs["url"],
                    status="ok",
                    status_code=200,
                    content_type="text/html",
                    raw_file="",
                    size_bytes=8,
                    error="",
                    accessed_at="2026-09-02T00:00:00+00:00",
                )

            acquisition.request_missing_url = fake_request
            try:
                batch = acquisition.acquire_missing_ledger_files(
                    root=root,
                    raw_dir=raw_dir,
                    rows=rows,
                    user_agent="fixture/1.0",
                    timeout_seconds=1,
                    retries=1,
                    backoff_seconds=0,
                    frozen_entries=acquisition.read_checksum_manifest(
                        manifest,
                        raw_dir,
                    ),
                )
            finally:
                acquisition.request_missing_url = original_request
            result = batch.results[0]
            expect(
                batch.staging_dir is not None
                and (batch.staging_dir / "fetch_log.json").is_file()
                and (batch.staging_dir / "checksums.sha256").is_file(),
                f"{case} finalizes the immutable staging log and manifest",
            )
            if case == "destination_conflict":
                expect(
                    result.status == "destination_conflict_staged_ok"
                    and acquisition.acquisition_result_is_blocking(result)
                    and raw_path.read_bytes() == b"competing",
                    "competing unexpected destination is classified and preserved",
                )
            else:
                expect(
                    result.status == "internal_error"
                    and acquisition.acquisition_result_is_blocking(result)
                    and not raw_path.exists(),
                    "unexpected row failure is blocking and publishes no raw file",
                )


def run_validation_edge_tests() -> None:
    with tempfile.TemporaryDirectory(prefix="status_evidence_edges_") as temp:
        root = Path(temp)
        raw_dir = root / "data" / "raw" / "fixture"
        raw_dir.mkdir(parents=True)
        body = raw_dir / "source.html"
        body.write_bytes(b"error body")
        metadata = raw_dir / "source.metadata.json"
        metadata.write_text(
            json.dumps(
                {
                    "fetch_status": "http_error",
                    "status_code": 404,
                    "content_type": "text/html",
                    "error": "HTTP 404",
                }
            ),
            encoding="utf-8",
        )
        manifest = raw_dir / "checksums.sha256"
        manifest.write_text(
            f"{sha256_bytes(body.read_bytes())}  source.html\n",
            encoding="utf-8",
        )
        ledger = root / "ledger.csv"
        write_fixture_ledger(ledger, "data/raw/fixture/source.html")
        rows = acquisition.validate_frozen_archive(
            root=root,
            ledger_path=ledger,
            raw_dir=raw_dir,
            manifest_path=manifest,
            expected_entries=1,
        )
        batch = acquisition.acquire_missing_ledger_files(
            root=root,
            raw_dir=raw_dir,
            rows=rows,
            user_agent="fixture/1.0",
            timeout_seconds=1,
            retries=1,
            backoff_seconds=0,
            frozen_entries=acquisition.read_checksum_manifest(manifest, raw_dir),
        )
        expect(
            batch.results[0].status == "cached_http_error"
            and batch.results[0].status_code == 404,
            "cached status comes from metadata rather than the filename",
        )

        original_manifest = manifest.read_text(encoding="utf-8")
        manifest.write_text(
            original_manifest
            + f"{sha256_bytes(b'ghost')}  unowned_metadata.json\n",
            encoding="utf-8",
        )
        expect_error(
            lambda: acquisition.validate_frozen_archive(
                root=root,
                ledger_path=ledger,
                raw_dir=raw_dir,
                manifest_path=manifest,
                expected_entries=2,
                allow_missing=True,
            ),
            "acquisition mode rejects missing non-ledger manifest entries",
        )
        manifest.write_text(original_manifest, encoding="utf-8")

        for invalid_url in (
            "file:///tmp/source",
            "https://-",
            "http://user@",
            "https://example.com:bad",
            "https://example.com/ bad",
            "https://example.com/%zz",
            "https://example.com/\x7f",
            "https://example.com/\x80",
            "https://example.com/<",
            "https://example.com/é",
            "https://example.com/[raw]",
            "https://example.com/?q=[raw]",
            "https://example.com/#a#b",
            "http://[::1]/source",
            "https://001.002.003.004/source",
        ):
            expect_error(
                lambda value=invalid_url: acquisition.validate_http_url(value),
                f"invalid acquisition URL is rejected: {invalid_url}",
            )
        expect(
            acquisition.validate_http_url(
                "https://example.com/a%5Bb%5D?x=1/2?3#valid/fragment?"
            )
            == "https://example.com/a%5Bb%5D?x=1/2?3#valid/fragment?",
            "component-valid percent-encoded HTTP URI is accepted",
        )
        redirect_handler = acquisition.HttpOnlyRedirectHandler()
        redirect_request = urllib.request.Request("https://example.com/start")
        expect_error(
            lambda: redirect_handler.redirect_request(
                redirect_request,
                None,
                302,
                "Found",
                Message(),
                "ftp://example.com/file",
            ),
            "redirects outside HTTP(S) are rejected before opening",
        )
        redirected = redirect_handler.redirect_request(
            redirect_request,
            None,
            302,
            "Found",
            Message(),
            "https://example.com/next",
        )
        expect(
            redirected.full_url == "https://example.com/next",
            "valid HTTPS redirects remain available",
        )
        expect_error(
            lambda: acquisition.validate_acquisition_options(
                timeout_seconds=0,
                retries=1,
                backoff_seconds=0,
            ),
            "nonpositive timeout is rejected",
        )
        expect_error(
            lambda: acquisition.validate_acquisition_options(
                timeout_seconds=1,
                retries=0,
                backoff_seconds=0,
            ),
            "zero retries is rejected",
        )
        expect_error(
            lambda: acquisition.validate_acquisition_options(
                timeout_seconds=1,
                retries=1,
                backoff_seconds=-1,
            ),
            "negative backoff is rejected",
        )
        for nonfinite in (math.nan, math.inf, -math.inf):
            expect_error(
                lambda value=nonfinite: acquisition.validate_acquisition_options(
                    timeout_seconds=1,
                    retries=1,
                    backoff_seconds=value,
                ),
                f"non-finite backoff {nonfinite!r} is rejected",
            )
        existing_log = root / "fetch_log.json"
        acquisition.write_json_log(existing_log, batch.results)
        expect_error(
            lambda: acquisition.write_json_log(existing_log, batch.results),
            "run-scoped logs cannot be overwritten",
        )
        protected = root / "protected.raw"
        protected.write_bytes(b"original")
        expect_error(
            lambda: acquisition._write_bytes_exclusive(protected, b"replacement"),
            "exclusive raw writes reject a competing existing file",
        )
        expect(
            protected.read_bytes() == b"original",
            "exclusive raw write failure preserves existing bytes",
        )

        class FailingStream:
            def __init__(self) -> None:
                self.calls = 0

            def read(self, size: int) -> bytes:
                self.calls += 1
                if self.calls == 1:
                    return b"partial"
                raise OSError("fixture stream failure")

        failed_stream_target = root / "failed_stream.raw"
        expect_error(
            lambda: acquisition._write_stream_exclusive(
                failed_stream_target,
                FailingStream(),
            ),
            "failed stream publication raises without publishing a raw file",
        )
        expect(
            not failed_stream_target.exists()
            and any(root.glob(".failed_stream.raw.partial-*")),
            "failed stream keeps only a uniquely named partial audit artifact",
        )
        expect_error(
            lambda: acquisition._write_stream_exclusive(
                protected,
                type("Stream", (), {"read": lambda self, size: b""})(),
            ),
            "stream publication cannot replace a competing raw file",
        )
        expect(
            protected.read_bytes() == b"original",
            "stream publication failure never removes the competing file",
        )

        copy_source = root / "copy_source.raw"
        copy_source.write_bytes(b"candidate")
        expect_error(
            lambda: acquisition._copy_verified_exclusive(
                copy_source,
                protected,
                sha256_bytes(b"candidate"),
            ),
            "verified promotion cannot replace a competing raw file",
        )
        expect(
            protected.read_bytes() == b"original",
            "verified promotion failure never removes the competing file",
        )
        mismatch_target = root / "mismatch.raw"
        expect(
            acquisition._copy_verified_exclusive(
                copy_source,
                mismatch_target,
                sha256_bytes(b"different"),
            )
            == "hash_mismatch"
            and not mismatch_target.exists(),
            "hash-mismatched bytes are never published to the frozen path",
        )
        concurrent_match = root / "concurrent_match.raw"
        concurrent_match.write_bytes(b"candidate")
        expect(
            acquisition._copy_verified_exclusive(
                copy_source,
                concurrent_match,
                sha256_bytes(b"candidate"),
            )
            == "concurrent_match"
            and concurrent_match.read_bytes() == b"candidate",
            "matching concurrent publication is classified and preserved",
        )


def run_source_tests() -> None:
    forbidden_main_calls = {
        "aggregate_country_codes",
        "build_ex_top1_country_codes_candidate",
        "write_csv",
        "write_sources_yaml",
        "write_data_dictionary",
        "write_collection_log",
        "write_checksum_manifest",
        "write_checksums",
        "run_gdelt_queries",
    }
    for filename in (
        "collect_status_cue_salience_sources.py",
        "collect_ex_top1_salience_sources.py",
    ):
        path = DIAGNOSTICS / filename
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
        calls = main_calls(path)
        expect(
            not calls.intersection(forbidden_main_calls),
            f"{filename} main is acquisition-only",
        )
        expect(
            "acquire_missing_ledger_files" in calls,
            f"{filename} delegates raw acquisition to the shared helper",
        )

    status_rows = acquisition.validate_frozen_archive(
        root=ROOT,
        ledger_path=ROOT
        / "data"
        / "processed"
        / "status_cue_salience"
        / "status_cue_source_evidence.csv",
        raw_dir=ROOT / "data" / "raw" / "status_cue_salience",
        manifest_path=ROOT
        / "data"
        / "raw"
        / "status_cue_salience"
        / "checksums.sha256",
        expected_entries=89,
    )
    ex_rows = acquisition.validate_frozen_archive(
        root=ROOT,
        ledger_path=ROOT
        / "data"
        / "processed"
        / "ex_top1_salience"
        / "ex_top1_source_evidence.csv",
        raw_dir=ROOT / "data" / "raw" / "ex_top1_salience",
        manifest_path=ROOT
        / "data"
        / "raw"
        / "ex_top1_salience"
        / "checksums.sha256",
        expected_entries=48,
    )
    expect(len(status_rows) == 21, "status source ledger has 21 frozen rows")
    expect(len(ex_rows) == 22, "former-incumbent ledger has 22 frozen rows")


if __name__ == "__main__":
    run_source_tests()
    run_entrypoint_tests()
    run_entrypoint_acquisition_fixture_tests()
    run_entrypoint_preexisting_conflict_tests()
    run_entrypoint_preprocessing_race_tests()
    run_fixture_tests()
    run_staging_failure_tests()
    run_batch_finalization_failure_tests()
    run_validation_edge_tests()
    print("ALL_STATIC_STATUS_EVIDENCE_PYTHON_TESTS_PASSED")
