#!/usr/bin/env Rscript

# Staggered-adoption SDiD for the public-cue cases (exploratory).
#
# Design, following the cohort-by-cohort approach of Arkhangelsky et al. (2021)
# as implemented by Clarke, Pailanir, Athey and Imbens (2023):
#   * One SDiD per public-cue cohort, each on its own balanced panel running from
#     1997 (the start of the Brazil SDiD) to cue year + 6 (seven post-cue years
#     for every case).
#   * Controls: countries with complete outcome and rank data in 1997-2022 in
#     which China is never the top goods-export destination in 1997-2022.
#   * Aggregate ATT: cohort ATTs weighted by treated units x post-cue years
#     (equal post-cue horizons, so the weight is the number of treated units).
#   * Inference: placebo SE for the aggregate. Each replication draws seven
#     distinct controls, gives them the observed cohort structure, removes them
#     from every cohort's control set, and re-estimates each cohort with the
#     project's placebo mechanics (sdid_placebo_helpers.R: fitted weights passed
#     as starting values, same options). Canonical seed 20260520.
#   * Descriptive single-country SDiDs on the same windows (no inference).
#
# Gate: before any new number, the code must reproduce the stored single-treated
# public-cue SDiDs (Chile 2008 and Australia 2007, window 1997-2022, including the
# Chile placebo SE).
#
# Round of 2026-09-24 (plan: quality_reports/plans/2026-09-24_public_cue_fourteen_case_round.md):
# cases, specifications and outcomes come from public_cue_specs.R, chosen by
#   PUBLIC_CUE_SPEC    seven_case (default), fourteen_case or us_side_ten
#   PUBLIC_CUE_OUTCOME abs (default; the paper's absolute distance) or signed
# Outputs go to public_cue_staggered_sdid/fourteen_round/<spec>_<outcome>/; the
# seven_case / abs run must reproduce the stored aggregate (-0.052, SE 0.057).
# Every run adds the lambda mass on the last two pre-cue years of each cohort and
# the side table (years beyond China); fourteen_case adds leave-one-out point
# estimates and a one-year shift of treatment (ATT over years >= cue only).
#
# Exploratory and outside the targets graph; move to targets once settled.
#   PUBLIC_CUE_SPEC=fourteen_case PUBLIC_CUE_OUTCOME=signed \
#     Rscript scripts/diagnostics/estimate_public_cue_staggered_sdid.R

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
})

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
source(file.path("scripts", "diagnostics", "public_cue_specs.R"))
sdid_limit_blas_threads()

placebo_replications <- as.integer(Sys.getenv("STAGGERED_SDID_REPS", "5000"))
cores <- min(8L, sdid_available_cores())
window_start <- 1997L
horizon <- 7L
last_year <- 2022L

spec_id <- Sys.getenv("PUBLIC_CUE_SPEC", "seven_case")
outcome_key <- Sys.getenv("PUBLIC_CUE_OUTCOME", "abs")
stopifnot(outcome_key %in% names(public_cue_outcomes))
outcome_col <- public_cue_outcomes[[outcome_key]]

stored_dir <- file.path(
  "data", "processed", "diagnostics", "public_cue_staggered_sdid"
)
output_dir <- file.path(stored_dir, "fourteen_round",
                        paste(spec_id, outcome_key, sep = "_"))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cues <- public_cue_spec(spec_id)

panel_all <- targets::tar_read(china_top_m2_goods_panel) |>
  dplyr::select(iso3c, country_name, year, abs_distance_china, china_is_top) |>
  dplyr::mutate(year = as.integer(year), iso3c = as.character(iso3c),
                china_is_top = as.logical(china_is_top)) |>
  public_cue_add_signed()

