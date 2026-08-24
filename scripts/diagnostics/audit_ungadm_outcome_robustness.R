#!/usr/bin/env Rscript

# Pre-committed measurement-robustness check: re-estimate the two main paper
# specifications with the outcome built from UNGA-DM ideal points (Fjelstul,
# Hug & Kilby 2026) instead of BSV Jun/2024.
#   (1) Brazil SDiD `predetermined_core` (1997-2015): same panel, donor pool,
#       covariate arrays, synthdid parametrization; 1,000-replication placebo
#       SE and placebo-in-space ranks, exactly mirroring
#       scripts/diagnostics/audit_brazil_sdid_predetermined_commodity_controls.R.
#   (2) Cross-country IFE, 5-year restricted risk set: common-window
#       apples-to-apples (UNGA-DM vs BSV on the identical row set, year <= 2020),
#       nboots = 10,000, same run_fect_analysis settings (seed 42).
# Also extracts the existing m2 pre-trend F-test targets and attempts the fect
# equivalence plot (plan Pacote D).
# Decision rule (fixed before estimation): results are reported regardless of
# outcome. Plan: quality_reports/plans/2026-08-23_ungadm_robustness_check.md.
# Reads existing targets; never runs targets.

suppressPackageStartupMessages({
  library(targets)
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(tibble)
  library(janitor)
  library(synthdid)
  library(fect)
  library(ggplot2)
})

options(scipen = 999)

run_started <- Sys.time()
run_date <- as.character(Sys.Date())
audit_code_version <- "2026-08-23-v1-ungadm-outcome"
target_store <- "_targets"

bsv_path <- file.path(
  "raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv"
)
ungadm_path <- file.path(
  "raw data", "unga_dm", "unga_dm_ideal_points_all_resolution_votes_s75.csv"
)
paper_sdid_dir <- file.path(
  "data", "processed", "diagnostics", "paper_v4_brazil_sdid_predetermined_core"
)
out_dir <- file.path(
  "data", "processed", "diagnostics", "ungadm_outcome_robustness", "estimation"
)
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- function(filename) file.path(out_dir, filename)

placebo_replications <- as.integer(Sys.getenv("UNGADM_PLACEBO_REPS", "1000"))
placebo_seed <- 20260823L
ife_nboots <- as.integer(Sys.getenv("UNGADM_IFE_NBOOTS", "10000"))
if (placebo_replications < 1000L || ife_nboots < 10000L) {
  message("NOTE: smoke-test replication counts in use (reps = ",
          placebo_replications, ", nboots = ", ife_nboots,
          "); final outputs require the defaults.")
}
parallel_cores <- as.integer(Sys.getenv(
  "SDID_PARALLEL_CORES",
  as.character(min(12L, parallel::detectCores(logical = FALSE)))
))
if (is.na(parallel_cores) || parallel_cores < 1L) parallel_cores <- 1L
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1"
)

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) stop("Could not read target `", name, "`: ",
                             conditionMessage(e), call. = FALSE)
  )
}

message("Sourcing scripts/functions.R for the fect machinery.")
source(file.path("scripts", "functions.R"))

# ---------------------------------------------------------------------------
# Step 1 - UNGA-DM outcome mapped to iso3c-year
# Country mapping inherits the pipeline's own convention by joining UNGA-DM to
# BSV on (ccode, session). Known convention difference fixed explicitly:
# session 45 (1990) Germany is ccode 255 in UNGA-DM and 260/DEU in BSV.
# Distances mirror get_unga_data(): per-session anchors from the source's own
# China (ccode 710) and US (ccode 2) positions; year = session + 1945.
# ---------------------------------------------------------------------------

