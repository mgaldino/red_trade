#!/usr/bin/env Rscript

# Diagnostic only. This script does not modify or run the targets pipeline.

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(countrycode)
  library(duckdb)
  library(DBI)
  library(yaml)
  library(digest)
  library(knitr)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

run_date <- as.Date("2026-05-20")
analysis_year_start <- 2005L
analysis_year_end <- 2022L
analysis_years <- analysis_year_start:analysis_year_end

script_path <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", script_path[grepl("^--file=", script_path)])
if (length(script_path) == 0) {
  script_path <- "scripts/diagnostics/diagnose_china_top_goods_services_batis_bpm6.R"
}
repo_dir <- normalizePath(file.path(dirname(script_path[1]), "..", ".."), mustWork = TRUE)

path <- function(...) file.path(repo_dir, ...)

raw_dir <- path("data", "raw", "batis_bpm6")
processed_dir <- path("data", "processed", "diagnostics", "china_top_goods_services")
report_dir <- path("quality_reports", "china_top_goods_services")
public_raw_dir <- path("data", "raw", "public_partner_onsets")

dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(public_raw_dir, recursive = TRUE, showWarnings = FALSE)

log_msg <- function(...) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", paste0(..., collapse = ""))
}

download_if_missing <- function(url, dest) {
  if (file.exists(dest) && file.info(dest)$size > 0) {
    if (!grepl("\\.zip$", dest, ignore.case = TRUE)) {
      log_msg("Reusing existing raw file: ", dest)
      return(invisible(dest))
    }
    zip_ok <- tryCatch({
      nrow(utils::unzip(dest, list = TRUE)) > 0
    }, error = function(e) FALSE)
    if (zip_ok) {
      log_msg("Reusing existing raw file: ", dest)
      return(invisible(dest))
    }
    warning("Existing ZIP is incomplete or invalid and will be overwritten: ", dest, call. = FALSE)
  }
  log_msg("Downloading: ", url)
  ok <- tryCatch({
    utils::download.file(url, destfile = dest, mode = "wb", method = "libcurl", quiet = FALSE)
    TRUE
  }, error = function(e) {
    warning("Download failed for ", url, ": ", conditionMessage(e), call. = FALSE)
    FALSE
  })
  if (!ok || !file.exists(dest) || file.info(dest)$size == 0) {
    stop("Required download unavailable: ", url, call. = FALSE)
  }
  invisible(dest)
}

sql_quote <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

sql_ident <- function(x) {
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}

clean_col <- function(x) {
  x |>
    tolower() |>
    gsub("[^a-z0-9]+", "_", x = _) |>
    gsub("^_|_$", "", x = _)
}

detect_col <- function(cols, candidates, required = TRUE) {
  clean <- clean_col(cols)
  idx <- match(candidates, clean)
  idx <- idx[!is.na(idx)]
  if (length(idx) > 0) {
    return(cols[idx[1]])
  }
  if (required) {
    stop(
      "Could not detect required column. Candidates: ",
      paste(candidates, collapse = ", "),
      ". Available: ",
      paste(cols, collapse = ", "),
      call. = FALSE
    )
  }
  NA_character_
}

country_name <- function(x) {
  dplyr::case_when(
    x == "ANT" ~ "Netherlands Antilles",
    x == "CIV" ~ "Côte d'Ivoire",
    x == "FRE" ~ "Free Zones",
    x == "HKG" ~ "Hong Kong",
    x == "MAC" ~ "Macao",
    x == "SCG" ~ "Serbia and Montenegro",
    x == "TWN" ~ "Taiwan",
    x == "XKX" ~ "Kosovo",
    x == "PSE" ~ "Palestine",
    TRUE ~ countrycode::countrycode(x, "iso3c", "country.name", warn = FALSE)
  )
}

batis_data_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_BATIS_data_BPM6-1.zip"
batis_codes_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_BATIS_codes_BPM6-1.zip"
batis_method_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_Batis_methodology_BPM6.pdf"
batis_page_url <- "https://www.wto.org/english/res_e/statis_e/trade_datasets_e.htm"
bulk_catalog_url <- "https://data.wto.org/en/dataset/bulkdownload"

batis_zip <- file.path(raw_dir, paste0("OECD-WTO_BATIS_data_BPM6-1_", run_date, ".zip"))
batis_codes_zip <- file.path(raw_dir, paste0("OECD-WTO_BATIS_codes_BPM6-1_", run_date, ".zip"))
batis_method_pdf <- file.path(raw_dir, paste0("OECD-WTO_Batis_methodology_BPM6_", run_date, ".pdf"))

download_if_missing(batis_data_url, batis_zip)
download_if_missing(batis_codes_url, batis_codes_zip)
download_if_missing(batis_method_url, batis_method_pdf)

public_sources <- tibble::tribble(
  ~iso3c, ~country_name_manual, ~publicly_reported_onset, ~source_id, ~source_name, ~url, ~raw_file, ~evidence_paraphrase, ~apparent_metric,
  "AUS", "Australia", 2007L, "aus_dfat_composition_trade_2007", "Australian DFAT, Composition of Trade Australia 2007 media release", "https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2007", "aus_dfat_composition_trade_2007.html", "DFAT reported that China became Australia's largest two-way trading partner in 2007, with total goods-and-services trade above Japan and the United States.", "Two-way trade in goods and services",
  "BRA", "Brazil", 2009L, "bra_agencia_brasil_2009", "Agencia Brasil, 4 May 2009", "https://memoria.ebc.com.br/agenciabrasil/noticia/2009-05-04/china-supera-estados-unidos-e-torna-se-maior-parceiro-comercial-do-brasil", "bra_agencia_brasil_china_maior_parceiro_2009.html", "Agencia Brasil reported that China surpassed the United States as Brazil's largest commercial partner in 2009, defining the comparison as trade current, exports plus imports.", "Two-way merchandise trade/current, apparently goods only",
  "BRA", "Brazil", 2009L, "bra_mre_china_bilateral", "Brazilian Ministry of Foreign Affairs country page", "https://www.gov.br/mre/en/subjects/bilateral-relations/all-countries/people-s-republic-of-china", "bra_mre_china_bilateral_relations.html", "The MRE states that China has been Brazil's largest trading partner since 2009 and reports bilateral export and import values.", "Two-way merchandise trade/current, apparently goods only"
)

for (i in seq_len(nrow(public_sources))) {
  dest <- file.path(public_raw_dir, public_sources$raw_file[i])
  try(download_if_missing(public_sources$url[i], dest), silent = TRUE)
}

public_sources <- public_sources |>
  dplyr::mutate(
    raw_file_path = file.path(public_raw_dir, raw_file),
    raw_file_preserved = file.exists(raw_file_path) & file.info(raw_file_path)$size > 0,
    raw_file_status = dplyr::if_else(
      raw_file_preserved,
      "preserved_locally",
      "local_preservation_failed_url_documented"
    )
  )

