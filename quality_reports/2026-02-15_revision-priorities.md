# Revision Priorities: Theory Strengthening + Backlog

**Date**: 2026-02-15
**Source**: Edmans editorial review (Contribution 5/10, Execution 7.5/10, Exposition 6/10)
**Decision**: R&R major — recommended IO or ISQ

---

## Priority 1: Formalize Directional, Testable Hypotheses

### Problem

The current paper lacks formal, numbered hypotheses. The theoretical argument (coarse categorization + rank salience) is present but never crystallized into testable predictions. This makes the paper read as a sophisticated empirical narrative rather than a theory-driven study. Reviewers cannot assess whether the evidence *tests* the theory or merely *illustrates* a case.

### Treatment vs. manipulation: at what level should hypotheses be?

The paper itself distinguishes (line 142): *"status is the treatment, rank is the manipulation."* Edmans (2025, sec. 2.6) does not address this distinction directly, but his criteria resolve it:

1. **Precision**: Edmans rejects hypotheses where the theoretical argument is about X→Y1 but the test measures Y2. By analogy, if the theoretical concept is "status" (broad) but the empirical test identifies "rank reversal" (specific), hypotheses about "status" are imprecise — status can change via many channels the paper does not test (e.g., Olympics, UNSC seat, G20 membership).

2. **Strength**: A "strong" hypothesis is one where the channel is convincing *ex ante*, not just plausible post-hoc. "Rank reversals produce disproportionate effects via coarse categorization" is a strong, specific claim grounded in cognitive theory. "Status gains produce alignment" is weaker — which status gains? Through which channel?

3. **Correspondence hypothesis↔test**: The SDiD identifies the effect of a rank reversal at a specific moment. The cross-country DiD identifies rank reversals across countries. Neither tests "status" in the abstract.

**Conclusion**: Hypotheses should be at the **manipulation level** (rank reversal). "Status" is the motivating theoretical framework — it explains *why* rank reversals matter — but the testable predictions are about rank reversals specifically.

### What to do

Derive 3 hypotheses from the theoretical argument, each at the manipulation level (rank reversal) and mapping to a specific empirical test already in the paper:

**H1 (Main effect):** A rank reversal in trade hierarchies — when a rising power overtakes the incumbent as a country's top trade partner — produces a discrete reduction in the country's foreign policy distance from the rising power, beyond what gradual trade growth predicts.

- *Test*: SDiD estimate at 2009 (Brazil) and cross-country staggered DiD.
- *Key distinction*: "discrete" and "beyond gradual trade growth" separate this from the gradualist literature. The placebo tests at 2003 and 2005 directly test the discreteness claim — those years had steep trade growth but no rank reversal, and the placebo effects are null.
- *Theoretical grounding*: Coarse categorization theory (Graeber et al. 2025) predicts that ordinal categories ("top partner") receive disproportionate attention relative to continuous metrics (trade share). The rank reversal is the moment the coarse category switches.

**H2 (Scope condition — hegemon displacement):** The effect of a rank reversal is stronger when the displaced partner is the global hegemon, because the symbolic significance of the reversal is amplified and media coverage is greater.

- *Test*: Cross-country DiD comparing all-countries sample (null or weak effect) vs. "displaced USA" subsample (significant effect, ATT = -0.11, p = 0.004).
- *Why this matters*: Currently the paper reports multiple cross-country specifications that look like specification searching. H2, stated *before* the results, reframes the "displaced USA" restriction as a *theoretical prediction*, not a post-hoc sample selection.
- *Theoretical grounding*: The salience of a category disruption depends on the baseline prominence of the category (Enke 2024). The US as top partner is a more prominent category than, say, Japan as top partner.

**H3 (Mechanism — media amplification):** Media coverage of the bilateral trade relationship increases disproportionately at the moment of the rank reversal, compared to years with similar trade growth but no rank change.

- *Test*: Folha de Sao Paulo headline analysis (NLP classification).
- *Honest caveat*: The paper should explicitly state that H3 provides *suggestive* evidence of one channel (media), not a causal identification of the mechanism. The SDiD identifies the *combined* effect of all channels (cognitive, media, coordination).
- *Theoretical grounding*: Agenda-setting theory (Edwards & Wood 1999) predicts that discrete, easily categorizable events attract disproportionate coverage.

### Where in the paper

Insert a subsection "Hypotheses" at the end of Section 2 (after the theoretical argument, before Methodology). Approximately 1-1.5 pages. The hypotheses should flow naturally from the preceding argument — they are logical implications of the rank-salience theory, not arbitrary predictions. The broader concept of "status" appears in the motivation (why rank matters) but the predictions are about the observable manipulation (rank reversal).

### Scope conditions (in prose, not as hypotheses)

State these explicitly after H1-H3:

