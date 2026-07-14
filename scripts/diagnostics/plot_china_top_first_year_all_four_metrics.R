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
    original_itpde_exports_no_sector_filter =
      "M1. Original do pipeline:\nexportações ITPD-E\nsem filtro setorial",
    goods_exports_rank = "M2. Recalculado:\nbens, exportações\nITPD-E goods-only",
    goods_services_exports_rank = "M3. Recalculado:\nbens + serviços,\nexportações",
    goods_services_two_way_rank = "M4. Recalculado:\nbens + serviços,\ntwo-way",
    .default = metric
  )
}

metric_id <- function(metric) {
  dplyr::recode(
    metric,
    original_itpde_exports_no_sector_filter = "M1",
    goods_exports_rank = "M2",
    goods_services_exports_rank = "M3",
    goods_services_two_way_rank = "M4",
    .default = metric
  )
}

metric_definition <- function(metric) {
  dplyr::recode(
    metric,
    original_itpde_exports_no_sector_filter =
      "Métrica original do pipeline: soma ITPD-E trade por país-parceiro-ano sem filtrar broad_sector; portanto não é estritamente goods-only.",
    goods_exports_rank =
      "Reconstrução: exportações de bens no ITPD-E, filtrando broad_sector para Agriculture, Mining and Energy, and Manufacturing; janela 2005-2022.",
    goods_services_exports_rank =
      "Reconstrução: exportações de bens do ITPD-E mais exportações de serviços do BaTIS BPM6.",
    goods_services_two_way_rank =
      "Reconstrução: exportações e importações de bens e serviços, ITPD-E mais BaTIS BPM6.",
    .default = metric
  )
}

status_label <- function(status) {
  dplyr::recode(
    status,
    observed_entry = "Entrada observada",
    left_censored_first_observed = "Censurado à esquerda no primeiro ano observado",
    left_censored_2005 = "Censurado à esquerda em 2005",
    missing_2005 = "Primeiro #1 observado com 2005 ausente",
    never_observed = "Nunca observado #1",
    .default = status
  )
}

formulation_levels <- c(
  metric_label("original_itpde_exports_no_sector_filter"),
  metric_label("goods_exports_rank"),
  metric_label("goods_services_exports_rank"),
  metric_label("goods_services_two_way_rank")
)

status_levels <- c(
  "Entrada observada",
  "Censurado à esquerda no primeiro ano observado",
  "Censurado à esquerda em 2005",
  "Primeiro #1 observado com 2005 ausente",
  "Nunca observado #1"
)

alt_status_file <- dated_file(
  processed_dir,
  paste0("alternative_cross_country_status_by_country_", run_date, ".csv")
)

message("Reading raw original panel and alternative metric status.")
original_panel <- read_target_object("china_top_panel") |>
  tibble::as_tibble()

alternative_status <- readr::read_csv(alt_status_file, show_col_types = FALSE)

