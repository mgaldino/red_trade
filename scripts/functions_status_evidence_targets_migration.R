# Deterministic status-evidence processing for the targets migration.
# HTTP acquisition remains in the Python collectors. These functions begin at
# frozen raw manifests and author-owned coding ledgers.

status_evidence_require_columns <- function(data, required, label) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop(
      label,
      " is missing required columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(data)
}

status_evidence_bool <- function(x, label) {
  if (is.logical(x)) {
    if (anyNA(x)) {
      stop(label, " contains missing boolean values.", call. = FALSE)
    }
    return(x)
  }
  value <- tolower(trimws(as.character(x)))
  if (anyNA(value) || any(!value %in% c("true", "false"))) {
    stop(label, " must contain only true or false.", call. = FALSE)
  }
  value == "true"
}

status_evidence_integer <- function(x, label, minimum, maximum) {
  value <- trimws(as.character(x))
  valid_lexeme <- !is.na(value) & grepl("^[0-9]+$", value)
  parsed <- suppressWarnings(as.integer(value))
  valid_range <- !is.na(parsed) & parsed >= minimum & parsed <= maximum
  if (any(!valid_lexeme | !valid_range)) {
    stop(
      label,
      " must contain only whole years from ",
      minimum,
      " through ",
      maximum,
      ".",
      call. = FALSE
    )
  }
  parsed
}

status_evidence_valid_iso_date <- function(x) {
  value <- as.character(x)
  lexically_valid <- !is.na(value) &
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)
  parsed <- suppressWarnings(as.Date(value, format = "%Y-%m-%d"))
  lexically_valid & !is.na(parsed) & format(parsed, "%Y-%m-%d") == value
}

status_evidence_valid_http_url <- function(x) {
  value <- as.character(x)
  !is.na(value) & grepl(
    "^https?://[^/?#[:space:]]+(?:[/?#]|$)",
    value,
    perl = TRUE
  )
}

status_evidence_expected_audit_universe <- function() {
  tibble::tribble(
    ~iso3c, ~country_name, ~entry_year,
    "SLB", "Solomon Islands", 2003L,
    "PHL", "Philippines", 2005L,
    "AGO", "Angola", 2007L,
    "CHL", "Chile", 2008L,
    "BRA", "Brazil", 2009L,
    "MYS", "Malaysia", 2009L,
    "AUS", "Australia", 2010L,
    "SLE", "Sierra Leone", 2012L,
    "URY", "Uruguay", 2013L,
    "MMR", "Myanmar (Burma)", 2014L,
    "SAU", "Saudi Arabia", 2015L,
    "GAB", "Gabon", 2017L,
    "KWT", "Kuwait", 2018L,
    "QAT", "Qatar", 2021L
  )
}

status_evidence_file_sha256 <- function(path) {
  digest::digest(
    file = path,
    algo = "sha256",
    serialize = FALSE
  )
}

status_evidence_read_checksum_manifest <- function(manifest_file,
                                                    raw_directory,
                                                    expected_entries) {
  lines <- readLines(manifest_file, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  matched <- regexec("^([0-9a-f]{64})  (.+)$", lines, perl = TRUE)
  fields <- regmatches(lines, matched)
  if (length(lines) != expected_entries ||
      any(lengths(fields) != 3L)) {
    stop(
      "Malformed raw checksum manifest or unexpected entry count: ",
      manifest_file,
      call. = FALSE
    )
  }
  relative_path <- vapply(fields, `[[`, character(1), 3L)
  sha256 <- vapply(fields, `[[`, character(1), 2L)
  components <- strsplit(relative_path, "/", fixed = TRUE)
  unsafe <- grepl("^/", relative_path) |
    vapply(components, function(value) ".." %in% value, logical(1))
  if (any(unsafe) || anyDuplicated(relative_path)) {
    stop("Unsafe or duplicated path in raw checksum manifest.", call. = FALSE)
  }
  paths <- file.path(raw_directory, relative_path)
  if (any(!file.exists(paths))) {
    stop(
      "Raw checksum manifest references absent files: ",
      paste(relative_path[!file.exists(paths)], collapse = ", "),
      call. = FALSE
    )
  }
  tibble::tibble(
    relative_path = relative_path,
    path = paths,
    expected_sha256 = sha256
  ) |>
    dplyr::arrange(relative_path)
}

status_evidence_raw_paths <- function(manifest_file,
                                      raw_directory,
                                      expected_entries) {
  status_evidence_read_checksum_manifest(
    manifest_file,
    raw_directory,
    expected_entries
  )$path
}

validate_status_evidence_raw_archive <- function(manifest_file,
                                                 raw_files,
                                                 raw_directory,
                                                 expected_entries,
                                                 expected_manifest_sha256) {
  manifest <- status_evidence_read_checksum_manifest(
    manifest_file,
    raw_directory,
    expected_entries
  ) |>
    dplyr::mutate(
      observed_sha256 = vapply(
        path,
        status_evidence_file_sha256,
        character(1)
      ),
      hash_matches = observed_sha256 == expected_sha256
    )
  tibble::tibble(
    validation = c(
      "manifest_hash_matches",
      "manifest_entry_count_matches",
      "file_target_matches_manifest",
      "all_raw_hashes_match"
    ),
    passed = c(
      identical(
        status_evidence_file_sha256(manifest_file),
        expected_manifest_sha256
      ),
      nrow(manifest) == expected_entries,
      identical(
        sort(normalizePath(raw_files, mustWork = TRUE)),
        sort(normalizePath(manifest$path, mustWork = TRUE))
      ),
      all(manifest$hash_matches)
    ),
    detail = c(
      basename(manifest_file),
      paste0("entries=", nrow(manifest)),
      paste0("files=", length(raw_files)),
      paste0("matching=", sum(manifest$hash_matches), "/", nrow(manifest))
    )
  )
}

status_evidence_read_character_csv <- function(path) {
  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE,
    progress = FALSE
  )
}

