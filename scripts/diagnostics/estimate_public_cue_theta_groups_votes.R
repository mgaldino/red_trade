#!/usr/bin/env Rscript

# Direction of the response to the public cue by the sign of theta: vote-level
# part (exploratory; outside the targets graph and outside the paper).
#
# Plan: quality_reports/plans/2026-09-29_public_cue_theta_groups.md, section
# "Desenho revisado". Proposition 1(i): a nonzero response has the sign of theta,
# coded by the author (public_cue_theta in public_cue_specs.R).
#
# Design:
#   * Roll calls from the unvotes 0.3.0 tarball (to 2019) on which China and the
#     US vote differently, as in the paper's Brazil vote-level models.
#   * Outcomes, oriented so that positive = toward the US:
#       distance  = |vote - China| - |vote - US| (distance_china_minus_usa);
#       agreement = agree with US - agree with China (minus
#                   agreement_china_minus_usa), which does not depend on how far
#                   apart China and the US vote on each roll call.
#   * Per case and domain (human rights; other): outcome ~ treated x post |
#     country + roll call, window cue - 4 to cue + 3, calendar year of the vote,
#     the case plus the 104 controls of the DDD (complete and never China-top in
#     1997-2022, minus the US).
#   * Cases (public_cue_theta_groups$votes): theta < 0 KOR, AUS, JPN, NZL, SAU;
#     theta > 0 CHL, BRA, PER, RUS, URY. ZAF, MYS and TKM sit at the floor
#     (pre-cue position below 0.05, 0 = votes with China, 1 = with the US;
#     author's threshold) and MMR is undetermined: descriptive only.
#   * Estimands: tau_neg, tau_pos, Delta = tau_neg - tau_pos (prediction > 0),
#     Delta_mag = mean(JPN, KOR, SAU) - mean(AUS, NZL) (author's magnitude
#     prediction, >= 0 under equal cue salience and adjustment costs). Variant
#     without SAU (weakest cue; the only case whose theta differs from its voting
#     profile), with its own placebo p.
#   * Inference: every control is fitted as pseudo-treated in every case window.
#     5,000 draws, seed 20260520. Primary draws are matched on the pre-cue
#     position: each case slot draws a distinct control from the same band in
#     that case's pre-cue window (>= 0.30 for KOR, AUS, JPN, NZL; 0.05 to 0.30 for
#     the others), so that room to move is comparable. Unmatched draws as a
#     secondary reference.
#   * Drift: time placebo with a fake cue at c - 4 (window c - 8 to c - 1) and at
#     c - 3 (window c - 7 to c - 1); same draws; break statistic Delta(true) -
#     Delta(fake).
#   * Sensitivities (points): leave one case out; flip one sign; RUS without the
#     roll calls in which it is a party (Ukraine, GUAM, Abkhazia/Georgia, Syria);
#     all cases without country-specific roll calls (coarse text filter).
#
# Gates: the paper's Brazil vote-level DiD (target
# selective_china_alignment_vote_level_models, China-US divergent roll calls,
# 2005-2012: distance -0.357 on human rights and -0.131 on other roll calls;
# agreement +0.166 and +0.113) is reproduced; the floor rule reproduces the
# case lists in public_cue_specs.R; each draw has distinct units.
#
#   LC_ALL=en_US.UTF-8 Rscript scripts/diagnostics/estimate_public_cue_theta_groups_votes.R
# THETA_VOTES_REPS overrides the number of draws (smoke tests only).

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(targets)
})

source(file.path("scripts", "functions.R"))
source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
source(file.path("scripts", "diagnostics", "public_cue_specs.R"))

draws_n <- as.integer(Sys.getenv("THETA_VOTES_REPS", "5000"))
cores <- min(6L, sdid_available_cores())
fixest::setFixest_nthreads(1)  # fits run in forked children
window_pre <- 4L
window_post <- 3L
floor_threshold <- 0.05
high_band <- 0.30
outcomes <- c(distance = "distance_china_minus_usa", agreement = "agreement_usa_minus_china")
domains <- c(hr = "Human rights", nonhr = "Non-human rights")

