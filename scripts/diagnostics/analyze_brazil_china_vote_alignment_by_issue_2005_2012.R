#!/usr/bin/env Rscript

# Analyze relational alignment in Brazil-China UNGA votes, 2005-2012.
# The script reads the preserved CRAN unvotes source tarball and writes
# diagnostic outputs without modifying raw data or the targets pipeline.

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
  library(lubridate)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
})

raw_tarball <- "data/raw/unvotes/unvotes_0.3.0.tar.gz"
source_url <- "https://cran.r-project.org/src/contrib/unvotes_0.3.0.tar.gz"
access_date <- "2026-05-16"
analysis_period <- 2005:2012
support_shift_threshold_pp <- 5

processed_dir <- "data/processed/unvotes"
report_dir <- "quality_reports/un_vote_cases"

resolution_out <- file.path(
  processed_dir,
  "brazil_china_vote_alignment_by_resolution_2005_2012.csv"
)
issue_year_out <- file.path(
  processed_dir,
  "brazil_china_vote_alignment_by_issue_year_2005_2012.csv"
)
mechanisms_out <- file.path(
  processed_dir,
  "brazil_china_vote_alignment_mechanisms_2005_2012.csv"
)
note_out <- file.path(
  report_dir,
  "nota_alinhamento_relacional_brasil_china_2005_2012.md"
)
validation_out <- file.path(
  report_dir,
  "brazil_china_vote_alignment_validation_2005_2012.csv"
)
session_info_out <- file.path(
  report_dir,
  "brazil_china_vote_alignment_session_info_2005_2012.txt"
)

fig1_png <- file.path(
  report_dir,
  "figura_1_alinhamento_medio_brasil_china_por_tema_2005_2012.png"
)
fig1_pdf <- file.path(
  report_dir,
  "figura_1_alinhamento_medio_brasil_china_por_tema_2005_2012.pdf"
)
fig2_png <- file.path(
  report_dir,
  "figura_2_diferenca_apoio_relativo_por_tema_2005_2012.png"
)
fig2_pdf <- file.path(
  report_dir,
  "figura_2_diferenca_apoio_relativo_por_tema_2005_2012.pdf"
)
fig3_png <- file.path(
  report_dir,
  "figura_3_decomposicao_mecanismos_pre_pos_2009.png"
)
fig3_pdf <- file.path(
  report_dir,
  "figura_3_decomposicao_mecanismos_pre_pos_2009.pdf"
)
fig4_png <- file.path(
  report_dir,
  "figura_4_heatmap_convergencia_apoio_relativo_2005_2012.png"
)
fig4_pdf <- file.path(
  report_dir,
  "figura_4_heatmap_convergencia_apoio_relativo_2005_2012.pdf"
)

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(raw_tarball)) {
  stop(
    "Missing raw tarball: ", raw_tarball,
    ". Expected preserved source from ", source_url
  )
}

if (file.info(raw_tarball)$size <= 0) {
  stop("Raw tarball exists but is empty: ", raw_tarball)
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

clean_text <- function(x) {
  x |>
    iconv(from = "", to = "UTF-8", sub = "") |>
    stringr::str_replace_all("\u00a0", " ") |>
    stringr::str_replace_all("\u00c2", "") |>
    stringr::str_squish()
}

make_title_key <- function(x) {
  clean_text(x) |>
    stringr::str_to_lower() |>
    stringr::str_replace("\\s*[:;].*$", "") |>
    stringr::str_replace_all("[^a-z0-9]+", " ") |>
    stringr::str_squish()
}

make_doc_symbol <- function(unres) {
  dplyr::if_else(
    is.na(unres) | unres == "",
    NA_character_,
    stringr::str_replace(unres, "^R/", "A/RES/")
  )
}

map_issue_family <- function(issue) {
  dplyr::case_when(
    is.na(issue) | issue == "" ~ "Outros / sem codificação",
    stringr::str_detect(issue, "Human rights") ~ "Direitos humanos",
    stringr::str_detect(issue, "Arms control|Nuclear weapons|disarmament") ~
      "Armas/desarmamento/nuclear",
    stringr::str_detect(issue, "Palestinian conflict") ~
      "Palestina/Oriente Médio",
    stringr::str_detect(issue, "Economic development") ~
      "Desenvolvimento econômico",
    stringr::str_detect(issue, "Colonialism") ~ "Descolonização",
    stringr::str_detect(issue, "Environment") ~ "Meio ambiente",
    stringr::str_detect(issue, "Refugees") ~ "Refugiados",
    TRUE ~ "Outros / sem codificação"
  )
}

mean_na <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }
  mean(x, na.rm = TRUE)
}

median_na <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }
  stats::median(x, na.rm = TRUE)
}

fmt_num <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", format(round(x, digits), nsmall = digits, trim = TRUE))
}

fmt_int <- function(x) {
  ifelse(is.na(x), "NA", format(as.integer(round(x)), trim = TRUE))
}

markdown_table <- function(df, max_rows = 12) {
  if (nrow(df) == 0) {
    return("_Nenhum caso encontrado._")
  }

  df <- df |>
    utils::head(max_rows) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))

  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(df)), collapse = " | "), " |")
  rows <- apply(
    df,
    1,
    function(row) {
      row <- stringr::str_replace_all(row, "\\|", "/")
      paste0("| ", paste(row, collapse = " | "), " |")
    }
  )
  paste(c(header, separator, rows), collapse = "\n")
}

png_utf8 <- function(filename, width, height, units, res, ...) {
  png_type <- if (isTRUE(capabilities("aqua"))) {
    "quartz"
  } else {
    getOption("bitmapType", "cairo")
  }
  grDevices::png(
    filename = filename,
    width = width,
    height = height,
    units = units,
    res = res,
    type = png_type,
    ...
  )
}

pdf_utf8 <- function(filename, width, height, ...) {
  grDevices::pdf(
    file = filename,
    width = width,
    height = height,
    useDingbats = FALSE,
    ...
  )
}

save_plot_pair <- function(plot, png_path, pdf_path, width, height) {
  ggplot2::ggsave(
    png_path,
    plot,
    width = width,
    height = height,
    dpi = 300,
    device = png_utf8
  )
  ggplot2::ggsave(
    pdf_path,
    plot,
    width = width,
    height = height,
    device = pdf_utf8
  )
}

