#!/usr/bin/env Rscript

# Validate the UNGA-DM ideal-point series (Fjelstul, Hug & Kilby 2026) against
# the BSV Jun/2024 series used as the paper outcome, BEFORE any re-estimation.
# Integrity gates only: country/session mapping, coverage, scale, and the
# correlation of the pipeline outcome (absolute ideal-point distance to China).
# Plan: quality_reports/plans/2026-08-23_ungadm_robustness_check.md (Pacote B).
# This script reads raw files only; it does not touch the targets store.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(janitor)
  library(ggplot2)
})

options(scipen = 999)

run_date <- as.character(Sys.Date())
bsv_path <- file.path(
  "raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv"
)
ungadm_path <- file.path(
  "raw data", "unga_dm", "unga_dm_ideal_points_all_resolution_votes_s75.csv"
)
out_dir <- file.path(
  "data", "processed", "diagnostics", "ungadm_outcome_robustness", "validation"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

input_provenance <- tibble::tibble(
  file = c(bsv_path, ungadm_path),
  sha256 = vapply(
    c(bsv_path, ungadm_path),
    function(f) digest::digest(file = f, algo = "sha256", serialize = FALSE),
    character(1)
  ),
  run_date = run_date
)

# ---------------------------------------------------------------------------
# Load and harmonize. The pipeline outcome uses the posterior median
# (BSV `Q50%All` -> q50_percent_all in get_unga_data()); the UNGA-DM
# counterpart is `X50.`. Merge key is ccode + session (UNGA-DM has no iso3c).
# Year convention mirrors the pipeline: year = session + 1945.
# ---------------------------------------------------------------------------

bsv <- read_csv(bsv_path, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(
    ccode = as.integer(ccode),
    session = as.integer(session),
    iso3c,
    q50_bsv = q50_percent_all,
    n_votes_bsv = n_votes_all
  )

ungadm <- read_csv(ungadm_path, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(
    ccode = as.integer(ccode),
    session = as.integer(session),
    country_ungadm = country,
    q50_dm = x50
  )

stopifnot(!any(duplicated(bsv[, c("ccode", "session")])))
stopifnot(!any(duplicated(ungadm[, c("ccode", "session")])))

session_max_dm <- max(ungadm$session)

# Distances are computed within each source over that source's full country
# set for the session, using that source's own China/US position, exactly
# mirroring get_unga_data().
add_distances <- function(df, q50_col) {
  df %>%
    group_by(session) %>%
    mutate(
      china_ideal = .data[[q50_col]][ccode == 710][1],
      us_ideal = .data[[q50_col]][ccode == 2][1],
      abs_distance_china = abs(.data[[q50_col]] - china_ideal),
      abs_distance_usa = abs(.data[[q50_col]] - us_ideal)
    ) %>%
    ungroup()
}

bsv_d <- add_distances(bsv, "q50_bsv") %>%
  rename(dist_china_bsv = abs_distance_china, dist_usa_bsv = abs_distance_usa) %>%
  select(ccode, session, iso3c, q50_bsv, dist_china_bsv, dist_usa_bsv)
ungadm_d <- add_distances(ungadm, "q50_dm") %>%
  rename(dist_china_dm = abs_distance_china, dist_usa_dm = abs_distance_usa) %>%
  select(ccode, session, country_ungadm, q50_dm, dist_china_dm, dist_usa_dm)

merged <- inner_join(bsv_d, ungadm_d, by = c("ccode", "session")) %>%
  mutate(year = session + 1945L)

# ---------------------------------------------------------------------------
# Coverage: rows in one source and not the other. Sessions beyond the UNGA-DM
# endpoint (76+) are expected to be BSV-only by construction; report them
# separately from within-range gaps, which would indicate mapping problems.
# ---------------------------------------------------------------------------

bsv_only <- anti_join(bsv_d, ungadm_d, by = c("ccode", "session")) %>%
  mutate(
    year = session + 1945L,
    reason = if_else(session > session_max_dm,
                     "beyond UNGA-DM endpoint", "within-range gap")
  )
dm_only <- anti_join(ungadm_d, bsv_d, by = c("ccode", "session")) %>%
  mutate(year = session + 1945L, reason = "missing from BSV")

coverage_summary <- bind_rows(
  bsv_only %>% count(reason, name = "n_country_sessions") %>%
    mutate(source = "BSV only"),
  dm_only %>% count(reason, name = "n_country_sessions") %>%
    mutate(source = "UNGA-DM only")
) %>%
  select(source, reason, n_country_sessions)

within_range_gaps <- bind_rows(
  bsv_only %>% filter(reason == "within-range gap") %>%
    transmute(source = "BSV only", ccode, session, year, label = iso3c),
  dm_only %>%
    transmute(source = "UNGA-DM only", ccode, session, year,
              label = country_ungadm)
) %>%
  arrange(source, session, ccode)

# ---------------------------------------------------------------------------
# Correlations by window. The decisive integrity gate is the correlation of
# abs_distance_china over the SDiD-relevant panel window.
# ---------------------------------------------------------------------------

cor_block <- function(df, label) {
  ok <- stats::complete.cases(df$q50_bsv, df$q50_dm,
                              df$dist_china_bsv, df$dist_china_dm)
  tibble::tibble(
    window = label,
    n_country_sessions = nrow(df),
    n_used_in_correlation = sum(ok),
    cor_q50 = cor(df$q50_bsv, df$q50_dm, use = "complete.obs"),
    cor_dist_china = cor(df$dist_china_bsv, df$dist_china_dm,
                         use = "complete.obs"),
    cor_dist_usa = cor(df$dist_usa_bsv, df$dist_usa_dm, use = "complete.obs")
  )
}

correlations <- bind_rows(
  cor_block(merged, "All merged sessions (1-75)"),
  cor_block(filter(merged, year >= 1946, year <= 1989), "1946-1989"),
  cor_block(filter(merged, year >= 1990), "1990-2020 (panel era)"),
  cor_block(filter(merged, year >= 1997, year <= 2015),
            "1997-2015 (Brazil SDiD window)"),
  cor_block(filter(merged, year >= 1990, year <= 2000), "1990-2000"),
  cor_block(filter(merged, year >= 2001, year <= 2010), "2001-2010"),
  cor_block(filter(merged, year >= 2011), "2011-2020")
)

brazil_series <- merged %>%
  filter(ccode == 140L) %>%
  arrange(session) %>%
  select(session, year, q50_bsv, q50_dm, dist_china_bsv, dist_china_dm,
         dist_usa_bsv, dist_usa_dm)

brazil_window <- brazil_series %>% filter(year >= 1997, year <= 2015)
cor_brazil_dist_sdid_window <- cor(
  brazil_window$dist_china_bsv, brazil_window$dist_china_dm
)

# Mean within-window gap in the Brazil outcome, in outcome units, as a scale
# check that a correlation alone can hide.
brazil_gap_summary <- brazil_window %>%
  summarise(
    mean_dist_bsv = mean(dist_china_bsv),
    mean_dist_dm = mean(dist_china_dm),
    mean_abs_diff = mean(abs(dist_china_bsv - dist_china_dm)),
    max_abs_diff = max(abs(dist_china_bsv - dist_china_dm))
  )

gate_panel <- correlations$cor_dist_china[
  correlations$window == "1997-2015 (Brazil SDiD window)"
]
gates <- tibble::tibble(
  gate = c(
    "cor(abs_distance_china), panel 1997-2015",
    "cor(abs_distance_china), Brazil series 1997-2015",
    "within-range coverage gaps"
  ),
  value = c(
    sprintf("%.4f", gate_panel),
    sprintf("%.4f", cor_brazil_dist_sdid_window),
    as.character(nrow(within_range_gaps))
  ),
  threshold = c(">= 0.95", "report", "inspect if > 0"),
  status = c(
    if_else(gate_panel >= 0.95, "PASS", "CHECK"),
    "reported",
    if_else(nrow(within_range_gaps) == 0, "PASS", "INSPECT")
  )
)

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

write_csv(input_provenance, file.path(out_dir, "input_provenance.csv"))
write_csv(correlations, file.path(out_dir, "correlations.csv"))
write_csv(coverage_summary, file.path(out_dir, "coverage_summary.csv"))
write_csv(within_range_gaps, file.path(out_dir, "within_range_gaps.csv"))
write_csv(brazil_series, file.path(out_dir, "brazil_series_overlay.csv"))
write_csv(brazil_gap_summary, file.path(out_dir, "brazil_gap_summary.csv"))
write_csv(gates, file.path(out_dir, "gates.csv"))

overlay_df <- brazil_series %>%
  select(year, BSV = dist_china_bsv, `UNGA-DM` = dist_china_dm) %>%
  pivot_longer(-year, names_to = "source", values_to = "dist")
p <- ggplot(overlay_df, aes(year, dist, colour = source)) +
  geom_line(linewidth = 0.6) +
  geom_point(size = 1.2) +
  geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey40") +
  annotate("rect", xmin = 1997, xmax = 2015, ymin = -Inf, ymax = Inf,
           alpha = 0.06) +
  labs(
    x = "Year", y = "Absolute ideal-point distance to China",
    colour = NULL,
    title = "Brazil outcome series: BSV Jun/2024 vs UNGA-DM (all votes, -75)",
    subtitle = "Shaded band = 1997-2015 SDiD window; dashed line = 2009 onset"
  ) +
  theme_minimal(base_size = 11)
ggsave(file.path(out_dir, "brazil_series_overlay.png"), p,
       width = 8, height = 4.5, dpi = 200)

cat("\n=== UNGA-DM validation summary (", run_date, ") ===\n", sep = "")
cat("UNGA-DM sessions: 1-", session_max_dm, "; merged country-sessions: ",
    nrow(merged), "\n", sep = "")
print(as.data.frame(correlations), row.names = FALSE)
cat("\nBrazil 1997-2015: cor(dist to China) = ",
    sprintf("%.4f", cor_brazil_dist_sdid_window), "\n", sep = "")
print(as.data.frame(brazil_gap_summary), row.names = FALSE)
cat("\nCoverage:\n")
print(as.data.frame(coverage_summary), row.names = FALSE)
cat("\nGates:\n")
print(as.data.frame(gates), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(out_dir, "session_info.txt"))
cat("\nOutputs in: ", out_dir, "\n", sep = "")

# A validation gate that does not interrupt is not a gate: fail loudly so an
# orchestrator (or a replicator) cannot proceed on a broken mapping.
hard_gates <- gates[gates$threshold != "report", ]
if (any(hard_gates$status != "PASS" & hard_gates$status != "INSPECT")) {
  stop("UNGA-DM validation gates failed; see ",
       file.path(out_dir, "gates.csv"), call. = FALSE)
}
if (any(hard_gates$status == "INSPECT")) {
  message("NOTE: coverage gaps require inspection (see within_range_gaps.csv); ",
          "documented as benign on 2026-08-23.")
}
