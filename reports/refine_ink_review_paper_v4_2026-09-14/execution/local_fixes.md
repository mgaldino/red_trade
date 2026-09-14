# Adjudicação delimitada: itens 15, 29, 30, 33 e 34

## Escopo e identidade

Esta é a adjudicação própria do especialista `local_fixes`, limitada aos itens 15, 29, 30, 33 e 34 da seleção em `items_to_address.md`. O artefato revisado é o `paper_v4.Rmd` atual, com conferência no `output/paper_v4.pdf` e nas cópias congeladas. Os comentários não selecionados permanecem fora do escopo e não receberam proposta neste record.

- `paper_v4.Rmd`: SHA-256 `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`.
- `output/paper_v4.pdf`: SHA-256 `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`.
- As cópias em `execution/baseline/` têm os mesmos hashes do Rmd e do PDF ativos.
- `feedback-the-foreign-policy-impact-of-trade-based-status-ga-2026-09-14.md`: SHA-256 `eb7dc9488e3b6726cee0ddf232250be18f09291797e2a85470b67637af58b88a`.
- `items_to_address.md`: SHA-256 `d0220df748585215fc3ce14786e555546134d1e25534470ee153b1872437ea25`.
- Os pré-requisitos `execution/cross_country.json` (`item15_target_design`) e `execution/sdid.json` (`item29_caption_prerequisites`) foram lidos antes da adjudicação.

## Disposição executiva

Há quatro defeitos confirmados e um defeito parcial. O item 15 é uma lacuna real de auditabilidade, mas sua correção exige os alvos novos já especificados no pré-requisito; nesta rodada entrego o esquema revisável, o contrato de validação e a integração proposta, sem criar linhas sintéticas, alterar o grafo ou executar alvos. O item 29 é parcial porque a falha está na terminologia da caption; a inspeção não encontrou defeito no estimador ou na anotação visual da seta.

Veredicto técnico: `READY_FOR_IMPLEMENTATION`. Esse veredicto encaminha os defeitos e propostas seguras para a fase correspondente; não autoriza a implementação dos novos alvos, a execução do pipeline ou a edição do manuscrito nesta rodada.

## Classes de verificação

### Inspeção estática

Foram lidos os trechos citados do Rmd ativo e da baseline, a extração textual do PDF congelado, o produtor status-current em `scripts/functions.R`, as declarações relevantes de `_targets.R`, as fontes CSV da comparação BSV/UNGA-DM, e os dois pré-requisitos da execução. A Figura 2 também foi inspecionada visualmente: as séries são trajetórias não deslocadas e a seta é um elemento separado do contraste bruto entre as linhas.

### Verificação computacional

Foi feita uma checagem exclusivamente em R, com `targets::tar_read(synth_data)` para leitura do objeto existente e leitura dos CSVs existentes. A checagem calcula apenas média, mediana, razões aritméticas e identidades entre números já armazenados; não calcula ATT novo, não estima modelos, não executa placebos e não executa `targets`.

O resultado completo está em `local_fixes_r_checks.txt`: os 12 anos pré-2009 têm média BSV `0.646777890583333` e mediana `0.620922368500000`; o ATT BSV armazenado implica `42.173891772497932%` sobre a média e `43.930033997971528%` sobre a mediana. A tabela existente confirma `0.646777890583333` para BSV, `0.836545155415565` para UNGA-DM, e reproduz os percentuais `42.173891772497932` e `39.514054175898416`.

### Nova análise

Nenhuma nova análise substantiva foi feita. Não houve reestimação, execução de alvos, renderização, classificação por API, alteração de dados, alteração de código compartilhado, alteração do manuscrito, commit, sinal ou comunicação externa. O item 15 contém apenas uma especificação de transformação que deverá nascer no grafo `targets` quando houver autorização para implementação e execução.

## Resumo dos findings

| Item | Status | Dimensão | Avaliação da correção |
|---:|---|---|---|
| 15 | `CONFIRMED` | Reprodutibilidade / exposição | `needs_design`: desenho target-first concreto entregue; implementação e execução pendentes |
| 29 | `PARTIAL` | Exposição / fidelidade do estimando | `safe`: corrigir somente a terminologia da caption |
| 30 | `CONFIRMED` | Escopo / estimando | `safe`: substituir uma frase |
| 33 | `CONFIRMED` | Consistência numérica | `safe`: trocar a referência a mediana por média pré-tratamento |
| 34 | `CONFIRMED` | Atribuição numérica | `safe`: identificar cada média pela fonte do outcome |

