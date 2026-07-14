#!/usr/bin/env Rscript

# Diagnostic: compare fixed-r IFE estimates for two treatment definitions:
# (1) literal China rank 1; (2) China becomes rank 1 after an observed reversal,
# with spell start year >= 2000. This script does not modify _targets.R or the
# targets store.

library(targets)
library(dplyr)
library(tidyr)
library(countrycode)
library(fect)
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

inspect_fect_diagtest <- function(fit, label, r_fixed, proportion = 0.3,
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
    r_fixed = r_fixed,
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
      top_partner = importer_iso3
    )

  rank_china_usa <- ranked_partners |>
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
    dplyr::left_join(rank_china_usa, by = c("iso3c", "year")) |>
    dplyr::left_join(top_partner, by = c("iso3c", "year")) |>
    dplyr::mutate(
      current_rule = as.integer(
        !is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA)
      ),
      china_is_top = !is.na(rank_CHN) & rank_CHN == 1,
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
      previous_observed_year = dplyr::lag(year),
      previous_china_is_top = dplyr::lag(china_is_top),
      china_top_spell_start =
        china_is_top & !dplyr::lag(china_is_top, default = FALSE),
      china_top_spell_id = cumsum(china_top_spell_start)
    ) |>
    dplyr::ungroup()

  spell_onsets <- panel |>
    dplyr::filter(china_top_spell_start) |>
    dplyr::select(
      iso3c,
      china_top_spell_id,
      spell_start_year = year,
      previous_observed_year_at_start = previous_observed_year,
      previous_china_is_top_at_start = previous_china_is_top
    )

  panel |>
    dplyr::left_join(
      spell_onsets,
      by = c("iso3c", "china_top_spell_id")
    ) |>
    dplyr::arrange(country_id, year) |>
    as.data.frame()
}

