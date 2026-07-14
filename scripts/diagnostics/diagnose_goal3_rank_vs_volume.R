#!/usr/bin/env Rscript

# Goal 3 diagnostic: rank-versus-volume.
# This script reads existing targets and writes diagnostic outputs only. It does
# not modify _targets.R, _targets.yaml, or the targets store.

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
  library(countrycode)
  library(here)
  library(readr)
  library(tibble)
  library(synthdid)
})

options(scipen = 999)

target_store <- here::here("_targets")
source(here::here("scripts", "functions.R"))

out_dir <- here::here("quality_reports")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
script_path <- "scripts/diagnostics/diagnose_goal3_rank_vs_volume.R"

path_out <- function(filename) file.path(out_dir, filename)

target_audit_path <- path_out("goal3_target_audit.csv")
brazil_rank_path <- path_out("goal3_brazil_rank_volume_2000_2012.csv")
brazil_key_years_path <- path_out("goal3_brazil_rank_volume_key_years.csv")
sdid_comparison_path <- path_out("goal3_brazil_sdid_trade_share_comparison.csv")
placebo_tests_path <- path_out("goal3_brazil_placebo_rank_volume_tests.csv")
cross_country_entries_path <- path_out("goal3_cross_country_entry_share_margin.csv")
cross_country_summary_path <- path_out("goal3_cross_country_entry_share_margin_summary.csv")
cross_country_feasibility_path <- path_out("goal3_cross_country_trade_control_feasibility.csv")
cross_country_join_diagnostics_path <- path_out("goal3_cross_country_trade_join_diagnostics.csv")
sdid_target_validation_path <- path_out("goal3_brazil_sdid_target_validation.csv")
session_info_path <- path_out("goal3_rank_vs_volume_session_info.txt")
report_path <- path_out(paste0(run_date, "_goal3_rank_vs_volume_diagnostic.md"))

brazil_fig_png <- path_out("fig_goal3_brazil_rank_volume_2000_2012.png")
brazil_fig_pdf <- path_out("fig_goal3_brazil_rank_volume_2000_2012.pdf")
sdid_fig_png <- path_out("fig_goal3_brazil_sdid_trade_share_comparison.png")
sdid_fig_pdf <- path_out("fig_goal3_brazil_sdid_trade_share_comparison.pdf")
entry_fig_png <- path_out("fig_goal3_cross_country_entry_share_margin.png")
entry_fig_pdf <- path_out("fig_goal3_cross_country_entry_share_margin.pdf")

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) {
      structure(
        list(error = conditionMessage(e)),
        class = "goal3_tar_read_error"
      )
    }
  )
}

collapse_meta_column <- function(x) {
  if (is.list(x)) {
    return(vapply(x, function(item) paste(as.character(item), collapse = " | "), character(1)))
  }
  as.character(x)
}

object_shape <- function(x) {
  if (inherits(x, "goal3_tar_read_error")) {
    return(tibble::tibble(
      object_class = "tar_read_error",
      nrow = NA_integer_,
      ncol = NA_integer_,
      length = NA_integer_,
      read_error = x$error
    ))
  }

  if (is.data.frame(x)) {
    return(tibble::tibble(
      object_class = paste(class(x), collapse = ";"),
      nrow = nrow(x),
      ncol = ncol(x),
      length = length(x),
      read_error = ""
    ))
  }

  tibble::tibble(
    object_class = paste(class(x), collapse = ";"),
    nrow = NA_integer_,
    ncol = NA_integer_,
    length = length(x),
    read_error = ""
  )
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", paste0(formatC(100 * x, digits = digits, format = "f"), "%"))
}

format_table_text <- function(data) {
  paste(capture.output(print(tibble::as_tibble(data), n = Inf, width = Inf)), collapse = "\n")
}

markdown_table <- function(data, digits = 3) {
  data <- as.data.frame(data)
  if (nrow(data) == 0L) {
    return("_No rows._")
  }

  display <- data
  for (col in names(display)) {
    if (is.numeric(display[[col]])) {
      display[[col]] <- ifelse(
        is.na(display[[col]]),
        "",
        formatC(display[[col]], digits = digits, format = "f")
      )
    } else {
      display[[col]] <- ifelse(is.na(display[[col]]), "", as.character(display[[col]]))
    }
  }

  header <- paste0("| ", paste(names(display), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(display)), collapse = " | "), " |")
  rows <- apply(display, 1, function(x) paste0("| ", paste(x, collapse = " | "), " |"))
  paste(c(header, separator, rows), collapse = "\n")
}

country_name <- function(iso3c) {
  iso3c_chr <- as.character(iso3c)
  out <- countrycode::countrycode(
    iso3c_chr,
    origin = "iso3c",
    destination = "country.name",
    warn = FALSE
  )
  dplyr::if_else(is.na(out), iso3c_chr, out)
}

target_notes <- tibble::tribble(
  ~name, ~diagnostic_role,
  "trade_data", "Directed export flows; source for China share, ordinal rank, and margin.",
  "trade_data_ranked", "Existing China export-destination rank target; has rank and first/second indicators but no margin.",
  "trade_data_cleaned", "Existing aggregate trade target; has China/US export shares once divided by total trade.",
  "synth_data", "Brazil SDiD analytical panel with continuous China/US trade-share covariates already rescaled.",
  "synth_fit", "Existing Brazil SDiD main fit with trade-share covariates.",
  "se_synth", "Existing placebo standard error for main Brazil SDiD fit.",
  "synth_data_baseline", "Existing SDiD panel without institutional covariates; still contains trade-share covariates.",
  "synth_fit_baseline", "Existing robustness fit without institutional covariates; not a no-trade-share fit.",
  "se_synth_baseline", "Existing placebo standard error for institutional-baseline robustness.",
  "placebo_teste_treatment02", "Existing in-time placebo: treatment turns on in 2003, sample ends before 2009.",
  "se_synth_placebo2", "Existing placebo standard error for 2003 in-time placebo.",
  "placebo_teste_treatment04", "Existing in-time placebo: treatment turns on in 2005, sample ends before 2009.",
  "se_synth_placebo3", "Existing placebo standard error for 2005 in-time placebo.",
  "placebo_teste_treatment11", "Existing post-treatment timing falsification: treatment turns on in 2012.",
  "se_synth_placebo1", "Existing placebo standard error for 2012 timing falsification.",
  "china_top_panel", "Scope-conditioned cross-country panel; treatment is China top export destination.",
  "china_top_fect_data", "Existing estimation panel for fect IFE China-top specification.",
  "fect_ife_china_top_summary", "Existing cross-country fect IFE summary without covariates.",
  "fect_ife_china_top_cov_summary", "Existing cross-country fect IFE summary with log GDP per capita and press freedom."
)

target_meta <- targets::tar_meta(store = target_store) |>
  dplyr::select(dplyr::any_of(c(
    "name",
    "type",
    "format",
    "bytes",
    "time",
    "warnings",
    "error"
  )))

for (meta_col in c("type", "format", "bytes", "time", "warnings", "error")) {
  if (!meta_col %in% names(target_meta)) {
    target_meta[[meta_col]] <- NA
  }
}

target_meta <- target_meta |>
  dplyr::mutate(
    warnings = collapse_meta_column(warnings),
    error = collapse_meta_column(error)
  )

