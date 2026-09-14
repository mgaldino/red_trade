# Bounded adjudication: corpus, votes, Figure 8, and bibliography

Date: 2026-09-14  
Scope: comments 4, 21, 27, 35, and 36 only  
Configuration requested: Sol, high  
Disposition: `READY_FOR_IMPLEMENTATION`, subject to the item 4 target-first gate described below

## Input identity and boundary

- Reviewed manuscript: `paper_v4.Rmd`, SHA-256 `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`.
- Frozen manuscript baseline: `execution/baseline/paper_v4.Rmd`, byte-identical to the reviewed manuscript.
- Reviewed PDF: `output/paper_v4.pdf`, SHA-256 `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`.
- Frozen PDF baseline: `execution/baseline/paper_v4.pdf`, byte-identical to the reviewed PDF.
- Review selection: `items_to_address.md`, SHA-256 `d0220df748585215fc3ce14786e555546134d1e25534470ee153b1872437ea25`.
- Review report: `feedback-the-foreign-policy-impact-of-trade-based-status-ga-2026-09-14.md`, SHA-256 `eb7dc9488e3b6726cee0ddf232250be18f09291797e2a85470b67637af58b88a`.
- Bounded packets: `execution/packets/corpus_votes.txt`, SHA-256 `da2f79f10f4ebbe085a5a3b85abe3f22fccebf0aa5e5931ea8809ce59bf54b24`; `execution/packets/bibliography.txt`, SHA-256 `8fa1347b46ba5764a70c469ebad894403c32e56db035c86c25df2edd98727703`.
- Repository state inspected at Git commit `8591fea`; unrelated pre-existing working-tree changes were left untouched.

No argument contract was required for these localized claims. I did not execute or modify `targets`, reestimate a model, call a classification API, change data, edit the manuscript, commit, signal a process, or communicate externally. Items 7 and 8 remain governed by `execution/corpus_pipeline.md` and `.json`; the item 4 proposal below does not replace or overwrite their classification-provenance proposal.

## Evidence classes

### Static inspection

- Read only the selected comments, bounded packets, localized manuscript passages, Figure 8 and its producer chunk, the relevant bibliography records, and the specific corpus/vote producer functions.
- The preserved Folha retrieval function queries the site search for `china`, sorts oldest first, iterates offsets `1, 26, ..., 49,976` in five blocks of 400 pages, and extracts the displayed headline and timestamp (`scripts/functions.R:20-50`; `_targets.R:62-67`).
- The preserved classification producer applies `distinct(title)`, then retains titles matching `China|chin(ês|esa)`, and later joins classifications to headlines by exact title (`scripts/chatgpt_api.R:40-42,91-98`).
- The active media counterfactual uses the archived `data/folha_classificado.rds`, not a live retrieval target (`_targets.R:752-759`; `scripts/functions.R:5598-5620`).
- Vote scores are `no = -1`, `abstain = 0`, and `yes = 1`; the code retains resolutions with recorded and different China/U.S. scores and constructs the signed difference between absolute ordinal distances (`scripts/functions.R:6555-6561,6634-6675`).
- Figure 8 is produced from `ideal_point_all` for Brazil and China over 1990-2022 (`paper_v4.Rmd:1309-1328`). Visual inspection of PDF page 44 shows a jagged China series and sustained post-2009 movement in Brazil.

### Computed verification on existing files

These were read-only checks made outside `targets`. They are adjudication evidence, not new paper outputs.

- `data/raw/network_caches/folha_scrape_cache.rds` contains 14,589 rows, 14,589 distinct titles, no exact duplicate rows, no missing title/timestamp/date, and dates from 2000-05-14 through 2014-07-28. All cached titles satisfy the preserved China-title filter.
- The archived classification and final files each contain 14,589 distinct titles. Exact title-set comparisons produce zero cache-to-classification, classification-to-cache, cache-to-final, and final-to-cache losses; an exact-title join produces 14,589 rows and zero timestamp/date disagreements.
- The preserved current classification loop would cover rows 1-14,500 in complete 500-row blocks and leave the final 89-row partial block uncovered. This is evidence that current producer code is not a sufficient record of the historical classification execution; it does not contradict the complete 14,589-row archived classification. Items 7 and 8 already adjudicate that provenance defect.
- The inspected `un_votes` object has only the observed vote levels `yes`, `no`, and `abstain`; absence and nonparticipation are not explicit vote categories in that table.
- For the Figure 8 source series, Brazil's mean ideal point changes from -0.156 in 2005-2008 to -0.481 in 2009-2012, whereas China's changes from -0.704 to -0.769. China's mean absolute annual change over 2005-2012 is 0.121, compared with 0.073 for Brazil. These descriptive checks support the distinction between stability in China's period average and year-to-year volatility. No variance decomposition or attribution of bilateral-distance changes was computed.

