#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
})

input_dir <- file.path(
  "data", "processed", "diagnostics", "selected_public_cue_sdid_fect"
)
output_dir <- file.path(
  "quality_reports", "revisions", "paper_v4",
  "20260922_cross_country_public_cue_preview", "assets"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

panel <- readr::read_csv(
  file.path(input_dir, "fect_clean_controls_panel.csv"),
  show_col_types = FALSE
) %>%
  dplyr::mutate(
    public_cue_year = dplyr::if_else(
      iso3c == "AUS",
      2007L,
      as.integer(public_cue_year)
    )
  )

pre_cue_summary <- panel %>%
  dplyr::filter(focal_country, year < public_cue_year) %>%
  dplyr::group_by(iso3c, country_name, public_cue_year) %>%
  dplyr::summarise(
    mean_pre_cue_distance = mean(abs_distance_china, na.rm = TRUE),
    median_pre_cue_distance = stats::median(abs_distance_china, na.rm = TRUE),
    min_pre_cue_distance = min(abs_distance_china, na.rm = TRUE),
    max_pre_cue_distance = max(abs_distance_china, na.rm = TRUE),
    n_pre_cue_years = dplyr::n(),
    .groups = "drop"
  ) %>%
  dplyr::arrange(mean_pre_cue_distance)

readr::write_csv(
  pre_cue_summary,
  file.path(output_dir, "pre_cue_distance_summary.csv")
)

distance_plot <- pre_cue_summary %>%
  dplyr::mutate(
    country_name = stats::reorder(country_name, mean_pre_cue_distance),
    highlight = dplyr::if_else(country_name == "Gabon", "Gabon", "Other cases")
  ) %>%
  ggplot2::ggplot(
    ggplot2::aes(x = mean_pre_cue_distance, y = country_name, colour = highlight)
  ) +
  ggplot2::geom_segment(
    ggplot2::aes(
      x = min_pre_cue_distance,
      xend = max_pre_cue_distance,
      yend = country_name
    ),
    linewidth = 0.65,
    alpha = 0.55
  ) +
  ggplot2::geom_point(size = 3.2) +
  ggplot2::geom_point(
    ggplot2::aes(x = median_pre_cue_distance),
    shape = 21,
    fill = "white",
    size = 2.5,
    stroke = 0.7
  ) +
  ggplot2::geom_text(
    ggplot2::aes(label = sprintf("%.2f", mean_pre_cue_distance)),
    hjust = 0.5,
    vjust = -1.0,
    size = 3.4,
    show.legend = FALSE
  ) +
  ggplot2::scale_colour_manual(
    values = c("Gabon" = "#b2182b", "Other cases" = "#2166ac"),
    guide = "none"
  ) +
  ggplot2::scale_x_continuous(
    limits = c(0, 2.65),
    breaks = seq(0, 2.5, by = 0.5),
    expand = ggplot2::expansion(mult = c(0.01, 0.02))
  ) +
  ggplot2::labs(
    x = "Absolute UNGA ideal-point distance to China before the public cue",
    y = NULL
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_text(colour = "black"),
    plot.margin = ggplot2::margin(8, 18, 8, 8)
  )

ggplot2::ggsave(
  filename = file.path(output_dir, "figure_pre_cue_distance_focal_cases.png"),
  plot = distance_plot,
  width = 7.2,
  height = 4.2,
  units = "in",
  dpi = 320,
  bg = "white"
)
sdid_results <- readr::read_csv(
  file.path(input_dir, "sdid_results.csv"),
  show_col_types = FALSE
)
australia_2007 <- readr::read_csv(
  file.path(input_dir, "australia_sdid_2007_results.csv"),
  show_col_types = FALSE
)

selected_sdid <- sdid_results %>%
  dplyr::filter(fit_id %in% c("chl_cue_2008", "ury_cue_2013", "aus_top1_2010")) %>%
  dplyr::transmute(
    fit_id,
    country = country_name,
    timing = dplyr::case_when(
      fit_id == "chl_cue_2008" ~ "Public cue (2008)",
      fit_id == "ury_cue_2013" ~ "Public cue (2013)",
      fit_id == "aus_top1_2010" ~ "Top goods-export destination (2010)",
      TRUE ~ fit_id
    ),
    treatment_year,
    att = estimate,
    se = se_placebo,
    ci_low = ci_95_low,
    ci_high = ci_95_high,
    p_value = p_normal_two_sided,
    n_pre_years,
    n_post_years,
    n_donors,
    inference = "Placebo SE (5,000 re-estimations)"
  )

australia_2007_row <- australia_2007 %>%
  dplyr::transmute(
    fit_id,
    country = country_name,
    timing = "Public cue (2007)",
    treatment_year,
    att = estimate,
    se = se_placebo,
    ci_low = ci_95_low,
    ci_high = ci_95_high,
    p_value = p_normal_two_sided,
    n_pre_years,
    n_post_years,
    n_donors,
    inference = "Placebo SE (5,000 re-estimations)"
  )

selected_sdid <- dplyr::bind_rows(selected_sdid, australia_2007_row) %>%
  dplyr::mutate(
    display_order = dplyr::case_when(
      fit_id == "chl_cue_2008" ~ 1L,
      fit_id == "ury_cue_2013" ~ 2L,
      fit_id == "aus_cue_2007" ~ 3L,
      fit_id == "aus_top1_2010" ~ 4L,
      TRUE ~ 99L
    )
  ) %>%
  dplyr::arrange(display_order) %>%
  dplyr::select(-display_order)

readr::write_csv(
  selected_sdid,
  file.path(output_dir, "table_selected_public_cue_sdid.csv"),
  na = ""
)

ife_results <- readr::read_csv(
  file.path(input_dir, "fect_results.csv"),
  show_col_types = FALSE
)

selected_ife <- ife_results %>%
  dplyr::filter(
    model_id %in% c(
      "clean_controls",
      "full_switching",
      "clean_controls_without_gab_qat",
      "full_switching_without_gab_qat"
    )
  ) %>%
  dplyr::transmute(
    model_id,
    case_sample = dplyr::case_when(
      model_id %in% c("clean_controls", "full_switching") ~
        "Five cases: AUS, CHL, GAB, QAT, URY",
      model_id %in% c(
        "clean_controls_without_gab_qat",
        "full_switching_without_gab_qat"
      ) ~ "Four cases: AUS, BRA, CHL, URY",
      TRUE ~ model_id
    ),
    comparison_rule = dplyr::case_when(
      model_id %in% c(
        "clean_controls",
        "clean_controls_without_gab_qat"
      ) ~ "Never-China-top controls",
      model_id %in% c(
        "full_switching",
        "full_switching_without_gab_qat"
      ) ~ "Controls enter and leave the comparison set",
      TRUE ~ model_id
    ),
    att = estimate,
    se = se_bootstrap,
    ci_low = ci_95_low,
    ci_high = ci_95_high,
    p_value = p_normal_two_sided,
    latent_factors = selected_factors,
    n_treated = n_treated_units,
    n_control = n_never_treated_units,
    bootstrap_replications,
    display_order = dplyr::case_when(
      model_id == "clean_controls_without_gab_qat" ~ 1L,
      model_id == "full_switching_without_gab_qat" ~ 2L,
      model_id == "clean_controls" ~ 3L,
      model_id == "full_switching" ~ 4L,
      TRUE ~ 99L
    )
  ) %>%
  dplyr::arrange(display_order) %>%
  dplyr::select(-display_order)

readr::write_csv(
  selected_ife,
  file.path(output_dir, "table_public_cue_pooled_models.csv")
)

writeLines(
  capture.output(sessionInfo()),
  file.path(output_dir, "asset_build_session_info.txt")
)
