#!/usr/bin/env Rscript

# Diagnostic only. This script tests whether BaTIS BPM5 and BPM6 produce stable
# top-1/top-2 partner rankings in their overlap years. It does not modify or run
# the targets pipeline.

options(scipen = 999)

suppressPackageStartupMessages({
  library(DBI)
  library(countrycode)
  library(data.table)
  library(digest)
  library(dplyr)
  library(duckdb)
  library(ggplot2)
  library(knitr)
  library(purrr)
  library(readr)
  library(readxl)
  library(rmarkdown)
  library(scales)
  library(tibble)
  library(tidyr)
  library(yaml)
})

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))

run_date <- as.Date("2026-05-20")
overlap_start <- 2005L
overlap_end <- 2012L
overlap_years <- overlap_start:overlap_end

processed_dir <- file.path(
  "data", "processed", "diagnostics", "batis_bpm5_bpm6_overlap"
)
report_dir <- file.path("quality_reports", "batis_bpm5_bpm6_overlap")
figure_dir <- file.path(report_dir, "figures")
raw_bpm5_dir <- file.path("data", "raw", "batis_bpm5")
raw_bpm6_dir <- file.path("data", "raw", "batis_bpm6")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(raw_bpm5_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(raw_bpm6_dir, recursive = TRUE, showWarnings = FALSE)

log_msg <- function(...) {
  message(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", paste0(..., collapse = ""))
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x
}

download_if_missing <- function(url, dest) {
  if (file.exists(dest) && file.info(dest)$size > 0) {
    if (!grepl("\\.zip$", dest, ignore.case = TRUE)) {
      log_msg("Reusing existing raw file: ", dest)
      return(invisible(dest))
    }
    zip_ok <- tryCatch({
      nrow(utils::unzip(dest, list = TRUE)) > 0L
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

extract_one_from_zip <- function(zip_path, exdir, pattern) {
  dir.create(exdir, recursive = TRUE, showWarnings = FALSE)
  listing <- utils::unzip(zip_path, list = TRUE)
  member <- listing$Name[grepl(pattern, listing$Name, ignore.case = TRUE)][1]
  if (is.na(member)) {
    stop("No file matching pattern in ZIP: ", zip_path, call. = FALSE)
  }
  out <- file.path(exdir, basename(member))
  if (!file.exists(out) || file.info(out)$size == 0) {
    log_msg("Extracting ", member, " to ", out)
    utils::unzip(zip_path, files = member, exdir = exdir, overwrite = TRUE)
  } else {
    log_msg("Reusing extracted file: ", out)
  }
  out
}

file_metadata <- function(paths, labels = basename(paths)) {
  tibble::tibble(label = labels, path = paths) |>
    dplyr::mutate(
      exists = file.exists(path),
      size_bytes = dplyr::if_else(exists, as.numeric(file.info(path)$size), NA_real_),
      sha256 = purrr::map_chr(
        path,
        ~ if (file.exists(.x)) digest::digest(file = .x, algo = "sha256") else NA_character_
      )
    )
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
  if (length(idx) > 0L) {
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

sql_quote <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

sql_ident <- function(x) {
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}

country_name_from_iso3 <- function(x) {
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

map_economy_codes <- function(codes, descriptions = NULL, types = NULL) {
  code <- toupper(as.character(codes))
  type <- if (is.null(types)) NA_character_ else as.character(types)
  description <- if (is.null(descriptions)) NA_character_ else as.character(descriptions)

  tibble::tibble(
    code = code,
    code_description = description,
    type = type,
    iso3c = dplyr::case_when(
      code == "888" ~ "XKX",
      code == "AN" ~ "ANT",
      code == "PAL" ~ "PSE",
      code == "YU" ~ "SCG",
      TRUE ~ countrycode::countrycode(code, "iso2c", "iso3c", warn = FALSE)
    ),
    exclude_from_rank = is.na(iso3c) |
      (!is.na(type) & type == "g") |
      code %in% c("WL", "WLD", "WORLD", "ROW", "EU", "GEU", "FRE")
  )
}

read_panel_countries <- function() {
  target_panel_file <- file.path("_targets", "objects", "china_top_panel")
  panel <- NULL
  panel_source <- NA_character_

  if (file.exists(target_panel_file)) {
    panel <- readRDS(target_panel_file)
    panel_source <- "_targets/objects/china_top_panel read via readRDS, read-only"
  }

  if (is.null(panel) && file.exists(file.path("data", "colt_panel.rds"))) {
    colt <- readRDS(file.path("data", "colt_panel.rds"))
    panel <- colt$panel
    panel_source <- "data/colt_panel.rds$panel"
  }

  if (is.null(panel) || !"iso3c" %in% names(panel)) {
    stop("Could not identify panel countries from target object or data/colt_panel.rds.", call. = FALSE)
  }

  countries <- panel |>
    tibble::as_tibble() |>
    dplyr::select(iso3c, dplyr::any_of("country_name")) |>
    dplyr::filter(!is.na(iso3c), iso3c != "CHN") |>
    dplyr::distinct(iso3c, .keep_all = TRUE)

  if (!"country_name" %in% names(countries)) {
    countries$country_name <- NA_character_
  }

  countries |>
    dplyr::mutate(
      country_name = dplyr::coalesce(country_name, country_name_from_iso3(iso3c)),
      panel_source = panel_source
    ) |>
    dplyr::arrange(iso3c)
}

read_bpm5_codes <- function(path) {
  economy <- readxl::read_excel(path, sheet = "economies") |>
    tibble::as_tibble()

  code_col <- detect_col(names(economy), c("country_code", "code"))
  desc_col <- detect_col(names(economy), c("country_description", "code_description", "description"))

  map_economy_codes(
    codes = economy[[code_col]],
    descriptions = economy[[desc_col]]
  )
}

read_bpm6_codes <- function(path) {
  economy <- readxl::read_excel(path, sheet = "economies") |>
    tibble::as_tibble()

  code_col <- detect_col(names(economy), c("code", "country_code"))
  desc_col <- detect_col(names(economy), c("code_description", "country_description", "description"))
  type_col <- detect_col(names(economy), c("type"), required = FALSE)

  map_economy_codes(
    codes = economy[[code_col]],
    descriptions = economy[[desc_col]],
    types = if (!is.na(type_col)) economy[[type_col]] else NULL
  )
}

read_batis_total_services <- function(csv_path, code_map, total_item_code,
                                      source_name, start_year, end_year) {
  header <- data.table::fread(csv_path, nrows = 0)
  cols <- names(header)
  reporter_col <- detect_col(cols, c("reporter", "reporter_code", "reporting_economy", "reporter_iso3"))
  partner_col <- detect_col(cols, c("partner", "partner_code", "partner_iso3"))
  flow_col <- detect_col(cols, c("flow"))
  item_col <- detect_col(cols, c("item_code", "item", "service_item", "sector"))
  year_col <- detect_col(cols, c("year"))
  value_col <- detect_col(cols, c("balanced_value", "balanced", "balance_value", "value_balanced", "final_value"))

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tempfile(fileext = ".duckdb"))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  csv_sql <- sql_quote(normalizePath(csv_path, mustWork = TRUE))
  item_sql <- sql_quote(total_item_code)
  query <- paste0(
    "SELECT ",
    sql_ident(reporter_col), " AS reporter, ",
    sql_ident(partner_col), " AS partner, ",
    sql_ident(flow_col), " AS flow, ",
    sql_ident(item_col), " AS item, ",
    sql_ident(year_col), " AS year, ",
    sql_ident(value_col), " AS value_raw ",
    "FROM read_csv_auto(", csv_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE ", sql_ident(item_col), " = ", item_sql, " ",
    "AND try_cast(", sql_ident(year_col), " AS INTEGER) BETWEEN ", start_year, " AND ", end_year
  )

  log_msg("Reading ", source_name, " total-services rows with DuckDB.")
  raw <- DBI::dbGetQuery(con, query) |>
    tibble::as_tibble() |>
    dplyr::mutate(
      reporter = toupper(as.character(reporter)),
      partner = toupper(as.character(partner)),
      flow = toupper(as.character(flow)),
      year = suppressWarnings(as.integer(year)),
      value_raw_text = as.character(value_raw),
      value_raw_missing = is.na(value_raw_text) | trimws(value_raw_text) == "",
      services_value_musd = readr::parse_number(value_raw_text),
      parsed_missing_from_nonmissing = !value_raw_missing & is.na(services_value_musd),
      source = source_name
    ) |>
    dplyr::select(
      source, reporter, partner, flow, item, year, value_raw_text,
      value_raw_missing, services_value_musd, parsed_missing_from_nonmissing
    )

  reporter_map <- code_map |>
    dplyr::select(
      reporter = code,
      iso3c,
      reporter_exclude_from_rank = exclude_from_rank
    )

  partner_map <- code_map |>
    dplyr::select(
      partner = code,
      partner_iso3 = iso3c,
      partner_exclude_from_rank = exclude_from_rank
    )

  mapped <- raw |>
    dplyr::left_join(reporter_map, by = "reporter") |>
    dplyr::left_join(partner_map, by = "partner") |>
    dplyr::mutate(
      valid_flow = flow %in% c("X", "M", "EXP", "IMP", "EXPORTS", "IMPORTS"),
      flow_clean = dplyr::case_when(
        flow %in% c("X", "EXP", "EXPORTS") ~ "exports",
        flow %in% c("M", "IMP", "IMPORTS") ~ "imports",
        TRUE ~ NA_character_
      )
    )

  valid_rows <- mapped |>
    dplyr::filter(
      !is.na(iso3c),
      !is.na(partner_iso3),
      !reporter_exclude_from_rank,
      !partner_exclude_from_rank,
      iso3c != partner_iso3,
      year >= start_year,
      year <= end_year,
      valid_flow,
      !is.na(flow_clean)
    )

  audit <- mapped |>
    dplyr::summarise(
      source = source_name,
      item_code = total_item_code,
      raw_rows_total_item_overlap = dplyr::n(),
      distinct_raw_reporters = dplyr::n_distinct(reporter),
      distinct_raw_partners = dplyr::n_distinct(partner),
      raw_missing_value_rows = sum(value_raw_missing, na.rm = TRUE),
      raw_parse_fail_nonmissing_rows = sum(parsed_missing_from_nonmissing, na.rm = TRUE),
      raw_negative_value_rows = sum(services_value_musd < 0, na.rm = TRUE),
      raw_zero_value_rows = sum(services_value_musd == 0, na.rm = TRUE),
      unmapped_reporter_rows = sum(is.na(iso3c), na.rm = TRUE),
      unmapped_partner_rows = sum(is.na(partner_iso3), na.rm = TRUE),
      excluded_reporter_rows = sum(reporter_exclude_from_rank %in% TRUE, na.rm = TRUE),
      excluded_partner_rows = sum(partner_exclude_from_rank %in% TRUE, na.rm = TRUE),
      self_flow_rows = sum(iso3c == partner_iso3, na.rm = TRUE),
      invalid_flow_rows = sum(!valid_flow, na.rm = TRUE),
      valid_rank_input_rows = nrow(valid_rows),
      valid_missing_value_rows = sum(valid_rows$value_raw_missing, na.rm = TRUE),
      valid_parse_fail_nonmissing_rows = sum(valid_rows$parsed_missing_from_nonmissing, na.rm = TRUE),
      valid_negative_value_rows = sum(valid_rows$services_value_musd < 0, na.rm = TRUE),
      valid_zero_value_rows = sum(valid_rows$services_value_musd == 0, na.rm = TRUE)
    )

  flows <- valid_rows |>
    dplyr::group_by(source, year, iso3c, partner_iso3, flow_clean) |>
    dplyr::summarise(
      services_value_musd = sum(services_value_musd, na.rm = TRUE),
      .groups = "drop"
    ) |>
    tidyr::pivot_wider(
      names_from = flow_clean,
      values_from = services_value_musd,
      names_prefix = "services_"
    ) |>
    dplyr::mutate(
      services_exports_musd = dplyr::coalesce(services_exports, 0),
      services_imports_musd = dplyr::coalesce(services_imports, 0)
    ) |>
    dplyr::select(source, year, iso3c, partner_iso3, services_exports_musd, services_imports_musd)

  list(data = flows, audit = audit)
}

read_itpd_goods_overlap <- function(itpd_path, panel_countries, start_year, end_year) {
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
  log_msg("Aggregating ITPD-E goods flows in overlap years.")

  goods_audit <- DBI::dbGetQuery(con, paste0(
    "SELECT ",
    "'ITPD-E goods' AS source, ",
    "count(*) AS raw_goods_rows_overlap, ",
    "sum(CASE WHEN trade IS NULL OR trim(trade) = '' THEN 1 ELSE 0 END) AS raw_missing_trade_rows, ",
    "sum(CASE WHEN trade IS NOT NULL AND trim(trade) <> '' AND try_cast(trade AS DOUBLE) IS NULL THEN 1 ELSE 0 END) AS raw_parse_fail_nonmissing_trade_rows, ",
    "sum(CASE WHEN try_cast(trade AS DOUBLE) < 0 THEN 1 ELSE 0 END) AS raw_negative_trade_rows, ",
    "sum(CASE WHEN try_cast(trade AS DOUBLE) = 0 THEN 1 ELSE 0 END) AS raw_zero_trade_rows ",
    "FROM read_csv_auto(", itpd_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
    "AND upper(exporter_iso3) <> upper(importer_iso3) ",
    "AND broad_sector IN ('Agriculture', 'Mining and Energy', 'Manufacturing')"
  )) |>
    tibble::as_tibble()

  DBI::dbExecute(con, paste0(
    "CREATE TEMP TABLE goods_flows AS ",
    "SELECT ",
    "try_cast(year AS INTEGER) AS year, ",
    "upper(exporter_iso3) AS exporter_iso3, ",
    "upper(importer_iso3) AS importer_iso3, ",
    "sum(coalesce(try_cast(trade AS DOUBLE), 0)) AS goods_exports_musd ",
    "FROM read_csv_auto(", itpd_sql, ", header = true, all_varchar = true, ignore_errors = true) ",
    "WHERE try_cast(year AS INTEGER) BETWEEN ", start_year, " AND ", end_year, " ",
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
    tibble::as_tibble() |>
    dplyr::select(year, iso3c, partner_iso3, goods_exports_musd)

  goods_imports <- DBI::dbGetQuery(con, paste0(
    "SELECT gf.year, gf.importer_iso3 AS iso3c, gf.exporter_iso3 AS partner_iso3, ",
    "gf.goods_exports_musd AS goods_imports_musd ",
    "FROM goods_flows gf ",
    "INNER JOIN panel_countries pc ON gf.importer_iso3 = pc.iso3c"
  )) |>
    tibble::as_tibble() |>
    dplyr::select(year, iso3c, partner_iso3, goods_imports_musd)

  flows <- dplyr::full_join(
    goods_exports,
    goods_imports,
    by = c("year", "iso3c", "partner_iso3")
  ) |>
    dplyr::mutate(
      goods_exports_musd = dplyr::coalesce(goods_exports_musd, 0),
      goods_imports_musd = dplyr::coalesce(goods_imports_musd, 0)
    ) |>
    dplyr::select(year, iso3c, partner_iso3, goods_exports_musd, goods_imports_musd)

  list(data = flows, audit = goods_audit)
}

build_partner_metric_panel <- function(services, goods, panel_countries) {
  dplyr::full_join(
    goods,
    services,
    by = c("year", "iso3c", "partner_iso3")
  ) |>
    dplyr::filter(iso3c %in% panel_countries$iso3c) |>
    dplyr::filter(iso3c != "CHN") |>
    dplyr::filter(iso3c != partner_iso3) |>
    dplyr::mutate(
      source = dplyr::coalesce(source, unique(services$source)[1]),
      goods_exports_musd = dplyr::coalesce(goods_exports_musd, 0),
      goods_imports_musd = dplyr::coalesce(goods_imports_musd, 0),
      services_exports_musd = dplyr::coalesce(services_exports_musd, 0),
      services_imports_musd = dplyr::coalesce(services_imports_musd, 0),
      services_two_way_musd = services_exports_musd + services_imports_musd,
      goods_services_exports_musd = goods_exports_musd + services_exports_musd,
      goods_services_two_way_musd = goods_exports_musd + goods_imports_musd +
        services_exports_musd + services_imports_musd
    ) |>
    dplyr::select(
      source, iso3c, year, partner_iso3,
      services_exports_musd,
      services_two_way_musd,
      goods_services_exports_musd,
      goods_services_two_way_musd
    )
}

rank_top_two <- function(metric_panel) {
  metric_panel |>
    tidyr::pivot_longer(
      cols = c(
        services_exports_musd,
        services_two_way_musd,
        goods_services_exports_musd,
        goods_services_two_way_musd
      ),
      names_to = "metric",
      values_to = "value_musd"
    ) |>
    dplyr::mutate(
      metric = dplyr::recode(
        metric,
        services_exports_musd = "services_exports_only",
        services_two_way_musd = "services_two_way_only",
        goods_services_exports_musd = "goods_services_exports_combined",
        goods_services_two_way_musd = "goods_services_two_way_combined"
      ),
      metric_label = dplyr::recode(
        metric,
        services_exports_only = "Serviços: exportações",
        services_two_way_only = "Serviços: exportações + importações",
        goods_services_exports_combined = "Bens + serviços: exportações",
        goods_services_two_way_combined = "Bens + serviços: exportações + importações"
      )
    ) |>
    dplyr::filter(!is.na(value_musd), value_musd > 0) |>
    dplyr::group_by(source, metric, metric_label, iso3c, year) |>
    dplyr::arrange(dplyr::desc(value_musd), partner_iso3, .by_group = TRUE) |>
    dplyr::mutate(partner_rank = dplyr::row_number()) |>
    dplyr::filter(partner_rank <= 2L) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      country_name = country_name_from_iso3(iso3c),
      partner_name = country_name_from_iso3(partner_iso3)
    ) |>
    dplyr::select(
      source, metric, metric_label, iso3c, country_name, year,
      partner_rank, partner_iso3, partner_name, value_musd
    ) |>
    dplyr::arrange(source, metric, iso3c, year, partner_rank)
}

summarise_top_two <- function(top_two_long) {
  top_two_long |>
    dplyr::group_by(source, metric, metric_label, iso3c, country_name, year) |>
    dplyr::summarise(
      top1_partner_iso3 = partner_iso3[partner_rank == 1L][1] %||% NA_character_,
      top1_partner_name = partner_name[partner_rank == 1L][1] %||% NA_character_,
      top1_value_musd = value_musd[partner_rank == 1L][1] %||% NA_real_,
      top2_partner_iso3 = partner_iso3[partner_rank == 2L][1] %||% NA_character_,
      top2_partner_name = partner_name[partner_rank == 2L][1] %||% NA_character_,
      top2_value_musd = value_musd[partner_rank == 2L][1] %||% NA_real_,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      top1_top2_margin_musd = top1_value_musd - top2_value_musd,
      top1_top2_margin_share = dplyr::if_else(
        top1_value_musd > 0,
        top1_top2_margin_musd / top1_value_musd,
        NA_real_
      )
    )
}

same_or_both_na <- function(x, y) {
  (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
}

same_top2_set <- function(a1, a2, b1, b2) {
  purrr::pmap_lgl(
    list(a1, a2, b1, b2),
    function(x1, x2, y1, y2) {
      if (any(is.na(c(x1, x2, y1, y2)))) {
        return(FALSE)
      }
      identical(sort(c(x1, x2)), sort(c(y1, y2)))
    }
  )
}

stopifnot(
  identical(same_or_both_na(c("A", NA), c("A", NA)), c(TRUE, TRUE)),
  identical(same_top2_set("A", "B", "B", "A"), TRUE),
  identical(same_top2_set("A", "B", "A", "C"), FALSE)
)

compare_sources <- function(source_summary) {
  bpm5 <- source_summary |>
    dplyr::filter(source == "BPM5") |>
    dplyr::rename_with(~ paste0(.x, "_bpm5"), -c(metric, metric_label, iso3c, country_name, year))

  bpm6 <- source_summary |>
    dplyr::filter(source == "BPM6") |>
    dplyr::rename_with(~ paste0(.x, "_bpm6"), -c(metric, metric_label, iso3c, country_name, year))

  dplyr::full_join(
    bpm5,
    bpm6,
    by = c("metric", "metric_label", "iso3c", "country_name", "year")
  ) |>
    dplyr::mutate(
      present_bpm5 = !is.na(source_bpm5),
      present_bpm6 = !is.na(source_bpm6),
      comparison_sample = dplyr::case_when(
        present_bpm5 & present_bpm6 ~ "common_bpm5_bpm6",
        present_bpm5 & !present_bpm6 ~ "bpm5_only",
        !present_bpm5 & present_bpm6 ~ "bpm6_only",
        TRUE ~ "absent_both"
      ),
      both_sources_present = comparison_sample == "common_bpm5_bpm6",
      top1_same = dplyr::if_else(
        both_sources_present,
        same_or_both_na(top1_partner_iso3_bpm5, top1_partner_iso3_bpm6),
        NA
      ),
      top2_ordered_same = dplyr::if_else(
        both_sources_present,
        top1_same & same_or_both_na(top2_partner_iso3_bpm5, top2_partner_iso3_bpm6),
        NA
      ),
      top2_unordered_same = dplyr::if_else(
        both_sources_present,
        same_top2_set(
          top1_partner_iso3_bpm5,
          top2_partner_iso3_bpm5,
          top1_partner_iso3_bpm6,
          top2_partner_iso3_bpm6
        ),
        NA
      ),
      china_top1_bpm5 = top1_partner_iso3_bpm5 == "CHN",
      china_top1_bpm6 = top1_partner_iso3_bpm6 == "CHN",
      china_top1_status_same = dplyr::if_else(
        both_sources_present,
        same_or_both_na(china_top1_bpm5, china_top1_bpm6),
        NA
      ),
      china_in_top2_bpm5 = top1_partner_iso3_bpm5 == "CHN" | top2_partner_iso3_bpm5 == "CHN",
      china_in_top2_bpm6 = top1_partner_iso3_bpm6 == "CHN" | top2_partner_iso3_bpm6 == "CHN",
      china_in_top2_status_same = dplyr::if_else(
        both_sources_present,
        same_or_both_na(china_in_top2_bpm5, china_in_top2_bpm6),
        NA
      ),
      china_in_top2_any_source = (china_in_top2_bpm5 %in% TRUE) | (china_in_top2_bpm6 %in% TRUE),
      china_top1_any_source = (china_top1_bpm5 %in% TRUE) | (china_top1_bpm6 %in% TRUE),
      top1_disagreement_involves_china =
        (top1_same %in% FALSE) &
          (top1_partner_iso3_bpm5 == "CHN" | top1_partner_iso3_bpm6 == "CHN"),
      top2_disagreement_involves_china =
        (top2_unordered_same %in% FALSE) & china_in_top2_any_source,
      min_top1_top2_margin_share = dplyr::if_else(
        both_sources_present &
          (!is.na(top1_top2_margin_share_bpm5) | !is.na(top1_top2_margin_share_bpm6)),
        pmin(top1_top2_margin_share_bpm5, top1_top2_margin_share_bpm6, na.rm = TRUE),
        NA_real_
      ),
      close_top1_top2_case = min_top1_top2_margin_share <= 0.10
    ) |>
    dplyr::arrange(metric, iso3c, year)
}

metric_summary <- function(comparison) {
  comparison |>
    dplyr::group_by(metric, metric_label) |>
    dplyr::summarise(
      country_years_any_source = dplyr::n(),
      country_years_compared = sum(both_sources_present, na.rm = TRUE),
      bpm5_only_country_years = sum(comparison_sample == "bpm5_only", na.rm = TRUE),
      bpm6_only_country_years = sum(comparison_sample == "bpm6_only", na.rm = TRUE),
      top1_agreement_n = sum(top1_same, na.rm = TRUE),
      top1_agreement_rate = mean(top1_same, na.rm = TRUE),
      top2_ordered_agreement_n = sum(top2_ordered_same, na.rm = TRUE),
      top2_ordered_agreement_rate = mean(top2_ordered_same, na.rm = TRUE),
      top2_unordered_agreement_n = sum(top2_unordered_same, na.rm = TRUE),
      top2_unordered_agreement_rate = mean(top2_unordered_same, na.rm = TRUE),
      china_top1_status_agreement_n = sum(china_top1_status_same, na.rm = TRUE),
      china_top1_status_agreement_rate = mean(china_top1_status_same, na.rm = TRUE),
      china_in_top2_status_agreement_n = sum(china_in_top2_status_same, na.rm = TRUE),
      china_in_top2_status_agreement_rate = mean(china_in_top2_status_same, na.rm = TRUE),
      china_in_top2_any_source_n = sum(china_in_top2_any_source, na.rm = TRUE),
      china_top1_status_disagreements_n = sum(!china_top1_status_same, na.rm = TRUE),
      top1_disagreements_involving_china_n = sum(top1_disagreement_involves_china, na.rm = TRUE),
      top2_disagreements_involving_china_n = sum(top2_disagreement_involves_china, na.rm = TRUE),
      close_top1_top2_cases_n = sum(close_top1_top2_case, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(metric)
}

country_summary <- function(comparison) {
  comparison |>
    dplyr::group_by(metric, metric_label, iso3c, country_name) |>
    dplyr::summarise(
      years_any_source = dplyr::n(),
      years_compared = sum(both_sources_present, na.rm = TRUE),
      bpm5_only_years = sum(comparison_sample == "bpm5_only", na.rm = TRUE),
      bpm6_only_years = sum(comparison_sample == "bpm6_only", na.rm = TRUE),
      top1_agreement_rate = mean(top1_same, na.rm = TRUE),
      top2_unordered_agreement_rate = mean(top2_unordered_same, na.rm = TRUE),
      china_top1_status_disagreements_n = sum(!china_top1_status_same, na.rm = TRUE),
      china_in_top2_status_disagreements_n = sum(!china_in_top2_status_same, na.rm = TRUE),
      china_in_top2_any_year = any(china_in_top2_any_source, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(metric, top1_agreement_rate, top2_unordered_agreement_rate, iso3c)
}

first_china_top1_overlap <- function(source_summary) {
  source_summary |>
    dplyr::mutate(china_top1 = top1_partner_iso3 == "CHN") |>
    dplyr::group_by(source, metric, metric_label, iso3c, country_name) |>
    dplyr::summarise(
      first_china_top1_year_overlap = {
        yy <- year[china_top1]
        if (length(yy) == 0L) NA_integer_ else min(yy, na.rm = TRUE)
      },
      china_top1_any_overlap = any(china_top1, na.rm = TRUE),
      .groups = "drop"
    ) |>
    tidyr::pivot_wider(
      names_from = source,
      values_from = c(first_china_top1_year_overlap, china_top1_any_overlap),
      names_sep = "_"
    ) |>
    dplyr::mutate(
      china_top1_status_same_overlap = same_or_both_na(
        china_top1_any_overlap_BPM5,
        china_top1_any_overlap_BPM6
      ),
      first_year_same_if_observed = same_or_both_na(
        first_china_top1_year_overlap_BPM5,
        first_china_top1_year_overlap_BPM6
      )
    ) |>
    dplyr::arrange(metric, iso3c)
}

write_report <- function(paths, summaries) {
  rmd_path <- file.path(
    report_dir,
    paste0("relatorio_estabilidade_top1_top2_batis_bpm5_bpm6_", run_date, ".Rmd")
  )
  md_path <- sub("\\.Rmd$", ".md", rmd_path)

  report_lines <- c(
    "---",
    "title: \"Estabilidade do ranking #1/#2 em BaTIS BPM5 e BPM6\"",
    "lang: pt-BR",
    "output:",
    "  pdf_document:",
    "    toc: false",
    "    number_sections: false",
    "  md_document:",
    "    variant: gfm",
    "params:",
    "  metric_summary: null",
    "  country_summary: null",
    "  china_critical: null",
    "  first_year: null",
    "  input_audit: null",
    "  file_metadata: null",
    "geometry: margin=0.7in, landscape",
    "---",
    "",
    "```{r setup, include=FALSE}",
    "knitr::opts_chunk$set(echo = FALSE, warning = FALSE, message = FALSE)",
    "library(dplyr)",
    "library(readr)",
    "library(knitr)",
    "metric_summary <- readr::read_csv(params$metric_summary, show_col_types = FALSE)",
    "country_summary <- readr::read_csv(params$country_summary, show_col_types = FALSE)",
    "china_critical <- readr::read_csv(params$china_critical, show_col_types = FALSE)",
    "first_year <- readr::read_csv(params$first_year, show_col_types = FALSE)",
    "input_audit <- readr::read_csv(params$input_audit, show_col_types = FALSE)",
    "file_metadata <- readr::read_csv(params$file_metadata, show_col_types = FALSE)",
    "```",
    "",
    "## Objetivo",
    "",
    paste0(
      "Este diagnóstico testa uma hipótese estreita: no overlap ",
      overlap_start, "-", overlap_end,
      ", BaTIS BPM5 e BaTIS BPM6 produzem o mesmo parceiro #1 e #2?"
    ),
    "Isso é mais relevante para uma ponte de tratamento do que a comparabilidade de todos os rankings. O tratamento depende de uma fronteira ordinal: se a China é ou não o parceiro #1. Por isso, o teste foca em top-1, top-2 e nos casos em que a China aparece no topo.",
    "",
    "A comparação cobre quatro métricas: serviços puros por exportações, serviços puros two-way, bens + serviços por exportações e bens + serviços two-way. Nas duas métricas combinadas, o componente de bens vem da mesma ITPD-E; o que varia entre BPM5 e BPM6 é a fonte de serviços.",
    "",
    "## Fontes",
    "",
    paste0(
      "- WTO, página de bulk download de serviços: `",
      summaries$source_page_url,
      "`; acesso em ", run_date, "."
    ),
    paste0(
      "- BaTIS BPM5: cobertura 1995-2012, último update novembro de 2017, arquivo `",
      basename(paths$bpm5_zip), "`."
    ),
    paste0(
      "- BaTIS BPM6: cobertura 2005-2024, último update dezembro de 2025, arquivo `",
      basename(paths$bpm6_zip), "`."
    ),
    "- A própria página da WTO recomenda não combinar automaticamente BPM5 e BPM6 porque seguem padrões diferentes de balanço de pagamentos. Este diagnóstico avalia se, para a variável ordinal do paper, a ponte é empiricamente defensável.",
    "",
    "## Tabela 1. Concordância do ranking #1/#2 no overlap",
    "",
    "```{r table-1}",
    "metric_summary |>",
    "  dplyr::transmute(",
    "    `Métrica` = metric_label,",
    "    `País-anos comuns` = country_years_compared,",
    "    `Só BPM5` = bpm5_only_country_years,",
    "    `Só BPM6` = bpm6_only_country_years,",
    "    `#1 igual` = round(top1_agreement_rate, 3),",
    "    `#1/#2 mesma ordem` = round(top2_ordered_agreement_rate, 3),",
    "    `#1/#2 mesmo conjunto` = round(top2_unordered_agreement_rate, 3),",
    "    `China #1 mesmo status` = round(china_top1_status_agreement_rate, 3),",
    "    `China top-2 mesmo status` = round(china_in_top2_status_agreement_rate, 3),",
    "    `Divergências China #1` = china_top1_status_disagreements_n,",
    "    `Divergências top-2 com China` = top2_disagreements_involving_china_n,",
    "    `Casos #1/#2 próximos` = close_top1_top2_cases_n",
    "  ) |>",
    "  knitr::kable(",
    "    caption = 'Tabela 1. Estabilidade do parceiro #1/#2 entre BaTIS BPM5 e BPM6, 2005-2012.'",
    "  )",
    "```",
    "",
    "## Tabela 2. Auditoria de parsing e cobertura dos insumos",
    "",
    "```{r table-2}",
    "input_audit |>",
    "  dplyr::select(",
    "    dplyr::any_of(c(",
    "      'source', 'item_code', 'raw_rows_total_item_overlap',",
    "      'raw_missing_value_rows', 'raw_parse_fail_nonmissing_rows',",
    "      'raw_negative_value_rows', 'raw_zero_value_rows',",
    "      'valid_rank_input_rows', 'valid_missing_value_rows',",
    "      'valid_parse_fail_nonmissing_rows', 'raw_goods_rows_overlap',",
    "      'raw_missing_trade_rows', 'raw_parse_fail_nonmissing_trade_rows',",
    "      'raw_negative_trade_rows', 'raw_zero_trade_rows'",
    "    ))",
    "  ) |>",
    "  knitr::kable(",
    "    caption = 'Tabela 2. Auditoria dos insumos usados para calcular o ranking de topo.'",
    "  )",
    "```",
    "",
    "## Figura 1. Taxas de concordância",
    "",
    paste0("![](", file.path("figures", basename(paths$agreement_plot)), "){width=95%}"),
    "",
    "Figura 1. Concordância entre BPM5 e BPM6 para rankings de topo no overlap 2005-2012. O teste de top-2 sem ordem considera estável quando os dois parceiros são os mesmos, ainda que troquem a posição #1/#2.",
    "",
    "## Tabela 3. Casos críticos envolvendo China",
    "",
    "```{r table-3}",
    "china_critical |>",
    "  dplyr::transmute(",
    "    `Métrica` = metric_label,",
    "    `País` = paste0(iso3c, ' - ', country_name),",
    "    `Ano` = year,",
    "    `BPM5 #1/#2` = paste0(top1_partner_iso3_bpm5, ' / ', top2_partner_iso3_bpm5),",
    "    `BPM6 #1/#2` = paste0(top1_partner_iso3_bpm6, ' / ', top2_partner_iso3_bpm6),",
    "    `China #1 BPM5` = china_top1_bpm5,",
    "    `China #1 BPM6` = china_top1_bpm6",
    "  ) |>",
    "  utils::head(40) |>",
    "  knitr::kable(",
    "    caption = 'Tabela 3. Primeiros casos críticos: divergência no status da China como #1 ou no top-2 entre BPM5 e BPM6.'",
    "  )",
    "```",
    "",
    "## Tabela 4. Primeiro ano em que China é #1 dentro do overlap",
    "",
    "```{r table-4}",
    "first_year |>",
    "  dplyr::filter(",
    "    !first_year_same_if_observed |",
    "      china_top1_any_overlap_BPM5 | china_top1_any_overlap_BPM6",
    "  ) |>",
    "  dplyr::transmute(",
    "    `Métrica` = metric_label,",
    "    `País` = paste0(iso3c, ' - ', country_name),",
    "    `BPM5` = first_china_top1_year_overlap_BPM5,",
    "    `BPM6` = first_china_top1_year_overlap_BPM6,",
    "    `Mesmo status no overlap` = china_top1_status_same_overlap,",
    "    `Mesmo ano se observado` = first_year_same_if_observed",
    "  ) |>",
    "  knitr::kable(",
    "    caption = 'Tabela 4. Diferenças no primeiro ano observado em que a China é parceira #1 no overlap.'",
    "  )",
    "```",
    "",
    "## Interpretação",
    "",
    "O teste direto da ponte BaTIS, usando apenas serviços, não é forte: a concordância do parceiro #1 é moderada e a concordância do conjunto #1/#2 é baixa. Isso sugere que BPM5 e BPM6 não devem ser misturadas para produzir uma série histórica de serviços puros sem caveat forte.",
    "",
    "Nas métricas compostas bens + serviços, a estabilidade é maior porque o componente de bens vem da mesma ITPD-E nos dois lados. Essa é a pergunta mais próxima da variável substantiva M3/M4: a troca BPM5/BPM6 muda o ranking final de topo? A resposta é: pouco na maioria dos país-anos, mas não zero. Há divergências no status da China como #1 e vários casos em que China está exatamente na fronteira #1/#2. Portanto, uma ponte BPM5/BPM6 pode ser usada como robustez exploratória para M3/M4, mas não como substituto limpo da especificação M2 nem como evidência sem auditoria dos casos críticos.",
    "",
    "A leitura causal correta é: uma ponte BPM5/BPM6 mudaria a população de risco e permitiria observar entradas antes de 2005, mas só é plausível se a fronteira ordinal que define o tratamento for estável no overlap. Caso contrário, a ponte criaria anos de entrada artificiais por mudança de fonte, não por mudança real na posição comercial da China."
  )

  writeLines(report_lines, rmd_path, useBytes = TRUE)

  render_params <- list(
    metric_summary = normalizePath(paths$metric_summary, mustWork = TRUE),
    country_summary = normalizePath(paths$country_summary, mustWork = TRUE),
    china_critical = normalizePath(paths$china_critical, mustWork = TRUE),
    first_year = normalizePath(paths$first_year, mustWork = TRUE),
    input_audit = normalizePath(paths$input_audit, mustWork = TRUE),
    file_metadata = normalizePath(paths$file_metadata, mustWork = TRUE)
  )

  pdf_ok <- tryCatch({
    rmarkdown::render(
      rmd_path,
      output_format = "pdf_document",
      output_file = basename(sub("\\.Rmd$", ".pdf", rmd_path)),
      output_dir = report_dir,
      params = render_params,
      quiet = TRUE,
      envir = new.env(parent = globalenv())
    )
    TRUE
  }, error = function(e) {
    warning("PDF render failed: ", conditionMessage(e), call. = FALSE)
    FALSE
  })

  md_ok <- tryCatch({
    rmarkdown::render(
      rmd_path,
      output_format = "md_document",
      output_file = basename(md_path),
      output_dir = report_dir,
      params = render_params,
      quiet = TRUE,
      envir = new.env(parent = globalenv())
    )
    TRUE
  }, error = function(e) {
    warning("Markdown render failed: ", conditionMessage(e), call. = FALSE)
    FALSE
  })

  tibble::tibble(
    artifact = c("report_rmd", "report_pdf", "report_md"),
    path = c(rmd_path, sub("\\.Rmd$", ".pdf", rmd_path), md_path),
    created = c(file.exists(rmd_path), pdf_ok && file.exists(sub("\\.Rmd$", ".pdf", rmd_path)), md_ok && file.exists(md_path))
  )
}

source_page_url <- "https://www.wto.org/english/res_e/statis_e/trade_datasets_e.htm"
bpm5_data_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_BATIS_data.zip"
bpm5_codes_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_BATIS_codes.zip"
bpm5_method_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_Batis_methodology.pdf"
bpm6_data_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_BATIS_data_BPM6-1.zip"
bpm6_codes_url <- "https://www.wto.org/english/res_e/statis_e/daily_update_e/OECD-WTO_BATIS_codes_BPM6-1.zip"

bpm5_zip <- file.path(raw_bpm5_dir, paste0("OECD-WTO_BATIS_data_", run_date, ".zip"))
bpm5_codes_zip <- file.path(raw_bpm5_dir, paste0("OECD-WTO_BATIS_codes_", run_date, ".zip"))
bpm5_method_pdf <- file.path(raw_bpm5_dir, paste0("OECD-WTO_Batis_methodology_", run_date, ".pdf"))
bpm6_zip <- file.path(raw_bpm6_dir, paste0("OECD-WTO_BATIS_data_BPM6-1_", run_date, ".zip"))
bpm6_codes_zip <- file.path(raw_bpm6_dir, paste0("OECD-WTO_BATIS_codes_BPM6-1_", run_date, ".zip"))

download_if_missing(bpm5_data_url, bpm5_zip)
download_if_missing(bpm5_codes_url, bpm5_codes_zip)
download_if_missing(bpm5_method_url, bpm5_method_pdf)
download_if_missing(bpm6_data_url, bpm6_zip)
download_if_missing(bpm6_codes_url, bpm6_codes_zip)

bpm5_csv <- extract_one_from_zip(
  bpm5_zip,
  file.path(raw_bpm5_dir, paste0("extracted_", run_date)),
  "\\.(csv|txt)$"
)
bpm5_codes_xlsx <- extract_one_from_zip(
  bpm5_codes_zip,
  file.path(raw_bpm5_dir, paste0("codes_extracted_", run_date)),
  "\\.xlsx$"
)
bpm6_csv <- extract_one_from_zip(
  bpm6_zip,
  file.path(raw_bpm6_dir, paste0("extracted_", run_date)),
  "\\.(csv|txt)$"
)
bpm6_codes_xlsx <- extract_one_from_zip(
  bpm6_codes_zip,
  file.path(raw_bpm6_dir, paste0("codes_extracted_", run_date)),
  "\\.xlsx$"
)

panel_countries <- read_panel_countries()
bpm5_code_map <- read_bpm5_codes(bpm5_codes_xlsx)
bpm6_code_map <- read_bpm6_codes(bpm6_codes_xlsx)

bpm5_services_result <- read_batis_total_services(
  bpm5_csv,
  bpm5_code_map,
  total_item_code = "S200",
  source_name = "BPM5",
  start_year = overlap_start,
  end_year = overlap_end
)

bpm6_services_result <- read_batis_total_services(
  bpm6_csv,
  bpm6_code_map,
  total_item_code = "S",
  source_name = "BPM6",
  start_year = overlap_start,
  end_year = overlap_end
)

bpm5_services <- bpm5_services_result$data
bpm6_services <- bpm6_services_result$data

if (nrow(bpm5_services) == 0L || nrow(bpm6_services) == 0L) {
  stop("BaTIS extraction returned zero service rows for BPM5 or BPM6.", call. = FALSE)
}

itpd_goods_result <- read_itpd_goods_overlap(
  file.path("raw data", "ITPDE_R03.csv"),
  panel_countries,
  overlap_start,
  overlap_end
)
itpd_goods <- itpd_goods_result$data

input_audit <- dplyr::bind_rows(
  bpm5_services_result$audit,
  bpm6_services_result$audit,
  itpd_goods_result$audit
)

bpm5_metric_panel <- build_partner_metric_panel(bpm5_services, itpd_goods, panel_countries)
bpm6_metric_panel <- build_partner_metric_panel(bpm6_services, itpd_goods, panel_countries)

top_two_long <- dplyr::bind_rows(
  rank_top_two(bpm5_metric_panel),
  rank_top_two(bpm6_metric_panel)
)

top_two_summary <- summarise_top_two(top_two_long)
comparison <- compare_sources(top_two_summary)
summary_by_metric <- metric_summary(comparison)
summary_by_country <- country_summary(comparison)
first_year_overlap <- first_china_top1_overlap(top_two_summary)

coverage_by_metric_year <- comparison |>
  dplyr::count(metric, metric_label, year, comparison_sample, name = "country_years") |>
  tidyr::pivot_wider(
    names_from = comparison_sample,
    values_from = country_years,
    values_fill = 0
  ) |>
  dplyr::arrange(metric, year)

top1_disagreements <- comparison |>
  dplyr::filter(!top1_same) |>
  dplyr::arrange(metric, iso3c, year)

top2_disagreements <- comparison |>
  dplyr::filter(!top2_unordered_same) |>
  dplyr::arrange(metric, iso3c, year)

china_critical <- comparison |>
  dplyr::filter(
    !china_top1_status_same |
      !china_in_top2_status_same |
      top1_disagreement_involves_china |
      top2_disagreement_involves_china
  ) |>
  dplyr::arrange(metric, iso3c, year)

agreement_plot_data <- summary_by_metric |>
  dplyr::select(
    metric, metric_label,
    top1_agreement_rate,
    top2_ordered_agreement_rate,
    top2_unordered_agreement_rate,
    china_top1_status_agreement_rate,
    china_in_top2_status_agreement_rate
  ) |>
  tidyr::pivot_longer(
    cols = dplyr::ends_with("_rate"),
    names_to = "agreement_type",
    values_to = "agreement_rate"
  ) |>
  dplyr::mutate(
    agreement_type = dplyr::recode(
      agreement_type,
      top1_agreement_rate = "#1 igual",
      top2_ordered_agreement_rate = "#1/#2 iguais, mesma ordem",
      top2_unordered_agreement_rate = "#1/#2 iguais, sem ordem",
      china_top1_status_agreement_rate = "China #1: mesmo status",
      china_in_top2_status_agreement_rate = "China no top-2: mesmo status"
    ),
    metric_label = factor(
      metric_label,
      levels = c(
        "Serviços: exportações",
        "Serviços: exportações + importações",
        "Bens + serviços: exportações",
        "Bens + serviços: exportações + importações"
      )
    )
  )

agreement_plot <- ggplot2::ggplot(
  agreement_plot_data,
  ggplot2::aes(x = agreement_rate, y = agreement_type)
) +
  ggplot2::geom_col(fill = "#2f6f73", width = 0.68) +
  ggplot2::geom_text(
    ggplot2::aes(label = scales::percent(agreement_rate, accuracy = 0.1)),
    hjust = -0.05,
    size = 3.1
  ) +
  ggplot2::facet_wrap(~ metric_label, ncol = 2) +
  ggplot2::scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1.08),
    breaks = seq(0, 1, by = 0.25)
  ) +
  ggplot2::labs(
    title = "Figura 1. Estabilidade do ranking #1/#2 entre BaTIS BPM5 e BPM6",
    subtitle = paste0("País-ano no overlap ", overlap_start, "-", overlap_end, "; amostra do painel cross-country"),
    x = "Taxa de concordância BPM5/BPM6",
    y = NULL,
    caption = "Fonte: WTO-OECD BaTIS BPM5 e BPM6; ITPD-E para bens nas métricas combinadas."
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    plot.title.position = "plot",
    panel.grid.major.y = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.caption = ggplot2::element_text(hjust = 0)
  )

agreement_plot_path <- file.path(
  figure_dir,
  paste0("figura_1_estabilidade_top1_top2_batis_bpm5_bpm6_", run_date, ".pdf")
)
ggplot2::ggsave(
  agreement_plot_path,
  agreement_plot,
  width = 11,
  height = 7.5,
  device = grDevices::pdf
)

paths <- list(
  bpm5_zip = bpm5_zip,
  bpm6_zip = bpm6_zip,
  agreement_plot = agreement_plot_path,
  top_two_long = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_top2_long_", run_date, ".csv")),
  top_two_summary = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_top2_by_source_", run_date, ".csv")),
  comparison = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_top2_comparison_", run_date, ".csv")),
  metric_summary = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_top2_metric_summary_", run_date, ".csv")),
  country_summary = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_top2_country_summary_", run_date, ".csv")),
  coverage_by_metric_year = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_top2_coverage_by_metric_year_", run_date, ".csv")),
  input_audit = file.path(processed_dir, paste0("batis_bpm5_bpm6_overlap_input_audit_", run_date, ".csv")),
  top1_disagreements = file.path(processed_dir, paste0("batis_bpm5_bpm6_top1_disagreements_", run_date, ".csv")),
  top2_disagreements = file.path(processed_dir, paste0("batis_bpm5_bpm6_top2_disagreements_", run_date, ".csv")),
  china_critical = file.path(processed_dir, paste0("batis_bpm5_bpm6_china_critical_top1_top2_disagreements_", run_date, ".csv")),
  first_year = file.path(processed_dir, paste0("batis_bpm5_bpm6_first_china_top1_overlap_", run_date, ".csv")),
  file_metadata = file.path(processed_dir, paste0("batis_bpm5_bpm6_overlap_file_metadata_", run_date, ".csv")),
  sources = file.path(processed_dir, paste0("batis_bpm5_bpm6_overlap_sources_", run_date, ".yaml")),
  session = file.path(processed_dir, paste0("batis_bpm5_bpm6_overlap_session_info_", run_date, ".txt"))
)

readr::write_csv(top_two_long, paths$top_two_long)
readr::write_csv(top_two_summary, paths$top_two_summary)
readr::write_csv(comparison, paths$comparison)
readr::write_csv(summary_by_metric, paths$metric_summary)
readr::write_csv(summary_by_country, paths$country_summary)
readr::write_csv(coverage_by_metric_year, paths$coverage_by_metric_year)
readr::write_csv(input_audit, paths$input_audit)
readr::write_csv(top1_disagreements, paths$top1_disagreements)
readr::write_csv(top2_disagreements, paths$top2_disagreements)
readr::write_csv(china_critical, paths$china_critical)
readr::write_csv(first_year_overlap, paths$first_year)

metadata <- file_metadata(
  c(
    bpm5_zip,
    bpm5_codes_zip,
    bpm5_method_pdf,
    bpm5_csv,
    bpm5_codes_xlsx,
    bpm6_zip,
    bpm6_codes_zip,
    bpm6_csv,
    bpm6_codes_xlsx,
    file.path("raw data", "ITPDE_R03.csv")
  ),
  c(
    "batis_bpm5_data_zip",
    "batis_bpm5_codes_zip",
    "batis_bpm5_methodology_pdf",
    "batis_bpm5_extracted_csv",
    "batis_bpm5_codes_xlsx",
    "batis_bpm6_data_zip",
    "batis_bpm6_codes_zip",
    "batis_bpm6_extracted_csv",
    "batis_bpm6_codes_xlsx",
    "itpde_raw_csv"
  )
)
readr::write_csv(metadata, paths$file_metadata)

source_manifest <- list(
  run_date = as.character(run_date),
  accessed_on = as.character(run_date),
  overlap_years = paste0(overlap_start, "-", overlap_end),
  wto_bulk_download_page = source_page_url,
  panel_country_source = unique(panel_countries$panel_source),
  file_metadata_csv = paths$file_metadata,
  input_audit_csv = paths$input_audit,
  bpm5 = list(
    data_url = bpm5_data_url,
    codes_url = bpm5_codes_url,
    methodology_url = bpm5_method_url,
    local_data_zip = bpm5_zip,
    extracted_csv = bpm5_csv,
    local_codes_zip = bpm5_codes_zip,
    local_methodology_pdf = bpm5_method_pdf,
    declared_coverage = "1995-2012",
    declared_standard = "BPM5 / EBOPS 2002"
  ),
  bpm6 = list(
    data_url = bpm6_data_url,
    codes_url = bpm6_codes_url,
    local_data_zip = bpm6_zip,
    extracted_csv = bpm6_csv,
    local_codes_zip = bpm6_codes_zip,
    declared_coverage = "2005-2024",
    declared_standard = "BPM6 / EBOPS 2010"
  ),
  design_note = paste(
    "The diagnostic evaluates only top-1/top-2 rank stability in the overlap.",
    "It does not assume full comparability of all service values or lower partner ranks."
  )
)
yaml::write_yaml(source_manifest, paths$sources)
writeLines(capture.output(sessionInfo()), paths$session, useBytes = TRUE)

report_manifest <- write_report(
  paths,
  summaries = list(source_page_url = source_page_url)
)

output_manifest <- dplyr::bind_rows(
  tibble::tibble(
    artifact = c(
      "top_two_long",
      "top_two_by_source",
      "top_two_comparison",
      "metric_summary",
      "country_summary",
      "coverage_by_metric_year",
      "input_audit",
      "top1_disagreements",
      "top2_disagreements",
      "china_critical",
      "first_china_top1_overlap",
      "agreement_plot",
      "file_metadata",
      "sources_yaml",
      "session_info"
    ),
    path = c(
      paths$top_two_long,
      paths$top_two_summary,
      paths$comparison,
      paths$metric_summary,
      paths$country_summary,
      paths$coverage_by_metric_year,
      paths$input_audit,
      paths$top1_disagreements,
      paths$top2_disagreements,
      paths$china_critical,
      paths$first_year,
      agreement_plot_path,
      paths$file_metadata,
      paths$sources,
      paths$session
    ),
    created = file.exists(c(
      paths$top_two_long,
      paths$top_two_summary,
      paths$comparison,
      paths$metric_summary,
      paths$country_summary,
      paths$coverage_by_metric_year,
      paths$input_audit,
      paths$top1_disagreements,
      paths$top2_disagreements,
      paths$china_critical,
      paths$first_year,
      agreement_plot_path,
      paths$file_metadata,
      paths$sources,
      paths$session
    ))
  ),
  report_manifest
)

manifest_path <- file.path(
  processed_dir,
  paste0("batis_bpm5_bpm6_overlap_output_manifest_", run_date, ".csv")
)
readr::write_csv(output_manifest, manifest_path)

log_msg("Finished BaTIS BPM5/BPM6 top-1/top-2 overlap diagnostic.")
print(summary_by_metric)
cat("\nOutput manifest: ", manifest_path, "\n", sep = "")