status_evidence_expected_ledger_hash <- function(kind) {
  switch(
    kind,
    status = "e24bfca356622e72702f35252c7a1a5c0ffa3fd4c76a1810011a17c2d1e27f99",
    ex_top1 = "c7f14d595af04ec5bad108897bf150a833bbe56123e1229857c38eb88f9ec1fc",
    stop("Unknown status-evidence ledger kind: ", kind, call. = FALSE)
  )
}

status_evidence_required_source_columns <- function(kind) {
  common <- c(
    "iso3c", "country_name", "entry_year", "evidence_year",
    "source_type", "source_name", "source_country", "language", "title",
    "publication_date", "url", "archive_url", "raw_file", "query_used",
    "accessed_at", "rank_label_original", "rank_label_english", "label_type",
    "explicit_rank_language", "excerpt_under_25_words", "evidence_strength",
    "notes"
  )
  if (identical(kind, "status")) {
    return(c(
      common,
      "mentions_china_rank_change", "mentions_displaced_incumbent",
      "displaced_partner_named"
    ))
  }
  c(
    "source_id", common,
    "incumbent_partner_name", "incumbent_partner_iso3",
    "incumbent_rank_year", "incumbent_rank_source_file",
    "incumbent_export_share", "china_export_share", "eligible_source",
    "coverage_topic", "mentions_incumbent_trade", "mentions_china",
    "mentions_rank_change_or_displacement", "incumbent_partner_named",
    "count_for_benchmark"
  )
}

read_status_evidence_source_ledger <- function(path, kind) {
  source <- status_evidence_read_character_csv(path)
  status_evidence_require_columns(
    source,
    status_evidence_required_source_columns(kind),
    paste0(kind, " source-evidence ledger")
  )
  source
}

status_evidence_raw_pointer_membership <- function(raw_pointer,
                                                   raw_files,
                                                   raw_directory) {
  root <- normalizePath(".", mustWork = TRUE)
  raw_root <- normalizePath(raw_directory, mustWork = TRUE)
  if (any(!nzchar(raw_pointer)) || any(grepl("^/", raw_pointer))) {
    return(rep(FALSE, length(raw_pointer)))
  }
  pieces <- strsplit(raw_pointer, "/", fixed = TRUE)
  if (any(vapply(pieces, function(value) ".." %in% value, logical(1)))) {
    return(rep(FALSE, length(raw_pointer)))
  }
  pointer_path <- file.path(root, raw_pointer)
  existing <- file.exists(pointer_path)
  normalized <- rep(NA_character_, length(pointer_path))
  normalized[existing] <- normalizePath(pointer_path[existing], mustWork = TRUE)
  raw_members <- startsWith(normalized, paste0(raw_root, .Platform$file.sep))
  raw_members[is.na(raw_members)] <- FALSE
  normalized_files <- normalizePath(raw_files, mustWork = TRUE)
  existing & raw_members & normalized %in% normalized_files
}

