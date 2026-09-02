# Revisão R independente — SDiD e commodities, rodada 5

Commit revisado: `941c0aba79ca377d8163906f465194ee890ee40b`.

Veredito: **FAIL**. Nota: **C**.

A revisão foi estritamente estática, com a skill `review-r`. O revisor não
executou R, `targets`, modelos, placebos, bootstrap ou computação de dados e
não alterou arquivos. Não houve achado crítico; um achado importante impediu o
`PASS`.

## Achado importante

1. O fingerprint dos ranks ainda não cobria
   `sdid_build_covariate_array()`. Essa função é chamada por `sdid_fit_spec()`
   quando há covariáveis, mas alterar seu corpo não altera o corpo textual da
   função chamadora. Portanto, o rank commodity da Tabela 5 poderia reutilizar
   um checkpoint obsoleto de estimativa e RMSPE.

## Melhorias menores

- testar diretamente que mudanças em `sdid_fit_summary_row()` e
  `sdid_build_covariate_array()` mudam o fingerprint;
- testar a rejeição explícita de RMSPE negativo;
- acrescentar regressões para superconjunto de checks e `passed = FALSE` no
  gate agregado.

## Itens confirmados

O revisor confirmou como corretos: gate agregado com conjunto exato e falha
fechada; repetição de linhas de rank com erro sem perder linhas estimadas;
normalização de `NA`/`NaN`/`Inf`; cobertura global de 239 linhas e cinco anos
somente no universo analítico; tolerâncias; seeds e common random numbers; SE
preferida com 20 mil repetições e comparações com 5 mil; checkpoints atômicos e
BLAS; scan único via DuckDB; file targets; e ausência de promoção antecipada.
