#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

Rscript --vanilla -e "rmarkdown::render('paper_v4.Rmd', output_file='paper_v4.pdf', quiet=FALSE)"
