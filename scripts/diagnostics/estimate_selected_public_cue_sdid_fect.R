#!/usr/bin/env Rscript

# Estimate case-specific SDiD models and pooled interactive fixed-effects
# models for countries with a selected public China-rank cue.
#
# This is deliberately outside the targets pipeline. It reads the already
# stored `china_top_m2_goods_panel` target, but never calls tar_make() and never
# writes to `_targets/`.
#
# Design (default window: 1997-2022):
#   * Outcome: absolute UNGA ideal-point distance to China.
#   * Six single-treated SDiD fits: CHL 2008, URY 2013, GAB 2017, QAT 2021,
#     AUS 2009 (public cue), and AUS 2010 (user-requested top-1 timing).
#   * SDiD controls must have a complete outcome/rank panel and must never have
#     China as the largest goods-export destination anywhere in the window.
#   * Placebo standard errors use the shared, checkpointed project helper.
#   * Pooled fect/IFE alternative 1 contains the same clean controls plus the
#     five focal countries. Only focal countries can be treated.
#   * Pooled fect/IFE alternative 2 starts from every complete country panel.
#     Only focal countries receive D = 1. For non-focal countries, current
#     China-top years are masked from estimation, so controls leave and re-enter
#     the comparison pool without becoming treated cases.
#   * For the five focal cases in both alternatives, treatment is status-current
#     after the public cue: it turns off if China later loses top rank.
#   * Both IFE alternatives are also re-estimated after removing Gabon and
#     Qatar entirely and adding Brazil to the focal group, leaving Australia,
#     Brazil, Chile, and Uruguay as focal cases.
#
# Optional environment variables:
#   PUBLIC_CUE_YEAR_START       default 1997
#   PUBLIC_CUE_YEAR_END         default 2022
#   PUBLIC_CUE_PLACEBO_REPS     default 5000
#   PUBLIC_CUE_FECT_BOOTS       default 1000
#   PUBLIC_CUE_CORES            default min(8, physical cores)
#   PUBLIC_CUE_OUTPUT_DIR       default data/processed/diagnostics/
#                                     selected_public_cue_sdid_fect

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(tibble)
  library(targets)
})

required_packages <- c("digest", "fect", "jsonlite", "synthdid")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    "Missing required package(s): ", paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()

read_env_int <- function(name, default, minimum = 1L) {
  raw <- Sys.getenv(name, unset = as.character(default))
  value <- suppressWarnings(as.integer(raw))
  if (length(value) != 1L || is.na(value) || value < minimum) {
    stop(
      name, " must be one integer >= ", minimum, "; received `", raw, "`.",
      call. = FALSE
    )
  }
  value
}

year_start <- read_env_int("PUBLIC_CUE_YEAR_START", 1997L, minimum = 1990L)
year_end <- read_env_int("PUBLIC_CUE_YEAR_END", 2022L, minimum = year_start + 2L)
placebo_replications <- read_env_int("PUBLIC_CUE_PLACEBO_REPS", 5000L)
fect_bootstraps <- read_env_int("PUBLIC_CUE_FECT_BOOTS", 1000L)
fect_min_untreated_periods <- 1L
parallel_cores <- read_env_int(
  "PUBLIC_CUE_CORES",
  sdid_available_cores(cap = 8L)
)

target_store <- "_targets"
input_target <- "china_top_m2_goods_panel"
output_dir <- Sys.getenv(
  "PUBLIC_CUE_OUTPUT_DIR",
  unset = file.path(
    "data", "processed", "diagnostics", "selected_public_cue_sdid_fect"
  )
)
checkpoint_dir <- file.path(output_dir, "checkpoints")
fit_dir <- file.path(output_dir, "fits")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)

expected_years <- seq.int(year_start, year_end)
expected_n_years <- length(expected_years)

# The public-cue years are validated below against the maintained salience
# appendix. The second Australian row is intentionally a separate timing fit.
cue_years <- tibble::tribble(
  ~iso3c, ~country_name, ~public_cue_year,
  "CHL", "Chile",     2008L,
  "URY", "Uruguay",   2013L,
  "GAB", "Gabon",     2017L,
  "QAT", "Qatar",     2021L,
  "AUS", "Australia", 2009L
)
brazil_cue_year <- tibble::tribble(
  ~iso3c, ~country_name, ~public_cue_year,
  "BRA", "Brazil", 2009L
)
reduced_cue_years <- dplyr::bind_rows(
  cue_years |>
    dplyr::filter(!iso3c %in% c("GAB", "QAT")),
  brazil_cue_year
)
all_model_cue_years <- dplyr::bind_rows(cue_years, brazil_cue_year) |>
  dplyr::distinct(iso3c, .keep_all = TRUE)
reduced_focal_iso3c <- reduced_cue_years$iso3c

sdid_specs <- tibble::tribble(
  ~fit_id,          ~iso3c, ~country_name, ~treatment_year, ~timing_definition,
  "chl_cue_2008",  "CHL", "Chile",      2008L, "selected public-cue year",
  "ury_cue_2013",  "URY", "Uruguay",    2013L, "selected public-cue year",
  "gab_cue_2017",  "GAB", "Gabon",      2017L, "selected public-cue year",
  "qat_cue_2021",  "QAT", "Qatar",      2021L, "selected public-cue year",
  "aus_cue_2009",  "AUS", "Australia",  2009L, "selected public-cue year",
  "aus_top1_2010", "AUS", "Australia",  2010L,
  "user-requested year when China is measured as top 1"
)

if (any(sdid_specs$treatment_year <= year_start) ||
    any(sdid_specs$treatment_year > year_end)) {
  stop("Every treatment year must fall strictly inside the analysis window.",
       call. = FALSE)
}

cue_source_path <- file.path(
  "data", "processed", "status_cue_salience", "status_cue_appendix_table.csv"
)
if (!file.exists(cue_source_path)) {
  stop("Missing cue-year source: ", cue_source_path, call. = FALSE)
}

cue_source <- readr::read_csv(cue_source_path, show_col_types = FALSE) |>
  dplyr::filter(iso3c %in% all_model_cue_years$iso3c) |>
  dplyr::transmute(iso3c, recorded_entry_year = as.integer(entry_year))

