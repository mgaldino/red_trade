#!/usr/bin/env Rscript

# Ad hoc diagnostic: compare the current factor-model treatment rule
# (China outranks USA) against the textual rule (China is top export
# destination). This script does not modify targets.

library(targets)
library(dplyr)
library(tidyr)
library(countrycode)
library(here)

options(scipen = 999)

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
classified_events <- tar_read(classified_events)
usa_top_countries <- tar_read(usa_top_countries)
current_panel <- tar_read(switching_panel)
current_fit <- tar_read(fect_ife)

treated_usa <- classified_events %>%
  dplyr::filter(displaced == "USA") %>%
  dplyr::pull(iso3c)

did_countries <- unique(c(treated_usa, usa_top_countries))

rank_current <- trade_data %>%
  dplyr::group_by(year, exporter_iso3) %>%
  dplyr::arrange(dplyr::desc(exports), .by_group = TRUE) %>%
  dplyr::mutate(rank = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  dplyr::filter(exporter_iso3 %in% did_countries, importer_iso3 == "CHN") %>%
  dplyr::select(iso3c = exporter_iso3, year, rank_CHN = rank)

china_top_panel <- unga_data %>%
  dplyr::filter(iso3c %in% did_countries, year >= 1990) %>%
  dplyr::select(iso3c, year, abs_distance_china) %>%
  dplyr::left_join(rank_current, by = c("iso3c", "year")) %>%
  dplyr::mutate(
    china_top = as.integer(!is.na(rank_CHN) & rank_CHN == 1),
    country_id = as.integer(as.factor(iso3c)),
    country_name = countrycode::countrycode(iso3c, "iso3c", "country.name")
  ) %>%
  dplyr::arrange(country_id, year)

china_top_panel$china_top[is.na(china_top_panel$china_top)] <- 0L
china_top_panel <- as.data.frame(china_top_panel)

validate_panel <- function(panel, label) {
  years_per_country <- panel %>%
    dplyr::count(iso3c, name = "n_years")

  tibble::tibble(
    specification = label,
    n_obs = nrow(panel),
    n_countries = dplyr::n_distinct(panel$iso3c),
    min_year = min(panel$year),
    max_year = max(panel$year),
    min_years_per_country = min(years_per_country$n_years),
    max_years_per_country = max(years_per_country$n_years),
    duplicate_country_years = sum(duplicated(panel[, c("iso3c", "year")])),
    missing_outcome = sum(is.na(panel$abs_distance_china)),
    missing_treatment = sum(is.na(panel$china_top)),
    complete_rows_for_fect = panel %>%
      dplyr::select(country_id, year, abs_distance_china, china_top) %>%
      stats::complete.cases() %>%
      sum()
  )
}

rule_check <- china_top_panel$china_top ==
  as.integer(!is.na(china_top_panel$rank_CHN) & china_top_panel$rank_CHN == 1)

if (!all(rule_check)) {
  stop("Textual-rule panel failed validation: china_top is not equivalent to rank_CHN == 1.")
}

current_keys <- current_panel %>%
  dplyr::select(iso3c, year)

china_top_keys <- china_top_panel %>%
  dplyr::select(iso3c, year)

current_not_alt <- dplyr::anti_join(current_keys, china_top_keys, by = c("iso3c", "year"))
alt_not_current <- dplyr::anti_join(china_top_keys, current_keys, by = c("iso3c", "year"))

validation <- dplyr::bind_rows(
  validate_panel(current_panel, "current_code_china_outranks_usa"),
  validate_panel(china_top_panel, "text_rule_china_rank_1")
)

if (any(validation$duplicate_country_years > 0)) {
  stop("Panel validation failed: duplicate country-years detected.")
}

if (any(validation$missing_treatment > 0)) {
  stop("Panel validation failed: missing treatment values detected.")
}

if (nrow(current_not_alt) > 0 || nrow(alt_not_current) > 0) {
  stop("Panel validation failed: current and textual-rule panels do not use the same country-year rows.")
}

summarise_panel <- function(panel, label) {
  treat_summary <- panel %>%
    dplyr::group_by(iso3c, country_name) %>%
    dplyr::summarise(
      treated_years = sum(china_top),
      switches = sum(abs(diff(china_top))),
      .groups = "drop"
    ) %>%
    dplyr::filter(treated_years > 0)

  tibble::tibble(
    specification = label,
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated_countries = dplyr::n_distinct(panel$iso3c[panel$china_top == 1]),
    n_treated_country_years = sum(panel$china_top == 1),
    n_switching = sum(treat_summary$switches > 1, na.rm = TRUE),
    n_absorbing = sum(treat_summary$switches <= 1, na.rm = TRUE),
    min_year = min(panel$year),
    max_year = max(panel$year)
  )
}

current_summary <- summarise_panel(current_panel, "current_code_china_outranks_usa")
china_top_summary <- summarise_panel(china_top_panel, "text_rule_china_rank_1")

current_s <- fect_att_summary(current_fit)

set.seed(42)
china_top_fit <- run_fect_analysis(china_top_panel, method = "ife")
china_top_s <- fect_att_summary(china_top_fit)

result <- dplyr::bind_rows(
  current_summary %>%
    dplyr::mutate(
      att = current_s$att,
      se = current_s$se,
      ci_lo = current_s$ci_lo,
      ci_hi = current_s$ci_hi,
      p = current_s$p,
      r_cv = current_s$r_cv
    ),
  china_top_summary %>%
    dplyr::mutate(
      att = china_top_s$att,
      se = china_top_s$se,
      ci_lo = china_top_s$ci_lo,
      ci_hi = china_top_s$ci_hi,
      p = china_top_s$p,
      r_cv = china_top_s$r_cv
    )
)

treated_countries <- china_top_panel %>%
  dplyr::group_by(iso3c, country_name) %>%
  dplyr::summarise(
    treated_years = sum(china_top),
    switches = sum(abs(diff(china_top))),
    first_on = ifelse(any(china_top == 1), min(year[china_top == 1]), NA_integer_),
    last_on = ifelse(any(china_top == 1), max(year[china_top == 1]), NA_integer_),
    .groups = "drop"
  ) %>%
  dplyr::filter(treated_years > 0) %>%
  dplyr::arrange(first_on, iso3c)

write.csv(result, file.path(out_dir, "china_top_rule_factor_model_comparison.csv"),
          row.names = FALSE)
write.csv(treated_countries, file.path(out_dir, "china_top_rule_treated_countries.csv"),
          row.names = FALSE)
write.csv(validation, file.path(out_dir, "china_top_rule_panel_validation.csv"),
          row.names = FALSE)

report_path <- file.path(out_dir, "2026-05-13_china_top_rule_factor_model_test.md")
sink(report_path)
cat("# Factor model diagnostic: textual treatment rule\n\n")
cat("Date: 2026-05-13\n\n")
cat("This diagnostic does not modify `_targets.R` or write to the targets store. It reads existing targets, rebuilds an alternative in-memory panel using the textual rule `rank_CHN == 1`, and compares it with the current `fect_ife` target.\n\n")
cat("## Validation\n\n")
print(validation)
cat("\nBoth panels use the same country-year rows. The textual-rule treatment was validated as exactly `rank_CHN == 1`.\n\n")
cat("## Comparison\n\n")
print(result)
cat("\n## Treated countries under textual rule\n\n")
print(treated_countries, n = nrow(treated_countries))
sink()

print(result)
cat("\nWrote:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_rule_factor_model_comparison.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_rule_treated_countries.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_rule_panel_validation.csv"), "\n", sep = "")
