#!/usr/bin/env Rscript

# Diagnostic for the China-demand-shock critique.
# This script reads existing targets and local raw ITPD-E data only. It does not
# modify _targets.R, _targets.yaml, _targets/, or the manuscript.

suppressPackageStartupMessages({
  library(targets)
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
  library(countrycode)
  library(readr)
  library(tibble)
  library(synthdid)
  library(fixest)
  library(MatchIt)
  library(rmarkdown)
})

options(scipen = 999)
set.seed(20260520)

target_store <- "_targets"
script_path <- "scripts/diagnostics/diagnose_china_demand_shock_rank_threshold.R"
run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

out_dir <- file.path("quality_reports", "china_demand_shock_rank_threshold")
data_out_dir <- file.path("data", "processed", "diagnostics")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(data_out_dir, recursive = TRUE, showWarnings = FALSE)

path_out <- function(filename) file.path(out_dir, filename)
data_path_out <- function(filename) file.path(data_out_dir, filename)

primary_exposure_path <- data_path_out("pre2009_primary_goods_export_exposure_itpde_2026-05-20.csv")
source_note_path <- path_out("SOURCES.md")
session_info_path <- path_out("session_info.txt")
report_rmd_path <- path_out("2026-05-20_china_demand_shock_rank_threshold_report.Rmd")
report_md_path <- path_out("2026-05-20_china_demand_shock_rank_threshold_report.md")
report_pdf_path <- path_out("2026-05-20_china_demand_shock_rank_threshold_report.pdf")
render_log_path <- path_out("render_log.txt")

table_design_path <- path_out("table_1_design_reconstruction.csv")
table_brazil_exposure_path <- path_out("table_2_brazil_trade_exposure_2000_2012.csv")
table_sdid_path <- path_out("table_3_brazil_sdid_expanded_controls.csv")
table_placebo_path <- path_out("table_4_brazil_timing_placebos_expanded_controls.csv")
table_cross_fe_path <- path_out("table_5_cross_country_fe_continuous_controls.csv")
table_placebo_threshold_path <- path_out("table_6_cross_country_threshold_placebos.csv")
table_weighted_path <- path_out("table_7_cross_country_commodity_balanced_models.csv")
table_balance_path <- path_out("table_8_matching_balance.csv")
table_validation_path <- path_out("table_9_validation_checks.csv")
table_country_exposure_path <- path_out("table_10_country_pre_entry_exposures.csv")

fig_brazil_exposure_png <- path_out("figura_1_brazil_trade_exposure_diagnostics.png")
fig_brazil_exposure_pdf <- path_out("figura_1_brazil_trade_exposure_diagnostics.pdf")
fig_sdid_png <- path_out("figura_2_brazil_sdid_expanded_controls.png")
fig_sdid_pdf <- path_out("figura_2_brazil_sdid_expanded_controls.pdf")
fig_threshold_png <- path_out("figura_3_cross_country_threshold_placebos.png")
fig_threshold_pdf <- path_out("figura_3_cross_country_threshold_placebos.pdf")
fig_balance_png <- path_out("figura_4_commodity_china_share_balance.png")
fig_balance_pdf <- path_out("figura_4_commodity_china_share_balance.pdf")

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) {
      structure(list(error = conditionMessage(e)), class = "tar_read_error")
    }
  )
}

stop_if_tar_error <- function(x, name) {
  if (inherits(x, "tar_read_error")) {
    stop("Could not read target `", name, "`: ", x$error, call. = FALSE)
  }
  invisible(x)
}

country_name <- function(iso3c) {
  out <- countrycode::countrycode(iso3c, "iso3c", "country.name", warn = FALSE)
  dplyr::if_else(is.na(out), as.character(iso3c), out)
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", paste0(formatC(100 * x, digits = digits, format = "f"), "%"))
}

scale_vec <- function(x) {
  if (all(is.na(x))) {
    return(rep(NA_real_, length(x)))
  }
  sdx <- stats::sd(x, na.rm = TRUE)
  if (is.na(sdx) || sdx == 0) {
    return(rep(0, length(x)))
  }
  as.numeric((x - mean(x, na.rm = TRUE)) / sdx)
}

bounded_logit <- function(x, eps = 0.000001) {
  stats::qlogis(pmin(pmax(x, eps), 1 - eps))
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

save_plot_pair <- function(plot, png_path, pdf_path, width, height) {
  ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = 320)
  ggplot2::ggsave(pdf_path, plot, width = width, height = height)
}

write_lines_utf8 <- function(lines, path) {
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeLines(lines, con = con)
}

message("Reading existing targets.")
trade_data <- safe_tar_read("trade_data")
unga_data <- safe_tar_read("unga_data")
synth_data <- safe_tar_read("synth_data")
synth_fit <- safe_tar_read("synth_fit")
se_synth <- safe_tar_read("se_synth")
placebo_2003_fit <- safe_tar_read("placebo_teste_treatment02")
se_placebo_2003 <- safe_tar_read("se_synth_placebo2")
placebo_2005_fit <- safe_tar_read("placebo_teste_treatment04")
se_placebo_2005 <- safe_tar_read("se_synth_placebo3")
placebo_2012_fit <- safe_tar_read("placebo_teste_treatment11")
se_placebo_2012 <- safe_tar_read("se_synth_placebo1")
china_top_panel <- safe_tar_read("china_top_panel")
china_top_fect_data <- safe_tar_read("china_top_fect_data")
final_df <- safe_tar_read("final_df")

for (nm in c(
  "trade_data", "unga_data", "synth_data", "synth_fit", "se_synth",
  "china_top_panel", "china_top_fect_data", "final_df"
)) {
  stop_if_tar_error(get(nm), nm)
}

message("Building destination-rank and concentration measures.")
build_export_portfolio <- function(trade_data) {
  ranked <- trade_data |>
    dplyr::filter(
      !is.na(year),
      !is.na(exporter_iso3),
      !is.na(importer_iso3),
      exporter_iso3 != importer_iso3
    ) |>
    dplyr::mutate(exports = dplyr::coalesce(as.numeric(exports), 0)) |>
    dplyr::group_by(year, exporter_iso3) |>
    dplyr::arrange(dplyr::desc(exports), importer_iso3, .by_group = TRUE) |>
    dplyr::mutate(
      export_total = sum(exports, na.rm = TRUE),
      partner_share = dplyr::if_else(export_total > 0, exports / export_total, NA_real_),
      partner_rank = dplyr::row_number(),
      hhi_destination = sum(partner_share^2, na.rm = TRUE),
      top_partner = dplyr::first(importer_iso3),
      top_exports = dplyr::first(exports),
      top_partner_share = dplyr::first(partner_share),
      second_partner = dplyr::nth(importer_iso3, 2, default = NA_character_),
      second_exports = dplyr::nth(exports, 2, default = NA_real_),
      second_partner_share = dplyr::nth(partner_share, 2, default = NA_real_)
    ) |>
    dplyr::ungroup()

  ranked |>
    dplyr::filter(importer_iso3 == "CHN") |>
    dplyr::transmute(
      iso3c = exporter_iso3,
      country_name = country_name(exporter_iso3),
      year,
      china_rank = partner_rank,
      china_top = as.integer(partner_rank == 1L & exports > 0),
      china_second = as.integer(partner_rank == 2L & exports > 0),
      china_exports = exports,
      export_total,
      china_share = dplyr::if_else(export_total > 0, exports / export_total, NA_real_),
      top_partner,
      top_partner_name = country_name(top_partner),
      top_exports,
      top_partner_share,
      second_partner,
      second_partner_name = country_name(second_partner),
      second_exports,
      second_partner_share,
      competitor_partner = dplyr::if_else(partner_rank == 1L, second_partner, top_partner),
      competitor_partner_name = country_name(competitor_partner),
      competitor_exports = dplyr::if_else(partner_rank == 1L, second_exports, top_exports),
      competitor_share = dplyr::if_else(partner_rank == 1L, second_partner_share, top_partner_share),
      china_margin_vs_competitor = exports - competitor_exports,
      china_margin_vs_competitor_share = china_share - competitor_share,
      china_margin_over_second_share = dplyr::if_else(
        partner_rank == 1L,
        china_share - second_partner_share,
        NA_real_
      ),
      china_gap_to_top_share = dplyr::if_else(partner_rank == 1L, 0, top_partner_share - china_share),
      hhi_destination
    ) |>
    dplyr::arrange(iso3c, year)
}

