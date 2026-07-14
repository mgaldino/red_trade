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

estimate_overall <- function(event_data, xformla) {
  fit <- run_cross_country_did(
    event_data,
    xformla = xformla,
    aggte_na_rm = TRUE
  )
  overall <- fit$overall_att
  att <- unname(overall$overall.att)
  se <- unname(overall$overall.se)

  tibble::tibble(
    att = att,
    se = se,
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se,
    p = 2 * stats::pnorm(-abs(att / se)),
    n_obs = nrow(event_data),
    n_countries = dplyr::n_distinct(event_data$iso3c),
    n_treated = dplyr::n_distinct(event_data$iso3c[event_data$first_treat > 0]),
    n_control = dplyr::n_distinct(event_data$iso3c[event_data$first_treat == 0])
  )
}

run_leave_one_out <- function(event_data, label, xformla) {
  message("Running leave-one-out C&S: ", label)
  set.seed(42)

  base <- estimate_overall(event_data, xformla) %>%
    dplyr::mutate(
      model = label,
      excluded_iso3c = NA_character_,
      excluded_country_name = NA_character_,
      excluded_first_treat = NA_real_,
      status = "ok",
      error_message = NA_character_,
      .before = att
    )

  treated_units <- event_data %>%
    dplyr::filter(first_treat > 0) %>%
    dplyr::distinct(iso3c, first_treat) %>%
    dplyr::mutate(
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      )
    ) %>%
    dplyr::arrange(first_treat, iso3c)

  loo <- dplyr::bind_rows(lapply(seq_len(nrow(treated_units)), function(i) {
    unit <- treated_units[i, ]
    sample_data <- event_data %>%
      dplyr::filter(iso3c != unit$iso3c)

    fit <- tryCatch(
      estimate_overall(sample_data, xformla),
      error = function(e) e
    )

    if (inherits(fit, "error")) {
      return(tibble::tibble(
        model = label,
        excluded_iso3c = unit$iso3c,
        excluded_country_name = unit$country_name,
        excluded_first_treat = unit$first_treat,
        status = "error",
        error_message = conditionMessage(fit),
        att = NA_real_,
        se = NA_real_,
        ci_lo = NA_real_,
        ci_hi = NA_real_,
        p = NA_real_,
        n_obs = nrow(sample_data),
        n_countries = dplyr::n_distinct(sample_data$iso3c),
        n_treated = dplyr::n_distinct(sample_data$iso3c[sample_data$first_treat > 0]),
        n_control = dplyr::n_distinct(sample_data$iso3c[sample_data$first_treat == 0])
      ))
    }

    fit %>%
      dplyr::mutate(
        model = label,
        excluded_iso3c = unit$iso3c,
        excluded_country_name = unit$country_name,
        excluded_first_treat = unit$first_treat,
        status = "ok",
        error_message = NA_character_,
        .before = att
      )
  }))

  dplyr::bind_rows(base, loo) %>%
    dplyr::mutate(
      base_att = base$att[[1]],
      delta_att = att - base_att,
      abs_delta_att = abs(delta_att)
    ) %>%
    dplyr::arrange(model, dplyr::desc(abs_delta_att))
}

write_report <- function(output_dir, influence_results) {
  base_lines <- influence_results %>%
    dplyr::filter(is.na(excluded_iso3c)) %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", p = ", format_num(p),
        ", treated = ", n_treated,
        ", controls = ", n_control
      )
    ) %>%
    dplyr::pull(line)

  top_lines <- influence_results %>%
    dplyr::filter(!is.na(excluded_iso3c), status == "ok") %>%
    dplyr::group_by(model) %>%
    dplyr::slice_max(abs_delta_att, n = 5, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(model, dplyr::desc(abs_delta_att)) %>%
    dplyr::mutate(
      line = paste0(
        "- ", model, ": excluding ", excluded_iso3c,
        " (", excluded_country_name, ", ", excluded_first_treat,
        ") gives ATT = ", format_num(att),
        ", p = ", format_num(p),
        ", delta = ", format_num(delta_att)
      )
    ) %>%
    dplyr::pull(line)

  brazil_lines <- influence_results %>%
    dplyr::filter(excluded_iso3c == "BRA") %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ": excluding Brazil gives ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", p = ", format_num(p),
        ", delta = ", format_num(delta_att)
      )
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# C&S absorbing-treatment leave-one-treated-country diagnostics",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "This diagnostic uses the corrected broad China-top sample and the absorbing C&S design. Each leave-one-out run removes one absorbing treated country from the estimation sample while retaining never-treated controls.",
    "",
    "## Baseline",
    "",
    base_lines,
    "",
    "## Most influential exclusions",
    "",
    top_lines,
    "",
    "## Brazil exclusion",
    "",
    brazil_lines,
    "",
    "## Output file",
    "",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_leave_one_out.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_absorbing_cs_leave_one_out_report.md"),
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

cs_data <- prepare_absorbing_china_top_did_data(
  china_top_panel,
  min_entry_year = min_entry_year
)

cs_cov_data <- prepare_absorbing_china_top_did_data(
  panel_cov,
  covariate_cols = covariates,
  min_entry_year = min_entry_year
)

influence_results <- dplyr::bind_rows(
  run_leave_one_out(cs_data, "No covariates", ~1),
  run_leave_one_out(
    cs_cov_data,
    "log_gdp_pc + free_press",
    ~ log_gdp_pc + free_press
  )
)

readr::write_csv(
  influence_results,
  file.path(output_dir, "china_top_absorbing_cs_leave_one_out.csv")
)

write_report(output_dir, influence_results)

print(influence_results %>%
        dplyr::filter(!is.na(excluded_iso3c), status == "ok") %>%
        dplyr::group_by(model) %>%
        dplyr::slice_max(abs_delta_att, n = 5, with_ties = FALSE) %>%
        dplyr::ungroup() %>%
        dplyr::select(
          model,
          excluded_iso3c,
          excluded_country_name,
          excluded_first_treat,
          att,
          se,
          p,
          delta_att
        ))

message(
  "Wrote report to ",
  file.path(output_dir, "china_top_absorbing_cs_leave_one_out_report.md")
)
