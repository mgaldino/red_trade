#!/usr/bin/env Rscript

# Assess whether Liu, Pang & Vreeland (2026) variables can be reused as
# pre-treatment moderators in the red_trade cross-country China-top panel.
# Reads raw external files and existing targets only; does not run tar_make().

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(countrycode)
  library(here)
  library(tibble)
})

options(scipen = 999)

source(here::here("scripts", "functions.R"))

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
report_dir <- here::here("reports", "incumbent_salience_vreeland_reuse_2026-05-19")
processed_dir <- here::here("data", "processed", "diagnostics")
raw_dir <- here::here("data", "raw", "external", "liu_pang_vreeland_2026")
files_dir <- file.path(raw_dir, "files")

dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

output_csv <- file.path(processed_dir, "vreeland_pre_entry_moderators_2026-05-19.csv")
inventory_csv <- file.path(report_dir, "vreeland_data_files_inventory.csv")
assessment_md <- file.path(report_dir, "vreeland_data_reuse_assessment.md")

as_iso3_from_cow <- function(ccode) {
  iso3c <- countrycode::countrycode(ccode, "cown", "iso3c", warn = FALSE)
  dplyr::case_when(
    ccode == 345 ~ "SRB",
    TRUE ~ iso3c
  )
}

format_bool <- function(x) {
  ifelse(isTRUE(x), "yes", "no")
}

message("Reading existing targets: trade_data and unga_data.")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)

message("Building treatment entry table from existing functions.")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = 1990L,
  min_entry_year = 2000L
) %>%
  tibble::as_tibble()

treatment_entries <- china_top_panel %>%
  dplyr::group_by(iso3c, country_name) %>%
  dplyr::arrange(year, .by_group = TRUE) %>%
  dplyr::mutate(
    china_top_lag = dplyr::lag(china_top),
    entry = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L
  ) %>%
  dplyr::summarise(
    t0 = ifelse(any(entry, na.rm = TRUE), min(year[entry], na.rm = TRUE), NA_integer_),
    .groups = "drop"
  ) %>%
  dplyr::filter(!is.na(t0))

message("Inspecting BSAupdate.RData.")
vreeland_env <- new.env()
load(file.path(files_dir, "13378058_BSAupdate.RData"), envir = vreeland_env)
vreeland <- tibble::as_tibble(vreeland_env$datasave) %>%
  dplyr::mutate(
    iso3c = as_iso3_from_cow(ccode),
    high_level_partner = as.integer(partner_level >= 4L),
    high_level_partner_lag1 = as.integer(partner_level_lag1 >= 4L),
    bsa_with_china = as.integer(!is.na(swap_dummy) & swap_dummy == 1L),
    bsa_with_china_lag1 = as.integer(!is.na(swap_dummy_lag1) & swap_dummy_lag1 == 1L)
  )

message("Inspecting BRI_2020.tab.")
bri <- read.delim(
  file.path(files_dir, "13393235_BRI_2020.tab"),
  check.names = FALSE
) %>%
  tibble::as_tibble() %>%
  dplyr::mutate(
    iso3c = countrycode::countrycode(countryname, "country.name", "iso3c", warn = FALSE),
    iso3c = dplyr::case_when(
      countryname == "Serbia" ~ "SRB",
      TRUE ~ iso3c
    )
  ) %>%
  dplyr::group_by(iso3c) %>%
  dplyr::summarise(
    bri_mou_year = min(year, na.rm = TRUE),
    bri_countryname = dplyr::first(countryname),
    bri_region = dplyr::first(region),
    .groups = "drop"
  )

