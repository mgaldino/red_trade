#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(readr)
  library(tibble)
  library(ggplot2)
  library(synthdid)
  library(countrycode)
})

source(file.path("scripts", "functions.R"))

set.seed(20260714L)

targets_metadata_path <- file.path("_targets", "meta", "meta")
targets_metadata_mtime_before <- as.numeric(
  file.info(targets_metadata_path)$mtime
)

out_dir <- file.path(
  "data", "processed", "diagnostics",
  "paper_v4_brazil_sdid_predetermined_core"
)
figure_dir <- file.path(
  "quality_reports", "china_demand_shock_rank_threshold"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

out_path <- function(name) file.path(out_dir, name)

core_fit <- targets::tar_read_raw(
  "synth_fit_no_time_varying_covariates", store = "_targets"
)
core_se <- as.numeric(targets::tar_read_raw(
  "se_synth_no_time_varying_covariates", store = "_targets"
))
synth_data <- targets::tar_read_raw("synth_data", store = "_targets")
trade_data_ranked <- targets::tar_read_raw("trade_data_ranked", store = "_targets")
trade_data_cleaned <- targets::tar_read_raw("trade_data_cleaned", store = "_targets")
rank_volume_data <- targets::tar_read_raw(
  "goal3_brazil_rank_volume_data", store = "_targets"
)

audit_dir <- file.path(
  "data", "processed", "diagnostics",
  "brazil_sdid_predetermined_commodity_controls"
)
audit_results <- readr::read_csv(
  file.path(audit_dir, "table_4_sdid_specification_results.csv"),
  show_col_types = FALSE
)
rank_distribution <- readr::read_csv(
  file.path(audit_dir, "table_11_sdid_placebo_in_space_distribution.csv"),
  show_col_types = FALSE
) |>
  dplyr::filter(
    specification == "predetermined_core",
    status == "estimated",
    is.finite(estimate)
  )

core_result <- audit_results |>
  dplyr::filter(specification == "predetermined_core") |>
  dplyr::slice_head(n = 1)
stopifnot(
  nrow(core_result) == 1L,
  isTRUE(all.equal(as.numeric(core_fit), core_result$estimate, tolerance = 1e-10)),
  isTRUE(all.equal(core_se, core_result$se_placebo, tolerance = 1e-10))
)

fit_summary <- brazil_sdid_summarise_fit(
  core_fit, "Preferred: no effective covariate adjustment"
)
brazil_pre_mean <- synth_data |>
  dplyr::filter(iso3c == "BRA", year <= 2008L) |>
  dplyr::summarise(value = mean(abs_distance_china, na.rm = TRUE)) |>
  dplyr::pull(value)

main_summary <- fit_summary |>
  dplyr::mutate(
    se_placebo = core_se,
    ci_95_low = core_result$ci_95_low,
    ci_95_high = core_result$ci_95_high,
    p_normal_two_sided = core_result$p_value_two_sided,
    rank_one_sided_negative = core_result$rank_one_sided,
    rank_two_sided_absolute = core_result$rank_two_sided,
    rank_denominator = core_result$rank_denominator,
    p_rank_one_sided_negative = core_result$rank_p_one_sided_negative,
    p_rank_two_sided_absolute = core_result$rank_p_two_sided,
    brazil_pre_treatment_mean = brazil_pre_mean,
    estimate_as_percent_of_pre_mean = 100 * estimate / brazil_pre_mean,
    se_replications = core_result$se_replications,
    max_abs_fixed_covariate_coefficient = max(
      abs(attr(core_fit, "weights")$beta)
    ),
    source = paste0(
      "targets: synth_fit_no_time_varying_covariates and ",
      "se_synth_no_time_varying_covariates; audited rank checkpoint"
    )
  )
readr::write_csv(main_summary, out_path("main_summary.csv"))

unit_weights <- brazil_sdid_unit_weights(core_fit, synth_data)
time_weights <- brazil_sdid_time_weights(core_fit)
fixed_balance_values <- synth_data |>
  dplyr::filter(year <= 2008L) |>
  dplyr::summarise(
    abs_distance_china = mean(
      abs_distance_china[year %in% 1997:2008], na.rm = TRUE
    ),
    perc_trade_with_us = mean(
      perc_trade_with_us[year %in% 2004:2008], na.rm = TRUE
    ),
    perc_trade_with_china = mean(
      perc_trade_with_china[year %in% 2004:2008], na.rm = TRUE
    ),
    pci_cur = mean(pci_cur[year %in% 2004:2008], na.rm = TRUE),
    distance_us = dplyr::first(distance_us[year == 2004L]),
    inst_parliamentary = dplyr::first(inst_parliamentary[year == 2008L]),
    us_trade_agreement = dplyr::first(us_trade_agreement[year == 2008L]),
    .by = iso3c
  ) |>
  tidyr::pivot_longer(
    cols = -iso3c, names_to = "variable", values_to = "value"
  )

balance <- dplyr::bind_rows(lapply(
  unique(fixed_balance_values$variable),
  function(variable_name) {
    variable_values <- fixed_balance_values |>
      dplyr::filter(variable == variable_name)
    brazil_value <- variable_values |>
      dplyr::filter(iso3c == "BRA") |>
      dplyr::pull(value)
    donor_values <- variable_values |>
      dplyr::inner_join(
        unit_weights |>
          dplyr::select(iso3c, unit_weight),
        by = "iso3c"
      )
    donor_sd <- stats::sd(donor_values$value, na.rm = TRUE)
    synthetic_value <- sum(
      donor_values$value * donor_values$unit_weight, na.rm = TRUE
    )
    tibble::tibble(
      variable = variable_name,
      brazil_pre_mean = brazil_value,
      synthetic_pre_mean = synthetic_value,
      brazil_minus_synthetic = brazil_value - synthetic_value,
      standardized_difference = dplyr::if_else(
        is.na(donor_sd) || donor_sd == 0,
        NA_real_,
        (brazil_value - synthetic_value) / donor_sd
      )
    )
  }
)) |>
  dplyr::left_join(brazil_sdid_variable_dictionary(), by = "variable") |>
  dplyr::mutate(
    role = dplyr::if_else(
      variable == "abs_distance_china",
      "Outcome",
      "Predetermined/fixed covariate"
    ),
    included_in_preferred_specification = TRUE,
    value_definition = dplyr::case_when(
      variable == "abs_distance_china" ~ "1997-2008 mean",
      variable %in% c(
        "perc_trade_with_us", "perc_trade_with_china", "pci_cur"
      ) ~ "2004-2008 mean held fixed",
      variable == "distance_us" ~ "Time-invariant value held fixed",
      TRUE ~ "2008 value held fixed"
    ),
    diagnostic_scope = paste0(
      "Preferred-specification values weighted by omega; descriptive, not ",
      "residualized synthdid balance"
    )
  ) |>
  dplyr::relocate(label, role, .after = variable)
readr::write_csv(unit_weights, out_path("unit_weights.csv"))
readr::write_csv(time_weights, out_path("time_weights.csv"))
readr::write_csv(balance, out_path("balance.csv"))

goods_panel_path <- file.path(
  "data", "processed", "diagnostics",
  "china_top_m2_goods_status_current_min5",
  "m2_goods_status_current_full_panel_2026-05-20.csv"
)
goods_panel <- readr::read_csv(goods_panel_path, show_col_types = FALSE)

original_top <- trade_data_ranked |>
  dplyr::filter(
    iso3c %in% rank_distribution$iso3c,
    importer_iso3 == "CHN",
    year >= 1997L,
    year <= 2015L,
    exports > 0
  ) |>
  dplyr::summarise(
    ever_china_top_original = any(rank_from_i == 1L),
    original_top_years = paste(year[rank_from_i == 1L], collapse = ";"),
    .by = iso3c
  )
goods_top <- goods_panel |>
  dplyr::filter(
    iso3c %in% rank_distribution$iso3c,
    year >= 1997L,
    year <= 2015L
  ) |>
  dplyr::summarise(
    ever_china_top_goods = any(china_is_top == 1L, na.rm = TRUE),
    goods_top_years = paste(year[china_is_top == 1L], collapse = ";"),
    .by = iso3c
  )

rank_distribution <- rank_distribution |>
  dplyr::left_join(original_top, by = "iso3c") |>
  dplyr::left_join(goods_top, by = "iso3c") |>
  dplyr::mutate(
    ever_china_top_original = dplyr::coalesce(ever_china_top_original, FALSE),
    ever_china_top_goods = dplyr::coalesce(ever_china_top_goods, FALSE),
    country_name = countrycode::countrycode(iso3c, "iso3c", "country.name"),
    role = dplyr::if_else(iso3c == "BRA", "Brazil", "Control placebo"),
    rmspe_pre_ratio_to_brazil = rmspe_pre /
      rmspe_pre[iso3c == "BRA"]
  ) |>
  dplyr::select(
    specification, year_end, iso3c, country_name, role, estimate, rmspe_pre,
    rmspe_pre_ratio_to_brazil, ever_china_top_original, original_top_years,
    ever_china_top_goods, goods_top_years, status, error
  )
readr::write_csv(rank_distribution, out_path("placebo_distribution.csv"))

brazil_rank <- rank_distribution |>
  dplyr::filter(iso3c == "BRA") |>
  dplyr::slice_head(n = 1)
rank_sets <- list(
  "All valid assignments" = rank_distribution,
  "Exclude goods-only China-top donor assignments" = rank_distribution |>
    dplyr::filter(iso3c == "BRA" | !ever_china_top_goods),
  "Pre-fit RMSPE no larger than twice Brazil" = rank_distribution |>
    dplyr::filter(rmspe_pre <= 2 * brazil_rank$rmspe_pre)
)
rank_inference <- dplyr::bind_rows(lapply(names(rank_sets), function(set_name) {
  data <- rank_sets[[set_name]]
  tibble::tibble(
    comparison_set = set_name,
    rank_one_sided_negative = sum(data$estimate <= brazil_rank$estimate),
    rank_two_sided_absolute = sum(
      abs(data$estimate) >= abs(brazil_rank$estimate)
    ),
    denominator = nrow(data),
    p_rank_one_sided_negative = mean(
      data$estimate <= brazil_rank$estimate
    ),
    p_rank_two_sided_absolute = mean(
      abs(data$estimate) >= abs(brazil_rank$estimate)
    )
  )
}))
readr::write_csv(rank_inference, out_path("rank_inference.csv"))

donor_exposure <- brazil_sdid_donor_china_exposure(
  trade_data_ranked,
  trade_data_cleaned,
  unit_weights,
  pre_years = 1997:2008,
  post_years = 2009:2015
)
readr::write_csv(donor_exposure$exposure, out_path("donor_china_exposure.csv"))
readr::write_csv(
  donor_exposure$summary, out_path("donor_china_exposure_summary.csv")
)

fit_core_subset <- function(data, specification, time_end = 2016L) {
  fit <- simple_fit_no_time_varying_covariates(
    data, time_treatment = 2008L, time_end = time_end,
    filter_latin_america = FALSE
  )
  brazil_sdid_summarise_fit(fit, specification)
}

top10 <- unit_weights |>
  dplyr::arrange(weight_rank) |>
  dplyr::slice_head(n = 10)
high_weight <- unit_weights |>
  dplyr::filter(high_weight_donor)
high_weight_lac <- high_weight |>
  dplyr::filter(region == "Latin America & Caribbean")
removal_specs <- dplyr::bind_rows(
  top10 |>
    dplyr::transmute(
      specification = paste0("Drop ", iso3c, " (rank ", weight_rank, ")"),
      removed_donors = iso3c
    ),
  tibble::tibble(
    specification = c(
      "Drop top 5 donors by weight",
      "Drop top 10 donors by weight",
      "Drop donors with weight >= 2x uniform",
      "Drop high-weight Latin America/Caribbean donors"
    ),
    removed_donors = c(
      paste(top10$iso3c[seq_len(min(5L, nrow(top10)))], collapse = ";"),
      paste(top10$iso3c, collapse = ";"),
      paste(high_weight$iso3c, collapse = ";"),
      paste(high_weight_lac$iso3c, collapse = ";")
    )
  )
)
donor_rows <- lapply(seq_len(nrow(removal_specs)), function(i) {
  removed <- strsplit(
    removal_specs$removed_donors[[i]], ";", fixed = TRUE
  )[[1]]
  removed <- removed[nzchar(removed)]
  tryCatch(
    fit_core_subset(
      synth_data |>
        dplyr::filter(!iso3c %in% removed),
      removal_specs$specification[[i]]
    ) |>
      dplyr::mutate(
        removed_donors = paste(removed, collapse = ";"),
        n_removed_donors = length(removed)
      ),
    error = function(e) {
      tibble::tibble(
        specification = removal_specs$specification[[i]],
        estimate = NA_real_, rmspe_pre = NA_real_, rmspe_post = NA_real_,
        rmspe_ratio = NA_real_, n_units = NA_integer_, n_donors = NA_integer_,
        n_pre_years = NA_integer_, n_post_years = NA_integer_,
        status = "error", error = conditionMessage(e),
        removed_donors = paste(removed, collapse = ";"),
        n_removed_donors = length(removed)
      )
    }
  )
})
donor_sensitivity <- dplyr::bind_rows(
  fit_summary |>
    dplyr::mutate(removed_donors = "", n_removed_donors = 0L),
  donor_rows
) |>
  dplyr::mutate(
    estimate_change_vs_main = estimate - as.numeric(core_fit),
    percent_change_vs_main = 100 * estimate_change_vs_main /
      abs(as.numeric(core_fit)),
    inference = dplyr::if_else(
      n_removed_donors == 0L,
      "Main SE and rank reported separately",
      "Point estimate only"
    )
  )
readr::write_csv(donor_sensitivity, out_path("donor_sensitivity.csv"))

window_specs <- tibble::tribble(
  ~specification, ~year_start, ~year_end,
  "1997-2013", 1997L, 2013L,
  "1997-2014", 1997L, 2014L,
  "1997-2015 preferred", 1997L, 2015L,
  "1997-2016", 1997L, 2016L,
  "1998-2015", 1998L, 2015L,
  "1999-2015", 1999L, 2015L,
  "2000-2015", 2000L, 2015L
)
window_sensitivity <- dplyr::bind_rows(lapply(
  seq_len(nrow(window_specs)),
  function(i) {
    spec <- window_specs[i, ]
    fit <- if (spec$specification == "1997-2015 preferred") {
      core_fit
    } else {
      simple_fit_no_time_varying_covariates(
        synth_data |>
          dplyr::filter(year >= spec$year_start),
        time_treatment = 2008L,
        time_end = spec$year_end + 1L,
        filter_latin_america = FALSE
      )
    }
    brazil_sdid_summarise_fit(fit, spec$specification) |>
      dplyr::mutate(
        year_start = spec$year_start,
        year_end = spec$year_end
      )
  }
)) |>
  dplyr::mutate(
    estimate_change_vs_main = estimate - as.numeric(core_fit),
    percent_change_vs_main = 100 * estimate_change_vs_main /
      abs(as.numeric(core_fit)),
    inference = dplyr::if_else(
      specification == "1997-2015 preferred",
      "1,000-placebo SE and rank reported in main results",
      "Point estimate only"
    )
  )
readr::write_csv(window_sensitivity, out_path("window_sensitivity.csv"))

fit_no_covariates <- function(data, treatment_start, year_end) {
  fit_data <- data |>
    dplyr::filter(year <= year_end) |>
    dplyr::mutate(
      treatment = as.integer(iso3c == "BRA" & year >= treatment_start),
      .unit_treated = as.integer(iso3c == "BRA")
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)
  panel <- fit_data |>
    dplyr::mutate(
      iso3c = as.factor(iso3c), year = as.integer(year),
      Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel)
  synthdid::synthdid_estimate(
    Y = setup$Y, N0 = setup$N0, T0 = setup$T0
  )
}
timing_specs <- tibble::tribble(
  ~nominal_treatment_year, ~year_end, ~test_role,
  2003L, 2008L, "Growth/lower-rank promotion",
  2004L, 2008L, "China rank-2 threshold",
  2005L, 2008L, "Rapid growth without rank 1",
  2009L, 2015L, "Actual rank-1 reversal",
  2012L, max(synth_data$year), "Later-break falsification"
)
timing_results <- dplyr::bind_rows(lapply(
  seq_len(nrow(timing_specs)),
  function(i) {
    spec <- timing_specs[i, ]
    fit <- fit_no_covariates(
      synth_data, spec$nominal_treatment_year, spec$year_end
    )
    tibble::tibble(
      nominal_treatment_year = spec$nominal_treatment_year,
      year_end = spec$year_end,
      test_role = spec$test_role,
      estimate = as.numeric(fit),
      inference = "Point estimate only; no covariates"
    )
  }
)) |>
  dplyr::left_join(
    rank_volume_data |>
      dplyr::select(
        year, china_rank, china_share_pct,
        china_margin_vs_competitor_usd_billion
      ),
    by = c("nominal_treatment_year" = "year")
  )
readr::write_csv(timing_results, out_path("timing_placebos.csv"))

latam_core_fit <- simple_fit_no_time_varying_covariates(
  synth_data, time_treatment = 2008L, time_end = 2016L,
  filter_latin_america = TRUE
)
latam_core_summary <- brazil_sdid_summarise_fit(
  latam_core_fit, "Latin America donors; no effective covariate adjustment"
) |>
  dplyr::mutate(inference = "Point estimate only")
readr::write_csv(latam_core_summary, out_path("latam_core_summary.csv"))

latam_trend_plot <- my_plot_trends(latam_core_fit) +
  ggplot2::labs(
    title = NULL,
    subtitle = paste0(
      "Latin America donors; no effective covariate adjustment"
    )
  )
ggplot2::ggsave(
  file.path(
    figure_dir,
    "figure_brazil_sdid_predetermined_core_latam_fit.pdf"
  ),
  latam_trend_plot, width = 7, height = 4.8, device = grDevices::pdf
)
ggplot2::ggsave(
  file.path(
    figure_dir,
    "figure_brazil_sdid_predetermined_core_latam_fit.png"
  ),
  latam_trend_plot, width = 7, height = 4.8, dpi = 300
)

trend_plot <- my_plot_trends(core_fit) +
  ggplot2::labs(
    title = NULL,
    subtitle = "Preferred specification with no effective covariate adjustment"
  )
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_fit.pdf"),
  trend_plot, width = 7, height = 4.8, device = grDevices::pdf
)
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_fit.png"),
  trend_plot, width = 7, height = 4.8, dpi = 300
)

