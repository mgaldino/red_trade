#!/usr/bin/env Rscript

# Cheap, deterministic tests for the candidate full-union panel construction.
# This script does not call targets and does not estimate any model.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(DBI)
  library(duckdb)
  library(countrycode)
})

# The shell used by this worktree starts R in the C locale. Select an available
# UTF-8 character locale before sourcing the historical functions file.
locale_set <- Sys.setlocale("LC_CTYPE", "pt_BR.UTF-8")
if (is.na(locale_set) || identical(locale_set, "")) {
  stop("Could not select the UTF-8 locale required by scripts/functions.R.")
}
source(file.path("scripts", "functions.R"), encoding = "UTF-8")
source(
  file.path("scripts", "functions_targets_migration.R"),
  encoding = "UTF-8"
)

expect_true <- function(condition, label) {
  if (!isTRUE(condition)) {
    stop("FAIL: ", label, call. = FALSE)
  }
  message("PASS: ", label)
}

expect_error <- function(expression, pattern, label) {
  observed <- tryCatch(
    {
      force(expression)
      NULL
    },
    error = identity
  )
  expect_true(inherits(observed, "error"), paste0(label, " (aborts)"))
  expect_true(
    grepl(pattern, conditionMessage(observed), fixed = TRUE),
    paste0(label, " (message)")
  )
}

make_master_fixture <- function(iso3c, years, status, missing_outcome_years = integer()) {
  stopifnot(length(years) == length(status))
  tibble(
    iso3c = iso3c,
    country_name = iso3c,
    year = as.integer(years),
    china_top_status = as.integer(status),
    trade_rank_observed = !is.na(china_top_status),
    unga_row_present = !year %in% missing_outcome_years,
    outcome_observed = !year %in% missing_outcome_years,
    abs_distance_china = if_else(outcome_observed, 0.25, NA_real_)
  ) |>
    group_by(iso3c) |>
    arrange(year, .by_group = TRUE) |>
    mutate(
      previous_china_top_status = lag(china_top_status),
      china_top_period_start = china_top_status %in% 1L &
        !(lag(china_top_status) %in% 1L),
      china_top_period_id_raw = cumsum(china_top_period_start),
      china_top_period_id = if_else(
        china_top_status %in% 1L,
        china_top_period_id_raw,
        NA_integer_
      )
    ) |>
    ungroup() |>
    dplyr::select(-china_top_period_id_raw)
}

# 1. The acquisition parser aggregates all exporters and fails closed on bad
# trade values.
good_csv <- tempfile(fileext = ".csv")
writeLines(
  c(
    "year,exporter_iso3,importer_iso3,broad_sector,trade",
    "2000,AAA,CHN,Agriculture,1",
    "2000,AAA,CHN,Mining and Energy,2",
    "2000,AAA,CHN,Manufacturing,3",
    "2000,BBB,USA,Agriculture,4",
    "2000,BBB,USA,Mining and Energy,5",
    "2000,BBB,USA,Manufacturing,6"
  ),
  good_csv,
  useBytes = TRUE
)
aggregation <- aggregate_itpde_goods_exports_all_exporters(
  good_csv,
  start_year = 2000L,
  end_year = 2000L
)
expect_true(
  setequal(aggregation$goods_exports$exporter_iso3, c("AAA", "BBB")),
  "ITPD-E aggregation retains every exporter"
)
expect_true(
  identical(sort(aggregation$goods_exports$exports), c(6, 15)),
  "ITPD-E aggregation sums the three goods sectors"
)

bad_csv <- tempfile(fileext = ".csv")
writeLines(
  c(
    "year,exporter_iso3,importer_iso3,broad_sector,trade",
    "2000,AAA,CHN,Agriculture,1",
    "2000,AAA,CHN,Mining and Energy,2",
    "2000,AAA,CHN,Manufacturing,bad"
  ),
  bad_csv,
  useBytes = TRUE
)
expect_error(
  aggregate_itpde_goods_exports_all_exporters(
    bad_csv,
    start_year = 2000L,
    end_year = 2000L
  ),
  "missing or unparseable trade values",
  "ITPD-E parsing fails closed"
)

# 2. Partner ranking uses all exporters and does not break exact top ties.
rank_fixture <- tribble(
  ~year, ~exporter_iso3, ~importer_iso3, ~exports,
  2000L, "AAA", "USA", 100,
  2000L, "AAA", "CHN", 50,
  2000L, "BBB", "USA", 100,
  2000L, "BBB", "CHN", 100,
  2000L, "CCC", "CHN", 120,
  2000L, "CCC", "USA", 30
)
ranked <- rank_itpde_goods_export_destinations(rank_fixture)
expect_true(
  identical(ranked$china_top_status[ranked$iso3c == "AAA"], 0L) &&
    is.na(ranked$china_top_status[ranked$iso3c == "BBB"]) &&
    identical(ranked$china_top_status[ranked$iso3c == "CCC"], 1L),
  "ranking distinguishes China top, another partner top, and an exact tie"
)

