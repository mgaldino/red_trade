#!/usr/bin/env Rscript

# Draft visuals and appendix tables for the status-cue/ex-Top1 salience audit.
# Reads processed CSVs only; does not run targets and does not edit the manuscript.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(forcats)
  library(ggplot2)
  library(patchwork)
  library(readr)
  library(scales)
  library(stringr)
  library(tidyr)
})

args_all <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_all, value = TRUE)
script_path <- if (length(file_arg) > 0L) {
  normalizePath(sub("^--file=", "", file_arg[[1]]))
} else {
  normalizePath("scripts/diagnostics/plot_ex_top1_salience_visual_drafts.R")
}
root <- normalizePath(file.path(dirname(script_path), "..", ".."))

ex_dir <- file.path(root, "data", "processed", "ex_top1_salience")
status_dir <- file.path(root, "data", "processed", "status_cue_salience")
report_dir <- file.path(root, "quality_reports", "ex_top1_salience")
figure_dir <- file.path(report_dir, "figures")
table_dir <- file.path(report_dir, "tables")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

comparison_path <- file.path(ex_dir, "status_cue_vs_ex_top1_coverage.csv")
ex_country_path <- file.path(ex_dir, "ex_top1_country_codes.csv")
ex_source_path <- file.path(ex_dir, "ex_top1_source_evidence.csv")
status_country_path <- file.path(status_dir, "status_cue_country_codes.csv")
status_source_path <- file.path(status_dir, "status_cue_source_evidence.csv")

required_paths <- c(
  comparison_path,
  ex_country_path,
  ex_source_path,
  status_country_path,
  status_source_path
)
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0L) {
  stop("Missing required input(s): ", paste(missing_paths, collapse = ", "))
}

bool <- function(x) {
  tolower(as.character(x)) == "true"
}

empty_to_na <- function(x) {
  dplyr::if_else(is.na(x) | !nzchar(x), NA_character_, x)
}

wrap_label <- function(x, width = 28L) {
  stringr::str_wrap(x, width = width)
}

code_label <- function(x) {
  dplyr::case_when(
    x == "high" ~ "High",
    x == "medium" ~ "Medium",
    x == "low" ~ "No evidence",
    x == "unknown" ~ "Not recovered",
    TRUE ~ stringr::str_to_sentence(x)
  )
}

implication_label <- function(x) {
  dplyr::case_when(
    x == "china_status_cue_observed" ~ "China cue observed",
    x == "more_informative_absence" ~ "Benchmark recoverable\n(not low)",
    x == "weak_observation" ~ "Weak observation;\nbenchmark not recovered",
    TRUE ~ stringr::str_replace_all(x, "_", " ")
  )
}

source_family <- function(source_type) {
  dplyr::case_when(
    source_type %in% c("local_news", "business_news", "newspaper", "national_news_agency") ~
      "news",
    source_type %in% c(
      "official",
      "official_pdf",
      "official_statistics",
      "official_report",
      "official_speech",
      "government_news"
    ) ~ "official",
    TRUE ~ "other"
  )
}

country_order <- c(
  "Solomon Islands",
  "Philippines",
  "Angola",
  "Chile",
  "Brazil",
  "Malaysia",
  "Australia",
  "Sierra Leone",
  "Uruguay",
  "Myanmar (Burma)",
  "Saudi Arabia",
  "Gabon",
  "Kuwait",
  "Qatar"
)

comparison <- readr::read_csv(comparison_path, show_col_types = FALSE) |>
  dplyr::mutate(
    entry_year = as.integer(entry_year),
    incumbent_rank_year = as.integer(incumbent_rank_year),
    incumbent_export_share = as.numeric(incumbent_export_share),
    china_export_share = as.numeric(china_export_share),
    export_share_gap_pp = 100 * (incumbent_export_share - china_export_share),
    country_year = paste0(country_name, " (", entry_year, ")"),
    country_year = forcats::fct_rev(forcats::fct_relevel(country_year, paste0(country_order, " (", entry_year, ")"))),
    status_cue_salience = factor(
      status_cue_salience,
      levels = c("high", "medium", "low", "unknown")
    ),
    ex_top1_coverage_code = factor(
      ex_top1_coverage_code,
      levels = c("high", "medium", "low", "unknown")
    ),
    implication_for_china_status_cue_absence = factor(
      implication_for_china_status_cue_absence,
      levels = c(
        "china_status_cue_observed",
        "more_informative_absence",
        "weak_observation"
      )
    )
  )

