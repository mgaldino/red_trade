# Candidate functions for migrating the Brazil SDiD paper outputs and the
# commodity/Table 5 robustness block into targets. These functions do not read
# the targets store and do not access the network.

sdid_migration_current_covariates <- function() {
  c(
    "gpi", "perc_trade_with_us", "perc_trade_with_china", "pci_cur",
    "exachange_rate", "distance_us", "us_power_gap", "hog_left", "CA_GDP",
    "govdef_GDP", "inst_parliamentary", "inst_military_exec",
    "us_trade_agreement"
  )
}

sdid_migration_scale_vec <- function(x) {
  if (all(is.na(x))) {
    return(rep(NA_real_, length(x)))
  }
  scale_sd <- stats::sd(x, na.rm = TRUE)
  if (is.na(scale_sd) || scale_sd == 0) {
    return(rep(0, length(x)))
  }
  as.numeric((x - mean(x, na.rm = TRUE)) / scale_sd)
}

validate_sdid_commodity_share_bounds <- function(exposure,
                                                 tolerance = 1e-12) {
  share_columns <- grep("share|coverage", names(exposure), value = TRUE)
  share_values <- unlist(exposure[share_columns], use.names = FALSE)
  if (any(!is.finite(share_values[!is.na(share_values)])) ||
      any(
        share_values < -tolerance | share_values > 1 + tolerance,
        na.rm = TRUE
      )) {
    stop(
      "Commodity shares must be finite and lie in [0, 1] within tolerance.",
      call. = FALSE
    )
  }
  invisible(exposure)
}

build_sdid_commodity_exposure_from_itpde <- function(
    itpd_path,
    start_year = 2004L,
    end_year = 2008L) {
  if (!file.exists(itpd_path)) {
    stop("ITPD-E file not found: ", itpd_path, call. = FALSE)
  }
  if (start_year > end_year) {
    stop("start_year must not exceed end_year.", call. = FALSE)
  }

  duckdb_path <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = duckdb_path)
  on.exit({
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    unlink(c(duckdb_path, paste0(duckdb_path, ".wal")))
  }, add = TRUE)
  itpd_sql <- as.character(DBI::dbQuoteString(
    con,
    normalizePath(itpd_path, mustWork = TRUE)
  ))
  source_sql <- paste0(
    "read_csv_auto(", itpd_sql,
    ", header = true, all_varchar = true, ignore_errors = false)"
  )

  # Keep the aggregation deterministic and scan the 7.8 GB source only once.
  # The materialized temporary table contains only the five-year window and
  # only the columns needed by the commodity construction.
  DBI::dbExecute(con, "PRAGMA threads = 1")
  DBI::dbExecute(con, paste0(
    "CREATE TEMP TABLE sdid_commodity_window AS ",
    "SELECT upper(exporter_iso3) AS exporter_iso3, ",
    "upper(importer_iso3) AS importer_iso3, ",
    "try_cast(year AS INTEGER) AS year, ",
    "broad_sector, try_cast(industry_id AS INTEGER) AS industry_id, ",
    "try_cast(trade AS DOUBLE) AS trade ",
    "FROM ", source_sql, " ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year,
    " AND ", end_year
  ))

  parse_audit <- DBI::dbGetQuery(con, paste0(
    "SELECT ",
    "count(*) AS rows_in_window, ",
    "sum(CASE WHEN trade IS NULL THEN 1 ELSE 0 END) ",
    "AS missing_or_parse_fail_trade, ",
    "sum(CASE WHEN exporter_iso3 = importer_iso3 THEN 1 ELSE 0 END) ",
    "AS domestic_rows_excluded, ",
    "sum(CASE WHEN exporter_iso3 = importer_iso3 ",
    "THEN coalesce(trade, 0) ELSE 0 END) ",
    "AS domestic_trade_excluded ",
    "FROM sdid_commodity_window"
  )) |>
    tibble::as_tibble()
  if (parse_audit$missing_or_parse_fail_trade[[1]] > 0L) {
    stop(
      "ITPD-E contains missing or unparseable trade values in the commodity window.",
      call. = FALSE
    )
  }

  yearly <- DBI::dbGetQuery(con, paste0(
    "SELECT exporter_iso3 AS iso3c, year, ",
    "sum(CASE WHEN broad_sector <> 'Services' THEN trade ELSE 0 END) AS goods_exports, ",
    "sum(CASE WHEN broad_sector = 'Agriculture' THEN trade ELSE 0 END) AS agriculture_exports, ",
    "sum(CASE WHEN broad_sector = 'Mining and Energy' THEN trade ELSE 0 END) AS mining_energy_exports, ",
    "sum(CASE WHEN broad_sector <> 'Services' AND importer_iso3 = 'CHN' ",
    "THEN trade ELSE 0 END) AS china_goods_exports, ",
    "sum(CASE WHEN industry_id IN (29, 30, 31) ",
    "THEN trade ELSE 0 END) AS energy_mapped_exports, ",
    "sum(CASE WHEN industry_id IN (32, 33) ",
    "THEN trade ELSE 0 END) AS metals_mapped_exports, ",
    "sum(CASE WHEN industry_id IN (34, 35) ",
    "THEN trade ELSE 0 END) AS mining_unmapped_exports ",
    "FROM sdid_commodity_window ",
    "WHERE exporter_iso3 IS NOT NULL AND importer_iso3 IS NOT NULL ",
    "AND exporter_iso3 <> importer_iso3 ",
    "GROUP BY 1, 2 ORDER BY 1, 2"
  )) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      year = as.integer(year),
      primary_exports = agriculture_exports + mining_energy_exports,
      china_goods_share = dplyr::if_else(
        goods_exports > 0,
        china_goods_exports / goods_exports,
        NA_real_
      ),
      primary_share = dplyr::if_else(
        goods_exports > 0,
        primary_exports / goods_exports,
        NA_real_
      ),
      agriculture_share = dplyr::if_else(
        goods_exports > 0,
        agriculture_exports / goods_exports,
        NA_real_
      ),
      mining_energy_share = dplyr::if_else(
        goods_exports > 0,
        mining_energy_exports / goods_exports,
        NA_real_
      ),
      energy_mapped_share = dplyr::if_else(
        goods_exports > 0,
        energy_mapped_exports / goods_exports,
        NA_real_
      ),
      metals_mapped_share = dplyr::if_else(
        goods_exports > 0,
        metals_mapped_exports / goods_exports,
        NA_real_
      ),
      mining_unmapped_share = dplyr::if_else(
        goods_exports > 0,
        mining_unmapped_exports / goods_exports,
        NA_real_
      )
    )
  abort_if_duplicate_keys(
    yearly,
    c("iso3c", "year"),
    "candidate commodity exposure by country-year"
  )

  exposure <- yearly |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      pre_window_start = start_year,
      pre_window_end = end_year,
      observed_years = dplyr::n_distinct(year),
      pre_primary_share_mean = mean(primary_share, na.rm = TRUE),
      pre_agriculture_share_mean = mean(agriculture_share, na.rm = TRUE),
      pre_mining_energy_share_mean = mean(mining_energy_share, na.rm = TRUE),
      pre_energy_mapped_share_mean = mean(energy_mapped_share, na.rm = TRUE),
      pre_metals_mapped_share_mean = mean(metals_mapped_share, na.rm = TRUE),
      pre_mining_unmapped_share_mean = mean(mining_unmapped_share, na.rm = TRUE),
      pre_china_goods_share_mean = mean(china_goods_share, na.rm = TRUE),
      pre_primary_share_pooled = sum(primary_exports, na.rm = TRUE) /
        sum(goods_exports, na.rm = TRUE),
      pre_agriculture_share_pooled = sum(agriculture_exports, na.rm = TRUE) /
        sum(goods_exports, na.rm = TRUE),
      pre_mining_energy_share_pooled = sum(mining_energy_exports, na.rm = TRUE) /
        sum(goods_exports, na.rm = TRUE),
      pre_goods_exports = sum(goods_exports, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      price_mapping_coverage = dplyr::if_else(
        pre_primary_share_mean > 0,
        (
          pre_agriculture_share_mean +
            pre_energy_mapped_share_mean +
            pre_metals_mapped_share_mean
        ) / pre_primary_share_mean,
        NA_real_
      ),
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name"
      )
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      pre_window_start,
      pre_window_end,
      observed_years,
      pre_primary_share_mean,
      pre_agriculture_share_mean,
      pre_mining_energy_share_mean,
      pre_energy_mapped_share_mean,
      pre_metals_mapped_share_mean,
      pre_mining_unmapped_share_mean,
      pre_china_goods_share_mean,
      price_mapping_coverage,
      pre_primary_share_pooled,
      pre_agriculture_share_pooled,
      pre_mining_energy_share_pooled,
      pre_goods_exports
    ) |>
    dplyr::arrange(iso3c)
  abort_if_duplicate_keys(
    exposure,
    "iso3c",
    "candidate pre-2009 commodity exposure"
  )

  validate_sdid_commodity_share_bounds(exposure)

  list(
    exposure = exposure,
    yearly = yearly,
    audit = parse_audit
  )
}

