#!/usr/bin/env python3
"""Collect and rebuild the 48-country status-cue extension without targets.

Inputs: the frozen goods-rank inventory, an executed web-search log, and a
versioned candidate list.  New HTTP responses are immutable; --build uses only
the named manifest and hash-verified raw files.  Search results and GDELT hits
are discovery aids, never countable source evidence.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import html
from html.parser import HTMLParser
import json
import logging
from pathlib import Path
import re
import subprocess
import sys
import time
import unicodedata
from urllib import error, parse, request, robotparser
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / "quality_reports/status_cue_salience/search_inventory_goods_rank_one_2026-09-22.csv"
LEGACY_EVIDENCE = ROOT / "data/processed/status_cue_salience/status_cue_source_evidence.csv"
LEGACY_COUNTRIES = ROOT / "data/processed/status_cue_salience/status_cue_country_codes.csv"
CANDIDATES = ROOT / "scripts/diagnostics/status_cue_extension_candidates.json"
RAW = ROOT / "data/raw/status_cue_salience/extension_2026"
PROCESSED = ROOT / "data/processed/status_cue_salience"
REPORTS = ROOT / "quality_reports/status_cue_salience"
USER_AGENT = "RDD-Trade-public-cue-audit/1.0 (academic source verification)"
TIMEOUT = 18
DOC_START = 2017
METRICS = {"goods_exports", "goods_services_exports", "two_way_trade", "unspecified"}
OFFICIAL_TYPES = {"official", "official_speech", "official_statistics", "official_release"}
NEWS_TYPES = {"newspaper", "business_news", "national_news_agency", "local_news"}


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def rel(path: Path) -> str:
    if not path.is_absolute():
        path = ROOT / path
    return str(path.relative_to(ROOT))


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_new(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as f:
        f.write(data)


def write_json_new(path: Path, obj: object) -> None:
    write_new(path, (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def read_inventory() -> list[dict[str, str]]:
    rows = [r for r in read_csv(INVENTORY) if r["in_legacy_search"].casefold() == "false"]
    if len(rows) != 48 or len({r["iso3c"] for r in rows}) != 48:
        raise ValueError("Expected exactly 48 unique extension countries")
    for r in rows:
        years = [int(x) for x in r["entry_years"].split(";")]
        if years[0] != int(r["first_entry"]) or years != sorted(set(years)):
            raise ValueError(f"Invalid entry years: {r['iso3c']}")
        if int(r["first_entry"]) < 2000 or int(r["first_entry"]) > 2022:
            raise ValueError(f"Invalid first entry: {r['iso3c']}")
    if {r["iso3c"] for r in rows} & {r["iso3c"] for r in read_csv(LEGACY_COUNTRIES)}:
        raise ValueError("Extension overlaps legacy countries")
    return rows


def read_candidates(sample: list[dict[str, str]]) -> list[dict[str, object]]:
    items = json.loads(CANDIDATES.read_text(encoding="utf-8"))["candidates"]
    isos = {r["iso3c"] for r in sample}
    ids = set()
    for c in items:
        if c["source_id"] in ids or c["iso3c"] not in isos:
            raise ValueError(f"Duplicate or out-of-scope source: {c['source_id']}")
        ids.add(c["source_id"])
        if c["metric_in_source"] not in METRICS:
            raise ValueError(f"Bad metric: {c['source_id']}")
        if c["source_type"] not in OFFICIAL_TYPES | NEWS_TYPES:
            raise ValueError(f"Bad source type: {c['source_id']}")
        if c["disposition"] not in {"count", "do_not_count", "candidate"}:
            raise ValueError(f"Bad disposition: {c['source_id']}")
        if not str(c["url"]).startswith("https://"):
            raise ValueError(f"Source requires an HTTPS URL: {c['source_id']}")
    return items


def candidate_url_hash(candidates: list[dict[str, object]]) -> str:
    """Bind a capture to source identities/URLs while allowing later manual coding."""
    pairs = sorted((str(c["source_id"]), str(c["url"])) for c in candidates)
    return hashlib.sha256(json.dumps(pairs, ensure_ascii=False).encode("utf-8")).hexdigest()


def discovery_queries(sample: list[dict[str, str]], candidates: list[dict[str, object]]) -> list[dict[str, object]]:
    output = []
    by_iso = {r["iso3c"]: r for r in sample}
    by_source = {c["source_id"]: c for c in candidates}
    for path in sorted(RAW.glob("web_discovery_queries*.json")):
        obj = json.loads(path.read_text(encoding="utf-8"))
        for original in obj["queries"]:
            q = dict(original)
            if not q.get("window") and q.get("source_id") in by_source:
                candidate = by_source[q["source_id"]]
                entry = int(by_iso[candidate["iso3c"]]["first_entry"])
                q["window"] = candidate.get("search_window") or f"{entry}-{entry + 1}"
            output.append(q)
    return output


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = request.build_opener(NoRedirect)


def http_once(url: str) -> tuple[int, dict[str, str], bytes]:
    req = request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/pdf,application/json,text/plain,*/*"})
    try:
        with OPENER.open(req, timeout=TIMEOUT) as response:
            return response.status, dict(response.headers.items()), response.read(20_000_001)
    except error.HTTPError as exc:
        body = exc.read(100_000) if exc.code not in {301, 302, 303, 307, 308} else b""
        return exc.code, dict(exc.headers.items()), body


class RobotsCache:
    def __init__(self, run: Path):
        self.run = run
        self.cache: dict[str, tuple[str, robotparser.RobotFileParser | None, str]] = {}
        self.last_fetch: dict[str, float] = {}

    def check(self, url: str) -> tuple[str, str]:
        parts = parse.urlsplit(url)
        origin = f"{parts.scheme}://{parts.netloc}"
        if origin not in self.cache:
            robots_url = origin + "/robots.txt"
            slug = re.sub(r"[^a-zA-Z0-9]+", "_", parts.netloc)
            path = self.run / "robots" / (slug + ".txt")
            try:
                status, headers, body = http_once(robots_url)
                for _ in range(4):
                    if status not in {301, 302, 303, 307, 308}:
                        break
                    target = parse.urljoin(robots_url, headers.get("Location", headers.get("location", "")))
                    if parse.urlsplit(target).scheme != "https" or not target.endswith("/robots.txt"):
                        break
                    robots_url = target
                    status, headers, body = http_once(robots_url)
                write_new(path, body)
                if status == 404 or status == 410:
                    decision, parser = "no_robots_file", None
                elif status == 200:
                    parser = robotparser.RobotFileParser()
                    parser.parse(body.decode("utf-8", "replace").splitlines())
                    decision = "available"
                else:
                    decision, parser = f"robots_http_{status}_stop", None
            except (OSError, TimeoutError, error.URLError) as exc:
                decision, parser = "robots_unavailable_stop", None
                write_new(path, (str(exc) + "\n").encode("utf-8"))
            self.cache[origin] = (decision, parser, rel(path))
        decision, parser, raw_file = self.cache[origin]
        if decision == "available":
            return ("allowed" if parser and parser.can_fetch(USER_AGENT, url) else "disallowed_stop", raw_file)
        return decision, raw_file

    def pace(self, url: str) -> None:
        origin = parse.urlsplit(url).netloc
        elapsed = time.monotonic() - self.last_fetch.get(origin, 0)
        if elapsed < 1.25:
            time.sleep(1.25 - elapsed)
        self.last_fetch[origin] = time.monotonic()


def fetch_checked(url: str, robots: RobotsCache) -> dict[str, object]:
    original = url
    hops = []
    for _ in range(5):
        decision, robots_file = robots.check(url)
        if decision not in {"allowed", "no_robots_file"}:
            return {"url": original, "final_url": url, "status": decision, "robots_file": robots_file, "hops": hops}
        robots.pace(url)
        try:
            status, headers, body = http_once(url)
        except (OSError, TimeoutError, error.URLError) as exc:
            return {"url": original, "final_url": url, "status": "network_error", "error": str(exc), "robots_file": robots_file, "hops": hops}
        if status in {301, 302, 303, 307, 308}:
            location = headers.get("Location") or headers.get("location")
            if not location:
                return {"url": original, "final_url": url, "status": "redirect_without_location", "robots_file": robots_file, "hops": hops}
            hops.append({"url": url, "status": status})
            url = parse.urljoin(url, location)
            if parse.urlsplit(url).scheme != "https":
                return {"url": original, "final_url": url, "status": "insecure_redirect_stop", "robots_file": robots_file, "hops": hops}
            continue
        return {"url": original, "final_url": url, "status": "ok" if status == 200 else f"http_{status}", "http_status": status, "headers": headers, "body": body, "robots_file": robots_file, "hops": hops}
    return {"url": original, "final_url": url, "status": "redirect_limit_stop", "hops": hops}


def collect(sample: list[dict[str, str]], candidates: list[dict[str, object]], gdelt: bool, reuse_manifest: Path | None = None) -> Path:
    run = RAW / "runs" / stamp()
    if run.exists():
        raise FileExistsError(run)
    run.mkdir(parents=True)
    robots = RobotsCache(run)
    by_iso = {r["iso3c"]: r for r in sample}
    manifest: dict[str, object] = {"run_at": utc_now(), "inventory": rel(INVENTORY), "inventory_sha256": sha(INVENTORY), "candidate_url_sha256": candidate_url_hash(candidates), "sources": [], "gdelt": []}
    old = json.loads(reuse_manifest.read_text(encoding="utf-8")) if reuse_manifest else None
    previous_sources = {x["source_id"]: x for x in old["sources"]} if old else {}
    if old and not gdelt:
        manifest["gdelt"] = old["gdelt"]
    for c in candidates:
        iso = str(c["iso3c"])
        year = int(str(c["publication_date"])[:4])
        target_url = str(c.get("archive_url") or c["url"])
        previous = previous_sources.get(str(c["source_id"]), {})
        old_raw = ROOT / str(previous.get("raw_file", ""))
        if previous.get("status") == "ok" and previous.get("url") == target_url and old_raw.is_file() and sha(old_raw) == previous.get("sha256"):
            manifest["sources"].append(previous)
            logging.info("%s %s reused_hash_verified", iso, c["source_id"])
            continue
        result = fetch_checked(target_url, robots)
        result.pop("body", None) if result.get("status") != "ok" else None
        if result.get("status") == "ok":
            body = result.pop("body")
            if len(body) > 20_000_000:
                result["status"] = "size_limit_stop"
            else:
                ctype = str(result.get("headers", {}).get("Content-Type", ""))
                suffix = ".pdf" if body.startswith(b"%PDF") else ".html" if "html" in ctype or b"<html" in body[:1000].lower() else ".bin"
                path = RAW / iso / str(year) / str(c["source_id"]) / (stamp() + suffix)
                write_new(path, body)
                result["raw_file"] = rel(path)
                result["sha256"] = sha(path)
                result["size_bytes"] = len(body)
        result["source_id"] = c["source_id"]
        result["iso3c"] = iso
        result["accessed_at"] = utc_now()
        manifest["sources"].append(result)
        logging.info("%s %s %s", iso, c["source_id"], result["status"])
    if gdelt:
        for row in sample:
            iso = row["iso3c"]
            for year_text in row["entry_years"].split(";"):
                year = int(year_text)
                if year + 1 < DOC_START:
                    manifest["gdelt"].append({"iso3c": iso, "search_window": f"{year}-{year+1}", "status": "pre_2017_not_covered"})
                    continue
                start = max(year, DOC_START)
                query = f'"China" "{row["country_name"]}" ("largest trading partner" OR "largest export market")'
                params = {"query": query, "mode": "artlist", "format": "json", "startdatetime": f"{start}0101000000", "enddatetime": f"{year+1}1231235959", "maxrecords": "50"}
                url = "https://api.gdeltproject.org/api/v2/doc/doc?" + parse.urlencode(params)
                result = fetch_checked(url, robots)
                body = result.pop("body", None)
                if result.get("status") == "ok" and body is not None:
                    path = RAW / "gdelt" / iso / f"{year}-{year+1}" / (stamp() + ".json")
                    write_new(path, body)
                    result["raw_file"] = rel(path)
                    result["sha256"] = sha(path)
                    try:
                        obj = json.loads(body)
                        result["n_articles_returned"] = len(obj.get("articles", []))
                        result["status"] = "queried"
                    except (ValueError, UnicodeDecodeError):
                        result["status"] = "invalid_json"
                result.update({"iso3c": iso, "search_window": f"{year}-{year+1}", "query": query, "url": url, "accessed_at": utc_now()})
                manifest["gdelt"].append(result)
                logging.info("GDELT %s %s %s", iso, year, result["status"])
                time.sleep(1.25)
    write_json_new(run / "manifest.json", manifest)
    return run / "manifest.json"


class VisibleText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts: list[str] = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "noscript"}:
            self.hidden += 1

    def handle_endtag(self, tag):
        if tag in {"script", "style", "noscript"} and self.hidden:
            self.hidden -= 1

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def raw_text(path: Path) -> str:
    if path.suffix == ".pdf":
        p = subprocess.run(["pdftotext", str(path), "-"], capture_output=True, text=True, timeout=45, check=False)
        return p.stdout if p.returncode == 0 else ""
    data_bytes = path.read_bytes()
    if data_bytes.startswith(b"\x1f\x8b"):
        try:
            data_bytes = gzip.decompress(data_bytes)
        except OSError:
            return ""
    data = data_bytes.decode("utf-8", "replace")
    if path.suffix == ".html" or "<html" in data[:1000].casefold():
        parser = VisibleText()
        parser.feed(data)
        return html.unescape(" ".join(parser.parts))
    return data


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).casefold()
    s = s.translate(str.maketrans({"’": "'", "‘": "'", "“": '"', "”": '"', "−": "-", "–": "-", "—": "-"}))
    return " ".join(s.split())


def boolstr(value: bool) -> str:
    return "true" if value else "false"


def source_row(c: dict[str, object], fetch: dict[str, object], country: dict[str, str]) -> tuple[dict[str, str], bool]:
    path_text = str(fetch.get("raw_file", ""))
    path = ROOT / path_text if path_text else None
    raw_ok = bool(path and path.is_file() and sha(path) == fetch.get("sha256"))
    text = raw_text(path) if raw_ok and path else ""
    markers = c.get("content_markers", [])
    markers_ok = bool(markers) and all(norm(str(m)) in norm(text) for m in markers)
    raw_bytes = path.read_bytes() if raw_ok and path else b""
    raw_string = raw_bytes.decode("utf-8", "replace")
    date_marker = str(c.get("date_marker", ""))
    date_ok = bool(date_marker) and (norm(date_marker) in norm(text) or norm(date_marker) in norm(raw_string))
    year = int(str(c["publication_date"])[:4])
    entries = [int(x) for x in country["entry_years"].split(";")]
    windows = [f"{e}-{e+1}" for e in entries if e <= year <= e + 1]
    window = str(c.get("search_window") or (windows[0] if windows else "outside"))
    inside = window in windows
    quote = str(c.get("excerpt_under_25_words", ""))
    quote_ok = len(quote.split()) < 25 and (not quote or norm(quote) in norm(text))
    eligible = (c["disposition"] == "count" and fetch.get("status") == "ok" and raw_ok and markers_ok and date_ok and inside and quote_ok and bool(c["explicit_rank_language"]) and c["label_type"] in {"export_rank", "generic_trade_partner"} and c["evidence_strength"] in {"strong", "moderate"})
    reason = "" if eligible else "; ".join(x for x, fail in [
        ("not approved for count", c["disposition"] != "count"),
        (f"fetch {fetch.get('status', 'missing')}", fetch.get("status") != "ok"),
        ("raw or checksum missing", not raw_ok),
        ("claim marker absent", not markers_ok),
        ("publication-date marker absent", not date_ok),
        ("outside coded window", not inside),
        ("quote absent or 25+ words", not quote_ok),
        ("no explicit rank-language flag", not bool(c["explicit_rank_language"])),
    ] if fail)
    note = str(c.get("notes", ""))
    if not eligible:
        note = "DO_NOT_COUNT: " + reason + ("; " + note if note else "")
    return ({
        "iso3c": country["iso3c"], "country_name": country["country_name"], "entry_year": country["first_entry"],
        "evidence_year": str(year), "source_type": str(c["source_type"]), "source_name": str(c["source_name"]),
        "source_country": country["country_name"], "language": str(c["language"]), "title": str(c["title"]),
        "publication_date": str(c["publication_date"]), "url": str(c["url"]), "archive_url": str(c.get("archive_url", "")),
        "raw_file": path_text if raw_ok else "", "query_used": str(c.get("query_used", "")), "accessed_at": str(fetch.get("accessed_at", "")),
        "rank_label_original": str(c.get("rank_label_original", "")), "rank_label_english": str(c.get("rank_label_english", "")),
        "label_type": str(c.get("label_type", "")), "explicit_rank_language": boolstr(bool(c.get("explicit_rank_language"))),
        "mentions_china_rank_change": boolstr(bool(c.get("mentions_china_rank_change"))),
        "mentions_displaced_incumbent": boolstr(bool(c.get("mentions_displaced_incumbent"))),
        "displaced_partner_named": str(c.get("displaced_partner_named", "")),
        "excerpt_under_25_words": quote, "evidence_strength": str(c["evidence_strength"]),
        "notes": note, "metric_in_source": str(c["metric_in_source"]), "search_window": window,
    }, eligible)


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def build(manifest_path: Path, sample: list[dict[str, str]], candidates: list[dict[str, object]]) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["inventory_sha256"] != sha(INVENTORY) or manifest["candidate_url_sha256"] != candidate_url_hash(candidates):
        raise ValueError("Inventory or candidate URL drift; use a fresh collection manifest")
    fetches = {r["source_id"]: r for r in manifest["sources"]}
    if set(fetches) != {c["source_id"] for c in candidates}:
        raise ValueError("Manifest and candidate list differ")
    lookup = {r["iso3c"]: r for r in sample}
    evidence = []
    counted = {}
    for c in candidates:
        row, accepted = source_row(c, fetches[c["source_id"]], lookup[c["iso3c"]])
        evidence.append(row)
        if accepted:
            counted.setdefault(c["iso3c"], []).append((c, row))
    query_log = discovery_queries(sample, candidates)
    queries_by_iso: dict[str, list[dict[str, object]]] = {}
    windows_by_iso: dict[str, set[str]] = {}
    for q in query_log:
        queries_by_iso.setdefault(q["iso3c"], []).append(q)
        windows_by_iso.setdefault(q["iso3c"], set()).add(q["window"])
    countries = []
    for country in sample:
        iso = country["iso3c"]
        accepted = counted.get(iso, [])
        primary = f"{country['first_entry']}-{int(country['first_entry'])+1}"
        # A later entry is only a fallback when the primary window has no countable source.
        effective = [x for x in accepted if x[1]["search_window"] == primary]
        if not effective:
            for year in [int(x) for x in country["entry_years"].split(";")][1:]:
                effective = [x for x in accepted if x[1]["search_window"] == f"{year}-{year+1}"]
                if effective:
                    break
        publisher_ids = {str(c["publisher_id"]) for c, _ in effective}
        rank_issue = str(country.get("rank_issue", ""))
        # Rank issues are declared in the candidate configuration, never inferred from a missing result.
        issues = []
        for c in candidates:
            if c["iso3c"] != iso or not c.get("rank_issue"):
                continue
            fetch = fetches[c["source_id"]]
            raw_path = ROOT / str(fetch.get("raw_file", ""))
            if fetch.get("status") == "ok" and raw_path.is_file() and sha(raw_path) == fetch.get("sha256"):
                visible = raw_text(raw_path)
                if all(norm(str(m)) in norm(visible) for m in c.get("content_markers", [])) and norm(str(c.get("date_marker", ""))) in norm(visible + raw_path.read_bytes().decode("utf-8", "replace")):
                    issues.append(str(c["rank_issue"]))
        if issues:
            code = "unknown"
        elif len(publisher_ids) >= 2:
            code = "high"
        elif len(effective) >= 1:
            code = "medium"
        else:
            code = "unknown"
        # No low code is generated from search-result absence. A low needs an explicit,
        # separately audited breadth record of local news and official full raws.
        qcount = len(queries_by_iso.get(iso, [])) + sum(g["iso3c"] == iso and bool(g.get("query")) for g in manifest["gdelt"])
        windows_tried = sorted(windows_by_iso.get(iso, set()))
        source_n = len(effective)
        rationale = (f"{source_n} countable source(s) from {len(publisher_ids)} independent publisher(s) in {effective[0][1]['search_window']}." if effective else "No fully archived, verified local/official rank cue in searched entry windows; absence is not established.")
        if issues:
            rationale = "Contemporaneous rank-definition conflict; public-cue evidence is not assigned a high/medium code pending reconciliation."
        additional_gaps = [str(c["country_gap"]) for c in candidates if c["iso3c"] == iso and c.get("country_gap")]
        gaps = "; ".join(dict.fromkeys(issues + additional_gaps)) if issues or additional_gaps else ("" if effective else "Local/official archive coverage and metric alignment remain insufficient for a negative-case inference.")
        countries.append({
            "iso3c": iso, "country_name": country["country_name"], "entry_year": country["first_entry"],
            "n_newspaper_sources_strong": str(sum(c["source_type"] in NEWS_TYPES for c, _ in effective)),
            "n_official_sources_strong": str(sum(c["source_type"] in OFFICIAL_TYPES for c, _ in effective)),
            "n_total_strong_or_moderate": str(source_n),
            "has_explicit_export_rank_label": boolstr(any(r["label_type"] == "export_rank" for _, r in effective)),
            "has_explicit_generic_trade_partner_label": boolstr(any(r["label_type"] == "generic_trade_partner" for _, r in effective)),
            "has_official_uptake": boolstr(any(c["source_type"] in OFFICIAL_TYPES for c, _ in effective)),
            "has_newspaper_uptake": boolstr(any(c["source_type"] in NEWS_TYPES for c, _ in effective)),
            "salience_code": code, "negative_case_candidate": "no", "coding_rationale": rationale,
            "remaining_gaps": gaps, "search_windows_tried": ";".join(windows_tried), "n_queries_logged": str(qcount),
        })
    with LEGACY_EVIDENCE.open(encoding="utf-8-sig", newline="") as f:
        evidence_fields = list(csv.DictReader(f).fieldnames or []) + ["metric_in_source", "search_window"]
    with LEGACY_COUNTRIES.open(encoding="utf-8-sig", newline="") as f:
        country_fields = list(csv.DictReader(f).fieldnames or []) + ["search_windows_tried", "n_queries_logged"]
    write_csv(PROCESSED / "status_cue_source_evidence_extension.csv", evidence_fields, evidence)
    write_csv(PROCESSED / "status_cue_country_codes_extension.csv", country_fields, countries)
    write_reports(manifest_path, manifest, sample, candidates, evidence, countries, query_log)
    build_files = [
        PROCESSED / "status_cue_source_evidence_extension.csv",
        PROCESSED / "status_cue_country_codes_extension.csv",
        PROCESSED / "SOURCES_extension.yaml",
        PROCESSED / "DATA_DICTIONARY_extension.md",
        REPORTS / "extension_collection_log.md",
        REPORTS / "extension_report.md",
    ]
    build_record = {
        "built_at": utc_now(),
        "collector_script": {"path": rel(Path(__file__)), "sha256": sha(Path(__file__))},
        "inventory": {"path": rel(INVENTORY), "sha256": sha(INVENTORY)},
        "candidate_coding": {"path": rel(CANDIDATES), "sha256": sha(CANDIDATES)},
        "raw_manifest": {"path": rel(manifest_path), "sha256": sha(manifest_path)},
        "query_logs": [{"path": rel(p), "sha256": sha(p)} for p in sorted(RAW.glob("web_discovery_queries*.json"))],
        "outputs": [{"path": rel(p), "sha256": sha(p)} for p in build_files],
    }
    (PROCESSED / "extension_build_manifest.json").write_text(json.dumps(build_record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_reports(manifest_path, manifest, sample, candidates, evidence, countries, queries):
    from collections import Counter
    counts = Counter(c["salience_code"] for c in countries)
    problem_isos = {c["iso3c"] for c in candidates if c.get("rank_issue") or c.get("country_gap")}
    rank_issues = [c for c in countries if c["iso3c"] in problem_isos]
    gdelt_counts = Counter(g["status"] for g in manifest["gdelt"])
    fetch_counts = Counter(f["status"] for f in manifest["sources"])
    log = [
        "# Extension collection log", "", f"Run: `{rel(manifest_path)}`. Accessed in UTC on {manifest['run_at'][:10]}.",
        f"Candidate coding config: `{rel(CANDIDATES)}` (SHA-256 `{sha(CANDIDATES)}`).",
        "", "## Scope and protocol", "",
        f"Inventory: `{rel(INVENTORY)}` (SHA-256 `{manifest['inventory_sha256']}`); {len(sample)} non-legacy countries. First entry and +1 were searched. Later entries are fallbacks only when the first has no countable cue.",
        "Search results, snippets, third-country sources, and GDELT hits are leads only. Publisher raws must pass robots, checksum, full-text claim, and publication-date checks before counting.",
        "", "## Executed discovery queries", "",
        f"Web discovery queries logged: {len(queries)}. GDELT window attempts: {sum(bool(g.get('query')) for g in manifest['gdelt'])}; successful JSON responses: {sum(g['status'] == 'queried' for g in manifest['gdelt'])}. Individual queries, UTC dates, and returned URLs: `data/raw/status_cue_salience/extension_2026/web_discovery_queries*.json`.",
        "", "## Source fetch status", "",
        *[f"- `{k}`: {v}" for k, v in sorted(fetch_counts.items())],
        "", "## GDELT DOC 2.0", "",
        "GDELT DOC article discovery is treated as useful only from 2017. Pre-2017 windows were not queried. A successful JSON response establishes an executed API search, not complete media coverage. HTTP 429 attempts had no usable leads; the earlier collector did not retain their response bodies, so only request URL, status, and UTC time are auditable. One invalid-JSON raw was preserved but yielded no usable leads.",
        *[f"- `{k}`: {v}" for k, v in sorted(gdelt_counts.items())],
        "", "## Country coverage", "",
        "| Country | Entry years | Search windows tried | Web/API queries | Code | Counted sources | Gap |",
        "|---|---|---|---:|---|---:|---|",
    ]
    for original, c in zip(sample, countries, strict=True):
        log.append(f"| {c['iso3c']} | {original['entry_years']} | {c['search_windows_tried'] or 'none'} | {c['n_queries_logged']} | {c['salience_code']} | {c['n_total_strong_or_moderate']} | {c['remaining_gaps'].replace('|', '/')} |")
    (REPORTS / "extension_collection_log.md").write_text("\n".join(log) + "\n", encoding="utf-8")
    report = [
        "# Public cue extension: 48 goods-rank-entry countries", "",
        f"Candidate and raw manifest: `{rel(manifest_path)}`. Coding config SHA-256: `{sha(CANDIDATES)}`. The 14-country legacy CSVs and `paper_v4.Rmd` were not changed.",
        "", "## Coding result", "",
        "| Code | Countries | n |", "|---|---|---:|",
    ]
    for code in ["high", "medium", "low", "unknown"]:
        names = ", ".join(c["iso3c"] for c in countries if c["salience_code"] == code) or "none"
        report.append(f"| {code} | {names} | {counts[code]} |")
    report += ["", "Negative-case candidates: " + (", ".join(c["iso3c"] for c in countries if c["negative_case_candidate"] == "yes") or "none") + ".", "", "## Rank-definition problems", ""]
    report += [f"- **{c['iso3c']}**: {c['remaining_gaps']}" for c in rank_issues] or ["None documented in hash-verified contemporaneous raws."]
    report += ["", "## GDELT coverage actually obtained", "", *[f"- `{k}`: {v} country-entry windows" for k, v in sorted(gdelt_counts.items())], "", "Only four GDELT calls returned usable JSON. The 24 rate-limited calls and one invalid-JSON call supplied no usable leads. The invalid-JSON response was preserved as raw; the 429 request URLs and statuses are logged, but their response bodies were not retained. Pre-2017 windows are outside documented useful GDELT DOC coverage. GDELT did not determine any country code.", "", "## Access and coding limits", "", "The Peru MEF and New Zealand Beehive live pages returned challenge shells; the Beehive cue was recovered from Wayback. The Japan Times archived page exposed a dated headline but not its full article. The BPS-authored Indonesian PDF mirror was blocked by robots.txt; its search result was never counted as raw evidence. Other unknown countries lack a sufficiently verified national-news and official corpus for a negative-case conclusion.", "", "## Interpretation", "", "Only positive rank cues with preserved publisher or archived raws enter high or medium. Unknown includes failed access, insufficient local/official coverage, and unresolved rank definitions; it is not a negative case. Later-window evidence is reported separately and never relabeled as first-entry uptake.", "", "## Independent check", "", "The separate fact-check report is `quality_reports/status_cue_salience/extension_fact_check_report.md`; consult its latest round and candidate hash for the verified status of these codes."]
    (REPORTS / "extension_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    sources = {"sources": []}
    for c in candidates:
        row = next(r for r in evidence if r["url"] == c["url"] and r["iso3c"] == c["iso3c"])
        sources["sources"].append({"id": c["source_id"], "name": c["title"], "provider": c["source_name"], "url": c["url"], "access_method": "robots-checked public web download", "license": "Publisher rights retained; internal source verification", "download_script": rel(Path(__file__)), "date_accessed": row["accessed_at"][:10], "raw_file": row["raw_file"], "query_used": row["query_used"]})
    (PROCESSED / "SOURCES_extension.yaml").write_text(json.dumps(sources, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    dictionary = """# Status cue extension data dictionary