original_first_year <- original_panel |>
  dplyr::filter(!is.na(iso3c), iso3c != "CHN") |>
  dplyr::mutate(
    china_rank1_observed = dplyr::coalesce(china_is_top, FALSE),
    trade_observed = !is.na(top_partner)
  ) |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    first_observed_year = {
      value <- year[trade_observed]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    first_china_rank1_year = {
      value <- year[china_rank1_observed]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    status = dplyr::case_when(
      is.na(first_china_rank1_year) ~ "never_observed",
      !is.na(first_observed_year) &
        first_china_rank1_year == first_observed_year ~ "left_censored_first_observed",
      TRUE ~ "observed_entry"
    ),
    source_window = "1990-2023 no painel bruto original",
    .groups = "drop"
  ) |>
  dplyr::mutate(
    metric = "original_itpde_exports_no_sector_filter",
    metric_id = metric_id(metric),
    metric_definition = metric_definition(metric),
    formulation_label = metric_label(metric)
  ) |>
  dplyr::select(
    metric_id, metric, formulation_label, metric_definition, iso3c,
    country_name, first_china_rank1_year, status, source_window
  )

alternative_first_year <- alternative_status |>
  dplyr::filter(
    metric %in% c(
      "goods_exports_rank",
      "goods_services_exports_rank",
      "goods_services_two_way_rank"
    )
  ) |>
  dplyr::mutate(
    first_china_rank1_year = as.integer(first_china_top_year),
    status = dplyr::case_when(
      !ever_china_top ~ "never_observed",
      censoring_status == "left_censored_china_rank1_in_2005" ~ "left_censored_2005",
      censoring_status == "missing_rank_in_2005" ~ "missing_2005",
      TRUE ~ "observed_entry"
    ),
    source_window = dplyr::case_when(
      metric == "goods_exports_rank" ~
        "2005-2022 na reconstrução ITPD-E com filtro de bens",
      TRUE ~ "2005-2022 na reconstrução ITPD-E/BaTIS"
    ),
    metric_id = metric_id(metric),
    metric_definition = metric_definition(metric),
    formulation_label = metric_label(metric)
  ) |>
  dplyr::select(
    metric_id, metric, formulation_label, metric_definition, iso3c,
    country_name, first_china_rank1_year, status, source_window
  )

first_year_long <- dplyr::bind_rows(original_first_year, alternative_first_year) |>
  dplyr::mutate(
    formulation_label = factor(formulation_label, levels = formulation_levels),
    status_label = factor(status_label(status), levels = status_levels),
    country_name_plot = gsub("\u2019", "'", country_name, fixed = TRUE),
    year_label = dplyr::case_when(
      is.na(first_china_rank1_year) ~ "Nunca",
      status %in% c("left_censored_first_observed", "left_censored_2005") ~
        paste0(first_china_rank1_year, "*"),
      status == "missing_2005" ~ paste0(first_china_rank1_year, "+"),
      TRUE ~ as.character(first_china_rank1_year)
    ),
    country_label = paste0(country_name_plot, " (", iso3c, ")")
  )

countries_to_plot <- first_year_long |>
  dplyr::group_by(iso3c, country_label) |>
  dplyr::summarise(
    any_china_rank1 = any(!is.na(first_china_rank1_year)),
    earliest_rank1 = {
      value <- first_china_rank1_year[!is.na(first_china_rank1_year)]
      if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
    },
    original_rank1 = {
      value <- first_china_rank1_year[
        metric == "original_itpde_exports_no_sector_filter"
      ]
      if (length(value) == 0L || all(is.na(value))) NA_integer_ else min(value, na.rm = TRUE)
    },
    .groups = "drop"
  ) |>
  dplyr::filter(any_china_rank1) |>
  dplyr::arrange(earliest_rank1, original_rank1, country_label)

plot_data <- first_year_long |>
  dplyr::filter(iso3c %in% countries_to_plot$iso3c) |>
  dplyr::mutate(
    country_label = factor(country_label, levels = rev(countries_to_plot$country_label)),
    year_for_fill = first_china_rank1_year
  )

first_year_wide <- first_year_long |>
  dplyr::filter(iso3c %in% countries_to_plot$iso3c) |>
  dplyr::select(iso3c, country_name, metric_id, year_label) |>
  tidyr::pivot_wider(
    names_from = metric_id,
    values_from = year_label,
    values_fn = list(year_label = dplyr::first)
  ) |>
  dplyr::arrange(country_name)

metric_dictionary <- first_year_long |>
  dplyr::distinct(
    metric_id, metric, formulation_label, metric_definition, source_window
  ) |>
  dplyr::arrange(metric_id)

long_file <- file.path(
  processed_dir,
  paste0("china_top_first_year_all_four_metrics_long_", run_date, ".csv")
)
wide_file <- file.path(
  processed_dir,
  paste0("china_top_first_year_all_four_metrics_wide_", run_date, ".csv")
)
session_file <- file.path(
  processed_dir,
  paste0("china_top_first_year_all_four_metrics_session_info_", run_date, ".txt")
)
metric_dictionary_file <- file.path(
  processed_dir,
  paste0("china_top_first_year_all_four_metrics_dictionary_", run_date, ".csv")
)
pdf_file <- file.path(
  figure_dir,
  paste0("figura_4_primeiro_ano_china_top1_quatro_metricas_", run_date, ".pdf")
)
png_file <- file.path(
  figure_dir,
  paste0("figura_4_primeiro_ano_china_top1_quatro_metricas_", run_date, ".png")
)

readr::write_csv(first_year_long, long_file, na = "")
readr::write_csv(first_year_wide, wide_file, na = "")
readr::write_csv(metric_dictionary, metric_dictionary_file, na = "")
writeLines(capture.output(sessionInfo()), session_file)

caption_text <- paste(
  strwrap(
    paste(
      "Notas: cada célula mostra o primeiro ano observado em que a China aparece como parceiro #1 naquela métrica.",
      "A coluna original usa o painel bruto do pipeline e não filtra setor no ITPD-E; M2 usa ITPD-E com filtro de bens; M3 e M4 acrescentam serviços BaTIS BPM6.",
      "Asterisco indica censura à esquerda no primeiro ano observado: no painel bruto original, pode ser o primeiro ano disponível para o país; nas reconstruções pós-2005, é 2005.",
      "O sinal + indica que 2005 está ausente para aquela métrica e país, de modo que o primeiro ano observado não deve ser interpretado como entrada causal limpa.",
      "`Nunca` significa que a China não foi observada como #1 naquela métrica dentro da janela da fonte, não uma afirmação sobre anos fora da janela."
    ),
    width = 155
  ),
  collapse = "\n"
)

fill_limits <- range(plot_data$year_for_fill, na.rm = TRUE)

timing_plot <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(x = formulation_label, y = country_label)
) +
  ggplot2::geom_tile(
    ggplot2::aes(fill = year_for_fill),
    color = "white",
    linewidth = 0.25,
    width = 0.96,
    height = 0.9
  ) +
  ggplot2::geom_text(
    ggplot2::aes(label = year_label),
    size = 2.15,
    lineheight = 0.9,
    color = "grey10"
  ) +
  ggplot2::scale_fill_gradientn(
    colours = c("#d8f3dc", "#74c69d", "#1d79a8", "#fdae61", "#d7301f"),
    na.value = "grey92",
    limits = fill_limits,
    guide = "none"
  ) +
  ggplot2::scale_x_discrete(position = "top") +
  ggplot2::labs(
    title = "Figura 4. Primeiro ano em que a China aparece como parceiro #1",
    subtitle = "Comparação do pipeline original sem filtro setorial com três reconstruções alternativas",
    x = NULL,
    y = NULL,
    caption = caption_text
  ) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 12),
    plot.subtitle = ggplot2::element_text(size = 10),
    plot.caption = ggplot2::element_text(size = 7, hjust = 0, lineheight = 1.08),
    axis.text.x = ggplot2::element_text(face = "bold", size = 8),
    axis.text.x.top = ggplot2::element_text(
      face = "bold",
      size = 8,
      margin = ggplot2::margin(b = 4)
    ),
    axis.text.y = ggplot2::element_text(size = 5.7),
    panel.grid = ggplot2::element_blank(),
    legend.position = "bottom",
    plot.margin = ggplot2::margin(8, 12, 12, 8)
  )