read_sdid_pink_sheet_indices <- function(pink_sheet_path,
                                         start_year = 1997L,
                                         end_year = 2016L,
                                         base_year = 2007L) {
  if (!file.exists(pink_sheet_path)) {
    stop("Pink Sheet file not found: ", pink_sheet_path, call. = FALSE)
  }
  raw <- readxl::read_excel(
    pink_sheet_path,
    sheet = "Annual Indices (Nominal)",
    skip = 9,
    col_names = FALSE
  )
  raw_names <- names(raw)
  if (length(raw_names) < 15L) {
    stop("Pink Sheet annual-index sheet has fewer than 15 columns.", call. = FALSE)
  }
  indices <- raw |>
    dplyr::transmute(
      year = suppressWarnings(as.integer(.data[[raw_names[[1]]]])),
      energy_index = suppressWarnings(as.numeric(.data[[raw_names[[3]]]])),
      agriculture_index = suppressWarnings(as.numeric(.data[[raw_names[[5]]]])),
      metals_minerals_index = suppressWarnings(as.numeric(.data[[raw_names[[15]]]]))
    ) |>
    dplyr::filter(!is.na(year), year >= start_year, year <= end_year)
  abort_if_duplicate_keys(indices, "year", "candidate Pink Sheet indices")
  if (anyNA(indices) ||
      any(!is.finite(unlist(indices[-1], use.names = FALSE))) ||
      any(unlist(indices[-1], use.names = FALSE) <= 0)) {
    stop("Pink Sheet indices must be complete, finite, and positive.", call. = FALSE)
  }

  base <- indices |>
    dplyr::filter(year == base_year)
  if (nrow(base) != 1L) {
    stop("Pink Sheet base year is unavailable or duplicated.", call. = FALSE)
  }
  indices <- indices |>
    dplyr::mutate(
      energy_log_change_2007 = log(energy_index / base$energy_index),
      agriculture_log_change_2007 = log(
        agriculture_index / base$agriculture_index
      ),
      metals_minerals_log_change_2007 = log(
        metals_minerals_index / base$metals_minerals_index
      )
    ) |>
    dplyr::select(
      year,
      energy_index,
      agriculture_index,
      metals_minerals_index,
      energy_log_change_2007,
      agriculture_log_change_2007,
      metals_minerals_log_change_2007
    ) |>
    dplyr::arrange(year)
  base_log_values <- indices |>
    dplyr::filter(year == base_year) |>
    dplyr::select(dplyr::ends_with("_log_change_2007")) |>
    unlist(use.names = FALSE)
  if (!all(base_log_values == 0)) {
    stop("Pink Sheet log changes must equal zero in the base year.", call. = FALSE)
  }
  indices
}

