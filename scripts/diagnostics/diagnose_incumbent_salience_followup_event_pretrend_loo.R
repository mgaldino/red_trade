#!/usr/bin/env Rscript

# Follow-up diagnostics for incumbent-salience moderators:
# subgroup event studies, pretrend checks, leave-one-treated-country-out,
# hub/entrepot exclusion, and regional-power decomposition.
# Reads existing targets and diagnostic CSVs only; does not run tar_make().

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(targets)
  library(tibble)
})

source("scripts/functions.R")

report_dir <- "reports/incumbent_salience_vreeland_reuse_2026-05-19"
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

incumbent_csv <- "data/processed/diagnostics/incumbent_salience_moderators_2026-05-19.csv"
vreeland_csv <- "data/processed/diagnostics/vreeland_pre_entry_moderators_2026-05-19.csv"

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

format_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, "<0.001", sprintf("%.3f", x)))
}

markdown_table <- function(data) {
  if (nrow(data) == 0L) {
    return("_No rows._")
  }
  data_chr <- data |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
  header <- paste(names(data_chr), collapse = " | ")
  separator <- paste(rep("---", ncol(data_chr)), collapse = " | ")
  rows <- apply(data_chr, 1, function(row) paste(row, collapse = " | "))
  paste(
    c(
      paste0("| ", header, " |"),
      paste0("| ", separator, " |"),
      paste0("| ", rows, " |")
    ),
    collapse = "\n"
  )
}

scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_real_)
  }
  value <- suppressWarnings(as.numeric(x[[1]]))
  ifelse(is.na(value), NA_real_, value)
}

safe_mean <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_real_)
  }
  mean(x)
}

safe_min <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_real_)
  }
  min(x)
}

safe_max_abs <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_real_)
  }
  max(abs(x))
}

validate_unique_iso3 <- function(data, label) {
  duplicates <- data |>
    dplyr::count(iso3c, name = "n") |>
    dplyr::filter(n > 1L)
  if (nrow(duplicates) > 0L) {
    stop(label, " has duplicate iso3c rows: ", paste(duplicates$iso3c, collapse = ", "))
  }
}

estimate_cs <- function(event_data, label, subgroup, min_treated = 2L) {
  n_treated <- dplyr::n_distinct(event_data$iso3c[event_data$first_treat > 0])
  n_control <- dplyr::n_distinct(event_data$iso3c[event_data$first_treat == 0])

  if (n_treated < min_treated || n_control == 0L) {
    return(list(
      label = label,
      subgroup = subgroup,
      data = event_data,
      fit = NULL,
      status = "skipped",
      error_message = paste0(
        "Insufficient support: treated = ", n_treated,
        ", controls = ", n_control
      )
    ))
  }

  message("Estimating C&S: ", label)
  set.seed(42)
  fit <- tryCatch(
    run_cross_country_did(event_data, xformla = ~1, aggte_na_rm = TRUE),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(list(
      label = label,
      subgroup = subgroup,
      data = event_data,
      fit = NULL,
      status = "error",
      error_message = conditionMessage(fit)
    ))
  }

  list(
    label = label,
    subgroup = subgroup,
    data = event_data,
    fit = fit,
    status = "ok",
    error_message = NA_character_
  )
}

overall_row <- function(estimate) {
  data <- estimate$data
  if (!identical(estimate$status, "ok")) {
    return(tibble::tibble(
      model = estimate$label,
      subgroup = estimate$subgroup,
      status = estimate$status,
      error_message = estimate$error_message,
      att = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_obs = nrow(data),
      n_countries = dplyr::n_distinct(data$iso3c),
      n_treated = dplyr::n_distinct(data$iso3c[data$first_treat > 0]),
      n_control = dplyr::n_distinct(data$iso3c[data$first_treat == 0])
    ))
  }

  overall <- estimate$fit$overall_att
  att <- unname(overall$overall.att)
  se <- unname(overall$overall.se)
  tibble::tibble(
    model = estimate$label,
    subgroup = estimate$subgroup,
    status = "ok",
    error_message = NA_character_,
    att = att,
    se = se,
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se,
    p = 2 * stats::pnorm(-abs(att / se)),
    n_obs = nrow(data),
    n_countries = dplyr::n_distinct(data$iso3c),
    n_treated = dplyr::n_distinct(data$iso3c[data$first_treat > 0]),
    n_control = dplyr::n_distinct(data$iso3c[data$first_treat == 0])
  )
}

