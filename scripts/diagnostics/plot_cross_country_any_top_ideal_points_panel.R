#!/usr/bin/env Rscript

# Diagnostic plot for the cross-country specification in which treatment is
# China being the country's #1 export destination, regardless of the previous
# top trade partner. This script reads existing targets and does not modify the
# targets pipeline.

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

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

pdf_path <- file.path(out_dir, "fig_cross_country_any_top_ideal_points_panel.pdf")
plot_data_path <- file.path(out_dir, "cross_country_any_top_ideal_point_plot_data.csv")
spells_path <- file.path(out_dir, "cross_country_any_top_partner_spells.csv")
country_summary_path <- file.path(out_dir, "cross_country_any_top_partner_country_summary.csv")
report_path <- file.path(out_dir, "2026-05-17_cross_country_any_top_ideal_points_panel.md")

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

trim_text <- function(x, max_chars = 105) {
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
    switches = sum(abs(diff(china_top)), na.rm = TRUE),
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
  )

rank_china_check <- ranked_trade |>
  dplyr::filter(importer_iso3 == "CHN") |>
  dplyr::select(iso3c = exporter_iso3, year, rebuilt_rank_CHN = rank)

panel_check <- switching_panel_any |>
  dplyr::filter(iso3c %in% treated_countries$iso3c) |>
  dplyr::select(iso3c, year, target_rank_CHN = rank_CHN, target_china_top = china_top) |>
  dplyr::left_join(rank_china_check, by = c("iso3c", "year")) |>
  dplyr::mutate(
    rebuilt_china_top = as.integer(!is.na(rebuilt_rank_CHN) & rebuilt_rank_CHN == 1L),
    rank_matches_target = dplyr::coalesce(target_rank_CHN == rebuilt_rank_CHN, is.na(target_rank_CHN) & is.na(rebuilt_rank_CHN)),
    treatment_matches_target = target_china_top == rebuilt_china_top
  )

if (!all(panel_check$rank_matches_target, na.rm = TRUE) ||
    !all(panel_check$treatment_matches_target, na.rm = TRUE)) {
  warning(
    "Rebuilt trade ranks do not perfectly match switching_panel_any. ",
    "The plot uses switching_panel_any for treatment spells and rebuilt ranks for partner labels."
  )
}

treatment_timeline <- switching_panel_any |>
  dplyr::filter(iso3c %in% treated_countries$iso3c) |>
  dplyr::select(iso3c, country_name, year, china_top) |>
  dplyr::left_join(top_two_partners, by = c("iso3c", "year")) |>
  dplyr::group_by(iso3c) |>
  dplyr::arrange(year, .by_group = TRUE) |>
  dplyr::mutate(
    previous_year = dplyr::lag(year),
    previous_top_partner = dplyr::lag(rank1_partner),
    previous_top_exports = dplyr::lag(rank1_exports),
    china_top_previous = dplyr::lag(china_top, default = 0L),
    spell_start = china_top == 1L & china_top_previous == 0L,
    spell_id = cumsum(spell_start)
  ) |>
  dplyr::ungroup()

spell_starts <- treatment_timeline |>
  dplyr::filter(spell_start) |>
  dplyr::transmute(
    iso3c,
    country_name,
    spell_id,
    spell_start = year,
    previous_year,
    displaced_partner = previous_top_partner,
    displaced_partner_name = safe_country_name(displaced_partner),
    rank2_at_start = rank2_partner,
    rank2_at_start_name = safe_country_name(rank2_at_start),
    rank2_differs_from_displaced = !is.na(displaced_partner) &
      !is.na(rank2_at_start) &
      displaced_partner != rank2_at_start
  )

