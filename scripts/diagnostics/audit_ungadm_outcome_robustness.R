#!/usr/bin/env Rscript

# Pre-committed measurement-robustness check: re-estimate the two main paper
# specifications with the outcome built from UNGA-DM ideal points (Fjelstul,
# Hug & Kilby 2026) instead of BSV Jun/2024.
#   (1) Brazil SDiD, preferred specification (NO covariates, 1997-2015): same
#       panel and donor pool; the BSV column reuses the pipeline SE after a
#       reproduction gate, and the UNGA-DM column uses the same replication
#       count and seed, so the two columns differ only in the outcome.
#   (2) Cross-country IFE, 5-year restricted risk set: common-window
#       apples-to-apples (UNGA-DM vs BSV on the identical row set,
#       year <= 2020), nboots = 10,000, same run_fect_analysis settings.
# Also extracts the existing m2 pre-trend F-test targets and attempts the fect
# equivalence plot.
# Decision rule (fixed before estimation): results are reported regardless of
# outcome. Plan: quality_reports/plans/2026-08-23_ungadm_robustness_check.md.
# Donor-exclusion rank rows use the window criterion decided by the author on
# 2026-08-23 (China-top observed inside 1997-2015); the 5-year qualifying
# criterion is kept only as an explicitly labeled legacy row.
# Reads existing targets; never runs targets.

