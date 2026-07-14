options(scipen = 999)

set.seed(12345)

set_utf8_locale <- function() {
  for (locale in c("pt_BR.UTF-8", "en_US.UTF-8", "UTF-8")) {
    result <- suppressWarnings(try(Sys.setlocale("LC_CTYPE", locale), silent = TRUE))
    if (!inherits(result, "try-error") && !is.na(result) && nzchar(result)) {
      return(invisible(result))
    }
  }
  invisible(Sys.getlocale("LC_CTYPE"))
}

set_utf8_locale()

required_sdid_covariates <- function(data) {
  candidate_covariates <- c(
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
    "inst_parliamentary",
    "inst_military_exec",
    "us_trade_agreement"
  )
  intersect(candidate_covariates, names(data))
}

sdid_variable_dictionary <- function() {
  tibble::tribble(
    ~variable, ~label, ~role,
    "abs_distance_china", "Absolute UNGA ideal-point distance to China", "Outcome",
    "gpi", "Global Power Index", "Main covariate",
    "abs_distance_usa", "Absolute UNGA ideal-point distance to the United States", "Available outcome/covariate diagnostic",
    "perc_trade_with_us", "Export share to the United States", "Main covariate",
    "perc_trade_with_china", "Export share to China", "Main covariate",
    "pci_cur", "Per-capita income", "Main covariate",
    "exachange_rate", "Exchange rate", "Main covariate",
    "distance_us", "Geographic distance to Washington", "Main covariate",
    "us_power_gap", "Power gap to the United States", "Main covariate",
    "hog_left", "Head of government is left", "Main covariate",
    "CA_GDP", "Current account balance (% GDP)", "Main covariate",
    "govdef_GDP", "Government budget deficit (% GDP)", "Main covariate",
    "inst_parliamentary", "Parliamentary system", "Institutional covariate",
    "inst_military_exec", "Military executive", "Institutional covariate",
    "us_trade_agreement", "Trade agreement with the United States", "Institutional covariate",
    "latin_america", "Latin America and Caribbean donor indicator", "Available grouping variable"
  )
}

safe_tar_read <- function(name, store = "_targets") {
  tryCatch(
    targets::tar_read_raw(name, store = store),
    error = function(e) {
      structure(
        list(name = name, error = conditionMessage(e)),
        class = "sdid_tar_read_error"
      )
    }
  )
}

is_tar_error <- function(x) {
  inherits(x, "sdid_tar_read_error")
}

object_audit_row <- function(name, object) {
  if (is_tar_error(object)) {
    return(tibble::tibble(
      object = name,
      status = "read_error",
      class = "sdid_tar_read_error",
      nrow = NA_integer_,
      ncol = NA_integer_,
      length = NA_integer_,
      columns = "",
      error = object$error
    ))
  }

  tibble::tibble(
    object = name,
    status = "read",
    class = paste(class(object), collapse = ";"),
    nrow = if (is.data.frame(object)) nrow(object) else NA_integer_,
    ncol = if (is.data.frame(object)) ncol(object) else NA_integer_,
    length = length(object),
    columns = if (is.data.frame(object)) paste(names(object), collapse = ";") else "",
    error = ""
  )
}

markdown_table <- function(data, digits = 3, max_rows = Inf) {
  data <- as.data.frame(data)
  if (nrow(data) == 0L) {
    return("_No rows._")
  }

  if (is.finite(max_rows)) {
    data <- utils::head(data, max_rows)
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
    display[[col]] <- stringr::str_replace_all(display[[col]], "\\|", "/")
  }

  header <- paste0("| ", paste(names(display), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(display)), collapse = " | "), " |")
  rows <- apply(display, 1, function(x) paste0("| ", paste(x, collapse = " | "), " |"))
  paste(c(header, separator, rows), collapse = "\n")
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", paste0(formatC(x, digits = digits, format = "f"), "%"))
}

save_plot_pair <- function(plot, png_path, pdf_path, width, height) {
  ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = 320)
  ggplot2::ggsave(pdf_path, plot, width = width, height = height)
}

