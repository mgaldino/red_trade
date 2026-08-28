# ---------------------------------------------------------------------------
# Dose-response placebo diagnostic for the Brazil SDiD
# ---------------------------------------------------------------------------
#
# PURPOSE. The paper's principal inference for Brazil is placebo-in-space: every
# donor receives the 2009 pseudo-treatment and yields a pseudo-ATT. The rival
# explanation this diagnostic discriminates is CONTINUOUS DEPENDENCE -- the claim
# that alignment responds smoothly to the DOSE of trade exposure to China, with
# no special role for the rank-#1 threshold. The donor pool is a sample of "dose
# without the crown": countries whose export share to China grew by varying
# amounts but which never became China's rank-#1 goods-export destination.
#
# Crossing each donor's pseudo-ATT with its exposure dose separates the two
# stories. A flat dose-ATT relation, with Brazil extreme even against high-dose
# donors only, says dose alone does not generate convergence. A negative relation
# says dose matters too, and enters the paper as an honest qualification.
#
# WHAT THIS IS NOT. Nothing here is a control in Brazil's estimation. Dose only
# STRATIFIES the comparison set used for the rank test; Brazil's ATT is read from
# the stored placebo distribution and never changes.
#
# TRUNCATION TO DECLARE. No donor crossed the rank-#1 threshold on the goods
# definition that defines treatment, so this exercise can only show the presence
# or absence of a dose gradient BELOW the threshold. It does not, and cannot,
# estimate the discontinuity at the threshold itself.
#
# MEASUREMENT PROVENANCE (important caveat, recorded in the summary output).
# The dose columns consumed here come from donor_china_exposure.csv, which
# brazil_sdid_donor_china_exposure() builds from trade_data_cleaned and
# trade_data_ranked -- both ALL-SECTOR series, i.e. get_trade_data() applies no
# broad_sector filter, so services are included. Treatment and the donor screen,
# by contrast, are defined on GOODS (trade_data_goods_ranked). The two bases
# disagree for exactly one donor: Singapore is China's rank-#1 partner in
# 2013-2014 on all-sector trade but never better than rank #2 on goods, which is
# why it is an eligible donor and why the exposure file nonetheless flags it as
# "China top export destination post-2009". The dose measure is therefore an
# export share computed on the all-sector file -- exports to China over the
# country's total exports to all partners, since process_trade_data() groups by
# exporter and total_trade is the sum of that exporter's outward flows -- and
# the pool remains untreated on the goods definition that identifies the design.
#
# INFERENCE DISCIPLINE. The slope and correlations below are DESCRIPTIVE ONLY.
# Donor pseudo-ATTs are not independent: each is fitted against a donor pool that
# overlaps heavily with every other donor's pool, so their errors are correlated
# by construction. No standard error or p-value for the slope is computed or
# reported, because none would have a defensible sampling interpretation. The
# only inferential statements are the rank/permutation p-values, which inherit
# their justification from the placebo design itself.

# Rank convention. The body below MIRRORS sdid_rank_inference() in
# scripts/diagnostics/sdid_placebo_helpers.R VERBATIM: ties are inclusive
# (`<=` / `>=`), the treated unit is counted in its own numerator, and the
# denominator is the number of valid assignments retained. It is duplicated
# rather than sourced because sdid_placebo_helpers.R is deliberately NOT part of
# the targets graph (it belongs to the standalone audit layer); sourcing it from
# target code would drag an unmanaged file into the pipeline's dependency
# tracking. The self-test row written by
# summarise_brazil_sdid_dose_placebo_ranks() reproduces the full-pool ranks from
# rank_inference.csv and fails loudly if this duplicate ever drifts.
brazil_sdid_dose_placebo_rank_inference <- function(distribution,
                                                    comparison_set,
                                                    keep_units = NULL,
                                                    treated_iso3c = "BRA") {
  valid <- distribution |>
    dplyr::filter(status == "estimated", !is.na(estimate))
  if (!is.null(keep_units)) {
    valid <- valid |> dplyr::filter(iso3c %in% keep_units)
  }
  treated <- valid |> dplyr::filter(iso3c == treated_iso3c)
  if (nrow(treated) != 1L) {
    stop("Treated unit ", treated_iso3c,
         " absent from the comparison set: ", comparison_set, call. = FALSE)
  }
  tibble::tibble(
    comparison_set = comparison_set,
    excluded_units = paste(setdiff(distribution$iso3c, valid$iso3c),
                           collapse = ";"),
    rank_one_sided_negative = sum(valid$estimate <= treated$estimate),
    rank_two_sided_absolute = sum(abs(valid$estimate) >= abs(treated$estimate)),
    denominator = nrow(valid),
    p_rank_one_sided_negative = mean(valid$estimate <= treated$estimate),
    p_rank_two_sided_absolute = mean(abs(valid$estimate) >= abs(treated$estimate)),
    resolution_floor = 1 / nrow(valid)
  )
}


