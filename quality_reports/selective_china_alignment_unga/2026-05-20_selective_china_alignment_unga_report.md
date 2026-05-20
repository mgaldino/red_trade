# Selective China Alignment in UNGA Voting

Data: 2026-05-20

Execução: 2026-05-20 12:16:45 -03

Script: `scripts/diagnostics/diagnose_selective_china_alignment_unga.R`

Este relatório foi gerado por um script diagnóstico auditável. Ele lê targets existentes e o tarball bruto `data/raw/unvotes/unvotes_0.3.0.tar.gz`, não executa `targets::tar_make()`, não altera `_targets.R`, `_targets/`, `_targets.yaml`, e não sobrescreve dados brutos.

## Resposta curta

Classificação pela matriz pré-definida: **Diagnostic evidence compatible with selective HR China alignment, not standalone causal proof**.

The main text can make only a cautious diagnostic claim: Brazil's post-2009 UNGA movement is most consistent with selective adjustment in human-rights votes where China and the United States diverged. It should not say that Table 4/Figure 6 alone proves China-specific convergence.

O resultado country-year do Goal 6 já indicava que a distância à China cai, a distância aos EUA aumenta, e o contraste China-menos-EUA se move na direção esperada. O novo teste voto-a-voto é mais restritivo: ele pergunta se, em resoluções de direitos humanos nas quais China e Estados Unidos votaram de forma diferente, o Brasil ficou relativamente mais próximo da China do que países comparáveis do donor pool. Essa é a evidência necessária para separar alinhamento seletivo, afastamento genérico dos EUA e reposicionamento amplo.

## Tabela 1. O que já responde / o que ainda falta

| component | what_already_responds | what_still_missing | status |
| --- | --- | --- | --- |
| Goal 6 country-year outcome robustness | Shows that Brazil's SDiD estimate is negative for distance to China, positive for distance to the United States, and negative for China-minus-US distance; annual agreement outcomes have the same directional pattern. | Alternative outcomes mostly lack newly computed SEs and do not by themselves isolate China-US divergent votes or resolution-level donor comparisons. | Partly answered |
| Existing issue-area Brazil-China diagnostics | Shows descriptive post-2009 increase in identical Brazil-China voting, especially human rights; also documents agenda-composition risks. | Brazil-only pre/post shares do not compare Brazil with donor countries and do not separate convergence toward China from generic opposition to the United States. | Partly answered |
| Raw unvotes tarball | Preserved source allows reproducible country-resolution panel without overwriting raw data. | Needs new panel construction and explicit coding of valid votes, reference votes, and China-US divergent subsets. | Available |
| Donor-pool comparability | The SDiD donor pool and weights are recoverable from existing targets. | Needs audit for reference actors and donor countries with China-top treatment entries during 2005-2012. | New analysis required |

## Tabela 2. Auditoria de targets e arquivos existentes

| audit_type | name | exists | object_class | nrow | ncol | bytes_meta | bytes_file | read_error |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| target | synth_data | TRUE | tbl_df;tbl;data.frame | 1920 | 19 | 147115 |  |  |
| target | unga_data | TRUE | tbl_df;tbl;data.frame | 6318 | 10 | 183860 |  |  |
| target | synth_fit | TRUE | synthdid_estimate |  |  | 191667 |  |  |
| target | se_synth | TRUE | matrix;array |  |  | 80 |  |  |
| target | goal6_sdid_outcome_results | TRUE | tbl_df;tbl;data.frame | 5 | 11 | 731 |  |  |
| target | classified_events | TRUE | tbl_df;tbl;data.frame | 56 | 4 | 626 |  |  |
| target | treatment_events | TRUE | tbl_df;tbl;data.frame | 56 | 2 | 439 |  |  |
| target | china_top_panel | TRUE | data.frame | 6283 | 21 | 81316 |  |  |
| file | goal6_report | TRUE |  |  |  |  | 24482 |  |
| file | goal6_sdid_outcome_results_csv | TRUE |  |  |  |  | 2036 |  |
| file | processed_alignment_by_resolution | TRUE |  |  |  |  | 656513 |  |
| file | processed_alignment_by_issue_year | TRUE |  |  |  |  | 34681 |  |
| file | processed_similarity_by_resolution | TRUE |  |  |  |  | 51185 |  |

## Tabela 3. Matriz decisória definida antes da estimação

