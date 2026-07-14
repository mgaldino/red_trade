#!/usr/bin/env Rscript

# Diagnostic join of status-cue salience codes to the existing China-top panel.
# Reads existing targets only; does not call targets::tar_make() and does not
# modify the targets pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

args <- commandArgs(trailingOnly = TRUE)
run_fect <- "--run-fect" %in% args
nboots_arg <- args[grepl("^--nboots=", args)]
nboots <- if (length(nboots_arg) > 0L) {
  as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
} else {
  100L
}
if (is.na(nboots) || nboots <= 0L) {
  stop("--nboots must be a positive integer.")
}

processed_dir <- "data/processed/status_cue_salience"
report_dir <- "quality_reports/status_cue_salience"
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

country_codes_path <- file.path(processed_dir, "status_cue_country_codes.csv")
evidence_path <- file.path(processed_dir, "status_cue_source_evidence.csv")
treated_path <- file.path(
  "quality_reports",
  "cross_country_sample",
  "china_top_absorbing_cs_sample_fect_treated_countries.csv"
)
status_scope_path <- file.path(
  "quality_reports",
  "cross_country_sample",
  "china_top_absorbing_cs_corrected_sample_status.csv"
)

appendix_table_path <- file.path(processed_dir, "status_cue_appendix_table.csv")
event_profile_path <- file.path(processed_dir, "status_cue_event_profile_descriptive.csv")
subgroup_path <- file.path(processed_dir, "status_cue_salience_subgroup_fect.csv")
summary_path <- file.path(report_dir, "status_cue_salience_event_study_summary.md")

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

markdown_table <- function(data) {
  if (nrow(data) == 0L) {
    return("_No rows._")
  }
  data_chr <- data |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
  header <- paste(names(data_chr), collapse = " | ")
  separator <- paste(rep("---", ncol(data_chr)), collapse = " | ")
  rows <- apply(data_chr, 1, function(row) paste(row, collapse = " | "))
  paste(
    c(
      paste0("| ", header, " |"),
      paste0("| ", separator, " |"),
      paste0("| ", rows, " |")
    ),
    collapse = "\n"
  )
}

safe_mean <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_real_)
  }
  mean(x)
}

country_codes <- readr::read_csv(country_codes_path, show_col_types = FALSE)
evidence <- readr::read_csv(evidence_path, show_col_types = FALSE)
treated <- readr::read_csv(treated_path, show_col_types = FALSE) |>
  dplyr::filter(model == "No covariates") |>
  dplyr::transmute(
    iso3c,
    country_name,
    entry_year = as.integer(first_treated_year)
  )
status_scope <- readr::read_csv(status_scope_path, show_col_types = FALSE) |>
  dplyr::filter(
    model == "No covariates",
    cs_role %in% c("treated_absorbing", "never_treated")
  ) |>
  dplyr::select(iso3c, cs_role)

missing_codes <- setdiff(treated$iso3c, country_codes$iso3c)
if (length(missing_codes) > 0L) {
  stop("Missing salience codes for: ", paste(missing_codes, collapse = ", "))
}

source_summary <- evidence |>
  dplyr::filter(
    evidence_strength %in% c("strong", "moderate"),
    explicit_rank_language,
    mentions_china_rank_change,
    !grepl("^DO_NOT_COUNT", notes)
  ) |>
  dplyr::mutate(
    source_label = paste0(source_name, " (", rank_label_english, ")")
  ) |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    principal_sources = paste(source_label[seq_len(min(3L, dplyr::n()))], collapse = "; "),
    principal_labels = paste(unique(rank_label_english), collapse = "; "),
    .groups = "drop"
  )

appendix_table <- country_codes |>
  dplyr::left_join(source_summary, by = "iso3c") |>
  dplyr::mutate(
    principal_sources = dplyr::if_else(
      is.na(principal_sources),
      "",
      principal_sources
    ),
    principal_labels = dplyr::if_else(
      is.na(principal_labels),
      "",
      principal_labels
    )
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    entry_year,
    principal_sources,
    principal_labels,
    salience_code,
    negative_case_candidate,
    coding_rationale,
    remaining_gaps
  ) |>
  dplyr::arrange(entry_year, country_name)

readr::write_csv(appendix_table, appendix_table_path)

message("Reading existing targets: trade_data and unga_data.")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)

message("Building China-top partner panel from existing functions.")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = 1990L,
  min_entry_year = 2000L
)

required_cols <- c("iso3c", "year", "country_name", "china_top", "abs_distance_china")
missing_cols <- setdiff(required_cols, names(china_top_panel))
if (length(missing_cols) > 0L) {
  stop("Panel missing required columns: ", paste(missing_cols, collapse = ", "))
}

treated_codes <- country_codes |>
  dplyr::select(
    iso3c,
    status_entry_year = entry_year,
    salience_code
  )

panel_with_salience <- china_top_panel |>
  dplyr::semi_join(status_scope, by = "iso3c") |>
  dplyr::left_join(status_scope, by = "iso3c") |>
  dplyr::left_join(treated_codes, by = "iso3c") |>
  dplyr::mutate(
    treated_in_status_sample = !is.na(status_entry_year),
    salience_code = dplyr::if_else(
      treated_in_status_sample,
      salience_code,
      "never_treated_control"
    ),
    first_treat = dplyr::if_else(
      treated_in_status_sample,
      as.integer(status_entry_year),
      0L
    ),
    event_time = dplyr::if_else(
      treated_in_status_sample,
      as.integer(year - status_entry_year),
      NA_integer_
    ),
    country_id = as.integer(factor(iso3c))
  )