### New analysis

None. No new inferential result, model, corpus reconstruction, retrieval audit, variance attribution, or paper-facing analytical output was created. Any new numerical corpus audit intended for the manuscript remains gated by a target-first specification.

## Adjudication

### Item 4 — `CONFIRMED`

**Localized claim and defect.** The paper says that it examines Folha coverage from 2000 to 2014 and describes headline classification (`paper_v4.Rmd:1057-1085`; appendix at `paper_v4.Rmd:1978-2070`), but it does not state the retrieval rule, actual archived date coverage, treatment of duplicate or missing records, or observed join losses. The boundary years are partial, and the archive cannot establish historical search completeness.

**Evidence.** The code and archived files establish the preserved query configuration, post-retrieval headline uniqueness, zero missingness in the stored cache, and zero title-set join loss across the stored cache/classification/final files. They do not establish the historical collection date, pre-deduplication duplicate count, page-level request failures or empty pages, the search engine's stated result total, or omissions from Folha's archive. The stored cache is already title-unique and therefore cannot be treated as raw page-level retrieval evidence.

**Assessment.** The reporting defect is confirmed. Historical completeness claims remain unsupported and should not be added. A manuscript-facing count/date/join audit is `needs_design`: first register the three archived files as file-tracked inputs and create a target that emits their hashes, row counts, minimum/maximum dates, missingness, exact duplicates, title-set differences, exact-join losses, and year support. That target should feed the same provenance manifest proposed for items 7 and 8, with unavailable fields such as collection date and raw page logs explicitly recorded as unavailable. No such target was added or run here.

**Exact minimal proposal, gated until that target reproduces the figures.** Insert after “This diagnostic does not measure the frequency of explicit rank labels” at `paper_v4.Rmd:1059`:

> The archived retrieval cache contains 14,589 unique search-result headlines dated May 14, 2000 through July 28, 2014. The preserved retrieval code queries Folha's site search for `china`, sorts results from oldest to newest, requests 2,000 pages in five 400-page blocks, and extracts each displayed headline and timestamp. Before classification, the preserved producer retains one record per exact headline and keeps titles containing `China`, `chinês`, or `chinesa`. In the archived files, titles and dates are complete, no exact duplicate rows remain, and all 14,589 cached titles match both a classified title and the final analysis file. The archive does not preserve the pre-deduplication page responses, page-level failures or empty-page checks, the search engine's result total, or the collection date, so duplicate removals and archive-level omissions cannot be quantified. The 2000 and 2014 counts cover only May--December and January--July, respectively.

This insertion is independent of, and should precede rather than replace, the appendix classification-provenance correction already proposed for items 7 and 8.

### Item 21 — `CONFIRMED`

**Localized claim and defect.** The outcome paragraph identifies distance to China relative to the United States and gives the sample size, but does not define the vote coding or formula and does not say what happens to country-resolution pairs without recorded votes (`paper_v4.Rmd:971-977`).

**Evidence.** The producer assigns -1/0/1 to no/abstain/yes. For resolution (r), it calculates `abs(country_score - china_score) - abs(country_score - usa_score)`. It includes only recorded yes/no/abstain country votes and requires recorded, different China and U.S. votes. Thus absence/nonparticipation is not coded as abstention; a country-resolution pair without a recorded yes/no/abstain vote is absent from the observed-vote sample.

**Assessment.** The omission is confirmed and the following prose-only clarification is `safe`; it changes neither the estimand nor the sample.

**Exact minimal replacement.** Replace the sentence beginning “Any human-rights tag...” at `paper_v4.Rmd:975` with:

> Votes are scored -1 for no, 0 for abstain, and 1 for yes. The outcome is $Y_{ir}=|s_{ir}-s_{Cr}|-|s_{ir}-s_{Ur}|$, where $s_{Cr}$ and $s_{Ur}$ are China's and the United States' scores; negative values indicate a vote closer to China. Country-resolution pairs without a recorded yes, no, or abstain vote -- whether because of absence, nonparticipation, or another reason -- do not enter the observed-vote sample. A resolution enters the China-U.S. divergent sample only when both China and the United States have recorded votes and their scores differ. Any human-rights tag places a resolution in the human-rights group; all remaining resolutions form the non-human-rights group.

