#!/usr/bin/env Rscript

# Direction of the response to the public cue by the sign of theta: fect part
# (exploratory; outside the targets graph and outside the paper).
#
# Plan: quality_reports/plans/2026-09-29_public_cue_theta_groups.md, section
# "Desenho revisado" (earlier sections are record only). Proposition 1(i) of the
# model: a nonzero response has the sign of theta. The author coded the sign case
# by case (public_cue_theta in public_cue_specs.R). Positive = toward the US on the
# signed distance, i.e., away from China for cases on the US side of China.
#
# Model (the fourteen-case round, unchanged): the 14 public-cue cases treated from
# their cue year while China is the top goods-export destination; clean controls
# (complete 1997-2022 panels, never China-top); outcome signed_distance_china; no
# Z; fect IFE, two-way FE, EM, min.T0 = 1, 1,000 bootstraps, seed 42, and every
# other argument as in estimate_public_cue_pooled_ife.R (PUBLIC_CUE_ROUND=fourteen),
# whose panel construction this script copies. No treated case reverses in
# 1997-2022, so fect resamples the 14 treated units among themselves and the 105
# controls apart.
#
# Groups (fect `group`, a unit-level constant; fect requires a group value on
# every unit, so the controls get one of their own):
#   neg_us  theta < 0 on the US side of China: KOR, AUS, JPN, NZL
#   pos_us  theta > 0 on the US side of China: CHL, BRA, PER, RUS, ZAF, URY
#   other   treated, outside Delta: SAU, MYS, TKM (beyond China in pre-cue years)
#           and MMR (theta undetermined)
#   control the 105 clean controls
#
# Estimands (event times 0..6 from the cue; fect labels the first treated period
# 1, so event times 0..6 are fect periods 1..7):
#   tau_neg = equal-weight mean over the neg_us countries of each country's
#             average effect over event times 0..6 (prediction > 0)
#   tau_pos = the same over the pos_us countries (prediction < 0)
#   Delta   = tau_neg - tau_pos (prediction > 0)
#   Delta_mag_signed = mean(JPN, KOR) - mean(AUS, NZL); point only (SAU is beyond
#             China on this axis; no fect inference for Delta_mag, per the plan).
#
# Inference: from the joint bootstrap replicates (keep.sims = TRUE). eff.boot holds
# the unit effects of every replicate and colnames.boot the resampled unit indices
# (boot.id); tau and Delta are recomputed in each replicate from the drawn units,
# a unit drawn twice counting twice. The resampling is not stratified by group, so
# a group can be empty in a replicate; those replicates are counted and dropped,
# and inference conditions on replicates in which both groups are drawn. fect's
# own group ATTs (est.group.output[[g]]$att.on.boot) give the same tau in every
# replicate (checked); eff.boot is used because it defines the estimand directly
# by calendar year and also yields Delta(t) and the placebo windows. Reported:
# bootstrap SE, 95% percentile interval, a one-sided percentile p for the
# predicted direction (share of usable replicates at zero or on the wrong side),
# and the one-sided normal p for reference.
#
# Variants (same outputs for each):
#   cv        r chosen by cross-validation over 0..3 (the fourteen round chose 0);
#             descriptive: with r = 0 the baseline is the whole pre-cue period, and
#             the theta groups already drift apart before the cue. Sequential
#             bootstrap, as in the fourteen round.
#   r1, r2    IFE with r fixed at 1 and at 2. Bootstrap run in parallel (8 workers,
#             fect's doRNG streams from seed 42; the draws therefore differ from
#             the sequential ones but are shared by each variant's main and placebo
#             fits). fect's default EM settings (tol 1e-5, max.iteration 5,000):
#             the main fits converge (3,727 and 1,175 iterations); the placebo
#             fits hit the cap. Their points move with the cap (engine_checks.csv,
#             caps 5,000 and 50,000), and in the smoke-test stage the r = 1 placebo
#             run at tol 1e-7 was still moving after 1,000,000 iterations, so with
#             r >= 1 the placebo is not pinned down by the data (units with few
#             fitting years). Reported as fect returns it, flagged.
#   cfe_trend two-way FE plus a unit-specific linear time trend, r = 0 (fect
#             method = "cfe", Q.type = "linear"; kappa defaults to the unit).
#             DEVIATION: fect 2.4.5 cannot deliver this estimator here. Q.type =
#             "linear" enters the raw year (1997-2022), which makes the unit
#             intercept and the unit slope nearly collinear; the backfitting starts
#             at the two-way FE fit and, at the default max.iteration (5,000), is
#             still close to it (tau and Delta within about 0.002 of the r = 0
#             fit); with a higher cap fect's stopping rule ends it after about
#             63,000 iterations at Delta = 0.17, far from the least-squares fixed
#             point (-0.22). With a centred year the main fit converges, but the
#             placebo fits (KOR keeps two fitting years) need about 110,000
#             iterations per fit. The
#             estimator is the least-squares fit of y on unit FE + year FE + unit
#             x centred-year slope over the untreated cells (the fixed point of
#             fect's EM), so the script computes it directly (lm.fit, exact) and
#             bootstraps it over the resampled units that fect's sequential
#             bootstrap draws with seed 42. Checks: (i) the same code without the
#             trend reproduces fect's r = 0 estimates in every replicate, main and
#             placebo; (ii) fect cfe with a centred year run to tol = 1e-9
#             reproduces the direct points; (iii) the resampled units equal those
#             of a fect cfe bootstrap (first 20 replicates). The as-specified fect
#             cfe points are saved for the record.
#
# Time placebo, for each variant: placeboTest = TRUE. fect masks the treated units'
# observations whose relative period T.on lies in placebo.period and predicts them
# out of sample; T.on = 0 is the last pre-cue year (cue - 1), so placebo.period =
# c(-3, 0) is cue - 4 .. cue - 1 (main, as in the task) and c(-2, 0) is
# cue - 3 .. cue - 1 (the plan's second fake cue; KOR has six pre-cue years,
# 1997-2002, and keeps two for fitting under the main placebo, three under the
# second). The placebo tau and Delta average the out-of-sample effects over those
# calendar years with the same equal weights. fect does not allow a placebo test
# with cross-validation, so the placebo of the cv variant fixes r at the value
# cross-validation chose. Reading rule of the plan: a post-cue Delta counts as a
# cue effect only when it exceeds the placebo Delta of the same estimator. When a
# variant's main and placebo fits share the bootstrap draws, the paired contrast
# post Delta - placebo Delta is also reported.
#
# Event study: Delta(t), tau_neg(t), tau_pos(t) by event time from the unit effects
# of each fit (in the main fits the pre-cue values are the treated units'
# in-sample residuals, the usual fect pre-period estimates; in the placebo fits
# the placebo window is out of sample), with bootstrap SEs from the same replicates.
#
# Gates (before anything new is written):
#   1. The plain fit reproduces the stored fourteen_case / clean_controls / signed
#      row of public_cue_pooled_ife/fourteen_round/fect_results.csv (att.avg and
#      its SE, the 0-6 average and its SE) and the stored per-country 0-6 effects
#      in fect_country_effects.csv (tolerance 1e-8).
#   2. The same fit with `group` and `keep.sims = TRUE` leaves estimates, SEs,
#      bootstrap draws and unit effects unchanged (differences reported).
#   3. tau_neg and tau_pos of the cv fit equal the means of the stored per-country
#      0-6 effects of each group (1e-10).
#   4. For every fect fit: the resampled unit indices match D.boot; tau from
#      eff.boot equals tau from fect's group ATTs in every replicate (1e-10); the
#      placebo point estimates and SEs match fect's group placebo output (1e-10).
# With fewer than 1,000 bootstraps (smoke test) gate 1 checks estimates only.
#
# Run (fect 2.4.5 lives in the user library, outside renv):
#   LC_ALL=en_US.UTF-8 Rscript --vanilla scripts/diagnostics/estimate_public_cue_theta_groups_fect.R
# THETA_FECT_NBOOTS overrides the number of bootstraps and THETA_FECT_OUTPUT_DIR
# the output directory (smoke tests only).

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
})