out_dir <- file.path("data", "processed", "diagnostics", "public_cue_theta_groups", "votes")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
op <- function(f) file.path(out_dir, f)

groups <- public_cue_theta_groups$votes
theta <- stats::setNames(public_cue_theta$theta_sign, public_cue_theta$iso3c)
all_cases <- public_cue_cases |>
  dplyr::select(iso3c, cue_year) |>
  dplyr::mutate(theta_sign = theta[iso3c],
                in_test = iso3c %in% c(groups$neg, groups$pos))
cases <- all_cases |>
  dplyr::filter(in_test) |>
  dplyr::mutate(group = dplyr::if_else(iso3c %in% groups$neg, "neg", "pos")) |>
  dplyr::arrange(dplyr::desc(group == "neg"), cue_year, iso3c)
mag <- public_cue_theta_mag
mag_no_sau <- list(large = setdiff(mag$large, "SAU"), small = mag$small)

fit_did <- function(d, unit, treat_year, start, end, outcome) {
  fd <- d |>
    dplyr::filter(year >= start, year <= end) |>
    dplyr::mutate(treated_post = as.integer(iso3c == unit & year >= treat_year))
  fit <- fixest::feols(stats::as.formula(paste0(outcome, " ~ treated_post | iso3c + rcid")),
                       data = fd, vcov = "iid", notes = FALSE)
  stopifnot("treated_post" %in% names(stats::coef(fit)))
  unname(stats::coef(fit)[["treated_post"]])
}
add_measures <- function(v) {
  v |>
    dplyr::mutate(agreement_usa_minus_china = -agreement_china_minus_usa,
                  gap_china_usa = abs(china_score - usa_score),
                  pos01 = (distance_china_minus_usa + gap_china_usa) / (2 * gap_china_usa))
}

unvotes_tarball <- tar_read(unvotes_tarball)

# ---- Gate: the paper's Brazil vote-level DiD ---------------------------------
synth_data <- tar_read(synth_data)
paper_donors <- synth_data |>
  dplyr::distinct(iso3c) |>
  dplyr::filter(!iso3c %in% c("BRA", "USA")) |>
  dplyr::pull(iso3c) |>
  sort()
gate_panel <- selective_unga_build_vote_panel(unvotes_tarball, paper_donors, years = 2005:2012) |>
  dplyr::filter(iso3c %in% c("BRA", paper_donors), china_usa_divergent) |>
  add_measures()
stored <- tar_read(selective_china_alignment_vote_level_models) |>
  dplyr::filter(sample %in% c("Human-rights China-US divergent votes",
                              "Non-human-rights China-US divergent votes"),
                outcome %in% c("distance_china_minus_usa", "agreement_china_minus_usa")) |>
  dplyr::transmute(domain = dplyr::if_else(grepl("^Human", sample), "Human rights", "Non-human rights"),
                   outcome,
                   stored = dplyr::if_else(outcome == "agreement_china_minus_usa", -estimate, estimate),
                   outcome_rebuilt = dplyr::if_else(outcome == "agreement_china_minus_usa",
                                                    "agreement_usa_minus_china", outcome))
gate <- stored
gate$rebuilt <- vapply(seq_len(nrow(gate)), function(i) {
  fit_did(gate_panel[gate_panel$issue_domain == gate$domain[i], ], "BRA", 2009L, 2005L, 2012L,
          gate$outcome_rebuilt[i])
}, numeric(1))
gate$abs_diff <- abs(gate$rebuilt - gate$stored)
print(as.data.frame(gate))
readr::write_csv(gate, op("gate_brazil_vote_did.csv"))
stopifnot(nrow(gate) == 4L, all(gate$abs_diff < 1e-10))

# ---- Panel -------------------------------------------------------------------
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
stopifnot(length(controls) == 105L, !any(all_cases$iso3c %in% controls))
controls <- setdiff(controls, c("USA", "CHN"))

