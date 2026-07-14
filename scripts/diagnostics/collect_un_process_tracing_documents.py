#!/usr/bin/env python3
"""Collect UN process-tracing documents for selected Brazil-China votes.

Sources:
- Official Documents of the United Nations, documents.un.org
- UN General Assembly Third Committee proposal-status pages, un.org
- UN Digital Library Speeches collection RSS/search pages, digitallibrary.un.org
- Permanent Mission of China to the UN public statement archive

Access: public web/API endpoints, no credentials.
Last execution: 2026-05-16.

The script preserves raw files and writes derived CSV/text outputs. It does not
modify source voting data or the targets pipeline.
"""

from __future__ import annotations

import csv
import hashlib
import html
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable
from urllib.parse import quote, urlencode, urljoin
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ACCESS_DATE = "2026-05-16"
USER_AGENT = "red_trade_research_script/1.0 (academic reproducibility)"
BASE_DOC_URL = "https://documents.un.org/api/symbol/access"

CASES_PATH = Path("data/processed/unvotes/brazil_china_un_vote_cases_2004_2012.csv")
PLENARY_RECORDS_PATH = Path("data/processed/unvotes/brazil_china_un_vote_meeting_records_2004_2012.csv")

RAW_RES_DIR = Path("data/raw/un_docs/resolutions")
RAW_REPORT_DIR = Path("data/raw/un_docs/committee_reports")
RAW_DRAFT_DIR = Path("data/raw/un_docs/drafts")
RAW_COMMITTEE_RECORD_DIR = Path("data/raw/un_docs/committee_records")
RAW_STATUS_DIR = Path("data/raw/un_docs/third_committee_status")
RAW_UNDL_DIR = Path("data/raw/un_docs/digital_library_speeches_search")
RAW_MISSION_DIR = Path("data/raw/un_docs/mission_statements")
TEXT_DIR = Path("data/processed/un_docs/text")

OUT_DIR = Path("data/processed/unvotes")
REPORT_DIR = Path("quality_reports/un_vote_cases")

DOCUMENTS_OUT = OUT_DIR / "brazil_china_un_vote_process_tracing_documents_2004_2012.csv"
COMMITTEE_SPEECHES_OUT = OUT_DIR / "brazil_china_un_vote_committee_speech_evidence_2004_2012.csv"
UNDL_SEARCH_OUT = OUT_DIR / "brazil_china_un_vote_undl_speeches_search_2004_2012.csv"
MISSION_OUT = OUT_DIR / "brazil_china_un_vote_mission_statement_candidates_2004_2012.csv"
SOURCE_LOG_OUT = REPORT_DIR / "UN_PROCESS_TRACING_DOCUMENT_COLLECTION_LOG.md"


def ensure_dirs() -> None:
    for directory in (
        RAW_RES_DIR,
        RAW_REPORT_DIR,
        RAW_DRAFT_DIR,
        RAW_COMMITTEE_RECORD_DIR,
        RAW_STATUS_DIR,
        RAW_UNDL_DIR,
        RAW_MISSION_DIR,
        TEXT_DIR,
        OUT_DIR,
        REPORT_DIR,
    ):
        directory.mkdir(parents=True, exist_ok=True)


def symbol_to_filename(symbol: str, suffix: str) -> str:
    safe = (
        symbol.replace("/", "_")
        .replace(".", "_")
        .replace(" ", "_")
        .replace("(", "")
        .replace(")", "")
    )
    return f"{safe}{suffix}"


def query_to_filename(prefix: str, query: str, suffix: str) -> str:
    digest = hashlib.sha1(query.encode("utf-8")).hexdigest()[:12]
    return f"{prefix}_{digest}{suffix}"


def documents_url(symbol: str) -> str:
    return f"{BASE_DOC_URL}?l=en&s={quote(symbol, safe='')}&t=pdf"


def log(message: str) -> None:
    print(message, flush=True)


def request_bytes(url: str, timeout: int = 25) -> bytes:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    last_error: Exception | None = None
    for attempt in range(2):
        try:
            with urlopen(request, timeout=timeout) as response:
                return response.read()
        except HTTPError as exc:
            if exc.code in {400, 401, 403, 404}:
                raise RuntimeError(f"HTTP {exc.code}") from exc
            last_error = exc
            time.sleep(1 + attempt)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(1 + attempt)
    raise RuntimeError(f"Could not fetch {url}: {last_error}")


