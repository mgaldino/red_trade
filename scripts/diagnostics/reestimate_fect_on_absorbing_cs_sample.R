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

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

as_fect_panel <- function(cs_data) {
  cs_data %>%
    dplyr::mutate(
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      ),
      country_id = as.integer(as.factor(iso3c))
    ) %>%
    dplyr::arrange(country_id, year)
}

fit_fect_model <- function(panel, label, method, nboots, fml, covariates) {
  message("Estimating fect ", method, ": ", label)

  fit <- tryCatch(
    run_fect_analysis(
      panel,
      method = method,
      nboots = nboots,
      fml = fml
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      model = label,
      estimator = paste0("fect_", method),
      status = "error",
      error_message = conditionMessage(fit),
      covariates = covariates,
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_real_,
      att_rel_pct = NA_real_,
      att_sd_units = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      n_treated = NA_integer_,
      n_control = NA_integer_,
      n_treated_country_years = NA_integer_,
      n_entries = NA_integer_,
      n_exits = NA_integer_,
      n_left_censored = NA_integer_,
      panel_min = NA_integer_,
      panel_max = NA_integer_,
      pre_treated_mean = NA_real_,
      outcome_sd = NA_real_
    ))
  }

  summarize_fect_model(fit, panel, fml = fml) %>%
    tibble::as_tibble() %>%
    dplyr::mutate(
      model = label,
      estimator = paste0("fect_", method),
      status = "ok",
      error_message = NA_character_,
      covariates = covariates,
      nboots = nboots,
      .before = att
    )
}

make_treated_country_table <- function(panel, label) {
  panel %>%
    dplyr::filter(china_top == 1L) %>%
    dplyr::group_by(iso3c, country_name) %>%
    dplyr::summarise(
      first_treated_year = min(year, na.rm = TRUE),
      last_treated_year = max(year, na.rm = TRUE),
      treated_years = dplyr::n_distinct(year),
      .groups = "drop"
    ) %>%
    dplyr::mutate(model = label, .before = iso3c) %>%
    dplyr::arrange(model, first_treated_year, iso3c)
}

write_report <- function(output_dir, results, treated_countries, nboots) {
  result_lines <- results %>%
    dplyr::mutate(
      line = paste0(
        "- ", model, " (", estimator, ")",
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", 95% CI [", format_num(ci_lo), ", ",
        format_num(ci_hi), "]",
        ", p = ", format_num(p),
        ", r* = ", format_num(r_cv, 0L),
        ", countries = ", n_countries,
        ", treated = ", n_treated,
        ", controls = ", n_control,
        ", panel = ", panel_min, "-", panel_max
      )
    ) %>%
    dplyr::pull(line)

  treated_lines <- treated_countries %>%
    dplyr::filter(model == "No covariates") %>%
    dplyr::mutate(
      line = paste0(
        "- ", iso3c, " (", country_name, "), ",
        first_treated_year, "-", last_treated_year,
        ", treated years = ", treated_years
      )
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# fect on the absorbing C&S estimation sample",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("Bootstrap replications: ", nboots),
    "",
    "This diagnostic rebuilds the corrected broad China-top partner panel, constructs the absorbing C&S estimation samples, and then runs `fect` on exactly those samples. The no-covariate fect model uses the no-covariate C&S sample; the covariate-adjusted fect model uses the complete-case C&S covariate sample. Treated switchers are excluded, and never-treated countries remain as controls.",
    "",
    "## Results",
    "",
    result_lines,
    "",
    "## Absorbing treated countries in the no-covariate fect/C&S sample",
    "",
    treated_lines,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_sample_fect_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_sample_fect_treated_countries.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_absorbing_cs_sample_fect_report.md"),
    useBytes = TRUE
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args)

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

fect_panel <- as_fect_panel(cs_data)
fect_cov_panel <- as_fect_panel(cs_cov_data)

results <- dplyr::bind_rows(
  fit_fect_model(
    panel = fect_panel,
    label = "No covariates",
    method = "ife",
    nboots = nboots,
    fml = abs_distance_china ~ china_top,
    covariates = "None"
  ),
  fit_fect_model(
    panel = fect_cov_panel,
    label = "log_gdp_pc + free_press",
    method = "ife",
    nboots = nboots,
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press,
    covariates = "log_gdp_pc + free_press"
  ),
  fit_fect_model(
    panel = fect_panel,
    label = "No covariates",
    method = "fe",
    nboots = nboots,
    fml = abs_distance_china ~ china_top,
    covariates = "None"
  ),
  fit_fect_model(
    panel = fect_cov_panel,
    label = "log_gdp_pc + free_press",
    method = "fe",
    nboots = nboots,
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press,
    covariates = "log_gdp_pc + free_press"
  )
)

treated_countries <- dplyr::bind_rows(
  make_treated_country_table(fect_panel, "No covariates"),
  make_treated_country_table(fect_cov_panel, "log_gdp_pc + free_press")
)

readr::write_csv(
  results,
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_results.csv")
)
readr::write_csv(
  treated_countries,
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_treated_countries.csv")
)

write_report(
  output_dir = output_dir,
  results = results,
  treated_countries = treated_countries,
  nboots = nboots
)

print(results %>%
        dplyr::select(
          model,
          estimator,
          status,
          att,
          se,
          ci_lo,
          ci_hi,
          p,
          r_cv,
          n_obs,
          n_countries,
          n_treated,
          n_control,
          panel_min,
          panel_max
        ))

message(
  "Wrote report to ",
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_report.md")
)