dynamic_rows <- function(estimate) {
  if (!identical(estimate$status, "ok")) {
    return(tibble::tibble())
  }

  event_study <- estimate$fit$event_study
  support <- estimate$data |>
    dplyr::filter(first_treat > 0) |>
    dplyr::mutate(event_time = year - first_treat) |>
    dplyr::distinct(iso3c, first_treat, event_time) |>
    dplyr::count(event_time, name = "n_treated_units_observed")

  tibble::tibble(
    model = estimate$label,
    subgroup = estimate$subgroup,
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
  ) |>
    dplyr::left_join(support, by = "event_time") |>
    dplyr::arrange(model, event_time)
}

pretrend_row <- function(estimate, dynamic_data, near_window = -5:-2) {
  data <- estimate$data
  model_dynamic <- dynamic_data |>
    dplyr::filter(model == estimate$label)
  near_pre <- model_dynamic |>
    dplyr::filter(event_time %in% near_window)
  all_pre <- model_dynamic |>
    dplyr::filter(event_time < 0)
  post_0_5 <- model_dynamic |>
    dplyr::filter(event_time %in% 0:5)

  tibble::tibble(
    model = estimate$label,
    subgroup = estimate$subgroup,
    status = estimate$status,
    error_message = estimate$error_message,
    n_obs = nrow(data),
    n_countries = dplyr::n_distinct(data$iso3c),
    n_treated = dplyr::n_distinct(data$iso3c[data$first_treat > 0]),
    n_control = dplyr::n_distinct(data$iso3c[data$first_treat == 0]),
    pretest_wald_stat = if (identical(estimate$status, "ok")) {
      scalar_or_na(estimate$fit$att_gt$W)
    } else {
      NA_real_
    },
    pretest_p = if (identical(estimate$status, "ok")) {
      scalar_or_na(estimate$fit$att_gt$Wpval)
    } else {
      NA_real_
    },
    near_pre_mean_att = safe_mean(near_pre$att),
    near_pre_max_abs_att = safe_max_abs(near_pre$att),
    near_pre_min_p = safe_min(near_pre$p),
    near_pre_n_p_below_005 = sum(near_pre$p < 0.05, na.rm = TRUE),
    all_pre_n_p_below_005 = sum(all_pre$p < 0.05, na.rm = TRUE),
    post_0_5_mean_att = safe_mean(post_0_5$att)
  )
}

make_subgroup_data <- function(data, group_var, group_value) {
  keep_treated <- data |>
    dplyr::filter(first_treat > 0, .data[[group_var]] == group_value) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c)

  data |>
    dplyr::filter(first_treat == 0 | iso3c %in% keep_treated)
}

treated_country_table <- function(data, group_var = NULL, group_value = NULL,
                                  model = "baseline") {
  out <- data |>
    dplyr::filter(first_treat > 0) |>
    dplyr::distinct(
      iso3c,
      country_name,
      first_treat_year,
      displaced_partner,
      displaced_partner_name,
      hub_entrepot_incumbent,
      displacement_salience_warning,
      regional_power_decomposition
    )

  if (!is.null(group_var)) {
    out <- out |>
      dplyr::filter(.data[[group_var]] == group_value)
  }

  out |>
    dplyr::mutate(model = model, .before = iso3c) |>
    dplyr::arrange(model, first_treat_year, iso3c)
}