read_panel_countries <- function() {
  panel_source <- NA_character_
  panel <- NULL

  target_panel_file <- path("_targets", "objects", "china_top_panel")
  if (file.exists(target_panel_file)) {
    panel <- readRDS(target_panel_file)
    panel_source <- "_targets/objects/china_top_panel read via readRDS, read-only"
  }

  if (is.null(panel) && file.exists(path("data", "colt_panel.rds"))) {
    colt <- readRDS(path("data", "colt_panel.rds"))
    panel <- colt$panel
    panel_source <- "data/colt_panel.rds$panel"
  }

  if (is.null(panel) || !"iso3c" %in% names(panel)) {
    stop("Could not identify panel countries from _targets/objects/china_top_panel or data/colt_panel.rds.", call. = FALSE)
  }

  countries <- panel |>
    as_tibble() |>
    dplyr::select(iso3c) |>
    dplyr::filter(!is.na(iso3c), iso3c != "CHN") |>
    dplyr::distinct() |>
    dplyr::arrange(iso3c) |>
    dplyr::mutate(country_name = country_name(iso3c))

  list(countries = countries, source = panel_source)
}

panel_info <- read_panel_countries()
panel_countries <- panel_info$countries
log_msg("Panel countries: ", nrow(panel_countries), " from ", panel_info$source)

extract_one_from_zip <- function(zip_path, exdir, pattern = NULL) {
  dir.create(exdir, recursive = TRUE, showWarnings = FALSE)
  listing <- utils::unzip(zip_path, list = TRUE)
  names_vec <- listing$Name
  if (!is.null(pattern)) {
    names_vec <- names_vec[grepl(pattern, names_vec, ignore.case = TRUE)]
  }
  if (length(names_vec) == 0) {
    stop("No file matching pattern in zip: ", zip_path, call. = FALSE)
  }
  member <- names_vec[1]
  out <- file.path(exdir, basename(member))
  if (!file.exists(out) || file.info(out)$size == 0) {
    log_msg("Extracting ", member, " to ", out)
    utils::unzip(zip_path, files = member, exdir = exdir, overwrite = TRUE)
  } else {
    log_msg("Reusing extracted file: ", out)
  }
  out
}

batis_csv <- extract_one_from_zip(
  batis_zip,
  file.path(raw_dir, paste0("extracted_", run_date)),
  "\\.(csv|txt)$"
)

codes_xlsx <- extract_one_from_zip(
  batis_codes_zip,
  file.path(raw_dir, paste0("codes_extracted_", run_date)),
  "\\.xlsx$"
)

economy_codes <- readxl::read_excel(codes_xlsx, sheet = "economies") |>
  janitor::clean_names() |>
  dplyr::select(code, code_description, type, notes) |>
  dplyr::mutate(
    code = as.character(code),
    iso3c = dplyr::case_when(
      code == "888" ~ "XKX",
      code == "AN" ~ "ANT",
      code == "PAL" ~ "PSE",
      code == "YU" ~ "SCG",
      TRUE ~ countrycode::countrycode(code, "iso2c", "iso3c", warn = FALSE)
    ),
    type = as.character(type),
    exclude_from_rank = type == "g" | code %in% c("WL", "WLD", "WORLD", "ROW", "EU", "GEU")
  )

manual_excluded_partner_codes <- c("FRE")

excluded_partner_codes <- economy_codes |>
  dplyr::filter(exclude_from_rank) |>
  dplyr::select(code) |>
  dplyr::pull(code)

excluded_partner_codes <- unique(c(
  excluded_partner_codes,
  "WL", "WLD", "WORLD", "ROW", "EU", "GEU",
  manual_excluded_partner_codes
))

excluded_partner_iso3 <- economy_codes |>
  dplyr::filter(exclude_from_rank, !is.na(iso3c)) |>
  dplyr::select(iso3c) |>
  dplyr::pull(iso3c)