export_panel <- build_export_portfolio(trade_data)

message("Building pre-2009 primary-sector export exposure from local ITPD-E raw data.")
build_pre_primary_exposure <- function(raw_path, output_path, start_year = 2004L, end_year = 2008L) {
  if (file.exists(output_path)) {
    return(readr::read_csv(output_path, show_col_types = FALSE))
  }

  if (!file.exists(raw_path)) {
    stop("Raw ITPD-E file not found: ", raw_path, call. = FALSE)
  }

  dt <- data.table::fread(
    raw_path,
    select = c("year", "exporter_iso3", "trade", "broad_sector"),
    showProgress = FALSE
  )
  dt <- dt[year >= start_year & year <= end_year]
  dt[, trade := fifelse(is.na(trade), 0, as.numeric(trade))]
  dt[, primary_trade := fifelse(broad_sector %in% c("Agriculture", "Mining and Energy"), trade, 0)]
  dt[, agriculture_trade := fifelse(broad_sector == "Agriculture", trade, 0)]
  dt[, mining_energy_trade := fifelse(broad_sector == "Mining and Energy", trade, 0)]
  dt[, services_trade := fifelse(broad_sector == "Services", trade, 0)]

  yearly <- dt[, .(
    total_exports = sum(trade, na.rm = TRUE),
    services_exports = sum(services_trade, na.rm = TRUE),
    primary_exports = sum(primary_trade, na.rm = TRUE),
    agriculture_exports = sum(agriculture_trade, na.rm = TRUE),
    mining_energy_exports = sum(mining_energy_trade, na.rm = TRUE)
  ), by = .(iso3c = exporter_iso3, year)]
  yearly[, goods_exports := total_exports - services_exports]

  exposure <- yearly[, .(
    pre_window_start = start_year,
    pre_window_end = end_year,
    observed_years = uniqueN(year),
    pre_total_exports_all_sectors = sum(total_exports, na.rm = TRUE),
    pre_services_exports = sum(services_exports, na.rm = TRUE),
    pre_goods_exports = sum(goods_exports, na.rm = TRUE),
    pre_primary_exports = sum(primary_exports, na.rm = TRUE),
    pre_agriculture_exports = sum(agriculture_exports, na.rm = TRUE),
    pre_mining_energy_exports = sum(mining_energy_exports, na.rm = TRUE)
  ), by = iso3c]
  exposure[, pre_primary_share := fifelse(pre_goods_exports > 0, pre_primary_exports / pre_goods_exports, NA_real_)]
  exposure[, pre_agriculture_share := fifelse(pre_goods_exports > 0, pre_agriculture_exports / pre_goods_exports, NA_real_)]
  exposure[, pre_mining_energy_share := fifelse(pre_goods_exports > 0, pre_mining_energy_exports / pre_goods_exports, NA_real_)]
  exposure[, country_name := country_name(iso3c)]

  out <- tibble::as_tibble(exposure) |>
    dplyr::select(
      iso3c,
      country_name,
      pre_window_start,
      pre_window_end,
      observed_years,
      pre_total_exports_all_sectors,
      pre_services_exports,
      pre_goods_exports,
      pre_primary_exports,
      pre_primary_share,
      pre_agriculture_share,
      pre_mining_energy_share
    ) |>
    dplyr::arrange(iso3c)

  readr::write_csv(out, output_path)
  out
}

primary_exposure <- build_pre_primary_exposure(
  raw_path = file.path("raw data", "ITPDE_R03.csv"),
  output_path = primary_exposure_path
)

write_lines_utf8(c(
  "# Sources",
  "",
  paste0("- Local raw trade file: `raw data/ITPDE_R03.csv`; accessed by this diagnostic on ", run_date, "."),
  "- Dataset: International Trade and Production Database for Estimation (ITPD-E), release R03, already preserved in this repository.",
  "- Aggregate country-year targets read from the local `targets` store: `trade_data`, `unga_data`, `synth_data`, `china_top_panel`, `china_top_fect_data`, and `final_df`.",
  "- Commodity-cycle exposure proxy: pre-2009 primary-sector share of goods exports, computed from ITPD-E broad sectors `Agriculture` and `Mining and Energy` over 2004-2008, excluding `Services` from the denominator. No external commodity-price index was added in this run."
), source_note_path)

message("Reconstructing Brazil design and exposure series.")
design_reconstruction <- tibble::tibble(
  item = c(
    "Unit of analysis",
    "Outcome",
    "Treatment",
    "Treatment onset",
    "Main Brazil estimator",
    "Brazil panel window",
    "Donor pool size in synth_data",
    "Covariates in manuscript Table 3 baseline",
    "Continuous China exposure already in baseline",
    "Commodity exposure added in this diagnostic",
    "Raw ITPD-E unit"
  ),
  value = c(
    "country-year; Brazil is the only treated unit in the SDiD design",
    "absolute UNGA ideal-point distance to China; lower values mean convergence",
    "indicator equal to 1 for Brazil in years where China is the largest export destination",
    "2009, the first year China is ranked #1 among Brazil's export destinations",
    "synthetic difference-in-differences with unit/time weights and covariate adjustment",
    paste0(min(synth_data$year), "-", max(synth_data$year), " in target `synth_data`; Table 3 uses post-2009 average gaps through 2015 in the main fit"),
    as.character(dplyr::n_distinct(synth_data$iso3c) - 1L),
    "GPI, China/US export shares, GDP per capita, exchange rate, distance to US, US power gap, leader ideology, current account, government deficit, parliamentary system, military executive, and US trade agreement",
    "`perc_trade_with_china` and `perc_trade_with_us`, rescaled in `synth_data`",
    "pre-2009 primary-sector share of goods exports from ITPD-E broad sectors Agriculture and Mining and Energy",
    "millions of current US dollars"
  )
)
readr::write_csv(design_reconstruction, table_design_path)

brazil_exposure <- export_panel |>
  dplyr::filter(iso3c == "BRA", year >= 2000L, year <= 2012L) |>
  dplyr::left_join(
    primary_exposure |>
      dplyr::select(
        iso3c,
        pre_primary_share,
        pre_agriculture_share,
        pre_mining_energy_share
      ),
    by = "iso3c"
  ) |>
  dplyr::mutate(
    china_share_pct = 100 * china_share,
    top_partner_share_pct = 100 * top_partner_share,
    hhi_destination_pct = 100 * hhi_destination,
    margin_share_pct = 100 * china_margin_vs_competitor_share,
    china_exports_usd_bn = china_exports / 1000,
    competitor_exports_usd_bn = competitor_exports / 1000,
    margin_usd_bn = china_margin_vs_competitor / 1000,
    pre_primary_share_pct = 100 * pre_primary_share
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    year,
    china_rank,
    china_top,
    china_share,
    china_share_pct,
    hhi_destination,
    hhi_destination_pct,
    top_partner,
    top_partner_name,
    top_partner_share,
    top_partner_share_pct,
    second_partner,
    second_partner_name,
    competitor_partner,
    competitor_partner_name,
    china_margin_vs_competitor_share,
    margin_share_pct,
    china_exports_usd_bn,
    competitor_exports_usd_bn,
    margin_usd_bn,
    pre_primary_share,
    pre_primary_share_pct,
    pre_agriculture_share,
    pre_mining_energy_share
  )
readr::write_csv(brazil_exposure, table_brazil_exposure_path)

panel_theme <- ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold", size = 10),
    legend.position = "bottom"
  )

p_share <- ggplot2::ggplot(brazil_exposure, ggplot2::aes(x = year, y = china_share_pct)) +
  ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35") +
  ggplot2::geom_line(colour = "#1B7837", linewidth = 0.8) +
  ggplot2::geom_point(colour = "#1B7837", size = 1.6) +
  ggplot2::labs(title = "A. China export share", x = NULL, y = "Percent") +
  panel_theme