# Reads the stored placebo distribution and the donor exposure table, joins them
# on iso3c, and returns the analysis dataset plus the provenance checks that the
# reviewer needs in order to trust it.
#
# The treated unit is returned separately and deliberately carries NO dose: BRA
# has no row in donor_china_exposure.csv (it is not a donor), and inventing a
# dose for it from another source would silently change the measurement basis.
build_brazil_sdid_dose_placebo_dataset <- function(placebo_path,
                                                   exposure_path,
                                                   treated_iso3c = "BRA") {
  placebo <- readr::read_csv(
    placebo_path,
    col_types = readr::cols(
      iso3c = readr::col_character(),
      estimate = readr::col_double(),
      rmspe_pre = readr::col_double(),
      status = readr::col_character(),
      .default = readr::col_character()
    )
  )

  exposure <- readr::read_csv(
    exposure_path,
    col_types = readr::cols(
      iso3c = readr::col_character(),
      country_name = readr::col_character(),
      region = readr::col_character(),
      unit_weight = readr::col_double(),
      mean_china_export_share_pre_treatment = readr::col_double(),
      mean_china_export_share_post_treatment = readr::col_double(),
      delta_mean_china_export_share_post_minus_pre = readr::col_double(),
      min_china_rank_post_treatment = readr::col_double(),
      china_exposure_flag = readr::col_character(),
      .default = readr::col_guess()
    )
  )

  # The rank convention is applied to the valid assignments only, exactly as in
  # the stored rank_inference.csv.
  valid <- placebo |>
    dplyr::filter(status == "estimated", !is.na(estimate))

  treated <- valid |> dplyr::filter(iso3c == treated_iso3c)
  if (nrow(treated) != 1L) {
    stop("build_brazil_sdid_dose_placebo_dataset: treated unit ", treated_iso3c,
         " must appear exactly once among the valid assignments; found ",
         nrow(treated), ".", call. = FALSE)
  }

  donor_estimates <- valid |> dplyr::filter(iso3c != treated_iso3c)

  # Recompute the dose from its two components rather than trusting the stored
  # difference, then confirm the stored column agrees. A silent disagreement
  # would mean the exposure file and its own inputs had drifted apart.
  exposure_dose <- exposure |>
    dplyr::mutate(
      dose_delta_share = mean_china_export_share_post_treatment -
        mean_china_export_share_pre_treatment,
      dose_post_share = mean_china_export_share_post_treatment
    )

  max_abs_delta_discrepancy <- max(abs(
    exposure_dose$dose_delta_share -
      exposure_dose$delta_mean_china_export_share_post_minus_pre
  ))
  if (!isTRUE(all.equal(
    exposure_dose$dose_delta_share,
    exposure_dose$delta_mean_china_export_share_post_minus_pre,
    tolerance = 1e-12
  ))) {
    stop("build_brazil_sdid_dose_placebo_dataset: the recomputed post-minus-pre ",
         "dose disagrees with delta_mean_china_export_share_post_minus_pre ",
         "(max absolute discrepancy ", format(max_abs_delta_discrepancy),
         "); the exposure file is internally inconsistent.", call. = FALSE)
  }

  donors <- donor_estimates |>
    dplyr::left_join(
      exposure_dose |>
        dplyr::select(
          iso3c, country_name, region, unit_weight,
          mean_china_export_share_pre_treatment,
          mean_china_export_share_post_treatment,
          dose_delta_share, dose_post_share,
          min_china_rank_post_treatment, china_exposure_flag
        ),
      by = "iso3c"
    ) |>
    dplyr::arrange(iso3c)

  dropped <- donors |>
    dplyr::filter(is.na(dose_delta_share) | is.na(dose_post_share))

  checks <- tibble::tibble(
    n_placebo_rows = nrow(placebo),
    n_placebo_not_estimated = sum(placebo$status != "estimated" | is.na(placebo$estimate)),
    n_valid_assignments = nrow(valid),
    n_donors = nrow(donor_estimates),
    n_exposure_rows = nrow(exposure),
    n_donors_with_dose = nrow(donors) - nrow(dropped),
    n_donors_dropped_missing_exposure = nrow(dropped),
    dropped_iso3c = paste(dropped$iso3c, collapse = ";"),
    exposure_rows_without_placebo = paste(
      setdiff(exposure$iso3c, donor_estimates$iso3c), collapse = ";"
    ),
    max_abs_delta_discrepancy = max_abs_delta_discrepancy,
    treated_iso3c = treated_iso3c,
    treated_estimate = treated$estimate
  )

  list(
    donors = donors,
    treated = treated,
    # The FULL distribution is retained (not just the valid rows) because
    # sdid_rank_inference() derives `excluded_units` from it; passing the
    # pre-filtered table would silently empty that column.
    placebo = placebo,
    valid = valid,
    checks = checks
  )
}


