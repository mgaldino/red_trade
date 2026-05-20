# Liu, Pang & Vreeland (2026) data reuse assessment

Generated: 2026-05-19 23:05:59 -03

## Source and collection

- Source: Harvard Dataverse DOI `https://doi.org/10.7910/DVN/MWAPWV`.
- Collection script: `scripts/data_collection/download_liu_pang_vreeland_2026_dataverse.py`.
- Raw data directory: `data/raw/external/liu_pang_vreeland_2026/`.
- Raw files were preserved unchanged; checksums are in `data/raw/external/liu_pang_vreeland_2026/checksums.sha256`.

## File inventory

- `alt_LoanasT.R`: replication code; type `type/x-r-syntax`; SHA256 `114fe071d63d513983a557aa2f5236680247d84bd03dca23cd3155415f4d1463`.
- `BRI_2020.tab`: BRI MoU timing data; type `text/tab-separated-values`; SHA256 `7430de5abb789d42bfdb8d3aa9e007f5e4c376ae79e6845a4264f1b60a9161eb`.
- `bsaNchina.csv`: non-China BSA dyads; type `text/comma-separated-values`; SHA256 `2fea5d60fffcf1b6b6d40680cf1f819ebacd538644c5966580ed7dc7f8783b1f`.
- `BSAupdate.RData`: main country-year analysis data; type `application/x-rlang-transport`; SHA256 `d27809197d2b7a1565ed2e3f8a3fb110aeeb931810f652258e9b7a6a2034dbdb`.
- `case_selection.R`: replication code; type `type/x-r-syntax`; SHA256 `d5d29ff86905dbfbf77be20a3acc5c5d6947b073d4630972e616f8343d62aeec`.
- `co_sponsorship.R`: replication code; type `type/x-r-syntax`; SHA256 `ae0dfe8a3088b6d0a7c2210875c8317b4afb205f9ba5a3d71855654c72b2a782`.
- `cosponsorship_data.RData`: other; type `application/x-rlang-transport`; SHA256 `58ecf7579a3644ba86de3c176de3a6ff0e45aefa398d83aefe392c8954bb1101`.
- `currency_converted.RData`: other; type `application/x-rlang-transport`; SHA256 `b6fc5dc4453110a0399d9288c21a04c04bab741be6642b140540c217af1d3c19`.
- `Data_SWAPNet_panel_202207.xlsx`: annual BSA network workbook; type `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`; SHA256 `36cfa92686286d07a3478e23b970c456842ae68398bd2254e96d1520fffc139a`.
- `IMF_program_data.csv`: IMF program data; type `text/comma-separated-values`; SHA256 `872ae347dcc93cd3766d7cdbb52d1abc84e07bba70e8631092390458d8bdf63b`.
- `ITT_confusion.csv`: case-level susceptibility classification; type `text/comma-separated-values`; SHA256 `a6475a9ca1a3af7fc0affc0553a6d542f932dee1b262c29b16fca0b707bed5a6`.
- `loanasT_data.RData`: other; type `application/x-rlang-transport`; SHA256 `d8384a8cc2469f50e9d1cae9f980e4f6dcf1d394d4dc1c9e14fe546739db0621`.
- `MainCode.R`: replication code; type `type/x-r-syntax`; SHA256 `14daed38dd32b9ab83d19d7a631ca805055fede6155223caea60af1c9805a3b6`.
- `plot_function2.R`: replication code; type `type/x-r-syntax`; SHA256 `f1a02aded0b62a00acc2715bc2d735f812598771477df6ff7c337c8d25e410d4`.
- `readme.txt`: other; type `text/plain`; SHA256 `5ace4b14b65bca1296595726fa7eb4689f5ae586c0b2eda76f76edae2295692b`.
- `regression.R`: replication code; type `type/x-r-syntax`; SHA256 `1524933b9bbf376d270ecd5cb20e863a3b5b79f759664039bf4a18ffa8a7fa4e`.
- `robustness_checks.R`: replication code; type `type/x-r-syntax`; SHA256 `f5b89e7002d32281ff7d33af442ec8a4d0d19edca67236d097f8272a74422745`.
- `summary_function.R`: replication code; type `type/x-r-syntax`; SHA256 `b5e08f53c34794558974cb6a1bfc6b37d55fba487fb019250dea418df9c04122`.
- `visualization.R`: replication code; type `type/x-r-syntax`; SHA256 `4085b85297ebf68b0943804391be6a27e9dfb2e78342e00a9b9e072922edc8aa`.

