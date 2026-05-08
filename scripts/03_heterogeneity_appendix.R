###############################################################################
# 03_heterogeneity_appendix.R
#
# Generates appendix materials:
#   1. Descriptive table of USA-displaced treated countries
#   2. Panel plot (facet) of abs_distance_china for each treated country
#   3. Full specification table across panels, covariates, exclusions
#
# Usage: Rscript scripts/03_heterogeneity_appendix.R
###############################################################################

options(scipen = 999)

suppressPackageStartupMessages({
  library(here)
  library(targets)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(did)
  library(countrycode)
})

source(here("scripts", "functions.R"))

# Load from store
tar_load(c(treatment_events, unga_data, classified_events, usa_top_countries))
het_data <- readRDS(here("data", "heterogeneity_vars.rds"))

# USA-displaced treated countries
treated_usa_all <- classified_events %>%
  filter(displaced == "USA") %>%
  select(iso3c, first_treat_year)

cat("=== USA-displaced treated countries ===\n")
print(treated_usa_all)

# =========================================================================
# 1. Descriptive table
# =========================================================================
cat("\n=== Table 1: Descriptive statistics of treated countries ===\n")

desc_table <- unga_data %>%
  select(iso3c, year, abs_distance_china) %>%
  inner_join(treated_usa_all, by = "iso3c") %>%
  mutate(period = ifelse(year < first_treat_year, "pre", "post")) %>%
  group_by(iso3c, first_treat_year, period) %>%
  summarise(
    mean_distance = mean(abs_distance_china, na.rm = TRUE),
    n_years = n(),
    .groups = "drop"
  ) %>%
  pivot_wider(names_from = period, values_from = c(mean_distance, n_years)) %>%
  left_join(het_data %>% select(iso3c, usa_streak, press_free), by = "iso3c") %>%
  mutate(
    country = countrycode(iso3c, "iso3c", "country.name"),
    diff = mean_distance_post - mean_distance_pre,
    in_panel = ifelse(iso3c %in% unique(tar_read(event_study_data_usa)$iso3c), "Yes", "No")
  ) %>%
  arrange(first_treat_year) %>%
  select(country, iso3c, first_treat_year, usa_streak, press_free,
         mean_distance_pre, mean_distance_post, diff, in_panel)

print(desc_table, n = 20)

# Save CSV
write.csv(desc_table, here("quality_reports", "table_treated_countries.csv"),
          row.names = FALSE)
cat("Saved: quality_reports/table_treated_countries.csv\n")

# =========================================================================
# 2. Panel plot: abs_distance_china over time for treated countries
# =========================================================================
cat("\n=== Figure: Panel plot of treated countries ===\n")

# Get countries in the main 1990+ panel
panel_countries <- unique(tar_read(event_study_data_usa)$iso3c[
  tar_read(event_study_data_usa)$first_treat > 0])

plot_data <- unga_data %>%
  select(iso3c, year, abs_distance_china) %>%
  filter(iso3c %in% panel_countries) %>%
  inner_join(treated_usa_all, by = "iso3c") %>%
  mutate(country = countrycode(iso3c, "iso3c", "country.name"))

panel_plot <- ggplot(plot_data, aes(x = year, y = abs_distance_china)) +
  geom_point(size = 0.8, alpha = 0.6) +
  geom_smooth(se = FALSE, method = "loess", span = 0.5, linewidth = 0.8) +
  geom_vline(aes(xintercept = first_treat_year),
             linetype = "dashed", colour = "red", linewidth = 0.5) +
  facet_wrap(~ country, ncol = 2, scales = "free") +
  labs(x = "Year",
       y = "Absolute distance to China (UNGA ideal points)",
       title = "UNGA voting distance to China: USA-displaced treated countries",
       subtitle = "Dashed red line = year China became #1 trade partner") +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank())

ggsave(here("quality_reports", "fig_panel_treated_countries.pdf"),
       panel_plot, width = 8, height = 10)
ggsave(here("quality_reports", "fig_panel_treated_countries.png"),
       panel_plot, width = 8, height = 10, dpi = 300)
cat("Saved: quality_reports/fig_panel_treated_countries.pdf\n")

# =========================================================================
# 3. Full specification table
# =========================================================================
cat("\n=== Table 2: Full specification table ===\n")