validate_status_evidence_source_ledger <- function(source,
                                                   source_file,
                                                   kind,
                                                   raw_files,
                                                   raw_directory,
                                                   expected_rows) {
  bool_columns <- if (identical(kind, "status")) {
    c(
      "explicit_rank_language", "mentions_china_rank_change",
      "mentions_displaced_incumbent"
    )
  } else {
    c(
      "eligible_source", "explicit_rank_language", "mentions_incumbent_trade",
      "mentions_china", "mentions_rank_change_or_displacement",
      "count_for_benchmark"
    )
  }
  bool_valid <- vapply(
    bool_columns,
    function(column) {
      !inherits(
        try(status_evidence_bool(source[[column]], column), silent = TRUE),
        "try-error"
      )
    },
    logical(1)
  )
  key <- if (identical(kind, "status")) source$raw_file else source$source_id
  entry_year_text <- trimws(as.character(source$entry_year))
  evidence_year_text <- trimws(as.character(source$evidence_year))
  entry_year <- suppressWarnings(as.integer(entry_year_text))
  evidence_year <- suppressWarnings(as.integer(evidence_year_text))
  years_valid <-
    all(grepl("^[0-9]+$", entry_year_text)) &&
    all(grepl("^[0-9]+$", evidence_year_text)) &&
    !anyNA(entry_year) &&
    !anyNA(evidence_year) &&
    all(entry_year >= 1990L & entry_year <= 2023L) &&
    all(evidence_year >= 1990L & evidence_year <= 2023L)
  dates_valid <- all(status_evidence_valid_iso_date(source$publication_date))
  urls_valid <- all(status_evidence_valid_http_url(source$url))
  tibble::tibble(
    validation = c(
      "ledger_hash_matches",
      "ledger_row_count_matches",
      "ledger_keys_unique_and_nonmissing",
      "ledger_country_codes_valid",
      "ledger_years_valid",
      "ledger_publication_dates_valid",
      "ledger_urls_valid",
      "ledger_booleans_valid",
      "ledger_raw_pointers_manifested"
    ),
    passed = c(
      identical(
        status_evidence_file_sha256(source_file),
        status_evidence_expected_ledger_hash(kind)
      ),
      nrow(source) == expected_rows,
      !anyNA(key) && all(nzchar(key)) && anyDuplicated(key) == 0L,
      !anyNA(source$iso3c) && all(grepl("^[A-Z]{3}$", source$iso3c)),
      years_valid,
      dates_valid,
      urls_valid,
      all(bool_valid),
      all(status_evidence_raw_pointer_membership(
        source$raw_file,
        raw_files,
        raw_directory
      ))
    ),
    detail = c(
      basename(source_file),
      paste0("rows=", nrow(source)),
      paste0("unique=", dplyr::n_distinct(key)),
      paste0("countries=", dplyr::n_distinct(source$iso3c)),
      paste0(min(evidence_year), "-", max(evidence_year)),
      paste0("valid_dates=", sum(status_evidence_valid_iso_date(
        source$publication_date
      )), "/", nrow(source)),
      paste0("valid_urls=", sum(status_evidence_valid_http_url(source$url)),
             "/", nrow(source)),
      paste(bool_columns, bool_valid, sep = "=", collapse = ";"),
      paste0("manifested=", sum(status_evidence_raw_pointer_membership(
        source$raw_file,
        raw_files,
        raw_directory
      )), "/", nrow(source))
    )
  )
}

read_status_evidence_audit_universe <- function(path) {
  universe <- status_evidence_read_character_csv(path)
  status_evidence_require_columns(
    universe,
    c("iso3c", "country_name", "entry_year"),
    "status-evidence audit universe"
  )
  universe |>
    dplyr::mutate(
      entry_year = status_evidence_integer(
        entry_year,
        "audit-universe entry_year",
        1990L,
        2023L
      )
    ) |>
    dplyr::arrange(entry_year, iso3c)
}

read_status_country_overrides <- function(path) {
  overrides <- status_evidence_read_character_csv(path)
  status_evidence_require_columns(
    overrides,
    c(
      "iso3c", "salience_code", "negative_case_candidate",
      "coding_rationale", "remaining_gaps"
    ),
    "status-country overrides"
  )
  overrides
}

read_ex_top1_country_annotations <- function(path) {
  annotations <- status_evidence_read_character_csv(path)
  status_evidence_require_columns(
    annotations,
    c("iso3c", "remaining_gaps"),
    "former-incumbent country annotations"
  )
  annotations
}

validate_status_evidence_manual_inputs <- function(universe,
                                                   overrides,
                                                   annotations) {
  expected_universe <- status_evidence_expected_audit_universe() |>
    dplyr::arrange(entry_year, iso3c)
  observed_universe <- universe |>
    dplyr::select(iso3c, country_name, entry_year) |>
    dplyr::arrange(entry_year, iso3c)
  tibble::tibble(
    validation = c(
      "audit_universe_has_14_unique_cases",
      "audit_universe_years_valid",
      "audit_universe_iso3c_valid",
      "audit_universe_exact_contract",
      "status_overrides_unique_and_in_universe",
      "status_override_codes_allowed",
      "ex_annotations_cover_universe_once"
    ),
    passed = c(
      nrow(universe) == 14L && anyDuplicated(universe$iso3c) == 0L,
      !anyNA(universe$entry_year) &&
        all(universe$entry_year >= 1990L & universe$entry_year <= 2023L),
      !anyNA(universe$iso3c) && all(grepl("^[A-Z]{3}$", universe$iso3c)),
      identical(observed_universe, expected_universe),
      anyDuplicated(overrides$iso3c) == 0L &&
        all(overrides$iso3c %in% universe$iso3c),
      all(overrides$salience_code %in% c("high", "medium", "low", "unknown")) &&
        all(overrides$negative_case_candidate %in% c("yes", "no")),
      nrow(annotations) == nrow(universe) &&
        anyDuplicated(annotations$iso3c) == 0L &&
        setequal(annotations$iso3c, universe$iso3c)
    ),
    detail = c(
      paste0("rows=", nrow(universe)),
      paste0(min(universe$entry_year), "-", max(universe$entry_year)),
      paste(sort(universe$iso3c), collapse = ";"),
      "iso3c-country_name-entry_year",
      paste0("overrides=", nrow(overrides)),
      paste(sort(unique(overrides$salience_code)), collapse = ";"),
      paste0("annotations=", nrow(annotations))
    )
  )
}

validate_status_evidence_incumbent_file <- function(path) {
  expected <- "c170d884d943c9a133849e4676a9cbff1236ce8a2c4ea9d8f68cead364b4f08f"
  tibble::tibble(
    validation = "incumbent_file_hash_matches",
    passed = file.exists(path) &&
      identical(status_evidence_file_sha256(path), expected),
    detail = basename(path)
  )
}

