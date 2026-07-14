#!/usr/bin/env Rscript

# Diagnostic: rerun the factor model restricting the current treatment rule
# to spells where China's rank is 2 or 3 before/on treatment onset.
# This script does not modify _targets.R or write to the targets store.

library(targets)
library(dplyr)
library(tidyr)
library(countrycode)
library(here)

options(scipen = 999)

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

safe_cov <- function(coef_mat) {
  if (ncol(coef_mat) < 2) {
    return(matrix(NA_real_, nrow = nrow(coef_mat), ncol = nrow(coef_mat)))
  }

  stats::cov(t(coef_mat))
}

safe_rank <- function(cov_mat, tol = 1e-10) {
  tryCatch(
    qr(cov_mat, tol = tol)$rank,
    error = function(e) NA_integer_
  )
}

calculate_f_test <- function(point_estimates, cov_mat, n_bar,
                             f_threshold = 0.6) {
  df1 <- nrow(point_estimates)
  df2 <- n_bar - df1

  solve_cov <- tryCatch(
    solve(cov_mat),
    error = function(e) e
  )

  if (inherits(solve_cov, "error")) {
    return(list(
      stat = NA_real_,
      p = NA_real_,
      equiv_p = NA_real_,
      error = conditionMessage(solve_cov)
    ))
  }

  scale <- (n_bar - df1) / ((n_bar - 1) * df1)
  if (scale <= 0) {
    return(list(
      stat = NA_real_,
      p = NA_real_,
      equiv_p = NA_real_,
      error = "insufficient treated units for the F statistic"
    ))
  }

  psi <- as.numeric(t(point_estimates) %*% solve_cov %*% point_estimates)
  f_stat <- psi * scale

  list(
    stat = f_stat,
    p = stats::pf(f_stat, df1 = df1, df2 = df2, lower.tail = FALSE),
    equiv_p = stats::pf(
      f_stat,
      df1 = df1,
      df2 = df2,
      ncp = n_bar * f_threshold
    ),
    error = ""
  )
}

inspect_fect_diagtest <- function(fit, label, proportion = 0.3,
                                  pre.periods = NULL, tol = 1e-10,
                                  f_threshold = 0.6) {
  if (is.null(pre.periods)) {
    max_count <- max(fit$count, na.rm = TRUE)
    pre.periods <- fit$time[
      fit$count >= max_count * proportion & fit$time <= 0
    ]
  }

  n_all_nonpositive_periods <- sum(fit$time <= 0, na.rm = TRUE)
  pre_pos <- which(fit$time %in% pre.periods)

  if (length(pre_pos) == n_all_nonpositive_periods) {
    pre_pos <- pre_pos[-1]
  }

  n_bar <- max(fit$count[fit$time %in% pre.periods], na.rm = TRUE)

  att_boot <- as.matrix(fit$att.boot)
  valid_boot_cols <- which(apply(!is.na(att_boot), 2, all))
  valid_boot_cols_selected_only <- which(
    apply(!is.na(att_boot[pre_pos, , drop = FALSE]), 2, all)
  )

  coef_mat_global <- att_boot[pre_pos, valid_boot_cols, drop = FALSE]
  coef_mat_selected <- att_boot[
    pre_pos, valid_boot_cols_selected_only, drop = FALSE
  ]

  point_estimates <- as.matrix(fit$est.att[pre_pos, 1, drop = FALSE])
  cov_global <- safe_cov(coef_mat_global)
  cov_selected <- safe_cov(coef_mat_selected)

  global_f_test <- calculate_f_test(
    point_estimates,
    cov_global,
    n_bar,
    f_threshold = f_threshold
  )
  selected_f_test <- calculate_f_test(
    point_estimates,
    cov_selected,
    n_bar,
    f_threshold = f_threshold
  )

  tibble::tibble(
    specification = label,
    selected_periods = paste(fit$time[pre_pos], collapse = ", "),
    df1 = length(pre_pos),
    df2 = n_bar - length(pre_pos),
    valid_boot_cols_global = length(valid_boot_cols),
    valid_boot_cols_selected_only = length(valid_boot_cols_selected_only),
    cov_rank_global = safe_rank(cov_global, tol = tol),
    cov_rank_selected_only = safe_rank(cov_selected, tol = tol),
    global_f_stat = global_f_test$stat,
    global_f_p = global_f_test$p,
    global_f_error = global_f_test$error,
    selected_only_f_stat = selected_f_test$stat,
    selected_only_f_p = selected_f_test$p,
    selected_only_f_equiv_p = selected_f_test$equiv_p,
    selected_only_f_error = selected_f_test$error
  )
}

