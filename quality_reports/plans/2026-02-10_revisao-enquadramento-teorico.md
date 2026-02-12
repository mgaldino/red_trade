# Plano: Revisão do Enquadramento Teórico do Paper

**Status**: DRAFT
**Data**: 2026-02-10

## Contexto

Os pareceristas (simulados) identificaram como problema central que a teoria do paper está subdesenvolvida: a pergunta é formulada no nível do caso (Brasil), não da teoria geral; o mecanismo causal ("saliência") é ambíguo; scope conditions estão ausentes; e a literatura de status em RI é engajada de forma incompleta. Este plano decompõe a revisão teórica em 9 passos pequenos e sequenciais.

## Diagnóstico: o que está errado hoje

A Seção 2 atual ("Trade and Political Alignment") funciona como uma **revisão de literatura** organizada por mecanismo (coerção, interesses, pressão societária, poder estrutural), seguida de blocos separados sobre behavioral economics (coarse categorization) e status em RI. Os problemas:

1. Não há uma **pergunta teórica geral** — a pergunta é sobre o Brasil
2. Os mecanismos (cognitivo, mediático, estratégico) são **misturados** sem distinção
3. Não há **hipóteses derivadas** logicamente do argumento
4. Não há **scope conditions** (quando o argumento se aplica)
5. O caso brasileiro não é **posicionado** como teste de uma teoria geral
6. **Explicações alternativas** (Lula, crise 2008, dual hegemony) não são endereçadas
7. A **literatura de status** é citada mas não integrada ao argumento

## Arquivos a modificar

- `red_trade/paper_status_trade_submission.Rmd` — versão de submissão
- `red_trade/paper_v3.Rmd` — versão do autor (mesmas mudanças)
- `red_trade/synth-trade-china.bib` — referências adicionais

## Os 9 Passos

---

### Passo 1: Reformular a pergunta de pesquisa (Introdução, §1)

**O que mudar**: Os parágrafos 3-4 da introdução (linhas 61-65 do submission Rmd) formulam a pergunta no nível do Brasil. Reformular no nível geral.

**De**: "We hypothesize that a symbolic status change by an emerging power leads a country like Brazil to align its foreign policy more closely with that power."

**Para** (algo como): "We ask: do discrete rank reversals in trade hierarchies — moments when an emerging power overtakes an established partner — produce measurable shifts in foreign policy alignment? We argue that they do, through a rank-salience mechanism, and we test this proposition using Brazil's case and a cross-country design."

**Regra**: A pergunta deve ser compreensível sem mencionar Brasil. O Brasil aparece como *caso teste*, não como *objeto da pergunta*.

---

### Passo 2: Reorganizar a Seção 2 — bloco 1: "O consenso gradualista" (~3 parágrafos)

**O que fazer**: Manter o material existente sobre mecanismos da literatura (coerção, interesses, pressão societária, poder estrutural), mas reorganizá-lo em torno de uma **única observação unificadora**: todos esses mecanismos assumem que a influência escala suavemente com o volume de comércio. Nenhum distingue um momento particular de outro.

**Estrutura proposta**:
- Parágrafo 1: Quatro mecanismos da literatura (coerção, interesses, soft power, poder estrutural). Usar o material existente das linhas 71-75.
- Parágrafo 2: Causalidade reversa e endogeneidade. Usar material das linhas 76-80.
- Parágrafo 3: Frase-ponte — "What these perspectives share is the assumption that influence scales smoothly... We propose an alternative."

**Material a cortar**: O parágrafo sobre medição (Bailey et al., linha 81) pode ir para a seção de metodologia. A crítica detalhada de Flores-Macías & Kreps (linhas 79-80) pode ser encurtada.

---

### Passo 3: Reorganizar a Seção 2 — bloco 2: "Por que reversões de rank importam" (~3 parágrafos)

**O que fazer**: Construir o argumento teórico de que mudanças *discretas* de posição (rank reversals) produzem efeitos desproporcionais em comparação com mudanças graduais. Isso já está parcialmente no paper mas espalhado — consolidar.

