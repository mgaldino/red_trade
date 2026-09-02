#!/usr/bin/env Rscript

# Cheap deterministic tests for the UNGA-DM candidate graph. This script does
# not call targets and never estimates SDiD or fect models.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(readr)
  library(janitor)
  library(digest)
})

source("scripts/functions.R")
source("scripts/functions_targets_migration.R")
source("scripts/diagnostics/sdid_placebo_helpers.R")
source("scripts/functions_sdid_targets_migration.R")
source("scripts/functions_ungadm_targets_migration.R")

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("FAILED: ", label, call. = FALSE)
  message("PASS: ", label)
}

expect_error <- function(expression, label) {
  failed <- tryCatch(
    {
      force(expression)
      FALSE
    },
    error = function(error) TRUE
  )
  expect_true(failed, label)
}

bsv_file <- file.path(
  "raw data", "dataverse_files-2",
  "IdealpointestimatesAll_Jun2024.csv"
)
dm_file <- file.path(
  "raw data", "unga_dm",
  "unga_dm_ideal_points_all_resolution_votes_s75.csv"
)
codebook_file <- file.path(
  "raw data", "unga_dm", "unga_dm_codebook.pdf"
)
sources_file <- file.path("raw data", "unga_dm", "SOURCES.md")

input_validation <- validate_ungadm_input_files(
  bsv_file,
  dm_file,
  codebook_file,
  sources_file
)
expect_true(
  all(input_validation$passed),
  "frozen UNGA-DM inputs match the contract"
)

sdid_reference_directory <- file.path(
  "data", "processed", "diagnostics", "ungadm_outcome_robustness"
)
sdid_reference_validation <- validate_ungadm_sdid_reference_files(
  sdid_reference_directory
)
expect_true(
  nrow(sdid_reference_validation) == 4L &&
    all(sdid_reference_validation$passed),
  "frozen UNGA-DM SDiD references match the contract hashes"
)
tampered_reference_directory <- tempfile("ungadm-sdid-reference-")
dir.create(
  file.path(tampered_reference_directory, "estimation"),
  recursive = TRUE
)
dir.create(
  file.path(tampered_reference_directory, "postreview"),
  recursive = TRUE
)
copied_references <- file.copy(
  sdid_reference_validation$path,
  c(
    file.path(
      tampered_reference_directory,
      "estimation",
      "sdid_comparison_table.csv"
    ),
    file.path(
      tampered_reference_directory,
      "estimation",
      "sdid_dm_placebo_distribution.csv"
    ),
    file.path(
      tampered_reference_directory,
      "postreview",
      "sdid_dm_rank_inference_harmonized.csv"
    ),
    file.path(
      tampered_reference_directory,
      "estimation",
      "sdid_unit_weights_bsv_vs_dm.csv"
    )
  )
)
expect_true(
  all(copied_references),
  "SDiD hash-test fixtures are complete"
)
writeLines(
  "tampered",
  file.path(
    tampered_reference_directory,
    "estimation",
    "sdid_comparison_table.csv"
  )
)
expect_error(
  validate_ungadm_sdid_reference_files(tampered_reference_directory),
  "SDiD reference validation rejects a changed file"
)
unlink(tampered_reference_directory, recursive = TRUE)

harmonized <- build_ungadm_harmonized_bundle(bsv_file, dm_file)
validation_outputs <- build_ungadm_validation_outputs(harmonized)
assert_ungadm_validation(
  validation_outputs$validation,
  ungadm_validation_names()
)
expect_true(
  nrow(harmonized$unmatched) == 28L,
  "harmonization preserves the 28 unmapped rows"
)
expect_true(
  nrow(dplyr::filter(
    harmonized$outcome,
    iso3c == "DEU", year == 1990L, ccode == 260L
  )) == 1L,
  "German session-45 convention maps to DEU"
)
expect_true(
  nrow(validation_outputs$within_range_gaps) == 31L,
  "corrected harmonization has 31 within-range source gaps"
)

years <- 1990:2023
master <- tidyr::expand_grid(
  iso3c = c("AAA", "BBB"),
  year = years
) |>
  dplyr::arrange(iso3c, year) |>
  dplyr::mutate(
    trade_rank_row_present = TRUE,
    trade_rank_observed = TRUE,
    n_top_ties = 1L,
    top_partner = dplyr::if_else(
      iso3c == "AAA" & year >= 2009L,
      "CHN",
      "USA"
    ),
    top_export_value = 1,
    rank_CHN = dplyr::if_else(top_partner == "CHN", 1, 2),
    rank_USA = dplyr::if_else(top_partner == "USA", 1, 2),
    china_top_status = as.integer(top_partner == "CHN"),
    previous_china_top_status = dplyr::lag(
      china_top_status,
      order_by = interaction(iso3c, year)
    ),
    china_top_period_start = china_top_status == 1L & year == 2009L,
    china_top_period_id = dplyr::if_else(
      china_top_status == 1L,
      1L,
      NA_integer_
    )
  )