years <- seq.int(min(all_cases$cue_year) - 2L * window_pre, max(all_cases$cue_year) + window_post)
vote_panel <- selective_unga_build_vote_panel(unvotes_tarball, c(controls, all_cases$iso3c), years = years) |>
  dplyr::filter(iso3c %in% c(controls, all_cases$iso3c), china_usa_divergent) |>
  add_measures()
stopifnot(!anyNA(vote_panel$pos01), all(vote_panel$pos01 >= 0 & vote_panel$pos01 <= 1))
controls <- sort(intersect(controls, unique(vote_panel$iso3c)))
stopifnot(length(controls) == 104L)

# ---- Floor rule --------------------------------------------------------------
pre_position <- function(units, cue_year) {
  vote_panel |>
    dplyr::filter(iso3c %in% units, year >= cue_year - window_pre, year <= cue_year - 1L) |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(pos01_pre = mean(pos01), .groups = "drop")
}
case_position <- dplyr::bind_rows(lapply(seq_len(nrow(all_cases)), function(k) {
  pre_position(all_cases$iso3c[k], all_cases$cue_year[k])
})) |>
  dplyr::right_join(all_cases, by = "iso3c")
readr::write_csv(case_position, op("case_pre_position.csv"))
print(as.data.frame(case_position))
floor_cases <- case_position$iso3c[case_position$pos01_pre < floor_threshold]
stopifnot(setequal(floor_cases, c("ZAF", "MYS", "TKM")),
          setequal(case_position$iso3c[case_position$pos01_pre >= floor_threshold &
                                         !is.na(case_position$theta_sign)],
                   c(groups$neg, groups$pos)))

# ---- Windows -----------------------------------------------------------------
case_windows <- dplyr::bind_rows(
  all_cases |> dplyr::mutate(kind = "true", start = cue_year - window_pre, treat_year = cue_year,
                             end = cue_year + window_post),
  cases |> dplyr::select(iso3c, cue_year) |>
    dplyr::mutate(kind = "fake_4", start = cue_year - 8L, treat_year = cue_year - 4L,
                  end = cue_year - 1L),
  cases |> dplyr::select(iso3c, cue_year) |>
    dplyr::mutate(kind = "fake_3", start = cue_year - 7L, treat_year = cue_year - 3L,
                  end = cue_year - 1L)
) |>
  dplyr::select(iso3c, cue_year, kind, start, treat_year, end) |>
  dplyr::mutate(window_id = paste(start, treat_year, end, sep = "_"))
stopifnot(min(case_windows$start) >= min(years), max(case_windows$end) <= max(years))
windows <- dplyr::distinct(case_windows, window_id, start, treat_year, end)

by_domain <- lapply(domains, function(dm) dplyr::filter(vote_panel, issue_domain == dm))
control_by_domain <- lapply(by_domain, function(d) dplyr::filter(d, iso3c %in% controls))

case_estimates <- tidyr::expand_grid(case_windows, outcome = names(outcomes), domain = names(domains))
case_estimates$estimate <- vapply(seq_len(nrow(case_estimates)), function(i) {
  r <- case_estimates[i, ]
  d <- dplyr::filter(by_domain[[r$domain]], iso3c %in% c(controls, r$iso3c))
  fit_did(d, r$iso3c, r$treat_year, r$start, r$end, outcomes[[r$outcome]])
}, numeric(1))
readr::write_csv(case_estimates, op("case_estimates.csv"))

jobs <- tidyr::expand_grid(windows, control = controls, outcome = names(outcomes),
                           domain = names(domains))
