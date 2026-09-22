# Builds the appendix table of the public-cue search (paper_v4.Rmd, section
# "Public Cue Search") and writes it to
# data/processed/status_cue_salience/public_cue_audit_table.csv.
#
# Outside the targets graph for now; listed for migration in TARGETS_MIGRATION.md.
# Reads the built target china_top_m2_goods_panel from the local store.
#
# Usage: Rscript scripts/diagnostics/build_public_cue_audit_table.R

suppressMessages({
  library(targets)
  library(dplyr)
  library(readr)
})

source("scripts/functions_public_cue_audit.R")

cue_dir <- file.path("data", "processed", "status_cue_salience")

public_cue_audit <- build_public_cue_audit_table(
  goods_panel = tar_read(china_top_m2_goods_panel),
  status_country_file = file.path(cue_dir, "status_cue_country_codes.csv"),
  status_source_file = file.path(cue_dir, "status_cue_source_evidence.csv"),
  australia_media_file = file.path(cue_dir, "australia_public_cue_media_2006_2009.csv"),
  australia_code = "high"
)

readr::write_csv(public_cue_audit, file.path(cue_dir, "public_cue_audit_table.csv"))
