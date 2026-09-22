#!/usr/bin/env Rscript

# Export the native synthdid plot for the Australia point estimate whose
# treatment onset is imposed in 2006. No uncertainty estimate is computed.

options(scipen = 999)
suppressWarnings(Sys.setlocale("LC_CTYPE", "pt_BR.UTF-8"))

suppressPackageStartupMessages({
  library(ggplot2)
  library(readr)
})

if (!requireNamespace("synthdid", quietly = TRUE)) {
  stop("Package `synthdid` is required.", call. = FALSE)
}

analysis_dir <- file.path(
  "data", "processed", "diagnostics", "selected_public_cue_sdid_fect"
)
fit_path <- file.path(analysis_dir, "australia_sdid_2006_point_fit.rds")
result_path <- file.path(analysis_dir, "australia_sdid_2006_point.csv")

if (!file.exists(fit_path) || !file.exists(result_path)) {
  stop(
    "Run `estimate_australia_sdid_2007_point.R` with ",
    "AUSTRALIA_SDID_TREATMENT_YEAR=2006 before plotting.",
    call. = FALSE
  )
}

fit <- readRDS(fit_path)
result <- readr::read_csv(result_path, show_col_types = FALSE)
if (nrow(result) != 1L || result$treatment_year[[1L]] != 2006L ||
    result$placebo_replications[[1L]] != 0L) {
  stop("The stored result is not the requested 2006 point estimate.", call. = FALSE)
}

estimate_label <- formatC(
  result$estimate[[1L]],
  digits = 4L,
  format = "f",
  decimal.mark = ",",
  flag = "+"
)

# `plot()` dispatches to `plot.synthdid_estimate()`, the native plotting
# method provided by synthdid. `se.method = "none"` prevents any jackknife or
# placebo uncertainty calculation.
plot_object <- plot(
  fit,
  treated.name = "Austrália",
  control.name = "Controle sintético",
  se.method = "none",
  overlay = 0,
  line.width = 0.75,
  point.size = 2.0,
  trajectory.alpha = 0.82,
  diagram.alpha = 0.92,
  effect.alpha = 0.95,
  onset.alpha = 0.55
) +
  ggplot2::labs(
    title = "Austrália: SDiD com tratamento imposto em 2006",
    subtitle = paste0(
      "ATT = ", estimate_label,
      " | 105 controles limpos | janela 1997-2022"
    ),
    x = "Ano",
    y = "Distância absoluta à China",
    caption = paste0(
      "Gráfico nativo de plot.synthdid_estimate(). A linha vertical separa ",
      "2005, último ano pré, de 2006, primeiro ano tratado.\n",
      "A faixa inferior mostra os pesos temporais pré-tratamento. ",
      "Sem erro-padrão ou intervalo de confiança."
    )
  ) +
  ggplot2::scale_x_continuous(
    breaks = seq.int(1998L, 2022L, by = 4L),
    minor_breaks = NULL
  ) +
  ggplot2::scale_color_manual(
    values = c("Austrália" = "#17365D", "Controle sintético" = "#D55E00")
  ) +
  ggplot2::scale_fill_manual(
    values = c("Austrália" = "#17365D", "Controle sintético" = "#D55E00")
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "top",
    legend.direction = "horizontal",
    plot.title.position = "plot",
    plot.caption.position = "plot",
    plot.caption = ggplot2::element_text(
      hjust = 0,
      color = "#404040",
      size = 9,
      margin = ggplot2::margin(t = 10)
    ),
    panel.grid.minor = ggplot2::element_blank()
  )

output_dir <- file.path(
  "quality_reports", "selected_public_cue_sdid_fect", "figures"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

png_path <- file.path(output_dir, "australia_sdid_2006_native.png")
pdf_path <- file.path(output_dir, "australia_sdid_2006_native.pdf")

ggplot2::ggsave(
  filename = png_path,
  plot = plot_object,
  width = 8.0,
  height = 5.5,
  units = "in",
  dpi = 300,
  bg = "white"
)
ggplot2::ggsave(
  filename = pdf_path,
  plot = plot_object,
  width = 8.0,
  height = 5.5,
  units = "in",
  device = grDevices::pdf
)

message("Native synthdid plot written to: ", png_path)
message("Vector version written to: ", pdf_path)
