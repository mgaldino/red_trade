synth_data <- teste %>%
  group_by(iso3c) %>%
  arrange(iso3c, year) %>% 
  ungroup() %>%
  mutate(latin_america = region_o %in% c("south_america", "central_america", "north_america") & 
           !iso3c %in% c("USA", "CAN")) %>%
  dplyr::filter(year > 1990 & year < 2016) %>%
  dplyr::select(iso3c, year, pop, abs_distance_china, gdp_cur, ideal_point_all, abs_distance_usa, gpi,
                us_power_gap, us_ideal, abs_distance_usa, gpi, trade_with_china, trade_with_us, total_trade,
                distance_us, distance_china, exachange_rate, latin_america) %>%
  arrange(year) %>%
  mutate(pci_cur = gdp_cur/pop,
         perc_trade_with_china = trade_with_china/total_trade,
         perc_trade_with_us = trade_with_us/total_trade) %>%
  tidyr::drop_na() 

summary(synth_data)

exclude_countries <- synth_data %>%
  group_by(iso3c) %>%
  summarise(num_obs = n()) %>%
  dplyr::filter(num_obs < 24) %>%
  pull(iso3c)


tar_read(folha_df) %>%
  filter(month(date_piece) %in% 1)

library(topicmodels)

ap_lda <- LDA(AssociatedPress, k = 10, control = list(seed = 1234))
ap_lda

library(tidytext)

ap_topics <- tidy(ap_lda, matrix = "beta")
ap_topic

library(ggplot2)
library(dplyr)

ap_top_terms <- ap_topics %>%
  group_by(topic) %>%
  slice_max(beta, n = 10) %>% 
  ungroup() %>%
  arrange(topic, -beta)

ap_top_terms %>%
  mutate(term = reorder_within(term, beta, topic)) %>%
  ggplot(aes(beta, term, fill = factor(topic))) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ topic, scales = "free") +
  scale_y_reordered()

library(tidyr)
library(tidyverse)      # dplyr, tibble etc.
library(tidytext)       # unnest_tokens(), cast_dtm()
library(topicmodels)     # LDA()
library(tm)             # Term-Document/Document-Term Matrix classes
library(quanteda)





folha <- tar_read(folha_df) %>% 
  mutate(doc_id = row_number())

create_list_graphs <- function(data) {
  data$date_piece[1] <- as.Date("2008-06-07", "%Y-%m-%d")
  
  
  folha <- data %>%
    mutate(year = lubridate::year(date_piece))
  
  stop_pt <- stopwords(source = "stopwords-iso",
                       language = "pt")
  
  folha_2000 <- folha %>%
    filter(year > 1999)
  
  year_filter <- sort(unique(folha_2000$year))
  year_filter[seq(1, length(year_filter), 3)]
  
  plots   <- list()       # lista vazia
  idx     <- 1   
  
  for (i  in seq(1, length(year_filter), 3)) {
    data <- folha_2000 %>%
      filter(year == year_filter[i])
    
    tidy_folha <- data %>%
      unnest_tokens(bigram, title, token = "ngrams", n = 2, drop=FALSE)
    
    bigrams_separated <- tidy_folha %>%
      separate(bigram, c("word1", "word2"), sep = " ")
    
    
    bigrams_filtered <- bigrams_separated %>%
      filter(!word1 %in% stop_pt) %>%
      filter(!word2 %in% stop_pt)
    
    bigram_counts <- bigrams_filtered %>% 
      count(word1, word2, sort = TRUE)
    
    bigram_graph_filtered <- bigram_counts %>%
      filter(n > 18) %>%
      graph_from_data_frame()
    
    set.seed(100)
    a <- grid::arrow(type = "closed", length = unit(.2, "inches"))
    
    plots[[idx]] <-                     # salva o grafo como ggplot
      ggraph(bigram_graph, layout = "fr") +
      geom_edge_link(aes(edge_alpha = n),
                     arrow     = a,
                     end_cap   = circle(.07, 'inches'),
                     show.legend = FALSE) +
      geom_node_point(color = "lightblue", size = 3) +
      geom_node_text(aes(label = name), vjust = 1, hjust = 1) +
      theme_void() +
      ggtitle(year_filter[i])         # (opcional) título por ano
    
    idx <- idx + 1    
    
  }
  return(plots)
}

folha$date_piece[1] <- as.Date("2008-06-07", "%Y-%m-%d")

folha <- folha %>%
  mutate(year = lubridate::year(date_piece))

stop_pt <- stopwords(source = "stopwords-iso",
                                   language = "pt")

folha_2000 <- folha %>%
  filter(year > 2002 & year < 2014)

year_filter <- sort(unique(folha_2000$year))


plots   <- list()       # lista vazia
idx     <- 1   

for (i  in seq(1, length(year_filter), 3)) {
  data <- folha_2000 %>%
    filter(year == 2008)
  
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
    filter(n > 5)                        # seu corte
  
  ## 3. Criar grafo --------------------------------------------------------
  set.seed(1234)
  trigram_graph <- graph_from_data_frame(edges, directed = FALSE)
  
  ## 4. Plotar -------------------------------------------------------------
  a <- grid::arrow(type = "closed", length = unit(.2, "inches"))
  ggraph(trigram_graph, layout = "fr") +
    geom_edge_link(aes(edge_alpha = n),
                   arrow     = a,
                   end_cap   = circle(.07, 'inches'),
                   show.legend = FALSE) +
    geom_node_point(color = "lightblue", size = 3) +
    geom_node_text(aes(label = name), vjust = 1, hjust = 1) +
    theme_void() +
    ggtitle(year_filter[i])
  
  idx <- idx + 1    
  
}



