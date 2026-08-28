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
# amounts but for which China never became the rank-#1 goods-export destination.
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
# estimate the discontinuity at the threshold itself. That claim is no longer
# asserted in prose: brazil_sdid_dose_placebo_rank_one_check() recomputes it from
# the ranked trade data at every build and aborts if it ever stops being true.
#
# ---------------------------------------------------------------------------
# TWO MEASUREMENT ARMS
# ---------------------------------------------------------------------------
#
# Treatment and the donor screen are defined on GOODS-only export ranks
# (ITPD-E broad sectors Agriculture, Mining and Energy, and Manufacturing;
# services are excluded before ranking -- see get_trade_data_goods()). The dose
# that stratifies the comparison set must therefore be measured on the SAME
# sector basis as the treatment it is meant to be an alternative explanation
# for. Measuring the dose on one sector definition while assigning treatment on
# another leaves a gap that a referee can drive through: a flat gradient on
# all-sector shares does not, on its own, rule out a gradient on the shares that
# actually define the design.
#
#   PRIMARY ARM (goods-only). Dose = a country's goods exports to China over its
#   total goods exports to all partners, computed inside the targets graph from
#   trade_data_goods -- the very object rank_trade() ranks to assign treatment.
#   This arm supplies the figure, the headline subgroup rank tests, and the
#   summary's primary columns.
#
#   ROBUSTNESS ARM (all-sector). Dose = the same share computed on the
#   all-sector trade file, read from donor_china_exposure.csv, which
#   brazil_sdid_donor_china_exposure() builds from trade_data_cleaned and
#   trade_data_ranked (get_trade_data() applies no broad_sector filter, so
#   services are included). This arm is retained in full, not discarded: it is
#   the measurement-robustness comparison that shows whether the sector basis
#   drives anything.
#
# Every shipped number carries its arm in its column name, its comparison_set
# string, or a dedicated analysis_arm column, so no file can be read in
# isolation and leave the arm in doubt.
#
# The two bases disagree about the crown for exactly one donor: China is
# Singapore's rank-#1 export destination in 2013-2014 on all-sector trade but
# never better than rank #2 on goods over 1997-2015, which is why Singapore is
# an eligible donor and why the exposure file nonetheless flags it as "China top
# export destination post-2009". Singapore's position on the goods dose is
# recorded explicitly in the summary for this reason.
#
# ---------------------------------------------------------------------------
# DOSE DEFINITION, REPLICATED RATHER THAN REINVENTED
# ---------------------------------------------------------------------------
#
# brazil_sdid_dose_placebo_period_dose() reproduces, property for property, the
# definition behind donor_china_exposure.csv (brazil_sdid_donor_china_exposure()
# in scripts/functions.R, together with process_trade_data()):
#
#   (i)   windows are pre-treatment 1997-2008 and post-treatment 2009-2015;
#   (ii)  the ANNUAL share is trade_with_china / total_trade, where for each
#         (year, exporter) total_trade is the sum of that exporter's OUTWARD
#         flows to all partners -- an export share, not a two-way trade share --
#         and trade_with_china is that exporter's flow to CHN;
#   (iii) the PERIOD dose is mean(annual share, na.rm = TRUE), the MEAN OF THE
#         ANNUAL SHARES and not a ratio of period totals; the two differ
#         whenever total exports vary across years.
#
# The replication is not asserted, it is tested:
# brazil_sdid_dose_placebo_verify_dose_definition() applies the same function to
# the ALL-SECTOR trade table and requires the result to reproduce
# donor_china_exposure.csv's stored period means to 1e-12, aborting the build
# otherwise. Any future drift between the two implementations -- or any error in
# this one -- fails loudly instead of shipping a goods dose computed under a
# silently different rule.
#
# DEGENERATE COUNTRY-YEARS. An exporter with zero total goods exports in a year
# has an undefined annual share (0 / 0 is NaN in R). The rule is inherited, not
# invented: na.rm = TRUE in the period mean drops those years, so the period
# dose is the mean over the years in which the share is defined, exactly as the
# all-sector code does. A donor whose every year in a period is degenerate has
# no dose for that period and is excluded from that dose definition's OLS,
# quartile cutoff and subgroup, and is counted in the shipped dropped columns.
# The count of undefined country-years, and the exporters they belong to, are
# recorded in the summary rather than left implicit.
# Alternative discarded: treating a zero-export year as a zero share. That would
# silently pull the period mean toward zero for a country with no trade at all
# to average, and -- decisively -- it would DEPART from the all-sector rule,
# making the robustness arm non-comparable to the primary one.
#
# ---------------------------------------------------------------------------
# THE TREATED UNIT HAS NO DOSE COORDINATE, ON EITHER ARM
# ---------------------------------------------------------------------------
#
# Brazil is absent from donor_china_exposure.csv by construction (it is not a
# donor), so the all-sector arm CANNOT supply a dose for it. The goods arm
# could: trade_data_goods contains BRA, and a Brazilian goods dose is one
# group_by away. It is deliberately not computed, and Brazil is added to every
# high-dose subgroup UNCONDITIONALLY rather than by clearing a cutoff.
#
# Reasons, in order of weight:
#   1. ARM SYMMETRY. If the primary figure placed Brazil at a dose coordinate
#      and the robustness figure could not, the two arms would differ in how
#      they treat the treated unit as well as in sector basis, and the
#      robustness comparison would confound the two.
#   2. THE RANK TEST WOULD BECOME CONDITIONAL ON THE TREATED UNIT'S OWN
#      EXPOSURE. Making Brazil's membership depend on its dose clearing the
#      cutoff would leave the subgroup test undefined whenever Brazil fell
#      below it, and would make the comparison set a function of precisely the
#      quantity under test.
#   3. Brazil's ATT is read from the stored placebo distribution and never
#      enters the OLS. A dose coordinate would invite reading the scatter as if
#      Brazil were a fitted point.
# This rule is written into both CSVs (treated_unit_dose_rule) so a reader of
# comparison_set alone can tell that Brazil is in the subgroup by construction
# and not because its dose cleared the cutoff.
#
# INFERENCE DISCIPLINE. The slopes and correlations below are DESCRIPTIVE ONLY,
# on BOTH arms. Donor pseudo-ATTs are not independent: each is fitted against a
# donor pool that overlaps heavily with every other donor's pool, so their errors
# are correlated by construction. No standard error or p-value for any slope is
# computed or reported on any basis, because none would have a defensible
# sampling interpretation. The only inferential statements are the
# rank/permutation p-values, which inherit their justification from the placebo
# design itself.

# Rank convention. The body below MIRRORS sdid_rank_inference() in
# scripts/diagnostics/sdid_placebo_helpers.R VERBATIM: ties are inclusive
# (`<=` / `>=`), the treated unit is counted in its own numerator, and the
# denominator is the number of valid assignments retained. It is duplicated
# rather than sourced because sdid_placebo_helpers.R is deliberately NOT part of
# the targets graph (it belongs to the standalone audit layer); sourcing it from
# target code would drag an unmanaged file into the pipeline's dependency
# tracking. The self-test row written by
# write_brazil_sdid_dose_placebo_ranks() reproduces the full-pool ranks from
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