source(file.path("scripts", "diagnostics", "public_cue_specs.R"))

`%||%` <- function(a, b) if (is.null(a)) b else a

year_start <- 1997L
year_end <- 2022L
expected_years <- seq.int(year_start, year_end)
expected_n_years <- length(expected_years)
fect_bootstraps <- as.integer(Sys.getenv("THETA_FECT_NBOOTS", "1000"))
full_run <- fect_bootstraps >= 1000L
outcome <- "signed_distance_china"
parallel_cores <- 8L
# fect's default EM cap (5,000) for the r1 and r2 fits. The placebo fits with
# r >= 1 hit it (units with few fitting years); see the cap-sensitivity rows of
# engine_checks.csv. A higher cap does not fix it (header).
IFE_MAX_ITER <- 5000L
stopifnot(as.character(utils::packageVersion("fect")) == "2.4.5")

output_dir <- Sys.getenv(
  "THETA_FECT_OUTPUT_DIR",
  file.path("data", "processed", "diagnostics", "public_cue_theta_groups", "fect")
)
stored_dir <- file.path("data", "processed", "diagnostics", "public_cue_pooled_ife",
                        "fourteen_round")

groups <- public_cue_theta_groups$signed
mag <- list(large = c("JPN", "KOR"), small = c("AUS", "NZL"))
stopifnot(all(unlist(mag) %in% groups$neg),
          identical(sort(setdiff(public_cue_theta_mag$large, "SAU")), sort(mag$large)),
          identical(sort(public_cue_theta_mag$small), sort(mag$small)))
placebo_periods <- list(placebo_c4 = c(-3L, 0L), placebo_c3 = c(-2L, 0L))
predicted <- list(tau_neg = 1, tau_pos = -1, delta = 1)

# ---- Panel (copied from estimate_public_cue_pooled_ife.R, clean controls) ----

panel <- targets::tar_read(china_top_m2_goods_panel) |>
  dplyr::filter(year >= year_start, year <= year_end) |>
  dplyr::select(iso3c, country_name, year, abs_distance_china, china_is_top) |>
  dplyr::mutate(
    year = as.integer(year),
    iso3c = as.character(iso3c),
    abs_distance_china = as.numeric(abs_distance_china),
    china_is_top = as.logical(china_is_top)
  ) |>
  dplyr::arrange(iso3c, year) |>
  public_cue_add_signed()

unit_audit <- panel |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    complete_common_panel = dplyr::n_distinct(year) == expected_n_years &
      setequal(year, expected_years) &
      all(!is.na(abs_distance_china)) & all(!is.na(china_is_top)),
    ever_china_top = any(china_is_top %in% TRUE),
    goods_entry_year = if (any(china_is_top %in% TRUE & year >= 2000L)) {
      min(year[china_is_top %in% TRUE & year >= 2000L])
    } else {
      NA_integer_
    },
    .groups = "drop"
  )
complete_units <- sort(unit_audit$iso3c[unit_audit$complete_common_panel])
clean_donors <- sort(
  unit_audit$iso3c[unit_audit$complete_common_panel & !unit_audit$ever_china_top]
)

focal_cues <- dplyr::rename(public_cue_spec("fourteen_case"), public_cue_year = cue_year)
stopifnot(all(focal_cues$iso3c %in% complete_units))

panel_data <- panel |>
  dplyr::filter(iso3c %in% c(clean_donors, focal_cues$iso3c)) |>
  dplyr::left_join(focal_cues, by = "iso3c") |>
  dplyr::left_join(dplyr::select(unit_audit, iso3c, goods_entry_year), by = "iso3c") |>
  dplyr::mutate(
    focal_country = !is.na(public_cue_year),
    treatment = as.integer(
      focal_country & year >= public_cue_year &
        (china_is_top %in% TRUE | year < goods_entry_year)
    ),
    model_outcome = .data[[outcome]],
    country_id = as.integer(factor(iso3c)),
    theta_group = dplyr::case_when(
      iso3c %in% groups$neg ~ "neg_us",
      iso3c %in% groups$pos ~ "pos_us",
      focal_country ~ "other",
      TRUE ~ "control"
    ),
    year_centered = year - mean(expected_years)
  ) |>
  dplyr::arrange(country_id, year)

stopifnot(
  dplyr::n_distinct(panel_data$iso3c[panel_data$theta_group == "control"]) == 105L,
  setequal(unique(panel_data$iso3c[panel_data$theta_group == "other"]),
           c("SAU", "MYS", "TKM", "MMR")),
  # No treated case switches treatment off inside the window.
  all(dplyr::summarise(dplyr::group_by(dplyr::filter(panel_data, focal_country), iso3c),
                       ok = all(treatment == as.integer(year >= public_cue_year)))$ok)
)

# ---- fect call (arguments of the fourteen round) ----------------------------

