#!/usr/bin/env Rscript

# Diagnostic only. This script reads existing target objects read-only and
# already-produced diagnostic CSVs. It does not modify or run the targets
# pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(tibble)
  library(tidyr)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

run_date <- as.Date("2026-05-20")

processed_dir <- file.path(
  "data", "processed", "diagnostics", "china_top_alternative_cross_country"
)
report_dir <- file.path("quality_reports", "china_top_alternative_cross_country")
figure_dir <- file.path(report_dir, "figures")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

read_target_object <- function(name) {
  path <- file.path("_targets", "objects", name)
  if (!file.exists(path)) {
    stop("Required read-only targets object not found: ", path, call. = FALSE)
  }
  readRDS(path)
}

dated_file <- function(dir, filename) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) {
    stop("Required dated input file not found: ", path, call. = FALSE)
  }
  path
}

metric_label <- function(metric) {
  dplyr::recode(
    metric,
    goods_exports_rank = "Recalculado: bens\nexportações\nentrada observada",
    goods_services_exports_rank = "Recalculado: bens + serviços\nexportações\nentrada observada",
    goods_services_two_way_rank = "Recalculado: bens + serviços\ntwo-way\nentrada observada",
    .default = metric
  )
}

rule_label <- function(rule) {
  dplyr::recode(
    rule,
    clean_risk_set = "Clean risk set: exclui países já China #1 em 2005",
    left_censored_as_already_treated =
      "Censurados à esquerda como já tratados desde 2005 (descritivo)",
    cutoff_not_top_through_2010 =
      "Sensibilidade: países não China #1 em nenhum ano de 2005 a 2010",
    .default = rule
  )
}

page_label <- function(rule) {
  dplyr::recode(
    rule,
    clean_risk_set = "Figura 3A",
    left_censored_as_already_treated = "Figura 3B",
    cutoff_not_top_through_2010 = "Figura 3C",
    .default = "Figura 3"
  )
}

onset_label <- function(year, timing_status) {
  dplyr::case_when(
    is.na(year) ~ NA_character_,
    timing_status == "Censurado à esquerda em 2005" ~ paste0(year, " (cens.)"),
    TRUE ~ as.character(year)
  )
}

formulation_levels <- c(
  "Paper: amostra estimada\nbens exportações\nabsorvente",
  "Recalculado: bens\nexportações\nentrada observada",
  "Recalculado: bens + serviços\nexportações\nentrada observada",
  "Recalculado: bens + serviços\ntwo-way\nentrada observada"
)

rules_to_plot <- c(
  "clean_risk_set",
  "left_censored_as_already_treated",
  "cutoff_not_top_through_2010"
)

status_levels <- c(
  "Entrada observada",
  "Censurado à esquerda em 2005"
)

alt_panel_file <- dated_file(
  processed_dir,
  paste0("alternative_cross_country_model_panel_", run_date, ".csv")
)

message("Reading treatment panels.")
original_panel <- read_target_object("china_top_fect_cov_data") |>
  tibble::as_tibble()

alt_panel <- readr::read_csv(alt_panel_file, show_col_types = FALSE)

original_onsets <- original_panel |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    onset_year = {
      value <- year[china_top == 1]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    .groups = "drop"
  ) |>
  dplyr::filter(!is.na(onset_year)) |>
  tidyr::expand_grid(rule = rules_to_plot) |>
  dplyr::mutate(
    formulation = "original_main_covariate_model",
    formulation_label = formulation_levels[[1]],
    timing_status = "Entrada observada",
    sample_scope = "Amostra estimável original 1990-2020; tratamento absorvente do paper",
    source = "Target object: china_top_fect_cov_data",
    rule_label = rule_label(rule)
  ) |>
  dplyr::select(
    rule, rule_label, formulation, formulation_label, iso3c, country_name,
    onset_year, timing_status, sample_scope, source
  )

