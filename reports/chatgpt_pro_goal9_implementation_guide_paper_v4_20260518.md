# Goal 9 Implementation Guide

This guide is for the Codex agent that will edit `paper_v4.Rmd` to implement Goal 9 first and then prepare the manuscript for a later Goal 1 abstract/introduction rewrite. Use `paper_v4.Rmd` as the authoritative source. The rendered PDF is only a visual/context reference.

Do **not** run `targets::tar_make()`. Do **not** reopen Goal 2. Do **not** turn this into a new NLP/media reproducibility plan. Do **not** write the final abstract or full introduction here; reserve that for Goal 1 after the paper architecture is stable.

The relevant reports to treat as constraints are:

- `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.md`
- `quality_reports/2026-05-18_goal3_rank_vs_volume_diagnostic.md`
- `quality_reports/goal4_h2_scope_condition/goal4_h2_methodological_report_20260518.md`
- `quality_reports/2026-05-18_goal5_sdid_identification_prompt_report.md`
- `quality_reports/goal6_outcome_robustness/2026-05-18_goal6_outcome_robustness_report.md`
- `quality_reports/2026-05-18_goal7_cross_country_scope_prompt_report.md`

## One-Page Diagnosis

After Goals 3--7 are reflected, but before Goal 1 rewrites the abstract and introduction, the paper should read as a compact, Brazil-first APSR-style empirical manuscript about **rank thresholds in international political economy**. The paper should no longer read like a research notebook that reports every diagnostic in the main text. It should present a disciplined claim ladder:

1. **Brazil is the main reduced-form design.** The Brazilian SDiD estimate is the paper's strongest causal evidence. It estimates the average post-2009 gap in Brazil's UNGA ideal-point distance to China relative to a synthetic counterfactual after China became Brazil's largest export destination. It is not evidence of a one-year discontinuity, and it is not a direct causal test of the salience-to-vote mechanism.

2. **Rank-versus-volume evidence is necessary but should be compact.** Goal 3 supports the claim that the 2009 Brazil treatment is empirically distinguishable from smooth export-volume growth: China export share was rising before 2009, but the ordinal rank-1 category switched only in 2009. The 2003 and 2005 in-time placebos should be framed as **rank-versus-volume timing tests**: rapid trade growth and lower-rank promotions did not generate a comparable estimated shift. These are timing falsifications, not equivalence tests. Contemporaneous post-2009 China share and China-over-second margin are not clean preferred controls because they are mechanically tied to, or downstream from, treatment.

3. **Media evidence is salience evidence, not mechanism identification.** The Folha evidence should support only the attention/salience step: the 2009 rank reversal made China and China-Brazil trade more salient in Brazilian public discourse. It should not be written as showing that media attention caused UNGA votes to change. Goal 8 will later improve reproducibility; Goal 9 should only bound the claim and move excessive NLP details to the appendix.

4. **Outcome robustness broadens the measurement base but narrows the substantive claim.** Goal 6 reports that the main Brazil result is not an artifact of one absolute ideal-point-distance metric: the China-minus-US relative-distance contrast points in the expected direction. However, agreement and resolution-level measures are sensitive to agenda composition. Resolution-level evidence shows selective convergence, with stronger descriptive movement in human rights than outside human rights. The paper should therefore narrow from broad “foreign-policy realignment” to **selective UNGA voting convergence toward China**, especially in issue areas where Brazil had room to move.

5. **The cross-country panel is a scope probe.** Goal 7 requires demoting the panel to a credible scope probe: one main estimator, one main table, one main dynamic figure, and one short limitations paragraph. It should not compete with Brazil as a second main identification design. The preferred main text estimator is the switching-treatment `fect` IFE specification with covariates if the audited values support that choice. C&S absorbing-treatment estimates, PanelMatch, leave-one-out, raw treated panels, and detailed diagnostics belong in the appendix unless they change the central conclusion.

6. **H2 is a scope condition, not a confirmed result.** Goal 4 finds that the pooled ATT is not a direct H2 test and that the exploratory subgroup comparison does not provide confirmatory evidence that U.S.-displacement effects are larger. The manuscript should say that the Brazilian case lies in the high-salience U.S.-displacement scope condition, while cross-country H2 evidence is exploratory and underpowered. Remove or rewrite any claim that the panel directly confirms H2.

Goal 9's job is exposition and architecture: compress, relocate diagnostics, standardize terminology, repair captions/cross-references, and make the claim strength consistent with the evidence. It should not add many new analyses, collect new data, or solve Goal 8.

## Priority Order

### Passes that must happen before moving content to the appendix

1. **Freeze the claim ladder.** Before editing section structure, write a short internal note at the top of your implementation scratchpad: “Main claim = Brazil reduced-form UNGA convergence after rank reversal; media = salience evidence; cross-country = scope probe; outcome robustness = selective convergence; H2 = scope condition/exploratory.” Use this note to adjudicate every cut.

2. **Freeze terminology.** Treat the empirical treatment as **China becoming the largest export destination**. The already-incorporated Goal 2 note permits “top trade partner” as shorthand for the publicly salient Brazilian event, but captions, estimands, and treatment notes should use “largest export destination” or “top export destination.”

3. **Audit all current sections, chunks, labels, tables, and figures.** Make a quick inventory from `paper_v4.Rmd`: section headers, chunk labels, figure labels, table labels, and all references to `Table`, `Figure`, `@fig`, `@tbl`, `\ref`, and `(#fig:...)`. Do this before relocating material so that you do not create orphaned references.

4. **Identify the main-text evidence set.** Decide which tables and figures remain in the main text using the architecture below. Mark everything else as appendix material before cutting prose.

5. **Insert the necessary claim-discipline paragraphs before major cuts.** Add short paragraphs/caveats for rank-versus-volume, H2 demotion, outcome-scope narrowing, and cross-country scope-probe status. Once these are in place, cuts will be less likely to remove the paper's safeguards.

### Passes after the main/appendix boundary is clear

6. **Compress the Brazil SDiD section to roughly three pages.** Keep estimand, fit, estimate, rank-versus-volume placebo logic, compact outcome robustness, and one limitations paragraph. Move donor details and secondary diagnostics.

