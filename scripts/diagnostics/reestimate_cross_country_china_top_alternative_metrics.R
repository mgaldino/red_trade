#!/usr/bin/env Rscript

# Diagnostic only. This script reads existing targets objects read-only but does
# not modify or run the targets pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(countrycode)
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(rmarkdown)
  library(tibble)
  library(tidyr)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

source("scripts/functions.R")

run_date <- as.Date("2026-05-20")
rank_window_start <- 2005L
rank_window_end <- 2022L
cutoff_year <- 2010L
model_window_start <- 2005L

parse_args <- function(args) {
  get_arg <- function(prefix, default) {
    hit <- args[startsWith(args, prefix)]
    if (length(hit) == 0L) {
      return(default)
    }
    sub(prefix, "", hit[[1]], fixed = TRUE)
  }

  list(
    nboots = as.integer(get_arg("--nboots=", "500")),
    skip_pdf = tolower(get_arg("--skip-pdf=", "false")) %in% c("1", "true", "yes"),
    run_focus_influence =
      tolower(get_arg("--focus-influence=", "true")) %in% c("1", "true", "yes")
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

if (is.na(args$nboots) || args$nboots < 50L) {
  stop("--nboots must be an integer >= 50.", call. = FALSE)
}

processed_dir <- file.path(
  "data", "processed", "diagnostics", "china_top_alternative_cross_country"
)
report_dir <- file.path("quality_reports", "china_top_alternative_cross_country")
figure_dir <- file.path(report_dir, "figures")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

latest_file <- function(dir, pattern) {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0L) {
    stop("No file matching pattern found in ", dir, ": ", pattern, call. = FALSE)
  }
  files[which.max(file.info(files)$mtime)]
}

dated_file <- function(dir, filename) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) {
    stop("Required dated input file not found: ", path, call. = FALSE)
  }
  path
}

read_target_object <- function(name) {
  path <- file.path("_targets", "objects", name)
  if (!file.exists(path)) {
    stop("Required read-only targets object not found: ", path, call. = FALSE)
  }
  readRDS(path)
}

fmt <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

format_p <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "NA",
    x < 0.001 ~ "<0.001",
    TRUE ~ sprintf("%.3f", x)
  )
}

ensure_columns <- function(data, cols, fill = 0L) {
  missing_cols <- setdiff(cols, names(data))
  if (length(missing_cols) > 0L) {
    for (col in missing_cols) {
      data[[col]] <- fill
    }
  }
  data
}

