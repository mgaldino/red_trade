#!/usr/bin/env Rscript

# Direction of the response to the public cue by the sign of theta: SDiD part
# (exploratory; outside the targets graph and outside the paper).
#
# Plan: quality_reports/plans/2026-09-29_public_cue_theta_groups.md, section
# "Desenho revisado". Proposition 1(i) of the model: a nonzero response has the
# sign of theta. The author coded the sign case by case (public_cue_theta in
# public_cue_specs.R). Positive = toward the US on the signed distance, i.e.,
# away from China for cases on the US side of China.
#
# Design:
#   * Cases: the ten on the US side of China in every pre-cue year
#     (public_cue_theta_groups$signed): theta < 0 KOR, AUS, JPN, NZL; theta > 0
#     CHL, BRA, PER, RUS, ZAF, URY.
#   * One single-country SDiD per case, window 1997 to cue + 6, the 105 controls
#     that are complete and never China-top in 1997-2022, signed distance.
#   * Estimands: tau_neg and tau_pos (equal-weight means), Delta = tau_neg -
#     tau_pos (prediction > 0), Delta_mag = mean(JPN, KOR) - mean(AUS, NZL) (the
#     author's magnitude prediction; SAU is beyond China on this axis).
#   * Inference: every control is fitted as pseudo-treated in every case window
#     (the other 104 controls as donors). Each of 5,000 draws gives the case
#     slots distinct controls; Delta, tau_neg, tau_pos and Delta_mag are
#     recomputed from their pseudo-estimates. Seed 20260520.
#   * Drift (the reason for the revised design): pre-cue, the theta groups
#     already diverge. Time placebo with a fake cue at c - 4 and c - 3 (KOR, with
#     six pre-cue years, uses c - 3 in both), using only data up to c - 1; same
#     draws; and the break statistic Delta(true) - Delta(fake) with its placebo
#     distribution. A post-cue Delta counts as a cue effect only when it exceeds
#     the fake-cue Delta.
#   * Event study of Delta(t) (equal-weight DiD per case against the control
#     mean, relative to c - 1, event times -6..6), with a placebo band, a
#     pre-trend slope test, and the post-cue departure of Delta(t) from its
#     extrapolated pre-cue linear trend.
#   * Sensitivities (points): leave one case out; flip the sign of one case.
#
# Gates: the single-country SDiDs of the 14 cases reproduce the stored
# public_cue_staggered_sdid/fourteen_round/fourteen_case_signed/
# single_country_estimates.csv; each draw has distinct units; swapping the group
# labels negates Delta exactly.
#
#   LC_ALL=en_US.UTF-8 Rscript scripts/diagnostics/estimate_public_cue_theta_groups_sdid.R
# (no --vanilla: the project .Rprofile activates renv, which pins synthdid 0.0.9)
# THETA_SDID_REPS overrides the number of draws (smoke tests only).

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(targets)
})

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
source(file.path("scripts", "diagnostics", "public_cue_specs.R"))
sdid_limit_blas_threads()

draws_n <- as.integer(Sys.getenv("THETA_SDID_REPS", "5000"))
cores <- min(6L, sdid_available_cores())
window_start <- 1997L
horizon <- 7L
last_year <- 2022L
event_min <- -6L
outcome_col <- "signed_distance_china"

out_dir <- file.path("data", "processed", "diagnostics", "public_cue_theta_groups", "sdid")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
op <- function(f) file.path(out_dir, f)

groups <- public_cue_theta_groups$signed
cases <- public_cue_cases |>
  dplyr::filter(iso3c %in% c(groups$neg, groups$pos)) |>
  dplyr::select(iso3c, cue_year) |>
  dplyr::mutate(group = dplyr::if_else(iso3c %in% groups$neg, "neg", "pos"),
                pred_sign = dplyr::if_else(group == "neg", 1, -1)) |>
  dplyr::arrange(dplyr::desc(group == "neg"), cue_year, iso3c)
