#!/usr/bin/env Rscript

# Re-estimate the cross-country China #1 models outside targets.
# This script combines:
# - the status-current / restricted-risk-set logic from the 2026-05-20 pending
#   note; and
# - the M2 goods-only treatment metric, using ITPD-E goods sectors only.
#
# It reads small already-materialized objects with readRDS(), not tar_read(),
# and it does not modify or run the targets pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(DBI)
  library(countrycode)
  library(dplyr)
  library(duckdb)
  library(ggplot2)
  library(readr)
  library(tibble)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

source("scripts/functions.R")
Sys.setenv(CHINA_TOP_STATUS_CURRENT_SOURCE_ONLY = "1")
source("scripts/diagnostics/reestimate_china_top_min5_status_current_strict.R")
Sys.unsetenv("CHINA_TOP_STATUS_CURRENT_SOURCE_ONLY")

run_date <- as.Date("2026-05-20")
rank_window_start <- 1990L
rank_window_end <- 2023L
model_window_start <- 1990L
min_entry_year <- 2000L
goods_sectors <- c("Agriculture", "Mining and Energy", "Manufacturing")

parse_args <- function(args) {
  get_arg <- function(prefix, default) {
    hit <- args[startsWith(args, prefix)]
    if (length(hit) == 0L) {
      return(default)
    }
    sub(prefix, "", hit[[1]], fixed = TRUE)
  }

  durations <- strsplit(get_arg("--durations=", "3,5,7"), ",")[[1]]
  durations <- as.integer(trimws(durations))
  if (any(is.na(durations)) || any(durations <= 0L)) {
    stop("--durations must be a comma-separated list of positive integers.",
         call. = FALSE)
  }

  nboots <- as.integer(get_arg("--nboots=", "10000"))
  if (is.na(nboots) || nboots < 50L) {
    stop("--nboots must be an integer >= 50.", call. = FALSE)
  }

  list(
    nboots = nboots,
    durations = sort(unique(durations))
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

processed_dir <- file.path(
  "data", "processed", "diagnostics",
  "china_top_m2_goods_status_current_min5"
)
report_dir <- file.path(
  "quality_reports", "cross_country_m2_goods_status_current"
)
figure_dir <- file.path(report_dir, "figures")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

read_target_object_rds <- function(name) {
  path <- file.path("_targets", "objects", name)
  if (!file.exists(path)) {
    stop("Required materialized object not found: ", path, call. = FALSE)
  }
  readRDS(path)
}

file_md5_or_na <- function(path) {
  if (!file.exists(path)) {
    return(NA_character_)
  }
  unname(tools::md5sum(path))
}

file_mtime_or_na <- function(path) {
  if (!file.exists(path)) {
    return(NA_character_)
  }
  format(file.info(path)$mtime, "%Y-%m-%d %H:%M:%S %Z")
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
      "Duplicate keys detected in ", label, " for keys ",
      paste(keys, collapse = ", "), "\nExamples:\n", example,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

min_int_or_na <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_integer_)
  }
  as.integer(min(x))
}