alternative_onsets <- alt_panel |>
  dplyr::filter(rule %in% rules_to_plot) |>
  dplyr::group_by(rule, metric, iso3c, country_name, censoring_status) |>
  dplyr::summarise(
    onset_year = {
      value <- year[china_top == 1]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    .groups = "drop"
  ) |>
  dplyr::filter(!is.na(onset_year)) |>
  dplyr::mutate(
    formulation = metric,
    formulation_label = metric_label(metric),
    timing_status = dplyr::if_else(
      censoring_status == "left_censored_china_rank1_in_2005" &
        onset_year == 2005L,
      "Censurado à esquerda em 2005",
      "Entrada observada"
    ),
    sample_scope =
      "Painel ITPD-E/BaTIS filtrado pela regra; entrada observada sem exigir absorção",
    source = "CSV: alternative_cross_country_model_panel",
    rule_label = rule_label(rule)
  ) |>
  dplyr::select(
    rule, rule_label, formulation, formulation_label, iso3c, country_name,
    onset_year, timing_status, sample_scope, source
  )

timing_long <- dplyr::bind_rows(original_onsets, alternative_onsets) |>
  dplyr::mutate(
    formulation_label = factor(formulation_label, levels = formulation_levels),
    timing_status = factor(timing_status, levels = status_levels),
    country_label = paste0(country_name, " (", iso3c, ")"),
    onset_label = onset_label(onset_year, as.character(timing_status))
  ) |>
  dplyr::arrange(rule, onset_year, country_name, formulation_label)

timing_wide <- timing_long |>
  dplyr::select(
    rule, rule_label, iso3c, country_name, formulation_label, onset_label
  ) |>
  tidyr::pivot_wider(
    names_from = formulation_label,
    values_from = onset_label,
    values_fn = list(onset_label = dplyr::first)
  ) |>
  dplyr::arrange(rule, country_name)

long_file <- file.path(
  processed_dir,
  paste0("china_top_treatment_timing_long_", run_date, ".csv")
)
wide_file <- file.path(
  processed_dir,
  paste0("china_top_treatment_timing_wide_", run_date, ".csv")
)
session_file <- file.path(
  processed_dir,
  paste0("china_top_treatment_timing_session_info_", run_date, ".txt")
)
pdf_file <- file.path(
  figure_dir,
  paste0("figura_3_tratamento_por_pais_original_vs_alternativas_", run_date, ".pdf")
)

readr::write_csv(timing_long, long_file, na = "")
readr::write_csv(timing_wide, wide_file, na = "")
writeLines(capture.output(sessionInfo()), session_file)

make_timing_plot <- function(rule_id) {
  plot_data <- timing_long |>
    dplyr::filter(rule == rule_id)

  country_order <- plot_data |>
    dplyr::group_by(country_label) |>
    dplyr::summarise(
      earliest_onset = min(onset_year, na.rm = TRUE),
      original_onset = suppressWarnings(
        min(onset_year[formulation == "original_main_covariate_model"], na.rm = TRUE)
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      original_onset = dplyr::if_else(is.infinite(original_onset), NA_real_, original_onset)
    ) |>
    dplyr::arrange(earliest_onset, original_onset, country_label)

  plot_data <- plot_data |>
    dplyr::mutate(
      country_label = factor(country_label, levels = rev(country_order$country_label))
    )

  caption_text <- paste(
    strwrap(
      paste(
        "Notas: cada ponto é o primeiro ano tratado naquela formulação e regra de amostra.",
        "A regra de amostra indicada no subtítulo vale para os painéis recalculados.",
        "O painel do paper mostra apenas a amostra estimável original com tratamento absorvente;",
        "ausência de ponto ali não significa necessariamente que o país nunca tenha tido China #1 no painel bruto.",
        "Países nunca tratados em todas as formulações desta página foram omitidos.",
        "A área cinza marca anos anteriores a 2005, fora da janela BaTIS BPM6.",
        "Triângulos em 2005 indicam países já China #1 no primeiro ano observado pela BaTIS,",
        "não uma entrada limpa pós-2005."
      ),
      width = 165
    ),
    collapse = "\n"
  )

  ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = onset_year,
      y = country_label,
      shape = timing_status,
      color = formulation_label
    )
  ) +
    ggplot2::annotate(
      "rect",
      xmin = -Inf,
      xmax = 2004.5,
      ymin = -Inf,
      ymax = Inf,
      fill = "grey92",
      alpha = 0.7
    ) +
    ggplot2::geom_vline(
      xintercept = 2005,
      linewidth = 0.35,
      linetype = "dashed",
      color = "grey35"
    ) +
    ggplot2::geom_point(size = 2.1, stroke = 0.85, alpha = 0.96) +
    ggplot2::facet_grid(. ~ formulation_label, drop = FALSE) +
    ggplot2::scale_x_continuous(
      breaks = seq(1990, 2022, by = 5),
      minor_breaks = seq(1990, 2022, by = 1),
      limits = c(1990, 2022),
      expand = ggplot2::expansion(mult = c(0.01, 0.02))
    ) +
    ggplot2::scale_shape_manual(
      values = c(
        "Entrada observada" = 16,
        "Censurado à esquerda em 2005" = 17
      ),
      drop = FALSE
    ) +
    ggplot2::scale_color_manual(
      values = c(
        "Paper: amostra estimada\nbens exportações\nabsorvente" = "#1b1b1b",
        "Recalculado: bens\nexportações\nentrada observada" = "#0072B2",
        "Recalculado: bens + serviços\nexportações\nentrada observada" = "#D55E00",
        "Recalculado: bens + serviços\ntwo-way\nentrada observada" = "#009E73"
      ),
      drop = FALSE
    ) +
    ggplot2::labs(
      title = paste0(
        page_label(rule_id),
        ". Ano em que cada país passa a ter a China como parceiro #1"
      ),
      subtitle = paste0(
        unique(plot_data$rule_label),
        " | Paper = amostra estimável absorvente; recalculados = entrada observada"
      ),
      x = "Ano de entrada no tratamento",
      y = NULL,
      shape = NULL,
      color = NULL,
      caption = caption_text
    ) +
    ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 10),
      plot.caption = ggplot2::element_text(size = 7, hjust = 0, lineheight = 1.08),
      axis.text.y = ggplot2::element_text(size = 5.6),
      axis.text.x = ggplot2::element_text(size = 7),
      axis.title.x = ggplot2::element_text(size = 9),
      panel.grid.major.y = ggplot2::element_line(linewidth = 0.16, color = "grey87"),
      panel.grid.minor.x = ggplot2::element_line(linewidth = 0.12, color = "grey91"),
      panel.grid.major.x = ggplot2::element_line(linewidth = 0.2, color = "grey82"),
      strip.text = ggplot2::element_text(face = "bold", size = 8),
      legend.position = "bottom",
      legend.box = "vertical",
      legend.margin = ggplot2::margin(t = 2, r = 0, b = 0, l = 0),
      plot.margin = ggplot2::margin(8, 12, 12, 8)
    )
}

