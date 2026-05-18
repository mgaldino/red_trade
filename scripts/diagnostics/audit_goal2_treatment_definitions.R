#!/usr/bin/env Rscript

# Diagnostic for Revision Goal 2: harmonize treatment definitions.
# This script reads existing targets only. It does not modify _targets.R and
# does not write to the targets store.

library(targets)
library(dplyr)
library(tidyr)
library(countrycode)
library(here)
library(synthdid)

options(scipen = 999)

source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

diagnostic_date <- as.character(Sys.Date())
diagnostic_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
diagnostic_run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
nboots <- as.integer(Sys.getenv("GOAL2_NBOOTS", "100"))
compute_sdid_se <- identical(Sys.getenv("GOAL2_COMPUTE_SDID_SE", "0"), "1")
min_entry_year <- 2000L

trade_data <- tar_read(trade_data)
unga_data <- tar_read(unga_data)
final_df <- tar_read(final_df)
dpi_data <- tar_read(dpi_data)
trade_agreement_data <- tar_read(trade_agreement_data)
classified_events <- tar_read(classified_events)
usa_top_countries <- tar_read(usa_top_countries)
china_top_panel_target <- tar_read(china_top_panel)
china_top_fect_data_target <- tar_read(china_top_fect_data)

country_name <- function(iso3c) {
  countrycode::countrycode(
    iso3c,
    "iso3c",
    "country.name",
    warn = FALSE
  )
}

clean_partner_portfolio <- function(data) {
  data |>
    dplyr::filter(
      !is.na(year),
      !is.na(iso3c),
      !is.na(partner),
      iso3c != partner
    ) |>
    dplyr::mutate(value = dplyr::coalesce(value, 0))
}

build_export_destination_portfolio <- function(trade_data) {
  trade_data |>
    dplyr::transmute(
      year,
      iso3c = exporter_iso3,
      partner = importer_iso3,
      value = as.numeric(exports)
    ) |>
    clean_partner_portfolio()
}

build_import_source_portfolio <- function(trade_data) {
  trade_data |>
    dplyr::transmute(
      year,
      iso3c = importer_iso3,
      partner = exporter_iso3,
      value = as.numeric(exports)
    ) |>
    clean_partner_portfolio()
}

build_total_bilateral_portfolio <- function(trade_data) {
  exports_from_country <- trade_data |>
    dplyr::group_by(
      year,
      iso3c = exporter_iso3,
      partner = importer_iso3
    ) |>
    dplyr::summarise(export_value = sum(exports, na.rm = TRUE), .groups = "drop")

  imports_into_country <- trade_data |>
    dplyr::group_by(
      year,
      iso3c = importer_iso3,
      partner = exporter_iso3
    ) |>
    dplyr::summarise(import_value = sum(exports, na.rm = TRUE), .groups = "drop")

  dplyr::full_join(
    exports_from_country,
    imports_into_country,
    by = c("year", "iso3c", "partner")
  ) |>
    dplyr::mutate(
      export_value = dplyr::coalesce(export_value, 0),
      import_value = dplyr::coalesce(import_value, 0),
      value = export_value + import_value
    ) |>
    clean_partner_portfolio()
}

rank_china_in_portfolio <- function(portfolio, definition) {
  ranked <- portfolio |>
    dplyr::group_by(year, iso3c) |>
    dplyr::arrange(dplyr::desc(value), partner, .by_group = TRUE) |>
    dplyr::mutate(
      row_rank = dplyr::row_number(),
      min_rank = dplyr::min_rank(dplyr::desc(value)),
      portfolio_total = sum(value, na.rm = TRUE),
      top_partner = dplyr::first(partner),
      top_value = dplyr::first(value),
      second_partner = dplyr::nth(partner, 2, default = NA_character_),
      second_value = dplyr::nth(value, 2, default = NA_real_)
    ) |>
    dplyr::ungroup()

  ranked |>
    dplyr::filter(partner == "CHN") |>
    dplyr::transmute(
      definition = definition,
      iso3c,
      country_name = country_name(iso3c),
      year,
      rank_CHN = row_rank,
      min_rank_CHN = min_rank,
      china_value = value,
      portfolio_total,
      china_share = dplyr::if_else(portfolio_total > 0, value / portfolio_total, NA_real_),
      top_partner,
      top_value,
      second_partner,
      second_value,
      china_margin_over_second = dplyr::if_else(
        row_rank == 1L & !is.na(second_value),
        value - second_value,
        NA_real_
      ),
      china_gap_to_top = dplyr::if_else(
        row_rank == 1L,
        0,
        top_value - value
      ),
      china_top_raw = as.integer(row_rank == 1L & value > 0),
      china_second_raw = as.integer(row_rank == 2L & value > 0)
    )
}

