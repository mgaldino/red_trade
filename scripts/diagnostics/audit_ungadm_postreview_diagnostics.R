#!/usr/bin/env Rscript

# Post-review diagnostics for the UNGA-DM measurement-robustness check,
# implementing the items requested by the independent causal review
# (quality_reports/ungadm_outcome_robustness/2026-08-23_independent_causal_review.md):
#   1. Full 2x2 fixed-r IFE grid (BSV/UNGA-DM x r = 1/2) on the common-window,
#      identical-row panel, 10,000 bootstraps each, to decompose measurement
#      change from latent-factor selection.
#   2. Paired cluster bootstrap of the ATT difference (UNGA-DM minus BSV),
#      stratified by treated/control, point fits only (se = FALSE), with the
#      procedure-selected factor numbers (DM r=1 vs BSV r=2) and a common-r
#      (both r=2) sensitivity.
#   3. Per-treated-country divergence inspection between the two outcome series.
#   4. Harmonized China-top donor-exclusion rank column for the SDiD variant
#      (exclude donors with observed China-top status within 1997-2015: MLT),
#      plus time-weights and balance exports for the UNGA-DM SDiD fit and a
#      seed note. Rank recomputation reuses the stored placebo distribution.
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
audit_code_version <- "2026-08-23-v1-postreview"
target_store <- "_targets"

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
out_path <- function(filename) file.path(out_dir, filename)

ife_nboots <- as.integer(Sys.getenv("UNGADM2_IFE_NBOOTS", "10000"))
boot_B <- as.integer(Sys.getenv("UNGADM2_BOOT_B", "1000"))
boot_seed <- 20260823L
parallel_cores <- as.integer(Sys.getenv(
  "SDID_PARALLEL_CORES",
  as.character(min(12L, parallel::detectCores(logical = FALSE)))
))
if (is.na(parallel_cores) || parallel_cores < 1L) parallel_cores <- 1L
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1"
)
if (ife_nboots < 10000L || boot_B < 1000L) {
  message("NOTE: smoke-test counts in use (nboots = ", ife_nboots,
          ", B = ", boot_B, "); final outputs require the defaults.")
}

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) stop("Could not read target `", name, "`: ",
                             conditionMessage(e), call. = FALSE)
  )
}

message("Sourcing scripts/functions.R for prepare_fect_data/fect summaries.")
source(file.path("scripts", "functions.R"))

