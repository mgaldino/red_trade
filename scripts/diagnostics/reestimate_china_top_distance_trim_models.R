#!/usr/bin/env Rscript

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

parse_nboots <- function(args, default = 500L) {
  nboots_arg <- args[grepl("^--nboots=", args)]
  if (length(nboots_arg) == 0L) {
    return(default)
  }
  as.integer(sub("^--nboots=", "", nboots_arg[[1]]))
}

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

make_entry_table <- function(panel) {
  panel %>%
    dplyr::arrange(iso3c, year) %>%
    dplyr::group_by(iso3c) %>%
    dplyr::mutate(
      china_top_lag = dplyr::lag(china_top),
      treatment_entry = china_top == 1L &
        !is.na(china_top_lag) &
        china_top_lag == 0L
    ) %>%
    dplyr::summarise(
      country_name = dplyr::first(stats::na.omit(country_name)),
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      first_entry_year = ifelse(
        any(treatment_entry, na.rm = TRUE),
        min(year[treatment_entry], na.rm = TRUE),
        NA_integer_
      ),
      .groups = "drop"
    ) %>%
    dplyr::filter(ever_treated, !is.na(first_entry_year))
}

make_pre_entry_distance <- function(panel, entry_table,
                                    pre_window = 5L) {
  entry_table %>%
    dplyr::select(iso3c, country_name, first_entry_year) %>%
    dplyr::left_join(
      panel %>%
        dplyr::select(iso3c, year, abs_distance_china),
      by = "iso3c"
    ) %>%
    dplyr::filter(
      year >= first_entry_year - pre_window,
      year <= first_entry_year - 1L
    ) %>%
    dplyr::group_by(iso3c, country_name, first_entry_year) %>%
    dplyr::summarise(
      pre_entry_china_distance = ifelse(
        sum(!is.na(abs_distance_china)) > 0L,
        mean(abs_distance_china, na.rm = TRUE),
        NA_real_
      ),
      n_pre_entry_rows = dplyr::n(),
      n_pre_entry_nonmissing = sum(!is.na(abs_distance_china)),
      pre_entry_years = paste(sort(year[!is.na(abs_distance_china)]), collapse = ","),
      .groups = "drop"
    ) %>%
    dplyr::mutate(complete_five_year_window = n_pre_entry_nonmissing == pre_window) %>%
    dplyr::arrange(pre_entry_china_distance, iso3c)
}

make_trim_rules <- function(pre_entry_distance) {
  threshold_source <- pre_entry_distance %>%
    dplyr::filter(complete_five_year_window, !is.na(pre_entry_china_distance))

  p75_cutoff <- stats::quantile(
    threshold_source$pre_entry_china_distance,
    probs = 0.75,
    names = FALSE,
    na.rm = TRUE
  )
  p25_cutoff <- stats::quantile(
    threshold_source$pre_entry_china_distance,
    probs = 0.25,
    names = FALSE,
    na.rm = TRUE
  )
  mean_distance <- mean(threshold_source$pre_entry_china_distance, na.rm = TRUE)
  sd_distance <- stats::sd(threshold_source$pre_entry_china_distance, na.rm = TRUE)
  two_sd_cutoff <- mean_distance + 2 * sd_distance

  list(
    threshold_source = threshold_source,
    thresholds = tibble::tibble(
      trim_rule = c(
        "Original",
        "Exclude treated below p25 pre-entry China distance",
        "Exclude treated above p75 pre-entry China distance",
        "Exclude treated outside p25-p75 pre-entry China distance",
        "Exclude treated above mean + 2sd pre-entry China distance"
      ),
      cutoff_value = c(NA_real_, p25_cutoff, p75_cutoff, NA_real_, two_sd_cutoff),
      lower_cutoff_value = c(NA_real_, p25_cutoff, NA_real_, p25_cutoff, NA_real_),
      upper_cutoff_value = c(NA_real_, NA_real_, p75_cutoff, p75_cutoff, two_sd_cutoff),
      threshold_mean = c(
        NA_real_,
        mean_distance,
        mean_distance,
        mean_distance,
        mean_distance
      ),
      threshold_sd = c(
        NA_real_,
        sd_distance,
        sd_distance,
        sd_distance,
        sd_distance
      ),
      n_threshold_treated = c(
        NA_integer_,
        nrow(threshold_source),
        nrow(threshold_source),
        nrow(threshold_source),
        nrow(threshold_source)
      )
    ),
    exclusions = dplyr::bind_rows(
      threshold_source %>%
        dplyr::filter(pre_entry_china_distance < p25_cutoff) %>%
        dplyr::mutate(
          trim_rule = "Exclude treated below p25 pre-entry China distance",
          cutoff_value = p25_cutoff,
          lower_cutoff_value = p25_cutoff,
          upper_cutoff_value = NA_real_,
          exclusion_side = "below"
        ),
      threshold_source %>%
        dplyr::filter(pre_entry_china_distance > p75_cutoff) %>%
        dplyr::mutate(
          trim_rule = "Exclude treated above p75 pre-entry China distance",
          cutoff_value = p75_cutoff,
          lower_cutoff_value = NA_real_,
          upper_cutoff_value = p75_cutoff,
          exclusion_side = "above"
        ),
      threshold_source %>%
        dplyr::filter(
          pre_entry_china_distance < p25_cutoff |
            pre_entry_china_distance > p75_cutoff
        ) %>%
        dplyr::mutate(
          trim_rule = "Exclude treated outside p25-p75 pre-entry China distance",
          cutoff_value = NA_real_,
          lower_cutoff_value = p25_cutoff,
          upper_cutoff_value = p75_cutoff,
          exclusion_side = dplyr::if_else(
            pre_entry_china_distance < p25_cutoff,
            "below",
            "above"
          )
        ),
      threshold_source %>%
        dplyr::filter(pre_entry_china_distance > two_sd_cutoff) %>%
        dplyr::mutate(
          trim_rule = "Exclude treated above mean + 2sd pre-entry China distance",
          cutoff_value = two_sd_cutoff,
          lower_cutoff_value = NA_real_,
          upper_cutoff_value = two_sd_cutoff,
          exclusion_side = "above"
        )
    ) %>%
      dplyr::select(
        trim_rule,
        cutoff_value,
        lower_cutoff_value,
        upper_cutoff_value,
        exclusion_side,
        iso3c,
        country_name,
        first_entry_year,
        pre_entry_china_distance,
        n_pre_entry_nonmissing,
        pre_entry_years
      )
  )
}

