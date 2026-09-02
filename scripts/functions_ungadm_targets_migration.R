# Candidate functions for migrating the UNGA-DM measurement-robustness block
# into targets. Network acquisition remains outside the graph; every function
# below starts from frozen file targets or upstream R objects.

ungadm_expected_input_manifest <- function(bsv_file,
                                           ungadm_file,
                                           codebook_file,
                                           sources_file) {
  tibble::tribble(
    ~role, ~path, ~expected_bytes, ~expected_sha256,
    "BSV Jun/2024 ideal points", bsv_file, 1932704,
    "94ce7440bdba9252b2f4294333291585748dfe84dbaf56fe9f26e1af38f66198",
    "UNGA-DM session 75 ideal points", ungadm_file, 2060041,
    "3713cadff82a220dcc332cc09e433037144b1c41e3be07343d38a309506761f7",
    "UNGA-DM codebook v2023.2", codebook_file, 278907,
    "74117c225215dc8c749ba8b84dbbca0a23aba795046f1ffdd00d1ee9631cad69",
    "UNGA-DM source note", sources_file, NA_real_, NA_character_
  )
}

validate_ungadm_input_files <- function(bsv_file,
                                        ungadm_file,
                                        codebook_file,
                                        sources_file) {
  manifest <- ungadm_expected_input_manifest(
    bsv_file,
    ungadm_file,
    codebook_file,
    sources_file
  ) |>
    dplyr::mutate(
      exists = file.exists(path),
      bytes = vapply(
        path,
        function(candidate) {
          if (!file.exists(candidate)) return(NA_real_)
          as.numeric(file.info(candidate)$size)
        },
        numeric(1)
      ),
      sha256 = vapply(
        path,
        function(candidate) {
          if (!file.exists(candidate)) return(NA_character_)
          digest::digest(
            file = candidate,
            algo = "sha256",
            serialize = FALSE
          )
        },
        character(1)
      ),
      bytes_match = is.na(expected_bytes) | bytes == expected_bytes,
      hash_match = is.na(expected_sha256) | sha256 == expected_sha256,
      passed = exists & bytes_match & hash_match
    )
  if (any(!(manifest$passed %in% TRUE))) {
    failed <- manifest |>
      dplyr::filter(!(.data$passed %in% TRUE)) |>
      dplyr::pull(role)
    stop(
      "Frozen UNGA-DM inputs failed validation: ",
      paste(failed, collapse = ", "),
      call. = FALSE
    )
  }
  manifest
}

ungadm_require_columns <- function(data, required, label) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop(
      label, " lacks required columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(data)
}

ungadm_add_source_distances <- function(data,
                                        ideal_column,
                                        source_label) {
  ungadm_require_columns(
    data,
    c("ccode", "session", ideal_column),
    source_label
  )
  anchors <- data |>
    dplyr::group_by(session) |>
    dplyr::summarise(
      n_china = sum(ccode == 710L),
      n_usa = sum(ccode == 2L),
      china_ideal = if (sum(ccode == 710L) == 1L) {
        .data[[ideal_column]][ccode == 710L][[1]]
      } else NA_real_,
      usa_ideal = if (sum(ccode == 2L) == 1L) {
        .data[[ideal_column]][ccode == 2L][[1]]
      } else NA_real_,
      .groups = "drop"
    )
  analytic_anchors <- anchors |>
    dplyr::filter(session + 1945L >= 1990L)
  if (nrow(analytic_anchors) == 0L ||
      any(analytic_anchors$n_china != 1L) ||
      any(analytic_anchors$n_usa != 1L)) {
    stop(
      source_label,
      " must contain exactly one China and US anchor in every analytic session.",
      call. = FALSE
    )
  }
  data |>
    dplyr::left_join(
      anchors,
      by = "session",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      abs_distance_china = abs(.data[[ideal_column]] - china_ideal),
      abs_distance_usa = abs(.data[[ideal_column]] - usa_ideal)
    )
}

