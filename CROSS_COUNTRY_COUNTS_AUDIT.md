# Auditoria da inconsistência nas contagens cross-country

Data: 2026-05-13
Status: diagnóstico concluído; correção pendente
Prioridade: alta

## Pergunta

De onde vem a divergência entre a narrativa do manuscrito, que fala em "4 de 8 países tratados" com reversão, e os resultados/slides atuais, que reportam 99 países no painel, 59 tratados, 52 switching e 7 absorbing?

## Conclusão curta

A divergência não é apenas um texto antigo no abstract. Há uma inconsistência real entre três camadas do projeto:

1. O diagnóstico C&S/DiD (`event_study_data_usa`) ainda tem 67 países, 8 tratados e 59 controles. Entre os 8 tratados, 4 são absorbing e 4 são switching. A frase "four of the eight treated countries" corresponde a esse objeto.
2. O objeto bruto de eventos (`classified_events`) tem 13 eventos em que China virou #1 deslocando os EUA. Cinco desses eventos não entram no painel balanceado com UNGA usado em `event_study_data_usa`: HKG, TWN, KOR, GNQ e LBR.
3. O estimador principal atual (`fect_ife`) usa `switching_panel`, que tem 99 países e 59 países tratados. Nesse painel, `china_top` não mede literalmente "China é o principal destino de exportação"; o código marca tratamento quando China rankeia acima dos EUA entre os parceiros de exportação disponíveis.

Portanto, o problema substantivo é uma mistura de amostra e definição de tratamento, não apenas uma contagem desatualizada.

## Pente fino adicional: a regra real não está clara no texto

Busca realizada em 2026-05-13 nos arquivos fonte (`.R`, `.Rmd`, `.md`, `.tex`) e em versões renderizadas por `pdftotext` (`output/paper_v4.pdf`, `output/paper_v4_anonymous.pdf`, `presentations/paper_v4_beamer_90.pdf`, `math_guide_factor_model.pdf`).

Resultado: fora desta auditoria e de `PENDING.md`, não encontrei texto no paper, slides ou guia matemático que explique a regra real como "China rankeia acima dos EUA" (`rank_CHN < rank_USA`). O texto público documenta quase sempre uma regra diferente: "China é o principal destino de exportações", "China holds the top rank", "China = top partner", ou "USA regains the top position".

Exemplos centrais:

- `paper_v4.Rmd` e `paper_v4_anonymous.Rmd`, definição global: `treat_def_panel <- "Treatment indicator equals 1 in any year China is currently the top export destination; turns off if USA regains the position (switching treatment)"`.
- `paper_v4.Rmd` e `paper_v4_anonymous.Rmd`, seção cross-country: "For the cross-country analysis, $D_{it}$ equals 1 in any year China is currently the top export destination".
- `paper_v4.Rmd` e `paper_v4_anonymous.Rmd`, resultados: "The treatment indicator $D_{it}$ equals 1 in any year China is currently the top export destination and switches off when the USA regains that position."
- `presentations/paper_v4_beamer_90.Rmd`: "treated cells are years in which China is currently the top export destination" e "If the United States regains the top position, $D_{it}$ returns to zero."
- `math_guide_factor_model.Rmd`: define $D_{it}=1$ "se a China é o principal destino de exportações do país".

O único lugar onde a regra real aparecia antes desta auditoria era no código.

## Evidência

### Objeto C&S/diagnóstico: 8 tratados, 4 switching

O target `event_study_data_usa` é construído em `_targets.R` a partir de `filter_usa_top_control(...)` e mantém:

- 67 países no painel;
- 8 tratados;
- 59 controles;
- tratados: AGO, CHL, BRA, THA, JPN, PER, SAU, VNM;
- 4 absorbing: AGO, CHL, BRA, SAU;
- 4 switching: THA, JPN, PER, VNM.

Esse é o objeto reproduzido pelo relatório antigo `quality_reports/reversal_exploration.pdf`, que explicitamente diz: "Of the 8 treated countries in the DiD specification".

