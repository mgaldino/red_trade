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

make_treatment_duration_summary <- function(panel) {
  panel %>%
    dplyr::arrange(iso3c, year) %>%
    dplyr::group_by(iso3c, country_name) %>%
    dplyr::mutate(
      treatment_entry = china_top == 1L &
        dplyr::lag(china_top, default = 0L) == 0L,
      treatment_exit = china_top == 0L &
        dplyr::lag(china_top, default = 0L) == 1L
    ) %>%
    dplyr::summarise(
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      first_treated_year = ifelse(
        treated_years > 0L,
        min(year[china_top == 1L], na.rm = TRUE),
        NA_integer_
      ),
      last_treated_year = ifelse(
        treated_years > 0L,
        max(year[china_top == 1L], na.rm = TRUE),
        NA_integer_
      ),
      treatment_entries = sum(treatment_entry, na.rm = TRUE),
      treatment_exits = sum(treatment_exit, na.rm = TRUE),
      ever_treated = treated_years > 0L,
      .groups = "drop"
    ) %>%
    dplyr::arrange(treated_years, first_treated_year, iso3c)
}

fit_one_model <- function(panel, label, excluded_iso3c, nboots, fml) {
  message("Estimating: ", label)

  sample_panel <- panel %>%
    dplyr::filter(!iso3c %in% excluded_iso3c)

  fit <- tryCatch(
    run_fect_analysis(
      sample_panel,
      method = "ife",
      nboots = nboots,
      fml = fml
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      model = label,
      status = "error",
      error_message = conditionMessage(fit),
      nboots = nboots,
      n_excluded_treated = length(excluded_iso3c),
      excluded_iso3c = paste(excluded_iso3c, collapse = ";"),
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      n_treated = NA_integer_,
      n_control = NA_integer_
    ))
  }

  s <- summarize_fect_model(fit, sample_panel, fml = fml)

  tibble::as_tibble(s) %>%
    dplyr::mutate(
      model = label,
      status = "ok",
      error_message = NA_character_,
      nboots = nboots,
      n_excluded_treated = length(excluded_iso3c),
      excluded_iso3c = paste(excluded_iso3c, collapse = ";"),
      .before = att
    )
}

write_report <- function(output_dir, model_results, one_year_countries,
                         duration_summary, nboots) {
  result_lines <- model_results %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ": ATT = ", sprintf("%.3f", att),
        ", SE = ", sprintf("%.3f", se),
        ", 95% CI [", sprintf("%.3f", ci_lo), ", ",
        sprintf("%.3f", ci_hi), "]",
        ", p = ", sprintf("%.3f", p),
        ", r* = ", r_cv,
        ", countries = ", n_countries,
        ", treated = ", n_treated,
        ", controls = ", n_control
      )
    ) %>%
    dplyr::pull(line)

  one_year_lines <- one_year_countries %>%
    dplyr::mutate(
      line = paste0(
        "- ", iso3c, " (", country_name, "), year ",
        first_treated_year
      )
    ) %>%
    dplyr::pull(line)

  if (length(one_year_lines) == 0L) {
    one_year_lines <- "- No one-year treated countries in the fect estimation sample."
  }

  duration_lines <- duration_summary %>%
    dplyr::filter(ever_treated) %>%
    dplyr::count(treated_years, name = "n_treated_countries") %>%
    dplyr::arrange(treated_years) %>%
    dplyr::mutate(
      line = paste0("- ", treated_years, " treated years: ",
                    n_treated_countries, " countries")
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# China top-partner fect IFE: excluding one-year treated countries",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("Bootstrap replications: ", nboots),
    "",
    "The sample excludes China and countries where China was already observed as the rank-1 export destination before 2000. Treatment starts only when China becomes rank 1 in or after 2000 after an observed prior non-China-top year. This diagnostic removes treated countries with exactly one treated year in the complete-case fect estimation sample. Those countries are dropped from the sample rather than recoded as controls.",
    "",
    "## Model Results",
    "",
    result_lines,
    "",
    "## One-Year Treated Countries Removed",
    "",
    one_year_lines,
    "",
    "## Treated-Year Distribution",
    "",
    duration_lines,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_one_year_treated_model_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_one_year_treated_countries.csv`",
    "- `quality_reports/cross_country_sample/china_top_treatment_duration_by_country.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_one_year_treated_report.md"),
    useBytes = TRUE
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args)

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_year <- 1990L
min_entry_year <- 2000L
fml <- abs_distance_china ~ china_top + log_gdp_pc + free_press

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Building China top-partner panel with pre-2000 China-top countries excluded...")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = min_entry_year,
  exclude_pre_min_entry_china_top = TRUE
)

panel_cov <- china_top_panel %>%
  dplyr::left_join(covariates_panel, by = c("iso3c", "year"))

fect_data <- prepare_fect_data(panel_cov, fml = fml)
duration_summary <- make_treatment_duration_summary(fect_data)

one_year_countries <- duration_summary %>%
  dplyr::filter(ever_treated, treated_years == 1L)

one_year_iso3c <- one_year_countries %>%
  dplyr::pull(iso3c)

model_results <- dplyr::bind_rows(
  fit_one_model(
    panel = panel_cov,
    label = "Original",
    excluded_iso3c = character(),
    nboots = nboots,
    fml = fml
  ),
  fit_one_model(
    panel = panel_cov,
    label = "Exclude one-year treated countries",
    excluded_iso3c = one_year_iso3c,
    nboots = nboots,
    fml = fml
  )
)

readr::write_csv(
  model_results,
  file.path(output_dir, "china_top_one_year_treated_model_results.csv")
)
readr::write_csv(
  one_year_countries,
  file.path(output_dir, "china_top_one_year_treated_countries.csv")
)
readr::write_csv(
  duration_summary,
  file.path(output_dir, "china_top_treatment_duration_by_country.csv")
)

write_report(
  output_dir = output_dir,
  model_results = model_results,
  one_year_countries = one_year_countries,
  duration_summary = duration_summary,
  nboots = nboots
)

print(model_results %>%
        dplyr::select(
          model,
          status,
          att,
          se,
          ci_lo,
          ci_hi,
          p,
          r_cv,
          n_countries,
          n_treated,
          n_control,
          n_excluded_treated,
          excluded_iso3c
        ))

cat("\nReport written to: ",
    file.path(output_dir, "china_top_one_year_treated_report.md"),
    "\n",
    sep = "")
