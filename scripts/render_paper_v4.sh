#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

# --vanilla isolates user-level startup files, but it also skips the project
# .Rprofile, which is what activates renv. Activate renv explicitly so the
# render uses the locked library, not the system one, and record the session.
Rscript --vanilla -e "source('renv/activate.R'); rmarkdown::render('paper_v4.Rmd', output_file='paper_v4.pdf', quiet=FALSE); writeLines(capture.output(sessionInfo()), 'output/paper_v4_session_info.txt')"