# Top-quartile membership for one dose definition.
#
# Cutoff = the 75th percentile of the dose AMONG DONORS WITH AN OBSERVED DOSE,
# using stats::quantile()'s default type 7 (R's default; linear interpolation of
# order statistics). Boundary rule: a donor is high-dose when dose >= cutoff, so
# a donor sitting exactly on the cutoff is retained. Both choices are recorded in
# the summary output so the subgroup is reconstructible without reading this code.
brazil_sdid_dose_placebo_high_dose <- function(donors, dose_column,
                                               cutoff_prob = 0.75) {
  dose <- donors[[dose_column]]
  observed <- dose[!is.na(dose)]
  cutoff <- stats::quantile(
    observed,
    probs = cutoff_prob,
    na.rm = TRUE,
    names = FALSE,
    type = 7
  )
  list(
    cutoff = cutoff,
    iso3c = donors$iso3c[!is.na(dose) & dose >= cutoff]
  )
}


# Descriptive association between dose and pseudo-ATT.
#
# NO standard error and NO p-value are returned. Donor pseudo-ATTs share
# overlapping donor pools, so OLS sampling theory does not apply to this slope;
# reporting an SE would dress a correlated-error artefact as a formal test. The
# slope is reported in two scalings -- per unit of export share and per
# percentage point -- so that the figure's annotation (percentage points) and the
# native-unit data cannot be confused for one another.
brazil_sdid_dose_placebo_association <- function(donors, dose_column) {
  fit_data <- donors |>
    dplyr::filter(!is.na(.data[[dose_column]]), !is.na(estimate))

  dose <- fit_data[[dose_column]]
  outcome <- fit_data$estimate

  fit <- stats::lm(outcome ~ dose)
  slope_per_unit_share <- unname(stats::coef(fit)[["dose"]])

  tibble::tibble(
    n_donors = nrow(fit_data),
    ols_intercept = unname(stats::coef(fit)[["(Intercept)"]]),
    ols_slope_per_unit_share = slope_per_unit_share,
    ols_slope_per_percentage_point = slope_per_unit_share / 100,
    pearson_correlation = stats::cor(dose, outcome, method = "pearson"),
    spearman_correlation = stats::cor(dose, outcome, method = "spearman")
  )
}