abort_if_duplicates <- function(data, keys, label) {
  duplicates <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(duplicates) > 0L) {
    example <- duplicates |>
      utils::head(5L) |>
      capture.output() |>
      paste(collapse = "\n")

    stop(
      "Duplicate keys detected in ", label, " for keys: ",
      paste(keys, collapse = ", "), "\nExamples:\n", example,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

abort_if_row_count_changed <- function(data, expected_n, label) {
  actual_n <- nrow(data)
  if (!identical(actual_n, expected_n)) {
    stop(
      label, " changed the expected row count from ", expected_n,
      " to ", actual_n, ". Check join keys before proceeding.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

model_status_label <- function(status) {
  dplyr::recode(
    status,
    clean_risk_set = "Clean risk set",
    left_censored_as_already_treated =
      "Censurados à esquerda como já tratados (descritivo)",
    restricted_post_2005_cohort = "Coorte pós-2005 observada",
    cutoff_not_top_through_2010 = "Restrição: não China #1 até 2010",
    .default = status
  )
}

metric_label <- function(metric) {
  dplyr::recode(
    metric,
    goods_exports_rank = "Bens: exportações",
    goods_services_exports_rank = "Bens + serviços: exportações",
    goods_services_two_way_rank = "Bens + serviços: two-way",
    .default = metric
  )
}

rank_file <- dated_file(
  file.path("data", "processed", "diagnostics", "china_top_goods_services"),
  paste0("china_top_goods_services_rank_long_", run_date, ".csv")
)

onsets_file <- dated_file(
  file.path("data", "processed", "diagnostics", "china_top_goods_services"),
  paste0("china_top_goods_services_onsets_comparison_", run_date, ".csv")
)

public_metric_file <- dated_file(
  file.path("data", "processed", "diagnostics", "china_top_goods_services"),
  paste0("china_top_goods_two_way_public_metric_check_aus_bra_", run_date, ".csv")
)

message("Reading read-only target objects and BaTIS diagnostic CSVs.")
unga_data <- read_target_object("unga_data")
covariates_panel <- read_target_object("covariates_panel")
paper_main_summary <- read_target_object("fect_ife_china_top_cov_summary")
paper_nocov_summary <- read_target_object("fect_ife_china_top_summary")
paper_main_panel <- read_target_object("china_top_fect_cov_data")
paper_full_panel <- read_target_object("china_top_panel")

rank_long <- readr::read_csv(rank_file, show_col_types = FALSE)
onsets_comparison <- readr::read_csv(onsets_file, show_col_types = FALSE)
public_metric <- readr::read_csv(public_metric_file, show_col_types = FALSE)

target_object_names <- c(
  "unga_data",
  "covariates_panel",
  "fect_ife_china_top_cov_summary",
  "fect_ife_china_top_summary",
  "china_top_fect_cov_data",
  "china_top_panel"
)
target_object_paths <- file.path("_targets", "objects", target_object_names)
target_input_manifest <- tibble::tibble(
  object = target_object_names,
  path = target_object_paths,
  md5 = unname(tools::md5sum(target_object_paths))
)

metrics_to_model <- c(
  "goods_exports_rank",
  "goods_services_exports_rank",
  "goods_services_two_way_rank"
)

rank_long_metrics <- rank_long |>
  dplyr::filter(metric %in% metrics_to_model)

abort_if_duplicates(
  rank_long_metrics,
  c("metric", "iso3c", "year", "partner_iso3"),
  "rank_long"
)

abort_if_duplicates(
  rank_long_metrics |>
    dplyr::filter(partner_iso3 == "CHN"),
  c("metric", "iso3c", "year"),
  "rank_long China rows"
)

model_window_end <- min(
  max(covariates_panel$year, na.rm = TRUE),
  max(unga_data$year, na.rm = TRUE),
  rank_window_end
)

panel_countries <- paper_full_panel |>
  tibble::as_tibble() |>
  dplyr::filter(!is.na(iso3c), iso3c != "CHN") |>
  dplyr::distinct(iso3c, country_name) |>
  dplyr::mutate(
    country_name = dplyr::coalesce(
      country_name,
      countrycode::countrycode(iso3c, "iso3c", "country.name", warn = FALSE)
    )
  ) |>
  dplyr::arrange(iso3c)

country_year_grid <- tidyr::expand_grid(
  metric = metrics_to_model,
  panel_countries,
  year = rank_window_start:rank_window_end
)

rank_country_year <- rank_long_metrics |>
  dplyr::group_by(metric, iso3c, country_name, year) |>
  dplyr::summarise(
    top_partner = dplyr::first(top_partner_iso3),
    top_partner_name = dplyr::first(top_partner_name),
    top_value_musd = dplyr::first(top_value_musd),
    n_ranked_partners = dplyr::n_distinct(partner_iso3),
    china_rank = {
      value <- partner_rank[partner_iso3 == "CHN"]
      if (length(value) == 0L) NA_integer_ else as.integer(value[[1]])
    },
    china_value_musd = {
      value <- value_musd[partner_iso3 == "CHN"]
      if (length(value) == 0L) NA_real_ else as.numeric(value[[1]])
    },
    .groups = "drop"
  ) |>
  dplyr::mutate(
    rank_observed = TRUE,
    china_is_top_observed = !is.na(china_rank) & china_rank == 1L
  )

abort_if_duplicates(
  rank_country_year,
  c("metric", "iso3c", "year"),
  "rank_country_year"
)

rank_panel <- country_year_grid |>
  dplyr::left_join(
    rank_country_year |>
      dplyr::select(
        metric, iso3c, year, top_partner, top_partner_name, top_value_musd,
        n_ranked_partners, china_rank, china_value_musd, rank_observed,
        china_is_top_observed
      ),
    by = c("metric", "iso3c", "year")
  ) |>
  dplyr::mutate(
    rank_observed = dplyr::coalesce(rank_observed, FALSE),
    china_is_top_observed = dplyr::if_else(
      rank_observed,
      dplyr::coalesce(china_is_top_observed, FALSE),
      NA
    )
  ) |>
  dplyr::left_join(
    unga_data |>
      dplyr::select(iso3c, year, abs_distance_china),
    by = c("iso3c", "year")
  ) |>
  dplyr::left_join(
    covariates_panel |>
      dplyr::select(iso3c, year, log_gdp_pc, free_press),
    by = c("iso3c", "year")
  )

abort_if_row_count_changed(
  rank_panel,
  nrow(country_year_grid),
  "rank_panel construction"
)

make_metric_status <- function(panel) {
  panel |>
    dplyr::arrange(metric, iso3c, year) |>
    dplyr::group_by(metric, iso3c, country_name) |>
    dplyr::summarise(
      first_observed_year = {
        value <- year[rank_observed]
        if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
      },
      last_observed_year = {
        value <- year[rank_observed]
        if (length(value) == 0L) NA_integer_ else max(value, na.rm = TRUE)
      },
      observed_2005 = any(year == rank_window_start & rank_observed, na.rm = TRUE),
      china_top_2005 = any(
        year == rank_window_start & rank_observed & china_is_top_observed,
        na.rm = TRUE
      ),
      ever_china_top = any(china_is_top_observed %in% TRUE, na.rm = TRUE),
      first_china_top_year = {
        value <- year[china_is_top_observed %in% TRUE]
        if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
      },
      first_observed_china_top = {
        value <- china_is_top_observed[rank_observed]
        if (length(value) == 0L) NA else value[[1]]
      },
      n_observed_years = sum(rank_observed, na.rm = TRUE),
      n_china_top_years = sum(china_is_top_observed %in% TRUE, na.rm = TRUE),
      .groups = "drop"
    )
}

metric_status_base <- make_metric_status(rank_panel)

entry_table <- rank_panel |>
  dplyr::filter(rank_observed) |>
  dplyr::arrange(metric, iso3c, year) |>
  dplyr::group_by(metric, iso3c) |>
  dplyr::mutate(
    previous_observed_year = dplyr::lag(year),
    previous_china_is_top = dplyr::lag(china_is_top_observed),
    previous_observed_year_is_prior_year = previous_observed_year == year - 1L,
    observed_entry_after_non_top =
      china_is_top_observed %in% TRUE &
        !is.na(previous_china_is_top) &
        previous_china_is_top %in% FALSE &
        previous_observed_year_is_prior_year,
    entry_after_non_top_gap =
      china_is_top_observed %in% TRUE &
        !is.na(previous_china_is_top) &
        previous_china_is_top %in% FALSE &
        !previous_observed_year_is_prior_year
  ) |>
  dplyr::summarise(
    first_entry_after_non_top = {
      value <- year[observed_entry_after_non_top]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    previous_observed_year_at_entry = {
      if (!any(observed_entry_after_non_top, na.rm = TRUE)) {
        NA_integer_
      } else {
        year_entry <- min(year[observed_entry_after_non_top], na.rm = TRUE)
        as.integer(previous_observed_year[match(year_entry, year)])
      }
    },
    first_entry_after_gap = {
      value <- year[entry_after_non_top_gap]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    absorbing_after_entry = {
      if (!any(observed_entry_after_non_top, na.rm = TRUE)) {
        FALSE
      } else {
        year_entry <- min(year[observed_entry_after_non_top], na.rm = TRUE)
        all(china_is_top_observed[year >= year_entry] %in% TRUE, na.rm = TRUE)
      }
    },
    .groups = "drop"
  )

coverage_2005_2010 <- rank_panel |>
  dplyr::filter(year >= rank_window_start, year <= cutoff_year) |>
  dplyr::group_by(metric, iso3c) |>
  dplyr::summarise(
    observed_all_2005_2010 = all(rank_observed),
    china_top_any_2005_2010 = any(china_is_top_observed %in% TRUE, na.rm = TRUE),
    .groups = "drop"
  )

metric_status <- metric_status_base |>
  dplyr::left_join(entry_table, by = c("metric", "iso3c")) |>
  dplyr::left_join(coverage_2005_2010, by = c("metric", "iso3c")) |>
  dplyr::mutate(
    censoring_status = dplyr::case_when(
      !observed_2005 ~ "missing_rank_in_2005",
      china_top_2005 ~ "left_censored_china_rank1_in_2005",
      !ever_china_top ~ "never_china_rank1_observed",
      !is.na(first_entry_after_non_top) &
        first_entry_after_non_top > rank_window_start ~ "observed_entry_after_2005",
      first_observed_china_top %in% TRUE ~ "left_censored_after_first_observed_year",
      !is.na(first_entry_after_gap) ~ "entry_after_gap_not_estimable",
      TRUE ~ "observed_but_entry_not_estimable"
    ),
    observed_entry_year = dplyr::if_else(
      censoring_status == "observed_entry_after_2005",
      first_entry_after_non_top,
      NA_integer_
    )
  )

make_rule_panel <- function(metric_name, rule_name) {
  status <- metric_status |>
    dplyr::filter(metric == metric_name)

  if (rule_name == "clean_risk_set") {
    status <- status |>
      dplyr::mutate(
        eligible_country =
          observed_2005 & !china_top_2005 &
            (censoring_status %in% c(
              "never_china_rank1_observed",
              "observed_entry_after_2005"
            ))
      )
  } else if (rule_name == "left_censored_as_already_treated") {
    status <- status |>
      dplyr::mutate(eligible_country = observed_2005)
  } else if (rule_name == "restricted_post_2005_cohort") {
    status <- status |>
      dplyr::mutate(
        eligible_country = censoring_status %in% c(
          "never_china_rank1_observed",
          "observed_entry_after_2005"
        )
      )
  } else if (rule_name == "cutoff_not_top_through_2010") {
    status <- status |>
      dplyr::mutate(
        eligible_country =
          observed_all_2005_2010 & !china_top_any_2005_2010 &
            (
              censoring_status == "never_china_rank1_observed" |
                (!is.na(first_entry_after_non_top) &
                   first_entry_after_non_top > cutoff_year)
            )
      )
  } else {
    status <- status |>
      dplyr::mutate(eligible_country = FALSE)
  }

  status <- status |>
    dplyr::mutate(rule = rule_name)

  rank_panel |>
    dplyr::filter(metric == metric_name) |>
    dplyr::left_join(
      status |>
        dplyr::select(
          metric, iso3c, rule, eligible_country, censoring_status,
          first_entry_after_non_top, observed_entry_year, first_entry_after_gap,
          absorbing_after_entry, observed_2005, china_top_2005,
          observed_all_2005_2010, china_top_any_2005_2010
        ),
      by = c("metric", "iso3c")
    ) |>
    dplyr::filter(eligible_country, rank_observed) |>
    dplyr::mutate(
      china_top = as.integer(china_is_top_observed %in% TRUE),
      country_id = as.integer(as.factor(iso3c))
    ) |>
    dplyr::arrange(country_id, year)
}

summarise_rule_support <- function(panel, metric_name, rule_name) {
  if (nrow(panel) == 0L) {
    return(tibble::tibble(
      metric = metric_name,
      rule = rule_name,
      n_obs_rank = 0L,
      n_countries_rank = 0L,
      n_obs_model_complete = 0L,
      n_countries_model_complete = 0L,
      n_treated_countries = 0L,
      n_control_countries = 0L,
      n_treated_country_years = 0L,
      n_left_censored_2005 = 0L,
      n_observed_entries_after_2005 = 0L,
      n_entries_after_gap_in_rule = 0L,
      n_missing_rank_2005_in_rule = 0L,
      first_entry_min = NA_integer_,
      first_entry_max = NA_integer_,
      panel_min = NA_integer_,
      panel_max = NA_integer_
    ))
  }

  model_complete <- panel |>
    dplyr::filter(
      year >= model_window_start,
      year <= model_window_end,
      dplyr::if_all(
        dplyr::all_of(c(
          "year", "iso3c", "abs_distance_china", "china_top",
          "log_gdp_pc", "free_press"
        )),
        ~ !is.na(.x)
      )
    )

  unit_status <- panel |>
    dplyr::distinct(
      iso3c, censoring_status, observed_entry_year, first_entry_after_gap,
      observed_2005, china_top_2005
    )

  model_units <- model_complete |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      ever_treated_model = any(china_top == 1L, na.rm = TRUE),
      treated_years_model = sum(china_top == 1L, na.rm = TRUE),
      .groups = "drop"
    )

  tibble::tibble(
    metric = metric_name,
    rule = rule_name,
    n_obs_rank = nrow(panel),
    n_countries_rank = dplyr::n_distinct(panel$iso3c),
    n_obs_model_complete = nrow(model_complete),
    n_countries_model_complete = dplyr::n_distinct(model_complete$iso3c),
    n_treated_countries = sum(model_units$ever_treated_model, na.rm = TRUE),
    n_control_countries = sum(!model_units$ever_treated_model, na.rm = TRUE),
    n_treated_country_years = sum(model_complete$china_top == 1L, na.rm = TRUE),
    n_left_censored_2005 = sum(unit_status$china_top_2005, na.rm = TRUE),
    n_observed_entries_after_2005 =
      sum(!is.na(unit_status$observed_entry_year), na.rm = TRUE),
    n_entries_after_gap_in_rule =
      sum(!is.na(unit_status$first_entry_after_gap), na.rm = TRUE),
    n_missing_rank_2005_in_rule = sum(!unit_status$observed_2005, na.rm = TRUE),
    first_entry_min = suppressWarnings(min(
      unit_status$observed_entry_year,
      na.rm = TRUE
    )),
    first_entry_max = suppressWarnings(max(
      unit_status$observed_entry_year,
      na.rm = TRUE
    )),
    panel_min = min(model_complete$year, na.rm = TRUE),
    panel_max = max(model_complete$year, na.rm = TRUE)
  ) |>
    dplyr::mutate(
      dplyr::across(
        c(first_entry_min, first_entry_max, panel_min, panel_max),
        ~ dplyr::if_else(is.infinite(.x), NA_real_, as.numeric(.x))
      )
    )
}

estimate_fect <- function(panel, metric_name, rule_name, label_suffix = "full_sample",
                          excluded_iso3c = character(0)) {
  panel_model <- panel |>
    dplyr::filter(
      !iso3c %in% excluded_iso3c,
      year >= model_window_start,
      year <= model_window_end,
      dplyr::if_all(
        dplyr::all_of(c(
          "year", "iso3c", "abs_distance_china", "china_top",
          "log_gdp_pc", "free_press"
        )),
        ~ !is.na(.x)
      )
    ) |>
    dplyr::mutate(country_id = as.integer(as.factor(iso3c))) |>
    dplyr::arrange(country_id, year)

  empty_result <- function(status, error_message = NA_character_) {
    tibble::tibble(
      metric = metric_name,
      metric_label = metric_label(metric_name),
      rule = rule_name,
      rule_label = model_status_label(rule_name),
      sample_variant = label_suffix,
      excluded_iso3c = paste(excluded_iso3c, collapse = ";"),
      status = status,
      error_message = error_message,
      nboots = args$nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_character_,
      elapsed_seconds = NA_real_,
      n_obs = nrow(panel_model),
      n_countries = dplyr::n_distinct(panel_model$iso3c),
      n_treated = dplyr::n_distinct(panel_model$iso3c[panel_model$china_top == 1L]),
      n_control = dplyr::n_distinct(panel_model$iso3c) -
        dplyr::n_distinct(panel_model$iso3c[panel_model$china_top == 1L]),
      n_treated_country_years = sum(panel_model$china_top == 1L, na.rm = TRUE),
      panel_min = if (nrow(panel_model) == 0L) NA_integer_ else min(panel_model$year),
      panel_max = if (nrow(panel_model) == 0L) NA_integer_ else max(panel_model$year),
      pre_treated_mean = NA_real_,
      outcome_sd = if (nrow(panel_model) == 0L) {
        NA_real_
      } else {
        stats::sd(panel_model$abs_distance_china, na.rm = TRUE)
      }
    )
  }

  if (nrow(panel_model) == 0L) {
    return(empty_result("not_estimated_no_complete_rows"))
  }
  unit_treatment_status <- panel_model |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      .groups = "drop"
    )
  n_treated_units <- sum(unit_treatment_status$ever_treated, na.rm = TRUE)
  n_never_treated_units <- sum(!unit_treatment_status$ever_treated, na.rm = TRUE)

  if (length(unique(panel_model$china_top)) < 2L) {
    return(empty_result("not_estimated_no_treatment_variation"))
  }
  if (n_treated_units < 2L) {
    return(empty_result("not_estimated_too_few_treated_countries"))
  }
  if (n_never_treated_units < 2L) {
    return(empty_result("not_estimated_too_few_never_treated_countries"))
  }

  timing <- system.time({
    fit <- tryCatch(
      run_fect_analysis(
        panel_model,
        method = "ife",
        nboots = args$nboots,
        fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
      ),
      error = function(e) e
    )
  })

  if (inherits(fit, "error")) {
    return(empty_result("error", conditionMessage(fit)))
  }

  summary <- fect_att_summary(fit)
  treated_units <- panel_model |>
    dplyr::arrange(iso3c, year) |>
    dplyr::group_by(iso3c) |>
    dplyr::mutate(entry = china_top == 1L & dplyr::lag(china_top, default = 0L) == 0L) |>
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      first_entry = ifelse(any(entry), min(year[entry]), NA_integer_),
      .groups = "drop"
    )

  pre_treated_mean <- panel_model |>
    dplyr::left_join(
      treated_units |>
        dplyr::filter(ever_treated, !is.na(first_entry)) |>
        dplyr::select(iso3c, first_entry),
      by = "iso3c"
    ) |>
    dplyr::filter(!is.na(first_entry), year < first_entry) |>
    dplyr::summarise(value = mean(abs_distance_china, na.rm = TRUE)) |>
    dplyr::pull(value)

  tibble::tibble(
    metric = metric_name,
    metric_label = metric_label(metric_name),
    rule = rule_name,
    rule_label = model_status_label(rule_name),
    sample_variant = label_suffix,
    excluded_iso3c = paste(excluded_iso3c, collapse = ";"),
    status = "ok",
    error_message = NA_character_,
    nboots = args$nboots,
    att = as.numeric(summary$att),
    se = as.numeric(summary$se),
    ci_lo = as.numeric(summary$ci_lo),
    ci_hi = as.numeric(summary$ci_hi),
    p = as.numeric(summary$p),
    r_cv = paste(summary$r_cv, collapse = ";"),
    elapsed_seconds = as.numeric(timing[["elapsed"]]),
    n_obs = nrow(panel_model),
    n_countries = dplyr::n_distinct(panel_model$iso3c),
    n_treated = n_treated_units,
    n_control = n_never_treated_units,
    n_treated_country_years = sum(panel_model$china_top == 1L, na.rm = TRUE),
    panel_min = min(panel_model$year),
    panel_max = max(panel_model$year),
    pre_treated_mean = pre_treated_mean,
    outcome_sd = stats::sd(panel_model$abs_distance_china, na.rm = TRUE)
  )
}

rules_to_model <- c(
  "clean_risk_set",
  "left_censored_as_already_treated",
  "restricted_post_2005_cohort",
  "cutoff_not_top_through_2010"
)

message("Building treatment panels.")
rule_panels <- list()
support_rows <- list()
for (metric_name in metrics_to_model) {
  for (rule_name in rules_to_model) {
    key <- paste(metric_name, rule_name, sep = "__")
    panel <- make_rule_panel(metric_name, rule_name)
    rule_panels[[key]] <- panel
    support_rows[[key]] <- summarise_rule_support(panel, metric_name, rule_name)
  }
}

sample_support <- dplyr::bind_rows(support_rows) |>
  dplyr::mutate(
    metric_label = metric_label(metric),
    rule_label = model_status_label(rule),
    n_left_censored_2005 = dplyr::if_else(
      rule == "left_censored_as_already_treated",
      n_left_censored_2005,
      0L
    )
  ) |>
  dplyr::select(
    metric, metric_label, rule, rule_label, dplyr::everything()
  )

model_panel_export <- dplyr::bind_rows(rule_panels, .id = "metric_rule") |>
  dplyr::filter(year >= model_window_start, year <= model_window_end) |>
  dplyr::mutate(
    complete_case_for_estimation = dplyr::if_all(
      dplyr::all_of(c(
        "year", "iso3c", "abs_distance_china", "china_top",
        "log_gdp_pc", "free_press"
      )),
      ~ !is.na(.x)
    )
  ) |>
  dplyr::select(
    metric_rule, metric, rule, iso3c, country_name, year,
    china_top, china_rank, top_partner, top_partner_name,
    censoring_status, abs_distance_china, log_gdp_pc, free_press,
    complete_case_for_estimation
  )

model_panel_complete_export <- model_panel_export |>
  dplyr::filter(complete_case_for_estimation)

message("Estimating fect IFE models with nboots = ", args$nboots, ".")
model_results <- list()
for (metric_name in metrics_to_model) {
  for (rule_name in rules_to_model) {
    key <- paste(metric_name, rule_name, sep = "__")
    message("Estimating: ", metric_name, " / ", rule_name)
    model_results[[key]] <- estimate_fect(rule_panels[[key]], metric_name, rule_name)
  }
}

if (isTRUE(args$run_focus_influence)) {
  message("Estimating focused Australia/Brazil influence checks for clean risk set.")
  for (metric_name in metrics_to_model) {
    key <- paste(metric_name, "clean_risk_set", sep = "__")
    panel <- rule_panels[[key]]
    for (variant in c("drop_AUS", "drop_BRA", "drop_AUS_BRA")) {
      excluded <- switch(
        variant,
        drop_AUS = "AUS",
        drop_BRA = "BRA",
        drop_AUS_BRA = c("AUS", "BRA")
      )
      model_results[[paste(key, variant, sep = "__")]] <-
        estimate_fect(panel, metric_name, "clean_risk_set", variant, excluded)
    }
  }
}

model_results <- dplyr::bind_rows(model_results)

paper_baseline_results <- dplyr::bind_rows(
  tibble::as_tibble(paper_main_summary) |>
    dplyr::mutate(
      r_cv = as.character(r_cv),
      metric = "pipeline_original_itpde_no_sector_filter",
      metric_label = "Pipeline original sem filtro setorial (diagnóstico)",
      rule = "paper_targets_absorbing_covariate_sample",
      rule_label = "Amostra absorvente do targets",
      sample_variant = "targets_existing_10000_boot",
      excluded_iso3c = "",
      status = "ok",
      error_message = NA_character_,
      nboots = 10000L,
      elapsed_seconds = NA_real_,
      .before = att
    ),
  tibble::as_tibble(paper_nocov_summary) |>
    dplyr::mutate(
      r_cv = as.character(r_cv),
      metric = "pipeline_original_itpde_no_sector_filter",
      metric_label = "Pipeline original sem filtro setorial (diagnóstico)",
      rule = "paper_targets_absorbing_no_covariates",
      rule_label = "Amostra absorvente do targets, sem covariáveis",
      sample_variant = "targets_existing_10000_boot",
      excluded_iso3c = "",
      status = "ok",
      error_message = NA_character_,
      nboots = 10000L,
      elapsed_seconds = NA_real_,
      .before = att
    )
) |>
  dplyr::select(
    metric, metric_label, rule, rule_label, sample_variant, excluded_iso3c,
    status, error_message, nboots, att, se, ci_lo, ci_hi, p, r_cv,
    elapsed_seconds, n_obs, n_countries, n_treated, n_control,
    n_treated_country_years, panel_min, panel_max, pre_treated_mean,
    outcome_sd, dplyr::everything()
  )

all_model_results <- dplyr::bind_rows(
  paper_baseline_results,
  model_results |>
    dplyr::mutate(
      att_rel_pct = 100 * att / pre_treated_mean,
      att_sd_units = att / outcome_sd
    )
) |>
  dplyr::mutate(
    direction = dplyr::case_when(
      is.na(att) ~ NA_character_,
      att < 0 ~ "closer_to_china",
      att > 0 ~ "farther_from_china",
      TRUE ~ "zero"
    )
  )

status_by_country <- metric_status |>
  dplyr::mutate(metric_label = metric_label(metric)) |>
  dplyr::select(
    metric, metric_label, iso3c, country_name, censoring_status,
    first_observed_year, last_observed_year, observed_2005, china_top_2005,
    ever_china_top, first_china_top_year, first_entry_after_non_top,
    observed_entry_year, first_entry_after_gap, previous_observed_year_at_entry,
    absorbing_after_entry, n_observed_years, n_china_top_years,
    observed_all_2005_2010, china_top_any_2005_2010
  ) |>
  dplyr::arrange(metric, censoring_status, observed_entry_year, iso3c)

left_censored <- status_by_country |>
  dplyr::filter(china_top_2005) |>
  dplyr::arrange(metric, iso3c)

entry_distribution <- status_by_country |>
  dplyr::filter(!is.na(observed_entry_year)) |>
  dplyr::count(metric, metric_label, observed_entry_year, name = "n_countries") |>
  dplyr::arrange(metric, observed_entry_year)

changed_status <- onsets_comparison |>
  dplyr::select(
    iso3c, country_name,
    goods_exports = first_china_rank1_year_ge2005_goods_exports_rank,
    goods_services_exports =
      first_china_rank1_year_ge2005_goods_services_exports_rank,
    goods_services_two_way =
      first_china_rank1_year_ge2005_goods_services_two_way_rank,
    status_goods_exports = onset_status_goods_exports_rank,
    status_goods_services_exports = onset_status_goods_services_exports_rank,
    status_goods_services_two_way = onset_status_goods_services_two_way_rank,
    publicly_reported_onset, public_apparent_metric,
    any_services_export_change, any_two_way_change, any_change_from_goods_exports
  ) |>
  dplyr::filter(any_change_from_goods_exports) |>
  dplyr::arrange(iso3c)

overlap_country_year <- rank_panel |>
  dplyr::filter(metric %in% metrics_to_model, rank_observed) |>
  dplyr::select(metric, iso3c, year, china_top_alt = china_is_top_observed) |>
  tidyr::pivot_wider(names_from = metric, values_from = china_top_alt) |>
  dplyr::filter(!is.na(goods_exports_rank)) |>
  tidyr::pivot_longer(
    cols = c(goods_services_exports_rank, goods_services_two_way_rank),
    names_to = "alternative_metric",
    values_to = "alternative_china_top"
  ) |>
  dplyr::filter(!is.na(alternative_china_top)) |>
  dplyr::mutate(
    overlap_category = dplyr::case_when(
      goods_exports_rank & alternative_china_top ~ "both_treated",
      goods_exports_rank & !alternative_china_top ~ "goods_exports_only",
      !goods_exports_rank & alternative_china_top ~ "alternative_only",
      TRUE ~ "neither_treated"
    )
  ) |>
  dplyr::count(alternative_metric, overlap_category, name = "n_country_years") |>
  tidyr::pivot_wider(
    names_from = overlap_category,
    values_from = n_country_years,
    values_fill = 0
  ) |>
  ensure_columns(
    c("both_treated", "goods_exports_only", "alternative_only", "neither_treated"),
    fill = 0L
  ) |>
  dplyr::mutate(
    metric_label = metric_label(alternative_metric),
    jaccard_treated_country_years = both_treated /
      (both_treated + goods_exports_only + alternative_only)
  ) |>
  dplyr::select(
    alternative_metric, metric_label, both_treated, goods_exports_only,
    alternative_only, neither_treated, jaccard_treated_country_years
  )

overlap_country <- metric_status |>
  dplyr::select(metric, iso3c, ever_china_top) |>
  tidyr::pivot_wider(names_from = metric, values_from = ever_china_top) |>
  tidyr::pivot_longer(
    cols = c(goods_services_exports_rank, goods_services_two_way_rank),
    names_to = "alternative_metric",
    values_to = "alternative_ever_treated"
  ) |>
  dplyr::mutate(
    overlap_category = dplyr::case_when(
      goods_exports_rank & alternative_ever_treated ~ "both_ever",
      goods_exports_rank & !alternative_ever_treated ~ "goods_exports_only",
      !goods_exports_rank & alternative_ever_treated ~ "alternative_only",
      TRUE ~ "neither_ever"
    )
  ) |>
  dplyr::count(alternative_metric, overlap_category, name = "n_countries") |>
  tidyr::pivot_wider(
    names_from = overlap_category,
    values_from = n_countries,
    values_fill = 0
  ) |>
  ensure_columns(
    c("both_ever", "goods_exports_only", "alternative_only", "neither_ever"),
    fill = 0L
  ) |>
  dplyr::mutate(
    metric_label = metric_label(alternative_metric),
    jaccard_ever_treated = both_ever /
      (both_ever + goods_exports_only + alternative_only)
  ) |>
  dplyr::select(
    alternative_metric, metric_label, both_ever, goods_exports_only,
    alternative_only, neither_ever, jaccard_ever_treated
  )

overlap_summary <- overlap_country_year |>
  dplyr::left_join(
    overlap_country |>
      dplyr::select(
        alternative_metric, metric_label, both_ever, jaccard_ever_treated
      ),
    by = c("alternative_metric", "metric_label")
  )

focus_cases <- rank_panel |>
  dplyr::filter(iso3c %in% c("AUS", "BRA"), metric %in% metrics_to_model) |>
  dplyr::select(
    metric, iso3c, country_name, year,
    rank_observed, china_rank, top_partner, top_partner_name,
    china_is_top_observed, china_value_musd, top_value_musd
  ) |>
  dplyr::mutate(metric_label = metric_label(metric)) |>
  dplyr::arrange(iso3c, metric, year)

focus_case_summary <- status_by_country |>
  dplyr::filter(iso3c %in% c("AUS", "BRA")) |>
  dplyr::left_join(
    onsets_comparison |>
      dplyr::filter(iso3c %in% c("AUS", "BRA")) |>
      dplyr::select(
        iso3c, publicly_reported_onset, public_apparent_metric,
        first_china_rank1_year_ge2005_goods_two_way_supplemental
      ),
    by = "iso3c"
  ) |>
  dplyr::arrange(iso3c, metric)

public_metric_focus <- public_metric |>
  dplyr::filter(iso3c %in% c("AUS", "BRA"), partner_iso3 %in% c("CHN", "USA", "JPN")) |>
  dplyr::arrange(iso3c, year, partner_rank)

status_counts <- status_by_country |>
  dplyr::count(metric, metric_label, censoring_status, name = "n_countries") |>
  dplyr::arrange(metric, censoring_status)

results_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_model_results_", run_date, ".csv")
)
support_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_sample_support_", run_date, ".csv")
)
panel_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_model_panel_", run_date, ".csv")
)
panel_complete_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_model_panel_complete_case_", run_date, ".csv")
)
status_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_status_by_country_", run_date, ".csv")
)
left_censored_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_left_censored_2005_", run_date, ".csv")
)
entry_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_entry_distribution_", run_date, ".csv")
)
changed_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_changed_status_", run_date, ".csv")
)
overlap_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_overlap_with_goods_exports_", run_date, ".csv")
)
focus_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_focus_cases_aus_bra_", run_date, ".csv")
)
public_focus_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_public_goods_two_way_focus_aus_bra_", run_date, ".csv")
)
target_inputs_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_target_inputs_manifest_", run_date, ".csv")
)

