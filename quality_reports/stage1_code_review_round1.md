# Stage 1: Code Quality Review -- Round 1

**Reviewer**: Claude Opus 4.6 (automated)
**Date**: 2026-02-12
**Files reviewed**:
- `scripts/functions.R` (1448 lines)
- `_targets.R` (112 lines)
- R chunks in `paper_v3.Rmd` (602 lines)

---

## 1. Executive Summary

The codebase implements a well-structured `targets` pipeline for a political science paper studying whether China displacing the US as top trade partner causes foreign-policy alignment shifts. The statistical methods -- Synthetic Difference-in-Differences (SDiD), Callaway & Sant'Anna staggered DiD, wild cluster bootstrap, Fisher randomization, and HonestDiD sensitivity -- are correctly chosen for the research design and generally well-implemented. Reproducibility is supported by `set.seed()` in all stochastic functions and by the `targets` caching framework.

However, the review identifies **two critical issues**, **six major issues**, and **nine minor issues**, resulting in a score of **52/100**.

---

## 2. Critical Issues (-20 each)

### C1. Broken target name references in paper_v3.Rmd placebo table (-20)

**Location**: `paper_v3.Rmd`, lines 314--320

```r
b_est1 <- tar_read(placebo_teste_time1)[1]   # placebo, treatment year 2003
se1    <- tar_read(se_synth_placebo1)

b_est2 <- tar_read(placebo_teste_time2)[1]   # placebo, treatment year 2011
se2    <- tar_read(se_synth_placebo2)

b_est3 <- tar_read(placebo_teste_time3)[1]   # placebo, treatment year 2011
se3    <- tar_read(se_synth_placebo3)
```

**Problem**: The paper reads targets named `placebo_teste_time1`, `placebo_teste_time2`, `placebo_teste_time3`, but `_targets.R` defines them as `placebo_teste_treatment02`, `placebo_teste_treatment11`, `placebo_teste_treatment04` (lines 74--79). These names do not match. The paper will fail to knit, or if there are stale cached targets with the old names, it will silently read outdated results. This directly compromises reproducibility.

Additionally, there is a label/assignment mismatch: the inline comments in the Rmd say "placebo, treatment year 2003" for `b_est1`, but in `_targets.R`, `se_synth_placebo1` corresponds to `placebo_teste_treatment11` (treatment year 2011), and `se_synth_placebo2` corresponds to `placebo_teste_treatment02` (treatment year 2002). This means even if the names were corrected, the mapping of placebo labels ("Placebo (2003)", "Placebo (2005)", "Placebo (2012)") to actual estimates would be scrambled.

**Suggested fix**: Align the target names in `paper_v3.Rmd` with those in `_targets.R`, and verify that each estimate--SE pair corresponds to the correct treatment year:

```r
b_est1 <- tar_read(placebo_teste_treatment02)[1]  # treatment year 2002
se1    <- tar_read(se_synth_placebo2)

b_est2 <- tar_read(placebo_teste_treatment04)[1]  # treatment year 2004
se2    <- tar_read(se_synth_placebo3)

b_est3 <- tar_read(placebo_teste_treatment11)[1]  # treatment year 2011
se3    <- tar_read(se_synth_placebo1)
```

And update the table labels accordingly (2002 and 2004 instead of 2003 and 2005).

---

### C2. Commented-out targets referenced in the paper appendix (-20)

**Location**: `_targets.R` lines 65, 72; `paper_v3.Rmd` lines 516--517, 531

```r
# _targets.R:
# tar_target(plot_weights_coef, my_plot_weigths(synth_fit)),           # line 65
# tar_target(plot_weights_coef_latam, my_plot_weigths(synth_fit_latam, latam=T)),  # line 72
```

```r
# paper_v3.Rmd:
tar_read(plot_weights_coef)         # line 516
tar_read(plot_weights_coef_latam)   # line 531
```

