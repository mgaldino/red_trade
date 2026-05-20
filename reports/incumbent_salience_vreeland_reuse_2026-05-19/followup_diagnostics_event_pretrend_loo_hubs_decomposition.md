# Follow-up diagnostics: event studies, pretrends, influence, hubs, and regional-power decomposition

Generated: 2026-05-19 23:32:55 -03

This script reads `china_top_absorbing_sample` via `targets::tar_read()` and joins the already-created incumbent-salience and LPV moderator CSVs. It does not run `targets::tar_make()` and does not edit the targets pipeline or manuscript.

## Table 1. Overall C&S estimates by diagnostic sample

| model | status | att | se | ci | p | n_treated | n_control |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline C&S | ok | -0.101 | 0.047 | [-0.193, -0.009] | 0.032 | 14 | 91 |
| Event study: displaced_us_no | ok | -0.110 | 0.065 | [-0.237, 0.017] | 0.088 | 10 | 91 |
| Event study: displaced_us_yes | ok | -0.082 | 0.072 | [-0.222, 0.059] | 0.257 | 4 | 91 |
| Event study: displaced_g7_no | ok | -0.095 | 0.081 | [-0.254, 0.063] | 0.238 | 6 | 91 |
| Event study: displaced_g7_yes | ok | -0.104 | 0.066 | [-0.234, 0.027] | 0.119 | 8 | 91 |
| Event study: regional_power_no | ok | -0.089 | 0.103 | [-0.292, 0.113] | 0.387 | 4 | 91 |
| Event study: regional_power_yes | ok | -0.105 | 0.061 | [-0.224, 0.015] | 0.086 | 10 | 91 |
| Event study: same_region_power_no | ok | -0.084 | 0.053 | [-0.187, 0.020] | 0.112 | 10 | 91 |
| Event study: same_region_power_yes | ok | -0.128 | 0.105 | [-0.335, 0.078] | 0.224 | 4 | 91 |
| Event study: high_level_partner_no | ok | -0.098 | 0.054 | [-0.203, 0.008] | 0.070 | 11 | 91 |
| Event study: high_level_partner_yes | ok | -0.124 | 0.127 | [-0.373, 0.125] | 0.329 | 3 | 91 |
| Hub-excluded C&S | ok | -0.118 | 0.054 | [-0.223, -0.013] | 0.027 | 12 | 91 |
| Regional-power decomposition: other_g7 | ok | -0.126 | 0.126 | [-0.373, 0.122] | 0.320 | 4 | 91 |
| Regional-power decomposition: other_incumbent | ok | -0.089 | 0.103 | [-0.292, 0.113] | 0.387 | 4 | 91 |
| Regional-power decomposition: us | ok | -0.082 | 0.072 | [-0.222, 0.059] | 0.257 | 4 | 91 |
| Regional-power decomposition: external_regional_or_global_power | skipped | NA | NA | [NA, NA] | NA | 1 | 91 |
| Regional-power decomposition: same_region_regional_power | skipped | NA | NA | [NA, NA] | NA | 1 | 91 |

## Table 2. Lead/pretrend diagnostics

The formal pre-test is the `did::att_gt()` pre-test when available. The near-pre window is event times -5 to -2; event time -1 is the universal baseline.

| model | status | n_treated | pretest_p | near_pre_mean_att | near_pre_max_abs_att | near_pre_n_p_below_005 | all_pre_n_p_below_005 | post_0_5_mean_att |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline C&S | ok | 14 | NA | 0.011 | 0.031 | 0 | 2 | -0.102 |
| Event study: displaced_us_no | ok | 10 | NA | 0.004 | 0.035 | 0 | 3 | -0.106 |
| Event study: displaced_us_yes | ok | 4 | NA | 0.030 | 0.054 | 0 | 6 | -0.093 |
| Event study: displaced_g7_no | ok | 6 | NA | -0.034 | 0.140 | 0 | 3 | -0.137 |
| Event study: displaced_g7_yes | ok | 8 | NA | 0.045 | 0.085 | 0 | 7 | -0.074 |
| Event study: regional_power_no | ok | 4 | NA | -0.088 | 0.150 | 0 | 6 | -0.120 |
| Event study: regional_power_yes | ok | 10 | NA | 0.051 | 0.078 | 0 | 5 | -0.096 |
| Event study: same_region_power_no | ok | 10 | NA | 0.005 | 0.053 | 0 | 3 | -0.108 |
| Event study: same_region_power_yes | ok | 4 | NA | 0.026 | 0.094 | 0 | 4 | -0.087 |
| Event study: high_level_partner_no | ok | 11 | NA | 0.028 | 0.041 | 0 | 3 | -0.107 |
| Event study: high_level_partner_yes | ok | 3 | NA | -0.048 | 0.202 | 0 | 6 | -0.085 |
| Hub-excluded C&S | ok | 12 | NA | 0.021 | 0.067 | 0 | 3 | -0.110 |
| Regional-power decomposition: other_g7 | ok | 4 | NA | 0.060 | 0.121 | 0 | 11 | -0.052 |
| Regional-power decomposition: other_incumbent | ok | 4 | NA | -0.088 | 0.150 | 0 | 6 | -0.120 |
| Regional-power decomposition: us | ok | 4 | NA | 0.030 | 0.054 | 0 | 6 | -0.093 |
| Regional-power decomposition: external_regional_or_global_power | skipped | 1 | NA | NA | NA | 0 | 0 | NA |
| Regional-power decomposition: same_region_regional_power | skipped | 1 | NA | NA | NA | 0 | 0 | NA |