message("Building the UNGA-DM outcome series.")
bsv_raw <- read_csv(bsv_path, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(ccode = as.integer(ccode), session = as.integer(session), iso3c)

ungadm_raw <- read_csv(ungadm_path, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(
    ccode = as.integer(ccode),
    session = as.integer(session),
    country_ungadm = country,
    q50_dm = x50
  ) %>%
  mutate(ccode = if_else(session == 45L & ccode == 255L, 260L, ccode))

dm_mapped <- ungadm_raw %>%
  left_join(bsv_raw, by = c("ccode", "session"))
unmatched_dm <- dm_mapped %>% filter(is.na(iso3c))
write_csv(
  unmatched_dm %>% select(ccode, session, country_ungadm),
  out_path("dm_rows_without_iso3c_mapping.csv")
)
message("  UNGA-DM rows without iso3c mapping (excluded): ", nrow(unmatched_dm))

dm_outcome <- dm_mapped %>%
  filter(!is.na(iso3c)) %>%
  group_by(session) %>%
  mutate(
    china_ideal_dm = q50_dm[ccode == 710L][1],
    us_ideal_dm = q50_dm[ccode == 2L][1]
  ) %>%
  ungroup() %>%
  mutate(
    year = session + 1945L,
    abs_distance_china_dm = abs(q50_dm - china_ideal_dm),
    abs_distance_usa_dm = abs(q50_dm - us_ideal_dm)
  ) %>%
  # All analysis windows start in 1990; pre-1990 rows carry a BSV iso3c quirk
  # (both Yemens coded YAR in sessions 22-44) that would break uniqueness.
  filter(year >= 1990L) %>%
  select(iso3c, year, abs_distance_china_dm, abs_distance_usa_dm)
stopifnot(!any(duplicated(dm_outcome[, c("iso3c", "year")])))

# ---------------------------------------------------------------------------
# SDiD machinery ported unchanged from
# audit_brazil_sdid_predetermined_commodity_controls.R (fit, covariate array,
# summary, exact parallel placebo SE with checkpointing, rank placebos).
# ---------------------------------------------------------------------------

make_covariate_array <- function(data, covariate_cols) {
  unit_levels <- unique(data$iso3c)
  time_levels <- sort(unique(data$year))
  out <- array(
    NA_real_,
    dim = c(length(unit_levels), length(time_levels), length(covariate_cols)),
    dimnames = list(unit_levels, as.character(time_levels), covariate_cols)
  )
  for (k in seq_along(covariate_cols)) {
    covariate <- covariate_cols[[k]]
    wide <- data |>
      dplyr::select(iso3c, year, value = dplyr::all_of(covariate)) |>
      dplyr::mutate(
        iso3c = factor(iso3c, levels = unit_levels),
        year = factor(year, levels = time_levels)
      ) |>
      dplyr::arrange(iso3c, year) |>
      tidyr::pivot_wider(id_cols = iso3c, names_from = year, values_from = value) |>
      dplyr::arrange(iso3c)
    out[, , k] <- wide |>
      dplyr::select(dplyr::all_of(as.character(time_levels))) |>
      as.matrix()
  }
  if (anyNA(out)) stop("Covariate array contains missing values.", call. = FALSE)
  out
}

fit_sdid <- function(data, covariate_cols, treated_iso3c = "BRA", year_end = 2015L) {
  fit_data <- data |>
    dplyr::filter(year >= 1997L, year <= year_end) |>
    dplyr::mutate(
      treatment = as.integer(iso3c == treated_iso3c & year >= 2009L),
      .unit_treated = as.integer(iso3c == treated_iso3c)
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)
  required <- c("iso3c", "year", "abs_distance_china", "treatment", covariate_cols)
  if (anyNA(fit_data |> dplyr::select(dplyr::all_of(required)))) {
    stop("Missing values in fit for treated unit ", treated_iso3c, call. = FALSE)
  }
  counts <- fit_data |>
    dplyr::count(iso3c, name = "n_years")
  if (dplyr::n_distinct(counts$n_years) != 1L) stop("Unbalanced SDiD panel.", call. = FALSE)
  x_array <- make_covariate_array(fit_data, covariate_cols)
  panel_data <- fit_data |>
    dplyr::mutate(
      iso3c = factor(iso3c, levels = unique(iso3c)),
      year = as.integer(year),
      Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0, X = x_array)
}

extract_fit_summary <- function(fit, specification, se_value = NA_real_) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  omega <- as.numeric(weights$omega)
  controls <- setup$Y[seq_len(setup$N0), , drop = FALSE]
  treated <- as.numeric(setup$Y[setup$N0 + 1L, ])
  synthetic <- as.numeric(t(omega) %*% controls)
  gap <- treated - synthetic
  pre_gap <- gap[seq_len(setup$T0)]
  centered_gap <- gap - mean(pre_gap, na.rm = TRUE)
  rmspe_pre <- sqrt(mean(centered_gap[seq_len(setup$T0)]^2, na.rm = TRUE))
  rmspe_post <- sqrt(mean(
    centered_gap[(setup$T0 + 1L):ncol(setup$Y)]^2, na.rm = TRUE
  ))
  estimate <- as.numeric(fit)
  p_value <- ifelse(is.na(se_value) || se_value <= 0, NA_real_,
                    2 * stats::pnorm(-abs(estimate / se_value)))
  tibble::tibble(
    specification = specification,
    estimate = estimate,
    se_placebo = se_value,
    ci_95_low = estimate - stats::qnorm(0.975) * se_value,
    ci_95_high = estimate + stats::qnorm(0.975) * se_value,
    p_value_two_sided = p_value,
    n_countries = nrow(setup$Y),
    n_treated_units = 1L,
    n_donors = setup$N0,
    n_pre_years = setup$T0,
    n_post_years = ncol(setup$Y) - setup$T0,
    rmspe_pre_intercept_adjusted = rmspe_pre,
    rmspe_post_intercept_adjusted = rmspe_post
  )
}

fit_fingerprint <- function(fit, specification, replications, seed) {
  digest::digest(
    list(
      code_version = audit_code_version,
      synthdid_version = as.character(utils::packageVersion("synthdid")),
      specification = specification,
      replications = replications,
      seed = seed,
      estimate = as.numeric(fit),
      setup = attr(fit, "setup"),
      opts = attr(fit, "opts"),
      weights = attr(fit, "weights")
    ),
    algo = "sha256",
    serialize = TRUE
  )
}

placebo_se_parallel <- function(fit, replications, seed, specification) {
  checkpoint_path <- file.path(
    checkpoint_dir,
    paste0("placebo_se_", specification, "_", replications, ".rds")
  )
  fingerprint <- fit_fingerprint(fit, specification, replications, seed)
  estimates <- rep(NA_real_, replications)
  if (file.exists(checkpoint_path)) {
    cached <- readRDS(checkpoint_path)
    cache_valid <- identical(cached$replications, replications) &&
      identical(cached$seed, seed) &&
      identical(cached$fingerprint, fingerprint) &&
      length(cached$estimates) == replications
    if (cache_valid) {
      estimates <- cached$estimates
      if (all(is.finite(estimates))) {
        recalculated_se <- sqrt((replications - 1) / replications) *
          stats::sd(estimates)
        message("    Reusing completed checkpoint: ", basename(checkpoint_path))
        return(recalculated_se)
      }
      message(
        "    Resuming checkpoint with ", sum(is.finite(estimates)), "/",
        replications, " placebo estimates."
      )
    }
  }
  setup <- attr(fit, "setup")
  opts <- attr(fit, "opts")
  fit_weights <- attr(fit, "weights")
  n_treated <- nrow(setup$Y) - setup$N0
  if (setup$N0 <= n_treated) {
    stop("Placebo SE requires more control than treated units.", call. = FALSE)
  }
  set.seed(seed)
  draws <- replicate(replications, sample(seq_len(setup$N0)))
  theta <- function(j) {
    ind <- draws[, j]
    n_control <- length(ind) - n_treated
    bootstrap_weights <- fit_weights
    bootstrap_weights$omega <- synthdid:::sum_normalize(
      fit_weights$omega[ind[seq_len(n_control)]]
    )
    as.numeric(do.call(
      synthdid::synthdid_estimate,
      c(
        list(
          Y = setup$Y[ind, , drop = FALSE],
          N0 = n_control,
          T0 = setup$T0,
          X = setup$X[ind, , , drop = FALSE],
          weights = bootstrap_weights
        ),
        opts
      )
    ))
  }
  missing_indices <- which(!is.finite(estimates))
  batches <- split(missing_indices, ceiling(seq_along(missing_indices) / 120L))
  for (batch_number in seq_along(batches)) {
    batch <- batches[[batch_number]]
    message(
      "    Exact placebo batch ", batch_number, "/", length(batches),
      " (", length(batch), " re-estimations; ", parallel_cores, " cores)."
    )
    estimates[batch] <- unlist(parallel::mclapply(
      batch, theta,
      mc.cores = parallel_cores, mc.preschedule = TRUE, mc.set.seed = FALSE
    ))
    partial_se <- if (all(is.finite(estimates))) {
      sqrt((replications - 1) / replications) * stats::sd(estimates)
    } else {
      NA_real_
    }
    saveRDS(
      list(
        specification = specification,
        replications = replications,
        seed = seed,
        fingerprint = fingerprint,
        se = partial_se,
        estimates = estimates,
        parallel_cores = parallel_cores,
        completed_at = if (all(is.finite(estimates))) {
          format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
        } else {
          NA_character_
        }
      ),
      checkpoint_path
    )
  }
  if (length(estimates) != replications || any(!is.finite(estimates))) {
    stop("Invalid placebo estimates for ", specification, ".", call. = FALSE)
  }
  sqrt((replications - 1) / replications) * stats::sd(estimates)
}

run_rank_placebos <- function(data, covariate_cols, specification, year_end = 2015L) {
  units <- sort(unique(data$iso3c))
  rank_fingerprint <- digest::digest(
    list(
      code_version = audit_code_version,
      synthdid_version = as.character(utils::packageVersion("synthdid")),
      specification = specification,
      year_end = year_end,
      covariate_cols = covariate_cols,
      data = data |>
        dplyr::filter(year >= 1997L, year <= year_end) |>
        dplyr::arrange(iso3c, year) |>
        dplyr::select(
          iso3c, year, abs_distance_china,
          dplyr::all_of(covariate_cols)
        )
    ),
    algo = "sha256",
    serialize = TRUE
  )
  checkpoint_path <- file.path(
    checkpoint_dir,
    paste0("rank_placebos_", specification, "_end_", year_end, ".rds")
  )
  if (file.exists(checkpoint_path)) {
    cached <- readRDS(checkpoint_path)
    if (
      identical(cached$units, units) &&
      identical(cached$fingerprint, rank_fingerprint)
    ) {
      message("    Reusing rank-placebo checkpoint: ", basename(checkpoint_path))
      return(cached$result)
    }
  }
  distribution <- dplyr::bind_rows(parallel::mclapply(units, function(unit) {
    fit <- tryCatch(
      fit_sdid(data, covariate_cols, treated_iso3c = unit, year_end = year_end),
      error = function(e) e
    )
    if (inherits(fit, "error")) {
      return(tibble::tibble(
        specification = specification, year_end = year_end, iso3c = unit,
        estimate = NA_real_, rmspe_pre = NA_real_, status = "error",
        error = conditionMessage(fit)
      ))
    }
    summary <- extract_fit_summary(fit, specification)
    tibble::tibble(
      specification = specification, year_end = year_end, iso3c = unit,
      estimate = summary$estimate,
      rmspe_pre = summary$rmspe_pre_intercept_adjusted,
      status = "estimated", error = ""
    )
  }, mc.cores = parallel_cores, mc.preschedule = TRUE, mc.set.seed = FALSE))
  result <- list(distribution = distribution)
  saveRDS(
    list(
      units = units,
      fingerprint = rank_fingerprint,
      result = result,
      completed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    ),
    checkpoint_path
  )
  result
}

rank_inference_from_distribution <- function(distribution, comparison_set,
                                             keep_units = NULL) {
  valid <- distribution |>
    dplyr::filter(status == "estimated", !is.na(estimate))
  if (!is.null(keep_units)) {
    valid <- valid |> dplyr::filter(iso3c %in% keep_units)
  }
  brazil <- valid |> dplyr::filter(iso3c == "BRA")
  if (nrow(brazil) != 1L) {
    stop("Brazil missing from rank distribution for ", comparison_set, call. = FALSE)
  }
  tibble::tibble(
    comparison_set = comparison_set,
    rank_one_sided_negative = sum(valid$estimate <= brazil$estimate),
    rank_two_sided_absolute = sum(abs(valid$estimate) >= abs(brazil$estimate)),
    denominator = nrow(valid),
    p_rank_one_sided_negative = mean(valid$estimate <= brazil$estimate),
    p_rank_two_sided_absolute = mean(abs(valid$estimate) >= abs(brazil$estimate))
  )
}

# ---------------------------------------------------------------------------
# Step 2 - Brazil SDiD predetermined core: BSV reproduction gate + DM variant
# ---------------------------------------------------------------------------

message("Reading SDiD targets and freezing predetermined-core covariates.")
synth_data <- safe_tar_read("synth_data")
synth_fit_core_target <- safe_tar_read("synth_fit_no_time_varying_covariates")
se_synth_core_target <- safe_tar_read("se_synth_no_time_varying_covariates")

pre_years <- 2004:2008
frozen_means <- synth_data |>
  dplyr::filter(year %in% pre_years) |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    frozen_perc_trade_with_china = mean(perc_trade_with_china, na.rm = TRUE),
    frozen_perc_trade_with_us = mean(perc_trade_with_us, na.rm = TRUE),
    frozen_pci_cur = mean(pci_cur, na.rm = TRUE),
    frozen_distance_us = dplyr::first(distance_us),
    frozen_inst_parliamentary = dplyr::first(inst_parliamentary[year == 2008L]),
    frozen_us_trade_agreement = dplyr::first(us_trade_agreement[year == 2008L]),
    .groups = "drop"
  )
