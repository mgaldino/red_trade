#!/usr/bin/env Rscript

# Placebo SEs at 5,000 replications for the four Brazil SDiD specifications in
# manuscript Table 3, computed with the same se_sdid() and the same default
# seed the pipeline uses. Running this outside targets avoids needing the full
# environment restore, and the values are identical to what tar_make() will
# store overnight, because se_sdid() is deterministic given the seed.
#
# Motivation: at 1,000 replications the SE estimator itself is noisy (five
# independent blocks on the preferred fit spanned 0.1262-0.1355, moving p
# between 0.031 and 0.045). At 5,000 it converges to the standard deviation of
# the exhaustive placebo-in-space distribution.

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(readr); library(tibble)
  library(synthdid)
})
options(scipen = 999)
source(file.path("scripts", "functions.R"))

started <- Sys.time()
out <- file.path("data", "processed", "diagnostics",
                 "sdid_placebo_se_5000_reference.csv")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()
reps <- as.integer(Sys.getenv("SE5K_REPS", "5000"))
cores <- sdid_available_cores()

synth_data <- tar_read(synth_data)

# The preferred fit is recomputed locally because its target is stale (the
# function dropped the covariate arrays); the comparison fits come from targets.
fits <- list(
  `(1) Preferred: no covariates` = simple_fit_no_time_varying_covariates(synth_data),
  `(2) Current covariates`       = tar_read(synth_fit),
  `(3) No institutions`          = tar_read(synth_fit_baseline),
  `(4) Latin America`            = tar_read(synth_fit_latam)
)

# Per-column replication counts mirror _targets.R: 20,000 for the preferred
# no-covariate column (cheap: ~4 min), 5,000 for the covariate comparisons
# (each replication re-solves the covariate coefficients, ~1.6 s/replication
# on 12 cores, so 5,000 already costs ~2h per column).
reps_for <- function(nm) if (startsWith(nm, "(1)")) 20000L else reps

rows <- lapply(names(fits), function(nm) {
  reps_nm <- reps_for(nm)
  message("Computing SE for ", nm, " (", reps_nm, " reps, ", cores, " cores)...")
  t0 <- Sys.time()
  se <- se_sdid(fits[[nm]], replications = reps_nm, cores = cores)
  att <- as.numeric(fits[[nm]])[1]
  message(sprintf("  ATT = %.4f | SE = %.4f | p = %.4f | %.1f min",
                  att, se, 2 * pnorm(-abs(att / se)),
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  tibble(column = nm, att = att, se_placebo = se,
         ci_95_low = att - qnorm(0.975) * se,
         ci_95_high = att + qnorm(0.975) * se,
         p_normal_two_sided = 2 * pnorm(-abs(att / se)),
         replications = reps_nm, seed = 20260520L,
         minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")))
})

res <- bind_rows(rows)
write_csv(res, out)
cat("\n")
print(as.data.frame(res |> select(column, att, se_placebo, p_normal_two_sided)),
      row.names = FALSE)
cat(sprintf("\nTotal: %.1f min -> %s\n",
            as.numeric(difftime(Sys.time(), started, units = "mins")), out))