run_leave_one_out <- function(data) {
  base <- estimate_cs(data, "Baseline C&S", "all")
  base_row <- overall_row(base) |>
    dplyr::mutate(
      excluded_iso3c = NA_character_,
      excluded_country_name = NA_character_,
      excluded_first_treat = NA_real_,
      .before = status
    )

  treated_units <- data |>
    dplyr::filter(first_treat > 0) |>
    dplyr::distinct(iso3c, country_name, first_treat) |>
    dplyr::arrange(first_treat, iso3c)

  loo <- dplyr::bind_rows(lapply(seq_len(nrow(treated_units)), function(i) {
    unit <- treated_units[i, ]
    estimate <- estimate_cs(
      data |> dplyr::filter(iso3c != unit$iso3c),
      paste0("Drop ", unit$iso3c),
      "leave_one_out"
    )
    overall_row(estimate) |>
      dplyr::mutate(
        excluded_iso3c = unit$iso3c,
        excluded_country_name = unit$country_name,
        excluded_first_treat = unit$first_treat,
        .before = status
      )
  }))

  dplyr::bind_rows(base_row, loo) |>
    dplyr::mutate(
      base_att = base_row$att[[1]],
      delta_att = att - base_att,
      abs_delta_att = abs(delta_att)
    ) |>
    dplyr::arrange(dplyr::desc(abs_delta_att))
}

make_display <- function(data) {
  data |>
    dplyr::mutate(
      att = format_num(att),
      se = format_num(se),
      ci = paste0("[", format_num(ci_lo), ", ", format_num(ci_hi), "]"),
      p = format_p(p)
    )
}

message("Loading existing target and diagnostic CSVs.")
analysis_data <- targets::tar_read(china_top_absorbing_sample) |>
  tibble::as_tibble()
incumbent <- readr::read_csv(incumbent_csv, show_col_types = FALSE)
vreeland <- readr::read_csv(vreeland_csv, show_col_types = FALSE)

validate_unique_iso3(incumbent, "incumbent moderator CSV")
validate_unique_iso3(vreeland, "Vreeland moderator CSV")

required_incumbent <- c(
  "iso3c",
  "t0",
  "displaced_partner",
  "displaced_partner_name",
  "displaced_us",
  "displaced_g7",
  "displaced_regional_power",
  "displaced_regional_power_same_macroregion",
  "hub_entrepot_incumbent",
  "displacement_salience_warning"
)
required_vreeland <- c(
  "iso3c",
  "pre_entry_partner_level",
  "pre_entry_high_level_partner",
  "pre_entry_bri_mou"
)

missing_incumbent <- setdiff(required_incumbent, names(incumbent))
missing_vreeland <- setdiff(required_vreeland, names(vreeland))
if (length(missing_incumbent) > 0L) {
  stop("Missing incumbent columns: ", paste(missing_incumbent, collapse = ", "))
}
if (length(missing_vreeland) > 0L) {
  stop("Missing Vreeland columns: ", paste(missing_vreeland, collapse = ", "))
}

analysis_data <- analysis_data |>
  dplyr::left_join(
    incumbent |> dplyr::select(dplyr::all_of(required_incumbent)),
    by = "iso3c"
  ) |>
  dplyr::left_join(
    vreeland |> dplyr::select(dplyr::all_of(required_vreeland)),
    by = "iso3c"
  ) |>
  dplyr::mutate(
    country_id = as.integer(as.factor(iso3c)),
    displaced_us_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_us == TRUE ~ "displaced_us_yes",
      displaced_us == FALSE ~ "displaced_us_no",
      TRUE ~ "missing_moderator"
    ),
    displaced_g7_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_g7 == TRUE ~ "displaced_g7_yes",
      displaced_g7 == FALSE ~ "displaced_g7_no",
      TRUE ~ "missing_moderator"
    ),
    displaced_regional_power_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_regional_power == TRUE ~ "regional_power_yes",
      displaced_regional_power == FALSE ~ "regional_power_no",
      TRUE ~ "missing_moderator"
    ),
    same_region_regional_power_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_regional_power_same_macroregion == TRUE ~ "same_region_power_yes",
      displaced_regional_power_same_macroregion == FALSE ~ "same_region_power_no",
      TRUE ~ "missing_moderator"
    ),
    high_level_partner_group = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      pre_entry_high_level_partner == 1 ~ "high_level_partner_yes",
      pre_entry_high_level_partner == 0 ~ "high_level_partner_no",
      TRUE ~ "missing_moderator"
    ),
    regional_power_decomposition = dplyr::case_when(
      first_treat <= 0 ~ "never_treated_control",
      displaced_us == TRUE ~ "us",
      displaced_g7 == TRUE & displaced_us != TRUE ~ "other_g7",
      displaced_regional_power_same_macroregion == TRUE ~ "same_region_regional_power",
      displaced_regional_power == TRUE ~ "external_regional_or_global_power",
      TRUE ~ "other_incumbent"
    )
  ) |>
  dplyr::arrange(country_id, year)

