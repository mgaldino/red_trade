# Codificação alternativa do ano em que a China se torna parceiro comercial #1

Data de execução: 2026-05-20

## Resumo executivo

Este diagnóstico reconstrói rankings bilaterais para 193 países do painel, fora do pipeline `targets`, combinando exportações de bens do ITPD-E com serviços totais bilaterais do BaTIS BPM6. Foram produzidas três métricas: exportações de bens, exportações de bens + serviços, e comércio two-way de bens + serviços.

Austrália: o onset público é 2007. A métrica goods+services two-way coloca a China em rank 1 em 2007, contra 2009 na métrica de exportações de bens. A checagem auxiliar de corrente de bens também aponta 2007.

Brasil: o onset público é 2009. A métrica goods+services two-way coloca a China em rank 1 em 2017, e a métrica de exportações de bens em 2009. A checagem auxiliar de corrente de bens aponta 2009, consistente com a métrica pública brasileira.

Ao todo, 74 países têm algum ano de China #1 alterado quando serviços e/ou comércio two-way entram na codificação. A recomendação é usar `goods_services_two_way_rank` como robustez para linguagem pública de comércio total de bens e serviços, mantendo `goods_exports_rank` como métrica principal se o argumento substantivo continuar centrado em export-destination status; para fontes que usam corrente de bens, use a checagem auxiliar de bens two-way.

## Fontes e limitações

- BaTIS BPM6: página oficial da OMC de bulk download, arquivo `OECD-WTO_BATIS_data_BPM6-1.zip`, código e metodologia acessados em 2026-05-20. A página informa cobertura 2005-2024 e mais de 200 reporters/partners. O diagnóstico usa apenas BPM6 e não combina BPM5, porque a própria OMC alerta que as edições seguem padrões diferentes e geram problemas de comparabilidade.
- ITPD-E: arquivo local `raw data/ITPDE_R03.csv`. A métrica de bens filtra `broad_sector` para Agriculture, Mining and Energy, e Manufacturing, excluindo Services.
- Sobreposição temporal: como o ITPD-E local vai até 2022, as métricas combinadas são interpretadas em 2005-2022. O ano 2005 é tratado como possível censura à esquerda; o relatório informa o primeiro ano observado a partir de 2005, não um onset pré-2005 verdadeiro.
- Serviços: usa `Balanced_value` do BaTIS para obter matriz bilateral completa e reconciliada. Isso é apropriado para robustez de ranking, mas incorpora estimativas e ajustes da OMC/OCDE, não apenas valores reportados diretamente.
- Fontes públicas manuais: as fontes brasileiras foram preservadas em `data/raw/public_partner_onsets/`. A preservação local falhou para aus_dfat_composition_trade_2007; a URL, a data de acesso e a paráfrase da evidência permanecem documentadas no CSV manual e em `SOURCES.yaml`.

## Metodologia

1. Agreguei ITPD-E por país exportador, parceiro importador e ano, mantendo apenas setores de bens.
2. Calculei importações de bens do país como exportações do parceiro para o país no ITPD-E.
3. Extraí BaTIS BPM6 apenas para item `S` (Total services), distinguindo fluxos de exportação e importação.
4. Converti códigos BaTIS de economia para ISO-3 antes do join com ITPD-E, com mapeamentos manuais para Kosovo, Palestina, Antilhas Holandesas e Sérvia-Montenegro.
5. Excluí parceiros agregados/grupos identificados nos códigos BaTIS (`WL`, `EU`, `GEU`, `ROW` e demais códigos com tipo `g`) e o código ITPD-E `FRE` (`Free Zones`) antes do ranking.
6. Ranqueei apenas parceiros com valor positivo em cada país-ano-métrica.

## Tabela 1. Casos principais

|iso3c |country_name | goods_exports| goods_services_exports| goods_services_two_way| goods_two_way_supplemental| publicly_reported_onset|public_apparent_metric                                   |
|:-----|:------------|-------------:|----------------------:|----------------------:|--------------------------:|-----------------------:|:--------------------------------------------------------|
|AUS   |Australia    |          2009|                   2009|                   2007|                       2007|                    2007|Two-way trade in goods and services                      |
|BRA   |Brazil       |          2009|                   2009|                   2017|                       2009|                    2009|Two-way merchandise trade/current, apparently goods only |

