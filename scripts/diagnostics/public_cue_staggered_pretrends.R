#!/usr/bin/env Rscript

# Pre-trend diagnostics for the staggered public-cue design (exploratory).
#
# Same cases, windows (1997 to cue year + 6) and controls (complete and never
# China-top in 1997-2022) as estimate_public_cue_staggered_sdid.R.
#
#   * DiD event study with uniform weights: for each treated country, the gap to
#     the control mean in each year, relative to the year before the cue; the
#     curve is the simple average over the seven countries at each event time
#     (-6 to 6, the event times all seven share).
#     Placebo bands: 5,000 draws of seven controls given the observed cue years,
#     with the drawn units removed from the control mean (seed 20260520).
#     Pre-trend tests against the placebo distribution: slope of the average
#     curve on event time over -6 to -1, and the sum of squared coefficients
#     over -6 to -2.
#   * SDiD gaps: for each cohort fit, the treated mean minus the omega-weighted
#     control mean in every year, minus the lambda-weighted pre-cue gap. The
#     average of the post-cue values is the cohort ATT. Pre-cue values are
#     descriptive: the weights are chosen to make them small.
#
# Exploratory and outside the targets graph.
#   Rscript scripts/diagnostics/public_cue_staggered_pretrends.R

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
})

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))

window_start <- 1997L
horizon <- 7L
last_year <- 2022L
event_min <- -6L
placebo_draws <- 5000L