build_ungadm_harmonized_bundle <- function(bsv_file,
                                            ungadm_file,
                                            min_year = 1990L) {
  bsv_import <- readr::read_csv(bsv_file, show_col_types = FALSE) |>
    janitor::clean_names()
  ungadm_import <- readr::read_csv(ungadm_file, show_col_types = FALSE) |>
    janitor::clean_names()
  ungadm_require_columns(
    bsv_import,
    c(
      "ccode", "session", "iso3c", "countryname", "q50_percent_all",
      "n_votes_all"
    ),
    "BSV input"
  )
  ungadm_require_columns(
    ungadm_import,
    c("ccode", "session", "country", "x50"),
    "UNGA-DM input"
  )

  bsv <- bsv_import |>
    dplyr::transmute(
      ccode = as.integer(ccode),
      session = as.integer(session),
      iso3c = toupper(iso3c),
      country_bsv = countryname,
      q50_bsv = as.numeric(q50_percent_all),
      n_votes_bsv = as.integer(n_votes_all)
    )
  ungadm <- ungadm_import |>
    dplyr::transmute(
      ccode_original = as.integer(ccode),
      ccode = dplyr::if_else(
        as.integer(session) == 45L & as.integer(ccode) == 255L,
        260L,
        as.integer(ccode)
      ),
      session = as.integer(session),
      country_ungadm = country,
      q50_dm = as.numeric(x50)
    )
  abort_if_duplicate_keys(bsv, c("ccode", "session"), "BSV country-session")
  abort_if_duplicate_keys(
    ungadm,
    c("ccode", "session"),
    "UNGA-DM country-session after Germany harmonization"
  )
  if (anyNA(bsv[c("ccode", "session", "iso3c", "q50_bsv")]) ||
      anyNA(ungadm[c("ccode", "session", "q50_dm")]) ||
      any(!is.finite(bsv$q50_bsv)) ||
      any(!is.finite(ungadm$q50_dm))) {
    stop("Ideal-point inputs must have complete finite keys and medians.",
         call. = FALSE)
  }

  bsv_distances <- ungadm_add_source_distances(
    bsv,
    "q50_bsv",
    "BSV"
  )
  dm_distances <- ungadm_add_source_distances(
    ungadm,
    "q50_dm",
    "UNGA-DM"
  )
  bsv_crosswalk <- bsv |>
    dplyr::select(ccode, session, iso3c)
  dm_mapped <- dm_distances |>
    dplyr::left_join(
      bsv_crosswalk,
      by = c("ccode", "session"),
      relationship = "one-to-one"
    )
  unmatched <- dm_mapped |>
    dplyr::filter(is.na(iso3c)) |>
    dplyr::select(ccode, session, country_ungadm) |>
    dplyr::arrange(session, ccode)
  outcome <- dm_mapped |>
    dplyr::filter(!is.na(iso3c), session + 1945L >= min_year) |>
    dplyr::transmute(
      iso3c,
      year = session + 1945L,
      session,
      ccode,
      country_ungadm,
      ideal_point_dm = q50_dm,
      china_ideal_dm = china_ideal,
      usa_ideal_dm = usa_ideal,
      abs_distance_china_dm = abs_distance_china,
      abs_distance_usa_dm = abs_distance_usa
    ) |>
    dplyr::arrange(iso3c, year)
  abort_if_duplicate_keys(outcome, c("iso3c", "year"), "UNGA-DM outcome")

  comparison <- bsv_distances |>
    dplyr::select(
      ccode,
      session,
      iso3c,
      q50_bsv,
      n_votes_bsv,
      china_ideal_bsv = china_ideal,
      usa_ideal_bsv = usa_ideal,
      dist_china_bsv = abs_distance_china,
      dist_usa_bsv = abs_distance_usa
    ) |>
    dplyr::inner_join(
      dm_distances |>
        dplyr::select(
          ccode,
          session,
          country_ungadm,
          q50_dm,
          china_ideal_dm = china_ideal,
          usa_ideal_dm = usa_ideal,
          dist_china_dm = abs_distance_china,
          dist_usa_dm = abs_distance_usa
        ),
      by = c("ccode", "session"),
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(year = session + 1945L) |>
    dplyr::arrange(session, ccode)

  list(
    bsv = bsv_distances,
    ungadm = dm_distances,
    comparison = comparison,
    outcome = outcome,
    unmatched = unmatched,
    session_max_dm = max(ungadm$session)
  )
}

ungadm_cor_block <- function(data, label) {
  complete <- stats::complete.cases(
    data$q50_bsv,
    data$q50_dm,
    data$dist_china_bsv,
    data$dist_china_dm,
    data$dist_usa_bsv,
    data$dist_usa_dm
  )
  used <- data[complete, , drop = FALSE]
  correlation <- function(x, y) {
    if (length(x) < 2L) return(NA_real_)
    stats::cor(x, y)
  }
  tibble::tibble(
    window = label,
    n_country_sessions = nrow(data),
    n_used_in_correlation = nrow(used),
    cor_q50 = correlation(used$q50_bsv, used$q50_dm),
    cor_dist_china = correlation(
      used$dist_china_bsv,
      used$dist_china_dm
    ),
    cor_dist_usa = correlation(used$dist_usa_bsv, used$dist_usa_dm)
  )
}

build_ungadm_validation_outputs <- function(harmonized_bundle) {
  bsv <- harmonized_bundle$bsv
  ungadm <- harmonized_bundle$ungadm
  comparison <- harmonized_bundle$comparison
  session_max <- harmonized_bundle$session_max_dm

  bsv_only <- dplyr::anti_join(
    bsv,
    ungadm,
    by = c("ccode", "session")
  ) |>
    dplyr::mutate(
      year = session + 1945L,
      reason = dplyr::if_else(
        session > session_max,
        "beyond UNGA-DM endpoint",
        "within-range gap"
      )
    )
  dm_only <- dplyr::anti_join(
    ungadm,
    bsv,
    by = c("ccode", "session")
  ) |>
    dplyr::mutate(
      year = session + 1945L,
      reason = "missing from BSV"
    )
  coverage_summary <- dplyr::bind_rows(
    bsv_only |>
      dplyr::count(reason, name = "n_country_sessions") |>
      dplyr::mutate(source = "BSV only"),
    dm_only |>
      dplyr::count(reason, name = "n_country_sessions") |>
      dplyr::mutate(source = "UNGA-DM only")
  ) |>
    dplyr::select(source, reason, n_country_sessions) |>
    dplyr::arrange(source, reason)
  within_range_gaps <- dplyr::bind_rows(
    bsv_only |>
      dplyr::filter(reason == "within-range gap") |>
      dplyr::transmute(
        source = "BSV only",
        ccode,
        session,
        year,
        label = iso3c
      ),
    dm_only |>
      dplyr::transmute(
        source = "UNGA-DM only",
        ccode,
        session,
        year,
        label = country_ungadm
      )
  ) |>
    dplyr::arrange(source, session, ccode)

  correlations <- dplyr::bind_rows(
    ungadm_cor_block(comparison, "All merged sessions (1-75)"),
    ungadm_cor_block(
      dplyr::filter(comparison, year >= 1946L, year <= 1989L),
      "1946-1989"
    ),
    ungadm_cor_block(
      dplyr::filter(comparison, year >= 1990L, year <= 2020L),
      "1990-2020 (panel era)"
    ),
    ungadm_cor_block(
      dplyr::filter(comparison, year >= 1997L, year <= 2015L),
      "1997-2015 (Brazil SDiD window)"
    ),
    ungadm_cor_block(
      dplyr::filter(comparison, year >= 1990L, year <= 2000L),
      "1990-2000"
    ),
    ungadm_cor_block(
      dplyr::filter(comparison, year >= 2001L, year <= 2010L),
      "2001-2010"
    ),
    ungadm_cor_block(
      dplyr::filter(comparison, year >= 2011L, year <= 2020L),
      "2011-2020"
    )
  )
  brazil_series <- comparison |>
    dplyr::filter(ccode == 140L) |>
    dplyr::arrange(session) |>
    dplyr::select(
      session,
      year,
      q50_bsv,
      q50_dm,
      dist_china_bsv,
      dist_china_dm,
      dist_usa_bsv,
      dist_usa_dm
    )
  brazil_window <- brazil_series |>
    dplyr::filter(year >= 1997L, year <= 2015L)
  brazil_gap_summary <- brazil_window |>
    dplyr::summarise(
      mean_dist_bsv = mean(dist_china_bsv),
      mean_dist_dm = mean(dist_china_dm),
      mean_abs_diff = mean(abs(dist_china_bsv - dist_china_dm)),
      max_abs_diff = max(abs(dist_china_bsv - dist_china_dm))
    )
  panel_correlation <- correlations |>
    dplyr::filter(window == "1997-2015 (Brazil SDiD window)") |>
    dplyr::pull(cor_dist_china)
  brazil_correlation <- stats::cor(
    brazil_window$dist_china_bsv,
    brazil_window$dist_china_dm
  )
  germany_mapped <- harmonized_bundle$outcome |>
    dplyr::filter(year == 1990L, iso3c == "DEU", ccode == 260L) |>
    nrow() == 1L

  validation <- tibble::tibble(
    validation = c(
      "unique_bsv_country_session_keys",
      "unique_ungadm_country_session_keys",
      "unique_ungadm_iso3c_year_keys",
      "analytic_sessions_have_unique_anchors",
      "germany_session_45_is_mapped",
      "expected_unmapped_rows",
      "panel_window_correlation_at_least_0_95",
      "brazil_sdid_window_complete"
    ),
    passed = c(
      anyDuplicated(bsv[c("ccode", "session")]) == 0L,
      anyDuplicated(ungadm[c("ccode", "session")]) == 0L,
      anyDuplicated(harmonized_bundle$outcome[c("iso3c", "year")]) == 0L,
      all(
        harmonized_bundle$outcome$year < 1990L |
          (
            !is.na(harmonized_bundle$outcome$china_ideal_dm) &
              !is.na(harmonized_bundle$outcome$usa_ideal_dm)
          )
      ),
      germany_mapped,
      nrow(harmonized_bundle$unmatched) == 28L,
      length(panel_correlation) == 1L &&
        is.finite(panel_correlation) && panel_correlation >= 0.95,
      nrow(brazil_window) == 19L &&
        !anyNA(brazil_window[c("dist_china_bsv", "dist_china_dm")])
    ),
    detail = c(
      paste0("rows=", nrow(bsv)),
      paste0("rows=", nrow(ungadm)),
      paste0("rows=", nrow(harmonized_bundle$outcome)),
      "China and US anchors required from 1990 onward",
      paste0("mapped=", germany_mapped),
      paste0("unmapped=", nrow(harmonized_bundle$unmatched)),
      paste0("cor=", format(panel_correlation, digits = 16)),
      paste0("Brazil rows=", nrow(brazil_window),
             "; cor=", format(brazil_correlation, digits = 16))
    )
  )
  list(
    validation = validation,
    correlations = correlations,
    coverage_summary = coverage_summary,
    within_range_gaps = within_range_gaps,
    brazil_series = brazil_series,
    brazil_gap_summary = brazil_gap_summary,
    unmapped = harmonized_bundle$unmatched
  )
}

ungadm_validation_names <- function() {
  c(
    "unique_bsv_country_session_keys",
    "unique_ungadm_country_session_keys",
    "unique_ungadm_iso3c_year_keys",
    "analytic_sessions_have_unique_anchors",
    "germany_session_45_is_mapped",
    "expected_unmapped_rows",
    "panel_window_correlation_at_least_0_95",
    "brazil_sdid_window_complete"
  )
}

assert_ungadm_validation <- function(validation, expected_names) {
  if (!is.data.frame(validation) ||
      !all(c("validation", "passed") %in% names(validation)) ||
      !is.character(validation$validation) ||
      !is.logical(validation$passed) ||
      nrow(validation) == 0L ||
      anyNA(validation$validation) ||
      anyDuplicated(validation$validation) ||
      !setequal(validation$validation, expected_names)) {
    stop("UNGA-DM validation has an invalid schema.", call. = FALSE)
  }
  failed <- validation |>
    dplyr::filter(!(.data$passed %in% TRUE)) |>
    dplyr::pull(validation)
  if (length(failed) > 0L) {
    stop(
      "UNGA-DM validation failed: ",
      paste(failed, collapse = ", "),
      call. = FALSE
    )
  }
  validation
}

join_ungadm_to_full_union_master <- function(master_panel, ungadm_outcome) {
  abort_if_duplicate_keys(
    master_panel,
    c("iso3c", "year"),
    "full-union master before UNGA-DM join"
  )
  abort_if_duplicate_keys(
    ungadm_outcome,
    c("iso3c", "year"),
    "UNGA-DM outcome before master join"
  )
  master_keys <- master_panel |>
    dplyr::select(iso3c, year)
  treatment_columns <- intersect(
    c(
      "trade_rank_row_present", "trade_rank_observed", "n_top_ties",
      "top_partner", "top_export_value", "rank_CHN", "rank_USA",
      "china_top_status", "previous_china_top_status",
      "china_top_period_start", "china_top_period_id"
    ),
    names(master_panel)
  )
  treatment_before <- master_panel |>
    dplyr::select(iso3c, year, dplyr::all_of(treatment_columns))
  augmented <- master_panel |>
    dplyr::left_join(
      ungadm_outcome |>
        dplyr::select(
          iso3c,
          year,
          session_dm = session,
          ccode_dm = ccode,
          ideal_point_dm,
          china_ideal_dm,
          usa_ideal_dm,
          abs_distance_china_dm,
          abs_distance_usa_dm
        ),
      by = c("iso3c", "year"),
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      ungadm_row_present = !is.na(session_dm),
      ungadm_outcome_observed = !is.na(abs_distance_china_dm)
    ) |>
    dplyr::arrange(iso3c, year)
  treatment_after <- augmented |>
    dplyr::select(iso3c, year, dplyr::all_of(treatment_columns))
  if (!identical(master_keys, dplyr::select(augmented, iso3c, year)) ||
      !identical(treatment_before, treatment_after)) {
    stop("UNGA-DM join changed the master grid or trade treatment.",
         call. = FALSE)
  }
  augmented
}

validate_ungadm_master_join <- function(master_panel, augmented_master) {
  future <- augmented_master |>
    dplyr::filter(year %in% 2021:2023)
  treatment_columns <- intersect(
    c(
      "trade_rank_row_present", "trade_rank_observed", "n_top_ties",
      "top_partner", "top_export_value", "rank_CHN", "rank_USA",
      "china_top_status", "previous_china_top_status",
      "china_top_period_start", "china_top_period_id"
    ),
    names(master_panel)
  )
  validation <- tibble::tibble(
    validation = c(
      "master_row_count_unchanged",
      "master_keys_unchanged",
      "master_treatment_unchanged",
      "future_years_present_for_every_country",
      "future_ungadm_outcomes_are_missing",
      "ungadm_missingness_does_not_erase_trade_status"
    ),
    passed = c(
      nrow(master_panel) == nrow(augmented_master),
      identical(
        dplyr::select(master_panel, iso3c, year),
        dplyr::select(augmented_master, iso3c, year)
      ),
      identical(
        dplyr::select(
          master_panel,
          iso3c,
          year,
          dplyr::all_of(treatment_columns)
        ),
        dplyr::select(
          augmented_master,
          iso3c,
          year,
          dplyr::all_of(treatment_columns)
        )
      ),
      nrow(future) == dplyr::n_distinct(augmented_master$iso3c) * 3L,
      all(is.na(future$abs_distance_china_dm)),
      any(
        !augmented_master$ungadm_outcome_observed &
          augmented_master$trade_rank_observed
      )
    ),
    detail = c(
      paste0(nrow(master_panel), " -> ", nrow(augmented_master)),
      "iso3c-year sequence",
      paste(treatment_columns, collapse = ";"),
      paste0("future rows=", nrow(future)),
      paste0("observed future DM=", sum(!is.na(future$abs_distance_china_dm))),
      paste0(
        "missing DM with trade rank=",
        sum(
          !augmented_master$ungadm_outcome_observed &
            augmented_master$trade_rank_observed
        )
      )
    )
  )
  validation
}

ungadm_master_join_validation_names <- function() {
  c(
    "master_row_count_unchanged",
    "master_keys_unchanged",
    "master_treatment_unchanged",
    "future_years_present_for_every_country",
    "future_ungadm_outcomes_are_missing",
    "ungadm_missingness_does_not_erase_trade_status"
  )
}

write_ungadm_validation_overlay_candidate <- function(brazil_series,
                                                       output_path) {
  plot_data <- brazil_series |>
    dplyr::select(
      year,
      BSV = dist_china_bsv,
      `UNGA-DM` = dist_china_dm
    ) |>
    tidyr::pivot_longer(
      cols = -year,
      names_to = "source",
      values_to = "distance"
    )
  plot <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = year, y = distance, colour = source)
  ) +
    ggplot2::geom_line(linewidth = 0.6) +
    ggplot2::geom_point(size = 1.2) +
    ggplot2::geom_vline(
      xintercept = 2009,
      linetype = "dashed",
      colour = "grey40"
    ) +
    ggplot2::annotate(
      "rect",
      xmin = 1997,
      xmax = 2015,
      ymin = -Inf,
      ymax = Inf,
      alpha = 0.06
    ) +
    ggplot2::labs(
      x = "Year",
      y = "Absolute ideal-point distance to China",
      colour = NULL,
      title = "Brazil outcome series: BSV Jun/2024 vs UNGA-DM",
      subtitle = "Shaded band: 1997-2015; dashed line: 2009 treatment onset"
    ) +
    ggplot2::theme_minimal(base_size = 11)
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    output_path,
    plot,
    width = 8,
    height = 4.5,
    dpi = 300
  )
  normalizePath(output_path, mustWork = TRUE)
}

