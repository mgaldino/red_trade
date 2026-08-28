#!/usr/bin/env Rscript

# Build the two-panel dose-response diagnostic used in paper_v4.Rmd.
#
# This script is intentionally downstream-only: it reads the validated CSV
# artifacts already stored in data/processed/diagnostics and does not touch the
# targets pipeline. It reconstructs the plotted statistics before exporting the
# figure so stale or internally inconsistent inputs fail loudly.

required_packages <- c("dplyr", "ggplot2", "readr", "scales", "tibble")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
]
if (length(missing_packages) > 0L) {
  stop(
    "Missing required R package(s): ",
    paste(missing_packages, collapse = ", "),
    ".",
    call. = FALSE
  )
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_argument) != 1L) {
  stop("Could not identify this script's path from commandArgs().", call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", script_argument), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)

input_dir <- file.path(
  repo_root,
  "data", "processed", "diagnostics", "brazil_sdid_dose_response_placebo"
)
donor_path <- file.path(input_dir, "dose_response_donor_doses.csv")
summary_path <- file.path(input_dir, "dose_response_summary.csv")
output_pdf <- file.path(repo_root, "images", "figure_brazil_sdid_dose_response_panel.pdf")
output_png <- file.path(repo_root, "images", "figure_brazil_sdid_dose_response_panel.png")

assert_true <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

assert_schema <- function(data, required_columns, object_name) {
  missing_columns <- setdiff(required_columns, names(data))
  assert_true(
    length(missing_columns) == 0L,
    paste0(
      object_name,
      " is missing required column(s): ",
      paste(missing_columns, collapse = ", "),
      "."
    )
  )
}

assert_finite_columns <- function(data, columns, object_name) {
  values <- data |>
    dplyr::select(dplyr::all_of(columns))
  nonnumeric <- names(values)[!vapply(values, is.numeric, logical(1))]
  assert_true(
    length(nonnumeric) == 0L,
    paste0(
      object_name,
      " has nonnumeric required column(s): ",
      paste(nonnumeric, collapse = ", "),
      "."
    )
  )
  nonfinite <- names(values)[
    !vapply(values, function(column) all(is.finite(column)), logical(1))
  ]
  assert_true(
    length(nonfinite) == 0L,
    paste0(
      object_name,
      " has missing or nonfinite values in: ",
      paste(nonfinite, collapse = ", "),
      "."
    )
  )
}

assert_close <- function(observed, expected, label, tolerance = 1e-12) {
  assert_true(
    length(observed) == 1L && length(expected) == 1L &&
      is.finite(observed) && is.finite(expected),
    paste0(label, " must compare two finite scalar values.")
  )
  difference <- abs(observed - expected)
  scale <- max(1, abs(observed), abs(expected))
  assert_true(
    difference <= tolerance * scale,
    paste0(
      label,
      " does not reproduce dose_response_summary.csv: observed ",
      format(observed, digits = 17),
      ", expected ",
      format(expected, digits = 17),
      "."
    )
  )
}

read_validated_csv <- function(path) {
  assert_true(file.exists(path), paste0("Validated input not found: ", path, "."))
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

donors <- read_validated_csv(donor_path)
summary_data <- read_validated_csv(summary_path)

donor_required <- c(
  "iso3c",
  "country_name",
  "placebo_estimate",
  "primary_goods_dose_delta_share",
  "robustness_all_sector_dose_delta_share",
  "primary_goods_delta_share_in_high_dose_subgroup",
  "robustness_all_sector_delta_share_in_high_dose_subgroup"
)
summary_required <- c(
  "treated_iso3c",
  "brazil_estimate",
  "n_valid_assignments",
  "n_donors",
  "quartile_cutoff_probability",
  "quantile_type",
  "high_dose_boundary_rule",
  "goods_rank_one_window",
  "goods_rank_one_n_donor_years_in_window"
)
arm_prefixes <- c(
  "primary_goods_delta_share",
  "robustness_all_sector_delta_share"
)
summary_stat_suffixes <- c(
  "n_donors_with_dose",
  "ols_n_donors",
  "ols_slope_per_unit_share",
  "ols_slope_per_percentage_point",
  "ols_intercept",
  "pearson_correlation",
  "spearman_correlation",
  "quartile_cutoff",
  "n_high_dose_donors",
  "high_dose_donor_iso3c",
  "rank_one_sided_negative",
  "rank_two_sided_absolute",
  "denominator"
)
summary_required <- c(
  summary_required,
  unlist(
    lapply(
      arm_prefixes,
      function(prefix) paste0(prefix, "_", summary_stat_suffixes)
    ),
    use.names = FALSE
  )
)

assert_schema(donors, donor_required, "dose_response_donor_doses.csv")
assert_schema(summary_data, summary_required, "dose_response_summary.csv")
assert_true(nrow(summary_data) == 1L, "dose_response_summary.csv must contain exactly one row.")
assert_true(nrow(donors) == 95L, "The donor file must contain exactly 95 rows.")
assert_true(
  !any(is.na(donors$iso3c) | donors$iso3c == ""),
  "Donor ISO3 keys must be nonmissing and nonblank."
)
assert_true(!anyDuplicated(donors$iso3c), "Donor ISO3 keys must be unique.")
assert_true(
  !any(is.na(donors$country_name) | donors$country_name == ""),
  "Donor country names must be nonmissing and nonblank."
)
assert_true(!("BRA" %in% donors$iso3c), "Brazil must not have a donor dose coordinate.")
assert_true(
  identical(summary_data$treated_iso3c[[1L]], "BRA"),
  "The summary treated-unit key must be BRA."
)
assert_true(summary_data$n_donors[[1L]] == 95L, "The summary must report 95 donors.")
assert_true(
  summary_data$n_valid_assignments[[1L]] == 96L,
  "The summary must report 96 valid assignments: Brazil plus 95 donors."
)
assert_true(
  summary_data$quartile_cutoff_probability[[1L]] == 0.75,
  "The stored high-dose cutoff probability must be 0.75."
)
assert_true(summary_data$quantile_type[[1L]] == 7L, "The stored quantile type must be 7.")
assert_true(
  identical(summary_data$high_dose_boundary_rule[[1L]], "dose >= cutoff"),
  "The stored high-dose boundary rule must be 'dose >= cutoff'."
)
assert_true(
  identical(summary_data$goods_rank_one_window[[1L]], "1997-2015") &&
    summary_data$goods_rank_one_n_donor_years_in_window[[1L]] == 0L,
  paste0(
    "The caption's below-threshold claim requires zero donor-years at goods rank one ",
    "during 1997-2015."
  )
)

assert_finite_columns(
  donors,
  c(
    "placebo_estimate",
    "primary_goods_dose_delta_share",
    "robustness_all_sector_dose_delta_share"
  ),
  "dose_response_donor_doses.csv"
)
flag_columns <- c(
  "primary_goods_delta_share_in_high_dose_subgroup",
  "robustness_all_sector_delta_share_in_high_dose_subgroup"
)
for (flag_column in flag_columns) {
  assert_true(
    is.logical(donors[[flag_column]]) && !any(is.na(donors[[flag_column]])),
    paste0(flag_column, " must be a complete logical column.")
  )
  assert_true(
    sum(donors[[flag_column]]) == 24L,
    paste0(flag_column, " must identify exactly 24 high-dose donors.")
  )
}

summary_numeric_columns <- c(
  "brazil_estimate",
  "n_valid_assignments",
  "n_donors",
  "quartile_cutoff_probability",
  "quantile_type",
  "goods_rank_one_n_donor_years_in_window",
  unlist(
    lapply(
      arm_prefixes,
      function(prefix) {
        paste0(
          prefix,
          "_",
          setdiff(summary_stat_suffixes, "high_dose_donor_iso3c")
        )
      }
    ),
    use.names = FALSE
  )
)
assert_finite_columns(summary_data, summary_numeric_columns, "dose_response_summary.csv")

brazil_estimate <- summary_data$brazil_estimate[[1L]]

arm_specs <- list(
  list(
    panel = "A. Goods trade",
    dose_column = "primary_goods_dose_delta_share",
    high_dose_column = "primary_goods_delta_share_in_high_dose_subgroup",
    summary_prefix = "primary_goods_delta_share"
  ),
  list(
    panel = "B. All-sector trade (goods and services)",
    dose_column = "robustness_all_sector_dose_delta_share",
    high_dose_column = "robustness_all_sector_delta_share_in_high_dose_subgroup",
    summary_prefix = "robustness_all_sector_delta_share"
  )
)

summary_value <- function(prefix, suffix) {
  column <- paste0(prefix, "_", suffix)
  summary_data[[column]][[1L]]
}

reconstruct_arm <- function(specification) {
  arm_data <- donors |>
    dplyr::select(
      iso3c,
      country_name,
      placebo_estimate,
      dplyr::all_of(specification$dose_column),
      dplyr::all_of(specification$high_dose_column)
    ) |>
    dplyr::transmute(
      iso3c = iso3c,
      country_name = country_name,
      placebo_estimate = placebo_estimate,
      dose_share = .data[[specification$dose_column]],
      high_dose = .data[[specification$high_dose_column]]
    )

  cutoff <- unname(stats::quantile(
    arm_data$dose_share,
    probs = 0.75,
    names = FALSE,
    type = 7
  ))
  reconstructed_high_dose <- arm_data$dose_share >= cutoff
  assert_true(
    identical(arm_data$high_dose, reconstructed_high_dose),
    paste0(specification$panel, " high-dose flags do not reproduce the type-7 cutoff.")
  )

  fit <- stats::lm(placebo_estimate ~ dose_share, data = arm_data)
  fit_coefficients <- stats::coef(fit)
  slope_per_unit_share <- unname(fit_coefficients[["dose_share"]])
  slope_per_percentage_point <- slope_per_unit_share / 100
  intercept <- unname(fit_coefficients[["(Intercept)"]])
  pearson <- stats::cor(
    arm_data$dose_share,
    arm_data$placebo_estimate,
    method = "pearson"
  )
  spearman <- stats::cor(
    arm_data$dose_share,
    arm_data$placebo_estimate,
    method = "spearman"
  )

  high_dose_data <- arm_data |>
    dplyr::filter(high_dose)
  rank_estimates <- c(brazil_estimate, high_dose_data$placebo_estimate)
  rank_one_sided_negative <- sum(rank_estimates <= brazil_estimate)
  rank_two_sided_absolute <- sum(abs(rank_estimates) >= abs(brazil_estimate))
  denominator <- length(rank_estimates)

  assert_close(
    slope_per_unit_share,
    summary_value(specification$summary_prefix, "ols_slope_per_unit_share"),
    paste0(specification$panel, " OLS slope per unit share")
  )
  assert_close(
    slope_per_percentage_point,
    summary_value(specification$summary_prefix, "ols_slope_per_percentage_point"),
    paste0(specification$panel, " OLS slope per percentage point")
  )
  assert_close(
    intercept,
    summary_value(specification$summary_prefix, "ols_intercept"),
    paste0(specification$panel, " OLS intercept")
  )
  assert_close(
    pearson,
    summary_value(specification$summary_prefix, "pearson_correlation"),
    paste0(specification$panel, " Pearson correlation")
  )
  assert_close(
    spearman,
    summary_value(specification$summary_prefix, "spearman_correlation"),
    paste0(specification$panel, " Spearman correlation")
  )
  assert_close(
    cutoff,
    summary_value(specification$summary_prefix, "quartile_cutoff"),
    paste0(specification$panel, " top-quartile cutoff")
  )

  expected_high_dose_iso3c <- strsplit(
    summary_value(specification$summary_prefix, "high_dose_donor_iso3c"),
    ";",
    fixed = TRUE
  )[[1L]]
  assert_true(
    identical(sort(high_dose_data$iso3c), sort(expected_high_dose_iso3c)),
    paste0(specification$panel, " high-dose donor keys do not reproduce the summary.")
  )
  assert_true(
    nrow(arm_data) == summary_value(specification$summary_prefix, "n_donors_with_dose") &&
      nrow(arm_data) == summary_value(specification$summary_prefix, "ols_n_donors"),
    paste0(specification$panel, " donor count does not reproduce the summary.")
  )
  assert_true(
    nrow(high_dose_data) == 24L &&
      nrow(high_dose_data) == summary_value(specification$summary_prefix, "n_high_dose_donors"),
    paste0(specification$panel, " high-dose donor count does not reproduce the summary.")
  )
  assert_true(
    rank_one_sided_negative ==
      summary_value(specification$summary_prefix, "rank_one_sided_negative") &&
      rank_two_sided_absolute ==
      summary_value(specification$summary_prefix, "rank_two_sided_absolute") &&
      denominator == summary_value(specification$summary_prefix, "denominator"),
    paste0(specification$panel, " Brazil rank does not reproduce the summary.")
  )
  assert_true(
    sum(high_dose_data$placebo_estimate > brazil_estimate) == 23L,
    paste0(specification$panel, " must place Brazil below 23 of 24 high-dose donors.")
  )

  plot_data <- arm_data |>
    dplyr::mutate(
      panel = specification$panel,
      dose_pp = dose_share * 100,
      dose_group = factor(
        dplyr::if_else(high_dose, "Top quartile", "Lower three quartiles"),
        levels = c("Lower three quartiles", "Top quartile")
      )
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      placebo_estimate,
      panel,
      dose_pp,
      dose_group
    )

  list(
    data = plot_data,
    statistics = tibble::tibble(
      panel = specification$panel,
      cutoff_pp = cutoff * 100,
      slope_per_percentage_point = slope_per_percentage_point,
      spearman = spearman
    )
  )
}

arm_results <- lapply(arm_specs, reconstruct_arm)
plot_data <- dplyr::bind_rows(lapply(arm_results, function(result) result$data))
panel_statistics <- dplyr::bind_rows(
  lapply(arm_results, function(result) result$statistics)
)
panel_levels <- vapply(arm_specs, function(specification) specification$panel, character(1))
plot_data <- plot_data |>
  dplyr::mutate(panel = factor(panel, levels = panel_levels))
panel_statistics <- panel_statistics |>
  dplyr::mutate(panel = factor(panel, levels = panel_levels))

x_range <- range(plot_data$dose_pp)
y_range <- range(plot_data$placebo_estimate)
x_span <- diff(x_range)
y_span <- diff(y_range)
panel_statistics <- panel_statistics |>
  dplyr::mutate(
    annotation_x = x_range[[1L]] + 0.025 * x_span,
    annotation_y = y_range[[1L]] + 0.025 * y_span,
    brazil_label_x = x_range[[2L]] - 0.025 * x_span,
    brazil_label_y = brazil_estimate,
    annotation = sprintf(
      "Donors: n = 95\nOLS slope: %.4f per pp\nSpearman: %.3f",
      slope_per_percentage_point,
      spearman
    ),
    brazil_label = sprintf("Brazil ATT = %.3f", brazil_estimate)
  )

dose_response_panel <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(x = dose_pp, y = placebo_estimate)
) +
  ggplot2::geom_hline(
    yintercept = brazil_estimate,
    linetype = "dashed",
    linewidth = 0.55,
    colour = "#D55E00"
  ) +
  ggplot2::geom_vline(
    data = panel_statistics,
    ggplot2::aes(xintercept = cutoff_pp),
    inherit.aes = FALSE,
    linetype = "dotted",
    linewidth = 0.5,
    colour = "grey35"
  ) +
  ggplot2::geom_smooth(
    method = "lm",
    formula = y ~ x,
    se = FALSE,
    linewidth = 0.6,
    colour = "black"
  ) +
  ggplot2::geom_point(
    ggplot2::aes(fill = dose_group),
    shape = 21,
    size = 2.15,
    stroke = 0.35,
    colour = "white",
    alpha = 0.9
  ) +
  ggplot2::geom_text(
    data = panel_statistics,
    ggplot2::aes(x = annotation_x, y = annotation_y, label = annotation),
    inherit.aes = FALSE,
    hjust = 0,
    vjust = 0,
    lineheight = 1.05,
    size = 2.75,
    colour = "grey20"
  ) +
  ggplot2::geom_text(
    data = panel_statistics,
    ggplot2::aes(x = brazil_label_x, y = brazil_label_y, label = brazil_label),
    inherit.aes = FALSE,
    hjust = 1,
    vjust = -0.55,
    size = 2.75,
    colour = "#D55E00"
  ) +
  ggplot2::facet_wrap(~panel, nrow = 1, scales = "fixed") +
  ggplot2::scale_fill_manual(
    values = c(
      "Lower three quartiles" = "#8FB1CF",
      "Top quartile" = "#1F4E79"
    ),
    name = NULL,
    drop = FALSE
  ) +
  ggplot2::scale_x_continuous(
    breaks = seq(-4, 12, by = 4),
    labels = scales::label_number(accuracy = 1),
    expand = ggplot2::expansion(mult = c(0.04, 0.04))
  ) +
  ggplot2::scale_y_continuous(
    breaks = seq(-0.6, 0.4, by = 0.2),
    labels = scales::label_number(accuracy = 0.1),
    expand = ggplot2::expansion(mult = c(0.05, 0.05))
  ) +
  ggplot2::labs(
    x = "Change in export share directed to China (percentage points)",
    y = "Placebo pseudo-ATT on UNGA ideal-point distance to China",
    fill = NULL
  ) +
  ggplot2::guides(
    fill = ggplot2::guide_legend(
      override.aes = list(size = 2.8, alpha = 1, colour = "white")
    )
  ) +
  ggplot2::theme_minimal(base_size = 10.5) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(colour = "grey90", linewidth = 0.35),
    strip.text = ggplot2::element_text(face = "bold", colour = "grey15", size = 10),
    strip.background = ggplot2::element_rect(fill = "grey96", colour = NA),
    legend.position = "top",
    legend.justification = "center",
    legend.margin = ggplot2::margin(t = 0, r = 0, b = 2, l = 0),
    axis.title = ggplot2::element_text(colour = "grey15"),
    axis.text = ggplot2::element_text(colour = "grey25"),
    panel.spacing.x = grid::unit(0.55, "lines"),
    plot.margin = ggplot2::margin(t = 4, r = 5, b = 4, l = 5)
  )

dir.create(dirname(output_pdf), recursive = TRUE, showWarnings = FALSE)
ggplot2::ggsave(
  filename = output_pdf,
  plot = dose_response_panel,
  width = 7.2,
  height = 4.4,
  units = "in",
  device = grDevices::pdf,
  bg = "white",
  useDingbats = FALSE
)
ggplot2::ggsave(
  filename = output_png,
  plot = dose_response_panel,
  width = 7.2,
  height = 4.4,
  units = "in",
  dpi = 300,
  bg = "white"
)

assert_true(file.exists(output_pdf) && file.info(output_pdf)$size > 0L,
            "The PDF figure was not written or is empty.")
assert_true(file.exists(output_png) && file.info(output_png)$size > 0L,
            "The PNG figure was not written or is empty.")

message("Validated 95 donors and reproduced both arms' slopes, correlations, cutoffs, and ranks.")
message("Wrote: ", output_pdf)
message("Wrote: ", output_png)
