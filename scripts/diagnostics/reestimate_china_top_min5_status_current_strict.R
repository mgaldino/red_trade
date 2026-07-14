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

build_min5_period_data <- function(panel,
                                   min_duration_years = 5L,
                                   min_entry_year = 2000L) {
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

  qualifying_periods <- period_summary |>
    dplyr::filter(qualifies_min5) |>
    dplyr::select(iso3c, eligible_period_id)

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
      cs_role_min5 = dplyr::case_when(
        qualifying_periods > 0L ~ "treated_min5",
        !ever_china_top_observed ~ "never_treated",
        TRUE ~ "excluded_short_or_ineligible"
      ),
      first_treat = dplyr::if_else(
        cs_role_min5 == "treated_min5",
        as.numeric(first_qualifying_entry),
        0
      )
    )

  list(
    period_panel = period_panel,
    period_summary = period_summary,
    qualifying_periods = qualifying_periods,
    unit_summary = unit_summary
  )
}

make_status_current_panel <- function(period_data,
                                      require_balanced = TRUE,
                                      strict_never_control = FALSE,
                                      clean_single_spell = FALSE) {
  analysis_panel <- period_data$period_panel |>
    dplyr::left_join(
      period_data$qualifying_periods |>
        dplyr::mutate(qualifying_period = TRUE),
      by = c("iso3c", "eligible_period_id")
    ) |>
    dplyr::mutate(
      qualifying_period = dplyr::coalesce(qualifying_period, FALSE),
      china_top = as.integer(qualifying_period)
    ) |>
    dplyr::left_join(
      period_data$unit_summary |>
        dplyr::select(
          iso3c,
          cs_role_min5,
          first_treat,
          first_qualifying_entry,
          eligible_periods,
          max_eligible_duration,
          total_eligible_china_top_years,
          total_qualifying_china_top_years,
          qualifying_periods,
          ever_china_top_observed
        ),
      by = "iso3c"
    ) |>
    dplyr::filter(cs_role_min5 %in% c("treated_min5", "never_treated"))

  if (clean_single_spell) {
    analysis_panel <- analysis_panel |>
      dplyr::filter(
        cs_role_min5 == "never_treated" |
          (
            cs_role_min5 == "treated_min5" &
              eligible_periods == 1L &
              qualifying_periods == 1L
          )
      )
  }

  if (strict_never_control) {
    # For treated countries, retain only clean pre-treatment non-China-top years
    # and active qualifying China-top years. This removes post-exit off-treatment
    # years and short China-top episodes from the estimating risk set.
    analysis_panel <- analysis_panel |>
      dplyr::filter(
        cs_role_min5 == "never_treated" |
          (
            cs_role_min5 == "treated_min5" &
              (
                qualifying_period |
                  (year < first_treat & china_top_eligible == 0L)
              )
          )
      )

    # Match fect's own identification screen so reported sample counts do not
    # include units that fect would drop internally.
    analysis_panel <- analysis_panel |>
      dplyr::group_by(iso3c) |>
      dplyr::filter(sum(china_top == 0L, na.rm = TRUE) >= 5L) |>
      dplyr::ungroup()
  }

  analysis_panel <- analysis_panel |>
    dplyr::select(-china_top_eligible, -eligible_period_start,
                  -eligible_period_id_raw, -qualifying_period)

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

  analysis_panel |>
    dplyr::filter(first_treat == 0 | iso3c %in% estimable_treated) |>
    dplyr::mutate(
      country_id = as.integer(as.factor(iso3c)),
      id = country_id
    ) |>
    dplyr::arrange(country_id, year) |>
    as.data.frame()
}