# 3. The master starts from the source union and expands every included country
# to the complete requested grid.
master_trade <- ranked |>
  filter(iso3c == "AAA")
master_outcome <- tibble(
  iso3c = "DDD",
  year = 2001L,
  abs_distance_china = 0.4
)
master_union <- build_country_year_full_union_master(
  master_trade,
  master_outcome,
  min_year = 2000L,
  max_year = 2001L
)
expect_true(
  nrow(master_union) == 4L &&
    setequal(master_union$iso3c, c("AAA", "DDD")),
  "master includes trade-only and outcome-only countries"
)
expect_true(
  all(vapply(
    split(master_union$year, master_union$iso3c),
    function(x) identical(sort(x), 2000:2001),
    logical(1)
  )),
  "master has the exact requested year grid"
)

# 4. Treatment follows trade status; outcome missingness affects estimation only.
years <- 1999:2006
treated_fixture <- make_master_fixture(
  "COD",
  years,
  c(0L, rep(1L, 5), 0L, 0L),
  missing_outcome_years = 2002L
)
control_fixture <- make_master_fixture(
  "AAA",
  years,
  rep(0L, length(years))
)
period_data <- build_full_union_status_period_data(
  bind_rows(treated_fixture, control_fixture),
  min_duration_years = 5L,
  min_entry_year = 2000L
)
risk_audit <- build_full_union_risk_set_audit(
  period_data,
  min_untreated_observations = 1L
)
cod_2002 <- risk_audit |>
  filter(iso3c == "COD", year == 2002L)
expect_true(
  nrow(cod_2002) == 1L &&
    cod_2002$china_top_status == 1L &&
    cod_2002$china_top == 1L &&
    cod_2002$risk_set_eligible &&
    !cod_2002$outcome_observed &&
    !cod_2002$estimation_included &&
    cod_2002$row_status == "risk_set_missing_outcome",
  "a treated trade-year with missing outcome stays treated and leaves only at estimation"
)

# 5. A missing commercial year interrupts consecutive duration.
gap_fixture <- make_master_fixture(
  "GAP",
  years,
  c(0L, 1L, NA_integer_, 1L, 1L, 1L, 1L, 0L)
)
gap_periods <- build_full_union_status_period_data(
  gap_fixture,
  min_duration_years = 5L,
  min_entry_year = 2000L
)
expect_true(
  sum(gap_periods$period_summary$qualifies_min_duration) == 0L,
  "a commercial-data gap interrupts duration and prior-year eligibility"
)

# 6. The historical clean-single-entry rule excludes a treated unit with two
# eligible entries even when only one reaches the duration threshold.
multi_fixture <- make_master_fixture(
  "MULTI",
  1999:2008,
  c(0L, 1L, 0L, rep(1L, 5), 0L, 0L)
)
multi_control <- make_master_fixture(
  "CTRL",
  1999:2008,
  rep(0L, 10L)
)
multi_period_data <- build_full_union_status_period_data(
  bind_rows(multi_fixture, multi_control),
  min_duration_years = 5L,
  min_entry_year = 2000L
)
multi_audit <- build_full_union_risk_set_audit(
  multi_period_data,
  clean_single_entry = TRUE,
  min_untreated_observations = 1L
)
expect_true(
  all(!multi_audit$clean_single_entry_unit[multi_audit$iso3c == "MULTI"]) &&
    all(!multi_audit$specification_unit_eligible[multi_audit$iso3c == "MULTI"]),
  "clean-single-entry requires exactly one eligible and one qualifying period"
)

# 7. Switching-allowed keeps units with the same exact modal/longest year set.
grid_fixture <- tribble(
  ~iso3c, ~year,
  "AAA", 2000L,
  "AAA", 2001L,
  "AAA", 2002L,
  "BBB", 2000L,
  "BBB", 2001L,
  "BBB", 2002L,
  "CCC", 2001L,
  "CCC", 2002L,
  "CCC", 2003L
)
common_grid <- filter_modal_common_year_grid(grid_fixture)
expect_true(
  setequal(common_grid$iso3c, c("AAA", "BBB")) &&
    identical(sort(unique(common_grid$year)), 2000:2002),
  "switching-allowed selects an exact common year set"
)

# 8. A failed validation is an abortive gate.
expect_error(
  assert_full_union_status_validation(
    tibble(validation = "deliberate_failure", passed = FALSE)
  ),
  "Full-union status validation failed: deliberate_failure",
  "validation gate fails closed"
)

message("ALL FULL-UNION PANEL TESTS PASSED")
