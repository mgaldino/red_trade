# Unified SDiD placebo machinery for the diagnostic scripts.
#
# Why this file exists (2026-08-24, following the R code review in
# quality_reports/2026-08-23_review_r_sdid_scripts.md): the placebo SE and
# placebo-in-space rank machinery had been copied into four diagnostic scripts
# with small divergences (seeds, checkpoint fingerprints, mclapply error
# handling). This file is the single implementation. It lives apart from
# sdid_diagnostics_helpers.R because that file runs set.seed() and setlocale()
# at source time, which a shared library must not do.
#
# Contracts:
#   * All randomness is drawn once from an explicit seed before any parallel
#     evaluation (mc.set.seed = FALSE), so results are deterministic given the
#     seed and independent of the number of cores.
#   * Checkpoint fingerprints cover the input data slice, the covariate set,
#     the synthdid version, AND the code bodies of the functions involved, so
#     editing the algorithm invalidates old checkpoints automatically.
#   * Parallel results are validated for completeness and type before use;
#     a child killed by the OS aborts the run instead of corrupting output.
#
# The canonical seed for every placebo standard error in this project is
# 20260520 (the default of se_sdid() in scripts/functions.R and of the
# targets pipeline). Scripts should not introduce other seeds for SEs.

SDID_PLACEBO_SEED <- 20260520L

# Local copy of synthdid:::sum_normalize (5 lines; copied verbatim so that a
# package update cannot silently change behavior; renv pins synthdid anyway).
sdid_sum_normalize <- function(x) {
  if (sum(x) != 0) x / sum(x) else rep(1 / length(x), length(x))
}

sdid_available_cores <- function(cap = 12L) {
  detected <- parallel::detectCores(logical = FALSE)
  cores <- if (is.na(detected)) 1L else max(1L, min(cap, detected))
  if (.Platform$OS.type == "windows") {
    message("mclapply does not fork on Windows; running sequentially.")
    cores <- 1L
  }
  cores
}

# BLAS threads must be limited BEFORE forking. Env vars set from inside R do
# not reconfigure an already-loaded BLAS, so prefer RhpcBLASctl when present.
sdid_limit_blas_threads <- function() {
  Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
             MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1")
  if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
    RhpcBLASctl::blas_set_num_threads(1L)
    RhpcBLASctl::omp_set_num_threads(1L)
  } else {
    message("RhpcBLASctl not installed: BLAS thread limits were set via ",
            "environment variables only, which an already-loaded BLAS may ",
            "ignore. Prefer launching via scripts/run_reproducibility_rebuild.sh, ",
            "which exports the limits before R starts.")
  }
  invisible(NULL)
}

# mclapply with completeness and type validation (a child killed by the OS
# returns NULL and would otherwise be dropped or recycled silently).
sdid_mclapply_checked <- function(items, fun, cores, what = "task") {
  vals <- parallel::mclapply(items, fun, mc.cores = cores,
                             mc.preschedule = TRUE, mc.set.seed = FALSE)
  if (length(vals) != length(items)) {
    stop("mclapply returned ", length(vals), " of ", length(items), " ",
         what, " results (child process killed?).", call. = FALSE)
  }
  dead <- vapply(vals, is.null, logical(1))
  if (any(dead)) {
    stop(sum(dead), " ", what, " result(s) are NULL (child process killed?).",
         call. = FALSE)
  }
  vals
}

sdid_read_checkpoint <- function(path) {
  tryCatch(
    readRDS(path),
    error = function(error) {
      warning(
        "Ignoring unreadable SDiD checkpoint ", path, ": ",
        conditionMessage(error),
        call. = FALSE
      )
      NULL
    }
  )
}

sdid_atomic_save_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(
    pattern = paste0(".", basename(path), "-"),
    tmpdir = dirname(path)
  )
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  saveRDS(object, temporary)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically replace SDiD checkpoint: ", path,
         call. = FALSE)
  }
  invisible(path)
}

sdid_build_covariate_array <- function(data, covariate_cols) {
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
      tidyr::pivot_wider(id_cols = iso3c, names_from = year,
                         values_from = value) |>
      dplyr::arrange(iso3c)
    out[, , k] <- wide |>
      dplyr::select(dplyr::all_of(as.character(time_levels))) |>
      as.matrix()
  }
  if (anyNA(out)) stop("Covariate array contains missing values.", call. = FALSE)
  out
}

