#!/usr/bin/env Rscript

# Commodity / China-demand SDiD diagnostics under the no-covariate preferred
# specification (manuscript Table 5).
#
# Why this script exists (author decision, 2026-08-23): the preferred Brazil
# SDiD no longer supplies unit-level fixed covariate arrays; they are not
# separately identified from the SDiD unit fixed effects (coefficients
# numerically zero). The July audit
# (audit_brazil_sdid_predetermined_commodity_controls.R) built every
# "predetermined_*" specification on top of those arrays, so its Table 5 rows
# are no longer consistent with the preferred specification. That script is
# kept untouched as the record of how the previous numbers were produced.
#
# Specification changes relative to July:
#   * the preferred row uses NO covariates and takes its SE from the targets
#     pipeline (single source of truth; local fallback uses the pipeline's
#     own replication count and seed);
#   * commodity/price/China-demand rows keep ONLY the time-varying 2008-2009
#     interactions. Fixed levels are absorbed by the unit fixed effects, which
#     is also why an interaction without its main effect is the correct
#     specification here;
#   * the row "Add pre-2009 primary share" disappears (a fixed level alone is
#     collinear: in the July file it reproduced the preferred estimate to the
#     13th decimal);
#   * the legacy/invalid reconstruction row disappears (never shown in the
#     manuscript).
#
# All comparison rows share ONE permutation seed (common random numbers), so
# differences between rows reflect the specification, never the draw.
# Inputs are the persisted exposure and price tables from the July audit, so
# ITPD-E does not have to be reprocessed. Reads targets; never runs targets.

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(readr)
  library(tibble); library(synthdid)
})

options(scipen = 999)
run_started <- Sys.time()
audit_code_version <- "2026-08-24-v2-commodity-helpers"
target_store <- "_targets"

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()
parallel_cores <- sdid_available_cores()

in_dir <- file.path("data", "processed", "diagnostics",
                    "brazil_sdid_predetermined_commodity_controls")
out_dir <- file.path("data", "processed", "diagnostics",
                     "brazil_sdid_commodity_no_covariates")
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
op <- function(f) file.path(out_dir, f)

placebo_replications <- as.integer(Sys.getenv("COMMODITY_PLACEBO_REPS", "5000"))
target_replications <- 20000L  # must mirror _targets.R for the preferred row
smoke <- placebo_replications < 1000L
if (smoke) {
  message("NOTE: smoke-test replication count (", placebo_replications,
          "); outputs will be flagged smoke_test = TRUE and must not be used ",
          "as deliverables.")
}

safe_tar_read <- function(n) tryCatch(
  targets::tar_read_raw(n, store = target_store),
  error = function(e) NULL)

scale_vec <- function(x) {
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  as.numeric((x - mean(x, na.rm = TRUE)) / s)
}

# ------------------------------------------------------------------ inputs
message("Reading panel and persisted commodity/price inputs.")
synth_data <- safe_tar_read("synth_data")
if (is.null(synth_data)) stop("target `synth_data` unavailable.", call. = FALSE)
stopifnot(dir.exists(in_dir))
exposure <- read_csv(
  file.path(in_dir, "table_2_pre2009_commodity_exposure_by_country.csv"),
  show_col_types = FALSE)
prices <- read_csv(
  file.path(in_dir, "table_3_world_bank_commodity_price_indices.csv"),
  show_col_types = FALSE)

current_covariates <- c(
  "gpi", "perc_trade_with_us", "perc_trade_with_china", "pci_cur",
  "exachange_rate", "distance_us", "us_power_gap", "hog_left", "CA_GDP",
  "govdef_GDP", "inst_parliamentary", "inst_military_exec",
  "us_trade_agreement")
missing_covariates <- setdiff(current_covariates, names(synth_data))
if (length(missing_covariates)) {
  stop("missing covariates: ", paste(missing_covariates, collapse = ", "))
}