# Assembles every quantity the diagnostic reports: the two dose definitions, the
# descriptive associations, the quartile cutoffs, and the rank tests on the
# full pool (self-test) and on each high-dose subgroup.
compute_brazil_sdid_dose_placebo_results <- function(dataset,
                                                     cutoff_prob = 0.75,
                                                     treated_iso3c = "BRA") {
  donors <- dataset$donors
  distribution <- dataset$placebo

  dose_definitions <- c(
    delta_share = "dose_delta_share",
    post_share = "dose_post_share"
  )

  # These labels are pasted into the `comparison_set` column of the rank output,
  # so they are the only description of the dose a reader of that CSV alone ever
  # sees. They carry the "all-sector" qualifier for the same reason the figure
  # and dose_measurement_basis do: the dose rests on the all-sector trade file
  # while treatment and the donor screen are defined on goods, and a label that
  # said only "China export share" would hide that two sector definitions are in
  # play. The self-test row's comparison_set is a separate literal below and is
  # deliberately left alone -- it names the reference row, not a dose.
  dose_labels <- c(
    delta_share = "Change in all-sector China export share, post minus pre",
    post_share = "Post-period mean all-sector China export share"
  )

  high_dose <- lapply(dose_definitions, function(column) {
    brazil_sdid_dose_placebo_high_dose(donors, column, cutoff_prob)
  })

  associations <- lapply(names(dose_definitions), function(nm) {
    brazil_sdid_dose_placebo_association(donors, dose_definitions[[nm]]) |>
      dplyr::mutate(dose_definition = nm, .before = 1)
  })
  associations <- dplyr::bind_rows(associations)

  # Self-test: with keep_units = NULL this must reproduce the stored
  # "All valid assignments" row of rank_inference.csv exactly (3 / 7 / 96).
  ranks <- list(
    brazil_sdid_dose_placebo_rank_inference(
      distribution,
      comparison_set = "All valid assignments (self-test vs rank_inference.csv)",
      keep_units = NULL,
      treated_iso3c = treated_iso3c
    ) |>
      dplyr::mutate(
        dose_definition = "none",
        dose_cutoff = NA_real_,
        .before = 1
      )
  )

  for (nm in names(dose_definitions)) {
    keep <- c(treated_iso3c, high_dose[[nm]]$iso3c)
    ranks[[length(ranks) + 1L]] <- brazil_sdid_dose_placebo_rank_inference(
      distribution,
      comparison_set = paste0(
        "Brazil plus top-quartile donors by ", dose_labels[[nm]]
      ),
      keep_units = keep,
      treated_iso3c = treated_iso3c
    ) |>
      dplyr::mutate(
        dose_definition = nm,
        dose_cutoff = high_dose[[nm]]$cutoff,
        .before = 1
      )
  }
  ranks <- dplyr::bind_rows(ranks)

  list(
    donors = donors,
    treated = dataset$treated,
    checks = dataset$checks,
    associations = associations,
    ranks = ranks,
    high_dose = high_dose,
    cutoff_prob = cutoff_prob,
    dose_definitions = dose_definitions,
    dose_labels = dose_labels
  )
}


