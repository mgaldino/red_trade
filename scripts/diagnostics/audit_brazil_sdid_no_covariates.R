#!/usr/bin/env Rscript

# Brazil SDiD WITHOUT covariates: full diagnostic package for the preferred
# specification (manuscript Table 2/3 inputs and appendix tables).
#
# Motivation (author decision, 2026-08-23): the previous preferred
# specification supplied unit-level fixed covariate arrays (2004-2008 means,
# 2008 institutional values, geographic distance). Those are not separately
# identified from the SDiD unit fixed effects: their coefficients are
# numerically zero (max|beta| ~ 3e-17), they forced a defensive paragraph in
# the text, and they made every placebo re-estimation roughly 60x slower.
# Dropping them changes the estimate only in the fourth decimal and leaves
# the exhaustive placebo-in-space distribution unchanged (SD 0.1310 either
# way), so inference is unaffected.
#
# The placebo SE is taken from the targets pipeline whenever the stored
# target reproduces the local fit; otherwise it is computed locally with the
# SAME replication count and seed the pipeline uses, so the number printed in
# the manuscript cannot depend on which path ran (single source of truth).
#
# Outputs mirror the schemas of
# data/processed/diagnostics/paper_v4_brazil_sdid_predetermined_core/ so the
# manuscript can switch directories without structural code changes.
# Reads existing targets; never runs targets.

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(readr)
  library(tibble); library(synthdid); library(countrycode)
})

options(scipen = 999)
run_started <- Sys.time()
run_date <- as.character(Sys.Date())
audit_code_version <- "2026-08-24-v2-no-covariates-helpers"
target_store <- "_targets"

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()
parallel_cores <- sdid_available_cores()

old_dir <- file.path("data", "processed", "diagnostics",
                     "paper_v4_brazil_sdid_predetermined_core")
out_dir <- file.path("data", "processed", "diagnostics",
                     "paper_v4_brazil_sdid_no_covariates")
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
op <- function(f) file.path(out_dir, f)

# Must mirror _targets.R (se_synth_no_time_varying_covariates).
target_replications <- 20000L

safe_tar_read <- function(n) tryCatch(
  targets::tar_read_raw(n, store = target_store),
  error = function(e) NULL)

synth_data <- safe_tar_read("synth_data")
if (is.null(synth_data)) stop("target `synth_data` unavailable.", call. = FALSE)

# ------------------------------------------------------------------ main fit
message("Fitting Brazil SDiD without covariates (1997-2015).")
fit <- sdid_fit_spec(synth_data)
main <- sdid_fit_summary_row(fit, "Preferred: no covariates")
message(sprintf("  ATT = %.6f | pre-RMSPE = %.6f", main$estimate, main$rmspe_pre))

se_info <- sdid_preferred_se(
  fit,
  target_fit = safe_tar_read("synth_fit_no_time_varying_covariates"),
  target_se = safe_tar_read("se_synth_no_time_varying_covariates"),
  target_replications = target_replications,
  cores = parallel_cores, checkpoint_dir = checkpoint_dir
)
message("  SE = ", sprintf("%.6f", se_info$se), " (", se_info$source, ")")

# --------------------------------------------------------- placebo-in-space
message("Placebo-in-space ranks (", dplyr::n_distinct(synth_data$iso3c),
        " reassignments).")
dist <- sdid_rank_distribution(synth_data, label = "no_covariates",
                               cores = parallel_cores,
                               checkpoint_dir = checkpoint_dir)
write_csv(dist, op("placebo_distribution.csv"))

bra_rmspe <- dist$rmspe_pre[dist$iso3c == "BRA"]
goods_panel <- safe_tar_read("china_top_m2_goods_panel")
if (is.null(goods_panel)) stop("target `china_top_m2_goods_panel` unavailable.",
                               call. = FALSE)
