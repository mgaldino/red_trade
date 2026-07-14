# Data Dictionary: China Mechanism Evidence, 2009-2011

All files use UTF-8 unless the preserved raw source is an original public download with its own encoding. The main analytical table is `evidence_table.csv`.

## `evidence_table.csv`

- `id`: Stable evidence identifier.
- `date`: Document or event date in ISO format.
- `year`: Calendar year of `date`.
- `source_type`: Type of primary source used.
- `institution`: Institution responsible for the document or official publication.
- `speaker_author`: Speaker, author, or attributed actor.
- `title`: Title of the document, speech, interview, note, or news item.
- `url`: Primary-source URL used for access.
- `local_raw_path`: Repo-relative path to the preserved raw source.
- `accessed_date`: Date on which the online source was accessed.
- `exact_quote`: Short verbatim excerpt containing the rank/status language.
- `english_translation_if_needed`: Translation for non-English excerpts, preserving the mechanism-relevant meaning.
- `context_summary`: Paraphrase of the surrounding context.
- `mechanism_relevance`: Interpretation of how the excerpt relates to the hypothesized status-cue mechanism.
- `strength_rating`: `Forte`, `Média`, `Fraca`, or `Irrelevante`; no `Fraca` or `Irrelevante` rows were retained as positive evidence.
- `factcheck_status`: `verified`, `partially_verified`, or `rejected`. Only verified rows are included here.
- `notes`: Verification notes, caveats, and use guidance.

## Supporting Files

- `raw_checksums.csv`: SHA-256 checksums and sizes for every preserved raw file under `data/raw/mechanism_evidence_china_2009_2011/`.
- `falabr_scan_counts.csv`: Annual scan counts for the Fala.BR filtered text zips.
- `falabr_mre_china_hits.csv`: Fala.BR rows from MRE/Relações Exteriores containing China-related terms.
- `falabr_mre_china_rank_hits.csv`: Fala.BR MRE-China rows also containing rank/status terms.
- `falabr_zip_checksums.csv`: Checksums generated during the temporary Fala.BR scan before preservation in the repo.
- `SOURCES.yaml`: Source manifest with URLs, local paths, dates of access, and checksums.

## Raw Sources

- `data/raw/mechanism_evidence_china_2009_2011/mre_resenhas/`: MRE/FUNAG Resenha PDFs and `pdftotext -layout` extractions.
- `data/raw/mechanism_evidence_china_2009_2011/camara/`: Preserved Agência Câmara HTML.
- `data/raw/mechanism_evidence_china_2009_2011/falabr/`: Preserved CGU/Fala.BR filtered text zips, 2015-2026, used only for source discovery.