suppressPackageStartupMessages({
  library(targets)
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
audit_code_version <- "2026-08-24-v2-ungadm-no-covariates"
target_store <- "_targets"

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()
parallel_cores <- sdid_available_cores()

bsv_path <- file.path(
  "raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv"
)
ungadm_path <- file.path(
  "raw data", "unga_dm", "unga_dm_ideal_points_all_resolution_votes_s75.csv"
)
paper_sdid_dir <- file.path(
  "data", "processed", "diagnostics", "paper_v4_brazil_sdid_no_covariates"
)
out_dir <- file.path(
  "data", "processed", "diagnostics", "ungadm_outcome_robustness", "estimation"
)
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- function(filename) file.path(out_dir, filename)

# Must mirror _targets.R (se_synth_no_time_varying_covariates); the UNGA-DM
# column uses the same count and seed so the columns are comparable.
target_replications <- 20000L
dm_replications <- as.integer(Sys.getenv("UNGADM_PLACEBO_REPS",
                                         as.character(target_replications)))
ife_nboots <- as.integer(Sys.getenv("UNGADM_IFE_NBOOTS", "10000"))
smoke <- dm_replications < 1000L || ife_nboots < 10000L
if (smoke) {
  message("NOTE: smoke-test counts in use (reps = ", dm_replications,
          ", nboots = ", ife_nboots, "); final outputs require the defaults.")
}

safe_tar_read <- function(name) {
  tryCatch(targets::tar_read_raw(name, store = target_store),
           error = function(e) stop("Could not read target `", name, "`: ",
                                    conditionMessage(e), call. = FALSE))
}

message("Sourcing scripts/functions.R for the fect machinery.")
source(file.path("scripts", "functions.R"))

# ---------------------------------------------------------------------------
# Step 1 - UNGA-DM outcome mapped to iso3c-year
# Country mapping inherits the pipeline's own convention by joining UNGA-DM to
# BSV on (ccode, session). Known convention difference fixed explicitly:
# session 45 (1990) Germany is ccode 255 in UNGA-DM and 260/DEU in BSV.
# Distances mirror get_unga_data(): per-session anchors from the source's own
# China (ccode 710) position; year = session + 1945.
# ---------------------------------------------------------------------------

message("Building the UNGA-DM outcome series.")
bsv_raw <- read_csv(bsv_path, show_col_types = FALSE) |>
  clean_names() |>
  transmute(ccode = as.integer(ccode), session = as.integer(session), iso3c)

ungadm_raw <- read_csv(ungadm_path, show_col_types = FALSE) |>
  clean_names() |>
  transmute(
    ccode = as.integer(ccode),
    session = as.integer(session),
    country_ungadm = country,
    q50_dm = x50
  ) |>
  mutate(ccode = if_else(session == 45L & ccode == 255L, 260L, ccode))

dm_mapped <- ungadm_raw |>
  left_join(bsv_raw, by = c("ccode", "session"))
unmatched_dm <- dm_mapped |> filter(is.na(iso3c))
write_csv(
  unmatched_dm |> select(ccode, session, country_ungadm),
  out_path("dm_rows_without_iso3c_mapping.csv")
)
message("  UNGA-DM rows without iso3c mapping (excluded): ", nrow(unmatched_dm))

dm_outcome <- dm_mapped |>
  filter(!is.na(iso3c)) |>
  group_by(session) |>
  mutate(china_ideal_dm = q50_dm[ccode == 710L][1]) |>
  ungroup() |>
  mutate(
    year = session + 1945L,
    abs_distance_china_dm = abs(q50_dm - china_ideal_dm)
  ) |>
  # All analysis windows start in 1990; pre-1990 rows carry a BSV iso3c quirk
  # (both Yemens coded YAR in sessions 22-44) that would break uniqueness.
  filter(year >= 1990L) |>
  select(iso3c, year, abs_distance_china_dm)
stopifnot(!any(duplicated(dm_outcome[, c("iso3c", "year")])))

# ---------------------------------------------------------------------------
# Step 2 - Brazil SDiD, preferred (no-covariate) specification
# ---------------------------------------------------------------------------

message("Reading SDiD targets.")
synth_data <- safe_tar_read("synth_data")
target_fit <- safe_tar_read("synth_fit_no_time_varying_covariates")
target_se <- safe_tar_read("se_synth_no_time_varying_covariates")

message("Gate: reproducing the pipeline's preferred (no-covariate) fit locally.")
fit_bsv <- sdid_fit_spec(synth_data)
gate_fit_equal <- isTRUE(all.equal(
  as.numeric(fit_bsv), as.numeric(target_fit), tolerance = 1e-8
))
message("  Local BSV estimate = ", format(as.numeric(fit_bsv), digits = 8),
        "; target = ", format(as.numeric(target_fit), digits = 8),
        "; equal = ", gate_fit_equal)
if (!gate_fit_equal) {
  stop("BSV reproduction gate failed: the stored target does not match the ",
       "no-covariate specification. Run the reproducibility rebuild ",
       "(scripts/run_reproducibility_rebuild.sh) first.", call. = FALSE)
}
bsv_se_info <- sdid_preferred_se(fit_bsv, target_fit, target_se,
                                 target_replications = target_replications,
                                 cores = parallel_cores,
                                 checkpoint_dir = checkpoint_dir,
                                 label = "bsv_no_covariates")

message("Swapping in the UNGA-DM outcome for the identical panel.")
estimation_data_dm <- synth_data |>
  left_join(dm_outcome, by = c("iso3c", "year")) |>
  mutate(abs_distance_china = abs_distance_china_dm) |>
  select(-abs_distance_china_dm)
dm_missing <- estimation_data_dm |>
  filter(year >= 1997L, year <= 2015L, is.na(abs_distance_china))
write_csv(dm_missing |> select(iso3c, year),
          out_path("sdid_dm_missing_outcome_rows.csv"))
if (nrow(dm_missing) > 0L) {
  stop("UNGA-DM outcome missing for ", nrow(dm_missing),
       " SDiD panel rows; donor pool would change. Inspect ",
       out_path("sdid_dm_missing_outcome_rows.csv"), call. = FALSE)
}

message("Fitting the UNGA-DM variant (no covariates).")
fit_dm <- sdid_fit_spec(estimation_data_dm)
message("  UNGA-DM estimate = ", format(as.numeric(fit_dm), digits = 8))

message("Placebo SE for the UNGA-DM variant (", dm_replications,
        " replications, seed ", SDID_PLACEBO_SEED, ").")
se_dm <- as.numeric(sdid_placebo_se(fit_dm, dm_replications,
                                    seed = SDID_PLACEBO_SEED,
                                    cores = parallel_cores,
                                    checkpoint_dir = checkpoint_dir,
                                    label = "ungadm_no_covariates"))

message("Rank placebos for the UNGA-DM variant.")
dm_distribution <- sdid_rank_distribution(estimation_data_dm,
                                          label = "ungadm_no_covariates",
                                          cores = parallel_cores,
                                          checkpoint_dir = checkpoint_dir)
write_csv(dm_distribution, out_path("sdid_dm_placebo_distribution.csv"))

units <- sort(unique(estimation_data_dm$iso3c))
bra_rmspe_dm <- dm_distribution$rmspe_pre[dm_distribution$iso3c == "BRA"]
goods_panel <- safe_tar_read("china_top_m2_goods_panel")
window_china_top <- goods_panel |>
  filter(china_is_top %in% TRUE, year >= 1997L, year <= 2015L,
         iso3c %in% units) |>
  distinct(iso3c) |>
  pull(iso3c)
window_excluded <- setdiff(window_china_top, "BRA")
m2_unit_summary <- safe_tar_read("china_top_m2_goods_status_current_unit_summary")
legacy_excluded <- m2_unit_summary |>
  filter(min_duration_years == 5L, sample == "risk_set_restricted",
         ever_treated %in% TRUE, iso3c %in% units) |>
  pull(iso3c) |>
  setdiff("BRA")

dm_rank_inference <- bind_rows(
  sdid_rank_inference(dm_distribution, "All valid assignments"),
  sdid_rank_inference(
    dm_distribution,
    "Exclude goods-only China-top donor assignments (window criterion)",
    keep_units = setdiff(units, window_excluded)),
  sdid_rank_inference(
    dm_distribution,
    "Exclude goods-only China-top donor assignments (legacy 5-year qualifying criterion; audit only)",
    keep_units = setdiff(units, legacy_excluded)),
  sdid_rank_inference(
    dm_distribution, "Pre-fit RMSPE no larger than twice Brazil",
    keep_units = dm_distribution$iso3c[dm_distribution$status == "estimated" &
                                         dm_distribution$rmspe_pre <=
                                           2 * bra_rmspe_dm])
)
write_csv(dm_rank_inference, out_path("sdid_dm_rank_inference.csv"))

dm_all_rank <- dm_rank_inference |> slice(1)
brazil_pre_mean_dm <- estimation_data_dm |>
  filter(iso3c == "BRA", year >= 1997L, year <= 2008L) |>
  summarise(m = mean(abs_distance_china)) |>
  pull(m)
brazil_pre_mean_bsv <- synth_data |>
  filter(iso3c == "BRA", year >= 1997L, year <= 2008L) |>
  summarise(m = mean(abs_distance_china)) |>
  pull(m)

dm_summary <- sdid_fit_summary_row(fit_dm, "ungadm_no_covariates", se_dm) |>
  mutate(
    rank_one_sided_negative = dm_all_rank$rank_one_sided_negative,
    rank_two_sided_absolute = dm_all_rank$rank_two_sided_absolute,
    rank_denominator = dm_all_rank$denominator,
    p_rank_one_sided_negative = dm_all_rank$p_rank_one_sided_negative,
    p_rank_two_sided_absolute = dm_all_rank$p_rank_two_sided_absolute,
    brazil_pre_treatment_mean = brazil_pre_mean_dm,
    estimate_as_percent_of_pre_mean = 100 * estimate / brazil_pre_treatment_mean,
    se_replications = dm_replications,
    se_seed = SDID_PLACEBO_SEED,
    smoke_test = smoke,
    source = paste0("Locally estimated; no-covariate specification; same ",
                    "replication count and seed as the BSV pipeline SE.")
  )
write_csv(dm_summary, out_path("sdid_dm_main_summary.csv"))

dm_setup <- attr(fit_dm, "setup"); dm_weights <- attr(fit_dm, "weights")
dm_unit_weights <- tibble(
  iso3c = rownames(dm_setup$Y)[seq_len(dm_setup$N0)],
  unit_weight = as.numeric(dm_weights$omega)
) |>
  arrange(desc(unit_weight))
write_csv(dm_unit_weights, out_path("sdid_dm_unit_weights.csv"))
bsv_setup <- attr(fit_bsv, "setup"); bsv_weights <- attr(fit_bsv, "weights")
bsv_unit_weights <- tibble(
  iso3c = rownames(bsv_setup$Y)[seq_len(bsv_setup$N0)],
  unit_weight = as.numeric(bsv_weights$omega)
) |>
  arrange(desc(unit_weight))
weight_overlap <- dm_unit_weights |>
  rename(unit_weight_dm = unit_weight) |>
  full_join(bsv_unit_weights |> rename(unit_weight_bsv = unit_weight),
            by = "iso3c")
write_csv(weight_overlap, out_path("sdid_unit_weights_bsv_vs_dm.csv"))

dm_time_weights <- tibble(
  year = as.integer(colnames(dm_setup$Y)[seq_len(dm_setup$T0)]),
  time_weight = as.numeric(dm_weights$lambda)
) |>
  mutate(time_weight_rank = rank(-time_weight, ties.method = "min"),
         high_time_weight = time_weight >= 0.1)
write_csv(dm_time_weights, out_path("sdid_dm_time_weights.csv"))

bsv_main_audited <- read_csv(file.path(paper_sdid_dir, "main_summary.csv"),
                             show_col_types = FALSE)
stopifnot(nrow(bsv_main_audited) == 1L)
sdid_comparison <- bind_rows(
  tibble(
    outcome_source = "BSV Jun/2024 (paper main, no covariates)",
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
    estimate_pct_pre_mean = bsv_main_audited$estimate_as_percent_of_pre_mean,
    se_replications = bsv_main_audited$se_replications,
    se_seed = bsv_main_audited$se_seed
  ),
  tibble(
    outcome_source = "UNGA-DM all resolution-related votes (Fjelstul et al. 2026)",
    estimate = dm_summary$estimate,
    se_placebo = dm_summary$se_placebo,
    ci_95_low = dm_summary$ci_95_low,
    ci_95_high = dm_summary$ci_95_high,
    p_normal_two_sided = dm_summary$p_normal_two_sided,
    rank_one_sided = dm_summary$rank_one_sided_negative,
    rank_two_sided = dm_summary$rank_two_sided_absolute,
    rank_denominator = dm_summary$rank_denominator,
    p_rank_one_sided = dm_summary$p_rank_one_sided_negative,
    p_rank_two_sided = dm_summary$p_rank_two_sided_absolute,
    rmspe_pre = dm_summary$rmspe_pre,
    brazil_pre_mean = brazil_pre_mean_dm,
    estimate_pct_pre_mean = dm_summary$estimate_as_percent_of_pre_mean,
    se_replications = dm_replications,
    se_seed = SDID_PLACEBO_SEED
  )
)
write_csv(sdid_comparison, out_path("sdid_comparison_table.csv"))
message("SDiD comparison written.")
print(as.data.frame(sdid_comparison |>
                      select(outcome_source, estimate, se_placebo,
                             p_normal_two_sided, p_rank_one_sided,
                             p_rank_two_sided)), row.names = FALSE)

# ---------------------------------------------------------------------------
# Step 3 - Cross-country IFE, 5-year restricted risk set, common window
# Apples-to-apples: both variants estimated on the identical row set
# (year <= 2020 and UNGA-DM outcome observed), same seed and settings.
# ---------------------------------------------------------------------------

message("Preparing the common-window IFE panels.")
panel_bundle <- safe_tar_read("china_top_m2_goods_status_current_panel_bundle")
p5 <- panel_bundle$panels[["5"]]$risk_set_restricted

p5_dm <- p5 |>
  left_join(dm_outcome, by = c("iso3c", "year"))
dropped_rows <- p5_dm |>
  filter(year > 2020L | is.na(abs_distance_china_dm)) |>
  count(reason = if_else(year > 2020L,
                         "beyond UNGA-DM endpoint (year > 2020)",
                         "UNGA-DM outcome missing"),
        iso3c) |>
  arrange(reason, iso3c)
write_csv(dropped_rows, out_path("ife_common_window_dropped_rows.csv"))

common_rows <- p5_dm |>
  filter(year <= 2020L, !is.na(abs_distance_china_dm))
message("  Common-window rows: ", nrow(common_rows), " of ", nrow(p5),
        " (dropped ", nrow(p5) - nrow(common_rows), ").")

panel_dm_common <- common_rows |>
  mutate(abs_distance_china = abs_distance_china_dm) |>
  select(-abs_distance_china_dm)
panel_bsv_common <- common_rows |>
  select(-abs_distance_china_dm)

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
  filter(min_duration_years == 5L, specification == "risk_set_restricted") |>
  slice(1)

ife_row <- function(label, s) {
  tibble(
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
ife_comparison <- bind_rows(
  tibble(
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
  tibble(
    variant = label,
    event_time = fit$time,
    count = fit$count,
    att = as.numeric(fit$est.att[, 1]),
    se = as.numeric(fit$est.att[, 2])
  ) |>
    mutate(ci_lo = att - 1.96 * se, ci_hi = att + 1.96 * se)
}
write_csv(
  bind_rows(
    dynamic_tbl(fit_ife_bsv_common, "BSV common window"),
    dynamic_tbl(fit_ife_dm_common, "UNGA-DM common window")
  ),
  out_path("ife_common_window_dynamic.csv")
)

# ---------------------------------------------------------------------------
# Step 4 - existing m2 pre-trend F test + fect equivalence plot
# ---------------------------------------------------------------------------

message("Extracting the stored m2 pre-trend F test.")
pretrend <- tryCatch(
  safe_tar_read("fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test"),
  error = function(e) NULL
)
if (!is.null(pretrend)) {
  write_csv(as_tibble(pretrend$summary), out_path("m2_pretrend_f_test_summary.csv"))
  write_csv(as_tibble(pretrend$selected_periods), out_path("m2_pretrend_f_test_periods.csv"))
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
write_csv(tibble(artifact = "m2_fect_equiv_plot.png", status = equiv_status),
          out_path("m2_fect_equiv_plot_status.csv"))
message("  Equivalence plot status: ", equiv_status)

# ---------------------------------------------------------------------------
# Provenance and session info
# ---------------------------------------------------------------------------

manifest <- tibble(
  run_date = run_date,
  audit_code_version = audit_code_version,
  elapsed_minutes = as.numeric(difftime(Sys.time(), run_started, units = "mins")),
  parallel_cores = parallel_cores,
  dm_replications = dm_replications,
  dm_seed = SDID_PLACEBO_SEED,
  bsv_se_source = bsv_se_info$source,
  ife_nboots = ife_nboots,
  smoke_test = smoke,
  bsv_sha256 = digest::digest(file = bsv_path, algo = "sha256", serialize = FALSE),
  ungadm_sha256 = digest::digest(file = ungadm_path, algo = "sha256", serialize = FALSE),
  bsv_reproduction_gate = gate_fit_equal,
  synthdid_version = as.character(utils::packageVersion("synthdid")),
  fect_version = as.character(utils::packageVersion("fect"))
)
write_csv(manifest, out_path("run_manifest.csv"))
writeLines(capture.output(sessionInfo()), out_path("session_info.txt"))
message("Done in ", sprintf("%.1f", manifest$elapsed_minutes),
        " minutes. Outputs in ", out_dir)