bigrams_separated <- tidy_folha %>%
  separate(bigram, c("word1", "word2"), sep = " ")

bigrams_filtered <- bigrams_separated %>%
  filter(!word1 %in% stop_pt) %>%
  filter(!word2 %in% stop_pt)

bigram_counts <- bigrams_filtered %>% 
  count(word1, word2, sort = TRUE)

bigram_counts


bigrams_united <- bigrams_filtered %>%
  unite(bigram, word1, word2, sep = " ")

bigrams_united

library(udpipe)

# Annotation (co-occurrences of verbs and nouns)
udmodel <- udpipe_download_model(language = "portuguese-gsd")

anno <- data.frame(doc_id = folha$doc_id, text = folha$title,
                   stringsAsFactors = FALSE)
anno <- udpipe(anno, "portuguese-gsd", trace = 10)

## Get cooccurrences of nouns / adjectives and proper nouns
biterms <- as.data.table(anno)
biterms <- biterms[, cooccurrence(x = lemma, 
                                  relevant = upos %in% c("ADJ", "PROPN"),
                                  skipgram = 2), 
                   by = list(doc_id)]

# Model
library(BTM)

set.seed(123456)
x     <- subset(anno, upos %in% c("VERB", "PROPN", "NOUN", "ADJ", "NUM"))
x     <- x[, c("doc_id", "lemma")]
model <- BTM(x, k = 20, beta = 0.01, iter = 2000, background = TRUE, 
             biterms = biterms, trace = 100)

topicterms <- terms(model, top_n = 5)

topicterms

# visualization
library(igraph)
library(ggraph)

bigram_graph <- bigram_counts %>%
  graph_from_data_frame()

bigram_graph_filtered <- bigram_counts %>%
  filter(n > 18) %>%
  graph_from_data_frame()

bigram_graph_filtered

set.seed(100)

a <- grid::arrow(type = "closed", length = unit(.2, "inches"))

ggraph(bigram_graph_filtered, layout = "fr") +
  geom_edge_link(aes(edge_alpha = n), show.legend = FALSE,
                 arrow = a, end_cap = circle(.07, 'inches')) +
  geom_node_point(color = "lightblue", size = 3) +
  geom_node_text(aes(label = name), vjust = 1, hjust = 1) +
  theme_void()

library(textplot)
library(ggraph)
library(concaveman)

plot(model)

doc_topics <- predict(model,           # objeto BTM
                      newdata = x)     # data-frame (doc_id, lemma)

# Estrutura típica de doc_topics:
#   doc_id  topic  gamma
#   1       12     0.74
#   1        5     0.18
#   1       17     0.08
#   2        5     0.62
#   ...


dominant <- tibble(
  doc_id = as.integer(rownames(doc_topics)),          # ou seq_len(nrow(doc_topics))
  topic  = max.col(doc_topics, ties.method = "first"),# índice do máx por linha
  gamma  = doc_topics[cbind(seq_len(nrow(doc_topics)),
                            max.col(doc_topics))]
)

headline_topics <- folha |>
  left_join(dominant, by = "doc_id")
# tópicos 18 e 14

headline_topics %>%
  filter(topic %in% c(18))

## network graph topic 18

folha_18 <- folha %>%
  left_join(dominant, by = "doc_id") %>%
  filter(topic %in% c(18)) %>%
  unnest_tokens(bigram, title, token = "ngrams", n = 2, drop=FALSE)


bigrams_separated_18 <- folha_18 %>%
  separate(bigram, c("word1", "word2"), sep = " ")

bigrams_filtered_18 <- bigrams_separated_18 %>%
  filter(!word1 %in% stop_pt) %>%
  filter(!word2 %in% stop_pt)

bigram_counts_18 <- bigrams_filtered_18 %>% 
  count(word1, word2, sort = TRUE)

bigram_graph <- bigram_counts_18 %>%
  graph_from_data_frame()

bigram_graph_filtered <- bigram_counts_18 %>%
  filter(n > 11) %>%
  graph_from_data_frame()


a <- grid::arrow(type = "closed", length = unit(.2, "inches"))

ggraph(bigram_graph_filtered, layout = "fr") +
  geom_edge_link(aes(edge_alpha = n), show.legend = FALSE,
                 arrow = a, end_cap = circle(.07, 'inches')) +
  geom_node_point(color = "lightblue", size = 3) +
  geom_node_text(aes(label = name), vjust = 1, hjust = 1) +
  theme_void()

##

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
  filter(n > 5)                        # seu corte

## 3. Criar grafo --------------------------------------------------------
trigram_graph <- graph_from_data_frame(edges, directed = FALSE)

## 4. Plotar -------------------------------------------------------------
a <- grid::arrow(type = "closed", length = unit(.2, "inches"))
ggraph(trigram_graph, layout = "fr") +
  geom_edge_link(aes(edge_alpha = n),
                 arrow     = a,
                 end_cap   = circle(.07, 'inches'),
                 show.legend = FALSE) +
  geom_node_point(color = "lightblue", size = 3) +
  geom_node_text(aes(label = name), vjust = 1, hjust = 1) +
  theme_void()
