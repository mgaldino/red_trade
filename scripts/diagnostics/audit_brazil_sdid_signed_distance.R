#!/usr/bin/env Rscript

# Brazil SDiD, the paper's preferred specification (no covariates, 1997-2015,
# treatment 2009, the synth_data donor pool), with the SIGNED distance to China
# in place of the absolute distance (exploratory; outside the targets graph and
# outside the paper).
#
# Why: the absolute distance |q50 - q50 of China| folds around a China whose
# ideal point moves much more than the controls' (devil's-advocate finding E1 of
# the 14-case public-cue round, confirmed in
# quality_reports/adjudication/public_cue_fourteen_round/dfaf1470ed13/). Brazil is
# beyond China in 2013, 2015 and 2016, inside the paper's post window, because
# China's ideal point jumps past it (2015: China +0.61, Brazil +0.10 toward the
# US); some donors cross China in some years. The signed distance, q50 of the
# country minus q50 of China from the same raw file, has no fold; with year
# effects it equals the country's own ideal point, so the signed estimate
# measures Brazil's move along the ideal-point axis away from the US pole
# relative to synthetic Brazil, not its distance to China in the years it is
# beyond China. Adjudication item B1 left this check to the author, who asked
# for it on 2026-09-24.
#
# Design:
#   * Gate: the local absolute-distance fit reproduces the target
#     synth_fit_no_time_varying_covariates and the stored main summary
#     (paper_v4_brazil_sdid_no_covariates/main_summary.csv: -0.27277, SE 0.1306
#     with 20,000 replications), and the stored placebo-in-space distribution.
#   * The signed column uses the same panel, window, donors and estimator; only
#     Y changes. Placebo SE with the pipeline's replication count and seed
#     (20,000; 20260520) and placebo-in-space ranks over the same 96 units.
#   * Decomposition: the synthdid estimate is linear in Y given the weights, and
#     abs = signed + fold, with fold = |s| - s = 2 max(-s, 0) (zero on the US side
#     of China). With the absolute fit's weights, the absolute estimate splits
#     exactly into the signed outcome, Brazil's own fold and the donors' fold;
#     the signed fit then differs from the first term only by its weights.
#   * Window sensitivity (point estimates), with 1997-2012 added: it ends before
#     Brazil's first year beyond China.
#
#   LC_ALL=en_US.UTF-8 Rscript scripts/diagnostics/audit_brazil_sdid_signed_distance.R
# (no --vanilla: the project .Rprofile activates renv, which pins synthdid 0.0.9)
# BRAZIL_SIGNED_REPS overrides the replication count (smoke tests only).

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(readr)
  library(tibble); library(synthdid)
})

options(scipen = 999)
run_started <- Sys.time()

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
source(file.path("scripts", "diagnostics", "public_cue_specs.R"))
sdid_limit_blas_threads()
cores <- sdid_available_cores()

target_replications <- 20000L  # must mirror _targets.R (se_synth_no_time_varying_covariates)
replications <- as.integer(Sys.getenv("BRAZIL_SIGNED_REPS", as.character(target_replications)))
smoke <- replications < target_replications
if (smoke) message("NOTE: smoke test with ", replications, " replications.")

paper_dir <- file.path("data", "processed", "diagnostics", "paper_v4_brazil_sdid_no_covariates")
out_dir <- file.path("data", "processed", "diagnostics", "brazil_sdid_signed_distance")
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
op <- function(f) file.path(out_dir, f)

# ---- Gate ------------------------------------------------------------------
synth_data <- tar_read(synth_data)
target_fit <- tar_read(synth_fit_no_time_varying_covariates)
target_se <- tar_read(se_synth_no_time_varying_covariates)
stored_main <- read_csv(file.path(paper_dir, "main_summary.csv"), show_col_types = FALSE)
stored_dist <- read_csv(file.path(paper_dir, "placebo_distribution.csv"), show_col_types = FALSE)

fit_abs <- sdid_fit_spec(synth_data)
se_abs <- sdid_preferred_se(fit_abs, target_fit, target_se,
                            target_replications = target_replications,
                            cores = cores, checkpoint_dir = checkpoint_dir)
gate <- tibble(
  check = c("local fit vs target", "local fit vs stored main_summary",
            "target SE vs stored main_summary", "Brazil in stored placebo distribution"),
  value = c(as.numeric(fit_abs), as.numeric(fit_abs), se_abs$se,
            stored_dist$estimate[stored_dist$iso3c == "BRA"]),
  reference = c(as.numeric(target_fit), stored_main$estimate, stored_main$se_placebo,
                stored_main$estimate)
) |>
  mutate(abs_diff = abs(value - reference))
print(as.data.frame(gate))
write_csv(gate, op("gate_reproduction.csv"))
stopifnot(all(gate$abs_diff < 1e-10), grepl("^Reused target", se_abs$source))

# ---- Signed outcome --------------------------------------------------------
signed_panel <- public_cue_add_signed(synth_data)  # asserts |signed| = abs to 1e-10
signed_data <- signed_panel |>
  mutate(abs_distance_china = signed_distance_china) |>
  select(-signed_distance_china)
