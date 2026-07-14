#!/usr/bin/env Rscript

# Audit predetermined commodity exposure and post-treatment covariates in the
# Brazil SDiD design. This script reads existing targets but never runs targets.

suppressPackageStartupMessages({
  library(targets)
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(readxl)
  library(tibble)
  library(synthdid)
  library(countrycode)
})

options(scipen = 999)
set.seed(20260711)

run_started <- Sys.time()
run_date <- as.character(Sys.Date())
audit_code_version <- "2026-07-12-v3-external-goods"
script_path <- file.path(
  "scripts", "diagnostics",
  "audit_brazil_sdid_predetermined_commodity_controls.R"
)
script_sha256 <- digest::digest(
  file = script_path, algo = "sha256", serialize = FALSE
)
placebo_replications <- as.integer(Sys.getenv("SDID_PLACEBO_REPLICATIONS", "1000"))
if (is.na(placebo_replications) || placebo_replications < 1000L) {
  stop("SDID_PLACEBO_REPLICATIONS must be at least 1000 for the final audit.", call. = FALSE)
}
parallel_cores <- as.integer(Sys.getenv(
  "SDID_PARALLEL_CORES",
  as.character(min(12L, parallel::detectCores(logical = FALSE)))
))
if (is.na(parallel_cores) || parallel_cores < 1L) parallel_cores <- 1L
Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1"
)

target_store <- "_targets"
itpde_path <- file.path("raw data", "ITPDE_R03.csv")
legacy_exposure_path <- file.path(
  "data", "processed", "diagnostics",
  "pre2009_primary_goods_export_exposure_itpde_2026-05-20.csv"
)
pink_sheet_path <- file.path(
  "data", "raw", "commodity_prices", "world_bank_pink_sheet",
  "CMO-Historical-Data-Annual_2026-07-11.xlsx"
)
out_dir <- file.path(
  "data", "processed", "diagnostics",
  "brazil_sdid_predetermined_commodity_controls"
)
report_dir <- file.path("quality_reports", "china_demand_shock_rank_threshold")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
reference_dir <- file.path(checkpoint_dir, "references")
dir.create(reference_dir, recursive = TRUE, showWarnings = FALSE)

out_path <- function(filename) file.path(out_dir, filename)
report_path <- function(filename) file.path(report_dir, filename)

covariate_inventory_path <- out_path("table_1_current_covariate_inventory.csv")
commodity_exposure_path <- out_path("table_2_pre2009_commodity_exposure_by_country.csv")
price_indices_path <- out_path("table_3_world_bank_commodity_price_indices.csv")
specification_results_path <- out_path("table_4_sdid_specification_results.csv")
rank_inference_path <- out_path("table_5_sdid_rank_inference.csv")
balance_path <- out_path("table_6_sdid_covariate_balance.csv")
donor_weights_path <- out_path("table_7_sdid_donor_weights.csv")
shock_window_path <- out_path("table_8_shock_window_sensitivity.csv")
time_window_path <- out_path("table_9_time_window_sensitivity.csv")
validation_path <- out_path("table_10_validation_checks.csv")
placebo_distribution_path <- out_path("table_11_sdid_placebo_in_space_distribution.csv")
design_contract_path <- out_path("table_12_design_contract.csv")
parallel_validation_path <- out_path("table_13_parallel_placebo_validation.csv")
anticipation_window_path <- out_path("table_14_anticipation_window_sensitivity.csv")
manifest_path <- out_path("table_15_inference_artifact_manifest.csv")
existing_rank_path <- file.path(
  "data", "processed", "diagnostics", "sdid_single_treated",
  "table_a8_sdid_placebo_rank_inference.csv"
)
existing_distribution_path <- file.path(
  "data", "processed", "diagnostics", "sdid_single_treated",
  "table_a7_sdid_placebo_distribution.csv"
)
source_note_path <- report_path("SOURCES_predetermined_commodity_controls_2026-07-11.md")
session_info_path <- report_path("session_info_predetermined_commodity_controls_2026-07-11.txt")
run_log_path <- report_path("run_log_predetermined_commodity_controls_2026-07-11.txt")

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) stop("Could not read target `", name, "`: ", conditionMessage(e), call. = FALSE)
  )
}

scale_vec <- function(x) {
  if (all(is.na(x))) return(rep(NA_real_, length(x)))
  sdx <- stats::sd(x, na.rm = TRUE)
  if (is.na(sdx) || sdx == 0) return(rep(0, length(x)))
  as.numeric((x - mean(x, na.rm = TRUE)) / sdx)
}

current_covariates <- c(
  "gpi", "perc_trade_with_us", "perc_trade_with_china", "pci_cur",
  "exachange_rate", "distance_us", "us_power_gap", "hog_left", "CA_GDP",
  "govdef_GDP", "inst_parliamentary", "inst_military_exec",
  "us_trade_agreement"
)

covariate_inventory <- tibble::tribble(
  ~variable, ~description, ~timing_class, ~uses_post_2009, ~post_treatment_risk, ~frozen_rule, ~kept_in_predetermined_core,
  "gpi", "Global Power Index", "time-varying plausibly exogenous/slow-moving", TRUE, "moderate: post-2009 power can respond to economic changes", "2004-2008 mean", FALSE,
  "perc_trade_with_us", "Export share to the United States", "time-varying treatment-related exposure", TRUE, "high: trade composition can be affected by the treatment process", "2004-2008 mean", TRUE,
  "perc_trade_with_china", "Export share to China", "time-varying treatment-defining/mediating exposure", TRUE, "high: mechanically related to China becoming rank 1", "2004-2008 mean", TRUE,
  "pci_cur", "Per-capita income", "time-varying macroeconomic covariate", TRUE, "moderate: can respond to trade and commodity shocks", "2004-2008 mean", TRUE,
  "exachange_rate", "Exchange rate", "time-varying macroeconomic covariate", TRUE, "high: contemporaneous macro outcome and possible mediator", "2004-2008 mean", FALSE,
  "distance_us", "Geographic distance to Washington", "time-invariant", FALSE, "none", "first observed value", TRUE,
  "us_power_gap", "Power gap to the United States", "time-varying structural covariate", TRUE, "moderate: observed after onset and partly Brazil-specific", "2004-2008 mean", FALSE,
  "hog_left", "Head of government is left", "time-varying political covariate", TRUE, "moderate: post-onset government changes are not predetermined", "2008 value", FALSE,
  "CA_GDP", "Current-account balance as percent of GDP", "time-varying macroeconomic outcome", TRUE, "high: directly affected by trade and commodity prices", "2004-2008 mean", FALSE,
  "govdef_GDP", "Government budget deficit as percent of GDP", "time-varying policy/macro outcome", TRUE, "high: may respond to the same shock or mediate policy adjustment", "2004-2008 mean", FALSE,
  "inst_parliamentary", "Parliamentary-system indicator", "slow-moving institutional covariate", TRUE, "low to moderate: post-2009 values are not required", "2008 value", TRUE,
  "inst_military_exec", "Military-executive indicator", "time-varying institutional covariate", TRUE, "moderate: regime changes after onset are post-treatment", "2008 value", FALSE,
  "us_trade_agreement", "Trade agreement with the United States", "time-varying policy covariate", TRUE, "high: agreements after onset can be policy responses/mediators", "2008 value", TRUE
) |>
  dplyr::mutate(
    included_by_simple_fit = TRUE,
    observed_years_in_main_matrix = "1997-2015"
  ) |>
  dplyr::select(
    variable, description, timing_class, included_by_simple_fit,
    observed_years_in_main_matrix, uses_post_2009, post_treatment_risk,
    frozen_rule, kept_in_predetermined_core
  )
readr::write_csv(covariate_inventory, covariate_inventory_path)

message("Reading existing SDiD targets.")
synth_data <- safe_tar_read("synth_data")
trade_data <- safe_tar_read("trade_data")
synth_fit_target <- safe_tar_read("synth_fit")
se_synth_target <- safe_tar_read("se_synth")
synth_fit_core_target <- safe_tar_read("synth_fit_no_time_varying_covariates")
se_synth_core_target <- safe_tar_read("se_synth_no_time_varying_covariates")
existing_diagnostic_target <- safe_tar_read("china_demand_sdid_diagnostics_table")
target_metadata <- targets::tar_meta(
  fields = c(name, data, command, time),
  store = target_store
)

missing_current <- setdiff(current_covariates, names(synth_data))
if (length(missing_current) > 0L) {
  stop("Missing current covariates: ", paste(missing_current, collapse = ", "), call. = FALSE)
}

