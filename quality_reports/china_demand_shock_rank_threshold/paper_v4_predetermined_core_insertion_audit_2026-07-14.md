# Auditoria de inserção no `paper_v4`: Brazil SDiD sem covariáveis time-varying

## Decisão

A especificação principal passa a ser `synth_fit_no_time_varying_covariates`, correspondente ao `predetermined_core` auditado. Os níveis predeterminados/fixos fornecidos ao estimador têm coeficientes numericamente nulos, com máximo absoluto de aproximadamente `3,1e-17`. A especificação é, portanto, descrita no paper como sem ajuste efetivo por covariáveis. O modelo com covariáveis contemporâneas permanece somente como comparação de sensibilidade.

## Locais que exigem atualização

1. Abstract: substituir ATT e percentual do baseline brasileiro.
2. Bloco `basic-num`: ler fit e SE da especificação sem covariáveis time-varying.
3. Data and design: documentar que os arrays fixos são empiricamente inertes e que variáveis contemporâneas aparecem apenas em comparações.
4. Identification strategy: explicar por que o modelo principal evita ajuste pós-tratamento.
5. Figura principal: substituir `plot_trend`, baseado em `synth_fit`, pelo fit `predetermined_core`.
6. Resumo diagnóstico: substituir pesos, fit, balance e ranks do bundle corrente pelos outputs do fit principal.
7. Tabela de especificações: promover a antiga coluna 3 à coluna 1 e rebaixar a matriz contemporânea a comparação.
8. Timing placebos: evitar covariáveis observadas depois dos pseudo-onsets; reportar diagnósticos de ponto estimado sem covariáveis.
9. Commodity/GFC: substituir o target legado contaminado por fluxos domésticos pelo snapshot external-goods auditado.
10. Apêndice SDiD: atualizar pesos, balance, ranks, sensibilidades, figuras e comparação latino-americana.
11. Conclusão: calibrar a evidência como ATT negativo com p normal bilateral de 0,036, rank direcional de 3/96 e rank bilateral conservador de 7/96.

## Regra inferencial

- ATT principal: aproximadamente -0,272.
- SE placebo: aproximadamente 0,130, com 1.000 replicações.
- IC95% bilateral: aproximadamente [-0,527; -0,017].
- p normal bilateral: aproximadamente 0,036.
- rank direcional negativo: 3/96, p = 0,031.
- rank bilateral absoluto: 7/96, p = 0,073.

O rank direcional testa a expectativa teórica de convergência. O rank bilateral é mantido como calibração conservadora; nenhum resultado é omitido.

## Implementação concluída

O `paper_v4.Rmd` e o `paper_v4.pdf` foram atualizados em 2026-07-14. A mudança alcança o abstract, a introdução, a descrição dos dados, a estratégia de identificação, os resultados do Brasil, as tabelas de especificações e commodities, a conclusão e o apêndice de diagnósticos. Após revisão independente, o paper passou a chamar a especificação preferida de sem ajuste efetivo por covariáveis; a Tabela 3 não atribui checkmarks de covariáveis ao modelo principal.

A Tabela 2 foi redesenhada em duas colunas para corrigir a ilegibilidade da versão compacta anterior. As Tabelas 3 e 5 também foram simplificadas e ampliadas após inspeção visual. As figuras de fit global, pesos e fit latino-americano foram regeneradas para a especificação sem ajuste efetivo por covariáveis. A comparação latino-americana é apresentada apenas como sensibilidade de ponto, pois sua distribuição placebo não foi recomputada.

## Artefatos reprodutíveis

- Script: `scripts/diagnostics/prepare_paper_v4_brazil_sdid_predetermined_core_outputs.R`.
- Dados: `data/processed/diagnostics/paper_v4_brazil_sdid_predetermined_core/`.
- Figuras: `quality_reports/china_demand_shock_rank_threshold/figure_brazil_sdid_predetermined_core_*.{pdf,png}`.
- Manuscrito: `paper_v4.Rmd` e `paper_v4.pdf`.

O script lê alvos já existentes e checkpoints auditados, mas não executa `targets::tar_make()`. As sensibilidades de exclusão de doadores, janelas temporais, timing e doadores latino-americanos são reestimadas separadamente sob a mesma parametrização. A tabela de balanceamento usa exatamente as definições dos arrays fixos: médias de 2004--2008 para shares de exportação e renda per capita, distância geográfica fixa, valores institucionais de 2008 e média pré-tratamento de 1997--2008 para o outcome. Ela é apresentada como auditoria descritiva, não como evidência de ajuste efetivo.

## Validação

Os 11 checks de `validation_checks.csv` passaram. Eles confirmam ATT e SE contra o checkpoint auditado, ranks 3/96 e 7/96, coeficientes fixos numericamente nulos, ausência de placebos tratados pela definição original em 1997--2015, igualdade dos dois ranks após excluir a atribuição goods-only exposta, timing sem covariáveis, soma dos pesos e ausência de mudança no timestamp dos metadados de `targets` durante a execução.

A interpretação dos ranks como p-valores agora traz a ressalva de que as atribuições placebo precisam ser suficientemente comparáveis ao Brasil. A exclusão por exposição e o filtro de fit são apresentados como diagnósticos dessa condição, não como garantia de exchangeability nem como critérios para selecionar o p-valor principal.

O PDF foi compilado com `scripts/render_paper_v4.sh`. A inspeção visual cobriu a figura principal, as Tabelas 2 e 3, a tabela de balanceamento, a tabela de ranks, as sensibilidades de doadores e janelas e as figuras de pesos e doadores latino-americanos.

## Revisão independente

Uma primeira rodada somente leitura identificou cinco pontos: arrays fixos empiricamente inertes, rótulo incorreto da especificação com rank na tabela de commodities, ausência da condição de comparabilidade dos placebos, baixa legibilidade das Tabelas 3 e 5 e dois checks com rótulos mais fortes que seus testes. Todos foram corrigidos.

A segunda rodada independente retornou `PASS` sem findings remanescentes para especificação, coerência numérica, condição da inferência por rank, legibilidade e validações. O revisor não editou arquivos nem executou a implementação.