window_rows <- filter(signed_data, year >= 1997L, year <= 2015L)
stopifnot(!anyNA(window_rows$abs_distance_china),
          n_distinct(window_rows$iso3c) == stored_main$n_units)

fit_signed <- sdid_fit_spec(signed_data)
message(sprintf("Signed estimate = %.6f (absolute %.6f)", as.numeric(fit_signed), as.numeric(fit_abs)))
se_signed <- sdid_placebo_se(fit_signed, replications, seed = SDID_PLACEBO_SEED,
                             cores = cores, checkpoint_dir = checkpoint_dir,
                             label = "signed_no_covariates")
dist_signed <- sdid_rank_distribution(signed_data, label = "signed_no_covariates",
                                      cores = cores, checkpoint_dir = checkpoint_dir)
write_csv(dist_signed, op("placebo_distribution_signed.csv"))

rank_rows <- function(dist) {
  bra_rmspe <- dist$rmspe_pre[dist$iso3c == "BRA"]
  bind_rows(
    sdid_rank_inference(dist, "All valid assignments"),
    sdid_rank_inference(dist, "Pre-fit RMSPE no larger than twice Brazil",
                        keep_units = dist$iso3c[dist$status == "estimated" &
                                                  dist$rmspe_pre <= 2 * bra_rmspe])
  )
}
ranks <- bind_rows(
  rank_rows(stored_dist) |> mutate(outcome = "abs", .before = 1),
  rank_rows(dist_signed) |> mutate(outcome = "signed", .before = 1)
)
write_csv(ranks, op("rank_inference.csv"))

bra_pre_mean <- function(d) mean(d$abs_distance_china[d$iso3c == "BRA" & d$year >= 1997L & d$year <= 2008L])
summary_row <- function(fit, se, reps, source, outcome, dist, data) {
  r <- rank_rows(dist) |> slice(1)
  sdid_fit_summary_row(fit, outcome, se) |>
    mutate(outcome = outcome, .before = 1) |>
    mutate(rank_one_sided_negative = r$rank_one_sided_negative,
           rank_two_sided_absolute = r$rank_two_sided_absolute,
           rank_denominator = r$denominator,
           p_rank_one_sided_negative = r$p_rank_one_sided_negative,
           p_rank_two_sided_absolute = r$p_rank_two_sided_absolute,
           brazil_pre_mean = bra_pre_mean(data),
           se_replications = reps, se_seed = SDID_PLACEBO_SEED, se_source = source,
           smoke_test = smoke)
}
main_summary <- bind_rows(
  summary_row(fit_abs, se_abs$se, se_abs$replications, se_abs$source, "abs", stored_dist, synth_data),
  summary_row(fit_signed, as.numeric(se_signed), replications,
              "Locally computed; pipeline replication count and seed", "signed",
              dist_signed, signed_data)
)
stopifnot(abs(main_summary$rank_one_sided_negative[1] - stored_main$rank_one_sided_negative) == 0,
          abs(main_summary$rank_two_sided_absolute[1] - stored_main$rank_two_sided_absolute) == 0)
write_csv(main_summary, op("main_summary.csv"))
print(as.data.frame(main_summary |> select(outcome, estimate, se_placebo, p_normal_two_sided,
                                           rank_one_sided_negative, rank_two_sided_absolute,
                                           rank_denominator, rmspe_pre)))

# ---- Weights ---------------------------------------------------------------
weights_of <- function(fit, outcome) {
  s <- attr(fit, "setup"); w <- attr(fit, "weights")
  list(
    unit = tibble(outcome = outcome, iso3c = rownames(s$Y)[seq_len(s$N0)],
                  unit_weight = as.numeric(w$omega)),
    time = tibble(outcome = outcome, year = as.integer(colnames(s$Y)[seq_len(s$T0)]),
                  time_weight = as.numeric(w$lambda))
  )
}
w_abs <- weights_of(fit_abs, "abs"); w_signed <- weights_of(fit_signed, "signed")
unit_weights <- bind_rows(w_abs$unit, w_signed$unit) |>
  group_by(outcome) |> arrange(desc(unit_weight), .by_group = TRUE) |>
  mutate(weight_rank = row_number()) |> ungroup()
time_weights <- bind_rows(w_abs$time, w_signed$time)
write_csv(unit_weights, op("unit_weights.csv"))
write_csv(time_weights, op("time_weights.csv"))

# ---- Gaps by year and the fold decomposition -------------------------------
# DiD of any Y matrix (rows ordered as the fit's setup) under given weights:
# the synthdid point estimate formula, linear in Y.
did_given_weights <- function(Y, N0, T0, omega, lambda) {
  N1 <- nrow(Y) - N0; T1 <- ncol(Y) - T0
  as.numeric(t(c(-omega, rep(1 / N1, N1))) %*% Y %*% c(-lambda, rep(1 / T1, T1)))
}
s_abs <- attr(fit_abs, "setup"); wa <- attr(fit_abs, "weights")
stopifnot(abs(did_given_weights(s_abs$Y, s_abs$N0, s_abs$T0, wa$omega, wa$lambda) -
                as.numeric(fit_abs)) < 1e-12)
