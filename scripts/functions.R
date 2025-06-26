# R functions for target

get_exchange_rate_data <- function(from = 1989, end = 2016){
  wb_data("PA.NUS.FCRF", start_date = from, end_date = end) %>%
    rename(year = date,
           exachange_rate = "PA.NUS.FCRF") %>%
    dplyr::select(iso3c, year, exachange_rate )
}

get_country_data <- function(country_file) { 
  fread(country_file) %>%
   # dplyr::select(year, iso3_o, pop_o, gdp_pwt_const_o) %>%
    group_by(year, iso3_o) %>%
    mutate(
      ## 1–2  distances to the reference partners
      distance_us    = first(distance[iso3_d == "USA"]),
      distance_china = first(distance[iso3_d == "CHN"]),
      
      ## 3    same-region indicators
      region_us      = first(region_d[iso3_d == "USA"]),
      region_china   = first(region_d[iso3_d == "CHN"]),
      same_region_us    = region_o == region_us,
      same_region_china = region_o == region_china,
      
      ## 4–5 preferential / free-trade agreements (any PTA-goods **or** FTA)
      pta_us    = first((agree_pta_goods | agree_fta)[iso3_d == "USA"]),
      pta_china = first((agree_pta_goods | agree_fta)[iso3_d == "CHN"]),
      
      ## 6    contiguity with China
      contiguity_china  = first(contiguity[iso3_d == "CHN"])
    ) %>%
    summarise(pop = max(pop_o, na.rm=T),
              region_o = max(region_o, na.rm=T),
              gdp_cur  = max(gdp_pwt_cur_o, na.rm=T),
              distance_us = max(distance_us, na.rm=T),
              distance_china = max(distance_china, na.rm=T),
              region_us = max(region_us, na.rm=T),
              region_china = max(region_china, na.rm=T),
              same_region_us = max(same_region_us, na.rm=T),
              same_region_china = max(same_region_china, na.rm=T),
              pta_us = max(pta_us, na.rm=T),
              pta_china = max(pta_china, na.rm=T),
              colony_ever = max(colony_ever, na.rm=T),
              contiguity_china = max(contiguity_china, na.rm=T),
              .groups= "drop") %>%
    dplyr::filter(is.finite(pop) & is.finite(gdp_cur)) %>%
    rename(iso3c = iso3_o)
}

bind_data <- function(file1, file2, ...) {
  dplyr::bind_rows(file1, file2, ...)
}

get_trade_data <- function(trade_file) {
  fread(trade_file) %>%
    dplyr::select(year, exporter_iso3, importer_iso3, trade) %>%
    filter( year > 1989 & year < 2016) %>%
    group_by(year, exporter_iso3, importer_iso3) %>%
    dplyr::filter(exporter_iso3 != importer_iso3) %>%
    summarise(exports = sum(trade), .groups = "drop") 
}

process_trade_data <- function(file) {
  file %>%
    rename(iso3c = exporter_iso3,
           trade = exports) %>%
    group_by(year, iso3c) %>%           
    summarise(
      trade_with_china = sum(trade[importer_iso3 == "CHN"], na.rm = TRUE),
      trade_with_us    = sum(trade[importer_iso3 == "USA"], na.rm = TRUE),
      .groups = "drop"
    )
  
}

get_unga_data <- function(file, year_filter=1989) {
  fread(file) %>%
    mutate(year = session + 1945) %>%
    clean_names() %>%
    dplyr::filter(year > year_filter) %>%
    group_by(session) %>%
    mutate(china_ideal = q50_percent_all[iso3c == "CHN"],
           us_ideal = q50_percent_all[iso3c == "USA"]) %>%
    ungroup() %>%
    mutate(abs_distance_china = abs(q50_percent_all - china_ideal),
           abs_distance_usa = abs(q50_percent_all - us_ideal)) %>%
    dplyr::select(year, iso3c, ideal_point_all, us_agree, china_agree, china_ideal, us_ideal,abs_distance_china,
                  abs_distance_usa)
}

get_gpi_data <- function(file, year_filter=1989) { 
  read_excel(file,
             sheet = "Global Power Index", skip = 1) %>%
    janitor::clean_names() %>%
    dplyr::select(-world) %>%
    rename(year = x1) %>%
    slice(-(1:2)) %>%
    mutate_all(as.numeric) %>%
    filter(year > year_filter) %>%
    tidyr::pivot_longer(names_to = "country_name", cols=!year, values_to = "gpi") %>%
    dplyr::filter(!grepl("korea$", country_name)) %>%
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
    dplyr::select(country_name, country_clean, iso3c, year, gpi) %>%
    group_by(year) %>%
    mutate(us_power = gpi[iso3c == "USA"]) %>%
    ungroup() %>%
    mutate(us_power_gap = abs(us_power - gpi))
}

join_df <- function(file1, file2, file3, file4, file5) {
  df_joined <- file1 %>%
    inner_join(file2, by = join_by(iso3c, year)) %>%
    inner_join(file3, by = join_by(iso3c, year)) %>%
    inner_join(file4, by = join_by(iso3c, year)) %>%
    inner_join(file5, by = join_by(iso3c, year))
  
}

generate_plot_data <- function(file) {
  file %>%
    dplyr::filter(year < 2016) %>%
    mutate(Brasil_from = iso3c == "BRA") %>%
    group_by(year, Brasil_from) %>%
    summarise(similarity_china_mean = mean(abs_distance_china), .groups = "drop") %>%   # evita aviso
    mutate(Brasil_from = factor(
      Brasil_from,
      levels = c(FALSE, TRUE),
      labels = c("Other Countries", "Brazil")
    ))
}