aggregate_itpde_goods_exports <- function(itpd_path, panel_countries,
                                          start_year, end_year,
                                          goods_sector_values) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tempfile(fileext = ".duckdb"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbWriteTable(
    con,
    "panel_countries",
    panel_countries |> dplyr::select(iso3c),
    temporary = TRUE,
    overwrite = TRUE
  )

  itpd_sql <- as.character(DBI::dbQuoteString(
    con,
    normalizePath(itpd_path, mustWork = TRUE)
  ))
  goods_sql <- paste(
    as.character(DBI::dbQuoteString(con, goods_sector_values)),
    collapse = ", "
  )

  message("Auditing ITPD-E broad sectors in the requested window.")
  sector_audit <- DBI::dbGetQuery(con, paste0(
    "SELECT broad_sector, count(*) AS raw_rows, ",
    "sum(CASE WHEN try_cast(trade AS DOUBLE) IS NULL THEN 1 ELSE 0 END) AS missing_or_parse_fail_trade, ",
    "sum(CASE WHEN coalesce(try_cast(trade AS DOUBLE), 0) > 0 THEN 1 ELSE 0 END) AS positive_trade_rows ",
    "FROM read_csv_auto(", itpd_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
    "GROUP BY 1 ORDER BY 1"
  )) |>
    tibble::as_tibble()

  message("Aggregating ITPD-E goods exports with DuckDB.")
  DBI::dbExecute(con, paste0(
    "CREATE TEMP TABLE goods_exports AS ",
    "SELECT ",
    "try_cast(year AS INTEGER) AS year, ",
    "upper(exporter_iso3) AS exporter_iso3, ",
    "upper(importer_iso3) AS importer_iso3, ",
    "sum(coalesce(try_cast(trade AS DOUBLE), 0)) AS exports ",
    "FROM read_csv_auto(", itpd_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
    "AND upper(exporter_iso3) <> upper(importer_iso3) ",
    "AND broad_sector IN (", goods_sql, ") ",
    "GROUP BY 1, 2, 3"
  ))

  out <- DBI::dbGetQuery(con, paste0(
    "SELECT ge.year, ge.exporter_iso3, ge.importer_iso3, ge.exports ",
    "FROM goods_exports ge ",
    "INNER JOIN panel_countries pc ON ge.exporter_iso3 = pc.iso3c"
  )) |>
    tibble::as_tibble() |>
    dplyr::mutate(year = as.integer(year)) |>
    dplyr::filter(exports > 0) |>
    dplyr::select(year, exporter_iso3, importer_iso3, exports) |>
    dplyr::arrange(exporter_iso3, year, importer_iso3)

  abort_if_duplicates(
    out,
    c("year", "exporter_iso3", "importer_iso3"),
    "ITPD-E goods exports"
  )

  list(goods_exports = out, sector_audit = sector_audit)
}

make_panel_bundle <- function(m2_panel, duration_years) {
  period_data <- build_min5_period_data(
    m2_panel,
    min_duration_years = duration_years,
    min_entry_year = min_entry_year
  )

  list(
    switching_allowed = make_status_current_panel(
      period_data,
      require_balanced = TRUE,
      strict_never_control = FALSE
    ),
    risk_set_restricted = make_status_current_panel(
      period_data,
      require_balanced = FALSE,
      strict_never_control = TRUE
    ),
    clean_single_spell = make_status_current_panel(
      period_data,
      require_balanced = FALSE,
      strict_never_control = TRUE,
      clean_single_spell = TRUE
    ),
    period_summary = period_data$period_summary
  )
}

