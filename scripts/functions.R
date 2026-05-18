#############################
### R functions for target
#############################

## First, functions to get data from online sources

# Exchange Rate Data
get_wb_data <- function(from = 1989, end = 2020){
  wb_data(c("PA.NUS.FCRF", "SP.POP.TOTL", "GC.TAX.TOTL.GD.ZS", "NY.GDP.MKTP.CD", "NY.GDP.MKTP.KD", "NY.GDP.MKTP.KD.ZG"), start_date = from, end_date = end) %>%
    rename(year = date,
           exachange_rate = PA.NUS.FCRF,
           pop = SP.POP.TOTL,
           tax_share_gdp = GC.TAX.TOTL.GD.ZS,
           gdp_cur = NY.GDP.MKTP.CD,
           gdp_constant15 = NY.GDP.MKTP.KD,
           gdp_growth = NY.GDP.MKTP.KD.ZG) %>%
    dplyr::select(iso3c, year, exachange_rate, pop, tax_share_gdp, gdp_cur, gdp_constant15,  gdp_growth)
}

# Folha de São Paulo newspaper scrapping
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


## Second, functions to get data from local files, manually downloaded

# Country information data
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

get_country_data2 <- function() {
  years <- 1989:2020   # 32 years

  countries <- wb_countries("en")
  countries <- countries %>%
    mutate(long_us = longitude[iso3c == "USA"],
           lat_us = latitude[iso3c == "USA"],
           long_china = longitude[iso3c == "CHN"],
           lat_china = latitude[iso3c == "CHN"])
  vec1 <- cbind(countries$longitude, countries$latitude)
  vec2 <- cbind(countries$long_us, countries$lat_us)
  vec3 <- cbind(countries$long_china, countries$lat_china)
  distance_us <- numeric()
  for ( i in 1:nrow(countries)) {
    distance_us[i] <- distGeo(vec1[i,], vec2[i,])/1000
  }
  
  distance_china <- numeric()
  for ( i in 1:nrow(countries)) {
    distance_china[i] <- distGeo(vec1[i,], vec3[i,])/1000
  }
  
  countries <- countries %>%
    mutate(distance_us = distance_us,
           distance_china = distance_china) %>%
    dplyr::select(iso3c, distance_us, distance_china, region)
  
  countries <- tidyr::crossing(countries, year = years)
  return(countries)

}
# Trade data
get_trade_data <- function(trade_file) {
  fread(trade_file) %>%
    dplyr::select(year, exporter_iso3, importer_iso3, trade) %>%
    filter( year > 1989) %>%
    group_by(year, exporter_iso3, importer_iso3) %>%
    dplyr::filter(exporter_iso3 != importer_iso3) %>%
    summarise(exports = sum(trade), .groups = "drop") 
}

# Power index data
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

# DPI (Database of Political Institutions, Cruz et al. 2021)
get_dpi_data <- function(file) {
  dpi <- fread(file)

  # Replace -999 with NA (DPI missing code)
  dpi[dpi == -999] <- NA

  dpi_final <- dpi %>%
    dplyr::filter(ifs != "0") %>%
    mutate(inst_parliamentary = ifelse(system == 2, 1, 0),
           inst_military_exec = ifelse(military == 1, 1, 0)) %>%
    dplyr::select(ifs, year, inst_parliamentary, inst_military_exec) %>%
    rename(iso3c = ifs) %>%
    # Fix legacy IFS codes to ISO 3166-1 alpha-3
    mutate(iso3c = case_match(iso3c, "ROM" ~ "ROU", .default = iso3c)) %>%
    arrange(iso3c, year)

  # Forward-fill to 2020 (DPI covers up to 2015; institutional vars change slowly)
  all_combos <- tidyr::expand_grid(
    iso3c = unique(dpi_final$iso3c),
    year = min(dpi_final$year):2020
  )

  dpi_final <- all_combos %>%
    left_join(dpi_final, by = c("iso3c", "year")) %>%
    group_by(iso3c) %>%
    tidyr::fill(inst_parliamentary, inst_military_exec, .direction = "down") %>%
    ungroup() %>%
    drop_na(inst_parliamentary, inst_military_exec)

  return(dpi_final)
}

# US Trade Agreement (from Dynamic Gravity Database release_2)
get_us_trade_agreement <- function(file1, file2, file3, file4, file5) {
  # Bind all release_2 files
  all_data <- bind_rows(
    fread(file1),
    fread(file2),
    fread(file3),
    fread(file4),
    fread(file5)
  )

  # Replace -999 with NA
  all_data[all_data == -999] <- NA

  # Filter to dyads with USA as destination, extract agreement indicators
  us_agreements <- all_data %>%
    dplyr::filter(iso3_d == "USA") %>%
    mutate(us_trade_agreement = as.integer(
      agree_pta_goods == 1 | agree_fta == 1 | agree_eia == 1 |
      agree_cu == 1 | agree_fta_eia == 1 | agree_cu_eia == 1
    )) %>%
    # Replace NA with 0 (no agreement info = no agreement)
    mutate(us_trade_agreement = tidyr::replace_na(us_trade_agreement, 0L)) %>%
    dplyr::select(iso3c = iso3_o, year, us_trade_agreement) %>%
    group_by(iso3c, year) %>%
    summarise(us_trade_agreement = max(us_trade_agreement, na.rm = TRUE), .groups = "drop")

  return(us_agreements)
}

get_ideology_data <- function(ideology_data){
  
  ideology <- data.table::fread(ideology_data)
  
  cow_iso <- fread("https://raw.githubusercontent.com/leops95/cow2iso/refs/heads/master/cow2iso.csv") %>%
    dplyr::select(cow_id, iso3) %>%
    distinct(cow_id, .keep_all = TRUE) %>%
    rename(iso3c = iso3)
  
  ideology <- ideology %>%
    inner_join(cow_iso, by = join_by(country_code_cow == cow_id)) %>%
    rename(region2 = region) %>%
    dplyr::select(year, iso3c, hog, hog_ideology, hog_left, hog_right, hog_center,
                  hog_party, hog_ideology_bls, leader_ideology_m, region2) %>%
    dplyr::filter(!is.na(hog_left))
  
}
get_macro <- function() {
  df <- gmd(version = "2025_06", variables = c("rGDP","CA_GDP","govdef_GDP",
                                               "SovDebtCrisis"))
  df <- df %>%
    filter(year > 1989) %>%
    rename(iso3c = ISO3)
  
  return(df)
}

####################
## Data Wrangling
####################

## Binding country data (had to download separate files due to size)
bind_data <- function(file1, file2, ...) {
  dplyr::bind_rows(file1, file2, ...)
}

# UNGA data
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


# process trade data
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

# create rank of trade partners
# needed to identify treatment period
rank_trade <- function(data) {
  data %>%
    group_by(year, exporter_iso3) %>%                         # wbcode1 = exporter / “i”
    mutate(rank_from_i = dense_rank(desc(exports))) %>%  # 1 = largest partner
    ungroup() %>% 
    
    ## rank each partner *i* in the portfolio of country *j*
    group_by(year, importer_iso3) %>%                         # wbcode2 = importer / “j”
    mutate(rank_from_j = dense_rank(desc(exports))) %>% 
    ungroup() %>%
    dplyr::filter(importer_iso3 == "CHN") %>%
    mutate(treatment_first = ifelse(rank_from_i == 1, 1, 0),
           treatment_second = ifelse(rank_from_i == 2, 1, 0)) %>%
    rename(iso3c = exporter_iso3)
    
}

# join country data into a single data.frame
join_df <- function(file1, file2, file3, file4, file5, file6, file7) {
  df_joined <- file1 %>%
    inner_join(file2, by = join_by(iso3c, year)) %>%
    inner_join(file3, by = join_by(iso3c, year)) %>%
    inner_join(file4, by = join_by(iso3c, year)) %>%
    inner_join(file5, by = join_by(iso3c, year)) %>%
    inner_join(file6, by = join_by(iso3c, year)) %>%
    inner_join(file7, by = join_by(iso3c, year))
  
}

# bind Folha de São Paulo data
bind_folha <- function(data1, data2, data3, data4, data5) {
  bind_rows(data1, data2, data3, data4, data5)
}

#############################
#### Plot  ####
#############################

## First, descriptive plots

# Basic plot
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

# Frequency of headlines per year plot
folha_plot <- function(data ) {
  start <- as.Date("1999-01-01")
  end   <- as.Date("2014-12-31")
  
  data %>%
    mutate(year_month = dmy(paste("1", month(date_piece), year(date_piece), sep="-")),
           year_month = as.Date(year_month)) %>%
    filter(year(year_month) > 1998) %>%
    filter(date_piece < "2014-01-01") %>%
    group_by(year_month) %>%
    summarise(num = n()) %>%
    ggplot(aes(x=year_month, y=num)) + geom_col() + theme_bw() +
    theme(axis.line = element_line(colour = "black"),
          panel.grid.minor = element_blank(),
          panel.background = element_blank()) +
    scale_x_date(
      breaks      = seq(start, end, by = "2 years"),
      minor_breaks = seq(start %m+% months(6), end, by = "2 years"),
      date_labels = "%b %y"
    ) +
    ylab("Number of pieces published") + xlab("date")
}

## UNGA ideal point serie plot
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

## Comparative ideal points plot
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

# Trigram Plot
create_list_graphs <- function(data, start, end=NA, num_by, n_filter) {
  data$date_piece[1] <- as.Date("2008-06-07", "%Y-%m-%d")
  
  folha <- data %>%
    mutate(year = lubridate::year(date_piece))
  
  stop_pt <- stopwords(source = "stopwords-iso",
                       language = "pt")
  
  folha_2000 <- folha %>%
    filter(year > 2002 & year < 2014)
  
  year_filter <- sort(unique(folha_2000$year))
  
  plots   <- list()       # lista vazia
  idx     <- 1   
  
  if(is.na(end)) {
    end <- length(year_filter) 
  }
  for (i  in seq(start, end, num_by)) {
    
    data <- folha_2000 %>%
      filter(year == year_filter[i])
    
    tidy_folha <- data %>%
      unnest_tokens(trigram, title, token = "ngrams", n = 3, drop = FALSE) %>%
      separate(trigram, into = c("w1", "w2", "w3"), sep = " ") %>%
      filter(!w1 %in% stop_pt,
             !w2 %in% stop_pt,
             !w3 %in% stop_pt)
    
    ## 2. Converter cada trigram em 2 pares (w1-w2, w2-w3) ------------------
    edges <- bind_rows(
      tidy_folha %>% count(from = w1, to = w2,  name = "n"),
      tidy_folha %>% count(from = w2, to = w3,  name = "n")
    ) %>%
      group_by(from, to) %>%                # agrega se aparecer em >1 trigram
      summarise(n = sum(n), .groups = "drop") %>%
      filter(n > n_filter)                        # seu corte
    
    ## 3. Criar grafo --------------------------------------------------------
    set.seed(1234)
    trigram_graph <- graph_from_data_frame(edges, directed = FALSE)
    
    ## 4. Plotar -------------------------------------------------------------
    a <- grid::arrow(type = "closed", length = unit(3, "mm"), angle  = 15)
    
    plots[[idx]] <- ggraph(trigram_graph, layout = "fr") +
      geom_edge_link(aes(edge_alpha = n),
                     arrow     = a,
                     end_cap   = circle(.05, 'inches'),
                     show.legend = FALSE) +
      geom_node_point(color = "lightblue", size = 2) +
      geom_node_text(aes(label = name), vjust = 1, hjust = 1, size = 2.5) +
      theme_void() +
      ggtitle(year_filter[i])
    
    idx <- idx + 1    
    
  }
  return(plots)
}

## Distance ideal point between Brazil and China plot
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

