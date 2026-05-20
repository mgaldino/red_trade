# Created by use_targets().

# Load packages required to define the pipeline:
library(targets)
library(here)
library(tarchetypes)
# library(tarchetypes) # Load other packages as needed.

# Set target options:
tar_option_set(packages = c("tidyverse", "tidyr", "ggplot2", "janitor", "data.table", "geosphere",
                            "tidysynth", "here", "stringr", "readxl", "countrycode",
                            "wbstats", "synthdid", "fixest", "rvest", "httr", "purrr",
                            "stringr", "lubridate", "tidytext", "topicmodels", "tm",
                            "ggraph", "igraph", "grid", "patchwork", "quanteda", "globalmacrodata",
                            "ellmer", "jsonlite", "stringr", "keyring", "did",
                            "HonestDiD", "fwildclusterboot", "MASS",
                            "fect", "PanelMatch", "vdemdata"))

# Run the R scripts in the R/ folder with your custom functions:
tar_source("scripts/functions.R")
tar_source("scripts/functions_unvotes.R")
# tar_source("other_functions.R") # Source other scripts as needed.

# Replace the target list below with your own:
list(
  tar_target(wb_data, get_wb_data()),
  tar_target(country_file1,  here("raw data", "release_2","release_2.1_2000_2004.csv"), format = "file"),
  tar_target(country_file2, here("raw data", "release_2", "release_2.1_2005_2009.csv"), format = "file"),
  tar_target(country_file3, here("raw data", "release_2","release_2.1_2010_2014.csv"), format = "file"),
  tar_target(country_file4, here("raw data", "release_2","release_2.1_1990_1999.csv"), format = "file"),
  tar_target(country_file5, here("raw data", "release_2","release_2.1_2015_2019.csv"), format = "file"),
  tar_target(unga_file, here("raw data", "dataverse_files-2", "IdealpointestimatesAll_Jun2024.csv"), format = "file"),
  tar_target(gpi_file, here("raw data", "GPI with sub-components_1816-2050_20241007.xlsx"), format = "file"),
  tar_target(trade_file, here("raw data", "ITPDE_R03.csv"), format = "file"),
  tar_target(ideology_file, here("raw data", "global_leader_ideologies.csv"), format = "file"),
  tar_target(dpi_file, here("raw data", "database-political-institutions-2015.csv"), format = "file"),
  tar_target(unvotes_tarball, here("data", "raw", "unvotes", "unvotes_0.3.0.tar.gz"), format = "file"),
  tar_target(country_data, get_country_data2()),
  tar_target(unga_data, get_unga_data(unga_file)),
  tar_target(gpi_data, get_gpi_data(gpi_file)),
  tar_target(trade_data, get_trade_data(trade_file)),
  tar_target(trade_data_ranked, rank_trade(trade_data)),
  tar_target(goal3_brazil_rank_volume_data,
             goal9_brazil_rank_volume_data(trade_data)),
  tar_target(goal3_brazil_rank_volume_plot,
             goal9_plot_brazil_rank_volume(goal3_brazil_rank_volume_data)),
  tar_target(trade_data_cleaned, process_trade_data(trade_data)),
  tar_target(ideology_data, get_ideology_data(ideology_file)),
  tar_target(macro_data, get_macro()),
  tar_target(dpi_data, get_dpi_data(dpi_file)),
  tar_target(trade_agreement_data, get_us_trade_agreement(country_file1, country_file2, country_file3, country_file4, country_file5)),
  tar_target(final_df, join_df(country_data, unga_data, gpi_data, trade_data_cleaned, wb_data, macro_data, ideology_data)),
  tar_target(folha_df_p0, get_folhasp_newspieces(start=1, end=400)),
  tar_target(folha_df_p1, get_folhasp_newspieces(start=401, end=800)),
  tar_target(folha_df_p2, get_folhasp_newspieces(start=801, end=1200)),
  tar_target(folha_df_p3, get_folhasp_newspieces(start=1201, end=1600)),
  tar_target(folha_df_p4, get_folhasp_newspieces(start=1601, end=2000)),
  tar_target(folha_df, bind_folha(folha_df_p0, folha_df_p1, folha_df_p2, folha_df_p3, folha_df_p4)),
  # descriptive plots
  tar_target(plot_data, generate_plot_data(final_df)),
  tar_target(plot, plot_serie(plot_data)),
  tar_target(plot_ideal, plot_ideal_points(unga_data)),
  tar_target(plot_ideal_distance, plot_distance_unga(unga_data)),
  tar_target(trade_plot, plot_trade(trade_data_cleaned)),
  tar_target(plot_folha, folha_plot(folha_df)),
  tar_target(list_plots, create_list_graphs(folha_df, start=1, num_by=3, n_filter=8)),
  tar_target(list_plots_08_09, create_list_graphs(folha_df, start=6, end=7, num_by=1, n_filter=5)),
  # Resolution-level Brazil-China UNGA vote diagnostics
  tar_target(brazil_china_unvotes_resolution_2005_2012,
             build_brazil_china_unvotes_resolution_data(unvotes_tarball)),
  tar_target(brazil_china_unvotes_similarity_by_year_2005_2012,
             summarise_brazil_china_unvotes_similarity_by_year(
               brazil_china_unvotes_resolution_2005_2012
             )),
  tar_target(brazil_china_unvotes_similarity_by_issue_year_2005_2012,
             summarise_brazil_china_unvotes_similarity_by_issue_year(
               brazil_china_unvotes_resolution_2005_2012
             )),
  tar_target(plot_brazil_china_unvotes_similarity_by_issue_year_2005_2012,
             plot_brazil_china_unvotes_similarity_by_issue_year(
               brazil_china_unvotes_similarity_by_issue_year_2005_2012
             )),
  tar_target(goal6_human_rights_vs_non_human_rights,
             goal9_human_rights_vs_non_human_rights(
               brazil_china_unvotes_resolution_2005_2012
             )),
  # SDiD
  tar_target(synth_data, clean_synth_data(final_df, ranked_trade_data=trade_data_ranked,
                                         dpi_data=dpi_data, trade_agreement_data=trade_agreement_data)),
  # Vote-level selective UNGA alignment diagnostics for the paper
  tar_target(selective_china_alignment_unga_targets_bundle,
             build_selective_china_alignment_unga_targets(
               synth_data = synth_data,
               unvotes_tarball = unvotes_tarball
             )),
  tar_target(selective_china_alignment_vote_level_models,
             selective_china_alignment_unga_targets_bundle$vote_models),
  tar_target(selective_china_alignment_ddd_hr_nonhr_models,
             selective_china_alignment_unga_targets_bundle$ddd_models),
  tar_target(selective_china_alignment_country_placebo_summary,
             selective_china_alignment_unga_targets_bundle$country_placebo_summary),
  # residuals all countries
  tar_target(synth_fit, simple_fit(data=synth_data, filter_latin_america=FALSE)),
  tar_target(se_synth , se_sdid(synth_fit)),
  tar_target(goal6_sdid_outcome_results,
             goal9_sdid_outcome_results(synth_data, unga_data, synth_fit, se_synth)),
  tar_target(plot_trend, my_plot_trends(synth_fit)),
  tar_target(plot_parallel, my_plot_dif(synth_fit)),
  tar_target(plot_weights_coef, my_plot_weigths(synth_fit)),
  tar_target(spaghetti_plot, plot_controls(synth_fit)),
  # residuals latam
  tar_target(synth_fit_latam, simple_fit(synth_data, filter_latin_america=TRUE)),
  tar_target(se_synth_latam, se_sdid(synth_fit_latam)),
  tar_target(plot_trend_latam, my_plot_trends(synth_fit_latam)),
  tar_target(plot_parallel_latam, my_plot_dif(synth_fit_latam)),
  tar_target(plot_weights_coef_latam, my_plot_weigths(synth_fit_latam, latam=T)),
  #robustness checks
  tar_target(placebo_teste_treatment02, simple_fit(synth_data, time_treatment=2002, time_end=2009)),
  tar_target(se_synth_placebo2, se_sdid(placebo_teste_treatment02)),
  tar_target(placebo_teste_treatment11, simple_fit(synth_data, time_treatment=2011,  time_end=2019)),
  tar_target(se_synth_placebo1, se_sdid(placebo_teste_treatment11)),
  tar_target(placebo_teste_treatment04, simple_fit(synth_data, time_treatment=2004, time_end=2009)),
  tar_target(se_synth_placebo3, se_sdid(placebo_teste_treatment04)),
  tar_target(goal3_brazil_placebo_rank_volume_tests,
             goal9_brazil_rank_volume_placebos(
               goal3_brazil_rank_volume_data,
               synth_fit,
               se_synth,
               placebo_teste_treatment02,
               se_synth_placebo2,
               placebo_teste_treatment04,
               se_synth_placebo3,
               placebo_teste_treatment11,
               se_synth_placebo1
             )),
  # Robustness: baseline SDiD without institutional covariates
  tar_target(synth_data_baseline, clean_synth_data(final_df, ranked_trade_data=trade_data_ranked)),
  tar_target(synth_fit_baseline, simple_fit(data=synth_data_baseline, filter_latin_america=FALSE)),
  tar_target(se_synth_baseline, se_sdid(synth_fit_baseline)),
  tar_target(synth_fit_no_time_varying_covariates, simple_fit_no_time_varying_covariates(synth_data)),
  tar_target(se_synth_no_time_varying_covariates, se_sdid(synth_fit_no_time_varying_covariates)),
  tar_target(brazil_sdid_spec_table,
             make_brazil_sdid_spec_table(
               synth_fit,
               se_synth,
               synth_data,
               synth_fit_baseline,
               se_synth_baseline,
               synth_data_baseline,
               synth_fit_no_time_varying_covariates,
               se_synth_no_time_varying_covariates,
               synth_fit_latam,
               se_synth_latam
             )),
  # Phase 1.1: RMSPE diagnostics & permutation inference
  tar_target(rmspe_diagnostics, compute_rmspe(synth_fit)),
  tar_target(permutation_results, permutation_test(synth_data)),
  # Phase 1.2: Sensitivity analysis
  tar_target(synth_data_extended, clean_synth_data(final_df, trade_data_ranked, year_end = 2020,
                                                  dpi_data=dpi_data, trade_agreement_data=trade_agreement_data)),
  tar_target(sensitivity_results, sensitivity_analysis(synth_data, synth_data_extended)),
  # Phase 1.3: Extended sample (2009-2019)
  tar_target(synth_fit_extended, simple_fit(synth_data_extended, time_end = 2020)),
  tar_target(se_synth_extended, se_sdid(synth_fit_extended)),
  # Phase 1.4: Donor pool composition table
  tar_target(donor_table, donor_pool_table(synth_fit, unga_data, trade_data_cleaned)),
  # Phase 2: Cross-country event study
  tar_target(treatment_events, identify_treatment_events(trade_data_ranked)),
  tar_target(event_study_data, prepare_event_study_data(treatment_events, unga_data)),
  tar_target(did_results, run_cross_country_did(event_study_data)),
  # Phase 2b: Restricted cross-country DiD
  tar_target(classified_events, classify_treatment_events(trade_data_ranked, trade_data)),
  tar_target(did_absorbing, run_restricted_did(event_study_data, classified_events, restrict_absorbing = TRUE)),
  tar_target(did_absorbing_usa, run_restricted_did(event_study_data, classified_events, restrict_absorbing = TRUE, restrict_displaced_usa = TRUE)),
  # Phase 2c: USA-was-#1 control group (main specification)
  tar_target(usa_top_countries, get_usa_top_countries(trade_data)),
  tar_target(event_study_data_usa, filter_usa_top_control(event_study_data, classified_events, usa_top_countries)),
  tar_target(did_displaced_usa, run_cross_country_did(event_study_data_usa)),
  tar_target(plot_es_displaced_usa, plot_event_study_did(did_displaced_usa)),
  # Wild cluster bootstrap (stacked DiD, USA-was-#1 control)
  tar_target(wild_bootstrap_result, run_wild_cluster_bootstrap(event_study_data_usa, classified_events,
                                                                restrict_displaced_usa = TRUE,
                                                                B = 9999)),
  # Fisher randomization test (USA-was-#1 control)
  tar_target(fisher_test_result, fisher_randomization_test(event_study_data_usa, classified_events,
                                                            n_perms = 1000)),
  tar_target(plot_fisher, plot_fisher_test(fisher_test_result)),
  # Phase 3: fect + PanelMatch (switching treatment)
  tar_target(switching_panel, build_switching_panel(trade_data, unga_data, classified_events, usa_top_countries)),
  tar_target(covariates_panel, build_covariates(final_df)),
  # Phase 3a: pooled China top-partner treatment
  # Sample includes all countries observed in both the trade data and the UNGA
  # ideal-point data. Treatment = 1 when China is the country's largest export
  # destination within that panel.
  tar_target(china_top_panel, build_china_top_partner_panel(
    trade_data,
    unga_data
  )),
  tar_target(china_top_panel_summary, summarize_china_top_panel(china_top_panel)),
  tar_target(china_pre_china_distance_1996_2000,
             build_pre_china_distance(china_top_panel, years = 1996:2000)),
  tar_target(china_top_pre_distance_balance_table,
             make_pre_china_distance_balance_table(
               china_top_panel,
               china_pre_china_distance_1996_2000
             )),
  tar_target(plot_china_top_pre_distance_balance,
             plot_pre_china_distance_balance(
               china_top_pre_distance_balance_table
             )),
  tar_target(china_top_panel_cov, dplyr::left_join(china_top_panel, covariates_panel, by = c("iso3c", "year"))),
  tar_target(china_top_panel_cov_pre_distance_trim,
             filter_pre_china_distance_sample(
               china_top_panel_cov,
               china_pre_china_distance_1996_2000,
               cutoff_prob = 0.75
             )),
  tar_target(china_top_pre_distance_trim_summary,
             summarize_pre_china_distance_trim(
               china_top_panel_cov,
               china_top_panel_cov_pre_distance_trim,
               china_pre_china_distance_1996_2000,
               cutoff_prob = 0.75
             )),
  tar_target(china_top_absorbing_sample,
             prepare_absorbing_china_top_sample(china_top_panel)),
  tar_target(china_top_absorbing_sample_validation,
             validate_absorbing_china_top_sample(china_top_absorbing_sample)),
  tar_target(china_top_absorbing_cov_sample,
             prepare_absorbing_china_top_covariate_sample(
               china_top_absorbing_sample,
               covariates_panel,
               covariate_cols = c("log_gdp_pc", "free_press")
             )),
  tar_target(china_top_absorbing_cov_sample_validation,
             validate_absorbing_china_top_sample(china_top_absorbing_cov_sample)),
  tar_target(china_top_fect_data, prepare_fect_data(china_top_absorbing_sample)),
  tar_target(china_top_fect_cov_data, prepare_fect_data(
    china_top_absorbing_cov_sample,
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
  )),
  tar_target(fect_fe_china_top, run_fect_analysis(china_top_fect_data, method = "fe", nboots = 10000L)),
  tar_target(fect_ife_china_top, run_fect_analysis(china_top_fect_data, method = "ife", nboots = 10000L)),
  tar_target(fect_ife_china_top_summary, summarize_fect_model(fect_ife_china_top, china_top_fect_data)),
  tar_target(fect_ife_china_top_cov, run_fect_analysis(china_top_fect_cov_data, method = "ife",
             nboots = 10000L, fml = abs_distance_china ~ china_top + log_gdp_pc + free_press)),
  tar_target(fect_ife_china_top_cov_summary, summarize_fect_model(
    fect_ife_china_top_cov,
    china_top_fect_cov_data,
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
  )),
  tar_target(china_top_fect_cov_pre_distance_trim_data, prepare_fect_data(
    prepare_absorbing_china_top_sample(
      china_top_panel_cov_pre_distance_trim,
      covariate_cols = c("log_gdp_pc", "free_press")
    ),
    fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
  )),
  tar_target(fect_ife_china_top_cov_pre_distance_trim,
             run_fect_analysis(
               china_top_fect_cov_pre_distance_trim_data,
               method = "ife",
               nboots = 10000L,
               fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
             )),
  tar_target(fect_ife_china_top_cov_pre_distance_trim_summary,
             summarize_fect_model(
               fect_ife_china_top_cov_pre_distance_trim,
               china_top_fect_cov_pre_distance_trim_data,
               fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
             )),
  tar_target(plot_fect_ife_gap_china_top_cov,
             plot_fect_gap(fect_ife_china_top_cov, "Absorbing IFE with covariates: entry-aligned gap plot")),
  tar_target(plot_fect_ife_gap_china_top,
             plot_fect_gap(fect_ife_china_top, "Absorbing IFE: entry-aligned gap plot")),
  tar_target(plot_diagnostics_equiv_china_top,
             plot_fect_equiv_appendix(fect_fe_china_top, fect_ife_china_top)),
  tar_target(fect_ife_china_top_recent_pretrend_f_test,
             reconstruct_fect_recent_pretrend_f_test(
               fect_ife_china_top,
               model = "Main: fect IFE",
               max_recent_periods = 12L
             )),
  tar_target(fect_ife_china_top_cov_recent_pretrend_f_test,
             reconstruct_fect_recent_pretrend_f_test(
               fect_ife_china_top_cov,
               model = "Robustness: fect IFE + covariates",
               max_recent_periods = 12L
             )),
  tar_target(cross_country_recent_pretrend_f_test_table,
             make_fect_recent_pretrend_table(
               fect_ife_china_top_recent_pretrend_f_test,
               fect_ife_china_top_cov_recent_pretrend_f_test
             )),
  tar_target(plot_treated_panel_china_top, plot_china_top_country_panel(china_top_fect_data)),
  tar_target(fect_ife_china_top_loo, run_fect_leave_one_out(china_top_fect_data, nboots = 10000L)),
  tar_target(china_top_fect_no_hub_entrepot_data,
             prepare_fect_data(
               filter_absorbing_treated_cases(
                 china_top_absorbing_sample,
                 excluded_iso3c = c("MYS", "SLE")
               )
             )),
  tar_target(fect_ife_china_top_no_hub_entrepot,
             run_fect_analysis(
               china_top_fect_no_hub_entrepot_data,
               method = "ife",
               nboots = 10000L
             )),
  tar_target(fect_ife_china_top_no_hub_entrepot_summary,
             summarize_fect_model(
               fect_ife_china_top_no_hub_entrepot,
               china_top_fect_no_hub_entrepot_data
             )),
  tar_target(china_top_fect_drop_slb_data,
             prepare_fect_data(
               filter_absorbing_treated_cases(
                 china_top_absorbing_sample,
                 excluded_iso3c = "SLB"
               )
             )),
  tar_target(fect_ife_china_top_drop_slb,
             run_fect_analysis(
               china_top_fect_drop_slb_data,
               method = "ife",
               nboots = 10000L
             )),
  tar_target(fect_ife_china_top_drop_slb_summary,
             summarize_fect_model(
               fect_ife_china_top_drop_slb,
               china_top_fect_drop_slb_data
             )),
  tar_target(cross_country_incumbent_salience_appendix_table,
             make_incumbent_salience_scope_table(
               fect_ife_china_top_summary,
               fect_ife_china_top_no_hub_entrepot_summary,
               fect_ife_china_top_drop_slb_summary
             )),
  tar_target(china_top_absorbing_cs_data, china_top_absorbing_sample),
  tar_target(did_china_top_absorbing, run_cross_country_did(
    china_top_absorbing_cs_data,
    aggte_na_rm = TRUE
  )),
  tar_target(did_china_top_absorbing_summary, summarize_cross_country_did(
    did_china_top_absorbing,
    china_top_absorbing_cs_data
  )),
  tar_target(china_top_absorbing_cs_cov_data, china_top_absorbing_cov_sample),
  tar_target(did_china_top_absorbing_cov, run_cross_country_did(
    china_top_absorbing_cs_cov_data,
    xformla = ~ log_gdp_pc + free_press,
    aggte_na_rm = TRUE
  )),
  tar_target(did_china_top_absorbing_cov_summary, summarize_cross_country_did(
    did_china_top_absorbing_cov,
    china_top_absorbing_cs_cov_data
  )),
  tar_target(plot_es_china_top_absorbing, plot_event_study_did(did_china_top_absorbing)),
  tar_target(china_top_short_lived_fect_data,
             prepare_fect_data(prepare_nonabsorbing_china_top_fect_data(china_top_panel))),
  tar_target(fect_ife_china_top_short_lived,
             run_fect_analysis(china_top_short_lived_fect_data, method = "ife", nboots = 10000L)),
  tar_target(fect_ife_china_top_short_lived_summary,
             summarize_fect_model(fect_ife_china_top_short_lived, china_top_short_lived_fect_data)),
  tar_target(china_top_short_lived_fect_cov_data,
             prepare_fect_data(
               prepare_nonabsorbing_china_top_fect_data(
                 china_top_panel_cov,
                 covariate_cols = c("log_gdp_pc", "free_press")
               ),
               fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
             )),
  tar_target(fect_ife_china_top_short_lived_cov,
             run_fect_analysis(
               china_top_short_lived_fect_cov_data,
               method = "ife",
               nboots = 10000L,
               fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
             )),
  tar_target(fect_ife_china_top_short_lived_cov_summary,
             summarize_fect_model(
               fect_ife_china_top_short_lived_cov,
               china_top_short_lived_fect_cov_data,
               fml = abs_distance_china ~ china_top + log_gdp_pc + free_press
             )),
  tar_target(cross_country_absorbing_main_table,
             make_cross_country_absorbing_table(
               fect_ife_china_top_summary,
               fect_ife_china_top_cov_summary,
               did_china_top_absorbing_summary,
               did_china_top_absorbing_cov_summary
             )),
  tar_target(cross_country_short_lived_appendix_table,
             make_cross_country_short_lived_table(
               fect_ife_china_top_short_lived_summary,
               fect_ife_china_top_short_lived_cov_summary
             )),
  tar_target(switching_panel_cov, dplyr::left_join(switching_panel, covariates_panel, by = c("iso3c", "year"))),
  tar_target(fect_fe, run_fect_analysis(switching_panel, method = "fe")),
  tar_target(fect_ife, run_fect_analysis(switching_panel, method = "ife")),
  tar_target(fect_ife_cov, run_fect_analysis(switching_panel_cov, method = "ife",
             fml = abs_distance_china ~ china_top + log_gdp_pc + free_press)),
  tar_target(fect_carryover, run_fect_carryover(switching_panel)),
  tar_target(panelmatch_att, run_panelmatch_analysis(switching_panel, qoi = "att")),
  tar_target(panelmatch_art, run_panelmatch_analysis(switching_panel, qoi = "art")),
  tar_target(plot_fect_ife_gap, plot_fect_gap(fect_ife, "IFE: Entry-aligned gap plot")),
  tar_target(plot_fect_ife_exit, plot_fect_exit(fect_ife, "IFE: Exit-aligned gap plot")),
  tar_target(plot_pm_combined, plot_panelmatch_combined(panelmatch_att, panelmatch_art)),
  # C&S with covariates (absorbing-only, balanced panel)
  tar_target(event_study_data_usa_cov, {
    cov_merged <- dplyr::left_join(event_study_data_usa, covariates_panel, by = c("iso3c", "year"))
    complete <- cov_merged[complete.cases(cov_merged[, c("log_gdp_pc", "free_press")]), ]
    max_yr <- max(table(complete$id))
    bal_ids <- complete %>% dplyr::group_by(id) %>%
      dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
      dplyr::filter(n == max_yr) %>% dplyr::pull(id)
    complete[complete$id %in% bal_ids, ]
  }),
  tar_target(did_displaced_usa_cov, run_cross_country_did(event_study_data_usa_cov,
             xformla = ~ log_gdp_pc + free_press,
             aggte_na_rm = TRUE)),
  # Diagnostic plots (Liu, Wang & Xu 2024 Figure 8 style)
  tar_target(plot_diagnostics_main, plot_fect_diagnostics(fect_ife, fect_fe, fect_carryover)),
  tar_target(plot_diagnostics_equiv, plot_fect_equiv_appendix(fect_fe, fect_ife)),
  # Raw data panel for treated countries
  tar_target(plot_treated_panel, plot_treated_country_panel(switching_panel, classified_events)),
  # Phase 4: Devil's Advocate responses
  # Leave-one-out fect IFE (drop each treated country)
  tar_target(fect_ife_loo, run_fect_leave_one_out(switching_panel)),
  # Exploratory scope specification using the same China top-partner rule.
  tar_target(switching_panel_any, build_any_displacement_panel(trade_data, unga_data, classified_events)),
  tar_target(fect_ife_any, run_fect_analysis(switching_panel_any, method = "ife")),
  # Media counterfactual
  tar_target(folha_classified_file, here("data", "folha_classificado.rds"), format = "file"),
  tar_target(media_counterfactual, build_media_counterfactual(folha_classified_file)),
  tar_target(sample_headlines_image_file, here("images", "table1_headlines.png"), format = "file"),
  # Cohen's kappa for ChatGPT validation
  tar_target(validation_file, here("data", "folha_validation_sample_annotated.csv"), format = "file"),
  tar_target(chatgpt_validation_summary, build_chatgpt_validation_summary(validation_file)),
  tar_target(cohens_kappa, compute_cohens_kappa(validation_file))
)