status_country <- readr::read_csv(status_country_path, show_col_types = FALSE) |>
  dplyr::mutate(
    salience_code = factor(salience_code, levels = c("high", "medium", "low", "unknown"))
  )

ex_country <- readr::read_csv(ex_country_path, show_col_types = FALSE) |>
  dplyr::mutate(
    ex_top1_coverage_code = factor(
      ex_top1_coverage_code,
      levels = c("high", "medium", "low", "unknown")
    )
  )

status_source <- readr::read_csv(status_source_path, show_col_types = FALSE) |>
  dplyr::mutate(
    explicit_rank_language = bool(explicit_rank_language),
    mentions_china_rank_change = bool(mentions_china_rank_change),
    notes = tidyr::replace_na(notes, ""),
    countable = evidence_strength %in% c("strong", "moderate") &
      explicit_rank_language &
      mentions_china_rank_change &
      !stringr::str_detect(notes, "^DO_NOT_COUNT"),
    source_family = source_family(source_type)
  )

ex_source <- readr::read_csv(ex_source_path, show_col_types = FALSE) |>
  dplyr::mutate(
    eligible_source = bool(eligible_source),
    explicit_rank_language = bool(explicit_rank_language),
    count_for_benchmark = bool(count_for_benchmark),
    notes = tidyr::replace_na(notes, ""),
    countable = count_for_benchmark &
      eligible_source &
      evidence_strength %in% c("strong", "moderate") &
      explicit_rank_language &
      !stringr::str_detect(notes, "^DO_NOT_COUNT"),
    source_family = source_family(source_type)
  )

summary_counts <- comparison |>
  dplyr::count(implication_for_china_status_cue_absence, name = "n_countries") |>
  dplyr::mutate(
    label = implication_label(as.character(implication_for_china_status_cue_absence))
  )

country_matrix <- comparison |>
  dplyr::left_join(
    status_country |>
      dplyr::select(
        iso3c,
        n_china_news_sources = n_newspaper_sources_strong,
        n_china_official_sources = n_official_sources_strong,
        n_china_sources = n_total_strong_or_moderate,
        has_explicit_export_rank_label,
        has_explicit_generic_trade_partner_label,
        has_official_uptake,
        has_newspaper_uptake,
        negative_case_candidate,
        status_cue_rationale = coding_rationale,
        status_cue_remaining_gaps = remaining_gaps
      ),
    by = "iso3c"
  ) |>
  dplyr::left_join(
    ex_country |>
      dplyr::select(
        iso3c,
        n_ex_top1_sources = n_countable_sources,
        n_ex_top1_news_sources = n_news_sources,
        n_ex_top1_official_sources = n_official_sources,
        n_ex_top1_independent_sources = n_independent_sources,
        n_ex_top1_broad_trade_context_sources = n_broad_trade_partner_context_sources,
        ex_top1_broad_trade_context_sources = broad_trade_partner_context_sources,
        ex_top1_broad_trade_context_labels = broad_trade_partner_context_labels,
        ex_top1_rationale = coding_rationale,
        ex_top1_remaining_gaps = remaining_gaps
      ),
    by = "iso3c"
  ) |>
  dplyr::mutate(
    n_ex_top1_broad_trade_context_sources = tidyr::replace_na(
      n_ex_top1_broad_trade_context_sources,
      0L
    ),
    ex_top1_broad_trade_context_sources = tidyr::replace_na(
      as.character(ex_top1_broad_trade_context_sources),
      ""
    ),
    ex_top1_broad_trade_context_labels = tidyr::replace_na(
      as.character(ex_top1_broad_trade_context_labels),
      ""
    ),
    reading = implication_label(as.character(implication_for_china_status_cue_absence)),
    metric_note = dplyr::case_when(
      iso3c == "AUS" & n_ex_top1_broad_trade_context_sources > 0L ~
        "Metric mismatch documented in archived AFR source: broad aggregate trading-partner cue; excluded from export-destination benchmark.",
      iso3c == "AUS" ~
        "Metric mismatch risk: export-destination treatment vs broader aggregate trading-partner press language in author-supplied AFR item.",
      iso3c == "MYS" ~
        "Rank-definition caveat: MITI also reports China as second-largest; China/Hong Kong aggregation may alter interpretation.",
      iso3c == "PHL" ~
        "Treatment-rank audit issue: contemporaneous sources place China below first in sectoral/monthly coverage.",
      iso3c == "SLE" ~
        "Local statistics conflict with Belgium-as-incumbent for the China-entry window.",
      TRUE ~ ""
    )
  ) |>
  dplyr::arrange(entry_year, country_name)

