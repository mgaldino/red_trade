# Adjudicação SDiD: itens 6, 18, 20, 31 e 32

## Identidade da fonte

- Manuscrito-fonte: `paper_v4.Rmd`, SHA-256 `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`.
- Artefato revisado: `output/paper_v4.pdf`, SHA-256 `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`.
- As duas versões ativas são byte a byte iguais às cópias congeladas em `execution/baseline/`. As cinco passagens citadas pelo Refine aparecem no Rmd e no PDF. O artefato está íntegro.
- Este recorte é uma adjudicação metodológica local. Não exige contrato argumental e não reutiliza contratos históricos.

## Disposição executiva

| Item | Status | Escopo confirmado | Avaliação da correção |
|---:|---|---|---|
| 6 | **CONFIRMED** | Faltam definições das exposições, janelas-base, ativação em 2008–2009 e termos de ordem inferior da Tabela 5. | `safe`; texto e nota, sem reestimar. |
| 18 | **CONFIRMED** | O parágrafo confunde SE placebo, ranks por reatribuição e aproximação normal. | `safe`; substituir o parágrafo inferencial. |
| 20 | **CONFIRMED** | A exposição não define pesos positivos de tratados e períodos pós-tratamento. | `safe`; definir vetores completos de pesos. |
| 31 | **PARTIAL** | Distância geográfica é absorvida/inercial; a colinearidade alegada para o diferencial de poder não vale para a variável em módulo. | `safe`; esclarecer a implementação, mantendo a principal sem covariáveis. |
| 32 | **CONFIRMED** | O texto inverte o alvo dos pesos temporais e mistura a informação usada por pesos de unidade e de tempo. | `safe`; três correções locais coordenadas com o item 20. |

Veredito do recorte: **READY_FOR_IMPLEMENTATION**. São quatro defeitos confirmados e um parcial, nenhum item material não resolvido. Todas as correções são expositivas. O ATT principal, sua inferência e a especificação preferida sem covariáveis ficam inalterados.

## Item 6 — Tabela 5

**Status: CONFIRMED.** A Tabela 5 e sua nota informam que as medidas usam exportações externas de bens e que as interações de 2008–2009 incluem o primeiro ano tratado. Isso não permite reconstruir o significado das quatro linhas.

O produtor ativo mostra a implementação exata:

- As exposições são médias por país de 2004–2008. A parcela primária é Agricultura mais Mining and Energy sobre exportações externas de bens. A decomposição usa separadamente essas duas parcelas. A exposição prévia à China é a parcela das exportações externas de bens destinada à China.
- “x 2008–2009” multiplica cada exposição fixa de 2004–2008 por um indicador igual a um em 2008 e 2009 e zero nos demais anos; o produto é padronizado no painel de estimação.
- A exposição de preços pondera mudanças logarítmicas dos índices anuais nominais de Agricultura, Energia e Metals and Minerals da World Bank Pink Sheet, relativas a 2007, pelas parcelas médias de exportação de 2004–2008. O índice é ativado em 2008–2009 e padronizado.
- Apenas essas interações variáveis no tempo entram nas quatro linhas diagnósticas. Os níveis de exposição são invariantes no tempo e absorvidos pelos efeitos de unidade. O indicador comum de 2008–2009 é absorvido pelos efeitos de tempo. Por isso o código não inclui termos de ordem inferior separados.

Evidência: `paper_v4.Rmd:754,805-899`; `scripts/diagnostics/audit_brazil_sdid_commodity_no_covariates.R:97-151`; produtor dos insumos em `scripts/diagnostics/audit_brazil_sdid_predetermined_commodity_controls.R:190-257,293-326`; resultado em `data/processed/diagnostics/brazil_sdid_commodity_no_covariates/table_5_sdid_specification_results.csv`. As seis linhas são estimativas completas (`smoke_test = FALSE`).

**Substituição mínima na nota da Tabela 5**

Texto atual:

> Primary-goods measures use external goods exports only. The 2008-2009 interactions include the first treated year and are mechanism robustness checks, not preferred total-effect specifications.

Texto proposto:

> The exposure baselines are country means over 2004--2008: primary goods as a share of external goods exports, its Agriculture and Mining and Energy components, and China as a share of external goods exports. `x 2008--2009` means that the fixed 2004--2008 exposure is multiplied by an indicator for 2008 and 2009 and then standardized over the estimation panel. The price diagnostic instead weights World Bank Pink Sheet log-price changes relative to 2007 by the country's 2004--2008 Agriculture, Energy, and Metals and Minerals export shares, activates that index in 2008--2009, and standardizes it. Only these time-varying interactions enter the four diagnostic specifications: exposure levels are time-invariant and absorbed by unit effects, while the common 2008--2009 indicator is absorbed by time effects. Because 2009 is the first treated year, these are mechanism robustness checks rather than preferred total-effect specifications.

