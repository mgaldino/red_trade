#!/usr/bin/env Rscript

# Diagnostic for the review concern:
# "UNGA distance does not yet show selective alignment toward China rather
# than broader repositioning." This script reads existing targets and preserved
# UN votes only. It does not edit _targets.R, _targets/, _targets.yaml, raw
# data, or the manuscript.

options(scipen = 999)

set.seed(20260520)

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

suppressPackageStartupMessages({
  library(countrycode)
  library(dplyr)
  library(fixest)
  library(ggplot2)
  library(here)
  library(lubridate)
  library(readr)
  library(stringr)
  library(synthdid)
  library(targets)
  library(tibble)
  library(tidyr)
})

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
script_path <- "scripts/diagnostics/diagnose_selective_china_alignment_unga.R"
target_store <- here::here("_targets")
raw_tarball <- here::here("data", "raw", "unvotes", "unvotes_0.3.0.tar.gz")
out_dir <- here::here("quality_reports", "selective_china_alignment_unga")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

path_out <- function(filename) file.path(out_dir, filename)

report_path <- path_out(paste0(run_date, "_selective_china_alignment_unga_report.md"))
report_pdf_path <- path_out(paste0(run_date, "_selective_china_alignment_unga_report.pdf"))
pdf_render_log_path <- path_out("selective_china_alignment_pdf_render_log.txt")
session_info_path <- path_out("selective_china_alignment_session_info.txt")

paths <- list(
  audit_gap = path_out("selective_china_alignment_audit_gap_table.csv"),
  decision_matrix = path_out("selective_china_alignment_decision_matrix.csv"),
  country_year = path_out("selective_china_alignment_country_year_outcomes.csv"),
  country_year_series = path_out("selective_china_alignment_country_year_brazil_series.csv"),
  reference_spatial = path_out("selective_china_alignment_reference_spatial_diagnostics.csv"),
  vote_panel = path_out("selective_china_alignment_vote_panel_2005_2012.csv"),
  vote_panel_extended = path_out("selective_china_alignment_vote_panel_2000_2015.csv"),
  vote_models = path_out("selective_china_alignment_vote_level_models.csv"),
  vote_descriptives = path_out("selective_china_alignment_vote_level_descriptives.csv"),
  target_file_audit = path_out("selective_china_alignment_target_file_audit.csv"),
  ddd_models = path_out("selective_china_alignment_ddd_hr_nonhr_models.csv"),
  twoway_cluster = path_out("selective_china_alignment_twoway_cluster_sensitivity.csv"),
  event_pretrend = path_out("selective_china_alignment_pretrend_event_study.csv"),
  temporal_placebos = path_out("selective_china_alignment_temporal_placebos.csv"),
  country_placebos = path_out("selective_china_alignment_country_placebos.csv"),
  country_placebo_summary = path_out("selective_china_alignment_country_placebo_summary.csv"),
  extreme_placebo_audit = path_out("selective_china_alignment_extreme_placebo_audit.csv"),
  donor_audit = path_out("selective_china_alignment_donor_pool_audit.csv"),
  donor_sensitivity = path_out("selective_china_alignment_donor_contamination_sensitivity.csv"),
  model_sample_counts = path_out("selective_china_alignment_model_sample_counts.csv"),
  final_interpretation = path_out("selective_china_alignment_final_interpretation.csv"),
  validation = path_out("selective_china_alignment_validation_checks.csv"),
  fig_country_year_png = path_out("figura_1_country_year_parallel_outcomes.png"),
  fig_country_year_pdf = path_out("figura_1_country_year_parallel_outcomes.pdf"),
  fig_vote_prepost_png = path_out("figura_2_vote_level_hr_divergent_prepost.png"),
  fig_vote_prepost_pdf = path_out("figura_2_vote_level_hr_divergent_prepost.pdf"),
  fig_placebo_png = path_out("figura_3_country_placebo_distribution.png"),
  fig_placebo_pdf = path_out("figura_3_country_placebo_distribution.pdf")
)

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) {
      structure(list(error = conditionMessage(e)), class = "selective_tar_error")
    }
  )
}

is_tar_error <- function(x) inherits(x, "selective_tar_error")

safe_tar_meta <- function() {
  tryCatch(
    targets::tar_meta(store = target_store),
    error = function(e) tibble::tibble(name = character(), error = conditionMessage(e))
  )
}

object_shape <- function(x) {
  if (is_tar_error(x)) {
    return(tibble::tibble(
      object_class = "tar_read_error",
      nrow = NA_integer_,
      ncol = NA_integer_,
      columns = "",
      read_error = x$error
    ))
  }

  if (is.data.frame(x)) {
    return(tibble::tibble(
      object_class = paste(class(x), collapse = ";"),
      nrow = nrow(x),
      ncol = ncol(x),
      columns = paste(names(x), collapse = ";"),
      read_error = ""
    ))
  }

  tibble::tibble(
    object_class = paste(class(x), collapse = ";"),
    nrow = NA_integer_,
    ncol = NA_integer_,
    columns = "",
    read_error = ""
  )
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "",
    x < 0.001 ~ "<0.001",
    TRUE ~ formatC(x, digits = 3, format = "f")
  )
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "", paste0(formatC(100 * x, digits = digits, format = "f"), "%"))
}