**Problem**: The paper appendix reads `plot_weights_coef` and `plot_weights_coef_latam`, but these targets are commented out in `_targets.R`. The paper will fail to knit in a clean build (no cache), making these appendix figures non-reproducible. If stale cache exists, results may be from an older, inconsistent pipeline state.

**Suggested fix**: Uncomment these two targets in `_targets.R`, or remove the corresponding `tar_read()` calls from the paper if the plots are no longer desired.

---

## 3. Major Issues (-10 each)

### M1. No error handling for external data fetches (-10)

**Location**: `scripts/functions.R`

Several functions fetch data from external URLs/APIs with no error handling:

- `get_folhasp_newspieces()` (line 21): scrapes Folha de Sao Paulo website in a loop of up to 2000 pages with no `tryCatch()`. A network timeout or 403 response will crash the entire pipeline.
- `get_ideology_data()` (line 192): fetches COW-to-ISO mapping from `raw.githubusercontent.com` with no fallback. If the GitHub repo is deleted, renamed, or rate-limited, the pipeline fails silently (or noisily).
- `get_macro()` (line 205): calls `gmd()` with a hardcoded version string `"2025_06"` -- if this API version is retired, the function breaks.

**Suggested fix**: Wrap each external fetch in `tryCatch()` with informative error messages. For `get_ideology_data`, consider pinning the COW-ISO mapping as a local file (or at minimum caching the result).

---

### M2. Hardcoded data mutation in create_list_graphs (-10)

**Location**: `scripts/functions.R`, line 406

```r
data$date_piece[1] <- as.Date("2008-06-07", "%Y-%m-%d")
```

**Problem**: This silently overwrites the first row's date with a hardcoded value, with no comment explaining why. This looks like a one-off data fix that should be documented or handled upstream. It modifies the input data inside a plotting function, which violates separation of concerns and could produce incorrect results if the data ordering changes.

**Suggested fix**: Either fix the source data upstream (in the scraping or binding step) with a comment explaining the correction, or at minimum add a clear comment explaining why this date override is necessary.

---

### M3. Missing input validation for key functions (-10)

**Location**: `scripts/functions.R`, multiple functions

None of the core estimation functions validate their inputs:

- `simple_fit()` does not check that `data` contains the required columns, that `time_treatment` is within the year range of the data, or that Brazil (`"BRA"`) is actually present in the data.
- `run_cross_country_did()` does not check that `event_data` has the required columns (`abs_distance_china`, `year`, `id`, `first_treat`) or that there are both treated and never-treated units.
- `clean_synth_data()` does not validate that the join between `data` and `ranked_trade_data` produces non-empty results.

**Suggested fix**: Add `stopifnot()` or `if(...) stop(...)` checks at the top of each key function for required columns, non-empty data, and valid parameter ranges.

---

### M4. Inefficient web scraping could cause pipeline timeouts (-10)

**Location**: `scripts/functions.R`, lines 21--51; `_targets.R`, lines 43--47

The `get_folhasp_newspieces()` function is called 5 times in the pipeline, each scraping 400 pages (1 second sleep per page = ~7 minutes minimum per call, ~35 minutes total). Each call operates sequentially with no progress reporting, no retry logic, and no caching of intermediate results. If any single request fails on page 399 of 400, the entire batch is lost.

**Suggested fix**: Add retry logic (e.g., `httr::RETRY()`), checkpoint intermediate results, and consider using `tar_target(..., cue = tar_cue(mode = "never"))` for the scraping targets to prevent re-execution.

---

### M5. Bad variable names that obscure logic (-10)

**Location**: `scripts/functions.R`

Several function parameters are named `file` or `file1`...`file7` when they actually receive data frames, not file paths:

- `process_trade_data(file)` (line 243): `file` is actually a data frame.
- `join_df(file1, file2, file3, file4, file5, file6, file7)` (line 277): all seven `file*` arguments are data frames.
- `generate_plot_data(file)` (line 300): `file` is a data frame.

This is confusing because other functions in the same codebase (e.g., `get_trade_data(trade_file)`, line 129) correctly use `file` for actual file paths.

