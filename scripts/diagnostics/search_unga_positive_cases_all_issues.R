#!/usr/bin/env Rscript

# Search for additional positive Brazil-China UNGA vote cases beyond human rights.
# A positive candidate is a recurring resolution family with at least one
# pre-2009 Brazil-China divergence and at least one 2009-2012 convergence.
# The script reads the preserved CRAN unvotes tarball and does not modify raw data.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
})

raw_tarball <- "data/raw/unvotes/unvotes_0.3.0.tar.gz"
source_url <- "https://cran.r-project.org/src/contrib/unvotes_0.3.0.tar.gz"
access_date <- "2026-05-16"

processed_dir <- "data/processed/unvotes"
report_dir <- "quality_reports/un_vote_cases"
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

positive_candidates_out <- file.path(
  processed_dir,
  "brazil_china_positive_candidate_themes_all_issues_2004_2012.csv"
)
positive_vote_rows_out <- file.path(
  processed_dir,
  "brazil_china_positive_candidate_votes_all_issues_2004_2012.csv"
)
positive_pairs_out <- file.path(
  processed_dir,
  "brazil_china_positive_candidate_pairs_non_human_rights_2004_2012.csv"
)
non_hr_note_out <- file.path(
  report_dir,
  "positive_candidates_non_human_rights_2004_2012.md"
)

if (!file.exists(raw_tarball)) {
  stop("Missing raw tarball: ", raw_tarball)
}

raw_tarball_md5 <- unname(tools::md5sum(raw_tarball))

tmp_dir <- tempfile("unvotes_")
dir.create(tmp_dir)
on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
untar(raw_tarball, exdir = tmp_dir)

load_unvotes_data <- function(name) {
  env <- new.env(parent = emptyenv())
  load(file.path(tmp_dir, "unvotes", "data", paste0(name, ".rda")), envir = env)
  env[[name]]
}

un_votes <- load_unvotes_data("un_votes")
un_roll_calls <- load_unvotes_data("un_roll_calls")
un_roll_call_issues <- load_unvotes_data("un_roll_call_issues")

issue_by_rcid <- un_roll_call_issues |>
  dplyr::summarise(
    issue = paste(sort(unique(as.character(issue))), collapse = "; "),
    .by = rcid
  ) |>
  dplyr::mutate(issue = dplyr::na_if(issue, "NA"))