compare_sdid_candidate_frame <- function(candidate,
                                         reference_file,
                                         keys,
                                         label,
                                         tolerance = 1e-12) {
  if (!file.exists(reference_file)) {
    stop("Reference file not found: ", reference_file, call. = FALSE)
  }
  reference <- readr::read_csv(reference_file, show_col_types = FALSE)
  common <- intersect(names(reference), names(candidate))
  same_columns <- identical(names(candidate), names(reference))
  candidate_sorted <- candidate |>
    dplyr::arrange(dplyr::across(dplyr::all_of(keys)))
  reference_sorted <- reference |>
    dplyr::arrange(dplyr::across(dplyr::all_of(keys)))
  normalize_csv_text <- function(value) {
    value <- as.character(value)
    value[is.na(value) | value == ""] <- NA_character_
    value
  }
  compare_key <- function(column) {
    candidate_value <- candidate_sorted[[column]]
    reference_value <- reference_sorted[[column]]
    if (is.numeric(candidate_value) && is.numeric(reference_value)) {
      if (!identical(is.na(candidate_value), is.na(reference_value)) ||
          any(!is.finite(candidate_value[!is.na(candidate_value)])) ||
          any(!is.finite(reference_value[!is.na(reference_value)]))) {
        return(FALSE)
      }
      return(identical(
        as.numeric(candidate_value),
        as.numeric(reference_value)
      ))
    }
    identical(
      normalize_csv_text(candidate_value),
      normalize_csv_text(reference_value)
    )
  }
  same_keys <- nrow(candidate_sorted) == nrow(reference_sorted) &&
    all(vapply(keys, compare_key, logical(1)))

  numeric_columns <- common[
    vapply(candidate[common], is.numeric, logical(1)) &
      vapply(reference[common], is.numeric, logical(1))
  ]
  numeric_equal <- same_keys
  max_abs_diff <- 0
  if (same_keys && length(numeric_columns) > 0L) {
    for (column in numeric_columns) {
      candidate_value <- candidate_sorted[[column]]
      reference_value <- reference_sorted[[column]]
      if (!identical(is.na(candidate_value), is.na(reference_value))) {
        numeric_equal <- FALSE
        max_abs_diff <- Inf
        break
      }
      if (any(is.nan(candidate_value)) || any(is.nan(reference_value)) ||
          any(is.infinite(candidate_value)) ||
          any(is.infinite(reference_value))) {
        numeric_equal <- FALSE
        max_abs_diff <- Inf
        break
      }
      comparable <- !is.na(candidate_value)
      differences <- abs(
        candidate_value[comparable] - reference_value[comparable]
      )
      column_max <- if (length(differences) == 0L) 0 else max(differences)
      max_abs_diff <- max(max_abs_diff, column_max)
      scale <- pmax(
        abs(candidate_value[comparable]),
        abs(reference_value[comparable])
      )
      allowed <- tolerance + tolerance * scale
      numeric_equal <- numeric_equal && all(differences <= allowed)
    }
  }

  nonnumeric_columns <- setdiff(common, numeric_columns)
  nonnumeric_equal <- same_keys && all(vapply(
    nonnumeric_columns,
    function(column) {
      identical(
        normalize_csv_text(candidate_sorted[[column]]),
        normalize_csv_text(reference_sorted[[column]])
      )
    },
    logical(1)
  ))

  tibble::tibble(
    validation = c(
      paste0(label, "_same_columns"),
      paste0(label, "_same_keys"),
      paste0(label, "_numeric_equal"),
      paste0(label, "_nonnumeric_equal")
    ),
    passed = c(same_columns, same_keys, numeric_equal, nonnumeric_equal),
    detail = c(
      paste(names(candidate), collapse = ";"),
      paste0("candidate=", nrow(candidate), "; reference=", nrow(reference)),
      paste0("max_abs_diff=", format(max_abs_diff, digits = 17)),
      paste0("columns=", paste(nonnumeric_columns, collapse = ";"))
    )
  )
}

validate_sdid_commodity_derivations <- function(
    exposure,
    prices,
    reference_exposure_file,
    reference_price_file,
    tolerance = 1e-12) {
  dplyr::bind_rows(
    compare_sdid_candidate_frame(
      exposure,
      reference_exposure_file,
      "iso3c",
      "commodity_exposure",
      tolerance
    ),
    compare_sdid_candidate_frame(
      prices,
      reference_price_file,
      "year",
      "pink_sheet_indices",
      tolerance
    ),
    tibble::tibble(
      validation = c(
        "commodity_exposure_unique_iso3c",
        "commodity_exposure_window_2004_2008",
        "commodity_exposure_five_observed_years",
        "pink_sheet_window_1997_2016",
        "pink_sheet_2007_log_changes_zero"
      ),
      passed = c(
        anyDuplicated(exposure$iso3c) == 0L,
        all(exposure$pre_window_start == 2004L) &&
          all(exposure$pre_window_end == 2008L),
        all(exposure$observed_years == 5L),
        identical(prices$year, 1997:2016),
        all(
          unlist(
            prices[prices$year == 2007L, grep("_log_change_2007", names(prices))],
            use.names = FALSE
          ) == 0
        )
      ),
      detail = c(
        paste0("rows=", nrow(exposure)),
        "expected 2004-2008",
        paste(sort(unique(exposure$observed_years)), collapse = ";"),
        paste0(min(prices$year), "-", max(prices$year)),
        "expected all zero"
      )
    )
  )
}

