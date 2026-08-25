#!/usr/bin/env Rscript

# Post-review diagnostics for the UNGA-DM measurement-robustness check,
# implementing the items requested by the independent causal review
# (quality_reports/ungadm_outcome_robustness/2026-08-23_independent_causal_review.md):
#   1. Full 2x2 fixed-r IFE grid (BSV/UNGA-DM x r = 1/2) on the common-window,
#      identical-row panel, 10,000 bootstraps each.
#   2. Paired cluster bootstrap of the ATT difference (UNGA-DM minus BSV),
#      stratified by treated/control, point fits only.
#   3. Per-treated-country divergence inspection between the outcome series.
#   4. Time-weights/balance exports for the UNGA-DM SDiD fit and seed notes.
# The SDiD side uses the paper's preferred NO-COVARIATE specification via
# scripts/diagnostics/sdid_placebo_helpers.R; the previously supplied fixed
# covariate arrays are reported only as descriptive balance rows.
# Reads existing targets and stored CSVs; never runs targets.

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(tibble)
  library(janitor)
  library(synthdid)
  library(fect)
})

options(scipen = 999)
run_started <- Sys.time()
run_date <- as.character(Sys.Date())
audit_code_version <- "2026-08-24-v2-postreview-no-covariates"
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
est_dir <- file.path(
  "data", "processed", "diagnostics", "ungadm_outcome_robustness", "estimation"
)
out_dir <- file.path(
  "data", "processed", "diagnostics", "ungadm_outcome_robustness", "postreview"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
op <- function(f) file.path(out_dir, f)

ife_nboots <- as.integer(Sys.getenv("UNGADM2_IFE_NBOOTS", "10000"))
boot_B <- as.integer(Sys.getenv("UNGADM2_BOOT_B", "1000"))
boot_seed <- 20260823L  # resampling seed only; SEs always use SDID_PLACEBO_SEED
smoke <- ife_nboots < 10000L || boot_B < 1000L
if (smoke) {
  message("NOTE: smoke-test counts in use (nboots = ", ife_nboots,
          ", B = ", boot_B, "); final outputs require the defaults.")
}

safe_tar_read <- function(n) tryCatch(
  targets::tar_read_raw(n, store = target_store),
  error = function(e) stop("target `", n, "`: ", conditionMessage(e),
                           call. = FALSE))

message("Sourcing scripts/functions.R for prepare_fect_data/fect summaries.")
source(file.path("scripts", "functions.R"))

# ---------------------------------------------------------------------------
# UNGA-DM outcome (identical construction to audit_ungadm_outcome_robustness.R)
# ---------------------------------------------------------------------------
message("Building the UNGA-DM outcome series.")
bsv_raw <- read_csv(bsv_path, show_col_types = FALSE) |>
  clean_names() |>
  transmute(ccode = as.integer(ccode), session = as.integer(session), iso3c)
ungadm_raw <- read_csv(ungadm_path, show_col_types = FALSE) |>
  clean_names() |>
  transmute(
    ccode = as.integer(ccode), session = as.integer(session),
    country_ungadm = country, q50_dm = x50
  ) |>
  mutate(ccode = if_else(session == 45L & ccode == 255L, 260L, ccode))
dm_outcome <- ungadm_raw |>
  left_join(bsv_raw, by = c("ccode", "session")) |>
  filter(!is.na(iso3c)) |>
  group_by(session) |>
  mutate(china_ideal_dm = q50_dm[ccode == 710L][1]) |>
  ungroup() |>
  mutate(
    year = session + 1945L,
    abs_distance_china_dm = abs(q50_dm - china_ideal_dm)
  ) |>
  filter(year >= 1990L) |>
  select(iso3c, year, abs_distance_china_dm)
stopifnot(!any(duplicated(dm_outcome[, c("iso3c", "year")])))

# ---------------------------------------------------------------------------
# SDiD exports under the preferred no-covariate specification: refits are
# deterministic; the BSV fit is gated against the pipeline target.
# ---------------------------------------------------------------------------
message("Refitting both SDiD variants (no covariates) for weights/balance exports.")
synth_data <- safe_tar_read("synth_data")
estimation_data_dm <- synth_data |>
  left_join(dm_outcome, by = c("iso3c", "year")) |>
  mutate(abs_distance_china = abs_distance_china_dm) |>
  select(-abs_distance_china_dm)

fit_bsv <- sdid_fit_spec(synth_data)
fit_dm <- sdid_fit_spec(estimation_data_dm)
target_fit <- safe_tar_read("synth_fit_no_time_varying_covariates")
if (!isTRUE(all.equal(as.numeric(fit_bsv), as.numeric(target_fit),
                      tolerance = 1e-8))) {
  stop("BSV reproduction gate failed: the stored target does not match the ",
       "no-covariate specification. Run the reproducibility rebuild first.",
       call. = FALSE)
}

# Harmonized China-top donor exclusion (author decision 2026-08-23): window
# criterion. The legacy 5-year qualifying criterion is reported for audit.
units <- sort(unique(synth_data$iso3c))
goods_panel <- safe_tar_read("china_top_m2_goods_panel")
window_excluded <- goods_panel |>
  filter(china_is_top %in% TRUE, year >= 1997L, year <= 2015L,
         iso3c %in% units) |>
  distinct(iso3c) |>
  pull(iso3c) |>
  setdiff("BRA")
m2_unit_summary <- safe_tar_read("china_top_m2_goods_status_current_unit_summary")
legacy_excluded <- m2_unit_summary |>
  filter(min_duration_years == 5L, sample == "risk_set_restricted",
         ever_treated %in% TRUE, iso3c %in% units) |>
  pull(iso3c) |>
  setdiff("BRA")

dm_distribution <- read_csv(
  file.path(est_dir, "sdid_dm_placebo_distribution.csv"),
  show_col_types = FALSE
)
stopifnot(nrow(dm_distribution) == length(units),
          setequal(dm_distribution$iso3c, units))
rank_harmonized <- bind_rows(
  sdid_rank_inference(dm_distribution, "All valid assignments"),
  sdid_rank_inference(
    dm_distribution,
    "Exclude goods-only China-top donor assignments (harmonized: window criterion)",
    keep_units = setdiff(units, window_excluded)),
  sdid_rank_inference(
    dm_distribution,
    "Exclude goods-only China-top donor assignments (legacy 5-year qualifying criterion; audit only)",
    keep_units = setdiff(units, legacy_excluded))
)
write_csv(rank_harmonized, op("sdid_dm_rank_inference_harmonized.csv"))
print(as.data.frame(rank_harmonized), row.names = FALSE)

dm_setup <- attr(fit_dm, "setup"); dm_weights <- attr(fit_dm, "weights")
tw_dm <- tibble(
  year = as.integer(colnames(dm_setup$Y)[seq_len(dm_setup$T0)]),
  time_weight = as.numeric(dm_weights$lambda)
) |>
  mutate(time_weight_rank = rank(-time_weight, ties.method = "min"),
         high_time_weight = time_weight >= 0.1)
write_csv(tw_dm, op("sdid_dm_time_weights.csv"))

donors <- rownames(dm_setup$Y)[seq_len(dm_setup$N0)]
omega_dm <- as.numeric(dm_weights$omega)
pre <- estimation_data_dm |> filter(year >= 1997L, year <= 2008L)
pre_bsv <- synth_data |> filter(year >= 1997L, year <= 2008L)
bal_one <- function(data_pre, v, label, role, defn) {
  dv <- data_pre |> filter(iso3c != "BRA") |>
    group_by(iso3c) |>
    summarise(x = mean(.data[[v]], na.rm = TRUE), .groups = "drop")
  dv <- dv[match(donors, dv$iso3c), ]
  bv <- data_pre |> filter(iso3c == "BRA") |>
    summarise(x = mean(.data[[v]], na.rm = TRUE)) |> pull(x)
  sv <- sum(omega_dm * dv$x)
  sdv <- stats::sd(dv$x)
  tibble(variable = v, label = label, role = role,
         brazil_pre_mean = bv, synthetic_pre_mean = sv,
         brazil_minus_synthetic = bv - sv,
         standardized_difference = (bv - sv) / ifelse(sdv > 0, sdv, NA_real_),
         included_in_preferred_specification = (role == "Outcome"),
         value_definition = defn,
         diagnostic_scope = paste0(
           "Omega-weighted pre-treatment values under the UNGA-DM fit; ",
           "descriptive. The preferred specification uses no covariates."))
}
balance_dm <- bind_rows(
  bal_one(pre, "abs_distance_china",
          "Absolute UNGA ideal-point distance to China (UNGA-DM)",
          "Outcome", "1997-2008 mean"),
  bal_one(pre_bsv, "perc_trade_with_china", "Export share to China",
          "Descriptive covariate", "1997-2008 mean"),
  bal_one(pre_bsv, "perc_trade_with_us", "Export share to the United States",
          "Descriptive covariate", "1997-2008 mean"),
  bal_one(pre_bsv, "pci_cur", "Per-capita income",
          "Descriptive covariate", "1997-2008 mean"),
  bal_one(pre_bsv, "gpi", "Power index", "Descriptive covariate",
          "1997-2008 mean")
)
write_csv(balance_dm, op("sdid_dm_balance.csv"))

# Seed/provenance notes generated from the actual values in the comparison
# table, so they cannot drift from the artifacts they describe.
sdid_comparison <- read_csv(file.path(est_dir, "sdid_comparison_table.csv"),
                            show_col_types = FALSE)
stopifnot(nrow(sdid_comparison) == 2L)
write_csv(tibble(
  note = c("se_provenance", "ranks_deterministic"),
  detail = c(
    sprintf(
      "BSV SE: %s replications, seed %s. UNGA-DM SE: %s replications, seed %s. Identical counts and seeds make the two columns differ only in the outcome series.",
      format(sdid_comparison$se_replications[1], big.mark = ","),
      sdid_comparison$se_seed[1],
      format(sdid_comparison$se_replications[2], big.mark = ","),
      sdid_comparison$se_seed[2]),
    "Placebo-in-space ranks involve no random draws; rank columns are exactly reproducible regardless of seed."
  )
), op("sdid_inference_notes.csv"))

# ---------------------------------------------------------------------------
# Common-window IFE panels (identical construction to the estimation audit)
# ---------------------------------------------------------------------------
message("Rebuilding the common-window IFE panels.")
panel_bundle <- safe_tar_read("china_top_m2_goods_status_current_panel_bundle")
p5 <- panel_bundle$panels[["5"]]$risk_set_restricted
common_rows <- p5 |>
  left_join(dm_outcome, by = c("iso3c", "year")) |>
  filter(year <= 2020L, !is.na(abs_distance_china_dm))
panel_dm_common <- common_rows |>
  mutate(abs_distance_china = abs_distance_china_dm) |>
  select(-abs_distance_china_dm)
panel_bsv_common <- common_rows |> select(-abs_distance_china_dm)
message("  Common rows: ", nrow(common_rows))

# ---------------------------------------------------------------------------
# Item 1 - 2x2 fixed-r grid with full bootstrap inference
# ---------------------------------------------------------------------------
run_fect_fixed_r <- function(panel, r_fixed, nboots) {
  set.seed(42)
  fect_data <- prepare_fect_data(panel, fml = abs_distance_china ~ china_top)
  fect::fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "ife", force = "two-way",
    se = TRUE, nboots = nboots, parallel = FALSE,
    CV = FALSE, r = r_fixed
  )
}
# CV-selected factor numbers come from the estimation-stage artifact rather
# than being hard-coded, so the labels cannot drift from the data.
ife_comparison_est <- read_csv(file.path(est_dir, "ife_comparison_table.csv"),
                               show_col_types = FALSE)
