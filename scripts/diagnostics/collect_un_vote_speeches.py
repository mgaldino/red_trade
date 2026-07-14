#!/usr/bin/env python3
"""Collect UN meeting-record evidence for selected Brazil-China UNGA votes.

Source: Official UN Documents API (documents.un.org)
Access: public API / PDF download
Credentials: none
Last execution: 2026-05-16

The script preserves raw PDFs and writes derived CSV/text outputs. It does not
modify source voting data.
"""

from __future__ import annotations

import csv
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable
from urllib.parse import quote
from urllib.request import Request, urlopen


ACCESS_DATE = "2026-05-16"
BASE_DOC_URL = "https://documents.un.org/api/symbol/access"
USER_AGENT = "red_trade_research_script/1.0 (academic reproducibility)"

CASES_PATH = Path("data/processed/unvotes/brazil_china_un_vote_cases_2004_2012.csv")
RAW_RES_DIR = Path("data/raw/un_docs/resolutions")
RAW_MEETING_DIR = Path("data/raw/un_docs/meeting_records")
TEXT_DIR = Path("data/processed/un_docs/text")
OUT_DIR = Path("data/processed/unvotes")
REPORT_DIR = Path("quality_reports/un_vote_cases")

SPEECH_EVIDENCE_OUT = OUT_DIR / "brazil_china_un_vote_speech_evidence_2004_2012.csv"
MEETING_RECORDS_OUT = OUT_DIR / "brazil_china_un_vote_meeting_records_2004_2012.csv"
SOURCE_LOG_OUT = REPORT_DIR / "UN_SPEECH_COLLECTION_LOG.md"


