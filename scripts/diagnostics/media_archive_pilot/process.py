#!/usr/bin/env python3
"""Build auditable pilot records and diagnostics from saved raw responses."""

from __future__ import annotations

import argparse
import csv
import hashlib
import html as std_html
import json
import re
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit

from lxml import html


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]

RECORD_FIELDS = [
    "source_id",
    "newspaper",
    "country",
    "iso3",
    "language",
    "requested_date",
    "observation_unit",
    "original_id",
    "original_url",
    "normalized_url",
    "title_original",
    "publication_datetime",
    "publication_datetime_utc",
    "publication_date",
    "publication_date_method",
    "publication_date_inferred",
    "date_matches_requested",
    "update_datetime",
    "update_datetime_utc",
    "source_page_or_endpoint",
    "source_raw_relative_path",
    "source_page_number",
    "collected_at_utc",
    "extraction_method",
    "china_mention_title",
    "usa_mention_title",
    "mention_ambiguity",
    "mention_matches",
    "duplicate_url",
    "duplicate_original_id",
    "possible_duplicate_title",
    "dedup_keep",
]

DIAGNOSTIC_FIELDS = [
    "source_id",
    "newspaper",
    "country",
    "requested_date",
    "observation_unit",
    "mechanism",
    "http_statuses",
    "access_outcome",
    "records_returned_by_source",
    "records_wrong_date",
    "records_before_dedup",
    "records_after_dedup",
    "duplicate_url_rows",
    "duplicate_original_id_rows",
    "possible_duplicate_title_rows",
    "source_declared_total",
    "source_declared_total_basis",
    "html_reconciliation_count",
    "pages_requested",
    "pagination_evidence",
    "pagination_complete",
    "denominator_assessment",
    "publication_date_method",
    "date_inferred_records",
    "update_only_records",
    "absence_type",
    "additional_volume_retrieved",
    "access_problems",
    "extraction_problems",
    "historical_structure_note",
    "fidelity_sample_n",
    "fidelity_result",
    "status",
    "status_justification",
]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite {path}")
    with path.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows([{field: serialize(row.get(field, "")) for field in fields} for row in rows])


def serialize(value: Any) -> Any:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return ""
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def clean_text(value: str | None) -> str:
    if not value:
        return ""
    decoded = std_html.unescape(value)
    try:
        text = html.fromstring(f"<div>{decoded}</div>").text_content()
    except (ValueError, html.ParserError):
        text = decoded
    return re.sub(r"\s+", " ", text).strip()


def normalize_url(url: str) -> str:
    if not url:
        return ""
    parts = urlsplit(url.strip())
    query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if not k.lower().startswith("utm_")]
    path = re.sub(r"/{2,}", "/", parts.path or "/")
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, urlencode(query), ""))


def normalize_title_for_duplicate(title: str) -> str:
    value = unicodedata.normalize("NFKC", title).casefold()
    value = re.sub(r"\s+", " ", value).strip()
    return value


def row_for_raw(request_rows: list[dict[str, str]], relative_path: str) -> dict[str, str]:
    matches = [row for row in request_rows if row["raw_relative_path"] == relative_path]
    if len(matches) != 1:
        raise ValueError(f"Expected one request-manifest row for {relative_path}; found {len(matches)}")
    return matches[0]


def base_record(source: dict[str, Any], requested_date: str, request: dict[str, str], raw_path: Path) -> dict[str, Any]:
    return {
        "source_id": source["source_id"],
        "newspaper": source["newspaper"],
        "country": source["country"],
        "iso3": source["iso3"],
        "language": source["language"],
        "requested_date": requested_date,
        "observation_unit": source["observation_unit"],
        "source_page_or_endpoint": request["requested_url"],
        "source_raw_relative_path": str(raw_path),
        "source_page_number": request["page_number"],
        "collected_at_utc": request["completed_at_utc"],
    }


