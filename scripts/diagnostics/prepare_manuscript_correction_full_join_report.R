#!/usr/bin/env Rscript

# Prepare the data tables, validation artifacts, and publication-ready figures
# for a report explaining how the corrected full-join/consecutive-calendar-year
# treatment rule should be incorporated into paper_v4.Rmd.
#
# This diagnostic is deliberately external to targets. It reads preserved
# outputs and the manuscript source, but does not modify or run the pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(scales)
  library(tibble)
  library(tidyr)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

args <- commandArgs(trailingOnly = TRUE)
manifest_only <- "--manifest-only" %in% args
report_date <- as.Date("2026-08-29")

analysis_root <- file.path(
  "data", "processed", "diagnostics",
  "china_top_m2_goods_full_join_consecutive", "final"
)
analysis_prefix <- "m2_goods_full_join_consecutive_2026-08-29"
report_dir <- file.path(
  "quality_reports", "cross_country_sample",
  "manuscript_correction_full_join"
)
figure_dir <- file.path(report_dir, "figures")
output_dir <- file.path(
  "data", "processed", "diagnostics",
  "manuscript_correction_full_join"
)

dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

path_from_analysis <- function(suffix) {
  file.path(analysis_root, paste0(analysis_prefix, suffix))
}

master_path <- path_from_analysis("_master_panel.csv")
estimation_path <- path_from_analysis("_main_estimation_panel.csv")
model_comparison_path <- path_from_analysis("_model_comparison.csv")
model_result_path <- path_from_analysis("_model_result.csv")
fixed_r_path <- path_from_analysis("_fixed_r_sensitivity.csv")
country_comparison_path <- path_from_analysis("_country_comparison.csv")
row_audit_path <- path_from_analysis("_row_audit.csv")
change_reason_path <- path_from_analysis("_change_reason_audit.csv")
final_manifest_path <- path_from_analysis("_manifest.csv")
decision_path <- file.path(
  "quality_reports", "cross_country_sample",
  "2026-08-29_decisao_painel_full_join_tratamento_comercial.md"
)
paper_source_path <- "paper_v4.Rmd"
paper_pdf_path <- "paper_v4.pdf"
script_path <- file.path(
  "scripts", "diagnostics",
  "prepare_manuscript_correction_full_join_report.R"
)
report_rmd_path <- file.path(
  report_dir,
  "manuscript_correction_full_join_2026-08-29.Rmd"
)
report_pdf_path <- sub("[.]Rmd$", ".pdf", report_rmd_path)

sample_flow_path <- file.path(output_dir, "sample_flow_2026-08-29.csv")
estimate_comparison_path <- file.path(
  output_dir,
  "estimate_comparison_2026-08-29.csv"
)
affected_countries_path <- file.path(
  output_dir,
  "affected_countries_2026-08-29.csv"
)
manuscript_locations_path <- file.path(
  output_dir,
  "manuscript_locations_2026-08-29.csv"
)
correction_matrix_path <- file.path(
  output_dir,
  "manuscript_correction_matrix_2026-08-29.csv"
)
validation_path <- file.path(
  output_dir,
  "validation_summary_2026-08-29.csv"
)
manifest_path <- file.path(
  output_dir,
  "report_manifest_2026-08-29.csv"
)

figure_1_pdf <- file.path(figure_dir, "figure_1_congo_timeline.pdf")
figure_1_png <- file.path(figure_dir, "figure_1_congo_timeline.png")
figure_2_pdf <- file.path(figure_dir, "figure_2_sample_flow.pdf")
figure_2_png <- file.path(figure_dir, "figure_2_sample_flow.png")
figure_3_pdf <- file.path(figure_dir, "figure_3_estimate_comparison.pdf")
figure_3_png <- file.path(figure_dir, "figure_3_estimate_comparison.png")
figure_4_pdf <- file.path(figure_dir, "figure_4_affected_countries.pdf")
figure_4_png <- file.path(figure_dir, "figure_4_affected_countries.png")

input_paths <- c(
  master_path,
  estimation_path,
  model_comparison_path,
  model_result_path,
  fixed_r_path,
  country_comparison_path,
  row_audit_path,
  change_reason_path,
  final_manifest_path,
  decision_path,
  paper_source_path,
  paper_pdf_path
)