# Helper: build panel, run DiD, return one row
run_spec <- function(start_year, exclude_years, xformla, spec_label) {
  # Build balanced panel
  panel <- unga_data %>%
    select(iso3c, year, abs_distance_china) %>%
    filter(year >= start_year) %>%
    left_join(treatment_events, by = "iso3c") %>%
    mutate(first_treat = ifelse(is.na(first_treat_year), 0, first_treat_year),
           id = as.integer(as.factor(iso3c)))

  max_years <- max(table(panel$id))
  balanced_ids <- panel %>%
    group_by(id) %>%
    summarise(n_years = n(), .groups = "drop") %>%
    filter(n_years == max_years) %>%
    pull(id)
  panel <- panel %>% filter(id %in% balanced_ids)

  # Exclude crisis cohorts
  if (length(exclude_years) > 0) {
    exclude_iso <- classified_events %>%
      filter(first_treat_year %in% exclude_years) %>%
      pull(iso3c)
    panel <- panel %>% filter(!iso3c %in% exclude_iso)
  }

  # Filter for USA-displaced treated + USA-was-#1 controls
  treated_usa <- classified_events %>% filter(displaced == "USA") %>% pull(iso3c)
  panel_usa <- panel %>%
    filter(iso3c %in% treated_usa | (first_treat == 0 & iso3c %in% usa_top_countries)) %>%
    mutate(id = as.integer(as.factor(iso3c))) %>%
    left_join(het_data, by = "iso3c")

  # Drop NAs in covariates
  cov_vars <- all.vars(xformla)
  if (length(cov_vars) > 0) {
    panel_usa <- panel_usa %>% drop_na(all_of(cov_vars))
    panel_usa <- panel_usa %>% mutate(id = as.integer(as.factor(iso3c)))
  }

  n_treated <- length(unique(panel_usa$iso3c[panel_usa$first_treat > 0]))
  n_control <- length(unique(panel_usa$iso3c[panel_usa$first_treat == 0]))

  tryCatch({
    r <- run_cross_country_did(panel_usa, xformla = xformla)
    oa <- r$overall_att
    data.frame(
      spec = spec_label,
      panel_start = start_year,
      excluded = paste(exclude_years, collapse = ","),
      n_treated = n_treated,
      n_control = n_control,
      att = oa$overall.att,
      se = oa$overall.se,
      p_value = 2 * (1 - pnorm(abs(oa$overall.att / oa$overall.se))),
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    data.frame(
      spec = spec_label, panel_start = start_year,
      excluded = paste(exclude_years, collapse = ","),
      n_treated = n_treated, n_control = n_control,
      att = NA_real_, se = NA_real_, p_value = NA_real_,
      stringsAsFactors = FALSE
    )
  })
}

# Define all specifications
specs <- list()
idx <- 0

for (start_yr in c(1990, 1991, 1995)) {
  for (excl in list(integer(0), 2008, 2009, c(2008, 2009))) {
    excl_label <- if (length(excl) == 0) "none" else paste(excl, collapse = "+")
    for (fm in list(
      list(f = ~1, name = "Baseline"),
      list(f = ~usa_streak, name = "+ Streak"),
      list(f = ~press_free, name = "+ Press"),
      list(f = ~usa_streak + press_free, name = "+ Both")
    )) {
      idx <- idx + 1
      label <- sprintf("Panel %d | Excl %s | %s", start_yr, excl_label, fm$name)
      specs[[idx]] <- list(start = start_yr, excl = excl, f = fm$f, label = label)
    }
  }
}

cat("Running", length(specs), "specifications...\n")

results <- list()
for (i in seq_along(specs)) {
  s <- specs[[i]]
  results[[i]] <- run_spec(s$start, s$excl, s$f, s$label)
  if (i %% 8 == 0) cat("  ", i, "/", length(specs), "done\n")
}

full_table <- bind_rows(results) %>%
  mutate(
    att = round(att, 4),
    se = round(se, 4),
    p_value = round(p_value, 4)
  )

print(as.data.frame(full_table))

write.csv(full_table, here("quality_reports", "table_full_specifications.csv"),
          row.names = FALSE)
cat("\nSaved: quality_reports/table_full_specifications.csv\n")
cat("Done.\n")
