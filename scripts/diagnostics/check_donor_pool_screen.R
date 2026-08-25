#!/usr/bin/env Rscript

# Donor-pool eligibility invariant.
#
# Why this file exists (2026-08-25). The SDiD donor pool is built by
# clean_synth_data(), which drops any country coded as China's top export
# destination. That screen used to rank partners on TOTAL trade while the
# paper defines treatment on GOODS exports. The two rules disagree wherever
# services reorder a country's partners, and they did:
#
#   Malta 2011-2012   China is Malta's top goods destination but only third
#                     once services are counted, so a unit that is TREATED
#                     under the paper's own definition sat in the donor pool
#                     with 3.0% weight -- a direct violation of the SDiD
#                     assumption that the counterfactual is built from
#                     untreated units.
#   Singapore 2013-14 The mirror error: China tops Singapore's total trade
#                     but never its goods exports, so an eligible donor was
#                     screened out.
#
# The screen now ranks on goods (trade_data_goods_ranked). This script is the
# standing check that it stays that way, and it cross-validates the two
# independent code paths -- the screen's ranking and the cross-country
# panel's ranking (china_top_m2_goods_panel) -- against each other. If they
# ever drift apart again, this fails loudly instead of silently contaminating
# the counterfactual.
#
# What it asserts, in order:
#   1. the three goods sectors behind the panel are present AND carry
#      positive-trade rows (the duckdb path validates nothing on its own);
#   2. every donor-year cell of each panel is observable in the goods ranking,
#      with no unknown (NA) status;
#   3. the pool has not collapsed (a small pool satisfies the invariant for the
#      wrong reason), and Malta is out / Singapore is in;
#   4. no donor is China's top goods export destination inside the window.
#
# Usage:  Rscript scripts/diagnostics/check_donor_pool_screen.R
# Exit:   0 if every invariant holds; non-zero with a diagnosis otherwise.

suppressPackageStartupMessages({
  library(dplyr)
  library(targets)
})

TREATED <- "BRA"

goods_panel <- tar_read_raw("china_top_m2_goods_panel")

# ---------------------------------------------------------------- sectors --
# The two implementations of "goods" defend themselves asymmetrically.
# get_trade_data_goods() stops when an expected broad_sector label is absent
# from the ITPD-E file; the duckdb path that builds this panel filters
# `broad_sector IN ('Agriculture', 'Mining and Energy', 'Manufacturing')` and
# would return an empty set in silence if a release renamed a category.
#
# The defence is asserted here rather than inside the function on purpose: the
# aggregation's command hash feeds china_top_m2_goods_exports ->
# china_top_m2_goods_panel -> the whole fect_ife_* family, which is up to date
# and expensive, and editing the function body would invalidate all of it. The
# information is already a target. It is also a STRONGER test than the label
# check inside get_trade_data_goods(): a release that kept the label and
# emptied the category passes there and fails here.
GOODS_SECTORS <- c("Agriculture", "Mining and Energy", "Manufacturing")
sector_audit <- tar_read_raw("china_top_m2_goods_sector_audit")
absent_sectors <- setdiff(GOODS_SECTORS, sector_audit$broad_sector)
if (length(absent_sectors) > 0) {
  stop("goods sectors missing from the ITPD-E aggregation: ",
       paste(absent_sectors, collapse = ", "),
       "\nPresent labels: ", paste(sector_audit$broad_sector, collapse = ", "),
       "\nA renamed broad_sector silently empties the goods filter in ",
       "aggregate_itpde_goods_exports().", call. = FALSE)
}
# `%in% TRUE` rather than `>` alone: an NA count is not evidence of positive
# rows, and a bare comparison would drop it silently.
has_positive_rows <- (sector_audit$positive_trade_rows > 0) %in% TRUE
empty_sectors <- sector_audit$broad_sector[
  sector_audit$broad_sector %in% GOODS_SECTORS & !has_positive_rows]
if (length(empty_sectors) > 0) {
  stop("goods sectors present but with no positive-trade rows: ",
       paste(empty_sectors, collapse = ", "),
       "\nThe label survived but the category is empty, so the goods ranking ",
       "is built from a subset of what the paper calls goods.", call. = FALSE)
}
cat(sprintf(
  "goods sectors present with positive trade rows: %s\n",
  paste(sprintf("%s (%s)", GOODS_SECTORS,
                format(sector_audit$positive_trade_rows[
                  match(GOODS_SECTORS, sector_audit$broad_sector)],
                  big.mark = ",", trim = TRUE)),
        collapse = ", ")))

