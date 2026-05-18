# AGENTS.md

Instruções operacionais para agentes trabalhando neste repositório.

## Regras do projeto

- Use R para análise estatística e mantenha computação em scripts separados.
- Para diagnósticos exploratórios, prefira `scripts/diagnostics/`.
- Não altere `_targets.R`, `_targets/`, `_targets.yaml` nem o pipeline `targets` sem instrução explícita.
- Não rode `targets::tar_make()` sem instrução explícita.
- Preserve dados brutos e nunca sobrescreva arquivos de origem.
- Use `dplyr::select()` ao selecionar colunas em R.
- Outputs analíticos devem ser reprodutíveis e em UTF-8.
- Figuras e tabelas para relatórios devem ser numeradas e ter caption.
- Documente fonte e data de acesso.
- Quem implementa não revisa; quem revisa não edita.
- Para scripts R substantivos, use revisão crítica com a skill `review-r` quando solicitado.
- No manuscrito e em relatórios voltados ao autor/leitor, não use o jargão `spell` ou `treatment spell`. Prefira linguagem substantiva: `treatment entry/onset` para o ano em que a China se torna o maior destino de exportações, `treated periods` para os anos em que a China permanece nessa posição, e `cases where China displaced the United States/another partner` para heterogeneidade por incumbente deslocado. Nomes internos de variáveis podem manter `spell` quando já existirem em scripts ou CSVs, mas a prosa do paper deve evitar esse termo.

## Estado recente: votos Brasil-China na AGNU

Em 2026-05-17 foi produzida uma análise diagnóstica separada do pipeline `targets` sobre a dinâmica relacional dos votos Brasil-China na Assembleia Geral da ONU, 2005-2012.

Arquivos principais:

- `scripts/diagnostics/analyze_brazil_china_vote_alignment_by_issue_2005_2012.R`
- `scripts/diagnostics/plot_brazil_china_vote_similarity_by_issue_year_local_linear_2005_2012.R`
- `scripts/diagnostics/plot_brazil_china_vote_similarity_by_issue_year_facets_local_linear_2005_2012.R`
- `scripts/diagnostics/plot_brazil_china_vote_similarity_score_jitter_2005_2012.R`
- `data/processed/unvotes/brazil_china_vote_alignment_by_resolution_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_alignment_mechanisms_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_similarity_by_issue_year_plot_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_similarity_score_by_resolution_2005_2012.csv`
- `quality_reports/un_vote_cases/nota_alinhamento_relacional_brasil_china_2005_2012.md`

Takeaway substantivo: a aproximação Brasil-China pós-2009 aparece de forma real, mas estreita e temática. O mecanismo mais convincente é mudança direta do voto brasileiro em direção à China em direitos humanos. Há menos evidência de realinhamento relacional amplo pró-China, e alguns casos fora de direitos humanos parecem falsos positivos porque a China se moveu para posições brasileiras.

Próxima etapa recomendada: decidir como incorporar esse achado no paper, calibrando a força da narrativa de alinhamento com a China e separando mecanismo direto de mecanismo relacional.
