# ChatGPT Pro Request: Goal 9 Implementation Guide

You are continuing the earlier ChatGPT Pro review conversation titled **"ChatGPT Pro Review Guide"**. In that conversation, you produced the APSR revision goals for this manuscript. We now need a follow-up output focused on **Goal 9**.

## Manuscript

Manuscript title: **The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Export Destination**

Use the attached current manuscript source, `paper_v4.Rmd`, as the authoritative current version. A rendered PDF may also be attached for context, but the source is more current.

## Current Revision Status

Please take the following status as fixed unless the attached materials show a direct contradiction:

1. **Goal 2 has already been incorporated in the paper.** The author added a note/footnote explaining that the paper uses "top trade partner" as shorthand for the publicly salient event in which China became the country's largest export destination, while the empirical treatment in Brazil and the cross-country panel is China becoming the largest export destination.
2. **Goal 1 will be left until last.** Do not spend the report rewriting the abstract or introduction in full. You may flag what Goal 1 should later do after Goal 9 is implemented.
3. **Goal 8 will be left for later.** Do not turn this output into an NLP/media reproducibility plan. Mention Goal 8 only where Goal 9 needs to avoid premature media-section overclaiming.
4. **Goal 6 is still being finalized by another agent at packet-preparation time.** When you receive this request, a final Goal 6 report should be attached. If the Goal 6 final report is missing, stop and ask for it instead of producing the guide.

## Attachments You Should Use

Core manuscript/context:

- `paper_v4.Rmd` - current manuscript source.
- `paper_v4.pdf` or latest rendered manuscript PDF, if attached - visual/context reference only.
- `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.md` - the original APSR revision goals you generated.

Goal reports to integrate:

- Goal 3: `quality_reports/2026-05-18_goal3_rank_vs_volume_diagnostic.md`
- Goal 4: `quality_reports/goal4_h2_scope_condition/goal4_h2_methodological_report_20260518.md`
- Goal 5: `quality_reports/2026-05-18_goal5_sdid_identification_prompt_report.md`
- Goal 6: final Goal 6 outcome-robustness report, to be attached when complete.
- Goal 7: `quality_reports/2026-05-18_goal7_cross_country_scope_prompt_report.md`

Treat the reports as constraints. Do not recommend ignoring their findings unless there is a clear scholarly reason.

## Task

Create a **downloadable Markdown file** named:

`goal9_implementation_guide_for_codex.md`

This file must be an implementation guide for a new Codex agent that will execute **Goal 9 first** and then later help with **Goal 1**. The guide should be concrete enough that the next agent can edit `paper_v4.Rmd` without needing to rediscover the whole review history.

Goal 9 is:

> Compress the paper and repair all presentation defects before any top-journal submission. Perform an exposition pass aimed at making the manuscript read like a submission rather than a research notebook. Reduce defensive diagnostics in the main text, repair every broken label, and standardize terminology.

## Required Output Structure

Please write the Markdown guide with these sections:

1. `# Goal 9 Implementation Guide`
2. `## One-Page Diagnosis`
   - State what the paper should become after Goals 3-7 are reflected but before Goal 1 is rewritten.
   - Be explicit about claim strength: Brazil as the main reduced-form design; media as salience evidence; cross-country as a scope probe; outcome robustness as narrowing or broadening the claim depending on Goal 6.
3. `## Priority Order`
   - Give an ordered list of implementation passes for the Codex agent.
   - Separate edits that must happen before moving content to the appendix from edits that can happen after.
4. `## Main Text Architecture`
   - Give the target structure: Introduction; Theory and hypotheses; Data and design; Brazil SDiD evidence; Brazilian media salience; Cross-country scope probe; Conclusion.
   - For each section, state what should stay, what should be compressed, what should move to appendix, and what should be deleted.
5. `## Section-by-Section Text Instructions`
   - Provide detailed instructions for `paper_v4.Rmd`.
   - Include concrete replacement language where useful.
   - Do not write a full new introduction or abstract; reserve that for Goal 1.
6. `## Tables`
   - List every table that should remain in the main text, be added, be revised, moved to appendix, or dropped.
   - For each table, specify the purpose, preferred columns, caption/note requirements, treatment definition wording, units, uncertainty, and source report.
7. `## Figures`
   - List every figure that should remain in the main text, be added, be revised, moved to appendix, or dropped.
   - For each figure, specify the purpose, caption/note requirements, units, window, treatment definition, and source report.
   - Include new or revised figure/table needs from Goals 3, 4, 5, 6, and 7.
8. `## Appendix Relocation Map`
   - Give a practical map of diagnostic material that should move out of the main text.
   - Include PanelMatch, C&S absorbing-treatment estimates, leave-one-out, raw treated-country panels, long donor-weight plots, extended NLP prompt details, and any long robustness tables unless Goal 6 says otherwise.
9. `## Terminology and Claim Discipline`
   - Specify terms to standardize.
   - Include replacements for overbroad or casual wording, especially "foreign-policy realignment" versus "UNGA voting convergence toward China".
   - Reflect the already-incorporated Goal 2 note/footnote instead of reopening Goal 2.
10. `## Cross-References, Captions, and Presentation Defects`
    - Provide a checklist of labels, figure/table references, captions, typos, and formatting defects to search for.
    - Include the known defects from the original Goal 9.
11. `## What Goal 1 Should Do Later`
    - Give a short handoff for the later abstract/introduction rewrite after Goal 9 is implemented.
    - Do not write the final Goal 1 text here.
12. `## Validation Checklist`
    - Provide concrete final checks: searches to run, compilation checks, caption checks, terminology checks, and what should be true before the agent stops.

## Substantive Constraints

Follow these substantive constraints from the completed reports:

- From Goal 3: the paper should show, compactly, that the 2009 Brazil treatment is empirically distinguishable from smooth export-volume growth. The 2003 and 2005 timing placebos should be framed as rank-versus-volume tests. Contemporaneous post-2009 trade share and margin are not clean preferred controls.
- From Goal 4: H2 should not be presented as conclusively tested. The cross-country H2 evidence should be treated as exploratory heterogeneity or a scope condition. The pooled ATT is not a direct H2 test.
- From Goal 5: the Brazil SDiD section should be defensible in roughly three pages: estimand, fit, estimate, placebo logic, donor/sensitivity summary, and one limitations paragraph. Long donor and diagnostic material should move to the appendix.
- From Goal 6: use the attached final Goal 6 report to decide how outcome robustness changes the wording, tables, and figures. If convergence is concentrated in a specific issue area, narrow the claim rather than hiding that fact.
- From Goal 7: demote the cross-country panel to a credible scope probe with one main estimator, one main table, one main dynamic figure, and a short limitations paragraph. Make the distinction between switching fect and absorbing-treatment C&S explicit.

## Style of the Guide

- Write in English, because the manuscript is in English.
- Be direct, concrete, and implementation-oriented.
- Do not produce a broad referee report.
- Do not ask the next agent to run `targets::tar_make()`.
- Do not ask for new data collection unless it is strictly necessary for Goal 9.
- Do not over-expand Goal 8.
- Do not reopen Goal 2 except to ensure wording is internally consistent.
- Make the output self-contained enough that a new Codex agent can follow it using the attached reports and the repository files.

## Final Requirement

Return the result as a downloadable Markdown file named `goal9_implementation_guide_for_codex.md`. If the interface cannot create a downloadable file, return the complete Markdown content in a fenced Markdown block and explicitly title it with that filename.
