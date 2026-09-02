# Revisão independente Python: evidência de status — rodada 2

Commit revisado: `7ad6e08d32907c4c4efca12faf111f19e9056f4e`

Revisor: sessão independente `01a06121-993a-7bb3-aeea-038b56822c13`, modo
somente leitura, aplicando `review-python` e adjudicando os achados da rodada 1.

## Resultado

**Nota: C — GATE: FAIL**

O commit resolveu a imutabilidade dos manifests, separou staging de refreeze
autoral, passou a recuperar status dos metadados, restringiu a aquisição a
HTTP(S) explícito e manteve os dois `main()` sem derivação. Os 89 + 48 hashes
brutos e os hashes dos ledgers permaneceram iguais ao contrato.

## Achados bloqueantes

1. A promoção calculava `sha256(actual_path)` e depois reabria o pathname para
   copiar. Portanto, os bytes copiados não estavam ligados ao mesmo descritor
   usado na verificação, e o destino promovido não era revalidado.
2. `_write_stream_exclusive()` e `_copy_exclusive()` removiam um pathname após
   exceção. Um processo concorrente poderia substituir esse pathname entre o
   teste e o `unlink()`, criando risco TOCTOU destrutivo.
3. Os testes cobriam aquisição pelo helper, mas não o caminho real
   `main(acquire=True)` dos dois coletores. A lista de chamadas proibidas também
   continha `write_checksum_manifest`, mas não o nome legado real
   `write_checksums`.
4. `validate_acquisition_options()` aceitava `NaN` e infinito como backoff.

## Limitação de execução do revisor

Os arquivos compilaram em memória e os hashes foram rechecados. O sandbox
somente leitura do revisor não ofereceu diretório temporário gravável, por isso
as fixtures não rodaram nessa sessão; isso foi registrado como limitação do
ambiente, não como defeito adicional.

Nenhuma rede, coleta, derivação, modelo, placebo, bootstrap ou `tar_make()` foi
executado, e nenhum arquivo foi editado pelo revisor.
