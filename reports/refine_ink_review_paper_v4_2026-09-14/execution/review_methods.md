# Revisão independente de métodos — preliminar

**Achados primeiro.** Há uma imprecisão textual menor, confirmada nos produtores, na proposta do **item 6**: as interações são padronizadas no painel armazenado de **1997–2016**, antes de o helper restringir o ajuste a **1997–2015**. “Standardized over the estimation panel” não descreve exatamente essa sequência. A correção é apenas textual e vale também para o índice de preços; não requer reestimação.

A alegação original do especialista no **item 31**, já rejeitada pelo orquestrador, foi **REFUTED** independentemente: `abs()` não rompe a colinearidade no suporte efetivamente observado. **Não é um novo defeito atribuído ao candidato.** A nota do **item 25** não apresentou defeito confirmado nas verificações delimitadas abaixo.

**Veredicto do candidato: ADIADO / BLOCKED por identidade ainda não finalizada.** `execution/integration_final.txt` não apareceu durante a revisão de fontes nem após espera de 45 segundos. Não li nem aprovei um diff final. O hash observado do candidato identifica somente um instantâneo provisório. O próximo revisor deve aguardar o marcador, ler/hashar o candidato e o diff completos e conferir novamente o hash ao terminar.

## Identidade e limites

- Baseline congelado: `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`.
- Candidato observado em `/private/tmp/refine-review-20260914/paper_v4.Rmd`: `798665c291ac21733adfe219d2b9b9a9968626a356f71d4909cd2ea3cdf789a6` — **provisório, sem veredicto final**.
- Fonte integral da nota `domain_note.md`: `78356d0b657d1c1730e2607f92ecff3e8b6c36a6b46b21335023da92ab07ee4f`.
- Decisões do orquestrador: `d10d14c5bfe5a80d214d2b5106e39d089b1cc7f76e663f717d099084f2fdd3d6`.
- Modelo solicitado: Astra, high. Papel independente, sem delegação.
- Li `AGENTS.md`, `CLAUDE.md`, a skill `adjudicate-review`, sua especificação de registros, os comentários selecionados e a adjudicação. Nenhuma memória usada. Contrato argumentativo global não requerido para este recorte.
- Escopo: itens 2, 4, 6, 7, 8, 11, 18, 20, 21, 22, 27, 29, 31, 32; item 25 somente entendimento; item 15 somente desenho. Comentários gerais e demais itens não adjudicados.

## Achados localizados

| ID | Status | Severidade | Evidência e encaminhamento |
|---|---|---|---|
| RM-S006 | CONFIRMED | Menor | `sdid.md`, proposta do item 6; produtor commodity:72–118,158–164; helper SDiD:109–116. Corrigir a população de padronização descrita. Persistência/localização no candidato final ainda pendente. |
| RM-S031 | REFUTED | Maior se a proposta rejeitada fosse aplicada | `sdid.md`, item 31; `orchestrator_decisions.md`, rejeição do item 31; `scripts/functions.R:208–210,683–691,706–756`; matrizes e implementação local. Preservar a rejeição e o fit principal sem covariáveis. |
| RM-GATE | UNRESOLVED | Bloqueia somente veredicto final | Marcador de integração ausente; não certificar candidato em movimento. |

O JSON é o registro autoritativo, com evidências, hashes e saídas R integrais. Contagens: 1 confirmado, 0 parciais, 1 refutado e 1 não resolvido. Isso **não** é uma contagem de defeitos finais do candidato.

## Evidência mecânica central

**Item 31.** O store tem 1.920 observações, 96 países, 1997–2016. O fit usa 1.824 observações, os mesmos 96 países, 1997–2015; 95 controles, 12 anos pré e sete pós. Conferi unicidade e presença de todas as chaves, completude dos campos brutos, ordem das linhas e igualdade de todas as 13 colunas de X e de Y com o painel. Nenhum país supera os EUA; a diferença assinada reproduz exatamente o gap bruto.

