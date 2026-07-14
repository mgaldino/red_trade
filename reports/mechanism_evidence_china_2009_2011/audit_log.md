# Audit Log: Mechanism Evidence China 2009-2011

Access date: 2026-05-19

## Local Repo Inspection

Local searches were run first in `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade` using `rg`. Terms included `AGNU`, `UNGA`, `Assembleia Geral`, `ONU`, `China`, `discursos`, `maior parceiro`, `principal parceiro`, `maior destino`, `largest trade partner`, and related variants. Relevant local material found before external search included:

- `data/raw/un_docs/` and `data/processed/unvotes/`, including UN process-tracing and speech evidence files.
- `data/processed/unvotes/SOURCES.yaml` and `DATA_DICTIONARY.md`.
- `scripts/diagnostics/collect_un_process_tracing_documents.py`, `collect_un_vote_speeches.py`, and related UN vote/process-tracing scripts.
- Folha/training-data headline files with media references to China overtaking the United States as commercial partner.
- Existing manuscript and review files discussing the mechanism.

Local UNGA/AGNU materials did not contain direct 2009-2011 Brazilian rank/status language connecting China trade rank to diplomatic prioritization. They were treated as negative/contextual for this mechanism search.

## External Queries and Source Mapping

Representative official-source queries included:

- `site:gov.br/planalto Lula China maior destino das exportacoes brasileiras 2009`
- `site:gov.br/mre China maior parceiro comercial Brasil 2009 Itamaraty Lula Hu Jintao`
- `site:funag.gov.br Resenha de Política Exterior do Brasil China maior parceiro comercial 2009 Lula`
- `site:camara.leg.br China maior parceiro comercial Brasil 2009 politica externa`
- `site:senado.leg.br China maior parceiro comercial Brasil 2009 2010 2011`
- `site:in.gov.br China principal parceiro comercial Brasil 2011`
- `dados abertos CGU FalaBR pedidos respostas csv`

Official sources consulted: MRE/FUNAG Resenhas, Agência Câmara, CGU/Fala.BR documentation and filtered public-data zips. Senado and DOU searches did not yield positive direct evidence for the 2009-2011 mechanism.

## Fala.BR/CGU Scan

The CGU/Fala.BR filtered text zips for 2015-2026 were downloaded from the official pattern `https://dadosabertos-download.cgu.gov.br/FalaBR/Arquivos_FalaBR_Filtrado/Arquivos_csv_{year}.zip` and preserved under `data/raw/mechanism_evidence_china_2009_2011/falabr/`. The scan filtered rows where the destination organ matched MRE/Relações Exteriores and the text contained China-related terms. It then searched those rows for rank/status terms.

Results: 1,071,879 rows scanned; 12,383 MRE rows; 397 MRE-China rows; 5 MRE-China rank/status rows. The rank/status rows were later LAI requests or responses (2016 and 2021), not verified 2009-2011 diplomatic documents. They are documented as source-discovery evidence only and are not used in the paper block.

Promising LAI pointers from the subagent mapping include requests for telegrams from Dilma Rousseff's April 2011 China trip, China-Africa cooperation telegrams from 2011, and mission reports for China/Shanghai. Public open-data text did not expose the underlying 2009-2011 telegram excerpts with mechanism language.

## Positive Sources Retained

- MRE/FUNAG Resenha 104 (1st semester 2009): MECH001-MECH004.
- MRE/FUNAG Resenha 106 (1st semester 2010): MECH005.
- MRE/FUNAG Resenha 108 (1st semester 2011): MECH006-MECH009.
- MRE/FUNAG Resenha 109 (2nd semester 2011): MECH011.
- Agência Câmara official news page, 7 Oct. 2011: MECH010.

## Sources Discarded or Treated as Contextual

- Journalistic/secondary hits were used only as search leads, not final evidence.
- UNGA/AGNU files were inspected locally but did not contain direct commercial-rank mechanism evidence.
- Fala.BR hits where rank/status language appeared only in citizen request text were excluded from the final paper block.
- Senate and DOU searches did not produce verified 2009-2011 primary evidence with the mechanism language.
- MECH001 is retained as medium/contextual because it uses second-largest-partner language before the 2009 top-rank cue.

## Independent Fact-Check

A separate verifier reopened the local raw text/HTML sources and confirmed all 11 retained rows as `verified`. The verifier flagged three caveats: MECH001 should not be used as evidence that China was already the top partner; MECH010 is legislative/judicial adjustment evidence rather than presidential diplomacy; and MECH011 should be cited with its China-introducing context because the short quote alone is elliptical.

## URL Validation

`curl -I` returned HTTP 200 for the MRE/FUNAG PDFs and the Agência Câmara page on 2026-05-19. The Fala.BR documentation page blocks `HEAD` with 403 in this environment, but the page was accessible through browser/search and the official zip downloads worked by GET. The raw files and checksums in `SOURCES.yaml` and `raw_checksums.csv` provide local auditability if URLs change.
