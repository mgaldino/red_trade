#!/usr/bin/env Rscript

# Builds the targets the manuscript and the diagnostic scripts consume.
#
# tar_make() forwards its `names` argument unevaluated to the pipeline
# process, where neither the helper function nor a local variable holding the
# names exists. bquote() substitutes the resolved character vector into the
# call, so what crosses the process boundary is the literal selection.
#
# Usage:
#   Rscript scripts/run_rebuild_targets.R           # every rebuild target
#   Rscript scripts/run_rebuild_targets.R core      # one batch (see
#   Rscript scripts/run_rebuild_targets.R se_a      #  rebuild_target_batches)
#   Rscript scripts/run_rebuild_targets.R se_b

source(file.path("scripts", "rebuild_targets.R"))

args  <- commandArgs(trailingOnly = TRUE)
batch <- if (length(args) >= 1 && nzchar(args[1])) args[1] else "all"

target_names <- rebuild_batch_names(batch)
if (length(target_names) == 0) {
  message("Batch '", batch, "' is empty; nothing to build.")
  quit(save = "no", status = 0)
}

message("Batch '", batch, "': rebuilding ", length(target_names), " targets.")
message("  ", paste(target_names, collapse = ", "))

eval(bquote(targets::tar_make(names = tidyselect::all_of(.(target_names)))))