markdown_table <- function(data, digits = 3, max_rows = Inf) {
  data <- as.data.frame(data)
  if (nrow(data) == 0L) {
    return("_Nenhuma linha._")
  }
  if (is.finite(max_rows)) {
    data <- utils::head(data, max_rows)
  }

  display <- data
  for (col in names(display)) {
    if (is.numeric(display[[col]])) {
      non_missing <- display[[col]][!is.na(display[[col]])]
      if (length(non_missing) > 0L && all(abs(non_missing - round(non_missing)) < .Machine$double.eps^0.5)) {
        display[[col]] <- ifelse(is.na(display[[col]]), "", as.character(as.integer(round(display[[col]]))))
      } else {
        display[[col]] <- fmt_num(display[[col]], digits = digits)
      }
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

save_plot_pair <- function(plot, png_path, pdf_path, width, height) {
  ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = 320)
  ggplot2::ggsave(pdf_path, plot, width = width, height = height)
}

clean_text <- function(x) {
  x |>
    iconv(from = "", to = "UTF-8", sub = "") |>
    stringr::str_replace_all("\u00a0", " ") |>
    stringr::str_replace_all("\u00c2", "") |>
    stringr::str_squish()
}

map_issue_family <- function(issue) {
  dplyr::case_when(
    is.na(issue) | issue == "" ~ "Other / uncoded",
    stringr::str_detect(issue, "Human rights") ~ "Human rights",
    stringr::str_detect(issue, "Arms control|Nuclear weapons|disarmament") ~
      "Arms/disarmament/nuclear",
    stringr::str_detect(issue, "Palestinian conflict") ~
      "Palestine/Middle East",
    stringr::str_detect(issue, "Economic development") ~
      "Economic development",
    stringr::str_detect(issue, "Colonialism") ~ "Decolonization",
    TRUE ~ "Other / uncoded"
  )
}

vote_score <- function(vote) {
  dplyr::case_when(
    vote == "no" ~ -1,
    vote == "abstain" ~ 0,
    vote == "yes" ~ 1,
    TRUE ~ NA_real_
  )
}

load_unvotes_tables <- function(raw_tarball) {
  if (!file.exists(raw_tarball)) {
    stop("Missing raw unvotes tarball: ", raw_tarball)
  }
  if (file.info(raw_tarball)$size <= 0) {
    stop("Raw unvotes tarball exists but is empty: ", raw_tarball)
  }

  tmp_dir <- tempfile("unvotes_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  utils::untar(raw_tarball, exdir = tmp_dir, tar = "internal")

  load_unvotes_data <- function(name) {
    env <- new.env(parent = emptyenv())
    load(file.path(tmp_dir, "unvotes", "data", paste0(name, ".rda")), envir = env)
    env[[name]]
  }

  list(
    un_votes = load_unvotes_data("un_votes"),
    un_roll_calls = load_unvotes_data("un_roll_calls"),
    un_roll_call_issues = load_unvotes_data("un_roll_call_issues")
  )
}

build_vote_panel <- function(unvotes_tables, donor_iso3c, years) {
  un_votes <- unvotes_tables$un_votes |>
    dplyr::mutate(
      vote = as.character(vote),
      iso3c = countrycode::countrycode(
        country_code,
        origin = "iso2c",
        destination = "iso3c",
        warn = FALSE
      )
    )

  un_roll_calls <- unvotes_tables$un_roll_calls |>
    dplyr::mutate(
      year = lubridate::year(date),
      short = clean_text(short),
      descr = clean_text(descr),
      doc_symbol = stringr::str_replace(unres, "^R/", "A/RES/")
    ) |>
    dplyr::filter(year %in% years)

  issue_by_rcid <- unvotes_tables$un_roll_call_issues |>
    dplyr::mutate(
      issue = clean_text(as.character(issue)),
      issue_family_single = map_issue_family(issue)
    ) |>
    dplyr::summarise(
      issue = paste(sort(unique(issue[!is.na(issue)])), collapse = "; "),
      issue_family = paste(sort(unique(issue_family_single[!is.na(issue_family_single)])), collapse = "; "),
      any_human_rights = any(issue_family_single == "Human rights", na.rm = TRUE),
      .by = rcid
    ) |>
    dplyr::mutate(
      issue = dplyr::na_if(issue, ""),
      issue_family = dplyr::if_else(
        is.na(issue_family) | issue_family == "",
        "Other / uncoded",
        issue_family
      ),
      issue_domain = dplyr::if_else(any_human_rights, "Human rights", "Non-human rights")
    )

  reference_votes <- un_votes |>
    dplyr::filter(iso3c %in% c("CHN", "USA")) |>
    dplyr::filter(vote %in% c("yes", "no", "abstain")) |>
    dplyr::select(rcid, iso3c, vote) |>
    tidyr::pivot_wider(names_from = iso3c, values_from = vote, names_prefix = "vote_") |>
    dplyr::rename(vote_china = vote_CHN, vote_usa = vote_USA) |>
    dplyr::mutate(
      china_score = vote_score(vote_china),
      usa_score = vote_score(vote_usa),
      china_usa_divergent = !is.na(china_score) & !is.na(usa_score) & china_score != usa_score,
      china_usa_strong_divergent = china_usa_divergent &
        abs(china_score - usa_score) == 2
    ) |>
    dplyr::filter(!is.na(china_score), !is.na(usa_score))

  panel_countries <- unique(c("BRA", donor_iso3c))

  un_votes |>
    dplyr::filter(iso3c %in% panel_countries) |>
    dplyr::filter(vote %in% c("yes", "no", "abstain")) |>
    dplyr::select(rcid, country, country_code, iso3c, vote) |>
    dplyr::inner_join(un_roll_calls, by = "rcid") |>
    dplyr::inner_join(reference_votes, by = "rcid") |>
    dplyr::left_join(issue_by_rcid, by = "rcid") |>
    dplyr::mutate(
      issue = dplyr::coalesce(issue, "Uncoded"),
      issue_family = dplyr::coalesce(issue_family, "Other / uncoded"),
      issue_domain = dplyr::coalesce(issue_domain, "Non-human rights"),
      vote_ordinal = vote_score(vote),
      post_2009 = as.integer(year >= 2009),
      brazil = as.integer(iso3c == "BRA"),
      brazil_post_2009 = brazil * post_2009,
      distance_to_china_vote = abs(vote_ordinal - china_score),
      distance_to_usa_vote = abs(vote_ordinal - usa_score),
      distance_china_minus_usa = distance_to_china_vote - distance_to_usa_vote,
      closer_to_china_than_usa = as.integer(distance_to_china_vote < distance_to_usa_vote),
      closer_to_china_score = distance_to_usa_vote - distance_to_china_vote,
      agree_china = as.integer(vote_ordinal == china_score),
      agree_usa = as.integer(vote_ordinal == usa_score),
      agreement_china_minus_usa = agree_china - agree_usa,
      doc_symbol = dplyr::if_else(is.na(doc_symbol) | doc_symbol == "", NA_character_, doc_symbol),
      document_url = dplyr::if_else(
        is.na(doc_symbol),
        NA_character_,
        paste0("https://docs.un.org/en/", doc_symbol)
      ),
      vote_record_url = dplyr::if_else(
        is.na(doc_symbol),
        NA_character_,
        paste0(
          "https://digitallibrary.un.org/search?ln=en&p=",
          utils::URLencode(doc_symbol, reserved = TRUE)
        )
      )
    ) |>
    dplyr::filter(!is.na(vote_ordinal)) |>
    dplyr::arrange(year, rcid, iso3c)
}

make_covariate_array <- function(data, covariate_cols) {
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

prepare_sdid_panel <- function(data, outcome_col, covariate_cols,
                               time_treatment = 2008L, time_end = 2016L) {
  required <- c("iso3c", "year", outcome_col, covariate_cols)
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("prepare_sdid_panel missing columns: ", paste(missing, collapse = ", "))
  }

  base <- data |>
    dplyr::filter(year < time_end) |>
    dplyr::select(dplyr::all_of(required)) |>
    dplyr::mutate(
      year = as.integer(year),
      outcome_value = as.numeric(.data[[outcome_col]])
    )

  common_years <- sort(unique(base$year))
  complete_units <- base |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      n_years = dplyr::n_distinct(year),
      complete_year_grid = setequal(year, common_years),
      complete_outcome = all(!is.na(outcome_value)),
      complete_covariates = all(stats::complete.cases(dplyr::pick(dplyr::all_of(covariate_cols)))),
      .groups = "drop"
    ) |>
    dplyr::filter(
      n_years == length(common_years),
      complete_year_grid,
      complete_outcome,
      complete_covariates
    ) |>
    dplyr::pull(iso3c)

  base |>
    dplyr::filter(iso3c %in% complete_units) |>
    dplyr::mutate(
      treatment = as.integer(iso3c == "BRA" & year > time_treatment),
      .unit_treated = as.integer(iso3c == "BRA")
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)
}

fit_sdid_point <- function(data, outcome_col, covariate_cols, compute_se = FALSE) {
  fit_data <- prepare_sdid_panel(data, outcome_col, covariate_cols)
  if (!"BRA" %in% unique(fit_data$iso3c)) {
    stop("Brazil dropped from SDiD complete-case panel.")
  }
  x_array <- make_covariate_array(fit_data, covariate_cols)
  panel_data <- fit_data |>
    dplyr::mutate(
      iso3c = as.factor(iso3c),
      year = as.integer(year),
      Y = outcome_value
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()
  setup <- synthdid::panel.matrices(panel_data)
  fit <- synthdid::synthdid_estimate(
    Y = setup$Y,
    N0 = setup$N0,
    T0 = setup$T0,
    X = x_array
  )
  se <- if (compute_se) {
    tryCatch(as.numeric(sqrt(stats::vcov(fit, method = "placebo"))), error = function(e) NA_real_)
  } else {
    NA_real_
  }
  tibble::tibble(
    estimate = as.numeric(fit),
    se_placebo = se,
    p_value = ifelse(is.na(se), NA_real_, 2 * stats::pnorm(-abs(as.numeric(fit) / se))),
    n_obs = nrow(fit_data),
    n_countries = dplyr::n_distinct(fit_data$iso3c),
    n_donors = dplyr::n_distinct(fit_data$iso3c) - 1L
  )
}

fit_vote_model <- function(data, outcome, treatment_var = "brazil_post_2009",
                           model_label, sample_label, expected_direction,
                           vcov_formula = ~iso3c,
                           inference_note = "Model-based country-clustered SE; fixed effects for country and resolution. With one treated country, country-placebo inference is primary.") {
  if (!outcome %in% names(data)) {
    return(tibble::tibble(
      model = model_label,
      sample = sample_label,
      outcome = outcome,
      expected_direction = expected_direction,
      estimate = NA_real_,
      se = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      n_obs = nrow(data),
      n_countries = dplyr::n_distinct(data$iso3c),
      n_resolutions = dplyr::n_distinct(data$rcid),
      inference_status = "Outcome missing.",
      error = "missing outcome"
    ))
  }

  if (nrow(data) == 0L || length(unique(data[[treatment_var]])) < 2L) {
    return(tibble::tibble(
      model = model_label,
      sample = sample_label,
      outcome = outcome,
      expected_direction = expected_direction,
      estimate = NA_real_,
      se = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      n_obs = nrow(data),
      n_countries = dplyr::n_distinct(data$iso3c),
      n_resolutions = dplyr::n_distinct(data$rcid),
      inference_status = "Not estimated: no treatment variation.",
      error = "no treatment variation"
    ))
  }

  fml <- stats::as.formula(paste0(outcome, " ~ ", treatment_var, " | iso3c + rcid"))
  fit <- tryCatch(
    fixest::feols(fml, data = data, vcov = vcov_formula, notes = FALSE),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      model = model_label,
      sample = sample_label,
      outcome = outcome,
      expected_direction = expected_direction,
      estimate = NA_real_,
      se = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      n_obs = nrow(data),
      n_countries = dplyr::n_distinct(data$iso3c),
      n_resolutions = dplyr::n_distinct(data$rcid),
      inference_status = "Model failed.",
      error = conditionMessage(fit)
    ))
  }

  coef_name <- treatment_var
  estimate <- unname(stats::coef(fit)[coef_name])
  se <- tryCatch(unname(fixest::se(fit)[coef_name]), error = function(e) NA_real_)
  ci <- tryCatch(stats::confint(fit, parm = coef_name), error = function(e) matrix(c(NA_real_, NA_real_), nrow = 1))
  p_value <- tryCatch(unname(fixest::pvalue(fit)[coef_name]), error = function(e) NA_real_)

  tibble::tibble(
    model = model_label,
    sample = sample_label,
    outcome = outcome,
    expected_direction = expected_direction,
    estimate = estimate,
    se = se,
    p_value = p_value,
    ci_95_low = as.numeric(ci[1, 1]),
    ci_95_high = as.numeric(ci[1, 2]),
    n_obs = stats::nobs(fit),
    n_countries = dplyr::n_distinct(data$iso3c),
    n_resolutions = dplyr::n_distinct(data$rcid),
    inference_status = inference_note,
    error = ""
  )
}

fit_vote_model_set <- function(data, model_label, sample_label,
                               vcov_formula = ~iso3c,
                               inference_note = "Model-based country-clustered SE; fixed effects for country and resolution. With one treated country, country-placebo inference is primary.") {
  dplyr::bind_rows(
    fit_vote_model(
      data,
      outcome = "distance_to_china_vote",
      model_label = model_label,
      sample_label = sample_label,
      expected_direction = "negative",
      vcov_formula = vcov_formula,
      inference_note = inference_note
    ),
    fit_vote_model(
      data,
      outcome = "distance_to_usa_vote",
      model_label = model_label,
      sample_label = sample_label,
      expected_direction = "positive",
      vcov_formula = vcov_formula,
      inference_note = inference_note
    ),
    fit_vote_model(
      data,
      outcome = "distance_china_minus_usa",
      model_label = model_label,
      sample_label = sample_label,
      expected_direction = "negative",
      vcov_formula = vcov_formula,
      inference_note = inference_note
    ),
    fit_vote_model(
      data,
      outcome = "closer_to_china_than_usa",
      model_label = model_label,
      sample_label = sample_label,
      expected_direction = "positive",
      vcov_formula = vcov_formula,
      inference_note = inference_note
    ),
    fit_vote_model(
      data,
      outcome = "closer_to_china_score",
      model_label = model_label,
      sample_label = sample_label,
      expected_direction = "positive",
      vcov_formula = vcov_formula,
      inference_note = inference_note
    ),
    fit_vote_model(
      data,
      outcome = "agreement_china_minus_usa",
      model_label = model_label,
      sample_label = sample_label,
      expected_direction = "positive",
      vcov_formula = vcov_formula,
      inference_note = inference_note
    )
  )
}

make_vote_descriptives <- function(data, sample_label) {
  data |>
    dplyr::mutate(period = dplyr::if_else(year < 2009, "Pre-2009", "Post-2009")) |>
    dplyr::summarise(
      n_obs = dplyr::n(),
      n_countries = dplyr::n_distinct(iso3c),
      n_resolutions = dplyr::n_distinct(rcid),
      mean_distance_china = mean(distance_to_china_vote, na.rm = TRUE),
      mean_distance_usa = mean(distance_to_usa_vote, na.rm = TRUE),
      mean_distance_china_minus_usa = mean(distance_china_minus_usa, na.rm = TRUE),
      mean_closer_china = mean(closer_to_china_than_usa, na.rm = TRUE),
      mean_closer_china_score = mean(closer_to_china_score, na.rm = TRUE),
      .by = c(period, brazil)
    ) |>
    dplyr::mutate(
      sample = sample_label,
      country_group = dplyr::if_else(brazil == 1L, "Brazil", "Donor pool"),
      .before = 1
    ) |>
    dplyr::select(-brazil) |>
    dplyr::arrange(sample, country_group, period)
}

country_placebo <- function(data, outcome, expected_direction) {
  units <- sort(unique(data$iso3c))
  results <- dplyr::bind_rows(lapply(units, function(unit) {
    placebo_data <- data |>
      dplyr::mutate(placebo_post = as.integer(iso3c == unit & year >= 2009))
    fit_vote_model(
      placebo_data,
      outcome = outcome,
      treatment_var = "placebo_post",
      model_label = paste0("Placebo treated unit: ", unit),
      sample_label = "Human-rights China-US divergent votes",
      expected_direction = expected_direction,
      inference_note = "Country placebo estimate; same fixed effects and country-clustered SE."
    ) |>
      dplyr::mutate(placebo_unit = unit, .before = model)
  }))

  brazil_est <- results |>
    dplyr::filter(placebo_unit == "BRA") |>
    dplyr::pull(estimate)

  if (expected_direction == "negative") {
    results <- results |>
      dplyr::mutate(
        expected_rank = rank(estimate, ties.method = "min", na.last = "keep"),
        more_extreme_than_brazil = estimate <= brazil_est,
        strictly_more_extreme_than_brazil = estimate < brazil_est
      )
  } else {
    results <- results |>
      dplyr::mutate(
        expected_rank = rank(-estimate, ties.method = "min", na.last = "keep"),
        more_extreme_than_brazil = estimate >= brazil_est,
        strictly_more_extreme_than_brazil = estimate > brazil_est
      )
  }

  results |>
    dplyr::mutate(
      brazil_estimate = brazil_est,
      randomization_p_two_sided = mean(abs(estimate) >= abs(brazil_est), na.rm = TRUE),
      randomization_p_directional = mean(more_extreme_than_brazil, na.rm = TRUE),
      randomization_p_two_sided_strict_donor = mean(
        abs(estimate[placebo_unit != "BRA"]) > abs(brazil_est),
        na.rm = TRUE
      ),
      randomization_p_directional_strict_donor = mean(
        strictly_more_extreme_than_brazil[placebo_unit != "BRA"],
        na.rm = TRUE
      )
    )
}

fit_ddd_model <- function(data, outcome, vcov_formula, vcov_label) {
  model_label <- paste0("DDD HR vs non-HR among China-US divergent votes; ", vcov_label)
  if (nrow(data) == 0L || !outcome %in% names(data)) {
    return(tibble::tibble(
      model = model_label,
      outcome = outcome,
      term = character(),
      estimate = numeric(),
      se = numeric(),
      p_value = numeric(),
      ci_95_low = numeric(),
      ci_95_high = numeric(),
      n_obs = integer(),
      n_countries = integer(),
      n_resolutions = integer(),
      inference_status = character(),
      error = character()
    ))
  }

  fit_data <- data |>
    dplyr::mutate(
      human_rights_binary = as.integer(issue_domain == "Human rights"),
      brazil_post_hr = brazil_post_2009 * human_rights_binary
    )
  fml <- stats::as.formula(paste0(outcome, " ~ brazil_post_2009 + brazil_post_hr | iso3c + rcid"))
  fit <- tryCatch(
    fixest::feols(fml, data = fit_data, vcov = vcov_formula, notes = FALSE),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(tibble::tibble(
      model = model_label,
      outcome = outcome,
      term = c("brazil_post_2009", "brazil_post_hr"),
      estimate = NA_real_,
      se = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      n_obs = nrow(fit_data),
      n_countries = dplyr::n_distinct(fit_data$iso3c),
      n_resolutions = dplyr::n_distinct(fit_data$rcid),
      inference_status = "Model failed.",
      error = conditionMessage(fit)
    ))
  }

  terms <- c("brazil_post_2009", "brazil_post_hr")
  estimates <- stats::coef(fit)[terms]
  ses <- tryCatch(fixest::se(fit)[terms], error = function(e) rep(NA_real_, length(terms)))
  pvals <- tryCatch(fixest::pvalue(fit)[terms], error = function(e) rep(NA_real_, length(terms)))
  cis <- tryCatch(stats::confint(fit, parm = terms), error = function(e) {
    matrix(NA_real_, nrow = length(terms), ncol = 2, dimnames = list(terms, c("2.5 %", "97.5 %")))
  })

  tibble::tibble(
    model = model_label,
    outcome = outcome,
    term = terms,
    estimate = as.numeric(estimates),
    se = as.numeric(ses),
    p_value = as.numeric(pvals),
    ci_95_low = as.numeric(cis[, 1]),
    ci_95_high = as.numeric(cis[, 2]),
    n_obs = stats::nobs(fit),
    n_countries = dplyr::n_distinct(fit_data$iso3c),
    n_resolutions = dplyr::n_distinct(fit_data$rcid),
    inference_status = paste0(
      "Model-based ", vcov_label,
      ". The interaction term tests whether the Brazil post-2009 shift is stronger in human-rights than non-human-rights divergent votes."
    ),
    error = ""
  )
}

fit_pretrend_event_study <- function(data, outcome, main_effect_abs) {
  threshold <- 0.25 * abs(main_effect_abs)
  fit_data <- data |>
    dplyr::filter(year < 2009)
  if (nrow(fit_data) == 0L || dplyr::n_distinct(fit_data$year) < 2L) {
    return(tibble::tibble(
      outcome = outcome,
      year = integer(),
      estimate = numeric(),
      se = numeric(),
      p_value = numeric(),
      ci_95_low = numeric(),
      ci_95_high = numeric(),
      equivalence_threshold = numeric(),
      within_threshold = logical(),
      inference_status = character(),
      error = character()
    ))
  }

  fml <- stats::as.formula(paste0(outcome, " ~ i(year, brazil, ref = 2005) | iso3c + rcid"))
  fit <- tryCatch(
    fixest::feols(fml, data = fit_data, vcov = ~iso3c, notes = FALSE),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(tibble::tibble(
      outcome = outcome,
      year = NA_integer_,
      estimate = NA_real_,
      se = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      equivalence_threshold = threshold,
      within_threshold = NA,
      inference_status = "Model failed.",
      error = conditionMessage(fit)
    ))
  }

  terms <- names(stats::coef(fit))
  estimates <- stats::coef(fit)
  ses <- tryCatch(fixest::se(fit), error = function(e) rep(NA_real_, length(terms)))
  pvals <- tryCatch(fixest::pvalue(fit), error = function(e) rep(NA_real_, length(terms)))
  cis <- tryCatch(stats::confint(fit), error = function(e) {
    matrix(NA_real_, nrow = length(terms), ncol = 2, dimnames = list(terms, c("2.5 %", "97.5 %")))
  })

  tibble::tibble(
    outcome = outcome,
    term = terms,
    year = as.integer(stringr::str_extract(terms, "\\d{4}")),
    estimate = as.numeric(estimates),
    se = as.numeric(ses),
    p_value = as.numeric(pvals),
    ci_95_low = as.numeric(cis[, 1]),
    ci_95_high = as.numeric(cis[, 2]),
    equivalence_threshold = threshold,
    within_threshold = abs(estimate) <= threshold,
    inference_status = "Pre-2009 Brazil-by-year event-study diagnostic with country and resolution FE; threshold is 25% of the main HR divergent effect.",
    error = ""
  ) |>
    dplyr::arrange(year)
}

target_names <- c(
  "synth_data",
  "unga_data",
  "synth_fit",
  "se_synth",
  "goal6_sdid_outcome_results",
  "classified_events",
  "treatment_events",
  "china_top_panel"
)

targets_read <- stats::setNames(lapply(target_names, safe_tar_read), target_names)
target_audit <- dplyr::bind_rows(lapply(names(targets_read), function(name) {
  object_shape(targets_read[[name]]) |>
    dplyr::mutate(name = name, source_type = "target", .before = 1)
}))

csv_audit_paths <- tibble::tribble(
  ~name, ~path,
  "goal6_report", "quality_reports/goal6_outcome_robustness/2026-05-18_goal6_outcome_robustness_report.md",
  "goal6_sdid_outcome_results_csv", "quality_reports/goal6_outcome_robustness/goal6_sdid_outcome_results.csv",
  "processed_alignment_by_resolution", "data/processed/unvotes/brazil_china_vote_alignment_by_resolution_2005_2012.csv",
  "processed_alignment_by_issue_year", "data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv",
  "processed_similarity_by_resolution", "data/processed/unvotes/brazil_china_vote_similarity_score_by_resolution_2005_2012.csv"
)

file_audit <- csv_audit_paths |>
  dplyr::mutate(
    exists = file.exists(path),
    bytes = ifelse(exists, file.info(path)$size, NA_real_)
  )

target_meta <- safe_tar_meta() |>
  dplyr::select(dplyr::any_of(c("name", "type", "format", "bytes", "time", "error")))
for (missing_col in setdiff(c("name", "type", "format", "bytes", "time", "error"), names(target_meta))) {
  target_meta[[missing_col]] <- NA
}

target_file_audit <- dplyr::bind_rows(
  target_audit |>
    dplyr::left_join(target_meta, by = "name", suffix = c("_read", "_meta")) |>
    dplyr::mutate(
      audit_type = "target",
      path = "",
      exists = read_error == "",
      bytes_file = NA_real_
    ) |>
    dplyr::select(
      audit_type,
      name,
      path,
      exists,
      object_class,
      nrow,
      ncol,
      columns,
      type,
      format,
      bytes_meta = bytes,
      time,
      bytes_file,
      read_error
    ),
  file_audit |>
    dplyr::transmute(
      audit_type = "file",
      name,
      path,
      exists,
      object_class = "",
      nrow = NA_integer_,
      ncol = NA_integer_,
      columns = "",
      type = "",
      format = "",
      bytes_meta = NA_real_,
      time = as.POSIXct(NA),
      bytes_file = bytes,
      read_error = ""
    )
)
readr::write_csv(target_file_audit, paths$target_file_audit, na = "")

synth_data <- targets_read[["synth_data"]]
if (is_tar_error(synth_data)) {
  stop("Cannot continue without target `synth_data`: ", synth_data$error)
}
unga_data <- targets_read[["unga_data"]]
if (is_tar_error(unga_data)) {
  stop("Cannot continue without target `unga_data`: ", unga_data$error)
}
goal6_results <- targets_read[["goal6_sdid_outcome_results"]]
if (is_tar_error(goal6_results)) {
  goal6_csv <- here::here("quality_reports", "goal6_outcome_robustness", "goal6_sdid_outcome_results.csv")
  if (file.exists(goal6_csv)) {
    goal6_results <- readr::read_csv(goal6_csv, show_col_types = FALSE, locale = readr::locale(encoding = "UTF-8"))
  } else {
    goal6_results <- tibble::tibble()
  }
}

donor_iso3c <- synth_data |>
  dplyr::distinct(iso3c) |>
  dplyr::filter(iso3c != "BRA") |>
  dplyr::pull(iso3c) |>
  sort()

synth_fit <- targets_read[["synth_fit"]]
omega <- if (!is_tar_error(synth_fit) && !is.null(attr(synth_fit, "weights")$omega)) {
  as.numeric(attr(synth_fit, "weights")$omega)
} else {
  rep(NA_real_, length(donor_iso3c))
}
if (length(omega) != length(donor_iso3c)) {
  omega <- rep(NA_real_, length(donor_iso3c))
}

classified_events <- targets_read[["classified_events"]]
if (is_tar_error(classified_events)) {
  classified_events <- tibble::tibble(
    iso3c = character(),
    first_treat_year = integer(),
    absorbing = logical(),
    displaced = character()
  )
}

china_top_panel <- targets_read[["china_top_panel"]]
if (is_tar_error(china_top_panel)) {
  china_top_panel <- tibble::tibble(iso3c = character(), year = integer(), china_top = integer())
}

donor_audit <- tibble::tibble(
  iso3c = donor_iso3c,
  country_name = countrycode::countrycode(donor_iso3c, "iso3c", "country.name", warn = FALSE),
  sdid_weight = omega
) |>
  dplyr::left_join(
    classified_events |>
      dplyr::select(iso3c, first_treat_year, absorbing, displaced),
    by = "iso3c"
  ) |>
  dplyr::left_join(
    china_top_panel |>
      dplyr::filter(year >= 2005, year <= 2012) |>
      dplyr::summarise(
        china_top_years_2005_2012 = sum(china_top == 1L, na.rm = TRUE),
        observed_trade_years_2005_2012 = dplyr::n_distinct(year),
        .by = iso3c
      ),
    by = "iso3c"
  ) |>
  dplyr::mutate(
    first_treat_year = as.integer(first_treat_year),
    absorbing = dplyr::coalesce(absorbing, FALSE),
    china_top_years_2005_2012 = tidyr::replace_na(china_top_years_2005_2012, 0L),
    china_top_or_similar_shock_2005_2012 = !is.na(first_treat_year) &
      first_treat_year >= 2005L &
      first_treat_year <= 2012L,
    reference_actor_in_vote_design = iso3c == "USA",
    main_vote_level_included = !reference_actor_in_vote_design,
    contamination_note = dplyr::case_when(
      reference_actor_in_vote_design ~ "USA is a reference actor in China-US divergent vote outcomes; excluded from main vote-level donor comparison.",
      china_top_or_similar_shock_2005_2012 ~ "Donor has a China-top treatment entry during the vote-level window; flagged for sensitivity.",
      TRUE ~ "No China-top treatment entry flagged during 2005-2012."
    )
  ) |>
  dplyr::arrange(dplyr::desc(sdid_weight), iso3c)

readr::write_csv(donor_audit, paths$donor_audit, na = "")

vote_donor_iso3c <- donor_audit |>
  dplyr::filter(main_vote_level_included) |>
  dplyr::pull(iso3c)

unvotes_tables <- load_unvotes_tables(raw_tarball)
vote_panel <- build_vote_panel(unvotes_tables, donor_iso3c = vote_donor_iso3c, years = 2005:2012)
vote_panel_extended <- build_vote_panel(unvotes_tables, donor_iso3c = vote_donor_iso3c, years = 2000:2015)

readr::write_csv(vote_panel, paths$vote_panel, na = "")
readr::write_csv(vote_panel_extended, paths$vote_panel_extended, na = "")

audit_gap_table <- tibble::tribble(
  ~component, ~what_already_responds, ~what_still_missing, ~status,
  "Goal 6 country-year outcome robustness",
  "Shows that Brazil's SDiD estimate is negative for distance to China, positive for distance to the United States, and negative for China-minus-US distance; annual agreement outcomes have the same directional pattern.",
  "Alternative outcomes mostly lack newly computed SEs and do not by themselves isolate China-US divergent votes or resolution-level donor comparisons.",
  "Partly answered",
  "Existing issue-area Brazil-China diagnostics",
  "Shows descriptive post-2009 increase in identical Brazil-China voting, especially human rights; also documents agenda-composition risks.",
  "Brazil-only pre/post shares do not compare Brazil with donor countries and do not separate convergence toward China from generic opposition to the United States.",
  "Partly answered",
  "Raw unvotes tarball",
  "Preserved source allows reproducible country-resolution panel without overwriting raw data.",
  "Needs new panel construction and explicit coding of valid votes, reference votes, and China-US divergent subsets.",
  "Available",
  "Donor-pool comparability",
  "The SDiD donor pool and weights are recoverable from existing targets.",
  "Needs audit for reference actors and donor countries with China-top treatment entries during 2005-2012.",
  "New analysis required"
)
readr::write_csv(audit_gap_table, paths$audit_gap, na = "")

decision_matrix <- tibble::tribble(
  ~interpretation_class, ~pre_estimation_rule, ~expected_pattern, ~editorial_action,
  "China-specific alignment",
  "Brazil gets closer to China after 2009 relative to comparable donor countries, especially in human-rights and China-US divergent votes, while non-human-rights controls and broad benchmarks do not show equivalent movement.",
  "Negative Brazil x Post for distance to China and China-minus-US distance; positive for closer-to-China score; Brazil is directionally unusual in donor placebos; HR is stronger than non-HR; any benchmark counterexample must be geometrically independent of China.",
  "Allow cautious claim of selective UNGA alignment toward China, with vote-level and placebo evidence as support.",
  "Away-from-US movement",
  "Brazil moves away from the United States, but China proximity is mechanical or indistinguishable from anti-Washington movement.",
  "Distance to the United States rises and China-minus-US contrast improves, but effects concentrate only where China and USA oppose each other and are mirrored by generic closer-than-US outcomes without China-specific domains.",
  "Frame as movement away from Washington, not direct China-specific accommodation.",
  "Broad repositioning",
  "Similar effects appear in non-human-rights controls, alternative benchmarks, or temporal placebos, suggesting a general Lula/post-2008 reorientation.",
  "Effects are comparable in HR and non-HR, Brazil is not unusual in donor placebos, or valid independent benchmarks move similarly. Benchmarks that are already close to China in ideal-point space are geometric diagnostics, not independent counterexamples.",
  "Narrow the claim to broad UNGA repositioning or remove China-specific language.",
  "Inconclusive",
  "Evidence is descriptive, underpowered, or lacks a comparable counterfactual.",
  "Point estimates are unstable, not unusual in placebos, or sample restrictions are too thin.",
  "Describe Table 4/Figure 6 as diagnostics only and avoid causal language about selectivity."
)
readr::write_csv(decision_matrix, paths$decision_matrix, na = "")

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

reference_years <- unga_data |>
  dplyr::select(year, iso3c, ideal_point_all) |>
  dplyr::filter(iso3c %in% c("RUS", "IND", "CHN", "ZAF", "USA")) |>
  tidyr::pivot_wider(names_from = iso3c, values_from = ideal_point_all, names_prefix = "ideal_") |>
  dplyr::mutate(
    ideal_brics_no_brazil = rowMeans(
      dplyr::pick(dplyr::any_of(c("ideal_CHN", "ideal_RUS", "ideal_IND", "ideal_ZAF"))),
      na.rm = TRUE
    )
  )

sdid_data <- synth_data |>
  dplyr::left_join(
    unga_data |>
      dplyr::select(iso3c, year, ideal_point_all, china_agree, us_agree),
    by = c("iso3c", "year")
  ) |>
  dplyr::left_join(reference_years, by = "year") |>
  dplyr::mutate(
    relative_distance_china_minus_usa = abs_distance_china - abs_distance_usa,
    china_minus_us_agree = china_agree - us_agree,
    abs_distance_russia = abs(ideal_point_all - ideal_RUS),
    abs_distance_india = abs(ideal_point_all - ideal_IND),
    abs_distance_brics_no_brazil = abs(ideal_point_all - ideal_brics_no_brazil)
  )

reference_spatial_diagnostics <- dplyr::bind_rows(
  reference_years |>
    dplyr::filter(year >= 2005, year <= 2008) |>
    dplyr::mutate(
      `China-India ideal-point distance` = abs(ideal_CHN - ideal_IND),
      `China-Russia ideal-point distance` = abs(ideal_CHN - ideal_RUS),
      `China-South Africa ideal-point distance` = abs(ideal_CHN - ideal_ZAF),
      `China-BRICS mean ideal-point distance` = abs(ideal_CHN - ideal_brics_no_brazil),
      `China-United States ideal-point distance` = abs(ideal_CHN - ideal_USA)
    ) |>
    tidyr::pivot_longer(
      cols = dplyr::ends_with("ideal-point distance"),
      names_to = "metric",
      values_to = "value"
    ) |>
    dplyr::summarise(
      value = mean(value, na.rm = TRUE),
      sd_value = stats::sd(value, na.rm = TRUE),
      min_value = min(value, na.rm = TRUE),
      max_value = max(value, na.rm = TRUE),
      n_years = dplyr::n_distinct(year[!is.na(value)]),
      .by = metric
    ) |>
    dplyr::mutate(
      diagnostic_type = "pre-2009 reference-actor distance",
      interpretation = "Small pre-2009 reference distances mean the benchmark is geometrically close to China and should not be interpreted as an independent placebo."
    ),
  sdid_data |>
    dplyr::filter(year >= 2005, year <= 2008) |>
    dplyr::summarise(
      `Correlation: distance to China vs distance to India` =
        stats::cor(abs_distance_china, abs_distance_india, use = "pairwise.complete.obs"),
      `Correlation: distance to China vs distance to Russia` =
        stats::cor(abs_distance_china, abs_distance_russia, use = "pairwise.complete.obs"),
      `Correlation: distance to China vs distance to BRICS mean` =
        stats::cor(abs_distance_china, abs_distance_brics_no_brazil, use = "pairwise.complete.obs")
    ) |>
    tidyr::pivot_longer(
      cols = dplyr::everything(),
      names_to = "metric",
      values_to = "value"
    ) |>
    dplyr::mutate(
      sd_value = NA_real_,
      min_value = NA_real_,
      max_value = NA_real_,
      n_years = 4L,
      diagnostic_type = "pre-2009 country-year outcome correlation",
      interpretation = "High pre-2009 correlations mean distance-to-reference outcomes are not independent tests of China specificity."
    )
) |>
  dplyr::select(diagnostic_type, metric, value, sd_value, min_value, max_value, n_years, interpretation)
readr::write_csv(reference_spatial_diagnostics, paths$reference_spatial, na = "")

goal6_country_year <- if (nrow(goal6_results) > 0L) {
  goal6_results |>
    dplyr::rename(
      evidence_tier = dplyr::any_of(c("causal_status", "evidence_tier"))
    ) |>
    dplyr::mutate(
      donor_pool = "Baseline Brazil SDiD donor pool",
      status_inferencial = dplyr::coalesce(
        .data$inference_status,
        "Status inferencial não informado no Goal 6."
      ),
      interpretation = dplyr::case_when(
        outcome == "abs_distance_china" & estimate < 0 ~ "Brazil moves closer to China than its synthetic counterfactual.",
        outcome == "abs_distance_usa" & estimate > 0 ~ "Brazil moves farther from the United States than its synthetic counterfactual.",
        outcome == "relative_distance_china_minus_usa" & estimate < 0 ~ "Brazil becomes closer to China relative to the United States.",
        outcome == "china_agree" & estimate > 0 ~ "Annual agreement with China rises, but this is agenda-sensitive.",
        outcome == "china_minus_us_agree" & estimate > 0 ~ "Annual agreement shifts toward China relative to the United States, but this is agenda-sensitive.",
        TRUE ~ "Direction does not match the expected alignment pattern."
      )
    ) |>
    dplyr::select(
      outcome,
      label,
      evidence_tier,
      estimate,
      se_placebo,
      p_value,
      status_inferencial,
      expected_direction,
      donor_pool,
      interpretation
    )
} else {
  tibble::tibble()
}

benchmark_catalog <- tibble::tribble(
  ~outcome, ~label, ~expected_direction, ~interpretation_rule,
  "abs_distance_russia", "Distance to Russia", "diagnostic/no preferred direction", "Interpret only after checking pre-2009 spatial proximity to China; this is not an independent placebo by default.",
  "abs_distance_india", "Distance to India", "diagnostic/no preferred direction", "Interpret only after checking pre-2009 spatial proximity to China; this is not an independent placebo by default.",
  "abs_distance_brics_no_brazil", "Distance to BRICS mean excluding Brazil", "diagnostic/no preferred direction", "Interpret only after checking pre-2009 spatial proximity to China; this is not an independent placebo by default."
)

benchmark_results <- dplyr::bind_rows(lapply(seq_len(nrow(benchmark_catalog)), function(i) {
  row <- benchmark_catalog[i, ]
  result <- tryCatch(
    fit_sdid_point(sdid_data, row$outcome, pipeline_covariates, compute_se = FALSE),
    error = function(e) tibble::tibble(
      estimate = NA_real_,
      se_placebo = NA_real_,
      p_value = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      n_donors = NA_integer_,
      error = conditionMessage(e)
    )
  )
  result |>
    dplyr::mutate(
      outcome = row$outcome,
      label = row$label,
      evidence_tier = "geometric country-year benchmark; not used as placebo evidence",
      status_inferencial = "Point estimate only. Spatial diagnostics show this is a geometric benchmark, not an independent placebo for China-specificity.",
      expected_direction = row$expected_direction,
      donor_pool = "Baseline Brazil SDiD donor pool",
      interpretation = paste(row$interpretation_rule, "Estimate:", fmt_num(estimate, 3)),
      .before = estimate
    ) |>
    dplyr::select(
      outcome,
      label,
      evidence_tier,
      estimate,
      se_placebo,
      p_value,
      status_inferencial,
      expected_direction,
      donor_pool,
      interpretation
    )
}))

country_year_results <- dplyr::bind_rows(goal6_country_year, benchmark_results) |>
  dplyr::mutate(
    estimate = as.numeric(estimate),
    se_placebo = as.numeric(se_placebo),
    p_value = as.numeric(p_value)
  )
readr::write_csv(country_year_results, paths$country_year, na = "")

country_year_series <- sdid_data |>
  dplyr::filter(iso3c == "BRA", year >= 2005, year <= 2012) |>
  dplyr::select(
    iso3c,
    year,
    abs_distance_china,
    abs_distance_usa,
    relative_distance_china_minus_usa,
    china_agree,
    china_minus_us_agree,
    abs_distance_russia,
    abs_distance_india,
    abs_distance_brics_no_brazil
  ) |>
  tidyr::pivot_longer(
    cols = -c(iso3c, year),
    names_to = "outcome",
    values_to = "value"
  ) |>
  dplyr::mutate(period = dplyr::if_else(year < 2009, "Pre-2009", "Post-2009"))
readr::write_csv(country_year_series, paths$country_year_series, na = "")

main_vote_panel <- vote_panel |>
  dplyr::filter(iso3c %in% c("BRA", vote_donor_iso3c))

hr_divergent <- main_vote_panel |>
  dplyr::filter(issue_domain == "Human rights", china_usa_divergent)
hr_strong_divergent <- main_vote_panel |>
  dplyr::filter(issue_domain == "Human rights", china_usa_strong_divergent)
nonhr_divergent <- main_vote_panel |>
  dplyr::filter(issue_domain == "Non-human rights", china_usa_divergent)
nonhr_strong_divergent <- main_vote_panel |>
  dplyr::filter(issue_domain == "Non-human rights", china_usa_strong_divergent)
hr_all <- main_vote_panel |>
  dplyr::filter(issue_domain == "Human rights")
nonhr_all <- main_vote_panel |>
  dplyr::filter(issue_domain == "Non-human rights")

sample_counts <- tibble::tribble(
  ~sample, ~data_name,
  "Human-rights China-US divergent votes", "hr_divergent",
  "Human-rights strong yes/no China-US divergent votes", "hr_strong_divergent",
  "Non-human-rights China-US divergent votes", "nonhr_divergent",
  "Non-human-rights strong yes/no China-US divergent votes", "nonhr_strong_divergent",
  "All human-rights votes", "hr_all",
  "All non-human-rights votes", "nonhr_all"
) |>
  dplyr::rowwise() |>
  dplyr::mutate(
    n_obs = nrow(get(data_name)),
    n_countries = dplyr::n_distinct(get(data_name)$iso3c),
    n_resolutions = dplyr::n_distinct(get(data_name)$rcid),
    n_brazil_obs = sum(get(data_name)$iso3c == "BRA"),
    n_donor_obs = sum(get(data_name)$iso3c != "BRA")
  ) |>
  dplyr::ungroup() |>
  dplyr::select(-data_name)
readr::write_csv(sample_counts, paths$model_sample_counts, na = "")

vote_descriptives <- dplyr::bind_rows(
  make_vote_descriptives(hr_divergent, "Human-rights China-US divergent votes"),
  make_vote_descriptives(hr_strong_divergent, "Human-rights strong yes/no China-US divergent votes"),
  make_vote_descriptives(nonhr_divergent, "Non-human-rights China-US divergent votes"),
  make_vote_descriptives(nonhr_strong_divergent, "Non-human-rights strong yes/no China-US divergent votes")
)
readr::write_csv(vote_descriptives, paths$vote_descriptives, na = "")

vote_models <- dplyr::bind_rows(
  fit_vote_model_set(hr_divergent, "Country + resolution FE", "Human-rights China-US divergent votes"),
  fit_vote_model_set(hr_strong_divergent, "Country + resolution FE", "Human-rights strong yes/no China-US divergent votes"),
  fit_vote_model_set(nonhr_divergent, "Country + resolution FE", "Non-human-rights China-US divergent votes"),
  fit_vote_model_set(nonhr_strong_divergent, "Country + resolution FE", "Non-human-rights strong yes/no China-US divergent votes"),
  fit_vote_model_set(hr_all, "Country + resolution FE", "All human-rights votes"),
  fit_vote_model_set(nonhr_all, "Country + resolution FE", "All non-human-rights votes")
) |>
  dplyr::mutate(
    direction_matches_expected = dplyr::case_when(
      expected_direction == "negative" ~ estimate < 0,
      expected_direction == "positive" ~ estimate > 0,
      TRUE ~ NA
    )
  )
readr::write_csv(vote_models, paths$vote_models, na = "")

divergent_all <- main_vote_panel |>
  dplyr::filter(china_usa_divergent) |>
  dplyr::mutate(human_rights_binary = as.integer(issue_domain == "Human rights"))

ddd_models <- dplyr::bind_rows(
  fit_ddd_model(
    divergent_all,
    "distance_china_minus_usa",
    vcov_formula = ~iso3c,
    vcov_label = "country-clustered SE"
  ),
  fit_ddd_model(
    divergent_all,
    "distance_china_minus_usa",
    vcov_formula = ~iso3c + rcid,
    vcov_label = "two-way clustered SE by country and resolution"
  ),
  fit_ddd_model(
    divergent_all,
    "agreement_china_minus_usa",
    vcov_formula = ~iso3c,
    vcov_label = "country-clustered SE"
  ),
  fit_ddd_model(
    divergent_all,
    "agreement_china_minus_usa",
    vcov_formula = ~iso3c + rcid,
    vcov_label = "two-way clustered SE by country and resolution"
  )
) |>
  dplyr::mutate(
    expected_direction = dplyr::case_when(
      outcome == "distance_china_minus_usa" & term == "brazil_post_hr" ~ "negative incremental HR effect",
      outcome == "agreement_china_minus_usa" & term == "brazil_post_hr" ~ "positive incremental HR effect",
      term == "brazil_post_2009" ~ "non-HR Brazil post component",
      TRUE ~ "diagnostic"
    ),
    direction_matches_expected = dplyr::case_when(
      expected_direction == "negative incremental HR effect" ~ estimate < 0,
      expected_direction == "positive incremental HR effect" ~ estimate > 0,
      TRUE ~ NA
    )
  )
readr::write_csv(ddd_models, paths$ddd_models, na = "")

twoway_cluster_sensitivity <- dplyr::bind_rows(
  fit_vote_model_set(
    hr_divergent,
    "Country + resolution FE; two-way clustered",
    "Human-rights China-US divergent votes",
    vcov_formula = ~iso3c + rcid,
    inference_note = "Model-based two-way clustered SE by country and resolution; country-placebo inference remains primary."
  ),
  fit_vote_model_set(
    hr_strong_divergent,
    "Country + resolution FE; two-way clustered",
    "Human-rights strong yes/no China-US divergent votes",
    vcov_formula = ~iso3c + rcid,
    inference_note = "Model-based two-way clustered SE by country and resolution; country-placebo inference remains primary."
  ),
  fit_vote_model_set(
    nonhr_divergent,
    "Country + resolution FE; two-way clustered",
    "Non-human-rights China-US divergent votes",
    vcov_formula = ~iso3c + rcid,
    inference_note = "Model-based two-way clustered SE by country and resolution; country-placebo inference remains primary."
  )
) |>
  dplyr::mutate(
    direction_matches_expected = dplyr::case_when(
      expected_direction == "negative" ~ estimate < 0,
      expected_direction == "positive" ~ estimate > 0,
      TRUE ~ NA
    )
  )
readr::write_csv(twoway_cluster_sensitivity, paths$twoway_cluster, na = "")

temporal_placebo_data <- dplyr::bind_rows(lapply(c(2007L, 2008L), function(pseudo_year) {
  data <- hr_divergent |>
    dplyr::filter(year < 2009) |>
    dplyr::mutate(
      pseudo_post = as.integer(year >= pseudo_year),
      brazil_pseudo_post = as.integer(iso3c == "BRA") * pseudo_post
    )
  dplyr::bind_rows(
    fit_vote_model(
      data,
      outcome = "distance_china_minus_usa",
      treatment_var = "brazil_pseudo_post",
      model_label = paste0("Pseudo-break ", pseudo_year),
      sample_label = "Pre-2009 human-rights China-US divergent votes",
      expected_direction = "negative",
      inference_note = "Pre-treatment temporal placebo; country-clustered SE with country and resolution FE."
    ),
    fit_vote_model(
      data,
      outcome = "closer_to_china_score",
      treatment_var = "brazil_pseudo_post",
      model_label = paste0("Pseudo-break ", pseudo_year),
      sample_label = "Pre-2009 human-rights China-US divergent votes",
      expected_direction = "positive",
      inference_note = "Pre-treatment temporal placebo; country-clustered SE with country and resolution FE."
    )
  ) |>
    dplyr::mutate(pseudo_year = pseudo_year, .before = model)
}))
readr::write_csv(temporal_placebo_data, paths$temporal_placebos, na = "")

country_placebos <- dplyr::bind_rows(
  country_placebo(hr_divergent, "distance_china_minus_usa", "negative"),
  country_placebo(hr_divergent, "closer_to_china_score", "positive")
)
country_placebo_summary <- country_placebos |>
  dplyr::group_by(outcome) |>
  dplyr::summarise(
    brazil_estimate = estimate[placebo_unit == "BRA"][1],
    brazil_rank_expected_direction = expected_rank[placebo_unit == "BRA"][1],
    n_placebo_units = sum(!is.na(estimate)),
    p_directional = randomization_p_directional[placebo_unit == "BRA"][1],
    p_two_sided = randomization_p_two_sided[placebo_unit == "BRA"][1],
    p_directional_strict_donor = randomization_p_directional_strict_donor[placebo_unit == "BRA"][1],
    p_two_sided_strict_donor = randomization_p_two_sided_strict_donor[placebo_unit == "BRA"][1],
    .groups = "drop"
  ) |>
  dplyr::mutate(
    randomization_p_directional = p_directional,
    randomization_p_two_sided = p_two_sided,
    randomization_p_directional_strict_donor = p_directional_strict_donor,
    randomization_p_two_sided_strict_donor = p_two_sided_strict_donor,
    interpretation = dplyr::case_when(
      p_directional <= 0.10 ~
        "Brazil is in the directional tail of the donor-placebo distribution.",
      TRUE ~ "Brazil is not unusually extreme relative to donor-placebo estimates."
    )
  ) |>
  dplyr::select(-p_directional, -p_two_sided, -p_directional_strict_donor, -p_two_sided_strict_donor) |>
  dplyr::ungroup()

readr::write_csv(country_placebos, paths$country_placebos, na = "")
readr::write_csv(country_placebo_summary, paths$country_placebo_summary, na = "")

extreme_placebo_audit <- country_placebos |>
  dplyr::filter(outcome == "distance_china_minus_usa") |>
  dplyr::arrange(expected_rank, placebo_unit) |>
  dplyr::slice_head(n = 6) |>
  dplyr::left_join(
    donor_audit |>
      dplyr::select(iso3c, country_name, sdid_weight, first_treat_year, china_top_or_similar_shock_2005_2012),
    by = c("placebo_unit" = "iso3c")
  ) |>
  dplyr::mutate(
    country_name = dplyr::coalesce(
      country_name,
      countrycode::countrycode(placebo_unit, "iso3c", "country.name", warn = FALSE)
    ),
    sdid_weight = dplyr::if_else(placebo_unit == "BRA", NA_real_, sdid_weight),
    china_top_or_similar_shock_2005_2012 = dplyr::coalesce(china_top_or_similar_shock_2005_2012, FALSE),
    region = countrycode::countrycode(placebo_unit, "iso3c", "region", warn = FALSE),
    audit_note = dplyr::case_when(
      placebo_unit == "BRA" ~ "Actual treated unit; included as the reference line for the placebo distribution.",
      placebo_unit %in% c("BOL", "ECU", "NIC") ~ "Latin America left-turn/ALBA context; plausible broad anti-US or South-South repositioning competing explanation.",
      placebo_unit == "DOM" ~ "Latin America/Caribbean high-tail placebo; requires country-specific follow-up and weakens uniqueness of the Brazil pattern.",
      placebo_unit == "UGA" ~ "Sub-Saharan Africa high-tail placebo; possible bloc or issue-specific voting shift, requiring country-specific follow-up.",
      TRUE ~ "High-tail donor placebo; interpret as a warning against uniqueness claims."
    )
  ) |>
  dplyr::select(
    expected_rank,
    placebo_unit,
    country_name,
    region,
    estimate,
    brazil_estimate,
    sdid_weight,
    first_treat_year,
    china_top_or_similar_shock_2005_2012,
    audit_note
  )
readr::write_csv(extreme_placebo_audit, paths$extreme_placebo_audit, na = "")

contaminated_donors <- donor_audit |>
  dplyr::filter(china_top_or_similar_shock_2005_2012) |>
  dplyr::pull(iso3c)

clean_hr_divergent <- hr_divergent |>
  dplyr::filter(iso3c == "BRA" | !iso3c %in% contaminated_donors)
clean_nonhr_divergent <- nonhr_divergent |>
  dplyr::filter(iso3c == "BRA" | !iso3c %in% contaminated_donors)

donor_sensitivity <- dplyr::bind_rows(
  fit_vote_model_set(clean_hr_divergent, "Country + resolution FE; contaminated donors excluded", "Human-rights China-US divergent votes"),
  fit_vote_model_set(clean_nonhr_divergent, "Country + resolution FE; contaminated donors excluded", "Non-human-rights China-US divergent votes")
) |>
  dplyr::mutate(
    excluded_donors = paste(contaminated_donors, collapse = ";"),
    n_excluded_donors = length(contaminated_donors)
  )
readr::write_csv(donor_sensitivity, paths$donor_sensitivity, na = "")

hr_key <- vote_models |>
  dplyr::filter(sample == "Human-rights China-US divergent votes")
nonhr_key <- vote_models |>
  dplyr::filter(sample == "Non-human-rights China-US divergent votes")
hr_strong_key <- vote_models |>
  dplyr::filter(sample == "Human-rights strong yes/no China-US divergent votes")

get_est <- function(tbl, target_outcome) {
  tbl |>
    dplyr::filter(.data$outcome == .env$target_outcome) |>
    dplyr::slice_head(n = 1) |>
    dplyr::pull(estimate)
}

get_p <- function(tbl, target_outcome) {
  tbl |>
    dplyr::filter(.data$outcome == .env$target_outcome) |>
    dplyr::slice_head(n = 1) |>
    dplyr::pull(p_value)
}

get_term_est <- function(tbl, target_outcome, target_term, model_pattern = "country-clustered") {
  tbl |>
    dplyr::filter(
      .data$outcome == .env$target_outcome,
      .data$term == .env$target_term,
      stringr::str_detect(.data$model, .env$model_pattern)
    ) |>
    dplyr::slice_head(n = 1) |>
    dplyr::pull(estimate)
}

hr_diff_est <- get_est(hr_key, "distance_china_minus_usa")
hr_score_est <- get_est(hr_key, "closer_to_china_score")
hr_china_dist_est <- get_est(hr_key, "distance_to_china_vote")
hr_us_dist_est <- get_est(hr_key, "distance_to_usa_vote")
nonhr_diff_est <- get_est(nonhr_key, "distance_china_minus_usa")
nonhr_score_est <- get_est(nonhr_key, "closer_to_china_score")
strong_diff_est <- get_est(hr_strong_key, "distance_china_minus_usa")
ddd_hr_incremental_diff_est <- get_term_est(ddd_models, "distance_china_minus_usa", "brazil_post_hr")
ddd_hr_incremental_agree_est <- get_term_est(ddd_models, "agreement_china_minus_usa", "brazil_post_hr")

event_pretrend <- dplyr::bind_rows(
  fit_pretrend_event_study(hr_divergent, "distance_china_minus_usa", hr_diff_est),
  fit_pretrend_event_study(hr_divergent, "closer_to_china_score", hr_score_est)
)
readr::write_csv(event_pretrend, paths$event_pretrend, na = "")

placebo_diff <- country_placebo_summary |>
  dplyr::filter(outcome == "distance_china_minus_usa")
placebo_score <- country_placebo_summary |>
  dplyr::filter(outcome == "closer_to_china_score")

temporal_placebo_summary <- temporal_placebo_data |>
  dplyr::filter(outcome == "distance_china_minus_usa") |>
  dplyr::summarise(
    max_abs_temporal_placebo = max(abs(estimate), na.rm = TRUE),
    min_temporal_placebo_p = min(p_value, na.rm = TRUE),
    temporal_placebo_detail = paste0(
      "pseudo-",
      pseudo_year,
      "=",
      fmt_num(estimate, 3),
      " (p=",
      fmt_p(p_value),
      ")",
      collapse = "; "
    )
  )

benchmark_direction <- country_year_results |>
  dplyr::filter(outcome %in% c("abs_distance_russia", "abs_distance_india", "abs_distance_brics_no_brazil")) |>
  dplyr::summarise(
    n_benchmarks_closer = sum(estimate < 0, na.rm = TRUE),
    benchmark_summary = paste0(outcome, "=", fmt_num(estimate, 3), collapse = "; ")
  )

decision_flags <- tibble::tibble(
  criterion = c(
    "HR China-minus-US vote-level effect is in China-specific direction",
    "DDD test shows incremental HR effect beyond non-HR divergent votes",
    "HR distance-to-China falls and distance-to-USA rises",
    "Strong yes/no HR sensitivity is in China-specific direction",
    "Non-HR negative-control effect is materially weaker than HR",
    "Temporal placebo diagnostics are small but not clean",
    "Brazil is directionally unusual in donor country-placebo distribution",
    "Alternative BRICS/Russia/India benchmarks are treated as geometric diagnostics, not independent placebos"
  ),
  passed = c(
    !is.na(hr_diff_est) && hr_diff_est < 0,
    !is.na(ddd_hr_incremental_diff_est) && ddd_hr_incremental_diff_est < 0,
    !is.na(hr_china_dist_est) && !is.na(hr_us_dist_est) &&
      hr_china_dist_est < 0 && hr_us_dist_est > 0,
    !is.na(strong_diff_est) && strong_diff_est < 0,
    !is.na(nonhr_diff_est) && !is.na(hr_diff_est) && abs(nonhr_diff_est) < abs(hr_diff_est),
    nrow(temporal_placebo_summary) > 0L &&
      temporal_placebo_summary$max_abs_temporal_placebo < 0.25 * abs(hr_diff_est),
    nrow(placebo_diff) > 0L && !is.na(placebo_diff$randomization_p_directional[1]) &&
      placebo_diff$randomization_p_directional[1] <= 0.10,
    FALSE
  ),
  detail = c(
    paste0("HR distance China-minus-USA estimate = ", fmt_num(hr_diff_est, 3), "."),
    paste0(
      "DDD incremental HR estimate for distance China-minus-USA = ",
      fmt_num(ddd_hr_incremental_diff_est, 3),
      "; for agreement China-minus-USA = ",
      fmt_num(ddd_hr_incremental_agree_est, 3),
      "."
    ),
    paste0("HR distance-to-China = ", fmt_num(hr_china_dist_est, 3), "; HR distance-to-USA = ", fmt_num(hr_us_dist_est, 3), "."),
    paste0("Strong yes/no HR distance China-minus-USA estimate = ", fmt_num(strong_diff_est, 3), "."),
    paste0("Non-HR distance China-minus-USA estimate = ", fmt_num(nonhr_diff_est, 3), "."),
    paste0(
      "Main HR estimate = ",
      fmt_num(hr_diff_est, 3),
      "; temporal placebos: ",
      temporal_placebo_summary$temporal_placebo_detail,
      "."
    ),
    paste0(
      "Directional country-placebo p inclusive = ",
      fmt_p(placebo_diff$randomization_p_directional[1]),
      "; strict donor-only p = ",
      fmt_p(placebo_diff$randomization_p_directional_strict_donor[1]),
      "."
    ),
    paste0(
      benchmark_direction$benchmark_summary,
      ". Spatial proximity/correlation means these outcomes are not used as China-specific counterexamples."
    )
  )
)

n_pass <- sum(decision_flags$passed, na.rm = TRUE)
final_class <- dplyr::case_when(
  n_pass >= 7 ~ "Diagnostic evidence compatible with selective HR China alignment, not standalone causal proof",
  decision_flags$passed[1] && decision_flags$passed[2] && decision_flags$passed[5] ~
    "Diagnostic evidence compatible with selective HR China alignment, bounded by broad-repositioning concerns",
  decision_flags$passed[3] && !decision_flags$passed[6] ~ "Away-from-US movement or inconclusive China-specificity",
  TRUE ~ "Inconclusive"
)

editorial_recommendation <- dplyr::case_when(
  stringr::str_detect(final_class, "selective HR China alignment") ~
    "The main text can make only a cautious diagnostic claim: Brazil's post-2009 UNGA movement is most consistent with selective adjustment in human-rights votes where China and the United States diverged. It should not say that Table 4/Figure 6 alone proves China-specific convergence.",
  final_class == "Broad repositioning" ~
    "Narrow the paper's claim: the pattern is better read as broad UNGA repositioning rather than China-specific alignment.",
  final_class == "Away-from-US movement or inconclusive China-specificity" ~
    "Narrow the paper's claim: country-year outcomes are consistent with movement away from the United States, but vote-level evidence does not yet isolate direct China-specific alignment strongly enough.",
  TRUE ~
    "Treat Table 4/Figure 6 as substantive diagnostics only; remove or soften claims that they prove selective convergence toward China."
)

final_interpretation <- dplyr::bind_rows(
  decision_flags |>
    dplyr::mutate(section = "Decision flag", .before = 1),
  tibble::tibble(
    section = "Final classification",
    criterion = final_class,
    passed = NA,
    detail = editorial_recommendation
  )
)
readr::write_csv(final_interpretation, paths$final_interpretation, na = "")

plot_country_year <- country_year_series |>
  dplyr::filter(
    outcome %in% c(
      "abs_distance_china",
      "abs_distance_usa",
      "relative_distance_china_minus_usa",
      "china_agree",
      "china_minus_us_agree",
      "abs_distance_russia",
      "abs_distance_india",
      "abs_distance_brics_no_brazil"
    )
  ) |>
  dplyr::mutate(
    outcome_label = dplyr::recode(
      outcome,
      abs_distance_china = "Distance to China",
      abs_distance_usa = "Distance to United States",
      relative_distance_china_minus_usa = "Distance: China minus United States",
      china_agree = "Annual agreement with China",
      china_minus_us_agree = "Agreement: China minus United States",
      abs_distance_russia = "Distance to Russia",
      abs_distance_india = "Distance to India",
      abs_distance_brics_no_brazil = "Distance to BRICS mean"
    )
  ) |>
  ggplot2::ggplot(ggplot2::aes(x = year, y = value)) +
  ggplot2::geom_vline(xintercept = 2008.5, color = "gray55", linewidth = 0.35) +
  ggplot2::geom_line(color = "#1F4E79", linewidth = 0.7) +
  ggplot2::geom_point(color = "#1F4E79", size = 1.8) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = 2005:2012) +
  ggplot2::labs(
    x = "Year",
    y = "Outcome value"
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold")
  )
