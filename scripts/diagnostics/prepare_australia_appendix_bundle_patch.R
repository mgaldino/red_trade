# Prepare the corrected public-cue appendix bundle, with Australia as the focal case.
#
# This diagnostic reads two existing targets and the existing appendix bundle.
# It joins the current 14-country public-cue codes, records the legacy source-
# audit chronology separately, and writes a new RDS. It never calls tar_make
# and does not modify targets or raw inputs.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(readr)
  library(tibble)
})

repo_root <- normalizePath(getwd(), mustWork = TRUE)
store_path <- file.path(repo_root, "_targets")
diagnostic_output_dir <- file.path(
  repo_root,
  "data",
  "processed",
  "diagnostics",
  "RIO_20260905_australia"
)
output_path <- file.path(diagnostic_output_dir, "australia_appendix_tables_patch.rds")
status_country_path <- file.path(
  repo_root,
  "data",
  "processed",
  "status_cue_salience",
  "status_cue_country_codes.csv"
)

stopifnot(
  file.exists(file.path(
    repo_root,
    "_targets",
    "objects",
    "china_top_m2_goods_status_current_unit_summary"
  ))
)

sha256_file <- function(path) {
  stopifnot(file.exists(path))
  digest::digest(path, algo = "sha256", file = TRUE)
}

rel_path <- function(path) {
  sub(paste0("^", normalizePath(repo_root, mustWork = TRUE), "/?"), "", normalizePath(path, mustWork = TRUE))
}

# Read the serialized target objects directly.  This keeps the diagnostic a
# read-only consumer of the existing store and avoids any target execution or
# process orchestration.
appendix_tables <- readRDS(file.path(
  store_path,
  "objects",
  "ex_top1_salience_appendix_tables"
))
status_summary <- readRDS(file.path(
  store_path,
  "objects",
  "china_top_m2_goods_status_current_unit_summary"
))

stopifnot(
  is.list(appendix_tables),
  all(c(
    "salience_country_matrix",
    "measurement_caveats",
    "supplemental_context_sources",
    "recoverability_table",
    "afr_context_table"
  ) %in% names(appendix_tables)),
  all(c(
    "min_duration_years",
    "sample",
    "iso3c",
    "ever_treated",
    "first_treat"
  ) %in% names(status_summary))
)

legacy_matrix <- appendix_tables$salience_country_matrix
australia_legacy <- legacy_matrix |>
  dplyr::filter(iso3c == "AUS") |>
  dplyr::select(iso3c, country_name, source_audit_year = entry_year)
stopifnot(nrow(australia_legacy) == 1L, australia_legacy$source_audit_year == 2010L)

current_summary <- status_summary |>
  dplyr::filter(
    min_duration_years == 5L,
    sample == "risk_set_restricted",
    ever_treated,
    iso3c == "AUS"
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    treatment_year_current = first_treat,
    treated_years,
    untreated_years,
    first_year_in_panel,
    last_year_in_panel
  ) |>
  dplyr::mutate(treatment_year_current = as.integer(treatment_year_current))
stopifnot(
  nrow(current_summary) == 1L,
  current_summary$treatment_year_current == 2009L
)

current_status <- readr::read_csv(status_country_path, show_col_types = FALSE) |>
  dplyr::filter(iso3c %in% legacy_matrix$iso3c) |>
  dplyr::transmute(
    iso3c,
    current_audit_entry_year = as.integer(entry_year),
    current_salience = as.character(salience_code),
    current_news_sources = as.numeric(n_newspaper_sources_strong),
    current_official_sources = as.numeric(n_official_sources_strong),
    current_total_sources = as.numeric(n_total_strong_or_moderate),
    current_rationale = coding_rationale,
    current_remaining_gaps = remaining_gaps
  )
stopifnot(
  nrow(current_status) == nrow(legacy_matrix),
  setequal(current_status$iso3c, legacy_matrix$iso3c)
)
australia_status <- current_status |>
  dplyr::filter(iso3c == "AUS")
stopifnot(
  nrow(australia_status) == 1L,
  australia_status$current_audit_entry_year == 2009L,
  australia_status$current_salience == "high",
  australia_status$current_news_sources == 1,
  australia_status$current_official_sources == 1,
  australia_status$current_total_sources == 2
)

# Compare the legacy appendix chronology with both the current treatment panel
# and the current public-cue audit. The latter governs displayed cue status and
# source-window years; treatment-onset differences remain visible separately.
appendix_codes <- legacy_matrix |>
  dplyr::distinct(
    iso3c,
    country_name,
    legacy_entry_year = entry_year,
    legacy_salience = status_cue_salience
  ) |>
  dplyr::mutate(legacy_salience = as.character(legacy_salience))