build_ungadm_sdid_panel_bundle <- function(synth_data,
                                            ungadm_outcome,
                                            year_start = 1997L,
                                            year_end = 2015L) {
  source_keys <- synth_data |>
    dplyr::filter(year >= year_start, year <= year_end) |>
    dplyr::select(iso3c, year) |>
    dplyr::arrange(iso3c, year)
  abort_if_duplicate_keys(
    source_keys,
    c("iso3c", "year"),
    "BSV SDiD source panel"
  )
  joined <- synth_data |>
    dplyr::left_join(
      ungadm_outcome |>
        dplyr::select(iso3c, year, abs_distance_china_dm),
      by = c("iso3c", "year"),
      relationship = "many-to-one"
    )
  missing <- joined |>
    dplyr::filter(
      year >= year_start,
      year <= year_end,
      is.na(abs_distance_china_dm)
    ) |>
    dplyr::select(iso3c, year) |>
    dplyr::arrange(iso3c, year)
  panel <- joined |>
    dplyr::mutate(
      abs_distance_china_bsv = abs_distance_china,
      abs_distance_china = abs_distance_china_dm
    ) |>
    dplyr::select(-abs_distance_china_dm)
  panel_keys <- panel |>
    dplyr::filter(year >= year_start, year <= year_end) |>
    dplyr::select(iso3c, year) |>
    dplyr::arrange(iso3c, year)
  if (!identical(source_keys, panel_keys)) {
    stop("UNGA-DM join changed the Brazil SDiD country-year grid.",
         call. = FALSE)
  }
  list(panel = panel, missing = missing)
}

validate_ungadm_sdid_panel <- function(synth_data,
                                       sdid_panel_bundle,
                                       year_start = 1997L,
                                       year_end = 2015L,
                                       expected_units = 96L) {
  source_window <- synth_data |>
    dplyr::filter(year >= year_start, year <= year_end) |>
    dplyr::arrange(iso3c, year)
  dm_window <- sdid_panel_bundle$panel |>
    dplyr::filter(year >= year_start, year <= year_end) |>
    dplyr::arrange(iso3c, year)
  tibble::tibble(
    validation = c(
      "sdid_country_year_keys_unchanged",
      "sdid_treatment_unchanged",
      "sdid_expected_unit_count",
      "sdid_complete_annual_window",
      "sdid_dm_outcome_complete"
    ),
    passed = c(
      identical(
        dplyr::select(source_window, iso3c, year),
        dplyr::select(dm_window, iso3c, year)
      ),
      identical(source_window$treatment, dm_window$treatment),
      dplyr::n_distinct(dm_window$iso3c) == expected_units,
      nrow(dm_window) == expected_units * (year_end - year_start + 1L),
      nrow(sdid_panel_bundle$missing) == 0L &&
        !anyNA(dm_window$abs_distance_china)
    ),
    detail = c(
      paste0("rows=", nrow(dm_window)),
      "Brazil treatment inherited from synth_data",
      paste0("units=", dplyr::n_distinct(dm_window$iso3c)),
      paste0(year_start, "-", year_end),
      paste0("missing=", nrow(sdid_panel_bundle$missing))
    )
  )
}

ungadm_sdid_panel_validation_names <- function() {
  c(
    "sdid_country_year_keys_unchanged",
    "sdid_treatment_unchanged",
    "sdid_expected_unit_count",
    "sdid_complete_annual_window",
    "sdid_dm_outcome_complete"
  )
}

