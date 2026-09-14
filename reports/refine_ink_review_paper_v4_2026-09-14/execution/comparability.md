# Adjudicação delimitada: itens 11 e 22

**Resultado:** 2 CONFIRMED; propostas textuais prontas para implementação separada. Nenhuma alteração do manuscrito. Os valores numéricos permanecem intactos.

Fonte ativa e baseline têm SHA-256 `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4`. PDF: `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312`. As citações selecionadas do parecer correspondem ao fonte e ao texto extraído do PDF. Isso verifica os trechos em exame, não a proveniência integral do upload ao revisor. Não foi necessário contrato argumentativo para esta adjudicação delimitada.

## Item 11: mapa das cinco linhas da Tabela 4

| Início | Janela | Pré nominal | Pós nominal | Horizonte | Amostra | ATT existente | Contrafactual |
|---|---|---|---|---:|---|---:|---|
| 2003 | 1997–2008 | 1997–2002 | 2003–2008 | 6 anos | Brasil + mesmos 95 doadores; 1152 país-anos | -0.064 | SDiD sem covariáveis, pesos reajustados nesta linha |
| 2004 | 1997–2008 | 1997–2003 | 2004–2008 | 5 anos | Brasil + mesmos 95 doadores; 1152 país-anos | -0.109 | SDiD sem covariáveis, pesos reajustados nesta linha |
| 2005 | 1997–2008 | 1997–2004 | 2005–2008 | 4 anos | Brasil + mesmos 95 doadores; 1152 país-anos | -0.099 | SDiD sem covariáveis, pesos reajustados nesta linha |
| 2009 | 1997–2015 | 1997–2008 | 2009–2015 | 7 anos | Brasil + mesmos 95 doadores; 1824 país-anos | -0.273 | SDiD sem covariáveis, pesos reajustados nesta linha |
| 2012 | 1997–2016 | 1997–2011 | 2012–2016 | 5 anos | Brasil + mesmos 95 doadores; 1920 país-anos | -0.100 | SDiD sem covariáveis, pesos reajustados nesta linha |

A linha de 2009 é a especificação preferida; 2003–2005 são pseudo-inícios anteriores à entrada efetiva e 2012 é uma quebra tardia cujo pré nominal inclui 2009–2011 já tratados. Todos usam o mesmo objeto `synth_data`, com filtros de janela, sem seleção adicional de países no helper. Os 95 doadores e a ausência de missing/duplicatas foram verificados diretamente no objeto salvo. Não foram recalculados pesos nem ATTs.

Produtor efetivamente consumido: `audit_brazil_sdid_no_covariates.R:247-280` → `sdid_fit_spec()` em `sdid_placebo_helpers.R:107-146` → `timing_placebos.csv` → `paper_v4.Rmd:377-378,758-803`. O helper chama `synthdid_estimate()` novamente para cada especificação. A função legada `goal9_brazil_rank_volume_placebos()` contém SEs, mas não produz o CSV consumido por esta tabela; seus SEs não devem ser transferidos para estas linhas.

## Item 22: resultados existentes e limites

O produtor `audit_ungadm_postreview_diagnostics.R:214-285` deriva ambas as medidas das mesmas linhas do risk set restrito (durabilidade de cinco anos), até 2020 e com UNGA-DM observado. O CSV da janela comum registra 1990–2020, 4.727 país-anos, 161 países, 35 tratados e 126 controles. As quatro células usam 10.000 bootstraps de inferência, sem smoke test.

| Medida | r=1 ATT (p) | r=2 ATT (p) | r=2 menos r=1, aritmética existente |
|---|---:|---:|---:|
| BSV | -0.035975914 (0.336406848) | -0.095321560 (0.016295990) | -0.059345646 |
| UNGA-DM | -0.026818587 (0.573196959) | -0.064838822 (0.237778665) | -0.038020234 |

A diferença entre as duas mudanças é 0.021325412 nas escalas numéricas originais. Isso demonstra não aditividade descritiva da tabela; não é teste de interação, evidência de interação estatisticamente significativa ou contribuição invariável à escala. Não foi produzido resultado novo para o paper.

