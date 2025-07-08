library(haven)
library(tidyverse)
library(here)
library(data.table)
library(janitor)
library(rvest)
library(tidysynth)
library(tidyr)
library(countrycode)
library(stringr)
library(comtradr)


# URL of the table
url <- "https://www.iban.com/country-codes"

# Import the table
country_codes <- url %>%
  read_html() %>%
  html_node("table") %>%
  html_table() %>%
  clean_names() %>%
  rename(countryA_alpha2cc = alpha_2_code,
        iso3c = alpha_3_code)

# Display the table
head(country_codes)

## Power index

library(readxl)
gpi <- read_excel("raw data/GPI with sub-components_1816-2050_20241007.xlsx", 
                                                         sheet = "Global Power Index", skip = 1) %>%
  clean_names() %>%
  dplyr::select(-world) %>%
  rename(year = x1) %>%
  slice(-(1:2))
glimpse(gpi)

gpi90 <- gpi %>%
  mutate_all(as.numeric) %>%
  filter(year > 1989) %>%
  pivot_longer(names_to = "country_name", cols=!year, values_to = "gpi") %>%
  filter(!grepl("korea$", country_name))

gpi90_clean <- gpi90 %>% 
  dplyr::filter(!country_name %in% c("baden", "bavaria", "east_germany", "hanover", "hesse_electoral",
                                    "hesse_grand_ducal", "kosovo", "mecklenburg_schwerin", "micronesia",
                                    "modena", "parma", "saharawi_arab_dem_rep", "saxony", "serbia_and_montenegro",
                                    "south_vietnam", "sudan_south", "tuscany", "two_sicilies", "wuerttemburg",
                                    "yugoslavia", "east_germany", "west_germany")) %>%
  mutate(country_clean = country_name %>% 
           str_replace_all("_", " ") %>%           # "_" → " "
           str_squish() %>%                        # trim redundant spaces
           str_to_title(locale = "en"),            # "cote d ivoire" → "Cote D Ivoire"
         
         # 2. ISO-3 lookup (built-in dictionary) ----------------------
         iso3c = countrycode(country_clean,
                             origin      = "country.name",
                             destination = "iso3c")
  ) %>%
  dplyr::select(country_name, country_clean, iso3c, year, gpi)

gpi90_clean <- gpi90_clean %>%
  group_by(year) %>%
  mutate(us_power = gpi[iso3c == "USA"]) %>%
  ungroup() %>%
  mutate(us_power_gap = abs(us_power - gpi))


# gpi90_clean |>
#   dplyr::summarise(n = dplyr::n(), maior = max(country_name), .by = c(year, iso3c)) |>
#   dplyr::filter(n > 1L) |>
#   View()
#trade_data <- read_dta("~/Documents/DCP/Papers/RDD Trade/116365-V1/data/trade_data.dta")
trade_data <- fread(here("raw data", "dataverse_files", "mirrortrade_dyadic.csv"))

glimpse(trade_data)

# trade_data %>%
#   group_by() %>%
#   summarise(n_distinct(countryA_name),
#             n_distinct(trade_pair))

first_trade <- trade_data %>%
  dplyr::filter(year > 1989) %>%
  group_by(ifscode1, year) %>%
  mutate(first = max(flowBAA, na.rm=T))


trade_data <- trade_data %>% 
  dplyr::filter(year > 1989) %>%
  ## rank each partner *j* in the trade portfolio of country *i* for every year
  group_by(year, countryA_name) %>%                         # wbcode1 = exporter / “i”
  mutate(rank_from_i = dense_rank(desc(flowBAA))) %>%  # 1 = largest partner
  ungroup() %>% 
  
  ## rank each partner *i* in the portfolio of country *j*
  group_by(year, countryB_name) %>%                         # wbcode2 = importer / “j”
  mutate(rank_from_j = dense_rank(desc(flowBAA))) %>% 
  ungroup() %>%
  
  ## create the dummies
  mutate(
    Top1_ij_t        = as.integer(rank_from_i == 1),                # i’s No. 1 partner
    Top2_ij_t        = as.integer(rank_from_i == 2),                # i’s No. 2 partner
    MutualTop1_ij_t  = as.integer(rank_from_i == 1 & rank_from_j == 1) # each other’s No. 1
  )

# trade_data %>%
#   group_by() %>%
#   summarise(n_distinct(countryA_name),
#             n_distinct(trade_pair))

trade_data_top1 <- trade_data %>%
  group_by(year, countryA_name) %>%
  mutate(flow_china = ifelse(countryB_name == "China", flowBAA, NA)) %>%
  dplyr::filter(!is.na(flow_china)) %>%
  summarise(flow_china = max(flow_china, na.rm=T),
            countryA_alpha2cc = max(countryA_alpha2cc)) %>%
  ungroup() %>%
  inner_join(country_codes, by = join_by(countryA_alpha2cc))

## UNGA vote

unga_data <- fread(here("raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv"))
unga_data <- unga_data  %>%
  mutate(year = session + 1945)

