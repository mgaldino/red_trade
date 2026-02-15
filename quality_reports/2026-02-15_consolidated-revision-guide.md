# Consolidated Revision Guide: Theory Overhaul

**Date**: 2026-02-15
**Sources synthesized**:
1. Edmans editorial review (Contribution 5/10, Execution 7.5/10, Exposition 6/10) — R&R major
2. Revision priorities document (`2026-02-15_revision-priorities.md`)
3. Theory framing diagnosis (`2026-02-15_theory-framing.md`)

**Bottom line**: The empirical execution is the paper's strength. The bottleneck is theory: underspecified mechanism, missing hypotheses, literature gaps, and epistemic ambiguity. This guide consolidates all recommendations into a single ordered plan.

---

## I. Epistemic Framing (do first — everything else depends on this)

### Problem

The paper oscillates between theory generation and theory testing without clearly demarcating which claims fall into which category. The abstract says "we test this claim in Brazil" (testing language), but Brazil is positioned as a most-likely case (generation language). The SDiD provides causal evidence for the *reduced-form* effect, but the mechanism evidence (NLP) is correlational.

### Solution: Structured Hybrid

State explicitly in the introduction:

- **Generated/probed**: The salience mechanism (coarse categorization -> media attention -> elite consideration sets -> alignment) is *proposed and probed* using the Brazilian case + NLP evidence.
- **Tested**: The reduced-form prediction (rank reversal -> alignment shift) is *tested* first in Brazil (most-likely case, SDiD) and then cross-country (staggered DiD).

**Concrete change**: Add 2-3 sentences after the "most likely case" paragraph (current line 108) making this distinction explicit. Align abstract and conclusion — "causal evidence" refers only to the reduced-form effect; mechanism claims use "suggestive" / "consistent with."

---

## II. Research Question Reformulation

### Current (line 74)
> "Should a status change induced by discrete rank reversals in trade hierarchies involving great powers cause disproportionate shifts in foreign policy alignment, beyond what gradual trade accumulation would predict?"

### Problems
1. "Should" is normative/predictive, not empirical
2. Mechanism is absent from the question
3. Oscillation between general phenomenon and Brazilian case

### Suggested reformulation
> "Do discrete rank reversals in trade hierarchies — particularly when a rising power displaces the hegemon as a country's top trade partner — produce foreign policy realignment beyond what continuous trade growth predicts, and if so, through what informational channels?"

---

## III. Theory Section Restructuring

### Current structure (Section 2, ~3.5 pages)
Literature review by mechanism (coercion, interests, soft power, structural power) -> behavioral economics (coarse categorization) -> status in IR. The paper's own argument is buried under other people's work.

### New structure (5 blocks, ~5 pages)

#### Block 1: "The Gradualist Consensus" (~2 paragraphs)

Consolidate existing material on trade-alignment mechanisms. **Unifying observation**: all assume influence scales smoothly with trade volume. No moment is distinguished.

Bridge: "We propose an alternative: that discrete rank reversals produce disproportionate effects through informational channels."

*Cut*: Shorten Flores-Macias & Kreps critique (move detail to footnote). Move Bailey et al. measurement paragraph to Data and Variables.

#### Block 2: "Why Rank Reversals Matter" (~3 paragraphs)

1. **Status as rank, not standing.** MacDonald & Parent (2021) tension. Introduce conceptual distinction:
   - *Trade status* = the ordinal rank position a trade partner holds
   - *Status shock* = the discrete event of rank reversal (the treatment)

2. **Coarse categorization as micro-foundation.** Graeber et al. (2025), Enke (2024). Specify the categories being disrupted: "US = top partner" (entrenched default) -> "China = top partner" (novel recategorization).

3. **Rank effects in politics.** Domestic evidence (Anagol & Fujiwara 2016, Folke et al. 2016, Granzier et al. 2023). **NEW**: Connect to **punctuated equilibrium theory** (Baumgartner & Jones 1993, 2009) — rank reversals as "focusing events" that disrupt incremental policy processing.

#### Block 3: "Two Claims: Attention and Policy Response" (~3 paragraphs)

**This is the key new block.** The theory-framing diagnosis identified that the paper conflates two distinct claims:

**Claim 1 — Attention claim**: Rank reversals function as focusing events that disrupt coarse cognitive categories and produce a disproportionate media-salience shock.
- Micro-foundation: coarse categorization (Graeber et al.)
- Amplification: agenda-setting (Edwards & Wood 1999)
- Testable with: NLP media evidence

**Claim 2 — Policy-response claim**: The media-salience shock enters elite consideration sets and shifts foreign policy alignment. Multiple downstream channels operate (and cannot be distinguished with the current design):
- *Cognitive channel*: Decision-makers directly update via poliheuristic processing (Mintz 2004)
- *Media channel*: Coverage shifts public agenda, creating audience costs for inaction (Fearon 1994; Tomz 2007)
- *Coordination channel*: Rank reversal as Schelling focal point for lobbies, business, bureaucrats who already had converging interests

Close with: "These downstream channels are complementary rather than competing. Our empirical strategy identifies the combined reduced-form effect; the media analysis provides suggestive evidence for Claim 1 specifically."

