# Pendências do Projeto

Atualizado em: 2026-08-23, após parecer de inferência causal
(`quality_reports/2026-08-23_causal_did_inference.md`) sobre o `paper_v4.Rmd`
atual e o `paper_v4.pdf` renderizado em 2026-07-15.

## Fonte de verdade operacional

Para o manuscrito ativo, use nesta ordem:

1. `paper_v4.Rmd`
2. `paper_v4.pdf`
3. `_targets.R` e `scripts/functions.R` para verificar se resultados vêm do
   pipeline

Não use `PENDING.md`, `README.md`, relatórios antigos de revisão ou
`paper_v4.extraction_cache.json` como fonte de verdade sem conferir o Rmd/PDF
atuais. O cache de extração pode conter texto de versões anteriores.

## TAREFA PRIORITÁRIA Nº 1 — migrar para o `targets` TUDO que entra no paper

**Status**: ABERTA, é a próxima tarefa de código do projeto (decisão do autor, 2026-08-26)
**Prioridade**: MÁXIMA — antes de qualquer outra coisa de código
**Rastreamento**: issue #6 (`gh issue view 6`); plano em
`quality_reports/plans/2026-08-25_migrate_diagnostics_to_targets.md`

Regra do autor, sem exceção além das duas nomeadas: **nada que entra no paper pode ficar
fora do `targets`, exceto as chamadas externas ao Banco Mundial e o scraping da Folha**
(esses ficam como dados já coletados, cacheados e declarados, para não onerar a pesquisa —
e a submissão explica isso). Motivo: o pacote de replicação vai afirmar que a análise usa
`targets`; script fora do grafo produzindo número do manuscrito derruba o claim.

**ATUALIZAÇÃO 2026-08-26 — a auditoria adversarial ampliou o problema**
(`quality_reports/2026-08-26_adversarial_audit_targets_coverage.md`, 6 bloqueantes):
a lista de exceções está incompleta por um fator de três, e **duas das fontes de rede
omitidas rodam DENTRO do grafo**, a cada build numa máquina limpa —
`functions.R:280` baixa cow2iso do GitHub e `:292` chama `gmd()`, que baixa de
globalmacrodata.com; `:100` chama `wb_countries()` (segundo endpoint do BM). Os três
alimentam `synth_data`/`final_df` (72 descendentes cada) e portanto a Tabela 1 e as colunas
(2)-(4) da Tabela 3. Ou seja: **estar dentro do grafo não basta — o critério é nenhuma folha
tocar a rede**. Além disso, os snapshots que produziram os números existem só na máquina do
autor (`macro_data`/`country_data` de 2025-07-05, `ideology_data` de 2025-07-07;
`_targets/objects/` = 515 MB, não versionado). Ver a EMENDA no plano.

Hoje **206 targets** existem, e o manuscrito lê 26 deles — mas também lê **13 CSVs**
escritos por scripts de diagnóstico que o `targets` não rastreia
(`scripts/diagnostics/audit_*.R`, `prepare_paper_v4_*.R`). `main_summary`,
`rank_inference`, `unit_weights` etc. NÃO são targets (verificado contra o manifesto). Um
`tar_make()` puro num clone limpo não os produz.

Escopo: **migrar tudo de uma vez** (SDiD + figuras + commodity/table5 + UNGA-DM). Não há
migração parcial "para ver funcionando": se não funciona dentro do `targets`, há algo
errado no código, não no `targets`.

Custo medido (rodada de 2026-08-25/26, não é estimativa): o diagnóstico do SDiD leva **16
segundos** e as figuras **8 segundos** — os fits caros (SEs a 20.000 replicações, família
`fect_ife_*`) já são targets e NÃO serão reconstruídos. O grosso do recálculo é a família
commodity, que reaproveita checkpoints validados por fingerprint.

Critério de aceitação: saídas idênticas às da rodada de 2026-08-26 (gabarito numérico,
tolerância 1e-12) e `tar_make()` + render suficientes para reproduzir o paper.

## Estado atual do `paper_v4`

### Resolvido: cross-country China #1 status-current

**Status**: Resolvido no manuscrito ativo e migrado para `targets`
**Prioridade**: FECHADO, salvo nova decisão substantiva

A antiga pendência de migrar a recodificação cross-country para `targets` está
superada. O `paper_v4.Rmd` agora usa a especificação goods-only
**status-current** com **restricted risk set**:

- tratamento = 1 apenas em país-anos em que China é o maior destino de
  exportações de bens;
- o período China-top precisa durar pelo menos cinco anos observados;
- anos pós-saída e episódios curtos são removidos do risk set principal;
- há robustez `clean_single_spell` e `switching_allowed`;
- serviços são excluídos antes do cálculo dos ranks.

Alvos relevantes já existem em `_targets.R`:

- `china_top_m2_goods_status_current_panel_bundle`
- `china_top_m2_goods_status_current_model_results`
- `fect_ife_china_top_m2_goods_status_current_min5_risk_set`
- `plot_china_top_m2_goods_status_current_dynamic`

Funções relevantes já existem em `scripts/functions.R`:

- `build_status_current_period_data()`
- `make_status_current_panel()`
- `make_status_current_panel_bundle()`
- `fit_status_current_fect_models()`
- `plot_status_current_dynamic()`

Critério de resolução já atendido: o paper não depende mais de tabelas
cross-country off-target como especificação principal e não usa tratamento
absorvente como estimando principal.

### Resolvido: diagnósticos SDiD do Brasil