target_audit <- target_notes |>
  dplyr::left_join(
    target_meta,
    by = "name"
  ) |>
  dplyr::mutate(
    exists_in_target_store = !is.na(type),
    complete_without_error = exists_in_target_store & (is.na(error) | error == "")
  )

target_shapes <- dplyr::bind_rows(lapply(target_notes$name, function(target_name) {
  object_shape(safe_tar_read(target_name)) |>
    dplyr::mutate(name = target_name, .before = 1)
}))

target_audit <- target_audit |>
  dplyr::left_join(target_shapes, by = "name") |>
  dplyr::mutate(
    contains_trade_share = name %in% c("trade_data_cleaned", "synth_data", "synth_data_baseline"),
    contains_china_rank = name %in% c("trade_data_ranked", "china_top_panel", "china_top_fect_data"),
    contains_margin = FALSE,
    margin_status = dplyr::if_else(
      name %in% c("trade_data", "trade_data_ranked", "china_top_panel"),
      "derivable from trade_data; not stored as target",
      "not applicable"
    )
  ) |>
  dplyr::select(
    name,
    diagnostic_role,
    exists_in_target_store,
    complete_without_error,
    object_class,
    nrow,
    ncol,
    length,
    contains_trade_share,
    contains_china_rank,
    contains_margin,
    margin_status,
    bytes,
    time,
    warnings,
    error,
    read_error
  )

readr::write_csv(target_audit, target_audit_path)

trade_data <- safe_tar_read("trade_data")
unga_data <- safe_tar_read("unga_data")
synth_data <- safe_tar_read("synth_data")
china_top_panel <- safe_tar_read("china_top_panel")

if (inherits(trade_data, "goal3_tar_read_error")) {
  stop("Could not read target trade_data: ", trade_data$error)
}
if (inherits(unga_data, "goal3_tar_read_error")) {
  stop("Could not read target unga_data: ", unga_data$error)
}
if (inherits(synth_data, "goal3_tar_read_error")) {
  stop("Could not read target synth_data: ", synth_data$error)
}
if (inherits(china_top_panel, "goal3_tar_read_error")) {
  stop("Could not read target china_top_panel: ", china_top_panel$error)
}

build_export_rank_panel <- function(trade_data) {
  ranked <- trade_data |>
    dplyr::filter(!is.na(year), !is.na(exporter_iso3), !is.na(importer_iso3)) |>
    dplyr::filter(exporter_iso3 != importer_iso3) |>
    dplyr::mutate(exports = dplyr::coalesce(as.numeric(exports), 0)) |>
    dplyr::group_by(year, exporter_iso3) |>
    dplyr::arrange(dplyr::desc(exports), importer_iso3, .by_group = TRUE) |>
    dplyr::mutate(
      row_order = dplyr::row_number(),
      partner_rank = dplyr::dense_rank(dplyr::desc(exports)),
      export_total = sum(exports, na.rm = TRUE),
      top_partner = dplyr::first(importer_iso3),
      top_exports = dplyr::first(exports),
      second_partner = dplyr::nth(importer_iso3, 2, default = NA_character_),
      second_exports = dplyr::nth(exports, 2, default = NA_real_)
    ) |>
    dplyr::ungroup()

  ranked |>
    dplyr::filter(importer_iso3 == "CHN") |>
    dplyr::transmute(
      iso3c = exporter_iso3,
      country_name = country_name(exporter_iso3),
      year,
      china_rank = partner_rank,
      china_exports = exports,
      export_total,
      china_share = dplyr::if_else(export_total > 0, china_exports / export_total, NA_real_),
      top_partner,
      top_partner_name = country_name(top_partner),
      top_exports,
      second_partner,
      second_partner_name = country_name(second_partner),
      second_exports,
      china_top = as.integer(china_rank == 1L & china_exports > 0),
      competitor_partner = dplyr::if_else(china_rank == 1L, second_partner, top_partner),
      competitor_partner_name = country_name(competitor_partner),
      competitor_exports = dplyr::if_else(china_rank == 1L, second_exports, top_exports),
      china_margin_vs_competitor = china_exports - competitor_exports,
      china_margin_over_second = dplyr::if_else(china_rank == 1L, china_exports - second_exports, NA_real_),
      china_gap_to_top = dplyr::if_else(china_rank == 1L, 0, top_exports - china_exports)
    ) |>
    dplyr::arrange(iso3c, year)
}

rank_panel <- build_export_rank_panel(trade_data)

rank_tie_diagnostics <- trade_data |>
  dplyr::filter(!is.na(year), !is.na(exporter_iso3), !is.na(importer_iso3)) |>
  dplyr::filter(exporter_iso3 != importer_iso3) |>
  dplyr::mutate(exports = dplyr::coalesce(as.numeric(exports), 0)) |>
  dplyr::group_by(year, exporter_iso3, exports) |>
  dplyr::summarise(n_partners_same_exports = dplyr::n(), .groups = "drop") |>
  dplyr::filter(n_partners_same_exports > 1L) |>
  dplyr::summarise(
    n_tied_exporter_year_values = dplyr::n(),
    n_brazil_tied_exporter_year_values = sum(exporter_iso3 == "BRA"),
    .groups = "drop"
  )

brazil_rank <- rank_panel |>
  dplyr::filter(iso3c == "BRA", year >= 2000, year <= 2012) |>
  dplyr::mutate(
    china_share_pct = 100 * china_share,
    china_margin_vs_competitor_raw_units = china_margin_vs_competitor
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    year,
    china_rank,
    china_top,
    china_exports,
    export_total,
    china_share,
    china_share_pct,
    top_partner,
    top_partner_name,
    top_exports,
    second_partner,
    second_partner_name,
    second_exports,
    competitor_partner,
    competitor_partner_name,
    competitor_exports,
    china_margin_vs_competitor,
    china_margin_over_second,
    china_gap_to_top
  )

stopifnot(nrow(brazil_rank) == 13L)
stopifnot(all(2000:2012 %in% brazil_rank$year))
stopifnot(!anyDuplicated(brazil_rank$year))
stopifnot(!anyNA(brazil_rank$china_rank))
stopifnot(!anyNA(brazil_rank$china_share))
stopifnot(!anyNA(brazil_rank$china_margin_vs_competitor))

brazil_key_years <- brazil_rank |>
  dplyr::filter(year %in% c(2003L, 2005L, 2009L)) |>
  dplyr::mutate(
    diagnostic_role = dplyr::case_when(
      year == 2003L ~ "volume growth / ordinal promotion, no rank-1 reversal",
      year == 2005L ~ "continued China trade growth, no rank-1 reversal",
      year == 2009L ~ "rank-1 reversal: China displaces the United States",
      TRUE ~ ""
    )
  ) |>
  dplyr::select(
    year,
    diagnostic_role,
    china_rank,
    china_top,
    china_share,
    china_margin_vs_competitor,
    competitor_partner,
    top_partner,
    second_partner
  )

stopifnot((brazil_key_years |> dplyr::filter(year == 2003L) |> dplyr::pull(china_top)) == 0L)
stopifnot((brazil_key_years |> dplyr::filter(year == 2005L) |> dplyr::pull(china_top)) == 0L)
stopifnot((brazil_key_years |> dplyr::filter(year == 2009L) |> dplyr::pull(china_top)) == 1L)
stopifnot((brazil_key_years |> dplyr::filter(year == 2009L) |> dplyr::pull(second_partner)) == "USA")

