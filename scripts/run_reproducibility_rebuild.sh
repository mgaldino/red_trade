#!/usr/bin/env bash
# Overnight reproducibility rebuild for paper_v4.
#
# Context (2026-08-23/24): the preferred Brazil SDiD dropped its unit-level
# fixed covariate arrays (not separately identified from the SDiD unit fixed
# effects; coefficients numerically zero). The manuscript text was updated
# immediately, but the targets store, the commodity/China-demand diagnostics
# behind Table 5, and the UNGA-DM robustness artifacts still hold values
# produced under the old specification. This script rebuilds everything from
# the pipeline so the paper is reproducible end to end.
#
# It also carries a second change: se_sdid() draws its placebo permutations
# once from the seed and evaluates them in parallel. Replications: 20,000 for
# the preferred no-covariate column (cheap; the SE estimator itself is noisy
# at 1,000: five independent blocks spanned 0.1262-0.1355, moving p between
# 0.031 and 0.045) and 5,000 for the covariate comparison columns (each of
# their replications re-solves the covariate coefficients, ~1.6 s/replication
# on 12 cores).
#
# Usage:   bash scripts/run_reproducibility_rebuild.sh
# Logs:    output/rebuild_<timestamp>/
# Runtime: roughly 9-11 hours; the covariate comparison columns dominate.
#          Safe to leave unattended: each stage logs separately, the script
#          stops at the first failure, targets caches completed work, and the
#          placebo/rank checkpoints resume, so re-running the same command
#          after an interruption continues instead of restarting.

set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the machine awake for the duration on macOS.
if command -v caffeinate >/dev/null 2>&1 && [ -z "${REBUILD_CAFFEINATED:-}" ]; then
  export REBUILD_CAFFEINATED=1
  exec caffeinate -i "$0" "$@"
fi

export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8
# One BLAS thread per process, set BEFORE R starts (an already-loaded BLAS
# ignores changes made from inside R): the placebo loops are already parallel.
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1

STAMP="$(date +%Y%m%d_%H%M%S)"
LOGDIR="output/rebuild_${STAMP}"
mkdir -p "$LOGDIR"

say() { printf '\n=== [%s] %s ===\n' "$(date +%H:%M:%S)" "$1" | tee -a "$LOGDIR/00_summary.log"; }
stage() {
  local name="$1"; shift
  say "START $name"
  if "$@" >"$LOGDIR/$name.log" 2>&1; then
    say "OK    $name"
  else
    say "FAIL  $name  (see $LOGDIR/$name.log)"
    tail -20 "$LOGDIR/$name.log" | tee -a "$LOGDIR/00_summary.log"
    exit 1
  fi
}

say "Rebuild started. Logs in $LOGDIR"

# 1. Restore the recorded environment. duckdb is a real dependency
#    (scripts/functions.R, ITPD-E goods aggregation) and is currently missing,
#    which makes every target fail to build. Record the environment state.
stage 01_renv_restore Rscript -e 'renv::restore(prompt = FALSE)'
stage 01b_env_record Rscript -e 'writeLines(capture.output({print(renv::status()); print(sessionInfo())}), file.path("'$LOGDIR'", "environment.txt"))'

# 1c. Validate that the parallel placebo algorithm reproduces the package's
#     serial one (seconds; documents the equivalence in the replication trail).
stage 01c_validate_placebo Rscript scripts/diagnostics/validate_parallel_synthdid_placebo.R

# 1d. Fail fast on syntax/manifest problems before any expensive stage: parse
#     the pipeline definition and the sourced function files, and build the
#     targets manifest (catches a broken _targets.R in seconds, not hours).
stage 01d_parse_pipeline Rscript -e 'invisible(parse("_targets.R")); invisible(parse("scripts/functions.R")); invisible(parse("scripts/diagnostics/sdid_placebo_helpers.R")); m <- targets::tar_manifest(callr_function = NULL); source("scripts/rebuild_targets.R"); missing <- setdiff(rebuild_target_names(), m$name); if (length(missing) > 0) stop("rebuild targets absent from the manifest: ", paste(missing, collapse = ", ")); cat("pipeline parses; manifest has", nrow(m), "targets; rebuild list fully covered\n")'

# 2. Rebuild the targets the manuscript and the diagnostic scripts consume.
#    The list is derived programmatically from the tar_read() calls in
#    paper_v4.Rmd (scripts/rebuild_targets.R), so it cannot drift from the
#    paper. A bare tar_make() would also try to rebuild unrelated exploratory
#    targets that have been failing since earlier work and would abort the run.
#    Because se_sdid() changed, every placebo SE target is invalidated and
#    recomputed; that is intended.
stage 02_targets Rscript -e 'source("scripts/rebuild_targets.R"); targets::tar_make(names = tidyselect::any_of(rebuild_target_names()))'

# 3. Regenerate the no-covariate diagnostic package that the manuscript reads.
#    It reuses the freshly built target SE, so the CSVs cannot drift from
#    Table 3.
stage 03_sdid_diagnostics Rscript scripts/diagnostics/audit_brazil_sdid_no_covariates.R

# 4. Recompute the commodity / China-demand family (Table 5) under the
#    no-covariate preferred specification (common permutation seed across
#    rows; preferred row reuses the pipeline SE).
stage 04_commodity_table5 Rscript scripts/diagnostics/audit_brazil_sdid_commodity_no_covariates.R

# 5. Re-run the UNGA-DM measurement-robustness estimation under the
#    no-covariate specification (SDiD columns share the pipeline's replication
#    count and seed; IFE common-window comparison at 10,000 bootstraps).
stage 05_ungadm_estimation Rscript scripts/diagnostics/audit_ungadm_outcome_robustness.R

# 6. Re-run the post-review UNGA-DM diagnostics (2x2 fixed-r grid, paired
#    bootstrap, divergence tables, harmonized rank criterion).
stage 06_ungadm_postreview Rscript scripts/diagnostics/audit_ungadm_postreview_diagnostics.R

# 7. Consistency invariant: text, Table 3, and Table 5 must report the same
#    SE and p for the preferred specification. Fails loudly if they diverge.
stage 07_consistency Rscript -e '
  se_t <- as.numeric(targets::tar_read(se_synth_no_time_varying_covariates))[1]
  ms <- readr::read_csv("data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/main_summary.csv", show_col_types = FALSE)
  t5 <- readr::read_csv("data/processed/diagnostics/brazil_sdid_commodity_no_covariates/table_5_sdid_specification_results.csv", show_col_types = FALSE)
  se_c <- ms$se_placebo[1]
  se_5 <- t5$se_placebo[t5$specification == "no_covariates"][1]
  ungadm <- readr::read_csv("data/processed/diagnostics/ungadm_outcome_robustness/estimation/sdid_comparison_table.csv", show_col_types = FALSE)
  se_u <- ungadm$se_placebo[grepl("^BSV", ungadm$outcome_source)][1]
  cat(sprintf("target=%.8f  main_summary=%.8f  tabela5=%.8f  ungadm_bsv=%.8f\n", se_t, se_c, se_5, se_u))
  stopifnot(isTRUE(all.equal(se_t, se_c, tolerance = 1e-10)),
            isTRUE(all.equal(se_t, se_5, tolerance = 1e-10)),
            isTRUE(all.equal(se_t, se_u, tolerance = 1e-10)),
            "smoke_test" %in% names(t5), !any(t5$smoke_test %in% TRUE))'

# 8. Render against the restored renv library and record the session.
stage 08_render bash scripts/render_paper_v4.sh

say "Rebuild finished."
say "Next: read $LOGDIR/07_consistency.log, spot-check the PDF, and update PENDING.md."