# Trade plot
plot_trade <- function(data){
  data %>%
    dplyr::filter(iso3c == "BRA") %>%
    mutate(perc_trade_with_china = trade_with_china/total_trade) %>%
    ggplot(aes(x=year, y=perc_trade_with_china))  + geom_point() + geom_smooth(se=F) +
    theme_bw() + ylab("Percent of brazilian exports to China") + 
    scale_y_continuous(labels = scales::label_percent()) +
    theme_minimal()
}

prepare_data_folha <- function(data) {
  data %>%
    mutate(subject = str_trim(subject),
           subject = gsub("brasil", "brazil", subject),
           year = year(date_piece)) %>%
    group_by(year, subject) %>%
    summarise(num = n()) %>%
    arrange(year, num) %>%
    ungroup() %>%
    mutate(total = sum(num), .by=year) %>%
    pivot_wider(names_from = subject, values_from = num) %>%
    clean_names() 
}

growth_plot <- function(data) {
  data %>%
    mutate(subject = str_trim(subject),
           subject = gsub("brasil", "brazil", subject),
           year = year(date_piece)) %>%
    group_by(year, subject) %>%
    summarise(num = n()) %>%
    arrange(subject, year) %>%
    filter(grepl("trade|economy|health|accident" ,subject )) %>%
    filter(year > 2005) %>%
    ungroup() %>%
    group_by(subject) %>%
    mutate(log_num = log(num),
           lag = lag(num),
           log_lag = log(lag),
           perc_diff = log_num - log_lag) %>%
    filter(!is.na(log_lag)) %>%
    ggplot(aes(x=year, y=perc_diff)) + geom_line() + geom_point() + 
    facet_wrap(~ subject, ncol=1, scales = "free") + theme_bw() +
    ylab("Year over Year Growth") + scale_y_continuous(labels = scales::label_percent())
}

descriptive_plot_folha <- function() {
  
}

##############
# Modeling
##############

# prep data for SDiD

## clean dataset
clean_synth_data <- function(data, ranked_trade_data, year_end = 2017,
                             dpi_data = NULL, trade_agreement_data = NULL) {

  synth_data <- data %>%
    group_by(iso3c) %>%
    arrange(iso3c, year) %>%
    ungroup() %>%
    mutate(latin_america = (region2 == "Latin America and Caribbean"|
             iso3c == "MEX")) %>%
    dplyr::filter(year > 1996 & year < 2020) %>%
    dplyr::select(iso3c, year, pop, abs_distance_china, gdp_cur, ideal_point_all, abs_distance_usa, gpi,
                  us_power_gap, us_ideal, abs_distance_usa, gpi, trade_with_china, trade_with_us, total_trade,
                  distance_us, distance_china, exachange_rate, latin_america, hog_left, CA_GDP,
                  govdef_GDP, gdp_growth)

  # Join institutional covariates if provided
  if (!is.null(dpi_data)) {
    synth_data <- synth_data %>%
      left_join(dpi_data, by = c("iso3c", "year"))
  }
  if (!is.null(trade_agreement_data)) {
    synth_data <- synth_data %>%
      left_join(trade_agreement_data, by = c("iso3c", "year"))
  }

  synth_data <- synth_data %>%
    arrange(year) %>%
    mutate(pci_cur = gdp_cur/pop,
           perc_trade_with_china = trade_with_china/total_trade,
           perc_trade_with_us = trade_with_us/total_trade) %>%
    drop_na()
  
  
  synth_data <- synth_data %>%
    inner_join(dplyr::select(ranked_trade_data, year, iso3c, treatment_first, treatment_second), by = join_by(year, iso3c)) %>%
    mutate(treatment = ifelse(iso3c == "BRA" & treatment_first == 1, 1, 0),
           condition = treatment_first == 1 & treatment == 0) %>%
    filter( year < year_end) %>%
    dplyr::filter(!condition)
  
  exclude_countries <- synth_data %>%
    group_by(iso3c) %>%
    summarise(num_obs = n()) %>%
    dplyr::filter(num_obs < max(num_obs, na.rm=T)) %>%
    pull(iso3c)
  
  
  synth_data <- synth_data %>%
    dplyr::filter(!iso3c %in% exclude_countries)
  
  

  
  df <- synth_data %>%
    mutate(id = as.integer(as.factor(iso3c))) %>%
    mutate(gpi = arm::rescale(gpi),
           us_power_gap = arm::rescale(us_power_gap),
           perc_trade_with_us = arm::rescale(perc_trade_with_us),
           perc_trade_with_china = arm::rescale(perc_trade_with_china),
           pci_cur = arm::rescale(pci_cur),
           distance_us = arm::rescale(distance_us),
           exachange_rate = arm::rescale(exachange_rate),
           CA_GDP = arm::rescale(CA_GDP),
           govdef_GDP = arm::rescale(govdef_GDP)) %>%
    dplyr::select(year, iso3c, treatment, abs_distance_china, gpi, abs_distance_usa, perc_trade_with_us, perc_trade_with_china, pci_cur,
                  exachange_rate, distance_us, us_power_gap, hog_left, CA_GDP, latin_america,
                  govdef_GDP,
                  any_of(c("inst_parliamentary", "inst_military_exec", "us_trade_agreement")))
  
  return(df)
}


## Create preditcor matrix
cov_matrix <- function(data) {
  mat_X <- data %>%
    dplyr::select(year, iso3c, gpi, perc_trade_with_us, perc_trade_with_china, pci_cur,
                  exachange_rate, distance_us, us_power_gap, hog_left, CA_GDP,
                  govdef_GDP,
                  any_of(c("inst_parliamentary", "inst_military_exec", "us_trade_agreement")))
  
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

# fit sdid
simple_fit <- function(data, time_treatment=2008, time_end=2016, filter_latin_america=FALSE) {
  set.seed(12345)
  if(filter_latin_america) {
    data <- data %>%
      dplyr::filter(latin_america)
  }

  data <- data %>%
    dplyr::filter(year < time_end) %>%
    mutate(treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1, 0))

  # Sort data: controls first (alphabetically), then treated unit (BRA) last.
  # This ensures cov_matrix() and panel.matrices() see rows in the same order.
  data <- data %>%
    mutate(.unit_treated = as.integer(iso3c == "BRA")) %>%
    arrange(.unit_treated, iso3c, year) %>%
    dplyr::select(-.unit_treated)

  covariates <- cov_matrix(data)

  data <- data %>%
    mutate(treatment = as.integer(treatment),
           year = as.integer(year),
           iso3c = as.factor(iso3c),
           Y = abs_distance_china) %>%
    dplyr::select(iso3c, year, Y, treatment) %>%
    as.data.frame() # aparentemente panel.matrices não funciona com tibble


  setup <- panel.matrices(data)

  tau.hat = synthdid::synthdid_estimate(Y=setup$Y, N0=setup$N0, T0=setup$T0, X=covariates)
}


## compute standard error (plecebos method)
se_sdid <- function(fitted_model) {
  se = sqrt(vcov(fitted_model, method = 'placebo'))
}

############################
## Inferential/results plots
############################

my_plot_trends <- function(fitted_model) {
  plot(fitted_model, treated.name='Brazil', se.method='none') 
}

my_plot_dif <- function(fitted_model) {
  plot(fitted_model, overlay=1,  se.method='placebo')
}

my_plot_weigths <- function(fitted_model, latam=F) {
  if(latam == T) {
    top.controls = synthdid_controls(fitted_model)[, , drop=FALSE]
    synthdid_units_plot(fitted_model, se.method='placebo', units = rownames(top.controls))
  } else {
    top.controls = synthdid_controls(fitted_model)[1:10, , drop=FALSE]
    synthdid_units_plot(fitted_model, se.method='placebo', units = rownames(top.controls))
  }

}

plot_controls <- function(fitted_model) {
  top.controls = synthdid_controls(fitted_model)[1:10, , drop=FALSE]
  plot(fitted_model, spaghetti.units=rownames(top.controls))
}

############################
## Phase 1: SDiD Diagnostics
############################

# Phase 1.1: RMSPE Diagnostics
compute_rmspe <- function(fit) {
  setup <- attr(fit, 'setup')
  Y <- setup$Y
  N0 <- setup$N0
  T0 <- setup$T0

  weights <- attr(fit, 'weights')
  omega <- weights$omega  # unit weights (N0 x 1)

  # Synthetic control = weighted average of control units
  Y_treated <- Y[N0 + 1, ]
  Y_controls <- Y[1:N0, , drop = FALSE]
  Y_synthetic <- as.numeric(t(omega) %*% Y_controls)

  # Pre- and post-treatment residuals
  residuals_pre  <- Y_treated[1:T0] - Y_synthetic[1:T0]
  residuals_post <- Y_treated[(T0 + 1):ncol(Y)] - Y_synthetic[(T0 + 1):ncol(Y)]

  rmspe_pre  <- sqrt(mean(residuals_pre^2))
  rmspe_post <- sqrt(mean(residuals_post^2))
  ratio <- rmspe_post / rmspe_pre

  list(
    rmspe_pre = rmspe_pre,
    rmspe_post = rmspe_post,
    ratio = ratio,
    residuals_pre = residuals_pre,
    residuals_post = residuals_post,
    Y_treated = Y_treated,
    Y_synthetic = Y_synthetic
  )
}

# Phase 1.1: Permutation Inference (placebo-in-space)
permutation_test <- function(data, time_treatment = 2008, time_end = 2016) {
  set.seed(12345)

  # Same filtering as simple_fit
  base_data <- data %>%
    dplyr::filter(year < time_end)

  countries <- sort(unique(base_data$iso3c))

  results <- list()

  for (i in seq_along(countries)) {
    country <- countries[i]

    # Assign treatment to this country instead of BRA
    perm_data <- base_data %>%
      mutate(treatment = ifelse(iso3c == country & year > time_treatment, 1, 0))

    # Sort: controls first, treated unit last
    perm_data <- perm_data %>%
      mutate(.unit_treated = as.integer(iso3c == country)) %>%
      arrange(.unit_treated, iso3c, year) %>%
      dplyr::select(-.unit_treated)

    tryCatch({
      covariates <- cov_matrix(perm_data)

      panel_data <- perm_data %>%
        mutate(treatment = as.integer(treatment),
               year = as.integer(year),
               iso3c = as.factor(iso3c),
               Y = abs_distance_china) %>%
        dplyr::select(iso3c, year, Y, treatment) %>%
        as.data.frame()

      setup <- panel.matrices(panel_data)
      fit <- synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0,
                                         T0 = setup$T0, X = covariates)

      rmspe_result <- compute_rmspe(fit)

      results[[i]] <- data.frame(
        iso3c = country,
        estimate = as.numeric(fit),
        rmspe_pre = rmspe_result$rmspe_pre,
        rmspe_post = rmspe_result$rmspe_post,
        ratio = rmspe_result$ratio,
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      results[[i]] <<- data.frame(
        iso3c = country,
        estimate = NA_real_,
        rmspe_pre = NA_real_,
        rmspe_post = NA_real_,
        ratio = NA_real_,
        stringsAsFactors = FALSE
      )
    })
  }

  result_df <- bind_rows(results)

  # p-value: fraction of units with RMSPE ratio >= Brazil's
  brazil_ratio <- result_df$ratio[result_df$iso3c == "BRA"]
  if (length(brazil_ratio) == 1 && !is.na(brazil_ratio)) {
    result_df$p_value <- mean(result_df$ratio >= brazil_ratio, na.rm = TRUE)
  } else {
    result_df$p_value <- NA_real_
  }

  result_df
}