**Status**: Resolvido no manuscrito ativo
**Prioridade**: FECHADO

O paper já incorporou:

- resumo compacto de diagnósticos SDiD no corpo do texto;
- pesos completos de doadores;
- pesos de tempo;
- RMSPE e balance;
- placebo ranks;
- sensibilidade a doadores;
- sensibilidade de janela;
- exposição dos doadores de alto peso à expansão chinesa.

Esses itens aparecem no corpo e no apêndice de `paper_v4.Rmd`.

### Resolvido: alinhamento entre tratamento e cue público

**Status**: Resolvido no manuscrito ativo
**Prioridade**: FECHADO

O paper agora distingue explicitamente:

- tratamento empírico: China como maior destino de exportações;
- linguagem pública: `largest trading partner`, `principal trading partner`,
  `main commercial partner`, `top export market`;
- evidência pública: usada como mecanismo, não como redefinição do tratamento.

O caso Austrália/AFR também já foi incorporado como caveat de métrica: o item
AFR documenta cue público amplo de parceiro comercial agregado, mas não conta
como evidência de uptake do tratamento estrito de destino de exportações.

### Resolvido: linguagem causal cross-country

**Status**: Resolvido no manuscrito ativo
**Prioridade**: FECHADO

A seção cross-country foi rebaixada para evidência de escopo/padrão compatível.
O paper usa linguagem como `compatible directional pattern`, `associated with`
e `scope evidence`, e não trata o painel como substituto do teste de mecanismo
brasileiro.

### Resolvido: AGNU/issue-area overclaim

**Status**: Resolvido no manuscrito ativo para a rodada atual
**Prioridade**: FECHADO, salvo nova exigência de parecerista

O paper já calibra a interpretação AGNU:

- a convergência é seletiva, não uniforme;
- a evidência mais informativa está em direitos humanos, especialmente quando
  China e EUA divergem;
- os diagnósticos voto-a-voto são interpretados como conteúdo substantivo e
  benchmark inferencial, não como prova isolada de causalidade;
- o texto evita vender uma aproximação geral ampla com a China.

## Pendências reais remanescentes

### RESOLVIDO (2026-08-26) — rebuild de reprodutibilidade da spec sem covariáveis

**Status**: CONCLUÍDO. 12/12 lotes OK entre 2026-08-25 16:35 e 2026-08-26 10:59 (~9h25),
sob o screen de doadores corrigido (bens). Invariante de consistência do SE passou nas
quatro fontes; `output/paper_v4.pdf` regenerado em 2026-08-26. Números finais: ATT −0,2728,
SE 0,1306 (20k, seed 20260520), p 0,037, rank direcional 3/96 (p 0,031), bilateral 7/96.
O texto abaixo é o registro histórico do que era a pendência.

#### (histórico)

**Status**: BLOQUEANTE antes de qualquer circulação ou submissão
**Prioridade**: MÁXIMA
**Decisão do autor (2026-08-23)**: "tudo precisa ser reproduzível".

