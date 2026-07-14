#!/usr/bin/env Rscript

# Summarize process-tracing document collection for Brazil-China UNGA cases.
# Inputs are produced by collect_un_process_tracing_documents.py.

suppressPackageStartupMessages({
  library(dplyr)
  library(forcats)
  library(ggplot2)
  library(readr)
  library(stringr)
  library(tidyr)
})

access_date <- "2026-05-16"

cases_path <- "data/processed/unvotes/brazil_china_un_vote_cases_2004_2012.csv"
docs_path <- "data/processed/unvotes/brazil_china_un_vote_process_tracing_documents_2004_2012.csv"
speeches_path <- "data/processed/unvotes/brazil_china_un_vote_committee_speech_evidence_2004_2012.csv"
undl_path <- "data/processed/unvotes/brazil_china_un_vote_undl_speeches_search_2004_2012.csv"
missions_path <- "data/processed/unvotes/brazil_china_un_vote_mission_statement_candidates_2004_2012.csv"

summary_out <- "data/processed/unvotes/brazil_china_un_vote_process_tracing_summary_2004_2012.csv"
curated_speeches_out <- "data/processed/unvotes/brazil_china_un_vote_speech_evidence_curated_2004_2012.csv"
mission_match_out <- "data/processed/unvotes/brazil_china_un_vote_mission_evidence_candidates_2004_2012.csv"
figure_png <- "quality_reports/un_vote_cases/figura_2_matriz_documentos_process_tracing.png"
figure_pdf <- "quality_reports/un_vote_cases/figura_2_matriz_documentos_process_tracing.pdf"

dir.create("quality_reports/un_vote_cases", recursive = TRUE, showWarnings = FALSE)

cases <- readr::read_csv(cases_path, show_col_types = FALSE)
docs <- readr::read_csv(docs_path, show_col_types = FALSE)
speeches <- readr::read_csv(speeches_path, show_col_types = FALSE)
undl <- readr::read_csv(undl_path, show_col_types = FALSE)
missions <- readr::read_csv(missions_path, show_col_types = FALSE)

theme_display <- c(
  "Country-specific human rights reports: DPRK" = "DPRK",
  "Country-specific human rights reports: Iran" = "Irã",
  "Moratorium on the death penalty" = "Pena de morte",
  "Globalization and human rights" = "Globalização",
  "UN Human Rights Council reports" = "Conselho DH",
  "Reducing nuclear danger" = "Perigo nuclear",
  "ICJ advisory opinion on nuclear weapons" = "CIJ/nuclear"
)

format_vote <- function(x) {
  dplyr::recode(
    x,
    "yes" = "sim",
    "no" = "não",
    "abstain" = "abstenção",
    .default = x
  )
}

first_speaker_turn <- function(x) {
  x |>
    stringr::str_replace(
      stringr::regex(
        "\n\\s*\\d+\\.\\s*(Mr\\.|Ms\\.|Mrs\\.|Miss|Madam|Sir)\\s+.*$",
        dotall = TRUE
      ),
      ""
    ) |>
    stringr::str_squish()
}

specific_theme_hit <- function(theme, text) {
  dplyr::case_when(
    stringr::str_detect(theme, "DPRK") ~
      stringr::str_detect(text, stringr::regex("Democratic People|DPRK|Korea", ignore_case = TRUE)),
    stringr::str_detect(theme, "Iran") ~
      stringr::str_detect(text, stringr::regex("Islamic Republic of Iran|\\bIran\\b|Iranian", ignore_case = TRUE)),
    stringr::str_detect(theme, "death penalty") ~
      stringr::str_detect(text, stringr::regex("death penalty|moratorium|capital punishment", ignore_case = TRUE)),
    stringr::str_detect(theme, "Globalization") ~
      stringr::str_detect(text, stringr::regex("globali[sz]ation", ignore_case = TRUE)),
    stringr::str_detect(theme, "Human Rights Council") ~
      stringr::str_detect(text, stringr::regex("Human Rights Council", ignore_case = TRUE)),
    TRUE ~ FALSE
  )
}

docs_counts <- docs |>
  dplyr::filter(!stringr::str_detect(download_status, "^failed")) |>
  dplyr::count(case_id, source_resolution, document_layer, name = "n") |>
  tidyr::pivot_wider(
    names_from = document_layer,
    values_from = n,
    values_fill = 0
  )

undl_counts <- undl |>
  dplyr::mutate(items_found = as.integer(items_found)) |>
  dplyr::group_by(case_id, doc_symbol) |>
  dplyr::summarise(
    undl_queries_with_hits = sum(items_found > 0, na.rm = TRUE),
    undl_records_found = sum(items_found, na.rm = TRUE),
    .groups = "drop"
  )

curated_speeches <- speeches |>
  dplyr::filter(speech_found_for_case == "TRUE") |>
  dplyr::mutate(
    speaker_excerpt_first = first_speaker_turn(speaker_excerpt),
    specific_hit = specific_theme_hit(theme, speaker_excerpt_first),
    country_pt = dplyr::recode(country, "Brazil" = "Brasil", "China" = "China"),
    vote_pt = format_vote(vote),
    evidence_type = dplyr::case_when(
      stringr::str_detect(relevance_rule, "theme") ~ "menção substantiva ao tema",
      stringr::str_detect(relevance_rule, "draft") ~ "menção a draft",
      TRUE ~ relevance_rule
    )
  ) |>
  dplyr::filter(specific_hit) |>
  dplyr::arrange(case_id, year, country, committee_record_symbol) |>
  dplyr::group_by(case_id, doc_symbol, country, committee_record_symbol) |>
  dplyr::slice(1) |>
  dplyr::ungroup() |>
  dplyr::select(
    case_id,
    theme,
    doc_symbol,
    year,
    country,
    country_pt,
    vote,
    vote_pt,
    committee_record_symbol,
    committee_record_url,
    evidence_type,
    speaker_excerpt_first,
    date_accessed
  )