# Wide one-row summary: every number the diagnostic produces, at full precision.
#
# No slope standard error or p-value appears here, by design (see the header).
brazil_sdid_dose_placebo_summary_row <- function(results) {
  assoc <- results$associations
  ranks <- results$ranks
  checks <- results$checks

  pick_assoc <- function(nm, column) assoc[[column]][assoc$dose_definition == nm]
  pick_rank <- function(nm, column) ranks[[column]][ranks$dose_definition == nm]

  tibble::tibble(
    treated_iso3c = checks$treated_iso3c,
    brazil_estimate = checks$treated_estimate,

    n_valid_assignments = checks$n_valid_assignments,
    n_donors = checks$n_donors,
    n_donors_with_dose = checks$n_donors_with_dose,
    n_donors_dropped_missing_exposure = checks$n_donors_dropped_missing_exposure,
    dropped_iso3c = checks$dropped_iso3c,
    exposure_rows_without_placebo = checks$exposure_rows_without_placebo,
    max_abs_delta_discrepancy = checks$max_abs_delta_discrepancy,

    # Primary dose: post minus pre change in the China export share.
    delta_share_ols_slope_per_unit_share = pick_assoc("delta_share", "ols_slope_per_unit_share"),
    delta_share_ols_slope_per_percentage_point = pick_assoc("delta_share", "ols_slope_per_percentage_point"),
    delta_share_ols_intercept = pick_assoc("delta_share", "ols_intercept"),
    delta_share_pearson_correlation = pick_assoc("delta_share", "pearson_correlation"),
    delta_share_spearman_correlation = pick_assoc("delta_share", "spearman_correlation"),
    delta_share_quartile_cutoff = results$high_dose$delta_share$cutoff,
    delta_share_n_high_dose_donors = length(results$high_dose$delta_share$iso3c),
    delta_share_rank_one_sided_negative = pick_rank("delta_share", "rank_one_sided_negative"),
    delta_share_rank_two_sided_absolute = pick_rank("delta_share", "rank_two_sided_absolute"),
    delta_share_denominator = pick_rank("delta_share", "denominator"),
    delta_share_p_rank_one_sided_negative = pick_rank("delta_share", "p_rank_one_sided_negative"),
    delta_share_p_rank_two_sided_absolute = pick_rank("delta_share", "p_rank_two_sided_absolute"),
    delta_share_resolution_floor = pick_rank("delta_share", "resolution_floor"),

    # Sensitivity dose: post-period level of the China export share.
    post_share_ols_slope_per_unit_share = pick_assoc("post_share", "ols_slope_per_unit_share"),
    post_share_ols_slope_per_percentage_point = pick_assoc("post_share", "ols_slope_per_percentage_point"),
    post_share_ols_intercept = pick_assoc("post_share", "ols_intercept"),
    post_share_pearson_correlation = pick_assoc("post_share", "pearson_correlation"),
    post_share_spearman_correlation = pick_assoc("post_share", "spearman_correlation"),
    post_share_quartile_cutoff = results$high_dose$post_share$cutoff,
    post_share_n_high_dose_donors = length(results$high_dose$post_share$iso3c),
    post_share_rank_one_sided_negative = pick_rank("post_share", "rank_one_sided_negative"),
    post_share_rank_two_sided_absolute = pick_rank("post_share", "rank_two_sided_absolute"),
    post_share_denominator = pick_rank("post_share", "denominator"),
    post_share_p_rank_one_sided_negative = pick_rank("post_share", "p_rank_one_sided_negative"),
    post_share_p_rank_two_sided_absolute = pick_rank("post_share", "p_rank_two_sided_absolute"),
    post_share_resolution_floor = pick_rank("post_share", "resolution_floor"),

    # Self-test against the stored rank_inference.csv "All valid assignments" row.
    selftest_rank_one_sided_negative = pick_rank("none", "rank_one_sided_negative"),
    selftest_rank_two_sided_absolute = pick_rank("none", "rank_two_sided_absolute"),
    selftest_denominator = pick_rank("none", "denominator"),

    quartile_cutoff_probability = results$cutoff_prob,
    quantile_type = 7L,
    high_dose_boundary_rule = "dose >= cutoff",
    dose_measurement_basis = paste(
      "China export share computed on the all-sector trade file (goods and",
      "services) from donor_china_exposure.csv: exports to China divided by",
      "total exports to all partners, i.e. trade_with_china / total_trade,",
      "where total_trade is the sum of the country's exports across all",
      "partners and NOT a measure of two-way trade. Treatment and the donor",
      "screen are defined on goods, so no donor crossed the rank-1 threshold",
      "on the treatment-defining sector definition."
    ),
    slope_inference_note = paste(
      "Slope and correlations are descriptive only: donor pseudo-ATTs share",
      "overlapping donor pools, so their errors are correlated and no standard",
      "error or p-value for the slope is defensible. Only the rank p-values are",
      "inferential."
    ),
    # The sector qualifier below is not decoration. "Dose without the crown" is
    # true on GOODS, the definition that assigns treatment, and false on the
    # ALL-SECTOR file this same row uses to MEASURE the dose, where Singapore
    # held rank 1. Naming Singapore here is the only way a reader of this CSV
    # can learn it: neither this file nor rank_inference.csv carries a per-donor
    # exposure column, so an unqualified claim would be unfalsifiable from the
    # shipped outputs alone.
    truncation_note = paste(
      "Donors span dose without the rank-1 crown on the goods definition that",
      "defines treatment: no donor-year sits at goods rank 1 over 1997-2015, so",
      "the diagnostic shows the presence or absence of a dose gradient BELOW the",
      "threshold and does not identify the discontinuity at the threshold. The",
      "sector qualifier is load-bearing. On the all-sector basis this file uses",
      "to MEASURE the dose, exactly one donor reached rank 1: Singapore, China's",
      "top all-sector export destination in 2013-2014, which sits inside both",
      "high-dose subgroups. The crownless span is therefore a property of the",
      "goods definition alone."
    )
  )
}


