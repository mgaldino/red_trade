# Adjudicação dos itens 2 e 15 — painel cross-country

## Identidade e escopo

- Artefato-fonte adjudicado: `paper_v4.Rmd`, SHA-256 `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`.
- Artefato renderizado conferido: `output/paper_v4.pdf`, SHA-256 `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`.
- Parecer: `feedback-the-foreign-policy-impact-of-trade-based-status-ga-2026-09-14.md`, SHA-256 `eb7dc9488e3b6726cee0ddf232250be18f09291797e2a85470b67637af58b88a`.
- Contrato argumentativo: não requerido nesta adjudicação delimitada; contratos históricos não foram usados.
- Verificação: leitura estática do Rmd, PDF, `_targets.R`, produtores e objetos existentes em `_targets/objects`. Nenhum target, modelo, API, script analítico ou renderização foi executado.

## Disposição executiva

| Item | Status | Diagnóstico | Encaminhamento |
|---:|---|---|---|
| 2 | `PARTIAL` | O manuscrito não revela que a auditoria de fontes cobre 14 casos de uma amostra anterior nem que a tabela exibe nove casos após um filtro. A inferência do parecer de que os outros 26 casos simplesmente desapareceram da auditoria é incorreta. | Correção textual segura para declarar universo, filtro e regras de `medium`; nenhuma nova busca é necessária para corrigir o escopo. |
| 15 | `CONFIRMED` | A Tabela 23 mostra apenas primeiro ano e contagens agregadas. Ela não identifica anos tratados, saídas, anos fora da amostra nem períodos curtos excluídos. | `needs_design`: manter a tabela atual até existir um novo output produzido por `targets`; especificação abaixo. |

Veredicto delimitado: `READY_FOR_IMPLEMENTATION`. O item 2 admite patch apenas textual. O item 15 está adjudicado, mas a solução deve nascer no grafo `targets` e permanece pendente de implementação e execução autorizadas.

## Item 2 — escopo da auditoria de fontes

### Finding normalizado

O texto apresenta a auditoria de cue público como auditoria cross-country sem informar o universo efetivamente pesquisado, o filtro da tabela e a definição de `medium`.

### Evidência de defeito

- `paper_v4.Rmd:1882-1884` descreve genericamente uma “cross-country audit” vinculada ao tratamento do painel, sem número de casos, regra amostral ou relação com os 35 tratados atuais.
- `paper_v4.Rmd:1913-1917` define a finalidade do benchmark, mas não define `medium` nem o filtro que determina as linhas exibidas.
- `scripts/diagnostics/analyze_ex_top1_salience.R:46-87` constrói a auditoria a partir de `china_top_absorbing_cs_sample_fect_treated_countries.csv`, uma amostra anterior, e não dos 35 tratados do target status-current atual.
- O objeto exibido contém 14 casos na matriz subjacente e nove na `recoverability_table`. Dos 35 tratados atuais, 13 aparecem na matriz de auditoria; Qatar é o 14º caso auditado, mas não está entre os 35 atuais. Vinte e dois tratados atuais nunca entraram nessa auditoria de fontes.
- Os anos de auditoria também não estão inteiramente sincronizados: Chile está em 2008 na auditoria e 2007 no target atual; Arábia Saudita, 2015 e 2013; Austrália foi corrigida de 2010 para 2009 no patch de 5 de setembro (`prepare_australia_appendix_bundle_patch.R:75-125`).

### Evidência que refuta parte do parecer

- `scripts/functions.R:2213-2217` aplica filtro explícito: mantém casos cujo cue da China não foi observado e mantém Austrália em qualquer caso. Com os dados atuais, a tabela resultante tem nove linhas, todas `unknown`.
- As cinco linhas suprimidas da matriz de 14 casos são Chile, Brasil, Uruguai, Arábia Saudita e Qatar, todas com cue da China recuperado (`high` ou `medium`). Portanto, nove linhas exibidas não significam nove países auditados.
- A decomposição correta dos 26 tratados atuais não exibidos é: quatro foram auditados e ocultados pelo filtro porque tinham cue recuperado; 22 não foram auditados. Qatar é auditado e ocultado, mas não pertence aos 35 atuais.