readr::write_csv(brazil_rank, brazil_rank_path)
readr::write_csv(brazil_key_years, brazil_key_years_path)

rank_plot_data <- brazil_rank |>
  dplyr::select(
    year,
    china_share,
    china_rank,
    china_margin_vs_competitor,
    top_partner_name,
    second_partner_name
  )

share_plot <- ggplot(rank_plot_data, aes(x = year, y = 100 * china_share)) +
  geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35", linewidth = 0.45) +
  geom_line(colour = "#1B7837", linewidth = 0.9) +
  geom_point(colour = "#1B7837", size = 1.9) +
  scale_x_continuous(breaks = seq(2000, 2012, by = 2)) +
  labs(
    title = "A. China export share",
    x = NULL,
    y = "Share of Brazil exports (%)"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))

rank_plot <- ggplot(rank_plot_data, aes(x = year, y = china_rank)) +
  geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35", linewidth = 0.45) +
  geom_step(colour = "#2166AC", linewidth = 0.9, direction = "mid") +
  geom_point(colour = "#2166AC", size = 1.9) +
  scale_x_continuous(breaks = seq(2000, 2012, by = 2)) +
  scale_y_reverse(breaks = sort(unique(rank_plot_data$china_rank))) +
  labs(
    title = "B. China's ordinal rank",
    x = NULL,
    y = "Rank among export destinations"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))

margin_plot <- ggplot(rank_plot_data, aes(x = year, y = china_margin_vs_competitor)) +
  geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.45) +
  geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35", linewidth = 0.45) +
  geom_col(aes(fill = china_margin_vs_competitor >= 0), width = 0.72, show.legend = FALSE) +
  scale_fill_manual(values = c("TRUE" = "#B2182B", "FALSE" = "#762A83")) +
  scale_x_continuous(breaks = seq(2000, 2012, by = 2)) +
  labs(
    title = "C. China margin over current competitor",
    x = "Year",
    y = "China exports minus top/second partner exports"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), plot.title = element_text(face = "bold"))

brazil_rank_volume_plot <- (share_plot / rank_plot / margin_plot) +
  patchwork::plot_annotation(
    title = "Figure 1. Brazil: continuous China trade share versus discrete rank reversal",
    caption = paste(
      "Notes: Export shares and margins use the directed export-destination portfolio from the ITPDE target.",
      "Panel C is negative before China is rank 1 because it subtracts the current leader; after China is rank 1 it subtracts the second partner.",
      "The dashed line marks 2009, when China becomes Brazil's largest export destination."
    )
  )

ggsave(brazil_fig_png, brazil_rank_volume_plot, width = 8, height = 8.8, dpi = 320)
ggsave(brazil_fig_pdf, brazil_rank_volume_plot, width = 8, height = 8.8)

make_covariate_array <- function(data, covariate_cols) {
  stopifnot(length(covariate_cols) > 0L)
  unit_levels <- unique(data$iso3c)
  time_levels <- sort(unique(data$year))
  x_array <- array(
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
      tidyr::pivot_wider(
        id_cols = iso3c,
        names_from = year,
        values_from = value
      ) |>
      dplyr::arrange(iso3c)

    x_array[, , k] <- wide |>
      dplyr::select(dplyr::all_of(as.character(time_levels))) |>
      as.matrix()
  }

  x_array
}

fit_sdid_goal3 <- function(data, time_treatment, time_end, covariate_cols,
                           filter_latin_america = FALSE) {
  set.seed(12345)
  fit_data <- data
  if (filter_latin_america) {
    fit_data <- fit_data |>
      dplyr::filter(latin_america)
  }

  fit_data <- fit_data |>
    dplyr::filter(year < time_end) |>
    dplyr::mutate(treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1L, 0L)) |>
    dplyr::arrange(as.integer(iso3c == "BRA"), iso3c, year)

  if (anyNA(fit_data |> dplyr::select(dplyr::all_of(covariate_cols)))) {
    stop("fit_sdid_goal3: covariate matrix has missing values.")
  }

  x_array <- make_covariate_array(fit_data, covariate_cols)

  panel_data <- fit_data |>
    dplyr::mutate(
      treatment = as.integer(treatment),
      year = as.integer(year),
      iso3c = as.factor(iso3c),
      Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()

  setup <- synthdid::panel.matrices(panel_data)
  synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0, X = x_array)
}

summarise_sdid_fit <- function(fit, compute_se = TRUE) {
  estimate <- as.numeric(fit)
  se <- if (compute_se) {
    tryCatch(
      as.numeric(sqrt(vcov(fit, method = "placebo"))),
      error = function(e) NA_real_
    )
  } else {
    NA_real_
  }
  tibble::tibble(
    estimate = estimate,
    se_placebo = se,
    z = estimate / se,
    p_value = 2 * stats::pnorm(-abs(estimate / se)),
    ci_95_low = estimate - stats::qnorm(0.975) * se,
    ci_95_high = estimate + stats::qnorm(0.975) * se
  )
}

read_sdid_target_pair <- function(timing_test, fit_target, se_target) {
  fit <- safe_tar_read(fit_target)
  se <- safe_tar_read(se_target)

  tibble::tibble(
    timing_test = timing_test,
    target_fit = fit_target,
    target_se = se_target,
    target_estimate = if (inherits(fit, "goal3_tar_read_error")) NA_real_ else as.numeric(fit),
    target_se_placebo = if (inherits(se, "goal3_tar_read_error")) NA_real_ else as.numeric(se),
    target_read_error = paste(
      c(
        if (inherits(fit, "goal3_tar_read_error")) paste0(fit_target, ": ", fit$error) else "",
        if (inherits(se, "goal3_tar_read_error")) paste0(se_target, ": ", se$error) else ""
      ),
      collapse = ""
    )
  )
}

pipeline_covariates <- c(
  "gpi",
  "perc_trade_with_us",
  "perc_trade_with_china",
  "pci_cur",
  "exachange_rate",
  "distance_us",
  "us_power_gap",
  "hog_left",
  "CA_GDP",
  "govdef_GDP",
  intersect(
    c("inst_parliamentary", "inst_military_exec", "us_trade_agreement"),
    names(synth_data)
  )
)
missing_pipeline_covariates <- setdiff(pipeline_covariates, names(synth_data))
if (length(missing_pipeline_covariates) > 0L) {
  stop(
    "Missing expected SDiD covariates in synth_data: ",
    paste(missing_pipeline_covariates, collapse = ", ")
  )
}

all_covariates <- pipeline_covariates
trade_share_covariates <- c("perc_trade_with_china", "perc_trade_with_us")
without_trade_share_covariates <- setdiff(all_covariates, trade_share_covariates)

sdid_specs <- tibble::tribble(
  ~timing_test, ~nominal_treatment_year, ~time_treatment, ~time_end, ~interpretation,
  "actual_2009_rank_reversal", 2009L, 2008L, 2016L, "China becomes Brazil's largest export destination.",
  "placebo_2003_growth_rank2", 2003L, 2002L, 2009L, "China trade is growing and China reaches rank 2, but it does not become rank 1.",
  "placebo_2005_growth_no_rank1", 2005L, 2004L, 2009L, "China trade keeps growing before the rank-1 reversal.",
  "post_placebo_2012_later_shock", 2012L, 2011L, 2019L, "Timing falsification for a later post-2009 shock."
)

