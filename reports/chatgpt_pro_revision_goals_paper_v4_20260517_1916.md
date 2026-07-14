# APSR Revision Goals

## Field-Specific Calibration

Use the following standard when revising: an APSR-level empirical paper must make readers update their beliefs about a general political-science mechanism, not merely accept a plausible country case. For this manuscript, the publication barrier is not that the Brazil result is uninteresting. The barrier is whether the paper can show that an ordinal trade-rank shock has evidentiary leverage distinct from continuous trade growth, commodity demand, South-South diplomacy, BRICS-era foreign policy, and general awareness of China’s rise.

## Strategic Triage of the Pareceres

The reports are right on five central points: the paper must separate rank from trade volume more directly; H2 is currently underused because the panel does not directly estimate whether U.S.-displacement cases have larger effects; the cross-country diagnostics and captions must be harmonized before the panel can carry weight; the manuscript overuses broad “foreign-policy realignment” language for an outcome that is UNGA voting distance to China; and visible typos, broken figure labels, unresolved table numbering, and inconsistent p-values would damage credibility at review.

The reports are partly right, but too demanding or too literal, on mechanism evidence. Additional elite, Itamaraty, legislative, or exporter evidence would strengthen the paper, but the manuscript does not need to causally identify every link from media salience to UNGA votes. The correct revision is to separate two claims: the attention shock is measured directly in Brazil; the translation from attention to votes remains a theorized policy-response channel supported by reduced-form convergence and suggestive elite discourse. Similarly, NLP reproducibility should be improved, but the media section should not become a machine-learning paper.

The reports are wrong or strategically harmful where they imply the paper should abandon its core design, add broad policy trade-off analysis, or concede that the paper is inherently not APSR-suitable. Do not turn the conclusion into a cost-benefit essay. Do not bury the Brazil design under a long list of secondary estimators. Do not remove all “foreign-policy alignment” language; instead, discipline it by repeatedly tying the empirical claim to “UNGA voting convergence toward China, one observable dimension of foreign-policy alignment.”

The revision logic is: make the contribution narrower but sharper. The paper should become a theory of threshold salience in international political economy: continuous trade growth matters, but crossing a publicly legible rank threshold can reclassify a rising power from “important partner” to “top partner,” especially when it displaces the United States. Brazil supplies the high-salience case with the strongest identification and media evidence; the cross-country panel supplies a scope probe, not dispositive proof.

## Executable Revision Goals

### Goal 1 — Rebuild the abstract and introduction around a disciplined claim ladder

**Codex task:** Rewrite the abstract and introduction so the paper advances three explicitly separated claims: (1) a reduced-form Brazil claim, (2) a Brazil mechanism-implication claim about media salience, and (3) a cautious cross-country scope claim. Replace broad “foreign-policy realignment” language with “UNGA voting convergence toward China” unless the sentence is explicitly theoretical.

**Actions:**

1. Replace the current abstract with a version that reports the Brazil SDiD estimate as an average post-treatment gap, not a discontinuity.
2. State that the media evidence identifies attention/salience in Brazil, not the full causal path from salience to votes.
3. Describe the cross-country estimates as smaller and suggestive unless the cleaned diagnostics and robustness checks justify stronger language.
4. Use one sentence early in the introduction to define the contribution: rank thresholds as publicly legible status cues in IPE.

**Draft abstract language to adapt:**

> How do discrete changes in trade hierarchies affect foreign-policy behavior? Research on China’s economic influence usually treats trade exposure as continuous: more trade should produce more alignment. I argue that rank thresholds can matter independently because becoming a country’s top trade partner creates a publicly legible status cue, especially when China displaces the United States. I test this argument in Brazil, where China overtook the United States as Brazil’s leading trade partner in 2009. Using synthetic difference-in-differences and UNGA ideal-point distance to China, I estimate that Brazil’s post-2009 distance to China fell by 0.26 points relative to the synthetic counterfactual, about 41% of Brazil’s pre-treatment distance, with placebo-based inference rejecting no effect at conventional levels. This is an average post-treatment gap, not evidence of a one-year discontinuity. To probe the attention mechanism, I analyze Folha de S.Paulo coverage and show that China-related trade coverage became more salient after the rank reversal. A cross-country switching-treatment panel provides suggestive evidence that China’s entry into the top export-destination position is associated with smaller UNGA distance to China, though the pooled effect is weaker than in the high-salience Brazilian case. The findings suggest that international political economy should attend not only to continuous trade dependence but also to categorical thresholds that make economic change politically usable.