make_country_exclusion_audit <- function(m2_panel, duration_thresholds,
                                         min_entry_year) {
  base_units <- m2_panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      first_year_in_panel = min(year, na.rm = TRUE),
      last_year_in_panel = max(year, na.rm = TRUE),
      trade_years_observed = sum(!is.na(top_partner), na.rm = TRUE),
      ever_observed_china_top = any(china_is_top %in% TRUE, na.rm = TRUE),
      first_observed_china_top_year =
        min_int_or_na(year[china_is_top %in% TRUE]),
      .groups = "drop"
    )

  observed_periods <- m2_panel |>
    dplyr::filter(china_is_top %in% TRUE, !is.na(china_top_period_id)) |>
    dplyr::group_by(iso3c, country_name, china_top_period_id) |>
    dplyr::summarise(
      period_entry_year = min(year, na.rm = TRUE),
      period_exit_year = max(year, na.rm = TRUE),
      duration_years = dplyr::n_distinct(year),
      previous_trade_observed_at_entry =
        dplyr::first(previous_trade_observed_at_entry),
      previous_china_is_top_at_entry =
        dplyr::first(previous_china_is_top_at_entry),
      previous_top_partner_at_entry =
        dplyr::first(previous_top_partner_at_entry),
      .groups = "drop"
    )

  threshold_audit <- lapply(duration_thresholds, function(threshold) {
    period_counts <- observed_periods |>
      dplyr::mutate(
        eligible_entry =
          period_entry_year >= min_entry_year &
          previous_trade_observed_at_entry == TRUE &
          previous_china_is_top_at_entry == FALSE,
        qualifying_period = eligible_entry & duration_years >= threshold,
        short_eligible_period = eligible_entry & duration_years < threshold,
        pre_min_entry_period = period_entry_year < min_entry_year,
        no_clean_prior_period = !pre_min_entry_period &
          (
            is.na(previous_trade_observed_at_entry) |
              previous_trade_observed_at_entry != TRUE |
              is.na(previous_china_is_top_at_entry) |
              previous_china_is_top_at_entry != FALSE
          )
      ) |>
      dplyr::group_by(iso3c, country_name) |>
      dplyr::summarise(
        n_observed_china_top_periods = dplyr::n(),
        n_qualifying_periods = sum(qualifying_period, na.rm = TRUE),
        n_short_eligible_periods = sum(short_eligible_period, na.rm = TRUE),
        n_pre_min_entry_periods = sum(pre_min_entry_period, na.rm = TRUE),
        n_no_clean_prior_periods = sum(no_clean_prior_period, na.rm = TRUE),
        longest_observed_china_top_period =
          max(duration_years, na.rm = TRUE),
        first_qualifying_entry =
          min_int_or_na(period_entry_year[qualifying_period]),
        .groups = "drop"
      )

    base_units |>
      dplyr::left_join(period_counts, by = c("iso3c", "country_name")) |>
      dplyr::mutate(
        min_duration_years = .env$threshold,
        dplyr::across(
          c(
            n_observed_china_top_periods, n_qualifying_periods,
            n_short_eligible_periods, n_pre_min_entry_periods,
            n_no_clean_prior_periods
          ),
          ~ dplyr::coalesce(.x, 0L)
        ),
        longest_observed_china_top_period =
          dplyr::coalesce(longest_observed_china_top_period, 0L),
        audit_role = dplyr::case_when(
          n_qualifying_periods > 0L ~ "treated_qualifying",
          !ever_observed_china_top ~ "never_china_top_control",
          n_pre_min_entry_periods > 0L &
            n_short_eligible_periods == 0L &
            n_no_clean_prior_periods == 0L ~ "excluded_pre_2000",
          n_no_clean_prior_periods > 0L &
            n_short_eligible_periods == 0L ~ "excluded_no_clean_prior",
          n_short_eligible_periods > 0L ~ "excluded_short_duration",
          TRUE ~ "excluded_other_nonqualifying"
        ),
        .before = iso3c
      )
  })

  dplyr::bind_rows(threshold_audit) |>
    dplyr::arrange(min_duration_years, audit_role, iso3c)
}

spec_label <- function(specification) {
  dplyr::recode(
    specification,
    switching_allowed = "Status-current, switching allowed",
    risk_set_restricted = "Status-current, restricted risk set",
    clean_single_spell = "Clean single-entry robustness",
    .default = specification
  )
}

fit_one_model <- function(panel, duration_years, specification, nboots) {
  message(
    "Estimating M2 goods-only duration ", duration_years, ", ",
    specification, " with nboots = ", nboots, "."
  )

  timing <- system.time({
    fit <- run_fect_analysis(
      panel,
      method = "ife",
      nboots = nboots,
      fml = abs_distance_china ~ china_top
    )
  })

  summary <- summarize_fect_model(
    fit,
    panel,
    fml = abs_distance_china ~ china_top
  ) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      metric = "m2_goods_exports_itpde",
      metric_label = "M2 goods-only: ITPD-E export destinations",
      min_duration_years = duration_years,
      specification = specification,
      specification_label = spec_label(specification),
      nboots = nboots,
      elapsed_seconds = as.numeric(timing[["elapsed"]]),
      .before = att
    )

  dynamic <- tibble::tibble(
    metric = "m2_goods_exports_itpde",
    min_duration_years = duration_years,
    specification = specification,
    event_time = fit$time,
    count = fit$count,
    att = as.numeric(fit$est.att[, 1]),
    se = as.numeric(fit$est.att[, 2]),
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se
  )

  list(summary = summary, dynamic = dynamic, fit = fit)
}

plot_dynamic <- function(dynamic_data, output_path) {
  p <- dynamic_data |>
    dplyr::filter(!is.na(att), !is.na(se)) |>
    ggplot2::ggplot(ggplot2::aes(x = event_time, y = att)) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.35, linetype = "dashed",
                        color = "grey45") +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = ci_lo, ymax = ci_hi),
      fill = "#9bb7d4",
      alpha = 0.32,
      color = NA
    ) +
    ggplot2::geom_line(linewidth = 0.65, color = "#1f4e79") +
    ggplot2::geom_point(size = 1.8, color = "#1f4e79") +
    ggplot2::labs(
      x = "Periods relative to China #1 entry",
      y = "Effect on UNGA ideal-point distance to China"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_blank()
    )

  ggplot2::ggsave(output_path, p, width = 7, height = 4.6)
  p
}