predetermined_core <- c(
  "frozen_perc_trade_with_china", "frozen_perc_trade_with_us",
  "frozen_pci_cur", "frozen_distance_us", "frozen_inst_parliamentary",
  "frozen_us_trade_agreement"
)
estimation_data_bsv <- synth_data |>
  dplyr::left_join(frozen_means, by = "iso3c")

message("Gate: reproducing the audited BSV predetermined-core fit locally.")
fit_bsv <- fit_sdid(estimation_data_bsv, predetermined_core)
gate_fit_equal <- isTRUE(all.equal(
  as.numeric(fit_bsv), as.numeric(synth_fit_core_target), tolerance = 1e-8
))
message("  Local BSV estimate = ", format(as.numeric(fit_bsv), digits = 8),
        "; target = ", format(as.numeric(synth_fit_core_target), digits = 8),
        "; equal = ", gate_fit_equal)
if (!gate_fit_equal) {
  stop("BSV reproduction gate failed; DM variant would not be comparable.",
       call. = FALSE)
}

message("Swapping in the UNGA-DM outcome for the identical 96-country panel.")
estimation_data_dm <- estimation_data_bsv |>
  dplyr::left_join(dm_outcome |> dplyr::select(iso3c, year, abs_distance_china_dm),
                   by = c("iso3c", "year")) |>
  dplyr::mutate(abs_distance_china = abs_distance_china_dm) |>
  dplyr::select(-abs_distance_china_dm)
