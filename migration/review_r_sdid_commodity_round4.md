# Revisão R independente — SDiD e commodities, rodada 4

Commit revisado: `294b5b5c56240a2faedd0d0977df37b66da0f092`.

Veredito: **FAIL**. Nota: **C**.

A revisão foi estritamente estática. O revisor não executou R, `targets`,
modelos, placebos, bootstrap ou computação de dados e não alterou arquivos.
Não houve achado crítico; três achados importantes impediram o `PASS`.

## Achados importantes

1. O gate genérico aceitava uma tabela de validação vazia, nomes duplicados ou
   um subconjunto dos checks obrigatórios. Portanto, ainda podia falhar aberto.
2. Linhas de rank placebo com `status = "error"` eram persistidas e tratadas
   como concluídas. Uma falha transitória nunca seria tentada novamente.
3. O fingerprint do rank não incluía `sdid_fit_summary_row()`, embora essa
   função calcule a estimativa e o RMSPE persistidos.

## Sugestões

- exigir RMSPE finito e não negativo;
- documentar separadamente os comandos usados para inspecionar o baseline real;
- substituir seleções de colunas por indexação base por `dplyr::select()`.

## Correções anteriores confirmadas

- `NaN` estrutural normalizado para `NA`;
- 239 linhas globais preservadas, incluindo cinco coberturas parciais e cinco
  exportadores com bens iguais a zero;
- cinco anos exigidos somente nas 96 unidades do universo analítico;
- comparator CSV, checkpoints de SE, escrita atômica, seeds, replicações,
  common random numbers, BLAS, scan único, file targets e ausência de promoção
  antecipada.