fit_fect <- function(r_fixed = NULL, method = "ife", q_type = NULL, q = NULL,
                     grouped = TRUE, keep_sims = TRUE, placebo = NULL, label = "",
                     parallel = FALSE, max_iter = 5000L, tol = 1e-5, se = TRUE,
                     nboots = fect_bootstraps) {
  message("Estimating `", label, "`.")
  n_warn <- 0L
  set.seed(42L)
  timing <- system.time({
    fit <- withCallingHandlers(
      fect::fect(
        model_outcome ~ treatment,
        data = as.data.frame(panel_data),
        index = c("country_id", "year"),
        method = method,
        force = "two-way",
        na.rm = FALSE,
        em = TRUE,
        se = se,
        nboots = nboots,
        parallel = parallel,
        cores = if (isTRUE(parallel)) parallel_cores else NULL,
        CV = is.null(r_fixed),
        r = if (is.null(r_fixed)) c(0, 3) else r_fixed,
        min.T0 = 1L,
        max.missing = expected_n_years,
        seed = 42L,
        max.iteration = max_iter,
        tol = tol,
        group = if (grouped) "theta_group" else NULL,
        keep.sims = keep_sims,
        Q.type = q_type,
        Q = q,
        placeboTest = !is.null(placebo),
        placebo.period = placebo
      ),
      warning = function(w) {
        if (grepl("converge", conditionMessage(w))) {
          n_warn <<- n_warn + 1L
          invokeRestart("muffleWarning")
        }
      }
    )
  })
  fit$elapsed_seconds <- as.numeric(timing[["elapsed"]])
  fit$n_nonconvergence_warnings <- n_warn
  fit$parallel_boot <- isTRUE(parallel)
  fit$max_iter <- max_iter
  message("  done in ", round(fit$elapsed_seconds), " s; full-sample EM iterations ",
          paste(fit$niter %||% NA, collapse = "/"), "; non-convergence warnings ",
          n_warn, if (isTRUE(parallel)) " (replicate warnings not visible in parallel)" else "")
  fit
}

selected_r <- function(fit) {
  if (!is.null(fit$r.cv) && "r" %in% names(fit$r.cv)) {
    as.integer(fit$r.cv[["r"]])
  } else if (!is.null(fit$r.cv)) {
    as.integer(fit$r.cv[1])
  } else {
    NA_integer_
  }
}

# ---- Unit bookkeeping -------------------------------------------------------

unit_info_for <- function(fit) {
  ids <- as.integer(as.character(fit$id))
  info <- dplyr::distinct(panel_data, country_id, iso3c, public_cue_year, theta_group)
  info <- info[match(ids, info$country_id), ]
  stopifnot(!anyNA(info$country_id), nrow(info) == ncol(fit$eff))
  info
}

years_of <- function(fit) as.integer(as.character(fit$rawtime))

# Per-unit mean of `effmat` columns over calendar years cue + lo .. cue + hi.
# `cols` indexes fit$id (the unit order of fect's internal matrices).
unit_window_means <- function(effmat, cols, info, years, lo, hi) {
  vapply(seq_along(cols), function(j) {
    cue <- info$public_cue_year[cols[j]]
    if (is.na(cue)) return(NA_real_)
    rows <- which(years >= cue + lo & years <= cue + hi)
    stopifnot(length(rows) == hi - lo + 1L)
    v <- effmat[rows, j]
    stopifnot(!anyNA(v))
    mean(v)
  }, numeric(1))
}

group_stats <- function(unit_values, grp) {
  neg <- grp == "neg_us"
  pos <- grp == "pos_us"
  tau_neg <- if (any(neg)) mean(unit_values[neg]) else NA_real_
  tau_pos <- if (any(pos)) mean(unit_values[pos]) else NA_real_
  c(tau_neg = tau_neg, tau_pos = tau_pos, delta = tau_neg - tau_pos)
}

# Point estimates and replicate draws over a calendar window around the cue.
window_estimates <- function(fit, lo, hi) {
  info <- unit_info_for(fit)
  years <- years_of(fit)
  in_groups <- which(info$theta_group %in% c("neg_us", "pos_us"))
  point_units <- rep(NA_real_, nrow(info))
  point_units[in_groups] <- unit_window_means(
    fit$eff[, in_groups, drop = FALSE], in_groups, info, years, lo, hi
  )
  point <- group_stats(point_units[in_groups], info$theta_group[in_groups])
  mag_point <- mean(point_units[match(mag$large, info$iso3c)]) -
    mean(point_units[match(mag$small, info$iso3c)])
  B <- dim(fit$eff.boot)[3]
  stopifnot(length(fit$colnames.boot) == B)
  draws <- t(vapply(seq_len(B), function(b) {
    cols <- fit$colnames.boot[[b]]
    keep <- which(info$theta_group[cols] %in% c("neg_us", "pos_us"))
    vals <- unit_window_means(fit$eff.boot[, , b][, keep, drop = FALSE], cols[keep],
                              info, years, lo, hi)
    c(group_stats(vals, info$theta_group[cols[keep]]),
      n_neg = sum(info$theta_group[cols] == "neg_us"),
      n_pos = sum(info$theta_group[cols] == "pos_us"))
  }, numeric(5)))
  list(point = point, units = point_units, info = info, draws = draws,
       mag_point = mag_point)
}

# Checks the resampled indices against D.boot (so colnames.boot indexes fit$id).
check_boot_ids <- function(fit) {
  B <- dim(fit$eff.boot)[3]
  ok <- vapply(seq_len(B), function(b) {
    cols <- fit$colnames.boot[[b]]
    a <- fit$D.boot[, , b]
    e <- fit$D.dat[, cols]
    identical(dim(a), dim(e)) &&
      all((is.na(a) & is.na(e)) | (!is.na(a) & !is.na(e) & a == e))
  }, logical(1))
  stopifnot(all(ok))
  invisible(TRUE)
}

summarise_draws <- function(point, draws) {
  use <- draws[, "n_neg"] > 0 & draws[, "n_pos"] > 0
  dplyr::bind_rows(lapply(names(point), function(nm) {
    x <- draws[use, nm]
    stopifnot(!anyNA(x))
    se <- stats::sd(x)
    s <- predicted[[nm]]
    tibble::tibble(
      estimand = nm,
      predicted_sign = s,
      estimate = unname(point[[nm]]),
      se_bootstrap = se,
      ci_95_low_percentile = unname(stats::quantile(x, 0.025)),
      ci_95_high_percentile = unname(stats::quantile(x, 0.975)),
      p_one_sided_bootstrap = if (s > 0) mean(x <= 0) else mean(x >= 0),
      p_one_sided_normal = stats::pnorm(-s * unname(point[[nm]]) / se),
      replicates_total = nrow(draws),
      replicates_used = sum(use),
      replicates_empty_neg = sum(draws[, "n_neg"] == 0),
      replicates_empty_pos = sum(draws[, "n_pos"] == 0)
    )
  }))
}

