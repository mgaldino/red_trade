#!/usr/bin/env Rscript
# Check whether any treated country experienced a re-reversal
# (China lost #1 trade partner position back to the US after initially gaining it)

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
})

setwd("/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade")

cat("===================================================================\n")
cat("  RE-REVERSAL ANALYSIS: Did the US regain #1 from China?\n")
cat("===================================================================\n\n")

# --- 1. Load targets ---
treatment_events  <- tar_read(treatment_events)
trade_data_ranked <- tar_read(trade_data_ranked)
trade_data        <- tar_read(trade_data)

cat("--- TREATMENT EVENTS (treatment_events target) ---\n")
print(as.data.frame(treatment_events))
cat("\nNumber of treated countries:", nrow(treatment_events), "\n\n")

# --- 2. Build full annual rankings for each exporter ---
# For each country-year, rank all importers by export value
full_ranks <- trade_data %>%
  group_by(year, exporter_iso3) %>%
  mutate(rank = dense_rank(desc(exports))) %>%
  ungroup()

# --- 3. For each treated country, extract China & US rankings over time ---
treated_iso3 <- treatment_events$iso3c

cat("===================================================================\n")
cat("  YEARLY RANKINGS: China vs US as trade partner per treated country\n")
cat("===================================================================\n\n")

for (cty in treated_iso3) {
  treat_year <- treatment_events$first_treat_year[treatment_events$iso3c == cty]

  # Get China rank
  china_rank <- full_ranks %>%
    filter(exporter_iso3 == cty, importer_iso3 == "CHN") %>%
    select(year, china_rank = rank, china_exports = exports)

  # Get USA rank
  usa_rank <- full_ranks %>%
    filter(exporter_iso3 == cty, importer_iso3 == "USA") %>%
    select(year, usa_rank = rank, usa_exports = exports)

  combined <- china_rank %>%
    full_join(usa_rank, by = "year") %>%
    arrange(year) %>%
    mutate(
      who_is_top = case_when(
        china_rank < usa_rank ~ "CHINA",
        usa_rank < china_rank ~ "USA",
        TRUE ~ "TIE"
      )
    )

  cat(sprintf("--- %s (treatment year: %d) ---\n", cty, treat_year))
  print(as.data.frame(combined), row.names = FALSE)
  cat("\n")
}

# --- 4. Detect re-reversals ---
cat("===================================================================\n")
cat("  RE-REVERSAL DETECTION\n")
cat("===================================================================\n\n")

reversal_countries <- c()

for (cty in treated_iso3) {
  treat_year <- treatment_events$first_treat_year[treatment_events$iso3c == cty]

  china_rank <- full_ranks %>%
    filter(exporter_iso3 == cty, importer_iso3 == "CHN") %>%
    select(year, china_rank = rank)

  usa_rank <- full_ranks %>%
    filter(exporter_iso3 == cty, importer_iso3 == "USA") %>%
    select(year, usa_rank = rank)

  combined <- china_rank %>%
    full_join(usa_rank, by = "year") %>%
    arrange(year) %>%
    # Only look at years AFTER treatment
    filter(year > treat_year)

  # Check: did USA ever regain #1 (become ranked higher than China)?
  re_reversals <- combined %>%
    filter(usa_rank < china_rank)

  if (nrow(re_reversals) > 0) {
    reversal_countries <- c(reversal_countries, cty)
    cat(sprintf("*** RE-REVERSAL FOUND: %s ***\n", cty))
    cat(sprintf("    Treatment year: %d\n", treat_year))
    cat(sprintf("    Years where US regained #1 over China AFTER treatment:\n"))
    for (i in seq_len(nrow(re_reversals))) {
      cat(sprintf("      Year %d: US rank=%d, China rank=%d\n",
                  re_reversals$year[i],
                  re_reversals$usa_rank[i],
                  re_reversals$china_rank[i]))
    }
    cat("\n")
  } else {
    cat(sprintf("    %s: No re-reversal. China stayed #1 from %d onward.\n", cty, treat_year))
  }
}

# --- 4b. Also check from classify_treatment_events (absorbing flag) ---
cat("\n--- Cross-check with classify_treatment_events target ---\n")
tryCatch({
  classified <- tar_read(classified_events)
  cat("classified_events:\n")
  print(as.data.frame(classified))
}, error = function(e) {
  cat("  (classified_events target not available)\n")
})

# --- 5. If re-reversals found, load UNGA data ---
if (length(reversal_countries) > 0) {
  cat("\n===================================================================\n")
  cat("  UNGA ALIGNMENT FOR RE-REVERSAL COUNTRIES\n")
  cat("===================================================================\n\n")

  unga_data <- tar_read(unga_data)

  for (cty in reversal_countries) {
    treat_year <- treatment_events$first_treat_year[treatment_events$iso3c == cty]

    # Show UNGA data around the treatment and reversal window
    unga_cty <- unga_data %>%
      filter(iso3c == cty, year >= treat_year - 5, year <= max(unga_data$year)) %>%
      select(iso3c, year, any_of(c("abs_distance_china", "IdealPointAll",
                                    "abs_distance_us", "abs_distance_china"))) %>%
      arrange(year)

    cat(sprintf("--- UNGA data for %s (treatment year: %d) ---\n", cty, treat_year))
    print(as.data.frame(unga_cty), row.names = FALSE)
    cat("\n")
  }

  # Also show re-reversal years alongside UNGA ideal-point distance
  cat("\n--- RE-REVERSAL YEARS + UNGA DISTANCE FROM CHINA ---\n\n")
  for (cty in reversal_countries) {
    treat_year <- treatment_events$first_treat_year[treatment_events$iso3c == cty]

    # trade ranks
    china_rank <- full_ranks %>%
      filter(exporter_iso3 == cty, importer_iso3 == "CHN") %>%
      select(year, china_rank = rank)
    usa_rank <- full_ranks %>%
      filter(exporter_iso3 == cty, importer_iso3 == "USA") %>%
      select(year, usa_rank = rank)
    combined <- china_rank %>%
      full_join(usa_rank, by = "year") %>%
      arrange(year)

    # UNGA
    unga_cty <- unga_data %>%
      filter(iso3c == cty) %>%
      select(year, abs_distance_china)

    merged <- combined %>%
      left_join(unga_cty, by = "year") %>%
      filter(year >= treat_year - 3) %>%
      mutate(
        who_is_top = case_when(
          china_rank < usa_rank ~ "CHINA #1",
          usa_rank < china_rank ~ "USA #1",
          TRUE ~ "TIE"
        )
      )

    cat(sprintf("--- %s: Trade rank + UNGA distance (treatment=%d) ---\n", cty, treat_year))
    print(as.data.frame(merged), row.names = FALSE)
    cat("\n")
  }
} else {
  cat("\nNo re-reversals found. All treated countries have absorbing treatments.\n")
}

cat("\n===================================================================\n")
cat("  SUMMARY\n")
cat("===================================================================\n")
cat(sprintf("Total treated countries: %d\n", length(treated_iso3)))
cat(sprintf("Countries with re-reversals: %d\n", length(reversal_countries)))
if (length(reversal_countries) > 0) {
  cat(sprintf("Re-reversal countries: %s\n", paste(reversal_countries, collapse = ", ")))
}
cat("===================================================================\n")