dm_missing <- estimation_data_dm |>
  dplyr::filter(year >= 1997L, year <= 2015L, is.na(abs_distance_china))
write_csv(
  dm_missing |> dplyr::select(iso3c, year),
  out_path("sdid_dm_missing_outcome_rows.csv")
)
if (nrow(dm_missing) > 0L) {
  stop("UNGA-DM outcome missing for ", nrow(dm_missing),
       " SDiD panel rows; donor pool would change. Inspect ",
       out_path("sdid_dm_missing_outcome_rows.csv"), call. = FALSE)
}

message("Fitting the UNGA-DM predetermined-core SDiD.")
fit_dm <- fit_sdid(estimation_data_dm, predetermined_core)
message("  UNGA-DM estimate = ", format(as.numeric(fit_dm), digits = 8))

message("Placebo SE for the UNGA-DM variant (", placebo_replications,
        " replications, seed ", placebo_seed, ").")
se_dm <- placebo_se_parallel(
  fit_dm, placebo_replications, placebo_seed, "ungadm_predetermined_core"
)

message("Rank placebos for the UNGA-DM variant.")
rank_obj_dm <- run_rank_placebos(
  estimation_data_dm, predetermined_core, "ungadm_predetermined_core"
)
dm_distribution <- rank_obj_dm$distribution
write_csv(dm_distribution, out_path("sdid_dm_placebo_distribution.csv"))