# ---------------------------------------------------------------------------
# UNGA-DM outcome (identical construction to audit_ungadm_outcome_robustness.R)
# ---------------------------------------------------------------------------
message("Building the UNGA-DM outcome series.")
bsv_raw <- read_csv(bsv_path, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(ccode = as.integer(ccode), session = as.integer(session), iso3c)
ungadm_raw <- read_csv(ungadm_path, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(
    ccode = as.integer(ccode), session = as.integer(session),
    country_ungadm = country, q50_dm = x50
  ) %>%
  mutate(ccode = if_else(session == 45L & ccode == 255L, 260L, ccode))
dm_outcome <- ungadm_raw %>%
  left_join(bsv_raw, by = c("ccode", "session")) %>%
  filter(!is.na(iso3c)) %>%
  group_by(session) %>%
  mutate(china_ideal_dm = q50_dm[ccode == 710L][1]) %>%
  ungroup() %>%
  mutate(
    year = session + 1945L,
    abs_distance_china_dm = abs(q50_dm - china_ideal_dm)
  ) %>%
  filter(year >= 1990L) %>%
  select(iso3c, year, abs_distance_china_dm)
stopifnot(!any(duplicated(dm_outcome[, c("iso3c", "year")])))

# ---------------------------------------------------------------------------
# Item 4a - Harmonized China-top donor exclusion for the SDiD rank column
# Criterion (harmonized to the July convention): exclude donor assignments for
# SDiD-panel countries with observed goods-only China-top status in any year of
# the 1997-2015 window (m2 goods panel, china_is_top). Brazil stays (treated).
# ---------------------------------------------------------------------------
message("Recomputing the harmonized China-top exclusion rank column.")
synth_units <- unique(safe_tar_read("synth_data")$iso3c)
goods_panel <- safe_tar_read("china_top_m2_goods_panel")
window_china_top <- goods_panel %>%
  filter(china_is_top %in% TRUE, year >= 1997L, year <= 2015L,
         iso3c %in% synth_units) %>%
  distinct(iso3c) %>%
  pull(iso3c)
harmonized_excluded <- setdiff(window_china_top, "BRA")
old_excluded <- {
  m2_unit_summary <- safe_tar_read("china_top_m2_goods_status_current_unit_summary")
  m2_unit_summary %>%
    filter(min_duration_years == 5L, sample == "risk_set_restricted",
           ever_treated %in% TRUE, iso3c %in% synth_units) %>%
    pull(iso3c) %>% setdiff("BRA")
}
message("  Harmonized exclusion (window criterion): ",
        paste(harmonized_excluded, collapse = ", "),
        " | previous run excluded: ", paste(old_excluded, collapse = ", "))

dm_distribution <- read_csv(
  file.path(est_dir, "sdid_dm_placebo_distribution.csv"), show_col_types = FALSE
)
rank_from <- function(distribution, comparison_set, drop_units = character(0)) {
  valid <- distribution %>%
    filter(status == "estimated", !is.na(estimate), !iso3c %in% drop_units)
  brazil <- valid %>% filter(iso3c == "BRA")
  stopifnot(nrow(brazil) == 1L)
  tibble(
    comparison_set = comparison_set,
    excluded_units = paste(drop_units, collapse = ";"),
    rank_one_sided_negative = sum(valid$estimate <= brazil$estimate),
    rank_two_sided_absolute = sum(abs(valid$estimate) >= abs(brazil$estimate)),
    denominator = nrow(valid),
    p_rank_one_sided_negative = mean(valid$estimate <= brazil$estimate),
    p_rank_two_sided_absolute = mean(abs(valid$estimate) >= abs(brazil$estimate))
  )
}
rank_harmonized <- bind_rows(
  rank_from(dm_distribution, "All valid assignments"),
  rank_from(dm_distribution,
            "Exclude goods-only China-top donor assignments (harmonized: window criterion)",
            harmonized_excluded),
  rank_from(dm_distribution,
            "Exclude goods-only China-top donor assignments (previous run: 5y qualifying criterion)",
            old_excluded)
)
write_csv(rank_harmonized, out_path("sdid_dm_rank_inference_harmonized.csv"))
print(as.data.frame(rank_harmonized), row.names = FALSE)

# ---------------------------------------------------------------------------
# Item 4b - Time weights and balance for the UNGA-DM SDiD fit (deterministic
# refits of both variants; same construction as the estimation audit).
# ---------------------------------------------------------------------------
message("Refitting both SDiD variants for weights/balance exports.")
synth_data <- safe_tar_read("synth_data")
pre_years <- 2004:2008
frozen_means <- synth_data %>%
  filter(year %in% pre_years) %>%
  group_by(iso3c) %>%
  summarise(
    frozen_perc_trade_with_china = mean(perc_trade_with_china, na.rm = TRUE),
    frozen_perc_trade_with_us = mean(perc_trade_with_us, na.rm = TRUE),
    frozen_pci_cur = mean(pci_cur, na.rm = TRUE),
    frozen_distance_us = first(distance_us),
    frozen_inst_parliamentary = first(inst_parliamentary[year == 2008L]),
    frozen_us_trade_agreement = first(us_trade_agreement[year == 2008L]),
    .groups = "drop"
  )
predetermined_core <- c(
  "frozen_perc_trade_with_china", "frozen_perc_trade_with_us",
  "frozen_pci_cur", "frozen_distance_us", "frozen_inst_parliamentary",
  "frozen_us_trade_agreement"
)
estimation_data_bsv <- synth_data %>% left_join(frozen_means, by = "iso3c")
estimation_data_dm <- estimation_data_bsv %>%
  left_join(dm_outcome, by = c("iso3c", "year")) %>%
  mutate(abs_distance_china = abs_distance_china_dm) %>%
  select(-abs_distance_china_dm)

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
  x_array <- make_covariate_array(fit_data, covariate_cols)
  panel_data <- fit_data |>
    dplyr::mutate(
      iso3c = factor(iso3c, levels = unique(iso3c)),
      year = as.integer(year), Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0, X = x_array)
}
fit_bsv <- fit_sdid(estimation_data_bsv, predetermined_core)
fit_dm <- fit_sdid(estimation_data_dm, predetermined_core)
stopifnot(isTRUE(all.equal(
  as.numeric(fit_bsv),
  as.numeric(safe_tar_read("synth_fit_no_time_varying_covariates")),
  tolerance = 1e-8
)))

export_time_weights <- function(fit, filename) {
  setup <- attr(fit, "setup")
  lambda <- as.numeric(attr(fit, "weights")$lambda)
  years <- as.integer(colnames(setup$Y)[seq_len(setup$T0)])
  tw <- tibble(year = years, time_weight = lambda) %>%
    mutate(
      time_weight_rank = rank(-time_weight, ties.method = "min"),
      high_time_weight = time_weight >= 0.1
    )
  write_csv(tw, out_path(filename))
  tw
}
tw_dm <- export_time_weights(fit_dm, "sdid_dm_time_weights.csv")

balance_table <- function(fit, data, covariate_cols, outcome_label) {
  omega <- as.numeric(attr(fit, "weights")$omega)
  setup <- attr(fit, "setup")
  donor_order <- rownames(setup$Y)[seq_len(setup$N0)]
  pre <- data %>% filter(year >= 1997L, year <= 2008L)
  one_var <- function(varname, label, role, value_definition) {
    donor_vals <- pre %>%
      filter(iso3c != "BRA") %>%
      group_by(iso3c) %>%
      summarise(v = mean(.data[[varname]], na.rm = TRUE), .groups = "drop")
    donor_vals <- donor_vals[match(donor_order, donor_vals$iso3c), ]
    brazil_val <- pre %>%
      filter(iso3c == "BRA") %>%
      summarise(v = mean(.data[[varname]], na.rm = TRUE)) %>% pull(v)
    synth_val <- sum(omega * donor_vals$v)
    donor_sd <- sd(donor_vals$v)
    tibble(
      variable = varname, label = label, role = role,
      brazil_pre_mean = brazil_val, synthetic_pre_mean = synth_val,
      brazil_minus_synthetic = brazil_val - synth_val,
      standardized_difference = (brazil_val - synth_val) /
        ifelse(donor_sd > 0, donor_sd, NA_real_),
      value_definition = value_definition,
      diagnostic_scope = "Preferred-specification values weighted by omega; descriptive, not residualized synthdid balance"
    )
  }
  bind_rows(
    one_var("abs_distance_china", outcome_label, "Outcome", "1997-2008 mean"),
    one_var("frozen_perc_trade_with_us", "Export share to the United States",
            "Predetermined/fixed covariate", "2004-2008 mean held fixed"),
    one_var("frozen_perc_trade_with_china", "Export share to China",
            "Predetermined/fixed covariate", "2004-2008 mean held fixed"),
    one_var("frozen_pci_cur", "Per-capita income",
            "Predetermined/fixed covariate", "2004-2008 mean held fixed"),
    one_var("frozen_distance_us", "Geographic distance to Washington",
            "Predetermined/fixed covariate", "Time-invariant value held fixed"),
    one_var("frozen_inst_parliamentary", "Parliamentary system",
            "Predetermined/fixed covariate", "2008 value held fixed"),
    one_var("frozen_us_trade_agreement", "Trade agreement with the United States",
            "Predetermined/fixed covariate", "2008 value held fixed")
  )
}
write_csv(
  balance_table(fit_dm, estimation_data_dm, predetermined_core,
                "Absolute UNGA ideal-point distance to China (UNGA-DM)"),
  out_path("sdid_dm_balance.csv")
)

write_csv(
  tibble(
    note = c(
      "placebo_se_seed",
      "ranks_deterministic",
      "seed_comparability"
    ),
    detail = c(
      "UNGA-DM placebo SE uses seed 20260823 (1,000 replications); the audited BSV target se_synth_no_time_varying_covariates uses seed 20260520.",
      "Placebo-in-space ranks involve no random draws; rank columns are exactly reproducible regardless of seed.",
      "Different placebo-permutation seeds imply Monte Carlo noise of roughly 2 percent in the SE at 1,000 replications; point estimates are unaffected."
    )
  ),
  out_path("sdid_inference_notes.csv")
)

# ---------------------------------------------------------------------------
# Common-window IFE panels (identical construction to the estimation audit)
# ---------------------------------------------------------------------------
message("Rebuilding the common-window IFE panels.")
panel_bundle <- safe_tar_read("china_top_m2_goods_status_current_panel_bundle")
p5 <- panel_bundle$panels[["5"]]$risk_set_restricted
common_rows <- p5 %>%
  left_join(dm_outcome, by = c("iso3c", "year")) %>%
  filter(year <= 2020L, !is.na(abs_distance_china_dm))
panel_dm_common <- common_rows %>%
  mutate(abs_distance_china = abs_distance_china_dm) %>%
  select(-abs_distance_china_dm)
panel_bsv_common <- common_rows %>% select(-abs_distance_china_dm)
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
    cv_selected = (outcome_i == "BSV" && r_i == 2L) ||
      (outcome_i == "UNGA-DM" && r_i == 1L),
    att = s_i$att, se = s_i$se, ci_lo = s_i$ci_lo, ci_hi = s_i$ci_hi,
    p = s_i$p, att_rel_pct = s_i$att_rel_pct, att_sd_units = s_i$att_sd_units,
    n_obs = s_i$n_obs, nboots = ife_nboots
  )
  print(as.data.frame(grid_results[[i]]), row.names = FALSE)
}
grid_table <- bind_rows(grid_results)
write_csv(grid_table, out_path("ife_2x2_fixed_r.csv"))

