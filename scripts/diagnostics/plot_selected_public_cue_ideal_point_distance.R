#!/usr/bin/env Rscript

# Descriptive figure for selected countries in the public-cue audit.
#
# This script uses materialized CSV inputs only. It does not read or modify the
# targets store and does not estimate a treatment effect. Treatment-entry years
# come from the status-cue audit, so the figure matches the evidence windows on
# which the high-quality coding was based.

invisible(Sys.setlocale("LC_CTYPE", "pt_BR.UTF-8"))

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
})

options(scipen = 999)

codes_path <- "data/processed/status_cue_salience/status_cue_country_codes.csv"
panel_path <- paste0(
  "data/processed/diagnostics/",
  "china_top_m2_goods_full_join_consecutive/final/",
  "m2_goods_full_join_consecutive_2026-08-29_master_panel.csv"
)
out_dir <- "quality_reports/status_cue_salience"
plot_data_path <- file.path(
  "data/processed/status_cue_salience",
  "selected_public_cue_ideal_point_distance_plot_data.csv"
)
png_path <- file.path(
  out_dir,
  "figure_selected_public_cue_ideal_point_distance.png"
)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

selected_iso3c <- c("BRA", "CHL", "GAB", "URY", "QAT", "AUS")

selected_codes <- readr::read_csv(codes_path, show_col_types = FALSE) |>
  dplyr::filter(iso3c %in% selected_iso3c) |>
  dplyr::transmute(
    iso3c,
    country_name,
    cue_audit_entry_year = as.integer(entry_year),
    salience_code
  ) |>
  dplyr::mutate(
    salience_order = match(salience_code, c("high", "medium", "unknown"))
  ) |>
  dplyr::arrange(salience_order, cue_audit_entry_year, country_name) |>
  dplyr::select(-salience_order)

stopifnot(
  nrow(selected_codes) == 6L,
  setequal(selected_codes$iso3c, selected_iso3c),
  !anyDuplicated(selected_codes$iso3c),
  !anyNA(selected_codes$cue_audit_entry_year),
  setequal(
    selected_codes$iso3c[selected_codes$salience_code == "high"],
    c("BRA", "CHL", "GAB", "URY")
  ),
  identical(selected_codes$salience_code[selected_codes$iso3c == "QAT"], "medium"),
  identical(selected_codes$salience_code[selected_codes$iso3c == "AUS"], "unknown")
)

plot_data <- readr::read_csv(panel_path, show_col_types = FALSE) |>
  dplyr::filter(
    iso3c %in% selected_codes$iso3c,
    year >= 2000L,
    !is.na(abs_distance_china)
  ) |>
  dplyr::select(
    iso3c,
    country_name_panel = country_name,
    year,
    abs_distance_china
  ) |>
  dplyr::left_join(selected_codes, by = "iso3c") |>
  dplyr::mutate(
    display_name = dplyr::recode(
      iso3c,
      BRA = "Brasil",
      CHL = "Chile",
      GAB = "Gabão",
      URY = "Uruguai",
      QAT = "Catar",
      AUS = "Austrália"
    ),
    country_label = paste0(
      display_name,
      " (", iso3c, "; entrada ", cue_audit_entry_year,
      "; cue ", salience_code, ")"
    ),
    period = dplyr::if_else(
      year < cue_audit_entry_year,
      "Antes da entrada",
      "Entrada e anos seguintes"
    )
  ) |>
  dplyr::arrange(cue_audit_entry_year, country_name, year)

coverage <- plot_data |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    min_year = min(year),
    max_year = max(year),
    n_years = dplyr::n(),
    entry_year = dplyr::first(cue_audit_entry_year),
    .groups = "drop"
  )

stopifnot(
  nrow(coverage) == 6L,
  all(coverage$min_year == 2000L),
  all(coverage$max_year == 2023L),
  all(coverage$n_years == 24L)
)

facet_levels <- selected_codes |>
  dplyr::mutate(
    display_name = dplyr::recode(
      iso3c,
      BRA = "Brasil",
      CHL = "Chile",
      GAB = "Gabão",
      URY = "Uruguai",
      QAT = "Catar",
      AUS = "Austrália"
    ),
    country_label = paste0(
      display_name,
      " (", iso3c, "; entrada ", cue_audit_entry_year,
      "; cue ", salience_code, ")"
    )
  ) |>
  dplyr::pull(country_label)

plot_data <- plot_data |>
  dplyr::mutate(country_label = factor(country_label, levels = facet_levels))

entry_lines <- selected_codes |>
  dplyr::mutate(
    display_name = dplyr::recode(
      iso3c,
      BRA = "Brasil",
      CHL = "Chile",
      GAB = "Gabão",
      URY = "Uruguai",
      QAT = "Catar",
      AUS = "Austrália"
    ),
    country_label = factor(
      paste0(
        display_name,
        " (", iso3c, "; entrada ", cue_audit_entry_year,
        "; cue ", salience_code, ")"
      ),
      levels = facet_levels
    )
  )

figure <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(x = year, y = abs_distance_china)
) +
  ggplot2::geom_line(colour = "#25364a", linewidth = 0.55) +
  ggplot2::geom_point(colour = "#25364a", size = 1.35, alpha = 0.9) +
  ggplot2::geom_vline(
    data = entry_lines,
    ggplot2::aes(xintercept = cue_audit_entry_year),
    colour = "#b2182b",
    linetype = "dashed",
    linewidth = 0.7
  ) +
  ggplot2::facet_wrap(~country_label, ncol = 2) +
  ggplot2::scale_x_continuous(
    breaks = seq(2000, 2024, by = 4),
    limits = c(1999.5, 2023.5)
  ) +
  ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.04, 0.08))) +
  ggplot2::labs(
    title = "Distância até a China nos casos selecionados",
    subtitle = paste0(
      "Distância absoluta entre os ideal points do país e da China na AGNU, 2000–2023.\n",
      "Linha vermelha = entrada usada na auditoria de public cue. ",
      "Brasil, Chile, Gabão e Uruguai: high; Catar: medium; Austrália: unknown."
    ),
    x = "Ano",
    y = "Distância absoluta do\nideal point à China",
    caption = paste0(
      "Figura 1. Valores menores indicam maior proximidade à China. Figura descritiva; ",
      "não é uma estimativa causal.\n",
      "Fontes: master panel M2 de 29 ago. 2026 e auditoria de public cue atualizada ",
      "em 22 set. 2026.\n",
      "Os anos de entrada são os da auditoria e não coincidem em todos os casos ",
      "com a regra M2/min-5 do painel principal atual."
    )
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold", size = 10.5),
    plot.title = ggplot2::element_text(face = "bold", size = 15),
    plot.subtitle = ggplot2::element_text(size = 10.5, lineheight = 1.12),
    plot.caption = ggplot2::element_text(size = 8.5, hjust = 0, colour = "grey30"),
    axis.title = ggplot2::element_text(size = 10),
    plot.margin = ggplot2::margin(10, 12, 10, 10)
  )

readr::write_csv(
  plot_data |>
    dplyr::mutate(country_label = as.character(country_label)),
  plot_data_path
)

ggplot2::ggsave(
  filename = png_path,
  plot = figure,
  width = 10,
  height = 9.2,
  dpi = 320,
  bg = "white"
)

message("Wrote: ", png_path)
message("Wrote: ", plot_data_path)