spells <- treatment_timeline |>
  dplyr::filter(china_top == 1L) |>
  dplyr::group_by(iso3c, country_name, spell_id) |>
  dplyr::summarise(
    spell_end = max(year),
    rank2_partners_during_spell = collapse_values(rank2_partner),
    n_rank2_partners_during_spell = dplyr::n_distinct(rank2_partner, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(spell_starts, by = c("iso3c", "country_name", "spell_id")) |>
  dplyr::select(
    iso3c,
    country_name,
    spell_id,
    spell_start,
    spell_end,
    previous_year,
    displaced_partner,
    displaced_partner_name,
    rank2_at_start,
    rank2_at_start_name,
    rank2_differs_from_displaced,
    rank2_partners_during_spell,
    n_rank2_partners_during_spell
  ) |>
  dplyr::arrange(iso3c, spell_start)

country_partner_summary <- spells |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    n_china_top_spells = dplyr::n(),
    china_top_spells = paste0(spell_start, "-", spell_end, collapse = "; "),
    displaced_partners = collapse_values(displaced_partner),
    displaced_partner_names = collapse_values(displaced_partner_name),
    n_displaced_partners = dplyr::n_distinct(displaced_partner, na.rm = TRUE),
    rank2_at_start_partners = collapse_values(rank2_at_start),
    rank2_at_start_partner_names = collapse_values(rank2_at_start_name),
    n_rank2_at_start_partners = dplyr::n_distinct(rank2_at_start, na.rm = TRUE),
    any_rank2_start_differs_from_displaced = any(rank2_differs_from_displaced, na.rm = TRUE),
    n_spells_with_rank2_start_differs = sum(rank2_differs_from_displaced, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(n_china_top_spells), iso3c)

reference_partners <- spells |>
  dplyr::select(
    iso3c,
    country_name,
    displaced_partner,
    rank2_at_start
  ) |>
  tidyr::pivot_longer(
    cols = c(displaced_partner, rank2_at_start),
    names_to = "reference_source",
    values_to = "reference_iso3c"
  ) |>
  dplyr::filter(!is.na(reference_iso3c), reference_iso3c != "CHN") |>
  dplyr::distinct(iso3c, country_name, reference_iso3c)

plot_series_index <- dplyr::bind_rows(
  treated_countries |>
    dplyr::transmute(
      plot_country = iso3c,
      plot_country_name = country_name,
      series_iso3c = iso3c,
      series_role = "Treated country"
    ),
  treated_countries |>
    dplyr::transmute(
      plot_country = iso3c,
      plot_country_name = country_name,
      series_iso3c = "CHN",
      series_role = "China"
    ),
  reference_partners |>
    dplyr::transmute(
      plot_country = iso3c,
      plot_country_name = country_name,
      series_iso3c = reference_iso3c,
      series_role = "Former #1 or #2 at entry"
    )
) |>
  dplyr::distinct(plot_country, plot_country_name, series_iso3c, series_role) |>
  dplyr::mutate(
    series_name = safe_country_name(series_iso3c),
    series_label = dplyr::case_when(
      series_role == "Treated country" ~ paste0(plot_country_name, " (", series_iso3c, ")"),
      series_role == "China" ~ "China",
      TRUE ~ paste0(series_name, " (", series_iso3c, ")")
    )
  )

available_ideal_series <- unga_data |>
  dplyr::select(year, series_iso3c = iso3c, ideal_point = ideal_point_all)

plot_data <- plot_series_index |>
  dplyr::left_join(
    available_ideal_series,
    by = "series_iso3c",
    relationship = "many-to-many"
  ) |>
  dplyr::filter(!is.na(year)) |>
  dplyr::arrange(plot_country, series_role, series_iso3c, year)

missing_reference_series <- plot_series_index |>
  dplyr::anti_join(
    available_ideal_series |> dplyr::distinct(series_iso3c),
    by = "series_iso3c"
  ) |>
  dplyr::filter(series_role == "Former #1 or #2 at entry") |>
  dplyr::group_by(plot_country, plot_country_name) |>
  dplyr::summarise(
    missing_un_ideal_series = collapse_values(series_iso3c),
    missing_un_ideal_series_names = collapse_values(series_name),
    .groups = "drop"
  )

country_partner_summary <- country_partner_summary |>
  dplyr::left_join(
    plot_series_index |>
      dplyr::filter(series_role == "Former #1 or #2 at entry") |>
      dplyr::group_by(plot_country, plot_country_name) |>
      dplyr::summarise(
        plotted_reference_partners = collapse_values(series_iso3c),
        plotted_reference_partner_names = collapse_values(series_name),
        n_plotted_reference_partners = dplyr::n_distinct(series_iso3c),
        .groups = "drop"
      ),
    by = c("iso3c" = "plot_country", "country_name" = "plot_country_name")
  ) |>
  dplyr::left_join(
    missing_reference_series,
    by = c("iso3c" = "plot_country", "country_name" = "plot_country_name")
  )

role_colours <- c(
  "Treated country" = "#222222",
  "China" = "#b2182b",
  "Former #1 or #2 at entry" = "#2166ac"
)

role_linetypes <- c(
  "Treated country" = "solid",
  "China" = "solid",
  "Former #1 or #2 at entry" = "longdash"
)

make_country_plot <- function(country_iso3c) {
  country_data <- plot_data |>
    dplyr::filter(plot_country == country_iso3c)

  country_spells <- spells |>
    dplyr::filter(iso3c == country_iso3c)

  country_summary <- country_partner_summary |>
    dplyr::filter(iso3c == country_iso3c)

  label_data <- country_data |>
    dplyr::filter(!is.na(ideal_point)) |>
    dplyr::group_by(series_iso3c, series_role, series_label) |>
    dplyr::filter(year == max(year, na.rm = TRUE)) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      endpoint_label = dplyr::case_when(
        series_role == "China" ~ "CHN",
        series_role == "Treated country" ~ country_iso3c,
        TRUE ~ series_iso3c
      )
    )

  ref_names <- country_summary$plotted_reference_partners[1]
  missing_names <- country_summary$missing_un_ideal_series[1]
  rank2_note <- if (isTRUE(country_summary$any_rank2_start_differs_from_displaced[1])) {
    " #2 differs at entry in at least one spell."
  } else {
    ""
  }
  missing_note <- if (!is.na(missing_names) && nzchar(missing_names)) {
    paste0(" Missing UN ideal series: ", missing_names, ".")
  } else {
    ""
  }

  subtitle <- trim_text(paste0(
    "China #1: ", country_summary$china_top_spells[1],
    " | refs: ", ifelse(is.na(ref_names), "none", ref_names),
    ".", rank2_note, missing_note
  ))

  ggplot(country_data, aes(x = year, y = ideal_point, group = series_iso3c)) +
    geom_rect(
      data = country_spells,
      aes(xmin = spell_start - 0.5, xmax = spell_end + 0.5, ymin = -Inf, ymax = Inf),
      inherit.aes = FALSE,
      fill = "#fdd49e",
      alpha = 0.28
    ) +
    geom_line(aes(colour = series_role, linetype = series_role), linewidth = 0.42, na.rm = TRUE) +
    geom_point(aes(colour = series_role), size = 0.45, alpha = 0.85, na.rm = TRUE) +
    geom_text(
      data = label_data,
      aes(label = endpoint_label, colour = series_role),
      hjust = 0,
      nudge_x = 0.45,
      size = 2.0,
      show.legend = FALSE
    ) +
    scale_colour_manual(values = role_colours, drop = FALSE) +
    scale_linetype_manual(values = role_linetypes, drop = FALSE) +
    scale_x_continuous(
      breaks = seq(1990, max(unga_data$year, na.rm = TRUE), by = 8),
      limits = c(min(unga_data$year, na.rm = TRUE), max(unga_data$year, na.rm = TRUE) + 4)
    ) +
    labs(
      title = paste0(country_summary$country_name[1], " (", country_iso3c, ")"),
      subtitle = subtitle,
      x = NULL,
      y = "UNGA ideal point"
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
    year = rep(1:2, 3),
    ideal_point = rep(c(1, 2), 3),
    series_role = rep(names(role_colours), each = 2),
    series_iso3c = rep(names(role_colours), each = 2)
  ),
  aes(x = year, y = ideal_point, colour = series_role, linetype = series_role)
) +
  geom_line(linewidth = 0.8) +
  scale_colour_manual(values = role_colours, name = NULL) +
  scale_linetype_manual(values = role_linetypes, name = NULL) +
  theme_void(base_size = 9) +
  theme(legend.position = "bottom")

plots_per_page <- 6L
plot_pages <- split(country_plots, ceiling(seq_along(country_plots) / plots_per_page))

grDevices::pdf(pdf_path, width = 11, height = 8.5, onefile = TRUE)
for (page_id in seq_along(plot_pages)) {
  page <- patchwork::wrap_plots(plot_pages[[page_id]], ncol = 2) +
    patchwork::plot_annotation(
      title = paste0(
        "Cross-country treated cases: UNGA ideal points, China, and displaced/entry partners",
        " (page ", page_id, "/", length(plot_pages), ")"
      ),
      subtitle = paste0(
        "Treatment periods where China is #1 are shaded. ",
        "Reference partners include the prior #1 before each China-top spell and the #2 at entry when different."
      )
    )

  print(page)
}

print(legend_plot + labs(title = "Legend"))
grDevices::dev.off()

readr::write_csv(plot_data, plot_data_path)
readr::write_csv(spells, spells_path)
readr::write_csv(country_partner_summary, country_summary_path)

reentry_cases <- country_partner_summary |>
  dplyr::filter(n_china_top_spells > 1)

multiple_displaced <- reentry_cases |>
  dplyr::filter(n_displaced_partners > 1)

rank2_differs <- country_partner_summary |>
  dplyr::filter(any_rank2_start_differs_from_displaced)

sink(report_path)
cat("# Cross-country any-top ideal-point panel\n\n")
cat("Date: 2026-05-17\n\n")
cat("This diagnostic uses `switching_panel_any`: treatment equals 1 when China is the #1 export destination, regardless of which partner was previously #1. It does not modify `_targets.R` or the targets store.\n\n")
cat("## Outputs\n\n")
cat("- PDF: `", pdf_path, "`\n", sep = "")
cat("- Plot data: `", plot_data_path, "`\n", sep = "")
cat("- Spell-level partner table: `", spells_path, "`\n", sep = "")
cat("- Country-level partner summary: `", country_summary_path, "`\n\n", sep = "")
cat("## Coverage\n\n")
cat("- Treated countries: ", nrow(treated_countries), "\n", sep = "")
cat("- China-top spells: ", nrow(spells), "\n", sep = "")
cat("- Countries with more than one China-top spell: ", nrow(reentry_cases), "\n", sep = "")
cat("- Re-entry countries where the displaced prior #1 changes across spells: ", nrow(multiple_displaced), "\n", sep = "")
cat("- Countries where the #2 partner at China-entry differs from the prior #1 in at least one spell: ", nrow(rank2_differs), "\n\n", sep = "")
cat("## Re-entry cases with multiple displaced prior #1 partners\n\n")
print(multiple_displaced |> dplyr::select(iso3c, country_name, n_china_top_spells, displaced_partners, rank2_at_start_partners))
cat("\n## Cases where #2 at China-entry differs from prior #1\n\n")
print(rank2_differs |> dplyr::select(iso3c, country_name, n_china_top_spells, displaced_partners, rank2_at_start_partners, n_spells_with_rank2_start_differs))
sink()

cat("Wrote:\n")
cat("- ", pdf_path, "\n", sep = "")
cat("- ", plot_data_path, "\n", sep = "")
cat("- ", spells_path, "\n", sep = "")
cat("- ", country_summary_path, "\n", sep = "")
cat("- ", report_path, "\n", sep = "")
