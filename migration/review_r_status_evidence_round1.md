# Revisão de código: migração de evidência de status

## Resumo executivo

No commit `231ab001` sobre `05c1144`, a reconstrução semântica atual, os hashes
dos insumos e a topologia do DAG passam. Entretanto, o gate não congela
efetivamente o universo exato de 14 casos e os writers não reproduzem os hashes
dos três CSVs de referência. São bloqueios de reprodutibilidade e integridade
pré-escrita.

## Nota geral: C

## Problemas críticos 🔴

1. **O gate aceita alteração indevida do universo congelado e pode escrever antes
   de detectar o problema.**

   A validação exige apenas 14 linhas, unicidade e anos dentro de uma faixa; não
   exige o conjunto contratual de países, códigos ISO válidos, nomes ou pares
   país-ano exatos. Em teste negativo read-only, a substituição de `SAU` por `x`
   no universo e nas anotações produziu `ALTERED_GATE_PASSED=TRUE`. Os três
   writers são executados antes da validação downstream do consumidor.

   Correção necessária: validar o conjunto exato ordenado de
   `(iso3c, country_name, entry_year)`, incluindo formato ISO e não ausência, e
   mover validações de schema/equivalência para candidatos em memória antes de
   qualquer writer.

## Melhorias importantes 🟡

1. A serialização dos três CSVs não reproduz o baseline contratado. Os writers
   produziram hashes diferentes por LF versus CRLF e, em dois arquivos, por
   campos literais `NA` transformados em vazios. `compare_frame()` também usava
   `check.attributes = FALSE`, aceitando nomes de colunas e tipos incorretos.
   Testar nomes, ordem, tipos e hashes serializados, ou documentar e aprovar novos
   hashes canônicos.
2. Tornar estritas as validações de anos, `publication_date` e URLs: impedir
   truncamento por `as.integer()`, exigir datas ISO válidas e hostname HTTP(S).

## Sugestões 🟢

- O gate combinado causa sobre-invalidação segura, porém desnecessária.
- O store absoluto em `_targets.yaml` é compartilhado com o checkout irmão e
  exige atenção a locks/interferência em eventual build autorizado.

## Pontos positivos ✓

- `HEAD` e base confirmados; worktree permaneceu limpo.
- Parse, `tar_validate()` e teste estático R passaram.
- Os 89/89 e 48/48 arquivos brutos e todos os inputs congelados coincidem com os
  SHA-256 contratados.
- O DAG é acíclico e nenhum target HTTP aparece na ancestry do bloco.
- O conteúdo atual reproduz as tabelas 14 × 14, 14 × 25 e 14 × 18 e as duas
  tabelas do apêndice.
- Todos os `select()` relevantes estão qualificados como `dplyr::select()`.

GATE: FAIL