**Draft introduction contribution sentence:**

> The paper’s central claim is not that trade with China mechanically produces alignment. It is that crossing a rank threshold can reclassify China from an important commercial partner into the top partner, creating a salient political cue that may make diplomatic adjustment more likely than trade-volume growth alone would predict.

**Acceptance criteria:** The first three pages must make clear what is identified, what is suggestive, and what remains theorized. The abstract must not say or imply that the design identifies the salience-to-vote mechanism.

---

### Goal 2 — Resolve the treatment-definition problem: top trade partner vs. top export destination

**Codex task:** Audit and harmonize every treatment definition in the manuscript, data construction, figures, captions, and tables. Decide whether the main treatment is “top trade partner by total bilateral trade” or “top export destination.” If the main panel must remain export-destination based, narrow the theory and wording accordingly; if total-trade treatment is available and consistent with the public salience claim, make it the main specification or a co-primary robustness check.

**Actions:**

1. Create treatment variants from the trade data: top export destination, top import source, top total-trade partner, China’s ordinal rank, China’s trade share, and China’s margin over the second-ranked partner.
2. For Brazil, report a small treatment-audit table showing the year China becomes number one under each definition.
3. For the cross-country panel, report how many treated countries and treatment switches each definition produces.
4. Re-estimate the core Brazil SDiD and cross-country fect models under the feasible treatment variants.
5. Add a concise paragraph explaining why the chosen main treatment best matches the theory of public salience.

**Draft wording if export destination remains main:**

> Empirically, the cross-country treatment is China becoming a country’s largest export destination. I therefore use “top export destination” when describing the panel estimand and reserve “top trade partner” for the Brazilian public-salience case when the data and contemporary coverage support that broader description.

**Draft wording if total trade becomes main or co-primary:**

> Because the theory concerns a publicly legible commercial hierarchy, the preferred treatment uses total bilateral trade. Export-destination status is reported as a robustness check because exporters and policymakers may also perceive market access through export rankings.

**Acceptance criteria:** No figure note, hypothesis, abstract sentence, or table caption should alternate casually between “partner,” “export destination,” and “trade partner.” Any remaining distinction must be intentional and explained.

---

### Goal 3 — Show that rank is not just a relabeled nonlinear trade-volume effect

**Codex task:** Add a focused rank-versus-volume evidence package that directly addresses the main APSR skepticism: that the treatment is simply continuous trade growth, commodity demand, or a nonlinear trade-share effect.

**Actions:**

1. Add a descriptive figure for Brazil plotting China’s trade share, China’s rank, and the China-over-second-partner margin around 2009.
2. Add a table comparing Brazil SDiD estimates with and without continuous trade-share covariates already in the paper.
3. Add placebo tests for years of rapid China trade growth without rank reversal, including the existing 2003 and 2005 placebo years, but present them explicitly as rank-versus-volume tests.
4. In the panel, estimate models that include continuous China trade share and the China-over-second margin where feasible, while avoiding post-treatment controls that mechanically absorb the treatment effect. If a variable is post-treatment, say so and present it only as a descriptive diagnostic, not as a preferred control.
5. Avoid high-order polynomial “fixes.” The revision should not rely on quadratic or cubic terms as the main answer to the rank-versus-volume concern.

**Draft manuscript paragraph:**

> The rank interpretation requires more than showing that trade with China was increasing. Brazil’s exports to China grew before 2009, including years in which China rose in the hierarchy but did not become number one. The in-time placebo tests therefore serve a specific purpose: they ask whether rapid trade growth and lower-rank promotions generate the same estimated convergence as the top-rank reversal. They do not. This pattern is consistent with the argument that the number-one threshold has informational and political salience beyond continuous exposure.

**Acceptance criteria:** A skeptical reader must be able to locate, in one subsection, the evidence that the 2009 effect is not merely “trade with China was growing.”

---

### Goal 4 — Test H2 directly or explicitly demote it

**Codex task:** Implement a direct H2 heterogeneity analysis for the cross-country panel: the effect should be larger when China displaces the United States than when it displaces another partner. If the sample is too small or the result is unstable, keep H2 as a scope-condition expectation and report the limitation honestly rather than implying that the current pooled ATT tests it.