mag <- list(large = intersect(public_cue_theta_mag$large, groups$neg),
            small = intersect(public_cue_theta_mag$small, groups$neg))
stopifnot(setequal(mag$large, c("JPN", "KOR")), setequal(mag$small, c("AUS", "NZL")))

# ---- Panel -----------------------------------------------------------------
panel_all <- targets::tar_read(china_top_m2_goods_panel) |>
  dplyr::select(iso3c, year, abs_distance_china, china_is_top) |>
  dplyr::mutate(year = as.integer(year), iso3c = as.character(iso3c),
                china_is_top = as.logical(china_is_top)) |>
  public_cue_add_signed()

controls <- panel_all |>
  dplyr::filter(year >= window_start, year <= last_year) |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    ok = dplyr::n_distinct(year) == (last_year - window_start + 1L) &
      all(!is.na(abs_distance_china)) & all(!is.na(china_is_top)) &
      !any(china_is_top %in% TRUE),
    .groups = "drop"
  ) |>
  dplyr::filter(ok) |>
  dplyr::pull(iso3c) |>
  sort()
stopifnot(length(controls) == 105L, !any(public_cue_cases$iso3c %in% controls))

# Same construction as fit_sdid() in estimate_public_cue_staggered_sdid.R.
fit_single <- function(unit, treat_year, end, donors) {
  d <- panel_all |>
    dplyr::filter(year >= window_start, year <= end, iso3c %in% c(donors, unit)) |>
    dplyr::mutate(treatment = as.integer(iso3c == unit & year >= treat_year),
                  .unit_treated = as.integer(iso3c == unit)) |>
    dplyr::arrange(.unit_treated, iso3c, year)
  stopifnot(!anyNA(d[[outcome_col]]), dplyr::n_distinct(dplyr::count(d, iso3c)$n) == 1L)
  panel_data <- d |>
    dplyr::mutate(iso3c = factor(iso3c, levels = unique(iso3c)), Y = .data[[outcome_col]]) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  as.numeric(synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0))
}

# ---- Gate: stored single-country SDiDs --------------------------------------
stored_single <- readr::read_csv(
  file.path("data", "processed", "diagnostics", "public_cue_staggered_sdid", "fourteen_round",
            "fourteen_case_signed", "single_country_estimates.csv"),
  show_col_types = FALSE)
gate <- stored_single |>
  dplyr::rowwise() |>
  dplyr::mutate(rebuilt = fit_single(iso3c, cue_year, window_end, controls)) |>
  dplyr::ungroup() |>
  dplyr::mutate(abs_diff = abs(rebuilt - att_single))
readr::write_csv(gate, op("gate_single_country.csv"))
print(as.data.frame(gate |> dplyr::select(iso3c, cue_year, abs_diff)))
stopifnot(nrow(gate) == 14L, all(gate$abs_diff < 1e-10))

# ---- Windows ----------------------------------------------------------------
# kind "true": treatment at the cue, window to cue + 6. kind "fake_k": fake cue at
# cue - k (KOR: cue - 3 for both k), window ends at cue - 1.
fake_year <- function(iso3c, cue_year, k) ifelse(iso3c == "KOR", cue_year - 3L, cue_year - k)
case_windows <- dplyr::bind_rows(
  cases |> dplyr::mutate(kind = "true", treat_year = cue_year, end = cue_year + horizon - 1L),
  cases |> dplyr::mutate(kind = "fake_4", treat_year = fake_year(iso3c, cue_year, 4L), end = cue_year - 1L),
  cases |> dplyr::mutate(kind = "fake_3", treat_year = fake_year(iso3c, cue_year, 3L), end = cue_year - 1L)
) |>
  dplyr::mutate(window_id = paste(treat_year, end, sep = "_"))
stopifnot(all(case_windows$end <= last_year),
          all(case_windows$treat_year - window_start >= 3L))
