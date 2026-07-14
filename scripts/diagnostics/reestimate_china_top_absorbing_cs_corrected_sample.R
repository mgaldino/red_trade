#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

summarize_cs_spec <- function(did_result, event_data, label,
                              covariates, status = "ok",
                              error_message = NA_character_) {
  if (!identical(status, "ok")) {
    return(tibble::tibble(
      model = label,
      status = status,
      error_message = error_message,
      covariates = covariates,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_obs = nrow(event_data),
      n_countries = dplyr::n_distinct(event_data$iso3c),
      n_treated = dplyr::n_distinct(event_data$iso3c[event_data$first_treat > 0]),
      n_control = dplyr::n_distinct(event_data$iso3c[event_data$first_treat == 0]),
      panel_min = min(event_data$year, na.rm = TRUE),
      panel_max = max(event_data$year, na.rm = TRUE),
      first_treat_min = min(event_data$first_treat[event_data$first_treat > 0], na.rm = TRUE),
      first_treat_max = max(event_data$first_treat[event_data$first_treat > 0], na.rm = TRUE)
    ))
  }

  s <- summarize_cross_country_did(did_result, event_data)

  tibble::as_tibble(s) %>%
    dplyr::mutate(
      model = label,
      status = "ok",
      error_message = NA_character_,
      covariates = covariates,
      .before = att
    )
}

estimate_cs_spec <- function(event_data, label, xformla, covariates) {
  message("Estimating C&S: ", label)
  set.seed(42)

  fit <- tryCatch(
    run_cross_country_did(
      event_data,
      xformla = xformla,
      aggte_na_rm = TRUE
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    summary <- summarize_cs_spec(
      did_result = NULL,
      event_data = event_data,
      label = label,
      covariates = covariates,
      status = "error",
      error_message = conditionMessage(fit)
    )
    return(list(fit = NULL, summary = summary))
  }

  list(
    fit = fit,
    summary = summarize_cs_spec(
      did_result = fit,
      event_data = event_data,
      label = label,
      covariates = covariates
    )
  )
}

make_dynamic_table <- function(did_result, label) {
  if (is.null(did_result)) {
    return(tibble::tibble())
  }

  event_study <- did_result$event_study
  tibble::tibble(
    model = label,
    event_time = event_study$egt,
    att = event_study$att.egt,
    se = event_study$se.egt,
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se
  )
}

make_treated_country_table <- function(event_data, label) {
  event_data %>%
    dplyr::filter(first_treat > 0) %>%
    dplyr::distinct(iso3c, first_treat, first_treat_year, absorbing) %>%
    dplyr::mutate(
      model = label,
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      )
    ) %>%
    dplyr::select(
      model,
      iso3c,
      country_name,
      first_treat,
      first_treat_year,
      absorbing
    ) %>%
    dplyr::arrange(first_treat, iso3c)
}

make_absorbing_status_table <- function(panel, covariate_cols = NULL,
                                        min_entry_year = 2000L,
                                        label = "No covariates") {
  if (is.null(covariate_cols)) {
    covariate_cols <- character(0)
  }

  required_cols <- c("iso3c", "year", "abs_distance_china", "china_top")
  rank_observed_col <- intersect("top_partner", names(panel))
  keep_cols <- c(required_cols, rank_observed_col, covariate_cols)

  base_panel <- panel %>%
    dplyr::select(dplyr::all_of(keep_cols)) %>%
    dplyr::filter(stats::complete.cases(dplyr::select(
      .,
      dplyr::all_of(required_cols)
    ))) %>%
    dplyr::arrange(iso3c, year)

  if ("top_partner" %in% names(base_panel)) {
    base_panel <- base_panel %>% dplyr::filter(!is.na(top_partner))
  }

  if (length(covariate_cols) > 0L) {
    base_panel <- base_panel %>%
      dplyr::filter(stats::complete.cases(dplyr::select(
        .,
        dplyr::all_of(covariate_cols)
      )))
  }

  base_panel %>%
    dplyr::group_by(iso3c) %>%
    dplyr::arrange(year, .by_group = TRUE) %>%
    dplyr::mutate(
      china_top_lag = dplyr::lag(china_top),
      entry = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L
    ) %>%
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      left_censored = dplyr::first(china_top) == 1L,
      first_treat_year = ifelse(
        any(entry, na.rm = TRUE),
        min(year[entry], na.rm = TRUE),
        NA_integer_
      ),
      absorbing = ifelse(
        any(entry, na.rm = TRUE),
        all(china_top[year >= first_treat_year] == 1L, na.rm = TRUE),
        FALSE
      ),
      n_years = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      model = label,
      cs_role = dplyr::case_when(
        ever_treated & !left_censored & absorbing &
          first_treat_year >= min_entry_year ~ "treated_absorbing",
        !ever_treated ~ "never_treated",
        TRUE ~ "excluded_treated_or_ineligible"
      ),
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      )
    ) %>%
    dplyr::select(
      model,
      iso3c,
      country_name,
      cs_role,
      ever_treated,
      left_censored,
      absorbing,
      first_treat_year,
      n_years
    ) %>%
    dplyr::arrange(cs_role, first_treat_year, iso3c)
}