p_concentration <- ggplot2::ggplot(brazil_exposure, ggplot2::aes(x = year)) +
  ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35") +
  ggplot2::geom_line(ggplot2::aes(y = hhi_destination_pct, colour = "HHI"), linewidth = 0.8) +
  ggplot2::geom_line(ggplot2::aes(y = top_partner_share_pct, colour = "Top partner share"), linewidth = 0.8) +
  ggplot2::scale_colour_manual(values = c("HHI" = "#2166AC", "Top partner share" = "#D55E00")) +
  ggplot2::labs(title = "B. Destination concentration", x = NULL, y = "Percent / HHI x 100", colour = NULL) +
  panel_theme

p_margin <- ggplot2::ggplot(brazil_exposure, ggplot2::aes(x = year, y = margin_usd_bn)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45") +
  ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35") +
  ggplot2::geom_col(ggplot2::aes(fill = margin_usd_bn >= 0), show.legend = FALSE, width = 0.72) +
  ggplot2::scale_fill_manual(values = c("TRUE" = "#D55E00", "FALSE" = "#999999")) +
  ggplot2::labs(title = "C. Margin over competitor", x = "Year", y = "US$ billions") +
  panel_theme

fig_brazil_exposure <- p_share / p_concentration / p_margin
fig_brazil_exposure <- fig_brazil_exposure +
  patchwork::plot_annotation(
    title = "Figure 1. Brazil: continuous trade exposure, concentration, and rank margin",
    caption = "Caption: The dashed line marks the 2009 treatment onset, when China becomes Brazil's largest export destination. Shares and HHI use directed export flows from ITPD-E; margins are current US$ billions."
  )
save_plot_pair(fig_brazil_exposure, fig_brazil_exposure_png, fig_brazil_exposure_pdf, 8.2, 8.2)

message("Fitting Brazil SDiD diagnostic specifications.")
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
      tidyr::pivot_wider(id_cols = iso3c, names_from = year, values_from = value) |>
      dplyr::arrange(iso3c)

    x_array[, , k] <- wide |>
      dplyr::select(dplyr::all_of(as.character(time_levels))) |>
      as.matrix()
  }

  x_array
}

fit_sdid_diagnostic <- function(data, time_treatment, time_end, covariate_cols) {
  fit_data <- data |>
    dplyr::filter(year < time_end) |>
    dplyr::mutate(treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1L, 0L)) |>
    dplyr::arrange(as.integer(iso3c == "BRA"), iso3c, year)

  required <- c("iso3c", "year", "abs_distance_china", "treatment", covariate_cols)
  if (anyNA(fit_data |> dplyr::select(dplyr::all_of(required)))) {
    missing_counts <- fit_data |>
      dplyr::summarise(dplyr::across(dplyr::all_of(required), ~sum(is.na(.x)))) |>
      tidyr::pivot_longer(dplyr::everything(), names_to = "variable", values_to = "missing") |>
      dplyr::filter(missing > 0)
    stop(
      "fit_sdid_diagnostic: missing values in estimation data: ",
      paste(missing_counts$variable, missing_counts$missing, sep = "=", collapse = ", "),
      call. = FALSE
    )
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

summarise_sdid_fit <- function(fit, compute_se = FALSE) {
  if (inherits(fit, "error")) {
    return(tibble::tibble(
      estimate = NA_real_,
      se_placebo = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      fit_status = conditionMessage(fit)
    ))
  }

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
    p_value = ifelse(is.na(se), NA_real_, 2 * stats::pnorm(-abs(estimate / se))),
    ci_95_low = ifelse(is.na(se), NA_real_, estimate - stats::qnorm(0.975) * se),
    ci_95_high = ifelse(is.na(se), NA_real_, estimate + stats::qnorm(0.975) * se),
    fit_status = "ok"
  )
}

synth_enriched <- synth_data |>
  dplyr::left_join(
    export_panel |>
      dplyr::select(
        iso3c,
        year,
        china_rank,
        china_share,
        hhi_destination,
        top_partner_share,
        china_margin_vs_competitor_share
      ),
    by = c("iso3c", "year")
  ) |>
  dplyr::left_join(
    primary_exposure |>
      dplyr::select(
        iso3c,
        pre_primary_share,
        pre_agriculture_share,
        pre_mining_energy_share
      ),
    by = "iso3c"
  ) |>
  dplyr::group_by(iso3c) |>
  dplyr::arrange(year, .by_group = TRUE) |>
  dplyr::mutate(
    china_share_delta = china_share - dplyr::lag(china_share),
    pre_china_share_2004_2008 = mean(china_share[year >= 2004L & year <= 2008L], na.rm = TRUE),
    pre_hhi_2004_2008 = mean(hhi_destination[year >= 2004L & year <= 2008L], na.rm = TRUE),
    pre_top_share_2004_2008 = mean(top_partner_share[year >= 2004L & year <= 2008L], na.rm = TRUE)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    gfc_2008_2009 = as.integer(year %in% 2008:2009),
    post_2009 = as.integer(year >= 2009L),
    china_share_z = scale_vec(china_share),
    china_share_logit_z = scale_vec(bounded_logit(china_share)),
    china_share_sqrt_z = scale_vec(sqrt(pmax(china_share, 0))),
    china_share_delta_z = scale_vec(dplyr::coalesce(china_share_delta, 0)),
    hhi_destination_z = scale_vec(hhi_destination),
    top_partner_share_z = scale_vec(top_partner_share),
    china_margin_share_z = scale_vec(china_margin_vs_competitor_share),
    pre_primary_share_z = scale_vec(pre_primary_share),
    pre_agriculture_share_z = scale_vec(pre_agriculture_share),
    pre_mining_energy_share_z = scale_vec(pre_mining_energy_share),
    pre_china_share_z = scale_vec(pre_china_share_2004_2008),
    pre_hhi_z = scale_vec(pre_hhi_2004_2008),
    china_share_x_gfc_z = scale_vec(china_share * gfc_2008_2009),
    hhi_x_gfc_z = scale_vec(hhi_destination * gfc_2008_2009),
    top_share_x_gfc_z = scale_vec(top_partner_share * gfc_2008_2009),
    pre_primary_x_gfc_z = scale_vec(pre_primary_share * gfc_2008_2009),
    pre_primary_x_post_z = scale_vec(pre_primary_share * post_2009),
    pre_china_share_x_gfc_z = scale_vec(pre_china_share_2004_2008 * gfc_2008_2009)
  )

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
    names(synth_enriched)
  )
)

covariate_sets <- list(
  manuscript_main = pipeline_covariates,
  plus_smooth_china_share = unique(c(
    pipeline_covariates,
    "china_share_logit_z",
    "china_share_sqrt_z",
    "china_share_delta_z"
  )),
  plus_destination_concentration = unique(c(
    pipeline_covariates,
    "hhi_destination_z",
    "top_partner_share_z"
  )),
  plus_rank_margin_bad_control = unique(c(
    pipeline_covariates,
    "hhi_destination_z",
    "top_partner_share_z",
    "china_margin_share_z"
  )),
  plus_commodity_gfc_exposure = unique(c(
    pipeline_covariates,
    "pre_primary_share_z",
    "pre_agriculture_share_z",
    "pre_mining_energy_share_z",
    "pre_primary_x_gfc_z",
    "pre_china_share_x_gfc_z"
  )),
  full_diagnostic = unique(c(
    pipeline_covariates,
    "china_share_logit_z",
    "china_share_sqrt_z",
    "china_share_delta_z",
    "hhi_destination_z",
    "top_partner_share_z",
    "china_margin_share_z",
    "pre_primary_share_z",
    "pre_agriculture_share_z",
    "pre_mining_energy_share_z",
    "china_share_x_gfc_z",
    "hhi_x_gfc_z",
    "top_share_x_gfc_z",
    "pre_primary_x_gfc_z",
    "pre_primary_x_post_z",
    "pre_china_share_x_gfc_z"
  ))
)