### Item 27 — `CONFIRMED`

**Localized claim and defect.** The appendix says that “China remains comparatively stable” and that Brazil “accounts for most” of the movement in bilateral distance (`paper_v4.Rmd:1304-1307`). Figure 8 supports a smaller change in China's period average around 2009, but it also shows sizable annual volatility. The plot alone does not identify or decompose which country accounts for most variation in the bilateral distance.

**Evidence.** Static inspection of Figure 8 (PDF p. 44) and the descriptive checks above agree: China changes less in period-average location, while its year-to-year series is more volatile over 2005-2012; Brazil moves persistently toward China's location after 2009. No variance-attribution calculation exists in the inspected evidence, and none was performed here.

**Assessment.** The unqualified interpretation is confirmed as defective. A narrower visual description is `safe` and avoids introducing a new analytical claim.

**Exact minimal replacement.** Replace the second sentence at `paper_v4.Rmd:1306` with:

> This diagnostic clarifies the interpretation of the absolute-distance outcome used in the main SDiD design: China's average position changes little around 2009 despite sizable year-to-year volatility, while Brazil shows a sustained post-2009 movement toward China.

### Item 35 — `CONFIRMED`

**Localized claim and defect.** The literature sentence says that the cited interdependence literature studies “only the effects of trade flows” (`paper_v4.Rmd:133`). Urdinez et al. do not study trade flows alone.

**Primary-source evidence.** The article abstract states that it analyzes “foreign direct investments, bank loans, and international trade” and reports results for Chinese state-owned-enterprise investment, bank loans, and manufacturing exports: Urdinez et al., *Chinese Economic Statecraft and U.S. Hegemony in Latin America*, article p. 3, [publisher PDF via DOI](https://onlinelibrary.wiley.com/doi/pdf/10.1111/laps.12000) (DOI 10.1111/laps.12000). The local bibliography record identifies the same DOI (`references.bib:1319-1334`).

**Assessment.** The “only trade flows” characterization is false for this citation. The shared replacement under items 35/36 is `safe` and leaves the surrounding rationality argument, including unselected comment 3, untouched.

### Item 36 — `CONFIRMED`

**Localized claim and defect.** The same “only the effects of trade flows” sentence also mischaracterizes Kastner and Pearson (`paper_v4.Rmd:133`).

**Primary-source evidence.** The article opens by defining China's economic ties in terms of “trade, investment, and aid” (p. 18), identifies sanctions, foreign aid, foreign direct investment, and state-owned enterprises in its keywords and mechanisms, discusses economic tools that “reward compliance or punish non-compliance” (pp. 24-27), and develops the role of firms as state agents (pp. 30-35): Kastner and Pearson, *Exploring the Parameters of China's Economic Influence*, [publisher page](https://link.springer.com/article/10.1007/s12116-021-09318-9), [publisher-version full text at PubMed Central](https://pmc.ncbi.nlm.nih.gov/articles/PMC7934344/) (DOI 10.1007/s12116-021-09318-9). The local bibliography record identifies the same DOI (`references.bib:799-811`).

**Assessment.** The characterization is false for this citation. One shared sentence correction resolves items 35 and 36 without changing the paper's broader rationality claim.

**Exact shared replacement for items 35 and 36.** Replace only the second sentence of the paragraph at `paper_v4.Rmd:133`:

> **Old:** Most of the literature on the effects of interdependence implicitly or explicitly assumes this hyperrationalist perspective and studies only the effects of trade flows [@flores-macias_kreps2013; @urdinez_etal2016; @kastner_pearson2021].
>
> **New:** Most of the literature on the effects of interdependence implicitly or explicitly assumes this hyperrationalist perspective and studies how trade and other economic ties, including investment, lending, aid, firms, and coercive economic tools, shape foreign policy [@flores-macias_kreps2013; @urdinez_etal2016; @kastner_pearson2021].

The preceding sentence (“If everyone is perfectly rational...”) and the following prediction remain unchanged.

## Verdict

All five selected findings are `CONFIRMED`. Items 21, 27, and the shared 35/36 correction are safe localized prose changes supported by existing evidence. Item 4 is a confirmed reporting defect, but its paper-facing numerical disclosure must be generated by the target-first audit specified above; historical retrieval completeness, collection date, pre-deduplication duplicate counts, and archive omissions remain unavailable. No manuscript change is made or authorized by this adjudication artifact.