message(nrow(jobs), " pseudo-treated vote-level DiDs.")
vals <- sdid_mclapply_checked(seq_len(nrow(jobs)), function(i) {
  r <- jobs[i, ]
  fit_did(control_by_domain[[r$domain]], r$control, r$treat_year, r$start, r$end,
          outcomes[[r$outcome]])
}, cores, what = "pseudo-treated vote DiD")
ok <- vapply(vals, function(v) is.numeric(v) && length(v) == 1L && is.finite(v), logical(1))
if (!all(ok)) stop(sum(!ok), " pseudo-treated fits failed.", call. = FALSE)
jobs$estimate <- unlist(vals)
readr::write_csv(jobs, op("pseudo_treated_estimates.csv"))
pseudo_of <- function(o, dm) {
  jobs |>
    dplyr::filter(outcome == o, domain == dm) |>
    dplyr::select(window_id, control, estimate) |>
    tidyr::pivot_wider(names_from = window_id, values_from = estimate) |>
    tibble::column_to_rownames("control") |>
    as.matrix()
}

# ---- Draws -------------------------------------------------------------------
control_position <- dplyr::bind_rows(lapply(sort(unique(cases$cue_year)), function(y) {
  pre_position(controls, y) |> dplyr::mutate(cue_year = y)
}))
case_band <- case_position |>
  dplyr::filter(iso3c %in% cases$iso3c) |>
  dplyr::mutate(band = dplyr::if_else(pos01_pre >= high_band, "high", "low"))
stopifnot(all(case_band$band[case_band$iso3c %in% c("KOR", "AUS", "JPN", "NZL")] == "high"),
          all(case_band$band[!case_band$iso3c %in% c("KOR", "AUS", "JPN", "NZL")] == "low"))
eligible <- lapply(cases$iso3c, function(u) {
  b <- case_band$band[case_band$iso3c == u]
  y <- cases$cue_year[cases$iso3c == u]
  cp <- dplyr::filter(control_position, cue_year == y)
  if (b == "high") cp$iso3c[cp$pos01_pre >= high_band]
  else cp$iso3c[cp$pos01_pre >= floor_threshold & cp$pos01_pre < high_band]
})
names(eligible) <- cases$iso3c
pool_sizes <- tibble::tibble(iso3c = names(eligible), eligible_controls = lengths(eligible))
readr::write_csv(pool_sizes, op("matched_pool_sizes.csv"))
stopifnot(all(pool_sizes$eligible_controls >= nrow(cases)))

set.seed(SDID_PLACEBO_SEED)
draws_matched <- replicate(draws_n, {
  drawn <- character(nrow(cases))
  for (s in seq_len(nrow(cases))) {
    pool <- setdiff(eligible[[s]], drawn[seq_len(s - 1L)])
    drawn[s] <- pool[sample.int(length(pool), 1L)]
  }
  drawn
})
set.seed(SDID_PLACEBO_SEED)
draws_unmatched <- replicate(draws_n, sample(controls, nrow(cases)))
for (dr in list(draws_matched, draws_unmatched)) {
  stopifnot(all(apply(dr, 2, function(x) !anyDuplicated(x))))
}

