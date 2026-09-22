#!/usr/bin/env Rscript

# Complete the Australia 2007 single-treated SDiD diagnostic with the same
# placebo inference used by `estimate_selected_public_cue_sdid_fect.R`.
#
# This script deliberately stays outside the targets pipeline. It only reads
# the stored `china_top_m2_goods_panel` target and writes Australia-2007-
# specific diagnostic artifacts. It never calls tar_make() or writes to
# `_targets/`.

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(targets)
  library(tibble)
})

required_packages <- c("digest", "jsonlite", "synthdid")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    "Missing required package(s): ", paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()

read_env_int <- function(name, default, minimum = 1L) {
  raw <- Sys.getenv(name, unset = as.character(default))
  value <- suppressWarnings(as.integer(raw))
  if (length(value) != 1L || is.na(value) || value < minimum) {
    stop(
      name, " must be one integer >= ", minimum, "; received `", raw, "`.",
      call. = FALSE
    )
  }
  value
}

started_at <- Sys.time()
year_start <- 1997L
year_end <- 2022L
treatment_year <- 2007L
treated_iso3c <- "AUS"
placebo_replications <- 5000L
placebo_seed <- SDID_PLACEBO_SEED
parallel_cores <- read_env_int(
  "AUSTRALIA_SDID_2007_CORES",
  sdid_available_cores(cap = 8L)
)

target_store <- "_targets"
input_target <- "china_top_m2_goods_panel"
output_dir <- file.path(
  "data", "processed", "diagnostics", "selected_public_cue_sdid_fect"
)
checkpoint_dir <- file.path(output_dir, "checkpoints")
fit_dir <- file.path(output_dir, "fits")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)

checkpoint_path <- file.path(
  checkpoint_dir,
  "placebo_se_aus_cue_2007_5000.rds"
)
fit_path <- file.path(fit_dir, "sdid_aus_cue_2007.rds")
point_reference_path <- file.path(output_dir, "australia_sdid_2007_point.csv")
point_fit_reference_path <- file.path(
  output_dir, "australia_sdid_2007_point_fit.rds"
)

message(
  "Reading stored target `", input_target,
  "` without executing the targets pipeline."
)
panel_raw <- targets::tar_read_raw(input_target, store = target_store)

required_cols <- c(
  "iso3c", "country_name", "year", "abs_distance_china", "china_is_top"
)
missing_cols <- setdiff(required_cols, names(panel_raw))
if (length(missing_cols) > 0L) {
  stop(
    "Stored target is missing required column(s): ",
    paste(missing_cols, collapse = ", "),
    call. = FALSE
  )
}

expected_years <- seq.int(year_start, year_end)
expected_n_years <- length(expected_years)
panel <- panel_raw |>
  dplyr::filter(year >= year_start, year <= year_end) |>
  dplyr::select(dplyr::all_of(required_cols)) |>
  dplyr::mutate(
    iso3c = as.character(iso3c),
    country_name = as.character(country_name),
    year = as.integer(year),
    abs_distance_china = as.numeric(abs_distance_china),
    china_is_top = as.logical(china_is_top)
  ) |>
  dplyr::arrange(iso3c, year)

duplicate_keys <- panel |>
  dplyr::count(iso3c, year, name = "n") |>
  dplyr::filter(n != 1L)
if (nrow(duplicate_keys) > 0L) {
  stop("Duplicate country-year keys in the stored panel.", call. = FALSE)
}