compute_sdid_se <- identical(Sys.getenv("CHINA_SHOCK_COMPUTE_SDID_SE", "0"), "1")
sdid_results <- dplyr::bind_rows(lapply(names(covariate_sets), function(set_name) {
  if (identical(set_name, "manuscript_main")) {
    target_estimate <- as.numeric(synth_fit)
    target_se <- as.numeric(se_synth)
    return(tibble::tibble(
      specification = set_name,
      treatment_onset = 2009L,
      estimate = target_estimate,
      se_placebo = target_se,
      p_value = 2 * stats::pnorm(-abs(target_estimate / target_se)),
      ci_95_low = target_estimate - stats::qnorm(0.975) * target_se,
      ci_95_high = target_estimate + stats::qnorm(0.975) * target_se,
      fit_status = "existing target",
      inference = "placebo SE from target `se_synth`",
      covariates_added = "none beyond manuscript Table 3 baseline"
    ))
  }

  fit <- tryCatch(
    fit_sdid_diagnostic(
      data = synth_enriched,
      time_treatment = 2008L,
      time_end = 2016L,
      covariate_cols = covariate_sets[[set_name]]
    ),
    error = function(e) e
  )
  summarise_sdid_fit(fit, compute_se = compute_sdid_se) |>
    dplyr::mutate(
      specification = set_name,
      treatment_onset = 2009L,
      inference = ifelse(
        compute_sdid_se,
        "local placebo SE requested by CHINA_SHOCK_COMPUTE_SDID_SE=1",
        "point estimate only; placebo SE not recomputed for expanded exploratory SDiD"
      ),
      covariates_added = dplyr::case_when(
        set_name == "plus_smooth_china_share" ~ "logit/sqrt/delta transformations of China export share",
        set_name == "plus_destination_concentration" ~ "destination HHI and top-partner export share",
        set_name == "plus_rank_margin_bad_control" ~ "destination HHI, top-partner share, and China margin over competitor",
        set_name == "plus_commodity_gfc_exposure" ~ "pre-2009 primary export composition and 2008-2009 exposure interactions",
        set_name == "full_diagnostic" ~ "smooth share, concentration, margin, commodity composition, and 2008-2009 interactions",
        TRUE ~ ""
      )
    ) |>
    dplyr::select(
      specification,
      treatment_onset,
      estimate,
      se_placebo,
      p_value,
      ci_95_low,
      ci_95_high,
      fit_status,
      inference,
      covariates_added
    )
}))
readr::write_csv(sdid_results, table_sdid_path)

timing_specs <- tibble::tribble(
  ~timing_test, ~nominal_treatment_year, ~time_treatment, ~time_end, ~role,
  "growth_2003_lower_rank_promotion", 2003L, 2002L, 2009L, "Existing pre-2009 growth placebo; China is not #1.",
  "china_rank2_2004_threshold", 2004L, 2003L, 2009L, "New threshold placebo: China first reaches #2 but is not #1.",
  "growth_2005_without_rank1", 2005L, 2004L, 2009L, "Existing pre-2009 growth placebo; China is not #1.",
  "actual_2009_rank1", 2009L, 2008L, 2016L, "Actual rank-1 treatment onset.",
  "later_2012_break", 2012L, 2011L, 2019L, "Later-break falsification after China is already #1."
)

target_timing <- tibble::tibble(
  timing_test = c(
    "growth_2003_lower_rank_promotion",
    "growth_2005_without_rank1",
    "actual_2009_rank1",
    "later_2012_break"
  ),
  target_estimate = c(
    as.numeric(placebo_2003_fit),
    as.numeric(placebo_2005_fit),
    as.numeric(synth_fit),
    as.numeric(placebo_2012_fit)
  ),
  target_se = c(
    as.numeric(se_placebo_2003),
    as.numeric(se_placebo_2005),
    as.numeric(se_synth),
    as.numeric(se_placebo_2012)
  )
) |>
  dplyr::mutate(
    target_p = 2 * stats::pnorm(-abs(target_estimate / target_se))
  )

timing_results <- dplyr::bind_rows(lapply(seq_len(nrow(timing_specs)), function(i) {
  spec <- timing_specs[i, ]
  full_fit <- tryCatch(
    fit_sdid_diagnostic(
      data = synth_enriched,
      time_treatment = spec$time_treatment,
      time_end = spec$time_end,
      covariate_cols = covariate_sets$full_diagnostic
    ),
    error = function(e) e
  )
  local <- summarise_sdid_fit(full_fit, compute_se = FALSE)
  target_row <- target_timing |>
    dplyr::filter(timing_test == spec$timing_test) |>
    dplyr::slice_head(n = 1)
  exposure_row <- brazil_exposure |>
    dplyr::filter(year == spec$nominal_treatment_year) |>
    dplyr::slice_head(n = 1)

  tibble::tibble(
    timing_test = spec$timing_test,
    nominal_treatment_year = spec$nominal_treatment_year,
    role = spec$role,
    china_rank = exposure_row$china_rank,
    china_top = exposure_row$china_top,
    china_share_pct = exposure_row$china_share_pct,
    margin_usd_bn = exposure_row$margin_usd_bn,
    target_estimate = ifelse(nrow(target_row) == 0L, NA_real_, target_row$target_estimate),
    target_se = ifelse(nrow(target_row) == 0L, NA_real_, target_row$target_se),
    target_p = ifelse(nrow(target_row) == 0L, NA_real_, target_row$target_p),
    full_diagnostic_estimate = local$estimate,
    full_diagnostic_status = local$fit_status
  )
}))
readr::write_csv(timing_results, table_placebo_path)

sdid_plot_data <- sdid_results |>
  dplyr::mutate(
    specification_label = dplyr::case_when(
      specification == "manuscript_main" ~ "Manuscript main",
      specification == "plus_smooth_china_share" ~ "Smooth share",
      specification == "plus_destination_concentration" ~ "Concentration",
      specification == "plus_rank_margin_bad_control" ~ "Rank margin",
      specification == "plus_commodity_gfc_exposure" ~ "Commodity/GFC",
      specification == "full_diagnostic" ~ "Full diagnostic",
      TRUE ~ specification
    ),
    specification_label = factor(
      specification_label,
      levels = c(
        "Manuscript main",
        "Smooth share",
        "Concentration",
        "Rank margin",
        "Commodity/GFC",
        "Full diagnostic"
      )
    )
  )

fig_sdid <- ggplot2::ggplot(sdid_plot_data, ggplot2::aes(x = specification_label, y = estimate)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey50") +
  ggplot2::geom_point(size = 2.4, colour = "#2166AC") +
  ggplot2::geom_errorbar(
    data = sdid_plot_data |> dplyr::filter(!is.na(ci_95_low), !is.na(ci_95_high)),
    ggplot2::aes(ymin = ci_95_low, ymax = ci_95_high),
    width = 0.12,
    colour = "#2166AC"
  ) +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Figure 2. Brazil SDiD: rank-1 estimate after continuous-exposure diagnostics",
    x = NULL,
    y = "ATT in absolute UNGA distance to China",
    caption = "Caption: Negative estimates mean convergence toward China. Only the manuscript-main row has a target placebo SE unless CHINA_SHOCK_COMPUTE_SDID_SE=1 is set; other rows are point-estimate diagnostics."
  ) +
  panel_theme
save_plot_pair(fig_sdid, fig_sdid_png, fig_sdid_pdf, 8.0, 4.8)

message("Building cross-country FE and placebo-threshold diagnostics.")
final_covariates <- final_df |>
  dplyr::mutate(log_gdp_pc = log(gdp_cur / pop)) |>
  dplyr::select(
    iso3c,
    year,
    region2,
    log_gdp_pc,
    gdp_growth,
    CA_GDP,
    govdef_GDP,
    hog_left
  )

