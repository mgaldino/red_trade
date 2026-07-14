#!/usr/bin/env Rscript

# Inspect the fect diagnostic F-test covariance matrix for the baseline
# factor model and for the textual China-top-partner treatment rule.
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

build_text_rule_panel <- function(trade_data, unga_data, classified_events,
                                  usa_top_countries) {
  treated_usa <- classified_events |>
    dplyr::filter(displaced == "USA") |>
    dplyr::pull(iso3c)

  did_countries <- unique(c(treated_usa, usa_top_countries))

  rank_current <- trade_data |>
    dplyr::group_by(year, exporter_iso3) |>
    dplyr::arrange(dplyr::desc(exports), .by_group = TRUE) |>
    dplyr::mutate(rank = dplyr::row_number()) |>
    dplyr::ungroup() |>
    dplyr::filter(exporter_iso3 %in% did_countries, importer_iso3 == "CHN") |>
    dplyr::select(iso3c = exporter_iso3, year, rank_CHN = rank)

  panel <- unga_data |>
    dplyr::filter(iso3c %in% did_countries, year >= 1990) |>
    dplyr::select(iso3c, year, abs_distance_china) |>
    dplyr::left_join(rank_current, by = c("iso3c", "year")) |>
    dplyr::mutate(
      china_top = as.integer(!is.na(rank_CHN) & rank_CHN == 1),
      country_id = as.integer(as.factor(iso3c)),
      country_name = countrycode::countrycode(iso3c, "iso3c", "country.name")
    ) |>
    dplyr::arrange(country_id, year)

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
  dropped_first_selected_period <- FALSE

  if (length(pre_pos) == n_all_nonpositive_periods) {
    pre_pos <- pre_pos[-1]
    dropped_first_selected_period <- TRUE
  }

  n_bar <- max(fit$count[fit$time %in% pre.periods], na.rm = TRUE)

  att_boot <- as.matrix(fit$att.boot)
  valid_boot_cols <- which(apply(!is.na(att_boot), 2, all))
  valid_boot_cols_selected_only <- which(
    apply(!is.na(att_boot[pre_pos, , drop = FALSE]), 2, all)
  )
  n_valid_boot_cols <- length(valid_boot_cols)
  n_valid_boot_cols_selected_only <- length(valid_boot_cols_selected_only)
  att_boot_valid <- att_boot[, valid_boot_cols, drop = FALSE]

  if (length(pre_pos) > 1) {
    coef_mat <- att_boot_valid[pre_pos, , drop = FALSE]
    coef_mat_selected_only <- att_boot[
      pre_pos, valid_boot_cols_selected_only, drop = FALSE
    ]
  } else {
    coef_mat <- t(as.matrix(att_boot_valid[pre_pos, ]))
    coef_mat_selected_only <- t(as.matrix(
      att_boot[pre_pos, valid_boot_cols_selected_only]
    ))
  }

  point_estimates <- as.matrix(fit$est.att[pre_pos, 1, drop = FALSE])
  cov_mat <- stats::cov(t(coef_mat))
  cov_mat_selected_only <- stats::cov(t(coef_mat_selected_only))
  global_f_test <- calculate_f_test(
    point_estimates,
    cov_mat,
    n_bar,
    f_threshold = f_threshold
  )
  selected_only_f_test <- calculate_f_test(
    point_estimates,
    cov_mat_selected_only,
    n_bar,
    f_threshold = f_threshold
  )
  solve_error <- tryCatch({
    solve(cov_mat)
    NA_character_
  }, error = function(e) conditionMessage(e))
  selected_only_solve_error <- tryCatch({
    solve(cov_mat_selected_only)
    NA_character_
  }, error = function(e) conditionMessage(e))

  eigenvalues <- tryCatch(
    eigen((cov_mat + t(cov_mat)) / 2, symmetric = TRUE,
          only.values = TRUE)$values,
    error = function(e) numeric()
  )

  singular_values <- tryCatch(
    svd(cov_mat)$d,
    error = function(e) numeric()
  )
  selected_only_singular_values <- tryCatch(
    svd(cov_mat_selected_only)$d,
    error = function(e) numeric()
  )

  row_vars_global <- apply(coef_mat, 1, stats::var)
  unique_boot_values_global <- apply(coef_mat, 1, function(x) {
    length(unique(signif(x, 12)))
  })
  row_vars_selected_only <- apply(coef_mat_selected_only, 1, stats::var)
  unique_boot_values_selected_only <- apply(coef_mat_selected_only, 1, function(x) {
    length(unique(signif(x, 12)))
  })

  cor_mat <- suppressWarnings(stats::cor(t(coef_mat)))
  perfect_pairs_idx <- which(
    abs(cor_mat) > 1 - 1e-8 & row(cor_mat) < col(cor_mat),
    arr.ind = TRUE
  )
  perfect_pairs <- tibble::tibble()
  if (nrow(perfect_pairs_idx) > 0) {
    perfect_pairs <- tibble::tibble(
      specification = label,
      period_a = fit$time[pre_pos[perfect_pairs_idx[, "row"]]],
      period_b = fit$time[pre_pos[perfect_pairs_idx[, "col"]]],
      correlation = cor_mat[perfect_pairs_idx]
    )
  }

  selected_periods <- tibble::tibble(
    specification = label,
    period = fit$time[pre_pos],
    count = fit$count[pre_pos],
    att = as.numeric(point_estimates),
    se_reported = fit$est.att[pre_pos, 2],
    global_filter_bootstrap_variance = row_vars_global,
    global_filter_unique_bootstrap_values = unique_boot_values_global,
    selected_only_bootstrap_variance = row_vars_selected_only,
    selected_only_unique_bootstrap_values = unique_boot_values_selected_only
  )

  summary <- tibble::tibble(
    specification = label,
    r_cv = if (!is.null(fit$r.cv)) fit$r.cv else NA_real_,
    n_time_rows = length(fit$time),
    n_nonpositive_periods = n_all_nonpositive_periods,
    n_selected_periods_after_drop = length(pre_pos),
    selected_periods = paste(fit$time[pre_pos], collapse = ", "),
    dropped_first_selected_period = dropped_first_selected_period,
    n_bar = n_bar,
    df1 = length(pre_pos),
    df2 = n_bar - length(pre_pos),
    att_boot_rows = nrow(att_boot),
    att_boot_cols = ncol(att_boot),
    valid_boot_cols = n_valid_boot_cols,
    valid_boot_cols_selected_only = n_valid_boot_cols_selected_only,
    cov_dim = nrow(cov_mat),
    cov_rank = qr(cov_mat, tol = tol)$rank,
    selected_only_cov_rank = qr(cov_mat_selected_only, tol = tol)$rank,
    max_cov_rank_given_global_boots = n_valid_boot_cols - 1,
    rank_deficiency_forced_by_boot_count =
      (n_valid_boot_cols - 1) < length(pre_pos),
    min_eigenvalue = if (length(eigenvalues) > 0) min(eigenvalues) else NA_real_,
    max_eigenvalue = if (length(eigenvalues) > 0) max(eigenvalues) else NA_real_,
    min_singular_value = if (length(singular_values) > 0) min(singular_values) else NA_real_,
    max_singular_value = if (length(singular_values) > 0) max(singular_values) else NA_real_,
    selected_only_min_singular_value =
      if (length(selected_only_singular_values) > 0) {
        min(selected_only_singular_values)
      } else {
        NA_real_
      },
    selected_only_max_singular_value =
      if (length(selected_only_singular_values) > 0) {
        max(selected_only_singular_values)
      } else {
        NA_real_
      },
    zero_variance_selected_periods = sum(row_vars_global < tol, na.rm = TRUE),
    perfect_correlation_pairs = nrow(perfect_pairs),
    solve_ok = is.na(solve_error),
    solve_error = ifelse(is.na(solve_error), "", solve_error),
    selected_only_solve_ok = is.na(selected_only_solve_error),
    selected_only_solve_error = ifelse(
      is.na(selected_only_solve_error),
      "",
      selected_only_solve_error
    ),
    f_threshold = f_threshold,
    global_filter_f_stat = global_f_test$stat,
    global_filter_f_p = global_f_test$p,
    global_filter_f_equiv_p = global_f_test$equiv_p,
    selected_only_f_stat = selected_only_f_test$stat,
    selected_only_f_p = selected_only_f_test$p,
    selected_only_f_equiv_p = selected_only_f_test$equiv_p
  )

  list(
    summary = summary,
    selected_periods = selected_periods,
    bootstrap_support = tibble::tibble(
      specification = label,
      period = fit$time,
      count = fit$count,
      nonmissing_boot_cols = rowSums(!is.na(att_boot)),
      missing_boot_cols = rowSums(is.na(att_boot))
    ),
    eigenvalues = tibble::tibble(
      specification = label,
      index = seq_along(eigenvalues),
      eigenvalue = eigenvalues
    ),
    perfect_pairs = perfect_pairs
  )
}

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
classified_events <- tar_read(classified_events)
usa_top_countries <- tar_read(usa_top_countries)
current_panel <- tar_read(switching_panel)
current_fit <- tar_read(fect_ife)

