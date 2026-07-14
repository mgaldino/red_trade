#!/usr/bin/env Rscript

# Diagnostic plot for the broad cross-country specification:
# treatment equals China being the country's #1 export destination. The figure
# compares each treated country's UNGA ideal-point distance to China with its
# distance to the current #2 export destination, restricted to 2000 onward.
# This script reads existing targets and does not modify the targets pipeline.

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
  library(countrycode)
  library(here)
  library(readr)
})

options(scipen = 999)

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

start_year <- 2000L

pdf_path <- file.path(
  out_dir,
  "fig_cross_country_any_top_distance_to_china_vs_rank2_post2000.pdf"
)
plot_data_path <- file.path(
  out_dir,
  "cross_country_any_top_distance_to_china_vs_rank2_post2000_plot_data.csv"
)
summary_path <- file.path(
  out_dir,
  "cross_country_any_top_distance_to_china_vs_rank2_post2000_summary.csv"
)
report_path <- file.path(
  out_dir,
  "2026-05-17_cross_country_any_top_distance_to_china_vs_rank2_post2000.md"
)

safe_country_name <- function(iso3c) {
  iso3c_chr <- as.character(iso3c)
  out <- countrycode::countrycode(
    iso3c_chr,
    origin = "iso3c",
    destination = "country.name",
    warn = FALSE
  )
  dplyr::if_else(is.na(out), iso3c_chr, out)
}

collapse_values <- function(x) {
  x <- sort(unique(stats::na.omit(as.character(x))))
  if (length(x) == 0) {
    return(NA_character_)
  }
  paste(x, collapse = "; ")
}

trim_text <- function(x, max_chars = 112) {
  x <- ifelse(is.na(x), "", x)
  ifelse(nchar(x) > max_chars, paste0(substr(x, 1, max_chars - 3), "..."), x)
}

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
switching_panel_any <- tar_read(switching_panel_any)

treated_countries <- switching_panel_any |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    treated_years = sum(china_top == 1L, na.rm = TRUE),
    first_china_top = if (any(china_top == 1L)) min(year[china_top == 1L]) else NA_integer_,
    last_china_top = if (any(china_top == 1L)) max(year[china_top == 1L]) else NA_integer_,
    .groups = "drop"
  ) |>
  dplyr::filter(treated_years > 0) |>
  dplyr::arrange(first_china_top, iso3c)

if (nrow(treated_countries) == 0) {
  stop("No treated countries found in switching_panel_any.")
}

ranked_trade <- trade_data |>
  dplyr::filter(exporter_iso3 %in% treated_countries$iso3c) |>
  dplyr::group_by(year, exporter_iso3) |>
  dplyr::arrange(dplyr::desc(exports), importer_iso3, .by_group = TRUE) |>
  dplyr::mutate(rank = dplyr::row_number()) |>
  dplyr::ungroup()

top_two_partners <- ranked_trade |>
  dplyr::filter(rank %in% c(1L, 2L)) |>
  dplyr::select(
    iso3c = exporter_iso3,
    year,
    rank,
    partner = importer_iso3,
    exports
  ) |>
  tidyr::pivot_wider(
    names_from = rank,
    values_from = c(partner, exports),
    names_glue = "rank{rank}_{.value}"
  ) |>
  dplyr::mutate(
    rank1_partner_name = safe_country_name(rank1_partner),
    rank2_partner_name = safe_country_name(rank2_partner)
  )

plot_year_max <- max(unga_data$year, na.rm = TRUE)

ideal_data <- unga_data |>
  dplyr::filter(year >= start_year) |>
  dplyr::select(year, iso3c, ideal_point = ideal_point_all)

china_ideal <- ideal_data |>
  dplyr::filter(iso3c == "CHN") |>
  dplyr::select(year, china_ideal = ideal_point)

rank2_ideal <- ideal_data |>
  dplyr::select(year, rank2_partner = iso3c, rank2_ideal = ideal_point)

