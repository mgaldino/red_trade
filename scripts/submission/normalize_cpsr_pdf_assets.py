#!/usr/bin/env python3
"""Normalize volatile metadata in R-generated PDF figure assets."""

from __future__ import annotations

import argparse
from pathlib import Path

from pypdf import PdfReader, PdfWriter


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RAW = ROOT / "output" / "submission" / "cpsr" / "raw"
FIXED_PDF_DATE = "D:20260922000000Z"


def normalize_pdf(path: Path) -> None:
    reader = PdfReader(path)
    writer = PdfWriter()
    for page in reader.pages:
        writer.add_page(page)
    writer.add_metadata(
        {
            "/Title": "",
            "/Author": "",
            "/Subject": "CPSR manuscript figure",
            "/Creator": "Deterministic CPSR submission build",
            "/Producer": "pypdf",
            "/CreationDate": FIXED_PDF_DATE,
            "/ModDate": FIXED_PDF_DATE,
        }
    )
    temporary = path.with_suffix(path.suffix + ".normalized")
    with temporary.open("wb") as handle:
        writer.write(handle)
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW)
    args = parser.parse_args()

    assets = sorted(args.raw_dir.glob("*_files/figure-latex/*.pdf"))
    if not assets:
        raise FileNotFoundError(f"No generated PDF figure assets found in {args.raw_dir}")
    for path in assets:
        normalize_pdf(path)
    print(f"Normalized {len(assets)} generated PDF figure assets")


if __name__ == "__main__":
    main()