# Creates the output directory for a file the diagnostic is about to write.
# Both writers below (the CSV writer and the figure writer) need this, so the
# call lives in one place rather than being repeated verbatim at each site.
ensure_brazil_sdid_dose_placebo_dir <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}


# Writes a CSV with no rounding, and verifies that every double survives the
# trip to disk at full double precision. These outputs are the citable source
# for numbers that may reach the manuscript, so a silent `round(x, 3)` creeping
# in later must break the build rather than quietly degrade the record.
#
# WHY THE TOLERANCE IS A FEW ULP AND NOT BIT-EXACT. readr::write_csv emits full
# 17-significant-digit text, and that text is exactly right: the C library's
# strtod reparses "0.10877366210152313" to 0x1.bd897396466fdp-4, bit-identical
# to the value written. R's own parser is the lossy component -- as.numeric(),
# scan() and therefore utils::read.csv() return 0x1.bd897396466fcp-4 for that
# same text, one unit in the last place low, because R_strtod is not correctly
# rounded. On this platform roughly 29% of random doubles reparse one ULP off.
# Demanding bit equality here would therefore fail on files that are in fact
# perfectly precise, and would tempt a future maintainer to "fix" the failure by
# rounding the output -- the exact damage this check exists to prevent. The
# bound below is a few ULP, which passes parser noise and still fails by many
# orders of magnitude on any genuine rounding of the data.
brazil_sdid_dose_placebo_write_csv <- function(data, path) {
  ensure_brazil_sdid_dose_placebo_dir(path)
  readr::write_csv(data, path, na = "")

  roundtrip <- utils::read.csv(path, colClasses = "character",
                               check.names = FALSE)
  numeric_columns <- names(data)[vapply(data, is.numeric, logical(1))]
  ulp_tolerance <- 8 * .Machine$double.eps

  for (column in numeric_columns) {
    written <- roundtrip[[column]]
    written[written == ""] <- NA_character_
    original <- as.numeric(data[[column]])
    reparsed <- suppressWarnings(as.numeric(written))

    if (!identical(is.na(original), is.na(reparsed))) {
      stop("brazil_sdid_dose_placebo_write_csv: column '", column,
           "' changes its missing-value pattern when written to ", path, ".",
           call. = FALSE)
    }

    observed <- original[!is.na(original)]
    recovered <- reparsed[!is.na(reparsed)]
    within_tolerance <- ifelse(
      observed == 0,
      recovered == 0,
      abs(observed - recovered) <= ulp_tolerance * abs(observed)
    )
    if (!all(within_tolerance)) {
      stop("brazil_sdid_dose_placebo_write_csv: column '", column,
           "' does not round-trip through ", path,
           " at full double precision; the written file loses precision.",
           call. = FALSE)
    }
  }
  path
}


write_brazil_sdid_dose_placebo_summary <- function(results, path) {
  brazil_sdid_dose_placebo_write_csv(
    brazil_sdid_dose_placebo_summary_row(results), path
  )
}