## Tabela 2. Países cujo onset muda em relação a exportações de bens

|iso3c |country_name             | goods_exports| goods_services_exports| goods_services_two_way|onset_status_goods_exports_rank      |onset_status_goods_services_exports_rank |onset_status_goods_services_two_way_rank |
|:-----|:------------------------|-------------:|----------------------:|----------------------:|:------------------------------------|:----------------------------------------|:----------------------------------------|
|AGO   |Angola                   |          2007|                   2007|                   2008|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|ARE   |United Arab Emirates     |            NA|                     NA|                   2017|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|ARM   |Armenia                  |          2015|                   2020|                     NA|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |never_china_rank1_in_observed_window     |
|AUS   |Australia                |          2009|                   2009|                   2007|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|BDI   |Burundi                  |            NA|                     NA|                   2017|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|BEN   |Benin                    |          2008|                   2005|                   2012|observed_first_rank1_after_2005      |left_censored_china_rank1_in_2005        |observed_first_rank1_after_2005          |
|BFA   |Burkina Faso             |          2005|                   2005|                     NA|left_censored_china_rank1_in_2005    |left_censored_china_rank1_in_2005        |never_china_rank1_in_observed_window     |
|BGD   |Bangladesh               |            NA|                     NA|                   2010|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|BLR   |Belarus                  |            NA|                     NA|                   2022|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|BRA   |Brazil                   |          2009|                   2009|                   2017|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|BRN   |Brunei                   |            NA|                     NA|                   2020|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|CAF   |Central African Republic |          2013|                   2013|                   2020|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|CHL   |Chile                    |          2007|                   2008|                   2009|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|CIV   |Côte d'Ivoire            |            NA|                     NA|                   2022|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|CUB   |Cuba                     |          2005|                   2006|                   2006|left_censored_china_rank1_in_2005    |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|DEU   |Germany                  |            NA|                     NA|                   2021|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|DJI   |Djibouti                 |            NA|                     NA|                   2010|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|EGY   |Egypt                    |            NA|                     NA|                   2015|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|ERI   |Eritrea                  |          2014|                   2014|                   2013|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|ETH   |Ethiopia                 |          2009|                   2014|                   2007|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|GAB   |Gabon                    |          2017|                   2015|                   2017|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|GHA   |Ghana                    |          2019|                   2019|                   2013|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|GIN   |Guinea                   |          2019|                   2019|                   2010|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|GMB   |Gambia                   |          2011|                   2012|                   2012|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|IDN   |Indonesia                |          2013|                   2013|                   2011|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|IRN   |Iran                     |          2007|                   2007|                   2006|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|IRQ   |Iraq                     |          2014|                   2014|                   2013|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|JPN   |Japan                    |          2008|                   2009|                   2008|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|KAZ   |Kazakhstan               |          2007|                   2007|                   2010|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|KEN   |Kenya                    |            NA|                     NA|                   2011|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|KGZ   |Kyrgyzstan               |            NA|                     NA|                   2016|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|KHM   |Cambodia                 |            NA|                     NA|                   2014|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|KWT   |Kuwait                   |          2018|                   2018|                   2017|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |observed_first_rank1_after_2005          |
|LAO   |Laos                     |          2014|                   2014|                     NA|observed_first_rank1_after_2005      |observed_first_rank1_after_2005          |never_china_rank1_in_observed_window     |
|LBN   |Lebanon                  |            NA|                     NA|                   2022|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|LBR   |Liberia                  |          2012|                     NA|                   2019|observed_first_rank1_after_2005      |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|LBY   |Libya                    |            NA|                     NA|                   2019|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|LKA   |Sri Lanka                |            NA|                     NA|                   2020|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|MDG   |Madagascar               |            NA|                     NA|                   2022|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |
|MDV   |Maldives                 |            NA|                     NA|                   2019|never_china_rank1_in_observed_window |never_china_rank1_in_observed_window     |observed_first_rank1_after_2005          |