clean_units <- function(start, end) {
  panel_all |>
    dplyr::filter(year >= start, year <= end) |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      ok = dplyr::n_distinct(year) == (end - start + 1L) &
        all(!is.na(abs_distance_china)) & all(!is.na(china_is_top)) &
        !any(china_is_top %in% TRUE),
      .groups = "drop"
    ) |>
    dplyr::filter(ok) |>
    dplyr::pull(iso3c) |>
    sort()
}

# SDiD with one or more treated units sharing a treatment year. Mirrors
# sdid_fit_spec() in sdid_placebo_helpers.R (row order: controls by iso3c, then
# treated units by iso3c).
fit_sdid <- function(treated, treat_year, start, end, controls,
                     outcome = outcome_col) {
  d <- panel_all |>
    dplyr::filter(year >= start, year <= end, iso3c %in% c(controls, treated)) |>
    dplyr::mutate(
      treatment = as.integer(iso3c %in% treated & year >= treat_year),
      .unit_treated = as.integer(iso3c %in% treated)
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year)
  stopifnot(!anyNA(d[[outcome]]))
  stopifnot(dplyr::n_distinct(dplyr::count(d, iso3c)$n) == 1L)
  panel_data <- d |>
    dplyr::mutate(iso3c = factor(iso3c, levels = unique(iso3c)),
                  Y = .data[[outcome]]) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0)
}

# ---- Gate ------------------------------------------------------------------
stored <- readr::read_csv(
  file.path("data", "processed", "diagnostics", "selected_public_cue_sdid_fect",
            "sdid_results.csv"),
  show_col_types = FALSE
)
stored_aus <- readr::read_csv(
  file.path("data", "processed", "diagnostics", "selected_public_cue_sdid_fect",
            "australia_sdid_2007_results.csv"),
  show_col_types = FALSE
)
controls_1997 <- clean_units(1997L, 2022L)
gate_chl <- fit_sdid("CHL", 2008L, 1997L, 2022L, controls_1997,
                     outcome = "abs_distance_china")
gate_aus <- fit_sdid("AUS", 2007L, 1997L, 2022L, controls_1997,
                     outcome = "abs_distance_china")
gate_chl_se <- as.numeric(sdid_placebo_se(gate_chl, placebo_replications,
                                          cores = cores, label = "gate_chl_2008"))
gate <- tibble::tibble(
  check = c("CHL 2008 ATT", "AUS 2007 ATT", "CHL 2008 placebo SE"),
  rebuilt = c(as.numeric(gate_chl), as.numeric(gate_aus), gate_chl_se),
  stored = c(stored$estimate[stored$fit_id == "chl_cue_2008"],
             stored_aus$estimate[1],
             stored$se_placebo[stored$fit_id == "chl_cue_2008"])
) |>
  dplyr::mutate(abs_diff = abs(rebuilt - stored))
readr::write_csv(gate, file.path(output_dir, "gate_reproduction.csv"))
print(as.data.frame(gate))
stopifnot(all(gate$abs_diff < 1e-8))

# ---- Cohort SDiDs ----------------------------------------------------------
controls <- clean_units(window_start, last_year)
stopifnot(!any(cues$iso3c %in% controls))
message(length(controls), " controls (complete and never China-top, ",
        window_start, "-", last_year, ").")

cohorts <- cues |>
  dplyr::group_by(cue_year) |>
  dplyr::summarise(treated = list(sort(iso3c)), n_treated = dplyr::n(),
                   .groups = "drop") |>
  dplyr::arrange(cue_year) |>
  dplyr::mutate(window_end = cue_year + horizon - 1L)
stopifnot(all(cohorts$window_end <= last_year))

