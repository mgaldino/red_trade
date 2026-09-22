# Appendix table of the public-cue search: one row per searched country, with the
# first post-2000 year in which China is the top goods-export destination, the search
# window, the salience code, and the counted sources. Australia is reported from the
# 2006-2007 media search, which dates its public cue; the other countries use the
# entry-year window of the status-cue audit.
build_public_cue_audit_table <- function(goods_panel,
                                         status_country_file,
                                         status_source_file,
                                         australia_media_file,
                                         australia_code) {
  fmt_date <- function(x) {
    x <- as.character(x)
    full <- nchar(x) == 10L
    out <- x
    out[full] <- format(as.Date(x[full]), "%b %Y")
    month_only <- nchar(x) == 7L
    out[month_only] <- format(as.Date(paste0(x[month_only], "-01")), "%b %Y")
    out
  }

  goods_entry <- goods_panel |>
    dplyr::filter(
      .data$china_is_top %in% TRUE,
      .data$year >= 2000L,
      !(.data$previous_china_is_top %in% TRUE)
    ) |>
    dplyr::group_by(.data$iso3c) |>
    dplyr::summarise(goods_entry_year = min(.data$year), .groups = "drop")

  status_country <- readr::read_csv(status_country_file, show_col_types = FALSE)
  status_source <- readr::read_csv(status_source_file, show_col_types = FALSE)
  australia_media <- readr::read_csv(
    australia_media_file,
    show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )

  counted <- status_source |>
    dplyr::filter(
      .data$evidence_strength %in% c("strong", "moderate"),
      is.na(.data$notes) | !grepl("^DO_NOT_COUNT", .data$notes),
      .data$iso3c != "AUS"
    ) |>
    dplyr::transmute(
      iso3c = .data$iso3c,
      publication_date = as.character(.data$publication_date),
      source_name = .data$source_name,
      label = .data$rank_label_english
    )

  # The counted sources must reproduce the audit's own source counts.
  count_check <- counted |>
    dplyr::count(.data$iso3c, name = "n_counted") |>
    dplyr::right_join(
      status_country |>
        dplyr::filter(.data$iso3c != "AUS") |>
        dplyr::select(iso3c, n_total_strong_or_moderate),
      by = "iso3c"
    ) |>
    dplyr::mutate(n_counted = dplyr::coalesce(.data$n_counted, 0L))
  stopifnot(all(count_check$n_counted == count_check$n_total_strong_or_moderate))

  australia_sources <- australia_media |>
    dplyr::filter(substr(.data$publication_date, 1L, 4L) %in% c("2006", "2007")) |>
    dplyr::transmute(
      iso3c = "AUS",
      publication_date = .data$publication_date,
      source_name = .data$source_name,
      label = sub("\\.$", "", .data$excerpt_under_25_words)
    )
  stopifnot(nrow(australia_sources) > 0L)

  sources_text <- dplyr::bind_rows(counted, australia_sources) |>
    dplyr::arrange(.data$iso3c, .data$publication_date) |>
    dplyr::mutate(
      item = paste0(.data$label, " (", .data$source_name, ", ",
                    fmt_date(.data$publication_date), ")")
    ) |>
    dplyr::group_by(.data$iso3c) |>
    dplyr::summarise(sources = paste(.data$item, collapse = "; "), .groups = "drop")

  out <- status_country |>
    dplyr::transmute(
      iso3c = .data$iso3c,
      country = .data$country_name,
      window_start = as.integer(.data$entry_year),
      code = .data$salience_code
    ) |>
    dplyr::mutate(
      window_start = dplyr::if_else(.data$iso3c == "AUS", 2006L, .data$window_start),
      window_end = dplyr::if_else(.data$iso3c == "AUS", 2007L, .data$window_start + 1L),
      code = dplyr::if_else(.data$iso3c == "AUS", australia_code, .data$code)
    ) |>
    dplyr::left_join(goods_entry, by = "iso3c") |>
    dplyr::left_join(sources_text, by = "iso3c") |>
    dplyr::mutate(
      search_window = paste0(.data$window_start, "--", .data$window_end),
      sources = dplyr::coalesce(.data$sources, "None recovered in the window"),
      code = factor(.data$code, levels = c("high", "medium", "low", "unknown"))
    ) |>
    dplyr::arrange(.data$code, .data$goods_entry_year, .data$country) |>
    dplyr::select(iso3c, country, goods_entry_year, search_window, code, sources)

  stopifnot(!anyNA(out$goods_entry_year))
  out
}
