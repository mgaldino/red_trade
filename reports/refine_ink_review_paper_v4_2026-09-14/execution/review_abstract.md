# Independent abstract-number review

## Executive disposition

Candidate reviewed: `/private/tmp/refine-review-20260914/paper_v4.Rmd`  
Candidate SHA-256: `82c811def270d266f8ef4541d6fc8afecb6adfe980cda6260d84439714bb340c`  
Frozen baseline: `reports/refine_ink_review_paper_v4_2026-09-14/execution/baseline/paper_v4.Rmd`  
Baseline SHA-256: `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`

Verdict: `NO_CONFIRMED_DEFECTS` for the requested numeric gate. The selected finding `REFINE-033` was real in the frozen baseline but is refuted as a current-candidate defect: the candidate now says “42% of the pre-treatment mean distance before 2009.” The mean-based calculation is correct. No unselected comment, conceptual claim, exposition issue, model, target, or pipeline question was reopened.

## Finding

| ID | Severity | Candidate status | Localized result |
|---|---:|---|---|
| `REFINE-033` | minor | `REFUTED` | Baseline `:20` said “median”; candidate `:20` says “pre-treatment mean.” Existing-data arithmetic gives 42.1739% using the mean and 43.9300% using the median. |

The proposed correction remains `safe`; no further edit is indicated by this gate.

## Numeric audit

| Value/claim in YAML abstract | Candidate body/conclusion projection | Original CSV/target evidence | Status |
|---|---|---|---|
| `2009` Brazil ranking shift and pre-2009 cutoff | Body `:147`, `:223`, `:328`, `:330`, and `:338`; conclusion `:1287` | `goal3_brazil_rank_volume_data`: rank 2 in 2008, rank 1 in 2009, first China rank 1 in 2009. The pre-treatment target slice is 1997–2008, `n=12`. | PASS |
| `42%` relative reduction | Body `:149` computes `perc_change`; body `:338` labels the denominator “pre-treatment mean” and uses the same inline percentage | `main_summary.csv`: ATT `-0.272771407583060`, pre-treatment mean `0.646777890583333`, stored percentage `-42.17389177249793`; independently, `abs(ATT)/mean = 42.173891772497932%`, which rounds to `42%` in the abstract and `42.2%` in the body. The median would give `43.930033997971528%`. | PASS |
| `2000–2022` cross-country date context | Body `:322` restricts treatment to years in or after 2000; the conclusion refers to the cross-country estimates without adding another date | Main current target: treated entry-year range `2000–2018`; main risk-set sample panel `1990–2022`. Thus 2000 is the entry lower bound and 2022 is the observed panel endpoint. | PASS |
| Manually typed conclusion value `0.273` | Candidate conclusion `:1287`; body `:336` renders `abs(estimate)` to three decimals | Existing main summary ATT `-0.272771407583060`; `round(abs(ATT), 3) = 0.273`. Candidate and baseline conclusion lines are byte-identical. | PASS |

The abstract's broad “leading trading partner” wording was treated as deliberate, as instructed; this review checks only its numeric/date content.

## Exact projections and hashes

The candidate abstract line 20 contains the corrected clause:

> Relative to the counterfactual, the estimated reduction in bilateral voting distance is equivalent to 42% of the pre-treatment mean distance before 2009.

The candidate body keeps the dynamic calculation at lines 149 and 338, and the conclusion keeps the manually typed `0.273` at line 1287. SHA-256 hashes below are of the exact individual line bytes, including the line ending:

| Projection | Candidate line/hash | Frozen baseline line/hash |
|---|---|---|
| YAML abstract | `:20` / `9accf3cbd103cffc29f82136030266d70f13900f6b01d4085a0962ea43a7ef2f` | `:20` / `35e3a8b4b5313bcb3d77cc12b7c3892c47ec7b0716aa3355fc57f90035b6eb77` |
| Body percentage expression | `:149` / `3eda74013d86b8ad41f35290f11754d6d6564ad2ceae61e81554e9eed0e3d44d` | `:149` / `3eda74013d86b8ad41f35290f11754d6d6564ad2ceae61e81554e9eed0e3d44d` |
| Body detail expression | `:338` / `a2347ab570ca4cff0346eaa8991c36b979c4c50b1241244df2d0249b17a29b52` | `:338` / `a2347ab570ca4cff0346eaa8991c36b979c4c50b1241244df2d0249b17a29b52` |
| Numeric conclusion | `:1287` / `8568ff0a6d63f22208b2425593e4953a412c79a51fd3576bbd9908075d25f5af` | `:1283` / `8568ff0a6d63f22208b2425593e4953a412c79a51fd3576bbd9908075d25f5af` |

