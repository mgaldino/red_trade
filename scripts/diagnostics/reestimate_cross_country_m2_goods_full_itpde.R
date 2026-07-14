#!/usr/bin/env Rscript

# Diagnostic only. This script reconstructs the goods-only China #1 treatment
# from the original ITPD-E file for the full original time window, outside the
# targets pipeline. It reads existing target objects read-only and does not run
# targets::tar_make().

options(scipen = 999)

suppressPackageStartupMessages({
  library(DBI)
  library(countrycode)
  library(dplyr)
  library(duckdb)
  library(readr)
  library(rmarkdown)
  library(tibble)
  library(tidyr)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

source("scripts/functions.R")

run_date <- as.Date("2026-05-20")
rank_window_start <- 1990L
rank_window_end <- 2023L
model_window_start <- 1990L
nboots <- 500L

processed_dir <- file.path(
  "data", "processed", "diagnostics", "china_top_m2_goods_full_itpde"
)
report_dir <- file.path("quality_reports", "china_top_m2_goods_full_itpde")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

read_target_object <- function(name) {
  path <- file.path("_targets", "objects", name)
  if (!file.exists(path)) {
    stop("Required read-only targets object not found: ", path, call. = FALSE)
  }
  readRDS(path)
}

fmt <- function(x, digits = 3L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

format_p <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "NA",
    x < 0.001 ~ "<0.001",
    TRUE ~ sprintf("%.3f", x)
  )
}

abort_if_duplicates <- function(data, keys, label) {
  duplicates <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(n > 1L)

  if (nrow(duplicates) > 0L) {
    example <- duplicates |>
      utils::head(5L) |>
      capture.output() |>
      paste(collapse = "\n")

    stop(
      "Duplicate keys detected in ", label, " for keys: ",
      paste(keys, collapse = ", "), "\nExamples:\n", example,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

first_year_status <- function(panel, metric_name, metric_label) {
  panel |>
    tibble::as_tibble() |>
    dplyr::filter(!is.na(iso3c), iso3c != "CHN") |>
    dplyr::mutate(
      china_rank1_observed = dplyr::coalesce(china_is_top, FALSE),
      trade_observed = !is.na(top_partner)
    ) |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      first_observed_year = {
        value <- year[trade_observed]
        if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
      },
      first_china_rank1_year = {
        value <- year[china_rank1_observed]
        if (length(value) == 0L) NA_integer_ else min(value, na.rm = TRUE)
      },
      ever_china_rank1 = any(china_rank1_observed, na.rm = TRUE),
      status = dplyr::case_when(
        is.na(first_china_rank1_year) ~ "never_observed",
        !is.na(first_observed_year) &
          first_china_rank1_year == first_observed_year ~
          "left_censored_first_observed",
        TRUE ~ "observed_entry"
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      metric = metric_name,
      metric_label = metric_label
    ) |>
    dplyr::select(
      metric, metric_label, iso3c, country_name, first_observed_year,
      first_china_rank1_year, ever_china_rank1, status
    )
}

sample_status <- function(panel, metric_name, metric_label) {
  panel |>
    tibble::as_tibble() |>
    dplyr::group_by(iso3c, country_name) |>
    dplyr::summarise(
      in_regression_sample = TRUE,
      first_treat = {
        value <- first_treat[!is.na(first_treat)]
        if (length(value) == 0L) NA_real_ else value[[1]]
      },
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      n_years = dplyr::n(),
      min_year = min(year, na.rm = TRUE),
      max_year = max(year, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      metric = metric_name,
      metric_label = metric_label,
      treatment_status = dplyr::case_when(
        ever_treated ~ "treated_in_absorbing_sample",
        TRUE ~ "never_treated_in_absorbing_sample"
      )
    ) |>
    dplyr::select(
      metric, metric_label, iso3c, country_name, in_regression_sample,
      treatment_status, first_treat, ever_treated, treated_years, n_years,
      min_year, max_year
    )
}

aggregate_itpde_goods_exports <- function(itpd_path, panel_countries,
                                          start_year, end_year) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tempfile(fileext = ".duckdb"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbWriteTable(
    con,
    "panel_countries",
    panel_countries |> dplyr::select(iso3c),
    temporary = TRUE,
    overwrite = TRUE
  )

  itpd_sql <- as.character(DBI::dbQuoteString(
    con,
    normalizePath(itpd_path, mustWork = TRUE)
  ))

  message("Aggregating full-window ITPD-E goods exports with DuckDB.")
  DBI::dbExecute(con, paste0(
    "CREATE TEMP TABLE goods_exports AS ",
    "SELECT ",
    "try_cast(year AS INTEGER) AS year, ",
    "upper(exporter_iso3) AS exporter_iso3, ",
    "upper(importer_iso3) AS importer_iso3, ",
    "sum(coalesce(try_cast(trade AS DOUBLE), 0)) AS exports ",
    "FROM read_csv_auto(", itpd_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
    "AND upper(exporter_iso3) <> upper(importer_iso3) ",
    "AND broad_sector IN ('Agriculture', 'Mining and Energy', 'Manufacturing') ",
    "GROUP BY 1, 2, 3"
  ))

  out <- DBI::dbGetQuery(con, paste0(
    "SELECT ge.year, ge.exporter_iso3, ge.importer_iso3, ge.exports ",
    "FROM goods_exports ge ",
    "INNER JOIN panel_countries pc ON ge.exporter_iso3 = pc.iso3c"
  )) |>
    tibble::as_tibble() |>
    dplyr::mutate(year = as.integer(year)) |>
    dplyr::select(year, exporter_iso3, importer_iso3, exports) |>
    dplyr::arrange(exporter_iso3, year, importer_iso3)

  abort_if_duplicates(
    out,
    c("year", "exporter_iso3", "importer_iso3"),
    "full-window ITPD-E goods exports"
  )

  out
}

message("Reading read-only targets objects.")
unga_data <- read_target_object("unga_data")
covariates_panel <- read_target_object("covariates_panel")
original_full_panel <- read_target_object("china_top_panel")
original_absorbing_cov_sample <- read_target_object("china_top_absorbing_cov_sample")
original_main_summary <- read_target_object("fect_ife_china_top_cov_summary")

panel_countries <- original_full_panel |>
  tibble::as_tibble() |>
  dplyr::filter(!is.na(iso3c), iso3c != "CHN") |>
  dplyr::distinct(iso3c, country_name) |>
  dplyr::mutate(
    country_name = dplyr::coalesce(
      country_name,
      countrycode::countrycode(iso3c, "iso3c", "country.name", warn = FALSE)
    )
  ) |>
  dplyr::arrange(iso3c)

model_window_end <- min(
  max(covariates_panel$year, na.rm = TRUE),
  max(unga_data$year, na.rm = TRUE),
  2020L
)

itpd_path <- file.path("raw data", "ITPDE_R03.csv")
goods_trade_full <- aggregate_itpde_goods_exports(
  itpd_path,
  panel_countries,
  rank_window_start,
  rank_window_end
)

message("Building full-window M2 China #1 panel.")
m2_full_panel <- build_china_top_partner_panel(
  goods_trade_full,
  unga_data,
  min_year = rank_window_start
)

m2_absorbing_sample <- prepare_absorbing_china_top_sample(m2_full_panel)
m2_absorbing_cov_sample <- prepare_absorbing_china_top_covariate_sample(
  m2_absorbing_sample,
  covariates_panel,
  covariate_cols = c("log_gdp_pc", "free_press")
)

m2_model_panel <- m2_absorbing_cov_sample |>
  tibble::as_tibble() |>
  dplyr::filter(year >= model_window_start, year <= model_window_end) |>
  dplyr::filter(dplyr::if_all(
    dplyr::all_of(c(
      "year", "iso3c", "abs_distance_china", "china_top",
      "log_gdp_pc", "free_press"
    )),
    ~ !is.na(.x)
  )) |>
  dplyr::mutate(country_id = as.integer(as.factor(iso3c))) |>
  dplyr::arrange(country_id, year)

message("Estimating full-window M2 fect IFE model with nboots = ", nboots, ".")
timing <- system.time({
  fit <- run_fect_analysis(
    m2_model_panel,
    method = "ife",
    nboots = nboots,
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
  )
})
fit_summary <- fect_att_summary(fit)

m2_result <- tibble::tibble(
  metric = "m2_goods_exports_rank_full_itpde",
  metric_label = "M2 full: bens/exportações ITPD-E",
  rule = "original_absorbing_covariate_design",
  rule_label = "Amostra absorvente com covariáveis",
  status = "ok",
  nboots = nboots,
  att = as.numeric(fit_summary$att),
  se = as.numeric(fit_summary$se),
  ci_lo = as.numeric(fit_summary$ci_lo),
  ci_hi = as.numeric(fit_summary$ci_hi),
  p = as.numeric(fit_summary$p),
  r_cv = paste(fit_summary$r_cv, collapse = ";"),
  elapsed_seconds = as.numeric(timing[["elapsed"]]),
  n_obs = nrow(m2_model_panel),
  n_countries = dplyr::n_distinct(m2_model_panel$iso3c),
  n_treated = dplyr::n_distinct(m2_model_panel$iso3c[m2_model_panel$china_top == 1L]),
  n_control = dplyr::n_distinct(m2_model_panel$iso3c) -
    dplyr::n_distinct(m2_model_panel$iso3c[m2_model_panel$china_top == 1L]),
  panel_min = min(m2_model_panel$year, na.rm = TRUE),
  panel_max = max(m2_model_panel$year, na.rm = TRUE)
)

original_result <- tibble::as_tibble(original_main_summary) |>
  dplyr::mutate(
    r_cv = as.character(r_cv),
    metric = "pipeline_original_itpde_no_sector_filter",
    metric_label = "Pipeline original sem filtro setorial",
    rule = "targets_absorbing_covariate_design",
    rule_label = "Amostra absorvente com covariáveis",
    status = "ok",
    nboots = 10000L,
    elapsed_seconds = NA_real_,
    .before = att
  ) |>
  dplyr::select(
    metric, metric_label, rule, rule_label, status, nboots, att, se, ci_lo,
    ci_hi, p, r_cv, elapsed_seconds, n_obs, n_countries, n_treated,
    n_control, panel_min, panel_max
  )

results <- dplyr::bind_rows(original_result, m2_result)

first_year_long <- dplyr::bind_rows(
  first_year_status(
    original_full_panel,
    "pipeline_original_itpde_no_sector_filter",
    "Pipeline original sem filtro setorial"
  ),
  first_year_status(
    m2_full_panel,
    "m2_goods_exports_rank_full_itpde",
    "M2 full: bens/exportações ITPD-E"
  )
)

first_year_change <- first_year_long |>
  dplyr::select(
    metric, iso3c, country_name, first_china_rank1_year,
    ever_china_rank1, status
  ) |>
  tidyr::pivot_wider(
    names_from = metric,
    values_from = c(first_china_rank1_year, ever_china_rank1, status)
  ) |>
  dplyr::mutate(
    original_year =
      first_china_rank1_year_pipeline_original_itpde_no_sector_filter,
    m2_full_year = first_china_rank1_year_m2_goods_exports_rank_full_itpde,
    original_ever =
      ever_china_rank1_pipeline_original_itpde_no_sector_filter,
    m2_full_ever = ever_china_rank1_m2_goods_exports_rank_full_itpde,
    status_original = status_pipeline_original_itpde_no_sector_filter,
    status_m2_full = status_m2_goods_exports_rank_full_itpde,
    change_type = dplyr::case_when(
      !original_ever & m2_full_ever ~ "m2_full_treated_original_never",
      original_ever & !m2_full_ever ~ "original_treated_m2_full_never",
      original_ever & m2_full_ever & original_year != m2_full_year ~
        "both_treated_year_changed",
      original_ever & m2_full_ever & status_original != status_m2_full ~
        "same_year_censoring_status_changed",
      TRUE ~ "no_change"
    )
  ) |>
  dplyr::select(
    iso3c, country_name, original_year, m2_full_year, original_ever,
    m2_full_ever, status_original, status_m2_full, change_type
  ) |>
  dplyr::arrange(change_type, country_name)

sample_status_long <- dplyr::bind_rows(
  sample_status(
    original_absorbing_cov_sample,
    "pipeline_original_itpde_no_sector_filter",
    "Pipeline original sem filtro setorial"
  ),
  sample_status(
    m2_absorbing_cov_sample,
    "m2_goods_exports_rank_full_itpde",
    "M2 full: bens/exportações ITPD-E"
  )
)

sample_status_change <- sample_status_long |>
  dplyr::select(
    metric, iso3c, country_name, in_regression_sample, treatment_status,
    first_treat, ever_treated, min_year, max_year
  ) |>
  tidyr::pivot_wider(
    names_from = metric,
    values_from = c(
      in_regression_sample, treatment_status, first_treat, ever_treated,
      min_year, max_year
    )
  ) |>
  dplyr::mutate(
    original_in_sample = dplyr::coalesce(
      in_regression_sample_pipeline_original_itpde_no_sector_filter,
      FALSE
    ),
    m2_full_in_sample = dplyr::coalesce(
      in_regression_sample_m2_goods_exports_rank_full_itpde,
      FALSE
    ),
    original_treated = dplyr::coalesce(
      ever_treated_pipeline_original_itpde_no_sector_filter,
      FALSE
    ),
    m2_full_treated = dplyr::coalesce(
      ever_treated_m2_goods_exports_rank_full_itpde,
      FALSE
    ),
    change_type = dplyr::case_when(
      original_in_sample & !m2_full_in_sample ~ "drops_out_of_m2_full_sample",
      !original_in_sample & m2_full_in_sample ~ "enters_m2_full_sample",
      original_treated & !m2_full_treated ~ "treated_original_never_m2_full",
      !original_treated & m2_full_treated ~ "never_original_treated_m2_full",
      original_treated & m2_full_treated &
        first_treat_pipeline_original_itpde_no_sector_filter !=
        first_treat_m2_goods_exports_rank_full_itpde ~
        "both_treated_first_treat_changed",
      TRUE ~ "no_change"
    )
  ) |>
  dplyr::select(
    iso3c, country_name, original_in_sample, m2_full_in_sample,
    original_treated, m2_full_treated,
    first_treat_original = first_treat_pipeline_original_itpde_no_sector_filter,
    first_treat_m2_full = first_treat_m2_goods_exports_rank_full_itpde,
    change_type
  ) |>
  dplyr::arrange(change_type, country_name)

results_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_model_results_", run_date, ".csv")
)
model_panel_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_model_panel_", run_date, ".csv")
)
first_year_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_first_year_change_vs_original_", run_date, ".csv")
)
sample_change_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_regression_sample_change_vs_original_", run_date, ".csv")
)
target_manifest_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_target_inputs_manifest_", run_date, ".csv")
)
session_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_session_info_", run_date, ".txt")
)
report_md <- file.path(
  report_dir,
  paste0("nota_m2_goods_full_itpde_", run_date, ".md")
)
report_rmd <- file.path(
  report_dir,
  paste0("nota_m2_goods_full_itpde_", run_date, ".Rmd")
)
report_pdf <- file.path(
  report_dir,
  paste0("nota_m2_goods_full_itpde_", run_date, ".pdf")
)

