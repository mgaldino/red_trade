#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# This standalone model contains no analysis chunks or targets calls.
# Use the project's existing R library for reproducible document rendering.
Rscript --vanilla -e 'source("renv/activate.R"); rmarkdown::render("reports/toy_model_status_cue/toy_model_status_cue_short_en.Rmd", output_file="toy_model_status_cue_short_en.pdf", output_dir="output/pdf", quiet=FALSE)'