clean_text <- function(x) {
  x |>
    iconv(from = "", to = "UTF-8", sub = "") |>
    stringr::str_replace_all("\\?\u00c3\u2020", "'") |>
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

issue_family <- function(issue) {
  dplyr::case_when(
    stringr::str_detect(issue, "Human rights") ~ "Direitos humanos",
    stringr::str_detect(issue, "Arms control|Nuclear weapons") ~ "Armas e nuclear",
    stringr::str_detect(issue, "Palestinian conflict") ~ "Palestina/Oriente Médio",
    stringr::str_detect(issue, "Colonialism") ~ "Descolonização",
    stringr::str_detect(issue, "Economic development") ~ "Desenvolvimento econômico",
    stringr::str_detect(issue, "Disarmament") ~ "Desarmamento",
    stringr::str_detect(issue, "Drugs") ~ "Drogas",
    stringr::str_detect(issue, "Environment") ~ "Meio ambiente",
    stringr::str_detect(issue, "Refugees") ~ "Refugiados",
    is.na(issue) ~ "Sem issue codificado",
    TRUE ~ "Outros"
  )
}

paired_votes <- un_votes |>
  dplyr::filter(country_code %in% c("BR", "CN")) |>
  dplyr::select(rcid, country_code, vote) |>
  tidyr::pivot_wider(
    names_from = country_code,
    values_from = vote,
    names_prefix = "vote_"
  ) |>
  dplyr::inner_join(un_roll_calls, by = "rcid") |>
  dplyr::left_join(issue_by_rcid, by = "rcid") |>
  dplyr::mutate(
    year = lubridate::year(date),
    short = clean_text(short),
    descr = clean_text(descr),
    title_key = make_title_key(descr),
    vote_brazil = as.character(vote_BR),
    vote_china = as.character(vote_CN),
    convergence = dplyr::if_else(vote_brazil == vote_china, "convergente", "divergente"),
    period = dplyr::if_else(year <= 2008, "pre_2009", "post_2009"),
    doc_symbol = stringr::str_replace(unres, "^R/", "A/RES/"),
    issue_family = issue_family(issue),
    human_rights_issue = stringr::str_detect(tidyr::replace_na(issue, ""), "Human rights"),
    document_url = dplyr::if_else(
      is.na(doc_symbol) | doc_symbol == "",
      NA_character_,
      paste0("https://docs.un.org/en/", doc_symbol)
    )
  ) |>
  dplyr::filter(
    year >= 2004,
    year <= 2012,
    !is.na(vote_brazil),
    !is.na(vote_china),
    !is.na(title_key),
    title_key != "",
    !stringr::str_detect(title_key, "^(the acting president|the president)"),
    vote_brazil != "absent",
    vote_china != "absent"
  )

family_summary <- paired_votes |>
  dplyr::summarise(
    title = dplyr::first(descr),
    issue = paste(sort(unique(tidyr::replace_na(issue, "Sem issue codificado"))), collapse = " | "),
    issue_family = paste(sort(unique(issue_family)), collapse = " | "),
    human_rights_issue = any(human_rights_issue),
    n_votes = dplyr::n(),
    n_pre = sum(period == "pre_2009"),
    n_post = sum(period == "post_2009"),
    pre_divergent = sum(period == "pre_2009" & convergence == "divergente"),
    pre_convergent = sum(period == "pre_2009" & convergence == "convergente"),
    post_divergent = sum(period == "post_2009" & convergence == "divergente"),
    post_convergent = sum(period == "post_2009" & convergence == "convergente"),
    pre_examples = paste0(
      doc_symbol[period == "pre_2009" & convergence == "divergente"],
      " (BR=", vote_brazil[period == "pre_2009" & convergence == "divergente"],
      ", CH=", vote_china[period == "pre_2009" & convergence == "divergente"],
      ")",
      collapse = "; "
    ),
    post_convergent_examples = paste0(
      doc_symbol[period == "post_2009" & convergence == "convergente"],
      " (BR=", vote_brazil[period == "post_2009" & convergence == "convergente"],
      ", CH=", vote_china[period == "post_2009" & convergence == "convergente"],
      ")",
      collapse = "; "
    ),
    years = paste(sort(unique(year)), collapse = ", "),
    .by = title_key
  ) |>
  dplyr::mutate(
    positive_candidate = n_pre > 0 & n_post > 0 & pre_divergent > 0 & post_convergent > 0,
    non_human_rights_candidate = positive_candidate & !human_rights_issue,
    priority = dplyr::case_when(
      non_human_rights_candidate & n_votes >= 3 & n_post >= 2 ~ "alta",
      non_human_rights_candidate & n_votes >= 2 ~ "média",
      non_human_rights_candidate ~ "baixa",
      TRUE ~ "fora do escopo"
    ),
    case_strength = dplyr::case_when(
      non_human_rights_candidate & pre_convergent == 0 & post_divergent == 0 ~
        "forte",
      non_human_rights_candidate & post_divergent == 0 ~
        "misto: há convergência pré-2009",
      non_human_rights_candidate ~
        "fraco: ainda há divergência pós-2009",
      TRUE ~ "fora do escopo"
    )
  ) |>
  dplyr::filter(positive_candidate) |>
  dplyr::arrange(human_rights_issue, dplyr::desc(priority == "alta"), issue_family, title_key)

candidate_vote_rows <- paired_votes |>
  dplyr::semi_join(family_summary, by = "title_key") |>
  dplyr::arrange(human_rights_issue, title_key, year, doc_symbol) |>
  dplyr::select(
    title_key,
    issue_family,
    issue,
    human_rights_issue,
    rcid,
    year,
    doc_symbol,
    unres,
    short,
    descr,
    vote_brazil,
    vote_china,
    convergence,
    period,
    document_url
  )

readr::write_csv(family_summary, positive_candidates_out)
readr::write_csv(candidate_vote_rows, positive_vote_rows_out)

non_hr <- family_summary |>
  dplyr::filter(non_human_rights_candidate)

non_hr_titles <- non_hr |>
  dplyr::select(
    title_key,
    title,
    issue_family,
    priority,
    case_strength,
    pre_convergent,
    post_divergent
  )

latest_pre_divergence <- candidate_vote_rows |>
  dplyr::semi_join(non_hr_titles, by = "title_key") |>
  dplyr::filter(period == "pre_2009", convergence == "divergente") |>
  dplyr::arrange(title_key, dplyr::desc(year), dplyr::desc(doc_symbol)) |>
  dplyr::group_by(title_key) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    title_key,
    pre_rcid = rcid,
    pre_year = year,
    pre_resolution = doc_symbol,
    pre_brazil_vote = vote_brazil,
    pre_china_vote = vote_china,
    pre_document_url = document_url
  )

earliest_post_convergence <- candidate_vote_rows |>
  dplyr::semi_join(non_hr_titles, by = "title_key") |>
  dplyr::filter(period == "post_2009", convergence == "convergente") |>
  dplyr::arrange(title_key, year, doc_symbol) |>
  dplyr::group_by(title_key) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    title_key,
    post_rcid = rcid,
    post_year = year,
    post_resolution = doc_symbol,
    post_brazil_vote = vote_brazil,
    post_china_vote = vote_china,
    post_document_url = document_url
  )