| interpretation_class | pre_estimation_rule | expected_pattern | editorial_action |
| --- | --- | --- | --- |
| China-specific alignment | Brazil gets closer to China after 2009 relative to comparable donor countries, especially in human-rights and China-US divergent votes, while non-human-rights controls and broad benchmarks do not show equivalent movement. | Negative Brazil x Post for distance to China and China-minus-US distance; positive for closer-to-China score; Brazil is directionally unusual in donor placebos; HR is stronger than non-HR; any benchmark counterexample must be geometrically independent of China. | Allow cautious claim of selective UNGA alignment toward China, with vote-level and placebo evidence as support. |
| Away-from-US movement | Brazil moves away from the United States, but China proximity is mechanical or indistinguishable from anti-Washington movement. | Distance to the United States rises and China-minus-US contrast improves, but effects concentrate only where China and USA oppose each other and are mirrored by generic closer-than-US outcomes without China-specific domains. | Frame as movement away from Washington, not direct China-specific accommodation. |
| Broad repositioning | Similar effects appear in non-human-rights controls, alternative benchmarks, or temporal placebos, suggesting a general Lula/post-2008 reorientation. | Effects are comparable in HR and non-HR, Brazil is not unusual in donor placebos, or valid independent benchmarks move similarly. Benchmarks that are already close to China in ideal-point space are geometric diagnostics, not independent counterexamples. | Narrow the claim to broad UNGA repositioning or remove China-specific language. |
| Inconclusive | Evidence is descriptive, underpowered, or lacks a comparable counterfactual. | Point estimates are unstable, not unusual in placebos, or sample restrictions are too thin. | Describe Table 4/Figure 6 as diagnostics only and avoid causal language about selectivity. |

A regra de interpretação não conclui apenas pela direção de um coeficiente. Para sustentar alinhamento seletivo toward China, o resultado precisa aparecer sobretudo em direitos humanos e em votos China-EUA divergentes, com comparação contra donor pool. Benchmarks alternativos só contam contra China-specificity se forem geometricamente independentes da China no pré-2009; caso contrário, são apenas diagnósticos da geometria do espaço ideal.

## Country-Year Outcome Robustness

## Tabela 4. Outcomes country-year paralelos

| outcome | label | evidence_tier | estimate | se_placebo | p_value | status_inferencial | expected_direction | donor_pool | interpretation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| abs_distance_china | Absolute Brazil-China ideal-point distance | Brazil SDiD reduced-form estimate with placebo SE | -0.264 | 0.123 | 0.032 | Placebo SE from existing target se_synth. | negative | Baseline Brazil SDiD donor pool | Brazil moves closer to China than its synthetic counterfactual. |
| relative_distance_china_minus_usa | China-minus-US ideal-point distance | alternative country-year SDiD robustness; point estimate only | -0.521 |  |  | Point estimate only; placebo SE not recomputed for exploratory outcome robustness. | negative | Baseline Brazil SDiD donor pool | Brazil becomes closer to China relative to the United States. |
| abs_distance_usa | Absolute ideal-point distance to the United States | secondary country-year SDiD diagnostic; point estimate only | 0.305 |  |  | Point estimate only; placebo SE not recomputed for exploratory outcome robustness. | positive | Baseline Brazil SDiD donor pool | Brazil moves farther from the United States than its synthetic counterfactual. |
| china_agree | Annual vote agreement with China | agenda-sensitive country-year diagnostic; point estimate only | 0.078 |  |  | Point estimate only; placebo SE not recomputed for exploratory outcome robustness. | positive | Baseline Brazil SDiD donor pool | Annual agreement with China rises, but this is agenda-sensitive. |
| china_minus_us_agree | Annual agreement with China minus agreement with the United States | agenda-sensitive country-year diagnostic; point estimate only | 0.066 |  |  | Point estimate only; placebo SE not recomputed for exploratory outcome robustness. | positive | Baseline Brazil SDiD donor pool | Annual agreement shifts toward China relative to the United States, but this is agenda-sensitive. |
| abs_distance_russia | Distance to Russia | geometric country-year benchmark; not used as placebo evidence | 0.325 |  |  | Point estimate only. Spatial diagnostics show this is a geometric benchmark, not an independent placebo for China-specificity. | diagnostic/no preferred direction | Baseline Brazil SDiD donor pool | Interpret only after checking pre-2009 spatial proximity to China; this is not an independent placebo by default. Estimate: 0.325 |
| abs_distance_india | Distance to India | geometric country-year benchmark; not used as placebo evidence | -0.296 |  |  | Point estimate only. Spatial diagnostics show this is a geometric benchmark, not an independent placebo for China-specificity. | diagnostic/no preferred direction | Baseline Brazil SDiD donor pool | Interpret only after checking pre-2009 spatial proximity to China; this is not an independent placebo by default. Estimate: -0.296 |
| abs_distance_brics_no_brazil | Distance to BRICS mean excluding Brazil | geometric country-year benchmark; not used as placebo evidence | -0.249 |  |  | Point estimate only. Spatial diagnostics show this is a geometric benchmark, not an independent placebo for China-specificity. | diagnostic/no preferred direction | Baseline Brazil SDiD donor pool | Interpret only after checking pre-2009 spatial proximity to China; this is not an independent placebo by default. Estimate: -0.249 |

