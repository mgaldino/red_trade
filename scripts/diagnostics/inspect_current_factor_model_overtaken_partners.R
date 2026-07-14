#!/usr/bin/env Rscript

# Diagnostic: identify what the current factor-model treatment rule actually
# means in partner-ranking terms. The implemented rule is China outranks the
# USA, not necessarily China is the top export partner.
# This script does not modify _targets.R or write to the targets store.

library(targets)
library(dplyr)
library(tidyr)
library(countrycode)
library(here)

options(scipen = 999)

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

partner_name <- function(iso3c) {
  iso3c_chr <- as.character(iso3c)
  out <- rep(NA_character_, length(iso3c_chr))
  observed <- !is.na(iso3c_chr)

  out[observed] <- countrycode::countrycode(
    iso3c_chr[observed],
    origin = "iso3c",
    destination = "country.name",
    warn = FALSE
  )
  out
}

build_current_rank_panel <- function(trade_data, unga_data, classified_events,
                                     usa_top_countries) {
  treated_usa <- classified_events |>
    dplyr::filter(displaced == "USA") |>
    dplyr::pull(iso3c)

  did_countries <- unique(c(treated_usa, usa_top_countries))

  ranked_partners <- trade_data |>
    dplyr::group_by(year, exporter_iso3) |>
    dplyr::arrange(dplyr::desc(exports), .by_group = TRUE) |>
    dplyr::mutate(rank = dplyr::row_number()) |>
    dplyr::ungroup() |>
    dplyr::filter(exporter_iso3 %in% did_countries)

  top_partner <- ranked_partners |>
    dplyr::filter(rank == 1) |>
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      top_partner = importer_iso3,
      top_exports = exports
    )

  rank_china_usa <- ranked_partners |>
    dplyr::filter(importer_iso3 %in% c("CHN", "USA")) |>
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      partner = importer_iso3,
      rank
    ) |>
    tidyr::pivot_wider(
      names_from = partner,
      values_from = rank,
      names_prefix = "rank_"
    )

  china_rank <- ranked_partners |>
    dplyr::filter(importer_iso3 == "CHN") |>
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      rank_CHN_for_neighbors = rank
    )

  china_neighbors <- ranked_partners |>
    dplyr::inner_join(china_rank, by = c("exporter_iso3" = "iso3c", "year")) |>
    dplyr::filter(
      rank == rank_CHN_for_neighbors - 1 |
        rank == rank_CHN_for_neighbors + 1
    ) |>
    dplyr::mutate(
      neighbor_position = dplyr::case_when(
        rank == rank_CHN_for_neighbors - 1 ~ "partner_immediately_above_china",
        rank == rank_CHN_for_neighbors + 1 ~ "partner_immediately_below_china",
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      neighbor_position,
      importer_iso3
    ) |>
    tidyr::pivot_wider(
      names_from = neighbor_position,
      values_from = importer_iso3
    )

  panel <- unga_data |>
    dplyr::filter(iso3c %in% did_countries, year >= 1990) |>
    dplyr::select(iso3c, year, abs_distance_china) |>
    dplyr::left_join(rank_china_usa, by = c("iso3c", "year")) |>
    dplyr::left_join(top_partner, by = c("iso3c", "year")) |>
    dplyr::left_join(china_neighbors, by = c("iso3c", "year")) |>
    dplyr::mutate(
      china_top_current_rule = as.integer(
        !is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA)
      ),
      china_is_literal_top = !is.na(rank_CHN) & rank_CHN == 1,
      usa_observed = !is.na(rank_USA),
      country_id = as.integer(as.factor(iso3c)),
      country_name = partner_name(iso3c),
      top_partner_name = partner_name(top_partner),
      partner_above_china_name = partner_name(partner_immediately_above_china),
      partner_below_china_name = partner_name(partner_immediately_below_china)
    ) |>
    dplyr::group_by(iso3c) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      previous_observed_year = dplyr::lag(year),
      previous_top_partner = dplyr::lag(top_partner),
      previous_top_partner_name = dplyr::lag(top_partner_name),
      previous_rank_CHN = dplyr::lag(rank_CHN),
      previous_rank_USA = dplyr::lag(rank_USA),
      previous_current_rule = dplyr::lag(china_top_current_rule, default = 0L),
      current_rule_spell_start =
        china_top_current_rule == 1L & previous_current_rule == 0L,
      current_rule_spell_id = cumsum(current_rule_spell_start)
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(country_id, year)

  list(
    panel = as.data.frame(panel),
    ranked_partners = ranked_partners
  )
}

