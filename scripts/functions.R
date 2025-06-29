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
    filter( year > 1989) %>%
    group_by(year, exporter_iso3, importer_iso3) %>%
    dplyr::filter(exporter_iso3 != importer_iso3) %>%
    summarise(exports = sum(trade), .groups = "drop") 
}

rank_trade <- function(data) {
  data %>%
    group_by(year, exporter_iso3) %>%                         # wbcode1 = exporter / “i”
    mutate(rank_from_i = dense_rank(desc(exports))) %>%  # 1 = largest partner
    ungroup() %>% 
    
    ## rank each partner *i* in the portfolio of country *j*
    group_by(year, importer_iso3) %>%                         # wbcode2 = importer / “j”
    mutate(rank_from_j = dense_rank(desc(exports))) %>% 
    ungroup() %>%
    dplyr::filter(importer_iso3 == "CHN")
}

get_folhasp_newspieces <- function(start, end) {
  link <- "https://search.folha.uol.com.br/search?q=china&site=sitefolha&periodo=todos&sort=asc&sr="
  seq_paginas <- seq(1, 100000, by=25)
  lista_df <- list()
  # 2) lê o HTML
  for(i in start:end) {
    url <- paste0(link, seq_paginas[i])
    pg <- read_html(url)
    titles <- html_elements(pg, ".c-headline__title") |> html_text2()
    datas   <- html_elements(pg, "time")       |> html_attr("datetime")
    
    # 4) junta tudo em um data frame
    result <- data.frame(title = titles,
                         data   = datas)
    lista_df[[i]] <- result
    Sys.sleep(1)
  }
  
  df_folha <- bind_rows(lista_df)
  df_folha <- df_folha %>%
    mutate(date_piece = str_extract(data, "[:alnum:]+\\.[:alnum:]+\\.[:alnum:]+"),
           date_piece = gsub("out", "oct", date_piece),
           date_piece = gsub("fev", "feb", date_piece),
           date_piece = gsub("abr", "apr", date_piece),
           date_piece = gsub("mai", "may", date_piece),
           date_piece = gsub("ago", "aug", date_piece),
           date_piece = gsub("set", "sep", date_piece),
           date_piece = gsub("dez", "dec", date_piece),
           date_piece = dmy(date_piece))
  return(df_folha)
}

process_trade_data <- function(file) {
  file %>%
    rename(iso3c = exporter_iso3,
           trade = exports) %>%
    group_by(year, iso3c) %>%           
    summarise(
      trade_with_china = sum(trade[importer_iso3 == "CHN"], na.rm = TRUE),
      trade_with_us    = sum(trade[importer_iso3 == "USA"], na.rm = TRUE),
      total_trade = sum(trade, na.rm=TRUE),
      .groups = "drop"
    )
  
}

rank_trade <- function(data) {
  data %>%
    group_by(year, exporter_iso3) %>%                         # wbcode1 = exporter / “i”
    mutate(rank_from_i = dense_rank(desc(exports))) %>%  # 1 = largest partner
    ungroup() %>% 
    
    ## rank each partner *i* in the portfolio of country *j*
    group_by(year, importer_iso3) %>%                         # wbcode2 = importer / “j”
    mutate(rank_from_j = dense_rank(desc(exports))) %>% 
    ungroup() %>%
    dplyr::filter(importer_iso3 == "CHN")
}