r_cv_bsv <- ife_comparison_est |>
  filter(grepl("^BSV common window", variant)) |> pull(r_cv)
r_cv_dm <- ife_comparison_est |>
  filter(grepl("^UNGA-DM common window", variant)) |> pull(r_cv)
stopifnot(length(r_cv_bsv) == 1L, length(r_cv_dm) == 1L)

grid <- expand.grid(
  outcome = c("BSV", "UNGA-DM"), r_fixed = c(1L, 2L),
  stringsAsFactors = FALSE
)
grid_results <- list()
for (i in seq_len(nrow(grid))) {
  outcome_i <- grid$outcome[i]
  r_i <- grid$r_fixed[i]
  message("2x2 cell ", i, "/4: ", outcome_i, ", r = ", r_i,
          " (nboots = ", ife_nboots, ").")
  panel_i <- if (outcome_i == "BSV") panel_bsv_common else panel_dm_common
  fit_i <- run_fect_fixed_r(panel_i, r_i, ife_nboots)
  s_i <- summarize_fect_model(fit_i, panel_i)
  grid_results[[i]] <- tibble(
    outcome = outcome_i, r_fixed = r_i,
    cv_selected = (outcome_i == "BSV" && r_i == r_cv_bsv) ||
      (outcome_i == "UNGA-DM" && r_i == r_cv_dm),
    att = s_i$att, se = s_i$se, ci_lo = s_i$ci_lo, ci_hi = s_i$ci_hi,
    p = s_i$p, att_rel_pct = s_i$att_rel_pct, att_sd_units = s_i$att_sd_units,
    n_obs = s_i$n_obs, nboots = ife_nboots, smoke_test = smoke
  )
  print(as.data.frame(grid_results[[i]]), row.names = FALSE)
}
grid_table <- bind_rows(grid_results)
write_csv(grid_table, op("ife_2x2_fixed_r.csv"))