cohort_fits <- lapply(seq_len(nrow(cohorts)), function(i) {
  fit_sdid(cohorts$treated[[i]], cohorts$cue_year[i], window_start,
           cohorts$window_end[i], controls)
})
# Lambda mass on the last two pre-cue years: under a one-year anticipation effect
# the SDiD keeps (1 - lambda_last_pre) of it (quality_reports/2026-09-24_anticipation_sdid_ife.md).
lambda_at <- function(fit, back) {
  lambda <- attr(fit, "weights")$lambda
  lambda[length(lambda) - back]
}
cohorts <- cohorts |>
  dplyr::mutate(
    att = vapply(cohort_fits, as.numeric, numeric(1)),
    weight = n_treated * horizon / sum(n_treated * horizon),
    n_pre_years = cue_year - window_start,
    treated_label = vapply(treated, paste, character(1), collapse = "+"),
    lambda_last_pre = vapply(cohort_fits, lambda_at, numeric(1), back = 0L),
    lambda_second_last_pre = vapply(cohort_fits, lambda_at, numeric(1), back = 1L)
  )
att_aggregate <- sum(cohorts$weight * cohorts$att)

# ---- Placebo for the aggregate --------------------------------------------
# Each cohort's setup lists the controls first, in the same (iso3c) order.
n_control <- length(controls)
n_placebo <- sum(cohorts$n_treated)
set.seed(SDID_PLACEBO_SEED)
draws <- replicate(placebo_replications, sample(seq_len(n_control), n_placebo))
cohort_slots <- split(seq_len(n_placebo),
                      rep(seq_len(nrow(cohorts)), cohorts$n_treated))

placebo_cohort <- function(fit, placebo_rows, excluded_rows) {
  setup <- attr(fit, "setup")
  opts <- attr(fit, "opts")
  w <- attr(fit, "weights")
  keep <- setdiff(seq_len(setup$N0), excluded_rows)
  ind <- c(keep, placebo_rows)
  w$omega <- sdid_sum_normalize(w$omega[keep])
  as.numeric(do.call(
    synthdid::synthdid_estimate,
    c(list(Y = setup$Y[ind, , drop = FALSE], N0 = length(keep), T0 = setup$T0,
           X = setup$X[ind, , , drop = FALSE], weights = w),
      opts)
  ))
}

theta <- function(j) {
  drawn <- draws[, j]
  atts <- vapply(seq_len(nrow(cohorts)), function(i) {
    placebo_cohort(cohort_fits[[i]], drawn[cohort_slots[[i]]], drawn)
  }, numeric(1))
  sum(cohorts$weight * atts)
}

message("Placebo for the aggregate: ", placebo_replications,
        " replications on ", cores, " cores.")
placebo <- unlist(sdid_mclapply_checked(seq_len(placebo_replications), theta,
                                        cores, what = "aggregate placebo"))
stopifnot(length(placebo) == placebo_replications, all(is.finite(placebo)))
se_aggregate <- sqrt((placebo_replications - 1) / placebo_replications) *
  stats::sd(placebo)

aggregate <- tibble::tibble(
  estimand = sprintf("Aggregate ATT, %d public-cue cases, seven post-cue years",
                     nrow(cues)),
  spec_id = spec_id,
  outcome = outcome_col,
  att = att_aggregate,
  se_placebo = se_aggregate,
  ci_95_low = att_aggregate - stats::qnorm(0.975) * se_aggregate,
  ci_95_high = att_aggregate + stats::qnorm(0.975) * se_aggregate,
  p_normal_two_sided = 2 * stats::pnorm(-abs(att_aggregate / se_aggregate)),
  p_placebo_two_sided = (1 + sum(abs(placebo) >= abs(att_aggregate))) /
    (placebo_replications + 1),
  n_controls = n_control,
  window_start = window_start,
  horizon_years = horizon,
  placebo_replications = placebo_replications,
  placebo_seed = SDID_PLACEBO_SEED,
  synthdid_version = as.character(utils::packageVersion("synthdid"))
)

# ---- Descriptive single-country SDiDs --------------------------------------
single <- cues |>
  dplyr::rowwise() |>
  dplyr::mutate(
    window_end = cue_year + horizon - 1L,
    att_single = as.numeric(
      fit_sdid(iso3c, cue_year, window_start, window_end, controls)
    )
  ) |>
  dplyr::ungroup()

