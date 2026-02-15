# Mapa de Revisão: O Que Mudar, Onde Está a Orientação

**Para uso do autor ao editar `paper_v3.Rmd`**

---

## Legenda dos documentos-fonte

| Sigla | Arquivo | O que traz |
|-------|---------|-----------|
| **TF** | `quality_reports/2026-02-15_theory-framing.md` | Diagnóstico completo da seção teórica: problemas conceituais, mecanismos na literatura, lacunas, hipóteses sugeridas, consistência teoria↔evidência |
| **RP** | `quality_reports/2026-02-15_revision-priorities.md` | Hipóteses H1-H3 ao nível da manipulação (rank reversal) com justificativa Edmans; plano de 5 blocos para a seção teórica; backlog (placebo outcomes, FP measures alternativos) |
| **CG** | `quality_reports/2026-02-15_consolidated-revision-guide.md` | Síntese ordenada de tudo: 9 fases de implementação, tabelas de referências a adicionar, claims a moderar, o que NÃO mudar |
| **P9** | `quality_reports/plans/2026-02-10_revisao-enquadramento-teorico.md` | Plano original de 9 passos (DRAFT, pré-covariáveis). Ainda útil para detalhes sobre reorganização parágrafo a parágrafo |

---

## 1. INTRODUÇÃO (lines 70-118)

### 1a. Pergunta de pesquisa — line 74

**O que mudar**: Trocar "Should a status change..." por formulação empírica ao nível geral.

| O que está | O que deveria estar | Fonte |
|-----------|-------------------|-------|
| "Should a status change induced by discrete rank reversals..." | "Do discrete rank reversals in trade hierarchies — particularly when a rising power displaces the hegemon — produce foreign policy realignment beyond what continuous trade growth predicts, and if so, through what informational channels?" | TF §1; CG §II |

**Por que**: "Should" é normativo; mecanismo ausente da pergunta; precisa ser compreensível sem mencionar Brasil.

### 1b. Framing epistêmico — após line 108

**O que mudar**: Adicionar 2-3 frases explicitando o structured hybrid.

| O que falta | O que adicionar | Fonte |
|------------|----------------|-------|
| Paper oscila entre "testar" e "gerar" sem demarcar | "We follow a structured hybrid approach: the reduced-form prediction (rank reversal -> alignment) is *tested* in Brazil (SDiD) and cross-country (DiD). The salience mechanism is *proposed and probed* using the Brazilian case and NLP media evidence." | TF §2; CG §I |

**Onde inserir**: Logo após "Most-likely cases are well-suited for theory generation..." (line 108).

### 1c. Claim principal — line 116

**O que mudar**: Moderar "first causal evidence that status change... produces..."

| Atual | Sugerido | Fonte |
|-------|---------|-------|
| "the first causal evidence that status change induced by trade rank reversals... produces measurable foreign policy realignment" | "the first causal evidence that trade rank reversals produce foreign policy realignment, with suggestive evidence that a media-salience mechanism contributes to this effect" | TF §6; CG §VII |

### 1d. Roadmap — line 118

**O que mudar**: Atualizar para refletir nova estrutura da Seção 2 (se houver subseções novas como "Hypotheses").

---

## 2. SEÇÃO TEÓRICA: "Trade, Status and Political Alignment" (lines 120-151)

**Esta é a mudança mais importante.** A seção inteira precisa ser reestruturada.

### Estrutura atual (problemática)

| Lines | Conteúdo atual | Problema |
|-------|---------------|----------|
| 122 | Lit review por mecanismo (coerção, interesses, soft power, poder estrutural) | Argumento próprio soterrado; lê-se como survey |
| 124-126 | Estudos qualitativos + Brasil especificamente | Prematuro — caso antes da teoria |
| 128 | Causalidade reversa na literatura | OK, pode ficar |
| 130 | Crítica detalhada de Flores-Macias & Kreps | Muito longa — mover para nota de rodapé |
| 132 | Medição (Bailey et al.) | Mover para Data and Variables |
| 134-136 | Behavioral economics (coarse categorization, poliheuristic) | Bom material, mas aparece tarde e misturado |
| 138 | Rank effects em domestic politics | Bom, mas desconectado |
| 140-142 | Status na IR, definição, status como rank | Bom, mas aparece muito tarde |
| 145-147 | Coarse categorization aplicada ao caso | Mistura mecanismos sem distinguir |
| 149 | Scope conditions | Bom, manter essencialmente como está |

### Estrutura nova proposta (5 blocos)

#### Bloco 1: "The Gradualist Consensus" (~2 par.)
- **Conteúdo**: Material das lines 122, 124-126, 128 reorganizado
- **Ponto unificador**: Todos os mecanismos assumem que influência escala suavemente com volume de comércio
- **Frase-ponte final**: "We propose an alternative..."
- **Cortar**: Crítica longa de Flores-Macias & Kreps (line 130) → nota de rodapé. Parágrafo de medição (line 132) → mover para seção Data and Variables
- **Fontes**: RP §Priority 3, Block 1; CG §III, Block 1; P9 Passo 2

