#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_year <- 1990L
pre_treatment_end_year <- 2008L

trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)

top_by_year <- trade_data %>%
  dplyr::filter(year >= min_year) %>%
  dplyr::group_by(year, exporter_iso3) %>%
  dplyr::slice_max(exports, n = 1, with_ties = FALSE) %>%
  dplyr::ungroup()

trade_countries <- trade_data %>%
  dplyr::filter(year >= min_year) %>%
  dplyr::distinct(exporter_iso3)

unga_countries <- unga_data %>%
  dplyr::filter(year >= min_year) %>%
  dplyr::distinct(iso3c)

eligible_countries <- trade_countries %>%
  dplyr::inner_join(unga_countries, by = c("exporter_iso3" = "iso3c")) %>%
  dplyr::filter(exporter_iso3 != "CHN") %>%
  dplyr::mutate(
    country_name = countrycode::countrycode(
      exporter_iso3,
      "iso3c",
      "country.name",
      warn = FALSE
    )
  ) %>%
  dplyr::arrange(exporter_iso3)

usa_top_years <- top_by_year %>%
  dplyr::filter(importer_iso3 == "USA") %>%
  dplyr::group_by(exporter_iso3) %>%
  dplyr::summarise(
    n_years_usa_top = dplyr::n_distinct(year),
    first_usa_top_year = min(year),
    last_usa_top_year = max(year),
    any_pre_2009 = any(year <= pre_treatment_end_year),
    .groups = "drop"
  ) %>%
  dplyr::left_join(
    eligible_countries %>%
      dplyr::select(exporter_iso3, country_name) %>%
      dplyr::mutate(in_full_eligible_sample = TRUE),
    by = "exporter_iso3"
  ) %>%
  dplyr::mutate(
    in_full_eligible_sample = dplyr::coalesce(in_full_eligible_sample, FALSE),
    country_name = dplyr::if_else(
      is.na(country_name),
      countrycode::countrycode(
        exporter_iso3,
        "iso3c",
        "country.name",
        warn = FALSE
      ),
      country_name
    )
  ) %>%
  dplyr::arrange(exporter_iso3)

usa_top_eligible <- usa_top_years %>%
  dplyr::filter(in_full_eligible_sample)

usa_top_pre_2009_eligible <- usa_top_years %>%
  dplyr::filter(in_full_eligible_sample, any_pre_2009)

old_scope_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  usa_top_countries = usa_top_eligible$exporter_iso3,
  min_year = min_year
)

corrected_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = 2000L,
  exclude_pre_min_entry_china_top = TRUE
)

panel_summary <- dplyr::bind_rows(
  summarize_china_top_panel(old_scope_panel) %>%
    dplyr::mutate(sample_rule = "Old: USA ever top export destination"),
  summarize_china_top_panel(corrected_panel) %>%
    dplyr::mutate(sample_rule = "Corrected: all trade-UNGA countries")
) %>%
  dplyr::select(sample_rule, dplyr::everything())

sample_counts <- tibble::tibble(
  measure = c(
    "Countries observed in trade data from 1990 onward",
    "Countries observed in UNGA data from 1990 onward",
    "Countries observed in both sources, excluding China",
    "Eligible countries where USA was ever top export destination",
    "Eligible countries where USA was top export destination by 2008",
    "Eligible USA-ever-top countries with exactly one USA-top year"
  ),
  n = c(
    dplyr::n_distinct(trade_countries$exporter_iso3),
    dplyr::n_distinct(unga_countries$iso3c),
    dplyr::n_distinct(eligible_countries$exporter_iso3),
    dplyr::n_distinct(usa_top_eligible$exporter_iso3),
    dplyr::n_distinct(usa_top_pre_2009_eligible$exporter_iso3),
    usa_top_eligible %>%
      dplyr::filter(n_years_usa_top == 1L) %>%
      nrow()
  )
)