def parse_wordpress(
    source: dict[str, Any], requested_date: str, raw_dir: Path, request_rows: list[dict[str, str]]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    records: list[dict[str, Any]] = []
    date_dir = raw_dir / source["source_id"] / requested_date
    api_paths = sorted(date_dir.glob("api_page_*.json"))
    returned = 0
    totals: list[str] = []
    total_pages_headers: list[str] = []
    successful_pages = 0
    for path in api_paths:
        relative = str(path.relative_to(raw_dir))
        request = row_for_raw(request_rows, relative)
        if request["status_code"] != "200":
            continue
        successful_pages += 1
        totals.append(request["x_wp_total"])
        total_pages_headers.append(request["x_wp_totalpages"])
        with path.open(encoding="utf-8") as handle:
            items = json.load(handle)
        if not isinstance(items, list):
            raise ValueError(f"Expected a JSON list in {path}")
        returned += len(items)
        for item in items:
            publication_datetime = item.get("date", "") or ""
            publication_datetime_utc = item.get("date_gmt", "") or ""
            publication_date = publication_datetime[:10] if publication_datetime else publication_datetime_utc[:10]
            title = clean_text((item.get("title") or {}).get("rendered", ""))
            original_url = item.get("link", "") or ""
            record = base_record(source, requested_date, request, Path(relative))
            record.update(
                {
                    "original_id": item.get("id", ""),
                    "original_url": original_url,
                    "normalized_url": normalize_url(original_url),
                    "title_original": title,
                    "publication_datetime": publication_datetime,
                    "publication_datetime_utc": publication_datetime_utc,
                    "publication_date": publication_date,
                    "publication_date_method": "wordpress_rest_date",
                    "publication_date_inferred": False,
                    "date_matches_requested": publication_date == requested_date,
                    "update_datetime": item.get("modified", "") or "",
                    "update_datetime_utc": item.get("modified_gmt", "") or "",
                    "extraction_method": "WordPress REST JSON fields",
                }
            )
            records.append(record)
    reconciliation_count: int | str = ""
    reconciliation_complete = False
    reconciliation_pages: int | str = ""
    reconciliation_path = date_dir / "daily_reconciliation.html"
    if reconciliation_path.exists():
        request = row_for_raw(request_rows, str(reconciliation_path.relative_to(raw_dir)))
        if request["status_code"] == "200":
            tree = html.fromstring(reconciliation_path.read_bytes())
            if source["source_id"] == "cyprus_mail":
                reconciliation_count = len(tree.xpath("//article[contains(@class, 'elementor-post')]") or tree.xpath("//article"))
            else:
                article_links = {
                    urljoin(request["final_url"] or request["requested_url"], href)
                    for href in tree.xpath("//article//a[@href]/@href")
                    if "/archives/" in href
                }
                reconciliation_count = len(article_links) if article_links else len(tree.xpath("//article"))
            load_more = tree.xpath("//*[@data-max-page]")
            if load_more:
                try:
                    reconciliation_pages = int(load_more[0].get("data-max-page", ""))
                except ValueError:
                    reconciliation_pages = ""
            reconciliation_complete = reconciliation_pages in {"", 1}
    declared_total = next((value for value in totals if value != ""), "")
    declared_pages = next((value for value in total_pages_headers if value != ""), "")
    if declared_pages != "":
        expected_saved_pages = max(int(declared_pages), 1)
    else:
        expected_saved_pages = len(api_paths)
    meta = {
        "records_returned_by_source": returned,
        "source_declared_total": declared_total,
        "source_declared_total_basis": "X-WP-Total for the pre-specified daily interval" if declared_total != "" else "",
        "html_reconciliation_count": reconciliation_count,
        "html_reconciliation_complete": reconciliation_complete,
        "html_reconciliation_pages": reconciliation_pages,
        "pages_requested": len(api_paths),
        "pagination_evidence": f"X-WP-TotalPages={declared_pages}" if declared_pages != "" else "No total-pages header received",
        "pagination_complete": bool(api_paths) and successful_pages == len(api_paths) == expected_saved_pages,
        "additional_volume_retrieved": (
            f"one daily HTML reconciliation page (first of {reconciliation_pages}; API remained the complete primary universe)"
            if reconciliation_pages not in {"", 1}
            else "one complete daily HTML reconciliation page"
        ),
    }
    return records, meta


def parse_latvian_date(value: str) -> str:
    match = re.search(r"\b(\d{2})\.(\d{2})\.(\d{4})\b", value)
    return f"{match.group(3)}-{match.group(2)}-{match.group(1)}" if match else ""


def parse_diena(
    source: dict[str, Any], requested_date: str, raw_dir: Path, request_rows: list[dict[str, str]]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    records: list[dict[str, Any]] = []
    date_dir = raw_dir / source["source_id"] / requested_date
    daily_path = date_dir / "daily_archive.html"
    monthly_path = date_dir / "month_index.html"
    declared_total: int | str = ""
    declared_basis = ""
    monthly_bytes = 0
    if monthly_path.exists():
        monthly_bytes = monthly_path.stat().st_size
        request = row_for_raw(request_rows, str(monthly_path.relative_to(raw_dir)))
        if request["status_code"] == "200":
            tree = html.fromstring(monthly_path.read_bytes())
            d = datetime.fromisoformat(requested_date)
            target_path = f"/arhivs/{d.year:04d}/{d.month:02d}/{d.day:02d}"
            for anchor in tree.xpath("//a[contains(@href, $target)]", target=target_path):
                match = re.search(r"(\d+)\s+rakst", clean_text(anchor.text_content()), flags=re.IGNORECASE)
                if match:
                    declared_total = int(match.group(1))
                    declared_basis = "count adjacent to requested date in monthly archive index"
                    break
    successful_daily = False
    if daily_path.exists():
        relative = str(daily_path.relative_to(raw_dir))
        request = row_for_raw(request_rows, relative)
        if request["status_code"] == "200":
            successful_daily = True
            tree = html.fromstring(daily_path.read_bytes())
            candidates: list[tuple[str, str, str]] = []
            for anchor in tree.xpath("//a[contains(@href, '/raksts/')]"):
                href = anchor.get("href", "")
                title_nodes = anchor.xpath(".//p[normalize-space()] | .//h2[normalize-space()] | .//h3[normalize-space()]")
                title = clean_text(title_nodes[0].text_content()) if title_nodes else clean_text(anchor.text_content())
                time_nodes = anchor.xpath(".//time[normalize-space()] | ancestor::*[self::article or self::li or self::div][1]//time[normalize-space()]")
                displayed_date = clean_text(time_nodes[0].text_content()) if time_nodes else ""
                if href and title and title.lower() not in {"lasīt", "vairāk"}:
                    candidates.append((href, title, displayed_date))
            seen_candidates: set[tuple[str, str]] = set()
            for href, title, displayed_date in candidates:
                absolute_url = urljoin(request["final_url"] or request["requested_url"], href)
                candidate_key = (absolute_url, title)
                if candidate_key in seen_candidates:
                    continue
                seen_candidates.add(candidate_key)
                publication_date = parse_latvian_date(displayed_date) or requested_date
                inferred = not bool(parse_latvian_date(displayed_date))
                id_match = re.search(r"-(\d+)$", urlsplit(absolute_url).path.rstrip("/"))
                record = base_record(source, requested_date, request, Path(relative))
                record.update(
                    {
                        "original_id": id_match.group(1) if id_match else "",
                        "original_url": absolute_url,
                        "normalized_url": normalize_url(absolute_url),
                        "title_original": title,
                        "publication_datetime": "",
                        "publication_datetime_utc": "",
                        "publication_date": publication_date,
                        "publication_date_method": "listing_time_element" if not inferred else "daily_archive_page_context",
                        "publication_date_inferred": inferred,
                        "date_matches_requested": publication_date == requested_date,
                        "update_datetime": "",
                        "update_datetime_utc": "",
                        "extraction_method": "Diena daily archive HTML listing",
                    }
                )
                records.append(record)
    meta = {
        "records_returned_by_source": len(records),
        "source_declared_total": declared_total,
        "source_declared_total_basis": declared_basis,
        "html_reconciliation_count": "",
        "pages_requested": 1 if daily_path.exists() else 0,
        "pagination_evidence": "single daily page; no pagination link expected in the date-specific route",
        "pagination_complete": successful_daily,
        "additional_volume_retrieved": f"monthly index only ({monthly_bytes} bytes); records restricted to requested day",
    }
    return records, meta


def parse_mbl(
    source: dict[str, Any], requested_date: str, raw_dir: Path, request_rows: list[dict[str, str]]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    records: list[dict[str, Any]] = []
    date_dir = raw_dir / source["source_id"] / requested_date
    daily_path = date_dir / "daily_archive_http.html"
    successful = False
    item_numbers: list[int] = []
    next_links: list[str] = []
    if daily_path.exists():
        relative = str(daily_path.relative_to(raw_dir))
        request = row_for_raw(request_rows, relative)
        if request["status_code"] == "200":
            tree = html.fromstring(daily_path.read_bytes())
            cards = tree.xpath("//div[contains(concat(' ', normalize-space(@class), ' '), ' grein-teaser ')]")
            for card in cards:
                links = card.xpath(".//h3/a[contains(@href, '/greinasafn/grein/')]")
                if not links:
                    continue
                link = links[0]
                title = clean_text(link.text_content())
                if not title:
                    continue
                original_url = urljoin(request["final_url"] or request["requested_url"], link.get("href", ""))
                parts = urlsplit(original_url)
                query = dict(parse_qsl(parts.query, keep_blank_values=True))
                try:
                    item_numbers.append(int(query["item_num"]))
                except (KeyError, ValueError):
                    pass
                id_match = re.search(r"/greinasafn/grein/(\d+)", parts.path)
                date_links = card.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' dags ')]//a[contains(@href, '/greinasafn/dagur/')]/@href")
                displayed_date_path = date_links[0] if date_links else ""
                date_match = re.search(r"/(\d{4})/(\d{2})/(\d{2})/?$", displayed_date_path)
                publication_date = "-".join(date_match.groups()) if date_match else query.get("dags", requested_date)
                inferred = not bool(date_match or query.get("dags"))
                normalized = urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path, "", ""))
                record = base_record(source, requested_date, request, Path(relative))
                record.update(
                    {
                        "original_id": id_match.group(1) if id_match else "",
                        "original_url": original_url,
                        "normalized_url": normalized,
                        "title_original": title,
                        "publication_datetime": "",
                        "publication_datetime_utc": "",
                        "publication_date": publication_date,
                        "publication_date_method": "daily_listing_date_link_and_dags_parameter" if not inferred else "daily_archive_page_context",
                        "publication_date_inferred": inferred,
                        "date_matches_requested": publication_date == requested_date,
                        "update_datetime": "",
                        "update_datetime_utc": "",
                        "extraction_method": "mbl.is daily archive HTML h3 listing",
                    }
                )
                records.append(record)
            next_links = tree.xpath("//link[contains(concat(' ', normalize-space(@rel), ' '), ' next ')]/@href | //a[contains(concat(' ', normalize-space(@rel), ' '), ' next ')]/@href")
            successful = True
    ordered = sorted(item_numbers)
    contiguous = bool(ordered) and ordered == list(range(0, len(ordered)))
    complete = successful and contiguous and not next_links and len(records) == len(ordered)
    meta = {
        "records_returned_by_source": len(records),
        "source_declared_total": "",
        "source_declared_total_basis": "",
        "html_reconciliation_count": "",
        "pages_requested": 1 if daily_path.exists() else 0,
        "pagination_evidence": (
            f"one daily page; item_num contiguous 0-{len(ordered) - 1}; no rel=next"
            if complete
            else "daily page failed, item_num was not contiguous, or a next link remained"
        ),
        "pagination_complete": complete,
        "additional_volume_retrieved": "daily listing HTML includes publisher teasers; only title/date/URL were processed",
    }
    return records, meta


