#!/usr/bin/env Rscript

# Comparator-anchor diagnostic for Brazil's post-2009 UNGA vote movement.
# The diagnostic asks whether Brazil moved closer to China more than it moved
# toward alternative BRICS, G77, Latin American, or U.S. anchors.
# It reads the preserved unvotes CRAN tarball and does not touch targets.

options(scipen = 999)

set.seed(20260525)

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
  library(ggplot2)
  library(here)
  library(lubridate)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
})

run_date <- as.character(Sys.Date())
run_timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
script_path <- "scripts/diagnostics/diagnose_unga_comparator_anchor_convergence.R"
analysis_years <- 2005:2012
post_start_year <- 2009L

raw_tarball <- here::here("data", "raw", "unvotes", "unvotes_0.3.0.tar.gz")
processed_dir <- here::here("data", "processed", "unvotes")
report_dir <- here::here("quality_reports", "unga_comparator_anchor_convergence")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

path_processed <- function(filename) file.path(processed_dir, filename)
path_report <- function(filename) file.path(report_dir, filename)

paths <- list(
  resolution_metrics = path_processed("brazil_comparator_anchor_resolution_metrics_2005_2012.csv"),
  prepost_summary = path_processed("brazil_comparator_anchor_prepost_summary_2005_2012.csv"),
  relative_change = path_processed("brazil_comparator_anchor_relative_change_2005_2012.csv"),
  common_support_relative_change = path_processed("brazil_comparator_anchor_common_support_relative_change_2005_2012.csv"),
  annual_summary = path_processed("brazil_comparator_anchor_annual_summary_2005_2012.csv"),
  anchor_members = path_processed("brazil_comparator_anchor_members_2005_2012.csv"),
  validation = path_report("brazil_comparator_anchor_validation_2005_2012.csv"),
  session_info = path_report("brazil_comparator_anchor_session_info_2005_2012.txt"),
  manifest = path_report("brazil_comparator_anchor_output_manifest_2005_2012.csv"),
  note = path_report(paste0(run_date, "_unga_comparator_anchor_convergence_note.md")),
  figure_png = path_report("figura_1_relative_china_proximity_by_anchor_2005_2012.png"),
  figure_pdf = path_report("figura_1_relative_china_proximity_by_anchor_2005_2012.pdf")
)

source_url <- "https://cran.r-project.org/src/contrib/unvotes_0.3.0.tar.gz"
g77_members_url <- "https://www.g77.org/geninfo/members.htm"
g77_about_url <- "https://www.g77.org/doc/"
access_date <- run_date

valid_vote_values <- c("yes", "no", "abstain")

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
    stringr::str_detect(issue, "Economic development") ~ "Economic development",
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

score_vote <- function(score) {
  dplyr::case_when(
    is.na(score) ~ NA_character_,
    score == -1 ~ "no",
    score == 0 ~ "abstain",
    score == 1 ~ "yes",
    TRUE ~ NA_character_
  )
}

ordinal_similarity <- function(score_a, score_b) {
  dplyr::if_else(
    is.na(score_a) | is.na(score_b),
    NA_real_,
    1 - abs(score_a - score_b) / 2
  )
}

