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
    tibble::tibble(validation = c("known", "unknown"), passed = c(TRUE, NA))
  ),
  "aggregate validation fails closed on NA"
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
sdid_fit_spec <- original_fit_spec
sdid_fit_summary_row <- original_summary_row

# Small ITPD-E fixture: five years, one foreign goods flow, one service flow,
# and one domestic flow per year. The candidate builder must exclude services
# and domestic trade from the goods denominator while auditing the latter.
itpd_path <- tempfile(fileext = ".csv")
fixture <- dplyr::bind_rows(lapply(2004:2008, function(year) {
  tibble::tribble(
    ~exporter_iso3, ~importer_iso3, ~year, ~broad_sector, ~industry_id, ~trade,
    "BRA", "CHN", year, "Agriculture", 1L, 100,
    "BRA", "USA", year, "Services", 36L, 50,
    "BRA", "BRA", year, "Agriculture", 1L, 10,
    "USA", "CHN", year, "Manufacturing", 20L, 200
  )
}))
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

unlink(c(reference_path, itpd_path))
unlink(checkpoint_directory, recursive = TRUE)
message("ALL_STATIC_SDID_MIGRATION_TESTS_PASSED")
