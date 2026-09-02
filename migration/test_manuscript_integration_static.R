#!/usr/bin/env Rscript

# Cheap tests for the manuscript integration. This script parses the Rmd and
# target graph but does not build targets, estimate models, render the paper, or
# write either production figure.

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(targets)
  library(igraph)
})

source("scripts/functions_manuscript_targets_migration.R")

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("FAILED: ", label, call. = FALSE)
  message("PASS: ", label)
}

expect_error <- function(expression, label) {
  failed <- tryCatch(
    {
      force(expression)
      FALSE
    },
    error = function(error) TRUE
  )
  expect_true(failed, label)
}

file_text <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

invisible(parse(file = "_targets.R"))
invisible(parse(file = "scripts/functions_manuscript_targets_migration.R"))
invisible(parse(
  file = "scripts/diagnostics/plot_brazil_sdid_dose_response_panel.R"
))
invisible(parse(
  file = "scripts/diagnostics/preview_cross_country_dynamic_with_pooled_att.R"
))
message("PASS: all changed R scripts parse")

purl_path <- tempfile("paper-v4-integration-", fileext = ".R")
on.exit(unlink(purl_path, force = TRUE), add = TRUE)
invisible(knitr::purl(
  input = "paper_v4.Rmd",
  output = purl_path,
  documentation = 0L,
  quiet = TRUE
))
invisible(parse(file = purl_path))
message("PASS: all paper_v4.Rmd code chunks parse")

paper <- file_text("paper_v4.Rmd")
targets_script <- file_text("_targets.R")
dose_script <- file_text(
  "scripts/diagnostics/plot_brazil_sdid_dose_response_panel.R"
)
preview_script <- file_text(
  "scripts/diagnostics/preview_cross_country_dynamic_with_pooled_att.R"
)

baseline_leaves <- read.csv(
  "migration/baseline_direct_paper_leaves.csv",
  stringsAsFactors = FALSE,
  check.names = FALSE
)
expect_true(
  nrow(baseline_leaves) == 27L,
  "baseline manifest still identifies exactly 27 direct leaves"
)
legacy_basenames <- basename(baseline_leaves$path)
remaining_legacy <- legacy_basenames[
  vapply(legacy_basenames, grepl, logical(1), x = paper, fixed = TRUE)
]
expect_true(
  length(remaining_legacy) == 0L,
  "paper contains none of the 27 legacy leaf basenames"
)
expect_true(
  !grepl("readr::read_csv", paper, fixed = TRUE),
  "paper no longer reads analytical CSV files directly"
)

sdid_elements <- c(
  "main_summary", "unit_weights", "time_weights", "balance",
  "rank_inference", "placebo_distribution", "donor_sensitivity",
  "window_sensitivity", "donor_china_exposure",
  "donor_china_exposure_summary", "timing_placebos", "latam_core_summary"
)
expect_true(
  grepl(
    "tar_read(brazil_sdid_paper_outputs_candidate)",
    paper,
    fixed = TRUE
  ) && all(vapply(
    paste0("paper_sdid_outputs$", sdid_elements),
    grepl,
    logical(1),
    x = paper,
    fixed = TRUE
  )),
  "paper maps all 12 Brazil SDiD tables from one in-memory target bundle"
)
expect_true(
  grepl(
    "tar_read(brazil_sdid_commodity_table_candidate)",
    paper,
    fixed = TRUE
  ),
  "Table 5 comes from the in-memory commodity target"
)

paper_figure_targets <- c(
  "brazil_sdid_main_fit_figure_candidate",
  "brazil_sdid_weights_figure_candidate",
  "brazil_sdid_latam_fit_figure_candidate",
  "brazil_sdid_dose_response_panel_files_candidate",
  "china_top_m2_goods_full_union_dynamic_pooled_figure_candidate"
)
expect_true(
  all(vapply(paper_figure_targets, grepl, logical(1),
             x = paper, fixed = TRUE)),
  "all five migrated figures are consumed through file targets"
)

ungadm_mappings <- c(
  "ungadm_sdid_outputs$comparison",
  "ungadm_sdid_outputs$placebo_distribution",
  "ungadm_sdid_outputs$rank_inference_harmonized",
  "ungadm_sdid_outputs$unit_weights_bsv_vs_dm",
  "tar_read(ungadm_ife_comparison_candidate)",
  "tar_read(ungadm_ife_fixed_grid_candidate)",
  "tar_read(ungadm_ife_paired_bootstrap_summary_candidate)",
  "tar_read(ungadm_unmapped_rows_candidate)",
  "ungadm_sdid_panel_bundle$missing"
)
expect_true(
  all(vapply(ungadm_mappings, grepl, logical(1),
             x = paper, fixed = TRUE)),
  "paper maps all nine UNGA-DM leaves to target objects"
)

