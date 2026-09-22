#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export OMP_NUM_THREADS=1

Rscript --vanilla -e "source('renv/activate.R'); source('scripts/diagnostics/build_cross_country_public_cue_preview_assets.R')"

Rscript --vanilla -e "source('renv/activate.R'); rmarkdown::render('paper_v4_cross_country_public_cue_preview.Rmd', output_file='paper_v4_cross_country_public_cue_preview.pdf', output_dir='output/pdf', quiet=FALSE); writeLines(capture.output(sessionInfo()), 'output/pdf/paper_v4_cross_country_public_cue_preview_session_info.txt')"

if [ -f paper_v4_cross_country_public_cue_preview.log ]; then
  mv -f paper_v4_cross_country_public_cue_preview.log output/pdf/paper_v4_cross_country_public_cue_preview.log
fi