target_object_names <- c(
  "unga_data",
  "covariates_panel",
  "china_top_panel",
  "china_top_absorbing_cov_sample",
  "fect_ife_china_top_cov_summary"
)
target_object_paths <- file.path("_targets", "objects", target_object_names)
target_manifest <- tibble::tibble(
  object = target_object_names,
  path = target_object_paths,
  md5 = unname(tools::md5sum(target_object_paths))
)

readr::write_csv(results, results_file, na = "")
readr::write_csv(m2_model_panel, model_panel_file, na = "")
readr::write_csv(first_year_change, first_year_file, na = "")
readr::write_csv(sample_status_change, sample_change_file, na = "")
readr::write_csv(target_manifest, target_manifest_file, na = "")
writeLines(capture.output(utils::sessionInfo()), session_file, useBytes = TRUE)

result_lines <- results |>
  dplyr::mutate(
    line = paste0(
      "| ", metric_label, " | ", panel_min, "-", panel_max, " | ",
      n_countries, " | ", n_treated, " | ", n_control, " | ",
      fmt(att), " | ", fmt(se), " | [", fmt(ci_lo), ", ", fmt(ci_hi),
      "] | ", format_p(p), " |"
    )
  ) |>
  dplyr::pull(line)

first_year_summary_lines <- first_year_change |>
  dplyr::count(change_type, name = "n_countries") |>
  dplyr::mutate(line = paste0("| ", change_type, " | ", n_countries, " |")) |>
  dplyr::pull(line)

