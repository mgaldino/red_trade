# =============================================================================
# Cross-country DiD with covariates (outside targets)
# Runs fect IFE and C&S with: log GDP pc, free press (V-Dem), USA streak
# =============================================================================

library(targets)
library(dplyr)
library(tidyr)
library(fect)
library(did)

source("scripts/functions.R")

# --- 1. Load targets objects ------------------------------------------------

sw_panel       <- tar_read(switching_panel)
cs_data        <- as.data.frame(tar_read(event_study_data_usa))
final_df       <- tar_read(final_df)
classified_ev  <- tar_read(classified_events)
trade_data     <- tar_read(trade_data)

cat("=== Switching panel:", nrow(sw_panel), "obs,",
    n_distinct(sw_panel$iso3c), "countries ===\n")
cat("=== C&S panel:", nrow(cs_data), "obs,",
    n_distinct(cs_data$id), "units ===\n")

# --- 2. Build covariates ----------------------------------------------------

# 2a. GDP per capita from final_df
gdp_cov <- final_df %>%
  mutate(log_gdp_pc = log(gdp_cur / pop)) %>%
  dplyr::select(iso3c, year, log_gdp_pc) %>%
  dplyr::filter(!is.na(log_gdp_pc))

cat("\nGDP pc available for", n_distinct(gdp_cov$iso3c), "countries\n")

# 2b. Free press from V-Dem (v2x_freexp_altinf)
cat("Loading V-Dem data...\n")
vdem <- vdemdata::vdem %>%
  dplyr::select(country_text_id, year, v2x_freexp_altinf) %>%
  dplyr::filter(year >= 1990, !is.na(v2x_freexp_altinf)) %>%
  dplyr::rename(iso3c = country_text_id, free_press = v2x_freexp_altinf)

cat("V-Dem free press available for", n_distinct(vdem$iso3c),
    "countries, years", min(vdem$year), "-", max(vdem$year), "\n")

# 2c. USA streak (consecutive years US was #1 export destination)
rank_data <- trade_data %>%
  group_by(year, exporter_iso3) %>%
  arrange(desc(exports)) %>%
  mutate(rank = row_number()) %>%
  ungroup() %>%
  dplyr::filter(importer_iso3 %in% c("CHN", "USA")) %>%
  dplyr::select(iso3c = exporter_iso3, year,
                partner = importer_iso3, rank) %>%
  pivot_wider(names_from = partner, values_from = rank, names_prefix = "rank_") %>%
  mutate(usa_is_top = as.integer(!is.na(rank_USA) &
                                   (is.na(rank_CHN) | rank_USA < rank_CHN)))

usa_streak <- rank_data %>%
  arrange(iso3c, year) %>%
  group_by(iso3c) %>%
  mutate(
    streak_reset = cumsum(c(1, diff(usa_is_top) != 0)),
    streak = ave(usa_is_top, streak_reset, FUN = cumsum)
  ) %>%
  ungroup() %>%
  mutate(usa_streak = ifelse(usa_is_top == 1, streak, 0)) %>%
  dplyr::select(iso3c, year, usa_streak)

cat("USA streak computed for", n_distinct(usa_streak$iso3c), "countries\n")

# --- 3. Merge all covariates into switching panel ---------------------------

sw_cov <- sw_panel %>%
  left_join(gdp_cov, by = c("iso3c", "year")) %>%
  left_join(vdem, by = c("iso3c", "year")) %>%
  left_join(usa_streak, by = c("iso3c", "year"))

cat("\nSwitching panel after merging covariates:\n")
cat("  Missing log_gdp_pc:", sum(is.na(sw_cov$log_gdp_pc)), "/", nrow(sw_cov), "\n")
cat("  Missing free_press:", sum(is.na(sw_cov$free_press)), "/", nrow(sw_cov), "\n")
cat("  Missing usa_streak:", sum(is.na(sw_cov$usa_streak)), "/", nrow(sw_cov), "\n")
cat("  Complete (all 3):", sum(complete.cases(
  sw_cov[, c("log_gdp_pc", "free_press", "usa_streak")])), "/", nrow(sw_cov), "\n")

# --- 4. fect IFE specifications ---------------------------------------------

cat("\n=== Running fect IFE specifications ===\n\n")

run_fect_spec <- function(data, formula, label) {
  fit <- fect(
    formula,
    data = data,
    index = c("country_id", "year"),
    method = "ife", force = "two-way",
    se = TRUE, nboots = 500, parallel = FALSE,
    CV = TRUE, r = c(0, 3)
  )
  s <- fect_att_summary(fit)
  n_obs <- nrow(data)
  n_treat <- n_distinct(data$country_id[data$china_top == 1])
  n_ctrl <- n_distinct(data$country_id) - n_treat
  cat(sprintf("  %-35s ATT=%.4f  SE=%.4f  p=%.4f  r*=%d  N=%d  Nt=%d  Nc=%d\n",
              label, s$att, s$se, s$p, s$r_cv, n_obs, n_treat, n_ctrl))
  list(s = s, n_obs = n_obs, n_treat = n_treat, n_ctrl = n_ctrl)
}

# Spec 1: Baseline (no covariates)
d1 <- sw_panel %>%
  dplyr::select(country_id, year, abs_distance_china, china_top) %>%
  as.data.frame()
r1 <- run_fect_spec(d1, abs_distance_china ~ china_top, "Baseline (no cov.)")

