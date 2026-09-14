# Item 25 — O que acrescentam os efeitos fixos país × domínio?

Nota para o autor, 14 de setembro de 2026. Escopo: entendimento e verificação de evidência existente. Nenhuma implementação proposta foi aplicada.

**O efeito fixo país × domínio permite que cada doador tenha sua própria diferença persistente entre votos de direitos humanos e demais votos. A interação Brasil × domínio já existente permite essa diferença específica apenas para o Brasil.** A extensão protege o coeficiente contra a transformação de diferenças temáticas fixas entre doadores em uma mudança aparente quando muda a composição dos votos observados. Ela não resolve, por si, seleção de votos ou choques temáticos que mudam no tempo.

**Adjudicação: PARTIAL como pendência de correção.** O alerta condicional do parecer é procedente: a restrição existe e seu mecanismo é verificável. Mas o manuscrito já a declara e os diagnósticos arquivados mostram pequena sensibilidade à extensão sugerida. Não há demonstração de que um viés de composição explique o resultado substantivo. O parecer usa “may” e “could”; esta nota preserva seu caráter condicional, sem lhe atribuir uma alegação categórica de viés.

## 1. Evidência localizada e identidade dos arquivos

O Item 25 está em `items_to_address.md:30`, selecionado explicitamente para entendimento, e em `feedback-the-foreign-policy-impact-of-trade-based-status-ga-2026-09-14.md:434–442`. Ambos ficam em `reports/refine_ink_review_paper_v4_2026-09-14/`. O parecer aponta a frase sobre ausência de interceptos de domínio para cada doador; a frase permanece em `paper_v4.Rmd:975` e na página 26 de `output/paper_v4.pdf`.

Em verificação nesta tarefa, o Rmd ativo e `execution/baseline/paper_v4.Rmd` eram idênticos por SHA-256: `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`. O PDF ativo e o congelado também eram idênticos: `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`. A extração localizada do PDF está em `domain_note_pdf_excerpt.json`. Isso confirma a correspondência local da passagem citada; não certifica todos os bytes recebidos pelo serviço externo nem constitui auditoria integral da conversão do paper. Não se exigiu contrato global de argumento para esta explicação metodológica delimitada.

O caminho efetivamente consumido importa: `paper_v4.Rmd:904–910` lê os modelos DDD de `data/processed/diagnostics/RIO_20260905_ddd/corrected_ddd_bundle.rds`. Não lê o coeficiente DDD diretamente do target nominal. O arquivo é produzido pela revisão separada de setembro, documentada em `scripts/diagnostics/reestimate_corrected_ddd_RIO_20260905.R:67–113,196–201`. Seu hash atual coincide com o registrado pela revisão independente: `3f16f202a8aac1d6ca6d73acd5d5c45c3a0090358cc646744da2f7f5677de188`. Os hashes atuais de `scripts/functions.R`, do script produtor e do script de revisão também coincidem com o manifesto daquela revisão. A observação serve para rastrear a evidência, sem abrir outra pendência de implementação.

## 2. Modelo atual e extensão

Seja \(i\) um país e \(r\) uma resolução. Defina \(B_i=1\) para Brasil, \(P_r=1\) para 2009–2012 e \(H_r=1\) se a resolução tiver qualquer classificação de direitos humanos. O resultado é

\[
Y_{ir}=|v_{ir}-v_{Cr}|-|v_{ir}-v_{Ur}|,
\]

em que os votos “não”, abstenção e “sim” recebem −1, 0 e +1; C e U indicam China e Estados Unidos. Valores mais negativos indicam maior proximidade à China relativamente aos EUA. A amostra usa votos observados em resoluções nas quais os dois países divergem, em 2005–2012; ausências e não participação não são abstenções. O produtor filtra votos válidos e exige votos válidos das duas referências (`scripts/functions.R:6555–6561,6590–6676`).

A equação atual é

\[
Y_{ir}=\alpha_i+\lambda_r+\beta B_iP_r+\gamma B_iH_r+\delta B_iP_rH_r+\varepsilon_{ir}.
\tag{1}
\]