weights_plot_data <- unit_weights |>
  dplyr::slice_head(n = 10) |>
  dplyr::mutate(
    donor_label = paste0(country_name, " (", iso3c, ")"),
    donor_label = stats::reorder(donor_label, unit_weight)
  )
weights_plot <- ggplot2::ggplot(
  weights_plot_data,
  ggplot2::aes(x = donor_label, y = unit_weight)
) +
  ggplot2::geom_col(fill = "#2B6F77", width = 0.72) +
  ggplot2::coord_flip() +
  ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  ggplot2::labs(x = NULL, y = "Donor weight") +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_weights.pdf"),
  weights_plot, width = 7, height = 4.8, device = grDevices::pdf
)
ggplot2::ggsave(
  file.path(figure_dir, "figure_brazil_sdid_predetermined_core_weights.png"),
  weights_plot, width = 7, height = 4.8, dpi = 300
)

all_rank_validation <- rank_inference |>
  dplyr::filter(comparison_set == "All valid assignments") |>
  dplyr::slice_head(n = 1)
clean_rank_validation <- rank_inference |>
  dplyr::filter(
    comparison_set == "Exclude goods-only China-top donor assignments"
  ) |>
  dplyr::slice_head(n = 1)
targets_metadata_mtime_after <- as.numeric(
  file.info(targets_metadata_path)$mtime
)