Se Xp e Xg são as colunas afimmente reescaladas de poder e gap, **Xg + 0,8451679 Xp é uma função apenas do ano**, com resíduo máximo 9,44e-16. A projeção dessa direção nas duas funções objetivo de pesos do `synthdid` é zero até 4,88e-16 e 3,61e-16. Não estimei uma regressão para obter isso: derivei os fatores afins de dois valores distintos e conferi todas as observações.

Inspecionei as funções instaladas de `synthdid` 0.0.9: `synthdid_estimate`, `collapsed.form` e `sc.weight.fw.covariates`. O algoritmo atualiza conjuntamente beta e os pesos, com os dois interceptos habilitados, e calcula o contraste sobre `Y - contract3(X, beta)`. As componentes anuais e de unidade são anuladas pelas comparações com intercepto. Beta do gap = −0,008069458 não identifica seu efeito separado do poder. A distância geográfica varia no máximo 4,44e-16 dentro de uma unidade; seu beta é 7,96e-19.

O fit principal tem X de dimensão **96 × 19 × 0**. Os pesos dos controles e dos períodos pré somam um, podendo conter zeros; Brasil recebe peso positivo 1 e cada ano pós 1/7. O contraste calculado com esses pesos reproduz **−0,272771407583060**, com discrepância zero. Nenhum modelo ou peso foi reestimado.

**Item 6.** O produtor `audit_brazil_sdid_commodity_no_covariates.R` padroniza antes de chamar `sdid_fit_spec(panel, cols)`, cujo filtro padrão termina em 2015. Na reconstrução aritmética da interação de exposição primária, a média/DP são aproximadamente 0/1 nas 1.920 linhas; nas 1.824 linhas retidas, são **0,01186477/1,024619**. A observação delimita a documentação da sequência efetiva; não demonstra mudança ou erro no ATT.

**Itens 18/20/29/32.** O produtor de SE calcula o desvio-padrão de população finita das reamostragens placebo, com 20.000 replicações e seed 20260520. O SE armazenado é 0,13060794328219072; a aproximação normal produz p/IC a partir dele. Reconstruí os ranks **3/96** e **7/96** da distribuição existente e reconciliei o p normal. Os pesos lambda usam resultados dos controles antes e depois do início; omega usa históricos pré-tratamento. O produtor da Figura 2 lê o fit principal sem covariáveis e usa seu plot padrão. A legenda deve distinguir distância vertical bruta e ATT líquido do contraste pré ponderado; nenhum novo gráfico foi gerado.

## Demais verificações delimitadas

- **Item 2:** reconciliação direta do RDS consumido: 14 países auditados, nove casos exibidos com China-cue unknown; 13 pertencem aos 35 tratados atuais, Qatar não, 22 atuais não foram auditados. Conferi o filtro original, a regra countable, medium e a exceção manual de Qatar. Fonte/código recuperados não autorizam inferência de ausência de cue, nem uma busca histórica inventada para os demais.
- **Itens 4/7/8:** busca `china`, ordem cronológica, extração de título/data, deduplicação, filtro textual, alias `gpt-4.1-mini`, temperatura zero, slices e parser conferidos nos produtores originais. O código disponível é configuração preservada, não log histórico completo; inclusive o loop de slices não certifica que sozinho produziu todo o arquivo. O arquivo final tem 14.589 títulos únicos e registra o alias. Validação: 100 registros, 88% de acordo sem ponderação; seis predições trade com concordância integral. Isso não estabelece recall populacional, probabilidades de inclusão, nem invariância temporal do erro. Nenhuma matriz adicional está autorizada para o paper fora do grafo.
- **Item 11:** mesmos 95 doadores, janelas pós de seis, cinco, quatro, sete e cinco anos; ajuste separado em cada linha. O pré nominal de 2012 contém 2009–2011 já tratados. Não há inferência dos contrastes entre linhas nem estimando comum demonstrado.
- **Item 21:** conferi −1/0/+1 para não/abstenção/sim, distância à China menos distância aos EUA, exclusão de votos inválidos e divergência das referências. O DDD corrigido tem FE de país e resolução, Brasil × pós, Brasil × domínio e interação tripla, com peso de entrada 1 por voto observado. Não substituí esses FE por ano/área temática.
- **Item 22:** quatro células armazenadas com 4.727 linhas e 10.000 bootstraps. Os contrastes r2−r1 diferem (−0,059345646431 BSV; −0,038020234148 UNGA-DM), sustentando não aditividade descritiva, sem teste de interação. Os 1.000 draws pareados reconciliam os resumos a 1,11e-16: p percentil 0,134/0,356. O produtor mantém r fixo em cada réplica, `CV=FALSE`. Diferenças entre fontes são nas escalas originais; não rejeição não demonstra equivalência nem atribuição invariável à escala.
- **Item 27:** li as séries separadas e seu produtor. Há oscilação anual expressiva na China e movimento brasileiro persistente em direção à China em 2009–2012. Não calculei nem validei atribuição da maior parte da variação bilateral a um país.

