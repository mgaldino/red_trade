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
- reprovação de `Inf` e `NaN` no comparador;
- reprovação de chave divergente;
- aceitação de overshoot de ponto flutuante em share a precisão de máquina;
- reprovação de violação material dos limites de share;
- gate agregado fail-closed quando `passed` é `NA`;
- escrita/leitura atômica de checkpoint e descarte seguro de RDS corrompido;
- retomada de rank placebo parcial, computando apenas unidades faltantes com
  um fit falso barato, sem modelo estatístico;
- descarte integral de checkpoint de rank legível, mas semanticamente inválido;
- fixture ITPD-E 2004–2008 processada em DuckDB;
- exclusão de serviços e fluxos domésticos do denominador de bens;
- cálculo da participação chinesa sobre bens;
- auditoria de fluxos domésticos;
- normalização de shares estruturalmente indefinidos de `NaN` para `NA` quando
  as exportações de bens são zero;
- preservação de cobertura parcial na tabela global;
- gate integral de derivações com cobertura completa apenas no universo
  analítico e reprovação quando uma linha parcial é incluída nesse universo.

Também passaram:

- parse de `_targets.R` e `scripts/functions_sdid_targets_migration.R`;
- `git diff --check`;
- manifesto estático com 288 targets.
- validação estrutural do baseline commodity real: 239 linhas, cinco com
  cobertura parcial e cinco com exportações de bens iguais a zero.

Não foram executados `tar_make()`, modelos, placebos, bootstrap nem o scan do
ITPD-E real de 7,8 GB.
