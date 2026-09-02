# Revisão independente Python: evidência de status — rodada 5

Commit revisado: `9fc075fe8d41051f95c7edd762d8f7542ac508ce`, pai direto
`24702e0fbe6a1c2154353362fd24782af7b110a9`.

Revisor: sessão independente `01a06162-9cca-70c1-9fad-80ded28acd4e`, modo
somente leitura, aplicando `review-python`.

## Resultado

**Nota: C — GATE: FAIL**

## Achado importante

Um destino podia aparecer entre o preflight e o processamento da linha. Nesse caso,
`_acquire_ledger_row()` aceitava o arquivo como `cached_*` sem confrontar seus bytes
com o hash congelado. Um concorrente divergente podia, portanto, ser excluído de
`attempted` e fazer os dois entrypoints retornarem código 0.

Correção requerida: revalidar sem seguir symlink todo destino presente no processamento
da linha; reutilizar matching e tratar mismatch ou destino sem entrada no manifest como
conflito bloqueante. Cobrir matching e conflito anteriores ao ramo de promoção, inclusive
os códigos de saída dos dois `main()`.

## Verificações

- URI por componente, somente DNS/IPv4, e redirecionamentos HTTP(S)-only: corretos.
- A corrida em `os.link()` distingue matching e conflito sem remover o concorrente.
- O fluxo normal e os erros de linha finalizam log e manifest de staging.
- O manifest congelado não é reescrito.
- Nenhuma rede, coleta, `tar_make()`, modelo, placebo ou bootstrap foi executado.

As fixtures temporárias não puderam rodar no sandbox somente leitura do revisor. Antes
desse limite, passaram os checks dos dois `main()` como acquisition-only e read-only por
padrão, a delegação ao helper e a validação dos ledgers e hashes brutos.

