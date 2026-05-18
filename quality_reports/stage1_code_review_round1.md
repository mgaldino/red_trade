# Stage 1: Code Review -- Round 1

**Reviewer**: Codex, Agente Reviewer do Estágio 1
**Date**: 2026-05-17
**Scope**: `_targets.R`, `scripts/functions.R`, and computational chunks of `paper_v4.Rmd` that consume `tar_read()`, `readRDS()`, `knitr::include_graphics()`, and fect/C&S/panel results.
**Role constraint**: revisão apenas; nenhuma correção implementada.

## Q&A inicial

**Q: Rodei `targets::tar_make()`?**
A: Não.

**Q: Editei código, pipeline ou manuscrito?**
A: Não. A única escrita foi este relatório.

**Q: O código R tem erro de sintaxe evidente?**
A: Não. `parse("_targets.R")` e `parse("scripts/functions.R")` passaram.

## Resultado

**REPROVADO [40]**

Score inicial: 100. Dedução total: -60.

## Blocking Issues

1. C1. O estimando cross-country descrito no manuscrito não corresponde ao painel construído no código.
2. C2. `paper_v4.Rmd` ainda depende de `tar_read(table_treated)`, alvo ausente no `_targets.R` atual.
3. M1. A robustez C&S com covariáveis tem violações de overlap/convergência registradas e é reportada sem qualificação suficiente.

## Problemas Críticos

### C1. Mismatch de estimando/amostra no painel cross-country (-30)

**Arquivos/linhas**: `scripts/functions.R:2052-2059`, `_targets.R:144-149`, `paper_v4.Rmd:560-562`, `paper_v4.Rmd:809-811`.

O manuscrito afirma que a especificação cross-country testa se o efeito ocorre "whenever China becomes the number-one export destination" e que o tratamento principal independe de qual parceiro foi deslocado. Porém `build_china_top_partner_panel()` restringe a amostra a:

```r
treated_usa <- classified_events %>%
  dplyr::filter(displaced == "USA") %>%
  dplyr::pull(iso3c)

did_countries <- unique(c(treated_usa, usa_top_countries))
```

Ou seja, o painel é condicionado a países onde a China deslocou os EUA e/ou onde os EUA já foram o principal destino de exportação. Isso não é o universo de países em que a China se torna o principal destino de exportação. A frase "regardless of which partner it displaces" é, no mínimo, incompleta: vale apenas dentro de uma amostra filtrada por histórico dos EUA como parceiro principal.

**Impacto**: problema de domínio/especificação. A inferência substantiva sobre generalização cross-country está mais ampla do que a amostra efetivamente estimada. Esta é uma questão bloqueante antes de circular o paper.

### C2. Dependência de alvo stale não definido no pipeline atual (-20)

**Arquivos/linhas**: `paper_v4.Rmd:1107`, `_targets.R:1-243`.

O chunk `table-treated-appendix` chama:

```r
treated_tbl <- tar_read(table_treated)
```

Mas `table_treated` não aparece no `_targets.R` atual. O objeto existe no store local (`_targets/objects/table_treated`) e nos metadados antigos, mas não é reproduzível a partir da definição corrente do pipeline.

**Impacto**: em um clone limpo, ou depois de limpar/reconstruir o store, o apêndice quebra ou fica dependente de artefato obsoleto. Isso viola a exigência de reprodutibilidade do manuscrito e é bloqueante para o Estágio 1.

## Problemas Major

### M1. Robustez C&S com covariáveis tem warning substantivo de overlap/convergência (-10)

**Arquivos/linhas**: `_targets.R:188-197`, `paper_v4.Rmd:661-725`, `_targets/meta/meta:334`.

O alvo `did_china_top_absorbing_cov` registra warnings do tipo:

- `glm.fit: algorithm did not converge`
- `glm.fit: fitted probabilities numerically 0 or 1 occurred`
- `overlap condition violated`

Esses warnings são diretamente relevantes para a validade do C&S covariate-adjusted, porque indicam problemas de propensity/overlap em grupos pequenos. O manuscrito reporta a coluna covariate-adjusted como robustez na Tabela `table-fect-specs`, mas não sinaliza que a estimativa depende de uma especificação com violações de overlap.