pre_entry <- treatment_entries %>%
  dplyr::left_join(
    vreeland %>%
      dplyr::select(
        iso3c,
        t0 = year,
        pre_entry_partner_level = partner_level_lag1,
        pre_entry_high_level_partner = high_level_partner_lag1,
        pre_entry_bsa_with_china = bsa_with_china_lag1
      ),
    by = c("iso3c", "t0")
  ) %>%
  dplyr::left_join(
    vreeland %>%
      dplyr::transmute(
        iso3c,
        t0 = year + 1L,
        pre_entry_partner_level_raw = level_raw
      ),
    by = c("iso3c", "t0")
  ) %>%
  dplyr::left_join(bri, by = "iso3c") %>%
  dplyr::mutate(
    pre_entry_bri_mou = !is.na(bri_mou_year) & bri_mou_year < t0,
    bri_mou_at_or_before_t0 = !is.na(bri_mou_year) & bri_mou_year <= t0,
    bri_mou_post_t0 = !is.na(bri_mou_year) & bri_mou_year > t0,
    source = "Liu, Pang & Vreeland 2026 Harvard Dataverse DOI 10.7910/DVN/MWAPWV",
    date_accessed = run_date,
    construction_note = "pre_entry_partner_level uses partner_level_lag1 on the Vreeland row for t0, equivalent to partner_level at t0 - 1; pre_entry_partner_level_raw is level_raw at t0 - 1."
  ) %>%
  dplyr::arrange(t0, iso3c) %>%
  dplyr::select(
    iso3c,
    country_name,
    t0,
    pre_entry_partner_level,
    pre_entry_high_level_partner,
    pre_entry_partner_level_raw,
    pre_entry_bsa_with_china,
    bri_mou_year,
    pre_entry_bri_mou,
    bri_mou_at_or_before_t0,
    bri_mou_post_t0,
    source,
    date_accessed,
    construction_note
  )

readr::write_excel_csv(pre_entry, output_csv, na = "")

manifest <- readr::read_csv(file.path(raw_dir, "file_manifest.csv"), show_col_types = FALSE)
inventory <- manifest %>%
  dplyr::mutate(
    inferred_role = dplyr::case_when(
      grepl("BSAupdate", original_filename) ~ "main country-year analysis data",
      grepl("BRI", original_filename) ~ "BRI MoU timing data",
      grepl("SWAPNet", original_filename) ~ "annual BSA network workbook",
      grepl("ITT_confusion", original_filename) ~ "case-level susceptibility classification",
      grepl("bsaNchina", original_filename) ~ "non-China BSA dyads",
      grepl("IMF", original_filename) ~ "IMF program data",
      grepl("\\.R$", original_filename) ~ "replication code",
      TRUE ~ "other"
    )
  ) %>%
  dplyr::select(
    original_filename,
    stored_filename,
    content_type,
    filesize,
    sha256,
    inferred_role,
    relative_path
  )

readr::write_excel_csv(inventory, inventory_csv, na = "")

summary_pre <- pre_entry %>%
  dplyr::summarise(
    n_treated = dplyr::n(),
    t0_min = min(t0, na.rm = TRUE),
    t0_max = max(t0, na.rm = TRUE),
    partner_level_coverage = sum(!is.na(pre_entry_partner_level)),
    high_level_pre = sum(pre_entry_high_level_partner == 1L, na.rm = TRUE),
    bri_any_observed = sum(!is.na(bri_mou_year)),
    bri_pre = sum(pre_entry_bri_mou, na.rm = TRUE),
    bri_post = sum(bri_mou_post_t0, na.rm = TRUE)
  )

partner_distribution <- pre_entry %>%
  dplyr::count(pre_entry_partner_level, name = "n") %>%
  dplyr::arrange(pre_entry_partner_level)

file_role_lines <- inventory %>%
  dplyr::mutate(
    line = paste0(
      "- `", original_filename, "`: ", inferred_role,
      "; type `", content_type, "`; SHA256 `", sha256, "`."
    )
  ) %>%
  dplyr::pull(line)

partner_dist_lines <- partner_distribution %>%
  dplyr::mutate(
    level = ifelse(is.na(pre_entry_partner_level), "missing", as.character(pre_entry_partner_level)),
    line = paste0("- level ", level, ": ", n)
  ) %>%
  dplyr::pull(line)