O bootstrap pareado usa os mesmos sorteios de países, estratificados em tratados/controles, nas duas medidas. `CV=FALSE` em cada réplica: a comparação “procedure-selected” mantém r=2 para BSV e r=1 para UNGA-DM escolhidos na amostra original; a outra mantém r=2 em ambas. Os 1.000 sorteios já salvos têm status ok e nenhuma falha. Os CSVs de draws e summary foram reconciliados (erro máximo 1.11e-16), incluindo diferenças, médias, desvios, quantis e p-valores. Diferenças observadas: 0.068502973 (p percentil 0.134) e 0.030482738 (p 0.356). São diferenças brutas UNGA-DM menos BSV; não demonstram equivalência ou decomposição invariante à escala.

## Item 11: CONFIRMED

**Comentário original:** The timing rows appear to estimate averages over different calendar periods, post-onset horizons, and fitted SDiD counterfactuals. Because no uncertainty is reported for the differences between rows, their ordering provides suggestive timing evidence but does not establish that the 2009 effect differs statistically from the earlier pseudo-onsets or the later break.

**Localizações:** paper_v4.Rmd:693-695; paper_v4.Rmd:526-541; paper_v4.Rmd:756-783; scripts/diagnostics/audit_brazil_sdid_no_covariates.R:247-280; scripts/diagnostics/sdid_placebo_helpers.R:107-146; data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/timing_placebos.csv:2-6; output/paper_v4.pdf:23, Table 4

**Evidência do defeito:** Post-onset horizons are 6, 5, 4, 7, and 5 years. The helper constructs a new treatment vector and calls synthdid_estimate separately for each row; no shared fitted counterfactual or cross-row contrast inference is supplied. Table 4 note calls all rows estimated causal effects after nominal onset; text uses early magnitudes against the Lula account and describes stability across timing tests. The later-break nominal pre-period includes actual treated years 2009-2011.

**Evidência limitadora/contrária:** The manuscript already calls the rows point-estimate diagnostics, notes early truncation and later extension, and supplies preferred 2009 inference elsewhere. The donor identities are common, so sample membership differences are not the source of incomparability.

**Adjudicação:** The reviewer correctly limits the ordering to suggestive timing evidence. Identical donor identities do not equate calendar periods, horizons, treatment histories or fitted SDiD weights. Matching horizons and adding individual SEs alone would still not define a common causal estimand or valid inference for between-row differences.

**Proposta:** Use localized diagnostic language and complete table notes; retain every numeric output. Change the overlapping Lula paragraph only to remove the selected cross-window comparability inference, without adjudicating item 12.

## Item 22: CONFIRMED

**Comentário original:** The 2 × 2 comparison does not uniquely isolate factor-count and outcome-source components. The factor-count contrast differs across outcomes, indicating an interaction, while the two ideal-point measures may have different absolute scales. The table supports conditional sensitivity comparisons, but the raw cross-outcome ATT differences and paired bootstrap do not by themselves identify a scale-invariant outcome-source contribution beyond factor selection.

**Localizações:** paper_v4.Rmd:2239-2240; paper_v4.Rmd:2417-2454; paper_v4.Rmd:2461-2507; scripts/diagnostics/audit_ungadm_postreview_diagnostics.R:214-285; scripts/diagnostics/audit_ungadm_postreview_diagnostics.R:287-381; data/processed/diagnostics/ungadm_outcome_robustness/postreview/ife_2x2_fixed_r.csv:2-5; data/processed/diagnostics/ungadm_outcome_robustness/postreview/ife_paired_bootstrap_summary.csv:2-3; output/paper_v4.pdf:68-69, Tables 27-28

**Evidência do defeito:** The factor contrast r2-r1 is -0.059345646431 under BSV and -0.038020234148 under UNGA-DM. Their descriptive difference is 0.021325412283 in the original numerical scales; no interaction test was found in the traced outputs. Repeated text says isolates/assessed separately/outcome metric contributes beyond factor selection. Paired differences are unstandardized UNGA-DM minus BSV, not a scale-invariant decomposition. Counts are fixed within bootstrap replicates, not reselected.

