#!/usr/bin/env Rscript

# Plot Brazil-China UNGA vote similarity scores by resolution, 2005-2012.
# Score: 1 for identical votes, 0.5 for yes/abstain or no/abstain, 0 for yes/no.

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

input_file <- "data/processed/unvotes/brazil_china_vote_alignment_by_resolution_2005_2012.csv"
plot_data_out <- "data/processed/unvotes/brazil_china_vote_similarity_score_by_resolution_2005_2012.csv"
report_dir <- "quality_reports/un_vote_cases"
access_date <- "2026-05-16"

fig_color_png <- file.path(
  report_dir,
  "figura_7_similarity_score_jitter_cor_tema_2005_2012.png"
)
fig_color_pdf <- file.path(
  report_dir,
  "figura_7_similarity_score_jitter_cor_tema_2005_2012.pdf"
)
fig_facet_png <- file.path(
  report_dir,
  "figura_8_similarity_score_jitter_facet_tema_2005_2012.png"
)
fig_facet_pdf <- file.path(
  report_dir,
  "figura_8_similarity_score_jitter_facet_tema_2005_2012.pdf"
)
fig_plain_png <- file.path(
  report_dir,
  "figura_9_similarity_score_jitter_sem_tema_2005_2012.png"
)
fig_plain_pdf <- file.path(
  report_dir,
  "figura_9_similarity_score_jitter_sem_tema_2005_2012.pdf"
)