assert_sdid_migration_validation <- function(validation) {
  if (!is.data.frame(validation) ||
      !all(c("validation", "passed") %in% names(validation)) ||
      !is.logical(validation$passed)) {
    stop("SDiD migration validation has an invalid schema.", call. = FALSE)
  }
  failed <- validation |>
    dplyr::filter(!(.data$passed %in% TRUE)) |>
    dplyr::pull(validation)
  if (length(failed) > 0L) {
    stop(
      "SDiD migration validation failed: ",
      paste(failed, collapse = ", "),
      call. = FALSE
    )
  }
  validation
}

build_sdid_commodity_panel_candidate <- function(synth_data,
                                                 exposure,
                                                 prices) {
  current_covariates <- sdid_migration_current_covariates()
  missing_covariates <- setdiff(current_covariates, names(synth_data))
  if (length(missing_covariates) > 0L) {
    stop(
      "Missing current SDiD covariates: ",
      paste(missing_covariates, collapse = ", "),
      call. = FALSE
    )
  }

  panel <- synth_data |>
    dplyr::left_join(
      exposure |>
        dplyr::select(
          iso3c,
          pre_primary_share_mean,
          pre_agriculture_share_mean,
          pre_mining_energy_share_mean,
          pre_energy_mapped_share_mean,
          pre_metals_mapped_share_mean,
          pre_china_goods_share_mean
        ),
      by = "iso3c",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      prices |>
        dplyr::select(
          year,
          energy_log_change_2007,
          agriculture_log_change_2007,
          metals_minerals_log_change_2007
        ),
      by = "year",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      shock_2008_2009 = as.integer(year %in% 2008:2009),
      primary_x_2008_2009_z = sdid_migration_scale_vec(
        pre_primary_share_mean * shock_2008_2009
      ),
      agriculture_x_2008_2009_z = sdid_migration_scale_vec(
        pre_agriculture_share_mean * shock_2008_2009
      ),
      mining_energy_x_2008_2009_z = sdid_migration_scale_vec(
        pre_mining_energy_share_mean * shock_2008_2009
      ),
      weighted_price_log_change_2007 =
        pre_agriculture_share_mean * agriculture_log_change_2007 +
        pre_energy_mapped_share_mean * energy_log_change_2007 +
        pre_metals_mapped_share_mean * metals_minerals_log_change_2007,
      weighted_price_x_2008_2009_z = sdid_migration_scale_vec(
        weighted_price_log_change_2007 * shock_2008_2009
      ),
      pre_china_x_2008_2009_z = sdid_migration_scale_vec(
        pre_china_goods_share_mean * shock_2008_2009
      )
    ) |>
    dplyr::arrange(iso3c, year)
  abort_if_duplicate_keys(
    panel,
    c("iso3c", "year"),
    "candidate SDiD commodity panel"
  )
  panel
}

sdid_commodity_specification_columns <- function(specification) {
  specifications <- list(
    current_baseline = sdid_migration_current_covariates(),
    no_covariates = character(0),
    primary_gfc_2008_2009 = "primary_x_2008_2009_z",
    agriculture_mining_gfc = c(
      "agriculture_x_2008_2009_z",
      "mining_energy_x_2008_2009_z"
    ),
    weighted_price_gfc = "weighted_price_x_2008_2009_z",
    pre_china_gfc = "pre_china_x_2008_2009_z"
  )
  if (!specification %in% names(specifications)) {
    stop("Unknown commodity specification: ", specification, call. = FALSE)
  }
  specifications[[specification]]
}

fit_sdid_commodity_specification_candidate <- function(panel, specification) {
  covariates <- sdid_commodity_specification_columns(specification)
  required <- c("iso3c", "year", "abs_distance_china", covariates)
  analysis <- panel |>
    dplyr::filter(year >= 1997L, year <= 2015L)
  if (anyNA(analysis |>
            dplyr::select(dplyr::all_of(required)))) {
    stop(
      "Missing analysis values for commodity specification ",
      specification,
      call. = FALSE
    )
  }
  sdid_fit_spec(panel, covariate_cols = covariates)
}

sdid_candidate_checkpoint_directory <- function(block) {
  path <- file.path(
    "data", "processed", "targets_migration", "checkpoints", block
  )
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(path)) {
    stop("Could not create SDiD candidate checkpoint directory: ", path,
         call. = FALSE)
  }
  path
}

sdid_candidate_parallel_cores <- function(cap = 12L) {
  # This must happen in the target process immediately before any fork.
  sdid_limit_blas_threads()
  sdid_available_cores(cap = cap)
}

run_sdid_rank_distribution_candidate <- function(
    data,
    covariate_cols = character(0),
    label,
    checkpoint_block,
    year_start = 1997L,
    year_end = 2015L,
    treat_year = 2009L,
    core_cap = 12L) {
  checkpoint_dir <- sdid_candidate_checkpoint_directory(checkpoint_block)
  sdid_rank_distribution(
    data,
    covariate_cols = covariate_cols,
    label = label,
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year,
    cores = sdid_candidate_parallel_cores(core_cap),
    checkpoint_dir = checkpoint_dir
  )
}