lines <- c(
  "# Liu, Pang & Vreeland (2026) data reuse assessment",
  "",
  paste0("Generated: ", run_timestamp),
  "",
  "## Source and collection",
  "",
  "- Source: Harvard Dataverse DOI `https://doi.org/10.7910/DVN/MWAPWV`.",
  "- Collection script: `scripts/data_collection/download_liu_pang_vreeland_2026_dataverse.py`.",
  "- Raw data directory: `data/raw/external/liu_pang_vreeland_2026/`.",
  "- Raw files were preserved unchanged; checksums are in `data/raw/external/liu_pang_vreeland_2026/checksums.sha256`.",
  "",
  "## File inventory",
  "",
  file_role_lines,
  "",
  "## Variables identified",
  "",
  "| File | Variable(s) | Unit | Coverage/timing | Time-varying? | Reuse assessment |",
  "|---|---|---|---|---|---|",
  paste0(
    "| `BSAupdate.RData` | `swap_dummy`, `swap_dummy_lag1`, `signdate` | country-year | 1992-2021; BSA dates 2009-2021 in raw rows | yes | Do not use as moderator for this paper; it is the LPV treatment, not a pre-treatment receptivity variable for trade-onset. |"
  ),
  paste0(
    "| `BSAupdate.RData` | `partner_level`, `partner_level_lag1`, `level_raw` | country-year | 1992-2021; 5,560 non-missing lagged country-years | yes | Usable as `pre_entry_partner_level = partner_level_lag1` at my `t0`; use only as robustness because it proxies political closeness to China. |"
  ),
  paste0(
    "| `BSAupdate.RData` | `high_level_partner = partner_level >= 4` | country-year | Derived from LPV threshold for comprehensive cooperation partnership or above | yes | Usable as pre-treatment robustness if measured at `t0 - 1`; not as post-entry/ever high-level status. |"
  ),
  paste0(
    "| `BRI_2020.tab` | `year`, `countryname`, `region` | country event | 138 country-years, 2014-2020 | event timing | Only `bri_mou_year < t0` is admissible. `ever BRI` or `bri_mou_year <= post` would be post-treatment for most treated countries. |"
  ),
  paste0(
    "| `Data_SWAPNet_panel_202207.xlsx` | BSA dyads by annual sheet | dyad-year/network | 2008-2020 sheets plus `World` | yes | Useful for LPV BSA replication, not directly needed for the trade-onset moderator. |"
  ),
  paste0(
    "| `ITT_confusion.csv` | `Comprehensive_Partner`, `BRI`, `year_BSA`, `susceptible` | BSA case | 37 LPV BSA cases | mostly static/case-level | Not reusable for my panel because it is restricted to BSA cases and partly post-treatment relative to trade entry. |"
  ),
  "",
  "## Crosswalk to my treatment entries",
  "",
  paste0("- Treated countries in the China-top panel: ", summary_pre$n_treated, "."),
  paste0("- Treatment entry/onset years: ", summary_pre$t0_min, "-", summary_pre$t0_max, "."),
  paste0("- `pre_entry_partner_level` coverage: ", summary_pre$partner_level_coverage, "/", summary_pre$n_treated, "."),
  paste0("- Countries with `pre_entry_high_level_partner == 1`: ", summary_pre$high_level_pre, "."),
  paste0("- Countries with any BRI MoU observed in LPV file: ", summary_pre$bri_any_observed, "."),
  paste0("- Countries with BRI MoU strictly before `t0`: ", summary_pre$bri_pre, "."),
  paste0("- Countries with BRI MoU only after `t0`: ", summary_pre$bri_post, "."),
  "",
  "### Distribution of pre-entry partner level",
  "",
  partner_dist_lines,
  "",
  "## Post-treatment bias assessment",
  "",
  "- `partner_level_lag1` is admissible only when read on the row for `t0`, because it equals the previous-year partnership level. This avoids conditioning on partnership upgrades after China becomes the top export destination.",
  "- `partner_level` at `t0` is less conservative because the partnership status in the entry year can be contemporaneous with or after trade entry. The diagnostic CSV therefore uses `partner_level_lag1` at `t0`.",
  "- `high_level_partner` is admissible only as `pre_entry_high_level_partner = partner_level_lag1 >= 4` at `t0`.",
  "- `BRI` is high risk if coded as ever signatory. In this panel, most observed BRI MoUs occur after `t0`, so the valid version is `pre_entry_bri_mou = bri_mou_year < t0`.",
  "",
  "## Recommendation",
  "",
  "- Use `pre_entry_partner_level` or `pre_entry_high_level_partner` only as robustness diagnostics, not as the main moderator. They are temporally usable, but conceptually close to the political-alignment mechanism.",
  "- Do not use LPV's case-level `Comprehensive_Partner` and `BRI` columns from `ITT_confusion.csv` in this panel.",
  "- Do not use `ever BRI MoU`; if used at all, use only `pre_entry_bri_mou`, and interpret cautiously because only 10 treated countries satisfy it before trade entry.",
  "",
  "## Files written",
  "",
  paste0("- `", output_csv, "`"),
  paste0("- `", inventory_csv, "`"),
  paste0("- `", assessment_md, "`")
)

writeLines(lines, con = assessment_md, useBytes = TRUE)

message("Wrote: ", output_csv)
message("Wrote: ", inventory_csv)
message("Wrote: ", assessment_md)