make_sdid_ranked_data <- function(china_rank_data) {
  china_rank_data |>
    dplyr::transmute(
      year,
      iso3c,
      treatment_first = china_top_raw,
      treatment_second = china_second_raw
    )
}

summarise_brazil_definition <- function(china_rank_data) {
  brazil <- china_rank_data |>
    dplyr::filter(iso3c == "BRA") |>
    dplyr::arrange(year) |>
    dplyr::mutate(
      previous_top_partner = dplyr::lag(top_partner),
      previous_rank_CHN = dplyr::lag(rank_CHN),
      previous_china_share = dplyr::lag(china_share)
    )

  first_top <- brazil |>
    dplyr::filter(china_top_raw == 1L) |>
    dplyr::slice_head(n = 1)

  if (nrow(first_top) == 0L) {
    return(tibble::tibble(
      definition = unique(china_rank_data$definition)[1],
      first_china_rank1_year = NA_integer_,
      previous_top_partner = NA_character_,
      top_partner_at_onset = NA_character_,
      rank_CHN_at_onset = NA_integer_,
      china_share_at_onset = NA_real_,
      china_margin_over_second_at_onset = NA_real_,
      n_rank1_years = sum(brazil$china_top_raw == 1L, na.rm = TRUE),
      first_observed_year = min(brazil$year, na.rm = TRUE),
      last_observed_year = max(brazil$year, na.rm = TRUE)
    ))
  }

  tibble::tibble(
    definition = first_top$definition,
    first_china_rank1_year = first_top$year,
    previous_top_partner = first_top$previous_top_partner,
    top_partner_at_onset = first_top$top_partner,
    rank_CHN_at_onset = first_top$rank_CHN,
    china_share_at_onset = first_top$china_share,
    china_margin_over_second_at_onset = first_top$china_margin_over_second,
    n_rank1_years = sum(brazil$china_top_raw == 1L, na.rm = TRUE),
    first_observed_year = min(brazil$year, na.rm = TRUE),
    last_observed_year = max(brazil$year, na.rm = TRUE)
  )
}