status_evidence_collapse_unique <- function(x) {
  x <- unique(x[!is.na(x) & nzchar(x)])
  if (length(x) == 0L) return("")
  paste(sort(x), collapse = "; ")
}

build_status_cue_country_codes_candidate <- function(universe,
                                                     source,
                                                     overrides) {
  evidence <- source |>
    dplyr::mutate(
      explicit_rank_language = status_evidence_bool(
        explicit_rank_language,
        "status explicit_rank_language"
      ),
      mentions_china_rank_change = status_evidence_bool(
        mentions_china_rank_change,
        "status mentions_china_rank_change"
      ),
      notes = tidyr::replace_na(notes, ""),
      counted = evidence_strength %in% c("strong", "moderate") &
        explicit_rank_language &
        mentions_china_rank_change &
        !stringr::str_detect(notes, "^DO_NOT_COUNT")
    )
  counts <- evidence |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      n_newspaper_sources_strong = sum(
        counted & source_type %in% c(
          "newspaper", "national_news_agency", "local_news", "business_news"
        )
      ),
      n_official_sources_strong = sum(
        counted & source_type %in% c(
          "official", "official_pdf", "official_statistics",
          "official_speech", "government_news"
        )
      ),
      n_total_strong_or_moderate = sum(counted),
      has_explicit_export_rank_label = any(counted & label_type == "export_rank"),
      has_explicit_generic_trade_partner_label = any(
        counted & label_type == "generic_trade_partner"
      ),
      has_official_uptake = n_official_sources_strong > 0L,
      has_newspaper_uptake = n_newspaper_sources_strong > 0L,
      n_independent_sources = dplyr::n_distinct(source_name[counted]),
      counted_labels = status_evidence_collapse_unique(
        rank_label_english[counted]
      ),
      .groups = "drop"
    )
  output <- universe |>
    dplyr::left_join(counts, by = "iso3c", relationship = "one-to-one") |>
    dplyr::mutate(
      dplyr::across(
        c(
          n_newspaper_sources_strong, n_official_sources_strong,
          n_total_strong_or_moderate, n_independent_sources
        ),
        ~ tidyr::replace_na(as.integer(.x), 0L)
      ),
      dplyr::across(
        c(
          has_explicit_export_rank_label,
          has_explicit_generic_trade_partner_label,
          has_official_uptake,
          has_newspaper_uptake
        ),
        ~ tidyr::replace_na(.x, FALSE)
      ),
      counted_labels = tidyr::replace_na(counted_labels, ""),
      salience_code_auto = dplyr::case_when(
        (
          n_total_strong_or_moderate >= 2L &
            n_independent_sources >= 2L &
            (has_newspaper_uptake | has_official_uptake)
        ) |
          (has_newspaper_uptake & has_official_uptake) ~ "high",
        n_total_strong_or_moderate >= 1L ~ "medium",
        TRUE ~ "unknown"
      ),
      negative_case_candidate_auto = "no",
      coding_rationale_auto = dplyr::case_when(
        salience_code_auto == "high" ~ paste0(
          n_total_strong_or_moderate,
          " strong/moderate independent first-window sources use explicit rank language",
          dplyr::if_else(
            nzchar(counted_labels),
            paste0(" (", counted_labels, ")."),
            "."
          )
        ),
        salience_code_auto == "medium" ~
          "One strong/moderate first-window source uses explicit rank language.",
        TRUE ~
          "No countable first-window source with explicit top-rank uptake was recovered."
      ),
      remaining_gaps_auto = dplyr::case_when(
        salience_code_auto == "high" ~
          "No major gap for salience coding; still verify archived raw files before manuscript use.",
        salience_code_auto == "medium" ~
          "Need a second independent first-window source to classify as high.",
        TRUE ~ "Additional local-language archive work required."
      )
    ) |>
    dplyr::left_join(overrides, by = "iso3c", relationship = "many-to-one") |>
    dplyr::mutate(
      salience_code = dplyr::coalesce(salience_code, salience_code_auto),
      negative_case_candidate = dplyr::coalesce(
        negative_case_candidate,
        negative_case_candidate_auto
      ),
      coding_rationale = dplyr::coalesce(coding_rationale, coding_rationale_auto),
      remaining_gaps = dplyr::coalesce(remaining_gaps, remaining_gaps_auto)
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      entry_year,
      n_newspaper_sources_strong,
      n_official_sources_strong,
      n_total_strong_or_moderate,
      has_explicit_export_rank_label,
      has_explicit_generic_trade_partner_label,
      has_official_uptake,
      has_newspaper_uptake,
      salience_code,
      negative_case_candidate,
      coding_rationale,
      remaining_gaps
    ) |>
    dplyr::arrange(entry_year, iso3c)
  output
}

status_evidence_window_ok <- function(publication_date, entry_year) {
  year <- suppressWarnings(as.integer(substr(publication_date, 1L, 4L)))
  !is.na(year) & year >= (entry_year - 1L) & year <= (entry_year + 1L)
}

