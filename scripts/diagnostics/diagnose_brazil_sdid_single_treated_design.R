#!/usr/bin/env Rscript

# Complete diagnostics for the Brazil SDiD design with one treated unit.
# This script reads existing targets and recomputes new diagnostics outside
# the targets pipeline. It does not edit _targets.R, _targets/, _targets.yaml,
# raw data, or manuscript files, and it does not call targets::tar_make().

options(scipen = 999)

suppressPackageStartupMessages({
  library(countrycode)
  library(dplyr)
  library(ggplot2)
  library(janitor)
  library(knitr)
  library(readr)
  library(stringr)
  library(synthdid)
  library(targets)
  library(tibble)
  library(tidyr)
})

source("scripts/diagnostics/sdid_diagnostics_helpers.R", encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
skip_window_placebos <- "--skip-window-placebos" %in% args

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
script_path <- "scripts/diagnostics/diagnose_brazil_sdid_single_treated_design.R"
helper_path <- "scripts/diagnostics/sdid_diagnostics_helpers.R"
target_store <- "_targets"

data_dir <- file.path("data", "processed", "diagnostics", "sdid_single_treated")
figure_dir <- file.path("figures", "sdid_single_treated")
table_dir <- file.path("tables", "sdid_single_treated")
report_dir <- file.path("quality_reports", "sdid_single_treated")

for (dir in c(data_dir, figure_dir, table_dir, report_dir)) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
}

path_data <- function(filename) file.path(data_dir, filename)
path_figure <- function(filename) file.path(figure_dir, filename)
path_table <- function(filename) file.path(table_dir, filename)
path_report <- function(filename) file.path(report_dir, filename)

object_audit_path <- path_data("sdid_existing_target_object_audit.csv")
design_contract_path <- path_data("table_a1_sdid_design_contract.csv")
unit_weights_path <- path_data("table_a2_sdid_unit_weights_complete.csv")
time_weights_path <- path_data("table_a3_sdid_time_weights.csv")
series_path <- path_data("table_a4_sdid_brazil_synthetic_series.csv")
prefit_summary_path <- path_data("table_a5_sdid_pre_treatment_fit_summary.csv")
balance_path <- path_data("table_a6_sdid_pre_treatment_balance.csv")
placebo_distribution_path <- path_data("table_a7_sdid_placebo_distribution.csv")
placebo_inference_path <- path_data("table_a8_sdid_placebo_rank_inference.csv")
donor_sensitivity_path <- path_data("table_a9_sdid_influential_donor_sensitivity.csv")
window_sensitivity_path <- path_data("table_a10_sdid_window_sensitivity.csv")
window_placebos_path <- path_data("table_a11_sdid_window_placebos_long.csv")
china_exposure_path <- path_data("table_a12_sdid_donor_china_exposure.csv")
china_exposure_summary_path <- path_data("table_a13_sdid_high_weight_donor_china_exposure_summary.csv")
validation_path <- path_data("sdid_diagnostic_validation_checks.csv")
caption_path <- path_data("sdid_diagnostic_table_figure_captions.csv")
manifest_path <- path_data("sdid_diagnostic_output_manifest.csv")
session_info_path <- path_report("sdid_single_treated_session_info.txt")
paper_text_path <- path_report("sdid_diagnostics_paper_text_block.md")
report_path <- path_report(paste0(run_date, "_sdid_single_treated_diagnostics_report.md"))
report_pdf_path <- path_report(paste0(run_date, "_sdid_single_treated_diagnostics_report.pdf"))
pdf_render_log_path <- path_report("sdid_single_treated_pdf_render_log.txt")

fig_prefit_png <- path_figure("figure_a1_sdid_pre_treatment_fit.png")
fig_prefit_pdf <- path_figure("figure_a1_sdid_pre_treatment_fit.pdf")
fig_placebo_png <- path_figure("figure_a2_sdid_placebo_distribution.png")
fig_placebo_pdf <- path_figure("figure_a2_sdid_placebo_distribution.pdf")
fig_donor_sensitivity_png <- path_figure("figure_a3_sdid_influential_donor_sensitivity.png")
fig_donor_sensitivity_pdf <- path_figure("figure_a3_sdid_influential_donor_sensitivity.pdf")
fig_window_png <- path_figure("figure_a4_sdid_window_sensitivity.png")
fig_window_pdf <- path_figure("figure_a4_sdid_window_sensitivity.pdf")
fig_china_exposure_png <- path_figure("figure_a5_sdid_high_weight_donor_china_exposure.png")
fig_china_exposure_pdf <- path_figure("figure_a5_sdid_high_weight_donor_china_exposure.pdf")

message("Reading existing targets without running tar_make()...")

target_names <- c(
  "synth_data",
  "synth_data_extended",
  "synth_fit",
  "se_synth",
  "synth_fit_latam",
  "se_synth_latam",
  "rmspe_diagnostics",
  "permutation_results",
  "sensitivity_results",
  "donor_table",
  "trade_data_ranked",
  "trade_data_cleaned",
  "unga_data"
)

objects <- stats::setNames(lapply(target_names, safe_tar_read, store = target_store), target_names)
object_audit <- dplyr::bind_rows(Map(object_audit_row, names(objects), objects))
readr::write_csv(object_audit, object_audit_path, na = "")

required_targets <- c(
  "synth_data",
  "synth_fit",
  "se_synth",
  "permutation_results",
  "trade_data_ranked",
  "trade_data_cleaned",
  "unga_data"
)
missing_required <- object_audit |>
  dplyr::filter(object %in% required_targets, status != "read")

if (nrow(missing_required) > 0L) {
  stop(
    "Cannot continue because required targets could not be read: ",
    paste(missing_required$object, collapse = ", ")
  )
}