non_hr_pairs <- non_hr_titles |>
  dplyr::left_join(latest_pre_divergence, by = "title_key") |>
  dplyr::left_join(earliest_post_convergence, by = "title_key") |>
  dplyr::mutate(
    brazil_changed_to_converge = pre_brazil_vote != post_brazil_vote,
    china_changed_to_converge = pre_china_vote != post_china_vote,
    convergence_direction = dplyr::case_when(
      brazil_changed_to_converge & !china_changed_to_converge ~
        "Brasil mudou; China ficou igual",
      !brazil_changed_to_converge & china_changed_to_converge ~
        "China mudou; Brasil ficou igual",
      brazil_changed_to_converge & china_changed_to_converge ~
        "Brasil e China mudaram",
      TRUE ~ "sem mudança no par selecionado"
    ),
    useful_for_brazil_shift_story = dplyr::case_when(
      convergence_direction == "Brasil mudou; China ficou igual" &
        case_strength == "forte" ~
        "sim",
      convergence_direction == "Brasil mudou; China ficou igual" ~
        "parcial: direção correta, mas há convergência pré-2009",
      TRUE ~ "não"
    )
  ) |>
  dplyr::arrange(dplyr::desc(case_strength == "forte"), title) |>
  dplyr::select(
    title,
    issue_family,
    priority,
    case_strength,
    convergence_direction,
    useful_for_brazil_shift_story,
    pre_convergent,
    post_divergent,
    pre_rcid,
    pre_year,
    pre_resolution,
    pre_brazil_vote,
    pre_china_vote,
    pre_document_url,
    post_rcid,
    post_year,
    post_resolution,
    post_brazil_vote,
    post_china_vote,
    post_document_url
  )

readr::write_csv(non_hr_pairs, positive_pairs_out)

note_lines <- c(
  "# Candidatos positivos fora de direitos humanos",
  "",
  paste0("- Fonte: `unvotes` 0.3.0, tarball CRAN preservado em `", raw_tarball, "`."),
  paste0("- URL da fonte: ", source_url, "."),
  paste0("- Data de acesso da fonte: ", access_date, "."),
  paste0("- MD5 do tarball preservado: `", raw_tarball_md5, "`."),
  "- Regra: família recorrente de resolução com pelo menos uma divergência Brasil-China em 2004-2008 e pelo menos uma convergência em 2009-2012.",
  "- Classificação: casos fortes não têm convergência pré-2009 nem divergência pós-2009; casos mistos satisfazem a regra mínima, mas já tinham alguma convergência antes de 2009.",
  "- Unidade de triagem: `title_key` normalizado a partir da descrição da resolução.",
  paste0("- Pares antes/depois salvos em `", positive_pairs_out, "`."),
  "",
  paste0("Total de famílias positivas encontradas: ", nrow(family_summary), "."),
  paste0("Famílias positivas fora de direitos humanos: ", nrow(non_hr), "."),
  paste0(
    "Casos fortes fora de direitos humanos: ",
    sum(non_hr$case_strength == "forte"),
    "."
  ),
  paste0(
    "Candidatos mistos fora de direitos humanos: ",
    sum(stringr::str_detect(non_hr$case_strength, "^misto")),
    "."
  ),
  "",
  "## Candidatos fora de direitos humanos",
  ""
)

if (nrow(non_hr) == 0) {
  note_lines <- c(note_lines, "Nenhum candidato positivo fora de direitos humanos foi localizado com esta regra.")
} else {
  note_lines <- c(
    note_lines,
    "| Prioridade | Força | Direção | Uso para história | Família | Issue | Pré-divergente | Pós-convergente | Anos |",
    "|---|---|---|---|---|---|---|---|---|",
    apply(
      non_hr |>
        dplyr::left_join(
          non_hr_pairs |>
            dplyr::select(
              title,
              convergence_direction,
              useful_for_brazil_shift_story
            ),
          by = "title"
        ) |>
        dplyr::mutate(
          title = stringr::str_replace_all(title, "\\|", "/"),
          issue_family = stringr::str_replace_all(issue_family, "\\|", "/"),
          convergence_direction = stringr::str_replace_all(convergence_direction, "\\|", "/"),
          useful_for_brazil_shift_story = stringr::str_replace_all(
            useful_for_brazil_shift_story,
            "\\|",
            "/"
          ),
          pre_examples = stringr::str_replace_all(pre_examples, "\\|", "/"),
          post_convergent_examples = stringr::str_replace_all(post_convergent_examples, "\\|", "/")
        ) |>
        dplyr::select(
          priority,
          case_strength,
          convergence_direction,
          useful_for_brazil_shift_story,
          title,
          issue_family,
          pre_examples,
          post_convergent_examples,
          years
        ),
      1,
      function(x) paste0("| ", paste(x, collapse = " | "), " |")
    )
  )
}

writeLines(note_lines, non_hr_note_out, useBytes = TRUE)

message("Saved positive candidates: ", positive_candidates_out)
message("Saved candidate vote rows: ", positive_vote_rows_out)
message("Saved non-human-rights pairs: ", positive_pairs_out)
message("Saved note: ", non_hr_note_out)
