# Devil's Advocate Report

## Veredito

**Nota: A para workflow diagnóstico preliminar.**

A operacionalização revisada não elimina todos os problemas conceituais, mas agora os reconhece, mede e limita corretamente a interpretação. Para um diagnóstico preliminar de heterogeneidade pré-tratamento, a versão final é aceitável: ela não vende a dummy de incumbente como prova de saliência política forte, não usa variáveis LPV contaminadas por pós-tratamento, e adiciona diagnósticos concretos de margem, persistência, hub/entrepôt e validade conceitual de potência regional.

As críticas residuais **não impedem nota A neste critério**. Elas impediriam nota A se o objetivo fosse incorporação causal definitiva no paper sem novos testes.

## Vulnerabilidade principal

A maior vulnerabilidade continua sendo que `displaced_partner = top_export_destination_{t0-1}` é uma fronteira de ranking comercial, não uma medida direta de saliência política. A revisão resolve isso de forma adequada para diagnóstico ao incluir share, margem, persistência prévia, incumbente modal e flags de hub. O ponto fraco passa a ser interpretativo, não mais operacional.

## Avaliação por dimensão

### 1. Incumbente deslocado

A revisão endereça a crítica central. O log agora mostra que o CSV inclui:

- share do incumbente em `t0 - 1`;
- share da China em `t0 - 1`;
- margem incumbente-China;
- persistência do incumbente nos cinco anos anteriores;
- incumbente modal pré-entrada;
- flag de hub/entrepôt;
- classificação de aviso de saliência.

Isso é exatamente o tipo de auditoria necessária para impedir que um ranking anual frágil seja tratado como saliência substantiva robusta.

**Crítica residual:** 25 de 59 casos não têm warning, mas 34 têm algum tipo de aviso: 9 hubs/entrepôts, 17 margens estreitas, 8 baixa persistência. Isso é substantivamente importante. O diagnóstico pode prosseguir, mas qualquer tabela precisa mostrar a composição dos grupos por warning.

**Impacto na nota:** não impede A para diagnóstico, desde que os warnings sejam reportados junto aos modelos.

### 2. Variáveis Liu, Pang & Vreeland

A decisão final é correta. A operacionalização:

- não usa `swap_dummy`, `signdate` ou BSA como moderadores;
- não usa `ever BRI`;
- usa `partner_level_lag1` apenas como robustez/descritivo;
- restringe BRI a `bri_mou_year < t0`;
- reconhece baixa variação de BRI pré-entrada.

Isso neutraliza o principal risco de pós-tratamento vindo dos dados LPV.

**Crítica residual:** `pre_entry_partner_level` ainda pode capturar proximidade política prévia com a China, isto é, seleção para entrada comercial e para mudança diplomática. Mas a versão final já diz que isso é robustez/descritivo, não moderador principal.

**Impacto na nota:** não impede A.

### 3. Post-treatment bias

A construção é temporalmente conservadora. O incumbente é medido em `t0 - 1`; `partner_level_lag1` na linha `year == t0` equivale a `t0 - 1`; BRI exige `bri_mou_year < t0`; assinaturas em `t0` não entram como pré-tratamento.

**Crítica residual:** permanece o risco de antecipação ou de trajetória prévia: a China pode já estar crescendo antes de `t0`, e o estado em `t0 - 1` pode refletir uma transição em andamento. Mas isso é um problema de interpretação de heterogeneidade, não uma falha mecânica de pós-tratamento.

**Impacto na nota:** não impede A para diagnóstico; exigiria event studies/leads antes de claim causal.

### 4. Potência regional

A versão final melhora bastante. Ela preserva a lista pré-especificada, mas agora reconhece que `displaced_regional_power` mistura potências globais, G7, polos regionais e grandes potências externas. Também eleva `displaced_regional_power_same_macroregion` a diagnóstico central de validade conceitual.

**Crítica residual:** a lista segue substantivamente heterogênea. `USA`, `JPN`, `KOR`, `AUS`, `RUS`, `IND` e `ZAF` não têm o mesmo significado político quando deslocados. Além disso, só 13 casos têm potência regional na mesma macrorregião, então a versão conceitualmente mais limpa terá pouca alavancagem empírica.

**Impacto na nota:** não impede A para diagnóstico porque a limitação está registrada e operacionalmente auditável. Impediria A se a dummy ampla fosse apresentada isoladamente como teste substantivo forte de "poder regional".

### 5. Modelos com interações

A versão final usa a linguagem correta: modelos com 500 bootstraps como diagnóstico preliminar, não nova identificação causal independente. Também exige contagens por célula e avisos de saliência.

**Crítica residual:** grupos pequenos continuam sendo um problema real: `displaced_us = 12`, `same_macroregion = 13`, `pre_entry_high_level_partner = 12`, `pre_entry_bri_mou = 10`. Interações podem ser muito sensíveis a poucos países.

**Impacto na nota:** não impede A para workflow diagnóstico, desde que o relatório não use significância isolada como evidência forte. Para paper, ainda precisaria de event studies por subgrupo, leads e leave-one-country-out.

## Ranking das vulnerabilidades residuais

1. **Grande fração de casos com warning de saliência** -- precisa aparecer na interpretação dos resultados.
2. **`displaced_regional_power` é ampla e heterogênea** -- só é aceitável se acompanhada de decomposição e `same_macroregion`.
3. **Células pequenas em interações** -- inferência deve ser exploratória.
4. **Possível antecipação/pré-tendência antes de `t0`** -- exige event studies antes de incorporação causal.
5. **`partner_level_lag1` mede proximidade com a China** -- adequado como robustez, não como moderador principal.

## O que sobrevive

A operacionalização revisada é reproduzível, pré-tratamento, documentada e honesta sobre seus limites. A revisão transformou a proposta de uma operacionalização potencialmente overclaimed em um desenho diagnóstico bem calibrado. O ponto mais forte é que as fragilidades não foram escondidas: viraram variáveis de auditoria.

## Condições para manter a nota A

Para preservar A no relatório diagnóstico, três condições são indispensáveis:

1. Reportar sempre contagens por grupo e por warning de saliência.
2. Nunca interpretar `displaced_regional_power` isoladamente como poder regional forte.
3. Apresentar resultados de interação como heterogeneidade exploratória pré-tratamento, não como evidência causal definitiva.

## Para incorporação futura no paper

Antes de levar ao manuscrito como argumento substantivo, ainda seriam necessários:

- event studies por subgrupo;
- testes de leads;
- leave-one-country-out;
- especificações excluindo hubs/entrepôts;
- decomposição de potência regional por EUA, G7, mesma macrorregião e grandes potências externas;
- checagem de robustez usando incumbente modal ou persistente no pré-período.

**Conclusão:** para o objetivo declarado, as críticas residuais podem ficar como limitações registradas. Elas não bloqueiam nota A.