make_doc_symbol <- function(unres) {
  dplyr::if_else(
    is.na(unres) | unres == "",
    NA_character_,
    stringr::str_replace(unres, "^R/", "A/RES/")
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

modal_vote_summary <- function(scores) {
  scores <- scores[!is.na(scores)]
  if (length(scores) == 0L) {
    return(tibble::tibble(
      modal_score = NA_real_,
      modal_vote = NA_character_,
      modal_tied = NA,
      modal_top_count = NA_integer_,
      modal_top_share = NA_real_
    ))
  }

  counts <- tibble::tibble(score = scores) |>
    dplyr::count(score, name = "n") |>
    dplyr::arrange(dplyr::desc(n), score)

  top_n <- counts$n[[1]]
  top <- counts |>
    dplyr::filter(n == top_n)
  tied <- nrow(top) > 1L
  modal_score <- if (tied) NA_real_ else top$score[[1]]

  tibble::tibble(
    modal_score = modal_score,
    modal_vote = score_vote(modal_score),
    modal_tied = tied,
    modal_top_count = top_n,
    modal_top_share = top_n / length(scores)
  )
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "", paste0(formatC(100 * x, digits = digits, format = "f"), "%"))
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

g77_member_names <- c(
  "Afghanistan", "Algeria", "Angola", "Antigua and Barbuda",
  "Argentina", "Bahamas", "Bahrain", "Bangladesh", "Barbados",
  "Belize", "Benin", "Bhutan", "Bolivia", "Bosnia and Herzegovina",
  "Botswana", "Brazil", "Brunei Darussalam", "Burkina Faso",
  "Burundi", "Cabo Verde", "Cambodia", "Cameroon",
  "Central African Republic", "Chad", "Chile", "China", "Colombia",
  "Comoros", "Congo", "Costa Rica", "Cote d'Ivoire", "Cuba",
  "Democratic People's Republic of Korea", "Democratic Republic of the Congo",
  "Djibouti", "Dominica", "Dominican Republic", "Ecuador", "Egypt",
  "El Salvador", "Equatorial Guinea", "Eritrea", "Eswatini", "Ethiopia",
  "Fiji", "Gabon", "Gambia", "Ghana", "Grenada", "Guatemala",
  "Guinea", "Guinea-Bissau", "Guyana", "Haiti", "Honduras",
  "India", "Indonesia", "Iran", "Iraq", "Jamaica", "Jordan",
  "Kenya", "Kuwait", "Lao People's Democratic Republic", "Lebanon",
  "Lesotho", "Liberia", "Libya", "Madagascar", "Malawi", "Malaysia",
  "Maldives", "Mali", "Mauritania", "Mauritius", "Micronesia",
  "Mongolia", "Morocco", "Mozambique", "Myanmar", "Namibia", "Nauru",
  "Nepal", "Nicaragua", "Niger", "Nigeria", "Oman", "Pakistan",
  "Palestine", "Panama", "Papua New Guinea", "Paraguay", "Peru",
  "Philippines", "Qatar", "Rwanda", "Saint Kitts and Nevis",
  "Saint Lucia", "Saint Vincent and the Grenadines", "Samoa",
  "Sao Tome and Principe", "Saudi Arabia", "Senegal", "Seychelles",
  "Sierra Leone", "Singapore", "Solomon Islands", "Somalia",
  "South Africa", "South Sudan", "Sri Lanka", "Sudan", "Suriname",
  "Syrian Arab Republic", "Tajikistan", "Thailand", "Timor-Leste",
  "Togo", "Tonga", "Trinidad and Tobago", "Tunisia", "Turkmenistan",
  "Uganda", "United Arab Emirates", "United Republic of Tanzania",
  "Uruguay", "Vanuatu", "Venezuela", "Viet Nam", "Yemen", "Zambia",
  "Zimbabwe"
)

g77_custom_match <- c(
  "Brunei Darussalam" = "BRN",
  "Cabo Verde" = "CPV",
  "Congo" = "COG",
  "Cote d'Ivoire" = "CIV",
  "Democratic People's Republic of Korea" = "PRK",
  "Democratic Republic of the Congo" = "COD",
  "Eswatini" = "SWZ",
  "Iran" = "IRN",
  "Lao People's Democratic Republic" = "LAO",
  "Micronesia" = "FSM",
  "Palestine" = "PSE",
  "Saint Kitts and Nevis" = "KNA",
  "Saint Lucia" = "LCA",
  "Saint Vincent and the Grenadines" = "VCT",
  "Sao Tome and Principe" = "STP",
  "South Sudan" = "SSD",
  "Syrian Arab Republic" = "SYR",
  "Timor-Leste" = "TLS",
  "United Republic of Tanzania" = "TZA",
  "Venezuela" = "VEN",
  "Viet Nam" = "VNM"
)

g77_iso3c <- countrycode::countrycode(
  g77_member_names,
  origin = "country.name",
  destination = "iso3c",
  custom_match = g77_custom_match,
  warn = FALSE
) |>
  unique() |>
  stats::na.omit() |>
  as.character()

if (length(g77_iso3c) < 120L) {
  warning("G77 ISO3C vector has fewer than 120 mapped members; check hard-coded member names.")
}

tables <- load_unvotes_tables(raw_tarball)

issue_by_rcid <- tables$un_roll_call_issues |>
  dplyr::mutate(
    issue = clean_text(as.character(issue)),
    issue_family_single = map_issue_family(issue)
  ) |>
  dplyr::summarise(
    issue = paste(sort(unique(issue[!is.na(issue)])), collapse = "; "),
    issue_family = paste(sort(unique(issue_family_single[!is.na(issue_family_single)])), collapse = "; "),
    any_human_rights = any(issue_family_single == "Human rights", na.rm = TRUE),
    n_issue_codes = dplyr::n_distinct(issue[!is.na(issue)]),
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

roll_calls <- tables$un_roll_calls |>
  dplyr::mutate(
    year = lubridate::year(date),
    short = clean_text(short),
    descr = clean_text(descr),
    doc_symbol = make_doc_symbol(unres)
  ) |>
  dplyr::filter(year %in% analysis_years) |>
  dplyr::select(
    rcid,
    session,
    importantvote,
    date,
    year,
    unres,
    amend,
    para,
    short,
    descr,
    doc_symbol
  )

vote_long <- tables$un_votes |>
  dplyr::mutate(
    vote = as.character(vote),
    iso3c = countrycode::countrycode(
      country_code,
      origin = "iso2c",
      destination = "iso3c",
      custom_match = c("KV" = "XKX"),
      warn = FALSE
    ),
    vote_score = vote_score(vote)
  ) |>
  dplyr::inner_join(roll_calls |> dplyr::select(rcid, year), by = "rcid") |>
  dplyr::filter(
    vote %in% valid_vote_values,
    !is.na(iso3c),
    !is.na(vote_score)
  ) |>
  dplyr::select(rcid, year, country, country_code, iso3c, vote, vote_score) |>
  dplyr::distinct(rcid, iso3c, .keep_all = TRUE)

reference_votes <- vote_long |>
  dplyr::filter(iso3c %in% c("BRA", "CHN", "USA")) |>
  dplyr::select(rcid, iso3c, vote, vote_score) |>
  tidyr::pivot_wider(
    names_from = iso3c,
    values_from = c(vote, vote_score),
    names_sep = "_"
  ) |>
  dplyr::rename(
    vote_brazil = vote_BRA,
    vote_china = vote_CHN,
    vote_usa = vote_USA,
    brazil_score = vote_score_BRA,
    china_score = vote_score_CHN,
    usa_score = vote_score_USA
  ) |>
  dplyr::filter(!is.na(brazil_score), !is.na(china_score)) |>
  dplyr::mutate(
    agreement_brazil_china = as.integer(brazil_score == china_score),
    ordinal_similarity_brazil_china = ordinal_similarity(brazil_score, china_score),
    china_usa_divergent = !is.na(usa_score) & china_score != usa_score,
    china_usa_strong_divergent = !is.na(usa_score) & abs(china_score - usa_score) == 2
  )

base_resolutions <- reference_votes |>
  dplyr::inner_join(roll_calls, by = "rcid") |>
  dplyr::left_join(issue_by_rcid, by = "rcid") |>
  dplyr::mutate(
    period = dplyr::if_else(year < post_start_year, "Pre-2009", "Post-2009"),
    post_2009 = as.integer(year >= post_start_year),
    issue = dplyr::coalesce(issue, "Uncoded"),
    issue_family = dplyr::coalesce(issue_family, "Other / uncoded"),
    issue_domain = dplyr::coalesce(issue_domain, "Non-human rights"),
    n_issue_codes = tidyr::replace_na(n_issue_codes, 0L),
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
  )

country_catalog <- countrycode::codelist |>
  dplyr::filter(!is.na(iso3c)) |>
  dplyr::distinct(iso3c, .keep_all = TRUE) |>
  dplyr::select(iso3c, country_name = country.name.en, region, region23, continent)

valid_un_voting_iso3c <- vote_long |>
  dplyr::distinct(iso3c) |>
  dplyr::pull(iso3c)

latin_america_peers <- country_catalog |>
  dplyr::filter(region23 %in% c("South America", "Central America")) |>
  dplyr::filter(
    !iso3c %in% c("BRA", "CHN"),
    iso3c %in% valid_un_voting_iso3c
  ) |>
  dplyr::pull(iso3c) |>
  unique()

anchor_members <- dplyr::bind_rows(
  tibble::tribble(
    ~anchor_id, ~anchor_label, ~anchor_type, ~member_iso3c, ~start_year, ~end_year,
    "china", "China", "individual", "CHN", min(analysis_years), max(analysis_years),
    "russia", "Russia", "individual", "RUS", min(analysis_years), max(analysis_years),
    "india", "India", "individual", "IND", min(analysis_years), max(analysis_years),
    "south_africa", "South Africa", "individual", "ZAF", min(analysis_years), max(analysis_years),
    "united_states", "United States", "individual", "USA", min(analysis_years), max(analysis_years),
    "brics_peers_fixed", "BRICS peers excluding Brazil and China, fixed", "bloc_modal", "RUS", min(analysis_years), max(analysis_years),
    "brics_peers_fixed", "BRICS peers excluding Brazil and China, fixed", "bloc_modal", "IND", min(analysis_years), max(analysis_years),
    "brics_peers_fixed", "BRICS peers excluding Brazil and China, fixed", "bloc_modal", "ZAF", min(analysis_years), max(analysis_years),
    "brics_peers_historical", "BRICS peers excluding Brazil and China, historical", "bloc_modal", "RUS", min(analysis_years), max(analysis_years),
    "brics_peers_historical", "BRICS peers excluding Brazil and China, historical", "bloc_modal", "IND", min(analysis_years), max(analysis_years),
    "brics_peers_historical", "BRICS peers excluding Brazil and China, historical", "bloc_modal", "ZAF", 2011L, max(analysis_years)
  ),
  tibble::tibble(
    anchor_id = "g77_fixed",
    anchor_label = "G77 modal vote excluding Brazil and China, fixed official member list",
    anchor_type = "bloc_modal",
    member_iso3c = setdiff(g77_iso3c, c("BRA", "CHN")),
    start_year = min(analysis_years),
    end_year = max(analysis_years)
  ),
  tibble::tibble(
    anchor_id = "latin_america_peers",
    anchor_label = "Latin American peer modal vote excluding Brazil, non-Caribbean",
    anchor_type = "bloc_modal",
    member_iso3c = latin_america_peers,
    start_year = min(analysis_years),
    end_year = max(analysis_years)
  )
) |>
  dplyr::left_join(country_catalog, by = c("member_iso3c" = "iso3c")) |>
  dplyr::mutate(
    member_name = dplyr::coalesce(country_name, member_iso3c),
    construction_note = dplyr::case_when(
      anchor_id == "china" ~ "Primary China benchmark.",
      anchor_type == "individual" ~ "Individual-country pairwise anchor.",
      anchor_id == "brics_peers_fixed" ~
        "Fixed Russia-India-South Africa peer set, excluding Brazil and China.",
      anchor_id == "brics_peers_historical" ~
        "Historical peer set: Russia and India in 2005-2010; South Africa added from 2011.",
      anchor_id == "g77_fixed" ~
        "Fixed official Group of 77 member list, excluding Brazil and China; not year-varying.",
      anchor_id == "latin_america_peers" ~
        "Countrycode South/Central America peer set, excluding Brazil, Caribbean countries, and non-voting territories absent from unvotes.",
      TRUE ~ ""
    )
  ) |>
  dplyr::select(
    anchor_id,
    anchor_label,
    anchor_type,
    member_iso3c,
    member_name,
    start_year,
    end_year,
    construction_note
  ) |>
  dplyr::arrange(anchor_id, member_iso3c)

readr::write_csv(anchor_members, paths$anchor_members, na = "")

active_anchor_members <- anchor_members |>
  dplyr::select(anchor_id, anchor_label, anchor_type, member_iso3c, start_year, end_year) |>
  tidyr::crossing(roll_calls |> dplyr::distinct(rcid, year)) |>
  dplyr::filter(year >= start_year, year <= end_year)

anchor_member_votes <- active_anchor_members |>
  dplyr::left_join(
    vote_long |>
      dplyr::select(rcid, year, iso3c, country, country_code, vote, vote_score),
    by = c("rcid", "year", "member_iso3c" = "iso3c")
  )

anchor_scores <- anchor_member_votes |>
  dplyr::summarise(
    anchor_members_total_n = dplyr::n_distinct(member_iso3c),
    anchor_members_valid_n = sum(!is.na(vote_score)),
    anchor_members_valid_iso3c = paste(sort(unique(member_iso3c[!is.na(vote_score)])), collapse = ";"),
    anchor_median_score = stats::median(vote_score, na.rm = TRUE),
    anchor_mean_score = mean(vote_score, na.rm = TRUE),
    .by = c(rcid, year, anchor_id, anchor_label, anchor_type)
  ) |>
  dplyr::left_join(
    anchor_member_votes |>
      dplyr::summarise(modal_vote_summary(vote_score), .by = c(rcid, anchor_id)),
    by = c("rcid", "anchor_id")
  ) |>
  dplyr::mutate(
    min_valid_members_required = dplyr::case_when(
      anchor_id %in% c("china", "russia", "india", "south_africa", "united_states") ~ 1L,
      anchor_id %in% c("brics_peers_fixed", "brics_peers_historical") ~ 2L,
      anchor_id == "latin_america_peers" ~ 5L,
      anchor_id == "g77_fixed" ~ 20L,
      TRUE ~ 1L
    ),
    anchor_position_valid = anchor_members_valid_n >= min_valid_members_required &
      !is.na(modal_score) &
      !isTRUE(modal_tied)
  )

resolution_metrics <- base_resolutions |>
  dplyr::inner_join(anchor_scores, by = c("rcid", "year")) |>
  dplyr::mutate(
    anchor_modal_score = dplyr::if_else(anchor_position_valid, modal_score, NA_real_),
    anchor_modal_vote = dplyr::if_else(anchor_position_valid, modal_vote, NA_character_),
    agreement_brazil_anchor = dplyr::if_else(
      anchor_position_valid,
      as.integer(brazil_score == anchor_modal_score),
      NA_integer_
    ),
    ordinal_similarity_brazil_anchor = ordinal_similarity(brazil_score, anchor_median_score),
    relative_agreement_china_minus_anchor =
      agreement_brazil_china - agreement_brazil_anchor,
    relative_similarity_china_minus_anchor =
      ordinal_similarity_brazil_china - ordinal_similarity_brazil_anchor,
    source = paste0(
      "unvotes 0.3.0 CRAN tarball (", source_url,
      "), accessed ", access_date,
      "; raw preserved at data/raw/unvotes/unvotes_0.3.0.tar.gz"
    )
  ) |>
  dplyr::filter(anchor_id != "china") |>
  dplyr::arrange(year, rcid, anchor_id) |>
  dplyr::select(
    rcid,
    doc_symbol,
    unres,
    session,
    date,
    year,
    period,
    post_2009,
    importantvote,
    amend,
    para,
    short,
    descr,
    issue,
    issue_family,
    issue_domain,
    any_human_rights,
    n_issue_codes,
    vote_brazil,
    vote_china,
    vote_usa,
    brazil_score,
    china_score,
    usa_score,
    china_usa_divergent,
    china_usa_strong_divergent,
    agreement_brazil_china,
    ordinal_similarity_brazil_china,
    anchor_id,
    anchor_label,
    anchor_type,
    anchor_members_total_n,
    anchor_members_valid_n,
    min_valid_members_required,
    anchor_members_valid_iso3c,
    anchor_position_valid,
    anchor_modal_tied = modal_tied,
    anchor_modal_top_count = modal_top_count,
    anchor_modal_top_share = modal_top_share,
    anchor_modal_vote,
    anchor_modal_score,
    anchor_median_score,
    anchor_mean_score,
    agreement_brazil_anchor,
    ordinal_similarity_brazil_anchor,
    relative_agreement_china_minus_anchor,
    relative_similarity_china_minus_anchor,
    document_url,
    vote_record_url,
    source
  )

sample_conditions <- tibble::tribble(
  ~sample_id, ~sample_label, ~issue_filter, ~divergence_filter,
  "all_votes", "All valid Brazil-China votes", "all", "all",
  "human_rights", "Human-rights votes", "human_rights", "all",
  "china_usa_divergent", "China-U.S. divergent votes", "all", "china_usa_divergent",
  "china_usa_strong_divergent", "China-U.S. strong yes-no divergent votes", "all", "china_usa_strong_divergent",
  "human_rights_china_usa_divergent", "Human-rights votes where China and the United States diverged", "human_rights", "china_usa_divergent",
  "human_rights_china_usa_strong_divergent", "Human-rights votes where China and the United States strongly diverged", "human_rights", "china_usa_strong_divergent"
)

metrics_by_sample <- dplyr::bind_rows(lapply(seq_len(nrow(sample_conditions)), function(i) {
  condition <- sample_conditions[i, ]
  sample_data <- resolution_metrics

  if (condition$issue_filter == "human_rights") {
    sample_data <- sample_data |>
      dplyr::filter(issue_domain == "Human rights")
  }

  if (condition$divergence_filter == "china_usa_divergent") {
    sample_data <- sample_data |>
      dplyr::filter(china_usa_divergent)
  }

  if (condition$divergence_filter == "china_usa_strong_divergent") {
    sample_data <- sample_data |>
      dplyr::filter(china_usa_strong_divergent)
  }

  sample_data |>
    dplyr::mutate(
      sample_id = condition$sample_id,
      sample_label = condition$sample_label,
      .before = 1
    )
}))

summarise_period <- function(data) {
  data |>
    dplyr::filter(anchor_position_valid) |>
    dplyr::summarise(
      n_resolution_anchor_rows = dplyr::n(),
      n_resolutions = dplyr::n_distinct(rcid),
      n_years = dplyr::n_distinct(year),
      mean_brazil_china_agreement = mean(agreement_brazil_china, na.rm = TRUE),
      mean_brazil_anchor_agreement = mean(agreement_brazil_anchor, na.rm = TRUE),
      mean_relative_agreement_china_minus_anchor =
        mean(relative_agreement_china_minus_anchor, na.rm = TRUE),
      mean_brazil_china_similarity = mean(ordinal_similarity_brazil_china, na.rm = TRUE),
      mean_brazil_anchor_similarity = mean(ordinal_similarity_brazil_anchor, na.rm = TRUE),
      mean_relative_similarity_china_minus_anchor =
        mean(relative_similarity_china_minus_anchor, na.rm = TRUE),
      n_anchor_ties_omitted = sum(anchor_modal_tied %in% TRUE, na.rm = TRUE),
      mean_anchor_valid_members = mean(anchor_members_valid_n, na.rm = TRUE),
      .by = c(sample_id, sample_label, anchor_id, anchor_label, anchor_type, period)
    ) |>
    dplyr::arrange(sample_id, anchor_id, period)
}

prepost_summary <- summarise_period(metrics_by_sample)

make_relative_change <- function(period_summary) {
  period_summary |>
    dplyr::mutate(
      period_key = dplyr::case_when(
        period == "Pre-2009" ~ "pre_2009",
        period == "Post-2009" ~ "post_2009",
        TRUE ~ stringr::str_replace_all(stringr::str_to_lower(period), "[^a-z0-9]+", "_")
      )
    ) |>
    dplyr::select(
      sample_id,
      sample_label,
      anchor_id,
      anchor_label,
      anchor_type,
      period_key,
      n_resolutions,
      mean_brazil_china_agreement,
      mean_brazil_anchor_agreement,
      mean_relative_agreement_china_minus_anchor,
      mean_brazil_china_similarity,
      mean_brazil_anchor_similarity,
      mean_relative_similarity_china_minus_anchor,
      mean_anchor_valid_members
    ) |>
    tidyr::pivot_wider(
      names_from = period_key,
      values_from = c(
        n_resolutions,
        mean_brazil_china_agreement,
        mean_brazil_anchor_agreement,
        mean_relative_agreement_china_minus_anchor,
        mean_brazil_china_similarity,
        mean_brazil_anchor_similarity,
        mean_relative_similarity_china_minus_anchor,
        mean_anchor_valid_members
      ),
      names_glue = "{.value}_{period_key}"
    ) |>
    dplyr::mutate(
      change_brazil_china_agreement =
        mean_brazil_china_agreement_post_2009 -
        mean_brazil_china_agreement_pre_2009,
      change_brazil_anchor_agreement =
        mean_brazil_anchor_agreement_post_2009 -
        mean_brazil_anchor_agreement_pre_2009,
      change_relative_agreement_china_minus_anchor =
        mean_relative_agreement_china_minus_anchor_post_2009 -
        mean_relative_agreement_china_minus_anchor_pre_2009,
      change_brazil_china_similarity =
        mean_brazil_china_similarity_post_2009 -
        mean_brazil_china_similarity_pre_2009,
      change_brazil_anchor_similarity =
        mean_brazil_anchor_similarity_post_2009 -
        mean_brazil_anchor_similarity_pre_2009,
      change_relative_similarity_china_minus_anchor =
        mean_relative_similarity_china_minus_anchor_post_2009 -
        mean_relative_similarity_china_minus_anchor_pre_2009,
      interpretation = dplyr::case_when(
        is.na(change_relative_agreement_china_minus_anchor) ~ "Insufficient support",
        change_relative_agreement_china_minus_anchor > 0.05 ~
          "Relative China-specific movement",
        change_relative_agreement_china_minus_anchor < -0.05 ~
          "Comparator movement at least as strong",
        TRUE ~ "Similar China and comparator movement"
      )
    ) |>
    dplyr::arrange(sample_id, anchor_id)
}

relative_change <- make_relative_change(prepost_summary)

expected_anchor_ids <- sort(unique(resolution_metrics$anchor_id))

common_support_rcids <- metrics_by_sample |>
  dplyr::summarise(
    anchors_present = dplyr::n_distinct(anchor_id),
    anchors_valid = sum(anchor_position_valid, na.rm = TRUE),
    .by = c(sample_id, rcid)
  ) |>
  dplyr::filter(
    anchors_present == length(expected_anchor_ids),
    anchors_valid == length(expected_anchor_ids)
  ) |>
  dplyr::select(sample_id, rcid)

common_support_metrics <- metrics_by_sample |>
  dplyr::semi_join(common_support_rcids, by = c("sample_id", "rcid"))

common_support_prepost_summary <- summarise_period(common_support_metrics)
common_support_relative_change <- make_relative_change(common_support_prepost_summary)

annual_summary <- metrics_by_sample |>
  dplyr::filter(anchor_position_valid) |>
  dplyr::summarise(
    n_resolutions = dplyr::n_distinct(rcid),
    mean_brazil_china_agreement = mean(agreement_brazil_china, na.rm = TRUE),
    mean_brazil_anchor_agreement = mean(agreement_brazil_anchor, na.rm = TRUE),
    mean_relative_agreement_china_minus_anchor =
      mean(relative_agreement_china_minus_anchor, na.rm = TRUE),
    mean_brazil_china_similarity = mean(ordinal_similarity_brazil_china, na.rm = TRUE),
    mean_brazil_anchor_similarity = mean(ordinal_similarity_brazil_anchor, na.rm = TRUE),
    mean_relative_similarity_china_minus_anchor =
      mean(relative_similarity_china_minus_anchor, na.rm = TRUE),
    mean_anchor_valid_members = mean(anchor_members_valid_n, na.rm = TRUE),
    .by = c(sample_id, sample_label, anchor_id, anchor_label, anchor_type, year, period)
  ) |>
  dplyr::arrange(sample_id, anchor_id, year)

readr::write_csv(resolution_metrics, paths$resolution_metrics, na = "")
readr::write_csv(prepost_summary, paths$prepost_summary, na = "")
readr::write_csv(relative_change, paths$relative_change, na = "")
readr::write_csv(common_support_relative_change, paths$common_support_relative_change, na = "")
readr::write_csv(annual_summary, paths$annual_summary, na = "")

issue_coverage <- base_resolutions |>
  dplyr::distinct(rcid, n_issue_codes, issue_domain, china_usa_divergent, china_usa_strong_divergent) |>
  dplyr::summarise(
    n_resolutions = dplyr::n(),
    n_uncoded = sum(n_issue_codes == 0L, na.rm = TRUE),
    n_human_rights = sum(issue_domain == "Human rights", na.rm = TRUE),
    n_china_usa_divergent = sum(china_usa_divergent, na.rm = TRUE),
    n_china_usa_strong_divergent = sum(china_usa_strong_divergent, na.rm = TRUE),
    n_human_rights_china_usa_divergent =
      sum(issue_domain == "Human rights" & china_usa_divergent, na.rm = TRUE),
    n_human_rights_china_usa_strong_divergent =
      sum(issue_domain == "Human rights" & china_usa_strong_divergent, na.rm = TRUE)
  )

validation <- tibble::tribble(
  ~check, ~status, ~value,
  "raw_tarball_exists", file.exists(raw_tarball), raw_tarball,
  "analysis_year_min", min(analysis_years) == 2005L, as.character(min(analysis_years)),
  "analysis_year_max", max(analysis_years) == 2012L, as.character(max(analysis_years)),
  "post_2009_start", post_start_year == 2009L, as.character(post_start_year),
  "base_has_brazil_china_valid_votes", nrow(base_resolutions) > 0L, as.character(nrow(base_resolutions)),
  "no_targets_read_or_written", TRUE, "Script reads raw unvotes tarball and CSV inputs only.",
  "all_relative_agreement_in_bounds",
  all(is.na(resolution_metrics$relative_agreement_china_minus_anchor) |
        resolution_metrics$relative_agreement_china_minus_anchor %in% c(-1, 0, 1)),
  paste(range(resolution_metrics$relative_agreement_china_minus_anchor, na.rm = TRUE), collapse = " to "),
  "all_similarity_in_bounds",
  all(is.na(resolution_metrics$ordinal_similarity_brazil_anchor) |
        (resolution_metrics$ordinal_similarity_brazil_anchor >= 0 &
           resolution_metrics$ordinal_similarity_brazil_anchor <= 1)),
  paste(range(resolution_metrics$ordinal_similarity_brazil_anchor, na.rm = TRUE), collapse = " to "),
  "human_rights_divergent_sample_nonempty",
  any(metrics_by_sample$sample_id == "human_rights_china_usa_divergent"),
  as.character(sum(metrics_by_sample$sample_id == "human_rights_china_usa_divergent")),
  "g77_member_count_after_excluding_brazil_china",
  sum(anchor_members$anchor_id == "g77_fixed") >= 100L,
  as.character(sum(anchor_members$anchor_id == "g77_fixed")),
  "latin_peer_count_after_excluding_brazil",
  sum(anchor_members$anchor_id == "latin_america_peers") >= 10L,
  as.character(sum(anchor_members$anchor_id == "latin_america_peers")),
  "latin_peers_are_unvotes_voting_units",
  all(anchor_members$member_iso3c[anchor_members$anchor_id == "latin_america_peers"] %in% valid_un_voting_iso3c),
  paste(anchor_members$member_iso3c[anchor_members$anchor_id == "latin_america_peers"], collapse = ";"),
  "uncoded_resolution_count_documented",
  TRUE,
  as.character(issue_coverage$n_uncoded),
  "human_rights_strong_divergent_sample_nonempty",
  issue_coverage$n_human_rights_china_usa_strong_divergent > 0L,
  as.character(issue_coverage$n_human_rights_china_usa_strong_divergent)
) |>
  dplyr::mutate(status = as.logical(status))

readr::write_csv(validation, paths$validation, na = "")

if (!all(validation$status)) {
  failed <- validation |>
    dplyr::filter(!status) |>
    dplyr::pull(check)
  stop("Validation failed: ", paste(failed, collapse = ", "))
}

plot_data <- relative_change |>
  dplyr::filter(sample_id %in% c(
    "human_rights",
    "human_rights_china_usa_divergent",
    "human_rights_china_usa_strong_divergent"
  )) |>
  dplyr::mutate(
    anchor_label_short = dplyr::case_when(
      anchor_id == "russia" ~ "Russia",
      anchor_id == "india" ~ "India",
      anchor_id == "south_africa" ~ "South Africa",
      anchor_id == "brics_peers_fixed" ~ "BRICS peers fixed",
      anchor_id == "brics_peers_historical" ~ "BRICS peers historical",
      anchor_id == "g77_fixed" ~ "G77 fixed",
      anchor_id == "latin_america_peers" ~ "Latin American peers",
      anchor_id == "united_states" ~ "United States",
      TRUE ~ anchor_label
    ),
    anchor_label_short = factor(
      anchor_label_short,
      levels = c(
        "United States",
        "Russia",
        "India",
        "South Africa",
        "BRICS peers fixed",
        "BRICS peers historical",
        "G77 fixed",
        "Latin American peers"
      )
    ),
    sample_label = factor(
      sample_label,
      levels = c(
        "Human-rights votes",
        "Human-rights votes where China and the United States diverged",
        "Human-rights votes where China and the United States strongly diverged"
      )
    )
  )

fig <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(
    x = anchor_label_short,
    y = change_relative_agreement_china_minus_anchor,
    fill = sample_label
  )
) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.35, color = "gray45") +
  ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.72), width = 0.64) +
  ggplot2::coord_flip() +
  ggplot2::scale_fill_manual(
    values = c(
      "Human-rights votes" = "#1B7837",
      "Human-rights votes where China and the United States diverged" = "#762A83",
      "Human-rights votes where China and the United States strongly diverged" = "#2166AC"
    )
  ) +
  ggplot2::labs(
    title = "Figure 1. Post-2009 change in Brazil's relative China proximity",
    subtitle = "Positive values mean Brazil moved closer to China than to the comparator anchor.",
    x = NULL,
    y = "Post-minus-pre change in [agreement with China - agreement with comparator]",
    fill = NULL,
    caption = paste0(
      "Source: unvotes 0.3.0/Voeten, accessed ", access_date,
      ". Bloc anchors use modal valid votes; tied modes are omitted. Brazil and China are excluded from bloc anchors."
    )
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    plot.title = ggplot2::element_text(face = "bold")
  )

