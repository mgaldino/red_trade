#!/usr/bin/env Rscript

# Run the final Goal 2 targets that feed the paper after setting the
# cross-country bootstrap/iteration counts to 10,000 in _targets.R.

library(targets)
library(tidyselect)

targets::tar_make(
  names = tidyselect::all_of(c(
    "fect_fe_china_top",
    "fect_ife_china_top",
    "fect_ife_china_top_summary",
    "fect_ife_china_top_cov",
    "fect_ife_china_top_cov_summary",
    "fect_carryover_china_top",
    "panelmatch_att_china_top",
    "panelmatch_art_china_top",
    "plot_fect_ife_gap_china_top",
    "plot_fect_ife_exit_china_top",
    "plot_pm_combined_china_top",
    "plot_diagnostics_main_china_top",
    "plot_diagnostics_equiv_china_top",
    "fect_ife_china_top_loo"
  ))
)
