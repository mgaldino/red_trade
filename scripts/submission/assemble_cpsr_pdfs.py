#!/usr/bin/env python3
"""Assemble final CPSR PDFs from deterministic render intermediates."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from pypdf import PdfReader, PdfWriter


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = ROOT / "submission" / "cpsr" / "cpsr_submission_config.json"
DEFAULT_RAW = ROOT / "output" / "submission" / "cpsr" / "raw"
DEFAULT_FINAL = ROOT / "output" / "submission" / "cpsr" / "final"

FIXED_PDF_DATE = "D:20260922000000Z"


def normalize(value: str) -> str:
    value = value.translate(
        str.maketrans(
            {
                "\x15": "-",
                "\x16": "-",
                "\x1b": "ff",
                "\x1c": "fi",
                "\x1d": "fl",
                "\x1e": "ffi",
                "\x1f": "ffl",
            }
        )
    )
    value = value.replace("–", "-").replace("—", "-")
    return re.sub(r"\s+", " ", value).strip()


def page_has_heading(text: str, heading: str) -> bool:
    wanted = normalize(heading)
    # Normalize before splitlines: Python treats form-feed/file-separator codes
    # used for PDF font ligatures as line boundaries.
    normalized_text = normalize(text)
    lines = [normalize(line) for line in normalized_text.splitlines() if normalize(line)]
    for line in lines[:18]:
        if line == wanted:
            return True
        if re.fullmatch(rf"(?:[A-Z0-9.]+\s+)?{re.escape(wanted)}", line):
            return True
    return wanted in normalized_text[:2000]


def section_starts(reader: PdfReader, headings: list[str]) -> dict[str, int]:
    starts: dict[str, int] = {}
    cursor = 0
    for heading in headings:
        found = None
        for index in range(cursor, len(reader.pages)):
            text = reader.pages[index].extract_text() or ""
            if page_has_heading(text, heading):
                found = index
                break
        if found is None:
            raise RuntimeError(f"Could not locate appendix heading in PDF: {heading}")
        starts[heading] = found
        cursor = found + 1
    return starts


def add_metadata(writer: PdfWriter, title: str, anonymous: bool) -> None:
    writer.add_metadata(
        {
            "/Title": title,
            "/Author": "" if anonymous else "Manoel Galdino",
            "/Subject": "Submission materials for Chinese Political Science Review",
            "/Creator": "Deterministic CPSR submission build",
            "/Producer": "pypdf",
            "/CreationDate": FIXED_PDF_DATE,
            "/ModDate": FIXED_PDF_DATE,
        }
    )


def write_pdf(
    output: Path,
    title: str,
    sources: list[tuple[Path, list[int] | None]],
    anonymous: bool,
) -> None:
    writer = PdfWriter()
    for path, indices in sources:
        reader = PdfReader(path)
        chosen = range(len(reader.pages)) if indices is None else indices
        for index in chosen:
            writer.add_page(reader.pages[index])
    add_metadata(writer, title, anonymous)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as handle:
        writer.write(handle)


def ranges_for_selected_sections(
    starts: dict[str, int], headings: list[str], selected: list[str], page_count: int
) -> list[int]:
    pages: list[int] = []
    for index, heading in enumerate(headings):
        start = starts[heading]
        end = starts[headings[index + 1]] if index + 1 < len(headings) else page_count
        if heading in selected:
            pages.extend(range(start, end))
    return pages


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW)
    parser.add_argument("--final-dir", type=Path, default=DEFAULT_FINAL)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    raw = args.raw_dir
    final = args.final_dir

    main_pdf = raw / "cpsr_manuscript_anonymous.pdf"
    inline_pdf = raw / "cpsr_full_inline_anonymous.pdf"
    supplement_pdf = raw / "cpsr_full_supplement_anonymous.pdf"
    required = [
        main_pdf,
        inline_pdf,
        supplement_pdf,
        raw / "cpsr_title_page.pdf",
        raw / "cpsr_cover_letter.pdf",
        raw / "cpsr_appendix_full_cover.pdf",
        raw / "cpsr_appendix_short_cover.pdf",
        raw / "cpsr_online_resource_anonymous_cover.pdf",
        raw / "cpsr_online_supplement_public_cover.pdf",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing render intermediates:\n" + "\n".join(missing))

    headings = config["appendix_sections"]
    inline_reader = PdfReader(inline_pdf)
    supplement_reader = PdfReader(supplement_pdf)
    inline_starts = section_starts(inline_reader, headings)
    supplement_starts = section_starts(supplement_reader, headings)

    full_inline_pages = list(range(inline_starts[headings[0]], len(inline_reader.pages)))
    full_supplement_pages = list(
        range(supplement_starts[headings[0]], len(supplement_reader.pages))
    )
    short_pages = ranges_for_selected_sections(
        inline_starts,
        headings,
        config["short_appendix_sections"],
        len(inline_reader.pages),
    )

    write_pdf(
        final / "CPSR_Manuscript_Anonymous.pdf",
        config["title"],
        [(main_pdf, None)],
        anonymous=True,
    )
    write_pdf(
        final / "CPSR_Manuscript_with_Full_Appendix_Anonymous.pdf",
        config["title"] + " - Manuscript with Full Appendix",
        [(inline_pdf, None)],
        anonymous=True,
    )
    write_pdf(
        final / "CPSR_Appendix_Full_Anonymous.pdf",
        "Supporting Appendix - Full Version",
        [
            (raw / "cpsr_appendix_full_cover.pdf", None),
            (inline_pdf, full_inline_pages),
        ],
        anonymous=True,
    )
    write_pdf(
        final / "CPSR_Appendix_Short_Anonymous.pdf",
        "Supporting Appendix - Condensed Version",
        [
            (raw / "cpsr_appendix_short_cover.pdf", None),
            (inline_pdf, short_pages),
        ],
        anonymous=True,
    )
    write_pdf(
        final / "CPSR_Online_Resource_1_Anonymous.pdf",
        "Online Resource 1 - Full Supplementary Information",
        [
            (raw / "cpsr_online_resource_anonymous_cover.pdf", None),
            (supplement_pdf, full_supplement_pages),
        ],
        anonymous=True,
    )
    write_pdf(
        final / "CPSR_Online_Supplement_Public.pdf",
        "Online Supplement - Full Supplementary Information",
        [
            (raw / "cpsr_online_supplement_public_cover.pdf", None),
            (supplement_pdf, full_supplement_pages),
        ],
        anonymous=False,
    )
    write_pdf(
        final / "CPSR_Title_Page.pdf",
        "Title Page",
        [(raw / "cpsr_title_page.pdf", None)],
        anonymous=False,
    )
    write_pdf(
        final / "CPSR_Cover_Letter.pdf",
        "Cover Letter to Chinese Political Science Review",
        [(raw / "cpsr_cover_letter.pdf", None)],
        anonymous=False,
    )

    page_map = {
        "inline_section_starts_one_based": {
            heading: page + 1 for heading, page in inline_starts.items()
        },
        "supplement_section_starts_one_based": {
            heading: page + 1 for heading, page in supplement_starts.items()
        },
        "short_appendix_source_pages_one_based": [page + 1 for page in short_pages],
    }
    (final / "page_map.json").write_text(
        json.dumps(page_map, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