7. **Compress the media section to the attention claim.** Keep the main salience pattern and one clean disaggregated figure or compact set of figures. Move trigrams, examples of “bate,” prompt details, and validation details to the appendix.

8. **Rebuild the cross-country section as a scope probe.** Keep one main `fect` IFE table, one dynamic figure, a short paragraph on H2 as exploratory heterogeneity/scope, and one limitations paragraph. Move C&S, PanelMatch, leave-one-out, raw treated panels, equivalence/carryover details, and long estimator discussion to the appendix.

9. **Renumber, relabel, and rewrite captions/notes.** Every main-text table/figure must have a caption and note stating unit, time window, treatment definition, uncertainty, and causal/descriptive status.

10. **Line edit for terminology and typos.** Run the validation searches listed below. Replace overbroad empirical claims and remove casual phrasing.

11. **Render once using the repository's ordinary document-rendering command.** Do not run `targets::tar_make()`. Fix compilation warnings, duplicate chunk labels, missing references, and unresolved labels.

12. **Stop only after validation passes.** A clean Goal 9 implementation has no unresolved cross-references, no broken labels, no known typos, no main-text overclaiming, and no main-text diagnostic sprawl.

## Main Text Architecture

The target main-text structure is:

1. Introduction
2. Theory and hypotheses
3. Data and design
4. Brazil SDiD evidence
5. Brazilian media salience
6. Cross-country scope probe
7. Conclusion

### 1. Introduction

**Stay:** The motivating 2009 Brazil headline, the rank-threshold puzzle, the core theoretical contrast between continuous trade exposure and categorical rank thresholds, and a short preview of the evidence ladder.

**Compress:** Literature setup. The introduction should not review status, China trade influence, cognitive psychology, and causal panel methods at length before stating the paper's contribution. Leave the final reordering to Goal 1, but remove obvious contradictions with the revised evidence.

**Move to appendix/delete:** None now, except defensive methodological criticism that is too detailed for the introduction.

**Goal 9 instruction:** Do not fully rewrite the abstract or introduction. Make only compatibility edits: terminology, H2 demotion, cross-country scope-probe status, and removal of claims that later sections no longer support.

### 2. Theory and hypotheses

**Stay:** The rank-threshold argument, coarse categorization, salience/attention claim, policy-response claim, temporal dynamics, and scope conditions.

**Compress:** The literature discussion should be leaner. Keep the distinction between “trade volume” and “rank threshold,” but reduce citation clusters that read as defensive. The theory should generate observable implications rather than rehearse every adjacent literature.

**Move to appendix/delete:** The simplified DAG can move to the appendix or be deleted unless it is revised to avoid implying that the paper causally identifies every arrow. Detailed methodological footnotes critiquing earlier designs should move to the appendix or be shortened.

**Required change:** Reframe H2. It should be a **scope-condition expectation** or **exploratory heterogeneity implication**, not a conclusively tested hypothesis. The Brazilian case is high-salience because China displaced a long-entrenched U.S. incumbent; the cross-country panel does not confirm H2.

### 3. Data and design

**Stay:** Outcome definition, treatment definition, Brazil SDiD design, media data overview, and cross-country switching-treatment design.

**Compress:** Long equations, detailed estimator comparisons, and long covariate justifications. The main text needs enough to understand the estimand and why the estimator is appropriate, not a methods appendix.

**Move to appendix:** Detailed DiD/SCM/SDiD equations; full covariate construction; full descriptive statistics; long explanation of fect, C&S, and PanelMatch; full discussion of equivalence/carryover testing.

**Required change:** Merge current “Methodology,” “Data and Variables,” and excessive descriptive setup into a cleaner “Data and Design” section. The section should make the treatment-definition note explicit once and then use the terminology consistently.

### 4. Brazil SDiD evidence

**Stay:** This is the main empirical section. Keep: the estimand, the main SDiD fit, the main estimate, the rank-versus-volume timing tests, compact donor/fit summary, compact outcome robustness, and one limitations paragraph.

**Compress:** Descriptive figures that do not directly support identification. Keep only the descriptive evidence needed to distinguish rank from volume and orient the reader.

**Move to appendix:** Long donor-weight plots, top-10 donor country trajectory plot, Latin America-only fit and weights, full donor tables, full covariate balance, donor-pool sensitivity details, detailed placebo distributions, raw ideal-point descriptive plots unless they are needed for interpretation.

**Required change:** Present the 2003 and 2005 timing placebos as rank-versus-volume tests, not generic robustness checks. Present the 2012 timing falsification as a later-break test.

### 5. Brazilian media salience

**Stay:** One concise section showing that China and China-Brazil trade became more salient in Folha after 2009. Keep the evidence that directly supports the attention/salience claim.

**Compress:** The prose about trigrams, headline examples, “bate,” prompt engineering problems, and multiple media figures. Use the strongest figure(s) and one paragraph of interpretation.

**Move to appendix:** Extended NLP prompt, examples, random sample, validation table/confusion matrix, trigrams, “bate” examples, model/prompt caveats, and any detailed classification discussion. Goal 8 will later strengthen this; Goal 9 should avoid main-text clutter.

**Required change:** Add an explicit caveat that the media evidence identifies attention/salience in Brazil, not the full causal path from salience to UNGA votes.

### 6. Cross-country scope probe

**Stay:** One main switching-treatment `fect` IFE estimator, one main table, one main dynamic figure, a short paragraph explaining heterogeneity/scope, and one limitations paragraph.

**Compress:** Everything else. The panel should not be a methods section inside the results section.

**Move to appendix:** C&S absorbing-treatment estimates and dynamic plot, PanelMatch ATT/ART, leave-one-out, raw treated-country panels, equivalence tests, carryover/exit details, long alternative-explanation table, and detailed H2 spell tables unless a compact H2 scope table is essential.

**Required change:** Make the estimand difference explicit: `fect` estimates the switching-treatment panel where treatment turns on while China is the largest export destination and turns off when China loses that position; C&S estimates a persistent-treatment subset and is not the same estimand.

### 7. Conclusion

**Stay:** A concise restatement of the rank-threshold contribution and the evidence ladder.

**Compress:** Broad policy claims and claims about refuting the status literature.

**Move/delete:** Strong claims such as “status gains are mostly illusory is wrong” or “foreign-policy realignment” if they imply more than the evidence supports.

