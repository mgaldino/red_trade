#!/usr/bin/env Rscript

# Pooled interactive fixed-effects models for the public-cue cases.
#
# Builds the model panels from the stored target `china_top_m2_goods_panel`
# with the sample rules of scripts/diagnostics/estimate_selected_public_cue_sdid_fect.R
# (window 1997-2022; complete outcome/rank panels; clean controls never have China
# as their top goods-export destination; in the switching rule, non-focal
# China-top country-years are masked) and repeats its fect() call unchanged.
#
# Treatment of a focal country starts in its public-cue year, the publication
# year of the first counted source with explicit rank language. It stays on while
# China is the top goods-export destination, and also covers post-cue years before
# China first reaches that position (Australia, 2007-2008).
#
# Specifications:
#   gate_4case          AUS 2007, BRA 2009, CHL 2008, URY 2013; must reproduce
#                       data/processed/diagnostics/public_cue_pooled_ife_aus2007/
#                       fect_results_aus2007.csv before anything else is used.
#   four_case_chl2009   AUS 2007, BRA 2009, CHL 2009, URY 2013.
#   seven_case          four_case_chl2009 plus KOR 2003, ZAF 2010, NZL 2013.
#
# South Africa's first counted cue is dated 11 December 2009, after most of that
# session's votes, so its treatment starts in 2010.
#
# Countries with a documented public cue that are not treated in a specification
# are dropped from it rather than used as controls, as in the original script
# (Gabon and Qatar in every specification; Ukraine in the seven-case one).
#
# Outside the targets graph; listed for migration in TARGETS_MIGRATION.md.
# Run as the original models were run (fect 2.4.5, outside renv):
#   Rscript --vanilla scripts/diagnostics/estimate_public_cue_pooled_ife.R

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