make_sdid_covariate_array <- function(data, covariates = required_sdid_covariates(data)) {
  unit_order <- data |>
    dplyr::distinct(iso3c) |>
    dplyr::pull(iso3c)
  year_order <- sort(unique(data$year))

  if (length(covariates) == 0L) {
    stop("No SDiD covariates found in the input data.")
  }

  covariates_array <- array(
    NA_real_,
    dim = c(length(unit_order), length(year_order), length(covariates)),
    dimnames = list(unit_order, as.character(year_order), covariates)
  )

  for (covariate in covariates) {
    covariate_wide <- data |>
      dplyr::select(iso3c, year, dplyr::all_of(covariate)) |>
      dplyr::mutate(.unit_order = match(iso3c, unit_order)) |>
      dplyr::arrange(.unit_order, year) |>
      tidyr::pivot_wider(names_from = year, values_from = dplyr::all_of(covariate)) |>
      dplyr::arrange(.unit_order)

    covariate_matrix <- covariate_wide |>
      dplyr::select(dplyr::all_of(as.character(year_order))) |>
      as.matrix()

    covariates_array[, , covariate] <- covariate_matrix
  }

  if (anyNA(covariates_array)) {
    stop("The SDiD covariate array contains missing values.")
  }

  covariates_array
}

prepare_sdid_panel <- function(data,
                               year_start = 1997L,
                               year_end = 2015L,
                               treated_iso3c = "BRA",
                               treatment_start = 2009L,
                               exclude_iso3c = character(),
                               latin_america_only = FALSE) {
  panel <- data |>
    dplyr::filter(
      year >= year_start,
      year <= year_end,
      !iso3c %in% exclude_iso3c
    )

  if (latin_america_only) {
    panel <- panel |>
      dplyr::filter(latin_america | iso3c == treated_iso3c)
  }

  if (!treated_iso3c %in% panel$iso3c) {
    stop("The treated unit is not present after filtering: ", treated_iso3c)
  }

  required_years <- seq.int(year_start, year_end)
  incomplete_units <- panel |>
    dplyr::count(iso3c, name = "n_years") |>
    dplyr::filter(n_years != length(required_years)) |>
    dplyr::pull(iso3c)

  if (length(incomplete_units) > 0L) {
    stop(
      "The SDiD panel is incomplete for units: ",
      paste(utils::head(incomplete_units, 10), collapse = ", ")
    )
  }

  covariates <- required_sdid_covariates(panel)
  required_columns <- c("iso3c", "year", "abs_distance_china", covariates)
  missing_columns <- setdiff(required_columns, names(panel))
  if (length(missing_columns) > 0L) {
    stop("Missing required SDiD columns: ", paste(missing_columns, collapse = ", "))
  }

  missing_values <- panel |>
    dplyr::select(dplyr::all_of(required_columns)) |>
    is.na() |>
    any()
  if (missing_values) {
    stop("Missing values detected in the SDiD panel outcome or covariates.")
  }

  panel <- panel |>
    dplyr::mutate(
      treatment = as.integer(iso3c == treated_iso3c & year >= treatment_start),
      .unit_treated = as.integer(iso3c == treated_iso3c)
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)

  covariate_array <- make_sdid_covariate_array(panel, covariates)

  panel_for_sdid <- panel |>
    dplyr::mutate(
      iso3c = factor(iso3c, levels = unique(iso3c)),
      year = as.integer(year),
      Y = abs_distance_china
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()

  setup <- synthdid::panel.matrices(panel_for_sdid)

  list(
    panel = panel,
    setup = setup,
    covariates = covariate_array
  )
}

fit_sdid_from_panel <- function(data,
                                year_start = 1997L,
                                year_end = 2015L,
                                treated_iso3c = "BRA",
                                treatment_start = 2009L,
                                exclude_iso3c = character(),
                                latin_america_only = FALSE) {
  prepared <- prepare_sdid_panel(
    data = data,
    year_start = year_start,
    year_end = year_end,
    treated_iso3c = treated_iso3c,
    treatment_start = treatment_start,
    exclude_iso3c = exclude_iso3c,
    latin_america_only = latin_america_only
  )

  synthdid::synthdid_estimate(
    Y = prepared$setup$Y,
    N0 = prepared$setup$N0,
    T0 = prepared$setup$T0,
    X = prepared$covariates
  )
}

fit_sdid_safely <- function(...) {
  tryCatch(
    fit_sdid_from_panel(...),
    error = function(e) {
      structure(list(error = conditionMessage(e)), class = "sdid_fit_error")
    }
  )
}

is_fit_error <- function(x) {
  inherits(x, "sdid_fit_error")
}

extract_sdid_series <- function(fit) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  omega <- as.numeric(weights$omega)
  lambda <- as.numeric(weights$lambda)
  year <- as.integer(colnames(setup$Y))
  treated_row <- setup$N0 + 1L

  controls <- setup$Y[seq_len(setup$N0), , drop = FALSE]
  observed <- as.numeric(setup$Y[treated_row, ])
  synthetic <- as.numeric(t(omega) %*% controls)

  tibble::tibble(
    year = year,
    period = dplyr::if_else(seq_along(year) <= setup$T0, "Pre-treatment", "Post-treatment"),
    brazil_observed = observed,
    synthetic_control = synthetic,
    gap = observed - synthetic,
    time_weight = c(lambda, rep(NA_real_, length(year) - length(lambda)))
  )
}

