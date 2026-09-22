# Migração integral para o `targets`

**Status:** aprovado pelo autor em 2026-09-01 para execução em branch e worktree
isoladas. A promoção para `main` depende de todos os gates abaixo.

**Baseline analítico anterior a este documento:** `main` em
`6da13b58a120f3be7ffa9304af1a3285ccfe956a`.

**Plano histórico de referência:**
`quality_reports/plans/2026-08-25_migrate_diagnostics_to_targets.md`. Esse arquivo
permanece ignorado pelo Git e contém estados operacionais antigos; não deve ser usado
sozinho como descrição do estado atual.

## Objetivo

Todo número, tabela, figura e diagnóstico que entra em `paper_v4.Rmd` deve ser um target
ou arquivo produzido por target. O build de replicação não acessa a rede: começa em
insumos brutos congelados, documentados e validados por hash.

## Isolamento e preservação

- Preservar o checkout atual de `main`, seus scripts externos e seu store `_targets/`
  como referência até a promoção final.
- Executar a migração na branch `codex/targets-migration`, em worktree separado.
- O worktree de migração terá store `_targets/` próprio. É proibido apontá-lo para o
  store do checkout principal.
- Em 2026-09-01, o marcador `_targets/meta/process` do checkout principal registrava o
  PID 60838, criado em 2026-08-28. O PID já não existia. O marcador não foi removido e
  nenhum processo recebeu sinal.
- Antes da primeira mudança analítica, produzir um manifesto do baseline: arquivos,
  tamanhos, SHA-256, chaves, dimensões, especificações, seeds, replicações e outputs do
  manuscrito.

## Decisões sobre dados externos

### Coletores Python de evidência de status

- Manter no Git e no pacote de replicação os 139 arquivos brutos atuais, que somam
  21,75 MiB.
- Manter apenas o acesso HTTP fora do `targets`.
- Tratar arquivos brutos congelados como file targets e validar seus SHA-256.
- Separar codificações manuais em CSVs pequenos, versionados e autorais.
- Levar parsing, junções, contagens, resumos por país e tabelas do apêndice para o
  `targets`.
- Qualquer alteração nos coletores passa por `review-python` independente até PASS sem
  ressalva. Nenhum coletor será executado sem autorização específica.

### UNGA-DM

- Incluir no pacote de replicação o CSV e o codebook UNGA-DM, além do arquivo BSV usado
  no mapeamento. O conjunto atual soma aproximadamente 4 MiB.
- Declarar os insumos como file targets; não fazer download durante `tar_make()`.
- Construir uma única tabela harmonizada `iso3c` × ano, preservando linhas não
  mapeadas como diagnóstico.
- Fazer `left_join` do outcome UNGA-DM na grade mestre 1990–2023. Tratamento, risk set e
  grade não dependem da presença do outcome.
- Manter 2021–2023 e outras lacunas como `NA`, sem imputação.
- Construir a janela comum BSV–UNGA-DM como target analítico a jusante, com linhas
  idênticas, sem redefinir o painel mestre.

## Escopo da migração

| Bloco | Estado de origem | Destino |
|---|---|---|
| Painel mestre e tratamento cross-country | Correção `full_join` ainda externa ao pipeline de produção | União das fontes, grade país × ano 1990–2023, tratamento independente do outcome e testes de adjacência calendária |
| SDiD Brasil | Parte dos diagnósticos e figuras vem de scripts externos | Bundles e file targets dependentes dos alvos de estimação vigentes |
| Commodity e Tabela 5 | Tabelas derivadas por scripts de diagnóstico | Targets a montante e tabelas produzidas dentro do grafo |
| UNGA-DM | Dois scripts externos produzem estimação e pós-revisão | Outcome harmonizado, SDiD, IFE, bootstrap, ranks, tabelas e figuras como targets |
| Evidência de status | Coletores misturam HTTP, codificação e derivações | HTTP externo; bruto e codificação congelados; derivações e tabelas dentro do grafo |
| Manuscrito | Leituras diretas de CSVs diagnósticos e imagens manuais | `tar_read()` e caminhos retornados por file targets |

Nenhum bloco será promovido isoladamente. A implementação pode ser organizada por
blocos dentro da worktree, mas a integração em `main` é atômica.

## Inventário operacional de scripts ainda fora do grafo

**Atualizado em 2026-09-22**, contra `main` no commit `53cf696` mais as alterações
não commitadas do `paper_v4.Rmd`, e contra `codex/targets-migration` no commit
`882e959`. Um script entra nesta lista quando produz um número, tabela ou figura
que o manuscrito atual lê diretamente. O plano de execução que fecha esta lista
está em `quality_reports/plans/2026-09-22_migracao_targets_execucao.md`.