# ---------------------------------------------------------------------------
# Item 2 - Paired cluster bootstrap of the ATT difference (point fits only)
# Stratified country resampling; identical draws applied to both outcomes.
# ---------------------------------------------------------------------------
message("Paired cluster bootstrap (B = ", boot_B, ", stratified).")
treated_units <- common_rows |>
  group_by(iso3c) |>
  summarise(t = any(china_top == 1), .groups = "drop")
treated_ids <- treated_units$iso3c[treated_units$t]
control_ids <- treated_units$iso3c[!treated_units$t]
fit_point <- function(panel, r_fixed) {
  fect_data <- prepare_fect_data(panel, fml = abs_distance_china ~ china_top)
  fit <- fect::fect(
    abs_distance_china ~ china_top,
    data = fect_data, index = c("country_id", "year"),
    method = "ife", force = "two-way",
    se = FALSE, parallel = FALSE, CV = FALSE, r = r_fixed
  )
  as.numeric(fit$att.avg)
}
set.seed(boot_seed)
draw_list <- lapply(seq_len(boot_B), function(b) {
  c(sample(treated_ids, length(treated_ids), replace = TRUE),
    sample(control_ids, length(control_ids), replace = TRUE))
})
boot_one <- function(b) {
  # fect should not consume RNG with se = FALSE and fixed r, but fixing the
  # child seed guarantees core-count independence even if it does.
  set.seed(boot_seed + b)
  drawn <- draw_list[[b]]
  resampled <- lapply(seq_along(drawn), function(k) {
    common_rows |>
      filter(iso3c == drawn[k]) |>
      mutate(
        iso3c = paste0(drawn[k], "_", k),
        country_id = k,
        country_name = iso3c
      )
  }) |> bind_rows()
  panel_dm_b <- resampled |>
    mutate(abs_distance_china = abs_distance_china_dm) |>
    select(-abs_distance_china_dm)
  panel_bsv_b <- resampled |> select(-abs_distance_china_dm)
  tryCatch({
    att_bsv_r2 <- fit_point(panel_bsv_b, 2L)
    att_dm_r1 <- fit_point(panel_dm_b, 1L)
    att_dm_r2 <- fit_point(panel_dm_b, 2L)
    tibble(
      b = b, status = "ok",
      att_bsv_r2 = att_bsv_r2, att_dm_r1 = att_dm_r1, att_dm_r2 = att_dm_r2,
      diff_procedure = att_dm_r1 - att_bsv_r2,
      diff_common_r2 = att_dm_r2 - att_bsv_r2
    )
  }, error = function(e) {
    tibble(
      b = b, status = paste0("error: ", conditionMessage(e)),
      att_bsv_r2 = NA_real_, att_dm_r1 = NA_real_, att_dm_r2 = NA_real_,
      diff_procedure = NA_real_, diff_common_r2 = NA_real_
    )
  })
}
boot_vals <- sdid_mclapply_checked(seq_len(boot_B), boot_one, parallel_cores,
                                   what = "paired bootstrap")