**Required change:** End with a narrow contribution: trade-rank thresholds can make economic change politically salient and are associated with selective UNGA voting convergence toward China in the strongest case, with suggestive cross-country scope evidence.

## Section-by-Section Text Instructions

### Title and front matter

Use the user's current manuscript title unless the author explicitly prefers otherwise:

> The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Export Destination

If the current title says “Top Trade Partner,” either change it to “Top Export Destination” or leave a note for the author that the title conflicts with the Goal 2 treatment-definition clarification. Do not silently let the title conflict with the captions and estimands.

### Abstract and introduction

Do not perform the full Goal 1 rewrite. Make only consistency repairs:

- Replace empirical uses of “foreign-policy realignment” with “UNGA voting convergence toward China” or “one observable dimension of foreign-policy alignment.”
- Replace “cross-country estimate confirms” with “cross-country estimate is consistent with” or “provides suggestive scope evidence.”
- Remove any claim that the media evidence identifies the full mechanism.
- Remove any claim that H2 is conclusively tested.
- Ensure treatment wording matches the Goal 2 note: empirical treatment is China becoming the largest export destination.

Useful compatibility sentence for the introduction, to be refined later under Goal 1:

> The paper separates three claims: a reduced-form Brazil claim about post-2009 UNGA voting convergence toward China, a Brazilian media-salience claim about the public visibility of the rank reversal, and a cross-country scope claim about whether similar top-rank transitions are associated with smaller UNGA distance to China beyond the Brazilian case.

### Theory and hypotheses

Keep the theory's core: rank thresholds matter because actors use coarse categories such as “largest export market” or “top partner,” and the number-one threshold can make China politically salient beyond smooth export growth.

Replace the current H2 formulation with scope-condition language. Suggested language:

> **Scope condition: hegemonic-rival replacement.** The top-rank cue should be most politically salient when China displaces the United States or another long-entrenched, geopolitically prominent incumbent. The Brazilian case falls squarely inside this high-salience scope condition. Because the identity of the displaced partner is not randomly assigned and subgroup support in the cross-country panel is limited, the panel analysis treats U.S.-displacement as exploratory heterogeneity rather than a confirmatory test.

If the manuscript retains numbered hypotheses, revise H2 as follows:

> **Hypothesis 2 / Scope expectation.** The top-rank effect should be stronger in high-salience cases, especially when China displaces a long-entrenched U.S. incumbent. The empirical analysis treats this as a scope-condition expectation and reports exploratory heterogeneity rather than a definitive test.

Do not write that the pooled ATT tests H2. It does not.

### Data and design

Insert one clean treatment-definition paragraph and use it consistently throughout:

> Empirically, the treatment is China becoming a country's largest export destination. I use “top trade partner” only as shorthand for the publicly salient Brazilian event when contemporary coverage and the Goal 2 treatment note support that wording. In the Brazil SDiD and the cross-country panel, the estimand is defined by largest-export-destination status, not by total bilateral trade unless explicitly labeled otherwise.

Use “UNGA ideal-point distance to China” as the primary outcome. Define lower values as convergence toward China. When discussing outcome robustness, distinguish country-year outcomes from descriptive resolution-level diagnostics.

Move detailed equations to the appendix. The main text can summarize SDiD and fect in prose:

> SDiD estimates Brazil's average post-2009 gap relative to a weighted synthetic counterfactual, using pre-treatment information to construct unit and time weights. The estimate should be interpreted as an average post-treatment reduced-form effect, not as a one-year discontinuity.

For the cross-country design:

> The cross-country panel uses a switching-treatment design: treatment equals one in years when China is the country's largest export destination and returns to zero if China loses that position. The main estimator is the counterfactual `fect` IFE estimator, which is more appropriate for this switching structure than absorbing-treatment DiD estimators. Absorbing-treatment estimators are reported only as appendix sensitivity checks because they estimate a different subset.

### Brazil SDiD evidence

Open the section with the estimand and evidence hierarchy:

> The Brazilian analysis estimates the average post-2009 reduced-form effect of China's entry into the top export-destination position on Brazil's UNGA ideal-point distance to China. The design does not identify each mechanism linking salience to votes. Its credibility rests on pre-treatment fit, placebo timing tests, donor-pool sensitivity, and outcome robustness.

Use the main SDiD estimate already supported by Goals 3 and 6: ATT approximately `-0.264`, placebo SE approximately `0.123`, p approximately `0.032`, and a roughly 41% reduction relative to Brazil's pre-treatment distance. Verify the exact values from the current targets/report before hard-coding.

Add the rank-versus-volume paragraph:

> The rank interpretation requires more than showing that trade with China was increasing. Brazil's exports to China grew before 2009, including years in which China rose in the export hierarchy but did not become number one. The in-time placebo tests therefore ask whether rapid trade growth and lower-rank promotions generate the same estimated UNGA convergence as the top-rank reversal. They do not. This pattern is consistent with the claim that the number-one threshold has political salience beyond continuous exposure; it is not an equivalence test and does not prove that trade volume is irrelevant.

Use Goal 3 values in a compact table: 2003 placebo `-0.117` (SE `0.188`, p `0.534`), 2005 placebo `-0.119` (SE `0.135`, p `0.379`), 2009 actual `-0.264` (SE `0.123`, p `0.032`), and 2012 later-break placebo `0.037` (SE `0.139`, p `0.792`) if included.

Add the Goal 5 limitations paragraph:

> The Brazilian design cannot rule out every contemporaneous political development in 2009. Its credibility comes from the combination of close pre-treatment fit, explicit controls for trade exposure and crisis-related macroeconomic stress, in-time placebos during earlier periods of rapid China trade growth, and donor-pool sensitivity checks. The estimate should therefore be read as strong reduced-form evidence for the Brazilian rank-reversal episode, not as a direct test of every mechanism linking salience to votes.

Add the Goal 6 outcome-scope paragraph, preferably after the main result and before mechanism/media:

> As a robustness check, I reestimated the Brazilian SDiD using alternative UNGA-based country-year outcomes. The main result is not an artifact of the exact absolute-distance metric: Brazil also moves closer to China relative to the United States in the China-minus-US distance contrast. However, annual agreement measures and resolution-level vote similarity are more sensitive to agenda composition, so I treat them as interpretive diagnostics rather than alternative primary estimands. The resolution-level evidence indicates selective convergence, especially around human-rights votes, which narrows the substantive interpretation from wholesale foreign-policy realignment to issue-specific UNGA convergence after the 2009 trade-rank reversal.

Then add a short substantive caveat:

> This evidence should not be read as showing a uniform shift across the entire UNGA agenda. The post-2009 Brazil-China convergence is clearest in the ideal-point and relative-distance outcomes and is descriptively concentrated in issue areas where Brazil and China had room to converge, especially human rights. This pattern suggests selective diplomatic adjustment in politically salient areas, not a wholesale replacement of Brazil's foreign-policy orientation.

### Brazilian media salience

Reduce the section to a tight mechanism-implication test. Suggested opening:

> The SDiD estimate is reduced-form. To assess whether the rank reversal became publicly salient, I examine Folha de S.Paulo coverage of China before and after 2009. This evidence measures the attention step of the theory: whether China and China-Brazil trade became more visible in public discourse after the rank reversal.

Add the required caveat:

> The media evidence identifies the first step in the proposed mechanism: the rank reversal made China's commercial status more salient in Brazilian public discourse. It does not by itself prove that media attention caused UNGA votes to change. The policy-response channel remains a theoretically motivated interpretation of the reduced-form SDiD estimate, supported by the timing and content of the salience shift.

Keep only the main salience figure(s). Move the prompt and classification process details to the appendix. Do not spend main-text space apologizing for LLM classification; simply state the measurement approach and cite the appendix for validation.

### Cross-country scope probe

Rename the section to something like:

> Cross-Country Scope Probe

Do not call it a second main test or an independent confirmation of the theory. Use this transition:

> The panel analysis should not be read as a second Brazil. It estimates a broader and weaker estimand: the average association between China entering and holding the top export-destination position across heterogeneous cases, many of which lack Brazil's high-salience displacement of a long-entrenched U.S. incumbent. Its purpose is to probe scope and rule out a purely Brazilian episode, not to identify the mechanism with the same leverage as the Brazil-media design.

Use one main estimator, preferably the audited `fect_ife_china_top_cov` specification. Keep exact numerical values only after checking the Goal 7 audit outputs and current targets. The table must state: estimator, ATT, bootstrap SE, p-value/CI if available, N, treated/control units or treated spells, covariates, latent factors selected by CV, panel window, and treatment definition.

Add H2 language consistent with Goal 4:

> The pooled panel does not test the hegemonic-replacement scope condition directly because it averages across treatment spells with different displaced incumbents. Exploratory heterogeneity estimates by U.S.-displacement are reported in the appendix. Given limited subgroup support and non-random scope conditions, I interpret these estimates as descriptive scope evidence rather than confirmatory evidence for H2.

If reporting the Goal 4 exploratory result, write cautiously:

> In the available spell-level comparison, U.S.-displacement cases do not produce a clearly larger estimated effect than non-U.S.-displacement cases; the exploratory difference is imprecise. This does not overturn the Brazilian scope argument, but it prevents a strong cross-country claim that H2 has been confirmed.

Add the cross-country limitations paragraph:

> The cross-country estimates should be interpreted cautiously. The panel does not measure media salience in each country, treatment spells differ in incumbent identity and political visibility, and exit/carryover diagnostics cannot by themselves distinguish salience from reversible interest-based mechanisms. The panel therefore probes whether the top-rank pattern travels beyond Brazil; it does not identify the full mechanism.

### Conclusion

Narrow the conclusion. Suggested replacement for overbroad concluding claims:

> The evidence indicates that rank thresholds in trade hierarchies can matter for one observable dimension of foreign-policy behavior: UNGA voting convergence toward China. The strongest evidence comes from Brazil's 2009 rank-reversal episode, where SDiD estimates show a post-treatment reduction in distance to China and media evidence shows a contemporaneous rise in China-Brazil trade salience. Cross-country evidence is consistent with a broader top-rank pattern but remains a scope probe. The findings motivate further research on how categorical economic milestones become politically usable, without implying a wholesale reorientation of foreign policy or a fully identified salience-to-vote mechanism.

Avoid “contrary to Mercer, prestige is not illusory” as a strong conclusion. Use softer language:

> The findings speak to debates about whether status gains have observable behavioral consequences by showing that a specific economic status cue can be associated with measurable UNGA voting convergence.

## Tables

The goal is not to maximize the number of tables. The main text should have only tables that carry the claim ladder. Everything else should move to the appendix.

### Main-text tables

#### Main Table 1: Brazil SDiD estimate and rank-versus-volume timing tests

**Action:** Revise existing SDiD/placebo table or replace it with a compact table that includes the Goal 3 rank-versus-volume columns.

**Purpose:** Show the main Brazil estimate and make clear that 2003/2005 are tests against the “continuous export growth” alternative.

**Preferred columns:**

- Timing year
- Test role / threat addressed
- China export-destination rank
- Rank-1 reversal indicator
- China export share (%)
- Signed margin over second-ranked export destination
- ATT
- Placebo SE
- p-value
- Sample note, if needed

**Rows:**

- 2003: lower-rank promotion / rapid growth without rank 1
- 2005: rapid growth without rank 1
- 2009: actual rank-1 reversal
- 2012: later-break falsification, if space permits

**Caption/note requirements:**

- Unit: ATT in absolute UNGA ideal-point distance to China.
- Lower values mean convergence toward China.
- Treatment definition: China becomes Brazil's largest export destination.
- 2003/2005 samples are truncated before 2009.
- Uncertainty: placebo-based SE and p-values.
- Interpretation: timing falsifications, not equivalence tests.
- Source: Goal 3 and Goal 5 reports.

#### Main Table 2: Brazil outcome robustness and interpretation

**Action:** Add a compact table or integrate into the Brazil results table if space is tight.

**Purpose:** Prevent the paper from depending solely on one ideal-point-distance metric while narrowing the claim to selective UNGA convergence.

**Preferred columns:**

- Outcome / diagnostic
- Unit
- Estimate or pre-post difference
- Causal status
- Interpretation

**Rows to include:**

