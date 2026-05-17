# Nota analítica: alinhamento relacional Brasil-China na AGNU, 2005-2012

Fonte: pacote `unvotes` 0.3.0, baseado nos dados de Erik Voeten sobre votações nominais da AGNU. O tarball bruto está preservado em `data/raw/unvotes/unvotes_0.3.0.tar.gz`. Data de acesso registrada no projeto: 2026-05-16.

## Definição operacional

A unidade principal é a votação nominal (`rcid`). A amostra contém 748 resoluções entre 2005 e 2012 nas quais Brasil e China têm votos válidos (`yes`, `no` ou `abstain`). Ausentes são excluídos dos percentuais. Para medir o apoio relacional dos demais países, Brasil e China também são excluídos do denominador dos percentuais de alinhamento.

As famílias recorrentes de resolução são aproximadas por uma chave normalizada da descrição (`title_key`). O mecanismo C exige que Brasil e China mantenham os votos estáveis e que o apoio à posição de pelo menos um dos dois mude mais de 5 pontos percentuais entre duas ocorrências da mesma família. Chaves procedimentais genéricas como `the acting president` e `the president` foram excluídas da classificação A-E para evitar falsas famílias recorrentes.

O CSV por ano e tema contém dois níveis em `theme_level`: `issue_unvotes`, que preserva o tema original do `unvotes`, e `familia_substantiva`, que agrega esses temas nas famílias substantivas usadas nas figuras e na interpretação.

## Resposta curta

A aproximação observável aparece como uma combinação dos dois mecanismos, mas a evidência de mudança direta do Brasil é mais nítida quando há transições de divergência para convergência com a China estável. Foram identificadas 3 transições desse tipo no conjunto de famílias recorrentes; 2 terminam no período pós-2009. A evidência de realinhamento relacional também existe em sentido amplo: há 6 transições pós-2009 em que os votos de Brasil e China ficam iguais aos da ocorrência anterior, mas a estrutura de apoio dos demais países muda substantivamente. Em sentido estrito, isto é, com mudança na vantagem relativa China-Brasil superior a 5 p.p., há 3 transições pós-2009. Dessas transições estritas, 0 aumentam a vantagem relativa da posição chinesa e 3 aumentam a vantagem relativa brasileira.

Isso favorece uma leitura mais específica: a evidência pós-2009 mais favorável à narrativa de aproximação direta vem de direitos humanos (2 casos diretos), não de uma migração geral para votações em que a posição chinesa fosse mais majoritária. Fora de direitos humanos há 0 caso direto pós-2009 e 1 caso de realinhamento relativo estrito, mas este último não se move na direção de maior vantagem chinesa.

O tema com maior aumento agregado de convergência após 2009 é `Outros / sem codificação` (delta de 9.7 p.p.). O tema em que a posição chinesa aparece mais frequentemente como mais majoritária no pós-2009 é `Direitos humanos` (4.2% das resoluções).

## Tabela 1. Resoluções por tema e mudança pré/pós-2009

| tema | n_pre | n_pos | conv_pre | conv_pos | delta_conv | china_mais_majoritaria_pos | gap_pos |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Outros / sem codificação | 94 | 77 | 73.4 | 83.1 | 9.7 | 3.9 | 4.8 |
| Direitos humanos | 102 | 96 | 69.6 | 77.1 | 7.5 | 4.2 | 3.8 |
| Descolonização | 51 | 52 | 94.1 | 98.1 | 4.0 | 0.0 | 1.8 |
| Armas/desarmamento/nuclear | 112 | 108 | 83.0 | 84.3 | 1.2 | 0.0 | 11.6 |
| Palestina/Oriente Médio | 71 | 65 | 100.0 | 100.0 | 0.0 | 0.0 | 0.0 |
| Desenvolvimento econômico | 42 | 40 | 92.9 | 90.0 | -2.9 | 2.5 | 4.5 |

Legenda: `conv_pre` e `conv_pos` são percentuais de resoluções em que Brasil e China votam igual; `gap_pos` é apoio médio ao Brasil menos apoio médio à China no pós-2009, em pontos percentuais.

## Tabela 2. Mecanismos A-E por período

