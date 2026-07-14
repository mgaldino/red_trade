#!/usr/bin/env Rscript

# Diagnostic: compare factor-model treatment rules around China becoming
# the top export partner after the USA. This script does not modify
# _targets.R or write to the targets store.

library(targets)
library(dplyr)
library(tidyr)
library(countrycode)
library(here)

options(scipen = 999)

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

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

  top_partner <- ranked_partners |>
    dplyr::filter(rank == 1) |>
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      top_partner = importer_iso3,
      top_exports = exports
    )

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
    dplyr::left_join(top_partner, by = c("iso3c", "year")) |>
    dplyr::mutate(
      china_is_top = !is.na(rank_CHN) & rank_CHN == 1,
      country_id = as.integer(as.factor(iso3c)),
      country_name = countrycode::countrycode(iso3c, "iso3c", "country.name")
    ) |>
    dplyr::group_by(iso3c) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      previous_observed_year = dplyr::lag(year),
      previous_observed_top_partner = dplyr::lag(top_partner),
      previous_observed_is_adjacent_year =
        !is.na(previous_observed_year) & year - previous_observed_year == 1,
      china_top_spell_start =
        china_is_top & !dplyr::lag(china_is_top, default = FALSE),
      china_top_spell_id = cumsum(china_top_spell_start)
    ) |>
    dplyr::group_by(iso3c, china_top_spell_id) |>
    dplyr::mutate(
      top_partner_before_china_spell = ifelse(
        any(china_top_spell_start),
        previous_observed_top_partner[which(china_top_spell_start)[1]],
        NA_character_
      ),
      year_before_china_spell = ifelse(
        any(china_top_spell_start),
        previous_observed_year[which(china_top_spell_start)[1]],
        NA_integer_
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(country_id, year)

  as.data.frame(panel)
}

make_treatment_panel <- function(rank_panel, label) {
  panel <- rank_panel

  if (label == "current_code_china_outranks_usa") {
    panel$china_top <- as.integer(
      !is.na(panel$rank_CHN) &
        (is.na(panel$rank_USA) | panel$rank_CHN < panel$rank_USA)
    )
  } else if (label == "text_rule_china_rank_1") {
    panel$china_top <- as.integer(panel$china_is_top)
  } else if (
    label %in% c(
      "china_rank_1_after_usa_spell",
      "china_rank_1_after_usa_spell_drop_1yr_countries"
    )
  ) {
    panel$china_top <- as.integer(
      panel$china_is_top &
        !is.na(panel$top_partner_before_china_spell) &
        panel$top_partner_before_china_spell == "USA"
    )
  } else if (label == "china_rank_1_after_usa_previous_observed_year") {
    panel$china_top <- as.integer(
      panel$china_is_top &
        !is.na(panel$previous_observed_top_partner) &
        panel$previous_observed_top_partner == "USA"
    )
  } else {
    stop("Unknown treatment label: ", label)
  }

  panel$china_top[is.na(panel$china_top)] <- 0L
  as.data.frame(panel)
}

identify_one_year_treated_countries <- function(panel) {
  panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      treated_years = sum(china_top),
      first_on = ifelse(any(china_top == 1), min(year[china_top == 1]), NA_integer_),
      last_on = ifelse(any(china_top == 1), max(year[china_top == 1]), NA_integer_),
      .groups = "drop"
    ) |>
    dplyr::filter(treated_years == 1) |>
    dplyr::arrange(iso3c)
}

drop_one_year_treated_countries <- function(panel) {
  one_year_countries <- identify_one_year_treated_countries(panel) |>
    dplyr::pull(iso3c)

  panel |>
    dplyr::filter(!iso3c %in% one_year_countries) |>
    dplyr::mutate(country_id = as.integer(as.factor(iso3c))) |>
    as.data.frame()
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
      switches = sum(abs(diff(china_top))),
      first_on = ifelse(any(china_top == 1), min(year[china_top == 1]), NA_integer_),
      last_on = ifelse(any(china_top == 1), max(year[china_top == 1]), NA_integer_),
      .groups = "drop"
    ) |>
    dplyr::filter(treated_years > 0)

  tibble::tibble(
    specification = label,
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated_countries = dplyr::n_distinct(panel$iso3c[panel$china_top == 1]),
    n_treated_country_years = sum(panel$china_top == 1),
    n_switching_treated_countries = sum(treat_summary$switches > 1, na.rm = TRUE),
    n_absorbing_treated_countries = sum(treat_summary$switches <= 1, na.rm = TRUE),
    min_year = min(panel$year, na.rm = TRUE),
    max_year = max(panel$year, na.rm = TRUE)
  )
}