units <- sort(unique(synth_data$iso3c))
# Harmonized exclusion criterion (author decision 2026-08-23): donors with
# observed goods-only China-top status inside the 1997-2015 analysis window.
window_china_top <- goods_panel |>
  filter(china_is_top %in% TRUE, year >= 1997L, year <= 2015L,
         iso3c %in% units) |>
  distinct(iso3c) |> pull(iso3c)
excluded_units <- setdiff(window_china_top, "BRA")

ranks <- bind_rows(
  sdid_rank_inference(dist, "All valid assignments"),
  sdid_rank_inference(dist, "Exclude goods-only China-top donor assignments",
                      keep_units = setdiff(units, excluded_units)),
  sdid_rank_inference(dist, "Pre-fit RMSPE no larger than twice Brazil",
                      keep_units = dist$iso3c[dist$status == "estimated" &
                                                dist$rmspe_pre <= 2 * bra_rmspe])
)
write_csv(ranks, op("rank_inference.csv"))
print(as.data.frame(ranks), row.names = FALSE)

# ---------------------------------------------------------------- summaries
all_rank <- ranks |> slice(1)
bra_pre_mean <- synth_data |>
  filter(iso3c == "BRA", year >= 1997L, year <= 2008L) |>
  summarise(m = mean(abs_distance_china)) |> pull(m)
main_summary <- main |>
  mutate(
    rank_one_sided_negative = all_rank$rank_one_sided_negative,
    rank_two_sided_absolute = all_rank$rank_two_sided_absolute,
    rank_denominator = all_rank$denominator,
    p_rank_one_sided_negative = all_rank$p_rank_one_sided_negative,
    p_rank_two_sided_absolute = all_rank$p_rank_two_sided_absolute,
    brazil_pre_treatment_mean = bra_pre_mean,
    estimate_as_percent_of_pre_mean = 100 * estimate / bra_pre_mean,
    se_placebo = se_info$se,
    ci_95_low = estimate - stats::qnorm(0.975) * se_info$se,
    ci_95_high = estimate + stats::qnorm(0.975) * se_info$se,
    p_normal_two_sided = 2 * stats::pnorm(-abs(estimate / se_info$se)),
    se_replications = se_info$replications,
    se_seed = se_info$seed,
    source = se_info$source
  )
write_csv(main_summary, op("main_summary.csv"))

# weights (schema-compatible with the previous directory)
s <- attr(fit, "setup"); w <- attr(fit, "weights")
donors <- rownames(s$Y)[seq_len(s$N0)]
latam <- synth_data |> distinct(iso3c, latin_america)
unit_weights <- tibble(iso3c = donors, unit_weight = as.numeric(w$omega)) |>
  arrange(desc(unit_weight)) |>
  mutate(
    weight_rank = row_number(),
    country_name = countrycode::countrycode(iso3c, "iso3c", "country.name"),
    region = countrycode::countrycode(iso3c, "iso3c", "region"),
    cumulative_weight = cumsum(unit_weight),
    uniform_weight = 1 / length(donors),
    high_weight_donor = weight_rank <= 10L
  ) |>
  left_join(latam, by = "iso3c") |>
  select(weight_rank, iso3c, country_name, region, latin_america,
         unit_weight, cumulative_weight, uniform_weight, high_weight_donor)
write_csv(unit_weights, op("unit_weights.csv"))

pre_years <- as.integer(colnames(s$Y)[seq_len(s$T0)])
time_weights <- tibble(year = pre_years, time_weight = as.numeric(w$lambda)) |>
  mutate(time_weight_rank = rank(-time_weight, ties.method = "min"),
         high_time_weight = time_weight >= 0.1)
write_csv(time_weights, op("time_weights.csv"))

