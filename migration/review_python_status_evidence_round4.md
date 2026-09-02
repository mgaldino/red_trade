# Revisão independente Python: evidência de status — rodada 4

Commit revisado: `24702e0fbe6a1c2154353362fd24782af7b110a9`, pai direto
`c0f4870e49c6eeb48ede7ce46ae01cde5907fbc4`.

Revisor: sessão independente `01a06149-c336-79e3-8199-246f90aab33f`, modo
somente leitura, aplicando `review-python`.

## Resultado

**Nota: C — GATE: FAIL**

Nenhum problema crítico foi encontrado. Três achados importantes impediram
`PASS`.

## Achados importantes

1. A whitelist global de URI não validava cada componente. Aceitava colchetes
   crus em path/query, um segundo `#` no fragmento e IPv6, embora o contrato
   restrinja host a DNS ou IPv4.
2. `request_missing_url()` validava somente a URL inicial. O redirecionador
   padrão do `urllib` permite `ftp:` e o opener contém `FTPHandler`, de modo que
   uma resposta HTTP poderia ampliar a aquisição para fora de HTTP(S).
3. Se outro processo criasse o destino entre o teste inicial e `os.link()`,
   `FileExistsError` abortava o batch. O destino concorrente não era validado e
   o staging podia ficar sem metadado final, log ou manifest.

## Verificações

- Compilação em memória dos quatro Python: passou.
- Manifests, 137 arquivos brutos, ledgers, três CSVs derivados e input do
  incumbente mantiveram dimensões e hashes contratuais.
- Os dois `main()` permaneceram acquisition-only e read-only por padrão.
- Nenhuma rede, coleta real, derivação, `tar_make()`, modelo, placebo ou
  bootstrap foi executado; nenhum arquivo foi alterado.
- As fixtures com filesystem temporário não iniciaram no sandbox read-only;
  os achados foram demonstrados por probes em memória.

## Sugestão não bloqueante

Registrar em `size_bytes` o tamanho real do artefato `.error.txt` produzido
após falha de rede.

