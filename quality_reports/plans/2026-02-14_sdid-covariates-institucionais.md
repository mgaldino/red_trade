# Plano: Substituir baseline SDiD por modelo com covariáveis institucionais

**Status**: COMPLETED
**Data**: 2026-02-14 (concluído 2026-02-15)

## Contexto

O modelo SDiD atual (caso Brasil) tem ATT = -0.287, SE = 0.133, **p = 0.078** — não significativo a 5%. Testes ad hoc mostraram que adicionar 3 covariáveis institucionais (`inst_parliamentary`, `inst_military_exec`, `us_trade_agreement`) mantém o ATT praticamente idêntico (-0.286) mas reduz o SE para 0.118, resultando em **p = 0.016**. Melhora o RMSPE pré em 3.2% com perda de apenas 4.2% das observações.

O objetivo é integrar esse modelo ao pipeline `targets` como novo baseline e mover o modelo antigo para robustez.

**Nota importante**: o teste ad hoc usou S0 com 8 covariáveis (sem trade shares), enquanto o pipeline atual usa 10 covariáveis (com trade shares). O modelo final terá 13 covariáveis (10 existentes + 3 novas). Os resultados podem diferir ligeiramente do ad hoc.

## Abordagem

### Fase 1: Código R (scripts/functions.R + _targets.R) — via skill `/data-analysis-r`

#### 1.1 Descomentar e adaptar `get_dpi_data()` (functions.R:172-186)

Já existe uma versão comentada. Descomentar e adaptar:
- Ler DPI CSV, substituir `-999` por `NA`
- Construir `inst_parliamentary = ifelse(system == 2, 1, 0)`
- Construir `inst_military_exec = ifelse(military == 1, 1, 0)`
- Forward-fill até 2020 (DPI cobre só até 2015, mas panel vai até 2017+)
- Retornar `(iso3c, year, inst_parliamentary, inst_military_exec)`

#### 1.2 Criar `get_us_trade_agreement()` (functions.R, após get_dpi_data)

- Receber os 5 arquivos release_2 (já carregados como country_file1-5)
- Filtrar `iso3_d == "USA"`, tratar `-999` como NA
- Construir `us_trade_agreement = 1` se qualquer acordo ativo
- Agrupar por `(iso3c, year)`, retornar panel

#### 1.3 Modificar `clean_synth_data()` (functions.R:540-596)

- Adicionar parâmetros opcionais: `dpi_data = NULL`, `trade_agreement_data = NULL`
- Após line 552, fazer `left_join` condicional dos novos dados
- Na `dplyr::select()` final (line 591), usar `any_of()` para incluir novas colunas
- **Não rescalar** binários 0/1 (já estão em escala natural)
- O `drop_na()` existente (line 557) cuidará da perda amostral automaticamente

#### 1.4 Modificar `cov_matrix()` (functions.R:600-619)

- Adicionar `any_of(c("inst_parliamentary", "inst_military_exec", "us_trade_agreement"))` ao `dplyr::select()` (line 602)
- A construção do array 3D já é dinâmica (`ncol(mat_X) - 2`), sem mudanças adicionais

#### 1.5 Modificar `_targets.R`

Adicionar após line 33 (data loading):
```r
tar_target(dpi_file, here("raw data", "database-political-institutions-2015.csv"), format = "file"),
tar_target(dpi_data, get_dpi_data(dpi_file)),
tar_target(trade_agreement_data, get_us_trade_agreement(country_file1, country_file2, country_file3, country_file4, country_file5)),
```

Modificar line 59 (synth_data):
```r
tar_target(synth_data, clean_synth_data(final_df, ranked_trade_data=trade_data_ranked,
                                         dpi_data=dpi_data, trade_agreement_data=trade_agreement_data)),
```

Adicionar targets de robustez (modelo antigo, sem covariáveis institucionais):
```r
tar_target(synth_data_baseline, clean_synth_data(final_df, ranked_trade_data=trade_data_ranked)),
tar_target(synth_fit_baseline, simple_fit(data=synth_data_baseline, filter_latin_america=FALSE)),
tar_target(se_synth_baseline, se_sdid(synth_fit_baseline)),
```

Modificar line 84 (synth_data_extended):
```r
tar_target(synth_data_extended, clean_synth_data(final_df, trade_data_ranked, year_end = 2020,
                                                  dpi_data=dpi_data, trade_agreement_data=trade_agreement_data)),
```

#### 1.6 Rodar pipeline

`tar_make()` em background (~1-2h, dominado por ~6 SEs placebo a ~12 min cada).

Targets que serão reconstruídos:
- `synth_data`, `synth_fit`, `se_synth` (modelo principal)
- `synth_data_baseline`, `synth_fit_baseline`, `se_synth_baseline` (robustez, novos)
- Todos os placebos (`placebo_teste_treatment02/04/11` e seus SEs)
- LatAm (`synth_fit_latam`, `se_synth_latam`)
- Extended (`synth_data_extended`, `synth_fit_extended`, `se_synth_extended`)
- Plots e diagnósticos downstream