**Actions:**

1. Construct variables for the identity of the displaced number-one partner, whether the displaced partner is the United States, and the incumbent’s pre-treatment tenure as number one.
2. Estimate separate fect or event-study specifications for U.S.-displacement and non-U.S.-displacement cases if sample size permits.
3. Estimate or bootstrap the difference between the two subgroup effects. If this is not feasible, report descriptive subgroup ATTs with uncertainty and call the test exploratory.
4. Add a table listing treated cases by treatment year, displaced partner, U.S.-displacement indicator, incumbent tenure, and treatment-switching status.
5. Revise the hypothesis section so H2 is either tested directly or framed as an untested scope condition.

**Draft wording if the H2 test is weak:**

> The cross-country panel is informative about the general top-rank claim, but it has limited power to adjudicate the hegemonic-replacement hypothesis. I therefore treat U.S.-displacement as a scope condition highlighted by the Brazilian case and report exploratory heterogeneity estimates rather than presenting H2 as conclusively tested.

**Draft wording if the H2 test supports the theory:**

> The pooled estimate masks theoretically relevant heterogeneity. Cases in which China displaces the United States show a larger estimated movement toward China than cases in which China displaces another partner, consistent with the claim that rank reversals are most salient when the displaced incumbent is the hegemon.

**Acceptance criteria:** The paper must no longer contain the pattern “H2 is theoretically central, but the empirical section admits it is not tested” without a corrective analysis or explicit demotion.

---

### Goal 5 — Strengthen the Brazil SDiD identification package without bloating the main text

**Codex task:** Reorganize the Brazil empirical section around one main SDiD estimate and a compact set of diagnostics that directly answer identification threats. Move secondary diagnostics to the appendix.

**Actions:**

1. Report pre-treatment fit metrics, including RMSPE or equivalent fit diagnostics, in the main text or a compact table.
2. Report donor weights and covariate balance cleanly; move long donor plots to the appendix unless they are essential.
3. Run donor-pool sensitivity checks: Latin America-only donor pool, leave-one-high-weight-donor-out, exclusion of donor countries that themselves experience China top-rank reversals during relevant periods, and exclusion of donors with obvious post-2009 China shocks if identified in the data.
4. Keep the existing 2003, 2005, and 2012 placebo/falsification tests, but label them by the threat they address: lower-rank promotion, rapid trade growth without top rank, and later-break alternative timing.
5. Add a short paragraph on simultaneous Brazilian political confounders—Lula, BRICS/South-South diplomacy, and the 2008 crisis—without claiming they are fully ruled out.

**Draft caveat:**

> The Brazilian design cannot rule out every contemporaneous political development in 2009. Its credibility comes from the combination of close pre-treatment fit, explicit controls for trade exposure and crisis-related macroeconomic stress, in-time placebos during earlier periods of rapid China trade growth, and donor-pool sensitivity checks. The estimate should therefore be read as strong reduced-form evidence for the Brazilian rank-reversal episode, not as a direct test of every mechanism linking salience to votes.

**Acceptance criteria:** The main Brazil result should be defensible in three pages: estimand, fit, estimate, placebo logic, and one paragraph of limitations. Anything more detailed belongs in the appendix.

---

### Goal 6 — Add outcome robustness that matches the paper’s claim scope

**Codex task:** Add a compact outcome-robustness package for UNGA alignment so the manuscript does not depend entirely on one ideal-point distance measure or on one issue area.

**Actions:**

1. Re-estimate the Brazil result using at least two alternative UNGA-based outcomes where feasible: vote similarity/S-score, identical-vote share, relative distance to China versus the United States, or issue-area-specific distance.
2. Add issue-area diagnostics that show whether the estimated convergence is concentrated in human rights or also visible elsewhere.
3. If convergence is concentrated in human rights, revise the theoretical interpretation to explain why that is substantively meaningful and why it is not merely an agenda-composition artifact.
4. Consider a robustness check excluding human-rights resolutions if the data permit. If the effect disappears, do not hide it; use it to narrow the mechanism.
5. Make clear that these are robustness and interpretation checks, not new primary estimands unless they strongly outperform the current outcome.