args_msg <- paste0(
  "Running with nboots = ", args$nboots,
  "; durations = ", paste(args$durations, collapse = ", "), "."
)
message(args_msg)

message("Reading small materialized objects with readRDS(), not tar_read().")
unga_data <- read_target_object_rds("unga_data")

panel_countries <- unga_data |>
  tibble::as_tibble() |>
  dplyr::filter(year >= model_window_start, !is.na(iso3c), iso3c != "CHN") |>
  dplyr::distinct(iso3c) |>
  dplyr::mutate(
    country_name = countrycode::countrycode(
      iso3c, "iso3c", "country.name", warn = FALSE
    )
  ) |>
  dplyr::arrange(iso3c)

itpd_path <- file.path("raw data", "ITPDE_R03.csv")
aggregation <- aggregate_itpde_goods_exports(
  itpd_path,
  panel_countries,
  rank_window_start,
  rank_window_end,
  goods_sectors
)
goods_trade_full <- aggregation$goods_exports

message("Building M2 goods-only China #1 panel.")
m2_panel <- build_china_top_partner_panel(
  goods_trade_full,
  unga_data,
  min_year = model_window_start,
  min_entry_year = min_entry_year
)

all_model_results <- list()
all_dynamic <- list()
all_counts <- list()
all_units <- list()
all_periods <- list()
main_fit <- NULL

for (duration_years in args$durations) {
  panels <- make_panel_bundle(m2_panel, duration_years)

  spec_panels <- panels[c(
    "switching_allowed",
    "risk_set_restricted",
    "clean_single_spell"
  )]

  for (specification in names(spec_panels)) {
    fitted <- fit_one_model(
      spec_panels[[specification]],
      duration_years = duration_years,
      specification = specification,
      nboots = args$nboots
    )
    key <- paste(duration_years, specification, sep = "_")
    all_model_results[[key]] <- fitted$summary
    all_dynamic[[key]] <- fitted$dynamic

    if (duration_years == 5L && specification == "risk_set_restricted") {
      main_fit <- fitted$fit
      saveRDS(
        fitted$fit,
        file.path(processed_dir, paste0(
          "m2_goods_status_current_min5_risk_set_fect_fit_",
          run_date, ".rds"
        ))
      )
    }
  }

  all_counts[[as.character(duration_years)]] <- dplyr::bind_rows(
    comparison_counts(panels$switching_allowed, "switching_allowed"),
    comparison_counts(panels$risk_set_restricted, "risk_set_restricted"),
    comparison_counts(panels$clean_single_spell, "clean_single_spell")
  ) |>
    dplyr::mutate(
      min_duration_years = .env$duration_years,
      .before = sample
    )

  all_units[[as.character(duration_years)]] <- dplyr::bind_rows(
    panel_unit_summary(panels$switching_allowed, "switching_allowed"),
    panel_unit_summary(panels$risk_set_restricted, "risk_set_restricted"),
    panel_unit_summary(panels$clean_single_spell, "clean_single_spell")
  ) |>
    dplyr::mutate(
      min_duration_years = .env$duration_years,
      .before = sample
    )

  all_periods[[as.character(duration_years)]] <- panels$period_summary |>
    dplyr::mutate(
      min_duration_years = .env$duration_years,
      .before = iso3c
    )
}

model_results <- dplyr::bind_rows(all_model_results) |>
  dplyr::mutate(
    specification_order = dplyr::case_when(
      specification == "risk_set_restricted" ~ 1L,
      specification == "clean_single_spell" ~ 2L,
      specification == "switching_allowed" ~ 3L,
      TRUE ~ 99L
    )
  ) |>
  dplyr::arrange(min_duration_years, specification_order) |>
  dplyr::select(-specification_order)

dynamic_results <- dplyr::bind_rows(all_dynamic) |>
  dplyr::arrange(min_duration_years, specification, event_time)