plot_serie <- function(data) {
  ggplot(data,
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
      breaks = seq(min(data$year), max(data$year), by = 5)
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
  
}

clean_synth_data <- function(data) {
  
  synth_data <- data %>%
    group_by(iso3c) %>%
    arrange(iso3c, year) %>% 
    mutate(lag_dis_china = dplyr::lag(abs_distance_china)) %>%
    ungroup() %>%
    dplyr::filter(year > 1990 & year < 2012) %>%
    dplyr::select(iso3c, year, pop, abs_distance_china, gdp_cur, ideal_point_all, lag_dis_china, abs_distance_usa, gpi,
                  us_power_gap, us_ideal, abs_distance_usa, gpi, trade_with_china, trade_with_us,
                  distance_us, distance_china, region_us, region_china, same_region_us, same_region_china,
                  pta_us, pta_china, colony_ever, contiguity_china, exachange_rate, region_o) %>%
    arrange(year) %>%
    mutate(pci_cur = gdp_cur/pop,
           trade_with_china_pc = trade_with_china/gdp_cur,
           trade_with_us_pc = trade_with_us/gdp_cur)
  
  
  
  exclude_countries <- teste_synth %>% 
    dplyr::filter(is.na(lag_dis_china)) %>%
    dplyr::filter(is.na(exachange_rate)) %>%
    distinct(iso3c)
  
  teste_synth <- teste_synth %>%
    dplyr::filter(!iso3c %in% exclude_countries$iso3c)
  
  teste_synth <- teste_synth %>%
    dplyr::filter(iso3c %in% c("ARG", "AUT", "BEN", "BFA", "BGD", "BGR", "BHS", "BOL", "BRA", "BRB", "BRN",
                                               "BTN", "CAN", "CHL", "CIV", "CMR", "COD", "COL", "CPV", "CRI", "CYP", "DEU",
                                               "DJI", "DNK", "DZA", "ECU", "EGY", "ESP", "FIN", "FJI", "FRA", "GAB", "GBR",
                                               "GHA", "GIN", "GMB", "GTM", "HTI", "HUN", "HND", "IND", "IRL", "IRN", "ISL", "ISR",
                                               "ITA", "IDN", "JAM", "JOR", "JPN", "KEN", "KOR", "KWT", "LAO", "LBN", "LCA",
                                               "LKA", "LSO", "MAR", "MDG", "MDV", "MEX", "MLI", "MLT", "MMR", "MNG", "MOZ",
                                               "MUS", "MWI", "MYS", "NGA", "NIC", "NLD", "NOR",
                                               "NPL", "NZL", "OMN", "PAK", "PAN", "PER", "PHL", "POL", "PRT", "PRY", "QAT",
                                               "ROU", "RWA", "SAU", "SDN", "SEN", "SGP", "SLE", "SLV", "SUR", "SWE", "SWZ", "SYR",
                                               "TGO", "TTO", "TUN", "TUR", "TZA", "UGA", "USA", "URY", "VEN", "YEM","VNM",
                                               "ZWE"))
    # dplyr::filter(region_o %in% c("south_america", "central_america", "north_america", "africa",
    #                               "south_east_asia", "suth_east_asia"))
  
  
  teste_synth <- teste_synth %>%
    mutate(treatment = ifelse(iso3c == "BRA" & year > 2006, 1, 0))
  
  df <- teste_synth %>%
    mutate(event_time = year - 2006,
           id = as.integer(as.factor(iso3c))) %>%
    group_by(iso3c) %>%
    mutate(g = ifelse(iso3c == "BRA", 1988, 0),
           cohort = ifelse(iso3c == "BRA", 1, 0),
           g1 = ifelse(iso3c == "BRA" & year >= 1980, 1980, 0)) %>%
    dplyr::filter(!is.na(exachange_rate))  %>%
    dplyr::filter(year < 2012) %>%
    dplyr::filter(!iso3c %in% c("BFA", "BHR", "LKA", "HND", "ZWE")) %>%
    ungroup()
  return(df)
}

fit_reglin <- function(data) {
  reg <- lm(abs_distance_china ~ gpi + us_power_gap + trade_with_us_pc + trade_with_china_pc + pci_cur + distance_us +
              exachange_rate, data=data)
  y_res <- residuals(reg)
  
}

fit_sdid <- function(data, placebos=TRUE) {
  data <- data %>%
    mutate(treatment = as.integer(treatment),
           year = as.integer(year),
           iso3c = as.factor(iso3c),
           Y = y_res) %>%
    dplyr::select(iso3c, year, Y, treatment) %>%
    as.data.frame() # aparentemente panel.matrices não funciona com tibble
  
  
  setup <- panel.matrices(data)
  
  tau.hat = synthdid::synthdid_estimate(setup$Y, setup$N0, setup$T0)
  
}

se_sdid <- function(fitted_model) {
  se = sqrt(vcov(fitted_model, method = 'placebo'))
}

my_plot_trends <- function(fitted_model) {
  plot(fitted_model, treated.name='Brazil', se.method='placebo') 
}

my_plot_dif <- function(data) {
  data %>% plot_differences()
}

my_plot_weigths <- function(data) {
  data %>% plot_weights()
}

my_balance_table <- function(data) {
  data %>% grab_balance_table()
}