readr::write_csv(all_model_results, results_file, na = "")
readr::write_csv(sample_support, support_file, na = "")
readr::write_csv(model_panel_export, panel_file, na = "")
readr::write_csv(model_panel_complete_export, panel_complete_file, na = "")
readr::write_csv(status_by_country, status_file, na = "")
readr::write_csv(left_censored, left_censored_file, na = "")
readr::write_csv(entry_distribution, entry_file, na = "")
readr::write_csv(changed_status, changed_file, na = "")
readr::write_csv(overlap_summary, overlap_file, na = "")
readr::write_csv(focus_case_summary, focus_file, na = "")
readr::write_csv(public_metric_focus, public_focus_file, na = "")
readr::write_csv(target_input_manifest, target_inputs_file, na = "")

plot_entry <- entry_distribution |>
  ggplot2::ggplot(ggplot2::aes(
    x = observed_entry_year,
    y = n_countries,
    fill = metric_label
  )) +
  ggplot2::geom_col(show.legend = FALSE) +
  ggplot2::facet_wrap(~ metric_label, ncol = 1, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(2005, 2022, by = 2)) +
  ggplot2::labs(
    x = "Ano de entrada observada",
    y = "Número de países",
    caption = "Fonte: ITPD-E e BaTIS BPM6; entradas observadas após ano anterior não China #1."
  ) +
  ggplot2::theme_minimal(base_size = 11)

