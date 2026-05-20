#!/usr/bin/env Rscript

# Reproducible construction of displaced-incumbent salience moderators.
# Reads existing targets only; does not run or modify the targets pipeline.

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(countrycode)
  library(here)
})

options(scipen = 999)

source(here::here("scripts", "functions.R"))

min_year <- 1990L
min_entry_year <- 2000L
creation_date <- as.character(Sys.Date())
creation_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
regional_power_list_version <- "strict_pre_specified_ri_ipe_2026_05_19"

processed_dir <- here::here("data", "processed", "diagnostics")
report_dir <- here::here(
  "reports",
  "incumbent_salience_vreeland_reuse_2026-05-19"
)

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

output_csv <- file.path(
  processed_dir,
  "incumbent_salience_moderators_2026-05-19.csv"
)
output_log <- file.path(
  report_dir,
  "incumbent_salience_variable_creation_log.md"
)

g7_iso3 <- c("CAN", "FRA", "DEU", "ITA", "JPN", "GBR", "USA")
regional_power_iso3 <- c(
  "USA", "BRA", "MEX", "ARG", "DEU", "FRA", "GBR", "RUS", "TUR", "EGY",
  "IRN", "SAU", "NGA", "ZAF", "IND", "PAK", "JPN", "KOR", "IDN", "AUS"
)
hub_entrepot_iso3 <- c("ARE", "BEL", "CHE", "HKG", "SGP")

country_name <- function(x) {
  countrycode::countrycode(x, "iso3c", "country.name", warn = FALSE)
}

country_region <- function(x) {
  countrycode::countrycode(x, "iso3c", "region", warn = FALSE)
}

format_count <- function(data, variable) {
  data %>%
    dplyr::count(.data[[variable]], name = "n") %>%
    dplyr::mutate(value = as.character(.data[[variable]])) %>%
    dplyr::select(value, n)
}

mode_partner <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_character_)
  }
  names(sort(table(x), decreasing = TRUE))[[1]]
}

validation_line <- function(label, passed, details) {
  paste0(
    "- ", label, ": ", if (isTRUE(passed)) "PASS" else "FAIL",
    if (!is.null(details) && nzchar(details)) paste0(" — ", details) else ""
  )
}

message("Reading existing targets: trade_data and unga_data.")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)

message("Building China-top-partner panel from existing objects.")
china_top_panel <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  min_year = min_year,
  min_entry_year = min_entry_year
)

required_panel_cols <- c(
  "iso3c", "year", "country_name", "top_partner", "china_top",
  "rank_CHN", "rank_USA"
)
missing_panel_cols <- setdiff(required_panel_cols, names(china_top_panel))
if (length(missing_panel_cols) > 0) {
  stop(
    "China-top panel is missing required columns: ",
    paste(missing_panel_cols, collapse = ", ")
  )
}

entry_table <- china_top_panel %>%
  dplyr::filter(china_top == 1L) %>%
  dplyr::group_by(iso3c) %>%
  dplyr::summarise(t0 = min(year, na.rm = TRUE), .groups = "drop")

t0_minus_1_table <- china_top_panel %>%
  dplyr::select(
    iso3c,
    t0_minus_1 = year,
    displaced_partner = top_partner,
    rank_CHN_at_t0_minus_1 = rank_CHN,
    rank_USA_at_t0_minus_1 = rank_USA
  )

incumbent_base <- entry_table %>%
  dplyr::mutate(t0_minus_1 = t0 - 1L) %>%
  dplyr::left_join(t0_minus_1_table, by = c("iso3c", "t0_minus_1"))

message("Computing pre-entry trade share and persistence diagnostics.")
candidate_exporters <- incumbent_base %>%
  dplyr::pull(iso3c)

