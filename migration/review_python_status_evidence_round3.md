# Revisão independente Python: evidência de status — rodada 3

Commit revisado: `c0f4870e49c6eeb48ede7ce46ae01cde5907fbc4`.

Revisor: sessão independente `01a06138-73da-7a63-8045-25de4d92b1a5`, modo
somente leitura, aplicando `review-python`.

## Resultado

**Nota: C — GATE: FAIL**

As quatro falhas da rodada 2 foram corrigidas. A cópia e o hash agora usam o
mesmo descritor-fonte, a publicação usa hard link exclusivo, o destino é
revalidado e nenhum caminho de falha remove o pathname bruto contratado. Os
dois caminhos reais `main(acquire=True)` possuem fixtures offline,
`write_checksums` está bloqueado e backoffs não finitos são rejeitados.

## Achado importante

O validador Python de URLs ainda aceitava `U+007F` (`DEL`), controles C1 como
`U+0080` e caracteres crus fora da gramática URI, como `<`. Isso violava o
contrato de URL sintaticamente válida e sem controles. Os URLs congelados não
contêm esses caracteres, mas o gate precisa impor a regra para inputs futuros.

Correção exigida: rejeitar todos os controles e caracteres crus fora da
gramática URI, ou normalizar explicitamente IRI para URI, e adicionar fixtures
adversariais.

## Verificações

- Compilação em memória dos quatro arquivos: passou.
- Manifests: 89 e 48 entradas, com hashes contratuais.
- Hashes dos ledgers, três CSVs derivados e input de incumbente: preservados.
- Worktree limpo; nenhuma rede, coleta, derivação, `tar_make()`, modelo,
  placebo ou bootstrap executado.
- As fixtures dinâmicas não rodaram no sandbox somente leitura do revisor por
  ausência de diretório temporário gravável; isso foi registrado como limitação
  do ambiente, não como defeito do código.