#### Bloco 2: "Why Rank Reversals Matter" (~3 par.)
- **Conteúdo**: Material das lines 138, 140-142 reorganizado + material novo
- Par. 1: Status como rank, não standing. MacDonald & Parent (2021). **NOVO**: Distinguir *trade status* (posição ordinal) de *status shock* (o evento de reversão). → TF §3a, CG §V
- Par. 2: Coarse categorization como micro-fundamento (Graeber et al., Enke). **REFINAR**: Especificar as categorias: "US = top partner" (default) → "China = top partner" (recategorização). → TF §3a
- Par. 3: Rank effects em política doméstica (Anagol & Fujiwara, Folke et al., Granzier et al.) + **NOVO**: Conectar a **punctuated equilibrium** (Baumgartner & Jones 1993, 2009) — rank reversal como "focusing event". → TF §8; CG §VI
- **Fontes**: RP §Priority 3, Block 2; CG §III, Block 2; P9 Passo 3

#### Bloco 3: "Two Claims: Attention and Policy Response" (~3 par.)
- **Este é o bloco mais novo e mais importante**
- **Claim 1 (Attention)**: Rank reversal → media salience (testável com NLP)
  - Micro-fundamento: coarse categorization
  - Amplificação: agenda-setting (Edwards & Wood), punctuated equilibrium (Baumgartner & Jones)
- **Claim 2 (Policy response)**: Media salience → alignment (NÃO identificado causalmente)
  - Canal cognitivo: poliheuristic (Mintz)
  - Canal mediático: audience costs (Fearon, Tomz) — **NOVO**
  - Canal de coordenação: focal point/Schelling — **NOVO**
- **Fechamento**: "These channels are complementary. Our design identifies the combined reduced-form effect; the NLP evidence provides suggestive evidence for Claim 1 specifically."
- **Fontes**: TF §3b (separação attention vs. policy-response); CG §III, Block 3; RP §Priority 3, Block 3

#### Bloco 4: Hipóteses (~1-1.5 pág.)
- **H1**: Rank reversal → redução discreta na distância FP, além do trade growth gradual
- **H2**: Efeito mais forte quando o deslocado é o hegemon
- **H3**: Cobertura mediática aumenta desproporcionalmente no momento da reversão
- **H4** (NOVO): Efeito atenua ao longo do tempo (salience prediz transitoriedade; structural bandwagoning prediz persistência)
- **Scope conditions** em prosa após hipóteses (5 condições)
- **Fontes**: RP §Priority 1 (formulação ao nível rank reversal + justificativa Edmans); CG §IV; TF §5 (tabela com 9 hipóteses — selecionar H1-H4)

#### Bloco 5: Explicações alternativas (~1 pág.)
- Lula, crise 2008, Olimpíadas, trade growth não-linear, **structural bandwagoning** (o mais importante — usar event study attenuation como evidência contra), reverse causality
- **Fontes**: TF §7 (tabela completa); CG §III, Block 5; P9 Passo 6

---

## 3. SEÇÃO METODOLOGIA (lines 177-248)

**Não precisa de mudanças estruturais.** Dois ajustes menores:

| Line | O que mudar | Fonte |
|------|-----------|-------|
| ~249 (Data and Variables) | Receber o parágrafo de medição (Bailey et al.) que saiu da Seção 2 (line 132) | RP §Priority 3, Block 1 |
| ~241-246 (Identification) | Considerar adicionar breve menção à exogeneidade do rank reversal como scope condition teórica (não apenas empírica) | TF §4 |

---

## 4. RESULTADOS EMPÍRICOS (lines 359-374)

**Não precisa de mudanças.** Números são auto-atualizados via `tar_read()`.

---

## 5. ROBUSTNESS (lines 376-433)

**Não precisa de mudanças estruturais.** Já inclui placebos, baseline sem covariáveis institucionais, e discussão de trade growth.

---

## 6. SALIENCE IN THE MEDIA (lines 435-505)

**Ajuste de linguagem**: Garantir que toda a seção use linguagem de "Claim 1" (attention claim), não de mecanismo causal completo.

| Atual | Sugerido | Fonte |
|-------|---------|-------|
| Qualquer linguagem que sugira que a evidência de mídia prova o mecanismo completo | Usar consistentemente: "consistent with", "suggestive of", "supports the attention claim" | TF §6, claim 2 |

---

## 7. CROSS-COUNTRY (lines 506-717)

### 7a. Spec 1 vs. Spec 2 — expandir discussão

