# Testes baratos — migração SDiD e commodities

Data: 2026-09-02.

Comando executado:

```sh
Rscript --vanilla migration/test_sdid_migration_static.R
```

Resultado: **PASS**.

Cobertura:

- normalização de chaves integer/double após round trip CSV;
- equivalência de texto vazio e `NA` gerada pela serialização CSV;
- tolerância numérica absoluta mais relativa a `1e-12`;
- reprovação de divergência além da tolerância;
- reprovação de `Inf`;
- reprovação de chave divergente;
- fixture ITPD-E 2004–2008 processada em DuckDB;
- exclusão de serviços e fluxos domésticos do denominador de bens;
- cálculo da participação chinesa sobre bens;
- auditoria de fluxos domésticos;
- cobertura dos cinco anos da janela de exposição.

Também passaram:

- parse de `_targets.R` e `scripts/functions_sdid_targets_migration.R`;
- `git diff --check`;
- manifesto estático com 286 targets.

Não foram executados `tar_make()`, modelos, placebos, bootstrap nem o scan do
ITPD-E real de 7,8 GB.