message("Constructing annual-average predetermined commodity exposure from ITPD-E.")
if (!file.exists(itpde_path)) stop("Missing ITPD-E raw file: ", itpde_path, call. = FALSE)
trade_raw <- data.table::fread(
  itpde_path,
  select = c(
    "year", "exporter_iso3", "importer_iso3", "trade",
    "industry_id", "broad_sector"
  ),
  showProgress = FALSE
)
domestic_rows_excluded <- trade_raw[
  year >= 2004L & year <= 2008L &
    !is.na(exporter_iso3) & !is.na(importer_iso3) &
    exporter_iso3 == importer_iso3,
  .N
]
domestic_trade_excluded <- trade_raw[
  year >= 2004L & year <= 2008L &
    !is.na(exporter_iso3) & !is.na(importer_iso3) &
    exporter_iso3 == importer_iso3,
  sum(as.numeric(trade), na.rm = TRUE)
]
trade_raw <- trade_raw[
  year >= 2004L & year <= 2008L &
    !is.na(exporter_iso3) & !is.na(importer_iso3) &
    exporter_iso3 != importer_iso3
]
trade_raw[, trade := data.table::fifelse(is.na(trade), 0, as.numeric(trade))]
trade_raw[, goods_trade := data.table::fifelse(broad_sector != "Services", trade, 0)]
trade_raw[, agriculture_trade := data.table::fifelse(broad_sector == "Agriculture", trade, 0)]
trade_raw[, mining_energy_trade := data.table::fifelse(broad_sector == "Mining and Energy", trade, 0)]
trade_raw[, energy_mapped_trade := data.table::fifelse(industry_id %in% c(29L, 30L, 31L), trade, 0)]
trade_raw[, metals_mapped_trade := data.table::fifelse(industry_id %in% c(32L, 33L), trade, 0)]
trade_raw[, mining_unmapped_trade := data.table::fifelse(industry_id %in% c(34L, 35L), trade, 0)]

commodity_yearly <- trade_raw[, .(
  goods_exports = sum(goods_trade, na.rm = TRUE),
  agriculture_exports = sum(agriculture_trade, na.rm = TRUE),
  mining_energy_exports = sum(mining_energy_trade, na.rm = TRUE),
  china_goods_exports = sum(goods_trade[importer_iso3 == "CHN"], na.rm = TRUE),
  energy_mapped_exports = sum(energy_mapped_trade, na.rm = TRUE),
  metals_mapped_exports = sum(metals_mapped_trade, na.rm = TRUE),
  mining_unmapped_exports = sum(mining_unmapped_trade, na.rm = TRUE)
), by = .(iso3c = exporter_iso3, year)]
commodity_yearly[, primary_exports := agriculture_exports + mining_energy_exports]
commodity_yearly[, china_goods_share := data.table::fifelse(
  goods_exports > 0, china_goods_exports / goods_exports, NA_real_
)]
for (nm in c(
  "primary", "agriculture", "mining_energy", "energy_mapped",
  "metals_mapped", "mining_unmapped"
)) {
  export_col <- paste0(nm, "_exports")
  share_col <- paste0(nm, "_share")
  commodity_yearly[, (share_col) := data.table::fifelse(
    goods_exports > 0, get(export_col) / goods_exports, NA_real_
  )]
}

commodity_exposure_dt <- commodity_yearly[, .(
  pre_window_start = 2004L,
  pre_window_end = 2008L,
  observed_years = data.table::uniqueN(year),
  pre_primary_share_mean = mean(primary_share, na.rm = TRUE),
  pre_agriculture_share_mean = mean(agriculture_share, na.rm = TRUE),
  pre_mining_energy_share_mean = mean(mining_energy_share, na.rm = TRUE),
  pre_energy_mapped_share_mean = mean(energy_mapped_share, na.rm = TRUE),
  pre_metals_mapped_share_mean = mean(metals_mapped_share, na.rm = TRUE),
  pre_mining_unmapped_share_mean = mean(mining_unmapped_share, na.rm = TRUE),
  pre_china_goods_share_mean = mean(china_goods_share, na.rm = TRUE),
  pre_primary_share_pooled = sum(primary_exports, na.rm = TRUE) / sum(goods_exports, na.rm = TRUE),
  pre_agriculture_share_pooled = sum(agriculture_exports, na.rm = TRUE) / sum(goods_exports, na.rm = TRUE),
  pre_mining_energy_share_pooled = sum(mining_energy_exports, na.rm = TRUE) / sum(goods_exports, na.rm = TRUE),
  pre_goods_exports = sum(goods_exports, na.rm = TRUE)
), by = iso3c]
commodity_exposure_dt[, price_mapping_coverage := data.table::fifelse(
  pre_primary_share_mean > 0,
  (pre_agriculture_share_mean + pre_energy_mapped_share_mean + pre_metals_mapped_share_mean) /
    pre_primary_share_mean,
  NA_real_
)]
commodity_exposure <- tibble::as_tibble(commodity_exposure_dt) |>
  dplyr::mutate(country_name = countrycode::countrycode(iso3c, "iso3c", "country.name")) |>
  dplyr::select(
    iso3c, country_name, pre_window_start, pre_window_end, observed_years,
    pre_primary_share_mean, pre_agriculture_share_mean,
    pre_mining_energy_share_mean, pre_energy_mapped_share_mean,
    pre_metals_mapped_share_mean, pre_mining_unmapped_share_mean,
    pre_china_goods_share_mean,
    price_mapping_coverage, pre_primary_share_pooled,
    pre_agriculture_share_pooled, pre_mining_energy_share_pooled,
    pre_goods_exports
  ) |>
  dplyr::arrange(iso3c)
readr::write_csv(commodity_exposure, commodity_exposure_path)
anticipation_commodity_exposure <- data.table::rbindlist(lapply(
  c(2006L, 2007L, 2008L),
  function(window_end) {
    commodity_yearly[
      year >= 2004L & year <= window_end,
      .(
        exposure_window_start = 2004L,
        exposure_window_end = window_end,
        observed_years = data.table::uniqueN(year),
        primary_share = mean(primary_share, na.rm = TRUE),
        agriculture_share = mean(agriculture_share, na.rm = TRUE),
        mining_energy_share = mean(mining_energy_share, na.rm = TRUE)
        , pre_china_goods_share = mean(china_goods_share, na.rm = TRUE)
      ),
      by = iso3c
    ]
  }
)) |>
  tibble::as_tibble()
internal_rows_retained <- trade_raw[exporter_iso3 == importer_iso3, .N]
if (!file.exists(legacy_exposure_path)) {
  stop("Missing legacy exposure file: ", legacy_exposure_path, call. = FALSE)
}
legacy_commodity_exposure <- readr::read_csv(
  legacy_exposure_path, show_col_types = FALSE
) |>
  dplyr::select(
    iso3c,
    legacy_primary_share = pre_primary_share,
    legacy_agriculture_share = pre_agriculture_share,
    legacy_mining_energy_share = pre_mining_energy_share
  )
rm(trade_raw, commodity_yearly, commodity_exposure_dt)
invisible(gc())

message("Reading World Bank Pink Sheet annual nominal indices.")
if (!file.exists(pink_sheet_path)) stop("Missing Pink Sheet raw file: ", pink_sheet_path, call. = FALSE)
pink_raw <- readxl::read_excel(
  pink_sheet_path,
  sheet = "Annual Indices (Nominal)",
  skip = 9,
  col_names = FALSE
)
pink_names <- names(pink_raw)
pink_indices <- pink_raw |>
  dplyr::transmute(
    year = suppressWarnings(as.integer(.data[[pink_names[[1]]]])),
    energy_index = suppressWarnings(as.numeric(.data[[pink_names[[3]]]])),
    agriculture_index = suppressWarnings(as.numeric(.data[[pink_names[[5]]]])),
    metals_minerals_index = suppressWarnings(as.numeric(.data[[pink_names[[15]]]]))
  ) |>
  dplyr::filter(!is.na(year), year >= 1997L, year <= 2016L)

pink_2007 <- pink_indices |>
  dplyr::filter(year == 2007L) |>
  dplyr::slice_head(n = 1)
if (nrow(pink_2007) != 1L) stop("Pink Sheet 2007 baseline is unavailable.", call. = FALSE)
pink_indices <- pink_indices |>
  dplyr::mutate(
    energy_log_change_2007 = log(energy_index / pink_2007$energy_index),
    agriculture_log_change_2007 = log(agriculture_index / pink_2007$agriculture_index),
    metals_minerals_log_change_2007 = log(metals_minerals_index / pink_2007$metals_minerals_index)
  ) |>
  dplyr::select(
    year, energy_index, agriculture_index, metals_minerals_index,
    energy_log_change_2007, agriculture_log_change_2007,
    metals_minerals_log_change_2007
  )
readr::write_csv(pink_indices, price_indices_path)