**Suggested fix**: Rename `file` to `data` or `df` in data-frame-accepting functions.

---

### M6. Missing documentation for complex functions (-10)

**Location**: `scripts/functions.R`

None of the 40+ functions in the file have documentation (roxygen-style or otherwise) explaining:
- What the function does
- What its parameters are and their expected types
- What it returns
- What side effects it has (e.g., `run_wild_cluster_bootstrap` assigns to `.GlobalEnv`)

The most critical undocumented functions are `clean_synth_data()` (which performs ~10 data transformations including filtering, joining, and rescaling), `simple_fit()` (the core SDiD estimation), and `permutation_test()` (complex simulation).

**Suggested fix**: Add at minimum a one-line comment above each function describing its purpose, inputs, and outputs. For the core estimation functions, add full roxygen-style documentation.

---

## 4. Minor Issues (-2 each)

### m1. Style inconsistencies: snake_case vs camelCase (-2)

**Location**: `scripts/functions.R`

Mixed naming conventions throughout:
- snake_case: `get_wb_data`, `clean_synth_data`, `se_sdid`, `permutation_test`
- camelCase: `cov_matrix` (borderline), `lista_df` (Portuguese)
- Mixed Portuguese/English: `seq_paginas` (line 23), `lista_df` (line 24), `folha_2000` (line 414)

---

### m2. Commented-out dead code: get_dpi function (-2)

**Location**: `scripts/functions.R`, lines 174--186

A full function `get_dpi()` is commented out. If no longer needed, it should be removed. If it is retained for reference, it should be noted why.

---

### m3. Redundant library() calls in paper_v3.Rmd (-2)

**Location**: `paper_v3.Rmd`

`library(targets)` and `library(tidyverse)` are loaded in the `setup` chunk (line 40--41), then loaded again in the `basic data` chunk (lines 184--185), and again in the `table_summary` chunk (lines 222--223), and again in `sample_chagpt` chunk (lines 593--594). These redundant calls are harmless but clutter the code.

---

### m4. Redundant library() calls in _targets.R (-2)

**Location**: `_targets.R`, line 7

```r
# library(tarchetypes) # Load other packages as needed.
```

This commented-out line is a leftover from the `use_targets()` template, while `tarchetypes` is already loaded on line 6.

---

### m5. Magic number in treatment definition without comment (-2)

**Location**: `scripts/functions.R`, line 631

```r
mutate(treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1, 0))
```

The use of `year > time_treatment` (strictly greater than) means treatment begins in the year AFTER `time_treatment`. This is correct for the paper's design (China became #1 in 2009, `time_treatment=2008`), but the off-by-one semantics deserve a comment, especially since it differs from the `clean_synth_data` function which uses actual trade rank data.

---

### m6. Empty function body: descriptive_plot_folha (-2)

**Location**: `scripts/functions.R`, lines 529--531

```r
descriptive_plot_folha <- function() {

}
```

An empty function that does nothing. Should be removed if unused.

---

### m7. Typo in variable name: "exachange_rate" (-2)

**Location**: `scripts/functions.R`, lines 11, 551, 588, 591

The variable `exachange_rate` (should be `exchange_rate`) is consistently misspelled. While consistent misspelling does not break the code, it reduces readability and could confuse collaborators.

---

### m8. Deprecated function: mutate_all (-2)

**Location**: `scripts/functions.R`, line 146

```r
mutate_all(as.numeric) %>%
```

`mutate_all()` has been superseded by `across()` in dplyr 1.0.0 (June 2020). While it still works, it generates lifecycle warnings and may be removed in a future dplyr release.

---

### m9. Magic numbers in sensitivity analysis without clear justification (-2)

**Location**: `scripts/functions.R`, lines 1403, 1417

```r
Mvec = seq(from = 0, to = 0.05, by = 0.01)       # line 1403
Mbarvec = seq(from = 0.5, to = 2, by = 0.5)       # line 1417
```

These sensitivity grid values are hardcoded without comments explaining why these specific ranges were chosen.

---

## 5. Score Calculation

