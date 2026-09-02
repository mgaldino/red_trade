# Contrato da integração do manuscrito ao `targets`

## Escopo e ponto de partida

Este contrato governa a remoção das 27 folhas externas registradas em
`migration/baseline_direct_paper_leaves.csv` e a promoção, dentro da branch de
migração, do painel cross-country corrigido por união completa das fontes. O baseline
é o estado descrito em `migration/baseline_contract.md`; os arquivos legados são
comparadores, não dependências de produção do manuscrito.

Nenhuma edição deste bloco autoriza coleta HTTP, `targets::tar_make()`, modelos,
placebos, bootstraps, renderização do R Markdown ou alteração do checkout de `main`.

## Mapa das 27 folhas externas

### SDiD Brasil: doze tabelas em memória

Uma única leitura de `brazil_sdid_paper_outputs_candidate` deve alimentar os objetos
abaixo. O manuscrito não pode reler os CSVs de diagnóstico nem os CSVs candidatos
gravados pelo pipeline.

| Folha legada | Elemento do target | Objeto no manuscrito |
|---|---|---|
| `main_summary.csv` | `$main_summary` | `sdid_main_summary` |
| `unit_weights.csv` | `$unit_weights` | `sdid_unit_weights` |
| `time_weights.csv` | `$time_weights` | `sdid_time_weights` |
| `balance.csv` | `$balance` | `sdid_balance` |
| `rank_inference.csv` | `$rank_inference` | `sdid_rank_inference` |
| `placebo_distribution.csv` | `$placebo_distribution` | `sdid_placebo_distribution` |
| `donor_sensitivity.csv` | `$donor_sensitivity` | `sdid_donor_sensitivity` |
| `window_sensitivity.csv` | `$window_sensitivity` | `sdid_window_sensitivity` |
| `donor_china_exposure.csv` | `$donor_china_exposure` | `sdid_donor_china_exposure` |
| `donor_china_exposure_summary.csv` | `$donor_china_exposure_summary` | `sdid_high_weight_exposure_summary` |
| `timing_placebos.csv` | `$timing_placebos` | `sdid_timing_placebos` |
| `latam_core_summary.csv` | `$latam_core_summary` | `sdid_latam_core_summary` |

### Commodity/Table 5

`table_5_sdid_specification_results.csv` deve ser substituído pela leitura em memória
de `brazil_sdid_commodity_table_candidate`.

### Figuras SDiD

| Folha legada | File target |
|---|---|
| `figure_brazil_sdid_predetermined_core_fit.png` | `brazil_sdid_main_fit_figure_candidate` |
| `figure_brazil_sdid_predetermined_core_weights.png` | `brazil_sdid_weights_figure_candidate` |
| `figure_brazil_sdid_predetermined_core_latam_fit.png` | `brazil_sdid_latam_fit_figure_candidate` |
| `figure_brazil_sdid_dose_response_panel.pdf` | novo `brazil_sdid_dose_response_panel_files_candidate` |

O novo painel de dose–resposta deve ser gerado pelo script versionado
`scripts/diagnostics/plot_brazil_sdid_dose_response_panel.R`, parametrizado para receber
os file targets `brazil_sdid_dose_placebo_donors_file` e
`brazil_sdid_dose_placebo_summary_file`. O target declara e devolve PDF e PNG sob
`images/targets_migration/`; o manuscrito consome o PDF devolvido pelo target.

### Figura cross-country

`images/figure6_cross_country_dynamic_with_pooled_att.png` deve ser substituída pelo
novo file target `china_top_m2_goods_full_union_dynamic_pooled_figure_candidate`. Ele
recebe `china_top_m2_goods_full_union_status_dynamic_results` e
`china_top_m2_goods_full_union_status_model_results`, depende do gate do painel mestre
e preserva as validações do gráfico legado: especificação preferida única, horizontes
únicos, valores finitos, suporte positivo, soma do suporte igual ao denominador do ATT
e média ponderada dos ATTs dinâmicos igual ao ATT agregado a `1e-10`.

### UNGA-DM: nove tabelas em memória

