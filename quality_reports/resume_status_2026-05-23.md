# Status after resuming the May 2026 targets/paper update

Date/time: 2026-05-23, America/Sao_Paulo.

## What was resumed

The work resumed from `quality_reports/targets_resume_note_2026-05-21.md`.
The first command run was:

```r
targets::tar_make(callr_function = NULL)
```

The pipeline skipped all targets:

- 177 targets skipped;
- no target recomputed;
- `tar_validate()` returned `NULL`.

The previously expensive target `china_demand_sdid_diagnostics_table` remains
available in `_targets` and was read successfully.

## Current China-demand-shock SDiD diagnostics

| Specification | ATT | Placebo SE | p-value | Interpretation |
|---|---:|---:|---:|---|
| Main SDiD | -0.264 | 0.145 | 0.069 | Baseline estimate remains negative. |
| Smooth China share | -0.247 | 3.370 | 0.942 | Point estimate remains negative, but placebo inference is imprecise. |
| Destination concentration | -0.255 | 0.140 | 0.070 | Similar to baseline. |
| Commodity/GFC exposure | -0.306 | 0.148 | 0.038 | Robust to predetermined commodity exposure and 2008-2009 interactions. |
| Full stress test | -0.281 | 72,439 | 1.000 | Point estimate remains negative, but placebo inference is numerically unstable and not substantively informative. |

The paper now treats the full stress-test row as a conservative support
diagnostic, not as a preferred inferential specification.

## Paper rendering

`paper_v4.Rmd` was rendered successfully with:

```bash
bash scripts/render_paper_v4.sh
```

Output:

- `paper_v4.pdf`
- 44 pages;
- creation time: 2026-05-23 15:50:57 -03.

Validation checks:

- PDF text includes Table 3 with the China #2 threshold placebo.
- PDF text includes Table 4, "Brazil SDiD diagnostics for the China-demand-shock critique."
- The full stress-test row is rendered as `unstable` / `not informative`.
- No `spell` or `treatment spell` language was found in `paper_v4.Rmd` or extracted PDF text.

## Remaining technical caveat

`targets::tar_outdated()` still reports nine AGNU/selective-alignment targets:

1. `selective_china_alignment_vote_level_models`
2. `selective_china_alignment_ddd_hr_nonhr_models`
3. `goal6_human_rights_vs_non_human_rights`
4. `selective_china_alignment_unga_targets_bundle`
5. `brazil_china_unvotes_similarity_by_year_2005_2012`
6. `plot_brazil_china_unvotes_similarity_by_issue_year_2005_2012`
7. `brazil_china_unvotes_resolution_2005_2012`
8. `brazil_china_unvotes_similarity_by_issue_year_2005_2012`
9. `selective_china_alignment_country_placebo_summary`

However, `targets::tar_make(callr_function = NULL)` skips the pipeline and
the objects used by the paper are readable. This appears to be a
metadata/outdated-diagnostic inconsistency rather than a blocker for rendering.
It should be investigated separately before treating `tar_outdated()` as a
clean reproducibility certificate.