**Evidência limitadora/contrária:** The 2x2 genuinely holds the common panel fixed at 4,727 observations, 161 countries (35 treated, 126 controls), 1990-2020, and permits conditional within-measure factor comparisons. The final paragraph already explicitly says non-rejection does not establish equivalence. Table 28 reports both factor counts rather than hiding sensitivity. All displayed numerical results match the existing CSVs.

**Adjudicação:** The design supports conditional sensitivity statements, not a unique additive attribution. Nonadditivity is descriptive and scale-dependent, not established statistically by the saved bootstrap. A common panel and fixed factor count do not harmonize outcome units. Paired non-rejection neither proves equivalence nor identifies an outcome-source contribution.

**Proposta:** Replace all isolation/decomposition occurrences and associated notes with conditional within-measure comparisons, explicit scale limits and non-equivalence. Preserve numbers and unrelated Brazil robustness statements, including wording reserved to unselected comments.

## Substituições exatas propostas

Cada bloco OLD é único no fonte ativo e no baseline. NEW é proposta, não patch aplicado. Parágrafos completos são reproduzidos quando a alteração é de prosa; nas notas, preservam-se os consumidores inline e todos os valores. O item 11 alcança a inferência de comparabilidade no parágrafo de Lula, mas não adjudica o comentário 12. No item 22, a frase sobre médias prévias reservada ao item 34 fica intacta.

### 1. Item 11 — paper_v4.Rmd:693-693

OLD:
```rmd
The rank interpretation requires more than showing that trade with China was increasing. Brazil's exports to China grew before 2009, including years in which China rose in the export hierarchy but did not become number one. Table \@ref(tab:table-placebo) therefore reports outcome-path timing falsifications without covariates: using no covariates prevents variables measured after the early pseudo-onsets from entering those comparisons. The 2003, 2004, and 2005 estimates are smaller than the 2009 rank-one estimate; 2004 is especially useful because China first reaches rank 2 but is still not Brazil's largest export destination. The 2012 row probes a later break after China had already become the top destination. These are point-estimate diagnostics rather than additional tests with separately recomputed placebo inference.
```

NEW:
```rmd
The rank interpretation requires more than showing that trade with China was increasing. Brazil's exports to China grew before 2009, including years in which China rose in the export hierarchy but did not become number one. Table \@ref(tab:table-placebo) therefore reports outcome-path timing falsifications without covariates: using no covariates prevents variables measured after the early pseudo-onsets from entering those comparisons. The 2003, 2004, and 2005 estimates are smaller in absolute value than the 2009 rank-one estimate; 2004 is especially useful because China first reaches rank 2 but is still not Brazil's largest export destination. The 2012 row probes a later break after China had already become the top destination. Each row refits the SDiD counterfactual over a different pre- or post-onset window. The early estimates average 2003--2008, 2004--2008, and 2005--2008, compared with 2009--2015 for the preferred estimate and 2012--2016 for the later break. Their ordering is suggestive timing evidence, not a comparison of a common estimand or a test that the effects differ. No uncertainty for differences between rows is reported, and the 2012 fit uses already-treated years in its nominal pre-period.
```

### 2. Item 11 — paper_v4.Rmd:695-695

OLD:
```rmd
The same timing logic addresses the main Brazilian political confounder. President Lula da Silva took office in 2003 and pursued a more explicit South-South foreign-policy agenda, a shift emphasized in work on Brazilian autonomy, presidential foreign policy, and international engagement [@neto2011; @mouron_urdinez2014; @neto_malamud2015; @rodrigues2019measuring; @schenoniMythsMultipolaritySources2022]. If that ideological shift were sufficient to explain Brazil-China UNGA convergence, the pseudo-treatment years in 2003 or 2005 should already show comparable movement. They do not. The cross-country panel also estimates the rank-threshold pattern across countries with different political systems and leadership profiles, which reduces the concern that the Brazil estimate is only a Lula-period artifact.
```

