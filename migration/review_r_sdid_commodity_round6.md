# Revisão R independente — SDiD e commodities, rodada 6

Commit revisado: `54b1e222e487b375b6137d6dc447fcd07eefac8b`.

Veredito: **FAIL**. Nota: **C**.

A revisão foi estritamente estática, com a skill `review-r`. O revisor não
executou R, `targets`, modelos, placebos, bootstrap ou computação de dados e
não alterou arquivos. Não houve achado crítico; um achado importante impediu o
`PASS`.

## Achado importante

1. O fingerprint ainda não cobria toda a cadeia funcional dos checkpoints de
   rank. Embora já incluísse `sdid_build_covariate_array()`,
   `sdid_fit_summary_row()` e `sdid_rank_distribution()`, deixava de fora
   `sdid_mclapply_checked()`, chamado diretamente para produzir os lotes. Uma
   mudança nesse helper podia manter o mesmo digest e permitir a devolução
   antecipada de um checkpoint completo. A maquinaria de checkpoint
   (`sdid_rank_checkpoint_valid()`, `sdid_read_checkpoint()` e
   `sdid_atomic_save_rds()`) também não estava incluída na promessa explícita
   de invalidação por mudança de código.

## Correção exigida

- incluir no fingerprint os helpers diretos de execução, validação, leitura e
  escrita de checkpoints;
- acrescentar teste integrado barato que grave um checkpoint completo, altere
  um helper coberto e confirme a recomputação de todas as linhas.

## Itens confirmados

O revisor confirmou: cobertura dos dois helpers corrigidos na rodada 5;
rejeição de RMSPE negativo; gate agregado com conjunto exato e falha fechada;
retomada parcial e retry; seeds e common random numbers; 20 mil repetições na
especificação preferida e 5 mil nas demais comparações; limites de BLAS; scan
único do ITPD-E; gate das 239 linhas e cobertura parcial; file targets; e
ausência de promoção antecipada ao manuscrito.
