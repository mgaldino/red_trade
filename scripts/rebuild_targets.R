# Targets the reproducibility rebuild must build: every target the manuscript
# reads (derived programmatically from the tar_read() calls in paper_v4.Rmd,
# so the list cannot drift from the paper) plus the targets the diagnostic
# scripts consume. Used by scripts/run_reproducibility_rebuild.sh.
rebuild_target_names <- function(rmd = "paper_v4.Rmd") {
  # Collapsed to one string first: paper_v4.Rmd wraps at least one tar_read()
  # across a line break, and a per-line regex silently drops those, which
  # defeats the whole point of deriving the list from the manuscript.
  text <- paste(readLines(rmd, warn = FALSE), collapse = "\n")
  hits <- regmatches(
    text, gregexpr("tar_read\\(\\s*([A-Za-z_0-9]+)\\s*\\)", text))
  from_paper <- unique(trimws(gsub("tar_read\\(|\\)", "", unlist(hits))))
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
                    "synth_fit_no_time_varying_covariates",
                    # Read by check_donor_pool_screen.R, which runs as this
                    # batch's gate. Without them here the gate dies on a clean
                    # machine, because both are otherwise built in `core`. The
                    # sector audit is a plain extraction from the aggregation
                    # the panel already depends on, so it adds no work.
                    "china_top_m2_goods_panel",
                    "china_top_m2_goods_sector_audit",
                    # Read by audit_brazil_sdid_no_covariates.R (batch
                    # `diagnostics`), which builds the donor China exposure and
                    # the timing falsification grid from targets instead of
                    # from CSVs frozen under the superseded donor screen. All
                    # three are cheap: trade_data_cleaned is already an
                    # ancestor of synth_data, trade_data_ranked is a ranking of
                    # a table this batch already builds, and
                    # goal3_brazil_rank_volume_data is a 13-row Brazil series
                    # derived from trade_data.
                    "trade_data_ranked", "trade_data_cleaned",
                    "goal3_brazil_rank_volume_data")

  expensive_se <- intersect(
    c("se_synth", "se_synth_latam", "se_synth_baseline"),
    all_targets)

  # Two families of targets descend from the corrected donor screen without
  # feeding any number in the manuscript. Both are rebuilt so that a replicator
  # does not find artefacts built under the superseded total-trade screen
  # sitting beside artefacts built under the goods screen -- but they are kept
  # apart because their costs differ by an order of magnitude.
  #
  # `extended` is cheap (~1 h, one 5,000-replication SE) and runs by default,
  # after the PDF exists.
  extended_targets <- c("synth_fit_extended", "se_synth_extended",
                        "sensitivity_results")

  # `legacy` is the exploratory material from earlier drafts: alternative
  # treatment dates, permutation tests, superseded plots. It carries FOUR more
  # 5,000-replication placebo SEs plus a permutation test, so it costs roughly
  # five hours, and it is opt-in for that reason. Leaving it out does not
  # affect a single manuscript number; it only means the store keeps mixed
  # provenance in targets nothing reads.
  #
  # Derived from the dependency graph, not by hand:
  #   descendants of synth_data / synth_data_baseline / trade_data_goods_ranked
  #   that appear in no other batch. check_batch_coverage.R recomputes this set
  #   from tar_network() on every prep batch and fails if the list has drifted.
  legacy_targets <- c(
    "brazil_sdid_diagnostics_bundle", "china_demand_sdid_diagnostics_table",
    "china_demand_sdid_panel", "donor_table",
    "goal3_brazil_placebo_rank_volume_tests", "goal6_sdid_outcome_results",
    "permutation_results", "placebo_teste_treatment02",
    "placebo_teste_treatment03", "placebo_teste_treatment04",
    "placebo_teste_treatment11", "plot_parallel", "plot_parallel_latam",
    "plot_trend", "plot_trend_latam", "plot_weights_coef",
    "plot_weights_coef_latam", "rmspe_diagnostics",
    "se_synth_placebo_rank2_2004", "se_synth_placebo1", "se_synth_placebo2",
    "se_synth_placebo3", "spaghetti_plot")

  batches <- c(
    list(data = data_targets),
    stats::setNames(as.list(expensive_se),
                    paste0("se_", seq_along(expensive_se)))
  )
  batches$core <- setdiff(all_targets,
                          c(unlist(batches, use.names = FALSE),
                            extended_targets, legacy_targets))
  batches$extended <- extended_targets
  batches$legacy <- legacy_targets
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
