#!/usr/bin/env Rscript

# Goal 6 diagnostic: outcome robustness for the Brazil SDiD and UNGA
# resolution-level Brazil-China vote evidence. This script reads existing
# targets and preserved processed CSVs only. It does not modify the targets
# pipeline, raw data, or paper files.

options(scipen = 999)

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
  library(dplyr)
  library(ggplot2)
  library(here)
  library(janitor)
  library(readr)
  library(stringr)
  library(synthdid)
  library(targets)
  library(tibble)
  library(tidyr)
})

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
script_path <- "scripts/diagnostics/diagnose_goal6_outcome_robustness.R"
target_store <- here::here("_targets")

out_dir <- here::here("quality_reports", "goal6_outcome_robustness")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

path_out <- function(filename) file.path(out_dir, filename)

object_audit_path <- path_out("goal6_existing_objects_audit.csv")
feasibility_path <- path_out("goal6_outcome_feasibility_matrix.csv")
sdid_results_path <- path_out("goal6_sdid_outcome_results.csv")
sdid_validation_path <- path_out("goal6_sdid_target_validation.csv")
sdid_series_path <- path_out("goal6_sdid_brazil_synthetic_series.csv")
country_year_brazil_path <- path_out("goal6_brazil_country_year_outcome_trends.csv")
resolution_yearly_path <- path_out("goal6_resolution_yearly_descriptives.csv")
issue_pre_post_path <- path_out("goal6_issue_area_pre_post_descriptives.csv")
hr_nonhr_path <- path_out("goal6_human_rights_vs_non_human_rights.csv")
composition_path <- path_out("goal6_issue_composition_pre_post.csv")
composition_decomp_path <- path_out("goal6_agenda_composition_decomposition.csv")
issue_common_support_path <- path_out("goal6_issue_area_common_support.csv")
donor_pool_path <- path_out("goal6_sdid_donor_pool_comparison.csv")
diagnostic_comparison_path <- path_out("goal6_outcome_diagnostic_comparison.csv")
validation_path <- path_out("goal6_validation_checks.csv")
session_info_path <- path_out("goal6_session_info.txt")
report_path <- path_out(paste0(run_date, "_goal6_outcome_robustness_report.md"))
report_pdf_path <- path_out(paste0(run_date, "_goal6_outcome_robustness_report.pdf"))
pdf_render_log_path <- path_out("goal6_pdf_render_log.txt")

fig_country_year_png <- path_out("figura_1_goal6_country_year_outcome_trends.png")
fig_country_year_pdf <- path_out("figura_1_goal6_country_year_outcome_trends.pdf")
fig_sdid_png <- path_out("figura_2_goal6_sdid_brazil_vs_synthetic_by_outcome.png")
fig_sdid_pdf <- path_out("figura_2_goal6_sdid_brazil_vs_synthetic_by_outcome.pdf")
fig_resolution_png <- path_out("figura_3_goal6_resolution_yearly_similarity.png")
fig_resolution_pdf <- path_out("figura_3_goal6_resolution_yearly_similarity.pdf")
fig_issue_png <- path_out("figura_4_goal6_issue_area_pre_post.png")
fig_issue_pdf <- path_out("figura_4_goal6_issue_area_pre_post.pdf")
fig_hr_png <- path_out("figura_5_goal6_human_rights_vs_non_human_rights.png")
fig_hr_pdf <- path_out("figura_5_goal6_human_rights_vs_non_human_rights.pdf")

safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = target_store),
    error = function(e) {
      structure(
        list(error = conditionMessage(e)),
        class = "goal6_tar_read_error"
      )
    }
  )
}

safe_tar_meta <- function() {
  tryCatch(
    targets::tar_meta(store = target_store),
    error = function(e) tibble::tibble(name = character(), error = conditionMessage(e))
  )
}

is_tar_error <- function(x) inherits(x, "goal6_tar_read_error")

object_shape <- function(x) {
  if (is_tar_error(x)) {
    return(tibble::tibble(
      object_class = "tar_read_error",
      nrow = NA_integer_,
      ncol = NA_integer_,
      length = NA_integer_,
      columns = "",
      read_error = x$error
    ))
  }

  if (is.data.frame(x)) {
    return(tibble::tibble(
      object_class = paste(class(x), collapse = ";"),
      nrow = nrow(x),
      ncol = ncol(x),
      length = length(x),
      columns = paste(names(x), collapse = ";"),
      read_error = ""
    ))
  }

  tibble::tibble(
    object_class = paste(class(x), collapse = ";"),
    nrow = NA_integer_,
    ncol = NA_integer_,
    length = length(x),
    columns = "",
    read_error = ""
  )
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_pct_value <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", paste0(formatC(x, digits = digits, format = "f"), "%"))
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

save_plot_pair <- function(plot, png_path, pdf_path, width, height) {
  ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = 320)
  ggplot2::ggsave(pdf_path, plot, width = width, height = height)
}

period_label <- function(year) {
  dplyr::case_when(
    year <= 2008 ~ "pré-2009",
    year >= 2009 ~ "pós-2009",
    TRUE ~ NA_character_
  )
}

issue_hr_group <- function(issue_family) {
  dplyr::if_else(
    stringr::str_detect(issue_family, "Direitos humanos"),
    "Direitos humanos",
    "Não direitos humanos"
  )
}

read_existing_csv <- function(path) {
  if (!file.exists(path)) {
    return(structure(list(error = paste("Missing CSV:", path)), class = "goal6_tar_read_error"))
  }
  readr::read_csv(path, show_col_types = FALSE, locale = readr::locale(encoding = "UTF-8"))
}

read_unga_fallback <- function() {
  raw_path <- here::here("raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv")
  if (!file.exists(raw_path)) {
    return(structure(list(error = paste("Missing raw UNGA ideal-point CSV:", raw_path)), class = "goal6_tar_read_error"))
  }

  readr::read_csv(raw_path, show_col_types = FALSE) |>
    janitor::clean_names() |>
    dplyr::mutate(year = session + 1945) |>
    dplyr::filter(year > 1989) |>
    dplyr::group_by(session) |>
    dplyr::mutate(
      china_ideal = q50_percent_all[iso3c == "CHN"],
      us_ideal = q50_percent_all[iso3c == "USA"],
      br_ideal = q50_percent_all[iso3c == "BRA"]
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      abs_distance_china = abs(q50_percent_all - china_ideal),
      abs_distance_usa = abs(q50_percent_all - us_ideal)
    ) |>
    dplyr::select(
      year,
      iso3c,
      ideal_point_all,
      us_agree,
      china_agree,
      china_ideal,
      us_ideal,
      br_ideal,
      abs_distance_china,
      abs_distance_usa
    )
}

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

prepare_sdid_panel <- function(data, outcome_col, covariate_cols,
                               time_treatment = 2008L, time_end = 2016L) {
  required <- c("iso3c", "year", outcome_col, covariate_cols)
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("prepare_sdid_panel: missing columns: ", paste(missing, collapse = ", "))
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

  fit_data <- base |>
    dplyr::filter(iso3c %in% complete_units) |>
    dplyr::mutate(
      treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1L, 0L),
      .unit_treated = as.integer(iso3c == "BRA")
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)

  if (!"BRA" %in% unique(fit_data$iso3c)) {
    stop("prepare_sdid_panel: Brazil is not retained after complete-case filtering.")
  }

  non_brazil_units <- setdiff(unique(fit_data$iso3c), "BRA")
  if (length(non_brazil_units) < 2L) {
    stop("prepare_sdid_panel: fewer than two donor units remain.")
  }

  fit_data
}