# Long per-comparison-set rank table, in the format of the pipeline's stored
# rank_inference.csv plus the dose columns and the resolution floor.
#
# Hard gate: the self-test row must reproduce the stored full-pool ranks. If the
# duplicated rank convention ever drifts from sdid_rank_inference(), this stops
# the build instead of publishing a silently different convention.
write_brazil_sdid_dose_placebo_ranks <- function(results,
                                                 rank_reference_path,
                                                 path) {
  reference <- readr::read_csv(
    rank_reference_path,
    col_types = readr::cols(
      comparison_set = readr::col_character(),
      excluded_units = readr::col_character(),
      rank_one_sided_negative = readr::col_integer(),
      rank_two_sided_absolute = readr::col_integer(),
      denominator = readr::col_integer(),
      .default = readr::col_double()
    )
  ) |>
    dplyr::filter(comparison_set == "All valid assignments")

  if (nrow(reference) != 1L) {
    stop("write_brazil_sdid_dose_placebo_ranks: expected exactly one ",
         "'All valid assignments' row in ", rank_reference_path, "; found ",
         nrow(reference), ".", call. = FALSE)
  }

  selftest <- results$ranks |>
    dplyr::filter(dose_definition == "none")

  observed <- c(
    selftest$rank_one_sided_negative,
    selftest$rank_two_sided_absolute,
    selftest$denominator
  )
  expected <- c(
    reference$rank_one_sided_negative,
    reference$rank_two_sided_absolute,
    reference$denominator
  )

  if (!identical(as.integer(observed), as.integer(expected))) {
    stop("write_brazil_sdid_dose_placebo_ranks: the self-test does not ",
         "reproduce rank_inference.csv. Expected one-sided/two-sided/denominator ",
         paste(expected, collapse = "/"), " but computed ",
         paste(observed, collapse = "/"),
         ". The duplicated rank convention has drifted from ",
         "sdid_rank_inference().", call. = FALSE)
  }

  # Flags WHICH row is the self-test, not whether it passed: a failed self-test
  # has already aborted above, so every file written carries a verified one.
  # Naming this "selftest_matches_..." would put a FALSE on the subgroup rows and
  # read as if they had failed a check that was never applied to them.
  ranks_out <- results$ranks |>
    dplyr::mutate(is_selftest_row = dose_definition == "none")

  brazil_sdid_dose_placebo_write_csv(ranks_out, path)
}