speech_counts <- curated_speeches |>
  dplyr::count(case_id, doc_symbol, name = "curated_speech_hits")

mission_candidates <- missions |>
  dplyr::mutate(
    mission_year = as.integer(year),
    mission_text = paste(title, excerpt),
    link_label = paste0(country, " ", mission_year)
  ) |>
  dplyr::select(-year) |>
  tidyr::crossing(
    cases |>
      dplyr::filter(issue == "Human rights") |>
      dplyr::select(case_id, theme, doc_symbol, year)
  ) |>
  dplyr::filter(mission_year == year) |>
  dplyr::mutate(specific_hit = specific_theme_hit(theme, mission_text)) |>
  dplyr::filter(specific_hit) |>
  dplyr::select(
    case_id,
    theme,
    doc_symbol,
    year,
    country,
    title,
    url,
    local_path,
    text_path,
    excerpt,
    date_accessed
  ) |>
  dplyr::arrange(case_id, year, title)

mission_counts <- mission_candidates |>
  dplyr::count(case_id, doc_symbol, name = "mission_candidates")

summary_table <- cases |>
  dplyr::left_join(
    docs_counts,
    by = c("case_id", "doc_symbol" = "source_resolution")
  ) |>
  dplyr::left_join(undl_counts, by = c("case_id", "doc_symbol")) |>
  dplyr::left_join(speech_counts, by = c("case_id", "doc_symbol")) |>
  dplyr::left_join(mission_counts, by = c("case_id", "doc_symbol")) |>
  dplyr::mutate(
    dplyr::across(
      c(
        resolution,
        committee_report,
        draft,
        third_committee_record,
        undl_queries_with_hits,
        undl_records_found,
        curated_speech_hits,
        mission_candidates
      ),
      ~ tidyr::replace_na(.x, 0)
    ),
    tema_curto = dplyr::recode(theme, !!!theme_display, .default = theme),
    voto = paste0("BR ", format_vote(vote_brazil), " / CH ", format_vote(vote_china)),
    resultado = dplyr::if_else(convergence == "convergente", "convergência", "divergência")
  ) |>
  dplyr::select(
    case_id,
    tema_curto,
    theme,
    doc_symbol,
    year,
    vote_brazil,
    vote_china,
    voto,
    convergence,
    resultado,
    committee_report,
    draft,
    third_committee_record,
    curated_speech_hits,
    undl_queries_with_hits,
    undl_records_found,
    mission_candidates,
    date_accessed = source
  )

readr::write_csv(summary_table, summary_out)
readr::write_csv(curated_speeches, curated_speeches_out)
readr::write_csv(mission_candidates, mission_match_out)

matrix_data <- summary_table |>
  dplyr::mutate(
    case_label = paste0(case_id, " | ", tema_curto, " | ", year, " | ", doc_symbol),
    `Relatório` = committee_report > 0,
    `Draft` = draft > 0,
    `Ata 3º Comitê` = third_committee_record > 0,
    `Fala em ata` = curated_speech_hits > 0,
    `Speeches UNDL` = undl_queries_with_hits > 0,
    `Missão nacional` = mission_candidates > 0
  ) |>
  dplyr::select(
    case_id,
    year,
    case_label,
    `Relatório`,
    `Draft`,
    `Ata 3º Comitê`,
    `Fala em ata`,
    `Speeches UNDL`,
    `Missão nacional`
  ) |>
  tidyr::pivot_longer(
    cols = c(`Relatório`, `Draft`, `Ata 3º Comitê`, `Fala em ata`, `Speeches UNDL`, `Missão nacional`),
    names_to = "camada",
    values_to = "disponivel"
  ) |>
  dplyr::mutate(
    camada = factor(camada, levels = c("Relatório", "Draft", "Ata 3º Comitê", "Fala em ata", "Speeches UNDL", "Missão nacional")),
    case_label = forcats::fct_rev(forcats::fct_inorder(case_label))
  )

matrix_plot <- ggplot2::ggplot(matrix_data, ggplot2::aes(x = camada, y = case_label, fill = disponivel)) +
  ggplot2::geom_tile(color = "white", linewidth = 0.35) +
  ggplot2::scale_fill_manual(
    values = c(`TRUE` = "#1b9e77", `FALSE` = "#e6e6e6"),
    labels = c(`TRUE` = "coletado/localizado", `FALSE` = "não localizado"),
    name = NULL
  ) +
  ggplot2::labs(
    x = NULL,
    y = NULL,
    caption = paste0(
      "Figura 2. Matriz de disponibilidade documental para process tracing. ",
      "Fonte: documentos oficiais da ONU, UN Digital Library e registros públicos de missão; acesso em ",
      access_date,
      "."
    )
  ) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(
    panel.grid = ggplot2::element_blank(),
    axis.text.x = ggplot2::element_text(angle = 35, hjust = 1),
    legend.position = "bottom",
    plot.caption = ggplot2::element_text(hjust = 0, size = 8),
    plot.margin = ggplot2::margin(8, 8, 8, 8)
  )

ggplot2::ggsave(figure_png, matrix_plot, width = 9.5, height = 7.2, dpi = 300, bg = "white")
ggplot2::ggsave(figure_pdf, matrix_plot, width = 9.5, height = 7.2, bg = "white")

message("Saved summary: ", summary_out)
message("Saved curated speeches: ", curated_speeches_out)
message("Saved mission candidates: ", mission_match_out)
message("Saved figure: ", figure_png)