### Já coberto pela branch `codex/targets-migration` (implementado, nunca executado)

A branch acrescenta 154 targets (222 → 376), cinco arquivos
`scripts/functions_*_targets_migration.R` e seis testes estáticos em `migration/`.
No `paper_v4.Rmd` da branch não resta nenhuma leitura direta de arquivo. Cobre:
os 12 CSVs do SDiD sem covariáveis, as três figuras do SDiD, a Tabela 5 de
commodity, a figura de dose–resposta, a figura 6 do painel cross-country e as
nove tabelas UNGA-DM.

Duas ressalvas que a branch deixou explicitamente em aberto:

1. **Caminhos-sombra.** Todo target novo tem sufixo `_candidate` e escreve em
   `data/processed/targets_migration/` ou `images/targets_migration/`; os
   artefatos legados entram como arquivos de referência e há gates de igualdade
   entre candidato e referência. A troca pelos caminhos de produção é etapa
   separada, posterior aos gates.
2. **Família cross-country.** No manuscrito da branch, `china_top_m2_goods_status_current_*`
   foi substituída por `china_top_m2_goods_full_union_*`. A questão deixou de existir em
   2026-09-22: o autor removeu do paper a regressão em painel antiga e os três apêndices
   que dependiam dela. A evidência cross-country do corpo é o desenho do public cue. O
   bloco full-union, a figura 6 e o IFE antigo do apêndice UNGA-DM saem do escopo desta
   rodada; a comparação UNGA-DM será refeita para o desenho do public cue.

### Ainda fora do grafo (tudo criado na `main` depois de 2026-09-01)

| Prioridade | Script produtor | Saída consumida diretamente pelo manuscrito | Destino da migração |
|---|---|---|---|
| P0 | `scripts/diagnostics/estimate_selected_public_cue_sdid_fect.R` + `estimate_australia_sdid_2007_{point,placebo}.R` + `build_cross_country_public_cue_preview_assets.R` + `estimate_public_cue_pooled_ife_aus2007.R` (reestima os quatro modelos `fect` com a Austrália tratada desde 2007; a tabela do pool no paper vem dele, via `fect_results_aus2007.csv`) | Quatro ativos em `quality_reports/revisions/paper_v4/20260922_cross_country_public_cue_preview/assets/`: `table_public_cue_pooled_models.csv`, `table_selected_public_cue_sdid.csv`, `pre_cue_distance_summary.csv`, `figure_pre_cue_distance_focal_cases.png` | Painel de public cue, sete fits SDiD com SE placebo de 5.000 e quatro modelos `fect` com 1.000 bootstraps como targets; cue years e o uso do ano de 2007 na apresentação viram dado versionado, não literal no código; a figura vira file target em `images/`. |
| P0 | `scripts/diagnostics/reestimate_corrected_ddd_RIO_20260905.R` | `data/processed/diagnostics/RIO_20260905_ddd/corrected_ddd_bundle.rds` | A função `build_selective_unga_corrected_ddd` já existe em `functions.R` e é órfã do grafo: basta criar os targets do bundle e dos placebos por país e trocar o `readRDS()` por `tar_read()`. |
| P0 | `scripts/diagnostics/prepare_australia_appendix_bundle_patch.R` | `data/processed/diagnostics/RIO_20260905_australia/australia_appendix_tables_patch.rds` | Incorporar as correções ao produtor das tabelas do apêndice, em vez de remendar o target depois; preservar a proveniência histórica e o registro de mudanças. |
| P0 | `scripts/diagnostics/rebuild_figure12_sample_RIO_20260905.R` | `images/RIO_20260905_table1_headlines_14.pdf` | A tabela das 14 manchetes vira CSV versionado de codificação autoral; a figura vira file target dependente de `folha_classified_file`. |
| P0 | `scripts/diagnostics/build_public_cue_audit_table.R` (função em `scripts/functions_public_cue_audit.R`) | `data/processed/status_cue_salience/public_cue_audit_table.csv` (tabela da seção "Public Cue Search" do apêndice) | `tar_source("scripts/functions_public_cue_audit.R")`; file target para `australia_public_cue_media_2006_2009.csv` (os de `status_cue_country_codes.csv` e `status_cue_source_evidence.csv` já existem); target `public_cue_audit_table` com `china_top_m2_goods_panel` e `australia_code = "high"`; trocar o `read_csv()` do chunk `public-cue-audit-inputs` por `tar_read()`. Quando chegarem os arquivos `*_extension.csv` e `status_cue_source_evidence_chl_2007.csv` do Codex, declará-los como file targets e juntá-los na função. |
| P1 | `scripts/diagnostics/audit_brazil_sdid_predetermined_commodity_controls.R` | `table_10_validation_checks.csv` | Expor os três percentuais de exposição a commodities como colunas próprias, eliminando o regex que o manuscrito faz hoje sobre uma coluna de texto livre. |
| P1 | — (produtor já é target) | `dose_response_summary.csv` | O chunk novo `dose-response-numbers` lê por caminho um arquivo que o target `brazil_sdid_dose_placebo_summary_file` já produz; basta trocar por `tar_read()`. |