treated_ideal <- ideal_data |>
  dplyr::select(iso3c, year, treated_ideal = ideal_point)

distance_panel <- switching_panel_any |>
  dplyr::filter(iso3c %in% treated_countries$iso3c, year >= start_year) |>
  dplyr::select(iso3c, country_name, year, china_top, rank_CHN) |>
  dplyr::left_join(top_two_partners, by = c("iso3c", "year")) |>
  dplyr::left_join(treated_ideal, by = c("iso3c", "year")) |>
  dplyr::left_join(china_ideal, by = "year") |>
  dplyr::left_join(rank2_ideal, by = c("year", "rank2_partner")) |>
  dplyr::mutate(
    distance_to_china = abs(treated_ideal - china_ideal),
    distance_to_rank2 = abs(treated_ideal - rank2_ideal),
    rank2_missing_ideal = !is.na(rank2_partner) & is.na(rank2_ideal)
  ) |>
  dplyr::arrange(iso3c, year)

if (any(is.na(distance_panel$treated_ideal))) {
  warning("Some treated-country ideal points are missing after 2000.")
}

spell_timeline <- switching_panel_any |>
  dplyr::filter(iso3c %in% treated_countries$iso3c) |>
  dplyr::select(iso3c, country_name, year, china_top) |>
  dplyr::group_by(iso3c) |>
  dplyr::arrange(year, .by_group = TRUE) |>
  dplyr::mutate(
    previous_china_top = dplyr::lag(china_top, default = 0L),
    spell_start = china_top == 1L & previous_china_top == 0L,
    spell_id = cumsum(spell_start)
  ) |>
  dplyr::ungroup()

spells <- spell_timeline |>
  dplyr::filter(china_top == 1L) |>
  dplyr::group_by(iso3c, country_name, spell_id) |>
  dplyr::summarise(
    spell_start = min(year),
    spell_end = max(year),
    .groups = "drop"
  ) |>
  dplyr::filter(spell_end >= start_year, spell_start <= plot_year_max) |>
  dplyr::mutate(
    plot_start = pmax(spell_start, start_year),
    plot_end = pmin(spell_end, plot_year_max)
  ) |>
  dplyr::arrange(iso3c, spell_start)

plot_data <- distance_panel |>
  dplyr::select(
    plot_country = iso3c,
    plot_country_name = country_name,
    year,
    china_top,
    rank_CHN,
    rank1_partner,
    rank1_partner_name,
    rank2_partner,
    rank2_partner_name,
    distance_to_china,
    distance_to_rank2
  ) |>
  tidyr::pivot_longer(
    cols = c(distance_to_china, distance_to_rank2),
    names_to = "distance_type",
    values_to = "distance"
  ) |>
  dplyr::mutate(
    distance_type = dplyr::case_when(
      distance_type == "distance_to_china" ~ "Distance to China",
      distance_type == "distance_to_rank2" ~ "Distance to current #2 export partner",
      TRUE ~ distance_type
    )
  ) |>
  dplyr::arrange(plot_country, distance_type, year)