fit_one_model <- function(panel_cov, trim_rule, cutoff_value,
                          lower_cutoff_value, upper_cutoff_value,
                          excluded_iso3c,
                          nboots, fml) {
  message("Estimating: ", trim_rule)

  sample_panel <- panel_cov %>%
    dplyr::filter(!iso3c %in% excluded_iso3c)

  fit <- tryCatch(
    run_fect_analysis(
      sample_panel,
      method = "ife",
      nboots = nboots,
      fml = fml
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      trim_rule = trim_rule,
      status = "error",
      error_message = conditionMessage(fit),
      nboots = nboots,
      cutoff_value = cutoff_value,
      lower_cutoff_value = lower_cutoff_value,
      upper_cutoff_value = upper_cutoff_value,
      n_excluded_treated = length(excluded_iso3c),
      excluded_iso3c = paste(excluded_iso3c, collapse = ";"),
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      r_cv = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      n_treated = NA_integer_,
      n_control = NA_integer_,
      n_entries = NA_integer_,
      n_exits = NA_integer_,
      panel_min = NA_integer_,
      panel_max = NA_integer_
    ))
  }

  model_summary <- summarize_fect_model(fit, sample_panel, fml = fml)

  tibble::as_tibble(model_summary) %>%
    dplyr::mutate(
      trim_rule = trim_rule,
      status = "ok",
      error_message = NA_character_,
      nboots = nboots,
      cutoff_value = cutoff_value,
      lower_cutoff_value = lower_cutoff_value,
      upper_cutoff_value = upper_cutoff_value,
      n_excluded_treated = length(excluded_iso3c),
      excluded_iso3c = paste(excluded_iso3c, collapse = ";"),
      .before = att
    )
}