**Estrutura proposta**:
- Parágrafo 1: **Status como conceito qualitativo, não contínuo.** Usar o material da linha 89 (MacDonald & Parent, tensão standing/membership). Aqui engajar mais profundamente: citar Ward (2017) sobre como SIT foi mal traduzida para RI; Renshon (2017) sobre quando status concerns são salientes. Fazer a distinção entre *standing* (contínuo) e *rank* (ordinal/categórico), e argumentar que o paper adota a segunda perspectiva.
- Parágrafo 2: **Coarse categorization como micro-fundamento.** Usar material existente (Graeber et al. 2025, Enke 2024). A ideia: atores usam categorias grossas ("maior parceiro" vs. "segundo maior") porque são cognitivamente mais baratas. Rankings são categorias grossas naturais. Adicionar Kelley & Simmons (2019) sobre como rankings globais moldam comportamento estatal.
- Parágrafo 3: **Rank effects na política.** Usar material existente sobre Anagol & Fujiwara (2016), Folke et al. (2016), Granzier et al. (2023). Frase-ponte: "We extend this logic from domestic to international politics."

---

### Passo 4: Reorganizar a Seção 2 — bloco 3: "Três canais de rank-saliência" (~3 parágrafos)

**O que fazer**: Este é o passo mais importante. Atualmente o paper mistura os canais. Separar explicitamente em três, mostrando como são **complementares** (não concorrentes):

- **Canal cognitivo** (~1 parágrafo): Tomadores de decisão usam coarse categories. O rank reversal entra no "consideration set" de policymakers (poliheuristic theory, Mintz 2004; Enke 2024). Efeito direto sobre decisores.

- **Canal mediático** (~1 parágrafo): Mídia amplifica o marco porque é "newsworthy" (um ranking mudou). A cobertura desproporcional muda a agenda pública (Edwards & Wood 1999; Soroka 2003; Baum & Potter 2008). Efeito indireto: rank reversal → mídia → opinião pública/elites → policy.

- **Canal de coordenação política** (~1 parágrafo): O rank reversal serve como **ponto focal** para lobbies, empresários e burocratas que já tinham interesses convergentes mas careciam de um "momento" para coordenar pressão. Similar ao bandwagon effect de Granzier et al. (2023). Efeito: rank reversal → coordenação de interesses → policy.

**Parágrafo de fechamento**: "These channels are complementary rather than competing. Our empirical strategy identifies the combined effect of the rank reversal, while the media analysis provides suggestive evidence on the amplification channel specifically."

**Por que isso importa**: Resolve o problema do P1 sobre ambiguidade do mecanismo. Também prepara o terreno para admitir honestamente (na seção de mídia e na conclusão) que não podemos separar os canais empiricamente — mas a teoria os distingue.

---

### Passo 5: Derivar hipóteses e scope conditions (~2 parágrafos)

**O que fazer**: Adicionar uma subseção ou parágrafos claros com hipóteses numeradas e scope conditions explícitas. Atualmente o paper não tem hipóteses formais.

**Hipóteses propostas**:

- **H1 (efeito principal)**: Um rank reversal — quando uma potência emergente se torna o principal parceiro comercial, deslocando o incumbente — produz uma redução discreta na distância de política externa em relação à potência emergente, além do que seria esperado pela tendência gradual de comércio.

- **H2 (scope condition — quem é deslocado)**: O efeito é mais forte quando o parceiro deslocado é o hegemon (EUA), porque o significado simbólico é maior e a saliência mediática é amplificada.

- **H3 (evidência de mecanismo — mídia)**: A cobertura mediática sobre a relação comercial bilateral aumenta desproporcionalmente no momento do rank reversal, em comparação com anos de crescimento comercial similar sem mudança de rank.

**Scope conditions explícitas** (em prosa, não como hipóteses):
- O argumento se aplica quando há **imprensa livre** para amplificar o marco (canal mediático depende disso)
- O efeito deve ser maior quando a **relação anterior com o deslocado era longa e estável** (mais saliente a mudança)
- Não se espera efeito quando o deslocado é um **parceiro pequeno ou irrelevante** (China ultrapassar Bélgica não é saliente)

**Por que isso importa**: Resolve o problema das scope conditions e prepara teoricamente a restrição amostral do cross-country DiD (displaced USA) como **predição ex ante**, não como fishing.

---

### Passo 6: Endereçar explicações alternativas (~2 parágrafos)

**O que fazer**: Adicionar parágrafos (no final da seção teórica ou como subseção) discutindo explicações alternativas e por que o design pode distingui-las:

1. **Crescimento gradual do comércio**: Se o efeito fosse apenas volume, esperaríamos uma tendência suave, não uma quebra em 2009. Os placebos em anos com crescimento similar mas sem rank change testam isso.