trade_shares <- trade_data %>%
  dplyr::filter(
    year >= min_year,
    exporter_iso3 %in% candidate_exporters
  ) %>%
  dplyr::group_by(exporter_iso3, year) %>%
  dplyr::mutate(total_exports = sum(exports, na.rm = TRUE)) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(
    export_share = dplyr::if_else(
      total_exports > 0,
      exports / total_exports,
      NA_real_
    )
  ) %>%
  dplyr::select(
    iso3c = exporter_iso3,
    year,
    partner = importer_iso3,
    partner_exports = exports,
    total_exports,
    export_share
  )

t0_minus_1_displaced_shares <- trade_shares %>%
  dplyr::rename(
    displaced_partner = partner,
    displaced_exports_t0_minus_1 = partner_exports,
    total_exports_t0_minus_1 = total_exports,
    displaced_export_share_t0_minus_1 = export_share
  )

t0_minus_1_china_shares <- trade_shares %>%
  dplyr::filter(partner == "CHN") %>%
  dplyr::select(
    iso3c,
    t0_minus_1 = year,
    china_exports_t0_minus_1 = partner_exports,
    china_export_share_t0_minus_1 = export_share
  )

pre_window_years <- incumbent_base %>%
  dplyr::select(iso3c, t0, displaced_partner) %>%
  tidyr::expand_grid(relative_year = -5L:-1L) %>%
  dplyr::mutate(year = t0 + relative_year) %>%
  dplyr::filter(year >= min_year)

pre_window_displaced <- pre_window_years %>%
  dplyr::left_join(
    trade_shares %>%
      dplyr::rename(
        displaced_partner = partner,
        displaced_exports = partner_exports,
        displaced_export_share = export_share
      ) %>%
      dplyr::select(
        iso3c,
        year,
        displaced_partner,
        displaced_exports,
        displaced_export_share
      ),
    by = c("iso3c", "year", "displaced_partner")
  )

pre_window_china <- trade_shares %>%
  dplyr::filter(partner == "CHN") %>%
  dplyr::select(
    iso3c,
    year,
    china_exports = partner_exports,
    china_export_share = export_share
  )