cue_validation <- all_model_cue_years |>
  dplyr::left_join(cue_source, by = "iso3c") |>
  dplyr::mutate(matches_recorded_entry = public_cue_year == recorded_entry_year)

if (nrow(cue_validation) != nrow(all_model_cue_years) ||
    any(is.na(cue_validation$recorded_entry_year)) ||
    any(!cue_validation$matches_recorded_entry)) {
  stop(
    "The maintained salience appendix does not match the selected cue years.",
    call. = FALSE
  )
}

message("Reading stored target `", input_target, "` (no pipeline execution).")
panel_raw <- targets::tar_read_raw(input_target, store = target_store)

required_cols <- c(
  "iso3c", "country_name", "year", "abs_distance_china",
  "china_is_top", "top_partner"
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
  stop("Duplicate country-year keys in input target.", call. = FALSE)
}

unit_audit <- panel |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    n_years = dplyr::n_distinct(year),
    first_year = min(year),
    last_year = max(year),
    exact_common_grid = setequal(year, expected_years),
    outcome_complete = all(!is.na(abs_distance_china)),
    rank_complete = all(!is.na(china_is_top)),
    ever_china_top = any(china_is_top %in% TRUE),
    first_china_top_year = ifelse(
      any(china_is_top %in% TRUE),
      min(year[china_is_top %in% TRUE]),
      NA_integer_
    ),
    last_china_top_year = ifelse(
      any(china_is_top %in% TRUE),
      max(year[china_is_top %in% TRUE]),
      NA_integer_
    ),
    china_top_years = paste(year[china_is_top %in% TRUE], collapse = ";"),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    complete_common_panel =
      n_years == expected_n_years & exact_common_grid &
      outcome_complete & rank_complete,
    focal_country = iso3c %in% all_model_cue_years$iso3c,
    sample_role = dplyr::case_when(
      focal_country & complete_common_panel ~ "focal_treated_country",
      focal_country ~ "excluded_focal_incomplete",
      complete_common_panel & !ever_china_top ~ "clean_never_china_top_control",
      complete_common_panel & ever_china_top ~ "excluded_ever_china_top",
      TRUE ~ "excluded_incomplete_common_panel"
    )
  ) |>
  dplyr::arrange(sample_role, iso3c)

focal_audit <- unit_audit |>
  dplyr::filter(focal_country)
if (nrow(focal_audit) != nrow(all_model_cue_years) ||
    any(!focal_audit$complete_common_panel)) {
  stop("At least one focal country lacks a complete outcome/rank panel.",
       call. = FALSE)
}

clean_donors <- unit_audit |>
  dplyr::filter(sample_role == "clean_never_china_top_control") |>
  dplyr::pull(iso3c) |>
  sort()

if (length(clean_donors) < 2L) {
  stop("Fewer than two clean donor countries remain.", call. = FALSE)
}

readr::write_csv(cue_validation, file.path(output_dir, "cue_year_validation.csv"))
readr::write_csv(unit_audit, file.path(output_dir, "unit_eligibility_audit.csv"))

sdid_membership <- tidyr::crossing(
  sdid_specs |>
    dplyr::select(fit_id, treated_iso3c = iso3c),
  unit_audit |>
    dplyr::select(
      iso3c, country_name, complete_common_panel, ever_china_top,
      focal_country, sample_role
    )
) |>
  dplyr::mutate(
    fit_role = dplyr::case_when(
      iso3c == treated_iso3c ~ "treated",
      iso3c %in% clean_donors ~ "included_donor",
      complete_common_panel & ever_china_top ~
        "excluded_ever_china_top_in_window",
      TRUE ~ "excluded_incomplete_common_panel"
    )
  ) |>
  dplyr::arrange(fit_id, fit_role, iso3c)
readr::write_csv(
  sdid_membership,
  file.path(output_dir, "sdid_sample_membership.csv")
)