**O que mudar**: Dedicar mais espaço à comparação Spec 1 (null) vs. Spec 2 (significant). Atualmente recebe apenas um parágrafo.

| O que falta | O que adicionar | Fonte |
|------------|----------------|-------|
| Discussão de por que Spec 1 é nulo | Discutir: heterogeneidade entre tipos de parceiros deslocados; H2 prevê que apenas hegemon displacement produz efeito grande | TF §6, claim 3; CG §IV, H2 |

### 7b. Dynamic event study — lines 707-717

**O que mudar**: Promover a atenuação como evidência discriminatória central.

| Atual | O que reforçar | Fonte |
|-------|---------------|-------|
| Já discute atenuação e transitoriedade (bom!) | Adicionar argumento explícito: "This attenuation pattern discriminates between the salience mechanism (which predicts transience) and structural bandwagoning (which predicts persistence)." Conectar a H4. | TF §6 (underexploited evidence); CG §IV, H4; CG §IX, item 8 |

---

## 8. CONCLUSÃO (lines 719-731)

### 8a. Moderar claim sobre Mercer — line 725

| Atual | Sugerido | Fonte |
|-------|---------|-------|
| "contrary to @mercer_2017, who argued that prestige is illusory, we have shown that it matters" | "we challenge the claim that status gains are *behaviorally* inconsequential: even if perceptual complexities exist, trade rank reversals produce measurable alignment shifts" | TF §6, claim 7; CG §VII |

**Por que**: Mercer argumenta sobre *percepção* de prestígio; o paper mostra *consequências comportamentais* de status. São coisas diferentes.

### 8b. Considerar adicionar implicações teóricas (~2 par.)

| O que falta | O que adicionar | Fonte |
|------------|----------------|-------|
| Conclusão curta e pouco ambiciosa | (1) Status como rank discreto, não standing contínuo; (2) Implicações para economic statecraft — marcos simbólicos importam; (3) Conexão com punctuated equilibrium | P9 Passo 8; CG §III, Block 2 |

---

## 9. ABSTRACT (line 19)

**O que mudar**: Alinhar com as mudanças acima.

| Aspecto | Ajuste | Fonte |
|---------|--------|-------|
| "We test this claim in Brazil" | Substituir por linguagem hybrid: "We initially probe this claim..." ou "We develop and probe this theory through..." | TF §2 |
| "first causal evidence that status change... produces" | Mesma moderação da line 116 | CG §VII |

---

## 10. BIBLIOGRAFIA (.bib)

### Referências a adicionar

| Referência | Prioridade | Para onde no texto | Fonte |
|-----------|-----------|-------------------|-------|
| Baumgartner & Jones (1993, 2009) — Punctuated equilibrium | **ALTA** | Bloco 2 (par. 3) + Bloco 3 (Claim 1) | TF §8; CG §VI |
| Bordalo, Gennaioli & Shleifer (2022) — Salience theory | MÉDIA | Bloco 2 (par. 2), ao lado de Graeber et al. | TF §8 |
| Fearon (1994); Tomz (2007) — Audience costs | MÉDIA | Bloco 3 (Claim 2, canal mediático) | TF §8; CG §VI |
| Steinert & Weyrauch (2024) — BRI e UNGA | BAIXA | Cross-country discussion ou conclusão | TF §8 |
| "Power of recognition" (Int'l Affairs, 2025) | BAIXA | Conclusão, contra Mercer | TF §8 |

### Referências que podem ser cortadas/reduzidas

O paper tem 36 entradas não citadas no .bib (ver `/validate-bib` de 2026-02-15). Limpar entradas órfãs.

---

## 11. O QUE NÃO MUDAR

| Seção | Por que manter |
|-------|---------------|
| Design empírico (SDiD, cross-country DiD) | Forte, todos os diagnósticos concordam |
| Scope conditions (lines 149-150) | Bem especificadas e derivadas logicamente |
| NLP analysis | Apropriada para probing; não tentar torná-la causal |
| Spec 1 vs. Spec 2 comparison | Teste teórico genuíno |
| Hedging epistêmico (Section 2.3, lines 241-246) | Exemplar |
| Institutional covariates | Recém integrados, pipeline rodando |
| Placebo tests e robustness table | Completos |

---

## Ordem sugerida de edição

1. **Bloco 4** (Hipóteses) — escrever primeiro porque determina a estrutura
2. **Bloco 3** (Dois claims) — o bloco mais novo
3. **Bloco 2** (Por que rank importa) — fundamentação
4. **Bloco 1** (Consenso gradualista) — reorganização de material existente
5. **Bloco 5** (Explicações alternativas)
6. Pergunta de pesquisa (line 74)
7. Framing epistêmico (após line 108)
8. Cross-country: event study attenuation + Spec 1 vs 2
9. Conclusão
10. Abstract
11. Bibliografia
