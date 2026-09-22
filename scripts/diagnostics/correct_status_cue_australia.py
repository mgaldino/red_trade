#!/usr/bin/env python3
"""Correct Australia's public-cue coding from preserved local evidence.

This focal correction is offline and idempotent. It does not call targets,
re-estimate models, download sources, or modify raw files. It synchronizes the
status-cue audit to the current M2 entry year (2009), imports the already
preserved AFR and DFAT evidence, and records broad-cue versus strict-M2 scope.
"""

from __future__ import annotations

import csv
import hashlib
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROCESSED = ROOT / "data" / "processed" / "status_cue_salience"
COUNTRY_CODES = PROCESSED / "status_cue_country_codes.csv"
SOURCE_EVIDENCE = PROCESSED / "status_cue_source_evidence.csv"
WINDOWS = PROCESSED / "status_cue_australia_windows.csv"

AFR_RAW = Path(
    "data/raw/ex_top1_salience/AUS/2009/australian_financial_review/"
    "aus_afr_china_trading_partner_2009.html"
)
DFAT_RAW = Path(
    "data/raw/ex_top1_salience/AUS/2010/"
    "australian_department_of_foreign_affairs_and_trade/"
    "aus_dfat_china_became_largest_export_market_2010.html"
)

EXPECTED_RAW_HASHES = {
    AFR_RAW: "7fc8a7aca3f57fd1fa294614722789cc2a70b87e26a2cb83d5135cefe0f99953",
    DFAT_RAW: "ec40fa256dbd2536a308832dd4f26c1bb02a682bfb51c9ad85b840eb83c948d5",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"Missing CSV header: {path}")
        return list(reader.fieldnames), list(reader)


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp, path)


def verify_raws() -> None:
    for relative_path, expected in EXPECTED_RAW_HASHES.items():
        absolute_path = ROOT / relative_path
        if not absolute_path.is_file():
            raise FileNotFoundError(absolute_path)
        observed = sha256(absolute_path)
        if observed != expected:
            raise ValueError(
                f"Raw checksum mismatch for {relative_path}: {observed} != {expected}"
            )


def update_country_codes() -> None:
    fieldnames, rows = read_csv(COUNTRY_CODES)
    australia = [row for row in rows if row["iso3c"] == "AUS"]
    if len(australia) != 1:
        raise ValueError(f"Expected one AUS country row, found {len(australia)}")

    row = australia[0]
    if (row["entry_year"], row["salience_code"]) not in {
        ("2010", "unknown"),
        ("2009", "high"),
    }:
        raise ValueError(
            "Unexpected pre-correction AUS state: "
            f"entry={row['entry_year']}, code={row['salience_code']}"
        )

    row.update(
        entry_year="2009",
        n_newspaper_sources_strong="1",
        n_official_sources_strong="1",
        n_total_strong_or_moderate="2",
        has_explicit_export_rank_label="true",
        has_explicit_generic_trade_partner_label="true",
        has_official_uptake="true",
        has_newspaper_uptake="true",
        salience_code="high",
        negative_case_candidate="no",
        coding_rationale=(
            "Current M2 2009-2010 window: two preserved national sources from "
            "independent publisher families use explicit top-rank language. AFR "
            "identifies China as Australia's largest aggregate trading partner; "
            "DFAT identifies China as Australia's largest export market in 2009."
        ),
        remaining_gaps=(
            "Broad public-cue evidence is high, but strict alignment to M2 goods-only "
            "is unresolved: AFR combines exports and imports of goods and services, "
            "and DFAT reports exports of goods and services."
        ),
    )
    write_csv(COUNTRY_CODES, fieldnames, rows)


def source_rows() -> list[dict[str, str]]:
    return [
        {
            "iso3c": "AUS",
            "country_name": "Australia",
            "entry_year": "2009",
            "evidence_year": "2009",
            "source_type": "business_news",
            "source_name": "Australian Financial Review",
            "source_country": "Australia",
            "language": "en",
            "title": "China hits the spot as trading partner",
            "publication_date": "2009-11-09",
            "url": "https://www.afr.com/markets/china-hits-the-spot-as-trading-partner-20091109-iwhtx",
            "archive_url": "",
            "raw_file": str(AFR_RAW),
            "query_used": (
                '"China hits the spot as trading partner" Australia '
                '"largest trading partner"'
            ),
            "accessed_at": "2026-05-23T22:04:48+00:00",
            "rank_label_original": "Australia's largest trading partner",
            "rank_label_english": "Australia's largest aggregate trading partner",
            "label_type": "generic_trade_partner",
            "explicit_rank_language": "true",
            "mentions_china_rank_change": "true",
            "mentions_displaced_incumbent": "true",
            "displaced_partner_named": "Japan",
            "excerpt_under_25_words": (
                "For the third consecutive year, China has taken its position as "
                "Australia's largest trading partner."
            ),
            "evidence_strength": "moderate",
            "notes": (
                "COUNT_FOR_BROAD_CUE_CURRENT_M2_WINDOW: national business-news "
                "coverage in 2009. Metric is aggregate exports and imports of goods "
                "and services, not strict M2 goods-only exports."
            ),
        },
        {
            "iso3c": "AUS",
            "country_name": "Australia",
            "entry_year": "2009",
            "evidence_year": "2009",
            "source_type": "government_news",
            "source_name": "Australian Department of Foreign Affairs and Trade",
            "source_country": "Australia",
            "language": "en",
            "title": "Australian trade volumes grow despite financial crisis",
            "publication_date": "2010-06-04",
            "url": (
                "https://www.dfat.gov.au/news/media/Pages/"
                "australian-trade-volumes-grow-despite-financial-crisis"
            ),
            "archive_url": (
                "https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/"
                "news/media/Pages/australian-trade-volumes-grow-despite-financial-crisis"
            ),
            "raw_file": str(DFAT_RAW),
            "query_used": (
                '"China became Australia\'s largest export market" '
                '"Japan was Australia\'s second largest export market"'
            ),
            "accessed_at": "2026-05-23T22:04:48+00:00",
            "rank_label_original": (
                "China became Australia's largest export market in 2009"
            ),
            "rank_label_english": (
                "China became Australia's largest export market in 2009"
            ),
            "label_type": "export_rank",
            "explicit_rank_language": "true",
            "mentions_china_rank_change": "true",
            "mentions_displaced_incumbent": "true",
            "displaced_partner_named": "Japan",
            "excerpt_under_25_words": (
                "China became Australia's largest export market in 2009."
            ),
            "evidence_strength": "strong",
            "notes": (
                "COUNT_FOR_BROAD_CUE_CURRENT_M2_WINDOW: national official release "
                "published in 2010 about annual 2009 trade. Export measure includes "
                "goods and services, so strict M2 goods-only alignment is unresolved."
            ),
        },
    ]


