#!/usr/bin/env Rscript

# Build a country-year master panel from the union of the trade-rank and UNGA
# sources, define treatment exclusively from consecutive observed trade ranks,
# and re-estimate the main goods-only status-current IFE specification.
#
# This diagnostic is deliberately separate from targets. It does not read,
# modify, unlock, or run the targets store.

options(scipen = 999)

renv_activation_path <- file.path("renv", "activate.R")
if (!file.exists(renv_activation_path)) {
  stop("renv/activate.R is required for this analysis.", call. = FALSE)
}
source(renv_activation_path)

suppressPackageStartupMessages({
  library(countrycode)
  library(data.table)
  library(DBI)
  library(digest)
  library(dplyr)
  library(duckdb)
  library(fect)
  library(janitor)
  library(readr)
  library(tibble)
  library(tidyr)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

source("scripts/functions.R")

decision_date <- as.Date("2026-08-29")
execution_date <- Sys.Date()
min_year <- 1990L
max_year <- 2023L
min_entry_year <- 2000L
min_duration_years <- 5L
expected_fect_version <- package_version("2.1.0")

if (packageVersion("fect") != expected_fect_version) {
  stop(
    "This analysis requires fect 2.1.0; loaded version is ",
    as.character(packageVersion("fect")), ".",
    call. = FALSE
  )
}

parse_args <- function(args) {
  get_arg <- function(prefix, default) {
    hit <- args[startsWith(args, prefix)]
    if (length(hit) == 0L) {
      return(default)
    }
    sub(prefix, "", hit[[1]], fixed = TRUE)
  }

  nboots <- as.integer(get_arg("--nboots=", "10000"))
  run_label <- get_arg("--run-label=", "final")
  overwrite <- identical(tolower(get_arg("--overwrite=", "false")), "true")

  if (is.na(nboots) || nboots < 20L) {
    stop("--nboots must be an integer >= 20.", call. = FALSE)
  }
  if (!run_label %in% c("smoke", "final")) {
    stop("--run-label must be either 'smoke' or 'final'.", call. = FALSE)
  }
  if (run_label == "final" && nboots != 10000L) {
    stop("The final run requires exactly 10,000 bootstrap repetitions.",
         call. = FALSE)
  }

  list(nboots = nboots, run_label = run_label, overwrite = overwrite)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

input_dir <- file.path(
  "data", "processed", "diagnostics",
  "china_top_m2_goods_status_current_min5"
)
processed_root <- file.path(
  "data", "processed", "diagnostics",
  "china_top_m2_goods_full_join_consecutive"
)
processed_dir <- file.path(processed_root, args$run_label)
report_dir <- file.path(
  "quality_reports", "cross_country_sample",
  "full_join_consecutive_treatment"
)

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

prefix <- paste0(
  "m2_goods_full_join_consecutive_",
  format(decision_date, "%Y-%m-%d")
)
master_path <- file.path(processed_dir, paste0(prefix, "_master_panel.csv"))
report_path <- file.path(
  report_dir,
  paste0(prefix, "_", args$run_label, "_report.md")
)
existing_sentinels <- c(master_path, report_path)
if (any(file.exists(existing_sentinels)) && !args$overwrite) {
  stop(
    "Output already exists for this run label. Use --overwrite=true only ",
    "after reviewing the existing artifacts.",
    call. = FALSE
  )
}

itpd_path <- file.path("raw data", "ITPDE_R03.csv")
unga_path <- file.path(
  "raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv"
)
old_full_panel_path <- file.path(
  input_dir,
  "m2_goods_status_current_full_panel_2026-05-20.csv"
)
old_model_results_path <- file.path(
  input_dir,
  "m2_goods_status_current_min_duration_model_results_2026-05-20.csv"
)
old_trade_aggregate_path <- file.path(
  input_dir,
  "m2_goods_exports_country_partner_year_2026-05-20.csv"
)
old_counts_path <- file.path(
  input_dir,
  "m2_goods_status_current_min_duration_sample_counts_2026-05-20.csv"
)
old_fit_path <- file.path(
  input_dir,
  "m2_goods_status_current_min5_risk_set_fect_fit_2026-05-20.rds"
)
old_session_path <- file.path(
  input_dir,
  "m2_goods_status_current_min_duration_session_info_2026-05-20.txt"
)
decision_path <- file.path(
  "quality_reports", "cross_country_sample",
  "2026-08-29_decisao_painel_full_join_tratamento_comercial.md"
)
review_paths <- Sys.glob(file.path(
  "quality_reports", "code_review",
  "2026-08-29_review_r_full_join_consecutive_round*.md"
))

required_inputs <- c(
  itpd_path,
  unga_path,
  old_full_panel_path,
  old_model_results_path,
  old_trade_aggregate_path,
  old_counts_path,
  old_fit_path,
  old_session_path,
  decision_path,
  "scripts/functions.R",
  "renv.lock",
  renv_activation_path,
  "scripts/diagnostics/reestimate_china_top_m2_goods_full_join_consecutive.R",
  review_paths
)
missing_inputs <- required_inputs[!file.exists(required_inputs)]
if (length(missing_inputs) > 0L) {
  stop(
    "Required input files are missing: ",
    paste(missing_inputs, collapse = ", "),
    call. = FALSE
  )
}

abort_if_duplicates_local <- function(data, keys, label) {
  duplicates <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(duplicates) > 0L) {
    example <- duplicates |>
      utils::head(5L) |>
      capture.output() |>
      paste(collapse = "\n")
    stop(
      "Duplicate keys in ", label, " for ",
      paste(keys, collapse = ", "), "\n", example,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

sha256_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
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

format_p_sentence <- function(x) {
  if (is.na(x)) {
    return("p = NA")
  }
  if (x < 0.001) {
    return("p < 0.001")
  }
  paste0("p = ", sprintf("%.3f", x))
}

collapse_years <- function(x) {
  x <- sort(unique(as.integer(x[!is.na(x)])))
  if (length(x) == 0L) {
    return("")
  }
  paste(x, collapse = ",")
}

message("Aggregating goods exports for every exporter in the raw ITPD-E source.")
duckdb_connection <- DBI::dbConnect(duckdb::duckdb())
on.exit(
  DBI::dbDisconnect(duckdb_connection, shutdown = TRUE),
  add = TRUE
)

itpd_sql_path <- as.character(DBI::dbQuoteString(
  duckdb_connection,
  normalizePath(itpd_path, mustWork = TRUE)
))
trade_query <- paste0(
  "SELECT upper(exporter_iso3) AS exporter_iso3, ",
  "upper(importer_iso3) AS importer_iso3, ",
  "try_cast(year AS INTEGER) AS year, ",
  "sum(coalesce(try_cast(trade AS DOUBLE), 0)) AS exports ",
  "FROM read_csv_auto(", itpd_sql_path, ", header = true) ",
  "WHERE try_cast(year AS INTEGER) BETWEEN ", min_year, " AND ", max_year, " ",
  "AND broad_sector IN ('Agriculture', 'Mining and Energy', 'Manufacturing') ",
  "AND exporter_iso3 IS NOT NULL AND importer_iso3 IS NOT NULL ",
  "AND upper(exporter_iso3) <> upper(importer_iso3) ",
  "GROUP BY 1, 2, 3 ",
  "HAVING sum(coalesce(try_cast(trade AS DOUBLE), 0)) > 0"
)
trade <- DBI::dbGetQuery(duckdb_connection, trade_query) |>
  tibble::as_tibble() |>
  dplyr::mutate(
    year = as.integer(year),
    exporter_iso3 = toupper(exporter_iso3),
    importer_iso3 = toupper(importer_iso3)
  ) |>
  dplyr::arrange(exporter_iso3, year, importer_iso3)

abort_if_duplicates_local(
  trade,
  c("exporter_iso3", "importer_iso3", "year"),
  "goods-export input"
)
if (any(!is.finite(trade$exports)) || any(trade$exports <= 0)) {
  stop("Goods exports must be finite and strictly positive.", call. = FALSE)
}

message("Validating the raw-source aggregate against the preserved subset.")
old_trade_aggregate <- readr::read_csv(
  old_trade_aggregate_path,
  show_col_types = FALSE
) |>
  dplyr::mutate(
    year = as.integer(year),
    exporter_iso3 = toupper(exporter_iso3),
    importer_iso3 = toupper(importer_iso3)
  )
abort_if_duplicates_local(
  old_trade_aggregate,
  c("exporter_iso3", "importer_iso3", "year"),
  "preserved goods-export subset"
)

trade_overlap <- old_trade_aggregate |>
  dplyr::left_join(
    trade |>
      dplyr::select(
        exporter_iso3,
        importer_iso3,
        year,
        exports_new = exports
      ),
    by = c("exporter_iso3", "importer_iso3", "year"),
    relationship = "one-to-one"
  ) |>
  dplyr::mutate(
    absolute_difference = abs(exports - exports_new),
    relative_difference = absolute_difference / pmax(abs(exports), 1)
  )

n_old_trade_keys_missing <- sum(is.na(trade_overlap$exports_new))
n_new_trade_keys <- nrow(trade) -
  (nrow(old_trade_aggregate) - n_old_trade_keys_missing)
max_trade_absolute_difference <- max(
  trade_overlap$absolute_difference,
  na.rm = TRUE
)
max_trade_relative_difference <- max(
  trade_overlap$relative_difference,
  na.rm = TRUE
)
trade_overlap_validation <- tibble::tibble(
  validation = c(
    "all_preserved_trade_keys_found_in_raw_aggregate",
    "overlapping_trade_values_match_within_1e_12_relative"
  ),
  passed = c(
    n_old_trade_keys_missing == 0L,
    max_trade_relative_difference <= 1e-12
  ),
  detail = c(
    paste0(
      "found=", nrow(old_trade_aggregate) - n_old_trade_keys_missing,
      "/", nrow(old_trade_aggregate),
      "; missing=", n_old_trade_keys_missing,
      "; new_keys=", n_new_trade_keys
    ),
    paste0(
      "max_abs=", format(max_trade_absolute_difference, scientific = TRUE),
      "; max_rel=", format(max_trade_relative_difference, scientific = TRUE)
    )
  )
)
if (!all(trade_overlap_validation$passed)) {
  stop("The raw-source trade aggregate failed overlap validation.",
       call. = FALSE)
}

message("Computing partner ranks and auditing exact top-rank ties.")
ranked_trade <- trade |>
  dplyr::group_by(exporter_iso3, year) |>
  dplyr::mutate(partner_rank = dplyr::min_rank(dplyr::desc(exports))) |>
  dplyr::ungroup()

top_partner <- ranked_trade |>
  dplyr::filter(partner_rank == 1L) |>
  dplyr::group_by(exporter_iso3, year) |>
  dplyr::summarise(
    n_top_ties = dplyr::n(),
    top_partner = dplyr::if_else(
      dplyr::n() == 1L,
      dplyr::first(importer_iso3),
      NA_character_
    ),
    top_export_value = max(exports),
    .groups = "drop"
  )

rank_china_usa <- ranked_trade |>
  dplyr::filter(importer_iso3 %in% c("CHN", "USA")) |>
  dplyr::select(
    exporter_iso3,
    year,
    partner = importer_iso3,
    partner_rank
  ) |>
  tidyr::pivot_wider(
    names_from = partner,
    values_from = partner_rank,
    names_prefix = "rank_"
  )

trade_rank <- top_partner |>
  dplyr::left_join(
    rank_china_usa,
    by = c("exporter_iso3", "year"),
    relationship = "one-to-one"
  ) |>
  dplyr::transmute(
    iso3c = exporter_iso3,
    year,
    trade_rank_row_present = TRUE,
    trade_rank_observed = n_top_ties == 1L,
    n_top_ties,
    top_partner,
    top_export_value,
    rank_CHN,
    rank_USA,
    china_top_status = dplyr::case_when(
      n_top_ties > 1L ~ NA_integer_,
      top_partner == "CHN" ~ 1L,
      !is.na(top_partner) ~ 0L,
      TRUE ~ NA_integer_
    )
  )

abort_if_duplicates_local(trade_rank, c("iso3c", "year"), "trade ranks")

message("Reading the raw UNGA ideal-point source.")
unga_raw <- data.table::fread(unga_path) |>
  janitor::clean_names() |>
  tibble::as_tibble() |>
  dplyr::mutate(
    year = as.integer(session + 1945L),
    iso3c = toupper(iso3c)
  ) |>
  dplyr::filter(
    year >= min_year,
    year <= max_year,
    !is.na(iso3c)
  )

abort_if_duplicates_local(unga_raw, c("iso3c", "year"), "raw UNGA data")

china_reference <- unga_raw |>
  dplyr::filter(iso3c == "CHN") |>
  dplyr::select(year, china_ideal = q50_percent_all)

abort_if_duplicates_local(
  china_reference,
  "year",
  "China ideal-point reference"
)

unga <- unga_raw |>
  dplyr::select(
    iso3c,
    year,
    country_name_source = countryname,
    ideal_point_all,
    q50_percent_all,
    us_agree,
    china_agree
  ) |>
  dplyr::left_join(
    china_reference,
    by = "year",
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(
    abs_distance_china = abs(q50_percent_all - china_ideal),
    unga_row_present = TRUE,
    outcome_observed = !is.na(abs_distance_china)
  )

abort_if_duplicates_local(unga, c("iso3c", "year"), "prepared UNGA data")

message("Creating the full union and explicit country-year spine.")
source_union <- dplyr::full_join(
  trade_rank,
  unga,
  by = c("iso3c", "year"),
  relationship = "one-to-one"
) |>
  dplyr::filter(iso3c != "CHN")

country_universe <- source_union |>
  dplyr::distinct(iso3c) |>
  dplyr::arrange(iso3c)

country_year_spine <- tidyr::expand_grid(
  iso3c = country_universe$iso3c,
  year = seq.int(min_year, max_year)
)

master_panel <- country_year_spine |>
  dplyr::left_join(
    source_union,
    by = c("iso3c", "year"),
    relationship = "one-to-one"
  ) |>
  dplyr::mutate(
    trade_rank_row_present = dplyr::coalesce(
      trade_rank_row_present,
      FALSE
    ),
    trade_rank_observed = dplyr::coalesce(trade_rank_observed, FALSE),
    unga_row_present = dplyr::coalesce(unga_row_present, FALSE),
    outcome_observed = dplyr::coalesce(outcome_observed, FALSE),
    country_name_standard = countrycode::countrycode(
      iso3c,
      "iso3c",
      "country.name",
      warn = FALSE
    ),
    country_name = dplyr::coalesce(
      country_name_standard,
      country_name_source,
      iso3c
    )
  ) |>
  dplyr::group_by(iso3c) |>
  tidyr::fill(country_name, .direction = "downup") |>
  dplyr::arrange(year, .by_group = TRUE) |>
  dplyr::mutate(
    previous_china_top_status = dplyr::lag(china_top_status),
    china_top_period_start = china_top_status %in% 1L &
      !(dplyr::lag(china_top_status) %in% 1L),
    china_top_period_id_raw = cumsum(china_top_period_start),
    china_top_period_id = dplyr::if_else(
      china_top_status %in% 1L,
      china_top_period_id_raw,
      NA_integer_
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::select(
    iso3c,
    country_name,
    year,
    trade_rank_row_present,
    trade_rank_observed,
    n_top_ties,
    top_partner,
    top_export_value,
    rank_CHN,
    rank_USA,
    china_top_status,
    previous_china_top_status,
    china_top_period_start,
    china_top_period_id,
    unga_row_present,
    outcome_observed,
    ideal_point_all,
    q50_percent_all,
    china_ideal,
    abs_distance_china,
    us_agree,
    china_agree
  )

abort_if_duplicates_local(master_panel, c("iso3c", "year"), "master panel")

expected_master_rows <- nrow(country_universe) * (max_year - min_year + 1L)
if (nrow(master_panel) != expected_master_rows) {
  stop("The master panel is not a complete country-year grid.", call. = FALSE)
}

message("Identifying consecutive China-top periods from trade ranks only.")
period_summary <- master_panel |>
  dplyr::filter(
    china_top_status %in% 1L,
    !is.na(china_top_period_id)
  ) |>
  dplyr::group_by(iso3c, china_top_period_id) |>
  dplyr::summarise(
    country_name = dplyr::first(country_name),
    period_entry_year = min(year),
    period_exit_year = max(year),
    duration_calendar_years = dplyr::n_distinct(year),
    calendar_span_years = period_exit_year - period_entry_year + 1L,
    prior_year = period_entry_year - 1L,
    prior_china_top_status = dplyr::first(previous_china_top_status),
    eligible_entry = period_entry_year >= min_entry_year &
      prior_china_top_status %in% 0L,
    qualifies_min5 = eligible_entry &
      duration_calendar_years >= min_duration_years,
    .groups = "drop"
  ) |>
  dplyr::mutate(
    consecutive_calendar_years =
      duration_calendar_years == calendar_span_years
  ) |>
  dplyr::arrange(iso3c, period_entry_year)

if (any(!period_summary$consecutive_calendar_years)) {
  stop("A China-top period contains a calendar gap.", call. = FALSE)
}

qualifying_periods <- period_summary |>
  dplyr::filter(qualifies_min5) |>
  dplyr::select(iso3c, china_top_period_id) |>
  dplyr::mutate(qualifying_period = TRUE)

master_panel <- master_panel |>
  dplyr::left_join(
    qualifying_periods,
    by = c("iso3c", "china_top_period_id"),
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(
    qualifying_period = dplyr::coalesce(qualifying_period, FALSE),
    china_top = dplyr::case_when(
      is.na(china_top_status) ~ NA_integer_,
      china_top_status == 1L & qualifying_period ~ 1L,
      TRUE ~ 0L
    )
  )

unit_period_counts <- period_summary |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    n_observed_china_top_periods = dplyr::n(),
    n_qualifying_periods = sum(qualifies_min5),
    first_qualifying_entry = ifelse(
      any(qualifies_min5),
      min(period_entry_year[qualifies_min5]),
      NA_integer_
    ),
    longest_china_top_period = max(duration_calendar_years),
    total_qualifying_treated_years = sum(
      duration_calendar_years[qualifies_min5]
    ),
    .groups = "drop"
  )

unit_summary <- master_panel |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    country_name = dplyr::first(country_name),
    trade_rank_years = sum(trade_rank_observed),
    outcome_years = sum(outcome_observed),
    ever_observed_china_top = any(china_top_status %in% 1L),
    unknown_trade_rank_years = sum(is.na(china_top_status)),
    .groups = "drop"
  ) |>
  dplyr::left_join(
    unit_period_counts,
    by = "iso3c",
    relationship = "one-to-one"
  ) |>
  dplyr::mutate(
    dplyr::across(
      c(
        n_observed_china_top_periods,
        n_qualifying_periods,
        longest_china_top_period,
        total_qualifying_treated_years
      ),
      ~ dplyr::coalesce(.x, 0)
    ),
    country_role = dplyr::case_when(
      n_qualifying_periods > 0L ~ "treated_qualifying",
      trade_rank_years == 0L ~ "excluded_no_observed_trade_rank",
      !ever_observed_china_top ~ "never_observed_china_top_control",
      TRUE ~ "excluded_nonqualifying_china_top"
    ),
    first_treat = dplyr::if_else(
      country_role == "treated_qualifying",
      as.numeric(first_qualifying_entry),
      0
    )
  ) |>
  dplyr::arrange(country_role, iso3c)

master_panel <- master_panel |>
  dplyr::left_join(
    unit_summary |>
      dplyr::select(
        iso3c,
        country_role,
        first_qualifying_entry,
        first_treat,
        n_qualifying_periods
      ),
    by = "iso3c",
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(
    main_risk_set_eligible = dplyr::case_when(
      country_role == "never_observed_china_top_control" &
        china_top_status %in% 0L ~ TRUE,
      country_role == "treated_qualifying" & qualifying_period ~ TRUE,
      country_role == "treated_qualifying" &
        year < first_qualifying_entry &
        china_top_status %in% 0L ~ TRUE,
      TRUE ~ FALSE
    ),
    main_estimation_candidate = main_risk_set_eligible &
      outcome_observed &
      !is.na(china_top)
  )

candidate_panel_pre_support <- master_panel |>
  dplyr::filter(main_estimation_candidate) |>
  dplyr::group_by(iso3c) |>
  dplyr::mutate(
    untreated_observations = sum(china_top == 0L),
    treated_observations = sum(china_top == 1L)
  ) |>
  dplyr::ungroup()

unit_estimator_support <- candidate_panel_pre_support |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    untreated_observations = dplyr::first(untreated_observations),
    treated_observations = dplyr::first(treated_observations),
    .groups = "drop"
  )

candidate_panel <- candidate_panel_pre_support |>
  dplyr::filter(untreated_observations >= 5L)

panel_max <- max(candidate_panel$year, na.rm = TRUE)
estimable_treated <- candidate_panel |>
  dplyr::filter(
    country_role == "treated_qualifying",
    first_treat > 0,
    first_treat < panel_max,
    china_top == 1L
  ) |>
  dplyr::distinct(iso3c) |>
  dplyr::pull(iso3c)

estimation_keys <- candidate_panel |>
  dplyr::filter(
    country_role == "never_observed_china_top_control" |
      iso3c %in% estimable_treated
  ) |>
  dplyr::select(iso3c, year) |>
  dplyr::mutate(main_estimation_included = TRUE)

master_panel <- master_panel |>
  dplyr::left_join(
    unit_estimator_support,
    by = "iso3c",
    relationship = "many-to-one"
  ) |>
  dplyr::left_join(
    estimation_keys,
    by = c("iso3c", "year"),
    relationship = "one-to-one"
  ) |>
  dplyr::mutate(
    untreated_observations = dplyr::coalesce(untreated_observations, 0L),
    treated_observations = dplyr::coalesce(treated_observations, 0L),
    main_estimation_included = dplyr::coalesce(
      main_estimation_included,
      FALSE
    ),
    row_status = dplyr::case_when(
      main_estimation_included ~ "included_estimation",
      main_estimation_candidate & untreated_observations < 5L ~
        "excluded_fewer_than_five_untreated_outcomes",
      main_estimation_candidate &
        country_role == "treated_qualifying" &
        !iso3c %in% estimable_treated ~ "excluded_treated_not_estimable",
      main_risk_set_eligible & !outcome_observed ~ "risk_set_missing_outcome",
      country_role == "excluded_no_observed_trade_rank" ~
        "country_no_observed_trade_rank",
      is.na(china_top_status) ~ "unknown_trade_rank",
      country_role == "excluded_nonqualifying_china_top" ~
        "country_nonqualifying_china_top",
      country_role == "treated_qualifying" &
        china_top_status == 1L &
        !qualifying_period ~ "nonqualifying_china_top_period",
      country_role == "treated_qualifying" &
        year >= first_qualifying_entry &
        china_top_status == 0L ~ "post_entry_off_status",
      TRUE ~ "outside_main_risk_set"
    )
  )

estimation_panel <- master_panel |>
  dplyr::filter(main_estimation_included) |>
  dplyr::mutate(
    country_id = as.integer(as.factor(iso3c)),
    id = country_id
  ) |>
  dplyr::arrange(country_id, year) |>
  dplyr::select(
    iso3c,
    country_name,
    country_id,
    id,
    year,
    abs_distance_china,
    china_top,
    china_top_status,
    qualifying_period,
    first_treat,
    country_role,
    untreated_observations,
    treated_observations
  ) |>
  as.data.frame()

abort_if_duplicates_local(
  estimation_panel,
  c("iso3c", "year"),
  "corrected estimation panel"
)

if (any(is.na(estimation_panel$abs_distance_china)) ||
    any(is.na(estimation_panel$china_top))) {
  stop("The estimation panel contains missing outcome or treatment.", call. = FALSE)
}
if (any(!estimation_panel$china_top %in% c(0L, 1L))) {
  stop("Treatment must be binary in the estimation panel.", call. = FALSE)
}
if (nrow(estimation_panel) != sum(master_panel$main_estimation_included)) {
  stop("Final row flags do not reproduce the estimation panel.", call. = FALSE)
}
if (any(is.na(master_panel$china_top) !=
        is.na(master_panel$china_top_status))) {
  stop("Treatment missingness must exactly follow trade-status missingness.",
       call. = FALSE)
}
if (any(master_panel$qualifying_period &
        master_panel$china_top_status != 1L, na.rm = TRUE)) {
  stop("A qualifying period contains a non-China-top trade status.",
       call. = FALSE)
}
if (any(period_summary$qualifies_min5 &
        (!period_summary$eligible_entry |
         period_summary$duration_calendar_years < min_duration_years))) {
  stop("A qualifying period violates the entry or duration rule.",
       call. = FALSE)
}

cod_2021 <- master_panel |>
  dplyr::filter(iso3c == "COD", year == 2021L)
if (
  nrow(cod_2021) != 1L ||
    !identical(cod_2021$china_top_status, 1L) ||
    !identical(cod_2021$china_top, 1L) ||
    !is.na(cod_2021$abs_distance_china) ||
    !isTRUE(cod_2021$main_risk_set_eligible) ||
    isTRUE(cod_2021$main_estimation_candidate) ||
    isTRUE(cod_2021$main_estimation_included)
) {
  stop("COD 2021 failed the treatment/missing-outcome validation.", call. = FALSE)
}

message("Reconstructing the previous analytic sample for row-level comparison.")
old_full_panel <- readr::read_csv(
  old_full_panel_path,
  show_col_types = FALSE
) |>
  as.data.frame()

old_bundle <- make_status_current_panel_bundle(
  old_full_panel,
  duration_thresholds = min_duration_years,
  min_entry_year = min_entry_year
)
old_estimation_panel <- old_bundle$panels[[as.character(min_duration_years)]][[
  "risk_set_restricted"
]]

old_counts_reference <- readr::read_csv(
  old_counts_path,
  show_col_types = FALSE
) |>
  dplyr::filter(
    min_duration_years == 5L,
    sample == "risk_set_restricted"
  )

if (
  nrow(old_counts_reference) != 1L ||
    nrow(old_estimation_panel) != old_counts_reference$n_obs
) {
  stop("The reconstructed old sample does not match its archived count.",
       call. = FALSE)
}

message("Validating the reconstructed old sample against its preserved fit.")
old_session_text <- readLines(old_session_path, warn = FALSE)
if (!any(grepl("fect_2\\.1\\.0", old_session_text))) {
  stop("The archived model session does not document fect 2.1.0.",
       call. = FALSE)
}
old_fit <- readRDS(old_fit_path)
old_fit_index <- cbind(
  match(old_estimation_panel$year, old_fit$rawtime),
  match(old_estimation_panel$country_id, old_fit$id)
)
if (anyNA(old_fit_index)) {
  stop("The old reconstructed panel cannot be indexed in the preserved fit.",
       call. = FALSE)
}

old_outcome_from_fit <- as.numeric(old_fit$Y.dat[old_fit_index])
old_treatment_from_fit <- as.numeric(old_fit$D.dat[old_fit_index])
old_outcome_max_abs_difference <- max(
  abs(as.numeric(old_estimation_panel$abs_distance_china) -
      old_outcome_from_fit)
)
old_fit_validation <- tibble::tibble(
  validation = c(
    "all_reconstructed_rows_observed_in_old_fit",
    "old_fit_observation_count_matches",
    "old_outcome_matches_within_1e_12",
    "old_treatment_matches_exactly"
  ),
  passed = c(
    all(old_fit$I.dat[old_fit_index] == 1),
    sum(old_fit$I.dat) == nrow(old_estimation_panel),
    isTRUE(all.equal(
      as.numeric(old_estimation_panel$abs_distance_china),
      old_outcome_from_fit,
      tolerance = 1e-12
    )),
    identical(
      as.numeric(old_estimation_panel$china_top),
      old_treatment_from_fit
    )
  ),
  detail = c(
    NA_character_,
    paste0("n=", nrow(old_estimation_panel)),
    paste0("max_abs_difference=", format(
      old_outcome_max_abs_difference,
      scientific = TRUE
    )),
    NA_character_
  )
)
if (!all(old_fit_validation$passed)) {
  stop("The reconstructed old sample failed preserved-fit validation.",
       call. = FALSE)
}

row_comparison <- dplyr::full_join(
  old_estimation_panel |>
    dplyr::select(
      iso3c,
      year,
      old_treatment = china_top,
      old_outcome = abs_distance_china
    ),
  estimation_panel |>
    dplyr::select(
      iso3c,
      year,
      new_treatment = china_top,
      new_outcome = abs_distance_china
    ),
  by = c("iso3c", "year"),
  relationship = "one-to-one"
) |>
  dplyr::left_join(
    master_panel |>
      dplyr::select(
        iso3c,
        year,
        master_treatment = china_top,
        master_china_top_status = china_top_status,
        master_country_role = country_role,
        master_row_status = row_status
      ),
    by = c("iso3c", "year"),
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(
    row_change = dplyr::case_when(
      is.na(old_treatment) & !is.na(new_treatment) ~ "added_to_estimation",
      !is.na(old_treatment) & is.na(new_treatment) ~ "removed_from_estimation",
      old_treatment != new_treatment ~ "treatment_changed",
      TRUE ~ "unchanged"
    )
  ) |>
  dplyr::arrange(row_change, iso3c, year)

run_fixed_r_ife <- function(panel, fixed_r, nboots) {
  set.seed(42)
  fect_data <- prepare_fect_data(
    panel,
    fml = abs_distance_china ~ china_top
  )
  fect::fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "ife",
    force = "two-way",
    se = TRUE,
    nboots = nboots,
    parallel = FALSE,
    CV = FALSE,
    r = fixed_r
  )
}

message("Estimating the corrected main IFE model with ", args$nboots,
        " bootstrap repetitions.")
fit_timing <- system.time({
  fit <- run_fect_analysis(
    estimation_panel,
    method = "ife",
    nboots = args$nboots,
    fml = abs_distance_china ~ china_top
  )
})

new_model <- summarize_fect_model(
  fit,
  estimation_panel,
  fml = abs_distance_china ~ china_top
) |>
  tibble::as_tibble() |>
  dplyr::mutate(
    coding = "Full union + consecutive trade-defined treatment",
    run_label = args$run_label,
    nboots = args$nboots,
    elapsed_seconds = as.numeric(fit_timing[["elapsed"]]),
    .before = att
  )

message("Estimating fixed-r sensitivity models (r = 1 and r = 2).")
fixed_r_runs <- lapply(c(1L, 2L), function(fixed_r) {
  fixed_timing <- system.time({
    fixed_fit <- run_fixed_r_ife(
      estimation_panel,
      fixed_r = fixed_r,
      nboots = args$nboots
    )
  })
  fixed_summary <- summarize_fect_model(
    fixed_fit,
    estimation_panel,
    fml = abs_distance_china ~ china_top
  ) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      specified_r = fixed_r,
      run_label = args$run_label,
      nboots = args$nboots,
      elapsed_seconds = as.numeric(fixed_timing[["elapsed"]]),
      .before = att
    )
  list(fit = fixed_fit, summary = fixed_summary)
})
names(fixed_r_runs) <- c("1", "2")
fixed_r_fits <- lapply(fixed_r_runs, `[[`, "fit")
fixed_r_results <- lapply(fixed_r_runs, `[[`, "summary") |>
  dplyr::bind_rows()

old_model <- readr::read_csv(
  old_model_results_path,
  show_col_types = FALSE
) |>
  dplyr::filter(
    min_duration_years == 5L,
    specification == "risk_set_restricted"
  )

if (nrow(old_model) != 1L) {
  stop("Archived main-model comparison row is not unique.", call. = FALSE)
}

old_fit_summary <- fect_att_summary(old_fit)
old_estimation_unit_counts <- old_estimation_panel |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(ever_treated = any(china_top == 1L), .groups = "drop")
old_fit_model_validation <- tibble::tibble(
  statistic = c(
    "ATT", "Bootstrap SE", "Selected latent factors", "Observations",
    "Countries", "Treated countries", "Control countries",
    "Treated country-years"
  ),
  archived_value = c(
    old_model$att,
    old_model$se,
    old_model$r_cv,
    old_model$n_obs,
    old_model$n_countries,
    old_model$n_treated,
    old_model$n_control,
    old_model$n_treated_country_years
  ),
  reconstructed_value = c(
    old_fit_summary$att,
    old_fit_summary$se,
    old_fit_summary$r_cv,
    nrow(old_estimation_panel),
    dplyr::n_distinct(old_estimation_panel$iso3c),
    sum(old_estimation_unit_counts$ever_treated),
    sum(!old_estimation_unit_counts$ever_treated),
    sum(old_estimation_panel$china_top == 1L)
  )
) |>
  dplyr::mutate(
    absolute_difference = abs(archived_value - reconstructed_value),
    passed = absolute_difference <= 1e-12
  )
if (!all(old_fit_model_validation$passed)) {
  stop("Archived old-model numbers do not match the preserved fit/panel.",
       call. = FALSE)
}

model_comparison <- tibble::tibble(
  statistic = c(
    "ATT", "Bootstrap SE", "CI lower", "CI upper", "p-value",
    "Selected latent factors", "Observations", "Countries",
    "Treated countries", "Control countries", "Treated country-years"
  ),
  previous = c(
    old_model$att,
    old_model$se,
    old_model$ci_lo,
    old_model$ci_hi,
    old_model$p,
    old_model$r_cv,
    old_model$n_obs,
    old_model$n_countries,
    old_model$n_treated,
    old_model$n_control,
    old_model$n_treated_country_years
  ),
  corrected = c(
    new_model$att,
    new_model$se,
    new_model$ci_lo,
    new_model$ci_hi,
    new_model$p,
    new_model$r_cv,
    new_model$n_obs,
    new_model$n_countries,
    new_model$n_treated,
    new_model$n_control,
    new_model$n_treated_country_years
  )
) |>
  dplyr::mutate(difference = corrected - previous)

dynamic_results <- tibble::tibble(
  event_time = fit$time,
  count = fit$count,
  att = as.numeric(fit$est.att[, 1]),
  se = as.numeric(fit$est.att[, 2])
) |>
  dplyr::mutate(
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se
  ) |>
  dplyr::arrange(event_time)

row_audit <- master_panel |>
  dplyr::count(row_status, name = "n_country_years") |>
  dplyr::arrange(dplyr::desc(n_country_years), row_status)

if (sum(row_audit$n_country_years) != nrow(master_panel) ||
    sum(row_audit$n_country_years[row_audit$row_status ==
                                   "included_estimation"]) !=
      nrow(estimation_panel)) {
  stop("The final row-status audit does not reconcile to the panels.",
       call. = FALSE)
}

change_reason_audit <- row_comparison |>
  dplyr::filter(row_change != "unchanged") |>
  dplyr::count(row_change, master_row_status, name = "n_country_years") |>
  dplyr::arrange(row_change, dplyr::desc(n_country_years), master_row_status)

country_comparison <- dplyr::full_join(
  old_estimation_panel |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      old_country_name = dplyr::first(country_name),
      old_in_estimation = TRUE,
      old_n_obs = dplyr::n(),
      old_ever_treated = any(china_top == 1L),
      old_treated_years = sum(china_top == 1L),
      old_first_treat = ifelse(
        any(china_top == 1L),
        min(year[china_top == 1L]),
        NA_integer_
      ),
      .groups = "drop"
    ),
  estimation_panel |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      new_country_name = dplyr::first(country_name),
      new_in_estimation = TRUE,
      new_n_obs = dplyr::n(),
      new_ever_treated = any(china_top == 1L),
      new_treated_years = sum(china_top == 1L),
      new_first_treat = ifelse(
        any(china_top == 1L),
        min(year[china_top == 1L]),
        NA_integer_
      ),
      .groups = "drop"
    ),
  by = "iso3c",
  relationship = "one-to-one"
) |>
  dplyr::mutate(
    country_name = dplyr::coalesce(new_country_name, old_country_name),
    old_in_estimation = dplyr::coalesce(old_in_estimation, FALSE),
    new_in_estimation = dplyr::coalesce(new_in_estimation, FALSE),
    classification_change = dplyr::case_when(
      !old_in_estimation & new_in_estimation ~ "country_added",
      old_in_estimation & !new_in_estimation ~ "country_removed",
      old_ever_treated != new_ever_treated ~ "treated_status_changed",
      old_treated_years != new_treated_years ~ "treated_year_count_changed",
      old_first_treat != new_first_treat ~ "first_treatment_changed",
      old_n_obs != new_n_obs ~ "estimation_row_count_changed",
      TRUE ~ "unchanged"
    )
  ) |>
  dplyr::arrange(classification_change, iso3c)

trade_aggregate_path <- file.path(
  processed_dir,
  paste0(prefix, "_goods_exports_country_partner_year.csv")
)
risk_set_path <- file.path(
  processed_dir,
  paste0(prefix, "_main_risk_set_master.csv")
)
estimation_path <- file.path(
  processed_dir,
  paste0(prefix, "_main_estimation_panel.csv")
)
period_path <- file.path(processed_dir, paste0(prefix, "_period_summary.csv"))
unit_path <- file.path(processed_dir, paste0(prefix, "_unit_summary.csv"))
row_audit_path <- file.path(processed_dir, paste0(prefix, "_row_audit.csv"))
change_reason_path <- file.path(
  processed_dir,
  paste0(prefix, "_change_reason_audit.csv")
)
row_comparison_path <- file.path(
  processed_dir,
  paste0(prefix, "_analytic_row_comparison.csv")
)
country_comparison_path <- file.path(
  processed_dir,
  paste0(prefix, "_country_comparison.csv")
)
model_path <- file.path(processed_dir, paste0(prefix, "_model_result.csv"))
model_comparison_path <- file.path(
  processed_dir,
  paste0(prefix, "_model_comparison.csv")
)
fixed_r_path <- file.path(
  processed_dir,
  paste0(prefix, "_fixed_r_sensitivity.csv")
)
dynamic_path <- file.path(processed_dir, paste0(prefix, "_dynamic_results.csv"))
fit_path <- file.path(processed_dir, paste0(prefix, "_fect_fit.rds"))
fixed_r1_fit_path <- file.path(
  processed_dir,
  paste0(prefix, "_fect_fit_fixed_r1.rds")
)
fixed_r2_fit_path <- file.path(
  processed_dir,
  paste0(prefix, "_fect_fit_fixed_r2.rds")
)
old_fit_validation_path <- file.path(
  processed_dir,
  paste0(prefix, "_old_fit_validation.csv")
)
old_fit_model_validation_path <- file.path(
  processed_dir,
  paste0(prefix, "_old_fit_model_validation.csv")
)
trade_overlap_validation_path <- file.path(
  processed_dir,
  paste0(prefix, "_trade_overlap_validation.csv")
)
session_path <- file.path(processed_dir, paste0(prefix, "_session_info.txt"))
manifest_path <- file.path(processed_dir, paste0(prefix, "_manifest.csv"))

message("Writing auditable outputs.")
readr::write_csv(trade, trade_aggregate_path, na = "")
readr::write_csv(master_panel, master_path, na = "")
readr::write_csv(
  master_panel |>
    dplyr::filter(main_risk_set_eligible),
  risk_set_path,
  na = ""
)
readr::write_csv(estimation_panel, estimation_path, na = "")
readr::write_csv(period_summary, period_path, na = "")
readr::write_csv(unit_summary, unit_path, na = "")
readr::write_csv(row_audit, row_audit_path, na = "")
readr::write_csv(change_reason_audit, change_reason_path, na = "")
readr::write_csv(row_comparison, row_comparison_path, na = "")
readr::write_csv(country_comparison, country_comparison_path, na = "")
readr::write_csv(new_model, model_path, na = "")
readr::write_csv(model_comparison, model_comparison_path, na = "")
readr::write_csv(fixed_r_results, fixed_r_path, na = "")
readr::write_csv(dynamic_results, dynamic_path, na = "")
readr::write_csv(old_fit_validation, old_fit_validation_path, na = "")
readr::write_csv(
  old_fit_model_validation,
  old_fit_model_validation_path,
  na = ""
)
readr::write_csv(
  trade_overlap_validation,
  trade_overlap_validation_path,
  na = ""
)
saveRDS(fit, fit_path, version = 3)
saveRDS(fixed_r_fits[["1"]], fixed_r1_fit_path, version = 3)
saveRDS(fixed_r_fits[["2"]], fixed_r2_fit_path, version = 3)
writeLines(capture.output(sessionInfo()), session_path, useBytes = TRUE)

output_paths <- c(
  trade_aggregate_path,
  master_path,
  risk_set_path,
  estimation_path,
  period_path,
  unit_path,
  row_audit_path,
  change_reason_path,
  row_comparison_path,
  country_comparison_path,
  model_path,
  model_comparison_path,
  fixed_r_path,
  dynamic_path,
  fit_path,
  fixed_r1_fit_path,
  fixed_r2_fit_path,
  old_fit_validation_path,
  old_fit_model_validation_path,
  trade_overlap_validation_path,
  session_path
)

changed_rows <- row_comparison |>
  dplyr::filter(row_change != "unchanged")
changed_countries <- country_comparison |>
  dplyr::filter(classification_change != "unchanged")
countries_with_any_row_change <- changed_rows |>
  dplyr::distinct(iso3c)
n_countries_fully_removed <- sum(
  country_comparison$classification_change == "country_removed"
)

comparison_lines <- vapply(seq_len(nrow(model_comparison)), function(i) {
  paste0(
    "| ", model_comparison$statistic[[i]],
    " | ", fmt(model_comparison$previous[[i]], 6L),
    " | ", fmt(model_comparison$corrected[[i]], 6L),
    " | ", fmt(model_comparison$difference[[i]], 6L), " |"
  )
}, character(1))

row_audit_lines <- vapply(seq_len(nrow(row_audit)), function(i) {
  paste0(
    "| ", row_audit$row_status[[i]],
    " | ", row_audit$n_country_years[[i]], " |"
  )
}, character(1))

change_reason_lines <- vapply(seq_len(nrow(change_reason_audit)), function(i) {
  paste0(
    "| ", change_reason_audit$row_change[[i]],
    " | ", change_reason_audit$master_row_status[[i]],
    " | ", change_reason_audit$n_country_years[[i]], " |"
  )
}, character(1))

fixed_r_lines <- vapply(seq_len(nrow(fixed_r_results)), function(i) {
  paste0(
    "| ", fixed_r_results$specified_r[[i]],
    " | ", fmt(fixed_r_results$att[[i]], 6L),
    " | ", fmt(fixed_r_results$se[[i]], 6L),
    " | ", fmt(fixed_r_results$ci_lo[[i]], 6L),
    " | ", fmt(fixed_r_results$ci_hi[[i]], 6L),
    " | ", format_p(fixed_r_results$p[[i]]), " |"
  )
}, character(1))

old_fit_validation_lines <- vapply(
  seq_len(nrow(old_fit_validation)),
  function(i) {
    paste0(
      "| ", old_fit_validation$validation[[i]],
      " | ", ifelse(old_fit_validation$passed[[i]], "PASS", "FAIL"),
      " | ", dplyr::coalesce(old_fit_validation$detail[[i]], ""), " |"
    )
  },
  character(1)
)

trade_overlap_validation_lines <- vapply(
  seq_len(nrow(trade_overlap_validation)),
  function(i) {
    paste0(
      "| ", trade_overlap_validation$validation[[i]],
      " | ", ifelse(trade_overlap_validation$passed[[i]], "PASS", "FAIL"),
      " | ", trade_overlap_validation$detail[[i]], " |"
    )
  },
  character(1)
)

old_fit_model_validation_lines <- vapply(
  seq_len(nrow(old_fit_model_validation)),
  function(i) {
    paste0(
      "| ", old_fit_model_validation$statistic[[i]],
      " | ", fmt(old_fit_model_validation$archived_value[[i]], 12L),
      " | ", fmt(old_fit_model_validation$reconstructed_value[[i]], 12L),
      " | ", ifelse(old_fit_model_validation$passed[[i]], "PASS", "FAIL"),
      " |"
    )
  },
  character(1)
)

source_presence <- source_union |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    present_in_trade = any(trade_rank_row_present %in% TRUE),
    present_in_unga = any(unga_row_present %in% TRUE),
    .groups = "drop"
  )
changed_country_codes <- paste(
  sort(countries_with_any_row_change$iso3c),
  collapse = ", "
)

report_lines <- c(
  "# Relatório: painel completo e tratamento comercial consecutivo",
  "",
  paste0("**Gerado em:** ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("**Execução:** `", args$run_label, "`; ", args$nboots,
         " repetições bootstrap"),
  paste0("**Carga inferencial:** três ajustes × ", args$nboots,
         " = ", 3L * args$nboots, " replicações bootstrap no total"),
  paste0("**Versão do estimador:** `fect ",
         as.character(packageVersion("fect")), "` (travada por `renv.lock`)"),
  "",
  "## Resumo executivo",
  "",
  paste0(
    "A recodificação constrói primeiro a união das fontes comercial e da AGNU, ",
    "completa a grade país × ano e define o tratamento apenas a partir de ",
    "rankings comerciais consecutivos. A amostra de estimação é criada depois, ",
    "sem converter desfechos ausentes em tratamento ausente."
  ),
  "",
  paste0(
    "Na especificação IFE principal, o ATT corrigido é ", fmt(new_model$att),
    " (SE bootstrap = ", fmt(new_model$se), ", IC 95% [",
    fmt(new_model$ci_lo), ", ", fmt(new_model$ci_hi), "], ",
    format_p_sentence(new_model$p), ", r* = ", new_model$r_cv, ")."
  ),
  paste0(
    "O ATT arquivado é ", fmt(old_model$att), "; portanto, a diferença de ",
    fmt(new_model$att - old_model$att, 6L),
    " é a comparação pertinente sob a mesma versão do estimador."
  ),
  "",
  "## Decisão implementada",
  "",
  paste0("A decisão completa está em `", decision_path, "`. A regra exige ",
         "um ano anterior observado em que a China não é número 1, seguido de ",
         "pelo menos cinco anos-calendário consecutivos em que ela permanece ",
         "como maior destino de exportações de bens."),
  "A amostra final exige ainda pelo menos cinco observações do desfecho em ",
  "anos não tratados por país; essa restrição de suporte adotada na especificação é ",
  "aplicada depois da construção do conjunto de risco e recebe flag própria.",
  "",
  "## Validações do banco",
  "",
  paste0("- Painel mestre: ", nrow(master_panel), " país-anos e ",
         dplyr::n_distinct(master_panel$iso3c), " países."),
  paste0("- Universo na fonte bruta: ",
         sum(source_presence$present_in_trade), " países com comércio e ",
         sum(source_presence$present_in_unga), " países com linha na AGNU; ",
         sum(source_presence$present_in_trade &
               !source_presence$present_in_unga),
         " aparecem apenas no comércio no intervalo."),
  paste0("- Empates exatos no primeiro lugar: ",
         sum(master_panel$n_top_ties > 1L, na.rm = TRUE), "."),
  paste0("- Períodos China-top qualificados: ",
         sum(period_summary$qualifies_min5), "."),
  paste0("- Amostra de estimação: ", nrow(estimation_panel), " país-anos, ",
         dplyr::n_distinct(estimation_panel$iso3c), " países e ",
         sum(estimation_panel$china_top == 1L), " país-anos tratados."),
  paste0("- Linhas da amostra antiga alteradas: ", nrow(changed_rows), "."),
  paste0("- Países com ao menos uma linha de estimação alterada: ",
         nrow(countries_with_any_row_change), " (", changed_country_codes,
         ")."),
  paste0("- Países inteiramente removidos da estimação: ",
         n_countries_fully_removed, "."),
  "",
  "**Tabela 1. Comparação entre a especificação vigente e a corrigida.**",
  "",
  "| Estatística | Vigente | Corrigida | Diferença |",
  "|---|---:|---:|---:|",
  comparison_lines,
  "",
  "*Nota:* ambas as colunas usam IFE sem covariáveis e `fect` 2.1.0. A coluna ",
  "vigente vem do artefato preservado de 10.000 bootstraps; a corrigida usa o ",
  "número de repetições informado no cabeçalho desta execução.",
  "",
  "**Tabela 2. Sensibilidade do resultado corrigido ao número fixo de fatores.**",
  "",
  "| Fatores fixos | ATT | SE | IC inferior | IC superior | p |",
  "|---:|---:|---:|---:|---:|---:|",
  fixed_r_lines,
  "",
  paste0(
    "A magnitude depende da dimensão fatorial: com `r = 1`, o ATT é ",
    fmt(fixed_r_results$att[fixed_r_results$specified_r == 1L]),
    "; com `r = 2`, é ",
    fmt(fixed_r_results$att[fixed_r_results$specified_r == 2L]),
    ". A validação cruzada escolhe dois fatores tanto no resultado vigente ",
    "quanto no corrigido. Essa sensibilidade pertence à especificação do ",
    "estimador, não foi criada pela recodificação."
  ),
  paste0(
    "Tempos dos ajustes: CV = ", fmt(new_model$elapsed_seconds, 1L),
    " s; `r = 1` = ",
    fmt(fixed_r_results$elapsed_seconds[
      fixed_r_results$specified_r == 1L
    ], 1L),
    " s; `r = 2` = ",
    fmt(fixed_r_results$elapsed_seconds[
      fixed_r_results$specified_r == 2L
    ], 1L),
    " s; total = ",
    fmt(new_model$elapsed_seconds + sum(fixed_r_results$elapsed_seconds), 1L),
    " s."
  ),
  "",
  "**Tabela 3. Destino dos país-anos no painel mestre corrigido.**",
  "",
  "| Situação | País-anos |",
  "|---|---:|",
  row_audit_lines,
  "",
  "**Tabela 4. Alterações em relação à amostra vigente, por motivo.**",
  "",
  "| Alteração | Situação no painel corrigido | País-anos |",
  "|---|---|---:|",
  change_reason_lines,
  "",
  "**Tabela 5. Validação da reconstrução da amostra antiga contra o fit preservado.**",
  "",
  "| Validação | Resultado | Detalhe |",
  "|---|---|---|",
  old_fit_validation_lines,
  "",
  "**Tabela 6. Validação dos números antigos contra o fit e o painel preservados.**",
  "",
  "| Estatística | Arquivada | Reconstruída | Resultado |",
  "|---|---:|---:|---|",
  old_fit_model_validation_lines,
  "",
  "**Tabela 7. Validação do agregado comercial bruto contra o subconjunto preservado.**",
  "",
  "| Validação | Resultado | Detalhe |",
  "|---|---|---|",
  trade_overlap_validation_lines,
  "",
  "## Caso de validação: Congo",
  "",
  paste0(
    "A linha `COD–2021` está presente no painel mestre com ranking comercial ",
    "observado, China em primeiro lugar, tratamento igual a 1 e distância de ",
    "ponto ideal ausente. Ela pertence ao conjunto de risco, mas não à amostra ",
    "de estimação. O período comercial do Congo é contado de 2008 a 2022, com ",
    "15 anos consecutivos."
  ),
  "",
  "## Proveniência e reprodutibilidade",
  "",
  paste0("- Fonte comercial bruta: `", itpd_path, "`."),
  paste0("- Agregado de comércio desta execução: `",
         trade_aggregate_path, "`."),
  paste0("- Fonte de pontos ideais: `", unga_path, "`."),
  paste0("- Painel mestre corrigido: `", master_path, "`."),
  paste0("- Amostra de estimação: `", estimation_path, "`."),
  paste0("- Comparação de resultados: `", model_comparison_path, "`."),
  paste0("- Manifesto SHA-256: `", manifest_path, "`."),
  paste0("- Informações da sessão: `", session_path, "`."),
  paste0("- Data efetiva de acesso local aos insumos: ",
         as.character(execution_date), "."),
  "",
  "## Limite operacional",
  "",
  "Esta execução é diagnóstica e externa ao pipeline `targets`. Nenhum alvo, ",
  "lock ou arquivo de configuração do pipeline foi alterado. Antes de usar os ",
  "resultados no paper, a recodificação precisa ser integrada ao pipeline por ",
  "autorização separada e os alvos correspondentes precisam ser reconstruídos."
)

writeLines(report_lines, report_path, useBytes = TRUE)

manifest_files <- c(required_inputs, output_paths, report_path)
manifest <- tibble::tibble(
  file = manifest_files,
  role = c(
    rep("input", length(required_inputs)),
    rep("output", length(output_paths) + 1L)
  )
) |>
  dplyr::mutate(
    sha256 = vapply(file, sha256_file, character(1)),
    bytes = file.info(file)$size,
    modified = format(
      file.info(file)$mtime,
      "%Y-%m-%d %H:%M:%S %Z"
    ),
    accessed_on = as.character(execution_date),
    decision_date = as.character(decision_date),
    run_label = args$run_label,
    nboots = args$nboots,
    expected_fect_version = as.character(expected_fect_version),
    actual_fect_version = as.character(packageVersion("fect"))
  )
readr::write_csv(manifest, manifest_path, na = "")

message("Completed. Report: ", report_path)
message("Corrected master panel: ", master_path)
message("Corrected estimation panel: ", estimation_path)