country_summary <- distance_panel |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    n_post2000_years = dplyr::n(),
    first_plot_year = min(year, na.rm = TRUE),
    last_plot_year = max(year, na.rm = TRUE),
    n_china_top_years_post2000 = sum(china_top == 1L, na.rm = TRUE),
    rank2_partners_post2000 = collapse_values(rank2_partner),
    rank2_partner_names_post2000 = collapse_values(rank2_partner_name),
    n_rank2_partners_post2000 = dplyr::n_distinct(rank2_partner, na.rm = TRUE),
    rank2_partners_during_china_top = collapse_values(rank2_partner[china_top == 1L]),
    rank2_partner_names_during_china_top = collapse_values(rank2_partner_name[china_top == 1L]),
    n_rank2_partners_during_china_top = dplyr::n_distinct(rank2_partner[china_top == 1L], na.rm = TRUE),
    n_missing_rank2_ideal_years = sum(rank2_missing_ideal, na.rm = TRUE),
    missing_rank2_ideal_partners = collapse_values(rank2_partner[rank2_missing_ideal]),
    mean_distance_china = mean(distance_to_china, na.rm = TRUE),
    mean_distance_rank2 = mean(distance_to_rank2, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(
    spells |>
      dplyr::group_by(iso3c, country_name) |>
      dplyr::summarise(
        n_china_top_spells_post2000 = dplyr::n(),
        china_top_spells_post2000 = paste0(plot_start, "-", plot_end, collapse = "; "),
        .groups = "drop"
      ),
    by = c("iso3c", "country_name")
  ) |>
  dplyr::mutate(
    n_china_top_spells_post2000 = tidyr::replace_na(n_china_top_spells_post2000, 0L),
    china_top_spells_post2000 = tidyr::replace_na(china_top_spells_post2000, "none")
  ) |>
  dplyr::arrange(first_plot_year, iso3c)

distance_colours <- c(
  "Distance to China" = "#b2182b",
  "Distance to current #2 export partner" = "#2166ac"
)

distance_linetypes <- c(
  "Distance to China" = "solid",
  "Distance to current #2 export partner" = "longdash"
)

make_country_plot <- function(country_iso3c) {
  country_data <- plot_data |>
    dplyr::filter(plot_country == country_iso3c)

  country_spells <- spells |>
    dplyr::filter(iso3c == country_iso3c)

  country_summary_row <- country_summary |>
    dplyr::filter(iso3c == country_iso3c)

  endpoint_data <- country_data |>
    dplyr::filter(!is.na(distance)) |>
    dplyr::group_by(distance_type) |>
    dplyr::filter(year == max(year, na.rm = TRUE)) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      endpoint_label = dplyr::case_when(
        distance_type == "Distance to China" ~ "China",
        TRUE ~ "#2"
      )
    )

  rank2_note <- country_summary_row$rank2_partners_during_china_top[1]
  missing_note <- country_summary_row$missing_rank2_ideal_partners[1]
  subtitle <- trim_text(paste0(
    "China #1: ", country_summary_row$china_top_spells_post2000[1],
    " | #2 during China-top: ",
    ifelse(is.na(rank2_note), "none", rank2_note),
    ifelse(
      !is.na(missing_note) && nzchar(missing_note),
      paste0(" | missing UN ideal: ", missing_note),
      ""
    )
  ))

  ggplot(country_data, aes(x = year, y = distance, group = distance_type)) +
    geom_rect(
      data = country_spells,
      aes(xmin = plot_start - 0.5, xmax = plot_end + 0.5, ymin = -Inf, ymax = Inf),
      inherit.aes = FALSE,
      fill = "#fdd49e",
      alpha = 0.28
    ) +
    geom_line(
      aes(colour = distance_type, linetype = distance_type),
      linewidth = 0.55,
      na.rm = TRUE
    ) +
    geom_point(
      aes(colour = distance_type),
      size = 0.55,
      alpha = 0.85,
      na.rm = TRUE
    ) +
    geom_text(
      data = endpoint_data,
      aes(label = endpoint_label, colour = distance_type),
      hjust = 0,
      nudge_x = 0.35,
      size = 2.0,
      show.legend = FALSE
    ) +
    scale_colour_manual(values = distance_colours, drop = FALSE) +
    scale_linetype_manual(values = distance_linetypes, drop = FALSE) +
    scale_x_continuous(
      breaks = seq(start_year, plot_year_max, by = 5),
      limits = c(start_year, plot_year_max + 2)
    ) +
    labs(
      title = paste0(country_summary_row$country_name[1], " (", country_iso3c, ")"),
      subtitle = subtitle,
      x = NULL,
      y = "Absolute UNGA ideal-point distance"
    ) +
    coord_cartesian(clip = "off") +
    theme_minimal(base_size = 8) +
    theme(
      legend.position = "none",
      plot.title = element_text(face = "bold", size = 8.4),
      plot.subtitle = element_text(size = 6.3, colour = "grey25", lineheight = 0.95),
      panel.grid.minor = element_blank(),
      axis.title.y = element_text(size = 7),
      axis.text = element_text(size = 6.6),
      plot.margin = margin(4, 22, 4, 4)
    )
}