build_variant_panel <- function(china_rank_data, did_countries, unga_data,
                                min_year = 1990L,
                                min_entry_year = 2000L) {
  rank_cols <- china_rank_data |>
    dplyr::select(
      iso3c,
      country_name,
      year,
      rank_CHN,
      min_rank_CHN,
      china_value,
      portfolio_total,
      china_share,
      top_partner,
      top_value,
      second_partner,
      second_value,
      china_margin_over_second,
      china_gap_to_top,
      china_top_raw
    )

  panel <- unga_data |>
    dplyr::filter(iso3c %in% did_countries, year >= min_year) |>
    dplyr::select(iso3c, year, abs_distance_china) |>
    dplyr::left_join(rank_cols, by = c("iso3c", "year")) |>
    dplyr::mutate(
      country_name = dplyr::coalesce(country_name, country_name(iso3c)),
      trade_observed = !is.na(rank_CHN),
      china_top_raw = dplyr::coalesce(china_top_raw, 0L),
      country_id = as.integer(as.factor(iso3c))
    ) |>
    dplyr::group_by(iso3c) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      previous_observed_year = dplyr::lag(year),
      previous_china_top_raw = dplyr::lag(china_top_raw),
      previous_trade_observed = dplyr::lag(trade_observed),
      previous_top_partner = dplyr::lag(top_partner),
      top_period_start = china_top_raw == 1L &
        dplyr::lag(china_top_raw, default = 0L) == 0L,
      top_period_id = cumsum(top_period_start)
    ) |>
    dplyr::ungroup()

  period_onsets <- panel |>
    dplyr::filter(top_period_start) |>
    dplyr::select(
      iso3c,
      top_period_id,
      entry_year = year,
      previous_observed_year_at_entry = previous_observed_year,
      previous_china_top_raw_at_entry = previous_china_top_raw,
      previous_trade_observed_at_entry = previous_trade_observed,
      previous_top_partner_at_entry = previous_top_partner
    )

  panel |>
    dplyr::left_join(period_onsets, by = c("iso3c", "top_period_id")) |>
    dplyr::mutate(
      china_top = dplyr::case_when(
        china_top_raw == 1L &
          !is.na(entry_year) &
          entry_year >= min_entry_year &
          !is.na(previous_observed_year_at_entry) &
          previous_trade_observed_at_entry == TRUE &
          !is.na(previous_china_top_raw_at_entry) &
          previous_china_top_raw_at_entry == 0L ~ 1L,
        TRUE ~ 0L
      )
    ) |>
    dplyr::arrange(country_id, year) |>
    as.data.frame()
}

summarise_status <- function(panel, treatment_col) {
  unit_summary <- panel |>
    dplyr::arrange(iso3c, year) |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::mutate(
      d = .data[[treatment_col]],
      d_lag = dplyr::lag(d),
      entry = d == 1L & dplyr::lag(d, default = 0L) == 0L,
      exit = d == 0L & dplyr::lag(d, default = 0L) == 1L
    ) |>
    dplyr::summarise(
      treated_years = sum(d == 1L, na.rm = TRUE),
      entries = sum(entry, na.rm = TRUE),
      exits = sum(exit, na.rm = TRUE),
      switches = sum(abs(diff(d)), na.rm = TRUE),
      ever_treated = any(d == 1L, na.rm = TRUE),
      left_censored = dplyr::first(d) == 1L,
      first_entry_year = {
        entry_years <- year[entry]
        if (length(entry_years) > 0L) {
          as.integer(min(entry_years, na.rm = TRUE))
        } else {
          NA_integer_
        }
      },
      .groups = "drop"
    )

  tibble::tibble(
    n_obs = nrow(panel),
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated_countries = sum(unit_summary$ever_treated, na.rm = TRUE),
    n_control_countries = sum(!unit_summary$ever_treated, na.rm = TRUE),
    n_treated_country_years = sum(panel[[treatment_col]] == 1L, na.rm = TRUE),
    n_entries = sum(unit_summary$entries, na.rm = TRUE),
    n_exits = sum(unit_summary$exits, na.rm = TRUE),
    n_switches = sum(unit_summary$switches, na.rm = TRUE),
    n_left_censored = sum(unit_summary$left_censored, na.rm = TRUE),
    first_entry_year = suppressWarnings(min(unit_summary$first_entry_year, na.rm = TRUE)),
    last_entry_year = suppressWarnings(max(unit_summary$first_entry_year, na.rm = TRUE))
  ) |>
    dplyr::mutate(
      first_entry_year = dplyr::if_else(is.infinite(first_entry_year), NA_integer_, first_entry_year),
      last_entry_year = dplyr::if_else(is.infinite(last_entry_year), NA_integer_, last_entry_year)
    )
}

summarise_variant_panel <- function(panel, definition) {
  dplyr::bind_rows(
    summarise_status(panel, "china_top_raw") |>
      dplyr::mutate(status_rule = "raw_current_rank1_status"),
    summarise_status(panel, "china_top") |>
      dplyr::mutate(status_rule = "eligible_reversal_spell_start_ge_2000")
  ) |>
    dplyr::mutate(definition = definition, .before = 1)
}

summarise_current_target <- function(panel) {
  summarise_status(panel, "china_top") |>
    dplyr::mutate(
      definition = "current_target_top_export_destination",
      status_rule = "target_china_top_panel"
    ) |>
    dplyr::select(definition, status_rule, dplyr::everything())
}