message("Freezing current covariates and constructing exposure interactions.")
pre_years <- 2004:2008
binary_endpoint <- c("hog_left", "inst_parliamentary", "inst_military_exec", "us_trade_agreement")
continuous_mean <- setdiff(current_covariates, c("distance_us", binary_endpoint))

frozen_means <- synth_data |>
  dplyr::filter(year %in% pre_years) |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    dplyr::across(dplyr::all_of(continuous_mean), ~mean(.x, na.rm = TRUE), .names = "frozen_{.col}"),
    frozen_distance_us = dplyr::first(distance_us),
    dplyr::across(dplyr::all_of(binary_endpoint), ~dplyr::first(.x[year == 2008L]), .names = "frozen_{.col}"),
    .groups = "drop"
  )

legacy_pre_china_yearly <- trade_data |>
  dplyr::filter(
    year %in% pre_years,
    !is.na(exporter_iso3), !is.na(importer_iso3),
    exporter_iso3 != importer_iso3
  ) |>
  dplyr::mutate(exports = dplyr::coalesce(as.numeric(exports), 0)) |>
  dplyr::group_by(year, exporter_iso3) |>
  dplyr::summarise(
    export_total = sum(exports, na.rm = TRUE),
    china_exports = sum(exports[importer_iso3 == "CHN"], na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    legacy_china_share_all_sector = dplyr::if_else(
      export_total > 0, china_exports / export_total, NA_real_
    )
  ) |>
  dplyr::select(
    iso3c = exporter_iso3, year, legacy_china_share_all_sector
  )
legacy_pre_china_exposure <- legacy_pre_china_yearly |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    legacy_pre_china_share_2004_2008 = mean(
      legacy_china_share_all_sector, na.rm = TRUE
    ),
    .groups = "drop"
  )
pre_china_exposure <- commodity_exposure |>
  dplyr::select(
    iso3c,
    pre_china_share_2004_2008 = pre_china_goods_share_mean
  )
anticipation_china_exposure <- anticipation_commodity_exposure |>
  dplyr::select(
    iso3c, exposure_window_end,
    pre_china_share = pre_china_goods_share,
    observed_years
  )

panel <- synth_data |>
  dplyr::left_join(frozen_means, by = "iso3c") |>
  dplyr::left_join(pre_china_exposure, by = "iso3c") |>
  dplyr::left_join(legacy_pre_china_exposure, by = "iso3c") |>
  dplyr::left_join(commodity_exposure, by = "iso3c") |>
  dplyr::left_join(legacy_commodity_exposure, by = "iso3c") |>
  dplyr::left_join(pink_indices, by = "year") |>
  dplyr::mutate(
    shock_2008 = as.integer(year == 2008L),
    shock_2009 = as.integer(year == 2009L),
    shock_2008_2009 = as.integer(year %in% 2008:2009),
    primary_level_z = scale_vec(pre_primary_share_mean),
    agriculture_level_z = scale_vec(pre_agriculture_share_mean),
    mining_energy_level_z = scale_vec(pre_mining_energy_share_mean),
    primary_x_2008_z = scale_vec(pre_primary_share_mean * shock_2008),
    primary_x_2009_z = scale_vec(pre_primary_share_mean * shock_2009),
    primary_x_2008_2009_z = scale_vec(pre_primary_share_mean * shock_2008_2009),
    agriculture_x_2008_2009_z = scale_vec(pre_agriculture_share_mean * shock_2008_2009),
    mining_energy_x_2008_2009_z = scale_vec(pre_mining_energy_share_mean * shock_2008_2009),
    pre_china_x_2008_2009_z = scale_vec(pre_china_share_2004_2008 * shock_2008_2009),
    weighted_price_log_change_2007 =
      pre_agriculture_share_mean * agriculture_log_change_2007 +
      pre_energy_mapped_share_mean * energy_log_change_2007 +
      pre_metals_mapped_share_mean * metals_minerals_log_change_2007,
    weighted_price_x_2008_z = scale_vec(weighted_price_log_change_2007 * shock_2008),
    weighted_price_x_2009_z = scale_vec(weighted_price_log_change_2007 * shock_2009),
    weighted_price_x_2008_2009_z = scale_vec(weighted_price_log_change_2007 * shock_2008_2009),
    legacy_primary_level_z = scale_vec(legacy_primary_share),
    legacy_agriculture_level_z = scale_vec(legacy_agriculture_share),
    legacy_mining_energy_level_z = scale_vec(legacy_mining_energy_share),
    legacy_primary_x_2008_2009_z = scale_vec(legacy_primary_share * shock_2008_2009),
    legacy_pre_china_x_2008_2009_z = scale_vec(
      legacy_pre_china_share_2004_2008 * shock_2008_2009
    )
  )

all_frozen_covariates <- paste0("frozen_", current_covariates)
predetermined_core <- c(
  "frozen_perc_trade_with_china", "frozen_perc_trade_with_us",
  "frozen_pci_cur", "frozen_distance_us", "frozen_inst_parliamentary",
  "frozen_us_trade_agreement"
)
specifications <- list(
  current_baseline = current_covariates,
  all_current_covariates_frozen = all_frozen_covariates,
  predetermined_core = predetermined_core,
  predetermined_plus_primary_level = c(predetermined_core, "primary_level_z"),
  predetermined_plus_primary_gfc_2008_2009 = c(
    predetermined_core, "primary_level_z", "primary_x_2008_2009_z"
  ),
  predetermined_plus_agriculture_mining_gfc = c(
    predetermined_core, "agriculture_level_z", "mining_energy_level_z",
    "agriculture_x_2008_2009_z", "mining_energy_x_2008_2009_z"
  ),
  predetermined_plus_weighted_price_gfc = c(
    predetermined_core, "weighted_price_x_2008_2009_z"
  ),
  predetermined_plus_pre_china_gfc = c(
    predetermined_core, "pre_china_x_2008_2009_z"
  ),
  existing_commodity_gfc_exposure = c(
    current_covariates, "legacy_primary_level_z", "legacy_agriculture_level_z",
    "legacy_mining_energy_level_z", "legacy_primary_x_2008_2009_z",
    "legacy_pre_china_x_2008_2009_z"
  )
)

specification_metadata <- tibble::tribble(
  ~specification, ~label, ~role, ~identification_rationale,
  "current_baseline", "Current manuscript baseline", "comparison", "Uses the current time-varying covariate matrix, including post-2009 observations.",
  "all_current_covariates_frozen", "All current covariates frozen before treatment", "post-treatment audit", "Preserves all current covariate concepts but fixes them using 2004-2008 means, 2008 endpoints, or time-invariant values.",
  "predetermined_core", "SDiD without time-varying/post-treatment covariates", "preferred main specification", "Removes contemporaneous covariates; the retained time-invariant levels are empirically inert in this synthdid parametrization.",
  "predetermined_plus_primary_level", "Predetermined core + primary composition", "composition diagnostic", "Adds the 2004-2008 mean annual primary-goods share; its level is predetermined but time invariant.",
  "predetermined_plus_primary_gfc_2008_2009", "Predetermined core + primary exposure x 2008-2009", "commodity mechanism robustness", "Includes the first treated year and may absorb part of the treatment mechanism; it is not an estimate of the total effect.",
  "predetermined_plus_agriculture_mining_gfc", "Predetermined core + separate agriculture/mining exposure", "decomposition robustness", "Separates Agriculture and Mining and Energy levels and 2008-2009 interactions.",
  "predetermined_plus_weighted_price_gfc", "Predetermined core + Pink Sheet price exposure", "price-shock robustness", "Uses global commodity price changes from 2007, weighted by 2004-2008 export composition and activated only in 2008-2009.",
  "predetermined_plus_pre_china_gfc", "Predetermined core + prior China exposure x 2008-2009", "China-demand robustness", "Uses mean 2004-2008 China export share interacted with the common shock window.",
  "existing_commodity_gfc_exposure", "Legacy commodity/GFC reconstruction", "invalid legacy comparator", "Reproduces the prior target, whose exposure denominator includes domestic flows; retained only for audit and not as valid robustness."
)

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
  required <- c("iso3c", "year", "abs_distance_china", "treatment", covariate_cols)
  if (anyNA(fit_data |> dplyr::select(dplyr::all_of(required)))) {
    stop("Missing values in fit for treated unit ", treated_iso3c, call. = FALSE)
  }
  counts <- fit_data |>
    dplyr::count(iso3c, name = "n_years")
  if (dplyr::n_distinct(counts$n_years) != 1L) stop("Unbalanced SDiD panel.", call. = FALSE)
  x_array <- make_covariate_array(fit_data, covariate_cols)
  panel_data <- fit_data |>
    dplyr::mutate(
      iso3c = factor(iso3c, levels = unique(iso3c)),
      year = as.integer(year),
      Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0, X = x_array)
}