build_ex_top1_incumbent_base_candidate <- function(universe,
                                                   incumbent_data,
                                                   source_path) {
  status_evidence_require_columns(
    incumbent_data,
    c(
      "iso3c", "t0", "displaced_partner", "displaced_partner_name",
      "displaced_export_share_t0_minus_1", "china_export_share_t0_minus_1"
    ),
    "former-incumbent input"
  )
  incumbent_data |>
    dplyr::filter(iso3c %in% universe$iso3c) |>
    dplyr::transmute(
      iso3c,
      entry_year = as.integer(t0),
      incumbent_partner_name = displaced_partner_name,
      incumbent_partner_iso3 = displaced_partner,
      incumbent_rank_year = as.integer(t0) - 1L,
      incumbent_rank_source_file = source_path,
      incumbent_export_share = as.numeric(displaced_export_share_t0_minus_1),
      china_export_share = as.numeric(china_export_share_t0_minus_1)
    ) |>
    dplyr::arrange(entry_year, iso3c)
}

build_ex_top1_country_codes_candidate <- function(universe,
                                                  source,
                                                  incumbent_base,
                                                  annotations) {
  evidence <- source |>
    dplyr::mutate(
      entry_year = as.integer(entry_year),
      evidence_year = as.integer(evidence_year),
      eligible_source = status_evidence_bool(
        eligible_source,
        "ex_top1 eligible_source"
      ),
      explicit_rank_language = status_evidence_bool(
        explicit_rank_language,
        "ex_top1 explicit_rank_language"
      ),
      mentions_incumbent_trade = status_evidence_bool(
        mentions_incumbent_trade,
        "ex_top1 mentions_incumbent_trade"
      ),
      count_for_benchmark = status_evidence_bool(
        count_for_benchmark,
        "ex_top1 count_for_benchmark"
      ),
      notes = tidyr::replace_na(notes, ""),
      in_window = status_evidence_window_ok(publication_date, entry_year),
      countable = count_for_benchmark & eligible_source & in_window &
        evidence_strength %in% c("strong", "moderate") &
        !stringr::str_detect(notes, "^DO_NOT_COUNT"),
      broad_trade_partner_context = eligible_source & in_window &
        evidence_strength %in% c("strong", "moderate") &
        label_type == "broad_trade_partner_rank",
      rank_or_displacement = countable & explicit_rank_language &
        label_type %in% c(
          "incumbent_export_rank", "incumbent_trade_rank", "displacement"
        ),
      trade_only = countable & mentions_incumbent_trade &
        label_type == "trade_coverage"
    )
  counts <- evidence |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(
      n_sources_total = dplyr::n(),
      n_countable_sources = sum(countable),
      n_rank_or_displacement_sources = sum(rank_or_displacement),
      n_trade_coverage_sources = sum(trade_only),
      n_official_sources = sum(
        countable & source_type %in% c(
          "official_statistics", "official_report", "official_speech",
          "government_news"
        )
      ),
      n_news_sources = sum(
        countable & source_type %in% c(
          "local_news", "business_news", "national_news_agency"
        )
      ),
      n_broad_trade_partner_context_sources = sum(broad_trade_partner_context),
      n_independent_sources = dplyr::n_distinct(source_name[countable]),
      principal_sources = status_evidence_collapse_unique(source_name[countable]),
      principal_labels = status_evidence_collapse_unique(
        rank_label_english[rank_or_displacement]
      ),
      broad_trade_partner_context_sources = status_evidence_collapse_unique(
        source_name[broad_trade_partner_context]
      ),
      broad_trade_partner_context_labels = status_evidence_collapse_unique(
        rank_label_english[broad_trade_partner_context]
      ),
      .groups = "drop"
    )
  universe |>
    dplyr::left_join(
      incumbent_base,
      by = c("iso3c", "entry_year"),
      relationship = "one-to-one"
    ) |>
    dplyr::left_join(counts, by = "iso3c", relationship = "one-to-one") |>
    dplyr::mutate(
      dplyr::across(
        c(
          n_sources_total, n_countable_sources,
          n_rank_or_displacement_sources, n_trade_coverage_sources,
          n_official_sources, n_news_sources,
          n_broad_trade_partner_context_sources, n_independent_sources
        ),
        ~ tidyr::replace_na(as.integer(.x), 0L)
      ),
      dplyr::across(
        c(
          principal_sources, principal_labels,
          broad_trade_partner_context_sources,
          broad_trade_partner_context_labels
        ),
        ~ tidyr::replace_na(.x, "")
      ),
      incumbent_identification_code = dplyr::if_else(
        is.na(incumbent_partner_iso3) | !nzchar(incumbent_partner_iso3),
        "incumbent_unknown",
        "incumbent_identified"
      ),
      ex_top1_coverage_code = dplyr::case_when(
        incumbent_identification_code == "incumbent_unknown" ~ "unknown",
        n_rank_or_displacement_sources >= 2L &
          n_independent_sources >= 2L ~ "high",
        n_rank_or_displacement_sources >= 1L &
          n_news_sources >= 1L & n_official_sources >= 1L ~ "high",
        n_rank_or_displacement_sources >= 1L ~ "medium",
        n_trade_coverage_sources >= 2L & n_independent_sources >= 1L ~ "medium",
        TRUE ~ "unknown"
      ),
      coding_rationale = dplyr::case_when(
        ex_top1_coverage_code == "high" ~ paste0(
          n_rank_or_displacement_sources,
          " countable source(s) use rank/displacement language for the incumbent; sources: ",
          principal_sources,
          "."
        ),
        ex_top1_coverage_code == "medium" &
          n_rank_or_displacement_sources > n_independent_sources ~ paste0(
          n_rank_or_displacement_sources,
          " countable row(s) from one independent source/source family use incumbent rank/status language; source: ",
          principal_sources,
          "."
        ),
        ex_top1_coverage_code == "medium" &
          n_rank_or_displacement_sources >= 1L ~ paste0(
          "One countable source uses incumbent rank/status language; source: ",
          principal_sources,
          "."
        ),
        ex_top1_coverage_code == "medium" ~ paste0(
          "Multiple countable local/news sources cover trade with the incumbent but without a clear top-rank label; sources: ",
          principal_sources,
          "."
        ),
        incumbent_identification_code == "incumbent_unknown" ~
          "The incumbent partner could not be identified from the local diagnostic input.",
        TRUE ~
          "No countable local/official source establishes incumbent-rank uptake in the window."
      )
    ) |>
    dplyr::left_join(annotations, by = "iso3c", relationship = "one-to-one") |>
    dplyr::mutate(
      dplyr::across(
        c(
          principal_sources, principal_labels,
          broad_trade_partner_context_sources,
          broad_trade_partner_context_labels
        ),
        ~ dplyr::if_else(
          n_sources_total > 0L,
          .x,
          dplyr::na_if(.x, "")
        )
      )
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      entry_year,
      incumbent_identification_code,
      incumbent_partner_name,
      incumbent_partner_iso3,
      incumbent_rank_year,
      incumbent_rank_source_file,
      incumbent_export_share,
      china_export_share,
      n_sources_total,
      n_countable_sources,
      n_rank_or_displacement_sources,
      n_trade_coverage_sources,
      n_official_sources,
      n_news_sources,
      n_broad_trade_partner_context_sources,
      n_independent_sources,
      principal_sources,
      principal_labels,
      broad_trade_partner_context_sources,
      broad_trade_partner_context_labels,
      ex_top1_coverage_code,
      coding_rationale,
      remaining_gaps
    ) |>
    dplyr::arrange(entry_year, iso3c)
}