covariate_sets <- list(
  with_china_us_trade_shares = all_covariates,
  without_china_us_trade_shares = without_trade_share_covariates
)

existing_sdid_targets <- dplyr::bind_rows(
  read_sdid_target_pair("actual_2009_rank_reversal", "synth_fit", "se_synth"),
  read_sdid_target_pair("placebo_2003_growth_rank2", "placebo_teste_treatment02", "se_synth_placebo2"),
  read_sdid_target_pair("placebo_2005_growth_no_rank1", "placebo_teste_treatment04", "se_synth_placebo3"),
  read_sdid_target_pair("post_placebo_2012_later_shock", "placebo_teste_treatment11", "se_synth_placebo1")
)

sdid_results <- dplyr::bind_rows(lapply(seq_len(nrow(sdid_specs)), function(i) {
  spec <- sdid_specs[i, ]
  dplyr::bind_rows(lapply(names(covariate_sets), function(cov_set_name) {
    covariates <- covariate_sets[[cov_set_name]]
    fit <- fit_sdid_goal3(
      data = synth_data,
      time_treatment = spec$time_treatment,
      time_end = spec$time_end,
      covariate_cols = covariates,
      filter_latin_america = FALSE
    )

    if (identical(cov_set_name, "with_china_us_trade_shares")) {
      target_row <- existing_sdid_targets |>
        dplyr::filter(timing_test == spec$timing_test) |>
        dplyr::slice_head(n = 1)

      estimate <- target_row$target_estimate
      se <- target_row$target_se_placebo
      result <- tibble::tibble(
        estimate = estimate,
        se_placebo = se,
        z = estimate / se,
        p_value = 2 * stats::pnorm(-abs(estimate / se)),
        ci_95_low = estimate - stats::qnorm(0.975) * se,
        ci_95_high = estimate + stats::qnorm(0.975) * se,
        reestimated_estimate_for_validation = as.numeric(fit),
        estimate_source = "existing target",
        inference_source = "existing target placebo SE"
      )
    } else {
      result <- summarise_sdid_fit(fit, compute_se = FALSE) |>
        dplyr::mutate(
          reestimated_estimate_for_validation = estimate,
          estimate_source = "local re-estimation",
          inference_source = "SE not recomputed for no-share sensitivity"
        )
    }

    result |>
      dplyr::mutate(
        timing_test = spec$timing_test,
        nominal_treatment_year = spec$nominal_treatment_year,
        time_end = spec$time_end,
        covariate_set = cov_set_name,
        n_covariates = length(covariates),
        covariates = paste(covariates, collapse = "; "),
        n_obs = nrow(synth_data |> dplyr::filter(year < spec$time_end)),
        n_countries = dplyr::n_distinct((synth_data |> dplyr::filter(year < spec$time_end))$iso3c),
        interpretation = spec$interpretation,
        .before = 1
      )
  }))
}))

sdid_results <- sdid_results |>
  dplyr::arrange(
    factor(
      timing_test,
      levels = c(
        "actual_2009_rank_reversal",
        "placebo_2003_growth_rank2",
        "placebo_2005_growth_no_rank1",
        "post_placebo_2012_later_shock"
      )
    ),
    covariate_set
  )

sdid_target_validation <- sdid_results |>
  dplyr::filter(covariate_set == "with_china_us_trade_shares") |>
  dplyr::select(
    timing_test,
    reestimated_estimate = reestimated_estimate_for_validation,
    target_used_estimate = estimate,
    target_used_se_placebo = se_placebo
  ) |>
  dplyr::left_join(existing_sdid_targets, by = "timing_test") |>
  dplyr::mutate(
    estimate_difference = reestimated_estimate - target_estimate,
    se_difference = target_used_se_placebo - target_se_placebo,
    validation_status = dplyr::case_when(
      !is.na(estimate_difference) & abs(estimate_difference) < 0.000001 &
        !is.na(se_difference) & abs(se_difference) < 0.000001 ~ "matches target",
      !is.na(estimate_difference) & abs(estimate_difference) < 0.000001 ~ "estimate matches target; SE differs or unavailable",
      TRUE ~ "check difference"
    )
  )

readr::write_csv(sdid_results, sdid_comparison_path)
readr::write_csv(sdid_target_validation, sdid_target_validation_path)

sdid_plot_data <- sdid_results |>
  dplyr::mutate(
    timing_label = dplyr::case_when(
      timing_test == "actual_2009_rank_reversal" ~ "2009 actual",
      timing_test == "placebo_2003_growth_rank2" ~ "2003 placebo",
      timing_test == "placebo_2005_growth_no_rank1" ~ "2005 placebo",
      timing_test == "post_placebo_2012_later_shock" ~ "2012 post-placebo",
      TRUE ~ timing_test
    ),
    timing_label = factor(
      timing_label,
      levels = c("2003 placebo", "2005 placebo", "2009 actual", "2012 post-placebo")
    ),
    covariate_label = dplyr::case_when(
      covariate_set == "with_china_us_trade_shares" ~ "With China/US trade shares",
      covariate_set == "without_china_us_trade_shares" ~ "Without China/US trade shares",
      TRUE ~ covariate_set
    ),
    ci_plot_low = dplyr::coalesce(ci_95_low, estimate),
    ci_plot_high = dplyr::coalesce(ci_95_high, estimate)
  )

sdid_comparison_plot <- ggplot(
  sdid_plot_data,
  aes(x = timing_label, y = estimate, colour = covariate_label)
) +
  geom_hline(yintercept = 0, linewidth = 0.45, colour = "grey45") +
  geom_pointrange(
    aes(ymin = ci_plot_low, ymax = ci_plot_high),
    position = position_dodge(width = 0.55),
    linewidth = 0.45
  ) +
  scale_colour_manual(values = c(
    "With China/US trade shares" = "#B2182B",
    "Without China/US trade shares" = "#2166AC"
  )) +
  labs(
    title = "Figure 2. Brazil SDiD timing tests with and without continuous trade-share covariates",
    x = NULL,
    y = "SDiD estimate: absolute UNGA ideal-point distance to China",
    colour = NULL,
    caption = "Notes: Intervals use existing target placebo standard errors for with-share rows; no-share rows are point-estimate sensitivity checks. Lower estimates imply reduced distance to China."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    axis.text.x = element_text(angle = 20, hjust = 1),
    plot.caption = element_text(hjust = 0, size = 8)
  )

ggsave(sdid_fig_png, sdid_comparison_plot, width = 8.2, height = 5.2, dpi = 320)
ggsave(sdid_fig_pdf, sdid_comparison_plot, width = 8.2, height = 5.2)

placebo_tests <- sdid_results |>
  dplyr::filter(covariate_set == "with_china_us_trade_shares") |>
  dplyr::left_join(
    brazil_rank |>
      dplyr::select(
        nominal_treatment_year = year,
        china_rank,
        china_share,
        china_margin_vs_competitor,
        top_partner,
        second_partner,
        competitor_partner
      ),
    by = "nominal_treatment_year"
  ) |>
  dplyr::mutate(
    rank_volume_test_role = dplyr::case_when(
      nominal_treatment_year == 2003L ~ "Growth/promotion placebo: China is not #1.",
      nominal_treatment_year == 2005L ~ "Growth placebo: China is not #1.",
      nominal_treatment_year == 2009L ~ "Actual rank-1 reversal.",
      nominal_treatment_year == 2012L ~ "Later-shock placebo after rank reversal.",
      TRUE ~ ""
    ),
    rank1_reversal = china_rank == 1L & nominal_treatment_year == 2009L
  ) |>
  dplyr::select(
    nominal_treatment_year,
    timing_test,
    rank_volume_test_role,
    china_rank,
    rank1_reversal,
    china_share,
    china_margin_vs_competitor,
    top_partner,
    second_partner,
    competitor_partner,
    estimate,
    se_placebo,
    p_value,
    ci_95_low,
    ci_95_high
  ) |>
  dplyr::arrange(nominal_treatment_year)

