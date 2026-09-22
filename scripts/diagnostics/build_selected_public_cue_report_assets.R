#!/usr/bin/env Rscript

# Build publication-ready tables and figures for the diagnostic report on
# selected public cues, individual SDiD estimates, and pooled latent-factor
# models. This script only reads completed diagnostic outputs. It does not
# re-estimate a model, call targets::tar_make(), or write to `_targets/`.

options(scipen = 999)

report_locale <- suppressWarnings(Sys.setlocale("LC_CTYPE", "pt_BR.UTF-8"))
if (!nzchar(report_locale)) {
  warning("Could not set LC_CTYPE to pt_BR.UTF-8; UTF-8 labels may degrade.")
}

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(tibble)
})

required_packages <- c("digest", "jsonlite")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    "Missing required package(s): ", paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

analysis_dir <- file.path(
  "data", "processed", "diagnostics", "selected_public_cue_sdid_fect"
)
assets_dir <- file.path(
  "quality_reports", "selected_public_cue_sdid_fect", "report_assets"
)
dir.create(assets_dir, recursive = TRUE, showWarnings = FALSE)

input_files <- c(
  "sdid_results.csv",
  "fect_results.csv",
  "fect_treatment_audit.csv",
  "fect_model_sample_audit.csv",
  "cue_year_validation.csv",
  "input_target_metadata.csv",
  "run_manifest.json",
  "output_manifest.csv",
  paste0("australia_sdid_", 2006:2008, "_point.csv")
)
missing_inputs <- input_files[
  !file.exists(file.path(analysis_dir, input_files))
]
if (length(missing_inputs) > 0L) {
  stop(
    "Missing completed diagnostic output(s): ",
    paste(missing_inputs, collapse = ", "),
    call. = FALSE
  )
}

sdid_results <- readr::read_csv(
  file.path(analysis_dir, "sdid_results.csv"),
  show_col_types = FALSE
)
fect_results <- readr::read_csv(
  file.path(analysis_dir, "fect_results.csv"),
  show_col_types = FALSE
)
treatment_audit <- readr::read_csv(
  file.path(analysis_dir, "fect_treatment_audit.csv"),
  show_col_types = FALSE
)
sample_audit <- readr::read_csv(
  file.path(analysis_dir, "fect_model_sample_audit.csv"),
  show_col_types = FALSE
)
cue_validation <- readr::read_csv(
  file.path(analysis_dir, "cue_year_validation.csv"),
  show_col_types = FALSE
)
target_metadata <- readr::read_csv(
  file.path(analysis_dir, "input_target_metadata.csv"),
  show_col_types = FALSE
)
run_manifest <- jsonlite::read_json(
  file.path(analysis_dir, "run_manifest.json"),
  simplifyVector = TRUE
)

expected_models <- c(
  "clean_controls",
  "full_switching",
  "clean_controls_without_gab_qat",
  "full_switching_without_gab_qat"
)
expected_treated <- c(5L, 5L, 4L, 4L)
if (!identical(fect_results$model_id, expected_models) ||
    !identical(as.integer(fect_results$n_treated_units), expected_treated) ||
    any(!fect_results$target_estimand) ||
    nrow(sdid_results) != 6L ||
    any(!cue_validation$matches_recorded_entry)) {
  stop("Completed outputs do not match the expected report design.", call. = FALSE)
}

dropped_units <- sample_audit |>
  dplyr::filter(!included_by_fect)
if (nrow(dropped_units) != 2L ||
    any(dropped_units$iso3c != "MNG") ||
    any(dropped_units$treated_periods != 0L) ||
    any(dropped_units$observed_model_periods != 0L)) {
  stop("Unexpected unit exclusion in the switching-control fits.", call. = FALSE)
}

fmt_num <- function(x, digits = 4L) {
  formatC(x, digits = digits, format = "f", decimal.mark = ",")
}

fmt_p <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "NA",
    x < 0.001 ~ "< 0,001",
    TRUE ~ fmt_num(x, 3L)
  )
}

fmt_axis <- function(x) {
  formatC(x, digits = 2L, format = "f", decimal.mark = ",")
}

country_pt <- c(
  Australia = "Austrália",
  Brazil = "Brasil",
  Chile = "Chile",
  Gabon = "Gabão",
  Qatar = "Catar",
  Uruguay = "Uruguai"
)

model_labels <- c(
  clean_controls = "Cinco casos + controles limpos",
  full_switching = "Cinco casos + controles que entram/saem",
  clean_controls_without_gab_qat =
    "Austrália, Brasil, Chile e Uruguai + controles limpos",
  full_switching_without_gab_qat =
    "Austrália, Brasil, Chile e Uruguai + controles que entram/saem"
)