- Main absolute distance to China: ATT about `-0.264`, placebo SE about `0.123`.
- Relative distance China-minus-US: estimate about `-0.521`.
- Annual agreement with China: estimate about `0.078`.
- Annual agreement China-minus-US: estimate about `0.066`.
- Resolution-level identical vote share: overall change about `+3.8` p.p. (descriptive).
- Human rights vs non-human-rights: about `+7.5` p.p. vs `+2.7` p.p. (descriptive).

**Caption/note requirements:**

- Separate country-year SDiD outcomes from resolution-year diagnostics.
- State that resolution-level rows are descriptive and not causal estimates.
- State that agreement measures are more sensitive to agenda composition than ideal points.
- Source: Goal 6 final report.

#### Main Table 3: Cross-country scope-probe estimate

**Action:** Replace the current multi-estimator Table 3 with one main table centered on the audited switching-treatment `fect` IFE estimator.

**Purpose:** Present the cross-country panel as a scope probe without making C&S/PanelMatch co-primary.

**Preferred columns:**

- Estimator: `fect` IFE with covariates
- Treatment type: switching
- ATT
- Bootstrap SE
- 95% CI and/or p-value, if reported by the audited object
- N country-years
- Treated units and/or treated spells
- Control units
- Covariates
- Latent factors selected by cross-validation (`r_cv`)
- Panel window

**Caption/note requirements:**

- Unit: ATT in absolute UNGA ideal-point distance to China.
- Treatment: indicator equals 1 when China is currently the country's largest export destination and turns off when China loses that position.
- Uncertainty: bootstrap; state number of replications and clustering if used.
- Estimand: average effect for treated observations in the switching panel.
- State that C&S absorbing-treatment estimates are appendix sensitivity checks because they estimate a persistent-treatment subset.
- Source: Goal 7 report / audited targets.

### Tables to move to appendix or revise there

#### Original descriptive-statistics table

**Action:** Move to appendix.

**Purpose:** Sample description, not main evidence.

**Revision:** Ensure variables, windows, and treatment definition are current. If the table includes variables from multiple designs, label which design each column belongs to.

#### Full donor weights and covariate balance

**Action:** Appendix.

**Purpose:** Support the Brazil counterfactual without crowding the main text.

**Preferred columns:** donor country, SDiD weight, pre-treatment outcome mean, key covariate balance if available. Add compact main-text sentence summarizing top weights and fit.

**Source:** Goal 5.

#### Donor-pool sensitivity table

**Action:** Appendix, unless a sensitivity directly changes the conclusion.

**Rows:** Latin America-only donor pool; leave-one-high-weight-donor-out; exclusion of donors with relevant China top-rank reversals; exclusion of donors with obvious post-2009 China shocks if available.

**Source:** Goal 5.

#### H2 treated-spell table

**Action:** Appendix, with a short main-text mention if needed.

**Columns:** country, ISO3, treatment year, displaced partner, U.S.-displacement indicator, incumbent tenure, treated years, switching status.

**Purpose:** Document the H2 scope condition and exploratory heterogeneity.

**Source:** Goal 4.

#### H2 subgroup / exploratory heterogeneity table

**Action:** Appendix.

**Purpose:** Show that U.S.-displacement heterogeneity is exploratory and not confirmatory.

**Preferred rows:** U.S.-displacement subgroup, non-U.S.-displacement subgroup, U.S. minus non-U.S. contrast, with SE/p-value where available. Include Goal 4 warning that inference is exploratory.

#### C&S absorbing-treatment estimates

**Action:** Appendix.

**Purpose:** Sensitivity for persistent-treatment subset, not same estimand as `fect` switching.

**Note:** Explicitly state that countries with switching treatment are excluded from the treated subset rather than treated as controls.

#### PanelMatch ATT/ART table

**Action:** Appendix.

**Purpose:** Diagnostic/sensitivity for entry and exit; generally noisy.

#### Leave-one-out cross-country table

**Action:** Appendix.

**Purpose:** Influence diagnostic; not independent causal evidence.

#### NLP validation table and classification prompt

**Action:** Appendix.

**Purpose:** Measurement documentation for media salience; Goal 8 will later improve it.

#### Agenda decomposition and common-support tables

**Action:** Appendix.

**Purpose:** Support the Goal 6 caveat that resolution-level convergence is partly issue-specific and agenda-composition-sensitive.

## Figures

Keep only figures that are necessary for the main argument. A good target is four main-text figures: rank-versus-volume diagnostic, Brazil SDiD fit, Brazilian media salience, and cross-country dynamic scope-probe figure.

### Main-text figures

#### Main Figure 1: Brazil rank-versus-volume diagnostic

**Action:** Add or replace existing export-share-only figure with the Goal 3 figure plotting China's export share, China's ordinal rank, and China-over-second margin around 2009.

**Purpose:** Visually show that export share was growing before 2009, but rank-1 status switched in 2009.

**Caption/note requirements:**

- Unit: export share in percent; rank is ordinal; margin is export-value difference or signed margin as defined in Goal 3.
- Window: around 2000--2012 or the exact Goal 3 window.
- Treatment definition: China becomes Brazil's largest export destination in 2009.
- State that this is descriptive, not a causal estimate.
- Source: `fig_goal3_brazil_rank_volume_2000_2012.png/pdf` and Goal 3 report.

#### Main Figure 2: Brazil SDiD fit

**Action:** Keep the Brazil vs synthetic fit figure, revised for clean formatting and caption. This replaces raw descriptive trajectory figures as the main evidence figure.

**Purpose:** Show pre-treatment fit and post-treatment gap.

**Caption/note requirements:**

- Unit: absolute UNGA ideal-point distance to China.
- Lower values mean convergence toward China.
- Time window: state exact years used in the SDiD plot.
- Treatment definition: China becomes Brazil's largest export destination in 2009.
- Uncertainty is not plotted; refer to table for placebo-based SE/p-value.
- State that the plotted post-treatment gap is interpreted as an average post-treatment reduced-form effect, not a one-year break.

#### Main Figure 3: Brazilian media salience

**Action:** Keep one clean media figure. Preferred: a disaggregated China-headlines figure separating China-Brazil trade from Chinese economy, diplomacy/relations, and non-economic categories. If total China salience and trade-share salience are essential, combine them into a compact multi-panel figure; otherwise move the extra plots to the appendix.

