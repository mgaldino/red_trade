#!/usr/bin/env Rscript

# Human-rights triple difference for the public-cue cases (exploratory).
#
# Specification copied from the paper's Brazil DDD
# (selective_unga_fit_ddd_model() in scripts/functions.R; the paper's numbers come
# from data/processed/diagnostics/RIO_20260905_ddd/corrected_ddd_bundle.rds):
#   * Vote-level data from the unvotes 0.3.0 tarball (plenary roll calls to 2019);
#     only roll calls on which China and the United States vote differently.
#   * Outcomes: distance to China's vote minus distance to the US vote, and
#     agreement with China minus agreement with the US. Both are measured on each
#     roll call against that roll call's China and US votes, so the fold of the
#     ideal-point distance (14-case round, finding E1) does not arise here; cases
#     that already vote with China on most divergent roll calls have little room
#     to move instead (see case_vote_counts.csv in the 14-case round).
#   * ddd_country_placebo_ranks.csv: rank_directional is out of n_placebo + 1
#     (the placebos plus the case itself), as is the p-value denominator.
#   * outcome ~ treated_post + treated_hr + treated_post_hr | country + roll call.
#   * Window: cue year - 4 to cue year + 3 (Brazil: 2005-2012), calendar year of
#     the vote, as in the paper.
#
# Stacked: one regression per case, with that case and the controls of the
# staggered SDiD (complete and never China-top in 1997-2022) minus the United
# States and China, whose outcome is degenerate. The aggregate is the simple mean
# of the case estimates.
#
# Inference: every control is given every case's cue year (the other controls
# stay as controls); the aggregate placebo draws as many distinct controls as the
# specification has cases, one per case, and averages their estimates. 5,000
# draws, seed 20260520, reset for each specification.
#
# Rounds (PUBLIC_CUE_ROUND):
#   * seven (default): the seven original cases; outputs in public_cue_hr_ddd/.
#   * fourteen: the 14 cases of scripts/diagnostics/public_cue_specs.R and the
#     specifications seven_case, fourteen_case and us_side_ten; outputs in
#     public_cue_hr_ddd/fourteen_round/. Gate: the seven_case rows reproduce the
#     stored seven-round outputs before anything new is written.
#
# Gate (both rounds): with Brazil and the paper's donors, the code must
# reproduce the corrected Brazil DDD the paper uses before anything else is
# estimated.
#
# Exploratory and outside the targets graph; listed in TARGETS_MIGRATION.md.
#   Rscript scripts/diagnostics/estimate_public_cue_hr_ddd.R
#   PUBLIC_CUE_ROUND=fourteen Rscript scripts/diagnostics/estimate_public_cue_hr_ddd.R

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
})

source(file.path("scripts", "functions.R"))
source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))

placebo_draws <- 5000L
window_pre <- 4L
window_post <- 3L
outcomes <- c(distance_china_minus_usa = -1, agreement_china_minus_usa = 1)
cores <- sdid_available_cores()
fixest::setFixest_nthreads(1)  # placebo fits run in forked children

round <- Sys.getenv("PUBLIC_CUE_ROUND", "seven")
stopifnot(round %in% c("seven", "fourteen"))
base_dir <- file.path("data", "processed", "diagnostics", "public_cue_hr_ddd")
output_dir <- if (round == "fourteen") file.path(base_dir, "fourteen_round") else base_dir
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

if (round == "fourteen") {
  source(file.path("scripts", "diagnostics", "public_cue_specs.R"))
  cases <- dplyr::select(public_cue_cases, iso3c, cue_year)
  specs <- public_cue_spec_cases
} else {
  cases <- tibble::tribble(
    ~iso3c, ~cue_year,
    "KOR", 2003L,
    "AUS", 2007L,
    "CHL", 2007L,
    "BRA", 2009L,
    "ZAF", 2010L,
    "URY", 2013L,
    "NZL", 2013L
  )
  specs <- list(seven_case = cases$iso3c)
}