brazil_rmspe_dm <- dm_distribution |>
  dplyr::filter(iso3c == "BRA") |>
  dplyr::pull(rmspe_pre)
fit_filter_units <- dm_distribution |>
  dplyr::filter(status == "estimated", rmspe_pre <= 2 * brazil_rmspe_dm) |>
  dplyr::pull(iso3c)

m2_unit_summary <- safe_tar_read("china_top_m2_goods_status_current_unit_summary")
china_top_units <- m2_unit_summary |>
  dplyr::filter(
    min_duration_years == 5L, sample == "risk_set_restricted",
    ever_treated %in% TRUE
  ) |>
  dplyr::pull(iso3c) |>
  unique()
non_china_top_units <- setdiff(unique(dm_distribution$iso3c), setdiff(china_top_units, "BRA"))

dm_rank_inference <- dplyr::bind_rows(
  rank_inference_from_distribution(dm_distribution, "All valid assignments"),
  rank_inference_from_distribution(
    dm_distribution, "Exclude goods-only China-top donor assignments",
    keep_units = non_china_top_units
  ),
  rank_inference_from_distribution(
    dm_distribution, "Pre-fit RMSPE no larger than twice Brazil",
    keep_units = fit_filter_units
  )
)
write_csv(dm_rank_inference, out_path("sdid_dm_rank_inference.csv"))