build_rank_panel <- function(trade_data, unga_data, classified_events,
                             usa_top_countries) {
  treated_usa <- classified_events |>
    dplyr::filter(displaced == "USA") |>
    dplyr::pull(iso3c)

  did_countries <- unique(c(treated_usa, usa_top_countries))

  ranked_partners <- trade_data |>
    dplyr::group_by(year, exporter_iso3) |>
    dplyr::arrange(dplyr::desc(exports), .by_group = TRUE) |>
    dplyr::mutate(rank = dplyr::row_number()) |>
    dplyr::ungroup() |>
    dplyr::filter(exporter_iso3 %in% did_countries)

  rank_current <- ranked_partners |>
    dplyr::filter(importer_iso3 %in% c("CHN", "USA")) |>
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      partner = importer_iso3,
      rank
    ) |>
    tidyr::pivot_wider(
      names_from = partner,
      values_from = rank,
      names_prefix = "rank_"
    )

  panel <- unga_data |>
    dplyr::filter(iso3c %in% did_countries, year >= 1990) |>
    dplyr::select(iso3c, year, abs_distance_china) |>
    dplyr::left_join(rank_current, by = c("iso3c", "year")) |>
    dplyr::mutate(
      current_rule = as.integer(
        !is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA)
      ),
      country_id = as.integer(as.factor(iso3c)),
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      )
    ) |>
    dplyr::group_by(iso3c) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      previous_rank_CHN = dplyr::lag(rank_CHN),
      previous_rank_USA = dplyr::lag(rank_USA),
      previous_current_rule = dplyr::lag(current_rule, default = 0L),
      current_rule_spell_start =
        current_rule == 1L & previous_current_rule == 0L,
      current_rule_spell_id = cumsum(current_rule_spell_start)
    ) |>
    dplyr::ungroup()

  spell_onsets <- panel |>
    dplyr::filter(current_rule_spell_start) |>
    dplyr::select(
      iso3c,
      current_rule_spell_id,
      onset_year = year,
      previous_rank_CHN_at_onset = previous_rank_CHN,
      previous_rank_USA_at_onset = previous_rank_USA,
      onset_rank_CHN = rank_CHN,
      onset_rank_USA = rank_USA
    )

  panel |>
    dplyr::left_join(
      spell_onsets,
      by = c("iso3c", "current_rule_spell_id")
    ) |>
    dplyr::arrange(country_id, year) |>
    as.data.frame()
}

make_treatment_panel <- function(rank_panel, label) {
  panel <- rank_panel

  if (label == "current_code_china_outranks_usa") {
    panel$china_top <- panel$current_rule
  } else if (label == "current_rule_prev_china_rank_2_3_spell") {
    panel$china_top <- as.integer(
      panel$current_rule == 1L &
        !is.na(panel$previous_rank_CHN_at_onset) &
        panel$previous_rank_CHN_at_onset %in% c(2L, 3L)
    )
  } else if (label == "current_rule_onset_china_rank_2_3_spell") {
    panel$china_top <- as.integer(
      panel$current_rule == 1L &
        !is.na(panel$onset_rank_CHN) &
        panel$onset_rank_CHN %in% c(2L, 3L)
    )
  } else {
    stop("Unknown specification: ", label)
  }

  panel$china_top[is.na(panel$china_top)] <- 0L
  as.data.frame(panel)
}

