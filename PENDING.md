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

### Contrato inferencial da especificação principal — declarar no texto

**Status**: Parcialmente resolvida; resta a redação do autor
**Prioridade**: ALTA antes de nova circulação

A parte estimativa desta pendência (versão de 2026-05-25) foi resolvida em
julho: a especificação principal passou a ser o `predetermined_core` (commit
`2b6200d`), escolhido por argumento de identificação (remoção de covariáveis
pós-tratamento), com revisões causais independentes em
`quality_reports/china_demand_shock_rank_threshold/`. Números atuais da
especificação principal:

| Medida | Valor |
|---|---:|
| ATT | -0.272 |
| SE placebo (1.000 replicações) | 0.130 |
| p normal bilateral | 0.036 |
| IC 95% | [-0.527, -0.017] |
| Rank placebo direcional | 3/96 (p = 0.031) |
| Rank absoluto bilateral | 7/96 (p = 0.073) |

Os passos 1-5 da versão anterior desta pendência foram executados (specs
pré-especificadas na Tabela 5, sinal estável, revisão causal independente).
O que resta é a decisão de contrato aprovada em 2026-08-23 (parecer
`quality_reports/2026-08-23_causal_did_inference.md`, seções 3-4 e 7),
a implementar **pelo autor** no texto:

1. Declarar na seção de desenho/identificação que o teste primário é o rank
   placebo direcional (H1 é direcional e pré-declarada na teoria), com o p do
   SE placebo como complemento nativo e o rank bilateral como sensibilidade
   conservadora explicada (nota de resolução: piso 1/96; 4 dos 6 placebos mais
   extremos são positivos).
2. Aplicar o contrato uniformemente, inclusive no diagnóstico de direitos
   humanos (0.063 direcional citado; 0.053 donor-only como robustez).
3. Adicionar a figura da distribuição placebo com o Brasil marcado
   (`placebo_distribution.csv` já é lido no Rmd, linha ~305, e nunca usado).
4. Consolidar a inferência da especificação preferida num painel único
   (integrar à reforma da Table 2, abaixo).
5. Levar o resumo inferencial dos dois desenhos para a introdução (hoje ela
   não carrega inferência; o painel a p = 0.010 robusto aparece tarde).

Critério de resolução: contrato declarado antes dos resultados, aplicado
uniformemente, e apresentação consolidada. O rank bilateral (0.073) continua
reportado — explicado, não omitido.

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
1. **Antes de qualquer frase interpretativa no manuscrito sobre o painel**:
   rodar o 2×2 completo (BSV/UNGA-DM × r = 1/2) — a atenuação está confundida
   com a seleção de fatores (CV mudou r* = 2→1 com o outcome; IC do fect
   virtualmente empatado entre r = 1 e 2 no UNGA-DM; variante DM tem 3 leads
   pré-tratamento com IC excluindo zero). Complementos: bootstrap pareado da
   diferença de ATTs; inspeção de quais tratados divergem entre as séries.
   Aguarda aprovação do autor.
2. Linguagem para o paper: claim sustentável é "sensível à fonte de
   mensuração / impreciso demais para informar", NÃO "não sobrevive" (o IC do
   UNGA-DM [-0.120, 0.066] contém o próprio ponto BSV -0.095). Simetricamente,
   não promover o rank 2/96 do SDiD (Fiji está a 0.002 do Brasil); claim
   estável: "todas as convenções < 5%".
3. Housekeeping técnico antes do apêndice: harmonizar critério de exclusão
   China-top, exportar time weights/balance da variante DM, nota de seed
   (diferença ~2% é ruído MC; ranks determinísticos), commitar artefatos
   untracked (aguarda instrução do autor para commit).
4. Autor escreve o texto: tabela de apêndice BSV vs UNGA-DM + parágrafo de
   sensibilidade de mensuração; recalibrar a passagem (~linha 610 do Rmd) que
   usa o painel contra confounders Brasil-específicos, redistribuindo peso
   para os testes Brasil-específicos. BSV permanece outcome principal (regra
   pré-comprometida).

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

Nota 2026-08-23: integrar esta reforma com o item 4 do contrato inferencial
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
