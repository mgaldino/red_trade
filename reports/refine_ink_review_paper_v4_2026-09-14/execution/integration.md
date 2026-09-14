# Manuscript integration record

Date: 2026-09-14

Role: sole manuscript integrator. This is an implementation record, not an independent scientific review.

## Isolated artifacts

- Frozen baseline: `execution/baseline/paper_v4.Rmd`
- Baseline SHA-256: `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`
- Candidate: `/private/tmp/refine-review-20260914/paper_v4.Rmd`
- Candidate SHA-256: `82c811def270d266f8ef4541d6fc8afecb6adfe980cda6260d84439714bb340c`
- Exact unified diff: `execution/integration.patch`
- Patch SHA-256: `64058bc13bdc76d02cd924e0721e36188c29f2458edbf3d92f4958b4a8bc2240`
- Diff size: 55 insertions and 48 deletions in the candidate Rmd.

The canonical `paper_v4.Rmd` remained byte-identical to the frozen baseline. `output/paper_v4.pdf` remained at SHA-256 `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`. No PDF was rendered.

## Item-by-item integration

| Item | Result | Implemented change and evidence | Dependency or explicit deferral |
|---:|---|---|---|
| 2 | Applied | Recast Table 20 as a nine-row diagnostic subset of a 14-country legacy source audit, disclosed its relationship to the 35-country current treated sample, defined `medium`, `Unknown`, countable sources, legacy entry windows, and shortened the table note. Evidence: `cross_country.json`, item 2; `orchestrator_decisions.md`. | No new source search. The 22 current treated countries outside the audit remain unaudited; Chile and Saudi Arabia retain legacy audit windows. |
| 4 | Applied, bounded | Added only qualitative documentation of the preserved Folha retrieval procedure, frozen classified input, missing historical completeness logs, and incomplete boundary-year coverage. Evidence: `corpus_votes_bibliography.json`, item 4; additional Sol-high adjudication in `orchestrator_decisions.md`. | Numeric corpus counts, exact dates, join-loss reporting, and annual coverage details remain deferred to the authorized targets-first provenance design. |
| 6 | Applied | Defined the 2004--2008 exposure baselines, the `x 2008--2009` interactions, the Pink Sheet price construction, standardization, and absorbed lower-order terms in prose adjacent to Table 5; shortened the note. Evidence: `sdid.json`, item 6. | Table 5 values and preferred fit are unchanged. Its separate targets-migration debt is not resolved by this prose fix. |
| 7 | Applied, bounded | Documented what the preserved producer specifies: model alias, temperature, slicing, parsing, exact-title join, and label normalization; distinguished configuration from historical execution. Evidence: `corpus_pipeline.json`, item 7; `orchestrator_decisions.md`. | No immutable model snapshot, complete request-response archive, rerun history, or provider-default record exists; exact historical re-execution is not claimed. |
| 8 | Applied, bounded | Relabeled the 100-headline result and table as unweighted agreement in a category-enriched sample; changed display column names; preserved the existing inline overall and category rates; stated limits on recall, corpus-wide accuracy, and temporal stability. Evidence: `corpus_pipeline.json`, item 8; `orchestrator_decisions.md`. | Confusion matrix, precision, recall calculations, temporal metrics, and weighting remain deferred to authorized targets. No TP, FP, or FN values were added. |
| 11 | Applied | Reframed timing rows as separately refitted, different-window point-estimate diagnostics; added horizons, the already-treated nominal pre-period for 2012, and the absence of cross-row contrast inference. Evidence: `comparability.json`, item 11. | Numeric rows and the preferred 2009 inference are unchanged. |
| 15 | Deferred, no manuscript change | Confirmed Table 23 and its current caption remain unchanged. Evidence: `cross_country.json`, item 15; `local_fixes.json`, item 15; `orchestrator_decisions.md`. | Requires the four proposed audit targets, validation, authorized graph edits, and execution before any expanded table or claim that audit rows exist. |
| 18 | Applied | Separated the 20,000-resample placebo SE, normal-approximation p-value and interval, and exhaustive placebo-in-space ranks. Evidence: `sdid.json`, item 18. | No estimate, SE, p-value, rank, seed, or replication count was changed. |
| 20 | Applied | Defined `N_0`, `N_1`, `T_0`, and `T_1`; stated the positive uniform treated and post-period weights and full unit/time vectors before the objectives. Evidence: `sdid.json`, item 20. | Equations were clarified without changing estimator code or results. |
| 21 | Applied | Added the -1/0/+1 vote coding, signed China-minus-U.S. distance definition, observed-vote exclusion, and China-U.S. divergence rule while retaining country and resolution effects and the existing item-25 caveat. Evidence: `corpus_votes_bibliography.json`, item 21; `orchestrator_decisions.md`. | No fixed-effect specification, sample, or result changed. |
| 22 | Applied | Replaced additive-isolation claims with conditional within-measure factor-count sensitivity, explicit original-scale limits, fixed factor counts within paired bootstrap replications, and non-equivalence language. Evidence: `comparability.json`, item 22. | Raw cross-outcome ATT differences remain scale-dependent; no interaction or equivalence test was introduced. |
| 25 | Explanation only, no item-25 change | Preserved the existing country-and-resolution-effects equation and donor-domain caveat. Evidence: `domain_note.md` and `domain_note.json`. | Any country-by-domain extension or new evidence remains a separately authorized targets-first decision. |
| 27 | Applied | Replaced the unsupported stability/variance-attribution sentence for Figure 8 with a visual description of China's annual volatility and Brazil's sustained post-2009 movement. Evidence: `corpus_votes_bibliography.json`, item 27. | No figure or underlying series changed. |
| 29 | Applied | Corrected Figure 2's caption: the arrow is the level-adjusted SDiD ATT, not the raw vertical gap. Evidence: `local_fixes.json`, item 29; prerequisites in `sdid.json`. | Orchestrator rendering must visually confirm the caption and unchanged figure. |
| 30 | Applied | Corrected the hierarchy direction: China rises to first place among a country's export destinations. Evidence: `local_fixes.json`, item 30. | Treatment code and estimand unchanged. |
| 31 | Applied with orchestrator correction | Explained separate input rescaling, inert time-invariant distance, the absolute power-gap construction, its exact equality to the signed difference on stored support, nuisance residualization, and why a nonzero stored coefficient is not identification evidence. Evidence: `orchestrator_decisions.md`, `verify_power_identity.R`, and `verify_power_identity.log`; the specialist's contrary inference in `sdid.json` was not used. | Preferred no-covariate fit unchanged. Independent methodological review of the corrected exposition and `synthdid` nuisance-adjustment description remains required before promotion. |
| 32 | Applied | Corrected all selected descriptions of SDiD time weights and characterized classic DiD as uniform weighting in the comparison. Evidence: `sdid.json`, item 32. | Unit and time weights and all stored results unchanged. |
| 33 | Applied | Changed `median` to `pre-treatment mean` in the abstract, retaining 42 percent. Evidence: `local_fixes.json`, item 33; existing BSV comparison CSV. Arithmetic check: `|-0.272771407583| / 0.646777890583 = 42.1738917725%`. | The usual delegated abstract-number gate in `CLAUDE.md` was not invoked because this task explicitly prohibited delegation. The integrator verified the number against the existing CSV and the body formula; no independent scientific review is claimed. |
| 34 | Applied jointly with item 22 | Identified the two pre-treatment means as BSV and UNGA-DM while preserving both inline values and relative-effect expressions. Evidence: `local_fixes.json`, item 34. | Merged into the item-22 paragraph to avoid overlapping replacement drift. |
| 35 | Applied jointly with item 36 | Broadened the economic-mechanism literature sentence to cover trade, investment, lending, aid, firms, and coercive tools. Evidence: `corpus_votes_bibliography.json`, items 35--36; `orchestrator_decisions.md`. | Other rationality-argument sentences were left unchanged. Bibliography source remains `synth-trade-china.bib`. |
| 36 | Applied jointly with item 35 | Same shared sentence correction. Evidence: `corpus_votes_bibliography.json`, items 35--36. | No bibliography record changed. |
| 37 | Refuted, no manuscript change | Retained the reverse-causality sentence and Strüver citation. Evidence: `bibliography_xhigh.json`, item 37. | No action warranted by the selected comment. |
| 38 | Applied | Removed only `@macdonald_parent2021` from the undifferentiated relational-status citation cluster. Evidence: `bibliography_xhigh.json`, item 38. | Prose and BibTeX entry retained. |

## Mechanical verification

- All 52 R chunks parsed without evaluation.
- All 52 chunk labels are nonempty and unique.
- All 47 literal figure/table cross-references resolve to chunk labels.
- The multiset of all 144 inline R expressions is identical to the baseline.
- Unified diff whitespace check reported no whitespace errors.
- No added manuscript line uses `spell` or `treatment spell`.
- No TP, FP, FN, confusion-matrix, or newly calculated class-performance values were added.
- The Table 23 section, its current fields, caption, and note remain unchanged.
- The item-25 donor-domain caveat and the item-37 Strüver sentence remain present.
- The exact patch is a unified diff from `execution/baseline/paper_v4.Rmd` to the isolated candidate.

## Not executed

No `targets` change or execution, reestimation, classification API call, raw-data edit, new analytical output, render, PDF write, git commit, push, process signal, lock operation, hook/configuration edit, or canonical-manuscript edit was performed.

The candidate is ready for the orchestrator's independent review and render gate. It has not been rendered or scientifically re-reviewed by the integrator.
