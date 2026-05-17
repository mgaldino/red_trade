#!/usr/bin/env Rscript

# Plot yearly Brazil-China UNGA vote similarity by substantive theme.
# Points are annual theme-level percentages; smooths are separate local linear
# regressions for 2005-2008 and 2009-2012.

options(scipen = 999)

set_utf8_locale <- function() {
  for (locale in c("pt_BR.UTF-8", "en_US.UTF-8", "UTF-8")) {
    result <- suppressWarnings(try(Sys.setlocale("LC_CTYPE", locale), silent = TRUE))
    if (!inherits(result, "try-error") && !is.na(result) && nzchar(result)) {
      return(invisible(result))
    }
  }
  invisible(Sys.getlocale("LC_CTYPE"))
}

set_utf8_locale()

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(tidyr)
})

input_file <- "data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv"
plot_data_out <- "data/processed/unvotes/brazil_china_vote_similarity_by_issue_year_plot_2005_2012.csv"
plot_png <- "quality_reports/un_vote_cases/figura_5_similaridade_brasil_china_por_tema_local_linear_2005_2012.png"
plot_pdf <- "quality_reports/un_vote_cases/figura_5_similaridade_brasil_china_por_tema_local_linear_2005_2012.pdf"
access_date <- "2026-05-16"

dir.create(dirname(plot_data_out), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(plot_png), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(input_file)) {
  stop(
    "Missing input file: ", input_file,
    ". Run scripts/diagnostics/analyze_brazil_china_vote_alignment_by_issue_2005_2012.R first."
  )
}

png_utf8 <- function(filename, width, height, units, res, ...) {
  png_type <- if (isTRUE(capabilities("aqua"))) {
    "quartz"
  } else {
    getOption("bitmapType", "cairo")
  }
  grDevices::png(
    filename = filename,
    width = width,
    height = height,
    units = units,
    res = res,
    type = png_type,
    ...
  )
}

pdf_utf8 <- function(filename, width, height, ...) {
  grDevices::pdf(
    file = filename,
    width = width,
    height = height,
    useDingbats = FALSE,
    ...
  )
}

save_plot_pair <- function(plot, png_path, pdf_path, width, height) {
  ggplot2::ggsave(
    png_path,
    plot,
    width = width,
    height = height,
    dpi = 300,
    device = png_utf8
  )
  ggplot2::ggsave(
    pdf_path,
    plot,
    width = width,
    height = height,
    device = pdf_utf8
  )
}

plot_data <- readr::read_csv(input_file, show_col_types = FALSE) |>
  dplyr::filter(
    theme_level == "familia_substantiva",
    year >= 2005,
    year <= 2012
  ) |>
  dplyr::mutate(
    period_fit = dplyr::case_when(
      year <= 2008 ~ "2005-2008",
      year >= 2009 ~ "2009-2012",
      TRUE ~ NA_character_
    ),
    theme = factor(
      theme,
      levels = c(
        "Direitos humanos",
        "Armas/desarmamento/nuclear",
        "Desenvolvimento econômico",
        "Descolonização",
        "Palestina/Oriente Médio",
        "Outros / sem codificação"
      )
    )
  ) |>
  dplyr::arrange(theme, year) |>
  dplyr::select(
    theme,
    year,
    period_fit,
    n_resolutions,
    n_convergent,
    n_divergent,
    pct_convergent
  )

validation <- plot_data |>
  dplyr::summarise(
    n_years = dplyr::n_distinct(year),
    n_themes = dplyr::n_distinct(theme),
    min_pct = min(pct_convergent, na.rm = TRUE),
    max_pct = max(pct_convergent, na.rm = TRUE),
    any_missing_pct = any(is.na(pct_convergent))
  )

if (validation$n_years != 8) {
  stop("Expected 8 years in plot data, found ", validation$n_years)
}

if (validation$min_pct < 0 || validation$max_pct > 100) {
  stop("pct_convergent outside [0, 100].")
}

if (validation$any_missing_pct) {
  stop("Missing pct_convergent values in plot data.")
}

readr::write_csv(plot_data, plot_data_out)

theme_colors <- c(
  "Direitos humanos" = "#B2182B",
  "Armas/desarmamento/nuclear" = "#2166AC",
  "Desenvolvimento econômico" = "#1B7837",
  "Descolonização" = "#E69F00",
  "Palestina/Oriente Médio" = "#7B3294",
  "Outros / sem codificação" = "#666666"
)

fig <- ggplot(
  plot_data,
  aes(x = year, y = pct_convergent, color = theme)
) +
  geom_vline(xintercept = 2008.5, color = "gray45", linewidth = 0.4) +
  geom_point(size = 2.8, alpha = 0.9) +
  geom_smooth(
    aes(group = interaction(theme, period_fit)),
    method = "loess",
    formula = y ~ x,
    method.args = list(degree = 1),
    span = 1,
    se = FALSE,
    linewidth = 0.9,
    na.rm = TRUE
  ) +
  scale_x_continuous(breaks = 2005:2012) +
  scale_y_continuous(
    limits = c(50, 100),
    breaks = seq(50, 100, 10),
    labels = function(x) paste0(x, "%")
  ) +
  scale_color_manual(values = theme_colors, drop = FALSE) +
  labs(
    title = "Figura 5. Similaridade dos votos Brasil-China por tema, 2005-2012",
    subtitle = "Pontos mostram percentuais anuais; linhas são regressões locais lineares separadas para 2005-2008 e 2009-2012.",
    x = "Ano",
    y = "Resoluções com votos similares (%)",
    color = NULL,
    caption = paste0(
      "Fonte: unvotes 0.3.0/Voeten, acessado em ",
      access_date,
      ". Elaboração própria. Resoluções com múltiplos temas entram em cada família substantiva correspondente."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    legend.box = "vertical",
    panel.grid.minor = element_blank()
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

save_plot_pair(fig, plot_png, plot_pdf, width = 10.5, height = 6.5)

message("Wrote: ", plot_data_out)
message("Wrote: ", plot_png)
message("Wrote: ", plot_pdf)
