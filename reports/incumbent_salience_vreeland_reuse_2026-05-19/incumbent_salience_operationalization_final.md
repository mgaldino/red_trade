# Operacionalização final: saliência do incumbente e variáveis LPV

Data: 2026-05-19  
Escopo: diagnóstico fora do `targets`; não edita `paper_v4.Rmd`.

## Decisão após Devil's Advocate

A operacionalização final mantém as três dummies solicitadas, mas rebaixa sua interpretação para heterogeneidade descritiva pré-tratamento. O parecer adversarial mostrou que `top_export_destination_{t0-1}` é temporalmente limpo, mas não basta para provar saliência política. Por isso, o CSV final agora inclui diagnósticos de share, margem, persistência do incumbente, incumbente modal no pré-período e flag de hubs comerciais.

## Unidade e timing

A unidade é o país tratado no painel cross-country. O treatment entry/onset (`t0`) é o primeiro ano em que a China entra validamente como maior destino das exportações, após um ano observado em que a China não era o principal destino. O incumbente deslocado é:

`displaced_partner_i = top_export_destination_{i,t0-1}`

Todas as variáveis de incumbente são fixas no país tratado e medidas antes de `t0`.

## Dummies principais

1. `displaced_us`: igual a 1 se `displaced_partner == "USA"`.
2. `displaced_g7`: igual a 1 se `displaced_partner` pertence a `{CAN, FRA, DEU, ITA, JPN, GBR, USA}`.
3. `displaced_regional_power`: igual a 1 se `displaced_partner` pertence à lista pré-especificada `strict_pre_specified_ri_ipe_2026_05_19`: `{USA, BRA, MEX, ARG, DEU, FRA, GBR, RUS, TUR, EGY, IRN, SAU, NGA, ZAF, IND, PAK, JPN, KOR, IDN, AUS}`.

Essas três dummies devem ser reportadas com contagens de países e lista de casos. A dummy `displaced_regional_power` não deve ser interpretada isoladamente como poder regional no sentido forte; ela mistura potências globais, G7, polos regionais e grandes potências externas. A interpretação substantiva exige a decomposição abaixo.

## Diagnósticos obrigatórios de validade

O arquivo `data/processed/diagnostics/incumbent_salience_moderators_2026-05-19.csv` inclui as seguintes variáveis adicionais:

- `displaced_export_share_t0_minus_1`: share das exportações do país tratado enviado ao incumbente em `t0 - 1`.
- `china_export_share_t0_minus_1`: share das exportações enviado à China em `t0 - 1`.
- `export_share_margin_over_china_t0_minus_1`: diferença entre os dois shares em `t0 - 1`.
- `displaced_partner_top_years_pre5`: número de anos, de `t0 - 5` a `t0 - 1`, em que o incumbente de `t0 - 1` também foi o maior destino de exportações.
- `modal_top_partner_pre5`: principal destino modal no período `t0 - 5` a `t0 - 1`.
- `displaced_partner_modal_top_pre5`: igual a 1 se o incumbente de `t0 - 1` também é o principal destino modal do pré-período.
- `hub_entrepot_incumbent`: igual a 1 se o incumbente está em `{ARE, BEL, CHE, HKG, SGP}`.
- `displacement_salience_warning`: classifica casos como `hub_or_entrepot_incumbent`, `narrow_export_share_margin`, `weak_pre_entry_persistence` ou `none`.

Esses diagnósticos respondem à crítica de que a regra de ranking poderia capturar uma troca comercial estreita, volátil ou mediada por hubs. A especificação principal pode usar as dummies solicitadas, mas a interpretação deve discutir quantos casos têm aviso de saliência.

## Potência regional

A revisão de literatura recomenda uma lista pré-especificada por região, porque a literatura de RI trata potência regional como posição relacional, reconhecida e situada regionalmente, não apenas como tamanho econômico. A lista operacional preservada para diagnóstico é:

- Américas: `USA`, `BRA`, `MEX`, `ARG`
- Europa/Eurásia: `DEU`, `FRA`, `GBR`, `RUS`, `TUR`
- Oriente Médio/Norte da África: `EGY`, `IRN`, `SAU`
- África Subsaariana: `NGA`, `ZAF`
- Sul da Ásia: `IND`, `PAK`
- Leste/Sudeste Asiático e Oceania: `JPN`, `KOR`, `IDN`, `AUS`

Para evitar sobreinterpretação, `displaced_regional_power_same_macroregion` deve ser tratado como diagnóstico central de validade conceitual: se o mecanismo é deslocamento de influência regional, casos em que a potência deslocada não está na mesma macrorregião têm interpretação mais fraca.

## Variáveis Liu, Pang & Vreeland (2026)

A variável reutilizável mais limpa é `partner_level_lag1` no arquivo `BSAupdate.RData`. No meu painel, ela foi cruzada como:

`pre_entry_partner_level_i = partner_level_lag1` na linha LPV de `year == t0`

Isso equivale a medir o nível de parceria diplomática com a China em `t0 - 1`. A versão binária é `pre_entry_high_level_partner = pre_entry_partner_level >= 4`, usando o limiar dos autores para comprehensive cooperation partnership or above.

Recomendação final:

- Usar `pre_entry_partner_level` ou `pre_entry_high_level_partner` apenas como robustez/descritivo.
- Não usar `swap_dummy`, `signdate` ou BSA como moderadores; eles são o tratamento de Liu, Pang & Vreeland.
- Não usar `ever BRI MoU`.
- Se BRI entrar, usar apenas `pre_entry_bri_mou = bri_mou_year < t0`, com interpretação descritiva porque há poucos casos pré-entrada.

## Implicação para os modelos diagnósticos

Os modelos com 500 bootstraps devem ser apresentados como diagnóstico preliminar. Eles testam heterogeneidade pré-tratamento e não fornecem uma nova identificação causal independente. O relatório deve incluir:

- ATT geral sem moderador.
- ATT por grupo para `displaced_us`.
- ATT por grupo para `displaced_g7`.
- ATT por grupo para `displaced_regional_power`.
- ATT por grupo para `pre_entry_high_level_partner`, como robustez LPV.
- Contagens de países tratados por célula.
- Avisos sobre hubs, margens estreitas e baixa persistência.

Próximos testes antes de incorporação no paper: event studies por subgrupo, testes de leads, leave-one-country-out e especificações excluindo hubs/entrepôts.
