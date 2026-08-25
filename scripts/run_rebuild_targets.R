#!/usr/bin/env Rscript

# Builds exactly the targets the manuscript and the diagnostic scripts consume.
#
# tar_make() forwards its `names` argument unevaluated to the pipeline
# process, where neither the helper function nor a local variable holding the
# names exists. bquote() substitutes the resolved character vector into the
# call, so what crosses the process boundary is the literal selection.

source(file.path("scripts", "rebuild_targets.R"))
target_names <- rebuild_target_names()
message("Rebuilding ", length(target_names), " targets.")

eval(bquote(targets::tar_make(names = tidyselect::all_of(.(target_names)))))
