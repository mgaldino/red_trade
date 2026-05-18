# RDD Trade — Foreign Policy Impact of Trade Status Gains

## Projeto
Paper: "The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Trade Partner". Em Revise & Resubmit. Tambem submetido ao Simposio FGV-USP em 2026-04-10 (versao anonimizada: `paper_v4_anonymous.Rmd` / `output/paper_v4_anonymous.pdf`, folha de rosto apenas com titulo e abstract de 139 palavras).

SDiD principal: -0.2339 (SE: 0.1328), permutation p=0.0105. DiD restrito (China deslocou EUA): ATT=-0.116, SE=0.044, p=0.008. Pipeline completo (~3h30min rebuild).

Autor: Manoel Galdino (DCP-USP).

## Pendência alta

- **2026-05-12 — harmonizar contagens cross-country**: o abstract de `paper_v4.Rmd` afirma "4 de 8 tratados" com reversões, mas os resultados/targets atuais indicam 99 países no painel, 59 tratados, 52 switching e 7 absorbing. Antes de nova submissão ou apresentação acompanhada do manuscrito, revisar `paper_v4.Rmd`, `paper_v4_anonymous.Rmd` e materiais derivados. Documento versionável: `PENDING.md`. Nota local detalhada: `quality_reports/2026-05-12_high_priority_pending_cross_country_counts.md`.

## Estrutura do repositorio
```
red_trade/
  red_trade.Rproj              # Projeto R
  _targets.R / _targets.yaml   # Pipeline targets
  renv/ + renv.lock            # Dependencias travadas
  paper_v4.Rmd                 # Paper atual (R&R)
  paper.Rmd ... paper_v3.Rmd   # Versoes anteriores (.Rmd sources)
  synth-trade-china.bib        # Bibliografia
  scripts/                     # Scripts R de analise
  data/                        # Dados processados + brutos
  raw data/                    # Dados brutos (24 subdirs)
  output/                      # PDFs compilados, logs, figuras
  references/                  # PDFs de papers citados
  replication package/         # Pacote de replicacao para submissao
  presentations/               # Slides
  quality_reports/             # Reviews
```

## Stack
- R (renv para dependencias, targets pipeline, fixest)
- Execucao via `targets::tar_make()`
- Cache local: `folha_scrape_cache.rds`, `wb_data_cache.rds` (determinismo sem API)
- Dados: Dataverse DOI https://doi.org/10.7910/DVN/M97OCJ

## Regras de trabalho

### Separacao de papeis
- **O agente que implementa NAO revisa. Quem revisa NAO implementa.** Usar agentes separados para cada funcao.

### Autoria
- **O autor escreve o paper.** NAO redigir secoes ou texto a menos que o autor peca explicitamente.
- Em prosa de manuscrito e relatórios para o autor/leitor, evitar o jargão `spell`/`treatment spell`. Usar `treatment entry/onset`, `treated periods`, ou descrição substantiva do parceiro deslocado. `Spell` pode aparecer apenas como nome interno herdado de variável/arquivo quando tecnicamente necessário.

### Workflow
- NAO rodar scripts sem aprovacao do usuario
- NAO commitar sem instrucao explicita
- NAO incorrer custos de API externos sem aprovacao explicita previa (informar: o que, quantas chamadas, custo estimado)
- Skills que exigem permissao devem ser rodadas em foreground
- Sempre ler o arquivo antes de propor mudancas
- Para imagens e documentos digitalizados, usar Read tool (VLM) diretamente — zero custo adicional