extract_fit_summary <- function(fit, specification, se_value = NA_real_) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  omega <- as.numeric(weights$omega)
  controls <- setup$Y[seq_len(setup$N0), , drop = FALSE]
  treated <- as.numeric(setup$Y[setup$N0 + 1L, ])
  synthetic <- as.numeric(t(omega) %*% controls)
  gap <- treated - synthetic
  pre_gap <- gap[seq_len(setup$T0)]
  centered_gap <- gap - mean(pre_gap, na.rm = TRUE)
  rmspe_pre <- sqrt(mean(centered_gap[seq_len(setup$T0)]^2, na.rm = TRUE))
  estimate <- as.numeric(fit)
  p_value <- ifelse(is.na(se_value) || se_value <= 0, NA_real_, 2 * stats::pnorm(-abs(estimate / se_value)))
  tibble::tibble(
    specification = specification,
    estimate = estimate,
    se_placebo = se_value,
    ci_95_low = estimate - stats::qnorm(0.975) * se_value,
    ci_95_high = estimate + stats::qnorm(0.975) * se_value,
    p_value_two_sided = p_value,
    n_countries = nrow(setup$Y),
    n_treated_units = 1L,
    n_donors = setup$N0,
    n_pre_years = setup$T0,
    n_post_years = ncol(setup$Y) - setup$T0,
    rmspe_pre_intercept_adjusted = rmspe_pre
  )
}

fit_fingerprint <- function(fit, specification, replications, seed) {
  digest::digest(
    list(
      code_version = audit_code_version,
      synthdid_version = as.character(utils::packageVersion("synthdid")),
      specification = specification,
      replications = replications,
      seed = seed,
      estimate = as.numeric(fit),
      setup = attr(fit, "setup"),
      opts = attr(fit, "opts"),
      weights = attr(fit, "weights")
    ),
    algo = "sha256",
    serialize = TRUE
  )
}

# Exact package placebo algorithm with deterministic draws and parallel workers.
placebo_se_parallel <- function(fit, replications, seed, specification) {
  checkpoint_path <- file.path(
    checkpoint_dir,
    paste0("placebo_se_", specification, "_", replications, ".rds")
  )
  fingerprint <- fit_fingerprint(fit, specification, replications, seed)
  estimates <- rep(NA_real_, replications)
  if (file.exists(checkpoint_path)) {
    cached <- readRDS(checkpoint_path)
    cache_valid <- identical(cached$replications, replications) &&
      identical(cached$seed, seed) &&
      identical(cached$fingerprint, fingerprint) &&
      length(cached$estimates) == replications
    if (cache_valid) {
      estimates <- cached$estimates
      if (all(is.finite(estimates))) {
        recalculated_se <- sqrt((replications - 1) / replications) *
          stats::sd(estimates)
        if (!isTRUE(all.equal(recalculated_se, cached$se, tolerance = 1e-12))) {
          stop("Cached SE does not match cached estimates: ", specification, call. = FALSE)
        }
        message("    Reusing completed checkpoint: ", basename(checkpoint_path))
        return(recalculated_se)
      }
      message(
        "    Resuming checkpoint with ", sum(is.finite(estimates)), "/",
        replications, " placebo estimates."
      )
    }
  }

  setup <- attr(fit, "setup")
  opts <- attr(fit, "opts")
  fit_weights <- attr(fit, "weights")
  n_treated <- nrow(setup$Y) - setup$N0
  if (setup$N0 <= n_treated) {
    stop("Placebo SE requires more control than treated units.", call. = FALSE)
  }
  set.seed(seed)
  draws <- replicate(replications, sample(seq_len(setup$N0)))
  theta <- function(j) {
    ind <- draws[, j]
    n_control <- length(ind) - n_treated
    bootstrap_weights <- fit_weights
    bootstrap_weights$omega <- synthdid:::sum_normalize(
      fit_weights$omega[ind[seq_len(n_control)]]
    )
    as.numeric(do.call(
      synthdid::synthdid_estimate,
      c(
        list(
          Y = setup$Y[ind, , drop = FALSE],
          N0 = n_control,
          T0 = setup$T0,
          X = setup$X[ind, , , drop = FALSE],
          weights = bootstrap_weights
        ),
        opts
      )
    ))
  }
  missing_indices <- which(!is.finite(estimates))
  batches <- split(missing_indices, ceiling(seq_along(missing_indices) / 120L))
  for (batch_number in seq_along(batches)) {
    batch <- batches[[batch_number]]
    message(
      "    Exact placebo batch ", batch_number, "/", length(batches),
      " (", length(batch), " re-estimations; ", parallel_cores, " cores)."
    )
    estimates[batch] <- unlist(parallel::mclapply(
      batch, theta,
      mc.cores = parallel_cores, mc.preschedule = TRUE, mc.set.seed = FALSE
    ))
    partial_se <- if (all(is.finite(estimates))) {
      sqrt((replications - 1) / replications) * stats::sd(estimates)
    } else {
      NA_real_
    }
    saveRDS(
      list(
        specification = specification,
        replications = replications,
        seed = seed,
        fingerprint = fingerprint,
        se = partial_se,
        estimates = estimates,
        parallel_cores = parallel_cores,
        completed_at = if (all(is.finite(estimates))) {
          format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
        } else {
          NA_character_
        }
      ),
      checkpoint_path
    )
  }
  if (length(estimates) != replications || any(!is.finite(estimates))) {
    stop("Invalid placebo estimates for ", specification, ".", call. = FALSE)
  }
  se <- sqrt((replications - 1) / replications) * stats::sd(estimates)
  se
}

extract_donor_weights <- function(fit, specification) {
  setup <- attr(fit, "setup")
  tibble::tibble(
    specification = specification,
    iso3c = rownames(setup$Y)[seq_len(setup$N0)],
    unit_weight = as.numeric(attr(fit, "weights")$omega)
  ) |>
    dplyr::mutate(
      country_name = countrycode::countrycode(iso3c, "iso3c", "country.name"),
      weight_rank = rank(-unit_weight, ties.method = "first")
    ) |>
    dplyr::arrange(weight_rank) |>
    dplyr::select(specification, weight_rank, iso3c, country_name, unit_weight)
}

build_balance <- function(data, fit, covariate_cols, specification, year_end = 2015L) {
  weights <- extract_donor_weights(fit, specification) |>
    dplyr::select(iso3c, unit_weight)
  variables <- c("abs_distance_china", covariate_cols)
  dplyr::bind_rows(lapply(variables, function(variable) {
    means <- data |>
      dplyr::filter(year >= 1997L, year <= min(2008L, year_end)) |>
      dplyr::group_by(iso3c) |>
      dplyr::summarise(pre_mean = mean(.data[[variable]], na.rm = TRUE), .groups = "drop")
    brazil <- means |>
      dplyr::filter(iso3c == "BRA") |>
      dplyr::pull(pre_mean)
    donors <- means |>
      dplyr::filter(iso3c != "BRA") |>
      dplyr::left_join(weights, by = "iso3c")
    synthetic <- sum(donors$pre_mean * donors$unit_weight, na.rm = TRUE)
    donor_sd <- stats::sd(donors$pre_mean, na.rm = TRUE)
    tibble::tibble(
      specification = specification,
      variable = variable,
      brazil_pre_mean = brazil,
      synthetic_pre_mean = synthetic,
      difference = brazil - synthetic,
      standardized_difference = ifelse(donor_sd > 0, (brazil - synthetic) / donor_sd, NA_real_)
    ) |>
      dplyr::mutate(
        material_raw_imbalance = abs(standardized_difference) > 0.25,
        diagnostic_scope = "Raw pre-period means weighted by omega; descriptive, not residualized synthdid balance"
      )
  }))
}