summarise_sdid_fit <- function(fit, label = "Baseline") {
  if (is_fit_error(fit)) {
    return(tibble::tibble(
      specification = label,
      estimate = NA_real_,
      rmspe_pre = NA_real_,
      rmspe_post = NA_real_,
      rmspe_ratio = NA_real_,
      n_units = NA_integer_,
      n_donors = NA_integer_,
      n_pre_years = NA_integer_,
      n_post_years = NA_integer_,
      status = "error",
      error = fit$error
    ))
  }

  setup <- attr(fit, "setup")
  series <- extract_sdid_series(fit)
  pre_gap <- series$gap[series$period == "Pre-treatment"]
  pre_gap_intercept <- mean(pre_gap, na.rm = TRUE)
  adjusted_gap <- series$gap - pre_gap_intercept
  rmspe_pre <- sqrt(mean(adjusted_gap[series$period == "Pre-treatment"]^2))
  rmspe_post <- sqrt(mean(adjusted_gap[series$period == "Post-treatment"]^2))

  tibble::tibble(
    specification = label,
    estimate = as.numeric(fit),
    rmspe_pre = rmspe_pre,
    rmspe_post = rmspe_post,
    rmspe_ratio = rmspe_post / rmspe_pre,
    n_units = nrow(setup$Y),
    n_donors = setup$N0,
    n_pre_years = setup$T0,
    n_post_years = ncol(setup$Y) - setup$T0,
    status = "estimated",
    error = ""
  )
}

extract_unit_weights <- function(fit, synth_data) {
  setup <- attr(fit, "setup")
  weights <- attr(fit, "weights")
  donor_units <- rownames(setup$Y)[seq_len(setup$N0)]
  uniform_weight <- 1 / setup$N0

  donor_metadata <- synth_data |>
    dplyr::distinct(iso3c, latin_america) |>
    dplyr::mutate(
      country_name = countrycode::countrycode(iso3c, "iso3c", "country.name"),
      region = countrycode::countrycode(iso3c, "iso3c", "region")
    ) |>
    dplyr::select(iso3c, country_name, region, latin_america)

  tibble::tibble(
    iso3c = donor_units,
    unit_weight = as.numeric(weights$omega)
  ) |>
    dplyr::left_join(donor_metadata, by = "iso3c") |>
    dplyr::arrange(dplyr::desc(unit_weight), iso3c) |>
    dplyr::mutate(
      weight_rank = dplyr::row_number(),
      cumulative_weight = cumsum(unit_weight),
      relative_to_uniform_weight = unit_weight / uniform_weight,
      high_weight_top10 = weight_rank <= 10L,
      high_weight_2x_uniform = unit_weight >= 2 * uniform_weight,
      high_weight_donor = high_weight_top10 | high_weight_2x_uniform
    ) |>
    dplyr::select(
      weight_rank,
      iso3c,
      country_name,
      region,
      latin_america,
      unit_weight,
      cumulative_weight,
      relative_to_uniform_weight,
      high_weight_top10,
      high_weight_2x_uniform,
      high_weight_donor
    )
}

