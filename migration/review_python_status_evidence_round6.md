# Revisão independente Python: evidência de status — rodada 6

Commit revisado: `33f2e3cce6ba2dc77db63be8fc72d4991ced0a0b`, pai direto
`9fc075fe8d41051f95c7edd762d8f7542ac508ce`.

Revisor: sessão independente `01a06172-c1d0-7961-80e8-96773cb1cba3`, modo
somente leitura, aplicando `review-python`.

## Resultado

**Nota: C — GATE: FAIL**

## Achado importante

`_safe_repo_path()` resolvia o pathname completo antes de devolvê-lo. Se o destino
contratado fosse um symlink, `_sha256_regular_file()` receberia o alvo já resolvido e
seu `O_NOFOLLOW` não protegeria o pathname original. O preflight também usava
`is_file()` e `sha256()`, que seguem symlinks. Assim, um link interno para bytes
manifestados podia ser aceito como cache válido e produzir código de saída 0.

Correção requerida: preservar o pathname lexical até a abertura no-follow, rejeitar
symlink final ou em diretório pai, e cobrir symlink matching, dangling symlink e
concorrente não manifestado nos dois entrypoints, inclusive códigos de saída e
preservação do concorrente.

## Verificações aprovadas

- Concorrentes regulares matching e divergentes são distinguidos corretamente.
- Os dois `main()` convertem conflito em código 2 e matching em código 0.
- Staging criado é finalizado com log e manifest; o manifest congelado não é reescrito.
- URI por componentes, redirects HTTP(S)-only e promoção descriptor-bound continuam
  corretos.
- Compilação integral em memória passou; os checks sem fixtures validaram os dois
  entrypoints, 89/48 arquivos e ledgers 21/22.

As fixtures temporárias não puderam rodar no sandbox somente leitura do revisor.
Nenhuma rede, coleta, `tar_make()`, modelo, placebo ou bootstrap foi executado.
