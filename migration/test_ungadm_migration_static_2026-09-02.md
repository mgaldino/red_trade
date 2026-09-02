# Testes estáticos da migração UNGA-DM — 2026-09-02

## Escopo

Testes baratos e determinísticos. Nenhum `tar_make()`, modelo `synthdid`/`fect`,
placebo ou bootstrap econométrico foi executado.

## Comandos

```sh
LC_ALL=en_US.UTF-8 R_PROFILE_USER=/dev/null R_ENVIRON_USER=/dev/null \
  Rscript migration/test_ungadm_migration_static.R

Rscript -e "m <- targets::tar_manifest(callr_function = NULL); \
  cat('STATIC_MANIFEST_PASS targets=', nrow(m), '\n', sep='')"
```

## Resultado

- hashes e tamanhos dos insumos congelados: `PASS`;
- harmonização real BSV/UNGA-DM: `PASS`;
- 28 linhas UNGA-DM sem `iso3c` preservadas: `PASS`;
- correção alemã da sessão 45 para `DEU`: `PASS`;
- 31 lacunas entre fontes após a correção alemã: `PASS`;
- correlação do outcome na janela 1997–2015 >= 0,95: `PASS`;
- `left_join` conserva grade e tratamento: `PASS`;
- 2021–2023 permanecem presentes com UNGA-DM ausente: `PASS`;
- risk set aplicado antes do filtro de outcome: `PASS`;
- painéis BSV/UNGA-DM comuns têm linhas e tratamento idênticos: `PASS`;
- painel SDiD conserva chaves e tratamento: `PASS`;
- gates rejeitam linhas ausentes, duplicadas e `passed = NA`: `PASS`;
- checkpoint pareado completo é reutilizado: `PASS`;
- checkpoint parcial retoma apenas draws ausentes: `PASS`;
- mudança no corpo do estimador invalida o checkpoint: `PASS`;
- parse de `_targets.R` e do novo arquivo de funções: `PASS`;
- `git diff --check`: `PASS`;
- manifesto estático: `STATIC_MANIFEST_PASS targets=335`.

Resultado terminal do script:

```text
ALL_STATIC_UNGADM_MIGRATION_TESTS_PASSED
```

O manifesto exigiu restaurar `renv`, `targets`, `here` e `tarchetypes` a partir
do lockfile/cache no ambiente isolado do worktree. Isso não alterou o lockfile.
