options(scipen = 999)

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(readr)
})

source("scripts/functions.R")

tar_config_set(store = "_targets")
tar_load(c(
  treatment_events,
  unga_data,
  final_df,
  classified_events,
  usa_top_countries,
  did_results,
  did_displaced_usa
))

summarize_baseline <- function() {
  bind_rows(
    tibble(
      specification = "Baseline target: all events (~1)",
      overall_att = did_results$overall_att$overall.att,
      overall_se = did_results$overall_att$overall.se,
      p_value = 2 * pnorm(-abs(did_results$overall_att$overall.att / did_results$overall_att$overall.se))
    ),
    tibble(
      specification = "Baseline target: USA displaced (~1)",
      overall_att = did_displaced_usa$overall_att$overall.att,
      overall_se = did_displaced_usa$overall_att$overall.se,
      p_value = 2 * pnorm(-abs(did_displaced_usa$overall_att$overall.att / did_displaced_usa$overall_att$overall.se))
    )
  )
}

run_spec <- function(var_names, spec_label) {
  covariates_df <- final_df %>%
    mutate(log_gdp_pc = log(gdp_cur / pop)) %>%
    dplyr::select(iso3c, year, dplyr::all_of(var_names)) %>%
    tidyr::drop_na()

  event_cov <- prepare_event_study_data(
    treatment_events = treatment_events,
    unga_data = unga_data,
    covariates_df = covariates_df
  )

  event_cov_usa <- filter_usa_top_control(
    event_data = event_cov,
    classified_events = classified_events,
    usa_top_countries = usa_top_countries
  )

  xformla <- as.formula(paste("~", paste(var_names, collapse = " + ")))

  estimate_one <- function(data, flavor) {
    n_treated <- dplyr::n_distinct(data$iso3c[data$first_treat > 0])
    n_control <- dplyr::n_distinct(data$iso3c[data$first_treat == 0])

    if (n_treated == 0 || n_control == 0) {
      return(tibble(
        specification = spec_label,
        sample = flavor,
        covariates = paste(var_names, collapse = " + "),
        n_units = dplyr::n_distinct(data$iso3c),
        n_treated = n_treated,
        n_control = n_control,
        n_obs = nrow(data),
        overall_att = NA_real_,
        overall_se = NA_real_,
        p_value = NA_real_,
        status = "skipped: no treated or no controls"
      ))
    }

    fit <- did::att_gt(
      yname = "abs_distance_china",
      tname = "year",
      idname = "id",
      gname = "first_treat",
      xformla = xformla,
      data = as.data.frame(data),
      control_group = "nevertreated",
      base_period = "universal"
    )

    overall <- tryCatch(
      did::aggte(fit, type = "simple", na.rm = TRUE),
      error = function(e) e
    )

    if (inherits(overall, "error")) {
      tibble(
        specification = spec_label,
        sample = flavor,
        covariates = paste(var_names, collapse = " + "),
        n_units = dplyr::n_distinct(data$iso3c),
        n_treated = n_treated,
        n_control = n_control,
        n_obs = nrow(data),
        overall_att = NA_real_,
        overall_se = NA_real_,
        p_value = NA_real_,
        status = paste("error:", overall$message)
      )
    } else {
      tibble(
        specification = spec_label,
        sample = flavor,
        covariates = paste(var_names, collapse = " + "),
        n_units = dplyr::n_distinct(data$iso3c),
        n_treated = n_treated,
        n_control = n_control,
        n_obs = nrow(data),
        overall_att = overall$overall.att,
        overall_se = overall$overall.se,
        p_value = 2 * pnorm(-abs(overall$overall.att / overall$overall.se)),
        status = "ok"
      )
    }
  }

  bind_rows(
    estimate_one(event_cov, "all_events"),
    estimate_one(event_cov_usa, "usa_displaced")
  )
}

specs <- list(
  list(vars = c("log_gdp_pc"), label = "Covariates spec 1"),
  list(vars = c("log_gdp_pc", "gpi"), label = "Covariates spec 2"),
  list(vars = c("log_gdp_pc", "gpi", "us_power_gap"), label = "Covariates spec 3"),
  list(vars = c("log_gdp_pc", "gpi", "us_power_gap", "distance_us", "hog_left"), label = "Covariates spec 4 (full)")
)

cov_results <- bind_rows(lapply(specs, function(s) run_spec(s$vars, s$label)))
baseline_results <- summarize_baseline()

dir.create("quality_reports", showWarnings = FALSE, recursive = TRUE)
write_csv(cov_results, "quality_reports/did_with_covariates_outside_targets.csv")
write_csv(baseline_results, "quality_reports/did_baseline_targets_reference.csv")

cat("\n=== Baseline (from targets, ~1) ===\n")
print(baseline_results)
cat("\n=== Covariate specs (outside targets) ===\n")
print(cov_results)
cat("\nSaved:\n")
cat("- quality_reports/did_with_covariates_outside_targets.csv\n")
cat("- quality_reports/did_baseline_targets_reference.csv\n")