def download_pdf(symbol: str, output_dir: Path) -> tuple[Path, str]:
    out_path = output_dir / symbol_to_filename(symbol, ".pdf")
    if out_path.exists() and out_path.stat().st_size > 1024:
        return out_path, "existing"
    try:
        payload = request_bytes(documents_url(symbol))
        if len(payload) <= 1024 or not payload.startswith(b"%PDF"):
            raise RuntimeError("response was not a valid PDF")
        out_path.write_bytes(payload)
        return out_path, "downloaded"
    except Exception as exc:  # noqa: BLE001
        return out_path, f"failed: {exc}"


def download_html(url: str, output_dir: Path, prefix: str) -> tuple[Path, str, str]:
    out_path = output_dir / query_to_filename(prefix, url, ".html")
    if out_path.exists() and out_path.stat().st_size > 100:
        payload = out_path.read_bytes()
        return out_path, payload.decode("utf-8", errors="replace"), "existing"
    try:
        payload = request_bytes(url)
        out_path.write_bytes(payload)
        return out_path, payload.decode("utf-8", errors="replace"), "downloaded"
    except Exception as exc:  # noqa: BLE001
        return out_path, "", f"failed: {exc}"


def download_rss(url: str, output_dir: Path, prefix: str) -> tuple[Path, str, str]:
    out_path = output_dir / query_to_filename(prefix, url, ".xml")
    if out_path.exists() and out_path.stat().st_size > 100:
        payload = out_path.read_bytes()
        return out_path, payload.decode("utf-8", errors="replace"), "existing"
    try:
        payload = request_bytes(url)
        out_path.write_bytes(payload)
        return out_path, payload.decode("utf-8", errors="replace"), "downloaded"
    except Exception as exc:  # noqa: BLE001
        return out_path, "", f"failed: {exc}"


