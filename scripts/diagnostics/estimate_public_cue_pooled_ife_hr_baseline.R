#!/usr/bin/env Rscript

# Pooled IFE for the public-cue cases with a baseline human-rights alignment
# covariate interacted with year (exploratory).
#
# Covariate Z_i: share of human-rights roll calls in the 1994-1996 UNGA sessions
# (sessions 49-51, before the 1997 start of the window and before every cue) on
# which country i cast the same vote as China (yes, no or abstain; roll calls
# where either did not vote are left out). Source: unvotes 0.3.0 tarball.
# Z_i is fixed in time, so the unit fixed effect absorbs it; it enters as
# Z_i x 1[year = s] for every year except 1997, which lets the year shocks differ
# with baseline alignment (Z_i gamma_t). fect's Z/gamma arguments exist only for
# method "cfe"; the explicit regressors keep the IFE estimator and the
# cross-validation of the number of factors used in estimate_public_cue_pooled_ife.R.
#
# Specifications (cue years as in estimate_public_cue_pooled_ife.R, Chile 2007):
#   four_case_chl2007  AUS 2007, BRA 2009, CHL 2007, URY 2013.
#   seven_case         plus KOR 2003, ZAF 2010, NZL 2013.
# Each is run with and without the covariate on the same sample (units with Z),
# under both comparison rules (clean controls; full switching).
#
# Gate: without the covariate and on the full sample, the code reproduces the
# stored seven-case and four-case estimates in public_cue_pooled_ife/fect_results.csv.
#
# Outside the targets graph; listed in TARGETS_MIGRATION.md.
#   Rscript --vanilla scripts/diagnostics/estimate_public_cue_pooled_ife_hr_baseline.R

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
})

year_start <- 1997L
year_end <- 2022L
expected_years <- seq.int(year_start, year_end)
expected_n_years <- length(expected_years)
fect_bootstraps <- 1000L
baseline_sessions <- 49:51

output_dir <- file.path("data", "processed", "diagnostics", "public_cue_pooled_ife", "hr_baseline")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

specs <- list(
  four_case_chl2007 = tibble::tribble(
    ~iso3c, ~public_cue_year,
    "AUS", 2007L, "BRA", 2009L, "CHL", 2007L, "URY", 2013L
  ),
  seven_case = tibble::tribble(
    ~iso3c, ~public_cue_year,
    "AUS", 2007L, "BRA", 2009L, "CHL", 2007L, "URY", 2013L,
    "KOR", 2003L, "ZAF", 2010L, "NZL", 2013L
  )
)
dropped_cue_cases <- list(
  four_case_chl2007 = c("GAB", "QAT"),
  seven_case = c("GAB", "QAT", "UKR")
)

# ---- Baseline human-rights alignment ---------------------------------------
tmp_dir <- tempfile("unvotes_")
dir.create(tmp_dir)
utils::untar(tar_read(unvotes_tarball), exdir = tmp_dir, tar = "internal")
load_unvotes <- function(name) {
  env <- new.env(parent = emptyenv())
  load(file.path(tmp_dir, "unvotes", "data", paste0(name, ".rda")), envir = env)
  env[[name]]
}
roll_calls <- load_unvotes("un_roll_calls")
hr_rcid <- load_unvotes("un_roll_call_issues") |>
  dplyr::filter(as.character(issue) == "Human rights") |>
  dplyr::distinct(rcid) |>
  dplyr::pull(rcid)
baseline_rcid <- roll_calls$rcid[roll_calls$session %in% baseline_sessions &
                                   roll_calls$rcid %in% hr_rcid]
votes <- load_unvotes("un_votes") |>
  dplyr::filter(rcid %in% baseline_rcid, as.character(vote) %in% c("yes", "no", "abstain")) |>
  dplyr::mutate(vote = as.character(vote),
                iso3c = countrycode::countrycode(country_code, "iso2c", "iso3c", warn = FALSE)) |>
  dplyr::select(rcid, iso3c, vote)
unlink(tmp_dir, recursive = TRUE)
china <- dplyr::filter(votes, iso3c == "CHN") |> dplyr::select(rcid, china_vote = vote)
hr_baseline <- votes |>
  dplyr::filter(iso3c != "CHN", !is.na(iso3c)) |>
  dplyr::inner_join(china, by = "rcid") |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(hr_agree_china_1994_96 = mean(vote == china_vote),
                   n_hr_votes_1994_96 = dplyr::n(), .groups = "drop")
