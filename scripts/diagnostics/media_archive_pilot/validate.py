#!/usr/bin/env python3
"""Validate pilot schemas, counts, fidelity and raw-only reprocessing."""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlsplit


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def as_bool(value: str) -> bool:
    if value not in {"true", "false"}:
        raise ValueError(f"Expected lowercase boolean, found {value!r}")
    return value == "true"


def normalized_raw_text(path: Path) -> str:
    value = path.read_text(encoding="utf-8", errors="replace")
    value = html.unescape(value)
    return re.sub(r"\s+", " ", value)


def verify_fidelity(row: dict[str, str], raw_dir: Path) -> bool:
    raw_path = raw_dir / row["source_raw_relative_path"]
    if not raw_path.is_file():
        return False
    if raw_path.suffix == ".json":
        with raw_path.open(encoding="utf-8") as handle:
            items = json.load(handle)
        matching = [item for item in items if str(item.get("id", "")) == row["original_id"]]
        if len(matching) != 1:
            return False
        rendered = html.unescape((matching[0].get("title") or {}).get("rendered", ""))
        rendered = re.sub(r"<[^>]+>", " ", rendered)
        title_ok = re.sub(r"\s+", " ", rendered).strip() == row["title_original"]
        date_ok = (matching[0].get("date") or matching[0].get("date_gmt") or "")[:10] == row["requested_date"]
        url_ok = urlsplit(matching[0].get("link", "")).path == urlsplit(row["original_url"]).path
        return title_ok and date_ok and url_ok
    raw_text = normalized_raw_text(raw_path)
    title_ok = row["title_original"] in raw_text
    url_ok = urlsplit(row["original_url"]).path in raw_text
    date_ok = row["publication_date"] == row["requested_date"]
    return title_ok and url_ok and date_ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=SCRIPT_DIR / "pilot_config.json")
    parser.add_argument("--raw-dir", type=Path, default=None)
    parser.add_argument("--processed-dir", type=Path, default=None)
    parser.add_argument("--report-dir", type=Path, default=REPO_ROOT / "quality_reports" / "media_archive_pilot")
    args = parser.parse_args()
    with args.config.open(encoding="utf-8") as handle:
        config = json.load(handle)
    raw_dir = (args.raw_dir or REPO_ROOT / "data" / "raw" / "media_archive_pilot" / config["run_date"]).resolve()
    processed_dir = (args.processed_dir or REPO_ROOT / "data" / "processed" / "media_archive_pilot" / config["run_date"]).resolve()
    report_path = processed_dir / "validation_report.json"
    checks_path = processed_dir / "validation_checks.csv"
    if report_path.exists() or checks_path.exists():
        raise FileExistsError("Refusing to overwrite existing validation outputs")

    records_path = processed_dir / "records.csv"
    diagnostics_path = processed_dir / "diagnostics.csv"
    fidelity_path = processed_dir / "fidelity_sample.csv"
    records = read_csv(records_path)
    diagnostics = read_csv(diagnostics_path)
    fidelity = read_csv(fidelity_path)
    checks: list[dict[str, str]] = []

    def check(name: str, condition: bool, detail: str) -> None:
        checks.append({"check": name, "result": "PASS" if condition else "FAIL", "detail": detail})

    expected_pairs = {
        (source["source_id"], requested_date)
        for source in config["sources"]
        for requested_date in config["fixed_dates"]
    }
    actual_pairs = {(row["source_id"], row["requested_date"]) for row in diagnostics}
    check("diagnostic_shape", len(diagnostics) == 20 and actual_pairs == expected_pairs, f"rows={len(diagnostics)}; unique_pairs={len(actual_pairs)}")
    check("record_scope", all((row["source_id"], row["requested_date"]) in expected_pairs for row in records), f"rows={len(records)}")
    check("record_required_fields", all(row["title_original"] and row["original_url"] and row["publication_date"] for row in records), "title, URL and publication date are non-empty")
    check("title_only_dictionary", all(row["mention_matches"] == "" or row["title_original"] for row in records), "mention flags are stored only with title_original")
    mention_errors: list[str] = []
    dictionaries = config["mention_dictionaries"]
    for row in records:
        dictionary = dictionaries[row["source_id"]]
        if "inherits" in dictionary:
            dictionary = dictionaries[dictionary["inherits"]]
        matches: list[str] = []
        flags: dict[str, bool] = {}
        ambiguous = False
        for entity in ("china", "usa"):
            flags[entity] = False
            for variant in dictionary[entity]:
                if re.search(variant["regex"], row["title_original"]):
                    flags[entity] = True
                    ambiguous = ambiguous or bool(variant["ambiguous"])
                    matches.append(f"{entity}:{variant['label']}")
        if (
            as_bool(row["china_mention_title"]) != flags["china"]
            or as_bool(row["usa_mention_title"]) != flags["usa"]
            or as_bool(row["mention_ambiguity"]) != ambiguous
            or row["mention_matches"] != "|".join(matches)
        ):
            mention_errors.append(f"{row['source_id']}:{row['requested_date']}:{row['original_url']}")
    check("mention_dictionary_recomputed", not mention_errors, f"errors={len(mention_errors)}; scope=title_original")

    groups: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in records:
        groups[(row["source_id"], row["requested_date"])].append(row)
    count_mismatches: list[str] = []
    flag_errors: list[str] = []
    for diagnostic in diagnostics:
        key = (diagnostic["source_id"], diagnostic["requested_date"])
        group = [row for row in groups[key] if as_bool(row["date_matches_requested"])]
        if diagnostic["records_before_dedup"] != "":
            expected_before = int(diagnostic["records_before_dedup"])
            expected_after = int(diagnostic["records_after_dedup"])
            if expected_before != len(group) or expected_after != sum(as_bool(row["dedup_keep"]) for row in group):
                count_mismatches.append(f"{key}:diagnostic")
        seen_urls: set[str] = set()
        seen_ids: set[str] = set()
        seen_titles: set[str] = set()
        for row in group:
            title_key = re.sub(r"\s+", " ", row["title_original"].casefold()).strip()
            expected_url = bool(row["normalized_url"] and row["normalized_url"] in seen_urls)
            expected_id = bool(row["original_id"] and row["original_id"] in seen_ids)
            expected_title = bool(title_key and title_key in seen_titles)
            if as_bool(row["duplicate_url"]) != expected_url or as_bool(row["duplicate_original_id"]) != expected_id or as_bool(row["possible_duplicate_title"]) != expected_title or as_bool(row["dedup_keep"]) != (not (expected_url or expected_id)):
                flag_errors.append(f"{key}:{row['original_url']}")
            if row["normalized_url"]:
                seen_urls.add(row["normalized_url"])
            if row["original_id"]:
                seen_ids.add(row["original_id"])
            if title_key:
                seen_titles.add(title_key)
    check("diagnostic_counts", not count_mismatches, "; ".join(count_mismatches) or "before/after counts reconcile")
    check("deduplication_rules", not flag_errors, f"errors={len(flag_errors)}")

    absent_failure_errors = [
        f"{row['source_id']}:{row['requested_date']}"
        for row in diagnostics
        if row["absence_type"] in {"access_failure", "access_or_extraction_failure"}
        and (row["records_before_dedup"] == "0" or row["records_after_dedup"] == "0")
    ]
    check("failures_not_zero", not absent_failure_errors, "; ".join(absent_failure_errors) or "failed acquisitions use blank counts")
    check("classification_domain", all(row["status"] in {"adequado", "parcial", "bloqueado", "inconclusivo"} and row["status_justification"] for row in diagnostics), "all 20 tests are classified with justification")
    adequate_errors = [
        f"{row['source_id']}:{row['requested_date']}"
        for row in diagnostics
        if row["status"] == "adequado" and row["pagination_complete"] != "true"
    ]
    check("adequate_has_complete_enumeration", not adequate_errors, "; ".join(adequate_errors) or "all adequate tests reached an explicit endpoint")

    fidelity_failures = [f"{row['source_id']}:{row['requested_date']}" for row in fidelity if not verify_fidelity(row, raw_dir)]
    check("fidelity_saved_sources", bool(fidelity) and not fidelity_failures, f"sample_rows={len(fidelity)}; failures={len(fidelity_failures)}")

    deterministic_files = ["records.csv", "diagnostics.csv", "fidelity_sample.csv", "request_manifest.csv", "source_manifest.csv"]
    reproduction_differences: list[str] = []
    with tempfile.TemporaryDirectory(prefix="media-archive-reprocess-") as temp_dir:
        reproduced = Path(temp_dir) / "processed"
        command = [
            sys.executable,
            str(SCRIPT_DIR / "process.py"),
            "--config",
            str(args.config.resolve()),
            "--raw-dir",
            str(raw_dir),
            "--output-dir",
            str(reproduced),
            "--report-dir",
            str(args.report_dir.resolve()),
        ]
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            reproduction_differences.append(f"process.py failed: {completed.stderr.strip()}")
        else:
            for filename in deterministic_files:
                if sha256_file(processed_dir / filename) != sha256_file(reproduced / filename):
                    reproduction_differences.append(filename)
    check("raw_only_reprocessing", not reproduction_differences, "; ".join(reproduction_differences) or "all deterministic outputs are byte-identical")

    overall = "PASS" if all(row["result"] == "PASS" for row in checks) else "FAIL"
    with checks_path.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["check", "result", "detail"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(checks)
    with report_path.open("x", encoding="utf-8") as handle:
        json.dump(
            {
                "schema_version": "1.0.0",
                "overall": overall,
                "checks_passed": sum(row["result"] == "PASS" for row in checks),
                "checks_total": len(checks),
                "downloads_repeated": False,
                "deterministic_files_compared": deterministic_files,
                "checks": checks,
            },
            handle,
            ensure_ascii=False,
            indent=2,
        )
        handle.write("\n")
    print(f"Validation {overall}: {sum(row['result'] == 'PASS' for row in checks)}/{len(checks)} checks passed")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
