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

parse_durations <- function(args, default = c(3L, 5L, 7L)) {
  durations_arg <- args[grepl("^--durations=", args)]
  if (length(durations_arg) == 0L) {
    return(default)
  }
  values <- strsplit(sub("^--durations=", "", durations_arg[[1]]), ",")[[1]]
  values <- as.integer(trimws(values))
  if (any(is.na(values)) || any(values <= 0L)) {
    stop("`--durations` must be a comma-separated list of positive integers.",
         call. = FALSE)
  }
  sort(unique(values))
}

fmt <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

pretrend_window_test <- function(fit,
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
    q_requested = q_requested,
    event_time = fit$time[pre_pos],
    count = fit$count[pre_pos],
    att = as.numeric(point_estimates),
    se = se
  ) |>
    dplyr::arrange(event_time)

  list(
    summary = tibble::tibble(
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

fit_status_current_cell <- function(panel, duration_years, specification,
                                    nboots) {
  message(
    "Estimating min", duration_years, " ", specification,
    " with nboots = ", nboots, "."
  )
  timing <- system.time({
    fit <- run_fect_analysis(
      panel,
      method = "ife",
      nboots = nboots,
      fml = abs_distance_china ~ china_top
    )
  })

  model_summary <- summarize_fect_model(
    fit,
    panel,
    fml = abs_distance_china ~ china_top
  ) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      min_duration_years = duration_years,
      specification = specification,
      nboots = nboots,
      elapsed_seconds = as.numeric(timing["elapsed"]),
      .before = att
    )

  pretrend_tests <- lapply(c(3L, 5L, 10L), function(q) {
    pretrend_window_test(fit, q_requested = q)
  })

  pretrend_summary <- dplyr::bind_rows(
    lapply(pretrend_tests, `[[`, "summary")
  ) |>
    dplyr::mutate(
      min_duration_years = duration_years,
      specification = specification,
      .before = q_requested
    )

  pretrend_periods <- dplyr::bind_rows(
    lapply(pretrend_tests, `[[`, "periods")
  ) |>
    dplyr::mutate(
      min_duration_years = duration_years,
      specification = specification,
      .before = q_requested
    )

  list(
    model_summary = model_summary,
    pretrend_summary = pretrend_summary,
    pretrend_periods = pretrend_periods
  )
}

make_duration_panels <- function(china_top_panel, duration_years) {
  period_data <- build_min5_period_data(
    china_top_panel,
    min_duration_years = duration_years,
    min_entry_year = 2000L
  )

  list(
    switching = make_status_current_panel(
      period_data,
      require_balanced = TRUE,
      strict_never_control = FALSE
    ),
    risk_set = make_status_current_panel(
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

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args, default = 1000L)
durations <- parse_durations(args, default = c(3L, 5L, 7L))
output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Loading existing target objects. This script does not run tar_make().")
china_top_panel <- targets::tar_read(china_top_panel)
china_top_absorbing_sample <- targets::tar_read(china_top_absorbing_sample)
main_summary <- targets::tar_read(fect_ife_china_top_summary)

all_results <- list()
all_counts <- list()
all_units <- list()
all_periods <- list()

for (duration_years in durations) {
  panels <- make_duration_panels(china_top_panel, duration_years)

  cell_specs <- list(
    switching = panels$switching,
    risk_set = panels$risk_set,
    clean_single_spell = panels$clean_single_spell
  )

  for (specification in names(cell_specs)) {
    cell <- fit_status_current_cell(
      cell_specs[[specification]],
      duration_years = duration_years,
      specification = specification,
      nboots = nboots
    )
    all_results[[paste(duration_years, specification, sep = "_")]] <- cell
  }

  all_counts[[as.character(duration_years)]] <- dplyr::bind_rows(
    comparison_counts(panels$switching, "switching"),
    comparison_counts(panels$risk_set, "risk_set"),
    comparison_counts(panels$clean_single_spell, "clean_single_spell")
  ) |>
    dplyr::mutate(min_duration_years = duration_years, .before = sample)

  all_units[[as.character(duration_years)]] <- dplyr::bind_rows(
    panel_unit_summary(panels$switching, "switching"),
    panel_unit_summary(panels$risk_set, "risk_set"),
    panel_unit_summary(panels$clean_single_spell, "clean_single_spell")
  ) |>
    dplyr::mutate(min_duration_years = duration_years, .before = sample)

  all_periods[[as.character(duration_years)]] <- panels$period_summary |>
    dplyr::mutate(min_duration_years = duration_years, .before = iso3c)
}

model_results <- dplyr::bind_rows(
  lapply(all_results, `[[`, "model_summary")
) |>
  dplyr::arrange(specification, min_duration_years)

pretrend_summary <- dplyr::bind_rows(
  lapply(all_results, `[[`, "pretrend_summary")
) |>
  dplyr::arrange(specification, min_duration_years, q_requested)

pretrend_periods <- dplyr::bind_rows(
  lapply(all_results, `[[`, "pretrend_periods")
) |>
  dplyr::arrange(specification, min_duration_years, q_requested, event_time)

sample_counts <- dplyr::bind_rows(all_counts) |>
  dplyr::arrange(sample, min_duration_years)

unit_summary <- dplyr::bind_rows(all_units) |>
  dplyr::arrange(sample, min_duration_years, iso3c)

period_summary <- dplyr::bind_rows(all_periods) |>
  dplyr::arrange(min_duration_years, iso3c, eligible_period_id)

benchmark <- tibble::as_tibble(main_summary) |>
  dplyr::mutate(
    min_duration_years = NA_integer_,
    specification = "current_absorbing_targets",
    nboots = 10000L,
    elapsed_seconds = NA_real_,
    .before = att
  )

model_results_with_benchmark <- dplyr::bind_rows(benchmark, model_results)

readr::write_csv(
  model_results_with_benchmark,
  file.path(output_dir,
            "china_top_status_current_duration_robustness_model_results.csv")
)
readr::write_csv(
  sample_counts,
  file.path(output_dir,
            "china_top_status_current_duration_robustness_sample_counts.csv")
)
readr::write_csv(
  pretrend_summary,
  file.path(output_dir,
            "china_top_status_current_duration_robustness_pretrend_summary.csv")
)
readr::write_csv(
  pretrend_periods,
  file.path(output_dir,
            "china_top_status_current_duration_robustness_pretrend_periods.csv")
)
readr::write_csv(
  unit_summary,
  file.path(output_dir,
            "china_top_status_current_duration_robustness_unit_summary.csv")
)
readr::write_csv(
  period_summary,
  file.path(output_dir,
            "china_top_status_current_duration_robustness_period_summary.csv")
)
writeLines(
  capture.output(sessionInfo()),
  con = file.path(
    output_dir,
    "china_top_status_current_duration_robustness_session_info.txt"
  )
)

model_lines <- model_results |>
  dplyr::mutate(
    line = paste0(
      "- min", min_duration_years, " ", specification,
      ": ATT = ", fmt(att),
      ", SE = ", fmt(se),
      ", 95% CI [", fmt(ci_lo), ", ", fmt(ci_hi), "]",
      ", p = ", fmt(p),
      ", r* = ", r_cv,
      ", treated/control = ", n_treated, "/", n_control,
      ", treated country-years = ", n_treated_country_years
    )
  ) |>
  dplyr::pull(line)

pretrend_lines <- pretrend_summary |>
  dplyr::filter(q_requested == 5L) |>
  dplyr::mutate(
    line = paste0(
      "- min", min_duration_years, " ", specification,
      " (-5 to -1): F = ", fmt(f_stat),
      ", p = ", fmt(f_p),
      ", equivalence p = ", fmt(f_equiv_p),
      ", df = ", df1, "/", df2
    )
  ) |>
  dplyr::pull(line)

report_lines <- c(
  "# China top treatment: duration-window robustness",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Bootstrap replications: ", nboots),
  paste0("Duration windows: ", paste(durations, collapse = ", "), " years"),
  "",
  "## Coding Rule",
  "",
  paste(
    "All status-current specifications set treatment equal to 1 only in",
    "country-years where China is the rank-1 export destination and the",
    "observed China-top period lasts at least the specified minimum duration."
  ),
  "",
  "- `switching`: post-exit off-status years remain in the panel as untreated.",
  "- `risk_set`: post-exit off-status years and short/nonqualifying China-top years for treated countries are removed from the comparison risk set.",
  "- `clean_single_spell`: same risk-set restriction, but treated countries must have exactly one observed China-top period and that period must qualify.",
  "",
  "## Model Results",
  "",
  paste0(
    "- Current absorbing target benchmark: ATT = ", fmt(main_summary$att),
    ", SE = ", fmt(main_summary$se),
    ", 95% CI [", fmt(main_summary$ci_lo), ", ",
    fmt(main_summary$ci_hi), "]",
    ", p = ", fmt(main_summary$p),
    ", r* = ", main_summary$r_cv,
    ", treated/control = ", main_summary$n_treated, "/",
    main_summary$n_control,
    "."
  ),
  model_lines,
  "",
  "## Five-Lead Pure Pretrend F-Tests",
  "",
  pretrend_lines,
  "",
  "## Output Files",
  "",
  "- `quality_reports/cross_country_sample/china_top_status_current_duration_robustness_model_results.csv`",
  "- `quality_reports/cross_country_sample/china_top_status_current_duration_robustness_sample_counts.csv`",
  "- `quality_reports/cross_country_sample/china_top_status_current_duration_robustness_pretrend_summary.csv`",
  "- `quality_reports/cross_country_sample/china_top_status_current_duration_robustness_pretrend_periods.csv`",
  "- `quality_reports/cross_country_sample/china_top_status_current_duration_robustness_unit_summary.csv`",
  "- `quality_reports/cross_country_sample/china_top_status_current_duration_robustness_period_summary.csv`"
)

writeLines(
  report_lines,
  con = file.path(
    output_dir,
    "china_top_status_current_duration_robustness_report.md"
  ),
  useBytes = TRUE
)

message(
  "Wrote report to ",
  file.path(output_dir,
            "china_top_status_current_duration_robustness_report.md")
)
