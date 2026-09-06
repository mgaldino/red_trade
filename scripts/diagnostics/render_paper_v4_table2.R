#!/usr/bin/env Rscript
# Render Table 2 revision using existing results; never run targets or estimators.
# Run from the repository root:
# LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 OMP_NUM_THREADS=1 Rscript --vanilla scripts/diagnostics/render_paper_v4_table2.R
local_library <- "renv/library/macos/R-4.4/aarch64-apple-darwin20"
if (dir.exists(local_library)) .libPaths(c(local_library, .libPaths()))
options(encoding = "UTF-8", nwarnings = 1000L)
Sys.setenv(OMP_NUM_THREADS = "1")
revision_dir <- "quality_reports/revisions/paper_v4/20260906_table2"
dir.create(revision_dir, recursive = TRUE, showWarnings = FALSE)
render_warnings <- character()
withCallingHandlers(
  rmarkdown::render(
    "paper_v4.Rmd", output_file = "paper_v4_table2.pdf",
    output_dir = revision_dir,
    intermediates_dir = file.path(revision_dir, "build"),
    output_options = list(keep_tex = TRUE), clean = FALSE, quiet = TRUE
  ),
  warning = function(w) render_warnings <<- c(render_warnings, conditionMessage(w))
)
writeLines(unique(render_warnings), file.path(revision_dir, "render_warnings.txt"))
writeLines(capture.output(sessionInfo()), file.path(revision_dir, "session_info.txt"))
