# Chinese Political Science Review submission checklist

Generated from `paper_v4.Rmd` on 2026-09-22. The build reads existing project outputs and does **not** execute `targets::tar_make()`.

## Automated checks

- [x] main PDF exists
- [x] inline PDF exists
- [x] full PDF exists
- [x] short PDF exists
- [x] online PDF exists
- [x] public PDF exists
- [x] title PDF exists
- [x] letter PDF exists
- [x] portable LaTeX source ZIP exists
- [x] source ZIP contains only relative safe paths
- [x] source ZIP contains TeX for manuscript_anonymous
- [x] source ZIP contains TeX for manuscript_with_full_appendix_anonymous
- [x] source ZIP contains TeX for online_resource_1_anonymous
- [x] source ZIP contains its checksum manifest
- [x] abstract has 197 words (required: 150-250)
- [x] keywords count is 6 (required: 4-6)
- [x] main PDF contains structured abstract label: Purpose
- [x] main PDF contains structured abstract label: Methods
- [x] main PDF contains structured abstract label: Results
- [x] main PDF contains structured abstract label: Conclusion
- [x] formal-model sentence appears in Methods
- [x] main PDF contains the approved cross-country abstract result
- [x] standalone main PDF excludes appendix content
- [x] full appendix contains: Brazil and China Ideal-Point Series
- [x] online resource contains: Brazil and China Ideal-Point Series
- [x] full appendix contains: Triple-Difference Pre-Trends
- [x] online resource contains: Triple-Difference Pre-Trends
- [x] full appendix contains: Resolution-Level UNGA Vote Diagnostics
- [x] online resource contains: Resolution-Level UNGA Vote Diagnostics
- [x] full appendix contains: SDiD
- [x] online resource contains: SDiD
- [x] full appendix contains: Selected Public-Cue Cross-Country Analyses
- [x] online resource contains: Selected Public-Cue Cross-Country Analyses
- [x] full appendix contains: Cross-Country Robustness: Duration Thresholds
- [x] online resource contains: Cross-Country Robustness: Duration Thresholds
- [x] full appendix contains: Cross-Country Sample Audit: Goods-Only Treatment Coding
- [x] online resource contains: Cross-Country Sample Audit: Goods-Only Treatment Coding
- [x] full appendix contains: Public Cue and Recoverability Audit
- [x] online resource contains: Public Cue and Recoverability Audit
- [x] full appendix contains: ChatGPT Classification
- [x] online resource contains: ChatGPT Classification
- [x] full appendix contains: Cross-Country: Goods-Only Treated Countries
- [x] online resource contains: Cross-Country: Goods-Only Treated Countries
- [x] full appendix contains: Measurement Robustness: UNGA-DM Ideal Points
- [x] online resource contains: Measurement Robustness: UNGA-DM Ideal Points
- [x] short appendix contains: Brazil and China Ideal-Point Series
- [x] short appendix contains: Triple-Difference Pre-Trends
- [x] short appendix contains: Cross-Country Robustness: Duration Thresholds
- [x] short appendix contains: Cross-Country Sample Audit: Goods-Only Treatment Coding
- [x] short appendix contains: Public Cue and Recoverability Audit
- [x] short appendix contains: Measurement Robustness: UNGA-DM Ideal Points
- [x] short appendix content omits: Resolution-Level UNGA Vote Diagnostics
- [x] short appendix content omits: SDiD
- [x] short appendix content omits: Selected Public-Cue Cross-Country Analyses
- [x] short appendix content omits: ChatGPT Classification
- [x] short appendix content omits: Cross-Country: Goods-Only Treated Countries
- [x] main PDF contains no author given name
- [x] main PDF contains no author family name
- [x] main PDF contains no author email
- [x] main PDF contains no author ORCID
- [x] main PDF contains no preprint DOI
- [x] inline PDF contains no author given name
- [x] inline PDF contains no author family name
- [x] inline PDF contains no author email
- [x] inline PDF contains no author ORCID
- [x] inline PDF contains no preprint DOI
- [x] full PDF contains no author given name
- [x] full PDF contains no author family name
- [x] full PDF contains no author email
- [x] full PDF contains no author ORCID
- [x] full PDF contains no preprint DOI
- [x] short PDF contains no author given name
- [x] short PDF contains no author family name
- [x] short PDF contains no author email
- [x] short PDF contains no author ORCID
- [x] short PDF contains no preprint DOI
- [x] online PDF contains no author given name
- [x] online PDF contains no author family name
- [x] online PDF contains no author email
- [x] online PDF contains no author ORCID
- [x] online PDF contains no preprint DOI
- [x] cpsr_full_supplement_anonymous.Rmd requests indented paragraphs
- [x] cpsr_full_supplement_anonymous.Rmd contains no author given name
- [x] cpsr_full_supplement_anonymous.Rmd contains no author family name
- [x] cpsr_full_supplement_anonymous.Rmd contains no author email
- [x] cpsr_full_supplement_anonymous.Rmd contains no author ORCID
- [x] cpsr_full_supplement_anonymous.Rmd contains no preprint DOI
- [x] cpsr_full_inline_anonymous.Rmd requests indented paragraphs
- [x] cpsr_full_inline_anonymous.Rmd contains no author given name
- [x] cpsr_full_inline_anonymous.Rmd contains no author family name
- [x] cpsr_full_inline_anonymous.Rmd contains no author email
- [x] cpsr_full_inline_anonymous.Rmd contains no author ORCID
- [x] cpsr_full_inline_anonymous.Rmd contains no preprint DOI
- [x] cpsr_manuscript_anonymous.Rmd requests indented paragraphs
- [x] cpsr_manuscript_anonymous.Rmd contains no author given name
- [x] cpsr_manuscript_anonymous.Rmd contains no author family name
- [x] cpsr_manuscript_anonymous.Rmd contains no author email
- [x] cpsr_manuscript_anonymous.Rmd contains no author ORCID
- [x] cpsr_manuscript_anonymous.Rmd contains no preprint DOI
- [x] Springer template disables extra paragraph spacing
- [x] Springer template prevents vertical glue stretching
- [x] body-only PDF is shorter than full inline PDF
- [x] condensed appendix is shorter than full appendix