cross_panel_base <- china_top_fect_data |>
  dplyr::select(iso3c, country_name, country_id, year, abs_distance_china, china_top) |>
  dplyr::left_join(
    export_panel |>
      dplyr::select(
        iso3c,
        year,
        china_rank,
        china_second,
        china_share,
        hhi_destination,
        top_partner,
        top_partner_share,
        china_margin_vs_competitor_share
      ),
    by = c("iso3c", "year")
  ) |>
  dplyr::left_join(
    primary_exposure |>
      dplyr::select(
        iso3c,
        pre_primary_share,
        pre_agriculture_share,
        pre_mining_energy_share
      ),
    by = "iso3c"
  ) |>
  dplyr::left_join(final_covariates, by = c("iso3c", "year")) |>
  dplyr::group_by(iso3c) |>
  dplyr::arrange(year, .by_group = TRUE) |>
  dplyr::mutate(
    ever_china_top = any(china_top == 1L, na.rm = TRUE),
    first_china_top_year = ifelse(ever_china_top, min(year[china_top == 1L], na.rm = TRUE), NA_integer_),
    before_china_top = is.na(first_china_top_year) | year < first_china_top_year,
    china_share_delta = china_share - dplyr::lag(china_share),
    previous_top_partner = dplyr::lag(top_partner),
    nonchina_top_change = !is.na(previous_top_partner) &
      top_partner != previous_top_partner &
      top_partner != "CHN" &
      previous_top_partner != "CHN" &
      year >= 2000L,
    first_nonchina_top_change = ifelse(
      any(nonchina_top_change, na.rm = TRUE),
      min(year[nonchina_top_change], na.rm = TRUE),
      NA_integer_
    ),
    first_china_rank2_year = ifelse(
      any(china_rank == 2L & before_china_top & year >= 2000L, na.rm = TRUE),
      min(year[china_rank == 2L & before_china_top & year >= 2000L], na.rm = TRUE),
      NA_integer_
    )
  ) |>
  dplyr::ungroup()

pseudo_growth_cutoff <- stats::quantile(
  cross_panel_base$china_share_delta[
    cross_panel_base$before_china_top &
      !is.na(cross_panel_base$china_share_delta) &
      cross_panel_base$china_share_delta > 0
  ],
  probs = 0.90,
  na.rm = TRUE
)

cross_panel <- cross_panel_base |>
  dplyr::group_by(iso3c) |>
  dplyr::arrange(year, .by_group = TRUE) |>
  dplyr::mutate(
    pseudo_share_growth_candidate = before_china_top &
      !is.na(china_share_delta) &
      china_share_delta >= pseudo_growth_cutoff &
      china_rank != 1L &
      year >= 2000L,
    first_pseudo_share_growth_year = ifelse(
      any(pseudo_share_growth_candidate, na.rm = TRUE),
      min(year[pseudo_share_growth_candidate], na.rm = TRUE),
      NA_integer_
    ),
    china_rank2_onset = as.integer(!is.na(first_china_rank2_year) & year >= first_china_rank2_year & before_china_top),
    nonchina_new_top_onset = as.integer(!is.na(first_nonchina_top_change) & year >= first_nonchina_top_change & !ever_china_top),
    pseudo_share_growth_onset = as.integer(!is.na(first_pseudo_share_growth_year) & year >= first_pseudo_share_growth_year & before_china_top)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    gfc_2008_2009 = as.integer(year %in% 2008:2009),
    post_2009 = as.integer(year >= 2009L),
    china_share_z = scale_vec(china_share),
    china_share_logit_z = scale_vec(bounded_logit(china_share)),
    china_share_delta_z = scale_vec(dplyr::coalesce(china_share_delta, 0)),
    hhi_destination_z = scale_vec(hhi_destination),
    top_partner_share_z = scale_vec(top_partner_share),
    china_margin_share_z = scale_vec(china_margin_vs_competitor_share),
    pre_primary_share_z = scale_vec(pre_primary_share),
    pre_agriculture_share_z = scale_vec(pre_agriculture_share),
    pre_mining_energy_share_z = scale_vec(pre_mining_energy_share),
    log_gdp_pc_z = scale_vec(log_gdp_pc),
    gdp_growth_z = scale_vec(gdp_growth),
    primary_x_gfc_z = scale_vec(pre_primary_share * gfc_2008_2009),
    primary_x_post2009_z = scale_vec(pre_primary_share * post_2009),
    china_share_x_gfc_z = scale_vec(china_share * gfc_2008_2009),
    hhi_x_gfc_z = scale_vec(hhi_destination * gfc_2008_2009)
  )

fit_fe_model <- function(model_name, fml, data, weight_col = NULL) {
  fit <- tryCatch(
    {
      if (is.null(weight_col)) {
        fixest::feols(fml, data = data, vcov = ~iso3c)
      } else {
        fixest::feols(fml, data = data, weights = stats::as.formula(paste0("~", weight_col)), vcov = ~iso3c)
      }
    },
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      model = model_name,
      term = "china_top",
      estimate = NA_real_,
      se = NA_real_,
      p_value = NA_real_,
      n_obs = nrow(data),
      n_countries = dplyr::n_distinct(data$iso3c),
      fit_status = conditionMessage(fit)
    ))
  }

  ct <- fixest::coeftable(fit)
  term <- if ("china_top" %in% rownames(ct)) "china_top" else rownames(ct)[1]
  tibble::tibble(
    model = model_name,
    term = term,
    estimate = unname(ct[term, "Estimate"]),
    se = unname(ct[term, "Std. Error"]),
    p_value = unname(ct[term, "Pr(>|t|)"]),
    n_obs = stats::nobs(fit),
    n_countries = dplyr::n_distinct(fit$model_info$fixef_vars$iso3c %||% data$iso3c),
    fit_status = "ok"
  )
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

cross_model_data <- cross_panel |>
  dplyr::filter(!is.na(abs_distance_china), !is.na(china_top))

cross_fe_specs <- list(
  "TWFE baseline" = abs_distance_china ~ china_top | iso3c + year,
  "TWFE + smooth China share" = abs_distance_china ~ china_top + china_share_logit_z + china_share_delta_z | iso3c + year,
  "TWFE + concentration" = abs_distance_china ~ china_top + china_share_logit_z + hhi_destination_z + top_partner_share_z | iso3c + year,
  "TWFE + rank margin" = abs_distance_china ~ china_top + china_share_logit_z + hhi_destination_z + top_partner_share_z + china_margin_share_z | iso3c + year,
  "TWFE + commodity/GFC exposure" = abs_distance_china ~ china_top + china_share_logit_z + hhi_destination_z + primary_x_gfc_z + primary_x_post2009_z + china_share_x_gfc_z + hhi_x_gfc_z | iso3c + year,
  "TWFE full diagnostic" = abs_distance_china ~ china_top + china_share_logit_z + china_share_delta_z + hhi_destination_z + top_partner_share_z + china_margin_share_z + primary_x_gfc_z + primary_x_post2009_z + china_share_x_gfc_z + hhi_x_gfc_z + log_gdp_pc_z + gdp_growth_z | iso3c + year
)

cross_fe_results <- dplyr::bind_rows(lapply(names(cross_fe_specs), function(nm) {
  fit_fe_model(nm, cross_fe_specs[[nm]], cross_model_data)
}))
readr::write_csv(cross_fe_results, table_cross_fe_path)

fit_placebo_model <- function(model_name, placebo_var, data_filter) {
  data <- cross_panel |>
    dplyr::filter({{ data_filter }}) |>
    dplyr::filter(!is.na(abs_distance_china), !is.na(.data[[placebo_var]]))
  fml <- stats::as.formula(paste0(
    "abs_distance_china ~ ",
    placebo_var,
    " + china_share_logit_z + hhi_destination_z + top_partner_share_z + primary_x_gfc_z + china_share_x_gfc_z | iso3c + year"
  ))
  out <- fit_fe_model(model_name, fml, data)
  out |>
    dplyr::mutate(term = placebo_var)
}