fit_single_sdid <- function(spec) {
  treated_iso3c <- spec$iso3c[[1L]]
  treatment_year <- spec$treatment_year[[1L]]
  fit_id <- spec$fit_id[[1L]]
  units <- c(clean_donors, treated_iso3c)

  fit_data <- panel |>
    dplyr::filter(iso3c %in% units) |>
    dplyr::mutate(
      treatment = as.integer(
        iso3c == treated_iso3c & year >= treatment_year
      ),
      .unit_treated = as.integer(iso3c == treated_iso3c)
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year)

  counts <- fit_data |>
    dplyr::count(iso3c, name = "n_years")
  if (nrow(counts) != length(units) ||
      any(counts$n_years != expected_n_years)) {
    stop("Unbalanced SDiD input for ", fit_id, ".", call. = FALSE)
  }
  if (anyNA(fit_data$abs_distance_china) || anyNA(fit_data$treatment)) {
    stop("Missing SDiD input for ", fit_id, ".", call. = FALSE)
  }

  unit_levels <- c(clean_donors, treated_iso3c)
  panel_data <- fit_data |>
    dplyr::transmute(
      iso3c = factor(iso3c, levels = unit_levels),
      year = as.integer(year),
      Y = abs_distance_china,
      treatment = as.integer(treatment)
    ) |>
    as.data.frame()

  setup <- synthdid::panel.matrices(panel_data)
  if (setup$N0 != length(clean_donors)) {
    stop("Unexpected donor count for ", fit_id, ".", call. = FALSE)
  }
  expected_t0 <- treatment_year - year_start
  if (setup$T0 != expected_t0) {
    stop(
      "Unexpected pretreatment count for ", fit_id,
      ": expected ", expected_t0, ", got ", setup$T0, ".",
      call. = FALSE
    )
  }

  fit <- synthdid::synthdid_estimate(
    Y = setup$Y,
    N0 = setup$N0,
    T0 = setup$T0
  )

  message(
    "  ", fit_id, ": ATT = ", sprintf("%.6f", as.numeric(fit)),
    "; computing ", placebo_replications, " placebo replications."
  )
  se_placebo <- as.numeric(sdid_placebo_se(
    fit,
    replications = placebo_replications,
    seed = SDID_PLACEBO_SEED,
    cores = parallel_cores,
    checkpoint_dir = checkpoint_dir,
    label = fit_id
  ))

  fit_setup <- attr(fit, "setup")
  fit_weights <- attr(fit, "weights")
  outcome_matrix <- fit_setup$Y
  donor_outcomes <- outcome_matrix[seq_len(fit_setup$N0), , drop = FALSE]
  treated_outcome <- as.numeric(outcome_matrix[fit_setup$N0 + 1L, ])
  synthetic_outcome <- as.numeric(
    t(as.numeric(fit_weights$omega)) %*% donor_outcomes
  )
  raw_gap <- treated_outcome - synthetic_outcome
  pre_idx <- seq_len(fit_setup$T0)
  post_idx <- seq.int(fit_setup$T0 + 1L, ncol(outcome_matrix))
  pre_gap_weighted <- sum(as.numeric(fit_weights$lambda) * raw_gap[pre_idx])
  adjusted_synthetic <- synthetic_outcome + pre_gap_weighted
  adjusted_gap <- treated_outcome - adjusted_synthetic
  att_from_path <- mean(adjusted_gap[post_idx])

  if (!isTRUE(all.equal(
    att_from_path,
    as.numeric(fit),
    tolerance = 1e-8,
    check.attributes = FALSE
  ))) {
    stop("SDiD path decomposition failed for ", fit_id, ".", call. = FALSE)
  }

  estimate <- as.numeric(fit)
  z_value <- if (is.finite(se_placebo) && se_placebo > 0) {
    estimate / se_placebo
  } else {
    NA_real_
  }

  result <- spec |>
    dplyr::transmute(
      fit_id,
      iso3c,
      country_name,
      treatment_year,
      timing_definition,
      outcome = "Absolute UNGA ideal-point distance to China",
      treatment = "Absorbing post-timing indicator for the focal SDiD fit",
      donor_rule = paste0(
        "Complete ", year_start, "-", year_end,
        " panel; China never top goods-export destination in that window"
      ),
      estimate = estimate,
      se_placebo = se_placebo,
      ci_95_low = estimate - stats::qnorm(0.975) * se_placebo,
      ci_95_high = estimate + stats::qnorm(0.975) * se_placebo,
      z_value = z_value,
      p_normal_two_sided = ifelse(
        is.na(z_value), NA_real_, 2 * stats::pnorm(-abs(z_value))
      ),
      rmspe_pre_level_adjusted = sqrt(mean(adjusted_gap[pre_idx]^2)),
      rmspe_post_level_adjusted = sqrt(mean(adjusted_gap[post_idx]^2)),
      rmspe_ratio = rmspe_post_level_adjusted / rmspe_pre_level_adjusted,
      n_donors = fit_setup$N0,
      n_treated = nrow(fit_setup$Y) - fit_setup$N0,
      n_pre_years = fit_setup$T0,
      n_post_years = ncol(fit_setup$Y) - fit_setup$T0,
      year_start = year_start,
      year_end = year_end,
      placebo_replications = placebo_replications,
      placebo_seed = SDID_PLACEBO_SEED,
      synthdid_version = as.character(utils::packageVersion("synthdid"))
    )

  unit_weights <- tibble::tibble(
    fit_id = fit_id,
    donor_iso3c = rownames(fit_setup$Y)[seq_len(fit_setup$N0)],
    unit_weight = as.numeric(fit_weights$omega)
  ) |>
    dplyr::arrange(dplyr::desc(unit_weight), donor_iso3c) |>
    dplyr::mutate(
      weight_rank = dplyr::row_number(),
      cumulative_weight = cumsum(unit_weight),
      effective_donor_count = 1 / sum(unit_weight^2)
    )

  time_weights <- tibble::tibble(
    fit_id = fit_id,
    year = as.integer(colnames(fit_setup$Y)[pre_idx]),
    time_weight = as.numeric(fit_weights$lambda)
  ) |>
    dplyr::arrange(year)

  path <- tibble::tibble(
    fit_id = fit_id,
    iso3c = treated_iso3c,
    treatment_year = treatment_year,
    year = as.integer(colnames(fit_setup$Y)),
    post_treatment = year >= treatment_year,
    observed_outcome = treated_outcome,
    synthetic_outcome = synthetic_outcome,
    level_adjusted_synthetic_outcome = adjusted_synthetic,
    raw_gap = raw_gap,
    level_adjusted_gap = adjusted_gap
  )

  saveRDS(fit, file.path(fit_dir, paste0("sdid_", fit_id, ".rds")))

  list(
    result = result,
    unit_weights = unit_weights,
    time_weights = time_weights,
    path = path
  )
}

message(
  "Estimating ", nrow(sdid_specs), " single-treated SDiD fits with ",
  length(clean_donors), " clean donors."
)
sdid_objects <- lapply(
  seq_len(nrow(sdid_specs)),
  function(i) fit_single_sdid(sdid_specs[i, , drop = FALSE])
)

sdid_results <- dplyr::bind_rows(lapply(sdid_objects, `[[`, "result"))
sdid_unit_weights <- dplyr::bind_rows(
  lapply(sdid_objects, `[[`, "unit_weights")
)
sdid_time_weights <- dplyr::bind_rows(
  lapply(sdid_objects, `[[`, "time_weights")
)
sdid_paths <- dplyr::bind_rows(lapply(sdid_objects, `[[`, "path"))

readr::write_csv(sdid_results, file.path(output_dir, "sdid_results.csv"))
readr::write_csv(
  sdid_unit_weights,
  file.path(output_dir, "sdid_unit_weights.csv")
)
readr::write_csv(
  sdid_time_weights,
  file.path(output_dir, "sdid_time_weights.csv")
)
readr::write_csv(sdid_paths, file.path(output_dir, "sdid_paths.csv"))

# Pooled IFE alternatives. In both, focal treatment is current China-top status
# at/after the selected public cue. In the second model, non-focal China-top
# outcomes are masked so those countries leave and re-enter the comparison
# pool without being coded as treated cases.
complete_units <- unit_audit |>
  dplyr::filter(complete_common_panel) |>
  dplyr::pull(iso3c) |>
  sort()

add_focal_cue_fields <- function(data, focal_cues) {
  data |>
    dplyr::left_join(
      focal_cues |>
        dplyr::select(iso3c, public_cue_year),
      by = "iso3c"
    ) |>
    dplyr::mutate(
      focal_country = !is.na(public_cue_year),
      public_cue_year = as.integer(public_cue_year),
      cue_group = dplyr::if_else(
        focal_country,
        "selected_public_cue",
        "other_countries"
      )
    )
}