panel_duplicates <- analysis_data |>
  dplyr::count(country_id, year, name = "n") |>
  dplyr::filter(n > 1L)
if (nrow(panel_duplicates) > 0L) {
  stop("Joined analysis panel has duplicate country_id-year rows.")
}

base_estimate <- estimate_cs(analysis_data, "Baseline C&S", "all")

subgroup_specs <- tibble::tribble(
  ~family, ~group_var, ~group_value, ~label,
  "displaced_us", "displaced_us_group", "displaced_us_no", "Event study: displaced_us_no",
  "displaced_us", "displaced_us_group", "displaced_us_yes", "Event study: displaced_us_yes",
  "displaced_g7", "displaced_g7_group", "displaced_g7_no", "Event study: displaced_g7_no",
  "displaced_g7", "displaced_g7_group", "displaced_g7_yes", "Event study: displaced_g7_yes",
  "regional_power", "displaced_regional_power_group", "regional_power_no", "Event study: regional_power_no",
  "regional_power", "displaced_regional_power_group", "regional_power_yes", "Event study: regional_power_yes",
  "same_region_power", "same_region_regional_power_group", "same_region_power_no", "Event study: same_region_power_no",
  "same_region_power", "same_region_regional_power_group", "same_region_power_yes", "Event study: same_region_power_yes",
  "lpv_high_level_partner", "high_level_partner_group", "high_level_partner_no", "Event study: high_level_partner_no",
  "lpv_high_level_partner", "high_level_partner_group", "high_level_partner_yes", "Event study: high_level_partner_yes"
)

subgroup_estimates <- lapply(seq_len(nrow(subgroup_specs)), function(i) {
  spec <- subgroup_specs[i, ]
  subgroup_data <- make_subgroup_data(
    analysis_data,
    group_var = spec$group_var,
    group_value = spec$group_value
  )
  estimate_cs(subgroup_data, spec$label, spec$family)
})

hub_excluded_data <- analysis_data |>
  dplyr::filter(first_treat == 0 | hub_entrepot_incumbent != TRUE)
hub_estimate <- estimate_cs(
  hub_excluded_data,
  "Hub-excluded C&S",
  "hub_exclusion"
)

decomposition_counts <- analysis_data |>
  dplyr::filter(first_treat > 0) |>
  dplyr::distinct(
    iso3c,
    country_name,
    first_treat_year,
    regional_power_decomposition,
    displaced_partner,
    displaced_partner_name
  ) |>
  dplyr::group_by(regional_power_decomposition) |>
  dplyr::summarise(
    n_treated_countries = dplyr::n(),
    countries = paste(sort(iso3c), collapse = ", "),
    displaced_partners = paste(sort(unique(displaced_partner)), collapse = ", "),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(n_treated_countries), regional_power_decomposition)

decomposition_estimates <- lapply(
  decomposition_counts$regional_power_decomposition,
  function(category) {
    estimate_cs(
      make_subgroup_data(
        analysis_data,
        "regional_power_decomposition",
        category
      ),
      paste0("Regional-power decomposition: ", category),
      "regional_power_decomposition"
    )
  }
)

all_estimates <- c(
  list(base_estimate),
  subgroup_estimates,
  list(hub_estimate),
  decomposition_estimates
)

overall_results <- dplyr::bind_rows(lapply(all_estimates, overall_row))
dynamic_results <- dplyr::bind_rows(lapply(all_estimates, dynamic_rows))
pretrend_results <- dplyr::bind_rows(lapply(
  all_estimates,
  pretrend_row,
  dynamic_data = dynamic_results
))