save_plot_pair(fig, paths$figure_png, paths$figure_pdf, width = 9, height = 6)

focus_table <- relative_change |>
  dplyr::filter(sample_id == "human_rights_china_usa_divergent") |>
  dplyr::mutate(
    anchor = dplyr::case_when(
      anchor_id == "russia" ~ "Russia",
      anchor_id == "india" ~ "India",
      anchor_id == "south_africa" ~ "South Africa",
      anchor_id == "brics_peers_fixed" ~ "BRICS peers fixed",
      anchor_id == "brics_peers_historical" ~ "BRICS peers historical",
      anchor_id == "g77_fixed" ~ "G77 fixed",
      anchor_id == "latin_america_peers" ~ "Latin American peers",
      anchor_id == "united_states" ~ "United States",
      TRUE ~ anchor_label
    ),
    `Pre relative agreement` = fmt_num(mean_relative_agreement_china_minus_anchor_pre_2009, 3),
    `Post relative agreement` = fmt_num(mean_relative_agreement_china_minus_anchor_post_2009, 3),
    `Post-pre change` = fmt_num(change_relative_agreement_china_minus_anchor, 3),
    `Pre N` = n_resolutions_pre_2009,
    `Post N` = n_resolutions_post_2009
  ) |>
  dplyr::select(
    Anchor = anchor,
    `Pre N`,
    `Post N`,
    `Pre relative agreement`,
    `Post relative agreement`,
    `Post-pre change`,
    Interpretation = interpretation
  )