## Evidência e decisão por item

### Item 15 — Tabela 23 não expõe os anos retidos

Localizações: feedback, linhas 289–306; seleção, linha 25; `paper_v4.Rmd:2121–2160`; PDF, p. 63; `_targets.R:411–422`; `scripts/functions.R:4119–4264`, `4268–4364`, `4407–4521`; `execution/cross_country.json:item15_target_design`.

Status: `CONFIRMED`.

Defeito verificado: o chunk atual seleciona somente `country_name`, `iso3c`, primeiro ano tratado, `treated_years`, `untreated_years` e limites do painel (`paper_v4.Rmd:2128–2142`). Os produtores atuais calculam e retêm, em objetos diferentes, períodos elegíveis, períodos qualificantes, entradas, saídas e contagens agregadas. A regra `strict_never_control` conserva anos pré-entrada não-China-top e períodos qualificantes, mas remove anos pós-entrada fora do status e episódios curtos; esses anos omitidos não podem ser recuperados da primeira entrada e das contagens agregadas. Portanto, a tabela atual não torna auditáveis os anos ou motivos de omissão.

Evidência de escopo: o defeito é de transparência e reprodutibilidade da tabela, não uma demonstração de que o ATT pooled ou o suporte de event-time esteja incorreto. A transformação adicional deve usar o painel de bens, o bundle status-current, o resumo de períodos e o resumo por unidade, sem mudar a regra de tratamento.

Avaliação da correção: `needs_design`. O desenho abaixo é concreto e revisável, mas ainda depende de implementação autorizada no grafo e de execução/validação posterior.

#### Esquema target-first proposto

| Camada | Especificação |
|---|---|
| Bundle | `china_top_m2_goods_status_current_min5_audit_bundle` |
| Auditoria país-ano | `china_top_m2_goods_status_current_min5_country_year_audit` |
| Tabela de exibição | `china_top_m2_goods_status_current_min5_treated_country_table` |
| Validação | `china_top_m2_goods_status_current_min5_audit_validation` |
| Inputs | `china_top_m2_goods_panel`; `china_top_m2_goods_status_current_panel_bundle`; `china_top_m2_goods_status_current_period_summary`; `china_top_m2_goods_status_current_unit_summary` |
| Unidade da auditoria | uma linha por `iso3c`–`year`, sob `min_duration_years = 5` e `specification = risk_set_restricted` |

Campos da saída país-ano: `specification`, `min_duration_years`, `iso3c`, `country_name`, `year`, `observed_china_top`, `status_current_period_id`, `period_entry_year`, `period_exit_year`, `period_duration_observed_years`, `period_calendar_span_years`, `period_qualifies_min5`, `retained_in_risk_set`, `treatment_indicator_retained` e `row_status`.

Os valores permitidos de `row_status` devem ser exclusivos e exaustivos: `retained_pre_entry_control`, `retained_qualifying_treated`, `omitted_missing_required_input`, `omitted_pre_entry_nonqualifying_china_top`, `omitted_post_entry_short_china_top_period`, `omitted_between_qualifying_periods_off_status`, `omitted_post_final_qualifying_exit_off_status` e `omitted_other_nonretained`.

Campos da tabela revisável por país: `Country`, `ISO3c`, `Qualifying entries and exits`, `Excluded short periods`, `Retained treated years`, `Omitted off-status years`, `Treated N`, `Untreated N` e `Omitted N`. A compactação de anos só pode unir anos consecutivos; a expansão deve reproduzir exatamente os anos observados, preservando lacunas.

Contrato de validação antes da integração:

1. As chaves `iso3c`–`year` são únicas e cada linha recebe exatamente um `row_status` permitido.
2. As chaves retidas coincidem exatamente com o painel `risk_set_restricted` para os 35 países tratados.
3. `treatment_indicator_retained` é igual a 1 se, e somente se, a linha retida pertence a um período corrente China-top qualificado.
4. Entradas, saídas, duração observada, extensão calendárica e qualificação coincidem com `period_summary`.
5. As contagens tratadas e não tratadas coincidem, por país, com `unit_summary`.
6. A tabela de exibição contém exatamente os 35 valores ISO3c tratados na especificação vigente.
7. As strings compactadas de anos fazem round-trip para os anos observados sem preencher lacunas.
8. A contagem de `omitted_other_nonretained` é zero.