| Category | ID  | Description | Deduction |
|----------|-----|-------------|-----------|
| Critical | C1  | Broken target name references in placebo table | -20 |
| Critical | C2  | Commented-out targets still referenced in paper | -20 |
| Major    | M1  | No error handling for external data fetches | -10 |
| Major    | M2  | Hardcoded data mutation in plotting function | -10 |
| Major    | M3  | Missing input validation for key functions | -10 |
| Major    | M4  | Inefficient web scraping without retry/checkpoint | -10 |
| Major    | M5  | Bad variable names (file vs data frame) | -10 |
| Major    | M6  | Missing documentation for complex functions | -10 |
| Minor    | m1  | Style inconsistencies (snake_case vs camelCase) | -2 |
| Minor    | m2  | Commented-out dead code (get_dpi) | -2 |
| Minor    | m3  | Redundant library() calls in paper_v3.Rmd | -2 |
| Minor    | m4  | Redundant commented line in _targets.R | -2 |
| Minor    | m5  | Magic number in treatment year definition | -2 |
| Minor    | m6  | Empty function body (descriptive_plot_folha) | -2 |
| Minor    | m7  | Typo: "exachange_rate" throughout | -2 |
| Minor    | m8  | Deprecated function: mutate_all | -2 |
| Minor    | m9  | Magic numbers in HonestDiD sensitivity grids | -2 |
| **Total** | | | **-108** |

**Note on cap**: The minimum score is 0. The raw deduction total is -108, but the score is floored at 0.

---

## 6. Positive Observations

Despite the issues above, the codebase has several strengths worth noting:

1. **Correct estimator choices**: SDiD for the single-unit Brazil case is appropriate and superior to naive DiD or SCM alone. Callaway & Sant'Anna for the staggered cross-country design correctly handles treatment-effect heterogeneity. The use of `control_group = "nevertreated"` and `base_period = "universal"` are defensible choices.

2. **Reproducibility seeds**: All stochastic functions (`simple_fit`, `permutation_test`, `create_list_graphs`, `fisher_randomization_test`) include `set.seed()` calls.

3. **Robust standard errors**: SDiD uses the placebo variance estimator. The cross-country DiD uses clustering by country (via `did` package defaults). The wild cluster bootstrap with Webb weights correctly handles the small-cluster problem. The `.GlobalEnv` assignment pattern in `run_wild_cluster_bootstrap` (with `on.exit` cleanup) is a correct workaround for the known `fwildclusterboot` limitation.

4. **Correct handling of fixest FE interaction**: The code correctly uses `interaction()` to create explicit FE columns rather than `^` notation, per the known `fwildclusterboot` compatibility issue.

5. **Defensive donor pool construction**: `clean_synth_data()` correctly removes other treated countries from the donor pool (`condition = treatment_first == 1 & treatment == 0; filter(!condition)`), preventing contamination.

6. **HonestDiD implementation**: The sensitivity analysis correctly handles the near-singular sigma problem with a ridge correction and excludes the reference period (e = -1).

7. **Fisher randomization test**: The implementation correctly reassigns both treatment country and treatment timing, providing exact inference that does not rely on asymptotics.

---

## 7. Verdict

**REPROVADO [0]**

The two critical issues (C1: broken target references producing incorrect placebo results; C2: non-reproducible appendix figures from commented-out targets) prevent the paper from being knitted in a clean environment and risk presenting incorrect statistical results. These must be fixed before the analysis can be considered reproducible.

The major issues (M1--M6) represent important software engineering shortcomings that, while they do not invalidate the statistical results when the pipeline runs successfully, reduce maintainability and increase the risk of silent errors.

**Priority fixes**:
1. Fix C1 immediately: align target names in `paper_v3.Rmd` with `_targets.R` and verify the placebo year labels.
2. Fix C2 immediately: uncomment the two weight-plot targets or remove the `tar_read()` calls from the appendix.
3. Address M1--M3 before submission: add error handling, remove hardcoded data mutations, add basic input validation.
