#!/usr/bin/env Rscript

# Single-country SDiD plots for the seven public-cue cases, plus Chile with the
# superseded 2009 cue (exploratory). Same windows (1997 to cue year + 6) and
# controls (complete and never China-top in 1997-2022) as
# estimate_public_cue_staggered_sdid.R. Dotted line: year China enters the top
# of the goods-export ranking.
#
# Exploratory and outside the targets graph; listed in TARGETS_MIGRATION.md.
#   Rscript scripts/diagnostics/plot_public_cue_single_sdid.R

suppressPackageStartupMessages({library(dplyr); library(ggplot2); library(patchwork)})
p <- targets::tar_read(china_top_m2_goods_panel) |>
  mutate(year = as.integer(year), iso3c = as.character(iso3c), china_is_top = as.logical(china_is_top))
controls <- p |> filter(year >= 1997, year <= 2022) |> group_by(iso3c) |>
  summarise(ok = n_distinct(year) == 26 & all(!is.na(abs_distance_china)) & all(!is.na(china_is_top)) & !any(china_is_top %in% TRUE), .groups = "drop") |>
  filter(ok) |> pull(iso3c) |> sort()
stopifnot(length(controls) == 105)
Y <- p |> filter(iso3c %in% c(controls, "KOR","AUS","BRA","CHL","ZAF","URY","NZL"), year %in% 1997:2022) |>
  select(iso3c, year, abs_distance_china) |> tidyr::pivot_wider(names_from = year, values_from = abs_distance_china) |>
  tibble::column_to_rownames("iso3c") |> as.matrix()
entry <- p |> filter(china_is_top %in% TRUE, year >= 2000) |> group_by(iso3c) |> summarise(entry = min(year))
cases <- tibble::tribble(~iso3c, ~cue,
  "KOR", 2003L, "AUS", 2007L, "CHL", 2007L, "CHL", 2009L, "BRA", 2009L, "ZAF", 2010L, "URY", 2013L, "NZL", 2013L)
plots <- lapply(seq_len(nrow(cases)), function(k) {
  u <- cases$iso3c[k]; cue <- cases$cue[k]
  cols <- as.character(1997:(cue + 6))
  est <- synthdid::synthdid_estimate(Y[c(controls, u), cols], length(controls), cue - 1997)
  e <- entry$entry[entry$iso3c == u]
  synthdid::synthdid_plot(est, se.method = "none", treated.name = u, control.name = "sintético") +
    geom_vline(xintercept = e, linetype = "dotted", colour = "darkred") +
    labs(title = sprintf("%s — cue %d (entrada no rank de bens %d): SDiD %+.3f", u, cue, e, as.numeric(est)),
         x = NULL, y = "Distância à China") +
    theme(plot.title = element_text(size = 9), legend.position = "bottom",
          legend.text = element_text(size = 7), axis.text = element_text(size = 7))
})
g <- wrap_plots(plots, ncol = 2)
ggsave(file.path("data", "processed", "diagnostics", "public_cue_staggered_sdid", "single_sdid_plots.png"),
       g, width = 11, height = 15, dpi = 130)