**Purpose:** Show that post-2009 salience shifts toward bilateral trade coverage.

**Caption/note requirements:**

- Unit: count or share of China-related headlines, depending on panel.
- Window: 2000--2014 or exact corpus window.
- Treatment definition: 2009 rank reversal in Brazil's export-destination hierarchy.
- State that this is descriptive media-salience evidence, not causal evidence that media changed UNGA votes.
- Source: media/NLP section; Goal 8 will later refine documentation.

#### Main Figure 4: Cross-country dynamic scope-probe figure

**Action:** Keep one dynamic `fect` IFE figure. Prefer the entry-aligned dynamic treatment-effect plot from the main `fect_ife_china_top_cov` specification if available. Do not keep placebo, carryover, and equivalence panels in the main text unless the final Goal 7 audit says they are essential.

**Purpose:** Show whether the cross-country panel has a post-entry pattern consistent with the Brazil result.

**Caption/note requirements:**

- Unit: effect on absolute UNGA ideal-point distance to China.
- Time axis: periods since treatment entry.
- Treatment definition: China is currently the largest export destination; treatment turns off when China loses that position.
- Uncertainty: bootstrap confidence intervals; state replications and clustering if true.
- State that the figure is a scope probe, not mechanism evidence.
- Source: Goal 7 report / audited targets.

### Figures to move to appendix or drop

#### Current DAG figure

**Action:** Move to appendix or delete. If kept, revise treatment wording and caption so it does not imply the design identifies every arrow.

#### Raw ideal-point trajectories for Brazil, China, and the United States

**Action:** Move to appendix as descriptive background.

#### Brazil-China raw distance with separate OLS fits

**Action:** Move to appendix or drop. If kept, remove embedded “Figure 1” text inside the plot and state clearly that it is descriptive only.

#### Export share to China over time

**Action:** Replace in main text with Goal 3 rank-versus-volume figure; move old export-share-only plot to appendix or drop.

#### Top-10 donor trajectory plot and donor-weight plots

**Action:** Move to appendix. Keep a compact donor summary in main text.

#### Latin America-only donor figures

**Action:** Move to appendix and fix unresolved labels such as `(#fig:plot latam)` and `(#fig:plot weight latam)`.

#### Media figures beyond the main salience figure

**Action:** Move extra total-count/share/trigram figures to appendix unless they are combined into a single concise main figure.

#### Exit-aligned gap plot

**Action:** Appendix unless Goal 7 audit says it changes the main conclusion. In main text, summarize exit evidence as imprecise and diagnostic.

#### PanelMatch figure

**Action:** Appendix.

#### Raw treated-country panel figure

**Action:** Appendix. It is useful for heterogeneity but too large for the main text.

#### C&S dynamic plot

**Action:** Appendix.

#### Equivalence-test figure

**Action:** Appendix. Fix caption/p-value mismatches before retaining.

#### Outcome-robustness issue-area figures

**Action:** Appendix unless one compact figure is needed to justify the narrowed claim. Prefer a compact main table over multiple main figures.

#### NLP prompt/sample-classification figure

**Action:** Appendix or drop. The main text should not include prompt screenshots or random classification samples.

## Appendix Relocation Map

Use this map when moving material out of the main text. Preserve the material if it is useful for auditability, but do not let it dominate the submission narrative.

### Appendix A: Data, variables, and estimator details

Move here:

- Detailed DiD, SCM, and SDiD equations.
- Formal `fect`, C&S, and PanelMatch estimator details.
- Full covariate construction.
- Full descriptive statistics table.
- Treatment-definition audit details if not already integrated elsewhere.

### Appendix B: Brazil SDiD diagnostics and donor-pool checks

Move here:

- Full donor-weight table.
- Donor-weight plots.
- Top-10 donor trajectory plot.
- Covariate balance table.
- Latin America-only donor-pool specification.
- Leave-one-high-weight-donor-out sensitivity.
- Donor contamination exclusions.
- Full placebo-in-space distribution if available.
- Full rank-versus-volume diagnostic outputs not in the main table.

### Appendix C: Outcome robustness and issue-area diagnostics

Move here:

- Alternative country-year outcome tables.
- Resolution-year annual similarity table.
- Issue-area pre/post table and figure.
- Human-rights versus non-human-rights diagnostic.
- Agenda-composition decomposition.
- Common-support table for issue areas.

The main text should only summarize the implication: robustness reduces dependence on one ideal-point metric but narrows the substantive claim to selective UNGA convergence.

### Appendix D: Brazilian media/NLP documentation

Move here:

- Full LLM prompt.
- Classification label set and examples.
- Random headline sample.
- Validation table / confusion matrix.
- Trigram discussion.
- “Bate” headline examples.
- Details on prompt engineering and refusals.
- Elite-statement examples if too long for main text.

Do not expand this appendix into a new Goal 8 project. Goal 8 will later strengthen reproducibility.

### Appendix E: Cross-country scope-probe diagnostics

Move here:

- `fect` no-covariate benchmark.
- FE/placebo/equivalence diagnostics.
- Carryover and exit diagnostics.
- C&S absorbing-treatment estimates and dynamic figure.
- PanelMatch ATT/ART table and figure.
- Leave-one-out table.
- Raw treated-country panels.
- Treated-spell table with displaced partner and tenure.
- H2 exploratory subgroup estimates.
- Cross-country entry share and margin diagnostics from Goal 3.

### Appendix F: Source and documentation notes

Move or add here:

- Documentation for factual claims such as “the United States was Brazil's leading trade partner for roughly eight decades.” Use existing trade data notes or primary sources already in the repository where possible. If no source is available, flag the claim for author verification rather than adding a broad new data-collection task.

## Terminology and Claim Discipline

### Standard terms

Use these terms consistently:

- **Largest export destination / top export destination:** the empirical treatment in Brazil and the cross-country panel.
- **Top trade partner:** allowed only as shorthand for the publicly salient Brazilian event when supported by contemporary coverage and the Goal 2 note. Do not use it in estimand definitions unless the model actually uses total trade.
- **Rank reversal:** China moves into the number-one position in the export-destination hierarchy.
- **Trade-status cue / rank-threshold cue:** theoretical language for why the ordinal event matters.
- **UNGA voting convergence toward China:** the main empirical outcome interpretation.
- **Foreign-policy alignment:** broader concept; use only when explicitly saying UNGA voting is one observable dimension of it.
- **Reduced-form effect:** the Brazil SDiD estimate.
- **Media salience / attention evidence:** the Folha evidence.
- **Scope probe:** the cross-country panel.
- **Exploratory heterogeneity / scope condition:** the H2/U.S.-displacement evidence.

### Replace overbroad or casual wording

Use the following replacements throughout `paper_v4.Rmd`:

| Avoid | Replace with |
| --- | --- |
| “foreign-policy realignment” in empirical claims | “UNGA voting convergence toward China” |
| “realignment of foreign policy orientation” | “reduced UNGA ideal-point distance to China” |
| “causal effect on Brazil's foreign policy orientation” | “reduced-form effect on Brazil's UNGA ideal-point distance to China” |
| “cross-country estimate confirms” | “cross-country evidence is consistent with” / “provides suggestive scope evidence” |
| “direct evidence for H2” | “exploratory heterogeneity evidence for the U.S.-displacement scope condition” |
| “the exit effects rule out coercion/bandwagoning” | “exit diagnostics weigh against large persistent-effect accounts but do not identify salience” |
| “contrary to Mercer, prestige matters” | “the evidence speaks to debates over whether status gains have observable behavioral consequences” |
| “wholesale foreign-policy realignment” | “selective issue-specific UNGA convergence” |
| “media evidence shows the mechanism” | “media evidence supports the attention/salience implication” |
| “trade partner” in estimator/caption notes | “largest export destination” |
| “the paper empirically document” | “the paper empirically documents” or, preferably, “I first examine” / “We first examine” depending manuscript voice |

### Voice consistency

The current manuscript mixes first-person singular, first-person plural, and impersonal phrasing. Pick one voice and apply it consistently. If the manuscript is single-authored, first-person singular is acceptable, but many political science articles use “I” sparingly. If the current Rmd mostly uses “we,” keep “we” for consistency. Do not mix “I first examine” with “we estimate” in adjacent paragraphs.

### Goal 2 consistency

Do not reopen the treatment-definition issue. The paper already has a note/footnote clarifying the shorthand. Goal 9 should only ensure every empirical table, figure note, hypothesis, and estimator description matches that note.

Correct pattern:

> “The treatment equals one from 2009 onward, when China became Brazil's largest export destination.”

Acceptable Brazil public-salience wording:

> “Contemporary coverage often described the event as China becoming Brazil's top trade partner; empirically, the treatment used here is largest-export-destination status.”

Incorrect pattern:

> “Treatment equals one when China becomes the top trade partner,” if the treatment is actually export-destination based.

## Cross-References, Captions, and Presentation Defects

Run this checklist directly on `paper_v4.Rmd`.

### Known wording defects to search and fix

Search for these exact strings or variants:

```sh
rg -n "specially|the paper empirically document|Firstly|toe reflect|Wolrd|two thousands|anonymous reviewer" paper_v4.Rmd
```

Required fixes:

- `specially` → `especially`
- `the paper empirically document` → `the paper empirically documents`, or rewrite the sentence
- `Firstly I consider` → `I first examine` or voice-consistent equivalent
- `toe reflect` → `to reflect`
- `Wolrd Trade Organization` → `World Trade Organization`
- `two thousands` → `2000s`
- Remove “We thank an anonymous reviewer...” from any submission version

### Known figure/table defects

Search for:

```sh
rg -n "\\(#fig:|#fig:plot|Table 4|Figure 19|Figure 1|\\?\\?|@fig|@tbl|ref\{" paper_v4.Rmd
```

Fix the following known problems:

- Remove embedded “Figure 1” text inside the current Brazil-China distance plot.
- Resolve labels like `(#fig:plot latam)` and `(#fig:plot weight latam)`.
- Locate or remove any missing `Table 4` references.
- If Figure 19 remains in the appendix, ensure its caption p-values match the plotted p-values.
- Ensure every figure/table reference points to an existing label.
- Ensure no duplicate chunk labels exist after moving chunks.
- Ensure table numbering is sequential after relocating tables.

### Treatment-definition checks

Run:

```sh
rg -n "top trade partner|top partner|largest export destination|top export destination|displaced the US|USA regains|China loses" paper_v4.Rmd
```

Then verify:

- Estimator descriptions use “largest export destination.”
- Figure/table notes use “largest export destination.”
- “Top trade partner” appears only in public-salience/framing contexts or in the Goal 2 note.
- Cross-country treatment turns off when China loses the largest-export-destination position, not only when the United States regains it, unless a specific older U.S.-replacement-only specification is explicitly labeled as an appendix robustness check.

### Claim-strength checks

Run:

```sh
rg -n "foreign-policy realignment|realignment|confirms|direct evidence|rule out|Mercer|prestige|mechanism" paper_v4.Rmd
```

Then verify:

- “Foreign-policy realignment” is not used to describe estimated effects unless immediately qualified as UNGA voting convergence.
- “Confirms” is not used for cross-country evidence.
- “Direct evidence for H2” is removed.
- “Rule out” is not used for alternative explanations that remain plausible.
- Mercer/status claims are softened.
- Media evidence is described as salience/attention evidence, not proof that media caused voting change.

### Caption/note checklist

Every main-text table and figure note should include, as applicable:

- Unit of analysis or plotted quantity.
- Outcome unit.
- Time window.
- Treatment definition.
- Uncertainty measure.
- Cluster level, if relevant.
- Whether the figure/table is causal, robustness, diagnostic, or descriptive.

Examples:

For SDiD tables:

> Unit = Brazil-year. Outcome = absolute UNGA ideal-point distance to China. Lower values indicate convergence toward China. Treatment = China becomes Brazil's largest export destination in 2009. Standard errors and p-values are placebo-based. The 2003 and 2005 tests are timing falsifications for rapid export growth without rank-1 status, not equivalence tests.

For cross-country `fect`:

> Unit = country-year. Outcome = absolute UNGA ideal-point distance to China. Treatment = 1 when China is currently the country's largest export destination and 0 otherwise. Treatment is switching and turns off when China loses the top export-destination position. Uncertainty = bootstrap [state replications and clustering after audit]. This estimate is a scope probe, not a mechanism test.

