# Dicionário — piloto de coautoria na OMC

## Convenções centrais

- `CHN`: República Popular da China.
- `HKG`: Hong Kong, China, membro distinto da OMC. Nunca é convertido em `CHN`.
- `family_root`: símbolo sem sufixos `Rev`, `Add` ou `Corr`.
- `canonical_family`: símbolo estável escolhido entre símbolos paralelos para deduplicar a família.
- Grupos como `African Group` não são expandidos para países individuais.

## Arquivos principais

### `wto_pilot_coded_records_2000_2014.csv`

- `catalogue_id`: identificador do catálogo oficial.
- `symbol`: símbolo oficial exibido.
- `title`: título oficial exibido na busca; pode conter abreviação `[...]` da interface.
- `query_partners`: buscas por pares nas quais o registro apareceu.
- `coded_authors`: países rastreados classificados como autores.
- `coding_source`: `manual_pdf_first_page_or_full_text` ou regra provisória de título.
- `coded_category`: proposta/comunicação, declaração, disputa/menção ou caso não resolvido.
- `in_strict_universe`: 1 para proposta, paper, comunicação ou contribuição negocial conjunta.
- `in_broad_coordination_universe`: adiciona declarações e cartas conjuntas; exclui disputas e menções.
- `authors_inferred_from_truncated_query`: imputação motivada pela abreviação do título.
- `china_hong_kong_ambiguity`: alerta quando a busca por China pode refletir somente HKG.

### `wto_strict_dyad_family_events_2000_2014.csv`

Uma linha por família e parceiro, na primeira data observada em que Brasil e parceiro aparecem como autores. Isso evita contar cada revisão como nova proposta, mas preserva o ingresso posterior de um coautor.

- `event_date`, `year`, `period_2009`, `window_2005_2012`: tempo do primeiro co-patrocínio observado.
- `authors_at_event`: autores rastreados nessa versão.
- `china_without_india_or_south_africa`: subconjunto discriminante Brasil–China.
- `india_or_south_africa_without_china`: subconjunto Sul–Sul sem China.
- `coverage_note`: lembra que a origem é uma busca de título condicionada ao par.

### `wto_dyad_year_outcomes.csv`

- `n_new_coauthored_families`: novas famílias coapresentadas por díade-ano no universo estrito.
- `share_all_brazilian_submissions_with_partner`: vazio por desenho; o denominador de todas as submissões brasileiras não foi coletado.
- `denominator_status`: justificativa da ausência do denominador.

### Validação

- `wto_manual_validation_results_40.csv`: 40 casos do primeiro sorteio estratificado, com símbolo, link oficial, autores, evidência e decisão.
- `wto_mention_validation_results_20.csv`: 20 menções/falsos positivos reais, todos conferidos em PDF.
- `wto_*_first_pages.txt`: primeira página extraída para auditoria textual.