### Regra efetiva de `medium`

Para o cue da China, `medium` significa uma fonte contável, forte ou moderada, na janela inicial, com linguagem explícita de primeira posição (`collect_status_cue_salience_sources.py:490-521`).

Para o benchmark do incumbente deslocado, `medium` significa uma destas condições (`analyze_ex_top1_salience.R:206-216`):

1. pelo menos uma fonte contável usa linguagem explícita de posição ou deslocamento; ou
2. pelo menos duas linhas contáveis de cobertura comercial, provenientes de ao menos uma fonte independente, cobrem o incumbente sem rótulo inequívoco de primeira posição.

Uma linha é contável somente se a fonte é elegível, cai na janela de `entry_year - 1` a `entry_year + 1`, tem força `strong` ou `moderate`, foi marcada para entrar no benchmark e não recebeu `DO_NOT_COUNT` (`analyze_ex_top1_salience.R:76-126`). `Unknown` indica incumbente não identificado ou ausência de fonte contável. Nenhum caso recebe atualmente o código `low` nesse produtor.

### Substituições textuais seguras

Substituir o parágrafo iniciado em `paper_v4.Rmd:1884` por:

> To assess the recoverability of public rank language, I use a source audit originally constructed for 14 countries in an earlier no-covariate treated sample. This is not a census of the 35 countries treated in the current goods-only restricted-risk-set specification: 13 audited countries remain in the current treated sample, Qatar does not, and 22 current treated countries were not included in the source audit. The underlying matrix records both recovered and unrecovered China cues. Table 20 is a diagnostic subset: it displays the nine cases in which the China cue is currently coded as unknown; five audited cases with recovered cues are omitted by the display filter. The table distinguishes weak observation from cases in which public rank language about the displaced incumbent is recoverable. Non-recovery is not coded as evidence that a cue was absent because contemporaneous local or official records may be inaccessible or inconsistent with the trade-rank series. Except for Australia, whose displayed year has been reconciled to the current 2009 entry, the table retains the entry windows used in the legacy source audit. Table 21 reports Australia's broad-trade source separately.

Substituir a caption da Tabela 20 por:

> Selected unresolved cases from a 14-country legacy source audit of public rank-language recoverability and metric caveats.

Substituir a nota da Tabela 20 por:

> The source audit covers 14 countries from an earlier no-covariate treated sample and is not a census of the 35 countries treated in the current goods-only restricted-risk-set specification. Thirteen audited countries remain in the current treated sample; Qatar does not. The table displays the nine cases for which the China cue is coded as unknown; Chile, Brazil, Uruguay, Saudi Arabia, and Qatar have recovered China cues and are omitted from this diagnostic display. For the China cue, `medium` means one countable strong or moderate first-window source with explicit rank language. For the former-incumbent benchmark, `medium` means either one countable source with explicit incumbent-rank or displacement language, or at least two countable trade-coverage records from at least one independent source without a clear top-rank label. Countable sources must be eligible, fall within one year of the source-audit entry year, be coded strong or moderate, enter the benchmark, and not be marked `DO_NOT_COUNT`. `Unknown` means that the incumbent was not identified or that no countable benchmark source was recovered; no case is currently coded `low`. Australia's displayed entry year follows the current annual goods-only panel; other entry years retain the legacy source-audit windows.

Essas substituições corrigem o reporting. Elas não transformam a auditoria em censo, não atribuem buscas aos 22 casos não auditados e não alteram códigos de saliência.

## Item 15 — Tabela 23 e anos retidos/omitidos

### Finding normalizado