# Phase 1.2: Sensitivity Analysis (specification curve)
# Note: SE computation skipped here (placebo vcov takes ~12 min per spec).
# The main estimate + SE are computed in dedicated targets (synth_fit, se_synth, etc.).
sensitivity_analysis <- function(synth_data, synth_data_extended) {
  specs <- expand.grid(
    time_end = c(2014, 2016, 2018, 2020),
    time_treatment = c(2007, 2008, 2009),
    filter_latin_america = c(FALSE, TRUE),
    stringsAsFactors = FALSE
  )

  results <- list()

  for (i in 1:nrow(specs)) {
    s <- specs[i, ]

    # Use base data for windows within original range, extended otherwise
    data <- if (s$time_end <= 2016) synth_data else synth_data_extended

    tryCatch({
      fit <- simple_fit(data,
                        time_treatment = s$time_treatment,
                        time_end = s$time_end,
                        filter_latin_america = s$filter_latin_america)

      results[[i]] <- data.frame(
        spec_id = i,
        time_end = s$time_end,
        time_treatment = s$time_treatment,
        filter_latin_america = s$filter_latin_america,
        estimate = as.numeric(fit),
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      results[[i]] <<- data.frame(
        spec_id = i,
        time_end = s$time_end,
        time_treatment = s$time_treatment,
        filter_latin_america = s$filter_latin_america,
        estimate = NA_real_,
        error_msg = conditionMessage(e),
        stringsAsFactors = FALSE
      )
    })
  }

  bind_rows(results)
}

# Phase 1.4: Donor Pool Composition Table
donor_pool_table <- function(fit, unga_data, trade_data_cleaned) {
  # Extract omega weights
  omega <- synthdid_controls(fit)

  countries <- data.frame(
    iso3c = rownames(omega),
    omega_weight = as.numeric(omega),
    stringsAsFactors = FALSE
  )

  countries$country_name <- countrycode(countries$iso3c, "iso3c", "country.name")
  countries$region <- countrycode(countries$iso3c, "iso3c", "region")

  # Trade share with China in last pre-treatment year
  trade_pre <- trade_data_cleaned %>%
    dplyr::filter(year == 2008) %>%
    mutate(trade_share_china = trade_with_china / total_trade) %>%
    dplyr::select(iso3c, trade_share_china)

  # UNGA distance in last pre-treatment year
  unga_pre <- unga_data %>%
    dplyr::filter(year == 2008) %>%
    dplyr::select(iso3c, abs_distance_china)

  countries <- countries %>%
    left_join(trade_pre, by = "iso3c") %>%
    left_join(unga_pre, by = "iso3c") %>%
    arrange(desc(omega_weight))

  countries
}

############################
## Phase 2: Cross-Country Event Study
############################

# Identify when China became #1 export destination for each country
identify_treatment_events <- function(trade_data_ranked) {
  trade_data_ranked %>%
    dplyr::filter(treatment_first == 1) %>%
    group_by(iso3c) %>%
    summarise(first_treat_year = min(year), .groups = "drop") %>%
    dplyr::filter(first_treat_year >= 1997)
}

# Identify countries where USA was ever the #1 export destination
get_usa_top_countries <- function(trade_data) {
  trade_data %>%
    group_by(year, exporter_iso3) %>%
    slice_max(exports, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    dplyr::filter(importer_iso3 == "USA") %>%
    distinct(exporter_iso3) %>%
    pull(exporter_iso3)
}

# Filter event study data to countries where USA was ever #1
filter_usa_top_control <- function(event_data, classified_events, usa_top_countries) {
  treated_usa <- classified_events %>%
    dplyr::filter(displaced == "USA") %>%
    pull(iso3c)

  # Keep: treated (China displaced USA) + never-treated where USA was #1
  event_data %>%
    dplyr::filter(
      iso3c %in% treated_usa |
      (first_treat == 0 & iso3c %in% usa_top_countries)
    ) %>%
    mutate(id = as.integer(as.factor(iso3c)))
}

# Prepare panel data for did::att_gt()
prepare_event_study_data <- function(treatment_events, unga_data, covariates_df = NULL) {
  panel <- unga_data %>%
    dplyr::select(iso3c, year, abs_distance_china) %>%
    dplyr::filter(year >= 1990)

  # If covariates provided, merge them in

  if (!is.null(covariates_df)) {
    panel <- panel %>%
      inner_join(covariates_df, by = c("iso3c", "year"))
  }

  panel <- panel %>%
    left_join(treatment_events, by = "iso3c") %>%
    mutate(
      # did package: 0 = never treated
      # Column named "first_treat" (not "gname") to avoid data.table conflict in did 2.3.0
      first_treat = ifelse(is.na(first_treat_year), 0, first_treat_year),
      id = as.integer(as.factor(iso3c))
    )

  # Balance the panel: keep only units observed in all years
  max_years <- max(table(panel$id))
  balanced_ids <- panel %>%
    group_by(id) %>%
    summarise(n_years = n(), .groups = "drop") %>%
    dplyr::filter(n_years == max_years) %>%
    pull(id)

  panel <- panel %>%
    dplyr::filter(id %in% balanced_ids)

  panel
}

# Run Callaway & Sant'Anna (2021) staggered DiD
run_cross_country_did <- function(event_data, xformla = ~1, aggte_na_rm = FALSE) {
  att_gt_result <- did::att_gt(
    yname = "abs_distance_china",
    tname = "year",
    idname = "id",
    gname = "first_treat",
    xformla = xformla,
    data = as.data.frame(event_data),
    control_group = "nevertreated",
    base_period = "universal"
  )

  # Event study aggregation (dynamic effects by relative time)
  event_study <- did::aggte(att_gt_result, type = "dynamic", na.rm = aggte_na_rm)

  # Group-level ATT (by cohort)
  group_att <- did::aggte(att_gt_result, type = "group", na.rm = aggte_na_rm)

  # Overall ATT
  overall_att <- did::aggte(att_gt_result, type = "simple", na.rm = aggte_na_rm)

  list(
    att_gt = att_gt_result,
    event_study = event_study,
    group_att = group_att,
    overall_att = overall_att
  )
}

prepare_absorbing_china_top_did_data <- function(panel, covariate_cols = NULL,
                                                 min_entry_year = 2000) {
  required_cols <- c("iso3c", "year", "abs_distance_china", "china_top")
  missing_cols <- setdiff(required_cols, names(panel))
  if (length(missing_cols) > 0) {
    stop("prepare_absorbing_china_top_did_data: missing columns: ",
         paste(missing_cols, collapse = ", "))
  }

  if (is.null(covariate_cols)) {
    covariate_cols <- character(0)
  }
  missing_covariates <- setdiff(covariate_cols, names(panel))
  if (length(missing_covariates) > 0) {
    stop("prepare_absorbing_china_top_did_data: missing covariates: ",
         paste(missing_covariates, collapse = ", "))
  }

  rank_observed_col <- intersect("top_partner", names(panel))
  keep_cols <- c(required_cols, rank_observed_col, covariate_cols)

  base_panel <- panel %>%
    dplyr::select(dplyr::all_of(keep_cols)) %>%
    dplyr::filter(stats::complete.cases(dplyr::select(
      .,
      dplyr::all_of(required_cols)
    ))) %>%
    dplyr::arrange(iso3c, year)

  if ("top_partner" %in% names(base_panel)) {
    base_panel <- base_panel %>%
      dplyr::filter(!is.na(top_partner))
  }

  unit_summary <- base_panel %>%
    dplyr::group_by(iso3c) %>%
    dplyr::arrange(year, .by_group = TRUE) %>%
    dplyr::mutate(
      china_top_lag = dplyr::lag(china_top),
      entry = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L
    ) %>%
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      left_censored = dplyr::first(china_top) == 1L,
      first_treat_year = ifelse(
        any(entry, na.rm = TRUE),
        min(year[entry], na.rm = TRUE),
        NA_integer_
      ),
      absorbing = ifelse(
        any(entry, na.rm = TRUE),
        all(china_top[year >= first_treat_year] == 1L, na.rm = TRUE),
        FALSE
      ),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      cs_role = dplyr::case_when(
        ever_treated & !left_censored & absorbing &
          first_treat_year >= min_entry_year ~ "treated_absorbing",
        !ever_treated ~ "never_treated",
        TRUE ~ "excluded"
      ),
      first_treat = dplyr::if_else(
        cs_role == "treated_absorbing",
        as.numeric(first_treat_year),
        0
      )
    )

  did_panel <- base_panel %>%
    dplyr::left_join(
      unit_summary %>%
        dplyr::select(iso3c, cs_role, first_treat, first_treat_year, absorbing),
      by = "iso3c"
    ) %>%
    dplyr::filter(cs_role %in% c("treated_absorbing", "never_treated"))

  if (length(covariate_cols) > 0) {
    did_panel <- did_panel %>%
      dplyr::filter(stats::complete.cases(dplyr::select(
        .,
        dplyr::all_of(covariate_cols)
      )))
  }

  max_years <- max(table(did_panel$iso3c))
  balanced_iso <- did_panel %>%
    dplyr::group_by(iso3c) %>%
    dplyr::summarise(n_years = dplyr::n(), .groups = "drop") %>%
    dplyr::filter(n_years == max_years) %>%
    dplyr::pull(iso3c)

  did_panel <- did_panel %>%
    dplyr::filter(iso3c %in% balanced_iso)

  panel_max <- max(did_panel$year, na.rm = TRUE)
  estimable_treated <- did_panel %>%
    dplyr::filter(first_treat > 0, first_treat < panel_max) %>%
    dplyr::distinct(iso3c) %>%
    dplyr::pull(iso3c)

  did_panel %>%
    dplyr::filter(first_treat == 0 | iso3c %in% estimable_treated) %>%
    dplyr::mutate(id = as.integer(as.factor(iso3c))) %>%
    dplyr::arrange(id, year) %>%
    as.data.frame()
}

summarize_cross_country_did <- function(did_result, event_data) {
  overall <- did_result$overall_att
  att <- unname(overall$overall.att)
  se <- unname(overall$overall.se)
  p <- 2 * stats::pnorm(-abs(att / se))

  data.frame(
    att = att,
    se = se,
    ci_lo = att - 1.96 * se,
    ci_hi = att + 1.96 * se,
    p = p,
    n_obs = nrow(event_data),
    n_countries = dplyr::n_distinct(event_data$iso3c),
    n_treated = dplyr::n_distinct(event_data$iso3c[event_data$first_treat > 0]),
    n_control = dplyr::n_distinct(event_data$iso3c[event_data$first_treat == 0]),
    panel_min = min(event_data$year, na.rm = TRUE),
    panel_max = max(event_data$year, na.rm = TRUE),
    first_treat_min = min(event_data$first_treat[event_data$first_treat > 0], na.rm = TRUE),
    first_treat_max = max(event_data$first_treat[event_data$first_treat > 0], na.rm = TRUE)
  )
}

############################
## Phase 2b: Restricted Cross-Country DiD
############################

# Classify treatment events: absorbing vs switching, and who China displaced
classify_treatment_events <- function(trade_data_ranked, trade_data) {
  # Step 1: identify first treatment year per country
  first_treat <- trade_data_ranked %>%
    dplyr::filter(treatment_first == 1) %>%
    group_by(iso3c) %>%
    summarise(first_treat_year = min(year), .groups = "drop") %>%
    dplyr::filter(first_treat_year >= 1997)

  # Step 2: classify absorbing vs switching
  # Absorbing = China stays #1 for all remaining years in the data after first becoming #1
  max_year <- max(trade_data_ranked$year)
  absorbing_check <- first_treat %>%
    left_join(trade_data_ranked %>% dplyr::select(iso3c, year, treatment_first), by = "iso3c") %>%
    dplyr::filter(year >= first_treat_year) %>%
    group_by(iso3c, first_treat_year) %>%
    summarise(
      all_treated = all(treatment_first == 1),
      years_observed = n(),
      .groups = "drop"
    )

  first_treat <- first_treat %>%
    left_join(absorbing_check %>% dplyr::select(iso3c, all_treated), by = "iso3c") %>%
    rename(absorbing = all_treated)

  # Step 3: identify who China displaced (who was #1 the year before treatment)
  prev_top <- trade_data %>%
    group_by(year, exporter_iso3) %>%
    slice_max(exports, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    dplyr::select(iso3c = exporter_iso3, year, displaced = importer_iso3)

  first_treat <- first_treat %>%
    mutate(year_before = first_treat_year - 1) %>%
    left_join(prev_top, by = c("iso3c", "year_before" = "year")) %>%
    dplyr::select(iso3c, first_treat_year, absorbing, displaced)

  first_treat
}

# Event study plot for cross-country DiD results
plot_event_study_did <- function(did_result,
                                 title = "Dynamic treatment effects: China becomes #1 trade partner") {
  es <- did_result$event_study

  df <- data.frame(
    e     = es$egt,
    att   = es$att.egt,
    se    = es$se.egt
  ) %>%
    mutate(ci_lo = att - 1.96 * se,
           ci_hi = att + 1.96 * se)

  ggplot(df, aes(x = e, y = att)) +
    geom_hline(yintercept = 0, colour = "grey50", linetype = "solid") +
    geom_vline(xintercept = -0.5, colour = "grey50", linetype = "dashed") +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.2, fill = "steelblue") +
    geom_point(size = 1.8, colour = "steelblue") +
    geom_line(colour = "steelblue") +
    labs(x = "Periods relative to treatment",
         y = "ATT estimate",
         title = title) +
    theme_minimal(base_size = 12) +
    theme(panel.grid.minor = element_blank())
}

# Run restricted DiD with filters for absorbing treatment and/or displaced partner
run_restricted_did <- function(event_study_data, classified_events,
                                restrict_absorbing = FALSE,
                                restrict_displaced_usa = FALSE,
                                xformla = ~1) {
  data <- event_study_data

  # Identify which treated countries to keep
  keep_treated <- classified_events

  if (restrict_absorbing) {
    keep_treated <- keep_treated %>% dplyr::filter(absorbing == TRUE)
  }

  if (restrict_displaced_usa) {
    keep_treated <- keep_treated %>% dplyr::filter(displaced == "USA")
  }

  # Filter data: keep qualifying treated countries + all never-treated
  data <- data %>%
    dplyr::filter(iso3c %in% keep_treated$iso3c | first_treat == 0)

  # Re-create numeric IDs after filtering
  data <- data %>%
    mutate(id = as.integer(as.factor(iso3c)))

  # Run DiD
  run_cross_country_did(data, xformla = xformla)
}

############################
## Phase 2c: Cross-Country DiD Enhancements
############################

# Prepare covariates for DiD (excludes trade shares — bad controls)
prepare_did_covariates <- function(final_df) {
  final_df %>%
    mutate(log_gdp_pc = log(gdp_cur / pop)) %>%
    dplyr::select(iso3c, year, log_gdp_pc, gpi, us_power_gap, distance_us, hog_left) %>%
    drop_na()
}

# Pre-trends Wald test: H0 = all pre-treatment ATTs jointly equal zero
pretrends_wald_test <- function(did_result, min_e = -Inf) {
  es <- did_result$event_study

  # Indices for pre-treatment periods (min_e <= e < 0), excluding reference period (se = NA)
  pre_idx <- which(es$egt < 0 & es$egt >= min_e & !is.na(es$se.egt))

  if (length(pre_idx) < 2) {
    return(list(
      wald_stat = NA_real_,
      df = length(pre_idx),
      p_value = NA_real_,
      pre_periods = es$egt[pre_idx],
      pre_atts = es$att.egt[pre_idx],
      vcv = NULL,
      message = "Not enough pre-treatment periods for Wald test"
    ))
  }

  # Pre-treatment ATT estimates
  beta_pre <- es$att.egt[pre_idx]

  # Variance-covariance matrix via influence functions
  # did::aggte stores influence functions; compute VCV from them
  inf_func <- es$inf.function$dynamic.inf.func.e
  # inf_func is n x length(egt) matrix
  inf_pre <- inf_func[, pre_idx, drop = FALSE]
  n <- nrow(inf_pre)
  V_pre <- crossprod(inf_pre) / n^2

  # Add small ridge for numerical stability (same trick as HonestDiD)
  k <- length(beta_pre)
  V_pre <- V_pre + diag(1e-8, k)

  # Wald statistic: beta' * V^{-1} * beta ~ chi-squared(k)
  V_inv <- tryCatch(solve(V_pre), error = function(e) MASS::ginv(V_pre))
  wald_stat <- as.numeric(t(beta_pre) %*% V_inv %*% beta_pre)
  p_value <- 1 - pchisq(wald_stat, df = k)

  list(
    wald_stat = wald_stat,
    df = k,
    p_value = p_value,
    pre_periods = es$egt[pre_idx],
    pre_atts = beta_pre,
    vcv = V_pre
  )
}

# Format group-level ATTs as a table
format_group_att_table <- function(did_result) {
  ga <- did_result$group_att

  data.frame(
    cohort_year = ga$egt,
    att = ga$att.egt,
    se = ga$se.egt,
    ci_lo = ga$att.egt - 1.96 * ga$se.egt,
    ci_hi = ga$att.egt + 1.96 * ga$se.egt,
    p_value = 2 * (1 - pnorm(abs(ga$att.egt / ga$se.egt)))
  )
}

# Build stacked DiD dataset (Cengiz et al. 2019)
build_stacked_did_data <- function(event_data, classified_events,
                                   restrict_displaced_usa = TRUE,
                                   window = 10) {
  # Get treated countries
  keep_treated <- classified_events
  if (restrict_displaced_usa) {
    keep_treated <- keep_treated %>% dplyr::filter(displaced == "USA")
  }

  # Never-treated units
  never_treated <- event_data %>%
    dplyr::filter(first_treat == 0)

  stacked_list <- list()
  stack_id <- 0

  for (i in seq_len(nrow(keep_treated))) {
    g <- keep_treated$first_treat_year[i]
    country_g <- keep_treated$iso3c[i]
    stack_id <- stack_id + 1

    # Time window for this sub-experiment
    year_min <- g - window
    year_max <- g + window

    # Treated unit in window
    treated_sub <- event_data %>%
      dplyr::filter(iso3c == country_g, year >= year_min, year <= year_max)

    # Never-treated units in window
    control_sub <- never_treated %>%
      dplyr::filter(year >= year_min, year <= year_max)

    sub_exp <- bind_rows(treated_sub, control_sub) %>%
      mutate(
        stack_id = stack_id,
        cohort_id = g,
        treat_post = as.integer(iso3c == country_g & year >= g)
      )

    stacked_list[[stack_id]] <- sub_exp
  }

  bind_rows(stacked_list)
}

# Wild cluster bootstrap for stacked DiD
run_wild_cluster_bootstrap <- function(event_data, classified_events,
                                       restrict_displaced_usa = TRUE,
                                       B = 9999) {
  set.seed(42)
  stacked_data <- build_stacked_did_data(event_data, classified_events,
                                    restrict_displaced_usa = restrict_displaced_usa)

  # Create explicit interactions for FE
  stacked_data <- stacked_data %>%
    mutate(stack_year = interaction(stack_id, year, drop = TRUE),
           unit_id = as.integer(as.factor(iso3c)))

  # Main estimate via fixest (efficient with many FEs)
  fit_feols <- fixest::feols(
    abs_distance_china ~ treat_post | unit_id + stack_year,
    data = stacked_data,
    cluster = ~iso3c
  )

  # For wild bootstrap: use lm with factor FEs (boottest has compatibility
  # issues with fixest::coef in some versions)
  assign("stacked_data", stacked_data, envir = .GlobalEnv)
  on.exit(rm("stacked_data", envir = .GlobalEnv), add = TRUE)

  fit_lm <- lm(abs_distance_china ~ treat_post + factor(unit_id) + factor(stack_year),
                data = stacked_data)

  boot_result <- fwildclusterboot::boottest(
    fit_lm,
    param = "treat_post",
    B = B,
    type = "webb",
    clustid = c("iso3c")
  )

  list(
    stacked_fit = fit_feols,
    coef = coef(fit_feols)["treat_post"],
    se_cluster = sqrt(fit_feols$cov.scaled["treat_post", "treat_post"]),
    boot_result = boot_result,
    boot_p_value = boot_result$p_val,
    boot_ci = boot_result$conf_int,
    n_clusters = length(unique(stacked_data$iso3c)),
    n_obs = nrow(stacked_data)
  )
}

# Fisher randomization test for cross-country DiD
fisher_randomization_test <- function(event_data, classified_events,
                                      n_perms = 1000) {
  set.seed(42)

  # Observed treated countries (displaced USA)
  treated_info <- classified_events %>%
    dplyr::filter(displaced == "USA")

  n_treated <- nrow(treated_info)
  observed_treat_years <- treated_info$first_treat_year

  # Get observed ATT
  obs_data <- event_data %>%
    dplyr::filter(iso3c %in% treated_info$iso3c | first_treat == 0) %>%
    mutate(id = as.integer(as.factor(iso3c)))

  obs_result <- run_cross_country_did(obs_data)
  obs_att <- obs_result$overall_att$overall.att

  # All available countries in the panel (including never-treated)
  all_countries <- unique(event_data$iso3c)

  # Permutation loop
  perm_atts <- numeric(n_perms)
  for (p in seq_len(n_perms)) {
    # Randomly assign treatment: pick n_treated countries, assign observed treatment years
    perm_countries <- sample(all_countries, n_treated)
    perm_assignments <- data.frame(
      iso3c = perm_countries,
      first_treat_perm = sample(observed_treat_years, n_treated, replace = FALSE)
    )

    # Build permuted panel
    perm_panel <- event_data %>%
      dplyr::select(iso3c, year, abs_distance_china) %>%
      left_join(perm_assignments, by = "iso3c") %>%
      mutate(
        first_treat = ifelse(is.na(first_treat_perm), 0, first_treat_perm),
        id = as.integer(as.factor(iso3c))
      ) %>%
      dplyr::select(-first_treat_perm)

    # Balance panel
    max_years <- max(table(perm_panel$id))
    balanced_ids <- perm_panel %>%
      group_by(id) %>%
      summarise(n_years = n(), .groups = "drop") %>%
      dplyr::filter(n_years == max_years) %>%
      pull(id)
    perm_panel <- perm_panel %>% dplyr::filter(id %in% balanced_ids)

    perm_atts[p] <- tryCatch({
      perm_result <- did::att_gt(
        yname = "abs_distance_china",
        tname = "year",
        idname = "id",
        gname = "first_treat",
        data = as.data.frame(perm_panel),
        control_group = "nevertreated",
        base_period = "universal"
      )
      perm_overall <- did::aggte(perm_result, type = "simple")
      perm_overall$overall.att
    }, error = function(e) NA_real_)
  }

  # Two-sided p-value
  valid_perms <- !is.na(perm_atts)
  p_value <- mean(abs(perm_atts[valid_perms]) >= abs(obs_att))

  list(
    observed_att = obs_att,
    perm_atts = perm_atts,
    p_value = p_value,
    n_perms = n_perms,
    n_valid = sum(valid_perms)
  )
}

# Plot Fisher randomization test results
plot_fisher_test <- function(fisher_result) {
  df <- data.frame(att = fisher_result$perm_atts) %>%
    dplyr::filter(!is.na(att))

  ggplot(df, aes(x = att)) +
    geom_histogram(bins = 50, fill = "grey70", colour = "grey50") +
    geom_vline(xintercept = fisher_result$observed_att,
               colour = "red", linewidth = 1, linetype = "dashed") +
    labs(
      x = "Permuted ATT",
      y = "Frequency",
      title = "Fisher Randomization Test",
      subtitle = sprintf("Observed ATT = %.4f | p-value = %.3f",
                         fisher_result$observed_att, fisher_result$p_value)
    ) +
    theme_minimal(base_size = 12)
}

# HonestDiD sensitivity analysis
# Follows approach from CS_RR repo (Pedro Sant'Anna)
# Limits event window to [-max_pre, max_post] excluding reference period (e=-1)
honest_did_sensitivity <- function(did_result, type = "smoothness",
                                   max_pre = 20, max_post = 10) {
  es <- did_result$event_study

  # Identify event times to keep: [-max_pre, -2] for pre and [0, max_post] for post
  # (e = -1 is the reference period, excluded)
  all_egt <- es$egt
  pre_mask <- all_egt >= -max_pre & all_egt <= -2
  post_mask <- all_egt >= 0 & all_egt <= max_post

  keep_mask <- pre_mask | post_mask
  keep_idx <- which(keep_mask)

  betahat <- es$att.egt[keep_idx]
  event_times <- all_egt[keep_idx]

  numPrePeriods <- sum(pre_mask)
  numPostPeriods <- sum(post_mask)

  # VCV via influence functions
  inf_func <- es$inf.function$dynamic.inf.func.e
  inf_keep <- inf_func[, keep_idx, drop = FALSE]
  n <- nrow(inf_keep)
  sigma <- crossprod(inf_keep) / n^2

  # Ensure sigma is symmetric positive definite (small ridge for numerical stability)
  sigma <- (sigma + t(sigma)) / 2
  eig_min <- min(eigen(sigma, symmetric = TRUE, only.values = TRUE)$values)
  if (eig_min < 1e-10) {
    sigma <- sigma + diag(abs(eig_min) + 1e-8, nrow(sigma))
  }

  # Average across all post-treatment periods (comparable to overall ATT)
  l_vec <- rep(1 / numPostPeriods, numPostPeriods)

  if (type == "smoothness") {
    sensitivity <- HonestDiD::createSensitivityResults(
      betahat = betahat,
      sigma = sigma,
      numPrePeriods = numPrePeriods,
      numPostPeriods = numPostPeriods,
      l_vec = l_vec,
      Mvec = seq(from = 0, to = 0.05, by = 0.01)
    )

    # Manual plot (createSensitivityPlot has a bug in some versions)
    plot <- ggplot(sensitivity, aes(x = M, ymin = lb, ymax = ub)) +
      geom_linerange(linewidth = 1, colour = "steelblue") +
      geom_point(aes(y = (lb + ub) / 2), colour = "steelblue", size = 2) +
      geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
      labs(title = "HonestDiD Sensitivity: Smoothness (DeltaSD)",
           x = "M (smoothness bound)", y = "95% Robust CI") +
      theme_minimal(base_size = 12)

  } else if (type == "relative_magnitude") {
    sensitivity <- HonestDiD::createSensitivityResults_relativeMagnitudes(
      betahat = betahat,
      sigma = sigma,
      numPrePeriods = numPrePeriods,
      numPostPeriods = numPostPeriods,
      l_vec = l_vec,
      Mbarvec = seq(from = 0.5, to = 2, by = 0.5)
    )

    x_col <- if ("Mbar" %in% names(sensitivity)) "Mbar" else names(sensitivity)[5]
    plot <- ggplot(sensitivity, aes(x = .data[[x_col]], ymin = lb, ymax = ub)) +
      geom_linerange(linewidth = 1, colour = "firebrick") +
      geom_point(aes(y = (lb + ub) / 2), colour = "firebrick", size = 2) +
      geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
      labs(title = "HonestDiD Sensitivity: Relative Magnitudes (DeltaRM)",
           x = expression(bar(M)), y = "95% Robust CI") +
      theme_minimal(base_size = 12)
  } else {
    stop("type must be 'smoothness' or 'relative_magnitude'")
  }

  list(
    sensitivity = sensitivity,
    plot = plot,
    betahat = betahat,
    sigma = sigma,
    event_times = event_times,
    numPrePeriods = numPrePeriods,
    numPostPeriods = numPostPeriods,
    type = type
  )
}

############################
## Phase 3: fect + PanelMatch (switching treatment)
############################

# Build covariate panel: log GDP per capita + V-Dem free press
build_covariates <- function(final_df) {
  # GDP per capita
  gdp_cov <- final_df %>%
    dplyr::mutate(log_gdp_pc = log(gdp_cur / pop)) %>%
    dplyr::select(iso3c, year, log_gdp_pc) %>%
    dplyr::filter(!is.na(log_gdp_pc))

  # V-Dem Freedom of Expression (v2x_freexp_altinf)
  # V-Dem country_text_id is mostly ISO3C but has some divergences
  vdem_cov <- vdemdata::vdem %>%
    dplyr::select(country_text_id, year, v2x_freexp_altinf) %>%
    dplyr::filter(year >= 1990, !is.na(v2x_freexp_altinf)) %>%
    dplyr::rename(iso3c = country_text_id, free_press = v2x_freexp_altinf) %>%
    dplyr::mutate(iso3c = dplyr::case_match(iso3c,
      "BUR" ~ "MMR",  # Burma → Myanmar
      .default = iso3c
    ))

  result <- gdp_cov %>%
    dplyr::left_join(vdem_cov, by = c("iso3c", "year"))

  # Warn if many GDP rows lost free_press after merge
  n_lost <- sum(!is.na(result$log_gdp_pc) & is.na(result$free_press))
  if (n_lost > nrow(result) * 0.1) {
    warning(sprintf("build_covariates: %d rows (%.0f%%) have GDP but missing V-Dem free_press after merge",
                    n_lost, n_lost / nrow(result) * 100))
  }
  result
}

# Build panel with binary switching treatment indicator
# china_top = 1 if China is currently the #1 export destination, 0 otherwise
build_switching_panel <- function(trade_data, unga_data, classified_events, usa_top_countries) {
  # Countries in the USA-displaced DiD sample
  treated_usa <- classified_events %>%
    dplyr::filter(displaced == "USA") %>%
    pull(iso3c)

  did_countries <- unique(c(treated_usa, usa_top_countries))

  # Current rank of China vs USA for each exporter-year

  rank_current <- trade_data %>%
    group_by(year, exporter_iso3) %>%
    arrange(desc(exports)) %>%
    mutate(rank = row_number()) %>%
    ungroup() %>%
    dplyr::filter(exporter_iso3 %in% did_countries,
                  importer_iso3 %in% c("CHN", "USA")) %>%
    dplyr::select(iso3c = exporter_iso3, year, partner = importer_iso3, rank) %>%
    tidyr::pivot_wider(names_from = partner, values_from = rank, names_prefix = "rank_")

  panel <- unga_data %>%
    dplyr::filter(iso3c %in% did_countries, year >= 1990) %>%
    dplyr::select(iso3c, year, abs_distance_china) %>%
    left_join(rank_current, by = c("iso3c", "year")) %>%
    mutate(
      china_top = as.integer(!is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA)),
      country_id = as.integer(as.factor(iso3c)),
      country_name = countrycode::countrycode(iso3c, "iso3c", "country.name")
    ) %>%
    arrange(country_id, year)
  panel$china_top[is.na(panel$china_top)] <- 0L

  as.data.frame(panel)
}