first_year_changed_lines <- first_year_change |>
  dplyr::filter(change_type != "no_change") |>
  dplyr::mutate(
    line = paste0(
      "| ", change_type, " | ", iso3c, " | ", country_name, " | ",
      ifelse(is.na(original_year), "Nunca", original_year), " | ",
      ifelse(is.na(m2_full_year), "Nunca", m2_full_year), " |"
    )
  ) |>
  dplyr::pull(line)

sample_change_summary_lines <- sample_status_change |>
  dplyr::count(change_type, name = "n_countries") |>
  dplyr::mutate(line = paste0("| ", change_type, " | ", n_countries, " |")) |>
  dplyr::pull(line)

report_body <- c(
  "# Nota diagnóstica: M2 goods-only no painel ITPD-E completo",
  "",
  paste0("Data de execução: ", run_date),
  "",
  "## Correção de desenho",
  "",
  paste0(
    "A métrica M2 não precisa começar em 2005. Ela usa a mesma fonte ITPD-E ",
    "do pipeline original e apenas filtra `broad_sector` para bens ",
    "(`Agriculture`, `Mining and Energy`, `Manufacturing`). A restrição a ",
    "2005 só é necessária para comparações diretas com M3/M4, porque BaTIS ",
    "BPM6 começa em 2005. Portanto, a baseline substantiva correta deve ser ",
    "M2 no painel ITPD-E completo; M3/M4 ficam como robustez na janela comum ",
    "2005-2020."
  ),
  "",
  "## Tabela 1. Resultado comparativo",
  "",
  "| Métrica | Janela | Países | Tratados | Controles | ATT | SE | IC 95% | p |",
  "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
  result_lines,
  "",
  paste0(
    "Notas: a linha M2 foi reestimada com ", nboots,
    " bootstrap draws. A linha do pipeline original vem do objeto materializado ",
    "em `_targets` com 10.000 draws e é mantida apenas como diagnóstico de ",
    "operacionalização."
  ),
  "",
  "## Tabela 2. Mudança no status bruto de ranking",
  "",
  "| Tipo de mudança | Países |",
  "|---|---:|",
  first_year_summary_lines,
  "",
  "## Tabela 3. Países com mudança no primeiro ano observado China #1",
  "",
  "| Tipo de mudança | ISO3 | País | Original | M2 full |",
  "|---|---|---|---:|---:|",
  first_year_changed_lines,
  "",
  "## Tabela 4. Mudança na amostra absorvente estimável",
  "",
  "| Tipo de mudança | Países |",
  "|---|---:|",
  sample_change_summary_lines,
  "",
  "## Arquivos gerados",
  "",
  paste0("- `", results_file, "`"),
  paste0("- `", model_panel_file, "`"),
  paste0("- `", first_year_file, "`"),
  paste0("- `", sample_change_file, "`"),
  paste0("- `", target_manifest_file, "`")
)