current_summary_all <- status_summary |>
  dplyr::filter(
    min_duration_years == 5L,
    sample == "risk_set_restricted",
    ever_treated,
    iso3c %in% appendix_codes$iso3c
  ) |>
  dplyr::transmute(
    iso3c,
    current_treatment_year = as.integer(first_treat),
    current_treated_years = treated_years
  )
all_country_comparison <- appendix_codes |>
  dplyr::left_join(current_summary_all, by = "iso3c") |>
  dplyr::left_join(current_status, by = "iso3c") |>
  dplyr::mutate(
    treatment_delta = current_treatment_year - legacy_entry_year,
    audit_window_delta = current_audit_entry_year - legacy_entry_year,
    treatment_differs = !is.na(treatment_delta) & treatment_delta != 0L,
    audit_window_differs = !is.na(audit_window_delta) & audit_window_delta != 0L,
    salience_differs = legacy_salience != current_salience,
    applied_in_this_patch = audit_window_differs | salience_differs
  ) |>
  dplyr::arrange(iso3c)

patched_tables <- appendix_tables
patched_tables$salience_country_matrix <- legacy_matrix |>
  dplyr::left_join(current_status, by = "iso3c") |>
  dplyr::mutate(
    entry_year = current_audit_entry_year,
    status_cue_salience = current_salience,
    implication_for_china_status_cue_absence = dplyr::case_when(
      current_salience != "unknown" ~ "china_status_cue_observed",
      as.character(ex_top1_coverage_code) %in% c("high", "medium") ~ "more_informative_absence",
      TRUE ~ "weak_observation"
    ),
    n_china_sources = current_total_sources,
    n_china_news_sources = current_news_sources,
    n_china_official_sources = current_official_sources,
    status_cue_rationale = current_rationale,
    metric_note = dplyr::if_else(
      iso3c == "AUS",
      "AFR and DFAT establish high broad public-cue salience; neither public label is strictly M2 goods-only.",
      metric_note
    ),
    status_cue_remaining_gaps = current_remaining_gaps
  ) |>
  dplyr::select(-dplyr::starts_with("current_"))
patched_tables$measurement_caveats <- appendix_tables$measurement_caveats |>
  dplyr::left_join(current_status, by = "iso3c") |>
  dplyr::mutate(
    entry_year = current_audit_entry_year,
    not_recovered_type = dplyr::case_when(
      iso3c == "AUS" ~ "cue observed - metric mismatch",
      current_salience == "unknown" & as.character(ex_top1_coverage_code) %in% c("high", "medium") ~
        "not recovered - benchmark recoverable",
      current_salience == "unknown" ~ "not recovered - weak observation",
      TRUE ~ "observed"
    ),
    status_cue_salience = current_salience,
    metric_note = dplyr::if_else(
      iso3c == "AUS",
      "AFR and DFAT establish high broad public-cue salience; neither public label is strictly M2 goods-only.",
      metric_note
    ),
    status_cue_remaining_gaps = current_remaining_gaps
  ) |>
  dplyr::select(-dplyr::starts_with("current_"))

current_unknown <- patched_tables$salience_country_matrix |>
  dplyr::filter(status_cue_salience == "unknown")
legacy_recoverability <- appendix_tables$recoverability_table |>
  dplyr::mutate(dplyr::across(dplyr::where(is.factor), as.character)) |>
  dplyr::filter(Country %in% current_unknown$country_name)
new_unknown <- current_unknown |>
  dplyr::filter(!country_name %in% legacy_recoverability$Country) |>
  dplyr::transmute(
    Country = country_name,
    `Entry year` = as.integer(entry_year),
    `China cue` = as.character(status_cue_salience),
    `Ex-#1 benchmark` = as.character(ex_top1_coverage_code),
    Interpretation = dplyr::if_else(
      implication_for_china_status_cue_absence == "more_informative_absence",
      "Benchmark recoverable; follow up before recoding salience",
      "Weak observation/recoverability problem"
    ),
    Caveat = dplyr::if_else(
      iso3c == "SAU",
      "Corrected 2013-2014 public-cue window remains unresolved; rank-definition reconciliation is required.",
      status_cue_remaining_gaps
    )
  )
patched_tables$recoverability_table <- dplyr::bind_rows(
  legacy_recoverability,
  new_unknown
) |>
  dplyr::mutate(
    `Entry year` = as.integer(`Entry year`),
    .order = match(Country, patched_tables$salience_country_matrix$country_name)
  ) |>
  dplyr::arrange(.order) |>
  dplyr::select(-.order)