build_ungadm_sdid_outputs_candidate <- function(
    dm_panel,
    dm_fit,
    dm_se_info,
    dm_rank_distribution,
    bsv_fit,
    bsv_outputs,
    full_union_trade_rank,
    full_union_unit_summary) {
  units <- sort(unique(
    dm_panel$iso3c[dm_panel$year >= 1997L & dm_panel$year <= 2015L]
  ))
  if (!setequal(dm_rank_distribution$iso3c, units) ||
      nrow(dm_rank_distribution) != length(units)) {
    stop("UNGA-DM rank distribution does not cover the exact SDiD units.",
         call. = FALSE)
  }
  brazil_rmspe <- dm_rank_distribution |>
    dplyr::filter(iso3c == "BRA", status == "estimated") |>
    dplyr::pull(rmspe_pre)
  if (length(brazil_rmspe) != 1L || !is.finite(brazil_rmspe) ||
      brazil_rmspe < 0) {
    stop("UNGA-DM rank distribution lacks a valid Brazil RMSPE.",
         call. = FALSE)
  }
  window_excluded <- full_union_trade_rank |>
    dplyr::filter(
      iso3c %in% units,
      iso3c != "BRA",
      year >= 1997L,
      year <= 2015L,
      china_top_status %in% 1L
    ) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c) |>
    sort()
  legacy_excluded <- full_union_unit_summary |>
    dplyr::filter(
      min_duration_years == 5L,
      sample == "risk_set_restricted",
      ever_treated %in% TRUE,
      iso3c %in% units,
      iso3c != "BRA"
    ) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c) |>
    sort()

  rank_all <- sdid_rank_inference(
    dm_rank_distribution,
    "All valid assignments"
  )
  rank_window <- sdid_rank_inference(
    dm_rank_distribution,
    paste0(
      "Exclude goods-only China-top donor assignments ",
      "(harmonized: window criterion)"
    ),
    keep_units = setdiff(units, window_excluded)
  )
  rank_legacy <- sdid_rank_inference(
    dm_rank_distribution,
    paste0(
      "Exclude goods-only China-top donor assignments ",
      "(legacy 5-year qualifying criterion; audit only)"
    ),
    keep_units = setdiff(units, legacy_excluded)
  )
  rank_fit <- sdid_rank_inference(
    dm_rank_distribution,
    "Pre-fit RMSPE no larger than twice Brazil",
    keep_units = dm_rank_distribution$iso3c[
      dm_rank_distribution$status == "estimated" &
        dm_rank_distribution$rmspe_pre <= 2 * brazil_rmspe
    ]
  )
  rank_inference <- dplyr::bind_rows(
    rank_all,
    rank_window,
    rank_legacy,
    rank_fit
  )
  rank_harmonized <- dplyr::bind_rows(rank_all, rank_window, rank_legacy)

  main_summary <- build_paper_sdid_main_summary_candidate(
    dm_fit,
    dm_se_info,
    dplyr::bind_rows(rank_all, rank_fit),
    dm_panel
  ) |>
    dplyr::mutate(
      specification = "ungadm_no_covariates",
      smoke_test = FALSE,
      source = paste0(
        "UNGA-DM all resolution-related votes; no-covariate ",
        "specification; same replication count and seed as BSV."
      )
    )
  dm_unit_weights_full <- build_paper_sdid_unit_weights_candidate(
    dm_fit,
    dm_panel
  )
  dm_unit_weights <- dm_unit_weights_full |>
    dplyr::select(iso3c, unit_weight)
  bsv_unit_weights <- bsv_outputs$unit_weights |>
    dplyr::select(iso3c, unit_weight)
  weight_overlap <- dm_unit_weights |>
    dplyr::rename(unit_weight_dm = unit_weight) |>
    dplyr::full_join(
      bsv_unit_weights |>
        dplyr::rename(unit_weight_bsv = unit_weight),
      by = "iso3c",
      relationship = "one-to-one"
    ) |>
    dplyr::arrange(iso3c)
  if (anyNA(weight_overlap) || nrow(weight_overlap) != 95L) {
    stop("BSV and UNGA-DM fits must use the same 95 donors.", call. = FALSE)
  }
  dm_time_weights <- build_paper_sdid_time_weights_candidate(dm_fit)
  dm_balance <- build_paper_sdid_balance_candidate(
    dm_panel,
    dm_fit,
    dm_unit_weights_full
  ) |>
    dplyr::mutate(
      label = dplyr::if_else(
        variable == "abs_distance_china",
        "Absolute UNGA ideal-point distance to China (UNGA-DM)",
        label
      ),
      diagnostic_scope = paste0(
        "Omega-weighted pre-treatment values under the UNGA-DM fit; ",
        "descriptive. The preferred specification uses no covariates."
      )
    )

  bsv_summary <- bsv_outputs$main_summary |>
    dplyr::slice(1L)
  if (nrow(bsv_summary) != 1L) {
    stop("BSV candidate main summary must contain exactly one row.",
         call. = FALSE)
  }
  comparison <- dplyr::bind_rows(
    tibble::tibble(
      outcome_source = "BSV Jun/2024 (paper main, no covariates)",
      estimate = bsv_summary$estimate,
      se_placebo = bsv_summary$se_placebo,
      ci_95_low = bsv_summary$ci_95_low,
      ci_95_high = bsv_summary$ci_95_high,
      p_normal_two_sided = bsv_summary$p_normal_two_sided,
      rank_one_sided = bsv_summary$rank_one_sided_negative,
      rank_two_sided = bsv_summary$rank_two_sided_absolute,
      rank_denominator = bsv_summary$rank_denominator,
      p_rank_one_sided = bsv_summary$p_rank_one_sided_negative,
      p_rank_two_sided = bsv_summary$p_rank_two_sided_absolute,
      rmspe_pre = bsv_summary$rmspe_pre,
      brazil_pre_mean = bsv_summary$brazil_pre_treatment_mean,
      estimate_pct_pre_mean = bsv_summary$estimate_as_percent_of_pre_mean,
      se_replications = bsv_summary$se_replications,
      se_seed = bsv_summary$se_seed
    ),
    tibble::tibble(
      outcome_source = paste0(
        "UNGA-DM all resolution-related votes (Fjelstul et al. 2026)"
      ),
      estimate = main_summary$estimate,
      se_placebo = main_summary$se_placebo,
      ci_95_low = main_summary$ci_95_low,
      ci_95_high = main_summary$ci_95_high,
      p_normal_two_sided = main_summary$p_normal_two_sided,
      rank_one_sided = main_summary$rank_one_sided_negative,
      rank_two_sided = main_summary$rank_two_sided_absolute,
      rank_denominator = main_summary$rank_denominator,
      p_rank_one_sided = main_summary$p_rank_one_sided_negative,
      p_rank_two_sided = main_summary$p_rank_two_sided_absolute,
      rmspe_pre = main_summary$rmspe_pre,
      brazil_pre_mean = main_summary$brazil_pre_treatment_mean,
      estimate_pct_pre_mean = main_summary$estimate_as_percent_of_pre_mean,
      se_replications = main_summary$se_replications,
      se_seed = main_summary$se_seed
    )
  )
  inference_notes <- tibble::tibble(
    note = c("se_provenance", "ranks_deterministic"),
    detail = c(
      paste0(
        "BSV and UNGA-DM SEs use ",
        format(main_summary$se_replications, big.mark = ","),
        " replications and seed ", main_summary$se_seed,
        "; the two columns differ only in the outcome series."
      ),
      paste0(
        "Placebo-in-space ranks use no random draws and are exactly ",
        "reproducible regardless of seed."
      )
    )
  )

  list(
    main_summary = main_summary,
    placebo_distribution = dm_rank_distribution,
    rank_inference = rank_inference,
    rank_inference_harmonized = rank_harmonized,
    unit_weights = dm_unit_weights,
    unit_weights_bsv_vs_dm = weight_overlap,
    time_weights = dm_time_weights,
    balance = dm_balance,
    comparison = comparison,
    inference_notes = inference_notes,
    window_excluded = window_excluded,
    legacy_excluded = legacy_excluded
  )
}

ungadm_sdid_baseline_keys <- function() {
  list(
    comparison = "outcome_source",
    placebo_distribution = "iso3c",
    rank_inference_harmonized = "comparison_set",
    unit_weights_bsv_vs_dm = "iso3c"
  )
}