Os benchmarks adicionais para Rússia, Índia e média BRICS sem Brasil usam o mesmo estimador SDiD para estimativas de ponto, mas não entram como placebos independentes de China-specificity. A razão é geométrica: se esses atores já estiverem próximos da China antes de 2009, aproximar-se da China pode reduzir mecanicamente a distância a eles. Por isso, a tabela abaixo diagnostica proximidade pré-2009 antes de qualquer interpretação substantiva.

## Tabela 4B. Diagnóstico espacial dos benchmarks country-year

| diagnostic_type | metric | value | sd_value | min_value | max_value | n_years | interpretation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pre-2009 reference-actor distance | China-India ideal-point distance | 0.236 |  | 0.236 | 0.236 | 4 | Small pre-2009 reference distances mean the benchmark is geometrically close to China and should not be interpreted as an independent placebo. |
| pre-2009 reference-actor distance | China-Russia ideal-point distance | 0.622 |  | 0.622 | 0.622 | 4 | Small pre-2009 reference distances mean the benchmark is geometrically close to China and should not be interpreted as an independent placebo. |
| pre-2009 reference-actor distance | China-South Africa ideal-point distance | 0.181 |  | 0.181 | 0.181 | 4 | Small pre-2009 reference distances mean the benchmark is geometrically close to China and should not be interpreted as an independent placebo. |
| pre-2009 reference-actor distance | China-BRICS mean ideal-point distance | 0.258 |  | 0.258 | 0.258 | 4 | Small pre-2009 reference distances mean the benchmark is geometrically close to China and should not be interpreted as an independent placebo. |
| pre-2009 reference-actor distance | China-United States ideal-point distance | 3.520 |  | 3.520 | 3.520 | 4 | Small pre-2009 reference distances mean the benchmark is geometrically close to China and should not be interpreted as an independent placebo. |
| pre-2009 country-year outcome correlation | Correlation: distance to China vs distance to India | 0.948 |  |  |  | 4 | High pre-2009 correlations mean distance-to-reference outcomes are not independent tests of China specificity. |
| pre-2009 country-year outcome correlation | Correlation: distance to China vs distance to Russia | 0.738 |  |  |  | 4 | High pre-2009 correlations mean distance-to-reference outcomes are not independent tests of China specificity. |
| pre-2009 country-year outcome correlation | Correlation: distance to China vs distance to BRICS mean | 0.960 |  |  |  | 4 | High pre-2009 correlations mean distance-to-reference outcomes are not independent tests of China specificity. |

A finalidade desta tabela é evitar sobreinterpretação: benchmarks próximos ou altamente correlacionados com distância à China servem para descrever a geometria do espaço ideal, não para refutar o teste voto-a-voto em direitos humanos.

![Figura 1. Outcomes country-year paralelos para o Brasil, 2005-2012. A linha vertical marca o treatment onset de 2009.](figura_1_country_year_parallel_outcomes.png)

## Vote-Level Human-Rights China-US Divergent Analysis

## Tabela 5. Amostras voto-a-voto

| sample | n_obs | n_countries | n_resolutions | n_brazil_obs | n_donor_obs |
| --- | --- | --- | --- | --- | --- |
| Human-rights China-US divergent votes | 16688 | 95 | 183 | 183 | 16505 |
| Human-rights strong yes/no China-US divergent votes | 15338 | 95 | 168 | 168 | 15170 |
| Non-human-rights China-US divergent votes | 38497 | 95 | 429 | 426 | 38071 |
| Non-human-rights strong yes/no China-US divergent votes | 27004 | 95 | 301 | 299 | 26705 |
| All human-rights votes | 18043 | 95 | 198 | 198 | 17845 |
| All non-human-rights votes | 49218 | 95 | 549 | 546 | 48672 |

A unidade é país-resolução. Votos ausentes, missing e not voting são excluídos. A codificação ordinal é `no = -1`, `abstain = 0`, `yes = 1`. `Post` é definido como `year >= 2009`, alinhado ao treatment onset do paper. A especificação principal usa efeitos fixos de país e resolução; o coeficiente-chave é `Brazil x Post-2009`.

## Tabela 6. Modelos voto-a-voto em votos China-EUA divergentes