leave_one_out <- run_leave_one_out(analysis_data)

treated_cases <- treated_country_table(analysis_data, model = "baseline") |>
  dplyr::select(
    model,
    iso3c,
    country_name,
    first_treat_year,
    displaced_partner,
    displaced_partner_name,
    hub_entrepot_incumbent,
    displacement_salience_warning,
    regional_power_decomposition
  )

hub_excluded_cases <- analysis_data |>
  dplyr::filter(first_treat > 0, hub_entrepot_incumbent == TRUE) |>
  dplyr::distinct(
    iso3c,
    country_name,
    first_treat_year,
    displaced_partner,
    displaced_partner_name,
    displacement_salience_warning
  ) |>
  dplyr::arrange(first_treat_year, iso3c)

event_window_results <- dynamic_results |>
  dplyr::filter(event_time >= -5, event_time <= 8)

overall_out <- file.path(report_dir, "followup_overall_att_by_diagnostic.csv")
dynamic_out <- file.path(report_dir, "followup_event_studies_by_subgroup.csv")
pretrend_out <- file.path(report_dir, "followup_pretrend_tests_by_subgroup.csv")
loo_out <- file.path(report_dir, "followup_leave_one_country_out_cs.csv")
hub_out <- file.path(report_dir, "followup_hub_exclusion_cases.csv")
decomp_counts_out <- file.path(report_dir, "followup_regional_power_decomposition_counts.csv")
treated_cases_out <- file.path(report_dir, "followup_treated_cases_audit.csv")
session_out <- file.path(report_dir, "followup_sessionInfo_event_pretrend_loo.txt")
plot_out <- file.path(report_dir, "followup_event_studies_by_subgroup.png")
report_out <- file.path(report_dir, "followup_diagnostics_event_pretrend_loo_hubs_decomposition.md")

readr::write_csv(overall_results, overall_out)
readr::write_csv(dynamic_results, dynamic_out)
readr::write_csv(pretrend_results, pretrend_out)
readr::write_csv(leave_one_out, loo_out)
readr::write_csv(hub_excluded_cases, hub_out)
readr::write_csv(decomposition_counts, decomp_counts_out)
readr::write_csv(treated_cases, treated_cases_out)
capture.output(sessionInfo(), file = session_out)

plot_data <- event_window_results |>
  dplyr::filter(
    model %in% c(
      "Baseline C&S",
      "Event study: displaced_us_no",
      "Event study: displaced_us_yes",
      "Event study: regional_power_no",
      "Event study: regional_power_yes",
      "Event study: high_level_partner_no",
      "Event study: high_level_partner_yes",
      "Hub-excluded C&S"
    )
  )

if (nrow(plot_data) > 0L) {
  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = event_time, y = att, color = model)
  ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "grey55") +
    ggplot2::geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey55") +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = ci_lo, ymax = ci_hi),
      width = 0.15,
      alpha = 0.55
    ) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::geom_line(linewidth = 0.5) +
    ggplot2::facet_wrap(~subgroup, scales = "free_y") +
    ggplot2::labs(
      x = "Event time relative to China becoming top export destination",
      y = "ATT on absolute Brazil-China UNGA distance",
      color = "Specification",
      caption = "Figure 1. C&S event-study diagnostics by pre-treatment subgroup; 95% pointwise intervals."
    ) +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom")

  ggplot2::ggsave(plot_out, p, width = 11, height = 8, dpi = 300)
}

overall_display <- overall_results |>
  make_display() |>
  dplyr::select(
    model,
    status,
    att,
    se,
    ci,
    p,
    n_treated,
    n_control
  )

pretrend_display <- pretrend_results |>
  dplyr::mutate(
    pretest_p = format_p(pretest_p),
    near_pre_mean_att = format_num(near_pre_mean_att),
    near_pre_max_abs_att = format_num(near_pre_max_abs_att),
    post_0_5_mean_att = format_num(post_0_5_mean_att)
  ) |>
  dplyr::select(
    model,
    status,
    n_treated,
    pretest_p,
    near_pre_mean_att,
    near_pre_max_abs_att,
    near_pre_n_p_below_005,
    all_pre_n_p_below_005,
    post_0_5_mean_att
  )