unga_data_90 <- unga_data %>%
  clean_names() %>%
  dplyr::filter(year > 1989) %>%
  group_by(session) %>%
  mutate(china_ideal = q50_percent_all[iso3c == "CHN"],
         us_ideal = q50_percent_all[iso3c == "USA"]) %>%
  ungroup() %>%
  mutate(abs_distance_china = abs(q50_percent_all - china_ideal),
         abs_distance_usa = abs(q50_percent_all - us_ideal))

# joining

trade_data_unga <- trade_data_top1 %>%
  inner_join(unga_data_90, by = join_by(iso3c, year)) %>%
  inner_join(gpi90_clean, by = join_by(iso3c, year))
  
plot_data <- trade_data_unga %>%
  dplyr::filter(year < 2016) %>%
  mutate(Brasil_from = countryA_name == "Brazil") %>%
  group_by(year, Brasil_from) %>%
  summarise(similarity_china_mean = mean(abs_distance_china), .groups = "drop") %>%   # evita aviso
  mutate(Brasil_from = factor(
    Brasil_from,
    levels = c(FALSE, TRUE),
    labels = c("Other Countries", "Brazil")
  ))

ggplot(plot_data,
       aes(x = year, y = similarity_china_mean,
           colour = Brasil_from,
           linetype = Brasil_from)) +
  geom_line(linewidth = 1) +
  ## linha vertical de referência
  geom_vline(
    aes(xintercept = 2007,
        colour = "China second partner",
        linetype = "China second partner"),
    linewidth = 0.8,
    show.legend = TRUE
  ) +
  ## escalas com as três categorias
  scale_colour_manual(
    values = c(
      "Other Countries" = "#2166ac",
      "Brazil"     = "#b2182b",
      "China second partner" = "black"
    )
  ) +
  scale_linetype_manual(
    values = c(
      "Other Countries" = "dashed",
      "Brazil"     = "solid",
      "China second partner" = "dotted"
    )
  ) +
  scale_x_continuous(
    breaks = seq(min(plot_data$year), max(plot_data$year), by = 5)
  ) +
  labs(
    title    = "Political Alignment with China",
    x        = "Year",
    y        = "UNGA vote Disimilarity with China",
    colour   = "",
    linetype = ""
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position.inside = c(0.80, 0.88),
    legend.background      = element_rect(fill = "white", colour = "grey80")
  )

# Controle sintético

# trade_data_unga %>%
#   filter(iso3c == "BRA")

trade_data_unga <- trade_data_unga %>%
  group_by(iso3c) %>%
  arrange(iso3c, year) %>% 
  mutate(lag_dis_china = dplyr::lag(abs_distance_china)) %>%
  dplyr::filter(year > 1990)

trade_data_unga_synth <- trade_data_unga %>%
  ungroup() %>%
  dplyr::select(iso3c, year, abs_distance_china, lag_dis_china, flow_china, abs_distance_usa, gpi,
                us_power_gap) %>%
  arrange(year)

exclude_countries <- trade_data_unga_synth %>% 
  dplyr::filter(is.na(lag_dis_china)) %>%
  distinct(iso3c)

trade_data_unga_synth <- trade_data_unga_synth %>%
  dplyr::filter(!iso3c %in% exclude_countries$iso3c)

bad_units <- trade_data_unga_synth %>% 
  # keep only the predictor window
  dplyr::filter(year %in% 1991:2006) %>% 
  # count how many observations each unit has
  count(iso3c, name = "n_window_obs") %>% 
  # units with zero rows are the culprits
  filter(n_window_obs < 16) %>% 
  pull(iso3c)

trade_data_unga_synth <- trade_data_unga_synth %>%
  dplyr::filter(!iso3c %in% bad_units)


trade_data_unga_synth_out <-
  trade_data_unga_synth %>%
  
  # initial the synthetic control object
  synthetic_control(outcome = abs_distance_china,
                    unit = iso3c,
                    time = year,
                    i_unit = "BRA",
                    i_time = 2006,
                    generate_placebos= FALSE) %>%
  
  # Generate the aggregate predictors used to generate the weights
  generate_predictor(time_window = 1991:2006,
                     flow_china = mean(flow_china, na.rm = TRUE),
                     lag_dis_china = mean(lag_dis_china, na.rm = TRUE),
                     abs_distance_usa = mean(abs_distance_usa, na.rm=TRUE),
                     gpi = mean(gpi, na.rm=TRUE),
                     us_power_gap = mean(us_power_gap, na.rm = TRUE)) %>%
  
  # Generate the fitted weights for the synthetic control
  generate_weights(optimization_window =1991:2006,
                   Margin.ipop=.02,Sigf.ipop=7,Bound.ipop=6) %>%
  
  # Generate the synthetic control
  generate_control()

# Plot the observed and synthetic trend
trade_data_unga_synth_out %>% plot_trends(time_window = 1991:2015)