# fect's own group ATTs over periods 1..7, replicate by replicate.
check_group_atts <- function(fit, est) {
  for (g in c("neg_us", "pos_us")) {
    time_on <- fit$group.output[[g]]$time.on
    stopifnot(all(1:7 %in% time_on))
    rows <- match(1:7, time_on)
    point_fect <- mean(fit$group.output[[g]]$att.on[rows])
    nm <- if (g == "neg_us") "tau_neg" else "tau_pos"
    stopifnot(abs(point_fect - est$point[[nm]]) < 1e-10)
    boot_fect <- colMeans(fit$est.group.output[[g]]$att.on.boot[rows, , drop = FALSE])
    ours <- est$draws[, nm]
    nonempty <- est$draws[, if (g == "neg_us") "n_neg" else "n_pos"] > 0
    stopifnot(length(boot_fect) == length(ours),
              all(is.na(boot_fect[!nonempty])),
              max(abs(boot_fect[nonempty] - ours[nonempty])) < 1e-10)
  }
  invisible(TRUE)
}

# fect's group placebo (count-weighted over the placebo periods) against ours.
check_group_placebo <- function(fit, est) {
  res <- dplyr::bind_rows(lapply(c("neg_us", "pos_us"), function(g) {
    nm <- if (g == "neg_us") "tau_neg" else "tau_pos"
    fp <- fit$est.group.output[[g]]$att.placebo
    stopifnot(!is.null(fp))
    nonempty <- est$draws[, if (g == "neg_us") "n_neg" else "n_pos"] > 0
    tibble::tibble(
      group = g,
      diff_estimate = abs(fp[1, "ATT.placebo"] - est$point[[nm]]),
      diff_se_same_replicates = abs(fp[1, "S.E."] - stats::sd(est$draws[nonempty, nm]))
    )
  }))
  stopifnot(all(res$diff_estimate < 1e-10), all(res$diff_se_same_replicates < 1e-10))
  res
}

# Event-time table from the unit effects of a fit.
event_study <- function(fit, e_range) {
  info <- unit_info_for(fit)
  years <- years_of(fit)
  cols_g <- which(info$theta_group %in% c("neg_us", "pos_us"))
  value_at <- function(effmat, cols, e) {
    vapply(seq_along(cols), function(j) {
      row <- match(info$public_cue_year[cols[j]] + e, years)
      if (is.na(row)) NA_real_ else effmat[row, j]
    }, numeric(1))
  }
  stats_at <- function(vals, grp) {
    ok <- !is.na(vals)
    group_stats(vals[ok], grp[ok])
  }
  B <- dim(fit$eff.boot)[3]
  dplyr::bind_rows(lapply(e_range, function(e) {
    pv <- value_at(fit$eff[, cols_g, drop = FALSE], cols_g, e)
    grp <- info$theta_group[cols_g]
    point <- stats_at(pv, grp)
    draws <- t(vapply(seq_len(B), function(b) {
      cols <- fit$colnames.boot[[b]]
      keep <- which(info$theta_group[cols] %in% c("neg_us", "pos_us"))
      v <- value_at(fit$eff.boot[, , b][, keep, drop = FALSE], cols[keep], e)
      stats_at(v, info$theta_group[cols[keep]])
    }, numeric(3)))
    use <- stats::complete.cases(draws)
    tibble::tibble(
      event_time = e,
      n_neg = sum(!is.na(pv) & grp == "neg_us"),
      n_pos = sum(!is.na(pv) & grp == "pos_us"),
      tau_neg = point[["tau_neg"]],
      se_tau_neg = stats::sd(draws[use, "tau_neg"]),
      tau_pos = point[["tau_pos"]],
      se_tau_pos = stats::sd(draws[use, "tau_pos"]),
      delta = point[["delta"]],
      se_delta = stats::sd(draws[use, "delta"]),
      delta_ci_95_low_percentile = unname(stats::quantile(draws[use, "delta"], 0.025)),
      delta_ci_95_high_percentile = unname(stats::quantile(draws[use, "delta"], 0.975)),
      replicates_used = sum(use)
    )
  }))
}

# 0-6 average and its SE exactly as event_att() of the pooled script.
event_0_6 <- function(fit) {
  info <- unit_info_for(fit)
  years <- years_of(fit)
  focal <- which(!is.na(info$public_cue_year))
  direct <- mean(unit_window_means(fit$eff[, focal, drop = FALSE], focal, info,
                                   years, 0L, 6L))
  periods <- match(1:7, as.numeric(fit$time))
  stopifnot(!anyNA(periods),
            abs(mean(as.numeric(fit$att)[periods]) - direct) < 1e-8)
  list(att = direct,
       se = stats::sd(colMeans(fit$att.boot[periods, , drop = FALSE]), na.rm = TRUE))
}

# Per-country 0-6 effects over treated years only (country_att() of the pooled
# script), for the gate.
country_0_6 <- function(fit) {
  info <- unit_info_for(fit)
  years <- years_of(fit)
  focal <- which(!is.na(info$public_cue_year))
  vals <- vapply(focal, function(j) {
    rows <- which(years >= info$public_cue_year[j] & years <= info$public_cue_year[j] + 6L)
    stopifnot(all(fit$D.dat[rows, j] == 1))
    mean(fit$eff[rows, j])
  }, numeric(1))
  tibble::tibble(iso3c = info$iso3c[focal], att_country_event_0_6 = vals)
}

max_abs_diff <- function(a, b) {
  if (is.null(a) && is.null(b)) return(0)
  a <- as.numeric(a)
  b <- as.numeric(b)
  if (length(a) != length(b)) return(NA_real_)
  if (!identical(is.na(a), is.na(b))) return(Inf)
  if (all(is.na(a))) return(0)
  max(abs(a - b), na.rm = TRUE)
}

# ---- Direct least-squares engine (cfe_trend variant) --------------------------
# Imputation estimator with unit FE, year FE and (if trend) a unit-specific slope
# on the centred year, fitted on the untreated cells (minus the placebo window of
# the treated units), for the columns `cols` of the unit order of fect's matrices
# (a column drawn twice is two units, as in fect's bootstrap). Returns y - y_hat.
# One unit slope is dropped: the slopes sum to the centred year, which the year FE
# and unit FE already span, so the fitted values are unchanged.
ls_eff_cols <- function(S, cols, placebo = NULL, trend = TRUE) {
  TT <- nrow(S$Y)
  k <- length(cols)
  Y <- S$Y[, cols, drop = FALSE]
  fitcell <- S$D[, cols, drop = FALSE] == 0
  if (!is.null(placebo)) {
    cue <- S$info$public_cue_year[cols]
    for (j in which(!is.na(cue))) {
      mask <- S$years >= cue[j] - 1L + placebo[1] & S$years <= cue[j] - 1L + placebo[2]
      stopifnot(sum(mask) == placebo[2] - placebo[1] + 1L, all(fitcell[mask, j]))
      fitcell[mask, j] <- FALSE
    }
  }
  n <- TT * k
  unit <- rep(seq_len(k), each = TT)
  tpos <- rep(seq_len(TT), k)
  tc <- (S$years - mean(S$years))[tpos]
  n_slope <- if (trend) k - 1L else 0L
  p <- k + n_slope + TT - 1L
  X <- matrix(0, n, p)
  X[cbind(seq_len(n), unit)] <- 1
  if (trend) {
    s <- which(unit < k)
    X[cbind(s, k + unit[s])] <- tc[s]
  }
  s <- which(tpos > 1L)
  X[cbind(s, k + n_slope + tpos[s] - 1L)] <- 1
  f <- which(c(fitcell))
  q <- stats::lm.fit(X[f, , drop = FALSE], c(Y)[f])
  stopifnot(q$rank == p)
  Y - matrix(drop(X %*% q$coefficients), TT, k)
}

