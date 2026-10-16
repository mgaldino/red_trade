# Exploratory (outside targets): pre-cue distance to China for the cases near
# the floor of the absolute-distance outcome, compared with Gabon.
#
# Panel per country, 1997-2022: absolute UNGA ideal-point distance to China, the
# public-cue year, the five pre-cue years, the long pre-cue mean (1997 to
# cue - 1, the criterion behind the paper's Gabon exclusion) and the five-year
# pre-cue mean. Background: 10th-25th percentile band and median of the 105
# never-China-top controls (complete 1997-2022).
#
# Run from the project root:
#   LC_ALL=en_US.UTF-8 Rscript --vanilla scripts/diagnostics/plot_public_cue_floor_panel.R
# (UTF-8 locale needed for the Portuguese labels under --vanilla.)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

output_dir <- file.path("data", "processed", "diagnostics", "public_cue_floor")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cases <- tibble::tribble(
  ~iso3c, ~label, ~cue,
  "GAB", "Gabão", 2017L,
  "SAU", "Arábia Saudita", 2013L,
  "ZAF", "África do Sul", 2010L,
  "TKM", "Turcomenistão", 2011L,
  "QAT", "Catar", 2021L,
  "MYS", "Malásia", 2010L,
  "BRA", "Brasil", 2009L
)

panel <- targets::tar_read(china_top_m2_goods_panel) |>
  dplyr::mutate(year = as.integer(year), iso3c = as.character(iso3c)) |>
  dplyr::filter(year >= 1997L, year <= 2022L) |>
  dplyr::select(iso3c, year, abs_distance_china, china_is_top)

controls <- panel |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    ok = dplyr::n_distinct(year) == 26L & all(!is.na(abs_distance_china)) &
      all(!is.na(china_is_top)) & !any(china_is_top %in% TRUE),
    .groups = "drop"
  ) |>
  dplyr::filter(ok) |>
  dplyr::pull(iso3c)
stopifnot(length(controls) == 105L)

control_band <- panel |>
  dplyr::filter(iso3c %in% controls) |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    p10 = stats::quantile(abs_distance_china, 0.10),
    p25 = stats::quantile(abs_distance_china, 0.25),
    p50 = stats::median(abs_distance_china),
    .groups = "drop"
  )

series <- panel |>
  dplyr::inner_join(cases, by = "iso3c") |>
  dplyr::filter(!is.na(abs_distance_china))

pre_means <- series |>
  dplyr::filter(year < cue) |>
  dplyr::group_by(iso3c, label, cue) |>
  dplyr::summarise(
    mean_long = mean(abs_distance_china),
    mean_5 = mean(abs_distance_china[year >= cue - 5L]),
    median_5 = stats::median(abs_distance_china[year >= cue - 5L]),
    .groups = "drop"
  )

facet_levels <- cases |>
  dplyr::left_join(pre_means, by = c("iso3c", "label", "cue")) |>
  dplyr::mutate(
    facet = sprintf("%s (cue %d)\nmédia longa %.2f · 5 anos pré: média %.2f, mediana %.2f",
                    label, cue, mean_long, mean_5, median_5)
  )

add_facet <- function(d) {
  dplyr::left_join(d, dplyr::select(facet_levels, iso3c, facet), by = "iso3c") |>
    dplyr::mutate(facet = factor(facet, levels = facet_levels$facet))
}

band <- tidyr::crossing(dplyr::select(cases, iso3c), control_band) |> add_facet()
series <- add_facet(series)
windows <- facet_levels |>
  dplyr::mutate(xmin = cue - 5.5, xmax = cue - 0.5,
                facet = factor(facet, levels = facet_levels$facet))
segments <- dplyr::bind_rows(
  dplyr::transmute(facet_levels, iso3c, what = "Média longa (1997 até cue−1)",
                   x = 1997, xend = cue - 1, y = mean_long),
  dplyr::transmute(facet_levels, iso3c, what = "Média dos 5 anos pré-cue",
                   x = cue - 5, xend = cue - 1, y = mean_5)
) |>
  add_facet()

p <- ggplot2::ggplot() +
  ggplot2::geom_rect(
    data = windows,
    ggplot2::aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
    fill = "#dbe9f6", colour = NA
  ) +
  ggplot2::geom_ribbon(
    data = band, ggplot2::aes(x = year, ymin = p10, ymax = p25),
    fill = "grey75", alpha = 0.6
  ) +
  ggplot2::geom_line(
    data = band, ggplot2::aes(x = year, y = p50),
    colour = "grey45", linetype = "dashed", linewidth = 0.4
  ) +
  ggplot2::geom_vline(
    data = windows, ggplot2::aes(xintercept = cue - 0.5),
    colour = "#b2182b", linewidth = 0.5
  ) +
  ggplot2::geom_segment(
    data = segments,
    ggplot2::aes(x = x, xend = xend, y = y, yend = y, linetype = what),
    colour = "#d6604d", linewidth = 0.8
  ) +
  ggplot2::geom_line(
    data = series, ggplot2::aes(x = year, y = abs_distance_china),
    colour = "grey10", linewidth = 0.6
  ) +
  ggplot2::geom_point(
    data = series, ggplot2::aes(x = year, y = abs_distance_china),
    colour = "grey10", size = 0.9
  ) +
  ggplot2::scale_linetype_manual(
    values = c("Média longa (1997 até cue−1)" = "dotted",
               "Média dos 5 anos pré-cue" = "solid"),
    name = NULL
  ) +
  ggplot2::scale_x_continuous(breaks = seq(2000, 2020, 5)) +
  ggplot2::scale_y_continuous(limits = c(0, NA), expand = ggplot2::expansion(mult = c(0, 0.04))) +
  ggplot2::facet_wrap(~facet, ncol = 3) +
  ggplot2::labs(
    x = NULL,
    y = "Distância absoluta ao ponto ideal da China",
    caption = paste0(
      "Linha preta: país. Linha vermelha vertical: ano do cue (tratado a partir dele). ",
      "Área azul: 5 anos pré-cue.\n",
      "Faixa cinza: 10º-25º percentil dos 105 controles nunca China-top (1997-2022); ",
      "tracejado cinza: mediana dos controles.\n",
      "Cues: GAB 2017 e QAT 2021 como no paper; SAU, TKM e MYS da busca dirigida de 2026-09-24."
    )
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(hjust = 0, size = 8),
    plot.caption = ggplot2::element_text(hjust = 0, size = 7.5, colour = "grey30")
  )

ggplot2::ggsave(file.path(output_dir, "floor_panel.png"), p,
                width = 12, height = 8.5, dpi = 200, bg = "white")
ggplot2::ggsave(file.path(output_dir, "floor_panel.pdf"), p,
                width = 12, height = 8.5)
readr::write_csv(
  dplyr::left_join(
    dplyr::select(series, iso3c, year, abs_distance_china),
    control_band, by = "year"
  ),
  file.path(output_dir, "floor_panel_data.csv")
)
print(as.data.frame(dplyr::select(facet_levels, iso3c, cue, mean_long, mean_5, median_5)))
