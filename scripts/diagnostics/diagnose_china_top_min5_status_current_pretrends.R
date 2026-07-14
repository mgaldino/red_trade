#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

Sys.setenv(CHINA_TOP_STATUS_CURRENT_SOURCE_ONLY = "1")
source("scripts/diagnostics/reestimate_china_top_min5_status_current_strict.R")
Sys.unsetenv("CHINA_TOP_STATUS_CURRENT_SOURCE_ONLY")

parse_nboots <- function(args, default = 1000L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    return(default)
  }
  value <- as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
  if (is.na(value) || value <= 0L) {
    stop("`--nboots` must be a positive integer.", call. = FALSE)
  }
  value
}

fmt <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

pretrend_window_test <- function(fit,
                                 model,
                                 q_requested,
                                 proportion = 0.3,
                                 f_threshold = 0.6,
                                 tost_threshold = NULL) {
  if (is.null(tost_threshold)) {
    tost_threshold <- if (!is.null(fit$sigma2.fect) &&
                          is.finite(fit$sigma2.fect)) {
      0.36 * sqrt(fit$sigma2.fect)
    } else {
      NA_real_
    }
  }

  max_count <- max(fit$count, na.rm = TRUE)
  candidate_periods <- fit$time[
    fit$time < 0 &
      fit$count >= max_count * proportion &
      !is.na(fit$count)
  ]
  candidate_periods <- sort(unique(candidate_periods), decreasing = TRUE)
  q <- min(q_requested, length(candidate_periods))

  if (q < 1L) {
    return(list(
      summary = tibble::tibble(
        model = model,
        q_requested = q_requested,
        test_status = "no_eligible_preperiods",
        selected_periods = NA_character_,
        q = 0L,
        n_bar = NA_real_,
        df1 = 0L,
        df2 = NA_real_,
        n_valid_boots = 0L,
        cov_rank = NA_integer_,
        f_stat = NA_real_,
        f_p = NA_real_,
        f_equiv_p = NA_real_,
        tost_equiv_p = NA_real_,
        f_threshold = f_threshold,
        tost_threshold = tost_threshold
      ),
      periods = tibble::tibble()
    ))
  }

  selected_periods <- candidate_periods[seq_len(q)]
  pre_pos <- which(fit$time %in% selected_periods)
  n_bar <- max(fit$count[pre_pos], na.rm = TRUE)
  att_boot <- as.matrix(fit$att.boot)
  valid_boot_cols <- which(
    apply(!is.na(att_boot[pre_pos, , drop = FALSE]), 2, all)
  )
  coef_mat <- att_boot[pre_pos, valid_boot_cols, drop = FALSE]
  cov_mat <- safe_bootstrap_cov(coef_mat)
  point_estimates <- as.matrix(fit$est.att[pre_pos, 1, drop = FALSE])

  f_test <- calculate_fect_pretrend_f(
    point_estimates = point_estimates,
    cov_mat = cov_mat,
    n_bar = n_bar,
    f_threshold = f_threshold
  )

  se <- fit$est.att[pre_pos, 2]
  tost_period_p <- mapply(
    fect_tost_p,
    coef = as.numeric(point_estimates),
    se = se,
    MoreArgs = list(threshold = tost_threshold)
  )
  tost_equiv_p <- if (all(is.na(tost_period_p))) {
    NA_real_
  } else {
    max(tost_period_p, na.rm = TRUE)
  }

  periods <- tibble::tibble(
    model = model,
    q_requested = q_requested,
    event_time = fit$time[pre_pos],
    count = fit$count[pre_pos],
    att = as.numeric(point_estimates),
    se = se
  ) |>
    dplyr::arrange(event_time)

  list(
    summary = tibble::tibble(
      model = model,
      q_requested = q_requested,
      test_status = f_test$status,
      selected_periods = paste(sort(selected_periods), collapse = ", "),
      q = q,
      n_bar = n_bar,
      df1 = q,
      df2 = n_bar - q,
      n_valid_boots = length(valid_boot_cols),
      cov_rank = f_test$cov_rank,
      f_stat = f_test$f_stat,
      f_p = f_test$f_p,
      f_equiv_p = f_test$f_equiv_p,
      tost_equiv_p = tost_equiv_p,
      f_threshold = f_threshold,
      tost_threshold = tost_threshold
    ),
    periods = periods
  )
}

