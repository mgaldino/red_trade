#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

parse_nboots <- function(args, default = 500L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    return(default)
  }
  as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
}

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

safe_cov <- function(coef_mat) {
  if (ncol(coef_mat) < 2L) {
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
                                  pre_periods = NULL, tol = 1e-10,
                                  f_threshold = 0.6) {
  if (is.null(pre_periods)) {
    max_count <- max(fit$count, na.rm = TRUE)
    pre_periods <- fit$time[
      fit$count >= max_count * proportion & fit$time <= 0
    ]
  }

  n_all_nonpositive_periods <- sum(fit$time <= 0, na.rm = TRUE)
  pre_pos <- which(fit$time %in% pre_periods)

  dropped_first_selected_period <- FALSE
  if (length(pre_pos) == n_all_nonpositive_periods) {
    pre_pos <- pre_pos[-1]
    dropped_first_selected_period <- TRUE
  }

  n_bar <- max(fit$count[fit$time %in% pre_periods], na.rm = TRUE)

  att_boot <- as.matrix(fit$att.boot)
  valid_boot_cols_global <- which(apply(!is.na(att_boot), 2, all))
  valid_boot_cols_selected <- which(
    apply(!is.na(att_boot[pre_pos, , drop = FALSE]), 2, all)
  )

  coef_mat_global <- att_boot[pre_pos, valid_boot_cols_global, drop = FALSE]
  coef_mat_selected <- att_boot[
    pre_pos, valid_boot_cols_selected, drop = FALSE
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

  selected_periods <- tibble::tibble(
    model = label,
    event_time = fit$time[pre_pos],
    count = fit$count[pre_pos],
    att = as.numeric(point_estimates),
    se_reported = fit$est.att[pre_pos, 2],
    selected_only_nonmissing_boot_cols = length(valid_boot_cols_selected)
  )

  summary <- tibble::tibble(
    model = label,
    selected_periods = paste(fit$time[pre_pos], collapse = ", "),
    n_selected_periods = length(pre_pos),
    n_all_nonpositive_periods = n_all_nonpositive_periods,
    dropped_first_selected_period = dropped_first_selected_period,
    n_bar = n_bar,
    df1 = length(pre_pos),
    df2 = n_bar - length(pre_pos),
    valid_boot_cols_global = length(valid_boot_cols_global),
    valid_boot_cols_selected_only = length(valid_boot_cols_selected),
    cov_rank_global = safe_rank(cov_global, tol = tol),
    cov_rank_selected_only = safe_rank(cov_selected, tol = tol),
    global_f_stat = global_f_test$stat,
    global_f_p = global_f_test$p,
    global_f_error = global_f_test$error,
    selected_only_f_stat = selected_f_test$stat,
    selected_only_f_p = selected_f_test$p,
    selected_only_f_equiv_p = selected_f_test$equiv_p,
    selected_only_f_error = selected_f_test$error,
    f_threshold = f_threshold
  )

  list(summary = summary, selected_periods = selected_periods)
}

as_fect_panel <- function(cs_data) {
  cs_data %>%
    dplyr::mutate(
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      ),
      country_id = as.integer(as.factor(iso3c))
    ) %>%
    dplyr::arrange(country_id, year)
}

fit_and_diagnose <- function(panel, label, fml, nboots) {
  message("Estimating fect IFE: ", label)
  fit <- run_fect_analysis(
    panel,
    method = "ife",
    nboots = nboots,
    fml = fml
  )

  att_summary <- fect_att_summary(fit)
  model_summary <- summarize_fect_model(fit, panel, fml = fml) %>%
    tibble::as_tibble() %>%
    dplyr::mutate(
      model = label,
      estimator = "fect_ife",
      nboots = nboots,
      .before = att
    )

  f_test <- inspect_fect_diagtest(fit, label)

  list(
    fit = fit,
    model_summary = model_summary,
    f_test_summary = f_test$summary %>%
      dplyr::mutate(
        att = att_summary$att,
        se = att_summary$se,
        p = att_summary$p,
        r_cv = att_summary$r_cv,
        .after = model
      ),
    selected_periods = f_test$selected_periods
  )
}

write_report <- function(output_dir, model_results, f_test_results,
                         selected_periods, nboots) {
  result_lines <- model_results %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", p = ", format_num(p),
        ", r* = ", format_num(r_cv, 0L),
        ", countries = ", n_countries,
        ", treated = ", n_treated,
        ", controls = ", n_control
      )
    ) %>%
    dplyr::pull(line)

  f_lines <- f_test_results %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ": selected periods = ", selected_periods,
        "; df = ", df1, ", ", df2,
        "; selected-only F = ", format_num(selected_only_f_stat),
        "; p = ", format_num(selected_only_f_p),
        "; equivalence p = ", format_num(selected_only_f_equiv_p),
        ifelse(
          selected_only_f_error == "",
          "",
          paste0("; error = ", selected_only_f_error)
        )
      )
    ) %>%
    dplyr::pull(line)

  period_lines <- selected_periods %>%
    dplyr::mutate(
      line = paste0(
        "- ", model,
        ", event time ", event_time,
        ": count = ", count,
        ", ATT = ", format_num(att),
        ", SE = ", format_num(se_reported)
      )
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# fect IFE F-test diagnostics on the absorbing C&S sample",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("Bootstrap replications: ", nboots),
    "",
    "This diagnostic applies the F-test reconstruction used in the existing fect singularity scripts. The IFE estimates are unchanged; only the diagnostic covariance matrix is recomputed using bootstrap draws that are nonmissing for the selected diagnostic periods.",
    "",
    "## fect IFE estimates",
    "",
    result_lines,
    "",
    "## Reconstructed F-test",
    "",
    f_lines,
    "",
    "## Selected diagnostic periods",
    "",
    period_lines,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_sample_fect_f_test_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_sample_fect_f_test_selected_periods.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_sample_fect_f_test_model_results.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_absorbing_cs_sample_fect_f_test_report.md"),
    useBytes = TRUE
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args)

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_year <- 1990L
min_entry_year <- 2000L
covariates <- c("log_gdp_pc", "free_press")

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Building corrected broad China-top partner panel...")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = min_entry_year
)