| sample | outcome | estimate | se | p_value | ci_95_low | ci_95_high | n_obs | n_countries | n_resolutions | expected_direction |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Human-rights China-US divergent votes | distance_to_china_vote | -0.175 | 0.010 | <0.001 | -0.195 | -0.155 | 16688 | 95 | 183 | negative |
| Human-rights China-US divergent votes | distance_to_usa_vote | 0.185 | 0.011 | <0.001 | 0.164 | 0.207 | 16688 | 95 | 183 | positive |
| Human-rights China-US divergent votes | distance_china_minus_usa | -0.361 | 0.021 | <0.001 | -0.402 | -0.319 | 16688 | 95 | 183 | negative |
| Human-rights China-US divergent votes | closer_to_china_than_usa | 0.117 | 0.007 | <0.001 | 0.104 | 0.130 | 16688 | 95 | 183 | positive |
| Human-rights China-US divergent votes | closer_to_china_score | 0.361 | 0.021 | <0.001 | 0.319 | 0.402 | 16688 | 95 | 183 | positive |
| Human-rights strong yes/no China-US divergent votes | distance_to_china_vote | -0.209 | 0.011 | <0.001 | -0.232 | -0.187 | 15338 | 95 | 168 | negative |
| Human-rights strong yes/no China-US divergent votes | distance_to_usa_vote | 0.209 | 0.011 | <0.001 | 0.187 | 0.232 | 15338 | 95 | 168 | positive |
| Human-rights strong yes/no China-US divergent votes | distance_china_minus_usa | -0.418 | 0.023 | <0.001 | -0.463 | -0.373 | 15338 | 95 | 168 | negative |
| Human-rights strong yes/no China-US divergent votes | closer_to_china_than_usa | 0.134 | 0.007 | <0.001 | 0.120 | 0.147 | 15338 | 95 | 168 | positive |
| Human-rights strong yes/no China-US divergent votes | closer_to_china_score | 0.418 | 0.023 | <0.001 | 0.373 | 0.463 | 15338 | 95 | 168 | positive |
| Non-human-rights China-US divergent votes | distance_to_china_vote | -0.070 | 0.006 | <0.001 | -0.081 | -0.059 | 38497 | 95 | 429 | negative |
| Non-human-rights China-US divergent votes | distance_to_usa_vote | 0.062 | 0.007 | <0.001 | 0.049 | 0.076 | 38497 | 95 | 429 | positive |
| Non-human-rights China-US divergent votes | distance_china_minus_usa | -0.132 | 0.012 | <0.001 | -0.156 | -0.108 | 38497 | 95 | 429 | negative |
| Non-human-rights China-US divergent votes | closer_to_china_than_usa | 0.055 | 0.005 | <0.001 | 0.046 | 0.065 | 38497 | 95 | 429 | positive |
| Non-human-rights China-US divergent votes | closer_to_china_score | 0.132 | 0.012 | <0.001 | 0.108 | 0.156 | 38497 | 95 | 429 | positive |
| Non-human-rights strong yes/no China-US divergent votes | distance_to_china_vote | -0.067 | 0.009 | <0.001 | -0.084 | -0.049 | 27004 | 95 | 301 | negative |
| Non-human-rights strong yes/no China-US divergent votes | distance_to_usa_vote | 0.067 | 0.009 | <0.001 | 0.049 | 0.084 | 27004 | 95 | 301 | positive |
| Non-human-rights strong yes/no China-US divergent votes | distance_china_minus_usa | -0.133 | 0.018 | <0.001 | -0.169 | -0.097 | 27004 | 95 | 301 | negative |
| Non-human-rights strong yes/no China-US divergent votes | closer_to_china_than_usa | 0.039 | 0.006 | <0.001 | 0.027 | 0.050 | 27004 | 95 | 301 | positive |
| Non-human-rights strong yes/no China-US divergent votes | closer_to_china_score | 0.133 | 0.018 | <0.001 | 0.097 | 0.169 | 27004 | 95 | 301 | positive |

Os p-valores desta tabela são inferência model-based com clusters por país. Como há uma única unidade tratada substantiva, a inferência principal para o teste voto-a-voto é o placebo por país reportado abaixo; os erros-padrão convencionais servem como diagnóstico de precisão dentro da amostra.

## Tabela 7. Teste DDD: incremento em direitos humanos relativo a non-HR

