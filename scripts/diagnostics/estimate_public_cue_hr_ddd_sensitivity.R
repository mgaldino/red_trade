#!/usr/bin/env Rscript

# Sensitivity analyses for the human-rights triple difference of the seven
# public-cue cases (exploratory; main run: estimate_public_cue_hr_ddd.R).
#
# Same DDD as the main run (paper's Brazil specification: roll calls on which
# China and the reference country vote differently; outcome ~ treated_post +
# treated_hr + treated_post_hr | country + roll call; window cue - 4 to cue + 3;
# calendar year of the vote). Two variants:
#
#   latam_controls     BRA, CHL and URY with China - US outcome and only the
#                      Latin American and Caribbean controls (World Bank region).
#   displaced_partner  All seven cases, reference = the partner China displaced
#                      as top goods-export destination (the top destination in
#                      the year before China's entry): USA for KOR, BRA and CHL;
#                      JPN for AUS; GBR for ZAF; BRA for URY; AUS for NZL.
#                      Outcome = |vote - China| - |vote - partner| on roll calls
#                      where China and the partner vote differently. Controls:
#                      the main-run controls minus GBR (a displaced partner), the
#                      same set for every case.
#
# Placebo as in the main run: every control gets every case's cue year; the
# aggregate draws distinct controls, one per case (5,000 draws, seed 20260520).
#
# Gate: the generalized vote-panel builder, with the United States as partner,
# must reproduce the corrected Brazil DDD the paper uses.
#
# Exploratory and outside the targets graph; listed in TARGETS_MIGRATION.md.
#   Rscript scripts/diagnostics/estimate_public_cue_hr_ddd_sensitivity.R

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
outcomes <- c(distance = -1, agreement = 1)

output_dir <- file.path("data", "processed", "diagnostics", "public_cue_hr_ddd", "sensitivity")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cases <- tibble::tribble(
  ~iso3c, ~cue_year, ~partner,
  "KOR", 2003L, "USA",
  "AUS", 2007L, "JPN",
  "CHL", 2007L, "USA",
  "BRA", 2009L, "USA",
  "ZAF", 2010L, "GBR",
  "URY", 2013L, "BRA",
  "NZL", 2013L, "AUS"
)

tables <- selective_unga_load_unvotes_tables(tar_read(unvotes_tarball))
all_votes <- tables$un_votes |>
  dplyr::mutate(
    vote = as.character(vote),
    iso3c = countrycode::countrycode(country_code, origin = "iso2c",
                                     destination = "iso3c", warn = FALSE)
  ) |>
  dplyr::filter(vote %in% c("yes", "no", "abstain")) |>
  dplyr::mutate(score = selective_unga_vote_score(vote)) |>
  dplyr::select(rcid, iso3c, score)
roll_calls <- tables$un_roll_calls |>
  dplyr::transmute(rcid, year = as.integer(lubridate::year(date)))
issue_domain <- tables$un_roll_call_issues |>
  dplyr::mutate(issue = selective_unga_clean_text(as.character(issue)),
                family = selective_unga_map_issue_family(issue)) |>
  dplyr::summarise(any_hr = any(family == "Human rights", na.rm = TRUE), .by = rcid)

# Vote panel against China and one reference partner, restricted to roll calls on
# which the two vote differently. Mirrors selective_unga_build_vote_panel().
build_panel <- function(partner, countries, years) {
  ref <- all_votes |>
    dplyr::filter(iso3c %in% c("CHN", partner)) |>
    dplyr::mutate(who = dplyr::if_else(iso3c == "CHN", "china", "partner")) |>
    dplyr::select(rcid, who, score) |>
    tidyr::pivot_wider(names_from = who, values_from = score) |>
    dplyr::filter(!is.na(china), !is.na(partner), china != partner)
  all_votes |>
    dplyr::filter(iso3c %in% countries) |>
    dplyr::inner_join(dplyr::filter(roll_calls, year %in% years), by = "rcid") |>
    dplyr::inner_join(ref, by = "rcid") |>
    dplyr::left_join(issue_domain, by = "rcid") |>
    dplyr::mutate(
      hr = as.integer(dplyr::coalesce(any_hr, FALSE)),
      distance = abs(score - china) - abs(score - partner),
      agreement = as.integer(score == china) - as.integer(score == partner)
    )
}