loo_display <- leave_one_out |>
  dplyr::filter(!is.na(excluded_iso3c), status == "ok") |>
  dplyr::slice_max(abs_delta_att, n = 8, with_ties = FALSE) |>
  dplyr::mutate(
    att = format_num(att),
    delta_att = format_num(delta_att),
    p = format_p(p)
  ) |>
  dplyr::select(
    excluded_iso3c,
    excluded_country_name,
    excluded_first_treat,
    att,
    delta_att,
    p
  )

hub_display <- overall_results |>
  dplyr::filter(model %in% c("Baseline C&S", "Hub-excluded C&S")) |>
  make_display() |>
  dplyr::select(model, att, se, ci, p, n_treated, n_control)

decomp_display <- overall_results |>
  dplyr::filter(subgroup == "regional_power_decomposition") |>
  make_display() |>
  dplyr::select(model, status, att, se, ci, p, n_treated, n_control)

report_lines <- c(
  "# Follow-up diagnostics: event studies, pretrends, influence, hubs, and regional-power decomposition",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "This script reads `china_top_absorbing_sample` via `targets::tar_read()` and joins the already-created incumbent-salience and LPV moderator CSVs. It does not run `targets::tar_make()` and does not edit the targets pipeline or manuscript.",
  "",
  "## Table 1. Overall C&S estimates by diagnostic sample",
  "",
  markdown_table(overall_display),
  "",
  "## Table 2. Lead/pretrend diagnostics",
  "",
  "The formal pre-test is the `did::att_gt()` pre-test when available. The near-pre window is event times -5 to -2; event time -1 is the universal baseline.",
  "",
  markdown_table(pretrend_display),
  "",
  "## Table 3. Most influential leave-one-treated-country exclusions",
  "",
  markdown_table(loo_display),
  "",
  "## Table 4. Hub/entrepot exclusion",
  "",
  markdown_table(hub_display),
  "",
  "Excluded hub/entrepot treated cases:",
  "",
  markdown_table(hub_excluded_cases),
  "",
  "## Table 5. Regional-power decomposition counts",
  "",
  markdown_table(decomposition_counts),
  "",
  "## Table 6. Regional-power decomposition estimates",
  "",
  markdown_table(decomp_display),
  "",
  "## Interpretation",
  "",
  "- These diagnostics use C&S event-study estimators because they expose dynamic effects and pre-treatment leads directly.",
  "- Subgroups with very few treated countries remain exploratory; skipped models have insufficient treated support.",
  "- Formal pre-tests are often unavailable because `did::att_gt()` reports singular covariance matrices in this small-treated design; the lead summaries therefore matter more than the unavailable omnibus p-values.",
  "- Hub/entrepot exclusion removes treated countries whose displaced incumbents are `ARE`, `BEL`, `CHE`, `HKG`, or `SGP` while retaining never-treated controls.",
  "- The regional-power decomposition is prioritized as: US, other G7, same-region regional power, external regional/global power, other incumbent.",
  "",
  "## Output files",
  "",
  paste0("- `", overall_out, "`"),
  paste0("- `", dynamic_out, "`"),
  paste0("- `", pretrend_out, "`"),
  paste0("- `", loo_out, "`"),
  paste0("- `", hub_out, "`"),
  paste0("- `", decomp_counts_out, "`"),
  paste0("- `", treated_cases_out, "`"),
  paste0("- `", plot_out, "`"),
  paste0("- `", session_out, "`")
)

writeLines(report_lines, con = report_out, useBytes = TRUE)

message("Wrote: ", report_out)
message("Wrote: ", overall_out)
message("Wrote: ", dynamic_out)
message("Wrote: ", pretrend_out)
message("Wrote: ", loo_out)
message("Wrote: ", plot_out)

print(overall_display)
print(pretrend_display)
print(loo_display)