entry_plot_file <- file.path(
  figure_dir,
  paste0("figura_1_distribuicao_entradas_observadas_", run_date, ".png")
)
ggplot2::ggsave(entry_plot_file, plot_entry, width = 7, height = 7, dpi = 300)
entry_plot_rel <- file.path("figures", basename(entry_plot_file))

plot_overlap <- overlap_country_year |>
  tidyr::pivot_longer(
    cols = c(both_treated, goods_exports_only, alternative_only),
    names_to = "category",
    values_to = "n_country_years"
  ) |>
  dplyr::mutate(
    category = dplyr::recode(
      category,
      both_treated = "Ambas",
      goods_exports_only = "Só bens/exportações",
      alternative_only = "Só alternativa"
    )
  ) |>
  ggplot2::ggplot(ggplot2::aes(
    x = category,
    y = n_country_years,
    fill = category
  )) +
  ggplot2::geom_col(show.legend = FALSE) +
  ggplot2::facet_wrap(~ metric_label, nrow = 1) +
  ggplot2::labs(
    x = NULL,
    y = "País-anos tratados",
    caption = "Fonte: ITPD-E e BaTIS BPM6; país-anos 2005-2022 com ranking observado nas duas métricas."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1))

overlap_plot_file <- file.path(
  figure_dir,
  paste0("figura_2_overlap_tratamento_metricas_", run_date, ".png")
)
ggplot2::ggsave(overlap_plot_file, plot_overlap, width = 8, height = 4.5, dpi = 300)
overlap_plot_rel <- file.path("figures", basename(overlap_plot_file))