# ---------------------------------------------------------------------------
# Item 2 - Paired cluster bootstrap of the ATT difference (point fits only)
# Stratified country resampling (treated strata = countries with any treated
# row in the common panel), identical draws applied to both outcomes.
# ---------------------------------------------------------------------------
message("Paired cluster bootstrap (B = ", boot_B, ", stratified).")
treated_units <- common_rows %>%
  group_by(iso3c) %>% summarise(t = any(china_top == 1), .groups = "drop")
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
  drawn <- draw_list[[b]]
  resampled <- lapply(seq_along(drawn), function(k) {
    common_rows %>%
      filter(iso3c == drawn[k]) %>%
      mutate(
        iso3c = paste0(drawn[k], "_", k),
        country_id = k,
        country_name = iso3c
      )
  }) %>% bind_rows()
  panel_dm_b <- resampled %>%
    mutate(abs_distance_china = abs_distance_china_dm) %>%
    select(-abs_distance_china_dm)
  panel_bsv_b <- resampled %>% select(-abs_distance_china_dm)
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
boot_draws <- bind_rows(parallel::mclapply(
  seq_len(boot_B), boot_one,
  mc.cores = parallel_cores, mc.preschedule = TRUE, mc.set.seed = FALSE
))
write_csv(boot_draws, out_path("ife_paired_bootstrap_draws.csv"))