writeLines(report_body, report_md, useBytes = TRUE)

rmd_body <- c(
  "---",
  "title: \"M2 goods-only no painel ITPD-E completo\"",
  paste0("date: \"", run_date, "\""),
  "documentclass: article",
  "classoption: landscape",
  "geometry: margin=0.55in",
  "output:",
  "  pdf_document:",
  "    toc: false",
  "    number_sections: false",
  "    latex_engine: xelatex",
  "---",
  "",
  report_body[-1]
)

writeLines(rmd_body, report_rmd, useBytes = TRUE)

pdf_status <- "skipped"
pdf_error <- NA_character_
pdf_attempt <- tryCatch(
  {
    rmarkdown::render(
      report_rmd,
      output_file = basename(report_pdf),
      output_dir = dirname(report_pdf),
      quiet = TRUE,
      envir = new.env(parent = globalenv())
    )
    "ok"
  },
  error = function(e) {
    pdf_error <<- conditionMessage(e)
    "error"
  }
)
pdf_status <- pdf_attempt

manifest_file <- file.path(
  processed_dir,
  paste0("m2_goods_full_itpde_output_manifest_", run_date, ".csv")
)
manifest <- tibble::tibble(
  generated_on = as.character(run_date),
  nboots = nboots,
  rank_window_start = rank_window_start,
  rank_window_end = rank_window_end,
  model_window_start = model_window_start,
  model_window_end = model_window_end,
  itpd_file = itpd_path,
  itpd_md5 = unname(tools::md5sum(itpd_path)),
  pdf_status = pdf_status,
  pdf_error = pdf_error,
  output = c(
    results_file, model_panel_file, first_year_file, sample_change_file,
    target_manifest_file, session_file, report_md, report_rmd, report_pdf
  )
)
readr::write_csv(manifest, manifest_file, na = "")

message("Wrote report: ", report_md)
if (identical(pdf_status, "ok")) {
  message("Wrote PDF: ", report_pdf)
} else {
  warning("PDF render failed: ", pdf_error, call. = FALSE)
}
message("Wrote results: ", results_file)
print(results)