run_sdid_variant <- function(china_rank_data, definition, compute_se = FALSE) {
  brazil_first_year <- summarise_brazil_definition(china_rank_data)$first_china_rank1_year

  if (length(brazil_first_year) != 1L || is.na(brazil_first_year)) {
    return(tibble::tibble(
      definition = definition,
      brazil_treatment_year = NA_integer_,
      estimate = NA_real_,
      se_placebo = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      sdid_inference_status = "not estimated",
      error = "Brazil never reaches rank 1 under this definition."
    ))
  }

  if (brazil_first_year <= 1997L) {
    return(tibble::tibble(
      definition = definition,
      brazil_treatment_year = brazil_first_year,
      estimate = NA_real_,
      se_placebo = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      sdid_inference_status = "not estimated",
      error = "Treatment onset is too early for the existing SDiD pre-period."
    ))
  }

  ranked_for_sdid <- make_sdid_ranked_data(china_rank_data)

  tryCatch({
    synth_variant <- clean_synth_data(
      final_df,
      ranked_trade_data = ranked_for_sdid,
      dpi_data = dpi_data,
      trade_agreement_data = trade_agreement_data
    )

    fit <- simple_fit(
      data = synth_variant,
      time_treatment = brazil_first_year - 1L,
      time_end = 2016,
      filter_latin_america = FALSE
    )

    se <- if (compute_se) {
      tryCatch(
        as.numeric(se_sdid(fit)),
        error = function(e) NA_real_
      )
    } else {
      NA_real_
    }

    tibble::tibble(
      definition = definition,
      brazil_treatment_year = brazil_first_year,
      estimate = as.numeric(fit),
      se_placebo = se,
      n_obs = nrow(synth_variant),
      n_countries = dplyr::n_distinct(synth_variant$iso3c),
      sdid_inference_status = dplyr::if_else(
        compute_se,
        "placebo SE requested",
        "estimate only: placebo SE skipped in diagnostic mode"
      ),
      error = ""
    )
  }, error = function(e) {
    tibble::tibble(
      definition = definition,
      brazil_treatment_year = brazil_first_year,
      estimate = NA_real_,
      se_placebo = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      sdid_inference_status = "not estimated",
      error = conditionMessage(e)
    )
  })
}

run_fect_variant <- function(panel, definition, nboots) {
  if (!any(panel$china_top == 1L, na.rm = TRUE)) {
    return(tibble::tibble(
      definition = definition,
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_real_,
      error = "No eligible treated country-years."
    ))
  }

  tryCatch({
    fit <- run_fect_analysis(panel, method = "ife", nboots = nboots)
    s <- fect_att_summary(fit)
    tibble::tibble(
      definition = definition,
      nboots = nboots,
      att = s$att,
      se = s$se,
      ci_lo = s$ci_lo,
      ci_hi = s$ci_hi,
      p = s$p,
      r_cv = as.numeric(s$r_cv),
      error = ""
    )
  }, error = function(e) {
    tibble::tibble(
      definition = definition,
      nboots = nboots,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_real_,
      error = conditionMessage(e)
    )
  })
}

format_markdown_table <- function(data) {
  paste(capture.output(print(data, n = Inf, width = Inf)), collapse = "\n")
}

variant_portfolios <- list(
  top_export_destination = build_export_destination_portfolio(trade_data),
  top_import_source = build_import_source_portfolio(trade_data),
  top_total_bilateral_trade_partner = build_total_bilateral_portfolio(trade_data)
)

variant_rankings <- Map(
  f = rank_china_in_portfolio,
  portfolio = variant_portfolios,
  definition = names(variant_portfolios)
)

treated_usa <- classified_events |>
  dplyr::filter(displaced == "USA") |>
  dplyr::pull(iso3c)

did_countries <- unique(c(treated_usa, usa_top_countries))

brazil_audit <- dplyr::bind_rows(lapply(variant_rankings, summarise_brazil_definition))

