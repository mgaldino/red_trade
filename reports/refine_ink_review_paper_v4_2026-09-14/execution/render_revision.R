#!/usr/bin/env Rscript
# Presentation-only render using the existing manuscript and cached results.
# Run from the repository root with LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# OMP_NUM_THREADS=1 Rscript --vanilla <path-to-this-file>.
# No targets execution, estimator calls, API classification, or data writes.
local_library <- "renv/library/macos/R-4.4/aarch64-apple-darwin20"
if (dir.exists(local_library)) .libPaths(c(local_library, .libPaths()))
options(encoding = "UTF-8", nwarnings = 1000L)
Sys.setenv(OMP_NUM_THREADS = "1")
revision_dir <- "reports/refine_ink_review_paper_v4_2026-09-14/execution"
dir.create(file.path(revision_dir, "build"), recursive = TRUE, showWarnings = FALSE)
render_warnings <- character()
withCallingHandlers(
  rmarkdown::render(
    "paper_v4.Rmd", output_file = "paper_v4.pdf",
    output_dir = file.path(revision_dir, "build"),
    intermediates_dir = file.path(revision_dir, "build"),
    output_options = list(keep_tex = TRUE), clean = FALSE, quiet = TRUE
  ),
  warning = function(w) render_warnings <<- c(render_warnings, conditionMessage(w))
)
writeLines(unique(render_warnings), file.path(revision_dir, "render_warnings.txt"))
writeLines(capture.output(sessionInfo()), file.path(revision_dir, "session_info.txt"))