1. **Free press required**: The media amplification channel (H3) presupposes press freedom. In countries with restricted press, the rank reversal may go unreported, muting the salience mechanism.
2. **Duration of prior relationship**: The longer the displaced partner held rank 1, the more entrenched the coarse category and the more disruptive the reversal. (Brazil-US: ~80 years.)
3. **Geopolitical significance of the rising power**: Displacing the US with China (a perceived strategic rival) is more salient than displacing a minor partner.

These conditions are already partially discussed in the current paper (lines 149-150) but should be consolidated and made explicit.

---

## Priority 3: Restructure Theory Section (Argument First, Literature Second)

### Problem

Section 2 ("Trade, Status and Political Alignment") is currently organized as a **literature review by mechanism** (coercion, interests, societal pressure, structural power), followed by separate blocks on behavioral economics and status in IR. This structure:

- Buries the paper's own argument under 3+ pages of other people's work
- Makes it hard to see what is *new* versus what is *known*
- Mixes cognitive, media, and strategic channels without distinguishing them
- Leads readers to ask "what is *your* theory?" after several pages

### What to do

Restructure Section 2 following the "argument first, then literature" principle from Edmans (2025). The recommended structure:

#### Block 1: "The Gradualist Consensus" (~2-3 paragraphs)

Consolidate existing material on trade-alignment mechanisms (coercion, interests, soft power, structural power) under **one unifying observation**: all assume influence scales smoothly with trade volume. No particular moment is distinguished.

Close with a bridge sentence: "What these perspectives share is the assumption that influence scales smoothly with commercial exposure. We propose an alternative: that discrete rank reversals, not gradual accumulation, produce disproportionate effects."

*Material source*: Current lines 122-131. Cut or shorten the detailed critique of Flores-Macias & Kreps (currently ~1 full paragraph) — move to a footnote if needed. Move the measurement paragraph (Bailey et al.) to Data and Variables.

#### Block 2: "Why Rank Reversals Matter" (~3 paragraphs)

Build the theoretical argument:

1. **Status as rank, not standing.** Engage MacDonald & Parent (2021) distinction between continuous standing and ordinal rank. Argue that the paper adopts the rank perspective: being #1 is qualitatively different from #2, not just quantitatively better. (Current material: lines 140-142.)

2. **Coarse categorization as micro-foundation.** Actors use broad categories ("top partner" vs. "second partner") because they are cognitively cheaper to process (Graeber et al. 2025, Enke 2024). Rankings are natural coarse categories. (Current material: lines 134, 145.)

3. **Rank effects in politics.** Domestic evidence (Anagol & Fujiwara 2016, Folke et al. 2016, Granzier et al. 2023) shows rank reversals produce bandwagon effects. Bridge: "We extend this logic to international politics."

#### Block 3: "Three Channels of Rank-Salience" (~3 paragraphs)

This is the most important new block. Currently the paper mixes channels. Separate them explicitly as **complementary** (not competing):

1. **Cognitive channel**: Decision-makers use coarse categories directly. The rank reversal enters their "consideration set" (poliheuristic theory, Mintz 2004). Direct effect on policy.

2. **Media channel**: Media amplifies the milestone because rank changes are "newsworthy." Disproportionate coverage shifts the public agenda (Edwards & Wood 1999). Indirect effect: rank reversal -> media -> public/elites -> policy.

3. **Political coordination channel**: The rank reversal serves as a *focal point* for lobbies, business interests, and bureaucrats who already had converging interests but lacked a "moment" to coordinate pressure. Similar to bandwagon effects.

Close with: "These channels are complementary rather than competing. Our empirical strategy identifies the combined effect; the media analysis provides suggestive evidence on the amplification channel specifically."

#### Block 4: Hypotheses and Scope Conditions (~1.5 pages)

As described in Priority 1 above.

#### Block 5: Alternative Explanations (~1 page)

Move to end of theory section (currently scattered or absent):

- **Lula presidency/ideology**: Took office 2003, 6 years before treatment. Placebos at 2003/2005 test this. Cross-country design eliminates single-leader confounders.
- **2008 financial crisis**: Controlled for via current account and budget deficit covariates. SDiD time weights absorb common shocks.
- **Dual hegemony** (Schenoni & Leiva 2021): Predicts gradual attraction, not discrete break at 2009. Placebos distinguish the two.
- **Trade growth nonlinearity**: Covariates include trade shares. Placebos at years with steep growth but no rank change are null.

### Estimated changes

- Section 2 grows from ~3.5 pages to ~5 pages, but becomes more structured
- Net word count roughly neutral (reorganization, not addition)
- Requires minor cuts to redundant literature citations in current text

---

## Backlog: Placebo Outcome Tests

*Status*: BACKLOG (implement only if a reviewer requests it)

### Idea

A placebo outcome is a variable where, under our theory, the rank reversal should have **no effect**. If we find a null effect on the placebo outcome, it strengthens the claim that the SDiD is capturing alignment, not some unrelated shock.