synth_data <- objects$synth_data
synth_data_extended <- if (is_tar_error(objects$synth_data_extended)) NULL else objects$synth_data_extended
synth_fit <- objects$synth_fit
se_synth <- as.numeric(objects$se_synth)
permutation_results <- objects$permutation_results
trade_data_ranked <- objects$trade_data_ranked
trade_data_cleaned <- objects$trade_data_cleaned
unga_data <- objects$unga_data

setup <- attr(synth_fit, "setup")
baseline_series <- extract_sdid_series(synth_fit)
baseline_fit_summary <- summarise_sdid_fit(synth_fit, "Baseline: 1997-2015")
baseline_estimate <- baseline_fit_summary$estimate[[1]]
baseline_pre_mean <- mean(
  synth_data$abs_distance_china[synth_data$iso3c == "BRA" & synth_data$year <= 2008],
  na.rm = TRUE
)
baseline_percent_change <- 100 * baseline_estimate / baseline_pre_mean

message("Writing complete SDiD weight structure and pre-treatment fit diagnostics...")

unit_weights <- extract_unit_weights(synth_fit, synth_data)
time_weights <- extract_time_weights(synth_fit)
balance_table <- build_balance_table(synth_data, unit_weights, pre_years = 1997:2008)

message("Recomputing baseline placebo-in-space distribution with intercept-adjusted RMSPE diagnostics...")
baseline_placebo_results <- run_placebos_for_window(
  data = synth_data,
  year_start = 1997L,
  year_end = 2015L,
  treatment_start = 2009L,
  spec_label = "1997-2015 baseline"
) |>
  dplyr::mutate(
    ratio = rmspe_ratio,
    p_value = NA_real_
  )

placebo <- build_placebo_summary(baseline_placebo_results)
placebo_distribution <- placebo$placebo_results |>
  dplyr::mutate(
    country_name = countrycode::countrycode(iso3c, "iso3c", "country.name"),
    region = countrycode::countrycode(iso3c, "iso3c", "region")
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    region,
    role,
    estimate,
    rmspe_pre,
    rmspe_post,
    ratio,
    estimate_rank_negative,
    estimate_rank_abs,
    rmspe_ratio_rank_high,
    p_value
  )
placebo_inference <- placebo$inference

design_contract <- tibble::tibble(
  element = c(
    "Treated unit",
    "Treatment timing",
    "Treatment definition",
    "Outcome",
    "Estimator",
    "Estimand",
    "Baseline window used by the fitted target",
    "Pre-treatment years",
    "Post-treatment years",
    "Donor pool in fitted target",
    "Covariate adjustment",
    "Baseline ATT",
    "Placebo SE from target",
    "Brazil pre-treatment mean outcome",
    "ATT as percent of Brazil pre-treatment mean"
  ),
  value = c(
    "Brazil (BRA)",
    "Treatment turns on in 2009",
    "Indicator equals 1 from 2009 onward, when China became Brazil's largest export destination.",
    "Absolute annual UNGA ideal-point distance to China",
    "Synthetic difference-in-differences with covariate adjustment",
    "Average post-2009 ATT for Brazil relative to a synthetic counterfactual",
    paste0(min(as.integer(colnames(setup$Y))), "-", max(as.integer(colnames(setup$Y)))),
    paste(as.integer(colnames(setup$Y)[seq_len(setup$T0)]), collapse = ", "),
    paste(as.integer(colnames(setup$Y)[(setup$T0 + 1):ncol(setup$Y)]), collapse = ", "),
    paste0(setup$N0, " donor countries; Brazil excluded from donor pool"),
    paste(required_sdid_covariates(synth_data), collapse = ", "),
    fmt_num(baseline_estimate, 4),
    fmt_num(se_synth, 4),
    fmt_num(baseline_pre_mean, 4),
    fmt_pct(baseline_percent_change, 1)
  )
)

prefit_summary <- baseline_fit_summary |>
  dplyr::mutate(
    placebo_se = se_synth,
    brazil_pre_treatment_mean = baseline_pre_mean,
    estimate_as_percent_of_pre_mean = baseline_percent_change,
    source = "synth_fit, se_synth, and direct extraction from synthdid object"
  )

readr::write_csv(design_contract, design_contract_path, na = "")
readr::write_csv(unit_weights, unit_weights_path, na = "")
readr::write_csv(time_weights, time_weights_path, na = "")
readr::write_csv(baseline_series, series_path, na = "")
readr::write_csv(prefit_summary, prefit_summary_path, na = "")
readr::write_csv(balance_table, balance_path, na = "")
readr::write_csv(placebo_distribution, placebo_distribution_path, na = "")
readr::write_csv(placebo_inference, placebo_inference_path, na = "")

message("Running donor influence sensitivity fits...")

top_donors <- unit_weights |>
  dplyr::filter(high_weight_top10) |>
  dplyr::arrange(weight_rank)

block_specs <- list(
  "Drop top 5 donors by weight" = top_donors$iso3c[seq_len(min(5L, nrow(top_donors)))],
  "Drop top 10 donors by weight" = top_donors$iso3c,
  "Drop donors with weight >= 2x uniform" = unit_weights$iso3c[unit_weights$high_weight_2x_uniform],
  "Drop high-weight Latin America/Caribbean donors" =
    unit_weights$iso3c[unit_weights$high_weight_donor & unit_weights$latin_america]
)

jackknife_specs <- stats::setNames(
  as.list(top_donors$iso3c),
  paste0("Drop ", top_donors$iso3c, " (rank ", top_donors$weight_rank, ")")
)
jackknife_specs <- lapply(jackknife_specs, function(x) x)

donor_specs <- c(
  list("Baseline: no donor removed" = character()),
  jackknife_specs,
  block_specs
)

