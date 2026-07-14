library(targets)
library(here)
library(dplyr)
library(tidyr)
library(ggplot2)

source(here::here("scripts", "functions.R"))
targets::tar_config_set(store = here::here("_targets"))

extract_fect_factor <- function(fect_obj, spec_label) {
  factor_mat <- as.data.frame(fect_obj$factor)
  names(factor_mat) <- paste0("factor_", seq_len(ncol(factor_mat)))

  factor_mat %>%
    dplyr::mutate(year = fect_obj$rawtime) %>%
    tidyr::pivot_longer(
      cols = dplyr::starts_with("factor_"),
      names_to = "factor",
      values_to = "value"
    ) %>%
    dplyr::group_by(factor) %>%
    dplyr::mutate(value_z = as.numeric(scale(value))) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(
      specification = spec_label,
      r_cv = as.integer(fect_obj$r.cv[["r"]])
    ) %>%
    dplyr::select(specification, r_cv, year, factor, value, value_z)
}

factor_df <- extract_fect_factor(
  targets::tar_read(fect_ife),
  "Main IFE specification"
)

write.csv(
  factor_df,
  here::here("quality_reports", "fect_ife_latent_factor.csv"),
  row.names = FALSE
)

p <- ggplot(factor_df, ggplot2::aes(x = year, y = value_z)) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.25, colour = "grey70") +
  ggplot2::geom_vline(
    xintercept = 2009,
    linetype = "dashed",
    linewidth = 0.45,
    colour = "#B23A48"
  ) +
  ggplot2::geom_line(linewidth = 0.9, colour = "#183A59") +
  ggplot2::geom_point(size = 1.8, colour = "#183A59") +
  ggplot2::annotate(
    "text",
    x = 2009.4,
    y = max(factor_df$value_z, na.rm = TRUE) * 0.92,
    label = "Brazil treatment year",
    hjust = 0,
    size = 3.2,
    colour = "#B23A48"
  ) +
  ggplot2::scale_x_continuous(breaks = seq(1990, 2023, by = 5)) +
  ggplot2::labs(
    x = "Year",
    y = "Estimated latent factor (standardized)",
    title = "Latent factor from the main fect IFE specification",
    subtitle = "Scale and sign are normalization-dependent; the plot is useful for timing and relative movement.",
    caption = paste0(
      "Source: targets::tar_read(fect_ife). ",
      "Cross-validation selected r = ",
      unique(factor_df$r_cv),
      "."
    )
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold"),
    axis.title = ggplot2::element_text(face = "bold"),
    plot.caption = ggplot2::element_text(colour = "grey35")
  )

ggplot2::ggsave(
  filename = here::here("quality_reports", "fect_ife_latent_factor.png"),
  plot = p,
  width = 7,
  height = 4.2,
  dpi = 300
)

print(p)