fect_clean_panel <- panel |>
  dplyr::filter(iso3c %in% c(clean_donors, cue_years$iso3c)) |>
  add_focal_cue_fields(cue_years) |>
  dplyr::mutate(
    treatment = as.integer(
      focal_country & year >= public_cue_year & china_is_top %in% TRUE
    ),
    model_outcome = abs_distance_china,
    eligible_as_control = !focal_country,
    country_id = as.integer(factor(iso3c)),
    model_id = "clean_controls"
  ) |>
  dplyr::arrange(country_id, year)

fect_switching_panel <- panel |>
  dplyr::filter(iso3c %in% complete_units) |>
  add_focal_cue_fields(cue_years) |>
  dplyr::mutate(
    treatment = as.integer(
      focal_country & year >= public_cue_year & china_is_top %in% TRUE
    ),
    eligible_as_control = !focal_country & !china_is_top %in% TRUE,
    model_outcome = dplyr::if_else(
      !focal_country & china_is_top %in% TRUE,
      NA_real_,
      abs_distance_china
    ),
    country_id = as.integer(factor(iso3c)),
    model_id = "full_switching"
  ) |>
  dplyr::arrange(country_id, year)

fect_clean_reduced_panel <- panel |>
  dplyr::filter(iso3c %in% c(clean_donors, reduced_focal_iso3c)) |>
  add_focal_cue_fields(reduced_cue_years) |>
  dplyr::mutate(
    treatment = as.integer(
      focal_country & year >= public_cue_year & china_is_top %in% TRUE
    ),
    model_outcome = abs_distance_china,
    eligible_as_control = !focal_country,
    country_id = as.integer(factor(iso3c)),
    model_id = "clean_controls_without_gab_qat"
  ) |>
  dplyr::arrange(country_id, year)

fect_switching_reduced_panel <- panel |>
  dplyr::filter(
    iso3c %in% complete_units,
    !iso3c %in% c("GAB", "QAT")
  ) |>
  add_focal_cue_fields(reduced_cue_years) |>
  dplyr::mutate(
    treatment = as.integer(
      focal_country & year >= public_cue_year & china_is_top %in% TRUE
    ),
    eligible_as_control = !focal_country & !china_is_top %in% TRUE,
    model_outcome = dplyr::if_else(
      !focal_country & china_is_top %in% TRUE,
      NA_real_,
      abs_distance_china
    ),
    country_id = as.integer(factor(iso3c)),
    model_id = "full_switching_without_gab_qat"
  ) |>
  dplyr::arrange(country_id, year)

validate_fect_panel <- function(
    data,
    model_id,
    expected_units,
    expected_focal_iso3c,
    switching_controls = FALSE) {
  counts <- data |>
    dplyr::count(iso3c, name = "n_years")
  if (any(counts$n_years != expected_n_years) ||
      nrow(counts) != expected_units ||
      anyNA(data$abs_distance_china) ||
      anyNA(data$treatment) ||
      anyNA(data$eligible_as_control)) {
    stop(model_id, " is not strongly balanced and complete.", call. = FALSE)
  }
  focal_treated <- data |>
    dplyr::filter(focal_country, treatment == 1L) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c)
  if (!setequal(focal_treated, expected_focal_iso3c)) {
    stop(
      model_id,
      " does not treat exactly the intended focal countries.",
      call. = FALSE
    )
  }
  expected_mask <- !data$focal_country & data$china_is_top %in% TRUE
  if (switching_controls) {
    if (any(!is.na(data$model_outcome[expected_mask])) ||
        any(is.na(data$model_outcome[!expected_mask]))) {
      stop(
        model_id,
        " does not mask exactly the non-focal China-top country-years.",
        call. = FALSE
      )
    }
  } else if (anyNA(data$model_outcome)) {
    stop(model_id, " unexpectedly masks outcomes.", call. = FALSE)
  }
  invisible(TRUE)
}

validate_fect_panel(
  fect_clean_panel,
  "Clean-control fect panel",
  length(clean_donors) + nrow(cue_years),
  cue_years$iso3c
)
validate_fect_panel(
  fect_switching_panel,
  "Full-switching fect panel",
  length(complete_units),
  cue_years$iso3c,
  switching_controls = TRUE
)
validate_fect_panel(
  fect_clean_reduced_panel,
  "Clean-control fect panel without Gabon/Qatar",
  length(clean_donors) + length(reduced_focal_iso3c),
  reduced_focal_iso3c
)
validate_fect_panel(
  fect_switching_reduced_panel,
  "Full-switching fect panel without Gabon/Qatar",
  length(complete_units) - 2L,
  reduced_focal_iso3c,
  switching_controls = TRUE
)
all_clean_panels <- dplyr::bind_rows(
  fect_clean_panel,
  fect_clean_reduced_panel
)
all_fect_panels <- dplyr::bind_rows(
  all_clean_panels,
  fect_switching_panel,
  fect_switching_reduced_panel
)
if (any(
  all_fect_panels$treatment == 1L & !all_fect_panels$focal_country
)) {
  stop("A non-focal country is treated in an IFE model.",
       call. = FALSE)
}

