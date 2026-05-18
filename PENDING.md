# Pendências do Projeto

## Alta Prioridade

### 2026-05-12 — Harmonizar contagens cross-country no manuscrito

**Status**: Aberta — origem diagnosticada em `CROSS_COUNTRY_COUNTS_AUDIT.md`
**Escopo**: `paper_v4.Rmd`, `paper_v4_anonymous.Rmd`, abstract/introdução e materiais derivados
**Prioridade**: ALTA

Há uma inconsistência entre o resumo narrativo do paper e os resultados atuais da análise cross-country:

- O abstract de `paper_v4.Rmd` afirma que **4 de 8 países tratados** têm reversões de tratamento.
- A seção de resultados renderizada e os `targets` atuais indicam **59 países tratados**, dos quais **52 são switching** e **7 são absorbing**.
- A apresentação `presentations/paper_v4_beamer_90.Rmd` usa os números dos resultados atuais: **99 países no painel, 59 tratados, 52 switching, 7 absorbing**.

**Auditoria de origem (2026-05-13)**:

- O número **8 tratados / 4 switching** pertence ao objeto C&S/diagnóstico `event_study_data_usa`: 67 países, 8 tratados e 59 controles.
- O target principal atual `switching_panel` usa outra amostra e outra regra operacional: 99 países e tratamento quando China rankeia acima dos EUA (`rank_CHN < rank_USA`), não necessariamente quando China é o destino #1.
- Pente fino textual (2026-05-13): paper, slides e guia matemático **não documentam claramente** essa regra; quase todas as definições dizem que China é o destino #1/top partner.
- A divergência é material: 264 de 544 país-anos tratados têm `rank_CHN > 1`, e 27 dos 59 países tratados nunca têm China como #1 nos anos tratados.
- Teste ad hoc sem alterar targets (2026-05-13): usando a regra textual `rank_CHN == 1` na mesma amostra país-ano do `switching_panel`, o `fect` IFE muda de ATT = -0.074, SE = 0.029, p = 0.011 para ATT = -0.056, SE = 0.032, p = 0.083.
- A inconsistência entrou quando o diagnóstico C&S foi usado para motivar o `fect`, mas o target integrado ao pipeline passou a usar `classified_events ∪ usa_top_countries`.
- Antes de reescrever abstract e seções, é preciso decidir o estimando principal: USA-displacement restrito, China-outranks-USA, ou China-#1 amplo.

**Ação necessária**:

1. Decidir qual estimando cross-country será principal.
2. Se o estimando for **USA-displacement restrito**, ajustar `build_switching_panel(...)` e recomputar `fect`.
3. Se o estimando for **China-outranks-USA**, manter o código, mas reescrever `paper_v4.Rmd`, `paper_v4_anonymous.Rmd`, slides e captions para abandonar a linguagem "China é #1".
4. Recompilar os PDFs afetados.
5. Conferir slides, replication README e materiais de submissão para garantir que todos usem a mesma definição.

**Critério de resolução**: abstract, desenho cross-country, resultados, tabelas e slides devem reportar a mesma contagem de países tratados, switching e absorbing.
