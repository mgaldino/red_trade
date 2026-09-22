# AGENTS.md

Instruções operacionais para agentes trabalhando neste repositório.

## Regras do projeto

- Use R para análise estatística e mantenha computação em scripts separados.
- Para diagnósticos exploratórios, prefira `scripts/diagnostics/`.
- Não altere `_targets.R`, `_targets/`, `_targets.yaml` nem o pipeline `targets` sem instrução explícita.
- Não rode `targets::tar_make()` sem instrução explícita.
- Nunca encerre processos, envie sinais (`kill`/equivalentes), remova locks ou rode
  `targets::tar_unblock_process()` sem autorização explícita e específica do usuário
  para aquele PID/lock. Se `_targets` estiver bloqueado, audite e reporte o PID,
  comando, alvo aparente e horário; depois espere instrução.
- Preserve dados brutos e nunca sobrescreva arquivos de origem.
- Use `dplyr::select()` ao selecionar colunas em R.
- Outputs analíticos devem ser reprodutíveis e em UTF-8.
- Figuras e tabelas para relatórios devem ser numeradas e ter caption.
- Documente fonte e data de acesso.
- Quem implementa não revisa; quem revisa não edita.
- Para scripts R substantivos, use revisão crítica com a skill `review-r` quando solicitado.
- No manuscrito e em relatórios voltados ao autor/leitor, não use o jargão `spell` ou `treatment spell`. Prefira linguagem substantiva: `treatment entry/onset` para o ano em que a China se torna o maior destino de exportações, `treated periods` para os anos em que a China permanece nessa posição, e `cases where China displaced the United States/another partner` para heterogeneidade por incumbente deslocado. Nomes internos de variáveis podem manter `spell` quando já existirem em scripts ou CSVs, mas a prosa do paper deve evitar esse termo.

## Estado atual: `paper_v4` em 2026-05-25

Antes de inferir pendências a partir de relatórios antigos, cheque diretamente
`paper_v4.Rmd` e `paper_v4.pdf`. Em 2026-05-25, várias pendências documentadas
em `PENDING.md`, `README.md` e relatórios de 2026-05-20 foram resolvidas no
paper. O `paper_v4.extraction_cache.json` pode conter texto de PDFs antigos e
não deve ser tratado como evidência atual sem regeneração.

Estado confirmado no manuscrito ativo:

- A especificação cross-country principal é goods-only, status-current, com
  restricted risk set. Ela já foi migrada para `targets`.
- O paper usa alvos `china_top_m2_goods_status_current_*`, incluindo
  `china_top_m2_goods_status_current_model_results` e
  `plot_china_top_m2_goods_status_current_dynamic`.
- A seção cross-country já usa linguagem de escopo/padrão compatível, não
  claim causal forte.
- O alinhamento entre tratamento (`largest export destination`) e cue público
  (`largest/principal trading partner`) já foi tratado no texto e no apêndice.
- Os diagnósticos SDiD completos já foram integrados no corpo/apêndice.
- A evidência AGNU foi calibrada como convergência seletiva, sobretudo em
  direitos humanos, sem vender realinhamento geral amplo.

Pendências reais remanescentes:

- Table 2: a tabela compacta de diagnósticos SDiD no corpo do `paper_v4.pdf`
  ficou pequena demais e praticamente ilegível. Revisar antes de nova
  circulação, preferencialmente quebrando em tabelas menores ou convertendo
  parte do conteúdo em bullets no texto.
- C17 foi resolvido em 2026-09-05: `images/table1_headlines.png` agora mostra
  14 exemplos arquivados, sem a promessa de 20 headlines; o produtor legado
  também foi ajustado. Ver `quality_reports/revisions/paper_v4/20260905_RIO003_C17/`.
- Opcional: medir frequência normalizada de labels explícitos de rank
  (`largest`, `number one`, `principal partner`) na cobertura.
- Opcional: adicionar tabela país-a-país da codificação cross-country com
  entrada, incumbente, duração, saída, ties/missing e inclusão sob regras 1/3/5.
- Opcional: adicionar baseline formal de interdependência contínua no mesmo
  sample.

## Estado recente: public cue da Austrália, 2006–2009

Em 2026-09-22 foi concluída uma busca focal, separada do paper e do pipeline
`targets`, sobre a cronologia da pista pública australiana. A primeira pista
nacional positiva diretamente recuperada é da ABC em 04/05/2007, repetida em
01/09/2007: a China superou o Japão no comércio bilateral agregado. As fontes
recuperadas de 2006 ainda colocam a China em segundo lugar.