# A fect-like object from the direct engine, with the fields the summaries use.
ls_fit <- function(S, draws, placebo = NULL, trend = TRUE, label = "") {
  message("Direct least squares `", label, "`.")
  t0 <- proc.time()[["elapsed"]]
  TT <- nrow(S$Y)
  N <- ncol(S$Y)
  B <- length(draws)
  eff <- ls_eff_cols(S, seq_len(N), placebo, trend)
  eff_boot <- array(NA_real_, c(TT, N, B))
  for (b in seq_len(B)) eff_boot[, , b] <- ls_eff_cols(S, draws[[b]], placebo, trend)
  focal <- which(!is.na(S$info$public_cue_year))
  # Treated-cell aggregates as fect defines them: att.avg over all treated cells;
  # att by period 1..7 (event times 0..6) over the treated units; the placebo ATT
  # over the placebo window of all treated units.
  aggregates <- function(effmat, cols) {
    tr <- which(cols %in% focal)
    dmat <- S$D[, cols[tr], drop = FALSE]
    att_avg <- mean(effmat[, tr, drop = FALSE][dmat == 1])
    att <- vapply(0:6, function(e) mean(vapply(tr, function(j) {
      effmat[match(S$info$public_cue_year[cols[j]] + e, S$years), j]
    }, numeric(1))), numeric(1))
    att_pl <- if (is.null(placebo)) NA_real_ else
      mean(unit_window_means(effmat[, tr, drop = FALSE], cols[tr], S$info, S$years,
                             placebo[1] - 1L, placebo[2] - 1L))
    list(att_avg = att_avg, att = att, att_pl = att_pl)
  }
  a0 <- aggregates(eff, seq_len(N))
  ab <- lapply(seq_len(B), function(b) aggregates(eff_boot[, , b], draws[[b]]))
  list(
    eff = eff, eff.boot = eff_boot, colnames.boot = draws, id = S$id,
    rawtime = S$rawtime, D.dat = S$D,
    att.avg = a0$att_avg, att.avg.boot = vapply(ab, `[[`, numeric(1), "att_avg"),
    time = 1:7, att = a0$att, att.boot = vapply(ab, `[[`, numeric(7), "att"),
    att_placebo = a0$att_pl, att_placebo_boot = vapply(ab, `[[`, numeric(1), "att_pl"),
    Ntr = length(focal), Nco = N - length(focal), niter = NA_integer_,
    n_nonconvergence_warnings = NA_integer_, parallel_boot = FALSE, max_iter = NA_integer_,
    elapsed_seconds = proc.time()[["elapsed"]] - t0
  )
}

# ---- Gate 1: reproduce the stored fourteen-case signed row -----------------

stored_row <- readr::read_csv(file.path(stored_dir, "fect_results.csv"),
                              show_col_types = FALSE) |>
  dplyr::filter(spec_id == "fourteen_case", comparison_rule == "clean_controls",
                outcome == "signed_distance_china", treatment_shift == 0, r_mode == "cv")
stored_country <- readr::read_csv(file.path(stored_dir, "fect_country_effects.csv"),
                                  show_col_types = FALSE) |>
  dplyr::filter(spec_id == "fourteen_case", comparison_rule == "clean_controls",
                outcome == "signed_distance_china", treatment_shift == 0, r_mode == "cv")
stopifnot(nrow(stored_row) == 1L, nrow(stored_country) == 14L,
          stored_row$bootstrap_replications == 1000L, stored_row$bootstrap_seed == 42L)

fit_plain <- fit_fect(grouped = FALSE, keep_sims = FALSE, label = "gate: plain fit (cv)")
ev_plain <- event_0_6(fit_plain)
se_plain <- stats::sd(as.numeric(fit_plain$att.avg.boot), na.rm = TRUE)
country_plain <- country_0_6(fit_plain) |>
  dplyr::inner_join(dplyr::select(stored_country, iso3c, stored = att_country_event_0_6),
                    by = "iso3c")
stopifnot(nrow(country_plain) == 14L)

gate1 <- tibble::tibble(
  check = c("att_avg", "att_avg_se", "att_event_0_6", "att_event_0_6_se",
            "selected_r", "country_event_0_6_max_abs_diff"),
  reproduced = c(as.numeric(fit_plain$att.avg), se_plain, ev_plain$att, ev_plain$se,
                 selected_r(fit_plain), NA_real_),
  stored = c(stored_row$estimate, stored_row$se_bootstrap, stored_row$att_event_0_6,
             stored_row$se_event_0_6, stored_row$selected_factors, NA_real_),
  abs_diff = c(abs(as.numeric(fit_plain$att.avg) - stored_row$estimate),
               abs(se_plain - stored_row$se_bootstrap),
               abs(ev_plain$att - stored_row$att_event_0_6),
               abs(ev_plain$se - stored_row$se_event_0_6),
               abs(selected_r(fit_plain) - stored_row$selected_factors),
               max(abs(country_plain$att_country_event_0_6 - country_plain$stored))),
  checked = c(TRUE, full_run, TRUE, full_run, TRUE, TRUE)
) |>
  dplyr::mutate(pass = !checked | abs_diff < 1e-8)
# Per-country values are not written (the author has not looked at them yet);
# only the differences.
gate1_country <- dplyr::transmute(
  country_plain, iso3c, abs_diff = abs(att_country_event_0_6 - stored),
  pass = abs_diff < 1e-8
)
message("Gate 1:")
print(as.data.frame(gate1))
message("Gate 1, per-country 0-6 effects: max abs diff ",
        format(max(gate1_country$abs_diff), digits = 3))
stopifnot(all(gate1$pass), all(gate1_country$pass))

# ---- Gate 2: `group` and `keep.sims` leave the fit unchanged ----------------

