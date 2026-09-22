#!/usr/bin/env Rscript

# Point estimate for an Australia-only synthetic difference-in-differences
# specification. Treatment begins in 2007 by default and can be changed with
# the environment variable `AUSTRALIA_SDID_TREATMENT_YEAR`.
#
# This diagnostic deliberately stays outside the targets pipeline. It reads the
# stored `china_top_m2_goods_panel` object, uses the same 1997-2022 window and
# clean donor rule as `estimate_selected_public_cue_sdid_fect.R`, and computes
# no placebo standard error or other uncertainty measure.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
})

if (!requireNamespace("synthdid", quietly = TRUE)) {
  stop("Package `synthdid` is required.", call. = FALSE)
}

year_start <- 1997L
year_end <- 2022L
treatment_year <- suppressWarnings(as.integer(Sys.getenv(
  "AUSTRALIA_SDID_TREATMENT_YEAR",
  unset = "2007"
)))
if (length(treatment_year) != 1L || is.na(treatment_year) ||
    treatment_year <= year_start || treatment_year > year_end) {
  stop(
    "AUSTRALIA_SDID_TREATMENT_YEAR must be one year in ",
    year_start + 1L, "-", year_end, ".",
    call. = FALSE
  )
}
treated_iso3c <- "AUS"
expected_years <- seq.int(year_start, year_end)

message(
  "Reading stored target `china_top_m2_goods_panel` ",
  "without executing the targets pipeline."
)
panel_raw <- targets::tar_read_raw(
  "china_top_m2_goods_panel",
  store = "_targets"
)

required_cols <- c(
  "iso3c", "country_name", "year", "abs_distance_china", "china_is_top"
)
missing_cols <- setdiff(required_cols, names(panel_raw))
if (length(missing_cols) > 0L) {
  stop(
    "Stored target is missing required column(s): ",
    paste(missing_cols, collapse = ", "),
    call. = FALSE
  )
}

panel <- panel_raw |>
  dplyr::filter(year >= year_start, year <= year_end) |>
  dplyr::select(dplyr::all_of(required_cols)) |>
  dplyr::mutate(
    year = as.integer(year),
    iso3c = as.character(iso3c),
    abs_distance_china = as.numeric(abs_distance_china),
    china_is_top = as.logical(china_is_top)
  ) |>
  dplyr::arrange(iso3c, year)

duplicate_keys <- panel |>
  dplyr::count(iso3c, year, name = "n") |>
  dplyr::filter(n != 1L)
if (nrow(duplicate_keys) > 0L) {
  stop("Duplicate country-year keys in the stored panel.", call. = FALSE)
}

unit_audit <- panel |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    n_years = dplyr::n_distinct(year),
    exact_common_grid = setequal(year, expected_years),
    outcome_complete = all(!is.na(abs_distance_china)),
    rank_complete = all(!is.na(china_is_top)),
    ever_china_top = any(china_is_top %in% TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    complete_common_panel =
      n_years == length(expected_years) &
      exact_common_grid & outcome_complete & rank_complete
  )

clean_donors <- unit_audit |>
  dplyr::filter(complete_common_panel, !ever_china_top) |>
  dplyr::pull(iso3c) |>
  sort()

australia_audit <- unit_audit |>
  dplyr::filter(iso3c == treated_iso3c)
if (nrow(australia_audit) != 1L ||
    !isTRUE(australia_audit$complete_common_panel[[1L]])) {
  stop("Australia does not have the required complete panel.", call. = FALSE)
}
if (length(clean_donors) != 105L) {
  stop(
    "The clean donor count differs from the prior design: ",
    length(clean_donors), " instead of 105.",
    call. = FALSE
  )
}

unit_levels <- c(clean_donors, treated_iso3c)
fit_data <- panel |>
  dplyr::filter(iso3c %in% unit_levels) |>
  dplyr::mutate(.unit_treated = as.integer(iso3c == treated_iso3c)) |>
  dplyr::arrange(.unit_treated, iso3c, year) |>
  dplyr::transmute(
    iso3c = factor(iso3c, levels = unit_levels),
    year,
    Y = abs_distance_china,
    treatment = as.integer(
      iso3c == treated_iso3c & year >= treatment_year
    )
  ) |>
  as.data.frame()

setup <- synthdid::panel.matrices(fit_data)
expected_t0 <- treatment_year - year_start
if (setup$N0 != length(clean_donors) || setup$T0 != expected_t0) {
  stop(
    "Unexpected SDiD dimensions: N0 = ", setup$N0,
    ", T0 = ", setup$T0, ".",
    call. = FALSE
  )
}

fit <- synthdid::synthdid_estimate(
  Y = setup$Y,
  N0 = setup$N0,
  T0 = setup$T0
)

result <- tibble::tibble(
  fit_id = paste0("aus_timing_", treatment_year, "_point"),
  iso3c = treated_iso3c,
  country_name = "Australia",
  treatment_year = treatment_year,
  estimate = as.numeric(fit),
  n_donors = setup$N0,
  n_pre_years = setup$T0,
  n_post_years = ncol(setup$Y) - setup$T0,
  year_start = year_start,
  year_end = year_end,
  placebo_replications = 0L,
  synthdid_version = as.character(utils::packageVersion("synthdid"))
)

output_path <- file.path(
  "data", "processed", "diagnostics", "selected_public_cue_sdid_fect",
  paste0("australia_sdid_", treatment_year, "_point.csv")
)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(result, output_path)
fit_output_path <- sub("\\.csv$", "_fit.rds", output_path)
saveRDS(fit, fit_output_path)

message("Point estimate written to: ", output_path)
message("Fitted synthdid object written to: ", fit_output_path)
print(result, n = Inf, width = Inf)
