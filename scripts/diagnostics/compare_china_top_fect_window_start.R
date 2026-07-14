#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

parse_nboots <- function(args, default = 500L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    return(default)
  }
  as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
}

make_full_entry_table <- function(panel) {
  panel %>%
    dplyr::arrange(iso3c, year) %>%
    dplyr::group_by(iso3c) %>%
    dplyr::mutate(
      china_top_lag = dplyr::lag(china_top),
      treatment_entry = china_top == 1L &
        !is.na(china_top_lag) &
        china_top_lag == 0L
    ) %>%
    dplyr::summarise(
      country_name = dplyr::first(stats::na.omit(country_name)),
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      first_entry_year = ifelse(
        any(treatment_entry, na.rm = TRUE),
        min(year[treatment_entry], na.rm = TRUE),
        NA_integer_
      ),
      .groups = "drop"
    )
}

summarise_window_support <- function(panel, fml, window_start, full_entry_table) {
  fect_data <- prepare_fect_data(panel, fml = fml)

  unit_support <- fect_data %>%
    dplyr::group_by(iso3c) %>%
    dplyr::summarise(
      country_name = dplyr::first(stats::na.omit(country_name)),
      first_estimation_year = min(year, na.rm = TRUE),
      last_estimation_year = max(year, na.rm = TRUE),
      ever_treated_in_window = any(china_top == 1L, na.rm = TRUE),
      treated_at_first_estimation_year = dplyr::first(china_top) == 1L,
      .groups = "drop"
    ) %>%
    dplyr::left_join(
      full_entry_table %>%
        dplyr::select(iso3c, full_ever_treated = ever_treated, first_entry_year),
      by = "iso3c"
    ) %>%
    dplyr::mutate(
      full_ever_treated = dplyr::coalesce(full_ever_treated, FALSE)
    )

  pre_support <- fect_data %>%
    dplyr::left_join(
      unit_support %>%
        dplyr::select(iso3c, first_entry_year),
      by = "iso3c"
    ) %>%
    dplyr::group_by(iso3c) %>%
    dplyr::summarise(
      pre_periods_before_full_entry = ifelse(
        any(!is.na(first_entry_year)),
        sum(year < first_entry_year & china_top == 0L, na.rm = TRUE),
        sum(china_top == 0L, na.rm = TRUE)
      ),
      .groups = "drop"
    )

  unit_support <- unit_support %>%
    dplyr::left_join(pre_support, by = "iso3c")

  treated_units <- unit_support %>%
    dplyr::filter(full_ever_treated)

  tibble::tibble(
    window_start = window_start,
    n_obs = nrow(fect_data),
    n_countries = dplyr::n_distinct(fect_data$iso3c),
    n_full_treated_countries = sum(unit_support$full_ever_treated, na.rm = TRUE),
    n_treated_in_window = sum(unit_support$ever_treated_in_window, na.rm = TRUE),
    n_left_censored_treated_in_window = sum(
      unit_support$full_ever_treated &
        unit_support$treated_at_first_estimation_year,
      na.rm = TRUE
    ),
    min_pre_periods_treated = min(
      treated_units$pre_periods_before_full_entry,
      na.rm = TRUE
    ),
    median_pre_periods_treated = stats::median(
      treated_units$pre_periods_before_full_entry,
      na.rm = TRUE
    ),
    n_treated_with_lt_5_pre_periods = sum(
      treated_units$pre_periods_before_full_entry < 5L,
      na.rm = TRUE
    ),
    n_treated_with_zero_pre_periods = sum(
      treated_units$pre_periods_before_full_entry == 0L,
      na.rm = TRUE
    )
  )
}

