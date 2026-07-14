#!/usr/bin/env Rscript
# -*- coding: UTF-8 -*-

# Prepare an operational /goal prompt and analytic report for Revision Goal 5.
# This script reads local report sources and writes Markdown outputs only.
# It does not modify the paper, _targets.R, _targets/, or _targets.yaml.

invisible(try(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"), silent = TRUE))
options(scipen = 999, encoding = "UTF-8")

find_repo_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (
      file.exists(file.path(current, "AGENTS.md")) &&
        file.exists(file.path(current, "_targets.R"))
    ) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find repo root from: ", start)
    }
    current <- parent
  }
}

repo_root <- find_repo_root()
out_dir <- file.path(repo_root, "quality_reports")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

rel_path <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (!startsWith(normalized, paste0(repo_root, "/"))) {
    return(normalized)
  }
  substr(normalized, nchar(repo_root) + 2L, nchar(normalized))
}

read_utf8_lines <- function(path) {
  bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  text <- rawToChar(bytes)
  text <- iconv(text, from = "UTF-8", to = "UTF-8", sub = NA)
  if (is.na(text)) {
    stop("Invalid UTF-8 input in: ", rel_path(path))
  }
  strsplit(text, "\r?\n", perl = TRUE)[[1]]
}

write_utf8_lines <- function(lines, path) {
  text <- paste(enc2utf8(lines), collapse = "\n")
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(paste0(text, "\n")), con)
}

html_source <- file.path(
  repo_root,
  "quality_reports",
  "chatgpt_pro_revision_goals_paper_v4_20260517_1916.html"
)

md_candidates <- c(
  file.path(
    repo_root,
    "quality_reports",
    "chatgpt_pro_revision_goals_paper_v4_20260517_1916.md"
  ),
  file.path(
    repo_root,
    "reports",
    "chatgpt_pro_revision_goals_paper_v4_20260517_1916.md"
  )
)

source_md <- md_candidates[file.exists(md_candidates)][1]

if (!file.exists(html_source)) {
  stop("HTML source not found: ", html_source)
}
if (is.na(source_md) || !file.exists(source_md)) {
  stop("Markdown mirror not found for clean Goal 5 extraction.")
}

html_lines <- read_utf8_lines(html_source)
html_text <- paste(html_lines, collapse = " ")
html_goal_id <- "goal-5-strengthen-the-brazil-sdid-identification-package-without-bloating-the-main-text"
if (!any(grepl(html_goal_id, html_lines, fixed = TRUE))) {
  stop("Goal 5 anchor not found in HTML source.")
}

md_lines <- read_utf8_lines(source_md)
md_text <- paste(md_lines, collapse = " ")
goal_title_phrase <- "Strengthen the Brazil SDiD identification package without bloating the main text"
if (!grepl(goal_title_phrase, html_text, fixed = TRUE)) {
  stop("Goal 5 title phrase not found in HTML source.")
}
if (!grepl(goal_title_phrase, md_text, fixed = TRUE)) {
  stop("Goal 5 title phrase not found in Markdown mirror: ", rel_path(source_md))
}
start <- grep("^### Goal 5", md_lines)
end <- grep("^### Goal 6", md_lines)
if (length(start) != 1 || length(end) != 1 || start >= end) {
  stop("Could not isolate Goal 5 in Markdown source.")
}
goal5_lines <- md_lines[start:(end - 1)]

date_stamp <- "2026-05-18"
prompt_path <- file.path(out_dir, "goal_05_sdid_identification_prompt_20260518.md")
report_path <- file.path(out_dir, "2026-05-18_goal5_sdid_identification_prompt_report.md")
pdf_path <- file.path(out_dir, "2026-05-18_goal5_sdid_identification_prompt_report.pdf")
excerpt_path <- file.path(out_dir, "goal5_source_excerpt_20260518.md")
session_info_path <- file.path(out_dir, "goal5_prompt_generator_session_info_20260518.txt")

source_metadata <- data.frame(
  source = c("html_source", "markdown_mirror_used"),
  path = c(rel_path(html_source), rel_path(source_md)),
  modified = format(
    as.POSIXct(file.info(c(html_source, source_md))$mtime),
    "%Y-%m-%d %H:%M:%S %Z"
  ),
  md5 = as.character(tools::md5sum(c(html_source, source_md))),
  stringsAsFactors = FALSE
)