NEW:
```rmd
The same timing logic addresses the main Brazilian political confounder. President Lula da Silva took office in 2003 and pursued a more explicit South-South foreign-policy agenda, a shift emphasized in work on Brazilian autonomy, presidential foreign policy, and international engagement [@neto2011; @mouron_urdinez2014; @neto_malamud2015; @rodrigues2019measuring; @schenoniMythsMultipolaritySources2022]. The 2003 and 2005 pseudo-onsets yield smaller point estimates in absolute value, providing suggestive evidence against an immediate large break. Because these estimates cover different periods and refit the counterfactual, they do not establish that the early and 2009 effects differ or exclude a gradual or delayed Lula-era shift. The cross-country panel also estimates the rank-threshold pattern across countries with different political systems and leadership profiles, which reduces the concern that the Brazil estimate is only a Lula-period artifact.
```

### 3. Item 11 — paper_v4.Rmd:756-756

OLD:
```rmd
The cross-country panel below is a broader scope check, not the main answer to the Brazil-specific demand-shock critique. Brazil is included in the goods-only cross-country sample, but the panel aligns countries by their own China-top goods-export entry years. A Brazil-specific 2009 confounder cannot mechanically generate an average event-time effect across countries treated in different calendar years. For such an explanation to account for both the Brazil estimate and the cross-country result, the omitted force would need to coincide with durable China-top entry across countries, affect UNGA distance to China in the same direction, and remain outside the latent factors captured by the interactive fixed-effects specification. It would also need to be strongly enough associated with both treatment timing and the outcome to overturn estimates that are stable across the Brazil timing tests, donor-pool checks, and the cross-country duration and risk-set checks.
```

NEW:
```rmd
The cross-country panel below is a broader scope check, not the main answer to the Brazil-specific demand-shock critique. Brazil is included in the goods-only cross-country sample, but the panel aligns countries by their own China-top goods-export entry years. A Brazil-specific 2009 confounder cannot mechanically generate an average event-time effect across countries treated in different calendar years. For such an explanation to account for both the Brazil estimate and the cross-country result, the omitted force would need to coincide with durable China-top entry across countries, affect UNGA distance to China in the same direction, and remain outside the latent factors captured by the interactive fixed-effects specification. It would also need to be strongly enough associated with both treatment timing and the outcome to overturn estimates that are stable across the donor-pool checks and the cross-country duration and risk-set checks, alongside the suggestive Brazil timing diagnostics.
```

### 4. Item 11 — paper_v4.Rmd:526-526

OLD:
```rmd
  kableExtra::pack_rows("E. Windows and timing: stability of the point estimate", 12, 15,
```

NEW:
```rmd
  kableExtra::pack_rows("E. Windows and timing: point-estimate diagnostics", 12, 15,
```

### 5. Item 11 — paper_v4.Rmd:530-541

OLD:
```rmd
      "SDiD = synthetic difference-in-differences; preferred specification has no covariates. ",
      "Estimates and root mean squared prediction error (RMSPE) are in absolute UNGA ",
      "ideal-point distance to China; negative estimates indicate convergence. ",
      "RMSPE removes the mean pre-treatment gap. Placebo ranks include Brazil and ",
      "95 donor assignments; their p-value interpretation requires comparable assignments. ",
      "In D, changes are relative to the preferred estimate; high-weight donors are the top ten, ",
      "and exposure means China is a top-two export destination in at least one year during 2009--2015 (share of total donor weight). ",
      "D--E report point estimates, without recomputed inference. Full donor and time weights ",
      "and all sensitivity results appear in the appendix."
    ),
    general_title = "Note: ",
    escape = TRUE,
```

NEW:
```rmd
      "SDiD = synthetic difference-in-differences; preferred specification has no covariates. ",
      "Estimates and root mean squared prediction error (RMSPE) are in absolute UNGA ",
      "ideal-point distance to China; negative estimates indicate convergence. ",
      "RMSPE removes the mean pre-treatment gap. Placebo ranks include Brazil and ",
      "95 donor assignments; their p-value interpretation requires comparable assignments. ",
      "In D, changes are relative to the preferred estimate; high-weight donors are the top ten, ",
      "and exposure means China is a top-two export destination in at least one year during 2009--2015 (share of total donor weight). ",
      "D--E report point estimates, without recomputed inference. Full donor and time weights ",
      "and all sensitivity results appear in the appendix. The 2004 and 2009 onset rows use different ",
      "pre- and post-onset periods and separately fitted counterfactuals; their ordering is suggestive ",
      "and does not establish a statistically significant difference between effects."
    ),
    general_title = "Note: ",
    escape = TRUE,
```

