# red_trade

Replication repository for the paper:
**The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Trade Partner**.
Active development title in `paper_v4`: **The Foreign Policy Impact of
Trade-Based Status Gains: When China Overtakes the US as Top Export
Destination**.

## Q&A (Quick Answers)

**Q1. Where is the replication package README used for submission?**  
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/README.Rmd`  
Compiled PDF:  
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/README.pdf`

**Q2. What is the current manuscript source in the replication package?**  
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/paper_v3.Rmd`

**Q2a. What is the active development manuscript?**
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/paper_v4.Rmd`

As of 2026-05-25, `paper_v4.Rmd` is the source of truth for the active
development manuscript. The PDF was rendered as `paper_v4.pdf` on 2026-05-25
17:31 (-03). The local `coarse-review` minor-comment pass is mostly resolved:
comments C01-C16 and C18-C26 are implemented or resolved; C17 remains
deliberately deferred because the headline-sample image still promises 20
headlines. The tracking files are:

- `quality_reports/coarse_review/plan_minor_comments_coarse_review_2026-05-20.md`
- `quality_reports/coarse_review/pendencias_minor_comments_coarse_review_2026-05-20.md`

**Q2b. Is there a pending cross-country treatment recoding for `paper_v4.Rmd`?**
No. This was pending on 2026-05-20, but it has since been incorporated into
`targets` and into `paper_v4.Rmd`. The active cross-country design is
goods-only, status-current, and uses a restricted risk set. Treatment equals one
only in country-years where China is the largest goods export destination and
the China-top period lasts at least five observed years. Short China-top
episodes and post-exit off-status years are excluded from the main risk set.

Relevant targets include:

- `china_top_m2_goods_status_current_panel_bundle`
- `china_top_m2_goods_status_current_model_results`
- `fect_ife_china_top_m2_goods_status_current_min5_risk_set`
- `plot_china_top_m2_goods_status_current_dynamic`

The original design note remains useful as provenance:

- `quality_reports/cross_country_sample/nota_recodificacao_status_current_min5_2026-05-20.md`
- `quality_reports/cross_country_sample/nota_recodificacao_status_current_min5_2026-05-20.html`

**Q3. What should be run first for reproducibility?**  
Restore `renv`, run `targets::tar_make()`, then render `paper_v3.Rmd`.

**Q4. Does the replication package still depend on mandatory online scraping/API calls?**  
No for the default path. Local cache files are now included in `replication package/raw data/` (`folha_scrape_cache.rds`, `wb_data_cache.rds`).

## Repository Structure

- Root project files and development artifacts live at:
  `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade`
- Journal-facing replication package lives at:
  `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package`

## Reproduction (Replication Package)

Run from:
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package`

```r
install.packages("renv")
renv::restore(prompt = FALSE)

library(targets)
tar_make()

rmarkdown::render("paper_v3.Rmd", output_format = "pdf_document")
```

Optional submission variant:

```r
rmarkdown::render("paper_status_trade_submission.Rmd", output_format = "pdf_document")
```

## Data

Download Dataverse bundle and extract into:
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/raw data`

DOI: <https://doi.org/10.7910/DVN/M97OCJ>

## Notes

- The replication package includes precomputed NLP classification outputs in:
  `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/chatgpt data`
- The replication package includes local cache files for deterministic default runs:
  `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/raw data/folha_scrape_cache.rds`
  `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/raw data/wb_data_cache.rds`
- Full package documentation is maintained in:
  `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/README.Rmd`
- Do not use `paper_v4.extraction_cache.json` as current manuscript evidence
  without regenerating it; it may contain text extracted from older PDFs.

## Diagnostic Addendum: UN Votes, Brazil-China

On 2026-05-17, a separate diagnostic analysis was added under `scripts/diagnostics/` to examine Brazil-China vote similarity in the UN General Assembly from 2005 to 2012. This analysis is independent of the `targets` pipeline and should not be run through `targets::tar_make()`.

Main outputs are stored in `data/processed/unvotes/` and `quality_reports/un_vote_cases/`. The central takeaway is that the post-2009 Brazil-China rapprochement appears most clearly in human-rights votes and is better described as direct Brazilian movement toward China's position than as broad relational realignment across all issue areas. Outside human rights, the evidence is more mixed, and some apparent convergence reflects China moving toward Brazil.

As of 2026-05-25, `paper_v4.Rmd` already reflects this calibrated interpretation
through issue-area and vote-level diagnostics. Do not treat "incorporate AGNU
findings" as an open broad task without first checking the current manuscript.