fit_window <- function(panel, fml, nboots, window_start) {
  message("Estimating fect IFE for window start ", window_start)
  fit <- tryCatch(
    run_fect_analysis(
      panel,
      method = "ife",
      nboots = nboots,
      fml = fml
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      window_start = window_start,
      status = "error",
      error_message = conditionMessage(fit),
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_real_
    ))
  }

  s <- fect_att_summary(fit)

  tibble::tibble(
    window_start = window_start,
    status = "ok",
    error_message = NA_character_,
    nboots = nboots,
    att = s$att,
    se = s$se,
    ci_lo = s$ci_lo,
    ci_hi = s$ci_hi,
    p = s$p,
    r_cv = s$r_cv
  )
}

write_report <- function(output_dir, results, support, nboots) {
  result_lines <- results %>%
    dplyr::mutate(
      line = paste0(
        "- window start ", window_start,
        ": ATT = ", sprintf("%.3f", att),
        ", SE = ", sprintf("%.3f", se),
        ", 95% CI [", sprintf("%.3f", ci_lo), ", ",
        sprintf("%.3f", ci_hi), "]",
        ", p = ", sprintf("%.3f", p),
        ", r* = ", r_cv
      )
    ) %>%
    dplyr::pull(line)

  support_lines <- support %>%
    dplyr::mutate(
      line = paste0(
        "- window start ", window_start,
        ": countries = ", n_countries,
        ", treated in window = ", n_treated_in_window,
        ", left-censored treated = ", n_left_censored_treated_in_window,
        ", median treated pre-periods = ", median_pre_periods_treated,
        ", treated with <5 pre-periods = ", n_treated_with_lt_5_pre_periods,
        ", treated with zero pre-periods = ", n_treated_with_zero_pre_periods
      )
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# fect IFE window-start diagnostic",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("Bootstrap replications: ", nboots),
    "",
    "Treatment is classified using the full trade and UNGA history from 1990 onward. The diagnostic then filters the estimation window to test what happens if fect starts later. This avoids redefining treatment on a left-censored panel.",
    "",
    "## Estimation Results",
    "",
    result_lines,
    "",
    "## Pre-treatment Support",
    "",
    support_lines,
    "",
    "## Interpretation",
    "",
    "Starting the fect estimation window later is not equivalent to a harmless time fixed-effect change. It removes pre-treatment information used to estimate the interactive fixed-effect counterfactual and creates left-censored treated units for countries already treated at the first estimation year.",
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_fect_window_start_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_fect_window_start_support.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_fect_window_start_report.md"),
    useBytes = TRUE
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args)

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fml <- abs_distance_china ~ china_top + log_gdp_pc + free_press
window_starts <- c(1990L, 2000L, 2001L)

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Building full treatment panel from 1990 for treatment classification...")
full_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = 1990L,
  min_entry_year = 2000L
)

full_entry_table <- make_full_entry_table(full_panel)

panel_cov <- full_panel %>%
  dplyr::left_join(covariates_panel, by = c("iso3c", "year"))

window_panels <- lapply(
  window_starts,
  function(window_start) {
    panel_cov %>%
      dplyr::filter(year >= window_start)
  }
)
names(window_panels) <- as.character(window_starts)

support <- dplyr::bind_rows(lapply(
  window_starts,
  function(window_start) {
    summarise_window_support(
      panel = window_panels[[as.character(window_start)]],
      fml = fml,
      window_start = window_start,
      full_entry_table = full_entry_table
    )
  }
))

results <- dplyr::bind_rows(lapply(
  window_starts,
  function(window_start) {
    fit_window(
      panel = window_panels[[as.character(window_start)]],
      fml = fml,
      nboots = nboots,
      window_start = window_start
    )
  }
))

readr::write_csv(
  results,
  file.path(output_dir, "china_top_fect_window_start_results.csv")
)
readr::write_csv(
  support,
  file.path(output_dir, "china_top_fect_window_start_support.csv")
)

write_report(
  output_dir = output_dir,
  results = results,
  support = support,
  nboots = nboots
)

print(results)
cat("\nPre-treatment support:\n")
print(support)
cat("\nReport written to: ",
    file.path(output_dir, "china_top_fect_window_start_report.md"),
    "\n",
    sep = "")