# Canonical single-treated SDiD fit. With covariate_cols = character(0) the
# estimator uses outcomes alone (the project's preferred specification).
sdid_fit_spec <- function(data, covariate_cols = character(0),
                          treated_iso3c = "BRA",
                          year_start = 1997L, year_end = 2015L,
                          treat_year = 2009L, units = NULL) {
  d <- data |>
    dplyr::filter(year >= year_start, year <= year_end)
  if (!is.null(units)) d <- dplyr::filter(d, iso3c %in% units)
  d <- d |>
    dplyr::mutate(
      treatment = as.integer(iso3c == treated_iso3c & year >= treat_year),
      .unit_treated = as.integer(iso3c == treated_iso3c)
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)
  required <- c("iso3c", "year", "abs_distance_china", "treatment", covariate_cols)
  if (anyNA(d |> dplyr::select(dplyr::all_of(required)))) {
    stop("Missing values in fit data for treated unit ", treated_iso3c,
         call. = FALSE)
  }
  counts <- d |> dplyr::count(iso3c, name = "n_years")
  if (dplyr::n_distinct(counts$n_years) != 1L) {
    stop("Unbalanced SDiD panel.", call. = FALSE)
  }
  panel_data <- d |>
    dplyr::mutate(
      iso3c = factor(iso3c, levels = unique(iso3c)),
      year = as.integer(year),
      Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  if (length(covariate_cols) == 0L) {
    synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0)
  } else {
    synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0,
                                X = sdid_build_covariate_array(d, covariate_cols))
  }
}

sdid_fit_summary_row <- function(fit, specification, se_value = NA_real_) {
  s <- attr(fit, "setup"); w <- attr(fit, "weights")
  omega <- as.numeric(w$omega)
  controls <- s$Y[seq_len(s$N0), , drop = FALSE]
  treated <- as.numeric(s$Y[s$N0 + 1L, ])
  gap <- treated - as.numeric(t(omega) %*% controls)
  centered <- gap - mean(gap[seq_len(s$T0)], na.rm = TRUE)
  rmspe_pre <- sqrt(mean(centered[seq_len(s$T0)]^2, na.rm = TRUE))
  rmspe_post <- sqrt(mean(centered[(s$T0 + 1L):ncol(s$Y)]^2, na.rm = TRUE))
  estimate <- as.numeric(fit)
  tibble::tibble(
    specification = specification,
    estimate = estimate,
    se_placebo = se_value,
    ci_95_low = estimate - stats::qnorm(0.975) * se_value,
    ci_95_high = estimate + stats::qnorm(0.975) * se_value,
    p_normal_two_sided = ifelse(is.na(se_value) || se_value <= 0, NA_real_,
                                2 * stats::pnorm(-abs(estimate / se_value))),
    rmspe_pre = rmspe_pre,
    rmspe_post = rmspe_post,
    rmspe_ratio = rmspe_post / rmspe_pre,
    n_units = nrow(s$Y),
    n_donors = s$N0,
    n_pre_years = s$T0,
    n_post_years = ncol(s$Y) - s$T0,
    status = "estimated",
    error = ""
  )
}

.sdid_code_fingerprint <- function() {
  digest::digest(
    list(
      deparse(body(sdid_placebo_estimates)),
      deparse(body(sdid_sum_normalize)),
      deparse(body(sdid_fit_spec)),
      deparse(body(sdid_rank_distribution)),
      as.character(utils::packageVersion("synthdid"))
    ),
    algo = "sha256", serialize = TRUE
  )
}

