# Adjudication of bibliography items 37–38

Checked: 2026-09-14T13:49:11-03:00  
Bounded packet: `execution/packets/bibliography.txt`  
Verdict: `READY_FOR_IMPLEMENTATION` for the narrow part of item 38 only

## 1. Source and artifact identity

- Frozen reviewed source: `execution/baseline/paper_v4.Rmd`, SHA-256 `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`.
- Current source: `paper_v4.Rmd`, the same SHA-256. `cmp` returned 0, so the current manuscript and frozen baseline are byte-identical.
- Rendered artifact: `output/paper_v4.pdf`, SHA-256 `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`. The cited passages appear on physical pp. 2–3.
- Selection record: `items_to_address.md`, SHA-256 `d0220df748585215fc3ce14786e555546134d1e25534470ee153b1872437ea25`, lines 40–41.
- Detailed review: `feedback-the-foreign-policy-impact-of-trade-based-status-ga-2026-09-14.md`, SHA-256 `eb7dc9488e3b6726cee0ddf232250be18f09291797e2a85470b67637af58b88a`, lines 64–84.
- No argument contract was required for this bounded bibliographic adjudication. The review quotations match the baseline and rendered PDF; there is no indication of truncation or conversion error.

## 2. Executive disposition

| Item | Status | Disposition |
|---|---|---|
| 37 | `REFUTED` | Retain the Strüver citation and sentence. Reversing the source direction as the reviewer suggests would misstate the evidence. |
| 38 | `PARTIAL` | The review invents language not found in the official abstract, but the undifferentiated citation list can imply that a critical review affirmatively adopts the manuscript's definition. Remove only `@macdonald_parent2021` from that citation cluster. |

Counts: 0 `CONFIRMED`, 1 `PARTIAL`, 1 `REFUTED`, 0 `UNRESOLVED`.

## 3. Item 37 — Strüver (2016)

**Candidate finding.** The review says Strüver demonstrates that economic ties cause diplomatic affinity and therefore contradicts the manuscript's reverse-causality concern.

**Manuscript locations.** `paper_v4.Rmd:137` states the reverse-causality concern. `paper_v4.Rmd:147` separately cites Strüver for UN General Assembly voting as a measure of foreign-policy similarity. The same text is in the frozen baseline; the first passage spans physical pp. 2–3 of the PDF.

**Primary-source evidence.**

