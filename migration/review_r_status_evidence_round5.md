# Revisão independente R/targets: evidência de status — rodada 5

Commit revisado: `9fc075fe8d41051f95c7edd762d8f7542ac508ce`, pai direto
`24702e0fbe6a1c2154353362fd24782af7b110a9`.

Revisor: sessão independente `01a06162-9cde-7b32-8561-79c5d3c74f21`, modo
somente leitura, aplicando `review-r`.

## Resultado

**Nota: B — GATE: FAIL**

## Achados importantes

1. `_targets.yaml` ainda apontava para o `_targets/` do checkout de `main`, embora o
   protocolo determine um store local à worktree. O teste usava corretamente um store
   temporário, mas não validava a configuração efetiva de uma futura execução normal.
2. O commit ainda não possuía `review-python/PASS`; o parecer Python independente da
   mesma rodada encontrou a corrida anterior ao processamento da linha.

## Verificações R aprovadas

- O teste oficial terminou com código 0 e
  `ALL_STATIC_STATUS_EVIDENCE_R_TESTS_PASSED`.
- 89/89 e 48/48 hashes brutos e os dois ledgers congelados passaram.
- URI por componentes, `archive_url`, RFC 3339, schemas, chaves e universo exato de
  14 casos passaram.
- Os três CSVs reproduziram nomes, ordem, tipos, valores e SHA-256 serializado.
- As duas tabelas do apêndice permaneceram equivalentes em conteúdo.
- `tar_validate()` passou; o DAG é acíclico; raw files e gates são ancestrais dos
  writers e das tabelas.

Nenhuma rede, coleta, `tar_make()`, modelo, placebo ou bootstrap foi executado.