fit_ddd <- function(d, unit, cue_year, outcome) {
  fd <- d |>
    dplyr::filter(year >= cue_year - window_pre, year <= cue_year + window_post) |>
    dplyr::mutate(
      hr = as.integer(issue_domain == "Human rights"),
      treated_post = as.integer(iso3c == unit & year >= cue_year),
      treated_hr = as.integer(iso3c == unit) * hr,
      treated_post_hr = treated_post * hr
    )
  fit <- fixest::feols(
    stats::as.formula(paste0(outcome, " ~ treated_post + treated_hr + treated_post_hr | iso3c + rcid")),
    data = fd, vcov = "iid", notes = FALSE
  )
  stopifnot("treated_post_hr" %in% names(stats::coef(fit)))
  unname(stats::coef(fit)[["treated_post_hr"]])
}

unvotes_tarball <- tar_read(unvotes_tarball)

# ---- Gate ------------------------------------------------------------------
synth_data <- tar_read(synth_data)
paper_donors <- synth_data |>
  dplyr::distinct(iso3c) |>
  dplyr::filter(!iso3c %in% c("BRA", "USA")) |>
  dplyr::pull(iso3c) |>
  sort()
gate_panel <- selective_unga_build_vote_panel(unvotes_tarball, paper_donors, years = 2005:2012) |>
  dplyr::filter(iso3c %in% c("BRA", paper_donors), china_usa_divergent)
# The paper reads the corrected DDD (with the Brazil x human-rights term) from the
# RIO_20260905_ddd bundle; the target selective_china_alignment_ddd_hr_nonhr_models
# still holds the earlier specification without that term and is outdated.
stored <- readRDS(file.path("data", "processed", "diagnostics", "RIO_20260905_ddd",
                            "corrected_ddd_bundle.rds"))$ddd_models |>
  dplyr::filter(term == "brazil_post_hr") |>
  dplyr::distinct(outcome, estimate)
gate <- stored |>
  dplyr::mutate(rebuilt = vapply(outcome, function(o) fit_ddd(gate_panel, "BRA", 2009L, o), numeric(1)),
                abs_diff = abs(rebuilt - estimate))
print(as.data.frame(gate))
readr::write_csv(gate, file.path(output_dir, "gate_reproduction.csv"))
stopifnot(nrow(gate) == 2L, all(gate$abs_diff < 1e-10))

# ---- Panel -----------------------------------------------------------------
panel_all <- tar_read(china_top_m2_goods_panel) |>
  dplyr::mutate(year = as.integer(year), iso3c = as.character(iso3c),
                china_is_top = as.logical(china_is_top))
controls <- panel_all |>
  dplyr::filter(year >= 1997L, year <= 2022L) |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    ok = dplyr::n_distinct(year) == 26L & all(!is.na(abs_distance_china)) &
      all(!is.na(china_is_top)) & !any(china_is_top %in% TRUE),
    .groups = "drop"
  ) |>
  dplyr::filter(ok) |>
  dplyr::pull(iso3c) |>
  sort()
stopifnot(length(controls) == 105L, !any(cases$iso3c %in% controls))
controls <- setdiff(controls, c("USA", "CHN"))

years <- seq.int(min(cases$cue_year) - window_pre, max(cases$cue_year) + window_post)
vote_panel <- selective_unga_build_vote_panel(unvotes_tarball, c(controls, cases$iso3c), years = years) |>
  dplyr::filter(iso3c %in% c(controls, cases$iso3c), china_usa_divergent)
controls <- sort(intersect(controls, unique(vote_panel$iso3c)))
message(length(controls), " controls with votes; years ", min(years), "-", max(years), ".")

# ---- Estimates -------------------------------------------------------------
estimates <- dplyr::bind_rows(lapply(names(outcomes), function(o) {
  dplyr::bind_rows(lapply(seq_len(nrow(cases)), function(k) {
    d <- dplyr::filter(vote_panel, iso3c %in% c(controls, cases$iso3c[k]))
    tibble::tibble(outcome = o, iso3c = cases$iso3c[k], cue_year = cases$cue_year[k],
                   ddd = fit_ddd(d, cases$iso3c[k], cases$cue_year[k], o))
  }))
}))

