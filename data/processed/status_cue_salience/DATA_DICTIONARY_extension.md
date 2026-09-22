# Status cue extension data dictionary

The two extension CSVs retain the exact legacy column order and meanings, with appended columns only. Each row in the evidence CSV represents a candidate publisher document, including DO_NOT_COUNT failures. Only rows whose raw, date, claim, scope, and window pass the collector's checks enter country counts. A newspaper quoting official data is one newspaper source, not an additional official source.

| File | Extra column | Meaning | Values |
|---|---|---|---|
| status_cue_source_evidence_extension.csv | metric_in_source | Denominator the source explicitly describes; a generic partner label is normally `two_way_trade` only when the text makes both flows clear, otherwise `unspecified`. | goods_exports, goods_services_exports, two_way_trade, unspecified |
| status_cue_source_evidence_extension.csv | search_window | Publication window associated with this candidate. | `YYYY-YYYY`; `outside` |
| status_cue_country_codes_extension.csv | search_windows_tried | Entry and following-year windows with actually executed web discovery queries. | semicolon-separated windows |
| status_cue_country_codes_extension.csv | n_queries_logged | Number of executed web searches and attempted GDELT DOC requests, including rate-limited calls. | nonnegative integer |

The common legacy fields are defined in `DATA_DICTIONARY.md`. `negative_case_candidate` can be `yes` only after a separate documented wide search verifies contemporaneous national news and official coverage in English and the local language without a rank cue. The present collector never infers `low` from zero search hits. Search queries and result URLs are under `data/raw/status_cue_salience/extension_2026/web_discovery_queries*.json`; each collection run has a JSON manifest with SHA-256 for publisher and GDELT raws. Rebuild with `python3 scripts/diagnostics/collect_status_cue_salience_extension.py --build --manifest PATH`.