readr::write_csv(
  country_matrix |>
    dplyr::select(
      iso3c,
      country_name,
      entry_year,
      status_cue_salience,
      ex_top1_coverage_code,
      implication_for_china_status_cue_absence,
      incumbent_partner_name,
      incumbent_rank_year,
      incumbent_export_share,
      china_export_share,
      export_share_gap_pp,
      n_china_sources,
      n_china_news_sources,
      n_china_official_sources,
      n_ex_top1_sources,
      n_ex_top1_news_sources,
      n_ex_top1_official_sources,
      n_ex_top1_independent_sources,
      n_ex_top1_broad_trade_context_sources,
      ex_top1_broad_trade_context_sources,
      ex_top1_broad_trade_context_labels,
      principal_sources,
      principal_labels,
      status_cue_rationale,
      ex_top1_rationale,
      metric_note,
      status_cue_remaining_gaps,
      ex_top1_remaining_gaps
    ),
  file.path(table_dir, "appendix_table_salience_country_matrix.csv")
)

status_source_table <- status_source |>
  dplyr::filter(countable) |>
  dplyr::transmute(
    benchmark = "China status cue",
    iso3c,
    country_name,
    entry_year = as.integer(entry_year),
    source_name,
    source_type,
    source_family,
    publication_date,
    label_type,
    rank_label_english,
    evidence_strength,
    raw_file,
    url
  )

ex_source_table <- ex_source |>
  dplyr::filter(countable) |>
  dplyr::transmute(
    benchmark = "Former #1 benchmark",
    iso3c,
    country_name,
    entry_year = as.integer(entry_year),
    source_name,
    source_type,
    source_family,
    publication_date,
    label_type,
    rank_label_english,
    evidence_strength,
    raw_file,
    url
  )

countable_sources <- dplyr::bind_rows(status_source_table, ex_source_table) |>
  dplyr::arrange(country_name, benchmark, publication_date, source_name)

readr::write_csv(
  countable_sources |>
    dplyr::select(
      benchmark,
      iso3c,
      country_name,
      entry_year,
      source_name,
      source_type,
      source_family,
      publication_date,
      label_type,
      rank_label_english,
      evidence_strength,
      raw_file,
      url
    ),
  file.path(table_dir, "appendix_table_countable_sources.csv")
)

supplemental_ex_sources <- ex_source |>
  dplyr::filter(
    eligible_source,
    evidence_strength %in% c("strong", "moderate"),
    label_type == "broad_trade_partner_rank"
  ) |>
  dplyr::transmute(
    benchmark = "Former #1 benchmark context",
    iso3c,
    country_name,
    entry_year = as.integer(entry_year),
    source_name,
    source_type,
    source_family,
    publication_date,
    label_type,
    rank_label_english,
    evidence_strength,
    count_for_benchmark,
    raw_file,
    url,
    notes
  ) |>
  dplyr::arrange(country_name, publication_date, source_name)