extract_time_weights <- function(fit) {
  setup <- attr(fit, "setup")
  lambda <- as.numeric(attr(fit, "weights")$lambda)
  pre_years <- as.integer(colnames(setup$Y)[seq_len(setup$T0)])

  tibble::tibble(
    year = pre_years,
    time_weight = lambda
  ) |>
    dplyr::arrange(dplyr::desc(time_weight), year) |>
    dplyr::mutate(
      time_weight_rank = dplyr::row_number(),
      high_time_weight = time_weight_rank <= 4L
    ) |>
    dplyr::arrange(year)
}

build_balance_table <- function(synth_data, unit_weights, pre_years = 1997:2008) {
  variable_dictionary <- sdid_variable_dictionary()
  balance_variables <- intersect(variable_dictionary$variable, names(synth_data))

  donor_weights <- unit_weights |>
    dplyr::select(iso3c, unit_weight)

  rows <- lapply(balance_variables, function(variable) {
    unit_pre_means <- synth_data |>
      dplyr::filter(year %in% pre_years) |>
      dplyr::group_by(iso3c) |>
      dplyr::summarise(
        pre_mean = mean(.data[[variable]], na.rm = TRUE),
        .groups = "drop"
      )

    brazil_mean <- unit_pre_means |>
      dplyr::filter(iso3c == "BRA") |>
      dplyr::pull(pre_mean)

    donor_pre_means <- unit_pre_means |>
      dplyr::filter(iso3c != "BRA")

    synthetic_mean <- donor_pre_means |>
      dplyr::left_join(donor_weights, by = "iso3c") |>
      dplyr::summarise(value = sum(pre_mean * unit_weight, na.rm = TRUE)) |>
      dplyr::pull(value)

    donor_pool_mean <- mean(donor_pre_means$pre_mean, na.rm = TRUE)
    donor_pool_sd <- stats::sd(donor_pre_means$pre_mean, na.rm = TRUE)

    tibble::tibble(
      variable = variable,
      brazil_pre_mean = brazil_mean,
      synthetic_pre_mean = synthetic_mean,
      donor_pool_unweighted_pre_mean = donor_pool_mean,
      brazil_minus_synthetic = brazil_mean - synthetic_mean,
      standardized_difference = (brazil_mean - synthetic_mean) / donor_pool_sd
    )
  })

  dplyr::bind_rows(rows) |>
    dplyr::left_join(variable_dictionary, by = "variable") |>
    dplyr::relocate(label, role, .after = variable) |>
    dplyr::arrange(match(variable, balance_variables))
}