# allow_missing: a placebo unit with no recorded votes in one of the four
# period x domain cells does not identify the triple interaction; it returns NA
# and is left out of that case's placebo distribution.
fit_ddd <- function(d, unit, cue_year, outcome, allow_missing = FALSE) {
  fd <- d |>
    dplyr::filter(year >= cue_year - window_pre, year <= cue_year + window_post) |>
    dplyr::mutate(
      treated_post = as.integer(iso3c == unit & year >= cue_year),
      treated_hr = as.integer(iso3c == unit) * hr,
      treated_post_hr = treated_post * hr
    )
  fit <- fixest::feols(
    stats::as.formula(paste0(outcome, " ~ treated_post + treated_hr + treated_post_hr | iso3c + rcid")),
    data = fd, vcov = "iid", notes = FALSE
  )
  if (!"treated_post_hr" %in% names(stats::coef(fit))) {
    if (allow_missing) return(NA_real_)
    stop("Triple interaction not identified for ", unit, " (cue ", cue_year, ").")
  }
  unname(stats::coef(fit)[["treated_post_hr"]])
}

# ---- Gate ------------------------------------------------------------------
paper_donors <- tar_read(synth_data) |>
  dplyr::distinct(iso3c) |>
  dplyr::filter(!iso3c %in% c("BRA", "USA")) |>
  dplyr::pull(iso3c)
gate_panel <- build_panel("USA", c("BRA", paper_donors), 2005:2012)
stored <- readRDS(file.path("data", "processed", "diagnostics", "RIO_20260905_ddd",
                            "corrected_ddd_bundle.rds"))$ddd_models |>
  dplyr::filter(term == "brazil_post_hr") |>
  dplyr::distinct(outcome, estimate) |>
  dplyr::mutate(outcome = sub("_china_minus_usa", "", outcome))
gate <- stored |>
  dplyr::mutate(rebuilt = vapply(outcome, function(o) fit_ddd(gate_panel, "BRA", 2009L, o), numeric(1)),
                abs_diff = abs(rebuilt - estimate),
                n_obs_rebuilt = nrow(gate_panel))
print(as.data.frame(gate))
readr::write_csv(gate, file.path(output_dir, "gate_reproduction.csv"))
stopifnot(nrow(gate) == 2L, all(gate$abs_diff < 1e-10), nrow(gate_panel) == 55190L)

# ---- Controls --------------------------------------------------------------
main_controls <- readr::read_csv(
  file.path("data", "processed", "diagnostics", "public_cue_hr_ddd", "ddd_placebo_by_control.csv"),
  show_col_types = FALSE
) |>
  dplyr::distinct(placebo_unit) |>
  dplyr::pull(placebo_unit) |>
  sort()
stopifnot(length(main_controls) == 104L)
latam <- main_controls[countrycode::countrycode(main_controls, "iso3c", "region") ==
                         "Latin America & Caribbean"]
partner_controls <- setdiff(main_controls, cases$partner)

years <- seq.int(min(cases$cue_year) - window_pre, max(cases$cue_year) + window_post)