country_plots <- treated_countries$iso3c |>
  lapply(make_country_plot)

legend_plot <- ggplot(
  tibble::tibble(
    year = rep(1:2, 2),
    distance = rep(c(1, 2), 2),
    distance_type = rep(names(distance_colours), each = 2)
  ),
  aes(x = year, y = distance, colour = distance_type, linetype = distance_type)
) +
  geom_line(linewidth = 0.9) +
  scale_colour_manual(values = distance_colours, name = NULL) +
  scale_linetype_manual(values = distance_linetypes, name = NULL) +
  theme_void(base_size = 9) +
  theme(legend.position = "bottom")

plots_per_page <- 6L
plot_pages <- split(country_plots, ceiling(seq_along(country_plots) / plots_per_page))

grDevices::pdf(pdf_path, width = 11, height = 8.5, onefile = TRUE)
for (page_id in seq_along(plot_pages)) {
  page <- patchwork::wrap_plots(plot_pages[[page_id]], ncol = 2) +
    patchwork::plot_annotation(
      title = paste0(
        "Cross-country treated cases: distance to China vs. current #2 export partner",
        " (page ", page_id, "/", length(plot_pages), ")"
      ),
      subtitle = paste0(
        "Years from ", start_year, " onward. Treatment periods where China is #1 are shaded."
      )
    )

  print(page)
}

print(legend_plot + labs(title = "Legend"))
grDevices::dev.off()

readr::write_csv(plot_data, plot_data_path)
readr::write_csv(country_summary, summary_path)

missing_rank2 <- country_summary |>
  dplyr::filter(n_missing_rank2_ideal_years > 0)

sink(report_path)
cat("# Cross-country distance panel: China vs current #2\n\n")
cat("Date: 2026-05-17\n\n")
cat("This diagnostic uses `switching_panel_any`: treatment equals 1 when China is the #1 export destination, regardless of which partner was previously #1. It plots absolute UNGA ideal-point distance from the treated country to China and to the current #2 export destination, restricted to years >= ", start_year, ". It does not modify `_targets.R` or the targets store.\n\n", sep = "")
cat("## Outputs\n\n")
cat("- PDF: `", pdf_path, "`\n", sep = "")
cat("- Plot data: `", plot_data_path, "`\n", sep = "")
cat("- Country-level summary: `", summary_path, "`\n\n", sep = "")
cat("## Coverage\n\n")
cat("- Treated countries: ", nrow(treated_countries), "\n", sep = "")
cat("- Years plotted: ", start_year, "-", plot_year_max, "\n", sep = "")
cat("- Countries with China-top years after ", start_year, ": ", sum(country_summary$n_china_top_years_post2000 > 0), "\n", sep = "")
cat("- Country-years where the #2 partner lacks an UNGA ideal-point series: ", sum(distance_panel$rank2_missing_ideal, na.rm = TRUE), "\n\n", sep = "")
cat("## Countries with missing #2 ideal-point years\n\n")
print(
  missing_rank2 |>
    dplyr::select(
      iso3c,
      country_name,
      n_missing_rank2_ideal_years,
      missing_rank2_ideal_partners
    )
)
sink()

cat("Wrote:\n")
cat("- ", pdf_path, "\n", sep = "")
cat("- ", plot_data_path, "\n", sep = "")
cat("- ", summary_path, "\n", sep = "")
cat("- ", report_path, "\n", sep = "")