make_treatment_panel <- function(rank_panel, label) {
  panel <- rank_panel

  if (label == "text_rule_china_rank_1") {
    panel$china_top <- as.integer(panel$china_is_top)
  } else if (label == "china_rank_1_reversal_start_ge_2000") {
    panel$china_top <- as.integer(
      panel$china_is_top &
        !is.na(panel$spell_start_year) &
        panel$spell_start_year >= 2000 &
        !is.na(panel$previous_observed_year_at_start) &
        !is.na(panel$previous_china_is_top_at_start) &
        panel$previous_china_is_top_at_start == FALSE
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
  country_summary <- panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      treated_years = sum(china_top),
      treatment_spells = sum(
        china_top == 1L & dplyr::lag(china_top, default = 0L) == 0L
      ),
      .groups = "drop"
    ) |>
    dplyr::filter(treated_years > 0)

  tibble::tibble(
    specification = label,
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated_countries = dplyr::n_distinct(panel$iso3c[panel$china_top == 1L]),
    n_treated_country_years = sum(panel$china_top == 1L),
    n_treatment_spells = sum(country_summary$treatment_spells, na.rm = TRUE),
    min_year = min(panel$year, na.rm = TRUE),
    max_year = max(panel$year, na.rm = TRUE)
  )
}

run_fixed_r_fect <- function(panel, r_fixed, nboots = 500,
                             fml = abs_distance_china ~ china_top) {
  set.seed(42)

  fml_vars <- all.vars(fml)
  keep_cols <- unique(c("country_id", "year", fml_vars))
  fect_data <- panel |>
    dplyr::select(dplyr::all_of(keep_cols)) |>
    tidyr::drop_na() |>
    dplyr::mutate(country_id = as.integer(as.factor(country_id))) |>
    as.data.frame()

  fect::fect(
    fml,
    data = fect_data,
    index = c("country_id", "year"),
    method = "ife",
    force = "two-way",
    se = TRUE,
    nboots = nboots,
    parallel = FALSE,
    CV = FALSE,
    r = r_fixed
  )
}

summarise_fit <- function(fit, label, r_fixed) {
  se <- stats::sd(fit$att.avg.boot)
  p <- 2 * stats::pnorm(-abs(fit$att.avg / se))

  tibble::tibble(
    specification = label,
    r_fixed = r_fixed,
    att = fit$att.avg,
    se = se,
    ci_lo = fit$att.avg - 1.96 * se,
    ci_hi = fit$att.avg + 1.96 * se,
    p = p,
    n_valid_att_avg_boot = sum(!is.na(fit$att.avg.boot))
  )
}

run_one_spec_r <- function(panel, label, r_fixed) {
  fit <- run_fixed_r_fect(panel, r_fixed = r_fixed)

  list(
    result = summarise_panel(panel, label) |>
      dplyr::mutate(r_fixed = r_fixed) |>
      dplyr::left_join(
        summarise_fit(fit, label, r_fixed),
        by = c("specification", "r_fixed")
      ),
    f_test = inspect_fect_diagtest(fit, label, r_fixed)
  )
}

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
classified_events <- tar_read(classified_events)
usa_top_countries <- tar_read(usa_top_countries)

rank_panel <- build_rank_panel(
  trade_data,
  unga_data,
  classified_events,
  usa_top_countries
)

specifications <- c(
  "text_rule_china_rank_1",
  "china_rank_1_reversal_start_ge_2000"
)
r_values <- c(1L, 2L)

panels <- stats::setNames(
  lapply(specifications, function(label) make_treatment_panel(rank_panel, label)),
  specifications
)

validation <- dplyr::bind_rows(
  lapply(names(panels), function(label) validate_panel(panels[[label]], label))
)

rule_checks <- tibble::tibble(
  check = c(
    "literal_rule_only_china_top",
    "post2000_rule_only_china_top",
    "post2000_rule_starts_ge_2000",
    "post2000_rule_has_observed_prior_not_china_top"
  ),
  passed = c(
    all(panels[["text_rule_china_rank_1"]]$china_top == 0L |
          panels[["text_rule_china_rank_1"]]$china_is_top),
    all(panels[["china_rank_1_reversal_start_ge_2000"]]$china_top == 0L |
          panels[["china_rank_1_reversal_start_ge_2000"]]$china_is_top),
    all(panels[["china_rank_1_reversal_start_ge_2000"]]$china_top == 0L |
          panels[["china_rank_1_reversal_start_ge_2000"]]$spell_start_year >= 2000),
    all(panels[["china_rank_1_reversal_start_ge_2000"]]$china_top == 0L |
          (
            !is.na(panels[["china_rank_1_reversal_start_ge_2000"]]$previous_observed_year_at_start) &
              panels[["china_rank_1_reversal_start_ge_2000"]]$previous_china_is_top_at_start == FALSE
          ))
  )
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

if (!all(rule_checks$passed)) {
  stop("Rule validation failed.")
}

set.seed(42)
results <- list()
for (label in specifications) {
  for (r_fixed in r_values) {
    result_name <- paste(label, r_fixed, sep = "_r")
    results[[result_name]] <- run_one_spec_r(
      panels[[label]],
      label,
      r_fixed
    )
  }
}

comparison <- dplyr::bind_rows(lapply(results, `[[`, "result")) |>
  dplyr::arrange(r_fixed, specification)

f_tests <- dplyr::bind_rows(lapply(results, `[[`, "f_test")) |>
  dplyr::arrange(r_fixed, specification)

deltas_by_r <- comparison |>
  dplyr::select(
    specification,
    r_fixed,
    att,
    se,
    p,
    n_treated_country_years,
    n_treatment_spells
  ) |>
  tidyr::pivot_wider(
    names_from = specification,
    values_from = c(
      att,
      se,
      p,
      n_treated_country_years,
      n_treatment_spells
    )
  ) |>
  dplyr::mutate(
    delta_att = att_china_rank_1_reversal_start_ge_2000 -
      att_text_rule_china_rank_1,
    delta_se = se_china_rank_1_reversal_start_ge_2000 -
      se_text_rule_china_rank_1,
    se_ratio = se_china_rank_1_reversal_start_ge_2000 /
      se_text_rule_china_rank_1,
    delta_p = p_china_rank_1_reversal_start_ge_2000 -
      p_text_rule_china_rank_1,
    delta_treated_country_years =
      n_treated_country_years_china_rank_1_reversal_start_ge_2000 -
      n_treated_country_years_text_rule_china_rank_1,
    delta_treatment_spells =
      n_treatment_spells_china_rank_1_reversal_start_ge_2000 -
      n_treatment_spells_text_rule_china_rank_1
  )

write.csv(
  comparison,
  file.path(out_dir, "china_first_reversal_post2000_fixed_r_comparison.csv"),
  row.names = FALSE
)
write.csv(
  deltas_by_r,
  file.path(out_dir, "china_first_reversal_post2000_fixed_r_deltas.csv"),
  row.names = FALSE
)
write.csv(
  f_tests,
  file.path(out_dir, "china_first_reversal_post2000_fixed_r_f_tests.csv"),
  row.names = FALSE
)
write.csv(
  validation,
  file.path(out_dir, "china_first_reversal_post2000_fixed_r_panel_validation.csv"),
  row.names = FALSE
)
write.csv(
  rule_checks,
  file.path(out_dir, "china_first_reversal_post2000_fixed_r_rule_checks.csv"),
  row.names = FALSE
)

report_path <- file.path(out_dir, "2026-05-15_china_first_reversal_post2000_fixed_r.md")
sink(report_path)
cat("# Fixed-r IFE diagnostic: China #1 versus post-2000 reversals\n\n")
cat("Date: 2026-05-15\n\n")
cat("This diagnostic fixes the number of IFE latent factors at r = 1 and r = 2. It compares the literal China #1 treatment with the China-becomes-#1 post-2000 reversal treatment. It does not modify `_targets.R` or write to the targets store.\n\n")
cat("## Panel validation\n\n")
print(validation)
cat("\n## Rule checks\n\n")
print(rule_checks)
cat("\n## Fixed-r comparison\n\n")
print(comparison)
cat("\n## Within-r deltas\n\n")
print(deltas_by_r)
cat("\n## F-test diagnostics\n\n")
print(f_tests)
cat("\n## Session info\n\n")
print(sessionInfo())
sink()

print(comparison)
cat("\nWithin-r deltas:\n")
print(deltas_by_r)
cat("\nWrote:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, "china_first_reversal_post2000_fixed_r_comparison.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_first_reversal_post2000_fixed_r_deltas.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_first_reversal_post2000_fixed_r_f_tests.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_first_reversal_post2000_fixed_r_panel_validation.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "china_first_reversal_post2000_fixed_r_rule_checks.csv"), "\n", sep = "")
