#!/usr/bin/env Rscript

# Country-level coding and comparison for the ex-Top1 salience benchmark.
# Reads local CSVs only; does not run or modify targets.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

args_all <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_all, value = TRUE)
script_path <- if (length(file_arg) > 0L) {
  normalizePath(sub("^--file=", "", file_arg[[1]]))
} else {
  normalizePath("scripts/diagnostics/analyze_ex_top1_salience.R")
}
root <- normalizePath(file.path(dirname(script_path), "..", ".."))

processed_dir <- file.path(root, "data", "processed", "ex_top1_salience")
report_dir <- file.path(root, "quality_reports", "ex_top1_salience")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

source_evidence_path <- file.path(
  processed_dir,
  "ex_top1_source_evidence.csv"
)
incumbent_candidates <- sort(list.files(
  file.path(root, "data", "processed", "diagnostics"),
  pattern = "^incumbent_salience_moderators_.*\\.csv$",
  full.names = TRUE
))
if (length(incumbent_candidates) == 0L) {
  stop("No incumbent_salience_moderators_*.csv file found.")
}
incumbent_path <- incumbent_candidates[[length(incumbent_candidates)]]
status_country_path <- file.path(
  root,
  "data",
  "processed",
  "status_cue_salience",
  "status_cue_country_codes.csv"
)
sample_path <- file.path(
  root,
  "quality_reports",
  "cross_country_sample",
  "china_top_absorbing_cs_sample_fect_treated_countries.csv"
)

country_codes_path <- file.path(processed_dir, "ex_top1_country_codes.csv")
comparison_path <- file.path(
  processed_dir,
  "status_cue_vs_ex_top1_coverage.csv"
)
report_path <- file.path(report_dir, "ex_top1_salience_report.md")

bool <- function(x) {
  tolower(as.character(x)) == "true"
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "", format(round(x, digits), nsmall = digits, scientific = FALSE))
}

collapse_unique <- function(x) {
  x <- unique(x[!is.na(x) & nzchar(x)])
  if (length(x) == 0L) {
    return("")
  }
  paste(sort(x), collapse = "; ")
}

window_ok <- function(publication_date, entry_year) {
  year <- suppressWarnings(as.integer(substr(publication_date, 1L, 4L)))
  !is.na(year) & year >= (entry_year - 1L) & year <= (entry_year + 1L)
}

sample <- readr::read_csv(sample_path, show_col_types = FALSE) %>%
  dplyr::filter(.data$model == "No covariates") %>%
  dplyr::transmute(
    iso3c = .data$iso3c,
    country_name = .data$country_name,
    entry_year = as.integer(.data$first_treated_year)
  )

status_country <- readr::read_csv(status_country_path, show_col_types = FALSE) %>%
  dplyr::select(
    iso3c,
    status_cue_salience = salience_code,
    status_cue_rationale = coding_rationale
  )

evidence <- readr::read_csv(source_evidence_path, show_col_types = FALSE) %>%
  dplyr::mutate(
    entry_year = as.integer(.data$entry_year),
    evidence_year = as.integer(.data$evidence_year),
    incumbent_rank_year = as.integer(.data$incumbent_rank_year),
    incumbent_export_share = as.numeric(.data$incumbent_export_share),
    china_export_share = as.numeric(.data$china_export_share),
    eligible_source = bool(.data$eligible_source),
    explicit_rank_language = bool(.data$explicit_rank_language),
    mentions_incumbent_trade = bool(.data$mentions_incumbent_trade),
    mentions_rank_change_or_displacement = bool(
      .data$mentions_rank_change_or_displacement
    ),
    count_for_benchmark = bool(.data$count_for_benchmark),
    notes = tidyr::replace_na(.data$notes, ""),
    in_window = window_ok(.data$publication_date, .data$entry_year),
    countable = .data$count_for_benchmark &
      .data$eligible_source &
      .data$in_window &
      .data$evidence_strength %in% c("strong", "moderate") &
      !stringr::str_detect(.data$notes, "^DO_NOT_COUNT"),
    broad_trade_partner_context = .data$eligible_source &
      .data$in_window &
      .data$evidence_strength %in% c("strong", "moderate") &
      .data$label_type == "broad_trade_partner_rank",
    rank_or_displacement = .data$countable &
      .data$explicit_rank_language &
      .data$label_type %in% c("incumbent_export_rank", "incumbent_trade_rank", "displacement"),
    trade_only = .data$countable &
      .data$mentions_incumbent_trade &
      .data$label_type == "trade_coverage"
  )