dm_all_rank <- dm_rank_inference |> dplyr::slice(1)
brazil_pre_mean_dm <- estimation_data_dm |>
  dplyr::filter(iso3c == "BRA", year >= 1997L, year <= 2008L) |>
  dplyr::summarise(m = mean(abs_distance_china)) |>
  dplyr::pull(m)
brazil_pre_mean_bsv <- estimation_data_bsv |>
  dplyr::filter(iso3c == "BRA", year >= 1997L, year <= 2008L) |>
  dplyr::summarise(m = mean(abs_distance_china)) |>
  dplyr::pull(m)

dm_summary <- extract_fit_summary(fit_dm, "ungadm_predetermined_core", se_dm) |>
  dplyr::mutate(
    rank_one_sided_negative = dm_all_rank$rank_one_sided_negative,
    rank_two_sided_absolute = dm_all_rank$rank_two_sided_absolute,
    rank_denominator = dm_all_rank$denominator,
    p_rank_one_sided_negative = dm_all_rank$p_rank_one_sided_negative,
    p_rank_two_sided_absolute = dm_all_rank$p_rank_two_sided_absolute,
    brazil_pre_treatment_mean = brazil_pre_mean_dm,
    estimate_as_percent_of_pre_mean = 100 * estimate / brazil_pre_treatment_mean,
    se_replications = placebo_replications,
    se_seed = placebo_seed,
    source = "Locally estimated with the exact parallel synthdid placebo algorithm; UNGA-DM outcome."
  )
write_csv(dm_summary, out_path("sdid_dm_main_summary.csv"))

dm_weights <- attr(fit_dm, "weights")
dm_setup <- attr(fit_dm, "setup")
dm_unit_weights <- tibble::tibble(
  iso3c = rownames(dm_setup$Y)[seq_len(dm_setup$N0)],
  unit_weight = as.numeric(dm_weights$omega)
) |>
  dplyr::arrange(dplyr::desc(unit_weight))
write_csv(dm_unit_weights, out_path("sdid_dm_unit_weights.csv"))
bsv_weights <- attr(fit_bsv, "weights")
bsv_setup <- attr(fit_bsv, "setup")
bsv_unit_weights <- tibble::tibble(
  iso3c = rownames(bsv_setup$Y)[seq_len(bsv_setup$N0)],
  unit_weight = as.numeric(bsv_weights$omega)
) |>
  dplyr::arrange(dplyr::desc(unit_weight))
weight_overlap <- dm_unit_weights |>
  dplyr::rename(unit_weight_dm = unit_weight) |>
  dplyr::full_join(
    bsv_unit_weights |> dplyr::rename(unit_weight_bsv = unit_weight),
    by = "iso3c"
  )
write_csv(weight_overlap, out_path("sdid_unit_weights_bsv_vs_dm.csv"))

bsv_main_audited <- read_csv(
  file.path(paper_sdid_dir, "main_summary.csv"), show_col_types = FALSE
) |>
  dplyr::slice_head(n = 1)
sdid_comparison <- dplyr::bind_rows(
  tibble::tibble(
    outcome_source = "BSV Jun/2024 (paper main, audited checkpoint)",
    estimate = bsv_main_audited$estimate,
    se_placebo = bsv_main_audited$se_placebo,
    ci_95_low = bsv_main_audited$ci_95_low,
    ci_95_high = bsv_main_audited$ci_95_high,
    p_normal_two_sided = bsv_main_audited$p_normal_two_sided,
    rank_one_sided = bsv_main_audited$rank_one_sided_negative,
    rank_two_sided = bsv_main_audited$rank_two_sided_absolute,
    rank_denominator = bsv_main_audited$rank_denominator,
    p_rank_one_sided = bsv_main_audited$p_rank_one_sided_negative,
    p_rank_two_sided = bsv_main_audited$p_rank_two_sided_absolute,
    rmspe_pre = bsv_main_audited$rmspe_pre,
    brazil_pre_mean = bsv_main_audited$brazil_pre_treatment_mean,
    estimate_pct_pre_mean = bsv_main_audited$estimate_as_percent_of_pre_mean
  ),
  tibble::tibble(
    outcome_source = "UNGA-DM all resolution-related votes (Fjelstul et al. 2026)",
    estimate = dm_summary$estimate,
    se_placebo = dm_summary$se_placebo,
    ci_95_low = dm_summary$ci_95_low,
    ci_95_high = dm_summary$ci_95_high,
    p_normal_two_sided = dm_summary$p_value_two_sided,
    rank_one_sided = dm_summary$rank_one_sided_negative,
    rank_two_sided = dm_summary$rank_two_sided_absolute,
    rank_denominator = dm_summary$rank_denominator,
    p_rank_one_sided = dm_summary$p_rank_one_sided_negative,
    p_rank_two_sided = dm_summary$p_rank_two_sided_absolute,
    rmspe_pre = dm_summary$rmspe_pre_intercept_adjusted,
    brazil_pre_mean = brazil_pre_mean_dm,
    estimate_pct_pre_mean = dm_summary$estimate_as_percent_of_pre_mean
  )
)
write_csv(sdid_comparison, out_path("sdid_comparison_table.csv"))
message("SDiD comparison written.")
print(as.data.frame(sdid_comparison), row.names = FALSE)

