#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

extract_scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_real_)
  }
  value <- suppressWarnings(as.numeric(x[[1]]))
  ifelse(is.na(value), NA_real_, value)
}

safe_pretest <- function(att_gt_object) {
  tibble::tibble(
    pretest_wald_stat = extract_scalar_or_na(att_gt_object$W),
    pretest_p = extract_scalar_or_na(att_gt_object$Wpval)
  )
}

estimate_cs <- function(event_data, label, xformla) {
  message("Estimating C&S: ", label)
  set.seed(42)

  result <- run_cross_country_did(
    event_data,
    xformla = xformla,
    aggte_na_rm = TRUE
  )

  list(label = label, event_data = event_data, result = result)
}

make_dynamic_diagnostics <- function(estimate) {
  event_study <- estimate$result$event_study
  support <- estimate$event_data %>%
    dplyr::filter(first_treat > 0) %>%
    dplyr::mutate(event_time = year - first_treat) %>%
    dplyr::distinct(iso3c, first_treat, event_time) %>%
    dplyr::count(event_time, name = "n_treated_units_observed")

  tibble::tibble(
    model = estimate$label,
    event_time = event_study$egt,
    att = event_study$att.egt,
    se = event_study$se.egt,
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se,
    p = 2 * stats::pnorm(-abs(att / se)),
    period = dplyr::case_when(
      event_time < 0 ~ "pre",
      event_time == 0 ~ "entry",
      event_time > 0 ~ "post"
    )
  ) %>%
    dplyr::left_join(support, by = "event_time") %>%
    dplyr::arrange(model, event_time)
}

make_pretrend_summary <- function(estimate, dynamic_diagnostics,
                                  near_window = -5:-2) {
  pretest <- safe_pretest(estimate$result$att_gt)

  near_pre <- dynamic_diagnostics %>%
    dplyr::filter(model == estimate$label, event_time %in% near_window)

  all_pre <- dynamic_diagnostics %>%
    dplyr::filter(model == estimate$label, event_time < 0)

  post_window <- dynamic_diagnostics %>%
    dplyr::filter(model == estimate$label, event_time %in% 0:5)

  tibble::tibble(
    model = estimate$label,
    n_obs = nrow(estimate$event_data),
    n_countries = dplyr::n_distinct(estimate$event_data$iso3c),
    n_treated = dplyr::n_distinct(estimate$event_data$iso3c[
      estimate$event_data$first_treat > 0
    ]),
    n_control = dplyr::n_distinct(estimate$event_data$iso3c[
      estimate$event_data$first_treat == 0
    ]),
    panel_min = min(estimate$event_data$year, na.rm = TRUE),
    panel_max = max(estimate$event_data$year, na.rm = TRUE),
    first_treat_min = min(
      estimate$event_data$first_treat[estimate$event_data$first_treat > 0],
      na.rm = TRUE
    ),
    first_treat_max = max(
      estimate$event_data$first_treat[estimate$event_data$first_treat > 0],
      na.rm = TRUE
    ),
    pretest_wald_stat = pretest$pretest_wald_stat,
    pretest_p = pretest$pretest_p,
    near_pre_min_event_time = min(near_pre$event_time, na.rm = TRUE),
    near_pre_max_event_time = max(near_pre$event_time, na.rm = TRUE),
    near_pre_mean_att = mean(near_pre$att, na.rm = TRUE),
    near_pre_max_abs_att = max(abs(near_pre$att), na.rm = TRUE),
    near_pre_min_p = min(near_pre$p, na.rm = TRUE),
    near_pre_n_p_below_005 = sum(near_pre$p < 0.05, na.rm = TRUE),
    near_pre_n_p_below_010 = sum(near_pre$p < 0.10, na.rm = TRUE),
    all_pre_min_p = min(all_pre$p, na.rm = TRUE),
    all_pre_n_p_below_005 = sum(all_pre$p < 0.05, na.rm = TRUE),
    all_pre_n_p_below_010 = sum(all_pre$p < 0.10, na.rm = TRUE),
    post_0_5_mean_att = mean(post_window$att, na.rm = TRUE),
    post_0_5_min_p = min(post_window$p, na.rm = TRUE)
  )
}

make_group_size_table <- function(event_data, label) {
  event_data %>%
    dplyr::filter(first_treat > 0) %>%
    dplyr::distinct(iso3c, first_treat) %>%
    dplyr::mutate(
      model = label,
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      )
    ) %>%
    dplyr::count(model, first_treat, name = "n_treated_countries") %>%
    dplyr::arrange(model, first_treat)
}

