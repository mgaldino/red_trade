#!/usr/bin/env Rscript
# Render the selected RIO corrections without executing the targets pipeline.
# Run from repository root with Rscript --vanilla.
local_library <- "renv/library/macos/R-4.4/aarch64-apple-darwin20"
if (dir.exists(local_library)) .libPaths(c(local_library, .libPaths()))
options(encoding = "UTF-8")
options(nwarnings = 1000L)
Sys.setenv(OMP_NUM_THREADS = "1")
revision_dir <- "quality_reports/revisions/paper_v4/20260905_RIO_selected_fixes"
build_dir <- file.path(revision_dir, "compiled")
dir.create(build_dir, recursive = TRUE, showWarnings = FALSE)
build_dir <- normalizePath(build_dir)
stopifnot(file.exists("paper_v4.Rmd"), file.exists("synth-trade-china.bib"))
# Keep the source at repository root so cached file-target paths resolve.
# A distinct output basename protects the root paper_v4.pdf during QA.
root_dir <- normalizePath(".")
file.copy("paper_v4.Rmd", file.path(build_dir, "paper_v4.Rmd"), overwrite = TRUE)
file.copy("synth-trade-china.bib", file.path(build_dir, "synth-trade-china.bib"), overwrite = TRUE)
rmarkdown::render(
  "paper_v4.Rmd",
  output_file = "paper_v4_RIO_20260905.pdf",
  output_dir = build_dir,
  intermediates_dir = build_dir,
  knit_root_dir = root_dir,
  output_options = list(keep_tex = TRUE),
  clean = FALSE,
  envir = new.env(parent = globalenv()),
  quiet = FALSE
)
writeLines(capture.output(sessionInfo()), file.path(build_dir, "session_info.txt"))
writeLines(capture.output(warnings()), file.path(build_dir, "render_warnings.txt"))