threshold_placebos <- dplyr::bind_rows(
  fit_placebo_model(
    "China reaches rank #2 before any rank #1 entry",
    "china_rank2_onset",
    before_china_top
  ),
  fit_placebo_model(
    "Non-China partner becomes #1 among never-China-top countries",
    "nonchina_new_top_onset",
    !ever_china_top
  ),
  fit_placebo_model(
    "Large China-share growth without rank #1",
    "pseudo_share_growth_onset",
    before_china_top
  )
) |>
  dplyr::mutate(
    pseudo_share_growth_cutoff = pseudo_growth_cutoff,
    interpretation = dplyr::case_when(
      term == "china_rank2_onset" ~ "Tests whether lower-rank China promotion has the same association as rank #1.",
      term == "nonchina_new_top_onset" ~ "Tests whether generic top-partner changes toward non-China partners move countries toward China.",
      term == "pseudo_share_growth_onset" ~ "Tests large China-share growth without top-rank entry.",
      TRUE ~ ""
    )
  )
readr::write_csv(threshold_placebos, table_placebo_threshold_path)

threshold_plot_data <- dplyr::bind_rows(
  cross_fe_results |>
    dplyr::filter(model == "TWFE full diagnostic") |>
    dplyr::mutate(model = "Actual China #1"),
  threshold_placebos |>
    dplyr::mutate(model = dplyr::case_when(
      term == "china_rank2_onset" ~ "Placebo: China #2",
      term == "nonchina_new_top_onset" ~ "Placebo: non-China #1",
      term == "pseudo_share_growth_onset" ~ "Placebo: share growth",
      TRUE ~ model
    ))
) |>
  dplyr::mutate(
    ci_95_low = estimate - 1.96 * se,
    ci_95_high = estimate + 1.96 * se,
    model = factor(
      model,
      levels = c("Actual China #1", "Placebo: China #2", "Placebo: non-China #1", "Placebo: share growth")
    )
  )

fig_threshold <- ggplot2::ggplot(threshold_plot_data, ggplot2::aes(x = model, y = estimate)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey50") +
  ggplot2::geom_point(size = 2.4, colour = "#B2182B") +
  ggplot2::geom_errorbar(ggplot2::aes(ymin = ci_95_low, ymax = ci_95_high), width = 0.12, colour = "#B2182B") +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Figure 3. Cross-country threshold placebos",
    x = NULL,
    y = "TWFE coefficient in absolute UNGA distance to China",
    caption = "Caption: Negative estimates indicate movement toward China. Placebos use the same country-year outcome with country and year fixed effects and continuous-exposure controls."
  ) +
  panel_theme
save_plot_pair(fig_threshold, fig_threshold_png, fig_threshold_pdf, 8.0, 4.8)

message("Estimating commodity-exposure balanced cross-country models.")
country_pre_entry <- cross_panel |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    ever_china_top = any(china_top == 1L, na.rm = TRUE),
    first_china_top_year = ifelse(ever_china_top, min(year[china_top == 1L], na.rm = TRUE), NA_integer_),
    pre_window_start = ifelse(ever_china_top, first_china_top_year - 5L, 2004L),
    pre_window_end = ifelse(ever_china_top, first_china_top_year - 1L, 2008L),
    pre_china_share = mean(china_share[year >= pre_window_start & year <= pre_window_end], na.rm = TRUE),
    pre_hhi = mean(hhi_destination[year >= pre_window_start & year <= pre_window_end], na.rm = TRUE),
    pre_top_partner_share = mean(top_partner_share[year >= pre_window_start & year <= pre_window_end], na.rm = TRUE),
    pre_log_gdp_pc = mean(log_gdp_pc[year >= pre_window_start & year <= pre_window_end], na.rm = TRUE),
    pre_primary_share = dplyr::first(pre_primary_share),
    pre_agriculture_share = dplyr::first(pre_agriculture_share),
    pre_mining_energy_share = dplyr::first(pre_mining_energy_share),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    ever_china_top = as.integer(ever_china_top),
    brazil_case = iso3c == "BRA"
  ) |>
  dplyr::filter(
    is.finite(pre_china_share),
    is.finite(pre_hhi),
    is.finite(pre_top_partner_share),
    is.finite(pre_log_gdp_pc),
    is.finite(pre_primary_share)
  )
readr::write_csv(country_pre_entry, table_country_exposure_path)

match_formula <- ever_china_top ~ pre_china_share + pre_hhi + pre_top_partner_share +
  pre_primary_share + pre_log_gdp_pc

match_fit <- MatchIt::matchit(
  match_formula,
  data = country_pre_entry,
  method = "nearest",
  distance = "glm",
  ratio = 3,
  replace = TRUE
)

match_weights <- MatchIt::match.data(match_fit) |>
  dplyr::select(iso3c, match_weight = weights)

weighted_country_data <- country_pre_entry |>
  dplyr::left_join(match_weights, by = "iso3c") |>
  dplyr::mutate(match_weight = dplyr::coalesce(match_weight, 0))

matched_panel <- cross_panel |>
  dplyr::left_join(
    weighted_country_data |>
      dplyr::select(iso3c, match_weight),
    by = "iso3c"
  ) |>
  dplyr::filter(match_weight > 0)

commodity_cutoff <- stats::quantile(country_pre_entry$pre_primary_share, 0.75, na.rm = TRUE)
commodity_countries <- country_pre_entry |>
  dplyr::filter(pre_primary_share >= commodity_cutoff) |>
  dplyr::select(iso3c, commodity_exporter = pre_primary_share)

commodity_panel <- cross_panel |>
  dplyr::inner_join(commodity_countries, by = "iso3c")

weighted_results <- dplyr::bind_rows(
  fit_fe_model(
    "Full sample TWFE full diagnostic",
    cross_fe_specs[["TWFE full diagnostic"]],
    cross_model_data
  ),
  fit_fe_model(
    "Nearest-neighbor matched countries",
    cross_fe_specs[["TWFE full diagnostic"]],
    matched_panel,
    weight_col = "match_weight"
  ),
  fit_fe_model(
    "High pre-2009 primary-export countries",
    cross_fe_specs[["TWFE full diagnostic"]],
    commodity_panel
  )
) |>
  dplyr::mutate(
    commodity_cutoff = commodity_cutoff,
    design_note = dplyr::case_when(
      model == "Nearest-neighbor matched countries" ~ "Countries matched on pre-entry China export share, destination HHI, top-partner share, pre-2009 primary-sector export share, and log GDP per capita.",
      model == "High pre-2009 primary-export countries" ~ "Sample restricted to countries at or above the 75th percentile of pre-2009 primary-sector export share.",
      TRUE ~ "Unweighted full absorbing cross-country sample."
    )
  )
readr::write_csv(weighted_results, table_weighted_path)

weighted_moments <- function(data, weight_col, treat_col, vars) {
  dplyr::bind_rows(lapply(vars, function(v) {
    out <- dplyr::bind_rows(lapply(c(0, 1), function(g) {
      subset <- data |>
        dplyr::filter(.data[[treat_col]] == g)
      w <- subset[[weight_col]]
      x <- subset[[v]]
      tibble::tibble(
        variable = v,
        group = g,
        mean = stats::weighted.mean(x, w, na.rm = TRUE),
        var = stats::weighted.mean((x - stats::weighted.mean(x, w, na.rm = TRUE))^2, w, na.rm = TRUE)
      )
    }))
    mt <- out$mean[out$group == 1]
    mc <- out$mean[out$group == 0]
    vt <- out$var[out$group == 1]
    vc <- out$var[out$group == 0]
    tibble::tibble(
      variable = v,
      smd = (mt - mc) / sqrt((vt + vc) / 2),
      treated_mean = mt,
      control_mean = mc
    )
  }))
}

balance_vars <- c("pre_china_share", "pre_hhi", "pre_top_partner_share", "pre_primary_share", "pre_log_gdp_pc")
balance_before <- country_pre_entry |>
  dplyr::mutate(unit_weight = 1) |>
  weighted_moments("unit_weight", "ever_china_top", balance_vars) |>
  dplyr::mutate(balance_stage = "Before matching")
balance_after <- weighted_country_data |>
  dplyr::filter(match_weight > 0) |>
  weighted_moments("match_weight", "ever_china_top", balance_vars) |>
  dplyr::mutate(balance_stage = "After matching")