Integração proposta: inserir esses quatro alvos depois dos objetos status-current existentes; fazer o chunk `table-treated-appendix` consumir exclusivamente `china_top_m2_goods_status_current_min5_treated_country_table`; substituir o parágrafo e a caption somente depois de `china_top_m2_goods_status_current_min5_audit_validation` passar. Não produzir uma tabela paper-facing por script auxiliar ou por cálculo fora do grafo.

### Item 29 — Figura 2 mistura gap bruto e ATT

Localizações: feedback, linhas 482–491; seleção, linha 32; `paper_v4.Rmd:340–345`; PDF, p. 16; `execution/sdid.json:item29_caption_prerequisites`; imagem `quality_reports/china_demand_shock_rank_threshold/figure_brazil_sdid_predetermined_core_fit.png`.

Status: `PARTIAL`.

Defeito verificado: a caption chama de “post-treatment gap” o “average post-2009 reduced-form estimate” sem dizer que o ATT é o contraste pós-tratamento ajustado pela diferença prévia ponderada. Como o caminho do doador é não deslocado, o leitor pode interpretar a distância vertical bruta entre as linhas como `-0.273`, embora o ATT seja o contraste líquido.

Evidência que limita o finding: a própria revisão registra que a seta parece representar corretamente o contraste ajustado; a inspeção da Figura 2 confirma uma seta separada das trajetórias. O código do Rmd inclui a figura já produzida e o pré-requisito identifica a seta como fornecida pelo `synthdid_plot`, sem evidência de erro no estimador ou na anotação visual.

Avaliação da correção: `safe`, caption-only. Manter a especificação sem covariáveis, a janela 1997–2015, o ATT, o SE placebo de 20.000 repetições e todos os números existentes.

### Item 30 — frase de identificação inverte a hierarquia

Localizações: feedback, linhas 495–506; seleção, linha 33; `paper_v4.Rmd:298–304`; contexto correto em `paper_v4.Rmd:314`, `320–324` e `328–330`; PDF, p. 10.

Status: `CONFIRMED`.

Defeito verificado: “a country's rise in China's trade hierarchy” descreve o país como subindo na hierarquia comercial da China. O estimando implementado é a ascensão da China à primeira posição entre os destinos de exportação do país. As passagens posteriores usam o tratamento pretendido, mas isso não corrige a frase inicial que anuncia outro estimando.

Avaliação da correção: `safe`, uma substituição local sem alteração do desenho.

### Item 33 — média versus mediana

Localizações: feedback, linhas 534–542; seleção, linha 36; abstract em `paper_v4.Rmd:20`; cálculo em `paper_v4.Rmd:83–92` e `149`; Tabela 24 em `paper_v4.Rmd:2239–2268`; PDF, p. 1 e p. 65; `data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/main_summary.csv:1–2`; `data/processed/diagnostics/ungadm_outcome_robustness/estimation/sdid_comparison_table.csv:1–3`.

Status: `CONFIRMED`.

Defeito verificado: o abstract diz “42% of the median distance before 2009”. O cálculo ativo define `mean_br` como a média de `abs_distance_china` para o Brasil em 1997–2008, e o resultado armazenado é `0.646777890583333`. O ATT `-0.272771407583060` produz `42.173891772498%` sobre essa média, arredondado no corpo para `42.2%`. A mediana dos mesmos 12 anos é `0.620922368500000`, que produziria `43.930033997972%`, e não 42%.

Avaliação da correção: `safe`, desde que a referência do abstract seja ajustada para a média pré-tratamento. O patch abaixo mantém o arredondamento de 42% do abstract; `42.2%` continua sendo o valor detalhado no corpo e nas tabelas.

### Item 34 — atribuição das médias pré-tratamento

