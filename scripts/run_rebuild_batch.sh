#!/usr/bin/env bash
# Reproducibility rebuild, one batch at a time.
#
# Why this exists (2026-08-25). run_reproducibility_rebuild.sh does the whole
# rebuild in one ~7-9h run. This machine cannot sit on that, so the same work
# is split into batches that each finish in roughly an hour. Every batch is
# resumable and idempotent: targets caches completed work, the placebo and
# rank checkpoints resume mid-computation, and re-running a finished batch is
# a no-op that costs seconds.
#
# What is being rebuilt. The SDiD donor-eligibility screen now ranks partners
# on GOODS exports, the same definition that defines treatment. It used to
# rank on total trade, which let Malta (China's top goods destination in
# 2011-2012, but only third once services count) sit in the donor pool with
# 3.0% weight, and excluded Singapore for the mirror reason. The cross-country
# IFE panel already used the goods ranking and is NOT affected: tar_outdated()
# confirms its targets stay up to date, which is why this rebuild is shorter
# than the previous one.
#
# Usage:
#   bash scripts/run_rebuild_batch.sh list      # batches, order, estimates
#   bash scripts/run_rebuild_batch.sh status    # what is done, what remains
#   bash scripts/run_rebuild_batch.sh next      # run the next pending batch
#   bash scripts/run_rebuild_batch.sh data      # run one batch by name
#
# Run them in listed order. `data` is the gate: it is cheap and it verifies
# the corrected donor pool before any hour-long batch starts.

set -euo pipefail
cd "$(dirname "$0")/.."

STATEDIR="output/rebuild_batches"
STATE="$STATEDIR/STATE.tsv"
mkdir -p "$STATEDIR"
[ -f "$STATE" ] || printf 'batch\tstatus\tfinished_at\tduration\n' > "$STATE"

# Ordered batch list, with rough wall-clock estimates for planning a sitting.
BATCHES=(prep data se_1 se_2 se_3 core diagnostics table5 ungadm ungadm_post render extended legacy)
declare -a ESTIMATES=(
  "~10 min   renv restore, parallel-placebo validation, pipeline parse"
  "~10 min   goods ranking, donor pool, fits + DONOR POOL INVARIANT CHECK"
  "~1 h      se_synth (covariate spec, 5,000 replications)"
  "~1 h      se_synth_latam (covariate spec, 5,000 replications)"
  "~1 h      se_synth_baseline (covariate spec, 5,000 replications)"
  "~25 min   preferred SE at 20,000, spec table, DDD and vote-level models"
  "~25 min   no-covariate diagnostic package (Table 3, placebo figure)"
  "~1.5 h    commodity / China-demand family behind Table 5"
  "~40 min   UNGA-DM measurement robustness"
  "~1 h      UNGA-DM post-review diagnostics + consistency invariant"
  "~10 min   render paper_v4.pdf"
  "~1 h      extended-window family; store consistency, no manuscript number"
  "~5 h      OPT-IN legacy placebo/permutation family; feeds no manuscript number"
)

# The two arrays are addressed by the same index; inserting into one alone
# would silently misdescribe every batch after the insertion point.
if [ "${#BATCHES[@]}" -ne "${#ESTIMATES[@]}" ]; then
  echo "BATCHES (${#BATCHES[@]}) and ESTIMATES (${#ESTIMATES[@]}) are out of sync." >&2
  exit 3
fi

batch_index() {
  local i=0
  for b in "${BATCHES[@]}"; do [ "$b" = "$1" ] && { echo "$i"; return 0; }; i=$((i+1)); done
  return 1
}
# The LAST recorded run decides, not any past success. A batch that passed
# yesterday and failed today is not done: with an OR over every record, `next`
# would skip it and build later batches on top of a failed one.
is_done() { awk -F'\t' -v b="$1" '$1==b{s=$2} END{exit !(s=="OK")}' "$STATE"; }

cmd_list() {
  printf '\n  #  batch          estimate  contents\n'
  printf '  -- -------------- --------- ------------------------------------------------\n'
  local i=0
  for b in "${BATCHES[@]}"; do
    local mark=" "; is_done "$b" && mark="x"
    printf '  [%s] %-14s %s\n' "$mark" "$b" "${ESTIMATES[$i]}"
    i=$((i+1))
  done
  printf '\n  Run in this order. [x] = already completed.\n\n'
}

cmd_status() {
  cmd_list
  local pending=""
  for b in "${BATCHES[@]}"; do is_done "$b" || { pending="$b"; break; }; done
  if [ -z "$pending" ]; then
    printf '  All batches complete.\n\n'
  else
    printf '  Next: bash scripts/run_rebuild_batch.sh %s\n\n' "$pending"
  fi
  [ "$(wc -l < "$STATE")" -gt 1 ] && { printf '  Recorded runs:\n'; column -t -s $'\t' "$STATE" | sed 's/^/    /'; printf '\n'; }
  return 0
}

# --- everything below only runs when a real batch was requested -------------

BATCH="${1:-status}"
case "$BATCH" in
  list)   cmd_list;   exit 0 ;;
  status) cmd_status; exit 0 ;;
  next)
    BATCH=""
    for b in "${BATCHES[@]}"; do is_done "$b" || { BATCH="$b"; break; }; done
    [ -z "$BATCH" ] && { echo "All batches complete."; exit 0; }
    echo "Next pending batch: $BATCH"
    ;;
esac

if ! batch_index "$BATCH" >/dev/null; then
  echo "Unknown batch '$BATCH'." >&2
  cmd_list >&2
  exit 2
fi

