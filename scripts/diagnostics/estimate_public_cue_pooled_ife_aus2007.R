#!/usr/bin/env Rscript

# Re-estimates the four pooled interactive fixed-effects models of the public-cue
# design with Australia treated from its 2007 public cue.
#
# Starts from the four model panels written by
# scripts/diagnostics/estimate_selected_public_cue_sdid_fect.R and repeats its
# fect() call unchanged. Only Australia's treatment path changes: focal treatment
# starts at the public-cue year and stays on while China is the top goods-export
# destination, or before China first reaches that position. For every other focal
# country the cue year is at or after the goods-export entry, so the rule
# reproduces the original coding (checked below).
#
# Outside the targets graph; listed for migration in TARGETS_MIGRATION.md.
# The original models were estimated with fect 2.4.5 outside renv; run this script
# the same way (Rscript --vanilla) so the only difference is Australia's timing.
#
# Usage:
#   PUBLIC_CUE_AUS_YEAR=2009 Rscript --vanilla scripts/diagnostics/estimate_public_cue_pooled_ife_aus2007.R
#   PUBLIC_CUE_AUS_YEAR=2007 Rscript --vanilla scripts/diagnostics/estimate_public_cue_pooled_ife_aus2007.R
# The 2009 run must reproduce the stored estimates before the 2007 run is used.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

aus_year <- as.integer(Sys.getenv("PUBLIC_CUE_AUS_YEAR", unset = "2007"))
stopifnot(aus_year %in% c(2007L, 2009L))

fect_bootstraps <- 1000L
year_start <- 1997L
year_end <- 2022L
expected_n_years <- length(seq.int(year_start, year_end))

input_dir <- file.path(
  "data", "processed", "diagnostics", "selected_public_cue_sdid_fect"
)
output_dir <- file.path(
  "data", "processed", "diagnostics", "public_cue_pooled_ife_aus2007"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

model_ids <- c(
  "clean_controls",
  "full_switching",
  "clean_controls_without_gab_qat",
  "full_switching_without_gab_qat"
)
panel_files <- c(
  clean_controls = "fect_clean_controls_panel.csv",
  full_switching = "fect_full_switching_panel.csv",
  clean_controls_without_gab_qat = "fect_clean_controls_without_gab_qat_panel.csv",
  full_switching_without_gab_qat = "fect_full_switching_without_gab_qat_panel.csv"
)

recode_australia <- function(panel_data) {
  goods_entry <- panel_data |>
    dplyr::filter(focal_country, china_is_top %in% TRUE, year >= 2000L) |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(goods_entry_year = min(year), .groups = "drop")

  out <- panel_data |>
    dplyr::mutate(
      public_cue_year = dplyr::if_else(
        iso3c == "AUS", aus_year, as.integer(public_cue_year)
      )
    ) |>
    dplyr::left_join(goods_entry, by = "iso3c") |>
    dplyr::mutate(
      treatment_new = as.integer(
        focal_country & year >= public_cue_year &
          (china_is_top %in% TRUE | year < goods_entry_year)
      )
    )

  # Outside Australia the rule must reproduce the stored treatment exactly.
  stopifnot(all(out$treatment_new[out$iso3c != "AUS"] ==
                  out$treatment[out$iso3c != "AUS"]))
  if (aus_year == 2009L) {
    stopifnot(all(out$treatment_new == out$treatment))
  }

  out |>
    dplyr::mutate(treatment = treatment_new) |>
    dplyr::select(-treatment_new, -goods_entry_year)
}

extract_selected_factors <- function(fit) {
  if (!is.null(fit$r.cv) && "r" %in% names(fit$r.cv)) {
    as.integer(fit$r.cv[["r"]])
  } else {
    NA_integer_
  }
}

run_fect <- function(panel_data, model_id) {
  message("Estimating `", model_id, "` with Australia from ", aus_year, ".")
  set.seed(42L)
  timing <- system.time({
    fit <- fect::fect(
      model_outcome ~ treatment,
      data = as.data.frame(panel_data),
      index = c("country_id", "year"),
      method = "ife",
      force = "two-way",
      na.rm = FALSE,
      em = TRUE,
      se = TRUE,
      nboots = fect_bootstraps,
      parallel = FALSE,
      CV = TRUE,
      r = c(0, 3),
      min.T0 = 1L,
      max.missing = expected_n_years,
      seed = 42L
    )
  })
  overall_se <- stats::sd(as.numeric(fit$att.avg.boot), na.rm = TRUE)
  overall_z <- as.numeric(fit$att.avg) / overall_se
  tibble::tibble(
    model_id = model_id,
    australia_cue_year = aus_year,
    estimate = as.numeric(fit$att.avg),
    se_bootstrap = overall_se,
    ci_95_low = as.numeric(fit$att.avg) - stats::qnorm(0.975) * overall_se,
    ci_95_high = as.numeric(fit$att.avg) + stats::qnorm(0.975) * overall_se,
    p_normal_two_sided = 2 * stats::pnorm(-abs(overall_z)),
    selected_factors = extract_selected_factors(fit),
    n_treated_units = as.integer(fit$Ntr),
    n_never_treated_units = as.integer(fit$Nco),
    n_treated_country_years = sum(panel_data$treatment == 1L &
                                    panel_data$country_id %in% fit$id),
    bootstrap_replications = fect_bootstraps,
    bootstrap_seed = 42L,
    elapsed_seconds = as.numeric(timing[["elapsed"]]),
    fect_version = as.character(utils::packageVersion("fect"))
  )
}

results <- dplyr::bind_rows(lapply(model_ids, function(id) {
  panel_data <- readr::read_csv(
    file.path(input_dir, panel_files[[id]]),
    show_col_types = FALSE
  ) |>
    recode_australia() |>
    dplyr::arrange(country_id, year)
  run_fect(panel_data, id)
}))

readr::write_csv(
  results,
  file.path(output_dir, paste0("fect_results_aus", aus_year, ".csv"))
)
writeLines(
  capture.output(sessionInfo()),
  file.path(output_dir, paste0("session_info_aus", aus_year, ".txt"))
)

if (aus_year == 2009L) {
  stored <- readr::read_csv(
    file.path(input_dir, "fect_results.csv"),
    show_col_types = FALSE
  ) |>
    dplyr::select(model_id, stored_estimate = estimate, stored_se = se_bootstrap,
                  stored_factors = selected_factors)
  check <- results |>
    dplyr::left_join(stored, by = "model_id") |>
    dplyr::mutate(
      diff_estimate = abs(estimate - stored_estimate),
      diff_se = abs(se_bootstrap - stored_se)
    ) |>
    dplyr::select(model_id, estimate, stored_estimate, diff_estimate,
                  se_bootstrap, stored_se, diff_se, selected_factors, stored_factors)
  readr::write_csv(check, file.path(output_dir, "reproduction_check_aus2009.csv"))
  print(as.data.frame(check))
}

print(as.data.frame(results))