incumbent_base <- readr::read_csv(incumbent_path, show_col_types = FALSE) %>%
  dplyr::filter(.data$iso3c %in% sample$iso3c) %>%
  dplyr::transmute(
    iso3c = .data$iso3c,
    entry_year = as.integer(.data$t0),
    incumbent_partner_name = .data$displaced_partner_name,
    incumbent_partner_iso3 = .data$displaced_partner,
    incumbent_rank_year = as.integer(.data$t0) - 1L,
    incumbent_rank_source_file = sub(paste0(root, "/"), "", incumbent_path, fixed = TRUE),
    incumbent_export_share = as.numeric(.data$displaced_export_share_t0_minus_1),
    china_export_share = as.numeric(.data$china_export_share_t0_minus_1)
  )

counts <- evidence %>%
  dplyr::group_by(iso3c) %>%
  dplyr::summarise(
    n_sources_total = dplyr::n(),
    n_countable_sources = sum(.data$countable, na.rm = TRUE),
    n_rank_or_displacement_sources = sum(.data$rank_or_displacement, na.rm = TRUE),
    n_trade_coverage_sources = sum(.data$trade_only, na.rm = TRUE),
    n_official_sources = sum(
      .data$countable &
        .data$source_type %in% c(
          "official_statistics",
          "official_report",
          "official_speech",
          "government_news"
        ),
      na.rm = TRUE
    ),
    n_news_sources = sum(
      .data$countable &
        .data$source_type %in% c(
          "local_news",
          "business_news",
          "national_news_agency"
        ),
      na.rm = TRUE
    ),
    n_broad_trade_partner_context_sources = sum(
      .data$broad_trade_partner_context,
      na.rm = TRUE
    ),
    n_independent_sources = dplyr::n_distinct(.data$source_name[.data$countable]),
    principal_sources = collapse_unique(.data$source_name[.data$countable]),
    principal_labels = collapse_unique(.data$rank_label_english[.data$rank_or_displacement]),
    broad_trade_partner_context_sources = collapse_unique(
      .data$source_name[.data$broad_trade_partner_context]
    ),
    broad_trade_partner_context_labels = collapse_unique(
      .data$rank_label_english[.data$broad_trade_partner_context]
    ),
    conflict_notes = collapse_unique(.data$notes[stringr::str_detect(.data$label_type, "conflict")]),
    .groups = "drop"
  )

