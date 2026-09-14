# Ajustes após confirmação do autor — 2026-09-14

Fonte: instrução do autor nesta tarefa. Escopo: itens 8, 31, 35 e 36.

- Item 8: o autor confirmou amostragem aleatória estratificada proporcional ao tamanho dos estratos no corpus, com mínimo de cinco por categoria, sem semente preservada. O manuscrito documenta esse desenho e apresenta os 88% existentes como acurácia observada na validação. Retiradas as afirmações de desenho desconhecido, amostra enriquecida por categoria e impossibilidade de estimar acurácia do corpus. Nenhuma nova ponderação ou afirmação de ausência exata de viés foi introduzida. As taxas condicionadas ao rótulo previsto continuam distinguidas de recall.
- Item 31: adicionada tarefa em PENDING.md para retirar todas as redundâncias exatas das especificações com covariáveis, incluindo distância geográfica absorvida e redundância do diferencial de poder. A tarefa exige verificar o posto do conjunto remanescente e reestimar as comparações afetadas pelos produtores/targets. Nenhum estimador ou resultado mudou nesta rodada.
- Itens 35/36: substituída a frase exatamente pela redação fornecida pelo autor, mantendo suas citações.
- O item 4 não foi alterado nesta rodada: a resposta anterior registrou a inferência não demonstrada sobre cobertura anual; a presente instrução trata dos itens acima.

Este registro e a atualização de pending_authorizations.md prevalecem sobre as descrições anteriores do desenho amostral nos pareceres congelados da revisão. A origem da nova informação é a declaração do autor, não a recuperação de um script histórico.

## Verificação e entrega

Revisão independente de fonte/diff: PASS delimitado, incluindo o encurtamento final da frase de remissão à Tabela 22. YAML/abstract e todas as expressões R inline preservados. Fontes/configuração protegidas e arquivo de validação mantêm os hashes anteriores. Nenhum modelo, classificação por API ou pipeline foi executado.

PDF recompilado por render_isolated.R, com leitura dos resultados existentes, e copiado para output/paper_v4.pdf. Inspecionadas visualmente as páginas 2, 64 e 65, incluindo o desenho amostral e a tabela com 88,0%. A primeira tentativa foi bloqueada no carregamento de processx pelo sandbox; a renderização autorizada fora do sandbox concluiu. Advertências finais: depreciação de xfun::attr() e ajuste LaTeX de posicionamento de float (!h para !ht). Hashes e verificações em author_followup_20260914_manifest.json.