build_status_ex_top1_comparison_candidate <- function(ex_country,
                                                      status_country) {
  ex_country |>
    dplyr::left_join(
      status_country |>
        dplyr::select(
          iso3c,
          status_cue_salience = salience_code
        ),
      by = "iso3c",
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      implication_for_china_status_cue_absence = dplyr::case_when(
        status_cue_salience == "unknown" &
          ex_top1_coverage_code %in% c("high", "medium") ~
          "more_informative_absence",
        status_cue_salience == "unknown" &
          ex_top1_coverage_code %in% c("unknown", "low") ~
          "weak_observation",
        status_cue_salience %in% c("high", "medium") ~
          "china_status_cue_observed",
        TRUE ~ "not_applicable"
      )
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      entry_year,
      status_cue_salience,
      ex_top1_coverage_code,
      implication_for_china_status_cue_absence,
      incumbent_partner_name,
      incumbent_partner_iso3,
      incumbent_rank_year,
      incumbent_export_share,
      china_export_share,
      principal_sources,
      principal_labels,
      n_broad_trade_partner_context_sources,
      broad_trade_partner_context_sources,
      broad_trade_partner_context_labels,
      coding_rationale,
      remaining_gaps
    ) |>
    dplyr::arrange(entry_year, iso3c)
}