variant_panels <- lapply(variant_rankings, function(china_rank_data) {
  build_variant_panel(
    china_rank_data = china_rank_data,
    did_countries = did_countries,
    unga_data = unga_data,
    min_year = 1990L,
    min_entry_year = min_entry_year
  )
})

cross_country_counts <- dplyr::bind_rows(
  lapply(names(variant_panels), function(definition) {
    summarise_variant_panel(variant_panels[[definition]], definition)
  }),
  summarise_current_target(china_top_panel_target)
) |>
  dplyr::arrange(definition, status_rule)

sdid_results <- dplyr::bind_rows(
  lapply(names(variant_rankings), function(definition) {
    run_sdid_variant(
      variant_rankings[[definition]],
      definition,
      compute_se = compute_sdid_se
    )
  })
)

fect_results <- dplyr::bind_rows(
  run_fect_variant(
    china_top_fect_data_target,
    "current_target_top_export_destination",
    nboots = nboots
  ) |>
    dplyr::mutate(source_panel = "china_top_fect_data"),
  dplyr::bind_rows(lapply(names(variant_panels), function(definition) {
    run_fect_variant(variant_panels[[definition]], definition, nboots = nboots) |>
      dplyr::mutate(source_panel = "rebuilt_goal2_variant_panel")
  }))
) |>
  dplyr::arrange(definition) |>
  dplyr::mutate(
    inference_status = dplyr::if_else(
      nboots < 5000L,
      "preliminary diagnostic: nboots < 5000",
      "final-scale bootstrap"
    )
  )

run_suffix <- paste0("_", diagnostic_run_id)
brazil_audit_path <- file.path(out_dir, paste0("goal2_brazil_treatment_definition_audit", run_suffix, ".csv"))
cross_country_counts_path <- file.path(out_dir, paste0("goal2_cross_country_treatment_definition_counts", run_suffix, ".csv"))
sdid_results_path <- file.path(out_dir, paste0("goal2_sdid_variant_results", run_suffix, ".csv"))
fect_results_path <- file.path(out_dir, paste0("goal2_fect_variant_results", run_suffix, ".csv"))
report_path <- file.path(out_dir, paste0(diagnostic_date, "_goal2_treatment_definition_audit", run_suffix, ".md"))

utils::write.csv(brazil_audit, brazil_audit_path, row.names = FALSE)
utils::write.csv(cross_country_counts, cross_country_counts_path, row.names = FALSE)
utils::write.csv(sdid_results, sdid_results_path, row.names = FALSE)
utils::write.csv(fect_results, fect_results_path, row.names = FALSE)

export_year <- brazil_audit$first_china_rank1_year[
  brazil_audit$definition == "top_export_destination"
]
total_year <- brazil_audit$first_china_rank1_year[
  brazil_audit$definition == "top_total_bilateral_trade_partner"
]
import_year <- brazil_audit$first_china_rank1_year[
  brazil_audit$definition == "top_import_source"
]

main_recommendation <- if (!is.na(total_year) && !is.na(export_year) && total_year == export_year) {
  paste0(
    "For Brazil, the total-bilateral-trade and export-destination definitions ",
    "turn on in the same year (", total_year, "). The paper can describe ",
    "Brazil as a top-trade-partner case if the surrounding text states that ",
    "the cross-country panel is estimated separately as an export-destination ",
    "or total-trade robustness specification."
  )
} else {
  paste0(
    "The definitions do not turn on in the same year for Brazil ",
    "(export destination = ", export_year,
    ", import source = ", import_year,
    ", total bilateral trade = ", total_year,
    "). The manuscript should not use 'top trade partner' and ",
    "'top export destination' interchangeably."
  )
}

suggested_paragraph <- paste0(
  "Empirically, I distinguish three related commercial hierarchies: ",
  "China as the largest export destination, China as the largest import source, ",
  "and China as the largest total bilateral trade partner. The preferred ",
  "cross-country estimand should be named according to the treatment actually ",
  "used in the panel. When the treatment is export-destination status, I use ",
  "'largest export destination' in hypotheses, captions, and table notes, and ",
  "reserve 'top trade partner' for statements supported by total bilateral ",
  "trade or for the Brazilian public-salience description when contemporary ",
  "coverage used that broader language. This avoids treating a rank in exports ",
  "as if it were automatically a rank in total trade."
)