windows <- dplyr::distinct(case_windows, window_id, treat_year, end)

case_windows$estimate <- vapply(seq_len(nrow(case_windows)), function(i) {
  fit_single(case_windows$iso3c[i], case_windows$treat_year[i], case_windows$end[i], controls)
}, numeric(1))

message(nrow(windows), " windows x ", length(controls), " controls of pseudo-treated SDiDs.")
jobs <- tidyr::expand_grid(window_id = windows$window_id, control = controls) |>
  dplyr::left_join(windows, by = "window_id")
vals <- sdid_mclapply_checked(seq_len(nrow(jobs)), function(i) {
  fit_single(jobs$control[i], jobs$treat_year[i], jobs$end[i], setdiff(controls, jobs$control[i]))
}, cores, what = "pseudo-treated SDiD")
ok <- vapply(vals, function(v) is.numeric(v) && length(v) == 1L && is.finite(v), logical(1))
if (!all(ok)) stop(sum(!ok), " pseudo-treated SDiDs failed.", call. = FALSE)
jobs$estimate <- unlist(vals)
readr::write_csv(jobs, op("pseudo_treated_estimates.csv"))
pseudo <- jobs |>
  dplyr::select(window_id, control, estimate) |>
  tidyr::pivot_wider(names_from = window_id, values_from = estimate) |>
  tibble::column_to_rownames("control") |>
  as.matrix()
pseudo <- pseudo[controls, windows$window_id, drop = FALSE]

# ---- Draws and group statistics ---------------------------------------------
set.seed(SDID_PLACEBO_SEED)
draws <- replicate(draws_n, sample(controls, nrow(cases)))
stopifnot(all(apply(draws, 2, function(x) !anyDuplicated(x))))

stats_of <- function(est, cases_df, neg = groups$neg, pos = groups$pos) {
  names(est) <- cases_df$iso3c
  c(tau_neg = mean(est[neg]), tau_pos = mean(est[pos]),
    delta = mean(est[neg]) - mean(est[pos]),
    delta_mag = mean(est[mag$large]) - mean(est[mag$small]))
}
placebo_stats <- function(kind_id) {
  cw <- case_windows[case_windows$kind == kind_id, ]
  cw <- cw[match(cases$iso3c, cw$iso3c), ]
  vapply(seq_len(draws_n), function(b) {
    stats_of(pseudo[cbind(draws[, b], cw$window_id)], cw)
  }, numeric(4))
}
kinds <- c("true", "fake_4", "fake_3")
obs <- lapply(kinds, function(k) {
  cw <- case_windows[case_windows$kind == k, ]
  cw <- cw[match(cases$iso3c, cw$iso3c), ]
  stats_of(cw$estimate, cw)
})
names(obs) <- kinds
plc <- lapply(kinds, placebo_stats)
names(plc) <- kinds

# Gate: swapping labels negates Delta exactly, in the point and in the draws.
cw_true <- case_windows[case_windows$kind == "true", ]
cw_true <- cw_true[match(cases$iso3c, cw_true$iso3c), ]
swap <- stats_of(cw_true$estimate, cw_true, neg = groups$pos, pos = groups$neg)
swap_draw <- stats_of(pseudo[cbind(draws[, 1], cw_true$window_id)], cw_true,
                      neg = groups$pos, pos = groups$neg)
stopifnot(abs(swap[["delta"]] + obs$true[["delta"]]) < 1e-12,
          abs(swap_draw[["delta"]] + plc$true["delta", 1]) < 1e-12)

