#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/output/submission/cpsr/build"
RAW_DIR="$ROOT/output/submission/cpsr/raw"
FINAL_DIR="$ROOT/output/submission/cpsr/final"
VENDOR_DIR="$ROOT/submission/cpsr/vendor"

mkdir -p "$BUILD_DIR" "$RAW_DIR" "$FINAL_DIR"
cd "$ROOT"

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export TZ=UTC
export SOURCE_DATE_EPOCH=1790078400
export FORCE_SOURCE_DATE=1
export OMP_NUM_THREADS=1
export TEXINPUTS="$ROOT/:$VENDOR_DIR/:${TEXINPUTS:-}"
export BSTINPUTS="$VENDOR_DIR/:${BSTINPUTS:-}"
export BIBINPUTS="$BUILD_DIR/:$ROOT/:${BIBINPUTS:-}"

python3 scripts/submission/prepare_cpsr_sources.py

Rscript --vanilla scripts/submission/render_cpsr_rmd.R \
  "$ROOT" "$BUILD_DIR/cpsr_manuscript_anonymous.Rmd" \
  cpsr_manuscript_anonymous.pdf "$RAW_DIR"

Rscript --vanilla scripts/submission/render_cpsr_rmd.R \
  "$ROOT" "$BUILD_DIR/cpsr_full_inline_anonymous.Rmd" \
  cpsr_full_inline_anonymous.pdf "$RAW_DIR"

Rscript --vanilla scripts/submission/render_cpsr_rmd.R \
  "$ROOT" "$BUILD_DIR/cpsr_full_supplement_anonymous.Rmd" \
  cpsr_full_supplement_anonymous.pdf "$RAW_DIR"

# R's PDF device records the render time in generated figures. Normalize those
# assets, then force one final LaTeX pass so byte-level output depends only on
# manuscript inputs rather than wall-clock metadata.
python3 scripts/submission/normalize_cpsr_pdf_assets.py
for manuscript_source in \
  cpsr_manuscript_anonymous \
  cpsr_full_inline_anonymous \
  cpsr_full_supplement_anonymous
do
  latexmk -g -pdf -interaction=nonstopmode -halt-on-error \
    -outdir="$RAW_DIR" "$RAW_DIR/${manuscript_source}.tex"
done

for tex_source in \
  cpsr_title_page \
  cpsr_cover_letter \
  cpsr_appendix_full_cover \
  cpsr_appendix_short_cover \
  cpsr_online_resource_anonymous_cover \
  cpsr_online_supplement_public_cover
do
  latexmk -pdf -interaction=nonstopmode -halt-on-error \
    -outdir="$RAW_DIR" "$BUILD_DIR/${tex_source}.tex"
done

python3 scripts/submission/assemble_cpsr_pdfs.py
python3 scripts/submission/package_cpsr_latex_sources.py
Rscript --vanilla -e \
  "source('renv/activate.R'); writeLines(capture.output(sessionInfo()), 'output/submission/cpsr/final/session_info.txt')"
python3 scripts/submission/check_cpsr_package.py

echo "CPSR submission package ready: $FINAL_DIR"
