#!/usr/bin/env Rscript

# Render one generated CPSR R Markdown source without rebuilding the targets
# pipeline. All analytical values are read from the repository's existing files
# and target store by the chunks inherited from paper_v4.Rmd.

args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 4L) {
  stop(
    paste(
      "Usage: render_cpsr_rmd.R",
      "ROOT INPUT_RMD OUTPUT_FILE OUTPUT_DIR"
    ),
    call. = FALSE
  )
}

root <- normalizePath(args[[1]], mustWork = TRUE)
input <- normalizePath(args[[2]], mustWork = TRUE)
output_file <- args[[3]]
output_dir <- normalizePath(args[[4]], mustWork = FALSE)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
setwd(root)

# Rscript --vanilla skips the project .Rprofile, so activate the locked library
# explicitly. This mirrors the canonical paper_v4 render path.
source(file.path(root, "renv", "activate.R"))

vendor_dir <- file.path(root, "submission", "cpsr", "vendor")
path_sep <- .Platform$path.sep
Sys.setenv(
  TEXINPUTS = paste0(
    root, .Platform$file.sep, path_sep,
    vendor_dir, .Platform$file.sep, path_sep,
    Sys.getenv("TEXINPUTS")
  ),
  BSTINPUTS = paste0(vendor_dir, .Platform$file.sep, path_sep, Sys.getenv("BSTINPUTS")),
  BIBINPUTS = paste0(
    dirname(input), .Platform$file.sep, path_sep,
    root, .Platform$file.sep, path_sep,
    Sys.getenv("BIBINPUTS")
  )
)

render_env <- new.env(parent = globalenv())
rmarkdown::render(
  input = input,
  output_file = output_file,
  output_dir = output_dir,
  knit_root_dir = root,
  envir = render_env,
  clean = FALSE,
  quiet = FALSE
)