readr::write_csv(
  supplemental_ex_sources |>
    dplyr::select(
      benchmark,
      iso3c,
      country_name,
      entry_year,
      source_name,
      source_type,
      source_family,
      publication_date,
      label_type,
      rank_label_english,
      evidence_strength,
      count_for_benchmark,
      raw_file,
      url,
      notes
    ),
  file.path(table_dir, "appendix_table_supplemental_context_sources.csv")
)

caveats <- country_matrix |>
  dplyr::mutate(
    not_recovered_type = dplyr::case_when(
      implication_for_china_status_cue_absence == "weak_observation" ~
        "not recovered - weak observation",
      implication_for_china_status_cue_absence == "more_informative_absence" ~
        "not recovered - benchmark recoverable",
      status_cue_salience == "low" ~
        "no evidence after broad search",
      TRUE ~ "observed"
    )
  ) |>
  dplyr::filter(
    status_cue_salience != "high" |
      ex_top1_coverage_code != "high" |
      nzchar(metric_note)
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    entry_year,
    not_recovered_type,
    status_cue_salience,
    ex_top1_coverage_code,
    metric_note,
    status_cue_remaining_gaps,
    ex_top1_remaining_gaps
  ) |>
  dplyr::arrange(entry_year, country_name)

readr::write_csv(
  caveats,
  file.path(table_dir, "appendix_table_measurement_caveats.csv")
)

tile_data <- comparison |>
  dplyr::select(
    iso3c,
    country_name,
    country_year,
    entry_year,
    status_cue_salience,
    ex_top1_coverage_code,
    implication_for_china_status_cue_absence
  ) |>
  tidyr::pivot_longer(
    cols = c(status_cue_salience, ex_top1_coverage_code, implication_for_china_status_cue_absence),
    names_to = "dimension",
    values_to = "raw_value"
  ) |>
  dplyr::mutate(
    dimension = dplyr::recode(
      dimension,
      status_cue_salience = "China cue",
      ex_top1_coverage_code = "Former #1 cue",
      implication_for_china_status_cue_absence = "Interpretation"
    ),
    dimension = factor(dimension, levels = c("China cue", "Former #1 cue", "Interpretation")),
    raw_value = as.character(raw_value),
    cell_status = dplyr::case_when(
      dimension %in% c("China cue", "Former #1 cue") & raw_value == "high" ~ "High",
      dimension %in% c("China cue", "Former #1 cue") & raw_value == "medium" ~ "Medium",
      dimension %in% c("China cue", "Former #1 cue") & raw_value == "low" ~ "No evidence",
      dimension %in% c("China cue", "Former #1 cue") & raw_value == "unknown" ~ "Not recovered",
      raw_value == "china_status_cue_observed" ~ "Observed China cue",
      raw_value == "more_informative_absence" ~ "Recoverable benchmark",
      raw_value == "weak_observation" ~ "Weak observation",
      TRUE ~ raw_value
    ),
    cell_status = factor(
      cell_status,
      levels = c(
        "High",
        "Medium",
        "Observed China cue",
        "Recoverable benchmark",
        "Weak observation",
        "Not recovered",
        "No evidence"
      )
    ),
    cell_label = dplyr::case_when(
      dimension == "Interpretation" ~ implication_label(raw_value),
      TRUE ~ code_label(raw_value)
    )
  )

readr::write_csv(
  tile_data |>
    dplyr::select(
      iso3c,
      country_name,
      entry_year,
      dimension,
      raw_value,
      cell_status,
      cell_label
    ),
  file.path(figure_dir, "figure_salience_evidence_ladder_data.csv")
)

