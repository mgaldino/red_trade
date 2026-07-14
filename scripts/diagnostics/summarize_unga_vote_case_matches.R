#!/usr/bin/env Rscript

# Summarise selected UNGA vote cases as pre/post matched sets.
# Reads processed case data and writes communication-oriented outputs.

options(scipen = 999)
try(Sys.setlocale("LC_ALL", "pt_BR.UTF-8"), silent = TRUE)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(stringr)
  library(tibble)
})

cases_path <- "data/processed/unvotes/brazil_china_un_vote_cases_2004_2012.csv"
summary_out <- "data/processed/unvotes/brazil_china_un_vote_matched_summary_2004_2012.csv"
pairs_out <- "data/processed/unvotes/brazil_china_un_vote_matched_pairs_2004_2012.csv"
plot_png_out <- "quality_reports/un_vote_cases/figura_1_matching_casos_onu.png"
plot_pdf_out <- "quality_reports/un_vote_cases/figura_1_matching_casos_onu.pdf"

dir.create(dirname(summary_out), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(plot_png_out), recursive = TRUE, showWarnings = FALSE)

format_vote <- function(x) {
  dplyr::recode(
    x,
    "yes" = "sim",
    "no" = "não",
    "abstain" = "abstenção",
    .default = x
  )
}

make_vote_label <- function(year, doc_symbol, vote_brazil, vote_china) {
  paste0(
    year, "\n",
    doc_symbol, "\n",
    "BR ", format_vote(vote_brazil), " / CHN ", format_vote(vote_china)
  )
}

theme_labels <- c(
  "ICJ advisory opinion on nuclear weapons" = "Parecer da CIJ sobre armas nucleares",
  "Globalization and human rights" = "Globalização e direitos humanos",
  "UN Human Rights Council reports" = "Relatórios do Conselho de Direitos Humanos",
  "Country-specific human rights reports: DPRK" = "Direitos humanos: Coreia do Norte",
  "Country-specific human rights reports: Iran" = "Direitos humanos: Irã",
  "Reducing nuclear danger" = "Redução do perigo nuclear",
  "Moratorium on the death penalty" = "Moratória da pena de morte"
)

cases <- readr::read_csv(cases_path, show_col_types = FALSE) |>
  dplyr::mutate(
    case_family = dplyr::case_when(
      stringr::str_detect(case_type, "^positivo") ~ "positivo",
      stringr::str_detect(case_type, "^negativo") ~ "negativo",
      TRUE ~ "outro"
    ),
    period = dplyr::case_when(
      stringr::str_detect(case_type, "pre") ~ "pre",
      stringr::str_detect(case_type, "pos") ~ "post",
      TRUE ~ NA_character_
    ),
    convergence_pt = dplyr::if_else(
      convergence == "convergente",
      "convergência",
      "divergência"
    ),
    theme_display = dplyr::recode(theme, !!!theme_labels, .default = theme),
    vote_pair = paste0(
      "BR ", format_vote(vote_brazil),
      " / CHN ", format_vote(vote_china)
    )
  ) |>
  dplyr::arrange(case_family, case_id, year, doc_symbol)

stopifnot(nrow(cases) == 21)
stopifnot(all(c("pre", "post") %in% cases$period))

pre_cases <- cases |>
  dplyr::filter(period == "pre") |>
  dplyr::select(
    case_id,
    theme,
    theme_display,
    case_family,
    pre_year = year,
    pre_doc_symbol = doc_symbol,
    pre_vote_brazil = vote_brazil,
    pre_vote_china = vote_china,
    pre_convergence = convergence,
    pre_vote_pair = vote_pair
  )

post_cases <- cases |>
  dplyr::filter(period == "post") |>
  dplyr::arrange(case_id, year, doc_symbol) |>
  dplyr::mutate(post_match_id = dplyr::row_number(), .by = case_id) |>
  dplyr::select(
    case_id,
    theme,
    post_match_id,
    post_year = year,
    post_doc_symbol = doc_symbol,
    post_vote_brazil = vote_brazil,
    post_vote_china = vote_china,
    post_convergence = convergence,
    post_vote_pair = vote_pair
  )