| outcome | term | estimate | se | p_value | ci_95_low | ci_95_high | n_obs | n_countries | n_resolutions | expected_direction | model |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| distance_china_minus_usa | brazil_post_2009 | -0.120 | 0.013 | <0.001 | -0.146 | -0.093 | 55185 | 95 | 612 | non-HR Brazil post component | DDD HR vs non-HR among China-US divergent votes; country-clustered SE |
| distance_china_minus_usa | brazil_post_hr | -0.275 | 0.055 | <0.001 | -0.384 | -0.166 | 55185 | 95 | 612 | negative incremental HR effect | DDD HR vs non-HR among China-US divergent votes; country-clustered SE |
| distance_china_minus_usa | brazil_post_2009 | -0.120 | 0.014 | <0.001 | -0.147 | -0.093 | 55185 | 95 | 612 | non-HR Brazil post component | DDD HR vs non-HR among China-US divergent votes; two-way clustered SE by country and resolution |
| distance_china_minus_usa | brazil_post_hr | -0.275 | 0.054 | <0.001 | -0.383 | -0.167 | 55185 | 95 | 612 | negative incremental HR effect | DDD HR vs non-HR among China-US divergent votes; two-way clustered SE by country and resolution |
| agreement_china_minus_usa | brazil_post_2009 | 0.103 | 0.007 | <0.001 | 0.090 | 0.116 | 55185 | 95 | 612 | non-HR Brazil post component | DDD HR vs non-HR among China-US divergent votes; country-clustered SE |
| agreement_china_minus_usa | brazil_post_hr | 0.093 | 0.026 | <0.001 | 0.043 | 0.144 | 55185 | 95 | 612 | positive incremental HR effect | DDD HR vs non-HR among China-US divergent votes; country-clustered SE |
| agreement_china_minus_usa | brazil_post_2009 | 0.103 | 0.007 | <0.001 | 0.088 | 0.118 | 55185 | 95 | 612 | non-HR Brazil post component | DDD HR vs non-HR among China-US divergent votes; two-way clustered SE by country and resolution |
| agreement_china_minus_usa | brazil_post_hr | 0.093 | 0.025 | <0.001 | 0.043 | 0.144 | 55185 | 95 | 612 | positive incremental HR effect | DDD HR vs non-HR among China-US divergent votes; two-way clustered SE by country and resolution |

O termo `brazil_post_hr` é o teste mais direto de seletividade temática: ele compara a mudança brasileira em votos de direitos humanos com a mudança brasileira em votos non-HR, mantendo efeitos fixos de país e resolução.

## Tabela 8. Sensibilidade com clusters bidirecionais por país e resolução

| sample | outcome | estimate | se | p_value | ci_95_low | ci_95_high | n_obs | n_countries | n_resolutions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Human-rights China-US divergent votes | distance_to_china_vote | -0.175 | 0.011 | <0.001 | -0.197 | -0.153 | 16688 | 95 | 183 |
| Human-rights China-US divergent votes | distance_to_usa_vote | 0.185 | 0.011 | <0.001 | 0.163 | 0.208 | 16688 | 95 | 183 |
| Human-rights China-US divergent votes | distance_china_minus_usa | -0.361 | 0.022 | <0.001 | -0.404 | -0.317 | 16688 | 95 | 183 |
| Human-rights China-US divergent votes | closer_to_china_score | 0.361 | 0.022 | <0.001 | 0.317 | 0.404 | 16688 | 95 | 183 |
| Human-rights strong yes/no China-US divergent votes | distance_to_china_vote | -0.209 | 0.012 | <0.001 | -0.233 | -0.185 | 15338 | 95 | 168 |
| Human-rights strong yes/no China-US divergent votes | distance_to_usa_vote | 0.209 | 0.012 | <0.001 | 0.185 | 0.233 | 15338 | 95 | 168 |
| Human-rights strong yes/no China-US divergent votes | distance_china_minus_usa | -0.418 | 0.024 | <0.001 | -0.466 | -0.370 | 15338 | 95 | 168 |
| Human-rights strong yes/no China-US divergent votes | closer_to_china_score | 0.418 | 0.024 | <0.001 | 0.370 | 0.466 | 15338 | 95 | 168 |
| Non-human-rights China-US divergent votes | distance_to_china_vote | -0.070 | 0.006 | <0.001 | -0.082 | -0.058 | 38497 | 95 | 429 |
| Non-human-rights China-US divergent votes | distance_to_usa_vote | 0.062 | 0.007 | <0.001 | 0.048 | 0.076 | 38497 | 95 | 429 |
| Non-human-rights China-US divergent votes | distance_china_minus_usa | -0.132 | 0.012 | <0.001 | -0.157 | -0.108 | 38497 | 95 | 429 |
| Non-human-rights China-US divergent votes | closer_to_china_score | 0.132 | 0.012 | <0.001 | 0.108 | 0.157 | 38497 | 95 | 429 |

![Figura 2. Médias pré/pós em votos de direitos humanos nos quais China e EUA divergiram.](figura_2_vote_level_hr_divergent_prepost.png)

A sensibilidade forte `yes` vs `no` exclui divergências mediadas por abstenção. O controle negativo non-HR usa a mesma lógica, mas em resoluções fora de direitos humanos. A categoria `Other / uncoded`, quando aparece no painel bruto, é residual e heterogênea; ela não é interpretada como área substantiva.

## Placebos

## Tabela 9. Event-study pré-2009 e teste de magnitude substantiva

