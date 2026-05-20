# Revisão de código: `reestimate_cross_country_incumbent_salience_500_bootstrap.R`

## Problemas críticos

**Crítico: SEs e p-values dos grouped ATT estavam incorretos**

O script tratava `fit$est.group.att` como matriz de draws bootstrap e calculava `apply(..., safe_sd)`. No `fect` 2.1.0, `est.group.att` é uma matriz-resumo com colunas como `ATT`, `S.E.`, `CI.lower`, `CI.upper`, `p.value`. Portanto, o script calculava o desvio-padrão sobre `ATT`, `S.E.`, limites de CI e p-value, produzindo SEs, CIs e p-values inválidos para todos os resultados por grupo. O ATT de grupo provavelmente estava correto; a inferência por grupo não.

**Crítico: o script não validava unicidade dos CSVs antes dos joins por `iso3c`**

Os joins assumiam uma linha por país em cada CSV diagnóstico. Se `incumbent` ou `vreeland` tivesse duplicatas por `iso3c`, o painel seria multiplicado e o `fect` poderia falhar com observações não únicas por `country_id`/`year`, ou rodar sobre contagens distorcidas. Antes de executar 500 bootstraps, precisa haver validação explícita de duplicatas.

## Melhorias importantes

**Importante: saída sobrescreve resultados anteriores e nomes ficam errados se `--nboots` mudar**

Os arquivos eram fixos como `model_results_500_bootstrap_*.csv`, mesmo quando o argumento `--nboots` mudava. Isso prejudica smoke tests e reprodutibilidade.

**Importante: `--nboots` não era validado**

`parse_nboots()` podia retornar `NA`, zero, negativo ou não inteiro. Melhor falhar cedo.

**Importante: execução com 500 bootstraps é operacionalmente arriscada sem teste curto**

São 5 modelos `fect` IFE, cada um com `CV = TRUE`, `r = c(0, 3)`, `se = TRUE`, `nboots = 500`, `parallel = FALSE`. Isso é seguro no sentido de não saturar CPU, mas pode demorar. Foi recomendada execução smoke com poucos bootstraps antes da execução completa.

## Checagens solicitadas

- `targets::tar_make()`: não há chamada; apenas `targets::tar_read()`.
- `_targets` / pipeline: não há edição explícita; o script só lê target existente e CSVs.
- `dplyr::select()`: os usos relevantes estão namespaced corretamente.
- Extração de grupos `fect`: nomes de grupos parecem plausíveis, mas a inferência por grupo precisava copiar a matriz-resumo corretamente.
- Timing do tratamento: usa `first_treat > 0` e grupos pré-tratamento por país; conceitualmente alinhado ao desenho absorvente, condicionado aos CSVs terem o mesmo `t0`.
- Paths: relativos ao repo e em `reports/`.

## Testes sugeridos antes da execução completa

1. Rodar com `--nboots=5 --report-dir=reports/tmp_incumbent_salience_smoke` depois de corrigir a extração de `est.group.att`.
2. Validar `n_distinct(iso3c) == nrow()` nos dois CSVs diagnósticos.
3. Validar unicidade final de `country_id, year` após os joins.
4. Comparar manualmente `fit$est.group.att` com o CSV de grupos para garantir que ATT, SE, CI e p-value foram copiados corretamente.

## Resposta implementada

O script foi revisado antes de execução: a extração de grupos agora copia `ATT`, `S.E.`, intervalos e `p.value` diretamente de `fit$est.group.att`; os CSVs diagnósticos e o painel final têm validações de unicidade; `--nboots` falha cedo se inválido; e os nomes de saída passam a usar o número efetivo de bootstraps.