summarize_diff <- function(x, label, observed_diff) {
  x <- x[is.finite(x)]
  tibble(
    contrast = label,
    observed_diff = observed_diff,
    boot_mean = mean(x),
    boot_sd = sd(x),
    ci_2_5 = quantile(x, 0.025),
    ci_97_5 = quantile(x, 0.975),
    p_two_sided_percentile = 2 * min(mean(x <= 0), mean(x >= 0)),
    p_two_sided_normal = 2 * stats::pnorm(-abs(observed_diff / sd(x))),
    n_valid = length(x),
    n_failed = boot_B - length(x)
  )
}
obs_bsv_r2 <- grid_table %>% filter(outcome == "BSV", r_fixed == 2L) %>% pull(att)
obs_dm_r1 <- grid_table %>% filter(outcome == "UNGA-DM", r_fixed == 1L) %>% pull(att)
obs_dm_r2 <- grid_table %>% filter(outcome == "UNGA-DM", r_fixed == 2L) %>% pull(att)
boot_summary <- bind_rows(
  summarize_diff(boot_draws$diff_procedure,
                 "UNGA-DM (r=1) minus BSV (r=2), procedure-selected",
                 obs_dm_r1 - obs_bsv_r2),
  summarize_diff(boot_draws$diff_common_r2,
                 "UNGA-DM (r=2) minus BSV (r=2), common factors",
                 obs_dm_r2 - obs_bsv_r2)
)
write_csv(boot_summary, out_path("ife_paired_bootstrap_summary.csv"))
print(as.data.frame(boot_summary), row.names = FALSE)

