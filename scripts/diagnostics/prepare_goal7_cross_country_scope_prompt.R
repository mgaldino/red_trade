#!/usr/bin/env Rscript
# -*- coding: UTF-8 -*-

# Prepare an operational /goal prompt and analytic report for Revision Goal 7.
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
  stop("HTML source not found: ", rel_path(html_source))
}
if (is.na(source_md) || !file.exists(source_md)) {
  stop("Markdown mirror not found for clean Goal 7 extraction.")
}

html_lines <- read_utf8_lines(html_source)
html_text <- paste(html_lines, collapse = " ")
html_goal_id <- "goal-7-clean-and-demote-the-cross-country-panel-to-a-credible-scope-probe"
if (!any(grepl(html_goal_id, html_lines, fixed = TRUE))) {
  stop("Goal 7 anchor not found in HTML source.")
}

md_lines <- read_utf8_lines(source_md)
md_text <- paste(md_lines, collapse = " ")
goal_title_phrase <- "Clean and demote the cross-country panel to a credible scope probe"
if (!grepl(goal_title_phrase, html_text, fixed = TRUE)) {
  stop("Goal 7 title phrase not found in HTML source.")
}
if (!grepl(goal_title_phrase, md_text, fixed = TRUE)) {
  stop("Goal 7 title phrase not found in Markdown mirror: ", rel_path(source_md))
}

start <- grep("^### Goal 7", md_lines)
end <- grep("^### Goal 8", md_lines)
if (length(start) != 1 || length(end) != 1 || start >= end) {
  stop("Could not isolate Goal 7 in Markdown source.")
}
goal7_lines <- md_lines[start:(end - 1)]

