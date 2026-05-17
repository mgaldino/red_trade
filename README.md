# red_trade

Replication repository for the paper:
**The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Trade Partner**.

## Q&A (Quick Answers)

**Q1. Where is the replication package README used for submission?**  
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/README.Rmd`  
Compiled PDF:  
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/README.pdf`

**Q2. What is the current manuscript source in the replication package?**  
`/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade/replication package/paper_v3.Rmd`

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

## Diagnostic Addendum: UN Votes, Brazil-China

On 2026-05-17, a separate diagnostic analysis was added under `scripts/diagnostics/` to examine Brazil-China vote similarity in the UN General Assembly from 2005 to 2012. This analysis is independent of the `targets` pipeline and should not be run through `targets::tar_make()`.

Main outputs are stored in `data/processed/unvotes/` and `quality_reports/un_vote_cases/`. The central takeaway is that the post-2009 Brazil-China rapprochement appears most clearly in human-rights votes and is better described as direct Brazilian movement toward China's position than as broad relational realignment across all issue areas. Outside human rights, the evidence is more mixed, and some apparent convergence reflects China moving toward Brazil.