## Nota do item 25 e propostas futuras

A nota foi lida integralmente no hash acima. A formulação país × domínio permite contrastes temáticos persistentes próprios de cada doador. A explicação de FWL é correta: os controles atuais não impõem soma zero dos pesos de direitos humanos para cada doador; país × domínio impõe essa condição, sujeito à identificação.

A nota distingue adequadamente:
1. a diferença tripla **−1** das médias brutas do exemplo didático, que não pretende reproduzir o coeficiente com FE de resolução;
2. o contraexemplo sintético arquivado na estrutura real de observações (**+0,031791903613**), que não estima viés observado nem fornece limite universal;
3. os resultados reais arquivados: atual **−0,222333401762**, país × domínio **−0,225731227550**, diferença **−0,003397825788**, ou 1,528257% do módulo atual.

Li `check_ddd.R` sem executá-lo e executei somente `domain_note_verify.R`, após inspecionar sua ausência de ajustes/escritas. O RDS consumido coincide com o coeficiente atual da sensibilidade; amostra: 55.190 votos, 95 países e 612 resoluções, chaves únicas e campos essenciais completos. A identidade FWL arquivada tem discrepância máxima 1,58e-10. O EP agrupado é precisão condicional; a nota não transfere ranks atuais à extensão nem afirma identificação causal por estabilidade. **Nenhum defeito confirmado nesses checks delimitados da nota.**

O desenho do **item 15** permanece somente proposta: bundle, auditoria país–ano, tabela e validação no `targets`; exige listas dos anos observados, reconciliação de chaves e proibição de preencher lacunas ao compactar intervalos. Não computei suas contagens nem executei helpers. Novos outputs dos itens 4/7/8 e eventual sensibilidade país × domínio também precisam de produção pelo grafo, se autorizados. Nenhuma dessas análises é exigência desta revisão, nem deve aparecer no candidato como concluída.

## Reprodução e fronteira da entrega

As conferências usaram `Rscript --vanilla`, apontando a biblioteca renv existente, leituras RDS/CSV, aritmética e inspeção de funções instaladas. Os scripts somente de verificação `domain_note_verify.R` e `comparability_verify.R` foram lidos antes da execução; seus hashes e resultados constam no JSON. O segundo reconcilia janelas e bootstrap **já armazenado**, sem realizar novos sorteios/ajustes.

A conferência de identidade de poder pode ser repetida lendo `synth_fit`, `synth_data` e `gpi_data`, formando a grade de nomes de linhas/colunas de Y, ligando por país–ano, verificando todas as colunas e calculando a combinação afim acima. A saída e o código das funções instaladas usados para verificar os dois objetivos estão incorporados no JSON.

**Escritos somente:** `execution/review_methods.md` e `execution/review_methods.json`. `CODEX_AUTO_COMMIT_PUSH_DRY_RUN=1` foi conferido e preservado. Sem alterações em manuscrito, propostas, dados, scripts ou pipeline; sem nova estimação, bootstrap, placebo, classificação, coleta, renderização, commits/push, sinais ou locks. Os avisos de locale do R não interromperam as conferências numéricas.

Não estabeleci frescor do store por rebuild, proveniência histórica integral de APIs, validade causal geral ou layout do candidato. **Falta concluir a revisão dos bytes finais e de seu diff após o marcador de integração.**


Validação do registro: **PASS** no validador da skill contra o baseline congelado. O hash da nota foi reconferido sem mudança; o marcador continuava ausente na conferência final.
