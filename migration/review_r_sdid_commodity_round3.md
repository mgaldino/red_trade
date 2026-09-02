# Revisão R independente — SDiD e commodities, rodada 3

Commit revisado: `8cadddb0f4dca0daa149fb4a03c720df36dfc68b`.

Veredito: **FAIL**. Nota: **D**.

A revisão foi estritamente estática. O revisor não executou R, `targets`,
modelos, placebos, bootstrap ou computação de dados e não alterou arquivos.

## Problemas críticos

1. A construção candidata produzia `NaN` estrutural para exportadores sem
   bens, enquanto o comparador corretamente reprovava qualquer `NaN`. O
   baseline obrigatório representa essas quantidades indefinidas como `NA`.
2. O gate exigia cinco anos observados em todas as linhas globais, embora o
   próprio baseline contenha Guiana Francesa com um ano e Sérvia e Montenegro
   com dois. A cobertura completa deve ser exigida no universo analítico do
   SDiD; a tabela global deve preservar e auditar sua cobertura parcial.

## Melhoria importante

Os testes não cobriam `NaN`, ausência estrutural por exportações de bens iguais
a zero, cobertura global parcial nem uma chamada integral ao gate de
derivações com essas condições.

## Correções da rodada anterior confirmadas

- tolerância para overshoot de precisão de máquina em shares;
- SE preferida com 20.000 replicações, seed `20260520` e checkpoint por lote;
- limites de BLAS antes do paralelismo;
- ranks retomáveis e escrita atômica de RDS;
- gate agregado fail-closed em `NA`;
- file targets para exposição commodity e Pink Sheet;
- comparação normalizada de integer/double e vazio/`NA`, com reprovação de
  infinitos;
- scan único do ITPD-E;
- ausência de promoção antecipada.

Sugestão adicional do revisor: validar também tipos, estados permitidos e
finitude das linhas estimadas antes de reutilizar checkpoints de rank.