## Reproducible checks and evidence

Commands were read-only. The final arithmetic/date assertion was:

```sh
Rscript --vanilla -e 'options(digits=17); targets::tar_config_set(store="_targets"); d <- targets::tar_read(synth_data); b <- d[d$iso3c == "BRA" & d$year < 2009, , drop=FALSE]; m <- utils::read.csv("data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/main_summary.csv"); rv <- targets::tar_read(goal3_brazil_rank_volume_data); bundle <- targets::tar_read(china_top_m2_goods_status_current_panel_bundle); sc <- bundle$sample_counts[bundle$sample_counts$min_duration_years == 5L & bundle$sample_counts$sample == "risk_set_restricted", , drop=FALSE]; u <- bundle$unit_summary[bundle$unit_summary$min_duration_years == 5L & bundle$unit_summary$sample == "risk_set_restricted" & bundle$unit_summary$ever_treated, , drop=FALSE]; mean_b <- mean(b$abs_distance_china); median_b <- median(b$abs_distance_china); att <- m$estimate[1]; stopifnot(nrow(b) == 12L, min(b$year) == 1997L, max(b$year) == 2008L, abs(mean_b - m$brazil_pre_treatment_mean[1]) < 1e-12, abs(abs(att)/mean_b*100 - abs(m$estimate_as_percent_of_pre_mean[1])) < 1e-12, min(rv$year[rv$china_rank == 1]) == 2009L, rv$china_rank[rv$year == 2008] == 2L, rv$china_rank[rv$year == 2009] == 1L, sc$panel_min == 1990L, sc$panel_max == 2022L, min(u$first_treat, na.rm=TRUE) == 2000L, round(abs(att), 3) == 0.273); cat("BRA_PRE_YEARS=1997-2008 n=12\n"); cat(sprintf("MEAN=%.15f MEDIAN=%.15f ATT=%.15f RATIO_MEAN=%.15f%% RATIO_MEDIAN=%.15f%%\n", mean_b, median_b, att, abs(att)/mean_b*100, abs(att)/median_b*100)); cat(sprintf("RANK_2008=%d RANK_2009=%d FIRST_CHINA_RANK1=%d\n", rv$china_rank[rv$year == 2008], rv$china_rank[rv$year == 2009], min(rv$year[rv$china_rank == 1]))); cat(sprintf("CROSS_MAIN_PANEL=%d-%d TREATED_ENTRY_RANGE=%d-%d\n", sc$panel_min, sc$panel_max, min(u$first_treat, na.rm=TRUE), max(u$first_treat, na.rm=TRUE))); cat("CHECKS=PASS\n")'
```

Relevant output:

```text
BRA_PRE_YEARS=1997-2008 n=12
MEAN=0.646777890583333 MEDIAN=0.620922368500000 ATT=-0.272771407583060 RATIO_MEAN=42.173891772497932% RATIO_MEDIAN=43.930033997971528%
RANK_2008=2 RANK_2009=1 FIRST_CHINA_RANK1=2009
CROSS_MAIN_PANEL=1990-2022 TREATED_ENTRY_RANGE=2000-2018
CHECKS=PASS
```

Source hashes used in the check:

```text
main_summary.csv  29afbe934bc650fe79f8214cfc8050646d404420a160c4d34b6386d87643f711
m2_goods_status_current_min_duration_sample_counts_2026-05-20.csv  fc06a07153721bf426b155230438db48d64726b888739c486cdd1338a98b59fd
_targets/meta/meta  e869bf119fa3d72f5a5ef659f8d7f589b9bd3da8dfdb3fb50bd5e5a6a504677d
```

At the final check, `reports/refine_ink_review_paper_v4_2026-09-14/execution/integration_final.txt` was present. Its item-33 statement that the 42% abstract value equals the rounded mean-based calculation agrees with the independent check above. No rendering, `targets` execution, reestimation, classification API, data edit, commit, push, signal, or configuration change was performed.

## Scope boundary and verdict

The review is bounded to the selected item 33 numeric correction, every number in the YAML abstract, relevant body/conclusion projections, and the manually typed `0.273` in the conclusion. The candidate is not hereby certified as scientifically correct in its entirety; other edits and non-numeric dimensions were not reviewed.

Final adjudication: `NO_CONFIRMED_DEFECTS`.
