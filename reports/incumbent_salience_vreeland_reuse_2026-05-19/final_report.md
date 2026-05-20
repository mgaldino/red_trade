# Final report: LPV reuse and incumbent-salience diagnostics

Data: 2026-05-19  
Escopo: análise diagnóstica fora do `targets`; `_targets.R`, `_targets/`, `_targets.yaml` e `paper_v4.Rmd` não foram editados; `targets::tar_make()` não foi executado.

## 1. Coleta e documentação dos dados LPV

Os dados de replicação de Liu, Pang & Vreeland (2026), DOI `https://doi.org/10.7910/DVN/MWAPWV`, foram baixados via script reproduzível:

- Script: `scripts/data_collection/download_liu_pang_vreeland_2026_dataverse.py`
- Diretório bruto: `data/raw/external/liu_pang_vreeland_2026/`
- Fontes: `data/raw/external/liu_pang_vreeland_2026/SOURCES.yaml`
- Log: `data/raw/external/liu_pang_vreeland_2026/COLLECTION_LOG.md`
- Checksums: `data/raw/external/liu_pang_vreeland_2026/checksums.sha256`

Foram preservados 19 arquivos brutos, incluindo `BSAupdate.RData`, `BRI_2020.tab`, `Data_SWAPNet_panel_202207.xlsx`, `ITT_confusion.csv` e scripts de replicação.

## 2. Reutilização de variáveis LPV

Arquivo principal reutilizável: `BSAupdate.RData`, objeto `datasave`, painel país-ano 1992-2021.

Variáveis candidatas:

- `partner_level`: escala ordinal de parceria diplomática com a China.
- `partner_level_lag1`: versão defasada, temporalmente adequada para uso em `t0`.
- `pre_entry_high_level_partner`: dummy derivada como `partner_level_lag1 >= 4` na linha `year == t0`.
- `pre_entry_bri_mou`: admissível apenas se `bri_mou_year < t0`.

Recomendação: usar `pre_entry_partner_level` ou `pre_entry_high_level_partner` apenas como robustez/descritivo. Não usar `swap_dummy`, `signdate`, BSA ou `ever BRI` como moderadores deste desenho.

## 3. Dummies finais de incumbente deslocado

O incumbente deslocado é `top_export_destination_{i,t0-1}`, onde `t0` é o ano de treatment entry/onset.

Definições finais:

- `displaced_us = 1` se `displaced_partner == "USA"`.
- `displaced_g7 = 1` se `displaced_partner` está em `{CAN, FRA, DEU, ITA, JPN, GBR, USA}`.
- `displaced_regional_power = 1` se `displaced_partner` está em `{USA, BRA, MEX, ARG, DEU, FRA, GBR, RUS, TUR, EGY, IRN, SAU, NGA, ZAF, IND, PAK, JPN, KOR, IDN, AUS}`.

O CSV final adiciona diagnósticos de saliência:

- margem de share exportado incumbente-China em `t0 - 1`;
- persistência do incumbente nos cinco anos pré-entrada;
- incumbente modal no pré-período;
- flag de hubs/entrepôts (`ARE`, `BEL`, `CHE`, `HKG`, `SGP`);
- warning de saliência.

Arquivo: `data/processed/diagnostics/incumbent_salience_moderators_2026-05-19.csv`.

## 4. Revisões críticas

A primeira avaliação Devil's Advocate deu nota B e apontou risco de confundir ranking comercial anual com saliência política. A operacionalização foi revisada para incluir margem, persistência, incumbente modal e hubs. A reavaliação final deu nota A para workflow diagnóstico preliminar, condicionada a não interpretar as interações como identificação causal definitiva.

A revisão independente de R encontrou dois problemas críticos antes da execução: inferência incorreta para grouped ATT e ausência de validação de unicidade antes dos joins. Ambos foram corrigidos antes do smoke test e da execução com 500 bootstraps.

## 5. Modelos de 500 bootstraps

O script `scripts/diagnostics/reestimate_cross_country_incumbent_salience_500_bootstrap.R` usa o sample principal atual de `fect` no repositório: `china_top_absorbing_sample`, lido via `targets::tar_read()`. Esse sample tem 105 países, 14 tratados absorventes e 91 controles nunca tratados.

Modelo base: `fect` IFE, efeitos fixos two-way, `r = 0:3` com validação cruzada, 500 bootstraps. Todos os modelos escolheram `r* = 2`. O `fect` avisou que não pôde calcular o F statistic por insuficiência de unidades tratadas.

Resultado geral:

- ATT = -0.100
- SE = 0.041
- IC 95% = [-0.180, -0.020]
- p = 0.014

Resultados por grupos:

- `displaced_us`: não EUA ATT = -0.091; EUA ATT = -0.120.
- `displaced_g7`: não G7 ATT = -0.103; G7 ATT = -0.099.
- `displaced_regional_power`: não potência regional ATT = -0.092; potência regional ATT = -0.103.
- `pre_entry_high_level_partner`: não high-level ATT = -0.089; high-level ATT = -0.187.

Interpretação preliminar: o efeito geral continua negativo. Não há diferença material entre G7 e não G7 nem entre a dummy ampla de potência regional e sua contraparte. O grupo `displaced_us` e o grupo `pre_entry_high_level_partner` aparecem mais negativos, mas as células são pequenas: 4 países no grupo EUA e 3 países no grupo high-level partner. Isso deve ser tratado como sinal exploratório, não evidência causal forte.

## 6. Limitações e próximos passos

Principais limitações:

- A amostra principal de `fect` tem apenas 14 tratados absorventes.
- Entre esses tratados, 10 de 14 têm algum warning de saliência: 7 margem estreita, 2 hubs/entrepôts e 1 baixa persistência.
- `displaced_regional_power` é conceitualmente ampla e mistura tipos diferentes de poder.
- `pre_entry_partner_level` é temporalmente pré-tratamento, mas está conceitualmente próximo do mecanismo de alinhamento político com a China.

Próximos passos antes de editar o paper:

- event studies por subgrupo;
- testes de leads/pre-trends por moderador;
- leave-one-country-out;
- especificações excluindo hubs/entrepôts;
- decompor potência regional em EUA, G7, potência regional da mesma macrorregião e grandes potências externas;
- testar versões alternativas do incumbente: modal pré-entrada e persistente.

## 7. Arquivos principais

- `vreeland_data_reuse_assessment.md`
- `regional_power_operationalization_lit_review.md`
- `incumbent_salience_operationalization_draft.md`
- `devils_advocate_operationalization_round1.md`
- `devils_advocate_operationalization_final.md`
- `incumbent_salience_operationalization_final.md`
- `r_code_review.md`
- `model_results_500_bootstrap.md`
- `model_results_500_bootstrap_overall.csv`
- `model_results_500_bootstrap_group_att.csv`
- `model_results_500_bootstrap_cell_counts.csv`
- `model_results_500_bootstrap_salience_diagnostics.csv`
- `model_run_500_bootstrap.log`
- `model_sessionInfo_500_bootstrap.txt`

## 8. Follow-up: event studies, pretrends, influence, hubs e decomposição

Após o diagnóstico inicial, foi executado o script `scripts/diagnostics/diagnose_incumbent_salience_followup_event_pretrend_loo.R`, também fora do `targets`.

Principais resultados C&S:

- Baseline: ATT = -0.101, SE = 0.047, IC 95% [-0.193, -0.009], p = 0.032.
- Event studies por subgrupo: os efeitos médios por subgrupo mantêm sinal negativo, mas quase todos têm ICs largos e poucos tratados.
- Leads/pretrends: os pretests formais ficam indisponíveis (`NA`) por matriz de covariância singular; na janela próxima `-5:-2`, nenhum subgrupo tem lead significativo a 5%, mas há sinais em leads mais distantes, registrados em `all_pre_n_p_below_005`.
- Leave-one-out: a exclusão mais influente é Solomon Islands (`SLB`), que move o ATT de -0.101 para -0.066; nenhum único país reverte totalmente o sinal.
- Excluindo hubs/entrepôts (`MYS` e `SLE` na amostra absorvente), o ATT fica mais negativo: -0.118, SE = 0.054, p = 0.027.
- Decomposição de potência regional: `other_g7`, `other_incumbent` e `us` têm quatro tratados cada; `external_regional_or_global_power` e `same_region_regional_power` têm apenas um tratado e foram pulados por suporte insuficiente.

Arquivos de follow-up:

- `followup_diagnostics_event_pretrend_loo_hubs_decomposition.md`
- `followup_overall_att_by_diagnostic.csv`
- `followup_event_studies_by_subgroup.csv`
- `followup_pretrend_tests_by_subgroup.csv`
- `followup_leave_one_country_out_cs.csv`
- `followup_hub_exclusion_cases.csv`
- `followup_regional_power_decomposition_counts.csv`
- `followup_treated_cases_audit.csv`
- `followup_event_studies_by_subgroup.png`
