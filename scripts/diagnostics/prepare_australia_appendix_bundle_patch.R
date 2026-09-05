# Prepare a reviewable Table 20 bundle for RIO-R1-006.
#
# This diagnostic reads two existing targets and the existing appendix bundle.
# It updates Australia only, records the legacy source-audit year separately,
# and writes a new RDS under the revision directory.  It never calls tar_make
# and does not modify targets, raw inputs, shared functions, or the manuscript.

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
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

# Compare every appendix country before applying the explicitly scoped AUS-only
# change.  This makes other potential chronology differences visible without
# silently changing CHL, SAU, or any other country in this handoff.
appendix_codes <- legacy_matrix |>
  dplyr::distinct(iso3c, country_name, legacy_entry_year = entry_year)
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
  dplyr::mutate(
    delta_if_applied = current_treatment_year - legacy_entry_year,
    differs = !is.na(delta_if_applied) & delta_if_applied != 0L,
    applied_in_this_patch = iso3c == "AUS"
  ) |>
  dplyr::arrange(iso3c)

patched_tables <- appendix_tables
patched_tables$salience_country_matrix <- legacy_matrix |>
  dplyr::mutate(
    entry_year = dplyr::if_else(
      iso3c == "AUS",
      current_summary$treatment_year_current,
      as.integer(entry_year)
    )
  )
patched_tables$measurement_caveats <- appendix_tables$measurement_caveats |>
  dplyr::mutate(
    entry_year = dplyr::if_else(
      iso3c == "AUS",
      current_summary$treatment_year_current,
      as.integer(entry_year)
    )
  )
patched_tables$recoverability_table <- appendix_tables$recoverability_table |>
  dplyr::mutate(
    `Entry year` = dplyr::if_else(
      Country == "Australia",
      current_summary$treatment_year_current,
      as.integer(`Entry year`)
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

change_log <- tibble::tibble(
  table = "recoverability_table",
  key = "Australia",
  field = "Entry year",
  old = 2010L,
  new = current_summary$treatment_year_current,
  reason = "Current five-year risk-set-restricted goods-only status summary"
)

patch_bundle <- list(
  schema_version = "1.0",
  finding_id = "RIO-R1-006",
  status = "PREPARED_NOT_INTEGRATED",
  generated_on = as.character(Sys.Date()),
  scope = "Australia only; other chronology differences are recorded, not applied",
  source = list(
    treatment_target = "china_top_m2_goods_status_current_unit_summary",
    treatment_target_filter = "min_duration_years == 5; sample == risk_set_restricted; ever_treated == TRUE; iso3c == AUS",
    treatment_metric = "goods-only annual export destination rank",
    audit_input = "data/processed/ex_top1_salience/ex_top1_country_codes.csv",
    audit_year_definition = "legacy ex-Top1 input entry_year/source-audit chronology",
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
cat("Other current-vs-legacy differences recorded:", paste(all_country_comparison$iso3c[all_country_comparison$differs & all_country_comparison$iso3c != "AUS"], collapse = ", "), "\n")