**Why this matters**: Separating the two claims (i) clarifies what the NLP evidence does and does not show, (ii) prevents overinterpretation of the causal chain, (iii) opens productive avenues for future research.

#### Block 4: Hypotheses and Scope Conditions (~1.5 pages)

See Section IV below.

#### Block 5: Alternative Explanations (~1 page)

| Alternative | How handled | Key evidence |
|------------|-------------|--------------|
| Lula presidency/ideology | Took office 2003, 6 years before treatment | Placebos at 2003/2005 null; cross-country eliminates single-leader confounders |
| 2008 financial crisis | Macro covariates (current account, budget deficit) | SDiD time weights; staggered cross-country timing |
| 2008 Beijing Olympics | Time-specific confounder | Cross-country staggered timing; Olympics affected all countries equally |
| Non-linear trade growth | Trade shares as SDiD covariates | Placebos at years with steep growth but no rank change are null; different treated countries reached reversal at different trade levels |
| Dual hegemony / structural bandwagoning | **Most important unaddressed alternative** | Use **dynamic event study attenuation** as evidence: structural bandwagoning predicts *persistent* effects, but the event study shows the effect *fades over time*, consistent with a salience/novelty mechanism |
| Reverse causality | UNGA voting unlikely to cause trade patterns | SDiD exploits sharp timing; add brief paragraph noting that UNGA positions are set at a level of abstraction far from trade decisions |

---

## IV. Hypotheses (at manipulation level — rank reversal)

### Justification for manipulation-level hypotheses

Per Edmans (2025, sec. 2.6), hypotheses must be (1) strong (convincing ex ante channel), (2) precise (about exactly what is measured), (3) directional, and (4) corresponding to what is tested. "Status" is the motivating framework; "rank reversal" is the testable manipulation. See `2026-02-15_revision-priorities.md` for full Edmans analysis.

### Core hypotheses (in paper)

| # | Hypothesis | Derivation | Test | Evidence |
|---|-----------|-----------|------|----------|
| **H1** | A rank reversal in trade hierarchies — when a rising power overtakes the incumbent as top trade partner — produces a discrete reduction in the country's foreign policy distance from the rising power, beyond gradual trade growth. | Core claim: coarse categorization -> focusing event -> disproportionate response | SDiD (Brazil) + cross-country DiD | Supported (ATT = -41%, p = 0.032; cross-country ATT = -0.11, p = 0.004) |
| **H2** | The effect of a rank reversal is stronger when the displaced partner is the global hegemon. | Scope condition: disrupting a more prominent category produces larger attention shock (Enke 2024) | Spec 1 (all events) vs. Spec 2 (US displaced) | Supported (Spec 1 null; Spec 2 significant) |
| **H3** | Media coverage of the bilateral trade relationship increases disproportionately at the moment of rank reversal. | Attention claim: focusing event -> media salience (Edwards & Wood 1999) | Folha NLP analysis | Consistent (trade-share headlines double after 2009) |

### Additional hypotheses to consider

| # | Hypothesis | Source | Testable? | Status |
|---|-----------|--------|-----------|--------|
| **H4** | The alignment effect attenuates over time as novelty fades. | Theory-framing: salience predicts transience; distinguishes from structural bandwagoning | Yes (dynamic event study) | **Already in data** — underexploited. Promote to main text. |
| **H5** | The effect is larger in countries where the US held top position longer (higher USA streak). | Scope condition 3 | Partially (covariate-adjusted DiD) | Suggestive |
| **H6** | The effect is larger in countries with higher press freedom. | Scope condition 2 | Partially (covariate-adjusted DiD) | Suggestive |
| H7 | The rank reversal does not produce alignment shifts toward the *displaced* partner (US). | Discriminant test: salience benefits rising power, not just "disruption" | Feasible (UNGA distance to US as outcome) | **Backlog** |
| H8 | The rank reversal produces a disproportionate media shift relative to years with comparable trade growth but no rank change. | Stronger NLP test | Feasible for Brazil (compare 2003-05 vs. 2009) | **Backlog** |

**Recommendation**: Include H1-H4 in the paper. H4 is critical because the attenuation pattern is the best evidence discriminating the salience mechanism from structural bandwagoning. H5-H6 can be discussed as suggestive scope-condition tests. H7-H8 are backlog.

### Scope conditions (in prose, after hypotheses)

1. **Hegemon displacement**: Effect stronger when displaced partner is the hegemon (tested via H2)
2. **Free press**: Media amplification channel requires press freedom (partially tested, H6)
3. **Entrenched prior relationship**: Longer the prior rank-1 tenure, more disruptive the reversal (partially tested, H5)
4. **Democratic accountability**: Media salience more consequential where public opinion constrains foreign policy (not directly tested — acknowledge)
5. **Exogeneity of rank reversal**: Theory predicts effects of *exogenous* status shocks, not endogenous ones (handled by design — SDiD, parallel trends)

---

## V. Conceptual Refinements