For media:

> Unit = Folha de S.Paulo headline/article count or share. Window = 2000--2014. Treatment marker = 2009 Brazil rank reversal. The figure is descriptive salience evidence and does not identify the effect of media attention on UNGA votes.

### Formatting and rendering defects

Check for broken characters in the PDF and source, especially:

- `China-related`
- `external-sector`
- `three-word`
- `São Paulo`
- `Folha de S.Paulo`
- author names with broken spaces, such as `V oeten` or `Y an`
- long dashes or special characters that render incorrectly
- math expressions with broken hats/subscripts after moving equations

Fix in source, not only in the rendered PDF.

## What Goal 1 Should Do Later

After Goal 9 is implemented and the main evidence architecture is stable, Goal 1 should rewrite the abstract and introduction around the final claim ladder:

1. **Core question:** Do rank thresholds in trade hierarchies affect UNGA voting convergence beyond smooth trade exposure?
2. **Theory:** Crossing the number-one export-destination threshold creates a publicly legible status cue, especially in high-salience cases such as Brazil's 2009 U.S.-displacement episode.
3. **Brazil design:** SDiD estimates a reduced-form post-2009 effect on UNGA ideal-point distance to China.
4. **Rank-versus-volume:** 2003 and 2005 growth/lower-rank placebos and Goal 3 diagnostics distinguish the rank threshold from smooth export growth.
5. **Outcome scope:** Robustness checks support the direction of convergence but narrow the substantive claim to selective UNGA convergence, especially in human rights.
6. **Media evidence:** Folha evidence supports the salience/attention implication in Brazil, not the full causal mechanism.
7. **Cross-country evidence:** The panel is a scope probe with a switching-treatment `fect` estimator; it is not a second main identification design and does not conclusively test H2.

Goal 1 should not revive broad language such as “foreign-policy realignment” or “status gains are not illusory” unless carefully qualified. It should use the final tables and figures selected under Goal 9 as the introduction roadmap.

## Validation Checklist

Before stopping, complete these checks.

### 1. Required files and source checks

- Confirm `paper_v4.Rmd` was the edited source.
- Confirm the final Goal 6 report was present and used: `quality_reports/goal6_outcome_robustness/2026-05-18_goal6_outcome_robustness_report.md`.
- Confirm no edits were made to `_targets.R`, `_targets/`, or `_targets.yaml`.
- Confirm `targets::tar_make()` was not run.

### 2. Main-text architecture check

The main text should have this structure, with only minor naming variation:

- Introduction
- Theory and hypotheses
- Data and design
- Brazil SDiD evidence
- Brazilian media salience
- Cross-country scope probe
- Conclusion

The main text should not contain long methods-appendix material. The cross-country section should not include PanelMatch, C&S dynamics, leave-one-out, raw treated panels, and equivalence-test details except as one-sentence appendix references.

### 3. Search checks

Run:

```sh
rg -n "specially|the paper empirically document|Firstly|toe reflect|Wolrd|two thousands|anonymous reviewer" paper_v4.Rmd
rg -n "\\(#fig:|#fig:plot|\\?\\?|Table 4|Figure 19" paper_v4.Rmd
rg -n "foreign-policy realignment|confirms|direct evidence for H2|rule out|Mercer|prestige is illusory" paper_v4.Rmd
rg -n "top trade partner|top partner|largest export destination|top export destination|displaced the US|USA regains" paper_v4.Rmd
rg -n "PanelMatch|Callaway|Sant.?Anna|leave-one-out|raw treated|trigram|bate|ChatGPT classification|prompt" paper_v4.Rmd
```

Expected results:

- The typo search returns no remaining defects.
- Cross-reference search returns only valid references.
- Claim-strength search returns no unsupported broad claims.
- Treatment-definition search shows intentional usage: estimator/caption language is “largest export destination”; “top trade partner” appears only in the Goal 2 note or public-salience contexts.
- Diagnostic-method search shows appendix material or short main-text references only.

### 4. Table and figure checks

For every main-text table and figure:

- It is referenced in the prose.
- It has a unique label.
- It has a complete caption and note.
- It states the correct treatment definition.
- It states units and uncertainty where relevant.
- It is in the correct section.
- It is not redundant with another main-text object.

For every appendix table and figure:

- It has a label and caption.
- It is referenced at least once in the main text or appendix prose, or it is removed.
- Its note does not contradict main-text treatment definitions.

### 5. Claim-ladder checks

The manuscript should satisfy all of the following:

- Brazil SDiD is presented as the main reduced-form evidence.
- The 2003 and 2005 placebos are framed as rank-versus-volume timing tests.
- Outcome robustness is used to narrow the substantive claim to selective UNGA convergence.
- Media evidence is bounded to salience/attention.
- Cross-country panel is presented as a scope probe.
- H2/U.S.-displacement is a scope condition or exploratory heterogeneity claim, not a confirmed result.
- C&S is not presented as the same estimand as switching `fect`.
- Exit/carryover diagnostics are not presented as proof of salience.

### 6. Rendering checks

Render the manuscript once using the repository's normal R Markdown/PDF rendering command. Do not run `targets::tar_make()`.

After rendering:

- Inspect the first three pages for treatment terminology and claim strength.
- Inspect all table/figure captions.
- Confirm no `??`, unresolved labels, or raw chunk labels appear.
- Confirm no embedded label text remains inside plots.
- Confirm appendix material appears in the appendix, not the main text.
- Confirm the word count is materially lower than the prior 14,500-word version. A reasonable target after Goal 9 is roughly 10,000--11,500 main-text words, depending on journal formatting and how much appendix material remains.

### 7. Stop condition

Stop only when a skeptical reader can see, without reading the appendix, the paper's disciplined evidence ladder:

> Brazil provides the main reduced-form SDiD evidence of post-2009 UNGA voting convergence toward China; rank-versus-volume diagnostics distinguish the 2009 threshold from smooth export growth; outcome robustness narrows the claim to selective UNGA convergence; Folha evidence supports the Brazilian salience implication; and the cross-country panel is a cautious scope probe rather than a second decisive identification design.