pred_dir <- c(tau_neg = 1, tau_pos = -1, delta = 1, delta_mag = 1)
summarise_stat <- function(o, p, label) {
  dplyr::bind_rows(lapply(names(pred_dir), function(s) {
    d <- pred_dir[[s]]
    tibble::tibble(
      kind = label, estimand = s, estimate = o[[s]], se_placebo = stats::sd(p[s, ]),
      p_directional = (1 + sum(d * p[s, ] >= d * o[[s]])) / (draws_n + 1),
      p_two_sided = (1 + sum(abs(p[s, ]) >= abs(o[[s]]))) / (draws_n + 1),
      mde_one_sided_5pct_power80 = 2.487 * stats::sd(p[s, ]),
      n_draws = draws_n, seed = SDID_PLACEBO_SEED
    )
  }))
}
results <- dplyr::bind_rows(lapply(kinds, function(k) summarise_stat(obs[[k]], plc[[k]], k)))

# Break: Delta(true) - Delta(fake), same draws.
breaks <- dplyr::bind_rows(lapply(c("fake_4", "fake_3"), function(k) {
  lapply(c("delta", "tau_neg", "tau_pos", "delta_mag"), function(s) {
    d <- pred_dir[[s]]
    o <- obs$true[[s]] - obs[[k]][[s]]
    p <- plc$true[s, ] - plc[[k]][s, ]
    tibble::tibble(kind = paste0("true_minus_", k), estimand = s, estimate = o,
                   se_placebo = stats::sd(p),
                   p_directional = (1 + sum(d * p >= d * o)) / (draws_n + 1),
                   p_two_sided = (1 + sum(abs(p) >= abs(o))) / (draws_n + 1),
                   mde_one_sided_5pct_power80 = 2.487 * stats::sd(p),
                   n_draws = draws_n, seed = SDID_PLACEBO_SEED)
  }) |> dplyr::bind_rows()
}))
results <- dplyr::bind_rows(results, breaks)
readr::write_csv(results, op("group_estimates.csv"))
print(as.data.frame(results |> dplyr::mutate(dplyr::across(where(is.numeric), ~ round(.x, 4)))))

# ---- Per-case table ----------------------------------------------------------
per_case <- case_windows |>
  dplyr::filter(kind == "true") |>
  dplyr::rowwise() |>
  dplyr::mutate(
    p_predicted_direction = (1 + sum(pred_sign * pseudo[, window_id] >= pred_sign * estimate)) /
      (length(controls) + 1),
    p_wrong_direction = (1 + sum(-pred_sign * pseudo[, window_id] >= -pred_sign * estimate)) /
      (length(controls) + 1),
    wrong_sign_p10 = p_wrong_direction <= 0.10
  ) |>
  dplyr::ungroup() |>
  dplyr::select(iso3c, group, cue_year, estimate, p_predicted_direction, p_wrong_direction,
                wrong_sign_p10) |>
  dplyr::left_join(
    case_windows |> dplyr::filter(kind != "true") |>
      dplyr::select(iso3c, kind, estimate) |>
      tidyr::pivot_wider(names_from = kind, values_from = estimate, names_prefix = "estimate_"),
    by = "iso3c")
readr::write_csv(per_case, op("per_case.csv"))

# ---- Sensitivities (points) --------------------------------------------------
est_true <- stats::setNames(cw_true$estimate, cw_true$iso3c)
delta_of <- function(neg, pos) mean(est_true[neg]) - mean(est_true[pos])
loo <- dplyr::bind_rows(lapply(cases$iso3c, function(u) {
  tibble::tibble(dropped = u, delta = delta_of(setdiff(groups$neg, u), setdiff(groups$pos, u)))
}))
flips <- dplyr::bind_rows(lapply(cases$iso3c, function(u) {
  neg <- if (u %in% groups$neg) setdiff(groups$neg, u) else c(groups$neg, u)
  pos <- if (u %in% groups$pos) setdiff(groups$pos, u) else c(groups$pos, u)
  tibble::tibble(flipped = u, n_neg = length(neg), n_pos = length(pos), delta = delta_of(neg, pos))
}))
readr::write_csv(loo, op("leave_one_out.csv"))
readr::write_csv(flips, op("flip_one_sign.csv"))