signed_matrix <- signed_panel |>
  filter(year >= 1997L, year <= 2015L) |>
  select(iso3c, year, signed_distance_china) |>
  pivot_wider(names_from = year, values_from = signed_distance_china) |>
  tibble::column_to_rownames("iso3c") |>
  as.matrix()
signed_matrix <- signed_matrix[rownames(s_abs$Y), colnames(s_abs$Y)]
stopifnot(max(abs(abs(signed_matrix) - s_abs$Y)) < 1e-10)
fold_matrix <- abs(signed_matrix) - signed_matrix
brazil_row <- rownames(s_abs$Y) == "BRA"
fold_brazil <- fold_matrix; fold_brazil[!brazil_row, ] <- 0
fold_donors <- fold_matrix; fold_donors[brazil_row, ] <- 0
dd <- function(Y) did_given_weights(Y, s_abs$N0, s_abs$T0, wa$omega, wa$lambda)
decomposition <- tibble(
  component = c("absolute estimate (absolute-fit weights)",
                "signed outcome, absolute-fit weights",
                "Brazil's fold (years beyond China)",
                "donors' fold, contribution to the estimate (sign already applied)",
                "sum of the three components",
                "signed fit (own weights)",
                "reweighting: signed fit minus signed outcome under absolute-fit weights"),
  value = c(as.numeric(fit_abs), dd(signed_matrix), dd(fold_brazil), dd(fold_donors),
            dd(signed_matrix) + dd(fold_brazil) + dd(fold_donors),
            as.numeric(fit_signed), as.numeric(fit_signed) - dd(signed_matrix))
)
stopifnot(abs(decomposition$value[5] - decomposition$value[1]) < 1e-12)
write_csv(decomposition, op("fold_decomposition.csv"))
print(as.data.frame(decomposition))

gap_rows <- function(fit, outcome) {
  s <- attr(fit, "setup"); w <- attr(fit, "weights")
  omega <- as.numeric(w$omega); lambda <- as.numeric(w$lambda)
  years <- as.integer(colnames(s$Y))
  treated <- as.numeric(s$Y[s$N0 + 1L, ])
  synthetic <- as.numeric(t(omega) %*% s$Y[seq_len(s$N0), , drop = FALSE])
  gap <- treated - synthetic
  effect <- gap - sum(lambda * gap[seq_len(s$T0)])
  stopifnot(abs(mean(effect[(s$T0 + 1L):length(effect)]) - as.numeric(fit)) < 1e-12)
  tibble(outcome = outcome, year = years, brazil = treated, synthetic = synthetic,
         gap = gap, effect_vs_lambda_pre = effect, post = years >= 2009L)
}
gaps <- bind_rows(gap_rows(fit_abs, "abs"), gap_rows(fit_signed, "signed"))
write_csv(gaps, op("gap_by_year.csv"))

side_by_year <- signed_panel |>
  filter(year >= 1997L, year <= 2015L) |>
  group_by(year) |>
  summarise(brazil_signed = signed_distance_china[iso3c == "BRA"],
            donors_beyond_china = sum(signed_distance_china[iso3c != "BRA"] < 0),
            donors = sum(iso3c != "BRA"),
            abs_weight_on_donors_beyond_china = sum(
              wa$omega[match(iso3c[iso3c != "BRA" & signed_distance_china < 0],
                             rownames(s_abs$Y)[seq_len(s_abs$N0)])]),
            .groups = "drop")
write_csv(side_by_year, op("side_by_year.csv"))

# ---- Window sensitivity (point estimates) ----------------------------------
windows <- list(c(1997L, 2012L), c(1997L, 2013L), c(1997L, 2014L), c(1997L, 2015L),
                c(1997L, 2016L), c(1998L, 2015L), c(1999L, 2015L), c(2000L, 2015L))
window_sensitivity <- bind_rows(lapply(windows, function(wd) {
  bind_rows(
    tibble(outcome = "abs", estimate = as.numeric(sdid_fit_spec(synth_data, year_start = wd[1], year_end = wd[2]))),
    tibble(outcome = "signed", estimate = as.numeric(sdid_fit_spec(signed_data, year_start = wd[1], year_end = wd[2])))
  ) |>
    mutate(year_start = wd[1], year_end = wd[2], .before = 1)
})) |>
  pivot_wider(names_from = outcome, values_from = estimate)
stored_windows <- read_csv(file.path(paper_dir, "window_sensitivity.csv"), show_col_types = FALSE)
window_check <- inner_join(window_sensitivity, stored_windows |> select(year_start, year_end, stored = estimate),
                           by = c("year_start", "year_end"))
stopifnot(nrow(window_check) == 7L, max(abs(window_check$abs - window_check$stored)) < 1e-10)
write_csv(window_sensitivity, op("window_sensitivity.csv"))
print(as.data.frame(window_sensitivity))

writeLines(capture.output(sessionInfo()), op("session_info.txt"))
message("Done in ", sprintf("%.1f", as.numeric(difftime(Sys.time(), run_started, units = "mins"))),
        " min -> ", out_dir)