| periodo | mecanismo | descricao | n | brasil_para_china | china_para_brasil | realinhamento | realinhamento_relativo |
| --- | --- | --- | --- | --- | --- | --- | --- |
| pré-2009 | A | A. Brasil muda e China fica igual | 4 | 1 | 0 | 0 | 0 |
| pré-2009 | B | B. China muda e Brasil fica igual | 2 | 0 | 1 | 0 | 0 |
| pré-2009 | C | C. Brasil/China ficam iguais, mas apoio relativo muda | 6 | 0 | 0 | 6 | 1 |
| pré-2009 | D | D. Ambos mudam | 0 | 0 | 0 | 0 | 0 |
| pré-2009 | E | E. Ambos ficam iguais e estrutura quase não muda | 113 | 0 | 0 | 0 | 0 |
| pós-2009 | A | A. Brasil muda e China fica igual | 4 | 2 | 0 | 0 | 0 |
| pós-2009 | B | B. China muda e Brasil fica igual | 7 | 0 | 3 | 0 | 0 |
| pós-2009 | C | C. Brasil/China ficam iguais, mas apoio relativo muda | 6 | 0 | 0 | 6 | 3 |
| pós-2009 | D | D. Ambos mudam | 0 | 0 | 0 | 0 | 0 |
| pós-2009 | E | E. Ambos ficam iguais e estrutura quase não muda | 205 | 0 | 0 | 0 | 0 |

O padrão favorável à narrativa principal deve ser lido com cautela: mudanças de convergência podem decorrer de Brasil se aproximando de uma posição chinesa estável, mas também de China se aproximando de uma posição brasileira estável. Esses casos são marcados como falsos positivos potenciais abaixo. Foram encontrados 4 falsos positivos desse tipo.

## Tabela 3. Casos de mudança direta do Brasil em direção à China

| ano | resolucao | tema | familia | transicao | delta_apoio_china |
| --- | --- | --- | --- | --- | --- |
| 2006 | A/RES/61/57 | Armas/desarmamento/nuclear | conclusion of effective international arran... | A/RES/60/53 -> A/RES/61/57 (BR abstain -> yes; CN yes) | -34.5 |
| 2010 | A/RES/65/195 | Direitos humanos | report of the human rights council | A/RES/63/160 -> A/RES/65/195 (BR abstain -> yes; CN yes) | -34.2 |
| 2010 | A/RES/65/216 | Direitos humanos | globalization and its impact on the full en... | A/RES/64/160 -> A/RES/65/216 (BR abstain -> yes; CN yes) | -68.5 |

Esses casos são os melhores candidatos para process tracing qualitativo se a pergunta for se o Brasil mudou voto em direção a uma posição chinesa relativamente estável.

## Tabela 4. Casos pós-2009 de realinhamento relacional

| ano | resolucao | tema | familia | votos | delta_apoio_brasil | delta_apoio_china | delta_vantagem_china |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2009 | A/RES/64/31 | Armas/desarmamento/nuclear | follow up to nuclear disarmament obligation... | BR=yes; CN=abstain | 10.9 | -9.8 | -20.7 |
| 2011 | A/RES/66/175 | Direitos humanos | situation of human rights in the islamic re... | BR=abstain; CN=no | 2.6 | -8.4 | -11.0 |
| 2011 | A/RES/66/174 | Direitos humanos | situation of human rights in the democratic... | BR=yes; CN=no | 6.9 | -2.5 | -9.4 |

Esses casos são úteis para rastrear se mudanças na distribuição de votos de terceiros alteram a interpretação relacional do alinhamento, mesmo quando Brasil e China não mudam seus próprios votos.

## Tabela 5. Falsos positivos potenciais: China muda para o Brasil

| ano | resolucao | tema | familia | transicao |
| --- | --- | --- | --- | --- |
| 2006 | A/RES/61/77 | Armas/desarmamento/nuclear | transparency in armaments | A/RES/60/226 -> A/RES/61/77 (CN abstain -> yes; BR yes) |
| 2009 | A/RES/64/55 | Armas/desarmamento/nuclear | follow up to the advisory opinion of the in... | A/RES/63/49 -> A/RES/64/55 (CN abstain -> yes; BR yes) |
| 2010 | A/RES/65/71 | Armas/desarmamento/nuclear | decreasing the operational readiness of nuc... | A/RES/63/41 -> A/RES/65/71 (CN abstain -> yes; BR yes) |
| 2012 | A/RES/67/234 | Armas/desarmamento/nuclear; Desenvolvimento econômico | the arms trade treaty | A/RES/64/48 -> A/RES/67/234 (CN abstain -> yes; BR yes) |