status_palette <- c(
  "High" = "#1B9E77",
  "Medium" = "#A6D854",
  "Observed China cue" = "#0B6E4F",
  "Recoverable benchmark" = "#F4A261",
  "Weak observation" = "#B8BEC6",
  "Not recovered" = "#E5E7EB",
  "No evidence" = "#FFF7F7"
)

tile_text_colors <- c(
  "High" = "white",
  "Medium" = "#172018",
  "Observed China cue" = "white",
  "Recoverable benchmark" = "#1F2937",
  "Weak observation" = "#1F2937",
  "Not recovered" = "#4B5563",
  "No evidence" = "#991B1B"
)

ladder_plot <- ggplot(
  tile_data,
  aes(x = dimension, y = country_year, fill = cell_status)
) +
  geom_tile(aes(color = cell_status), linewidth = 0.7, width = 0.94, height = 0.86) +
  geom_text(
    aes(label = cell_label, color = cell_status),
    size = 2.65,
    lineheight = 0.9,
    fontface = "bold"
  ) +
  scale_fill_manual(
    values = status_palette,
    breaks = names(status_palette),
    drop = FALSE,
    name = NULL
  ) +
  scale_color_manual(
    values = c(
      tile_text_colors,
      "No evidence" = "#991B1B"
    ),
    breaks = names(status_palette),
    drop = FALSE,
    guide = "none"
  ) +
  labs(
    title = "Rank language is visible in some cases; most absences are not negative evidence",
    subtitle = stringr::str_wrap(
      "The ex-Top1 benchmark separates recoverability problems from more informative non-recovery of the China status cue.",
      width = 115
    ),
    x = NULL,
    y = NULL,
    caption = stringr::str_wrap(
      paste(
        "Data: status_cue_country_codes.csv and status_cue_vs_ex_top1_coverage.csv.",
        "Window: China entry and adjacent benchmark windows documented in the audit.",
        "Pale red/no-evidence is reserved for future low cases; no country is currently coded low."
      ),
      width = 135
    )
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 13),
    plot.subtitle = element_text(size = 9.5, margin = margin(b = 8)),
    plot.caption = element_text(size = 7.3, color = "#4B5563", hjust = 0),
    axis.text.y = element_text(size = 8.4, color = "#111827"),
    axis.text.x = element_text(size = 9, face = "bold", color = "#111827"),
    panel.grid = element_blank(),
    legend.position = "bottom",
    legend.key.width = unit(0.6, "cm"),
    legend.text = element_text(size = 8),
    plot.margin = margin(9, 10, 8, 10)
  ) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE))

summary_plot <- ggplot(
  summary_counts,
  aes(
    x = n_countries,
    y = forcats::fct_reorder(label, n_countries),
    fill = implication_for_china_status_cue_absence
  )
) +
  geom_col(width = 0.58, color = "white", linewidth = 0.4) +
  geom_text(aes(label = n_countries), hjust = -0.3, size = 3.1, fontface = "bold") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.18)), breaks = 0:9) +
  scale_fill_manual(
    values = c(
      "china_status_cue_observed" = "#0B6E4F",
      "more_informative_absence" = "#F4A261",
      "weak_observation" = "#B8BEC6"
    ),
    guide = "none"
  ) +
  labs(
    title = "Bottom line",
    x = "Countries",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 11),
    axis.text.y = element_text(size = 8.2),
    axis.text.x = element_text(size = 8),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank()
  )

main_plot <- ladder_plot / summary_plot + plot_layout(heights = c(4.6, 1.1))

ggsave(
  filename = file.path(figure_dir, "figure_salience_evidence_ladder.pdf"),
  plot = main_plot,
  width = 9.4,
  height = 8.6,
  device = grDevices::pdf
)
ggsave(
  filename = file.path(figure_dir, "figure_salience_evidence_ladder.png"),
  plot = main_plot,
  width = 9.4,
  height = 8.6,
  dpi = 320,
  device = ragg::agg_png
)

australia <- country_matrix |>
  dplyr::filter(iso3c == "AUS") |>
  dplyr::slice(1L)