old_cross_country_targets <- c(
  "china_top_m2_goods_status_current_model_results",
  "china_top_m2_goods_status_current_unit_summary",
  "china_top_m2_goods_status_current_country_audit"
)
new_cross_country_targets <- c(
  "china_top_m2_goods_full_union_status_model_results",
  "china_top_m2_goods_full_union_sector_audit",
  "china_top_m2_goods_full_union_status_unit_summary",
  "china_top_m2_goods_full_union_country_audit_candidate",
  "china_top_m2_goods_full_union_dynamic_pooled_figure_candidate"
)
expect_true(
  !any(vapply(old_cross_country_targets, grepl, logical(1),
              x = paper, fixed = TRUE)) &&
    all(vapply(new_cross_country_targets, grepl, logical(1),
               x = paper, fixed = TRUE)),
  "paper consistently promotes the corrected full-union cross-country branch"
)
expect_true(
  grepl("excluded_no_observed_trade_rank", paper, fixed = TRUE),
  "paper audit discloses countries without an observed goods-export rank"
)

target_definitions <- c(
  "brazil_sdid_dose_response_panel_script_candidate",
  "brazil_sdid_dose_response_panel_files_candidate",
  "china_top_m2_goods_full_union_country_audit_candidate",
  "china_top_m2_goods_full_union_dynamic_pooled_figure_candidate"
)
expect_true(
  all(vapply(target_definitions, grepl, logical(1),
             x = targets_script, fixed = TRUE)) &&
    grepl(
      'tar_source("scripts/functions_manuscript_targets_migration.R")',
      targets_script,
      fixed = TRUE
    ),
  "new functions and all four integration targets are declared"
)
expect_true(
  grepl("length(runtime_arguments) == 4L", dose_script, fixed = TRUE) &&
    grepl("donor_path <- runtime_arguments[[1L]]", dose_script, fixed = TRUE) &&
    grepl("summary_path <- runtime_arguments[[2L]]", dose_script, fixed = TRUE) &&
    grepl("output_pdf <- runtime_arguments[[3L]]", dose_script, fixed = TRUE) &&
    grepl("output_png <- runtime_arguments[[4L]]", dose_script, fixed = TRUE),
  "dose-response script accepts explicit target input and output paths"
)
expect_true(
  grepl(
    "china_top_m2_goods_full_union_status_dynamic_results",
    preview_script,
    fixed = TRUE
  ) && grepl(
    "china_top_m2_goods_full_union_status_model_results",
    preview_script,
    fixed = TRUE
  ) && !grepl(
    "china_top_m2_goods_status_current_dynamic_results",
    preview_script,
    fixed = TRUE
  ),
  "manual preview points to the corrected full-union branch"
)

unit_summary <- tibble::tibble(
  min_duration_years = 5L,
  iso3c = c("AAA", "BBB", "CCC", "DDD", "EEE", "FFF"),
  country_name = paste("Country", c("A", "B", "C", "D", "E", "F")),
  trade_rank_years = c(20L, 20L, 0L, 20L, 20L, 20L),
  ever_china_top_observed = c(TRUE, FALSE, FALSE, TRUE, TRUE, TRUE)
)
period_summary <- tibble::tibble(
  min_duration_years = 5L,
  iso3c = c("AAA", "DDD", "EEE", "FFF"),
  period_entry_year = c(2005L, 2005L, 1995L, 2005L),
  duration_years = c(6L, 3L, 6L, 6L),
  prior_china_top_status = c(0L, 0L, 0L, NA_integer_),
  eligible_entry = c(TRUE, TRUE, FALSE, FALSE),
  qualifies_min_duration = c(TRUE, FALSE, FALSE, FALSE)
)
country_audit <- build_full_union_country_audit_candidate(
  unit_summary,
  period_summary
)
expected_roles <- c(
  AAA = "treated_qualifying",
  BBB = "never_china_top_control",
  CCC = "excluded_no_observed_trade_rank",
  DDD = "excluded_short_duration",
  EEE = "excluded_pre_2000",
  FFF = "excluded_no_clean_prior"
)
observed_roles <- stats::setNames(country_audit$audit_role, country_audit$iso3c)
expect_true(
  identical(unname(observed_roles[names(expected_roles)]),
            unname(expected_roles)),
  "full-union audit classifies treatment without using outcome availability"
)
expect_error(
  build_full_union_country_audit_candidate(
    dplyr::bind_rows(unit_summary, unit_summary[1L, ]),
    period_summary
  ),
  "full-union audit rejects duplicated duration-country keys"
)