summarise_transitions <- function(panel, label) {
  first_character_or_na <- function(x) {
    x <- x[!is.na(x)]
    if (length(x) == 0) {
      return(NA_character_)
    }
    x[1]
  }

  first_integer_or_na <- function(x) {
    x <- x[!is.na(x)]
    if (length(x) == 0) {
      return(NA_integer_)
    }
    as.integer(x[1])
  }

  panel |>
    dplyr::filter(china_top == 1) |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      treated_years = dplyr::n(),
      first_on = min(year),
      last_on = max(year),
      first_top_partner_before_china_spell =
        first_character_or_na(top_partner_before_china_spell),
      first_previous_observed_top_partner =
        first_character_or_na(previous_observed_top_partner),
      first_year_before_china_spell =
        first_integer_or_na(year_before_china_spell),
      first_previous_observed_year =
        first_integer_or_na(previous_observed_year),
      .groups = "drop"
    ) |>
    dplyr::mutate(specification = label) |>
    dplyr::select(
      specification,
      iso3c,
      country_name,
      treated_years,
      first_on,
      last_on,
      first_top_partner_before_china_spell,
      first_previous_observed_top_partner,
      first_year_before_china_spell,
      first_previous_observed_year
    )
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
  "text_rule_china_rank_1",
  "china_rank_1_after_usa_spell",
  "china_rank_1_after_usa_spell_drop_1yr_countries",
  "china_rank_1_after_usa_previous_observed_year"
)

base_specifications <- c(
  "current_code_china_outranks_usa",
  "text_rule_china_rank_1",
  "china_rank_1_after_usa_spell",
  "china_rank_1_after_usa_previous_observed_year"
)

panels <- stats::setNames(
  lapply(base_specifications, function(label) make_treatment_panel(rank_panel, label)),
  base_specifications
)
one_year_removed_countries <- identify_one_year_treated_countries(
  panels[["china_rank_1_after_usa_spell"]]
)
panels[["china_rank_1_after_usa_spell_drop_1yr_countries"]] <-
  drop_one_year_treated_countries(panels[["china_rank_1_after_usa_spell"]])
panels <- panels[specifications]

current_keys <- current_panel_from_targets |>
  dplyr::select(iso3c, year)
rank_panel_keys <- rank_panel |>
  dplyr::select(iso3c, year)

