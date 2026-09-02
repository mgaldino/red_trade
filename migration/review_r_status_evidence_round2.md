# Revisão independente R/targets: evidência de status — rodada 2

Commit revisado: `7ad6e08d32907c4c4efca12faf111f19e9056f4e`

Revisor: sessão independente `01a06121-9937-7230-bd0a-012c5d9b1461`, modo
somente leitura, aplicando `review-r`.

## Resultado

**Nota: B — GATE: FAIL**

O teste estático passou integralmente. O revisor confirmou 89/89 e 48/48 hashes
brutos, universo autoral exato, equivalência de nomes, ordem, tipos, valores e
hashes serializados das três tabelas, outputs novos separados, DAG acíclico e
ancestry completa do gate antes dos writers e das tabelas do apêndice.

## Achado bloqueante

`status_evidence_valid_http_url()` validava apenas o prefixo HTTP(S) e uma
autoridade não vazia. Fixtures adversariais mostraram que o gate aceitava:

- `https://-`;
- `http://user@`;
- `https://example.com:bad`;
- `https://example.com/ bad`.

Além disso, `archive_url` fazia parte do schema requerido, mas não era validada.
O relatório estático afirmava uma garantia mais ampla do que o teste realmente
cobria. O hash congelado dos ledgers impedia corrupção dos outputs atuais, mas a
validação contratada continuava incompleta.

## Observações não bloqueantes

- Registrar `sessionInfo()` na execução controlada futura.
- Manter o build futuro em store isolado: `_targets.yaml` ainda aponta para o
  store absoluto do checkout principal.

Nenhuma rede, coleta, derivação, modelo, placebo, bootstrap ou `tar_make()` foi
executado, e nenhum arquivo foi editado pelo revisor.