## Tabela 3. Onsets por métrica

|iso3c |country_name             | goods_exports| goods_services_exports| goods_services_two_way| publicly_reported_onset|any_change_from_goods_exports |
|:-----|:------------------------|-------------:|----------------------:|----------------------:|-----------------------:|:-----------------------------|
|AGO   |Angola                   |          2007|                   2007|                   2008|                      NA|TRUE                          |
|ARE   |United Arab Emirates     |            NA|                     NA|                   2017|                      NA|TRUE                          |
|ARM   |Armenia                  |          2015|                   2020|                     NA|                      NA|TRUE                          |
|AUS   |Australia                |          2009|                   2009|                   2007|                    2007|TRUE                          |
|BDI   |Burundi                  |            NA|                     NA|                   2017|                      NA|TRUE                          |
|BEN   |Benin                    |          2008|                   2005|                   2012|                      NA|TRUE                          |
|BFA   |Burkina Faso             |          2005|                   2005|                     NA|                      NA|TRUE                          |
|BGD   |Bangladesh               |            NA|                     NA|                   2010|                      NA|TRUE                          |
|BLR   |Belarus                  |            NA|                     NA|                   2022|                      NA|TRUE                          |
|BRA   |Brazil                   |          2009|                   2009|                   2017|                    2009|TRUE                          |
|BRN   |Brunei                   |            NA|                     NA|                   2020|                      NA|TRUE                          |
|CAF   |Central African Republic |          2013|                   2013|                   2020|                      NA|TRUE                          |
|CHL   |Chile                    |          2007|                   2008|                   2009|                      NA|TRUE                          |
|CIV   |Côte d'Ivoire            |            NA|                     NA|                   2022|                      NA|TRUE                          |
|CMR   |Cameroon                 |          2012|                   2012|                   2012|                      NA|FALSE                         |
|COD   |Congo - Kinshasa         |          2008|                   2008|                   2008|                      NA|FALSE                         |
|COG   |Congo - Brazzaville      |          2005|                   2005|                   2005|                      NA|FALSE                         |
|CUB   |Cuba                     |          2005|                   2006|                   2006|                      NA|TRUE                          |
|DEU   |Germany                  |            NA|                     NA|                   2021|                      NA|TRUE                          |
|DJI   |Djibouti                 |            NA|                     NA|                   2010|                      NA|TRUE                          |
|EGY   |Egypt                    |            NA|                     NA|                   2015|                      NA|TRUE                          |
|ERI   |Eritrea                  |          2014|                   2014|                   2013|                      NA|TRUE                          |
|ETH   |Ethiopia                 |          2009|                   2014|                   2007|                      NA|TRUE                          |
|GAB   |Gabon                    |          2017|                   2015|                   2017|                      NA|TRUE                          |
|GHA   |Ghana                    |          2019|                   2019|                   2013|                      NA|TRUE                          |
|GIN   |Guinea                   |          2019|                   2019|                   2010|                      NA|TRUE                          |
|GMB   |Gambia                   |          2011|                   2012|                   2012|                      NA|TRUE                          |
|GNQ   |Equatorial Guinea        |          2006|                   2006|                   2006|                      NA|FALSE                         |
|IDN   |Indonesia                |          2013|                   2013|                   2011|                      NA|TRUE                          |
|IRN   |Iran                     |          2007|                   2007|                   2006|                      NA|TRUE                          |
|IRQ   |Iraq                     |          2014|                   2014|                   2013|                      NA|TRUE                          |
|JPN   |Japan                    |          2008|                   2009|                   2008|                      NA|TRUE                          |
|KAZ   |Kazakhstan               |          2007|                   2007|                   2010|                      NA|TRUE                          |
|KEN   |Kenya                    |            NA|                     NA|                   2011|                      NA|TRUE                          |
|KGZ   |Kyrgyzstan               |            NA|                     NA|                   2016|                      NA|TRUE                          |
|KHM   |Cambodia                 |            NA|                     NA|                   2014|                      NA|TRUE                          |
|KOR   |South Korea              |          2005|                   2005|                   2005|                      NA|FALSE                         |
|KWT   |Kuwait                   |          2018|                   2018|                   2017|                      NA|TRUE                          |
|LAO   |Laos                     |          2014|                   2014|                     NA|                      NA|TRUE                          |
|LBN   |Lebanon                  |            NA|                     NA|                   2022|                      NA|TRUE                          |
|LBR   |Liberia                  |          2012|                     NA|                   2019|                      NA|TRUE                          |
|LBY   |Libya                    |            NA|                     NA|                   2019|                      NA|TRUE                          |
|LKA   |Sri Lanka                |            NA|                     NA|                   2020|                      NA|TRUE                          |
|MDG   |Madagascar               |            NA|                     NA|                   2022|                      NA|TRUE                          |
|MDV   |Maldives                 |            NA|                     NA|                   2019|                      NA|TRUE                          |
|MHL   |Marshall Islands         |            NA|                     NA|                   2018|                      NA|TRUE                          |
|MLI   |Mali                     |          2006|                   2006|                     NA|                      NA|TRUE                          |
|MLT   |Malta                    |          2011|                     NA|                     NA|                      NA|TRUE                          |
|MMR   |Myanmar (Burma)          |          2014|                   2014|                   2011|                      NA|TRUE                          |
|MNG   |Mongolia                 |          2005|                   2005|                   2005|                      NA|FALSE                         |
|MOZ   |Mozambique               |          2014|                   2014|                     NA|                      NA|TRUE                          |
|MRT   |Mauritania               |          2006|                   2006|                   2006|                      NA|FALSE                         |
|MWI   |Malawi                   |            NA|                   2014|                   2019|                      NA|TRUE                          |
|MYS   |Malaysia                 |          2009|                   2009|                   2009|                      NA|FALSE                         |
|NER   |Niger                    |            NA|                     NA|                   2010|                      NA|TRUE                          |
|NGA   |Nigeria                  |            NA|                     NA|                   2020|                      NA|TRUE                          |
|NZL   |New Zealand              |          2013|                   2014|                   2017|                      NA|TRUE                          |
|OMN   |Oman                     |          2005|                   2005|                   2005|                      NA|FALSE                         |
|PAK   |Pakistan                 |            NA|                     NA|                   2014|                      NA|TRUE                          |
|PAN   |Panama                   |          2021|                   2021|                     NA|                      NA|TRUE                          |
|PER   |Peru                     |          2010|                   2010|                   2016|                      NA|TRUE                          |
|PHL   |Philippines              |          2005|                   2005|                   2007|                      NA|TRUE                          |
|PLW   |Palau                    |            NA|                     NA|                   2020|                      NA|TRUE                          |
|PNG   |Papua New Guinea         |          2018|                   2018|                   2021|                      NA|TRUE                          |
|PRK   |North Korea              |          2005|                   2005|                   2005|                      NA|FALSE                         |
|QAT   |Qatar                    |          2021|                   2021|                   2020|                      NA|TRUE                          |
|RUS   |Russia                   |          2012|                   2012|                   2010|                      NA|TRUE                          |
|RWA   |Rwanda                   |            NA|                     NA|                   2013|                      NA|TRUE                          |
|SAU   |Saudi Arabia             |          2013|                   2013|                   2015|                      NA|TRUE                          |
|SDN   |Sudan                    |          2005|                   2005|                   2005|                      NA|FALSE                         |
|SGP   |Singapore                |            NA|                   2005|                   2013|                      NA|TRUE                          |
|SLB   |Solomon Islands          |          2005|                   2005|                   2005|                      NA|FALSE                         |
|SLE   |Sierra Leone             |          2012|                   2012|                   2011|                      NA|TRUE                          |
|SSD   |South Sudan              |          2012|                   2012|                   2012|                      NA|FALSE                         |
|SYR   |Syria                    |            NA|                     NA|                   2012|                      NA|TRUE                          |
|TCD   |Chad                     |          2019|                   2019|                   2019|                      NA|FALSE                         |
|TGO   |Togo                     |            NA|                     NA|                   2006|                      NA|TRUE                          |
|THA   |Thailand                 |          2008|                   2008|                   2011|                      NA|TRUE                          |
|TJK   |Tajikistan               |            NA|                     NA|                   2009|                      NA|TRUE                          |
|TKM   |Turkmenistan             |          2010|                   2010|                   2010|                      NA|FALSE                         |
|TLS   |Timor-Leste              |          2021|                   2022|                     NA|                      NA|TRUE                          |
|TUV   |Tuvalu                   |            NA|                     NA|                   2008|                      NA|TRUE                          |
|TZA   |Tanzania                 |          2011|                   2011|                   2010|                      NA|TRUE                          |
|UKR   |Ukraine                  |          2020|                   2020|                   2020|                      NA|FALSE                         |
|URY   |Uruguay                  |          2013|                   2013|                   2013|                      NA|FALSE                         |
|USA   |United States            |            NA|                     NA|                   2014|                      NA|TRUE                          |
|UZB   |Uzbekistan               |          2013|                   2013|                   2015|                      NA|TRUE                          |
|VEN   |Venezuela                |          2021|                   2021|                   2019|                      NA|TRUE                          |
|VNM   |Vietnam                  |          2018|                   2018|                   2007|                      NA|TRUE                          |
|VUT   |Vanuatu                  |            NA|                     NA|                   2013|                      NA|TRUE                          |
|YEM   |Yemen                    |          2005|                   2005|                   2005|                      NA|FALSE                         |
|ZAF   |South Africa             |          2009|                   2009|                   2009|                      NA|FALSE                         |
|ZMB   |Zambia                   |          2012|                   2012|                   2012|                      NA|FALSE                         |
|ZWE   |Zimbabwe                 |          2011|                   2011|                     NA|                      NA|TRUE                          |

