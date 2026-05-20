# Model results: 500-bootstrap incumbent-salience diagnostics

Generated: 2026-05-19 23:24:42 -03
Bootstrap replications: 500

These are preliminary diagnostics. They use the existing absorbing China-top estimation sample and `fect` IFE with two-way fixed effects, cross-validated latent factors `r = 0:3`, and grouped ATT estimates. The grouped models are heterogeneity diagnostics, not independent causal identification checks.

## Table 1. Overall fect IFE estimates

| model | status | att | se | ci | p | r_cv | n_countries | n_treated | n_control |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Baseline IFE, no moderator | ok | -0.100 | 0.041 | [-0.180, -0.020] | 0.014 | 2 | 105 | 14 | 91 |
| IFE grouped by displaced_us | ok | -0.100 | 0.041 | [-0.180, -0.020] | 0.014 | 2 | 105 | 14 | 91 |
| IFE grouped by displaced_g7 | ok | -0.100 | 0.041 | [-0.180, -0.020] | 0.014 | 2 | 105 | 14 | 91 |
| IFE grouped by displaced_regional_power | ok | -0.100 | 0.041 | [-0.180, -0.020] | 0.014 | 2 | 105 | 14 | 91 |
| IFE grouped by pre_entry_high_level_partner | ok | -0.100 | 0.041 | [-0.180, -0.020] | 0.014 | 2 | 105 | 14 | 91 |

## Table 2. Grouped ATT estimates by pre-treatment moderator

| model | group | n_treated_countries | treated_country_years | att | se | ci | p | r_cv |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| IFE grouped by displaced_us | displaced_us_no | 10 | 108 | -0.091 | 0.054 | [-0.189, 0.025] | 0.120 | 2 |
| IFE grouped by displaced_us | displaced_us_yes | 4 | 53 | -0.120 | 0.048 | [-0.206, -0.018] | 0.036 | 2 |
| IFE grouped by displaced_g7 | displaced_g7_no | 6 | 55 | -0.103 | 0.060 | [-0.220, 0.017] | 0.068 | 2 |
| IFE grouped by displaced_g7 | displaced_g7_yes | 8 | 106 | -0.099 | 0.061 | [-0.219, 0.021] | 0.100 | 2 |
| IFE grouped by displaced_regional_power | regional_power_no | 4 | 40 | -0.092 | 0.076 | [-0.264, 0.030] | 0.133 | 2 |
| IFE grouped by displaced_regional_power | regional_power_yes | 10 | 121 | -0.103 | 0.054 | [-0.208, 0.008] | 0.068 | 2 |
| IFE grouped by pre_entry_high_level_partner | high_level_partner_no | 11 | 142 | -0.089 | 0.044 | [-0.175, 0.003] | 0.056 | 2 |
| IFE grouped by pre_entry_high_level_partner | high_level_partner_yes | 3 | 19 | -0.187 | 0.079 | [-0.314, -0.007] | 0.037 | 2 |

## Table 3. Treated-country cell counts

| model | group | n_treated_countries | treated_country_years | first_t0 | last_t0 |
| --- | --- | --- | --- | --- | --- |
| IFE grouped by displaced_us | displaced_us_no | 10 | 108 | 2003 | 2021 |
| IFE grouped by displaced_us | displaced_us_yes | 4 | 53 | 2007 | 2015 |
| IFE grouped by displaced_g7 | displaced_g7_no | 6 | 55 | 2009 | 2018 |
| IFE grouped by displaced_g7 | displaced_g7_yes | 8 | 106 | 2003 | 2021 |
| IFE grouped by displaced_regional_power | regional_power_no | 4 | 40 | 2009 | 2017 |
| IFE grouped by displaced_regional_power | regional_power_yes | 10 | 121 | 2003 | 2021 |
| IFE grouped by pre_entry_high_level_partner | high_level_partner_no | 11 | 142 | 2003 | 2018 |
| IFE grouped by pre_entry_high_level_partner | high_level_partner_yes | 3 | 19 | 2014 | 2021 |

## Table 4. Salience warnings among treated countries

| displacement_salience_warning | n_countries |
| --- | --- |
| narrow_export_share_margin | 7 |
| none | 4 |
| hub_or_entrepot_incumbent | 2 |
| weak_pre_entry_persistence | 1 |

## Interpretation guardrails

- `displaced_us`, `displaced_g7`, and `displaced_regional_power` are measured at `t0 - 1`, before treatment entry/onset.
- `pre_entry_high_level_partner` is derived from LPV's `partner_level_lag1` at `t0`; it is a robustness diagnostic because it is close to the China-alignment mechanism.
- Cases flagged as hubs/entrepôts, narrow-margin displacements, or weakly persistent incumbents should not be treated as strong evidence that a politically salient incumbent was displaced.
- These 500-bootstrap runs are meant to screen patterns before heavier event-study, pre-trend, hub-exclusion, and leave-one-country-out diagnostics.

## Output files

- `reports/incumbent_salience_vreeland_reuse_2026-05-19/model_results_500_bootstrap_overall.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/model_results_500_bootstrap_group_att.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/model_results_500_bootstrap_cell_counts.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/model_results_500_bootstrap_salience_diagnostics.csv`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/model_run_500_bootstrap.log`
- `reports/incumbent_salience_vreeland_reuse_2026-05-19/model_sessionInfo_500_bootstrap.txt`
