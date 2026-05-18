# Goal 9 validation report

Date: 2026-05-18

## Versioning

- Pre-edit snapshot commit: `5caae22 chore: snapshot pre-goal9 inputs`.
- Pre-edit tag: `pre-goal9-paper-v4-20260518`.
- Active manuscript: `paper_v4.Rmd`.

## Target-backed evidence

Selected targets were built with `targets::tar_make(names = c(...))`; the full pipeline was not run.

Targets built for Goal 9:

- `goal3_brazil_rank_volume_data`
- `goal3_brazil_rank_volume_plot`
- `goal3_brazil_placebo_rank_volume_tests`
- `goal6_human_rights_vs_non_human_rights`
- `goal6_sdid_outcome_results`
- `plot_fect_ife_gap_china_top_cov`

The Goal 6 human-rights versus non-human-rights diagnostic was rebuilt after deduplicating by `rcid`. The target now matches the Goal 6 report: human-rights resolutions 102/96, non-human-rights resolutions 292/258, and non-human-rights identical-vote change 2.665 p.p. (`+2.7 p.p.` in the paper).

## Render

- Command: `rmarkdown::render('paper_v4.Rmd', output_format = 'bookdown::pdf_document2', clean = FALSE)`.
- Output: `paper_v4.pdf`.
- Result: success.
- PDF pages: 30.
- Remaining LaTeX warning: `!h` float specifier changed to `!ht`; no render failure.

## Cross-reference and presentation checks

PDF text search found no unresolved `??`, `@ref`, `fig:`, or `tab:` references.

The PDF contains Tables 1--3 in the intended main-text sections:

- Table 1: Brazil SDiD estimate and rank-versus-volume timing tests.
- Table 2: Brazil outcome robustness and issue-scope diagnostics.
- Table 3: Cross-country scope-probe estimate.

The Brazilian media figure renders before the cross-country section. The cross-country table renders inside the cross-country section.

## Required string checks

Final searches found no remaining hits for:

- `specially`
- `empirically document`
- `Firstly`
- `toe reflect`
- `Wolrd`
- `anonymous reviewer`
- raw `(#fig:` or `(#tab:` labels in `paper_v4.Rmd`
- `foreign-policy realignment`
- `foreign policy realignment`
- `wholesale`
- `direct evidence for H2`
- `confirms H2`
- `PanelMatch diagnostics are reported`

Remaining `top trade partner` usage is intentional and limited to public/contemporary framing. The empirical treatment remains largest/top export-destination status.

## Separate review

- Manuscript review report: `quality_reports/review_goal9_implementation_20260518.md`.
- R review report: `quality_reports/review_r_goal9_targets_20260518.md`.
- Visual/pedagogy gate report for the rank-versus-volume figure: `quality_reports/review_goal9_rank_volume_visual_pedagogy_20260518.md`.

Final manuscript reviewer verdict: no blockers.