# ---- Runner ----------------------------------------------------------------
run_spec <- function(spec_id, spec_cases, controls) {
  panels <- lapply(unique(spec_cases$partner), function(p) {
    build_panel(p, c(controls, spec_cases$iso3c), years)
  })
  names(panels) <- unique(spec_cases$partner)

  sample_sizes <- dplyr::bind_rows(lapply(seq_len(nrow(spec_cases)), function(k) {
    cue <- spec_cases$cue_year[k]
    panels[[spec_cases$partner[k]]] |>
      dplyr::filter(iso3c == spec_cases$iso3c[k], year >= cue - window_pre, year <= cue + window_post) |>
      dplyr::mutate(period = dplyr::if_else(year >= cue, "post", "pre"),
                    domain = dplyr::if_else(hr == 1L, "hr", "nonhr")) |>
      dplyr::count(period, domain) |>
      tidyr::pivot_wider(names_from = c(domain, period), values_from = n, names_prefix = "n_votes_") |>
      dplyr::mutate(iso3c = spec_cases$iso3c[k], .before = 1L)
  }))

  estimates <- dplyr::bind_rows(lapply(names(outcomes), function(o) {
    dplyr::bind_rows(lapply(seq_len(nrow(spec_cases)), function(k) {
      d <- dplyr::filter(panels[[spec_cases$partner[k]]], iso3c %in% c(controls, spec_cases$iso3c[k]))
      tibble::tibble(spec_id = spec_id, outcome = o, iso3c = spec_cases$iso3c[k],
                     cue_year = spec_cases$cue_year[k], partner = spec_cases$partner[k],
                     ddd = fit_ddd(d, spec_cases$iso3c[k], spec_cases$cue_year[k], o))
    }))
  }))

  placebos <- dplyr::bind_rows(lapply(names(outcomes), function(o) {
    dplyr::bind_rows(lapply(seq_len(nrow(spec_cases)), function(k) {
      d <- dplyr::filter(panels[[spec_cases$partner[k]]], iso3c %in% controls)
      tibble::tibble(spec_id = spec_id, outcome = o, case = spec_cases$iso3c[k], placebo_unit = controls,
                     ddd = vapply(controls, function(u) {
                       fit_ddd(d, u, spec_cases$cue_year[k], o, allow_missing = TRUE)
                     }, numeric(1)))
    }))
  }))

  set.seed(SDID_PLACEBO_SEED)
  draws <- replicate(placebo_draws, sample(controls, nrow(spec_cases)))
  unidentified <- dplyr::filter(placebos, is.na(ddd))
  aggregate <- dplyr::bind_rows(lapply(names(outcomes), function(o) {
    sign <- outcomes[[o]]
    pm <- placebos |>
      dplyr::filter(outcome == o) |>
      dplyr::select(case, placebo_unit, ddd) |>
      tidyr::pivot_wider(names_from = case, values_from = ddd) |>
      tibble::column_to_rownames("placebo_unit") |>
      as.matrix()
    pm <- pm[, spec_cases$iso3c, drop = FALSE]
    agg <- vapply(seq_len(placebo_draws), function(b) mean(pm[cbind(draws[, b], spec_cases$iso3c)]),
                  numeric(1))
    # Draws that give a case an unidentified placebo unit are dropped.
    agg <- agg[!is.na(agg)]
    obs <- mean(estimates$ddd[estimates$outcome == o])
    tibble::tibble(spec_id = spec_id, outcome = o, expected_sign = sign, n_cases = nrow(spec_cases),
                   ddd_mean = obs, se_placebo = stats::sd(agg),
                   p_placebo_directional = (1 + sum(sign * agg >= sign * obs)) / (length(agg) + 1),
                   p_placebo_two_sided = (1 + sum(abs(agg) >= abs(obs))) / (length(agg) + 1),
                   n_controls = length(controls), placebo_draws = length(agg),
                   placebo_seed = SDID_PLACEBO_SEED)
  }))

  ranks <- estimates |>
    dplyr::left_join(dplyr::select(dplyr::filter(placebos, !is.na(ddd)), outcome, case, ddd_placebo = ddd),
                     by = c("outcome", "iso3c" = "case"), relationship = "many-to-many") |>
    dplyr::mutate(sign = outcomes[outcome]) |>
    dplyr::group_by(spec_id, outcome, iso3c, cue_year, partner, ddd) |>
    dplyr::summarise(rank_directional = 1L + sum(sign * ddd_placebo > sign * ddd),
                     n_units = dplyr::n() + 1L,
                     p_placebo_directional = (1 + sum(sign * ddd_placebo >= sign * ddd)) / (dplyr::n() + 1),
                     .groups = "drop") |>
    dplyr::left_join(sample_sizes, by = "iso3c") |>
    dplyr::arrange(outcome, cue_year)

  list(ranks = ranks, placebos = placebos, aggregate = aggregate, unidentified = unidentified)
}

latam_cases <- dplyr::filter(cases, iso3c %in% c("BRA", "CHL", "URY")) |>
  dplyr::mutate(partner = "USA")
runs <- list(
  run_spec("latam_controls", latam_cases, latam),
  run_spec("displaced_partner", cases, partner_controls)
)

ranks <- dplyr::bind_rows(lapply(runs, `[[`, "ranks"))
placebos <- dplyr::bind_rows(lapply(runs, `[[`, "placebos"))
aggregate <- dplyr::bind_rows(lapply(runs, `[[`, "aggregate"))
readr::write_csv(ranks, file.path(output_dir, "ddd_by_country.csv"))
readr::write_csv(placebos, file.path(output_dir, "ddd_placebo_by_control.csv"))
readr::write_csv(aggregate, file.path(output_dir, "ddd_aggregate.csv"))
unidentified <- dplyr::bind_rows(lapply(runs, `[[`, "unidentified"))
readr::write_csv(unidentified, file.path(output_dir, "placebo_units_unidentified.csv"))
print(as.data.frame(unidentified))
writeLines(capture.output(sessionInfo()), file.path(output_dir, "session_info.txt"))

message("Latin American controls: ", length(latam), "; displaced-partner controls: ",
        length(partner_controls), ".")
print(as.data.frame(ranks), digits = 3)
print(as.data.frame(aggregate), digits = 3)