donor_sensitivity <- lapply(names(donor_specs), function(spec_name) {
  excluded <- donor_specs[[spec_name]]
  fit <- if (length(excluded) == 0L) {
    synth_fit
  } else {
    fit_sdid_safely(
      data = synth_data,
      year_start = 1997L,
      year_end = 2015L,
      treated_iso3c = "BRA",
      treatment_start = 2009L,
      exclude_iso3c = excluded
    )
  }

  summarise_sdid_fit(fit, spec_name) |>
    dplyr::mutate(
      removed_donors = paste(excluded, collapse = ";"),
      n_removed_donors = length(excluded),
      placebo_se = dplyr::if_else(n_removed_donors == 0L, se_synth, NA_real_),
      inference_available = dplyr::if_else(
        n_removed_donors == 0L,
        "Baseline placebo SE from existing target se_synth.",
        "Point estimate only; placebo SE/rank not recomputed for donor-removal sensitivity."
      )
    )
}) |>
  dplyr::bind_rows() |>
  dplyr::mutate(
    estimate_change_vs_baseline = estimate - baseline_estimate,
    percent_change_vs_baseline = 100 * estimate_change_vs_baseline / abs(baseline_estimate),
    substantive_stability = dplyr::case_when(
      is.na(estimate) ~ "Not estimated",
      sign(estimate) != sign(baseline_estimate) ~ "Sign changes",
      abs(percent_change_vs_baseline) <= 10 ~ "Stable within 10%",
      abs(percent_change_vs_baseline) <= 25 ~ "Moderate movement",
      TRUE ~ "Large movement"
    )
  )

readr::write_csv(donor_sensitivity, donor_sensitivity_path, na = "")

message("Running window sensitivity fits...")

window_specs <- tibble::tribble(
  ~specification, ~year_start, ~year_end, ~data_source, ~notes,
  "1997-2013", 1997L, 2013L, "synth_data", "Shorter post-treatment window.",
  "1997-2014", 1997L, 2014L, "synth_data", "Shorter post-treatment window.",
  "1997-2015 baseline", 1997L, 2015L, "synth_data", "Baseline fitted target window.",
  "1997-2016", 1997L, 2016L, "synth_data", "One additional post-treatment year available in synth_data.",
  "1998-2015", 1998L, 2015L, "synth_data", "Drops earliest pre-treatment year.",
  "1999-2015", 1999L, 2015L, "synth_data", "Drops two earliest pre-treatment years.",
  "2000-2015", 2000L, 2015L, "synth_data", "Drops three earliest pre-treatment years."
)

window_sensitivity_base <- lapply(seq_len(nrow(window_specs)), function(i) {
  spec <- window_specs[i, ]
  data_for_spec <- if (spec$data_source == "synth_data_extended" && !is.null(synth_data_extended)) {
    synth_data_extended
  } else {
    synth_data
  }

  fit <- if (spec$specification == "1997-2015 baseline") {
    synth_fit
  } else {
    fit_sdid_safely(
      data = data_for_spec,
      year_start = spec$year_start,
      year_end = spec$year_end,
      treated_iso3c = "BRA",
      treatment_start = 2009L
    )
  }

  summarise_sdid_fit(fit, spec$specification) |>
    dplyr::mutate(
      year_start = spec$year_start,
      year_end = spec$year_end,
      data_source = spec$data_source,
      notes = spec$notes
    )
}) |>
  dplyr::bind_rows() |>
  dplyr::mutate(
    estimate_change_vs_baseline = estimate - baseline_estimate,
    percent_change_vs_baseline = 100 * estimate_change_vs_baseline / abs(baseline_estimate),
    stability = dplyr::case_when(
      is.na(estimate) ~ "Not estimated",
      sign(estimate) != sign(baseline_estimate) ~ "Sign changes",
      abs(percent_change_vs_baseline) <= 10 ~ "Stable within 10%",
      abs(percent_change_vs_baseline) <= 25 ~ "Moderate movement",
      TRUE ~ "Large movement"
    )
  )

if (skip_window_placebos) {
  message("Skipping expensive non-baseline window placebos because --skip-window-placebos was supplied.")
  window_placebos <- tibble::tibble()
  window_placebo_ranks <- tibble::tibble(
    specification = window_sensitivity_base$specification,
    brazil_estimate_rank_negative = NA_integer_,
    placebo_denominator = NA_integer_,
    placebo_p_one_sided_negative = NA_real_,
    placebo_p_two_sided_abs = NA_real_,
    brazil_rmspe_ratio_rank_high = NA_integer_
  )
  baseline_rank <- placebo_inference |>
    dplyr::filter(estimand == "One-sided negative effect") |>
    dplyr::transmute(
      specification = "1997-2015 baseline",
      brazil_estimate_rank_negative = rank,
      placebo_denominator = denominator,
      placebo_p_one_sided_negative = rank_based_p_value
    )
  if (nrow(baseline_rank) == 1L) {
    window_placebo_ranks <- window_placebo_ranks |>
      dplyr::rows_update(baseline_rank, by = "specification")
  }
} else {
  message("Running placebo-in-space ranks for non-baseline windows. This is the slow step.")
  placebo_window_results <- list()
  for (i in seq_len(nrow(window_specs))) {
    spec <- window_specs[i, ]
    if (spec$specification == "1997-2015 baseline") {
      placebo_window_results[[spec$specification]] <- baseline_placebo_results
    } else {
      message("  Placebo window: ", spec$specification)
      data_for_spec <- if (spec$data_source == "synth_data_extended" && !is.null(synth_data_extended)) {
        synth_data_extended
      } else {
        synth_data
      }
      placebo_window_results[[spec$specification]] <- run_placebos_for_window(
        data = data_for_spec,
        year_start = spec$year_start,
        year_end = spec$year_end,
        treatment_start = 2009L,
        spec_label = spec$specification
      )
    }
  }
  window_placebos <- dplyr::bind_rows(placebo_window_results)
  window_placebo_ranks <- summarise_window_placebo_rank(window_placebos)
}

readr::write_csv(window_placebos, window_placebos_path, na = "")

