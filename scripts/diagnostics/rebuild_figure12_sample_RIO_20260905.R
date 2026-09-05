# Rebuild the Figure 12 illustration used in the RIO revision.
#
# The frozen PDF displays 14 classified headlines although the embedded image
# promises 20 and ends with an empty human-rights group.  This script selects
# those 14 existing rows by exact headline and date from the archived
# classified file, verifies their stored labels, and writes a new image and a
# machine-readable manifest.  It does not modify the original image or the
# targets graph.

suppressPackageStartupMessages({
  library(dplyr)
  library(grid)
  library(jsonlite)
  library(ragg)
  library(readr)
})

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript so its project root can be inferred.")
}
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_root <- normalizePath(file.path(dirname(script_path), "../.."), mustWork = TRUE)

input_path <- file.path(project_root, "data", "folha_classificado.rds")
output_dir <- file.path(
  project_root, "data", "processed", "diagnostics", "RIO_20260905_figure12"
)
output_image <- file.path(project_root, "images", "RIO_20260905_table1_headlines_14.png")
output_pdf <- file.path(project_root, "images", "RIO_20260905_table1_headlines_14.pdf")
output_csv <- file.path(output_dir, "table1_headlines_14.csv")
output_manifest <- file.path(output_dir, "table1_headlines_14_manifest.json")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

expected <- tibble::tribble(
  ~display_order, ~classification, ~headline, ~date,
  1L, "china-brazil relations", "Disputa com Brasil é 'conflito menor' para China, dizem analistas", "2005-10-05",
  2L, "china-brazil relations", "Lula vai se encontrar com presidente da China na segunda", "2004-05-23",
  3L, "china-brazil trade", "China lidera as aquisições de empresas brasileiras", "2013-03-01",
  4L, "china-brazil trade", "China aceita nova regra brasileira e suspende embargo à soja", "2004-06-21",
  5L, "chinese economy", "PIB da China dobra participação no total mundial em 5 anos", "2011-03-25",
  6L, "chinese economy", "BHP prevê produção recorde de minério de ferro e aposta na China", "2012-01-18",
  7L, "chinese politics and policy", "China ameaça Google com \"consequências\" caso empresa largue autocensura", "2010-03-12",
  8L, "chinese politics and policy", "China anuncia fechamento de 700 websites", "2004-08-01",
  9L, "diplomacy", "China não quer interferência dos EUA na questão do Tibete", "2011-09-28",
  10L, "diplomacy", "Chega a Taiwan primeiro vôo direto da China em quase 60 anos", "2008-07-04",
  11L, "disaster and accidents", "Incêndio em prédio residencial deixa 12 mortos na China", "2010-07-19",
  12L, "disaster and accidents", "China detona barragens e prédios danificados; veja vídeo", "2008-06-06",
  13L, "health", "Uma em três chinesas da zona rural se mata por ano", "2002-11-29",
  14L, "health", "China suspende viagens ao Tibete para controlar Sars", "2003-05-13"
) %>%
  mutate(date = as.Date(date))

if (nrow(expected) != 14L || anyDuplicated(expected$display_order)) {
  stop("The Figure 12 specification must contain exactly 14 ordered rows.")
}

classified <- readRDS(input_path) %>%
  transmute(
    headline = enc2utf8(as.character(title)),
    date = as.Date(date_piece),
    classification = enc2utf8(as.character(subject))
  )

matches <- expected %>%
  left_join(classified, by = c("headline", "date"), suffix = c("_expected", "_stored"))

if (nrow(matches) != 14L || anyNA(matches$classification_stored)) {
  stop("One or more Figure 12 rows could not be matched exactly in the archived RDS.")
}
if (any(matches$classification_expected != matches$classification_stored)) {
  stop("The stored ChatGPT labels do not match the frozen Figure 12 labels.")
}

sample <- matches %>%
  arrange(display_order) %>%
  transmute(
    display_order,
    Headline = headline,
    Classification = classification_stored,
    Date = format(date, "%Y-%m-%d")
  )

write_csv(sample, output_csv, na = "")

wrap_headline <- function(x, width = 50L) {
  paste(strwrap(enc2utf8(x), width = width), collapse = "\n")
}

wrap_classification <- function(x, width = 24L) {
  paste(strwrap(enc2utf8(x), width = width), collapse = "\n")
}

table_data <- sample %>%
  transmute(
    Headline = vapply(Headline, wrap_headline, character(1)),
    Classification = vapply(Classification, wrap_classification, character(1)),
    Date
  )

