#!/usr/bin/env Rscript

# Summarize the Goal 2 targets after rerunning final cross-country models with
# 10,000 bootstrap/PanelMatch iterations inside the targets pipeline.

library(targets)
library(dplyr)
library(here)

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")

fect_ife_fit <- targets::tar_read(fect_ife_china_top)
fect_fe_fit <- targets::tar_read(fect_fe_china_top)
fect_carry_fit <- targets::tar_read(fect_carryover_china_top)
fect_ife_cov_fit <- targets::tar_read(fect_ife_china_top_cov)

fect_ife_s <- targets::tar_read(fect_ife_china_top_summary)
fect_ife_cov_s <- targets::tar_read(fect_ife_china_top_cov_summary)
loo_s <- targets::tar_read(fect_ife_china_top_loo)
pm_att <- targets::tar_read(panelmatch_att_china_top)
pm_art <- targets::tar_read(panelmatch_art_china_top)

bootstrap_counts <- tibble::tibble(
  target = c(
    "fect_fe_china_top",
    "fect_ife_china_top",
    "fect_carryover_china_top",
    "fect_ife_china_top_cov"
  ),
  bootstrap_draws = c(
    length(fect_fe_fit$att.avg.boot),
    length(fect_ife_fit$att.avg.boot),
    length(fect_carry_fit$att.avg.boot),
    length(fect_ife_cov_fit$att.avg.boot)
  ),
  r_cv = c(
    if (!is.null(fect_fe_fit$r.cv)) as.numeric(fect_fe_fit$r.cv) else NA_real_,
    if (!is.null(fect_ife_fit$r.cv)) as.numeric(fect_ife_fit$r.cv) else NA_real_,
    if (!is.null(fect_carry_fit$r.cv)) as.numeric(fect_carry_fit$r.cv) else NA_real_,
    if (!is.null(fect_ife_cov_fit$r.cv)) as.numeric(fect_ife_cov_fit$r.cv) else NA_real_
  )
)

main_results <- dplyr::bind_rows(
  fect_ife_s |>
    dplyr::mutate(model = "fect IFE", .before = 1),
  fect_ife_cov_s |>
    dplyr::mutate(model = "fect IFE with covariates", .before = 1)
) |>
  dplyr::select(
    model,
    att,
    se,
    ci_lo,
    ci_hi,
    p,
    r_cv,
    att_rel_pct,
    att_sd_units,
    n_obs,
    n_countries,
    n_treated,
    n_control,
    panel_min,
    panel_max
  )

panelmatch_results <- dplyr::bind_rows(
  pm_att$summary_df |>
    dplyr::mutate(model = "PanelMatch ATT", .before = 1),
  pm_art$summary_df |>
    dplyr::mutate(model = "PanelMatch ART", .before = 1)
) |>
  dplyr::select(model, dplyr::everything())

loo_results <- loo_s |>
  dplyr::arrange(iso3c) |>
  dplyr::select(dropped, iso3c, att, se, p, r_cv)

warnings_meta <- targets::tar_meta(fields = warnings, complete_only = TRUE) |>
  dplyr::filter(lengths(warnings) > 0L) |>
  dplyr::mutate(
    warnings = vapply(
      warnings,
      function(x) paste(as.character(x), collapse = " | "),
      character(1)
    )
  ) |>
  dplyr::select(name, warnings)

bootstrap_path <- file.path(out_dir, paste0("goal2_10k_bootstrap_counts_", run_id, ".csv"))
main_path <- file.path(out_dir, paste0("goal2_10k_main_fect_results_", run_id, ".csv"))
panelmatch_path <- file.path(out_dir, paste0("goal2_10k_panelmatch_results_", run_id, ".csv"))
loo_path <- file.path(out_dir, paste0("goal2_10k_leave_one_out_results_", run_id, ".csv"))
report_path <- file.path(out_dir, paste0(run_date, "_goal2_10k_targets_check_", run_id, ".md"))

utils::write.csv(bootstrap_counts, bootstrap_path, row.names = FALSE)
utils::write.csv(main_results, main_path, row.names = FALSE)
utils::write.csv(panelmatch_results, panelmatch_path, row.names = FALSE)
utils::write.csv(loo_results, loo_path, row.names = FALSE)

format_table <- function(data) {
  data <- tibble::as_tibble(data)
  paste(capture.output(print(data, n = Inf, width = Inf)), collapse = "\n")
}

sink(report_path)
cat("# Goal 2 targets 10k check\n\n")
cat("Date: ", run_date, "\n\n", sep = "")
cat("Run timestamp: ", run_timestamp, "\n\n", sep = "")
cat("Execution script: `scripts/diagnostics/run_goal2_final_targets_10k.R`\n\n")
cat("This report reads completed targets after the final Goal 2 cross-country models were rerun inside `targets`.\n\n")

cat("## Bootstrap counts\n\n")
cat("```text\n")
cat(format_table(bootstrap_counts))
cat("\n```\n\n")

cat("## Main fect results\n\n")
cat("```text\n")
cat(format_table(main_results))
cat("\n```\n\n")

cat("## PanelMatch results\n\n")
cat("```text\n")
cat(format_table(panelmatch_results))
cat("\n```\n\n")

cat("## Leave-one-out results\n\n")
cat("```text\n")
cat(format_table(loo_results))
cat("\n```\n\n")

cat("## Target warnings\n\n")
if (nrow(warnings_meta) == 0L) {
  cat("No completed target warnings recorded.\n\n")
} else {
  cat("```text\n")
  cat(format_table(warnings_meta))
  cat("\n```\n\n")
}

cat("## Files written\n\n")
cat("- `", bootstrap_path, "`\n", sep = "")
cat("- `", main_path, "`\n", sep = "")
cat("- `", panelmatch_path, "`\n", sep = "")
cat("- `", loo_path, "`\n", sep = "")
cat("- `", report_path, "`\n", sep = "")
sink()

cat("Wrote:\n")
cat("- ", bootstrap_path, "\n", sep = "")
cat("- ", main_path, "\n", sep = "")
cat("- ", panelmatch_path, "\n", sep = "")
cat("- ", loo_path, "\n", sep = "")
cat("- ", report_path, "\n", sep = "")