| Current term | Problem | Suggested refinement |
|-------------|---------|---------------------|
| "Status" | Does double duty: position (rank 1 vs. 2) AND transition (the reversal event) | Distinguish **trade status** (ordinal position) from **status shock** (the rank-reversal event). Treatment = status shock. |
| "Salience" | Conflates cognitive property, media output, and elite attention | Distinguish **cognitive salience** (attention-grabbing property of rank reversal), **media salience** (volume/type of coverage), **issue salience** (prominence in elite consideration sets). Chain: cognitive -> media -> issue -> policy. |
| "Coarse categorization" | Definition adequate but application underspecified | Specify: disrupted category = "US = top partner" (entrenched default); activated category = "China = top partner" (novel recategorization). |
| "Foreign policy alignment" | UNGA voting operationalization not connected to mechanism | Add brief discussion: why does media salience affect UNGA voting? Because executive/presidency directs UNGA voting positions and is responsive to media-salience cues. |

---

## VI. Literature to Add

### High priority (strengthens theoretical foundation)

| Reference | Why it matters |
|-----------|---------------|
| **Baumgartner & Jones (1993, 2009)** — Punctuated equilibrium | Directly theorizes disproportionate, threshold-driven policy change through attention shifts. The rank reversal IS a focusing event. **Most important omission.** |
| **Bordalo, Gennaioli & Shleifer (2022)** — Salience theory | More complete theoretical framework for salience effects than individual papers currently cited |

### Medium priority (strengthens positioning)

| Reference | Why it matters |
|-----------|---------------|
| **Fearon (1994); Tomz (2007); Kertzer & Brutger (2016)** — Audience costs | Provides micro-foundation for why media salience -> policy change in democracies |
| **Steinert & Weyrauch (2024)** — BRI and UNGA voting | BRI membership does NOT produce alignment; supports claim that *discrete* events matter more than gradual integration |
| **"Power of recognition" (Int'l Affairs, 2025)** | Status recognition has tangible effects — directly supports argument against Mercer |

### Low priority (useful context)

| Reference | Why it matters |
|-----------|---------------|
| Bruegel WP (2024) on China's UN influence | Context for interpreting discrete shifts |
| Arms exports and UNGA (EJPE, 2025) | Comparison: structural mechanism (arms) vs. salience mechanism (rank reversal) |

---

## VII. Claims to Moderate

| Current claim | Problem | Suggested revision |
|--------------|---------|-------------------|
| Abstract: "provides the first causal evidence that status change induced by trade rank reversals... produces measurable foreign policy realignment" | Too strong for mechanism part | "provides the first causal evidence that trade rank reversals produce foreign policy realignment, with suggestive evidence that a media-salience mechanism contributes to this effect" |
| Conclusion: "we have shown that [prestige] matters" | Mercer's argument is about *perception* of prestige, not behavioral consequences | "we challenge the claim that status gains are *behaviorally* inconsequential, even if perceptual complexities exist" |

---

## VIII. What NOT to Change

- **Empirical design**: SDiD, cross-country DiD, placebos, wild cluster bootstrap, Fisher randomization
- **Scope conditions**: Already well-specified and partially tested
- **NLP analysis**: Appropriate for probing mechanism (do not try to make it causal)
- **Spec 1 vs. Spec 2 comparison**: Genuine theoretical test — preserve as central result
- **Epistemic modesty** in Section 2.3 and Conclusion: exemplary hedging of mechanism claims
- **Cross-country DiD section**: Recently added, well-executed
- **Institutional covariates**: Just integrated, pipeline working

---

## IX. Implementation Order

### Phase 1: Theory rewrite (highest priority)
1. Adopt structured hybrid framing (Section I above)
2. Reformulate research question (Section II)
3. Restructure Section 2 into 5 blocks (Section III)
4. Refine conceptual vocabulary (Section V)
5. Write hypotheses H1-H4 at manipulation level (Section IV)

### Phase 2: Evidence exploitation
6. Promote dynamic event study attenuation (H4) as mechanism-discriminating evidence
7. Strengthen Spec 1 vs. Spec 2 discussion
8. Moderate claims in abstract and conclusion (Section VII)

### Phase 3: Literature
9. Add Baumgartner & Jones
10. Add audience costs connection
11. Add other references (Section VI)

### Phase 4: Backlog (only if reviewer asks)
- Placebo outcome tests (military spending — see `2026-02-15_revision-priorities.md`)
- Alternative FP measures (FPSIM v2, SIPRI — see `2026-02-15_revision-priorities.md`)
- H7 (distance to US as placebo outcome)
- H8 (media shift comparison across years)

---

## X. Cross-references

| Document | Content |
|----------|---------|
| `quality_reports/2026-02-15_theory-framing.md` | Full theory-framing diagnosis (306 lines) |
| `quality_reports/2026-02-15_revision-priorities.md` | Edmans-based priorities + backlog (FP measures, placebo outcomes) |
| `quality_reports/plans/2026-02-10_revisao-enquadramento-teorico.md` | Original 9-step theory plan (DRAFT) |
| `quality_reports/2026-02-10_review-paper.md` | Earlier editorial review (2 referees) |
| `quality_reports/plans/2026-02-14_sdid-covariates-institucionais.md` | SDiD covariates plan (COMPLETED) |