## Variables identified

| File | Variable(s) | Unit | Coverage/timing | Time-varying? | Reuse assessment |
|---|---|---|---|---|---|
| `BSAupdate.RData` | `swap_dummy`, `swap_dummy_lag1`, `signdate` | country-year | 1992-2021; BSA dates 2009-2021 in raw rows | yes | Do not use as moderator for this paper; it is the LPV treatment, not a pre-treatment receptivity variable for trade-onset. |
| `BSAupdate.RData` | `partner_level`, `partner_level_lag1`, `level_raw` | country-year | 1992-2021; 5,560 non-missing lagged country-years | yes | Usable as `pre_entry_partner_level = partner_level_lag1` at my `t0`; use only as robustness because it proxies political closeness to China. |
| `BSAupdate.RData` | `high_level_partner = partner_level >= 4` | country-year | Derived from LPV threshold for comprehensive cooperation partnership or above | yes | Usable as pre-treatment robustness if measured at `t0 - 1`; not as post-entry/ever high-level status. |
| `BRI_2020.tab` | `year`, `countryname`, `region` | country event | 138 country-years, 2014-2020 | event timing | Only `bri_mou_year < t0` is admissible. `ever BRI` or `bri_mou_year <= post` would be post-treatment for most treated countries. |
| `Data_SWAPNet_panel_202207.xlsx` | BSA dyads by annual sheet | dyad-year/network | 2008-2020 sheets plus `World` | yes | Useful for LPV BSA replication, not directly needed for the trade-onset moderator. |
| `ITT_confusion.csv` | `Comprehensive_Partner`, `BRI`, `year_BSA`, `susceptible` | BSA case | 37 LPV BSA cases | mostly static/case-level | Not reusable for my panel because it is restricted to BSA cases and partly post-treatment relative to trade entry. |

## Crosswalk to my treatment entries

- Treated countries in the China-top panel: 59.
- Treatment entry/onset years: 2000-2021.
- `pre_entry_partner_level` coverage: 59/59.
- Countries with `pre_entry_high_level_partner == 1`: 12.
- Countries with any BRI MoU observed in LPV file: 50.
- Countries with BRI MoU strictly before `t0`: 10.
- Countries with BRI MoU only after `t0`: 40.

### Distribution of pre-entry partner level

- level 0: 1
- level 1: 45
- level 2: 1
- level 4: 2
- level 6: 3
- level 7: 1
- level 8: 3
- level 9: 2
- level 10: 1

## Post-treatment bias assessment

- `partner_level_lag1` is admissible only when read on the row for `t0`, because it equals the previous-year partnership level. This avoids conditioning on partnership upgrades after China becomes the top export destination.
- `partner_level` at `t0` is less conservative because the partnership status in the entry year can be contemporaneous with or after trade entry. The diagnostic CSV therefore uses `partner_level_lag1` at `t0`.
- `high_level_partner` is admissible only as `pre_entry_high_level_partner = partner_level_lag1 >= 4` at `t0`.
- `BRI` is high risk if coded as ever signatory. In this panel, most observed BRI MoUs occur after `t0`, so the valid version is `pre_entry_bri_mou = bri_mou_year < t0`.

## Recommendation

- Use `pre_entry_partner_level` or `pre_entry_high_level_partner` only as robustness diagnostics, not as the main moderator. They are temporally usable, but conceptually close to the political-alignment mechanism.
- Do not use LPV's case-level `Comprehensive_Partner` and `BRI` columns from `ITT_confusion.csv` in this panel.
- Do not use `ever BRI MoU`; if used at all, use only `pre_entry_bri_mou`, and interpret cautiously because only 10 treated countries satisfy it before trade entry.

## Files written

- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/data/processed/diagnostics/vreeland_pre_entry_moderators_2026-05-19.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/reports/incumbent_salience_vreeland_reuse_2026-05-19/vreeland_data_files_inventory.csv`
- `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/reports/incumbent_salience_vreeland_reuse_2026-05-19/vreeland_data_reuse_assessment.md`