dm_fixture <- tidyr::expand_grid(
  iso3c = c("AAA", "BBB"),
  year = 1990:2020
) |>
  dplyr::mutate(
    session = year - 1945L,
    ccode = dplyr::if_else(iso3c == "AAA", 100L, 200L),
    country_ungadm = iso3c,
    ideal_point_dm = 0.5,
    china_ideal_dm = 0,
    usa_ideal_dm = 1,
    abs_distance_china_dm = 0.5,
    abs_distance_usa_dm = 0.5
  )
augmented <- join_ungadm_to_full_union_master(master, dm_fixture)
join_validation <- validate_ungadm_master_join(master, augmented)
assert_ungadm_validation(
  join_validation,
  ungadm_master_join_validation_names()
)
expect_true(
  all(is.na(augmented$abs_distance_china_dm[augmented$year >= 2021L])),
  "2021-2023 remain explicit UNGA-DM missing values"
)
master_missing_treatment_column <- master |>
  dplyr::select(-china_top_period_id)
expect_error(
  join_ungadm_to_full_union_master(
    master_missing_treatment_column,
    dm_fixture
  ),
  "master join rejects a missing contractual treatment column"
)

row_audit <- master |>
  dplyr::mutate(
    min_duration_years = 5L,
    specification_unit_eligible = TRUE,
    risk_set_eligible = TRUE,
    abs_distance_china = 0.4,
    outcome_observed = TRUE,
    china_top = china_top_status,
    treatment_role = dplyr::if_else(
      iso3c == "AAA",
      "treated_qualifying",
      "never_observed_china_top_control"
    ),
    first_treat = dplyr::if_else(iso3c == "AAA", 2009, 0),
    qualifying_period = china_top == 1L
  )
common <- build_ungadm_common_window_bundle(row_audit, augmented)
common_validation <- validate_ungadm_common_window_bundle(common)
assert_ungadm_validation(
  common_validation,
  ungadm_common_window_validation_names()
)
expect_true(
  identical(
    dplyr::select(common$panel_bsv, iso3c, year, china_top),
    dplyr::select(common$panel_dm, iso3c, year, china_top)
  ),
  "common BSV and UNGA-DM variants have identical rows and treatment"
)
common_missing_metadata <- common
common_missing_metadata$panel_dm <- common_missing_metadata$panel_dm |>
  dplyr::select(-qualifying_period)
expect_error(
  validate_ungadm_common_window_bundle(common_missing_metadata),
  "common-window validation rejects a missing contractual metadata column"
)
row_audit_missing_bsv <- row_audit |>
  dplyr::mutate(
    outcome_observed = dplyr::if_else(
      iso3c == "BBB" & year == 2000L,
      FALSE,
      outcome_observed
    ),
    abs_distance_china = dplyr::if_else(
      iso3c == "BBB" & year == 2000L,
      NA_real_,
      abs_distance_china
    )
  )
common_missing_bsv <- build_ungadm_common_window_bundle(
  row_audit_missing_bsv,
  augmented
)
expect_true(
  any(common_missing_bsv$dropped_rows$reason == "BSV outcome missing"),
  "common-window row audit distinguishes missing BSV outcomes"
)

sdid_fixture <- tidyr::expand_grid(
  iso3c = c("BRA", "AAA"),
  year = 1997:2015
) |>
  dplyr::arrange(iso3c, year) |>
  dplyr::mutate(
    abs_distance_china = 0.4,
    treatment = as.integer(iso3c == "BRA" & year >= 2009L)
  )
sdid_dm_fixture <- sdid_fixture |>
  dplyr::transmute(
    iso3c,
    year,
    abs_distance_china_dm = 0.5
  )
sdid_bundle <- build_ungadm_sdid_panel_bundle(
  sdid_fixture,
  sdid_dm_fixture
)
sdid_validation <- validate_ungadm_sdid_panel(
  sdid_fixture,
  sdid_bundle,
  expected_units = 2L
)
assert_ungadm_validation(
  sdid_validation,
  ungadm_sdid_panel_validation_names()
)
expect_true(
  identical(sdid_fixture$treatment, sdid_bundle$panel$treatment),
  "UNGA-DM SDiD join cannot change treatment"
)

expect_error(
  assert_ungadm_validation(
    join_validation[-1, ],
    ungadm_master_join_validation_names()
  ),
  "validation gate rejects a missing row"
)
expect_error(
  assert_ungadm_validation(
    dplyr::bind_rows(join_validation, join_validation[1, ]),
    ungadm_master_join_validation_names()
  ),
  "validation gate rejects duplicate rows"
)
join_validation_na <- join_validation
join_validation_na$passed[[1]] <- NA
expect_error(
  assert_ungadm_validation(
    join_validation_na,
    ungadm_master_join_validation_names()
  ),
  "validation gate rejects NA pass values"
)