un_votes <- load_unvotes_data("un_votes") |>
  dplyr::mutate(vote = as.character(vote))
un_roll_calls <- load_unvotes_data("un_roll_calls")
un_roll_call_issues <- load_unvotes_data("un_roll_call_issues") |>
  dplyr::mutate(issue = as.character(issue))

issue_long <- un_roll_call_issues |>
  dplyr::mutate(
    issue_raw = clean_text(issue),
    issue_family_raw = map_issue_family(issue_raw)
  ) |>
  dplyr::select(rcid, issue_raw, issue_family_raw) |>
  dplyr::distinct()

issue_by_rcid <- issue_long |>
  dplyr::summarise(
    issue = paste(sort(unique(issue_raw)), collapse = "; "),
    issue_family = paste(sort(unique(issue_family_raw)), collapse = "; "),
    n_issue_codes = dplyr::n_distinct(issue_raw),
    .by = rcid
  )

core_votes <- un_votes |>
  dplyr::filter(country_code %in% c("BR", "CN")) |>
  dplyr::select(rcid, country_code, vote) |>
  tidyr::pivot_wider(
    names_from = country_code,
    values_from = vote,
    names_prefix = "vote_"
  )

core_roll_calls <- core_votes |>
  dplyr::inner_join(un_roll_calls, by = "rcid") |>
  dplyr::mutate(
    year = lubridate::year(date),
    doc_symbol = make_doc_symbol(unres),
    title_key = make_title_key(descr),
    short = clean_text(short),
    descr = clean_text(descr),
    vote_brazil = as.character(vote_BR),
    vote_china = as.character(vote_CN),
    brazil_china_convergent = !is.na(vote_brazil) & vote_brazil == vote_china,
    convergence = dplyr::if_else(
      brazil_china_convergent,
      "convergente",
      "divergente"
    ),
    period = dplyr::if_else(year <= 2008, "pré-2009", "pós-2009"),
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
  dplyr::filter(year %in% analysis_period)

analysis_rcids <- core_roll_calls |>
  dplyr::filter(
    !is.na(vote_brazil),
    !is.na(vote_china),
    vote_brazil != "absent",
    vote_china != "absent"
  ) |>
  dplyr::select(
    rcid,
    vote_brazil,
    vote_china,
    brazil_china_convergent,
    convergence
  )

support_by_rcid <- un_votes |>
  dplyr::semi_join(analysis_rcids, by = "rcid") |>
  dplyr::left_join(analysis_rcids, by = "rcid") |>
  dplyr::mutate(
    valid_vote = !is.na(vote) & vote != "absent",
    comparison_country = !country_code %in% c("BR", "CN"),
    valid_comparison_vote = valid_vote & comparison_country,
    same_as_brazil = valid_comparison_vote & vote == vote_brazil,
    same_as_china = valid_comparison_vote & vote == vote_china,
    same_as_both = same_as_brazil & same_as_china,
    same_as_brazil_not_china = same_as_brazil & vote != vote_china,
    same_as_china_not_brazil = same_as_china & vote != vote_brazil
  ) |>
  dplyr::summarise(
    total_vote_records_n = dplyr::n(),
    valid_electorate_n = sum(valid_vote, na.rm = TRUE),
    absent_or_missing_n = sum(!valid_vote, na.rm = TRUE),
    comparison_electorate_n = sum(valid_comparison_vote, na.rm = TRUE),
    pct_same_as_brazil = 100 * sum(same_as_brazil, na.rm = TRUE) /
      comparison_electorate_n,
    pct_same_as_china = 100 * sum(same_as_china, na.rm = TRUE) /
      comparison_electorate_n,
    pct_same_as_both_when_convergent = dplyr::if_else(
      dplyr::first(brazil_china_convergent),
      100 * sum(same_as_both, na.rm = TRUE) / comparison_electorate_n,
      NA_real_
    ),
    pct_same_as_brazil_not_china_when_divergent = dplyr::if_else(
      !dplyr::first(brazil_china_convergent),
      100 * sum(same_as_brazil_not_china, na.rm = TRUE) /
        comparison_electorate_n,
      NA_real_
    ),
    pct_same_as_china_not_brazil_when_divergent = dplyr::if_else(
      !dplyr::first(brazil_china_convergent),
      100 * sum(same_as_china_not_brazil, na.rm = TRUE) /
        comparison_electorate_n,
      NA_real_
    ),
    .by = rcid
  ) |>
  dplyr::mutate(
    support_gap_brazil_minus_china_pct = pct_same_as_brazil -
      pct_same_as_china,
    china_support_advantage_pct = pct_same_as_china - pct_same_as_brazil,
    abs_support_gap_pct = abs(support_gap_brazil_minus_china_pct)
  )

resolution_metrics <- core_roll_calls |>
  dplyr::inner_join(support_by_rcid, by = "rcid") |>
  dplyr::left_join(issue_by_rcid, by = "rcid") |>
  dplyr::mutate(
    issue = tidyr::replace_na(issue, "Sem issue codificado"),
    issue_family = tidyr::replace_na(issue_family, "Outros / sem codificação"),
    n_issue_codes = tidyr::replace_na(n_issue_codes, 0L),
    support_percent_denominator = "demais países com voto válido; ausentes excluídos",
    source = paste0(
      "unvotes 0.3.0 CRAN tarball (", source_url,
      "), acessado em ", access_date,
      "; raw preservado em ", raw_tarball
    )
  ) |>
  dplyr::arrange(year, rcid) |>
  dplyr::select(
    rcid,
    doc_symbol,
    unres,
    session,
    date,
    year,
    period,
    importantvote,
    amend,
    para,
    short,
    descr,
    title_key,
    issue,
    issue_family,
    n_issue_codes,
    vote_brazil,
    vote_china,
    brazil_china_convergent,
    convergence,
    pct_same_as_brazil,
    pct_same_as_china,
    pct_same_as_both_when_convergent,
    pct_same_as_brazil_not_china_when_divergent,
    pct_same_as_china_not_brazil_when_divergent,
    support_gap_brazil_minus_china_pct,
    china_support_advantage_pct,
    abs_support_gap_pct,
    valid_electorate_n,
    comparison_electorate_n,
    total_vote_records_n,
    absent_or_missing_n,
    support_percent_denominator,
    document_url,
    vote_record_url,
    source
  )

resolution_issue_long <- resolution_metrics |>
  dplyr::select(
    rcid,
    year,
    period,
    vote_brazil,
    vote_china,
    convergence,
    pct_same_as_brazil,
    pct_same_as_china,
    pct_same_as_both_when_convergent,
    pct_same_as_brazil_not_china_when_divergent,
    pct_same_as_china_not_brazil_when_divergent,
    support_gap_brazil_minus_china_pct,
    china_support_advantage_pct,
    abs_support_gap_pct,
    valid_electorate_n,
    comparison_electorate_n
  ) |>
  dplyr::left_join(issue_long, by = "rcid") |>
  dplyr::mutate(
    issue = tidyr::replace_na(issue_raw, "Sem issue codificado"),
    issue_family = tidyr::replace_na(
      issue_family_raw,
      "Outros / sem codificação"
    )
  ) |>
  dplyr::select(
    rcid,
    year,
    period,
    issue,
    issue_family,
    vote_brazil,
    vote_china,
    convergence,
    pct_same_as_brazil,
    pct_same_as_china,
    pct_same_as_both_when_convergent,
    pct_same_as_brazil_not_china_when_divergent,
    pct_same_as_china_not_brazil_when_divergent,
    support_gap_brazil_minus_china_pct,
    china_support_advantage_pct,
    abs_support_gap_pct,
    valid_electorate_n,
    comparison_electorate_n
  )

theme_long <- dplyr::bind_rows(
  resolution_issue_long |>
    dplyr::transmute(
      rcid,
      year,
      period,
      theme_level = "issue_unvotes",
      theme = issue,
      vote_brazil,
      vote_china,
      convergence,
      pct_same_as_brazil,
      pct_same_as_china,
      pct_same_as_both_when_convergent,
      pct_same_as_brazil_not_china_when_divergent,
      pct_same_as_china_not_brazil_when_divergent,
      support_gap_brazil_minus_china_pct,
      china_support_advantage_pct,
      abs_support_gap_pct,
      valid_electorate_n,
      comparison_electorate_n
    ),
  resolution_issue_long |>
    dplyr::transmute(
      rcid,
      year,
      period,
      theme_level = "familia_substantiva",
      theme = issue_family,
      vote_brazil,
      vote_china,
      convergence,
      pct_same_as_brazil,
      pct_same_as_china,
      pct_same_as_both_when_convergent,
      pct_same_as_brazil_not_china_when_divergent,
      pct_same_as_china_not_brazil_when_divergent,
      support_gap_brazil_minus_china_pct,
      china_support_advantage_pct,
      abs_support_gap_pct,
      valid_electorate_n,
      comparison_electorate_n
    )
) |>
  dplyr::distinct(rcid, theme_level, theme, .keep_all = TRUE)

issue_year_summary <- theme_long |>
  dplyr::summarise(
    n_resolutions = dplyr::n_distinct(rcid),
    n_convergent = sum(convergence == "convergente", na.rm = TRUE),
    n_divergent = sum(convergence == "divergente", na.rm = TRUE),
    pct_convergent = 100 * mean(convergence == "convergente", na.rm = TRUE),
    mean_pct_same_as_brazil = mean_na(pct_same_as_brazil),
    median_pct_same_as_brazil = median_na(pct_same_as_brazil),
    mean_pct_same_as_china = mean_na(pct_same_as_china),
    median_pct_same_as_china = median_na(pct_same_as_china),
    mean_pct_same_as_both_when_convergent =
      mean_na(pct_same_as_both_when_convergent),
    median_pct_same_as_both_when_convergent =
      median_na(pct_same_as_both_when_convergent),
    mean_pct_same_as_brazil_not_china_when_divergent =
      mean_na(pct_same_as_brazil_not_china_when_divergent),
    median_pct_same_as_brazil_not_china_when_divergent =
      median_na(pct_same_as_brazil_not_china_when_divergent),
    mean_pct_same_as_china_not_brazil_when_divergent =
      mean_na(pct_same_as_china_not_brazil_when_divergent),
    median_pct_same_as_china_not_brazil_when_divergent =
      median_na(pct_same_as_china_not_brazil_when_divergent),
    mean_support_gap_brazil_minus_china_pct =
      mean_na(support_gap_brazil_minus_china_pct),
    median_support_gap_brazil_minus_china_pct =
      median_na(support_gap_brazil_minus_china_pct),
    mean_china_support_advantage_pct = mean_na(china_support_advantage_pct),
    median_china_support_advantage_pct = median_na(china_support_advantage_pct),
    mean_abs_support_gap_pct = mean_na(abs_support_gap_pct),
    median_abs_support_gap_pct = median_na(abs_support_gap_pct),
    mean_valid_electorate_n = mean_na(valid_electorate_n),
    median_valid_electorate_n = median_na(valid_electorate_n),
    mean_comparison_electorate_n = mean_na(comparison_electorate_n),
    median_comparison_electorate_n = median_na(comparison_electorate_n),
    pct_resolutions_china_more_majoritarian = 100 *
      mean(pct_same_as_china > pct_same_as_brazil, na.rm = TRUE),
    .by = c(theme_level, theme, year, period)
  ) |>
  dplyr::arrange(theme_level, theme, year)

mechanisms <- resolution_metrics |>
  dplyr::filter(
    !stringr::str_detect(
      title_key,
      "^the (acting )?president( spoke.*)?$"
    )
  ) |>
  dplyr::arrange(title_key, year, date, rcid) |>
  dplyr::group_by(title_key) |>
  dplyr::mutate(
    family_n_resolutions = dplyr::n(),
    previous_rcid = dplyr::lag(rcid),
    previous_doc_symbol = dplyr::lag(doc_symbol),
    previous_year = dplyr::lag(year),
    previous_date = dplyr::lag(date),
    previous_vote_brazil = dplyr::lag(vote_brazil),
    previous_vote_china = dplyr::lag(vote_china),
    previous_convergence = dplyr::lag(convergence),
    previous_pct_same_as_brazil = dplyr::lag(pct_same_as_brazil),
    previous_pct_same_as_china = dplyr::lag(pct_same_as_china),
    previous_support_gap_brazil_minus_china_pct =
      dplyr::lag(support_gap_brazil_minus_china_pct),
    previous_china_support_advantage_pct =
      dplyr::lag(china_support_advantage_pct),
    previous_abs_support_gap_pct = dplyr::lag(abs_support_gap_pct)
  ) |>
  dplyr::ungroup() |>
  dplyr::filter(family_n_resolutions >= 2, !is.na(previous_rcid)) |>
  dplyr::mutate(
    brazil_changed = vote_brazil != previous_vote_brazil,
    china_changed = vote_china != previous_vote_china,
    delta_pct_same_as_brazil = pct_same_as_brazil -
      previous_pct_same_as_brazil,
    delta_pct_same_as_china = pct_same_as_china -
      previous_pct_same_as_china,
    delta_support_gap_brazil_minus_china_pct =
      support_gap_brazil_minus_china_pct -
      previous_support_gap_brazil_minus_china_pct,
    delta_china_support_advantage_pct =
      china_support_advantage_pct -
      previous_china_support_advantage_pct,
    delta_abs_support_gap_pct = abs_support_gap_pct -
      previous_abs_support_gap_pct,
    support_shift_max_abs_pct = pmax(
      abs(delta_pct_same_as_brazil),
      abs(delta_pct_same_as_china),
      na.rm = TRUE
    ),
    mechanism_code = dplyr::case_when(
      brazil_changed & china_changed ~ "D",
      brazil_changed & !china_changed ~ "A",
      !brazil_changed & china_changed ~ "B",
      !brazil_changed & !china_changed &
        support_shift_max_abs_pct > support_shift_threshold_pp ~ "C",
      !brazil_changed & !china_changed ~ "E",
      TRUE ~ NA_character_
    ),
    mechanism_label = dplyr::case_when(
      mechanism_code == "A" ~ "A. Brasil muda e China fica igual",
      mechanism_code == "B" ~ "B. China muda e Brasil fica igual",
      mechanism_code == "C" ~
        "C. Brasil/China ficam iguais, mas apoio relativo muda",
      mechanism_code == "D" ~ "D. Ambos mudam",
      mechanism_code == "E" ~
        "E. Ambos ficam iguais e estrutura quase não muda",
      TRUE ~ NA_character_
    ),
    period_end = period,
    transition_period = dplyr::case_when(
      previous_year <= 2008 & year <= 2008 ~ "pré-2009",
      previous_year <= 2008 & year >= 2009 ~ "transição para pós-2009",
      previous_year >= 2009 & year >= 2009 ~ "pós-2009",
      TRUE ~ NA_character_
    ),
    direct_brazil_move_to_china = mechanism_code == "A" &
      previous_convergence == "divergente" &
      convergence == "convergente" &
      vote_china == previous_vote_china,
    false_positive_china_move_to_brazil = mechanism_code == "B" &
      previous_convergence == "divergente" &
      convergence == "convergente" &
      vote_brazil == previous_vote_brazil,
    relational_realignment_candidate = mechanism_code == "C" &
      support_shift_max_abs_pct > support_shift_threshold_pp,
    relational_relative_shift_candidate = relational_realignment_candidate &
      abs(delta_china_support_advantage_pct) > support_shift_threshold_pp,
    relational_shift_toward_china = relational_realignment_candidate &
      delta_china_support_advantage_pct > support_shift_threshold_pp,
    relational_shift_toward_brazil = relational_realignment_candidate &
      delta_support_gap_brazil_minus_china_pct > support_shift_threshold_pp
  ) |>
  dplyr::select(
    title_key,
    family_n_resolutions,
    rcid,
    doc_symbol,
    year,
    period_end,
    previous_rcid,
    previous_doc_symbol,
    previous_year,
    transition_period,
    issue,
    issue_family,
    short,
    descr,
    previous_vote_brazil,
    vote_brazil,
    brazil_changed,
    previous_vote_china,
    vote_china,
    china_changed,
    previous_convergence,
    convergence,
    previous_pct_same_as_brazil,
    pct_same_as_brazil,
    delta_pct_same_as_brazil,
    previous_pct_same_as_china,
    pct_same_as_china,
    delta_pct_same_as_china,
    previous_support_gap_brazil_minus_china_pct,
    support_gap_brazil_minus_china_pct,
    delta_support_gap_brazil_minus_china_pct,
    previous_china_support_advantage_pct,
    china_support_advantage_pct,
    delta_china_support_advantage_pct,
    previous_abs_support_gap_pct,
    abs_support_gap_pct,
    delta_abs_support_gap_pct,
    support_shift_max_abs_pct,
    mechanism_code,
    mechanism_label,
    direct_brazil_move_to_china,
    false_positive_china_move_to_brazil,
    relational_realignment_candidate,
    relational_relative_shift_candidate,
    relational_shift_toward_china,
    relational_shift_toward_brazil,
    document_url,
    vote_record_url
  ) |>
  dplyr::arrange(year, title_key, rcid)

analyzed_vote_rows <- un_votes |>
  dplyr::semi_join(analysis_rcids, by = "rcid")

country_vote_duplicates_n <- analyzed_vote_rows |>
  dplyr::summarise(n = dplyr::n(), .by = c(rcid, country_code)) |>
  dplyr::filter(n > 1) |>
  nrow()

expected_vote_values <- c("yes", "no", "abstain", "absent")
unexpected_vote_values <- setdiff(
  sort(unique(stats::na.omit(analyzed_vote_rows$vote))),
  expected_vote_values
)

validation_checks <- tibble::tibble(
  check = c(
    "Brasil e China têm votos válidos nas resoluções analisadas",
    "Período restrito a 2005-2012",
    "Sem duplicatas por rcid no CSV por resolução",
    "Sem duplicatas país-votação no universo analisado",
    "Categorias de voto restritas ao esperado",
    "Percentuais entre 0 e 100 ou NA",
    "Denominador de comparação positivo",
    "Ausentes excluídos dos denominadores de percentuais",
    "Eleitorado válido total consistente com denominador de comparação",
    "Colunas essenciais preservadas",
    "Classificação de mecanismos restrita a A-E"
  ),
  passed = c(
    all(
      !is.na(resolution_metrics$vote_brazil),
      !is.na(resolution_metrics$vote_china),
      resolution_metrics$vote_brazil != "absent",
      resolution_metrics$vote_china != "absent"
    ),
    all(resolution_metrics$year %in% analysis_period),
    anyDuplicated(resolution_metrics$rcid) == 0,
    country_vote_duplicates_n == 0,
    length(unexpected_vote_values) == 0,
    {
      percent_cols <- c(
        "pct_same_as_brazil",
        "pct_same_as_china",
        "pct_same_as_both_when_convergent",
        "pct_same_as_brazil_not_china_when_divergent",
        "pct_same_as_china_not_brazil_when_divergent"
      )
      percent_values <- unlist(resolution_metrics[percent_cols])
      all(is.na(percent_values) | (percent_values >= 0 & percent_values <= 100))
    },
    all(resolution_metrics$comparison_electorate_n > 0),
    all(resolution_metrics$comparison_electorate_n <=
      resolution_metrics$valid_electorate_n),
    all(resolution_metrics$valid_electorate_n ==
      resolution_metrics$comparison_electorate_n + 2),
    all(c(
      "rcid",
      "doc_symbol",
      "year",
      "issue",
      "issue_family",
      "vote_brazil",
      "vote_china",
      "document_url",
      "vote_record_url"
    ) %in% names(resolution_metrics)),
    all(stats::na.omit(mechanisms$mechanism_code) %in% c("A", "B", "C", "D", "E"))
  ),
  value = c(
    paste0(nrow(resolution_metrics), " resoluções com BR/CN válidos"),
    paste(range(resolution_metrics$year), collapse = "-"),
    paste0(sum(duplicated(resolution_metrics$rcid)), " duplicatas"),
    paste0(country_vote_duplicates_n, " duplicatas país-votação"),
    ifelse(
      length(unexpected_vote_values) == 0,
      paste(expected_vote_values, collapse = ", "),
      paste(unexpected_vote_values, collapse = ", ")
    ),
    "percentuais auditados",
    paste0("mínimo = ", min(resolution_metrics$comparison_electorate_n)),
    "denominador: demais países com voto diferente de absent",
    "valid_electorate_n = comparison_electorate_n + 2",
    "rcid, símbolo, ano, tema, votos e links preservados",
    paste(sort(unique(mechanisms$mechanism_code)), collapse = ", ")
  )
)

if (!all(validation_checks$passed)) {
  failed <- validation_checks |>
    dplyr::filter(!passed)
  stop(
    "Validation failed: ",
    paste(failed$check, collapse = "; ")
  )
}

readr::write_csv(resolution_metrics, resolution_out)
readr::write_csv(issue_year_summary, issue_year_out)
readr::write_csv(mechanisms, mechanisms_out)
readr::write_csv(validation_checks, validation_out)
writeLines(capture.output(utils::sessionInfo()), session_info_out, useBytes = TRUE)

family_year <- issue_year_summary |>
  dplyr::filter(theme_level == "familia_substantiva")

figure_1_data <- family_year |>
  dplyr::select(
    theme,
    year,
    mean_pct_same_as_brazil,
    mean_pct_same_as_china
  ) |>
  tidyr::pivot_longer(
    cols = c(mean_pct_same_as_brazil, mean_pct_same_as_china),
    names_to = "country",
    values_to = "mean_pct_aligned"
  ) |>
  dplyr::mutate(
    country = dplyr::recode(
      country,
      mean_pct_same_as_brazil = "Brasil",
      mean_pct_same_as_china = "China"
    )
  )

fig1 <- ggplot(
  figure_1_data,
  aes(x = year, y = mean_pct_aligned, color = country, group = country)
) +
  geom_line(linewidth = 0.8, na.rm = TRUE) +
  geom_point(size = 1.8, na.rm = TRUE) +
  facet_wrap(~theme, ncol = 2) +
  scale_x_continuous(breaks = analysis_period) +
  scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 25)) +
  scale_color_manual(values = c("Brasil" = "#1B7837", "China" = "#B2182B")) +
  labs(
    title = "Figura 1. Países alinhados ao Brasil e à China por ano e tema",
    subtitle = "Média por família substantiva; percentuais excluem ausentes e excluem Brasil/China do denominador.",
    x = "Ano",
    y = "Percentual médio de países alinhados",
    color = NULL,
    caption = paste0(
      "Fonte: unvotes 0.3.0/Voeten, acessado em ", access_date,
      ". Elaboração própria."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

fig2 <- ggplot(
  family_year,
  aes(x = year, y = mean_support_gap_brazil_minus_china_pct)
) +
  geom_hline(yintercept = 0, linewidth = 0.4, color = "gray40") +
  geom_col(fill = "#4477AA", width = 0.75, na.rm = TRUE) +
  facet_wrap(~theme, ncol = 2) +
  scale_x_continuous(breaks = analysis_period) +
  labs(
    title = "Figura 2. Diferença entre apoio relativo ao Brasil e à China",
    subtitle = "Valores positivos indicam posição brasileira mais majoritária; negativos indicam posição chinesa mais majoritária.",
    x = "Ano",
    y = "Apoio Brasil - apoio China (p.p.)",
    caption = paste0(
      "Fonte: unvotes 0.3.0/Voeten, acessado em ", access_date,
      ". Elaboração própria."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

mechanism_levels <- tibble::tibble(
  mechanism_code = c("A", "B", "C", "D", "E"),
  mechanism_label = c(
    "A. Brasil muda e China fica igual",
    "B. China muda e Brasil fica igual",
    "C. Brasil/China ficam iguais, mas apoio relativo muda",
    "D. Ambos mudam",
    "E. Ambos ficam iguais e estrutura quase não muda"
  )
)

mechanism_periods <- tibble::tibble(
  period_end = c("pré-2009", "pós-2009"),
  period_plot = c("Pré-2009", "Pós-2009")
)

mechanism_counts <- mechanisms |>
  dplyr::mutate(period_plot = dplyr::case_when(
    period_end == "pré-2009" ~ "Pré-2009",
    period_end == "pós-2009" ~ "Pós-2009",
    TRUE ~ period_end
  )) |>
  dplyr::summarise(
    n_transitions = dplyr::n(),
    .by = c(period_plot, mechanism_code, mechanism_label)
  ) |>
  dplyr::right_join(
    tidyr::expand_grid(
      mechanism_periods |> dplyr::select(period_plot),
      mechanism_levels
    ),
    by = c("period_plot", "mechanism_code", "mechanism_label")
  ) |>
  dplyr::mutate(n_transitions = tidyr::replace_na(n_transitions, 0L)) |>
  dplyr::arrange(period_plot, mechanism_code)

fig3 <- ggplot(
  mechanism_counts,
  aes(x = period_plot, y = n_transitions, fill = mechanism_code)
) +
  geom_col(width = 0.7) +
  scale_fill_manual(
    breaks = c("A", "B", "C", "D", "E"),
    labels = c(
      "A: BR muda",
      "B: CN muda",
      "C: apoio muda",
      "D: ambos mudam",
      "E: estável"
    ),
    values = c(
      "A" = "#E69F00",
      "B" = "#56B4E9",
      "C" = "#009E73",
      "D" = "#D55E00",
      "E" = "#999999"
    )
  ) +
  labs(
    title = "Figura 3. Decomposição dos mecanismos A-E antes e depois de 2009",
    subtitle = paste0(
      "Mecanismo C exige mudança superior a ",
      support_shift_threshold_pp,
      " p.p. no apoio a Brasil ou China mantendo ambos os votos estáveis."
    ),
    x = NULL,
    y = "Número de transições entre resoluções recorrentes",
    fill = NULL,
    caption = paste0(
      "Fonte: unvotes 0.3.0/Voeten, acessado em ", access_date,
      ". Elaboração própria."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    legend.box = "horizontal",
    panel.grid.minor = element_blank()
  )

fig4 <- ggplot(
  family_year,
  aes(x = year, y = theme, fill = pct_convergent)
) +
  geom_tile(color = "white", linewidth = 0.4) +
  geom_text(
    aes(label = fmt_num(mean_support_gap_brazil_minus_china_pct, 0)),
    size = 3,
    color = "black"
  ) +
  scale_x_continuous(breaks = analysis_period) +
  scale_fill_gradient(
    low = "#F7F7F7",
    high = "#2166AC",
    limits = c(0, 100),
    name = "% convergente"
  ) +
  labs(
    title = "Figura 4. Convergência Brasil-China e apoio relativo por tema",
    subtitle = "Preenchimento: percentual de resoluções convergentes. Número na célula: apoio Brasil - apoio China, em p.p.",
    x = "Ano",
    y = NULL,
    caption = paste0(
      "Fonte: unvotes 0.3.0/Voeten, acessado em ", access_date,
      ". Elaboração própria."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank())

save_plot_pair(fig1, fig1_png, fig1_pdf, width = 11, height = 8)
save_plot_pair(fig2, fig2_png, fig2_pdf, width = 11, height = 8)
save_plot_pair(fig3, fig3_png, fig3_pdf, width = 10, height = 6)
save_plot_pair(fig4, fig4_png, fig4_pdf, width = 11, height = 6)

pre_post_family <- theme_long |>
  dplyr::filter(theme_level == "familia_substantiva") |>
  dplyr::summarise(
    n_resolucoes = dplyr::n_distinct(rcid),
    pct_convergente = 100 * mean(convergence == "convergente", na.rm = TRUE),
    apoio_medio_brasil = mean_na(pct_same_as_brazil),
    apoio_medio_china = mean_na(pct_same_as_china),
    gap_medio_br_menos_china = mean_na(support_gap_brazil_minus_china_pct),
    pct_china_mais_majoritaria = 100 *
      mean(pct_same_as_china > pct_same_as_brazil, na.rm = TRUE),
    .by = c(theme, period)
  )

theme_delta <- pre_post_family |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(
      n_resolucoes,
      pct_convergente,
      apoio_medio_brasil,
      apoio_medio_china,
      gap_medio_br_menos_china,
      pct_china_mais_majoritaria
    )
  ) |>
  dplyr::mutate(
    delta_pct_convergente =
      `pct_convergente_pós-2009` - `pct_convergente_pré-2009`,
    delta_apoio_china =
      `apoio_medio_china_pós-2009` - `apoio_medio_china_pré-2009`,
    delta_gap_br_menos_china =
      `gap_medio_br_menos_china_pós-2009` -
      `gap_medio_br_menos_china_pré-2009`
  )

theme_note_table <- theme_delta |>
  dplyr::transmute(
    tema = theme,
    n_pre = fmt_int(`n_resolucoes_pré-2009`),
    n_pos = fmt_int(`n_resolucoes_pós-2009`),
    conv_pre = fmt_num(`pct_convergente_pré-2009`),
    conv_pos = fmt_num(`pct_convergente_pós-2009`),
    delta_conv = fmt_num(delta_pct_convergente),
    china_mais_majoritaria_pos =
      fmt_num(`pct_china_mais_majoritaria_pós-2009`),
    gap_pos = fmt_num(`gap_medio_br_menos_china_pós-2009`)
  ) |>
  dplyr::arrange(dplyr::desc(as.numeric(delta_conv)))

mechanism_summary_table <- mechanisms |>
  dplyr::summarise(
    n = dplyr::n(),
    diretos_brasil_para_china = sum(direct_brazil_move_to_china, na.rm = TRUE),
    falsos_positivos_china_para_brasil =
      sum(false_positive_china_move_to_brazil, na.rm = TRUE),
    realinhamentos_relacionais = sum(relational_realignment_candidate, na.rm = TRUE),
    realinhamentos_relativos = sum(relational_relative_shift_candidate, na.rm = TRUE),
    .by = c(period_end, mechanism_code, mechanism_label)
  ) |>
  dplyr::right_join(
    tidyr::expand_grid(mechanism_periods, mechanism_levels),
    by = c("period_end", "mechanism_code", "mechanism_label")
  ) |>
  dplyr::mutate(
    dplyr::across(
      c(
        n,
        diretos_brasil_para_china,
        falsos_positivos_china_para_brasil,
        realinhamentos_relacionais,
        realinhamentos_relativos
      ),
      ~tidyr::replace_na(.x, 0L)
    )
  ) |>
  dplyr::arrange(period_end, mechanism_code) |>
  dplyr::transmute(
    periodo = period_end,
    mecanismo = mechanism_code,
    descricao = mechanism_label,
    n = fmt_int(n),
    brasil_para_china = fmt_int(diretos_brasil_para_china),
    china_para_brasil = fmt_int(falsos_positivos_china_para_brasil),
    realinhamento = fmt_int(realinhamentos_relacionais),
    realinhamento_relativo = fmt_int(realinhamentos_relativos)
  )

direct_cases_table <- mechanisms |>
  dplyr::filter(direct_brazil_move_to_china) |>
  dplyr::arrange(year, dplyr::desc(delta_china_support_advantage_pct)) |>
  dplyr::transmute(
    ano = year,
    resolucao = doc_symbol,
    tema = issue_family,
    familia = stringr::str_trunc(title_key, 46),
    transicao = paste0(
      previous_doc_symbol,
      " -> ",
      doc_symbol,
      " (BR ",
      previous_vote_brazil,
      " -> ",
      vote_brazil,
      "; CN ",
      vote_china,
      ")"
    ),
    delta_apoio_china = fmt_num(delta_china_support_advantage_pct)
  )

relational_cases_table <- mechanisms |>
  dplyr::filter(relational_relative_shift_candidate, period_end == "pós-2009") |>
  dplyr::arrange(dplyr::desc(abs(delta_china_support_advantage_pct))) |>
  dplyr::transmute(
    ano = year,
    resolucao = doc_symbol,
    tema = issue_family,
    familia = stringr::str_trunc(title_key, 46),
    votos = paste0("BR=", vote_brazil, "; CN=", vote_china),
    delta_apoio_brasil = fmt_num(delta_pct_same_as_brazil),
    delta_apoio_china = fmt_num(delta_pct_same_as_china),
    delta_vantagem_china = fmt_num(delta_china_support_advantage_pct)
  )

false_positive_table <- mechanisms |>
  dplyr::filter(false_positive_china_move_to_brazil) |>
  dplyr::arrange(year, issue_family) |>
  dplyr::transmute(
    ano = year,
    resolucao = doc_symbol,
    tema = issue_family,
    familia = stringr::str_trunc(title_key, 46),
    transicao = paste0(
      previous_doc_symbol,
      " -> ",
      doc_symbol,
      " (CN ",
      previous_vote_china,
      " -> ",
      vote_china,
      "; BR ",
      vote_brazil,
      ")"
    )
  )

process_tracing_table <- dplyr::bind_rows(
  direct_cases_table |>
    dplyr::mutate(criterio = "mudança direta do Brasil") |>
    dplyr::select(criterio, dplyr::everything()),
  relational_cases_table |>
    dplyr::mutate(criterio = "realinhamento relacional") |>
    dplyr::select(criterio, dplyr::everything())
) |>
  dplyr::select(
    criterio,
    ano,
    resolucao,
    tema,
    familia,
    dplyr::everything()
  )

n_resolutions <- nrow(resolution_metrics)
n_transitions <- nrow(mechanisms)
n_direct <- sum(mechanisms$direct_brazil_move_to_china, na.rm = TRUE)
n_false_positive <- sum(mechanisms$false_positive_china_move_to_brazil, na.rm = TRUE)
n_relational_post <- sum(
  mechanisms$relational_realignment_candidate &
    mechanisms$period_end == "pós-2009",
  na.rm = TRUE
)
n_relational_relative_post <- sum(
  mechanisms$relational_relative_shift_candidate &
    mechanisms$period_end == "pós-2009",
  na.rm = TRUE
)
n_relational_toward_china_post <- sum(
  mechanisms$relational_shift_toward_china &
    mechanisms$period_end == "pós-2009",
  na.rm = TRUE
)
n_relational_toward_brazil_post <- sum(
  mechanisms$relational_shift_toward_brazil &
    mechanisms$period_end == "pós-2009",
  na.rm = TRUE
)
direct_post <- sum(
  mechanisms$direct_brazil_move_to_china & mechanisms$period_end == "pós-2009",
  na.rm = TRUE
)
direct_post_hr <- direct_cases_table |>
  dplyr::filter(
    ano >= 2009,
    stringr::str_detect(tema, "Direitos humanos")
  ) |>
  nrow()
direct_post_non_hr <- direct_cases_table |>
  dplyr::filter(
    ano >= 2009,
    !stringr::str_detect(tema, "Direitos humanos")
  ) |>
  nrow()
relational_post_hr <- relational_cases_table |>
  dplyr::filter(stringr::str_detect(tema, "Direitos humanos")) |>
  nrow()
relational_post_non_hr <- relational_cases_table |>
  dplyr::filter(!stringr::str_detect(tema, "Direitos humanos")) |>
  nrow()

strongest_theme <- theme_delta |>
  dplyr::arrange(dplyr::desc(delta_pct_convergente)) |>
  dplyr::slice(1)

china_majority_theme <- theme_delta |>
  dplyr::arrange(
    dplyr::desc(`pct_china_mais_majoritaria_pós-2009`),
    `gap_medio_br_menos_china_pós-2009`
  ) |>
  dplyr::slice(1)

note_lines <- c(
  "# Nota analítica: alinhamento relacional Brasil-China na AGNU, 2005-2012",
  "",
  paste0(
    "Fonte: pacote `unvotes` 0.3.0, baseado nos dados de Erik Voeten sobre ",
    "votações nominais da AGNU. O tarball bruto está preservado em `",
    raw_tarball,
    "`. Data de acesso registrada no projeto: ",
    access_date,
    "."
  ),
  "",
  "## Definição operacional",
  "",
  paste0(
    "A unidade principal é a votação nominal (`rcid`). A amostra contém ",
    n_resolutions,
    " resoluções entre 2005 e 2012 nas quais Brasil e China têm votos válidos ",
    "(`yes`, `no` ou `abstain`). Ausentes são excluídos dos percentuais. ",
    "Para medir o apoio relacional dos demais países, Brasil e China também ",
    "são excluídos do denominador dos percentuais de alinhamento."
  ),
  "",
  paste0(
    "As famílias recorrentes de resolução são aproximadas por uma chave ",
    "normalizada da descrição (`title_key`). O mecanismo C exige que Brasil e ",
    "China mantenham os votos estáveis e que o apoio à posição de pelo menos ",
    "um dos dois mude mais de ",
    support_shift_threshold_pp,
    " pontos percentuais entre duas ocorrências da mesma família. Chaves ",
    "procedimentais genéricas como `the acting president` e `the president` ",
    "foram excluídas da classificação A-E para evitar falsas famílias ",
    "recorrentes."
  ),
  "",
  paste0(
    "O CSV por ano e tema contém dois níveis em `theme_level`: ",
    "`issue_unvotes`, que preserva o tema original do `unvotes`, e ",
    "`familia_substantiva`, que agrega esses temas nas famílias substantivas ",
    "usadas nas figuras e na interpretação."
  ),
  "",
  "## Resposta curta",
  "",
  paste0(
    "A aproximação observável aparece como uma combinação dos dois mecanismos, ",
    "mas a evidência de mudança direta do Brasil é mais nítida quando há ",
    "transições de divergência para convergência com a China estável. Foram ",
    "identificadas ",
    n_direct,
    " transições desse tipo no conjunto de famílias recorrentes; ",
    direct_post,
    " terminam no período pós-2009. A evidência de realinhamento relacional ",
    "também existe em sentido amplo: há ",
    n_relational_post,
    " transições pós-2009 em que os votos de Brasil e China ficam iguais aos ",
    "da ocorrência anterior, mas a estrutura de apoio dos demais países muda ",
    "substantivamente. Em sentido estrito, isto é, com mudança na vantagem ",
    "relativa China-Brasil superior a ",
    support_shift_threshold_pp,
    " p.p., há ",
    n_relational_relative_post,
    " transições pós-2009. Dessas transições estritas, ",
    n_relational_toward_china_post,
    " aumentam a vantagem relativa da posição chinesa e ",
    n_relational_toward_brazil_post,
    " aumentam a vantagem relativa brasileira."
  ),
  "",
  paste0(
    "Isso favorece uma leitura mais específica: a evidência pós-2009 mais ",
    "favorável à narrativa de aproximação direta vem de direitos humanos ",
    "(",
    direct_post_hr,
    " casos diretos), não de uma migração geral para votações em que a posição ",
    "chinesa fosse mais majoritária. Fora de direitos humanos há ",
    direct_post_non_hr,
    " caso direto pós-2009 e ",
    relational_post_non_hr,
    " caso de realinhamento relativo estrito, mas este último não se move na ",
    "direção de maior vantagem chinesa."
  ),
  "",
  paste0(
    "O tema com maior aumento agregado de convergência após 2009 é `",
    strongest_theme$theme,
    "` (delta de ",
    fmt_num(strongest_theme$delta_pct_convergente),
    " p.p.). O tema em que a posição chinesa aparece mais frequentemente ",
    "como mais majoritária no pós-2009 é `",
    china_majority_theme$theme,
    "` (",
    fmt_num(china_majority_theme$`pct_china_mais_majoritaria_pós-2009`),
    "% das resoluções)."
  ),
  "",
  "## Tabela 1. Resoluções por tema e mudança pré/pós-2009",
  "",
  markdown_table(theme_note_table, max_rows = 20),
  "",
  "Legenda: `conv_pre` e `conv_pos` são percentuais de resoluções em que Brasil e China votam igual; `gap_pos` é apoio médio ao Brasil menos apoio médio à China no pós-2009, em pontos percentuais.",
  "",
  "## Tabela 2. Mecanismos A-E por período",
  "",
  markdown_table(mechanism_summary_table, max_rows = 20),
  "",
  paste0(
    "O padrão favorável à narrativa principal deve ser lido com cautela: ",
    "mudanças de convergência podem decorrer de Brasil se aproximando de uma ",
    "posição chinesa estável, mas também de China se aproximando de uma posição ",
    "brasileira estável. Esses casos são marcados como falsos positivos ",
    "potenciais abaixo. Foram encontrados ",
    n_false_positive,
    " falsos positivos desse tipo."
  ),
  "",
  "## Tabela 3. Casos de mudança direta do Brasil em direção à China",
  "",
  markdown_table(direct_cases_table, max_rows = 15),
  "",
  "Esses casos são os melhores candidatos para process tracing qualitativo se a pergunta for se o Brasil mudou voto em direção a uma posição chinesa relativamente estável.",
  "",
  "## Tabela 4. Casos pós-2009 de realinhamento relacional",
  "",
  markdown_table(relational_cases_table, max_rows = 15),
  "",
  "Esses casos são úteis para rastrear se mudanças na distribuição de votos de terceiros alteram a interpretação relacional do alinhamento, mesmo quando Brasil e China não mudam seus próprios votos.",
  "",
  "## Tabela 5. Falsos positivos potenciais: China muda para o Brasil",
  "",
  markdown_table(false_positive_table, max_rows = 15),
  "",
  "Essas transições não sustentam a narrativa de mudança direta do Brasil; elas indicam convergência produzida por mudança chinesa mantendo o voto brasileiro estável.",
  "",
  "## Evidência fora de direitos humanos",
  "",
  paste0(
    "A evidência fora de direitos humanos é limitada para a narrativa forte. ",
    "Há famílias de armas/desarmamento/nuclear com transições relevantes, mas ",
    "as transições pós-2009 mais claras de convergência por mudança brasileira ",
    "são de direitos humanos. Além disso, vários casos fora de direitos humanos ",
    "aparecem como falsos positivos porque a China muda para uma posição ",
    "brasileira já estável."
  ),
  "",
  "## Tabela 6. Prioridades para process tracing",
  "",
  markdown_table(process_tracing_table, max_rows = 20),
  "",
  "## Validações",
  "",
  paste0(
    "As validações obrigatórias foram salvas em `",
    validation_out,
    "`. Elas confirmam que Brasil e China têm votos válidos nas resoluções ",
    "analisadas; que não há duplicatas por `rcid` no CSV por resolução; que ",
    "os percentuais estão entre 0 e 100; que ausentes foram excluídos dos ",
    "denominadores; e que `rcid`, símbolo da resolução, ano, temas, votos e ",
    "links foram preservados."
  ),
  "",
  "## Arquivos gerados",
  "",
  paste0("- Métricas por resolução: `", resolution_out, "`"),
  paste0("- Resumo por ano e tema: `", issue_year_out, "`"),
  paste0("- Mecanismos por família recorrente: `", mechanisms_out, "`"),
  paste0("- Figura 1: `", fig1_png, "` e `", fig1_pdf, "`"),
  paste0("- Figura 2: `", fig2_png, "` e `", fig2_pdf, "`"),
  paste0("- Figura 3: `", fig3_png, "` e `", fig3_pdf, "`"),
  paste0("- Figura 4: `", fig4_png, "` e `", fig4_pdf, "`")
)

writeLines(note_lines, note_out, useBytes = TRUE)

message("Wrote: ", resolution_out)
message("Wrote: ", issue_year_out)
message("Wrote: ", mechanisms_out)
message("Wrote: ", note_out)
message("Wrote figures to: ", report_dir)
