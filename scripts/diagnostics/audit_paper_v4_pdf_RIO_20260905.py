#!/usr/bin/env python3
"""Read-only PDF text/bounds audit and rendered contact sheets for the RIO revision."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

import pdfplumber
from PIL import Image, ImageDraw

pdf = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
pages_dir = out / "pages"
pages_dir.mkdir(exist_ok=True)
subprocess.run(["pdftoppm", "-r", "80", "-png", str(pdf), str(pages_dir / "page")], check=True)
page_records = []
text_pages = []
with pdfplumber.open(pdf) as document:
    for n, page in enumerate(document.pages, 1):
        text = page.extract_text() or ""
        words = page.extract_words()
        outside = [w for w in words if w["x0"] < -1 or w["x1"] > page.width + 1
                   or w["top"] < -1 or w["bottom"] > page.height + 1]
        page_records.append({"page": n, "width": page.width, "height": page.height,
                             "words": len(words), "outside_page": outside,
                             "unresolved_marker": "??" in text,
                             "replacement_glyph": "\ufffd" in text})
        text_pages.append(f"\n===== PDF PAGE {n} =====\n{text}\n")
(out / "pages.txt").write_text("".join(text_pages), encoding="utf-8")
pngs = sorted(pages_dir.glob("page-*.png"))
for start in range(0, len(pngs), 9):
    sheet = Image.new("RGB", (1080, 1482), "#dddddd")
    draw = ImageDraw.Draw(sheet)
    for pos, path in enumerate(pngs[start:start + 9]):
        im = Image.open(path).convert("RGB")
        im.thumbnail((348, 454))
        x, y = (pos % 3) * 360 + 6, (pos // 3) * 494 + 28
        sheet.paste(im, (x, y))
        draw.text((x, y - 20), f"Page {start + pos + 1}", fill="black")
    sheet.save(out / f"contact-{start // 9 + 1:02d}.png")
manifest = {"pdf": str(pdf), "sha256": hashlib.sha256(pdf.read_bytes()).hexdigest(),
            "n_pages": len(page_records), "pages": page_records,
            "scope": "Mechanical extraction and page bounds only; visual and substantive review remain separate."}
(out / "pdf_mechanical_audit.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps({"n_pages": len(page_records),
                  "outside_pages": [x["page"] for x in page_records if x["outside_page"]],
                  "marker_pages": [x["page"] for x in page_records if x["unresolved_marker"] or x["replacement_glyph"]],
                  "sha256": manifest["sha256"]}))