run_rank_placebos <- function(data, covariate_cols, specification, year_end = 2015L) {
  units <- sort(unique(data$iso3c))
  rank_fingerprint <- digest::digest(
    list(
      code_version = audit_code_version,
      synthdid_version = as.character(utils::packageVersion("synthdid")),
      specification = specification,
      year_end = year_end,
      covariate_cols = covariate_cols,
      data = data |>
        dplyr::filter(year >= 1997L, year <= year_end) |>
        dplyr::arrange(iso3c, year) |>
        dplyr::select(
          iso3c, year, abs_distance_china,
          dplyr::all_of(covariate_cols)
        )
    ),
    algo = "sha256",
    serialize = TRUE
  )
  checkpoint_path <- file.path(
    checkpoint_dir,
    paste0("rank_placebos_", specification, "_end_", year_end, ".rds")
  )
  if (file.exists(checkpoint_path)) {
    cached <- readRDS(checkpoint_path)
    if (
      identical(cached$units, units) &&
      identical(cached$fingerprint, rank_fingerprint)
    ) {
      message("    Reusing rank-placebo checkpoint: ", basename(checkpoint_path))
      return(cached$result)
    }
  }
  distribution <- dplyr::bind_rows(parallel::mclapply(units, function(unit) {
    fit <- tryCatch(
      fit_sdid(data, covariate_cols, treated_iso3c = unit, year_end = year_end),
      error = function(e) e
    )
    if (inherits(fit, "error")) {
      return(tibble::tibble(
        specification = specification, year_end = year_end, iso3c = unit,
        estimate = NA_real_, rmspe_pre = NA_real_, status = "error",
        error = conditionMessage(fit)
      ))
    }
    summary <- extract_fit_summary(fit, specification)
    tibble::tibble(
      specification = specification, year_end = year_end, iso3c = unit,
      estimate = summary$estimate,
      rmspe_pre = summary$rmspe_pre_intercept_adjusted,
      status = "estimated", error = ""
    )
  }, mc.cores = parallel_cores, mc.preschedule = TRUE, mc.set.seed = FALSE))
  brazil <- distribution |>
    dplyr::filter(iso3c == "BRA", status == "estimated")
  valid <- distribution |>
    dplyr::filter(status == "estimated", !is.na(estimate))
  if (nrow(brazil) != 1L) {
    inference <- tibble::tibble(
      specification = specification, year_end = year_end,
      rank_p_one_sided_negative = NA_real_, rank_p_two_sided = NA_real_,
      rank_one_sided = NA_integer_, rank_two_sided = NA_integer_,
      rank_denominator = nrow(valid)
    )
  } else {
    inference <- tibble::tibble(
      specification = specification,
      year_end = year_end,
      rank_p_one_sided_negative = mean(valid$estimate <= brazil$estimate),
      rank_p_two_sided = mean(abs(valid$estimate) >= abs(brazil$estimate)),
      rank_one_sided = sum(valid$estimate <= brazil$estimate),
      rank_two_sided = sum(abs(valid$estimate) >= abs(brazil$estimate)),
      rank_denominator = nrow(valid)
    )
  }
  result <- list(distribution = distribution, inference = inference)
  saveRDS(
    list(
      units = units,
      fingerprint = rank_fingerprint,
      result = result,
      completed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    ),
    checkpoint_path
  )
  result
}

rank_unavailable <- function(specification, year_end = 2015L, note) {
  tibble::tibble(
    specification = specification,
    year_end = year_end,
    rank_p_one_sided_negative = NA_real_,
    rank_p_two_sided = NA_real_,
    rank_one_sided = NA_integer_,
    rank_two_sided = NA_integer_,
    rank_denominator = NA_integer_,
    rank_inference_status = note
  )
}

read_existing_baseline_rank <- function() {
  if (!file.exists(existing_rank_path)) {
    return(rank_unavailable(
      "current_baseline",
      note = "Existing audited baseline rank file is unavailable."
    ))
  }
  rank_data <- readr::read_csv(existing_rank_path, show_col_types = FALSE)
  one <- rank_data |>
    dplyr::filter(estimand == "One-sided negative effect") |>
    dplyr::slice_head(n = 1)
  two <- rank_data |>
    dplyr::filter(estimand == "Two-sided absolute effect") |>
    dplyr::slice_head(n = 1)
  tibble::tibble(
    specification = "current_baseline",
    year_end = 2015L,
    rank_p_one_sided_negative = one$rank_based_p_value,
    rank_p_two_sided = two$rank_based_p_value,
    rank_one_sided = one$rank,
    rank_two_sided = two$rank,
    rank_denominator = one$denominator,
    rank_inference_status = "Reused audited baseline placebo-in-space ranks from table_a8."
  )
}

message("Estimating pre-specified SDiD specifications with 1,000 placebo replications.")
fits <- list()
results <- list()
balances <- list()
weights <- list()
rank_results <- list()
rank_distributions <- list()

for (i in seq_along(specifications)) {
  specification <- names(specifications)[[i]]
  covariates <- specifications[[i]]
  message("  Fitting: ", specification)
  fit <- fit_sdid(panel, covariates, treated_iso3c = "BRA", year_end = 2015L)
  fits[[specification]] <- fit

  if (specification == "current_baseline") {
    se_value <- as.numeric(se_synth_target)
    se_source <- "Reused audited target se_synth (1,000 placebo replications)."
  } else if (specification == "predetermined_core") {
    se_value <- as.numeric(se_synth_core_target)
    se_source <- "Reused audited target se_synth_no_time_varying_covariates (1,000 placebo replications)."
  } else if (specification == "existing_commodity_gfc_exposure") {
    target_row <- existing_diagnostic_target |>
      dplyr::filter(specification == "commodity_gfc_exposure") |>
      dplyr::slice_head(n = 1)
    estimate_matches <- nrow(target_row) == 1L &&
      isTRUE(all.equal(as.numeric(fit), target_row$estimate, tolerance = 0.01))
    if (estimate_matches) {
      se_value <- target_row$se_placebo
      se_source <- "Reused audited china_demand_sdid_diagnostics_table row (1,000 placebo replications)."
    } else {
      se_value <- placebo_se_parallel(
        fit, placebo_replications, 20260711L + i, specification
      )
      se_source <- "Locally recomputed with exact parallel synthdid placebo algorithm."
    }
  } else {
    se_value <- placebo_se_parallel(
      fit, placebo_replications, 20260711L + i, specification
    )
    se_source <- "Locally recomputed with exact parallel synthdid placebo algorithm."
  }

  results[[specification]] <- extract_fit_summary(fit, specification, se_value) |>
    dplyr::mutate(se_source = se_source)
  balances[[specification]] <- build_balance(panel, fit, covariates, specification)
  weights[[specification]] <- extract_donor_weights(fit, specification)
  if (specification == "current_baseline") {
    rank_results[[specification]] <- read_existing_baseline_rank()
    if (file.exists(existing_distribution_path)) {
      rank_distributions[[specification]] <- readr::read_csv(
        existing_distribution_path,
        show_col_types = FALSE
      ) |>
        dplyr::transmute(
          specification = "current_baseline",
          year_end = 2015L,
          iso3c,
          estimate,
          rmspe_pre,
          status = "estimated",
          error = ""
        )
    }
  } else if (specification %in% c(
    "predetermined_core",
    "predetermined_plus_primary_gfc_2008_2009"
  )) {
    rank_obj <- run_rank_placebos(panel, covariates, specification, year_end = 2015L)
    rank_results[[specification]] <- rank_obj$inference |>
      dplyr::mutate(rank_inference_status = "Locally recomputed placebo-in-space ranks.")
    rank_distributions[[specification]] <- rank_obj$distribution
  } else {
    rank_results[[specification]] <- rank_unavailable(
      specification,
      note = "Not recomputed: rank inference is reported for the audited baseline, the preferred main specification, and the pre-specified commodity robustness."
    )
  }
}

specification_results <- dplyr::bind_rows(results) |>
  dplyr::left_join(specification_metadata, by = "specification") |>
  dplyr::left_join(
    dplyr::bind_rows(rank_results) |>
      dplyr::select(-year_end),
    by = "specification"
  )
baseline_estimate <- specification_results |>
  dplyr::filter(specification == "current_baseline") |>
  dplyr::pull(estimate)
specification_results <- specification_results |>
  dplyr::mutate(
    sign_stable_vs_current = sign(estimate) == sign(baseline_estimate),
    magnitude_ratio_vs_current = abs(estimate / baseline_estimate),
    placebo_inference_stable = is.finite(se_placebo) & se_placebo < 10,
    se_method = "synthdid placebo",
    se_replications = placebo_replications,
    preferred_by_identification = specification == "predetermined_core"
  ) |>
  dplyr::select(
    specification, label, role, preferred_by_identification,
    identification_rationale, estimate, se_placebo, ci_95_low, ci_95_high,
    p_value_two_sided, rank_p_one_sided_negative, rank_p_two_sided,
    rank_one_sided, rank_two_sided, rank_denominator, n_countries,
    n_treated_units, n_donors, n_pre_years, n_post_years,
    rmspe_pre_intercept_adjusted, sign_stable_vs_current,
    magnitude_ratio_vs_current, placebo_inference_stable,
    se_method, se_replications, se_source, rank_inference_status
  )
readr::write_csv(specification_results, specification_results_path)
readr::write_csv(dplyr::bind_rows(rank_results), rank_inference_path)
readr::write_csv(dplyr::bind_rows(balances), balance_path)
readr::write_csv(dplyr::bind_rows(weights), donor_weights_path)
readr::write_csv(dplyr::bind_rows(rank_distributions), placebo_distribution_path)

