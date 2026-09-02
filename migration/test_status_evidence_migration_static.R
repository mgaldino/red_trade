#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(digest)
  library(dplyr)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
})

source("scripts/functions.R")
source("scripts/functions_status_evidence_targets_migration.R")

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("FAIL: ", label, call. = FALSE)
  message("PASS: ", label)
}

expect_error <- function(expression, label) {
  failed <- inherits(try(force(expression), silent = TRUE), "try-error")
  expect_true(failed, label)
}

expect_validation_false <- function(validation, name, label) {
  row <- validation |>
    dplyr::filter(validation == name)
  expect_true(
    nrow(row) == 1L && identical(row$passed, FALSE),
    label
  )
}

compare_frame <- function(candidate, reference_file, kind, label) {
  validation <- validate_status_evidence_reference_equivalence(
    candidate,
    reference_file,
    kind
  )
  assert_status_evidence_validation(validation)
  expect_true(all(validation$passed), label)
  validation
}

status_manifest <- file.path(
  "data", "raw", "status_cue_salience", "checksums.sha256"
)
ex_manifest <- file.path(
  "data", "raw", "ex_top1_salience", "checksums.sha256"
)
status_raw_directory <- file.path("data", "raw", "status_cue_salience")
ex_raw_directory <- file.path("data", "raw", "ex_top1_salience")
status_raw_files <- status_evidence_raw_paths(
  status_manifest,
  status_raw_directory,
  89L
)
ex_raw_files <- status_evidence_raw_paths(
  ex_manifest,
  ex_raw_directory,
  48L
)
status_raw_validation <- validate_status_evidence_raw_archive(
  status_manifest,
  status_raw_files,
  status_raw_directory,
  89L,
  "9be41ee4805289fb6b32bf21cea39146363053d2a2970d26e20e9bc1aaaa0675"
)
ex_raw_validation <- validate_status_evidence_raw_archive(
  ex_manifest,
  ex_raw_files,
  ex_raw_directory,
  48L,
  "7f92a5822b396ee204e9e8eb4ea5682d791abdddecf5758134b97447ee69d8c3"
)
assert_status_evidence_validation(status_raw_validation)
assert_status_evidence_validation(ex_raw_validation)
message("PASS: both frozen raw archives match every declared SHA-256")

status_source_file <- file.path(
  "data", "processed", "status_cue_salience",
  "status_cue_source_evidence.csv"
)
ex_source_file <- file.path(
  "data", "processed", "ex_top1_salience",
  "ex_top1_source_evidence.csv"
)
status_source <- read_status_evidence_source_ledger(
  status_source_file,
  "status"
)
ex_source <- read_status_evidence_source_ledger(
  ex_source_file,
  "ex_top1"
)
status_source_validation <- validate_status_evidence_source_ledger(
  status_source,
  status_source_file,
  "status",
  status_raw_files,
  status_raw_directory,
  21L
)
ex_source_validation <- validate_status_evidence_source_ledger(
  ex_source,
  ex_source_file,
  "ex_top1",
  ex_raw_files,
  ex_raw_directory,
  22L
)
assert_status_evidence_validation(status_source_validation)
assert_status_evidence_validation(ex_source_validation)
message("PASS: both author-owned source ledgers satisfy the contract")

invalid_boolean <- status_source
invalid_boolean$explicit_rank_language[[1]] <- "maybe"
expect_error(
  assert_status_evidence_validation(
    validate_status_evidence_source_ledger(
      invalid_boolean,
      status_source_file,
      "status",
      status_raw_files,
      status_raw_directory,
      21L
    )
  ),
  "invalid boolean coding is rejected"
)

invalid_year <- status_source
invalid_year$entry_year[[1]] <- "2005.9"
expect_validation_false(
  validate_status_evidence_source_ledger(
    invalid_year,
    status_source_file,
    "status",
    status_raw_files,
    status_raw_directory,
    21L
  ),
  "ledger_years_valid",
  "fractional year coding is rejected"
)

invalid_date <- status_source
invalid_date$publication_date[[1]] <- "2021-02-30"
expect_validation_false(
  validate_status_evidence_source_ledger(
    invalid_date,
    status_source_file,
    "status",
    status_raw_files,
    status_raw_directory,
    21L
  ),
  "ledger_publication_dates_valid",
  "invalid ISO publication date is rejected"
)