| outcome | year | estimate | se | p_value | ci_95_low | ci_95_high | equivalence_threshold | within_threshold |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| distance_china_minus_usa | 2006 | 0.061 | 0.019 | 0.001 | 0.024 | 0.099 | 0.090 | TRUE |
| distance_china_minus_usa | 2007 | -0.029 | 0.030 | 0.347 | -0.089 | 0.032 | 0.090 | TRUE |
| distance_china_minus_usa | 2008 | -0.002 | 0.029 | 0.939 | -0.060 | 0.055 | 0.090 | TRUE |
| closer_to_china_score | 2006 | -0.061 | 0.019 | 0.001 | -0.099 | -0.024 | 0.090 | TRUE |
| closer_to_china_score | 2007 | 0.029 | 0.030 | 0.347 | -0.032 | 0.089 | 0.090 | TRUE |
| closer_to_china_score | 2008 | 0.002 | 0.029 | 0.939 | -0.055 | 0.060 | 0.090 | TRUE |

A coluna `within_threshold` indica se o coeficiente pré-2009 está dentro de 25% do efeito principal em valor absoluto. Isso é um diagnóstico de escala, não uma prova de tendências paralelas.

## Tabela 10. Placebos temporais pré-2009

| pseudo_year | outcome | estimate | se | p_value | ci_95_low | ci_95_high | n_obs | n_countries | n_resolutions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2007 | distance_china_minus_usa | -0.051 | 0.024 | 0.035 | -0.098 | -0.004 | 8720 | 95 | 96 |
| 2007 | closer_to_china_score | 0.051 | 0.024 | 0.035 | 0.004 | 0.098 | 8720 | 95 | 96 |
| 2008 | distance_china_minus_usa | -0.015 | 0.017 | 0.365 | -0.048 | 0.018 | 8720 | 95 | 96 |
| 2008 | closer_to_china_score | 0.015 | 0.017 | 0.365 | -0.018 | 0.048 | 8720 | 95 | 96 |

O pseudo-break de 2007 aparece na direção esperada, embora com magnitude muito menor que o efeito principal. Por isso, os placebos temporais são tratados como um aviso contra linguagem causal forte, não como validação binária.

## Tabela 11. Placebo por país no donor pool

| outcome | brazil_estimate | brazil_rank_expected_direction | n_placebo_units | randomization_p_directional | randomization_p_two_sided | randomization_p_directional_strict_donor | randomization_p_two_sided_strict_donor | interpretation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| closer_to_china_score | 0.361 | 6 | 95 | 0.063 | 0.084 | 0.053 | 0.074 | Brazil is in the directional tail of the donor-placebo distribution. |
| distance_china_minus_usa | -0.361 | 6 | 95 | 0.063 | 0.084 | 0.053 | 0.074 | Brazil is in the directional tail of the donor-placebo distribution. |

## Tabela 12. Auditoria dos placebos mais extremos

| expected_rank | placebo_unit | country_name | region | estimate | brazil_estimate | sdid_weight | first_treat_year | china_top_or_similar_shock_2005_2012 | audit_note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | NIC | Nicaragua | Latin America & Caribbean | -0.598 | -0.361 | 0.0130 |  | FALSE | Latin America left-turn/ALBA context; plausible broad anti-US or South-South repositioning competing explanation. |
| 2 | DOM | Dominican Republic | Latin America & Caribbean | -0.444 | -0.361 | 0.0215 |  | FALSE | Latin America/Caribbean high-tail placebo; requires country-specific follow-up and weakens uniqueness of the Brazil pattern. |
| 3 | UGA | Uganda | Sub-Saharan Africa | -0.427 | -0.361 | 0.0103 |  | FALSE | Sub-Saharan Africa high-tail placebo; possible bloc or issue-specific voting shift, requiring country-specific follow-up. |
| 4 | BOL | Bolivia | Latin America & Caribbean | -0.409 | -0.361 | 0.0215 |  | FALSE | Latin America left-turn/ALBA context; plausible broad anti-US or South-South repositioning competing explanation. |
| 5 | ECU | Ecuador | Latin America & Caribbean | -0.406 | -0.361 | 0.0005 |  | FALSE | Latin America left-turn/ALBA context; plausible broad anti-US or South-South repositioning competing explanation. |
| 6 | BRA | Brazil | Latin America & Caribbean | -0.361 | -0.361 |  |  | FALSE | Actual treated unit; included as the reference line for the placebo distribution. |

![Figura 3. Distribuição placebo por país para o outcome distância China-menos-EUA em votos de direitos humanos China-EUA divergentes. A linha vermelha marca o Brasil.](figura_3_country_placebo_distribution.png)

## Donor-Pool Audit

## Tabela 13. Auditoria do donor pool