### Estado que muda números

- Os objetos `selective_china_alignment_*` do store da `main` são de 2026-08-25/26,
  anteriores à mudança da especificação do DDD em `scripts/functions.R`
  (termo `brazil_hr`, 2026-09-05). O manuscrito lê três deles. Um `tar_make()`
  vai reconstruí-los sob a especificação vigente.
- Sete insumos do manuscrito vivem em `quality_reports/`, que é gitignored: as
  três figuras do SDiD e os quatro ativos do public cue. O manuscrito, hoje, não
  compila a partir de um clone limpo.
- Um `tar_make()` em store limpo ainda sai à rede em cinco pontos: `wb_data`,
  `country_data`, `macro_data`, `ideology_data` (baixa `cow2iso.csv`) e
  `folha_df_p0..p4`. Os caches resgatados estão em `data/raw/network_caches/` e
  não estão ligados ao grafo.

### Não entram nesta lista de produtores analíticos

- `scripts/diagnostics/render_paper_v4_RIO_20260905.R` apenas encapsula a renderização e
  deve continuar como ferramenta de execução, não como target analítico.
- `scripts/run_rebuild_batch.sh`, `scripts/run_rebuild_targets.R` e os checks de
  cobertura/frescor orquestram ou verificam o pipeline; não produzem conteúdo do
  manuscrito. Os invariantes substantivos de donor pool e consistência do erro-padrão
  podem virar asserts no grafo, conforme o protocolo já registrado.
- Coletores externos, como `collect_ex_top1_salience_sources.py`, permanecem na
  fronteira de aquisição: os dados congelados devem ser declarados e validados como
  file targets, enquanto suas derivações que alimentam o paper entram no grafo.

Nenhum item acima deve ser marcado como concluído apenas por uma revisão estática ou
por um patch preparado. A conclusão exige build controlado em store limpo, comparação
com o gabarito, renderização/QA e revisão independente antes de promoção para `main`.

## Protocolo para alterar scripts

1. Documentar a mudança proposta e o contrato de equivalência antes de editar.
2. Implementar somente na worktree de migração.
3. Preservar seeds, especificações, amostras e contagens de replicações.
4. Manter implementador e revisor como papéis separados.
5. Submeter R a `review-r` e Python a `review-python` até PASS sem ressalva.
6. Rodar primeiro parse, testes unitários, schemas, chaves, unicidade, datas, missingness
   e invariantes substantivos.
7. Executar computação cara e `tar_make()` somente com autorização específica.
8. Comparar os outputs novos com o baseline antes de alterar o manuscrito.

Uma revisão PASS de uma versão anterior não cobre código modificado posteriormente.

## Comparação e adjudicação

Comparar, no mínimo:

- chaves, dimensões, países, anos, duplicatas e missingness;
- tratamento, entrada, saída, reentrada, ties e risk set;
- amostra de estimação, especificação, seeds e replicações;
- valores numéricos a `1e-12`, quando o contrato implicar igualdade;
- dados subjacentes, labels, captions e arquivos das figuras;
- números do corpo, tabelas, abstract e conclusão.

Cada divergência deve ser classificada como:

1. erro na implementação nova;
2. erro no pipeline antigo;
3. mudança substantiva deliberada;
4. diferença irrelevante de serialização, metadados ou ambiente.

O baseline antigo é comparador, não verdade por definição. Se o antigo estiver errado,
a correção deve seguir os dados e a regra substantiva, ser documentada e passar por nova
revisão; o erro não será reproduzido apenas para obter igualdade.

## Gates para promoção a `main`

- [ ] Baseline e insumos congelados e manifestados.
- [ ] Código R e Python com revisão independente PASS sem ressalva.
- [ ] Build completo em store limpo, sem acesso à rede.
- [ ] Todas as divergências adjudicadas e documentadas.
- [ ] Nenhuma leitura direta de output diagnóstico pelo manuscrito.
- [ ] Figuras e tabelas produzidas pelo grafo.
- [ ] PDF renderizado e inspecionado.
- [ ] Abstract e conclusão conferidos contra corpo e targets.
- [ ] Revisão final independente da migração completa.
- [ ] Autor autoriza explicitamente a promoção.

Após a promoção, preservar o worktree e os stores antigo e novo até o primeiro rebuild
bem-sucedido e a validação final em `main`.
