# Goal 9 implementation review

Date: 2026-05-18

Reviewer role: separate manuscript reviewer. The reviewer did not edit files.

## Round 1

Verdict: blockers.

Render technically succeeded: `paper_v4.pdf` existed, was created on 2026-05-18, had 29 pages, and the reviewer found no unresolved `??`, `@ref`, `fig:`, or `tab:` references in the PDF text. The reviewer nevertheless found blockers for Goal 9 acceptance:

1. Main tables were not render-safe in the PDF. Tables 1 and 2 overflowed horizontally and key columns appeared cut off.
2. Cross-country Table 3 floated into the Brazilian media section, before the "Cross-country scope probe" heading.
3. The H2 text claimed that exploratory U.S.-displacement heterogeneity estimates were reported in the appendix, but the appendix did not include the corresponding Goal 4 subgroup estimates or U.S.-minus-non-U.S. contrast.

Required fixes:

1. Make Tables 1, 2, and 3 render visibly in PDF.
2. Force Table 3 to remain inside the cross-country section.
3. Either add an appendix H2 heterogeneity table from Goal 4 or revise the main-text sentence so it does not claim appendix reporting.
4. Re-render and re-check the PDF for table overflow, misplaced floats, and unresolved references.

Implementation response:

1. Tables 1, 2, and 3 were rebuilt with `kableExtra` width control, stronger hold-position options, and table notes embedded in the table objects rather than printed as separate paragraphs.
2. The Brazilian media figure was forced to render before the next section using `\clearpage`, preventing media material from floating into the cross-country section.
3. The H2 paragraph was revised to treat U.S.-displacement heterogeneity as exploratory without claiming appendix reporting.
4. The PDF was rendered again successfully after these fixes.

## Round 2

Verdict: no blockers.

The separate reviewer found that the Round 1 blockers were fixed:

- Tables 1, 2, and 3 rendered visibly in `paper_v4.pdf`, with captions and notes intact.
- Table 3 appeared inside the cross-country section rather than floating into the media section.
- The H2 paragraph no longer claimed absent appendix reporting and correctly treated U.S.-displacement heterogeneity as exploratory.
- Native LaTeX `\clearpage` was acceptable for this manuscript because it solved the section-boundary problem without adding a new dependency; introducing `placeins` was not worth doing before commit because the local package was unavailable.

Nonblocking notes from the reviewer:

- Remove the remaining phrase saying PanelMatch diagnostics were reported in the appendix.
- Reconcile Table 2's non-human-rights diagnostic with the Goal 6 report.
- Appendix media materials still include non-target documentation, but this does not affect the main claim ladder.

Implementation response:

- Removed the PanelMatch appendix-reporting phrase.
- Corrected the target-backed human-rights versus non-human-rights diagnostic by deduplicating by `rcid`; Table 2 now reports non-human-rights identical-vote change as +2.7 p.p., consistent with the Goal 6 report.
- Re-rendered `paper_v4.pdf` successfully.

## Final confirmation

Verdict: no blockers.

The reviewer confirmed that the current `paper_v4.Rmd` and rendered `paper_v4.pdf` remain acceptable for Goal 9. Tables 1--3 render visibly with notes/captions intact; section architecture is fixed; PanelMatch wording is gone; Table 2 reports non-human-rights as +2.7 p.p.; terminology and causal caveats are aligned; no unresolved cross-references were found; and `\clearpage` is an acceptable dependency-free solution here.

## Follow-up after author feedback

Verdict: no blockers.

The separate reviewer checked the follow-up revision after the author's comments on defensive language, table contents, cross-country terminology, and appendix float placement. The reviewer first flagged dirty workspace items outside the intended commit scope (`_targets/meta/meta` and untracked diagnostic scripts). After clarification that those files pre-existed and would be excluded from the commit, the reviewer rechecked the scoped changes and found no paper/doc/PDF blockers.

Checked items:

- No manuscript prose uses `spell` or `treatment spell`; `AGENTS.md` and `CLAUDE.md` now instruct future agents to avoid that term in author-facing prose.
- Tables 2 and 3 report standard errors where estimates appear.
- The confusing main-text outcome table with China-minus-U.S. and U.S.-distance outcomes was removed.
- The media section identifies Folha de S.Paulo as Brazil's widest-circulation newspaper and explains why salience matters.
- The cross-country section no longer opens with "second Brazil" language; Table 4 reports estimator, ATT, SE, p-value/CI, N, treated/control units, covariates, latent factors, panel window, and treatment type.
- The rendered PDF places Table 4 before References and Figures 9--10 before the ChatGPT appendix section.
- The unadjusted leave-one-out appendix table was removed because it did not match the preferred covariate-adjusted cross-country specification.
- No scripts were edited and `targets::tar_make()` was not run.

Render status: `paper_v4.pdf` rendered successfully after the follow-up edits on 2026-05-18.

## Follow-up on Table 3 and Data variables

Verdict: no blockers.

The author requested two additional changes: restore the Brazil SDiD Table 3 to the visual grammar of the older Table 2, and add a short paragraph in the Data section describing variables. The implementation kept the current four specification columns but reformatted Table 3 with an ATT row, standard errors in parentheses, a covariate checkmark block, and final rows for country-years, donor countries, donor pool, and time window. The Data section now describes the outcome, treatment, Brazil SDiD covariates, and cross-country `fect` controls before the descriptive-statistics table. The Lula/South-South ideology confounder argument was also restored near the timing/placebo tests.

Separate reviewer result: PASS. The reviewer confirmed that the variable paragraph appears before the descriptive-statistics table; Table 3 is readable in the rendered PDF and preserves the requested columns and sample/window rows; the Lula/South-South paragraph is restored without overclaiming; the PDF rendered successfully; and no `spell`/`treatment spell` or previously removed defensive phrases appear in the manuscript or rendered PDF.

Render status: `paper_v4.pdf` rendered successfully after these edits on 2026-05-18.
