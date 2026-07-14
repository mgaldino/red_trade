#!/usr/bin/env Rscript

# Descriptive Brazil-China UNGA ideal-point distance plot.
# Reads the existing targets object synth_data without running tar_make().

options(scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(here)
  library(readr)
  library(targets)
  library(tibble)
})

target_store <- here::here("_targets")
analysis_date <- "2026-05-16"
data_out <- here::here("quality_reports", "brazil_china_local_linear_data.csv")
smooth_out <- here::here("quality_reports", "brazil_china_local_linear_smooth.csv")
linear_smooth_out <- here::here("quality_reports", "brazil_china_simple_linear_smooth.csv")
caption_out <- here::here("quality_reports", "brazil_china_local_linear_caption.md")
png_out <- here::here("images", "brazil_china_distance_local_linear.png")
pdf_out <- here::here("images", "brazil_china_distance_local_linear.pdf")
linear_png_out <- here::here("images", "brazil_china_distance_linear.png")
linear_pdf_out <- here::here("images", "brazil_china_distance_linear.pdf")

dir.create(dirname(data_out), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(png_out), recursive = TRUE, showWarnings = FALSE)

targets::tar_config_set(store = target_store)

synth_data <- targets::tar_read(synth_data)

brazil_distance <- synth_data |>
  dplyr::filter(iso3c == "BRA") |>
  dplyr::select(iso3c, year, abs_distance_china, treatment) |>
  dplyr::arrange(year) |>
  dplyr::mutate(
    period = dplyr::case_when(
      year <= 2008 ~ "Pre-2009",
      year >= 2009 ~ "Post-2009",
      TRUE ~ NA_character_
    )
  )

stopifnot(nrow(brazil_distance) > 0)
stopifnot(!anyNA(brazil_distance$year))
stopifnot(!anyNA(brazil_distance$abs_distance_china))
stopifnot(any(brazil_distance$year <= 2008))
stopifnot(any(brazil_distance$year >= 2009))
stopifnot(!anyDuplicated(brazil_distance$year))

loess_span <- 0.80
loess_degree <- 1

fit_local_linear <- function(data, period_label, span = loess_span, degree = loess_degree) {
  if (nrow(data) < 4) {
    stop("Local linear regression requires at least four observations per period.")
  }

  fitted_model <- stats::loess(
    abs_distance_china ~ year,
    data = data,
    degree = degree,
    span = span,
    family = "gaussian",
    surface = "direct",
    control = stats::loess.control(surface = "direct")
  )

  pred_grid <- tibble::tibble(
    year = seq(min(data$year), max(data$year), length.out = 200)
  )

  pred_grid |>
    dplyr::mutate(
      abs_distance_china = as.numeric(stats::predict(fitted_model, newdata = pred_grid)),
      period = period_label,
      smoother = "loess",
      degree = degree,
      span = span
    )
}

fit_simple_linear <- function(data, period_label) {
  if (nrow(data) < 2) {
    stop("Simple linear regression requires at least two observations per period.")
  }

  fitted_model <- stats::lm(abs_distance_china ~ year, data = data)

  pred_grid <- tibble::tibble(
    year = seq(min(data$year), max(data$year), length.out = 200)
  )

  pred_grid |>
    dplyr::mutate(
      abs_distance_china = as.numeric(stats::predict(fitted_model, newdata = pred_grid)),
      period = period_label,
      smoother = "lm",
      degree = 1,
      span = NA_real_
    )
}

smooth_input <- brazil_distance |>
  dplyr::filter(!is.na(period))

smooth_distance <- smooth_input |>
  split(f = smooth_input[["period"]]) |>
  lapply(function(data) fit_local_linear(data, unique(data$period))) |>
  dplyr::bind_rows() |>
  dplyr::mutate(
    period = factor(period, levels = c("Pre-2009", "Post-2009"))
  )

linear_distance <- smooth_input |>
  split(f = smooth_input[["period"]]) |>
  lapply(function(data) fit_simple_linear(data, unique(data$period))) |>
  dplyr::bind_rows() |>
  dplyr::mutate(
    period = factor(period, levels = c("Pre-2009", "Post-2009"))
  )

local_linear_caption <- paste(
  strwrap(
    paste(
      "Figure 1. Descriptive only. Curves are separate degree-1 LOESS fits",
      "(span = 0.80) before 2009 and from 2009 onward. The dashed line marks",
      "China's rank reversal in Brazil's trade hierarchy."
    ),
    width = 105
  ),
  collapse = "\n"
)

simple_linear_caption <- paste(
  strwrap(
    paste(
      "Figure 1. Descriptive only. Lines are separate OLS fits before 2009",
      "and from 2009 onward. The dashed line marks China's rank reversal in",
      "Brazil's trade hierarchy."
    ),
    width = 105
  ),
  collapse = "\n"
)

