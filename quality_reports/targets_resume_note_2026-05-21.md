# Nota de parada e retomada do pipeline `targets`

Data/hora da anotação: 2026-05-21 17:22, America/Sao_Paulo.

## Estado no momento da parada

O `targets::tar_make(callr_function = NULL)` terminou sem precisar ser
interrompido manualmente. O console registrou:

- 23 alvos completados;
- 154 alvos pulados;
- tempo total: 1d 3h 50m 14.1s.

O alvo mais demorado, `china_demand_sdid_diagnostics_table`, terminou e ficou
salvo no `_targets`:

- runtime: 10h 47m 22.5s;
- conteúdo: diagnósticos SDiD para a crítica de China demand shock, incluindo
  participação contínua da China nas exportações, concentração por destino,
  margem de rank, exposição pré-2009 a bens primários e interações com
  2008-2009.

Depois dele também terminaram:

- `goal3_brazil_placebo_rank_volume_tests`;
- `brazil_sdid_spec_table`;
- `fect_ife_china_top_cov_pre_distance_trim`;
- `fect_ife_china_top_cov_pre_distance_trim_summary`.

Os tempos dos alvos maiores estão documentados em
`quality_reports/targets_runtime_log_2026-05-21.md`.

## Pendências detectadas por `tar_outdated()`

Após o fim do `tar_make`, `targets::tar_outdated()` ainda retornou estes alvos:

1. `selective_china_alignment_vote_level_models`
2. `selective_china_alignment_ddd_hr_nonhr_models`
3. `goal6_human_rights_vs_non_human_rights`
4. `selective_china_alignment_unga_targets_bundle`
5. `brazil_china_unvotes_similarity_by_year_2005_2012`
6. `plot_brazil_china_unvotes_similarity_by_issue_year_2005_2012`
7. `brazil_china_unvotes_resolution_2005_2012`
8. `brazil_china_unvotes_similarity_by_issue_year_2005_2012`
9. `selective_china_alignment_country_placebo_summary`

Esses alvos pertencem ao bloco de alinhamento seletivo Brasil-China na AGNU, não
ao bloco novo dos diagnósticos SDiD de China demand shock. Antes de renderizar a
versão final do paper, é melhor rodar `targets::tar_make(callr_function = NULL)`
novamente para resolver essa lista ou verificar por que esses alvos permanecem
marcados como desatualizados.

## Próximos passos ao retomar

1. Rodar:

```r
targets::tar_outdated()
```

2. Se os nove alvos acima ainda aparecerem, rodar:

```r
targets::tar_make(callr_function = NULL)
```

3. Ler e conferir a nova tabela:

```r
targets::tar_read(china_demand_sdid_diagnostics_table)
```

4. Renderizar `paper_v4.Rmd`.

5. Validar o PDF, especialmente:

- a nova tabela dos diagnósticos SDiD;
- a tabela de placebos com o threshold China #2 em 2004;
- as notas sobre 1.000 placebo replications nos SEs SDiD;
- a ausência de jargão "spell" na prosa voltada ao leitor.