### 6. Item 11 — paper_v4.Rmd:773-783

OLD:
```rmd
rank_tests_note <- paste0(
  sub(
    "^Note: ",
    "",
      caption_note(
      unit = "Outcome is absolute UNGA ideal-point distance to China; ATT is the estimated causal effect on Brazil after the nominal onset, so negative values mean convergence; export margins are current USD billions",
      window = "2003-2005 timing tests end in 2008; 2012 is a later-break falsification using data through 2016"
    )
  ),
  " All rows are no-covariate point-estimate diagnostics. The preferred 2009 estimate and its inference are reported separately in the main specification."
)
```

NEW:
```rmd
rank_tests_note <- paste0(
  sub(
    "^Note: ",
    "",
      caption_note(
      unit = "Outcome is absolute UNGA ideal-point distance to China; ATT denotes the SDiD estimate for Brazil after each nominal onset; negative values indicate convergence; export margins are current USD billions",
      window = "all windows begin in 1997. Post-onset periods are 2003-2008, 2004-2008, 2005-2008, 2009-2015, and 2012-2016 (6, 5, 4, 7, and 5 years)"
    )
  ),
  " All rows use Brazil and the same 95 donors, without covariates, but refit unit and time weights for each window and onset. These are suggestive diagnostics with different estimands, not tests of differences between effects; no uncertainty for the cross-row contrasts is reported. The 2012 nominal pre-period includes already-treated years. The preferred 2009 estimate and its inference are reported separately in the main specification."
)
```

### 7. Item 22 — paper_v4.Rmd:2239-2240

OLD:
```rmd
The two outcome measures preserve the negative direction of the Brazilian SDiD estimate, but they do not support a blanket claim of robustness across the Brazilian and cross-country designs. Table \@ref(tab:ungadm-sdid-comparison) shows the comparison. Under UNGA-DM, the point estimate is nominally higher than the original in absolute terms (`r sprintf("%.3f", ungadm_dm_row$estimate)` versus `r sprintf("%.3f", ungadm_bsv_row$estimate)`), with a lower p-value of `r sprintf("%.3f", ungadm_dm_row$p_normal_two_sided)`. The directional rank is the same in both measurements (`r ungadm_fmt_rank(ungadm_dm_row$rank_one_sided, ungadm_dm_row$rank_denominator, ungadm_dm_row$p_rank_one_sided)`). The bilateral rank improves from `r ungadm_fmt_rank(ungadm_bsv_row$rank_two_sided, ungadm_bsv_row$rank_denominator, ungadm_bsv_row$p_rank_two_sided)` to `r ungadm_fmt_rank(ungadm_dm_row$rank_two_sided, ungadm_dm_row$rank_denominator, ungadm_dm_row$p_rank_two_sided)`. It is noteworthy that the pre-treatment averages are different (`r sprintf("%.3f", ungadm_bsv_row$brazil_pre_mean)` against
`r sprintf("%.3f", ungadm_dm_row$brazil_pre_mean)`) in the original estimation. But the effect measured as a percentage of the pre-treatment average is similar: `r sprintf("%.1f", ungadm_bsv_row$estimate_pct_pre_mean)` and `r sprintf("%.1f", ungadm_dm_row$estimate_pct_pre_mean)` percent. The Brazilian result therefore retains its direction and inferential support under the alternative measure, with a similar relative magnitude. The cross-country comparison below is more sensitive to the outcome source: its IFE estimate is materially smaller and less precise under UNGA-DM. The $2\times2$ comparison below holds the common window and country-year panel fixed while varying the outcome source and factor count, so the contribution of factor selection can be assessed separately from the outcome-source difference.
```