# A previous tar_make() can leave a stale lock in _targets/meta/process if its
# parent was killed while the callr child kept running. Detect it up front.
if [ -f _targets/meta/process ]; then
  STALE_PID="$(awk -F'|' '$1=="pid"{print $2}' _targets/meta/process 2>/dev/null || true)"
  if [ -n "${STALE_PID:-}" ]; then
    if ps -p "$STALE_PID" >/dev/null 2>&1; then
      echo "A targets pipeline (PID $STALE_PID) is already using this store." >&2
      echo "Terminate it, or run targets::tar_unblock_process(), then retry." >&2
      exit 1
    fi
    echo "Clearing stale targets lock from dead PID $STALE_PID."
    rm -f _targets/meta/process
  fi
fi

# Keep the machine awake for the duration on macOS.
if command -v caffeinate >/dev/null 2>&1 && [ -z "${REBUILD_CAFFEINATED:-}" ]; then
  export REBUILD_CAFFEINATED=1
  exec caffeinate -i bash "$0" "$@"
fi

export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8
# One BLAS thread per process, set BEFORE R starts: the placebo loops are
# already parallel, and nested parallelism only causes contention.
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$STATEDIR/${BATCH}_${STAMP}.log"
START_EPOCH=$(date +%s)

say() { printf '\n=== [%s] %s ===\n' "$(date +%H:%M:%S)" "$1" | tee -a "$LOG"; }
step() {
  local name="$1"; shift
  say "START $name"
  if "$@" >>"$LOG" 2>&1; then
    say "OK    $name"
  else
    say "FAIL  $name  (see $LOG)"
    tail -25 "$LOG"
    printf '%s\tFAIL\t%s\t-\n' "$BATCH" "$(date +%Y-%m-%dT%H:%M:%S)" >> "$STATE"
    exit 1
  fi
}

say "Batch '$BATCH' started. Log: $LOG"

case "$BATCH" in
  prep)
    step 01_renv_restore Rscript -e 'renv::restore(prompt = FALSE)'
    step 01b_env_record  Rscript -e 'writeLines(capture.output({print(renv::status()); print(sessionInfo())}), file.path("'"$STATEDIR"'", "environment.txt"))'
    step 01c_batch_coverage Rscript scripts/diagnostics/check_batch_coverage.R
    step 01d_parse_pipeline Rscript -e 'invisible(parse("_targets.R")); invisible(parse("scripts/functions.R")); invisible(parse("scripts/diagnostics/sdid_placebo_helpers.R")); m <- targets::tar_manifest(callr_function = NULL); source("scripts/rebuild_targets.R"); missing <- setdiff(unlist(rebuild_target_batches(), use.names = FALSE), m$name); if (length(missing) > 0) stop("batch targets absent from the manifest: ", paste(missing, collapse = ", ")); cat("pipeline parses;", nrow(m), "targets; every batch target present\n")'
    ;;
  data)
    step 02_targets_data Rscript scripts/run_rebuild_targets.R data
    # Runs here, not in prep: it reads synth_fit, which this batch builds.
    step 02a_validate_placebo Rscript scripts/diagnostics/validate_parallel_synthdid_placebo.R
    # The gate: the corrected pool must contain no unit that is treated under
    # the paper's own definition. Failing here costs ten minutes; failing at
    # referee stage costs the paper.
    step 02b_donor_pool_invariant Rscript scripts/diagnostics/check_donor_pool_screen.R
    ;;
  se_1|se_2|se_3)
    step "02_targets_${BATCH}" Rscript scripts/run_rebuild_targets.R "$BATCH"
    ;;
  core)
    step 02_targets_core Rscript scripts/run_rebuild_targets.R core
    ;;
  legacy)
    step 10_targets_legacy Rscript scripts/run_rebuild_targets.R legacy
    ;;
  diagnostics)
    step 03_sdid_diagnostics Rscript scripts/diagnostics/audit_brazil_sdid_no_covariates.R
    # paper_v4.Rmd prints three PNGs from this script through
    # include_graphics. Nothing rebuilt them, so the donor-weight figure
    # kept showing Malta after the tables had already dropped it.
    step 03b_paper_figures Rscript scripts/diagnostics/prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R
    step 03c_figures_fresh Rscript scripts/diagnostics/check_paper_figures_fresh.R
    ;;
  table5)
    step 04_commodity_table5 Rscript scripts/diagnostics/audit_brazil_sdid_commodity_no_covariates.R
    ;;
  ungadm)
    step 05_ungadm_estimation Rscript scripts/diagnostics/audit_ungadm_outcome_robustness.R
    ;;
  ungadm_post)
    step 06_ungadm_postreview Rscript scripts/diagnostics/audit_ungadm_postreview_diagnostics.R
    step 07_consistency Rscript scripts/diagnostics/check_se_consistency.R
    ;;
  render)
    step 08_render bash scripts/render_paper_v4.sh
    ;;
  extended)
    step 09_targets_extended Rscript scripts/run_rebuild_targets.R extended
    # Nothing in the manuscript reads this family, so the only thing worth
    # asserting is that the store no longer holds a mix of screens.
    step 09b_extended_uptodate Rscript scripts/diagnostics/check_extended_uptodate.R
    ;;
esac

DURATION=$(( $(date +%s) - START_EPOCH ))
printf '%s\tOK\t%s\t%dm%02ds\n' "$BATCH" "$(date +%Y-%m-%dT%H:%M:%S)" $((DURATION/60)) $((DURATION%60)) >> "$STATE"
say "Batch '$BATCH' finished in $((DURATION/60))m$((DURATION%60))s."
cmd_status