# ---------------------------------------------------------------------------
# Item 3 - Per-treated-country divergence between the outcome series
# ---------------------------------------------------------------------------
message("Computing per-country series divergence for treated units.")
divergence <- common_rows %>%
  group_by(iso3c) %>%
  summarise(
    treated_unit = any(china_top == 1),
    first_treated_year = ifelse(any(china_top == 1),
                                min(year[china_top == 1]), NA_integer_),
    n_years = n(),
    cor_bsv_dm = ifelse(n() >= 3,
                        cor(abs_distance_china, abs_distance_china_dm), NA_real_),
    mean_abs_diff = mean(abs(abs_distance_china - abs_distance_china_dm)),
    mean_bsv_pre = mean(abs_distance_china[china_top == 0]),
    mean_dm_pre = mean(abs_distance_china_dm[china_top == 0]),
    mean_bsv_treated = ifelse(any(china_top == 1),
                              mean(abs_distance_china[china_top == 1]), NA_real_),
    mean_dm_treated = ifelse(any(china_top == 1),
                             mean(abs_distance_china_dm[china_top == 1]), NA_real_),
    .groups = "drop"
  ) %>%
  mutate(
    within_change_bsv = mean_bsv_treated - mean_bsv_pre,
    within_change_dm = mean_dm_treated - mean_dm_pre
  ) %>%
  arrange(desc(treated_unit), mean_abs_diff * -1)
write_csv(divergence, out_path("series_divergence_by_country.csv"))
group_means <- common_rows %>%
  mutate(group = if_else(iso3c %in% treated_ids, "ever-treated", "control")) %>%
  group_by(group, year) %>%
  summarise(
    mean_bsv = mean(abs_distance_china),
    mean_dm = mean(abs_distance_china_dm),
    .groups = "drop"
  )
write_csv(group_means, out_path("group_mean_series_bsv_vs_dm.csv"))

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
  harmonized_excluded = paste(harmonized_excluded, collapse = ";"),
  previous_excluded = paste(old_excluded, collapse = ";"),
  fect_version = as.character(utils::packageVersion("fect")),
  synthdid_version = as.character(utils::packageVersion("synthdid"))
)
write_csv(manifest, out_path("run_manifest.csv"))
writeLines(capture.output(sessionInfo()), out_path("session_info.txt"))
message("Done in ", sprintf("%.1f", manifest$elapsed_minutes),
        " minutes. Outputs in ", out_dir)
