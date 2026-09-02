# Functions introduced during the full migration of paper-producing diagnostics
# into targets. They are kept separate from scripts/functions.R until the
# side-by-side comparison and review gates are complete.

aggregate_itpde_goods_exports_all_exporters <- function(
    itpd_path,
    start_year = 1990L,
    end_year = 2023L,
    goods_sector_values = c(
      "Agriculture",
      "Mining and Energy",
      "Manufacturing"
    )) {
  if (!file.exists(itpd_path)) {
    stop("ITPD-E file not found: ", itpd_path, call. = FALSE)
  }
  if (start_year > end_year) {
    stop("start_year must not exceed end_year.", call. = FALSE)
  }

  con <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = tempfile(fileext = ".duckdb")
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  itpd_sql <- as.character(DBI::dbQuoteString(
    con,
    normalizePath(itpd_path, mustWork = TRUE)
  ))
  goods_sql <- paste(
    as.character(DBI::dbQuoteString(con, goods_sector_values)),
    collapse = ", "
  )

  sector_audit <- DBI::dbGetQuery(con, paste0(
    "SELECT broad_sector, count(*) AS raw_rows, ",
    "sum(CASE WHEN try_cast(trade AS DOUBLE) IS NULL THEN 1 ELSE 0 END) ",
    "AS missing_or_parse_fail_trade, ",
    "sum(CASE WHEN coalesce(try_cast(trade AS DOUBLE), 0) > 0 THEN 1 ELSE 0 END) ",
    "AS positive_trade_rows ",
    "FROM read_csv_auto(", itpd_sql,
    ", header = true, all_varchar = true, ignore_errors = false) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
    "GROUP BY 1 ORDER BY 1"
  )) |>
    tibble::as_tibble()

  goods_exports <- DBI::dbGetQuery(con, paste0(
    "SELECT try_cast(year AS INTEGER) AS year, ",
    "upper(exporter_iso3) AS exporter_iso3, ",
    "upper(importer_iso3) AS importer_iso3, ",
    "sum(coalesce(try_cast(trade AS DOUBLE), 0)) AS exports ",
    "FROM read_csv_auto(", itpd_sql,
    ", header = true, all_varchar = true, ignore_errors = false) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
    "AND broad_sector IN (", goods_sql, ") ",
    "AND exporter_iso3 IS NOT NULL AND importer_iso3 IS NOT NULL ",
    "AND upper(exporter_iso3) <> upper(importer_iso3) ",
    "GROUP BY 1, 2, 3 ",
    "HAVING sum(coalesce(try_cast(trade AS DOUBLE), 0)) > 0 ",
    "ORDER BY exporter_iso3, year, importer_iso3"
  )) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      year = as.integer(year),
      exporter_iso3 = toupper(exporter_iso3),
      importer_iso3 = toupper(importer_iso3)
    ) |>
    dplyr::select(year, exporter_iso3, importer_iso3, exports)

  abort_if_duplicate_keys(
    goods_exports,
    c("year", "exporter_iso3", "importer_iso3"),
    "all-exporter ITPD-E goods exports"
  )
  if (any(!is.finite(goods_exports$exports)) ||
      any(goods_exports$exports <= 0)) {
    stop("Goods exports must be finite and strictly positive.", call. = FALSE)
  }

  list(
    goods_exports = goods_exports,
    sector_audit = sector_audit
  )
}

