#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────
# Exploratory analysis: Treatment-switching DiD estimators
# Runs OUTSIDE targets — reads from the _targets store only
# Output: quality_reports/switching_did_report.pdf
# ─────────────────────────────────────────────────────────────────────

library(targets)
library(tidyverse)
library(countrycode)
library(patchwork)
library(grid)
library(gridExtra)

# ── 1. Load data from targets store ──────────────────────────────────
cat("=== Loading data from targets ===\n")
trade_ranked   <- tar_read(trade_data_ranked)
classified     <- tar_read(classified_events)
es_data_usa    <- tar_read(event_study_data_usa)
unga           <- tar_read(unga_data)
trade_raw      <- tar_read(trade_data)

# ── 2. Build panel with binary switching treatment ───────────────────
did_countries <- unique(es_data_usa$iso3c)

rank_current <- trade_raw %>%
  group_by(year, exporter_iso3) %>%
  arrange(desc(exports)) %>%
  mutate(rank = row_number()) %>%
  ungroup() %>%
  filter(exporter_iso3 %in% did_countries,
         importer_iso3 %in% c("CHN", "USA")) %>%
  select(iso3c = exporter_iso3, year, partner = importer_iso3, rank) %>%
  pivot_wider(names_from = partner, values_from = rank, names_prefix = "rank_")

panel <- unga %>%
  filter(iso3c %in% did_countries, year >= 1990) %>%
  select(iso3c, year, abs_distance_china) %>%
  left_join(rank_current, by = c("iso3c", "year")) %>%
  mutate(
    china_top = as.integer(!is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA)),
    country_id = as.integer(as.factor(iso3c)),
    country_name = countrycode(iso3c, "iso3c", "country.name")
  ) %>%
  arrange(country_id, year)
panel$china_top[is.na(panel$china_top)] <- 0L

cat("Panel:", nrow(panel), "rows,", n_distinct(panel$iso3c), "countries,",
    n_distinct(panel$year), "years\n")

# Treatment summary
treat_summary <- panel %>%
  group_by(iso3c, country_name) %>%
  summarise(
    years = n(), treated_years = sum(china_top),
    switches = sum(abs(diff(china_top))),
    first_on = ifelse(any(china_top == 1), min(year[china_top == 1]), NA),
    .groups = "drop") %>%
  arrange(desc(treated_years))

cat("\n=== Treatment summary ===\n")
print(treat_summary, n = 100)

# ── 3. Start PDF ─────────────────────────────────────────────────────
pdf("quality_reports/switching_did_report.pdf", width = 11, height = 8.5)

# Title page
grid.newpage()
pushViewport(viewport(y = 0.7, height = 0.3, just = "center"))
grid.text("Treatment-Switching DiD Estimators:\nChina as #1 Trade Partner (On/Off)",
          gp = gpar(fontsize = 18, fontface = "bold"))
popViewport()
pushViewport(viewport(y = 0.5, height = 0.1, just = "center"))
grid.text(paste0("Date: ", Sys.Date(), "\nPanel: ", n_distinct(panel$iso3c),
                 " countries, ", min(panel$year), "-", max(panel$year)),
          gp = gpar(fontsize = 12))
popViewport()
pushViewport(viewport(y = 0.3, height = 0.2, just = "center"))
grid.text(paste0(
  "Treatment: china_top = 1 if China is currently #1 trade partner\n",
  "(switches on/off as trade rankings change)\n\n",
  "Estimators:\n",
  "  PanelMatch (Imai, Kim & Wang 2023 APSR) - ATT + ART\n",
  "  fect (Liu, Wang & Xu 2024 AJPS) - FE + IFE, entry/exit plots"
), gp = gpar(fontsize = 10))
popViewport()

# Treatment summary table
grid.newpage()
pushViewport(viewport(y = 0.95, height = 0.08, just = "top"))
grid.text("Table 1: Treatment switching patterns",
          gp = gpar(fontsize = 14, fontface = "bold"))
popViewport()

tbl1 <- treat_summary %>%
  filter(treated_years > 0) %>%
  select(Country = country_name, ISO3 = iso3c,
         Years = years, `Treated yrs` = treated_years,
         Switches = switches, `First on` = first_on)

pushViewport(viewport(y = 0.45, height = 0.8, just = "center"))
grid.draw(tableGrob(tbl1, rows = NULL,
                     theme = ttheme_minimal(base_size = 9,
                       core = list(fg_params = list(hjust = 0, x = 0.05)),
                       colhead = list(fg_params = list(hjust = 0, x = 0.05, fontface = "bold")))))
popViewport()

# ── 4. PanelMatch ────────────────────────────────────────────────────
cat("\n=== Running PanelMatch ===\n")
library(PanelMatch)

