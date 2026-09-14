# Ações concretas ainda dependentes de autorização

## 1. Hook global: autorização específica pendente

O usuário autorizou o commit local e a promoção dos artefatos revisados foi concluída. A revisão automática rejeitou a alteração global em `auto_commit_push.py`, por não considerar a autorização de commit suficiente para modificar esse arquivo. Foi solicitada autorização explícita para o hook e o marcador `.codex-no-auto-checkpoint`. O patch e o teste simulado continuam prontos; nenhum deles foi aplicado.

O hook ainda pode fazer push automaticamente ao encerrar a tarefa. Push não está autorizado. A alteração proposta retorna antes dos comandos Git quando existir o marcador local; os demais repositórios não são afetados. Ver `hook_guard_proposal.patch`, `hook_guard_test.json` e `hook_approval_block.json`.

## 2. Corpus e validação: itens 4, 7 e 8

A documentação qualitativa pode ser corrigida agora. A camada numérica nova deve entrar no grafo antes de ser usada no paper. Entradas: os arquivos arquivados de recuperação/classificação, o produtor e prompt preservados e `data/folha_validation_sample_annotated.csv`. Criar uma auditoria do corpus que reporte hashes, cobertura de datas, tipos, ausências, duplicatas, diferenças entre conjuntos de títulos e perdas nas junções. Reutilizar o mesmo manifesto para evitar auditorias desconectadas.

Targets propostos no dossiê:

- `headline_classification_provenance_file`: Track a static JSON manifest with hashes for source corpus, producer, exact prompt, archived RDS files, and validation file; unknown historical fields must be null with reasons.
- `headline_classification_provenance_validation`: Fail on hash, row-count, label-set, or stored-model-string drift without making an API call.
- `headline_validation_design_file`: Record sampling frame, strata, allocation, seed, and inclusion probabilities; for the existing sample, mark probabilities unavailable unless documentary evidence is found.
- `chatgpt_validation_confusion_matrix`: Produce the complete predicted-by-manual 9-by-9 matrix and cell supports from validation_file.
- `chatgpt_validation_class_metrics`: Compute precision, recall, F1, numerators, denominators, and uncertainty intervals from the confusion matrix.
- `chatgpt_validation_sample_agreement`: Retain the existing 88 percent as explicitly unweighted validation-sample agreement.
- `chatgpt_validation_corpus_weighted_accuracy`: Compute a design-weighted corpus estimate only if justified inclusion probabilities are present; otherwise return unavailable and a reason.
- `chatgpt_validation_temporal_metrics`: After an authorized preregistered category-by-period manual validation sample, report cell sizes, interval estimates, and the predeclared temporal test; emit insufficient_support when cells are inadequate.

Limite do desenho: a matriz de confusão e precisão/recall da amostra não se tornam representativas do corpus por entrarem no grafo. Probabilidades ausentes ficam indisponíveis; não inferir retrospectivamente amostragem aleatória. Intervalos com interpretação populacional exigem desenho documentado. O target temporal depende de nova validação humana e de células suficientes, com decisão separada do autor. Não incluir nova classificação por API nesta autorização.

Funções propostas (ainda inexistentes): `audit_headline_corpus(scrape_cache, classification_cache, classified_corpus)` gera o bundle de contagens, datas, ausências, duplicatas, diferenças de títulos e junções; `validate_classification_provenance(manifest, archives, producer)` confere os arquivos sem API; `build_validation_confusion_matrix(validation_data, labels)` produz a matriz; `summarise_validation_class_metrics(confusion_matrix, design)` e `summarise_validation_sample_agreement(validation_data)` mantêm denominadores explícitos. O target `headline_corpus_audit` deve consumir três file-targets novos para `data/raw/network_caches/folha_scrape_cache.rds`, `data/raw/network_caches/df_classifcation.rds` e `data/folha_classificado.rds`, e alimentar o mesmo bundle de proveniência. A forma definitiva dos intervalos deve respeitar o desenho documentado; não atribuir cobertura populacional à amostra de conveniência.

Execução a autorizar: implementar funções puras e targets de auditoria; executar somente esses targets e dependências documentadas, sem reconstruir coleta/API ou estimadores. Validar contagens/margens/joins, reproduzir a concordância amostral existente, exigir revisão R independente com `review-r`, depois integrar os outputs autorizados ao Rmd e renderizar. Logs históricos e omissões do arquivo-fonte podem continuar irrecuperáveis.

## 3. Quadro de anos tratados e omitidos: item 15

Preservar regras de tratamento e a amostra atual. Targets propostos:

- `china_top_m2_goods_status_current_min5_audit_bundle`
- `china_top_m2_goods_status_current_min5_country_year_audit`
- `china_top_m2_goods_status_current_min5_treated_country_table`
- `china_top_m2_goods_status_current_min5_audit_validation`

Entradas existentes: `china_top_m2_goods_panel`, `china_top_m2_goods_status_current_panel_bundle`, `china_top_m2_goods_status_current_period_summary`, `china_top_m2_goods_status_current_unit_summary`.

Unidade da auditoria: país–ano, com presença observada, condição China-top, entrada/saída/duração do período, qualificação de cinco anos, retenção no risk set, indicador tratado e motivo exclusivo de omissão. A tabela para o autor mostra intervalos de entrada/saída, períodos curtos excluídos, anos tratados retidos e anos omitidos, com contagens reconciliadas.

Validações requeridas:

- unique iso3c-year keys and exhaustive exclusive row_status
- retained keys exactly match the risk_set_restricted panel for the 35 treated countries
- retained treatment indicator equals one iff the retained row is in a qualifying current China-top period
- period boundaries durations and qualification match period_summary
- treated and untreated counts match unit_summary by country
- display has exactly the 35 current treated ISO3c values
- compacted year strings round-trip to actual observed years without filling gaps
- omitted_other_nonretained count equals zero

Funções propostas (ainda inexistentes): `build_china_top_treatment_audit(goods_panel, panel_bundle, period_summary, unit_summary, min_duration_years = 5L, min_entry_year = 2000L)` reutiliza `build_status_current_period_data()`; `compact_observed_year_intervals(years)` compacta somente anos efetivamente observados; `validate_china_top_treatment_audit(audit, panel_bundle, period_summary, unit_summary)` verifica as igualdades listadas. O produtor da tabela deve ler somente o ledger derivado no grafo, sem recodificação paralela de tratamento.

Execução a autorizar: acrescentar os quatro targets e suas funções; executar apenas essa derivação sobre os objetos existentes; revisão independente dos scripts R e das reconciliações; então substituir a Tabela 23 por apresentação legível e renderizar. Não reestimar IFE nem alterar a regra de China-top, entradas, saídas ou controles. A tabela ampliada ainda não foi produzida.

## 4. Item 25: entendimento entregue; decisão do autor

A nota explica a restrição e compara somente resultados já arquivados, sem reestimação. Manter a especificação atual, adicionar uma sensibilidade ou mudar a principal são decisões distintas. Os alvos e fórmulas de uma eventual sensibilidade estão em `domain_note.md`, seções5–6, e `domain_note.json`. Nenhuma dessas alternativas foi implementada ou autorizada por esta revisão.
