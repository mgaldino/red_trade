#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(targets)
})

manifest <- targets::tar_manifest(fields = c(name, command))

cat("targets manifest parsed successfully\n")
cat("Number of targets:", nrow(manifest), "\n")
