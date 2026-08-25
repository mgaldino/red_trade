#!/usr/bin/env Rscript
# The extended-window family feeds no manuscript number, so the only property
# worth asserting is that it is not a leftover from the superseded total-trade
# donor screen sitting next to artefacts built under the goods screen.

family <- c("synth_data_extended", "synth_fit_extended",
            "se_synth_extended", "sensitivity_results")

stale <- targets::tar_outdated(
  names = c("synth_data_extended", "synth_fit_extended",
            "se_synth_extended", "sensitivity_results"),
  reporter = "silent")

if (length(stale) > 0) {
  stop("extended family still outdated after the batch: ",
       paste(stale, collapse = ", "), call. = FALSE)
}
cat("extended family up to date:", paste(family, collapse = ", "), "\n")