make_fect_treatment_audit <- function(data) {
  data |>
    dplyr::group_by(
      model_id, iso3c, country_name, focal_country, cue_group,
      public_cue_year
    ) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      treatment_lag = dplyr::lag(treatment, default = 0L),
      treatment_entry = treatment == 1L & treatment_lag == 0L,
      treatment_exit = treatment == 0L & treatment_lag == 1L,
      control_eligibility_lag = dplyr::lag(
        eligible_as_control,
        default = FALSE
      ),
      control_pool_entry = dplyr::row_number() > 1L &
        eligible_as_control & !control_eligibility_lag,
      control_pool_exit = dplyr::row_number() > 1L &
        !eligible_as_control & control_eligibility_lag
    ) |>
    dplyr::summarise(
      first_year = min(year),
      last_year = max(year),
      current_china_top_years = sum(china_is_top %in% TRUE),
      china_top_years_before_cue = ifelse(
        dplyr::first(focal_country),
        sum(
          china_is_top %in% TRUE &
            year < dplyr::first(public_cue_year),
          na.rm = TRUE
        ),
        NA_integer_
      ),
      treated_years = sum(treatment == 1L),
      untreated_years = sum(treatment == 0L),
      observed_model_years = sum(!is.na(model_outcome)),
      masked_model_years = sum(is.na(model_outcome)),
      eligible_control_years = sum(eligible_as_control),
      control_pool_entries = sum(control_pool_entry),
      control_pool_exits = sum(control_pool_exit),
      entries = sum(treatment_entry),
      exits = sum(treatment_exit),
      first_treated_year = ifelse(
        any(treatment == 1L),
        min(year[treatment == 1L]),
        NA_integer_
      ),
      last_treated_year = ifelse(
        any(treatment == 1L),
        max(year[treatment == 1L]),
        NA_integer_
      ),
      off_years_after_first_entry = ifelse(
        any(treatment == 1L),
        sum(year > min(year[treatment == 1L]) & treatment == 0L),
        0L
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      model_role = dplyr::case_when(
        focal_country ~ "focal_public_cue_case",
        eligible_control_years == 0L ~ "never_eligible_as_control",
        masked_model_years > 0L ~ "switching_control",
        TRUE ~ "clean_control"
      )
    ) |>
    dplyr::arrange(model_id, dplyr::desc(focal_country), iso3c)
}

fect_treatment_audit <- dplyr::bind_rows(
  make_fect_treatment_audit(fect_clean_panel),
  make_fect_treatment_audit(fect_switching_panel),
  make_fect_treatment_audit(fect_clean_reduced_panel),
  make_fect_treatment_audit(fect_switching_reduced_panel)
)

readr::write_csv(
  fect_clean_panel |>
    dplyr::select(
      model_id, iso3c, country_name, country_id, year,
      abs_distance_china, model_outcome, china_is_top, public_cue_year,
      focal_country, cue_group, eligible_as_control, treatment
    ),
  file.path(output_dir, "fect_clean_controls_panel.csv")
)
readr::write_csv(
  fect_switching_panel |>
    dplyr::select(
      model_id, iso3c, country_name, country_id, year,
      abs_distance_china, model_outcome, china_is_top, public_cue_year,
      focal_country, cue_group, eligible_as_control, treatment
    ),
  file.path(output_dir, "fect_full_switching_panel.csv")
)
readr::write_csv(
  fect_clean_reduced_panel |>
    dplyr::select(
      model_id, iso3c, country_name, country_id, year,
      abs_distance_china, model_outcome, china_is_top, public_cue_year,
      focal_country, cue_group, eligible_as_control, treatment
    ),
  file.path(output_dir, "fect_clean_controls_without_gab_qat_panel.csv")
)
readr::write_csv(
  fect_switching_reduced_panel |>
    dplyr::select(
      model_id, iso3c, country_name, country_id, year,
      abs_distance_china, model_outcome, china_is_top, public_cue_year,
      focal_country, cue_group, eligible_as_control, treatment
    ),
  file.path(output_dir, "fect_full_switching_without_gab_qat_panel.csv")
)
readr::write_csv(
  fect_treatment_audit,
  file.path(output_dir, "fect_treatment_audit.csv")
)

extract_selected_factors <- function(fit) {
  if (!is.null(fit$r.cv) && "r" %in% names(fit$r.cv)) {
    as.integer(fit$r.cv[["r"]])
  } else {
    NA_integer_
  }
}

extract_fect_dynamics <- function(fit, model_id) {
  overall <- tibble::tibble(
    model_id = model_id,
    estimand_group = "all_treated_episodes",
    switch_type = "switch_on_att",
    event_time = as.integer(fit$time),
    count = as.numeric(fit$count),
    estimate = as.numeric(fit$est.att[, 1]),
    se = as.numeric(fit$est.att[, 2]),
    ci_95_low = as.numeric(fit$est.att[, 3]),
    ci_95_high = as.numeric(fit$est.att[, 4])
  )

  if (is.null(fit$est.group.output) || length(fit$est.group.output) == 0L) {
    return(overall)
  }

  group_rows <- list()
  row_index <- 0L
  for (group_name in names(fit$est.group.output)) {
    inference <- fit$est.group.output[[group_name]]
    raw <- fit$group.output[[group_name]]
    if (!is.null(inference$att.on) && nrow(inference$att.on) > 0L) {
      row_index <- row_index + 1L
      group_rows[[row_index]] <- tibble::tibble(
        model_id = model_id,
        estimand_group = group_name,
        switch_type = "switch_on_att",
        event_time = as.integer(raw$time.on),
        count = as.numeric(raw$count.on),
        estimate = as.numeric(inference$att.on[, 1]),
        se = as.numeric(inference$att.on[, 2]),
        ci_95_low = as.numeric(inference$att.on[, 3]),
        ci_95_high = as.numeric(inference$att.on[, 4])
      )
    }
    if (!is.null(inference$att.off) && nrow(inference$att.off) > 0L) {
      row_index <- row_index + 1L
      group_rows[[row_index]] <- tibble::tibble(
        model_id = model_id,
        estimand_group = group_name,
        switch_type = "switch_off_art",
        event_time = as.integer(raw$time.off),
        count = as.numeric(raw$count.off),
        estimate = as.numeric(inference$att.off[, 1]),
        se = as.numeric(inference$att.off[, 2]),
        ci_95_low = as.numeric(inference$att.off[, 3]),
        ci_95_high = as.numeric(inference$att.off[, 4])
      )
    }
  }
  dplyr::bind_rows(overall, group_rows)
}