### Candidates considered

1. **UNGA distance to US**: REJECTED. If Brazil aligns more with China, it may also distance from the US (or not, if UNGA is multidimensional). This would likely show *some* effect, just noisier. Not a clean placebo.

2. **Bilateral trade volume (China-Brazil)**: QUESTIONABLE. Trade itself may respond to political alignment (reverse causality). Not independent enough.

3. **Possible candidates where no effect is expected**:
   - **Military spending (% GDP)**: Trade status changes should not affect defense budgets, which respond to security threats, not trade milestones. Source: SIPRI.
   - **Bilateral migration flows**: Trade rank reversal should not immediately affect immigration patterns.
   - **Environmental treaty ratification**: A non-trade domain where status change in trade shouldn't have mechanical effects.
   - **Bilateral aid flows (if Brazil is a donor)**: Aid decisions are budgetary and long-term, unlikely to respond to a trade milestone.

### Recommendation

If a reviewer asks for a placebo outcome, **military spending (% GDP)** is the cleanest candidate: it's available in panel form (SIPRI), has no theoretical reason to respond to trade rank changes, and is a "hard" policy variable (not a voting index).

---

## Alternative Measures of Foreign Policy Alignment (beyond UNGA)

*Status*: BACKLOG (for robustness or future work)

### Why consider alternatives?

UNGA ideal points (Bailey et al. 2017) are the standard in the literature, but reviewers may ask:
- Whether results hold with a different operationalization
- Whether UNGA votes capture the full scope of foreign policy alignment

### Available alternatives

#### 1. FPSIM v2 (Foreign Policy Similarity Dataset)

- **Authors**: Frank Haege (University of Limerick)
- **Coverage**: 1946-2022, all UN member dyads
- **What it measures**: Multiple similarity indices for UNGA voting (S-score, pi, kappa, affinity, ideal-point distance)
- **URL**: https://fpsim.org
- **Advantage**: Offers multiple metrics in one dataset, allowing robustness across operationalizations
- **Limitation**: Still based on UNGA votes, so it doesn't escape the "UNGA only" criticism

#### 2. Alliance-Based Measures

- **Formal alliances** (ATOP dataset, Leeds et al.): Binary indicator of shared defense pacts. Too coarse for Brazil-China (no formal alliance).
- **Security cooperation agreements**: Bilateral agreements on defense, intelligence, etc. Hard to systematize across countries.
- **Arms transfers** (SIPRI): Direction and volume of weapons trade captures security alignment. Could work as a complementary measure.

#### 3. CSIS Global Alignment Index (experimental)

- **Source**: Center for Strategic and International Studies
- **What it measures**: Composite alignment with US vs. China across economic, diplomatic, and security dimensions
- **Limitation**: Only available for recent years (~2020+). Cannot be used in our panel.

#### 4. Public Opinion Surveys

- **Gallup World Poll**: "Do you approve or disapprove of the leadership of [China/US]?"
- **Pew Global Attitudes**: Favorability ratings of China/US
- **Advantage**: Captures societal alignment, not just elite/government
- **Limitation**: Inconsistent country-year coverage; not available for most of our panel period

#### 5. Trade Policy Alignment

- **WTO voting patterns**: How countries vote on trade disputes/resolutions
- **BIT/FTA network**: Which countries sign bilateral investment treaties or FTAs with China vs. US
- **Limitation**: Sparse events, hard to create annual panel

#### 6. Diplomatic Visits / Embassy Exchanges

- **Source**: GDELT, diplomatic cables
- **Advantage**: Captures active diplomatic engagement beyond UNGA
- **Limitation**: Measurement noise, inconsistent coverage

### Recommendation for the paper

If a reviewer asks for alternative FP measures:

1. **First choice**: Use FPSIM v2 to show results hold across multiple UNGA-based metrics (S-score, pi, etc.). Low effort, same data source, addresses "index sensitivity."

2. **Second choice**: Use SIPRI arms transfers as a non-UNGA measure. Different domain (security vs. political), speaks to breadth of alignment.

3. **Note in the paper**: Acknowledge that UNGA captures only one dimension of foreign policy. Future work could examine trade policy, security cooperation, or diplomatic engagement as complementary outcomes.

---

## Implementation Priority

1. **Theory restructuring** (Priority 3) — do first, because it determines the structure
2. **Hypotheses** (Priority 1) — write after the theory is restructured
3. The backlog items are **not for immediate implementation** — only if requested by a reviewer

## Cross-reference

- Detailed 9-step theory plan: `quality_reports/plans/2026-02-10_revisao-enquadramento-teorico.md`
- SDiD covariates plan (completed): `quality_reports/plans/2026-02-14_sdid-covariates-institucionais.md`
- Earlier editorial review: `quality_reports/2026-02-10_review-paper.md`