validate_status_evidence_derivations <- function(status_country,
                                                 ex_country,
                                                 comparison,
                                                 universe,
                                                 incumbent_base,
                                                 ex_source) {
  embedded_incumbent <- ex_source |>
    dplyr::transmute(
      iso3c,
      entry_year = as.integer(entry_year),
      incumbent_partner_name,
      incumbent_partner_iso3,
      incumbent_rank_year = as.integer(incumbent_rank_year),
      incumbent_export_share = as.numeric(incumbent_export_share),
      china_export_share = as.numeric(china_export_share)
    ) |>
    dplyr::distinct()
  incumbent_check <- embedded_incumbent |>
    dplyr::left_join(
      incumbent_base |>
        dplyr::select(
          iso3c,
          entry_year,
          incumbent_partner_name,
          incumbent_partner_iso3,
          incumbent_rank_year,
          incumbent_export_share,
          china_export_share
        ),
      by = c(
        "iso3c", "entry_year", "incumbent_partner_name",
        "incumbent_partner_iso3", "incumbent_rank_year"
      ),
      suffix = c("_ledger", "_input"),
      relationship = "many-to-one"
    ) |>
    dplyr::filter(
      is.na(incumbent_export_share_input) |
        is.na(china_export_share_input) |
        abs(incumbent_export_share_ledger - incumbent_export_share_input) > 1e-12 |
        abs(china_export_share_ledger - china_export_share_input) > 1e-12
    ) |>
    dplyr::select(
      iso3c,
      entry_year,
      incumbent_partner_name,
      incumbent_partner_iso3,
      incumbent_rank_year
    )
  tibble::tibble(
    validation = c(
      "derived_tables_have_14_rows",
      "derived_country_keys_unique",
      "derived_country_sets_identical",
      "status_codes_allowed",
      "ex_top1_codes_allowed",
      "implication_codes_allowed",
      "derived_years_match_universe",
      "embedded_incumbent_matches_frozen_input",
      "derived_counts_nonnegative"
    ),
    passed = c(
      nrow(status_country) == 14L && nrow(ex_country) == 14L &&
        nrow(comparison) == 14L,
      anyDuplicated(status_country$iso3c) == 0L &&
        anyDuplicated(ex_country$iso3c) == 0L &&
        anyDuplicated(comparison$iso3c) == 0L,
      setequal(status_country$iso3c, universe$iso3c) &&
        setequal(ex_country$iso3c, universe$iso3c) &&
        setequal(comparison$iso3c, universe$iso3c),
      all(status_country$salience_code %in% c("high", "medium", "low", "unknown")),
      all(ex_country$ex_top1_coverage_code %in% c("high", "medium", "low", "unknown")),
      all(comparison$implication_for_china_status_cue_absence %in% c(
        "china_status_cue_observed", "more_informative_absence", "weak_observation"
      )),
      identical(
        dplyr::arrange(dplyr::select(status_country, iso3c, entry_year), iso3c),
        dplyr::arrange(dplyr::select(universe, iso3c, entry_year), iso3c)
      ),
      nrow(incumbent_check) == 0L,
      all(status_country$n_total_strong_or_moderate >= 0L) &&
        all(ex_country$n_sources_total >= 0L) &&
        all(ex_country$n_countable_sources >= 0L)
    ),
    detail = c(
      paste0(nrow(status_country), "/", nrow(ex_country), "/", nrow(comparison)),
      "iso3c",
      paste(sort(universe$iso3c), collapse = ";"),
      paste(sort(unique(status_country$salience_code)), collapse = ";"),
      paste(sort(unique(ex_country$ex_top1_coverage_code)), collapse = ";"),
      paste(sort(unique(comparison$implication_for_china_status_cue_absence)), collapse = ";"),
      "iso3c-entry_year",
      paste0("unmatched=", nrow(incumbent_check)),
      "status and ex-top1 counts"
    )
  )
}

status_evidence_output_spec <- function(kind) {
  common <- list(
    status = list(
      integer = c(
        "entry_year", "n_newspaper_sources_strong",
        "n_official_sources_strong", "n_total_strong_or_moderate"
      ),
      logical = c(
        "has_explicit_export_rank_label",
        "has_explicit_generic_trade_partner_label",
        "has_official_uptake", "has_newspaper_uptake"
      ),
      double = character(),
      na = "",
      eol = "\r\n",
      hash = "ca2fb896d5a6c7614ce1ad7907368b409ecf209a97367d00b19236c70d709533"
    ),
    ex_top1 = list(
      integer = c(
        "entry_year", "incumbent_rank_year", "n_sources_total",
        "n_countable_sources", "n_rank_or_displacement_sources",
        "n_trade_coverage_sources", "n_official_sources", "n_news_sources",
        "n_broad_trade_partner_context_sources", "n_independent_sources"
      ),
      logical = character(),
      double = c("incumbent_export_share", "china_export_share"),
      na = "NA",
      eol = "\n",
      hash = "568e1a9f6461347de4a74abc5b26c32770c2220cdd286cb91bf655a4f56fdce4"
    ),
    comparison = list(
      integer = c(
        "entry_year", "incumbent_rank_year",
        "n_broad_trade_partner_context_sources"
      ),
      logical = character(),
      double = c("incumbent_export_share", "china_export_share"),
      na = "NA",
      eol = "\n",
      hash = "f45ae615f6c2e7f0fe7582f08878f64e7f77526bfe7557307d2319693e8925b9"
    )
  )
  if (!kind %in% names(common)) {
    stop("Unknown status-evidence output kind: ", kind, call. = FALSE)
  }
  common[[kind]]
}

status_evidence_expected_types <- function(data, kind) {
  spec <- status_evidence_output_spec(kind)
  expected <- stats::setNames(rep("character", ncol(data)), names(data))
  expected[spec$integer] <- "integer"
  expected[spec$logical] <- "logical"
  expected[spec$double] <- "double"
  expected
}

status_evidence_cast_reference <- function(reference, candidate, kind) {
  spec <- status_evidence_output_spec(kind)
  output <- reference
  for (column in names(output)) {
    if (column %in% spec$integer) {
      value <- output[[column]]
      missing <- is.na(value) | value %in% c("", "NA")
      parsed <- rep(NA_integer_, length(value))
      parsed[!missing] <- status_evidence_integer(
        value[!missing],
        paste0(kind, " reference ", column),
        0L,
        9999L
      )
      output[[column]] <- parsed
    } else if (column %in% spec$double) {
      value <- output[[column]]
      value[value %in% c("", "NA")] <- NA_character_
      output[[column]] <- suppressWarnings(as.numeric(value))
    } else if (column %in% spec$logical) {
      output[[column]] <- status_evidence_bool(
        output[[column]],
        paste0(kind, " reference ", column)
      )
    } else {
      missing_like <- output[[column]] %in% c("", "NA")
      output[[column]][missing_like & is.na(candidate[[column]])] <- NA_character_
    }
  }
  output
}