check_pool <- function(dataset_name) {
  data <- tryCatch(tar_read_raw(dataset_name), error = function(e) NULL)
  if (is.null(data)) {
    message("  [skip] target '", dataset_name, "' is not built yet")
    return(invisible(NULL))
  }

  years  <- range(data$year)
  units  <- sort(unique(data$iso3c))
  donors <- setdiff(units, TREATED)

  cat(sprintf("\n%s: %d units (%d donors), %d-%d\n",
              dataset_name, length(units), length(donors), years[1], years[2]))

  problems <- character(0)

  if (!TREATED %in% units) {
    problems <- c(problems, sprintf("treated unit %s absent from the panel", TREATED))
  }

  # Every donor must be observable in the goods ranking; an unobserved donor
  # is an untested donor, which is not the same thing as a clean one.
  window_years <- seq.int(years[1], years[2])
  covered <- goods_panel |>
    filter(iso3c %in% donors, year >= years[1], year <= years[2]) |>
    distinct(iso3c, year)
  expected_cells <- length(donors) * length(window_years)

  if (nrow(covered) < expected_cells) {
    # Name the cells. A count alone ("1897 of 1900") tells the operator that
    # something is missing but not what to fix, and the companion count of
    # fully absent donors is usually zero, which reads as noise.
    wanted <- expand.grid(iso3c = donors, year = window_years,
                          stringsAsFactors = FALSE)
    gap <- wanted[!paste(wanted$iso3c, wanted$year) %in%
                    paste(covered$iso3c, covered$year), , drop = FALSE]
    gap <- gap[order(gap$iso3c, gap$year), , drop = FALSE]
    shown <- utils::head(gap, 10L)
    message_text <- sprintf(
      "goods-panel coverage is %d of %d donor-year cells; missing %s%s",
      nrow(covered), expected_cells,
      paste(sprintf("%s %d", shown$iso3c, shown$year), collapse = ", "),
      if (nrow(gap) > nrow(shown))
        sprintf(" and %d more", nrow(gap) - nrow(shown)) else "")
    missing_units <- setdiff(donors, unique(covered$iso3c))
    if (length(missing_units) > 0) {
      message_text <- paste0(message_text, sprintf(
        "; %d donor(s) absent from the panel in every year: %s",
        length(missing_units), paste(missing_units, collapse = ", ")))
    }
    problems <- c(problems, message_text)
  } else {
    cat("  goods-panel coverage of donor-years: ", nrow(covered), "/",
        expected_cells, "\n", sep = "")
  }

  # An NA treatment status is an untested donor, and filter() drops NA rows
  # silently, so an all-NA column would satisfy the invariant trivially.
  na_status <- goods_panel |>
    filter(iso3c %in% donors, year >= years[1], year <= years[2],
           is.na(china_is_top))
  if (nrow(na_status) > 0) {
    problems <- c(problems, sprintf(
      "%d donor-year cell(s) have an unknown china_is_top status", nrow(na_status)))
  }

  # S2, first half: a collapsed pool satisfies "no donor is China-top" for the
  # wrong reason. The pool has held 88-95 donors across every window in use.
  if (length(donors) < 80L) {
    problems <- c(problems, sprintf(
      "donor pool collapsed to %d units; the screen has always left 88 or more",
      length(donors)))
  }

  # Named regression pins for the two units that motivated the correction.
  # They cost nothing, they duplicate no logic, and they fail on the fact
  # rather than on an aggregate: the pool-size floor above would not notice a
  # revert that swaps one unit for another.
  #
  # Restricted to the two 1997-2016 panels on purpose. synth_data_extended runs
  # to 2019 and its membership differs for reasons unrelated to this bug (Papua
  # New Guinea, for instance, becomes China-top in goods in 2018-2019 and so
  # belongs in the main pool but not in the extended one), so pinning named
  # units there would assert something the screen is not claiming.
  if (dataset_name %in% c("synth_data", "synth_data_baseline")) {
    if ("MLT" %in% units) {
      problems <- c(problems, paste0(
        "MLT is back in the donor pool. Malta is China's top goods export ",
        "destination in 2011-2012, inside Brazil's post-treatment window, so ",
        "it is TREATED under the paper's own definition. Its presence means ",
        "the screen is ranking partners on total trade again."))
    }
    if (!"SGP" %in% units) {
      problems <- c(problems, paste0(
        "SGP is missing from the donor pool. China tops Singapore's TOTAL ",
        "trade but never its goods exports in this window, so only the ",
        "superseded total-trade screen would remove it -- the mirror half of ",
        "the same bug."))
    }
    if (!"MLT" %in% units && "SGP" %in% units) {
      cat("  MLT out and SGP in, the two cases that motivated the screen\n")
    }
  }

  # The invariant itself.
  violations <- goods_panel |>
    filter(iso3c %in% donors,
           year >= years[1], year <= years[2],
           china_is_top) |>
    distinct(iso3c, year) |>
    arrange(iso3c, year)

  if (nrow(violations) > 0) {
    listed <- violations |>
      group_by(iso3c) |>
      summarise(years = paste(year, collapse = "/"), .groups = "drop") |>
      mutate(txt = paste0(iso3c, " (", years, ")")) |>
      pull(txt)
    problems <- c(problems, sprintf(
      "%d donor(s) are China's top goods export destination inside the window: %s",
      length(listed), paste(listed, collapse = ", ")))
  } else {
    cat("  no donor is China-top in goods anywhere in the window\n")
  }

  # Deliberately NOT checked here: a full characterisation of why each absent
  # country is absent. Most exclusions come from the outcome data (no UNGA
  # ideal points) or from incomplete trade coverage, not from the screen, so
  # asserting that set would mean duplicating clean_synth_data() in a second
  # place -- two implementations that must agree, which is the failure mode
  # this file exists to prevent. The pool-size floor above is the cheap guard
  # against the mirror error: a screen that wrongly excludes units shrinks the
  # pool, and that fails loudly.

  if (length(problems) > 0) {
    stop("Donor-pool screen violated for '", dataset_name, "':\n  - ",
         paste(problems, collapse = "\n  - "),
         "\nThe donor pool must contain only units untreated under the ",
         "paper's own treatment definition (largest goods export destination).",
         call. = FALSE)
  }
  invisible(TRUE)
}

cat("Donor-pool eligibility invariant (screen must match the goods-based treatment definition)\n")
for (nm in c("synth_data", "synth_data_baseline", "synth_data_extended")) check_pool(nm)
cat("\nAll donor-pool invariants hold.\n")