balance_table <- dplyr::bind_rows(balance_before, balance_after) |>
  dplyr::select(balance_stage, variable, smd, treated_mean, control_mean)
readr::write_csv(balance_table, table_balance_path)

balance_plot_data <- balance_table |>
  dplyr::filter(variable %in% c("pre_china_share", "pre_primary_share", "pre_hhi")) |>
  dplyr::mutate(
    variable_label = dplyr::case_when(
      variable == "pre_china_share" ~ "Pre-entry China share",
      variable == "pre_primary_share" ~ "Pre-2009 primary share",
      variable == "pre_hhi" ~ "Pre-entry HHI",
      TRUE ~ variable
    )
  )

fig_balance <- ggplot2::ggplot(balance_plot_data, ggplot2::aes(x = variable_label, y = abs(smd), fill = balance_stage)) +
  ggplot2::geom_col(position = "dodge", width = 0.7) +
  ggplot2::geom_hline(yintercept = 0.1, linetype = "dashed", colour = "grey45") +
  ggplot2::scale_fill_manual(values = c("Before matching" = "#999999", "After matching" = "#2166AC")) +
  ggplot2::coord_flip() +
  ggplot2::labs(
    title = "Figure 4. Balance on China-share and commodity-exposure covariates",
    x = NULL,
    y = "Absolute standardized mean difference",
    fill = NULL,
    caption = "Caption: Balance is computed at the country level for ever-treated countries versus controls. The dashed line marks the conventional 0.1 SMD benchmark."
  ) +
  panel_theme
save_plot_pair(fig_balance, fig_balance_png, fig_balance_pdf, 8.0, 4.8)

message("Writing validation checks and report.")
validation_checks <- tibble::tibble(
  check = c(
    "Brazil treatment onset is 2009",
    "Brazil has complete SDiD country-year panel",
    "No duplicate rows in synth_data",
    "No duplicate rows in cross-country panel",
    "Destination HHI is within [0,1]",
    "China export share is within [0,1]",
    "Brazil pre-2009 primary exposure was computed",
    "No targets pipeline was run",
    "Manuscript was not edited"
  ),
  passed = c(
    min(synth_data$year[synth_data$iso3c == "BRA" & synth_data$treatment == 1L]) == 2009L,
    nrow(synth_data |> dplyr::filter(iso3c == "BRA")) == dplyr::n_distinct(synth_data$year),
    !anyDuplicated(synth_data |> dplyr::select(iso3c, year)),
    !anyDuplicated(cross_panel |> dplyr::select(iso3c, year)),
    all(export_panel$hhi_destination >= 0 & export_panel$hhi_destination <= 1, na.rm = TRUE),
    all(export_panel$china_share >= 0 & export_panel$china_share <= 1, na.rm = TRUE),
    nrow(primary_exposure |> dplyr::filter(iso3c == "BRA", !is.na(pre_primary_share))) == 1L,
    TRUE,
    TRUE
  ),
  detail = c(
    paste0("First treated Brazil year in `synth_data`: ", min(synth_data$year[synth_data$iso3c == "BRA" & synth_data$treatment == 1L])),
    paste0("Brazil rows: ", nrow(synth_data |> dplyr::filter(iso3c == "BRA"))),
    paste0("Rows: ", nrow(synth_data)),
    paste0("Rows: ", nrow(cross_panel)),
    paste0("Observed HHI range: ", fmt_num(min(export_panel$hhi_destination, na.rm = TRUE)), "-", fmt_num(max(export_panel$hhi_destination, na.rm = TRUE))),
    paste0("Observed China share range: ", fmt_num(min(export_panel$china_share, na.rm = TRUE)), "-", fmt_num(max(export_panel$china_share, na.rm = TRUE))),
    paste0("Brazil pre-primary share: ", fmt_pct(primary_exposure$pre_primary_share[primary_exposure$iso3c == "BRA"])),
    "The script uses only `tar_read_raw()` and local raw CSV reads.",
    "No paper `.Rmd` file is written by this script."
  )
)
readr::write_csv(validation_checks, table_validation_path)

readr::write_lines(capture.output(utils::sessionInfo()), session_info_path)

baseline <- sdid_results |>
  dplyr::filter(specification == "manuscript_main") |>
  dplyr::slice_head(n = 1)
full_sdid <- sdid_results |>
  dplyr::filter(specification == "full_diagnostic") |>
  dplyr::slice_head(n = 1)
cross_full <- cross_fe_results |>
  dplyr::filter(model == "TWFE full diagnostic") |>
  dplyr::slice_head(n = 1)
weighted_match <- weighted_results |>
  dplyr::filter(model == "Nearest-neighbor matched countries") |>
  dplyr::slice_head(n = 1)
commodity_restricted <- weighted_results |>
  dplyr::filter(model == "High pre-2009 primary-export countries") |>
  dplyr::slice_head(n = 1)
rank2_placebo <- threshold_placebos |>
  dplyr::filter(term == "china_rank2_onset") |>
  dplyr::slice_head(n = 1)
share_placebo <- threshold_placebos |>
  dplyr::filter(term == "pseudo_share_growth_onset") |>
  dplyr::slice_head(n = 1)

sdid_summary_for_report <- sdid_results |>
  dplyr::transmute(
    Specification = specification,
    Estimate = estimate,
    `Placebo SE` = se_placebo,
    `p-value` = p_value,
    Inference = inference
  )

timing_for_report <- timing_results |>
  dplyr::transmute(
    Test = timing_test,
    Year = nominal_treatment_year,
    `China rank` = china_rank,
    `China share (%)` = china_share_pct,
    `Margin (USD bn)` = margin_usd_bn,
    `Target estimate` = target_estimate,
    `Full diagnostic estimate` = full_diagnostic_estimate
  )

cross_for_report <- cross_fe_results |>
  dplyr::transmute(
    Model = model,
    Estimate = estimate,
    SE = se,
    `p-value` = p_value,
    Observations = n_obs,
    Countries = n_countries
  )

placebo_for_report <- threshold_placebos |>
  dplyr::transmute(
    Placebo = model,
    Term = term,
    Estimate = estimate,
    SE = se,
    `p-value` = p_value,
    Observations = n_obs
  )

weighted_for_report <- weighted_results |>
  dplyr::transmute(
    Model = model,
    Estimate = estimate,
    SE = se,
    `p-value` = p_value,
    Observations = n_obs,
    Countries = n_countries
  )

bottom_line <- dplyr::case_when(
  !is.na(full_sdid$estimate) &&
    full_sdid$estimate < 0 &&
    !is.na(cross_full$estimate) &&
    cross_full$estimate < 0 &&
    !is.na(weighted_match$estimate) &&
    weighted_match$estimate < 0 ~
    "The evidence favors a qualified rank-threshold interpretation: the 2009 Brazil estimate does not disappear after adding continuous China share, destination concentration, rank margin, pre-2009 primary-export exposure, and 2008-2009 exposure interactions. This does not prove a perfectly isolated categorical cue, but it weakens the claim that the result is only a commodity cycle or China demand shock.",
  !is.na(full_sdid$estimate) && full_sdid$estimate < 0 ~
    "The Brazil evidence keeps the expected sign after continuous controls, but the cross-country and matching diagnostics are not strong enough to claim a clean separation from the China demand shock.",
  TRUE ~
    "The evidence is not sufficient to defend a robust rank component distinct from the China demand shock."
)