validate_panel <- function(panel, label) {
  years_per_country <- panel |>
    dplyr::count(iso3c, name = "n_years")

  tibble::tibble(
    specification = label,
    n_obs = nrow(panel),
    n_countries = dplyr::n_distinct(panel$iso3c),
    min_year = min(panel$year, na.rm = TRUE),
    max_year = max(panel$year, na.rm = TRUE),
    min_years_per_country = min(years_per_country$n_years, na.rm = TRUE),
    max_years_per_country = max(years_per_country$n_years, na.rm = TRUE),
    duplicate_country_years = sum(duplicated(panel[, c("iso3c", "year")])),
    missing_outcome = sum(is.na(panel$abs_distance_china)),
    missing_treatment = sum(is.na(panel$china_top)),
    complete_rows_for_fect = panel |>
      dplyr::select(country_id, year, abs_distance_china, china_top) |>
      stats::complete.cases() |>
      sum()
  )
}

summarise_panel <- function(panel, label) {
  treat_summary <- panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      treated_years = sum(china_top),
      treatment_spells = sum(china_top == 1L & dplyr::lag(china_top, default = 0L) == 0L),
      first_on = ifelse(any(china_top == 1L), min(year[china_top == 1L]), NA_integer_),
      last_on = ifelse(any(china_top == 1L), max(year[china_top == 1L]), NA_integer_),
      .groups = "drop"
    ) |>
    dplyr::filter(treated_years > 0)

  tibble::tibble(
    specification = label,
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated_countries = dplyr::n_distinct(panel$iso3c[panel$china_top == 1L]),
    n_treated_country_years = sum(panel$china_top == 1L),
    n_treatment_spells = sum(treat_summary$treatment_spells, na.rm = TRUE),
    min_year = min(panel$year, na.rm = TRUE),
    max_year = max(panel$year, na.rm = TRUE)
  )
}

summarise_qualifying_spells <- function(panel, label) {
  panel |>
    dplyr::filter(china_top == 1L) |>
    dplyr::group_by(
      iso3c,
      country_name,
      current_rule_spell_id,
      onset_year,
      previous_rank_CHN_at_onset,
      previous_rank_USA_at_onset,
      onset_rank_CHN,
      onset_rank_USA
    ) |>
    dplyr::summarise(
      treated_years = dplyr::n(),
      first_on = min(year),
      last_on = max(year),
      .groups = "drop"
    ) |>
    dplyr::mutate(specification = label) |>
    dplyr::select(
      specification,
      iso3c,
      country_name,
      current_rule_spell_id,
      onset_year,
      previous_rank_CHN_at_onset,
      previous_rank_USA_at_onset,
      onset_rank_CHN,
      onset_rank_USA,
      treated_years,
      first_on,
      last_on
    ) |>
    dplyr::arrange(specification, onset_year, iso3c)
}

run_one_spec <- function(panel, label, current_fit = NULL) {
  fit <- if (is.null(current_fit)) {
    run_fect_analysis(panel, method = "ife")
  } else {
    current_fit
  }

  att_summary <- fect_att_summary(fit)

  list(
    fit = fit,
    result = summarise_panel(panel, label) |>
      dplyr::mutate(
        att = att_summary$att,
        se = att_summary$se,
        ci_lo = att_summary$ci_lo,
        ci_hi = att_summary$ci_hi,
        p = att_summary$p,
        r_cv = att_summary$r_cv
      ),
    f_test = inspect_fect_diagtest(fit, label)
  )
}

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
classified_events <- tar_read(classified_events)
usa_top_countries <- tar_read(usa_top_countries)
current_panel_from_targets <- tar_read(switching_panel)
current_fit <- tar_read(fect_ife)

rank_panel <- build_rank_panel(
  trade_data,
  unga_data,
  classified_events,
  usa_top_countries
)

specifications <- c(
  "current_code_china_outranks_usa",
  "current_rule_prev_china_rank_2_3_spell",
  "current_rule_onset_china_rank_2_3_spell"
)

panels <- stats::setNames(
  lapply(specifications, function(label) make_treatment_panel(rank_panel, label)),
  specifications
)

current_rule_compare <- panels[["current_code_china_outranks_usa"]] |>
  dplyr::select(iso3c, year, rebuilt_china_top = china_top) |>
  dplyr::left_join(
    current_panel_from_targets |>
      dplyr::select(iso3c, year, target_china_top = china_top),
    by = c("iso3c", "year")
  )