def elpais_id(article: Any, url: str) -> str:
    for attr in ("data-id", "data-article-id", "id"):
        value = article.get(attr)
        if value and re.search(r"\d", value):
            return value
    return ""


def parse_elpais(
    source: dict[str, Any], requested_date: str, raw_dir: Path, request_rows: list[dict[str, str]]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    records: list[dict[str, Any]] = []
    date_dir = raw_dir / source["source_id"] / requested_date
    page_paths = sorted(date_dir.glob("archive_page_*.html"))
    successful_pages = 0
    last_has_next = False
    for page_path in page_paths:
        relative = str(page_path.relative_to(raw_dir))
        request = row_for_raw(request_rows, relative)
        if request["status_code"] != "200":
            continue
        successful_pages += 1
        tree = html.fromstring(page_path.read_bytes())
        next_links = tree.xpath("//link[contains(concat(' ', normalize-space(@rel), ' '), ' next ')]/@href | //a[contains(concat(' ', normalize-space(@rel), ' '), ' next ')]/@href")
        last_has_next = bool(next_links)
        articles = tree.xpath("//article")
        for article in articles:
            links = article.xpath(".//h2//a[@href] | .//h3//a[@href]")
            if not links:
                continue
            link = links[0]
            title = clean_text(link.text_content())
            if not title:
                continue
            original_url = urljoin(request["final_url"] or request["requested_url"], link.get("href", ""))
            time_nodes = article.xpath(".//time[@datetime]")
            item_datetime = time_nodes[0].get("datetime", "") if time_nodes else ""
            item_date = item_datetime[:10] if re.match(r"\d{4}-\d{2}-\d{2}", item_datetime) else requested_date
            inferred = not bool(item_datetime)
            record = base_record(source, requested_date, request, Path(relative))
            record.update(
                {
                    "original_id": elpais_id(article, original_url),
                    "original_url": original_url,
                    "normalized_url": normalize_url(original_url),
                    "title_original": title,
                    "publication_datetime": item_datetime,
                    "publication_datetime_utc": "",
                    "publication_date": item_date,
                    "publication_date_method": "listing_time_datetime" if item_datetime else "daily_archive_page_context",
                    "publication_date_inferred": inferred,
                    "date_matches_requested": item_date == requested_date,
                    "update_datetime": "",
                    "update_datetime_utc": "",
                    "extraction_method": "El País paginated daily archive HTML",
                }
            )
            records.append(record)
    complete = bool(page_paths) and successful_pages == len(page_paths) and not last_has_next
    meta = {
        "records_returned_by_source": len(records),
        "source_declared_total": "",
        "source_declared_total_basis": "",
        "html_reconciliation_count": "",
        "pages_requested": len(page_paths),
        "pagination_evidence": "followed rel=next until absent" if complete else "last saved page still exposes rel=next or a page failed",
        "pagination_complete": complete,
        "additional_volume_retrieved": "none beyond all pages of the requested daily archive",
    }
    return records, meta


def resolve_dictionary(config: dict[str, Any], source_id: str) -> dict[str, list[dict[str, Any]]]:
    dictionaries = config["mention_dictionaries"]
    entry = dictionaries[source_id]
    if "inherits" in entry:
        entry = dictionaries[entry["inherits"]]
    return entry


def apply_mentions(record: dict[str, Any], dictionary: dict[str, list[dict[str, Any]]]) -> None:
    title = record["title_original"]
    matches: list[str] = []
    ambiguous = False
    flags: dict[str, bool] = {}
    for entity in ("china", "usa"):
        found = False
        for variant in dictionary[entity]:
            if re.search(variant["regex"], title):
                found = True
                ambiguous = ambiguous or bool(variant["ambiguous"])
                matches.append(f"{entity}:{variant['label']}")
        flags[entity] = found
    record["china_mention_title"] = flags["china"]
    record["usa_mention_title"] = flags["usa"]
    record["mention_ambiguity"] = ambiguous
    record["mention_matches"] = "|".join(matches)


def apply_duplicate_flags(records: list[dict[str, Any]]) -> None:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        grouped[(record["source_id"], record["requested_date"])].append(record)
    for group in grouped.values():
        seen_urls: set[str] = set()
        seen_ids: set[str] = set()
        seen_titles: set[str] = set()
        for record in group:
            url = record["normalized_url"]
            original_id = str(record["original_id"] or "")
            title_key = normalize_title_for_duplicate(record["title_original"])
            duplicate_url = bool(url and url in seen_urls)
            duplicate_id = bool(original_id and original_id in seen_ids)
            possible_title = bool(title_key and title_key in seen_titles)
            record["duplicate_url"] = duplicate_url
            record["duplicate_original_id"] = duplicate_id
            record["possible_duplicate_title"] = possible_title
            record["dedup_keep"] = not (duplicate_url or duplicate_id)
            if url:
                seen_urls.add(url)
            if original_id:
                seen_ids.add(original_id)
            if title_key:
                seen_titles.add(title_key)


def statuses_for(request_rows: list[dict[str, str]], source_id: str, requested_date: str) -> tuple[str, str]:
    rows = [row for row in request_rows if row["source_id"] == source_id and row["requested_date"] == requested_date]
    statuses = sorted({row["status_code"] for row in rows if row["status_code"]})
    outcomes = sorted({row["outcome"] for row in rows})
    return "|".join(statuses), "|".join(outcomes)


def count_html_items(raw_path: Path, source_id: str) -> int:
    tree = html.fromstring(raw_path.read_bytes())
    if source_id == "cyprus_mail":
        return len(tree.xpath("//article[contains(@class, 'elementor-post')]") or tree.xpath("//article"))
    return len(tree.xpath("//article"))


def build_fidelity_sample(records: list[dict[str, Any]], raw_dir: Path) -> list[dict[str, Any]]:
    eligible = [row for row in records if row["date_matches_requested"] and row["dedup_keep"]]
    by_source_date: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in eligible:
        by_source_date[(row["source_id"], row["requested_date"])].append(row)
    sample: list[dict[str, Any]] = []
    for source_id in sorted({row["source_id"] for row in eligible}):
        dates = sorted(date for sid, date in by_source_date if sid == source_id)
        selected_dates = dates[:1] + dates[-1:] if len(dates) > 1 else dates
        for requested_date in dict.fromkeys(selected_dates):
            row = by_source_date[(source_id, requested_date)][0]
            raw_path = raw_dir / row["source_raw_relative_path"]
            if raw_path.suffix == ".json":
                with raw_path.open(encoding="utf-8") as handle:
                    items = json.load(handle)
                matching = [item for item in items if str(item.get("id", "")) == str(row["original_id"])]
                if len(matching) == 1:
                    item = matching[0]
                    title_match = clean_text((item.get("title") or {}).get("rendered", "")) == row["title_original"]
                    url_match = urlsplit(item.get("link", "")).path == urlsplit(row["original_url"]).path
                    date_evidence = (item.get("date") or item.get("date_gmt") or "")[:10] == requested_date
                else:
                    title_match = url_match = date_evidence = False
            else:
                undecoded = raw_path.read_text(encoding="utf-8", errors="replace")
                raw_text = clean_text(undecoded)
                title_match = row["title_original"] in raw_text
                url_match = urlsplit(row["original_url"]).path in undecoded
                date_evidence = row["publication_date"] == requested_date
            passed = title_match and url_match and date_evidence
            sample.append(
                {
                    "source_id": source_id,
                    "requested_date": requested_date,
                    "original_id": row["original_id"],
                    "original_url": row["original_url"],
                    "title_original": row["title_original"],
                    "publication_date": row["publication_date"],
                    "source_raw_relative_path": row["source_raw_relative_path"],
                    "verification_method": "exact title and URL-path comparison against saved source response; requested-day date evidence",
                    "title_match": title_match,
                    "url_match": url_match,
                    "date_match": date_evidence,
                    "result": "pass" if passed else "fail",
                }
            )
    return sample


def historical_note(source_id: str, requested_date: str) -> str:
    year = int(requested_date[:4])
    if source_id == "civil_georgia":
        return "Outside the publisher's declared online period (begins 2001)." if year == 2000 else "Current WordPress API serves this archived date; legacy and current archive routes coexist."
    if source_id == "cyprus_mail":
        if requested_date in {"2009-06-15", "2026-08-15"}:
            return "The legacy archive API returned zero and its daily HTML route returned 404; the recent date also falls after the publisher's move to a current platform."
        return "The legacy WordPress archive exposes article metadata for this date; the two successful dates do not prove uninterrupted daily coverage."
    if source_id == "diena":
        return "Early archive is absent or extremely sparse, consistent with a pre-2007 indexing break." if year == 2000 else "The current hierarchical year/month/day archive exposes article listings and a monthly day count."
    if source_id == "elpais":
        return "Older records use legacy article URL structures while the daily hemeroteca is presented by the current platform." if year <= 2014 else "Recent records use current article URL structures; daily archive pagination remains date-specific."
    if source_id == "mbl":
        return "The rate-limited HTTP request exposes dated records, while the optional headless browser is challenged; access depends on the automation mechanism."
    return ""


def mbl_browser_map(report_dir: Path) -> dict[str, dict[str, Any]]:
    path = report_dir / "mbl_browser_observations.json"
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    return {row["requested_date"]: row for row in data["dates"]}


def diagnose(
    config: dict[str, Any],
    request_rows: list[dict[str, str]],
    all_records: list[dict[str, Any]],
    meta_map: dict[tuple[str, str], dict[str, Any]],
    fidelity: list[dict[str, Any]],
    report_dir: Path,
    raw_dir: Path,
) -> list[dict[str, Any]]:
    groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for record in all_records:
        groups[(record["source_id"], record["requested_date"])].append(record)
    fidelity_groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in fidelity:
        fidelity_groups[(row["source_id"], row["requested_date"])].append(row)
    browser = mbl_browser_map(report_dir)
    headless_path = raw_dir / "mbl_headless_probe.csv"
    headless_rows = read_csv(headless_path) if headless_path.exists() else []
    diagnostics: list[dict[str, Any]] = []
    for source in config["sources"]:
        source_id = source["source_id"]
        for requested_date in config["fixed_dates"]:
            raw_group = groups[(source_id, requested_date)]
            group = [row for row in raw_group if row["date_matches_requested"]]
            meta = meta_map.get((source_id, requested_date), {})
            http_statuses, access_outcome = statuses_for(request_rows, source_id, requested_date)
            before = len(group)
            after = sum(bool(row["dedup_keep"]) for row in group)
            wrong_date = sum(not bool(row["date_matches_requested"]) for row in raw_group)
            declared = meta.get("source_declared_total", "")
            reconciliation = meta.get("html_reconciliation_count", "")
            pagination_complete = bool(meta.get("pagination_complete", False))
            access_problems = ""
            extraction_problems = ""
            absence_type = "none"
            status = "adequado"
            justification = "The explicit archive/API universe was enumerated and date/deduplication checks passed."
            denominator = ""

            if source_id in {"civil_georgia", "cyprus_mail"}:
                denominator = "publisher API total reconciled with all API pages"
                if declared != "" and int(declared) != meta.get("records_returned_by_source", 0):
                    extraction_problems = "X-WP-Total does not equal the number returned across saved pages"
                    status = "parcial"
                    justification = "The publisher total did not reconcile with the saved API pages."
                if meta.get("html_reconciliation_complete", False) and reconciliation != "" and before != reconciliation:
                    extraction_problems = (extraction_problems + "; " if extraction_problems else "") + "daily HTML listing count differs from exact-day API records"
                    status = "parcial"
                    justification = "API enumeration succeeded, but the HTML listing did not reconcile."
            elif source_id == "diena":
                denominator = "publisher day count in monthly index" if declared != "" else "recovered daily listing only; no source count found"
                if declared != "" and int(declared) != before:
                    extraction_problems = "monthly index day count does not equal parsed daily records"
                    status = "parcial"
                    justification = "The daily listing did not reconcile with the publisher's monthly-index count."
                elif declared == "":
                    status = "parcial" if before else "inconclusivo"
                    justification = "No publisher-provided day count was found for reconciliation."
            elif source_id == "elpais":
                denominator = "all records exposed by the rel=next daily archive chain; no independent publisher total"
                if not pagination_complete:
                    status = "parcial"
                    justification = "The saved archive pages do not demonstrate that pagination reached its end."
            elif source_id == "mbl":
                observed = browser.get(requested_date, {})
                probe = next((row for row in headless_rows if row["requested_date"] == requested_date), {})
                browser_count = observed.get("dom_unique_article_ids", "")
                access_problems = (
                    f"The optional headless probe outcome was {probe.get('outcome', 'not_run')}; "
                    "the rate-limited HTTP collector nevertheless returned the populated daily HTML."
                )
                reconciliation = browser_count
                denominator = "all article cards on the saved daily HTML; matched a separate browser DOM count; no publisher-declared total"
                if browser_count != "" and int(browser_count) == before and pagination_complete:
                    status = "adequado"
                    justification = "The saved daily listing was enumerated, item numbers were contiguous, no next page remained, and a separate browser DOM count matched."
                else:
                    status = "parcial"
                    justification = "The daily HTML was extracted, but page-end or browser-count reconciliation was incomplete."

            robots_blocked = "robots_disallowed" in access_outcome
            no_http_response = "request_failure" in access_outcome and "success" not in access_outcome
            if robots_blocked:
                access_problems = "robots.txt explicitly disallows the requested archive/API route for the pilot user agent; no content request was made"
                absence_type = "access_failure"
                status = "bloqueado"
                justification = "Collection stopped at the publisher's explicit robots.txt restriction; blank counts are preserved."
                denominator = "unknown because the content route was not requested"
                pagination_complete = False
            elif no_http_response:
                access_problems = "No HTTP response was obtained after the configured limited attempts"
                absence_type = "access_failure"
                status = "bloqueado"
                justification = "The source could not be reached by the collector; blank counts are preserved."
                denominator = "unknown because acquisition failed"
                pagination_complete = False
            elif source_id == "civil_georgia" and requested_date == "2000-06-15":
                absence_type = "outside_declared_online_coverage"
                status = "inconclusivo"
                justification = "The API returned no records, but Civil Georgia states that online publication began in 2001; this is not an observed zero-news day."
                denominator = "API query returned zero outside declared online coverage"
            elif before == 0 and source_id != "mbl":
                if "200" in http_statuses:
                    absence_type = "archive_returned_zero_not_zero_news"
                elif "404" in http_statuses:
                    absence_type = "archive_unavailable"
                else:
                    absence_type = "access_or_extraction_failure"
                if status == "adequado":
                    status = "inconclusivo"
                    justification = "The archive route returned no exact-day records; coverage is insufficient to interpret this as a zero-news day."

            inferred_count = sum(bool(row["publication_date_inferred"]) for row in group)
            update_only = sum(bool(row["update_datetime"]) and not bool(row["publication_datetime"]) for row in group)
            publication_methods = sorted({row["publication_date_method"] for row in group})
            sample_rows = fidelity_groups[(source_id, requested_date)]
            fidelity_result = "not_sampled" if not sample_rows else ("pass" if all(row["result"] == "pass" for row in sample_rows) else "fail")
            if fidelity_result == "fail" and status == "adequado":
                status = "parcial"
                justification = "At least one saved-source fidelity check failed."
            count_unavailable = robots_blocked or no_http_response or absence_type == "archive_unavailable"
            diagnostics.append(
                {
                    "source_id": source_id,
                    "newspaper": source["newspaper"],
                    "country": source["country"],
                    "requested_date": requested_date,
                    "observation_unit": source["observation_unit"],
                    "mechanism": source["mechanism"],
                    "http_statuses": http_statuses,
                    "access_outcome": access_outcome,
                    "records_returned_by_source": "" if count_unavailable else meta.get("records_returned_by_source", ""),
                    "records_wrong_date": "" if count_unavailable else wrong_date,
                    "records_before_dedup": "" if count_unavailable else before,
                    "records_after_dedup": "" if count_unavailable else after,
                    "duplicate_url_rows": "" if count_unavailable else sum(bool(row["duplicate_url"]) for row in group),
                    "duplicate_original_id_rows": "" if count_unavailable else sum(bool(row["duplicate_original_id"]) for row in group),
                    "possible_duplicate_title_rows": "" if count_unavailable else sum(bool(row["possible_duplicate_title"]) for row in group),
                    "source_declared_total": declared,
                    "source_declared_total_basis": meta.get("source_declared_total_basis", ""),
                    "html_reconciliation_count": reconciliation,
                    "pages_requested": meta.get("pages_requested", ""),
                    "pagination_evidence": meta.get("pagination_evidence", ""),
                    "pagination_complete": pagination_complete,
                    "denominator_assessment": denominator,
                    "publication_date_method": "|".join(publication_methods),
                    "date_inferred_records": "" if count_unavailable else inferred_count,
                    "update_only_records": "" if count_unavailable else update_only,
                    "absence_type": absence_type,
                    "additional_volume_retrieved": meta.get("additional_volume_retrieved", ""),
                    "access_problems": access_problems,
                    "extraction_problems": extraction_problems,
                    "historical_structure_note": historical_note(source_id, requested_date),
                    "fidelity_sample_n": len(sample_rows),
                    "fidelity_result": fidelity_result,
                    "status": status,
                    "status_justification": justification,
                }
            )
    return diagnostics


def build_source_manifest(config: dict[str, Any], requests: list[dict[str, str]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source in config["sources"]:
        source_rows = [row for row in requests if row["source_id"] == source["source_id"]]
        robots = next((row for row in source_rows if row["request_role"] == "robots"), {})
        conditions = next((row for row in source_rows if row["request_role"] == "access_conditions"), {})
        rows.append(
            {
                "source_id": source["source_id"],
                "newspaper": source["newspaper"],
                "country": source["country"],
                "iso3": source["iso3"],
                "language": source["language"],
                "donor_rank": source["donor_rank"],
                "donor_weight": source["donor_weight"],
                "observation_unit": source["observation_unit"],
                "mechanism": source["mechanism"],
                "robots_url": source["robots_url"],
                "robots_http_status": robots.get("status_code", ""),
                "conditions_url": source["conditions_url"],
                "conditions_http_status": conditions.get("status_code", ""),
                "known_restrictions_before_collection": source["known_restrictions"],
                "access_date": config["run_date"],
            }
        )
    return rows


def file_manifest_rows(paths: Iterable[Path], repo_root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in sorted({path.resolve() for path in paths if path.is_file()}):
        stat = path.stat()
        try:
            relative = path.relative_to(repo_root.resolve())
        except ValueError:
            relative = path
        rows.append(
            {
                "relative_path": str(relative),
                "bytes": stat.st_size,
                "sha256": sha256_file(path),
                "modified_at_utc": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(timespec="seconds"),
            }
        )
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=SCRIPT_DIR / "pilot_config.json")
    parser.add_argument("--raw-dir", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--report-dir", type=Path, default=REPO_ROOT / "quality_reports" / "media_archive_pilot")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    with args.config.open(encoding="utf-8") as handle:
        config = json.load(handle)
    raw_dir = (args.raw_dir or REPO_ROOT / "data" / "raw" / "media_archive_pilot" / config["run_date"]).resolve()
    output_dir = (args.output_dir or REPO_ROOT / "data" / "processed" / "media_archive_pilot" / config["run_date"]).resolve()
    report_dir = args.report_dir.resolve()
    if not (raw_dir / "_COLLECTION_COMPLETE.json").exists():
        raise FileNotFoundError("Raw collection completion marker is missing; refusing to process a partial collection.")
    output_dir.mkdir(parents=True, exist_ok=True)
    requests = read_csv(raw_dir / "collection_requests.csv")
    all_records: list[dict[str, Any]] = []
    meta_map: dict[tuple[str, str], dict[str, Any]] = {}
    for source in config["sources"]:
        for requested_date in config["fixed_dates"]:
            if source["parser"] == "wordpress_api":
                records, meta = parse_wordpress(source, requested_date, raw_dir, requests)
            elif source["parser"] == "diena_html":
                records, meta = parse_diena(source, requested_date, raw_dir, requests)
            elif source["parser"] == "elpais_html":
                records, meta = parse_elpais(source, requested_date, raw_dir, requests)
            elif source["parser"] == "mbl_http_diagnostic":
                records, meta = parse_mbl(source, requested_date, raw_dir, requests)
            else:
                raise ValueError(f"Unknown parser: {source['parser']}")
            dictionary = resolve_dictionary(config, source["source_id"])
            for record in records:
                apply_mentions(record, dictionary)
            all_records.extend(records)
            meta_map[(source["source_id"], requested_date)] = meta
    all_records.sort(key=lambda row: (row["source_id"], row["requested_date"], int(row["source_page_number"] or 0), row["original_url"], row["title_original"]))
    apply_duplicate_flags(all_records)
    fidelity = build_fidelity_sample(all_records, raw_dir)
    diagnostics = diagnose(config, requests, all_records, meta_map, fidelity, report_dir, raw_dir)

    records_path = output_dir / "records.csv"
    diagnostics_path = output_dir / "diagnostics.csv"
    fidelity_path = output_dir / "fidelity_sample.csv"
    request_manifest_path = output_dir / "request_manifest.csv"
    source_manifest_path = output_dir / "source_manifest.csv"
    write_csv(records_path, all_records, RECORD_FIELDS)
    write_csv(diagnostics_path, diagnostics, DIAGNOSTIC_FIELDS)
    write_csv(
        fidelity_path,
        fidelity,
        [
            "source_id",
            "requested_date",
            "original_id",
            "original_url",
            "title_original",
            "publication_date",
            "source_raw_relative_path",
            "verification_method",
            "title_match",
            "url_match",
            "date_match",
            "result",
        ],
    )
    write_csv(request_manifest_path, requests, list(requests[0].keys()))
    source_manifest = build_source_manifest(config, requests)
    write_csv(source_manifest_path, source_manifest, list(source_manifest[0].keys()))

    run_manifest_path = output_dir / "run_manifest.json"
    run_manifest = {
        "schema_version": "1.0.0",
        "run_date": config["run_date"],
        "execution_timezone": config["execution_timezone"],
        "fixed_dates": config["fixed_dates"],
        "source_ids": [source["source_id"] for source in config["sources"]],
        "diagnostic_rows": len(diagnostics),
        "extracted_record_rows_before_dedup": len(all_records),
        "extracted_record_rows_after_dedup": sum(bool(row["dedup_keep"]) for row in all_records),
        "raw_directory": str(raw_dir.relative_to(REPO_ROOT)),
        "processed_directory": str(output_dir.relative_to(REPO_ROOT)) if output_dir.is_relative_to(REPO_ROOT) else str(output_dir),
        "mention_scope": "title_original only",
        "translations_or_llm_topics": False,
        "article_bodies_downloaded": False,
        "processing_config_sha256": sha256_file(args.config.resolve()),
    }
    with run_manifest_path.open("x", encoding="utf-8") as handle:
        json.dump(run_manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"Processed {len(all_records)} extracted rows into {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
