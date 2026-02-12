# Plano: Research Pipeline — paper_v3.Rmd

**Status**: APPROVED
**Data**: 2026-02-12

## Objetivo
Rodar pipeline completo de revisão de qualidade: Code Review → Devil's Advocate → Proofread.

## Arquivos
- Manuscrito: `paper_v3.Rmd`
- Código de análise: `scripts/functions.R` + `_targets.R` (chunks em paper_v3.Rmd)
- Bibliografia: `synth-trade-china.bib`

## Estágios
1. **Code Review**: Avaliar `scripts/functions.R` e chunks R em `paper_v3.Rmd`
2. **Devil's Advocate**: Estressar argumento do manuscrito
3. **Proofread**: Gramática, typos, consistência

## Mode
Standard (não "Just Do It") — pausar para aprovação no proofread.

## Verificação
- Score ≥ 80 em cada estágio (≥ 90 no proofread)
- Relatório final em `quality_reports/pipeline_report_2026-02-12.md`
