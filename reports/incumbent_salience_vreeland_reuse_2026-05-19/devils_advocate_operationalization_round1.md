# Devil's Advocate Report

## Vulnerabilidade principal

A operacionalização é temporalmente cuidadosa, mas ainda não prova que o "incumbente deslocado" mede saliência política pré-tratamento. Ela mede o principal destino de exportações em `t0 - 1`; isso é pré-tratamento no calendário, mas pode ser apenas o último estado de uma transição comercial já em curso, altamente sensível a empates, hubs comerciais e volatilidade anual. O risco central não é pós-tratamento clássico; é transformar uma fronteira mecânica do ranking comercial em conceito político substantivo.

**Nota: B.** A construção é defensável como diagnóstico pré-tratamento. Ainda não é A porque a validade conceitual do incumbente e a inferência com interações precisam de stress tests fortes.

## Críticas por dimensão

### 1. Incumbente deslocado

1. **`top_export_destination_{t0-1}` pode ser um incumbente fraco, não um incumbente politicamente saliente.**
   - **Severidade: Alta.**
   - Se o parceiro em `t0 - 1` liderava por margem mínima, por apenas um ano, ou por intermediação comercial, chamá-lo de "incumbente deslocado" exagera o conteúdo político da troca.
   - **Correção necessária:** reportar margem China-incumbente em `t0 - 1`, share do incumbente, persistência do incumbente nos 3-5 anos anteriores, e codificar versões alternativas: incumbente modal pré-entrada, incumbente persistente, incumbente por média móvel.

2. **Hubs comerciais podem contaminar a interpretação política.**
   - **Severidade: Alta.**
   - A lista de incumbentes inclui BEL, HKG, SGP, ARE, CHE. Esses casos podem refletir entrepostos, reexportação, centros financeiros/logísticos ou composição setorial, não uma relação bilateral politicamente saliente.
   - **Correção necessária:** identificar e separar hubs/entrepôts; rodar análise excluindo ou recodificando esses casos; documentar se os fluxos são gross exports e se há risco de destino intermediário.

3. **O timing evita pós-tratamento formal, mas não evita antecipação ou pré-tendência.**
   - **Severidade: Média-Alta.**
   - Em `t0 - 1`, a China pode já estar subindo rapidamente e reorganizando relações econômicas. O "incumbente deslocado" é pré-onset, mas pode estar condicionado à própria trajetória que produz o tratamento.
   - **Correção necessária:** mostrar dinâmica dos shares nos anos `t0 - 5` a `t0 - 1`; testar se os grupos de incumbente têm tendências prévias diferentes no outcome político.

### 2. Uso das variáveis Liu, Pang & Vreeland

1. **A decisão de não usar BSA/swap como moderador principal é correta.**
   - **Severidade da ameaça evitada: Alta.**
   - `swap_dummy`, `signdate` e dados de BSA são tratamento em LPV, não moderador limpo para este desenho. Usá-los como "susceptibility" criaria confusão conceitual e temporal.

2. **`partner_level_lag1` é temporalmente admissível, mas conceitualmente perigoso.**
   - **Severidade: Média-Alta.**
   - Ele mede proximidade diplomática com a China antes de `t0`. Isso pode ser pré-tratamento, mas está perto demais do mecanismo político que o paper quer explicar. Se usado como moderador, pode virar controle/estratificação sobre uma causa intermediária ou sobre seleção política para a entrada comercial chinesa.
   - **Correção necessária:** manter como robustness/descritivo, não como variável principal; mostrar resultados com e sem; não vender como teste causal forte.

3. **`pre_entry_bri_mou` tem baixa variação e risco alto se mal codificado.**
   - **Severidade: Média.**
   - A versão estrita `bri_mou_year < t0` é correta, mas só há 10 tratados com BRI antes de `t0`. Isso é pouco para interação confiável.
   - **Correção necessária:** usar apenas como diagnóstico descritivo ou placebo negativo; evitar interpretação substantiva forte.

### 3. Risco de post-treatment bias

1. **A regra temporal está bem desenhada.**
   - **Severidade residual: Baixa-Média.**
   - `displaced_partner` em `t0 - 1`, `partner_level_lag1` na linha de `t0`, e `bri_mou_year < t0` são escolhas corretas. A exclusão de `ever BRI` é essencial.

2. **O problema residual é "bad pre-treatment control", não pós-tratamento mecânico.**
   - **Severidade: Média.**
   - Variáveis prévias podem ainda estar endogenamente ligadas à trajetória de entrada da China. Isso importa especialmente para `partner_level`: aproximação diplomática com a China pode anteceder e causar tanto o tratamento comercial quanto mudanças nos votos.
   - **Correção necessária:** enquadrar essas variáveis como heterogeneidade descritiva pré-especificada, não como ajuste causal que purifica identificação.

### 4. Dummy de potência regional