readr::write_csv(placebo_tests, placebo_tests_path)

entry_rows <- china_top_panel |>
  dplyr::filter(!is.na(china_top)) |>
  dplyr::arrange(iso3c, year) |>
  dplyr::group_by(iso3c) |>
  dplyr::mutate(
    previous_china_top = dplyr::lag(china_top, default = 0L),
    entry = china_top == 1L & previous_china_top == 0L
  ) |>
  dplyr::ungroup() |>
  dplyr::filter(entry) |>
  dplyr::select(iso3c, country_name, entry_year = year)

cross_country_entries <- entry_rows |>
  dplyr::left_join(
    rank_panel |>
      dplyr::select(
        iso3c,
        entry_year = year,
        china_rank_at_entry = china_rank,
        china_share_at_entry = china_share,
        china_exports_at_entry = china_exports,
        export_total_at_entry = export_total,
        china_margin_over_second_at_entry = china_margin_over_second,
        china_margin_vs_competitor_at_entry = china_margin_vs_competitor,
        top_partner_at_entry = top_partner,
        second_partner_at_entry = second_partner
      ),
    by = c("iso3c", "entry_year")
  ) |>
  dplyr::left_join(
    rank_panel |>
      dplyr::transmute(
        iso3c,
        entry_year = year + 1L,
        china_rank_previous_year = china_rank,
        china_share_previous_year = china_share,
        china_margin_vs_competitor_previous_year = china_margin_vs_competitor,
        top_partner_previous_year = top_partner,
        second_partner_previous_year = second_partner
      ),
    by = c("iso3c", "entry_year")
  ) |>
  dplyr::mutate(
    country_name = dplyr::coalesce(country_name, country_name(iso3c)),
    entry_share_pct = 100 * china_share_at_entry,
    previous_share_pct = 100 * china_share_previous_year,
    margin_raw_units = china_margin_over_second_at_entry,
    previous_gap_raw_units = -china_margin_vs_competitor_previous_year,
    displaced_partner = top_partner_previous_year
  ) |>
  dplyr::arrange(entry_year, iso3c)

cross_country_summary <- cross_country_entries |>
  dplyr::summarise(
    n_entries = dplyr::n(),
    n_countries = dplyr::n_distinct(iso3c),
    first_entry_year = min(entry_year, na.rm = TRUE),
    last_entry_year = max(entry_year, na.rm = TRUE),
    min_china_share_at_entry = min(china_share_at_entry, na.rm = TRUE),
    p25_china_share_at_entry = as.numeric(stats::quantile(china_share_at_entry, 0.25, na.rm = TRUE)),
    median_china_share_at_entry = stats::median(china_share_at_entry, na.rm = TRUE),
    mean_china_share_at_entry = mean(china_share_at_entry, na.rm = TRUE),
    p75_china_share_at_entry = as.numeric(stats::quantile(china_share_at_entry, 0.75, na.rm = TRUE)),
    max_china_share_at_entry = max(china_share_at_entry, na.rm = TRUE),
    min_margin_over_second = min(china_margin_over_second_at_entry, na.rm = TRUE),
    median_margin_over_second = stats::median(china_margin_over_second_at_entry, na.rm = TRUE),
    max_margin_over_second = max(china_margin_over_second_at_entry, na.rm = TRUE),
    corr_entry_year_share = stats::cor(entry_year, china_share_at_entry, use = "complete.obs")
  )

china_top_trade_panel <- china_top_panel |>
  dplyr::select(
    iso3c,
    country_name,
    year,
    china_top,
    abs_distance_china
  ) |>
  dplyr::left_join(
    rank_panel |>
      dplyr::select(
        iso3c,
        year,
        china_rank,
        china_share,
        china_margin_vs_competitor,
        china_margin_over_second,
        china_gap_to_top
      ),
    by = c("iso3c", "year")
  )

cross_country_join_diagnostics <- tibble::tibble(
  diagnostic = c(
    "panel country-years",
    "panel countries",
    "treated country-years",
    "treated countries",
    "missing China export share, all panel rows",
    "missing signed China-vs-competitor margin, all panel rows",
    "missing China-over-second margin among treated rows",
    "entry spells",
    "entry spells missing entry-year share",
    "entry spells missing entry-year China-over-second margin",
    "entry spells missing previous-year share",
    "entry spells missing previous-year gap"
  ),
  value = c(
    nrow(china_top_trade_panel),
    dplyr::n_distinct(china_top_trade_panel$iso3c),
    sum(china_top_trade_panel$china_top == 1L, na.rm = TRUE),
    china_top_trade_panel |>
      dplyr::filter(china_top == 1L) |>
      dplyr::summarise(n = dplyr::n_distinct(iso3c)) |>
      dplyr::pull(n),
    sum(is.na(china_top_trade_panel$china_share)),
    sum(is.na(china_top_trade_panel$china_margin_vs_competitor)),
    sum(is.na(china_top_trade_panel$china_margin_over_second[which(china_top_trade_panel$china_top == 1L)])),
    nrow(cross_country_entries),
    sum(is.na(cross_country_entries$china_share_at_entry)),
    sum(is.na(cross_country_entries$china_margin_over_second_at_entry)),
    sum(is.na(cross_country_entries$china_share_previous_year)),
    sum(is.na(cross_country_entries$china_margin_vs_competitor_previous_year))
  )
)

readr::write_csv(cross_country_entries, cross_country_entries_path)
readr::write_csv(cross_country_summary, cross_country_summary_path)
readr::write_csv(cross_country_join_diagnostics, cross_country_join_diagnostics_path)

entry_plot_data <- cross_country_entries |>
  dplyr::filter(!is.na(china_share_at_entry), !is.na(china_margin_over_second_at_entry)) |>
  dplyr::mutate(
    highlight_brazil = iso3c == "BRA",
    margin_abs = abs(china_margin_over_second_at_entry)
  )

entry_share_margin_plot <- ggplot(
  entry_plot_data,
  aes(x = entry_year, y = 100 * china_share_at_entry)
) +
  geom_point(
    aes(size = margin_abs, colour = highlight_brazil),
    alpha = 0.78
  ) +
  geom_text(
    data = entry_plot_data |> dplyr::filter(highlight_brazil),
    aes(label = "Brazil"),
    nudge_x = 0.45,
    nudge_y = 1.2,
    size = 3.2,
    colour = "#B2182B"
  ) +
  scale_colour_manual(values = c("TRUE" = "#B2182B", "FALSE" = "#2166AC"), guide = "none") +
  scale_size_continuous(name = "Margin over #2\n(raw export units)", range = c(1.8, 7.5)) +
  scale_x_continuous(breaks = seq(
    min(entry_plot_data$entry_year, na.rm = TRUE),
    max(entry_plot_data$entry_year, na.rm = TRUE),
    by = 3
  )) +
  labs(
    title = "Figure 3. Cross-country rank reversals occur at heterogeneous China export shares",
    x = "Entry year: China becomes #1 export destination",
    y = "China export share at entry (%)",
    caption = paste(
      "Notes: Scope-conditioned China-top panel. Point size is China's margin over the second-ranked export destination at entry.",
      "Contemporaneous share and margin are diagnostic descriptors, not preferred controls."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0, size = 8)
  )

