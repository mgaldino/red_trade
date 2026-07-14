#!/usr/bin/env Rscript

# Identify comparable UNGA vote cases for Brazil-China process tracing.
# The script reads the preserved CRAN unvotes source tarball and writes
# processed outputs. It does not modify raw files.

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
sources_out <- file.path(processed_dir, "SOURCES.yaml")
dictionary_out <- file.path(processed_dir, "DATA_DICTIONARY.md")
cases_out <- file.path(processed_dir, "brazil_china_un_vote_cases_2004_2012.csv")
candidate_themes_out <- file.path(processed_dir, "brazil_china_un_vote_candidate_themes_2004_2012.csv")
case_validation_out <- file.path(report_dir, "brazil_china_un_vote_case_validation_2004_2012.csv")
summary_out <- file.path(report_dir, "brazil_china_un_vote_issue_summary_2004_2012.csv")
note_out <- file.path(report_dir, "2026-05-16_nota_analitica_casos_onu.md")
collection_log_out <- file.path(report_dir, "COLLECTION_LOG.md")

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(raw_tarball)) {
  stop(
    "Missing raw tarball: ", raw_tarball,
    ". Download it first from ", source_url
  )
}

if (file.info(raw_tarball)$size <= 0) {
  stop("Raw tarball exists but is empty: ", raw_tarball)
}

raw_sha256 <- tryCatch(
  {
    sha_line <- system2("shasum", c("-a", "256", raw_tarball), stdout = TRUE)
    strsplit(sha_line[[1]], "\\s+")[[1]][[1]]
  },
  error = function(e) NA_character_
)

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
    vote_brazil = as.character(vote_BR),
    vote_china = as.character(vote_CN),
    convergence = dplyr::if_else(vote_brazil == vote_china, "convergente", "divergente"),
    period = dplyr::if_else(year <= 2008, "pre_2009", "post_2009"),
    title_key = make_title_key(descr),
    doc_symbol = stringr::str_replace(unres, "^R/", "A/RES/"),
    document_url = dplyr::if_else(
      is.na(doc_symbol) | doc_symbol == "",
      NA_character_,
      paste0("https://docs.un.org/en/", doc_symbol)
    ),
    vote_record_url = dplyr::if_else(
      is.na(doc_symbol) | doc_symbol == "",
      NA_character_,
      paste0(
        "https://digitallibrary.un.org/search?ln=en&p=",
        utils::URLencode(doc_symbol, reserved = TRUE)
      )
    )
  ) |>
  dplyr::filter(
    year >= 2004,
    year <= 2012,
    !is.na(vote_brazil),
    !is.na(vote_china),
    !is.na(short),
    vote_brazil != "absent",
    vote_china != "absent"
  )

issue_counts <- paired_votes |>
  dplyr::summarise(
    n_votes = dplyr::n(),
    n_divergent = sum(convergence == "divergente"),
    n_convergent = sum(convergence == "convergente"),
    .by = c(issue, period)
  )

issue_summary <- issue_counts |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(n_votes, n_divergent, n_convergent),
    values_fill = 0
  ) |>
  dplyr::mutate(
    divergence_rate_pre_2009 = dplyr::if_else(
      n_votes_pre_2009 > 0,
      n_divergent_pre_2009 / n_votes_pre_2009,
      NA_real_
    ),
    divergence_rate_post_2009 = dplyr::if_else(
      n_votes_post_2009 > 0,
      n_divergent_post_2009 / n_votes_post_2009,
      NA_real_
    )
  ) |>
  dplyr::arrange(dplyr::desc(n_divergent_pre_2009), dplyr::desc(n_votes_post_2009))