**Draft wording for a concentrated human-rights result:**

> The resolution-level evidence suggests that convergence is not an across-the-board diplomatic bandwagon. It is concentrated in issue areas where Brazil had residual disagreement with China and where movement was politically meaningful. This pattern narrows the empirical claim: the rank reversal appears to have made selective UNGA convergence more likely, rather than producing wholesale foreign-policy realignment.

**Acceptance criteria:** The reader should not be able to dismiss the paper by saying “this is only one ideal-point measure” or “this is only a human-rights agenda artifact” without confronting explicit robustness evidence.

---

### Goal 7 — Clean and demote the cross-country panel to a credible scope probe

**Codex task:** Rebuild the cross-country section so it has one main estimator, one main table, one main dynamic figure, and a short limitations paragraph. Harmonize all fect, equivalence-test, bootstrap, and caption values across text, figures, appendix, and tables.

**Actions:**

1. Treat the switching-treatment fect IFE estimator as the main cross-country specification.
2. Move PanelMatch, C&S absorbing-treatment estimates, leave-one-out analysis, and raw treated-country panels to the appendix unless they directly change the core conclusion.
3. Audit every p-value and diagnostic in Figure 10, Figure 19, Table 3, and the associated text. Fix all mismatches.
4. State the exact estimand difference between fect and C&S: full switching panel versus absorbing-treatment subset.
5. Rephrase the panel evidence as “consistent with” or “suggestive of” generalization unless the cleaned estimates are robustly significant across definitions and outcomes.
6. Add a one-paragraph explanation of why heterogeneity is expected: Brazil is a high-salience U.S.-replacement case; the pooled panel averages over weaker cases.

**Draft cross-country transition:**

> The panel analysis should not be read as a second Brazil. It estimates a broader and weaker estimand: the average association between China entering and holding the top export-destination position across heterogeneous cases, many of which lack Brazil’s high-salience displacement of a long-entrenched U.S. incumbent. Its purpose is to probe scope and rule out a purely Brazilian episode, not to identify the mechanism with the same leverage as the Brazil-media design.

**Acceptance criteria:** No inconsistent diagnostic values remain. The main text should no longer feel like a methods appendix.

---

### Goal 8 — Make the media/NLP evidence reproducible and properly bounded

**Codex task:** Revise the media section so it supports the attention claim and does not overclaim the policy-response mechanism. Improve classification reproducibility enough that a reviewer sees the NLP evidence as a useful measurement exercise rather than an opaque LLM artifact.

**Actions:**

1. State that Folha evidence measures Brazilian media salience, not cross-country mechanism operation.
2. Freeze and report the classification protocol: model, date/version if available, prompt, temperature, batch procedure, refusal-handling rules, and exact label set.
3. Add a deterministic cross-check using a transparent dictionary or regular-expression count for trade terms such as exports, imports, trade, soy, iron ore, Vale, partner, and China-Brazil commerce terms in Portuguese. Use this as a validation check, not a replacement for the classifier.
4. Expand validation if feasible: two human coders or at least a second blinded human validation sample; report a confusion matrix and category-specific accuracy for the theoretically important categories.
5. Keep only the media figures that show the key pattern: total China salience, trade-share salience, and disaggregated trade versus non-trade coverage. Move trigrams, “bate” examples, and prompt details to the appendix.
6. Present elite statements from Lula and Congress as illustrative corroboration, not as causal identification.

**Draft mechanism caveat:**

> The media evidence identifies the first step in the proposed mechanism: the rank reversal made China’s commercial status more salient in Brazilian public discourse. It does not by itself prove that media attention caused UNGA votes to change. The policy-response channel remains a theoretically motivated interpretation of the reduced-form SDiD estimate, supported by the timing and content of the salience shift.

**Acceptance criteria:** A reviewer should not be able to characterize the mechanism section as “ChatGPT classified headlines and therefore votes changed.” The section must clearly say what the evidence does and does not identify.

---

### Goal 9 — Compress the paper and repair all presentation defects before any top-journal submission

**Codex task:** Perform an exposition pass aimed at making the manuscript read like a submission rather than a research notebook. Reduce defensive diagnostics in the main text, repair every broken label, and standardize terminology.

**Actions:**