get_unga_data <- function(file, year_filter=1989) {
  fread(file) %>%
    mutate(year = session + 1945) %>%
    clean_names() %>%
    dplyr::filter(year > year_filter) %>%
    group_by(session) %>%
    mutate(china_ideal = q50_percent_all[iso3c == "CHN"],
           us_ideal = q50_percent_all[iso3c == "USA"],
           br_ideal = q50_percent_all[iso3c == "BRA"]) %>%
    ungroup() %>%
    mutate(abs_distance_china = abs(q50_percent_all - china_ideal),
           abs_distance_usa = abs(q50_percent_all - us_ideal)) %>%
    dplyr::select(year, iso3c, ideal_point_all, us_agree, china_agree, china_ideal, us_ideal, br_ideal, 
                  abs_distance_china, abs_distance_usa)
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

plot_ideal_points <- function(data) {
  
  data %>%
    filter(iso3c %in% c("USA", "CHN", "BRA")) %>%
    dplyr::select(year, us_ideal, china_ideal, br_ideal) %>%
    pivot_longer(cols = ends_with("ideal") , names_to = "country", values_to = "ideal") %>%
    mutate(country = toupper(gsub("_ideal", "", country)),
           country = ifelse(country=="US", "USA",
                            ifelse(country == "BR", "BRA", "CHN"))) %>%
    ggplot(aes(x=year, y=ideal, group = country,  colour = country)) + geom_point() +
    geom_smooth(se=F) +
    ylab("Ideal points at UNGA") +
    scale_colour_manual(values = c(USA = "steelblue",
                                   CHN = "firebrick",
                                   BRA = "darkgreen")) +   # pick your colours (optional)
    theme_minimal()
}

plot_distance_unga <- function(data) {
  data %>%
    filter(iso3c %in% c("USA", "CHN", "BRA")) %>%
    dplyr::select(year, us_ideal, china_ideal, br_ideal) %>%
    mutate(distance_br_ch = abs(china_ideal - br_ideal)) %>%
    distinct(year, .keep_all = TRUE) %>%
    ggplot(aes(x=year, y=distance_br_ch)) + geom_point() +
    geom_smooth(se=F) +
    ylab("Absolute distance of Brazil's UNGA ideal points to China") +
    theme_minimal()
}

plot_trade <- function(data){
  data %>%
    dplyr::filter(iso3c == "BRA") %>%
    mutate(perc_trade_with_china = trade_with_china/total_trade) %>%
    ggplot(aes(x=year, y=perc_trade_with_china))  + geom_point() + geom_smooth(se=F) +
    theme_bw() + ylab("Percent of brazilian exports to China") + 
    scale_y_continuous(labels = scales::label_percent()) +
    theme_minimal()
}

clean_synth_data <- function(data) {
  
  synth_data <- data %>%
    group_by(iso3c) %>%
    arrange(iso3c, year) %>% 
    mutate(lag_dis_china = dplyr::lag(abs_distance_china)) %>%
    ungroup() %>%
    mutate(latin_america = region_o %in% c("south_america", "central_america", "north_america") & 
             !iso3c %in% c("USA", "CAN")) %>%
    dplyr::filter(year > 1990 & year < 2012) %>%
    dplyr::select(iso3c, year, pop, abs_distance_china, gdp_cur, ideal_point_all, abs_distance_usa, gpi,
                  us_power_gap, us_ideal, abs_distance_usa, gpi, trade_with_china, trade_with_us, total_trade,
                  distance_us, distance_china, exachange_rate, latin_america) %>%
    arrange(year) %>%
    mutate(pci_cur = gdp_cur/pop,
           perc_trade_with_china = trade_with_china/total_trade,
           perc_trade_with_us = trade_with_us/total_trade) %>%
    tidyr::drop_na() 
  
  exclude_countries <- synth_data %>%
    group_by(iso3c) %>%
    summarise(num_obs = n()) %>%
    dplyr::filter(num_obs < 21) %>%
    pull(iso3c)
  
  synth_data <- synth_data %>%
    dplyr::filter(!iso3c %in% exclude_countries)
  
  
  synth_data <- synth_data %>%
    mutate(treatment = ifelse(iso3c == "BRA" & year > 2004, 1, 0))
  
  df <- synth_data %>%
    mutate(id = as.integer(as.factor(iso3c)))
  
  return(df)
}

cov_matrix <- function(data) {
  mat_X <- data %>%
    mutate(gpi = arm::rescale(gpi),
           perc_trade_with_us = arm::rescale(perc_trade_with_us),
           perc_trade_with_china = arm::rescale(perc_trade_with_china),
           pci_cur = arm::rescale(pci_cur),
           distance_us = arm::rescale(distance_us),
           exachange_rate = arm::rescale(exachange_rate)) %>%
    dplyr::select(year, iso3c, gpi, perc_trade_with_us, perc_trade_with_china, pci_cur,
                  exachange_rate, distance_us, us_power_gap)
  
  cov_levels  <- colnames(mat_X)
  
  X_mat <- array(NA_real_,
                 dim = c(length(unique(mat_X$iso3c)),
                         length(unique(mat_X$year)),
                         ncol(mat_X) - 2))
  
  for (k in 3:ncol(mat_X)) {
    aux <- dplyr::select(mat_X, cov_levels[c(1,2, k)]) %>% pivot_wider(names_from = year, values_from=cov_levels[k]) %>%
      dplyr::select(-iso3c) %>% as.matrix()
    X_mat[ , , k-2] <- aux
  }
  return(X_mat)
}

fit_sdid <- function(data, placebos=TRUE, filter_latin_america) {
  
  if(filter_latin_america) {
    data <- data %>%
      dplyr::filter(latin_america)
  }
  
  data <- data %>%
    mutate(treatment = as.integer(treatment),
           year = as.integer(year),
           iso3c = as.factor(iso3c),
           Y = abs_distance_china) %>%
    dplyr::select(iso3c, year, Y, treatment) %>%
    as.data.frame() # aparentemente panel.matrices não funciona com tibble
  
  
  setup <- panel.matrices(data)
  
  tau.hat = synthdid::synthdid_estimate(setup$Y, setup$N0, setup$T0)
  
}

se_sdid <- function(fitted_model) {
  se = sqrt(vcov(fitted_model, method = 'placebo'))
}

my_plot_trends <- function(fitted_model) {
  plot(fitted_model, treated.name='Brazil', se.method='none') 
}

my_plot_dif <- function(fitted_model) {
  plot(fitted_model, overlay=1,  se.method='none')
}

my_plot_weigths <- function(fitted_model) {
  synthdid_units_plot(fitted_model, se.method='none')
}

my_balance_table <- function(data) {
  data %>% grab_balance_table()
}

