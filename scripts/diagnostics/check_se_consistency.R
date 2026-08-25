#!/usr/bin/env Rscript
# Every place the preferred placebo standard error is reported must carry the
# same number. Four independent artefacts hold a copy of it: the target itself,
# the no-covariate diagnostic summary, the Table 5 specification file, and the
# UNGA-DM comparison table. They are produced by different scripts at different
# times, so a partial rebuild can leave them disagreeing while every individual
# file still looks reasonable. This asserts they agree to 1e-10.
#
# Extracted from run_rebuild_batch.sh and run_reproducibility_rebuild.sh, which
# each carried a near-identical inline copy inside single quotes. One copy in
# one file cannot drift from the other.

se_target <- as.numeric(targets::tar_read_raw(
  "se_synth_no_time_varying_covariates", store = "_targets"))[1]

main_summary <- readr::read_csv(
  "data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/main_summary.csv",
  show_col_types = FALSE)
table5 <- readr::read_csv(
  paste0("data/processed/diagnostics/brazil_sdid_commodity_no_covariates/",
         "table_5_sdid_specification_results.csv"),
  show_col_types = FALSE)
ungadm <- readr::read_csv(
  paste0("data/processed/diagnostics/ungadm_outcome_robustness/estimation/",
         "sdid_comparison_table.csv"),
  show_col_types = FALSE)

se_summary <- main_summary$se_placebo[1]
se_table5 <- table5$se_placebo[table5$specification == "no_covariates"][1]
se_ungadm <- ungadm$se_placebo[grepl("^BSV", ungadm$outcome_source)][1]

cat(sprintf(
  "target=%.8f  main_summary=%.8f  table5=%.8f  ungadm_bsv=%.8f\n",
  se_target, se_summary, se_table5, se_ungadm))

stopifnot(
  isTRUE(all.equal(se_target, se_summary, tolerance = 1e-10)),
  isTRUE(all.equal(se_target, se_table5, tolerance = 1e-10)),
  isTRUE(all.equal(se_target, se_ungadm, tolerance = 1e-10)),
  "smoke_test" %in% names(table5),
  !any(table5$smoke_test %in% TRUE)
)
cat("SE consistency holds across all four sources.\n")