run_sdid_placebo_se_candidate <- function(
    fit,
    replications,
    label,
    checkpoint_block,
    seed = SDID_PLACEBO_SEED,
    core_cap = 12L) {
  checkpoint_dir <- sdid_candidate_checkpoint_directory(checkpoint_block)
  sdid_placebo_se(
    fit,
    replications = replications,
    seed = seed,
    cores = sdid_candidate_parallel_cores(core_cap),
    checkpoint_dir = checkpoint_dir,
    label = label
  )
}

compute_sdid_comparison_se_candidate <- function(fit,
                                                 specification,
                                                 replications = 5000L,
                                                 seed = SDID_PLACEBO_SEED,
                                                 checkpoint_block =
                                                   "commodity_table_5",
                                                 core_cap = 12L) {
  if (replications < 1000L) {
    stop("Final candidate SE requires at least 1,000 replications.", call. = FALSE)
  }
  se <- run_sdid_placebo_se_candidate(
    fit,
    replications = replications,
    label = specification,
    checkpoint_block = checkpoint_block,
    seed = seed,
    core_cap = core_cap
  )
  list(
    se = as.numeric(se),
    replications = as.integer(replications),
    seed = as.integer(seed),
    source = "Locally computed placebo SE (common random numbers across rows)."
  )
}

reuse_sdid_preferred_se_candidate <- function(fit,
                                              target_fit,
                                              target_se,
                                              replications = 20000L,
                                              checkpoint_block =
                                                "paper_sdid_preferred") {
  checkpoint_dir <- sdid_candidate_checkpoint_directory(checkpoint_block)
  sdid_limit_blas_threads()
  sdid_preferred_se(
    fit,
    target_fit,
    target_se,
    target_replications = replications,
    cores = 1L,
    checkpoint_dir = checkpoint_dir,
    label = "no_covariates"
  )
}

sdid_commodity_specification_metadata <- function() {
  tibble::tribble(
    ~specification, ~label, ~role, ~identification_rationale,
    "current_baseline", "Current covariates", "comparison",
    "Time-varying covariate matrix, including post-2009 observations.",
    "no_covariates", "Preferred: no covariates", "preferred main specification",
    "Counterfactual from pre-treatment outcomes and SDiD unit and time weights only.",
    "primary_gfc_2008_2009", "Primary share x 2008-2009", "commodity mechanism robustness",
    "Time-varying exposure interaction; includes the first treated year and may absorb part of the mechanism.",
    "agriculture_mining_gfc", "Agriculture/mining x 2008-2009", "decomposition robustness",
    "Separates Agriculture and Mining and Energy exposure interactions.",
    "weighted_price_gfc", "Price exposure x 2008-2009", "price-shock robustness",
    "Global commodity price changes from 2007 weighted by 2004-2008 export composition.",
    "pre_china_gfc", "Prior China share x 2008-2009", "China-demand robustness",
    "Mean 2004-2008 China goods-export share interacted with the common shock window."
  )
}

build_sdid_commodity_table_candidate <- function(
    fits,
    se_information,
    preferred_rank_distribution,
    primary_rank_distribution) {
  specification_order <- c(
    "current_baseline",
    "no_covariates",
    "primary_gfc_2008_2009",
    "agriculture_mining_gfc",
    "weighted_price_gfc",
    "pre_china_gfc"
  )
  if (!identical(names(fits), specification_order) ||
      !identical(names(se_information), specification_order)) {
    stop("Commodity fit and SE lists must follow the frozen specification order.",
         call. = FALSE)
  }

  rank_rows <- list(
    no_covariates = sdid_rank_inference(
      preferred_rank_distribution,
      "no_covariates"
    ),
    primary_gfc_2008_2009 = sdid_rank_inference(
      primary_rank_distribution,
      "primary_gfc_2008_2009"
    )
  )
  results <- lapply(specification_order, function(specification) {
    fit <- fits[[specification]]
    se_info <- se_information[[specification]]
    rank <- rank_rows[[specification]]
    rank_values <- if (is.null(rank)) {
      tibble::tibble(
        rank_one_sided = NA_integer_,
        rank_two_sided = NA_integer_,
        rank_denominator = NA_integer_,
        rank_p_one_sided_negative = NA_real_,
        rank_p_two_sided = NA_real_,
        rank_inference_status = paste0(
          "Not recomputed: rank inference is reported for the preferred ",
          "specification and the pre-specified commodity robustness."
        )
      )
    } else {
      tibble::tibble(
        rank_one_sided = rank$rank_one_sided_negative,
        rank_two_sided = rank$rank_two_sided_absolute,
        rank_denominator = rank$denominator,
        rank_p_one_sided_negative = rank$p_rank_one_sided_negative,
        rank_p_two_sided = rank$p_rank_two_sided_absolute,
        rank_inference_status = "Locally recomputed placebo-in-space ranks."
      )
    }
    sdid_fit_summary_row(fit, specification, se_info$se) |>
      dplyr::mutate(
        se_replications = se_info$replications,
        se_seed = se_info$seed,
        se_source = se_info$source
      ) |>
      dplyr::bind_cols(rank_values)
  })

  legacy_keys <- c(
    current_baseline = "current_baseline",
    no_covariates = "predetermined_core",
    primary_gfc_2008_2009 = "predetermined_plus_primary_gfc_2008_2009",
    agriculture_mining_gfc = "predetermined_plus_agriculture_mining_gfc",
    weighted_price_gfc = "predetermined_plus_weighted_price_gfc",
    pre_china_gfc = "predetermined_plus_pre_china_gfc"
  )
  dplyr::bind_rows(results) |>
    dplyr::rename(
      p_value_two_sided = p_normal_two_sided,
      rmspe_pre_intercept_adjusted = rmspe_pre
    ) |>
    dplyr::left_join(
      sdid_commodity_specification_metadata(),
      by = "specification",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      preferred_by_identification = specification == "no_covariates",
      legacy_specification = unname(legacy_keys[specification]),
      se_method = "synthdid placebo",
      smoke_test = FALSE
    ) |>
    dplyr::select(
      specification,
      legacy_specification,
      label,
      role,
      preferred_by_identification,
      identification_rationale,
      estimate,
      se_placebo,
      ci_95_low,
      ci_95_high,
      p_value_two_sided,
      rank_p_one_sided_negative,
      rank_p_two_sided,
      rank_one_sided,
      rank_two_sided,
      rank_denominator,
      dplyr::everything()
    )
}

