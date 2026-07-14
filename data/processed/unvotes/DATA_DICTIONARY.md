# Dicionário de dados: casos Brasil-China na AGNU

## brazil_china_un_vote_cases_2004_2012.csv

| Variável | Tipo | Descrição | Fonte |
|---|---|---|---|
| case_id | texto | Identificador do conjunto comparável de resoluções | Autor |
| theme | texto | Tema substantivo do conjunto comparável | Autor, com base em short/descr/issue |
| doc_symbol | texto | Símbolo oficial da resolução em formato A/RES/session/number | unvotes; transformação de unres |
| case_type | texto | Tipo de caso: positivo/negativo e papel pré/pós-2009 | Autor |
| selection_note | texto | Justificativa resumida da seleção do caso | Autor |
| rcid | numérico | Identificador do roll call no banco unvotes | unvotes |
| year | numérico | Ano da votação | unvotes |
| short | texto | Rótulo curto da votação | unvotes |
| descr | texto | Descrição da votação | unvotes |
| issue | texto | Tema(s) codificado(s) no unvotes | unvotes |
| title_key | texto | Chave normalizada da descrição, usada para auditar temas recorrentes | Autor |
| vote_brazil | texto | Voto do Brasil | unvotes |
| vote_china | texto | Voto da China | unvotes |
| convergence | texto | Convergente quando Brasil e China votam igual; divergente caso contrário | Autor |
| evidence_available | texto | Evidência documental disponível nesta rodada | Autor |
| document_url | texto | Link para o texto oficial da resolução | UN docs |
| vote_record_url | texto | Link de busca na UN Digital Library pelo registro da resolução/voto | UN Digital Library |
| source | texto | Fonte e data de acesso | Autor |

## brazil_china_un_vote_candidate_themes_2004_2012.csv

Tabela auditável de todos os títulos recorrentes no período que satisfazem pelo menos uma regra de candidato: divergência pré-2009 e convergência pós-2009, ou divergência pré-2009 e divergência pós-2009. A coluna `selected` indica se o tema entrou na tabela final.

## brazil_china_un_vote_case_validation_2004_2012.csv

Tabela de validação dos casos selecionados. Casos positivos precisam ter ao menos uma divergência pré-2009 e uma convergência pós-2009. Casos negativos precisam ter ao menos uma divergência pré-2009 e uma divergência pós-2009.

## brazil_china_un_vote_process_tracing_documents_2004_2012.csv

Inventário documental coletado para process tracing dos votos selecionados.

| Variável | Tipo | Descrição | Fonte |
|---|---|---|---|
| case_id | texto | Identificador do conjunto comparável de resoluções | Autor |
| theme | texto | Tema substantivo do caso | Autor |
| year | inteiro | Ano da resolução/voto | unvotes |
| issue | texto | Tema codificado no unvotes | unvotes |
| source_resolution | texto | Resolução de origem da busca documental | UN docs |
| document_layer | texto | Camada documental: resolução, relatório, draft, ata de comitê, busca nacional, candidato de missão | Autor |
| document_symbol | texto | Símbolo oficial ONU quando disponível | UN docs |
| committee | texto | Comitê associado ao documento quando identificado | UN docs |
| url | texto | URL pública de acesso ou busca | UN docs; UN Digital Library; missão nacional |
| local_path | texto | Caminho local do arquivo bruto preservado | Autor |
| download_status | texto | Status de download/coleta | Autor |
| notes | texto | Contexto de extração ou observação de escopo | Autor |
| date_accessed | data | Data de acesso | Autor |

## brazil_china_un_vote_committee_speech_evidence_2004_2012.csv

Tabela bruta de falas de Brasil/China detectadas nas atas do Terceiro Comitê ligadas às resoluções de direitos humanos.

| Variável | Tipo | Descrição | Fonte |
|---|---|---|---|
| case_id | texto | Identificador do conjunto comparável | Autor |
| theme | texto | Tema substantivo do caso | Autor |
| doc_symbol | texto | Resolução de origem | UN docs |
| year | inteiro | Ano da resolução/voto | unvotes |
| country | texto | País do orador buscado | Autor |
| vote | texto | Voto do país na resolução | unvotes |
| committee_record_symbol | texto | Símbolo da ata do Terceiro Comitê | UN docs |
| committee_record_url | texto | Link para a ata | UN docs |
| draft_symbols | texto | Drafts identificados no relatório de comissão | UN docs |
| speech_found_in_record | lógico | Indica se houve fala do país na ata | Autor |
| speech_found_for_case | lógico | Indica se a fala foi associada automaticamente ao caso | Autor |
| relevance_rule | texto | Regra automática de associação | Autor |
| speaker_excerpt | texto | Trecho extraído da ata | UN docs |
| source_note | texto | Nota de fonte | Autor |
| date_accessed | data | Data de acesso | Autor |

## brazil_china_un_vote_speech_evidence_curated_2004_2012.csv

Subconjunto curado da tabela bruta de falas. Mantém apenas falas cujo trecho do próprio orador contém palavras-chave substantivas do tema do caso.

## brazil_china_un_vote_undl_speeches_search_2004_2012.csv

Resultados das buscas na coleção `Speeches` da UN Digital Library por país, tema, sessão e símbolos de documentos.

| Variável | Tipo | Descrição | Fonte |
|---|---|---|---|
| case_id | texto | Identificador do conjunto comparável | Autor |
| theme | texto | Tema substantivo do caso | Autor |
| doc_symbol | texto | Resolução de origem | UN docs |
| year | inteiro | Ano da resolução/voto | unvotes |
| country | texto | País usado na busca | Autor |
| query_type | texto | Tipo de consulta: tema/sessão, resolução, draft, ata ou plenária | Autor |
| query | texto | Termos enviados à busca | Autor |
| search_url | texto | URL da busca HTML | UN Digital Library |
| rss_url | texto | URL RSS da busca | UN Digital Library |
| rss_local_path | texto | Caminho local do RSS preservado | Autor |
| download_status | texto | Status de download do RSS | Autor |
| items_found | inteiro | Número de itens retornados | UN Digital Library |
| first_item_title | texto | Primeiro título retornado, quando disponível | UN Digital Library |
| first_item_link | texto | Primeiro link de registro retornado | UN Digital Library |
| date_accessed | data | Data de acesso | Autor |

## brazil_china_un_vote_mission_statement_candidates_2004_2012.csv

Registros públicos da Missão Permanente da China junto à ONU coletados como candidatos de evidência discursiva nacional.

## brazil_china_un_vote_process_tracing_summary_2004_2012.csv

Tabela de síntese por resolução com contagens de relatórios, drafts, atas do Terceiro Comitê, falas curadas, resultados da UN Digital Library e candidatos de missão nacional.