message(length(baseline_rcid), " human-rights roll calls in sessions ",
        min(baseline_sessions), "-", max(baseline_sessions), ".")

# ---- Panel (as in estimate_public_cue_pooled_ife.R) --------------------------
panel <- tar_read(china_top_m2_goods_panel) |>
  dplyr::filter(year >= year_start, year <= year_end) |>
  dplyr::select(iso3c, country_name, year, abs_distance_china, china_is_top) |>
  dplyr::mutate(year = as.integer(year), iso3c = as.character(iso3c),
                abs_distance_china = as.numeric(abs_distance_china),
                china_is_top = as.logical(china_is_top)) |>
  dplyr::arrange(iso3c, year)

unit_audit <- panel |>
  dplyr::group_by(iso3c) |>
  dplyr::summarise(
    complete_common_panel = dplyr::n_distinct(year) == expected_n_years &
      setequal(year, expected_years) &
      all(!is.na(abs_distance_china)) & all(!is.na(china_is_top)),
    ever_china_top = any(china_is_top %in% TRUE),
    goods_entry_year = if (any(china_is_top %in% TRUE & year >= 2000L)) {
      min(year[china_is_top %in% TRUE & year >= 2000L])
    } else {
      NA_integer_
    },
    .groups = "drop"
  )
complete_units <- sort(unit_audit$iso3c[unit_audit$complete_common_panel])
clean_donors <- sort(
  unit_audit$iso3c[unit_audit$complete_common_panel & !unit_audit$ever_china_top]
)
units_without_z <- setdiff(complete_units, hr_baseline$iso3c)
message("Complete units without baseline votes: ",
        if (length(units_without_z)) paste(units_without_z, collapse = ", ") else "none", ".")

z_years <- setdiff(expected_years, year_start)
z_terms <- paste0("z_", z_years)

build_panel <- function(focal_cues, rule, dropped, keep_units) {
  base <- if (rule == "clean_controls") {
    dplyr::filter(panel, iso3c %in% c(clean_donors, focal_cues$iso3c))
  } else {
    dplyr::filter(panel, iso3c %in% complete_units, !iso3c %in% dropped)
  }
  out <- base |>
    dplyr::filter(iso3c %in% keep_units) |>
    dplyr::left_join(focal_cues, by = "iso3c") |>
    dplyr::left_join(dplyr::select(unit_audit, iso3c, goods_entry_year), by = "iso3c") |>
    dplyr::left_join(dplyr::select(hr_baseline, iso3c, hr_agree_china_1994_96), by = "iso3c") |>
    dplyr::mutate(
      focal_country = !is.na(public_cue_year),
      treatment = as.integer(
        focal_country & year >= public_cue_year &
          (china_is_top %in% TRUE | year < goods_entry_year)
      ),
      model_outcome = if (rule == "clean_controls") {
        abs_distance_china
      } else {
        dplyr::if_else(!focal_country & china_is_top %in% TRUE, NA_real_, abs_distance_china)
      },
      country_id = as.integer(factor(iso3c))
    ) |>
    dplyr::arrange(country_id, year)
  for (k in seq_along(z_years)) {
    out[[z_terms[k]]] <- out$hr_agree_china_1994_96 * as.numeric(out$year == z_years[k])
  }
  out
}

