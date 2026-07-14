# Dicionário de dados: codificação alternativa de parceiro comercial China #1

Gerado em: 2026-05-20

## china_top_goods_services_country_year_partner_YYYY-MM-DD.csv

| Variável | Tipo | Descrição | Fonte | Unidade |
|---|---|---|---|---|
| iso3c | texto | País do painel, ISO-3 | painel do paper | - |
| country_name | texto | Nome do país | countrycode | - |
| year | inteiro | Ano | ITPD-E/BaTIS | ano |
| partner_iso3 | texto | Parceiro bilateral, ISO-3/código econômico | ITPD-E/BaTIS | - |
| partner_name | texto | Nome do parceiro | countrycode/BaTIS | - |
| goods_exports_musd | numérico | Exportações de bens do país para o parceiro | ITPD-E | milhões de USD correntes |
| goods_imports_musd | numérico | Importações de bens do país vindas do parceiro, calculadas como exportações do parceiro para o país | ITPD-E | milhões de USD correntes |
| services_exports_musd | numérico | Exportações de serviços totais do país para o parceiro | BaTIS BPM6, item S, balanced value | milhões de USD correntes |
| services_imports_musd | numérico | Importações de serviços totais do país vindas do parceiro | BaTIS BPM6, item S, balanced value | milhões de USD correntes |
| goods_two_way_musd | numérico | Exportações + importações de bens; diagnóstico auxiliar para fontes públicas de corrente de comércio | ITPD-E | milhões de USD correntes |
| goods_services_exports_musd | numérico | Bens exportados + serviços exportados | ITPD-E + BaTIS | milhões de USD correntes |
| goods_services_two_way_musd | numérico | Exportações + importações de bens e serviços | ITPD-E + BaTIS | milhões de USD correntes |

## china_top_goods_services_rank_long_YYYY-MM-DD.csv

| Variável | Tipo | Descrição |
|---|---|---|
| metric | texto | Métrica de ranking: goods_exports_rank, goods_services_exports_rank ou goods_services_two_way_rank |
| value_musd | numérico | Valor usado no ranking da métrica |
| partner_rank | inteiro | Ranking do parceiro dentro do país-ano-métrica; 1 é o maior parceiro com valor positivo |
| top_partner_iso3 | texto | Parceiro no rank 1 do país-ano-métrica |
| china_indicator_partner | lógico | Parceiro é a China |
| focus_partner | lógico | Parceiro é China, Estados Unidos ou Japão |

## china_top_goods_services_onsets_comparison_YYYY-MM-DD.csv

| Variável | Tipo | Descrição |
|---|---|---|
| first_china_rank1_year_ge2005_* | inteiro | Primeiro ano observado a partir de 2005 em que a China aparece no rank 1 para a métrica |
| onset_status_* | texto | Indica se o primeiro ano é observado depois de 2005, left-censored em 2005 ou nunca observado |
| publicly_reported_onset | inteiro | Ano reportado por fonte pública/governamental quando disponível |
| public_apparent_metric | texto | Métrica que a fonte parece usar |
| public_evidence_paraphrase | texto | Paráfrase curta da evidência usada na codificação manual |
| public_minus_* | inteiro | Diferença entre onset público e onset computado |
| any_change_from_goods_exports | lógico | Alguma métrica com serviços altera o onset em relação a exportações de bens |

## china_top_goods_two_way_public_metric_check_aus_bra_YYYY-MM-DD.csv

Ranking auxiliar de corrente de comércio de bens para Austrália e Brasil, usado apenas para confrontar fontes públicas que parecem reportar `exports + imports` de bens.