| iso3c | country_name | sdid_weight | first_treat_year | absorbing | displaced | china_top_years_2005_2012 | china_top_or_similar_shock_2005_2012 | reference_actor_in_vote_design | contamination_note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MLT | Malta | 0.0306 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GEO | Georgia | 0.0291 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| PRY | Paraguay | 0.0272 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| TCD | Chad | 0.0268 | 2019 | FALSE | IND | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GTM | Guatemala | 0.0262 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| COL | Colombia | 0.0250 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| IND | India | 0.0217 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| DOM | Dominican Republic | 0.0215 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BOL | Bolivia | 0.0215 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| TUR | Turkey | 0.0214 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| FJI | Fiji | 0.0214 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| PNG | Papua New Guinea | 0.0207 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ALB | Albania | 0.0197 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MWI | Malawi | 0.0197 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| AZE | Azerbaijan | 0.0196 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| DEU | Germany | 0.0190 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| HRV | Croatia | 0.0176 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| CYP | Cyprus | 0.0176 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| CRI | Costa Rica | 0.0173 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| KEN | Kenya | 0.0159 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ARG | Argentina | 0.0155 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| HTI | Haiti | 0.0153 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SUR | Suriname | 0.0148 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ISL | Iceland | 0.0146 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| TTO | Trinidad & Tobago | 0.0139 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| NOR | Norway | 0.0136 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BRB | Barbados | 0.0134 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| HUN | Hungary | 0.0133 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SLV | El Salvador | 0.0132 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| NIC | Nicaragua | 0.0130 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| PAK | Pakistan | 0.0128 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| POL | Poland | 0.0127 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| DNK | Denmark | 0.0127 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| TUN | Tunisia | 0.0118 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| JAM | Jamaica | 0.0118 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MDV | Maldives | 0.0118 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| LTU | Lithuania | 0.0118 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MUS | Mauritius | 0.0117 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BTN | Bhutan | 0.0115 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| EST | Estonia | 0.0113 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| CZE | Czechia | 0.0113 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ROU | Romania | 0.0112 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| LVA | Latvia | 0.0111 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| NAM | Namibia | 0.0109 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| LBN | Lebanon | 0.0106 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ISR | Israel | 0.0106 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SVN | Slovenia | 0.0105 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GUY | Guyana | 0.0104 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| DZA | Algeria | 0.0103 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| UGA | Uganda | 0.0103 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BGR | Bulgaria | 0.0102 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| TGO | Togo | 0.0102 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SVK | Slovakia | 0.0099 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| PAN | Panama | 0.0099 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ESP | Spain | 0.0094 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| COM | Comoros | 0.0087 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| JOR | Jordan | 0.0081 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GRC | Greece | 0.0080 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MDA | Moldova | 0.0079 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SWE | Sweden | 0.0077 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| AUT | Austria | 0.0075 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SEN | Senegal | 0.0074 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| QAT | Qatar | 0.0074 | 2021 | TRUE | JPN | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MAR | Morocco | 0.0072 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| NLD | Netherlands | 0.0071 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| FIN | Finland | 0.0070 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| PRT | Portugal | 0.0066 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| CAN | Canada | 0.0064 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ITA | Italy | 0.0052 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| USA | United States | 0.0049 |  | FALSE |  | 0 | FALSE | TRUE | USA is a reference actor in China-US divergent vote outcomes; excluded from main vote-level donor comparison. |
| CPV | Cape Verde | 0.0044 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GBR | United Kingdom | 0.0044 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| LKA | Sri Lanka | 0.0042 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| UKR | Ukraine | 0.0038 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MEX | Mexico | 0.0031 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| EGY | Egypt | 0.0024 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| IRL | Ireland | 0.0019 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GHA | Ghana | 0.0018 | 2019 | FALSE | IND | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GIN | Guinea | 0.0011 | 2019 | FALSE | ARE | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| CIV | Côte d’Ivoire | 0.0010 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BWA | Botswana | 0.0008 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| LBY | Libya | 0.0007 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ARE | United Arab Emirates | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BGD | Bangladesh | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BHR | Bahrain | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| BLR | Belarus | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| ECU | Ecuador | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| FRA | France | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| GAB | Gabon | 0.0005 | 2017 | TRUE | COG | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| KWT | Kuwait | 0.0005 | 2018 | TRUE | KOR | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| MDG | Madagascar | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| NGA | Nigeria | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| RWA | Rwanda | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| SWZ | Eswatini | 0.0005 |  | FALSE |  | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |
| VEN | Venezuela | 0.0005 | 2021 | TRUE | IND | 0 | FALSE | FALSE | No China-top treatment entry flagged during 2005-2012. |

A especificação voto-a-voto principal exclui os Estados Unidos do donor pool porque os EUA são um dos polos que definem os outcomes de distância e proximidade. Essa decisão evita que uma unidade de referência entre mecanicamente como comparação. Donor weights aparecem apenas como auditoria/sensibilidade, não como base inferencial principal.

## Tabela 14. Sensibilidade excluindo donors com China-top entry em 2005-2012