validate_ungadm_sdid_against_baseline <- function(bundle,
                                                   reference_directory,
                                                   tolerance = 1e-12) {
  reference_files <- c(
    comparison = file.path(
      reference_directory,
      "estimation",
      "sdid_comparison_table.csv"
    ),
    placebo_distribution = file.path(
      reference_directory,
      "estimation",
      "sdid_dm_placebo_distribution.csv"
    ),
    rank_inference_harmonized = file.path(
      reference_directory,
      "postreview",
      "sdid_dm_rank_inference_harmonized.csv"
    ),
    unit_weights_bsv_vs_dm = file.path(
      reference_directory,
      "estimation",
      "sdid_unit_weights_bsv_vs_dm.csv"
    )
  )
  keys <- ungadm_sdid_baseline_keys()
  dplyr::bind_rows(lapply(names(keys), function(name) {
    compare_sdid_candidate_frame(
      bundle[[name]],
      reference_files[[name]],
      keys[[name]],
      paste0("ungadm_sdid_", name),
      tolerance
    )
  }))
}

ungadm_sdid_baseline_validation_names <- function() {
  sdid_frame_validation_names(
    paste0("ungadm_sdid_", names(ungadm_sdid_baseline_keys()))
  )
}

build_ungadm_common_window_bundle <- function(
    full_union_row_audit,
    augmented_master,
    common_max_year = 2020L) {
  structural_rows <- full_union_row_audit |>
    dplyr::filter(
      min_duration_years == 5L,
      specification_unit_eligible,
      risk_set_eligible
    ) |>
    dplyr::arrange(iso3c, year)
  if (nrow(structural_rows) == 0L) {
    stop("The structural five-year risk set is empty.", call. = FALSE)
  }
  abort_if_duplicate_keys(
    structural_rows,
    c("iso3c", "year"),
    "structural five-year risk set before outcome filtering"
  )
  dm_outcome <- augmented_master |>
    dplyr::select(
      iso3c,
      year,
      abs_distance_china_dm,
      ungadm_outcome_observed
    )
  joined <- structural_rows |>
    dplyr::left_join(
      dm_outcome,
      by = c("iso3c", "year"),
      relationship = "one-to-one"
    )
  dropped_rows <- joined |>
    dplyr::filter(
      year > common_max_year |
        !ungadm_outcome_observed |
        is.na(abs_distance_china_dm)
    ) |>
    dplyr::count(
      reason = dplyr::if_else(
        year > common_max_year,
        paste0("beyond UNGA-DM endpoint (year > ", common_max_year, ")"),
        "UNGA-DM outcome missing"
      ),
      iso3c,
      name = "n"
    ) |>
    dplyr::arrange(reason, iso3c)
  complete_outcomes <- joined |>
    dplyr::filter(
      year <= common_max_year,
      ungadm_outcome_observed,
      !is.na(abs_distance_china),
      !is.na(abs_distance_china_dm)
    ) |>
    dplyr::arrange(iso3c, year)
  if (nrow(complete_outcomes) == 0L) {
    stop("The BSV/UNGA-DM common-window panel is empty.", call. = FALSE)
  }
  support <- complete_outcomes |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      untreated_observations_common = sum(china_top == 0L),
      treated_observations_common = sum(china_top == 1L),
      .groups = "drop"
    )
  supported <- complete_outcomes |>
    dplyr::left_join(support, by = "iso3c", relationship = "many-to-one") |>
    dplyr::filter(untreated_observations_common >= 5L)
  panel_max <- max(supported$year)
  estimable_treated <- supported |>
    dplyr::filter(
      treatment_role == "treated_qualifying",
      first_treat > 0,
      first_treat < panel_max,
      china_top == 1L
    ) |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c)
  common <- supported |>
    dplyr::filter(
      treatment_role == "never_observed_china_top_control" |
        iso3c %in% estimable_treated
    ) |>
    dplyr::arrange(iso3c, year)
  if (nrow(common) == 0L || length(estimable_treated) == 0L) {
    stop("No estimable treated units remain in the common window.",
         call. = FALSE)
  }
  common <- common |>
    dplyr::mutate(
      country_id = as.integer(as.factor(iso3c)),
      id = country_id
    )
  panel_bsv <- common |>
    dplyr::select(-abs_distance_china_dm, -ungadm_outcome_observed)
  panel_dm <- common |>
    dplyr::mutate(abs_distance_china = abs_distance_china_dm) |>
    dplyr::select(-abs_distance_china_dm, -ungadm_outcome_observed)
  list(
    common_rows = common,
    panel_bsv = as.data.frame(panel_bsv),
    panel_dm = as.data.frame(panel_dm),
    dropped_rows = dropped_rows,
    structural_rows = structural_rows,
    complete_outcomes = complete_outcomes,
    common_max_year = common_max_year
  )
}

validate_ungadm_common_window_bundle <- function(common_bundle) {
  bsv <- tibble::as_tibble(common_bundle$panel_bsv)
  dm <- tibble::as_tibble(common_bundle$panel_dm)
  key_columns <- c("iso3c", "year")
  metadata_columns <- intersect(
    c(
      "china_top", "china_top_status", "treatment_role",
      "qualifying_period", "first_treat", "country_id", "id"
    ),
    names(bsv)
  )
  tibble::tibble(
    validation = c(
      "common_window_nonempty",
      "common_window_unique_keys",
      "common_window_keys_identical",
      "common_window_treatment_metadata_identical",
      "common_window_outcomes_complete",
      "common_window_treatment_binary",
      "common_window_endpoint_respected",
      "risk_set_precedes_outcome_filtering"
    ),
    passed = c(
      nrow(bsv) > 0L && nrow(dm) > 0L,
      anyDuplicated(bsv[key_columns]) == 0L &&
        anyDuplicated(dm[key_columns]) == 0L,
      identical(bsv[key_columns], dm[key_columns]),
      identical(
        dplyr::select(bsv, dplyr::all_of(c(key_columns, metadata_columns))),
        dplyr::select(dm, dplyr::all_of(c(key_columns, metadata_columns)))
      ),
      !anyNA(bsv$abs_distance_china) &&
        !anyNA(dm$abs_distance_china),
      all(bsv$china_top %in% c(0L, 1L)) &&
        identical(bsv$china_top, dm$china_top),
      max(bsv$year) <= common_bundle$common_max_year &&
        max(dm$year) <= common_bundle$common_max_year,
      nrow(common_bundle$structural_rows) >=
        nrow(common_bundle$complete_outcomes) &&
        nrow(common_bundle$complete_outcomes) >= nrow(bsv) &&
        all(common_bundle$complete_outcomes$iso3c %in%
              common_bundle$structural_rows$iso3c)
    ),
    detail = c(
      paste0("rows=", nrow(bsv)),
      "iso3c-year",
      "same ordered row set",
      paste(metadata_columns, collapse = ";"),
      "BSV and UNGA-DM",
      paste0("treated periods=", sum(bsv$china_top == 1L)),
      paste0("max year=", max(bsv$year)),
      paste0(
        "structural=", nrow(common_bundle$structural_rows),
        "; complete=", nrow(common_bundle$complete_outcomes),
        "; estimable=", nrow(bsv)
      )
    )
  )
}

ungadm_common_window_validation_names <- function() {
  c(
    "common_window_nonempty",
    "common_window_unique_keys",
    "common_window_keys_identical",
    "common_window_treatment_metadata_identical",
    "common_window_outcomes_complete",
    "common_window_treatment_binary",
    "common_window_endpoint_respected",
    "risk_set_precedes_outcome_filtering"
  )
}

run_ungadm_fect_cv_candidate <- function(panel, nboots = 10000L) {
  nboots <- as.integer(nboots)
  if (length(nboots) != 1L || is.na(nboots) || nboots < 10000L) {
    stop("Final UNGA-DM CV fits require at least 10,000 bootstraps.",
         call. = FALSE)
  }
  run_fect_analysis(
    panel,
    method = "ife",
    nboots = nboots,
    fml = abs_distance_china ~ china_top
  )
}

run_ungadm_fect_fixed_r_candidate <- function(panel,
                                               r_fixed,
                                               nboots = 10000L) {
  r_fixed <- as.integer(r_fixed)
  nboots <- as.integer(nboots)
  if (length(r_fixed) != 1L || is.na(r_fixed) ||
      !r_fixed %in% c(1L, 2L)) {
    stop("The frozen UNGA-DM grid permits only r = 1 or r = 2.",
         call. = FALSE)
  }
  if (length(nboots) != 1L || is.na(nboots) || nboots < 10000L) {
    stop("Final fixed-r fits require at least 10,000 bootstraps.",
         call. = FALSE)
  }
  set.seed(42L)
  fect_data <- prepare_fect_data(
    panel,
    fml = abs_distance_china ~ china_top
  )
  fect::fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "ife",
    force = "two-way",
    se = TRUE,
    nboots = nboots,
    parallel = FALSE,
    CV = FALSE,
    r = r_fixed
  )
}