2. **Presidência Lula / ideologia**: Lula assumiu em 2003, muito antes do tratamento (2009). A "política externa ativa e altiva" é anterior. O modelo inclui ideologia do chefe de governo (hog_left) como controle. Além disso, Bolsonaro (ideologia oposta) manteve Brasil mais próximo da China que dos EUA na UNGA.

3. **Crise de 2008**: Incluímos Current Account e déficit fiscal como controles. A crise afetou todos os países, não apenas o Brasil — o SDiD controla por choques comuns via time weights.

4. **Dual hegemony / poder estrutural** (Schenoni & Leiva 2021): Este argumento prevê um processo gradual de atração gravitacional, não um efeito discreto em 2009. Se fosse apenas dual hegemony, os placebos temporais também mostrariam efeitos.

---

### Passo 7: Posicionar o Brasil como caso teste (~1 parágrafo na intro)

**O que fazer**: Adicionar ou reescrever um parágrafo na introdução (após a pergunta geral, antes da descrição do método) que explique por que o Brasil é um caso **especialmente adequado** para testar a teoria:

- Relação de 8 décadas com os EUA como parceiro #1 → rank reversal é maximamente saliente
- Imprensa livre → canal mediático pode operar
- Potência regional, não estado pequeno → descarta coerção como mecanismo
- Timing claro (2009) → permite design causal crível

E ser explícito: "Brazil is not the question — it is the case through which we test a general proposition about rank-salience effects."

---

### Passo 8: Atualizar a Conclusão com implicações teóricas (~2 parágrafos)

**O que fazer**: A conclusão atual é curta e pouco ambiciosa. Expandir com:

- O que aprendemos **além do caso brasileiro**: status gains *produzem* realinhamento (contra Mercer 2017). Isso conecta a literatura de status (focada em conflito e status-seeking) com a de economic statecraft.
- **Implicações para a teoria de status**: MacDonald & Parent (2021) argumentam que a definição consensual esconde tensão entre standing e membership. Nossos resultados mostram que é o *rank* (discreto, qualitativo) que produz efeitos, não o standing (contínuo). Isso sugere que a agenda de status deveria focar mais em *thresholds* e menos em *gradients*.
- **Implicações para economic statecraft**: A literatura assume influência suave via volume. Nossos resultados sugerem que marcos simbólicos importam independentemente — implicação para FDI, aid, loans.

---

### Passo 9: Adicionar referências faltantes ao .bib

**Referências a adicionar** (citadas mas não no .bib):
- Ward (2017) — já está no .bib mas não citado no texto; passar a citar
- Larson & Shevchenko (2019), *Quest for Status*
- Kelley & Simmons (2019), "Power of Global Performance Indicators", *IO*
- Soroka (2003) — já está no .bib mas não citado; passar a citar
- Baum & Potter (2008) — já está no .bib mas não citado; passar a citar
- Schenoni et al. (2022), "Myths of Multipolarity" — já está no .bib mas não citado; engajar como alternativa

---

## Ordem de execução recomendada

A ordem que minimiza retrabalho:

1. **Passo 5** (hipóteses e scope conditions) — escrever primeiro porque determina a estrutura do resto
2. **Passo 4** (três canais) — o bloco teórico mais novo e mais importante
3. **Passo 3** (por que rank importa) — fundamentação
4. **Passo 2** (consenso gradualista) — reorganização do material existente
5. **Passo 6** (explicações alternativas)
6. **Passo 1** (pergunta na intro) — agora que a teoria está clara, reformular a pergunta
7. **Passo 7** (Brasil como caso teste)
8. **Passo 8** (conclusão)
9. **Passo 9** (referências)

## O que NÃO mudar

- Seção de Metodologia (SDiD) — não é foco desta revisão
- Seção de Resultados Empíricos
- Seção de Robustez (será endereçada em plano separado)
- Seção Cross-Country (recém adicionada)
- Seção de Mídia (claims serão moderadas, mas a análise em si não muda)
- Appendix

## Verificação

1. A Seção 2 revisada tem subseções claras: consenso gradualista → por que rank importa → canais → hipóteses/scope conditions → alternativas
2. Há pelo menos 3 hipóteses numeradas derivadas do argumento
3. Scope conditions são explícitas e a restrição amostral do cross-country DiD (displaced USA) segue diretamente de H2
4. Explicações alternativas são discutidas e distinguidas do argumento principal
5. A introdução formula a pergunta no nível geral, não no nível do Brasil
6. A conclusão articula implicações além do caso
7. Ambos os .Rmd compilam sem erros