Ela está no Rmd, linhas 971–975, e em `selective_unga_fit_ddd_model`, `scripts/functions.R:6908–6918`. Cada voto observado entra com peso 1; não são os pesos sintéticos do SDiD. O efeito fixo de país \(\alpha_i\) permite níveis gerais distintos de alinhamento. \(\gamma\) permite ao Brasil uma diferença temática persistente adicional à dos doadores. Para todos os doadores, entretanto, a equação não permite diferenças arbitrárias próprias entre os dois domínios. Isso é uma restrição da parte sistemática da regressão; não significa que seus votos observados sejam iguais.

A extensão mais direta é

\[
Y_{ir}=\mu_{i,H_r}+\lambda_r+\beta B_iP_r+\delta B_iP_rH_r+u_{ir}.
\tag{2}
\]

Para dois domínios, \(\mu_{i,H_r}=\alpha_i+\eta_iH_r\). Assim, cada país recebe seu próprio contraste temático fixo \(\eta_i\). O termo Brasil × domínio já está contido nesses efeitos fixos e deve sair da parte explícita da fórmula por redundância. A equação (2) continua permitindo uma mudança brasileira comum aos domínios, \(\beta\), e uma mudança adicional em direitos humanos, \(\delta\). Ela acrescenta flexibilidade aos níveis temáticos dos doadores, sem absorver automaticamente tendências próprias de cada país e domínio.

**Por que os efeitos fixos de resolução não bastam?** Uma resolução tem um único período e um único domínio. Portanto, \(\lambda_r\) absorve \(P_r\), \(H_r\), \(P_rH_r\), efeitos de ano e qualquer componente aditivo comum aos países naquela votação. Já \(\eta_iH_r\) varia entre países que votam na mesma resolução: um doador pode manter posição especialmente próxima à China em direitos humanos e outro não. Um único intercepto da resolução não absorve simultaneamente essas diferenças. Por outro lado, seria incorreto ignorar \(\lambda_r\) e atribuir todo movimento de médias brutas à regressão: ela já ajusta a composição comum das resoluções observadas, dentro do suporte disponível.

## 3. Como a composição dos doadores pode produzir movimento aparente

Considere um exemplo didático, sem relação quantitativa com os dados do paper. Em direitos humanos, o doador A mantém resultado −1 e o doador B mantém +1 em ambos os períodos. Nos demais votos, ambos mantêm zero. O Brasil mantém zero em todos os grupos. Antes de 2009, A representa 75% dos votos observados dos doadores em direitos humanos; depois, representa 25%.

A média dos doadores nesse domínio passa de \(0{,}75(-1)+0{,}25(1)=-0{,}5\) para \(0{,}25(-1)+0{,}75(1)=0{,}5\). A distância Brasil menos doadores passa de +0,5 para −0,5, apesar de nenhum país ter mudado sua posição dentro de um domínio. Se nada muda nos demais votos, a diferença tripla das médias brutas é −1: parece haver aproximação brasileira seletiva à China.

O exemplo explica a composição; **−1 não é uma previsão do coeficiente com efeitos fixos de resolução**. No painel real, importam quais países aparecem juntos em cada resolução e os pesos implícitos da regressão. Os 75% e 25% são participações em votos observados, não pesos SDiD. Manter a mesma lista de países nos dois períodos também não garante composição constante: eles podem contribuir com quantidades e conjuntos diferentes de resoluções.

A relação exata pode ser escrita pela residualização de Frisch–Waugh–Lovell. Seja \(x_{ir}=B_iP_rH_r\), e seja \(z\) o resíduo de projetar \(x\) nos demais termos da equação (1): país, resolução, Brasil × pós e Brasil × domínio. Então

\[
\widehat\delta=\sum_{ir}w_{ir}Y_{ir},\qquad
w_{ir}=\frac{z_{ir}}{\sum_{js}z_{js}^{2}}.
\tag{3}
\]

Se houver um componente omitido persistente \(q_{ir}=\eta_iH_r\), sua contribuição ao coeficiente será

\[
\sum_{ir}w_{ir}q_{ir}
=\sum_i\eta_i\left(\sum_{r:H_r=1}w_{ir}\right).
\tag{4}
\]