# ---- Placebos --------------------------------------------------------------
# A control's placebo estimate depends on the case only through the cue year, so
# it is computed once per cue year and mapped to the cases with that year.
control_panel <- dplyr::filter(vote_panel, iso3c %in% controls)
placebo_by_year <- dplyr::bind_rows(lapply(names(outcomes), function(o) {
  dplyr::bind_rows(lapply(sort(unique(cases$cue_year)), function(y) {
    vals <- sdid_mclapply_checked(controls, function(u) fit_ddd(control_panel, u, y, o),
                                  cores, what = "DDD placebo")
    ok <- vapply(vals, function(v) is.numeric(v) && length(v) == 1L && is.finite(v), logical(1))
    if (!all(ok)) stop("DDD placebo failed for ", o, ", cue year ", y, ": ",
                       paste(controls[!ok], collapse = ", "), call. = FALSE)
    tibble::tibble(outcome = o, cue_year = y, placebo_unit = controls, ddd = unlist(vals))
  }))
}))
placebos <- cases |>
  dplyr::inner_join(placebo_by_year, by = "cue_year", relationship = "many-to-many") |>
  dplyr::transmute(outcome, case = iso3c, placebo_unit, ddd) |>
  dplyr::arrange(match(outcome, names(outcomes)), match(case, cases$iso3c), placebo_unit)
stopifnot(nrow(placebos) == length(outcomes) * nrow(cases) * length(controls))

aggregate_spec <- function(spec_id) {
  spec_cases <- cases$iso3c[cases$iso3c %in% specs[[spec_id]]]
  set.seed(SDID_PLACEBO_SEED)
  draws <- replicate(placebo_draws, sample(controls, length(spec_cases)))
  dplyr::bind_rows(lapply(names(outcomes), function(o) {
    sign <- outcomes[[o]]
    pm <- placebos |>
      dplyr::filter(outcome == o) |>
      dplyr::select(case, placebo_unit, ddd) |>
      tidyr::pivot_wider(names_from = case, values_from = ddd) |>
      tibble::column_to_rownames("placebo_unit") |>
      as.matrix()
    pm <- pm[, spec_cases]
    agg_placebo <- vapply(seq_len(placebo_draws), function(b) {
      mean(pm[cbind(draws[, b], spec_cases)])
    }, numeric(1))
    obs <- mean(estimates$ddd[estimates$outcome == o & estimates$iso3c %in% spec_cases])
    tibble::tibble(
      spec = spec_id,
      n_cases = length(spec_cases),
      outcome = o,
      expected_sign = sign,
      ddd_mean = obs,
      se_placebo = stats::sd(agg_placebo),
      p_placebo_directional = (1 + sum(sign * agg_placebo >= sign * obs)) / (placebo_draws + 1),
      p_placebo_two_sided = (1 + sum(abs(agg_placebo) >= abs(obs))) / (placebo_draws + 1),
      placebo_mean = mean(agg_placebo),
      n_controls = length(controls),
      placebo_draws = placebo_draws,
      placebo_seed = SDID_PLACEBO_SEED
    )
  }))
}
aggregate <- dplyr::bind_rows(lapply(names(specs), aggregate_spec))

country_ranks <- estimates |>
  dplyr::left_join(placebos, by = c("outcome", "iso3c" = "case"), suffix = c("", "_placebo")) |>
  dplyr::mutate(sign = outcomes[outcome]) |>
  dplyr::group_by(outcome, iso3c, cue_year, ddd) |>
  dplyr::summarise(
    rank_directional = 1L + sum(sign * ddd_placebo > sign * ddd),
    p_placebo_directional = (1 + sum(sign * ddd_placebo >= sign * ddd)) / (dplyr::n() + 1),
    n_placebo = dplyr::n(),
    .groups = "drop"
  ) |>
  dplyr::arrange(outcome, cue_year)