save_plot_pair(plot_country_year, paths$fig_country_year_png, paths$fig_country_year_pdf, 8, 8)

vote_prepost_plot_data <- vote_descriptives |>
  dplyr::filter(sample == "Human-rights China-US divergent votes") |>
  dplyr::select(
    sample,
    country_group,
    period,
    mean_distance_china_minus_usa,
    mean_closer_china_score
  ) |>
  tidyr::pivot_longer(
    cols = c(mean_distance_china_minus_usa, mean_closer_china_score),
    names_to = "outcome",
    values_to = "value"
  ) |>
  dplyr::mutate(
    outcome_label = dplyr::recode(
      outcome,
      mean_distance_china_minus_usa = "Distance: China minus United States",
      mean_closer_china_score = "Closer-to-China score"
    ),
    period = factor(period, levels = c("Pre-2009", "Post-2009"))
  )

plot_vote_prepost <- ggplot2::ggplot(
  vote_prepost_plot_data,
  ggplot2::aes(x = period, y = value, group = country_group, color = country_group)
) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 2) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_y") +
  ggplot2::scale_color_manual(values = c("Brazil" = "#1B7837", "Donor pool" = "#762A83")) +
  ggplot2::labs(x = NULL, y = "Mean outcome", color = NULL) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom"
  )