# Representative cases selected after issue-level screening:
# - Positive cases: repeated themes with pre-2009 divergence and at least one
#   comparable 2009-2012 convergence.
# - Negative cases: repeated themes with pre-2009 divergence and continued
#   2009-2012 divergence.
# The full candidate table is exported below so the manual triage remains
# auditable and can be tightened before full process tracing.
case_plan <- tibble::tribble(
  ~case_id, ~theme, ~doc_symbol, ~case_type, ~selection_note,
  "P1", "ICJ advisory opinion on nuclear weapons", "A/RES/63/49", "positivo - pre-divergencia", "Brazil yes / China abstain before 2009.",
  "P1", "ICJ advisory opinion on nuclear weapons", "A/RES/64/55", "positivo - pos-convergencia", "Comparable recurring resolution; both voted yes after 2009.",
  "P1", "ICJ advisory opinion on nuclear weapons", "A/RES/65/76", "positivo - pos-convergencia", "Comparable recurring resolution; both voted yes after 2009.",
  "P2", "Globalization and human rights", "A/RES/63/176", "positivo - pre-divergencia", "Brazil abstain / China yes before 2009.",
  "P2", "Globalization and human rights", "A/RES/65/216", "positivo - pos-convergencia", "Comparable recurring resolution; both voted yes after 2009.",
  "P2", "Globalization and human rights", "A/RES/67/165", "positivo - pos-convergencia", "Comparable recurring resolution; both voted yes after 2009.",
  "P3", "UN Human Rights Council reports", "A/RES/63/160", "positivo - pre-divergencia", "Brazil abstain / China yes before 2009.",
  "P3", "UN Human Rights Council reports", "A/RES/65/195", "positivo - pos-convergencia", "Comparable Human Rights Council report; both voted yes after 2009.",
  "P3", "UN Human Rights Council reports", "A/RES/66/136", "positivo - pos-convergencia", "Comparable Human Rights Council report; both voted yes after 2009.",
  "N1", "Country-specific human rights reports: DPRK", "A/RES/62/167", "negativo - pre-divergencia", "Brazil yes / China no before 2009.",
  "N1", "Country-specific human rights reports: DPRK", "A/RES/64/175", "negativo - pos-divergencia", "Comparable country-specific report remains divergent after 2009.",
  "N1", "Country-specific human rights reports: DPRK", "A/RES/66/174", "negativo - pos-divergencia", "Comparable country-specific report remains divergent after 2009.",
  "N2", "Country-specific human rights reports: Iran", "A/RES/62/168", "negativo - pre-divergencia", "Brazil abstain / China no before 2009.",
  "N2", "Country-specific human rights reports: Iran", "A/RES/64/176", "negativo - pos-divergencia", "Comparable country-specific report remains divergent after 2009.",
  "N2", "Country-specific human rights reports: Iran", "A/RES/66/175", "negativo - pos-divergencia", "Comparable country-specific report remains divergent after 2009.",
  "N3", "Reducing nuclear danger", "A/RES/59/79", "negativo - pre-divergencia", "Brazil yes / China abstain before 2009.",
  "N3", "Reducing nuclear danger", "A/RES/64/37", "negativo - pos-divergencia", "Comparable recurring resolution remains divergent after 2009.",
  "N3", "Reducing nuclear danger", "A/RES/67/45", "negativo - pos-divergencia", "Comparable recurring resolution remains divergent after 2009.",
  "N4", "Moratorium on the death penalty", "A/RES/62/149", "negativo - pre-divergencia", "Brazil yes / China no before 2009.",
  "N4", "Moratorium on the death penalty", "A/RES/65/206", "negativo - pos-divergencia", "Comparable recurring resolution remains divergent after 2009.",
  "N4", "Moratorium on the death penalty", "A/RES/67/176", "negativo - pos-divergencia", "Comparable recurring resolution remains divergent after 2009."
)

cases <- case_plan |>
  dplyr::left_join(
    paired_votes |>
      dplyr::select(
        rcid,
        year,
        doc_symbol,
        unres,
        short,
        descr,
        issue,
        title_key,
        vote_brazil,
        vote_china,
        convergence,
        document_url,
        vote_record_url
      ),
    by = "doc_symbol"
  ) |>
  dplyr::mutate(
    evidence_available = paste(
      "UNGA roll-call vote metadata from unvotes/Voeten; official resolution",
      "text available through docs.un.org; vote-record search available",
      "through the UN Digital Library. Explanations of vote were not",
      "systematically collected in this round."
    ),
    source = paste0(
      "unvotes 0.3.0 CRAN tarball (", source_url,
      "), accessed ", access_date
    )
  ) |>
  dplyr::arrange(case_id, year, doc_symbol)

missing_cases <- cases |>
  dplyr::filter(is.na(rcid)) |>
  dplyr::select(case_id, doc_symbol)

if (nrow(missing_cases) > 0) {
  stop(
    "Selected cases not found in unvotes data: ",
    paste(missing_cases$doc_symbol, collapse = ", ")
  )
}