if (round == "seven") {
  aggregate <- aggregate |>
    dplyr::select(-spec, -n_cases) |>
    dplyr::rename(ddd_mean_seven = ddd_mean)
} else {
  # Gate: the seven original cases reproduce the stored seven-round outputs.
  old <- function(f) readr::read_csv(file.path(base_dir, f), show_col_types = FALSE)
  est_check <- dplyr::inner_join(estimates, old("ddd_by_country.csv"),
                                 by = c("outcome", "iso3c", "cue_year"), suffix = c("", "_stored"))
  plc_check <- dplyr::inner_join(placebos, old("ddd_placebo_by_control.csv"),
                                 by = c("outcome", "case", "placebo_unit"), suffix = c("", "_stored"))
  agg_check <- dplyr::inner_join(dplyr::filter(aggregate, spec == "seven_case"), old("ddd_aggregate.csv"),
                                 by = "outcome")
  round_gate <- tibble::tibble(
    check = c("case estimates", "placebo estimates", "aggregate mean", "aggregate placebo SE",
              "aggregate directional p"),
    rows = c(nrow(est_check), nrow(plc_check), nrow(agg_check), nrow(agg_check), nrow(agg_check)),
    max_abs_diff = c(max(abs(est_check$ddd - est_check$ddd_stored)),
                     max(abs(plc_check$ddd - plc_check$ddd_stored)),
                     max(abs(agg_check$ddd_mean - agg_check$ddd_mean_seven)),
                     max(abs(agg_check$se_placebo.x - agg_check$se_placebo.y)),
                     max(abs(agg_check$p_placebo_directional.x - agg_check$p_placebo_directional.y)))
  )
  print(as.data.frame(round_gate))
  readr::write_csv(round_gate, file.path(output_dir, "gate_seven_round.csv"))
  stopifnot(round_gate$rows == c(14L, 14L * length(controls), 2L, 2L, 2L),
            all(round_gate$max_abs_diff < 1e-10))

  country_ranks <- country_ranks |>
    dplyr::mutate(us_side = iso3c %in% public_cue_us_side)

  # Votes behind each case estimate and the case's pre-cue level: a case that
  # already votes with China on most divergent roll calls has little room to move
  # toward China (the distance floor on a roll call is -|China - US|: -2 when they
  # vote on opposite sides, -1 when one abstains). `roll_calls` counts, for the
  # case, the roll calls it voted on and, for the controls, those with any
  # control vote, so the gap between the two measures the case's absences.
  case_vote_counts <- dplyr::bind_rows(lapply(seq_len(nrow(cases)), function(k) {
    y <- cases$cue_year[k]
    vote_panel |>
      dplyr::filter(year >= y - window_pre, year <= y + window_post) |>
      dplyr::mutate(group = dplyr::if_else(iso3c == cases$iso3c[k], "case", "controls"),
                    period = dplyr::if_else(year >= y, "post", "pre"),
                    domain = dplyr::if_else(issue_domain == "Human rights", "hr", "nonhr")) |>
      dplyr::filter(group == "case" | iso3c %in% controls) |>
      dplyr::group_by(group, period, domain) |>
      dplyr::summarise(roll_calls = dplyr::n_distinct(rcid),
                       mean_distance = mean(distance_china_minus_usa),
                       mean_agreement = mean(agreement_china_minus_usa), .groups = "drop") |>
      dplyr::mutate(iso3c = cases$iso3c[k], cue_year = y, .before = 1)
  }))
  readr::write_csv(case_vote_counts, file.path(output_dir, "case_vote_counts.csv"))
}

readr::write_csv(estimates, file.path(output_dir, "ddd_by_country.csv"))
readr::write_csv(placebos, file.path(output_dir, "ddd_placebo_by_control.csv"))
readr::write_csv(aggregate, file.path(output_dir, "ddd_aggregate.csv"))
readr::write_csv(country_ranks, file.path(output_dir, "ddd_country_placebo_ranks.csv"))
writeLines(capture.output(sessionInfo()), file.path(output_dir, "session_info.txt"))

print(as.data.frame(country_ranks))
print(as.data.frame(aggregate))