output_dir <- file.path(
  "data", "processed", "diagnostics", "public_cue_pooled_ife"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

specs <- list(
  gate_4case = tibble::tribble(
    ~iso3c, ~public_cue_year,
    "AUS", 2007L, "BRA", 2009L, "CHL", 2008L, "URY", 2013L
  ),
  four_case_chl2009 = tibble::tribble(
    ~iso3c, ~public_cue_year,
    "AUS", 2007L, "BRA", 2009L, "CHL", 2009L, "URY", 2013L
  ),
  seven_case = tibble::tribble(
    ~iso3c, ~public_cue_year,
    "AUS", 2007L, "BRA", 2009L, "CHL", 2009L, "URY", 2013L,
    "KOR", 2003L, "ZAF", 2010L, "NZL", 2013L
  )
)
dropped_cue_cases <- list(
  gate_4case = c("GAB", "QAT"),
  four_case_chl2009 = c("GAB", "QAT"),
  seven_case = c("GAB", "QAT", "UKR")
)

panel <- targets::tar_read(china_top_m2_goods_panel) |>
  dplyr::filter(year >= year_start, year <= year_end) |>
  dplyr::select(iso3c, country_name, year, abs_distance_china, china_is_top) |>
  dplyr::mutate(
    year = as.integer(year),
    iso3c = as.character(iso3c),
    abs_distance_china = as.numeric(abs_distance_china),
    china_is_top = as.logical(china_is_top)
  ) |>
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

build_panel <- function(focal_cues, rule, dropped) {
  stopifnot(all(focal_cues$iso3c %in% complete_units))
  base <- if (rule == "clean_controls") {
    dplyr::filter(panel, iso3c %in% c(clean_donors, focal_cues$iso3c))
  } else {
    dplyr::filter(panel, iso3c %in% complete_units, !iso3c %in% dropped)
  }
  base |>
    dplyr::left_join(focal_cues, by = "iso3c") |>
    dplyr::left_join(
      dplyr::select(unit_audit, iso3c, goods_entry_year), by = "iso3c"
    ) |>
    dplyr::mutate(
      focal_country = !is.na(public_cue_year),
      treatment = as.integer(
        focal_country & year >= public_cue_year &
          (china_is_top %in% TRUE | year < goods_entry_year)
      ),
      model_outcome = if (rule == "clean_controls") {
        abs_distance_china
      } else {
        dplyr::if_else(
          !focal_country & china_is_top %in% TRUE, NA_real_, abs_distance_china
        )
      },
      country_id = as.integer(factor(iso3c))
    ) |>
    dplyr::arrange(country_id, year)
}

extract_selected_factors <- function(fit) {
  if (!is.null(fit$r.cv) && "r" %in% names(fit$r.cv)) {
    as.integer(fit$r.cv[["r"]])
  } else {
    NA_integer_
  }
}

run_fect <- function(panel_data, spec_id, rule) {
  message("Estimating `", spec_id, "` / `", rule, "`.")
  set.seed(42L)
  timing <- system.time({
    fit <- fect::fect(
      model_outcome ~ treatment,
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
  })
  overall_se <- stats::sd(as.numeric(fit$att.avg.boot), na.rm = TRUE)
  overall_z <- as.numeric(fit$att.avg) / overall_se
  list(
    fit = fit,
    result = tibble::tibble(
      spec_id = spec_id,
      comparison_rule = rule,
      focal_cases = paste(
        sort(unique(panel_data$iso3c[panel_data$focal_country])), collapse = ";"
      ),
      estimate = as.numeric(fit$att.avg),
      se_bootstrap = overall_se,
      ci_95_low = as.numeric(fit$att.avg) - stats::qnorm(0.975) * overall_se,
      ci_95_high = as.numeric(fit$att.avg) + stats::qnorm(0.975) * overall_se,
      p_normal_two_sided = 2 * stats::pnorm(-abs(overall_z)),
      selected_factors = extract_selected_factors(fit),
      n_treated_units = as.integer(fit$Ntr),
      n_never_treated_units = as.integer(fit$Nco),
      n_treated_country_years = sum(panel_data$treatment == 1L &
                                      panel_data$country_id %in% fit$id),
      bootstrap_replications = fect_bootstraps,
      bootstrap_seed = 42L,
      elapsed_seconds = as.numeric(timing[["elapsed"]]),
      fect_version = as.character(utils::packageVersion("fect"))
    )
  )
}

country_att <- function(fit, panel_data, spec_id, rule) {
  # Average treated-period effect by focal country, from fect's individual
  # treatment effects (observed minus counterfactual).
  if (is.null(fit$eff) || is.null(fit$D.dat)) return(NULL)
  ids <- panel_data |>
    dplyr::distinct(country_id, iso3c)
  label <- function(m) {
    dimnames(m) <- list(as.character(fit$rawtime), as.character(fit$id))
    m
  }
  eff <- as.data.frame(as.table(label(fit$eff))) |>
    stats::setNames(c("time", "unit", "eff"))
  d <- as.data.frame(as.table(label(fit$D.dat))) |>
    stats::setNames(c("time", "unit", "D"))
  dplyr::inner_join(eff, d, by = c("time", "unit")) |>
    dplyr::filter(D == 1) |>
    dplyr::mutate(country_id = as.integer(as.character(unit))) |>
    dplyr::left_join(ids, by = "country_id") |>
    dplyr::group_by(iso3c) |>
    dplyr::summarise(att_country = mean(eff), n_treated_years = dplyr::n(),
                     .groups = "drop") |>
    dplyr::mutate(spec_id = spec_id, comparison_rule = rule, .before = 1L)
}

rules <- c("clean_controls", "full_switching")
results <- list()
country_effects <- list()

# Gate first: stop before any new specification if the rebuild does not match.
reference <- readr::read_csv(
  file.path("data", "processed", "diagnostics", "public_cue_pooled_ife_aus2007",
            "fect_results_aus2007.csv"),
  show_col_types = FALSE
) |>
  dplyr::filter(grepl("without_gab_qat", model_id)) |>
  dplyr::mutate(comparison_rule = sub("_without_gab_qat", "", model_id)) |>
  dplyr::select(comparison_rule, ref_estimate = estimate, ref_se = se_bootstrap)

for (spec_id in names(specs)) {
  for (rule in rules) {
    panel_data <- build_panel(specs[[spec_id]], rule, dropped_cue_cases[[spec_id]])
    run <- run_fect(panel_data, spec_id, rule)
    results[[paste(spec_id, rule)]] <- run$result
    country_effects[[paste(spec_id, rule)]] <-
      country_att(run$fit, panel_data, spec_id, rule)
  }
  if (spec_id == "gate_4case") {
    gate <- dplyr::bind_rows(results) |>
      dplyr::left_join(reference, by = "comparison_rule") |>
      dplyr::mutate(diff_estimate = abs(estimate - ref_estimate),
                    diff_se = abs(se_bootstrap - ref_se))
    readr::write_csv(gate, file.path(output_dir, "gate_reproduction.csv"))
    print(as.data.frame(dplyr::select(gate, comparison_rule, estimate,
                                      ref_estimate, diff_estimate, diff_se)))
    stopifnot(all(gate$diff_estimate < 1e-8), all(gate$diff_se < 1e-8))
  }
}

results <- dplyr::bind_rows(results)
country_effects <- dplyr::bind_rows(country_effects)
readr::write_csv(results, file.path(output_dir, "fect_results.csv"))
readr::write_csv(country_effects, file.path(output_dir, "fect_country_effects.csv"))
writeLines(capture.output(sessionInfo()), file.path(output_dir, "session_info.txt"))

print(as.data.frame(dplyr::select(
  results, spec_id, comparison_rule, estimate, se_bootstrap,
  p_normal_two_sided, selected_factors, n_treated_units, n_never_treated_units
)))
print(as.data.frame(country_effects))