## Validações

- Países do painel: 193. Países-métrica sem nenhum ranking: 12. Ver `china_top_goods_services_missing_panel_countries_2026-05-20.csv`.
- Valores negativos/NA/zero: ver `china_top_goods_services_validation_summary_2026-05-20.csv`. Valores zero não entram no ranking; valores negativos são sinalizados.
- Integração BaTIS-ITPD-E: o script aborta se serviços não entrarem no join ou se casos-chave Austrália/Brasil com China, EUA e Japão não tiverem serviços. Ver `china_top_goods_services_service_join_key_checks_2026-05-20.csv`.
- Códigos sem mapeamento ISO ou excluídos como agregados: ver `china_top_goods_services_unmapped_or_excluded_codes_2026-05-20.csv`.
- Rankings anuais de China, Estados Unidos e Japão para Austrália e Brasil: ver `china_top_goods_services_focus_rank_diagnostics_aus_bra_2026-05-20.csv`. A checagem auxiliar de corrente de bens está em `china_top_goods_two_way_public_metric_check_aus_bra_2026-05-20.csv`.

## Implicações para o paper

- Se a narrativa empírica se refere a `largest export destination`, a métrica principal de exportações de bens continua conceitualmente limpa e alinhada ao mecanismo de status por destino exportador.
- Se a prosa usa `largest trading partner` sem qualificação, a robustez two-way bens + serviços é necessária, mas ela não replica automaticamente fontes que reportam apenas corrente de comércio de bens.
- A Austrália é o caso de maior risco de validade de medida: fontes australianas usam comércio two-way de bens e serviços para datar a virada em 2007.
- O Brasil exige qualificação: a fonte pública de 2009 parece usar corrente de comércio de bens; nessa checagem auxiliar o onset é 2009, mas na métrica two-way bens + serviços o onset passa a 2017 porque serviços com os Estados Unidos continuam grandes por mais tempo.

## Recomendação

Manter a codificação principal como `goods_exports_rank` se o estimando do paper for status de destino de exportações. Adicionar `goods_services_two_way_rank` como robustez para fontes que reportam `largest trading partner` em termos de comércio total de bens e serviços, mas interpretar Brasil com a checagem auxiliar de corrente de bens. No texto, evitar alternar sem qualificação entre `largest export destination`, `largest merchandise trading partner` e `largest goods-and-services trading partner`.