# ---- Event study of Delta(t) -------------------------------------------------
years <- seq.int(window_start, last_year)
Y <- panel_all |>
  dplyr::filter(iso3c %in% c(controls, cases$iso3c), year %in% years) |>
  dplyr::select(iso3c, year, value = dplyr::all_of(outcome_col)) |>
  tidyr::pivot_wider(names_from = year, values_from = value) |>
  tibble::column_to_rownames("iso3c") |>
  as.matrix()
Y <- Y[, as.character(years)]
stopifnot(!anyNA(Y))
event_times <- seq.int(event_min, horizon - 1L)
case_curve <- function(unit, cue_year, control_units) {
  gap <- Y[unit, ] - colMeans(Y[control_units, , drop = FALSE])
  gap[as.character(cue_year + event_times)] - gap[as.character(cue_year - 1L)]
}
delta_curve <- function(units, cue_years, control_units) {
  m <- vapply(seq_along(units), function(k) case_curve(units[k], cue_years[k], control_units),
              numeric(length(event_times)))
  is_neg <- seq_along(units) <= length(groups$neg)
  rowMeans(m[, is_neg, drop = FALSE]) - rowMeans(m[, !is_neg, drop = FALSE])
}
pre_e <- event_times[event_times <= -1L]
post_e <- event_times[event_times >= 0L]
curve_stats <- function(curve) {
  pre <- curve[event_times <= -1L]
  fit <- stats::lm(pre ~ pre_e)
  trend_post <- stats::predict(fit, newdata = data.frame(pre_e = post_e))
  c(slope_pre = stats::coef(fit)[[2]],
    post_mean = mean(curve[event_times >= 0L]),
    post_minus_pre_trend = mean(curve[event_times >= 0L] - trend_post))
}
ordered <- cases$iso3c  # neg first, then pos (see the arrange() above)
stopifnot(identical(ordered[seq_along(groups$neg)], cases$iso3c[cases$group == "neg"]))
observed_curve <- delta_curve(ordered, cases$cue_year, controls)
observed_cs <- curve_stats(observed_curve)
placebo_curves <- vapply(seq_len(draws_n), function(b) {
  drawn <- draws[, b]
  curve <- delta_curve(drawn, cases$cue_year, setdiff(controls, drawn))
  c(curve, curve_stats(curve))
}, numeric(length(event_times) + 3L))
n_e <- length(event_times)
event_study <- tibble::tibble(
  event_time = event_times, delta_t = observed_curve,
  placebo_low = apply(placebo_curves[seq_len(n_e), ], 1, stats::quantile, 0.025),
  placebo_high = apply(placebo_curves[seq_len(n_e), ], 1, stats::quantile, 0.975)
)
es_tests <- tibble::tibble(
  statistic = names(observed_cs), estimate = unname(observed_cs),
  placebo_sd = apply(placebo_curves[n_e + 1:3, ], 1, stats::sd),
  p_directional = c(
    (1 + sum(placebo_curves[n_e + 1, ] >= observed_cs[[1]])) / (draws_n + 1),
    (1 + sum(placebo_curves[n_e + 2, ] >= observed_cs[[2]])) / (draws_n + 1),
    (1 + sum(placebo_curves[n_e + 3, ] >= observed_cs[[3]])) / (draws_n + 1)),
  p_two_sided = vapply(1:3, function(i) {
    (1 + sum(abs(placebo_curves[n_e + i, ]) >= abs(observed_cs[[i]]))) / (draws_n + 1)
  }, numeric(1))
)
readr::write_csv(event_study, op("event_study_delta.csv"))
readr::write_csv(es_tests, op("event_study_tests.csv"))
print(as.data.frame(event_study |> dplyr::mutate(dplyr::across(where(is.numeric), ~ round(.x, 3)))))
print(as.data.frame(es_tests))

writeLines(capture.output(sessionInfo()), op("session_info.txt"))
message("Done -> ", out_dir)
