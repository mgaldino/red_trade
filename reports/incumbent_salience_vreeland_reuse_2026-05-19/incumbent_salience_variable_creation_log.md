# Incumbent salience variable creation log

- Data de execução: 2026-05-19
- Timestamp: 2026-05-19 23:14:02 -03
- Script: `scripts/diagnostics/create_incumbent_salience_variables.R`
- CSV: `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/data/processed/diagnostics/incumbent_salience_moderators_2026-05-19.csv`

## Fontes

- Objetos lidos via `targets::tar_read()`: `trade_data`, `unga_data`.
- Painel reconstruído com `build_china_top_partner_panel(trade_data, unga_data, min_year = 1990, min_entry_year = 2000)`.
- O pipeline `targets` não foi executado.

## Regras de construção

- `t0`: primeiro ano em que `china_top == 1` para cada país tratado.
- `displaced_partner`: principal destino de exportações no ano `t0 - 1`.
- `displaced_us`: incumbente deslocado igual a `USA`.
- `displaced_g7`: incumbente em `CAN, FRA, DEU, ITA, JPN, GBR, USA`.
- `displaced_regional_power`: incumbente em lista pré-especificada `strict_pre_specified_ri_ipe_2026_05_19`.
- `hub_entrepot_incumbent`: incumbente em lista diagnóstica de hubs/entrepôts observados nesta amostra (`ARE`, `BEL`, `CHE`, `HKG`, `SGP`).
- `export_share_margin_over_china_t0_minus_1`: share do incumbente menos share da China em `t0 - 1`.
- `displaced_partner_top_years_pre5`: número de anos, de `t0 - 5` a `t0 - 1`, em que o incumbente de `t0 - 1` também liderava as exportações.

## Totais

- Países tratados: 59
- Primeiro `t0`: 2000
- Último `t0`: 2021

## Contagens das dummies

### displaced_us
- FALSE: 47
- TRUE: 12

### displaced_g7
- FALSE: 35
- TRUE: 24

### displaced_regional_power
- FALSE: 21
- TRUE: 38

### displaced_regional_power_same_macroregion
- FALSE: 46
- TRUE: 13

## Diagnósticos de saliência do incumbente

### Avisos de saliência
- hub_or_entrepot_incumbent:  9
- narrow_export_share_margin: 17
- none: 25
- weak_pre_entry_persistence:  8

### Casos com hub/entrepôt como incumbente
- COD (Congo - Kinshasa), t0 = 2008: BEL (Belgium)
- MYS (Malaysia), t0 = 2009: SGP (Singapore)
- TZA (Tanzania), t0 = 2011: CHE (Switzerland)
- ZWE (Zimbabwe), t0 = 2011: ARE (United Arab Emirates)
- SLE (Sierra Leone), t0 = 2012: BEL (Belgium)
- ZMB (Zambia), t0 = 2012: CHE (Switzerland)
- CAF (Central African Republic), t0 = 2013: BEL (Belgium)
- SGP (Singapore), t0 = 2013: HKG (Hong Kong SAR China)
- GIN (Guinea), t0 = 2019: ARE (United Arab Emirates)

- Mediana da margem incumbente-China em `t0 - 1`: 0.0349
- Mediana de anos em que o incumbente liderava no pré-período de cinco anos: 4

## Incumbentes deslocados

- USA (United States): 12
- JPN (Japan):  7
- RUS (Russia):  5
- IND (India):  4
- BEL (Belgium):  3
- THA (Thailand):  3
- ARE (United Arab Emirates):  2
- CHE (Switzerland):  2
- DEU (Germany):  2
- KOR (South Korea):  2
- ZAF (South Africa):  2
- AUS (Australia):  1
- BFA (Burkina Faso):  1
- BRA (Brazil):  1
- CAN (Canada):  1
- COG (Congo - Brazzaville):  1
- ESP (Spain):  1
- GBR (United Kingdom):  1
- GHA (Ghana):  1
- HKG (Hong Kong SAR China):  1
- ITA (Italy):  1
- MYS (Malaysia):  1
- SAU (Saudi Arabia):  1
- SEN (Senegal):  1
- SGP (Singapore):  1
- UKR (Ukraine):  1

## Validações lógicas

- Cada país tratado tem incumbente observado em `t0 - 1`: PASS — missing = 0
- Nenhum incumbente deslocado é a China: PASS — CHN = 0
- `t0` respeita `min_entry_year`: PASS — min(t0) = 2000
- Há uma linha por país tratado: PASS — linhas = 59; países únicos = 59
- `displaced_us` é consistente com `displaced_partner == USA`: PASS
- `displaced_g7` é consistente com a lista do G7: PASS
- `displaced_regional_power` é consistente com a lista pré-especificada: PASS
- Shares de exportação em `t0 - 1` estão entre 0 e 1: PASS
- Janela de persistência usa no máximo os cinco anos pré-entrada: PASS