build_placebo_summary <- function(placebo_results) {
  placebo_results <- placebo_results |>
    dplyr::mutate(
      role = dplyr::if_else(iso3c == "BRA", "Brazil", "Control placebo"),
      estimate_rank_negative = rank(estimate, ties.method = "min", na.last = "keep"),
      estimate_rank_abs = rank(-abs(estimate), ties.method = "min", na.last = "keep"),
      rmspe_ratio_rank_high = rank(-ratio, ties.method = "min", na.last = "keep")
    )

  brazil <- placebo_results |>
    dplyr::filter(iso3c == "BRA")

  if (nrow(brazil) != 1L || is.na(brazil$estimate)) {
    return(list(
      placebo_results = placebo_results,
    inference = tibble::tibble()
    ))
  }

  valid_all <- placebo_results |>
    dplyr::filter(!is.na(estimate), !is.na(rmspe_pre), !is.na(ratio))
  fit_filtered <- valid_all |>
    dplyr::filter(rmspe_pre <= 2 * brazil$rmspe_pre)

  inference <- tibble::tibble(
    estimand = c(
      "One-sided negative effect",
      "Two-sided absolute effect",
      "One-sided negative effect, fit-filtered",
      "Two-sided absolute effect, fit-filtered",
      "Intercept-adjusted RMSPE ratio rank"
    ),
    brazil_statistic = c(
      brazil$estimate,
      abs(brazil$estimate),
      brazil$estimate,
      abs(brazil$estimate),
      brazil$ratio
    ),
    rank = c(
      sum(valid_all$estimate <= brazil$estimate, na.rm = TRUE),
      sum(abs(valid_all$estimate) >= abs(brazil$estimate), na.rm = TRUE),
      sum(fit_filtered$estimate <= brazil$estimate, na.rm = TRUE),
      sum(abs(fit_filtered$estimate) >= abs(brazil$estimate), na.rm = TRUE),
      sum(valid_all$ratio >= brazil$ratio, na.rm = TRUE)
    ),
    denominator = c(
      nrow(valid_all),
      nrow(valid_all),
      nrow(fit_filtered),
      nrow(fit_filtered),
      nrow(valid_all)
    )
  ) |>
    dplyr::mutate(
      rank_based_p_value = rank / denominator,
      inference_note = dplyr::case_when(
        stringr::str_detect(estimand, "fit-filtered") ~
          "Includes Brazil and placebos with intercept-adjusted pre-treatment RMSPE no larger than twice Brazil's intercept-adjusted pre-treatment RMSPE.",
        estimand == "Intercept-adjusted RMSPE ratio rank" ~
          "Ranks the post/pre intercept-adjusted RMSPE ratio; large ratios indicate a large post-treatment gap relative to adjusted pre-treatment fit.",
        TRUE ~
          "Includes Brazil and all valid placebo-in-space estimates; finite-sample rank p-value."
      )
    )

  list(
    placebo_results = placebo_results,
    inference = inference
  )
}

run_placebos_for_window <- function(data,
                                    year_start,
                                    year_end,
                                    treatment_start = 2009L,
                                    spec_label = "window") {
  base_panel <- data |>
    dplyr::filter(year >= year_start, year <= year_end)
  units <- sort(unique(base_panel$iso3c))

  results <- vector("list", length(units))

  for (i in seq_along(units)) {
    unit <- units[[i]]
    fit <- fit_sdid_safely(
      data = data,
      year_start = year_start,
      year_end = year_end,
      treated_iso3c = unit,
      treatment_start = treatment_start
    )

    summary <- summarise_sdid_fit(fit, label = spec_label) |>
      dplyr::mutate(iso3c = unit, .before = 1L)

    results[[i]] <- summary
  }

  dplyr::bind_rows(results)
}

summarise_window_placebo_rank <- function(placebo_window_results) {
  placebo_window_results |>
    dplyr::group_by(specification) |>
    dplyr::group_modify(function(.x, .y) {
      brazil <- .x |>
        dplyr::filter(iso3c == "BRA", status == "estimated")
      valid <- .x |>
        dplyr::filter(status == "estimated", !is.na(estimate))

      if (nrow(brazil) != 1L || nrow(valid) == 0L) {
        return(tibble::tibble(
          brazil_estimate_rank_negative = NA_integer_,
          placebo_denominator = nrow(valid),
          placebo_p_one_sided_negative = NA_real_,
          placebo_p_two_sided_abs = NA_real_,
          brazil_rmspe_ratio_rank_high = NA_integer_
        ))
      }

      tibble::tibble(
        brazil_estimate_rank_negative = sum(valid$estimate <= brazil$estimate, na.rm = TRUE),
        placebo_denominator = nrow(valid),
        placebo_p_one_sided_negative = mean(valid$estimate <= brazil$estimate, na.rm = TRUE),
        placebo_p_two_sided_abs = mean(abs(valid$estimate) >= abs(brazil$estimate), na.rm = TRUE),
        brazil_rmspe_ratio_rank_high = sum(valid$rmspe_ratio >= brazil$rmspe_ratio, na.rm = TRUE)
      )
    }) |>
    dplyr::ungroup()
}