main_results_table <- all_model_results |>
  dplyr::filter(
    sample_variant == "full_sample",
    metric %in% metrics_to_model
  ) |>
  dplyr::mutate(
    att_fmt = fmt(att),
    se_fmt = fmt(se),
    ci_fmt = paste0("[", fmt(ci_lo), ", ", fmt(ci_hi), "]"),
    p_fmt = format_p(p),
    line = paste0(
      "| ", metric_label, " | ", rule_label, " | ", status, " | ",
      att_fmt, " | ", se_fmt, " | ", ci_fmt, " | ", p_fmt, " | ",
      n_treated, " | ", n_control, " | ", panel_min, "-", panel_max, " |"
    )
  ) |>
  dplyr::pull(line)

if (length(main_results_table) == 0L) {
  main_results_table <- "| NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |"
}

pipeline_diagnostic_table <- all_model_results |>
  dplyr::filter(
    metric == "pipeline_original_itpde_no_sector_filter",
    rule == "paper_targets_absorbing_covariate_sample"
  ) |>
  dplyr::mutate(
    att_fmt = fmt(att),
    se_fmt = fmt(se),
    ci_fmt = paste0("[", fmt(ci_lo), ", ", fmt(ci_hi), "]"),
    p_fmt = format_p(p),
    line = paste0(
      "| ", metric_label, " | ", rule_label, " | ", status, " | ",
      att_fmt, " | ", se_fmt, " | ", ci_fmt, " | ", p_fmt, " | ",
      n_treated, " | ", n_control, " | ", panel_min, "-", panel_max, " |"
    )
  ) |>
  dplyr::pull(line)

