# Runtime log for the May 2026 targets recomputation

Source: `targets::tar_make(callr_function = NULL)` console output and
`targets::tar_meta()` inspected on 2026-05-21, America/Sao_Paulo timezone.

Pipeline outcome: 23 targets completed, 154 targets skipped, total elapsed time
1d 3h 50m 14.1s. The main computational bottleneck was the new SDiD diagnostic
table for the China-demand-shock critique.

## Major targets completed in this run

| Target | Completed at | Runtime | Notes |
|---|---:|---:|---|
| `se_synth_placebo2` | 2026-05-20 15:14:17 | 1h 47m 27s | SDiD placebo SE, 1,000 replications. |
| `se_synth_placebo_rank2_2004` | 2026-05-20 17:06:11 | 1h 51m 54s | China #2 threshold placebo SE, 1,000 replications. |
| `se_synth_placebo3` | 2026-05-20 19:00:18 | 1h 54m 07s | SDiD placebo SE, 1,000 replications. |
| `se_synth_no_time_varying_covariates` | 2026-05-20 20:41:07 | 1h 40m 48s | SDiD placebo SE, 1,000 replications. |
| `se_synth` | 2026-05-20 22:55:49 | 2h 14m 42s | Main SDiD placebo SE, 1,000 replications. |
| `se_synth_latam` | 2026-05-20 23:49:19 | 53m 31s | Latin America donor-pool SDiD placebo SE, 1,000 replications. |
| `se_synth_placebo1` | 2026-05-21 02:11:56 | 2h 22m 37s | SDiD placebo SE, 1,000 replications. |
| `se_synth_extended` | 2026-05-21 04:16:13 | 2h 04m 16s | Extended SDiD placebo SE, 1,000 replications. |
| `se_synth_baseline` | 2026-05-21 06:12:37 | 1h 56m 24s | Baseline SDiD placebo SE, 1,000 replications. |
| `fisher_test_result` | 2026-05-21 06:22:57 | 10m 17s | Fisher/randomization-style diagnostic. |
| `china_demand_sdid_diagnostics_table` | 2026-05-21 17:10:52 | 10h 47m 23s | New SDiD diagnostics for China share, concentration, rank margin, commodity exposure, and 2008-2009 interactions. |
| `fect_ife_china_top_cov_pre_distance_trim` | 2026-05-21 17:17:02 | 6m 09s | FECT/IFE robustness estimate after the SDiD diagnostics completed. |

## Short targets completed after the bottleneck

These targets completed quickly after `china_demand_sdid_diagnostics_table`:

- `goal3_brazil_placebo_rank_volume_tests`
- `china_top_fect_cov_pre_distance_trim_data`
- `china_top_pre_distance_trim_summary`
- `brazil_sdid_spec_table`
- `did_displaced_usa_cov`
- `plot_es_displaced_usa`
- `fect_ife_china_top_cov_pre_distance_trim_summary`

`wild_bootstrap_result` used 10,000 bootstrap replications and completed in
about 2.5 seconds in this run.

## Practical implication

The slowest reproducibility risk is not the full pipeline generally, but
`china_demand_sdid_diagnostics_table`: it wraps several SDiD specifications and
their placebo-based standard errors inside a single target. If this block needs
to be run often, it should be split into one fit/SE target pair per diagnostic
specification so partial progress is preserved across interruptions.