write_report <- function(output_dir, model_results, thresholds, exclusions,
                         pre_entry_distance, nboots, fml) {
  incomplete_windows <- pre_entry_distance %>%
    dplyr::filter(!complete_five_year_window)

  result_lines <- model_results %>%
    dplyr::mutate(
      line = paste0(
        "- ", trim_rule,
        ": ATT = ", format_num(att),
        ", SE = ", format_num(se),
        ", 95% CI [", format_num(ci_lo), ", ", format_num(ci_hi), "]",
        ", p = ", format_num(p),
        ", r* = ", format_num(r_cv, 0L),
        ", countries = ", n_countries,
        ", treated = ", n_treated,
        ", controls = ", n_control,
        ", excluded treated = ", n_excluded_treated
      )
    ) %>%
    dplyr::pull(line)

  exclusion_lines <- exclusions %>%
    dplyr::arrange(trim_rule, dplyr::desc(pre_entry_china_distance), iso3c) %>%
    dplyr::mutate(
      line = paste0(
        "- ", trim_rule, " [", exclusion_side, "]: ", iso3c, " (",
        country_name, "), entry ", first_entry_year,
        ", pre-entry distance = ",
        format_num(pre_entry_china_distance)
      )
    ) %>%
    dplyr::pull(line)

  if (length(exclusion_lines) == 0L) {
    exclusion_lines <- "- No treated countries excluded by these cutoffs."
  }

  report_lines <- c(
    "# China top-partner fect IFE reestimation with treated-distance trims",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("Bootstrap replications: ", nboots),
    paste0("Formula: `", paste(deparse(fml), collapse = " "), "`"),
    "",
    "## Sample and treatment definition",
    "",
    paste0(
      "The base sample includes countries observed in both the trade data and ",
      "the UNGA ideal-point data, excluding China and countries where China ",
      "was already observed as the rank-1 export destination before 2000. ",
      "Treatment equals one only in treated periods after China becomes the ",
      "country's rank-1 export destination with onset in or after 2000 and ",
      "after an observed prior year in which China was not rank 1. Treatment ",
      "can turn off if China loses the top export-destination position."
    ),
    "",
    "Distance-based trimming is applied only to treated countries. Controls are not removed by the distance rule. The trimming variable is each treated country's mean absolute UNGA ideal-point distance to China in the five years before its first treatment entry.",
    "",
    "## Thresholds",
    "",
    paste0(
      "- P25 cutoff among treated countries with complete five-year windows: ",
      format_num(thresholds$cutoff_value[thresholds$trim_rule == "Exclude treated below p25 pre-entry China distance"])
    ),
    paste0(
      "- P75 cutoff among treated countries with complete five-year windows: ",
      format_num(thresholds$cutoff_value[thresholds$trim_rule == "Exclude treated above p75 pre-entry China distance"])
    ),
    paste0(
      "- Mean + 2sd cutoff among treated countries with complete five-year windows: ",
      format_num(thresholds$cutoff_value[thresholds$trim_rule == "Exclude treated above mean + 2sd pre-entry China distance"])
    ),
    paste0(
      "- Treated countries with incomplete five-year windows: ",
      nrow(incomplete_windows)
    ),
    "",
    "## Model Results",
    "",
    result_lines,
    "",
    "## Excluded Treated Countries",
    "",
    exclusion_lines,
    "",
    "## Output files",
    "",
    "- `quality_reports/cross_country_sample/china_top_distance_trim_model_results.csv`",
    "- `quality_reports/cross_country_sample/china_top_distance_trim_thresholds.csv`",
    "- `quality_reports/cross_country_sample/china_top_distance_trim_exclusions.csv`",
    "- `quality_reports/cross_country_sample/china_top_pre_entry_distance_by_treated_country.csv`"
  )

  writeLines(
    report_lines,
    con = file.path(output_dir, "china_top_distance_trim_model_report.md"),
    useBytes = TRUE
  )
}

args <- commandArgs(trailingOnly = TRUE)
nboots <- parse_nboots(args)

set.seed(42)

output_dir <- "quality_reports/cross_country_sample"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

min_year <- 1990L
min_entry_year <- 2000L
pre_window <- 5L
fml <- abs_distance_china ~ china_top + log_gdp_pc + free_press

message("Loading target inputs...")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
covariates_panel <- targets::tar_read(covariates_panel)

message("Building corrected China top-partner panel from target inputs...")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = min_entry_year,
  exclude_pre_min_entry_china_top = TRUE
)

panel_cov <- china_top_panel %>%
  dplyr::left_join(covariates_panel, by = c("iso3c", "year"))

entry_table <- make_entry_table(china_top_panel)
pre_entry_distance <- make_pre_entry_distance(
  panel = china_top_panel,
  entry_table = entry_table,
  pre_window = pre_window
)
trim_rules <- make_trim_rules(pre_entry_distance)

p75_excluded <- trim_rules$exclusions %>%
  dplyr::filter(trim_rule == "Exclude treated above p75 pre-entry China distance") %>%
  dplyr::pull(iso3c)

p25_excluded <- trim_rules$exclusions %>%
  dplyr::filter(trim_rule == "Exclude treated below p25 pre-entry China distance") %>%
  dplyr::pull(iso3c)

middle_50_excluded <- trim_rules$exclusions %>%
  dplyr::filter(trim_rule == "Exclude treated outside p25-p75 pre-entry China distance") %>%
  dplyr::pull(iso3c)