fit_cv <- fit_fect(label = "cv (group, keep.sims)")
ev_cv <- event_0_6(fit_cv)
compare <- list(
  att_avg = list(fit_plain$att.avg, fit_cv$att.avg),
  att_avg_boot = list(fit_plain$att.avg.boot, fit_cv$att.avg.boot),
  att_avg_se = list(se_plain, stats::sd(as.numeric(fit_cv$att.avg.boot), na.rm = TRUE)),
  att_by_period = list(fit_plain$att, fit_cv$att),
  att_boot = list(fit_plain$att.boot, fit_cv$att.boot),
  est_att_se = list(fit_plain$est.att[, "S.E."], fit_cv$est.att[, "S.E."]),
  est_avg = list(fit_plain$est.avg, fit_cv$est.avg),
  att_event_0_6 = list(ev_plain$att, ev_cv$att),
  att_event_0_6_se = list(ev_plain$se, ev_cv$se),
  eff = list(fit_plain$eff, fit_cv$eff),
  selected_r = list(selected_r(fit_plain), selected_r(fit_cv)),
  n_bootstrap_kept = list(ncol(fit_plain$att.boot), ncol(fit_cv$att.boot))
)
gate2 <- tibble::tibble(
  quantity = names(compare),
  max_abs_diff = vapply(compare, function(x) max_abs_diff(x[[1]], x[[2]]), numeric(1)),
  identical = vapply(compare, function(x) isTRUE(all.equal(
    as.numeric(x[[1]]), as.numeric(x[[2]]), tolerance = 0)), logical(1))
)
message("Gate 2 (plain fit vs group + keep.sims):")
print(as.data.frame(gate2))
stopifnot(all(gate2$max_abs_diff < 1e-12))
rm(fit_plain)

# ---- Gate 3: group taus equal the means of the stored per-country effects ---

est_cv <- window_estimates(fit_cv, 0L, 6L)
stored_mean <- function(g) {
  mean(stored_country$att_country_event_0_6[stored_country$iso3c %in% g])
}
gate3 <- tibble::tibble(
  estimand = c("tau_neg", "tau_pos"),
  from_fit = c(est_cv$point[["tau_neg"]], est_cv$point[["tau_pos"]]),
  from_stored_country_effects = c(stored_mean(groups$neg), stored_mean(groups$pos))
) |>
  dplyr::mutate(abs_diff = abs(from_fit - from_stored_country_effects),
                pass = abs_diff < 1e-10)
message("Gate 3:")
print(as.data.frame(gate3))
stopifnot(all(gate3$pass), selected_r(fit_cv) == 0L)

# ---- Collectors ----------------------------------------------------------------

results <- list()
event_tables <- list()
mag_rows <- list()
fit_rows <- list()
unit_rows <- list()
draw_rows <- list()
check_rows <- list()
engine_rows <- list()
kept <- list()

record <- function(variant, phase, est, window_lo, window_hi, r_used, engine) {
  key <- paste(variant, phase)
  results[[key]] <<- summarise_draws(est$point, est$draws) |>
    dplyr::mutate(variant = variant, phase = phase, engine = engine,
                  window_from = window_lo, window_to = window_hi, r = r_used,
                  .before = 1L)
  mag_rows[[key]] <<- tibble::tibble(variant = variant, phase = phase,
                                     delta_mag_signed = est$mag_point)
  draw_rows[[key]] <<- tibble::as_tibble(est$draws) |>
    dplyr::mutate(variant = variant, phase = phase, replicate = dplyr::row_number(),
                  .before = 1L)
  in_groups <- which(est$info$theta_group %in% c("neg_us", "pos_us"))
  unit_rows[[key]] <<- tibble::tibble(
    variant = variant, phase = phase, iso3c = est$info$iso3c[in_groups],
    theta_group = est$info$theta_group[in_groups], window_from = window_lo,
    window_to = window_hi, unit_effect = est$units[in_groups]
  )
}

record_fit <- function(variant, fit_type, fit, engine, method, r_used, placebo, ev = NULL) {
  fit_rows[[paste(variant, fit_type)]] <<- tibble::tibble(
    variant = variant, fit_type = fit_type, engine = engine, method = method,
    r = r_used, placebo_period = if (is.null(placebo)) NA_character_ else
      paste(placebo, collapse = ".."),
    att_avg = as.numeric(fit$att.avg),
    att_avg_se = stats::sd(as.numeric(fit$att.avg.boot), na.rm = TRUE),
    att_event_0_6 = if (is.null(ev)) NA_real_ else ev$att,
    att_event_0_6_se = if (is.null(ev)) NA_real_ else ev$se,
    att_placebo_all_treated = if (is.null(placebo)) NA_real_ else
      if (engine == "fect") as.numeric(fit$est.placebo[1, 1]) else fit$att_placebo,
    att_placebo_all_treated_se = if (is.null(placebo)) NA_real_ else
      if (engine == "fect") as.numeric(fit$est.placebo[1, 2]) else
        stats::sd(fit$att_placebo_boot),
    n_treated_units = as.integer(fit$Ntr), n_control_units = as.integer(fit$Nco),
    bootstrap_requested = fect_bootstraps, bootstrap_kept = dim(fit$eff.boot)[3],
    parallel_bootstrap = fit$parallel_boot, max_iteration = fit$max_iter,
    full_sample_em_iterations = as.integer((fit$niter %||% NA)[1]),
    nonconvergence_warnings = fit$n_nonconvergence_warnings,
    elapsed_seconds = fit$elapsed_seconds
  )
}

# Paired post - placebo contrast when both fits share the resampled units.
record_break <- function(variant, ph, r_used, engine, same_draws) {
  if (!same_draws) return(invisible(NULL))
  post_d <- draw_rows[[paste(variant, "post")]]
  pl_d <- draw_rows[[paste(variant, ph)]]
  stopifnot(identical(post_d$n_neg, pl_d$n_neg), identical(post_d$n_pos, pl_d$n_pos))
  use <- post_d$n_neg > 0 & post_d$n_pos > 0
  diff_draws <- post_d$delta[use] - pl_d$delta[use]
  est_of <- function(key) {
    x <- results[[key]]
    x$estimate[x$estimand == "delta"]
  }
  diff_point <- est_of(paste(variant, "post")) - est_of(paste(variant, ph))
  results[[paste(variant, ph, "break")]] <<- tibble::tibble(
    variant = variant, phase = paste0("post_minus_", ph), engine = engine,
    window_from = NA_integer_, window_to = NA_integer_, r = r_used,
    estimand = "delta", predicted_sign = 1, estimate = diff_point,
    se_bootstrap = stats::sd(diff_draws),
    ci_95_low_percentile = unname(stats::quantile(diff_draws, 0.025)),
    ci_95_high_percentile = unname(stats::quantile(diff_draws, 0.975)),
    p_one_sided_bootstrap = mean(diff_draws <= 0),
    p_one_sided_normal = stats::pnorm(-diff_point / stats::sd(diff_draws)),
    replicates_total = nrow(post_d), replicates_used = sum(use),
    replicates_empty_neg = sum(post_d$n_neg == 0),
    replicates_empty_pos = sum(post_d$n_pos == 0)
  )
}