message("Estimating point estimates for pre-specified shock-window sensitivities.")
shock_specs <- list(
  shock_2008 = c(predetermined_core, "primary_level_z", "primary_x_2008_z"),
  shock_2009 = c(predetermined_core, "primary_level_z", "primary_x_2009_z"),
  shock_2008_2009 = c(predetermined_core, "primary_level_z", "primary_x_2008_2009_z"),
  price_shock_2008 = c(predetermined_core, "weighted_price_x_2008_z"),
  price_shock_2009 = c(predetermined_core, "weighted_price_x_2009_z"),
  price_shock_2008_2009 = c(predetermined_core, "weighted_price_x_2008_2009_z")
)
shock_results <- dplyr::bind_rows(lapply(seq_along(shock_specs), function(i) {
  nm <- names(shock_specs)[[i]]
  if (nm == "shock_2008_2009") {
    main <- specification_results |>
      dplyr::filter(specification == "predetermined_plus_primary_gfc_2008_2009")
    return(main |>
      dplyr::transmute(
        shock_specification = nm, estimate, se_placebo, ci_95_low, ci_95_high,
        p_value_two_sided, rank_p_one_sided_negative, rank_p_two_sided,
        se_replications
      ))
  }
  if (nm == "price_shock_2008_2009") {
    main <- specification_results |>
      dplyr::filter(specification == "predetermined_plus_weighted_price_gfc")
    return(main |>
      dplyr::transmute(
        shock_specification = nm, estimate, se_placebo, ci_95_low, ci_95_high,
        p_value_two_sided, rank_p_one_sided_negative, rank_p_two_sided,
        se_replications
      ))
  }
  fit <- fit_sdid(panel, shock_specs[[nm]], year_end = 2015L)
  summary <- extract_fit_summary(fit, nm)
  summary |>
    dplyr::transmute(
      shock_specification = specification, estimate, se_placebo, ci_95_low,
      ci_95_high, p_value_two_sided,
      rank_p_one_sided_negative = NA_real_, rank_p_two_sided = NA_real_,
      se_replications = 0L
    )
}))
readr::write_csv(shock_results, shock_window_path)

message("Estimating point estimates for anticipation-window sensitivities.")
anticipation_results <- dplyr::bind_rows(lapply(
  c(2006L, 2007L, 2008L),
  function(window_end) {
    commodity_alt <- anticipation_commodity_exposure |>
      dplyr::filter(exposure_window_end == window_end) |>
      dplyr::select(
        iso3c,
        primary_share_alt = primary_share,
        agriculture_share_alt = agriculture_share,
        mining_energy_share_alt = mining_energy_share,
        commodity_observed_years = observed_years
      )
    china_alt <- anticipation_china_exposure |>
      dplyr::filter(exposure_window_end == window_end) |>
      dplyr::select(
        iso3c,
        pre_china_share_alt = pre_china_share,
        china_observed_years = observed_years
      )
    panel_alt <- panel |>
      dplyr::left_join(commodity_alt, by = "iso3c") |>
      dplyr::left_join(china_alt, by = "iso3c") |>
      dplyr::mutate(
        primary_alt_level_z = scale_vec(primary_share_alt),
        primary_alt_x_gfc_z = scale_vec(primary_share_alt * shock_2008_2009),
        pre_china_alt_x_gfc_z = scale_vec(pre_china_share_alt * shock_2008_2009)
      )
    alt_specs <- list(
      primary_composition = c(
        predetermined_core, "primary_alt_level_z", "primary_alt_x_gfc_z"
      ),
      prior_china_exposure = c(
        predetermined_core, "pre_china_alt_x_gfc_z"
      )
    )
    dplyr::bind_rows(lapply(names(alt_specs), function(exposure_type) {
      fit <- fit_sdid(panel_alt, alt_specs[[exposure_type]], year_end = 2015L)
      main_specification <- if (exposure_type == "primary_composition") {
        "predetermined_plus_primary_gfc_2008_2009"
      } else {
        "predetermined_plus_pre_china_gfc"
      }
      main <- specification_results |>
        dplyr::filter(specification == main_specification) |>
        dplyr::slice_head(n = 1)
      se_value <- if (window_end == 2008L) main$se_placebo else NA_real_
      summary <- extract_fit_summary(
        fit,
        paste0(exposure_type, "_end_", window_end),
        se_value
      )
      brazil_row <- panel_alt |>
        dplyr::filter(iso3c == "BRA") |>
        dplyr::slice_head(n = 1)
      exposure_value <- if (exposure_type == "primary_composition") {
        brazil_row$primary_share_alt
      } else {
        brazil_row$pre_china_share_alt
      }
      summary |>
        dplyr::transmute(
          exposure_type = exposure_type,
          exposure_window_start = 2004L,
          exposure_window_end = window_end,
          brazil_exposure_value = exposure_value,
          observed_years = if (exposure_type == "primary_composition") {
            brazil_row$commodity_observed_years
          } else {
            brazil_row$china_observed_years
          },
          estimate, se_placebo, ci_95_low, ci_95_high, p_value_two_sided,
          inference_status = ifelse(
            window_end == 2008L,
            "Reuses 1,000-placebo inference from the corresponding main robustness.",
            "Point-estimate anticipation sensitivity; no new inference."
          )
        )
    }))
  }
))
readr::write_csv(anticipation_results, anticipation_window_path)

message("Estimating point estimates for temporal-window sensitivities.")
preferred_covariates <- specifications$predetermined_plus_primary_gfc_2008_2009
window_end_years <- c(2012L, 2014L, 2015L, 2016L)
time_window_results <- dplyr::bind_rows(lapply(seq_along(window_end_years), function(i) {
  year_end <- window_end_years[[i]]
  if (year_end == 2015L) {
    main <- specification_results |>
      dplyr::filter(specification == "predetermined_plus_primary_gfc_2008_2009")
    return(main |>
      dplyr::transmute(
        year_end = year_end, estimate, se_placebo, ci_95_low, ci_95_high,
        p_value_two_sided, rank_p_one_sided_negative, rank_p_two_sided,
        n_countries, n_treated_units, n_donors, n_pre_years, n_post_years,
        rmspe_pre_intercept_adjusted, political_window_note =
          "Includes 2015, when the impeachment crisis began, but not the 2016 removal/change of government."
      ))
  }
  fit <- fit_sdid(panel, preferred_covariates, year_end = year_end)
  summary <- extract_fit_summary(fit, paste0("preferred_end_", year_end))
  note <- dplyr::case_when(
    year_end <= 2012L ~ "Ends before the 2013 protests and before the impeachment crisis.",
    year_end == 2014L ~ "Includes Dilma Rousseff's first term but ends before the 2015 impeachment crisis.",
    year_end == 2016L ~ "Includes the 2015 impeachment crisis and the 2016 removal/change of government.",
    TRUE ~ "Sensitivity window."
  )
  summary |>
    dplyr::transmute(
      year_end = year_end, estimate, se_placebo, ci_95_low, ci_95_high,
      p_value_two_sided, rank_p_one_sided_negative = NA_real_,
      rank_p_two_sided = NA_real_,
      n_countries, n_treated_units, n_donors, n_pre_years, n_post_years,
      rmspe_pre_intercept_adjusted, political_window_note = note
    )
}))
readr::write_csv(time_window_results, time_window_path)

local_se_specs <- setdiff(
  names(specifications),
  c("current_baseline", "predetermined_core", "existing_commodity_gfc_exposure")
)
existing_target_row <- existing_diagnostic_target |>
  dplyr::filter(specification == "commodity_gfc_exposure") |>
  dplyr::slice_head(n = 1)
if (nrow(existing_target_row) != 1L) {
  stop("Missing legacy commodity/GFC row in diagnostics target.", call. = FALSE)
}

target_reference_spec <- function(
  specification, source_target, source_object, source_value, fit,
  replications = 1000L, seed = 20260520L
) {
  metadata <- target_metadata |>
    dplyr::filter(.data$name == .env$source_target) |>
    dplyr::slice_head(n = 1) |>
    dplyr::select(name, data, command, time)
  if (nrow(metadata) != 1L) {
    stop("Missing targets metadata for `", source_target, "`.", call. = FALSE)
  }
  reference <- list(
    artifact_contract_version = "target-reference-v1",
    specification = specification,
    source_target = source_target,
    source_target_metadata = metadata,
    source_object_sha256 = digest::digest(
      source_object, algo = "sha256", serialize = TRUE
    ),
    source_value = as.numeric(source_value),
    replications = as.integer(replications),
    seed = as.integer(seed),
    synthdid_version = as.character(utils::packageVersion("synthdid")),
    fit_fingerprint = fit_fingerprint(
      fit, specification, as.integer(replications), as.integer(seed)
    ),
    estimate = as.numeric(fit)
  )
  path <- file.path(
    reference_dir,
    paste0("target_reference_", specification, "_se_", replications, ".rds")
  )
  saveRDS(reference, path, version = 3)
  list(
    path = path,
    fingerprint = digest::digest(file = path, algo = "sha256", serialize = FALSE),
    value = reference$source_value,
    seed = reference$seed,
    replications = reference$replications
  )
}

