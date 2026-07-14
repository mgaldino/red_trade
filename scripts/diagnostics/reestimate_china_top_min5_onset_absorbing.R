#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

parse_nboots <- function(args, default = 1000L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    return(default)
  }
  value <- as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
  if (is.na(value) || value <= 0L) {
    stop("`--nboots` must be a positive integer.", call. = FALSE)
  }
  value
}

prepare_min5_onset_absorbing_sample <- function(panel,
                                                min_duration_years = 5L,
                                                min_entry_year = 2000L,
                                                require_balanced = TRUE) {
  required_cols <- c("iso3c", "year", "abs_distance_china", "china_top")
  missing_cols <- setdiff(required_cols, names(panel))
  if (length(missing_cols) > 0L) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "),
         call. = FALSE)
  }

  optional_cols <- intersect(
    c("country_id", "country_name", "top_partner", "china_is_top",
      "rank_CHN", "rank_USA"),
    names(panel)
  )

  base_panel <- panel |>
    dplyr::select(dplyr::all_of(unique(c(required_cols, optional_cols)))) |>
    dplyr::filter(dplyr::if_all(dplyr::all_of(required_cols), ~ !is.na(.x))) |>
    dplyr::arrange(iso3c, year)

  if ("top_partner" %in% names(base_panel)) {
    base_panel <- base_panel |>
      dplyr::filter(!is.na(top_partner)) |>
      dplyr::mutate(china_top_observed = top_partner == "CHN")
  } else if ("china_is_top" %in% names(base_panel)) {
    base_panel <- base_panel |>
      dplyr::mutate(china_top_observed = dplyr::coalesce(china_is_top, FALSE))
  } else {
    base_panel <- base_panel |>
      dplyr::mutate(china_top_observed = china_top == 1L)
  }

  if (!"country_name" %in% names(base_panel)) {
    base_panel <- base_panel |>
      dplyr::mutate(
        country_name = countrycode::countrycode(
          iso3c,
          "iso3c",
          "country.name",
          warn = FALSE
        )
      )
  }

  period_panel <- base_panel |>
    dplyr::group_by(iso3c) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      china_top_eligible = as.integer(china_top == 1L),
      eligible_period_start = china_top_eligible == 1L &
        dplyr::lag(china_top_eligible, default = 0L) == 0L,
      eligible_period_id_raw = cumsum(eligible_period_start),
      eligible_period_id = dplyr::if_else(
        china_top_eligible == 1L,
        eligible_period_id_raw,
        NA_integer_
      )
    ) |>
    dplyr::ungroup()

  period_summary <- period_panel |>
    dplyr::filter(china_top_eligible == 1L, !is.na(eligible_period_id)) |>
    dplyr::group_by(iso3c, country_name, eligible_period_id) |>
    dplyr::summarise(
      period_entry_year = min(year, na.rm = TRUE),
      period_exit_year = max(year, na.rm = TRUE),
      duration_years = dplyr::n_distinct(year),
      calendar_span_years = period_exit_year - period_entry_year + 1L,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      qualifies_min5 = period_entry_year >= min_entry_year &
        duration_years >= min_duration_years
    )

  unit_summary <- period_panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      ever_china_top_observed = any(china_top_observed, na.rm = TRUE),
      first_observed_year = min(year, na.rm = TRUE),
      last_observed_year = max(year, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::left_join(
      period_summary |>
        dplyr::group_by(iso3c) |>
        dplyr::summarise(
          eligible_periods = dplyr::n(),
          qualifying_periods = sum(qualifies_min5, na.rm = TRUE),
          first_eligible_entry = ifelse(
            dplyr::n() > 0L,
            min(period_entry_year, na.rm = TRUE),
            NA_integer_
          ),
          first_qualifying_entry = ifelse(
            any(qualifies_min5, na.rm = TRUE),
            min(period_entry_year[qualifies_min5], na.rm = TRUE),
            NA_integer_
          ),
          max_eligible_duration = ifelse(
            dplyr::n() > 0L,
            max(duration_years, na.rm = TRUE),
            0L
          ),
          total_eligible_china_top_years = sum(duration_years, na.rm = TRUE),
          total_qualifying_china_top_years = sum(
            duration_years[qualifies_min5],
            na.rm = TRUE
          ),
          .groups = "drop"
        ),
      by = "iso3c"
    ) |>
    dplyr::mutate(
      dplyr::across(
        c(eligible_periods, qualifying_periods, max_eligible_duration,
          total_eligible_china_top_years, total_qualifying_china_top_years),
        ~ dplyr::coalesce(.x, 0)
      ),
      cs_role_min5_onset = dplyr::case_when(
        qualifying_periods > 0L ~ "treated_min5_onset",
        !ever_china_top_observed ~ "never_treated",
        TRUE ~ "excluded_short_or_ineligible"
      ),
      first_treat = dplyr::if_else(
        cs_role_min5_onset == "treated_min5_onset",
        as.numeric(first_qualifying_entry),
        0
      )
    )

  analysis_panel <- period_panel |>
    dplyr::left_join(
      unit_summary |>
        dplyr::select(
          iso3c,
          cs_role_min5_onset,
          first_treat,
          first_qualifying_entry,
          max_eligible_duration,
          total_eligible_china_top_years,
          total_qualifying_china_top_years,
          qualifying_periods,
          ever_china_top_observed
        ),
      by = "iso3c"
    ) |>
    dplyr::filter(cs_role_min5_onset %in% c("treated_min5_onset", "never_treated")) |>
    dplyr::mutate(
      china_top = as.integer(
        cs_role_min5_onset == "treated_min5_onset" &
          year >= first_treat
      )
    ) |>
    dplyr::select(-china_top_eligible, -eligible_period_start,
                  -eligible_period_id_raw)

  if (require_balanced) {
    max_years <- max(table(analysis_panel$iso3c))
    balanced_iso <- analysis_panel |>
      dplyr::group_by(iso3c) |>
      dplyr::summarise(n_years = dplyr::n(), .groups = "drop") |>
      dplyr::filter(n_years == max_years) |>
      dplyr::pull(iso3c)

    analysis_panel <- analysis_panel |>
      dplyr::filter(iso3c %in% balanced_iso)
  }

  panel_max <- max(analysis_panel$year, na.rm = TRUE)
  estimable_treated <- analysis_panel |>
    dplyr::filter(first_treat > 0, first_treat < panel_max, china_top == 1L) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c)

  analysis_panel <- analysis_panel |>
    dplyr::filter(first_treat == 0 | iso3c %in% estimable_treated) |>
    dplyr::mutate(
      country_id = as.integer(as.factor(iso3c)),
      id = country_id
    ) |>
    dplyr::arrange(country_id, year) |>
    as.data.frame()

  list(
    panel = analysis_panel,
    unit_summary = unit_summary,
    period_summary = period_summary
  )
}