human_rights_table <- relative_change |>
  dplyr::filter(sample_id == "human_rights") |>
  dplyr::mutate(
    anchor = dplyr::case_when(
      anchor_id == "russia" ~ "Russia",
      anchor_id == "india" ~ "India",
      anchor_id == "south_africa" ~ "South Africa",
      anchor_id == "brics_peers_fixed" ~ "BRICS peers fixed",
      anchor_id == "brics_peers_historical" ~ "BRICS peers historical",
      anchor_id == "g77_fixed" ~ "G77 fixed",
      anchor_id == "latin_america_peers" ~ "Latin American peers",
      anchor_id == "united_states" ~ "United States",
      TRUE ~ anchor_label
    ),
    `China agreement change` = fmt_num(change_brazil_china_agreement, 3),
    `Anchor agreement change` = fmt_num(change_brazil_anchor_agreement, 3),
    `Relative change` = fmt_num(change_relative_agreement_china_minus_anchor, 3)
  ) |>
  dplyr::select(
    Anchor = anchor,
    `China agreement change`,
    `Anchor agreement change`,
    `Relative change`,
    Interpretation = interpretation
  )

strong_focus_table <- relative_change |>
  dplyr::filter(sample_id == "human_rights_china_usa_strong_divergent") |>
  dplyr::mutate(
    anchor = dplyr::case_when(
      anchor_id == "russia" ~ "Russia",
      anchor_id == "india" ~ "India",
      anchor_id == "south_africa" ~ "South Africa",
      anchor_id == "brics_peers_fixed" ~ "BRICS peers fixed",
      anchor_id == "brics_peers_historical" ~ "BRICS peers historical",
      anchor_id == "g77_fixed" ~ "G77 fixed",
      anchor_id == "latin_america_peers" ~ "Latin American peers",
      anchor_id == "united_states" ~ "United States",
      TRUE ~ anchor_label
    ),
    `Pre N` = n_resolutions_pre_2009,
    `Post N` = n_resolutions_post_2009,
    `Post-pre change` = fmt_num(change_relative_agreement_china_minus_anchor, 3)
  ) |>
  dplyr::select(
    Anchor = anchor,
    `Pre N`,
    `Post N`,
    `Post-pre change`,
    Interpretation = interpretation
  )