validation <- tibble::tibble(
  check = c(
    "Preferred ATT matches audited predetermined_core",
    "Preferred SE matches audited 1,000-placebo SE",
    "Directional rank is 3/96",
    "Two-sided absolute rank is 7/96",
    "Fixed covariate coefficients are numerically zero",
    "No non-Brazil original-treatment assignment in 1997-2015",
    "Goods-only donor exclusion leaves both ranks unchanged",
    "All timing falsifications are point estimates without covariates",
    "Donor-unit weights sum to one",
    "Pre-treatment time weights sum to one",
    "Targets metadata modification time is unchanged"
  ),
  passed = c(
    isTRUE(all.equal(as.numeric(core_fit), core_result$estimate, tolerance = 1e-10)),
    isTRUE(all.equal(core_se, core_result$se_placebo, tolerance = 1e-10)),
    core_result$rank_one_sided == 3L && core_result$rank_denominator == 96L,
    core_result$rank_two_sided == 7L && core_result$rank_denominator == 96L,
    max(abs(attr(core_fit, "weights")$beta)) < 1e-12,
    !any(
      rank_distribution$iso3c != "BRA" &
        rank_distribution$ever_china_top_original
    ),
    clean_rank_validation$rank_one_sided_negative ==
      all_rank_validation$rank_one_sided_negative &&
      clean_rank_validation$rank_two_sided_absolute ==
        all_rank_validation$rank_two_sided_absolute,
    all(timing_results$inference == "Point estimate only; no covariates"),
    abs(sum(unit_weights$unit_weight) - 1) < 1e-10,
    abs(sum(time_weights$time_weight) - 1) < 1e-10,
    isTRUE(all.equal(
      targets_metadata_mtime_before,
      targets_metadata_mtime_after,
      tolerance = 0
    ))
  )
)
stopifnot(all(validation$passed))
readr::write_csv(validation, out_path("validation_checks.csv"))

writeLines(
  c(
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "Preferred fit target: synth_fit_no_time_varying_covariates",
    "Preferred SE target: se_synth_no_time_varying_covariates",
    "Placebo SE replications: 1000",
    "Targets pipeline executed: no"
  ),
  out_path("run_log.txt"),
  useBytes = TRUE
)
writeLines(
  capture.output(sessionInfo()), out_path("session_info.txt"), useBytes = TRUE
)

message("Paper-ready predetermined-core outputs written to: ", out_dir)