run_fect <- function(panel_data, spec_id, rule, sample_id, covariate) {
  rhs <- if (covariate) paste(c("treatment", z_terms), collapse = " + ") else "treatment"
  message("Estimating `", spec_id, "` / `", rule, "` / ", sample_id,
          if (covariate) " / with Z x year" else " / no covariate", ".")
  set.seed(42L)
  fit <- fect::fect(
    stats::as.formula(paste("model_outcome ~", rhs)),
    data = as.data.frame(panel_data),
    index = c("country_id", "year"),
    method = "ife",
    force = "two-way",
    na.rm = FALSE,
    em = TRUE,
    se = TRUE,
    nboots = fect_bootstraps,
    parallel = FALSE,
    CV = TRUE,
    r = c(0, 3),
    min.T0 = 1L,
    max.missing = expected_n_years,
    seed = 42L
  )
  overall_se <- stats::sd(as.numeric(fit$att.avg.boot), na.rm = TRUE)
  ids <- dplyr::distinct(panel_data, country_id, iso3c)
  label <- function(m) {
    dimnames(m) <- list(as.character(fit$rawtime), as.character(fit$id))
    m
  }
  eff <- as.data.frame(as.table(label(fit$eff))) |> stats::setNames(c("time", "unit", "eff"))
  d <- as.data.frame(as.table(label(fit$D.dat))) |> stats::setNames(c("time", "unit", "D"))
  country <- dplyr::inner_join(eff, d, by = c("time", "unit")) |>
    dplyr::filter(D == 1) |>
    dplyr::mutate(country_id = as.integer(as.character(unit))) |>
    dplyr::left_join(ids, by = "country_id") |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(att_country = mean(eff), n_treated_years = dplyr::n(), .groups = "drop") |>
    dplyr::mutate(spec_id = spec_id, comparison_rule = rule, sample_id = sample_id,
                  covariate = covariate, .before = 1L)
  list(
    result = tibble::tibble(
      spec_id = spec_id, comparison_rule = rule, sample_id = sample_id, covariate = covariate,
      estimate = as.numeric(fit$att.avg), se_bootstrap = overall_se,
      ci_95_low = as.numeric(fit$att.avg) - stats::qnorm(0.975) * overall_se,
      ci_95_high = as.numeric(fit$att.avg) + stats::qnorm(0.975) * overall_se,
      p_normal_two_sided = 2 * stats::pnorm(-abs(as.numeric(fit$att.avg) / overall_se)),
      selected_factors = if (!is.null(fit$r.cv)) as.integer(fit$r.cv) else NA_integer_,
      n_units = dplyr::n_distinct(panel_data$iso3c),
      n_treated_units = as.integer(fit$Ntr), n_never_treated_units = as.integer(fit$Nco),
      bootstrap_replications = fect_bootstraps, bootstrap_seed = 42L,
      fect_version = as.character(utils::packageVersion("fect"))
    ),
    country = country
  )
}

# ---- Gate ------------------------------------------------------------------
stored <- readr::read_csv(file.path("data", "processed", "diagnostics", "public_cue_pooled_ife",
                                    "fect_results.csv"), show_col_types = FALSE) |>
  dplyr::filter(spec_id %in% names(specs), comparison_rule == "clean_controls") |>
  dplyr::select(spec_id, stored_estimate = estimate, stored_se = se_bootstrap)
gate <- dplyr::bind_rows(lapply(names(specs), function(s) {
  pd <- build_panel(specs[[s]], "clean_controls", dropped_cue_cases[[s]], complete_units)
  run_fect(pd, s, "clean_controls", "full", FALSE)$result
})) |>
  dplyr::left_join(stored, by = "spec_id") |>
  dplyr::mutate(diff_estimate = abs(estimate - stored_estimate), diff_se = abs(se_bootstrap - stored_se))
print(as.data.frame(dplyr::select(gate, spec_id, estimate, stored_estimate, diff_estimate, diff_se)))
readr::write_csv(gate, file.path(output_dir, "gate_reproduction.csv"))
stopifnot(all(gate$diff_estimate < 1e-8), all(gate$diff_se < 1e-8))

# ---- Estimates -------------------------------------------------------------
z_units <- intersect(complete_units, hr_baseline$iso3c)
runs <- list()
for (s in names(specs)) {
  stopifnot(all(specs[[s]]$iso3c %in% z_units))
  for (rule in c("clean_controls", "full_switching")) {
    pd <- build_panel(specs[[s]], rule, dropped_cue_cases[[s]], z_units)
    stopifnot(!anyNA(pd$hr_agree_china_1994_96))
    for (cov in c(FALSE, TRUE)) {
      runs[[paste(s, rule, cov)]] <- run_fect(pd, s, rule, "units_with_z", cov)
    }
  }
}
results <- dplyr::bind_rows(lapply(runs, `[[`, "result"))
country <- dplyr::bind_rows(lapply(runs, `[[`, "country")) |>
  dplyr::left_join(dplyr::select(hr_baseline, iso3c, hr_agree_china_1994_96), by = "iso3c")

readr::write_csv(hr_baseline, file.path(output_dir, "hr_agree_china_1994_96.csv"))
readr::write_csv(results, file.path(output_dir, "fect_results.csv"))
readr::write_csv(country, file.path(output_dir, "fect_country_effects.csv"))
writeLines(capture.output(sessionInfo()), file.path(output_dir, "session_info.txt"))

print(as.data.frame(dplyr::select(results, spec_id, comparison_rule, covariate, estimate,
                                  se_bootstrap, p_normal_two_sided, selected_factors,
                                  n_units, n_treated_units)))
print(as.data.frame(dplyr::filter(country, spec_id == "seven_case")))