boot_draws <- bind_rows(boot_vals)
stopifnot(nrow(boot_draws) == boot_B,
          setequal(boot_draws$b, seq_len(boot_B)))
write_csv(boot_draws, op("ife_paired_bootstrap_draws.csv"))

summarize_diff <- function(x, label, observed_diff) {
  x <- x[is.finite(x)]
  tibble(
    contrast = label,
    observed_diff = observed_diff,
    boot_mean = mean(x),
    boot_sd = sd(x),
    ci_2_5 = unname(quantile(x, 0.025)),
    ci_97_5 = unname(quantile(x, 0.975)),
    p_two_sided_percentile = 2 * min(mean(x <= 0), mean(x >= 0)),
    p_two_sided_normal = 2 * stats::pnorm(-abs(observed_diff / sd(x))),
    n_valid = length(x),
    n_failed = boot_B - length(x)
  )
}
obs_bsv_r2 <- grid_table |> filter(outcome == "BSV", r_fixed == 2L) |> pull(att)
obs_dm_r1 <- grid_table |> filter(outcome == "UNGA-DM", r_fixed == 1L) |> pull(att)
obs_dm_r2 <- grid_table |> filter(outcome == "UNGA-DM", r_fixed == 2L) |> pull(att)
boot_summary <- bind_rows(
  summarize_diff(boot_draws$diff_procedure,
                 "UNGA-DM (r=1) minus BSV (r=2), procedure-selected",
                 obs_dm_r1 - obs_bsv_r2),
  summarize_diff(boot_draws$diff_common_r2,
                 "UNGA-DM (r=2) minus BSV (r=2), common factors",
                 obs_dm_r2 - obs_bsv_r2)
)
write_csv(boot_summary, op("ife_paired_bootstrap_summary.csv"))
print(as.data.frame(boot_summary), row.names = FALSE)