focal_labels <- c(
  clean_controls = "AUS, CHL, GAB, QAT, URY",
  full_switching = "AUS, CHL, GAB, QAT, URY",
  clean_controls_without_gab_qat = "AUS, BRA, CHL, URY",
  full_switching_without_gab_qat = "AUS, BRA, CHL, URY"
)

comparison_labels <- c(
  clean_controls = "105 países nunca China-top",
  full_switching = "Controles entram/saem conforme status China-top",
  clean_controls_without_gab_qat = "105 países nunca China-top",
  full_switching_without_gab_qat =
    "Controles entram/saem conforme status China-top"
)

ife_table <- fect_results |>
  dplyr::mutate(
    model_order = match(model_id, expected_models),
    specification = unname(model_labels[model_id]),
    focal_cases = unname(focal_labels[model_id]),
    comparison_rule = unname(comparison_labels[model_id])
  ) |>
  dplyr::arrange(model_order) |>
  dplyr::transmute(
    specification = specification,
    focal_cases = focal_cases,
    att = fmt_num(estimate),
    bootstrap_se = fmt_num(se_bootstrap),
    ci_95 = paste0(
      "[", fmt_num(ci_95_low), "; ", fmt_num(ci_95_high), "]"
    ),
    p_value = fmt_p(p_normal_two_sided),
    factors = as.integer(selected_factors),
    treated_controls = paste0(
      n_treated_units, "/", n_never_treated_units
    ),
    switching_controls = as.integer(switching_control_units),
    masked_country_years = as.integer(masked_nonfocal_country_years)
  )
names(ife_table) <- c(
  "Especificação", "Casos focais", "ATT", "EP bootstrap", "IC 95%",
  "p-valor", "Fatores (r)", "N tratados/controles",
  "Controles que alternam", "País-anos mascarados"
)
readr::write_csv(ife_table, file.path(assets_dir, "table_1_ife_results.csv"))

sdid_table <- sdid_results |>
  dplyr::mutate(
    country_pt = unname(country_pt[country_name]),
    timing = dplyr::case_when(
      fit_id == "aus_cue_2009" ~ "Cue público em 2009",
      fit_id == "aus_top1_2010" ~ "Timing alternativo em 2010",
      TRUE ~ paste0("Cue público em ", treatment_year)
    )
  ) |>
  dplyr::transmute(
    country = country_pt,
    timing = timing,
    att = fmt_num(estimate),
    placebo_se = fmt_num(se_placebo),
    ci_95 = paste0(
      "[", fmt_num(ci_95_low), "; ", fmt_num(ci_95_high), "]"
    ),
    p_value = fmt_p(p_normal_two_sided),
    pre_post = paste0(n_pre_years, "/", n_post_years),
    donors = as.integer(n_donors)
  )
names(sdid_table) <- c(
  "País", "Timing", "ATT", "EP placebo", "IC 95%", "p-valor",
  "Pré/Pós", "Doadores"
)
readr::write_csv(sdid_table, file.path(assets_dir, "table_2_sdid_results.csv"))

sdid_fit_table <- sdid_results |>
  dplyr::mutate(
    country_pt = unname(country_pt[country_name]),
    timing = dplyr::case_when(
      fit_id == "aus_cue_2009" ~ "Austrália, 2009",
      fit_id == "aus_top1_2010" ~ "Austrália, 2010",
      TRUE ~ paste0(country_pt, ", ", treatment_year)
    )
  ) |>
  dplyr::transmute(
    Ajuste = timing,
    `RMSPE pré` = fmt_num(rmspe_pre_level_adjusted),
    `RMSPE pós` = fmt_num(rmspe_post_level_adjusted),
    `Razão pós/pré` = fmt_num(rmspe_ratio, 3L),
    `Anos pré` = as.integer(n_pre_years),
    `Anos pós` = as.integer(n_post_years)
  )
readr::write_csv(
  sdid_fit_table,
  file.path(assets_dir, "table_3_sdid_fit_diagnostics.csv")
)

focal_timing_table <- treatment_audit |>
  dplyr::filter(
    model_id %in% c(
      "clean_controls",
      "clean_controls_without_gab_qat"
    ),
    focal_country
  ) |>
  dplyr::mutate(
    scope = dplyr::if_else(
      model_id == "clean_controls",
      "Cinco casos",
      "Quatro casos sem Gabão/Catar, com Brasil"
    ),
    country_pt = unname(country_pt[country_name])
  ) |>
  dplyr::transmute(
    scope = scope,
    country = country_pt,
    cue_year = as.integer(public_cue_year),
    first_treated_year = as.integer(first_treated_year),
    last_treated_year = as.integer(last_treated_year),
    treated_periods = as.integer(treated_years),
    entries = as.integer(entries),
    exits = as.integer(exits),
    china_top_before_cue = as.integer(china_top_years_before_cue)
  ) |>
  dplyr::arrange(scope, cue_year, country)
