#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
output_path <- if (length(args) >= 1L) {
  args[[1]]
} else {
  file.path(
    "tmp", "figures",
    "figure6_dynamic_with_pooled_att_preview.png"
  )
}

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

dynamic_results <- targets::tar_read(
  china_top_m2_goods_status_current_dynamic_results
)
model_results <- targets::tar_read(
  china_top_m2_goods_status_current_model_results
)

required_dynamic <- c(
  "min_duration_years", "specification", "event_time", "count",
  "att", "se", "ci_lo", "ci_hi"
)
required_model <- c(
  "min_duration_years", "specification", "att", "ci_lo", "ci_hi",
  "n_treated_country_years"
)

if (!all(required_dynamic %in% names(dynamic_results))) {
  stop("Dynamic results are missing required columns.", call. = FALSE)
}
if (!all(required_model %in% names(model_results))) {
  stop("Model results are missing required columns.", call. = FALSE)
}

dynamic_main <- dynamic_results |>
  dplyr::filter(
    min_duration_years == 5L,
    specification == "risk_set_restricted"
  ) |>
  dplyr::arrange(event_time)

model_main <- model_results |>
  dplyr::filter(
    min_duration_years == 5L,
    specification == "risk_set_restricted"
  ) |>
  dplyr::slice_head(n = 1L)

if (nrow(model_main) != 1L || nrow(dynamic_main) == 0L) {
  stop("The preferred cross-country specification was not found.", call. = FALSE)
}
if (anyDuplicated(dynamic_main$event_time)) {
  stop("Event times are duplicated in the preferred specification.", call. = FALSE)
}
if (any(!is.finite(dynamic_main$att)) ||
    any(!is.finite(dynamic_main$ci_lo)) ||
    any(!is.finite(dynamic_main$ci_hi)) ||
    any(dynamic_main$count <= 0L)) {
  stop("Dynamic estimates contain invalid values or counts.", call. = FALSE)
}

post_all <- dynamic_main |>
  dplyr::filter(event_time >= 1L)

pooled_from_dynamic <- stats::weighted.mean(post_all$att, post_all$count)
if (sum(post_all$count) != model_main$n_treated_country_years[[1]]) {
  stop("Dynamic counts do not match the pooled ATT denominator.", call. = FALSE)
}
if (!isTRUE(all.equal(
  pooled_from_dynamic,
  model_main$att[[1]],
  tolerance = 1e-10
))) {
  stop("The event-time weighted mean does not reproduce the pooled ATT.",
       call. = FALSE)
}

display_min <- -12L
display_max <- 15L
plot_data <- dynamic_main |>
  dplyr::filter(
    event_time >= display_min,
    event_time <= display_max
  ) |>
  dplyr::mutate(
    period = dplyr::if_else(
      event_time >= 1L,
      "Post-entry effect",
      "Pre-entry diagnostic"
    )
  )

support_labels <- plot_data |>
  dplyr::filter(event_time %in% c(1L, 5L, 10L, 15L)) |>
  dplyr::mutate(label = paste0("N=", count)) |>
  dplyr::select(event_time, label)

pooled_label <- sprintf(
  "Pooled ATT = %.3f\n95%% CI [%.3f, %.3f]",
  model_main$att[[1]],
  model_main$ci_lo[[1]],
  model_main$ci_hi[[1]]
)

figure <- ggplot2::ggplot() +
  ggplot2::annotate(
    "rect",
    xmin = 0.5,
    xmax = display_max + 0.5,
    ymin = model_main$ci_lo[[1]],
    ymax = model_main$ci_hi[[1]],
    fill = "#E69F00",
    alpha = 0.16
  ) +
  ggplot2::geom_hline(
    yintercept = 0,
    linewidth = 0.35,
    linetype = "dashed",
    color = "grey45"
  ) +
  ggplot2::geom_vline(
    xintercept = 0.5,
    linewidth = 0.45,
    color = "grey35"
  ) +
  ggplot2::geom_errorbar(
    data = plot_data,
    ggplot2::aes(
      x = event_time,
      ymin = ci_lo,
      ymax = ci_hi,
      color = period
    ),
    width = 0,
    linewidth = 0.45,
    alpha = 0.82
  ) +
  ggplot2::geom_line(
    data = plot_data,
    ggplot2::aes(
      x = event_time,
      y = att,
      color = period,
      group = period
    ),
    linewidth = 0.65
  ) +
  ggplot2::geom_point(
    data = plot_data,
    ggplot2::aes(
      x = event_time,
      y = att,
      color = period
    ),
    size = 1.9
  ) +
  ggplot2::annotate(
    "segment",
    x = 0.5,
    xend = display_max + 0.5,
    y = model_main$att[[1]],
    yend = model_main$att[[1]],
    color = "#B45F06",
    linewidth = 0.75,
    linetype = "longdash"
  ) +
  ggplot2::annotate(
    "label",
    x = 3.9,
    y = -0.225,
    label = pooled_label,
    color = "#8C4A00",
    fill = "white",
    linewidth = 0.2,
    size = 3.0,
    hjust = 0
  ) +
  ggplot2::geom_text(
    data = support_labels,
    ggplot2::aes(x = event_time, y = 0.155, label = label),
    inherit.aes = FALSE,
    color = "grey35",
    size = 2.7
  ) +
  ggplot2::annotate(
    "text",
    x = 0.75,
    y = 0.185,
    label = "Treatment begins at +1",
    hjust = 0,
    color = "grey25",
    size = 3.0
  ) +
  ggplot2::scale_color_manual(
    values = c(
      "Pre-entry diagnostic" = "#7A7A7A",
      "Post-entry effect" = "#1F4E79"
    ),
    breaks = c("Pre-entry diagnostic", "Post-entry effect"),
    name = NULL
  ) +
  ggplot2::scale_x_continuous(
    breaks = seq(-10L, 15L, by = 5L),
    limits = c(display_min - 0.5, display_max + 0.5)
  ) +
  ggplot2::coord_cartesian(
    ylim = c(-0.38, 0.21),
    clip = "off"
  ) +
  ggplot2::labs(
    title = "Dynamic effects and the pooled post-entry ATT",
    subtitle = paste0(
      "Durable China top-export status; restricted-risk-set IFE specification"
    ),
    x = "Periods relative to entry as the top goods-export destination",
    y = "Effect on UNGA ideal-point distance to China",
    caption = paste(
      "Points and vertical bars: event-time estimates and pointwise 95% bootstrap CIs.",
      sprintf(
        "Orange band and dashed line: pooled ATT and its 95%% CI over all %d treated country-years (h=+1 to +20).",
        model_main$n_treated_country_years[[1]]
      ),
      "This is a pooled average, not a cumulative sum. Display: h=-12 to +15.",
      "N labels show contributing treated countries at selected post-entry horizons.",
      sep = "\n"
    )
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    legend.justification = "left",
    plot.title = ggplot2::element_text(face = "bold", size = 13),
    plot.subtitle = ggplot2::element_text(color = "grey30", size = 10.5),
    plot.caption = ggplot2::element_text(
      color = "grey35",
      size = 8.2,
      hjust = 0,
      margin = ggplot2::margin(t = 8)
    ),
    plot.margin = ggplot2::margin(8, 12, 8, 8)
  )

ggplot2::ggsave(
  filename = output_path,
  plot = figure,
  width = 7,
  height = 5.4,
  units = "in",
  dpi = 300,
  bg = "white"
)

message("Wrote preview: ", normalizePath(output_path))
message(sprintf(
  "Validated pooled ATT: %.6f from %d treated country-years.",
  pooled_from_dynamic,
  sum(post_all$count)
))