| sample | outcome | estimate | se | p_value | n_obs | n_countries | n_resolutions | n_excluded_donors | excluded_donors |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Human-rights China-US divergent votes | distance_china_minus_usa | -0.361 | 0.021 | <0.001 | 16688 | 95 | 183 | 0 |  |
| Human-rights China-US divergent votes | closer_to_china_score | 0.361 | 0.021 | <0.001 | 16688 | 95 | 183 | 0 |  |
| Non-human-rights China-US divergent votes | distance_china_minus_usa | -0.132 | 0.012 | <0.001 | 38497 | 95 | 429 | 0 |  |
| Non-human-rights China-US divergent votes | closer_to_china_score | 0.132 | 0.012 | <0.001 | 38497 | 95 | 429 | 0 |  |

## Matriz Interpretativa Final

## Tabela 15. Aplicação da matriz decisória aos achados

| section | criterion | passed | detail |
| --- | --- | --- | --- |
| Decision flag | HR China-minus-US vote-level effect is in China-specific direction | TRUE | HR distance China-minus-USA estimate = -0.361. |
| Decision flag | DDD test shows incremental HR effect beyond non-HR divergent votes | TRUE | DDD incremental HR estimate for distance China-minus-USA = -0.275; for agreement China-minus-USA = 0.093. |
| Decision flag | HR distance-to-China falls and distance-to-USA rises | TRUE | HR distance-to-China = -0.175; HR distance-to-USA = 0.185. |
| Decision flag | Strong yes/no HR sensitivity is in China-specific direction | TRUE | Strong yes/no HR distance China-minus-USA estimate = -0.418. |
| Decision flag | Non-HR negative-control effect is materially weaker than HR | TRUE | Non-HR distance China-minus-USA estimate = -0.132. |
| Decision flag | Temporal placebo diagnostics are small but not clean | TRUE | Main HR estimate = -0.361; temporal placebos: pseudo-2007=-0.051 (p=0.035); pseudo-2008=-0.015 (p=0.365). |
| Decision flag | Brazil is directionally unusual in donor country-placebo distribution | TRUE | Directional country-placebo p inclusive = 0.063; strict donor-only p = 0.053. |
| Decision flag | Alternative BRICS/Russia/India benchmarks are treated as geometric diagnostics, not independent placebos | FALSE | abs_distance_russia=0.325; abs_distance_india=-0.296; abs_distance_brics_no_brazil=-0.249. Spatial proximity/correlation means these outcomes are not used as China-specific counterexamples. |
| Final classification | Diagnostic evidence compatible with selective HR China alignment, not standalone causal proof |  | The main text can make only a cautious diagnostic claim: Brazil's post-2009 UNGA movement is most consistent with selective adjustment in human-rights votes where China and the United States diverged. It should not say that Table 4/Figure 6 alone proves China-specific convergence. |

## Recomendação editorial

No texto principal, a revisão deve evitar dizer que Table 4 sozinha prova convergência seletiva. A forma compacta recomendada é substituir a interpretação atual por uma frase que separe o SDiD country-year da evidência voto-a-voto:

> The country-year SDiD estimate shows that Brazil moved closer to China after the 2009 export-rank reversal, including in a China-minus-US distance contrast. Resolution-level evidence should be read as a substantive diagnostic rather than a standalone causal test: the clearest additional support comes from human-rights resolutions where China and the United States diverged, and the human-rights shift is larger than the corresponding non-human-rights shift. Benchmarks to India, Russia, and BRICS are useful geometric checks of the ideal-point space, not independent placebos for China-specificity. Taken together, the evidence supports a narrower claim of selective UNGA adjustment in politically visible domains, not a wholesale realignment of Brazilian foreign policy.

O resultado completo deste pacote deve entrar no apêndice ou em relatório de qualidade. No corpo do paper, bastam: a tabela country-year resumida, uma frase sobre o teste voto-a-voto HR China-EUA divergente, e o caveat explícito de que a evidência resolution-level é diagnóstica.

## Arquivos gerados

- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_audit_gap_table.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_decision_matrix.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_country_year_outcomes.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_country_year_brazil_series.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_reference_spatial_diagnostics.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_vote_panel_2005_2012.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_vote_panel_2000_2015.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_vote_level_models.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_vote_level_descriptives.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_target_file_audit.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_ddd_hr_nonhr_models.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_twoway_cluster_sensitivity.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_pretrend_event_study.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_temporal_placebos.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_country_placebos.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_country_placebo_summary.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_extreme_placebo_audit.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_donor_pool_audit.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_donor_contamination_sensitivity.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_model_sample_counts.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_final_interpretation.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_validation_checks.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/figura_1_country_year_parallel_outcomes.png`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/figura_1_country_year_parallel_outcomes.pdf`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/figura_2_vote_level_hr_divergent_prepost.png`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/figura_2_vote_level_hr_divergent_prepost.pdf`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/figura_3_country_placebo_distribution.png`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/figura_3_country_placebo_distribution.pdf`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/2026-05-20_selective_china_alignment_unga_report.md`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/quality_reports/selective_china_alignment_unga/selective_china_alignment_session_info.txt`