# Period dose from a long bilateral trade table, on whatever sector basis the
# caller hands it. See "DOSE DEFINITION" in the header: this is the single
# implementation used for BOTH arms, which is what makes the two comparable and
# what lets verify_dose_definition() test the goods computation by running it on
# the all-sector data.
#
# `trade_long` must carry year, exporter_iso3, importer_iso3 and exports, which
# is the schema of both trade_data_goods and trade_data.
#
# Returns a list rather than a bare tibble because the coverage facts (how many
# country-years had an undefined share, and for whom) are part of the record the
# summary must ship, and attaching them to the dose table as attributes would
# make them invisible to the first dplyr verb applied downstream.
brazil_sdid_dose_placebo_period_dose <- function(trade_long,
                                                 basis_label,
                                                 pre_years = 1997:2008,
                                                 post_years = 2009:2015,
                                                 china_iso3 = "CHN") {
  required_columns <- c("year", "exporter_iso3", "importer_iso3", "exports")
  missing_columns <- setdiff(required_columns, names(trade_long))
  if (length(missing_columns) > 0L) {
    stop("brazil_sdid_dose_placebo_period_dose: the ", basis_label,
         " trade table is missing required column(s): ",
         paste(missing_columns, collapse = ", "),
         ". The dose cannot be computed on a table with a different schema.",
         call. = FALSE)
  }
  if (length(intersect(pre_years, post_years)) > 0L) {
    stop("brazil_sdid_dose_placebo_period_dose: pre_years and post_years ",
         "overlap, so a country-year would be averaged into both periods.",
         call. = FALSE)
  }

  # Mirrors process_trade_data(): group by (year, exporter) and let total_trade
  # be the sum of that exporter's OUTWARD flows over all partners. Self-trade is
  # already excluded upstream by get_trade_data_goods()/get_trade_data().
  annual <- trade_long |>
    dplyr::filter(year %in% c(pre_years, post_years)) |>
    dplyr::group_by(year, iso3c = exporter_iso3) |>
    dplyr::summarise(
      trade_with_china = sum(exports[importer_iso3 == china_iso3], na.rm = TRUE),
      total_trade = sum(exports, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      china_export_share = trade_with_china / total_trade,
      period = dplyr::if_else(year %in% pre_years, "pre", "post")
    )

  undefined <- annual |> dplyr::filter(is.na(china_export_share))

  # An exporter whose total exports are negative would produce a share outside
  # [0, 1] and a meaningless mean. ITPD-E flows are non-negative, so this is a
  # data-integrity gate rather than an expected branch.
  if (any(annual$total_trade < 0, na.rm = TRUE)) {
    stop("brazil_sdid_dose_placebo_period_dose: negative total exports on the ",
         basis_label, " basis; the export share is not interpretable.",
         call. = FALSE)
  }

  # mean(..., na.rm = TRUE) is the inherited rule (see header): undefined years
  # are dropped, not zero-filled. n_years_defined records how many years each
  # period mean actually averaged, so a partial window is visible instead of
  # being hidden behind a well-formed number.
  dose <- annual |>
    dplyr::group_by(iso3c, period) |>
    dplyr::summarise(
      mean_share = mean(china_export_share, na.rm = TRUE),
      n_years_defined = sum(!is.na(china_export_share)),
      .groups = "drop"
    ) |>
    tidyr::pivot_wider(
      names_from = period,
      values_from = c(mean_share, n_years_defined)
    ) |>
    dplyr::mutate(
      # An exporter absent from a whole period yields NA from pivot_wider, an
      # exporter present but degenerate throughout yields NaN from mean() on an
      # empty vector. Both mean "no dose"; is.na() covers both, and the counts
      # are coalesced to 0 so "no observed year" is not confused with missing.
      dose_pre_share = dplyr::if_else(is.nan(mean_share_pre), NA_real_, mean_share_pre),
      dose_post_share = dplyr::if_else(is.nan(mean_share_post), NA_real_, mean_share_post),
      n_years_defined_pre = dplyr::coalesce(as.integer(n_years_defined_pre), 0L),
      n_years_defined_post = dplyr::coalesce(as.integer(n_years_defined_post), 0L),
      dose_delta_share = dose_post_share - dose_pre_share
    ) |>
    dplyr::select(
      iso3c, dose_pre_share, dose_post_share, dose_delta_share,
      n_years_defined_pre, n_years_defined_post
    ) |>
    dplyr::arrange(iso3c)

  coverage <- tibble::tibble(
    basis = basis_label,
    pre_window = paste0(min(pre_years), "-", max(pre_years)),
    post_window = paste0(min(post_years), "-", max(post_years)),
    n_pre_years = length(pre_years),
    n_post_years = length(post_years),
    n_exporters = nrow(dose),
    n_country_years = nrow(annual),
    n_country_years_undefined_share = nrow(undefined),
    undefined_share_iso3c = paste(sort(unique(undefined$iso3c)), collapse = ";")
  )

  list(dose = dose, coverage = coverage)
}


# Tests the goods dose implementation by running it on the ALL-SECTOR data and
# requiring it to reproduce the stored donor_china_exposure.csv period means.
#
# This is the proof obligation that replaces a prose claim: the header asserts
# that the goods dose replicates the all-sector definition property for
# property, and this gate makes the assertion falsifiable at every build. If
# brazil_sdid_donor_china_exposure() ever changes its windows, its denominator
# or its mean-of-annual-shares rule, or if this file's replication is wrong, the
# build stops here rather than shipping two doses computed under different
# rules and calling the comparison a robustness check.
#
# Tolerance is 1e-12 rather than bit equality: the reference values arrive
# through a CSV round trip and a different summation order, so a few ULP of
# drift is expected and harmless, while any genuine definitional difference is
# many orders of magnitude larger. The observed maxima on the shipped data are
# ~1e-17.
brazil_sdid_dose_placebo_verify_dose_definition <- function(trade_all_sector,
                                                            exposure_path,
                                                            pre_years = 1997:2008,
                                                            post_years = 2009:2015,
                                                            tolerance = 1e-12) {
  reference <- readr::read_csv(
    exposure_path,
    col_types = readr::cols(
      iso3c = readr::col_character(),
      mean_china_export_share_pre_treatment = readr::col_double(),
      mean_china_export_share_post_treatment = readr::col_double(),
      .default = readr::col_guess()
    )
  ) |>
    dplyr::select(
      iso3c,
      reference_pre = mean_china_export_share_pre_treatment,
      reference_post = mean_china_export_share_post_treatment
    )

  replicated <- brazil_sdid_dose_placebo_period_dose(
    trade_all_sector,
    basis_label = "all-sector",
    pre_years = pre_years,
    post_years = post_years
  )$dose

  compared <- reference |>
    dplyr::left_join(replicated, by = "iso3c")

  absent <- compared$iso3c[is.na(compared$dose_pre_share) &
                             !is.na(compared$reference_pre)]
  if (length(absent) > 0L) {
    stop("brazil_sdid_dose_placebo_verify_dose_definition: the replicated ",
         "all-sector dose is missing for unit(s) present in ", exposure_path,
         ": ", paste(sort(absent), collapse = ", "),
         ". The replication does not cover the reference sample.",
         call. = FALSE)
  }

  max_abs_pre <- max(abs(compared$reference_pre - compared$dose_pre_share))
  max_abs_post <- max(abs(compared$reference_post - compared$dose_post_share))

  if (!(max_abs_pre <= tolerance && max_abs_post <= tolerance)) {
    stop("brazil_sdid_dose_placebo_verify_dose_definition: the dose definition ",
         "replicated here does not reproduce ", exposure_path,
         " on the all-sector data (max absolute discrepancy pre ",
         format(max_abs_pre), ", post ", format(max_abs_post),
         ", tolerance ", format(tolerance),
         "). The goods dose would therefore be computed under a different rule ",
         "from the all-sector dose it is compared with.", call. = FALSE)
  }

  tibble::tibble(
    reference_file = basename(exposure_path),
    n_units_compared = nrow(compared),
    max_abs_pre_discrepancy = max_abs_pre,
    max_abs_post_discrepancy = max_abs_post,
    tolerance = tolerance
  )
}


# The donor pool the rank-1 checks screen, read from the exposure file.
#
# It is a separate target rather than being taken from the analysis dataset
# because the dataset consumes the rank-1 checks, and reading the donor list off
# the dataset would make the graph circular. The dataset asserts in turn that
# the set screened here has the same size as the set it actually analyses, so
# the two cannot silently diverge and leave a vacuous check in the record.
#
# The function is deliberately NOT named after the target it feeds: a target
# whose command calls a function of its own name is read by targets as
# depending on itself.
brazil_sdid_dose_placebo_screened_donors <- function(exposure_path) {
  exposure <- readr::read_csv(
    exposure_path,
    col_types = readr::cols(iso3c = readr::col_character(),
                            .default = readr::col_guess())
  )
  if (anyNA(exposure$iso3c) || any(exposure$iso3c == "")) {
    stop("brazil_sdid_dose_placebo_screened_donors: ", exposure_path,
         " contains a missing or empty iso3c, so the screened donor pool ",
         "would be ill-defined.", call. = FALSE)
  }
  sort(unique(exposure$iso3c))
}


# Recomputes, from a ranked trade table, which donors ever sat at China rank 1
# and when -- so the truncation claim is generated from the data instead of
# being retyped as prose that can go stale.
#
# `abort_if_any_in_window = TRUE` is used for the GOODS basis, where a donor at
# rank 1 inside the estimation window would mean a treated unit had survived the
# screen into the donor pool: that invalidates the diagnostic's premise and must
# stop the build. It is FALSE for the ALL-SECTOR basis, where Singapore at rank
# 1 in 2013-2014 is a known and expected fact -- the very fact the truncation
# note exists to disclose.
#
# The out-of-window facts are recorded rather than gated. They are true and they
# matter: a claim of "no donor ever reached rank 1" would be false over
# 1990-2022 on either basis, which is exactly why every such statement this file
# ships carries its time scope.
brazil_sdid_dose_placebo_rank_one_check <- function(ranked,
                                                    donor_iso3c,
                                                    basis_label,
                                                    window_start = 1997,
                                                    window_end = 2015,
                                                    abort_if_any_in_window = FALSE) {
  required_columns <- c("year", "iso3c", "rank_from_i")
  missing_columns <- setdiff(required_columns, names(ranked))
  if (length(missing_columns) > 0L) {
    stop("brazil_sdid_dose_placebo_rank_one_check: the ", basis_label,
         " ranked table is missing required column(s): ",
         paste(missing_columns, collapse = ", "), ".", call. = FALSE)
  }

  rank_one <- ranked |>
    dplyr::filter(iso3c %in% donor_iso3c, rank_from_i == 1) |>
    dplyr::select(iso3c, year) |>
    dplyr::arrange(iso3c, year)

  in_window <- rank_one |>
    dplyr::filter(year >= window_start, year <= window_end)

  collapse_donor_years <- function(x) {
    if (nrow(x) == 0L) return("")
    x |>
      dplyr::group_by(iso3c) |>
      dplyr::summarise(entry = paste0(iso3c[1], ":",
                                      paste(year, collapse = ",")),
                       .groups = "drop") |>
      dplyr::arrange(iso3c) |>
      dplyr::pull(entry) |>
      paste(collapse = ";")
  }

  if (abort_if_any_in_window && nrow(in_window) > 0L) {
    stop("brazil_sdid_dose_placebo_rank_one_check: donor(s) reach China rank 1 ",
         "on the ", basis_label, " basis inside ", window_start, "-", window_end,
         " (", collapse_donor_years(in_window),
         "). The donor pool is supposed to be untreated on the basis that ",
         "defines treatment, so the diagnostic's premise -- dose without the ",
         "crown -- no longer holds.", call. = FALSE)
  }

  tibble::tibble(
    basis = basis_label,
    window = paste0(window_start, "-", window_end),
    n_donors_screened = length(donor_iso3c),
    n_donor_years_rank_one_in_window = nrow(in_window),
    donors_rank_one_in_window = paste(sort(unique(in_window$iso3c)),
                                      collapse = ";"),
    donor_years_rank_one_in_window = collapse_donor_years(in_window),
    n_donor_years_rank_one_any_year = nrow(rank_one),
    donors_rank_one_any_year = paste(sort(unique(rank_one$iso3c)),
                                     collapse = ";"),
    donor_years_rank_one_any_year = collapse_donor_years(rank_one),
    full_span = paste0(min(ranked$year), "-", max(ranked$year))
  )
}


# Single source of truth for the arm structure. Every consumer -- the results
# builder, the summary row, the rank table and the figure -- reads its labels,
# column names and prose from here, so an arm cannot be described one way in the
# CSV and another way in the figure.
brazil_sdid_dose_placebo_arms <- function() {
  list(
    primary_goods = list(
      arm = "primary_goods",
      role = "PRIMARY",
      basis = "goods-only",
      dose_columns = c(delta_share = "goods_dose_delta_share",
                       post_share = "goods_dose_post_share"),
      dose_labels = c(
        delta_share = "change in the goods-only China export share, post minus pre",
        post_share = "post-period mean goods-only China export share"
      ),
      axis_labels = c(
        delta_share = paste0("Change in goods-only export share to China, ",
                             "2009-2015 mean minus 1997-2008 mean (percentage points)"),
        post_share = paste0("Post-period mean goods-only export share to China, ",
                            "2009-2015 (percentage points)")
      ),
      subtitle = paste0("PRIMARY ARM - dose measured on goods only, the same ",
                        "sector definition that assigns treatment"),
      caption_basis = paste0(
        "The dose is a GOODS-ONLY export share (ITPD-E Agriculture, Mining and ",
        "Energy, and Manufacturing), the same sector definition used to assign ",
        "treatment and to screen the donor pool."
      )
    ),
    robustness_all_sector = list(
      arm = "robustness_all_sector",
      role = "ROBUSTNESS",
      basis = "all-sector",
      dose_columns = c(delta_share = "all_sector_dose_delta_share",
                       post_share = "all_sector_dose_post_share"),
      dose_labels = c(
        delta_share = "change in the all-sector China export share, post minus pre",
        post_share = "post-period mean all-sector China export share"
      ),
      axis_labels = c(
        delta_share = paste0("Change in all-sector export share to China, ",
                             "2009-2015 mean minus 1997-2008 mean (percentage points)"),
        post_share = paste0("Post-period mean all-sector export share to China, ",
                            "2009-2015 (percentage points)")
      ),
      subtitle = paste0("ROBUSTNESS ARM - dose measured on all sectors (goods ",
                        "and services), while treatment is assigned on goods"),
      caption_basis = paste0(
        "The dose is an ALL-SECTOR export share (goods and services); treatment ",
        "and the donor screen are defined on goods only, so this arm ",
        "deliberately mixes two sector definitions to test whether the ",
        "measurement basis matters."
      )
    )
  )
}


# Reads the stored placebo distribution and the donor exposure table, attaches
# BOTH dose bases to each donor, and returns the analysis dataset plus the
# provenance checks that the reviewer needs in order to trust it.
#
# The treated unit is returned separately and deliberately carries NO dose on
# either arm; see "THE TREATED UNIT HAS NO DOSE COORDINATE" in the header for
# the reasoning and for the alternatives discarded.
build_brazil_sdid_dose_placebo_dataset <- function(placebo_path,
                                                   exposure_path,
                                                   goods_dose,
                                                   definition_check,
                                                   goods_rank_one_check,
                                                   all_sector_rank_one_check,
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

  # Recompute the all-sector dose from its two components rather than trusting
  # the stored difference, then confirm the stored column agrees. A silent
  # disagreement would mean the exposure file and its own inputs had drifted
  # apart.
  exposure_dose <- exposure |>
    dplyr::mutate(
      all_sector_dose_pre_share = mean_china_export_share_pre_treatment,
      all_sector_dose_post_share = mean_china_export_share_post_treatment,
      all_sector_dose_delta_share = mean_china_export_share_post_treatment -
        mean_china_export_share_pre_treatment
    )

  max_abs_delta_discrepancy <- max(abs(
    exposure_dose$all_sector_dose_delta_share -
      exposure_dose$delta_mean_china_export_share_post_minus_pre
  ))
  if (!isTRUE(all.equal(
    exposure_dose$all_sector_dose_delta_share,
    exposure_dose$delta_mean_china_export_share_post_minus_pre,
    tolerance = 1e-12
  ))) {
    stop("build_brazil_sdid_dose_placebo_dataset: the recomputed post-minus-pre ",
         "dose disagrees with delta_mean_china_export_share_post_minus_pre ",
         "(max absolute discrepancy ", format(max_abs_delta_discrepancy),
         "); the exposure file is internally inconsistent.", call. = FALSE)
  }

  # Both joins below are left_joins on iso3c, so a duplicated key on either
  # right-hand side would silently MULTIPLY donor rows: the OLS N would inflate,
  # the quartile cutoff would move, and the high-dose subgroup could change, with
  # nothing failing. Assert both keys are unique instead of trusting the inputs.
  assert_unique_key <- function(iso3c, source_label) {
    duplicated_iso3c <- unique(iso3c[duplicated(iso3c)])
    if (length(duplicated_iso3c) > 0L) {
      stop("build_brazil_sdid_dose_placebo_dataset: iso3c is not unique in ",
           source_label, ", so the donor join would duplicate rows and change ",
           "the OLS sample, the quartile cutoff and the high-dose subgroup ",
           "without any error. Duplicated iso3c: ",
           paste(sort(duplicated_iso3c), collapse = ", "), ".", call. = FALSE)
    }
    invisible(TRUE)
  }
  assert_unique_key(exposure$iso3c, exposure_path)
  assert_unique_key(goods_dose$dose$iso3c, "the goods period-dose table")

  goods_columns <- goods_dose$dose |>
    dplyr::select(
      iso3c,
      goods_dose_pre_share = dose_pre_share,
      goods_dose_post_share = dose_post_share,
      goods_dose_delta_share = dose_delta_share,
      goods_n_years_defined_pre = n_years_defined_pre,
      goods_n_years_defined_post = n_years_defined_post
    )

  donors <- donor_estimates |>
    dplyr::left_join(
      exposure_dose |>
        dplyr::select(
          iso3c, country_name, region, unit_weight,
          all_sector_dose_pre_share, all_sector_dose_post_share,
          all_sector_dose_delta_share,
          min_china_rank_post_treatment, china_exposure_flag
        ),
      by = "iso3c"
    ) |>
    dplyr::left_join(goods_columns, by = "iso3c") |>
    dplyr::arrange(iso3c)

  # The treated unit must not acquire a dose through either join. Brazil is
  # absent from the exposure file by construction but IS present in the goods
  # trade data, so this is a live guard on the goods arm rather than a formality.
  if (treated_iso3c %in% donors$iso3c) {
    stop("build_brazil_sdid_dose_placebo_dataset: the treated unit ",
         treated_iso3c, " appears among the donors, so it would receive a dose ",
         "coordinate and enter the OLS and the quartile cutoff.", call. = FALSE)
  }

  # The rank-1 checks screen a donor pool read straight from the exposure file.
  # If that pool were not the pool actually analysed here, the checks would be
  # true statements about the wrong set of countries and the truncation note
  # built from them would be vacuous.
  for (check in list(goods_rank_one_check, all_sector_rank_one_check)) {
    if (!identical(as.integer(check$n_donors_screened), nrow(donors))) {
      stop("build_brazil_sdid_dose_placebo_dataset: the ", check$basis,
           " rank-1 check screened ", check$n_donors_screened,
           " donors but the analysis uses ", nrow(donors),
           ". The truncation claim would describe a different donor pool from ",
           "the one the diagnostic analyses.", call. = FALSE)
    }
  }

  arms <- brazil_sdid_dose_placebo_arms()

  # Per dose definition and per arm, NOT pooled across dose definitions. The
  # pooled count is ambiguous by construction: a donor with a missing pre-share
  # but a valid post-share has an NA delta and a valid level, so a single N
  # would match one OLS sample and not the other while looking authoritative.
  # Each N shipped here is the exact sample of exactly one OLS fit, and
  # compute_brazil_sdid_dose_placebo_results() asserts the two agree.
  dose_counts <- list()
  for (arm in arms) {
    for (definition in names(arm$dose_columns)) {
      column <- arm$dose_columns[[definition]]
      observed <- !is.na(donors[[column]])
      key <- paste0(arm$arm, "_", definition)
      dose_counts[[key]] <- list(
        n_with_dose = sum(observed),
        n_missing_dose = sum(!observed),
        missing_iso3c = paste(donors$iso3c[!observed], collapse = ";")
      )
    }
  }

  checks <- tibble::tibble(
    n_placebo_rows = nrow(placebo),
    n_placebo_not_estimated = sum(placebo$status != "estimated" | is.na(placebo$estimate)),
    n_valid_assignments = nrow(valid),
    n_donors = nrow(donor_estimates),
    n_exposure_rows = nrow(exposure),
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
    checks = checks,
    dose_counts = dose_counts,
    goods_coverage = goods_dose$coverage,
    definition_check = definition_check,
    goods_rank_one_check = goods_rank_one_check,
    all_sector_rank_one_check = all_sector_rank_one_check
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
# NO standard error and NO p-value are returned, on either arm. Donor
# pseudo-ATTs share overlapping donor pools, so OLS sampling theory does not
# apply to this slope; reporting an SE would dress a correlated-error artefact
# as a formal test. The slope is reported in two scalings -- per unit of export
# share and per percentage point -- so that the figure's annotation (percentage
# points) and the native-unit data cannot be confused for one another.
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


# Correlation between the two dose bases across donors, for one dose definition.
#
# This is the quantity that says how far the goods and all-sector measurements
# actually diverge, and therefore how much the robustness arm can possibly add.
# Both Pearson (level agreement) and Spearman (ordering agreement) are reported:
# the subgroup is defined by a quantile cutoff, so it is the ORDERING, not the
# levels, that determines which donors enter the rank test.
brazil_sdid_dose_placebo_basis_correlation <- function(donors,
                                                       goods_column,
                                                       all_sector_column,
                                                       dose_definition) {
  paired <- donors |>
    dplyr::filter(!is.na(.data[[goods_column]]),
                  !is.na(.data[[all_sector_column]]))
  goods <- paired[[goods_column]]
  all_sector <- paired[[all_sector_column]]

  tibble::tibble(
    dose_definition = dose_definition,
    n_donors_both_bases = nrow(paired),
    pearson = stats::cor(goods, all_sector, method = "pearson"),
    spearman = stats::cor(goods, all_sector, method = "spearman")
  )
}


# Assembles every quantity the diagnostic reports, for BOTH arms: the two dose
# definitions on each basis, the descriptive associations, the quartile cutoffs,
# the cross-basis dose correlations, and the rank tests on the full pool
# (self-test) and on each high-dose subgroup.
compute_brazil_sdid_dose_placebo_results <- function(dataset,
                                                     cutoff_prob = 0.75,
                                                     treated_iso3c = "BRA",
                                                     focus_iso3c = "SGP") {
  donors <- dataset$donors
  distribution <- dataset$placebo
  arms <- brazil_sdid_dose_placebo_arms()

  # The rule the CSVs ship so that a reader of comparison_set alone can tell why
  # Brazil is in every subgroup. See the header for the reasoning.
  treated_unit_dose_rule <- paste0(
    "The treated unit (", treated_iso3c, ") has NO dose coordinate on either ",
    "arm and is added to every high-dose subgroup UNCONDITIONALLY, not by ",
    "clearing the cutoff. It is absent from donor_china_exposure.csv by ",
    "construction, so the all-sector arm cannot supply a dose for it; the ",
    "goods arm could, and deliberately does not, so that the two arms treat ",
    "the treated unit identically and the subgroup membership of the treated ",
    "unit never depends on the exposure quantity under test. Brazil never ",
    "enters the OLS fit, the quartile cutoff or the dose correlations."
  )

  high_dose <- list()
  associations <- list()
  ranks <- list()

  # Self-test: with keep_units = NULL this must reproduce the stored
  # "All valid assignments" row of rank_inference.csv exactly (3 / 7 / 96). It
  # is arm-agnostic because it uses no dose at all, which is precisely why it is
  # a valid check that the extension has not perturbed the rank machinery.
  ranks[[1L]] <- brazil_sdid_dose_placebo_rank_inference(
    distribution,
    comparison_set = "All valid assignments (self-test vs rank_inference.csv)",
    keep_units = NULL,
    treated_iso3c = treated_iso3c
  ) |>
    dplyr::mutate(
      analysis_arm = "self_test",
      dose_definition = "none",
      dose_cutoff = NA_real_,
      .before = 1
    )

  for (arm in arms) {
    for (definition in names(arm$dose_columns)) {
      column <- arm$dose_columns[[definition]]
      key <- paste0(arm$arm, "_", definition)

      high_dose[[key]] <- brazil_sdid_dose_placebo_high_dose(
        donors, column, cutoff_prob
      )

      association <- brazil_sdid_dose_placebo_association(donors, column) |>
        dplyr::mutate(analysis_arm = arm$arm, dose_definition = definition,
                      .before = 1)

      # Closes the ambiguity the pooled donor count used to leave open: the N
      # shipped for this arm-and-definition is asserted to be the N the OLS
      # actually fitted, so the two can never disagree in a shipped file.
      expected_n <- dataset$dose_counts[[key]]$n_with_dose
      if (!identical(as.integer(association$n_donors), as.integer(expected_n))) {
        stop("compute_brazil_sdid_dose_placebo_results: the OLS sample for ",
             key, " has ", association$n_donors, " donors but the shipped ",
             "donor count for that dose column is ", expected_n,
             ". The reported N would not describe the reported fit.",
             call. = FALSE)
      }
      associations[[key]] <- association

      keep <- c(treated_iso3c, high_dose[[key]]$iso3c)
      ranks[[length(ranks) + 1L]] <- brazil_sdid_dose_placebo_rank_inference(
        distribution,
        comparison_set = paste0(
          arm$role, " (", arm$basis, " dose): Brazil plus top-quartile donors ",
          "by ", arm$dose_labels[[definition]]
        ),
        keep_units = keep,
        treated_iso3c = treated_iso3c
      ) |>
        dplyr::mutate(
          analysis_arm = arm$arm,
          dose_definition = definition,
          dose_cutoff = high_dose[[key]]$cutoff,
          .before = 1
        )
    }
  }

  associations <- dplyr::bind_rows(associations)
  ranks <- dplyr::bind_rows(ranks) |>
    dplyr::mutate(treated_unit_dose_rule = treated_unit_dose_rule)

  basis_correlations <- dplyr::bind_rows(lapply(
    names(arms$primary_goods$dose_columns),
    function(definition) {
      brazil_sdid_dose_placebo_basis_correlation(
        donors,
        goods_column = arms$primary_goods$dose_columns[[definition]],
        all_sector_column = arms$robustness_all_sector$dose_columns[[definition]],
        dose_definition = definition
      )
    }
  ))

  # Singapore is singled out because it is the ONE donor on which the two sector
  # bases disagree about the crown (all-sector rank 1 in 2013-2014, never better
  # than goods rank 2 over 1997-2015). Where it falls on the goods dose is
  # therefore the sharpest single test of whether moving to the goods basis
  # changed the composition of the high-dose comparison set.
  focus <- brazil_sdid_dose_placebo_focus_donor(
    donors, high_dose, arms, focus_iso3c
  )

  list(
    donors = donors,
    treated = dataset$treated,
    checks = dataset$checks,
    dose_counts = dataset$dose_counts,
    goods_coverage = dataset$goods_coverage,
    definition_check = dataset$definition_check,
    goods_rank_one_check = dataset$goods_rank_one_check,
    all_sector_rank_one_check = dataset$all_sector_rank_one_check,
    associations = associations,
    ranks = ranks,
    basis_correlations = basis_correlations,
    high_dose = high_dose,
    focus = focus,
    cutoff_prob = cutoff_prob,
    treated_unit_dose_rule = treated_unit_dose_rule,
    arms = arms
  )
}


# Where one named donor sits in the goods dose distribution, and whether it is
# inside each arm's high-dose subgroup. Written as a function of an arbitrary
# iso3c rather than hard-coded to Singapore so the position is reconstructible
# for any donor a later reviewer asks about, but Singapore is the default for
# the reason given at the call site.
#
# The rank is descending (1 = largest dose) with ties.method = "min", and the
# percentile is the share of donors at or below this donor's dose, so the two
# read consistently: rank 14 of 95 pairs with a percentile near 0.86.
brazil_sdid_dose_placebo_focus_donor <- function(donors, high_dose, arms,
                                                 focus_iso3c) {
  row <- donors |> dplyr::filter(iso3c == focus_iso3c)
  if (nrow(row) != 1L) {
    stop("brazil_sdid_dose_placebo_focus_donor: donor ", focus_iso3c,
         " must appear exactly once among the donors; found ", nrow(row), ".",
         call. = FALSE)
  }

  out <- list(iso3c = focus_iso3c, country_name = row$country_name)
  for (arm in arms) {
    for (definition in names(arm$dose_columns)) {
      column <- arm$dose_columns[[definition]]
      key <- paste0(arm$arm, "_", definition)
      dose <- donors[[column]]
      value <- row[[column]]
      out[[key]] <- list(
        dose = value,
        rank_descending = as.integer(rank(-dose, ties.method = "min",
                                          na.last = "keep")[donors$iso3c == focus_iso3c]),
        n_donors_with_dose = sum(!is.na(dose)),
        percentile = mean(dose <= value, na.rm = TRUE),
        in_high_dose_subgroup = focus_iso3c %in% high_dose[[key]]$iso3c
      )
    }
  }
  out
}


# Wide one-row summary: every number the diagnostic produces, at full precision,
# for BOTH arms side by side.
#
# Column naming is a single rule -- <arm>_<dose_definition>_<quantity> -- so an
# arm can never be inferred wrongly from a column name. Arm-agnostic quantities
# (Brazil's ATT, the self-test, the cross-basis correlations, the coverage and
# rank-1 records) carry no arm prefix and are grouped separately below.
#
# Alternative discarded: reshaping this into a long, one-row-per-arm table,
# which would make the arm structurally unmistakable. Rejected because the long
# per-arm view already exists in dose_response_rank_inference.csv (which carries
# analysis_arm) and in dose_response_donor_doses.csv, while this file's job is
# to be the single machine-readable record of every scalar the diagnostic
# produces -- a job the phase-1 wide shape does well and which reshaping would
# split across rows with a ragged set of applicable columns.
#
# No slope standard error or p-value appears here, on either arm, by design.
brazil_sdid_dose_placebo_summary_row <- function(results) {
  assoc <- results$associations
  ranks <- results$ranks
  checks <- results$checks
  coverage <- results$goods_coverage
  arms <- results$arms

  pick_assoc <- function(arm, definition, column) {
    assoc[[column]][assoc$analysis_arm == arm & assoc$dose_definition == definition]
  }
  pick_rank <- function(arm, definition, column) {
    ranks[[column]][ranks$analysis_arm == arm & ranks$dose_definition == definition]
  }
  pick_basis <- function(definition, column) {
    results$basis_correlations[[column]][
      results$basis_correlations$dose_definition == definition
    ]
  }

  out <- list(
    treated_iso3c = checks$treated_iso3c,
    brazil_estimate = checks$treated_estimate,
    n_valid_assignments = checks$n_valid_assignments,
    n_donors = checks$n_donors,
    n_exposure_rows = checks$n_exposure_rows,
    exposure_rows_without_placebo = checks$exposure_rows_without_placebo
  )

  # Arm-major, dose-minor, so the two arms read as two adjacent blocks with
  # identical internal layout and can be diffed column by column.
  for (arm in arms) {
    for (definition in names(arm$dose_columns)) {
      key <- paste0(arm$arm, "_", definition)
      prefix <- paste0(key, "_")
      counts <- results$dose_counts[[key]]
      block <- list(
        n_donors_with_dose = counts$n_with_dose,
        n_donors_missing_dose = counts$n_missing_dose,
        missing_dose_iso3c = counts$missing_iso3c,
        ols_n_donors = pick_assoc(arm$arm, definition, "n_donors"),
        ols_slope_per_unit_share = pick_assoc(arm$arm, definition, "ols_slope_per_unit_share"),
        ols_slope_per_percentage_point = pick_assoc(arm$arm, definition, "ols_slope_per_percentage_point"),
        ols_intercept = pick_assoc(arm$arm, definition, "ols_intercept"),
        pearson_correlation = pick_assoc(arm$arm, definition, "pearson_correlation"),
        spearman_correlation = pick_assoc(arm$arm, definition, "spearman_correlation"),
        quartile_cutoff = results$high_dose[[key]]$cutoff,
        n_high_dose_donors = length(results$high_dose[[key]]$iso3c),
        high_dose_donor_iso3c = paste(sort(results$high_dose[[key]]$iso3c), collapse = ";"),
        rank_one_sided_negative = pick_rank(arm$arm, definition, "rank_one_sided_negative"),
        rank_two_sided_absolute = pick_rank(arm$arm, definition, "rank_two_sided_absolute"),
        denominator = pick_rank(arm$arm, definition, "denominator"),
        p_rank_one_sided_negative = pick_rank(arm$arm, definition, "p_rank_one_sided_negative"),
        p_rank_two_sided_absolute = pick_rank(arm$arm, definition, "p_rank_two_sided_absolute"),
        resolution_floor = pick_rank(arm$arm, definition, "resolution_floor")
      )
      names(block) <- paste0(prefix, names(block))
      out <- c(out, block)
    }
  }

  # How far the two measurement bases actually diverge across donors. This is
  # the number that says whether the robustness arm is a genuine alternative
  # measurement or a near-duplicate of the primary one.
  for (definition in c("delta_share", "post_share")) {
    block <- list(
      n_donors_both_bases = pick_basis(definition, "n_donors_both_bases"),
      pearson = pick_basis(definition, "pearson"),
      spearman = pick_basis(definition, "spearman")
    )
    names(block) <- paste0("dose_basis_goods_vs_all_sector_", definition, "_",
                           names(block))
    out <- c(out, block)
  }

  focus <- results$focus
  focus_block <- list(
    iso3c = focus$iso3c,
    country_name = focus$country_name,
    goods_dose_delta_share = focus$primary_goods_delta_share$dose,
    goods_dose_delta_share_rank_descending = focus$primary_goods_delta_share$rank_descending,
    goods_dose_delta_share_percentile = focus$primary_goods_delta_share$percentile,
    goods_delta_share_in_high_dose_subgroup = focus$primary_goods_delta_share$in_high_dose_subgroup,
    goods_dose_post_share = focus$primary_goods_post_share$dose,
    goods_dose_post_share_rank_descending = focus$primary_goods_post_share$rank_descending,
    goods_dose_post_share_percentile = focus$primary_goods_post_share$percentile,
    goods_post_share_in_high_dose_subgroup = focus$primary_goods_post_share$in_high_dose_subgroup,
    all_sector_delta_share_in_high_dose_subgroup = focus$robustness_all_sector_delta_share$in_high_dose_subgroup,
    all_sector_post_share_in_high_dose_subgroup = focus$robustness_all_sector_post_share$in_high_dose_subgroup
  )
  names(focus_block) <- paste0("focus_donor_", names(focus_block))
  out <- c(out, focus_block)

  # Self-test against the stored rank_inference.csv "All valid assignments" row.
  # Arm-agnostic: it uses no dose, so it must be identical across arms and
  # across phases, which is what makes it a check on the extension itself.
  out <- c(out, list(
    selftest_rank_one_sided_negative = pick_rank("self_test", "none", "rank_one_sided_negative"),
    selftest_rank_two_sided_absolute = pick_rank("self_test", "none", "rank_two_sided_absolute"),
    selftest_denominator = pick_rank("self_test", "none", "denominator")
  ))

  definition_check <- results$definition_check
  goods_rank_one <- results$goods_rank_one_check
  all_sector_rank_one <- results$all_sector_rank_one_check

  out <- c(out, list(
    quartile_cutoff_probability = results$cutoff_prob,
    quantile_type = 7L,
    high_dose_boundary_rule = "dose >= cutoff",

    primary_goods_pre_window = coverage$pre_window,
    primary_goods_post_window = coverage$post_window,
    primary_goods_n_exporters_with_dose = coverage$n_exporters,
    primary_goods_n_country_years = coverage$n_country_years,
    primary_goods_n_country_years_undefined_share = coverage$n_country_years_undefined_share,
    primary_goods_undefined_share_iso3c = coverage$undefined_share_iso3c,
    primary_goods_min_n_years_defined_pre = min(results$donors$goods_n_years_defined_pre),
    primary_goods_min_n_years_defined_post = min(results$donors$goods_n_years_defined_post),

    dose_definition_check_reference_file = definition_check$reference_file,
    dose_definition_check_n_units = definition_check$n_units_compared,
    dose_definition_check_max_abs_pre_discrepancy = definition_check$max_abs_pre_discrepancy,
    dose_definition_check_max_abs_post_discrepancy = definition_check$max_abs_post_discrepancy,
    dose_definition_check_tolerance = definition_check$tolerance,
    robustness_all_sector_max_abs_delta_discrepancy = checks$max_abs_delta_discrepancy,

    goods_rank_one_window = goods_rank_one$window,
    goods_rank_one_n_donor_years_in_window = goods_rank_one$n_donor_years_rank_one_in_window,
    goods_rank_one_donors_in_window = goods_rank_one$donors_rank_one_in_window,
    goods_rank_one_full_span = goods_rank_one$full_span,
    goods_rank_one_n_donor_years_any_year = goods_rank_one$n_donor_years_rank_one_any_year,
    goods_rank_one_donors_any_year = goods_rank_one$donors_rank_one_any_year,
    goods_rank_one_donor_years_any_year = goods_rank_one$donor_years_rank_one_any_year,

    all_sector_rank_one_window = all_sector_rank_one$window,
    all_sector_rank_one_n_donor_years_in_window = all_sector_rank_one$n_donor_years_rank_one_in_window,
    all_sector_rank_one_donor_years_in_window = all_sector_rank_one$donor_years_rank_one_in_window,
    all_sector_rank_one_full_span = all_sector_rank_one$full_span,
    all_sector_rank_one_n_donor_years_any_year = all_sector_rank_one$n_donor_years_rank_one_any_year,
    all_sector_rank_one_donors_any_year = all_sector_rank_one$donors_rank_one_any_year,
    all_sector_rank_one_donor_years_any_year = all_sector_rank_one$donor_years_rank_one_any_year,

    arm_structure_note = paste(
      "PRIMARY arm columns are prefixed primary_goods_*; ROBUSTNESS arm columns",
      "are prefixed robustness_all_sector_*. The primary dose is measured on",
      "GOODS ONLY -- the same sector definition (ITPD-E Agriculture, Mining and",
      "Energy, Manufacturing) that assigns treatment and screens the donor pool",
      "-- and supplies the figure and the headline subgroup rank tests. The",
      "robustness dose is measured on the ALL-SECTOR trade file (goods and",
      "services) and is retained as a measurement-robustness comparison, not",
      "discarded."
    ),
    dose_measurement_basis = paste(
      "On BOTH arms the ANNUAL share is exports to China divided by total",
      "exports to all partners, i.e. trade_with_china / total_trade, where",
      "total_trade is the sum of the country's exports across all partners and",
      "NOT a measure of two-way trade. Each period dose is the MEAN OF THE",
      "ANNUAL SHARES within the period, not a ratio of period totals; the two",
      "differ whenever total exports vary across years. Periods are",
      "pre-treatment 1997-2008 and post-treatment 2009-2015. The primary dose",
      "is computed inside the targets graph from trade_data_goods, the same",
      "object rank_trade() ranks to assign treatment; the robustness dose is",
      "read from donor_china_exposure.csv, built on the all-sector file. The",
      "two are computed by one shared function, and the build verifies that",
      "running it on the all-sector data reproduces donor_china_exposure.csv to",
      "the tolerance recorded above."
    ),
    degenerate_year_rule = paste(
      "A country-year whose total exports are zero has an undefined annual",
      "share (0/0). Such years are DROPPED from the period mean via",
      "na.rm = TRUE -- the same rule the all-sector exposure file applies --",
      "so a period dose is the mean over the years in which the share is",
      "defined, and the counts of averaged years are shipped in",
      "dose_response_donor_doses.csv. A unit with no defined year in a period",
      "has no dose for that period and is excluded from that dose definition's",
      "OLS, cutoff and subgroup. Alternative discarded: treating a zero-export",
      "year as a zero share, which would pull the mean toward zero for a",
      "country with nothing to average and would depart from the all-sector",
      "rule, making the two arms non-comparable."
    ),
    treated_unit_dose_rule = results$treated_unit_dose_rule,
    slope_inference_note = paste(
      "Slopes and correlations are descriptive only, on BOTH arms: donor",
      "pseudo-ATTs share overlapping donor pools, so their errors are",
      "correlated and no standard error or p-value for the slope is",
      "defensible. Only the rank p-values are inferential."
    ),
    # The sector qualifier below is not decoration, and every rank-1 claim in it
    # carries an explicit time scope because none of them holds over the full
    # 1990-2022 span of the trade data: over that span donors reach rank 1 on
    # BOTH bases. The donor lists and years spliced in here are recomputed from
    # the ranked trade tables at every build by
    # brazil_sdid_dose_placebo_rank_one_check(), so this sentence cannot go
    # stale relative to the data it describes.
    truncation_note = paste0(
      "Donors span dose without the rank-1 crown on the goods definition that ",
      "defines treatment: over ", goods_rank_one$window, " no donor-year sits ",
      "at goods rank 1 (", goods_rank_one$n_donor_years_rank_one_in_window,
      " donor-years found), so the diagnostic shows the presence or absence of ",
      "a dose gradient BELOW the threshold and does not identify the ",
      "discontinuity at the threshold. Every rank-1 statement here is ",
      "time-scoped because none survives the full span of the trade data (",
      goods_rank_one$full_span, "): over that span ",
      goods_rank_one$n_donor_years_rank_one_any_year,
      " donor-years reach goods rank 1 (", goods_rank_one$donors_rank_one_any_year,
      "), and ", all_sector_rank_one$n_donor_years_rank_one_any_year,
      " donor-years reach all-sector rank 1 (",
      all_sector_rank_one$donors_rank_one_any_year, "). The sector qualifier is ",
      "load-bearing over the estimation window too. On the all-sector basis ",
      "used by the robustness arm, exactly one donor reached rank 1 within ",
      all_sector_rank_one$window, ": ",
      all_sector_rank_one$donor_years_rank_one_in_window,
      " (China was Singapore's top all-sector export destination in those ",
      "years), and Singapore sits inside the high-dose subgroups recorded in ",
      "the focus_donor_* columns. The crownless span over the estimation ",
      "window is therefore a property of the goods definition alone."
    )
  ))

  tibble::as_tibble(out)
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
# for numbers that may reach the manuscript, so precision lost at the moment of
# writing must break the build rather than quietly degrade the record.
#
# WHAT THIS GUARD DOES AND DOES NOT COVER. It compares the in-memory column
# against the same column reparsed from the file just written, so it catches
# precision lost ON WRITE: a narrowed `digits` option, a formatting layer that
# truncates, a writer that emits fewer significant digits than a double needs.
# It does NOT catch rounding applied UPSTREAM. A round(x, 3) inserted in
# brazil_sdid_dose_placebo_summary_row() produces an already-rounded double that
# writes and reparses perfectly, so this check passes and the degraded number
# ships. Upstream rounding is prevented by the summary builder carrying raw
# values only, not by this function.
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
# rank_inference.csv plus the arm, the dose columns and the resolution floor.
#
# Every row carries analysis_arm and a comparison_set string that names the arm
# in words, so a reader who opens only this file can never mistake a robustness
# row for a primary one. treated_unit_dose_rule is repeated on every row for the
# same reason: it is the only place a reader of comparison_set learns that
# Brazil is in each subgroup by construction rather than by clearing the cutoff.
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
    dplyr::filter(analysis_arm == "self_test")

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
    dplyr::mutate(is_selftest_row = analysis_arm == "self_test")

  brazil_sdid_dose_placebo_write_csv(ranks_out, path)
}


# Per-donor table: the pseudo-ATT, both doses on both bases, the years each
# period mean averaged, and high-dose membership on all four arm-by-definition
# combinations.
#
# WHY THIS FILE EXISTS. Without it, two of the claims the summary makes are
# unfalsifiable from the shipped outputs alone: that Singapore sits inside the
# high-dose subgroups, and that the two sector bases order the donors almost
# identically. Neither the summary nor the rank table carries a per-donor dose,
# so a reader could only take those on trust. This file makes every cutoff,
# subgroup and correlation in the other two files reconstructible.
write_brazil_sdid_dose_placebo_donors <- function(results, path) {
  donors <- results$donors
  high_dose <- results$high_dose

  out <- donors |>
    dplyr::transmute(
      iso3c = iso3c,
      country_name = country_name,
      region = region,
      unit_weight = unit_weight,
      placebo_estimate = estimate,
      rmspe_pre = rmspe_pre,
      primary_goods_dose_pre_share = goods_dose_pre_share,
      primary_goods_dose_post_share = goods_dose_post_share,
      primary_goods_dose_delta_share = goods_dose_delta_share,
      primary_goods_n_years_defined_pre = goods_n_years_defined_pre,
      primary_goods_n_years_defined_post = goods_n_years_defined_post,
      robustness_all_sector_dose_pre_share = all_sector_dose_pre_share,
      robustness_all_sector_dose_post_share = all_sector_dose_post_share,
      robustness_all_sector_dose_delta_share = all_sector_dose_delta_share,
      all_sector_min_china_rank_post_treatment = min_china_rank_post_treatment,
      all_sector_china_exposure_flag = china_exposure_flag
    )

  for (key in names(high_dose)) {
    out[[paste0(key, "_in_high_dose_subgroup")]] <-
      out$iso3c %in% high_dose[[key]]$iso3c
  }

  out$treated_unit_dose_rule <- results$treated_unit_dose_rule

  brazil_sdid_dose_placebo_write_csv(out, path)
}


# Scatter of donor pseudo-ATT against exposure dose, for one arm.
#
# Brazil is drawn as a dashed HORIZONTAL line at its estimate and has NO dose
# coordinate on either arm (see the header for the decision and the alternatives
# discarded). The vertical DOTTED line marks the top-quartile cutoff, so the
# figure shows exactly which donors enter the high-dose rank test.
#
# The subtitle names the arm, and the axis label and caption both name the
# sector basis of the dose while the threshold statement is about GOODS. Two
# sector definitions are in play on the robustness arm, and a reader who sees
# only the figure must be able to tell which one produced the x axis, so the
# basis is carried in the figure text rather than left to the summary CSV.
plot_brazil_sdid_dose_placebo <- function(results,
                                          arm_key = "primary_goods",
                                          dose_key = "delta_share") {
  arm <- results$arms[[arm_key]]
  if (is.null(arm)) {
    stop("plot_brazil_sdid_dose_placebo: unknown arm '", arm_key, "'.",
         call. = FALSE)
  }
  dose_column <- arm$dose_columns[[dose_key]]
  if (is.null(dose_column) || is.na(dose_column)) {
    stop("plot_brazil_sdid_dose_placebo: unknown dose definition '", dose_key,
         "' for arm '", arm_key, "'.", call. = FALSE)
  }
  key <- paste0(arm_key, "_", dose_key)
  cutoff <- results$high_dose[[key]]$cutoff
  # Base subsetting rather than dplyr::filter(): the association table's columns
  # are themselves called `analysis_arm` and `dose_definition`, and masking them
  # against same-named local values is exactly the kind of shadowing that
  # silently returns every row.
  assoc <- results$associations[
    results$associations$analysis_arm == arm_key &
      results$associations$dose_definition == dose_key, ]

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

  # The caption is written as one unwrapped string and wrapped by strwrap() to a
  # fixed character width rather than carrying hand-placed newlines. Hand-placed
  # breaks have to be recounted every time a word changes, and the arm-specific
  # opening sentences differ in length, so the two arms would drift into
  # differently ragged blocks. strwrap() is deterministic, so the PNG stays
  # byte-reproducible. Width 155 is set below the ~166 characters that fit on
  # one line at size 7.5 in a 9-inch panel.
  caption_text <- paste0(
    "Each point is a donor given the 2009 pseudo-treatment. ",
    arm$caption_basis,
    " China never became any donor's top goods-export destination over ",
    "1997-2015, so the plot shows the dose gradient below the threshold rather ",
    "than the discontinuity at it. Brazil has no dose coordinate on either arm ",
    "and is added to the top-quartile rank test unconditionally. The dotted ",
    "line marks the top-quartile dose cutoff. The fitted line is descriptive ",
    "only: donor pools overlap, so no standard error is reported for the slope."
  )
  caption <- paste(strwrap(caption_text, width = 155), collapse = "\n")

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
      subtitle = arm$subtitle,
      x = arm$axis_labels[[dose_key]],
      y = "Placebo pseudo-ATT on UNGA ideal-point distance to China",
      caption = caption
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "top",
      plot.caption = ggplot2::element_text(hjust = 0, size = 7.5,
                                           colour = "grey30"),
      plot.subtitle = ggplot2::element_text(size = 9, colour = "grey20"),
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
                                                  arm_key = "primary_goods",
                                                  dose_key = "delta_share",
                                                  width = 9, height = 6.4,
                                                  dpi = 300) {
  ensure_brazil_sdid_dose_placebo_dir(path)
  ggplot2::ggsave(
    filename = path,
    plot = plot_brazil_sdid_dose_placebo(results, arm_key = arm_key,
                                         dose_key = dose_key),
    width = width,
    height = height,
    dpi = dpi,
    bg = "white"
  )
  path
}