Localizações: feedback, linhas 546–554; seleção, linha 37; `paper_v4.Rmd:2239–2240` e `2242–2283`; Tabela 24 no PDF, p. 65; `data/processed/diagnostics/ungadm_outcome_robustness/estimation/sdid_comparison_table.csv:1–3`; `data/processed/diagnostics/ungadm_outcome_robustness/estimation/sdid_dm_main_summary.csv:1–2`.

Status: `CONFIRMED`.

Defeito verificado: a frase diz que as médias `0.647` e `0.837` aparecem “in the original estimation”, embora a tabela de comparação associe a primeira ao outcome BSV e a segunda ao outcome UNGA-DM. A checagem R reproduz `0.646777890583333` para BSV e `0.836545155415565` para UNGA-DM; também reproduz os percentuais relativos `42.173891772498%` e `39.514054175898%`. O problema é de atribuição textual, não dos cálculos.

Avaliação da correção: `safe`, substituição local identificando explicitamente cada fonte do outcome.

## Replacements exatos propostos

Os replacements abaixo são propostas para o integrador. Nenhum foi aplicado nesta rodada.

### Item 15 — somente depois dos alvos e da validação

**Original, `paper_v4.Rmd:2123`:**

> Table 23 describes the 35 treated countries in the main goods-only restricted-risk-set specification. For each country, the table reports the first qualifying China-top goods-export year and the number of treated and untreated country-years retained in the estimation panel.

**Proposta:**

> Table 23 provides a country-level audit of the 35 treated countries in the main goods-only restricted-risk-set specification. It reports every qualifying entry and exit, the observed years in excluded short China-top periods, the treated years retained by the estimator, and the post-entry off-status years omitted by the restricted risk set. Year ranges are compressed only across consecutive observed calendar years; gaps remain explicit.

**Caption atual, `paper_v4.Rmd:2149`:**

> Treated countries in the main goods-only restricted-risk-set cross-country specification.

**Caption proposta:**

> Country-level audit of retained and omitted years in the main goods-only status-current restricted-risk-set specification.

### Item 29 — caption-only

**Original clause, `paper_v4.Rmd:340`:**

> the post-treatment gap is the average post-2009 reduced-form estimate.

**Proposta:**

> the arrow shows the level-adjusted SDiD ATT, equal to the average post-2009 contrast net of the SDiD-weighted pre-treatment contrast; it is not the raw vertical distance between the trajectories.

### Item 30 — uma frase

**Original sentence, `paper_v4.Rmd:300`:**

> I want to estimate the causal effect of a country's rise in China's trade hierarchy on its foreign policy.

**Proposta:**

> I want to estimate the causal effect of China rising to first place among a country's export destinations on its foreign policy.

### Item 33 — abstract

**Original sentence, `paper_v4.Rmd:20`:**

> Relative to the counterfactual, the estimated reduction in bilateral voting distance is equivalent to 42% of the median distance before 2009.

**Proposta:**

> Relative to the counterfactual, the estimated reduction in bilateral voting distance is equivalent to 42% of the pre-treatment mean distance before 2009.

### Item 34 — identificação das fontes

**Original trecho, `paper_v4.Rmd:2239–2240`:**

> It is noteworthy that the pre-treatment averages are different (`r sprintf("%.3f", ungadm_bsv_row$brazil_pre_mean)` against `r sprintf("%.3f", ungadm_dm_row$brazil_pre_mean)`) in the original estimation.

**Proposta:**

> It is noteworthy that the pre-treatment means differ (`r sprintf("%.3f", ungadm_bsv_row$brazil_pre_mean)` under BSV versus `r sprintf("%.3f", ungadm_dm_row$brazil_pre_mean)` under UNGA-DM).

## Limitações e encaminhamento

- Nenhum target foi executado e nenhum modelo foi reestimado.
- Não foi criada nenhuma linha factual nova para a Tabela 23; seu conteúdo permanece o output atual até que os alvos propostos existam e passem o contrato.
- A verificação R confirma as identidades nos objetos/CSV existentes, mas não é uma validação de frescor do store nem substitui uma futura execução autorizada.
- A inspeção visual da Figura 2 foi feita no PNG produtor; nenhuma nova renderização do PDF foi feita.
- O record não adjudica os comentários 2, 4, 6, 7, 8, 11, 18, 20, 21, 22, 25, 27, 31, 32, 35, 36, 37 ou 38, nem qualquer comentário geral.
