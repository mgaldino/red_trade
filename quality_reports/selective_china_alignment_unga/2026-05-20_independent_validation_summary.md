# Independent Validation Summary

Data: 2026-05-20

Escopo validado:

- `scripts/diagnostics/diagnose_selective_china_alignment_unga.R`
- `quality_reports/selective_china_alignment_unga/2026-05-20_selective_china_alignment_unga_report.md`
- `quality_reports/selective_china_alignment_unga/2026-05-20_paper_v4_revision_memo_selective_china_alignment.md`

## Validação 1. R review

Nota final: **A**.

Síntese do parecer: não há blockers restantes. A revisão aceitou que o relatório agora trata p-valores voto-a-voto como model-based/descritivos, usa placebo por país como benchmark inferencial principal, remove a contagem duplicada do `closer_to_china_score`, adiciona DDD HR vs non-HR, clusters bidirecionais, event-study pré-2009, p strict donor-only, auditoria target/file e auditoria dos placebos mais extremos. O PDF renderizou com sucesso, não há `targets::tar_make()`, não há `select()` sem `dplyr::`, e os dados brutos não são sobrescritos.

Ponto minor não bloqueante: a matriz marca o placebo temporal como `TRUE` apesar do pseudo-2007 significativo; isso é aceitável porque o texto o interpreta como pequeno, mas não limpo, e como limite contra linguagem causal forte.

## Validação 2. Causal-DiD review

Nota final: **A para o claim revisado e limitado**.

Síntese do parecer: a identificação recebeu A porque o DDD HR vs non-HR resolve o blocker principal anterior. A estimação recebeu A porque a unidade país-resolução, efeitos fixos de país e resolução, exclusão de ausentes, codificação ordinal, exclusão dos EUA como referência, sensibilidade yes/no, negative control non-HR e DDD estão alinhados ao estimando diagnóstico. A inferência recebeu A para o escopo diagnóstico porque o relatório agora usa o placebo por país como inferência principal e clusters convencionais/two-way apenas como precisão model-based.

Limite substantivo mantido: o placebo por país é sugestivo, não esmagador (`p` direcional inclusivo `0.063`; strict donor-only `0.053`; two-sided `0.084`/`0.074`). Isso sustenta linguagem cautelosa, não prova causal standalone.

## Conclusão validada

A formulação validada é:

> Diagnostic evidence compatible with selective HR China alignment, not standalone causal proof.

Essa validação não autoriza dizer que Table 4/Figure 6 sozinha prova convergência seletiva toward China.