build_paper_sdid_unit_weights_candidate <- function(fit, synth_data) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  donors <- rownames(setup$Y)[seq_len(setup$N0)]
  latam <- synth_data |>
    dplyr::distinct(iso3c, latin_america)
  unit_weights <- tibble::tibble(
    iso3c = donors,
    unit_weight = as.numeric(weights$omega)
  ) |>
    dplyr::arrange(dplyr::desc(unit_weight)) |>
    dplyr::mutate(
      weight_rank = dplyr::row_number(),
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name"
      ),
      region = countrycode::countrycode(iso3c, "iso3c", "region"),
      cumulative_weight = cumsum(unit_weight),
      uniform_weight = 1 / length(donors),
      high_weight_donor = weight_rank <= 10L
    ) |>
    dplyr::left_join(latam, by = "iso3c", relationship = "many-to-one") |>
    dplyr::select(
      weight_rank,
      iso3c,
      country_name,
      region,
      latin_america,
      unit_weight,
      cumulative_weight,
      uniform_weight,
      high_weight_donor
    )
  if (abs(sum(unit_weights$unit_weight) - 1) >= 1e-10) {
    stop("Candidate donor weights do not sum to one.", call. = FALSE)
  }
  if (!"SGP" %in% unit_weights$iso3c || "MLT" %in% unit_weights$iso3c) {
    stop("Candidate donor pool must include SGP and exclude MLT.", call. = FALSE)
  }
  unit_weights
}

build_paper_sdid_time_weights_candidate <- function(fit) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  tibble::tibble(
    year = as.integer(colnames(setup$Y)[seq_len(setup$T0)]),
    time_weight = as.numeric(weights$lambda)
  ) |>
    dplyr::mutate(
      time_weight_rank = rank(-time_weight, ties.method = "min"),
      high_time_weight = time_weight >= 0.1
    )
}

build_paper_sdid_balance_candidate <- function(synth_data,
                                               fit,
                                               unit_weights) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  donors <- rownames(setup$Y)[seq_len(setup$N0)]
  pre <- synth_data |>
    dplyr::filter(year >= 1997L, year <= 2008L)
  balance_one <- function(variable, label, role, definition) {
    donor_values <- pre |>
      dplyr::filter(iso3c != "BRA") |>
      dplyr::group_by(iso3c) |>
      dplyr::summarise(value = mean(.data[[variable]], na.rm = TRUE),
                       .groups = "drop")
    donor_values <- donor_values[match(donors, donor_values$iso3c), ]
    brazil_value <- pre |>
      dplyr::filter(iso3c == "BRA") |>
      dplyr::summarise(value = mean(.data[[variable]], na.rm = TRUE)) |>
      dplyr::pull(value)
    synthetic_value <- sum(as.numeric(weights$omega) * donor_values$value)
    donor_sd <- stats::sd(donor_values$value)
    tibble::tibble(
      variable = variable,
      label = label,
      role = role,
      brazil_pre_mean = brazil_value,
      synthetic_pre_mean = synthetic_value,
      brazil_minus_synthetic = brazil_value - synthetic_value,
      standardized_difference = (brazil_value - synthetic_value) /
        ifelse(donor_sd > 0, donor_sd, NA_real_),
      included_in_preferred_specification = variable == "abs_distance_china",
      value_definition = definition,
      diagnostic_scope = paste0(
        "Omega-weighted pre-treatment values; descriptive. The preferred ",
        "specification uses no covariates, so only the outcome enters ",
        "estimation."
      )
    )
  }
  dplyr::bind_rows(
    balance_one(
      "abs_distance_china",
      "Absolute UNGA ideal-point distance to China",
      "Outcome",
      "1997-2008 mean"
    ),
    balance_one(
      "perc_trade_with_china",
      "Export share to China",
      "Descriptive covariate",
      "1997-2008 mean"
    ),
    balance_one(
      "perc_trade_with_us",
      "Export share to the United States",
      "Descriptive covariate",
      "1997-2008 mean"
    ),
    balance_one(
      "pci_cur",
      "Per-capita income",
      "Descriptive covariate",
      "1997-2008 mean"
    ),
    balance_one(
      "gpi",
      "Power index",
      "Descriptive covariate",
      "1997-2008 mean"
    )
  )
}

build_paper_sdid_rank_inference_candidate <- function(distribution) {
  brazil_rmspe <- distribution$rmspe_pre[distribution$iso3c == "BRA"]
  dplyr::bind_rows(
    sdid_rank_inference(distribution, "All valid assignments"),
    sdid_rank_inference(
      distribution,
      "Pre-fit RMSPE no larger than twice Brazil",
      keep_units = distribution$iso3c[
        distribution$status == "estimated" &
          distribution$rmspe_pre <= 2 * brazil_rmspe
      ]
    )
  )
}