invalid_urls <- c(
  "file:///tmp/source",
  "https://-",
  "http://user@",
  "https://example.com:bad",
  "https://example.com/ bad",
  "https://example.com/%zz"
)
for (bad_url in invalid_urls) {
  invalid_url <- status_source
  invalid_url$url[[1]] <- bad_url
  expect_validation_false(
    validate_status_evidence_source_ledger(
      invalid_url,
      status_source_file,
      "status",
      status_raw_files,
      status_raw_directory,
      21L
    ),
    "ledger_urls_valid",
    paste0("invalid source URL is rejected: ", bad_url)
  )
}

invalid_archive_url <- status_source
invalid_archive_url$archive_url[[1]] <- "file:///tmp/archive"
expect_validation_false(
  validate_status_evidence_source_ledger(
    invalid_archive_url,
    status_source_file,
    "status",
    status_raw_files,
    status_raw_directory,
    21L
  ),
  "ledger_archive_urls_valid",
  "nonblank invalid archive URL is rejected"
)

invalid_pointer <- status_source
invalid_pointer$raw_file[[1]] <- "data/raw/status_cue_salience/../escape.html"
expect_error(
  assert_status_evidence_validation(
    validate_status_evidence_source_ledger(
      invalid_pointer,
      status_source_file,
      "status",
      status_raw_files,
      status_raw_directory,
      21L
    )
  ),
  "raw pointer traversal is rejected"
)

universe <- read_status_evidence_audit_universe(
  file.path("data", "manual", "status_evidence", "audit_universe.csv")
)
overrides <- read_status_country_overrides(
  file.path(
    "data", "manual", "status_evidence", "status_country_overrides.csv"
  )
)
annotations <- read_ex_top1_country_annotations(
  file.path(
    "data", "manual", "status_evidence", "ex_top1_country_annotations.csv"
  )
)
manual_validation <- validate_status_evidence_manual_inputs(
  universe,
  overrides,
  annotations
)
assert_status_evidence_validation(manual_validation)

duplicate_universe <- dplyr::bind_rows(universe, universe[1, ])
expect_error(
  assert_status_evidence_validation(
    validate_status_evidence_manual_inputs(
      duplicate_universe,
      overrides,
      annotations
    )
  ),
  "duplicated audit-universe keys are rejected"
)

altered_universe <- universe
altered_universe$iso3c[altered_universe$iso3c == "SAU"] <- "ZZZ"
altered_annotations <- annotations
altered_annotations$iso3c[altered_annotations$iso3c == "SAU"] <- "ZZZ"
expect_error(
  assert_status_evidence_validation(
    validate_status_evidence_manual_inputs(
      altered_universe,
      overrides,
      altered_annotations
    )
  ),
  "altered 14-case universe is rejected before derivation"
)

incumbent_file <- file.path(
  "data", "processed", "diagnostics",
  "incumbent_salience_moderators_2026-05-19.csv"
)
assert_status_evidence_validation(
  validate_status_evidence_incumbent_file(incumbent_file)
)
incumbent_data <- readr::read_csv(
  incumbent_file,
  show_col_types = FALSE
)
incumbent_base <- build_ex_top1_incumbent_base_candidate(
  universe,
  incumbent_data,
  incumbent_file
)
status_country <- build_status_cue_country_codes_candidate(
  universe,
  status_source,
  overrides
)
ex_country <- build_ex_top1_country_codes_candidate(
  universe,
  ex_source,
  incumbent_base,
  annotations
)
comparison <- build_status_ex_top1_comparison_candidate(
  ex_country,
  status_country
)
derivation_validation <- validate_status_evidence_derivations(
  status_country,
  ex_country,
  comparison,
  universe,
  incumbent_base,
  ex_source
)

