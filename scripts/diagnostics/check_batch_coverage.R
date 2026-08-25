#!/usr/bin/env Rscript
# Guards the two failure modes that produced real bugs in this rebuild.
#
# 1. COVERAGE. A target that descends from the corrected donor screen but sits
#    in no batch keeps its value from the superseded total-trade screen. The
#    store then holds mixed provenance with nothing failing.
#
# 2. ORDER. A reader that consumes a target built in a LATER batch either dies
#    on a clean machine or -- worse -- silently uses whatever the store happened
#    to hold from a previous run. Both happened here: the donor-pool gate read a
#    panel built two batches later, and the parallel placebo validator ran in
#    `prep` against a synth_fit that `data` rebuilds. The readers are the
#    verification scripts the orchestrator runs AND paper_v4.Rmd itself, which
#    is knitted by the `render` batch and would print a stale value with nothing
#    failing. A target built by no batch at all is reported the same way.
#
# Cheap: reads the dependency graph and the manifest, and greps the
# orchestrator. No target is built. Runs on every prep batch.

suppressMessages({
  library(targets)
})
source("scripts/rebuild_targets.R")

batches <- rebuild_target_batches()
batch_of <- stats::setNames(
  rep(names(batches), lengths(batches)), unlist(batches, use.names = FALSE))

orchestrator <- readLines("scripts/run_rebuild_batch.sh", warn = FALSE)

# The authoritative running order lives in the shell array, not in the R
# function: several batches run verification scripts and build no target at
# all, so names(batches) is a strict subset and would misorder the comparison.
batches_line <- grep("^BATCHES=\\(", orchestrator, value = TRUE)
stopifnot(length(batches_line) == 1)
batch_order <- strsplit(
  trimws(sub("^BATCHES=\\((.*)\\)$", "\\1", batches_line)), "\\s+")[[1]]
# The sub() above only matches a single-line array. ESTIMATES right below it is
# already multi-line, so reformatting BATCHES the same way is plausible -- and
# then sub() returns the line untouched and batch_order becomes
# c("BATCHES=(prep", "data", ...). names(batches) would still be a subset of
# that garbage, because the batches that build no target are not in it, so the
# check below would pass on nonsense. Fail loudly instead.
stopifnot(
  "prep" %in% batch_order,
  !any(grepl("=", batch_order)),
  all(names(batches) %in% batch_order))

# outdated = FALSE: this check is structural. The default would compute
# outdatedness for every target, which costs seconds today and grows with the
# store, for information this file never looks at.
network <- tar_network(targets_only = TRUE, callr_function = NULL,
                       outdated = FALSE)
edges <- network$edges

descendants_of <- function(roots) {
  seen <- character(0)
  frontier <- roots
  while (length(frontier) > 0) {
    nxt <- unique(edges$to[edges$from %in% frontier])
    nxt <- setdiff(nxt, seen)
    seen <- c(seen, nxt)
    frontier <- nxt
  }
  unique(seen)
}

# ---- 1. coverage ---------------------------------------------------------
screen_roots <- c("trade_data_goods", "trade_data_goods_ranked",
                  "synth_data", "synth_data_baseline", "synth_data_extended")
affected <- descendants_of(screen_roots)
uncovered <- setdiff(affected, names(batch_of))

cat(sprintf("targets descending from the corrected screen: %d\n", length(affected)))
if (length(uncovered) > 0) {
  stop("these descend from the corrected donor screen but sit in no batch, ",
       "so they would keep values from the superseded total-trade screen:\n  ",
       paste(sort(uncovered), collapse = ", "),
       "\nAdd them to a batch in rebuild_target_batches(), or, if they are ",
       "deliberately excluded, say so there and list them explicitly.",
       call. = FALSE)
}
cat("  all covered by a batch.\n")

# ---- 2. order ------------------------------------------------------------
MANUSCRIPT <- "paper_v4.Rmd"

# Map every orchestrated script to the batch that runs it, by parsing the
# dispatcher out of the shell script. Two subtleties, both of which used to
# produce a silent blind spot:
#
#   * The file holds TWO case blocks. The first dispatches list/status/next,
#     and its `next)` label matches the same pattern as a batch label. Anchoring
#     on min() of all labels therefore paired the batch labels with the
#     DISPATCHER's esac, which sits ABOVE them, so the last batch's body range
#     came out reversed (start > stop): its steps were never scanned, and every
#     other script picked up a spurious trailing label. The last batch is
#     exactly where a new batch gets appended. Keeping only labels that name a
#     batch drops `next)`, and max() then finds the esac that closes the batch
#     block. It also removes the NA that match("next", batch_order) would put
#     into min() if the dispatcher body ever gained a script call.
#   * gregexpr, not regexpr: 01d_parse_pipeline names three scripts on one
#     line, and regexpr returns only the first match per line.
label_lines <- grep('^\\s{2}[a-z_0-9|]+\\)\\s*$', orchestrator)
label_parts <- strsplit(
  trimws(sub("\\)\\s*$", "", orchestrator[label_lines])), "|", fixed = TRUE)