comparison_counts <- function(panel, label) {
  unit_status <- panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      entries = sum(
        china_top == 1L & dplyr::lag(china_top, default = 0L) == 0L,
        na.rm = TRUE
      ),
      exits = sum(
        china_top == 0L & dplyr::lag(china_top, default = 0L) == 1L,
        na.rm = TRUE
      ),
      first_treat_year = ifelse(
        ever_treated,
        min(year[china_top == 1L], na.rm = TRUE),
        NA_integer_
      ),
      .groups = "drop"
    )

  tibble::tibble(
    sample = label,
    n_obs = nrow(panel),
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated = sum(unit_status$ever_treated, na.rm = TRUE),
    n_control = sum(!unit_status$ever_treated, na.rm = TRUE),
    n_treated_country_years = sum(panel$china_top == 1L, na.rm = TRUE),
    n_entries = sum(unit_status$entries, na.rm = TRUE),
    n_exits = sum(unit_status$exits, na.rm = TRUE),
    panel_min = min(panel$year, na.rm = TRUE),
    panel_max = max(panel$year, na.rm = TRUE)
  )
}

fit_model <- function(panel, nboots) {
  fit <- run_fect_analysis(
    panel,
    method = "ife",
    nboots = nboots,
    fml = abs_distance_china ~ china_top
  )
  summarize_fect_model(fit, panel, fml = abs_distance_china ~ china_top)
}

if (!identical(Sys.getenv("CHINA_TOP_MIN5_ONSET_SOURCE_ONLY"), "1")) {
args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args, default = 1000L)
min_duration_years <- 5L
output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Loading existing target objects. This script does not run tar_make().")
china_top_panel <- targets::tar_read(china_top_panel)
china_top_absorbing_sample <- targets::tar_read(china_top_absorbing_sample)
main_summary <- targets::tar_read(fect_ife_china_top_summary)