valid_dynamic <- tibble::tibble(
  min_duration_years = 5L,
  specification = "risk_set_restricted",
  event_time = c(0L, 1L, 2L),
  count = c(5L, 2L, 3L),
  att = c(0, -0.10, -0.20),
  se = c(0.01, 0.02, 0.03),
  ci_lo = c(-0.02, -0.14, -0.26),
  ci_hi = c(0.02, -0.06, -0.14)
)
valid_model <- tibble::tibble(
  min_duration_years = 5L,
  specification = "risk_set_restricted",
  att = -0.16,
  ci_lo = -0.25,
  ci_hi = -0.07,
  n_treated_country_years = 5L
)
expect_error(
  write_cross_country_dynamic_with_pooled_att_candidate(
    dplyr::bind_rows(valid_dynamic, valid_dynamic[2L, ]),
    valid_model,
    tempfile(fileext = ".png")
  ),
  "dynamic figure rejects duplicated event times before writing"
)
wrong_denominator <- valid_model
wrong_denominator$n_treated_country_years <- 6L
expect_error(
  write_cross_country_dynamic_with_pooled_att_candidate(
    valid_dynamic,
    wrong_denominator,
    tempfile(fileext = ".png")
  ),
  "dynamic figure rejects a support/denominator mismatch before writing"
)
wrong_att <- valid_model
wrong_att$att <- -0.15
expect_error(
  write_cross_country_dynamic_with_pooled_att_candidate(
    valid_dynamic,
    wrong_att,
    tempfile(fileext = ".png")
  ),
  "dynamic figure rejects a pooled-ATT mismatch before writing"
)
expect_error(
  run_brazil_sdid_dose_response_panel_candidate(
    "scripts/diagnostics/plot_brazil_sdid_dose_response_panel.R",
    "migration/baseline_direct_paper_leaves.csv",
    "migration/baseline_contract.md",
    tempfile(fileext = ".txt"),
    tempfile(fileext = ".png")
  ),
  "dose-response wrapper rejects invalid output types without running Rscript"
)

static_store <- tempfile("manuscript_integration_targets_static_store_")
on.exit(unlink(static_store, recursive = TRUE, force = TRUE), add = TRUE)
expect_true(
  identical(
    normalizePath(targets::tar_config_get("store"), mustWork = FALSE),
    normalizePath("_targets", mustWork = FALSE)
  ),
  "configured targets store is local to the migration worktree"
)
targets::tar_validate(
  callr_function = NULL,
  script = "_targets.R",
  store = static_store
)
network <- targets::tar_network(
  targets_only = TRUE,
  outdated = FALSE,
  callr_function = NULL,
  script = "_targets.R",
  store = static_store
)
graph <- igraph::graph_from_data_frame(
  network$edges,
  directed = TRUE,
  vertices = data.frame(name = network$vertices$name)
)
expect_true(igraph::is_dag(graph), "target-only graph remains acyclic")

has_path <- function(from, to) {
  length(igraph::shortest_paths(
    graph,
    from = from,
    to = to,
    mode = "out"
  )$vpath[[1L]]) > 0L
}
expect_true(
  has_path(
    "brazil_sdid_dose_response_panel_script_candidate",
    "brazil_sdid_dose_response_panel_files_candidate"
  ) && has_path(
    "brazil_sdid_dose_placebo_donors_file",
    "brazil_sdid_dose_response_panel_files_candidate"
  ) && has_path(
    "brazil_sdid_dose_placebo_summary_file",
    "brazil_sdid_dose_response_panel_files_candidate"
  ),
  "dose-response file target has explicit script, donor, and summary ancestry"
)
expect_true(
  has_path(
    "china_top_m2_goods_full_union_status_validation_gate",
    "china_top_m2_goods_full_union_dynamic_pooled_figure_candidate"
  ) && has_path(
    "china_top_m2_goods_full_union_status_dynamic_results",
    "china_top_m2_goods_full_union_dynamic_pooled_figure_candidate"
  ) && has_path(
    "china_top_m2_goods_full_union_status_model_results",
    "china_top_m2_goods_full_union_dynamic_pooled_figure_candidate"
  ),
  "cross-country figure has validation, dynamic-result, and pooled-result ancestry"
)
expect_true(
  has_path(
    "china_top_m2_goods_full_union_treatment_unit_summary",
    "china_top_m2_goods_full_union_country_audit_candidate"
  ) && has_path(
    "china_top_m2_goods_full_union_status_period_summary",
    "china_top_m2_goods_full_union_country_audit_candidate"
  ),
  "country audit descends only from full-union treatment-period objects"
)

message("ALL_STATIC_MANUSCRIPT_INTEGRATION_TESTS_PASSED")