matched_pairs <- post_cases |>
  dplyr::left_join(pre_cases, by = c("case_id", "theme")) |>
  dplyr::mutate(
    transition = paste0(
      dplyr::if_else(pre_convergence == "convergente", "convergência", "divergência"),
      " -> ",
      dplyr::if_else(post_convergence == "convergente", "convergência", "divergência")
    ),
    interpretation = dplyr::case_when(
      case_family == "positivo" ~ "aproximação em resolução comparável",
      case_family == "negativo" ~ "divergência persistente em resolução comparável",
      TRUE ~ "caso não classificado"
    )
  ) |>
  dplyr::arrange(case_family, case_id, post_year, post_doc_symbol) |>
  dplyr::select(
    case_id,
    theme,
    theme_display,
    case_family,
    pre_year,
    pre_doc_symbol,
    pre_vote_pair,
    pre_convergence,
    post_match_id,
    post_year,
    post_doc_symbol,
    post_vote_pair,
    post_convergence,
    transition,
    interpretation
  )

matched_summary <- matched_pairs |>
  dplyr::summarise(
    case_family = dplyr::first(case_family),
    pre_match = paste0(
      dplyr::first(pre_year), " ",
      dplyr::first(pre_doc_symbol), " (",
      dplyr::first(pre_vote_pair), ")"
    ),
    post_matches = paste0(
      post_year, " ", post_doc_symbol, " (", post_vote_pair, ")",
      collapse = "; "
    ),
    transition = dplyr::first(transition),
    interpretation = dplyr::first(interpretation),
    .by = c(case_id, theme, theme_display)
  ) |>
  dplyr::arrange(match(case_id, c("P1", "P2", "P3", "N1", "N2", "N3", "N4"))) |>
  dplyr::select(
    case_id,
    theme,
    theme_display,
    case_family,
    pre_match,
    post_matches,
    transition,
    interpretation
  )

plot_data <- cases |>
  dplyr::arrange(case_family, case_id, year, doc_symbol) |>
  dplyr::group_by(case_id) |>
  dplyr::mutate(
    post_order = cumsum(period == "post"),
    slot = dplyr::case_when(
      period == "pre" ~ "Pré\nbaseline",
      period == "post" ~ paste0("Pós\nmatch ", post_order)
    ),
    slot_order = dplyr::case_when(
      period == "pre" ~ 1L,
      period == "post" ~ 1L + post_order
    ),
    row_label = paste0(
      case_id, " - ",
      stringr::str_wrap(theme_display, width = 32)
    ),
    tile_label = make_vote_label(year, doc_symbol, vote_brazil, vote_china),
    status = dplyr::if_else(convergence == "convergente", "Convergência", "Divergência")
  ) |>
  dplyr::ungroup()

case_order <- c("P1", "P2", "P3", "N1", "N2", "N3", "N4")

row_levels <- tibble::tibble(case_id = case_order) |>
  dplyr::left_join(
    plot_data |>
      dplyr::distinct(case_id, row_label),
    by = "case_id"
  ) |>
  dplyr::arrange(dplyr::desc(match(case_id, case_order))) |>
  dplyr::pull(row_label)

slot_levels <- c("Pré\nbaseline", "Pós\nmatch 1", "Pós\nmatch 2")

match_plot <- ggplot(
  plot_data,
  aes(
    x = factor(slot, levels = slot_levels),
    y = factor(row_label, levels = row_levels)
  )
) +
  geom_tile(
    aes(fill = status),
    colour = "white",
    linewidth = 1.1,
    width = 0.94,
    height = 0.86
  ) +
  geom_text(
    aes(label = tile_label),
    colour = "white",
    size = 3.0,
    lineheight = 0.86,
    fontface = "bold"
  ) +
  scale_fill_manual(
    values = c("Divergência" = "#A94442", "Convergência" = "#2E7D59"),
    breaks = c("Divergência", "Convergência"),
    name = NULL
  ) +
  labs(
    title = "Matching de votações Brasil-China na AGNU",
    subtitle = "Cada linha compara uma votação pré-2009 com resoluções pós-2009 substantivamente comparáveis",
    x = NULL,
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid = element_blank(),
    axis.text.x = element_text(face = "bold", size = 10),
    axis.text.y = element_text(size = 9.2, lineheight = 0.95),
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10),
    plot.caption = element_text(hjust = 0, size = 8),
    plot.margin = margin(10, 14, 10, 10)
  )

readr::write_csv(matched_summary, summary_out)
readr::write_csv(matched_pairs, pairs_out)

ggsave(plot_png_out, match_plot, width = 9.6, height = 6.2, dpi = 320)
ggsave(plot_pdf_out, match_plot, width = 9.6, height = 6.2)

cat("Saved matched summary: ", summary_out, "\n", sep = "")
cat("Saved matched pairs: ", pairs_out, "\n", sep = "")
cat("Saved matching PNG: ", plot_png_out, "\n", sep = "")
cat("Saved matching PDF: ", plot_pdf_out, "\n", sep = "")