rank_itpde_goods_export_destinations <- function(goods_exports) {
  required_cols <- c("year", "exporter_iso3", "importer_iso3", "exports")
  missing_cols <- setdiff(required_cols, names(goods_exports))
  if (length(missing_cols) > 0L) {
    stop(
      "Missing required trade columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  trade <- goods_exports |>
    tibble::as_tibble() |>
    dplyr::transmute(
      year = as.integer(year),
      exporter_iso3 = toupper(exporter_iso3),
      importer_iso3 = toupper(importer_iso3),
      exports = as.numeric(exports)
    )

  abort_if_duplicate_keys(
    trade,
    c("year", "exporter_iso3", "importer_iso3"),
    "goods exports before partner ranking"
  )
  if (anyNA(trade[c("year", "exporter_iso3", "importer_iso3", "exports")]) ||
      any(!is.finite(trade$exports)) ||
      any(trade$exports <= 0)) {
    stop("Trade-ranking inputs must be complete, finite, and positive.",
         call. = FALSE)
  }

  ranked_trade <- trade |>
    dplyr::group_by(exporter_iso3, year) |>
    dplyr::mutate(partner_rank = dplyr::min_rank(dplyr::desc(exports))) |>
    dplyr::ungroup()

  top_partner <- ranked_trade |>
    dplyr::filter(partner_rank == 1L) |>
    dplyr::group_by(exporter_iso3, year) |>
    dplyr::summarise(
      n_top_ties = dplyr::n(),
      top_partner = dplyr::if_else(
        dplyr::n() == 1L,
        dplyr::first(importer_iso3),
        NA_character_
      ),
      top_export_value = max(exports),
      .groups = "drop"
    )

  rank_china_usa <- ranked_trade |>
    dplyr::filter(importer_iso3 %in% c("CHN", "USA")) |>
    dplyr::select(
      exporter_iso3,
      year,
      partner = importer_iso3,
      partner_rank
    ) |>
    tidyr::pivot_wider(
      names_from = partner,
      values_from = partner_rank,
      names_prefix = "rank_"
    )
  if (!"rank_CHN" %in% names(rank_china_usa)) {
    rank_china_usa$rank_CHN <- NA_integer_
  }
  if (!"rank_USA" %in% names(rank_china_usa)) {
    rank_china_usa$rank_USA <- NA_integer_
  }

  trade_rank <- top_partner |>
    dplyr::left_join(
      rank_china_usa,
      by = c("exporter_iso3", "year"),
      relationship = "one-to-one"
    ) |>
    dplyr::transmute(
      iso3c = exporter_iso3,
      year,
      trade_rank_row_present = TRUE,
      trade_rank_observed = n_top_ties == 1L,
      n_top_ties,
      top_partner,
      top_export_value,
      rank_CHN = as.integer(rank_CHN),
      rank_USA = as.integer(rank_USA),
      china_top_status = dplyr::case_when(
        n_top_ties > 1L ~ NA_integer_,
        top_partner == "CHN" ~ 1L,
        !is.na(top_partner) ~ 0L,
        TRUE ~ NA_integer_
      )
    ) |>
    dplyr::arrange(iso3c, year)

  abort_if_duplicate_keys(
    trade_rank,
    c("iso3c", "year"),
    "ranked goods-export destinations"
  )
  trade_rank
}

build_country_year_full_union_master <- function(trade_rank,
                                                  unga_data,
                                                  min_year = 1990L,
                                                  max_year = 2023L) {
  trade_required <- c(
    "iso3c", "year", "trade_rank_row_present", "trade_rank_observed",
    "n_top_ties", "top_partner", "top_export_value", "rank_CHN",
    "rank_USA", "china_top_status"
  )
  outcome_required <- c("iso3c", "year", "abs_distance_china")
  missing_trade <- setdiff(trade_required, names(trade_rank))
  missing_outcome <- setdiff(outcome_required, names(unga_data))
  if (length(missing_trade) > 0L || length(missing_outcome) > 0L) {
    stop(
      "Missing master-panel inputs: ",
      paste(c(missing_trade, missing_outcome), collapse = ", "),
      call. = FALSE
    )
  }
  if (min_year > max_year) {
    stop("min_year must not exceed max_year.", call. = FALSE)
  }

  trade_prepared <- trade_rank |>
    tibble::as_tibble() |>
    dplyr::filter(year >= min_year, year <= max_year) |>
    dplyr::select(dplyr::all_of(trade_required))

  outcome_optional <- intersect(
    c(
      "ideal_point_all", "us_agree", "china_agree", "china_ideal",
      "us_ideal", "br_ideal", "abs_distance_usa"
    ),
    names(unga_data)
  )
  outcome_prepared <- unga_data |>
    tibble::as_tibble() |>
    dplyr::transmute(
      iso3c = toupper(iso3c),
      year = as.integer(year),
      dplyr::across(dplyr::all_of(c("abs_distance_china", outcome_optional)))
    ) |>
    dplyr::filter(year >= min_year, year <= max_year) |>
    dplyr::mutate(
      unga_row_present = TRUE,
      outcome_observed = !is.na(abs_distance_china)
    )

  abort_if_duplicate_keys(
    trade_prepared,
    c("iso3c", "year"),
    "trade ranks for the full-union master"
  )
  abort_if_duplicate_keys(
    outcome_prepared,
    c("iso3c", "year"),
    "UNGA outcome for the full-union master"
  )

  source_union <- dplyr::full_join(
    trade_prepared,
    outcome_prepared,
    by = c("iso3c", "year"),
    relationship = "one-to-one"
  ) |>
    dplyr::filter(!is.na(iso3c), iso3c != "CHN")

  country_universe <- source_union |>
    dplyr::distinct(iso3c) |>
    dplyr::arrange(iso3c)
  if (nrow(country_universe) == 0L) {
    stop("The union of trade ranks and UNGA outcomes is empty.", call. = FALSE)
  }

  master_panel <- tidyr::expand_grid(
    iso3c = country_universe$iso3c,
    year = seq.int(min_year, max_year)
  ) |>
    dplyr::left_join(
      source_union,
      by = c("iso3c", "year"),
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      trade_rank_row_present = dplyr::coalesce(
        trade_rank_row_present,
        FALSE
      ),
      trade_rank_observed = dplyr::coalesce(trade_rank_observed, FALSE),
      unga_row_present = dplyr::coalesce(unga_row_present, FALSE),
      outcome_observed = dplyr::coalesce(outcome_observed, FALSE),
      country_name = dplyr::coalesce(
        countrycode::countrycode(
          iso3c,
          "iso3c",
          "country.name",
          warn = FALSE
        ),
        iso3c
      )
    ) |>
    dplyr::group_by(iso3c) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::mutate(
      previous_china_top_status = dplyr::lag(china_top_status),
      china_top_period_start = china_top_status %in% 1L &
        !(dplyr::lag(china_top_status) %in% 1L),
      china_top_period_id_raw = cumsum(china_top_period_start),
      china_top_period_id = dplyr::if_else(
        china_top_status %in% 1L,
        china_top_period_id_raw,
        NA_integer_
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-china_top_period_id_raw)

  abort_if_duplicate_keys(
    master_panel,
    c("iso3c", "year"),
    "full-union country-year master"
  )
  expected_rows <- nrow(country_universe) * (max_year - min_year + 1L)
  if (nrow(master_panel) != expected_rows) {
    stop("The master panel is not a complete country-year grid.", call. = FALSE)
  }
  if (any(master_panel$trade_rank_observed &
          is.na(master_panel$china_top_status))) {
    stop("Observed trade ranks cannot have missing China-top status.",
         call. = FALSE)
  }
  if (any(master_panel$n_top_ties > 1L &
          !is.na(master_panel$china_top_status), na.rm = TRUE)) {
    stop("Exact top-rank ties must have unknown China-top status.",
         call. = FALSE)
  }

  master_panel |>
    dplyr::arrange(iso3c, year)
}

build_full_union_status_period_data <- function(master_panel,
                                                 min_duration_years = 5L,
                                                 min_entry_year = 2000L) {
  required_cols <- c(
    "iso3c", "country_name", "year", "china_top_status",
    "previous_china_top_status", "china_top_period_id",
    "trade_rank_observed", "outcome_observed", "abs_distance_china"
  )
  missing_cols <- setdiff(required_cols, names(master_panel))
  if (length(missing_cols) > 0L) {
    stop(
      "Missing full-union master columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }
  if (is.na(min_duration_years) || min_duration_years <= 0L) {
    stop("min_duration_years must be a positive integer.", call. = FALSE)
  }

  period_summary <- master_panel |>
    dplyr::filter(
      china_top_status %in% 1L,
      !is.na(china_top_period_id)
    ) |>
    dplyr::group_by(iso3c, country_name, china_top_period_id) |>
    dplyr::summarise(
      period_entry_year = min(year),
      period_exit_year = max(year),
      duration_years = dplyr::n_distinct(year),
      calendar_span_years = period_exit_year - period_entry_year + 1L,
      prior_year = period_entry_year - 1L,
      prior_china_top_status = dplyr::first(previous_china_top_status),
      eligible_entry = period_entry_year >= min_entry_year &
        prior_china_top_status %in% 0L,
      qualifies_min_duration = eligible_entry &
        duration_years >= min_duration_years,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      qualifies_min5 = qualifies_min_duration,
      consecutive_calendar_years = duration_years == calendar_span_years
    ) |>
    dplyr::arrange(iso3c, period_entry_year)

  if (any(!period_summary$consecutive_calendar_years)) {
    stop("A China-top period contains a calendar gap.", call. = FALSE)
  }

  qualifying_periods <- period_summary |>
    dplyr::filter(qualifies_min_duration) |>
    dplyr::select(iso3c, china_top_period_id) |>
    dplyr::mutate(qualifying_period = TRUE)

  period_panel <- master_panel |>
    dplyr::left_join(
      qualifying_periods,
      by = c("iso3c", "china_top_period_id"),
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      qualifying_period = dplyr::coalesce(qualifying_period, FALSE),
      china_top = dplyr::case_when(
        is.na(china_top_status) ~ NA_integer_,
        china_top_status == 1L & qualifying_period ~ 1L,
        TRUE ~ 0L
      )
    )

  period_counts <- period_summary |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      eligible_periods = sum(eligible_entry, na.rm = TRUE),
      qualifying_periods = sum(qualifies_min_duration, na.rm = TRUE),
      first_eligible_entry = min_int_or_na(
        period_entry_year[eligible_entry]
      ),
      first_qualifying_entry = min_int_or_na(
        period_entry_year[qualifies_min_duration]
      ),
      max_eligible_duration = ifelse(
        any(eligible_entry),
        max(duration_years[eligible_entry]),
        0L
      ),
      total_eligible_china_top_years = sum(
        duration_years[eligible_entry],
        na.rm = TRUE
      ),
      total_qualifying_china_top_years = sum(
        duration_years[qualifies_min_duration],
        na.rm = TRUE
      ),
      n_observed_china_top_periods = dplyr::n(),
      .groups = "drop"
    )

  unit_summary <- period_panel |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      trade_rank_years = sum(trade_rank_observed, na.rm = TRUE),
      outcome_years = sum(outcome_observed, na.rm = TRUE),
      ever_china_top_observed = any(china_top_status %in% 1L),
      first_observed_year = min(year),
      last_observed_year = max(year),
      unknown_trade_rank_years = sum(is.na(china_top_status)),
      .groups = "drop"
    ) |>
    dplyr::left_join(
      period_counts,
      by = "iso3c",
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      dplyr::across(
        c(
          eligible_periods,
          qualifying_periods,
          max_eligible_duration,
          total_eligible_china_top_years,
          total_qualifying_china_top_years,
          n_observed_china_top_periods
        ),
        ~ dplyr::coalesce(.x, 0)
      ),
      treatment_role = dplyr::case_when(
        qualifying_periods > 0L ~ "treated_qualifying",
        trade_rank_years == 0L ~ "excluded_no_observed_trade_rank",
        !ever_china_top_observed ~ "never_observed_china_top_control",
        TRUE ~ "excluded_nonqualifying_china_top"
      ),
      cs_role_min5 = dplyr::case_when(
        treatment_role == "treated_qualifying" ~ "treated_min5",
        treatment_role == "never_observed_china_top_control" ~
          "never_treated",
        TRUE ~ "excluded_short_or_ineligible"
      ),
      first_treat = dplyr::if_else(
        treatment_role == "treated_qualifying",
        as.numeric(first_qualifying_entry),
        0
      )
    ) |>
    dplyr::arrange(treatment_role, iso3c)

  list(
    period_panel = period_panel,
    period_summary = period_summary,
    qualifying_periods = qualifying_periods,
    unit_summary = unit_summary
  )
}

make_full_union_status_panel <- function(period_data,
                                         specification = c(
                                           "risk_set_restricted",
                                           "clean_single_spell",
                                           "switching_allowed"
                                         ),
                                         min_untreated_observations = 5L) {
  specification <- match.arg(specification)
  if (is.na(min_untreated_observations) ||
      min_untreated_observations < 1L) {
    stop("min_untreated_observations must be positive.", call. = FALSE)
  }

  panel <- period_data$period_panel |>
    dplyr::left_join(
      period_data$unit_summary |>
        dplyr::select(
          iso3c,
          treatment_role,
          cs_role_min5,
          first_treat,
          first_qualifying_entry,
          eligible_periods,
          qualifying_periods,
          n_observed_china_top_periods,
          max_eligible_duration,
          total_eligible_china_top_years,
          total_qualifying_china_top_years,
          ever_china_top_observed
        ),
      by = "iso3c",
      relationship = "many-to-one"
    )

  if (specification == "clean_single_spell") {
    panel <- panel |>
      dplyr::filter(
        treatment_role == "never_observed_china_top_control" |
          (
            treatment_role == "treated_qualifying" &
              n_observed_china_top_periods == 1L &
              qualifying_periods == 1L
          )
      )
  } else {
    panel <- panel |>
      dplyr::filter(
        treatment_role %in% c(
          "treated_qualifying",
          "never_observed_china_top_control"
        )
      )
  }

  if (specification %in% c("risk_set_restricted", "clean_single_spell")) {
    panel <- panel |>
      dplyr::filter(
        (
          treatment_role == "never_observed_china_top_control" &
            china_top_status %in% 0L
        ) |
          (
            treatment_role == "treated_qualifying" &
              (
                qualifying_period |
                  (year < first_qualifying_entry & china_top_status %in% 0L)
              )
          )
      )
  } else {
    panel <- panel |>
      dplyr::filter(!is.na(china_top_status))
  }

  panel <- panel |>
    dplyr::filter(outcome_observed, !is.na(abs_distance_china), !is.na(china_top))

  if (specification == "switching_allowed") {
    maximum_observed_years <- panel |>
      dplyr::count(iso3c, name = "n_years") |>
      dplyr::summarise(max_years = max(n_years)) |>
      dplyr::pull(max_years)
    panel <- panel |>
      dplyr::group_by(iso3c) |>
      dplyr::filter(dplyr::n() == maximum_observed_years) |>
      dplyr::ungroup()
  }

  panel <- panel |>
    dplyr::group_by(iso3c) |>
    dplyr::mutate(
      untreated_observations = sum(china_top == 0L),
      treated_observations = sum(china_top == 1L)
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(untreated_observations >= min_untreated_observations)

  if (nrow(panel) == 0L) {
    stop("No observations remain in the requested status-current panel.",
         call. = FALSE)
  }

  panel_max <- max(panel$year, na.rm = TRUE)
  estimable_treated <- panel |>
    dplyr::filter(
      treatment_role == "treated_qualifying",
      first_treat > 0,
      first_treat < panel_max,
      china_top == 1L
    ) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c)

  estimation_panel <- panel |>
    dplyr::filter(
      treatment_role == "never_observed_china_top_control" |
        iso3c %in% estimable_treated
    ) |>
    dplyr::mutate(
      country_id = as.integer(as.factor(iso3c)),
      id = country_id
    ) |>
    dplyr::arrange(country_id, year) |>
    as.data.frame()

  abort_if_duplicate_keys(
    estimation_panel,
    c("iso3c", "year"),
    paste0("full-union ", specification, " estimation panel")
  )
  if (anyNA(estimation_panel$abs_distance_china) ||
      anyNA(estimation_panel$china_top) ||
      any(!estimation_panel$china_top %in% c(0L, 1L))) {
    stop("The estimation panel has invalid outcome or treatment values.",
         call. = FALSE)
  }

  estimation_panel
}

make_full_union_status_panel_bundle <- function(
    master_panel,
    duration_thresholds = c(3L, 5L, 7L),
    min_entry_year = 2000L,
    min_untreated_observations = 5L) {
  duration_thresholds <- sort(unique(as.integer(duration_thresholds)))
  if (anyNA(duration_thresholds) || any(duration_thresholds <= 0L)) {
    stop("duration_thresholds must be positive integers.", call. = FALSE)
  }

  panels <- list()
  all_counts <- list()
  all_units <- list()
  all_treatment_units <- list()
  all_periods <- list()

  for (duration_years in duration_thresholds) {
    period_data <- build_full_union_status_period_data(
      master_panel,
      min_duration_years = duration_years,
      min_entry_year = min_entry_year
    )
    duration_panels <- list(
      switching_allowed = make_full_union_status_panel(
        period_data,
        specification = "switching_allowed",
        min_untreated_observations = min_untreated_observations
      ),
      risk_set_restricted = make_full_union_status_panel(
        period_data,
        specification = "risk_set_restricted",
        min_untreated_observations = min_untreated_observations
      ),
      clean_single_spell = make_full_union_status_panel(
        period_data,
        specification = "clean_single_spell",
        min_untreated_observations = min_untreated_observations
      )
    )
    duration_key <- as.character(duration_years)
    panels[[duration_key]] <- duration_panels

    all_counts[[duration_key]] <- dplyr::bind_rows(
      count_status_current_sample(
        duration_panels$switching_allowed,
        "switching_allowed"
      ),
      count_status_current_sample(
        duration_panels$risk_set_restricted,
        "risk_set_restricted"
      ),
      count_status_current_sample(
        duration_panels$clean_single_spell,
        "clean_single_spell"
      )
    ) |>
      dplyr::mutate(min_duration_years = duration_years, .before = sample)

    all_units[[duration_key]] <- dplyr::bind_rows(
      summarize_status_current_units(
        duration_panels$switching_allowed,
        "switching_allowed"
      ),
      summarize_status_current_units(
        duration_panels$risk_set_restricted,
        "risk_set_restricted"
      ),
      summarize_status_current_units(
        duration_panels$clean_single_spell,
        "clean_single_spell"
      )
    ) |>
      dplyr::mutate(min_duration_years = duration_years, .before = sample)

    all_treatment_units[[duration_key]] <- period_data$unit_summary |>
      dplyr::mutate(min_duration_years = duration_years, .before = iso3c)
    all_periods[[duration_key]] <- period_data$period_summary |>
      dplyr::mutate(min_duration_years = duration_years, .before = iso3c)
  }

  list(
    panels = panels,
    sample_counts = dplyr::bind_rows(all_counts) |>
      dplyr::arrange(min_duration_years, sample),
    unit_summary = dplyr::bind_rows(all_units) |>
      dplyr::arrange(min_duration_years, sample, iso3c),
    treatment_unit_summary = dplyr::bind_rows(all_treatment_units) |>
      dplyr::arrange(min_duration_years, treatment_role, iso3c),
    period_summary = dplyr::bind_rows(all_periods) |>
      dplyr::arrange(min_duration_years, iso3c, china_top_period_id)
  )
}

validate_full_union_status_bundle <- function(master_panel,
                                               panel_bundle,
                                               expected_cod_year = 2021L) {
  grid_counts <- master_panel |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      n_years = dplyr::n(),
      min_year = min(year),
      max_year = max(year),
      .groups = "drop"
    )

  cod_row <- master_panel |>
    dplyr::filter(iso3c == "COD", year == expected_cod_year)
  cod_gate_available <- nrow(cod_row) == 1L
  cod_trade_treated <- cod_gate_available &&
    identical(cod_row$china_top_status, 1L)
  cod_outcome_missing <- cod_gate_available &&
    is.na(cod_row$abs_distance_china)

  main_panel <- panel_bundle$panels[["5"]][["risk_set_restricted"]]
  tibble::tibble(
    validation = c(
      "unique_master_country_year_keys",
      "complete_common_year_grid",
      "treatment_missingness_follows_trade_status",
      "top_rank_ties_have_unknown_treatment_status",
      "main_estimation_outcomes_complete",
      "main_estimation_treatment_binary",
      "cod_2021_trade_status_is_treated",
      "cod_2021_outcome_remains_missing",
      "cod_2021_excluded_only_from_estimation"
    ),
    passed = c(
      !anyDuplicated(master_panel[c("iso3c", "year")]),
      dplyr::n_distinct(grid_counts$n_years) == 1L &&
        dplyr::n_distinct(grid_counts$min_year) == 1L &&
        dplyr::n_distinct(grid_counts$max_year) == 1L,
      all(is.na(master_panel$china_top_status) ==
            !master_panel$trade_rank_observed),
      all(is.na(master_panel$china_top_status[master_panel$n_top_ties > 1L])),
      !anyNA(main_panel$abs_distance_china),
      all(main_panel$china_top %in% c(0L, 1L)),
      cod_trade_treated,
      cod_outcome_missing,
      cod_gate_available && !any(
        main_panel$iso3c == "COD" & main_panel$year == expected_cod_year
      )
    )
  )
}