make_distance_plot <- function(fitted_data, plot_caption) {
  ggplot(
    brazil_distance,
    aes(x = year, y = abs_distance_china)
  ) +
    geom_vline(
      xintercept = 2009,
      colour = "grey35",
      linetype = "dashed",
      linewidth = 0.6
    ) +
    geom_point(
      aes(colour = "Annual raw value"),
      size = 2.3,
      alpha = 0.9
    ) +
    geom_line(
      data = fitted_data,
      aes(
        x = year,
        y = abs_distance_china,
        colour = period
      ),
      linewidth = 1.15
    ) +
    annotate(
      "text",
      x = 2009.15,
      y = max(brazil_distance$abs_distance_china, na.rm = TRUE),
      label = "2009",
      hjust = 0,
      vjust = 1,
      size = 3,
      colour = "grey30"
    ) +
    scale_colour_manual(
      values = c(
        "Annual raw value" = "#333333",
        "Pre-2009" = "#2C7FB8",
        "Post-2009" = "#D95F0E"
      ),
      breaks = c("Annual raw value", "Pre-2009", "Post-2009"),
      name = NULL
    ) +
    scale_x_continuous(
      breaks = seq(
        min(brazil_distance$year),
        max(brazil_distance$year),
        by = 2
      )
    ) +
    labs(
      title = "Brazil-China Distance in UNGA Ideal Points",
      x = "Year",
      y = "Absolute distance to China",
      caption = plot_caption
    ) +
    theme_minimal(base_size = 12) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(face = "bold"),
      plot.caption = element_text(hjust = 0, size = 7.8, margin = margin(t = 8)),
      plot.margin = margin(t = 10, r = 16, b = 10, l = 10),
      panel.grid.minor = element_blank()
    )
}

local_linear_plot <- make_distance_plot(
  fitted_data = smooth_distance,
  plot_caption = local_linear_caption
)

simple_linear_plot <- make_distance_plot(
  fitted_data = linear_distance,
  plot_caption = simple_linear_caption
)

local_linear_manuscript_caption <- paste(
  "Figure 1. Brazil-China distance in UNGA ideal points, 1997-2016.",
  "Points show raw annual absolute distances from the paper's analytic",
  "dataset. The blue and orange curves are separate local linear",
  "regressions (degree-1 LOESS, span = 0.80) estimated for the pre-2009",
  "and post-2009 periods, respectively. The vertical dashed line marks",
  "2009, when China became Brazil's top trade partner. The figure is",
  "descriptive and should not be read as a causal estimate; the SDiD",
  "design estimates the average post-2009 treatment effect relative to",
  "the synthetic counterfactual."
)

simple_linear_manuscript_caption <- paste(
  "Figure 1. Brazil-China distance in UNGA ideal points, 1997-2016.",
  "Points show raw annual absolute distances from the paper's analytic",
  "dataset. The blue and orange lines are separate OLS fits estimated for",
  "the pre-2009 and post-2009 periods, respectively. The vertical dashed",
  "line marks 2009, when China became Brazil's top trade partner. The",
  "figure is descriptive and should not be read as a causal estimate; the",
  "SDiD design estimates the average post-2009 treatment effect relative",
  "to the synthetic counterfactual."
)

writeLines(
  c(
    "# Caption pronta para o manuscrito",
    "",
    "## Versão local linear",
    "",
    local_linear_manuscript_caption,
    "",
    "## Versão linear simples",
    "",
    simple_linear_manuscript_caption,
    "",
    "# Fonte",
    "",
    paste0(
      "Objeto `synth_data` do pipeline local de `targets`, lido em ",
      analysis_date,
      " sem executar `targets::tar_make()`."
    )
  ),
  caption_out,
  useBytes = TRUE
)

readr::write_csv(brazil_distance, data_out)
readr::write_csv(smooth_distance, smooth_out)
readr::write_csv(linear_distance, linear_smooth_out)

ggsave(png_out, local_linear_plot, width = 7.6, height = 5.2, dpi = 320)
ggsave(pdf_out, local_linear_plot, width = 7.6, height = 5.2)
ggsave(linear_png_out, simple_linear_plot, width = 7.6, height = 5.2, dpi = 320)
ggsave(linear_pdf_out, simple_linear_plot, width = 7.6, height = 5.2)

cat("Saved data: ", data_out, "\n", sep = "")
cat("Saved local linear smooth data: ", smooth_out, "\n", sep = "")
cat("Saved simple linear smooth data: ", linear_smooth_out, "\n", sep = "")
cat("Saved local linear PNG: ", png_out, "\n", sep = "")
cat("Saved local linear PDF: ", pdf_out, "\n", sep = "")
cat("Saved simple linear PNG: ", linear_png_out, "\n", sep = "")
cat("Saved simple linear PDF: ", linear_pdf_out, "\n", sep = "")
cat("Saved caption: ", caption_out, "\n", sep = "")