comparison_counts <- function(panel, label) {
  unit_status <- panel |>
    dplyr::arrange(iso3c, year) |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      untreated_years = sum(china_top == 0L, na.rm = TRUE),
      entries = sum(
        china_top == 1L &
          (is.na(dplyr::lag(china_top)) | dplyr::lag(china_top) == 0L),
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
    n_untreated_country_years = sum(panel$china_top == 0L, na.rm = TRUE),
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

panel_unit_summary <- function(panel, label) {
  panel |>
    dplyr::group_by(iso3c, country_name, cs_role_min5) |>
    dplyr::summarise(
      sample = label,
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      untreated_years = sum(china_top == 0L, na.rm = TRUE),
      first_treat = ifelse(
        any(china_top == 1L, na.rm = TRUE),
        min(year[china_top == 1L], na.rm = TRUE),
        NA_integer_
      ),
      first_year_in_panel = min(year, na.rm = TRUE),
      last_year_in_panel = max(year, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::relocate(sample)
}

if (!identical(Sys.getenv("CHINA_TOP_STATUS_CURRENT_SOURCE_ONLY"), "1")) {
args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args, default = 1000L)
output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Loading existing target objects. This script does not run tar_make().")
china_top_panel <- targets::tar_read(china_top_panel)
china_top_absorbing_sample <- targets::tar_read(china_top_absorbing_sample)
main_summary <- targets::tar_read(fect_ife_china_top_summary)

period_data <- build_min5_period_data(
  china_top_panel,
  min_duration_years = 5L,
  min_entry_year = 2000L
)

status_panel <- make_status_current_panel(
  period_data,
  require_balanced = TRUE,
  strict_never_control = FALSE
)

strict_panel <- make_status_current_panel(
  period_data,
  require_balanced = FALSE,
  strict_never_control = TRUE
)

clean_panel <- make_status_current_panel(
  period_data,
  require_balanced = FALSE,
  strict_never_control = TRUE,
  clean_single_spell = TRUE
)

message("Estimating status-current model with nboots = ", nboots, ".")
timing_status <- system.time({
  status_summary <- fit_model(status_panel, nboots = nboots)
})

message("Estimating strict never-control/censored model with nboots = ",
        nboots, ".")
timing_strict <- system.time({
  strict_summary <- fit_model(strict_panel, nboots = nboots)
})

message("Estimating clean single-spell risk-set model with nboots = ",
        nboots, ".")
timing_clean <- system.time({
  clean_summary <- fit_model(clean_panel, nboots = nboots)
})

model_results <- dplyr::bind_rows(
  tibble::as_tibble(main_summary) |>
    dplyr::mutate(
      sample = "current_absorbing_targets_10000_boot",
      nboots = 10000L,
      elapsed_seconds = NA_real_
    ),
  tibble::as_tibble(status_summary) |>
    dplyr::mutate(
      sample = "minimum_5_year_status_current_balanced_1000_boot",
      nboots = nboots,
      elapsed_seconds = as.numeric(timing_status["elapsed"])
    ),
  tibble::as_tibble(strict_summary) |>
    dplyr::mutate(
      sample = "minimum_5_year_status_current_strict_1000_boot",
      nboots = nboots,
      elapsed_seconds = as.numeric(timing_strict["elapsed"])
    ),
  tibble::as_tibble(clean_summary) |>
    dplyr::mutate(
      sample = "minimum_5_year_status_current_clean_single_spell_1000_boot",
      nboots = nboots,
      elapsed_seconds = as.numeric(timing_clean["elapsed"])
    )
) |>
  dplyr::relocate(sample, nboots, elapsed_seconds)

sample_counts <- dplyr::bind_rows(
  comparison_counts(china_top_absorbing_sample, "current_absorbing_targets"),
  comparison_counts(status_panel, "minimum_5_year_status_current_balanced"),
  comparison_counts(strict_panel, "minimum_5_year_status_current_strict"),
  comparison_counts(clean_panel,
                    "minimum_5_year_status_current_clean_single_spell")
)

unit_summary <- dplyr::bind_rows(
  panel_unit_summary(status_panel,
                     "minimum_5_year_status_current_balanced"),
  panel_unit_summary(strict_panel,
                     "minimum_5_year_status_current_strict"),
  panel_unit_summary(clean_panel,
                     "minimum_5_year_status_current_clean_single_spell")
)

readr::write_csv(
  model_results,
  file.path(output_dir,
            "china_top_min5_status_current_strict_model_results.csv")
)
readr::write_csv(
  sample_counts,
  file.path(output_dir,
            "china_top_min5_status_current_strict_sample_counts.csv")
)
readr::write_csv(
  unit_summary,
  file.path(output_dir,
            "china_top_min5_status_current_strict_unit_summary.csv")
)
readr::write_csv(
  period_data$period_summary,
  file.path(output_dir,
            "china_top_min5_status_current_strict_period_summary.csv")
)
writeLines(
  capture.output(sessionInfo()),
  con = file.path(output_dir,
                  "china_top_min5_status_current_strict_session_info.txt")
)

fmt <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

status_row <- model_results |>
  dplyr::filter(sample == "minimum_5_year_status_current_balanced_1000_boot") |>
  dplyr::slice(1)

strict_row <- model_results |>
  dplyr::filter(sample == "minimum_5_year_status_current_strict_1000_boot") |>
  dplyr::slice(1)

clean_row <- model_results |>
  dplyr::filter(
    sample == "minimum_5_year_status_current_clean_single_spell_1000_boot"
  ) |>
  dplyr::slice(1)

main_row <- model_results |>
  dplyr::filter(sample == "current_absorbing_targets_10000_boot") |>
  dplyr::slice(1)

report_lines <- c(
  "# China top treatment: status-current minimum 5-year diagnostic",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Bootstrap replications for alternative specifications: ", nboots),
  "",
  "## Coding Rule",
  "",
  paste(
    "The status-current treatment equals 1 only in observed country-years",
    "where China is the rank-1 export destination and that China-top period",
    "lasts at least 5 observed country-years. It is not absorbing: when",
    "China is no longer rank 1, the treatment indicator is not 1."
  ),
  "",
  paste(
    "The strict variant additionally removes post-exit off-treatment years",
    "and short/nonqualifying China-top years for treated countries. This makes",
    "the comparison set closer to never-treated countries plus clean",
    "pre-treatment years for eventually treated countries."
  ),
  "",
  paste(
    "The clean single-spell variant keeps only treated countries with exactly",
    "one observed China-top period and requires that this period qualifies under",
    "the 5-year rule. Post-exit off-status years remain outside the comparison",
    "risk set."
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
    "."
  ),
  paste0(
    "- Minimum 5-year status-current balanced sample: ATT = ",
    fmt(status_row$att),
    ", SE = ", fmt(status_row$se),
    ", 95% CI [", fmt(status_row$ci_lo), ", ", fmt(status_row$ci_hi), "]",
    ", p = ", fmt(status_row$p),
    ", r* = ", status_row$r_cv,
    ", treated/control = ", status_row$n_treated, "/", status_row$n_control,
    "."
  ),
  paste0(
    "- Minimum 5-year strict status-current sample: ATT = ",
    fmt(strict_row$att),
    ", SE = ", fmt(strict_row$se),
    ", 95% CI [", fmt(strict_row$ci_lo), ", ", fmt(strict_row$ci_hi), "]",
    ", p = ", fmt(strict_row$p),
    ", r* = ", strict_row$r_cv,
    ", treated/control = ", strict_row$n_treated, "/", strict_row$n_control,
    "."
  ),
  paste0(
    "- Minimum 5-year clean single-spell risk-set sample: ATT = ",
    fmt(clean_row$att),
    ", SE = ", fmt(clean_row$se),
    ", 95% CI [", fmt(clean_row$ci_lo), ", ", fmt(clean_row$ci_hi), "]",
    ", p = ", fmt(clean_row$p),
    ", r* = ", clean_row$r_cv,
    ", treated/control = ", clean_row$n_treated, "/", clean_row$n_control,
    "."
  ),
  "",
  "## Output Files",
  "",
  paste0(
    "- `", output_dir,
    "/china_top_min5_status_current_strict_model_results.csv`"
  ),
  paste0(
    "- `", output_dir,
    "/china_top_min5_status_current_strict_sample_counts.csv`"
  ),
  paste0(
    "- `", output_dir,
    "/china_top_min5_status_current_strict_unit_summary.csv`"
  ),
  paste0(
    "- `", output_dir,
    "/china_top_min5_status_current_strict_period_summary.csv`"
  )
)

writeLines(
  report_lines,
  con = file.path(output_dir,
                  "china_top_min5_status_current_strict_report.md"),
  useBytes = TRUE
)

message("Wrote report to ",
        file.path(output_dir,
                  "china_top_min5_status_current_strict_report.md"))
}