prepare_fect_data <- function(panel, fml = abs_distance_china ~ china_top,
                              exclude_iso3c = "CHN",
                              min_untreated_periods = NULL,
                              min_pre_treatment_periods = NULL,
                              drop_left_censored = FALSE,
                              require_common_year_grid = FALSE) {
  fml_vars <- all.vars(fml)
  missing_vars <- setdiff(fml_vars, names(panel))
  if (length(missing_vars) > 0) {
    stop("prepare_fect_data: missing variables in panel: ",
         paste(missing_vars, collapse = ", "))
  }

  id_cols <- intersect(c("iso3c", "country_name"), names(panel))
  keep_cols <- unique(c(id_cols, "country_id", "year", fml_vars))
  if (!all(c("country_id", "year") %in% names(panel))) {
    stop("prepare_fect_data: panel must contain country_id and year")
  }

  data <- panel
  if ("iso3c" %in% names(data) && length(exclude_iso3c) > 0) {
    data <- data %>% dplyr::filter(!iso3c %in% exclude_iso3c)
  }

  estimation_cols <- unique(c("country_id", "year", fml_vars))
  data <- data %>%
    dplyr::select(dplyr::all_of(keep_cols)) %>%
    dplyr::filter(stats::complete.cases(dplyr::select(., dplyr::all_of(estimation_cols))))

  unit_var <- if ("iso3c" %in% names(data)) "iso3c" else "country_id"

  if (nrow(data) == 0L) {
    stop("prepare_fect_data: no complete cases remain after filtering")
  }

  if (require_common_year_grid) {
    common_years <- seq(min(data$year, na.rm = TRUE), max(data$year, na.rm = TRUE))
    balanced_units <- data %>%
      dplyr::group_by(.data[[unit_var]]) %>%
      dplyr::summarise(
        has_common_year_grid = setequal(year, common_years) &&
          dplyr::n_distinct(year) == length(common_years),
        .groups = "drop"
      ) %>%
      dplyr::filter(has_common_year_grid) %>%
      dplyr::pull(.data[[unit_var]])

    data <- data %>% dplyr::filter(.data[[unit_var]] %in% balanced_units)

    if (nrow(data) == 0L) {
      stop("prepare_fect_data: no units remain on the common year grid")
    }
  }

  if ("china_top" %in% names(data) &&
      (!is.null(min_pre_treatment_periods) || !is.null(min_untreated_periods))) {
    keep_units <- data %>%
      dplyr::arrange(.data[[unit_var]], year) %>%
      dplyr::group_by(.data[[unit_var]]) %>%
      dplyr::mutate(
        china_top_lag = dplyr::lag(china_top),
        entry = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L
      ) %>%
      dplyr::summarise(
        ever_treated = any(china_top == 1L, na.rm = TRUE),
        left_censored = dplyr::first(china_top) == 1L,
        first_entry_year = ifelse(
          any(entry, na.rm = TRUE),
          min(year[entry], na.rm = TRUE),
          NA_integer_
        ),
        pre_treatment_periods = ifelse(
          any(entry, na.rm = TRUE),
          sum(china_top == 0L & year < first_entry_year, na.rm = TRUE),
          sum(china_top == 0L, na.rm = TRUE)
        ),
        untreated_periods = sum(china_top == 0L, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::filter(!ever_treated |
                      (!drop_left_censored & left_censored) |
                      (!left_censored & pre_treatment_periods >= min_pre_treatment_periods))

    if (!is.null(min_untreated_periods)) {
      keep_units <- keep_units %>%
        dplyr::filter(untreated_periods >= min_untreated_periods)
    }

    keep_units <- keep_units %>% dplyr::pull(.data[[unit_var]])
    data <- data %>% dplyr::filter(.data[[unit_var]] %in% keep_units)
  }

  if ("iso3c" %in% names(data)) {
    data <- data %>% dplyr::mutate(country_id = as.integer(as.factor(iso3c)))
  } else {
    data <- data %>% dplyr::mutate(country_id = as.integer(as.factor(country_id)))
  }

  data %>%
    dplyr::arrange(country_id, year) %>%
    as.data.frame()
}

# Run fect analysis (FE or IFE method)
run_fect_analysis <- function(panel, method = "ife", nboots = 500,
                              fml = abs_distance_china ~ china_top) {
  set.seed(42)
  fect_data <- prepare_fect_data(panel, fml = fml)

  if (method == "fe") {
    fit <- fect::fect(
      fml,
      data = fect_data,
      index = c("country_id", "year"),
      method = "fe", force = "two-way",
      se = TRUE, nboots = nboots, parallel = FALSE,
      placeboTest = TRUE, placebo.period = c(-5, -1)
    )
  } else if (method == "ife") {
    fit <- fect::fect(
      fml,
      data = fect_data,
      index = c("country_id", "year"),
      method = "ife", force = "two-way",
      se = TRUE, nboots = nboots, parallel = FALSE,
      CV = TRUE, r = c(0, 3)
    )
  } else {
    stop("method must be 'fe' or 'ife'")
  }

  fit
}

# Run fect carryover test (separate run, FE only)
run_fect_carryover <- function(panel, nboots = 500) {
  set.seed(42)
  fect_data <- prepare_fect_data(panel, fml = abs_distance_china ~ china_top)

  fect::fect(
    abs_distance_china ~ china_top,
    data = fect_data,
    index = c("country_id", "year"),
    method = "fe", force = "two-way",
    se = TRUE, nboots = nboots, parallel = FALSE,
    carryoverTest = TRUE, carryover.period = c(1, 5)
  )
}

# Extract ATT summary from fect object
fect_att_summary <- function(fit) {
  se <- sd(fit$att.avg.boot)
  p <- 2 * pnorm(-abs(fit$att.avg / se))
  list(
    att = fit$att.avg,
    se = se,
    ci_lo = fit$att.avg - 1.96 * se,
    ci_hi = fit$att.avg + 1.96 * se,
    p = p,
    r_cv = if (!is.null(fit$r.cv)) fit$r.cv else NA
  )
}

# Run PanelMatch analysis (ATT or ART)
run_panelmatch_analysis <- function(panel, qoi = "att", lag = 1, lead = 0:8, n_iter = 1000) {
  set.seed(42)
  pm_df <- prepare_fect_data(
    panel,
    fml = abs_distance_china ~ china_top,
    require_common_year_grid = TRUE
  ) %>%
    dplyr::mutate(time_id = match(year, sort(unique(year))))

  pd <- PanelMatch::PanelData(
    panel.data = pm_df,
    unit.id = "country_id",
    time.id = "time_id",
    treatment = "china_top",
    outcome = "abs_distance_china"
  )

  pm <- PanelMatch::PanelMatch(
    panel.data = pd,
    lag = lag,
    refinement.method = "none",
    qoi = qoi,
    lead = lead,
    match.missing = TRUE,
    forbid.treatment.reversal = FALSE
  )

  est <- PanelMatch::PanelEstimate(sets = pm, panel.data = pd, number.iterations = n_iter)

  s <- summary(est)
  n_leads <- min(length(lead), nrow(s))
  result_df <- data.frame(
    lead = lead[1:n_leads],
    estimate = s[1:n_leads, "estimate"],
    se = s[1:n_leads, "std.error"],
    ci_lo = s[1:n_leads, "2.5%"],
    ci_hi = s[1:n_leads, "97.5%"]
  )

  list(
    fit = est,
    summary_df = result_df,
    qoi = qoi
  )
}

# Plot fect gap (entry-aligned)
plot_fect_gap <- function(fit, title = "Entry-aligned gap plot") {
  # Use fect's built-in plot for gap
  p <- plot(fit, type = "gap",
            main = title,
            ylab = "Effect on abs. distance to China",
            xlab = "Periods relative to treatment entry",
            show.points = TRUE)
  p
}

# Plot fect exit (exit-aligned)
plot_fect_exit <- function(fit, title = "Exit-aligned gap plot") {
  p <- plot(fit, type = "exit",
            main = title,
            ylab = "Effect on abs. distance to China",
            xlab = "Periods relative to treatment exit",
            show.points = TRUE)
  p
}

# Consolidated diagnostic figure (Figure 8 style from Liu, Wang & Xu 2024)
# Three panels: (a) IFE gap, (b) FE placebo test, (c) FE carryover test
plot_fect_diagnostics <- function(fect_ife, fect_fe, fect_carryover) {
  p_gap <- plot(fect_ife, type = "gap",
                main = "(a) IFE: Dynamic Treatment Effects",
                ylab = "Effect on UNGA distance to China",
                xlab = "Periods since treatment entry")

  p_placebo <- plot(fect_fe, type = "gap",
                    main = "(b) FE: Placebo Test",
                    ylab = "Effect on UNGA distance to China",
                    xlab = "Periods since treatment entry")

  p_carry <- plot(fect_carryover, type = "exit",
                  main = "(c) FE: Carryover Test",
                  ylab = "Effect on UNGA distance to China",
                  xlab = "Periods since treatment exit")

  combined <- p_gap | p_placebo | p_carry
  combined + patchwork::plot_layout(widths = c(1, 1, 1))
}

# Appendix: equivalence test plots (FE and IFE pretrend tests)
plot_fect_equiv_appendix <- function(fect_fe, fect_ife) {
  p_fe <- plot(fect_fe, type = "equiv",
               main = "(a) FE: No-Pretrend Equivalence Test",
               ylab = "Avg. prediction error",
               xlab = "Periods since treatment entry")

  p_ife <- plot(fect_ife, type = "equiv",
                main = "(b) IFE: No-Pretrend Equivalence Test",
                ylab = "Avg. prediction error",
                xlab = "Periods since treatment entry")

  p_fe | p_ife
}

# Plot PanelMatch combined (ATT + ART)
plot_panelmatch_combined <- function(est_att, est_art) {
  att_df <- est_att$summary_df %>% mutate(Estimand = "ATT (switch on)")
  art_df <- est_art$summary_df %>% mutate(Estimand = "ART (switch off)")

  combined <- bind_rows(att_df, art_df)

  colours <- c("ATT (switch on)" = "steelblue", "ART (switch off)" = "firebrick")

  p <- ggplot(combined, aes(x = lead, y = estimate, colour = Estimand, fill = Estimand)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, colour = NA) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    scale_colour_manual(values = colours) +
    scale_fill_manual(values = colours) +
    facet_wrap(~Estimand, ncol = 1, scales = "free_y") +
    labs(
      title = "PanelMatch: Entry vs. Exit Effects",
      subtitle = "Imai, Kim & Wang (2023) -- lag = 1, no refinement",
      x = "Periods after switch", y = "Estimate"
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), legend.position = "none")

  p
}

############################
## Phase 4: Devil's Advocate Responses
############################

# Leave-one-out fect IFE: drop each treated country one at a time
run_fect_leave_one_out <- function(panel, method = "ife", nboots = 500,
                                    fml = abs_distance_china ~ china_top) {
  set.seed(42)
  treated_ids <- unique(panel$iso3c[panel$china_top == 1])

  results <- list()
  for (i in seq_along(treated_ids)) {
    drop_id <- treated_ids[i]
    sub_panel <- panel[panel$iso3c != drop_id, ]

    tryCatch({
      fit <- run_fect_analysis(sub_panel, method = method, nboots = nboots, fml = fml)
      s <- fect_att_summary(fit)
      country_name <- unique(panel$country_name[panel$iso3c == drop_id])
      results[[i]] <- data.frame(
        dropped = country_name[1], iso3c = drop_id,
        att = s$att, se = s$se, p = s$p, r_cv = s$r_cv,
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      results[[i]] <<- data.frame(
        dropped = drop_id, iso3c = drop_id,
        att = NA_real_, se = NA_real_, p = NA_real_, r_cv = NA_integer_,
        stringsAsFactors = FALSE
      )
    })
  }

  do.call(rbind, results)
}

# Scope-conditioned cross-country panel from the diagnostic specification:
# the sample keeps countries where the United States is the prior top partner
# or a relevant benchmark; treatment turns on when China becomes #1 within
# that sample.
# treatment turns on only when China becomes the #1 export destination after an
# observed prior year in which China was not #1, with onset in/after 2000.
build_china_top_partner_panel <- function(trade_data, unga_data, classified_events,
                                          usa_top_countries, min_year = 1990,
                                          min_entry_year = 2000) {
  treated_usa <- classified_events %>%
    dplyr::filter(displaced == "USA") %>%
    dplyr::pull(iso3c)

  did_countries <- unique(c(treated_usa, usa_top_countries))

  ranked_partners <- trade_data %>%
    dplyr::group_by(year, exporter_iso3) %>%
    dplyr::arrange(dplyr::desc(exports), .by_group = TRUE) %>%
    dplyr::mutate(rank = dplyr::row_number()) %>%
    dplyr::ungroup() %>%
    dplyr::filter(exporter_iso3 %in% did_countries)

  top_partner <- ranked_partners %>%
    dplyr::filter(rank == 1L) %>%
    dplyr::select(iso3c = exporter_iso3, year, top_partner = importer_iso3)

  rank_china_usa <- ranked_partners %>%
    dplyr::filter(importer_iso3 %in% c("CHN", "USA")) %>%
    dplyr::select(
      iso3c = exporter_iso3,
      year,
      partner = importer_iso3,
      rank
    ) %>%
    tidyr::pivot_wider(
      names_from = partner,
      values_from = rank,
      names_prefix = "rank_"
    )

  panel <- unga_data %>%
    dplyr::filter(iso3c %in% did_countries, year >= min_year) %>%
    dplyr::select(iso3c, year, abs_distance_china) %>%
    dplyr::left_join(rank_china_usa, by = c("iso3c", "year")) %>%
    dplyr::left_join(top_partner, by = c("iso3c", "year")) %>%
    dplyr::mutate(
      china_is_top = dplyr::case_when(
        is.na(top_partner) ~ NA,
        !is.na(rank_CHN) & rank_CHN == 1L ~ TRUE,
        TRUE ~ FALSE
      ),
      country_id = as.integer(as.factor(iso3c)),
      country_name = countrycode::countrycode(
        iso3c,
        "iso3c",
        "country.name",
        warn = FALSE
      )
    ) %>%
    dplyr::group_by(iso3c) %>%
    dplyr::arrange(year, .by_group = TRUE) %>%
    dplyr::mutate(
      previous_observed_year = dplyr::lag(year),
      previous_china_is_top = dplyr::lag(china_is_top),
      previous_top_partner = dplyr::lag(top_partner),
      previous_trade_observed = !is.na(previous_top_partner),
      china_top_period_start = dplyr::coalesce(china_is_top, FALSE) &
        !dplyr::coalesce(dplyr::lag(china_is_top), FALSE),
      china_top_period_id = cumsum(china_top_period_start)
    ) %>%
    dplyr::ungroup()

  period_onsets <- panel %>%
    dplyr::filter(china_top_period_start) %>%
    dplyr::select(
      iso3c,
      china_top_period_id,
      entry_year = year,
      previous_observed_year_at_entry = previous_observed_year,
      previous_china_is_top_at_entry = previous_china_is_top,
      previous_top_partner_at_entry = previous_top_partner,
      previous_trade_observed_at_entry = previous_trade_observed
    )

  panel <- panel %>%
    dplyr::left_join(period_onsets, by = c("iso3c", "china_top_period_id")) %>%
    dplyr::mutate(
      china_top = dplyr::case_when(
        is.na(top_partner) ~ NA_integer_,
        china_is_top &
          !is.na(entry_year) &
          entry_year >= min_entry_year &
          !is.na(previous_observed_year_at_entry) &
          previous_trade_observed_at_entry == TRUE &
          !is.na(previous_china_is_top_at_entry) &
          previous_china_is_top_at_entry == FALSE ~ 1L,
        TRUE ~ 0L
      )
    )

  panel %>%
    dplyr::arrange(country_id, year) %>%
    as.data.frame()
}

# Backward-compatible helper for exploratory "any displacement" code.
build_any_displacement_panel <- function(trade_data, unga_data, classified_events = NULL) {
  treated_usa <- classified_events %>%
    dplyr::filter(displaced == "USA") %>%
    dplyr::pull(iso3c)

  build_china_top_partner_panel(trade_data, unga_data, classified_events, treated_usa)
}

summarize_china_top_panel <- function(panel) {
  unit_summary <- panel %>%
    dplyr::arrange(iso3c, year) %>%
    dplyr::group_by(iso3c, country_name) %>%
    dplyr::mutate(
      china_top_lag = dplyr::lag(china_top),
      left_censored = dplyr::first(china_top) == 1L,
      entry = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L,
      exit = china_top == 0L & !is.na(china_top_lag) & china_top_lag == 1L
    ) %>%
    dplyr::summarise(
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      entries = sum(entry, na.rm = TRUE),
      exits = sum(exit, na.rm = TRUE),
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      left_censored = any(left_censored, na.rm = TRUE),
      first_entry_year = ifelse(any(entry, na.rm = TRUE), min(year[entry], na.rm = TRUE), NA_integer_),
      .groups = "drop"
    )

  treated_iso <- unit_summary %>%
    dplyr::filter(ever_treated) %>%
    dplyr::pull(iso3c)

  pre_treated_mean <- panel %>%
    dplyr::left_join(
      unit_summary %>%
        dplyr::select(iso3c, first_entry_year) %>%
        dplyr::filter(!is.na(first_entry_year)),
      by = "iso3c"
    ) %>%
    dplyr::filter(iso3c %in% treated_iso,
                  !is.na(first_entry_year),
                  year < first_entry_year) %>%
    dplyr::summarise(m = mean(abs_distance_china, na.rm = TRUE)) %>%
    dplyr::pull(m)

  data.frame(
    n_obs = nrow(panel),
    n_countries = dplyr::n_distinct(panel$iso3c),
    n_treated = sum(unit_summary$ever_treated),
    n_control = sum(!unit_summary$ever_treated),
    n_treated_country_years = sum(panel$china_top == 1L, na.rm = TRUE),
    n_entries = sum(unit_summary$entries, na.rm = TRUE),
    n_exits = sum(unit_summary$exits, na.rm = TRUE),
    n_left_censored = sum(unit_summary$left_censored, na.rm = TRUE),
    panel_min = min(panel$year, na.rm = TRUE),
    panel_max = max(panel$year, na.rm = TRUE),
    pre_treated_mean = pre_treated_mean,
    outcome_sd = sd(panel$abs_distance_china, na.rm = TRUE)
  )
}

summarize_fect_model <- function(fit, panel, fml = abs_distance_china ~ china_top) {
  estimation_panel <- prepare_fect_data(panel, fml = fml)
  s <- fect_att_summary(fit)
  p <- summarize_china_top_panel(estimation_panel)
  data.frame(
    att = s$att,
    se = s$se,
    ci_lo = s$ci_lo,
    ci_hi = s$ci_hi,
    p = s$p,
    r_cv = s$r_cv,
    att_rel_pct = abs(s$att) / p$pre_treated_mean * 100,
    att_sd_units = abs(s$att) / p$outcome_sd,
    p
  )
}

plot_china_top_country_panel <- function(panel) {
  plot_panel <- panel %>%
    dplyr::filter(iso3c != "CHN")

  treated_iso <- plot_panel %>%
    dplyr::group_by(iso3c) %>%
    dplyr::summarise(ever_treated = any(china_top == 1L), .groups = "drop") %>%
    dplyr::filter(ever_treated) %>%
    dplyr::pull(iso3c)

  plot_df <- plot_panel %>%
    dplyr::filter(iso3c %in% treated_iso) %>%
    dplyr::arrange(country_name, year)

  treat_periods <- plot_df %>%
    dplyr::group_by(country_name) %>%
    dplyr::arrange(year, .by_group = TRUE) %>%
    dplyr::mutate(
      treatment_period_start = china_top == 1L & dplyr::lag(china_top, default = 0L) == 0L,
      treatment_period_id = cumsum(treatment_period_start)
    ) %>%
    dplyr::filter(china_top == 1L) %>%
    dplyr::group_by(country_name, treatment_period_id) %>%
    dplyr::summarise(
      treat_start = min(year),
      treat_end = max(year),
      .groups = "drop"
    )

  ggplot(plot_df, aes(x = year, y = abs_distance_china)) +
    geom_rect(
      data = treat_periods,
      aes(xmin = treat_start - 0.5, xmax = treat_end + 0.5,
          ymin = -Inf, ymax = Inf),
      inherit.aes = FALSE,
      fill = "lightblue", alpha = 0.3
    ) +
    geom_line(colour = "grey40", linewidth = 0.4) +
    geom_point(size = 0.8, colour = "grey30") +
    geom_smooth(method = "loess", se = FALSE, colour = "steelblue",
                linewidth = 0.8, span = 0.5) +
    facet_wrap(~country_name, scales = "free_y", ncol = 3) +
    labs(x = "Year", y = "UNGA distance to China") +
    theme_minimal(base_size = 10) +
    theme(
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold", size = 9)
    )
}

# Media counterfactual: compare trade-China headlines vs other categories
build_media_counterfactual <- function(folha_file) {
  folha <- readRDS(folha_file)

  folha %>%
    dplyr::filter(year >= 2000, year <= 2014) %>%
    dplyr::mutate(
      broad_category = dplyr::case_when(
        subject == "china-brazil trade" ~ "China-Brazil Trade",
        subject == "chinese economy" ~ "Chinese Economy",
        subject %in% c("china-brazil relations", "diplomacy") ~ "Diplomacy & Relations",
        TRUE ~ "Non-economic (sports, health, disasters, etc.)"
      )
    ) %>%
    dplyr::group_by(year, broad_category) %>%
    dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
    dplyr::group_by(year) %>%
    dplyr::mutate(
      total = sum(n),
      share = n / total * 100
    ) %>%
    dplyr::ungroup()
}

# Cohen's kappa for ChatGPT classification validation
compute_cohens_kappa <- function(validation_file) {
  val <- read.csv(validation_file, sep = ";")
  val$chatgpt <- trimws(tolower(val$chatgpt_label))
  val$manual <- trimws(tolower(val$manual_label))

  n <- nrow(val)
  p_o <- mean(val$chatgpt == val$manual)

  # Expected agreement by chance
  cats <- union(val$chatgpt, val$manual)
  p_e <- sum(sapply(cats, function(c) {
    (sum(val$chatgpt == c) / n) * (sum(val$manual == c) / n)
  }))

  kappa <- (p_o - p_e) / (1 - p_e)

  list(
    kappa = round(kappa, 3),
    p_observed = round(p_o, 3),
    p_expected = round(p_e, 3),
    n = n,
    accuracy_pct = round(p_o * 100, 1)
  )
}

# Raw UNGA distance plot for treated countries (China displaced USA)
plot_treated_country_panel <- function(switching_panel, classified_events) {
  usa_iso <- classified_events %>%
    filter(displaced == "USA", !is.na(iso3c)) %>%
    pull(iso3c)

  panel <- switching_panel %>%
    filter(iso3c %in% usa_iso)

  treat_periods <- panel %>%
    filter(china_top == 1) %>%
    group_by(country_name) %>%
    summarise(treat_start = min(year), treat_end = max(year), .groups = "drop")

  plot_df <- panel %>%
    left_join(treat_periods, by = "country_name")

  ggplot(plot_df, aes(x = year, y = abs_distance_china)) +
    geom_rect(aes(xmin = treat_start - 0.5, xmax = treat_end + 0.5,
                  ymin = -Inf, ymax = Inf),
              fill = "lightblue", alpha = 0.3) +
    geom_line(colour = "grey40", linewidth = 0.4) +
    geom_point(size = 0.8, colour = "grey30") +
    geom_smooth(method = "loess", se = FALSE, colour = "steelblue",
                linewidth = 0.8, span = 0.5) +
    facet_wrap(~country_name, scales = "free_y", ncol = 3) +
    labs(x = "Year", y = "UNGA distance to China") +
    theme_minimal(base_size = 10) +
    theme(
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold", size = 9)
    )
}

goal9_country_name <- function(iso3c) {
  countrycode::countrycode(iso3c, "iso3c", "country.name", warn = FALSE)
}

goal9_export_rank_panel <- function(trade_data) {
  ranked <- trade_data |>
    dplyr::filter(!is.na(year), !is.na(exporter_iso3), !is.na(importer_iso3)) |>
    dplyr::filter(exporter_iso3 != importer_iso3) |>
    dplyr::mutate(exports = dplyr::coalesce(as.numeric(exports), 0)) |>
    dplyr::group_by(year, exporter_iso3) |>
    dplyr::arrange(dplyr::desc(exports), importer_iso3, .by_group = TRUE) |>
    dplyr::mutate(
      partner_rank = dplyr::dense_rank(dplyr::desc(exports)),
      export_total = sum(exports, na.rm = TRUE),
      top_partner = dplyr::first(importer_iso3),
      top_exports = dplyr::first(exports),
      second_partner = dplyr::nth(importer_iso3, 2, default = NA_character_),
      second_exports = dplyr::nth(exports, 2, default = NA_real_)
    ) |>
    dplyr::ungroup()

  ranked |>
    dplyr::filter(importer_iso3 == "CHN") |>
    dplyr::transmute(
      iso3c = exporter_iso3,
      country_name = goal9_country_name(exporter_iso3),
      year,
      china_rank = partner_rank,
      china_exports = exports,
      export_total,
      china_share = dplyr::if_else(export_total > 0, china_exports / export_total, NA_real_),
      top_partner,
      top_partner_name = goal9_country_name(top_partner),
      top_exports,
      second_partner,
      second_partner_name = goal9_country_name(second_partner),
      second_exports,
      china_top = as.integer(china_rank == 1L & china_exports > 0),
      competitor_partner = dplyr::if_else(china_rank == 1L, second_partner, top_partner),
      competitor_partner_name = goal9_country_name(competitor_partner),
      competitor_exports = dplyr::if_else(china_rank == 1L, second_exports, top_exports),
      china_margin_vs_competitor = china_exports - competitor_exports,
      china_margin_over_second = dplyr::if_else(
        china_rank == 1L,
        china_exports - second_exports,
        NA_real_
      ),
      china_gap_to_top = dplyr::if_else(china_rank == 1L, 0, top_exports - china_exports)
    ) |>
    dplyr::arrange(iso3c, year)
}

goal9_brazil_rank_volume_data <- function(trade_data, start_year = 2000L, end_year = 2012L) {
  out <- goal9_export_rank_panel(trade_data) |>
    dplyr::filter(iso3c == "BRA", year >= start_year, year <= end_year) |>
    dplyr::mutate(
      china_share_pct = 100 * china_share,
      # USITC's ITPD-E variable guide defines `trade` as trade flows in
      # millions of current US dollars. Aggregate exports inherit that unit,
      # so dividing by 1000 reports current US$ billions.
      china_exports_usd_billion = china_exports / 1000,
      competitor_exports_usd_billion = competitor_exports / 1000,
      china_margin_vs_competitor_usd_billion = china_margin_vs_competitor / 1000
    ) |>
    dplyr::select(
      iso3c,
      country_name,
      year,
      china_rank,
      china_top,
      china_exports,
      export_total,
      china_share,
      china_share_pct,
      top_partner,
      top_partner_name,
      top_exports,
      second_partner,
      second_partner_name,
      second_exports,
      competitor_partner,
      competitor_partner_name,
      competitor_exports,
      china_exports_usd_billion,
      competitor_exports_usd_billion,
      china_margin_vs_competitor,
      china_margin_vs_competitor_usd_billion,
      china_margin_over_second,
      china_gap_to_top
    )

  stopifnot(nrow(out) == length(start_year:end_year))
  stopifnot(!anyDuplicated(out$year))
  stopifnot(!anyNA(out$china_rank))
  stopifnot(!anyNA(out$china_share))
  stopifnot(!anyNA(out$china_margin_vs_competitor))
  out
}

goal9_plot_brazil_rank_volume <- function(brazil_rank_volume_data) {
  panel_theme <- ggplot2::theme_minimal(base_size = 9.5) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "grey91", linewidth = 0.25),
      plot.title = ggplot2::element_text(face = "bold", size = 9.3),
      axis.title = ggplot2::element_text(size = 9.3),
      axis.text = ggplot2::element_text(size = 8.8),
      plot.margin = ggplot2::margin(4.5, 5.5, 4.5, 5.5)
    )

  share_plot <- ggplot2::ggplot(
    brazil_rank_volume_data,
    ggplot2::aes(x = year, y = china_share_pct)
  ) +
    ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35", linewidth = 0.45) +
    ggplot2::geom_line(colour = "#1B7837", linewidth = 0.85) +
    ggplot2::geom_point(colour = "#1B7837", size = 1.7) +
    ggplot2::scale_x_continuous(breaks = seq(2000, 2012, by = 2)) +
    ggplot2::labs(title = "A. Export share", x = NULL, y = "Export share (%)") +
    panel_theme

  rank_plot <- ggplot2::ggplot(
    brazil_rank_volume_data,
    ggplot2::aes(x = year, y = china_rank)
  ) +
    ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35", linewidth = 0.45) +
    ggplot2::geom_step(colour = "#2166AC", linewidth = 0.85, direction = "mid") +
    ggplot2::geom_point(colour = "#2166AC", size = 1.7) +
    ggplot2::scale_x_continuous(breaks = seq(2000, 2012, by = 2)) +
    ggplot2::scale_y_reverse(breaks = sort(unique(brazil_rank_volume_data$china_rank))) +
    ggplot2::labs(title = "B. Rank", x = NULL, y = "Rank (1 = top)") +
    panel_theme

  margin_plot <- ggplot2::ggplot(
    brazil_rank_volume_data,
    ggplot2::aes(x = year, y = china_margin_vs_competitor_usd_billion)
  ) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.45) +
    ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", colour = "grey35", linewidth = 0.45) +
    ggplot2::geom_col(
      ggplot2::aes(fill = china_margin_vs_competitor_usd_billion >= 0),
      width = 0.72,
      show.legend = FALSE
    ) +
    ggplot2::scale_fill_manual(values = c("TRUE" = "#D55E00", "FALSE" = "#999999")) +
    ggplot2::scale_x_continuous(breaks = seq(2000, 2012, by = 2)) +
    ggplot2::scale_y_continuous(labels = scales::label_number(accuracy = 1)) +
    ggplot2::labs(
      title = "C. Margin",
      x = "Year",
      y = "Margin over competitor\n(US$ billions)"
    ) +
    panel_theme

  patchwork::wrap_plots(
    share_plot,
    rank_plot,
    margin_plot,
    ncol = 1,
    heights = c(1, 1, 1.05)
  )
}