country_codes <- sample %>%
  dplyr::left_join(incumbent_base, by = c("iso3c", "entry_year")) %>%
  dplyr::left_join(counts, by = "iso3c") %>%
  dplyr::mutate(
    dplyr::across(
      c(
        n_sources_total,
        n_countable_sources,
        n_rank_or_displacement_sources,
        n_trade_coverage_sources,
        n_official_sources,
        n_news_sources,
        n_broad_trade_partner_context_sources,
        n_independent_sources
      ),
      ~ tidyr::replace_na(.x, 0L)
    ),
    incumbent_identification_code = dplyr::case_when(
      is.na(.data$incumbent_partner_iso3) | !nzchar(.data$incumbent_partner_iso3) ~ "incumbent_unknown",
      TRUE ~ "incumbent_identified"
    ),
    ex_top1_coverage_code = dplyr::case_when(
      .data$incumbent_identification_code == "incumbent_unknown" ~ "unknown",
      .data$n_rank_or_displacement_sources >= 2L &
        .data$n_independent_sources >= 2L ~ "high",
      .data$n_rank_or_displacement_sources >= 1L &
        .data$n_news_sources >= 1L &
        .data$n_official_sources >= 1L ~ "high",
      .data$n_rank_or_displacement_sources >= 1L ~ "medium",
      .data$n_trade_coverage_sources >= 2L &
        .data$n_independent_sources >= 1L ~ "medium",
      TRUE ~ "unknown"
    ),
    coding_rationale = dplyr::case_when(
      .data$ex_top1_coverage_code == "high" ~ paste0(
        .data$n_rank_or_displacement_sources,
        " countable source(s) use rank/displacement language for the incumbent; sources: ",
        .data$principal_sources,
        "."
      ),
      .data$ex_top1_coverage_code == "medium" &
        .data$n_rank_or_displacement_sources > .data$n_independent_sources ~ paste0(
          .data$n_rank_or_displacement_sources,
          " countable row(s) from one independent source/source family use incumbent rank/status language; source: ",
          .data$principal_sources,
          "."
        ),
      .data$ex_top1_coverage_code == "medium" &
        .data$n_rank_or_displacement_sources >= 1L ~ paste0(
          "One countable source uses incumbent rank/status language; source: ",
          .data$principal_sources,
          "."
        ),
      .data$ex_top1_coverage_code == "medium" ~ paste0(
        "Multiple countable local/news sources cover trade with the incumbent but without a clear top-rank label; sources: ",
        .data$principal_sources,
        "."
      ),
      .data$incumbent_identification_code == "incumbent_unknown" ~
        "The incumbent partner could not be identified from the local diagnostic input.",
      TRUE ~
        "No countable local/official source establishes incumbent-rank uptake in the window."
    ),
    remaining_gaps = dplyr::case_when(
      .data$iso3c == "SLB" ~
        "Need Solomon Islands local/official 2002-2004 archive access; only international macro context was located.",
      .data$iso3c == "AGO" ~
        "Need Angolan local/official 2006-2008 source; located evidence is third-country context only.",
      .data$iso3c == "MYS" ~
        "Preserve rank-definition caveat: MITI separately reports China as second-largest in 2009, and China/Hong Kong aggregation may alter interpretation.",
      .data$iso3c == "SLE" ~
        "Statistics Sierra Leone 2013 conflicts with Belgium-as-incumbent for the China-entry window.",
      .data$iso3c == "MMR" ~
        "Available source ranks Thailand second and is not Myanmar-local; audit fiscal/calendar timing before inference.",
      .data$iso3c == "AUS" & .data$n_broad_trade_partner_context_sources > 0L ~
        "AFR broad aggregate-trading-partner source is archived as DO_NOT_COUNT context: it documents metric mismatch and pre-existing salience, not export-destination uptake.",
      .data$iso3c == "GAB" ~
        "No countable local/official coverage of Congo-Brazzaville as incumbent was recovered.",
      .data$iso3c == "SAU" ~
        "No countable Saudi-local source in this pass establishes the United States as pre-entry export #1.",
      .data$ex_top1_coverage_code == "unknown" ~
        "Additional local-language archive search is required before treating absence as substantive.",
      TRUE ~ "No major gap for the benchmark code; still verify raw files before manuscript use."
    )
  ) %>%
  dplyr::select(
    iso3c,
    country_name,
    entry_year,
    incumbent_identification_code,
    incumbent_partner_name,
    incumbent_partner_iso3,
    incumbent_rank_year,
    incumbent_rank_source_file,
    incumbent_export_share,
    china_export_share,
    n_sources_total,
    n_countable_sources,
    n_rank_or_displacement_sources,
    n_trade_coverage_sources,
    n_official_sources,
    n_news_sources,
    n_broad_trade_partner_context_sources,
    n_independent_sources,
    principal_sources,
    principal_labels,
    broad_trade_partner_context_sources,
    broad_trade_partner_context_labels,
    ex_top1_coverage_code,
    coding_rationale,
    remaining_gaps
  ) %>%
  dplyr::arrange(.data$entry_year, .data$iso3c)

comparison <- country_codes %>%
  dplyr::left_join(status_country, by = "iso3c") %>%
  dplyr::mutate(
    implication_for_china_status_cue_absence = dplyr::case_when(
      .data$status_cue_salience == "unknown" &
        .data$ex_top1_coverage_code %in% c("high", "medium") ~
        "more_informative_absence",
      .data$status_cue_salience == "unknown" &
        .data$ex_top1_coverage_code %in% c("unknown", "low") ~
        "weak_observation",
      .data$status_cue_salience %in% c("high", "medium") ~
        "china_status_cue_observed",
      TRUE ~ "not_applicable"
    )
  ) %>%
  dplyr::select(
    iso3c,
    country_name,
    entry_year,
    status_cue_salience,
    ex_top1_coverage_code,
    implication_for_china_status_cue_absence,
    incumbent_partner_name,
    incumbent_partner_iso3,
    incumbent_rank_year,
    incumbent_export_share,
    china_export_share,
    principal_sources,
    principal_labels,
    n_broad_trade_partner_context_sources,
    broad_trade_partner_context_sources,
    broad_trade_partner_context_labels,
    coding_rationale,
    remaining_gaps
  ) %>%
  dplyr::arrange(.data$entry_year, .data$iso3c)

readr::write_csv(country_codes, country_codes_path)
readr::write_csv(comparison, comparison_path)

code_summary <- country_codes %>%
  dplyr::count(.data$ex_top1_coverage_code, name = "n") %>%
  dplyr::arrange(.data$ex_top1_coverage_code)

