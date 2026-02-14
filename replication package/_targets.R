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
                            "HonestDiD", "fwildclusterboot", "MASS"))

# Run the R scripts in the R/ folder with your custom functions:
tar_source("scripts/functions.R")
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
  tar_target(country_data, get_country_data2()),
  tar_target(unga_data, get_unga_data(unga_file)),
  tar_target(gpi_data, get_gpi_data(gpi_file)),
  tar_target(trade_data, get_trade_data(trade_file)),
  tar_target(trade_data_ranked, rank_trade(trade_data)),
  tar_target(trade_data_cleaned, process_trade_data(trade_data)),
  tar_target(ideology_data, get_ideology_data(ideology_file)),
  tar_target(macro_data, get_macro()),
  tar_target(final_df, join_df(country_data, unga_data, gpi_data, trade_data_cleaned, wb_data, macro_data, ideology_data)), # dpi_data
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
  # SDiD
  tar_target(synth_data, clean_synth_data(final_df, ranked_trade_data=trade_data_ranked)),
  # residuals all countries
  tar_target(synth_fit, simple_fit(data=synth_data, filter_latin_america=FALSE)),
  tar_target(se_synth , se_sdid(synth_fit)),
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
  # Phase 1.1: RMSPE diagnostics & permutation inference
  tar_target(rmspe_diagnostics, compute_rmspe(synth_fit)),
  tar_target(permutation_results, permutation_test(synth_data)),
  # Phase 1.2: Sensitivity analysis
  tar_target(synth_data_extended, clean_synth_data(final_df, trade_data_ranked, year_end = 2020)),
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

  # Phase 2d: Heterogeneity analysis (pre-computed outside the pipeline)
  # See scripts/compute_heterogeneity_data.R — must be run first
  tar_target(het_data_file, here("data", "heterogeneity_vars.rds"), format = "file"),
  tar_target(het_data, load_heterogeneity_data(het_data_file)),
  tar_target(event_study_data_usa_het,
             add_heterogeneity_vars(event_study_data_usa, het_data)),

  # DiD with continuous moderators as covariates
  tar_target(did_cov_streak, run_did_with_covariates(event_study_data_usa_het,
                                                      xformla = ~usa_streak)),
  tar_target(did_cov_press, run_did_with_covariates(event_study_data_usa_het,
                                                     xformla = ~press_free)),
  tar_target(did_cov_both, run_did_with_covariates(event_study_data_usa_het,
                                                    xformla = ~usa_streak + press_free)),

  # Robustness: exclude 2008/2009 treated (crisis-period countries), with covariates
  tar_target(did_no_crisis, run_exclude_crisis_did(event_study_data_usa_het, classified_events,
                                                    xformla = ~usa_streak + press_free)),

  # --- Descriptive table & raw data plot ---
  tar_target(table_treated, table_treated_descriptive(unga_data, classified_events, het_data)),
  tar_target(plot_treated_panel, plot_treated_country_panel(unga_data, classified_events,
                                                             event_study_data_usa)),

  # --- Alternative panels (1991+, 1995+) ---
  tar_target(panel_1991, build_alternative_panel(1991, treatment_events, unga_data,
                                                  classified_events, usa_top_countries, het_data)),
  tar_target(panel_1995, build_alternative_panel(1995, treatment_events, unga_data,
                                                  classified_events, usa_top_countries, het_data)),
  tar_target(did_1991_baseline, run_cross_country_did(panel_1991)),
  tar_target(did_1991_both, run_did_with_covariates(panel_1991,
                                                     xformla = ~usa_streak + press_free)),
  tar_target(did_1995_baseline, run_cross_country_did(panel_1995)),
  tar_target(did_1995_both, run_did_with_covariates(panel_1995,
                                                     xformla = ~usa_streak + press_free)),

  # --- Dynamic event study data frames ---
  tar_target(es_baseline, extract_event_study_df(did_displaced_usa, "1990+, Baseline (8)")),
  tar_target(es_cov_both, extract_event_study_df(did_cov_both, "1990+, + Both (8)")),
  tar_target(es_1995_baseline, extract_event_study_df(did_1995_baseline, "1995+, Baseline (10)")),
  tar_target(es_1995_both, extract_event_study_df(did_1995_both, "1995+, + Both (10)")),
  tar_target(es_no_crisis, extract_event_study_df(did_no_crisis, "1990+, excl 2008+2009 (5)")),

  # --- Dynamic event study plots ---
  tar_target(plot_es_facet, plot_event_study_facet(
    list(es_baseline, es_cov_both, es_1995_baseline, es_1995_both, es_no_crisis))),
  tar_target(plot_es_overlay, plot_event_study_overlay(es_baseline, es_cov_both))
)