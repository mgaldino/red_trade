# R Review: Goal 9 Target and Helper Changes

Date: 2026-05-18

Reviewer role: separate `review-r` agent. The reviewer did not edit files.

Files reviewed:

- `_targets.R`
- `scripts/functions.R`

Scope reviewed: Goal 9 additions only, including `goal3_brazil_rank_volume_*`, `goal6_*`, and appended `goal9_*` helper functions.

## Round 1

Grade: B-.

Syntax parse passed for `_targets.R` and `scripts/functions.R`; only locale startup warnings appeared.

### Blockers

1. Unsupported `US$ billions` conversion: the first version divided raw ITPD-E values by `1000` and labeled the result `US$ billions` without documenting the source unit.

2. Causal interpretation too strong for exploratory robustness rows: the first version labeled the main outcome as `primary causal` and generated a `supports_alignment_claim` field from sign alone, while most robustness rows had point estimates without SE or placebo inference.

### Nonblocking Issues

- Normal p-values from placebo SEs should be labeled as approximate or interpreted cautiously.
- The pre/post split at 2009 is substantively defensible but should be documented.
- Human-rights detection via string matching is acceptable with current labels but brittle to label recoding.
- `set.seed()` in a deterministic `synthdid_estimate()` call is unnecessary but harmless.
- `goal6_sdid_outcome_results` refits several SDiD models inside one target, increasing rebuild cost and reducing failure granularity.

## Implementer Response

The implementer made the following fixes:

- Added an explicit code comment documenting that the USITC ITPD-E variable guide defines `trade` as flows in millions of current US dollars; aggregate exports therefore inherit that unit, and division by `1000` reports current US$ billions.
- Replaced `evidence_tier` labels such as `primary causal` with `causal_status` labels that distinguish the Brazil reduced-form SDiD estimate from point-estimate-only diagnostics.
- Replaced `supports_alignment_claim` with `direction_consistent_with_convergence`.
- Added an `inference_status` column to the rank-versus-volume timing tests stating that p-values are normal approximations using placebo-based SEs and that the rows are timing falsifications, not equivalence tests.
- Parameterized the human-rights pre/post split with `treatment_year = 2009L`.

## Status

Round 1 blockers were addressed in code. A follow-up review is required before final commit if these targets remain part of the Goal 9 implementation.

## Round 2

Grade: A-.

The follow-up `review-r` agent found no blockers. It verified that:

- the ITPD-E conversion is now documented as millions of current US dollars converted to current US$ billions;
- secondary SDiD outcome rows are labeled as diagnostics or point-estimate robustness checks rather than causal evidence;
- `plot_fect_ife_gap_china_top_cov` is wired consistently to `fect_ife_china_top_cov` using the existing `plot_fect_gap()` helper;
- `_targets.R` and `scripts/functions.R` parse successfully;
- `targets::tar_make()` was not run.

The only nonblocking issue was that `direction_consistent_with_convergence` remained somewhat interpretive. The implementer renamed it to `direction_matches_expected_sign`.

Final verdict: ready for rendering and commit from the R-review perspective.
## Round 3 focused review

Reviewer role: separate R reviewer. The reviewer did not edit files.

Additional change reviewed: `goal9_human_rights_vs_non_human_rights()` now deduplicates by `rcid` before summarizing the human-rights versus non-human-rights diagnostic. A resolution is classified as human rights if any issue-family row for the resolution contains "Human rights". This prevents multi-issue resolutions from being counted more than once in the non-human-rights group.

Verdict: A. No blockers.

Reviewer assessment:

- Deduplicating by `rcid` before summarizing fixes the multi-issue-family overcount.
- Classifying a resolution as human rights when any issue-family row contains human rights is the appropriate conservative rule for this diagnostic.
- The rebuilt target returns HR 102/96, non-HR 292/258, and non-HR `delta_identical_vote_share` = 2.665 p.p., consistent with the Goal 6 report.
- Within `rcid`, `year`, `identical_vote`, and `similarity_score` are invariant, so using `dplyr::first()` after grouping is safe.
- The function remains deterministic and pipeline-compatible.

Final verdict: ready to commit.