point_taus <- function(fit, lo, hi) {
  info <- unit_info_for(fit)
  years <- years_of(fit)
  g <- which(info$theta_group %in% c("neg_us", "pos_us"))
  group_stats(unit_window_means(fit$eff[, g, drop = FALSE], g, info, years, lo, hi),
              info$theta_group[g])
}

# ---- fect variants: cv, r1, r2 ---------------------------------------------------

fect_variants <- list(
  cv = list(r_fixed = NULL, placebo_r = selected_r(fit_cv), parallel = FALSE,
            max_iter = 5000L),
  r1 = list(r_fixed = 1L, placebo_r = 1L, parallel = TRUE, max_iter = IFE_MAX_ITER),
  r2 = list(r_fixed = 2L, placebo_r = 2L, parallel = TRUE, max_iter = IFE_MAX_ITER)
)

for (v in names(fect_variants)) {
  spec <- fect_variants[[v]]
  fit <- if (v == "cv") fit_cv else
    fit_fect(r_fixed = spec$r_fixed, label = v, parallel = spec$parallel,
             max_iter = spec$max_iter)
  if (v == "cv") {
    fit$parallel_boot <- FALSE
    fit$max_iter <- 5000L
  }
  check_boot_ids(fit)
  est <- if (v == "cv") est_cv else window_estimates(fit, 0L, 6L)
  check_group_atts(fit, est)
  ev <- event_0_6(fit)
  r_used <- if (is.null(spec$r_fixed)) selected_r(fit) else spec$r_fixed
  record(v, "post", est, 0L, 6L, r_used, "fect")
  if (v == "cv") kept$est_cv_post <- est
  event_tables[[paste(v, "main")]] <- event_study(fit, seq.int(-16L, 6L)) |>
    dplyr::mutate(variant = v, fit_type = "main", .before = 1L)
  record_fit(v, "main", fit, "fect", "ife", r_used, NULL, ev)
  boot_ids_main <- fit$colnames.boot
  if (v == "cv") kept$cv_main_draws <- boot_ids_main
  rm(fit)
  if (v == "cv") rm(fit_cv)
  gc(verbose = FALSE)

  for (ph in names(placebo_periods)) {
    pp <- placebo_periods[[ph]]
    pfit <- fit_fect(r_fixed = spec$placebo_r, placebo = pp, label = paste(v, ph),
                     parallel = spec$parallel, max_iter = spec$max_iter)
    check_boot_ids(pfit)
    # Calendar window of the placebo: T.on = 0 is cue - 1, so c(a, 0) is
    # cue - 1 + a .. cue - 1.
    lo <- pp[1] - 1L
    hi <- pp[2] - 1L
    pest <- window_estimates(pfit, lo, hi)
    stopifnot(all(c(groups$neg, groups$pos) %in% pest$info$iso3c))
    same_draws <- identical(boot_ids_main, pfit$colnames.boot)
    check_rows[[paste(v, ph)]] <- check_group_placebo(pfit, pest) |>
      dplyr::mutate(variant = v, phase = ph, same_bootstrap_draws_as_main = same_draws,
                    .before = 1L)
    record(v, ph, pest, lo, hi, spec$placebo_r, "fect")
    record_break(v, ph, spec$placebo_r, "fect", same_draws)
    if (v == "cv") {
      kept[[paste0("est_cv_", ph)]] <- pest
      kept[[paste0("cv_", ph, "_draws")]] <- pfit$colnames.boot
    }
    event_tables[[paste(v, ph)]] <- event_study(pfit, seq.int(-16L, 6L)) |>
      dplyr::mutate(variant = v, fit_type = ph, .before = 1L)
    record_fit(v, ph, pfit, "fect", "ife", spec$placebo_r, pp)
    if (v == "cv" && ph == "placebo_c4") {
      # Template for the direct engine: fect's matrices in fect's unit order.
      S <- list(Y = pfit$Y.dat, D = pfit$D.dat, years = years_of(pfit),
                info = unit_info_for(pfit), id = pfit$id, rawtime = pfit$rawtime)
      stopifnot(!anyNA(S$Y), all(pfit$I.dat == 1))
    }
    rm(pfit)
    gc(verbose = FALSE)
  }
}

# EM cap sensitivity of the r >= 1 placebo points (no bootstrap).
for (r_fix in c(1L, 2L)) for (ph in names(placebo_periods)) for (cap in c(5000L, 50000L)) {
  pp <- placebo_periods[[ph]]
  f <- fit_fect(r_fixed = r_fix, placebo = pp, se = FALSE, keep_sims = FALSE,
                max_iter = cap, label = paste0("cap check r", r_fix, " ", ph, " cap ", cap))
  t <- point_taus(f, pp[1] - 1L, pp[2] - 1L)
  engine_rows[[paste("cap", r_fix, ph, cap)]] <- tibble::tibble(
    check = "ife_placebo_em_cap", variant = paste0("r", r_fix), phase = ph,
    detail = paste0("max.iteration = ", cap, "; EM iterations ", f$niter[1]),
    tau_neg = t[["tau_neg"]], tau_pos = t[["tau_pos"]], delta = t[["delta"]],
    max_abs_diff = NA_real_, pass = NA
  )
  rm(f)
}

# ---- cfe_trend: direct least squares with fect's sequential draws ---------------

# Draws of fect's sequential bootstrap with seed 42 and no cross-validation (the
# cv placebo fits); both placebo fits must share them.
seq_draws <- kept$cv_placebo_c4_draws
stopifnot(identical(seq_draws, kept$cv_placebo_c3_draws))

# Check (i): the engine without the trend reproduces fect's r = 0 fits, point and
# every replicate, main (cv draws) and both placebos.
validate_fe_only <- function(label, draws, placebo, lo, hi, est_fect) {
  lf <- ls_fit(S, draws, placebo = placebo, trend = FALSE, label = label)
  le <- window_estimates(lf, lo, hi)
  d_point <- max(abs(le$point - est_fect$point))
  d_draws <- max(abs(le$draws - est_fect$draws), na.rm = TRUE)
  stopifnot(identical(is.na(le$draws), is.na(est_fect$draws)))
  tibble::tibble(check = "direct_engine_fe_only_vs_fect_r0", variant = "cv",
                 phase = label, detail = "max abs diff over tau_neg, tau_pos, Delta; point and all replicates",
                 tau_neg = NA_real_, tau_pos = NA_real_, delta = NA_real_,
                 max_abs_diff = max(d_point, d_draws), pass = max(d_point, d_draws) < 1e-6)
}
engine_rows[["fe_only post"]] <- validate_fe_only("post", kept$cv_main_draws, NULL,
                                                  0L, 6L, kept$est_cv_post)