def ensure_dirs() -> None:
    for directory in (RAW_RES_DIR, RAW_MEETING_DIR, TEXT_DIR, OUT_DIR, REPORT_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def symbol_to_filename(symbol: str, suffix: str) -> str:
    safe = symbol.replace("/", "_").replace(".", "_").replace(" ", "_")
    return f"{safe}{suffix}"


def documents_url(symbol: str) -> str:
    return f"{BASE_DOC_URL}?l=en&s={quote(symbol, safe='')}&t=pdf"


def download_pdf(symbol: str, output_dir: Path) -> Path:
    out_path = output_dir / symbol_to_filename(symbol, ".pdf")
    if out_path.exists() and out_path.stat().st_size > 1024:
        return out_path

    request = Request(documents_url(symbol), headers={"User-Agent": USER_AGENT})
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urlopen(request, timeout=45) as response:
                payload = response.read()
            if len(payload) <= 1024 or not payload.startswith(b"%PDF"):
                raise RuntimeError(f"Download for {symbol} did not return a valid PDF")
            out_path.write_bytes(payload)
            return out_path
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(2**attempt)
    raise RuntimeError(f"Could not download {symbol}: {last_error}")


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


def clean_space(text: str) -> str:
    text = text.replace("\u00a0", " ")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def extract_plenary_meeting(resolution_text: str) -> str | None:
    match = re.search(r"(\d+)(?:st|nd|rd|th)\s+plenary meeting", resolution_text, re.I)
    if match:
        return match.group(1)
    return None


def resolution_session(doc_symbol: str) -> str:
    match = re.match(r"A/RES/(\d+)/", doc_symbol)
    if not match:
        raise ValueError(f"Unexpected resolution symbol: {doc_symbol}")
    return match.group(1)


def resolution_number(doc_symbol: str) -> str:
    return doc_symbol.replace("A/RES/", "")


def find_resolution_window(text: str, doc_symbol: str, title_hint: str, width: int = 9000) -> tuple[int, int, str]:
    number = re.escape(resolution_number(doc_symbol))
    patterns = [
        rf"resolution\s+{number}",
        rf"\({doc_symbol.replace('/', r'/')}\)",
        re.escape(title_hint[:60]) if title_hint else "",
    ]
    positions = []
    for pattern in patterns:
        if not pattern:
            continue
        match = re.search(pattern, text, re.I)
        if match:
            positions.append(match.start())
    center = min(positions) if positions else 0
    start = max(0, center - width // 2)
    end = min(len(text), center + width)
    return start, end, text[start:end]


def theme_keywords(theme: str, descr: str) -> list[str]:
    lower_theme = f"{theme} {descr}".lower()
    keyword_map = [
        ("death penalty", ["death penalty", "moratorium"]),
        ("dprk", ["democratic people's republic of korea", "democratic people’s republic of korea", "dprk"]),
        ("iran", ["islamic republic of iran", "iran"]),
        ("nuclear danger", ["nuclear danger"]),
        ("icj", ["international court of justice", "nuclear weapons"]),
        ("globalization", ["globalization", "globalisation"]),
        ("human rights council", ["human rights council"]),
    ]
    keywords: list[str] = []
    for trigger, values in keyword_map:
        if trigger in lower_theme:
            keywords.extend(values)
    if not keywords:
        keywords.append(theme.lower())
    return keywords


SPEAKER_START = re.compile(
    r"(?m)^\s*(Mr\.|Ms\.|Mrs\.|Miss|Madam|Sir)\s+[^:\n]{0,140}\((Brazil|China)\)[^:\n]*:",
    re.I,
)

NEXT_SPEAKER = re.compile(
    r"(?m)^\s*(Mr\.|Ms\.|Mrs\.|Miss|Madam|Sir|The President|The Acting President)\b[^:\n]{0,180}:",
    re.I,
)


def iter_country_speeches(text: str) -> Iterable[dict[str, str | int]]:
    matches = list(SPEAKER_START.finditer(text))
    for idx, match in enumerate(matches):
        country = match.group(2)
        start = match.start()
        next_match = NEXT_SPEAKER.search(text, match.end())
        end = next_match.start() if next_match else len(text)
        # If the next speaker is the same match detected by NEXT_SPEAKER, use the
        # next country-specific speaker as a fallback boundary.
        if end <= match.end() and idx + 1 < len(matches):
            end = matches[idx + 1].start()
        speech = clean_space(text[start:end])
        yield {
            "country": country,
            "start": start,
            "end": end,
            "speech": speech,
        }


def short_excerpt(text: str, limit: int = 900) -> str:
    cleaned = clean_space(text)
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1].rstrip() + "…"


def read_cases() -> list[dict[str, str]]:
    with CASES_PATH.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    ensure_dirs()
    cases = read_cases()
    if not cases:
        raise RuntimeError(f"No rows found in {CASES_PATH}")

    meeting_cache: dict[str, dict[str, str]] = {}
    evidence_rows: list[dict[str, str]] = []
    meeting_rows: list[dict[str, str]] = []

    for row in cases:
        doc_symbol = row["doc_symbol"]
        resolution_pdf = download_pdf(doc_symbol, RAW_RES_DIR)
        resolution_text = pdf_to_text(resolution_pdf)
        meeting_no = extract_plenary_meeting(resolution_text)
        session = resolution_session(doc_symbol)
        meeting_symbol = f"A/{session}/PV.{meeting_no}" if meeting_no else ""

        meeting_text = ""
        meeting_pdf_path = ""
        meeting_url = ""
        window_start = 0
        window_end = 0
        vote_context = ""
        download_status = "not attempted"

        if meeting_symbol:
            try:
                meeting_pdf = download_pdf(meeting_symbol, RAW_MEETING_DIR)
                meeting_text = pdf_to_text(meeting_pdf)
                meeting_pdf_path = str(meeting_pdf)
                meeting_url = documents_url(meeting_symbol)
                window_start, window_end, vote_context = find_resolution_window(
                    meeting_text,
                    doc_symbol=doc_symbol,
                    title_hint=row.get("descr", ""),
                )
                download_status = "downloaded"
            except Exception as exc:  # noqa: BLE001
                download_status = f"failed: {exc}"

        meeting_key = meeting_symbol or f"missing_{doc_symbol}"
        if meeting_key not in meeting_cache:
            meeting_cache[meeting_key] = {
                "meeting_symbol": meeting_symbol,
                "meeting_pdf_path": meeting_pdf_path,
                "meeting_url": meeting_url,
                "download_status": download_status,
            }

        country_speeches = list(iter_country_speeches(meeting_text)) if meeting_text else []

        for country in ("Brazil", "China"):
            near_speeches = [
                speech for speech in country_speeches
                if speech["country"].lower() == country.lower()
                and int(speech["start"]) >= window_start
                and int(speech["start"]) <= window_end
            ]
            any_speeches = [
                speech for speech in country_speeches
                if speech["country"].lower() == country.lower()
            ]
            number = resolution_number(doc_symbol)
            keywords = theme_keywords(row.get("theme", ""), row.get("descr", ""))
            relevant_speeches = []
            relevance_rule = ""
            for speech in any_speeches:
                speech_text = str(speech["speech"]).lower()
                if number.lower() in speech_text:
                    relevant_speeches.append(speech)
                    relevance_rule = "mentions resolution number"
                    break
                if any(keyword.lower() in speech_text for keyword in keywords):
                    relevant_speeches.append(speech)
                    relevance_rule = "mentions selected theme"
                    break
            if not relevant_speeches and near_speeches:
                relevant_speeches = near_speeches
                relevance_rule = "speaker turn inside resolution window"

            selected = relevant_speeches[0] if relevant_speeches else None
            evidence_rows.append(
                {
                    "case_id": row["case_id"],
                    "theme": row["theme"],
                    "doc_symbol": doc_symbol,
                    "year": row["year"],
                    "case_type": row["case_type"],
                    "country": country,
                    "vote": row["vote_brazil"] if country == "Brazil" else row["vote_china"],
                    "convergence": row["convergence"],
                    "meeting_symbol": meeting_symbol,
                    "meeting_url": meeting_url,
                    "speech_found_in_vote_window": "TRUE" if near_speeches else "FALSE",
                    "speech_found_in_meeting": "TRUE" if any_speeches else "FALSE",
                    "speech_found_for_resolution": "TRUE" if relevant_speeches else "FALSE",
                    "relevance_rule": relevance_rule,
                    "speaker_excerpt": short_excerpt(str(selected["speech"])) if selected else "",
                    "vote_context_excerpt": short_excerpt(vote_context),
                    "source_note": (
                        "Official UN meeting record; speeches are extracted from the English PV record. "
                        "A FALSE value means no Brazil/China speaker turn was detected in the selected vote window."
                    ),
                    "date_accessed": ACCESS_DATE,
                }
            )

    for meeting_symbol, meta in sorted(meeting_cache.items()):
        meeting_rows.append(meta)

    write_csv(
        SPEECH_EVIDENCE_OUT,
        evidence_rows,
        [
            "case_id",
            "theme",
            "doc_symbol",
            "year",
            "case_type",
            "country",
            "vote",
            "convergence",
            "meeting_symbol",
            "meeting_url",
            "speech_found_in_vote_window",
            "speech_found_in_meeting",
            "speech_found_for_resolution",
            "relevance_rule",
            "speaker_excerpt",
            "vote_context_excerpt",
            "source_note",
            "date_accessed",
        ],
    )
    write_csv(
        MEETING_RECORDS_OUT,
        meeting_rows,
        ["meeting_symbol", "meeting_pdf_path", "meeting_url", "download_status"],
    )

    SOURCE_LOG_OUT.write_text(
        "\n".join(
            [
                "# Log de coleta: discursos e atas de votação ONU",
                "",
                f"- Data de acesso: {ACCESS_DATE}",
                "- Fonte: Official Documents of the United Nations (`documents.un.org`).",
                f"- Resoluções brutas: `{RAW_RES_DIR}`.",
                f"- Atas brutas de plenária: `{RAW_MEETING_DIR}`.",
                f"- Textos extraídos: `{TEXT_DIR}`.",
                f"- Evidência processada: `{SPEECH_EVIDENCE_OUT}`.",
                f"- Mapa de atas: `{MEETING_RECORDS_OUT}`.",
                "",
                "Validações:",
                "- Cada resolução foi baixada a partir do símbolo oficial A/RES.",
                "- O número da plenária foi extraído do PDF da resolução.",
                "- A ata foi baixada pelo símbolo A/session/PV.meeting.",
                "- Falas de Brasil/China foram buscadas por turnos de orador no texto da ata.",
                "- `speech_found_in_vote_window` distingue falas próximas ao voto de falas em outra parte da mesma reunião.",
            ]
        ),
        encoding="utf-8",
    )

    print(f"Saved speech evidence: {SPEECH_EVIDENCE_OUT}")
    print(f"Saved meeting records: {MEETING_RECORDS_OUT}")
    print(f"Saved collection log: {SOURCE_LOG_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