# balance: outcome enters the model; the other variables are descriptive only
pre <- synth_data |> filter(year >= 1997L, year <= 2008L)
bal_one <- function(v, label, role, defn) {
  dv <- pre |> filter(iso3c != "BRA") |>
    group_by(iso3c) |>
    summarise(x = mean(.data[[v]], na.rm = TRUE), .groups = "drop")
  dv <- dv[match(donors, dv$iso3c), ]
  bv <- pre |> filter(iso3c == "BRA") |>
    summarise(x = mean(.data[[v]], na.rm = TRUE)) |> pull(x)
  sv <- sum(as.numeric(w$omega) * dv$x)
  sdv <- stats::sd(dv$x)
  tibble(variable = v, label = label, role = role,
         brazil_pre_mean = bv, synthetic_pre_mean = sv,
         brazil_minus_synthetic = bv - sv,
         standardized_difference = (bv - sv) / ifelse(sdv > 0, sdv, NA_real_),
         included_in_preferred_specification = (v == "abs_distance_china"),
         value_definition = defn,
         diagnostic_scope = paste0(
           "Omega-weighted pre-treatment values; descriptive. The preferred ",
           "specification uses no covariates, so only the outcome enters ",
           "estimation."))
}
balance <- bind_rows(
  bal_one("abs_distance_china", "Absolute UNGA ideal-point distance to China",
          "Outcome", "1997-2008 mean"),
  bal_one("perc_trade_with_china", "Export share to China",
          "Descriptive covariate", "1997-2008 mean"),
  bal_one("perc_trade_with_us", "Export share to the United States",
          "Descriptive covariate", "1997-2008 mean"),
  bal_one("pci_cur", "Per-capita income", "Descriptive covariate",
          "1997-2008 mean"),
  bal_one("gpi", "Power index", "Descriptive covariate", "1997-2008 mean")
)
write_csv(balance, op("balance.csv"))

# donor sensitivity: leave-one-out for top donors + drop top 10
message("Donor sensitivity.")
top10 <- unit_weights$iso3c[seq_len(10)]
loo <- bind_rows(lapply(seq_along(top10), function(i) {
  u <- top10[i]
  f <- sdid_fit_spec(synth_data, units = setdiff(units, u))
  sdid_fit_summary_row(f, paste0("Drop ", u, " (rank ", i, ")")) |>
    mutate(removed_donors = u, n_removed_donors = 1L)
}))
drop10 <- sdid_fit_spec(synth_data, units = setdiff(units, top10)) |>
  sdid_fit_summary_row("Drop top 10 donors by weight") |>
  mutate(removed_donors = paste(top10, collapse = ";"),
         n_removed_donors = 10L)
donor_sensitivity <- bind_rows(
  main |> mutate(removed_donors = NA_character_, n_removed_donors = 0L),
  loo, drop10) |>
  mutate(
    estimate_change_vs_main = estimate - main$estimate,
    percent_change_vs_main = 100 * (estimate - main$estimate) / abs(main$estimate),
    inference = if_else(n_removed_donors == 0L,
                        "Main SE and rank reported separately",
                        "Point estimate only"))
write_csv(donor_sensitivity, op("donor_sensitivity.csv"))

# window sensitivity
message("Window sensitivity.")
windows <- list(c(1997L, 2013L), c(1997L, 2014L), c(1997L, 2015L),
                c(1997L, 2016L), c(1998L, 2015L), c(1999L, 2015L),
                c(2000L, 2015L))
window_sensitivity <- bind_rows(lapply(windows, function(wd) {
  f <- sdid_fit_spec(synth_data, year_start = wd[1], year_end = wd[2])
  preferred <- wd[1] == 1997L && wd[2] == 2015L
  lab <- paste0(wd[1], "-", wd[2], if (preferred) " preferred" else "")
  sdid_fit_summary_row(f, lab) |>
    mutate(year_start = wd[1], year_end = wd[2])
})) |>
  mutate(
    estimate_change_vs_main = estimate - main$estimate,
    percent_change_vs_main = 100 * (estimate - main$estimate) / abs(main$estimate),
    inference = if_else(
      grepl("preferred", specification),
      sprintf("%s-placebo SE and rank reported in main results",
              format(se_info$replications, big.mark = ",")),
      "Point estimate only"))
