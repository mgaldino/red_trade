#!/usr/bin/env Rscript
# paper_v4.Rmd prints three figures as pre-rendered PNGs through
# include_graphics rather than building them in a chunk. That makes them
# invisible to knitr's dependency tracking: the manuscript's tables can be
# rebuilt from a corrected donor pool while the figures beside them still show
# the previous one. This is not hypothetical -- the donor-weight figure showed
# Malta as the second largest donor for weeks after the goods screen removed
# Malta from the pool.
#
# What this asserts, exactly:
#   1. the three PNGs exist;
#   2. each PNG is newer than the target objects it is drawn from
#      (synth_fit_no_time_varying_covariates, synth_data). A figure older than
#      the fit it draws was drawn from a superseded fit;
#   3. each PNG is newer than main_summary.csv, the diagnostic summary
#      audit_brazil_sdid_no_covariates.R writes in step 03 of this batch and
#      the manuscript prints beside the figures. This catches the original bug:
#      the CSVs regenerate, the figures do not;
#   4. unit_weights.csv -- the file the manuscript's appendix table prints --
#      contains no unit that has stopped being a donor.
#
# What it does NOT do: read the PNGs. Nothing here inspects pixels, so (2) and
# (3) are provenance-by-timestamp, and (4) is a statement about the CSV, not
# about the image. The guarantee that the image is drawn from live targets
# comes from its producer,
# prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R, which reads
# targets only and holds no frozen input.

store <- "_targets"
figure_dir <- file.path("quality_reports", "china_demand_shock_rank_threshold")
diag_dir <- file.path("data", "processed", "diagnostics",
                      "paper_v4_brazil_sdid_no_covariates")

figures <- file.path(figure_dir, c(
  "figure_brazil_sdid_predetermined_core_fit.png",
  "figure_brazil_sdid_predetermined_core_latam_fit.png",
  "figure_brazil_sdid_predetermined_core_weights.png"))

# The targets the producer draws the figures from.
sources <- c("synth_fit_no_time_varying_covariates", "synth_data")

missing <- figures[!file.exists(figures)]
if (length(missing) > 0) {
  stop("manuscript figures absent: ", paste(basename(missing), collapse = ", "),
       "\nRun scripts/diagnostics/",
       "prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R",
       call. = FALSE)
}

fig_time <- file.info(figures)$mtime

# ---- 2. newer than the targets they are drawn from ------------------------
source_files <- file.path(store, "objects", sources)
absent_sources <- sources[!file.exists(source_files)]
if (length(absent_sources) > 0) {
  stop("target objects absent from the store: ",
       paste(absent_sources, collapse = ", "),
       "\nThe `data` and `core` batches build them; this check runs in ",
       "`diagnostics`, so reaching here without them means a batch was ",
       "skipped.", call. = FALSE)
}
source_time <- max(file.info(source_files)$mtime)
# One second of slack throughout: ggsave and readr can land in the same second.
stale <- figures[fig_time < source_time - 1]
if (length(stale) > 0) {
  stop("manuscript figures older than the targets they are drawn from (",
       paste(sources, collapse = ", "), ", last built ",
       format(source_time, "%Y-%m-%d %H:%M:%S"), "): ",
       paste(basename(stale), collapse = ", "),
       "\nThey were drawn from a superseded fit. Run scripts/diagnostics/",
       "prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R",
       call. = FALSE)
}

# ---- 3. newer than the diagnostics printed beside them --------------------
reference <- file.path(diag_dir, "main_summary.csv")
if (!file.exists(reference)) {
  stop("reference file absent: ", reference,
       "\nStep 03 of this batch (audit_brazil_sdid_no_covariates.R) writes it.",
       call. = FALSE)
}
ref_time <- file.info(reference)$mtime
stale <- figures[fig_time < ref_time - 1]
if (length(stale) > 0) {
  stop("manuscript figures older than ", basename(reference), " (",
       format(ref_time, "%Y-%m-%d %H:%M:%S"), "): ",
       paste(basename(stale), collapse = ", "),
       "\nRun scripts/diagnostics/",
       "prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R",
       call. = FALSE)
}

# ---- 4. the printed weight table holds only current donors ----------------
# Independent of the figures: this is the CSV the appendix table prints. It is
# drawn from the same weight vector as the weight figure, so a mismatch here
# means the manuscript would print a donor list from a superseded pool.
weights_file <- file.path(diag_dir, "unit_weights.csv")
if (!file.exists(weights_file)) {
  stop("weight file absent: ", weights_file,
       "\nStep 03 of this batch (audit_brazil_sdid_no_covariates.R) writes it.",
       call. = FALSE)
}
weights <- readr::read_csv(weights_file, show_col_types = FALSE)
unit_col <- intersect(c("iso3c", "unit", "country"), names(weights))[1]
if (is.na(unit_col)) {
  stop("no unit column in ", weights_file, "; columns are: ",
       paste(names(weights), collapse = ", "), call. = FALSE)
}
donors <- setdiff(unique(targets::tar_read_raw("synth_data", store = store)$iso3c),
                  "BRA")
orphan <- setdiff(setdiff(unique(weights[[unit_col]]), "BRA"), donors)
if (length(orphan) > 0) {
  stop("the printed weight table holds units that are no longer donors: ",
       paste(sort(orphan), collapse = ", "),
       "\nStep 03 of this batch regenerates it from the live pool, so this ",
       "means the diagnostics ran against a superseded synth_data.",
       call. = FALSE)
}

cat(sprintf("weight table matches the live donor pool (%d donors).\n",
            length(donors)))
cat("manuscript figures are newer than the targets they are drawn from and ",
    "than the diagnostics printed beside them:\n   ",
    paste(basename(figures), collapse = "\n   "), "\n", sep = "")
