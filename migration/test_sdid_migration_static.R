source("scripts/functions.R")
source("scripts/functions_targets_migration.R")
source("scripts/diagnostics/sdid_placebo_helpers.R")
source("scripts/functions_sdid_targets_migration.R")

expect_true <- function(value, label) {
  if (!isTRUE(value)) {
    stop("FAILED: ", label, call. = FALSE)
  }
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

validation_passed <- function(validation, suffix) {
  validation$passed[endsWith(validation$validation, suffix)]
}

# CSV round trips may change integer to double and empty text to NA. Those are
# equivalent representations for this migration gate.
reference_path <- tempfile(fileext = ".csv")
readr::write_csv(
  tibble::tibble(
    year = 2007,
    error = NA_character_,
    value = 1e12
  ),
  reference_path,
  na = ""
)
candidate <- tibble::tibble(
  year = 2007L,
  error = "",
  value = 1e12 + 0.5
)
comparison <- compare_sdid_candidate_frame(
  candidate,
  reference_path,
  "year",
  "roundtrip"
)
expect_true(all(comparison$passed), "CSV type and blank/NA normalization")

# The tolerance is absolute plus relative. A difference beyond the
# scale-adjusted 1e-12 threshold must still fail.
too_far <- candidate
too_far$value <- 1e12 + 2
comparison_far <- compare_sdid_candidate_frame(
  too_far,
  reference_path,
  "year",
  "too_far"
)
expect_true(
  !validation_passed(comparison_far, "_numeric_equal"),
  "scale-adjusted numeric divergence fails"
)

# Infinite values are never silently discarded by the numeric comparison.
with_infinity <- candidate
with_infinity$value <- Inf
comparison_infinity <- compare_sdid_candidate_frame(
  with_infinity,
  reference_path,
  "year",
  "infinity"
)
expect_true(
  !validation_passed(comparison_infinity, "_numeric_equal"),
  "infinite numeric value fails"
)

with_nan <- candidate
with_nan$value <- NaN
comparison_nan <- compare_sdid_candidate_frame(
  with_nan,
  reference_path,
  "year",
  "nan"
)
expect_true(
  !validation_passed(comparison_nan, "_numeric_equal"),
  "NaN numeric value fails"
)

wrong_key <- candidate
wrong_key$year <- 2008L
comparison_key <- compare_sdid_candidate_frame(
  wrong_key,
  reference_path,
  "year",
  "wrong_key"
)
expect_true(
  !validation_passed(comparison_key, "_same_keys"),
  "key mismatch fails"
)

validate_sdid_commodity_share_bounds(
  tibble::tibble(price_mapping_coverage = 1 + .Machine$double.eps)
)
message("PASS: share bound admits machine-precision overshoot")
expect_error(
  validate_sdid_commodity_share_bounds(
    tibble::tibble(price_mapping_coverage = 1 + 1e-6)
  ),
  "material share bound violation fails"
)

expect_error(
  assert_sdid_migration_validation(
    tibble::tibble(validation = c("known", "unknown"), passed = c(TRUE, NA)),
    expected_validations = c("known", "unknown")
  ),
  "aggregate validation fails closed on NA"
)
expect_error(
  assert_sdid_migration_validation(
    tibble::tibble(validation = character(), passed = logical()),
    expected_validations = "required"
  ),
  "aggregate validation rejects an empty table"
)
expect_error(
  assert_sdid_migration_validation(
    tibble::tibble(validation = "known", passed = TRUE),
    expected_validations = c("known", "required")
  ),
  "aggregate validation rejects a missing required check"
)
expect_error(
  assert_sdid_migration_validation(
    tibble::tibble(validation = c("known", "known"), passed = c(TRUE, TRUE)),
    expected_validations = "known"
  ),
  "aggregate validation rejects duplicate checks"
)

checkpoint_directory <- tempfile(pattern = "sdid-checkpoint-")
dir.create(checkpoint_directory)
atomic_checkpoint <- file.path(checkpoint_directory, "atomic.rds")
sdid_atomic_save_rds(list(value = 42L), atomic_checkpoint)
expect_true(
  identical(sdid_read_checkpoint(atomic_checkpoint), list(value = 42L)),
  "atomic checkpoint round trip"
)
writeLines("not an RDS file", atomic_checkpoint)
expect_true(
  is.null(suppressWarnings(sdid_read_checkpoint(atomic_checkpoint))),
  "corrupt checkpoint is ignored safely"
)

# Exercise partial rank resumption without fitting a model. The first run
# writes three one-unit batches. After truncating the checkpoint to two units,
# the second run must evaluate only the missing unit.
original_fit_spec <- sdid_fit_spec
original_summary_row <- sdid_fit_summary_row
.rank_test_calls <- 0L
sdid_fit_spec <- function(data,
                          covariate_cols = character(0),
                          treated_iso3c,
                          ...) {
  .rank_test_calls <<- .rank_test_calls + 1L
  list(unit = treated_iso3c)
}
sdid_fit_summary_row <- function(fit, specification, se_value = NA_real_) {
  tibble::tibble(
    estimate = match(fit$unit, c("AAA", "BBB", "CCC")),
    rmspe_pre = 0.1
  )
}
rank_fixture <- tidyr::crossing(
  iso3c = c("AAA", "BBB", "CCC"),
  year = 1997:1998
) |>
  dplyr::mutate(abs_distance_china = 0)
rank_checkpoint_directory <- file.path(checkpoint_directory, "rank")
rank_first <- sdid_rank_distribution(
  rank_fixture,
  label = "resume_test",
  cores = 1L,
  checkpoint_dir = rank_checkpoint_directory,
  batch_size = 1L
)
rank_checkpoint_path <- file.path(
  rank_checkpoint_directory,
  "rank_placebos_resume_test.rds"
)
rank_cache <- sdid_read_checkpoint(rank_checkpoint_path)
rank_cache$distribution <- rank_cache$distribution[1:2, ]
sdid_atomic_save_rds(rank_cache, rank_checkpoint_path)
.rank_test_calls <- 0L
rank_second <- sdid_rank_distribution(
  rank_fixture,
  label = "resume_test",
  cores = 1L,
  checkpoint_dir = rank_checkpoint_directory,
  batch_size = 1L
)
expect_true(nrow(rank_first) == 3L, "rank checkpoint initial batches")
expect_true(nrow(rank_second) == 3L, "rank checkpoint resumed result complete")
expect_true(.rank_test_calls == 1L, "rank checkpoint resumes only missing units")

# A readable checkpoint with an invalid estimated value must not be reused.
rank_cache <- sdid_read_checkpoint(rank_checkpoint_path)
rank_cache$distribution$estimate[[1]] <- Inf
sdid_atomic_save_rds(rank_cache, rank_checkpoint_path)
.rank_test_calls <- 0L
rank_third <- sdid_rank_distribution(
  rank_fixture,
  label = "resume_test",
  cores = 1L,
  checkpoint_dir = rank_checkpoint_directory,
  batch_size = 1L
)
expect_true(nrow(rank_third) == 3L, "invalid rank checkpoint is rebuilt")
expect_true(.rank_test_calls == 3L, "invalid rank checkpoint reuses no rows")

# A syntactically valid error row records an interrupted/failed assignment, not
# completed work. The next run must retain good rows and retry the error unit.
rank_cache <- sdid_read_checkpoint(rank_checkpoint_path)
rank_cache$distribution$status[[1]] <- "error"
rank_cache$distribution$estimate[[1]] <- NA_real_
rank_cache$distribution$rmspe_pre[[1]] <- NA_real_
rank_cache$distribution$error[[1]] <- "transient test failure"
sdid_atomic_save_rds(rank_cache, rank_checkpoint_path)
.rank_test_calls <- 0L
rank_fourth <- sdid_rank_distribution(
  rank_fixture,
  label = "resume_test",
  cores = 1L,
  checkpoint_dir = rank_checkpoint_directory,
  batch_size = 1L
)
expect_true(nrow(rank_fourth) == 3L, "rank error row retried to completion")
expect_true(.rank_test_calls == 1L, "rank retry preserves successful rows")
sdid_fit_spec <- original_fit_spec
sdid_fit_summary_row <- original_summary_row

# Small ITPD-E fixture: five complete years for Brazil, a zero-goods exporter,
# and a partial-coverage exporter. The candidate builder must exclude services
# and domestic trade, normalize structurally undefined shares to NA, and retain
# partial global coverage without admitting it to the analytic universe.
itpd_path <- tempfile(fileext = ".csv")
fixture <- dplyr::bind_rows(lapply(2004:2008, function(year) {
  tibble::tribble(
    ~exporter_iso3, ~importer_iso3, ~year, ~broad_sector, ~industry_id, ~trade,
    "BRA", "CHN", year, "Agriculture", 1L, 100,
    "BRA", "USA", year, "Services", 36L, 50,
    "BRA", "BRA", year, "Agriculture", 1L, 10,
    "USA", "CHN", year, "Manufacturing", 20L, 200,
    "IMN", "CHN", year, "Services", 36L, 50
  )
}), tibble::tibble(
  exporter_iso3 = "GUF",
  importer_iso3 = "CHN",
  year = 2004L,
  broad_sector = "Agriculture",
  industry_id = 1L,
  trade = 25
))
readr::write_csv(fixture, itpd_path)
commodity <- build_sdid_commodity_exposure_from_itpde(itpd_path)
bra_yearly <- commodity$yearly |>
  dplyr::filter(iso3c == "BRA")
bra_exposure <- commodity$exposure |>
  dplyr::filter(iso3c == "BRA")
expect_true(nrow(bra_yearly) == 5L, "five-year commodity window")
expect_true(
  all(bra_yearly$goods_exports == 100),
  "services and domestic flows excluded from goods denominator"
)
expect_true(
  all(bra_yearly$china_goods_share == 1),
  "China goods share uses the goods denominator"
)
expect_true(
  bra_exposure$observed_years[[1]] == 5L,
  "exposure records all five years"
)
expect_true(
  commodity$audit$domestic_rows_excluded[[1]] == 5,
  "domestic rows audited"
)

zero_exposure <- commodity$exposure |>
  dplyr::filter(iso3c == "IMN")
partial_exposure <- commodity$exposure |>
  dplyr::filter(iso3c == "GUF")
expect_true(
  nrow(zero_exposure) == 1L && zero_exposure$pre_goods_exports[[1]] == 0,
  "zero-goods exporter retained"
)
expect_true(
  !any(is.nan(unlist(
    dplyr::select(zero_exposure, dplyr::where(is.numeric)),
    use.names = FALSE
  ))),
  "structural undefined values normalized from NaN to NA"
)
expect_true(
  is.na(zero_exposure$pre_primary_share_mean[[1]]),
  "zero-goods share is structural NA"
)
expect_true(
  partial_exposure$observed_years[[1]] == 1L,
  "partial global coverage retained"
)

commodity_reference_path <- tempfile(fileext = ".csv")
price_reference_path <- tempfile(fileext = ".csv")
price_fixture <- tibble::tibble(
  year = 1997:2016,
  energy_log_change_2007 = 0,
  agriculture_log_change_2007 = 0,
  metals_minerals_log_change_2007 = 0
)
readr::write_csv(commodity$exposure, commodity_reference_path)
readr::write_csv(price_fixture, price_reference_path)
derivation_validation <- validate_sdid_commodity_derivations(
  commodity$exposure,
  price_fixture,
  commodity_reference_path,
  price_reference_path,
  analytic_iso3c = "BRA"
)
expect_true(
  all(assert_sdid_migration_validation(
    derivation_validation,
    sdid_commodity_derivation_validation_names()
  )$passed),
  "full derivation gate accepts global partial coverage outside analytic universe"
)
partial_analytic_validation <- validate_sdid_commodity_derivations(
  commodity$exposure,
  price_fixture,
  commodity_reference_path,
  price_reference_path,
  analytic_iso3c = c("BRA", "GUF")
)
expect_error(
  assert_sdid_migration_validation(
    partial_analytic_validation,
    sdid_commodity_derivation_validation_names()
  ),
  "full derivation gate rejects partial coverage inside analytic universe"
)

unlink(c(
  reference_path,
  itpd_path,
  commodity_reference_path,
  price_reference_path
))
unlink(checkpoint_directory, recursive = TRUE)
message("ALL_STATIC_SDID_MIGRATION_TESTS_PASSED")