classify_onsets <- function(panel) {
  panel |>
    dplyr::filter(current_rule_spell_start) |>
    dplyr::mutate(
      effective_crossed_partner = dplyr::case_when(
        !usa_observed ~ "No observed USA rank at onset",
        rank_CHN < rank_USA ~ "USA",
        TRUE ~ "Unexpected: current rule on without China above USA"
      ),
      substantive_transition_type = dplyr::case_when(
        !usa_observed ~ "USA missing: treatment turns on because China is observed and USA is not",
        china_is_literal_top & previous_top_partner == "USA" ~ "China becomes #1 and displaces USA",
        china_is_literal_top & is.na(previous_top_partner) ~ "China is #1 with no previous observed top partner",
        china_is_literal_top & previous_top_partner != "USA" ~
          "China becomes #1, but previous top partner was not USA",
        !china_is_literal_top ~
          "China outranks USA, but another partner remains #1",
        TRUE ~ "Unclassified"
      ),
      top_partner_context = dplyr::case_when(
        china_is_literal_top ~ paste0("China is #1; previous #1 was ", previous_top_partner),
        !china_is_literal_top ~ paste0("China rank ", rank_CHN, "; current #1 is ", top_partner),
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      onset_year = year,
      previous_observed_year,
      previous_top_partner,
      previous_top_partner_name,
      previous_rank_CHN,
      previous_rank_USA,
      rank_CHN,
      rank_USA,
      top_partner,
      top_partner_name,
      partner_immediately_above_china,
      partner_above_china_name,
      partner_immediately_below_china,
      partner_below_china_name,
      china_is_literal_top,
      usa_observed,
      effective_crossed_partner,
      substantive_transition_type,
      top_partner_context
    )
}

summarise_country_first_onset <- function(onsets) {
  onsets |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::arrange(onset_year, .by_group = TRUE) |>
    dplyr::slice(1) |>
    dplyr::ungroup()
}

summarise_treated_country_years <- function(panel) {
  panel |>
    dplyr::filter(china_top_current_rule == 1L) |>
    dplyr::mutate(
      treated_year_type = dplyr::case_when(
        !usa_observed ~ "USA rank missing",
        china_is_literal_top ~ "China is #1",
        TRUE ~ "China above USA, but not #1"
      )
    ) |>
    dplyr::group_by(treated_year_type, top_partner, top_partner_name) |>
    dplyr::summarise(
      n_country_years = dplyr::n(),
      n_countries = dplyr::n_distinct(iso3c),
      .groups = "drop"
    ) |>
    dplyr::arrange(treated_year_type, dplyr::desc(n_country_years), top_partner)
}

summarise_non_top_rank_distribution <- function(panel) {
  non_top <- panel |>
    dplyr::filter(
      china_top_current_rule == 1L,
      !china_is_literal_top,
      usa_observed
    )

  total_country_years <- nrow(non_top)

  non_top |>
    dplyr::group_by(rank_CHN) |>
    dplyr::summarise(
      n_country_years = dplyr::n(),
      n_countries = dplyr::n_distinct(iso3c),
      share_country_years = n_country_years / total_country_years,
      countries = paste(sort(unique(iso3c)), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::arrange(rank_CHN)
}

summarise_non_top_rank_moments <- function(panel) {
  non_top <- panel |>
    dplyr::filter(
      china_top_current_rule == 1L,
      !china_is_literal_top,
      usa_observed
    )

  tibble::tibble(
    n_country_years = nrow(non_top),
    n_countries = dplyr::n_distinct(non_top$iso3c),
    min_rank_CHN = min(non_top$rank_CHN, na.rm = TRUE),
    p25_rank_CHN = as.numeric(stats::quantile(non_top$rank_CHN, 0.25, na.rm = TRUE)),
    median_rank_CHN = stats::median(non_top$rank_CHN, na.rm = TRUE),
    mean_rank_CHN = mean(non_top$rank_CHN, na.rm = TRUE),
    p75_rank_CHN = as.numeric(stats::quantile(non_top$rank_CHN, 0.75, na.rm = TRUE)),
    max_rank_CHN = max(non_top$rank_CHN, na.rm = TRUE)
  )
}

summarise_non_top_onset_rank_distribution <- function(onsets) {
  non_top_onsets <- onsets |>
    dplyr::filter(
      substantive_transition_type ==
        "China outranks USA, but another partner remains #1"
    )

  total_onsets <- nrow(non_top_onsets)

  non_top_onsets |>
    dplyr::group_by(rank_CHN) |>
    dplyr::summarise(
      n_onsets = dplyr::n(),
      n_countries = dplyr::n_distinct(iso3c),
      share_onsets = n_onsets / total_onsets,
      countries = paste(sort(unique(iso3c)), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::arrange(rank_CHN)
}

summarise_onsets <- function(onsets) {
  onsets |>
    dplyr::group_by(substantive_transition_type) |>
    dplyr::summarise(
      n_onsets = dplyr::n(),
      n_countries = dplyr::n_distinct(iso3c),
      countries = paste(sort(unique(iso3c)), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(n_onsets), substantive_transition_type)
}

summarise_country_treatment <- function(panel) {
  panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      treated_years = sum(china_top_current_rule),
      treatment_spells = sum(current_rule_spell_start),
      first_on = ifelse(
        any(china_top_current_rule == 1L),
        min(year[china_top_current_rule == 1L]),
        NA_integer_
      ),
      last_on = ifelse(
        any(china_top_current_rule == 1L),
        max(year[china_top_current_rule == 1L]),
        NA_integer_
      ),
      treated_years_china_literal_top =
        sum(china_top_current_rule == 1L & china_is_literal_top),
      treated_years_china_not_literal_top =
        sum(china_top_current_rule == 1L & !china_is_literal_top),
      min_china_rank_when_treated =
        suppressWarnings(min(rank_CHN[china_top_current_rule == 1L], na.rm = TRUE)),
      max_china_rank_when_treated =
        suppressWarnings(max(rank_CHN[china_top_current_rule == 1L], na.rm = TRUE)),
      .groups = "drop"
    ) |>
    dplyr::filter(treated_years > 0) |>
    dplyr::mutate(
      min_china_rank_when_treated = ifelse(
        is.infinite(min_china_rank_when_treated),
        NA_real_,
        min_china_rank_when_treated
      ),
      max_china_rank_when_treated = ifelse(
        is.infinite(max_china_rank_when_treated),
        NA_real_,
        max_china_rank_when_treated
      )
    ) |>
    dplyr::arrange(first_on, iso3c)
}

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
classified_events <- tar_read(classified_events)
usa_top_countries <- tar_read(usa_top_countries)
current_panel_target <- tar_read(switching_panel)

rank_objects <- build_current_rank_panel(
  trade_data,
  unga_data,
  classified_events,
  usa_top_countries
)
current_rank_panel <- rank_objects$panel

rule_compare <- current_rank_panel |>
  dplyr::select(iso3c, year, rebuilt_china_top = china_top_current_rule) |>
  dplyr::left_join(
    current_panel_target |>
      dplyr::select(iso3c, year, target_china_top = china_top),
    by = c("iso3c", "year")
  )

panel_validation <- tibble::tibble(
  n_obs_rank_panel = nrow(current_rank_panel),
  n_obs_target_panel = nrow(current_panel_target),
  n_countries_rank_panel = dplyr::n_distinct(current_rank_panel$iso3c),
  n_countries_target_panel = dplyr::n_distinct(current_panel_target$iso3c),
  duplicate_country_years = sum(duplicated(current_rank_panel[, c("iso3c", "year")])),
  missing_outcome = sum(is.na(current_rank_panel$abs_distance_china)),
  missing_treatment = sum(is.na(current_rank_panel$china_top_current_rule)),
  current_rule_matches_target = all(
    rule_compare$rebuilt_china_top == rule_compare$target_china_top
  )
)

if (!panel_validation$current_rule_matches_target) {
  stop("Rebuilt current treatment rule does not match switching_panel target.")
}

if (panel_validation$duplicate_country_years > 0) {
  stop("Panel validation failed: duplicate country-years detected.")
}

if (panel_validation$missing_treatment > 0) {
  stop("Panel validation failed: missing treatment values detected.")
}

onsets <- classify_onsets(current_rank_panel)
country_first_onsets <- summarise_country_first_onset(onsets)
treated_country_year_summary <- summarise_treated_country_years(current_rank_panel)
non_top_rank_distribution <- summarise_non_top_rank_distribution(current_rank_panel)
non_top_rank_moments <- summarise_non_top_rank_moments(current_rank_panel)
non_top_onset_rank_distribution <- summarise_non_top_onset_rank_distribution(onsets)
onset_summary <- summarise_onsets(onsets)
country_treatment_summary <- summarise_country_treatment(current_rank_panel)

write.csv(
  panel_validation,
  file.path(out_dir, "current_factor_model_overtaken_panel_validation.csv"),
  row.names = FALSE
)
write.csv(
  onset_summary,
  file.path(out_dir, "current_factor_model_overtaken_onset_summary.csv"),
  row.names = FALSE
)
write.csv(
  onsets,
  file.path(out_dir, "current_factor_model_overtaken_spell_onsets.csv"),
  row.names = FALSE
)
write.csv(
  country_first_onsets,
  file.path(out_dir, "current_factor_model_overtaken_country_first_onsets.csv"),
  row.names = FALSE
)
write.csv(
  treated_country_year_summary,
  file.path(out_dir, "current_factor_model_overtaken_treated_year_top_partners.csv"),
  row.names = FALSE
)
write.csv(
  non_top_rank_distribution,
  file.path(out_dir, "current_factor_model_overtaken_non_top_rank_distribution.csv"),
  row.names = FALSE
)
write.csv(
  non_top_rank_moments,
  file.path(out_dir, "current_factor_model_overtaken_non_top_rank_moments.csv"),
  row.names = FALSE
)
write.csv(
  non_top_onset_rank_distribution,
  file.path(out_dir, "current_factor_model_overtaken_non_top_onset_rank_distribution.csv"),
  row.names = FALSE
)
write.csv(
  country_treatment_summary,
  file.path(out_dir, "current_factor_model_overtaken_country_treatment_summary.csv"),
  row.names = FALSE
)

report_path <- file.path(out_dir, "2026-05-14_current_factor_model_overtaken_partners.md")
sink(report_path)
cat("# Current factor-model treatment: who is China overtaking?\n\n")
cat("Date: 2026-05-14\n\n")
cat("The current implementation marks treatment when China outranks the USA among export destinations, or when China is observed and the USA rank is missing. It does not require China to be the top export partner.\n\n")
cat("## Validation\n\n")
print(panel_validation)
cat("\n## Spell-onset classification\n\n")
print(onset_summary, n = nrow(onset_summary))
cat("\n## Treated country-years by current top partner\n\n")
print(treated_country_year_summary, n = nrow(treated_country_year_summary))
cat("\n## China rank when treatment is on but China is not #1\n\n")
print(non_top_rank_moments)
cat("\n")
print(non_top_rank_distribution, n = nrow(non_top_rank_distribution))
cat("\n## China rank at non-top treatment spell onsets\n\n")
print(non_top_onset_rank_distribution, n = nrow(non_top_onset_rank_distribution))
cat("\n## First onset by country\n\n")
print(country_first_onsets, n = nrow(country_first_onsets))
cat("\n## Country treatment summary\n\n")
print(country_treatment_summary, n = nrow(country_treatment_summary))
sink()

print(onset_summary)
cat("\nWrote:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_panel_validation.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_onset_summary.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_spell_onsets.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_country_first_onsets.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_treated_year_top_partners.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_non_top_rank_distribution.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_non_top_rank_moments.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_non_top_onset_rank_distribution.csv"), "\n", sep = "")
cat("- ", file.path(out_dir, "current_factor_model_overtaken_country_treatment_summary.csv"), "\n", sep = "")