| Folha legada | Target/elemento | Objeto no manuscrito |
|---|---|---|
| `sdid_comparison_table.csv` | `ungadm_sdid_outputs_candidate$comparison` | `ungadm_sdid_comparison` |
| `sdid_dm_placebo_distribution.csv` | `ungadm_sdid_outputs_candidate$placebo_distribution` | `ungadm_dm_placebo` |
| `sdid_dm_rank_inference_harmonized.csv` | `ungadm_sdid_outputs_candidate$rank_inference_harmonized` | `ungadm_rank_criteria` |
| `sdid_unit_weights_bsv_vs_dm.csv` | `ungadm_sdid_outputs_candidate$unit_weights_bsv_vs_dm` | `ungadm_weights` |
| `ife_comparison_table.csv` | `ungadm_ife_comparison_candidate` | `ungadm_ife_comparison` |
| `ife_2x2_fixed_r.csv` | `ungadm_ife_fixed_grid_candidate` | `ungadm_ife_2x2` |
| `ife_paired_bootstrap_summary.csv` | `ungadm_ife_paired_bootstrap_summary_candidate` | `ungadm_boot` |
| `dm_rows_without_iso3c_mapping.csv` | `ungadm_unmapped_rows_candidate` | `ungadm_unmapped` |
| `sdid_dm_missing_outcome_rows.csv` | `ungadm_sdid_panel_bundle_candidate$missing` | `ungadm_missing_outcome` |

## Promoção do painel mestre corrigido dentro do manuscrito

As leituras antigas `china_top_m2_goods_status_current_*` no manuscrito devem ser
substituídas pelos objetos `china_top_m2_goods_full_union_*` correspondentes:

- resultados dos modelos: `china_top_m2_goods_full_union_status_model_results`;
- auditoria setorial: `china_top_m2_goods_full_union_sector_audit`;
- resumo de unidades: `china_top_m2_goods_full_union_status_unit_summary`;
- auditoria de codificação: novo
  `china_top_m2_goods_full_union_country_audit_candidate`, derivado da classificação
  de períodos da grade mestre, nunca do outcome.

A auditoria de países deve manter as categorias substantivas da tabela atual quando
aplicáveis e distinguir unidades sem ranking comercial observado. Ela é construída
antes da filtragem por outcome e não substitui as contagens da amostra estimada.

## Invariantes

1. `paper_v4.Rmd` não pode conter nenhum dos 27 caminhos registrados no baseline.
2. O manuscrito lê tabelas analíticas em memória com `tar_read()` e figuras somente
   pelos caminhos devolvidos por file targets.
3. Nenhuma leitura do manuscrito pode voltar aos CSVs candidatos gravados em
   `data/processed/targets_migration/`.
4. Os doze objetos SDiD, a tabela de commodity e as nove tabelas UNGA-DM preservam
   nomes, ordem de colunas, tipos, chaves, dimensões e valores já aprovados nos gates
   dos respectivos blocos.
5. O painel cross-country usado pelo texto, tabelas e figura é o full-union corrigido:
   grade 1990–2023, tratamento anterior à filtragem por outcome e `COD–2021`
   preservado no mestre, mas excluído da estimação por outcome ausente.
6. O resultado cross-country corrigido esperado é o do contrato do baseline:
   ATT `-0.10072962830167595`, 5.002 observações, 160 países e 440 períodos tratados.
   Qualquer diferença após o build deve ser adjudicada.
7. A geração das duas figuras novas deve falhar diante de schema incompleto, valores
   não finitos, chaves duplicadas ou inconsistência entre estatísticas resumidas e
   dados subjacentes.
8. Os caminhos de saída das figuras novas ficam em `images/targets_migration/` e são
   declarados com `format = "file"`.
9. Nenhum target novo acessa a rede, descobre arquivo por ordenação de nomes, usa o
   relógio de execução ou lê o store do checkout principal.
10. Toda alteração R deste bloco exige revisão independente com `review-r` até
    `A/PASS`; uma revisão de commit anterior não cobre mudanças posteriores.

## Testes autorizados antes do build

Estão autorizados apenas parsing estático, `git diff --check`, inspeção do DAG sem
materializar alvos, validações de texto/AST e fixtures temporárias que não executem
modelos ou writers das figuras de produção. O build, a comparação numérica efetiva das
novas estimações, a renderização do PDF e a inspeção visual permanecem em gate separado
e dependem de autorização específica do autor.