common_support_table <- common_support_relative_change |>
  dplyr::filter(sample_id == "human_rights_china_usa_divergent") |>
  dplyr::mutate(
    anchor = dplyr::case_when(
      anchor_id == "russia" ~ "Russia",
      anchor_id == "india" ~ "India",
      anchor_id == "south_africa" ~ "South Africa",
      anchor_id == "brics_peers_fixed" ~ "BRICS peers fixed",
      anchor_id == "brics_peers_historical" ~ "BRICS peers historical",
      anchor_id == "g77_fixed" ~ "G77 fixed",
      anchor_id == "latin_america_peers" ~ "Latin American peers",
      anchor_id == "united_states" ~ "United States",
      TRUE ~ anchor_label
    ),
    `Pre N` = n_resolutions_pre_2009,
    `Post N` = n_resolutions_post_2009,
    `Post-pre change` = fmt_num(change_relative_agreement_china_minus_anchor, 3)
  ) |>
  dplyr::select(
    Anchor = anchor,
    `Pre N`,
    `Post N`,
    `Post-pre change`,
    Interpretation = interpretation
  )

main_focus <- relative_change |>
  dplyr::filter(sample_id == "human_rights_china_usa_divergent")

strong_focus <- relative_change |>
  dplyr::filter(sample_id == "human_rights_china_usa_strong_divergent")