### Eventos brutos: 13 deslocamentos dos EUA

O target `classified_events` identifica 13 eventos em que China virou #1 e o parceiro deslocado no ano anterior era os EUA:

| ISO3 | Primeiro ano | Absorbing | Entra em `event_study_data_usa`? |
|---|---:|---|---|
| HKG | 2002 | Não | Não |
| TWN | 2002 | Sim | Não |
| KOR | 2003 | Sim | Não |
| GNQ | 2006 | Não | Não |
| LBR | 2012 | Não | Não |
| AGO | 2007 | Sim | Sim |
| CHL | 2008 | Sim | Sim |
| BRA | 2009 | Sim | Sim |
| THA | 2009 | Não | Sim |
| JPN | 2010 | Não | Sim |
| PER | 2012 | Não | Sim |
| SAU | 2015 | Sim | Sim |
| VNM | 2018 | Não | Sim |

Os cinco primeiros não aparecem em `event_study_data`, depois da fusão com o painel UNGA balanceado usado pelo DiD.

### Objeto fect principal: 99 países, 59 tratados

O target principal atual é:

```r
tar_target(switching_panel, build_switching_panel(trade_data, unga_data, classified_events, usa_top_countries))
```

Em `scripts/functions.R`, `build_switching_panel(...)` define:

```r
treated_usa <- classified_events %>%
  dplyr::filter(displaced == "USA") %>%
  pull(iso3c)

did_countries <- unique(c(treated_usa, usa_top_countries))

china_top = as.integer(!is.na(rank_CHN) & (is.na(rank_USA) | rank_CHN < rank_USA))
```

Isso amplia a amostra para todos os países em que os EUA foram #1 em algum momento, mais os 13 eventos classificados. Além disso, a regra operacional não exige `rank_CHN == 1`; ela exige que `rank_CHN < rank_USA`. Logo, muitos países que eram controles no C&S passam a ter anos tratados no `fect` quando China fica acima dos EUA, mesmo que outro parceiro possa estar em primeiro lugar.

Contagem atual desse painel:

- 99 países;
- 59 países com pelo menos um ano tratado;
- 52 switching, usando a regra `switches > 1`;
- 7 absorbing, usando a regra `switches <= 1`;
- dos 59 tratados no `switching_panel`, apenas 8 são os tratados de `event_study_data_usa`; 3 adicionais aparecem em `classified_events` mas não no DiD balanceado; 48 não são eventos "China virou #1 deslocando EUA" segundo `classified_events`.

O tamanho da divergência entre a regra implementada e a regra descrita no texto é grande:

- 544 país-anos tratados no `switching_panel`;
- 280 país-anos tratados têm `rank_CHN == 1`;
- 264 país-anos tratados têm `rank_CHN > 1`;
- 49 dos 59 países tratados têm pelo menos um ano tratado em que China não é #1;
- 27 dos 59 países tratados nunca têm China como #1 em seus anos tratados; entram apenas porque China está acima dos EUA.

Exemplos de país-anos tratados pela regra atual, embora China não seja #1:

| ISO3 | País | Ano | Rank China | Rank EUA | Parceiro #1 real |
|---|---|---:|---:|---:|---|
| BHR | Bahrain | 1990 | 53 | 160 | JPN |
| GBR | United Kingdom | 1990 | 30 | 37 | DEU |
| ISR | Israel | 1990 | 78 | 178 | JPN |
| MMR | Myanmar (Burma) | 1990 | 4 | 29 | THA |
| NIC | Nicaragua | 1990 | 5 | 29 | CAN |
| PAK | Pakistan | 1990 | 15 | 22 | JPN |
| AFG | Afghanistan | 1992 | 9 | 12 | DEU |
| JOR | Jordan | 1992 | 5 | 14 | IND |
| MLT | Malta | 2007 | 3 | 7 | outro parceiro |

## Origem provável no histórico

