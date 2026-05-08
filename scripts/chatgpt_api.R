library(ellmer)
library(jsonlite)
library(stringr)
library(tidyverse)
library(keyring)
library(tidyr)
library(janitor)


data <- tar_read(folha_df) 
model = "gpt-4o-mini"
system_block <- paste(
  'You are a Brazilian expert in International Relations and the political',
  'economy of China–Brazil relations.  Classify the subject of EACH headline',
  'whe I say EACH, I mean all of them, even if repetitive or similar. Do classify **all** of them',
  'using **one** label from this list exactly as written:',
  '"diplomacy", "chinese economy", "china-brasil relations",',
  '"disaster and accidents", "chinese politics and policy",',
  '"sports, science, culture, other", "human rights",',
  '"china-brazil trade", "health".\n\n',
  # 13 static few-shot examples — leave them unchanged!
  'Examples:\n',
  '1. Presidente chinês visita o Brasil e participa de reunião com FHC -> china-brasil relations\n',
  '2. Ministro chinês de Defesa faz visita oficial ao Brasil -> china-brasil relations\n',
  '3. Para governo, novo câmbio chinês só beneficia Brasil no médio prazo -> china-brazil trade\n',
  '4. China ultrapassa EUA como maior parceiro comercial do Brasil -> china-brazil trade\n',
  '5. China vai controlar preços de alimentos e combustíveis -> chinese economy\n',
  '6. Vendas de automóveis na China desaceleram em junho -> chinese economy\n',
  '7. China quer devolução das relíquias Yin, patrimônio da Unesco -> sports, science, culture, other\n',
  '8. Dinossauro encontrado na China esclarece origem das aves -> sports, science, culture, other\n',
  '9. OMS confirma mais de 4.600 casos de gripe suína; China registra 2º caso -> health\n',
  '10. Marinha chinesa busca "cansar" barcos japoneses em águas disputadas -> diplomacy\n',
  '11. Acidente após casamento deixa 16 mortos na China -> disaster and accidents\n',
  '12. Jornal chinês sai das bancas por foto da praça Tiananmen -> human rights\n',
  '13. China é parceira estratégica contra crise econômica, diz UE -> chinese economy',
  'return as in the examples, a string with the headline and the classification'
)

# collecting classification from chatgpt
data <- tar_read(folha_df) %>%
  distinct(title, .keep_all = TRUE) %>%
  dplyr::filter(stringr::str_detect(title, regex("China|chin(ês|esa)", ignore_case = TRUE))) 

result <- list()
vec <- seq(1, nrow(data), by=500)
for ( i in 1:(length(vec)-1)) {
  print(i)

  chat <- ellmer::chat_openai(
    system_prompt = system_block,
    model         = "gpt-4.1-mini",
    params        = ellmer::params(temperature = 0),
    api_key = keyring::key_get("OPENAI_API_KEY")
  )
  
  title <- data %>%
    dplyr::mutate(title = stringr::str_replace_all(title, "(\\\\|\\\"{2})", "")) %>%
    slice(vec[i]:(vec[i+1]-1)) %>% # 3648
    dplyr::pull(title)
  
  result[[i]] <- chat$chat(title)
}

token_usage()

list_aux <- list()
list_aux2 <- list()
list_aux3 <- list()
list_df <- list()
for ( i in 1:length(result)) {
  
  list_aux[[i]] <- str_split_1(result[[i]], pattern = "\n")
  list_aux2[[i]] <- str_split_i(list_aux[[i]], pattern = "->", 1)
  list_aux3[[i]] <- str_split_i(list_aux[[i]], pattern = "->", 2)
  list_df[[i]] <- tibble(title = list_aux2[[i]], subject = list_aux3[[i]])
}

df_classifcation <- bind_rows(list_df) %>%
  mutate(model = "gpt-4.1-mini",
         title = str_trim(title),
         subject = str_trim(subject),
         title = gsub("^[0-9]+\\.\\s*", "", title)) %>%
  distinct(title, .keep_all = TRUE)


saveRDS(df_classifcation, "df_classifcation.rds")




data$date_piece[1] <- as.Date("2008-06-07") # fix date that was wrongly informed in the original dataset
data1 <- data %>%
  inner_join(df_classifcation, by = join_by(title)) %>%
  mutate(subject = str_trim(subject),
         subject = gsub("brasil", "brazil", subject),
         year = year(date_piece)) 

saveRDS(data1, "folha_classificado.rds")
