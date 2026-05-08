#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────
# Exploratory report: Trade rank reversals & UNGA alignment
# Runs OUTSIDE targets — reads from the _targets store only
# Output: quality_reports/reversal_exploration.pdf
# ─────────────────────────────────────────────────────────────────────

library(targets)
library(tidyverse)
library(countrycode)
library(patchwork)
library(knitr)
library(kableExtra)
library(grid)
library(gridExtra)

# ── 1. Load data from targets store ──────────────────────────────────
trade_ranked   <- tar_read(trade_data_ranked)
classified     <- tar_read(classified_events)
es_data_usa    <- tar_read(event_study_data_usa)
unga           <- tar_read(unga_data)
trade_raw      <- tar_read(trade_data)

# ── 2. Which countries are actually in the DiD? ──────────────────────
treated_in_did <- es_data_usa %>%
  filter(first_treat > 0) %>%
  distinct(iso3c, first_treat)

control_in_did <- es_data_usa %>%
  filter(first_treat == 0) %>%
  distinct(iso3c)

cat("=== Countries treated in the DiD (event_study_data_usa) ===\n")
cat("N treated:", nrow(treated_in_did), "\n")
print(treated_in_did %>% arrange(first_treat))

cat("\nN controls:", nrow(control_in_did), "\n")

# ── 3. Classify: absorbing vs switching among DiD-treated ────────────
did_classified <- treated_in_did %>%
  left_join(classified, by = "iso3c") %>%
  select(iso3c, first_treat, absorbing, displaced)

cat("\n=== Classification of DiD-treated countries ===\n")
print(did_classified %>% arrange(first_treat))

cat("\nAbsorbing:", sum(did_classified$absorbing), "\n")
cat("Switching:", sum(!did_classified$absorbing), "\n")

# ── 4. Build full rank history for treated countries ─────────────────
# For each treated country: yearly ranking of top trade partners
rank_history <- trade_raw %>%
  group_by(year, exporter_iso3) %>%
  arrange(desc(exports)) %>%
  mutate(rank = row_number()) %>%
  ungroup() %>%
  filter(exporter_iso3 %in% treated_in_did$iso3c,
         importer_iso3 %in% c("CHN", "USA")) %>%
  select(iso3c = exporter_iso3, year, partner = importer_iso3, exports, rank)

# Pivot: China rank vs USA rank per country-year
rank_wide <- rank_history %>%
  select(iso3c, year, partner, rank) %>%
  pivot_wider(names_from = partner, values_from = rank, names_prefix = "rank_") %>%
  left_join(treated_in_did, by = "iso3c") %>%
  mutate(
    china_is_top = !is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA),
    country_name = countrycode(iso3c, "iso3c", "country.name")
  )

# ── 5. Identify re-reversal spells ──────────────────────────────────
reversal_detail <- rank_wide %>%
  filter(year >= first_treat) %>%
  group_by(iso3c, country_name, first_treat) %>%
  summarise(
    years_post = n(),
    years_china_top = sum(china_is_top, na.rm = TRUE),
    years_usa_top = sum(!china_is_top, na.rm = TRUE),
    pct_china_top = round(years_china_top / years_post * 100, 1),
    reversal_years = paste(year[!china_is_top], collapse = ", "),
    .groups = "drop"
  ) %>%
  arrange(first_treat)

cat("\n=== Re-reversal detail for DiD-treated countries ===\n")
print(reversal_detail)

# ── 6. UNGA distance for treated countries ───────────────────────────
unga_treated <- unga %>%
  filter(iso3c %in% treated_in_did$iso3c) %>%
  select(iso3c, year, abs_distance_china) %>%
  left_join(treated_in_did, by = "iso3c") %>%
  left_join(rank_wide %>% select(iso3c, year, china_is_top, rank_CHN, rank_USA),
            by = c("iso3c", "year")) %>%
  mutate(country_name = countrycode(iso3c, "iso3c", "country.name"))

