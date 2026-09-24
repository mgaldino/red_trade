#!/usr/bin/env Rscript

# Descriptive check of human-rights voting for the seven public-cue cases
# (exploratory). Ordinal vote distance to China (yes/abstain/no = 1/0/-1;
# |vote - China's vote|, 0 to 2; absences left out) by country, year (session +
# 1945) and domain (human rights vs other). Change in the gap to the mean of the
# 105 controls between the six years before the cue and cue..cue+6 (to 2019), and
# the same against controls of the same World Bank region. Also splits Australia's
# 2006-2008 plenary votes at 3 December (Howard -> Rudd). Source: unvotes 0.3.0.
#
# Exploratory and outside the targets graph; listed in TARGETS_MIGRATION.md.
#   Rscript scripts/diagnostics/public_cue_hr_votes_descriptive.R

suppressPackageStartupMessages({library(dplyr); library(targets)})
options(width = 200)
source(file.path("scripts", "functions.R"))
tb <- selective_unga_load_unvotes_tables(tar_read(unvotes_tarball))
p <- tar_read(china_top_m2_goods_panel) |>
  mutate(year = as.integer(year), iso3c = as.character(iso3c), china_is_top = as.logical(china_is_top))
controls <- p |> filter(year >= 1997, year <= 2022) |> group_by(iso3c) |>
  summarise(ok = n_distinct(year) == 26 & all(!is.na(abs_distance_china)) & all(!is.na(china_is_top)) & !any(china_is_top %in% TRUE), .groups = "drop") |>
  filter(ok) |> pull(iso3c)
stopifnot(length(controls) == 105)
cases <- tibble::tribble(~iso3c, ~cue, "KOR", 2003L, "AUS", 2007L, "CHL", 2007L, "BRA", 2009L, "ZAF", 2010L, "URY", 2013L, "NZL", 2013L)
hr_rcid <- tb$un_roll_call_issues |> filter(as.character(issue) == "Human rights") |> distinct(rcid) |> pull(rcid)
rc <- tb$un_roll_calls |> transmute(rcid, year = as.integer(session) + 1945L, date) |> filter(year >= 1991)
v <- tb$un_votes |> mutate(vote = as.character(vote),
        iso3c = countrycode::countrycode(country_code, "iso2c", "iso3c", warn = FALSE)) |>
  filter(vote %in% c("yes", "abstain", "no"), rcid %in% rc$rcid) |>
  mutate(score = c(no = -1, abstain = 0, yes = 1)[vote]) |> select(rcid, iso3c, score)
chn <- v |> filter(iso3c == "CHN") |> select(rcid, chn = score)
d <- v |> filter(iso3c %in% c(controls, cases$iso3c)) |> inner_join(chn, by = "rcid") |>
  inner_join(rc, by = "rcid") |> mutate(dist = abs(score - chn), hr = rcid %in% hr_rcid)
cat("controls with votes:", n_distinct(d$iso3c[d$iso3c %in% controls]), "\n")
cy <- d |> group_by(iso3c, year, hr) |> summarise(dist = mean(dist), n = n(), .groups = "drop")
ctrl <- cy |> filter(iso3c %in% controls) |> group_by(year, hr) |> summarise(ctrl = mean(dist), .groups = "drop")
gaps <- cy |> filter(iso3c %in% cases$iso3c) |> inner_join(ctrl, by = c("year", "hr")) |>
  mutate(gap = dist - ctrl) |> inner_join(cases, by = "iso3c") |> mutate(e = year - cue)
summ <- gaps |> filter(e >= -6, e <= 6) |> mutate(period = if_else(e < 0, "pre", "post")) |>
  group_by(iso3c, cue, hr, period) |> summarise(gap = mean(gap), dist = mean(dist), .groups = "drop") |>
  tidyr::pivot_wider(names_from = c(hr, period), values_from = c(gap, dist)) |>
  transmute(iso3c, cue,
            HR_dist_pre = dist_TRUE_pre, HR_dist_post = dist_TRUE_post,
            dHR = gap_TRUE_post - gap_TRUE_pre,
            nonHR_dist_pre = dist_FALSE_pre, nonHR_dist_post = dist_FALSE_post,
            dNonHR = gap_FALSE_post - gap_FALSE_pre,
            DDD = dHR - dNonHR) |> arrange(cue)
cat("\nOrdinal vote distance to China (0-2), 6 years pre vs cue..cue+6 (to 2019); d* = change in gap to control mean\n")
print(as.data.frame(mutate(summ, across(where(is.double), ~ round(.x, 3)))))
output_dir <- file.path("data", "processed", "diagnostics", "public_cue_hr_ddd", "descriptive")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(gaps, file.path(output_dir, "hr_gaps_by_year.csv"))
readr::write_csv(summ, file.path(output_dir, "hr_change_global_controls.csv"))
# ---- Howard -> Rudd: votes of session 62 before/after 3 Dec 2007, vs sessions 61 and 63
aus <- d |> filter(year %in% 2006:2008) |> mutate(after = as.integer(format(date, "%m%d")) >= 1203L & as.integer(format(date, "%m")) == 12L)
hw <- aus |> filter(iso3c %in% c("AUS", controls)) |> mutate(grp = if_else(iso3c == "AUS", "AUS", "ctrl")) |>
  group_by(year, after, grp) |> summarise(dist = mean(dist), n_rc = n_distinct(rcid), .groups = "drop") |>
  tidyr::pivot_wider(names_from = grp, values_from = c(dist, n_rc)) |>
  mutate(gap = dist_AUS - dist_ctrl)
cat("\nAustralia: votes on/after 3 Dec vs before, sessions 61-63\n")
print(as.data.frame(mutate(hw, across(where(is.double), ~ round(.x, 3)))))
# ---- Regional controls: same change in gap, against controls of the same World Bank region
reg <- tibble::tibble(iso3c = c(controls, cases$iso3c)) |>
  mutate(region = countrycode::countrycode(iso3c, "iso3c", "region"))
ctrl_reg <- cy |> filter(iso3c %in% controls) |> inner_join(reg, by = "iso3c") |>
  group_by(region, year, hr) |> summarise(ctrl_reg = mean(dist), n_ctrl = n_distinct(iso3c), .groups = "drop")
rs <- cy |> filter(iso3c %in% cases$iso3c) |> inner_join(reg, by = "iso3c") |>
  inner_join(ctrl_reg, by = c("region", "year", "hr")) |> inner_join(cases, by = "iso3c") |>
  mutate(e = year - cue, gap = dist - ctrl_reg) |> filter(e >= -6, e <= 6) |>
  mutate(period = if_else(e < 0, "pre", "post")) |>
  group_by(iso3c, region, hr, period) |> summarise(gap = mean(gap), n_ctrl = max(n_ctrl), .groups = "drop") |>
  tidyr::pivot_wider(names_from = c(hr, period), values_from = gap) |>
  transmute(iso3c, region, n_ctrl, dHR_reg = TRUE_post - TRUE_pre, dNonHR_reg = FALSE_post - FALSE_pre,
            DDD_reg = dHR_reg - dNonHR_reg)
cat("\nAgainst same-region controls\n")
print(as.data.frame(mutate(rs, across(where(is.double), ~ round(.x, 3)))))
readr::write_csv(rs, file.path(output_dir, "hr_change_regional_controls.csv"))
readr::write_csv(hw, file.path(output_dir, "australia_votes_split_3dec.csv"))
cat("\nShare of HR roll calls, 1997-2019:", round(mean(unique(d[c("rcid","hr")])$hr), 3), "\n")