generated_paths <- c(
  sample_flow_path,
  estimate_comparison_path,
  affected_countries_path,
  manuscript_locations_path,
  correction_matrix_path,
  validation_path,
  figure_1_pdf,
  figure_1_png,
  figure_2_pdf,
  figure_2_png,
  figure_3_pdf,
  figure_3_png,
  figure_4_pdf,
  figure_4_png
)

required_paths <- c(input_paths, script_path, report_rmd_path)
missing_required <- required_paths[!file.exists(required_paths)]
if (length(missing_required) > 0L) {
  stop(
    "Required files are missing: ",
    paste(missing_required, collapse = ", "),
    call. = FALSE
  )
}

sha256_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

abort_if_duplicates <- function(data, keys, label) {
  duplicates <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L)
  if (nrow(duplicates) > 0L) {
    stop(label, " contains duplicate keys.", call. = FALSE)
  }
  invisible(TRUE)
}

save_plot <- function(plot, pdf_path, png_path, width, height) {
  ggplot2::ggsave(
    filename = pdf_path,
    plot = plot,
    width = width,
    height = height,
    units = "in",
    device = grDevices::pdf
  )
  ggplot2::ggsave(
    filename = png_path,
    plot = plot,
    width = width,
    height = height,
    units = "in",
    dpi = 320,
    bg = "white"
  )
}