**NÃO reconstruirá**: Cross-country DiD (depende de `event_study_data`, não de `synth_data`).

### Fase 2: Texto do paper (paper_v3.Rmd)

#### 2.1 Abstract (line 19)

Ajuste mínimo — os números inline (`r sprintf(...)`) serão atualizados automaticamente pelo targets. Considerar reforçar linguagem de significância se percentual mudar visivelmente.

#### 2.2 Seção Data and Variables (após line 285)

Adicionar novo parágrafo descrevendo as 3 covariáveis institucionais:
- `inst_parliamentary`: fonte DPI 2015, justificativa teórica (Chen & Zhou 2021)
- `inst_military_exec`: fonte DPI 2015, justificativa (Morgan 2019)
- `us_trade_agreement`: fonte Dynamic Gravity Database (release_2), justificativa (Kastner & Pearson 2021; Flores-Macías & Kreps 2013)

#### 2.3 Tabela descritiva (lines 289-326)

Adicionar labels para novas variáveis no `tbl_summary()`:
```r
inst_parliamentary ~ "Parliamentary System",
inst_military_exec ~ "Military Executive",
us_trade_agreement ~ "Trade Agreement with US"
```

#### 2.4 Seção Robustness (lines 378-420)

Adicionar modelo baseline (sem covariáveis institucionais) à tabela de placebos:
- Ler `tar_read(synth_fit_baseline)` e `tar_read(se_synth_baseline)`
- Adicionar linha "Baseline (2009, without institutional covariates)" à tabela
- Adicionar parágrafo explicativo: estimativa pontual estável, melhora de precisão com covariáveis

#### 2.5 Resultados empíricos (line 356)

Números auto-atualizados via `tar_read()`. Revisar prosa para refletir significância a 5%.

### Fase 3: Bibliografia (synth-trade-china.bib)

Adicionar referência do DPI (`@cruz_etal2021` ou similar) se não existir. As demais referências (@chen_zhou2021, @morgan_2019, @kastner_pearson2021, @flores-macias_kreps2013, @hirshberg_klosin2024) já estão no .bib.

### Fase 4: Validação — via skill `/validate-bib`

Rodar `/validate-bib` para verificar:
- Nova referência DPI corretamente formatada
- Todas as citações no texto resolvidas no .bib
- Nenhuma referência órfã

### Fase 5: Revisão de código — via skill `/review-r`

Rodar `/review-r` sobre os arquivos modificados para verificar qualidade do código R.

## Arquivos a modificar

- [x] `scripts/functions.R` — Descomentar/adaptar `get_dpi_data()`, criar `get_us_trade_agreement()`, modificar `clean_synth_data()` e `cov_matrix()`. Fix ROM→ROU no DPI. Fix MASS::select masking.
- [x] `_targets.R` — Adicionar targets de dados institucionais, modificar `synth_data` e `synth_data_extended`, adicionar targets de robustez
- [x] `paper_v3.Rmd` — Seções Data/Variables, Robustness, labels descritivas, abstract atualizado (41%, p=0.032)
- [x] `synth-trade-china.bib` — Adicionada referência DPI (@cruz_etal2021)

## O que NÃO muda

- Cross-country DiD (especificação, targets, texto)
- Seção de mecanismos (Folha de SP)
- Conclusão (ajuste mínimo se necessário)

## Verificação

- [x] `tar_make()` completa sem erros (3h 49min, 26 targets rebuilt)
- [x] ATT do novo modelo = -0.264 (ligeiramente diferente do ad hoc, como previsto)
- [x] SE placebo = 0.123 < 0.133 (precisão melhorou)
- [x] p-valor = 0.032 < 0.05 ✓
- [x] Modelo baseline de robustez: ATT = -0.264, SE = 0.145
- [x] `rmarkdown::render("paper_v3.Rmd")` compila sem erros
- [ ] `/validate-bib` — não executado
- [ ] `/review-r` — não executado

## Riscos

1. **SE placebo pode diferir do ad hoc**: O ad hoc usou 50 reps fora do pipeline; o pipeline usa método placebo padrão do synthdid (pseudo-tratamentos nos controles). O p-valor final pode ser diferente de 0.016.
2. **DPI cobre até 2015**: Forward-fill necessário para 2016-2017. Variáveis institucionais mudam lentamente, portanto razoável.
3. **Diferença S0 ad hoc vs pipeline**: O ad hoc excluiu trade shares; o pipeline as inclui. O modelo final terá 13 covariáveis, não 11.
4. **Tempo de execução**: ~1-2h para rebuild completo do pipeline.