goal9_brazil_rank_volume_placebos <- function(brazil_rank_volume_data,
                                               synth_fit,
                                               se_synth,
                                               placebo_2003_fit,
                                               se_2003,
                                               placebo_2005_fit,
                                               se_2005,
                                               placebo_2012_fit,
                                               se_2012) {
  estimates <- tibble::tibble(
    nominal_treatment_year = c(2003L, 2005L, 2009L, 2012L),
    timing_test = c(
      "placebo_2003_growth_rank2",
      "placebo_2005_growth_no_rank1",
      "actual_2009_rank_reversal",
      "post_placebo_2012_later_shock"
    ),
    rank_volume_test_role = c(
      "Growth/promotion placebo: China is not #1.",
      "Growth placebo: China is not #1.",
      "Actual rank-1 reversal.",
      "Later-shock placebo after rank reversal."
    ),
    estimate = as.numeric(c(placebo_2003_fit, placebo_2005_fit, synth_fit, placebo_2012_fit)),
    se_placebo = as.numeric(c(se_2003, se_2005, se_synth, se_2012))
  ) |>
    dplyr::mutate(
      z = estimate / se_placebo,
      p_value = 2 * stats::pnorm(-abs(z)),
      ci_95_low = estimate - stats::qnorm(0.975) * se_placebo,
      ci_95_high = estimate + stats::qnorm(0.975) * se_placebo,
      inference_status = "Normal approximation using placebo-based SE; timing falsification, not equivalence test."
    )

  estimates |>
    dplyr::left_join(
      brazil_rank_volume_data |>
        dplyr::select(
          nominal_treatment_year = year,
          china_rank,
          china_top,
          china_share,
          china_share_pct,
          china_margin_vs_competitor,
          china_margin_vs_competitor_usd_billion,
          top_partner,
          second_partner,
          competitor_partner
        ),
      by = "nominal_treatment_year"
    ) |>
    dplyr::mutate(
      rank1_reversal = china_rank == 1L & nominal_treatment_year == 2009L
    ) |>
    dplyr::select(
      nominal_treatment_year,
      timing_test,
      rank_volume_test_role,
      china_rank,
      rank1_reversal,
      china_share,
      china_share_pct,
      china_margin_vs_competitor,
      china_margin_vs_competitor_usd_billion,
      top_partner,
      second_partner,
      competitor_partner,
      estimate,
      se_placebo,
      p_value,
      ci_95_low,
      ci_95_high,
      inference_status
    ) |>
    dplyr::arrange(nominal_treatment_year)
}