write_csv(window_sensitivity, op("window_sensitivity.csv"))

# timing placebos (already covariate-free by design)
message("Timing placebos.")
stopifnot(dir.exists(old_dir))
old_timing <- read_csv(file.path(old_dir, "timing_placebos.csv"),
                       show_col_types = FALSE)
timing <- bind_rows(lapply(seq_len(nrow(old_timing)), function(i) {
  r <- old_timing[i, ]
  f <- sdid_fit_spec(synth_data, year_end = r$year_end,
                     treat_year = r$nominal_treatment_year)
  s2 <- sdid_fit_summary_row(f, "timing")
  r |> mutate(estimate = s2$estimate,
              inference = "Point estimate only; no covariates")
}))
write_csv(timing, op("timing_placebos.csv"))

# donor China exposure: reuse exposure file (descriptive, spec-independent),
# reweight with the new omega; verify coverage instead of silently dropping.
exposure <- read_csv(file.path(old_dir, "donor_china_exposure.csv"),
                     show_col_types = FALSE)
stopifnot(all(donors %in% exposure$iso3c))
exposure_new <- exposure |>
  select(-any_of(c("unit_weight", "weight_rank", "high_weight_donor"))) |>
  left_join(unit_weights |>
              select(iso3c, unit_weight, weight_rank, high_weight_donor),
            by = "iso3c") |>
  arrange(weight_rank)
stopifnot(nrow(exposure_new) == nrow(exposure))
write_csv(exposure_new, op("donor_china_exposure.csv"))
hw <- exposure_new |> filter(high_weight_donor %in% TRUE)
top_col <- "ever_china_top_export_destination_post_treatment"
top_two_col <- "ever_china_top_two_export_destination_post_treatment"
exposure_summary <- tibble(
  n_high_weight_donors = nrow(hw),
  total_high_weight = sum(hw$unit_weight, na.rm = TRUE),
  n_high_weight_top_china_post = sum(hw[[top_col]] %in% TRUE),
  n_high_weight_top_two_china_post = sum(hw[[top_two_col]] %in% TRUE),
  weighted_share_high_weight_top_two_china_post = sum(
    hw$unit_weight[hw[[top_two_col]] %in% TRUE], na.rm = TRUE))
write_csv(exposure_summary, op("donor_china_exposure_summary.csv"))

# Latin America donor pool
message("Latin America donor pool.")
latam_units <- synth_data |> filter(latin_america) |>
  distinct(iso3c) |> pull(iso3c)
latam_fit <- sdid_fit_spec(synth_data, units = union(latam_units, "BRA"))
latam_summary <- sdid_fit_summary_row(latam_fit,
                                      "Latin America donors; no covariates") |>
  mutate(inference = "Point estimate only")
write_csv(latam_summary, op("latam_core_summary.csv"))

# provenance
manifest <- tibble(
  run_date = run_date, audit_code_version = audit_code_version,
  elapsed_minutes = as.numeric(difftime(Sys.time(), run_started, units = "mins")),
  parallel_cores = parallel_cores,
  se_replications = se_info$replications, se_seed = se_info$seed,
  se_source = se_info$source,
  estimate = main_summary$estimate, se_placebo = main_summary$se_placebo,
  p_normal_two_sided = main_summary$p_normal_two_sided,
  p_rank_one_sided_negative = main_summary$p_rank_one_sided_negative,
  p_rank_two_sided_absolute = main_summary$p_rank_two_sided_absolute,
  synthdid_version = as.character(utils::packageVersion("synthdid")))
write_csv(manifest, op("run_manifest.csv"))
writeLines(capture.output(sessionInfo()), op("session_info.txt"))
message("Done in ", sprintf("%.1f", manifest$elapsed_minutes), " min -> ", out_dir)