ggsave(entry_fig_png, entry_share_margin_plot, width = 8.4, height = 5.5, dpi = 320)
ggsave(entry_fig_pdf, entry_share_margin_plot, width = 8.4, height = 5.5)

cross_country_feasibility <- tibble::tribble(
  ~candidate_diagnostic_or_model, ~technical_feasibility, ~causal_status, ~recommended_use, ~reason,
  "Contemporaneous China export share in fect IFE", "Technically feasible after joining rank_panel to china_top_panel.", "Potential post-treatment control.", "Do not use as preferred estimate; report only as sensitivity with strong caveat if at all.", "China share is part of the process that makes China rank #1 and can be affected by the treatment period itself.",
  "Contemporaneous China margin over second partner in fect IFE", "Technically feasible but mechanically tied to treatment.", "Bad control / near-definition of treatment.", "Do not include as a control in the main model.", "The margin is positive by construction when China is #1 and therefore absorbs the ordinal treatment contrast.",
  "Last pre-entry China export share for treated cohorts", "Feasible as an onset-level diagnostic; requires a defensible pseudo-entry rule for never-treated controls to become a regression covariate.", "Valid pre-treatment descriptor for treated entries.", "Use descriptively now; model-based use requires a separate design.", "It summarizes commercial exposure before rank reversal without conditioning on post-entry outcomes.",
  "Last pre-entry gap to current leader", "Feasible as an onset-level diagnostic for treated entries.", "Valid pre-treatment descriptor for treated entries.", "Use descriptively to show whether entry occurred from close races or large jumps.", "It captures how close China was to rank 1 before treatment without using post-treatment margin.",
  "Entry-year share and entry-year margin distribution", "Feasible and implemented here.", "Descriptive, not a causal control.", "Use as rank-versus-volume evidence that no single trade-share threshold defines treatment.", "Shows heterogeneity in the material level at which the same ordinal status change occurs.",
  "High-order polynomials of China trade share", "Technically feasible.", "Not recommended.", "Do not use as the primary answer.", "Unstable in small panels and does not solve the causal bad-control problem."
)

readr::write_csv(cross_country_feasibility, cross_country_feasibility_path)

utils::capture.output(sessionInfo(), file = session_info_path)

target_summary_for_report <- target_audit |>
  dplyr::transmute(
    target = name,
    role = diagnostic_role,
    complete = complete_without_error,
    has_share = contains_trade_share,
    has_rank = contains_china_rank,
    has_margin = contains_margin,
    margin_status
  )

brazil_key_for_report <- brazil_key_years |>
  dplyr::mutate(
    china_share = 100 * china_share
  ) |>
  dplyr::rename(
    china_share_pct = china_share,
    signed_margin = china_margin_vs_competitor
  )

sdid_for_report <- sdid_results |>
  dplyr::mutate(
    timing = dplyr::case_when(
      timing_test == "actual_2009_rank_reversal" ~ "2009 actual",
      timing_test == "placebo_2003_growth_rank2" ~ "2003 placebo",
      timing_test == "placebo_2005_growth_no_rank1" ~ "2005 placebo",
      timing_test == "post_placebo_2012_later_shock" ~ "2012 post-placebo",
      TRUE ~ timing_test
    ),
    covariate_set = dplyr::case_when(
      covariate_set == "with_china_us_trade_shares" ~ "with trade shares",
      covariate_set == "without_china_us_trade_shares" ~ "without trade shares",
      TRUE ~ covariate_set
    )
  ) |>
  dplyr::select(
    timing,
    covariate_set,
    estimate,
    se_placebo,
    p_value,
    ci_95_low,
    ci_95_high,
    n_covariates,
    n_obs,
    n_countries
  )

placebo_for_report <- placebo_tests |>
  dplyr::filter(nominal_treatment_year %in% c(2003L, 2005L, 2009L)) |>
  dplyr::mutate(china_share_pct = 100 * china_share) |>
  dplyr::select(
    year = nominal_treatment_year,
    rank_volume_test_role,
    china_rank,
    rank1_reversal,
    china_share_pct,
    signed_margin = china_margin_vs_competitor,
    estimate,
    se_placebo,
    p_value
  )

entry_summary_for_report <- cross_country_summary |>
  dplyr::mutate(
    min_china_share_at_entry = 100 * min_china_share_at_entry,
    p25_china_share_at_entry = 100 * p25_china_share_at_entry,
    median_china_share_at_entry = 100 * median_china_share_at_entry,
    mean_china_share_at_entry = 100 * mean_china_share_at_entry,
    p75_china_share_at_entry = 100 * p75_china_share_at_entry,
    max_china_share_at_entry = 100 * max_china_share_at_entry
  )

get_sdid_row <- function(timing, covariate) {
  sdid_results |>
    dplyr::filter(timing_test == timing, covariate_set == covariate) |>
    dplyr::slice_head(n = 1)
}

actual_with <- get_sdid_row(
  "actual_2009_rank_reversal",
  "with_china_us_trade_shares"
)
actual_without <- get_sdid_row(
  "actual_2009_rank_reversal",
  "without_china_us_trade_shares"
)
pre_placebos_with <- sdid_results |>
  dplyr::filter(
    timing_test %in% c("placebo_2003_growth_rank2", "placebo_2005_growth_no_rank1"),
    covariate_set == "with_china_us_trade_shares"
  )

actual_difference <- actual_without$estimate - actual_with$estimate
same_sign_actual <- sign(actual_with$estimate) == sign(actual_without$estimate)
relative_difference <- abs(actual_difference) / max(abs(actual_with$estimate), .Machine$double.eps)
actual_stability_status <- if (same_sign_actual && relative_difference <= 0.25) {
  "same sign and comparable magnitude"
} else if (same_sign_actual) {
  "same sign but different magnitude"
} else {
  "different sign"
}

placebo_estimates_available <- all(!is.na(pre_placebos_with$estimate)) &&
  !is.na(actual_with$estimate)
placebo_p_values_available <- all(!is.na(pre_placebos_with$p_value))
placebos_smaller <- placebo_estimates_available &&
  all(abs(pre_placebos_with$estimate) < abs(actual_with$estimate))
placebos_not_conventionally_significant <- placebo_p_values_available &&
  all(pre_placebos_with$p_value > 0.05)
placebo_status <- dplyr::case_when(
  !placebo_estimates_available ~
    "at least one pre-2009 growth placebo estimate is unavailable, so the rank-versus-volume timing diagnostic is incomplete",
  !placebo_p_values_available & placebos_smaller ~
    "the pre-2009 growth placebo estimates are smaller than the 2009 estimate, but at least one placebo p-value is unavailable",
  !placebo_p_values_available ~
    "at least one pre-2009 growth placebo p-value is unavailable, so inference for this diagnostic is incomplete",
  placebos_smaller & placebos_not_conventionally_significant ~
    "the pre-2009 growth placebos are smaller than the 2009 estimate and not conventionally significant",
  placebos_smaller ~
    "the pre-2009 growth placebos are smaller than the 2009 estimate, though inference is not uniformly null",
  TRUE ~
    "at least one pre-2009 growth placebo is not smaller than the 2009 estimate, so this diagnostic should be interpreted cautiously"
)