message("Building minimum-", min_duration_years,
        "-year onset-absorbing treatment sample with never-treated controls.")
min5 <- prepare_min5_onset_absorbing_sample(
  china_top_panel,
  min_duration_years = min_duration_years,
  min_entry_year = 2000L,
  require_balanced = TRUE
)
min5_panel <- min5$panel

message("Estimating fect IFE with nboots = ", nboots, ".")
timing <- system.time({
  min5_summary <- fit_model(min5_panel, nboots = nboots)
})

model_results <- dplyr::bind_rows(
  tibble::as_tibble(main_summary) |>
    dplyr::mutate(
      sample = "current_absorbing_targets_10000_boot",
      nboots = 10000L,
      elapsed_seconds = NA_real_,
      .before = att
    ),
  tibble::as_tibble(min5_summary) |>
    dplyr::mutate(
      sample = "minimum_5_year_onset_absorbing_1000_boot",
      nboots = nboots,
      elapsed_seconds = as.numeric(timing[["elapsed"]]),
      .before = att
    )
) |>
  dplyr::select(
    sample, nboots, att, se, ci_lo, ci_hi, p, r_cv, att_rel_pct,
    att_sd_units, n_obs, n_countries, n_treated, n_control,
    n_treated_country_years, n_entries, n_exits, panel_min, panel_max,
    pre_treated_mean, outcome_sd, elapsed_seconds
  )