The two extension CSVs retain the exact legacy column order and meanings, with appended columns only. Each row in the evidence CSV represents a candidate publisher document, including DO_NOT_COUNT failures. Only rows whose raw, date, claim, scope, and window pass the collector's checks enter country counts. A newspaper quoting official data is one newspaper source, not an additional official source.

| File | Extra column | Meaning | Values |
|---|---|---|---|
| status_cue_source_evidence_extension.csv | metric_in_source | Denominator the source explicitly describes; a generic partner label is normally `two_way_trade` only when the text makes both flows clear, otherwise `unspecified`. | goods_exports, goods_services_exports, two_way_trade, unspecified |
| status_cue_source_evidence_extension.csv | search_window | Publication window associated with this candidate. | `YYYY-YYYY`; `outside` |
| status_cue_country_codes_extension.csv | search_windows_tried | Entry and following-year windows with actually executed web discovery queries. | semicolon-separated windows |
| status_cue_country_codes_extension.csv | n_queries_logged | Number of executed web searches and attempted GDELT DOC requests, including rate-limited calls. | nonnegative integer |

The common legacy fields are defined in `DATA_DICTIONARY.md`. `negative_case_candidate` can be `yes` only after a separate documented wide search verifies contemporaneous national news and official coverage in English and the local language without a rank cue. The present collector never infers `low` from zero search hits. Search queries and result URLs are under `data/raw/status_cue_salience/extension_2026/web_discovery_queries*.json`; each collection run has a JSON manifest with SHA-256 for publisher and GDELT raws. Rebuild with `python3 scripts/diagnostics/collect_status_cue_salience_extension.py --build --manifest PATH`.
"""
    (PROCESSED / "DATA_DICTIONARY_extension.md").write_text(dictionary, encoding="utf-8")


def validate(manifest_path: Path, sample: list[dict[str, str]]) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for record in list(manifest["sources"]) + [g for g in manifest["gdelt"] if g.get("raw_file")]:
        path_text = record.get("raw_file")
        if path_text and sha(ROOT / path_text) != record["sha256"]:
            raise ValueError(f"Raw hash mismatch: {path_text}")
    country_rows = read_csv(PROCESSED / "status_cue_country_codes_extension.csv")
    evidence_rows = read_csv(PROCESSED / "status_cue_source_evidence_extension.csv")
    if len(country_rows) != 48 or {r["iso3c"] for r in country_rows} != {r["iso3c"] for r in sample}:
        raise ValueError("Country coverage mismatch")
    if {r["iso3c"] for r in evidence_rows} - {r["iso3c"] for r in sample}:
        raise ValueError("Out-of-scope evidence")
    for r in country_rows:
        if r["salience_code"] not in {"high", "medium", "low", "unknown"}:
            raise ValueError("Invalid code")
        if r["negative_case_candidate"] == "yes" and r["salience_code"] != "low":
            raise ValueError("Negative-case flag inconsistent")
    build_record = json.loads((PROCESSED / "extension_build_manifest.json").read_text(encoding="utf-8"))
    for item in build_record["outputs"]:
        if sha(ROOT / item["path"]) != item["sha256"]:
            raise ValueError(f"Build output hash mismatch: {item['path']}")
    if build_record["candidate_coding"]["sha256"] != sha(CANDIDATES):
        raise ValueError("Candidate coding config changed after build")
    print(f"PASS: {len(country_rows)} countries; {len(evidence_rows)} candidate documents; all recorded raw hashes match")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect", action="store_true", help="Fetch new publisher raws and optional GDELT API responses")
    parser.add_argument("--gdelt", action="store_true", help="Query GDELT DOC for entry windows that overlap 2017+")
    parser.add_argument("--build", action="store_true", help="Build separate extension CSVs and reports from a manifest")
    parser.add_argument("--validate", action="store_true", help="Check coverage, codes, and raw checksums")
    parser.add_argument("--manifest", type=Path, help="Existing run manifest for --build/--validate")
    parser.add_argument("--reuse-successful-from", type=Path, help="Reuse hash-verified successful raws and prior GDELT responses")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    sample = read_inventory()
    candidates = read_candidates(sample)
    manifest = args.manifest
    if args.collect:
        manifest = collect(sample, candidates, args.gdelt, args.reuse_successful_from)
        print(rel(manifest))
    if args.build:
        if not manifest:
            raise SystemExit("--build requires --manifest or --collect")
        build(manifest, sample, candidates)
    if args.validate:
        if not manifest:
            raise SystemExit("--validate requires --manifest or --collect")
        validate(manifest, sample)
    if not (args.collect or args.build or args.validate):
        parser.print_help()


if __name__ == "__main__":
    main()