pm_df <- panel %>%
  select(country_id, year, abs_distance_china, china_top) %>%
  as.data.frame()

pd <- PanelData(
  panel.data = pm_df,
  unit.id = "country_id",
  time.id = "year",
  treatment = "china_top",
  outcome = "abs_distance_china"
)

# ATT: Effect of China becoming #1
cat("  PanelMatch ATT (switch on)...\n")
pm_att_ok <- FALSE
tryCatch({
  pm_att <- PanelMatch(
    panel.data = pd,
    lag = 1,
    refinement.method = "none",
    qoi = "att",
    lead = 0:8,
    match.missing = TRUE,
    forbid.treatment.reversal = FALSE
  )
  est_att <- PanelEstimate(sets = pm_att, panel.data = pd, number.iterations = 1000)
  pm_att_ok <- TRUE
  cat("  ATT done.\n")
}, error = function(e) {
  cat("  ATT failed:", conditionMessage(e), "\n")
})

# ART: Effect of USA regaining #1 (reversal)
cat("  PanelMatch ART (switch off)...\n")
pm_art_ok <- FALSE
tryCatch({
  pm_art <- PanelMatch(
    panel.data = pd,
    lag = 1,
    refinement.method = "none",
    qoi = "art",
    lead = 0:8,
    match.missing = TRUE,
    forbid.treatment.reversal = FALSE
  )
  est_art <- PanelEstimate(sets = pm_art, panel.data = pd, number.iterations = 1000)
  pm_art_ok <- TRUE
  cat("  ART done.\n")
}, error = function(e) {
  cat("  ART failed:", conditionMessage(e), "\n")
})

# Plot PanelMatch results
if (pm_att_ok) {
  att_s <- summary(est_att)  # returns matrix directly in v3
  att_df <- data.frame(lead = 0:min(8, nrow(att_s)-1),
                        estimate = att_s[1:min(9, nrow(att_s)), "estimate"],
                        se = att_s[1:min(9, nrow(att_s)), "std.error"],
                        ci_lo = att_s[1:min(9, nrow(att_s)), "2.5%"],
                        ci_hi = att_s[1:min(9, nrow(att_s)), "97.5%"])

  p_att <- ggplot(att_df, aes(x = lead, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, fill = "steelblue") +
    geom_line(colour = "steelblue", linewidth = 0.8) +
    geom_point(colour = "steelblue", size = 2) +
    labs(title = "PanelMatch: ATT (China becomes #1)",
         subtitle = paste0("Effect of treatment turning ON (", nrow(att_s), " leads)"),
         x = "Periods after switch-on", y = "ATT (abs. distance to China)") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())
}

if (pm_art_ok) {
  art_s <- summary(est_art)  # returns matrix directly in v3
  art_df <- data.frame(lead = 0:min(8, nrow(art_s)-1),
                        estimate = art_s[1:min(9, nrow(art_s)), "estimate"],
                        se = art_s[1:min(9, nrow(art_s)), "std.error"],
                        ci_lo = art_s[1:min(9, nrow(art_s)), "2.5%"],
                        ci_hi = art_s[1:min(9, nrow(art_s)), "97.5%"])

  p_art <- ggplot(art_df, aes(x = lead, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, fill = "firebrick") +
    geom_line(colour = "firebrick", linewidth = 0.8) +
    geom_point(colour = "firebrick", size = 2) +
    labs(title = "PanelMatch: ART (USA regains #1)",
         subtitle = paste0("Effect of treatment turning OFF (reversal, ", nrow(art_s), " leads)"),
         x = "Periods after switch-off", y = "ART (abs. distance to China)") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())
}

if (pm_att_ok && pm_art_ok) {
  print(p_att / p_art + plot_annotation(
    title = "PanelMatch: Entry vs. Exit Effects",
    subtitle = "Imai, Kim & Wang (2023, APSR) - lag = 1, no refinement"
  ))
} else if (pm_att_ok) {
  print(p_att)
} else if (pm_art_ok) {
  print(p_art)
}

# PanelMatch numerical table
if (pm_att_ok || pm_art_ok) {
  grid.newpage()
  pushViewport(viewport(y = 0.95, height = 0.08, just = "top"))
  grid.text("PanelMatch: Numerical Results", gp = gpar(fontsize = 14, fontface = "bold"))
  popViewport()

  combined_pm <- bind_rows(
    if (pm_att_ok) att_df %>% mutate(Estimand = "ATT (switch on)") else NULL,
    if (pm_art_ok) art_df %>% mutate(Estimand = "ART (switch off)") else NULL
  ) %>%
    mutate(across(c(estimate, se, ci_lo, ci_hi), ~round(., 3))) %>%
    select(Estimand, Lead = lead, Estimate = estimate, SE = se,
           `CI low` = ci_lo, `CI high` = ci_hi)

  pushViewport(viewport(y = 0.45, height = 0.8, just = "center"))
  grid.draw(tableGrob(combined_pm, rows = NULL,
                       theme = ttheme_minimal(base_size = 8,
                         core = list(fg_params = list(hjust = 0.5)),
                         colhead = list(fg_params = list(fontface = "bold")))))
  popViewport()
}

