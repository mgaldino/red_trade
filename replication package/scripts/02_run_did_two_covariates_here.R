options(scipen = 999)

suppressPackageStartupMessages({
  library(here)
  library(targets)
  library(dplyr)
  library(tidyr)
  library(readr)
})

# Carrega funções do projeto
source(here::here("scripts", "functions.R"))

# Aponta para o banco de dados do {targets}
tar_config_set(store = here::here("_targets"))

# Carrega os objetos necessários
tar_load(c(
  treatment_events,
  unga_data,
  final_df,
  classified_events,
  usa_top_countries
))

# Monta covariáveis (duas): log_gdp_pc e gpi
covariates_df <- final_df %>%
  mutate(log_gdp_pc = log(gdp_cur / pop)) %>%
  dplyr::select(iso3c, year, log_gdp_pc, gpi) %>%
  tidyr::drop_na()

# Prepara painel completo com covariáveis
event_data_cov <- prepare_event_study_data(
  treatment_events = treatment_events,
  unga_data = unga_data,
  covariates_df = covariates_df
)

# Filtra especificação principal: USA deslocado + controles com USA #1
event_data_cov_usa <- filter_usa_top_control(
  event_data = event_data_cov,
  classified_events = classified_events,
  usa_top_countries = usa_top_countries
)

# Roda DiD com duas covariáveis na amostra completa
att_gt_full <- did::att_gt(
  yname = "abs_distance_china",
  tname = "year",
  idname = "id",
  gname = "first_treat",
  xformla = ~log_gdp_pc + gpi,
  data = as.data.frame(event_data_cov),
  control_group = "nevertreated",
  base_period = "universal"
)
overall_full <- did::aggte(att_gt_full, type = "simple", na.rm = TRUE)

# Roda DiD com duas covariáveis na amostra principal (USA)
att_gt_usa <- did::att_gt(
  yname = "abs_distance_china",
  tname = "year",
  idname = "id",
  gname = "first_treat",
  xformla = ~log_gdp_pc + gpi,
  data = as.data.frame(event_data_cov_usa),
  control_group = "nevertreated",
  base_period = "universal"
)
overall_usa <- did::aggte(att_gt_usa, type = "simple", na.rm = TRUE)

# Tabela simples de saída
results <- tibble::tibble(
  spec = c("all_events", "usa_displaced"),
  att = c(overall_full$overall.att, overall_usa$overall.att),
  se = c(overall_full$overall.se, overall_usa$overall.se),
  p_value = 2 * pnorm(-abs(att / se))
)

write_csv(results, here::here("quality_reports", "did_two_covariates_here.csv"))
print(results)