def pdf_to_text(pdf_path: Path) -> str:
    text_path = TEXT_DIR / f"{pdf_path.stem}.txt"
    result = subprocess.run(
        ["pdftotext", "-raw", str(pdf_path), "-"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    text_path.write_text(result.stdout, encoding="utf-8")
    return result.stdout


def html_to_text(raw_html: str) -> str:
    without_scripts = re.sub(r"(?is)<(script|style).*?</\1>", " ", raw_html)
    without_tags = re.sub(r"(?s)<[^>]+>", " ", without_scripts)
    text = html.unescape(without_tags)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def clean_space(text: str) -> str:
    text = text.replace("\u00a0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def short_excerpt(text: str, limit: int = 900) -> str:
    cleaned = clean_space(text)
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1].rstrip() + "…"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def resolution_session(symbol: str) -> str:
    match = re.match(r"A/RES/(\d+)/", symbol)
    if not match:
        return ""
    return match.group(1)


def committee_number(label: str) -> str:
    lower = label.lower()
    if "third committee" in lower:
        return "3"
    if "first committee" in lower:
        return "1"
    if "second committee" in lower:
        return "2"
    if "fourth committee" in lower:
        return "4"
    if "fifth committee" in lower:
        return "5"
    if "sixth committee" in lower:
        return "6"
    return ""


REPORT_RE = re.compile(r"A/\d+/\d+(?:/Add\.\d+)?(?:/Corr\.\d+)?", re.I)
DRAFT_RE = re.compile(r"A/C\.\d+/\d+/(?:L|CRP)\.\d+(?:/Rev\.\d+)?(?:/Add\.\d+)?", re.I)
MEETING_RE = re.compile(r"A/C\.\d+/\d+/(?:SR|PV)\.\d+", re.I)
MEETING_NO_RE = re.compile(r"(\d+)(?:st|nd|rd|th)\s+(?:meeting|mtg\.?)", re.I)


def extract_report_refs(resolution_text: str) -> list[dict[str, str]]:
    refs: list[dict[str, str]] = []
    for match in re.finditer(r"\[on the report of the ([^\]]+?)\]", resolution_text, re.I | re.S):
        chunk = clean_space(match.group(1))
        committee = ""
        committee_match = re.search(r"(First|Second|Third|Fourth|Fifth|Sixth) Committee", chunk, re.I)
        if committee_match:
            committee = f"{committee_match.group(1).title()} Committee"
        symbols = REPORT_RE.findall(chunk)
        for symbol in symbols:
            refs.append(
                {
                    "report_symbol": symbol,
                    "committee": committee,
                    "committee_no": committee_number(committee),
                    "report_context": chunk,
                }
            )
            corr_match = re.search(rf"{re.escape(symbol)}[^]]*?\bCorr\.(\d+)", chunk, re.I)
            if corr_match and "/Corr." not in symbol:
                refs.append(
                    {
                        "report_symbol": f"{symbol}/Corr.{corr_match.group(1)}",
                        "committee": committee,
                        "committee_no": committee_number(committee),
                        "report_context": chunk,
                    }
                )
    return refs


def case_keywords(row: dict[str, str]) -> list[str]:
    text = f"{row.get('theme', '')} {row.get('descr', '')} {row.get('short', '')}".lower()
    rules = [
        ("dprk", ["Democratic People's Republic of Korea", "Democratic People’s Republic of Korea", "DPRK"]),
        ("korea", ["Democratic People's Republic of Korea", "Democratic People’s Republic of Korea", "DPRK"]),
        ("iran", ["Islamic Republic of Iran", "Iran"]),
        ("death penalty", ["death penalty", "moratorium"]),
        ("globalization", ["globalization", "globalisation"]),
        ("human rights council", ["Human Rights Council"]),
        ("reducing nuclear danger", ["reducing nuclear danger"]),
        ("icj", ["International Court of Justice", "nuclear weapons"]),
    ]
    out: list[str] = []
    for trigger, keywords in rules:
        if trigger in text:
            out.extend(keywords)
    if not out and row.get("theme"):
        out.append(row["theme"])
    return list(dict.fromkeys(out))


def window_around(text: str, start: int, before: int = 1800, after: int = 2400) -> str:
    return text[max(0, start - before) : min(len(text), start + after)]


def window_has_keyword(window: str, keywords: list[str]) -> bool:
    lower = window.lower()
    return any(keyword.lower() in lower for keyword in keywords)


def extract_case_drafts(report_text: str, row: dict[str, str]) -> list[dict[str, str]]:
    keywords = case_keywords(row)
    matches = list(DRAFT_RE.finditer(report_text))
    if not matches:
        return []
    candidate_rows = []
    for match in matches:
        context = window_around(report_text, match.start())
        if window_has_keyword(context, keywords) or len(matches) <= 5:
            candidate_rows.append(
                {
                    "draft_symbol": match.group(0),
                    "draft_context": short_excerpt(context, limit=1200),
                }
            )
    if not candidate_rows:
        for match in matches:
            context = window_around(report_text, match.start())
            candidate_rows.append(
                {
                    "draft_symbol": match.group(0),
                    "draft_context": short_excerpt(context, limit=1200),
                }
            )
    deduped: dict[str, dict[str, str]] = {}
    for item in candidate_rows:
        deduped.setdefault(item["draft_symbol"], item)
    return list(deduped.values())


def extract_meeting_numbers_for_case(text: str, row: dict[str, str], draft_symbols: Iterable[str]) -> list[str]:
    keywords = case_keywords(row)
    anchors: list[int] = []
    lower = text.lower()
    for draft_symbol in draft_symbols:
        for match in re.finditer(re.escape(draft_symbol), text, re.I):
            anchors.append(match.start())
    for keyword in keywords:
        idx = lower.find(keyword.lower())
        while idx != -1:
            anchors.append(idx)
            idx = lower.find(keyword.lower(), idx + len(keyword))
    if not anchors:
        anchors = [0]

    meeting_numbers: set[str] = set()
    for anchor in anchors:
        context = window_around(text, anchor, before=3000, after=3500)
        for match in MEETING_NO_RE.finditer(context):
            meeting_no = match.group(1)
            if 1 <= int(meeting_no) <= 90:
                meeting_numbers.add(meeting_no)
    return sorted(meeting_numbers, key=lambda value: int(value))


SPEAKER_START = re.compile(
    r"(?m)^\s*(?:\d+\.\s*)?"
    r"(Mr\.|Ms\.|Mrs\.|Miss|Madam|Sir)\s+[^:\n]{0,160}\((Brazil|China)\)"
    r"(?:[^:\n]*:|\s+(?:said|stated|noted|welcomed|reiterated|asked|emphasized|emphasised|"
    r"explained|observed|expressed|supported|opposed)\b)",
    re.I,
)
NEXT_SPEAKER = re.compile(
    r"(?m)^\s*(?:\d+\.\s*)?"
    r"(Mr\.|Ms\.|Mrs\.|Miss|Madam|Sir|The Chair|The Chairman|The Chairperson|"
    r"The President|The Acting President)\b[^:\n]{0,200}"
    r"(?::|\s+(?:said|stated|noted|welcomed|reiterated|asked|emphasized|emphasised|"
    r"explained|observed|expressed|supported|opposed)\b)",
    re.I,
)


def iter_country_speeches(text: str) -> Iterable[dict[str, str | int]]:
    matches = list(SPEAKER_START.finditer(text))
    for idx, match in enumerate(matches):
        country = match.group(2)
        next_match = NEXT_SPEAKER.search(text, match.end())
        end = next_match.start() if next_match else len(text)
        if end <= match.end() and idx + 1 < len(matches):
            end = matches[idx + 1].start()
        yield {
            "country": country,
            "start": match.start(),
            "end": end,
            "speech": clean_space(text[match.start() : end]),
        }


def speech_relevance(speech: str, row: dict[str, str], draft_symbols: Iterable[str]) -> tuple[bool, str]:
    lower = speech.lower()
    for keyword in case_keywords(row):
        if keyword.lower() in lower:
            return True, "mentions selected theme"
    for draft_symbol in draft_symbols:
        if draft_symbol.lower() in lower:
            return True, "mentions draft symbol"
    if row.get("doc_symbol", "").lower() in lower:
        return True, "mentions resolution symbol"
    return False, ""


def parse_rss_items(raw_xml: str) -> list[dict[str, str]]:
    if not raw_xml.strip():
        return []
    try:
        root = ET.fromstring(raw_xml)
    except ET.ParseError:
        return []
    items: list[dict[str, str]] = []
    for item in root.findall(".//item"):
        title = item.findtext("title") or ""
        link = item.findtext("link") or ""
        description = item.findtext("description") or ""
        items.append(
            {
                "title": html.unescape(title),
                "link": link,
                "description": html_to_text(description),
            }
        )
    return items


def undl_search_urls(query: str) -> tuple[str, str]:
    params = {"ln": "en", "cc": "Speeches", "p": query, "rg": "25"}
    search_url = f"https://digitallibrary.un.org/search?{urlencode(params)}"
    rss_url = f"https://digitallibrary.un.org/rss?{urlencode(params)}"
    return search_url, rss_url


def third_committee_status_urls(session: str) -> list[str]:
    base = f"https://www.un.org/en/ga/third/{session}/proposalstatus.shtml"
    return [base]


def expand_paginated_status_urls(raw_html: str, first_url: str) -> list[str]:
    match = re.search(r"countPage\s*=\s*(\d+)", raw_html)
    if not match:
        return [first_url]
    count = int(match.group(1))
    urls = [first_url]
    base = first_url.rsplit("/", 1)[0] + "/"
    for page in range(1, count):
        urls.append(urljoin(base, f"proposalstatus_{page}.shtml"))
    return urls


def crawl_third_committee_status_pages(sessions: Iterable[str]) -> dict[str, str]:
    by_session: dict[str, str] = {}
    for session in sorted(set(sessions), key=int):
        log(f"Fetching Third Committee status page, session {session}")
        first_url = third_committee_status_urls(session)[0]
        first_path, first_html, first_status = download_html(first_url, RAW_STATUS_DIR, f"third_status_{session}")
        html_parts = [first_html]
        if first_status.startswith(("downloaded", "existing")):
            for url in expand_paginated_status_urls(first_html, first_url)[1:]:
                _, page_html, _ = download_html(url, RAW_STATUS_DIR, f"third_status_{session}")
                html_parts.append(page_html)
        combined = "\n".join(html_parts)
        by_session[session] = html_to_text(combined)
        text_path = TEXT_DIR / f"third_committee_status_{session}.txt"
        text_path.write_text(by_session[session], encoding="utf-8")
    return by_session


def crawl_china_mission_pages() -> list[dict[str, str]]:
    category_urls = [
        "https://un.china-mission.gov.cn/eng/chinaandun/socialhr/3rdcommittee/",
        "https://un.china-mission.gov.cn/eng/chinaandun/socialhr/rqwt/",
    ]
    category_pages: list[tuple[str, str]] = []
    for category_url in category_urls:
        path, raw_html, status = download_html(category_url, RAW_MISSION_DIR, "china_category")
        if not status.startswith(("downloaded", "existing")):
            continue
        category_pages.append((category_url, raw_html))
        match = re.search(r"countPage\s*=\s*(\d+)", raw_html)
        if match:
            count = int(match.group(1))
            for page in range(1, count):
                page_url = urljoin(category_url, f"index_{page}.htm")
                _, page_html, page_status = download_html(page_url, RAW_MISSION_DIR, "china_category")
                if page_status.startswith(("downloaded", "existing")):
                    category_pages.append((page_url, page_html))

    relevant_terms = [
        "third committee",
        "human rights",
        "human rights council",
        "death penalty",
        "iran",
        "korea",
        "globalization",
        "racism",
    ]
    rows: list[dict[str, str]] = []
    seen_urls: set[str] = set()
    for page_url, raw_html in category_pages:
        for match in re.finditer(r'<a\s+href="([^"]+)"[^>]*>(.*?)</a>', raw_html, re.I | re.S):
            href = html.unescape(match.group(1))
            title = html_to_text(match.group(2))
            if not title:
                continue
            year_match = re.search(r"(20\d{2}|19\d{2})[-/]\d{2}[-/]\d{2}", title)
            if not year_match:
                year_match = re.search(r"/(20\d{2})(?:\d{2})?/", href)
            if not year_match:
                continue
            year = int(year_match.group(1))
            if year < 2004 or year > 2012:
                continue
            if not any(term in title.lower() for term in relevant_terms):
                continue
            url = urljoin(page_url, href)
            if url in seen_urls:
                continue
            seen_urls.add(url)
            log(f"Fetching China mission candidate: {title[:70]}")
            article_path, article_html, status = download_html(url, RAW_MISSION_DIR, "china_statement")
            article_text = html_to_text(article_html)
            text_path = TEXT_DIR / f"{article_path.stem}.txt"
            if article_text:
                text_path.write_text(article_text, encoding="utf-8")
            rows.append(
                {
                    "country": "China",
                    "title": title,
                    "year": str(year),
                    "url": url,
                    "local_path": str(article_path),
                    "text_path": str(text_path) if article_text else "",
                    "download_status": status,
                    "excerpt": short_excerpt(article_text, limit=600),
                    "date_accessed": ACCESS_DATE,
                }
            )
    return rows


def official_search_rows(row: dict[str, str]) -> list[dict[str, str]]:
    theme = row.get("theme", "")
    session = resolution_session(row.get("doc_symbol", ""))
    query_base = f"{theme} {session}th session {row.get('doc_symbol', '')}"
    urls = [
        (
            "Brazil",
            "Gov.br/MRE site search",
            "https://www.gov.br/mre/pt-br/search?" + urlencode({"SearchableText": query_base}),
        ),
        (
            "Brazil",
            "Gov.br/MRE English site search",
            "https://www.gov.br/mre/en/search?" + urlencode({"SearchableText": query_base}),
        ),
        (
            "China",
            "Permanent Mission of China site query",
            "https://un.china-mission.gov.cn/eng/search/?" + urlencode({"query": query_base}),
        ),
        (
            "Brazil/China",
            "UN Member States on the Record",
            "https://www.un.org/en/library/unms",
        ),
    ]
    out = []
    for country, source_type, url in urls:
        out.append(
            {
                "case_id": row["case_id"],
                "theme": theme,
                "doc_symbol": row["doc_symbol"],
                "year": row["year"],
                "country": country,
                "source_type": source_type,
                "query": query_base,
                "url": url,
                "status": "search_url_documented",
                "date_accessed": ACCESS_DATE,
            }
        )
    return out


def main() -> int:
    ensure_dirs()
    cases = read_csv(CASES_PATH)
    if not cases:
        raise RuntimeError(f"No rows found in {CASES_PATH}")

    human_rights_sessions = [
        resolution_session(row["doc_symbol"])
        for row in cases
        if row.get("issue") == "Human rights"
    ]
    status_text_by_session = crawl_third_committee_status_pages(human_rights_sessions)

    documents_rows: list[dict[str, str]] = []
    speech_rows: list[dict[str, str]] = []
    undl_rows: list[dict[str, str]] = []
    search_rows: list[dict[str, str]] = []
    report_cache: dict[str, str] = {}
    committee_record_cache: dict[str, str] = {}
    case_to_committee_records: dict[str, set[str]] = {}
    case_to_drafts: dict[str, set[str]] = {}

    for row in cases:
        log(f"Processing {row['doc_symbol']} ({row['case_id']}, {row['year']})")
        case_key = f"{row['case_id']}::{row['doc_symbol']}"
        case_to_committee_records.setdefault(case_key, set())
        case_to_drafts.setdefault(case_key, set())

        resolution_pdf, resolution_status = download_pdf(row["doc_symbol"], RAW_RES_DIR)
        resolution_text = pdf_to_text(resolution_pdf) if resolution_pdf.exists() and resolution_pdf.stat().st_size > 1024 else ""
        documents_rows.append(
            {
                "case_id": row["case_id"],
                "theme": row["theme"],
                "year": row["year"],
                "issue": row["issue"],
                "source_resolution": row["doc_symbol"],
                "document_layer": "resolution",
                "document_symbol": row["doc_symbol"],
                "committee": "",
                "url": documents_url(row["doc_symbol"]),
                "local_path": str(resolution_pdf),
                "download_status": resolution_status,
                "notes": "Official resolution text.",
                "date_accessed": ACCESS_DATE,
            }
        )

        report_refs = extract_report_refs(resolution_text)
        for report_ref in report_refs:
            report_symbol = report_ref["report_symbol"]
            log(f"  Report {report_symbol}")
            report_pdf, report_status = download_pdf(report_symbol, RAW_REPORT_DIR)
            report_text = ""
            if report_pdf.exists() and report_pdf.stat().st_size > 1024:
                if report_symbol not in report_cache:
                    report_cache[report_symbol] = pdf_to_text(report_pdf)
                report_text = report_cache[report_symbol]
            documents_rows.append(
                {
                    "case_id": row["case_id"],
                    "theme": row["theme"],
                    "year": row["year"],
                    "issue": row["issue"],
                    "source_resolution": row["doc_symbol"],
                    "document_layer": "committee_report",
                    "document_symbol": report_symbol,
                    "committee": report_ref["committee"],
                    "url": documents_url(report_symbol),
                    "local_path": str(report_pdf),
                    "download_status": report_status,
                    "notes": report_ref["report_context"],
                    "date_accessed": ACCESS_DATE,
                }
            )

            case_drafts = extract_case_drafts(report_text, row)
            for draft in case_drafts:
                draft_symbol = draft["draft_symbol"]
                log(f"    Draft {draft_symbol}")
                case_to_drafts[case_key].add(draft_symbol)
                draft_pdf, draft_status = download_pdf(draft_symbol, RAW_DRAFT_DIR)
                draft_text = ""
                if draft_pdf.exists() and draft_pdf.stat().st_size > 1024:
                    draft_text = pdf_to_text(draft_pdf)
                documents_rows.append(
                    {
                        "case_id": row["case_id"],
                        "theme": row["theme"],
                        "year": row["year"],
                        "issue": row["issue"],
                        "source_resolution": row["doc_symbol"],
                        "document_layer": "draft",
                        "document_symbol": draft_symbol,
                        "committee": report_ref["committee"],
                        "url": documents_url(draft_symbol),
                        "local_path": str(draft_pdf),
                        "download_status": draft_status,
                        "notes": draft["draft_context"] if draft_text or draft_status.startswith("failed") else "Draft symbol found in committee report.",
                        "date_accessed": ACCESS_DATE,
                    }
                )

            if row.get("issue") == "Human rights" and report_ref["committee_no"] == "3":
                session = resolution_session(row["doc_symbol"])
                status_text = status_text_by_session.get(session, "")
                meeting_numbers = set(extract_meeting_numbers_for_case(report_text, row, case_to_drafts[case_key]))
                meeting_numbers.update(extract_meeting_numbers_for_case(status_text, row, case_to_drafts[case_key]))
                for meeting_no in sorted(meeting_numbers, key=int):
                    record_symbol = f"A/C.3/{session}/SR.{meeting_no}"
                    log(f"    Third Committee record {record_symbol}")
                    case_to_committee_records[case_key].add(record_symbol)
                    record_pdf, record_status = download_pdf(record_symbol, RAW_COMMITTEE_RECORD_DIR)
                    record_text = ""
                    if record_pdf.exists() and record_pdf.stat().st_size > 1024:
                        if record_symbol not in committee_record_cache:
                            committee_record_cache[record_symbol] = pdf_to_text(record_pdf)
                        record_text = committee_record_cache[record_symbol]
                    documents_rows.append(
                        {
                            "case_id": row["case_id"],
                            "theme": row["theme"],
                            "year": row["year"],
                            "issue": row["issue"],
                            "source_resolution": row["doc_symbol"],
                            "document_layer": "third_committee_record",
                            "document_symbol": record_symbol,
                            "committee": "Third Committee",
                            "url": documents_url(record_symbol),
                            "local_path": str(record_pdf),
                            "download_status": record_status,
                            "notes": "Derived from committee report/status-page meeting references near the selected draft/theme.",
                            "date_accessed": ACCESS_DATE,
                        }
                    )
                    country_speeches = list(iter_country_speeches(record_text)) if record_text else []
                    for country in ("Brazil", "China"):
                        selected = None
                        relevance_rule = ""
                        same_country = [
                            speech
                            for speech in country_speeches
                            if str(speech["country"]).lower() == country.lower()
                        ]
                        for speech in same_country:
                            is_relevant, rule = speech_relevance(str(speech["speech"]), row, case_to_drafts[case_key])
                            if is_relevant:
                                selected = speech
                                relevance_rule = rule
                                break
                        speech_rows.append(
                            {
                                "case_id": row["case_id"],
                                "theme": row["theme"],
                                "doc_symbol": row["doc_symbol"],
                                "year": row["year"],
                                "country": country,
                                "vote": row["vote_brazil"] if country == "Brazil" else row["vote_china"],
                                "committee_record_symbol": record_symbol,
                                "committee_record_url": documents_url(record_symbol),
                                "draft_symbols": "; ".join(sorted(case_to_drafts[case_key])),
                                "speech_found_in_record": "TRUE" if same_country else "FALSE",
                                "speech_found_for_case": "TRUE" if selected else "FALSE",
                                "relevance_rule": relevance_rule,
                                "speaker_excerpt": short_excerpt(str(selected["speech"])) if selected else "",
                                "source_note": "Official Third Committee summary record, extracted from documents.un.org PDF.",
                                "date_accessed": ACCESS_DATE,
                            }
                        )

        for search_row in official_search_rows(row):
            search_rows.append(search_row)

    # UN Digital Library Speeches collection searches by country, theme, session,
    # resolution, draft, and available committee/plenary meeting symbols.
    plenary_symbols: dict[str, str] = {}
    if PLENARY_RECORDS_PATH.exists():
        for record in read_csv(PLENARY_RECORDS_PATH):
            if record.get("meeting_symbol"):
                plenary_symbols[record["meeting_symbol"]] = record.get("meeting_url", "")

    seen_queries: set[tuple[str, str, str]] = set()
    for row in cases:
        log(f"Searching UN Digital Library Speeches for {row['doc_symbol']}")
        case_key = f"{row['case_id']}::{row['doc_symbol']}"
        session = resolution_session(row["doc_symbol"])
        base_queries = [
            ("theme_session", f'"{row["theme"]}" "{session}th session"'),
            ("resolution_symbol", f'"{row["doc_symbol"]}"'),
        ]
        for draft_symbol in sorted(case_to_drafts.get(case_key, set())):
            base_queries.append(("draft_symbol", f'"{draft_symbol}"'))
        for record_symbol in sorted(case_to_committee_records.get(case_key, set())):
            base_queries.append(("committee_record_symbol", f'"{record_symbol}"'))
        for meeting_symbol in sorted(plenary_symbols):
            if meeting_symbol.startswith(f"A/{session}/"):
                base_queries.append(("plenary_record_symbol", f'"{meeting_symbol}"'))

        for country in ("Brazil", "China"):
            for query_type, query_core in base_queries:
                query = f"{country} {query_core}"
                query_key = (row["doc_symbol"], country, query)
                if query_key in seen_queries:
                    continue
                seen_queries.add(query_key)
                search_url, rss_url = undl_search_urls(query)
                rss_path, raw_xml, rss_status = download_rss(rss_url, RAW_UNDL_DIR, "undl_speeches")
                items = parse_rss_items(raw_xml)
                undl_rows.append(
                    {
                        "case_id": row["case_id"],
                        "theme": row["theme"],
                        "doc_symbol": row["doc_symbol"],
                        "year": row["year"],
                        "country": country,
                        "query_type": query_type,
                        "query": query,
                        "search_url": search_url,
                        "rss_url": rss_url,
                        "rss_local_path": str(rss_path),
                        "download_status": rss_status,
                        "items_found": str(len(items)),
                        "first_item_title": items[0]["title"] if items else "",
                        "first_item_link": items[0]["link"] if items else "",
                        "date_accessed": ACCESS_DATE,
                    }
                )

    mission_rows = crawl_china_mission_pages()
    for mission in mission_rows:
        documents_rows.append(
            {
                "case_id": "",
                "theme": "",
                "year": mission["year"],
                "issue": "Human rights",
                "source_resolution": "",
                "document_layer": "mission_statement_candidate",
                "document_symbol": "",
                "committee": "",
                "url": mission["url"],
                "local_path": mission["local_path"],
                "download_status": mission["download_status"],
                "notes": mission["title"],
                "date_accessed": ACCESS_DATE,
            }
        )

    for search_row in search_rows:
        documents_rows.append(
            {
                "case_id": search_row["case_id"],
                "theme": search_row["theme"],
                "year": search_row["year"],
                "issue": "",
                "source_resolution": search_row["doc_symbol"],
                "document_layer": "official_national_search",
                "document_symbol": "",
                "committee": "",
                "url": search_row["url"],
                "local_path": "",
                "download_status": search_row["status"],
                "notes": f"{search_row['country']}: {search_row['source_type']}; query={search_row['query']}",
                "date_accessed": ACCESS_DATE,
            }
        )

    write_csv(
        DOCUMENTS_OUT,
        documents_rows,
        [
            "case_id",
            "theme",
            "year",
            "issue",
            "source_resolution",
            "document_layer",
            "document_symbol",
            "committee",
            "url",
            "local_path",
            "download_status",
            "notes",
            "date_accessed",
        ],
    )
    write_csv(
        COMMITTEE_SPEECHES_OUT,
        speech_rows,
        [
            "case_id",
            "theme",
            "doc_symbol",
            "year",
            "country",
            "vote",
            "committee_record_symbol",
            "committee_record_url",
            "draft_symbols",
            "speech_found_in_record",
            "speech_found_for_case",
            "relevance_rule",
            "speaker_excerpt",
            "source_note",
            "date_accessed",
        ],
    )
    write_csv(
        UNDL_SEARCH_OUT,
        undl_rows,
        [
            "case_id",
            "theme",
            "doc_symbol",
            "year",
            "country",
            "query_type",
            "query",
            "search_url",
            "rss_url",
            "rss_local_path",
            "download_status",
            "items_found",
            "first_item_title",
            "first_item_link",
            "date_accessed",
        ],
    )
    write_csv(
        MISSION_OUT,
        mission_rows,
        [
            "country",
            "title",
            "year",
            "url",
            "local_path",
            "text_path",
            "download_status",
            "excerpt",
            "date_accessed",
        ],
    )

    layer_counts: dict[str, int] = {}
    for doc in documents_rows:
        layer_counts[doc["document_layer"]] = layer_counts.get(doc["document_layer"], 0) + 1

    speech_hits = sum(1 for row in speech_rows if row["speech_found_for_case"] == "TRUE")
    undl_hits = sum(1 for row in undl_rows if int(row["items_found"] or "0") > 0)
    SOURCE_LOG_OUT.write_text(
        "\n".join(
            [
                "# Log de coleta: documentos para process tracing ONU",
                "",
                f"- Data de acesso: {ACCESS_DATE}",
                "- Fonte principal: Official Documents of the United Nations (`documents.un.org`).",
                "- Fonte auxiliar: páginas de status do Terceiro Comitê em `un.org/en/ga/third/`.",
                "- Fonte auxiliar: UN Digital Library, coleção `Speeches`, via RSS/search.",
                "- Fonte auxiliar: arquivo público da Missão Permanente da China junto à ONU.",
                "",
                "Arquivos brutos preservados:",
                f"- Relatórios de comissão: `{RAW_REPORT_DIR}`.",
                f"- Drafts: `{RAW_DRAFT_DIR}`.",
                f"- Atas de comitê: `{RAW_COMMITTEE_RECORD_DIR}`.",
                f"- Páginas de status do Terceiro Comitê: `{RAW_STATUS_DIR}`.",
                f"- Buscas RSS da coleção Speeches: `{RAW_UNDL_DIR}`.",
                f"- Registros de missão: `{RAW_MISSION_DIR}`.",
                "",
                "Tabelas derivadas:",
                f"- Inventário documental: `{DOCUMENTS_OUT}`.",
                f"- Evidência discursiva em atas de comitê: `{COMMITTEE_SPEECHES_OUT}`.",
                f"- Buscas na UN Digital Library Speeches: `{UNDL_SEARCH_OUT}`.",
                f"- Candidatos de missão nacional: `{MISSION_OUT}`.",
                "",
                "Contagem por camada documental:",
                *[f"- {layer}: {count}" for layer, count in sorted(layer_counts.items())],
                "",
                f"Falas Brasil/China associadas aos casos nas atas de comitê: {speech_hits}.",
                f"Buscas da coleção Speeches com ao menos um item RSS: {undl_hits}.",
                "",
                "Observação de escopo:",
                "- Atas do Terceiro Comitê foram buscadas apenas para resoluções de direitos humanos.",
                "- Para fontes nacionais, a coleta programática baixou candidatos da Missão da China e documentou URLs de busca oficiais para Brasil/MRE e UN Member States on the Record.",
            ]
        ),
        encoding="utf-8",
    )

    print(f"Saved document inventory: {DOCUMENTS_OUT}")
    print(f"Saved committee speech evidence: {COMMITTEE_SPEECHES_OUT}")
    print(f"Saved UNDL speeches search: {UNDL_SEARCH_OUT}")
    print(f"Saved mission candidates: {MISSION_OUT}")
    print(f"Saved collection log: {SOURCE_LOG_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