status_evidence_serialize_output <- function(data, kind) {
  spec <- status_evidence_output_spec(kind)
  output <- data
  if (identical(kind, "status")) {
    logical_columns <- names(output)[vapply(output, is.logical, logical(1))]
    output <- output |>
      dplyr::mutate(
        dplyr::across(
          dplyr::all_of(logical_columns),
          ~ tolower(as.character(.x))
        )
      )
  }
  text <- readr::format_csv(output, na = spec$na, eol = "\n")
  if (identical(spec$eol, "\r\n")) {
    text <- gsub("\n", "\r\n", text, fixed = TRUE)
  }
  charToRaw(text)
}

status_evidence_raw_sha256 <- function(value) {
  digest::digest(value, algo = "sha256", serialize = FALSE)
}

status_evidence_frames_equal <- function(candidate, reference) {
  if (!identical(names(candidate), names(reference)) ||
      nrow(candidate) != nrow(reference)) {
    return(FALSE)
  }
  checks <- vapply(
    names(candidate),
    function(column) {
      x <- candidate[[column]]
      y <- reference[[column]]
      if (!identical(typeof(x), typeof(y)) ||
          !identical(is.na(x), is.na(y))) {
        return(FALSE)
      }
      observed <- !is.na(x)
      if (is.double(x)) {
        return(all(abs(x[observed] - y[observed]) <= 1e-12))
      }
      identical(x[observed], y[observed])
    },
    logical(1)
  )
  all(checks)
}

validate_status_evidence_reference_equivalence <- function(candidate,
                                                           reference_file,
                                                           kind) {
  spec <- status_evidence_output_spec(kind)
  reference <- status_evidence_read_character_csv(reference_file)
  names_match <- identical(names(candidate), names(reference))
  types <- vapply(candidate, typeof, character(1))
  expected_types <- status_evidence_expected_types(candidate, kind)
  type_contract_matches <- identical(types, expected_types)
  values_match <- FALSE
  if (names_match && type_contract_matches) {
    cast_reference <- status_evidence_cast_reference(reference, candidate, kind)
    values_match <- status_evidence_frames_equal(candidate, cast_reference)
  }
  candidate_hash <- status_evidence_raw_sha256(
    status_evidence_serialize_output(candidate, kind)
  )
  tibble::tibble(
    validation = paste0(
      kind,
      c(
        "_reference_file_hash_matches",
        "_reference_names_and_order_match",
        "_candidate_type_contract_matches",
        "_reference_values_match",
        "_candidate_serialized_hash_matches"
      )
    ),
    passed = c(
      identical(status_evidence_file_sha256(reference_file), spec$hash),
      names_match,
      type_contract_matches,
      values_match,
      identical(candidate_hash, spec$hash)
    ),
    detail = c(
      basename(reference_file),
      paste(names(candidate), collapse = ";"),
      paste(types, collapse = ";"),
      paste0("rows=", nrow(candidate)),
      candidate_hash
    )
  )
}

status_evidence_reference_validation_names <- function() {
  unlist(lapply(
    c("status", "ex_top1", "comparison"),
    function(kind) {
      paste0(
        kind,
        c(
          "_reference_file_hash_matches",
          "_reference_names_and_order_match",
          "_candidate_type_contract_matches",
          "_reference_values_match",
          "_candidate_serialized_hash_matches"
        )
      )
    }
  ), use.names = FALSE)
}

status_evidence_validation_names <- function() {
  c(
    "audit_universe_has_14_unique_cases",
    "audit_universe_years_valid",
    "audit_universe_iso3c_valid",
    "audit_universe_exact_contract",
    "status_overrides_unique_and_in_universe",
    "status_override_codes_allowed",
    "ex_annotations_cover_universe_once",
    "derived_tables_have_14_rows",
    "derived_country_keys_unique",
    "derived_country_sets_identical",
    "status_codes_allowed",
    "ex_top1_codes_allowed",
    "implication_codes_allowed",
    "derived_years_match_universe",
    "embedded_incumbent_matches_frozen_input",
    "derived_counts_nonnegative",
    status_evidence_reference_validation_names()
  )
}

assert_status_evidence_validation <- function(validation, required = NULL) {
  status_evidence_require_columns(
    validation,
    c("validation", "passed", "detail"),
    "status-evidence validation"
  )
  if (anyDuplicated(validation$validation)) {
    stop("Status-evidence validation names are duplicated.", call. = FALSE)
  }
  if (!is.null(required)) {
    missing <- setdiff(required, validation$validation)
    if (length(missing) > 0L) {
      stop(
        "Status-evidence validation is missing required checks: ",
        paste(missing, collapse = ", "),
        call. = FALSE
      )
    }
  }
  failed <- is.na(validation$passed) | !validation$passed
  if (any(failed)) {
    stop(
      "Status-evidence validation failed: ",
      paste(validation$validation[failed], collapse = ", "),
      call. = FALSE
    )
  }
  validation
}

write_status_evidence_csv_candidate <- function(data, path, kind) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(status_evidence_serialize_output(data, kind), connection)
  path
}