extract_fect_factor_outputs <- function(fit, panel_data, model_id) {
  if (is.null(fit$factor) || ncol(as.matrix(fit$factor)) == 0L) {
    return(list(
      factors = tibble::tibble(
        model_id = character(), year = integer(), factor = character(),
        value = double(), value_standardized = double()
      ),
      loadings = tibble::tibble(
        model_id = character(), country_id = integer(), iso3c = character(),
        country_name = character(), factor = character(), loading = double()
      )
    ))
  }

  factor_matrix <- as.matrix(fit$factor)
  colnames(factor_matrix) <- paste0("factor_", seq_len(ncol(factor_matrix)))
  factors <- as.data.frame(factor_matrix) |>
    dplyr::mutate(
      model_id = model_id,
      year = as.integer(fit$rawtime),
      .before = 1L
    ) |>
    tidyr::pivot_longer(
      cols = dplyr::starts_with("factor_"),
      names_to = "factor",
      values_to = "value"
    ) |>
    dplyr::group_by(model_id, factor) |>
    dplyr::mutate(value_standardized = as.numeric(scale(value))) |>
    dplyr::ungroup()

  loading_matrix <- as.matrix(fit$lambda)
  colnames(loading_matrix) <- paste0(
    "factor_", seq_len(ncol(loading_matrix))
  )
  id_lookup <- panel_data |>
    dplyr::distinct(country_id, iso3c, country_name)
  loadings <- as.data.frame(loading_matrix) |>
    dplyr::mutate(
      model_id = model_id,
      country_id = as.integer(fit$id),
      .before = 1L
    ) |>
    dplyr::left_join(id_lookup, by = "country_id") |>
    tidyr::pivot_longer(
      cols = dplyr::starts_with("factor_"),
      names_to = "factor",
      values_to = "loading"
    ) |>
    dplyr::select(
      model_id, country_id, iso3c, country_name, factor, loading
    )

  list(factors = factors, loadings = loadings)
}

run_fect_alternative <- function(panel_data, model_id) {
  message(
    "Estimating fect alternative `", model_id, "` with ",
    dplyr::n_distinct(panel_data$iso3c), " requested units and ",
    fect_bootstraps, " bootstrap replications."
  )
  set.seed(42L)
  timing <- system.time({
    fit <- fect::fect(
      model_outcome ~ treatment,
      data = as.data.frame(panel_data),
      index = c("country_id", "year"),
      method = "ife",
      force = "two-way",
      na.rm = FALSE,
      em = TRUE,
      se = TRUE,
      nboots = fect_bootstraps,
      parallel = FALSE,
      CV = TRUE,
      r = c(0, 3),
      min.T0 = fect_min_untreated_periods,
      max.missing = expected_n_years,
      seed = 42L
    )
  })

  included_panel <- panel_data |>
    dplyr::filter(country_id %in% fit$id)
  overall_se <- stats::sd(as.numeric(fit$att.avg.boot), na.rm = TRUE)
  overall_z <- if (is.finite(overall_se) && overall_se > 0) {
    as.numeric(fit$att.avg) / overall_se
  } else {
    NA_real_
  }
  included_control_profiles <- included_panel |>
    dplyr::filter(!focal_country) |>
    dplyr::group_by(country_id) |>
    dplyr::summarise(
      ever_eligible = any(eligible_as_control),
      ever_ineligible = any(!eligible_as_control),
      .groups = "drop"
    )
  common_fields <- tibble::tibble(
    outcome = "Absolute UNGA ideal-point distance to China",
    n_requested_units = dplyr::n_distinct(panel_data$iso3c),
    n_estimated_units = length(fit$id),
    n_treated_units = as.integer(fit$Ntr),
    n_never_treated_units = as.integer(fit$Nco),
    selected_factors = extract_selected_factors(fit),
    treatment_reversals_detected_by_fect = as.integer(fit$hasRevs),
    year_start = year_start,
    year_end = year_end,
    bootstrap_replications = fect_bootstraps,
    bootstrap_seed = 42L,
    minimum_untreated_periods = fect_min_untreated_periods,
    masked_nonfocal_country_years = sum(
      is.na(included_panel$model_outcome) & !included_panel$focal_country
    ),
    switching_control_units = sum(
      included_control_profiles$ever_eligible &
        included_control_profiles$ever_ineligible
    ),
    bootstrap_error_process = ifelse(
      is.null(fit$para.error),
      NA_character_,
      as.character(fit$para.error)
    ),
    elapsed_seconds = as.numeric(timing[["elapsed"]]),
    fect_version = as.character(utils::packageVersion("fect"))
  )

  overall_result <- tibble::tibble(
    model_id = model_id,
    estimand_group = "focal_public_cue_cases",
    target_estimand = TRUE,
    treatment_definition = ifelse(
      startsWith(model_id, "clean_controls"),
      paste0(
        "Focal countries: post-cue x current China-top; ",
        "all other units never China-top"
      ),
      paste0(
        "Only focal countries are treated post-cue x current China-top; ",
        "non-focal China-top country-years are masked from the comparison pool"
      )
    ),
    estimate = as.numeric(fit$att.avg),
    se_bootstrap = overall_se,
    ci_95_low = as.numeric(fit$att.avg) -
      stats::qnorm(0.975) * overall_se,
    ci_95_high = as.numeric(fit$att.avg) +
      stats::qnorm(0.975) * overall_se,
    p_normal_two_sided = ifelse(
      is.na(overall_z), NA_real_, 2 * stats::pnorm(-abs(overall_z))
    ),
    n_estimand_treated_units = as.integer(fit$Ntr),
    n_treated_country_years = sum(included_panel$treatment == 1L)
  ) |>
    dplyr::bind_cols(common_fields)

  sample_audit <- panel_data |>
    dplyr::group_by(
      model_id, country_id, iso3c, country_name, focal_country, cue_group
    ) |>
    dplyr::summarise(
      observed_model_periods = sum(!is.na(model_outcome)),
      masked_model_periods = sum(is.na(model_outcome)),
      eligible_control_periods = sum(eligible_as_control),
      treated_periods = sum(treatment == 1L),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      included_by_fect = country_id %in% fit$id,
      ever_treated_in_model = country_id %in%
        unique(panel_data$country_id[panel_data$treatment == 1L])
    ) |>
    dplyr::arrange(dplyr::desc(focal_country), iso3c)

  factor_outputs <- extract_fect_factor_outputs(fit, panel_data, model_id)
  saveRDS(fit, file.path(fit_dir, paste0("fect_", model_id, ".rds")))

  list(
    fit = fit,
    results = overall_result,
    dynamic = extract_fect_dynamics(fit, model_id),
    factors = factor_outputs$factors,
    loadings = factor_outputs$loadings,
    sample_audit = sample_audit
  )
}