pre_window_stats <- pre_window_displaced %>%
  dplyr::left_join(pre_window_china, by = c("iso3c", "year")) %>%
  dplyr::group_by(iso3c) %>%
  dplyr::summarise(
    pre_window_years_observed = sum(!is.na(displaced_export_share)),
    displaced_partner_mean_share_pre5 = mean(
      displaced_export_share,
      na.rm = TRUE
    ),
    china_mean_share_pre5 = mean(china_export_share, na.rm = TRUE),
    mean_margin_over_china_pre5 = mean(
      displaced_export_share - china_export_share,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

pre_top_partner_persistence <- pre_window_years %>%
  dplyr::left_join(
    china_top_panel %>%
      dplyr::select(iso3c, year, top_partner),
    by = c("iso3c", "year")
  ) %>%
  dplyr::group_by(iso3c, displaced_partner) %>%
  dplyr::summarise(
    top_partner_years_observed_pre5 = sum(!is.na(top_partner)),
    displaced_partner_top_years_pre5 = sum(
      top_partner == displaced_partner,
      na.rm = TRUE
    ),
    modal_top_partner_pre5 = mode_partner(top_partner),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    displaced_partner_modal_top_pre5 = modal_top_partner_pre5 ==
      displaced_partner
  ) %>%
  dplyr::select(
    iso3c,
    top_partner_years_observed_pre5,
    displaced_partner_top_years_pre5,
    modal_top_partner_pre5,
    displaced_partner_modal_top_pre5
  )

incumbent_salience <- incumbent_base %>%
  dplyr::left_join(
    t0_minus_1_displaced_shares,
    by = c("iso3c", "t0_minus_1" = "year", "displaced_partner")
  ) %>%
  dplyr::left_join(
    t0_minus_1_china_shares,
    by = c("iso3c", "t0_minus_1")
  ) %>%
  dplyr::left_join(pre_window_stats, by = "iso3c") %>%
  dplyr::left_join(pre_top_partner_persistence, by = "iso3c") %>%
  dplyr::mutate(
    country_name = country_name(iso3c),
    displaced_partner_name = country_name(displaced_partner),
    displaced_partner_region = country_region(displaced_partner),
    treated_country_region = country_region(iso3c),
    displaced_us = displaced_partner == "USA",
    displaced_g7 = displaced_partner %in% g7_iso3,
    displaced_regional_power = displaced_partner %in% regional_power_iso3,
    displaced_regional_power_same_macroregion = dplyr::case_when(
      !is.na(displaced_partner_region) &
        !is.na(treated_country_region) ~ displaced_regional_power &
        displaced_partner_region == treated_country_region,
      TRUE ~ NA
    ),
    hub_entrepot_incumbent = displaced_partner %in% hub_entrepot_iso3,
    export_share_margin_over_china_t0_minus_1 =
      displaced_export_share_t0_minus_1 - china_export_share_t0_minus_1,
    displacement_salience_warning = dplyr::case_when(
      hub_entrepot_incumbent ~ "hub_or_entrepot_incumbent",
      !is.na(export_share_margin_over_china_t0_minus_1) &
        export_share_margin_over_china_t0_minus_1 < 0.02 ~
        "narrow_export_share_margin",
      !is.na(displaced_partner_top_years_pre5) &
        displaced_partner_top_years_pre5 < 3L ~
        "weak_pre_entry_persistence",
      TRUE ~ "none"
    ),
    regional_power_list_version = regional_power_list_version,
    hub_entrepot_list_version = "observed_hub_entrepot_cases_2026_05_19",
    min_year = min_year,
    min_entry_year = min_entry_year,
    source_targets = "trade_data; unga_data",
    construction_function = "build_china_top_partner_panel",
    creation_date = creation_date,
    creation_timestamp = creation_timestamp
  ) %>%
  dplyr::arrange(t0, iso3c) %>%
  dplyr::select(
    iso3c,
    country_name,
    t0,
    displaced_partner,
    displaced_partner_name,
    displaced_partner_region,
    treated_country_region,
    rank_CHN_at_t0_minus_1,
    rank_USA_at_t0_minus_1,
    displaced_exports_t0_minus_1,
    china_exports_t0_minus_1,
    total_exports_t0_minus_1,
    displaced_export_share_t0_minus_1,
    china_export_share_t0_minus_1,
    export_share_margin_over_china_t0_minus_1,
    pre_window_years_observed,
    displaced_partner_mean_share_pre5,
    china_mean_share_pre5,
    mean_margin_over_china_pre5,
    top_partner_years_observed_pre5,
    displaced_partner_top_years_pre5,
    modal_top_partner_pre5,
    displaced_partner_modal_top_pre5,
    hub_entrepot_incumbent,
    displacement_salience_warning,
    displaced_us,
    displaced_g7,
    displaced_regional_power,
    displaced_regional_power_same_macroregion,
    regional_power_list_version,
    hub_entrepot_list_version,
    min_year,
    min_entry_year,
    source_targets,
    construction_function,
    creation_date,
    creation_timestamp
  )

validation <- list(
  no_missing_t0_minus_1 = !any(is.na(incumbent_salience$displaced_partner)),
  no_china_as_displaced_partner = !any(
    incumbent_salience$displaced_partner == "CHN",
    na.rm = TRUE
  ),
  all_t0_at_or_after_min_entry_year = all(
    incumbent_salience$t0 >= min_entry_year,
    na.rm = TRUE
  ),
  unique_country_rows = nrow(incumbent_salience) ==
    dplyr::n_distinct(incumbent_salience$iso3c),
  displaced_us_consistent = all(
    incumbent_salience$displaced_us ==
      (incumbent_salience$displaced_partner == "USA"),
    na.rm = TRUE
  ),
  displaced_g7_consistent = all(
    incumbent_salience$displaced_g7 ==
      (incumbent_salience$displaced_partner %in% g7_iso3),
    na.rm = TRUE
  ),
  displaced_regional_power_consistent = all(
    incumbent_salience$displaced_regional_power ==
      (incumbent_salience$displaced_partner %in% regional_power_iso3),
    na.rm = TRUE
  ),
  salience_shares_bounded = all(
    is.na(incumbent_salience$displaced_export_share_t0_minus_1) |
      (
        incumbent_salience$displaced_export_share_t0_minus_1 >= 0 &
          incumbent_salience$displaced_export_share_t0_minus_1 <= 1
      )
  ),
  pre_window_does_not_cross_t0 = all(
    incumbent_salience$pre_window_years_observed <= 5L,
    na.rm = TRUE
  )
)

if (!all(unlist(validation))) {
  failing <- names(validation)[!unlist(validation)]
  stop("Logical validation failed: ", paste(failing, collapse = ", "))
}

readr::write_excel_csv(incumbent_salience, output_csv, na = "")

dummy_counts <- list(
  displaced_us = format_count(incumbent_salience, "displaced_us"),
  displaced_g7 = format_count(incumbent_salience, "displaced_g7"),
  displaced_regional_power = format_count(
    incumbent_salience,
    "displaced_regional_power"
  ),
  displaced_regional_power_same_macroregion = format_count(
    incumbent_salience,
    "displaced_regional_power_same_macroregion"
  )
)

warning_counts <- incumbent_salience %>%
  dplyr::count(displacement_salience_warning, name = "n") %>%
  dplyr::mutate(value = displacement_salience_warning) %>%
  dplyr::select(value, n)

hub_cases <- incumbent_salience %>%
  dplyr::filter(hub_entrepot_incumbent) %>%
  dplyr::select(
    iso3c,
    country_name,
    t0,
    displaced_partner,
    displaced_partner_name
  )

partner_counts <- incumbent_salience %>%
  dplyr::count(displaced_partner, displaced_partner_name, name = "n") %>%
  dplyr::arrange(dplyr::desc(n), displaced_partner)

render_count_table <- function(data) {
  paste0(
    apply(
      data,
      1,
      function(row) paste0("- ", row[["value"]], ": ", row[["n"]])
    ),
    collapse = "\n"
  )
}

render_partner_table <- function(data) {
  paste0(
    apply(
      data,
      1,
      function(row) {
        paste0(
          "- ", row[["displaced_partner"]], " (",
          row[["displaced_partner_name"]], "): ", row[["n"]]
        )
      }
    ),
    collapse = "\n"
  )
}

log_lines <- c(
  "# Incumbent salience variable creation log",
  "",
  paste0("- Data de execução: ", creation_date),
  paste0("- Timestamp: ", creation_timestamp),
  "- Script: `scripts/diagnostics/create_incumbent_salience_variables.R`",
  paste0("- CSV: `", output_csv, "`"),
  "",
  "## Fontes",
  "",
  "- Objetos lidos via `targets::tar_read()`: `trade_data`, `unga_data`.",
  paste0(
    "- Painel reconstruído com `build_china_top_partner_panel(trade_data, ",
    "unga_data, min_year = ", min_year, ", min_entry_year = ",
    min_entry_year, ")`."
  ),
  "- O pipeline `targets` não foi executado.",
  "",
  "## Regras de construção",
  "",
  "- `t0`: primeiro ano em que `china_top == 1` para cada país tratado.",
  "- `displaced_partner`: principal destino de exportações no ano `t0 - 1`.",
  "- `displaced_us`: incumbente deslocado igual a `USA`.",
  paste0("- `displaced_g7`: incumbente em `", paste(g7_iso3, collapse = ", "), "`."),
  paste0(
  "- `displaced_regional_power`: incumbente em lista pré-especificada ",
    "`", regional_power_list_version, "`."
  ),
  "- `hub_entrepot_incumbent`: incumbente em lista diagnóstica de hubs/entrepôts observados nesta amostra (`ARE`, `BEL`, `CHE`, `HKG`, `SGP`).",
  "- `export_share_margin_over_china_t0_minus_1`: share do incumbente menos share da China em `t0 - 1`.",
  "- `displaced_partner_top_years_pre5`: número de anos, de `t0 - 5` a `t0 - 1`, em que o incumbente de `t0 - 1` também liderava as exportações.",
  "",
  "## Totais",
  "",
  paste0("- Países tratados: ", nrow(incumbent_salience)),
  paste0("- Primeiro `t0`: ", min(incumbent_salience$t0, na.rm = TRUE)),
  paste0("- Último `t0`: ", max(incumbent_salience$t0, na.rm = TRUE)),
  "",
  "## Contagens das dummies",
  "",
  "### displaced_us",
  render_count_table(dummy_counts$displaced_us),
  "",
  "### displaced_g7",
  render_count_table(dummy_counts$displaced_g7),
  "",
  "### displaced_regional_power",
  render_count_table(dummy_counts$displaced_regional_power),
  "",
  "### displaced_regional_power_same_macroregion",
  render_count_table(dummy_counts$displaced_regional_power_same_macroregion),
  "",
  "## Diagnósticos de saliência do incumbente",
  "",
  "### Avisos de saliência",
  render_count_table(warning_counts),
  "",
  "### Casos com hub/entrepôt como incumbente",
  if (nrow(hub_cases) == 0L) {
    "- Nenhum"
  } else {
    paste0(
      apply(
        hub_cases,
        1,
        function(row) {
          paste0(
            "- ", row[["iso3c"]], " (", row[["country_name"]],
            "), t0 = ", row[["t0"]], ": ",
            row[["displaced_partner"]], " (",
            row[["displaced_partner_name"]], ")"
          )
        }
      ),
      collapse = "\n"
    )
  },
  "",
  paste0(
    "- Mediana da margem incumbente-China em `t0 - 1`: ",
    round(
      stats::median(
        incumbent_salience$export_share_margin_over_china_t0_minus_1,
        na.rm = TRUE
      ),
      4
    )
  ),
  paste0(
    "- Mediana de anos em que o incumbente liderava no pré-período de cinco anos: ",
    round(
      stats::median(
        incumbent_salience$displaced_partner_top_years_pre5,
        na.rm = TRUE
      ),
      2
    )
  ),
  "",
  "## Incumbentes deslocados",
  "",
  render_partner_table(partner_counts),
  "",
  "## Validações lógicas",
  "",
  validation_line(
    "Cada país tratado tem incumbente observado em `t0 - 1`",
    validation$no_missing_t0_minus_1,
    paste0("missing = ", sum(is.na(incumbent_salience$displaced_partner)))
  ),
  validation_line(
    "Nenhum incumbente deslocado é a China",
    validation$no_china_as_displaced_partner,
    paste0(
      "CHN = ",
      sum(incumbent_salience$displaced_partner == "CHN", na.rm = TRUE)
    )
  ),
  validation_line(
    "`t0` respeita `min_entry_year`",
    validation$all_t0_at_or_after_min_entry_year,
    paste0("min(t0) = ", min(incumbent_salience$t0, na.rm = TRUE))
  ),
  validation_line(
    "Há uma linha por país tratado",
    validation$unique_country_rows,
    paste0(
      "linhas = ", nrow(incumbent_salience),
      "; países únicos = ", dplyr::n_distinct(incumbent_salience$iso3c)
    )
  ),
  validation_line(
    "`displaced_us` é consistente com `displaced_partner == USA`",
    validation$displaced_us_consistent,
    ""
  ),
  validation_line(
    "`displaced_g7` é consistente com a lista do G7",
    validation$displaced_g7_consistent,
    ""
  ),
  validation_line(
    "`displaced_regional_power` é consistente com a lista pré-especificada",
    validation$displaced_regional_power_consistent,
    ""
  ),
  validation_line(
    "Shares de exportação em `t0 - 1` estão entre 0 e 1",
    validation$salience_shares_bounded,
    ""
  ),
  validation_line(
    "Janela de persistência usa no máximo os cinco anos pré-entrada",
    validation$pre_window_does_not_cross_t0,
    ""
  ),
  ""
)

writeLines(log_lines, con = output_log, useBytes = TRUE)

message("Wrote: ", output_csv)
message("Wrote: ", output_log)