names(focal_timing_table) <- c(
  "Escopo", "País", "Ano do cue", "Primeiro ano tratado",
  "Último ano tratado", "Períodos tratados", "Entradas", "Saídas",
  "Anos China-top antes do cue"
)
readr::write_csv(
  focal_timing_table,
  file.path(assets_dir, "table_4_focal_timing.csv")
)

script_paths <- c(
  "scripts/diagnostics/estimate_selected_public_cue_sdid_fect.R",
  "scripts/diagnostics/sdid_placebo_helpers.R",
  "scripts/diagnostics/build_selected_public_cue_report_assets.R",
  "reports/selected_public_cue_sdid_fect/relatorio_sdid_fatores_latentes.Rmd",
  "scripts/diagnostics/estimate_australia_sdid_2007_point.R",
  "scripts/diagnostics/plot_australia_sdid_2006_native.R"
)
script_roles <- c(
  "Estima os seis SDiD e os quatro modelos IFE; grava auditorias e manifests.",
  "Implementa os placebos SDiD determinísticos e checkpointados.",
  "Prepara as tabelas, figuras e metadados deste relatório; não reestima modelos.",
  "Importa os assets e apresenta método, resultados, limitações e proveniência.",
  "Estima o SDiD pontual australiano para o ano indicado, sem inferência.",
  "Exporta o gráfico nativo de cada ajuste australiano salvo, sem inferência."
)
script_table <- tibble::tibble(
  Script = script_paths,
  role = script_roles,
  sha256 = vapply(
    script_paths,
    function(path) {
      if (file.exists(path)) {
        digest::digest(path, algo = "sha256", file = TRUE)
      } else {
        "pending-at-asset-build"
      }
    },
    character(1)
  )
)
names(script_table) <- c("Script", "Função", "SHA-256")
readr::write_csv(
  script_table,
  file.path(assets_dir, "table_5_scripts.csv")
)

ife_plot_data <- fect_results |>
  dplyr::mutate(
    plot_label = dplyr::recode(
      model_id,
      clean_controls = "Cinco casos\ncontroles limpos",
      full_switching = "Cinco casos\ncontroles entram/saem",
      clean_controls_without_gab_qat =
        "AUS, BRA, CHL, URY\ncontroles limpos",
      full_switching_without_gab_qat =
        "AUS, BRA, CHL, URY\ncontroles entram/saem"
    ),
    comparison_design = dplyr::if_else(
      startsWith(model_id, "clean_controls"),
      "Controles limpos",
      "Controles entram/saem"
    ),
    plot_order = match(model_id, expected_models),
    plot_label = factor(
      plot_label,
      levels = rev(plot_label[order(plot_order)])
    )
  )

ife_plot <- ggplot2::ggplot(
  ife_plot_data,
  ggplot2::aes(
    x = plot_label,
    y = estimate,
    color = comparison_design
  )
) +
  ggplot2::geom_hline(
    yintercept = 0,
    linewidth = 0.45,
    linetype = "dashed",
    color = "#666666"
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_95_low, ymax = ci_95_high),
    width = 0.14,
    linewidth = 0.75
  ) +
  ggplot2::geom_point(size = 3.0) +
  ggplot2::coord_flip() +
  ggplot2::scale_color_manual(
    values = c(
      "Controles limpos" = "#17365D",
      "Controles entram/saem" = "#007C91"
    )
  ) +
  ggplot2::scale_y_continuous(
    breaks = seq(-0.3, 0.15, by = 0.05),
    labels = fmt_axis,
    expand = ggplot2::expansion(mult = c(0.04, 0.05))
  ) +
  ggplot2::labs(
    x = NULL,
    y = "ATT sobre a distância ideal à China",
    color = "Controles"
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_text(color = "#252525"),
    legend.position = "bottom",
    plot.margin = ggplot2::margin(8, 12, 8, 8)
  )

ggplot2::ggsave(
  file.path(assets_dir, "figure_1_ife_estimates.png"),
  ife_plot,
  width = 8.1,
  height = 4.6,
  dpi = 320,
  bg = "white"
)
ggplot2::ggsave(
  file.path(assets_dir, "figure_1_ife_estimates.pdf"),
  ife_plot,
  width = 8.1,
  height = 4.6,
  device = "pdf"
)