> **ESCOPO AMPLIADO EM 2026-08-25 — LEIA ANTES DE RODAR.** O rebuild agora
> carrega uma segunda correção, mais grave que a das covariáveis: o screen de
> elegibilidade do donor pool do SDiD ranqueava parceiros por comércio
> **total**, enquanto o paper define tratamento por exportações de **bens**.
> Malta (China #1 em bens, 2011–2012) estava no donor pool com 3,0% de peso —
> uma unidade tratada dentro do contrafactual, violando a suposição do modelo.
> Singapura era o erro espelhado, excluída sem motivo. Corrigido: sai Malta,
> entra Singapura, pool segue com 96 unidades, e **os resultados não se movem**
> (ATT −0,2720 → −0,2728; SE 0,1302 → 0,1306; ranks idênticos, 3/96 e 7/96).
>
> **O comando mudou.** Rodar em lotes de ~1h, não em bloco:
> `bash scripts/run_rebuild_batch.sh list | status | next | <lote>`.
> Custo medido por `tar_outdated()`: 17 targets reconstroem, 18 seguem válidos
> (toda a família cross-country já usava bens e fica intacta), ≈7h30 no total.
> Plano, causa-raiz e runbook completo:
> `quality_reports/plans/2026-08-25_goods_only_donor_screen.md`.

#### O que aconteceu e por que isto existe

Em 2026-08-23 a especificação principal do Brazil SDiD passou a **não usar
covariáveis**. Antes, ela supria arrays fixos por unidade (médias 2004-2008 de
export shares e renda per capita, distância geográfica, valores institucionais
de 2008). Sendo invariantes no tempo, são colineares com os efeitos fixos de
unidade do SDiD: coeficientes numericamente zero, e um parágrafo defensivo no
texto só para explicar o artefato. A motivação é de higiene metodológica —
não de inferência. `scripts/functions.R::simple_fit_no_time_varying_covariates()`
já não passa X.

Efeito nos números: ATT -0.2723 -> -0.2720 (quarta casa) e ranks placebo
**idênticos** (3/96 direcional p=0.031; 7/96 bilateral p=0.073). O SE observado
mudou de 0.130 para 0.137 numa primeira medição, mas isso era **ruído de seed**
com 1.000 replicações, não efeito das covariáveis — ver a seção "Descoberta que
motivou elevar as replicações", abaixo. Com 5.000 replicações o valor estável é
SE ~0.131 e p ~0.038, essencialmente o mesmo das duas especificações. **Não
escrever no paper que o SE anterior era otimista.**

#### O que está inconsistente AGORA (e por isso é bloqueante)

1. **Store de targets desatualizado**: `synth_fit_no_time_varying_covariates`
   e `se_synth_no_time_varying_covariates` no `_targets/` ainda contêm a
   versão COM covariáveis. A função mudou, mas o pipeline não pôde ser
   re-rodado nesta máquina (ver item 3). O `paper_v4.Rmd` foi apontado para os
   CSVs de diagnóstico para não exibir números velhos, mas isso é contorno,
   não reprodutibilidade.
2. **Tabela 5 inconsistente** (chunk `china-demand-sdid-diagnostics`): lê
   `data/processed/diagnostics/brazil_sdid_predetermined_commodity_controls/table_4_sdid_specification_results.csv`,
   cuja linha `predetermined_core` é a versão COM covariáveis e com 1.000
   replicações. O texto e a Tabela 3 mostram outro SE e outro p para a MESMA
   especificação preferida. O ATT arredondado coincide (-0.272), o SE e o p
   não. O rebuild resolve os dois lados de uma vez, ao passar tudo a 5.000
   replicações e à spec sem covariáveis. Além disso, a linha "Add pre-2009 primary share" daquela tabela é
   redundante por construção (nível fixo = colinear; ATT idêntico ao
   preferido) e some naturalmente na reforma.
3. **Ambiente incompleto**: `renv::status()` acusa `duckdb` gravado no
   lockfile mas NÃO instalado. `duckdb` é dependência real
   (`scripts/functions.R:3926`, agregação ITPD-E goods) e está em
   `tar_option_set(packages=...)`, então **qualquer** target falha ao ser
   construído. Outros pacotes também estão fora do lockfile (easypackages,
   ggsci, network, plm, priceR, stargazer, WDI).

#### Roteiro de execução

**Preferir a execução em lotes** (2026-08-25), que faz os mesmos estágios na
mesma ordem em sessões de no máximo ~1,5h, com estado em
`output/rebuild_batches/STATE.tsv`:

```bash
bash scripts/run_rebuild_batch.sh next
```

O bloco único abaixo continua válido para quem puder deixar rodando a noite
inteira, mas a estimativa de ~9h é anterior à correção do donor pool e hoje
superestima (a família cross-country não reconstrói mais):

```bash
bash scripts/run_reproducibility_rebuild.sh
```

Roda os cinco estágios em ordem, para no primeiro erro, e grava logs
separados em `output/rebuild_<timestamp>/`. Estimativa: **~9 h** (medição
direta de 2026-08-24: cada réplica placebo custa 0.026 s sem covariáveis e
1.644 s com 13 covariáveis em 12 cores — as colunas de comparação da Tabela 3
e a linha current-baseline da Tabela 5 dominam o tempo). Seguro deixar rodando
sozinho, e **retomável**: o `targets` cacheia o que completou, então se a
máquina dormir no meio, re-rodar o mesmo comando continua de onde parou.
Replicações: 20.000 na coluna preferida (sem covariáveis, ~4 min; SE fixado a
±0.001), 5.000 nas comparações (ampliá-las custaria ~9 h cada, sem ganho — são
colunas de estrelas, não a inferência do paper). As notas da Tabela 3, da
Tabela 5 e da figura principal já dizem as contagens corretas. Estágios: (1) `renv::restore()` — instala o `duckdb`, única
dependência real que faltava; (2) `tar_make()` restrito aos 30 targets que o
manuscrito e os scripts de diagnóstico consomem (um `tar_make()` completo
tentaria reconstruir targets exploratórios que já falhavam antes e abortaria
a madrugada); (3) diagnósticos SDiD sem covariáveis, que agora **reusam o SE
do target** para o CSV não divergir da Tabela 3; (4) família
commodity/China-demand da Tabela 5 sob a spec sem covariáveis
(`scripts/diagnostics/audit_brazil_sdid_commodity_no_covariates.R`, já
escrito e testado); (5) render.

Dry-run já confirmado: no subconjunto do SDiD, serão reconstruídos
`synth_fit_no_time_varying_covariates`, os quatro SEs placebo e
`brazil_sdid_spec_table`. `synth_data` e `synth_fit` seguem válidos.

#### Descoberta que motivou elevar as replicações (2026-08-23)

Com 1.000 permutações, o **próprio SE placebo é ruidoso**: cinco blocos
independentes de 1.000 sobre a spec preferida deram 0.1262, 0.1296, 0.1305,
0.1316 e 0.1355 — movendo o p entre **0.031 e 0.045 sem nada mudar nos
dados**. Com 5.000 o SE converge para **0.1309**, que é exatamente o desvio
padrão da distribuição placebo-in-space exaustiva (0.1310, idêntico com e sem
covariáveis). Consequências:

- `se_sdid()` foi reescrita: 5.000 replicações, permutações sorteadas uma vez
  a partir do seed e avaliadas em paralelo — determinística e independente do
  número de cores (verificado). Em tempo de parede fica **mais rápida** que as
  1.000 sequenciais que substitui.
- As dez chamadas em `_targets.R` passaram a 5.000.
- **Correção de interpretação**: a diferença 0.130 -> 0.137 observada ao
  remover as covariáveis era ruído de seed, NÃO compressão de variância pelas
  covariáveis. Não escrever no paper que o SE anterior era otimista. A
  justificativa da mudança continua sendo colinearidade/inércia e a remoção do
  parágrafo defensivo; a inferência é praticamente neutra (p ~ 0.038 estável).
- Isso vale para TODOS os SEs do paper, não só o preferido.

#### REBUILD: estágios 01-07 CONCLUÍDOS (2026-08-25). Falta só o render (08).

**Estágio 07 (consistência) PASSOU** — as quatro fontes reportam o mesmo SE
para a especificação preferida, até a 8ª casa:

```
target=0.13015889  main_summary=0.13015889  tabela5=0.13015889  ungadm_bsv=0.13015889
```

Era exatamente essa a inconsistência que tornava o rebuild bloqueante. **A
pendência de reprodutibilidade está resolvida**; falta apenas re-renderizar o
PDF (`bash scripts/render_paper_v4.sh`, minutos), adiado a pedido do autor.

**Números finais, todos do pipeline:**

Tabela 3 / texto (spec preferida, sem covariáveis, 20.000 reps, seed 20260520):
ATT -0.2720, SE 0.1302, p 0.037, IC [-0.527, -0.017], ranks 3/96 (p = 0.031) e
7/96 (p = 0.073).

Tabela 5 (commodity, 5.000 reps, seed comum entre linhas):

| Especificação | ATT | SE | p |
|---|---:|---:|---:|
| Current covariates (comparação) | -0.2639 | 0.1432 | 0.065 |
| **Preferida: sem covariáveis** | **-0.2720** | **0.1302** | **0.037** |
| Primary share x 2008-09 | -0.2839 | 0.1280 | 0.027 |
| Agriculture/mining x 2008-09 | -0.2839 | 0.1275 | 0.026 |
| Price exposure x 2008-09 | -0.2762 | 0.1301 | 0.034 |
| Prior China share x 2008-09 | -0.2843 | 0.1296 | 0.028 |

Todas as robustezes de commodity ficaram entre p = 0.026 e 0.034 (antes a
família ia até 0.051), num intervalo estreito de ATT (-0.272 a -0.284).

**Check UNGA-DM, agora com as duas colunas na MESMA spec, mesmas replicações e
mesmo seed** (diferem só no outcome, como o pré-compromisso exigia):

| Fonte | ATT | SE | p | rank dir. | rank bilat. |
|---|---:|---:|---:|---:|---:|
| BSV (principal) | -0.2720 | 0.1302 | 0.037 | 0.031 | 0.073 |
| UNGA-DM | **-0.3352** | 0.1234 | **0.007** | **0.021** | **0.031** |

Conclusão do check preservada sob a spec nova: sob o dado corrigido o caso
brasileiro fica mais forte e **todas** as convenções caem abaixo de 5%.

**Painel e 2×2 (estágio 06)** — o padrão da revisão independente se confirma:

| ATT (p) | r = 1 | r = 2 |
|---|---|---|
| BSV | -0.036 (0.336) | **-0.095 (0.016)** ← CV |
| UNGA-DM | **-0.027 (0.573)** ← CV | -0.065 (0.238) |

Bootstrap pareado (B = 1.000): a diferença entre os ATTs **não** é
distinguível de zero — p = 0.134 no contraste procedimento-selecionado e
p = 0.356 com fatores comuns. Linguagem para o paper permanece a aprovada:
painel "sensível à fonte de mensuração", nunca "não sobrevive"; e a
significância do painel requer o segundo fator latente mesmo no BSV.

Os números UNGA-DM do relatório de 2026-08-23 (ATT -0.335, p 0.009) ficam
confirmados sob a especificação vigente: **não é mais preciso esperar
reestimação para incorporar o apêndice ao texto.**

#### ESTADO DO REBUILD (parcial, 2026-08-25 03:07)

Rodou 3h10 e completou **6 dos 11 estágios**; interrompido a pedido do autor no
início do estágio 04. Retomar com o MESMO comando — os estágios 02 e 03 estão
gravados e serão pulados:

```bash
bash scripts/run_reproducibility_rebuild.sh
```

| Estágio | Status |
|---|---|
| 01, 01b, 01c, 01d | OK (renv restore instalou o duckdb; validação do algoritmo placebo passou) |
| 02 targets | **OK, 3h03** — quatro SEs reconstruídos |
| 03 diagnósticos SDiD | **OK** |
| 04 commodity (Tabela 5) | interrompido no início — faltam ~5h (4 specs com covariáveis × ~1h15) |
| 05-06 UNGA-DM | pendente (~1-2h) |
| 07 consistência, 08 render | pendente (minutos) |

**Falta: ~6-8 horas.** Custo por SE medido em produção: **1h15 com covariáveis**
(`se_synth`, `se_synth_baseline`) contra **4 minutos sem** — confirma que o
gargalo era o array de covariáveis, não as replicações.

**Verificação já feita (2026-08-25)**: o SE do pipeline bate EXATAMENTE com a
referência standalone medida um dia antes, por caminho independente:

| Fonte | ATT | SE | p |
|---|---|---|---|
| target `se_synth_no_time_varying_covariates` (20.000 reps, seed 20260520) | -0.272007 | **0.130159** | 0.0366 |
| CSV do estágio 03 (o que o Rmd lê) | -0.272007 | **0.130159** | 0.0366 |
| referência standalone de 2026-08-24 | — | **0.130159** | 0.0366 |

Diferença target vs CSV vs referência: **0.00e+00**. O determinismo da
`se_sdid()` está confirmado em produção, não só em teste. Ranks (que não
dependem de sorteio): 3/96 direcional (p = 0.031), 7/96 bilateral (p = 0.073).

**Números canônicos do paper, portanto**: ATT -0.272, SE 0.130, p 0.037,
IC 95% [-0.527, -0.017], rank direcional 3/96 (p = 0.031), bilateral 7/96
(p = 0.073).

**Três erros de operação já corrigidos e commitados** (não voltam): seleção de
targets avaliada no processo callr (`bquote`, commit 4fceba0); lock obsoleto do
store bloqueando o relançamento (guarda no orquestrador, commit f1c9410);
`RhpcBLASctl` fora do lockfile. Lição operacional: **não usar `timeout` em
volta de `tar_make`** (o filho callr sobrevive ao pai e mantém o lock) e **não
editar o orquestrador enquanto ele roda** (o bash lê o arquivo incrementalmente).

#### Valores de referência para conferir o estágio 02 (medidos em 2026-08-24)

`compute_sdid_se_5000.R` com as MESMAS contagens e seed do pipeline
(20.000/5.000, seed 20260520) produziu, antes de uma queda de energia
interromper a 4ª coluna (log: `output/se5000.log`; determinismo da se_sdid
verificado independentemente pelo revisor, então o tar_make DEVE reproduzir):

| Coluna Tabela 3 | ATT | SE | p |
|---|---|---|---|
| (1) Preferida, sem covariáveis (20k) | -0.2720 | 0.1302 | 0.0366 |
| (2) Covariáveis atuais (5k) | -0.2639 | 0.1432 | 0.0652 |
| (3) Sem instituições (5k) | -0.2645 | 0.1428 | 0.0640 |
| (4) América Latina (5k) | (interrompida; sai do próprio rebuild) | | |

Se o estágio 02 der números diferentes destes, algo mudou além do esperado —
investigar antes de seguir. A referência standalone NÃO precisa ser re-rodada.

#### Comportamento esperado ANTES do rebuild (não é bug)

- Knit do `paper_v4.Rmd` agora FALHA de propósito: a Tabela 5 lê o diretório
  novo, que só contém saída smoke (marcada `smoke_test = TRUE`), e o chunk tem
  guarda `stopifnot(!any(smoke_test))`. Mensagem críptica de `stopifnot` =
  rode o rebuild.
- Os scripts UNGA-DM param no gate com a mensagem "Run the reproducibility
  rebuild first" (verificado): o target ainda contém o fit da spec antiga.
- Tudo isso se resolve com `bash scripts/run_reproducibility_rebuild.sh`.

#### Iteração de revisão de código R (2026-08-24)

O autor pediu `review-r` com iteração até "pass sem ressalva". Rodada 1:
REPROVADO (C, 68/100) — algoritmos verificados corretos (se_sdid reproduz o
pacote com diferença zero; sinal `estimate - main` sem resíduos), mas 9
críticos de integração. Relatório completo:
`quality_reports/2026-08-23_review_r_sdid_scripts.md`. TODOS os críticos e
importantes foram implementados em seguida:

- **Consolidação (S10)**: nova biblioteca única
  `scripts/diagnostics/sdid_placebo_helpers.R` (fit, SE placebo com
  checkpoint/fingerprint cobrindo dados+código+versão do synthdid, ranks com
  denominador protegido, mclapply validado contra filho morto); os quatro
  scripts de diagnóstico foram reescritos sobre ela. Elimina C5/C6/C8/M5/M6.
- **C1 (três seeds)**: seed única 20260520 para TODOS os SEs; linha preferida
  sempre espelha o pipeline (reusa o target ou computa com a MESMA contagem e
  seed do target). Valor canônico medido: **SE 0.1302, p 0.0366**
  (20.000 replicações; ATT -0.2720; IC [-0.527, -0.017]).
- **C2**: `paper_v4.Rmd` religado ao novo diretório/arquivo da Tabela 5
  (`brazil_sdid_commodity_no_covariates/table_5_...`), com guardas
  `stopifnot` (specs presentes, 1 linha, anti-smoke).
- **C3**: `make_brazil_sdid_spec_table()` sem checkmarks na coluna preferida
  e nota parametrizada (replicações/seed, com fallback aos atributos do
  target).
- **C4**: os dois scripts UNGA-DM reescritos sob a spec SEM covariáveis; o
  gate agora compara like-with-like e instrui rodar o rebuild se o target
  estiver obsoleto. **Os artefatos UNGA-DM commitados (ATT -0.335 etc.) são
  da spec antiga e serão regenerados nos estágios 05-06 do rebuild** — não
  incorporar ao texto antes disso.
- **C7**: proveniência (seed/replicações) gravada a partir da fonte real do
  SE; `se_sdid()` agora devolve escalar com atributos.
- **C9**: `render_paper_v4.sh` ativa o renv explicitamente sob `--vanilla` e
  grava `output/paper_v4_session_info.txt`.
- **M17**: `goal9_summarise_sdid_estimate()` delega à `se_sdid()`.
- **M19 + reforço**: orquestrador com 11 estágios — renv restore + registro
  de ambiente, validação do algoritmo placebo, `tar_make` com lista derivada
  programaticamente do Rmd (`scripts/rebuild_targets.R`), diagnósticos,
  Tabela 5, UNGA-DM (estimação + pós-revisão), **estágio de consistência que
  falha se texto/Tabela 3/Tabela 5/UNGA-DM divergirem no SE**, render;
  `caffeinate -i` para a madrugada.
- Demais importantes (M1-M16, M18) e sugestões baratas (S1-S9) aplicados;
  M3: claim de "distorção da variância" removido de todos os comentários
  (a distribuição placebo exaustiva é idêntica com e sem covariáveis; a
  justificativa é identificação + custo computacional ~60x).

Rodada 2: REPROVADO por um único bloqueador NOVO (vírgula de `_targets.R:160`
engolida por comentário — o rebuild teria morrido no estágio 02), com os 28
achados da rodada 1 dados como RESOLVIDOS e verificados por execução (quatro
implementações do SE placebo idênticas a 0.175362758160; seed única confirmada
em três caminhos; SD exaustivo conferido nos dados). Rodada 3, após corrigir a
vírgula, adicionar o estágio 01d (parse + manifest, que pega esse tipo de erro
em segundos) e fechar dois one-liners: **PASS SEM RESSALVA**. Relatórios:
`quality_reports/2026-08-23_review_r_sdid_scripts.md` (rodada 1) e
`quality_reports/2026-08-24_review_r_sdid_scripts_round2.md` (rodadas 2-3,
com o veredito final). Registro do revisor: o PASS atesta o código; os números
do paper só ficam consistentes após o rebuild rodar com o estágio 07 verde.

#### Decisões do autor (2026-08-23, fim da sessão)

1. **SEs a 5.000 replicações: aprovado.** Os quatro SEs da Tabela 3 foram
   computados fora do `targets` com a nova `se_sdid()` e o mesmo seed default
   do pipeline (20260520), em
   `data/processed/diagnostics/sdid_placebo_se_5000_reference.csv`
   (script: `scripts/diagnostics/compute_sdid_se_5000.R`). Como a função é
   determinística dado o seed, o `tar_make()` da madrugada deve reproduzir
   esses valores exatamente — servem de conferência do estágio 2.
2. **Proofread: adiado** para depois do rebuild, para revisar o texto final
   uma vez só. O agente revisor foi interrompido antes de gravar o relatório;
   quando for retomado, o produto vai para
   `quality_reports/2026-08-23_proofread_paper_v4.md`, separando erros
   objetivos (a aplicar) de sugestões de estilo (decisão do autor).
3. **Frase da nota de dados: mantida.** O texto promete um apêndice UNGA-DM;
   o autor vai escrever esse apêndice (Bloco F do rascunho
   `quality_reports/ungadm_outcome_robustness/2026-08-23_draft_paper_text_ungadm.md`).
   Enquanto o apêndice não entrar, a promessa fica pendente — conferir antes
   de circular.

#### Verificação após o rebuild

- [ ] `tar_read(synth_fit_no_time_varying_covariates)` bate com
      `data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/main_summary.csv`
      no ATT (tolerância 1e-8). O SE pode diferir ~2% por ruído Monte Carlo de
      seed (o target usa seed 20260520; o diagnóstico usa 20260823) — decidir
      qual fonte o paper cita e usar SÓ ela.
- [ ] Tabela 3 e Tabela 5 mostram o mesmo SE e o mesmo p para a especificação
      preferida.
- [ ] Texto, Tabela 3, Tabela 5 e apêndice citam os mesmos números.
- [ ] Re-render sem erros e sem citações quebradas.
- [ ] Considerar reapontar o `paper_v4.Rmd` da coluna (1) da Tabela 3 de volta
      para os targets, encerrando o contorno.


### Convenção de teste da especificação principal — JÁ ESTÁ NO TEXTO

**Status**: RESOLVIDA em `paper_v4.Rmd`; não reabrir
**Prioridade**: FECHADA, salvo exigência de parecerista

A parte estimativa desta pendência (versão de 2026-05-25) foi resolvida em
julho: a especificação principal passou a ser o `predetermined_core` (commit
`2b6200d`), escolhido por argumento de identificação (remoção de covariáveis
pós-tratamento), com revisões causais independentes em
`quality_reports/china_demand_shock_rank_threshold/`. Números atuais da
especificação principal (rebuild de 2026-08-26; fonte:
`paper_v4_brazil_sdid_no_covariates/main_summary.csv`):

| Medida | Valor |
|---|---:|
| ATT | -0.273 |
| SE placebo (20.000 replicações, seed 20260520) | 0.131 |
| p normal bilateral | 0.037 |
| IC 95% | [-0.529, -0.017] |
| Rank placebo direcional | 3/96 (p = 0.031) |
| Rank absoluto bilateral | 7/96 (p = 0.073) |

O que o parecer de 2026-08-23 pedia
(`quality_reports/2026-08-23_causal_did_inference.md`, seções 3-4 e 7) já está
escrito, na formulação do autor, na seção "Identification strategy" (~linhas
285-289 do Rmd): o teste é o rank placebo direcional, justificado pela hipótese
direcional; o SE da aproximação normal entra como complemento; o rank bilateral
é reportado como avaliação conservadora, com o piso de resolução de ~1%
(1/96 = 0.0104) explicado; e a mesma convenção vale para todo diagnóstico
baseado em placebo, inclusive o benchmark de direitos humanos.

Também já feitos: a figura da distribuição placebo com o Brasil marcado (chunk
`plot-placebo-distribution`) e o p do rank direcional inline na introdução.

Resta um único item deste bloco, e ele vive na reforma da Table 2 abaixo:
consolidar ATT, SE, IC, p normal e os ranks num painel único de inferência. O
rank bilateral (0.073) continua reportado — explicado, não omitido.

### Robustez de mensuração com UNGA-DM (Fjelstul, Hug & Kilby 2026)

**Status**: EXECUTADO em 2026-08-23; revisão independente em andamento;
incorporação ao manuscrito pendente (autor)
**Prioridade**: ALTA antes de nova circulação (pré-comprometida)

Check executado conforme o plano
(`quality_reports/plans/2026-08-23_ungadm_robustness_check.md`); relatório
final em `quality_reports/ungadm_outcome_robustness/2026-08-23_final_report.md`.
Resultado (a reportar no paper **seja qual for**, por pré-compromisso):

- **Brazil SDiD fica MAIS forte** sob UNGA-DM: ATT -0.335 (SE placebo 0.129),
  p normal 0.009, rank direcional 2/96 (p = 0.021), rank bilateral 3/96
  (p = 0.031) — todas as convenções abaixo de 5%, inclusive o bilateral que
  era 0.073 no BSV. Painel idêntico (gate de reprodução 1e-8), mesmo fit pré.
- **Painel IFE atenua a ~zero** sob UNGA-DM em janela comum com linhas
  idênticas (≤2020): BSV -0.095 (p = 0.016, r* = 2) vs UNGA-DM -0.027
  (p = 0.573, r* = 1). O truncamento de janela NÃO explica (BSV comum ≈ BSV
  cheio); a troca de medida explica. A evidência de escopo cross-country é
  sensível à fonte de mensuração do outcome.

Revisão causal independente CONCLUÍDA (2026-08-23): **endossado com
ressalvas** — parecer completo em
`quality_reports/ungadm_outcome_robustness/2026-08-23_independent_causal_review.md`.
Aderência ao pré-compromisso julgada integral; mapeamento país-sessão
verificado no bruto; um defeito técnico imaterial encontrado (critério de
exclusão China-top divergente entre colunas de rank de julho e agosto — ranks
idênticos nas 4 combinações testadas pelo revisor).

Pendências derivadas (ordem do revisor):
1. **2×2 e bootstrap pareado — EXECUTADOS em 2026-08-23** (aprovados pelo
   autor; relatório completo:
   `quality_reports/ungadm_outcome_robustness/2026-08-23_postreview_diagnostics_report.md`;
   outputs: `data/processed/diagnostics/ungadm_outcome_robustness/postreview/`).
   Resultados: com fatores comuns (r = 2), BSV -0.095 (p = 0.016) vs UNGA-DM
   -0.065 (p = 0.238) — a medida explica ~1/3 da atenuação; derrubar r para 1
   anula até o BSV (-0.036, p = 0.336), logo a maior parte do "-0.027" era
   artefato da seleção de fatores. Bootstrap pareado (B = 1.000, 0 falhas):
   a diferença entre os ATTs NÃO é distinguível (p = 0.13
   procedimento-selecionado; 0.36 com fatores comuns). Divergência por país:
   queda bruta dentro dos tratados quase igual nas duas séries (-0.220 vs
   -0.199); correlações médias iguais em tratados e controles (~0.75).
   Subproduto importante: a significância do painel requer o segundo fator
   latente mesmo no BSV.
2. Linguagem para o paper — agora CONFIRMADA pelos testes: claim sustentável
   é "sensível à fonte de mensuração / impreciso demais para informar", NÃO
   "não sobrevive" (IC do UNGA-DM contém o ponto BSV; diferença de ATTs não
   passa no bootstrap pareado). Simetricamente, não promover o rank 2/96 do
   SDiD (Fiji está a 0.002 do Brasil); claim estável: "todas as convenções
   < 5%".
3. Housekeeping técnico antes do apêndice — DECIDIDO em 2026-08-23 (autor
   aprovou): a linha "exclude China-top donor assignments" do paper usa o
   **critério de julho/janela** — excluir doadores com status China-top
   observado dentro de 1997-2015 (= MLT; denominador 95) — porque o rótulo
   promete purga de contaminação, e contaminação é exposição dentro da janela
   de análise. Alternativas descartadas: (i) critério ever-treated/5 anos
   (GAB/KWT, tratados 2017-18, fora da janela) — mira seleção em tratamento
   futuro, ameaça distinta; sub-inclusivo para contaminação (perde MLT) e
   descarta placebos limpos; mantido apenas como linha de auditoria; (ii)
   união dos dois critérios (denominador 93) — redundante, ranks idênticos
   nas 4 combinações testadas pelo revisor; se a motivação not-yet-treated
   surgir (parecerista), apresentar como linha própria com rótulo próprio.
   Harmonização, time weights/balance da variante DM e nota de seed:
   executados em `scripts/diagnostics/audit_ungadm_postreview_diagnostics.R`
   (outputs em `data/processed/diagnostics/ungadm_outcome_robustness/postreview/`).
   Commit do check: `74bc686`; diagnósticos pós-revisão entram em commit
   próprio ao concluir.
4. **Parcialmente incorporado ao `paper_v4.Rmd` em 2026-08-23** (a pedido e
   na formulação do autor): resumo inferencial na introdução (Bloco B, com
   valores inline vindos dos targets), nota de dados UNGA-DM (Bloco C) e os
   dois parágrafos sobre a convenção de teste em "Identification strategy"
   (Bloco A); entrada BibTeX `fjelstul_etal2026` adicionada ao
   `synth-trade-china.bib`. Correção factual aplicada e sinalizada no Bloco A:
   piso de resolução do rank é ~1% (1/96 = 0.0104), não 0.1%.
   FALTA: figura da distribuição placebo (Bloco G, chunk a implementar),
   apêndice de robustez de mensuração (Bloco F), e os Blocos D e E, que o
   autor decidiu escrever/reformular pessoalmente. Rascunho de referência:
   `quality_reports/ungadm_outcome_robustness/2026-08-23_draft_paper_text_ungadm.md`.
   O PDF ainda não foi recompilado após estas inserções.
   Contexto original do item: tabela de apêndice BSV vs UNGA-DM + parágrafo de
   sensibilidade de mensuração; recalibrar a passagem (~linha 627 do Rmd) que
   usa o painel contra confounders Brasil-específicos, redistribuindo peso
   para os testes Brasil-específicos. BSV permanece outcome principal (regra
   pré-comprometida). **Rascunho de apoio disponível** (pedido pelo autor em
   2026-08-23; a escrita final é do autor):
   `quality_reports/ungadm_outcome_robustness/2026-08-23_draft_paper_text_ungadm.md`
   — blocos A-H (convenção de teste, introdução, nota de dados, parágrafo
   de sensibilidade, recalibragem ~610, apêndice com tabelas, legenda da
   figura placebo, BibTeX de Fjelstul et al.), cada um com nota explicativa e
   checklist de incorporação. Inclui também a convenção de teste da
   pendência anterior.

Pacote menor concluído: teste F de pré-tendência do m2 extraído e equivalence
plot do `fect` gerado
(`data/processed/diagnostics/ungadm_outcome_robustness/estimation/m2_fect_equiv_plot.png`)
— candidato a apêndice.

### Table 2: legibilidade

**Status**: Pendente
**Prioridade**: ALTA antes de nova circulação

A Table 2 do `paper_v4.pdf` ficou pequena demais e praticamente impossível de
ler. A tabela resume os diagnósticos compactos do SDiD do Brasil; o conteúdo é
útil, mas a apresentação atual precisa ser revista.

Ações possíveis:

1. quebrar a tabela em duas tabelas menores;
2. mover parte do conteúdo para o apêndice e deixar no corpo uma versão mais
   enxuta;
3. substituir por bullets numerados no texto e manter a tabela completa no
   apêndice;
4. ajustar layout/fonte/colunas apenas se isso resolver a legibilidade sem
   comprimir demais.

Critério de resolução: Table 2 legível no PDF renderizado em tamanho normal,
sem depender de zoom excessivo.

Nota 2026-08-23: integrar esta reforma com o painel único de inferência pedido
acima — um painel único de inferência da especificação preferida (ATT, SE, IC,
p normal, ranks direcional/bilateral/filtrados) pode absorver a linha "Placebo
inference" da Table 2 e reduzir o conteúdo restante.

### C17: imagem de headlines promete 20 itens

**Status**: Pendente deliberado
**Prioridade**: BAIXA

O caption do `paper_v4.Rmd` já foi suavizado, mas a imagem
`images/table1_headlines.png` ainda contém o subtítulo "Random sample of 20
headlines with ChatGPT-assigned topic". O PDF atual ainda extrai essa frase da
imagem. O item continua visual/transparência, não causal.

Ação futura, apenas se o autor pedir ou antes de circulação final:

1. regenerar a imagem para mostrar efetivamente os 20 headlines completos; ou
2. alterar o subtítulo dentro da imagem para não prometer 20 itens.

### Rank-label frequency explícita

**Status**: Opcional
**Prioridade**: MÉDIA se o objetivo for blindar mecanismo

O paper já tem evidência de saliência por categoria de headline e evidência
oficial de uptake do cue. Ainda não há uma contagem normalizada de expressões
explícitas como `largest`, `number one`, `principal partner` sobre o total da
cobertura. Isso responderia ao M04 literal do coarse review, mas não bloqueia a
versão atual.

### Tabela completa de portabilidade da codificação cross-country

**Status**: Opcional
**Prioridade**: MÉDIA

O apêndice já tem audit de setor e audit agregado de amostra. Ainda poderia ser
adicionada uma tabela país-a-país com entrada, incumbente deslocado, duração,
saída, ties/missing e inclusão sob regras de 1/3/5 anos. Isso é útil para
parecerista metodológico, mas não é uma falha estrutural da versão atual.

### Baseline formal de continuous interdependence

**Status**: Opcional
**Prioridade**: MÉDIA/BAIXA

O paper responde à alternativa de interdependência contínua por covariáveis,
timing tests, lower-threshold placebo e diagnósticos de demanda chinesa. Ainda
não há uma tabela dedicada estilo Flores-Macias/Kreps ou Urdinez no mesmo
sample adicionando depois a entrada rank-one. Isso é uma blindagem adicional,
não uma pendência operacional.

### Materiais derivados

**Status**: Condicional
**Prioridade**: BAIXA até uso externo

Antes de usar `paper_v4_anonymous.Rmd`, slides, pacote de submissão ou materiais
externos, sincronizar com o `paper_v4.Rmd` atual. A versão ativa do manuscrito
é `paper_v4.Rmd`, não os derivados.

## Itens removidos da lista de pendências ativas

- Decidir estimando cross-country principal: resolvido como goods-only
  status-current restricted risk set.
- Migrar status-current para `targets`: resolvido.
- Refazer cross-country com resultados vindos de `targets`: resolvido no paper
  atual.
- Corrigir M05 export-destination vs public cue: resolvido no texto e no
  apêndice.
- Inserir diagnósticos SDiD completos: resolvido.
- Suavizar linguagem causal do painel cross-country: resolvido.
- Tratar BaTIS BPM5/BPM6 como pendência do paper atual: removido; a
  especificação principal é goods-only e exclui serviços antes do ranking.