dir.create(dirname(plot_data_out), recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

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

similarity_score <- function(vote_brazil, vote_china) {
  dplyr::case_when(
    vote_brazil == vote_china ~ 1,
    vote_brazil %in% c("yes", "no") & vote_china == "abstain" ~ 0.5,
    vote_china %in% c("yes", "no") & vote_brazil == "abstain" ~ 0.5,
    vote_brazil %in% c("yes", "no") &
      vote_china %in% c("yes", "no") &
      vote_brazil != vote_china ~ 0,
    TRUE ~ NA_real_
  )
}

theme_levels <- c(
  "Direitos humanos",
  "Armas/desarmamento/nuclear",
  "Desenvolvimento econômico",
  "Descolonização",
  "Palestina/Oriente Médio",
  "Outros / sem codificação"
)

theme_colors <- c(
  "Direitos humanos" = "#B2182B",
  "Armas/desarmamento/nuclear" = "#2166AC",
  "Desenvolvimento econômico" = "#1B7837",
  "Descolonização" = "#E69F00",
  "Palestina/Oriente Médio" = "#7B3294",
  "Outros / sem codificação" = "#666666"
)

resolution_scores <- readr::read_csv(input_file, show_col_types = FALSE) |>
  dplyr::mutate(
    similarity_score = similarity_score(vote_brazil, vote_china),
    similarity_label = dplyr::case_when(
      similarity_score == 1 ~ "igual",
      similarity_score == 0.5 ~ "parcial",
      similarity_score == 0 ~ "oposto",
      TRUE ~ NA_character_
    )
  ) |>
  dplyr::select(
    rcid,
    doc_symbol,
    year,
    issue_family,
    vote_brazil,
    vote_china,
    similarity_score,
    similarity_label
  )

theme_scores <- resolution_scores |>
  tidyr::separate_longer_delim(issue_family, delim = "; ") |>
  dplyr::mutate(
    issue_family = tidyr::replace_na(
      issue_family,
      "Outros / sem codificação"
    ),
    issue_family = factor(issue_family, levels = theme_levels)
  ) |>
  dplyr::arrange(issue_family, year, rcid)

validation <- resolution_scores |>
  dplyr::summarise(
    n_resolutions = dplyr::n(),
    n_missing_scores = sum(is.na(similarity_score)),
    min_score = min(similarity_score, na.rm = TRUE),
    max_score = max(similarity_score, na.rm = TRUE),
    n_duplicate_rcid = sum(duplicated(rcid))
  )

if (validation$n_missing_scores > 0) {
  stop("Missing similarity scores: ", validation$n_missing_scores)
}

if (validation$min_score < 0 || validation$max_score > 1) {
  stop("Similarity scores outside [0, 1].")
}

if (validation$n_duplicate_rcid > 0) {
  stop("Duplicated rcid in resolution score data: ", validation$n_duplicate_rcid)
}

readr::write_csv(resolution_scores, plot_data_out)

base_caption <- paste0(
  "Fonte: unvotes 0.3.0/Voeten, acessado em ",
  access_date,
  ". Escore: 1 = igual; 0,5 = sim/abstenção ou não/abstenção; 0 = sim/não."
)

multi_theme_note <- "Resoluções com múltiplos temas aparecem em cada família correspondente."

jitter_position <- position_jitter(width = 0.24, height = 0.06, seed = 20260516)

fig_color <- ggplot(
  theme_scores,
  aes(x = year, y = similarity_score, color = issue_family)
) +
  geom_point(position = jitter_position, alpha = 0.58, size = 1.35) +
  scale_x_continuous(breaks = 2005:2012) +
  scale_y_continuous(
    limits = c(-0.08, 1.08),
    breaks = c(0, 0.5, 1),
    labels = c("0", "0,5", "1")
  ) +
  scale_color_manual(values = theme_colors, drop = FALSE) +
  labs(
    title = "Figura 7. Escore de similaridade dos votos Brasil-China por resolução",
    subtitle = "Pontos por resolução com jitter horizontal e vertical; cores indicam famílias substantivas.",
    x = "Ano",
    y = "Escore de similaridade",
    color = NULL,
    caption = paste(base_caption, multi_theme_note)
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    legend.box = "vertical",
    panel.grid.minor = element_blank(),
    plot.caption = element_text(hjust = 0, size = 9),
    plot.margin = margin(10, 16, 14, 16)
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

fig_facet <- ggplot(
  theme_scores,
  aes(x = year, y = similarity_score)
) +
  geom_point(position = jitter_position, color = "#1F4E79", alpha = 0.58, size = 1.25) +
  facet_wrap(~issue_family, ncol = 2) +
  scale_x_continuous(breaks = 2005:2012) +
  scale_y_continuous(
    limits = c(-0.08, 1.08),
    breaks = c(0, 0.5, 1),
    labels = c("0", "0,5", "1")
  ) +
  labs(
    title = "Figura 8. Escore de similaridade dos votos Brasil-China por tema",
    subtitle = "Pontos por resolução com jitter horizontal e vertical; painéis indicam famílias substantivas.",
    x = "Ano",
    y = "Escore de similaridade",
    caption = paste(base_caption, multi_theme_note)
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0, size = 9),
    plot.margin = margin(10, 16, 14, 16)
  )

fig_plain <- ggplot(
  resolution_scores,
  aes(x = year, y = similarity_score)
) +
  geom_point(position = jitter_position, color = "#1F4E79", alpha = 0.52, size = 1.25) +
  scale_x_continuous(breaks = 2005:2012) +
  scale_y_continuous(
    limits = c(-0.08, 1.08),
    breaks = c(0, 0.5, 1),
    labels = c("0", "0,5", "1")
  ) +
  labs(
    title = "Figura 9. Escore de similaridade dos votos Brasil-China por resolução",
    subtitle = "Pontos por resolução com jitter horizontal e vertical; temas não diferenciados.",
    x = "Ano",
    y = "Escore de similaridade",
    caption = base_caption
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    plot.caption = element_text(hjust = 0, size = 9),
    plot.margin = margin(10, 16, 14, 16)
  )

save_plot_pair(fig_color, fig_color_png, fig_color_pdf, width = 12, height = 7)
save_plot_pair(fig_facet, fig_facet_png, fig_facet_pdf, width = 12, height = 8.5)
save_plot_pair(fig_plain, fig_plain_png, fig_plain_pdf, width = 10.5, height = 5.8)

message("Wrote: ", plot_data_out)
message("Wrote: ", fig_color_png)
message("Wrote: ", fig_facet_png)
message("Wrote: ", fig_plain_png)