for (ph in names(placebo_periods)) {
  pp <- placebo_periods[[ph]]
  engine_rows[[paste("fe_only", ph)]] <- validate_fe_only(
    ph, seq_draws, pp, pp[1] - 1L, pp[2] - 1L, kept[[paste0("est_cv_", ph)]]
  )
}
message("Direct engine, FE-only checks:")
print(as.data.frame(dplyr::bind_rows(engine_rows[grepl("^fe_only", names(engine_rows))])))
stopifnot(all(dplyr::bind_rows(engine_rows[grepl("^fe_only", names(engine_rows))])$pass))

cfe_fits <- list(post = NULL)
for (ph in c("post", names(placebo_periods))) {
  pp <- if (ph == "post") NULL else placebo_periods[[ph]]
  lo <- if (ph == "post") 0L else pp[1] - 1L
  hi <- if (ph == "post") 6L else pp[2] - 1L
  lf <- ls_fit(S, seq_draws, placebo = pp, trend = TRUE, label = paste("cfe_trend", ph))
  le <- window_estimates(lf, lo, hi)
  record("cfe_trend", ph, le, lo, hi, 0L, "direct_ls")
  if (ph != "post") record_break("cfe_trend", ph, 0L, "direct_ls", TRUE)
  event_tables[[paste("cfe_trend", ph)]] <- event_study(lf, seq.int(-16L, 6L)) |>
    dplyr::mutate(variant = "cfe_trend", fit_type = if (ph == "post") "main" else ph,
                  .before = 1L)
  record_fit("cfe_trend", if (ph == "post") "main" else ph, lf, "direct_ls", "cfe", 0L,
             pp, if (ph == "post") event_0_6(lf) else NULL)
  cfe_fits[[ph]] <- le$point

  # Check (ii): fect cfe with a centred year, run to convergence, gives the same
  # points; and the as-specified fect cfe (Q.type = "linear", defaults) for the
  # record.
  f_tight <- fit_fect(r_fixed = 0L, method = "cfe", q = "year_centered", placebo = pp,
                      se = FALSE, keep_sims = FALSE, tol = 1e-9, max_iter = 1000000L,
                      label = paste("cfe centred year, tol 1e-9,", ph))
  t_tight <- point_taus(f_tight, lo, hi)
  engine_rows[[paste("cfe tight", ph)]] <- tibble::tibble(
    check = "direct_engine_vs_fect_cfe_centred_tol1e-9", variant = "cfe_trend",
    phase = ph, detail = paste0("fect EM iterations ", f_tight$niter[1]),
    tau_neg = t_tight[["tau_neg"]], tau_pos = t_tight[["tau_pos"]],
    delta = t_tight[["delta"]], max_abs_diff = max(abs(t_tight - le$point)),
    pass = max(abs(t_tight - le$point)) < 1e-4
  )
  rm(f_tight)
  f_spec <- fit_fect(r_fixed = 0L, method = "cfe", q_type = "linear", placebo = pp,
                     se = FALSE, keep_sims = FALSE,
                     label = paste("cfe as specified (Q.type linear, defaults),", ph))
  t_spec <- point_taus(f_spec, lo, hi)
  engine_rows[[paste("cfe spec", ph)]] <- tibble::tibble(
    check = "fect_cfe_as_specified_unconverged", variant = "cfe_trend", phase = ph,
    detail = paste0("Q.type = linear, max.iteration 5000; EM iterations ",
                    f_spec$niter[1], "; non-convergence warnings ",
                    f_spec$n_nonconvergence_warnings),
    tau_neg = t_spec[["tau_neg"]], tau_pos = t_spec[["tau_pos"]],
    delta = t_spec[["delta"]], max_abs_diff = max(abs(t_spec - le$point)), pass = NA
  )
  rm(f_spec, lf)
  gc(verbose = FALSE)
}

# Check (iii): a fect cfe bootstrap draws the same units (first 20 replicates).
n_check <- min(20L, fect_bootstraps)
f_draws <- fit_fect(r_fixed = 0L, method = "cfe", q_type = "linear", nboots = n_check,
                    label = "cfe as specified, bootstrap draws check")
same_units <- identical(f_draws$colnames.boot, seq_draws[seq_len(n_check)])
engine_rows[["cfe draws"]] <- tibble::tibble(
  check = "fect_cfe_bootstrap_draws_equal_direct_engine_draws", variant = "cfe_trend",
  phase = "post", detail = paste0("first ", n_check, " replicates"),
  tau_neg = NA_real_, tau_pos = NA_real_, delta = NA_real_,
  max_abs_diff = NA_real_, pass = same_units
)
rm(f_draws)
engine_checks <- dplyr::bind_rows(engine_rows)
message("Engine checks:")
print(as.data.frame(engine_checks))
stopifnot(all(engine_checks$pass[!is.na(engine_checks$pass)]))

# ---- Outputs -----------------------------------------------------------------

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
group_estimates <- dplyr::bind_rows(results)
readr::write_csv(gate1, file.path(output_dir, "gate1_reproduction.csv"))
readr::write_csv(gate1_country, file.path(output_dir, "gate1_country_diffs.csv"))
readr::write_csv(gate2, file.path(output_dir, "gate2_group_keep_sims_identity.csv"))
readr::write_csv(gate3, file.path(output_dir, "gate3_group_tau_vs_stored.csv"))
readr::write_csv(dplyr::bind_rows(check_rows),
                 file.path(output_dir, "check_group_placebo_vs_fect.csv"))
readr::write_csv(engine_checks, file.path(output_dir, "engine_checks.csv"))
readr::write_csv(group_estimates, file.path(output_dir, "group_estimates.csv"))
readr::write_csv(dplyr::bind_rows(mag_rows), file.path(output_dir, "delta_mag_signed.csv"))
readr::write_csv(dplyr::bind_rows(event_tables),
                 file.path(output_dir, "delta_event_study.csv"))
readr::write_csv(dplyr::bind_rows(fit_rows), file.path(output_dir, "fit_summary.csv"))
# Per-country effects (inputs to later sensitivities); not printed.
readr::write_csv(dplyr::bind_rows(unit_rows), file.path(output_dir, "country_effects.csv"))
readr::write_csv(dplyr::bind_rows(draw_rows), file.path(output_dir, "bootstrap_draws.csv"))
writeLines(capture.output(sessionInfo()), file.path(output_dir, "session_info.txt"))

print(as.data.frame(dplyr::select(
  group_estimates, variant, phase, estimand, estimate, se_bootstrap,
  ci_95_low_percentile, ci_95_high_percentile, p_one_sided_bootstrap,
  replicates_used, replicates_empty_neg, replicates_empty_pos
)))
print(as.data.frame(dplyr::bind_rows(mag_rows)))
print(as.data.frame(dplyr::bind_rows(fit_rows)))
