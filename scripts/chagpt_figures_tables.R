library(ggplot2)
library(tidyverse)
library(janitor)
# table 
library(gt)       
library(gtsummary)    

data1 <- readRDS("folha_classificado.rds")

data2 <- data1 %>%
  filter(grepl("trade", subject)) %>%
  filter(year == 2004)

data2 %>%
  mutate(soja = grepl("soja|óleo", title)) %>%
  summarise(sum(soja), n())

data2 %>%
  mutate(market_economy = grepl("economia de mercado|[Aa]cordo|dumping", title)) %>%
  summarise(sum(market_economy), n())


data1 %>%
  summarise(num = n()) 


p_basic <- data1 %>%
  group_by(year) %>%
  summarise(num = n()) %>%
  arrange(num) %>%
  filter( year < 2014) %>%
  ggplot(aes(x=year, y=num)) + geom_point() + geom_line() + theme_bw() +
  ylab("Number of news pieces")

ggsave("images/num_headlines.png" ,p_basic,  width  = 6, 
       height = 4, 
       units  = "in",
       bg     = "white")


p1 <- data1 %>%
  mutate(subject = str_trim(subject),
         subject = gsub("brasil", "brazil", subject),
         year = year(date_piece)) %>%
  group_by(year, subject) %>%
  summarise(num = n()) %>%
  arrange(subject, year) %>%
  filter(grepl("trade|economy|health|accident|human" ,subject )) %>%
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
  ylab("Year over Year Growth in the number of headlines") + scale_y_continuous(labels = scales::label_percent())

ggsave("images/yoy_growth_headlines.png" ,p1,  width  = 6, 
       height = 4, 
       units  = "in",
       bg     = "white")

pretty_labels <- c(
  prop_tradebr_economy   = "Trade / Economy",
  prop_tradebr_health    = "Trade / Health",
  prop_tradebr_accidents = "Trade / Disasters"
)


p2 <- data1 %>%
  mutate(subject = str_trim(subject),
         subject = gsub("brasil", "brazil", subject),
         year = year(date_piece)) %>%
  group_by(year, subject) %>%
  summarise(num = n()) %>%
  arrange(year, num) %>%
  ungroup() %>%
  mutate(total = sum(num), .by=year) %>%
  pivot_wider(names_from = subject, values_from = num) %>%
  clean_names() %>%
  mutate(prop_tradebr_economy = china_brazil_trade/chinese_economy,
         prop_tradebr_health = china_brazil_trade/health,
         prop_tradebr_accidents = china_brazil_trade/disaster_and_accidents) %>%
  dplyr::select(year, prop_tradebr_economy, prop_tradebr_health, prop_tradebr_accidents) %>%
  pivot_longer(cols = prop_tradebr_economy:prop_tradebr_accidents, names_to = "subject", values_to = "frequency") %>%
  filter(year > 2006) %>%
  mutate(subject = factor(subject, levels = names(pretty_labels),
                          labels = pretty_labels)) %>%
  ggplot(aes(x=year, y=frequency)) + geom_line() + geom_point() + 
  facet_wrap(~ subject, ncol=1, scales = "free") + scale_y_continuous(labels = scales::label_percent()) + theme_bw() +
  ylab("Proportion of trade headlines to other subjects") 

ggsave("images/prop_trade_headlines.png" ,p2,  width  = 6, 
       height = 4, 
       units  = "in",
       bg     = "white")

p3 <- data1 %>%
  mutate(subject = str_trim(subject),
         subject = gsub("brasil", "brazil", subject),
         year = year(date_piece)) %>%
  group_by(year, subject) %>%
  summarise(num = n()) %>%
  arrange(year, num) %>%
  ungroup() %>%
  mutate(total = sum(num), .by=year) %>%
  pivot_wider(names_from = subject, values_from = num) %>%
  clean_names() %>%
  mutate(prop = china_brazil_trade/total) %>%
  dplyr::select(year, prop) %>%
  ggplot(aes(x=year, y=prop)) + geom_line() + geom_point() + 
  scale_y_continuous(labels = scales::label_percent()) + theme_bw() +
  theme_bw() +
  ylab("Proportion of trade headlines to all subjects") 

ggsave("images/prop_trade_headlines_all.png" ,p3,  width  = 6, 
       height = 4, 
       units  = "in",
       bg     = "white")




set.seed(123)          # reproducible sampling

tbl_headlines <-
  data1 %>%
  group_by(subject) %>%
  sample_n(2) %>%                      
  rename(
    Headline        = title,          # rename for clarity
    Classification  = subject,          # ChatGPT category
    Date = date_piece
  ) %>% 
  dplyr::select(Headline,Classification, Date ) %>%
  gt() %>% 
  tab_header(
    title    = md("**TABLE 3 — Examples of Classified Headlines**"),
    subtitle = md("Archived headline examples with ChatGPT-assigned topic")
  ) %>% 
  cols_width(
    Headline       ~ pct(50),            # wider text column
    Classification ~ pct(30),
    Date ~ pct(20)
  ) %>% 
  opt_stylize(style = 3)                 # APSR‑ish minimal style

# Save (optional)
gtsave(tbl_headlines, "images/table1_headlines.png", expand = 10)