usa_top_distribution <- usa_top_eligible %>%
  dplyr::summarise(
    min_years = min(n_years_usa_top, na.rm = TRUE),
    p25_years = stats::quantile(n_years_usa_top, 0.25, na.rm = TRUE, names = FALSE),
    median_years = stats::median(n_years_usa_top, na.rm = TRUE),
    mean_years = mean(n_years_usa_top, na.rm = TRUE),
    p75_years = stats::quantile(n_years_usa_top, 0.75, na.rm = TRUE, names = FALSE),
    max_years = max(n_years_usa_top, na.rm = TRUE)
  )

readr::write_csv(
  sample_counts,
  file.path(output_dir, "china_top_sample_scope_counts.csv")
)
readr::write_csv(
  usa_top_years,
  file.path(output_dir, "china_top_usa_top_years_by_country.csv")
)
readr::write_csv(
  panel_summary,
  file.path(output_dir, "china_top_sample_scope_panel_summary.csv")
)
readr::write_csv(
  eligible_countries,
  file.path(output_dir, "china_top_corrected_eligible_countries.csv")
)

one_year_examples <- usa_top_eligible %>%
  dplyr::filter(n_years_usa_top == 1L) %>%
  dplyr::arrange(first_usa_top_year, exporter_iso3) %>%
  dplyr::select(
    exporter_iso3,
    country_name,
    first_usa_top_year,
    last_usa_top_year
  )

report_lines <- c(
  "# Audit of the cross-country China-top sample",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Interpretation",
  "",
  paste0(
    "The old criterion counted a country as in-scope if the United States was ",
    "observed as its top export destination in at least one year from ",
    min_year, " onward. This is too broad for the current China-top treatment ",
    "definition because it admits countries with only a single USA-top year and ",
    "can use post-2008 information to define the sample."
  ),
  "",
  paste0(
    "The paper-scope diagnostic no longer applies this USA-ever-top ",
    "scope condition. It includes countries observed in both the trade data ",
    "and the UNGA ideal-point data, excluding China and countries where China ",
    "was already observed as the rank-1 export destination before 2000. ",
    "Treatment is still defined year-by-year as China being the country's ",
    "rank-1 export destination after an observed prior non-China-top year, ",
    "with onset in or after 2000."
  ),
  "",
  "## Counts",
  "",
  paste0(
    "- Eligible trade-UNGA countries excluding China: ",
    dplyr::n_distinct(eligible_countries$exporter_iso3)
  ),
  paste0(
    "- Eligible countries where USA was ever top destination: ",
    dplyr::n_distinct(usa_top_eligible$exporter_iso3)
  ),
  paste0(
    "- Eligible countries where USA was top destination by 2008: ",
    dplyr::n_distinct(usa_top_pre_2009_eligible$exporter_iso3)
  ),
  paste0(
    "- Eligible USA-ever-top countries with exactly one USA-top year: ",
    nrow(one_year_examples)
  ),
  "",
  "## Distribution of USA-top years among eligible USA-ever-top countries",
  "",
  paste0(
    "- Min/p25/median/mean/p75/max: ",
    paste(round(unlist(usa_top_distribution[1, ]), 2), collapse = " / ")
  ),
  "",
  "## Countries with exactly one USA-top year",
  "",
  paste0(
    "- ",
    one_year_examples$exporter_iso3,
    " (",
    one_year_examples$country_name,
    "), ",
    one_year_examples$first_usa_top_year
  ),
  "",
  "## Output files",
  "",
  "- `quality_reports/cross_country_sample/china_top_sample_scope_counts.csv`",
  "- `quality_reports/cross_country_sample/china_top_usa_top_years_by_country.csv`",
  "- `quality_reports/cross_country_sample/china_top_sample_scope_panel_summary.csv`",
  "- `quality_reports/cross_country_sample/china_top_corrected_eligible_countries.csv`"
)

writeLines(
  report_lines,
  con = file.path(output_dir, "china_top_sample_scope_audit.md"),
  useBytes = TRUE
)

print(sample_counts)
cat("\nPanel summaries:\n")
print(panel_summary)
cat("\nAudit report written to: ", output_dir, "\n", sep = "")