sdid_plot_order <- c(
  "chl_cue_2008",
  "ury_cue_2013",
  "gab_cue_2017",
  "qat_cue_2021",
  "aus_cue_2009",
  "aus_top1_2010"
)
sdid_plot_data <- sdid_results |>
  dplyr::mutate(
    plot_label = dplyr::recode(
      fit_id,
      chl_cue_2008 = "Chile - cue 2008",
      ury_cue_2013 = "Uruguai - cue 2013",
      gab_cue_2017 = "Gabão - cue 2017",
      qat_cue_2021 = "Catar - cue 2021",
      aus_cue_2009 = "Austrália - cue 2009",
      aus_top1_2010 = "Austrália - timing 2010"
    ),
    timing_type = dplyr::if_else(
      fit_id == "aus_top1_2010",
      "Timing alternativo",
      "Cue público"
    ),
    plot_order = match(fit_id, sdid_plot_order),
    plot_label = factor(
      plot_label,
      levels = rev(plot_label[order(plot_order)])
    )
  )

sdid_plot <- ggplot2::ggplot(
  sdid_plot_data,
  ggplot2::aes(x = plot_label, y = estimate, color = timing_type)
) +
  ggplot2::geom_hline(
    yintercept = 0,
    linewidth = 0.45,
    linetype = "dashed",
    color = "#666666"
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_95_low, ymax = ci_95_high),
    width = 0.14,
    linewidth = 0.75
  ) +
  ggplot2::geom_point(size = 2.9) +
  ggplot2::coord_flip() +
  ggplot2::scale_color_manual(
    values = c(
      "Cue público" = "#17365D",
      "Timing alternativo" = "#B24C3B"
    )
  ) +
  ggplot2::scale_y_continuous(
    breaks = seq(-0.5, 0.4, by = 0.1),
    labels = fmt_axis,
    expand = ggplot2::expansion(mult = c(0.04, 0.05))
  ) +
  ggplot2::labs(
    x = NULL,
    y = "ATT sobre a distância ideal à China",
    color = "Timing"
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_text(color = "#252525"),
    legend.position = "bottom",
    plot.margin = ggplot2::margin(8, 12, 8, 8)
  )

ggplot2::ggsave(
  file.path(assets_dir, "figure_2_sdid_estimates.png"),
  sdid_plot,
  width = 8.1,
  height = 5.1,
  dpi = 320,
  bg = "white"
)
ggplot2::ggsave(
  file.path(assets_dir, "figure_2_sdid_estimates.pdf"),
  sdid_plot,
  width = 8.1,
  height = 5.1,
  device = "pdf"
)

report_numbers <- list(
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  year_start = run_manifest$year_start,
  year_end = run_manifest$year_end,
  outcome = "Distância absoluta do ponto ideal na AGNU em relação à China",
  clean_donor_count = run_manifest$clean_donor_count,
  complete_panel_unit_count = run_manifest$complete_panel_unit_count,
  placebo_replications = run_manifest$placebo_replications,
  placebo_seed = run_manifest$placebo_seed,
  fect_bootstraps = run_manifest$fect_bootstraps,
  fect_seed = run_manifest$fect_seed,
  fect_min_untreated_periods = run_manifest$fect_min_untreated_periods,
  target_name = target_metadata$name[[1L]],
  target_hash = target_metadata$data[[1L]],
  target_time = target_metadata$time[[1L]],
  fect = split(fect_results, fect_results$model_id),
  sdid = split(sdid_results, sdid_results$fit_id),
  dropped_nonfocal_unit = unique(dropped_units$iso3c),
  dropped_nonfocal_unit_name = unique(dropped_units$country_name)
)
saveRDS(report_numbers, file.path(assets_dir, "report_numbers.rds"))

asset_files <- c(
  "table_1_ife_results.csv",
  "table_2_sdid_results.csv",
  "table_3_sdid_fit_diagnostics.csv",
  "table_4_focal_timing.csv",
  "table_5_scripts.csv",
  "figure_1_ife_estimates.png",
  "figure_1_ife_estimates.pdf",
  "figure_2_sdid_estimates.png",
  "figure_2_sdid_estimates.pdf",
  "report_numbers.rds"
)
asset_manifest <- tibble::tibble(
  file = asset_files,
  bytes = file.info(file.path(assets_dir, asset_files))$size,
  sha256 = vapply(
    file.path(assets_dir, asset_files),
    digest::digest,
    character(1),
    algo = "sha256",
    file = TRUE
  )
)
readr::write_csv(
  asset_manifest,
  file.path(assets_dir, "report_asset_manifest.csv")
)

source_paths <- c(
  file.path(analysis_dir, input_files),
  file.path(
    "quality_reports", "selected_public_cue_sdid_fect", "figures",
    paste0("australia_sdid_", 2006:2008, "_native.pdf")
  )
)
stopifnot(all(file.exists(source_paths)))
source_manifest <- tibble::tibble(
  file = source_paths,
  bytes = file.info(source_paths)$size,
  sha256 = vapply(
    source_paths,
    digest::digest,
    character(1),
    algo = "sha256",
    file = TRUE
  )
)
readr::write_csv(
  source_manifest,
  file.path(assets_dir, "report_source_manifest.csv")
)

message("Report assets written to: ", assets_dir)