stopifnot(
  nrow(patched_tables$recoverability_table) == 8L,
  setequal(patched_tables$recoverability_table$Country, current_unknown$country_name),
  !"Australia" %in% patched_tables$recoverability_table$Country,
  !"Gabon" %in% patched_tables$recoverability_table$Country,
  "Saudi Arabia" %in% patched_tables$recoverability_table$Country
)
patched_tables$afr_context_table <- appendix_tables$afr_context_table |>
  dplyr::mutate(
    Interpretation = paste0(
      "Counts for broad public-cue salience in the current 2009 treatment window; ",
      "remains excluded from the strict export-destination benchmark because the metric ",
      "combines exports and imports of goods and services."
    )
  )

# Preserve the source-audit chronology and source documentation in a separate,
# machine-readable component.  The supplemental source table itself is copied
# unchanged inside source_appendix_tables.
australia_source_audit <- appendix_tables$supplemental_context_sources |>
  dplyr::filter(iso3c == "AUS") |>
  dplyr::transmute(
    iso3c,
    country_name,
    source_audit_year = as.integer(entry_year),
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
  )
stopifnot(nrow(australia_source_audit) >= 1L, all(australia_source_audit$source_audit_year == 2010L))

input_paths <- c(
  "data/processed/status_cue_salience/status_cue_country_codes.csv",
  "data/processed/status_cue_salience/status_cue_source_evidence.csv",
  "data/processed/ex_top1_salience/ex_top1_country_codes.csv",
  "data/processed/ex_top1_salience/ex_top1_source_evidence.csv",
  "data/processed/ex_top1_salience/status_cue_vs_ex_top1_coverage.csv",
  "_targets/objects/ex_top1_salience_appendix_tables",
  "_targets/objects/china_top_m2_goods_status_current_unit_summary"
)
input_manifest <- tibble::tibble(
  path = input_paths,
  sha256 = vapply(file.path(repo_root, input_paths), sha256_file, character(1))
)

change_log <- tibble::tribble(
  ~table, ~key, ~field, ~old, ~new, ~reason,
  "salience_country_matrix", "Australia", "entry_year", "2010", "2009", "Current five-year risk-set-restricted goods-only status summary",
  "salience_country_matrix", "Australia", "status_cue_salience", "unknown", "high", "Independently audited AFR 2009 plus DFAT 2010 broad-cue evidence",
  "recoverability_table", "Australia", "row", "included", "removed", "Australia now has an observed high broad public cue",
  "salience_country_matrix", "Saudi Arabia", "status_cue_salience", "high", "unknown", "Corrected 2013-2014 source window has no countable top-rank cue",
  "recoverability_table", "Saudi Arabia", "row", "omitted", "included", "Saudi Arabia is unresolved under the corrected current cue audit",
  "salience_country_matrix", "Gabon", "status_cue_salience", "unknown", "high", "Two preserved local 2017-2018 publisher families establish a broad cue",
  "recoverability_table", "Gabon", "row", "included", "removed", "Gabon now has an observed high broad public cue",
  "afr_context_table", "Australia", "Interpretation", "context only", "counts for broad cue", "Separate broad salience from strict export-destination benchmark"
)

patch_bundle <- list(
  schema_version = "1.0",
  finding_id = "RIO-R1-006",
  status = "CORRECTED_CURRENT_CUE",
  generated_on = as.character(Sys.Date()),
  scope = "Synchronize the 14-country appendix with current public-cue codes; Australia remains the focal metric-mismatch case",
  source = list(
    treatment_target = "china_top_m2_goods_status_current_unit_summary",
    treatment_target_filter = "min_duration_years == 5; sample == risk_set_restricted; ever_treated == TRUE; iso3c == AUS",
    treatment_metric = "goods-only annual export destination rank",
    audit_input = "data/processed/status_cue_salience/status_cue_country_codes.csv",
    audit_year_definition = "current status-cue audit entry_year, with treatment-onset differences recorded separately",
    input_manifest = input_manifest
  ),
  tables = patched_tables,
  source_appendix_tables = appendix_tables,
  australia_treatment_summary = current_summary,
  australia_source_audit = australia_source_audit,
  all_country_comparison = all_country_comparison,
  change_log = change_log
)

dir.create(diagnostic_output_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(patch_bundle, output_path, version = 3)
cat("Wrote", rel_path(output_path), "\n")
cat("Australia treatment year:", current_summary$treatment_year_current, "\n")
cat("Australia source-audit year:", australia_legacy$source_audit_year, "\n")
cat("Current unresolved rows:", paste(current_unknown$iso3c, collapse = ", "), "\n")
cat("Treatment-onset differences recorded:", paste(all_country_comparison$iso3c[all_country_comparison$treatment_differs], collapse = ", "), "\n")
