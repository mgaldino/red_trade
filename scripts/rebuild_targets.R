# Targets the reproducibility rebuild must build: every target the manuscript
# reads (derived programmatically from the tar_read() calls in paper_v4.Rmd,
# so the list cannot drift from the paper) plus the targets the diagnostic
# scripts consume. Used by scripts/run_reproducibility_rebuild.sh.
rebuild_target_names <- function(rmd = "paper_v4.Rmd") {
  text <- readLines(rmd, warn = FALSE)
  hits <- regmatches(text, gregexpr("tar_read\\(([A-Za-z_0-9]+)\\)", text))
  from_paper <- unique(gsub("tar_read\\(|\\)", "", unlist(hits)))
  diagnostics_extras <- c(
    "synth_fit_no_time_varying_covariates",
    "se_synth_no_time_varying_covariates",
    "china_top_m2_goods_panel",
    "china_top_m2_goods_status_current_panel_bundle",
    "china_top_m2_goods_status_current_unit_summary",
    "fect_ife_china_top_m2_goods_status_current_min5_risk_set",
    "fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test"
  )
  sort(unique(c(from_paper, diagnostics_extras)))
}

# --------------------------------------------------------------------------
# Batched execution (2026-08-25).
#
# The targets stage ran ~3h as one block, which is more than one sitting on
# this machine. Two facts shape the split:
#
#  1. The cost is concentrated in the placebo SEs of the COVARIATE
#     specifications. Each of their 5,000 replications re-solves the covariate
#     coefficients (~1.6 s/replication on 12 cores, roughly an hour apiece),
#     while the preferred no-covariate column stays cheap even at 20,000.
#  2. brazil_sdid_spec_table depends on ALL FOUR SE targets. Put it in an
#     early batch and tar_make() pulls every expensive SE in as a dependency,
#     collapsing the split back into one long block. It therefore belongs to
#     the LAST batch, by which point the SEs are already cached.
#
# Hence the order: data -> se_1 -> se_2 -> se_3 -> core. Batches can still be
# run in any order or repeated -- targets caches completed work and pulls in
# missing dependencies -- but that order is the one that actually keeps each
# sitting short. The `data` batch is deliberately first and cheap: it is the
# gate where the corrected donor pool is verified before any hour-long run.
rebuild_target_batches <- function(rmd = "paper_v4.Rmd") {
  all_targets <- rebuild_target_names(rmd)

  # Listed in full rather than intersected with the manuscript's targets:
  # trade_data_goods, trade_data_goods_ranked, synth_data_baseline and
  # synth_data_extended are upstream dependencies the paper never reads
  # directly, but naming them keeps the gate explicit about what it is
  # verifying. synth_data_extended matters here for a specific reason: the
  # donor-pool invariant validates all three panels, so leaving it out of the
  # batch makes the gate compare two freshly built panels against a stale one
  # and fail on the stale one's old total-trade screen. It is cheap to build
  # (well under a second); the expensive members of its family
  # (synth_fit_extended, se_synth_extended, sensitivity_results) feed no
  # manuscript number and stay out of the rebuild.
  data_targets <- c("trade_data_goods", "trade_data_goods_ranked",
                    "synth_data", "synth_data_baseline", "synth_data_extended",
                    "synth_fit", "synth_fit_baseline", "synth_fit_latam",
                    "synth_fit_no_time_varying_covariates")

  expensive_se <- intersect(
    c("se_synth", "se_synth_latam", "se_synth_baseline"),
    all_targets)

  batches <- c(
    list(data = data_targets),
    stats::setNames(as.list(expensive_se),
                    paste0("se_", seq_along(expensive_se)))
  )
  batches$core <- setdiff(all_targets, unlist(batches, use.names = FALSE))
  batches
}

# Names for one batch, or every rebuild target when batch is NULL/"all".
rebuild_batch_names <- function(batch = NULL, rmd = "paper_v4.Rmd") {
  if (is.null(batch) || identical(batch, "all")) return(rebuild_target_names(rmd))
  batches <- rebuild_target_batches(rmd)
  if (!batch %in% names(batches)) {
    stop("unknown target batch '", batch, "'; available: ",
         paste(names(batches), collapse = ", "), call. = FALSE)
  }
  batches[[batch]]
}
