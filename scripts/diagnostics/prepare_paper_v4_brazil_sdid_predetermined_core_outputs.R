#!/usr/bin/env Rscript

# The three figures paper_v4.Rmd prints as pre-rendered PNGs through
# include_graphics: the preferred SDiD fit (chunk plot-sdid), the Latin America
# fit (plot-latam) and the ten largest donor weights (plot-weights).
#
# Why this file is only that (2026-08-25). It used to also write a dozen CSVs
# into data/processed/diagnostics/paper_v4_brazil_sdid_predetermined_core/ and
# to guard them against three FROZEN inputs: a July specification table, a July
# placebo-in-space distribution, and a May snapshot of the goods panel. The
# manuscript reads none of those CSVs -- it reads the ones
# audit_brazil_sdid_no_covariates.R writes into
# paper_v4_brazil_sdid_no_covariates/ -- and the frozen inputs had gone stale in
# a way that could not be papered over: the July distribution's donor set still
# contains Malta and still lacks Singapore, and the July table's ATT differs
# from the live target in the fourth decimal, so the guard failed outright.
# Everything below therefore comes from live targets, and nothing but the
# figures is produced.
#
# Runs in the `diagnostics` batch, after audit_brazil_sdid_no_covariates.R
# regenerates the CSVs the manuscript prints beside these figures.
# Reads existing targets; never runs the pipeline.

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(ggplot2)
  library(synthdid)
  library(countrycode)
})

source(file.path("scripts", "functions.R"))

set.seed(20260714L)

# Nothing here may build a target: this script is a consumer, and a rebuild
# triggered from inside a diagnostic step would be invisible in the batch log.
targets_metadata_path <- file.path("_targets", "meta", "meta")
targets_metadata_mtime_before <- as.numeric(
  file.info(targets_metadata_path)$mtime
)

figure_dir <- file.path(
  "quality_reports", "china_demand_shock_rank_threshold"
)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

core_fit <- targets::tar_read_raw(
  "synth_fit_no_time_varying_covariates", store = "_targets"
)
synth_data <- targets::tar_read_raw("synth_data", store = "_targets")

unit_weights <- brazil_sdid_unit_weights(core_fit, synth_data)
stopifnot(abs(sum(unit_weights$unit_weight) - 1) < 1e-10)

# ---- Figure: preferred fit (paper_v4.Rmd chunk plot-sdid) -----------------
trend_plot <- my_plot_trends(core_fit) +
  ggplot2::labs(
    title = NULL,
    subtitle = "Preferred specification with no effective covariate adjustment"
  )
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_fit.pdf"),
  trend_plot, width = 7, height = 4.8, device = grDevices::pdf
)
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_fit.png"),
  trend_plot, width = 7, height = 4.8, dpi = 300
)

# ---- Figure: Latin America donor pool (chunk plot-latam) ------------------
latam_core_fit <- simple_fit_no_time_varying_covariates(
  synth_data, time_treatment = 2008L, time_end = 2016L,
  filter_latin_america = TRUE
)
latam_trend_plot <- my_plot_trends(latam_core_fit) +
  ggplot2::labs(
    title = NULL,
    subtitle = "Latin America donors; no effective covariate adjustment"
  )
ggplot2::ggsave(
  file.path(
    figure_dir,
    "figure_brazil_sdid_predetermined_core_latam_fit.pdf"
  ),
  latam_trend_plot, width = 7, height = 4.8, device = grDevices::pdf
)
ggplot2::ggsave(
  file.path(
    figure_dir,
    "figure_brazil_sdid_predetermined_core_latam_fit.png"
  ),
  latam_trend_plot, width = 7, height = 4.8, dpi = 300
)

# ---- Figure: ten largest donor weights (chunk plot-weights) ---------------
# The bug that made this script part of the rebuild: the pool changed and this
# figure did not, so the manuscript kept printing Malta as the second largest
# donor after the tables had dropped it.
weights_plot_data <- unit_weights |>
  dplyr::slice_head(n = 10) |>
  dplyr::mutate(
    donor_label = paste0(country_name, " (", iso3c, ")"),
    donor_label = stats::reorder(donor_label, unit_weight)
  )
weights_plot <- ggplot2::ggplot(
  weights_plot_data,
  ggplot2::aes(x = donor_label, y = unit_weight)
) +
  ggplot2::geom_col(fill = "#2B6F77", width = 0.72) +
  ggplot2::coord_flip() +
  ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  ggplot2::labs(x = NULL, y = "Donor weight") +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_weights.pdf"),
  weights_plot, width = 7, height = 4.8, device = grDevices::pdf
)
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_weights.png"),
  weights_plot, width = 7, height = 4.8, dpi = 300
)

targets_metadata_mtime_after <- as.numeric(
  file.info(targets_metadata_path)$mtime
)
stopifnot(isTRUE(all.equal(
  targets_metadata_mtime_before, targets_metadata_mtime_after, tolerance = 0
)))

message(
  "Manuscript figures written to: ", figure_dir,
  " (donors in the weight figure: ",
  paste(weights_plot_data$iso3c, collapse = ", "), ")"
)