O artigo do Australian Financial Review de 09/11/2009 usa anos fiscais: o
“terceiro ano consecutivo” corresponde a 2006–07, 2007–08 e 2008–09, não a três
anos-calendário. O DFAT põe o Japão novamente em primeiro no ano-calendário de
2008, confirmando essa distinção. Nenhuma das oito fontes fornece evidência
estritamente alinhada a exportações de bens; portanto, a pista ampla de 2007
não autoriza recodificar automaticamente o tratamento goods-only de 2009.

Arquivos canônicos:

- `reports/status_cue_salience/australia_public_cue_2006_2009.md`
- `output/pdf/australia_public_cue_2006_2009.pdf`
- `data/processed/status_cue_salience/australia_public_cue_media_2006_2009.csv`
- `scripts/diagnostics/australia_public_cue_2006_2009_manifest.json`
- `scripts/diagnostics/australia_public_cue_2006_2009_search_log.json`
- `scripts/diagnostics/collect_australia_public_cue_2006_2009.py`
- `quality_reports/status_cue_salience/australia_public_cue_2006_2009_independent_review.md`

Não trate a ausência de matéria recuperada em AFR, Sydney Morning Herald ou
The Age em 2006–2007 como evidência de ausência de cobertura. O RBA e o DFAT
2007 foram verificados no navegador, mas a coleta automatizada dos artigos
parou quando os endpoints de `robots.txt` ficaram indisponíveis; consulte as
colunas de acesso e verificação do CSV antes de afirmar preservação de raw.

## Estado recente: votos Brasil-China na AGNU

Em 2026-05-17 foi produzida uma análise diagnóstica separada do pipeline `targets` sobre a dinâmica relacional dos votos Brasil-China na Assembleia Geral da ONU, 2005-2012.

Arquivos principais:

- `scripts/diagnostics/analyze_brazil_china_vote_alignment_by_issue_2005_2012.R`
- `scripts/diagnostics/plot_brazil_china_vote_similarity_by_issue_year_local_linear_2005_2012.R`
- `scripts/diagnostics/plot_brazil_china_vote_similarity_by_issue_year_facets_local_linear_2005_2012.R`
- `scripts/diagnostics/plot_brazil_china_vote_similarity_score_jitter_2005_2012.R`
- `data/processed/unvotes/brazil_china_vote_alignment_by_resolution_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_alignment_mechanisms_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_similarity_by_issue_year_plot_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_similarity_score_by_resolution_2005_2012.csv`
- `quality_reports/un_vote_cases/nota_alinhamento_relacional_brasil_china_2005_2012.md`

Takeaway substantivo: a aproximação Brasil-China pós-2009 aparece de forma real, mas estreita e temática. O mecanismo mais convincente é mudança direta do voto brasileiro em direção à China em direitos humanos. Há menos evidência de realinhamento relacional amplo pró-China, e alguns casos fora de direitos humanos parecem falsos positivos porque a China se moveu para posições brasileiras.

Status em 2026-05-25: o `paper_v4.Rmd` já incorporou a interpretação calibrada
como convergência seletiva, sobretudo em direitos humanos e em votos em que
China e Estados Unidos divergem. Não trate "incorporar achados AGNU" como
pendência ampla sem antes checar o texto atual.

## Estado resolvido: recodificação cross-country China #1

Em 2026-05-20 foi produzida uma nota metodológica separada do pipeline `targets`
sobre a especificação cross-country do tratamento China como principal destino
de exportações. Em 2026-05-25, essa pendência foi checada contra o paper atual
e está resolvida no manuscrito ativo.

Arquivos principais:

- `quality_reports/cross_country_sample/nota_recodificacao_status_current_min5_2026-05-20.md`
- `quality_reports/cross_country_sample/nota_recodificacao_status_current_min5_2026-05-20.html`
- `scripts/diagnostics/reestimate_china_top_min5_status_current_strict.R`
- `scripts/diagnostics/diagnose_china_top_min5_status_current_pretrends.R`
- `scripts/diagnostics/reestimate_china_top_status_current_duration_robustness.R`

Takeaway metodológico incorporado: a especificação principal é goods-only
status-current com restricted risk set. `D_it = 1` apenas nos anos em que China
é de fato rank-1 em exportações de bens e o período qualifica pela janela mínima
de durabilidade. Anos pós-saída de países tratados não viram controles limpos.
A robustez clean single-entry acompanha a especificação principal; a versão
switching allowed entra como robustez, não como principal.

Alvos atuais em `targets`:

- `china_top_m2_goods_status_current_panel_bundle`
- `china_top_m2_goods_status_current_model_results`
- `fect_ife_china_top_m2_goods_status_current_min5_risk_set`
- `plot_china_top_m2_goods_status_current_dynamic`

Instrução operacional: não reabrir a decisão como se o paper ainda estivesse em
regra absorvente/off-target. Se for revisar o cross-country, comece pelo
`paper_v4.Rmd` atual e pelos alvos `china_top_m2_goods_status_current_*`.