write_report <- function(output_dir, results, status_counts,
                         treated_countries, dynamic_results) {
  result_lines <- results %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", 95% CI [", format_num(ci_lo), ", ",
        format_num(ci_hi), "]",
        ", p = ", format_num(p),
        ", countries = ", n_countries,
        ", treated = ", n_treated,
        ", controls = ", n_control,
        ", panel = ", panel_min, "-", panel_max
      )
    ) %>%
    dplyr::pull(line)

  status_lines <- status_counts %>%
    dplyr::mutate(
      line = paste0(
        "- ", model, ", ", cs_role, ": ", n_countries, " countries"
      )
    ) %>%
    dplyr::pull(line)

  treated_lines <- treated_countries %>%
    dplyr::filter(model == "No covariates") %>%
    dplyr::mutate(
      line = paste0(
        "- ", iso3c, " (", country_name, "), first treated ",
        first_treat_year
      )
    ) %>%
    dplyr::pull(line)

  if (length(treated_lines) == 0L) {
    treated_lines <- "- No absorbing treated countries in the estimation sample."
  }

  dynamic_kept <- dynamic_results %>%
    dplyr::filter(event_time >= -5, event_time <= 10) %>%
    dplyr::mutate(
      line = paste0(
        "- ", model, ", event time ", event_time,
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se)
      )
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# C&S absorbing-treatment diagnostic on the corrected China-top sample",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "This diagnostic rebuilds the broad corrected China-top partner panel directly from `trade_data` and `unga_data`, without the old sample restriction that conditioned on countries where the United States was a top export destination. It then keeps only countries with absorbing treatment status for C&S: China first becomes the rank-1 export destination in or after 2000 after an observed prior non-China-top year, and China does not subsequently lose the top position. Never-treated countries remain as controls; treated switchers are excluded rather than recoded as controls.",
    "",
    "## Overall estimates",
    "",
    result_lines,
    "",
    "## Pre-balance country roles",
    "",
    status_lines,
    "",
    "## Absorbing treated countries in the no-covariate estimation sample",
    "",
    treated_lines,
    "",
    "## Dynamic estimates, event times -5 to 10",
    "",
    dynamic_kept,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_corrected_sample_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_corrected_sample_dynamic.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_corrected_sample_treated_countries.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_corrected_sample_status.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_absorbing_cs_corrected_sample_report.md"),
    useBytes = TRUE
  )
}

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_year <- 1990L
min_entry_year <- 2000L
covariates <- c("log_gdp_pc", "free_press")

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Building corrected broad China-top partner panel...")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = min_entry_year
)

panel_cov <- china_top_panel %>%
  dplyr::left_join(covariates_panel, by = c("iso3c", "year"))

message("Preparing absorbing C&S samples...")
cs_data <- prepare_absorbing_china_top_did_data(
  china_top_panel,
  min_entry_year = min_entry_year
)

cs_cov_data <- prepare_absorbing_china_top_did_data(
  panel_cov,
  covariate_cols = covariates,
  min_entry_year = min_entry_year
)

status_no_cov <- make_absorbing_status_table(
  china_top_panel,
  min_entry_year = min_entry_year,
  label = "No covariates"
)

status_cov <- make_absorbing_status_table(
  panel_cov,
  covariate_cols = covariates,
  min_entry_year = min_entry_year,
  label = "log_gdp_pc + free_press"
)

fit_no_cov <- estimate_cs_spec(
  event_data = cs_data,
  label = "No covariates",
  xformla = ~1,
  covariates = "None"
)

fit_cov <- estimate_cs_spec(
  event_data = cs_cov_data,
  label = "log_gdp_pc + free_press",
  xformla = ~ log_gdp_pc + free_press,
  covariates = "log_gdp_pc + free_press"
)

results <- dplyr::bind_rows(fit_no_cov$summary, fit_cov$summary)

dynamic_results <- dplyr::bind_rows(
  make_dynamic_table(fit_no_cov$fit, "No covariates"),
  make_dynamic_table(fit_cov$fit, "log_gdp_pc + free_press")
)

treated_countries <- dplyr::bind_rows(
  make_treated_country_table(cs_data, "No covariates"),
  make_treated_country_table(cs_cov_data, "log_gdp_pc + free_press")
)

status_table <- dplyr::bind_rows(status_no_cov, status_cov)

status_counts <- status_table %>%
  dplyr::count(model, cs_role, name = "n_countries") %>%
  dplyr::arrange(model, cs_role)

readr::write_csv(
  results,
  file.path(output_dir, "china_top_absorbing_cs_corrected_sample_results.csv")
)
readr::write_csv(
  dynamic_results,
  file.path(output_dir, "china_top_absorbing_cs_corrected_sample_dynamic.csv")
)
readr::write_csv(
  treated_countries,
  file.path(output_dir, "china_top_absorbing_cs_corrected_sample_treated_countries.csv")
)
readr::write_csv(
  status_table,
  file.path(output_dir, "china_top_absorbing_cs_corrected_sample_status.csv")
)
readr::write_csv(
  status_counts,
  file.path(output_dir, "china_top_absorbing_cs_corrected_sample_status_counts.csv")
)

write_report(
  output_dir = output_dir,
  results = results,
  status_counts = status_counts,
  treated_countries = treated_countries,
  dynamic_results = dynamic_results
)

print(results %>%
        dplyr::select(
          model,
          status,
          att,
          se,
          ci_lo,
          ci_hi,
          p,
          n_obs,
          n_countries,
          n_treated,
          n_control,
          panel_min,
          panel_max,
          first_treat_min,
          first_treat_max
        ))

message(
  "Wrote report to ",
  file.path(output_dir, "china_top_absorbing_cs_corrected_sample_report.md")
)