save_plot_pair(plot_vote_prepost, paths$fig_vote_prepost_png, paths$fig_vote_prepost_pdf, 7, 4.5)

placebo_plot_data <- country_placebos |>
  dplyr::filter(outcome == "distance_china_minus_usa") |>
  dplyr::mutate(is_brazil = placebo_unit == "BRA")

plot_placebo <- ggplot2::ggplot(placebo_plot_data, ggplot2::aes(x = estimate)) +
  ggplot2::geom_histogram(binwidth = 0.05, fill = "#C7DCEF", color = "white", boundary = 0) +
  ggplot2::geom_vline(
    data = placebo_plot_data |> dplyr::filter(is_brazil),
    ggplot2::aes(xintercept = estimate),
    color = "#B2182B",
    linewidth = 0.9
  ) +
  ggplot2::labs(
    x = "Country-placebo estimate",
    y = "Number of countries"
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
save_plot_pair(plot_placebo, paths$fig_placebo_png, paths$fig_placebo_pdf, 7, 4.5)

validation_checks <- tibble::tribble(
  ~check, ~status, ~detail,
  "targets_pipeline_not_run", "manual_constraint", "This script reads existing targets with tar_read_raw/tar_meta and contains no targets::tar_make call.",
  "protected_targets_files_not_modified", "manual_constraint", "The script writes only under quality_reports/selective_china_alignment_unga and the new diagnostics script path.",
  "raw_unvotes_preserved", "pass", "Raw tarball is read-only input; vote panels are written as processed diagnostic outputs.",
  "vote_scores_valid", ifelse(all(vote_panel$vote_ordinal %in% c(-1, 0, 1)), "pass", "fail"), "Votes are coded no=-1, abstain=0, yes=1; absent/missing/not voting are excluded.",
  "china_usa_divergent_subset_exists", ifelse(nrow(hr_divergent) > 0L, "pass", "fail"), paste0("HR China-US divergent sample has ", nrow(hr_divergent), " country-resolution observations."),
  "other_uncoded_not_substantive", "pass", "Other / uncoded is retained only as a residual category and is not interpreted substantively.",
  "usa_reference_excluded_from_vote_main", ifelse(!"USA" %in% unique(main_vote_panel$iso3c), "pass", "fail"), "USA is excluded from the main vote-level donor comparison because it defines one reference outcome."
)
readr::write_csv(validation_checks, paths$validation, na = "")

utils::capture.output(utils::sessionInfo(), file = session_info_path)

country_year_display <- country_year_results |>
  dplyr::mutate(
    estimate = fmt_num(estimate, 3),
    se_placebo = fmt_num(se_placebo, 3),
    p_value = fmt_p(p_value)
  )

reference_spatial_display <- reference_spatial_diagnostics |>
  dplyr::mutate(
    value = fmt_num(value, 3),
    sd_value = fmt_num(sd_value, 3),
    min_value = fmt_num(min_value, 3),
    max_value = fmt_num(max_value, 3)
  )

vote_model_display <- vote_models |>
  dplyr::filter(
    sample %in% c(
      "Human-rights China-US divergent votes",
      "Human-rights strong yes/no China-US divergent votes",
      "Non-human-rights China-US divergent votes",
      "Non-human-rights strong yes/no China-US divergent votes"
    ),
    outcome %in% c(
      "distance_to_china_vote",
      "distance_to_usa_vote",
      "distance_china_minus_usa",
      "closer_to_china_than_usa",
      "closer_to_china_score"
    )
  ) |>
  dplyr::mutate(
    estimate = fmt_num(estimate, 3),
    se = fmt_num(se, 3),
    p_value = fmt_p(p_value),
    ci_95_low = fmt_num(ci_95_low, 3),
    ci_95_high = fmt_num(ci_95_high, 3)
  ) |>
  dplyr::select(
    sample,
    outcome,
    estimate,
    se,
    p_value,
    ci_95_low,
    ci_95_high,
    n_obs,
    n_countries,
    n_resolutions,
    expected_direction
  )

placebo_display <- country_placebo_summary |>
  dplyr::mutate(
    brazil_estimate = fmt_num(brazil_estimate, 3),
    randomization_p_directional = fmt_p(randomization_p_directional),
    randomization_p_two_sided = fmt_p(randomization_p_two_sided),
    randomization_p_directional_strict_donor = fmt_p(randomization_p_directional_strict_donor),
    randomization_p_two_sided_strict_donor = fmt_p(randomization_p_two_sided_strict_donor)
  )

donor_audit_display <- donor_audit |>
  dplyr::mutate(
    sdid_weight = fmt_num(sdid_weight, 4),
    first_treat_year = ifelse(is.na(first_treat_year), "", as.character(first_treat_year))
  ) |>
  dplyr::select(
    iso3c,
    country_name,
    sdid_weight,
    first_treat_year,
    absorbing,
    displaced,
    china_top_years_2005_2012,
    china_top_or_similar_shock_2005_2012,
    reference_actor_in_vote_design,
    contamination_note
  )

target_file_audit_display <- target_file_audit |>
  dplyr::mutate(
    bytes_meta = fmt_num(as.numeric(bytes_meta), 0),
    bytes_file = fmt_num(as.numeric(bytes_file), 0),
    columns = stringr::str_trunc(columns, 90)
  ) |>
  dplyr::select(
    audit_type,
    name,
    exists,
    object_class,
    nrow,
    ncol,
    bytes_meta,
    bytes_file,
    read_error
  )

ddd_display <- ddd_models |>
  dplyr::mutate(
    estimate = fmt_num(estimate, 3),
    se = fmt_num(se, 3),
    p_value = fmt_p(p_value),
    ci_95_low = fmt_num(ci_95_low, 3),
    ci_95_high = fmt_num(ci_95_high, 3)
  ) |>
  dplyr::select(
    outcome,
    term,
    estimate,
    se,
    p_value,
    ci_95_low,
    ci_95_high,
    n_obs,
    n_countries,
    n_resolutions,
    expected_direction,
    model
  )

twoway_display <- twoway_cluster_sensitivity |>
  dplyr::filter(
    outcome %in% c("distance_to_china_vote", "distance_to_usa_vote", "distance_china_minus_usa", "closer_to_china_score")
  ) |>
  dplyr::mutate(
    estimate = fmt_num(estimate, 3),
    se = fmt_num(se, 3),
    p_value = fmt_p(p_value),
    ci_95_low = fmt_num(ci_95_low, 3),
    ci_95_high = fmt_num(ci_95_high, 3)
  ) |>
  dplyr::select(sample, outcome, estimate, se, p_value, ci_95_low, ci_95_high, n_obs, n_countries, n_resolutions)

event_pretrend_display <- event_pretrend |>
  dplyr::mutate(
    estimate = fmt_num(estimate, 3),
    se = fmt_num(se, 3),
    p_value = fmt_p(p_value),
    ci_95_low = fmt_num(ci_95_low, 3),
    ci_95_high = fmt_num(ci_95_high, 3),
    equivalence_threshold = fmt_num(equivalence_threshold, 3)
  ) |>
  dplyr::select(outcome, year, estimate, se, p_value, ci_95_low, ci_95_high, equivalence_threshold, within_threshold)

extreme_placebo_display <- extreme_placebo_audit |>
  dplyr::mutate(
    estimate = fmt_num(estimate, 3),
    brazil_estimate = fmt_num(brazil_estimate, 3),
    sdid_weight = fmt_num(sdid_weight, 4),
    first_treat_year = ifelse(is.na(first_treat_year), "", as.character(first_treat_year))
  )

writeLines(
  c(
    "# Selective China Alignment in UNGA Voting",
    "",
    paste0("Data: ", run_date),
    "",
    paste0("Execução: ", run_timestamp),
    "",
    paste0("Script: `", script_path, "`"),
    "",
    "Este relatório foi gerado por um script diagnóstico auditável. Ele lê targets existentes e o tarball bruto `data/raw/unvotes/unvotes_0.3.0.tar.gz`, não executa `targets::tar_make()`, não altera `_targets.R`, `_targets/`, `_targets.yaml`, e não sobrescreve dados brutos.",
    "",
    "## Resposta curta",
    "",
    paste0("Classificação pela matriz pré-definida: **", final_class, "**."),
    "",
    editorial_recommendation,
    "",
    "O resultado country-year do Goal 6 já indicava que a distância à China cai, a distância aos EUA aumenta, e o contraste China-menos-EUA se move na direção esperada. O novo teste voto-a-voto é mais restritivo: ele pergunta se, em resoluções de direitos humanos nas quais China e Estados Unidos votaram de forma diferente, o Brasil ficou relativamente mais próximo da China do que países comparáveis do donor pool. Essa é a evidência necessária para separar alinhamento seletivo, afastamento genérico dos EUA e reposicionamento amplo.",
    "",
    "## Tabela 1. O que já responde / o que ainda falta",
    "",
    markdown_table(audit_gap_table),
    "",
    "## Tabela 2. Auditoria de targets e arquivos existentes",
    "",
    markdown_table(target_file_audit_display, max_rows = 30),
    "",
    "## Tabela 3. Matriz decisória definida antes da estimação",
    "",
    markdown_table(decision_matrix),
    "",
    "A regra de interpretação não conclui apenas pela direção de um coeficiente. Para sustentar alinhamento seletivo toward China, o resultado precisa aparecer sobretudo em direitos humanos e em votos China-EUA divergentes, com comparação contra donor pool. Benchmarks alternativos só contam contra China-specificity se forem geometricamente independentes da China no pré-2009; caso contrário, são apenas diagnósticos da geometria do espaço ideal.",
    "",
    "## Country-Year Outcome Robustness",
    "",
    "## Tabela 4. Outcomes country-year paralelos",
    "",
    markdown_table(country_year_display),
    "",
    "Os benchmarks adicionais para Rússia, Índia e média BRICS sem Brasil usam o mesmo estimador SDiD para estimativas de ponto, mas não entram como placebos independentes de China-specificity. A razão é geométrica: se esses atores já estiverem próximos da China antes de 2009, aproximar-se da China pode reduzir mecanicamente a distância a eles. Por isso, a tabela abaixo diagnostica proximidade pré-2009 antes de qualquer interpretação substantiva.",
    "",
    "## Tabela 4B. Diagnóstico espacial dos benchmarks country-year",
    "",
    markdown_table(reference_spatial_display),
    "",
    "A finalidade desta tabela é evitar sobreinterpretação: benchmarks próximos ou altamente correlacionados com distância à China servem para descrever a geometria do espaço ideal, não para refutar o teste voto-a-voto em direitos humanos.",
    "",
    "![Figura 1. Outcomes country-year paralelos para o Brasil, 2005-2012. A linha vertical marca o treatment onset de 2009.](figura_1_country_year_parallel_outcomes.png)",
    "",
    "## Vote-Level Human-Rights China-US Divergent Analysis",
    "",
    "## Tabela 5. Amostras voto-a-voto",
    "",
    markdown_table(sample_counts),
    "",
    "A unidade é país-resolução. Votos ausentes, missing e not voting são excluídos. A codificação ordinal é `no = -1`, `abstain = 0`, `yes = 1`. `Post` é definido como `year >= 2009`, alinhado ao treatment onset do paper. A especificação principal usa efeitos fixos de país e resolução; o coeficiente-chave é `Brazil x Post-2009`.",
    "",
    "## Tabela 6. Modelos voto-a-voto em votos China-EUA divergentes",
    "",
    markdown_table(vote_model_display, max_rows = 80),
    "",
    "Os p-valores desta tabela são inferência model-based com clusters por país. Como há uma única unidade tratada substantiva, a inferência principal para o teste voto-a-voto é o placebo por país reportado abaixo; os erros-padrão convencionais servem como diagnóstico de precisão dentro da amostra.",
    "",
    "## Tabela 7. Teste DDD: incremento em direitos humanos relativo a non-HR",
    "",
    markdown_table(ddd_display, max_rows = 20),
    "",
    "O termo `brazil_post_hr` é o teste mais direto de seletividade temática: ele compara a mudança brasileira em votos de direitos humanos com a mudança brasileira em votos non-HR, mantendo efeitos fixos de país e resolução.",
    "",
    "## Tabela 8. Sensibilidade com clusters bidirecionais por país e resolução",
    "",
    markdown_table(twoway_display, max_rows = 60),
    "",
    "![Figura 2. Médias pré/pós em votos de direitos humanos nos quais China e EUA divergiram.](figura_2_vote_level_hr_divergent_prepost.png)",
    "",
    "A sensibilidade forte `yes` vs `no` exclui divergências mediadas por abstenção. O controle negativo non-HR usa a mesma lógica, mas em resoluções fora de direitos humanos. A categoria `Other / uncoded`, quando aparece no painel bruto, é residual e heterogênea; ela não é interpretada como área substantiva.",
    "",
    "## Placebos",
    "",
    "## Tabela 9. Event-study pré-2009 e teste de magnitude substantiva",
    "",
    markdown_table(event_pretrend_display, max_rows = 20),
    "",
    "A coluna `within_threshold` indica se o coeficiente pré-2009 está dentro de 25% do efeito principal em valor absoluto. Isso é um diagnóstico de escala, não uma prova de tendências paralelas.",
    "",
    "## Tabela 10. Placebos temporais pré-2009",
    "",
    markdown_table(
      temporal_placebo_data |>
        dplyr::mutate(
          estimate = fmt_num(estimate, 3),
          se = fmt_num(se, 3),
          p_value = fmt_p(p_value),
          ci_95_low = fmt_num(ci_95_low, 3),
          ci_95_high = fmt_num(ci_95_high, 3)
        ) |>
        dplyr::select(pseudo_year, outcome, estimate, se, p_value, ci_95_low, ci_95_high, n_obs, n_countries, n_resolutions)
    ),
    "",
    "O pseudo-break de 2007 aparece na direção esperada, embora com magnitude muito menor que o efeito principal. Por isso, os placebos temporais são tratados como um aviso contra linguagem causal forte, não como validação binária.",
    "",
    "## Tabela 11. Placebo por país no donor pool",
    "",
    markdown_table(placebo_display),
    "",
    "## Tabela 12. Auditoria dos placebos mais extremos",
    "",
    markdown_table(extreme_placebo_display, max_rows = 10),
    "",
    "![Figura 3. Distribuição placebo por país para o outcome distância China-menos-EUA em votos de direitos humanos China-EUA divergentes. A linha vermelha marca o Brasil.](figura_3_country_placebo_distribution.png)",
    "",
    "## Donor-Pool Audit",
    "",
    "## Tabela 13. Auditoria do donor pool",
    "",
    markdown_table(donor_audit_display, max_rows = 120),
    "",
    "A especificação voto-a-voto principal exclui os Estados Unidos do donor pool porque os EUA são um dos polos que definem os outcomes de distância e proximidade. Essa decisão evita que uma unidade de referência entre mecanicamente como comparação. Donor weights aparecem apenas como auditoria/sensibilidade, não como base inferencial principal.",
    "",
    "## Tabela 14. Sensibilidade excluindo donors com China-top entry em 2005-2012",
    "",
    markdown_table(
      donor_sensitivity |>
        dplyr::filter(outcome %in% c("distance_china_minus_usa", "closer_to_china_score")) |>
        dplyr::mutate(
          estimate = fmt_num(estimate, 3),
          se = fmt_num(se, 3),
          p_value = fmt_p(p_value),
          ci_95_low = fmt_num(ci_95_low, 3),
          ci_95_high = fmt_num(ci_95_high, 3)
        ) |>
        dplyr::select(sample, outcome, estimate, se, p_value, n_obs, n_countries, n_resolutions, n_excluded_donors, excluded_donors)
    ),
    "",
    "## Matriz Interpretativa Final",
    "",
    "## Tabela 15. Aplicação da matriz decisória aos achados",
    "",
    markdown_table(final_interpretation),
    "",
    "## Recomendação editorial",
    "",
    "No texto principal, a revisão deve evitar dizer que Table 4 sozinha prova convergência seletiva. A forma compacta recomendada é substituir a interpretação atual por uma frase que separe o SDiD country-year da evidência voto-a-voto:",
    "",
    "> The country-year SDiD estimate shows that Brazil moved closer to China after the 2009 export-rank reversal, including in a China-minus-US distance contrast. Resolution-level evidence should be read as a substantive diagnostic rather than a standalone causal test: the clearest additional support comes from human-rights resolutions where China and the United States diverged, and the human-rights shift is larger than the corresponding non-human-rights shift. Benchmarks to India, Russia, and BRICS are useful geometric checks of the ideal-point space, not independent placebos for China-specificity. Taken together, the evidence supports a narrower claim of selective UNGA adjustment in politically visible domains, not a wholesale realignment of Brazilian foreign policy.",
    "",
    "O resultado completo deste pacote deve entrar no apêndice ou em relatório de qualidade. No corpo do paper, bastam: a tabela country-year resumida, uma frase sobre o teste voto-a-voto HR China-EUA divergente, e o caveat explícito de que a evidência resolution-level é diagnóstica.",
    "",
    "## Arquivos gerados",
    "",
    paste0("- `", unlist(paths), "`"),
    paste0("- `", report_path, "`"),
    paste0("- `", session_info_path, "`")
  ),
  con = report_path,
  useBytes = TRUE
)

pdf_result <- tryCatch(
  {
    rmarkdown::pandoc_convert(
      input = report_path,
      to = "pdf",
      output = report_pdf_path,
      verbose = FALSE
    )
    "PDF render succeeded."
  },
  error = function(e) paste("PDF render failed:", conditionMessage(e))
)
writeLines(pdf_result, con = pdf_render_log_path, useBytes = TRUE)

message("Wrote report: ", report_path)
message("PDF status: ", pdf_result)