# ---- Group statistics --------------------------------------------------------
variants <- list(
  all = list(neg = groups$neg, pos = groups$pos, mag = mag),
  no_sau = list(neg = setdiff(groups$neg, "SAU"), pos = groups$pos, mag = mag_no_sau)
)
pred_dir <- c(tau_neg = 1, tau_pos = -1, delta = 1, delta_mag = 1)
stats_of <- function(est, v) {
  c(tau_neg = mean(est[v$neg]), tau_pos = mean(est[v$pos]),
    delta = mean(est[v$neg]) - mean(est[v$pos]),
    delta_mag = mean(est[v$mag$large]) - mean(est[v$mag$small]))
}
case_est_vec <- function(k, o, dm) {
  x <- dplyr::filter(case_estimates, kind == k, outcome == o, domain == dm)
  stats::setNames(x$estimate, x$iso3c)[cases$iso3c]
}
window_vec <- function(k) {
  x <- dplyr::filter(case_windows, kind == k)
  stats::setNames(x$window_id, x$iso3c)[cases$iso3c]
}
kinds <- c("true", "fake_4", "fake_3")
results <- list()
for (o in names(outcomes)) for (dm in names(domains)) {
  pm <- pseudo_of(o, dm)
  for (draw_type in c("matched", "unmatched")) {
    dr <- if (draw_type == "matched") draws_matched else draws_unmatched
    placebo <- lapply(kinds, function(k) {
      wv <- window_vec(k)
      lapply(variants, function(v) {
        vapply(seq_len(draws_n), function(b) {
          stats_of(stats::setNames(pm[cbind(dr[, b], wv)], cases$iso3c), v)
        }, numeric(4))
      })
    })
    names(placebo) <- kinds
    for (vn in names(variants)) {
      v <- variants[[vn]]
      ob <- lapply(kinds, function(k) stats_of(case_est_vec(k, o, dm), v))
      names(ob) <- kinds
      rows <- list()
      for (k in kinds) for (s in names(pred_dir)) {
        d <- pred_dir[[s]]; p <- placebo[[k]][[vn]][s, ]; e <- ob[[k]][[s]]
        rows[[length(rows) + 1L]] <- tibble::tibble(kind = k, estimand = s, estimate = e,
          se_placebo = stats::sd(p), p_directional = (1 + sum(d * p >= d * e)) / (draws_n + 1),
          p_two_sided = (1 + sum(abs(p) >= abs(e))) / (draws_n + 1))
      }
      for (k in c("fake_4", "fake_3")) for (s in names(pred_dir)) {
        d <- pred_dir[[s]]
        p <- placebo$true[[vn]][s, ] - placebo[[k]][[vn]][s, ]
        e <- ob$true[[s]] - ob[[k]][[s]]
        rows[[length(rows) + 1L]] <- tibble::tibble(kind = paste0("true_minus_", k), estimand = s,
          estimate = e, se_placebo = stats::sd(p),
          p_directional = (1 + sum(d * p >= d * e)) / (draws_n + 1),
          p_two_sided = (1 + sum(abs(p) >= abs(e))) / (draws_n + 1))
      }
      results[[length(results) + 1L]] <- dplyr::bind_rows(rows) |>
        dplyr::mutate(outcome = o, domain = dm, draws = draw_type, variant = vn,
                      mde_one_sided_5pct_power80 = 2.487 * se_placebo,
                      n_draws = draws_n, seed = SDID_PLACEBO_SEED, .before = 1)
    }
  }
}
results <- dplyr::bind_rows(results)
# Gate: swapping the labels negates Delta (point).
e1 <- case_est_vec("true", "distance", "hr")
stopifnot(abs(stats_of(e1, list(neg = groups$pos, pos = groups$neg, mag = mag))[["delta"]] +
                stats_of(e1, variants$all)[["delta"]]) < 1e-12)
readr::write_csv(results, op("group_estimates.csv"))
print(as.data.frame(results |>
  dplyr::filter(draws == "matched", variant == "all", estimand %in% c("delta", "tau_neg", "tau_pos")) |>
  dplyr::select(outcome, domain, kind, estimand, estimate, se_placebo, p_directional) |>
  dplyr::mutate(dplyr::across(where(is.numeric), ~ round(.x, 3)))))

# ---- Per-case table (all 14, true window, against all controls) ---------------
per_case <- case_estimates |>
  dplyr::filter(kind == "true") |>
  dplyr::left_join(case_position |> dplyr::select(iso3c, pos01_pre, theta_sign, in_test), by = "iso3c")
per_case$p_predicted_direction <- NA_real_
per_case$p_wrong_direction <- NA_real_
for (i in seq_len(nrow(per_case))) {
  s <- -per_case$theta_sign[i]  # theta < 0 predicts positive (toward the US)
  if (is.na(s)) next
  p <- pseudo_of(per_case$outcome[i], per_case$domain[i])[, per_case$window_id[i]]
  per_case$p_predicted_direction[i] <- (1 + sum(s * p >= s * per_case$estimate[i])) / (length(p) + 1)
  per_case$p_wrong_direction[i] <- (1 + sum(-s * p >= -s * per_case$estimate[i])) / (length(p) + 1)
}
per_case$wrong_sign_p10 <- per_case$p_wrong_direction <= 0.10
readr::write_csv(per_case, op("per_case.csv"))

