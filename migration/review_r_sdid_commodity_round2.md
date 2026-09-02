# Revisão R independente — SDiD e commodities, rodada 2

Commit revisado: `a55544c7b30c30b3c1c4236a8a3127c44d9884b6`.

Veredito: **FAIL**. Nota: **D**.

A revisão foi estritamente estática. O revisor não executou R, `targets`,
modelos, placebos, bootstrap ou computação de dados e não alterou arquivos.

## Problema crítico

1. O gate de shares exigia estritamente valores em `[0, 1]`, mas o baseline
   contém `price_mapping_coverage = 1.0000000000000002` por arredondamento.
   Uma reconstrução equivalente pararia antes do comparador tolerante.

## Melhorias importantes

1. A SE preferida de 20.000 replicações ainda era produzida pelo target legado
   via `se_sdid()`, sem checkpoint e sem controle BLAS antes do fork; o wrapper
   candidato só era chamado depois dessa dependência.
2. O rank placebo só reutilizava checkpoint completo, executava todas as
   reatribuições em uma chamada e gravava apenas no final. `saveRDS()` e
   `readRDS()` também não estavam protegidos contra arquivo parcial.
3. `assert_sdid_migration_validation()` filtrava apenas `!passed`; como
   `dplyr::filter()` descarta `NA`, um resultado indeterminado podia passar.
4. Exposição commodity e índices Pink Sheet eram apenas object targets, sem os
   file targets de materialização exigidos pelo contrato.

## Correções confirmadas

- normalização integer/double e vazio/`NA`;
- reprovação de `Inf` e `NaN`;
- tolerância absoluta mais relativa;
- scan único do ITPD-E com `PRAGMA threads = 1`;
- BLAS limitado nos novos wrappers;
- seed `20260520`, replicações e common random numbers;
- fórmulas, janela, tratamento, donor pool e exclusões substantivas;
- ausência de promoção antecipada.
