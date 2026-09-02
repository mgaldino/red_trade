# Contrato de migração — SDiD Brasil e commodity/Tabela 5

## Escopo

Este bloco migra para o grafo candidato:

- os 12 CSVs de `paper_v4_brazil_sdid_no_covariates` lidos pelo manuscrito;
- as figuras de fit principal, pesos e fit da América Latina;
- a exposição predeterminada a commodities;
- os índices anuais do Pink Sheet;
- as seis linhas da Tabela 5.

O script externo e seus outputs permanecem intactos como baseline até a promoção.

## Insumos permitidos

- targets analíticos já existentes: `synth_data`,
  `synth_fit_no_time_varying_covariates`,
  `se_synth_no_time_varying_covariates`, `goal3_brazil_rank_volume_data`,
  `trade_data_ranked` e `trade_data_cleaned`;
- `raw data/ITPDE_R03.csv`, já declarado como file target;
- `data/raw/commodity_prices/world_bank_pink_sheet/CMO-Historical-Data-Annual_2026-07-11.xlsx`,
  a ser declarado como file target.

Não são insumos analíticos permitidos:

- CSVs em `data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/`;
- os dois CSVs derivados em
  `data/processed/diagnostics/brazil_sdid_predetermined_commodity_controls/`;
- CSVs em `data/processed/diagnostics/brazil_sdid_commodity_no_covariates/`;
- figuras preexistentes em `quality_reports/`.

Esses arquivos serão usados apenas na etapa de comparação.

## Construção candidata

1. Reusar a implementação canônica de placebo em
   `scripts/diagnostics/sdid_placebo_helpers.R` como biblioteca pura.
2. Construir a exposição 2004–2008 diretamente do ITPD-E, excluindo serviços e
   fluxos domésticos.
3. Construir os índices e log-variações anuais diretamente da planilha bruta do
   Pink Sheet, com 2007 como base.
4. Montar o painel de interações da Tabela 5 dentro do grafo.
5. Separar targets caros — SEs placebo e distribuições por reatribuição — das
   transformações determinísticas.
6. Produzir tabelas como objetos e materializá-las por file targets.
7. Produzir cada figura por file target a partir do fit ou dos pesos que a
   determinam.
8. Manter nomes candidatos distintos dos nomes de produção até a adjudicação.

## Invariantes

- Janela principal: 1997–2015.
- Entrada de tratamento do Brasil: 2009.
- Especificação preferida: sem covariáveis.
- Seed de placebo: `20260520`.
- SE preferida: 20.000 replicações.
- SEs das cinco comparações da Tabela 5: 5.000 replicações.
- Mesmos draws entre as comparações da Tabela 5.
- Donor pool vigente inclui Singapura e exclui Malta.
- Pesos somam 1 com tolerância `1e-10`.
- Exposição commodity: média anual 2004–2008, denominador de bens, com
  Agricultura e Mining and Energy como primários.
- Domestic flows e Services não entram no denominador de bens exportados.
- Nenhum output do paper pode ser marcado como smoke test.

## Baseline numérico obrigatório

### Especificação preferida

- ATT: `-0.27277140758306007`;
- SE: `0.13060794328219072`;
- IC 95%: `[-0.52875827251100394, -0.016784542655116197]`;
- p normal bilateral: `0.036755019814799388`;
- rank direcional: `3/96`, p `0.03125`;
- rank absoluto: `7/96`, p `0.07291666666666667`.

### Tabela 5

| Especificação | ATT | SE |
|---|---:|---:|
| Current covariates | -0.26826686837286001 | 0.14337141102872067 |
| Preferred: no covariates | -0.27277140758306007 | 0.13060794328219072 |
| Primary share x 2008–2009 | -0.28476634058333045 | 0.12856145245115758 |
| Agriculture/mining x 2008–2009 | -0.28440837500700328 | 0.12817764954496649 |
| Price exposure x 2008–2009 | -0.27697879146366394 | 0.13043898372211218 |
| Prior China share x 2008–2009 | -0.28436140745360544 | 0.13027823389726326 |

## Gates antes de computação cara

- parse e manifesto estático;
- schemas, chaves e unicidade;
- cobertura 2004–2008 por país;
- shares finitos e dentro de `[0, 1]`;
- base 2007 dos log-índices igual a zero;
- painel SDiD balanceado, sem missing nas variáveis de cada especificação;
- comparação determinística da exposição e dos preços candidatos com os CSVs
  antigos a `1e-12`;
- revisão `review-r` independente com `PASS` sem ressalvas.

Não executar `tar_make()`, placebo, bootstrap ou modelos sem autorização
específica posterior.