sample_counts <- dplyr::bind_rows(all_counts) |>
  dplyr::arrange(min_duration_years, sample)

unit_summary <- dplyr::bind_rows(all_units) |>
  dplyr::arrange(min_duration_years, sample, iso3c)

period_summary <- dplyr::bind_rows(all_periods) |>
  dplyr::arrange(min_duration_years, iso3c, eligible_period_id)

country_exclusion_audit <- make_country_exclusion_audit(
  m2_panel,
  duration_thresholds = args$durations,
  min_entry_year = min_entry_year
) |>
  dplyr::left_join(
    unit_summary |>
      dplyr::select(
        min_duration_years, sample, iso3c, ever_treated,
        treated_years, untreated_years, first_treat
      ),
    by = c("min_duration_years", "iso3c")
  ) |>
  dplyr::arrange(min_duration_years, audit_role, sample, iso3c)

sector_audit_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_itpde_sector_audit_", run_date, ".csv")
)
goods_trade_file <- file.path(
  processed_dir,
  paste0("m2_goods_exports_country_partner_year_", run_date, ".csv")
)
m2_panel_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_full_panel_", run_date, ".csv")
)
model_results_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_model_results_", run_date, ".csv")
)
dynamic_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_dynamic_", run_date, ".csv")
)
sample_counts_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_sample_counts_", run_date, ".csv")
)
unit_summary_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_unit_summary_", run_date, ".csv")
)
period_summary_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_period_summary_", run_date, ".csv")
)
country_exclusion_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_country_exclusion_audit_",
         run_date, ".csv")
)
session_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_session_info_", run_date, ".txt")
)
manifest_file <- file.path(
  processed_dir,
  paste0("m2_goods_status_current_min_duration_manifest_", run_date, ".csv")
)

main_dynamic_pdf <- file.path(
  figure_dir,
  paste0("figure_m2_goods_status_current_min5_risk_set_dynamic_",
         run_date, ".pdf")
)
main_dynamic_png <- file.path(
  figure_dir,
  paste0("figure_m2_goods_status_current_min5_risk_set_dynamic_",
         run_date, ".png")
)

readr::write_csv(aggregation$sector_audit, sector_audit_file, na = "")
readr::write_csv(goods_trade_full, goods_trade_file, na = "")
readr::write_csv(m2_panel, m2_panel_file, na = "")
readr::write_csv(model_results, model_results_file, na = "")
readr::write_csv(dynamic_results, dynamic_file, na = "")
readr::write_csv(sample_counts, sample_counts_file, na = "")
readr::write_csv(unit_summary, unit_summary_file, na = "")
readr::write_csv(period_summary, period_summary_file, na = "")
readr::write_csv(country_exclusion_audit, country_exclusion_file, na = "")
writeLines(capture.output(utils::sessionInfo()), session_file, useBytes = TRUE)

if (any(
  dynamic_results$min_duration_years == 5L &
    dynamic_results$specification == "risk_set_restricted"
)) {
  main_dynamic <- dynamic_results |>
    dplyr::filter(
      min_duration_years == 5L,
      specification == "risk_set_restricted"
    )
  plot_dynamic(main_dynamic, main_dynamic_pdf)
  plot_dynamic(main_dynamic, main_dynamic_png)
}

manifest <- tibble::tibble(
  generated_on = as.character(run_date),
  nboots = args$nboots,
  durations = paste(args$durations, collapse = ","),
  rank_window_start = rank_window_start,
  rank_window_end = rank_window_end,
  model_window_start = model_window_start,
  min_entry_year = min_entry_year,
  itpd_file = itpd_path,
  itpd_md5 = unname(tools::md5sum(itpd_path)),
  unga_object = file.path("_targets", "objects", "unga_data"),
  unga_object_md5 = file_md5_or_na(file.path("_targets", "objects", "unga_data")),
  unga_object_mtime = file_mtime_or_na(file.path("_targets", "objects", "unga_data")),
  script_md5 = file_md5_or_na(
    "scripts/diagnostics/reestimate_china_top_m2_goods_status_current_min5.R"
  ),
  helper_md5 = file_md5_or_na(
    "scripts/diagnostics/reestimate_china_top_min5_status_current_strict.R"
  ),
  goods_sectors = paste(goods_sectors, collapse = "; "),
  output = c(
    sector_audit_file,
    goods_trade_file,
    m2_panel_file,
    model_results_file,
    dynamic_file,
    sample_counts_file,
    unit_summary_file,
    period_summary_file,
    country_exclusion_file,
    session_file,
    main_dynamic_pdf,
    main_dynamic_png
  )
)
readr::write_csv(manifest, manifest_file, na = "")