Os controles atuais impõem soma zero dos pesos dentro de cada país, somando os dois domínios. A interação Brasil × domínio impõe também soma zero no domínio de direitos humanos do Brasil. Não impõem separadamente essa última condição a cada doador. Com país × domínio, a soma dos novos pesos é zero em cada célula país–domínio, e o componente (4) desaparece, desde que o coeficiente continue identificado na amostra utilizada.

Isso também explicita quando não há contaminação por esse mecanismo: basta que a soma em (4) seja zero. Invariância a *quaisquer* valores dos contrastes temáticos exige ortogonalidade para cada doador; um painel completo com as mesmas resoluções para todos é um caso suficiente. Desbalanceamento, isoladamente, não prova viés. Na interpretação probabilística, a expressão de viés por variável omitida requer ainda um modelo para o resultado e para o erro; (4) é primeiro uma identidade sobre a contribuição de um componente dado ao coeficiente amostral.

## 4. O que os diagnósticos existentes mostram

Os arquivos abaixo ficam em `quality_reports/revisions/paper_v4/20260905_RIO_selected_fixes/independent_ddd_checks/`. Foram produzidos em 5 de setembro; **nenhuma dessas regressões foi reexecutada nesta tarefa**.

**Tabela 1. Sensibilidade arquivada da DDD a efeitos fixos adicionais, na mesma amostra de 55.190 votos, 95 países e 612 resoluções.** Resultado: distância à China menos distância aos EUA, em unidades da codificação de votos. Fonte: `sensitivity.csv:3–5`; fórmulas: `check_ddd.R:15–22`. Consulta e verificação aritmética: 14/09/2026.

| Especificação | Coeficiente DDD | EP agrupado por país |
|---|---:|---:|
| Atual: país + resolução + Brasil × domínio | −0,2223334018 | 0,0144586498 |
| País × domínio + resolução | −0,2257312276 | 0,0143361365 |
| País × domínio + país × ano + resolução | −0,2220850974 | 0,0146481171 |

A primeira extensão muda o coeficiente em −0,0033978258, cerca de 1,53% do módulo do coeficiente atual. A direção permanece negativa e a magnitude pouco muda. Esses resultados sustentam estabilidade descritiva nessa comparação; não permitem identificar “o viés verdadeiro”, nem demonstram as hipóteses causais. Os erros-padrão são condicionais ao modelo, e a extensão não elimina a limitação de um único país tratado. Não foi localizada, no pacote de sensibilidade examinado, uma distribuição de reatribuições específica para país × domínio; os ranks da especificação atual não podem ser transferidos para ela.

Há evidência mais precisa do mecanismo possível. `check_ddd.R:25–49` constrói, sobre o padrão real de observações, um resultado **sintético** que só contém diferenças temáticas fixas por doador, com magnitude máxima 1. Escolhe seus sinais a partir dos pesos da regressão. Em `donor_domain_restriction.csv:2`, a fórmula atual retorna +0,0317919036 e a fórmula país × domínio retorna zero. O teste demonstra que a fórmula atual não é invariável a todos os contrastes temáticos fixos possíveis. Como os sinais foram escolhidos adversarialmente e o resultado é sintético, +0,0318 não estima a contaminação dos votos reais, não é uma correção a subtrair de −0,2223 e não fornece limite universal para o viés empírico.

Nesta tarefa foram conferidos os resultados armazenados no RDS consumido pelo manuscrito contra a linha atual de `sensitivity.csv`; as dimensões, chaves e campos essenciais da amostra arquivada; a diferença aritmética entre coeficientes; e as identidades já registradas em `fwl.csv` e `country_domain_weights.csv`. A discrepância máxima da identidade arquivada de Frisch–Waugh–Lovell é aproximadamente \(1{,}58\times10^{-10}\). O script `domain_note_verify.R` e o log `domain_note_verification.log` permitem reproduzir essas conferências sem estimar modelos.

O gráfico de pré-tendências em `paper_v4.Rmd:1330–1341` usa médias anuais brutas por grupo e domínio, subtraindo doadores do Brasil. Ele é informativo sobre padrões descritivos, mas não residualiza país × domínio, não reproduz automaticamente os pesos da equação (3) e não testa diretamente o mecanismo de disponibilidade de votos. Esta constatação delimita seu uso para o Item 25; não propõe alterar a figura ou adjudicar outro comentário.