## Item 18 — três objetos inferenciais distintos

**Status: CONFIRMED.** `paper_v4.Rmd:308` atribui o erro-padrão à “normal approximation native to the SDiD estimator”. O resultado ativo usa outra sequência:

1. O **SE placebo** é o desvio-padrão de população finita de 20.000 reestimações placebo, seed `20260520`, para a especificação preferida.
2. O **p convencional e o IC95** usam esse SE em uma aproximação normal bilateral: a aproximação normal não produz o SE.
3. Os **ranks placebo-in-space** vêm de 96 reatribuições determinísticas, uma para o Brasil e uma para cada doador. Não há sorteio. O rank direcional é 3/96 e o rank bilateral em módulo é 7/96.

Evidência: `scripts/functions.R:1072-1151`; `scripts/diagnostics/sdid_placebo_helpers.R:230-297,299-380`; `data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/main_summary.csv`; `rank_inference.csv`. O texto de resultados em `paper_v4.Rmd:338` já nomeia corretamente as três quantidades; o defeito é o parágrafo de desenho.

**Substituição mínima de `paper_v4.Rmd:308-310`**

> I report three distinct inferential summaries for the preferred Brazil estimate. First, the placebo-based standard error is the finite-population standard deviation of 20,000 seeded synthdid placebo resamples. Second, I combine that placebo standard error with a two-sided normal approximation to report the conventional p-value and 95 percent confidence interval. Third, I report deterministic placebo-in-space ranks obtained by reassigning treatment once to Brazil and to every donor: the directional rank counts estimates at least as negative as Brazil's, while the bilateral rank compares absolute magnitudes. The directional rank follows the theory's prediction of convergence; the bilateral rank is a conservative sensitivity assessment.

## Item 20 — definição completa dos pesos

**Status: CONFIRMED.** A equação em `paper_v4.Rmd:1439-1446` soma sobre todas as unidades e períodos, mas o texto define somente pesos dos doadores e pesos pré-tratamento. A leitura literal deixa sem definição os pesos das células tratadas no pós-tratamento.

A implementação instalada de `synthdid` 0.0.9 usa:

\[
\widehat w_i=
\begin{cases}
\widehat\omega_i,&i\le N_0,\\
1/N_1,&i>N_0,
\end{cases}
\qquad
\widehat\lambda_t=
\begin{cases}
\widehat\lambda_t^{\mathrm{pre}},&t\le T_0,\\
1/T_1,&t>T_0.
\end{cases}
\]

Os pesos otimizados dos controles e dos períodos pré-tratamento são não negativos e somam um nos respectivos blocos. Tratados e períodos pós-tratamento recebem pesos uniformes estritamente positivos. O objeto ativo confirma que a implementação está correta; o defeito está apenas na exposição.

**Substituições mínimas**

Após a equação de SCM, substituir a definição atual por:

> Here $\hat{w}^{\text{SCM}}_i$ denotes the full unit-weight vector: an optimized nonnegative weight for each control unit and the fixed positive weight $1/N_1$ for each treated unit.

Antes da equação de SDiD, substituir a frase de transição por:

> SDiD combines unit weights (like SCM) with unit fixed effects (like DiD) and time weights. Let $N_0$ and $N_1$ denote the numbers of control and treated units and $T_0$ and $T_1$ the numbers of pre- and post-treatment periods. In the full unit-weight vector, controls receive the optimized nonnegative donor weights, which sum to one, and each treated unit receives the fixed positive weight $1/N_1$. In the full time-weight vector, pre-treatment periods receive optimized nonnegative weights, which sum to one, and each post-treatment period receives the fixed positive weight $1/T_1$. Thus treated-post cells enter the objective with positive weight. The basic SDiD estimating equation is:

## Item 31 — distância inerte; diferencial de poder em módulo

**Status: PARTIAL.** A crítica à distância geográfica procede. `distance_us` é invariante no tempo, permanece no array de 13 covariáveis, e seu coeficiente armazenado é `7.959e-19`. A Tabela 3 marca a variável como incluída sem explicar que ela não fornece ajuste separado sob a parametrização com efeitos de unidade.

A crítica ao diferencial de poder parte da variável errada. `scripts/functions.R:208-210` define `us_power_gap = abs(us_power - gpi)`. O módulo impede a identidade linear exata entre o GPI do país, o GPI anual dos Estados Unidos e os efeitos de tempo. No ajuste armazenado, seu coeficiente é `-0.008069`, não zero. Não há base para aceitar a alegação de colinearidade assinada.

O ajuste preferido tem array de covariáveis `96 x 19 x 0`; portanto, nenhuma das duas questões muda o ATT principal sem covariáveis.