def update_source_evidence() -> None:
    fieldnames, rows = read_csv(SOURCE_EVIDENCE)
    required = set(source_rows()[0])
    if set(fieldnames) != required:
        raise ValueError("Unexpected status-cue source-evidence schema")

    new_raws = {str(AFR_RAW), str(DFAT_RAW)}
    rows = [row for row in rows if row["raw_file"] not in new_raws]

    australia_old = [row for row in rows if row["iso3c"] == "AUS"]
    if len(australia_old) != 2:
        raise ValueError(f"Expected two legacy AUS rows, found {len(australia_old)}")
    for row in australia_old:
        row["entry_year"] = "2009"
        if row["publication_date"] == "2011-06-29" and not row["notes"].startswith(
            "DO_NOT_COUNT: outside current 2009-2010 window."
        ):
            row["notes"] = (
                "DO_NOT_COUNT: outside current 2009-2010 window. " + row["notes"]
            )

    australia_block = sorted(
        source_rows() + australia_old,
        key=lambda row: (row["publication_date"], row["source_name"]),
    )

    first_aus = next(i for i, row in enumerate(rows) if row["iso3c"] == "AUS")
    without_aus = [row for row in rows if row["iso3c"] != "AUS"]
    before_count = sum(1 for row in rows[:first_aus] if row["iso3c"] != "AUS")
    rows = without_aus[:before_count] + australia_block + without_aus[before_count:]
    write_csv(SOURCE_EVIDENCE, fieldnames, rows)


def write_windows() -> None:
    fieldnames = [
        "iso3c",
        "window_definition",
        "entry_year",
        "window_start",
        "window_end",
        "n_counted_public_cue_sources",
        "n_publishers",
        "broad_cue_salience",
        "n_strict_m2_sources",
        "strict_m2_evidence",
        "source_ids",
    ]
    rows = [
        {
            "iso3c": "AUS",
            "window_definition": "legacy_absorbing_audit",
            "entry_year": "2010",
            "window_start": "2010",
            "window_end": "2011",
            "n_counted_public_cue_sources": "1",
            "n_publishers": "1",
            "broad_cue_salience": "medium",
            "n_strict_m2_sources": "0",
            "strict_m2_evidence": "unresolved",
            "source_ids": "aus_dfat_china_became_largest_export_market_2010",
        },
        {
            "iso3c": "AUS",
            "window_definition": "current_m2_min5",
            "entry_year": "2009",
            "window_start": "2009",
            "window_end": "2010",
            "n_counted_public_cue_sources": "2",
            "n_publishers": "2",
            "broad_cue_salience": "high",
            "n_strict_m2_sources": "0",
            "strict_m2_evidence": "unresolved",
            "source_ids": (
                "aus_afr_china_trading_partner_2009;"
                "aus_dfat_china_became_largest_export_market_2010"
            ),
        },
    ]
    write_csv(WINDOWS, fieldnames, rows)


def validate_outputs() -> None:
    _, countries = read_csv(COUNTRY_CODES)
    aus = [row for row in countries if row["iso3c"] == "AUS"]
    if len(aus) != 1 or aus[0]["entry_year"] != "2009" or aus[0]["salience_code"] != "high":
        raise AssertionError("Australia country code was not corrected")

    _, evidence = read_csv(SOURCE_EVIDENCE)
    countable = [
        row
        for row in evidence
        if row["iso3c"] == "AUS"
        and row["evidence_strength"] in {"strong", "moderate"}
        and row["explicit_rank_language"] == "true"
        and row["mentions_china_rank_change"] == "true"
        and not row["notes"].startswith("DO_NOT_COUNT")
    ]
    if len(countable) != 2 or len({row["source_name"] for row in countable}) != 2:
        raise AssertionError("Australia countable-source rule does not reproduce high")


def main() -> None:
    verify_raws()
    update_country_codes()
    update_source_evidence()
    write_windows()
    validate_outputs()
    print(f"Updated: {COUNTRY_CODES.relative_to(ROOT)}")
    print(f"Updated: {SOURCE_EVIDENCE.relative_to(ROOT)}")
    print(f"Wrote: {WINDOWS.relative_to(ROOT)}")
    print("Australia: entry=2009; broad public cue=high; strict M2 alignment=unresolved")


if __name__ == "__main__":
    main()