fit_with_pretrends <- function(panel, label, nboots) {
  message("Estimating fect IFE for pretrend diagnostics: ", label)
  fit <- run_fect_analysis(
    panel,
    method = "ife",
    nboots = nboots,
    fml = abs_distance_china ~ china_top
  )

  model_summary <- summarize_fect_model(
    fit,
    panel,
    fml = abs_distance_china ~ china_top
  ) |>
    tibble::as_tibble() |>
    dplyr::mutate(model = label, nboots = nboots, .before = att)

  tests <- lapply(c(3L, 5L, 10L), function(q) {
    pretrend_window_test(fit, label, q_requested = q)
  })

  list(
    fit = fit,
    model_summary = model_summary,
    pretrend_summary = dplyr::bind_rows(lapply(tests, `[[`, "summary")),
    pretrend_periods = dplyr::bind_rows(lapply(tests, `[[`, "periods"))
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args, default = 1000L)
output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Loading existing target objects. This script does not run tar_make().")
china_top_panel <- targets::tar_read(china_top_panel)

period_data <- build_min5_period_data(
  china_top_panel,
  min_duration_years = 5L,
  min_entry_year = 2000L
)

status_panel <- make_status_current_panel(
  period_data,
  require_balanced = TRUE,
  strict_never_control = FALSE
)

risk_set_panel <- make_status_current_panel(
  period_data,
  require_balanced = FALSE,
  strict_never_control = TRUE
)

clean_panel <- make_status_current_panel(
  period_data,
  require_balanced = FALSE,
  strict_never_control = TRUE,
  clean_single_spell = TRUE
)

diagnostics <- list(
  fit_with_pretrends(
    status_panel,
    "minimum_5_year_status_current_balanced",
    nboots
  ),
  fit_with_pretrends(
    risk_set_panel,
    "minimum_5_year_status_current_risk_set",
    nboots
  ),
  fit_with_pretrends(
    clean_panel,
    "minimum_5_year_status_current_clean_single_spell",
    nboots
  )
)

model_results <- dplyr::bind_rows(lapply(diagnostics, `[[`, "model_summary"))
pretrend_summary <- dplyr::bind_rows(
  lapply(diagnostics, `[[`, "pretrend_summary")
)
pretrend_periods <- dplyr::bind_rows(
  lapply(diagnostics, `[[`, "pretrend_periods")
)

readr::write_csv(
  model_results,
  file.path(output_dir,
            "china_top_min5_status_current_pretrend_model_results.csv")
)
readr::write_csv(
  pretrend_summary,
  file.path(output_dir,
            "china_top_min5_status_current_pretrend_summary.csv")
)
readr::write_csv(
  pretrend_periods,
  file.path(output_dir,
            "china_top_min5_status_current_pretrend_periods.csv")
)

result_lines <- model_results |>
  dplyr::mutate(
    line = paste0(
      "- ", model,
      ": ATT = ", fmt(att),
      ", SE = ", fmt(se),
      ", p = ", fmt(p),
      ", r* = ", r_cv,
      ", treated/control = ", n_treated, "/", n_control
    )
  ) |>
  dplyr::pull(line)

pretrend_lines <- pretrend_summary |>
  dplyr::mutate(
    line = paste0(
      "- ", model,
      ", q=", q_requested,
      " (", selected_periods, ")",
      ": F = ", fmt(f_stat),
      ", p = ", fmt(f_p),
      ", equivalence p = ", fmt(f_equiv_p),
      ", df = ", df1, "/", df2,
      ", status = ", test_status
    )
  ) |>
  dplyr::pull(line)

report_lines <- c(
  "# China top treatment: status-current pretrend diagnostics",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Bootstrap replications: ", nboots),
  "",
  "## Model Results",
  "",
  result_lines,
  "",
  "## Pure Pre-Treatment F-Tests",
  "",
  paste(
    "The tests use only negative event-time periods. They are reconstructed",
    "from bootstrap draws because the native full-window fect test can be",
    "unavailable when the requested lead window exceeds treated-unit support."
  ),
  "",
  pretrend_lines,
  "",
  "## Output Files",
  "",
  "- `quality_reports/cross_country_sample/china_top_min5_status_current_pretrend_model_results.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_status_current_pretrend_summary.csv`",
  "- `quality_reports/cross_country_sample/china_top_min5_status_current_pretrend_periods.csv`"
)

writeLines(
  report_lines,
  con = file.path(output_dir,
                  "china_top_min5_status_current_pretrend_report.md"),
  useBytes = TRUE
)

message("Wrote report to ",
        file.path(output_dir,
                  "china_top_min5_status_current_pretrend_report.md"))