two_sd_excluded <- trim_rules$exclusions %>%
  dplyr::filter(trim_rule == "Exclude treated above mean + 2sd pre-entry China distance") %>%
  dplyr::pull(iso3c)

get_threshold <- function(rule_name, column) {
  trim_rules$thresholds %>%
    dplyr::filter(.data$trim_rule == rule_name) %>%
    dplyr::pull(.data[[column]])
}

model_specs <- list(
  list(
    trim_rule = "Original",
    cutoff_value = NA_real_,
    lower_cutoff_value = NA_real_,
    upper_cutoff_value = NA_real_,
    excluded_iso3c = character()
  ),
  list(
    trim_rule = "Exclude treated below p25 pre-entry China distance",
    cutoff_value = get_threshold(
      "Exclude treated below p25 pre-entry China distance",
      "cutoff_value"
    ),
    lower_cutoff_value = get_threshold(
      "Exclude treated below p25 pre-entry China distance",
      "lower_cutoff_value"
    ),
    upper_cutoff_value = get_threshold(
      "Exclude treated below p25 pre-entry China distance",
      "upper_cutoff_value"
    ),
    excluded_iso3c = p25_excluded
  ),
  list(
    trim_rule = "Exclude treated above p75 pre-entry China distance",
    cutoff_value = get_threshold(
      "Exclude treated above p75 pre-entry China distance",
      "cutoff_value"
    ),
    lower_cutoff_value = get_threshold(
      "Exclude treated above p75 pre-entry China distance",
      "lower_cutoff_value"
    ),
    upper_cutoff_value = get_threshold(
      "Exclude treated above p75 pre-entry China distance",
      "upper_cutoff_value"
    ),
    excluded_iso3c = p75_excluded
  ),
  list(
    trim_rule = "Exclude treated outside p25-p75 pre-entry China distance",
    cutoff_value = get_threshold(
      "Exclude treated outside p25-p75 pre-entry China distance",
      "cutoff_value"
    ),
    lower_cutoff_value = get_threshold(
      "Exclude treated outside p25-p75 pre-entry China distance",
      "lower_cutoff_value"
    ),
    upper_cutoff_value = get_threshold(
      "Exclude treated outside p25-p75 pre-entry China distance",
      "upper_cutoff_value"
    ),
    excluded_iso3c = middle_50_excluded
  ),
  list(
    trim_rule = "Exclude treated above mean + 2sd pre-entry China distance",
    cutoff_value = get_threshold(
      "Exclude treated above mean + 2sd pre-entry China distance",
      "cutoff_value"
    ),
    lower_cutoff_value = get_threshold(
      "Exclude treated above mean + 2sd pre-entry China distance",
      "lower_cutoff_value"
    ),
    upper_cutoff_value = get_threshold(
      "Exclude treated above mean + 2sd pre-entry China distance",
      "upper_cutoff_value"
    ),
    excluded_iso3c = two_sd_excluded
  )
)

model_results <- dplyr::bind_rows(lapply(
  model_specs,
  function(spec) {
    fit_one_model(
      panel_cov = panel_cov,
      trim_rule = spec$trim_rule,
      cutoff_value = spec$cutoff_value,
      lower_cutoff_value = spec$lower_cutoff_value,
      upper_cutoff_value = spec$upper_cutoff_value,
      excluded_iso3c = spec$excluded_iso3c,
      nboots = nboots,
      fml = fml
    )
  }
))

readr::write_csv(
  model_results,
  file.path(output_dir, "china_top_distance_trim_model_results.csv")
)
readr::write_csv(
  trim_rules$thresholds,
  file.path(output_dir, "china_top_distance_trim_thresholds.csv")
)
readr::write_csv(
  trim_rules$exclusions,
  file.path(output_dir, "china_top_distance_trim_exclusions.csv")
)
readr::write_csv(
  pre_entry_distance,
  file.path(output_dir, "china_top_pre_entry_distance_by_treated_country.csv")
)

write_report(
  output_dir = output_dir,
  model_results = model_results,
  thresholds = trim_rules$thresholds,
  exclusions = trim_rules$exclusions,
  pre_entry_distance = pre_entry_distance,
  nboots = nboots,
  fml = fml
)

print(model_results %>%
        dplyr::select(
          trim_rule,
          status,
          att,
          se,
          ci_lo,
          ci_hi,
          p,
          r_cv,
          n_countries,
          n_treated,
          n_control,
          n_excluded_treated,
          excluded_iso3c
        ))

cat("\nReport written to: ",
    file.path(output_dir, "china_top_distance_trim_model_report.md"),
    "\n",
    sep = "")
