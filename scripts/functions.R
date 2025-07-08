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

# DPI

# get_dpi <- function(file) {
#   dpi <- fread(file) 
#   
#   dpi_final <- dpi %>%
#     dplyr::filter(execrlc %in% 1:3) %>%
#     mutate(parlamentary = ifelse(system == 2, 1, 0),
#            left = ifelse(execrlc == 3, 1, 0)) %>%
#     dplyr::select(ifs, year, parlamentary, left, execme) %>%
#     dplyr::filter(ifs != "0") %>%
#     rename(iso3c = ifs) %>%
#     arrange(iso3c, year)
#   
# }

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
    dplyr::filter(importer_iso3 == "CHN")
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

##############
# Modeling
##############

# prep data for SDiD

## clean dataset
clean_synth_data <- function(data) {
  
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
                  govdef_GDP, gdp_growth) %>%
    arrange(year) %>%
    mutate(pci_cur = gdp_cur/pop,
           perc_trade_with_china = trade_with_china/total_trade,
           perc_trade_with_us = trade_with_us/total_trade) %>%
    drop_na()
  
  exclude_countries <- synth_data %>%
    group_by(iso3c) %>%
    summarise(num_obs = n()) %>%
    dplyr::filter(num_obs < max(num_obs, na.rm=T)) %>%
    pull(iso3c)
  
  
  synth_data <- synth_data %>%
    dplyr::filter(!iso3c %in% exclude_countries)
  
  
  synth_data <- synth_data %>%
    mutate(treatment = ifelse(iso3c == "BRA" & year > 2008, 1, 0))
  
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
                  govdef_GDP)
  
  return(df)
}


## Create preditcor matrix
cov_matrix <- function(data) {
  mat_X <- data %>%
    dplyr::select(year, iso3c, gpi, perc_trade_with_us, perc_trade_with_china, pci_cur,
                  exachange_rate, distance_us, us_power_gap, hog_left, CA_GDP,
                  govdef_GDP)
  
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
  if(filter_latin_america) {
    data <- data %>%
      dplyr::filter(latin_america)
  }
  
  data <- data %>%
    dplyr::filter(year < time_end) %>%
    mutate(treatment = ifelse(iso3c == "BRA" & year > time_treatment, 1, 0))
  
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