# Full vector of placebo estimates for one fit, deterministic given the seed,
# with optional resumable checkpointing. The algorithm replicates
# synthdid::vcov(method = "placebo") exactly: resample the donor order,
# renormalize the unit weights over the drawn controls, re-estimate, and take
# the finite-population SD (validated numerically against the package in
# scripts/diagnostics/validate_parallel_synthdid_placebo.R).
sdid_placebo_estimates <- function(fit, replications, seed, cores,
                                   checkpoint_path = NULL, label = "spec",
                                   batch_size = 120L) {
  setup <- attr(fit, "setup")
  opts <- attr(fit, "opts")
  fit_weights <- attr(fit, "weights")
  n_treated <- nrow(setup$Y) - setup$N0
  if (setup$N0 <= n_treated) {
    stop("Placebo SE requires more control than treated units.", call. = FALSE)
  }
  fingerprint <- digest::digest(
    list(code = .sdid_code_fingerprint(), label = label,
         replications = replications, seed = seed,
         estimate = as.numeric(fit), setup = setup, opts = opts,
         weights = fit_weights),
    algo = "sha256", serialize = TRUE
  )
  estimates <- rep(NA_real_, replications)
  if (!is.null(checkpoint_path) && file.exists(checkpoint_path)) {
    cached <- sdid_read_checkpoint(checkpoint_path)
    cache_valid <- is.list(cached) &&
      identical(cached$fingerprint, fingerprint) &&
      is.numeric(cached$estimates) &&
      length(cached$estimates) == replications
    if (cache_valid) {
      estimates <- cached$estimates
      if (all(is.finite(estimates))) {
        recomputed <- sqrt((replications - 1) / replications) * stats::sd(estimates)
        if (!is.null(cached$se) &&
            !isTRUE(all.equal(recomputed, cached$se, tolerance = 1e-12))) {
          stop("Checkpoint SE does not match its own estimates (tampered or ",
               "truncated file): ", checkpoint_path, call. = FALSE)
        }
        message("    Reusing completed checkpoint: ", basename(checkpoint_path))
        return(estimates)
      }
      message("    Resuming checkpoint with ", sum(is.finite(estimates)), "/",
              replications, " placebo estimates.")
    }
  }
  set.seed(seed)
  draws <- replicate(replications, sample(seq_len(setup$N0)))
  theta <- function(j) {
    ind <- draws[, j]
    n_control <- length(ind) - n_treated
    bootstrap_weights <- fit_weights
    bootstrap_weights$omega <- sdid_sum_normalize(
      fit_weights$omega[ind[seq_len(n_control)]]
    )
    as.numeric(do.call(
      synthdid::synthdid_estimate,
      c(list(Y = setup$Y[ind, , drop = FALSE], N0 = n_control, T0 = setup$T0,
             X = setup$X[ind, , , drop = FALSE], weights = bootstrap_weights),
        opts)
    ))
  }
  missing_idx <- which(!is.finite(estimates))
  batches <- split(missing_idx, ceiling(seq_along(missing_idx) / batch_size))
  for (b in seq_along(batches)) {
    batch <- batches[[b]]
    if (length(batches) > 1L) {
      message("    Placebo batch ", b, "/", length(batches),
              " (", length(batch), " re-estimations; ", cores, " cores).")
    }
    vals <- sdid_mclapply_checked(batch, theta, cores, what = "placebo")
    bad <- !vapply(vals, function(v) is.numeric(v) && length(v) == 1L &&
                     is.finite(v), logical(1))
    if (any(bad)) {
      first <- vals[[which(bad)[1]]]
      stop("Placebo replication failed for ", label, ": ",
           if (inherits(first, "try-error")) as.character(first)
           else class(first)[1],
           call. = FALSE)
    }
    estimates[batch] <- unlist(vals)
    if (!is.null(checkpoint_path)) {
      partial_se <- if (all(is.finite(estimates))) {
        sqrt((replications - 1) / replications) * stats::sd(estimates)
      } else NA_real_
      sdid_atomic_save_rds(
        list(
          label = label,
          replications = replications,
          seed = seed,
          fingerprint = fingerprint,
          se = partial_se,
          estimates = estimates
        ),
        checkpoint_path
      )
    }
  }
  if (any(!is.finite(estimates))) {
    stop("Invalid placebo estimates for ", label, ".", call. = FALSE)
  }
  estimates
}