A Tabela 23 não permite reconstruir, por país, quais anos entram como tratados, quais períodos curtos são excluídos e quais anos fora da condição de tratamento são omitidos pelo risk set restrito.

### Evidência de defeito

- `paper_v4.Rmd:2123-2157` declara e exibe apenas `first_treat`, `treated_years`, `untreated_years`, `first_year_in_panel` e `last_year_in_panel` provenientes de `m2_unit_summary`.
- `scripts/functions.R:4407-4424` confirma que o unit summary é agregado por país e não retém listas de anos ou limites de cada período.
- `scripts/functions.R:4312-4323` retém para países tratados somente períodos qualificantes e anos anteriores ao primeiro tratamento nos quais China não ocupa a primeira posição. Anos fora da condição após saída e períodos curtos não qualificantes são removidos.
- Nos objetos existentes, os 35 países tratados atuais somam 36 períodos qualificantes; nove desses países também têm 14 períodos curtos excluídos. Há 440 anos tratados e 641 anos não tratados retidos. A tabela atual reporta apenas os totais por país.
- Período de entrada e saída também não basta: em pelo menos alguns casos o número de anos observados difere do intervalo civil, de modo que uma faixa contínua inventaria anos sem observação. O novo output deve registrar os anos efetivos.

### Outputs existentes e lacuna de apresentação

Os objetos atuais contêm informação suficiente como insumo, mas não um output pronto para o paper:

- `china_top_m2_goods_panel`: universo país-ano e condição China-top observada;
- `china_top_m2_goods_status_current_panel_bundle$panels[["5"]][["risk_set_restricted"]]`: chaves efetivamente retidas e indicador de tratamento;
- `china_top_m2_goods_status_current_period_summary`: entrada, saída, duração observada, intervalo civil e qualificação de cada período China-top;
- `china_top_m2_goods_status_current_unit_summary`: contagens usadas na Tabela 23.

Combinar esses objetos e compactar anos é uma nova transformação analítica destinada ao manuscrito. Pela regra do projeto, ela não pode ser feita no Rmd nem em um script externo para migração posterior.

### Proposta targets-first

Criar uma função pura em `scripts/functions.R` e os seguintes targets desde o início:

1. `china_top_m2_goods_status_current_min5_audit_bundle`: consome `china_top_m2_goods_panel` e `china_top_m2_goods_status_current_panel_bundle`; reutiliza `build_status_current_period_data(..., min_duration_years = 5L, min_entry_year = 2000L)` e produz as tabelas abaixo sem alterar a regra de tratamento.
2. `china_top_m2_goods_status_current_min5_country_year_audit`: uma linha por `iso3c-year` do universo auditável para os países tratados atuais.
3. `china_top_m2_goods_status_current_min5_treated_country_table`: tabela de 35 linhas pronta para o apêndice, derivada exclusivamente do target país-ano.
4. `china_top_m2_goods_status_current_min5_audit_validation`: checks fail-closed; o Rmd só lê a tabela após `all(passed)`.

Schema mínimo do target país-ano:

| Campo | Tipo | Regra |
|---|---|---|
| `specification` | string | valor fixo `goods_only_status_current_min5_risk_set_restricted` |
| `min_duration_years` | integer | valor fixo `5` |
| `iso3c`, `country_name`, `year` | string, string, integer | chave única `iso3c-year` |
| `observed_china_top` | logical | China ocupa a primeira posição no dado de bens observado |
| `status_current_period_id` | integer/NA | identificador recomputado pelo mesmo helper usado no painel |
| `period_entry_year`, `period_exit_year` | integer/NA | limites do período ao qual o ano pertence |
| `period_duration_observed_years` | integer/NA | número de anos observados, sem presumir continuidade civil |
| `period_calendar_span_years` | integer/NA | `exit - entry + 1` |
| `period_qualifies_min5` | logical | resultado da regra atual; não recodificar |
| `retained_in_risk_set` | logical | presença da chave no painel principal |
| `treatment_indicator_retained` | integer/NA | `china_top` do painel principal quando retido |
| `row_status` | enum | classificação exclusiva abaixo |