sink(report_path)
cat("# Goal 2 treatment-definition audit\n\n")
cat("Date: ", diagnostic_date, "\n\n", sep = "")
cat("Run timestamp: ", diagnostic_timestamp, "\n\n", sep = "")
cat("Script: `scripts/diagnostics/audit_goal2_treatment_definitions.R`\n\n")
cat("This diagnostic reads existing targets with `targets::tar_read()` and does not modify `_targets.R` or the targets store. Fect rows are re-estimated by this script with `nboots = ", nboots, "`.\n\n", sep = "")
if (nboots < 5000L) {
  cat("Important: fect intervals and p-values from re-estimated variants are preliminary because `nboots < 5000`; use them for screening, not as citation-ready inference.\n\n")
}
if (!compute_sdid_se) {
  cat("Important: Brazil SDiD variant estimates skip placebo SEs by default in diagnostic mode. Set `GOAL2_COMPUTE_SDID_SE=1` to run the slower placebo inference.\n\n")
}

cat("## Design contract\n\n")
cat("- Unit: country-year.\n")
cat("- Brazil outcome: absolute UNGA ideal-point distance to China.\n")
cat("- Brazil estimator: SDiD, re-run by treatment-onset year and donor exclusion implied by each definition.\n")
cat("- Cross-country estimator: `fect` IFE with switching treatment, using the scope-conditioned sample built from the existing USA-benchmark targets.\n")
cat("- Eligible cross-country treatment spell: China becomes rank 1 after an observed prior non-rank-1 year, with spell start in or after ", min_entry_year, "; treatment remains on while China remains rank 1.\n\n", sep = "")

cat("## Data availability\n\n")
cat("The raw trade target is directed exports with columns `year`, `exporter_iso3`, `importer_iso3`, and `exports`. Therefore:\n\n")
cat("- `top_export_destination` is directly observed as exports from focal country to partner.\n")
cat("- `top_import_source` is reconstructed as exports from partner to focal country.\n")
cat("- `top_total_bilateral_trade_partner` is reconstructed as focal exports to partner plus partner exports to focal country.\n\n")

cat("## Brazil treatment audit\n\n")
cat("```text\n")
cat(format_markdown_table(brazil_audit))
cat("\n```\n\n")

cat("## Cross-country treatment counts\n\n")
cat("```text\n")
cat(format_markdown_table(cross_country_counts))
cat("\n```\n\n")

cat("## Brazil SDiD variant results\n\n")
cat("```text\n")
cat(format_markdown_table(sdid_results))
cat("\n```\n\n")

cat("## Cross-country fect variant results\n\n")
cat("```text\n")
cat(format_markdown_table(fect_results))
cat("\n```\n\n")

cat("## Recommendation\n\n")
cat(main_recommendation, "\n\n", sep = "")
cat("The current target is included as `current_target_top_export_destination`, re-estimated from `china_top_fect_data` by this script. It defines treatment as China becoming and holding the number-one export-destination position, independent of which partner was second or displaced.\n\n")

cat("## Suggested manuscript paragraph\n\n")
cat(suggested_paragraph, "\n\n", sep = "")

cat("## Files written\n\n")
cat("- `", brazil_audit_path, "`\n", sep = "")
cat("- `", cross_country_counts_path, "`\n", sep = "")
cat("- `", sdid_results_path, "`\n", sep = "")
cat("- `", fect_results_path, "`\n", sep = "")
cat("- `", report_path, "`\n", sep = "")
sink()

cat("Wrote:\n")
cat("- ", brazil_audit_path, "\n", sep = "")
cat("- ", cross_country_counts_path, "\n", sep = "")
cat("- ", sdid_results_path, "\n", sep = "")
cat("- ", fect_results_path, "\n", sep = "")
cat("- ", report_path, "\n", sep = "")