actual_stability_sentence <- paste0(
  "For the 2009 treatment, the SDiD estimate with China/US export-share covariates is ",
  fmt_num(actual_with$estimate),
  " (placebo SE = ", fmt_num(actual_with$se_placebo),
  ", p = ", fmt_num(actual_with$p_value),
  "); removing those two trade-share covariates gives ",
  fmt_num(actual_without$estimate),
  " (placebo SE = ", fmt_num(actual_without$se_placebo),
  ", p = ", fmt_num(actual_without$p_value),
  "). The comparison is therefore: ",
  actual_stability_status,
  "."
)

placebo_status_sentence <- paste0(
  "For the 2003 and 2005 pre-treatment timing tests, ",
  placebo_status,
  ". These are timing falsifications, not equivalence tests."
)

rank_vs_volume_verdict <- if (
  same_sign_actual &&
    relative_difference <= 0.25 &&
    placebos_smaller &&
    placebos_not_conventionally_significant
) {
  "The diagnostics support the claim that the 2009 Brazil treatment is empirically distinguishable from smooth export-volume growth."
} else if (same_sign_actual && placebos_smaller) {
  "The diagnostics are directionally consistent with the rank-versus-volume claim, but at least one criterion is weaker than the strongest version of the argument."
} else {
  "The diagnostics are mixed and should be read as a partial rank-versus-volume assessment rather than decisive evidence."
}

bottom_line_sentence <- paste0(
  rank_vs_volume_verdict,
  " China's export-destination share rises before 2009, but the ordinal category switches only in 2009. ",
  actual_stability_sentence,
  " ",
  placebo_status_sentence
)

manual_rank_sentence <- if (placebos_smaller && placebos_not_conventionally_significant) {
  "The pre-2009 placebo estimates are smaller than the 2009 estimate and not conventionally significant, which weighs against a simple smooth-volume interpretation."
} else if (placebos_smaller) {
  "The pre-2009 placebo estimates are smaller than the 2009 estimate, although their inferential pattern requires a cautious statement."
} else {
  "The pre-2009 placebo pattern is not clean enough to rule out smooth-volume explanations on its own."
}

manual_trade_share_sentence <- if (same_sign_actual && relative_difference <= 0.25) {
  "Removing the China and United States export-share covariates leaves the 2009 estimate with the same sign and comparable magnitude."
} else if (same_sign_actual) {
  "Removing the China and United States export-share covariates leaves the 2009 estimate with the same sign, although the magnitude changes enough to warrant caution."
} else {
  "Removing the China and United States export-share covariates changes the sign of the 2009 estimate, so this diagnostic should not be used to claim robustness to trade-share controls."
}

entry_share_range_pct <- entry_summary_for_report$max_china_share_at_entry -
  entry_summary_for_report$min_china_share_at_entry
entry_heterogeneity_sentence <- if (!is.na(entry_share_range_pct) && entry_share_range_pct >= 10) {
  paste0(
    "Figure 3 shows that countries reach China rank 1 at heterogeneous China export-share levels and with heterogeneous margins over the second partner; the entry-share range is ",
    fmt_num(entry_share_range_pct, digits = 1),
    " percentage points. This weighs against interpreting treatment as a single hidden export-share threshold."
  )
} else {
  paste0(
    "Figure 3 reports the cross-country distribution of China export-share levels and margins at rank-1 entry. The entry-share range is ",
    fmt_num(entry_share_range_pct, digits = 1),
    " percentage points, so the strength of the hidden-threshold diagnostic should be read from Table 5 rather than assumed."
  )
}

files_written <- c(
  target_audit_path,
  brazil_rank_path,
  brazil_key_years_path,
  sdid_comparison_path,
  placebo_tests_path,
  cross_country_entries_path,
  cross_country_summary_path,
  cross_country_feasibility_path,
  cross_country_join_diagnostics_path,
  sdid_target_validation_path,
  brazil_fig_png,
  brazil_fig_pdf,
  sdid_fig_png,
  sdid_fig_pdf,
  entry_fig_png,
  entry_fig_pdf,
  session_info_path,
  report_path
)