text_rule_panel <- build_text_rule_panel(
  trade_data,
  unga_data,
  classified_events,
  usa_top_countries
)

rule_check <- text_rule_panel$china_top ==
  as.integer(!is.na(text_rule_panel$rank_CHN) & text_rule_panel$rank_CHN == 1)
if (!all(rule_check)) {
  stop("Textual-rule panel failed validation: china_top is not rank_CHN == 1.")
}

panel_validation_df <- dplyr::bind_rows(
  validate_panel(current_panel, "current_code_china_outranks_usa"),
  validate_panel(text_rule_panel, "text_rule_china_rank_1")
)

if (any(panel_validation_df$duplicate_country_years > 0)) {
  stop("Panel validation failed: duplicate country-years detected.")
}

if (any(panel_validation_df$missing_treatment > 0)) {
  stop("Panel validation failed: missing treatment values detected.")
}

current_keys <- current_panel |>
  dplyr::select(iso3c, year)
text_rule_keys <- text_rule_panel |>
  dplyr::select(iso3c, year)

current_not_text_rule <- dplyr::anti_join(
  current_keys,
  text_rule_keys,
  by = c("iso3c", "year")
)
text_rule_not_current <- dplyr::anti_join(
  text_rule_keys,
  current_keys,
  by = c("iso3c", "year")
)

