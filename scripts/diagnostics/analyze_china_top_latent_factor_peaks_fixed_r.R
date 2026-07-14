#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(targets)
  library(tibble)
  library(tidyr)
})

source("scripts/functions.R")

parse_nboots <- function(args, default = 500L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    return(default)
  }
  as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
}

prepare_estimation_panel <- function(trade_data, unga_data, covariates_panel,
                                     min_year = 1990L,
                                     min_entry_year = 2000L,
                                     fml = abs_distance_china ~ china_top +
                                       log_gdp_pc + free_press) {
  china_top_panel <- build_china_top_partner_panel(
    trade_data = trade_data,
    unga_data = unga_data,
    min_year = min_year,
    min_entry_year = min_entry_year
  )

  china_top_panel %>%
    dplyr::left_join(covariates_panel, by = c("iso3c", "year")) %>%
    prepare_fect_data(fml = fml)
}

run_fixed_r_ife <- function(fect_data, r_fixed, nboots, fml) {
  set.seed(42 + r_fixed)

  fect::fect(
    fml,
    data = as.data.frame(fect_data),
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

summarise_fixed_r_fit <- function(fit, r_fixed, nboots, fect_data, fml) {
  se <- stats::sd(fit$att.avg.boot, na.rm = TRUE)
  p <- 2 * stats::pnorm(-abs(fit$att.avg / se))
  panel_summary <- summarize_china_top_panel(fect_data)

  tibble::tibble(
    specification = paste0("IFE fixed r=", r_fixed),
    r_fixed = r_fixed,
    nboots = nboots,
    att = fit$att.avg,
    se = se,
    ci_lo = fit$att.avg - 1.96 * se,
    ci_hi = fit$att.avg + 1.96 * se,
    p = p,
    n_valid_boot = sum(!is.na(fit$att.avg.boot)),
    n_obs = nrow(fect_data),
    n_countries = dplyr::n_distinct(fect_data$iso3c),
    n_treated = panel_summary$n_treated,
    n_control = panel_summary$n_control,
    n_entries = panel_summary$n_entries,
    n_exits = panel_summary$n_exits,
    panel_min = panel_summary$panel_min,
    panel_max = panel_summary$panel_max
  )
}

extract_factors <- function(fit, r_fixed) {
  if (is.null(fit$factor) || r_fixed == 0L) {
    return(tibble::tibble())
  }

  factor_mat <- as.data.frame(fit$factor)
  names(factor_mat) <- paste0("factor_", seq_len(ncol(factor_mat)))

  factor_mat %>%
    dplyr::mutate(year = fit$rawtime) %>%
    tidyr::pivot_longer(
      cols = dplyr::starts_with("factor_"),
      names_to = "factor",
      values_to = "value"
    ) %>%
    dplyr::group_by(factor) %>%
    dplyr::mutate(
      value_z = as.numeric(scale(value)),
      abs_value_z = abs(value_z)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      specification = paste0("IFE fixed r=", r_fixed),
      r_fixed = r_fixed,
      .before = year
    ) %>%
    dplyr::select(specification, r_fixed, year, factor, value, value_z, abs_value_z)
}

find_factor_peaks <- function(factor_df, top_n = 5L) {
  if (nrow(factor_df) == 0L) {
    return(list(summary = tibble::tibble(), top_abs = tibble::tibble()))
  }

  peak_summary <- factor_df %>%
    dplyr::group_by(specification, r_fixed, factor) %>%
    dplyr::summarise(
      positive_peak_year = year[which.max(value_z)],
      positive_peak_z = max(value_z, na.rm = TRUE),
      negative_peak_year = year[which.min(value_z)],
      negative_peak_z = min(value_z, na.rm = TRUE),
      absolute_peak_year = year[which.max(abs_value_z)],
      absolute_peak_z_signed = value_z[which.max(abs_value_z)],
      absolute_peak_abs_z = max(abs_value_z, na.rm = TRUE),
      .groups = "drop"
    )

  top_abs <- factor_df %>%
    dplyr::group_by(specification, r_fixed, factor) %>%
    dplyr::slice_max(abs_value_z, n = top_n, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(specification, factor, dplyr::desc(abs_value_z), year)

  list(summary = peak_summary, top_abs = top_abs)
}

make_treatment_timing <- function(fect_data) {
  entry_country_years <- fect_data %>%
    dplyr::arrange(iso3c, year) %>%
    dplyr::group_by(iso3c) %>%
    dplyr::mutate(
      china_top_lag = dplyr::lag(china_top),
      treatment_entry = china_top == 1L &
        !is.na(china_top_lag) &
        china_top_lag == 0L
    ) %>%
    dplyr::ungroup() %>%
    dplyr::filter(treatment_entry) %>%
    dplyr::select(iso3c, country_name, entry_year = year)

  entry_counts <- entry_country_years %>%
    dplyr::count(entry_year, name = "n_entries") %>%
    dplyr::arrange(entry_year)

  treated_counts <- fect_data %>%
    dplyr::filter(china_top == 1L) %>%
    dplyr::count(year, name = "n_treated_country_years") %>%
    dplyr::arrange(year)

  list(
    entry_country_years = entry_country_years,
    entry_counts = entry_counts,
    treated_counts = treated_counts
  )
}

make_peak_treatment_overlap <- function(peak_summary, treatment_timing,
                                        window = 1L) {
  if (nrow(peak_summary) == 0L) {
    return(tibble::tibble())
  }

  peak_years <- peak_summary %>%
    dplyr::select(specification, r_fixed, factor, positive_peak_year,
                  negative_peak_year, absolute_peak_year) %>%
    tidyr::pivot_longer(
      cols = dplyr::ends_with("_peak_year"),
      names_to = "peak_type",
      values_to = "peak_year"
    ) %>%
    dplyr::mutate(
      window_start = peak_year - window,
      window_end = peak_year + window
    )

  peak_years %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      entries_exact = sum(
        treatment_timing$entry_country_years$entry_year == peak_year,
        na.rm = TRUE
      ),
      entries_window = sum(
        treatment_timing$entry_country_years$entry_year >= window_start &
          treatment_timing$entry_country_years$entry_year <= window_end,
        na.rm = TRUE
      ),
      countries_exact = paste(
        treatment_timing$entry_country_years$iso3c[
          treatment_timing$entry_country_years$entry_year == peak_year
        ],
        collapse = ";"
      ),
      countries_window = paste(
        treatment_timing$entry_country_years$iso3c[
          treatment_timing$entry_country_years$entry_year >= window_start &
            treatment_timing$entry_country_years$entry_year <= window_end
        ],
        collapse = ";"
      )
    ) %>%
    dplyr::ungroup()
}

plot_factors <- function(factor_df, output_path) {
  if (nrow(factor_df) == 0L) {
    return(invisible(NULL))
  }

  p <- ggplot2::ggplot(
    factor_df,
    ggplot2::aes(x = year, y = value_z)
  ) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.25, colour = "grey70") +
    ggplot2::geom_line(linewidth = 0.8, colour = "#1F4E79") +
    ggplot2::geom_point(size = 1.4, colour = "#1F4E79") +
    ggplot2::facet_grid(specification ~ factor, scales = "free_y") +
    ggplot2::scale_x_continuous(breaks = seq(1990, 2020, by = 5)) +
    ggplot2::labs(
      x = "Year",
      y = "Estimated latent factor (standardized)",
      title = "Latent factors from fixed-r fect IFE models",
      subtitle = "Scale and sign are normalization-dependent; timing of peaks is the relevant diagnostic."
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold")
    )

  ggplot2::ggsave(output_path, p, width = 8.5, height = 5.5, dpi = 300)
}

write_report <- function(output_dir, model_results, peak_summary,
                         peak_overlap, entry_counts, nboots) {
  model_lines <- model_results %>%
    dplyr::mutate(
      line = paste0(
        "- r=", r_fixed,
        ": ATT = ", sprintf("%.3f", att),
        ", SE = ", sprintf("%.3f", se),
        ", 95% CI [", sprintf("%.3f", ci_lo), ", ",
        sprintf("%.3f", ci_hi), "]",
        ", p = ", sprintf("%.3f", p)
      )
    ) %>%
    dplyr::pull(line)

  peak_lines <- peak_summary %>%
    dplyr::mutate(
      line = paste0(
        "- ", specification, ", ", factor,
        ": positive peak ", positive_peak_year,
        " (z=", sprintf("%.2f", positive_peak_z), "); negative peak ",
        negative_peak_year, " (z=", sprintf("%.2f", negative_peak_z),
        "); max |z| ", absolute_peak_year,
        " (signed z=", sprintf("%.2f", absolute_peak_z_signed), ")"
      )
    ) %>%
    dplyr::pull(line)

  overlap_lines <- peak_overlap %>%
    dplyr::mutate(
      line = paste0(
        "- ", specification, ", ", factor, ", ", peak_type,
        " = ", peak_year, ": entries exact/window +/-1 = ",
        entries_exact, "/", entries_window,
        "; countries window = ", countries_window
      )
    ) %>%
    dplyr::pull(line)

  entry_lines <- entry_counts %>%
    dplyr::arrange(dplyr::desc(n_entries), entry_year) %>%
    dplyr::slice_head(n = 12L) %>%
    dplyr::mutate(
      line = paste0("- ", entry_year, ": ", n_entries, " treatment entries")
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# Fixed-r latent factor peak diagnostic",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("Bootstrap replications: ", nboots),
    "",
    "## Model Results",
    "",
    model_lines,
    "",
    "## Factor Peaks",
    "",
    peak_lines,
    "",
    "## Peak-Treatment Overlap",
    "",
    overlap_lines,
    "",
    "## Treatment Entry Clusters",
    "",
    entry_lines,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_fixed_r_model_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_fixed_r_latent_factors.csv`",
    "- `quality_reports/cross_country_sample/china_top_fixed_r_factor_peaks.csv`",
    "- `quality_reports/cross_country_sample/china_top_fixed_r_factor_top_abs_years.csv`",
    "- `quality_reports/cross_country_sample/china_top_fixed_r_peak_treatment_overlap.csv`",
    "- `quality_reports/cross_country_sample/china_top_treatment_entries_by_year.csv`",
    "- `quality_reports/cross_country_sample/china_top_fixed_r_latent_factors.png`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_fixed_r_latent_factor_report.md"),
    useBytes = TRUE
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args)

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

fml <- abs_distance_china ~ china_top + log_gdp_pc + free_press

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Preparing corrected complete-case fect panel...")
fect_data <- prepare_estimation_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  covariates_panel = covariates_panel,
  fml = fml
)

treatment_timing <- make_treatment_timing(fect_data)

r_values <- c(0L, 1L, 2L)
fits <- list()
model_results <- list()
factor_data <- list()

for (r_fixed in r_values) {
  message("Estimating fixed-r IFE with r = ", r_fixed)
  fit <- run_fixed_r_ife(
    fect_data = fect_data,
    r_fixed = r_fixed,
    nboots = nboots,
    fml = fml
  )
  fits[[as.character(r_fixed)]] <- fit
  model_results[[as.character(r_fixed)]] <- summarise_fixed_r_fit(
    fit = fit,
    r_fixed = r_fixed,
    nboots = nboots,
    fect_data = fect_data,
    fml = fml
  )
  factor_data[[as.character(r_fixed)]] <- extract_factors(fit, r_fixed)
}

model_results <- dplyr::bind_rows(model_results)
factor_df <- dplyr::bind_rows(factor_data)
peaks <- find_factor_peaks(factor_df, top_n = 5L)
peak_overlap <- make_peak_treatment_overlap(
  peaks$summary,
  treatment_timing = treatment_timing,
  window = 1L
)

readr::write_csv(
  model_results,
  file.path(output_dir, "china_top_fixed_r_model_results.csv")
)
readr::write_csv(
  factor_df,
  file.path(output_dir, "china_top_fixed_r_latent_factors.csv")
)
readr::write_csv(
  peaks$summary,
  file.path(output_dir, "china_top_fixed_r_factor_peaks.csv")
)
readr::write_csv(
  peaks$top_abs,
  file.path(output_dir, "china_top_fixed_r_factor_top_abs_years.csv")
)
readr::write_csv(
  peak_overlap,
  file.path(output_dir, "china_top_fixed_r_peak_treatment_overlap.csv")
)
readr::write_csv(
  treatment_timing$entry_counts,
  file.path(output_dir, "china_top_treatment_entries_by_year.csv")
)
readr::write_csv(
  treatment_timing$entry_country_years,
  file.path(output_dir, "china_top_treatment_entry_country_years.csv")
)
readr::write_csv(
  treatment_timing$treated_counts,
  file.path(output_dir, "china_top_treated_country_years_by_year.csv")
)

plot_factors(
  factor_df,
  file.path(output_dir, "china_top_fixed_r_latent_factors.png")
)

write_report(
  output_dir = output_dir,
  model_results = model_results,
  peak_summary = peaks$summary,
  peak_overlap = peak_overlap,
  entry_counts = treatment_timing$entry_counts,
  nboots = nboots
)

print(model_results)
cat("\nFactor peaks:\n")
print(peaks$summary)
cat("\nReport written to: ",
    file.path(output_dir, "china_top_fixed_r_latent_factor_report.md"),
    "\n",
    sep = "")