if (nrow(australia) != 1L) {
  stop("Australia row not found or duplicated.")
}

australia_events <- tibble::tibble(
  metric_scope = c(
    "Aggregate trading partner\n(exports + imports,\ngoods + services)",
    "Aggregate trading partner\n(exports + imports,\ngoods + services)",
    "Export destination\n(treatment metric)",
    "Export destination\n(treatment metric)",
    "Export destination\n(treatment metric)"
  ),
  year = c(2006.5, 2008.8, 2008.7, 2009.0, australia$entry_year),
  event_label = c(
    "China reportedly overtakes Japan\nas #1 total trading partner",
    "AFR item: China #1 for\nthird consecutive year",
    "DFAT: Japan still #1\nexport market",
    "DFAT: China #1 export market;\nJapan #2",
    "Treatment entry in\nexport-rank data"
  ),
  source_note = c(
    "AFR archived as DO_NOT_COUNT broad-trade context",
    "AFR archived as DO_NOT_COUNT broad-trade context",
    "DFAT source family; countable ex-Top1 benchmark",
    "DFAT source family; countable ex-Top1 benchmark",
    "Processed treatment timing"
  ),
  evidence_status = c(
    "archived_broad_trade_context",
    "archived_broad_trade_context",
    "audited_official",
    "audited_official",
    "treatment_data"
  )
)

readr::write_csv(
  australia_events |>
    dplyr::mutate(
      australia_entry_year = australia$entry_year,
      incumbent_partner_name = australia$incumbent_partner_name,
      incumbent_export_share = australia$incumbent_export_share,
      china_export_share = australia$china_export_share
    ) |>
    dplyr::select(
      metric_scope,
      year,
      event_label,
      source_note,
      evidence_status,
      australia_entry_year,
      incumbent_partner_name,
      incumbent_export_share,
      china_export_share
    ),
  file.path(figure_dir, "figure_australia_metric_mismatch_data.csv")
)

metric_palette <- c(
  "archived_broad_trade_context" = "#7C3AED",
  "audited_official" = "#2563EB",
  "treatment_data" = "#111827"
)

australia_timeline <- ggplot(
  australia_events,
  aes(
    x = year,
    y = metric_scope,
    color = evidence_status
  )
) +
  geom_vline(
    xintercept = australia$entry_year,
    linetype = "dashed",
    linewidth = 0.5,
    color = "#111827"
  ) +
  geom_segment(
    data = tibble::tibble(
      metric_scope = unique(australia_events$metric_scope),
      x = c(2006.5, 2008.7),
      xend = c(2008.8, australia$entry_year),
      y = unique(australia_events$metric_scope),
      yend = unique(australia_events$metric_scope)
    ),
    aes(x = x, xend = xend, y = y, yend = yend),
    inherit.aes = FALSE,
    linewidth = 1.2,
    color = "#D1D5DB"
  ) +
  geom_point(size = 3.6) +
  geom_label(
  aes(label = event_label, fill = evidence_status),
  color = "white",
  size = 2.75,
  lineheight = 0.86,
  linewidth = 0,
  label.padding = unit(0.16, "lines"),
  show.legend = FALSE,
  nudge_y = c(0.18, -0.18, -0.2, 0.2, -0.2)
  ) +
  scale_color_manual(
    values = metric_palette,
    labels = c(
      "archived_broad_trade_context" = "Archived broad-trade context",
      "audited_official" = "Audited official source family",
      "treatment_data" = "Treatment timing"
    ),
    name = NULL
  ) +
  scale_fill_manual(values = metric_palette, guide = "none") +
  scale_x_continuous(
    breaks = c(2006.5, 2008, 2009, 2010),
    labels = c("2006-07", "2008", "2009", "2010"),
    limits = c(2005.85, 2010.55),
    expand = expansion(mult = c(0.02, 0.06))
  ) +
  labs(
    title = "Australia is a metric-mismatch case, not a clean absence",
    subtitle = stringr::str_wrap(
      paste0(
        "Official export-market evidence and the archived AFR press item describe different rank concepts. ",
        "Pre-entry export shares in the diagnostic data: Japan ",
        scales::percent(australia$incumbent_export_share, accuracy = 0.1),
        "; China ",
        scales::percent(australia$china_export_share, accuracy = 0.1),
        "."
      ),
      width = 110
    ),
    x = NULL,
    y = NULL,
    caption = stringr::str_wrap(
      paste(
        "Data: status_cue_vs_ex_top1_coverage.csv and appendix_table_supplemental_context_sources.csv.",
        "The AFR item is archived and coded as DO_NOT_COUNT broad-trade context, not export-destination benchmark evidence."
      ),
      width = 125
    )
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 13),
    plot.subtitle = element_text(size = 9.5, margin = margin(b = 8)),
    plot.caption = element_text(size = 7.3, color = "#4B5563", hjust = 0),
    axis.text.y = element_text(size = 8.6, face = "bold", color = "#111827"),
    axis.text.x = element_text(size = 8.4, color = "#111827"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    legend.text = element_text(size = 8),
    plot.margin = margin(8, 10, 8, 10)
  )