if (nrow(current_not_text_rule) > 0 || nrow(text_rule_not_current) > 0) {
  stop("Panel validation failed: current and text-rule panels do not use the same country-year rows.")
}

set.seed(42)
text_rule_fit <- run_fect_analysis(text_rule_panel, method = "ife")

current_diag <- inspect_fect_diagtest(
  current_fit,
  "current_code_china_outranks_usa"
)
text_rule_diag <- inspect_fect_diagtest(
  text_rule_fit,
  "text_rule_china_rank_1"
)

summarise_fit <- function(fit, label) {
  att_summary <- fect_att_summary(fit)
  tibble::tibble(
    specification = label,
    att = att_summary$att,
    se = att_summary$se,
    ci_lo = att_summary$ci_lo,
    ci_hi = att_summary$ci_hi,
    p = att_summary$p,
    r_cv = att_summary$r_cv
  )
}

model_results_df <- dplyr::bind_rows(
  summarise_fit(current_fit, "current_code_china_outranks_usa"),
  summarise_fit(text_rule_fit, "text_rule_china_rank_1")
)

summary_df <- dplyr::bind_rows(current_diag$summary, text_rule_diag$summary)
f_test_results_df <- summary_df |>
  dplyr::select(
    specification,
    r_cv,
    selected_periods,
    df1,
    df2,
    valid_boot_cols,
    valid_boot_cols_selected_only,
    cov_rank,
    selected_only_cov_rank,
    solve_ok,
    selected_only_solve_ok,
    global_filter_f_stat,
    global_filter_f_p,
    selected_only_f_stat,
    selected_only_f_p,
    selected_only_f_equiv_p
  )