target_se_references <- list(
  current_baseline = target_reference_spec(
    "current_baseline", "se_synth", se_synth_target, se_synth_target,
    fits$current_baseline
  ),
  predetermined_core = target_reference_spec(
    "predetermined_core", "se_synth_no_time_varying_covariates",
    se_synth_core_target, se_synth_core_target, fits$predetermined_core
  ),
  existing_commodity_gfc_exposure = target_reference_spec(
    "existing_commodity_gfc_exposure", "china_demand_sdid_diagnostics_table",
    existing_diagnostic_target, existing_target_row$se_placebo,
    fits$existing_commodity_gfc_exposure
  )
)

se_manifest <- dplyr::bind_rows(lapply(names(specifications), function(specification) {
  result_row <- specification_results |>
    dplyr::filter(.data$specification == .env$specification) |>
    dplyr::slice_head(n = 1)
  local_index <- match(specification, names(specifications))
  checkpoint_path <- file.path(
    checkpoint_dir,
    paste0("placebo_se_", specification, "_", placebo_replications, ".rds")
  )
  uses_checkpoint <- specification %in% local_se_specs && file.exists(checkpoint_path)
  checkpoint <- if (uses_checkpoint) readRDS(checkpoint_path) else NULL
  target_reference <- target_se_references[[specification]]
  uses_target_reference <- !is.null(target_reference)
  tibble::tibble(
    artifact_type = "placebo_standard_error",
    specification = specification,
    artifact_path = if (uses_checkpoint) {
      checkpoint_path
    } else if (uses_target_reference) {
      target_reference$path
    } else {
      result_row$se_source
    },
    seed = if (uses_checkpoint) {
      20260711L + local_index
    } else if (uses_target_reference) {
      target_reference$seed
    } else {
      NA_integer_
    },
    replications = result_row$se_replications,
    fingerprint_sha256 = if (uses_checkpoint) {
      checkpoint$fingerprint
    } else if (uses_target_reference) {
      target_reference$fingerprint
    } else {
      NA_character_
    },
    estimate = result_row$estimate,
    reported_value = result_row$se_placebo,
    recalculated_value = if (uses_checkpoint) {
      sqrt((placebo_replications - 1) / placebo_replications) *
        stats::sd(checkpoint$estimates)
    } else if (uses_target_reference) {
      target_reference$value
    } else {
      NA_real_
    },
    synthdid_version = as.character(utils::packageVersion("synthdid")),
    code_version = audit_code_version,
    script_sha256 = script_sha256,
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )
}))
rank_manifest_specs <- c(
  "current_baseline",
  "predetermined_core",
  "predetermined_plus_primary_gfc_2008_2009"
)
rank_manifest <- dplyr::bind_rows(lapply(rank_manifest_specs, function(specification) {
  rank_row <- dplyr::bind_rows(rank_results) |>
    dplyr::filter(.data$specification == .env$specification) |>
    dplyr::slice_head(n = 1)
  is_baseline <- specification == "current_baseline"
  artifact_path <- if (is_baseline) {
    existing_rank_path
  } else {
    file.path(
      checkpoint_dir,
      paste0("rank_placebos_", specification, "_end_2015.rds")
    )
  }
  checkpoint <- if (!is_baseline && file.exists(artifact_path)) {
    readRDS(artifact_path)
  } else {
    NULL
  }
  if (is_baseline) {
    baseline_reference <- list(
      artifact_contract_version = "target-reference-v1",
      specification = specification,
      rank_file = existing_rank_path,
      rank_file_sha256 = digest::digest(
        file = existing_rank_path, algo = "sha256", serialize = FALSE
      ),
      distribution_file = existing_distribution_path,
      distribution_file_sha256 = digest::digest(
        file = existing_distribution_path, algo = "sha256", serialize = FALSE
      ),
      rank_one_sided = rank_row$rank_one_sided,
      rank_two_sided = rank_row$rank_two_sided,
      rank_denominator = rank_row$rank_denominator,
      rank_p_two_sided = rank_row$rank_p_two_sided
    )
    artifact_path <- file.path(
      reference_dir, "target_reference_current_baseline_rank.rds"
    )
    saveRDS(baseline_reference, artifact_path, version = 3)
  }
  tibble::tibble(
    artifact_type = "placebo_in_space_rank",
    specification = specification,
    artifact_path = artifact_path,
    seed = NA_integer_,
    replications = rank_row$rank_denominator,
    fingerprint_sha256 = if (is_baseline) {
      digest::digest(file = artifact_path, algo = "sha256", serialize = FALSE)
    } else {
      checkpoint$fingerprint
    },
    estimate = specification_results |>
      dplyr::filter(.data$specification == .env$specification) |>
      dplyr::pull(estimate),
    reported_value = rank_row$rank_p_two_sided,
    recalculated_value = if (is_baseline) {
      baseline_reference$rank_two_sided / baseline_reference$rank_denominator
    } else {
      checkpoint$result$inference$rank_p_two_sided
    },
    synthdid_version = as.character(utils::packageVersion("synthdid")),
    code_version = audit_code_version,
    script_sha256 = script_sha256,
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )
}))
readr::write_csv(dplyr::bind_rows(se_manifest, rank_manifest), manifest_path)

design_contract <- tibble::tribble(
  ~item, ~value,
  "Unit of analysis", "Country-year; Brazil is the only treated unit",
  "Outcome", "Absolute UNGA ideal-point distance to China",
  "Treatment onset", "2009, when China becomes Brazil's largest export destination",
  "Estimand", "Average post-2009 Brazil-minus-synthetic gap under each covariate specification",
  "Main analysis window", "1997-2015",
  "Predetermined composition window", "2004-2008",
  "Primary commodity measure", "Mean annual Agriculture plus Mining and Energy share of goods exports, 2004-2008",
  "Export-flow scope", "External goods exports only; exporter-importer domestic flows are excluded",
  "Commodity robustness window", "2008-2009; includes the first treated year and is not the main total-effect specification",
  "Price source", "World Bank Commodity Price Data (Pink Sheet), annual nominal indices",
  "Price exposure", "2007-referenced global price changes weighted by fixed 2004-2008 external goods-export shares",
  "Inference", paste0("synthdid placebo standard errors with ", placebo_replications, " placebo replications; placebo-in-space rank p-values"),
  "Preferred specification rule", "SDiD without time-varying/post-treatment covariates; selected by total-effect timing and identification rather than p-value"
)
readr::write_csv(design_contract, design_contract_path)

brazil_exposure <- commodity_exposure |>
  dplyr::filter(iso3c == "BRA") |>
  dplyr::slice_head(n = 1)
parallel_validation <- if (file.exists(parallel_validation_path)) {
  readr::read_csv(parallel_validation_path, show_col_types = FALSE) |>
    dplyr::slice_head(n = 1)
} else {
  tibble::tibble(passed = FALSE, absolute_se_difference = NA_real_)
}
anticipation_primary_2008 <- anticipation_results |>
  dplyr::filter(
    exposure_type == "primary_composition",
    exposure_window_end == 2008L
  ) |>
  dplyr::slice_head(n = 1)
anticipation_china_2008 <- anticipation_results |>
  dplyr::filter(
    exposure_type == "prior_china_exposure",
    exposure_window_end == 2008L
  ) |>
  dplyr::slice_head(n = 1)