# ---- Sensitivities (points) --------------------------------------------------
sens <- list()
for (o in names(outcomes)) for (dm in names(domains)) {
  e <- case_est_vec("true", o, dm)
  for (u in cases$iso3c) {
    v <- list(neg = setdiff(groups$neg, u), pos = setdiff(groups$pos, u), mag = mag)
    sens[[length(sens) + 1L]] <- tibble::tibble(outcome = o, domain = dm, check = "leave_one_out",
      case = u, delta = mean(e[v$neg]) - mean(e[v$pos]))
    neg <- if (u %in% groups$neg) setdiff(groups$neg, u) else c(groups$neg, u)
    pos <- if (u %in% groups$pos) setdiff(groups$pos, u) else c(groups$pos, u)
    sens[[length(sens) + 1L]] <- tibble::tibble(outcome = o, domain = dm, check = "flip_one_sign",
      case = u, delta = mean(e[neg]) - mean(e[pos]))
  }
}
# RUS without the roll calls in which it is a party.
rus_party <- "ukrain|guam|abkhazia|georgia|syria"
text_of <- function(d) paste(d$short, d$descr)
rus_cue <- cases$cue_year[cases$iso3c == "RUS"]
for (o in names(outcomes)) for (dm in names(domains)) {
  d <- dplyr::filter(by_domain[[dm]], iso3c %in% c(controls, "RUS"))
  dropped_rcids <- unique(d$rcid[grepl(rus_party, text_of(d), ignore.case = TRUE) &
                                   d$year >= rus_cue - window_pre & d$year <= rus_cue + window_post])
  e <- case_est_vec("true", o, dm)
  e[["RUS"]] <- fit_did(dplyr::filter(d, !rcid %in% dropped_rcids), "RUS", rus_cue,
                        rus_cue - window_pre, rus_cue + window_post, outcomes[[o]])
  sens[[length(sens) + 1L]] <- tibble::tibble(outcome = o, domain = dm,
    check = paste0("rus_without_party_roll_calls (", length(dropped_rcids), " dropped)"),
    case = "RUS", delta = mean(e[groups$neg]) - mean(e[groups$pos]), case_estimate = e[["RUS"]])
}
# Coarse filter: roll calls about specific countries or territories.
country_specific <- paste(
  "situation of human rights in|human rights situation in|situation in|question of|occupied",
  "palestin|israel|golan|jerusalem|lebanon|syria|iran|korea|myanmar|burma|belarus|ukrain",
  "crimea|georgia|abkhazia|guam|cuba|embargo|kosovo|bosnia|afghanistan|iraq|sudan|congo",
  "haiti|cambodia|venezuela|eritrea", sep = "|")
for (o in names(outcomes)) for (dm in names(domains)) {
  d <- by_domain[[dm]]
  d <- d[!grepl(country_specific, text_of(d), ignore.case = TRUE), ]
  e <- vapply(cases$iso3c, function(u) {
    y <- cases$cue_year[cases$iso3c == u]
    fit_did(dplyr::filter(d, iso3c %in% c(controls, u)), u, y, y - window_pre, y + window_post,
            outcomes[[o]])
  }, numeric(1))
  sens[[length(sens) + 1L]] <- tibble::tibble(outcome = o, domain = dm,
    check = "without_country_specific_roll_calls", case = NA_character_,
    delta = mean(e[groups$neg]) - mean(e[groups$pos]),
    tau_neg = mean(e[groups$neg]), tau_pos = mean(e[groups$pos]))
}
sens <- dplyr::bind_rows(sens)
readr::write_csv(sens, op("sensitivities.csv"))

writeLines(capture.output(sessionInfo()), op("session_info.txt"))
message("Done -> ", out_dir)