window_sensitivity <- window_sensitivity_base |>
  dplyr::left_join(window_placebo_ranks, by = "specification")

readr::write_csv(window_sensitivity, window_sensitivity_path, na = "")

message("Building donor China-exposure diagnostic...")

china_exposure <- build_china_exposure_diagnostic(
  synth_data = synth_data,
  trade_data_ranked = trade_data_ranked,
  trade_data_cleaned = trade_data_cleaned,
  unit_weights = unit_weights,
  pre_years = 1997:2008,
  post_years = 2009:2015
)

donor_china_exposure <- china_exposure$exposure
china_exposure_summary <- china_exposure$summary

readr::write_csv(donor_china_exposure, china_exposure_path, na = "")
readr::write_csv(china_exposure_summary, china_exposure_summary_path, na = "")

message("Writing tables and figures...")

table_captions <- tibble::tribble(
  ~item, ~type, ~caption,
  "Table A1", "table", "Table A1. Design contract for the Brazil SDiD with a single treated unit.",
  "Table A2", "table", "Table A2. Complete SDiD donor-unit weights for the Brazil synthetic counterfactual.",
  "Table A3", "table", "Table A3. SDiD pre-treatment time weights for the Brazil baseline.",
  "Table A4", "table", "Table A4. Brazil observed and synthetic-control outcome series.",
  "Table A5", "table", "Table A5. Intercept-adjusted pre-treatment fit summary for the Brazil SDiD baseline.",
  "Table A6", "table", "Table A6. Pre-treatment balance of the outcome and SDiD covariates.",
  "Table A7", "table", "Table A7. Placebo-in-space distribution by country.",
  "Table A8", "table", "Table A8. Rank-based placebo inference for a single treated unit.",
  "Table A9", "table", "Table A9. Sensitivity to influential donors and high-weight donor blocks.",
  "Table A10", "table", "Table A10. Sensitivity to plausible time windows around the 1997-2015 baseline.",
  "Table A11", "table", "Table A11. Long placebo-in-space results for window sensitivity.",
  "Table A12", "table", "Table A12. Donor exposure to China's export expansion, by SDiD weight.",
  "Table A13", "table", "Table A13. High-weight donor exposure to China's export expansion.",
  "Figure A1", "figure", "Figure A1. Observed Brazil versus synthetic-control pre-treatment fit and post-treatment gap.",
  "Figure A2", "figure", "Figure A2. Placebo-in-space distribution of SDiD effects, with Brazil marked.",
  "Figure A3", "figure", "Figure A3. Sensitivity of the Brazil SDiD estimate to removing high-weight donors.",
  "Figure A4", "figure", "Figure A4. Sensitivity of the Brazil SDiD estimate to alternative time windows.",
  "Figure A5", "figure", "Figure A5. High-weight donor exposure to China's post-2009 export expansion."
)
readr::write_csv(table_captions, caption_path, na = "")

write_latex_table(
  design_contract,
  path_table("table_a1_sdid_design_contract.tex"),
  caption = "Table A1. Design contract for the Brazil SDiD with a single treated unit.",
  label = "tab:sdid-design-contract"
)
write_latex_table(
  unit_weights |>
    dplyr::select(weight_rank, iso3c, country_name, region, unit_weight, cumulative_weight, high_weight_donor),
  path_table("table_a2_sdid_unit_weights_complete.tex"),
  caption = "Table A2. Complete SDiD donor-unit weights for the Brazil synthetic counterfactual.",
  label = "tab:sdid-unit-weights"
)
write_latex_table(
  time_weights,
  path_table("table_a3_sdid_time_weights.tex"),
  caption = "Table A3. SDiD pre-treatment time weights for the Brazil baseline.",
  label = "tab:sdid-time-weights"
)
write_latex_table(
  prefit_summary |>
    dplyr::select(specification, estimate, placebo_se, rmspe_pre, rmspe_post, rmspe_ratio, brazil_pre_treatment_mean, estimate_as_percent_of_pre_mean) |>
    dplyr::rename(
      adj_rmspe_pre = rmspe_pre,
      adj_rmspe_post = rmspe_post,
      adj_rmspe_ratio = rmspe_ratio
    ),
  path_table("table_a5_sdid_pre_treatment_fit_summary.tex"),
  caption = "Table A5. Intercept-adjusted pre-treatment fit summary for the Brazil SDiD baseline.",
  label = "tab:sdid-prefit"
)
write_latex_table(
  balance_table |>
    dplyr::select(variable, label, role, brazil_pre_mean, synthetic_pre_mean, brazil_minus_synthetic, standardized_difference),
  path_table("table_a6_sdid_pre_treatment_balance.tex"),
  caption = "Table A6. Pre-treatment balance of the outcome and SDiD covariates.",
  label = "tab:sdid-balance"
)
write_latex_table(
  placebo_inference,
  path_table("table_a8_sdid_placebo_rank_inference.tex"),
  caption = "Table A8. Rank-based placebo inference for a single treated unit.",
  label = "tab:sdid-placebo-rank"
)
write_latex_table(
  donor_sensitivity |>
    dplyr::select(specification, estimate, placebo_se, rmspe_pre, rmspe_ratio, n_removed_donors, estimate_change_vs_baseline, percent_change_vs_baseline, substantive_stability) |>
    dplyr::rename(
      adj_rmspe_pre = rmspe_pre,
      adj_rmspe_ratio = rmspe_ratio
    ),
  path_table("table_a9_sdid_influential_donor_sensitivity.tex"),
  caption = "Table A9. Sensitivity to influential donors and high-weight donor blocks.",
  label = "tab:sdid-donor-sensitivity"
)
write_latex_table(
  window_sensitivity |>
    dplyr::select(specification, estimate, rmspe_pre, rmspe_ratio, placebo_p_one_sided_negative, placebo_p_two_sided_abs, percent_change_vs_baseline, stability) |>
    dplyr::rename(
      adj_rmspe_pre = rmspe_pre,
      adj_rmspe_ratio = rmspe_ratio
    ),
  path_table("table_a10_sdid_window_sensitivity.tex"),
  caption = "Table A10. Sensitivity to plausible time windows around the 1997-2015 baseline.",
  label = "tab:sdid-window-sensitivity"
)
write_latex_table(
  donor_china_exposure |>
    dplyr::filter(high_weight_donor) |>
    dplyr::select(weight_rank, iso3c, country_name, unit_weight, mean_china_export_share_pre_treatment, mean_china_export_share_post_treatment, min_china_rank_post_treatment, china_exposure_flag),
  path_table("table_a13_sdid_high_weight_donor_china_exposure.tex"),
  caption = "Table A13. High-weight donor exposure to China's export expansion.",
  label = "tab:sdid-china-exposure"
)