write_report <- function(output_dir, pretrend_summary,
                         dynamic_window, group_sizes) {
  summary_lines <- pretrend_summary %>%
    dplyr::mutate(
      pretest_text = dplyr::if_else(
        is.na(pretest_p),
        "formal pre-test unavailable/NA",
        paste0("formal pre-test p = ", format_num(pretest_p))
      ),
      line = paste0(
        "- ", model,
        ": ", pretest_text,
        "; near-pre mean ATT = ", format_num(near_pre_mean_att),
        "; max |ATT| in leads -5:-2 = ", format_num(near_pre_max_abs_att),
        "; min lead p in -5:-2 = ", format_num(near_pre_min_p),
        "; significant leads at 5% in -5:-2 = ", near_pre_n_p_below_005,
        "; post 0:5 mean ATT = ", format_num(post_0_5_mean_att)
      )
    ) %>%
    dplyr::pull(line)

  dynamic_lines <- dynamic_window %>%
    dplyr::mutate(
      line = paste0(
        "- ", model, ", event time ", event_time,
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", p = ", format_num(p),
        ", treated units observed = ", n_treated_units_observed
      )
    ) %>%
    dplyr::pull(line)

  group_lines <- group_sizes %>%
    dplyr::mutate(
      line = paste0(
        "- ", model, ", cohort ", first_treat,
        ": ", n_treated_countries, " treated countries"
      )
    ) %>%
    dplyr::pull(line)

  report_lines <- c(
    "# C&S absorbing-treatment pretrend diagnostics",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "This diagnostic uses the corrected broad China-top sample and then restricts the C&S estimator to absorbing treated countries plus never-treated controls. The near-pre period is event times -5 to -2. Event time -1 is the universal baseline and has ATT equal to zero by construction.",
    "",
    "## Summary",
    "",
    summary_lines,
    "",
    "## Event-window estimates",
    "",
    dynamic_lines,
    "",
    "## Treated cohort sizes",
    "",
    group_lines,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_pretrend_summary.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_pretrend_dynamic.csv`",
    "- `quality_reports/cross_country_sample/china_top_absorbing_cs_pretrend_group_sizes.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_absorbing_cs_pretrend_report.md"),
    useBytes = TRUE
  )
}

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_year <- 1990L
min_entry_year <- 2000L
covariates <- c("log_gdp_pc", "free_press")

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Building corrected broad China-top partner panel...")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = min_entry_year
)

panel_cov <- china_top_panel %>%
  dplyr::left_join(covariates_panel, by = c("iso3c", "year"))

cs_data <- prepare_absorbing_china_top_did_data(
  china_top_panel,
  min_entry_year = min_entry_year
)

cs_cov_data <- prepare_absorbing_china_top_did_data(
  panel_cov,
  covariate_cols = covariates,
  min_entry_year = min_entry_year
)

estimates <- list(
  estimate_cs(cs_data, "No covariates", ~1),
  estimate_cs(cs_cov_data, "log_gdp_pc + free_press", ~ log_gdp_pc + free_press)
)

dynamic_diagnostics <- dplyr::bind_rows(lapply(estimates, make_dynamic_diagnostics))

pretrend_summary <- dplyr::bind_rows(lapply(
  estimates,
  make_pretrend_summary,
  dynamic_diagnostics = dynamic_diagnostics
))

group_sizes <- dplyr::bind_rows(lapply(estimates, function(estimate) {
  make_group_size_table(estimate$event_data, estimate$label)
}))

dynamic_window <- dynamic_diagnostics %>%
  dplyr::filter(event_time >= -5, event_time <= 10)

readr::write_csv(
  pretrend_summary,
  file.path(output_dir, "china_top_absorbing_cs_pretrend_summary.csv")
)
readr::write_csv(
  dynamic_diagnostics,
  file.path(output_dir, "china_top_absorbing_cs_pretrend_dynamic.csv")
)
readr::write_csv(
  group_sizes,
  file.path(output_dir, "china_top_absorbing_cs_pretrend_group_sizes.csv")
)

write_report(
  output_dir = output_dir,
  pretrend_summary = pretrend_summary,
  dynamic_window = dynamic_window,
  group_sizes = group_sizes
)

print(pretrend_summary %>%
        dplyr::select(
          model,
          n_countries,
          n_treated,
          n_control,
          pretest_wald_stat,
          pretest_p,
          near_pre_mean_att,
          near_pre_max_abs_att,
          near_pre_min_p,
          near_pre_n_p_below_005,
          post_0_5_mean_att,
          post_0_5_min_p
        ))

message(
  "Wrote report to ",
  file.path(output_dir, "china_top_absorbing_cs_pretrend_report.md")
)