# ---------------------------------------------------------------------------
# Step 3 - Cross-country IFE, 5-year restricted risk set, common window
# Apples-to-apples: both variants estimated on the identical row set
# (year <= 2020 and UNGA-DM outcome observed), same seed and settings.
# ---------------------------------------------------------------------------

message("Preparing the common-window IFE panels.")
panel_bundle <- safe_tar_read("china_top_m2_goods_status_current_panel_bundle")
p5 <- panel_bundle$panels[["5"]]$risk_set_restricted

p5_dm <- p5 |>
  dplyr::left_join(dm_outcome |> dplyr::select(iso3c, year, abs_distance_china_dm),
                   by = c("iso3c", "year"))
dropped_rows <- p5_dm |>
  dplyr::filter(year > 2020L | is.na(abs_distance_china_dm)) |>
  dplyr::count(reason = dplyr::if_else(year > 2020L, "beyond UNGA-DM endpoint (year > 2020)",
                                       "UNGA-DM outcome missing"),
                iso3c) |>
  dplyr::arrange(reason, iso3c)
write_csv(dropped_rows, out_path("ife_common_window_dropped_rows.csv"))

common_rows <- p5_dm |>
  dplyr::filter(year <= 2020L, !is.na(abs_distance_china_dm))
message("  Common-window rows: ", nrow(common_rows), " of ", nrow(p5),
        " (dropped ", nrow(p5) - nrow(common_rows), ").")

panel_dm_common <- common_rows |>
  dplyr::mutate(abs_distance_china = abs_distance_china_dm) |>
  dplyr::select(-abs_distance_china_dm)
panel_bsv_common <- common_rows |>
  dplyr::select(-abs_distance_china_dm)

message("Fitting IFE on the BSV common window (nboots = ", ife_nboots, ").")
fit_ife_bsv_common <- run_fect_analysis(
  panel_bsv_common, method = "ife", nboots = ife_nboots,
  fml = abs_distance_china ~ china_top
)
sum_ife_bsv_common <- summarize_fect_model(fit_ife_bsv_common, panel_bsv_common)

message("Fitting IFE on the UNGA-DM common window (nboots = ", ife_nboots, ").")
fit_ife_dm_common <- run_fect_analysis(
  panel_dm_common, method = "ife", nboots = ife_nboots,
  fml = abs_distance_china ~ china_top
)
sum_ife_dm_common <- summarize_fect_model(fit_ife_dm_common, panel_dm_common)

m2_results <- safe_tar_read("china_top_m2_goods_status_current_model_results")
bsv_full_row <- m2_results |>
  dplyr::filter(min_duration_years == 5L, specification == "risk_set_restricted") |>
  dplyr::slice(1)