# Spec 2: + log GDP per capita
d2 <- sw_cov %>%
  dplyr::filter(!is.na(log_gdp_pc)) %>%
  mutate(country_id = as.integer(as.factor(iso3c))) %>%
  dplyr::select(country_id, year, abs_distance_china, china_top, log_gdp_pc) %>%
  as.data.frame()
r2 <- run_fect_spec(d2, abs_distance_china ~ china_top + log_gdp_pc, "+ log GDP pc")

# Spec 3: + log GDP pc + free press
d3 <- sw_cov %>%
  dplyr::filter(!is.na(log_gdp_pc) & !is.na(free_press)) %>%
  mutate(country_id = as.integer(as.factor(iso3c))) %>%
  dplyr::select(country_id, year, abs_distance_china, china_top,
                log_gdp_pc, free_press) %>%
  as.data.frame()
r3 <- run_fect_spec(d3, abs_distance_china ~ china_top + log_gdp_pc + free_press,
                    "+ log GDP pc + free press")

# Spec 4: + log GDP pc + free press + USA streak
d4 <- sw_cov %>%
  dplyr::filter(!is.na(log_gdp_pc) & !is.na(free_press) & !is.na(usa_streak)) %>%
  mutate(country_id = as.integer(as.factor(iso3c))) %>%
  dplyr::select(country_id, year, abs_distance_china, china_top,
                log_gdp_pc, free_press, usa_streak) %>%
  as.data.frame()
r4 <- run_fect_spec(d4, abs_distance_china ~ china_top + log_gdp_pc + free_press + usa_streak,
                    "+ log GDP pc + free press + streak")

# --- 5. C&S with covariates ------------------------------------------------

cat("\n=== Running C&S specifications ===\n\n")

# Merge covariates into C&S panel
cs_cov <- cs_data %>%
  left_join(gdp_cov, by = c("iso3c", "year")) %>%
  left_join(vdem, by = c("iso3c", "year")) %>%
  left_join(usa_streak, by = c("iso3c", "year"))

run_cs_spec <- function(data, xformla, label) {
  tryCatch({
    fit <- did::att_gt(
      yname = "abs_distance_china",
      tname = "year", idname = "id", gname = "first_treat",
      xformla = xformla,
      data = as.data.frame(data),
      control_group = "nevertreated",
      base_period = "universal"
    )
    agg <- did::aggte(fit, type = "simple")
    p <- 2 * pnorm(-abs(agg$overall.att / agg$overall.se))
    n_obs <- nrow(data)
    n_treat <- sum(data$first_treat > 0)
    cat(sprintf("  %-35s ATT=%.4f  SE=%.4f  p=%.4f  N=%d\n",
                label, agg$overall.att, agg$overall.se, p, n_obs))
    list(att = agg$overall.att, se = agg$overall.se, p = p, n_obs = n_obs)
  }, error = function(e) {
    cat(sprintf("  %-35s ERROR: %s\n", label, conditionMessage(e)))
    NULL
  })
}

# Balance helper
balance_panel <- function(df) {
  max_yr <- max(table(df$id))
  bal_ids <- df %>% group_by(id) %>%
    summarise(n = n(), .groups = "drop") %>%
    dplyr::filter(n == max_yr) %>% pull(id)
  df %>% dplyr::filter(id %in% bal_ids)
}

# Spec 1: Baseline
cs1 <- run_cs_spec(cs_data, ~1, "Baseline (no cov.)")

# Spec 2: + log GDP pc
cs_d2 <- cs_cov %>% dplyr::filter(!is.na(log_gdp_pc)) %>% balance_panel()
cs2 <- run_cs_spec(cs_d2, ~ log_gdp_pc, "+ log GDP pc")

# Spec 3: + log GDP pc + free press
cs_d3 <- cs_cov %>%
  dplyr::filter(!is.na(log_gdp_pc) & !is.na(free_press)) %>%
  balance_panel()
cs3 <- run_cs_spec(cs_d3, ~ log_gdp_pc + free_press, "+ log GDP pc + free press")

# Spec 4: + log GDP pc + free press + USA streak
cs_d4 <- cs_cov %>%
  dplyr::filter(!is.na(log_gdp_pc) & !is.na(free_press) & !is.na(usa_streak)) %>%
  balance_panel()
cs4 <- run_cs_spec(cs_d4, ~ log_gdp_pc + free_press + usa_streak,
                   "+ log GDP pc + free press + streak")

# --- 6. Summary table -------------------------------------------------------

cat("\n\n==================== SUMMARY ====================\n\n")
cat(sprintf("%-40s %8s %8s %8s %4s %6s\n",
            "Specification", "ATT", "SE", "p-val", "r*", "N"))
cat(paste(rep("=", 75), collapse = ""), "\n")
cat("fect IFE (switching treatment)\n")
cat(paste(rep("-", 75), collapse = ""), "\n")
for (r in list(
  list(r1, "Baseline (no cov.)"),
  list(r2, "+ log GDP pc"),
  list(r3, "+ log GDP pc + free press"),
  list(r4, "+ log GDP pc + free press + streak")
)) {
  cat(sprintf("  %-38s %8.4f %8.4f %8.4f %4d %6d\n",
              r[[2]], r[[1]]$s$att, r[[1]]$s$se, r[[1]]$s$p,
              r[[1]]$s$r_cv, r[[1]]$n_obs))
}
cat(paste(rep("=", 75), collapse = ""), "\n")

cat("\nDone.\n")