build_paper_sdid_main_summary_candidate <- function(fit,
                                                    se_info,
                                                    rank_inference,
                                                    synth_data) {
  all_rank <- rank_inference |>
    dplyr::slice(1L)
  brazil_pre_mean <- synth_data |>
    dplyr::filter(iso3c == "BRA", year >= 1997L, year <= 2008L) |>
    dplyr::summarise(value = mean(abs_distance_china)) |>
    dplyr::pull(value)
  sdid_fit_summary_row(
    fit,
    "Preferred: no covariates",
    se_info$se
  ) |>
    dplyr::mutate(
      rank_one_sided_negative = all_rank$rank_one_sided_negative,
      rank_two_sided_absolute = all_rank$rank_two_sided_absolute,
      rank_denominator = all_rank$denominator,
      p_rank_one_sided_negative = all_rank$p_rank_one_sided_negative,
      p_rank_two_sided_absolute = all_rank$p_rank_two_sided_absolute,
      brazil_pre_treatment_mean = brazil_pre_mean,
      estimate_as_percent_of_pre_mean = 100 * estimate / brazil_pre_mean,
      se_replications = se_info$replications,
      se_seed = se_info$seed,
      source = se_info$source
    )
}

build_paper_sdid_donor_sensitivity_candidate <- function(synth_data,
                                                         fit,
                                                         unit_weights) {
  units <- sort(unique(synth_data$iso3c))
  main <- sdid_fit_summary_row(fit, "Preferred: no covariates")
  top10 <- unit_weights$iso3c[seq_len(10L)]
  top10_names <- unit_weights$country_name[seq_len(10L)]
  leave_one_out <- dplyr::bind_rows(lapply(seq_along(top10), function(index) {
    removed <- top10[[index]]
    candidate_fit <- sdid_fit_spec(
      synth_data,
      units = setdiff(units, removed)
    )
    sdid_fit_summary_row(
      candidate_fit,
      paste0("Drop ", top10_names[[index]], " (rank ", index, ")")
    ) |>
      dplyr::mutate(removed_donors = removed, n_removed_donors = 1L)
  }))
  drop_top10 <- sdid_fit_spec(
    synth_data,
    units = setdiff(units, top10)
  ) |>
    sdid_fit_summary_row("Drop top 10 donors by weight") |>
    dplyr::mutate(
      removed_donors = paste(top10, collapse = ";"),
      n_removed_donors = 10L
    )
  dplyr::bind_rows(
    main |>
      dplyr::mutate(
        removed_donors = NA_character_,
        n_removed_donors = 0L
      ),
    leave_one_out,
    drop_top10
  ) |>
    dplyr::mutate(
      estimate_change_vs_main = estimate - main$estimate,
      percent_change_vs_main = 100 *
        (estimate - main$estimate) / abs(main$estimate),
      inference = dplyr::if_else(
        n_removed_donors == 0L,
        "Main SE and rank reported separately",
        "Point estimate only"
      )
    )
}

build_paper_sdid_window_sensitivity_candidate <- function(synth_data, fit) {
  main_estimate <- as.numeric(fit)
  windows <- list(
    c(1997L, 2013L),
    c(1997L, 2014L),
    c(1997L, 2015L),
    c(1997L, 2016L),
    c(1998L, 2015L),
    c(1999L, 2015L),
    c(2000L, 2015L)
  )
  dplyr::bind_rows(lapply(windows, function(window) {
    candidate_fit <- sdid_fit_spec(
      synth_data,
      year_start = window[[1]],
      year_end = window[[2]]
    )
    preferred <- window[[1]] == 1997L && window[[2]] == 2015L
    label <- paste0(
      window[[1]],
      "-",
      window[[2]],
      if (preferred) " preferred" else ""
    )
    sdid_fit_summary_row(candidate_fit, label) |>
      dplyr::mutate(year_start = window[[1]], year_end = window[[2]])
  })) |>
    dplyr::mutate(
      estimate_change_vs_main = estimate - main_estimate,
      percent_change_vs_main = 100 *
        (estimate - main_estimate) / abs(main_estimate),
      inference = dplyr::if_else(
        grepl("preferred", specification),
        "20,000-placebo SE and rank reported in main results",
        "Point estimate only"
      )
    )
}

build_paper_sdid_timing_placebos_candidate <- function(synth_data,
                                                       rank_volume) {
  specifications <- tibble::tribble(
    ~nominal_treatment_year, ~year_end, ~test_role,
    2003L, 2008L, "Growth/lower-rank promotion",
    2004L, 2008L, "China rank-2 threshold",
    2005L, 2008L, "Rapid growth without rank 1",
    2009L, 2015L, "Actual rank-1 reversal",
    2012L, as.integer(max(synth_data$year)), "Later-break falsification"
  )
  timing <- dplyr::bind_rows(lapply(seq_len(nrow(specifications)), function(index) {
    specification <- specifications[index, ]
    candidate_fit <- sdid_fit_spec(
      synth_data,
      year_end = specification$year_end,
      treat_year = specification$nominal_treatment_year
    )
    specification |>
      dplyr::mutate(
        estimate = as.numeric(candidate_fit),
        inference = "Point estimate only; no covariates"
      )
  })) |>
    dplyr::left_join(
      rank_volume |>
        dplyr::select(
          year,
          china_rank,
          china_share_pct,
          china_margin_vs_competitor_usd_billion
        ),
      by = c("nominal_treatment_year" = "year"),
      relationship = "many-to-one"
    )
  if (nrow(timing) != nrow(specifications) || anyNA(timing$china_rank)) {
    stop("Timing placebo grid failed to match Brazil's rank-volume series.",
         call. = FALSE)
  }
  timing
}