# ── 7. Generate PDF ─────────────────────────────────────────────────
pdf("quality_reports/reversal_exploration.pdf", width = 11, height = 8.5)

# --- Page 1: Summary table ---
# Use grid graphics for the table

tbl_display <- reversal_detail %>%
  mutate(reversal_years = ifelse(reversal_years == "", "None", reversal_years)) %>%
  select(
    Country = country_name,
    ISO3 = iso3c,
    `Treat. year` = first_treat,
    `Post years` = years_post,
    `China #1` = years_china_top,
    `USA #1` = years_usa_top,
    `% China #1` = pct_china_top,
    `USA re-reversal years` = reversal_years
  )

grid.newpage()
pushViewport(viewport(y = 0.95, height = 0.08, just = "top"))
grid.text("Table 1: Trade rank status of DiD-treated countries (post-treatment)",
          gp = gpar(fontsize = 14, fontface = "bold"))
popViewport()

pushViewport(viewport(y = 0.45, height = 0.85, just = "center"))
grid.draw(tableGrob(tbl_display, rows = NULL,
                     theme = ttheme_minimal(base_size = 9,
                       core = list(fg_params = list(hjust = 0, x = 0.02)),
                       colhead = list(fg_params = list(hjust = 0, x = 0.02, fontface = "bold")))))
popViewport()

# Also add absorbing classification
tbl_class <- did_classified %>%
  mutate(
    country_name = countrycode(iso3c, "iso3c", "country.name"),
    absorbing_label = ifelse(absorbing, "Yes (absorbing)", "No (switching)")
  ) %>%
  select(Country = country_name, ISO3 = iso3c,
         `Treat. year` = first_treat,
         `Absorbing?` = absorbing_label,
         `Displaced` = displaced) %>%
  arrange(`Treat. year`)

grid.newpage()
pushViewport(viewport(y = 0.95, height = 0.08, just = "top"))
grid.text("Table 2: Treatment classification — absorbing vs. switching",
          gp = gpar(fontsize = 14, fontface = "bold"))
popViewport()

pushViewport(viewport(y = 0.55, height = 0.7, just = "center"))
grid.draw(tableGrob(tbl_class, rows = NULL,
                     theme = ttheme_minimal(base_size = 10,
                       core = list(fg_params = list(hjust = 0, x = 0.05)),
                       colhead = list(fg_params = list(hjust = 0, x = 0.05, fontface = "bold")))))
popViewport()

pushViewport(viewport(y = 0.15, height = 0.1, just = "center"))
grid.text(paste0("Note: Callaway & Sant'Anna DiD assumes absorbing treatment.\n",
                 "Countries marked 'switching' violate this assumption — China lost #1 back to USA."),
          gp = gpar(fontsize = 9, col = "red"))
popViewport()


# --- Pages 2+: Individual country plots ---
# For each treated country: UNGA distance + shaded periods where China is #1

countries_to_plot <- unga_treated %>%
  distinct(iso3c, country_name, first_treat) %>%
  arrange(first_treat)