event_profile <- panel_with_salience |>
  dplyr::filter(
    treated_in_status_sample,
    event_time >= -8L,
    event_time <= 8L
  ) |>
  dplyr::group_by(salience_code, event_time) |>
  dplyr::summarise(
    n_countries = dplyr::n_distinct(iso3c),
    mean_abs_distance_china = mean(abs_distance_china, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(salience_code, event_time)

readr::write_csv(event_profile, event_profile_path)

estimate_subgroup <- function(group_value) {
  subgroup_data <- panel_with_salience |>
    dplyr::filter(
      salience_code == "never_treated_control" |
        (treated_in_status_sample & salience_code == group_value)
    ) |>
    dplyr::mutate(
      subgroup_treatment = as.integer(
        treated_in_status_sample &
          salience_code == group_value &
          year >= status_entry_year
      )
    )

  n_treated <- subgroup_data |>
    dplyr::filter(subgroup_treatment == 1L) |>
    dplyr::summarise(n = dplyr::n_distinct(iso3c), .groups = "drop") |>
    dplyr::pull(n)
  n_control <- subgroup_data |>
    dplyr::filter(salience_code == "never_treated_control") |>
    dplyr::summarise(n = dplyr::n_distinct(iso3c), .groups = "drop") |>
    dplyr::pull(n)

  if (!run_fect) {
    return(tibble::tibble(
      salience_code = group_value,
      status = "skipped",
      error_message = "Run with --run-fect to estimate subgroup fect models.",
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_treated = n_treated,
      n_control = n_control
    ))
  }

  if (!requireNamespace("fect", quietly = TRUE)) {
    return(tibble::tibble(
      salience_code = group_value,
      status = "error",
      error_message = "Package fect is not installed.",
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_treated = n_treated,
      n_control = n_control
    ))
  }

  if (n_treated < 2L || n_control < 10L) {
    return(tibble::tibble(
      salience_code = group_value,
      status = "skipped",
      error_message = paste0(
        "Insufficient support: treated = ", n_treated,
        ", controls = ", n_control
      ),
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_treated = n_treated,
      n_control = n_control
    ))
  }

  set.seed(42)
  fit <- tryCatch(
    fect::fect(
      abs_distance_china ~ subgroup_treatment,
      data = as.data.frame(subgroup_data),
      index = c("country_id", "year"),
      method = "ife",
      force = "two-way",
      se = TRUE,
      nboots = nboots,
      parallel = FALSE,
      CV = TRUE,
      r = c(0, 3)
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      salience_code = group_value,
      status = "error",
      error_message = conditionMessage(fit),
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_treated = n_treated,
      n_control = n_control
    ))
  }

  se <- stats::sd(fit$att.avg.boot, na.rm = TRUE)
  p_value <- ifelse(!is.na(se) && se > 0, 2 * stats::pnorm(-abs(fit$att.avg / se)), NA_real_)
  tibble::tibble(
    salience_code = group_value,
    status = "ok",
    error_message = NA_character_,
    nboots = nboots,
    att = fit$att.avg,
    se = se,
    ci_lo = fit$att.avg - 1.96 * se,
    ci_hi = fit$att.avg + 1.96 * se,
    p = p_value,
    n_treated = n_treated,
    n_control = n_control
  )
}

subgroup_results <- unique(country_codes$salience_code) |>
  sort() |>
  lapply(estimate_subgroup) |>
  dplyr::bind_rows()

readr::write_csv(subgroup_results, subgroup_path)

salience_counts <- country_codes |>
  dplyr::count(salience_code, name = "n_countries") |>
  dplyr::arrange(salience_code)

profile_compact <- event_profile |>
  dplyr::filter(event_time %in% c(-4L, -1L, 0L, 1L, 3L, 5L, 8L)) |>
  dplyr::mutate(mean_abs_distance_china = format_num(mean_abs_distance_china)) |>
  dplyr::select(salience_code, event_time, n_countries, mean_abs_distance_china)

subgroup_compact <- subgroup_results |>
  dplyr::mutate(
    att = format_num(att),
    se = format_num(se),
    p = format_num(p)
  ) |>
  dplyr::select(salience_code, status, error_message, n_treated, n_control, att, se, p)

summary_md <- paste(
  "# Status Cue Salience Event-Study Diagnostic",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "This diagnostic joins the country-level salience codes to the existing China-top partner panel.",
  "It reads existing targets with `targets::tar_read()` but does not call `targets::tar_make()`.",
  "",
  "## Salience Counts",
  "",
  markdown_table(salience_counts),
  "",
  "## Descriptive Event Profile",
  "",
  "Mean absolute UNGA ideal-point distance to China by event time and salience code. These are descriptive treated-country profiles, not causal subgroup estimates.",
  "",
  markdown_table(profile_compact),
  "",
  "## Subgroup FECT",
  "",
  if (run_fect) {
    paste0("Subgroup IFE models were requested with `--run-fect --nboots=", nboots, "`.")
  } else {
    "Subgroup IFE models were not run. Re-run this script with `--run-fect` to estimate them."
  },
  "",
  "These subgroup estimates are exploratory: treated-group counts are small, the bootstrap count may be low, and `fect` can report singular covariance warnings in this sample.",
  "",
  markdown_table(subgroup_compact),
  "",
  "## Output Files",
  "",
  paste0("- `", appendix_table_path, "`"),
  paste0("- `", event_profile_path, "`"),
  paste0("- `", subgroup_path, "`"),
  sep = "\n"
)

writeLines(summary_md, summary_path, useBytes = TRUE)

message("Wrote ", appendix_table_path)
message("Wrote ", event_profile_path)
message("Wrote ", subgroup_path)
message("Wrote ", summary_path)
