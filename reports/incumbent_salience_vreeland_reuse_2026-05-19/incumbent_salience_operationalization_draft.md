# Operacionalização preliminar: moderadores pré-tratamento e saliência do incumbente

Data: 2026-05-19  
Escopo: diagnóstico fora do `targets`, sem edição de `paper_v4.Rmd`.

## Unidade e timing

A unidade principal é país tratado no painel cross-country. O treatment entry/onset (`t0`) é o primeiro ano em que a China entra validamente como maior destino das exportações, após um ano observado em que a China não era o principal destino. O incumbente deslocado é:

`displaced_partner_i = top_export_destination_{i,t0-1}`

Todas as variáveis de saliência do incumbente são fixadas no nível do país tratado e medidas no ano imediatamente anterior ao treatment entry/onset.

## Dummies de incumbente deslocado

1. `displaced_us`: igual a 1 se `displaced_partner == "USA"`.
2. `displaced_g7`: igual a 1 se `displaced_partner` pertence a `{CAN, FRA, DEU, ITA, JPN, GBR, USA}`.
3. `displaced_regional_power`: igual a 1 se `displaced_partner` pertence à lista pré-especificada `strict_pre_specified_ri_ipe_2026_05_19`: `{USA, BRA, MEX, ARG, DEU, FRA, GBR, RUS, TUR, EGY, IRN, SAU, NGA, ZAF, IND, PAK, JPN, KOR, IDN, AUS}`.

Coluna auxiliar: `displaced_regional_power_same_macroregion`, igual a 1 se `displaced_regional_power == 1` e a macrorregião do incumbente deslocado coincide com a macrorregião do país tratado segundo `countrycode`.

## Variáveis de Liu, Pang & Vreeland (2026)

Arquivos inspecionados:

- `BSAupdate.RData`, objeto `datasave`, painel país-ano 1992-2021, 5.755 linhas, 195 COW codes.
- `BRI_2020.tab`, evento país-ano de assinatura de MoU BRI, 138 linhas, anos 2014-2020.
- `Data_SWAPNet_panel_202207.xlsx`, rede BSA anual 2008-2020 e aba `World`.
- `ITT_confusion.csv`, classificação de 37 casos BSA.

Variáveis candidatas:

- `partner_level`: escala ordinal de parceria diplomática com a China, 0-11.
- `partner_level_lag1`: valor defasado em um ano.
- `high_level_partner`: derivada como `partner_level >= 4`, seguindo o código dos autores para “comprehensive cooperation partnership or above”.
- `pre_entry_partner_level`: para o meu painel, usar `partner_level_lag1` na linha Vreeland do ano `t0`, equivalente a `partner_level_{t0-1}`.
- `pre_entry_high_level_partner`: `pre_entry_partner_level >= 4`.
- `pre_entry_bri_mou`: `bri_mou_year < t0`.

## Recomendação preliminar

Usar `pre_entry_partner_level` ou `pre_entry_high_level_partner` apenas como robustness diagnóstica, não como moderador principal nesta rodada. A variável está disponível antes do treatment entry/onset para todos os 59 tratados identificados no painel cross-country, mas mede proximidade política com a China e pode estar conceitualmente perto do mecanismo que o paper quer explicar.

Não usar `ever BRI MoU`. No cruzamento preliminar, 50 dos 59 tratados têm algum MoU BRI observado, mas apenas 10 assinaram antes de `t0`; 40 assinaram depois do treatment entry/onset. A versão admissível é somente `pre_entry_bri_mou = bri_mou_year < t0`, e deve ser tratada como robustness descritiva por baixa variação e forte risco de pós-tratamento se mal codificada.

## Validações lógicas exigidas

- `t0` deve ser maior que o ano usado para `displaced_partner`.
- `displaced_partner` não deve ser `CHN`.
- `pre_entry_partner_level` deve usar valor de `t0-1`, nunca valores contemporâneos ou posteriores.
- `pre_entry_bri_mou` deve usar estritamente `bri_mou_year < t0`; assinaturas no próprio `t0` não contam como pré-tratamento.
- Tabelas finais devem registrar contagens e casos missing.
