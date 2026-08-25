# Targets the reproducibility rebuild must build: every target the manuscript
# reads (derived programmatically from the tar_read() calls in paper_v4.Rmd,
# so the list cannot drift from the paper) plus the targets the diagnostic
# scripts consume. Used by scripts/run_reproducibility_rebuild.sh.
rebuild_target_names <- function(rmd = "paper_v4.Rmd") {
  text <- readLines(rmd, warn = FALSE)
  hits <- regmatches(text, gregexpr("tar_read\\(([A-Za-z_0-9]+)\\)", text))
  from_paper <- unique(gsub("tar_read\\(|\\)", "", unlist(hits)))
  diagnostics_extras <- c(
    "synth_fit_no_time_varying_covariates",
    "se_synth_no_time_varying_covariates",
    "china_top_m2_goods_panel",
    "china_top_m2_goods_status_current_panel_bundle",
    "china_top_m2_goods_status_current_unit_summary",
    "fect_ife_china_top_m2_goods_status_current_min5_risk_set",
    "fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test"
  )
  sort(unique(c(from_paper, diagnostics_extras)))
}
