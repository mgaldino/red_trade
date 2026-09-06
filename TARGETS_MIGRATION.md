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

**Atualizado em 2026-09-05**, contra `main` no commit `6750a9e`, o
`paper_v4.Rmd`, `_targets.R` e `scripts/run_rebuild_batch.sh`. Um script entra
nesta lista quando produz um número, tabela ou figura que o manuscrito atual lê
diretamente. A branch isolada `codex/targets-migration` contém uma integração
estática anterior, mas ela ainda não foi promovida para `main`; por isso os itens
abaixo permanecem pendentes nesta base.

| Prioridade | Script produtor | Saída ainda consumida diretamente pelo manuscrito | Destino da migração |
|---|---|---|---|
| P0 | `scripts/diagnostics/reestimate_corrected_ddd_RIO_20260905.R` | `data/processed/diagnostics/RIO_20260905_ddd/corrected_ddd_bundle.rds` | Criar targets para o bundle DDD corrigido e para o placebo por país; substituir os `readRDS()` do bloco de evidência por `tar_read()`. |
| P0 | `scripts/diagnostics/prepare_australia_appendix_bundle_patch.R` | `data/processed/diagnostics/RIO_20260905_australia/australia_appendix_tables_patch.rds` | Incorporar o ano de entrada atual ao produtor do apêndice e expor as tabelas corrigidas por target; preservar a proveniência histórica das fontes. |
| P0 | `scripts/diagnostics/rebuild_figure12_sample_RIO_20260905.R` | `images/RIO_20260905_table1_headlines_14.pdf` | Encapsular a seleção determinística como produtor e publicar o PDF vetorial como `format = "file"`; conservar o manifesto das 14 manchetes. |
| P1 | `scripts/diagnostics/audit_brazil_sdid_no_covariates.R` | CSVs em `data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/` usados pelos blocos de números e diagnósticos SDiD | Consolidar no bundle de diagnósticos SDiD já previsto no grafo, preservando seed, placebo distribution, ranks, pesos, balance, sensibilidades, timing e exposição dos doadores. |
| P1 | `scripts/diagnostics/prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R` | Figuras em `quality_reports/china_demand_shock_rank_threshold/` | Produzir as figuras de ajuste, pesos e pool latino-americano como file targets em diretório versionável; remover a dependência do caminho gitignored. |
| P1 | `scripts/diagnostics/audit_brazil_sdid_commodity_no_covariates.R` | `table_5_sdid_specification_results.csv` em `data/processed/diagnostics/brazil_sdid_commodity_no_covariates/` | Incorporar a exposição de commodities e a Tabela 5 ao grafo, incluindo os dois CSVs congelados a montante e seus checks. |
| P1 | `scripts/diagnostics/audit_ungadm_outcome_robustness.R` | Tabelas de estimação em `data/processed/diagnostics/ungadm_outcome_robustness/estimation/` | Criar o painel UNGA-DM harmonizado e o bundle SDiD/IFE como targets; manter os arquivos brutos e o codebook como file targets sem chamada de rede. |
| P1 | `scripts/diagnostics/audit_ungadm_postreview_diagnostics.R` | Tabelas de pós-revisão em `data/processed/diagnostics/ungadm_outcome_robustness/postreview/` | Mover ranks harmonizados, grade 2×2, bootstrap pareado e diagnósticos de divergência para targets/file targets dependentes do bundle UNGA-DM. |
| P1 | `scripts/diagnostics/preview_cross_country_dynamic_with_pooled_att.R` | `images/figure6_cross_country_dynamic_with_pooled_att.png` | Fazer o produtor da figura ser um target explícito dependente do modelo dinâmico e do ATT pooled; substituir o `include_graphics()` manual. |
| P1 | `scripts/diagnostics/plot_brazil_sdid_dose_response_panel.R` | `images/figure_brazil_sdid_dose_response_panel.pdf` | Expor a figura de dose–resposta como file target e declarar seus dados de entrada no grafo. |

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