trade_data_unga_synth_out %>% plot_differences()

trade_data_unga_synth_out %>% plot_weights()

trade_data_unga_synth_out %>% grab_balance_table()

trade_data_unga_synth_out %>% plot_placebos()

# Synt DiD

library(synthdid)

trade_data_unga_synth_did <- teste %>%
  mutate(treatment = ifelse(iso3c == "BRA" & year > 2006, 1, 0))

df <- trade_data_unga_synth_did %>%
  mutate(event_time = year - 2006,
         id = as.integer(as.factor(iso3c))) %>%
  group_by(iso3c) %>%
  mutate(g = ifelse(iso3c == "BRA", 1988, 0),
         cohort = ifelse(iso3c == "BRA", 1, 0),
         g1 = ifelse(iso3c == "BRA" & year >= 1980, 1980, 0))

estimators = list(sdid=synthdid_estimate)


# converte para matriz

df <- df %>%
  dplyr::filter(!is.na(exachange_rate))  %>%
  dplyr::filter(year < 2012) %>%
  dplyr::filter(!iso3c %in% c("BFA", "BHR", "LKA", "HND", "ZWE"))

reg <- lm(abs_distance_china ~ gpi + us_power_gap + trade_with_us_pc + trade_with_china_pc + pci_cur + distance_us +
            exachange_rate, data=df)
y_res <- residuals(reg)


df_sdid <- df %>%
  dplyr::filter(!iso3c %in% c("BFA", "BHR", "LKA", "HND", "ZWE")) %>% # painel balanceado
  dplyr::filter(year < 2012) %>%
  dplyr::select(iso3c, year, treatment) %>%
  ungroup() %>%
  mutate(treatment = as.integer(treatment),
         year = as.integer(year),
         iso3c = as.factor(iso3c),
         Y = y_res) %>%
  dplyr::select(iso3c, year, Y, treatment) %>%
  as.data.frame() # aparentemente panel.matrices não funciona com tibble

# df_sdid %>%
#   group_by(iso3c) %>%
#   summarise(num_obs = n()) %>%
#   arrange(num_obs)

setup <- panel.matrices(df_sdid)

tau.hat = synthdid::synthdid_estimate(setup$Y, setup$N0, setup$T0)

(se = sqrt(vcov(tau.hat, method = 'placebo')))
# coef
tau.hat[1]
z_score <- tau.hat[1]/se
pnorm(z_score)
plot(tau.hat, treated.name='Brazil') 

synthdid_plot(tau.hat, facet.vertical=FALSE,
              control.name='control', treated.name='BRA',
              lambda.comparable=TRUE, se.method = 'none',
              trajectory.linetype = 1, line.width=.75, effect.curvature=-.4,
              trajectory.alpha=.7, effect.alpha=.7,
              diagram.alpha=1, onset.alpha=.7) 


estimates <- lapply(estimators, function(estimator) { estimator(setup$Y,
                                                                setup$N0, setup$T0) } )

head(estimates)

standard.errors = mapply(function(estimate, name) {
  set.seed(12345)
  if(name == 'mc') { mc_placebo_se(setup$Y, setup$N0, setup$T0) }
  else {             sqrt(vcov(estimate, method='placebo'))     }
}, estimates, names(estimators))

head(standard.errors)

synthdid_plot(estimates[1], facet.vertical=FALSE,
              control.name='control', treated.name='BRA',
              lambda.comparable=TRUE, se.method = 'none',
              trajectory.linetype = 1, line.width=.75, effect.curvature=-.4,
              trajectory.alpha=.7, effect.alpha=.7,
              diagram.alpha=1, onset.alpha=.7) 

synthdid_units_plot(rev(estimates[1]), se.method='none') 




##


df_sdid <- df %>%
  dplyr::filter(!iso3c %in% c("BFA", "BHR", "LKA", "HND", "ZWE")) %>% # painel balanceado
  dplyr::filter(year < 2012) %>%
  dplyr::select(iso3c, year, treatment, abs_distance_china) %>%
  ungroup() %>%
  mutate(treatment = as.integer(treatment),
         year = as.integer(year),
         iso3c = as.factor(iso3c),
         Y = abs_distance_china) %>%
  dplyr::select(iso3c, year, Y, treatment) %>%
  as.data.frame() # aparentemente panel.matrices não funciona com tibble

# df_sdid %>%
#   group_by(iso3c) %>%
#   summarise(num_obs = n()) %>%
#   arrange(num_obs)

setup <- panel.matrices(df_sdid)

tau.hat = synthdid::synthdid_estimate(setup$Y, setup$N0, setup$T0)

(se = sqrt(vcov(tau.hat, method = 'placebo')))
# coef
tau.hat[1]
z_score <- tau.hat[1]/se
pnorm(z_score)
plot(tau.hat, treated.name='Brazil', se.method='placebo') 

synthdid_units_plot(tau.hat, se.method='placebo')

# checking parallel trends
plot(tau.hat, overlay=1,  se.method='placebo')