panel <- synth_data |>
  left_join(exposure |> select(iso3c, pre_primary_share_mean,
                               pre_agriculture_share_mean,
                               pre_mining_energy_share_mean,
                               pre_energy_mapped_share_mean,
                               pre_metals_mapped_share_mean,
                               pre_china_goods_share_mean),
            by = "iso3c") |>
  left_join(prices |> select(year, energy_log_change_2007,
                             agriculture_log_change_2007,
                             metals_minerals_log_change_2007),
            by = "year") |>
  mutate(
    shock_2008_2009 = as.integer(year %in% 2008:2009),
    primary_x_2008_2009_z = scale_vec(pre_primary_share_mean * shock_2008_2009),
    agriculture_x_2008_2009_z = scale_vec(pre_agriculture_share_mean * shock_2008_2009),
    mining_energy_x_2008_2009_z = scale_vec(pre_mining_energy_share_mean * shock_2008_2009),
    weighted_price_log_change_2007 =
      pre_agriculture_share_mean * agriculture_log_change_2007 +
      pre_energy_mapped_share_mean * energy_log_change_2007 +
      pre_metals_mapped_share_mean * metals_minerals_log_change_2007,
    weighted_price_x_2008_2009_z = scale_vec(weighted_price_log_change_2007 * shock_2008_2009),
    pre_china_x_2008_2009_z = scale_vec(pre_china_goods_share_mean * shock_2008_2009))

specifications <- list(
  current_baseline = current_covariates,
  no_covariates = character(0),
  primary_gfc_2008_2009 = "primary_x_2008_2009_z",
  agriculture_mining_gfc = c("agriculture_x_2008_2009_z", "mining_energy_x_2008_2009_z"),
  weighted_price_gfc = "weighted_price_x_2008_2009_z",
  pre_china_gfc = "pre_china_x_2008_2009_z")

# July's specification keys, kept as an auxiliary column for diffing versions.
legacy_keys <- c(
  current_baseline = "current_baseline",
  no_covariates = "predetermined_core",
  primary_gfc_2008_2009 = "predetermined_plus_primary_gfc_2008_2009",
  agriculture_mining_gfc = "predetermined_plus_agriculture_mining_gfc",
  weighted_price_gfc = "predetermined_plus_weighted_price_gfc",
  pre_china_gfc = "predetermined_plus_pre_china_gfc")

spec_meta <- tibble::tribble(
  ~specification, ~label, ~role, ~identification_rationale,
  "current_baseline", "Current covariates", "comparison",
  "Time-varying covariate matrix, including post-2009 observations.",
  "no_covariates", "Preferred: no covariates", "preferred main specification",
  "Counterfactual from pre-treatment outcomes and SDiD unit and time weights only.",
  "primary_gfc_2008_2009", "Primary share x 2008-2009", "commodity mechanism robustness",
  "Time-varying exposure interaction; includes the first treated year and may absorb part of the mechanism.",
  "agriculture_mining_gfc", "Agriculture/mining x 2008-2009", "decomposition robustness",
  "Separates Agriculture and Mining and Energy exposure interactions.",
  "weighted_price_gfc", "Price exposure x 2008-2009", "price-shock robustness",
  "Global commodity price changes from 2007 weighted by 2004-2008 export composition.",
  "pre_china_gfc", "Prior China share x 2008-2009", "China-demand robustness",
  "Mean 2004-2008 China goods-export share interacted with the common shock window.")

# ------------------------------------------------------------------- run
target_fit <- safe_tar_read("synth_fit_no_time_varying_covariates")
target_se <- safe_tar_read("se_synth_no_time_varying_covariates")