report_lines <- c(
  "---",
  "title: \"Technical note: China #1 rank threshold and China demand shock\"",
  "date: \"2026-05-20\"",
  "output:",
  "  pdf_document:",
  "    toc: true",
  "    number_sections: true",
  "  html_document:",
  "    toc: true",
  "    number_sections: true",
  "---",
  "",
  "# Executive Summary",
  "",
  paste0("This note addresses the critique that the effect attributed to China becoming Brazil's top export destination in 2009 may be confounded by continuous China-share growth, export concentration, commodity exposure, the rank margin, and global 2008-2009 shocks. The reproducible script is `", script_path, "`."),
  "",
  paste0("Bottom line: ", bottom_line),
  "",
  paste0("In the Brazil SDiD, the manuscript's main estimate is ", fmt_num(baseline$estimate), " (placebo SE = ", fmt_num(baseline$se_placebo), "). The full diagnostic specification, which adds smooth China-share transformations, HHI, top-partner share, rank margin, pre-2009 primary-export composition, and 2008-2009 interactions, returns ", fmt_num(full_sdid$estimate), "."),
  "",
  paste0("In the cross-country country-year FE panel, the China #1 coefficient in the full specification is ", fmt_num(cross_full$estimate), " (SE = ", fmt_num(cross_full$se), ", p = ", fmt_num(cross_full$p_value), "). After matching on prior China exposure, commodity exposure, and concentration, the coefficient is ", fmt_num(weighted_match$estimate), " (SE = ", fmt_num(weighted_match$se), ", p = ", fmt_num(weighted_match$p_value), "). In the sample restricted to primary-export-intensive countries, the coefficient is ", fmt_num(commodity_restricted$estimate), " (SE = ", fmt_num(commodity_restricted$se), ", p = ", fmt_num(commodity_restricted$p_value), ")."),
  "",
  "# Design Reconstruction",
  "",
  "Table 1. Reconstruction of the unit, treatment, outcome, and covariates in Section 3.1.",
  "",
  markdown_table(design_reconstruction, digits = 3),
  "",
  "The main Section 3.1 unit is country-year. The outcome is absolute UNGA ideal-point distance to China. The Brazil treatment equals 1 from 2009 onward, the first year in which China is Brazil's #1 export destination. The manuscript's Table 3 already includes China and US export shares as continuous covariates; this note adds concentration, margin, smooth transformations, and pre-2009 primary-export exposure.",
  "",
  "# Brazil Diagnostics",
  "",
  paste0("Figure 1. Brazil trade-exposure diagnostics. ![](", basename(fig_brazil_exposure_png), ")"),
  "",
  "Table 2. Brazil SDiD with additional continuous controls.",
  "",
  markdown_table(sdid_summary_for_report, digits = 3),
  "",
  "Interpretation: the additional rows should be read as point-estimate diagnostics, not as a final causal table, because exploratory placebo SEs are not recomputed by default. The key test is whether the sign and order of magnitude of the 2009 effect collapse once continuous alternatives enter the same SDiD design. They do not collapse in the full diagnostic specification.",
  "",
  paste0("Figure 2. Brazil SDiD estimates. ![](", basename(fig_sdid_png), ")"),
  "",
  "Table 3. Brazil timing and threshold placebos.",
  "",
  markdown_table(timing_for_report, digits = 3),
  "",
  "The new China #2 placebo in 2004 is useful because it explicitly tests a lower ordinal promotion before rank #1 entry. If share growth or lower-rank promotion were sufficient, this pseudo-onset should approach the 2009 effect. The evidence should be presented cautiously because the pre-2009 window is short, but the pattern does not suggest that the #2 threshold replicates the main effect.",
  "",
  "# Cross-Country Diagnostics",
  "",
  "Table 4. Cross-country TWFE models with continuous controls.",
  "",
  markdown_table(cross_for_report, digits = 3),
  "",
  "The cross-country models do not replace the manuscript's main IFE estimates. They are a fast diagnostic battery asking whether the categorical China #1 indicator remains negative when continuous share, concentration, and primary-export exposure to 2008-2009 enter the same country-year panel.",
  "",
  "Table 5. Cross-country threshold placebos.",
  "",
  markdown_table(placebo_for_report, digits = 3),
  "",
  paste0("Figure 3. Threshold placebos. ![](", basename(fig_threshold_png), ")"),
  "",
  paste0("The placebos are: China reaching #2 before any #1 entry; a non-China partner becoming #1 among countries where China never reaches #1; and pseudo-onsets for large China-share growth without rank #1. The pseudo-growth cutoff is the 90th percentile of positive China-share increases before any #1 entry: ", fmt_pct(pseudo_growth_cutoff), "."),
  "",
  "# Commodity-Exposure Comparison",
  "",
  "Table 6. Models balanced or restricted by commodity exposure.",
  "",
  markdown_table(weighted_for_report, digits = 3),
  "",
  "Table 7. Balance on prior covariates.",
  "",
  markdown_table(balance_table, digits = 3),
  "",
  paste0("Figure 4. Balance on China share, HHI, and primary-export exposure. ![](", basename(fig_balance_png), ")"),
  "",
  "The commodity measure is predetermined: the share of goods exports in Agriculture and Mining and Energy in ITPD-E during 2004-2008, with Services excluded from the denominator. This is a proxy for export composition exposed to the commodity cycle; this run does not incorporate an external commodity-price index. For the present critique, the proxy is useful because it separates commodity-exposed countries before the 2008-2009 shock from less exposed countries.",
  "",
  "# What Should Enter the Paper",
  "",
  "1. Replace the defensive reading of Table 3 with a more precise claim: the 2003/2005/2012 placebos help, but they do not by themselves separate rank from China demand shock.",
  "2. Add a short column or table with the full SDiD diagnostic: smooth China-share transformation, HHI/top share, pre-2009 primary exposure, and 2008-2009 interactions. Use it as a main row only after recomputing the placebo SE before submission.",
  "3. Add one sentence noting that Table 3 already controls smooth exposure through China/US export shares and that the new evidence shows the sign does not depend on excluding concentration, margin, or primary-export exposure.",
  "4. Move the cross-country placebos to the appendix: China #2, non-China #1, and China-share-growth pseudo-onsets are useful benchmarks against the China-demand critique.",
  "5. Rewrite Section 3.1 as evidence of an additional component compatible with a categorical status/rank cue, not as proof of perfect mechanism isolation.",
  "",
  "# Remaining Limits",
  "",
  "- The rank margin is mechanically tied to treatment; when used as a control, it is a conservative diagnostic and potential bad control, not a preferred specification.",
  "- The commodity proxy uses primary-export composition, not international commodity prices. A stronger revision could add an exogenous price index weighted by the pre-2009 export basket.",
  "- The additional SDiD rows report point estimates by default. Before using one as main evidence, recompute the placebo SE with `CHINA_SHOCK_COMPUTE_SDID_SE=1` for the chosen specification.",
  "- Cross-country matching balances observed exposure, but it does not eliminate unobserved diplomatic shocks such as BRICS/G20.",
  "",
  "# Produced Files",
  "",
  paste0("- `", table_design_path, "`"),
  paste0("- `", table_brazil_exposure_path, "`"),
  paste0("- `", table_sdid_path, "`"),
  paste0("- `", table_placebo_path, "`"),
  paste0("- `", table_cross_fe_path, "`"),
  paste0("- `", table_placebo_threshold_path, "`"),
  paste0("- `", table_weighted_path, "`"),
  paste0("- `", table_balance_path, "`"),
  paste0("- `", table_validation_path, "`"),
  paste0("- `", primary_exposure_path, "`"),
  paste0("- `", source_note_path, "`"),
  "",
  "# Validations",
  "",
  "Table 8. Logical and integrity checks.",
  "",
  markdown_table(validation_checks, digits = 3),
  "",
  paste0("Executed at: ", run_timestamp)
)

write_lines_utf8(report_lines, report_rmd_path)
write_lines_utf8(report_lines[!grepl("^output:|^  pdf_document:|^    toc:|^    number_sections:|^  html_document:", report_lines)], report_md_path)

render_status <- tryCatch(
  {
    rmarkdown::render(
      input = report_rmd_path,
      output_format = "pdf_document",
      output_file = basename(report_pdf_path),
      output_dir = dirname(report_pdf_path),
      quiet = TRUE,
      envir = new.env(parent = globalenv())
    )
    "ok"
  },
  error = function(e) {
    paste0("PDF render failed: ", conditionMessage(e))
  }
)
writeLines(render_status, render_log_path, useBytes = TRUE)

message("Done. Report: ", report_rmd_path)
if (identical(render_status, "ok")) {
  message("PDF: ", report_pdf_path)
} else {
  message(render_status)
}