selected_periods_df <- dplyr::bind_rows(
  current_diag$selected_periods,
  text_rule_diag$selected_periods
)
eigenvalues_df <- dplyr::bind_rows(
  current_diag$eigenvalues,
  text_rule_diag$eigenvalues
)
bootstrap_support_df <- dplyr::bind_rows(
  current_diag$bootstrap_support,
  text_rule_diag$bootstrap_support
)
perfect_pairs_df <- dplyr::bind_rows(
  current_diag$perfect_pairs,
  text_rule_diag$perfect_pairs
)

write.csv(
  model_results_df,
  file.path(out_dir, "fect_f_test_singularity_model_results.csv"),
  row.names = FALSE
)
write.csv(
  panel_validation_df,
  file.path(out_dir, "fect_f_test_singularity_panel_validation.csv"),
  row.names = FALSE
)
write.csv(
  summary_df,
  file.path(out_dir, "fect_f_test_singularity_summary.csv"),
  row.names = FALSE
)
write.csv(
  f_test_results_df,
  file.path(out_dir, "fect_f_test_selected_period_filter_results.csv"),
  row.names = FALSE
)
write.csv(
  selected_periods_df,
  file.path(out_dir, "fect_f_test_singularity_selected_periods.csv"),
  row.names = FALSE
)
write.csv(
  eigenvalues_df,
  file.path(out_dir, "fect_f_test_singularity_eigenvalues.csv"),
  row.names = FALSE
)
write.csv(
  bootstrap_support_df,
  file.path(out_dir, "fect_f_test_singularity_bootstrap_support.csv"),
  row.names = FALSE
)
write.csv(
  perfect_pairs_df,
  file.path(out_dir, "fect_f_test_singularity_perfect_pairs.csv"),
  row.names = FALSE
)

report_path <- file.path(out_dir, "2026-05-13_fect_f_test_singularity.md")
sink(report_path)
cat("# fect F-test singularity diagnostic\n\n")
cat("Date: 2026-05-13\n\n")
cat("This diagnostic reproduces the matrix calculation used by `fect:::diagtest()` for the F-test. It does not modify `_targets.R` or write to the targets store.\n\n")
cat("The selected-only F-test is a post-estimation diagnostic: the IFE model is unchanged, but the bootstrap covariance matrix is recomputed after filtering missing bootstrap draws only across the periods selected for the F-test.\n\n")
cat("## Panel validation\n\n")
print(panel_validation_df)
cat("## Model results\n\n")
print(model_results_df)
cat("\n## F-test results\n\n")
print(f_test_results_df)
cat("## Summary\n\n")
print(summary_df)
cat("\n## Selected periods used in the F-test\n\n")
print(selected_periods_df, n = nrow(selected_periods_df))
cat("\n## Perfectly correlated selected bootstrap rows\n\n")
print(perfect_pairs_df, n = nrow(perfect_pairs_df))
cat("\n## Bootstrap support by event time\n\n")
print(bootstrap_support_df, n = nrow(bootstrap_support_df))
cat("\n## Eigenvalues\n\n")
print(eigenvalues_df, n = nrow(eigenvalues_df))
sink()

print(summary_df)
cat("\nWrote:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_model_results.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_panel_validation.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_summary.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_selected_period_filter_results.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_selected_periods.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_bootstrap_support.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_eigenvalues.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "fect_f_test_singularity_perfect_pairs.csv"), "\n", sep = "")