# ---------------------------------------------------------------------------
# Item 3 - Per-treated-country divergence between the outcome series
# ---------------------------------------------------------------------------
message("Computing per-country series divergence for treated units.")
divergence <- common_rows |>
  group_by(iso3c) |>
  summarise(
    treated_unit = any(china_top == 1),
    first_treated_year = if (any(china_top == 1)) {
      min(year[china_top == 1])
    } else NA_integer_,
    n_years = n(),
    cor_bsv_dm = if (n() >= 3) {
      cor(abs_distance_china, abs_distance_china_dm)
    } else NA_real_,
    mean_abs_diff = mean(abs(abs_distance_china - abs_distance_china_dm)),
    mean_bsv_pre = mean(abs_distance_china[china_top == 0]),
    mean_dm_pre = mean(abs_distance_china_dm[china_top == 0]),
    mean_bsv_treated = if (any(china_top == 1)) {
      mean(abs_distance_china[china_top == 1])
    } else NA_real_,
    mean_dm_treated = if (any(china_top == 1)) {
      mean(abs_distance_china_dm[china_top == 1])
    } else NA_real_,
    .groups = "drop"
  ) |>
  mutate(
    within_change_bsv = mean_bsv_treated - mean_bsv_pre,
    within_change_dm = mean_dm_treated - mean_dm_pre
  ) |>
  arrange(desc(treated_unit), desc(mean_abs_diff))
write_csv(divergence, op("series_divergence_by_country.csv"))
group_means <- common_rows |>
  mutate(group = if_else(iso3c %in% treated_ids, "ever-treated", "control")) |>
  group_by(group, year) |>
  summarise(
    mean_bsv = mean(abs_distance_china),
    mean_dm = mean(abs_distance_china_dm),
    .groups = "drop"
  )
write_csv(group_means, op("group_mean_series_bsv_vs_dm.csv"))

# ---------------------------------------------------------------------------
# Provenance
# ---------------------------------------------------------------------------
manifest <- tibble(
  run_date = run_date,
  audit_code_version = audit_code_version,
  elapsed_minutes = as.numeric(difftime(Sys.time(), run_started, units = "mins")),
  parallel_cores = parallel_cores,
  ife_nboots = ife_nboots,
  boot_B = boot_B,
  boot_seed = boot_seed,
  boot_failures = sum(boot_draws$status != "ok"),
  harmonized_excluded = paste(window_excluded, collapse = ";"),
  legacy_excluded = paste(legacy_excluded, collapse = ";"),
  smoke_test = smoke,
  fect_version = as.character(utils::packageVersion("fect")),
  synthdid_version = as.character(utils::packageVersion("synthdid"))
)
write_csv(manifest, op("run_manifest.csv"))
writeLines(capture.output(sessionInfo()), op("session_info.txt"))
message("Done in ", sprintf("%.1f", manifest$elapsed_minutes),
        " minutes. Outputs in ", out_dir)
