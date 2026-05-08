###############################################################################
# compute_heterogeneity_data.R
#
# Standalone script — runs OUTSIDE the {targets} pipeline.
# Reads raw trade data + V-Dem, computes:
#   1. USA streak (consecutive years as #1 importer before treatment/end-of-data)
#   2. Pre-treatment press freedom (V-Dem v2x_freexp_altinf, 5-year mean)
# Both variables are computed for ALL countries in event_study_data_usa
# (treated + never-treated) so they can be used as continuous covariates
# in did::att_gt(xformla = ~usa_streak + press_free).
#
# Saves result to: data/heterogeneity_vars.rds
#
# Usage:
#   Rscript scripts/compute_heterogeneity_data.R
#   — OR source() interactively from the project root.
###############################################################################

library(data.table)
library(dplyr)
library(tidyr)
library(targets)    # only to read from the store
library(here)

cat("=== compute_heterogeneity_data.R ===\n")

# --------------------------------------------------------------------------
# 0.  Load objects from the {targets} store (already built)
# --------------------------------------------------------------------------
classified_events <- tar_read(classified_events)
event_study_data_usa <- tar_read(event_study_data_usa)

all_countries <- unique(event_study_data_usa$iso3c)
treated_iso <- unique(event_study_data_usa$iso3c[event_study_data_usa$first_treat > 0])
nevertreated_iso <- setdiff(all_countries, treated_iso)

cat("Countries in event_study_data_usa:", length(all_countries),
    "(", length(treated_iso), "treated,", length(nevertreated_iso), "never-treated)\n")

# --------------------------------------------------------------------------
# 1.  Compute USA streak for ALL countries
# --------------------------------------------------------------------------
cat("\nReading raw trade data (ITPDE_R03.csv)...\n")
trade_raw <- fread(here("raw data", "ITPDE_R03.csv"),
                   select = c("year", "exporter_iso3", "importer_iso3", "trade"))

# Aggregate to (year, exporter, importer) — same logic as get_trade_data()
# but starting from 1986 (earliest available) for maximum streak window
trade_agg <- trade_raw[year >= 1986 & exporter_iso3 != importer_iso3,
                       .(exports = sum(trade)),
                       by = .(year, exporter_iso3, importer_iso3)]

# For each (year, exporter), identify the #1 importer
top_partner <- trade_agg[,
  .SD[which.max(exports)],
  by = .(year, exporter_iso3)
][, .(iso3c = exporter_iso3, year, top_partner = importer_iso3)]

cat("Top-partner panel:", nrow(top_partner), "rows\n")

# Count consecutive years USA was #1, looking backwards from ref_year (inclusive)
compute_streak <- function(iso, ref_year, top_partner_dt) {
  hist <- top_partner_dt[iso3c == iso][order(-year)]
  hist <- hist[year <= ref_year]
  if (nrow(hist) == 0) return(0L)
  streak <- 0L
  for (i in seq_len(nrow(hist))) {
    if (hist$top_partner[i] == "USA") {
      streak <- streak + 1L
    } else {
      break
    }
  }
  streak
}

# For treated: streak up to (first_treat_year - 1)
treated_info <- classified_events %>%
  filter(iso3c %in% treated_iso) %>%
  select(iso3c, first_treat_year)

streak_treated <- treated_info %>%
  rowwise() %>%
  mutate(usa_streak = compute_streak(iso3c, first_treat_year - 1L, top_partner)) %>%
  ungroup() %>%
  select(iso3c, usa_streak)

# For never-treated: streak backwards from last year of data (2022)
max_year_data <- max(top_partner$year)
streak_nevertreated <- data.frame(iso3c = nevertreated_iso, stringsAsFactors = FALSE) %>%
  rowwise() %>%
  mutate(usa_streak = compute_streak(iso3c, max_year_data, top_partner)) %>%
  ungroup()

usa_streak_all <- bind_rows(streak_treated, streak_nevertreated)

cat("\nUSA streak summary (treated, >0):\n")
print(streak_treated %>% filter(usa_streak > 0) %>% arrange(desc(usa_streak)))
cat("\nUSA streak summary (never-treated, >0):\n")
print(streak_nevertreated %>% filter(usa_streak > 0) %>% arrange(desc(usa_streak)))

# --------------------------------------------------------------------------
# 2.  Get press freedom data (V-Dem: v2x_freexp_altinf)
# --------------------------------------------------------------------------
cat("\n--- Press Freedom (V-Dem) ---\n")

# Install vdemdata if not available
if (!requireNamespace("vdemdata", quietly = TRUE)) {
  cat("Installing vdemdata from GitHub (one-time)...\n")
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes", repos = "https://cran.r-project.org")
  }
  remotes::install_github("vdeminstitute/vdemdata", upgrade = "never")
}

library(vdemdata)

# Extract relevant variables
vdem_df <- vdem %>%
  as_tibble() %>%
  select(country_text_id, year, v2x_freexp_altinf) %>%
  rename(iso3c = country_text_id) %>%
  filter(!is.na(v2x_freexp_altinf))

cat("V-Dem panel:", nrow(vdem_df), "rows,",
    length(unique(vdem_df$iso3c)), "countries\n")

# Helper: mean press freedom over a window
compute_press_mean <- function(ciso, yr_start, yr_end, vdem) {
  window <- vdem[vdem$iso3c == ciso &
                 vdem$year >= yr_start &
                 vdem$year <= yr_end, ]
  if (nrow(window) > 0) mean(window$v2x_freexp_altinf, na.rm = TRUE) else NA_real_
}

# For treated: mean of 5 years before treatment
press_treated <- treated_info %>%
  rowwise() %>%
  mutate(press_free = compute_press_mean(iso3c,
                                         first_treat_year - 5,
                                         first_treat_year - 1,
                                         vdem_df)) %>%
  ungroup() %>%
  select(iso3c, press_free)

# For never-treated: mean over 1995-2005 (stable pre-period)
press_nevertreated <- data.frame(iso3c = nevertreated_iso, stringsAsFactors = FALSE) %>%
  rowwise() %>%
  mutate(press_free = compute_press_mean(iso3c, 1995, 2005, vdem_df)) %>%
  ungroup()

press_all <- bind_rows(press_treated, press_nevertreated)

cat("\nPress freedom — treated:\n")
print(press_treated %>% arrange(desc(press_free)))
cat("\nPress freedom — never-treated (sample):\n")
print(press_nevertreated %>% arrange(desc(press_free)) %>% head(15))

# --------------------------------------------------------------------------
# 3.  Merge into a single country-level dataset
# --------------------------------------------------------------------------
het_country <- usa_streak_all %>%
  left_join(press_all, by = "iso3c")

cat("\n--- Final dataset ---\n")
cat("Countries with streak:", sum(!is.na(het_country$usa_streak)), "\n")
cat("Countries with press freedom:", sum(!is.na(het_country$press_free)), "\n")
cat("Missing press freedom:", sum(is.na(het_country$press_free)), "—",
    het_country$iso3c[is.na(het_country$press_free)], "\n")

# --------------------------------------------------------------------------
# 4.  Save
# --------------------------------------------------------------------------
output_dir <- here("data")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

saveRDS(het_country, here("data", "heterogeneity_vars.rds"))
cat("\nSaved to:", here("data", "heterogeneity_vars.rds"), "\n")
cat("Done.\n")