results <- list(); rank_rows <- list(); i <- 0L
for (spec in names(specifications)) {
  i <- i + 1L
  cols <- specifications[[spec]]
  message(sprintf("[%d/%d] %s (%d covariates)", i, length(specifications),
                  spec, length(cols)))
  fit <- sdid_fit_spec(panel, cols)
  if (identical(spec, "no_covariates")) {
    se_info <- sdid_preferred_se(fit, target_fit, target_se,
                                 target_replications = target_replications,
                                 cores = parallel_cores,
                                 checkpoint_dir = checkpoint_dir)
    se <- se_info$se
    se_reps_used <- se_info$replications
    se_seed_used <- se_info$seed
    se_source <- se_info$source
  } else {
    # Common random numbers: one fixed seed for every comparison row.
    se <- as.numeric(sdid_placebo_se(fit, placebo_replications,
                                     seed = SDID_PLACEBO_SEED,
                                     cores = parallel_cores,
                                     checkpoint_dir = checkpoint_dir,
                                     label = spec))
    se_reps_used <- placebo_replications
    se_seed_used <- SDID_PLACEBO_SEED
    se_source <- "Locally computed placebo SE (common random numbers across rows)."
  }
  results[[spec]] <- sdid_fit_summary_row(fit, spec, se) |>
    mutate(se_replications = se_reps_used, se_seed = se_seed_used,
           se_source = se_source)
  message(sprintf("    ATT = %.4f | SE = %.4f", as.numeric(fit), se))
  # rank inference for the two rows the manuscript reports it for
  if (spec %in% c("no_covariates", "primary_gfc_2008_2009")) {
    d <- sdid_rank_distribution(panel, cols, label = spec,
                                cores = parallel_cores,
                                checkpoint_dir = checkpoint_dir)
    inf <- sdid_rank_inference(d, spec)
    rank_rows[[spec]] <- tibble(
      specification = spec,
      rank_one_sided = inf$rank_one_sided_negative,
      rank_two_sided = inf$rank_two_sided_absolute,
      rank_denominator = inf$denominator,
      rank_p_one_sided_negative = inf$p_rank_one_sided_negative,
      rank_p_two_sided = inf$p_rank_two_sided_absolute,
      rank_inference_status = "Locally recomputed placebo-in-space ranks.")
    write_csv(d, op(sprintf("placebo_distribution_%s.csv", spec)))
  } else {
    rank_rows[[spec]] <- tibble(
      specification = spec, rank_one_sided = NA_integer_,
      rank_two_sided = NA_integer_, rank_denominator = NA_integer_,
      rank_p_one_sided_negative = NA_real_, rank_p_two_sided = NA_real_,
      rank_inference_status = paste0(
        "Not recomputed: rank inference is reported for the preferred ",
        "specification and the pre-specified commodity robustness."))
  }
}

table_out <- bind_rows(results) |>
  rename(p_value_two_sided = p_normal_two_sided,
         rmspe_pre_intercept_adjusted = rmspe_pre) |>
  left_join(bind_rows(rank_rows), by = "specification") |>
  left_join(spec_meta, by = "specification") |>
  mutate(preferred_by_identification = specification == "no_covariates",
         legacy_specification = unname(legacy_keys[specification]),
         se_method = "synthdid placebo",
         smoke_test = smoke) |>
  select(specification, legacy_specification, label, role,
         preferred_by_identification, identification_rationale, estimate,
         se_placebo, ci_95_low, ci_95_high, p_value_two_sided,
         rank_p_one_sided_negative, rank_p_two_sided, rank_one_sided,
         rank_two_sided, rank_denominator, everything())
write_csv(table_out, op("table_5_sdid_specification_results.csv"))
print(as.data.frame(table_out |> select(specification, estimate, se_placebo,
                                        p_value_two_sided,
                                        rank_p_one_sided_negative)),
      row.names = FALSE)

write_csv(tibble(
  run_date = as.character(Sys.Date()), audit_code_version = audit_code_version,
  elapsed_minutes = as.numeric(difftime(Sys.time(), run_started, units = "mins")),
  parallel_cores = parallel_cores,
  comparison_replications = placebo_replications,
  preferred_replications = target_replications,
  placebo_seed = SDID_PLACEBO_SEED,
  smoke_test = smoke,
  synthdid_version = as.character(utils::packageVersion("synthdid"))),
  op("run_manifest.csv"))
writeLines(capture.output(sessionInfo()), op("session_info.txt"))
message("Done in ", sprintf("%.1f", as.numeric(difftime(Sys.time(), run_started,
        units = "mins"))), " min -> ", out_dir)