current_treated <- china_top_absorbing_sample |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    current_absorbing_treated = any(china_top == 1L, na.rm = TRUE),
    current_first_treat = ifelse(
      current_absorbing_treated,
      min(year[china_top == 1L], na.rm = TRUE),
      NA_integer_
    ),
    current_treated_years = sum(china_top == 1L, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::filter(current_absorbing_treated)

min5_treated <- min5_panel |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    min5_treated = any(china_top == 1L, na.rm = TRUE),
    min5_first_treat = ifelse(
      min5_treated,
      min(year[china_top == 1L], na.rm = TRUE),
      NA_integer_
    ),
    min5_treated_years = sum(china_top == 1L, na.rm = TRUE),
    min5_entries = sum(
      china_top == 1L & dplyr::lag(china_top, default = 0L) == 0L,
      na.rm = TRUE
    ),
    min5_exits = sum(
      china_top == 0L & dplyr::lag(china_top, default = 0L) == 1L,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  dplyr::filter(min5_treated)

country_comparison <- dplyr::full_join(
  current_treated,
  min5_treated,
  by = c("iso3c", "country_name")
) |>
  dplyr::mutate(
    current_absorbing_treated = dplyr::coalesce(
      current_absorbing_treated,
      FALSE
    ),
    min5_treated = dplyr::coalesce(min5_treated, FALSE),
    sample_change = dplyr::case_when(
      current_absorbing_treated & min5_treated ~ "kept_from_current",
      !current_absorbing_treated & min5_treated ~ "added_by_min5_onset",
      current_absorbing_treated & !min5_treated ~ "dropped_by_min5_onset",
      TRUE ~ "neither"
    )
  ) |>
  dplyr::arrange(sample_change, iso3c)

sample_counts <- dplyr::bind_rows(
  comparison_counts(china_top_absorbing_sample, "current_absorbing_targets"),
  comparison_counts(min5_panel, "minimum_5_year_onset_absorbing")
)

role_counts <- min5$unit_summary |>
  dplyr::count(cs_role_min5_onset, name = "n_countries") |>
  dplyr::arrange(cs_role_min5_onset)

readr::write_csv(
  model_results,
  file.path(output_dir, "china_top_min5_onset_absorbing_model_results.csv")
)
readr::write_csv(
  country_comparison,
  file.path(output_dir, "china_top_min5_onset_absorbing_country_comparison.csv")
)
readr::write_csv(
  sample_counts,
  file.path(output_dir, "china_top_min5_onset_absorbing_sample_counts.csv")
)
readr::write_csv(
  role_counts,
  file.path(output_dir, "china_top_min5_onset_absorbing_role_counts.csv")
)
readr::write_csv(
  min5$unit_summary,
  file.path(output_dir, "china_top_min5_onset_absorbing_unit_summary.csv")
)
readr::write_csv(
  min5$period_summary,
  file.path(output_dir, "china_top_min5_onset_absorbing_period_summary.csv")
)
writeLines(
  capture.output(sessionInfo()),
  con = file.path(output_dir, "china_top_min5_onset_absorbing_session_info.txt"),
  useBytes = TRUE
)

fmt <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", formatC(x, format = "f", digits = digits))
}

added <- country_comparison |>
  dplyr::filter(sample_change == "added_by_min5_onset") |>
  dplyr::mutate(line = paste0(
    "- ", iso3c, " (", country_name, "), entry ", min5_first_treat,
    ", post years ", min5_treated_years
  )) |>
  dplyr::pull(line)
kept <- country_comparison |>
  dplyr::filter(sample_change == "kept_from_current") |>
  dplyr::mutate(line = paste0("- ", iso3c, " (", country_name, ")")) |>
  dplyr::pull(line)
dropped <- country_comparison |>
  dplyr::filter(sample_change == "dropped_by_min5_onset") |>
  dplyr::mutate(line = paste0("- ", iso3c, " (", country_name, ")")) |>
  dplyr::pull(line)

if (length(added) == 0L) added <- "- None."
if (length(kept) == 0L) kept <- "- None."
if (length(dropped) == 0L) dropped <- "- None."

min5_row <- model_results |>
  dplyr::filter(sample == "minimum_5_year_onset_absorbing_1000_boot") |>
  dplyr::slice_head(n = 1)
main_row <- model_results |>
  dplyr::filter(sample == "current_absorbing_targets_10000_boot") |>
  dplyr::slice_head(n = 1)

report_lines <- c(
  "# China top treatment: minimum 5-year onset-absorbing diagnostic",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Bootstrap replications for alternative specification: ", nboots),
  "",
  "## Coding Rule",
  "",
  paste0(
    "A country is eligible for treatment if China enters as the rank-1 export ",
    "destination in or after 2000 after an observed prior non-China-top year ",
    "and that China-top episode lasts at least ", min_duration_years,
    " observed country-years. The estimated treatment is an absorbing onset ",
    "indicator: once a country has a qualifying durable China-top entry, it ",
    "remains treated for all subsequent years. Controls are restricted to ",
    "countries where China is never observed as rank 1. Countries with only ",
    "shorter China-top episodes are excluded rather than recoded as controls."
  ),
  "",
  "## Model Results",
  "",
  paste0(
    "- Current absorbing target sample: ATT = ", fmt(main_row$att),
    ", SE = ", fmt(main_row$se),
    ", 95% CI [", fmt(main_row$ci_lo), ", ", fmt(main_row$ci_hi), "]",
    ", p = ", fmt(main_row$p),
    ", r* = ", main_row$r_cv,
    ", treated/control = ", main_row$n_treated, "/", main_row$n_control,
    ", treated country-years = ", main_row$n_treated_country_years, "."
  ),
  paste0(
    "- Minimum 5-year onset-absorbing sample: ATT = ", fmt(min5_row$att),
    ", SE = ", fmt(min5_row$se),
    ", 95% CI [", fmt(min5_row$ci_lo), ", ", fmt(min5_row$ci_hi), "]",
    ", p = ", fmt(min5_row$p),
    ", r* = ", min5_row$r_cv,
    ", treated/control = ", min5_row$n_treated, "/", min5_row$n_control,
    ", treated country-years = ", min5_row$n_treated_country_years, "."
  ),
  "",
  "## Treated Country Changes",
  "",
  "### Kept from current absorbing sample",
  "",
  kept,
  "",
  "### Added by minimum-5-year onset rule",
  "",
  added,
  "",
  "### Dropped from current absorbing sample",
  "",
  dropped,
  "",
  "## Output Files",
  "",
  "- `quality_reports/cross_country_sample/china_top_min5_onset_absorbing_model_results.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_onset_absorbing_country_comparison.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_onset_absorbing_sample_counts.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_onset_absorbing_role_counts.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_onset_absorbing_unit_summary.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_onset_absorbing_period_summary.csv`"
)

writeLines(
  report_lines,
  con = file.path(output_dir, "china_top_min5_onset_absorbing_report.md"),
  useBytes = TRUE
)

print(model_results)
cat("\nCountry changes:\n")
print(country_comparison)
cat("\nReport written to: ",
    file.path(output_dir, "china_top_min5_onset_absorbing_report.md"),
    "\n",
    sep = "")
}
