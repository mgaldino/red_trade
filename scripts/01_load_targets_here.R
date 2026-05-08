options(scipen = 999)

suppressPackageStartupMessages({
  library(here)
  library(targets)
})

# Carrega as funções do projeto
source(here::here("scripts", "functions.R"))

# Define o banco de dados do {targets}
tar_config_set(store = here::here("_targets"))

# Carrega objetos necessários para os testes de DiD
tar_load(c(
  treatment_events,
  unga_data,
  final_df,
  classified_events,
  usa_top_countries
))

# Resumo rápido para confirmar carga
cat("Objetos carregados com sucesso do banco _targets\n")
cat("Linhas final_df:", nrow(final_df), "\n")
cat("Linhas unga_data:", nrow(unga_data), "\n")