status_country_reference <- file.path(
  "data", "processed", "status_cue_salience", "status_cue_country_codes.csv"
)
ex_country_reference <- file.path(
  "data", "processed", "ex_top1_salience", "ex_top1_country_codes.csv"
)
comparison_reference <- file.path(
  "data", "processed", "ex_top1_salience",
  "status_cue_vs_ex_top1_coverage.csv"
)
status_reference_validation <- compare_frame(
  status_country,
  status_country_reference,
  "status",
  "status country codes reproduce the 14-row baseline"
)
ex_reference_validation <- compare_frame(
  ex_country,
  ex_country_reference,
  "ex_top1",
  "former-incumbent country codes reproduce the 14-row baseline"
)
comparison_reference_validation <- compare_frame(
  comparison,
  comparison_reference,
  "comparison",
  "status/incumbent comparison reproduces the 14-row baseline"
)
reference_validation <- dplyr::bind_rows(
  status_reference_validation,
  ex_reference_validation,
  comparison_reference_validation
)
assert_status_evidence_validation(
  dplyr::bind_rows(
    manual_validation,
    derivation_validation,
    reference_validation
  ),
  status_evidence_validation_names()
)

baseline_appendix <- build_ex_top1_salience_appendix_tables(
  comparison_reference,
  ex_country_reference,
  ex_source_file,
  status_country_reference,
  status_source_file
)
temporary_directory <- tempfile("status_evidence_r_")
dir.create(temporary_directory, recursive = TRUE)
on.exit(unlink(temporary_directory, recursive = TRUE), add = TRUE)
candidate_status_file <- file.path(temporary_directory, "status_country.csv")
candidate_ex_file <- file.path(temporary_directory, "ex_country.csv")
candidate_comparison_file <- file.path(temporary_directory, "comparison.csv")
write_status_evidence_csv_candidate(
  status_country,
  candidate_status_file,
  "status"
)
write_status_evidence_csv_candidate(ex_country, candidate_ex_file, "ex_top1")
write_status_evidence_csv_candidate(
  comparison,
  candidate_comparison_file,
  "comparison"
)
expect_true(
  identical(
    status_evidence_file_sha256(candidate_status_file),
    status_evidence_file_sha256(status_country_reference)
  ) &&
    identical(
      status_evidence_file_sha256(candidate_ex_file),
      status_evidence_file_sha256(ex_country_reference)
    ) &&
    identical(
      status_evidence_file_sha256(candidate_comparison_file),
      status_evidence_file_sha256(comparison_reference)
    ),
  "all three serialized candidate CSVs match their frozen hashes"
)
candidate_appendix <- build_ex_top1_salience_appendix_tables(
  candidate_comparison_file,
  candidate_ex_file,
  ex_source_file,
  candidate_status_file,
  status_source_file
)
expect_true(
  isTRUE(all.equal(
    baseline_appendix$recoverability_table,
    candidate_appendix$recoverability_table,
    check.attributes = FALSE
  )),
  "recoverability appendix table is unchanged"
)
expect_true(
  isTRUE(all.equal(
    baseline_appendix$afr_context_table,
    candidate_appendix$afr_context_table,
    check.attributes = FALSE
  )),
  "Australian context appendix table is unchanged"
)

static_store <- tempfile("status_evidence_targets_static_store_")
targets::tar_validate(
  callr_function = NULL,
  script = "_targets.R",
  store = static_store
)
network <- targets::tar_network(
  targets_only = TRUE,
  outdated = FALSE,
  callr_function = NULL,
  script = "_targets.R",
  store = static_store
)
graph <- igraph::graph_from_data_frame(
  network$edges,
  directed = TRUE,
  vertices = data.frame(name = network$vertices$name)
)
expect_true(igraph::is_dag(graph), "target-only graph remains acyclic")
expect_true(
  !startsWith(
    normalizePath(static_store, mustWork = FALSE),
    normalizePath(
      targets::tar_config_get("store"),
      mustWork = FALSE
    )
  ),
  "DAG audit uses an isolated store rather than the shared checkout store"
)
has_path <- function(from, to) {
  length(igraph::shortest_paths(
    graph,
    from = from,
    to = to,
    mode = "out"
  )$vpath[[1]]) > 0L
}
expect_true(
  has_path(
    "status_cue_raw_files_candidate",
    "status_cue_country_codes_file"
  ) &&
    has_path(
      "ex_top1_raw_files_candidate",
      "ex_top1_country_codes_file"
    ),
  "raw file targets are ancestors of country-code outputs"
)
expect_true(
  has_path(
    "status_evidence_derivation_gate_candidate",
    "ex_top1_salience_appendix_tables"
  ),
  "derivation gate is an ancestor of the manuscript appendix tables"
)

message("ALL_STATIC_STATUS_EVIDENCE_R_TESTS_PASSED")