ife_row <- function(label, s) {
  tibble::tibble(
    variant = label,
    att = s$att, se = s$se, ci_lo = s$ci_lo, ci_hi = s$ci_hi, p = s$p,
    r_cv = s$r_cv,
    att_rel_pct = s$att_rel_pct, att_sd_units = s$att_sd_units,
    n_obs = s$n_obs, n_countries = s$n_countries,
    n_treated = s$n_treated, n_control = s$n_control,
    panel_min = s$panel_min, panel_max = s$panel_max,
    nboots = ife_nboots
  )
}
ife_comparison <- dplyr::bind_rows(
  tibble::tibble(
    variant = "BSV full window 1990-2022 (paper main, stored target)",
    att = bsv_full_row$att, se = bsv_full_row$se,
    ci_lo = bsv_full_row$ci_lo, ci_hi = bsv_full_row$ci_hi,
    p = bsv_full_row$p, r_cv = bsv_full_row$r_cv,
    att_rel_pct = bsv_full_row$att_rel_pct,
    att_sd_units = bsv_full_row$att_sd_units,
    n_obs = bsv_full_row$n_obs, n_countries = bsv_full_row$n_countries,
    n_treated = bsv_full_row$n_treated, n_control = bsv_full_row$n_control,
    panel_min = bsv_full_row$panel_min, panel_max = bsv_full_row$panel_max,
    nboots = bsv_full_row$nboots
  ),
  ife_row("BSV common window (<= 2020, identical rows)", sum_ife_bsv_common),
  ife_row("UNGA-DM common window (<= 2020, identical rows)", sum_ife_dm_common)
)
write_csv(ife_comparison, out_path("ife_comparison_table.csv"))
message("IFE comparison written.")
print(as.data.frame(ife_comparison), row.names = FALSE)

dynamic_tbl <- function(fit, label) {
  tibble::tibble(
    variant = label,
    event_time = fit$time,
    count = fit$count,
    att = as.numeric(fit$est.att[, 1]),
    se = as.numeric(fit$est.att[, 2])
  ) |>
    dplyr::mutate(ci_lo = att - 1.96 * se, ci_hi = att + 1.96 * se)
}
write_csv(
  dplyr::bind_rows(
    dynamic_tbl(fit_ife_bsv_common, "BSV common window"),
    dynamic_tbl(fit_ife_dm_common, "UNGA-DM common window")
  ),
  out_path("ife_common_window_dynamic.csv")
)

# ---------------------------------------------------------------------------
# Step 4 - Pacote D: existing m2 pre-trend F test + fect equivalence plot
# ---------------------------------------------------------------------------

message("Extracting the stored m2 pre-trend F test.")
pretrend <- tryCatch(
  safe_tar_read("fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test"),
  error = function(e) NULL
)
if (!is.null(pretrend)) {
  write_csv(tibble::as_tibble(pretrend$summary), out_path("m2_pretrend_f_test_summary.csv"))
  write_csv(tibble::as_tibble(pretrend$selected_periods), out_path("m2_pretrend_f_test_periods.csv"))
} else {
  message("  Pre-trend F-test target unavailable; skipping.")
}

message("Attempting the fect equivalence plot on the stored m2 main fit.")
equiv_status <- tryCatch({
  m2_main_fit <- safe_tar_read("fect_ife_china_top_m2_goods_status_current_min5_risk_set")
  p_equiv <- plot(
    m2_main_fit, type = "equiv",
    main = "Equivalence test: goods-only status-current IFE (5-year risk set)",
    cex.legend = 0.7
  )
  ggsave(out_path("m2_fect_equiv_plot.png"), p_equiv,
         width = 8, height = 5, dpi = 200)
  "saved"
}, error = function(e) paste0("failed: ", conditionMessage(e)))
write_csv(
  tibble::tibble(artifact = "m2_fect_equiv_plot.png", status = equiv_status),
  out_path("m2_fect_equiv_plot_status.csv")
)
message("  Equivalence plot status: ", equiv_status)

# ---------------------------------------------------------------------------
# Provenance and session info
# ---------------------------------------------------------------------------

manifest <- tibble::tibble(
  run_date = run_date,
  audit_code_version = audit_code_version,
  elapsed_minutes = as.numeric(difftime(Sys.time(), run_started, units = "mins")),
  parallel_cores = parallel_cores,
  placebo_replications = placebo_replications,
  placebo_seed = placebo_seed,
  ife_nboots = ife_nboots,
  bsv_sha256 = digest::digest(file = bsv_path, algo = "sha256", serialize = FALSE),
  ungadm_sha256 = digest::digest(file = ungadm_path, algo = "sha256", serialize = FALSE),
  bsv_reproduction_gate = gate_fit_equal,
  synthdid_version = as.character(utils::packageVersion("synthdid")),
  fect_version = as.character(utils::packageVersion("fect"))
)
write_csv(manifest, out_path("run_manifest.csv"))
writeLines(capture.output(sessionInfo()), out_path("session_info.txt"))
message("Done in ", sprintf("%.1f", manifest$elapsed_minutes), " minutes. Outputs in ", out_dir)