unknown_implications <- comparison %>%
  dplyr::filter(.data$status_cue_salience == "unknown") %>%
  dplyr::select(
    country_name,
    entry_year,
    incumbent_partner_name,
    ex_top1_coverage_code,
    implication_for_china_status_cue_absence
  )

more_informative <- unknown_implications %>%
  dplyr::filter(.data$implication_for_china_status_cue_absence == "more_informative_absence") %>%
  dplyr::pull(.data$country_name)

weak_observation <- unknown_implications %>%
  dplyr::filter(.data$implication_for_china_status_cue_absence == "weak_observation") %>%
  dplyr::pull(.data$country_name)

source_table <- country_codes %>%
  dplyr::mutate(
    incumbent_export_share = fmt_num(.data$incumbent_export_share),
    china_export_share = fmt_num(.data$china_export_share)
  ) %>%
  dplyr::select(
    Country = country_name,
    Entry = entry_year,
    Incumbent = incumbent_partner_name,
    `Ex-Top1 Code` = ex_top1_coverage_code,
    Sources = principal_sources,
    Labels = principal_labels,
    `Broad Trade Context Sources` = broad_trade_partner_context_sources,
    `Broad Trade Context Labels` = broad_trade_partner_context_labels,
    `Inc. Share` = incumbent_export_share,
    `China Share` = china_export_share
  )

table_to_md <- function(data) {
  out <- c(
    paste(names(data), collapse = " | "),
    paste(rep("---", ncol(data)), collapse = " | ")
  )
  rows <- apply(data, 1, function(x) paste(x, collapse = " | "))
  paste(c(out, rows), collapse = "\n")
}

report <- c(
  "# Ex-Top1 Salience Benchmark Report",
  "",
  paste0("Generated: ", Sys.Date()),
  "",
  "## Purpose",
  "",
  "This benchmark asks whether local/news or official sources recoverably covered the export partner that was #1 immediately before China entry. It is designed to distinguish weak observation from more informative absence in the original China status-cue salience coding.",
  "",
  "## Inputs",
  "",
  paste0("- Source evidence: `", file.path("data/processed/ex_top1_salience", "ex_top1_source_evidence.csv"), "`"),
  paste0("- Country codes: `", file.path("data/processed/ex_top1_salience", "ex_top1_country_codes.csv"), "`"),
  paste0("- Comparison CSV: `", file.path("data/processed/ex_top1_salience", "status_cue_vs_ex_top1_coverage.csv"), "`"),
  "- Incumbent identification: latest `data/processed/diagnostics/incumbent_salience_moderators_*.csv`.",
  "- The scripts did not run `targets::tar_make()`.",
  "",
  "## Classification Summary",
  "",
  table_to_md(code_summary),
  "",
  "## Country-Level Evidence",
  "",
  table_to_md(source_table),
  "",
  "## Interpretation for China Status-Cue Unknowns",
  "",
  paste0(
    "More informative absences: ",
    ifelse(length(more_informative) > 0L, paste(more_informative, collapse = ", "), "none"),
    "."
  ),
  "",
  paste0(
    "Weak observations: ",
    ifelse(length(weak_observation) > 0L, paste(weak_observation, collapse = ", "), "none"),
    "."
  ),
  "",
  "The more-informative group should still be interpreted conservatively. For Malaysia, the benchmark shows recoverable official rank language about Singapore, but the original China status-cue file also flags rank-definition and China/Hong Kong aggregation issues. For Australia, official DFAT sources recover both Japan's incumbent rank and explicit China displacement language; the AFR item is archived separately as broad aggregate-trade context and remains excluded from the export-destination benchmark.",
  "",
  "## Recommended Use",
  "",
  "Use this benchmark as a recoverability diagnostic, not as an automatic recode of China status-cue salience. Cases where the ex-Top1 benchmark is high or medium and China status-cue salience remains unknown deserve targeted follow-up before any manuscript claim that public rank language was absent.",
  "",
  "## Fact-Check Status",
  "",
  "Independent fact-check status: `PASS` without reservations for the original ex-Top1 benchmark after a second audit round. The 2026-05-23 AFR addition for Australia is archived and coded as `DO_NOT_COUNT` broad-trade context; it has not received a separate independent fact-check and does not enter the export-destination benchmark counters."
)

writeLines(report, report_path, useBytes = TRUE)

message("Wrote ", country_codes_path)
message("Wrote ", comparison_path)
message("Wrote ", report_path)