**Impacto**: a coluna C&S com covariáveis não deve ser interpretada como robustez limpa sem diagnóstico ou qualificação explícita.

### M2. A especificação C&S baseline e a C&S com covariáveis não estimam exatamente o mesmo subconjunto absorvente (-5)

**Arquivos/linhas**: `_targets.R:179-197`, `scripts/functions.R:1052-1158`, `paper_v4.Rmd:658`.

A especificação baseline C&S usa `china_top_panel` até 2022; a versão com covariáveis usa `china_top_panel_cov` e complete cases, cujo resumo atual cobre 1990-2020. Os objetos salvos mostram:

- `did_china_top_absorbing_summary`: 11 tratados, painel 1990-2022.
- `did_china_top_absorbing_cov_summary`: 12 tratados, painel 1990-2020.

Isso sugere que a versão covariate-adjusted muda não só covariáveis, mas também o horizonte e possivelmente a classificação "absorbing" de unidades que perdem a posição após 2020.

**Impacto**: a comparação entre colunas (3) e (4) pode misturar ajuste por covariáveis com mudança de estimando/amostra. O texto precisa tratar isso como mudança de amostra, não apenas como covariate adjustment.

### M3. P-valores de equivalência estão parcialmente hardcoded no caption (-3)

**Arquivos/linhas**: `paper_v4.Rmd:623-628`, `paper_v4.Rmd:1003-1004`.

O texto principal lê `placebo_equiv_p` e `carryover_equiv_p` dinamicamente, mas o caption do apêndice fixa valores como `TOST p = 0.040` e `TOST p = 0.484`. Se os targets forem rerodados, esses valores podem divergir dos objetos atuais.

**Impacto**: risco de inconsistência silenciosa entre resultado computado e resultado citado.

## Problemas Minor

### m1. Alvos legados de `switching_panel` continuam ambíguos (-2)

**Arquivos/linhas**: `_targets.R:202-212`, `scripts/functions.R:1680-1715`.

`build_switching_panel()` define `china_top` como China rankeada acima dos EUA, não como China sendo top partner geral. Embora o manuscrito atual use os alvos `china_top_*`, os alvos legados `fect_ife`, `panelmatch_att`, etc. permanecem no pipeline com nomes facilmente confundíveis.

**Impacto**: baixo para o manuscrito atual, mas aumenta o risco de uso acidental de estimandos diferentes.

## Pontos Positivos

- `scripts/functions.R` e `_targets.R` passam em parse estático.
- A correção recente para a especificação principal `china_top_*` está bem separada dos alvos legados.
- As funções recentes usam `dplyr::select()` nas seleções de colunas revisadas.
- `set.seed(42)` está presente nas rotinas bootstrap/aleatórias principais de fect, PanelMatch, wild bootstrap e Fisher.
- O manuscrito distingue melhor fect switching de C&S absorbing do que versões anteriores.
- Os chunks principais leem resultados de targets, mantendo a computação central fora do Rmd.

## Verificações Realizadas

- Leitura estática de `_targets.R`, `scripts/functions.R` e trechos computacionais de `paper_v4.Rmd`.
- Busca por `tar_read()`, `readRDS()`, `knitr::include_graphics()`, `fect`, `PanelMatch`, `did::att_gt`, C&S e alvos de painel.
- `parse("_targets.R")`: OK.
- `parse("scripts/functions.R")`: OK.
- Não executei `targets::tar_make()`.
- A leitura de `targets::tar_meta()` falhou por restrição de sandbox ao carregar `processx`; usei `_targets/meta/meta` como evidência estática de warnings.

## Recomendação

Não aprovar o Estágio 1 ainda. A prioridade é alinhar explicitamente a definição da amostra cross-country ao texto do manuscrito e remover a dependência de `table_treated` stale. Depois disso, a robustez C&S com covariáveis precisa ser reclassificada, qualificada ou substituída por uma especificação sem violações severas de overlap.