ungadm_ife_summary_row <- function(label, fit, panel, nboots) {
  summary <- summarize_fect_model(
    fit,
    panel,
    fml = abs_distance_china ~ china_top
  )
  tibble::tibble(
    variant = label,
    att = summary$att,
    se = summary$se,
    ci_lo = summary$ci_lo,
    ci_hi = summary$ci_hi,
    p = summary$p,
    r_cv = summary$r_cv,
    att_rel_pct = summary$att_rel_pct,
    att_sd_units = summary$att_sd_units,
    n_obs = summary$n_obs,
    n_countries = summary$n_countries,
    n_treated = summary$n_treated,
    n_control = summary$n_control,
    panel_min = summary$panel_min,
    panel_max = summary$panel_max,
    nboots = as.integer(nboots)
  )
}

build_ungadm_ife_comparison_candidate <- function(
    full_union_model_results,
    bsv_common_fit,
    dm_common_fit,
    common_bundle,
    nboots = 10000L) {
  full <- full_union_model_results |>
    dplyr::filter(
      min_duration_years == 5L,
      specification == "risk_set_restricted"
    ) |>
    dplyr::slice_head(n = 2L)
  if (nrow(full) != 1L) {
    stop("Corrected full-window IFE summary must contain exactly one row.",
         call. = FALSE)
  }
  full_nboots <- if ("nboots" %in% names(full)) {
    as.integer(full$nboots)
  } else {
    as.integer(nboots)
  }
  full_row <- tibble::tibble(
    variant = paste0(
      "BSV corrected full-union window ", full$panel_min, "-",
      full$panel_max, " (paper candidate)"
    ),
    att = full$att,
    se = full$se,
    ci_lo = full$ci_lo,
    ci_hi = full$ci_hi,
    p = full$p,
    r_cv = full$r_cv,
    att_rel_pct = full$att_rel_pct,
    att_sd_units = full$att_sd_units,
    n_obs = full$n_obs,
    n_countries = full$n_countries,
    n_treated = full$n_treated,
    n_control = full$n_control,
    panel_min = full$panel_min,
    panel_max = full$panel_max,
    nboots = full_nboots
  )
  dplyr::bind_rows(
    full_row,
    ungadm_ife_summary_row(
      "BSV common window (<= 2020, identical rows)",
      bsv_common_fit,
      common_bundle$panel_bsv,
      nboots
    ),
    ungadm_ife_summary_row(
      "UNGA-DM common window (<= 2020, identical rows)",
      dm_common_fit,
      common_bundle$panel_dm,
      nboots
    )
  )
}

ungadm_ife_dynamic_table <- function(fit, label) {
  tibble::tibble(
    variant = label,
    event_time = fit$time,
    count = fit$count,
    att = as.numeric(fit$est.att[, 1]),
    se = as.numeric(fit$est.att[, 2])
  ) |>
    dplyr::mutate(
      ci_lo = att - 1.96 * se,
      ci_hi = att + 1.96 * se
    )
}

build_ungadm_ife_dynamic_candidate <- function(bsv_fit, dm_fit) {
  dplyr::bind_rows(
    ungadm_ife_dynamic_table(bsv_fit, "BSV common window"),
    ungadm_ife_dynamic_table(dm_fit, "UNGA-DM common window")
  )
}

build_ungadm_ife_fixed_grid_candidate <- function(fits,
                                                   common_bundle,
                                                   bsv_cv_fit,
                                                   dm_cv_fit,
                                                   nboots = 10000L) {
  expected <- c("bsv_r1", "bsv_r2", "dm_r1", "dm_r2")
  if (!identical(names(fits), expected)) {
    stop("Fixed-r fits must follow bsv_r1, bsv_r2, dm_r1, dm_r2.",
         call. = FALSE)
  }
  metadata <- tibble::tribble(
    ~fit_name, ~outcome, ~r_fixed,
    "bsv_r1", "BSV", 1L,
    "bsv_r2", "BSV", 2L,
    "dm_r1", "UNGA-DM", 1L,
    "dm_r2", "UNGA-DM", 2L
  )
  cv_selected <- c(BSV = as.integer(bsv_cv_fit$r.cv),
                   `UNGA-DM` = as.integer(dm_cv_fit$r.cv))
  dplyr::bind_rows(lapply(seq_len(nrow(metadata)), function(index) {
    row <- metadata[index, ]
    panel <- if (row$outcome == "BSV") {
      common_bundle$panel_bsv
    } else {
      common_bundle$panel_dm
    }
    summary <- summarize_fect_model(
      fits[[row$fit_name]],
      panel,
      fml = abs_distance_china ~ china_top
    )
    tibble::tibble(
      outcome = row$outcome,
      r_fixed = row$r_fixed,
      cv_selected = row$r_fixed == cv_selected[[row$outcome]],
      att = summary$att,
      se = summary$se,
      ci_lo = summary$ci_lo,
      ci_hi = summary$ci_hi,
      p = summary$p,
      att_rel_pct = summary$att_rel_pct,
      att_sd_units = summary$att_sd_units,
      n_obs = summary$n_obs,
      nboots = as.integer(nboots),
      smoke_test = FALSE
    )
  }))
}

ungadm_fit_fect_point <- function(panel, r_fixed) {
  r_fixed <- as.integer(r_fixed)
  if (length(r_fixed) != 1L || is.na(r_fixed) ||
      !r_fixed %in% c(1L, 2L)) {
    stop("Paired-bootstrap point fits permit only r = 1 or r = 2.",
         call. = FALSE)
  }
  fect_data <- prepare_fect_data(
    panel,
    fml = abs_distance_china ~ china_top
  )
  fit <- fect::fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "ife",
    force = "two-way",
    se = FALSE,
    parallel = FALSE,
    CV = FALSE,
    r = r_fixed
  )
  as.numeric(fit$att.avg)
}

ungadm_paired_bootstrap_one <- function(index,
                                         draw,
                                         common_rows,
                                         boot_seed,
                                         fit_function) {
  set.seed(as.integer(boot_seed + index))
  resampled <- dplyr::bind_rows(lapply(seq_along(draw), function(k) {
    common_rows |>
      dplyr::filter(iso3c == draw[[k]]) |>
      dplyr::mutate(
        iso3c = paste0(draw[[k]], "_", k),
        country_id = as.integer(k),
        id = as.integer(k),
        country_name = iso3c
      )
  }))
  panel_bsv <- resampled |>
    dplyr::select(-abs_distance_china_dm, -ungadm_outcome_observed)
  panel_dm <- resampled |>
    dplyr::mutate(abs_distance_china = abs_distance_china_dm) |>
    dplyr::select(-abs_distance_china_dm, -ungadm_outcome_observed)
  tryCatch({
    att_bsv_r2 <- fit_function(panel_bsv, 2L)
    att_dm_r1 <- fit_function(panel_dm, 1L)
    att_dm_r2 <- fit_function(panel_dm, 2L)
    estimates <- c(att_bsv_r2, att_dm_r1, att_dm_r2)
    if (any(!is.finite(estimates))) {
      stop("point fit returned a nonfinite ATT")
    }
    tibble::tibble(
      b = as.integer(index),
      status = "ok",
      att_bsv_r2 = att_bsv_r2,
      att_dm_r1 = att_dm_r1,
      att_dm_r2 = att_dm_r2,
      diff_procedure = att_dm_r1 - att_bsv_r2,
      diff_common_r2 = att_dm_r2 - att_bsv_r2
    )
  }, error = function(error) {
    tibble::tibble(
      b = as.integer(index),
      status = paste0("error: ", conditionMessage(error)),
      att_bsv_r2 = NA_real_,
      att_dm_r1 = NA_real_,
      att_dm_r2 = NA_real_,
      diff_procedure = NA_real_,
      diff_common_r2 = NA_real_
    )
  })
}

ungadm_paired_bootstrap_columns <- function() {
  c(
    "b", "status", "att_bsv_r2", "att_dm_r1", "att_dm_r2",
    "diff_procedure", "diff_common_r2"
  )
}