1. **A lista é defensável como ponto de partida, mas ainda arbitrária demais para carregar inferência principal.**
   - **Severidade: Alta.**
   - A variável mistura superpotência, G7, potências regionais clássicas, potências médias e polos econômicos. USA, JPN, KOR, AUS, IND e RUS entram por razões muito diferentes. O resultado pode ser uma dummy de "parceiro grande/importante" disfarçada de potência regional.
   - **Correção necessária:** separar conceitos: `global_power`, `g7/western`, `same_region_regional_power`, `non_same_region_large_power`.

2. **A versão principal ignora se a potência é regional para o país tratado.**
   - **Severidade: Alta.**
   - A coluna `same_macroregion` existe, mas é tratada como auxiliar. Se a teoria é sobre deslocar autoridade/influência regional, então deslocar uma potência fora da região do país tratado tem significado diferente.
   - **Correção necessária:** tornar `same_macroregion` uma especificação central ou, no mínimo, uma condição de validade conceitual.

3. **Sobreposição com `displaced_us` e `displaced_g7` prejudica interpretação.**
   - **Severidade: Média.**
   - A dummy de potência regional tem 38 casos, mas incorpora USA, DEU, FRA, GBR, JPN etc. Se uma interação aparece, não está claro se vem de status regional, ordem liberal, tamanho econômico ou relações com o Ocidente.
   - **Correção necessária:** reportar decomposição e modelos separados, sem exigir que uma única dummy resolva todos os mecanismos.

### 5. Inferência preliminar com interações

1. **As células são pequenas para inferência forte.**
   - **Severidade: Alta.**
   - `displaced_us = 12`, `same_macroregion = 13`, `pre_entry_high_level_partner = 12`, `pre_entry_bri_mou = 10`. Em modelos com efeitos fixos, dinâmica temporal e interações, esses grupos serão sensíveis a poucos países influentes.
   - **Correção necessária:** reportar contagens por célula, países que identificam cada interação, leave-one-country-out, e intervalos de confiança honestos.

2. **Interações em DiD/event study exigem pré-tendências por subgrupo.**
   - **Severidade: Alta.**
   - Um coeficiente de interação pós-tratamento não basta. Se países que deslocaram EUA/G7/potência regional já tinham trajetórias diferentes antes de `t0`, a interação captura seleção diferencial.
   - **Correção necessária:** event studies por moderador, testes de leads conjuntos por subgrupo, gráficos de tendências prévias e estimativas não paramétricas por tempo relativo.

3. **Não há evidência nos arquivos lidos de que os modelos de interação já tenham sido auditados.**
   - **Severidade: Média.**
   - Os documentos lidos são de operacionalização e criação de variáveis, não de inferência. Qualquer conclusão substantiva a partir de interações ainda seria prematura.
   - **Correção necessária:** separar "variável criada" de "moderador validado".

## Ranking de vulnerabilidades

1. **Incumbente deslocado pode ser ranking mecânico, não vínculo político saliente** -- ameaça diretamente a validade do moderador.
2. **Dummy de potência regional mistura categorias substantivas diferentes** -- pode gerar resultado interpretável de várias formas incompatíveis.
3. **Interações com células pequenas e possível leverage de poucos países** -- ameaça a credibilidade inferencial.
4. **Variáveis LPV são temporalmente úteis, mas conceitualmente próximas do mecanismo** -- boas para robustness, ruins como moderadores principais.
5. **Risco residual de pré-tendências/antecipação** -- menor que pós-tratamento, mas ainda relevante.

## O que sobrevive ao escrutínio

- A regra `t0 - 1` para incumbente deslocado é uma escolha temporalmente limpa.
- As validações básicas passam: sem `CHN` como incumbente, sem missing em `t0 - 1`, uma linha por tratado.
- A rejeição de `ever BRI` é correta e importante.
- O uso de `partner_level_lag1` em vez de `partner_level` contemporâneo é a versão mais defensável.
- A lista de potência regional foi pré-especificada e documentada; isso reduz garden-of-forking-paths, embora não resolva validade conceitual.

## Condições para chegar a A

1. Validar "incumbente" com medidas de saliência: share exportado, margem sobre China, persistência prévia, incumbente modal/média móvel.
2. Separar hubs comerciais e mostrar robustez excluindo BEL, HKG, SGP, ARE, CHE e casos semelhantes.
3. Reestruturar potência regional em categorias teoricamente limpas: EUA, G7/Ocidente, potência regional da mesma macrorregião, grande potência externa.
4. Tratar variáveis LPV apenas como robustness/descritivo, salvo se houver argumento claro de que são predisposições prévias e não parte do mecanismo.
5. Para interações: apresentar células, países identificadores, event studies por subgrupo, pre-trends, leave-one-out e interpretação baseada em magnitude/incerteza, não só significância.
6. Escrever explicitamente que estes moderadores testam heterogeneidade pré-tratamento, não identificação causal independente do efeito principal.