ggsave(
  filename = file.path(figure_dir, "figure_australia_metric_mismatch.pdf"),
  plot = australia_timeline,
  width = 9.4,
  height = 4.8,
  device = grDevices::pdf
)
ggsave(
  filename = file.path(figure_dir, "figure_australia_metric_mismatch.png"),
  plot = australia_timeline,
  width = 9.4,
  height = 4.8,
  dpi = 320,
  device = ragg::agg_png
)

markdown_table <- function(data) {
  if (nrow(data) == 0L) {
    return("_No rows._")
  }
  data_chr <- data |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
  header <- paste(names(data_chr), collapse = " | ")
  separator <- paste(rep("---", ncol(data_chr)), collapse = " | ")
  rows <- apply(data_chr, 1, function(row) paste(row, collapse = " | "))
  paste(
    c(
      paste0("| ", header, " |"),
      paste0("| ", separator, " |"),
      paste0("| ", rows, " |")
    ),
    collapse = "\n"
  )
}

recommended_table <- country_matrix |>
  dplyr::transmute(
    Country = country_name,
    Entry = entry_year,
    `China cue` = code_label(as.character(status_cue_salience)),
    `Former #1 cue` = code_label(as.character(ex_top1_coverage_code)),
    Interpretation = dplyr::case_when(
      implication_for_china_status_cue_absence == "china_status_cue_observed" ~
        "positive salience evidence",
      implication_for_china_status_cue_absence == "more_informative_absence" ~
        "benchmark recoverable; not low salience",
      TRUE ~ "not recovered / weak observation"
    )
  )

output_files <- c(
  file.path(figure_dir, "figure_salience_evidence_ladder.pdf"),
  file.path(figure_dir, "figure_salience_evidence_ladder.png"),
  file.path(figure_dir, "figure_salience_evidence_ladder_data.csv"),
  file.path(figure_dir, "figure_australia_metric_mismatch.pdf"),
  file.path(figure_dir, "figure_australia_metric_mismatch.png"),
  file.path(figure_dir, "figure_australia_metric_mismatch_data.csv"),
  file.path(table_dir, "appendix_table_salience_country_matrix.csv"),
  file.path(table_dir, "appendix_table_countable_sources.csv"),
  file.path(table_dir, "appendix_table_supplemental_context_sources.csv"),
  file.path(table_dir, "appendix_table_measurement_caveats.csv")
)