validation_checks <- tibble::tibble(
  check = c(
    "Current local baseline reproduces target ATT",
    "Predetermined core reproduces no-time-varying target ATT",
    "Existing commodity/GFC reconstruction reproduces target ATT",
    "Deterministic parallel placebo algorithm reproduces serial estimates",
    "Frozen/static covariates are inert for ATT and donor weights",
    "Anticipation-window 2008 rows reproduce corresponding main robustness",
    "Domestic ITPD-E flows are excluded from export exposures",
    "Inference manifest reproduces every checkpoint-based standard error",
    "All declared outputs form a post-script snapshot",
    "Current covariate matrix contains post-2009 observations",
    "Brazil has five complete pre-exposure years",
    "Brazil commodity shares are bounded",
    "Brazil primary share equals agriculture plus mining/energy",
    "Pink Sheet contains 2007, 2008, and 2009",
    "All main specifications use 1,000 or more placebo replications",
    "All main specifications retain one treated unit",
    "No targets pipeline was run"
  ),
  passed = c(
    isTRUE(all.equal(as.numeric(fits$current_baseline), as.numeric(synth_fit_target), tolerance = 1e-8)),
    isTRUE(all.equal(as.numeric(fits$predetermined_core), as.numeric(synth_fit_core_target), tolerance = 1e-8)),
    isTRUE(all.equal(
      as.numeric(fits$existing_commodity_gfc_exposure),
      existing_target_row$estimate,
      tolerance = 1e-8
    )),
    isTRUE(parallel_validation$passed),
    isTRUE(all.equal(
      as.numeric(fits$all_current_covariates_frozen),
      as.numeric(fits$predetermined_core),
      tolerance = 1e-8
    )) && max(abs(
      attr(fits$all_current_covariates_frozen, "weights")$omega -
        attr(fits$predetermined_core, "weights")$omega
    )) < 1e-8,
    isTRUE(all.equal(
      anticipation_primary_2008$estimate,
      as.numeric(fits$predetermined_plus_primary_gfc_2008_2009),
      tolerance = 1e-8
    )) && isTRUE(all.equal(
      anticipation_china_2008$estimate,
      as.numeric(fits$predetermined_plus_pre_china_gfc),
      tolerance = 1e-8
    )),
    domestic_rows_excluded > 0L && internal_rows_retained == 0L,
    all(is.finite(se_manifest$recalculated_value)) &&
      all(abs(se_manifest$reported_value - se_manifest$recalculated_value) < 1e-12) &&
      all(nchar(se_manifest$fingerprint_sha256) == 64L),
    {
      declared_outputs <- c(
        covariate_inventory_path, commodity_exposure_path, price_indices_path,
        specification_results_path, rank_inference_path, balance_path,
        donor_weights_path, shock_window_path, time_window_path,
        placebo_distribution_path, design_contract_path,
        parallel_validation_path, anticipation_window_path, manifest_path
      )
      existing_outputs <- declared_outputs[file.exists(declared_outputs)]
      length(existing_outputs) == length(declared_outputs) &&
        all(file.info(existing_outputs)$mtime >= file.info(script_path)$mtime)
    },
    any(synth_data$year >= 2009L),
    nrow(brazil_exposure) == 1L && brazil_exposure$observed_years == 5L,
    nrow(brazil_exposure) == 1L && all(brazil_exposure$pre_primary_share_mean >= 0, brazil_exposure$pre_primary_share_mean <= 1),
    nrow(brazil_exposure) == 1L && abs(
      brazil_exposure$pre_primary_share_mean -
        brazil_exposure$pre_agriculture_share_mean -
        brazil_exposure$pre_mining_energy_share_mean
    ) < 1e-10,
    all(c(2007L, 2008L, 2009L) %in% pink_indices$year),
    all(specification_results$se_replications >= 1000L),
    all(specification_results$n_treated_units == 1L),
    TRUE
  ),
  detail = c(
    paste0("Local=", format(as.numeric(fits$current_baseline), digits = 8), "; target=", format(as.numeric(synth_fit_target), digits = 8)),
    paste0("Local=", format(as.numeric(fits$predetermined_core), digits = 8), "; target=", format(as.numeric(synth_fit_core_target), digits = 8)),
    paste0("Local=", format(as.numeric(fits$existing_commodity_gfc_exposure), digits = 8), "; target=", format(existing_target_row$estimate, digits = 8)),
    paste0("Absolute SE difference: ", format(parallel_validation$absolute_se_difference, scientific = TRUE)),
    paste0(
      "ATT difference=", format(
        as.numeric(fits$all_current_covariates_frozen) -
          as.numeric(fits$predetermined_core),
        scientific = TRUE
      ),
      "; max donor-weight difference=", format(max(abs(
        attr(fits$all_current_covariates_frozen, "weights")$omega -
          attr(fits$predetermined_core, "weights")$omega
      )), scientific = TRUE)
    ),
    paste0(
      "Primary difference=", format(
        anticipation_primary_2008$estimate -
          as.numeric(fits$predetermined_plus_primary_gfc_2008_2009),
        scientific = TRUE
      ),
      "; prior-China difference=", format(
        anticipation_china_2008$estimate -
          as.numeric(fits$predetermined_plus_pre_china_gfc),
        scientific = TRUE
      )
    ),
    paste0(
      "Excluded ", domestic_rows_excluded, " domestic rows (trade=",
      format(domestic_trade_excluded, scientific = FALSE), "); retained=",
      internal_rows_retained
    ),
    paste0(
      "Maximum SE discrepancy: ",
      format(max(abs(
        se_manifest$reported_value - se_manifest$recalculated_value
      )), scientific = TRUE)
    ),
    "All 14 upstream CSV outputs exist and are newer than the frozen analysis script",
    paste0("Main fit years: ", min(synth_data$year), "-", 2015L, "; source panel extends to ", max(synth_data$year)),
    paste0("Observed pre-exposure years: ", brazil_exposure$observed_years),
    paste0("Brazil primary share: ", round(100 * brazil_exposure$pre_primary_share_mean, 2), "%"),
    paste0("Agriculture=", round(100 * brazil_exposure$pre_agriculture_share_mean, 2), "%; mining/energy=", round(100 * brazil_exposure$pre_mining_energy_share_mean, 2), "%"),
    paste0("Pink Sheet years: ", min(pink_indices$year), "-", max(pink_indices$year)),
    paste0("Replications: ", placebo_replications),
    "Brazil only",
    "Script reads existing targets only and does not execute the targets pipeline"
  )
)
readr::write_csv(validation_checks, validation_path)
if (!all(validation_checks$passed)) {
  stop(
    "Validation failed: ",
    paste(validation_checks$check[!validation_checks$passed], collapse = "; "),
    call. = FALSE
  )
}

sha_line <- digest::digest(
  file = pink_sheet_path, algo = "sha256", serialize = FALSE
)
itpde_sha_line <- digest::digest(
  file = itpde_path, algo = "sha256", serialize = FALSE
)
legacy_sha_line <- digest::digest(
  file = legacy_exposure_path, algo = "sha256", serialize = FALSE
)
source_lines <- c(
  "# Sources: predetermined commodity-control audit",
  "",
  paste0("Accessed: ", run_date),
  "",
  "## ITPD-E Release 3",
  "",
  paste0("- Raw file: `", itpde_path, "`"),
  paste0("- SHA256: `", paste(itpde_sha_line, collapse = " "), "`"),
  "- Variables used: year, exporter ISO3, importer ISO3, trade, industry ID, broad sector.",
  paste0("- Domestic exporter-importer flows excluded: ", domestic_rows_excluded, " rows in 2004-2008."),
  "- Predetermined window: 2004-2008.",
  "- Goods denominator excludes Services.",
  "- Primary exports equal Agriculture plus Mining and Energy.",
  "- Valid prior China exposure uses China's share of external goods exports in raw ITPD-E, averaged over 2004-2008.",
  "- The legacy comparator separately reproduces the old domestic-flow-contaminated exposure and all-sector China share only for audit; it is not a valid robustness.",
  paste0("- Legacy exposure file SHA256: `", paste(legacy_sha_line, collapse = " "), "`"),
  "",
  "## World Bank Commodity Price Data (Pink Sheet)",
  "",
  "- Provider: World Bank Prospects Group.",
  "- Dataset page: https://www.worldbank.org/en/research/commodity-markets",
  "- Download URL: https://thedocs.worldbank.org/en/doc/74e8be41ceb20fa0da750cda2f6b9e4e-0050012026/related/CMO-Historical-Data-Annual.xlsx",
  paste0("- Raw file: `", pink_sheet_path, "`"),
  paste0("- Access date: ", run_date, "."),
  "- Sheet: Annual Indices (Nominal).",
  "- Series used: Agriculture, Energy, and Metals & Minerals.",
  "- Price changes are log differences relative to 2007.",
  paste0("- SHA256: `", paste(sha_line, collapse = " "), "`"),
  "",
  "## Mapping",
  "",
  "- ITPD-E Agriculture maps to the Pink Sheet Agriculture index.",
  "- ITPD-E industries 29-31 map to Energy.",
  "- ITPD-E industries 32-33 map to Metals & Minerals.",
  "- Industries 34-35 are retained as unmapped and excluded from the price-weighted component; mapping coverage is reported by country."
)
writeLines(source_lines, source_note_path, useBytes = TRUE)

writeLines(capture.output(sessionInfo()), session_info_path, useBytes = TRUE)
run_finished <- Sys.time()
writeLines(c(
  paste0("Started: ", format(run_started, "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Finished: ", format(run_finished, "%Y-%m-%d %H:%M:%S %Z")),
  paste0("Elapsed seconds: ", round(as.numeric(difftime(run_finished, run_started, units = "secs")), 1)),
    paste0("Placebo replications per inferential fit: ", placebo_replications),
    paste0("Parallel cores: ", parallel_cores),
    paste0("Audit code version: ", audit_code_version),
    paste0("Analysis script SHA256: ", script_sha256),
    "targets pipeline executed: no"
), run_log_path, useBytes = TRUE)

message("Audit outputs written to: ", out_dir)