NEW:
```rmd
The two outcome measures preserve the negative direction of the Brazilian SDiD estimate, but they do not support a blanket claim of robustness across the Brazilian and cross-country designs. Table \@ref(tab:ungadm-sdid-comparison) shows the comparison. Under UNGA-DM, the point estimate is nominally higher than the original in absolute terms (`r sprintf("%.3f", ungadm_dm_row$estimate)` versus `r sprintf("%.3f", ungadm_bsv_row$estimate)`), with a lower p-value of `r sprintf("%.3f", ungadm_dm_row$p_normal_two_sided)`. The directional rank is the same in both measurements (`r ungadm_fmt_rank(ungadm_dm_row$rank_one_sided, ungadm_dm_row$rank_denominator, ungadm_dm_row$p_rank_one_sided)`). The bilateral rank improves from `r ungadm_fmt_rank(ungadm_bsv_row$rank_two_sided, ungadm_bsv_row$rank_denominator, ungadm_bsv_row$p_rank_two_sided)` to `r ungadm_fmt_rank(ungadm_dm_row$rank_two_sided, ungadm_dm_row$rank_denominator, ungadm_dm_row$p_rank_two_sided)`. It is noteworthy that the pre-treatment averages are different (`r sprintf("%.3f", ungadm_bsv_row$brazil_pre_mean)` against
`r sprintf("%.3f", ungadm_dm_row$brazil_pre_mean)`) in the original estimation. But the effect measured as a percentage of the pre-treatment average is similar: `r sprintf("%.1f", ungadm_bsv_row$estimate_pct_pre_mean)` and `r sprintf("%.1f", ungadm_dm_row$estimate_pct_pre_mean)` percent. The Brazilian result therefore retains its direction and inferential support under the alternative measure, with a similar relative magnitude. The cross-country comparison below is more sensitive to the outcome source: its IFE point estimate is closer to zero on the UNGA-DM scale and its uncertainty interval includes zero. The $2\times2$ comparison below holds the common window and country-year panel fixed while varying the outcome source and factor count, allowing conditional factor-count comparisons within each measure. It does not provide a unique, scale-invariant decomposition of the difference between outcomes.
```

### 8. Item 22 — paper_v4.Rmd:2417-2419

OLD:
```rmd
Regarding the panel regression, Table \@ref(tab:ungadm-ife-window) shows the IFE estimation in the same time window for both outcomes, and the original estimation with the larger time window. The estimate retains the negative sign but is smaller and less precise under UNGA-DM:
`r sprintf("%.3f", ungadm_ife_dm_common$att)` with p =
`r sprintf("%.3f", ungadm_ife_dm_common$p)`. However, the models are not the same, since the number of latent factors chosen by cross-validation is different: `r ungadm_ife_bsv_common$r_cv` under BSV and `r ungadm_ife_dm_common$r_cv` under UNGA-DM. The $2\times2$ comparison below holds the common window and country-year panel fixed while crossing the outcome source with one versus two latent factors, allowing the factor-count component to be assessed separately.
```

NEW:
```rmd
Regarding the panel regression, Table \@ref(tab:ungadm-ife-window) shows the IFE estimation in the same time window for both outcomes, and the original estimation with the larger time window. The estimate retains the negative sign but is closer to zero on the UNGA-DM scale, with an uncertainty interval that includes zero:
`r sprintf("%.3f", ungadm_ife_dm_common$att)` with p =
`r sprintf("%.3f", ungadm_ife_dm_common$p)`. However, the models are not the same, since the number of latent factors chosen by cross-validation is different: `r ungadm_ife_bsv_common$r_cv` under BSV and `r ungadm_ife_dm_common$r_cv` under UNGA-DM. The $2\times2$ comparison below holds the common window and country-year panel fixed while crossing the outcome source with one versus two latent factors, allowing the sensitivity to factor count to be assessed within each outcome measure, rather than uniquely decomposing the cross-outcome difference.
```

### 9. Item 22 — paper_v4.Rmd:2461-2461