ungadm_paired_checkpoint_valid <- function(distribution, B) {
  columns <- ungadm_paired_bootstrap_columns()
  if (!is.data.frame(distribution) ||
      !identical(names(distribution), columns) ||
      !is.integer(distribution$b) ||
      !is.character(distribution$status) ||
      anyNA(distribution$b) || anyNA(distribution$status) ||
      anyDuplicated(distribution$b) ||
      any(!distribution$b %in% seq_len(B)) ||
      any(!grepl("^(ok|error: .+)$", distribution$status))) {
    return(FALSE)
  }
  numeric_columns <- setdiff(columns, c("b", "status"))
  if (!all(vapply(distribution[numeric_columns], is.numeric, logical(1)))) {
    return(FALSE)
  }
  ok <- distribution$status == "ok"
  error <- !ok
  all(vapply(distribution[numeric_columns], function(value) {
    all(is.finite(value[ok])) && all(is.na(value[error]))
  }, logical(1)))
}

ungadm_paired_code_fingerprint <- function(fit_function) {
  digest::digest(
    list(
      deparse(body(ungadm_paired_bootstrap_one)),
      deparse(body(ungadm_paired_checkpoint_valid)),
      deparse(body(ungadm_paired_bootstrap_columns)),
      deparse(body(sdid_read_checkpoint)),
      deparse(body(sdid_atomic_save_rds)),
      deparse(body(sdid_mclapply_checked)),
      deparse(body(prepare_fect_data)),
      deparse(body(fit_function)),
      as.character(utils::packageVersion("fect"))
    ),
    algo = "sha256",
    serialize = TRUE
  )
}

run_ungadm_paired_bootstrap_candidate <- function(
    common_rows,
    B = 1000L,
    boot_seed = 20260823L,
    checkpoint_block = "ungadm_ife_paired",
    checkpoint_directory = NULL,
    core_cap = 12L,
    batch_size = 24L,
    fit_function = ungadm_fit_fect_point) {
  B <- as.integer(B)
  boot_seed <- as.integer(boot_seed)
  batch_size <- as.integer(batch_size)
  if (length(B) != 1L || is.na(B) || B < 1L ||
      length(boot_seed) != 1L || is.na(boot_seed) ||
      length(batch_size) != 1L || is.na(batch_size) || batch_size < 1L) {
    stop("Invalid paired-bootstrap controls.", call. = FALSE)
  }
  required <- c(
    "iso3c", "year", "china_top", "abs_distance_china",
    "abs_distance_china_dm"
  )
  ungadm_require_columns(common_rows, required, "paired-bootstrap rows")
  if (anyNA(common_rows[required]) ||
      any(!common_rows$china_top %in% c(0L, 1L))) {
    stop("Paired-bootstrap rows contain invalid analysis values.",
         call. = FALSE)
  }
  unit_status <- common_rows |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(treated = any(china_top == 1L), .groups = "drop")
  treated_ids <- unit_status$iso3c[unit_status$treated]
  control_ids <- unit_status$iso3c[!unit_status$treated]
  if (length(treated_ids) == 0L || length(control_ids) == 0L) {
    stop("Paired bootstrap requires treated and control countries.",
         call. = FALSE)
  }
  set.seed(boot_seed)
  draws <- lapply(seq_len(B), function(index) {
    c(
      sample(treated_ids, length(treated_ids), replace = TRUE),
      sample(control_ids, length(control_ids), replace = TRUE)
    )
  })
  fingerprint <- digest::digest(
    list(
      code = ungadm_paired_code_fingerprint(fit_function),
      B = B,
      boot_seed = boot_seed,
      draws = draws,
      data = common_rows |>
        dplyr::arrange(iso3c, year) |>
        dplyr::select(dplyr::all_of(required))
    ),
    algo = "sha256",
    serialize = TRUE
  )
  if (is.null(checkpoint_directory)) {
    checkpoint_directory <- sdid_candidate_checkpoint_directory(
      checkpoint_block
    )
  } else {
    dir.create(checkpoint_directory, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(checkpoint_directory)) {
      stop("Could not create paired-bootstrap checkpoint directory.",
           call. = FALSE)
    }
  }
  checkpoint_path <- file.path(
    checkpoint_directory,
    paste0("paired_ife_b", B, ".rds")
  )
  distribution <- tibble::tibble(
    b = integer(),
    status = character(),
    att_bsv_r2 = numeric(),
    att_dm_r1 = numeric(),
    att_dm_r2 = numeric(),
    diff_procedure = numeric(),
    diff_common_r2 = numeric()
  )
  if (file.exists(checkpoint_path)) {
    cached <- sdid_read_checkpoint(checkpoint_path)
    cache_valid <- is.list(cached) &&
      identical(cached$fingerprint, fingerprint) &&
      ungadm_paired_checkpoint_valid(cached$distribution, B)
    if (cache_valid) {
      distribution <- cached$distribution |>
        dplyr::filter(status == "ok") |>
        dplyr::arrange(b)
      if (nrow(distribution) == B &&
          identical(distribution$b, seq_len(B))) {
        message("    Reusing completed paired-bootstrap checkpoint: ",
                basename(checkpoint_path))
        return(distribution)
      }
      message("    Resuming paired bootstrap with ", nrow(distribution),
              "/", B, " successful draws.")
    }
  }
  remaining <- setdiff(seq_len(B), distribution$b)
  batches <- split(remaining, ceiling(seq_along(remaining) / batch_size))
  sdid_limit_blas_threads()
  cores <- sdid_available_cores(core_cap)
  for (batch_index in seq_along(batches)) {
    batch <- batches[[batch_index]]
    values <- sdid_mclapply_checked(
      batch,
      function(index) {
        ungadm_paired_bootstrap_one(
          index,
          draws[[index]],
          common_rows,
          boot_seed,
          fit_function
        )
      },
      cores,
      what = "UNGA-DM paired bootstrap"
    )
    batch_rows <- dplyr::bind_rows(values)
    if (!ungadm_paired_checkpoint_valid(batch_rows, B) ||
        !identical(sort(batch_rows$b), sort(as.integer(batch)))) {
      stop("Invalid paired-bootstrap result batch.", call. = FALSE)
    }
    distribution <- dplyr::bind_rows(distribution, batch_rows) |>
      dplyr::arrange(b)
    sdid_atomic_save_rds(
      list(
        fingerprint = fingerprint,
        distribution = distribution,
        updated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
      ),
      checkpoint_path
    )
  }
  if (!ungadm_paired_checkpoint_valid(distribution, B) ||
      nrow(distribution) != B ||
      !identical(distribution$b, seq_len(B))) {
    stop("Paired bootstrap did not return the complete draw index.",
         call. = FALSE)
  }
  failed <- distribution |>
    dplyr::filter(status != "ok")
  if (nrow(failed) > 0L) {
    stop(
      "Paired bootstrap failed for draw(s) ",
      paste(failed$b, collapse = ", "),
      ". Error rows remain checkpointed and will be retried.",
      call. = FALSE
    )
  }
  distribution
}

ungadm_summarize_bootstrap_difference <- function(values,
                                                   label,
                                                   observed_difference,
                                                   B) {
  values <- values[is.finite(values)]
  if (length(values) < 2L) {
    stop("Too few valid paired-bootstrap differences.", call. = FALSE)
  }
  standard_error <- stats::sd(values)
  tibble::tibble(
    contrast = label,
    observed_diff = observed_difference,
    boot_mean = mean(values),
    boot_sd = standard_error,
    ci_2_5 = unname(stats::quantile(values, 0.025)),
    ci_97_5 = unname(stats::quantile(values, 0.975)),
    p_two_sided_percentile = 2 * min(mean(values <= 0), mean(values >= 0)),
    p_two_sided_normal = 2 * stats::pnorm(
      -abs(observed_difference / standard_error)
    ),
    n_valid = length(values),
    n_failed = as.integer(B - length(values))
  )
}

build_ungadm_paired_bootstrap_summary_candidate <- function(draws,
                                                             fixed_grid,
                                                             B = 1000L) {
  extract_att <- function(outcome, r_fixed) {
    value <- fixed_grid |>
      dplyr::filter(
        .data$outcome == outcome,
        .data$r_fixed == r_fixed
      ) |>
      dplyr::pull(att)
    if (length(value) != 1L || !is.finite(value)) {
      stop("Fixed-r grid lacks a unique finite ATT.", call. = FALSE)
    }
    value
  }
  bsv_r2 <- extract_att("BSV", 2L)
  dm_r1 <- extract_att("UNGA-DM", 1L)
  dm_r2 <- extract_att("UNGA-DM", 2L)
  dplyr::bind_rows(
    ungadm_summarize_bootstrap_difference(
      draws$diff_procedure,
      "UNGA-DM (r=1) minus BSV (r=2), procedure-selected",
      dm_r1 - bsv_r2,
      B
    ),
    ungadm_summarize_bootstrap_difference(
      draws$diff_common_r2,
      "UNGA-DM (r=2) minus BSV (r=2), common factors",
      dm_r2 - bsv_r2,
      B
    )
  )
}

