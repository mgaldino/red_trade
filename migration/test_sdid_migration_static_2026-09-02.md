# Testes baratos — migração SDiD e commodities

Data: 2026-09-02.

Comando executado:

```sh
Rscript --vanilla migration/test_sdid_migration_static.R
```

Resultado: **PASS**.

Cobertura:

- normalização de chaves integer/double após round trip CSV;
- equivalência de texto vazio e `NA` gerada pela serialização CSV;
- tolerância numérica absoluta mais relativa a `1e-12`;
- reprovação de divergência além da tolerância;
- reprovação de `Inf` e `NaN` no comparador;
- reprovação de chave divergente;
- aceitação de overshoot de ponto flutuante em share a precisão de máquina;
- reprovação de violação material dos limites de share;
- gate agregado fail-closed quando `passed` é `NA`;
- gate agregado exige tabela não vazia, nomes únicos e o conjunto exato de
  checks obrigatórios, reprovando também checks extras e `passed = FALSE`;
- escrita/leitura atômica de checkpoint e descarte seguro de RDS corrompido;
- retomada de rank placebo parcial, computando apenas unidades faltantes com
  um fit falso barato, sem modelo estatístico;
- descarte integral de checkpoint de rank legível, mas semanticamente inválido;
- retomada de linha de rank com erro transitório, preservando as linhas válidas;
- fingerprint de rank inclui tanto a função que calcula estimativa e RMSPE
  quanto a função que constrói a matriz de covariáveis;
- checkpoint de rank rejeita explicitamente RMSPE negativo;
- fixture ITPD-E 2004–2008 processada em DuckDB;
- exclusão de serviços e fluxos domésticos do denominador de bens;
- cálculo da participação chinesa sobre bens;
- auditoria de fluxos domésticos;
- normalização de shares estruturalmente indefinidos de `NaN` para `NA` quando
  as exportações de bens são zero;
- preservação de cobertura parcial na tabela global;
- gate integral de derivações com cobertura completa apenas no universo
  analítico e reprovação quando uma linha parcial é incluída nesse universo.

Também passaram:

- parse de `_targets.R` e `scripts/functions_sdid_targets_migration.R`;
- `git diff --check`;
- manifesto estático com 288 targets;
- validação estrutural do baseline commodity real: 239 linhas, cinco com
  cobertura parcial e cinco com exportações de bens iguais a zero.

Checagens separadas documentadas:

```sh
Rscript --vanilla -e 'source("scripts/functions.R"); source("scripts/functions_targets_migration.R"); source("scripts/functions_sdid_targets_migration.R"); x <- readr::read_csv("data/processed/diagnostics/brazil_sdid_predetermined_commodity_controls/table_2_pre2009_commodity_exposure_by_country.csv", show_col_types = FALSE); validate_sdid_commodity_share_bounds(x); validate_sdid_commodity_structural_missingness(x); stopifnot(all(x$observed_years >= 1L & x$observed_years <= 5L)); cat("BASELINE_COMMODITY_STRUCTURE_PASS rows=", nrow(x), " partial=", sum(x$observed_years < 5L), " zero_goods=", sum(x$pre_goods_exports == 0), "\n", sep = "")'
```

Saída: `BASELINE_COMMODITY_STRUCTURE_PASS rows=239 partial=5 zero_goods=5`.

```sh
Rscript --vanilla -e 'invisible(parse("_targets.R")); invisible(parse("scripts/functions_sdid_targets_migration.R")); invisible(parse("scripts/diagnostics/sdid_placebo_helpers.R")); m <- targets::tar_manifest(callr_function = NULL); stopifnot(nrow(m) == 288L); cat("STATIC_MANIFEST_PASS targets=", nrow(m), "\n", sep = "")'
```

Saída: `STATIC_MANIFEST_PASS targets=288`.

Não foram executados `tar_make()`, modelos, placebos, bootstrap nem o scan do
ITPD-E real de 7,8 GB.