if (length(pipeline_diagnostic_table) == 0L) {
  pipeline_diagnostic_table <- "| NA | NA | NA | NA | NA | NA | NA | NA | NA | NA |"
}

support_table <- sample_support |>
  dplyr::mutate(
    line = paste0(
      "| ", metric_label, " | ", rule_label, " | ",
      n_countries_model_complete, " | ", n_treated_countries, " | ",
      n_control_countries, " | ", n_treated_country_years, " | ",
      n_left_censored_2005, " | ", n_entries_after_gap_in_rule,
      " | ", n_missing_rank_2005_in_rule, " |"
    )
  ) |>
  dplyr::pull(line)

status_count_table <- status_counts |>
  dplyr::mutate(
    line = paste0(
      "| ", metric_label, " | ", censoring_status, " | ", n_countries, " |"
    )
  ) |>
  dplyr::pull(line)

overlap_table <- overlap_summary |>
  dplyr::mutate(
    line = paste0(
      "| ", metric_label, " | ", both_treated, " | ", goods_exports_only,
      " | ", alternative_only, " | ", fmt(jaccard_treated_country_years),
      " | ", both_ever, " | ", fmt(jaccard_ever_treated), " |"
    )
  ) |>
  dplyr::pull(line)

focus_table <- focus_case_summary |>
  dplyr::mutate(
    line = paste0(
      "| ", iso3c, " | ", metric_label, " | ", censoring_status,
      " | ", first_china_top_year, " | ", observed_entry_year,
      " | ", publicly_reported_onset, " | ",
      first_china_rank1_year_ge2005_goods_two_way_supplemental, " |"
    )
  ) |>
  dplyr::pull(line)

influence_table <- all_model_results |>
  dplyr::filter(sample_variant %in% c("full_sample", "drop_AUS", "drop_BRA", "drop_AUS_BRA")) |>
  dplyr::filter(rule == "clean_risk_set") |>
  dplyr::select(metric_label, sample_variant, status, att, se, p, n_treated, n_control) |>
  dplyr::mutate(
    line = paste0(
      "| ", metric_label, " | ", sample_variant, " | ", status, " | ",
      fmt(att), " | ", fmt(se), " | ", format_p(p), " | ",
      n_treated, " | ", n_control, " |"
    )
  ) |>
  dplyr::pull(line)

if (length(influence_table) == 0L) {
  influence_table <- "| NA | NA | NA | NA | NA | NA | NA | NA |"
}

report_md <- file.path(
  report_dir,
  paste0("relatorio_cross_country_metricas_alternativas_china_top_", run_date, ".md")
)
report_rmd <- file.path(
  report_dir,
  paste0("relatorio_cross_country_metricas_alternativas_china_top_", run_date, ".Rmd")
)
report_pdf <- file.path(
  report_dir,
  paste0("relatorio_cross_country_metricas_alternativas_china_top_", run_date, ".pdf")
)