goal9_make_covariate_array <- function(data, covariate_cols) {
  unit_levels <- unique(data$iso3c)
  time_levels <- sort(unique(data$year))
  x_array <- array(
    NA_real_,
    dim = c(length(unit_levels), length(time_levels), length(covariate_cols)),
    dimnames = list(unit_levels, as.character(time_levels), covariate_cols)
  )

  for (k in seq_along(covariate_cols)) {
    covariate <- covariate_cols[[k]]
    wide <- data |>
      dplyr::select(iso3c, year, value = dplyr::all_of(covariate)) |>
      dplyr::mutate(
        iso3c = factor(iso3c, levels = unit_levels),
        year = factor(year, levels = time_levels)
      ) |>
      dplyr::arrange(iso3c, year) |>
      tidyr::pivot_wider(id_cols = iso3c, names_from = year, values_from = value) |>
      dplyr::arrange(iso3c)

    x_array[, , k] <- wide |>
      dplyr::select(dplyr::all_of(as.character(time_levels))) |>
      as.matrix()
  }

  x_array
}

goal9_fit_sdid_outcome <- function(data, outcome_col, covariate_cols,
                                   time_treatment = 2008L, time_end = 2016L) {
  set.seed(12345)
  required <- c("iso3c", "year", outcome_col, covariate_cols)
  fit_data <- data |>
    dplyr::filter(year < time_end) |>
    dplyr::select(dplyr::all_of(required)) |>
    dplyr::mutate(
      outcome_value = as.numeric(.data[[outcome_col]]),
      treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1L, 0L),
      .unit_treated = as.integer(iso3c == "BRA")
    ) |>
    dplyr::arrange(.unit_treated, iso3c, year) |>
    dplyr::select(-.unit_treated)

  if (anyNA(fit_data |> dplyr::select(outcome_value, dplyr::all_of(covariate_cols)))) {
    stop("goal9_fit_sdid_outcome: missing values in outcome or covariates.")
  }

  x_array <- goal9_make_covariate_array(fit_data, covariate_cols)
  panel_data <- fit_data |>
    dplyr::mutate(
      treatment = as.integer(treatment),
      year = as.integer(year),
      iso3c = as.factor(iso3c),
      Y = outcome_value
    ) |>
    dplyr::select(iso3c, year, Y, treatment) |>
    as.data.frame()

  setup <- synthdid::panel.matrices(panel_data)
  synthdid::synthdid_estimate(Y = setup$Y, N0 = setup$N0, T0 = setup$T0, X = x_array)
}