fect_clean <- run_fect_alternative(
  fect_clean_panel,
  model_id = "clean_controls"
)
fect_switching <- run_fect_alternative(
  fect_switching_panel,
  model_id = "full_switching"
)
fect_clean_reduced <- run_fect_alternative(
  fect_clean_reduced_panel,
  model_id = "clean_controls_without_gab_qat"
)
fect_switching_reduced <- run_fect_alternative(
  fect_switching_reduced_panel,
  model_id = "full_switching_without_gab_qat"
)

fect_results <- dplyr::bind_rows(
  fect_clean$results,
  fect_switching$results,
  fect_clean_reduced$results,
  fect_switching_reduced$results
)
fect_dynamic <- dplyr::bind_rows(
  fect_clean$dynamic,
  fect_switching$dynamic,
  fect_clean_reduced$dynamic,
  fect_switching_reduced$dynamic
)
fect_factors <- dplyr::bind_rows(
  fect_clean$factors,
  fect_switching$factors,
  fect_clean_reduced$factors,
  fect_switching_reduced$factors
)
fect_loadings <- dplyr::bind_rows(
  fect_clean$loadings,
  fect_switching$loadings,
  fect_clean_reduced$loadings,
  fect_switching_reduced$loadings
)
fect_sample_audit <- dplyr::bind_rows(
  fect_clean$sample_audit,
  fect_switching$sample_audit,
  fect_clean_reduced$sample_audit,
  fect_switching_reduced$sample_audit
)

readr::write_csv(fect_results, file.path(output_dir, "fect_results.csv"))
readr::write_csv(fect_dynamic, file.path(output_dir, "fect_dynamic.csv"))
readr::write_csv(
  fect_factors,
  file.path(output_dir, "fect_latent_factors.csv")
)
readr::write_csv(
  fect_loadings,
  file.path(output_dir, "fect_factor_loadings.csv")
)
readr::write_csv(
  fect_sample_audit,
  file.path(output_dir, "fect_model_sample_audit.csv")
)

target_meta <- targets::tar_meta(
  fields = c(name, data, command, time),
  store = target_store
) |>
  dplyr::filter(name == input_target) |>
  dplyr::mutate(time = as.character(time))

readr::write_csv(target_meta, file.path(output_dir, "input_target_metadata.csv"))
capture.output(
  utils::sessionInfo(),
  file = file.path(output_dir, "session_info.txt")
)

format_num <- function(x, digits = 4L) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

sdid_report_rows <- sdid_results |>
  dplyr::transmute(
    Fit = fit_id,
    Country = country_name,
    Year = treatment_year,
    ATT = format_num(estimate),
    `Placebo SE` = format_num(se_placebo),
    `95% CI` = paste0("[", format_num(ci_95_low), ", ",
                      format_num(ci_95_high), "]"),
    `Pre/Post` = paste0(n_pre_years, "/", n_post_years),
    Donors = n_donors
  )

fect_report_rows <- fect_results |>
  dplyr::transmute(
    Alternative = dplyr::recode(
      model_id,
      clean_controls = "Five cases + clean controls",
      full_switching = "Five cases + switching controls",
      clean_controls_without_gab_qat =
        "Four cases + clean controls; no GAB/QAT",
      full_switching_without_gab_qat =
        "Four cases + switching controls; no GAB/QAT"
    ),
    Estimand = estimand_group,
    Target = ifelse(target_estimand, "yes", "no"),
    ATT = format_num(estimate),
    `Bootstrap SE` = format_num(se_bootstrap),
    `95% CI` = paste0(
      "[", format_num(ci_95_low), ", ", format_num(ci_95_high), "]"
    ),
    `Selected r` = selected_factors,
    `Estimand units/cells` = paste0(
      n_estimand_treated_units, "/", n_treated_country_years
    ),
    `Fit Ntr/Nco` = paste0(n_treated_units, "/", n_never_treated_units),
    `Switch controls/masked cells` = paste0(
      switching_control_units, "/", masked_nonfocal_country_years
    ),
    `Min untreated` = minimum_untreated_periods,
    Reversals = treatment_reversals_detected_by_fect
  )

markdown_table <- function(data) {
  data <- data |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
  header <- paste0("| ", paste(names(data), collapse = " | "), " |")
  rule <- paste0("| ", paste(rep("---", ncol(data)), collapse = " | "), " |")
  rows <- apply(
    data,
    1L,
    function(x) paste0("| ", paste(x, collapse = " | "), " |")
  )
  paste(c(header, rule, rows), collapse = "\n")
}

focal_switches <- fect_treatment_audit |>
  dplyr::filter(focal_country) |>
  dplyr::select(
    model_id, iso3c, public_cue_year, first_treated_year, last_treated_year,
    treated_years, entries, exits, off_years_after_first_entry,
    china_top_years_before_cue
  )

format_dropped_units <- function(model_id_value) {
  dropped <- fect_sample_audit |>
    dplyr::filter(
      model_id == model_id_value,
      !included_by_fect
    )
  if (nrow(dropped) == 0L) {
    return("none")
  }
  paste0(
    dropped$country_name,
    " (", dropped$iso3c, ")",
    collapse = "; "
  )
}
dropped_label_full <- format_dropped_units("full_switching")
dropped_label_reduced <- format_dropped_units(
  "full_switching_without_gab_qat"
)
focal_exit_counts <- fect_treatment_audit |>
  dplyr::filter(
    model_id %in% c(
      "full_switching",
      "full_switching_without_gab_qat"
    ),
    focal_country
  ) |>
  dplyr::group_by(model_id) |>
  dplyr::summarise(value = sum(exits, na.rm = TRUE), .groups = "drop")