OLD:
```rmd
Table \@ref(tab:ungadm-ife-2x2) holds the common window and country-year panel fixed and crosses the two outcome sources with one and two latent factors. This $2\times2$ design isolates the factor-count component of the comparison. Holding the outcome fixed, moving from one to two factors makes the ATT more negative (larger in absolute value): from `r sprintf("%.3f", ungadm_ife_bsv_r1$att)` to `r sprintf("%.3f", ungadm_ife_bsv_r2$att)` under BSV, and from `r sprintf("%.3f", ungadm_ife_dm_r1$att)` to `r sprintf("%.3f", ungadm_ife_dm_r2$att)` under UNGA-DM. Cross-validation selects `r ungadm_ife_bsv_common$r_cv` factors under BSV and `r ungadm_ife_dm_common$r_cv` under UNGA-DM. The one-factor UNGA-DM fit selected by cross-validation has the same negative sign and substantially overlapping uncertainty with the fixed-two-factor fit, although its point estimate is less negative; factor selection therefore changes magnitude without reversing the qualitative pattern. Holding the factor count at two still leaves a smaller UNGA-DM estimate (`r sprintf("%.3f", ungadm_ife_dm_r2$att)`) than the BSV estimate (`r sprintf("%.3f", ungadm_ife_bsv_r2$att)`), so the outcome source remains relevant after the factor-count component is isolated.
```

NEW:
```rmd
Table \@ref(tab:ungadm-ife-2x2) holds the common window and country-year panel fixed and crosses the two outcome sources with one and two latent factors. This $2\times2$ comparison describes sensitivity to factor count conditional on the outcome measure. Holding the outcome fixed, moving from one to two factors makes the ATT more negative (larger in absolute value): from `r sprintf("%.3f", ungadm_ife_bsv_r1$att)` to `r sprintf("%.3f", ungadm_ife_bsv_r2$att)` under BSV, and from `r sprintf("%.3f", ungadm_ife_dm_r1$att)` to `r sprintf("%.3f", ungadm_ife_dm_r2$att)` under UNGA-DM. Cross-validation selects `r ungadm_ife_bsv_common$r_cv` factors under BSV and `r ungadm_ife_dm_common$r_cv` under UNGA-DM. The change from one to two factors differs across the two measures, indicating a descriptive interaction between outcome source and factor count rather than a unique additive decomposition. This comparison does not test the interaction. Both UNGA-DM fits have negative point estimates and uncertainty intervals that include zero; overlapping intervals do not establish equivalence. Holding the factor count at two still leaves a smaller UNGA-DM estimate (`r sprintf("%.3f", ungadm_ife_dm_r2$att)`) than the BSV estimate (`r sprintf("%.3f", ungadm_ife_bsv_r2$att)`), but these raw estimates are expressed on different outcome scales. Their difference is a conditional sensitivity comparison, not a scale-invariant contribution attributable to outcome source.
```

### 10. Item 22 — paper_v4.Rmd:2447-2454

OLD:
```rmd
    general = paste0(
      "All rows use the goods-only status-current restricted risk set with ",
      ungadm_ife_bsv_common$n_treated, " treated and ",
      ungadm_ife_bsv_common$n_control, " control countries. ",
      "The common-window rows keep exactly the same country-years in both outcome sources. ",
      "Confidence intervals come from ", format(ungadm_ife_bsv_common$nboots, big.mark = ","),
      " bootstrap replications."
    ),
```

NEW:
```rmd
    general = paste0(
      "All rows use the goods-only status-current restricted risk set with ",
      ungadm_ife_bsv_common$n_treated, " treated and ",
      ungadm_ife_bsv_common$n_control, " control countries. ",
      "The common-window rows keep exactly the same country-years in both outcome sources. ",
      "Confidence intervals come from ", format(ungadm_ife_bsv_common$nboots, big.mark = ","),
      " bootstrap replications. ATTs and intervals are expressed on each outcome's original scale; ",
      "raw cross-outcome differences do not identify a scale-invariant measurement contribution."
    ),
```

### 11. Item 22 — paper_v4.Rmd:2489-2500

OLD:
```rmd
    general = paste0(
      "Same common window and identical rows as the previous table. ",
      "Paired bootstrap on the difference between the two ATTs, ",
      format(ungadm_boot_selected$n_valid, big.mark = ","),
      " replications and no failures: ",
      sprintf("%.3f", ungadm_boot_selected$observed_diff),
      " (percentile p = ", sprintf("%.3f", ungadm_boot_selected$p_two_sided_percentile),
      ") under procedure-selected factor counts, and ",
      sprintf("%.3f", ungadm_boot_common$observed_diff),
      " (percentile p = ", sprintf("%.3f", ungadm_boot_common$p_two_sided_percentile),
      ") with common factors."
    ),
```