if (
  nrow(dplyr::anti_join(current_keys, rank_panel_keys, by = c("iso3c", "year"))) > 0 ||
    nrow(dplyr::anti_join(rank_panel_keys, current_keys, by = c("iso3c", "year"))) > 0
) {
  stop("Rank panel and current target panel do not use the same country-year rows.")
}

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
    "text_rule_exactly_rank_CHN_1",
    "spell_rule_only_china_top",
    "spell_rule_previous_top_usa_when_on",
    "drop_1yr_rule_only_china_top",
    "drop_1yr_rule_previous_top_usa_when_on",
    "drop_1yr_rule_has_no_one_year_treated_countries",
    "previous_observed_rule_only_china_top",
    "previous_observed_rule_previous_top_usa_when_on"
  ),
  passed = c(
    all(current_rule_compare$rebuilt_china_top == current_rule_compare$target_china_top),
    all(
      panels[["text_rule_china_rank_1"]]$china_top ==
        as.integer(!is.na(panels[["text_rule_china_rank_1"]]$rank_CHN) &
                     panels[["text_rule_china_rank_1"]]$rank_CHN == 1)
    ),
    all(panels[["china_rank_1_after_usa_spell"]]$china_top == 0 |
          panels[["china_rank_1_after_usa_spell"]]$china_is_top),
    all(panels[["china_rank_1_after_usa_spell"]]$china_top == 0 |
          panels[["china_rank_1_after_usa_spell"]]$top_partner_before_china_spell == "USA"),
    all(panels[["china_rank_1_after_usa_spell_drop_1yr_countries"]]$china_top == 0 |
          panels[["china_rank_1_after_usa_spell_drop_1yr_countries"]]$china_is_top),
    all(panels[["china_rank_1_after_usa_spell_drop_1yr_countries"]]$china_top == 0 |
          panels[["china_rank_1_after_usa_spell_drop_1yr_countries"]]$top_partner_before_china_spell == "USA"),
    nrow(identify_one_year_treated_countries(
      panels[["china_rank_1_after_usa_spell_drop_1yr_countries"]]
    )) == 0,
    all(panels[["china_rank_1_after_usa_previous_observed_year"]]$china_top == 0 |
          panels[["china_rank_1_after_usa_previous_observed_year"]]$china_is_top),
    all(panels[["china_rank_1_after_usa_previous_observed_year"]]$china_top == 0 |
          panels[["china_rank_1_after_usa_previous_observed_year"]]$previous_observed_top_partner == "USA")
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
treated_countries <- dplyr::bind_rows(
  lapply(names(panels), function(label) summarise_transitions(panels[[label]], label))
)

write.csv(
  comparison,
  file.path(out_dir, "china_top_after_usa_factor_model_comparison.csv"),
  row.names = FALSE
)
write.csv(
  f_tests,
  file.path(out_dir, "china_top_after_usa_factor_model_f_tests.csv"),
  row.names = FALSE
)
write.csv(
  validation,
  file.path(out_dir, "china_top_after_usa_factor_model_panel_validation.csv"),
  row.names = FALSE
)
write.csv(
  rule_checks,
  file.path(out_dir, "china_top_after_usa_factor_model_rule_checks.csv"),
  row.names = FALSE
)
write.csv(
  one_year_removed_countries,
  file.path(out_dir, "china_top_after_usa_factor_model_removed_1yr_countries.csv"),
  row.names = FALSE
)
write.csv(
  treated_countries,
  file.path(out_dir, "china_top_after_usa_factor_model_treated_countries.csv"),
  row.names = FALSE
)

report_path <- file.path(out_dir, "2026-05-13_china_top_after_usa_factor_model.md")
sink(report_path)
cat("# Factor model diagnostic: China #1 after USA\n\n")
cat("Date: 2026-05-13\n\n")
cat("This diagnostic does not modify `_targets.R` or write to the targets store. It compares the current factor-model rule, the textual `rank_CHN == 1` rule, and two interpretations of `China is #1 and the previous top partner was the USA`.\n\n")
cat("Definitions:\n\n")
cat("- `china_rank_1_after_usa_spell`: China is currently #1 and the top partner immediately before the current China-top spell was USA. Treatment stays on for the China-top spell.\n")
cat("- `china_rank_1_after_usa_spell_drop_1yr_countries`: same spell rule, excluding from the panel countries whose treated spell lasts exactly one year.\n")
cat("- `china_rank_1_after_usa_previous_observed_year`: China is currently #1 and the previous observed country-year's top partner was USA. This is a stricter transition-year pulse.\n\n")
cat("## Countries removed from the one-year spell diagnostic\n\n")
print(one_year_removed_countries)
cat("\n")
cat("## Panel validation\n\n")
print(validation)
cat("\n## Rule checks\n\n")
print(rule_checks)
cat("\n## Comparison\n\n")
print(comparison)
cat("\n## F-test diagnostics\n\n")
print(f_tests)
cat("\n## Treated countries\n\n")
print(treated_countries, n = nrow(treated_countries))
sink()

print(comparison)
cat("\nWrote:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_after_usa_factor_model_comparison.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_after_usa_factor_model_f_tests.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_after_usa_factor_model_panel_validation.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_after_usa_factor_model_rule_checks.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_after_usa_factor_model_removed_1yr_countries.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_top_after_usa_factor_model_treated_countries.csv"), "\n", sep = "")