# Draw each cell in normalized coordinates.  A hand-sized table is used here
# instead of a fixed-height tableGrob so that wrapped text cannot enlarge a row
# into the title, footer, or adjacent column.
draw_figure <- function() {
  grid.newpage()

  grid.text(
    "Examples of Classified Headlines",
    x = 0.5, y = 0.965,
    gp = gpar(fontface = "bold", fontsize = 18, col = "#303030")
  )
  grid.text(
    "Archived sample: 14 headlines with ChatGPT-assigned topic",
    x = 0.5, y = 0.915,
    gp = gpar(fontsize = 12, col = "#4A4A4A")
  )

  x_left <- 0.03
  x_headline <- 0.63
  x_classification <- 0.83
  x_right <- 0.97
  y_top <- 0.865
  y_bottom <- 0.075
  header_height <- 0.052

  header_bottom <- y_top - header_height
  grid.rect(
    x = (x_left + x_right) / 2,
    y = (y_top + header_bottom) / 2,
    width = x_right - x_left,
    height = header_height,
    gp = gpar(fill = "#005B85", col = "#005B85")
  )
  grid.text("Headline", x = x_left + 0.012, y = (y_top + header_bottom) / 2,
            just = c("left", "centre"),
            gp = gpar(fontface = "bold", fontsize = 12, col = "#FFFFFF"))
  grid.text("Classification", x = x_headline + 0.012, y = (y_top + header_bottom) / 2,
            just = c("left", "centre"),
            gp = gpar(fontface = "bold", fontsize = 12, col = "#FFFFFF"))
  grid.text("Date", x = x_classification + 0.012, y = (y_top + header_bottom) / 2,
            just = c("left", "centre"),
            gp = gpar(fontface = "bold", fontsize = 12, col = "#FFFFFF"))

  max_lines <- pmax(
    lengths(strsplit(table_data$Headline, "\n", fixed = TRUE)),
    lengths(strsplit(table_data$Classification, "\n", fixed = TRUE))
  )
  raw_row_height <- 0.043 + (max_lines - 1L) * 0.022
  available_height <- header_bottom - y_bottom
  row_height <- raw_row_height * min(1, available_height / sum(raw_row_height))
  row_bottoms <- header_bottom - cumsum(row_height)
  row_tops <- c(header_bottom, head(row_bottoms, -1L))

  for (i in seq_len(nrow(table_data))) {
    fill <- if (i %% 2L == 0L) "#F5F7F8" else "#FFFFFF"
    y_center <- (row_tops[[i]] + row_bottoms[[i]]) / 2
    grid.rect(
      x = (x_left + x_right) / 2,
      y = y_center,
      width = x_right - x_left,
      height = row_height[[i]],
      gp = gpar(fill = fill, col = "#B5B5B5", lwd = 0.45)
    )
    grid.text(table_data$Headline[[i]], x = x_left + 0.012, y = y_center,
              just = c("left", "centre"),
              gp = gpar(fontsize = 10.5, col = "#222222", lineheight = 0.92))
    grid.text(table_data$Classification[[i]], x = x_headline + 0.012, y = y_center,
              just = c("left", "centre"),
              gp = gpar(fontsize = 9.5, col = "#222222", lineheight = 0.92))
    grid.text(table_data$Date[[i]], x = x_classification + 0.012, y = y_center,
              just = c("left", "centre"),
              gp = gpar(fontsize = 9.5, col = "#222222", lineheight = 0.92))
  }
}

output_width_px <- 2400L
output_height_px <- 2200L
ragg::agg_png(output_image, width = output_width_px, height = output_height_px,
              res = 300, background = "white")
draw_figure()
dev.off()

grDevices::pdf(output_pdf, width = output_width_px / 300,
               height = output_height_px / 300,
               useDingbats = FALSE, encoding = "ISOLatin1.enc")
draw_figure()
dev.off()

manifest <- list(
  schema_version = "1.0",
  revision_id = "RIO_20260905",
  purpose = "Deterministic Figure 12 illustration with the 14 rows visible in the frozen PDF",
  input = list(
    path = "data/folha_classificado.rds",
    rows_selected = 14L,
    source_role = "archived classified headline dataset"
  ),
  outputs = list(
    image = "images/RIO_20260905_table1_headlines_14.png",
    vector_pdf = "images/RIO_20260905_table1_headlines_14.pdf",
    csv = "data/processed/diagnostics/RIO_20260905_figure12/table1_headlines_14.csv"
  ),
  validation = list(
    exact_headline_date_matches = 14L,
    label_matches = 14L,
    empty_categories_shown = FALSE,
    validation_sample_n = 100L,
    validation_sample_unchanged = TRUE
  ),
  source_rows = unname(lapply(seq_len(nrow(sample)), function(i) {
    list(
      display_order = sample$display_order[[i]],
      headline = sample$Headline[[i]],
      classification = sample$Classification[[i]],
      date = sample$Date[[i]]
    )
  }))
)
jsonlite::write_json(manifest, output_manifest, auto_unbox = TRUE, pretty = TRUE)

message("Wrote ", output_image)
message("Wrote ", output_pdf)
message("Wrote ", output_csv)
message("Wrote ", output_manifest)