build_ungadm_series_diagnostics_candidate <- function(common_rows) {
  treated_ids <- common_rows |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(treated = any(china_top == 1L), .groups = "drop") |>
    dplyr::filter(treated) |>
    dplyr::pull(iso3c)
  divergence <- common_rows |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      treated_unit = any(china_top == 1L),
      first_treated_year = if (any(china_top == 1L)) {
        min(year[china_top == 1L])
      } else NA_integer_,
      n_years = dplyr::n(),
      cor_bsv_dm = if (dplyr::n() >= 3L) {
        stats::cor(abs_distance_china, abs_distance_china_dm)
      } else NA_real_,
      mean_abs_diff = mean(abs(abs_distance_china - abs_distance_china_dm)),
      mean_bsv_pre = mean(abs_distance_china[china_top == 0L]),
      mean_dm_pre = mean(abs_distance_china_dm[china_top == 0L]),
      mean_bsv_treated = if (any(china_top == 1L)) {
        mean(abs_distance_china[china_top == 1L])
      } else NA_real_,
      mean_dm_treated = if (any(china_top == 1L)) {
        mean(abs_distance_china_dm[china_top == 1L])
      } else NA_real_,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      within_change_bsv = mean_bsv_treated - mean_bsv_pre,
      within_change_dm = mean_dm_treated - mean_dm_pre
    ) |>
    dplyr::arrange(dplyr::desc(treated_unit), dplyr::desc(mean_abs_diff))
  group_means <- common_rows |>
    dplyr::mutate(
      group = dplyr::if_else(
        iso3c %in% treated_ids,
        "ever-treated",
        "control"
      )
    ) |>
    dplyr::group_by(group, year) |>
    dplyr::summarise(
      mean_bsv = mean(abs_distance_china),
      mean_dm = mean(abs_distance_china_dm),
      .groups = "drop"
    )
  list(divergence = divergence, group_means = group_means)
}

ungadm_ife_validation_names <- function() {
  c(
    "ife_comparison_has_three_variants",
    "ife_corrected_full_union_sample",
    "ife_common_rows_identical",
    "ife_inference_is_finite",
    "ife_dynamic_has_both_outcomes",
    "ife_fixed_grid_is_complete",
    "ife_fixed_grid_not_smoke",
    "ife_paired_draws_complete",
    "ife_paired_draws_successful",
    "ife_paired_summary_complete",
    "ife_divergence_unique_countries",
    "ife_group_means_unique_group_year"
  )
}

validate_ungadm_ife_outputs <- function(comparison,
                                        dynamic,
                                        fixed_grid,
                                        paired_draws,
                                        paired_summary,
                                        series_diagnostics,
                                        common_bundle,
                                        B = 1000L) {
  common_keys_identical <- identical(
    dplyr::select(common_bundle$panel_bsv, iso3c, year),
    dplyr::select(common_bundle$panel_dm, iso3c, year)
  )
  inference_columns <- c("att", "se", "ci_lo", "ci_hi", "p")
  tibble::tibble(
    validation = ungadm_ife_validation_names(),
    passed = c(
      nrow(comparison) == 3L &&
        dplyr::n_distinct(comparison$variant) == 3L,
      comparison$n_obs[[1]] == 5002L &&
        comparison$n_countries[[1]] == 160L &&
        comparison$n_treated[[1]] == 35L &&
        comparison$n_control[[1]] == 125L,
      common_keys_identical &&
        comparison$n_obs[[2]] == comparison$n_obs[[3]] &&
        comparison$n_countries[[2]] == comparison$n_countries[[3]],
      all(vapply(comparison[inference_columns], function(value) {
        all(is.finite(value))
      }, logical(1))),
      setequal(dynamic$variant,
               c("BSV common window", "UNGA-DM common window")) &&
        all(is.finite(dynamic$att)) && all(is.finite(dynamic$se)),
      nrow(fixed_grid) == 4L &&
        setequal(paste(fixed_grid$outcome, fixed_grid$r_fixed),
                 c("BSV 1", "BSV 2", "UNGA-DM 1", "UNGA-DM 2")) &&
        all(fixed_grid$nboots >= 10000L),
      all(fixed_grid$smoke_test %in% FALSE),
      nrow(paired_draws) == B &&
        identical(paired_draws$b, seq_len(B)),
      all(paired_draws$status == "ok") &&
        all(vapply(
          paired_draws[setdiff(
            ungadm_paired_bootstrap_columns(),
            c("b", "status")
          )],
          function(value) all(is.finite(value)),
          logical(1)
        )),
      nrow(paired_summary) == 2L &&
        all(paired_summary$n_valid == B) &&
        all(paired_summary$n_failed == 0L),
      anyDuplicated(series_diagnostics$divergence$iso3c) == 0L &&
        setequal(series_diagnostics$divergence$iso3c,
                 common_bundle$common_rows$iso3c),
      anyDuplicated(
        series_diagnostics$group_means[c("group", "year")]
      ) == 0L &&
        setequal(series_diagnostics$group_means$group,
                 c("ever-treated", "control"))
    ),
    detail = c(
      paste0("variants=", nrow(comparison)),
      paste0(
        comparison$n_obs[[1]], "/", comparison$n_countries[[1]], "/",
        comparison$n_treated[[1]], "/", comparison$n_control[[1]]
      ),
      paste0("common rows=", comparison$n_obs[[2]]),
      paste(inference_columns, collapse = ";"),
      paste(sort(unique(dynamic$variant)), collapse = ";"),
      paste(paste(fixed_grid$outcome, fixed_grid$r_fixed), collapse = ";"),
      paste(unique(fixed_grid$smoke_test), collapse = ";"),
      paste0("draws=", nrow(paired_draws)),
      paste0("failures=", sum(paired_draws$status != "ok")),
      paste0("summary rows=", nrow(paired_summary)),
      paste0("countries=", nrow(series_diagnostics$divergence)),
      paste0("group-year rows=", nrow(series_diagnostics$group_means))
    )
  )
}

write_ungadm_table_candidate <- function(table, output_path) {
  if (!is.data.frame(table)) {
    stop("UNGA-DM table output must be a data frame.", call. = FALSE)
  }
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(table, output_path)
  normalizePath(output_path, mustWork = TRUE)
}

write_ungadm_tables_candidate <- function(bundle, output_directory) {
  if (!is.list(bundle) || is.null(names(bundle)) ||
      any(!nzchar(names(bundle))) || anyDuplicated(names(bundle)) ||
      any(!vapply(bundle, is.data.frame, logical(1)))) {
    stop("Named UNGA-DM output bundle must contain only data frames.",
         call. = FALSE)
  }
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  unname(vapply(names(bundle), function(name) {
    path <- file.path(output_directory, paste0(name, ".csv"))
    readr::write_csv(bundle[[name]], path)
    normalizePath(path, mustWork = TRUE)
  }, character(1)))
}

write_ungadm_placebo_figure_candidate <- function(distribution,
                                                   output_path) {
  brazil <- distribution |>
    dplyr::filter(iso3c == "BRA", status == "estimated")
  if (nrow(brazil) != 1L || !is.finite(brazil$estimate)) {
    stop("Placebo distribution lacks a unique finite Brazil estimate.",
         call. = FALSE)
  }
  plot <- distribution |>
    dplyr::filter(status == "estimated") |>
    ggplot2::ggplot(ggplot2::aes(x = estimate)) +
    ggplot2::geom_histogram(bins = 24L, fill = "#4C78A8", colour = "white") +
    ggplot2::geom_vline(
      xintercept = brazil$estimate,
      colour = "#B22222",
      linewidth = 0.7,
      linetype = "dashed"
    ) +
    ggplot2::labs(
      x = "Placebo-in-space SDiD estimate",
      y = "Number of assignments",
      title = "UNGA-DM placebo-in-space distribution",
      subtitle = "Dashed line: Brazil"
    ) +
    ggplot2::theme_minimal(base_size = 11)
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(output_path, plot, width = 7, height = 4.5, dpi = 300)
  normalizePath(output_path, mustWork = TRUE)
}

write_ungadm_equivalence_plot_candidate <- function(fit, output_path) {
  plot <- plot(
    fit,
    type = "equiv",
    main = "Equivalence test: corrected goods-only status-current IFE",
    cex.legend = 0.7
  )
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(output_path, plot, width = 8, height = 5, dpi = 300)
  normalizePath(output_path, mustWork = TRUE)
}
