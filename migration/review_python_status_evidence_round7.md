# Revisão independente Python: evidência de status — rodada 7

Commit revisado: `47ce9162ee1a678ffbcc0e412b459dbcc119274a`, pai direto
`33f2e3cce6ba2dc77db63be8fc72d4991ced0a0b`.

Revisor: sessão independente `01a06182-b157-7100-8719-c3d6d9a5d3a4`, modo
somente leitura, aplicando `review-python`.

## Resultado

**Nota: C — GATE: FAIL**

## Achado importante

Symlink final, dangling symlink, diretório pai symlinkado, destino não manifestado e
hash divergente já eram bloqueados com segurança no preflight. Porém, a exceção de
validação escapava dos dois `main()`, produzindo normalmente código 1 em vez do código
2 contratado para conflito.

Correção requerida: representar a falha de preflight por exceção ou resultado
específico, convertê-la em retorno 2 nos dois entrypoints e testar conflitos que já
existam antes da chamada a `main()`.

## Verificações aprovadas

- O pathname lexical chega intacto a `os.open(..., O_NOFOLLOW)`.
- Symlink matching, dangling e pai symlinkado são rejeitados; matching regular é
  reutilizado.
- Manifest/preflight não seguem o arquivo bruto final.
- Concorrentes e manifests são preservados; staging criado é finalizado.
- URI, redirects HTTP(S)-only e promoção não regrediram.
- Compilação em memória e `git diff --check` passaram; os checks anteriores às
  fixtures validaram os dois entrypoints, 89/48 arquivos e ledgers 21/22.

As fixtures temporárias não puderam rodar no sandbox somente leitura do revisor.
Nenhuma rede, coleta, `tar_make()`, modelo, placebo ou bootstrap foi executado.