panel_cov <- china_top_panel %>%
  dplyr::left_join(covariates_panel, by = c("iso3c", "year"))

message("Preparing absorbing C&S samples...")
cs_data <- prepare_absorbing_china_top_did_data(
  china_top_panel,
  min_entry_year = min_entry_year
)

cs_cov_data <- prepare_absorbing_china_top_did_data(
  panel_cov,
  covariate_cols = covariates,
  min_entry_year = min_entry_year
)

diagnostics <- list(
  fit_and_diagnose(
    panel = as_fect_panel(cs_data),
    label = "No covariates",
    fml = abs_distance_china ~ china_top,
    nboots = nboots
  ),
  fit_and_diagnose(
    panel = as_fect_panel(cs_cov_data),
    label = "log_gdp_pc + free_press",
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press,
    nboots = nboots
  )
)

model_results <- dplyr::bind_rows(lapply(diagnostics, `[[`, "model_summary"))
f_test_results <- dplyr::bind_rows(lapply(diagnostics, `[[`, "f_test_summary"))
selected_periods <- dplyr::bind_rows(lapply(diagnostics, `[[`, "selected_periods"))

readr::write_csv(
  model_results,
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_f_test_model_results.csv")
)
readr::write_csv(
  f_test_results,
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_f_test_results.csv")
)
readr::write_csv(
  selected_periods,
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_f_test_selected_periods.csv")
)

write_report(
  output_dir = output_dir,
  model_results = model_results,
  f_test_results = f_test_results,
  selected_periods = selected_periods,
  nboots = nboots
)

print(f_test_results %>%
        dplyr::select(
          model,
          att,
          se,
          p,
          r_cv,
          selected_periods,
          df1,
          df2,
          selected_only_f_stat,
          selected_only_f_p,
          selected_only_f_equiv_p,
          selected_only_f_error
        ))

message(
  "Wrote report to ",
  file.path(output_dir, "china_top_absorbing_cs_sample_fect_f_test_report.md")
)