main_table <- model_results |>
  dplyr::filter(min_duration_years == 5L) |>
  dplyr::mutate(
    line = paste0(
      "| ", specification_label, " | ", n_treated, "/", n_control,
      " | ", n_treated_country_years, " | ", fmt(att), " | ",
      fmt(se), " | [", fmt(ci_lo), ", ", fmt(ci_hi), "] | ",
      format_p(p), " | ", r_cv, " |"
    )
  ) |>
  dplyr::pull(line)

duration_table <- model_results |>
  dplyr::filter(specification %in% c("risk_set_restricted", "clean_single_spell")) |>
  dplyr::mutate(
    line = paste0(
      "| ", min_duration_years, " | ", specification_label, " | ",
      n_treated, "/", n_control, " | ", fmt(att), " | ", fmt(se),
      " | [", fmt(ci_lo), ", ", fmt(ci_hi), "] | ", format_p(p), " |"
    )
  ) |>
  dplyr::pull(line)

sector_line <- aggregation$sector_audit |>
  dplyr::mutate(
    included = broad_sector %in% goods_sectors,
    line = paste0(
      "| ", broad_sector, " | ", raw_rows, " | ",
      positive_trade_rows, " | ", ifelse(included, "yes", "no"), " |"
    )
  ) |>
  dplyr::pull(line)

report_md <- file.path(
  report_dir,
  paste0("nota_m2_goods_status_current_min5_", run_date, ".md")
)

report_lines <- c(
  "# M2 goods-only status-current cross-country estimates",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Design",
  "",
  paste(
    "The treatment is coded from ITPD-E goods exports only. The script filters",
      "the raw ITPD-E file to Agriculture, Mining and Energy, and Manufacturing,",
      "excluding Services before partner ranks are computed."
  ),
  "",
  paste(
    "The main design follows the status-current restricted-risk-set rule. A",
    "country-year is treated only when China is rank 1 and that China-#1 period",
    "lasts at least five observed years. For treated countries, clean comparison",
    "years are pre-entry non-China-top years; post-exit off-treatment years and",
    "short China-top episodes are removed from the risk set."
  ),
  "",
  "## Main minimum-five-year table",
  "",
  "| Specification | Treated/control | Treated country-years | ATT | SE | 95% CI | p | r* |",
  "|---|---:|---:|---:|---:|---:|---:|---:|",
  main_table,
  "",
  "## Duration robustness",
  "",
  "| Minimum duration | Specification | Treated/control | ATT | SE | 95% CI | p |",
  "|---:|---|---:|---:|---:|---:|---:|",
  duration_table,
  "",
  "## ITPD-E sector audit",
  "",
  "| Broad sector | Raw rows | Positive-trade rows | Included in M2 |",
  "|---|---:|---:|---|",
  sector_line,
  "",
  "## Country-level exclusion audit",
  "",
  paste0("- `", country_exclusion_file, "`"),
  "",
  paste(
    "The audit reconciles all countries in the UNGA/trade panel across duration",
    "thresholds, separating qualifying treated countries, never-China-top",
    "controls, short China-#1 periods, pre-2000 entries, and cases without a",
    "clean observed prior non-China-top year."
  ),
  "",
  "## Output files",
  "",
  paste0("- `", model_results_file, "`"),
  paste0("- `", dynamic_file, "`"),
  paste0("- `", sample_counts_file, "`"),
  paste0("- `", unit_summary_file, "`"),
  paste0("- `", period_summary_file, "`"),
  paste0("- `", country_exclusion_file, "`"),
  paste0("- `", main_dynamic_pdf, "`")
)

writeLines(report_lines, report_md, useBytes = TRUE)

message("Wrote model results: ", model_results_file)
message("Wrote report: ", report_md)
print(model_results)