# ── 5. fect ──────────────────────────────────────────────────────────
cat("\n=== Running fect ===\n")
library(fect)

fect_data <- panel %>%
  select(country_id, year, abs_distance_china, china_top) %>%
  as.data.frame()

# FE with placebo test
cat("  fect FE + placebo...\n")
fect_fe_ok <- FALSE
tryCatch({
  fect_fe <- fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "fe", force = "two-way",
    se = TRUE, nboots = 500, parallel = FALSE,
    placeboTest = TRUE, placebo.period = c(-5, -1)
  )
  fect_fe_ok <- TRUE
  cat("  FE done.\n")
}, error = function(e) cat("  FE failed:", conditionMessage(e), "\n"))

# FE with carryover test (separate run)
cat("  fect FE + carryover...\n")
fect_carry_ok <- FALSE
tryCatch({
  fect_carry <- fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "fe", force = "two-way",
    se = TRUE, nboots = 500, parallel = FALSE,
    carryoverTest = TRUE, carryover.period = c(1, 5)
  )
  fect_carry_ok <- TRUE
  cat("  Carryover done.\n")
}, error = function(e) cat("  Carryover failed:", conditionMessage(e), "\n"))

# IFE model
cat("  fect IFE...\n")
fect_ife_ok <- FALSE
tryCatch({
  fect_ife <- fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "ife", force = "two-way",
    se = TRUE, nboots = 500, parallel = FALSE,
    CV = TRUE, r = c(0, 3)
  )
  fect_ife_ok <- TRUE
  cat("  IFE done. r* =", fect_ife$r.cv, "\n")
}, error = function(e) cat("  IFE failed:", conditionMessage(e), "\n"))

# Helper to extract ATT summary from fect
fect_att_se <- function(fit) {
  se <- sd(fit$att.avg.boot)
  p <- 2 * pnorm(-abs(fit$att.avg / se))
  list(att = fit$att.avg, se = se,
       ci_lo = fit$att.avg - 1.96 * se,
       ci_hi = fit$att.avg + 1.96 * se,
       p = p)
}

# Plot fect FE: gap (entry-aligned)
if (fect_fe_ok) {
  plot(fect_fe, main = "fect (FE): Entry-aligned gap plot",
       ylab = "Effect on abs. distance to China",
       xlab = "Periods relative to treatment entry",
       show.points = TRUE, type = "gap")

  # Exit-aligned gap plot
  plot(fect_fe, main = "fect (FE): Exit-aligned gap plot",
       ylab = "Effect on abs. distance to China",
       xlab = "Periods relative to treatment exit",
       show.points = TRUE, type = "exit")

  # Placebo test
  if (!is.null(fect_fe$placebo.test)) {
    plot(fect_fe, type = "placebo",
         main = "fect (FE): Placebo test (pre-treatment periods)")
  }
}

# Carryover test plot
if (fect_carry_ok && !is.null(fect_carry$carryover.test)) {
  plot(fect_carry, type = "carryover",
       main = "fect (FE): Carryover test (post-exit periods)")
}

# IFE plots
if (fect_ife_ok) {
  plot(fect_ife, main = paste0("fect (IFE, r=", fect_ife$r.cv, "): Entry-aligned gap plot"),
       ylab = "Effect on abs. distance to China",
       xlab = "Periods relative to treatment entry",
       show.points = TRUE, type = "gap")

  plot(fect_ife, main = paste0("fect (IFE, r=", fect_ife$r.cv, "): Exit-aligned gap plot"),
       ylab = "Effect on abs. distance to China",
       xlab = "Periods relative to treatment exit",
       show.points = TRUE, type = "exit")
}

# fect numerical summary page
grid.newpage()
pushViewport(viewport(y = 0.92, height = 0.08, just = "top"))
grid.text("fect: Numerical Summary", gp = gpar(fontsize = 14, fontface = "bold"))
popViewport()