recommendations <- c(
  "# Visualization recommendations: status-cue and ex-Top1 salience",
  "",
  paste0("Generated by `", sub(paste0(root, "/"), "", script_path, fixed = TRUE), "`."),
  "",
  "## Figure 1. Recommended main figure",
  "",
  "**Title:** Rank language is visible in some cases; most absences are not negative evidence.",
  "",
  "**Caption:** Evidence matrix for treated countries in the China-top cross-country design. The first column codes public rank language about China in the entry window; the second column codes recoverability of rank language for the displaced former #1 export partner; the third column gives the audit implication. `Not recovered` denotes missing or inaccessible source evidence and should not be read as substantive silence. `No evidence` is reserved for future low-salience cases after broad documented search; no country is currently coded low. Data: `status_cue_country_codes.csv`, `ex_top1_country_codes.csv`, and `status_cue_vs_ex_top1_coverage.csv`.",
  "",
  paste0("Draft file: `", sub(paste0(root, "/"), "", file.path(figure_dir, "figure_salience_evidence_ladder.pdf"), fixed = TRUE), "`."),
  "",
  "## Figure 2. Australia panel",
  "",
  "**Title:** Australia is a metric-mismatch case, not a clean absence.",
  "",
  "**Caption:** Timeline separating two concepts: China as Australia's largest aggregate trading partner (exports plus imports, goods plus services) and China/Japan in the export-destination metric used by the treatment. The AFR item is archived and coded as `DO_NOT_COUNT` broad-trade context: it supports press salience for a broader trade hierarchy, but it does not count as export-destination benchmark evidence. Official DFAT evidence supports recoverability for export-market rank language. Data: `status_cue_vs_ex_top1_coverage.csv` and `appendix_table_supplemental_context_sources.csv`.",
  "",
  paste0("Draft file: `", sub(paste0(root, "/"), "", file.path(figure_dir, "figure_australia_metric_mismatch.pdf"), fixed = TRUE), "`."),
  "",
  "## Appendix tables",
  "",
  "1. Country matrix: `quality_reports/ex_top1_salience/tables/appendix_table_salience_country_matrix.csv`.",
  "2. Countable source evidence: `quality_reports/ex_top1_salience/tables/appendix_table_countable_sources.csv`.",
  "3. Supplemental context sources excluded from counters: `quality_reports/ex_top1_salience/tables/appendix_table_supplemental_context_sources.csv`.",
  "4. Measurement caveats and non-recovery logic: `quality_reports/ex_top1_salience/tables/appendix_table_measurement_caveats.csv`.",
  "",
  "Recommended compact country table:",
  "",
  markdown_table(recommended_table),
  "",
  "## Visual coding",
  "",
  "- `High`: saturated green; two or more independent strong/moderate sources, or equivalent news plus official evidence.",
  "- `Medium`: light green; one strong/moderate countable source or one source family.",
  "- `Not recovered`: light gray with muted text; archive/source access is insufficient, so this is not a negative case.",
  "- `No evidence`: pale red/white tile with red text/border, reserved for future `low` cases after broad documented search. It does not appear in the current data.",
  "- `Recoverable benchmark`: amber; former #1 cue is recoverable while China cue remains unrecovered in the audit; this is more informative than weak observation but still not a low-salience code.",
  "",
  "## Measurement and causal cautions",
  "",
  "- The salience audit measures recoverable public rank language, not public opinion, elite belief updating, or a causal treatment effect.",
  "- Official sources and newspapers should not be pooled without a channel distinction; official rank language is less direct evidence of public uptake than journalistic coverage.",
  "- `Unknown` means `not recovered`, not `no evidence`. No country is currently a clean low-salience negative case.",
  "- Australia and Malaysia require metric/rank-definition caveats. Australia especially separates export destination from aggregate trading partner; Malaysia has China/Hong Kong aggregation and second-largest-rank issues.",
  "- The figures should be introduced as mechanism and measurement evidence, not as causal subgroup proof.",
  "",
  "## Output files",
  "",
  paste0("- `", sub(paste0(root, "/"), "", output_files, fixed = TRUE), "`")
)

writeLines(
  recommendations,
  con = file.path(report_dir, "visualization_recommendations.md"),
  useBytes = TRUE
)

message("Wrote draft figures, tables, and recommendations to quality_reports/ex_top1_salience/.")
