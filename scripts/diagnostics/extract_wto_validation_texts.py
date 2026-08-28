#!/usr/bin/env python3
"""Extrai texto integral e primeiras páginas dos PDFs da validação OMC."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SAMPLE = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_manual_validation_sample_40.csv"
DEFAULT_DOWNLOAD_LOG = ROOT / "data" / "raw" / "wto_coauthorship" / "2026-08-28" / "validation_download_log_full.json"
OUT_DIR = ROOT / "data" / "processed" / "wto_coauthorship"
TEXT_DIR = OUT_DIR / "validation_text"


def run_pdftotext(pdf: Path, first_page_only: bool = False) -> str:
    command = ["pdftotext", "-layout"]
    if first_page_only:
        command.extend(["-f", "1", "-l", "1"])
    command.extend([str(pdf), "-"])
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return result.stdout.replace("\r\n", "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", type=Path, default=DEFAULT_SAMPLE)
    parser.add_argument("--download-log", type=Path, default=DEFAULT_DOWNLOAD_LOG)
    parser.add_argument("--output-stem", default="wto_validation")
    args = parser.parse_args()
    if not args.output_stem.replace("_", "").replace("-", "").isalnum():
        raise ValueError("--output-stem deve ser um nome simples")

    text_dir = TEXT_DIR / args.output_stem
    first_pages = OUT_DIR / f"{args.output_stem}_first_pages.txt"
    extraction_log = OUT_DIR / f"{args.output_stem}_extraction_log.csv"
    text_dir.mkdir(parents=True, exist_ok=True)
    sample = list(csv.DictReader(args.sample.open(encoding="utf-8")))
    download_log = json.loads(args.download_log.read_text(encoding="utf-8"))
    path_by_catalogue = {
        row["catalogue_id"]: ROOT / row["path"]
        for row in download_log["records"]
        if row["status"] != "error"
    }

    first_page_blocks = []
    log_rows = []
    for index, row in enumerate(sample, start=1):
        pdf = path_by_catalogue[row["catalogue_id"]]
        full_text = run_pdftotext(pdf)
        first_page = run_pdftotext(pdf, first_page_only=True)
        if len(full_text.strip()) < 20 or len(first_page.strip()) < 20:
            raise RuntimeError(f"Extração vazia ou quase vazia: {pdf}")

        text_path = text_dir / f"{row['catalogue_id']}.txt"
        text_path.write_text(full_text, encoding="utf-8")
        first_page_blocks.append(
            "\n".join(
                [
                    "=" * 88,
                    f"AMOSTRA {index:02d} | {row['validation_stratum']} | {row['symbol']}",
                    f"PDF: {pdf.relative_to(ROOT)}",
                    f"URL: {row['english_url']}",
                    "-" * 88,
                    first_page.rstrip(),
                ]
            )
        )
        log_rows.append(
            {
                "sample_index": index,
                "catalogue_id": row["catalogue_id"],
                "symbol": row["symbol"],
                "pdf_path": str(pdf.relative_to(ROOT)),
                "text_path": str(text_path.relative_to(ROOT)),
                "full_text_characters": len(full_text),
                "first_page_characters": len(first_page),
            }
        )

    first_pages.write_text("\n\n".join(first_page_blocks) + "\n", encoding="utf-8")
    with extraction_log.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(log_rows[0].keys()))
        writer.writeheader()
        writer.writerows(log_rows)
    print(f"Extraídos {len(log_rows)} PDFs; primeiras páginas: {first_pages.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