A frase "four of the eight treated countries" entrou no manuscrito quando o projeto substituiu C&S por `fect` em `b64abb7` (2026-02-17). Naquele momento, o plano `quality_reports/plans/2026-02-17_fect-ife-replace-cs.md` motivava o `fect` a partir do diagnóstico C&S: "4 dos 8 países tratados têm tratamento switching".

O script exploratório `scripts/explore_switching_did.R` também partia de `event_study_data_usa`:

```r
did_countries <- unique(es_data_usa$iso3c)
```

Esse relatório gerou um painel de 67 países. A função integrada ao pipeline, porém, passou a usar `classified_events` e `usa_top_countries`, gerando o painel atual de 99 países. A narrativa do manuscrito preservou o diagnóstico de 8 tratados, enquanto a seção de resultados e os slides passaram a usar os números do novo `switching_panel`.

## Arquivos afetados

- `paper_v4.Rmd`: abstract, introdução, desenho cross-country e discussão de switching ainda misturam 8/4 com resultados do `switching_panel`.
- `paper_v4_anonymous.Rmd`: mesma inconsistência no corpo do texto.
- `presentations/paper_v4_beamer_90.Rmd`: usa os números atuais do `switching_panel`, mas mantém linguagem de "top export destination" em alguns pontos.
- `scripts/functions.R`: comentário e nome `china_top` sugerem "China é #1", mas a regra implementada é "China rankeia acima dos EUA".
- `quality_reports/*`: relatórios antigos documentam corretamente o diagnóstico 8/4 para o objeto C&S, mas não devem ser citados como se descrevessem o `fect` principal atual.

## Decisão pendente

Antes de reescrever o paper, é preciso escolher o estimando cross-country principal:

1. **Estimando restrito: China vira #1 deslocando os EUA.** Reescrever `build_switching_panel(...)` para usar a mesma base substantiva do diagnóstico C&S, provavelmente `event_study_data_usa` ou os eventos USA-displacement com cobertura UNGA. Isso preserva a teoria atual, mas reduz poder estatístico.
2. **Estimando relativo EUA-China: China rankeia acima dos EUA.** Manter o código atual, mas reescrever teoria, labels, captions e abstract para dizer "China overtakes/outranks the United States in the export-destination hierarchy", não "China becomes the top export destination".
3. **Estimando amplo: China é #1 contra qualquer parceiro.** Usar a lógica de `switching_panel_any`, que exige `rank_CHN == 1`, mas deixa de ser hegemon-specific.

Enquanto essa decisão não for tomada, a pendência deve continuar como alta prioridade.

## Teste ad hoc sem alterar targets: regra textual `rank_CHN == 1`

Em 2026-05-13, rodei `scripts/diagnostics/test_factor_model_china_top_rule.R`, sem alterar `_targets.R` nem escrever no targets store. O teste mantém a mesma amostra de país-anos do `switching_panel` atual e troca apenas a regra de tratamento:

- regra atual do código: `rank_CHN < rank_USA`;
- regra textual testada: `rank_CHN == 1`.

Validação do painel:

- ambos os painéis têm 3.294 observações, 99 países e anos 1990-2023;
- ambos usam exatamente as mesmas linhas país-ano;
- não há duplicatas país-ano;
- não há missing em outcome nem tratamento;
- o painel alternativo foi validado como exatamente `china_top == (rank_CHN == 1)`.

Comparação do `fect` IFE:

| Especificação | Países | Tratados | País-anos tratados | Switching | Absorbing | ATT | SE | IC 95% | p | r* |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|
| Código atual: China rankeia acima dos EUA | 99 | 59 | 544 | 52 | 7 | -0.074 | 0.029 | [-0.131, -0.017] | 0.011 | 1 |
| Regra textual: China é #1 | 99 | 32 | 280 | 31 | 1 | -0.056 | 0.032 | [-0.119, 0.007] | 0.083 | 2 |

Interpretação: quando o tratamento é definido como o texto descreve, o sinal permanece negativo, mas o efeito fica menor e deixa de ser estatisticamente significativo ao nível de 5%. O resultado principal atual depende materialmente da regra mais ampla `rank_CHN < rank_USA`.