# Round gate: the seven-case run on the paper's outcome reproduces the stored
# aggregate and its placebo SE.
if (spec_id == "seven_case" && outcome_key == "abs") {
  stored_aggregate <- readr::read_csv(
    file.path(stored_dir, "aggregate_estimate.csv"), show_col_types = FALSE
  )
  round_gate <- tibble::tibble(
    check = c("seven-case aggregate ATT", "seven-case placebo SE"),
    rebuilt = c(att_aggregate, se_aggregate),
    stored = c(stored_aggregate$att, stored_aggregate$se_placebo)
  ) |>
    dplyr::mutate(abs_diff = abs(rebuilt - stored))
  readr::write_csv(round_gate, file.path(output_dir, "round_gate_reproduction.csv"))
  print(as.data.frame(round_gate))
  stopifnot(all(round_gate$abs_diff < 1e-8))
}

# ---- Sides, leave-one-out and one-year shift -------------------------------
readr::write_csv(
  public_cue_side_table(dplyr::filter(panel_all, year <= last_year), cues),
  file.path(output_dir, "side_table.csv")
)

if (spec_id == "fourteen_case") {
  aggregate_point <- function(case_rows, treat_shift = 0L) {
    co <- case_rows |>
      dplyr::group_by(cue_year) |>
      dplyr::summarise(treated = list(sort(iso3c)), n_treated = dplyr::n(),
                       .groups = "drop")
    atts <- vapply(seq_len(nrow(co)), function(i) {
      fit <- fit_sdid(co$treated[[i]], co$cue_year[i] - treat_shift, window_start,
                      co$cue_year[i] + horizon - 1L, controls)
      if (treat_shift == 0L) return(as.numeric(fit))
      # Shifted treatment: average the per-year effects from the cue year on.
      curve <- as.numeric(synthdid::synthdid_effect_curve(fit))
      stopifnot(length(curve) == horizon + treat_shift,
                abs(mean(curve) - as.numeric(fit)) < 1e-10)
      mean(curve[-seq_len(treat_shift)])
    }, numeric(1))
    sum(co$n_treated * atts) / sum(co$n_treated)
  }
  leave_one_out <- tibble::tibble(
    left_out = cues$iso3c,
    att = vapply(cues$iso3c, function(u) {
      aggregate_point(dplyr::filter(cues, iso3c != u))
    }, numeric(1))
  ) |>
    dplyr::mutate(change = att - att_aggregate)
  stopifnot(abs(aggregate_point(cues) - att_aggregate) < 1e-10)
  shift <- tibble::tibble(
    treatment_start = c("cue year", "one year before the cue"),
    att_years_from_cue = c(att_aggregate, aggregate_point(cues, treat_shift = 1L))
  )
  readr::write_csv(leave_one_out, file.path(output_dir, "leave_one_out.csv"))
  readr::write_csv(shift, file.path(output_dir, "anticipation_shift.csv"))
  print(as.data.frame(leave_one_out))
  print(as.data.frame(shift))
}

readr::write_csv(
  dplyr::select(cohorts, cue_year, treated_label, n_treated, window_end,
                n_pre_years, att, weight, lambda_last_pre, lambda_second_last_pre),
  file.path(output_dir, "cohort_estimates.csv")
)
readr::write_csv(aggregate, file.path(output_dir, "aggregate_estimate.csv"))
readr::write_csv(single, file.path(output_dir, "single_country_estimates.csv"))
readr::write_csv(tibble::tibble(replication = seq_along(placebo),
                                placebo_att = placebo),
                 file.path(output_dir, "aggregate_placebo_distribution.csv"))
writeLines(capture.output(sessionInfo()),
           file.path(output_dir, "session_info.txt"))

print(as.data.frame(dplyr::select(cohorts, cue_year, treated_label, n_pre_years,
                                  att, weight)))
print(as.data.frame(aggregate))
print(as.data.frame(single))