# Scatter of donor pseudo-ATT against exposure dose.
#
# Brazil is drawn as a dashed HORIZONTAL line at its estimate and has NO dose
# coordinate: it has no row in the exposure file, and fabricating a dose for it
# from another source would change the measurement basis behind the reader's
# back. The vertical dashed line marks the top-quartile cutoff, so the figure
# shows exactly which donors enter the high-dose rank test.
#
# The axis label and the caption both say the dose is an ALL-SECTOR export share
# while the threshold statement is about GOODS. Two sector definitions are in
# play (see MEASUREMENT PROVENANCE at the top of this file) and a reader who
# sees only the figure must be able to tell, so the mixed basis is carried in
# the figure text rather than left to the summary CSV.
plot_brazil_sdid_dose_placebo <- function(results, dose_key = "delta_share") {
  dose_column <- results$dose_definitions[[dose_key]]
  cutoff <- results$high_dose[[dose_key]]$cutoff
  # Base subsetting rather than dplyr::filter(): the association table's column
  # is itself called `dose_definition`, and masking it against a same-named
  # argument is exactly the kind of shadowing that silently returns every row.
  assoc <- results$associations[results$associations$dose_definition == dose_key, ]

  # Percentage points on the x axis: the native share is a proportion, and a
  # 0-13% range reads badly as decimals. The slope annotation is rescaled to
  # match the axis; both scalings are in the summary CSV.
  plot_df <- results$donors |>
    dplyr::filter(!is.na(.data[[dose_column]])) |>
    dplyr::mutate(
      dose_pp = .data[[dose_column]] * 100,
      dose_group = dplyr::if_else(
        .data[[dose_column]] >= cutoff,
        "Top-quartile dose", "Lower three quartiles"
      )
    )

  brazil_estimate <- results$checks$treated_estimate

  annotation <- paste0(
    "Donors: n = ", assoc$n_donors, "\n",
    "OLS slope: ", sprintf("%.4f", assoc$ols_slope_per_percentage_point),
    " per pp (descriptive)\n",
    "Spearman: ", sprintf("%.3f", assoc$spearman_correlation)
  )

  ggplot2::ggplot(
    plot_df,
    ggplot2::aes(x = dose_pp, y = estimate)
  ) +
    ggplot2::geom_hline(
      yintercept = brazil_estimate,
      linetype = "dashed",
      linewidth = 0.6,
      colour = "#D55E00"
    ) +
    ggplot2::annotate(
      "text",
      x = max(plot_df$dose_pp, na.rm = TRUE),
      y = brazil_estimate,
      label = paste0("Brazil ATT = ", sprintf("%.3f", brazil_estimate),
                     " (no dose coordinate)"),
      hjust = 1,
      vjust = -0.6,
      size = 3.1,
      colour = "#D55E00"
    ) +
    ggplot2::geom_vline(
      xintercept = cutoff * 100,
      linetype = "dotted",
      linewidth = 0.5,
      colour = "grey35"
    ) +
    ggplot2::geom_smooth(
      method = "lm",
      formula = y ~ x,
      se = FALSE,
      linewidth = 0.6,
      colour = "grey35"
    ) +
    ggplot2::geom_point(
      ggplot2::aes(colour = dose_group),
      size = 1.9,
      alpha = 0.8
    ) +
    ggplot2::scale_colour_manual(
      values = c(
        "Lower three quartiles" = "#4C78A8",
        "Top-quartile dose" = "#1f4e79"
      ),
      name = NULL
    ) +
    # Anchored on the data range rather than -Inf so the block stays inside the
    # panel and left-aligns; `label` would centre the three lines inside a box.
    ggplot2::annotate(
      "text",
      x = min(plot_df$dose_pp, na.rm = TRUE),
      y = min(plot_df$estimate, na.rm = TRUE),
      label = annotation,
      hjust = 0,
      vjust = 0,
      size = 3.1,
      colour = "grey20"
    ) +
    ggplot2::labs(
      x = "Change in all-sector export share to China, 2009-2015 mean minus 1997-2008 mean (percentage points)",
      y = "Placebo pseudo-ATT on UNGA ideal-point distance to China",
      caption = paste0(
        "Each point is a donor given the 2009 pseudo-treatment. The dose is an ",
        "all-sector export share (goods and services); treatment\n",
        "and the donor screen are defined on goods only. No donor became ",
        "China's top goods-export destination, so the plot shows the\n",
        "dose gradient below the threshold rather than the discontinuity at it. ",
        "The dotted line marks the top-quartile dose cutoff.\n",
        "The fitted line is descriptive only: donor pools overlap, so no ",
        "standard error is reported for the slope."
      )
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "top",
      plot.caption = ggplot2::element_text(hjust = 0, size = 7.5,
                                           colour = "grey30"),
      plot.title = ggplot2::element_blank()
    )
}


# Builds the figure and writes it, taking `results` rather than a ready-made
# ggplot.
#
# WHY THE PLOT IS NOT PASSED IN. A ggplot object carries its `plot_env`, and
# serializing that environment is session-dependent: the same inputs produced
# two different object hashes in two different sessions, which would make a
# stored-plot target -- and this file target downstream of it -- report outdated
# and rebuild on a replication machine for no substantive reason. Building the
# plot inside the target that writes the PNG means no ggplot object is ever
# hashed, so the only thing tracked is the PNG itself. plot_brazil_sdid_dose_placebo()
# stays a separate named function so the figure's construction can be read, and
# re-run interactively, on its own.
write_brazil_sdid_dose_placebo_figure <- function(results, path,
                                                  dose_key = "delta_share",
                                                  width = 9, height = 6.2,
                                                  dpi = 300) {
  ensure_brazil_sdid_dose_placebo_dir(path)
  ggplot2::ggsave(
    filename = path,
    plot = plot_brazil_sdid_dose_placebo(results, dose_key = dose_key),
    width = width,
    height = height,
    dpi = dpi,
    bg = "white"
  )
  path
}