# Checkpoint tests use a cheap stub fit. The production fect function is never
# invoked, but the same draw, fingerprint, resume and retry machinery runs.
checkpoint_directory <- tempfile("ungadm-paired-checkpoint-")
fit_counter <- new.env(parent = emptyenv())
fit_counter$n <- 0L
stub_fit <- function(panel, r_fixed) {
  fit_counter$n <- fit_counter$n + 1L
  mean(panel$abs_distance_china) + r_fixed
}
draws_first <- run_ungadm_paired_bootstrap_candidate(
  common$common_rows,
  bsv_selected_r = 2L,
  dm_selected_r = 1L,
  B = 4L,
  boot_seed = 20260823L,
  checkpoint_directory = checkpoint_directory,
  core_cap = 1L,
  batch_size = 2L,
  fit_function = stub_fit
)
expect_true(
  nrow(draws_first) == 4L && fit_counter$n == 12L,
  "paired bootstrap computes every missing draw"
)
fit_counter$n <- 0L
draws_reused <- run_ungadm_paired_bootstrap_candidate(
  common$common_rows,
  bsv_selected_r = 2L,
  dm_selected_r = 1L,
  B = 4L,
  boot_seed = 20260823L,
  checkpoint_directory = checkpoint_directory,
  core_cap = 1L,
  batch_size = 2L,
  fit_function = stub_fit
)
expect_true(
  identical(draws_first, draws_reused) && fit_counter$n == 0L,
  "completed paired-bootstrap checkpoint is reused"
)

checkpoint_path <- file.path(checkpoint_directory, "paired_ife_b4.rds")
checkpoint <- readRDS(checkpoint_path)
checkpoint$distribution <- checkpoint$distribution[1:3, ]
sdid_atomic_save_rds(checkpoint, checkpoint_path)
fit_counter$n <- 0L
draws_resumed <- run_ungadm_paired_bootstrap_candidate(
  common$common_rows,
  bsv_selected_r = 2L,
  dm_selected_r = 1L,
  B = 4L,
  boot_seed = 20260823L,
  checkpoint_directory = checkpoint_directory,
  core_cap = 1L,
  batch_size = 2L,
  fit_function = stub_fit
)
expect_true(
  identical(draws_first, draws_resumed) && fit_counter$n == 3L,
  "partial paired-bootstrap checkpoint resumes only missing draws"
)

fit_counter$n <- 0L
stub_fit_changed <- function(panel, r_fixed) {
  fit_counter$n <- fit_counter$n + 1L
  mean(panel$abs_distance_china) + r_fixed + 0.01
}
draws_invalidated <- run_ungadm_paired_bootstrap_candidate(
  common$common_rows,
  bsv_selected_r = 2L,
  dm_selected_r = 1L,
  B = 4L,
  boot_seed = 20260823L,
  checkpoint_directory = checkpoint_directory,
  core_cap = 1L,
  batch_size = 2L,
  fit_function = stub_fit_changed
)
expect_true(
  fit_counter$n == 12L &&
    !identical(draws_invalidated$att_bsv_r2, draws_first$att_bsv_r2),
  "code change invalidates the paired-bootstrap checkpoint"
)

dynamic_checkpoint_directory <- tempfile("ungadm-paired-dynamic-")
fit_counter$n <- 0L
draws_dynamic <- run_ungadm_paired_bootstrap_candidate(
  common$common_rows,
  bsv_selected_r = 0L,
  dm_selected_r = 3L,
  B = 2L,
  boot_seed = 20260823L,
  checkpoint_directory = dynamic_checkpoint_directory,
  core_cap = 1L,
  batch_size = 2L,
  fit_function = stub_fit
)
expect_true(
  all(draws_dynamic$bsv_selected_r == 0L) &&
    all(draws_dynamic$dm_selected_r == 3L) &&
    fit_counter$n == 8L,
  "paired bootstrap follows arbitrary CV selections in 0:3"
)
dynamic_summary <- build_ungadm_paired_bootstrap_summary_candidate(
  draws_dynamic,
  tibble::tribble(
    ~variant, ~att, ~r_cv,
    "BSV common window (fixture)", 0.4, 0L,
    "UNGA-DM common window (fixture)", 3.5, 3L
  ),
  tibble::tribble(
    ~outcome, ~r_fixed, ~att,
    "BSV", 2L, 2.4,
    "UNGA-DM", 2L, 2.5
  ),
  B = 2L
)
expect_true(
  grepl("UNGA-DM \\(r=3\\) minus BSV \\(r=0\\)",
        dynamic_summary$contrast[[1]]) &&
    isTRUE(all.equal(dynamic_summary$observed_diff[[1]], 3.1)),
  "paired-bootstrap summary labels and contrasts the selected factors"
)
expect_true(
  grepl(
    "run_ungadm_paired_bootstrap_candidate",
    paste(deparse(body(ungadm_paired_code_fingerprint)), collapse = " "),
    fixed = TRUE
  ),
  "checkpoint fingerprint covers the bootstrap orchestrator"
)

unlink(checkpoint_directory, recursive = TRUE)
unlink(dynamic_checkpoint_directory, recursive = TRUE)
message("ALL_STATIC_UNGADM_MIGRATION_TESTS_PASSED")
