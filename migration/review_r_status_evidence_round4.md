# Revisão independente R: evidência de status — rodada 4

Commit revisado: `24702e0fbe6a1c2154353362fd24782af7b110a9`, pai direto
`c0f4870e49c6eeb48ede7ce46ae01cde5907fbc4`.

Revisor: sessão independente `01a06149-c32e-74d1-a10f-2093e7e7269e`, modo
somente leitura, aplicando `review-r`.

## Resultado

**Nota: B — GATE: FAIL**

## Achados importantes

1. O teste oficial definia `expect_true()`, mas duas novas fixtures chamavam
   `expect()`, que não existia. A execução parava antes das fixtures de URL,
   reconstrução, tabelas e auditoria do DAG.
2. A validação R ainda aplicava uma whitelist global ao restante da URI.
   Aceitava colchetes crus no path e múltiplos delimitadores `#`, inclusive em
   `archive_url`, contrariando a gramática URI contratada.

## Verificações

Com um shim somente em memória para a asserção quebrada, o revisor confirmou:

- 89/89 e 48/48 hashes brutos;
- ledgers `21 × 25` e `22 × 36` com hashes congelados;
- outputs `14 × 14`, `14 × 25` e `14 × 18` com nomes, ordem, tipos, valores e
  SHA-256 serializado idênticos ao baseline;
- as duas tabelas do apêndice exatamente `identical()` ao baseline;
- DAG acíclico em store isolado e gates ancestrais dos writers;
- IPv6 malformado rejeitado e `accessed_at` validado no código.

Nenhuma rede, coleta, `tar_make()`, modelo, placebo ou bootstrap foi executado.

## Sugestão não bloqueante

Documentar o perfil RFC 3339 mais estreito então implementado, ou aceitar as
formas válidas com frações de segundo e designadores `t`/`z` minúsculos.