goal9_sdid_outcome_results <- function(synth_data, unga_data, synth_fit, se_synth) {
  sdid_data <- synth_data |>
    dplyr::left_join(
      unga_data |>
        dplyr::select(iso3c, year, china_agree, us_agree) |>
        dplyr::mutate(china_minus_us_agree = china_agree - us_agree),
      by = c("iso3c", "year")
    ) |>
    dplyr::mutate(relative_distance_china_minus_usa = abs_distance_china - abs_distance_usa)

  covariates <- c(
    "gpi",
    "perc_trade_with_us",
    "perc_trade_with_china",
    "pci_cur",
    "exachange_rate",
    "distance_us",
    "us_power_gap",
    "hog_left",
    "CA_GDP",
    "govdef_GDP",
    intersect(
      c("inst_parliamentary", "inst_military_exec", "us_trade_agreement"),
      names(sdid_data)
    )
  )

  outcome_info <- tibble::tribble(
    ~outcome, ~label, ~causal_status, ~expected_direction,
    "abs_distance_china", "Absolute Brazil-China ideal-point distance", "Brazil SDiD reduced-form estimate with placebo SE", "negative",
    "relative_distance_china_minus_usa", "China-minus-US ideal-point distance", "alternative country-year SDiD robustness; point estimate only", "negative",
    "abs_distance_usa", "Absolute ideal-point distance to the United States", "secondary country-year SDiD diagnostic; point estimate only", "positive",
    "china_agree", "Annual vote agreement with China", "agenda-sensitive country-year diagnostic; point estimate only", "positive",
    "china_minus_us_agree", "Annual agreement with China minus agreement with the United States", "agenda-sensitive country-year diagnostic; point estimate only", "positive"
  )

  dplyr::bind_rows(lapply(seq_len(nrow(outcome_info)), function(i) {
    row <- outcome_info[i, ]
    if (row$outcome == "abs_distance_china") {
      estimate <- as.numeric(synth_fit)
      se <- as.numeric(se_synth)
      inference_status <- "Placebo SE from existing target se_synth."
    } else {
      estimate <- as.numeric(goal9_fit_sdid_outcome(sdid_data, row$outcome, covariates))
      se <- NA_real_
      inference_status <- "Point estimate only; placebo SE not recomputed for exploratory outcome robustness."
    }

    tibble::tibble(
      outcome = row$outcome,
      label = row$label,
      causal_status = row$causal_status,
      estimate = estimate,
      se_placebo = se,
      p_value = ifelse(is.na(se), NA_real_, 2 * stats::pnorm(-abs(estimate / se))),
      ci_95_low = ifelse(is.na(se), NA_real_, estimate - stats::qnorm(0.975) * se),
      ci_95_high = ifelse(is.na(se), NA_real_, estimate + stats::qnorm(0.975) * se),
      inference_status = inference_status,
      expected_direction = row$expected_direction,
      direction_matches_expected_sign = dplyr::case_when(
        row$expected_direction == "negative" ~ estimate < 0,
        row$expected_direction == "positive" ~ estimate > 0,
        TRUE ~ NA
      )
    )
  }))
}