## 5. Alternativas para uma decisão posterior

1. **Manter a especificação e a ressalva existentes.** É uma opção sustentada pelo reconhecimento explícito da restrição e pela pequena sensibilidade arquivada. Não equivale a concluir que composição seja irrelevante em geral. Nenhuma substituição de prosa é necessária para entregar o entendimento solicitado.
2. **Levar país × domínio ao apêndice como sensibilidade, mantendo a principal.** Responde diretamente ao mecanismo do Item 25. Exige produção pelo grafo `targets`, identificação de amostra comum e inferência própria se forem reportados ranks. Os resultados antigos servem de referência para validação, não de autorização para inclusão imediata.
3. **Adotar país × domínio como principal.** Relaxa uma restrição de níveis e preserva a pergunta sobre a mudança brasileira diferencial em direitos humanos. A residualização e os pesos efetivos mudam; não se deve presumir equivalência numérica de estimandos em amostra desbalanceada ou sob heterogeneidade. É decisão do autor, acompanhada de revisão dos consumidores e das reatribuições.
4. **Acrescentar país × ano, ou restringir/ponderar a composição.** País × ano absorve movimentos anuais próprios de todos os países e torna Brasil × pós redundante; a interação tripla permanece identificável se houver suporte. Restringir a resoluções comuns ou fixar pesos de doadores aborda outra dimensão de composição, mas pode excluir muitos votos e mudar a população relevante. Ambas são extensões substantivas; nenhuma resolve automaticamente choques específicos de país, domínio e tempo ou ausência seletiva ligada ao resultado.

Para escolher entre essas opções, a informação adicional útil é a disponibilidade por país, ano e domínio, o conjunto de países observado em cada resolução, a participação de cada doador nas células e os pesos implícitos agregados por país–domínio. Convém distinguir ausência, não participação e perdas por falta de voto válido da China ou dos EUA quando os dados de origem permitirem. A existência de quatro células país × domínio × pré/pós não garante suporte comparável resolução a resolução. A amostra completa potencial precisa de denominador explícito: países elegíveis × resoluções divergentes elegíveis, antes de filtrar os votos desses países. Estes diagnósticos de composição não foram produzidos de novo aqui.

## 6. Desenho target-first exato, condicionado a autorização futura

Se o autor decidir produzir nova evidência para o paper, o desenho mínimo é uma comparação da equação (1) com a equação (2), preservando resultado, janela, codificação, doadores, resoluções e linhas. Os nomes abaixo são **propostas de targets, ainda inexistentes neste trabalho**. Funções computacionais ficariam em `scripts/functions.R`; o Rmd consumiria apenas resultados.

1. `selective_unga_domain_fe_spec`: configuração versionada com anos 2005:2012, pós a partir de 2009, partição temática atual, resultado primário `distance_china_minus_usa`, peso de entrada 1 e as duas fórmulas abaixo. Sem nova API, classificação ou imputação. Registrar versões, hashes de entrada e convenções de inferência.
2. `selective_unga_domain_fe_sample`: depender de `selective_china_alignment_unga_targets_bundle$vote_panel` e da configuração; filtrar `china_usa_divergent` e construir `human_rights_binary`, `brazil_hr` e `brazil_post_hr` como no produtor vigente. Congelar as chaves `(iso3c, rcid)` e valores usados por ambos os modelos. Validar duplicidades, ausências, domínio/período constantes por resolução, anos e codificações. A referência arquivada é 55.190/95/612; se houver divergência de entradas, interromper a comparação e explicá-la, sem forçar contagens ou regenerar os upstreams silenciosamente.
3. `selective_unga_domain_fe_support`: produzir contagens por país–ano–domínio e país–domínio–pré/pós, cobertura por resolução e participações de votos. Para medir votos ausentes, usar como dependência adicional uma grade de países e resoluções elegíveis anterior ao filtro de voto do próprio país; o painel filtrado sozinho não distingue motivos de ausência. Fixar esse denominador no código.
4. `selective_unga_domain_fe_models`: ajustar ambas as fórmulas no mesmo objeto-amostra e verificar que nenhum modelo eliminou linhas ou a interação de interesse. Formas propostas em `fixest`:

```r
# Atual
distance_china_minus_usa ~ brazil_post_2009 + brazil_hr + brazil_post_hr |
  iso3c + rcid
# Sensibilidade país × domínio
distance_china_minus_usa ~ brazil_post_2009 + brazil_post_hr |
  iso3c^human_rights_binary + rcid
```

   Usar EP agrupado por país como precisão condicional e registrar parâmetros de ajuste. Resultado secundário de acordo relativo, agrupamento também por resolução ou país × ano só entram se forem incluídos na decisão de escopo. Para país × ano, a forma exata seria `Y ~ brazil_post_hr | iso3c^human_rights_binary + iso3c^year + rcid`, sem `brazil_post_2009` redundante.
5. `selective_unga_domain_fe_weights`: residualizar a interação tripla em cada desenho, verificar \(\widehat\delta=\sum wY\), guardar somas de pesos por país–domínio e verificar que a extensão zera essas somas até tolerância numérica. Registrar pesos negativos e suporte, sem descrevê-los como pesos sintéticos. O contraexemplo já existente pode ser teste de invariância da implementação; sempre identificado como sintético, sem convertê-lo em achado substantivo.
6. `selective_unga_domain_fe_placebos`: se houver inferência por reatribuição, trocar Brasil por cada país elegível e reconstruir os termos. Na fórmula atual, reconstruir país designado × pós, × domínio e × pós × domínio; na extensão, reconstruir × pós e × pós × domínio, pois país × domínio já está absorvido para todos. Preservar mesmas linhas, efeitos fixos e peso 1. Registrar unidades válidas, falhas, empates com tolerância predefinida e denominadores. Replicar a convenção existente: cauda direcional inclusiva, fração estrita só de doadores e cauda absoluta bilateral. Não reutilizar o rank atual nem interpretar o benchmark como teste aleatorizado sem permutabilidade da atribuição.
7. `selective_unga_domain_fe_table` e `selective_unga_domain_fe_files`: gerar tabela numerada, CSV e manifesto como outputs do grafo, com fórmulas, amostra, diferenças de coeficientes e inferência correspondente. Validar a linha atual contra o RDS congelado, revisar a implementação por pessoa/agente distinto e só então, com autorização para essa fase, incorporar no Rmd e conferir o PDF. Um ajuste de pré-tendências compatível com o novo modelo precisaria de especificação própria no grafo; não seria obtido renomeando o gráfico bruto existente.

Esse desenho não foi implementado nem executado. Não autoriza alterar `_targets.R`, executar o grafo, reestimar modelos ou mudar o manuscrito.

## 7. Fechamento e limites de uso

Há um único finding, Item 25, classificado **PARTIAL**, com avaliação da solução **needs_design**. A limitação estrutural é real, já comunicada no paper, e os resultados arquivados não sustentam que ela explique a aproximação seletiva estimada. Continua sem identificação empírica o tamanho de um eventual viés causal decorrente de seleção dos votos. Nenhum texto substituto foi autorizado: `replacements` está vazio.

No esquema de adjudicação, o encaminhamento fica **BLOCKED para implementação**: a decisão sobre nova especificação e evidência permanece reservada ao autor, e não existe correção implementável definida nesta tarefa de entendimento. Isso não indica falha de integridade dos arquivos nem impede usar a explicação entregue.

Inspeção estática: passagens delimitadas do Rmd/PDF, fórmula, produtor, script de revisão e resultados arquivados. Verificação computada nesta tarefa: hashes, extração textual localizada, integridade básica da amostra armazenada e aritmética sobre outputs existentes. Nova análise empírica: nenhuma. Não foram executados ajustes, novos efeitos fixos, reatribuições, `targets`, coleta, APIs ou mudanças de dados; não houve edição de manuscrito, arquivos compartilhados, commit, sinal ou comunicação externa. Os únicos escritos desta tarefa têm o prefixo `domain_note` neste diretório. A inicialização do R avisou sobre locale e usou `C`; as conferências numéricas passaram, e os artefatos textuais foram gravados em UTF-8.