build_paper_sdid_latam_summary_candidate <- function(fit,
                                                     se,
                                                     rank_distribution,
                                                     replications = 20000L,
                                                     seed = SDID_PLACEBO_SEED) {
  rank <- sdid_rank_inference(rank_distribution, "Latin America donor pool")
  sdid_fit_summary_row(
    fit,
    "Latin America donors; no covariates",
    as.numeric(se)
  ) |>
    dplyr::mutate(
      rank_one_sided_negative = rank$rank_one_sided_negative,
      rank_two_sided_absolute = rank$rank_two_sided_absolute,
      rank_denominator = rank$denominator,
      p_rank_one_sided_negative = rank$p_rank_one_sided_negative,
      p_rank_two_sided_absolute = rank$p_rank_two_sided_absolute,
      rank_floor = 1 / rank$denominator,
      se_replications = as.integer(replications),
      se_seed = as.integer(seed),
      inference = paste0(
        "Directional placebo rank is primary; placebo SE with ",
        format(replications, big.mark = ","),
        " replications, same seed as the preferred specification"
      )
    )
}

build_paper_sdid_outputs_candidate <- function(
    synth_data,
    preferred_fit,
    preferred_se_info,
    preferred_rank_distribution,
    latam_fit,
    latam_se,
    latam_rank_distribution,
    rank_volume,
    trade_data_ranked,
    trade_data_cleaned) {
  unit_weights <- build_paper_sdid_unit_weights_candidate(
    preferred_fit,
    synth_data
  )
  rank_inference <- build_paper_sdid_rank_inference_candidate(
    preferred_rank_distribution
  )
  exposure <- brazil_sdid_donor_china_exposure(
    trade_data_ranked,
    trade_data_cleaned,
    unit_weights,
    pre_years = 1997:2008,
    post_years = 2009:2015
  )
  if (!setequal(exposure$exposure$iso3c, unit_weights$iso3c)) {
    stop("Donor exposure does not cover the exact candidate donor pool.",
         call. = FALSE)
  }

  list(
    main_summary = build_paper_sdid_main_summary_candidate(
      preferred_fit,
      preferred_se_info,
      rank_inference,
      synth_data
    ),
    unit_weights = unit_weights,
    time_weights = build_paper_sdid_time_weights_candidate(preferred_fit),
    balance = build_paper_sdid_balance_candidate(
      synth_data,
      preferred_fit,
      unit_weights
    ),
    rank_inference = rank_inference,
    placebo_distribution = preferred_rank_distribution,
    donor_sensitivity = build_paper_sdid_donor_sensitivity_candidate(
      synth_data,
      preferred_fit,
      unit_weights
    ),
    window_sensitivity = build_paper_sdid_window_sensitivity_candidate(
      synth_data,
      preferred_fit
    ),
    donor_china_exposure = exposure$exposure,
    donor_china_exposure_summary = exposure$summary,
    timing_placebos = build_paper_sdid_timing_placebos_candidate(
      synth_data,
      rank_volume
    ),
    latam_core_summary = build_paper_sdid_latam_summary_candidate(
      latam_fit,
      latam_se,
      latam_rank_distribution
    )
  )
}

validate_paper_sdid_outputs_candidate <- function(
    bundle,
    reference_directory,
    tolerance = 1e-12) {
  keys <- list(
    main_summary = "specification",
    unit_weights = "weight_rank",
    time_weights = "year",
    balance = "variable",
    rank_inference = "comparison_set",
    placebo_distribution = "iso3c",
    donor_sensitivity = "specification",
    window_sensitivity = c("year_start", "year_end"),
    donor_china_exposure = "weight_rank",
    donor_china_exposure_summary = "n_high_weight_donors",
    timing_placebos = "nominal_treatment_year",
    latam_core_summary = "specification"
  )
  dplyr::bind_rows(lapply(names(keys), function(name) {
    compare_sdid_candidate_frame(
      bundle[[name]],
      file.path(reference_directory, paste0(name, ".csv")),
      keys[[name]],
      paste0("paper_sdid_", name),
      tolerance
    )
  }))
}

write_paper_sdid_outputs_candidate <- function(bundle, output_directory) {
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  files <- vapply(names(bundle), function(name) {
    path <- file.path(output_directory, paste0(name, ".csv"))
    readr::write_csv(bundle[[name]], path)
    normalizePath(path, mustWork = TRUE)
  }, character(1))
  unname(files)
}

write_sdid_table_candidate <- function(table, output_path) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(table, output_path)
  normalizePath(output_path, mustWork = TRUE)
}

write_sdid_fit_figure_candidate <- function(fit,
                                            output_path,
                                            subtitle) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  plot <- my_plot_trends(fit) +
    ggplot2::labs(title = NULL, subtitle = subtitle)
  ggplot2::ggsave(
    output_path,
    plot,
    width = 7,
    height = 4.8,
    dpi = 300
  )
  normalizePath(output_path, mustWork = TRUE)
}

write_sdid_weights_figure_candidate <- function(unit_weights, output_path) {
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  plot_data <- unit_weights |>
    dplyr::slice_head(n = 10L) |>
    dplyr::mutate(
      donor_label = paste0(country_name, " (", iso3c, ")"),
      donor_label = stats::reorder(donor_label, unit_weight)
    )
  plot <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = donor_label, y = unit_weight)
  ) +
    ggplot2::geom_col(fill = "#2B6F77", width = 0.72) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(
      labels = scales::label_percent(accuracy = 1)
    ) +
    ggplot2::labs(x = NULL, y = "Donor weight") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank()
    )
  ggplot2::ggsave(
    output_path,
    plot,
    width = 7,
    height = 4.8,
    dpi = 300
  )
  normalizePath(output_path, mustWork = TRUE)
}