case_validation <- cases |>
  dplyr::mutate(
    case_family = dplyr::if_else(
      stringr::str_detect(case_type, "^positivo"),
      "positivo",
      "negativo"
    )
  ) |>
  dplyr::summarise(
    case_family = dplyr::first(case_family),
    n_pre = sum(year <= 2008),
    n_post = sum(year >= 2009),
    has_pre_divergence = any(year <= 2008 & convergence == "divergente"),
    has_post_convergence = any(year >= 2009 & convergence == "convergente"),
    has_post_divergence = any(year >= 2009 & convergence == "divergente"),
    valid = dplyr::case_when(
      case_family == "positivo" ~
        n_pre > 0 & n_post > 0 & has_pre_divergence & has_post_convergence,
      case_family == "negativo" ~
        n_pre > 0 & n_post > 0 & has_pre_divergence & has_post_divergence,
      TRUE ~ FALSE
    ),
    .by = c(case_id, theme)
  )

if (any(!case_validation$valid)) {
  bad_cases <- case_validation |>
    dplyr::filter(!valid) |>
    dplyr::pull(case_id)
  stop("Selected cases failed pre/post validation: ", paste(bad_cases, collapse = ", "))
}

selected_titles <- cases |>
  dplyr::distinct(title_key, case_id, theme)

candidate_themes <- paired_votes |>
  dplyr::filter(!is.na(title_key), title_key != "") |>
  dplyr::summarise(
    title = dplyr::first(descr),
    issue = paste(sort(unique(stats::na.omit(issue))), collapse = "; "),
    first_year = min(year),
    last_year = max(year),
    n_votes = dplyr::n(),
    n_pre = sum(year <= 2008),
    n_post = sum(year >= 2009),
    pre_divergent = sum(year <= 2008 & convergence == "divergente"),
    post_divergent = sum(year >= 2009 & convergence == "divergente"),
    post_convergent = sum(year >= 2009 & convergence == "convergente"),
    doc_symbols = paste(sort(unique(doc_symbol)), collapse = "; "),
    .by = title_key
  ) |>
  dplyr::mutate(
    issue = dplyr::na_if(issue, ""),
    positive_candidate = n_pre > 0 & n_post > 0 & pre_divergent > 0 & post_convergent > 0,
    negative_candidate = n_pre > 0 & n_post > 0 & pre_divergent > 0 & post_divergent > 0
  ) |>
  dplyr::filter(positive_candidate | negative_candidate) |>
  dplyr::left_join(selected_titles, by = "title_key") |>
  dplyr::mutate(
    selected = !is.na(case_id),
    selection_status = dplyr::case_when(
      selected ~ "selected",
      positive_candidate & negative_candidate ~ "not selected: mixed positive/negative candidate",
      positive_candidate ~ "not selected: positive candidate",
      negative_candidate ~ "not selected: negative candidate",
      TRUE ~ "not selected"
    )
  ) |>
  dplyr::arrange(dplyr::desc(selected), title_key)

readr::write_csv(cases, cases_out)
readr::write_csv(candidate_themes, candidate_themes_out)
readr::write_csv(case_validation, case_validation_out)
readr::write_csv(issue_summary, summary_out)

writeLines(
  c(
    "sources:",
    "  - id: unvotes_cran_0_3_0",
    "    name: United Nations General Assembly Voting Data",
    "    provider: CRAN package unvotes, based on Erik Voeten UNGA voting data",
    paste0("    url: \"", source_url, "\""),
    "    access_method: bulk_download",
    "    requires_credentials: false",
    "    license: MIT package license; underlying public UNGA voting data",
    "    variables_used:",
    "      - rcid",
    "      - country_code",
    "      - vote",
    "      - unres",
    "      - short",
    "      - descr",
    "      - issue",
    "    temporal_coverage: 1946-2019 in source; 2004-2012 used here",
    "    geographic_coverage: UN member states",
    "    unit_of_analysis: country-roll-call vote",
    paste0("    download_script: scripts/diagnostics/identify_unga_vote_cases_pre_post_2009.R"),
    paste0("    date_accessed: \"", access_date, "\""),
    paste0("    checksum_sha256: \"", raw_sha256, "\""),
    "    notes: Raw tarball preserved at data/raw/unvotes/unvotes_0.3.0.tar.gz.",
    "  - id: un_docs",
    "    name: Official UN Documents",
    "    provider: United Nations",
    "    url: \"https://docs.un.org/\"",
    "    access_method: web",
    "    requires_credentials: false",
    "    license: Public UN documents",
    "    variables_used:",
    "      - resolution text links generated from A/RES symbols",
    "    temporal_coverage: 2004-2012 selected resolutions",
    "    geographic_coverage: UN General Assembly",
    "    unit_of_analysis: resolution",
    paste0("    download_script: scripts/diagnostics/identify_unga_vote_cases_pre_post_2009.R"),
    paste0("    date_accessed: \"", access_date, "\""),
    "    notes: Link construction uses https://docs.un.org/en/{document_symbol}."
  ),
  sources_out,
  useBytes = TRUE
)