sdid_placebo_se <- function(fit, replications, seed = SDID_PLACEBO_SEED,
                            cores = sdid_available_cores(),
                            checkpoint_dir = NULL, label = "spec") {
  checkpoint_path <- if (is.null(checkpoint_dir)) NULL else
    file.path(checkpoint_dir, sprintf("placebo_se_%s_%d.rds", label, replications))
  estimates <- sdid_placebo_estimates(fit, replications, seed, cores,
                                      checkpoint_path, label)
  structure(
    sqrt((replications - 1) / replications) * stats::sd(estimates),
    replications = replications, seed = seed,
    synthdid_version = as.character(utils::packageVersion("synthdid"))
  )
}

# Placebo-in-space distribution: refit with each unit as the pseudo-treated.
# Deterministic (no RNG). Completeness is enforced before any use, so a killed
# child can never silently shrink the rank denominator.
sdid_rank_distribution <- function(data, covariate_cols = character(0),
                                   label = "spec",
                                   year_start = 1997L, year_end = 2015L,
                                   treat_year = 2009L,
                                   cores = sdid_available_cores(),
                                   checkpoint_dir = NULL,
                                   batch_size = 12L) {
  units <- sort(unique(data$iso3c))
  batch_size <- as.integer(batch_size)
  if (length(batch_size) != 1L || is.na(batch_size) || batch_size < 1L) {
    stop("Rank-placebo batch_size must be a positive integer.", call. = FALSE)
  }
  fingerprint <- digest::digest(
    list(code = .sdid_code_fingerprint(), label = label,
         covariate_cols = covariate_cols, units = units,
         year_start = year_start, year_end = year_end, treat_year = treat_year,
         data = data |>
           dplyr::filter(year >= year_start, year <= year_end) |>
           dplyr::arrange(iso3c, year) |>
           dplyr::select(iso3c, year, abs_distance_china,
                         dplyr::all_of(covariate_cols))),
    algo = "sha256", serialize = TRUE
  )
  checkpoint_path <- if (is.null(checkpoint_dir)) NULL else
    file.path(checkpoint_dir, sprintf("rank_placebos_%s.rds", label))
  required_checkpoint_columns <- c(
    "iso3c", "estimate", "rmspe_pre", "status", "error"
  )
  distribution <- tibble::tibble(
    iso3c = character(),
    estimate = numeric(),
    rmspe_pre = numeric(),
    status = character(),
    error = character()
  )
  if (!is.null(checkpoint_path) && file.exists(checkpoint_path)) {
    cached <- sdid_read_checkpoint(checkpoint_path)
    cache_valid <- is.list(cached) &&
      identical(cached$fingerprint, fingerprint) &&
        is.data.frame(cached$distribution) &&
      all(required_checkpoint_columns %in% names(cached$distribution)) &&
      !anyDuplicated(cached$distribution$iso3c) &&
      all(cached$distribution$iso3c %in% units)
    if (cache_valid) {
      distribution <- cached$distribution |>
        dplyr::select(dplyr::all_of(required_checkpoint_columns)) |>
        dplyr::arrange(match(iso3c, units))
    }
    if (cache_valid && setequal(distribution$iso3c, units)) {
      message("    Reusing rank-placebo checkpoint: ", basename(checkpoint_path))
      return(distribution)
    }
    if (cache_valid && nrow(distribution) > 0L) {
      message(
        "    Resuming rank-placebo checkpoint with ", nrow(distribution),
        "/", length(units), " assignments."
      )
    }
  }

  remaining_units <- setdiff(units, distribution$iso3c)
  batches <- split(
    remaining_units,
    ceiling(seq_along(remaining_units) / batch_size)
  )
  fit_unit <- function(unit) {
    fit <- tryCatch(
      sdid_fit_spec(
        data,
        covariate_cols,
        treated_iso3c = unit,
        year_start = year_start,
        year_end = year_end,
        treat_year = treat_year
      ),
      error = function(error) error
    )
    if (inherits(fit, "error")) {
      return(tibble::tibble(
        iso3c = unit,
        estimate = NA_real_,
        rmspe_pre = NA_real_,
        status = "error",
        error = conditionMessage(fit)
      ))
    }
    row <- sdid_fit_summary_row(fit, label)
    tibble::tibble(
      iso3c = unit,
      estimate = row$estimate,
      rmspe_pre = row$rmspe_pre,
      status = "estimated",
      error = ""
    )
  }
  for (batch_index in seq_along(batches)) {
    batch <- batches[[batch_index]]
    if (length(batches) > 1L) {
      message(
        "    Rank-placebo batch ", batch_index, "/", length(batches),
        " (", length(batch), " assignments; ", cores, " cores)."
      )
    }
    values <- sdid_mclapply_checked(
      batch,
      fit_unit,
      cores,
      what = "rank placebo"
    )
    valid_values <- vapply(
      seq_along(values),
      function(index) {
        value <- values[[index]]
        is.data.frame(value) && nrow(value) == 1L &&
          all(required_checkpoint_columns %in% names(value)) &&
          identical(as.character(value$iso3c), as.character(batch[[index]]))
      },
      logical(1)
    )
    if (!all(valid_values)) {
      stop("Invalid rank-placebo result in batch ", batch_index, ".",
           call. = FALSE)
    }
    distribution <- dplyr::bind_rows(distribution, values) |>
      dplyr::arrange(match(iso3c, units))
    if (!is.null(checkpoint_path)) {
      sdid_atomic_save_rds(
        list(
          fingerprint = fingerprint,
          distribution = distribution,
          updated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
        ),
        checkpoint_path
      )
    }
  }
  stopifnot(nrow(distribution) == length(units),
            setequal(distribution$iso3c, units))
  distribution
}