validation <- dplyr::bind_rows(
  lapply(names(panels), function(label) validate_panel(panels[[label]], label))
)

if (!all(current_rule_compare$rebuilt_china_top == current_rule_compare$target_china_top)) {
  stop("Rebuilt current treatment rule does not match switching_panel target.")
}

if (any(validation$duplicate_country_years > 0)) {
  stop("Panel validation failed: duplicate country-years detected.")
}

if (any(validation$missing_treatment > 0)) {
  stop("Panel validation failed: missing treatment values detected.")
}

if (any(validation$missing_outcome > 0)) {
  stop("Panel validation failed: missing outcome values detected.")
}

rule_checks <- tibble::tibble(
  check = c(
    "current_rule_matches_switching_panel_target",
    "previous_rank_restriction_only_2_or_3",
    "onset_rank_restriction_only_2_or_3"
  ),
  passed = c(
    all(current_rule_compare$rebuilt_china_top == current_rule_compare$target_china_top),
    all(
      panels[["current_rule_prev_china_rank_2_3_spell"]]$china_top == 0L |
        panels[["current_rule_prev_china_rank_2_3_spell"]]$previous_rank_CHN_at_onset %in% c(2L, 3L)
    ),
    all(
      panels[["current_rule_onset_china_rank_2_3_spell"]]$china_top == 0L |
        panels[["current_rule_onset_china_rank_2_3_spell"]]$onset_rank_CHN %in% c(2L, 3L)
    )
  )
)

if (!all(rule_checks$passed)) {
  stop("Rule validation failed.")
}

set.seed(42)
results <- list()
for (label in specifications) {
  results[[label]] <- run_one_spec(
    panels[[label]],
    label,
    current_fit = if (label == "current_code_china_outranks_usa") current_fit else NULL
  )
}

comparison <- dplyr::bind_rows(lapply(results, `[[`, "result"))
f_tests <- dplyr::bind_rows(lapply(results, `[[`, "f_test"))
qualifying_spells <- dplyr::bind_rows(
  lapply(names(panels), function(label) summarise_qualifying_spells(panels[[label]], label))
)

write.csv(
  comparison,
  file.path(out_dir, "current_rule_china_rank_restriction_factor_model_comparison.csv"),
  row.names = FALSE
)
write.csv(
  f_tests,
  file.path(out_dir, "current_rule_china_rank_restriction_factor_model_f_tests.csv"),
  row.names = FALSE
)
write.csv(
  validation,
  file.path(out_dir, "current_rule_china_rank_restriction_panel_validation.csv"),
  row.names = FALSE
)
write.csv(
  rule_checks,
  file.path(out_dir, "current_rule_china_rank_restriction_rule_checks.csv"),
  row.names = FALSE
)
write.csv(
  qualifying_spells,
  file.path(out_dir, "current_rule_china_rank_restriction_qualifying_spells.csv"),
  row.names = FALSE
)

report_path <- file.path(out_dir, "2026-05-14_current_rule_china_rank_restriction_factor_model.md")
sink(report_path)
cat("# Factor model diagnostic: current rule restricted by China rank\n\n")
cat("Date: 2026-05-14\n\n")
cat("This diagnostic does not modify `_targets.R` or write to the targets store. The main restricted specification keeps the current treatment rule but retains only treatment spells whose previous observed China rank at spell onset was 2 or 3. A complementary specification uses China's rank at the onset year itself.\n\n")
cat("## Validation\n\n")
print(validation)
cat("\n## Rule checks\n\n")
print(rule_checks)
cat("\n## Comparison\n\n")
print(comparison)
cat("\n## F-test diagnostics\n\n")
print(f_tests)
cat("\n## Qualifying spells\n\n")
print(qualifying_spells, n = nrow(qualifying_spells))
sink()

print(comparison)
cat("\nWrote:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, "current_rule_china_rank_restriction_factor_model_comparison.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_rule_china_rank_restriction_factor_model_f_tests.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_rule_china_rank_restriction_panel_validation.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_rule_china_rank_restriction_rule_checks.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_rule_china_rank_restriction_qualifying_spells.csv"), "\n", sep = "")
