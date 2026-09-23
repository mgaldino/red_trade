# Chile public-cue 2007–2008 data dictionary

The source-evidence CSV keeps the 25 legacy fields in their original order and
adds `metric_in_source` and `search_window`, as in the 48-country extension.
Each row is one candidate publisher document, including excluded documents.
`notes` starts with `DO_NOT_COUNT` when the document fails countability.
The country-code CSV keeps the 14 legacy fields and adds
`search_windows_tried` and `n_queries_logged`.

`entry_year=2007` is the goods-only ITPD-E first-entry year from the inventory,
not a year inferred from the press. `salience_code=high` means two independent
strong/moderate sources in the 2007–2008 publication window. A repeated item from
the same publisher family does not establish independence. The search log counts
executed web-discovery queries; GDELT was unavailable for these years.

The DIRECON report's `publication_date=2007-05` is month precision, as printed
on its cover; no publication day was invented. The BCN publisher page could
not be fetched automatically after its robots check failed. The user supplied
a complete Safari PDF print; that PDF is copied byte-for-byte to `data/raw/`,
with its provenance recorded in the raw manifest. Its source date (2007) is
distinct from its capture date (2026).
