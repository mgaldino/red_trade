#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

# --vanilla isolates user-level startup files, but it also skips the project
# .Rprofile, which is what activates renv. Activate renv explicitly so the
# render uses the locked library, not the system one, and record the session.
#
# output_dir='output': without it the PDF lands in the repository root while
# README.md, readme_replication.Rmd and run_reproducibility_rebuild.sh all name
# output/paper_v4.pdf -- and an April 2026 file already sits there, so a
# replicator would finish a seven-hour rebuild and open a PDF describing the
# superseded cross-country design, with nothing failing.
Rscript --vanilla -e "source('renv/activate.R'); rmarkdown::render('paper_v4.Rmd', output_file='paper_v4.pdf', output_dir='output', quiet=FALSE); writeLines(capture.output(sessionInfo()), 'output/paper_v4_session_info.txt')"

# render(output_dir=) moves the .pdf but NOT the .tex/.log side products, so a
# stale output/paper_v4.log would sit next to a fresh PDF and be read as its
# compile log. Keep the pair together when the log exists.
if [ -f paper_v4.log ]; then
  mv -f paper_v4.log output/paper_v4.log
fi
