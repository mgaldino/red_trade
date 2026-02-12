# Guia de Interpretação: HonestDiD

## O que é

O HonestDiD (Rambachan & Roth, 2023) é um framework para avaliar a robustez de resultados de Difference-in-Differences (DiD). Em vez de *testar* se parallel trends são válidos (o que tem baixo poder estatístico), ele constrói **intervalos de confiança robustos** que permanecem válidos mesmo sob violações controladas da hipótese de tendências paralelas.

A pergunta central é: **"o resultado sobrevive se parallel trends não forem exatamente válidos?"**

## Os dois benchmarks

### 1. Smoothness (DeltaSD, parâmetro M)

O parâmetro M controla quanto a *segunda diferença* do viés pode mudar entre períodos consecutivos — ou seja, quão não-linear a tendência diferencial (entre tratados e controles) pode ser.

- **M = 0** → parallel trends exatas (nenhuma violação permitida)
- **M > 0** → permite desvios cada vez maiores da linearidade

Se o intervalo de confiança exclui zero em M = 0 mas inclui zero em M = 0.03, por exemplo, isso significa que o resultado é robusto a parallel trends exatos, mas não a violações moderadas de não-linearidade.

### 2. Relative Magnitudes (DeltaRM, parâmetro Mbar)

O parâmetro Mbar controla o tamanho do viés pós-tratamento *relativo à maior violação pré-tratamento observada*.

- **Mbar = 0.5** → o viés pós-tratamento pode ser até 50% do maior desvio pré-tratamento
- **Mbar = 1** → o viés pós pode ser tão grande quanto o maior desvio pré-tratamento
- **Mbar = 2** → até o dobro

Este benchmark é intuitivo: usa os próprios dados pré-tratamento como referência para calibrar o quanto de violação é "plausível".

## Como interpretar os resultados

A saída é uma tabela com colunas `lb` (lower bound), `ub` (upper bound), e o parâmetro de sensibilidade (`M` ou `Mbar`). Para cada nível de violação permitida, você obtém um intervalo de confiança robusto.

**O resultado é robusto se:** o intervalo de confiança exclui zero (ou o valor nulo relevante) para valores plausíveis do parâmetro de sensibilidade.

**O resultado é frágil se:** o intervalo inclui zero mesmo em M = 0 (parallel trends exatos).

## Escolhendo o período pós-tratamento: o parâmetro `l_vec`

Por padrão, o HonestDiD analisa **um único período pós-tratamento** (tipicamente e = 0, o primeiro período após o tratamento). Isso é controlado pelo argumento `l_vec`, um vetor de pesos sobre os períodos pós-tratamento.

### Default: primeiro período pós-tratamento (e = 0)

```r
l_vec <- HonestDiD::basisVector(index = 1, size = numPostPeriods)
```

Isso cria um vetor como `c(1, 0, 0, 0, 0)` — todo o peso no primeiro período.

### Outro período específico

Para analisar o terceiro período pós-tratamento (e = 2), por exemplo:

```r
l_vec <- HonestDiD::basisVector(index = 3, size = numPostPeriods)
# Resultado: c(0, 0, 1, 0, 0)
```

### Média de todos os períodos pós-tratamento

Para analisar o efeito médio (comparável ao overall ATT):

```r
l_vec <- rep(1 / numPostPeriods, numPostPeriods)
# Resultado: c(0.2, 0.2, 0.2, 0.2, 0.2) para 5 períodos
```

### Quando mudar o default?

O default (e = 0) funciona bem quando o efeito é **imediato** — um salto logo após o tratamento. Mas quando:

- O efeito **leva tempo para se materializar** (build-up gradual)
- O efeito **se acumula ao longo de vários períodos**
- O ATT geral é significativo mas o efeito em e = 0 não é

...então usar a **média dos períodos pós-tratamento** (`rep(1/numPostPeriods, numPostPeriods)`) ou um **período posterior específico** (`basisVector(index = k, ...)`) produz uma análise de sensibilidade mais informativa e comparável ao estimador agregado.

## Exemplo completo

```r
library(HonestDiD)

# betahat: vetor com coeficientes do event study (pré + pós)
# sigma:   matriz de variância-covariância dos coeficientes

# Média dos períodos pós-tratamento
l_vec <- rep(1 / numPostPeriods, numPostPeriods)

# Smoothness
createSensitivityResults(
  betahat = betahat,
  sigma = sigma,
  numPrePeriods = numPrePeriods,
  numPostPeriods = numPostPeriods,
  l_vec = l_vec,
  Mvec = seq(0, 0.05, by = 0.01)
)

# Relative Magnitudes
createSensitivityResults_relativeMagnitudes(
  betahat = betahat,
  sigma = sigma,
  numPrePeriods = numPrePeriods,
  numPostPeriods = numPostPeriods,
  l_vec = l_vec,
  Mbarvec = seq(0.5, 2, by = 0.5)
)
```

## Referência

Rambachan, A. & Roth, J. (2023). A More Credible Approach to Parallel Trends. *Review of Economic Studies*, 90(5), 2555–2591. doi:10.1093/restud/rdad018