unit_audit <- panel |>
  dplyr::group_by(iso3c, country_name) |>
  dplyr::summarise(
    n_years = dplyr::n_distinct(year),
    first_year = min(year),
    last_year = max(year),
    exact_common_grid = setequal(year, expected_years),
    outcome_complete = all(!is.na(abs_distance_china)),
    rank_complete = all(!is.na(china_is_top)),
    ever_china_top = any(china_is_top %in% TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    complete_common_panel =
      n_years == expected_n_years & exact_common_grid &
      outcome_complete & rank_complete
  )

clean_donors <- unit_audit |>
  dplyr::filter(complete_common_panel, !ever_china_top) |>
  dplyr::pull(iso3c) |>
  sort()
if (length(clean_donors) != 105L) {
  stop(
    "The clean donor count differs from the frozen design: ",
    length(clean_donors), " instead of 105.",
    call. = FALSE
  )
}

australia_audit <- unit_audit |>
  dplyr::filter(iso3c == treated_iso3c)
if (nrow(australia_audit) != 1L ||
    !isTRUE(australia_audit$complete_common_panel[[1L]])) {
  stop("Australia does not have the required complete panel.", call. = FALSE)
}

sample_membership <- unit_audit |>
  dplyr::mutate(
    fit_id = "aus_cue_2007",
    fit_role = dplyr::case_when(
      iso3c == treated_iso3c ~ "treated",
      iso3c %in% clean_donors ~ "included_donor",
      complete_common_panel & ever_china_top ~
        "excluded_ever_china_top_in_window",
      TRUE ~ "excluded_incomplete_common_panel"
    )
  ) |>
  dplyr::select(
    fit_id, iso3c, country_name, fit_role, n_years, first_year, last_year,
    exact_common_grid, outcome_complete, rank_complete, ever_china_top,
    complete_common_panel
  ) |>
  dplyr::arrange(fit_role, iso3c)

unit_levels <- c(clean_donors, treated_iso3c)
fit_data <- panel |>
  dplyr::filter(iso3c %in% unit_levels) |>
  dplyr::mutate(.unit_treated = as.integer(iso3c == treated_iso3c)) |>
  dplyr::arrange(.unit_treated, iso3c, year) |>
  dplyr::transmute(
    iso3c = factor(iso3c, levels = unit_levels),
    year,
    Y = abs_distance_china,
    treatment = as.integer(
      iso3c == treated_iso3c & year >= treatment_year
    )
  ) |>
  as.data.frame()

setup <- synthdid::panel.matrices(fit_data)
expected_t0 <- treatment_year - year_start
if (setup$N0 != length(clean_donors) || setup$T0 != expected_t0) {
  stop(
    "Unexpected SDiD dimensions: N0 = ", setup$N0,
    ", T0 = ", setup$T0, ".",
    call. = FALSE
  )
}

fit <- synthdid::synthdid_estimate(
  Y = setup$Y,
  N0 = setup$N0,
  T0 = setup$T0
)

if (!file.exists(point_reference_path) ||
    !file.exists(point_fit_reference_path)) {
  stop("The frozen Australia-2007 point-estimate references are missing.",
       call. = FALSE)
}
point_reference <- readr::read_csv(
  point_reference_path,
  show_col_types = FALSE
)
point_fit_reference <- readRDS(point_fit_reference_path)
if (nrow(point_reference) != 1L ||
    !isTRUE(all.equal(
      as.numeric(fit),
      point_reference$estimate[[1L]],
      tolerance = 1e-12,
      check.attributes = FALSE
    )) ||
    !isTRUE(all.equal(
      as.numeric(fit),
      as.numeric(point_fit_reference),
      tolerance = 1e-12,
      check.attributes = FALSE
    ))) {
  stop("The recomputed ATT does not match the frozen point estimate.",
       call. = FALSE)
}

message(
  "AUS-2007 ATT = ", sprintf("%.9f", as.numeric(fit)),
  "; computing ", placebo_replications,
  " placebo re-estimations with seed ", placebo_seed, "."
)
se_placebo <- as.numeric(sdid_placebo_se(
  fit,
  replications = placebo_replications,
  seed = placebo_seed,
  cores = parallel_cores,
  checkpoint_dir = checkpoint_dir,
  label = "aus_cue_2007"
))

if (!file.exists(checkpoint_path)) {
  stop("The placebo checkpoint was not created.", call. = FALSE)
}
checkpoint <- readRDS(checkpoint_path)
checkpoint_se <- sqrt(
  (placebo_replications - 1) / placebo_replications
) * stats::sd(checkpoint$estimates)
if (!identical(checkpoint$replications, placebo_replications) ||
    !identical(checkpoint$seed, placebo_seed) ||
    length(checkpoint$estimates) != placebo_replications ||
    any(!is.finite(checkpoint$estimates)) ||
    !isTRUE(all.equal(
      checkpoint_se,
      se_placebo,
      tolerance = 1e-12,
      check.attributes = FALSE
    ))) {
  stop("The completed placebo checkpoint failed validation.", call. = FALSE)
}

fit_setup <- attr(fit, "setup")
fit_weights <- attr(fit, "weights")
outcome_matrix <- fit_setup$Y
donor_outcomes <- outcome_matrix[seq_len(fit_setup$N0), , drop = FALSE]
treated_outcome <- as.numeric(outcome_matrix[fit_setup$N0 + 1L, ])
synthetic_outcome <- as.numeric(
  t(as.numeric(fit_weights$omega)) %*% donor_outcomes
)
raw_gap <- treated_outcome - synthetic_outcome
pre_idx <- seq_len(fit_setup$T0)
post_idx <- seq.int(fit_setup$T0 + 1L, ncol(outcome_matrix))
pre_gap_weighted <- sum(as.numeric(fit_weights$lambda) * raw_gap[pre_idx])
adjusted_synthetic <- synthetic_outcome + pre_gap_weighted
adjusted_gap <- treated_outcome - adjusted_synthetic
att_from_path <- mean(adjusted_gap[post_idx])
if (!isTRUE(all.equal(
  att_from_path,
  as.numeric(fit),
  tolerance = 1e-8,
  check.attributes = FALSE
))) {
  stop("The SDiD path decomposition failed.", call. = FALSE)
}

estimate <- as.numeric(fit)
z_value <- estimate / se_placebo
result <- tibble::tibble(
  fit_id = "aus_cue_2007",
  iso3c = treated_iso3c,
  country_name = "Australia",
  treatment_year = treatment_year,
  timing_definition = paste0(
    "imposed timing corresponding to the 2006-07 fiscal-year ",
    "aggregate-trade rank change"
  ),
  outcome = "Absolute UNGA ideal-point distance to China",
  treatment = "Absorbing post-timing indicator for the focal SDiD fit",
  donor_rule = paste0(
    "Complete ", year_start, "-", year_end,
    " panel; China never top goods-export destination in that window"
  ),
  estimate = estimate,
  se_placebo = se_placebo,
  ci_95_low = estimate - stats::qnorm(0.975) * se_placebo,
  ci_95_high = estimate + stats::qnorm(0.975) * se_placebo,
  z_value = z_value,
  p_normal_two_sided = 2 * stats::pnorm(-abs(z_value)),
  rmspe_pre_level_adjusted = sqrt(mean(adjusted_gap[pre_idx]^2)),
  rmspe_post_level_adjusted = sqrt(mean(adjusted_gap[post_idx]^2)),
  rmspe_ratio = rmspe_post_level_adjusted / rmspe_pre_level_adjusted,
  n_donors = fit_setup$N0,
  n_treated = nrow(fit_setup$Y) - fit_setup$N0,
  n_pre_years = fit_setup$T0,
  n_post_years = ncol(fit_setup$Y) - fit_setup$T0,
  year_start = year_start,
  year_end = year_end,
  placebo_replications = placebo_replications,
  placebo_seed = placebo_seed,
  synthdid_version = as.character(utils::packageVersion("synthdid"))
)

unit_weights <- tibble::tibble(
  fit_id = "aus_cue_2007",
  donor_iso3c = rownames(fit_setup$Y)[seq_len(fit_setup$N0)],
  unit_weight = as.numeric(fit_weights$omega)
) |>
  dplyr::arrange(dplyr::desc(unit_weight), donor_iso3c) |>
  dplyr::mutate(
    weight_rank = dplyr::row_number(),
    cumulative_weight = cumsum(unit_weight),
    effective_donor_count = 1 / sum(unit_weight^2)
  )

time_weights <- tibble::tibble(
  fit_id = "aus_cue_2007",
  year = as.integer(colnames(fit_setup$Y)[pre_idx]),
  time_weight = as.numeric(fit_weights$lambda)
) |>
  dplyr::arrange(year)

path <- tibble::tibble(
  fit_id = "aus_cue_2007",
  iso3c = treated_iso3c,
  treatment_year = treatment_year,
  year = as.integer(colnames(fit_setup$Y)),
  post_treatment = year >= treatment_year,
  observed_outcome = treated_outcome,
  synthetic_outcome = synthetic_outcome,
  level_adjusted_synthetic_outcome = adjusted_synthetic,
  raw_gap = raw_gap,
  level_adjusted_gap = adjusted_gap
)

target_meta <- targets::tar_meta(
  fields = c(name, data, command, time),
  store = target_store
) |>
  dplyr::filter(name == input_target) |>
  dplyr::mutate(time = as.character(time))

output_paths <- c(
  results = file.path(output_dir, "australia_sdid_2007_results.csv"),
  sample_membership = file.path(
    output_dir, "australia_sdid_2007_sample_membership.csv"
  ),
  unit_weights = file.path(
    output_dir, "australia_sdid_2007_unit_weights.csv"
  ),
  time_weights = file.path(
    output_dir, "australia_sdid_2007_time_weights.csv"
  ),
  path = file.path(output_dir, "australia_sdid_2007_path.csv"),
  validation = file.path(
    output_dir, "australia_sdid_2007_validation_checks.csv"
  ),
  input_metadata = file.path(
    output_dir, "australia_sdid_2007_input_target_metadata.csv"
  ),
  session_info = file.path(
    output_dir, "australia_sdid_2007_session_info.txt"
  )
)

readr::write_csv(result, output_paths[["results"]])
readr::write_csv(sample_membership, output_paths[["sample_membership"]])
readr::write_csv(unit_weights, output_paths[["unit_weights"]])
readr::write_csv(time_weights, output_paths[["time_weights"]])
readr::write_csv(path, output_paths[["path"]])
readr::write_csv(target_meta, output_paths[["input_metadata"]])
saveRDS(fit, fit_path)

validation_checks <- tibble::tribble(
  ~check, ~passed, ~observed, ~expected,
  "analysis_window", identical(sort(unique(panel$year)), expected_years),
  paste0(min(panel$year), "-", max(panel$year)), "1997-2022",
  "clean_donor_count", length(clean_donors) == 105L,
  as.character(length(clean_donors)), "105",
  "pre_period_count", fit_setup$T0 == 10L,
  as.character(fit_setup$T0), "10",
  "post_period_count", ncol(fit_setup$Y) - fit_setup$T0 == 16L,
  as.character(ncol(fit_setup$Y) - fit_setup$T0), "16",
  "point_estimate_matches_frozen_reference",
  isTRUE(all.equal(estimate, point_reference$estimate[[1L]], tolerance = 1e-12)),
  format(estimate, digits = 17),
  format(point_reference$estimate[[1L]], digits = 17),
  "path_decomposition_matches_att",
  isTRUE(all.equal(att_from_path, estimate, tolerance = 1e-8)),
  format(att_from_path, digits = 17), format(estimate, digits = 17),
  "unit_weights_sum_to_one",
  isTRUE(all.equal(sum(unit_weights$unit_weight), 1, tolerance = 1e-10)),
  format(sum(unit_weights$unit_weight), digits = 17), "1",
  "time_weights_sum_to_one",
  isTRUE(all.equal(sum(time_weights$time_weight), 1, tolerance = 1e-10)),
  format(sum(time_weights$time_weight), digits = 17), "1",
  "checkpoint_has_5000_finite_estimates",
  length(checkpoint$estimates) == placebo_replications &&
    all(is.finite(checkpoint$estimates)),
  paste0(sum(is.finite(checkpoint$estimates)), " finite"), "5000 finite",
  "checkpoint_seed", identical(checkpoint$seed, placebo_seed),
  as.character(checkpoint$seed), as.character(placebo_seed),
  "checkpoint_se_matches_reported_se",
  isTRUE(all.equal(checkpoint_se, se_placebo, tolerance = 1e-12)),
  format(checkpoint_se, digits = 17), format(se_placebo, digits = 17)
)
if (any(!validation_checks$passed)) {
  failed <- validation_checks |>
    dplyr::filter(!passed) |>
    dplyr::pull(check)
  stop("Validation failed: ", paste(failed, collapse = ", "), call. = FALSE)
}
readr::write_csv(validation_checks, output_paths[["validation"]])
capture.output(utils::sessionInfo(), file = output_paths[["session_info"]])

script_path <- file.path(
  "scripts", "diagnostics", "estimate_australia_sdid_2007_placebo.R"
)
manifest_paths <- c(
  unname(output_paths),
  fit_path,
  checkpoint_path,
  point_reference_path,
  point_fit_reference_path,
  script_path,
  file.path("scripts", "diagnostics", "sdid_placebo_helpers.R")
)
artifact_roles <- c(
  rep("new_output", length(output_paths)),
  "new_output",
  "new_checkpoint",
  "frozen_point_reference",
  "frozen_point_reference",
  "analysis_script",
  "shared_helper"
)
output_manifest <- tibble::tibble(
  artifact_role = artifact_roles,
  file = manifest_paths,
  bytes = file.info(manifest_paths)$size,
  sha256 = vapply(
    manifest_paths,
    digest::digest,
    character(1),
    algo = "sha256",
    file = TRUE
  )
)
manifest_path <- file.path(
  output_dir, "australia_sdid_2007_output_manifest.csv"
)
readr::write_csv(output_manifest, manifest_path)

completed_at <- Sys.time()
run_manifest <- list(
  analysis = "australia_sdid_2007_placebo",
  started_at = format(started_at, "%Y-%m-%dT%H:%M:%S%z"),
  completed_at = format(completed_at, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_minutes = as.numeric(difftime(
    completed_at, started_at, units = "mins"
  )),
  command = paste(
    "Rscript --vanilla",
    "scripts/diagnostics/estimate_australia_sdid_2007_placebo.R"
  ),
  script = script_path,
  shared_placebo_helper = file.path(
    "scripts", "diagnostics", "sdid_placebo_helpers.R"
  ),
  targets_pipeline_executed = FALSE,
  target_store_modified = FALSE,
  input_target = input_target,
  input_target_data_hash = if (nrow(target_meta) == 1L) {
    target_meta$data[[1L]]
  } else {
    NA_character_
  },
  analysis_panel_sha256 = digest::digest(
    panel |>
      dplyr::select(
        iso3c, country_name, year, abs_distance_china, china_is_top
      ),
    algo = "sha256",
    serialize = TRUE
  ),
  treated_iso3c = treated_iso3c,
  treatment_year = treatment_year,
  year_start = year_start,
  year_end = year_end,
  clean_donor_count = length(clean_donors),
  placebo_replications = placebo_replications,
  placebo_seed = placebo_seed,
  parallel_cores = parallel_cores,
  att = estimate,
  placebo_se = se_placebo,
  ci_95_low = result$ci_95_low[[1L]],
  ci_95_high = result$ci_95_high[[1L]],
  p_normal_two_sided = result$p_normal_two_sided[[1L]],
  rmspe_pre_level_adjusted = result$rmspe_pre_level_adjusted[[1L]],
  rmspe_post_level_adjusted = result$rmspe_post_level_adjusted[[1L]],
  rmspe_ratio = result$rmspe_ratio[[1L]],
  n_pre_years = result$n_pre_years[[1L]],
  n_post_years = result$n_post_years[[1L]],
  package_versions = as.list(vapply(
    c("digest", "dplyr", "readr", "synthdid", "targets"),
    function(pkg) as.character(utils::packageVersion(pkg)),
    character(1)
  )),
  checkpoint = checkpoint_path,
  checkpoint_sha256 = digest::digest(
    checkpoint_path, algo = "sha256", file = TRUE
  ),
  output_manifest = manifest_path,
  output_manifest_sha256 = digest::digest(
    manifest_path, algo = "sha256", file = TRUE
  )
)
run_manifest_path <- file.path(
  output_dir, "australia_sdid_2007_run_manifest.json"
)
jsonlite::write_json(
  run_manifest,
  run_manifest_path,
  auto_unbox = TRUE,
  pretty = TRUE,
  digits = 17,
  na = "null"
)

message("Completed Australia-2007 placebo inference.")
message("  Results: ", output_paths[["results"]])
message("  Checkpoint: ", checkpoint_path)
message("  Manifest: ", manifest_path)
print(result, n = Inf, width = Inf)
