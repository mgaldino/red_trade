#!/usr/bin/env bash
# Overnight reproducibility rebuild for paper_v4, in one sitting.
#
# Context (2026-08-23/25). Two corrections put the store out of date with the
# manuscript. First, the preferred Brazil SDiD dropped its unit-level fixed
# covariate arrays (not separately identified from the SDiD unit fixed
# effects; coefficients numerically zero). Second, the donor-eligibility
# screen ranked trade partners on TOTAL trade while the paper defines
# treatment on GOODS exports, which left Malta -- China's top goods
# destination in 2011-2012, inside Brazil's post-period -- in the donor pool,
# and kept Singapore out for the mirror reason. This rebuilds everything from
# the pipeline so the paper is reproducible end to end.
#
# It also carries a third change: se_sdid() draws its placebo permutations
# once from the seed and evaluates them in parallel. Replications: 20,000 for
# the preferred no-covariate column (cheap; the SE estimator itself is noisy
# at 1,000: five independent blocks spanned 0.1262-0.1355, moving p between
# 0.031 and 0.045) and 5,000 for the covariate comparison columns (each of
# their replications re-solves the covariate coefficients, ~1.6 s/replication
# on 12 cores).
#
# WHY THIS IS A LOOP. This script used to carry its own copy of the stages.
# The two entry points then drifted: the batch runner grew a donor-pool gate,
# a batch-coverage check and an extended-window stage that this file never
# got, so the same repository produced two different stores depending on which
# command you ran. Delegating makes them equivalent by construction -- there
# is exactly one definition of what the rebuild does, in run_rebuild_batch.sh.
#
# Usage:   bash scripts/run_reproducibility_rebuild.sh
# Logs:    output/rebuild_batches/<batch>_<timestamp>.log
# Runtime: roughly 7-8 hours; the covariate comparison columns dominate.
#          Safe to leave unattended: each batch logs separately, the script
#          stops at the first failure, targets caches completed work, and the
#          placebo/rank checkpoints resume, so re-running the same command
#          after an interruption continues instead of restarting.
#
# NOT included: the opt-in `legacy` batch (~5 h), which rebuilds exploratory
# targets from earlier drafts that feed no number in the manuscript. Run it
# separately with `bash scripts/run_rebuild_batch.sh legacy` if you want the
# whole store under one screen.

set -euo pipefail
cd "$(dirname "$0")/.."

RUNNER="scripts/run_rebuild_batch.sh"
[ -f "$RUNNER" ] || { echo "missing $RUNNER" >&2; exit 1; }

# The running order is defined once, in the runner. Read it rather than
# repeating it here, so this file cannot fall behind again.
# Deliberately not mapfile: macOS ships bash 3.2, where it does not exist.
BATCH_LIST="$(sed -n 's/^BATCHES=(\(.*\))$/\1/p' "$RUNNER")"
# shellcheck disable=SC2206
BATCHES=($BATCH_LIST)
[ "${#BATCHES[@]}" -gt 0 ] || { echo "could not read BATCHES from $RUNNER" >&2; exit 1; }

echo "Rebuild stages, in order:"
for b in "${BATCHES[@]}"; do
  [ "$b" = "legacy" ] && continue
  echo "  - $b"
done
echo

for b in "${BATCHES[@]}"; do
  [ "$b" = "legacy" ] && continue
  bash "$RUNNER" "$b"
done

echo
echo "Reproducibility rebuild complete. Paper: output/paper_v4.pdf"
echo "Optional: bash $RUNNER legacy   (~5 h, exploratory targets only)"
