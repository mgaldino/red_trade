#!/usr/bin/env Rscript

# Diagnostic fect runs for displaced-incumbent salience moderators.
# This script reads existing targets and diagnostic CSVs only. It does not run
# targets::tar_make() and does not modify the targets pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(fect)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

args <- commandArgs(trailingOnly = TRUE)

parse_nboots <- function(args, default = 500L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    nboots <- default
  } else {
    nboots <- as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
  }
  if (is.na(nboots) || nboots <= 0L) {
    stop("`--nboots` must be a positive integer.")
  }
  nboots
}

parse_report_dir <- function(args, default) {
  report_arg <- args[grepl("^--report-dir=", args)]
  if (length(report_arg) == 0L) {
    return(default)
  }
  sub("^--report-dir=", "", report_arg[[1]])
}

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

format_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, "<0.001", sprintf("%.3f", x)))
}

markdown_table <- function(data) {
  data_chr <- data %>%
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
  header <- paste(names(data_chr), collapse = " | ")
  separator <- paste(rep("---", ncol(data_chr)), collapse = " | ")
  rows <- apply(data_chr, 1, function(row) paste(row, collapse = " | "))
  paste(c(paste0("| ", header, " |"),
          paste0("| ", separator, " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}

safe_sd <- function(x) {
  x <- as.numeric(x)
  if (all(is.na(x)) || length(stats::na.omit(x)) < 2L) {
    return(NA_real_)
  }
  stats::sd(x, na.rm = TRUE)
}

att_row <- function(fit, model, moderator, group_var, nboots, status = "ok",
                    error_message = NA_character_) {
  if (status != "ok") {
    return(tibble::tibble(
      model = model,
      moderator = moderator,
      group_var = group_var,
      status = status,
      error_message = error_message,
      nboots = nboots,
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

  se <- safe_sd(fit$att.avg.boot)
  p_value <- ifelse(!is.na(se) && se > 0, 2 * stats::pnorm(-abs(fit$att.avg / se)), NA_real_)
  tibble::tibble(
    model = model,
    moderator = moderator,
    group_var = group_var,
    status = "ok",
    error_message = NA_character_,
    nboots = nboots,
    att = fit$att.avg,
    se = se,
    ci_lo = fit$att.avg - 1.96 * se,
    ci_hi = fit$att.avg + 1.96 * se,
    p = p_value,
    r_cv = if (!is.null(fit$r.cv)) as.numeric(fit$r.cv[[1]]) else NA_real_,
    n_obs = length(fit$Y.dat),
    n_countries = fit$N,
    n_treated = fit$Ntr,
    n_control = fit$Nco
  )
}

extract_group_rows <- function(fit, model, moderator, group_var, nboots) {
  if (is.null(fit$group.att) || is.null(fit$est.group.att)) {
    return(tibble::tibble())
  }

  group_summary <- as.data.frame(fit$est.group.att)
  group_summary$group <- rownames(fit$est.group.att)
  if (is.null(group_summary$group)) {
    group_summary$group <- names(fit$group.att)
  }
  if (is.null(group_summary$group) || any(is.na(group_summary$group))) {
    if (!is.null(fit$group) && nrow(fit$group) == nrow(group_summary)) {
      group_summary$group <- fit$group$rawgroup
    } else {
      group_summary$group <- paste0("group_", seq_len(nrow(group_summary)))
    }
  }

  col_lookup <- function(possible) {
    match <- intersect(possible, names(group_summary))
    if (length(match) == 0L) {
      return(NA_character_)
    }
    match[[1]]
  }

  att_col <- col_lookup(c("ATT", "att", "Estimate", "estimate"))
  se_col <- col_lookup(c("S.E.", "S.E", "SE", "Std. Error", "std.error"))
  ci_lo_col <- col_lookup(c("CI.lower", "CI Lower", "CI.low", "lower"))
  ci_hi_col <- col_lookup(c("CI.upper", "CI Upper", "CI.high", "upper"))
  p_col <- col_lookup(c("p.value", "p", "Pr(>|t|)"))

  if (is.na(att_col)) {
    stop("Could not identify ATT column in `fit$est.group.att`.")
  }

  att <- as.numeric(group_summary[[att_col]])
  se <- if (!is.na(se_col)) as.numeric(group_summary[[se_col]]) else rep(NA_real_, length(att))
  ci_lo <- if (!is.na(ci_lo_col)) {
    as.numeric(group_summary[[ci_lo_col]])
  } else {
    att - 1.96 * se
  }
  ci_hi <- if (!is.na(ci_hi_col)) {
    as.numeric(group_summary[[ci_hi_col]])
  } else {
    att + 1.96 * se
  }
  p_value <- if (!is.na(p_col)) {
    as.numeric(group_summary[[p_col]])
  } else {
    ifelse(!is.na(se) & se > 0, 2 * stats::pnorm(-abs(att / se)), NA_real_)
  }

  tibble::tibble(
    model = model,
    moderator = moderator,
    group_var = group_var,
    group = group_summary$group,
    nboots = nboots,
    att = att,
    se = se,
    ci_lo = ci_lo,
    ci_hi = ci_hi,
    p = p_value,
    r_cv = if (!is.null(fit$r.cv)) as.numeric(fit$r.cv[[1]]) else NA_real_
  ) %>%
    dplyr::filter(
      !is.na(att),
      group != "never_treated_control"
    )
}

fit_fect_ife <- function(data, model, moderator, group_var, nboots, log_message) {
  log_message("Estimating ", model, " with nboots = ", nboots)
  set.seed(42)
  fit_args <- list(
    formula = abs_distance_china ~ china_top,
    data = as.data.frame(data),
    index = c("country_id", "year"),
    method = "ife",
    force = "two-way",
    se = TRUE,
    nboots = nboots,
    parallel = FALSE,
    CV = TRUE,
    r = c(0, 3)
  )
  if (!is.null(group_var)) {
    fit_args$group <- group_var
  }

  fit <- tryCatch(
    do.call(fect::fect, fit_args),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    log_message("ERROR in ", model, ": ", conditionMessage(fit))
    return(list(
      fit = NULL,
      overall = att_row(
        fit = NULL,
        model = model,
        moderator = moderator,
        group_var = ifelse(is.null(group_var), NA_character_, group_var),
        nboots = nboots,
        status = "error",
        error_message = conditionMessage(fit)
      ),
      groups = tibble::tibble()
    ))
  }

  list(
    fit = fit,
    overall = att_row(
      fit = fit,
      model = model,
      moderator = moderator,
      group_var = ifelse(is.null(group_var), NA_character_, group_var),
      nboots = nboots
    ),
    groups = extract_group_rows(
      fit = fit,
      model = model,
      moderator = moderator,
      group_var = ifelse(is.null(group_var), NA_character_, group_var),
      nboots = nboots
    )
  )
}

make_cell_counts <- function(data, group_var, model, moderator) {
  treated_units <- data %>%
    dplyr::filter(first_treat > 0) %>%
    dplyr::distinct(
      iso3c,
      country_name,
      first_treat_year,
      group = .data[[group_var]]
    )

  treated_years <- data %>%
    dplyr::filter(first_treat > 0, china_top == 1L) %>%
    dplyr::group_by(group = .data[[group_var]]) %>%
    dplyr::summarise(treated_country_years = dplyr::n(), .groups = "drop")

  treated_units %>%
    dplyr::group_by(group) %>%
    dplyr::summarise(
      model = model,
      moderator = moderator,
      n_treated_countries = dplyr::n(),
      first_t0 = min(first_treat_year, na.rm = TRUE),
      last_t0 = max(first_treat_year, na.rm = TRUE),
      countries = paste(sort(iso3c), collapse = ", "),
      .groups = "drop"
    ) %>%
    dplyr::left_join(treated_years, by = "group") %>%
    dplyr::select(
      model,
      moderator,
      group,
      n_treated_countries,
      treated_country_years,
      first_t0,
      last_t0,
      countries
    )
}

nboots <- parse_nboots(args, default = 500L)
bootstrap_label <- paste0(nboots, "_bootstrap")
report_dir <- parse_report_dir(
  args,
  default = "reports/incumbent_salience_vreeland_reuse_2026-05-19"
)

dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(report_dir, paste0("model_run_", bootstrap_label, ".log"))

log_message <- function(...) {
  line <- paste0(
    "[", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "] ",
    paste0(..., collapse = "")
  )
  message(line)
  cat(line, "\n", file = log_file, append = TRUE)
}

incumbent_csv <- "data/processed/diagnostics/incumbent_salience_moderators_2026-05-19.csv"
vreeland_csv <- "data/processed/diagnostics/vreeland_pre_entry_moderators_2026-05-19.csv"

log_message("Loading existing target: china_top_absorbing_sample.")
analysis_data <- targets::tar_read(china_top_absorbing_sample) %>%
  tibble::as_tibble()

log_message("Loading diagnostic moderator CSVs.")
incumbent <- readr::read_csv(incumbent_csv, show_col_types = FALSE)
vreeland <- readr::read_csv(vreeland_csv, show_col_types = FALSE)

validate_unique_iso3 <- function(data, label) {
  duplicates <- data %>%
    dplyr::count(iso3c, name = "n") %>%
    dplyr::filter(n > 1L)
  if (nrow(duplicates) > 0L) {
    stop(
      label,
      " has duplicate iso3c rows: ",
      paste(duplicates$iso3c, collapse = ", ")
    )
  }
}

validate_unique_iso3(incumbent, "incumbent moderator CSV")
validate_unique_iso3(vreeland, "Vreeland moderator CSV")

required_incumbent <- c(
  "iso3c",
  "displaced_us",
  "displaced_g7",
  "displaced_regional_power",
  "displaced_regional_power_same_macroregion",
  "hub_entrepot_incumbent",
  "displacement_salience_warning",
  "export_share_margin_over_china_t0_minus_1",
  "displaced_partner_top_years_pre5"
)
missing_incumbent <- setdiff(required_incumbent, names(incumbent))
if (length(missing_incumbent) > 0L) {
  stop("Missing incumbent columns: ", paste(missing_incumbent, collapse = ", "))
}

required_vreeland <- c(
  "iso3c",
  "pre_entry_partner_level",
  "pre_entry_high_level_partner",
  "pre_entry_bri_mou"
)
missing_vreeland <- setdiff(required_vreeland, names(vreeland))
if (length(missing_vreeland) > 0L) {
  stop("Missing Vreeland columns: ", paste(missing_vreeland, collapse = ", "))
}

analysis_data <- analysis_data %>%
  dplyr::left_join(
    incumbent %>%
      dplyr::select(dplyr::all_of(required_incumbent)),
    by = "iso3c"
  ) %>%
  dplyr::left_join(
    vreeland %>%
      dplyr::select(dplyr::all_of(required_vreeland)),
    by = "iso3c"
  ) %>%
  dplyr::mutate(
    country_id = as.integer(as.factor(iso3c)),
    displaced_us_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_us == TRUE ~ "displaced_us_yes",
      displaced_us == FALSE ~ "displaced_us_no",
      TRUE ~ "missing_moderator"
    ),
    displaced_g7_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_g7 == TRUE ~ "displaced_g7_yes",
      displaced_g7 == FALSE ~ "displaced_g7_no",
      TRUE ~ "missing_moderator"
    ),
    displaced_regional_power_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_regional_power == TRUE ~ "regional_power_yes",
      displaced_regional_power == FALSE ~ "regional_power_no",
      TRUE ~ "missing_moderator"
    ),
    pre_entry_high_level_partner_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      pre_entry_high_level_partner == 1 ~ "high_level_partner_yes",
      pre_entry_high_level_partner == 0 ~ "high_level_partner_no",
      TRUE ~ "missing_moderator"
    )
  ) %>%
  dplyr::arrange(country_id, year)

panel_duplicates <- analysis_data %>%
  dplyr::count(country_id, year, name = "n") %>%
  dplyr::filter(n > 1L)
if (nrow(panel_duplicates) > 0L) {
  stop("Joined analysis panel has duplicate country_id-year rows.")
}

treated_missing <- analysis_data %>%
  dplyr::filter(first_treat > 0) %>%
  dplyr::summarise(
    missing_displaced_us = sum(is.na(displaced_us)),
    missing_displaced_g7 = sum(is.na(displaced_g7)),
    missing_displaced_regional_power = sum(is.na(displaced_regional_power)),
    missing_pre_entry_high_level_partner = sum(is.na(pre_entry_high_level_partner)),
    .groups = "drop"
  )

if (any(treated_missing > 0)) {
  stop("Missing moderator values among treated rows.")
}

model_specs <- tibble::tribble(
  ~model, ~moderator, ~group_var,
  "Baseline IFE, no moderator", "none", NA_character_,
  "IFE grouped by displaced_us", "displaced_us", "displaced_us_group",
  "IFE grouped by displaced_g7", "displaced_g7", "displaced_g7_group",
  "IFE grouped by displaced_regional_power", "displaced_regional_power", "displaced_regional_power_group",
  "IFE grouped by pre_entry_high_level_partner", "pre_entry_partner_level", "pre_entry_high_level_partner_group"
)

group_specs <- model_specs %>%
  dplyr::filter(!is.na(group_var))

cell_counts <- dplyr::bind_rows(lapply(seq_len(nrow(group_specs)), function(i) {
  make_cell_counts(
    data = analysis_data,
    group_var = group_specs$group_var[[i]],
    model = group_specs$model[[i]],
    moderator = group_specs$moderator[[i]]
  )
}))

salience_diagnostics <- analysis_data %>%
  dplyr::filter(first_treat > 0) %>%
  dplyr::distinct(
    iso3c,
    country_name,
    first_treat_year,
    displaced_us,
    displaced_g7,
    displaced_regional_power,
    displaced_regional_power_same_macroregion,
    hub_entrepot_incumbent,
    displacement_salience_warning,
    export_share_margin_over_china_t0_minus_1,
    displaced_partner_top_years_pre5,
    pre_entry_partner_level,
    pre_entry_high_level_partner,
    pre_entry_bri_mou
  ) %>%
  dplyr::arrange(first_treat_year, iso3c)

model_results <- vector("list", nrow(model_specs))
for (i in seq_len(nrow(model_specs))) {
  group_var <- model_specs$group_var[[i]]
  if (is.na(group_var)) {
    group_var <- NULL
  }
  model_results[[i]] <- fit_fect_ife(
    data = analysis_data,
    model = model_specs$model[[i]],
    moderator = model_specs$moderator[[i]],
    group_var = group_var,
    nboots = nboots,
    log_message = log_message
  )
}

overall_results <- dplyr::bind_rows(lapply(model_results, `[[`, "overall"))
group_results <- dplyr::bind_rows(lapply(model_results, `[[`, "groups")) %>%
  dplyr::left_join(
    cell_counts %>%
      dplyr::select(
        model,
        moderator,
        group,
        n_treated_countries,
        treated_country_years,
        countries
      ),
    by = c("model", "moderator", "group")
  )

overall_out <- file.path(report_dir, paste0("model_results_", bootstrap_label, "_overall.csv"))
group_out <- file.path(report_dir, paste0("model_results_", bootstrap_label, "_group_att.csv"))
counts_out <- file.path(report_dir, paste0("model_results_", bootstrap_label, "_cell_counts.csv"))
salience_out <- file.path(report_dir, paste0("model_results_", bootstrap_label, "_salience_diagnostics.csv"))
session_out <- file.path(report_dir, paste0("model_sessionInfo_", bootstrap_label, ".txt"))
report_out <- file.path(report_dir, paste0("model_results_", bootstrap_label, ".md"))

readr::write_csv(overall_results, overall_out)
readr::write_csv(group_results, group_out)
readr::write_csv(cell_counts, counts_out)
readr::write_csv(salience_diagnostics, salience_out)
capture.output(sessionInfo(), file = session_out)

overall_display <- overall_results %>%
  dplyr::mutate(
    att = format_num(att),
    se = format_num(se),
    ci = paste0("[", format_num(ci_lo), ", ", format_num(ci_hi), "]"),
    p = format_p(p),
    r_cv = format_num(r_cv, 0L)
  ) %>%
  dplyr::select(
    model,
    status,
    att,
    se,
    ci,
    p,
    r_cv,
    n_countries,
    n_treated,
    n_control
  )

group_display <- group_results %>%
  dplyr::mutate(
    att = format_num(att),
    se = format_num(se),
    ci = paste0("[", format_num(ci_lo), ", ", format_num(ci_hi), "]"),
    p = format_p(p),
    r_cv = format_num(r_cv, 0L)
  ) %>%
  dplyr::select(
    model,
    group,
    n_treated_countries,
    treated_country_years,
    att,
    se,
    ci,
    p,
    r_cv
  )

warning_display <- salience_diagnostics %>%
  dplyr::count(displacement_salience_warning, name = "n_countries") %>%
  dplyr::arrange(dplyr::desc(n_countries))

report_lines <- c(
  "# Model results: 500-bootstrap incumbent-salience diagnostics",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Bootstrap replications: ", nboots),
  "",
  "These are preliminary diagnostics. They use the existing absorbing China-top estimation sample and `fect` IFE with two-way fixed effects, cross-validated latent factors `r = 0:3`, and grouped ATT estimates. The grouped models are heterogeneity diagnostics, not independent causal identification checks.",
  "",
  "## Table 1. Overall fect IFE estimates",
  "",
  markdown_table(overall_display),
  "",
  "## Table 2. Grouped ATT estimates by pre-treatment moderator",
  "",
  markdown_table(group_display),
  "",
  "## Table 3. Treated-country cell counts",
  "",
  markdown_table(
    cell_counts %>%
      dplyr::select(
        model,
        group,
        n_treated_countries,
        treated_country_years,
        first_t0,
        last_t0
      )
  ),
  "",
  "## Table 4. Salience warnings among treated countries",
  "",
  markdown_table(warning_display),
  "",
  "## Interpretation guardrails",
  "",
  "- `displaced_us`, `displaced_g7`, and `displaced_regional_power` are measured at `t0 - 1`, before treatment entry/onset.",
  "- `pre_entry_high_level_partner` is derived from LPV's `partner_level_lag1` at `t0`; it is a robustness diagnostic because it is close to the China-alignment mechanism.",
  "- Cases flagged as hubs/entrepôts, narrow-margin displacements, or weakly persistent incumbents should not be treated as strong evidence that a politically salient incumbent was displaced.",
  "- These 500-bootstrap runs are meant to screen patterns before heavier event-study, pre-trend, hub-exclusion, and leave-one-country-out diagnostics.",
  "",
  "## Output files",
  "",
  paste0("- `", overall_out, "`"),
  paste0("- `", group_out, "`"),
  paste0("- `", counts_out, "`"),
  paste0("- `", salience_out, "`"),
  paste0("- `", log_file, "`"),
  paste0("- `", session_out, "`")
)

writeLines(report_lines, con = report_out, useBytes = TRUE)

log_message("Wrote ", overall_out)
log_message("Wrote ", group_out)
log_message("Wrote ", counts_out)
log_message("Wrote ", salience_out)
log_message("Wrote ", report_out)
log_message("Wrote ", session_out)

print(overall_display)
print(group_display)