report_body <- c(
  "# Métricas alternativas de China como parceiro #1 na regressão cross-country",
  "",
  paste0("Data de execução: ", run_date),
  "",
  "## Resumo executivo",
  "",
  paste0(
    "Reestimei a especificação cross-country `fect` IFE com covariáveis ",
    "(`log_gdp_pc` e `free_press`) usando como especificação substantiva ",
    "principal a métrica M2, isto é, China como destino #1 das exportações de ",
    "bens no ITPD-E com filtro setorial. M3 acrescenta serviços exportados, e ",
    "M4 mede comércio total two-way de bens e serviços. A análise foi feita ",
    "fora do pipeline `targets`, lendo objetos já materializados de forma ",
    "read-only e usando os rankings BaTIS/ITPD-E já produzidos. A janela ",
    "causalmente comparável para as métricas com serviços começa em 2005; a ",
    "janela estimável com covariáveis termina em ", model_window_end, "."
  ),
  "",
  paste0(
    "O ponto central é que a métrica alternativa não é apenas uma robustez ",
    "mecânica: ela muda a população de risco. Países já China #1 em 2005 são ",
    "censurados à esquerda, países com primeira entrada observada após 2005 ",
    "formam a coorte de entrada observada, e controles nunca tratados em ",
    "2005-2022 ainda podem ter histórico pré-2005 não observado. Portanto, a ",
    "especificação mais defensável como robustez causal é o `clean risk set`, ",
    "que exige ranking observado em 2005 e China não ser #1 naquele ano."
  ),
  "",
  paste0(
    "O resultado antigo do pipeline original é reportado apenas como diagnóstico ",
    "de operacionalização, porque esse pipeline agrega `trade` do ITPD-E sem ",
    "filtrar `broad_sector`. Ele não deve ser tratado como baseline substantivo ",
    "se o paper define o tratamento como exportações de bens."
  ),
  "",
  "## Tabela 1. Resultados comparativos do `fect` IFE: M2, M3 e M4",
  "",
  "| Métrica | Regra de amostra | Status | ATT | SE | IC 95% | p | Tratados | Controles | Janela |",
  "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
  main_results_table,
  "",
  paste0(
    "Notas: ATT negativo indica redução da distância de ponto ideal à China. ",
    "Os erros-padrão usam ", args$nboots,
    " bootstrap draws. As linhas M2-M4 são comparáveis entre si na janela ",
    model_window_start, "-", model_window_end,
    ". Os contadores de suporte indicam os casos completos antes dos ",
    "filtros internos do `fect`; durante a estimação, o pacote informa que ",
    "unidades com menos de 5 períodos não tratados são descartadas para fins ",
    "de identificação. A regra que trata países já China #1 em 2005 como ",
    "tratados desde 2005 é reportada apenas como sensibilidade descritiva, ",
    "pois esses casos não têm pré-tratamento observado na janela BaTIS. O ",
    "arquivo de painel completo exportado registra os casos completos antes ",
    "dos descartes internos do `fect`."
  ),
  "",
  "## Tabela 1A. Diagnóstico do pipeline original sem filtro setorial",
  "",
  "| Métrica | Regra de amostra | Status | ATT | SE | IC 95% | p | Tratados | Controles | Janela |",
  "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
  pipeline_diagnostic_table,
  "",
  paste0(
    "Nota: esta linha vem do objeto já materializado em `targets` e usa 10.000 ",
    "bootstrap draws. Ela é útil para documentar a diferença entre o pipeline ",
    "original e a codificação goods-only, mas não é a baseline conceitual se o ",
    "estimando do paper é China como destino #1 das exportações de bens."
  ),
  "",
  "## Tabela 2. Suporte por métrica e regra de amostra",
  "",
  "| Métrica | Regra | Países no modelo | Tratados | Controles | País-anos tratados | Censurados em 2005 | Entradas após lacuna | Sem ranking em 2005 |",
  "|---|---|---:|---:|---:|---:|---:|---:|---:|",
  support_table,
  "",
  "## Tabela 3. Status de censura e entrada por métrica",
  "",
  "| Métrica | Status | Países |",
  "|---|---|---:|",
  status_count_table,
  "",
  "## Tabela 4. Overlap com a métrica principal de exportações de bens",
  "",
  "| Métrica alternativa | Ambos tratados | Só bens/exportações | Só alternativa | Jaccard país-ano | Ambos ever-treated | Jaccard país |",
  "|---|---:|---:|---:|---:|---:|---:|",
  overlap_table,
  "",
  "## Tabela 5. Austrália e Brasil",
  "",
  "| País | Métrica | Status | Primeiro ano China #1 | Entrada observada | Onset público | Bens two-way auxiliar |",
  "|---|---|---|---:|---:|---:|---:|",
  focus_table,
  "",
  "## Tabela 6. Sensibilidade de influência: Austrália e Brasil",
  "",
  "| Métrica | Amostra | Status | ATT | SE | p | Tratados | Controles |",
  "|---|---|---|---:|---:|---:|---:|---:|",
  influence_table,
  "",
  "## Figura 1. Distribuição dos anos de entrada observada",
  "",
  paste0("![Figura 1. Distribuição dos anos de entrada observada.](", entry_plot_rel, ")"),
  "",
  "## Figura 2. Overlap de país-anos tratados",
  "",
  paste0("![Figura 2. Overlap entre métricas de tratamento.](", overlap_plot_rel, ")"),
  "",
  "## Avaliação causal da operacionalização",
  "",
  "### Desenho reconstruído",
  "",
  paste0(
    "A unidade é país-ano, o outcome é a distância absoluta do ponto ideal na ",
    "AGNU em relação à China, e o tratamento é um indicador de que a China ocupa ",
    "o rank 1 no portfólio comercial do país segundo uma métrica específica. ",
    "A especificação estimada é um `fect` IFE com efeitos fixos de unidade e ano, ",
    "fatores latentes selecionados por validação cruzada e covariáveis ",
    "`log_gdp_pc` e `free_press`. O contraste estimado nas métricas alternativas ",
    "é o efeito médio de períodos em que a China é #1 dentro da população de ",
    "risco definida por cada regra de censura."
  ),
  "",
  "### O que muda no estimando",
  "",
  paste0(
    "`goods_exports_rank` é a codificação M2 e deve ser a especificação ",
    "substantiva principal quando o paper define tratamento como China sendo ",
    "o destino #1 das exportações de bens. Ela substitui a codificação do ",
    "pipeline original sem filtro setorial. ",
    "`goods_services_exports_rank` preserva a lógica de destino de exportações, ",
    "mas amplia o domínio econômico para serviços. `goods_services_two_way_rank` ",
    "mede centralidade comercial total; ela é mais próxima de linguagem pública ",
    "do tipo 'maior parceiro comercial', mas mistura demanda externa por bens, ",
    "serviços exportados e dependência de importações. Essa métrica muda o ",
    "estimando: deixa de ser status de destino exportador e passa a ser status ",
    "de relação comercial total."
  ),
  "",
  "### Censura à esquerda",
  "",
  paste0(
    "Como BaTIS BPM6 começa em 2005, não é defensável codificar automaticamente ",
    "países sem China #1 até 2010 como nunca tratados antes de 2005. O desenho ",
    "`left_censored_as_already_treated` é informativo descritivamente, mas não ",
    "tem pré-tratamento para países já tratados em 2005. O desenho ",
    "`restricted_post_2005_cohort` isola entradas observadas após 2005, mas os ",
    "controles nunca tratados ainda carregam incerteza histórica pré-2005. O ",
    "cutoff de 2010 só faz sentido como sensibilidade para late adopters; ele ",
    "seleciona países que permaneceram fora do status China #1 durante 2005-2010 ",
    "e, por isso, muda o escopo substantivo."
  ),
  "",
  "### Suposições e diagnósticos",
  "",
  "| Suposição | Evidência disponível | Diagnóstico possível | Status | Implicação |",
  "|---|---|---|---|---|",
  "| Validade de medida | Rankings ITPD-E/BaTIS e checagens AUS/BRA | Comparar onsets, overlap e casos públicos | Parcialmente verificável | Two-way melhora linguagem pública, mas muda conceito |",
  "| População de risco | Status de 2005 e entradas observadas | Tabelas de censura e `clean risk set` | Crítica | Excluir já tratados em 2005 é a escolha mais limpa |",
  "| Comparabilidade contrafactual | IFE com fatores latentes e covariáveis | Pretrends/placebos específicos por regra | Parcialmente verificável | Requer cautela causal; esta análise não prova paralelismo |",
  "| Ausência de antecipação | Não observada diretamente | Leads/event-study por métrica | Não verificável diretamente | Onsets econômicos podem ser antecipados politicamente |",
  "| Sem spillovers | Países podem responder a ascensão chinesa regional/global | Placebos regionais e controles de exposição | Frágil | Efeitos globais podem contaminar controles |",
  "",
  "## Recomendação",
  "",
  paste0(
    "Para o paper, eu usaria `goods_exports_rank` (M2) como especificação ",
    "principal reconstruída do tratamento de exportações de bens. A comparação ",
    "de robustez deve ser M2 versus `goods_services_exports_rank` (M3) e ",
    "`goods_services_two_way_rank` (M4), preferencialmente no `clean risk set`. ",
    "M3 pergunta se o resultado sobrevive ao acréscimo de serviços mantendo a ",
    "lógica de destino exportador; M4 pergunta se o resultado sobrevive quando ",
    "a linguagem pública de 'maior parceiro comercial' é operacionalizada como ",
    "comércio total de bens e serviços. A métrica `goods_two_way_supplemental` ",
    "deve permanecer auxiliar para Austrália/Brasil e para confronto com fontes ",
    "públicas, não como regressão cross-country, pois o CSV diagnóstico disponível ",
    "só cobre esses casos focais."
  ),
  "",
  paste0(
    "A especificação com cutoff em 2010 deve ser tratada como análise de escopo ",
    "para late adopters, não como correção causal preferida. Ela não resolve, por ",
    "si só, a incerteza pré-2005; apenas impõe uma população mais tardia e mais ",
    "selecionada."
  ),
  "",
  "## Arquivos gerados",
  "",
  paste0("- Diretório de dados: `", processed_dir, "`."),
  paste0("- Diretório de relatório: `", report_dir, "`."),
  "",
  paste0("- `", basename(results_file), "`: resultados dos modelos."),
  paste0("- `", basename(support_file), "`: suporte por métrica e regra."),
  paste0("- `", basename(panel_file), "`: painel pré-estimação."),
  paste0("- `", basename(panel_complete_file), "`: painel complete-case antes dos descartes internos do `fect`."),
  paste0("- `", basename(status_file), "`: status por país."),
  paste0("- `", basename(left_censored_file), "`: países censurados à esquerda em 2005."),
  paste0("- `", basename(entry_file), "`: distribuição dos anos de entrada."),
  paste0("- `", basename(changed_file), "`: países com mudança de status entre métricas."),
  paste0("- `", basename(overlap_file), "`: overlap entre M2 e métricas alternativas."),
  paste0("- `", basename(focus_file), "`: casos Austrália/Brasil."),
  paste0("- `", basename(public_focus_file), "`: métrica pública auxiliar para Austrália/Brasil."),
  paste0("- `", basename(target_inputs_file), "`: checksums dos objetos `_targets` lidos.")
)