report_lines <- c(
  "# Goal 3: rank-versus-volume diagnostic",
  "",
  paste0("Date: ", run_date),
  "",
  paste0("Run timestamp: ", run_timestamp),
  "",
  paste0("Script: `", script_path, "`"),
  "",
  "This report reads existing targets with `targets::tar_read()` and writes diagnostic outputs only. It does not run `targets::tar_make()` and does not modify `_targets.R`, `_targets/`, `_targets.yaml`, or `paper_v4.Rmd`.",
  "",
  "## Bottom line",
  "",
  bottom_line_sentence,
  "",
  "## Causal contract",
  "",
  "- Unit and outcome: Brazil-year for the SDiD case study; outcome is Brazil's absolute UNGA ideal-point distance to China.",
  "- Treatment contrast: China becoming Brazil's largest export destination in 2009, not a generic increase in China trade share.",
  "- Alternative explanation targeted here: alignment follows a continuous, possibly nonlinear trade-volume path, commodity demand, or China trade share rather than the ordinal rank reversal.",
  "- Valid pre-treatment controls: covariates measured before treatment. The SDiD covariate array used in the existing model is treated here as model reproduction/sensitivity, not as a clean post-treatment control solution.",
  "- Potentially post-treatment variables: contemporaneous China trade share and China-over-second margin after 2009. These can describe the treatment environment, but including them as contemporaneous controls can absorb the mechanism or mechanically condition on treatment.",
  "- Estimand retained: average post-2009 SDiD effect for Brazil. These diagnostics do not redefine the estimand as a dose-response effect of trade share.",
  "",
  "## Objects and data audited",
  "",
  "Table 1. Existing target objects relevant to rank-versus-volume.",
  "",
  markdown_table(target_summary_for_report, digits = 2),
  "",
  "Rank reconstruction note: the script uses `dense_rank(desc(exports))` for China's ordinal rank, matching the project pipeline. Deterministic row order is used only to name the top and second partners when constructing signed margins. The all-portfolio tie diagnostic is:",
  "",
  markdown_table(rank_tie_diagnostics, digits = 0),
  "",
  "The key audit result is that the pipeline already stores trade shares and ordinal rank indicators, but it does not store China-over-second margin as a target. Margin is derived here from `trade_data` without changing the pipeline.",
  "",
  "## Brazil descriptive evidence",
  "",
  "Figure 1 plots the three quantities requested for Brazil around 2009: China export share, China's ordinal rank, and China's signed margin against the relevant competitor.",
  "",
  paste0("![Figure 1. Brazil rank-versus-volume diagnostics](", basename(brazil_fig_png), ")"),
  "",
  "Table 2. Key Brazil years for rank-versus-volume interpretation.",
  "",
  markdown_table(brazil_key_for_report, digits = 3),
  "",
  "The signed margin is negative before China is number one because it is measured as China exports minus the current leader's exports. It becomes positive in 2009 because China is then compared with the second-ranked partner. This is the empirical distinction the rank treatment uses: continuous share growth precedes 2009, but the categorical rank switch occurs only when the margin crosses zero.",
  "",
  "## SDiD comparison with and without trade-share covariates",
  "",
  "Figure 2 and Table 3 compare the Brazil SDiD estimates when the covariate matrix includes the existing continuous China/US trade-share variables versus when those two variables are removed. All other available SDiD covariates are left in place.",
  "",
  paste0("![Figure 2. SDiD trade-share comparison](", basename(sdid_fig_png), ")"),
  "",
  "Table 3. Brazil SDiD estimates by timing test and covariate set.",
  "",
  markdown_table(sdid_for_report, digits = 3),
  "",
  "Table 3a validates the re-estimated with-share rows against the completed targets already in `_targets/`.",
  "",
  markdown_table(sdid_target_validation, digits = 6),
  "",
  paste0(
    "The comparison should be read as a diagnostic reproduction/sensitivity exercise, not as a new preferred estimator. ",
    "In `synthdid`, covariates are supplied as an array over the estimation window, so the with-share rows reproduce the existing model rather than solve post-treatment-control concerns. ",
    actual_stability_sentence
  ),
  "",
  "## Placebos as rank-versus-volume tests",
  "",
  "Table 4 reorganizes the existing 2003 and 2005 in-time placebos as tests of the volume-growth alternative. Both years occur before the rank-1 reversal and are therefore useful because they preserve rapid China-trade growth without the salient number-one status switch.",
  "",
  markdown_table(placebo_for_report, digits = 3),
  "",
  paste0(
    "Interpretation: if continuous export-volume growth alone were sufficient to generate the alignment shift, pre-2009 placebo timings during China export growth should produce comparable effects. ",
    placebo_status_sentence
  ),
  "",
  "## Cross-country feasibility and diagnostics",
  "",
  "For the cross-country panel, contemporaneous China trade share and China-over-second margin are available after joining `trade_data` to `china_top_panel`, but their causal role differs from ordinary controls. Entry-year share and margin are excellent descriptive diagnostics; contemporaneous controls are risky because they are part of, or downstream from, the treatment definition.",
  "",
  entry_heterogeneity_sentence,
  "",
  paste0("![Figure 3. Cross-country entry share and margin](", basename(entry_fig_png), ")"),
  "",
  "Table 5. Cross-country entry-share and margin summary.",
  "",
  markdown_table(entry_summary_for_report, digits = 3),
  "",
  "Table 6. Feasibility of cross-country trade-share and margin controls/diagnostics.",
  "",
  markdown_table(cross_country_feasibility, digits = 3),
  "",
  "Table 7. Actual join/completeness diagnostics for share and margin in the scope-conditioned cross-country panel.",
  "",
  markdown_table(cross_country_join_diagnostics, digits = 0),
  "",
  "## Causal assessment",
  "",
  "### Identification",
  "",
  "The identifying claim is credible with qualifications. The design is strongest for Brazil because the treatment has a clear timing, the displaced partner is the United States, and the diagnostics separate pre-2009 trade growth from the 2009 categorical switch. The non-testable assumption remains that no Brazil-specific shock exactly at 2009 shifted UNGA alignment toward China through a path unrelated to the rank reversal.",
  "",
  "### Estimation",
  "",
  "The SDiD comparison is aligned with the estimand because it keeps the treatment binary and changes only whether continuous China/US export-share variables enter the SDiD covariate array over the estimation window. Removing trade-share covariates is a diagnostic sensitivity exercise; adding contemporaneous post-2009 trade intensity as a regression control would be a bad-control strategy because it could condition on the mechanism. For the cross-country design, entry-year share and margin are better used descriptively unless a separate pre-treatment covariate design is built.",
  "",
  "### Inference",
  "",
  "The with-share Brazil SDiD rows use the existing target placebo standard errors, appropriate for a single treated-unit synthetic design but still limited by the donor pool and by the number of plausible placebo units. The no-share rows are point-estimate sensitivity checks with no placebo SE recomputed. The 2003 and 2005 tests are timing falsifications, not proof of equivalence. The cross-country entry-share diagnostics are descriptive and do not require p-values; cross-country causal models with share/margin controls would require explicit treatment of clustering, switching exposure, and bad-control risk.",
  "",
  "## Limitations",
  "",
  "- The diagnostics do not prove that status salience is the only mechanism; they evaluate how far the 2009 rank reversal can be separated from smooth China export growth in the implemented evidence.",
  "- Commodity demand can still be a case-specific confounder if it caused both the 2009 rank reversal and Brazil-specific UNGA movement through channels not absorbed by SDiD weights or covariates.",
  "- Cross-country entry-year share and margin are descriptive. They should not be sold as a clean covariate-adjusted causal estimate.",
  "- The margin variable is in raw ITPDE export units. It is valid for within-portfolio rank diagnostics but should not be compared across countries as a normalized economic magnitude without further scaling.",
  "- High-order trade-share polynomials are deliberately not used; they are unstable in this design and do not solve the bad-control problem.",
  "",
  "## What should enter the main text",
  "",
  "- A concise figure or paragraph showing that Brazil's China trade share grew before 2009, while the ordinal rank switch occurs only in 2009.",
  paste0(
    "- The SDiD comparison with and without China/US trade-share covariates, with wording conditional on the diagnostic result: ",
    manual_trade_share_sentence
  ),
  "- A reframing of the 2003 and 2005 placebos as rank-versus-volume tests: growth and promotion without number-one status can be compared directly to the 2009 rank reversal.",
  "- A cross-country sentence noting that rank-1 entries occur at heterogeneous China export shares, so treatment is not a single hidden share threshold.",
  "- A caveat that contemporaneous trade share and margin are not preferred controls because they may be post-treatment or mechanically tied to treatment.",
  "",
  "## Suggested paragraphs for manual incorporation",
  "",
  "**Brazil rank-versus-volume paragraph.**",
  "",
  paste0(
    "A useful way to see what the treatment is not is to separate three quantities: China's export share, China's ordinal rank, and China's margin over the nearest competitor. ",
    "In Brazil, China trade was already growing before 2009, but the categorical status switch occurs only when China crosses from a lower-ranked destination to the largest export destination. ",
    "The pre-2009 placebos exploit this distinction: 2003 and 2005 are years of China-trade growth and ordinal promotion without the number-one reversal. ",
    manual_rank_sentence
  ),
  "",
  "**Trade-share covariate paragraph.**",
  "",
  paste0(
    manual_trade_share_sentence,
    " This diagnostic is not a new preferred specification; rather, it assesses whether the rank treatment is simply duplicating the continuous trade-share variables already available in the design."
  ),
  "",
  "**Cross-country caveat paragraph.**",
  "",
  paste0(
    "In the cross-country panel, China reaches the top export-destination position at very different export-share levels and with different margins over the second partner. ",
    "That heterogeneity is useful descriptively because it shows that the treatment is not a single hidden trade-share threshold. ",
    "At the same time, contemporaneous China trade share and China-over-second margin are not clean controls: after entry, they are potentially post-treatment and, in the case of the margin, mechanically linked to the rank definition. ",
    "I therefore treat them as rank-versus-volume diagnostics rather than as preferred covariate adjustments."
  ),
  "",
  "## Files generated",
  "",
  paste0("- `", files_written, "`"),
  ""
)

writeLines(report_lines, report_path, useBytes = TRUE)

cat("Wrote:\n")
cat(paste0("- ", files_written, collapse = "\n"))
cat("\n")
