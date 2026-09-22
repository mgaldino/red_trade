#!/usr/bin/env python3
"""Collect and tabulate Australia's 2006-2009 public trade-rank cues.

The workflow is deliberately separate from treatment coding and the targets
pipeline. It preserves new web responses in an immutable run directory, reuses
three older raw files only after hash verification, and writes one row per
document to a dedicated processed CSV.

Examples
--------
python3 scripts/diagnostics/collect_australia_public_cue_2006_2009.py \
  --collect --build --validate \
  --run-dir data/raw/status_cue_salience/AUS/australia_media_search/RUN_ID

python3 scripts/diagnostics/collect_australia_public_cue_2006_2009.py \
  --build --validate \
  --run-dir data/raw/status_cue_salience/AUS/australia_media_search/RUN_ID
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import logging
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = Path(__file__).with_name(
    "australia_public_cue_2006_2009_manifest.json"
)
RAW_ROOT = ROOT / "data/raw/status_cue_salience"
OUTPUT_PATH = (
    ROOT
    / "data/processed/status_cue_salience/"
    / "australia_public_cue_media_2006_2009.csv"
)
CHECKSUM_PATH = RAW_ROOT / "checksums.sha256"
USER_AGENT = "RDDTradeResearch/1.0 (Australia public-cue source audit)"
LOG = logging.getLogger(__name__)

CSV_COLUMNS = [
    "source_id",
    "publication_date",
    "source_name",
    "source_type",
    "title",
    "url",
    "archive_url",
    "raw_file",
    "raw_sha256",
    "accessed_at",
    "access_status",
    "robots_status",
    "robots_file",
    "content_verification_status",
    "verification_markers_present",
    "rank_position_china",
    "displaced_partner",
    "metric_scope",
    "flow_components",
    "goods_services_scope",
    "reference_period_type",
    "reference_period",
    "explicit_rank_language",
    "positive_broad_cue",
    "strict_m2_goods_only",
    "excerpt_under_25_words",
    "interpretation",
    "confidence",
    "query_used",
    "notes",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def save_json_new(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def load_manifest() -> dict:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    sources = manifest.get("sources", [])
    if len(sources) != 8:
        raise ValueError(f"Expected 8 manifest sources, found {len(sources)}")
    ids = [source["source_id"] for source in sources]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate source_id in manifest")
    return manifest


def request(url: str, path: Path, accessed_at: str) -> dict:
    """Fetch one public URL without overwrite, retrying transient errors."""
    if path.exists():
        raise FileExistsError(path)
    metadata = {
        "url": url,
        "accessed_at": accessed_at,
        "raw_file": "",
        "sha256": "",
    }
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as response:
                body = response.read()
                metadata.update(
                    status_code=response.status,
                    content_type=response.headers.get("Content-Type", ""),
                    final_url=response.url,
                )
            with path.open("xb") as handle:
                handle.write(body)
            metadata.update(
                fetch_status="ok",
                raw_file=relative(path),
                sha256=sha256(path),
                size_bytes=len(body),
            )
            lower = body[:20000].lower()
            if any(
                token in lower
                for token in (
                    b"cf-chl-",
                    b"challenge-platform",
                    b"verify you are human",
                    b"just a moment...",
                )
            ):
                metadata["fetch_status"] = "access_challenge_stop"
            return metadata
        except urllib.error.HTTPError as error:
            if error.code >= 500 and attempt < 2:
                time.sleep(2 ** (attempt + 1))
                continue
            body = error.read()
            metadata.update(
                fetch_status="http_error",
                status_code=error.code,
                error=str(error),
            )
            if body:
                with path.open("xb") as handle:
                    handle.write(body)
                metadata.update(
                    raw_file=relative(path),
                    sha256=sha256(path),
                    size_bytes=len(body),
                )
            return metadata
        except Exception as error:  # urllib wraps DNS/TLS/socket errors variably.
            metadata.update(fetch_status="network_error", error=repr(error))
            if "CERTIFICATE_VERIFY_FAILED" in repr(error):
                command = [
                    "/usr/bin/curl",
                    "--silent",
                    "--show-error",
                    "--location",
                    "--max-time",
                    "30",
                    "--user-agent",
                    USER_AGENT,
                    "--write-out",
                    "\n%{http_code}\n%{content_type}\n%{url_effective}",
                    url,
                ]
                response = subprocess.run(command, capture_output=True)
                if response.returncode == 0:
                    body, status, content_type, final_url = response.stdout.rsplit(
                        b"\n", 3
                    )
                    with path.open("xb") as handle:
                        handle.write(body)
                    status_code = int(status)
                    metadata.update(
                        transport="macos_curl_system_trust",
                        status_code=status_code,
                        content_type=content_type.decode(errors="replace"),
                        final_url=final_url.decode(errors="replace"),
                        fetch_status="ok" if status_code == 200 else "http_error",
                        raw_file=relative(path),
                        sha256=sha256(path),
                        size_bytes=len(body),
                    )
                    return metadata
                metadata["curl_error"] = response.stderr.decode(errors="replace")
                return metadata
            if attempt < 2:
                time.sleep(2 ** (attempt + 1))
    return metadata


def collect(manifest: dict, run_dir: Path) -> list[dict]:
    run_dir.mkdir(parents=True, exist_ok=False)
    save_json_new(run_dir / "manifest.json", manifest)
    accessed_at = utc_now()
    robots_by_host: dict[str, dict] = {}
    results: list[dict] = []

    for source in manifest["sources"]:
        source_id = source["source_id"]
        if source["acquisition_mode"] == "existing_raw":
            raw_path = ROOT / source["existing_raw_file"]
            observed = sha256(raw_path)
            if observed != source["expected_sha256"]:
                raise ValueError(
                    f"Hash mismatch for {source_id}: {observed} != "
                    f"{source['expected_sha256']}"
                )
            result = {
                "source_id": source_id,
                "url": source["url"],
                "fetch_status": "existing_raw_verified",
                "status_code": 200,
                "content_type": "preserved_local_raw",
                "accessed_at": source["existing_accessed_at"],
                "raw_file": source["existing_raw_file"],
                "sha256": observed,
                "size_bytes": raw_path.stat().st_size,
                "robots_status": "not_applicable_existing_raw",
                "robots_file": "",
            }
        else:
            parts = urllib.parse.urlsplit(source["url"])
            host = f"{parts.scheme}://{parts.netloc}"
            if host not in robots_by_host:
                robots_path = run_dir / (
                    parts.netloc.replace(".", "_") + "_robots.txt"
                )
                robots_by_host[host] = request(
                    host + "/robots.txt", robots_path, accessed_at
                )
                time.sleep(1)

            robots_result = robots_by_host[host]
            robots_status = robots_result["fetch_status"]
            permitted = False
            if robots_status == "ok":
                parser = urllib.robotparser.RobotFileParser()
                robots_text = (ROOT / robots_result["raw_file"]).read_text(
                    encoding="utf-8", errors="replace"
                )
                parser.parse(robots_text.splitlines())
                permitted = parser.can_fetch(USER_AGENT, source["url"])
                robots_status = "allowed" if permitted else "disallowed_stop"
            elif robots_result.get("status_code") in (404, 410):
                permitted = True
                robots_status = "no_robots_file"
            else:
                robots_status = "robots_unavailable_stop"

            if permitted:
                result = request(
                    source["url"], run_dir / f"{source_id}.html", accessed_at
                )
            else:
                result = {
                    "url": source["url"],
                    "fetch_status": robots_status,
                    "accessed_at": accessed_at,
                    "raw_file": "",
                    "sha256": "",
                }
            result.update(
                source_id=source_id,
                robots_status=robots_status,
                robots_file=robots_result.get("raw_file", ""),
            )

        results.append(result)
        save_json_new(run_dir / f"{source_id}.metadata.json", result)
        LOG.info(
            "%s: %s (%s)",
            source_id,
            result["fetch_status"],
            result["robots_status"],
        )
        time.sleep(1)

    save_json_new(run_dir / "fetch_results.json", results)
    save_json_new(run_dir / "robots_results.json", robots_by_host)
    return results


class VisibleTextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style", "svg"}:
            self.skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "svg"}:
            self.skip_depth = max(0, self.skip_depth - 1)

    def handle_data(self, data: str) -> None:
        if self.skip_depth == 0:
            self.parts.append(data)


def normalize(value: str) -> str:
    # Some preserved DFAT fallbacks are Markdown, while direct pages are HTML.
    # Removing emphasis markers makes semantic marker checks transport-neutral.
    return re.sub(r"\s+", " ", html.unescape(value).replace("**", "")).strip()


def source_text(source: dict, raw_path: Path) -> str:
    raw = raw_path.read_text(encoding="utf-8", errors="replace")
    if source["verification_mode"] == "raw_text":
        return normalize(raw)
    parser = VisibleTextParser()
    parser.feed(raw)
    return normalize(" ".join(parser.parts))


def markers_present(source: dict, raw_path: Path) -> bool:
    text = source_text(source, raw_path)
    return all(normalize(marker) in text for marker in source["verification_markers"])


def result_map(run_dir: Path) -> dict[str, dict]:
    results = json.loads((run_dir / "fetch_results.json").read_text(encoding="utf-8"))
    return {result["source_id"]: result for result in results}


def build(manifest: dict, run_dir: Path) -> list[dict[str, str]]:
    results = result_map(run_dir)
    rows: list[dict[str, str]] = []
    for source in manifest["sources"]:
        result = results[source["source_id"]]
        archived = result["fetch_status"] in {"ok", "existing_raw_verified"}
        browser_only = (
            source.get("allow_unarchived_browser_verification") is True
            and result["fetch_status"] == "robots_unavailable_stop"
        )
        if not (archived or browser_only):
            raise ValueError(
                f"Cannot build: {source['source_id']} status is "
                f"{result['fetch_status']}"
            )
        if archived:
            raw_path = ROOT / result["raw_file"]
            observed = sha256(raw_path)
            if observed != result["sha256"]:
                raise ValueError(f"Raw hash changed for {source['source_id']}")
            verified = markers_present(source, raw_path)
            if not verified:
                missing = [
                    marker
                    for marker in source["verification_markers"]
                    if normalize(marker) not in source_text(source, raw_path)
                ]
                raise ValueError(
                    f"Verification marker failure for {source['source_id']}: {missing}"
                )
            raw_file = result["raw_file"]
            raw_sha256 = observed
            verification_status = "verified_from_hash_checked_raw"
            marker_status = "true"
        else:
            raw_file = ""
            raw_sha256 = ""
            verification_status = (
                "verified_independently_in_browser_2026-09-22; "
                "article_raw_not_archived_after_robots_stop"
            )
            marker_status = "not_tested_no_article_raw"
        row = {column: "" for column in CSV_COLUMNS}
        for column in CSV_COLUMNS:
            if column in source:
                value = source[column]
                row[column] = str(value).lower() if isinstance(value, bool) else str(value)
        row.update(
            raw_file=raw_file,
            raw_sha256=raw_sha256,
            accessed_at=result["accessed_at"],
            access_status=result["fetch_status"],
            robots_status=result["robots_status"],
            robots_file=result.get("robots_file", ""),
            content_verification_status=verification_status,
            verification_markers_present=marker_status,
        )
        rows.append(row)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT_PATH.with_suffix(".csv.tmp")
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, OUTPUT_PATH)
    update_checksums()
    return rows


def update_checksums() -> None:
    files = sorted(
        path
        for path in RAW_ROOT.rglob("*")
        if path.is_file() and path != CHECKSUM_PATH
    )
    lines = [f"{sha256(path)}  {path.relative_to(RAW_ROOT).as_posix()}\n" for path in files]
    temporary = CHECKSUM_PATH.with_suffix(".sha256.tmp")
    temporary.write_text("".join(lines), encoding="utf-8")
    os.replace(temporary, CHECKSUM_PATH)


def count_words(value: str) -> int:
    return len(re.findall(r"\b[\w$.-]+\b", value, flags=re.UNICODE))


def validate_coded_rows(
    rows: list[dict[str, str]], manifest: dict, results: dict[str, dict]
) -> dict:
    """Check coded fields against the manifest and central time/metric claims."""
    source_by_id = {
        source["source_id"]: source for source in manifest["sources"]
    }
    if len(rows) != 8:
        raise ValueError(f"Expected 8 CSV rows, found {len(rows)}")
    expected_order = [source["source_id"] for source in manifest["sources"]]
    observed_order = [row["source_id"] for row in rows]
    if len(observed_order) != len(set(observed_order)):
        raise ValueError("Duplicate source_id in CSV")
    if observed_order != expected_order:
        raise ValueError("CSV row order or source ids differ from manifest")
    for row in rows:
        source = source_by_id[row["source_id"]]
        result = results[row["source_id"]]
        for column in CSV_COLUMNS:
            if column not in source:
                continue
            value = source[column]
            expected = str(value).lower() if isinstance(value, bool) else str(value)
            if row[column] != expected:
                raise ValueError(
                    f"CSV/manifest mismatch for {row['source_id']} field "
                    f"{column}: {row[column]!r} != {expected!r}"
                )
        if row["access_status"] != result["fetch_status"]:
            raise ValueError(f"CSV/result status mismatch for {row['source_id']}")
        if row["robots_status"] != result["robots_status"]:
            raise ValueError(f"CSV/result robots mismatch for {row['source_id']}")
        if count_words(row["excerpt_under_25_words"]) > 25:
            raise ValueError(f"Excerpt exceeds 25 words: {row['source_id']}")
        if row["strict_m2_goods_only"] != "false":
            raise ValueError(
                f"Unexpected strict-M2 claim for {row['source_id']}"
            )
    by_id = {row["source_id"]: row for row in rows}
    semantic_invariants = {
        "aus_abc_news_2006_06_28_china_second_partner": (
            "2",
            "false",
            "current_statement",
        ),
        "aus_abc_news_2007_05_04_china_overtakes_japan": (
            "1",
            "true",
            "rolling_12_months",
        ),
        "aus_dfat_composition_trade_2008": ("2", "false", "calendar_year"),
        "aus_afr_china_trading_partner_2009": ("1", "true", "fiscal_year"),
        "aus_dfat_composition_trade_2008_09": ("1", "true", "fiscal_year"),
    }
    for source_id, expected in semantic_invariants.items():
        observed = (
            by_id[source_id]["rank_position_china"],
            by_id[source_id]["positive_broad_cue"],
            by_id[source_id]["reference_period_type"],
        )
        if observed != expected:
            raise ValueError(
                f"Semantic invariant failed for {source_id}: "
                f"{observed} != {expected}"
            )
    if "2006-07" not in by_id["aus_afr_china_trading_partner_2009"][
        "reference_period"
    ]:
        raise ValueError("AFR fiscal onset 2006-07 is missing")
    earliest_positive = min(
        row["publication_date"] for row in rows if row["positive_broad_cue"] == "true"
    )
    if earliest_positive != "2007-05-04":
        raise ValueError(f"Unexpected earliest positive cue: {earliest_positive}")

    positive_count = sum(row["positive_broad_cue"] == "true" for row in rows)
    strict_count = sum(row["strict_m2_goods_only"] == "true" for row in rows)
    if positive_count != 5 or strict_count != 0:
        raise ValueError(
            f"Unexpected cue totals: broad={positive_count}, strict_m2={strict_count}"
        )
    return {
        "source_by_id": source_by_id,
        "positive_count": positive_count,
        "strict_count": strict_count,
        "earliest_positive": earliest_positive,
    }


def validate(manifest: dict, run_dir: Path) -> dict:
    results = result_map(run_dir)
    if set(results) != {source["source_id"] for source in manifest["sources"]}:
        raise ValueError("fetch_results source ids differ from manifest")
    with OUTPUT_PATH.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows or list(rows[0]) != CSV_COLUMNS:
        raise ValueError("Unexpected CSV schema")
    coding = validate_coded_rows(rows, manifest, results)
    source_by_id = coding["source_by_id"]

    for row in rows:
        source = source_by_id[row["source_id"]]
        result = results[row["source_id"]]
        if row["raw_file"]:
            raw_path = ROOT / row["raw_file"]
            if sha256(raw_path) != row["raw_sha256"]:
                raise ValueError(f"CSV hash mismatch for {row['source_id']}")
            if row["raw_file"] != result["raw_file"]:
                raise ValueError(f"CSV/result raw path mismatch for {row['source_id']}")
            if row["raw_sha256"] != result["sha256"]:
                raise ValueError(f"CSV/result raw hash mismatch for {row['source_id']}")
            if row["verification_markers_present"] != "true":
                raise ValueError(f"Unverified raw source row: {row['source_id']}")
            if not markers_present(source, raw_path):
                raise ValueError(
                    f"Current raw marker verification failed: {row['source_id']}"
                )
        elif not (
            source.get("allow_unarchived_browser_verification") is True
            and row["verification_markers_present"]
            == "not_tested_no_article_raw"
            and row["access_status"] == "robots_unavailable_stop"
        ):
            raise ValueError(f"Unexpected missing raw: {row['source_id']}")

    adversarial_rows = [dict(row) for row in rows]
    adversarial_afr = next(
        row
        for row in adversarial_rows
        if row["source_id"] == "aus_afr_china_trading_partner_2009"
    )
    adversarial_afr.update(
        rank_position_china="2",
        positive_broad_cue="false",
        reference_period_type="calendar_year",
        reference_period="2009",
    )
    try:
        validate_coded_rows(adversarial_rows, manifest, results)
    except ValueError:
        adversarial_rejected = True
    else:
        raise ValueError("Adversarial AFR fiscal-year mutation was not rejected")

    listed = {}
    for line in CHECKSUM_PATH.read_text(encoding="utf-8").splitlines():
        digest, path = line.split("  ", 1)
        listed[path] = digest
    actual_files = sorted(
        path
        for path in RAW_ROOT.rglob("*")
        if path.is_file() and path != CHECKSUM_PATH
    )
    if set(listed) != {
        path.relative_to(RAW_ROOT).as_posix() for path in actual_files
    }:
        raise ValueError("checksums.sha256 does not cover every current raw file")
    for path in actual_files:
        key = path.relative_to(RAW_ROOT).as_posix()
        if sha256(path) != listed[key]:
            raise ValueError(f"Checksum mismatch: {key}")

    return {
        "status": "PASS",
        "sources": len(rows),
        "positive_broad_cue_sources": coding["positive_count"],
        "strict_m2_goods_only_sources": coding["strict_count"],
        "earliest_positive_publication_date": coding["earliest_positive"],
        "adversarial_fiscal_mutation_rejected": adversarial_rejected,
        "raw_files_covered_by_checksums": len(actual_files),
        "output": relative(OUTPUT_PATH),
        "run_dir": relative(run_dir),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect", action="store_true")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    if not (args.collect or args.build or args.validate):
        parser.error("select at least one of --collect, --build, or --validate")
    return args


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(message)s",
    )
    manifest = load_manifest()
    run_dir = args.run_dir if args.run_dir.is_absolute() else ROOT / args.run_dir
    if args.collect:
        collect(manifest, run_dir)
    if args.build:
        build(manifest, run_dir)
    if args.validate:
        print(json.dumps(validate(manifest, run_dir), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