summary_lines <- c(
  "# Selected public-cue SDiD and pooled IFE diagnostic",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Design",
  "",
  paste0(
    "The common estimation window is ", year_start, "-", year_end,
    ". The outcome is absolute UNGA ideal-point distance to China. "
  ),
  paste0(
    "Every SDiD donor has a complete outcome/rank panel and never has China ",
    "as its largest goods-export destination in this window. This leaves ",
    length(clean_donors), " donors."
  ),
  paste0(
    "The first pooled IFE model keeps these controls plus CHL, URY, GAB, QAT, ",
    "and AUS; only those five can be treated. The second starts from every ",
    "complete country panel, but still codes treatment only for the five focal ",
    "cases. Non-focal China-top country-years are masked, so those countries ",
    "leave and re-enter the comparison pool without becoming treated cases. ",
    "Both designs are then re-estimated after excluding ",
    "Gabon and Qatar entirely and adding Brazil; the reduced focal group is ",
    "AUS, BRA, CHL, and URY."
  ),
  "",
  "## SDiD results",
  "",
  markdown_table(sdid_report_rows),
  "",
  paste0(
    "Placebo standard errors use ", placebo_replications,
    " replications and seed ", SDID_PLACEBO_SEED,
    ". The reported p-values are normal approximations based on the placebo ",
    "standard error, not exact randomization p-values."
  ),
  "",
  "## Pooled interactive fixed-effects results",
  "",
  markdown_table(fect_report_rows),
  "",
  paste0(
    "All four IFE fits use ", fect_bootstraps,
    " unit-bootstrap replications. Every reported row is the focal estimand: ",
    "five treated cases in the base fits and four in the fits without ",
    "Gabon/Qatar, which add Brazil. Non-focal countries never receive D = 1."
  ),
  "",
  "## Treatment-switch audit for the focal cases",
  "",
  markdown_table(focal_switches),
  "",
  "## Scope notes",
  "",
  paste0(
    "- The current stored goods-export panel first marks Australia China-top ",
    "in ", focal_audit$first_china_top_year[focal_audit$iso3c == "AUS"],
    ". The separate 2010 SDiD is nevertheless retained exactly as requested."
  ),
  paste0(
    "- The outcome extends to 2023, but the goods-export rank used to certify ",
    "clean controls ends in 2022; 2023 is therefore excluded."
  ),
  paste0(
    "- The switching-control fit requested ", length(complete_units),
    " units. `fect` retained ", fect_switching$fit$N,
    ". With `min.T0 = ", fect_min_untreated_periods,
    "`, the only excluded unit is ", dropped_label_full,
    ", which has zero eligible observed control periods in the analysis window."
  ),
  paste0(
    "- The reduced switching-control fit requested ",
    length(complete_units) - 2L,
    " units after excluding Gabon and Qatar. `fect` retained ",
    fect_switching_reduced$fit$N, ". With `min.T0 = ",
    fect_min_untreated_periods, "`, the only excluded unit is ",
    dropped_label_reduced,
    ", which has zero eligible observed control periods in the analysis window."
  ),
  paste0(
    "- Focal-case treatment exits in the switching-control specifications: ",
    paste0(
      focal_exit_counts$model_id,
      "=", focal_exit_counts$value,
      collapse = "; "
    ),
    ". Non-focal control availability changes are represented by masked ",
    "country-years, not by additional treated units."
  ),
  "- Ordinary weighted-regression standard errors are not used for SDiD.",
  "- No targets were created, rebuilt, or modified by this script."
)
writeLines(summary_lines, file.path(output_dir, "SUMMARY.md"), useBytes = TRUE)

primary_outputs <- c(
  "SUMMARY.md",
  "cue_year_validation.csv",
  "unit_eligibility_audit.csv",
  "sdid_sample_membership.csv",
  "sdid_results.csv",
  "sdid_unit_weights.csv",
  "sdid_time_weights.csv",
  "sdid_paths.csv",
  "fect_clean_controls_panel.csv",
  "fect_full_switching_panel.csv",
  "fect_clean_controls_without_gab_qat_panel.csv",
  "fect_full_switching_without_gab_qat_panel.csv",
  "fect_treatment_audit.csv",
  "fect_results.csv",
  "fect_dynamic.csv",
  "fect_latent_factors.csv",
  "fect_factor_loadings.csv",
  "fect_model_sample_audit.csv",
  "input_target_metadata.csv",
  "session_info.txt"
)
output_manifest <- tibble::tibble(
  file = primary_outputs,
  bytes = file.info(file.path(output_dir, primary_outputs))$size,
  sha256 = vapply(
    file.path(output_dir, primary_outputs),
    digest::digest,
    character(1),
    algo = "sha256",
    file = TRUE
  )
)
readr::write_csv(
  output_manifest,
  file.path(output_dir, "output_manifest.csv")
)

run_manifest <- list(
  analysis = "selected_public_cue_sdid_fect",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  script = "scripts/diagnostics/estimate_selected_public_cue_sdid_fect.R",
  targets_pipeline_executed = FALSE,
  target_store_modified = FALSE,
  input_target = input_target,
  input_target_data_hash = if (nrow(target_meta) == 1L) target_meta$data[[1L]] else NA,
  cue_year_source = cue_source_path,
  year_start = year_start,
  year_end = year_end,
  placebo_replications = placebo_replications,
  placebo_seed = SDID_PLACEBO_SEED,
  fect_bootstraps = fect_bootstraps,
  fect_seed = 42L,
  fect_min_untreated_periods = fect_min_untreated_periods,
  parallel_cores = parallel_cores,
  clean_donor_count = length(clean_donors),
  complete_panel_unit_count = length(complete_units),
  fect_alternatives = c(
    "clean_controls",
    "full_switching",
    "clean_controls_without_gab_qat",
    "full_switching_without_gab_qat"
  ),
  focal_countries = cue_years$iso3c,
  reduced_focal_countries = reduced_focal_iso3c,
  countries_excluded_in_reduced_fits = c("GAB", "QAT"),
  switching_control_rule = paste0(
    "Only focal cases receive D=1; non-focal China-top country-years have ",
    "model_outcome=NA and re-enter the comparison pool when China is not top 1."
  ),
  package_versions = as.list(vapply(
    c("dplyr", "fect", "synthdid", "targets"),
    function(pkg) as.character(utils::packageVersion(pkg)),
    character(1)
  )),
  output_manifest_sha256 = digest::digest(
    file.path(output_dir, "output_manifest.csv"),
    algo = "sha256",
    file = TRUE
  )
)
jsonlite::write_json(
  run_manifest,
  file.path(output_dir, "run_manifest.json"),
  auto_unbox = TRUE,
  pretty = TRUE,
  na = "null"
)

message("Completed. Main results: ", file.path(output_dir, "SUMMARY.md"))
print(sdid_results)
print(fect_results)