is_batch_label <- vapply(
  label_parts, function(p) all(p %in% batch_order), logical(1))
case_start <- label_lines[is_batch_label]
case_labels <- label_parts[is_batch_label]
esac_line <- grep("^esac\\s*$", orchestrator)
esac_line <- esac_line[esac_line > max(case_start)][1]
stopifnot(length(case_start) > 0, !is.na(esac_line))

script_batch <- list()
for (i in seq_along(case_start)) {
  stop_at <- if (i < length(case_start)) case_start[i + 1] - 1 else esac_line
  body <- orchestrator[case_start[i]:stop_at]
  scripts <- unlist(regmatches(
    body, gregexpr("scripts/[A-Za-z_0-9/]+\\.R", body)))
  # The manuscript is a consumer of targets like any script, and a stale one is
  # worse: a target built in a batch that runs after the render is printed in
  # the PDF from its previous value with nothing failing. The render step shells
  # out to render_paper_v4.sh, so the .R scan above cannot see the .Rmd; attach
  # it to whichever batch runs that shell script.
  if (any(grepl("render_paper_v4.sh", body, fixed = TRUE))) {
    scripts <- c(scripts, MANUSCRIPT)
  }
  for (sc in unique(scripts)) {
    script_batch[[sc]] <- unique(c(script_batch[[sc]], case_labels[[i]]))
  }
}
if (!MANUSCRIPT %in% names(script_batch)) {
  stop("no batch runs render_paper_v4.sh, so ", MANUSCRIPT, " could not be ",
       "attached to a batch; the manuscript's targets are unchecked.",
       call. = FALSE)
}

# The tar_read() surface rebuild_target_names() matches on the manuscript,
# widened to tar_read_raw() and to quoted names. Matched against the file as a
# single string so that a call wrapped across lines is still seen -- the
# manuscript has one.
#
# KNOWN BLIND SPOT (registered as a GitHub issue, 2026-08-25): this regex only
# recognizes DOUBLE-quoted or bare names inside tar_read()/tar_read_raw().
# Two idioms are invisible to it: single quotes (tar_read('x')) and tar_load(x).
# A read this function cannot see makes the final "none reads a target built
# later" message FALSE CONFIDENCE, which is the exact failure class this file
# exists to prevent. As of 2026-08-25 no orchestrated script or the manuscript
# uses either idiom (verified repo-wide), so the map is complete TODAY. If you
# are writing a new orchestrated script: use tar_read("x") style, or first
# widen this regex (["']? on both quote positions; tar_(read(_raw)?|load)) and
# re-run the 18-idiom battery from the round-3 review.
targets_read_by <- function(path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  hits <- unlist(regmatches(txt, gregexpr(
    'tar_read(_raw)?\\(\\s*"?([A-Za-z_0-9]+)"?\\s*[,)]', txt)))
  unique(trimws(gsub('tar_read(_raw)?\\(\\s*"?|"?\\s*[,)]$', "", hits)))
}

# Every target the pipeline defines. Needed to tell "this batch list forgot a
# target" from "this string only looks like a target name".
manifest <- targets::tar_manifest(callr_function = NULL)$name

problems <- character(0)
for (sc in names(script_batch)) {
  if (!file.exists(sc)) next
  reads <- targets_read_by(sc)
  runs_at <- min(match(script_batch[[sc]], batch_order))
  # A target in NO batch used to be dropped silently here by
  # intersect(reads, names(batch_of)). That is the worse half of the bug this
  # file exists to catch: the reader gets whatever the store happens to hold,
  # from any screen, and the ordering comparison below never sees it.
  for (tgt in setdiff(intersect(reads, manifest), names(batch_of))) {
    problems <- c(problems, sprintf(
      "%s reads '%s', which no batch builds", sc, tgt))
  }
  for (tgt in intersect(reads, names(batch_of))) {
    built_at <- match(batch_of[[tgt]], batch_order)
    if (built_at > runs_at) {
      problems <- c(problems, sprintf(
        "%s runs in batch '%s' (%d) but reads '%s', built in batch '%s' (%d)",
        sc, batch_order[runs_at], runs_at, tgt, batch_of[[tgt]], built_at))
    }
  }
}

if (length(problems) > 0) {
  stop("orchestrated readers get targets the batches do not build in time:\n  ",
       paste(problems, collapse = "\n  "),
       "\nEither move the step to a later batch, or add the target to an ",
       "earlier one in rebuild_target_batches().", call. = FALSE)
}
cat(sprintf(
  "checked %d orchestrated scripts and %s (%d targets read); none reads a ",
  length(script_batch) - 1L, MANUSCRIPT, length(targets_read_by(MANUSCRIPT))))
cat("target built later or built by no batch at all.\n")
cat("batch coverage and ordering hold.\n")