if (!manifest_only) {
  message("Reading final corrected artifacts and the active manuscript source.")
  master <- readr::read_csv(master_path, show_col_types = FALSE)
  estimation <- readr::read_csv(estimation_path, show_col_types = FALSE)
  model_comparison <- readr::read_csv(
    model_comparison_path,
    show_col_types = FALSE
  )
  model_result <- readr::read_csv(model_result_path, show_col_types = FALSE)
  fixed_r <- readr::read_csv(fixed_r_path, show_col_types = FALSE)
  country_comparison <- readr::read_csv(
    country_comparison_path,
    show_col_types = FALSE
  )
  row_audit <- readr::read_csv(row_audit_path, show_col_types = FALSE)
  change_reason <- readr::read_csv(
    change_reason_path,
    show_col_types = FALSE
  )

  abort_if_duplicates(master, c("iso3c", "year"), "Master panel")
  abort_if_duplicates(estimation, c("iso3c", "year"), "Estimation panel")

  if (nrow(master) != dplyr::n_distinct(master$iso3c) * 34L) {
    stop("The master panel is not a complete 1990-2023 grid.", call. = FALSE)
  }
  if (anyNA(estimation$abs_distance_china) || anyNA(estimation$china_top)) {
    stop("The estimation panel contains missing outcome or treatment.",
         call. = FALSE)
  }
  if (!all(estimation$china_top %in% c(0, 1))) {
    stop("The estimation treatment is not binary.", call. = FALSE)
  }

  main_value <- function(statistic, column) {
    value <- model_comparison |>
      dplyr::filter(.data$statistic == .env$statistic) |>
      dplyr::pull(dplyr::all_of(column))
    if (length(value) != 1L) {
      stop("Model comparison statistic is not unique: ", statistic,
           call. = FALSE)
    }
    value
  }

  old_att <- main_value("ATT", "previous")
  old_se <- main_value("Bootstrap SE", "previous")
  old_ci_low <- main_value("CI lower", "previous")
  old_ci_high <- main_value("CI upper", "previous")
  old_p <- main_value("p-value", "previous")
  old_r <- main_value("Selected latent factors", "previous")
  new_att <- main_value("ATT", "corrected")
  new_se <- main_value("Bootstrap SE", "corrected")
  new_ci_low <- main_value("CI lower", "corrected")
  new_ci_high <- main_value("CI upper", "corrected")
  new_p <- main_value("p-value", "corrected")
  new_r <- main_value("Selected latent factors", "corrected")

  estimate_comparison <- dplyr::bind_rows(
    tibble::tibble(
      specification = c(
        "Current pipeline, CV",
        "Corrected full-join, CV"
      ),
      comparison = "Treatment coding",
      estimate = c(old_att, new_att),
      se = c(old_se, new_se),
      ci_low = c(old_ci_low, new_ci_low),
      ci_high = c(old_ci_high, new_ci_high),
      p_value = c(old_p, new_p),
      latent_factors = c(old_r, new_r),
      nboots = 10000L
    ),
    fixed_r |>
      dplyr::transmute(
        specification = paste0("Corrected, fixed r = ", specified_r),
        comparison = "Factor sensitivity",
        estimate = att,
        se,
        ci_low = ci_lo,
        ci_high = ci_hi,
        p_value = p,
        latent_factors = specified_r,
        nboots = as.integer(nboots)
      )
  ) |>
    dplyr::mutate(
      specification = factor(
        specification,
        levels = c(
          "Corrected, fixed r = 2",
          "Corrected, fixed r = 1",
          "Corrected full-join, CV",
          "Current pipeline, CV"
        )
      )
    )

  sample_flow <- tibble::tibble(
    stage = c(
      "Master country-year grid",
      "Substantive risk set",
      "Observed-outcome candidates",
      "Final IFE estimation sample"
    ),
    country_years = c(
      nrow(master),
      sum(master$main_risk_set_eligible),
      sum(master$main_estimation_candidate),
      sum(master$main_estimation_included)
    )
  ) |>
    dplyr::mutate(
      loss_from_previous = c(
        NA_integer_,
        head(country_years, -1L) - tail(country_years, -1L)
      )
    )

  affected_countries <- country_comparison |>
    dplyr::filter(classification_change != "unchanged") |>
    dplyr::mutate(
      new_n_obs = dplyr::coalesce(new_n_obs, 0),
      observations_removed = old_n_obs - new_n_obs,
      change_label = dplyr::case_when(
        classification_change == "country_removed" ~
          "Entire control country removed",
        TRUE ~ "Some rows removed"
      )
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      old_n_obs,
      new_n_obs,
      observations_removed,
      change_label
    ) |>
    dplyr::arrange(dplyr::desc(observations_removed), country_name)

  manuscript_lines <- readLines(paper_source_path, warn = FALSE)
  manuscript_targets <- tibble::tribble(
    ~location_id, ~needle, ~required_action,
    "design_definition",
    "For the cross-country evidence beyond Brazil, the treated sample is restricted",
    "Replace the prose with a source-specific, consecutive-calendar-year definition.",
    "main_treatment_definition",
    "I therefore estimate the same treatment logic in a goods-only status-current panel",
    "Replace 'five observed years' and state how missing trade and outcome data differ.",
    "intro_result_object",
    "cross_country_results_intro <- tar_read(",
    "Point the introduction to targets rebuilt under the corrected rule.",
    "main_result_object",
    "m2_model_results <- tar_read(china_top_m2_goods_status_current_model_results)",
    "Replace the old results target after integrating the full-join construction.",
    "main_result_prose",
    "The preferred cross-country specification is the no-covariate IFE model",
    "Refresh ATT, uncertainty, unit counts, and factor-sensitivity language.",
    "dynamic_figure",
    "Figure \\@ref(fig:cross-country-dynamic) separates the event-time estimates",
    "Regenerate the dynamic figure from the corrected fit and audit its support labels.",
    "duration_robustness",
    "The main cross-country estimate uses a five-year durability threshold",
    "Re-estimate 3/7-year and clean single-entry checks under the same corrected construction.",
    "sample_audit",
    "The revised rank metric excludes services before partner ranks are computed",
    "Replace the country audit with full-union roles and explicit row-level exclusions.",
    "treated_country_table",
    "Table \\@ref(tab:table-treated-appendix) describes",
    "Regenerate treated-country counts and retained years from the corrected panel."
  )

  locate_line <- function(needle) {
    hits <- which(grepl(needle, manuscript_lines, fixed = TRUE))
    if (length(hits) == 0L) {
      stop("Manuscript anchor not found: ", needle, call. = FALSE)
    }
    hits[[1]]
  }

  manuscript_locations <- manuscript_targets |>
    dplyr::rowwise() |>
    dplyr::mutate(
      line = locate_line(needle),
      current_text = manuscript_lines[[line]]
    ) |>
    dplyr::ungroup() |>
    dplyr::select(
      location_id,
      line,
      current_text,
      required_action
    )

  correction_matrix <- tibble::tribble(
    ~priority, ~manuscript_component, ~status, ~correction,
    "P0", "Treatment definition (main text)", "Ready",
    "Replace ambiguous joint-panel language with trade-defined consecutive calendar years and source-specific missingness.",
    "P0", "Cross-country targets", "Not integrated",
    "Move the full join, complete grid, treatment, risk-set, and support flags into new targets before manuscript adoption.",
    "P0", "Robustness claims", "Blocked pending re-estimation",
    "Re-run 3/7-year thresholds and clean single-entry robustness; the diagnostic final run covers only the main five-year restricted risk set.",
    "P1", "Main IFE result", "Ready",
    "Update the computed result to ATT -0.101, SE 0.039, CI [-0.178, -0.024], p = 0.010, with 35 treated and 125 controls.",
    "P1", "Factor dimension", "Ready",
    "Disclose that fixed r=1 gives ATT -0.047 (p=0.199), while CV selects r=2 and reproduces ATT -0.101 (p=0.010).",
    "P1", "Tables and dynamic figure", "Needs target rebuild",
    "Regenerate the main table, dynamic figure, sample audit, and treated-country appendix from corrected targets.",
    "P1", "Introduction robustness range", "Blocked pending re-estimation",
    "Do not retain the claim that p-values are stable across durations/samples until corrected robustness models exist.",
    "P2", "Data provenance note", "Ready",
    "Document the ITPD-E/UNGA full union, complete 1990-2023 grid, tie handling, and outcome-independent treatment coding."
  )

  congo <- master |>
    dplyr::filter(iso3c == "COD", year >= 2000L, year <= 2023L)
  congo_2021 <- congo |>
    dplyr::filter(year == 2021L)

  validation_summary <- tibble::tibble(
    validation = c(
      "Master panel has unique country-year keys",
      "Master panel is a complete 1990-2023 grid",
      "Estimation panel has no missing outcome or treatment",
      "Estimation treatment is binary",
      "Congo 2021 is treated with missing outcome",
      "Congo 2021 remains in risk set and outside estimation",
      "Corrected treated country-years equal 440",
      "Corrected estimation observations equal 5002",
      "Current manuscript source anchors were all located"
    ),
    passed = c(
      TRUE,
      nrow(master) == dplyr::n_distinct(master$iso3c) * 34L,
      !anyNA(estimation$abs_distance_china) && !anyNA(estimation$china_top),
      all(estimation$china_top %in% c(0, 1)),
      nrow(congo_2021) == 1L && congo_2021$china_top == 1L &&
        !congo_2021$outcome_observed,
      nrow(congo_2021) == 1L && congo_2021$main_risk_set_eligible &&
        !congo_2021$main_estimation_included,
      sum(estimation$china_top == 1L) == 440L,
      nrow(estimation) == 5002L,
      nrow(manuscript_locations) == nrow(manuscript_targets)
    )
  )
  if (!all(validation_summary$passed)) {
    stop("At least one report validation failed.", call. = FALSE)
  }

  readr::write_csv(sample_flow, sample_flow_path, na = "")
  readr::write_csv(estimate_comparison, estimate_comparison_path, na = "")
  readr::write_csv(affected_countries, affected_countries_path, na = "")
  readr::write_csv(manuscript_locations, manuscript_locations_path, na = "")
  readr::write_csv(correction_matrix, correction_matrix_path, na = "")
  readr::write_csv(validation_summary, validation_path, na = "")

  message("Creating Figure 1: Congo treatment/outcome timeline.")
  congo_timeline <- dplyr::bind_rows(
    congo |>
      dplyr::transmute(
        year,
        track = "Trade-rank status",
        state = dplyr::case_when(
          china_top_status == 1 & qualifying_period ~
            "China rank 1",
          china_top_status == 0 ~ "Another destination rank 1",
          TRUE ~ "Trade rank unavailable or tied"
        )
      ),
    congo |>
      dplyr::transmute(
        year,
        track = "UNGA outcome availability",
        state = dplyr::if_else(
          outcome_observed,
          "UNGA outcome observed",
          "UNGA outcome missing"
        )
      )
  ) |>
    dplyr::mutate(
      track = factor(
        track,
        levels = c("UNGA outcome availability", "Trade-rank status")
      ),
      state = factor(
        state,
        levels = c(
          "Another destination rank 1",
          "China rank 1",
          "Trade rank unavailable or tied",
          "UNGA outcome observed",
          "UNGA outcome missing"
        )
      )
    )

  p_congo <- ggplot2::ggplot(
    congo_timeline,
    ggplot2::aes(x = year, y = track, fill = state)
  ) +
    ggplot2::geom_tile(width = 0.92, height = 0.68, color = "white") +
    ggplot2::geom_vline(
      xintercept = 2007.5,
      linetype = "dashed",
      color = "#333333",
      linewidth = 0.45
    ) +
    ggplot2::annotate(
      "text",
      x = 2008.1,
      y = 2.42,
      label = "Entry: 2008",
      hjust = 0,
      size = 3.2,
      family = "sans"
    ) +
    ggplot2::annotate(
      "text",
      x = 2021,
      y = 0.58,
      label = "2021: Y missing, D = 1",
      hjust = 1,
      size = 3.1,
      family = "sans"
    ) +
    ggplot2::scale_fill_manual(
      values = c(
        "Another destination rank 1" = "#999999",
        "China rank 1" = "#0072B2",
        "Trade rank unavailable or tied" = "#D55E00",
        "UNGA outcome observed" = "#56B4E9",
        "UNGA outcome missing" = "#E69F00"
      ),
      drop = FALSE
    ) +
    ggplot2::scale_x_continuous(
      breaks = seq(2000, 2022, by = 2),
      minor_breaks = NULL,
      expand = ggplot2::expansion(add = 0.6)
    ) +
    ggplot2::labs(x = "Calendar year", y = NULL, fill = NULL) +
    ggplot2::theme_minimal(base_size = 10.5, base_family = "sans") +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      legend.position = "bottom",
      legend.text = ggplot2::element_text(size = 8),
      axis.text.y = ggplot2::element_text(face = "bold"),
      plot.margin = ggplot2::margin(10, 8, 6, 8)
    ) +
    ggplot2::guides(
      fill = ggplot2::guide_legend(nrow = 3, byrow = TRUE)
    )

  save_plot(p_congo, figure_1_pdf, figure_1_png, 7.0, 3.65)

  message("Creating Figure 2: sample-construction flow.")
  flow_plot_data <- sample_flow |>
    dplyr::mutate(
      stage = factor(stage, levels = rev(stage)),
      label = scales::comma(country_years)
    )
  p_flow <- ggplot2::ggplot(
    flow_plot_data,
    ggplot2::aes(x = stage, y = country_years, fill = stage)
  ) +
    ggplot2::geom_col(width = 0.66, show.legend = FALSE) +
    ggplot2::geom_text(
      ggplot2::aes(label = label),
      hjust = -0.12,
      size = 3.6,
      family = "sans"
    ) +
    ggplot2::coord_flip(clip = "off") +
    ggplot2::scale_fill_manual(
      values = c("#4C78A8", "#72A0C1", "#9CC4D4", "#1B6CA8")
    ) +
    ggplot2::scale_y_continuous(
      labels = scales::comma,
      limits = c(0, max(sample_flow$country_years) * 1.10),
      expand = c(0, 0)
    ) +
    ggplot2::labs(x = NULL, y = "Country-years") +
    ggplot2::theme_minimal(base_size = 10.5, base_family = "sans") +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(face = "bold"),
      plot.margin = ggplot2::margin(8, 18, 8, 8)
    )

  save_plot(p_flow, figure_2_pdf, figure_2_png, 7.0, 3.6)

  message("Creating Figure 3: coefficient and factor-sensitivity comparison.")
  p_estimates <- ggplot2::ggplot(
    estimate_comparison,
    ggplot2::aes(
      x = estimate,
      y = specification,
      color = comparison,
      shape = comparison
    )
  ) +
    ggplot2::geom_vline(
      xintercept = 0,
      linetype = "dashed",
      color = "#555555",
      linewidth = 0.45
    ) +
    ggplot2::geom_segment(
      ggplot2::aes(x = ci_low, xend = ci_high, yend = specification),
      linewidth = 1.05
    ) +
    ggplot2::geom_point(size = 3.1, stroke = 0.9) +
    ggplot2::geom_text(
      ggplot2::aes(
        x = 0.035,
        label = paste0(
          "ATT ", sprintf("%.3f", estimate),
          "; p ", ifelse(p_value < 0.001, "< .001", paste0("= ", sprintf("%.3f", p_value)))
        )
      ),
      hjust = 0,
      color = "#222222",
      size = 3.0,
      family = "sans"
    ) +
    ggplot2::scale_color_manual(
      values = c(
        "Treatment coding" = "#0072B2",
        "Factor sensitivity" = "#D55E00"
      )
    ) +
    ggplot2::scale_shape_manual(
      values = c("Treatment coding" = 16, "Factor sensitivity" = 17)
    ) +
    ggplot2::scale_x_continuous(
      limits = c(-0.20, 0.13),
      breaks = seq(-0.20, 0.10, by = 0.05)
    ) +
    ggplot2::labs(
      x = "ATT on absolute UNGA ideal-point distance to China (95% CI)",
      y = NULL,
      color = NULL,
      shape = NULL
    ) +
    ggplot2::theme_minimal(base_size = 10.5, base_family = "sans") +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(face = "bold"),
      legend.position = "bottom",
      plot.margin = ggplot2::margin(8, 8, 8, 8)
    )

  save_plot(p_estimates, figure_3_pdf, figure_3_png, 7.0, 4.1)

  message("Creating Figure 4: countries with changed estimation rows.")
  affected_plot_data <- affected_countries |>
    dplyr::mutate(
      country_name = reorder(country_name, observations_removed),
      label = as.character(observations_removed)
    )
  p_affected <- ggplot2::ggplot(
    affected_plot_data,
    ggplot2::aes(
      x = observations_removed,
      y = country_name,
      fill = change_label
    )
  ) +
    ggplot2::geom_col(width = 0.64) +
    ggplot2::geom_text(
      ggplot2::aes(label = label),
      hjust = -0.25,
      size = 3.4,
      family = "sans"
    ) +
    ggplot2::scale_fill_manual(
      values = c(
        "Some rows removed" = "#56B4E9",
        "Entire control country removed" = "#D55E00"
      )
    ) +
    ggplot2::scale_x_continuous(
      breaks = c(0, 5, 10, 15, 20, 25),
      limits = c(0, max(affected_countries$observations_removed) * 1.12),
      expand = c(0, 0)
    ) +
    ggplot2::labs(
      x = "Country-years removed from the estimation sample",
      y = NULL,
      fill = NULL
    ) +
    ggplot2::theme_minimal(base_size = 10.5, base_family = "sans") +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "bottom",
      axis.text.y = ggplot2::element_text(face = "bold"),
      plot.margin = ggplot2::margin(8, 14, 8, 8)
    )

  save_plot(p_affected, figure_4_pdf, figure_4_png, 7.0, 4.0)
}