for (i in seq_len(nrow(countries_to_plot))) {
  cty <- countries_to_plot$iso3c[i]
  cty_name <- countries_to_plot$country_name[i]
  treat_yr <- countries_to_plot$first_treat[i]

  # Classification info
  is_absorbing <- did_classified$absorbing[did_classified$iso3c == cty]
  absorb_label <- ifelse(is_absorbing, "Absorbing", "SWITCHING")

  # Data for this country
  cty_data <- unga_treated %>%
    filter(iso3c == cty, year >= 1990)

  # Create shading rectangles for periods China is #1
  shade_data <- cty_data %>%
    filter(!is.na(china_is_top)) %>%
    mutate(china_top_num = as.integer(china_is_top))

  # Build consecutive spells
  spells <- shade_data %>%
    arrange(year) %>%
    mutate(spell_id = cumsum(c(1, diff(china_top_num) != 0))) %>%
    group_by(spell_id, china_is_top) %>%
    summarise(start = min(year), end = max(year), .groups = "drop") %>%
    filter(china_is_top)

  # Rank history for subplot
  rank_cty <- rank_wide %>%
    filter(iso3c == cty) %>%
    select(year, rank_CHN, rank_USA) %>%
    pivot_longer(cols = c(rank_CHN, rank_USA),
                 names_to = "partner", values_to = "rank") %>%
    mutate(partner = ifelse(partner == "rank_CHN", "China", "USA"))

  # Top panel: UNGA distance
  p1 <- ggplot(cty_data, aes(x = year, y = abs_distance_china)) +
    {if (nrow(spells) > 0)
      geom_rect(data = spells,
                aes(xmin = start - 0.5, xmax = end + 0.5, ymin = -Inf, ymax = Inf),
                inherit.aes = FALSE, fill = "red", alpha = 0.12)} +
    geom_line(colour = "steelblue", linewidth = 0.8) +
    geom_point(colour = "steelblue", size = 1.5) +
    geom_vline(xintercept = treat_yr, linetype = "dashed", colour = "red", linewidth = 0.7) +
    geom_smooth(method = "loess", se = FALSE, colour = "grey40", linetype = "dotted", span = 0.4) +
    labs(title = paste0(cty_name, " (", cty, ") — Treatment: ", treat_yr, " [", absorb_label, "]"),
         subtitle = "Red shading = China is #1 trade partner. Dashed line = treatment year.",
         y = "Abs. distance to China (UNGA)",
         x = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          plot.title = element_text(face = "bold"))

  # Bottom panel: Trade rank of China vs USA
  p2 <- ggplot(rank_cty, aes(x = year, y = rank, colour = partner)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.5) +
    geom_vline(xintercept = treat_yr, linetype = "dashed", colour = "red", linewidth = 0.7) +
    scale_y_reverse(breaks = 1:10) +
    scale_colour_manual(values = c("China" = "red3", "USA" = "navy")) +
    labs(subtitle = "Trade partner rank (1 = top)",
         y = "Rank", x = "Year", colour = "Partner") +
    coord_cartesian(ylim = c(10, 1)) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          legend.position = "bottom")

  print(p1 / p2 + plot_layout(heights = c(2, 1)))
}

# --- Final page: Summary of concern ---
grid.newpage()
pushViewport(viewport(y = 0.9, height = 0.08, just = "top"))
grid.text("Summary: Implications for the DiD",
          gp = gpar(fontsize = 14, fontface = "bold"))
popViewport()

n_switch <- sum(!did_classified$absorbing)
n_total <- nrow(did_classified)

summary_text <- paste0(
  "Of the ", n_total, " treated countries in the DiD specification:\n\n",
  "  - ", n_total - n_switch, " have absorbing treatment (China stays #1 permanently)\n",
  "  - ", n_switch, " have switching treatment (USA regained #1 at some point)\n\n",
  "Callaway & Sant'Anna (2021) assumes absorbing treatment (once treated, always treated).\n",
  "Countries with switching treatment violate this assumption.\n\n",
  "Options to consider:\n",
  "  (a) Restrict DiD to absorbing-only countries (target: did_absorbing_usa)\n",
  "  (b) Re-define treatment as 'ever had China as #1' (current approach, absorbing by construction)\n",
  "  (c) If re-reversal countries show UNGA rebound, this is actually evidence FOR the mechanism\n",
  "      but requires a different estimator (e.g., treatment switching, stacked DiD with exit)\n\n",
  "See individual country plots above for visual evidence of alignment patterns."
)

pushViewport(viewport(y = 0.55, height = 0.6, just = "center"))
grid.text(summary_text, gp = gpar(fontsize = 11), just = "left", x = 0.05)
popViewport()

dev.off()

cat("\n✓ Report saved to quality_reports/reversal_exploration.pdf\n")