1. Target this main-text structure: Introduction; Theory and hypotheses; Data and design; Brazil SDiD evidence; Brazilian media salience; Cross-country scope probe; Conclusion.
2. Move to the appendix: PanelMatch details, full raw treated-country plots, leave-one-out table, C&S dynamic plots, extended NLP prompt examples, long donor-weight plots, and detailed estimator equations if they are not necessary for interpretation.
3. Replace casual or incorrect wording: “specially” → “especially”; “the paper empirically document” → “the paper empirically documents”; “Firstly I consider” → “I first examine”; “toe reflect” → “to reflect”; “Wolrd Trade Organization” → “World Trade Organization.”
4. Fix all figure/table defects: remove embedded “Figure 1” text inside Figure 3; resolve `(#fig:...)` labels; locate or remove missing Table 4 references; ensure Figure 19 captions match plotted p-values; ensure every note states the correct unit, time window, standard error, clustering, and treatment definition.
5. Remove anonymous-reviewer acknowledgments from any submission version.
6. Replace broad claims with precise claims throughout: “foreign-policy realignment” → “UNGA voting convergence toward China” unless the sentence is explicitly conceptual.
7. Source or document factual claims such as the United States being Brazil’s leading partner for roughly eight decades using data notes or primary sources.

**Acceptance criteria:** A final automated and manual search should find no unresolved cross-references, no inconsistent treatment definitions, no broken figure labels, no typos listed above, and no unsupported broad “realignment” claims.

---

### Goal 10 — Prepare concise response-to-referee language for the hardest points

**Codex task:** Draft response-letter paragraphs that concede the valid criticism, describe the implemented revision, and resist overbroad interpretations of the criticism. Use these as reusable language if the paper is revised after advisor or referee feedback.

**Response language on rank versus trade volume:**

> We agree that the core claim requires distinguishing an ordinal rank threshold from continuous trade growth. We therefore added treatment-definition audits, lower-rank placebo tests, continuous trade-share diagnostics, and alternative treatment definitions based on exports, imports, total trade, rank, and the China-over-second-partner margin. These revisions make clear that the argument is not that trade volume is irrelevant, but that crossing the number-one threshold can create a politically salient cue not captured by smooth exposure alone.

**Response language on mechanism limits:**

> We agree that the media analysis does not causally identify the full salience-to-vote pathway. We have revised the theory and evidence sections to separate the directly measured attention claim from the theorized policy-response claim. The media evidence now supports the claim that the rank reversal increased the salience of China’s commercial status in Brazil; the SDiD estimate remains a reduced-form estimate of post-reversal UNGA convergence.

**Response language on cross-country fragility:**

> We have reframed the cross-country analysis as a scope probe rather than a decisive mechanism test. The main estimator now uses the switching-treatment fect design, while absorbing-treatment and matching estimators are reported as robustness checks in the appendix. We also added heterogeneity analysis for U.S.-displacement cases and clarified that the pooled panel averages over cases with different levels of salience.

**Response language on outcome scope:**

> We have narrowed the empirical language throughout. The manuscript now refers to “UNGA voting convergence toward China” when discussing estimated effects and treats this as one observable dimension of foreign-policy alignment rather than as comprehensive evidence of foreign-policy realignment.

**Acceptance criteria:** The response language should be candid without conceding away the paper’s core contribution. It should not promise analyses that the revised manuscript does not actually contain.

## What Not to Do

Do not turn the paper into a general essay about the costs and benefits of symbolic trade milestones. Do not add many new estimators in the main text merely to look robust. Do not present the cross-country panel as conclusive if the estimates remain marginal or definition-sensitive. Do not claim the NLP evidence identifies the causal mechanism from salience to UNGA votes. Do not abandon the Brazil-first design; the Brazil case is the paper’s strongest evidence. Do not remove all status language; the status/rank idea is the contribution, but it must be tied to observable rank thresholds and UNGA convergence.

## Priority Order

1. Fix treatment definitions and rank-versus-volume evidence.
2. Rewrite abstract/introduction around the disciplined claim ladder.
3. Test or demote H2.
4. Strengthen Brazil SDiD diagnostics and outcome robustness.
5. Clean cross-country diagnostics and demote the panel to a scope probe if needed.
6. Bound and validate the media/NLP mechanism evidence.
7. Compress the main text and repair all presentation defects.
8. Draft response-to-referee language only after the analyses are actually implemented.