build_china_exposure_diagnostic <- function(synth_data,
                                            trade_data_ranked,
                                            trade_data_cleaned,
                                            unit_weights,
                                            pre_years = 1997:2008,
                                            post_years = 2009:2015) {
  china_rank <- trade_data_ranked |>
    dplyr::filter(importer_iso3 == "CHN", year %in% c(pre_years, post_years)) |>
    dplyr::select(iso3c, year, rank_from_i, exports)

  china_trade_share <- trade_data_cleaned |>
    dplyr::filter(year %in% c(pre_years, post_years)) |>
    dplyr::mutate(china_export_share = trade_with_china / total_trade) |>
    dplyr::select(iso3c, year, china_export_share, trade_with_china, total_trade)

  exposure <- unit_weights |>
    dplyr::left_join(china_trade_share, by = "iso3c") |>
    dplyr::left_join(china_rank, by = c("iso3c", "year")) |>
    dplyr::mutate(period = dplyr::if_else(year %in% pre_years, "Pre-treatment", "Post-treatment")) |>
    dplyr::group_by(
      weight_rank,
      iso3c,
      country_name,
      region,
      latin_america,
      unit_weight,
      high_weight_donor,
      period
    ) |>
    dplyr::summarise(
      mean_china_export_share = mean(china_export_share, na.rm = TRUE),
      max_china_export_share = max(china_export_share, na.rm = TRUE),
      mean_china_rank = mean(rank_from_i, na.rm = TRUE),
      min_china_rank = min(rank_from_i, na.rm = TRUE),
      ever_china_top_export_destination = any(rank_from_i == 1, na.rm = TRUE),
      ever_china_top_two_export_destination = any(rank_from_i <= 2, na.rm = TRUE),
      .groups = "drop"
    ) |>
    tidyr::pivot_wider(
      names_from = period,
      values_from = c(
        mean_china_export_share,
        max_china_export_share,
        mean_china_rank,
        min_china_rank,
        ever_china_top_export_destination,
        ever_china_top_two_export_destination
      ),
      names_glue = "{.value}_{period}"
    ) |>
    janitor::clean_names() |>
    dplyr::mutate(
      delta_mean_china_export_share_post_minus_pre =
        mean_china_export_share_post_treatment - mean_china_export_share_pre_treatment,
      china_exposure_flag = dplyr::case_when(
        ever_china_top_export_destination_post_treatment ~ "China became/was top export destination post-2009",
        ever_china_top_two_export_destination_post_treatment ~ "China was top-two export destination post-2009",
        max_china_export_share_post_treatment >= 0.10 ~ "China export share reached at least 10% post-2009",
        TRUE ~ "No high descriptive China exposure flag"
      )
    )

  high_weight_summary <- exposure |>
    dplyr::summarise(
      n_high_weight_donors = sum(high_weight_donor, na.rm = TRUE),
      weighted_share_from_high_weight_donors = sum(unit_weight[high_weight_donor], na.rm = TRUE),
      n_high_weight_top_china_post = sum(
        high_weight_donor & ever_china_top_export_destination_post_treatment,
        na.rm = TRUE
      ),
      n_high_weight_top_two_china_post = sum(
        high_weight_donor & ever_china_top_two_export_destination_post_treatment,
        na.rm = TRUE
      ),
      weighted_share_high_weight_top_china_post = sum(
        unit_weight[high_weight_donor & ever_china_top_export_destination_post_treatment],
        na.rm = TRUE
      ),
      weighted_share_high_weight_top_two_china_post = sum(
        unit_weight[high_weight_donor & ever_china_top_two_export_destination_post_treatment],
        na.rm = TRUE
      ),
      .groups = "drop"
    )

  list(exposure = exposure, summary = high_weight_summary)
}

write_latex_table <- function(data, path, caption, label = NULL, digits = 3) {
  table <- data
  for (col in names(table)) {
    if (is.numeric(table[[col]])) {
      table[[col]] <- ifelse(is.na(table[[col]]), "", formatC(table[[col]], digits = digits, format = "f"))
    }
  }

  latex <- knitr::kable(
    table,
    format = "latex",
    booktabs = TRUE,
    caption = caption,
    label = label,
    escape = TRUE
  )

  writeLines(latex, path, useBytes = TRUE)
}