source_metadata_lines <- c(
  "| Fonte | Caminho | Modificado | MD5 |",
  "| --- | --- | --- | --- |",
  paste0(
    "| ",
    source_metadata$source,
    " | `",
    source_metadata$path,
    "` | ",
    source_metadata$modified,
    " | `",
    source_metadata$md5,
    "` |"
  )
)

goal_prompt <- c(
  "/goal Goal 5 - Fortalecer o pacote de identificação do SDiD Brasil sem inflar o texto principal",
  "",
  "Objetivo imediato: produzir um relatório diagnóstico e reprodutível, com análises e sugestões de revisão para o Goal 5. Não revise nem edite o paper nesta fase.",
  "",
  "Fonte do Goal 5:",
  "- `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.html`",
  "- Usar o bloco 'Goal 5 - Strengthen the Brazil SDiD identification package without bloating the main text'.",
  "",
  "Skills obrigatórias:",
  "- `causal-did-identification`: reconstruir desenho, estimando, suposições, ameaças e diagnósticos possíveis.",
  "- `causal-did-estimation`: avaliar alinhamento entre estimando, SDiD, donor pool, controles, transformações e amostra.",
  "- `causal-did-inference`: avaliar placebo inference, poucos tratados, dependência, placebos, sensibilidade e limites dos p-valores.",
  "- `data-analysis-r`: toda computação deve ficar em scripts R salvos, com outputs reprodutíveis.",
  "- `review-r`: revisão independente dos scripts R e do relatório técnico; quem revisa não edita.",
  "",
  "Restrições do repositório:",
  "- Não alterar `paper_v4.Rmd` nesta fase.",
  "- Não alterar `_targets.R`, `_targets/` ou `_targets.yaml`.",
  "- Não rodar `targets::tar_make()` sem autorização explícita.",
  "- Ler alvos existentes apenas com `targets::tar_read()` quando necessário.",
  "- Nada de código R inline, heredoc ou análises manuais não salvas; toda computação deve ser feita por scripts em `scripts/diagnostics/`.",
  "- Usar `dplyr::select()` sempre que selecionar colunas em R.",
  "- Preservar dados brutos; escrever apenas outputs novos em `quality_reports/`.",
  "- Outputs em UTF-8; tabelas e figuras citáveis devem ter número e caption no relatório.",
  "",
  "Separação de papéis:",
  "- Implementador: escreve e executa scripts, gera outputs e relatório diagnóstico. Não atribui a nota final de revisão.",
  "- Revisor independente: usa `review-r` para revisar scripts e relatório, não edita arquivos e entrega parecer separado.",
  "- Quem implementa não revisa; quem revisa não implementa.",
  "- Se o revisor der nota menor que A, o implementador deve corrigir os problemas apontados e reenviar à revisão. Iterar até obter A. Salvar cada rodada como `quality_reports/review_r_goal5_sdid_identification_roundN_YYYYMMDD.md`.",
  "",
  "Perguntas a responder no relatório:",
  "1. O desenho brasileiro está claramente definido como SDiD com uma unidade tratada, tratamento em 2009, outcome de distância absoluta em ideal point à China e estimando ATT médio pós-2009?",
  "2. O main text consegue defender o resultado em até três páginas: estimando, fit, estimate, lógica dos placebos e limitações?",
  "3. Quais diagnósticos de fit pré-tratamento já existem nos targets ou no paper, e quais ainda precisam ser calculados ou reportados de modo compacto?",
  "4. O donor pool atual é defensável? Quais controles têm peso alto, quais exclusões/sensibilidades são necessárias, e que parte deve ir para o apêndice?",
  "5. Os placebos de 2003, 2005 e 2012 estão rotulados pela ameaça causal correta: promoção de rank inferior, crescimento comercial rápido sem rank 1 e timing alternativo posterior?",
  "6. Como o texto deve tratar confounders simultâneos no Brasil, especialmente Lula, BRICS/diplomacia Sul-Sul e crise de 2008, sem prometer que foram plenamente descartados?",
  "7. A inferência placebo é apropriada para um caso com uma unidade tratada? Quais limites devem ser reconhecidos?",
  "",
  "Script diagnóstico esperado:",
  "- Criar `scripts/diagnostics/diagnose_goal5_sdid_identification_package.R`.",
  "- O script deve ler, quando disponíveis, `synth_fit`, `se_synth`, `synth_fit_latam`, `se_synth_latam`, `rmspe_diagnostics`, `permutation_results`, `sensitivity_results`, `donor_table`, `plot_weights_coef`, `placebo_teste_treatment02`, `se_synth_placebo2`, `placebo_teste_treatment04`, `se_synth_placebo3`, `placebo_teste_treatment11` e `se_synth_placebo1`.",
  "- Se algum target não existir ou estiver desatualizado, registrar isso em tabela de auditabilidade em vez de rodar o pipeline.",
  "- Produzir tabelas CSV e um relatório Markdown em `quality_reports/`.",
  "- Salvar `sessionInfo()` em arquivo `.txt`.",
  "",
  "Diagnósticos mínimos a propor ou executar no relatório:",
  "- Tabela 1: contrato causal do SDiD Brasil, com unidade, tratamento, período, outcome, estimando, donor pool e comparação relevante.",
  "- Tabela 2: fit pré-tratamento, incluindo RMSPE pré, RMSPE pós, razão pós/pré e, se possível, comparação placebo-in-space.",
  "- Tabela 3: estimativa principal, SE placebo, p-valor/rank placebo, média pré-tratamento do Brasil e mudança percentual. Reportar IC/intervalo apenas se justificado pela rotina placebo; caso contrário, reportar distribuição placebo e limites de poder.",
  "- Tabela 4: donor weights e covariate balance em formato compacto; long donor plots ficam no apêndice.",
  "- Tabela 5: donor-pool sensitivities: Latin America-only, leave-one-high-weight-donor-out, exclusão de doadores com China top-rank reversals relevantes e exclusão de doadores com choques China pós-2009 identificáveis.",
  "- Tabela 6: placebos/falsificações de 2003, 2005 e 2012, rotulados pela ameaça que testam.",
  "",
  "Análise causal exigida:",
  "- Separar suposição, evidência disponível, diagnóstico possível, status e implicação.",
  "- Distinguir o verificável do não verificável: fit, placebos e donor sensitivities aumentam plausibilidade, mas não provam identificação.",
  "- Tratar contemporaneous China trade share e variáveis pós-2009 como potenciais bad controls se forem usadas para limpar mecanismo.",
  "- Não vender não significância dos placebos como prova de validade; relatar poder limitado.",
  "- Concluir com veredito: crível, crível com ressalvas, frágil ou não identificado.",
  "",
  "Sugestões de revisão que o relatório deve entregar, sem aplicar no paper:",
  "- Uma arquitetura de seção principal com no máximo três páginas.",
  "- Um mapa do que deve ficar no main text e do que deve ir para o apêndice.",
  "- Um parágrafo de caveat sobre confounders brasileiros, usando linguagem cautelosa.",
  "- Captions ou notas sugeridas para tabelas/figuras, com unidade, erro-padrão, janela e tratamento.",
  "- Lista de alterações futuras em `paper_v4.Rmd`, mas sem editar o arquivo.",
  "",
  "Critérios de aceitação:",
  "- Nenhum arquivo do paper foi editado.",
  "- Nenhum alvo `targets` foi modificado e `targets::tar_make()` não foi rodado.",
  "- Toda computação está em script salvo e reproduzível.",
  "- O relatório deixa claro o que já está sustentado por outputs existentes e o que é recomendação de revisão futura.",
  "- A revisão independente `review-r` deu nota A aos scripts/relatório ou há rodadas documentadas até chegar a A.",
  "- O relatório final inclui links/caminhos de todos os arquivos gerados."
)