## Journal-fit and format decisions

- Journal: Chinese Political Science Review.
- Springer Nature class: `sn-jnl` with `referee,sn-basic` options (double-spaced review layout and author-year Springer Basic references).
- Structured abstract: 197 words across Purpose, Methods, Results, and Conclusion (journal range: 150-250).
- Keywords: 6: China, foreign policy alignment, international political economy, trade-based status, synthetic difference-in-differences, United Nations General Assembly (journal range: 4-6).
- The manuscript, appendices, and Online Resource 1 are anonymous. The title page and cover letter carry author identity.
- `CPSR_LaTeX_Sources.zip` contains three independently compiled portable source trees with local figures, bibliography, and vendored Springer runtime files.
- No explicit overall manuscript word limit or appendix word limit was found on the journal's current submission-guidelines page. Both the full and condensed appendix routes are retained so the package can be adapted if the portal or editor imposes a file-specific limit.
- Guidelines checked: <https://link.springer.com/journal/41111/submission-guidelines>
- Official Springer Nature LaTeX package: <https://www.springernature.com/gp/authors/campaigns/latex-author-support/see-where-our-services-will-take-you/18782940>

## PDF inventory

- `CPSR_Manuscript_Anonymous.pdf`: 53 pages
- `CPSR_Manuscript_with_Full_Appendix_Anonymous.pdf`: 87 pages
- `CPSR_Appendix_Full_Anonymous.pdf`: 34 pages
- `CPSR_Appendix_Short_Anonymous.pdf`: 15 pages
- `CPSR_Online_Resource_1_Anonymous.pdf`: 34 pages
- `CPSR_Online_Supplement_Public.pdf`: 34 pages
- `CPSR_Title_Page.pdf`: 1 pages
- `CPSR_Cover_Letter.pdf`: 1 pages

- `CPSR_LaTeX_Sources.zip`: portable, isolated-compile-verified LaTeX sources.

## Author confirmations before upload

- [ ] Confirm the funding statement, grant/process number, and acknowledgment wording on the title page.
- [ ] Confirm the competing-interests declaration and the statement that the manuscript is not under consideration elsewhere.
- [ ] Confirm the preprint title and DOI disclosed in the cover letter.
- [ ] Add the final public URL to `public_supplement_url` only after choosing a non-identifying review strategy or after peer review; then rebuild.
- [ ] Upload the title page separately from every file sent for double-anonymous review.

## Recommended upload routes

1. Default route: anonymous manuscript + separate title page + cover letter + full anonymous appendix.
2. Condensed route, if an editor or portal imposes an appendix limit: anonymous manuscript + separate title page + cover letter + condensed anonymous appendix + anonymous Online Resource 1.
3. `CPSR_Online_Supplement_Public.pdf` is the author-identified website version. Do not upload it as a double-anonymous review file.