positive_focus <- main_focus |>
  dplyr::filter(change_relative_agreement_china_minus_anchor > 0.05) |>
  dplyr::pull(anchor_label)

nonpositive_focus <- main_focus |>
  dplyr::filter(change_relative_agreement_china_minus_anchor <= 0.05) |>
  dplyr::pull(anchor_label)

strongest_relative <- main_focus |>
  dplyr::arrange(dplyr::desc(change_relative_agreement_china_minus_anchor)) |>
  dplyr::slice(1)

weakest_relative <- main_focus |>
  dplyr::arrange(change_relative_agreement_china_minus_anchor) |>
  dplyr::slice(1)

strong_positive_focus <- strong_focus |>
  dplyr::filter(change_relative_agreement_china_minus_anchor > 0.05) |>
  dplyr::pull(anchor_label)

strong_nonpositive_focus <- strong_focus |>
  dplyr::filter(change_relative_agreement_china_minus_anchor <= 0.05) |>
  dplyr::pull(anchor_label)

note <- c(
  "# Comparator-anchor diagnostic for Brazil's UNGA movement",
  "",
  paste0("Run date: ", run_timestamp),
  "",
  "## Motivation",
  "",
  "The reviewer concern is that the existing UNGA evidence may capture a broad BRICS, G77, or sovereignty-oriented bloc shift rather than China-specific accommodation. This diagnostic therefore changes the estimand. It does not ask only whether Brazil became more similar to China after 2009. It asks whether Brazil's similarity to China increased more than its similarity to plausible comparator anchors.",
  "",
  "The result should be read as a descriptive diagnostic, not as a causal identification strategy. The timing remains the 2009 Brazil-China trade-rank threshold, but the vote-level exercise cannot by itself remove all contemporaneous late-Lula, global-financial-crisis, G20, BRICS, or South-South foreign-policy shocks.",
  "",
  "## Data",
  "",
  paste0("- Vote data: `unvotes` 0.3.0 CRAN source tarball, based on Erik Voeten's UNGA voting data, preserved locally at `data/raw/unvotes/unvotes_0.3.0.tar.gz`; source URL: ", source_url, "."),
  paste0("- Period: ", min(analysis_years), "-", max(analysis_years), "."),
  paste0(
    "- Coverage: ", issue_coverage$n_resolutions,
    " valid Brazil-China resolutions; ", issue_coverage$n_uncoded,
    " have no `unvotes` issue code; ", issue_coverage$n_human_rights,
    " are coded as human rights; ", issue_coverage$n_human_rights_china_usa_divergent,
    " are human-rights votes where China and the United States diverged; ",
    issue_coverage$n_human_rights_china_usa_strong_divergent,
    " are human-rights votes with strong yes-no China-U.S. divergence."
  ),
  "- Unit: resolution-anchor rows. Brazil, China, and the comparator anchor must have valid yes/no/abstain information for the relative agreement measure.",
  "- Missing or absent votes are excluded from the relevant pair or bloc denominator.",
  "- Issue families use the same unvotes issue coding and mapping used by the existing Brazil-China diagnostics.",
  "",
  "## Anchor construction",
  "",
  "- Individual anchors: Russia, India, South Africa, and the United States. The United States is retained as the opposing benchmark.",
  "- BRICS fixed peer anchor: the modal vote of Russia, India, and South Africa, excluding Brazil and China.",
  "- BRICS historical peer anchor: Russia and India in 2005-2010, with South Africa added from 2011. Brazil and China are excluded.",
  paste0("- G77 anchor: modal valid vote among countries on the official Group of 77 member list, excluding Brazil and China. The list is fixed because year-specific membership files are not present in the repo. Source: ", g77_members_url, "; Group background: ", g77_about_url, "."),
  "- Latin American peer anchor: modal valid vote among South and Central American countries in `countrycode`, excluding Brazil, Caribbean countries, and territories that are not observed UNGA voting units in `unvotes`.",
  "- Bloc anchors use modal votes as the primary transparent position. Tied modes are omitted for agreement measures. Median ordinal bloc scores are also saved for continuous similarity diagnostics.",
  "",
  "## Measurement",
  "",
  "- Pairwise agreement is 1 when Brazil and the anchor cast the same valid vote and 0 otherwise.",
  "- Ordinal vote similarity is `1 - abs(score_Brazil - score_anchor) / 2`, where no = -1, abstain = 0, and yes = 1.",
  "- The key relative agreement measure is `agreement(Brazil, China) - agreement(Brazil, comparator)` on the same resolution-anchor support.",
  "- Positive post-minus-pre movement in the relative measure means Brazil moved closer to China than to the comparator anchor.",
  "- Tables 1, 2, and 4 use anchor-specific support: each comparator is evaluated on the resolutions for which that anchor has a valid position. Table 3 repeats the most demanding sample on common support across all comparator anchors.",
  paste0("- Post-2009 is coded as years >= ", post_start_year, "; pre-2009 is years < ", post_start_year, "."),
  "",
  "## Table 1. Human-rights votes where China and the United States diverged",
  "",
  "Caption: Pre- and post-2009 changes in Brazil's relative agreement with China versus comparator anchors. Positive post-pre changes support China-specific movement beyond the comparator anchor.",
  "",
  markdown_table(focus_table, digits = 3),
  "",
  "## Table 2. Human-rights votes, all China-U.S. configurations",
  "",
  "Caption: Decomposition of post-minus-pre agreement changes. The relative change subtracts the comparator-anchor movement from Brazil-China movement.",
  "",
  markdown_table(human_rights_table, digits = 3),
  "",
  "## Table 3. Common-support sensitivity for human-rights China-U.S.-divergent votes",
  "",
  "Caption: Same estimand as Table 1, restricted to resolutions where all comparator anchors have valid positions. This avoids cross-anchor support differences at the cost of a smaller sample.",
  "",
  markdown_table(common_support_table, digits = 3),
  "",
  "## Table 4. Strong China-U.S. divergence sensitivity",
  "",
  "Caption: Post-minus-pre change in relative agreement for human-rights resolutions where China and the United States cast opposite yes/no votes, excluding yes/abstain and no/abstain differences.",
  "",
  markdown_table(strong_focus_table, digits = 3),
  "",
  "## Figure 1",
  "",
  paste0("Caption: Post-2009 change in Brazil's relative China proximity by comparator anchor. Positive values mean that Brazil moved closer to China than to the comparator. Files: `", paths$figure_png, "` and `", paths$figure_pdf, "`."),
  "",
  "## Substantive findings",
  "",
  paste0(
    "In the most demanding sample, human-rights votes where China and the United States diverged, the largest positive relative movement is against ",
    strongest_relative$anchor_label[[1]], " (",
    fmt_num(strongest_relative$change_relative_agreement_china_minus_anchor[[1]], 3),
    "). The weakest relative comparison is against ",
    weakest_relative$anchor_label[[1]], " (",
    fmt_num(weakest_relative$change_relative_agreement_china_minus_anchor[[1]], 3),
    ")."
  ),
  paste0(
    "Anchors with positive relative China movement in this sample: ",
    ifelse(length(positive_focus) == 0L, "none", paste(positive_focus, collapse = "; ")),
    "."
  ),
  paste0(
    "Anchors with similar or stronger comparator movement in this sample: ",
    ifelse(length(nonpositive_focus) == 0L, "none", paste(nonpositive_focus, collapse = "; ")),
    "."
  ),
  paste0(
    "In the strong yes-no China-U.S. divergence sensitivity, anchors with positive relative China movement are: ",
    ifelse(length(strong_positive_focus) == 0L, "none", paste(strong_positive_focus, collapse = "; ")),
    ". Anchors with similar or stronger comparator movement are: ",
    ifelse(length(strong_nonpositive_focus) == 0L, "none", paste(strong_nonpositive_focus, collapse = "; ")),
    "."
  ),
  "Across the broader human-rights sample, the diagnostic should be interpreted jointly with Table 2 because China-U.S. non-divergent votes provide less leverage on a China-versus-U.S. accommodation claim.",
  "",
  "## Limitations",
  "",
  "- This is not a causal DiD design. It is a vote-level comparator diagnostic aligned with the paper's reduced-form timing.",
  "- Bloc anchors are summaries of observed voting positions, not measures of diplomatic coordination or agenda setting.",
  "- The G77 anchor uses a fixed official member list because the repo does not contain year-specific G77 membership data. This is transparent but imperfect for 2005-2012 membership timing.",
  "- Modal bloc positions omit tied modes. This is conservative for small BRICS peer anchors but can reduce support.",
  "- Human-rights issue coding follows unvotes labels; multi-coded resolutions enter the human-rights domain whenever at least one issue label is human rights.",
  "- The China-U.S. divergence restriction improves interpretability for accommodation on a China-versus-U.S. axis but leaves a smaller sample.",
  "",
  "## Outputs",
  "",
  paste0("- Resolution-level metrics: `", paths$resolution_metrics, "`."),
  paste0("- Pre/post summary: `", paths$prepost_summary, "`."),
  paste0("- Relative change summary: `", paths$relative_change, "`."),
  paste0("- Common-support relative change summary: `", paths$common_support_relative_change, "`."),
  paste0("- Annual summary: `", paths$annual_summary, "`."),
  paste0("- Anchor membership audit: `", paths$anchor_members, "`."),
  paste0("- Validation checks: `", paths$validation, "`."),
  paste0("- Session info: `", paths$session_info, "`."),
  "",
  "## Manuscript implication",
  "",
  "If this diagnostic is integrated, the manuscript should distinguish three quantities: absolute movement toward China, relative movement toward China compared with other anchors, and broader bloc convergence. The relative China-minus-comparator estimand is the relevant response to the reviewer concern."
)

writeLines(note, paths$note, useBytes = TRUE)

utils::capture.output(sessionInfo(), file = paths$session_info)

manifest <- tibble::tibble(
  file = unlist(paths, use.names = FALSE),
  exists = file.exists(file),
  bytes = ifelse(exists, file.info(file)$size, NA_real_),
  description = names(paths)
)
readr::write_csv(manifest, paths$manifest, na = "")

manifest <- manifest |>
  dplyr::mutate(
    exists = file.exists(file),
    bytes = ifelse(exists, file.info(file)$size, NA_real_)
  )
readr::write_csv(manifest, paths$manifest, na = "")

message("Wrote: ", paths$resolution_metrics)
message("Wrote: ", paths$prepost_summary)
message("Wrote: ", paths$relative_change)
message("Wrote: ", paths$common_support_relative_change)
message("Wrote: ", paths$annual_summary)
message("Wrote: ", paths$anchor_members)
message("Wrote: ", paths$note)
message("Wrote: ", paths$figure_png)
message("Wrote: ", paths$figure_pdf)