- The final publication is Georg Strüver, “What Friends Are Made of: Bilateral Linkages and Domestic Drivers of Foreign Policy Alignment with China,” *Foreign Policy Analysis* 12(2), 170–191, DOI `10.1111/fpa.12050`. The [Oxford Academic record](https://academic.oup.com/fpa/article-abstract/12/2/170/2367626) was accessed 2026-09-14. Its abstract describes a logistic-regression study that explores several explanations. It reports correlations chiefly with shared regime characteristics and comparable political-globalization patterns, with an additional association for foreign aid; it does not claim a trade-identified causal effect.
- The locally available author working-paper version, GIGA Working Paper 209/2012, SHA-256 `73a53e5282a9b1e570e7f87dfde21dafbf08e747dcc44d8d35719400d91a44bc`, was inspected only at the abstract, design, relevant results, discussion, and conclusion. Physical p. 21 (printed p. 20) reports that the aid-project moving average correlates with foreign-policy similarity. Physical p. 23 (printed p. 22) says the buyer-power account is not supported and instead interprets political understanding as conducive to economic exchange. Physical p. 24 (printed p. 23) explicitly states that the study does not establish a causal link. Its dynamic model treats trade dependence as more plausibly a consequence of similarity that helps maintain it than as a prerequisite for its onset.

**Adjudication: `REFUTED`.** The reviewer collapses theory, association, and causal identification. Strüver discusses possible economic influence, but the results do not establish that trade causes alignment. The source directly entertains the manuscript's direction: prior political understanding or shared interests can support denser trade, while dense trade may help maintain affinity. The citation therefore supports a reverse-causality concern and does not contradict it.

**Proposed-fix assessment: `unsafe`.** No replacement is proposed. Rewriting the manuscript to say that Strüver establishes trade as the primary cause of diplomatic alignment would overclaim the study and invert its explicit caution.

## 4. Item 38 — MacDonald and Parent (2021)

**Candidate finding.** The review says the article's abstract rejects a relational definition and states that status is an attribute rather than a relation.

**Manuscript location.** `paper_v4.Rmd:139`; physical p. 3 of `output/paper_v4.pdf`. The sentence defines trade-based status relationally and includes `@macdonald_parent2021` in a compact supporting citation cluster.

**Primary-source and bibliographic evidence.**

- The exact publication is Paul K. MacDonald and Joseph M. Parent, “The Status of Status in World Politics,” *World Politics* 73(2), 358–391, DOI `10.1017/S0043887120000301`. The [Cambridge University Press record](https://www.cambridge.org/core/journals/world-politics/article/abs/status-of-status-in-world-politics/BF85C05AAB728662D3CA526CDF69DA60) was accessed 2026-09-14. The official abstract does not contain either phrase attributed to it by the reviewer. It instead describes a critical stocktaking: the field's consensus definition obscures tensions between standing and membership.
- An [author-affiliated Notre Dame page](https://ondisc.nd.edu/news-media/news/the-status-of-status-in-world-politics/), accessed 2026-09-14, reproduces the official abstract and summarizes the conceptual section. It describes valued attributes, states' positions on them, and different rights and responsibilities attached to high status; it says the article's dispute concerns standing versus membership and quantitative versus qualitative approaches. This is inconsistent with the review's alleged attribute-versus-relation quotation.
- The author's [publication list](https://sites.google.com/a/wellesley.edu/paul-k-macdonald/publications), accessed 2026-09-14, confirms the title, journal, issue, date, and coauthor.
- `synth-trade-china.bib:877–890` already has the correct title, authors, year, journal, volume, issue, pages, and DOI. DOI letter case is immaterial. No BibTeX edit is needed for item 38.

**Defect evidence.** MacDonald and Parent is a critical review of the consensus rather than an unqualified proponent of a single relational definition. Placing it inside a list syntactically introduced as research that “treats status as” the stated definition can imply endorsement and obscures the source's standing-versus-membership qualification.

**Refuting evidence.** The review's stated basis is false: the official abstract does not say that the authors “take issue with this new conventional wisdom” or “argue that status is an attribute, not a relation.” The source recognizes status positions and the field's collective-belief account while diagnosing conceptual tensions. The manuscript's relational definition is not itself refuted by this article.

**Adjudication: `PARTIAL`.** There is a narrow citation-fidelity issue, not the material theoretical contradiction alleged by the reviewer. The safest correction preserves the author's definition and removes only the ambiguous supporting citation.

**Proposed-fix assessment: `safe`.** Exact minimal replacement:

```text
OLD: [@paul_larson_wohlforth2014; @wolfRespectDisrespect2011; @duque_2018; @renshon2017; @gotz_2021; @macdonald_parent2021; @roren_2024; @roren2025_power_recognition; @wolfTakingInteractionSeriously2019]
NEW: [@paul_larson_wohlforth2014; @wolfRespectDisrespect2011; @duque_2018; @renshon2017; @gotz_2021; @roren_2024; @roren2025_power_recognition; @wolfTakingInteractionSeriously2019]
```

This proposal changes no prose, leaves the relational definition intact, and does not affect comments 35–36 or any unselected comment. Do not delete the BibTeX entry because it may be used elsewhere and the entry itself is bibliographically correct.

## 5. Verification boundary

- **Static inspection:** bounded packet; items 37–38 in the selection and detailed review; manuscript lines 137, 139, and 147; corresponding frozen-baseline lines; the two BibTeX records; localized PDF text.
- **Computed verification:** SHA-256 checks; byte comparison of current and frozen Rmd; PDF metadata and localized text extraction; localized extraction from the Strüver working paper.
- **Source verification:** publisher metadata/abstracts and author-affiliated publication material, accessed 2026-09-14.
- **New analysis:** none. No R code, `targets`, reestimation, data transformation, classification API, or new analytical paper output was run or created. Any future analytical addition remains subject to a target-first specification and is outside this adjudication.
- **Limitation:** the paywalled full text of MacDonald and Parent was not downloaded. The verdict separates what can be decided from the official publisher abstract and author-affiliated conceptual summary from the narrower inference that the undifferentiated citation cluster is avoidably ambiguous. No claim is made that the reviewer-supplied abstract quotation was found anywhere in the article.

