# Collection Log: Mechanism Evidence China 2009-2011

Date of collection: 2026-05-19

## Raw Sources Collected

- MRE/FUNAG Resenha 104, 1º semestre de 2009: PDF and `pdftotext -layout` extraction.
- MRE/FUNAG Resenha 106, 1º semestre de 2010: PDF and `pdftotext -layout` extraction.
- MRE/FUNAG Resenha 108, 1º semestre de 2011: PDF and `pdftotext -layout` extraction.
- MRE/FUNAG Resenha 109, 2º semestre de 2011: PDF and `pdftotext -layout` extraction.
- Agência Câmara HTML page for the 7 Oct. 2011 story on the Brazil-China civil/commercial judicial-assistance agreement.
- CGU/Fala.BR filtered public text zips, 2015-2026, used for source discovery and LAI mapping.

## Processing Steps

1. Searched the local repo for UNGA/AGNU/ONU/China/rank-language files before external collection.
2. Downloaded official PDFs/HTML and preserved them unchanged under `data/raw/mechanism_evidence_china_2009_2011/`.
3. Extracted Resenha text with `pdftotext -layout` for quote verification.
4. Downloaded Fala.BR filtered text zips and scanned MRE/Relações Exteriores rows for China-related and rank/status terms.
5. Classified candidate excerpts as `Forte` or `Média`; no weak or irrelevant excerpt was retained in the positive evidence table.
6. Ran a separate verifier over the preserved local sources; all retained rows are marked `verified`.
7. Wrote `evidence_table.csv`, `SOURCES.yaml`, `DATA_DICTIONARY.md`, `raw_checksums.csv`, and `audit_log.md`.

## Limitations

Fala.BR public filtered text starts in 2015 for these text/anexo zips and did not expose direct 2009-2011 telegram excerpts with rank/status mechanism language. It does, however, identify LAI routes and document families for future follow-up requests.
