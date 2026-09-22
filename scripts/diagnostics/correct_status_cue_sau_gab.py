#!/usr/bin/env python3
"""Focused, append-only collection and recoding for SAU/GAB status-cue windows.

Sources/queries: status_cue_sau_gab_manifest.json alongside this script.
Access: public web/PDF; no credentials. Raw responses are immutable per run.
Run --collect to preserve new responses; run --build --run-dir PATH to recode
from an existing run without network. Robots exclusions and access challenges
are stop conditions. Does not run models or touch targets/manuscripts.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import logging
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("status_cue_sau_gab_manifest.json")
RAW = ROOT / "data/raw/status_cue_salience"
PROCESSED = ROOT / "data/processed/status_cue_salience"
REPORT = ROOT / "quality_reports/status_cue_salience"
USER_AGENT = "RDDTradeResearch/1.0 (status-cue academic source audit)"
DATE = datetime.now(timezone.utc).isoformat(timespec="seconds")
LOG = logging.getLogger(__name__)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return str(path.relative_to(ROOT))


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path, rows, columns=None):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns or list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def save_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def request(url, path):
    """No overwrites; retry transient network/server errors with backoff."""
    if path.exists():
        raise FileExistsError(path)
    meta = {"url": url, "accessed_at": DATE, "raw_file": "", "sha256": ""}
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=25) as response:
                body = response.read()
                meta.update(status_code=response.status, content_type=response.headers.get("Content-Type", ""), final_url=response.url)
            with path.open("xb") as stream:
                stream.write(body)
            meta.update(fetch_status="ok", raw_file=relative(path), sha256=digest(path), size_bytes=len(body))
            # A successful HTTP status alone does not establish source access.
            text = body[:15000].lower()
            if any(token in text for token in [b"cf-chl-", b"challenge-platform", b"verify you are human", b"just a moment..."]):
                meta["fetch_status"] = "access_challenge_stop"
            return meta
        except urllib.error.HTTPError as error:
            if error.code >= 500 and attempt < 2:
                time.sleep(2 ** (attempt + 1))
                continue
            meta.update(fetch_status="http_error", status_code=error.code, error=str(error))
            body = error.read()
            if body:
                with path.open("xb") as stream:
                    stream.write(body)
                meta.update(raw_file=relative(path), sha256=digest(path), size_bytes=len(body))
            return meta
        except Exception as error:
            meta.update(fetch_status="network_error", error=repr(error))
            if attempt < 2:
                time.sleep(2 ** (attempt + 1))
    return meta


def collect(manifest, run_dir):
    run_dir.mkdir(parents=True, exist_ok=False)
    save_json(run_dir / "manifest.json", manifest)
    robots = {}
    results = []
    for source in manifest["sources"]:
        parts = urllib.parse.urlsplit(source["url"])
        host = f"{parts.scheme}://{parts.netloc}"
        if host not in robots:
            path = run_dir / (parts.netloc.replace(".", "_") + "_robots.txt")
            robots[host] = request(host + "/robots.txt", path)
            time.sleep(1)
        robot = robots[host]
        robot_status = robot["fetch_status"]
        permitted = False
        if robot_status == "ok":
            parser = urllib.robotparser.RobotFileParser()
            parser.parse((ROOT / robot["raw_file"]).read_text(encoding="utf-8", errors="replace").splitlines())
            permitted = parser.can_fetch(USER_AGENT, source["url"])
            robot_status = "allowed" if permitted else "disallowed_stop"
        elif robot.get("status_code") in (404, 410):
            permitted, robot_status = True, "no_robots_file"
        else:
            robot_status = "robots_unavailable_stop"
        if permitted:
            suffix = ".pdf" if ".pdf" in parts.path else ".html"
            result = request(source["url"], run_dir / (source["source_id"] + suffix))
        else:
            result = {"url": source["url"], "fetch_status": robot_status, "accessed_at": DATE, "raw_file": "", "sha256": ""}
        result.update(source_id=source["source_id"], robots_status=robot_status, robots_file=robot.get("raw_file", ""))
        results.append(result)
        save_json(run_dir / (source["source_id"] + ".metadata.json"), result)
        LOG.info("%s: %s (%s)", source["source_id"], result["fetch_status"], robot_status)
        time.sleep(1)
    save_json(run_dir / "fetch_results.json", results)
    save_json(run_dir / "robots_results.json", robots)
    return results


def source_text(result):
    path = ROOT / result["raw_file"]
    if path.suffix == ".pdf":
        return subprocess.check_output(["pdftotext", "-layout", str(path), "-"], text=True)
    from bs4 import BeautifulSoup
    soup = BeautifulSoup(path.read_bytes(), "html.parser")
    for node in soup(["script", "style"]):
        node.decompose()
    return soup.get_text(" ", strip=True)


def normalized(text):
    return re.sub(r"\s+", " ", text).strip()


def build(manifest, run_dir):
    results = {r["source_id"]: r for r in json.loads((run_dir / "fetch_results.json").read_text())}
    evidence_path = PROCESSED / "status_cue_source_evidence.csv"
    original = read_csv(evidence_path)
    columns = list(original[0])
    other_original = [r for r in original if r["iso3c"] not in ("SAU", "GAB")]
    urls = {s["url"] for s in manifest["sources"]}
    evidence = [r for r in original if r["url"] not in urls]
    for row in evidence:
        if row["iso3c"] == "SAU":
            row["entry_year"] = "2013"
            if int(row["publication_date"][:4]) not in (2013, 2014):
                if "SAU_WINDOW_CORRECTION" not in row["notes"]:
                    row["notes"] = "DO_NOT_COUNT: SAU_WINDOW_CORRECTION: published outside 2013-2014 M2/M3 window. " + row["notes"]
                row["evidence_strength"] = "weak"
    supplement = []
    for source in manifest["sources"]:
        result = results[source["source_id"]]
        verified = False
        if result["fetch_status"] == "ok":
            assert digest(ROOT / result["raw_file"]) == result["sha256"]
            text = normalized(source_text(result))
            verified = all(normalized(marker) in text for marker in source["verification_markers"])
        countable = source["eligible"] and verified
        row = {column: "" for column in columns}
        row.update({key: str(value) for key, value in source.items() if key in columns})
        row.update(country_name="Saudi Arabia" if source["iso3c"] == "SAU" else "Gabon", entry_year="2013" if source["iso3c"] == "SAU" else "2017", raw_file=result["raw_file"], accessed_at=result["accessed_at"], evidence_strength="strong" if countable else "weak", explicit_rank_language="true", mentions_china_rank_change=str(source["eligible"]).lower(), mentions_displaced_incumbent=str(bool(source.get("displaced_partner_named"))).lower())
        row["notes"] = source["notes"]
        # Legacy country table targets M2 for the two corrected cases; M3-only
        # evidence remains in the source table but is excluded from M2 counters.
        if not countable or source["metric_window"] == "M3":
            reason = "M3_WINDOW_ONLY: outside GAB M2 2017-2018 window. " if countable else "Not eligible or full raw/date/text validation failed. "
            row["notes"] = "DO_NOT_COUNT: " + reason + row["notes"]
        evidence.append(row)
        supplement.append({"source_id": source["source_id"], "iso3c": source["iso3c"], "publication_date": source["publication_date"], "metric_window": source["metric_window"], "source_channel": source["source_channel"], "metric_scope": source["metric_scope"], "eligible_publication": str(source["eligible"]).lower(), "full_raw_verified": str(verified).lower(), "counted_in_window": str(countable).lower(), "fetch_status": result["fetch_status"], "robots_status": result["robots_status"], "raw_file": result["raw_file"], "sha256": result["sha256"], "url": source["url"], "accessed_at": result["accessed_at"]})
    assert [r for r in evidence if r["iso3c"] not in ("SAU", "GAB")] == other_original
    assert len({r["url"] for r in evidence}) == len(evidence)
    write_csv(evidence_path, evidence, columns)
    write_csv(PROCESSED / "status_cue_sau_gab_source_audit.csv", supplement)
    codes_path = PROCESSED / "status_cue_country_codes.csv"
    codes = read_csv(codes_path)
    for row in codes:
        if row["iso3c"] not in ("SAU", "GAB"):
            continue
        selected = [r for r in evidence if r["iso3c"] == row["iso3c"] and r["evidence_strength"] in ("strong", "moderate") and not r["notes"].startswith("DO_NOT_COUNT")]
        n_sources = len({r["source_name"] for r in selected})
        row.update(entry_year="2013" if row["iso3c"] == "SAU" else "2017", n_newspaper_sources_strong=str(len(selected)), n_official_sources_strong="0", n_total_strong_or_moderate=str(len(selected)), has_explicit_export_rank_label=str(any(r["label_type"] == "export_rank" for r in selected)).lower(), has_explicit_generic_trade_partner_label=str(any(r["label_type"] == "generic_trade_partner" for r in selected)).lower(), has_official_uptake="false", has_newspaper_uptake=str(bool(selected)).lower(), salience_code="high" if n_sources >= 2 else "medium" if selected else "unknown", negative_case_candidate="no")
        if row["iso3c"] == "SAU":
            row.update(coding_rationale="No countable local top-rank source recovered in corrected M2/M3 2013-2014 publication window; 2016 sources no longer count. Al Riyadh/SPA reports China second and USA first in calendar-year 2013 merchandise exports, requiring rank-definition reconciliation.", remaining_gaps="Contemporaneous top export-rank/public-cue evidence unresolved; no explicit goods-plus-services source recovered. Rank-direction reversals and retrospective articles are excluded; access gaps preclude a negative case.")
        else:
            row.update(coding_rationale=f"M2 2017-2018: {len(selected)} preserved local news sources across {n_sources} publishers; broad trade-partner labels are separated from export-client wording. M3 2015-2016 is coded separately in status_cue_sau_gab_windows.csv.", remaining_gaps="Sources using total trade are not strict export-rank evidence. L'Union explicitly identifies China as first export client in 2017. The 2016 premier-client source does not explicitly include services and has inconsistent semester/quarter wording; no fully aligned M3 label established.")
    write_csv(codes_path, codes)
    windows = []
    for iso3c, metric, onset in [("SAU", "M2", 2013), ("SAU", "M3", 2013), ("GAB", "M2", 2017), ("GAB", "M3", 2015)]:
        subset = [s for s in supplement if s["iso3c"] == iso3c and s["counted_in_window"] == "true" and s["metric_window"] in (metric, "M2_M3")]
        names = {next(x["source_name"] for x in manifest["sources"] if x["source_id"] == s["source_id"]) for s in subset}
        strict = [s for s in subset if s["metric_scope"] == ("goods_exports" if metric == "M2" else "goods_services_exports")]
        windows.append({"iso3c": iso3c, "metric": metric, "entry_year": onset, "window_start": onset, "window_end": onset+1, "n_counted_public_cue_sources": len(subset), "n_publishers": len(names), "broad_cue_salience": "high" if len(names) >= 2 else "medium" if subset else "unknown", "n_metric_aligned_sources": len(strict), "metric_aligned_evidence": "observed" if strict else "unresolved", "source_ids": ";".join(s["source_id"] for s in subset)})
    write_csv(PROCESSED / "status_cue_sau_gab_windows.csv", windows)
    # Manifest is valid YAML (JSON is a YAML subset); original historical entries
    # stay byte-for-byte in place, with an explicitly delimited focused appendix.
    yaml_path = PROCESSED / "SOURCES.yaml"
    content = yaml_path.read_text(encoding="utf-8").split("\n# BEGIN SAU_GAB_FOCUSED_CORRECTION")[0]
    new_yaml = "\n# BEGIN SAU_GAB_FOCUSED_CORRECTION\n"
    for source in manifest["sources"]:
        result = results[source["source_id"]]
        record = {"id": source["source_id"], "name": source["title"], "provider": source["source_name"], "url": source["url"], "access_method": "public_web_download", "license": "Publisher copyright; no redistribution license asserted; retained for internal verification", "download_script": relative(Path(__file__)), "date_accessed": result["accessed_at"][:10], "raw_file": result["raw_file"], "fetch_status": result["fetch_status"], "source_channel": source["source_channel"], "metric_scope": source["metric_scope"], "publication_date": source["publication_date"], "notes": source["notes"]}
        new_yaml += "  - " + json.dumps(record, ensure_ascii=False) + "\n"
    yaml_path.write_text(content + new_yaml, encoding="utf-8")
    summary = {"run_dir": relative(run_dir), "generated_at": DATE, "query_count": len(manifest["queries"]), "candidate_count": len(supplement), "preserved_and_verified": sum(s["full_raw_verified"] == "true" for s in supplement), "windows": windows, "models_run": False, "other_12_countries_unchanged": True}
    (REPORT / "sau_gab_correction_validation.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    LOG.info("Built source audit and corrected country codes: %s", summary)


def checksums():
    target = RAW / "checksums.sha256"
    target.write_text("".join(f"{digest(path)}  {path.relative_to(RAW)}\n" for path in sorted(RAW.rglob("*")) if path.is_file() and path != target), encoding="utf-8")


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect", action="store_true")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--run-dir", type=Path)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    run_dir = args.run_dir or RAW / "focused_sau_gab" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = run_dir.resolve()
    if args.collect:
        collect(manifest, run_dir)
    if args.build:
        manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))
        build(manifest, run_dir)
    if not args.collect and not args.build:
        parser.error("Specify --collect and/or --build")
    checksums()
    LOG.info("Run directory: %s", run_dir)


if __name__ == "__main__":
    main()
