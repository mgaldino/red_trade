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

row_audit <- master |>
  dplyr::mutate(
    min_duration_years = 5L,
    specification_unit_eligible = TRUE,
    risk_set_eligible = TRUE,
    abs_distance_china = 0.4,
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

unlink(checkpoint_directory, recursive = TRUE)
message("ALL_STATIC_UNGADM_MIGRATION_TESTS_PASSED")
