#!/usr/bin/env Rscript
# Presentation only. No targets mutation/execution, estimation, or API call.
# Rscript --vanilla render_isolated.R <repo> <candidate.Rmd> <build-directory>
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
repo <- normalizePath(args[[1]], mustWork = TRUE)
source <- normalizePath(args[[2]], mustWork = TRUE)
build <- normalizePath(args[[3]], mustWork = TRUE)
.libPaths(c(file.path(repo, "renv/library/macos/R-4.4/aarch64-apple-darwin20"), .libPaths()))
options(encoding = "UTF-8", nwarnings = 1000L)
Sys.setenv(OMP_NUM_THREADS = "1")
setwd(dirname(source))
render_warnings <- character()
withCallingHandlers(
  rmarkdown::render(
    basename(source), output_file = "paper_v4.pdf", output_dir = build,
    intermediates_dir = build, output_options = list(keep_tex = TRUE),
    clean = FALSE, quiet = TRUE
  ),
  warning = function(w) render_warnings <<- c(render_warnings, conditionMessage(w))
)
writeLines(unique(render_warnings), file.path(build, "render_warnings.txt"))
writeLines(capture.output(sessionInfo()), file.path(build, "session_info.txt"))