writeLines(
  c(
    "# Dicionário de dados: casos Brasil-China na AGNU",
    "",
    "## brazil_china_un_vote_cases_2004_2012.csv",
    "",
    "| Variável | Tipo | Descrição | Fonte |",
    "|---|---|---|---|",
    "| case_id | texto | Identificador do conjunto comparável de resoluções | Autor |",
    "| theme | texto | Tema substantivo do conjunto comparável | Autor, com base em short/descr/issue |",
    "| doc_symbol | texto | Símbolo oficial da resolução em formato A/RES/session/number | unvotes; transformação de unres |",
    "| case_type | texto | Tipo de caso: positivo/negativo e papel pré/pós-2009 | Autor |",
    "| selection_note | texto | Justificativa resumida da seleção do caso | Autor |",
    "| rcid | numérico | Identificador do roll call no banco unvotes | unvotes |",
    "| year | numérico | Ano da votação | unvotes |",
    "| short | texto | Rótulo curto da votação | unvotes |",
    "| descr | texto | Descrição da votação | unvotes |",
    "| issue | texto | Tema(s) codificado(s) no unvotes | unvotes |",
    "| title_key | texto | Chave normalizada da descrição, usada para auditar temas recorrentes | Autor |",
    "| vote_brazil | texto | Voto do Brasil | unvotes |",
    "| vote_china | texto | Voto da China | unvotes |",
    "| convergence | texto | Convergente quando Brasil e China votam igual; divergente caso contrário | Autor |",
    "| evidence_available | texto | Evidência documental disponível nesta rodada | Autor |",
    "| document_url | texto | Link para o texto oficial da resolução | UN docs |",
    "| vote_record_url | texto | Link de busca na UN Digital Library pelo registro da resolução/voto | UN Digital Library |",
    "| source | texto | Fonte e data de acesso | Autor |",
    "",
    "## brazil_china_un_vote_candidate_themes_2004_2012.csv",
    "",
    "Tabela auditável de todos os títulos recorrentes no período que satisfazem pelo menos uma regra de candidato: divergência pré-2009 e convergência pós-2009, ou divergência pré-2009 e divergência pós-2009. A coluna `selected` indica se o tema entrou na tabela final.",
    "",
    "## brazil_china_un_vote_case_validation_2004_2012.csv",
    "",
    "Tabela de validação dos casos selecionados. Casos positivos precisam ter ao menos uma divergência pré-2009 e uma convergência pós-2009. Casos negativos precisam ter ao menos uma divergência pré-2009 e uma divergência pós-2009."
  ),
  dictionary_out,
  useBytes = TRUE
)

positive_n <- cases |>
  dplyr::filter(stringr::str_detect(case_type, "^positivo")) |>
  dplyr::distinct(case_id) |>
  nrow()

negative_n <- cases |>
  dplyr::filter(stringr::str_detect(case_type, "^negativo")) |>
  dplyr::distinct(case_id) |>
  nrow()