NEW:
```rmd
    general = paste0(
      "Same common window and identical rows as the previous table. ",
      "Paired bootstrap on UNGA-DM minus BSV in their original outcome units, ",
      format(ungadm_boot_selected$n_valid, big.mark = ","),
      " replications and no failures: ",
      sprintf("%.3f", ungadm_boot_selected$observed_diff),
      " (percentile p = ", sprintf("%.3f", ungadm_boot_selected$p_two_sided_percentile),
      ") with the original CV-selected counts held fixed (BSV: two; UNGA-DM: one), and ",
      sprintf("%.3f", ungadm_boot_common$observed_diff),
      " (percentile p = ", sprintf("%.3f", ungadm_boot_common$p_two_sided_percentile),
      ") with two factors for both outcomes. The same stratified country draws are used for both ",
      "measures; factor counts are not reselected within replications. These are scale-dependent ",
      "contrasts, not a unique decomposition of factor and outcome-source components. ",
      "Non-rejection does not establish equivalence."
    ),
```

### 12. Item 22 — paper_v4.Rmd:2507-2507

OLD:
```rmd
To sum up, the Brazilian SDiD result retains its negative direction and inferential support across the two outcome measurements, with similar relative magnitude but a different absolute scale. The $2\times2$ IFE comparison shows that two factors produce a more negative ATT under either outcome, while the one-factor choice selected by cross-validation for UNGA-DM remains qualitatively close to the two-factor fit, with the same sign and overlapping uncertainty. Even with two factors held fixed, the UNGA-DM estimate remains smaller than the BSV estimate, so the outcome metric contributes beyond factor selection. The paired test does not detect a statistically significant difference between the ATTs, but this non-rejection does not establish equivalence and may reflect uncertainty.
```

NEW:
```rmd
To sum up, the Brazilian SDiD result retains its negative direction and inferential support across the two outcome measurements, with similar relative magnitude but a different absolute scale. The $2\times2$ IFE comparison shows that two factors produce a more negative ATT under either outcome, with a different within-measure change under BSV and UNGA-DM. Both UNGA-DM fits have negative point estimates and uncertainty intervals that include zero; this does not establish equivalence between them. Even with two factors held fixed, the raw UNGA-DM estimate is closer to zero than the BSV estimate on its own scale. This conditional comparison does not isolate a scale-invariant outcome-source contribution beyond factor selection. The paired test does not detect a statistically significant difference between the ATTs, but this non-rejection does not establish equivalence and may reflect uncertainty.
```

## Verificação, gates e limitações

Inspeção estática: trechos delimitados do fonte, produtores, consumidores e texto das páginas selecionadas do PDF (`comparability_pdf_evidence.txt`). Não foi feita auditoria visual de diagramação. Verificação computada: contagens do objeto já salvo, aritmética e resumos dos CSVs existentes, hashes e unicidade das substituições. Análise nova: nenhuma. Ver script `comparability_verify.R` e saída `comparability_verification.txt`.

Não se recomenda igualar horizontes e adicionar SEs como correção automática: isso ainda não estabelece estimando comum, tratamento comparável ou teste das diferenças. Para uma futura análise dessas diferenças, seria preciso especificar primeiro população, períodos, exposição e contrafactual comuns e inferência conjunta, implementados como targets desde o início e sob autorização. Tampouco se recomenda padronizar medidas ou estimar interação nesta adjudicação: novos resultados exigem definição substantiva de escala/estimando e especificação target-first autorizada. Nada disso é necessário para as correções textuais propostas.

Veredito técnico: READY_FOR_IMPLEMENTATION, restrito às propostas textuais dos itens 11 e 22. Não autoriza execução, edição ou publicação. Não foram alterados manuscrito, dados, targets, arquivos compartilhados ou Git.

Validação final: schema oficial `adjudicate-review` VALID contra `paper_v4.Rmd`; 12 correspondências OLD únicas e todas as expressões R inline preservadas. O diff global mostrou alterações em `execution/sdid.json`, alheias a esta tarefa; esse arquivo não foi tocado.
