# Selected public-cue SDiD and pooled IFE diagnostic

Generated: 2026-09-22 09:41:58 -03

## Design

The common estimation window is 1997-2022. The outcome is absolute UNGA ideal-point distance to China. 
Every SDiD donor has a complete outcome/rank panel and never has China as its largest goods-export destination in this window. This leaves 105 donors.
The first pooled IFE model keeps these controls plus CHL, URY, GAB, QAT, and AUS; only those five can be treated. The second starts from every complete country panel, but still codes treatment only for the five focal cases. Non-focal China-top country-years are masked, so those countries leave and re-enter the comparison pool without becoming treated cases. Both designs are then re-estimated after excluding Gabon and Qatar entirely and adding Brazil; the reduced focal group is AUS, BRA, CHL, and URY.

## SDiD results

| Fit | Country | Year | ATT | Placebo SE | 95% CI | Pre/Post | Donors |
| --- | --- | --- | --- | --- | --- | --- | --- |
| chl_cue_2008 | Chile | 2008 | -0.1301 | 0.1545 | [-0.4328, 0.1726] | 11/15 | 105 |
| ury_cue_2013 | Uruguay | 2013 | -0.0682 | 0.1514 | [-0.3649, 0.2285] | 16/10 | 105 |
| gab_cue_2017 | Gabon | 2017 | -0.0429 | 0.1175 | [-0.2732, 0.1874] | 20/6 | 105 |
| qat_cue_2021 | Qatar | 2021 | 0.1263 | 0.1221 | [-0.1131, 0.3657] | 24/2 | 105 |
| aus_cue_2009 | Australia | 2009 | 0.0420 | 0.1545 | [-0.2608, 0.3449] | 12/14 | 105 |
| aus_top1_2010 | Australia | 2010 | 0.0900 | 0.1468 | [-0.1978, 0.3778] | 13/13 | 105 |

Placebo standard errors use 5000 replications and seed 20260520. The reported p-values are normal approximations based on the placebo standard error, not exact randomization p-values.

## Pooled interactive fixed-effects results

| Alternative | Estimand | Target | ATT | Bootstrap SE | 95% CI | Selected r | Estimand units/cells | Fit Ntr/Nco | Switch controls/masked cells | Min untreated | Reversals |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Five cases + clean controls | focal_public_cue_cases | yes | -0.0236 | 0.0750 | [-0.1706, 0.1234] | 1 | 5/47 | 5/105 | 0/0 | 1 | 0 |
| Five cases + switching controls | focal_public_cue_cases | yes | -0.0213 | 0.0618 | [-0.1425, 0.1000] | 1 | 5/47 | 5/153 | 48/448 | 1 | 0 |
| Four cases + clean controls; no GAB/QAT | focal_public_cue_cases | yes | -0.1158 | 0.0654 | [-0.2441, 0.0124] | 0 | 4/53 | 4/105 | 0/0 | 1 | 0 |
| Four cases + switching controls; no GAB/QAT | focal_public_cue_cases | yes | -0.1359 | 0.0657 | [-0.2646, -0.0073] | 0 | 4/53 | 4/152 | 47/434 | 1 | 0 |

All four IFE fits use 1000 unit-bootstrap replications. Every reported row is the focal estimand: five treated cases in the base fits and four in the fits without Gabon/Qatar, which add Brazil. Non-focal countries never receive D = 1.

## Treatment-switch audit for the focal cases

| model_id | iso3c | public_cue_year | first_treated_year | last_treated_year | treated_years | entries | exits | off_years_after_first_entry | china_top_years_before_cue |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| clean_controls | AUS | 2009 | 2009 | 2022 | 14 | 1 | 0 | 0 | 0 |
| clean_controls | CHL | 2008 | 2008 | 2022 | 15 | 1 | 0 | 0 | 1 |
| clean_controls | GAB | 2017 | 2017 | 2022 | 6 | 1 | 0 | 0 | 0 |
| clean_controls | QAT | 2021 | 2021 | 2022 | 2 | 1 | 0 | 0 | 0 |
| clean_controls | URY | 2013 | 2013 | 2022 | 10 | 1 | 0 | 0 | 0 |
| full_switching | AUS | 2009 | 2009 | 2022 | 14 | 1 | 0 | 0 | 0 |
| full_switching | CHL | 2008 | 2008 | 2022 | 15 | 1 | 0 | 0 | 1 |
| full_switching | GAB | 2017 | 2017 | 2022 | 6 | 1 | 0 | 0 | 0 |
| full_switching | QAT | 2021 | 2021 | 2022 | 2 | 1 | 0 | 0 | 0 |
| full_switching | URY | 2013 | 2013 | 2022 | 10 | 1 | 0 | 0 | 0 |
| clean_controls_without_gab_qat | AUS | 2009 | 2009 | 2022 | 14 | 1 | 0 | 0 | 0 |
| clean_controls_without_gab_qat | BRA | 2009 | 2009 | 2022 | 14 | 1 | 0 | 0 | 0 |
| clean_controls_without_gab_qat | CHL | 2008 | 2008 | 2022 | 15 | 1 | 0 | 0 | 1 |
| clean_controls_without_gab_qat | URY | 2013 | 2013 | 2022 | 10 | 1 | 0 | 0 | 0 |
| full_switching_without_gab_qat | AUS | 2009 | 2009 | 2022 | 14 | 1 | 0 | 0 | 0 |
| full_switching_without_gab_qat | BRA | 2009 | 2009 | 2022 | 14 | 1 | 0 | 0 | 0 |
| full_switching_without_gab_qat | CHL | 2008 | 2008 | 2022 | 15 | 1 | 0 | 0 | 1 |
| full_switching_without_gab_qat | URY | 2013 | 2013 | 2022 | 10 | 1 | 0 | 0 | 0 |

## Scope notes

- The current stored goods-export panel first marks Australia China-top in 2009. The separate 2010 SDiD is nevertheless retained exactly as requested.
- The outcome extends to 2023, but the goods-export rank used to certify clean controls ends in 2022; 2023 is therefore excluded.
- The switching-control fit requested 159 units. `fect` retained 158. With `min.T0 = 1`, the only excluded unit is Mongolia (MNG), which has zero eligible observed control periods in the analysis window.
- The reduced switching-control fit requested 157 units after excluding Gabon and Qatar. `fect` retained 156. With `min.T0 = 1`, the only excluded unit is Mongolia (MNG), which has zero eligible observed control periods in the analysis window.
- Focal-case treatment exits in the switching-control specifications: full_switching=0; full_switching_without_gab_qat=0. Non-focal control availability changes are represented by masked country-years, not by additional treated units.
- Ordinary weighted-regression standard errors are not used for SDiD.
- No targets were created, rebuilt, or modified by this script.