## Table 3. Most influential leave-one-treated-country exclusions

| excluded_iso3c | excluded_country_name | excluded_first_treat | att | delta_att | p |
| --- | --- | --- | --- | --- | --- |
| SLB | Solomon Islands | 2003 | -0.066 | 0.035 | 0.069 |
| MMR | Myanmar (Burma) | 2014 | -0.083 | 0.018 | 0.114 |
| CHL | Chile | 2008 | -0.086 | 0.015 | 0.126 |
| PHL | Philippines | 2005 | -0.113 | -0.013 | 0.023 |
| SAU | Saudi Arabia | 2015 | -0.112 | -0.011 | 0.023 |
| SLE | Sierra Leone | 2012 | -0.110 | -0.009 | 0.028 |
| AGO | Angola | 2007 | -0.109 | -0.009 | 0.042 |
| AUS | Australia | 2010 | -0.109 | -0.008 | 0.036 |

## Table 4. Hub/entrepot exclusion

| model | att | se | ci | p | n_treated | n_control |
| --- | --- | --- | --- | --- | --- | --- |
| Baseline C&S | -0.101 | 0.047 | [-0.193, -0.009] | 0.032 | 14 | 91 |
| Hub-excluded C&S | -0.118 | 0.054 | [-0.223, -0.013] | 0.027 | 12 | 91 |

Excluded hub/entrepot treated cases:

| iso3c | country_name | first_treat_year | displaced_partner | displaced_partner_name | displacement_salience_warning |
| --- | --- | --- | --- | --- | --- |
| MYS | Malaysia | 2009 | SGP | Singapore | hub_or_entrepot_incumbent |
| SLE | Sierra Leone | 2012 | BEL | Belgium | hub_or_entrepot_incumbent |

## Table 5. Regional-power decomposition counts

| regional_power_decomposition | n_treated_countries | countries | displaced_partners |
| --- | --- | --- | --- |
| other_g7 | 4 | AUS, PHL, QAT, SLB | JPN |
| other_incumbent | 4 | GAB, MMR, MYS, SLE | BEL, COG, SGP, THA |
| us | 4 | AGO, BRA, CHL, SAU | USA |
| external_regional_or_global_power | 1 | KWT | KOR |
| same_region_regional_power | 1 | URY | BRA |

## Table 6. Regional-power decomposition estimates

| model | status | att | se | ci | p | n_treated | n_control |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Regional-power decomposition: other_g7 | ok | -0.126 | 0.126 | [-0.373, 0.122] | 0.320 | 4 | 91 |
| Regional-power decomposition: other_incumbent | ok | -0.089 | 0.103 | [-0.292, 0.113] | 0.387 | 4 | 91 |
| Regional-power decomposition: us | ok | -0.082 | 0.072 | [-0.222, 0.059] | 0.257 | 4 | 91 |
| Regional-power decomposition: external_regional_or_global_power | skipped | NA | NA | [NA, NA] | NA | 1 | 91 |
| Regional-power decomposition: same_region_regional_power | skipped | NA | NA | [NA, NA] | NA | 1 | 91 |

## Interpretation

- These diagnostics use C&S event-study estimators because they expose dynamic effects and pre-treatment leads directly.
- Subgroups with very few treated countries remain exploratory; skipped models have insufficient treated support.
- Formal pre-tests are often unavailable because `did::att_gt()` reports singular covariance matrices in this small-treated design; the lead summaries therefore matter more than the unavailable omnibus p-values.
- Hub/entrepot exclusion removes treated countries whose displaced incumbents are `ARE`, `BEL`, `CHE`, `HKG`, or `SGP` while retaining never-treated controls.
- The regional-power decomposition is prioritized as: US, other G7, same-region regional power, external regional/global power, other incumbent.

## Output files

- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_overall_att_by_diagnostic.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_event_studies_by_subgroup.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_pretrend_tests_by_subgroup.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_leave_one_country_out_cs.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_hub_exclusion_cases.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_regional_power_decomposition_counts.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_treated_cases_audit.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_event_studies_by_subgroup.png`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/followup_sessionInfo_event_pretrend_loo.txt`
