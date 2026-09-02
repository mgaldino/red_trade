# Revisão independente R: evidência de status — rodada 3

Commit revisado: `c0f4870e49c6eeb48ede7ce46ae01cde5907fbc4`, pai direto
`7ad6e08d32907c4c4efca12faf111f19e9056f4e`.

Revisor: sessão independente `01a06138-73da-7190-bdbf-4a28b0aff345`, modo
somente leitura, aplicando `review-r`.

## Resultado

**Nota: B — GATE: FAIL**

Os testes oficiais passaram: 137 hashes brutos, três hashes serializados,
equivalência das tabelas, DAG acíclico e ancestry correta dos gates antes dos
writers. Dois achados importantes, porém, impediram `PASS`.

## Achados importantes

1. O ramo manual de IPv6 aceitava autoridades malformadas como `[::::]`,
   `[1:2:3:4:5:6:7:8:9]`, `[12345::1]` e `[::ffff:999.0.0.1]` tanto em `url`
   quanto em `archive_url`. Era necessário usar um parser apropriado ou rejeitar
   hosts entre colchetes quando IPv6 não fosse necessário.
2. `accessed_at` era obrigatório no schema, mas não era validado. O valor
   `not-a-date` mantinha todos os checks verdes. Era necessário exigir um
   timestamp ISO 8601/RFC 3339 válido e adicionar fixture adversarial.

## Verificações

- Parse dos arquivos em escopo e teste R oficial: passaram.
- Ledgers `21 × 25` e `22 × 36` e hashes congelados: corretos.
- Três outputs `14 × 14`, `14 × 25` e `14 × 18`: nomes, ordem, tipos, valores e
  hashes serializados idênticos às referências.
- Tabelas do apêndice idênticas ao baseline.
- Nenhuma rede, coleta, `tar_make()`, modelo, placebo ou bootstrap executado.

