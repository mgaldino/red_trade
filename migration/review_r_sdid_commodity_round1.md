# Revisão R independente — SDiD e commodities, rodada 1

Commit revisado: `a78626ccdc87a164173d563b99691ce56433d8ae`

Veredito: **FAIL**. Nota: **D**.

O revisor não executou R, `targets`, modelos, placebos, bootstrap ou
computação de dados e não alterou arquivos.

## Achados críticos

1. O comparador usava `identical()` nas chaves. Após leitura do CSV, inteiros
   como `year` e `weight_rank` tornam-se `double`, de modo que valores iguais
   eram rejeitados. Campos textuais vazios escritos no CSV também voltavam
   como `NA`, produzindo falsas divergências. O problema afetava 11 dos 12
   CSVs do bloco, a Tabela 5 e o gate do Pink Sheet.
2. Diferenças numéricas não finitas eram descartadas. Uma divergência entre
   um valor finito e `Inf` poderia, portanto, passar pelo gate.

## Melhoria importante

3. O ITPD-E de 7,8 GB era percorrido duas vezes. Os placebos podiam usar até
   12 forks sem chamada explícita ao limitador de BLAS e sem checkpoints para
   retomada. Além disso, somas em `DOUBLE` pediam comparação sensível à escala,
   não apenas tolerância absoluta de `1e-12`.

## Itens confirmados pelo revisor

- janela 1997–2015 e tratamento em 2009;
- especificação preferida sem covariáveis;
- seed `20260520`, 20.000 replicações na preferida e 5.000 nas comparações;
- common random numbers entre comparações;
- donor pool com Singapura e sem Malta;
- reconstrução 2004–2008, exclusão de serviços e fluxos domésticos e
  mapeamento de commodities;
- Pink Sheet nominal com base 2007;
- fórmulas e schemas dos 12 CSVs, da Tabela 5 e das três figuras;
- outputs antigos usados apenas como referências;
- ausência de promoção antecipada.

Correção exigida antes de nova revisão: normalizar os tipos e a semântica CSV
no comparador, reprovar infinitos, fazer um único scan do bruto, limitar BLAS e
tornar os cálculos longos retomáveis.