report_lines <- c(
  "# Relatório analítico: prompt de Goal 5 para o pacote de identificação SDiD Brasil",
  "",
  paste0("Data: ", date_stamp),
  "",
  "Script gerador: `scripts/diagnostics/prepare_goal5_sdid_identification_prompt.R`",
  "",
  "Este relatório transforma o Goal 5 do relatório ChatGPT Pro em um prompt operacional de `/goal`. Ele não revisa o paper, não edita `paper_v4.Rmd`, não altera `_targets.R`, `_targets/` ou `_targets.yaml`, e não executa `targets::tar_make()`.",
  "",
  "## Reprodução",
  "",
  "Comando usado para gerar os arquivos Markdown:",
  "",
  "```sh",
  "LC_ALL=en_US.UTF-8 Rscript --vanilla scripts/diagnostics/prepare_goal5_sdid_identification_prompt.R",
  "```",
  "",
  "Comando usado para renderizar o PDF do relatório:",
  "",
  "```sh",
  "pandoc quality_reports/2026-05-18_goal5_sdid_identification_prompt_report.md -o quality_reports/2026-05-18_goal5_sdid_identification_prompt_report.pdf --pdf-engine=xelatex",
  "```",
  "",
  "## Fonte lida",
  "",
  "- HTML solicitado: `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.html`.",
  paste0("- Espelho Markdown usado para extração limpa do texto: `", rel_path(source_md), "`."),
  "- Trecho extraído salvo em: `quality_reports/goal5_source_excerpt_20260518.md`.",
  "",
  "Checagens de consistência:",
  "",
  "- O anchor do Goal 5 foi encontrado no HTML.",
  "- A frase-título do Goal 5 foi encontrada tanto no HTML quanto no espelho Markdown usado.",
  "- O trecho salvo em `goal5_source_excerpt_20260518.md` é verificado contra o bloco extraído durante a execução.",
  "",
  "Metadados das fontes:",
  "",
  source_metadata_lines,
  "",
  "## Leitura do Goal 5",
  "",
  "O Goal 5 pede uma reorganização do desenho empírico brasileiro em torno de uma estimativa principal de SDiD e de poucos diagnósticos diretamente ligados às ameaças de identificação. O critério substantivo é que o resultado brasileiro seja defensável em três páginas: estimando, fit, estimativa, lógica dos placebos e um parágrafo de limitações. O restante deve ir ao apêndice.",
  "",
  "## Diagnóstico inicial",
  "",
  "- O paper já contém a estimativa principal de SDiD, placebos de 2003, 2005 e 2012, donor weights no apêndice e uma sensibilidade Latin America-only.",
  "- A lacuna central é de organização e auditabilidade: o main text precisa mostrar fit pré-tratamento e donor evidence em formato compacto, em vez de depender de narrativas dispersas e figuras longas.",
  "- O Goal 5 também exige sensibilidades de donor pool mais direcionadas: leave-one-high-weight-donor-out, exclusão de doadores com China top-rank reversals relevantes e exclusão de doadores com choques China pós-2009 identificáveis.",
  "- O parágrafo atual sobre Lula e política externa brasileira deve ficar mais cauteloso. Placebos e evidência cross-country reduzem algumas alternativas, mas não descartam plenamente BRICS, diplomacia Sul-Sul, crise de 2008 ou choques político-econômicos coincidentes.",
  "",
  "## Identificação causal",
  "",
  "O contrato causal deve ser reconstruído antes de qualquer nova estimação. A unidade tratada é o Brasil, o tratamento é a entrada da China como maior destino de exportação em 2009, o outcome é a distância absoluta do ideal point brasileiro em relação à China, e o estimando é o ATT médio pós-2009 para o episódio brasileiro. O donor pool precisa representar uma trajetória contrafactual plausível para o Brasil sem rank reversal.",
  "",
  "Principais suposições e diagnósticos:",
  "",
  "| Suposição | Evidência/diagnóstico | Status sugerido | Implicação |",
  "| --- | --- | --- | --- |",
  "| Fit pré-tratamento suficiente | RMSPE, trajetória Brazil vs. synthetic, placebo-in-space | Deve entrar no main text | Sem fit compacto, o leitor não vê por que o contrafactual é plausível |",
  "| Donor pool não contaminado | Pesos, balanceamento, Latin America-only, exclusões por China top-rank reversals | Precisa de tabela auditável | Doadores afetados por choques China podem contaminar o contrafactual |",
  "| No anticipation | Placebos 2003/2005 antes do rank 1 | Parcialmente verificável | Placebos devem ser rotulados como crescimento/promoção sem rank 1, não como prova geral |",
  "| Timing correto | Falsificação 2012 | Parcialmente verificável | Ajuda contra explicação de choque posterior, mas não descarta choque em 2009 |",
  "| Sem confounder brasileiro simultâneo não ponderado | Discussão Lula/BRICS/crise de 2008 | Não testável plenamente | Exige caveat forte e claim reduzido a evidência reduced-form |",
  "",
  "Veredito de identificação para o prompt futuro: crível com ressalvas, condicionado a fit pré-tratamento claro e donor sensitivities documentadas.",
  "",
  "## Estimação",
  "",
  "A revisão deve manter uma estimativa principal, e não transformar o main text em uma bateria de especificações. O SDiD é apropriado para o caso brasileiro se o relatório explicitar o estimando médio pós-tratamento e se a apresentação separar estimate, fit e sensibilidade. Controles contemporâneos de comércio com China ou margens pós-2009 devem ser tratados com cuidado: eles podem ser parte do mecanismo ou variáveis pós-tratamento, não controles neutros.",
  "",
  "Sugestões de revisão futura:",
  "",
  "- Main text: uma tabela curta com estimativa principal, SE placebo, p-valor/rank placebo, fit pré-tratamento e intervalo apenas se a rotina placebo o justificar.",
  "- Main text: uma tabela curta de placebos com coluna `ameaça endereçada`.",
  "- Main text: um parágrafo de donor pool com top weights e balanceamento essencial.",
  "- Apêndice: donor plots longos, tabela completa de pesos, leave-one-out detalhado, Latin America-only, exclusões por donor contamination e detalhes de cálculo.",
  "",
  "## Inferência",
  "",
  "Como há uma unidade tratada, a inferência precisa ser apresentada como placebo-based e limitada pelo donor pool. O relatório futuro deve evitar linguagem binária do tipo 'os placebos provam validade'. O correto é dizer que placebos, fit e donor sensitivities reduzem ameaças específicas, mas que confounders contemporâneos em 2009 permanecem parcialmente não testáveis.",
  "",
  "Placebos devem ser rotulados assim:",
  "",
  "| Teste | Ameaça que endereça | Interpretação correta |",
  "| --- | --- | --- |",
  "| 2003 | Promoção inferior / crescimento comercial antes do rank 1 | Testa se rank inferior produz padrão semelhante |",
  "| 2005 | Crescimento comercial rápido sem status de número 1 | Testa alternativa de volume contínuo |",
  "| 2012 | Timing alternativo posterior | Testa se efeito é atribuído a choque posterior |",
  "",
  "## Protocolo R e revisão independente",
  "",
  "A próxima execução deve criar um script diagnóstico em `scripts/diagnostics/`, ler targets existentes com `targets::tar_read()` e escrever tabelas/relatório em `quality_reports/`. Nada deve ser feito inline. O script precisa registrar targets disponíveis, targets ausentes/desatualizados, `sessionInfo()` e todos os caminhos de output.",
  "",
  "A regra de governança deve ser explícita no `/goal`: quem implementa não revisa; quem revisa não implementa. A revisão `review-r` deve ser separada. Se a nota for menor que A, o implementador corrige e reenvia ao revisor até obter A.",
  "",
  "## Prompt de /goal",
  "",
  "```text",
  goal_prompt,
  "```",
  "",
  "## Arquivos gerados pelo script",
  "",
  paste0("- `", rel_path(excerpt_path), "`"),
  paste0("- `", rel_path(prompt_path), "`"),
  paste0("- `", rel_path(report_path), "`"),
  paste0("- `", rel_path(session_info_path), "`"),
  "",
  "## Arquivo renderizado separadamente",
  "",
  paste0("- `", rel_path(pdf_path), "`")
)

write_utf8_lines(goal5_lines, excerpt_path)
write_utf8_lines(goal_prompt, prompt_path)
write_utf8_lines(report_lines, report_path)
write_utf8_lines(capture.output(sessionInfo()), session_info_path)

written_excerpt <- read_utf8_lines(excerpt_path)
if (!identical(goal5_lines, written_excerpt)) {
  stop("Saved Goal 5 excerpt does not match extracted Goal 5 block.")
}

message("Wrote: ", rel_path(excerpt_path))
message("Wrote: ", rel_path(prompt_path))
message("Wrote: ", rel_path(report_path))
message("Wrote: ", rel_path(session_info_path))
