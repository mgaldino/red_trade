#!/usr/bin/env Rscript

# Validate that deterministic parallelization reproduces the serial placebo
# algorithm used by synthdid. This script reads targets but never runs targets.

suppressPackageStartupMessages({
  library(targets)
  library(synthdid)
  library(tibble)
  library(readr)
})

replications <- as.integer(Sys.getenv("SDID_VALIDATION_REPLICATIONS", "20"))
cores <- min(replications, as.integer(Sys.getenv("SDID_VALIDATION_CORES", "12")))
seed <- 20260712L
output_path <- file.path(
  "data", "processed", "diagnostics",
  "brazil_sdid_predetermined_commodity_controls",
  "table_13_parallel_placebo_validation.csv"
)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

fit <- targets::tar_read_raw("synth_fit", store = "_targets")
setup <- attr(fit, "setup")
opts <- attr(fit, "opts")
fit_weights <- attr(fit, "weights")
n_treated <- nrow(setup$Y) - setup$N0

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

set.seed(seed)
package_started <- Sys.time()
package_se <- as.numeric(sqrt(stats::vcov(
  fit, method = "placebo", replications = replications
)))
package_seconds <- as.numeric(difftime(
  Sys.time(), package_started, units = "secs"
))

set.seed(seed)
draws <- replicate(replications, sample(seq_len(setup$N0)))
serial_started <- Sys.time()
serial_values <- vapply(seq_len(replications), theta, numeric(1))
serial_seconds <- as.numeric(difftime(Sys.time(), serial_started, units = "secs"))
parallel_started <- Sys.time()
parallel_values <- unlist(parallel::mclapply(
  seq_len(replications), theta,
  mc.cores = cores, mc.preschedule = TRUE, mc.set.seed = FALSE
))
parallel_seconds <- as.numeric(difftime(Sys.time(), parallel_started, units = "secs"))

factor <- sqrt((replications - 1) / replications)
serial_se <- factor * stats::sd(serial_values)
parallel_se <- factor * stats::sd(parallel_values)
package_serial_se_difference <- abs(package_se - serial_se)
serial_parallel_se_difference <- abs(serial_se - parallel_se)
max_draw_absolute_difference <- max(abs(serial_values - parallel_values))
serial_values_sha256 <- digest::digest(
  serial_values, algo = "sha256", serialize = TRUE
)
parallel_values_sha256 <- digest::digest(
  parallel_values, algo = "sha256", serialize = TRUE
)
se_difference <- max(package_serial_se_difference, serial_parallel_se_difference)
result <- tibble::tibble(
  validation = "Installed synthdid vcov and draw-by-draw serial versus deterministic parallel placebo",
  replications = replications,
  seed = seed,
  cores = cores,
  synthdid_version = as.character(utils::packageVersion("synthdid")),
  upstream_placebo_se_sha256 = digest::digest(
    synthdid:::placebo_se, algo = "sha256", serialize = TRUE
  ),
  package_vcov_se = package_se,
  serial_se = serial_se,
  parallel_se = parallel_se,
  absolute_se_difference = se_difference,
  package_serial_se_difference = package_serial_se_difference,
  serial_parallel_se_difference = serial_parallel_se_difference,
  max_draw_absolute_difference = max_draw_absolute_difference,
  draws_identical = identical(serial_values, parallel_values),
  serial_values_sha256 = serial_values_sha256,
  parallel_values_sha256 = parallel_values_sha256,
  package_seconds = package_seconds,
  serial_seconds = serial_seconds,
  parallel_seconds = parallel_seconds,
  passed = is.finite(se_difference) &&
    se_difference < 1e-12 &&
    max_draw_absolute_difference < 1e-12 &&
    identical(serial_values_sha256, parallel_values_sha256)
)
readr::write_csv(result, output_path)
if (!result$passed) stop("Parallel placebo validation failed.", call. = FALSE)
message("Parallel placebo validation passed: ", output_path)