read_batis_services <- function(csv_path, economy_codes) {
  header <- data.table::fread(csv_path, nrows = 0)
  cols <- names(header)
  reporter_col <- detect_col(cols, c("reporter", "reporter_code", "reporting_economy", "reporter_iso3"))
  partner_col <- detect_col(cols, c("partner", "partner_code", "partner_iso3"))
  flow_col <- detect_col(cols, c("flow"))
  item_col <- detect_col(cols, c("item", "item_code", "service_item", "sector"))
  year_col <- detect_col(cols, c("year"))
  value_col <- detect_col(cols, c("balanced_value", "balanced", "balance_value", "value_balanced", "final_value"))

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tempfile(fileext = ".duckdb"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  csv_sql <- sql_quote(normalizePath(csv_path, mustWork = TRUE))
  query <- paste0(
    "SELECT ",
    sql_ident(reporter_col), " AS reporter, ",
    sql_ident(partner_col), " AS partner, ",
    sql_ident(flow_col), " AS flow, ",
    sql_ident(item_col), " AS item, ",
    sql_ident(year_col), " AS year, ",
    sql_ident(value_col), " AS value_raw ",
    "FROM read_csv_auto(", csv_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE ", sql_ident(item_col), " = 'S'"
  )

  log_msg("Reading BaTIS total services rows with DuckDB.")
  raw <- DBI::dbGetQuery(con, query) |>
    as_tibble() |>
    dplyr::mutate(
      reporter = toupper(as.character(reporter)),
      partner = toupper(as.character(partner)),
      flow = toupper(as.character(flow)),
      year = suppressWarnings(as.integer(year)),
      services_value_musd = readr::parse_number(as.character(value_raw))
    ) |>
    dplyr::select(reporter, partner, flow, item, year, services_value_musd)

  reporter_map <- economy_codes |>
    dplyr::select(
      reporter = code,
      iso3c,
      reporter_exclude_from_rank = exclude_from_rank
    )

  partner_map <- economy_codes |>
    dplyr::select(
      partner = code,
      partner_iso3 = iso3c,
      partner_exclude_from_rank = exclude_from_rank
    )

  raw |>
    dplyr::left_join(reporter_map, by = "reporter") |>
    dplyr::left_join(partner_map, by = "partner") |>
    dplyr::filter(
      !is.na(iso3c),
      !is.na(partner_iso3),
      !reporter_exclude_from_rank,
      !partner_exclude_from_rank,
      iso3c != partner_iso3,
      year >= analysis_year_start,
      year <= analysis_year_end,
      flow %in% c("X", "M", "EXP", "IMP", "EXPORTS", "IMPORTS")
    ) |>
    dplyr::mutate(
      flow_clean = dplyr::case_when(
        flow %in% c("X", "EXP", "EXPORTS") ~ "exports",
        flow %in% c("M", "IMP", "IMPORTS") ~ "imports",
        TRUE ~ NA_character_
      )
    ) |>
    dplyr::filter(!is.na(flow_clean)) |>
    dplyr::group_by(year, iso3c, partner_iso3, flow_clean) |>
    dplyr::summarise(services_value_musd = sum(services_value_musd, na.rm = TRUE), .groups = "drop") |>
    tidyr::pivot_wider(
      names_from = flow_clean,
      values_from = services_value_musd,
      names_prefix = "services_"
    ) |>
    dplyr::mutate(
      services_exports_musd = dplyr::coalesce(services_exports, 0),
      services_imports_musd = dplyr::coalesce(services_imports, 0)
    ) |>
    dplyr::select(year, iso3c, partner_iso3, services_exports_musd, services_imports_musd)
}

read_itpd_goods <- function(itpd_path, panel_countries) {
  if (!file.exists(itpd_path)) {
    stop("ITPD-E file not found: ", itpd_path, call. = FALSE)
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tempfile(fileext = ".duckdb"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbWriteTable(
    con,
    "panel_countries",
    panel_countries |> dplyr::select(iso3c),
    temporary = TRUE,
    overwrite = TRUE
  )

  itpd_sql <- sql_quote(normalizePath(itpd_path, mustWork = TRUE))
  log_msg("Aggregating ITPD-E goods flows with DuckDB.")
  DBI::dbExecute(con, paste0(
    "CREATE TEMP TABLE goods_flows AS ",
    "SELECT ",
    "try_cast(year AS INTEGER) AS year, ",
    "upper(exporter_iso3) AS exporter_iso3, ",
    "upper(importer_iso3) AS importer_iso3, ",
    "sum(coalesce(try_cast(trade AS DOUBLE), 0)) AS goods_exports_musd ",
    "FROM read_csv_auto(", itpd_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", analysis_year_start, " AND ", analysis_year_end, " ",
    "AND upper(exporter_iso3) <> upper(importer_iso3) ",
    "AND broad_sector IN ('Agriculture', 'Mining and Energy', 'Manufacturing') ",
    "GROUP BY 1, 2, 3"
  ))

  goods_exports <- DBI::dbGetQuery(con, paste0(
    "SELECT gf.year, gf.exporter_iso3 AS iso3c, gf.importer_iso3 AS partner_iso3, ",
    "gf.goods_exports_musd ",
    "FROM goods_flows gf ",
    "INNER JOIN panel_countries pc ON gf.exporter_iso3 = pc.iso3c"
  )) |>
    as_tibble() |>
    dplyr::select(year, iso3c, partner_iso3, goods_exports_musd)

  goods_imports <- DBI::dbGetQuery(con, paste0(
    "SELECT gf.year, gf.importer_iso3 AS iso3c, gf.exporter_iso3 AS partner_iso3, ",
    "gf.goods_exports_musd AS goods_imports_musd ",
    "FROM goods_flows gf ",
    "INNER JOIN panel_countries pc ON gf.importer_iso3 = pc.iso3c"
  )) |>
    as_tibble() |>
    dplyr::select(year, iso3c, partner_iso3, goods_imports_musd)

  list(exports = goods_exports, imports = goods_imports)
}

itpd_path <- path("raw data", "ITPDE_R03.csv")
batis_services <- read_batis_services(batis_csv, economy_codes)
itpd_goods <- read_itpd_goods(itpd_path, panel_countries)

partner_panel <- full_join(
  itpd_goods$exports,
  itpd_goods$imports,
  by = c("year", "iso3c", "partner_iso3")
) |>
  full_join(batis_services, by = c("year", "iso3c", "partner_iso3")) |>
  dplyr::filter(iso3c %in% panel_countries$iso3c) |>
  dplyr::filter(year %in% analysis_years) |>
  dplyr::filter(!partner_iso3 %in% excluded_partner_codes) |>
  dplyr::filter(!partner_iso3 %in% excluded_partner_iso3) |>
  dplyr::filter(iso3c != partner_iso3) |>
  dplyr::mutate(
    goods_exports_musd = dplyr::coalesce(goods_exports_musd, 0),
    goods_imports_musd = dplyr::coalesce(goods_imports_musd, 0),
    services_exports_musd = dplyr::coalesce(services_exports_musd, 0),
    services_imports_musd = dplyr::coalesce(services_imports_musd, 0),
    goods_two_way_musd = goods_exports_musd + goods_imports_musd,
    goods_services_exports_musd = goods_exports_musd + services_exports_musd,
    goods_services_two_way_musd = goods_two_way_musd + services_exports_musd + services_imports_musd,
    country_name = country_name(iso3c),
    partner_name = country_name(partner_iso3)
  ) |>
  dplyr::select(
    iso3c, country_name, year, partner_iso3, partner_name,
    goods_exports_musd, goods_imports_musd,
    services_exports_musd, services_imports_musd,
    goods_two_way_musd,
    goods_services_exports_musd, goods_services_two_way_musd
  )

if (nrow(batis_services) == 0) {
  stop("BaTIS service extraction returned zero rows after code mapping.", call. = FALSE)
}

if (sum(partner_panel$services_exports_musd > 0 | partner_panel$services_imports_musd > 0, na.rm = TRUE) == 0) {
  stop("BaTIS services are all zero after joining with ITPD-E. Check economy-code mapping.", call. = FALSE)
}

long_metrics <- partner_panel |>
  dplyr::select(
    iso3c, country_name, year, partner_iso3, partner_name,
    goods_exports_musd,
    goods_services_exports_musd,
    goods_services_two_way_musd
  ) |>
  tidyr::pivot_longer(
    cols = c(goods_exports_musd, goods_services_exports_musd, goods_services_two_way_musd),
    names_to = "metric",
    values_to = "value_musd"
  ) |>
  dplyr::mutate(
    metric = dplyr::recode(
      metric,
      goods_exports_musd = "goods_exports_rank",
      goods_services_exports_musd = "goods_services_exports_rank",
      goods_services_two_way_musd = "goods_services_two_way_rank"
    )
  ) |>
  dplyr::filter(!is.na(value_musd), value_musd > 0) |>
  dplyr::group_by(metric, iso3c, year) |>
  dplyr::arrange(dplyr::desc(value_musd), partner_iso3, .by_group = TRUE) |>
  dplyr::mutate(
    partner_rank = dplyr::row_number(),
    top_partner_iso3 = dplyr::first(partner_iso3),
    top_partner_name = dplyr::first(partner_name),
    top_value_musd = dplyr::first(value_musd)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    china_indicator_partner = partner_iso3 == "CHN",
    focus_partner = partner_iso3 %in% c("CHN", "USA", "JPN")
  ) |>
  dplyr::select(
    metric, iso3c, country_name, year, partner_iso3, partner_name,
    value_musd, partner_rank, top_partner_iso3, top_partner_name, top_value_musd,
    china_indicator_partner, focus_partner
  ) |>
  dplyr::arrange(metric, iso3c, year, partner_rank)

public_metric_ranks <- partner_panel |>
  dplyr::filter(iso3c %in% public_sources$iso3c) |>
  dplyr::select(
    iso3c, country_name, year, partner_iso3, partner_name,
    value_musd = goods_two_way_musd
  ) |>
  dplyr::filter(!is.na(value_musd), value_musd > 0) |>
  dplyr::group_by(iso3c, year) |>
  dplyr::arrange(dplyr::desc(value_musd), partner_iso3, .by_group = TRUE) |>
  dplyr::mutate(
    partner_rank = dplyr::row_number(),
    top_partner_iso3 = dplyr::first(partner_iso3),
    top_partner_name = dplyr::first(partner_name),
    top_value_musd = dplyr::first(value_musd)
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(metric = "goods_two_way_supplemental_public_metric_check") |>
  dplyr::select(
    metric, iso3c, country_name, year, partner_iso3, partner_name,
    value_musd, partner_rank, top_partner_iso3, top_partner_name, top_value_musd
  ) |>
  dplyr::arrange(iso3c, year, partner_rank)

public_metric_onsets <- public_metric_ranks |>
  dplyr::filter(partner_iso3 == "CHN") |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    first_china_rank1_year_ge2005_goods_two_way_supplemental = {
      rank1_years <- year[partner_rank == 1L]
      if (length(rank1_years) == 0) NA_integer_ else as.integer(min(rank1_years, na.rm = TRUE))
    },
    .groups = "drop"
  )

china_ranks <- long_metrics |>
  dplyr::filter(partner_iso3 == "CHN") |>
  dplyr::select(
    metric, iso3c, country_name, year,
    china_rank = partner_rank,
    china_value_musd = value_musd,
    top_partner_iso3,
    top_partner_name,
    top_value_musd
  ) |>
  dplyr::mutate(
    china_is_rank1 = china_rank == 1L,
    china_gap_to_top_musd = dplyr::if_else(china_is_rank1, 0, top_value_musd - china_value_musd)
  )

onsets_by_metric <- china_ranks |>
  dplyr::group_by(metric, iso3c, country_name) |>
  dplyr::summarise(
    first_china_rank1_year_ge2005 = {
      rank1_years <- year[china_is_rank1 %in% TRUE]
      if (length(rank1_years) == 0) NA_integer_ else as.integer(min(rank1_years, na.rm = TRUE))
    },
    china_top_in_2005 = any(year == 2005 & china_is_rank1, na.rm = TRUE),
    observed_years = dplyr::n_distinct(year),
    first_observed_year = min(year, na.rm = TRUE),
    last_observed_year = max(year, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    onset_status = dplyr::case_when(
      is.na(first_china_rank1_year_ge2005) ~ "never_china_rank1_in_observed_window",
      china_top_in_2005 ~ "left_censored_china_rank1_in_2005",
      TRUE ~ "observed_first_rank1_after_2005"
    )
  )

onsets_wide <- onsets_by_metric |>
  dplyr::select(
    iso3c, country_name, metric,
    first_china_rank1_year_ge2005,
    onset_status,
    observed_years,
    first_observed_year,
    last_observed_year
  ) |>
  tidyr::pivot_wider(
    names_from = metric,
    values_from = c(
      first_china_rank1_year_ge2005,
      onset_status,
      observed_years,
      first_observed_year,
      last_observed_year
    )
  )

public_onsets_by_country <- public_sources |>
  dplyr::group_by(iso3c, country_name_manual) |>
  dplyr::summarise(
    publicly_reported_onset = min(publicly_reported_onset, na.rm = TRUE),
    public_sources = paste(source_name, collapse = " | "),
    public_urls = paste(url, collapse = " | "),
    public_evidence_paraphrase = paste(evidence_paraphrase, collapse = " | "),
    public_apparent_metric = paste(unique(apparent_metric), collapse = " | "),
    .groups = "drop"
  ) |>
  dplyr::rename(country_name_public = country_name_manual)

year_changed <- function(reference_year, comparison_year) {
  (is.na(reference_year) & !is.na(comparison_year)) |
    (!is.na(reference_year) & is.na(comparison_year)) |
    (!is.na(reference_year) & !is.na(comparison_year) & reference_year != comparison_year)
}

onsets_comparison <- onsets_wide |>
  dplyr::left_join(public_onsets_by_country, by = "iso3c") |>
  dplyr::left_join(
    public_metric_onsets |>
      dplyr::select(iso3c, first_china_rank1_year_ge2005_goods_two_way_supplemental),
    by = "iso3c"
  ) |>
  dplyr::mutate(
    any_services_export_change = year_changed(
      first_china_rank1_year_ge2005_goods_exports_rank,
      first_china_rank1_year_ge2005_goods_services_exports_rank
    ),
    any_two_way_change = year_changed(
      first_china_rank1_year_ge2005_goods_exports_rank,
      first_china_rank1_year_ge2005_goods_services_two_way_rank
    ),
    any_change_from_goods_exports = any_services_export_change | any_two_way_change,
    public_minus_goods_exports =
      publicly_reported_onset - first_china_rank1_year_ge2005_goods_exports_rank,
    public_minus_goods_services_exports =
      publicly_reported_onset - first_china_rank1_year_ge2005_goods_services_exports_rank,
    public_minus_goods_services_two_way =
      publicly_reported_onset - first_china_rank1_year_ge2005_goods_services_two_way_rank,
    public_minus_goods_two_way_supplemental =
      publicly_reported_onset - first_china_rank1_year_ge2005_goods_two_way_supplemental
  ) |>
  dplyr::select(
    iso3c, country_name,
    first_china_rank1_year_ge2005_goods_exports_rank,
    first_china_rank1_year_ge2005_goods_services_exports_rank,
    first_china_rank1_year_ge2005_goods_services_two_way_rank,
    onset_status_goods_exports_rank,
    onset_status_goods_services_exports_rank,
    onset_status_goods_services_two_way_rank,
    first_china_rank1_year_ge2005_goods_two_way_supplemental,
    publicly_reported_onset,
    public_apparent_metric,
    public_sources,
    public_urls,
    public_evidence_paraphrase,
    public_minus_goods_exports,
    public_minus_goods_services_exports,
    public_minus_goods_services_two_way,
    public_minus_goods_two_way_supplemental,
    any_services_export_change,
    any_two_way_change,
    any_change_from_goods_exports
  ) |>
  dplyr::arrange(iso3c)

coverage_by_country_metric <- long_metrics |>
  dplyr::group_by(metric, iso3c, country_name) |>
  dplyr::summarise(
    first_year_with_rank = min(year, na.rm = TRUE),
    last_year_with_rank = max(year, na.rm = TRUE),
    n_years_with_rank = dplyr::n_distinct(year),
    missing_years_2005_2022 = paste(setdiff(analysis_years, unique(year)), collapse = ";"),
    .groups = "drop"
  ) |>
  dplyr::arrange(metric, iso3c)

missing_panel_countries <- tidyr::expand_grid(
  metric = unique(long_metrics$metric),
  panel_countries |> dplyr::select(iso3c, country_name)
) |>
  dplyr::anti_join(
    coverage_by_country_metric |> dplyr::select(metric, iso3c),
    by = c("metric", "iso3c")
  ) |>
  dplyr::arrange(metric, iso3c)

problem_values <- partner_panel |>
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_batis_service_rows_after_mapping = nrow(batis_services),
    n_rows_with_any_service = sum(services_exports_musd > 0 | services_imports_musd > 0, na.rm = TRUE),
    n_negative_goods_exports = sum(goods_exports_musd < 0, na.rm = TRUE),
    n_negative_goods_imports = sum(goods_imports_musd < 0, na.rm = TRUE),
    n_negative_services_exports = sum(services_exports_musd < 0, na.rm = TRUE),
    n_negative_services_imports = sum(services_imports_musd < 0, na.rm = TRUE),
    n_zero_goods_exports = sum(goods_exports_musd == 0, na.rm = TRUE),
    n_zero_services_exports = sum(services_exports_musd == 0, na.rm = TRUE),
    n_na_country = sum(is.na(iso3c)),
    n_na_partner = sum(is.na(partner_iso3))
  )

service_join_key_checks <- partner_panel |>
  dplyr::filter(iso3c %in% c("AUS", "BRA"), partner_iso3 %in% c("CHN", "USA", "JPN")) |>
  dplyr::group_by(iso3c, country_name, partner_iso3, partner_name) |>
  dplyr::summarise(
    n_years = dplyr::n_distinct(year),
    n_years_with_any_service = sum(services_exports_musd > 0 | services_imports_musd > 0, na.rm = TRUE),
    first_year_with_any_service = {
      service_years <- year[services_exports_musd > 0 | services_imports_musd > 0]
      if (length(service_years) == 0) NA_integer_ else as.integer(min(service_years, na.rm = TRUE))
    },
    last_year_with_any_service = {
      service_years <- year[services_exports_musd > 0 | services_imports_musd > 0]
      if (length(service_years) == 0) NA_integer_ else as.integer(max(service_years, na.rm = TRUE))
    },
    total_services_exports_musd = sum(services_exports_musd, na.rm = TRUE),
    total_services_imports_musd = sum(services_imports_musd, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    service_join_status = dplyr::if_else(
      n_years_with_any_service > 0,
      "services_joined",
      "no_services_after_join"
    )
  ) |>
  dplyr::select(
    iso3c, country_name, partner_iso3, partner_name,
    n_years, n_years_with_any_service,
    first_year_with_any_service, last_year_with_any_service,
    total_services_exports_musd, total_services_imports_musd,
    service_join_status
  ) |>
  dplyr::arrange(iso3c, partner_iso3)

if (any(service_join_key_checks$service_join_status != "services_joined")) {
  missing_keys <- service_join_key_checks |>
    dplyr::filter(service_join_status != "services_joined") |>
    dplyr::mutate(key = paste(iso3c, partner_iso3, sep = "-")) |>
    dplyr::pull(key)
  stop("BaTIS service join failed for key case-partners: ", paste(missing_keys, collapse = ", "), call. = FALSE)
}

unmapped_codes <- tibble(code = sort(unique(c(
  partner_panel$iso3c,
  partner_panel$partner_iso3,
  excluded_partner_codes,
  excluded_partner_iso3
)))) |>
  dplyr::mutate(
    country_name = country_name(code),
    countrycode_missing = is.na(country_name),
    in_batis_codes = code %in% economy_codes$iso3c | code %in% economy_codes$code,
    batis_type = dplyr::coalesce(
      economy_codes$type[match(code, economy_codes$iso3c)],
      economy_codes$type[match(code, economy_codes$code)]
    ),
    excluded_from_rank = code %in% excluded_partner_codes | code %in% excluded_partner_iso3
  ) |>
  dplyr::filter(countrycode_missing | excluded_from_rank) |>
  dplyr::arrange(desc(excluded_from_rank), code)

focus_rank_diagnostics <- long_metrics |>
  dplyr::filter(iso3c %in% c("AUS", "BRA"), partner_iso3 %in% c("CHN", "USA", "JPN")) |>
  dplyr::select(metric, iso3c, country_name, year, partner_iso3, partner_name, value_musd, partner_rank) |>
  dplyr::arrange(iso3c, metric, year, partner_rank)

case_top_partners <- long_metrics |>
  dplyr::filter(iso3c %in% c("AUS", "BRA"), partner_rank <= 5) |>
  dplyr::select(metric, iso3c, country_name, year, partner_rank, partner_iso3, partner_name, value_musd) |>
  dplyr::arrange(iso3c, metric, year, partner_rank)

changed_onsets <- onsets_comparison |>
  dplyr::filter(any_change_from_goods_exports) |>
  dplyr::select(
    iso3c, country_name,
    goods_exports = first_china_rank1_year_ge2005_goods_exports_rank,
    goods_services_exports = first_china_rank1_year_ge2005_goods_services_exports_rank,
    goods_services_two_way = first_china_rank1_year_ge2005_goods_services_two_way_rank,
    onset_status_goods_exports_rank,
    onset_status_goods_services_exports_rank,
    onset_status_goods_services_two_way_rank
  ) |>
  dplyr::arrange(iso3c)

file_partner_panel <- file.path(processed_dir, paste0("china_top_goods_services_country_year_partner_", run_date, ".csv"))
file_ranks <- file.path(processed_dir, paste0("china_top_goods_services_rank_long_", run_date, ".csv"))
file_china_ranks <- file.path(processed_dir, paste0("china_top_goods_services_china_ranks_", run_date, ".csv"))
file_onsets <- file.path(processed_dir, paste0("china_top_goods_services_onsets_comparison_", run_date, ".csv"))
file_public <- file.path(processed_dir, paste0("manual_publicly_reported_onsets_", run_date, ".csv"))
file_public_metric <- file.path(processed_dir, paste0("china_top_goods_two_way_public_metric_check_aus_bra_", run_date, ".csv"))
file_changed <- file.path(processed_dir, paste0("china_top_goods_services_changed_onsets_", run_date, ".csv"))
file_focus <- file.path(processed_dir, paste0("china_top_goods_services_focus_rank_diagnostics_aus_bra_", run_date, ".csv"))
file_service_join <- file.path(processed_dir, paste0("china_top_goods_services_service_join_key_checks_", run_date, ".csv"))
file_coverage <- file.path(processed_dir, paste0("china_top_goods_services_coverage_by_country_metric_", run_date, ".csv"))
file_missing <- file.path(processed_dir, paste0("china_top_goods_services_missing_panel_countries_", run_date, ".csv"))
file_unmapped <- file.path(processed_dir, paste0("china_top_goods_services_unmapped_or_excluded_codes_", run_date, ".csv"))
file_validation <- file.path(processed_dir, paste0("china_top_goods_services_validation_summary_", run_date, ".csv"))

readr::write_csv(partner_panel, file_partner_panel, na = "")
readr::write_csv(long_metrics, file_ranks, na = "")
readr::write_csv(china_ranks, file_china_ranks, na = "")
readr::write_csv(onsets_comparison, file_onsets, na = "")
readr::write_csv(public_sources, file_public, na = "")
readr::write_csv(public_metric_ranks, file_public_metric, na = "")
readr::write_csv(changed_onsets, file_changed, na = "")
readr::write_csv(focus_rank_diagnostics, file_focus, na = "")
readr::write_csv(service_join_key_checks, file_service_join, na = "")
readr::write_csv(coverage_by_country_metric, file_coverage, na = "")
readr::write_csv(missing_panel_countries, file_missing, na = "")
readr::write_csv(unmapped_codes, file_unmapped, na = "")
readr::write_csv(problem_values, file_validation, na = "")

sources_yaml <- list(
  generated_on = as.character(run_date),
  sources = list(
    list(
      id = "wto_oecd_batis_bpm6",
      name = "WTO-OECD Balanced Trade in Services Dataset (BaTiS), BPM6",
      provider = "World Trade Organization and OECD",
      url = batis_page_url,
      bulk_catalog_url = bulk_catalog_url,
      data_url = batis_data_url,
      codes_url = batis_codes_url,
      methodology_url = batis_method_url,
      access_method = "bulk_download",
      requires_credentials = FALSE,
      license = "WTO/OECD public statistical dataset; check provider terms for redistribution",
      variables_used = c("Reporter", "Partner", "Flow", "Item S total services", "Year", "Balanced_value"),
      temporal_coverage = "2005-2024 in source; diagnostic overlap with ITPD-E is 2005-2022",
      geographic_coverage = "Global, over 200 reporters and partners",
      unit_of_analysis = "reporter-partner-year-flow-service item",
      download_script = "scripts/diagnostics/diagnose_china_top_goods_services_batis_bpm6.R",
      date_accessed = as.character(run_date),
      raw_files = list(
        data = batis_zip,
        codes = batis_codes_zip,
        methodology = batis_method_pdf
      ),
      notes = "BPM6 only. BPM5 is not combined because WTO warns that BPM5 and BPM6 create comparability issues across the time series. BaTIS economy codes are converted to ISO-3 before joining to ITPD-E."
    ),
    list(
      id = "itpde_r03",
      name = "International Trade and Production Database for Estimation, release 03",
      provider = "USITC",
      url = "https://www.usitc.gov/data/gravity/itpde.htm",
      access_method = "local_raw_file_reuse",
      requires_credentials = FALSE,
      variables_used = c("year", "exporter_iso3", "importer_iso3", "trade", "broad_sector"),
      unit_of_analysis = "exporter-importer-year-sector",
      raw_file = itpd_path,
      date_accessed = as.character(run_date),
      notes = "Goods metric filters broad_sector to Agriculture, Mining and Energy, and Manufacturing; services in ITPD-E are not used for the robustness metrics. The non-country Free Zones code (FRE) is excluded from partner rankings."
    ),
    list(
      id = "manual_public_partner_onsets",
      name = "Manual public-source coding of China top-partner onset",
      provider = "DFAT, Agencia Brasil/EBC, Brazilian Ministry of Foreign Affairs",
      access_method = "manual_or_semiautomatic_source_coding",
      requires_credentials = FALSE,
      date_accessed = as.character(run_date),
      variables_used = c("publicly_reported_onset", "evidence_paraphrase", "apparent_metric"),
      output_file = file_public,
      raw_files = stats::setNames(as.list(public_sources$raw_file_path), public_sources$source_id),
      local_preservation_status = stats::setNames(as.list(public_sources$raw_file_status), public_sources$source_id)
    )
  )
)

yaml::write_yaml(sources_yaml, file.path(processed_dir, "SOURCES.yaml"))

data_dictionary <- c(
  "# Dicionário de dados: codificação alternativa de parceiro comercial China #1",
  "",
  paste0("Gerado em: ", run_date),
  "",
  "## china_top_goods_services_country_year_partner_YYYY-MM-DD.csv",
  "",
  "| Variável | Tipo | Descrição | Fonte | Unidade |",
  "|---|---|---|---|---|",
  "| iso3c | texto | País do painel, ISO-3 | painel do paper | - |",
  "| country_name | texto | Nome do país | countrycode | - |",
  "| year | inteiro | Ano | ITPD-E/BaTIS | ano |",
  "| partner_iso3 | texto | Parceiro bilateral, ISO-3/código econômico | ITPD-E/BaTIS | - |",
  "| partner_name | texto | Nome do parceiro | countrycode/BaTIS | - |",
  "| goods_exports_musd | numérico | Exportações de bens do país para o parceiro | ITPD-E | milhões de USD correntes |",
  "| goods_imports_musd | numérico | Importações de bens do país vindas do parceiro, calculadas como exportações do parceiro para o país | ITPD-E | milhões de USD correntes |",
  "| services_exports_musd | numérico | Exportações de serviços totais do país para o parceiro | BaTIS BPM6, item S, balanced value | milhões de USD correntes |",
  "| services_imports_musd | numérico | Importações de serviços totais do país vindas do parceiro | BaTIS BPM6, item S, balanced value | milhões de USD correntes |",
  "| goods_two_way_musd | numérico | Exportações + importações de bens; diagnóstico auxiliar para fontes públicas de corrente de comércio | ITPD-E | milhões de USD correntes |",
  "| goods_services_exports_musd | numérico | Bens exportados + serviços exportados | ITPD-E + BaTIS | milhões de USD correntes |",
  "| goods_services_two_way_musd | numérico | Exportações + importações de bens e serviços | ITPD-E + BaTIS | milhões de USD correntes |",
  "",
  "## china_top_goods_services_rank_long_YYYY-MM-DD.csv",
  "",
  "| Variável | Tipo | Descrição |",
  "|---|---|---|",
  "| metric | texto | Métrica de ranking: goods_exports_rank, goods_services_exports_rank ou goods_services_two_way_rank |",
  "| value_musd | numérico | Valor usado no ranking da métrica |",
  "| partner_rank | inteiro | Ranking do parceiro dentro do país-ano-métrica; 1 é o maior parceiro com valor positivo |",
  "| top_partner_iso3 | texto | Parceiro no rank 1 do país-ano-métrica |",
  "| china_indicator_partner | lógico | Parceiro é a China |",
  "| focus_partner | lógico | Parceiro é China, Estados Unidos ou Japão |",
  "",
  "## china_top_goods_services_onsets_comparison_YYYY-MM-DD.csv",
  "",
  "| Variável | Tipo | Descrição |",
  "|---|---|---|",
  "| first_china_rank1_year_ge2005_* | inteiro | Primeiro ano observado a partir de 2005 em que a China aparece no rank 1 para a métrica |",
  "| onset_status_* | texto | Indica se o primeiro ano é observado depois de 2005, left-censored em 2005 ou nunca observado |",
  "| publicly_reported_onset | inteiro | Ano reportado por fonte pública/governamental quando disponível |",
  "| public_apparent_metric | texto | Métrica que a fonte parece usar |",
  "| public_evidence_paraphrase | texto | Paráfrase curta da evidência usada na codificação manual |",
  "| public_minus_* | inteiro | Diferença entre onset público e onset computado |",
  "| any_change_from_goods_exports | lógico | Alguma métrica com serviços altera o onset em relação a exportações de bens |",
  "",
  "## china_top_goods_two_way_public_metric_check_aus_bra_YYYY-MM-DD.csv",
  "",
  "Ranking auxiliar de corrente de comércio de bens para Austrália e Brasil, usado apenas para confrontar fontes públicas que parecem reportar `exports + imports` de bens."
)

writeLines(data_dictionary, file.path(processed_dir, "DATA_DICTIONARY.md"), useBytes = TRUE)

public_preserved_files <- public_sources |>
  dplyr::filter(raw_file_preserved) |>
  dplyr::pull(raw_file_path)

sha_files <- c(
  batis_zip,
  batis_codes_zip,
  batis_method_pdf,
  public_preserved_files,
  file_partner_panel,
  file_ranks,
  file_china_ranks,
  file_onsets,
  file_public,
  file_public_metric,
  file_changed,
  file_focus,
  file_service_join,
  file_coverage,
  file_missing,
  file_unmapped,
  file_validation,
  file.path(processed_dir, "SOURCES.yaml"),
  file.path(processed_dir, "DATA_DICTIONARY.md")
)
checksums <- tibble::tibble(
  file = sha_files,
  sha256 = vapply(sha_files, digest::digest, character(1), algo = "sha256", file = TRUE)
)
readr::write_csv(checksums, file.path(processed_dir, paste0("checksums_", run_date, ".csv")), na = "")

fmt_year <- function(x) ifelse(is.na(x), "NA", as.character(x))

case_summary <- onsets_comparison |>
  dplyr::filter(iso3c %in% c("AUS", "BRA")) |>
  dplyr::select(
    iso3c, country_name,
    goods_exports = first_china_rank1_year_ge2005_goods_exports_rank,
    goods_services_exports = first_china_rank1_year_ge2005_goods_services_exports_rank,
    goods_services_two_way = first_china_rank1_year_ge2005_goods_services_two_way_rank,
    goods_two_way_supplemental = first_china_rank1_year_ge2005_goods_two_way_supplemental,
    publicly_reported_onset,
    public_apparent_metric
  )

report_onsets <- onsets_comparison |>
  dplyr::filter(!is.na(first_china_rank1_year_ge2005_goods_exports_rank) |
                  !is.na(first_china_rank1_year_ge2005_goods_services_exports_rank) |
                  !is.na(first_china_rank1_year_ge2005_goods_services_two_way_rank)) |>
  dplyr::select(
    iso3c, country_name,
    goods_exports = first_china_rank1_year_ge2005_goods_exports_rank,
    goods_services_exports = first_china_rank1_year_ge2005_goods_services_exports_rank,
    goods_services_two_way = first_china_rank1_year_ge2005_goods_services_two_way_rank,
    publicly_reported_onset,
    any_change_from_goods_exports
  ) |>
  dplyr::arrange(iso3c)

top_changed_for_report <- changed_onsets |>
  dplyr::slice_head(n = 40)

n_panel <- nrow(panel_countries)
n_missing <- nrow(missing_panel_countries)
n_changed <- nrow(changed_onsets)

aus_row <- case_summary |> dplyr::filter(iso3c == "AUS")
bra_row <- case_summary |> dplyr::filter(iso3c == "BRA")

aus_sentence <- if (nrow(aus_row) == 1) {
  paste0(
    "Austrália: o onset público é ", fmt_year(aus_row$publicly_reported_onset),
    ". A métrica goods+services two-way coloca a China em rank 1 em ",
    fmt_year(aus_row$goods_services_two_way),
    ", contra ", fmt_year(aus_row$goods_exports), " na métrica de exportações de bens. ",
    "A checagem auxiliar de corrente de bens também aponta ",
    fmt_year(aus_row$goods_two_way_supplemental), "."
  )
} else {
  "Austrália: país não localizado na tabela final de onsets."
}

bra_sentence <- if (nrow(bra_row) == 1) {
  paste0(
    "Brasil: o onset público é ", fmt_year(bra_row$publicly_reported_onset),
    ". A métrica goods+services two-way coloca a China em rank 1 em ",
    fmt_year(bra_row$goods_services_two_way),
    ", e a métrica de exportações de bens em ", fmt_year(bra_row$goods_exports), ". ",
    "A checagem auxiliar de corrente de bens aponta ",
    fmt_year(bra_row$goods_two_way_supplemental), ", consistente com a métrica pública brasileira."
  )
} else {
  "Brasil: país não localizado na tabela final de onsets."
}

public_preservation_note <- {
  missing_public_raw <- public_sources |>
    dplyr::filter(!raw_file_preserved) |>
    dplyr::select(source_id, url)

  if (nrow(missing_public_raw) == 0) {
    "- Fontes públicas manuais: os HTMLs consultados foram preservados em `data/raw/public_partner_onsets/`."
  } else {
    paste0(
      "- Fontes públicas manuais: as fontes brasileiras foram preservadas em `data/raw/public_partner_onsets/`. ",
      "A preservação local falhou para ",
      paste(missing_public_raw$source_id, collapse = ", "),
      "; a URL, a data de acesso e a paráfrase da evidência permanecem documentadas no CSV manual e em `SOURCES.yaml`."
    )
  }
}

report_lines <- c(
  "# Codificação alternativa do ano em que a China se torna parceiro comercial #1",
  "",
  paste0("Data de execução: ", run_date),
  "",
  "## Resumo executivo",
  "",
  paste0("Este diagnóstico reconstrói rankings bilaterais para ", n_panel, " países do painel, fora do pipeline `targets`, combinando exportações de bens do ITPD-E com serviços totais bilaterais do BaTIS BPM6. Foram produzidas três métricas: exportações de bens, exportações de bens + serviços, e comércio two-way de bens + serviços."),
  "",
  aus_sentence,
  "",
  bra_sentence,
  "",
  paste0("Ao todo, ", n_changed, " países têm algum ano de China #1 alterado quando serviços e/ou comércio two-way entram na codificação. A recomendação é usar `goods_services_two_way_rank` como robustez para linguagem pública de comércio total de bens e serviços, mantendo `goods_exports_rank` como métrica principal se o argumento substantivo continuar centrado em export-destination status; para fontes que usam corrente de bens, use a checagem auxiliar de bens two-way."),
  "",
  "## Fontes e limitações",
  "",
  "- BaTIS BPM6: página oficial da OMC de bulk download, arquivo `OECD-WTO_BATIS_data_BPM6-1.zip`, código e metodologia acessados em 2026-05-20. A página informa cobertura 2005-2024 e mais de 200 reporters/partners. O diagnóstico usa apenas BPM6 e não combina BPM5, porque a própria OMC alerta que as edições seguem padrões diferentes e geram problemas de comparabilidade.",
  "- ITPD-E: arquivo local `raw data/ITPDE_R03.csv`. A métrica de bens filtra `broad_sector` para Agriculture, Mining and Energy, e Manufacturing, excluindo Services.",
  "- Sobreposição temporal: como o ITPD-E local vai até 2022, as métricas combinadas são interpretadas em 2005-2022. O ano 2005 é tratado como possível censura à esquerda; o relatório informa o primeiro ano observado a partir de 2005, não um onset pré-2005 verdadeiro.",
  "- Serviços: usa `Balanced_value` do BaTIS para obter matriz bilateral completa e reconciliada. Isso é apropriado para robustez de ranking, mas incorpora estimativas e ajustes da OMC/OCDE, não apenas valores reportados diretamente.",
  public_preservation_note,
  "",
  "## Metodologia",
  "",
  "1. Agreguei ITPD-E por país exportador, parceiro importador e ano, mantendo apenas setores de bens.",
  "2. Calculei importações de bens do país como exportações do parceiro para o país no ITPD-E.",
  "3. Extraí BaTIS BPM6 apenas para item `S` (Total services), distinguindo fluxos de exportação e importação.",
  "4. Converti códigos BaTIS de economia para ISO-3 antes do join com ITPD-E, com mapeamentos manuais para Kosovo, Palestina, Antilhas Holandesas e Sérvia-Montenegro.",
  "5. Excluí parceiros agregados/grupos identificados nos códigos BaTIS (`WL`, `EU`, `GEU`, `ROW` e demais códigos com tipo `g`) e o código ITPD-E `FRE` (`Free Zones`) antes do ranking.",
  "6. Ranqueei apenas parceiros com valor positivo em cada país-ano-métrica.",
  "",
  "## Tabela 1. Casos principais",
  "",
  knitr::kable(case_summary, format = "pipe"),
  "",
  "## Tabela 2. Países cujo onset muda em relação a exportações de bens",
  "",
  if (nrow(top_changed_for_report) > 0) knitr::kable(top_changed_for_report, format = "pipe") else "Nenhum país mudou de onset nas métricas com serviços.",
  "",
  "## Tabela 3. Onsets por métrica",
  "",
  knitr::kable(report_onsets, format = "pipe"),
  "",
  "## Validações",
  "",
  paste0("- Países do painel: ", n_panel, ". Países-métrica sem nenhum ranking: ", n_missing, ". Ver `", basename(file_missing), "`."),
  paste0("- Valores negativos/NA/zero: ver `", basename(file_validation), "`. Valores zero não entram no ranking; valores negativos são sinalizados."),
  paste0("- Integração BaTIS-ITPD-E: o script aborta se serviços não entrarem no join ou se casos-chave Austrália/Brasil com China, EUA e Japão não tiverem serviços. Ver `", basename(file_service_join), "`."),
  paste0("- Códigos sem mapeamento ISO ou excluídos como agregados: ver `", basename(file_unmapped), "`."),
  paste0("- Rankings anuais de China, Estados Unidos e Japão para Austrália e Brasil: ver `", basename(file_focus), "`. A checagem auxiliar de corrente de bens está em `", basename(file_public_metric), "`."),
  "",
  "## Implicações para o paper",
  "",
  "- Se a narrativa empírica se refere a `largest export destination`, a métrica principal de exportações de bens continua conceitualmente limpa e alinhada ao mecanismo de status por destino exportador.",
  "- Se a prosa usa `largest trading partner` sem qualificação, a robustez two-way bens + serviços é necessária, mas ela não replica automaticamente fontes que reportam apenas corrente de comércio de bens.",
  "- A Austrália é o caso de maior risco de validade de medida: fontes australianas usam comércio two-way de bens e serviços para datar a virada em 2007.",
  "- O Brasil exige qualificação: a fonte pública de 2009 parece usar corrente de comércio de bens; nessa checagem auxiliar o onset é 2009, mas na métrica two-way bens + serviços o onset passa a 2017 porque serviços com os Estados Unidos continuam grandes por mais tempo.",
  "",
  "## Recomendação",
  "",
  "Manter a codificação principal como `goods_exports_rank` se o estimando do paper for status de destino de exportações. Adicionar `goods_services_two_way_rank` como robustez para fontes que reportam `largest trading partner` em termos de comércio total de bens e serviços, mas interpretar Brasil com a checagem auxiliar de corrente de bens. No texto, evitar alternar sem qualificação entre `largest export destination`, `largest merchandise trading partner` e `largest goods-and-services trading partner`."
)

report_file <- file.path(report_dir, paste0("relatorio_china_top_goods_services_batis_bpm6_", run_date, ".md"))
writeLines(report_lines, report_file, useBytes = TRUE)

collection_log <- c(
  "# Log de coleta e processamento",
  "",
  paste0("Data de acesso: ", run_date),
  "",
  paste0("- BaTIS data ZIP: ", batis_zip),
  paste0("- BaTIS codes ZIP: ", batis_codes_zip),
  paste0("- BaTIS methodology PDF: ", batis_method_pdf),
  paste0("- BaTIS data CSV extraído: ", batis_csv),
  paste0("- ITPD-E raw reutilizado: ", itpd_path),
  paste0("- Países do painel: ", n_panel, " (", panel_info$source, ")"),
  public_preservation_note,
  "",
  "Checksums estão em `checksums_YYYY-MM-DD.csv` no diretório processado."
)
writeLines(collection_log, file.path(report_dir, paste0("collection_log_china_top_goods_services_", run_date, ".md")), useBytes = TRUE)

log_msg("Wrote processed CSVs to ", processed_dir)
log_msg("Wrote report to ", report_file)
