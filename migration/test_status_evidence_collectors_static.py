#!/usr/bin/env python3
"""Static and fixture tests for acquisition-only status-evidence collectors."""

from __future__ import annotations

import ast
import csv
import hashlib
import sys
import tempfile
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

        original = body.read_bytes()
        results = acquisition.acquire_missing_ledger_files(
            root=root,
            raw_dir=raw_dir,
            rows=rows,
            user_agent="fixture/1.0",
            timeout_seconds=1,
            retries=1,
            backoff_seconds=0,
        )
        expect(
            results[0].status == "cached_ok" and body.read_bytes() == original,
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

        def fake_request_missing_url(**kwargs):
            kwargs["output_path"].write_bytes(b"future")
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
            results = acquisition.acquire_missing_ledger_files(
                root=root,
                raw_dir=raw_dir,
                rows=rows,
                user_agent="fixture/1.0",
                timeout_seconds=1,
                retries=1,
                backoff_seconds=0,
            )
        finally:
            acquisition.request_missing_url = original_request
        expect(
            results[0].status == "ok" and missing.read_bytes() == b"future",
            "stubbed missing acquisition writes a new raw body",
        )
        expect(
            (raw_dir / "missing.metadata.json").is_file(),
            "new acquisition archives a metadata sidecar",
        )


def run_source_tests() -> None:
    forbidden_main_calls = {
        "aggregate_country_codes",
        "build_ex_top1_country_codes_candidate",
        "write_csv",
        "write_sources_yaml",
        "write_data_dictionary",
        "write_collection_log",
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
    run_fixture_tests()
    print("ALL_STATIC_STATUS_EVIDENCE_PYTHON_TESTS_PASSED")