txt <- ""
if (fect_fe_ok) {
  fe_s <- fect_att_se(fect_fe)
  txt <- paste0(txt,
    "Fixed Effects (FE) model:\n",
    "  Overall ATT: ", round(fe_s$att, 3), "\n",
    "  SE (bootstrap): ", round(fe_s$se, 3), "\n",
    "  95% CI: [", round(fe_s$ci_lo, 3), ", ", round(fe_s$ci_hi, 3), "]\n",
    "  p-value: ", round(fe_s$p, 4), "\n\n"
  )
  if (!is.null(fect_fe$placebo.test)) {
    txt <- paste0(txt,
      "  Placebo test (pre-trend): p = ", round(fect_fe$placebo.test$p, 4), "\n",
      "    (H0: no pre-treatment effects in periods -5 to -1)\n\n"
    )
  }
}

if (fect_carry_ok && !is.null(fect_carry$carryover.test)) {
  txt <- paste0(txt,
    "  Carryover test: p = ", round(fect_carry$carryover.test$p, 4), "\n",
    "    (H0: no lingering effects 1-5 periods after treatment exits)\n",
    "    Low p = treatment has lasting effects even after China loses #1\n\n"
  )
}

if (fect_ife_ok) {
  ife_s <- fect_att_se(fect_ife)
  txt <- paste0(txt,
    "Interactive Fixed Effects (IFE) model (r* = ", fect_ife$r.cv, "):\n",
    "  Overall ATT: ", round(ife_s$att, 3), "\n",
    "  SE (bootstrap): ", round(ife_s$se, 3), "\n",
    "  95% CI: [", round(ife_s$ci_lo, 3), ", ", round(ife_s$ci_hi, 3), "]\n",
    "  p-value: ", round(ife_s$p, 4), "\n\n",
    "  IFE relaxes strict parallel trends via latent factors.\n"
  )
}

pushViewport(viewport(y = 0.5, height = 0.7, just = "center"))
grid.text(txt, gp = gpar(fontsize = 11, fontfamily = "mono"), just = "left", x = 0.05)
popViewport()

# ── 6. Final summary ─────────────────────────────────────────────────
grid.newpage()
pushViewport(viewport(y = 0.92, height = 0.08, just = "top"))
grid.text("Summary: Cross-Method Comparison", gp = gpar(fontsize = 14, fontface = "bold"))
popViewport()

summary_lines <- "Method                | ATT (switch on) | ART (switch off) | Notes\n"
summary_lines <- paste0(summary_lines, paste(rep("-", 80), collapse = ""), "\n")

if (pm_att_ok) {
  a0 <- att_df$estimate[1]; a0_se <- att_df$se[1]
  summary_lines <- paste0(summary_lines,
    sprintf("PanelMatch ATT (t=0)  | %6.3f (%5.3f)  |", a0, a0_se))
  if (pm_art_ok) {
    r0 <- art_df$estimate[1]; r0_se <- art_df$se[1]
    summary_lines <- paste0(summary_lines,
      sprintf(" %6.3f (%5.3f)  | Matching, lag=1\n", r0, r0_se))
  } else {
    summary_lines <- paste0(summary_lines, "      N/A       | ATT only\n")
  }
}

if (fect_fe_ok) {
  fe_s <- fect_att_se(fect_fe)
  summary_lines <- paste0(summary_lines,
    sprintf("fect (FE)             | %6.3f (%5.3f)  |   see exit plot  | Two-way FE\n",
            fe_s$att, fe_s$se))
}

if (fect_ife_ok) {
  ife_s <- fect_att_se(fect_ife)
  summary_lines <- paste0(summary_lines,
    sprintf("fect (IFE, r=%d)       | %6.3f (%5.3f)  |   see exit plot  | Interactive FE\n",
            fect_ife$r.cv, ife_s$att, ife_s$se))
}

pushViewport(viewport(y = 0.6, height = 0.5, just = "center"))
grid.text(summary_lines, gp = gpar(fontsize = 10, fontfamily = "mono"),
          just = "left", x = 0.05)
popViewport()

pushViewport(viewport(y = 0.25, height = 0.2, just = "center"))
grid.text(paste0(
  "Interpretation:\n",
  "  ATT < 0 => When China becomes #1, country moves CLOSER to China in UNGA\n",
  "  ART > 0 => When USA regains #1, country moves AWAY from China (back toward USA)\n",
  "  Both significant with opposite signs = strong evidence for the mechanism\n\n",
  "Key tests:\n",
  "  fect placebo test: validates pre-treatment parallel trends\n",
  "  fect carryover test: does the China effect linger after exit?\n",
  "  fect exit plot: dynamic effect of treatment turning OFF"
), gp = gpar(fontsize = 10), just = "left", x = 0.05)
popViewport()

dev.off()
cat("\n=== Report saved to quality_reports/switching_did_report.pdf ===\n")
