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
# Usage:  Rscript scripts/diagnostics/check_donor_pool_screen.R
# Exit:   0 if every invariant holds; non-zero with a diagnosis otherwise.

suppressPackageStartupMessages({
  library(dplyr)
  library(targets)
})

TREATED <- "BRA"

goods_panel <- tar_read(china_top_m2_goods_panel)

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
  uncovered <- setdiff(donors, unique(goods_panel$iso3c))
  if (length(uncovered) > 0) {
    problems <- c(problems, sprintf(
      "%d donor(s) absent from china_top_m2_goods_panel, so their treatment status is unverified: %s",
      length(uncovered), paste(uncovered, collapse = ", ")))
  } else {
    cat("  goods-panel coverage of donors: ", length(donors), "/", length(donors), "\n", sep = "")
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