Valores permitidos de `row_status`:

- `retained_pre_entry_control`;
- `retained_qualifying_treated`;
- `omitted_missing_required_input`;
- `omitted_pre_entry_nonqualifying_china_top`;
- `omitted_post_entry_short_china_top_period`;
- `omitted_between_qualifying_periods_off_status`;
- `omitted_post_final_qualifying_exit_off_status`;
- `omitted_other_nonretained` como fallback fail-closed que deve ter contagem zero antes de publicação.

Schema da tabela de 35 países:

| Campo | Conteúdo |
|---|---|
| `Country`, `ISO3c` | identificação |
| `Qualifying entries and exits` | períodos qualificantes, separados por `;` |
| `Excluded short periods` | anos efetivamente observados em períodos curtos, compactados em faixas somente quando consecutivos |
| `Retained treated years` | anos efetivamente tratados, com a mesma compactação segura |
| `Omitted off-status years` | anos omitidos após a primeira entrada, separados por motivo quando houver |
| `Treated N`, `Untreated N`, `Omitted N` | contagens que reconciliam com o audit país-ano e com o unit summary |

Checks obrigatórios:

1. unicidade de `iso3c-year` e enumeração exaustiva e exclusiva de `row_status`;
2. igualdade exata das chaves `retained_in_risk_set` com `panels[["5"]][["risk_set_restricted"]]` para os 35 tratados;
3. `treatment_indicator_retained == 1` se e somente se o ano está retido e pertence a um período qualificante China-top;
4. entradas, saídas, duração observada e qualificação idênticas a `period_summary`;
5. `Treated N` e `Untreated N` idênticos a `unit_summary` por país;
6. exatamente 35 linhas na tabela e o mesmo conjunto ISO3c do target principal;
7. round-trip das strings compactadas para os anos do target país-ano, sem preencher lacunas não observadas;
8. contagem zero de `omitted_other_nonretained` antes de uso no manuscrito.

### Texto exato condicionado à existência dos targets

Somente após geração e validação dos targets, substituir `paper_v4.Rmd:2123` por:

> Table 23 provides a country-level audit of the 35 treated countries in the main goods-only restricted-risk-set specification. It reports every qualifying entry and exit, the observed years in excluded short China-top periods, the treated years retained by the estimator, and the post-entry off-status years omitted by the restricted risk set. Year ranges are compressed only across consecutive observed calendar years; gaps remain explicit.

Substituir a caption por:

> Country-level audit of retained and omitted years in the main goods-only status-current restricted-risk-set specification.

Substituir a nota por:

> Ranks are computed from goods exports only. A qualifying period begins in or after 2000, follows an observed non-China-top year, and contains at least five observed China-top years under the current rule. Treated years are the observed years in qualifying periods that are retained by the estimator. The restricted risk set retains clean pre-entry non-China-top years and qualifying treated years; it omits post-entry off-status years and nonqualifying short China-top periods. Entries, exits, and year lists come from the target-based country-year audit; ranges join only consecutive observed calendar years.

Até esses targets existirem e passarem os checks, a Tabela 23 atual deve permanecer inalterada.

## Limitações e dependências

- A adjudicação inspecionou objetos existentes no store, mas não confirmou frescor por rebuild.
- Não houve nova busca de fontes. Os 22 países tratados atuais fora da auditoria continuam explicitamente não auditados.
- O patch textual do item 2 não sincroniza os anos legados de Chile e Arábia Saudita nem remove Qatar da base histórica; apenas torna esses limites transparentes.
- O item 15 depende de autorização para alterar `scripts/functions.R`, `_targets.R`, o Rmd e depois executar o target/rebuild. Nenhuma dessas ações foi realizada aqui.