plot_height <- max(12, min(36, 2.8 + length(unique(plot_data$country_label)) * 0.17))
plot_width <- 11

message("Rendering PDF: ", pdf_file)
grDevices::pdf(
  pdf_file,
  width = plot_width,
  height = plot_height,
  onefile = TRUE,
  useDingbats = FALSE,
  encoding = "ISOLatin1.enc"
)
print(timing_plot)
invisible(grDevices::dev.off())

message("Rendering PNG: ", png_file)
ggplot2::ggsave(
  filename = png_file,
  plot = timing_plot,
  width = plot_width,
  height = plot_height,
  units = "in",
  dpi = 220,
  device = "png",
  bg = "white",
  limitsize = FALSE
)

if (!file.exists(pdf_file)) {
  stop("PDF rendering failed: ", pdf_file, call. = FALSE)
}
if (!file.exists(png_file)) {
  stop("PNG rendering failed: ", png_file, call. = FALSE)
}

manifest <- tibble::tibble(
  artifact = c("long_csv", "wide_csv", "metric_dictionary", "session_info", "pdf", "png"),
  path = c(
    long_file, wide_file, metric_dictionary_file, session_file, pdf_file, png_file
  ),
  exists = file.exists(c(
    long_file, wide_file, metric_dictionary_file, session_file, pdf_file, png_file
  )),
  run_date = as.character(run_date),
  n_rows_long = c(
    nrow(first_year_long), NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_
  ),
  n_rows_wide = c(
    NA_integer_, nrow(first_year_wide), NA_integer_, NA_integer_, NA_integer_, NA_integer_
  )
)

manifest_file <- file.path(
  processed_dir,
  paste0("china_top_first_year_all_four_metrics_manifest_", run_date, ".csv")
)
readr::write_csv(manifest, manifest_file, na = "")

message("Done.")
message("PDF: ", pdf_file)
message("PNG: ", png_file)
message("Long CSV: ", long_file)
message("Wide CSV: ", wide_file)
message("Metric dictionary CSV: ", metric_dictionary_file)