writeLines(report_body, report_md, useBytes = TRUE)

rmd_body <- c(
  "---",
  "title: \"Métricas alternativas de China como parceiro #1\"",
  paste0("date: \"", run_date, "\""),
  "documentclass: article",
  "classoption: landscape",
  "fontsize: 8pt",
  "geometry: margin=0.45in",
  "header-includes:",
  "  - \\usepackage{array}",
  "  - \\setlength{\\tabcolsep}{3pt}",
  "  - \\renewcommand{\\arraystretch}{0.86}",
  "output:",
  "  pdf_document:",
  "    toc: false",
  "    number_sections: false",
  "    latex_engine: xelatex",
  "---",
  "",
  report_body[-1]
)

writeLines(rmd_body, report_rmd, useBytes = TRUE)

pdf_status <- "skipped"
pdf_error <- NA_character_
if (!args$skip_pdf) {
  pdf_attempt <- tryCatch(
    {
      rmarkdown::render(
        report_rmd,
        output_file = basename(report_pdf),
        output_dir = dirname(report_pdf),
        quiet = TRUE,
        envir = new.env(parent = globalenv())
      )
      "ok"
    },
    error = function(e) {
      pdf_error <<- conditionMessage(e)
      "error"
    }
  )
  pdf_status <- pdf_attempt
}

session_info_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_session_info_", run_date, ".txt")
)
writeLines(capture.output(utils::sessionInfo()), session_info_file, useBytes = TRUE)

input_md5 <- tools::md5sum(c(rank_file, onsets_file, public_metric_file))

manifest <- tibble::tibble(
  generated_on = as.character(run_date),
  nboots = args$nboots,
  model_window_start = model_window_start,
  model_window_end = model_window_end,
  rank_file = rank_file,
  rank_file_md5 = unname(input_md5[[rank_file]]),
  onsets_file = onsets_file,
  onsets_file_md5 = unname(input_md5[[onsets_file]]),
  public_metric_file = public_metric_file,
  public_metric_file_md5 = unname(input_md5[[public_metric_file]]),
  pdf_status = pdf_status,
  pdf_error = pdf_error,
  target_inputs_file = target_inputs_file,
  target_inputs_md5 = unname(tools::md5sum(target_inputs_file)),
  output = c(
    results_file, support_file, panel_file, panel_complete_file, status_file,
    left_censored_file, entry_file, changed_file, overlap_file, focus_file,
    public_focus_file, target_inputs_file, report_md, report_rmd, report_pdf,
    entry_plot_file, overlap_plot_file, session_info_file
  )
)

manifest_file <- file.path(
  processed_dir,
  paste0("alternative_cross_country_output_manifest_", run_date, ".csv")
)
readr::write_csv(manifest, manifest_file, na = "")

message("Wrote report: ", report_md)
if (pdf_status == "ok") {
  message("Wrote PDF: ", report_pdf)
} else if (pdf_status == "error") {
  warning("PDF render failed: ", pdf_error, call. = FALSE)
}
message("Wrote manifest: ", manifest_file)
print(
  all_model_results |>
    dplyr::filter(sample_variant %in% c("full_sample", "targets_existing_10000_boot")) |>
    dplyr::select(metric_label, rule_label, status, att, se, p, n_treated, n_control)
)