max_countries <- timing_long |>
  dplyr::count(rule, country_label, name = "n_points") |>
  dplyr::count(rule, name = "n_countries") |>
  dplyr::pull(n_countries) |>
  max(na.rm = TRUE)

pdf_height <- max(12, min(36, 2.8 + max_countries * 0.17))
pdf_width <- 15.5

message("Rendering PDF: ", pdf_file)
grDevices::pdf(
  pdf_file,
  width = pdf_width,
  height = pdf_height,
  onefile = TRUE,
  useDingbats = FALSE,
  encoding = "ISOLatin1.enc"
)
for (rule_id in rules_to_plot) {
  print(make_timing_plot(rule_id))
}
invisible(grDevices::dev.off())

if (!file.exists(pdf_file)) {
  stop("PDF rendering failed: ", pdf_file, call. = FALSE)
}

manifest <- tibble::tibble(
  artifact = c("timing_long_csv", "timing_wide_csv", "session_info", "pdf"),
  path = c(long_file, wide_file, session_file, pdf_file),
  exists = file.exists(c(long_file, wide_file, session_file, pdf_file)),
  run_date = as.character(run_date),
  n_rows_long = c(nrow(timing_long), NA_integer_, NA_integer_, NA_integer_),
  n_rows_wide = c(NA_integer_, nrow(timing_wide), NA_integer_, NA_integer_)
)

manifest_file <- file.path(
  processed_dir,
  paste0("china_top_treatment_timing_manifest_", run_date, ".csv")
)
readr::write_csv(manifest, manifest_file, na = "")

message("Done.")
message("PDF: ", pdf_file)
message("Long CSV: ", long_file)
message("Wide CSV: ", wide_file)