goal9_human_rights_vs_non_human_rights <- function(resolution_data, treatment_year = 2009L) {
  resolution_data |>
    dplyr::mutate(
      period = dplyr::if_else(year < treatment_year, "pre_2009", "post_2009"),
      human_rights_issue = stringr::str_detect(issue_family, "Human rights")
    ) |>
    dplyr::group_by(rcid, period) |>
    dplyr::summarise(
      identical_vote = dplyr::first(identical_vote),
      similarity_score = dplyr::first(similarity_score),
      hr_group = dplyr::if_else(any(human_rights_issue, na.rm = TRUE), "Human rights", "Non-human-rights"),
      .groups = "drop"
    ) |>
    dplyr::group_by(hr_group, period) |>
    dplyr::summarise(
      n_resolutions = dplyr::n_distinct(rcid),
      identical_vote_share = 100 * mean(identical_vote, na.rm = TRUE),
      mean_similarity_score = mean(similarity_score, na.rm = TRUE),
      .groups = "drop"
    ) |>
    tidyr::pivot_wider(
      names_from = period,
      values_from = c(n_resolutions, identical_vote_share, mean_similarity_score)
    ) |>
    dplyr::mutate(
      delta_identical_vote_share = identical_vote_share_post_2009 - identical_vote_share_pre_2009,
      delta_mean_similarity_score = mean_similarity_score_post_2009 - mean_similarity_score_pre_2009
    ) |>
    dplyr::select(
      hr_group,
      n_resolutions_pre_2009,
      n_resolutions_post_2009,
      identical_vote_share_pre_2009,
      identical_vote_share_post_2009,
      mean_similarity_score_pre_2009,
      mean_similarity_score_post_2009,
      delta_identical_vote_share,
      delta_mean_similarity_score
    )
}