date_stamp <- "2026-05-18"
prompt_path <- file.path(out_dir, "goal_07_cross_country_scope_prompt_20260518.md")
report_path <- file.path(out_dir, "2026-05-18_goal7_cross_country_scope_prompt_report.md")
pdf_path <- file.path(out_dir, "2026-05-18_goal7_cross_country_scope_prompt_report.pdf")
excerpt_path <- file.path(out_dir, "goal7_source_excerpt_20260518.md")
session_info_path <- file.path(out_dir, "goal7_prompt_generator_session_info_20260518.txt")

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
  "/goal Goal 7 - Limpar e rebaixar o painel cross-country a um scope probe crível",
  "",
  "Objetivo imediato: produzir um relatório diagnóstico e reprodutível, com análises e sugestões de revisão para o Goal 7. Não revise nem edite o paper nesta fase.",
  "",
  "Fonte do Goal 7:",
  "- `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.html`",
  "- Usar o bloco 'Goal 7 - Clean and demote the cross-country panel to a credible scope probe'.",
  "",
  "Skills obrigatórias:",
  "- `causal-did-identification`: reconstruir o desenho cross-country, a regra de tratamento switching, o escopo da amostra e as suposições de identificação.",
  "- `causal-did-estimation`: avaliar alinhamento entre estimando e estimador, especialmente fect IFE, C&S absorvente, PanelMatch, leave-one-out e covariáveis.",
  "- `causal-did-inference`: auditar bootstrap, equivalence tests, diagnostics, p-valores, múltiplas figuras/tabelas e limites inferenciais com poucos tratados/switches.",
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
  "- Se o revisor der nota menor que A, o implementador deve corrigir os problemas apontados e reenviar à revisão. Iterar até obter A. Salvar cada rodada como `quality_reports/review_r_goal7_cross_country_scope_roundN_YYYYMMDD.md`.",
  "",
  "Perguntas a responder no relatório:",
  "1. Qual é o estimando principal do painel cross-country: ATT de China entrar e manter a posição de maior destino de exportação no painel switching, ou outra quantidade?",
  "2. A especificação principal deve ser apenas o `fect` IFE switching-treatment covariate-adjusted (`fect_ife_china_top_cov`), com `log_gdp_pc` e `free_press`? O modelo sem covariáveis deve ir para o apêndice como benchmark, não para a tabela principal?",
  "3. Quais valores de ATT, SE, IC, p-valor, número de treated/control units, bootstrap draws, `r_cv`, placebo/equivalence tests e carryover diagnostics aparecem no texto, Figure 10, Figure 19, Table 3, captions e apêndice?",
  "4. Há inconsistências entre targets, tabelas, figuras, captions e texto? Quais devem ser corrigidas em revisão futura?",
  "5. C&S absorvente, PanelMatch, leave-one-out e raw treated-country panels mudam a conclusão central ou devem ir para o apêndice?",
  "6. O relatório explica exatamente a diferença de estimando entre `fect` e C&S: painel switching completo versus subconjunto absorvente/persistent-treatment?",
  "7. O painel está escrito como evidência 'consistent with' ou 'suggestive of' generalização, salvo se os estimates limpos forem robustamente significativos across definitions/outcomes?",
  "8. O texto explica por que heterogeneidade é esperada, dado que o Brasil é um caso de alta saliência com substituição dos EUA e o painel agrega casos mais fracos?",
  "",
  "Script diagnóstico esperado:",
  "- Criar `scripts/diagnostics/diagnose_goal7_cross_country_scope_probe.R`.",
  "- O script deve ler, quando disponíveis, `china_top_panel`, `china_top_panel_summary`, `china_top_fect_data`, `china_top_fect_cov_data`, `fect_fe_china_top`, `fect_ife_china_top`, `fect_ife_china_top_summary`, `fect_ife_china_top_cov`, `fect_ife_china_top_cov_summary`, `fect_carryover_china_top`, `panelmatch_att_china_top`, `panelmatch_art_china_top`, `fect_ife_china_top_loo`, `did_china_top_absorbing`, `did_china_top_absorbing_summary`, `did_china_top_absorbing_cov`, `did_china_top_absorbing_cov_summary`, `plot_diagnostics_main_china_top`, `plot_diagnostics_equiv_china_top`, `plot_pm_combined_china_top` e `plot_treated_panel_china_top`.",
  "- Se algum target não existir ou estiver desatualizado, registrar isso em tabela de auditabilidade em vez de rodar o pipeline.",
  "- Auditar também os trechos relevantes de `paper_v4.Rmd` por busca textual de valores e labels, mas sem editar o arquivo.",
  "- Produzir tabelas CSV e um relatório Markdown em `quality_reports/`.",
  "- Salvar `sessionInfo()` em arquivo `.txt`.",
  "",
  "Diagnósticos mínimos a propor ou executar no relatório:",
  "- Tabela 1: contrato causal do painel cross-country, com unidade, tratamento switching, escopo da amostra, outcome, estimando, janela e comparação relevante.",
  "- Tabela 2: auditoria de targets e disponibilidade dos objetos cross-country.",
  "- Tabela 3: valores da especificação principal `fect_ife_china_top_cov`: ATT, SE, p-valor, IC se apropriado, `r_cv`, bootstrap draws, N, treated/control units e janela.",
  "- Tabela 3A/apêndice: benchmark `fect_ife_china_top` sem covariáveis, reportado apenas como robustness/benchmark e não como co-principal.",
  "- Tabela 4: auditoria de consistência entre targets, Figure 10, Figure 19, Table 3, captions e texto associado.",
  "- Tabela 5: mapa de estimandos: `fect` switching, C&S absorvente, PanelMatch ATT/ART, leave-one-out e raw treated panels.",
  "- Tabela 6: mapa main text versus appendix: o que fica no corpo, o que vai ao apêndice, e por quê.",
  "- Tabela 7: linguagem recomendada para claim strength: robust evidence, suggestive evidence, diagnostic only, or appendix only.",
  "",
  "Análise causal exigida:",
  "- Separar suposição, evidência disponível, diagnóstico possível, status e implicação.",
  "- Distinguir identificação do painel cross-country de evidência mecanística do Brasil: o painel não mede saliência midiática em cada país.",
  "- Tratar `fect` IFE como especificação principal para tratamento switching; C&S estima um subconjunto absorvente e não é o mesmo estimando.",
  "- Não vender equivalence tests, carryover tests ou bootstrap p-values como prova de validade causal; relatar poder limitado, poucos tratados/switches e sensibilidade a especificação.",
  "- Avaliar se covariáveis são pré-tratamento/exógenas o bastante ou se podem induzir mudança de amostra/estimando.",
  "- Concluir com veredito: crível como scope probe, crível com ressalvas, frágil ou não sustentado.",
  "",
  "Sugestões de revisão que o relatório deve entregar, sem aplicar no paper:",
  "- Uma arquitetura de seção cross-country com uma única especificação principal no texto (`fect_ife_china_top_cov`), uma tabela principal, uma figura dinâmica principal e um parágrafo de limitações.",
  "- Um mapa do que deve ficar no main text e do que deve ir para o apêndice.",
  "- Um parágrafo de transição/caveat para demover o painel a scope probe.",
  "- Um parágrafo sobre heterogeneidade esperada, com Brasil como caso de alta saliência e pooled panel como média sobre casos mais fracos.",
  "- Captions ou notas sugeridas para tabela/figura principal, com unidade, bootstrap, janela, tratamento e estimando.",
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
  "# Relatório analítico: prompt de Goal 7 para o painel cross-country",
  "",
  paste0("Data: ", date_stamp),
  "",
  "Script gerador: `scripts/diagnostics/prepare_goal7_cross_country_scope_prompt.R`",
  "",
  "Este relatório transforma o Goal 7 do relatório ChatGPT Pro em um prompt operacional de `/goal`. Ele não revisa o paper, não edita `paper_v4.Rmd`, não altera `_targets.R`, `_targets/` ou `_targets.yaml`, e não executa `targets::tar_make()`.",
  "",
  "## Reprodução",
  "",
  "Comando usado para gerar os arquivos Markdown:",
  "",
  "```sh",
  "LC_ALL=en_US.UTF-8 Rscript --vanilla scripts/diagnostics/prepare_goal7_cross_country_scope_prompt.R",
  "```",
  "",
  "Comando usado para renderizar o PDF do relatório:",
  "",
  "```sh",
  "pandoc quality_reports/2026-05-18_goal7_cross_country_scope_prompt_report.md -o quality_reports/2026-05-18_goal7_cross_country_scope_prompt_report.pdf --pdf-engine=xelatex",
  "```",
  "",
  "## Fonte lida",
  "",
  "- HTML solicitado: `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.html`.",
  paste0("- Espelho Markdown usado para extração limpa do texto: `", rel_path(source_md), "`."),
  "- Trecho extraído salvo em: `quality_reports/goal7_source_excerpt_20260518.md`.",
  "",
  "Checagens de consistência:",
  "",
  "- O anchor do Goal 7 foi encontrado no HTML.",
  "- A frase-título do Goal 7 foi encontrada tanto no HTML quanto no espelho Markdown usado.",
  "- O trecho salvo em `goal7_source_excerpt_20260518.md` é verificado contra o bloco extraído durante a execução.",
  "",
  "Metadados das fontes:",
  "",
  source_metadata_lines,
  "",
  "## Leitura do Goal 7",
  "",
  "O Goal 7 pede que o painel cross-country deixe de competir com o caso brasileiro como se fosse uma segunda identificação principal. A seção deve funcionar como scope probe: uma especificação principal, uma tabela principal, uma figura dinâmica principal e um parágrafo curto de limitações. O restante deve ir para o apêndice, a menos que mude a conclusão central.",
  "",
  "## Diagnóstico inicial",
  "",
  "- O paper já contém material cross-country substantivo: `fect` IFE covariate-adjusted, `fect` IFE sem covariáveis, equivalence/placebo diagnostics, carryover/exit logic, PanelMatch, C&S absorvente, leave-one-out e painéis de trajetórias.",
  "- A lacuna central não é adicionar mais métodos, mas reduzir a seção a uma narrativa auditável: `fect_ife_china_top_cov` como especificação principal no texto; `fect_ife_china_top` sem covariáveis e os demais estimadores como diagnósticos ou apêndice.",
  "- O Goal 7 exige auditoria de consistência de todos os valores em Figure 10, Figure 19, Table 3, captions e texto. O relatório futuro deve comparar valores extraídos dos targets com valores escritos no Rmd, sem editar o paper nesta fase.",
  "- A linguagem causal deve ser reduzida para 'consistent with' ou 'suggestive of' generalização, salvo se os estimates limpos forem robustos across definitions e outcomes.",
  "",
  "## Identificação causal",
  "",
  "O contrato causal do painel cross-country deve ser reconstruído separadamente do desenho brasileiro. A unidade é país-ano; o tratamento é switching e vale 1 quando a China ocupa a posição de maior destino de exportação dentro do painel scope-conditioned; o tratamento retorna a 0 se a China perde essa posição. O outcome é a distância absoluta do ideal point à China. O estimando principal deve ser o efeito médio para observações tratadas nesse painel switching, não o mesmo estimando do C&S absorvente.",
  "",
  "Principais suposições e diagnósticos:",
  "",
  "| Suposição | Evidência/diagnóstico | Status sugerido | Implicação |",
  "| --- | --- | --- | --- |",
  "| Counterfactual IFE adequado | fect IFE, fator `r_cv`, placebo/equivalence diagnostics | Deve entrar de forma compacta | O leitor precisa ver por que o fect é a especificação principal |",
  "| Tratamento switching corretamente modelado | Entrada/saída de China top export destination | Central | Justifica fect e limita C&S a subconjunto absorvente |",
  "| C&S não estima o mesmo contraste | Absorbing-treatment subset e complete-case changes | Deve ser explicado | Evita falso conflito entre estimadores |",
  "| Inferência bootstrap apropriada | nboots, SE, p-valores, IC, número efetivo de tratados/switches | Precisa de auditoria | Valores inconsistentes corroem credibilidade |",
  "| Heterogeneidade substantiva | Brasil como caso de alta saliência; painel inclui casos mais fracos | Esperada | O pooled ATT deve ser menor/mais impreciso que o Brasil |",
  "| Evidência de mecanismo | Media salience só no Brasil | Limitada no painel | Painel deve ser scope probe, não teste mecanístico completo |",
  "",
  "Veredito de identificação para o prompt futuro: potencialmente crível como scope probe, condicionado à harmonização dos valores e a uma linguagem causal mais modesta.",
  "",
  "## Estimação",
  "",
  "A revisão deve escolher uma especificação principal no texto: `fect_ife_china_top_cov`, isto é, `fect` IFE para tratamento switching com `log_gdp_pc` e `free_press`. O `fect_ife_china_top` sem covariáveis deve ir para o apêndice como benchmark/robustness, não como coluna co-principal da tabela do corpo. PanelMatch, C&S, leave-one-out e raw panels também não devem ser apresentados como co-primários. C&S deve ser descrito como estimador de subconjunto absorvente; PanelMatch como diagnóstico de entry/exit; leave-one-out como sensibilidade de influência.",
  "",
  "Sugestões de revisão futura:",
  "",
  "- Main text: uma tabela curta com apenas `fect_ife_china_top_cov` como especificação principal.",
  "- Main text: uma figura dinâmica principal da especificação `fect_ife_china_top_cov`, se o objeto/plot estiver disponível de forma consistente; caso contrário, usar a figura `fect` IFE existente com legenda explícita sobre qual especificação ela representa.",
  "- Main text: um parágrafo de limitação que demova o painel a scope probe.",
  "- Apêndice: `fect_ife_china_top` sem covariáveis como benchmark, PanelMatch, C&S absorvente, leave-one-out, raw treated-country panels, equivalence-test plots completos e detalhes de bootstrap.",
  "",
  "## Inferência",
  "",
  "A inferência cross-country precisa ser auditada como sistema de valores, não apenas como estimativa isolada. O relatório futuro deve verificar p-valores, ICs, bootstrap draws, `r_cv`, placebo/equivalence p-values, carryover diagnostics e captions. O texto não deve transformar equivalence tests em prova de ausência de pre-trends nem bootstrap p-values em prova de identificação.",
  "",
  "Estimadores devem ser rotulados assim:",
  "",
  "| Estimador/diagnóstico | Papel recomendado | Interpretação correta |",
  "| --- | --- | --- |",
  "| `fect_ife_china_top_cov` | Principal no texto | Scope probe do tratamento China top export destination em painel com entradas e saídas, ajustado por log GDP per capita e press freedom |",
  "| `fect_ife_china_top` sem covariáveis | Apêndice/benchmark | Robustness simples; não deve ser co-principal no corpo |",
  "| `fect` FE / diagnostics | Diagnóstico | Checagem de placebo/equivalence/carryover, não estimador principal se IFE covariate-adjusted for preferido |",
  "| C&S absorvente | Apêndice/sensibilidade | Estima subconjunto persistent-treatment; não é o mesmo estimando do switching fect |",
  "| PanelMatch ATT/ART | Apêndice/diagnóstico | Evidência matching-based de entry/exit, geralmente mais ruidosa |",
  "| Leave-one-out | Apêndice | Influência de tratados, não evidência causal independente |",
  "| Raw treated-country panels | Apêndice | Descritivo; útil para heterogeneidade, não para inferência principal |",
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

write_utf8_lines(goal7_lines, excerpt_path)
write_utf8_lines(goal_prompt, prompt_path)
write_utf8_lines(report_lines, report_path)
write_utf8_lines(capture.output(sessionInfo()), session_info_path)

written_excerpt <- read_utf8_lines(excerpt_path)
if (!identical(goal7_lines, written_excerpt)) {
  stop("Saved Goal 7 excerpt does not match extracted Goal 7 block.")
}

message("Wrote: ", rel_path(excerpt_path))
message("Wrote: ", rel_path(prompt_path))
message("Wrote: ", rel_path(report_path))
message("Wrote: ", rel_path(session_info_path))