sdid_rank_inference <- function(distribution, comparison_set,
                                keep_units = NULL, treated_iso3c = "BRA") {
  valid <- distribution |>
    dplyr::filter(status == "estimated", !is.na(estimate))
  if (!is.null(keep_units)) {
    valid <- valid |> dplyr::filter(iso3c %in% keep_units)
  }
  treated <- valid |> dplyr::filter(iso3c == treated_iso3c)
  if (nrow(treated) != 1L) {
    stop("Treated unit ", treated_iso3c,
         " absent from the comparison set: ", comparison_set, call. = FALSE)
  }
  tibble::tibble(
    comparison_set = comparison_set,
    excluded_units = paste(setdiff(distribution$iso3c, valid$iso3c),
                           collapse = ";"),
    rank_one_sided_negative = sum(valid$estimate <= treated$estimate),
    rank_two_sided_absolute = sum(abs(valid$estimate) >= abs(treated$estimate)),
    denominator = nrow(valid),
    p_rank_one_sided_negative = mean(valid$estimate <= treated$estimate),
    p_rank_two_sided_absolute = mean(abs(valid$estimate) >= abs(treated$estimate))
  )
}

# Preferred-column SE with the pipeline as the source of truth: when the
# stored target reproduces `fit`, its SE is reused verbatim (with its own
# provenance); otherwise the SE is computed locally with the SAME replication
# count and seed the pipeline uses, so the value matches what tar_make() will
# store. `target_replications` must mirror _targets.R.
sdid_preferred_se <- function(fit, target_fit, target_se,
                              target_replications = 20000L,
                              cores = sdid_available_cores(),
                              checkpoint_dir = NULL, label = "no_covariates") {
  if (!is.null(target_fit) && !is.null(target_se) &&
      isTRUE(all.equal(as.numeric(target_fit), as.numeric(fit),
                       tolerance = 1e-8))) {
    reps <- attr(target_se, "replications")
    seed <- attr(target_se, "seed")
    return(list(
      se = as.numeric(target_se)[1],
      replications = if (is.null(reps)) target_replications else reps,
      seed = if (is.null(seed)) SDID_PLACEBO_SEED else seed,
      source = "Reused target se_synth_no_time_varying_covariates (pipeline is the source of truth)."
    ))
  }
  se <- sdid_placebo_se(fit, target_replications, SDID_PLACEBO_SEED,
                        cores, checkpoint_dir, label)
  list(
    se = as.numeric(se),
    replications = target_replications,
    seed = SDID_PLACEBO_SEED,
    source = paste0("Locally computed with the pipeline's replication count (",
                    format(target_replications, big.mark = ","),
                    ") and seed (", SDID_PLACEBO_SEED,
                    ") because the stored target was unavailable or stale; ",
                    "identical to what tar_make() will store.")
  )
}