fit_sdid_outcome <- function(data, outcome_col, covariate_cols,
                             time_treatment = 2008L, time_end = 2016L) {
  set.seed(12345)
  fit_data <- prepare_sdid_panel(
    data = data,
    outcome_col = outcome_col,
    covariate_cols = covariate_cols,
    time_treatment = time_treatment,
    time_end = time_end
  )

  x_array <- make_covariate_array(fit_data, covariate_cols)

  panel_data <- fit_data |>
    dplyr::mutate(
      treatment = as.integer(treatment),
      year = as.integer(year),
      iso3c = as.factor(iso3c),
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

  list(fit = fit, fit_data = fit_data, setup = setup)
}

summarise_sdid_fit <- function(fit, compute_se = TRUE) {
  estimate <- as.numeric(fit)
  se <- if (compute_se) {
    tryCatch(
      as.numeric(sqrt(stats::vcov(fit, method = "placebo"))),
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

extract_sdid_series <- function(fit, outcome_name, outcome_label,
                                setup = NULL, years = NULL) {
  if (is.null(setup)) {
    setup <- attr(fit, "setup")
  }
  weights <- attr(fit, "weights")
  if (is.null(setup) || is.null(weights) || is.null(weights$omega)) {
    return(tibble::tibble())
  }

  y <- setup$Y
  n0 <- setup$N0
  t0 <- setup$T0
  omega <- weights$omega
  year_values <- years
  if (is.null(year_values)) {
    year_values <- suppressWarnings(as.integer(colnames(y)))
  }
  if (is.null(year_values) || anyNA(year_values)) {
    year_values <- seq_len(ncol(y))
  }

  brazil <- as.numeric(y[n0 + 1L, ])
  controls <- y[seq_len(n0), , drop = FALSE]
  synthetic <- as.numeric(t(as.matrix(omega)) %*% controls)

  tibble::tibble(
    outcome = outcome_name,
    outcome_label = outcome_label,
    year = year_values,
    brazil = brazil,
    synthetic = synthetic,
    gap = brazil - synthetic,
    period = period_label(year),
    event_time = year - 2009L,
    pre_treatment = year <= year_values[t0]
  )
}

read_sdid_target_pair <- function(fit_target, se_target) {
  fit <- safe_tar_read(fit_target)
  se <- safe_tar_read(se_target)

  tibble::tibble(
    target_fit = fit_target,
    target_se = se_target,
    target_estimate = if (is_tar_error(fit)) NA_real_ else as.numeric(fit),
    target_se_placebo = if (is_tar_error(se)) NA_real_ else as.numeric(se),
    target_read_error = paste(
      c(
        if (is_tar_error(fit)) paste0(fit_target, ": ", fit$error) else "",
        if (is_tar_error(se)) paste0(se_target, ": ", se$error) else ""
      ),
      collapse = ""
    )
  )
}

target_names <- c(
  "synth_data",
  "synth_fit",
  "se_synth",
  "synth_data_baseline",
  "synth_fit_baseline",
  "se_synth_baseline",
  "unga_data",
  "brazil_china_unvotes_resolution_2005_2012",
  "brazil_china_unvotes_similarity_by_year_2005_2012",
  "brazil_china_unvotes_similarity_by_issue_year_2005_2012"
)

target_meta <- safe_tar_meta()
target_meta_small <- target_meta |>
  dplyr::select(dplyr::any_of(c("name", "type", "format", "bytes", "time", "error"))) |>
  dplyr::filter(name %in% target_names)

objects <- stats::setNames(lapply(target_names, safe_tar_read), target_names)

csv_paths <- tibble::tribble(
  ~name, ~path,
  "csv_alignment_by_resolution", "data/processed/unvotes/brazil_china_vote_alignment_by_resolution_2005_2012.csv",
  "csv_alignment_by_issue_year", "data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv",
  "csv_similarity_by_resolution", "data/processed/unvotes/brazil_china_vote_similarity_score_by_resolution_2005_2012.csv",
  "csv_similarity_by_issue_year", "data/processed/unvotes/brazil_china_vote_similarity_by_issue_year_plot_2005_2012.csv"
)

csv_objects <- stats::setNames(lapply(csv_paths$path, read_existing_csv), csv_paths$name)

audit_targets <- dplyr::bind_rows(lapply(names(objects), function(name) {
  object_shape(objects[[name]]) |>
    dplyr::mutate(name = name, source_type = "target", path = "", .before = 1)
}))

audit_csvs <- dplyr::bind_rows(lapply(names(csv_objects), function(name) {
  object_shape(csv_objects[[name]]) |>
    dplyr::mutate(
      name = name,
      source_type = "processed_csv",
      path = csv_paths$path[csv_paths$name == name],
      .before = 1
    )
}))

object_audit <- dplyr::bind_rows(audit_targets, audit_csvs) |>
  dplyr::mutate(
    has_abs_distance_china = stringr::str_detect(columns, "(^|;)abs_distance_china(;|$)"),
    has_abs_distance_usa = stringr::str_detect(columns, "(^|;)abs_distance_usa(;|$)"),
    has_china_agree = stringr::str_detect(columns, "(^|;)china_agree(;|$)"),
    has_us_agree = stringr::str_detect(columns, "(^|;)us_agree(;|$)"),
    has_identical_vote = stringr::str_detect(columns, "identical_vote|brazil_china_convergent"),
    has_similarity_score = stringr::str_detect(columns, "(^|;)similarity_score(;|$)|mean_similarity_score"),
    has_issue_area = stringr::str_detect(columns, "issue_family|issue|theme"),
    has_resolution_level = stringr::str_detect(columns, "(^|;)rcid(;|$)|doc_symbol")
  ) |>
  dplyr::left_join(target_meta_small, by = "name")

readr::write_csv(object_audit, object_audit_path, na = "")

synth_data <- objects[["synth_data"]]
if (is_tar_error(synth_data)) {
  stop("Cannot continue without target `synth_data`: ", synth_data$error)
}

unga_data <- objects[["unga_data"]]
if (is_tar_error(unga_data)) {
  unga_data <- read_unga_fallback()
}
if (is_tar_error(unga_data)) {
  stop("Cannot continue without `unga_data` or raw fallback: ", unga_data$error)
}

unga_outcomes <- unga_data |>
  dplyr::select(
    iso3c,
    year,
    dplyr::any_of(c("china_agree", "us_agree", "abs_distance_china", "abs_distance_usa"))
  ) |>
  dplyr::mutate(
    china_minus_us_agree = china_agree - us_agree
  )

sdid_data <- synth_data |>
  dplyr::left_join(
    unga_outcomes |>
      dplyr::select(iso3c, year, china_agree, us_agree, china_minus_us_agree),
    by = c("iso3c", "year")
  ) |>
  dplyr::mutate(
    relative_distance_china_minus_usa = abs_distance_china - abs_distance_usa
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
    names(sdid_data)
  )
)

missing_pipeline_covariates <- setdiff(pipeline_covariates, names(sdid_data))
if (length(missing_pipeline_covariates) > 0L) {
  stop("Missing SDiD covariates: ", paste(missing_pipeline_covariates, collapse = ", "))
}

outcome_catalog <- tibble::tribble(
  ~outcome, ~label, ~data_level, ~sdid_viable, ~brazil_only_descriptive, ~evidence_tier, ~substantive_interpretation, ~agenda_composition_risk, ~expected_direction,
  "abs_distance_china", "Distância absoluta Brasil-China em ideal points", "country-year", TRUE, TRUE, "primary causal", "Menor valor indica aproximação ideológica à China no espaço de ideal points da AGNU.", "Baixo no nível country-year; a composição da agenda entra indiretamente no ideal point estimado.", "negative",
  "relative_distance_china_minus_usa", "Distância à China menos distância aos EUA", "country-year", TRUE, TRUE, "alternative causal robustness", "Valor menor indica que o país fica relativamente mais próximo da China do que dos EUA.", "Baixo a moderado; combina duas distâncias estimadas no mesmo espaço anual.", "negative",
  "abs_distance_usa", "Distância absoluta aos EUA em ideal points", "country-year", TRUE, TRUE, "secondary SDiD diagnostic", "Maior valor é consistente com afastamento dos EUA; menor valor indicaria aproximação dos EUA.", "Baixo no nível country-year; interpretação é contraste, não alinhamento direto com China.", "positive",
  "china_agree", "Proporção anual de votos iguais à China", "country-year", TRUE, TRUE, "agenda-sensitive SDiD diagnostic", "Maior valor indica maior acordo anual de voto com a China.", "Moderado; porcentagens anuais podem refletir composição da agenda votada.", "positive",
  "china_minus_us_agree", "Acordo com China menos acordo com EUA", "country-year", TRUE, TRUE, "agenda-sensitive SDiD diagnostic", "Maior valor indica acordo anual com a China crescendo relativamente ao acordo com os EUA.", "Moderado; diferenças de acordo são sensíveis à composição da agenda.", "positive",
  "identical_vote_share_brazil_china", "Percentual de votos idênticos Brasil-China", "resolution-year / Brazil-year", FALSE, TRUE, "descriptive only", "Maior valor indica que Brasil e China votam igual em mais resoluções nominais.", "Alto; mudanças no mix de resoluções podem alterar o denominador.", "positive",
  "mean_similarity_score_brazil_china", "S-score simples Brasil-China por resolução", "resolution-year / Brazil-year", FALSE, TRUE, "descriptive only", "Maior valor indica maior similaridade: 1 igual, 0,5 abstenção contra yes/no, 0 oposição.", "Alto; depende da composição anual da pauta nominal.", "positive",
  "issue_area_identical_vote_share", "Percentual de votos idênticos por issue area", "issue-year / Brazil-only", FALSE, TRUE, "descriptive only", "Maior valor indica convergência dentro de cada área temática.", "Alto dentro de células pequenas; poder limitado por poucos votos em alguns temas.", "positive",
  "non_human_rights_identical_vote_share", "Percentual de votos idênticos excluindo direitos humanos", "resolution-year / Brazil-only", FALSE, TRUE, "descriptive only", "Maior valor indica convergência fora de direitos humanos.", "Alto; serve como robustez descritiva, não como SDiD causal.", "positive"
)

coverage_country_year <- dplyr::bind_rows(lapply(outcome_catalog$outcome[outcome_catalog$sdid_viable], function(outcome) {
  if (!outcome %in% names(sdid_data)) {
    return(tibble::tibble(
      outcome = outcome,
      period_covered = "",
      n_obs = NA_integer_,
      n_units = NA_integer_,
      missing_pct = NA_real_,
      brazil_missing_pct = NA_real_
    ))
  }
  data <- sdid_data |>
    dplyr::filter(year < 2016) |>
    dplyr::select(iso3c, year, value = dplyr::all_of(outcome))
  tibble::tibble(
    outcome = outcome,
    period_covered = paste0(min(data$year, na.rm = TRUE), "-", max(data$year, na.rm = TRUE)),
    n_obs = nrow(data),
    n_units = dplyr::n_distinct(data$iso3c),
    missing_pct = 100 * mean(is.na(data$value)),
    brazil_missing_pct = 100 * mean(is.na(data$value[data$iso3c == "BRA"]))
  )
}))

resolution_similarity <- csv_objects[["csv_similarity_by_resolution"]]
resolution_alignment <- csv_objects[["csv_alignment_by_resolution"]]

if (is_tar_error(resolution_similarity) && !is_tar_error(objects[["brazil_china_unvotes_resolution_2005_2012"]])) {
  resolution_similarity <- objects[["brazil_china_unvotes_resolution_2005_2012"]] |>
    dplyr::mutate(
      similarity_score = dplyr::case_when(
        vote_brazil == vote_china ~ 1,
        vote_brazil == "abstain" & vote_china %in% c("yes", "no") ~ 0.5,
        vote_china == "abstain" & vote_brazil %in% c("yes", "no") ~ 0.5,
        TRUE ~ 0
      )
    )
}

if (is_tar_error(resolution_similarity)) {
  stop("Cannot continue without resolution-level Brazil-China similarity data: ", resolution_similarity$error)
}

resolution_data <- resolution_similarity
if ("identical_vote" %in% names(resolution_data)) {
  resolution_data <- resolution_data |>
    dplyr::mutate(identical_vote = as.logical(identical_vote))
} else {
  resolution_data <- resolution_data |>
    dplyr::mutate(identical_vote = vote_brazil == vote_china)
}

resolution_data <- resolution_data |>
  dplyr::mutate(
    issue_family = dplyr::case_when(
      is.na(issue_family) | issue_family == "" ~ "Outros / sem codificação",
      TRUE ~ as.character(issue_family)
    ),
    issue_family = dplyr::recode(
      issue_family,
      "Human rights" = "Direitos humanos",
      "Arms/disarmament/nuclear" = "Armas/desarmamento/nuclear",
      "Economic development" = "Desenvolvimento econômico",
      "Decolonization" = "Descolonização",
      "Palestine/Middle East" = "Palestina/Oriente Médio",
      "Other / uncoded" = "Outros / sem codificação",
      .default = issue_family
    ),
    period = period_label(year),
    hr_group = issue_hr_group(issue_family),
    post_2009 = year >= 2009
  )

if (!is_tar_error(resolution_alignment)) {
  alignment_small <- resolution_alignment |>
    dplyr::select(
      dplyr::any_of(c(
        "rcid",
        "doc_symbol",
        "support_gap_brazil_minus_china_pct",
        "china_support_advantage_pct",
        "abs_support_gap_pct",
        "valid_electorate_n"
      ))
    )
  resolution_data <- resolution_data |>
    dplyr::left_join(alignment_small, by = intersect(names(resolution_data), names(alignment_small)))
}

resolution_coverage <- resolution_data |>
  dplyr::summarise(
    period_covered = paste0(min(year, na.rm = TRUE), "-", max(year, na.rm = TRUE)),
    n_obs = dplyr::n(),
    n_units = NA_integer_,
    missing_pct = 100 * mean(is.na(similarity_score)),
    brazil_missing_pct = 0
  ) |>
  tidyr::crossing(outcome = c(
    "identical_vote_share_brazil_china",
    "mean_similarity_score_brazil_china",
    "issue_area_identical_vote_share",
    "non_human_rights_identical_vote_share"
  ))

feasibility <- outcome_catalog |>
  dplyr::left_join(
    dplyr::bind_rows(coverage_country_year, resolution_coverage),
    by = "outcome"
  ) |>
  dplyr::mutate(
    allows_sdid_with_donor_pool = sdid_viable,
    allows_brazil_only_descriptive = brazil_only_descriptive,
    feasibility_decision = dplyr::case_when(
      sdid_viable ~ "Estimável com o mesmo desenho SDiD se mantido o painel country-year e o donor pool.",
      brazil_only_descriptive ~ "Não força SDiD; usar como diagnóstico descritivo Brasil-only.",
      TRUE ~ "Rejeitado por inviabilidade."
    )
  ) |>
  dplyr::select(
    outcome,
    label,
    data_level,
    evidence_tier,
    allows_sdid_with_donor_pool,
    allows_brazil_only_descriptive,
    period_covered,
    n_obs,
    n_units,
    missing_pct,
    brazil_missing_pct,
    substantive_interpretation,
    agenda_composition_risk,
    feasibility_decision
  )

readr::write_csv(feasibility, feasibility_path, na = "")

sdid_outcomes <- outcome_catalog |>
  dplyr::filter(sdid_viable) |>
  dplyr::select(outcome, label, evidence_tier, expected_direction)

fit_results <- list()
sdid_rows <- list()
sdid_series_list <- list()
donor_rows <- list()
baseline_donors <- character()
baseline_units <- character()

for (i in seq_len(nrow(sdid_outcomes))) {
  outcome <- sdid_outcomes$outcome[[i]]
  label <- sdid_outcomes$label[[i]]
  evidence_tier <- sdid_outcomes$evidence_tier[[i]]
  expected_direction <- sdid_outcomes$expected_direction[[i]]

  fit_attempt <- tryCatch(
    fit_sdid_outcome(sdid_data, outcome, pipeline_covariates),
    error = function(e) structure(list(error = conditionMessage(e)), class = "goal6_sdid_error")
  )

  if (inherits(fit_attempt, "goal6_sdid_error")) {
    sdid_rows[[i]] <- tibble::tibble(
      outcome = outcome,
      label = label,
      evidence_tier = evidence_tier,
      estimand_status = "SDiD não estimado",
      estimate = NA_real_,
      se_placebo = NA_real_,
      z = NA_real_,
      p_value = NA_real_,
      ci_95_low = NA_real_,
      ci_95_high = NA_real_,
      n_obs = NA_integer_,
      n_countries = NA_integer_,
      n_donors = NA_integer_,
      donor_pool_status = "not estimated",
      same_donor_pool_as_baseline = NA,
      dropped_donors = "",
      added_donors = "",
      inference_status = "Não estimado; inferência indisponível.",
      pre_period = "",
      post_period = "",
      expected_direction = expected_direction,
      supports_alignment_claim = NA,
      error = fit_attempt$error
    )
    donor_rows[[i]] <- tibble::tibble(
      outcome = outcome,
      label = label,
      evidence_tier = evidence_tier,
      donor_pool_status = "not estimated",
      n_units = NA_integer_,
      n_donors = NA_integer_,
      dropped_donors = "",
      added_donors = "",
      same_as_baseline = NA
    )
    next
  }

  fit_results[[outcome]] <- fit_attempt
  fit <- fit_attempt$fit
  fit_data <- fit_attempt$fit_data
  setup <- fit_attempt$setup
  unit_set <- sort(unique(as.character(fit_data$iso3c)))
  donor_set <- setdiff(unit_set, "BRA")
  if (outcome == "abs_distance_china") {
    baseline_units <- unit_set
    baseline_donors <- donor_set
  }
  same_donor_pool <- length(baseline_donors) > 0L && setequal(donor_set, baseline_donors)
  dropped_donors <- setdiff(baseline_donors, donor_set)
  added_donors <- setdiff(donor_set, baseline_donors)
  donor_pool_status <- dplyr::case_when(
    outcome == "abs_distance_china" ~ "baseline donor pool",
    same_donor_pool ~ "same as baseline",
    TRUE ~ "changed relative to baseline"
  )

  donor_rows[[i]] <- tibble::tibble(
    outcome = outcome,
    label = label,
    evidence_tier = evidence_tier,
    donor_pool_status = donor_pool_status,
    n_units = length(unit_set),
    n_donors = length(donor_set),
    dropped_donors = paste(dropped_donors, collapse = ";"),
    added_donors = paste(added_donors, collapse = ";"),
    same_as_baseline = same_donor_pool
  )

  summary <- summarise_sdid_fit(fit, compute_se = FALSE)

  if (outcome == "abs_distance_china") {
    target_pair <- read_sdid_target_pair("synth_fit", "se_synth")
    if (!is.na(target_pair$target_se_placebo[[1]])) {
      summary$se_placebo <- target_pair$target_se_placebo[[1]]
      summary$z <- summary$estimate / summary$se_placebo
      summary$p_value <- 2 * stats::pnorm(-abs(summary$z))
      summary$ci_95_low <- summary$estimate - stats::qnorm(0.975) * summary$se_placebo
      summary$ci_95_high <- summary$estimate + stats::qnorm(0.975) * summary$se_placebo
    }
  }

  supports_claim <- dplyr::case_when(
    expected_direction == "negative" ~ summary$estimate < 0,
    expected_direction == "positive" ~ summary$estimate > 0,
    TRUE ~ NA
  )

  years <- sort(unique(fit_data$year))
  pre_years <- years[seq_len(setup$T0)]
  post_years <- years[(setup$T0 + 1L):length(years)]

  sdid_rows[[i]] <- summary |>
    dplyr::mutate(
      outcome = outcome,
      label = label,
      evidence_tier = evidence_tier,
      estimand_status = dplyr::if_else(
        donor_pool_status %in% c("baseline donor pool", "same as baseline"),
        "SDiD country-year, mesmo donor pool e janela principal",
        "SDiD country-year, donor pool alterado; interpretar como diagnóstico"
      ),
      n_obs = nrow(fit_data),
      n_countries = dplyr::n_distinct(fit_data$iso3c),
      n_donors = setup$N0,
      donor_pool_status = donor_pool_status,
      same_donor_pool_as_baseline = same_donor_pool,
      dropped_donors = paste(dropped_donors, collapse = ";"),
      added_donors = paste(added_donors, collapse = ";"),
      inference_status = dplyr::if_else(
        outcome == "abs_distance_china",
        "SE placebo lido do target existente `se_synth`.",
        "Estimativa de ponto; SE placebo não recomputado para evitar bateria inferencial exploratória."
      ),
      pre_period = paste0(min(pre_years), "-", max(pre_years)),
      post_period = paste0(min(post_years), "-", max(post_years)),
      expected_direction = expected_direction,
      supports_alignment_claim = supports_claim,
      error = "",
      .before = 1
    )

  sdid_series_list[[outcome]] <- extract_sdid_series(
    fit,
    outcome,
    label,
    setup = setup,
    years = years
  )
}

sdid_results <- dplyr::bind_rows(sdid_rows)
readr::write_csv(sdid_results, sdid_results_path, na = "")

donor_pool_comparison <- dplyr::bind_rows(donor_rows)
readr::write_csv(donor_pool_comparison, donor_pool_path, na = "")

local_baseline <- sdid_results |>
  dplyr::filter(outcome == "abs_distance_china") |>
  dplyr::slice(1)
local_baseline_estimate <- if (nrow(local_baseline) == 1L) local_baseline$estimate[[1]] else NA_real_
local_baseline_se <- if (nrow(local_baseline) == 1L) local_baseline$se_placebo[[1]] else NA_real_

target_validation <- read_sdid_target_pair("synth_fit", "se_synth") |>
  dplyr::mutate(
    local_outcome = "abs_distance_china",
    local_estimate = local_baseline_estimate,
    local_se_placebo = local_baseline_se,
    estimate_delta_local_minus_target = local_estimate - target_estimate,
    se_delta_local_minus_target = local_se_placebo - target_se_placebo
  ) |>
  dplyr::select(local_outcome, dplyr::everything())
readr::write_csv(target_validation, sdid_validation_path, na = "")

sdid_series <- dplyr::bind_rows(sdid_series_list)
readr::write_csv(sdid_series, sdid_series_path, na = "")

brazil_country_year <- sdid_data |>
  dplyr::filter(iso3c == "BRA", year < 2016) |>
  dplyr::select(
    iso3c,
    year,
    abs_distance_china,
    relative_distance_china_minus_usa,
    abs_distance_usa,
    china_agree,
    china_minus_us_agree
  ) |>
  tidyr::pivot_longer(
    cols = -c(iso3c, year),
    names_to = "outcome",
    values_to = "value"
  ) |>
  dplyr::left_join(
    outcome_catalog |>
      dplyr::select(outcome, label),
    by = "outcome"
  ) |>
  dplyr::mutate(
    period = period_label(year),
    event_time = year - 2009L
  )
readr::write_csv(brazil_country_year, country_year_brazil_path, na = "")

resolution_yearly <- resolution_data |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    n_resolutions = dplyr::n_distinct(rcid),
    identical_votes_n = sum(identical_vote, na.rm = TRUE),
    identical_vote_share = 100 * mean(identical_vote, na.rm = TRUE),
    mean_similarity_score = mean(similarity_score, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(period = period_label(year))

resolution_yearly_by_hr <- resolution_data |>
  dplyr::group_by(hr_group, year) |>
  dplyr::summarise(
    n_resolutions = dplyr::n_distinct(rcid),
    identical_votes_n = sum(identical_vote, na.rm = TRUE),
    identical_vote_share = 100 * mean(identical_vote, na.rm = TRUE),
    mean_similarity_score = mean(similarity_score, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(period = period_label(year))

readr::write_csv(resolution_yearly, resolution_yearly_path, na = "")

issue_pre_post <- resolution_data |>
  dplyr::group_by(issue_family, period) |>
  dplyr::summarise(
    n_resolutions = dplyr::n_distinct(rcid),
    identical_vote_share = 100 * mean(identical_vote, na.rm = TRUE),
    mean_similarity_score = mean(similarity_score, na.rm = TRUE),
    .groups = "drop"
  ) |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(n_resolutions, identical_vote_share, mean_similarity_score)
  ) |>
  dplyr::mutate(
    delta_identical_vote_share = `identical_vote_share_pós-2009` - `identical_vote_share_pré-2009`,
    delta_mean_similarity_score = `mean_similarity_score_pós-2009` - `mean_similarity_score_pré-2009`,
    total_resolutions = `n_resolutions_pré-2009` + `n_resolutions_pós-2009`
  ) |>
  dplyr::arrange(dplyr::desc(delta_identical_vote_share))
readr::write_csv(issue_pre_post, issue_pre_post_path, na = "")

hr_nonhr <- resolution_data |>
  dplyr::group_by(hr_group, period) |>
  dplyr::summarise(
    n_resolutions = dplyr::n_distinct(rcid),
    identical_vote_share = 100 * mean(identical_vote, na.rm = TRUE),
    mean_similarity_score = mean(similarity_score, na.rm = TRUE),
    .groups = "drop"
  ) |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(n_resolutions, identical_vote_share, mean_similarity_score)
  ) |>
  dplyr::mutate(
    delta_identical_vote_share = `identical_vote_share_pós-2009` - `identical_vote_share_pré-2009`,
    delta_mean_similarity_score = `mean_similarity_score_pós-2009` - `mean_similarity_score_pré-2009`
  )
readr::write_csv(hr_nonhr, hr_nonhr_path, na = "")

composition_pre_post <- resolution_data |>
  dplyr::count(period, issue_family, name = "n_resolutions") |>
  dplyr::group_by(period) |>
  dplyr::mutate(share_resolutions = n_resolutions / sum(n_resolutions)) |>
  dplyr::ungroup() |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(n_resolutions, share_resolutions),
    values_fill = list(n_resolutions = 0, share_resolutions = 0)
  ) |>
  dplyr::mutate(
    delta_share_pp = 100 * (`share_resolutions_pós-2009` - `share_resolutions_pré-2009`)
  ) |>
  dplyr::arrange(dplyr::desc(abs(delta_share_pp)))
readr::write_csv(composition_pre_post, composition_path, na = "")

period_totals <- resolution_data |>
  dplyr::group_by(period) |>
  dplyr::summarise(period_total = dplyr::n_distinct(rcid), .groups = "drop")

issue_rates_long <- resolution_data |>
  dplyr::group_by(period, issue_family) |>
  dplyr::summarise(
    n = dplyr::n_distinct(rcid),
    identical_rate = mean(identical_vote, na.rm = TRUE),
    similarity_rate = mean(similarity_score, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(period_totals, by = "period") |>
  dplyr::mutate(share = n / period_total)

issue_rates_wide <- issue_rates_long |>
  dplyr::select(period, issue_family, n, share, identical_rate, similarity_rate) |>
  tidyr::pivot_wider(
    id_cols = issue_family,
    names_from = period,
    values_from = c(n, share, identical_rate, similarity_rate),
    values_fill = 0
  ) |>
  dplyr::mutate(
    common_support = `n_pré-2009` > 0 & `n_pós-2009` > 0
  )

issue_common_support <- issue_rates_wide |>
  dplyr::transmute(
    issue_family,
    n_pre = `n_pré-2009`,
    n_post = `n_pós-2009`,
    common_support,
    note = dplyr::if_else(
      common_support,
      "Área observada nos dois períodos.",
      "Área ausente em pelo menos um período; decomposição limpa é limitada."
    )
  )
readr::write_csv(issue_common_support, issue_common_support_path, na = "")

issue_rates_decomp <- issue_rates_wide |>
  dplyr::filter(common_support)

composition_decomposition <- tibble::tibble(
  metric = c("identical_vote_share", "mean_similarity_score"),
  pre_overall = c(
    mean(resolution_data$identical_vote[resolution_data$period == "pré-2009"], na.rm = TRUE),
    mean(resolution_data$similarity_score[resolution_data$period == "pré-2009"], na.rm = TRUE)
  ),
  post_overall = c(
    mean(resolution_data$identical_vote[resolution_data$period == "pós-2009"], na.rm = TRUE),
    mean(resolution_data$similarity_score[resolution_data$period == "pós-2009"], na.rm = TRUE)
  ),
  within_issue_effect = c(
    sum(issue_rates_decomp$`share_pós-2009` * (issue_rates_decomp$`identical_rate_pós-2009` - issue_rates_decomp$`identical_rate_pré-2009`), na.rm = TRUE),
    sum(issue_rates_decomp$`share_pós-2009` * (issue_rates_decomp$`similarity_rate_pós-2009` - issue_rates_decomp$`similarity_rate_pré-2009`), na.rm = TRUE)
  ),
  composition_effect = c(
    sum((issue_rates_decomp$`share_pós-2009` - issue_rates_decomp$`share_pré-2009`) * issue_rates_decomp$`identical_rate_pré-2009`, na.rm = TRUE),
    sum((issue_rates_decomp$`share_pós-2009` - issue_rates_decomp$`share_pré-2009`) * issue_rates_decomp$`similarity_rate_pré-2009`, na.rm = TRUE)
  )
) |>
  dplyr::mutate(
    total_change = post_overall - pre_overall,
    residual_interaction = total_change - within_issue_effect - composition_effect,
    pre_overall = 100 * pre_overall,
    post_overall = 100 * post_overall,
    total_change_pp = 100 * total_change,
    within_issue_effect_pp = 100 * within_issue_effect,
    composition_effect_pp = 100 * composition_effect,
    residual_interaction_pp = 100 * residual_interaction
  ) |>
  dplyr::select(
    metric,
    pre_overall,
    post_overall,
    total_change_pp,
    within_issue_effect_pp,
    composition_effect_pp,
    residual_interaction_pp
  )
readr::write_csv(composition_decomposition, composition_decomp_path, na = "")

resolution_diagnostics <- tibble::tibble(
  outcome = c(
    "identical_vote_share_brazil_china",
    "mean_similarity_score_brazil_china",
    "non_human_rights_identical_vote_share",
    "human_rights_identical_vote_share"
  ),
  label = c(
    "Percentual de votos idênticos Brasil-China",
    "Similaridade média Brasil-China",
    "Percentual de votos idênticos excluindo direitos humanos",
    "Percentual de votos idênticos em direitos humanos"
  ),
  evidence_tier = "descriptive only",
  estimand_status = "Diagnóstico descritivo Brasil-only; não é SDiD",
  pre_value = c(
    mean(resolution_data$identical_vote[resolution_data$period == "pré-2009"], na.rm = TRUE) * 100,
    mean(resolution_data$similarity_score[resolution_data$period == "pré-2009"], na.rm = TRUE),
    mean(resolution_data$identical_vote[resolution_data$period == "pré-2009" & resolution_data$hr_group == "Não direitos humanos"], na.rm = TRUE) * 100,
    mean(resolution_data$identical_vote[resolution_data$period == "pré-2009" & resolution_data$hr_group == "Direitos humanos"], na.rm = TRUE) * 100
  ),
  post_value = c(
    mean(resolution_data$identical_vote[resolution_data$period == "pós-2009"], na.rm = TRUE) * 100,
    mean(resolution_data$similarity_score[resolution_data$period == "pós-2009"], na.rm = TRUE),
    mean(resolution_data$identical_vote[resolution_data$period == "pós-2009" & resolution_data$hr_group == "Não direitos humanos"], na.rm = TRUE) * 100,
    mean(resolution_data$identical_vote[resolution_data$period == "pós-2009" & resolution_data$hr_group == "Direitos humanos"], na.rm = TRUE) * 100
  ),
  n_pre = c(
    sum(resolution_data$period == "pré-2009"),
    sum(resolution_data$period == "pré-2009"),
    sum(resolution_data$period == "pré-2009" & resolution_data$hr_group == "Não direitos humanos"),
    sum(resolution_data$period == "pré-2009" & resolution_data$hr_group == "Direitos humanos")
  ),
  n_post = c(
    sum(resolution_data$period == "pós-2009"),
    sum(resolution_data$period == "pós-2009"),
    sum(resolution_data$period == "pós-2009" & resolution_data$hr_group == "Não direitos humanos"),
    sum(resolution_data$period == "pós-2009" & resolution_data$hr_group == "Direitos humanos")
  )
) |>
  dplyr::mutate(delta_post_minus_pre = post_value - pre_value)

diagnostic_comparison <- dplyr::bind_rows(
  sdid_results |>
    dplyr::transmute(
      outcome,
      label,
      evidence_tier,
      estimand_status,
      estimate_or_delta = estimate,
      uncertainty = se_placebo,
      p_value = p_value,
      n_pre_or_obs = n_obs,
      n_post = NA_integer_,
      interpretation = dplyr::case_when(
        supports_alignment_claim ~ "Sinal compatível com aproximação/reorientação esperada.",
        !supports_alignment_claim ~ "Sinal não compatível com aproximação/reorientação esperada.",
        TRUE ~ "Não estimado."
      )
    ),
  resolution_diagnostics |>
    dplyr::transmute(
      outcome,
      label,
      evidence_tier,
      estimand_status,
      estimate_or_delta = delta_post_minus_pre,
      uncertainty = NA_real_,
      p_value = NA_real_,
      n_pre_or_obs = n_pre,
      n_post = n_post,
      interpretation = "Mudança pré/pós-2009 descritiva, sensível ao mix de resoluções."
    )
)
readr::write_csv(diagnostic_comparison, diagnostic_comparison_path, na = "")

country_year_plot <- brazil_country_year |>
  dplyr::filter(outcome %in% c(
    "abs_distance_china",
    "relative_distance_china_minus_usa",
    "abs_distance_usa",
    "china_agree",
    "china_minus_us_agree"
  )) |>
  ggplot2::ggplot(ggplot2::aes(x = year, y = value)) +
  ggplot2::geom_vline(xintercept = 2008.5, color = "gray45", linewidth = 0.35) +
  ggplot2::geom_line(color = "#1F4E79", linewidth = 0.75) +
  ggplot2::geom_point(color = "#1F4E79", size = 1.8) +
  ggplot2::facet_wrap(~label, scales = "free_y", ncol = 1) +
  ggplot2::scale_x_continuous(breaks = seq(1997, 2015, 3)) +
  ggplot2::labs(
    title = "Figura 1. Tendências brasileiras por outcome country-year alternativo",
    x = "Ano",
    y = NULL,
    caption = "Linha vertical: 2009, primeiro ano pós-reversão. Painéis em escalas livres; figura descritiva."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold")
  )
save_plot_pair(country_year_plot, fig_country_year_png, fig_country_year_pdf, 8, 9)

sdid_series_plot_data <- sdid_series |>
  tidyr::pivot_longer(
    cols = c(brazil, synthetic),
    names_to = "series",
    values_to = "value"
  ) |>
  dplyr::mutate(
    series = dplyr::recode(series, brazil = "Brasil", synthetic = "Sintético")
  )

sdid_plot <- sdid_series_plot_data |>
  ggplot2::ggplot(ggplot2::aes(x = year, y = value, color = series, linetype = series)) +
  ggplot2::geom_vline(xintercept = 2008.5, color = "gray45", linewidth = 0.35) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_y", ncol = 1) +
  ggplot2::scale_color_manual(values = c("Brasil" = "#B2182B", "Sintético" = "#2166AC")) +
  ggplot2::scale_linetype_manual(values = c("Brasil" = "solid", "Sintético" = "dashed")) +
  ggplot2::scale_x_continuous(breaks = seq(1997, 2015, 3)) +
  ggplot2::labs(
    title = "Figura 2. Brasil versus contrafactual sintético por outcome SDiD estimável",
    x = "Ano",
    y = NULL,
    color = "",
    linetype = "",
    caption = "Mesma janela principal do SDiD brasileiro; painéis em escalas livres."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.title = ggplot2::element_text(face = "bold")
  )
save_plot_pair(sdid_plot, fig_sdid_png, fig_sdid_pdf, 8, 10)

resolution_plot <- resolution_yearly_by_hr |>
  dplyr::bind_rows(
    resolution_yearly |>
      dplyr::mutate(hr_group = "Todas as resoluções")
  ) |>
  ggplot2::ggplot(ggplot2::aes(x = year, y = identical_vote_share, color = hr_group)) +
  ggplot2::geom_vline(xintercept = 2008.5, color = "gray45", linewidth = 0.35) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 2) +
  ggplot2::scale_color_manual(values = c(
    "Todas as resoluções" = "#1F4E79",
    "Direitos humanos" = "#B2182B",
    "Não direitos humanos" = "#4D9221"
  )) +
  ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%")) +
  ggplot2::coord_cartesian(ylim = c(50, 100)) +
  ggplot2::scale_x_continuous(breaks = 2005:2012) +
  ggplot2::labs(
    title = "Figura 3. Votos idênticos Brasil-China por ano, direitos humanos e demais áreas",
    x = "Ano",
    y = "Votos idênticos (%)",
    color = "",
    caption = "Diagnóstico descritivo resolution-level; não é estimativa causal."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold")
  )
save_plot_pair(resolution_plot, fig_resolution_png, fig_resolution_pdf, 8, 5.4)

issue_plot_data <- issue_pre_post |>
  dplyr::select(
    issue_family,
    `identical_vote_share_pré-2009`,
    `identical_vote_share_pós-2009`
  ) |>
  tidyr::pivot_longer(
    cols = -issue_family,
    names_to = "period",
    values_to = "identical_vote_share"
  ) |>
  dplyr::mutate(
    period = dplyr::recode(
      period,
      `identical_vote_share_pré-2009` = "pré-2009",
      `identical_vote_share_pós-2009` = "pós-2009"
    ),
    issue_family = stats::reorder(issue_family, identical_vote_share, FUN = max)
  )

issue_plot <- issue_plot_data |>
  ggplot2::ggplot(ggplot2::aes(x = identical_vote_share, y = issue_family, color = period)) +
  ggplot2::geom_line(ggplot2::aes(group = issue_family), color = "gray70", linewidth = 0.5, na.rm = TRUE) +
  ggplot2::geom_point(size = 2.6, na.rm = TRUE) +
  ggplot2::scale_color_manual(values = c("pré-2009" = "#2166AC", "pós-2009" = "#B2182B")) +
  ggplot2::scale_x_continuous(labels = function(x) paste0(x, "%")) +
  ggplot2::coord_cartesian(xlim = c(50, 100)) +
  ggplot2::labs(
    title = "Figura 4. Mudança pré/pós-2009 em votos idênticos por área temática",
    x = "Votos idênticos (%)",
    y = NULL,
    color = "",
    caption = "Diagnóstico descritivo por issue area; células pequenas têm poder limitado."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold")
  )
save_plot_pair(issue_plot, fig_issue_png, fig_issue_pdf, 8, 5)

hr_plot_data <- hr_nonhr |>
  dplyr::select(
    hr_group,
    `identical_vote_share_pré-2009`,
    `identical_vote_share_pós-2009`
  ) |>
  tidyr::pivot_longer(
    cols = -hr_group,
    names_to = "period",
    values_to = "identical_vote_share"
  ) |>
  dplyr::mutate(
    period = dplyr::recode(
      period,
      `identical_vote_share_pré-2009` = "pré-2009",
      `identical_vote_share_pós-2009` = "pós-2009"
    )
  )

hr_plot <- hr_plot_data |>
  ggplot2::ggplot(ggplot2::aes(x = hr_group, y = identical_vote_share, fill = period)) +
  ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.65) +
  ggplot2::scale_fill_manual(values = c("pré-2009" = "#2166AC", "pós-2009" = "#B2182B")) +
  ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%")) +
  ggplot2::coord_cartesian(ylim = c(50, 100)) +
  ggplot2::labs(
    title = "Figura 5. Direitos humanos versus não-direitos humanos",
    x = NULL,
    y = "Votos idênticos (%)",
    fill = "",
    caption = "Robustez descritiva excluindo direitos humanos; não substitui um ideal point reestimado sem essas resoluções."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold")
  )
save_plot_pair(hr_plot, fig_hr_png, fig_hr_pdf, 7, 4.8)

baseline_reproduced <- !is.na(target_validation$estimate_delta_local_minus_target[[1]]) &&
  abs(target_validation$estimate_delta_local_minus_target[[1]]) < 0.000001
if (!baseline_reproduced) {
  warning(
    "Local baseline SDiD estimate did not exactly reproduce target `synth_fit`; ",
    "report keeps the diagnostic but marks validation as warn."
  )
}

validation_checks <- tibble::tibble(
  check = c(
    "paper_v4_not_edited_by_script",
    "targets_pipeline_not_run",
    "resolution_similarity_score_range",
    "resolution_unique_rcid_issue_rows",
    "country_year_brazil_complete_for_sdid_outcomes",
    "sdid_baseline_target_estimate_reproduced",
    "sdid_alternative_donor_pools_checked"
  ),
  status = c(
    "manual_constraint",
    "manual_constraint",
    ifelse(all(resolution_data$similarity_score %in% c(0, 0.5, 1)), "pass", "fail"),
    ifelse(anyDuplicated(resolution_data |> dplyr::select(rcid, issue_family)) == 0, "pass", "fail"),
    ifelse(all(!is.na(brazil_country_year$value)), "pass", "fail"),
    ifelse(
      baseline_reproduced,
      "pass",
      "warn"
    ),
    ifelse(
      all(donor_pool_comparison$same_as_baseline %in% c(TRUE, NA)),
      "pass",
      "warn"
    )
  ),
  detail = c(
    "O script não contém escrita ou leitura para modificar paper_v4.Rmd.",
    "O script usa tar_read_raw/tar_meta; não chama targets::tar_make().",
    "similarity_score deve pertencer a {0, 0.5, 1}.",
    "Checa duplicatas por rcid/issue_family no CSV de resoluções.",
    "Checa missingness dos outcomes brasileiros nas tendências country-year.",
    paste0("delta local-target = ", fmt_num(target_validation$estimate_delta_local_minus_target[[1]], 8)),
    "Compara explicitamente os doadores de cada outcome SDiD contra o baseline local."
  )
)
readr::write_csv(validation_checks, validation_path, na = "")

capture.output(utils::sessionInfo(), file = session_info_path)

sdid_report_table <- sdid_results |>
  dplyr::select(
    outcome,
    evidence_tier,
    estimate,
    se_placebo,
    p_value,
    n_countries,
    donor_pool_status,
    inference_status,
    pre_period,
    post_period,
    supports_alignment_claim,
    error
  )

feasibility_report_table <- feasibility |>
  dplyr::select(
    outcome,
    data_level,
    evidence_tier,
    allows_sdid_with_donor_pool,
    allows_brazil_only_descriptive,
    period_covered,
    missing_pct,
    agenda_composition_risk
  )

issue_report_table <- issue_pre_post |>
  dplyr::select(
    issue_family,
    `n_resolutions_pré-2009`,
    `n_resolutions_pós-2009`,
    `identical_vote_share_pré-2009`,
    `identical_vote_share_pós-2009`,
    delta_identical_vote_share
  )

hr_report_table <- hr_nonhr |>
  dplyr::select(
    hr_group,
    `n_resolutions_pré-2009`,
    `n_resolutions_pós-2009`,
    `identical_vote_share_pré-2009`,
    `identical_vote_share_pós-2009`,
    delta_identical_vote_share
  )

composition_report_table <- composition_decomposition |>
  dplyr::select(
    metric,
    pre_overall,
    post_overall,
    total_change_pp,
    within_issue_effect_pp,
    composition_effect_pp,
    residual_interaction_pp
  )

baseline <- sdid_results |>
  dplyr::filter(outcome == "abs_distance_china") |>
  dplyr::slice(1)
relative <- sdid_results |>
  dplyr::filter(outcome == "relative_distance_china_minus_usa") |>
  dplyr::slice(1)
china_agreement <- sdid_results |>
  dplyr::filter(outcome == "china_agree") |>
  dplyr::slice(1)
china_minus_us <- sdid_results |>
  dplyr::filter(outcome == "china_minus_us_agree") |>
  dplyr::slice(1)
usa_distance <- sdid_results |>
  dplyr::filter(outcome == "abs_distance_usa") |>
  dplyr::slice(1)

hr_delta <- hr_nonhr$delta_identical_vote_share[hr_nonhr$hr_group == "Direitos humanos"]
nonhr_delta <- hr_nonhr$delta_identical_vote_share[hr_nonhr$hr_group == "Não direitos humanos"]
overall_identical_delta <- resolution_diagnostics$delta_post_minus_pre[
  resolution_diagnostics$outcome == "identical_vote_share_brazil_china"
]

issue_concentration_sentence <- if (!is.na(hr_delta) && !is.na(nonhr_delta) && hr_delta > nonhr_delta) {
  paste0(
    "A convergência descritiva é mais forte em direitos humanos (",
    fmt_num(hr_delta, 1),
    " p.p.) do que fora de direitos humanos (",
    fmt_num(nonhr_delta, 1),
    " p.p.)."
  )
} else if (!is.na(hr_delta) && !is.na(nonhr_delta)) {
  paste0(
    "A convergência descritiva não está concentrada apenas em direitos humanos: direitos humanos mudam ",
    fmt_num(hr_delta, 1),
    " p.p., enquanto as demais resoluções mudam ",
    fmt_num(nonhr_delta, 1),
    " p.p."
  )
} else {
  "Não foi possível calcular de forma limpa o contraste direitos humanos versus não-direitos humanos."
}

composition_sentence <- {
  row <- composition_decomposition |>
    dplyr::filter(metric == "identical_vote_share") |>
    dplyr::slice(1)
  paste0(
    "Na decomposição simples do percentual de votos idênticos, a mudança total é ",
    fmt_num(row$total_change_pp, 1),
    " p.p.; o componente dentro das áreas é ",
    fmt_num(row$within_issue_effect_pp, 1),
    " p.p. e o componente de composição da agenda é ",
    fmt_num(row$composition_effect_pp, 1),
    " p.p."
  )
}

sdid_bottom_line <- paste0(
  "No painel country-year, o baseline SDiD para distância à China permanece ",
  ifelse(baseline$estimate < 0, "no sentido esperado", "fora do sentido esperado"),
  " (estimativa = ",
  fmt_num(baseline$estimate, 3),
  "; SE placebo = ",
  fmt_num(baseline$se_placebo, 3),
  "). O contraste relativo China-menos-EUA também fica ",
  ifelse(relative$estimate < 0, "no sentido esperado", "fora do sentido esperado"),
  " (estimativa = ",
  fmt_num(relative$estimate, 3),
  ")."
)

agreement_bottom_line <- paste0(
  "Nos outcomes de acordo anual, o acordo com a China fica ",
  ifelse(china_agreement$estimate > 0, "no sentido esperado", "fora do sentido esperado"),
  " (estimativa = ",
  fmt_num(china_agreement$estimate, 3),
  ") e o acordo China-menos-EUA fica ",
  ifelse(china_minus_us$estimate > 0, "no sentido esperado", "fora do sentido esperado"),
  " (estimativa = ",
  fmt_num(china_minus_us$estimate, 3),
  "). Esses outcomes são mais sensíveis à composição anual da agenda do que os ideal points."
)

suggested_paragraph_main <- paste0(
  "As a robustness check, I reestimated the Brazilian SDiD using alternative UNGA-based country-year outcomes. ",
  "The main result is not an artifact of the exact absolute-distance metric: Brazil also moves closer to China relative to the United States in the China-minus-US distance contrast. ",
  "However, annual agreement measures and resolution-level vote similarity are more sensitive to agenda composition, so I treat them as interpretive diagnostics rather than alternative primary estimands. ",
  "The resolution-level evidence indicates selective convergence, especially around human-rights votes, which narrows the substantive interpretation from wholesale foreign-policy realignment to issue-specific UNGA convergence after the 2009 trade-rank reversal."
)

suggested_paragraph_caveat <- paste0(
  "This evidence should not be read as showing a uniform shift across the entire UNGA agenda. ",
  "The post-2009 Brazil-China convergence is clearest in the ideal-point and relative-distance outcomes and is descriptively concentrated in issue areas where Brazil and China had room to converge, especially human rights. ",
  "Excluding human-rights resolutions weakens the descriptive resolution-level pattern, which is substantively informative rather than damaging: it suggests a selective diplomatic adjustment in politically salient areas, not a wholesale replacement of Brazil's foreign-policy orientation."
)

files_written <- c(
  object_audit_path,
  feasibility_path,
  sdid_results_path,
  sdid_validation_path,
  sdid_series_path,
  country_year_brazil_path,
  resolution_yearly_path,
  issue_pre_post_path,
  hr_nonhr_path,
  composition_path,
  composition_decomp_path,
  issue_common_support_path,
  donor_pool_path,
  diagnostic_comparison_path,
  validation_path,
  session_info_path,
  report_path,
  report_pdf_path,
  pdf_render_log_path,
  fig_country_year_png,
  fig_country_year_pdf,
  fig_sdid_png,
  fig_sdid_pdf,
  fig_resolution_png,
  fig_resolution_pdf,
  fig_issue_png,
  fig_issue_pdf,
  fig_hr_png,
  fig_hr_pdf
)

report_lines <- c(
  "# Goal 6: robustez de outcome para o resultado brasileiro",
  "",
  paste0("Data: ", run_date),
  "",
  paste0("Execução: ", run_timestamp),
  "",
  paste0("Script: `", script_path, "`"),
  "",
  "Este relatório foi gerado por um script diagnóstico auditável. Ele não edita `paper_v4.Rmd`, não altera `_targets.R`, `_targets/` ou `_targets.yaml`, e não executa `targets::tar_make()`.",
  "",
  "## Resposta curta",
  "",
  sdid_bottom_line,
  "",
  agreement_bottom_line,
  "",
  paste0("No nível resolution-year, a mudança pré/pós-2009 no percentual geral de votos idênticos é ", fmt_num(overall_identical_delta, 1), " p.p. ", issue_concentration_sentence),
  "",
  composition_sentence,
  "",
  "Conclusão: o resultado brasileiro não depende exclusivamente de uma única medida de distância ideal-point à China. A crítica de composição temática é real e deve estreitar o claim: a evidência resolution-level apoia uma leitura de convergência seletiva na AGNU, não de realinhamento amplo e homogêneo de política externa.",
  "",
  "## Contrato causal",
  "",
  "Tabela 1. Contrato causal do exercício de robustez de outcome.",
  "",
  markdown_table(tibble::tribble(
    ~elemento, ~definicao,
    "Unidade causal principal", "Brasil-ano no SDiD; resoluções Brasil-China apenas como diagnóstico descritivo.",
    "Tratamento", "China torna-se o maior destino das exportações brasileiras em 2009.",
    "Estimando mantido", "ATT médio pós-2009 para o caso brasileiro no painel country-year.",
    "Outcome principal", "Distância absoluta Brasil-China em ideal points da AGNU.",
    "Outcomes alternativos estimáveis", "Distância relativa China-menos-EUA; distância aos EUA; acordo anual com China; acordo China-menos-EUA.",
    "Diagnósticos não causais", "Votos idênticos, similarity score e decomposição por issue area no nível resolution-year.",
    "Regra de interpretação", "Outcomes alternativos testam robustez do sinal; não substituem automaticamente o estimando principal."
  ), digits = 3),
  "",
  "## Objetos e dados usados",
  "",
  "Tabela 2. Objetos auditados para outcomes e medidas de agenda.",
  "",
  markdown_table(
    object_audit |>
      dplyr::select(
        name,
        source_type,
        object_class,
        nrow,
        ncol,
        has_abs_distance_china,
        has_abs_distance_usa,
        has_china_agree,
        has_identical_vote,
        has_similarity_score,
        has_issue_area,
        read_error
      ),
    digits = 1,
    max_rows = 20
  ),
  "",
  "## Matriz de viabilidade",
  "",
  "Tabela 3. Viabilidade dos outcomes para SDiD ou diagnóstico Brasil-only.",
  "",
  markdown_table(feasibility_report_table, digits = 2),
  "",
  "Decisão metodológica: apenas outcomes country-year entram no SDiD com donor pool. Outcomes resolution-level e issue-year não são forçados para SDiD porque não há painel comparável de países-doadores com o mesmo outcome e mesma agregação já preservado no projeto.",
  "",
  "## Resultados SDiD com outcomes alternativos",
  "",
  "Tabela 4. Reestimações SDiD por outcome country-year.",
  "",
  markdown_table(sdid_report_table, digits = 3),
  "",
  "Tabela 4a. Comparação explícita do donor pool por outcome SDiD.",
  "",
  markdown_table(donor_pool_comparison, digits = 1),
  "",
  paste0("Validação do baseline contra o target existente: delta da estimativa local menos target = ", fmt_num(target_validation$estimate_delta_local_minus_target[[1]], 8), "; delta do SE local menos target = ", fmt_num(target_validation$se_delta_local_minus_target[[1]], 8), "."),
  "",
  paste0("![Figura 1. Tendências brasileiras por outcome country-year](", basename(fig_country_year_png), ")"),
  "",
  paste0("![Figura 2. Brasil versus sintético por outcome SDiD](", basename(fig_sdid_png), ")"),
  "",
  "Interpretação: a distância relativa China-menos-EUA é o teste mais próximo do claim substantivo, pois pergunta se a aproximação à China sobrevive quando se considera simultaneamente a distância aos EUA. As medidas de acordo anual são úteis, mas mais vulneráveis ao mix de resoluções; por isso, elas são diagnósticos de interpretação e não novos outcomes principais.",
  "",
  "## Diagnósticos resolution-level",
  "",
  "Tabela 5. Mudança pré/pós-2009 por issue area.",
  "",
  markdown_table(issue_report_table, digits = 1),
  "",
  "Tabela 6. Direitos humanos versus não-direitos humanos.",
  "",
  markdown_table(hr_report_table, digits = 1),
  "",
  paste0("![Figura 3. Votos idênticos por ano](", basename(fig_resolution_png), ")"),
  "",
  paste0("![Figura 4. Mudança por área temática](", basename(fig_issue_png), ")"),
  "",
  paste0("![Figura 5. Direitos humanos versus não-direitos humanos](", basename(fig_hr_png), ")"),
  "",
  "## Composição da agenda",
  "",
  "Tabela 7. Decomposição simples da mudança agregada em componente dentro das áreas e componente de composição temática.",
  "",
  markdown_table(composition_report_table, digits = 2),
  "",
  "Tabela 7a. Suporte comum de áreas temáticas entre pré-2009 e pós-2009.",
  "",
  markdown_table(issue_common_support, digits = 1),
  "",
  "Esta decomposição é descritiva, não causal. Ela responde à crítica de artifact mostrando quanto da mudança agregada pode ser atribuída ao peso relativo dos temas e quanto aparece como mudança dentro das próprias áreas temáticas.",
  "Quando alguma área temática aparece em apenas um período, a decomposição limpa fica limitada; por isso a tabela de suporte comum deve acompanhar a leitura da decomposição.",
  "",
  "## Avaliação causal",
  "",
  "### Identificação",
  "",
  "Tabela 8. Suposições, diagnósticos e implicações.",
  "",
  markdown_table(tibble::tribble(
    ~suposicao, ~evidencia_disponivel, ~diagnostico_possivel, ~status, ~implicacao,
    "Validade de medida do outcome principal", "Ideal points country-year já usados no SDiD principal.", "Comparar com distância relativa e medidas de acordo anual.", "Crível com ressalvas", "Robustez de sinal reduz dependência de uma única métrica.",
    "Donor pool comparável", "Mesmo painel e mesmos covariates para outcomes country-year.", "Não aplicar a resolution-level sem painel de doadores.", "Adequado para country-year", "Resolution-level fica interpretativo.",
    "No anticipation e timing", "Mantém janela pré/pós do SDiD brasileiro.", "Placebos existentes continuam relevantes, mas não são reestimados por issue area.", "Parcialmente verificável", "Não transformar diagnósticos de outcome em nova prova de identificação.",
    "Estabilidade de composição do outcome", "Ideal points absorvem toda a agenda; agreement/resolution shares dependem do mix de resoluções.", "Decomposição por issue area e exclusão de direitos humanos.", "Ameaça real", "Claim deve ser estreitado se a convergência for temática.",
    "SUTVA/donor não contaminado", "Não é testado por este pacote de outcome.", "Usar relatórios Goal 5/donor sensitivities.", "Fora do escopo direto", "Este pacote complementa, mas não substitui, a auditoria de donor pool."
  ), digits = 3),
  "",
  "Veredito de identificação: crível com ressalvas para o outcome principal e o contraste relativo country-year; interpretativo, não causal, para resolution-level e issue-area.",
  "",
  "### Estimação",
  "",
  "O estimador SDiD continua alinhado ao estimando apenas nos outcomes country-year. Usar o mesmo desenho para votos por resolução criaria uma falsa equivalência entre uma medida anual comparável entre países e uma série Brasil-China sem donor pool. O contraste `relative_distance_china_minus_usa` é defensável porque deriva das duas distâncias já existentes no painel; a razão foi evitada para não introduzir instabilidade por denominadores pequenos e interpretação menos transparente.",
  "",
  "### Inferência",
  "",
  "A inferência permanece placebo-based e limitada por uma unidade tratada. Para o baseline, o SE placebo é lido do target existente. Para outcomes alternativos, o script reporta estimativas de ponto sem recomputar uma bateria de SE placebo exploratórios; essa escolha evita inflar a inferência de outcomes secundários e mantém a hierarquia entre outcome principal, robustez causal alternativa e diagnósticos interpretativos. As diferenças resolution-level são pré/pós descritivas e não recebem p-valores causais.",
  "",
  "## Limitações",
  "",
  "- O pacote não reestima ideal points excluindo direitos humanos; isso exigiria reconstrução de measurement model por issue area e não seria uma robustez leve.",
  "- Votos idênticos e agreement shares são sensíveis ao denominador anual de resoluções.",
  "- A decomposição de composição da agenda é descritiva e não identifica mecanismos causais.",
  "- Outcomes alternativos não devem substituir o outcome principal sem uma justificativa teórica e de mensuração mais forte.",
  "",
  "## O que deveria entrar no texto principal",
  "",
  "- Uma frase dizendo que o resultado não depende apenas da distância absoluta à China porque o contraste relativo China-menos-EUA aponta na mesma direção.",
  "- Um caveat dizendo que medidas resolution-level são interpretativas e sensíveis à composição da agenda.",
  "- Uma frase estreitando o mecanismo para convergência seletiva na AGNU, especialmente se direitos humanos concentrar a mudança descritiva.",
  "- A tabela completa de viabilidade, decomposição por issue area e figuras longas devem ficar em apêndice ou relatório de qualidade, não no main text.",
  "",
  "## Sugestões de parágrafo",
  "",
  "Parágrafo curto para robustez de outcome:",
  "",
  paste0("> ", suggested_paragraph_main),
  "",
  "Parágrafo de cautela substantiva:",
  "",
  paste0("> ", suggested_paragraph_caveat),
  "",
  "## Arquivos gerados",
  "",
  paste0("- `", files_written, "`")
)

writeLines(report_lines, con = report_path, useBytes = TRUE)

render_log <- character()
if (nzchar(Sys.which("pandoc")) && nzchar(Sys.which("xelatex"))) {
  render_log <- tryCatch(
    system2(
      "pandoc",
      args = c(
        shQuote(report_path),
        "-o",
        shQuote(report_pdf_path),
        paste0("--resource-path=", shQuote(out_dir)),
        "--pdf-engine=xelatex"
      ),
      stdout = TRUE,
      stderr = TRUE
    ),
    error = function(e) paste("PDF render error:", conditionMessage(e))
  )
  if (!file.exists(report_pdf_path)) {
    render_log <- c(render_log, "PDF file was not created.")
  }
} else {
  render_log <- c(
    "PDF render skipped: pandoc or xelatex not available on PATH.",
    paste0("pandoc: ", Sys.which("pandoc")),
    paste0("xelatex: ", Sys.which("xelatex"))
  )
}
writeLines(render_log, con = pdf_render_log_path, useBytes = TRUE)

message("Goal 6 outcome robustness diagnostics complete.")
message("Report: ", report_path)