**Substituição mínima de `paper_v4.Rmd:306`**

> The preferred specification uses no covariates because time-varying post-2009 values may induce post-treatment bias. The current-covariate comparison passes the country-year variables listed in Table 3 to synthdid. Geographic distance to the United States is time-invariant: it remains in that comparison array but is absorbed by the unit-effect parametrization and supplies no separate adjustment. The power gap is the absolute annual difference between the U.S. and country Global Power Index values, rather than a signed difference, so it is not mechanically collinear with country power and time effects. This covariate-adjusted model is retained only as a sensitivity comparison; the preferred specification remains covariate-free. Commodity composition and price interactions are separate robustness or mechanism diagnostics, especially because the 2008--2009 interaction includes the first treated year.

## Item 32 — alvo dos pesos temporais

**Status: CONFIRMED.** `paper_v4.Rmd:1424` diz que SDiD escolhe períodos comparáveis ao pré-tratamento. A implementação faz outra comparação: atribui pesos aos períodos pré-tratamento para que os resultados ponderados dos controles nesses períodos aproximem a média dos resultados dos controles no pós-tratamento. A construção de pesos de unidade usa os históricos pré-tratamento; a construção de pesos de tempo usa resultados dos controles antes e depois do início.

Evidência: funções `synthdid_estimate`, `collapsed.form`, `sc.weight.fw` e `sc.weight.fw.covariates` do `synthdid` 0.0.9. `collapsed.form` resume o bloco pós-tratamento pela média pós de cada controle e usa esse vetor como alvo da otimização de `lambda`. A Tabela 10 reporta corretamente apenas `lambda` sobre 1997–2008.

**Substituições mínimas**

Em `paper_v4.Rmd:223`:

> SDiD estimates Brazil's average post-2009 gap relative to a weighted synthetic counterfactual. Unit weights are learned from pre-treatment outcome histories, whereas the optimized pre-treatment time weights use control outcomes before onset and the controls' average outcome after onset [@arkhangelsky_etal2021].

Em `paper_v4.Rmd:302`:

> It also weights pre-treatment periods so that the controls' weighted pre-treatment outcomes approximate their average post-treatment outcomes.

Em `paper_v4.Rmd:1424`:

> SDiD assigns larger unit weights to control units whose pre-treatment outcome paths help reproduce the treated unit. Separately, it assigns optimized weights to pre-treatment periods so that their weighted control-unit outcomes approximate the controls' average post-treatment outcomes. Unit weights therefore use pre-treatment outcome histories, whereas time weights use control outcomes from both sides of treatment onset. Classic DiD corresponds to uniform weighting in this comparison.

## Pré-requisitos metodológicos para a futura correção do item 29

Este record não adjudica o item 29, mas a legenda da Figura 2 deve respeitar a identidade do estimador. A figura atual é produzida do objeto `synth_fit_no_time_varying_covariates` por `plot.synthdid_estimate`: as duas linhas são trajetórias não deslocadas, e a seta sobreposta representa o contraste difference-in-differences do estimador.

Com um tratado e sem covariáveis,

\[
\widehat\tau=
\left(\overline Y_{BRA,post}-\sum_i\widehat\omega_i\overline Y_{i,post}\right)
-
\left(\sum_t\widehat\lambda_tY_{BRA,t}
-\sum_i\widehat\omega_i\sum_t\widehat\lambda_tY_{it}\right).
\]

A legenda precisa chamar a separação vertical entre as linhas de diferença bruta e descrever a seta como o ATT ajustado pelo contraste pré-tratamento ponderado por `lambda`. Ela não deve chamar a distância vertical pós-tratamento bruta de ATT. Após a edição, basta confirmar a procedência do mesmo fit, comparar ATT/SE com `main_summary.csv`, renderizar e inspecionar a página. Uma mudança apenas de legenda não exige reestimação.

## Verificações e limites

Foram verificados hashes, igualdade com o baseline, texto-fonte, texto extraído do PDF, produtores, CSVs existentes, objetos armazenados do `targets` e a implementação local do `synthdid`. Nenhum modelo, placebo, bootstrap, `tar_make()` ou render foi executado.

Na implementação posterior, os números devem permanecer `-0.273`, `0.131`, `[-0.529, -0.017]`, `3/96` e `7/96`, e os valores da Tabela 5 devem ficar inalterados. Depois das substituições, procurar descrições antigas do SE e dos pesos temporais, renderizar e inspecionar as páginas 11, 23 e 46–47.

O produtor da Tabela 5 continua listado como P1 fora do grafo em `TARGETS_MIGRATION.md:91`. As correções aqui propostas usam apenas outputs congelados existentes. Qualquer cálculo novo para o paper precisa ser especificado primeiro como target/file target.
