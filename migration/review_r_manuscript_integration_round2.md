# Revisão R independente — integração do manuscrito, rodada 2

- Commit revisado: `c362a9cf9095672d24382c0e1255c77a9a54710b`
- Pai confirmado: `0c41feb8930620e83f3f02cf710675702074f3e6`
- Sessão independente: `01a061bd-965f-78b0-86ab-6ed3bd2af333`
- Nota: `C`
- Gate estático: `FAIL`

## Findings bloqueantes

1. Um link simbólico quebrado no destino escapava do guard porque
   `file.exists()` retorna falso nesse caso, apesar de `Sys.readlink()` identificar o
   link.
2. A relação um-para-um era verificada somente pelos textos dos outputs. Aliases
   como `x` e `./x`, duplicatas nos arquivos staged e interseções entre staged e
   outputs podiam referir-se ao mesmo caminho efetivo.

O revisor também solicitou ampliar os testes para fluxos de sucesso, estados mistos,
links válidos e quebrados, tipos e `NA`, limpeza dos backups após sucesso/rollback e
preservação dos backups quando o próprio rollback falhar.

## Testes da sessão

O preflight Git e `git diff --check` passaram. A suíte R não pôde iniciar no sandbox
somente leitura do revisor porque o processo não conseguiu criar `R_TempDir`; por
isso, o parecer não atribuiu à sessão resultados de parsing, `tar_validate()` ou DAG.
Nenhuma rede, build, estimação, writer, renderização ou edição foi executada.