if (manifest_only) {
  missing_generated <- generated_paths[!file.exists(generated_paths)]
  if (length(missing_generated) > 0L) {
    stop(
      "Cannot finalize manifest; generated files are missing: ",
      paste(missing_generated, collapse = ", "),
      call. = FALSE
    )
  }
  if (!file.exists(report_pdf_path)) {
    stop("Cannot finalize manifest before the report PDF exists.",
         call. = FALSE)
  }
}

manifest_files <- c(
  input_paths,
  script_path,
  report_rmd_path,
  generated_paths,
  if (file.exists(report_pdf_path)) report_pdf_path else character(0)
)
manifest <- tibble::tibble(
  file = manifest_files,
  role = c(
    rep("input", length(input_paths)),
    "script",
    "report_source",
    rep("output", length(generated_paths)),
    if (file.exists(report_pdf_path)) "final_report" else character(0)
  )
) |>
  dplyr::mutate(
    sha256 = vapply(file, sha256_file, character(1)),
    bytes = file.info(file)$size,
    modified = format(file.info(file)$mtime, "%Y-%m-%d %H:%M:%S %Z"),
    accessed_on = as.character(Sys.Date()),
    report_date = as.character(report_date)
  )
readr::write_csv(manifest, manifest_path, na = "")

message("Report preparation complete. Manifest: ", manifest_path)