writeLines(
  c(
    "# Nota analítica: casos de votação Brasil-China na AGNU, pré e pós-2009",
    "",
    "## Escopo e fonte",
    "",
    paste0(
      "Esta nota usa o pacote público `unvotes` 0.3.0, baixado do CRAN em ",
      access_date,
      ", para identificar votações nominais da Assembleia Geral da ONU em que Brasil e China participaram entre 2004 e 2012. O período pré-tratamento cobre 2004-2008; o período pós-tratamento cobre 2009-2012. Os arquivos brutos foram preservados em `data/raw/unvotes/`, e os dados derivados estão em `data/processed/unvotes/`."
    ),
    "",
    "## Regra de seleção",
    "",
    paste0(
      "A seleção partiu de temas recorrentes no banco (`issue`, `short` e `descr`), não de casos isolados. Para auditar o risco de cherry-picking, o script gera também a tabela `",
      candidate_themes_out,
      "`, com todos os títulos recorrentes que satisfazem a regra mínima de candidato. Casos positivos são conjuntos comparáveis em que havia divergência Brasil-China antes de 2009 e aparece convergência em votações substantivamente semelhantes entre 2009 e 2012. Casos negativos são conjuntos comparáveis em que a divergência pré-2009 persiste no período pós-2009."
    ),
    "",
    "A tabela final é uma triagem substantiva, não uma enumeração exaustiva. A seleção prioriza séries recorrentes com títulos e temas comparáveis, presença de votos antes e depois de 2009, e contraste claro entre casos positivos e negativos. Temas candidatos não selecionados permanecem na tabela auditável para que a próxima rodada possa ampliar ou substituir casos sem depender de exemplos isolados.",
    "",
    "## Tabela 1. Casos selecionados de votação Brasil-China na AGNU",
    "",
    paste0(
      "A tabela processada contém ", nrow(cases), " linhas, cobrindo ",
      positive_n, " conjuntos positivos e ", negative_n,
      " conjuntos negativos. Arquivo: `", cases_out, "`."
    ),
    "",
    "## Leitura substantiva",
    "",
    "Os casos positivos não sugerem uma virada instantânea e uniforme em 2009. O tema de globalização e direitos humanos, por exemplo, permaneceu divergente em 2009, mas convergiu em votações comparáveis a partir de 2010. Esse padrão é consistente com a leitura gradual do efeito: o marco de status pode aumentar a saliência imediatamente, mas a mudança observável em posições diplomáticas pode depender de negociação, aprendizado, custos reputacionais e rotinas institucionais.",
    "",
    "Os casos negativos são igualmente importantes. Votações sobre relatórios específicos de direitos humanos (DPRK e Irã), redução do perigo nuclear e moratória da pena de morte continuaram divergentes após 2009. Isso reduz o risco de uma narrativa de alinhamento irrestrito: o mecanismo proposto deve ser interpretado como uma aproximação média em áreas onde havia margem diplomático-institucional para ajuste, não como convergência automática em todos os temas.",
    "",
    "## Limites",
    "",
    "A rodada coletou metadados de votação e links oficiais para resoluções/documentos. Explanations of vote, discursos nacionais e registros diplomáticos ainda precisam ser coletados sistematicamente para transformar esses casos em process tracing completo. Os links `document_url` e `vote_record_url` na tabela indicam o ponto de partida documental para essa etapa."
  ),
  note_out,
  useBytes = TRUE
)

writeLines(
  c(
    "# Log de coleta: UNGA voting cases",
    "",
    paste0("- Data de acesso: ", access_date),
    paste0("- Fonte bruta: ", source_url),
    paste0("- Arquivo bruto preservado: ", raw_tarball),
    paste0("- SHA-256 do arquivo bruto: ", raw_sha256),
    paste0("- Tabela derivada: ", cases_out),
    paste0("- Tabela auditável de candidatos: ", candidate_themes_out),
    paste0("- Validação dos casos selecionados: ", case_validation_out),
    paste0("- Sumário por tema: ", summary_out),
    paste0("- Nota analítica: ", note_out),
    "",
    "Validações executadas:",
    "- Arquivo bruto existente e não vazio antes do processamento.",
    "- Votos ausentes foram excluídos da comparação Brasil-China.",
    "- Janela temporal restrita logicamente a 2004-2012.",
    "- Cada resolução selecionada foi validada contra o banco unvotes.",
    "- Cada caso selecionado foi validado quanto a presença pré/pós-2009 e padrão de convergência/divergência esperado.",
    "- A variável `convergence` foi gerada apenas por comparação direta entre votos do Brasil e da China."
  ),
  collection_log_out,
  useBytes = TRUE
)

cat("Saved cases: ", cases_out, "\n", sep = "")
cat("Saved candidate themes: ", candidate_themes_out, "\n", sep = "")
cat("Saved case validation: ", case_validation_out, "\n", sep = "")
cat("Saved issue summary: ", summary_out, "\n", sep = "")
cat("Saved note: ", note_out, "\n", sep = "")
cat("Saved sources: ", sources_out, "\n", sep = "")