output_dir <- file.path(
  "data", "processed", "diagnostics", "public_cue_staggered_sdid", "pretrends"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cues <- tibble::tribble(
  ~iso3c, ~cue_year,
  "KOR", 2003L,
  "AUS", 2007L,
  "BRA", 2009L,
  "CHL", 2007L,
  "ZAF", 2010L,
  "URY", 2013L,
  "NZL", 2013L
)

panel_all <- targets::tar_read(china_top_m2_goods_panel) |>
  dplyr::select(iso3c, year, abs_distance_china, china_is_top) |>
  dplyr::mutate(year = as.integer(year), iso3c = as.character(iso3c),
                china_is_top = as.logical(china_is_top))

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
stopifnot(length(controls) == 105L, !any(cues$iso3c %in% controls))

years <- seq.int(window_start, last_year)
Y <- panel_all |>
  dplyr::filter(iso3c %in% c(controls, cues$iso3c), year %in% years) |>
  dplyr::select(iso3c, year, abs_distance_china) |>
  tidyr::pivot_wider(names_from = year, values_from = abs_distance_china) |>
  tibble::column_to_rownames("iso3c") |>
  as.matrix()
Y <- Y[, as.character(years)]
stopifnot(!anyNA(Y))

# ---- DiD event study ------------------------------------------------------
event_times <- seq.int(event_min, horizon - 1L)

did_curve <- function(units, cue_years, control_units) {
  control_mean <- colMeans(Y[control_units, , drop = FALSE])
  coefs <- vapply(seq_along(units), function(k) {
    gap <- Y[units[k], ] - control_mean
    idx <- as.character(cue_years[k] + event_times)
    gap[idx] - gap[as.character(cue_years[k] - 1L)]
  }, numeric(length(event_times)))
  rowMeans(coefs)
}

did_country <- function(unit, cue_year) {
  gap <- Y[unit, ] - colMeans(Y[controls, , drop = FALSE])
  e <- years - cue_year
  keep <- e <= horizon - 1L
  tibble::tibble(iso3c = unit, event_time = e[keep],
                 coef = gap[keep] - gap[as.character(cue_year - 1L)])
}

# Canonical DiD per country (post mean minus mean of all pre-cue years in the
# window), averaged over countries.
did_att <- function(units, cue_years, control_units) {
  control_mean <- colMeans(Y[control_units, , drop = FALSE])
  mean(vapply(seq_along(units), function(k) {
    gap <- Y[units[k], ] - control_mean
    e <- years - cue_years[k]
    mean(gap[e >= 0 & e <= horizon - 1L]) - mean(gap[e < 0])
  }, numeric(1)))
}

pre_e <- event_times[event_times <= -1L]
slope_of <- function(curve) {
  stats::coef(stats::lm(curve[event_times <= -1L] ~ pre_e))[[2]]
}
ss_of <- function(curve) sum(curve[event_times <= -2L]^2)

observed <- did_curve(cues$iso3c, cues$cue_year, controls)
observed_att <- did_att(cues$iso3c, cues$cue_year, controls)

set.seed(SDID_PLACEBO_SEED)
placebo <- replicate(placebo_draws, {
  drawn <- sample(controls, nrow(cues))
  rest <- setdiff(controls, drawn)
  curve <- did_curve(drawn, cues$cue_year, rest)
  c(curve, slope = slope_of(curve), ss = ss_of(curve),
    att = did_att(drawn, cues$cue_year, rest))
})
n_e <- length(event_times)
band <- tibble::tibble(
  event_time = event_times,
  coef = observed,
  placebo_low = apply(placebo[seq_len(n_e), ], 1, stats::quantile, 0.025),
  placebo_high = apply(placebo[seq_len(n_e), ], 1, stats::quantile, 0.975)
)
p_rank <- function(stat, draws) (1 + sum(abs(draws) >= abs(stat))) / (length(draws) + 1)
pretrend_tests <- tibble::tibble(
  statistic = c("slope of average coefficient on event time, -6 to -1",
                "sum of squared average coefficients, -6 to -2",
                "DiD ATT, post mean minus pre mean, averaged over countries"),
  value = c(slope_of(observed), ss_of(observed), observed_att),
  placebo_sd = c(stats::sd(placebo["slope", ]), stats::sd(placebo["ss", ]),
                 stats::sd(placebo["att", ])),
  p_placebo_two_sided = c(
    p_rank(slope_of(observed), placebo["slope", ]),
    (1 + sum(placebo["ss", ] >= ss_of(observed))) / (placebo_draws + 1),
    p_rank(observed_att, placebo["att", ])
  )
)

country_did <- dplyr::bind_rows(lapply(seq_len(nrow(cues)), function(k) {
  did_country(cues$iso3c[k], cues$cue_year[k])
}))

# ---- SDiD gaps ------------------------------------------------------------
sdid_gaps <- function(units, cue_year) {
  end <- cue_year + horizon - 1L
  cols <- as.character(seq.int(window_start, end))
  rows <- c(controls, sort(units))
  fit <- synthdid::synthdid_estimate(Y[rows, cols], length(controls),
                                     cue_year - window_start)
  w <- attr(fit, "weights")
  gap <- colMeans(Y[sort(units), cols, drop = FALSE]) -
    as.numeric(crossprod(w$omega, Y[controls, cols]))
  t0 <- cue_year - window_start
  adj <- gap - sum(w$lambda * gap[seq_len(t0)])
  stopifnot(abs(mean(adj[-seq_len(t0)]) - as.numeric(fit)) < 1e-10)
  tibble::tibble(unit = paste(sort(units), collapse = "+"),
                 n_treated = length(units),
                 event_time = seq.int(window_start, end) - cue_year,
                 gap = adj)
}
cohort_gaps <- dplyr::bind_rows(lapply(split(cues, cues$cue_year), function(d) {
  sdid_gaps(d$iso3c, d$cue_year[1])
}))
country_gaps <- dplyr::bind_rows(lapply(seq_len(nrow(cues)), function(k) {
  sdid_gaps(cues$iso3c[k], cues$cue_year[k])
}))
sdid_average <- cohort_gaps |>
  dplyr::filter(event_time >= event_min) |>
  dplyr::group_by(event_time) |>
  dplyr::summarise(gap = stats::weighted.mean(gap, n_treated), .groups = "drop")

# ---- Outputs --------------------------------------------------------------
readr::write_csv(band, file.path(output_dir, "did_event_study_average.csv"))
readr::write_csv(country_did, file.path(output_dir, "did_event_study_by_country.csv"))
readr::write_csv(pretrend_tests, file.path(output_dir, "did_pretrend_tests.csv"))
readr::write_csv(cohort_gaps, file.path(output_dir, "sdid_gaps_by_cohort.csv"))
readr::write_csv(country_gaps, file.path(output_dir, "sdid_gaps_by_country.csv"))
readr::write_csv(sdid_average, file.path(output_dir, "sdid_gaps_average.csv"))

plot_data <- dplyr::bind_rows(
  dplyr::transmute(country_did, panel = "DiD, uniform weights (reference: year before cue)",
                   iso3c, event_time, value = coef),
  dplyr::transmute(country_gaps, panel = "SDiD gaps (minus lambda-weighted pre-cue gap)",
                   iso3c = unit, event_time, value = gap)
)
plot_avg <- dplyr::bind_rows(
  dplyr::transmute(band, panel = "DiD, uniform weights (reference: year before cue)",
                   event_time, value = coef, low = placebo_low, high = placebo_high),
  dplyr::transmute(sdid_average, panel = "SDiD gaps (minus lambda-weighted pre-cue gap)",
                   event_time, value = gap, low = NA_real_, high = NA_real_)
)
g <- ggplot() +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey50") +
  geom_ribbon(data = plot_avg, aes(event_time, ymin = low, ymax = high),
              fill = "grey80", alpha = 0.7) +
  geom_line(data = plot_data, aes(event_time, value, colour = iso3c),
            linewidth = 0.4, alpha = 0.8) +
  geom_line(data = plot_avg, aes(event_time, value), linewidth = 1.1) +
  geom_point(data = plot_avg, aes(event_time, value), size = 1.6) +
  facet_wrap(~panel, ncol = 1) +
  labs(x = "Years relative to public cue", y = "Distance to China (gap)",
       colour = NULL,
       caption = paste0("Thick line: average of the seven cases. Grey band (DiD): ",
                        "2.5-97.5% of 5,000 placebo draws of seven controls.")) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom")
ggsave(file.path(output_dir, "pretrends_did_sdid.png"), g, width = 7.5, height = 8,
       dpi = 150)

print(as.data.frame(band))
print(as.data.frame(pretrend_tests))
print(as.data.frame(sdid_average))