Essas transições não sustentam a narrativa de mudança direta do Brasil; elas indicam convergência produzida por mudança chinesa mantendo o voto brasileiro estável.

## Evidência fora de direitos humanos

A evidência fora de direitos humanos é limitada para a narrativa forte. Há famílias de armas/desarmamento/nuclear com transições relevantes, mas as transições pós-2009 mais claras de convergência por mudança brasileira são de direitos humanos. Além disso, vários casos fora de direitos humanos aparecem como falsos positivos porque a China muda para uma posição brasileira já estável.

## Tabela 6. Prioridades para process tracing

| criterio | ano | resolucao | tema | familia | transicao | delta_apoio_china | votos | delta_apoio_brasil | delta_vantagem_china |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| mudança direta do Brasil | 2006 | A/RES/61/57 | Armas/desarmamento/nuclear | conclusion of effective international arran... | A/RES/60/53 -> A/RES/61/57 (BR abstain -> yes; CN yes) | -34.5 | NA | NA | NA |
| mudança direta do Brasil | 2010 | A/RES/65/195 | Direitos humanos | report of the human rights council | A/RES/63/160 -> A/RES/65/195 (BR abstain -> yes; CN yes) | -34.2 | NA | NA | NA |
| mudança direta do Brasil | 2010 | A/RES/65/216 | Direitos humanos | globalization and its impact on the full en... | A/RES/64/160 -> A/RES/65/216 (BR abstain -> yes; CN yes) | -68.5 | NA | NA | NA |
| realinhamento relacional | 2009 | A/RES/64/31 | Armas/desarmamento/nuclear | follow up to nuclear disarmament obligation... | NA | -9.8 | BR=yes; CN=abstain | 10.9 | -20.7 |
| realinhamento relacional | 2011 | A/RES/66/175 | Direitos humanos | situation of human rights in the islamic re... | NA | -8.4 | BR=abstain; CN=no | 2.6 | -11.0 |
| realinhamento relacional | 2011 | A/RES/66/174 | Direitos humanos | situation of human rights in the democratic... | NA | -2.5 | BR=yes; CN=no | 6.9 | -9.4 |

## Validações

As validações obrigatórias foram salvas em `quality_reports/un_vote_cases/brazil_china_vote_alignment_validation_2005_2012.csv`. Elas confirmam que Brasil e China têm votos válidos nas resoluções analisadas; que não há duplicatas por `rcid` no CSV por resolução; que os percentuais estão entre 0 e 100; que ausentes foram excluídos dos denominadores; e que `rcid`, símbolo da resolução, ano, temas, votos e links foram preservados.

## Arquivos gerados

- Métricas por resolução: `data/processed/unvotes/brazil_china_vote_alignment_by_resolution_2005_2012.csv`
- Resumo por ano e tema: `data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv`
- Mecanismos por família recorrente: `data/processed/unvotes/brazil_china_vote_alignment_mechanisms_2005_2012.csv`
- Figura 1: `quality_reports/un_vote_cases/figura_1_alinhamento_medio_brasil_china_por_tema_2005_2012.png` e `quality_reports/un_vote_cases/figura_1_alinhamento_medio_brasil_china_por_tema_2005_2012.pdf`
- Figura 2: `quality_reports/un_vote_cases/figura_2_diferenca_apoio_relativo_por_tema_2005_2012.png` e `quality_reports/un_vote_cases/figura_2_diferenca_apoio_relativo_por_tema_2005_2012.pdf`
- Figura 3: `quality_reports/un_vote_cases/figura_3_decomposicao_mecanismos_pre_pos_2009.png` e `quality_reports/un_vote_cases/figura_3_decomposicao_mecanismos_pre_pos_2009.pdf`
- Figura 4: `quality_reports/un_vote_cases/figura_4_heatmap_convergencia_apoio_relativo_2005_2012.png` e `quality_reports/un_vote_cases/figura_4_heatmap_convergencia_apoio_relativo_2005_2012.pdf`