prefit_plot_data <- baseline_series |>
  tidyr::pivot_longer(
    cols = c(brazil_observed, synthetic_control),
    names_to = "series",
    values_to = "value"
  ) |>
  dplyr::mutate(
    series = dplyr::recode(
      series,
      brazil_observed = "Brazil observed",
      synthetic_control = "Synthetic control"
    )
  )

prefit_plot <- ggplot(prefit_plot_data, aes(x = year, y = value, color = series)) +
  geom_vline(xintercept = 2009, linetype = "dashed", color = "grey35", linewidth = 0.45) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.8) +
  annotate("text", x = 2009.15, y = max(prefit_plot_data$value, na.rm = TRUE),
           label = "Treatment begins", hjust = 0, vjust = 1, size = 3.1, color = "grey25") +
  scale_x_continuous(breaks = seq(1997, 2016, by = 2)) +
  scale_color_manual(values = c("Brazil observed" = "#1f78b4", "Synthetic control" = "#b2182b")) +
  labs(
    x = "Year",
    y = "Absolute UNGA ideal-point distance to China",
    color = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")
save_plot_pair(prefit_plot, fig_prefit_png, fig_prefit_pdf, width = 8, height = 5)

placebo_plot <- placebo_distribution |>
  dplyr::filter(role == "Control placebo") |>
  ggplot(aes(x = estimate)) +
  geom_histogram(binwidth = 0.05, fill = "#bdbdbd", color = "white", boundary = 0) +
  geom_vline(xintercept = baseline_estimate, color = "#b2182b", linewidth = 1.0) +
  annotate("text", x = baseline_estimate, y = Inf, label = "Brazil", hjust = -0.1,
           vjust = 1.5, color = "#b2182b", size = 3.2) +
  labs(
    x = "Placebo SDiD estimate",
    y = "Number of control units"
  ) +
  theme_minimal(base_size = 11)
save_plot_pair(placebo_plot, fig_placebo_png, fig_placebo_pdf, width = 7, height = 4.8)

donor_sensitivity_plot_data <- donor_sensitivity |>
  dplyr::filter(n_removed_donors <= 1L, specification != "Baseline: no donor removed") |>
  dplyr::mutate(
    specification = stringr::str_remove(specification, "^Drop "),
    specification = stringr::str_replace(specification, " \\(rank ", "\nrank "),
    specification = stringr::str_remove(specification, "\\)$"),
    specification = forcats::fct_reorder(specification, estimate)
  )

donor_sensitivity_plot <- ggplot(donor_sensitivity_plot_data, aes(x = estimate, y = specification)) +
  geom_vline(xintercept = baseline_estimate, linetype = "dashed", color = "grey35") +
  geom_point(size = 2.4, color = "#1f78b4") +
  labs(
    x = "SDiD estimate after donor removal",
    y = "Removed donor"
  ) +
  theme_minimal(base_size = 11)
save_plot_pair(donor_sensitivity_plot, fig_donor_sensitivity_png, fig_donor_sensitivity_pdf, width = 7, height = 5.2)

window_plot <- ggplot(window_sensitivity, aes(x = specification, y = estimate)) +
  geom_hline(yintercept = 0, color = "grey70") +
  geom_hline(yintercept = baseline_estimate, linetype = "dashed", color = "grey35") +
  geom_point(aes(color = stability), size = 2.6) +
  coord_flip() +
  scale_color_manual(values = c(
    "Stable within 10%" = "#1b9e77",
    "Moderate movement" = "#d95f02",
    "Large movement" = "#7570b3",
    "Sign changes" = "#b2182b",
    "Not estimated" = "grey50"
  )) +
  labs(
    x = "Window",
    y = "SDiD estimate",
    color = "Stability"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")
save_plot_pair(window_plot, fig_window_png, fig_window_pdf, width = 7.5, height = 4.8)

china_exposure_plot_data <- donor_china_exposure |>
  dplyr::filter(high_weight_donor) |>
  dplyr::mutate(
    donor_label = paste0(iso3c, " (rank ", weight_rank, ")"),
    donor_label = forcats::fct_reorder(donor_label, unit_weight)
  )

china_exposure_plot <- ggplot(
  china_exposure_plot_data,
  aes(x = mean_china_export_share_post_treatment, y = donor_label, size = unit_weight, color = china_exposure_flag)
) +
  geom_point(alpha = 0.85) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_size_continuous(range = c(2, 7), guide = "none") +
  labs(
    x = "Mean export share to China, 2009-2015",
    y = "High-weight donor",
    color = "Exposure flag"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
save_plot_pair(china_exposure_plot, fig_china_exposure_png, fig_china_exposure_pdf, width = 8, height = 5.5)

validation_checks <- tibble::tibble(
  check = c(
    "Required targets readable",
    "Baseline target estimate extracted",
    "Unit weights sum to one",
    "Time weights sum to one",
    "Brazil is last row in synthdid setup",
    "Baseline series has both pre and post periods",
    "Placebo distribution includes Brazil",
    "Donor sensitivity generated",
    "Window sensitivity generated",
    "China exposure diagnostic generated",
    "No tar_make call in script"
  ),
  passed = c(
    nrow(missing_required) == 0L,
    !is.na(baseline_estimate),
    abs(sum(unit_weights$unit_weight) - 1) < 1e-8,
    abs(sum(time_weights$time_weight) - 1) < 1e-8,
    tail(rownames(setup$Y), 1) == "BRA",
    all(c("Pre-treatment", "Post-treatment") %in% baseline_series$period),
    any(placebo_distribution$iso3c == "BRA"),
    nrow(donor_sensitivity) > 1L,
    nrow(window_sensitivity) == nrow(window_specs),
    nrow(donor_china_exposure) > 0L,
    {
      executable_lines <- readLines(script_path, warn = FALSE) |>
        stringr::str_trim()
      !any(stringr::str_detect(executable_lines, "^targets::tar_make\\(")) &&
        !any(stringr::str_detect(executable_lines, "^tar_make\\("))
    }
  ),
  details = c(
    paste(required_targets, collapse = "; "),
    fmt_num(baseline_estimate, 6),
    fmt_num(sum(unit_weights$unit_weight), 8),
    fmt_num(sum(time_weights$time_weight), 8),
    tail(rownames(setup$Y), 1),
    paste(table(baseline_series$period), collapse = "; "),
    paste0("n=", nrow(placebo_distribution)),
    paste0("n=", nrow(donor_sensitivity)),
    paste0("n=", nrow(window_sensitivity)),
    paste0("n=", nrow(donor_china_exposure)),
    "Static check of script text"
  )
)
readr::write_csv(validation_checks, validation_path, na = "")

capture.output(sessionInfo(), file = session_info_path)

main_placebo_p <- placebo_inference |>
  dplyr::filter(estimand == "One-sided negative effect") |>
  dplyr::pull(rank_based_p_value)
main_placebo_rank <- placebo_inference |>
  dplyr::filter(estimand == "One-sided negative effect") |>
  dplyr::pull(rank)
main_placebo_den <- placebo_inference |>
  dplyr::filter(estimand == "One-sided negative effect") |>
  dplyr::pull(denominator)
rmspe_ratio_rank <- placebo_inference |>
  dplyr::filter(estimand == "Intercept-adjusted RMSPE ratio rank") |>
  dplyr::pull(rank)
rmspe_ratio_den <- placebo_inference |>
  dplyr::filter(estimand == "Intercept-adjusted RMSPE ratio rank") |>
  dplyr::pull(denominator)

top_weight_sentence <- unit_weights |>
  dplyr::slice_head(n = 5) |>
  dplyr::mutate(piece = paste0(iso3c, " (", fmt_num(100 * unit_weight, 1), "%)")) |>
  dplyr::pull(piece) |>
  paste(collapse = ", ")

largest_jackknife_change <- donor_sensitivity |>
  dplyr::filter(n_removed_donors == 1L) |>
  dplyr::arrange(dplyr::desc(abs(percent_change_vs_baseline))) |>
  dplyr::slice_head(n = 1)

window_bottom_line <- window_sensitivity |>
  dplyr::summarise(
    min_estimate = min(estimate, na.rm = TRUE),
    max_estimate = max(estimate, na.rm = TRUE),
    n_same_sign = sum(sign(estimate) == sign(baseline_estimate), na.rm = TRUE),
    n_windows = dplyr::n(),
    .groups = "drop"
  )

china_exposure_line <- china_exposure_summary |>
  dplyr::mutate(
    sentence = paste0(
      n_high_weight_top_china_post,
      " high-weight donors were top-China cases post-2009, and ",
      n_high_weight_top_two_china_post,
      " were top-two-China cases; these donors account for ",
      fmt_pct(100 * weighted_share_high_weight_top_two_china_post, 1),
      " of total SDiD unit weight."
    )
  ) |>
  dplyr::pull(sentence)

paper_text <- c(
  "### Draft SDiD Diagnostics Text for the Paper",
  "",
  "The Brazil analysis uses synthetic difference-in-differences with Brazil as the only treated unit and treatment beginning in 2009, when China became Brazil's largest export destination. The diagnostic package reports the complete donor-weight vector, the pre-treatment time weights, pre-treatment fit, covariate balance, placebo-in-space inference, donor-influence checks, and window sensitivity. [AUTHOR TO INSERT SUBSTANTIVE JUSTIFICATION FOR THE GLOBAL DONOR POOL HERE.]",
  "",
  paste0(
    "In the baseline 1997-2015 window, the SDiD estimate is ",
    fmt_num(baseline_estimate, 3),
    " ideal-point-distance units, with a placebo-based standard error of ",
    fmt_num(se_synth, 3),
    ". In the appendix, the fit diagnostic reports an intercept-adjusted pre-treatment RMSPE of ",
    fmt_num(prefit_summary$rmspe_pre, 3),
    " and a post/pre intercept-adjusted RMSPE ratio of ",
    fmt_num(prefit_summary$rmspe_ratio, 3),
    ", ranked ",
    rmspe_ratio_rank,
    " out of ",
    rmspe_ratio_den,
    " treated and placebo assignments. The largest donor weights are ",
    top_weight_sentence,
    ", and the full donor-weight vector is reported in the appendix rather than only the top donors."
  ),
  "",
  paste0(
    "For inference with one treated unit, the appendix reports a placebo-in-space distribution rather than relying only on asymptotic approximations. Brazil ranks ",
    main_placebo_rank,
    " out of ",
    main_placebo_den,
    " units in the one-sided negative-effect placebo distribution, implying a finite-sample rank p-value of ",
    fmt_num(main_placebo_p, 3),
    ". Donor-influence checks leave the sign of the estimate unchanged; the largest single-donor deletion changes the estimate by ",
    fmt_pct(largest_jackknife_change$percent_change_vs_baseline, 1),
    " relative to the baseline. Window checks around 1997-2015 also preserve the negative sign in ",
    window_bottom_line$n_same_sign,
    " of ",
    window_bottom_line$n_windows,
    " specifications, with estimates ranging from ",
    fmt_num(window_bottom_line$min_estimate, 3),
    " to ",
    fmt_num(window_bottom_line$max_estimate, 3),
    "."
  ),
  "",
  paste0(
    "Finally, the donor-exposure diagnostic treats China's trade expansion among donor countries as a possible SUTVA/contamination concern rather than as a donor-pool justification. ",
    china_exposure_line,
    " This diagnostic should be interpreted as a remaining design risk to be discussed alongside the author's substantive argument for the donor pool."
  )
)
writeLines(paper_text, paper_text_path, useBytes = TRUE)

report_lines <- c(
  "# Diagnóstico SDiD com uma única unidade tratada",
  "",
  paste0("Execução: ", run_timestamp),
  "",
  "Este relatório foi gerado por script separado do pipeline `targets`. Ele leu alvos existentes com `targets::tar_read_raw()`, não chamou `targets::tar_make()`, não editou `_targets.R`, `_targets/`, `_targets.yaml` nem o manuscrito. As fontes são os objetos já preservados no pipeline do projeto; nenhuma coleta externa nova foi feita nesta execução.",
  "",
  "## O que foi estimado",
  "",
  "O desenho reconstruído é um SDiD com Brasil como única unidade tratada, tratamento ligado a partir de 2009, outcome anual de distância absoluta do ideal point da AGNU em relação à China, e ATT médio pós-2009 em relação a um controle sintético ponderado.",
  "",
  "Table A1. Design contract for the Brazil SDiD with a single treated unit.",
  "",
  markdown_table(design_contract, digits = 4),
  "",
  "## Pesos SDiD",
  "",
  paste0("O vetor completo contém ", nrow(unit_weights), " donors e soma ", fmt_num(sum(unit_weights$unit_weight), 6), ". Os cinco maiores pesos são: ", top_weight_sentence, ". A tabela completa está em `", unit_weights_path, "`."),
  "",
  "Table A2. Top 20 donor-unit weights; the complete CSV reports all donors.",
  "",
  markdown_table(
    unit_weights |>
      dplyr::select(weight_rank, iso3c, country_name, region, unit_weight, cumulative_weight, high_weight_donor) |>
      dplyr::slice_head(n = 20),
    digits = 4
  ),
  "",
  "Table A3. SDiD pre-treatment time weights.",
  "",
  markdown_table(time_weights, digits = 4),
  "",
  "## Fit pré-tratamento",
  "",
  paste0(
    "O RMSPE pré-tratamento ajustado por intercepto é ",
    fmt_num(prefit_summary$rmspe_pre, 3),
    "; o RMSPE pós-tratamento ajustado pelo mesmo intercepto é ",
    fmt_num(prefit_summary$rmspe_post, 3),
    "; a razão pós/pré é ",
    fmt_num(prefit_summary$rmspe_ratio, 3),
    ". O fit é informativo, mas não perfeito: há discrepância visível em alguns anos pré-tratamento, de modo que a defesa deve depender também de placebos e sensibilidades, não apenas da figura."
  ),
  "",
  paste0("Figure A1. Observed Brazil versus synthetic-control pre-treatment fit and post-treatment gap: `", fig_prefit_png, "`."),
  "",
  "Table A5. Intercept-adjusted pre-treatment fit summary.",
  "",
  markdown_table(
    prefit_summary |>
      dplyr::select(specification, estimate, placebo_se, rmspe_pre, rmspe_post, rmspe_ratio, brazil_pre_treatment_mean, estimate_as_percent_of_pre_mean) |>
      dplyr::rename(
        adj_rmspe_pre = rmspe_pre,
        adj_rmspe_post = rmspe_post,
        adj_rmspe_ratio = rmspe_ratio
      ),
    digits = 3
  ),
  "",
  "Table A6. Pre-treatment balance of the outcome and SDiD covariates.",
  "",
  markdown_table(
    balance_table |>
      dplyr::select(variable, role, brazil_pre_mean, synthetic_pre_mean, brazil_minus_synthetic, standardized_difference),
    digits = 3
  ),
  "",
  "## Placebos",
  "",
  paste0(
    "A distribuição placebo inclui Brasil e unidades controle. Para o teste rank-based de efeito negativo, o Brasil ocupa rank ",
    main_placebo_rank,
    " de ",
    main_placebo_den,
    ", com p-valor finito ",
    fmt_num(main_placebo_p, 3),
    ". Este é o diagnóstico inferencial mais apropriado para um desenho com uma unidade tratada; o SE placebo continua útil como escala de incerteza, mas não resolve sozinho o problema de N tratado igual a 1."
  ),
  "",
  paste0("Figure A2. Placebo-in-space distribution: `", fig_placebo_png, "`."),
  "",
  "Table A8. Rank-based placebo inference.",
  "",
  markdown_table(placebo_inference, digits = 3),
  "",
  "## Sensibilidade a donors influentes",
  "",
  paste0(
    "As exclusões de donors influentes preservam o sinal negativo. A maior mudança em leave-one-donor-out ocorre em `",
    largest_jackknife_change$specification,
    "`, com mudança percentual de ",
    fmt_pct(largest_jackknife_change$percent_change_vs_baseline, 1),
    ". Os SEs/placebos não foram recomputados para cada exclusão porque isso exigiria uma bateria de placebo-in-space por especificação; a tabela registra essa limitação explicitamente."
  ),
  "",
  paste0("Figure A3. Donor jackknife sensitivity: `", fig_donor_sensitivity_png, "`."),
  "",
  "Table A9. Donor influence sensitivity.",
  "",
  markdown_table(
    donor_sensitivity |>
      dplyr::select(specification, estimate, placebo_se, rmspe_pre, rmspe_ratio, n_removed_donors, percent_change_vs_baseline, substantive_stability) |>
      dplyr::rename(
        adj_rmspe_pre = rmspe_pre,
        adj_rmspe_ratio = rmspe_ratio
      ),
    digits = 3
  ),
  "",
  "## Sensibilidade de janela",
  "",
  paste0(
    "As janelas plausíveis ao redor de 1997-2015 preservam o sinal negativo em ",
    window_bottom_line$n_same_sign,
    " de ",
    window_bottom_line$n_windows,
    " especificações. As estimativas variam de ",
    fmt_num(window_bottom_line$min_estimate, 3),
    " a ",
    fmt_num(window_bottom_line$max_estimate, 3),
    ". Quando `--skip-window-placebos` não é usado, a tabela também inclui ranks placebo por janela."
  ),
  "",
  paste0("Figure A4. Window sensitivity: `", fig_window_png, "`."),
  "",
  "Table A10. Window sensitivity.",
  "",
  markdown_table(
    window_sensitivity |>
      dplyr::select(specification, estimate, rmspe_pre, rmspe_ratio, placebo_p_one_sided_negative, placebo_p_two_sided_abs, percent_change_vs_baseline, stability) |>
      dplyr::rename(
        adj_rmspe_pre = rmspe_pre,
        adj_rmspe_ratio = rmspe_ratio
      ),
    digits = 3
  ),
  "",
  "## Exposição dos controles à expansão comercial chinesa",
  "",
  paste0(
    "Este diagnóstico é descritivo e trata exposição chinesa entre donors como ameaça potencial a SUTVA/contaminação, não como justificativa substantiva para o donor pool global. ",
    china_exposure_line
  ),
  "",
  paste0("Figure A5. High-weight donor China exposure: `", fig_china_exposure_png, "`."),
  "",
  "Table A13. High-weight donor exposure to China's export expansion.",
  "",
  markdown_table(
    donor_china_exposure |>
      dplyr::filter(high_weight_donor) |>
      dplyr::select(weight_rank, iso3c, country_name, unit_weight, mean_china_export_share_pre_treatment, mean_china_export_share_post_treatment, min_china_rank_post_treatment, china_exposure_flag),
    digits = 3
  ),
  "",
  "## Riscos remanescentes",
  "",
  "- Os diagnósticos aumentam a credibilidade do contrafactual, mas não testam diretamente a ausência de choques brasileiros contemporâneos em 2009.",
  "- A inferência rank-based é apropriada para uma unidade tratada, mas tem granularidade limitada pelo número finito de unidades placebo.",
  "- A presença de donors com exposição relevante à expansão comercial chinesa deve ser discutida como risco de interferência/contaminação. A justificativa substantiva do donor pool global deve ser inserida pelo autor, separadamente.",
  "- Os SEs/ranks não foram recomputados para cada jackknife de donor porque isso exigiria uma bateria placebo por especificação; a tabela de sensibilidade deve ser lida como estabilidade do ponto estimado e do fit.",
  "",
  "## Bloco de texto em inglês para adaptação",
  "",
  paste(paper_text[-1], collapse = "\n"),
  "",
  "## Validação",
  "",
  markdown_table(validation_checks, digits = 4),
  "",
  "## Arquivos principais",
  "",
  markdown_table(
    tibble::tibble(
      output = c(
        "Object audit",
        "Complete unit weights",
        "Time weights",
        "Pre-treatment balance",
        "Placebo distribution",
        "Donor sensitivity",
        "Window sensitivity",
        "China exposure",
        "Paper text block",
        "Session info"
      ),
      path = c(
        object_audit_path,
        unit_weights_path,
        time_weights_path,
        balance_path,
        placebo_distribution_path,
        donor_sensitivity_path,
        window_sensitivity_path,
        china_exposure_path,
        paper_text_path,
        session_info_path
      )
    ),
    digits = 3
  )
)

writeLines(report_lines, report_path, useBytes = TRUE)

pdf_render_result <- tryCatch(
  {
    if (!requireNamespace("rmarkdown", quietly = TRUE)) {
      stop("rmarkdown is not installed.")
    }
    if (!rmarkdown::pandoc_available()) {
      stop("pandoc is not available.")
    }
    rmarkdown::pandoc_convert(
      input = normalizePath(report_path),
      to = "pdf",
      output = normalizePath(report_pdf_path, mustWork = FALSE),
      options = c("--pdf-engine=xelatex", "-V", "geometry:margin=1in")
    )
    paste0("PDF rendered successfully: ", report_pdf_path)
  },
  error = function(e) {
    paste0("PDF render failed: ", conditionMessage(e))
  }
)
writeLines(pdf_render_result, pdf_render_log_path, useBytes = TRUE)

manifest <- tibble::tibble(
  path = c(
    object_audit_path,
    design_contract_path,
    unit_weights_path,
    time_weights_path,
    series_path,
    prefit_summary_path,
    balance_path,
    placebo_distribution_path,
    placebo_inference_path,
    donor_sensitivity_path,
    window_sensitivity_path,
    window_placebos_path,
    china_exposure_path,
    china_exposure_summary_path,
    validation_path,
    caption_path,
    fig_prefit_png,
    fig_prefit_pdf,
    fig_placebo_png,
    fig_placebo_pdf,
    fig_donor_sensitivity_png,
    fig_donor_sensitivity_pdf,
    fig_window_png,
    fig_window_pdf,
    fig_china_exposure_png,
    fig_china_exposure_pdf,
    paper_text_path,
    report_path,
    report_pdf_path,
    pdf_render_log_path,
    session_info_path
  ),
  exists = file.exists(path),
  bytes = ifelse(file.exists(path), file.info(path)$size, NA_real_)
)
readr::write_csv(manifest, manifest_path, na = "")

message("Done. Report written to: ", report_path)
