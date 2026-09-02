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
                            "fect", "PanelMatch", "vdemdata", "DBI", "duckdb"))

# Run the R scripts in the R/ folder with your custom functions:
tar_source("scripts/functions.R")
tar_source("scripts/functions_unvotes.R")
tar_source("scripts/functions_sdid_dose_placebo.R")
tar_source("scripts/functions_targets_migration.R")
tar_source("scripts/diagnostics/sdid_placebo_helpers.R")
tar_source("scripts/functions_sdid_targets_migration.R")
tar_source("scripts/functions_ungadm_targets_migration.R")
tar_source("scripts/functions_status_evidence_targets_migration.R")
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
  # Donor-eligibility screen on the SAME sector definition that defines
  # treatment (largest GOODS export destination). trade_data_ranked stays as
  # it is: other targets legitimately describe total trade. See
  # get_trade_data_goods() for why ranking the screen on total trade let a
  # treated unit (Malta 2011-2012) into the donor pool while excluding an
  # eligible one (Singapore).
  tar_target(trade_data_goods, get_trade_data_goods(trade_file)),
  tar_target(trade_data_goods_ranked, rank_trade(trade_data_goods)),
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
  tar_target(synth_data, clean_synth_data(final_df, ranked_trade_data=trade_data_goods_ranked,
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
  tar_target(se_synth , se_sdid(synth_fit, replications = 5000L)),
  tar_target(china_demand_primary_goods_export_exposure,
             goal9_pre2009_primary_goods_export_exposure(trade_file)),
  tar_target(china_demand_sdid_panel,
             goal9_build_china_demand_sdid_panel(
               synth_data,
               trade_data,
               china_demand_primary_goods_export_exposure
             )),
  tar_target(china_demand_sdid_diagnostics_table,
             goal9_china_demand_sdid_diagnostics(
               china_demand_sdid_panel,
               synth_fit,
               se_synth,
               se_replications = 5000L
             )),
  tar_target(goal6_sdid_outcome_results,
             goal9_sdid_outcome_results(synth_data, unga_data, synth_fit, se_synth)),
  tar_target(plot_trend, my_plot_trends(synth_fit)),
  tar_target(plot_parallel, my_plot_dif(synth_fit)),
  tar_target(plot_weights_coef, my_plot_weigths(synth_fit)),
  tar_target(spaghetti_plot, plot_controls(synth_fit)),
  # residuals latam
  tar_target(synth_fit_latam, simple_fit(synth_data, filter_latin_america=TRUE)),
  tar_target(se_synth_latam, se_sdid(synth_fit_latam, replications = 5000L)),
  tar_target(plot_trend_latam, my_plot_trends(synth_fit_latam)),
  tar_target(plot_parallel_latam, my_plot_dif(synth_fit_latam)),
  tar_target(plot_weights_coef_latam, my_plot_weigths(synth_fit_latam, latam=T)),
  #robustness checks
  tar_target(placebo_teste_treatment02, simple_fit(synth_data, time_treatment=2002, time_end=2009)),
  tar_target(se_synth_placebo2, se_sdid(placebo_teste_treatment02, replications = 5000L)),
  tar_target(placebo_teste_treatment03, simple_fit(synth_data, time_treatment=2003, time_end=2009)),
  tar_target(se_synth_placebo_rank2_2004, se_sdid(placebo_teste_treatment03, replications = 5000L)),
  tar_target(placebo_teste_treatment11, simple_fit(synth_data, time_treatment=2011,  time_end=2019)),
  tar_target(se_synth_placebo1, se_sdid(placebo_teste_treatment11, replications = 5000L)),
  tar_target(placebo_teste_treatment04, simple_fit(synth_data, time_treatment=2004, time_end=2009)),
  tar_target(se_synth_placebo3, se_sdid(placebo_teste_treatment04, replications = 5000L)),
  tar_target(goal3_brazil_placebo_rank_volume_tests,
             goal9_brazil_rank_volume_placebos(
               goal3_brazil_rank_volume_data,
               synth_fit,
               se_synth,
               placebo_teste_treatment02,
               se_synth_placebo2,
               placebo_teste_treatment03,
               se_synth_placebo_rank2_2004,
               placebo_teste_treatment04,
               se_synth_placebo3,
               placebo_teste_treatment11,
               se_synth_placebo1
             )),
  # Robustness: baseline SDiD without institutional covariates
  tar_target(synth_data_baseline, clean_synth_data(final_df, ranked_trade_data=trade_data_goods_ranked)),
  tar_target(synth_fit_baseline, simple_fit(data=synth_data_baseline, filter_latin_america=FALSE)),
  tar_target(se_synth_baseline, se_sdid(synth_fit_baseline, replications = 5000L)),
  tar_target(synth_fit_no_time_varying_covariates, simple_fit_no_time_varying_covariates(synth_data)),
  # preferred column: no covariates makes replications cheap (~4 min); 20k pins the SE to +-0.001
  tar_target(se_synth_no_time_varying_covariates,
             run_sdid_placebo_se_candidate(
               synth_fit_no_time_varying_covariates,
               replications = 20000L,
               label = "no_covariates",
               checkpoint_block = "paper_sdid_preferred",
               seed = SDID_PLACEBO_SEED,
               core_cap = 12L
             )),
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
  tar_target(brazil_sdid_diagnostics_bundle,
             build_brazil_sdid_diagnostics_bundle(
               synth_data,
               synth_fit,
               se_synth,
               permutation_results,
               trade_data_ranked,
               trade_data_cleaned
             )),
  # Candidate migration of every Brazil SDiD CSV/figure currently read by the
  # paper. Expensive placebo targets stay separate and no paper-output file is
  # replaced before the side-by-side comparison passes. The existing preferred
  # SE target above keeps its public name but now has resumable computation.
  tar_target(brazil_sdid_preferred_se_info_candidate,
             reuse_sdid_preferred_se_candidate(
               synth_fit_no_time_varying_covariates,
               synth_fit_no_time_varying_covariates,
               se_synth_no_time_varying_covariates,
               replications = 20000L
             )),
  tar_target(brazil_sdid_preferred_rank_distribution_candidate,
             run_sdid_rank_distribution_candidate(
               synth_data,
               covariate_cols = character(0),
               label = "no_covariates",
               checkpoint_block = "paper_sdid_preferred"
             )),
  tar_target(brazil_sdid_latam_units_candidate,
             synth_data |>
               dplyr::filter(latin_america) |>
               dplyr::distinct(iso3c) |>
               dplyr::pull(iso3c)),
  tar_target(brazil_sdid_latam_fit_candidate,
             sdid_fit_spec(
               synth_data,
               units = union(brazil_sdid_latam_units_candidate, "BRA")
             )),
  tar_target(brazil_sdid_latam_se_candidate,
             run_sdid_placebo_se_candidate(
               brazil_sdid_latam_fit_candidate,
               replications = 20000L,
               label = "latam_no_covariates",
               checkpoint_block = "paper_sdid_latam",
               seed = SDID_PLACEBO_SEED,
               core_cap = 12L
             )),
  tar_target(brazil_sdid_latam_rank_distribution_candidate,
             run_sdid_rank_distribution_candidate(
               synth_data |>
                 dplyr::filter(
                   iso3c %in% union(brazil_sdid_latam_units_candidate, "BRA")
                 ),
               covariate_cols = character(0),
               label = "latam_no_covariates",
               checkpoint_block = "paper_sdid_latam"
             )),
  tar_target(brazil_sdid_paper_outputs_candidate,
             build_paper_sdid_outputs_candidate(
               synth_data,
               synth_fit_no_time_varying_covariates,
               brazil_sdid_preferred_se_info_candidate,
               brazil_sdid_preferred_rank_distribution_candidate,
               brazil_sdid_latam_fit_candidate,
               brazil_sdid_latam_se_candidate,
               brazil_sdid_latam_rank_distribution_candidate,
               goal3_brazil_rank_volume_data,
               trade_data_ranked,
               trade_data_cleaned
             )),
  tar_target(brazil_sdid_paper_reference_files,
             file.path(
               "data", "processed", "diagnostics",
               "paper_v4_brazil_sdid_no_covariates",
               paste0(
                 c(
                   "main_summary", "unit_weights", "time_weights", "balance",
                   "rank_inference", "placebo_distribution",
                   "donor_sensitivity", "window_sensitivity",
                   "donor_china_exposure", "donor_china_exposure_summary",
                   "timing_placebos", "latam_core_summary"
                 ),
                 ".csv"
               )
             ),
             format = "file"),
  tar_target(brazil_sdid_paper_outputs_validation_candidate,
             {
               brazil_sdid_paper_reference_files
               validate_paper_sdid_outputs_candidate(
                 brazil_sdid_paper_outputs_candidate,
                 file.path(
                   "data", "processed", "diagnostics",
                   "paper_v4_brazil_sdid_no_covariates"
                 )
               )
             }),
  tar_target(brazil_sdid_paper_outputs_validation_gate_candidate,
             assert_sdid_migration_validation(
               brazil_sdid_paper_outputs_validation_candidate,
               paper_sdid_output_validation_names()
             )),
  tar_target(brazil_sdid_paper_output_files_candidate,
             {
               brazil_sdid_paper_outputs_validation_gate_candidate
               write_paper_sdid_outputs_candidate(
                 brazil_sdid_paper_outputs_candidate,
                 file.path(
                   "data", "processed", "targets_migration",
                   "paper_v4_brazil_sdid_no_covariates"
                 )
               )
             },
             format = "file"),
  tar_target(brazil_sdid_main_fit_figure_candidate,
             {
               brazil_sdid_paper_outputs_validation_gate_candidate
               write_sdid_fit_figure_candidate(
                 synth_fit_no_time_varying_covariates,
                 file.path(
                   "images", "targets_migration",
                   "figure_brazil_sdid_predetermined_core_fit.png"
                 ),
                 "Preferred specification, estimated without covariates"
               )
             },
             format = "file"),
  tar_target(brazil_sdid_weights_figure_candidate,
             {
               brazil_sdid_paper_outputs_validation_gate_candidate
               write_sdid_weights_figure_candidate(
                 brazil_sdid_paper_outputs_candidate$unit_weights,
                 file.path(
                   "images", "targets_migration",
                   "figure_brazil_sdid_predetermined_core_weights.png"
                 )
               )
             },
             format = "file"),
  tar_target(brazil_sdid_latam_fit_figure_candidate,
             {
               brazil_sdid_paper_outputs_validation_gate_candidate
               write_sdid_fit_figure_candidate(
                 brazil_sdid_latam_fit_candidate,
                 file.path(
                   "images", "targets_migration",
                   "figure_brazil_sdid_predetermined_core_latam_fit.png"
                 ),
                 "Latin America donors, estimated without covariates"
               )
             },
             format = "file"),
  # Commodity inputs are reconstructed from the frozen raw ITPD-E and Pink
  # Sheet files. The legacy derived CSVs are comparison references only.
  tar_target(brazil_sdid_pink_sheet_file_candidate,
             file.path(
               "data", "raw", "commodity_prices",
               "world_bank_pink_sheet",
               "CMO-Historical-Data-Annual_2026-07-11.xlsx"
             ),
             format = "file"),
  tar_target(brazil_sdid_commodity_exposure_bundle_candidate,
             build_sdid_commodity_exposure_from_itpde(trade_file)),
  tar_target(brazil_sdid_commodity_exposure_candidate,
             brazil_sdid_commodity_exposure_bundle_candidate$exposure),
  tar_target(brazil_sdid_commodity_exposure_yearly_candidate,
             brazil_sdid_commodity_exposure_bundle_candidate$yearly),
  tar_target(brazil_sdid_commodity_exposure_audit_candidate,
             brazil_sdid_commodity_exposure_bundle_candidate$audit),
  tar_target(brazil_sdid_pink_sheet_indices_candidate,
             read_sdid_pink_sheet_indices(
               brazil_sdid_pink_sheet_file_candidate
             )),
  tar_target(brazil_sdid_commodity_reference_exposure_file,
             file.path(
               "data", "processed", "diagnostics",
               "brazil_sdid_predetermined_commodity_controls",
               "table_2_pre2009_commodity_exposure_by_country.csv"
             ),
             format = "file"),
  tar_target(brazil_sdid_commodity_reference_price_file,
             file.path(
               "data", "processed", "diagnostics",
               "brazil_sdid_predetermined_commodity_controls",
               "table_3_world_bank_commodity_price_indices.csv"
             ),
             format = "file"),
  tar_target(brazil_sdid_commodity_derivation_validation_candidate,
             validate_sdid_commodity_derivations(
               brazil_sdid_commodity_exposure_candidate,
               brazil_sdid_pink_sheet_indices_candidate,
               brazil_sdid_commodity_reference_exposure_file,
               brazil_sdid_commodity_reference_price_file,
               analytic_iso3c = sort(unique(synth_data$iso3c))
             )),
  tar_target(brazil_sdid_commodity_derivation_gate_candidate,
             assert_sdid_migration_validation(
               brazil_sdid_commodity_derivation_validation_candidate,
               sdid_commodity_derivation_validation_names()
             )),
  tar_target(brazil_sdid_commodity_exposure_file_candidate,
             {
               brazil_sdid_commodity_derivation_gate_candidate
               write_sdid_table_candidate(
                 brazil_sdid_commodity_exposure_candidate,
                 file.path(
                   "data", "processed", "targets_migration",
                   "brazil_sdid_predetermined_commodity_controls",
                   "table_2_pre2009_commodity_exposure_by_country.csv"
                 )
               )
             },
             format = "file"),
  tar_target(brazil_sdid_pink_sheet_indices_file_candidate,
             {
               brazil_sdid_commodity_derivation_gate_candidate
               write_sdid_table_candidate(
                 brazil_sdid_pink_sheet_indices_candidate,
                 file.path(
                   "data", "processed", "targets_migration",
                   "brazil_sdid_predetermined_commodity_controls",
                   "table_3_world_bank_commodity_price_indices.csv"
                 )
               )
             },
             format = "file"),
  tar_target(brazil_sdid_commodity_panel_candidate,
             {
               brazil_sdid_commodity_derivation_gate_candidate
               brazil_sdid_commodity_exposure_file_candidate
               brazil_sdid_pink_sheet_indices_file_candidate
               build_sdid_commodity_panel_candidate(
                 synth_data,
                 brazil_sdid_commodity_exposure_candidate,
                 brazil_sdid_pink_sheet_indices_candidate
               )
             }),
  tar_target(brazil_sdid_commodity_fit_current_baseline_candidate,
             fit_sdid_commodity_specification_candidate(
               brazil_sdid_commodity_panel_candidate,
               "current_baseline"
             )),
  tar_target(brazil_sdid_commodity_fit_no_covariates_candidate,
             fit_sdid_commodity_specification_candidate(
               brazil_sdid_commodity_panel_candidate,
               "no_covariates"
             )),
  tar_target(brazil_sdid_commodity_fit_primary_gfc_candidate,
             fit_sdid_commodity_specification_candidate(
               brazil_sdid_commodity_panel_candidate,
               "primary_gfc_2008_2009"
             )),
  tar_target(brazil_sdid_commodity_fit_agriculture_mining_candidate,
             fit_sdid_commodity_specification_candidate(
               brazil_sdid_commodity_panel_candidate,
               "agriculture_mining_gfc"
             )),
  tar_target(brazil_sdid_commodity_fit_weighted_price_candidate,
             fit_sdid_commodity_specification_candidate(
               brazil_sdid_commodity_panel_candidate,
               "weighted_price_gfc"
             )),
  tar_target(brazil_sdid_commodity_fit_pre_china_candidate,
             fit_sdid_commodity_specification_candidate(
               brazil_sdid_commodity_panel_candidate,
               "pre_china_gfc"
             )),
  tar_target(brazil_sdid_commodity_se_current_baseline_candidate,
             compute_sdid_comparison_se_candidate(
               brazil_sdid_commodity_fit_current_baseline_candidate,
               "current_baseline",
               replications = 5000L
             )),
  tar_target(brazil_sdid_commodity_se_no_covariates_candidate,
             reuse_sdid_preferred_se_candidate(
               brazil_sdid_commodity_fit_no_covariates_candidate,
               synth_fit_no_time_varying_covariates,
               se_synth_no_time_varying_covariates,
               replications = 20000L
             )),
  tar_target(brazil_sdid_commodity_se_primary_gfc_candidate,
             compute_sdid_comparison_se_candidate(
               brazil_sdid_commodity_fit_primary_gfc_candidate,
               "primary_gfc_2008_2009",
               replications = 5000L
             )),
  tar_target(brazil_sdid_commodity_se_agriculture_mining_candidate,
             compute_sdid_comparison_se_candidate(
               brazil_sdid_commodity_fit_agriculture_mining_candidate,
               "agriculture_mining_gfc",
               replications = 5000L
             )),
  tar_target(brazil_sdid_commodity_se_weighted_price_candidate,
             compute_sdid_comparison_se_candidate(
               brazil_sdid_commodity_fit_weighted_price_candidate,
               "weighted_price_gfc",
               replications = 5000L
             )),
  tar_target(brazil_sdid_commodity_se_pre_china_candidate,
             compute_sdid_comparison_se_candidate(
               brazil_sdid_commodity_fit_pre_china_candidate,
               "pre_china_gfc",
               replications = 5000L
             )),
  tar_target(brazil_sdid_commodity_primary_rank_distribution_candidate,
             run_sdid_rank_distribution_candidate(
               brazil_sdid_commodity_panel_candidate,
               covariate_cols = "primary_x_2008_2009_z",
               label = "primary_gfc_2008_2009",
               checkpoint_block = "commodity_table_5"
             )),
  tar_target(brazil_sdid_commodity_fits_candidate,
             list(
               current_baseline = brazil_sdid_commodity_fit_current_baseline_candidate,
               no_covariates = brazil_sdid_commodity_fit_no_covariates_candidate,
               primary_gfc_2008_2009 = brazil_sdid_commodity_fit_primary_gfc_candidate,
               agriculture_mining_gfc = brazil_sdid_commodity_fit_agriculture_mining_candidate,
               weighted_price_gfc = brazil_sdid_commodity_fit_weighted_price_candidate,
               pre_china_gfc = brazil_sdid_commodity_fit_pre_china_candidate
             )),
  tar_target(brazil_sdid_commodity_se_information_candidate,
             list(
               current_baseline = brazil_sdid_commodity_se_current_baseline_candidate,
               no_covariates = brazil_sdid_commodity_se_no_covariates_candidate,
               primary_gfc_2008_2009 = brazil_sdid_commodity_se_primary_gfc_candidate,
               agriculture_mining_gfc = brazil_sdid_commodity_se_agriculture_mining_candidate,
               weighted_price_gfc = brazil_sdid_commodity_se_weighted_price_candidate,
               pre_china_gfc = brazil_sdid_commodity_se_pre_china_candidate
             )),
  tar_target(brazil_sdid_commodity_table_candidate,
             build_sdid_commodity_table_candidate(
               brazil_sdid_commodity_fits_candidate,
               brazil_sdid_commodity_se_information_candidate,
               brazil_sdid_preferred_rank_distribution_candidate,
               brazil_sdid_commodity_primary_rank_distribution_candidate
             )),
  tar_target(brazil_sdid_commodity_table_reference_file,
             file.path(
               "data", "processed", "diagnostics",
               "brazil_sdid_commodity_no_covariates",
               "table_5_sdid_specification_results.csv"
             ),
             format = "file"),
  tar_target(brazil_sdid_commodity_table_validation_candidate,
             compare_sdid_candidate_frame(
               brazil_sdid_commodity_table_candidate,
               brazil_sdid_commodity_table_reference_file,
               "specification",
               "commodity_table_5"
             )),
  tar_target(brazil_sdid_commodity_table_validation_gate_candidate,
             assert_sdid_migration_validation(
               brazil_sdid_commodity_table_validation_candidate,
               sdid_frame_validation_names("commodity_table_5")
             )),
  tar_target(brazil_sdid_commodity_table_file_candidate,
             {
               brazil_sdid_commodity_table_validation_gate_candidate
               write_sdid_table_candidate(
                 brazil_sdid_commodity_table_candidate,
                 file.path(
                   "data", "processed", "targets_migration",
                   "brazil_sdid_commodity_no_covariates",
                   "table_5_sdid_specification_results.csv"
                 )
               )
             },
             format = "file"),
  # UNGA-DM measurement robustness. HTTP acquisition remains outside targets;
  # frozen source files, harmonization, deterministic diagnostics, models and
  # every paper-facing derivative are represented in the candidate graph.
  tar_target(ungadm_ideal_points_file_candidate,
             file.path(
               "raw data", "unga_dm",
               "unga_dm_ideal_points_all_resolution_votes_s75.csv"
             ),
             format = "file"),
  tar_target(ungadm_codebook_file_candidate,
             file.path("raw data", "unga_dm", "unga_dm_codebook.pdf"),
             format = "file"),
  tar_target(ungadm_sources_file_candidate,
             file.path("raw data", "unga_dm", "SOURCES.md"),
             format = "file"),
  tar_target(ungadm_input_validation_candidate,
             validate_ungadm_input_files(
               unga_file,
               ungadm_ideal_points_file_candidate,
               ungadm_codebook_file_candidate,
               ungadm_sources_file_candidate
             )),
  tar_target(ungadm_harmonized_bundle_candidate,
             {
               stopifnot(all(ungadm_input_validation_candidate$passed))
               build_ungadm_harmonized_bundle(
                 unga_file,
                 ungadm_ideal_points_file_candidate,
                 min_year = 1990L
               )
             }),
  tar_target(ungadm_outcome_candidate,
             ungadm_harmonized_bundle_candidate$outcome),
  tar_target(ungadm_unmapped_rows_candidate,
             ungadm_harmonized_bundle_candidate$unmatched),
  tar_target(ungadm_validation_outputs_candidate,
             build_ungadm_validation_outputs(
               ungadm_harmonized_bundle_candidate
             )),
  tar_target(ungadm_validation_gate_candidate,
             assert_ungadm_validation(
               ungadm_validation_outputs_candidate$validation,
               ungadm_validation_names()
             )),
  tar_target(ungadm_validation_files_candidate,
             {
               ungadm_validation_gate_candidate
               write_ungadm_tables_candidate(
                 list(
                   input_provenance = ungadm_input_validation_candidate,
                   correlations = ungadm_validation_outputs_candidate$correlations,
                   coverage_summary = ungadm_validation_outputs_candidate$coverage_summary,
                   within_range_gaps = ungadm_validation_outputs_candidate$within_range_gaps,
                   brazil_series_overlay = ungadm_validation_outputs_candidate$brazil_series,
                   brazil_gap_summary = ungadm_validation_outputs_candidate$brazil_gap_summary,
                   gates = ungadm_validation_outputs_candidate$validation
                 ),
                 file.path(
                   "data", "processed", "targets_migration", "ungadm",
                   "validation"
                 )
               )
             },
             format = "file"),
  tar_target(ungadm_validation_overlay_figure_candidate,
             {
               ungadm_validation_gate_candidate
               write_ungadm_validation_overlay_candidate(
                 ungadm_validation_outputs_candidate$brazil_series,
                 file.path(
                   "images", "targets_migration", "ungadm",
                   "brazil_series_overlay.png"
                 )
               )
             },
             format = "file"),
  tar_target(china_top_m2_goods_full_union_master_ungadm_candidate,
             {
               ungadm_validation_gate_candidate
               join_ungadm_to_full_union_master(
                 china_top_m2_goods_full_union_master_panel,
                 ungadm_outcome_candidate
               )
             }),
  tar_target(ungadm_master_join_validation_candidate,
             validate_ungadm_master_join(
               china_top_m2_goods_full_union_master_panel,
               china_top_m2_goods_full_union_master_ungadm_candidate
             )),
  tar_target(ungadm_master_join_gate_candidate,
             assert_ungadm_validation(
               ungadm_master_join_validation_candidate,
               ungadm_master_join_validation_names()
             )),
  tar_target(ungadm_sdid_panel_bundle_candidate,
             {
               stopifnot(
                 all(ungadm_sdid_reference_validation_candidate$passed)
               )
               ungadm_master_join_gate_candidate
               build_ungadm_sdid_panel_bundle(
                 synth_data,
                 ungadm_outcome_candidate
               )
             }),
  tar_target(ungadm_sdid_panel_validation_candidate,
             validate_ungadm_sdid_panel(
               synth_data,
               ungadm_sdid_panel_bundle_candidate
             )),
  tar_target(ungadm_sdid_panel_gate_candidate,
             assert_ungadm_validation(
               ungadm_sdid_panel_validation_candidate,
               ungadm_sdid_panel_validation_names()
             )),
  tar_target(ungadm_sdid_fit_candidate,
             {
               ungadm_sdid_panel_gate_candidate
               sdid_fit_spec(ungadm_sdid_panel_bundle_candidate$panel)
             }),
  tar_target(ungadm_sdid_se_candidate,
             run_sdid_placebo_se_candidate(
               ungadm_sdid_fit_candidate,
               replications = 20000L,
               label = "ungadm_no_covariates",
               checkpoint_block = "ungadm_sdid",
               seed = SDID_PLACEBO_SEED,
               core_cap = 12L
             )),
  tar_target(ungadm_sdid_se_info_candidate,
             list(
               se = as.numeric(ungadm_sdid_se_candidate),
               replications = 20000L,
               seed = SDID_PLACEBO_SEED,
               source = paste0(
                 "Locally computed placebo SE using the canonical ",
                 "resumable implementation."
               )
             )),
  tar_target(ungadm_sdid_rank_distribution_candidate,
             {
               ungadm_sdid_panel_gate_candidate
               run_sdid_rank_distribution_candidate(
                 ungadm_sdid_panel_bundle_candidate$panel,
                 covariate_cols = character(0),
                 label = "ungadm_no_covariates",
                 checkpoint_block = "ungadm_sdid"
               )
             }),
  tar_target(ungadm_sdid_outputs_candidate,
             build_ungadm_sdid_outputs_candidate(
               ungadm_sdid_panel_bundle_candidate$panel,
               ungadm_sdid_fit_candidate,
               ungadm_sdid_se_info_candidate,
               ungadm_sdid_rank_distribution_candidate,
               synth_fit_no_time_varying_covariates,
               brazil_sdid_paper_outputs_candidate,
               china_top_m2_goods_full_union_trade_rank,
               china_top_m2_goods_full_union_treatment_unit_summary
             )),
  tar_target(ungadm_sdid_reference_files,
             c(
               file.path(
                 "data", "processed", "diagnostics",
                 "ungadm_outcome_robustness", "estimation",
                 c(
                   "sdid_comparison_table.csv",
                   "sdid_dm_placebo_distribution.csv"
                 )
               ),
               file.path(
                 "data", "processed", "diagnostics",
                 "ungadm_outcome_robustness", "postreview",
                 "sdid_dm_rank_inference_harmonized.csv"
               ),
               file.path(
                 "data", "processed", "diagnostics",
                 "ungadm_outcome_robustness", "estimation",
                 "sdid_unit_weights_bsv_vs_dm.csv"
               )
             ),
             format = "file"),
  tar_target(ungadm_sdid_reference_validation_candidate,
             {
               ungadm_sdid_reference_files
               validate_ungadm_sdid_reference_files(
                 file.path(
                   "data", "processed", "diagnostics",
                   "ungadm_outcome_robustness"
                 )
               )
             }),
  tar_target(ungadm_sdid_baseline_validation_candidate,
             {
               stopifnot(
                 all(ungadm_sdid_reference_validation_candidate$passed)
               )
               validate_ungadm_sdid_against_baseline(
                 ungadm_sdid_outputs_candidate,
                 file.path(
                   "data", "processed", "diagnostics",
                   "ungadm_outcome_robustness"
                 )
               )
             }),
  tar_target(ungadm_sdid_baseline_gate_candidate,
             assert_sdid_migration_validation(
               ungadm_sdid_baseline_validation_candidate,
               ungadm_sdid_baseline_validation_names()
             )),
  tar_target(ungadm_sdid_output_files_candidate,
             {
               ungadm_sdid_baseline_gate_candidate
               write_ungadm_tables_candidate(
                 list(
                   sdid_comparison_table = ungadm_sdid_outputs_candidate$comparison,
                   sdid_dm_main_summary = ungadm_sdid_outputs_candidate$main_summary,
                   sdid_dm_missing_outcome_rows = ungadm_sdid_panel_bundle_candidate$missing,
                   sdid_dm_placebo_distribution = ungadm_sdid_outputs_candidate$placebo_distribution,
                   sdid_dm_rank_inference = ungadm_sdid_outputs_candidate$rank_inference,
                   sdid_dm_rank_inference_harmonized = ungadm_sdid_outputs_candidate$rank_inference_harmonized,
                   sdid_dm_unit_weights = ungadm_sdid_outputs_candidate$unit_weights,
                   sdid_unit_weights_bsv_vs_dm = ungadm_sdid_outputs_candidate$unit_weights_bsv_vs_dm,
                   sdid_dm_time_weights = ungadm_sdid_outputs_candidate$time_weights,
                   sdid_dm_balance = ungadm_sdid_outputs_candidate$balance,
                   sdid_inference_notes = ungadm_sdid_outputs_candidate$inference_notes,
                   dm_rows_without_iso3c_mapping = ungadm_unmapped_rows_candidate,
                   validation = ungadm_sdid_baseline_validation_candidate
                 ),
                 file.path(
                   "data", "processed", "targets_migration", "ungadm",
                   "sdid"
                 )
               )
             },
             format = "file"),
  tar_target(ungadm_sdid_placebo_figure_candidate,
             {
               ungadm_sdid_baseline_gate_candidate
               write_ungadm_placebo_figure_candidate(
                 ungadm_sdid_outputs_candidate$placebo_distribution,
                 file.path(
                   "images", "targets_migration", "ungadm",
                   "sdid_dm_placebo_distribution.png"
                 )
               )
             },
             format = "file"),
  tar_target(ungadm_common_window_bundle_candidate,
             {
               ungadm_master_join_gate_candidate
               build_ungadm_common_window_bundle(
                 china_top_m2_goods_full_union_status_row_audit,
                 china_top_m2_goods_full_union_master_ungadm_candidate,
                 common_max_year = 2020L
               )
             }),
  tar_target(ungadm_common_window_validation_candidate,
             validate_ungadm_common_window_bundle(
               ungadm_common_window_bundle_candidate
             )),
  tar_target(ungadm_common_window_gate_candidate,
             assert_ungadm_validation(
               ungadm_common_window_validation_candidate,
               ungadm_common_window_validation_names()
             )),
  tar_target(ungadm_ife_bsv_common_fit_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_fect_cv_candidate(
                 ungadm_common_window_bundle_candidate$panel_bsv,
                 nboots = 10000L
               )
             }),
  tar_target(ungadm_ife_dm_common_fit_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_fect_cv_candidate(
                 ungadm_common_window_bundle_candidate$panel_dm,
                 nboots = 10000L
               )
             }),
  tar_target(ungadm_ife_comparison_candidate,
             build_ungadm_ife_comparison_candidate(
               china_top_m2_goods_full_union_status_model_results,
               ungadm_ife_bsv_common_fit_candidate,
               ungadm_ife_dm_common_fit_candidate,
               ungadm_common_window_bundle_candidate,
               nboots = 10000L
             )),
  tar_target(ungadm_ife_dynamic_candidate,
             build_ungadm_ife_dynamic_candidate(
               ungadm_ife_bsv_common_fit_candidate,
               ungadm_ife_dm_common_fit_candidate
             )),
  tar_target(ungadm_ife_bsv_r1_fit_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_fect_fixed_r_candidate(
                 ungadm_common_window_bundle_candidate$panel_bsv,
                 r_fixed = 1L,
                 nboots = 10000L
               )
             }),
  tar_target(ungadm_ife_bsv_r2_fit_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_fect_fixed_r_candidate(
                 ungadm_common_window_bundle_candidate$panel_bsv,
                 r_fixed = 2L,
                 nboots = 10000L
               )
             }),
  tar_target(ungadm_ife_dm_r1_fit_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_fect_fixed_r_candidate(
                 ungadm_common_window_bundle_candidate$panel_dm,
                 r_fixed = 1L,
                 nboots = 10000L
               )
             }),
  tar_target(ungadm_ife_dm_r2_fit_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_fect_fixed_r_candidate(
                 ungadm_common_window_bundle_candidate$panel_dm,
                 r_fixed = 2L,
                 nboots = 10000L
               )
             }),
  tar_target(ungadm_ife_fixed_fits_candidate,
             list(
               bsv_r1 = ungadm_ife_bsv_r1_fit_candidate,
               bsv_r2 = ungadm_ife_bsv_r2_fit_candidate,
               dm_r1 = ungadm_ife_dm_r1_fit_candidate,
               dm_r2 = ungadm_ife_dm_r2_fit_candidate
             )),
  tar_target(ungadm_ife_fixed_grid_candidate,
             build_ungadm_ife_fixed_grid_candidate(
               ungadm_ife_fixed_fits_candidate,
               ungadm_common_window_bundle_candidate,
               ungadm_ife_bsv_common_fit_candidate,
               ungadm_ife_dm_common_fit_candidate,
               nboots = 10000L
             )),
  tar_target(ungadm_ife_paired_bootstrap_draws_candidate,
             {
               ungadm_common_window_gate_candidate
               run_ungadm_paired_bootstrap_candidate(
                 ungadm_common_window_bundle_candidate$common_rows,
                 bsv_selected_r = as.integer(
                   ungadm_ife_bsv_common_fit_candidate$r.cv
                 ),
                 dm_selected_r = as.integer(
                   ungadm_ife_dm_common_fit_candidate$r.cv
                 ),
                 B = 1000L,
                 boot_seed = 20260823L,
                 checkpoint_block = "ungadm_ife_paired",
                 core_cap = 12L
               )
             }),
  tar_target(ungadm_ife_paired_bootstrap_summary_candidate,
             build_ungadm_paired_bootstrap_summary_candidate(
               ungadm_ife_paired_bootstrap_draws_candidate,
               ungadm_ife_comparison_candidate,
               ungadm_ife_fixed_grid_candidate,
               B = 1000L
             )),
  tar_target(ungadm_series_diagnostics_candidate,
             build_ungadm_series_diagnostics_candidate(
               ungadm_common_window_bundle_candidate$common_rows
             )),
  tar_target(ungadm_ife_validation_candidate,
             validate_ungadm_ife_outputs(
               ungadm_ife_comparison_candidate,
               ungadm_ife_dynamic_candidate,
               ungadm_ife_fixed_grid_candidate,
               ungadm_ife_paired_bootstrap_draws_candidate,
               ungadm_ife_paired_bootstrap_summary_candidate,
               ungadm_series_diagnostics_candidate,
               ungadm_common_window_bundle_candidate,
               B = 1000L
             )),
  tar_target(ungadm_ife_validation_gate_candidate,
             assert_ungadm_validation(
               ungadm_ife_validation_candidate,
               ungadm_ife_validation_names()
             )),
  tar_target(ungadm_ife_output_files_candidate,
             {
               ungadm_ife_validation_gate_candidate
               write_ungadm_tables_candidate(
                 list(
                   ife_common_window_dropped_rows = ungadm_common_window_bundle_candidate$dropped_rows,
                   ife_comparison_table = ungadm_ife_comparison_candidate,
                   ife_common_window_dynamic = ungadm_ife_dynamic_candidate,
                   ife_2x2_fixed_r = ungadm_ife_fixed_grid_candidate,
                   ife_paired_bootstrap_draws = ungadm_ife_paired_bootstrap_draws_candidate,
                   ife_paired_bootstrap_summary = ungadm_ife_paired_bootstrap_summary_candidate,
                   series_divergence_by_country = ungadm_series_diagnostics_candidate$divergence,
                   group_mean_series_bsv_vs_dm = ungadm_series_diagnostics_candidate$group_means,
                   m2_pretrend_f_test_summary = tibble::as_tibble(
                     china_top_m2_goods_full_union_min5_recent_pretrend_f_test$summary
                   ),
                   m2_pretrend_f_test_periods = tibble::as_tibble(
                     china_top_m2_goods_full_union_min5_recent_pretrend_f_test$selected_periods
                   ),
                   common_window_validation = ungadm_common_window_validation_candidate,
                   ife_validation = ungadm_ife_validation_candidate
                 ),
                 file.path(
                   "data", "processed", "targets_migration", "ungadm",
                   "ife"
                 )
               )
             },
             format = "file"),
  tar_target(ungadm_fect_equivalence_figure_candidate,
             {
               ungadm_ife_validation_gate_candidate
               write_ungadm_equivalence_plot_candidate(
                 fect_ife_china_top_m2_goods_full_union_min5_risk_set,
                 file.path(
                   "images", "targets_migration", "ungadm",
                   "m2_fect_equiv_plot.png"
                 )
               )
             },
             format = "file"),
  # Dose-response placebo diagnostic. Crosses each donor's pseudo-ATT with its
  # trade exposure to China to discriminate the continuous-dependence rival
  # (alignment tracks the DOSE of exposure) from the rank-threshold mechanism.
  # Consumes the stored no-covariate SDiD diagnostics as tracked file inputs;
  # nothing here re-estimates Brazil's ATT, and dose is never a control -- it
  # only stratifies the comparison set for the rank test.
  #
  # TWO MEASUREMENT ARMS. The PRIMARY dose is goods-only, computed here from
  # trade_data_goods -- the same object rank_trade() ranks to assign treatment,
  # so dose and treatment share one sector definition. The ROBUSTNESS dose is
  # the all-sector share read from donor_china_exposure.csv and is retained in
  # full as the measurement-robustness comparison.
  #
  # DEPENDING ON trade_data_goods (and on trade_data / the ranked tables for the
  # build-time gates) is deliberate. An upstream dependency does not invalidate
  # the upstream target: these four are already built and current, and
  # tar_make(shortcut = TRUE) reads them from the store. The alternative --
  # re-reading raw data/ITPDE_R03.csv inside this subgraph to keep it
  # disconnected -- was discarded because it would compute the dose from a
  # second, untracked copy of the trade data and lose the guarantee that dose
  # and treatment come from the very same object.
  tar_target(brazil_sdid_dose_placebo_distribution_file,
             here("data", "processed", "diagnostics",
                  "paper_v4_brazil_sdid_no_covariates",
                  "placebo_distribution.csv"),
             format = "file"),
  tar_target(brazil_sdid_dose_placebo_exposure_file,
             here("data", "processed", "diagnostics",
                  "paper_v4_brazil_sdid_no_covariates",
                  "donor_china_exposure.csv"),
             format = "file"),
  tar_target(brazil_sdid_dose_placebo_rank_reference_file,
             here("data", "processed", "diagnostics",
                  "paper_v4_brazil_sdid_no_covariates",
                  "rank_inference.csv"),
             format = "file"),
  # Primary (goods-only) dose, on the same sector basis that assigns treatment.
  tar_target(brazil_sdid_dose_placebo_goods_dose,
             brazil_sdid_dose_placebo_period_dose(
               trade_data_goods,
               basis_label = "goods-only"
             )),
  # Build-time proof that the goods dose replicates the all-sector definition:
  # the same function, run on the all-sector table, must reproduce
  # donor_china_exposure.csv to 1e-12 or the build stops. Turns the header's
  # "property for property" claim into something a referee can see fail.
  tar_target(brazil_sdid_dose_placebo_definition_check,
             brazil_sdid_dose_placebo_verify_dose_definition(
               trade_data,
               brazil_sdid_dose_placebo_exposure_file
             )),
  tar_target(brazil_sdid_dose_placebo_donor_iso3c,
             brazil_sdid_dose_placebo_screened_donors(
               brazil_sdid_dose_placebo_exposure_file
             )),
  # Aborts if any donor sits at goods rank 1 inside 1997-2015: that would mean a
  # treated unit survived the screen into the donor pool and the "dose without
  # the crown" premise no longer holds.
  tar_target(brazil_sdid_dose_placebo_goods_rank_one_check,
             brazil_sdid_dose_placebo_rank_one_check(
               trade_data_goods_ranked,
               brazil_sdid_dose_placebo_donor_iso3c,
               basis_label = "goods-only",
               abort_if_any_in_window = TRUE
             )),
  # Records rather than gates: Singapore at all-sector rank 1 in 2013-2014 is
  # the known, expected fact the truncation note exists to disclose.
  tar_target(brazil_sdid_dose_placebo_all_sector_rank_one_check,
             brazil_sdid_dose_placebo_rank_one_check(
               trade_data_ranked,
               brazil_sdid_dose_placebo_donor_iso3c,
               basis_label = "all-sector",
               abort_if_any_in_window = FALSE
             )),
  tar_target(brazil_sdid_dose_placebo_dataset,
             build_brazil_sdid_dose_placebo_dataset(
               brazil_sdid_dose_placebo_distribution_file,
               brazil_sdid_dose_placebo_exposure_file,
               brazil_sdid_dose_placebo_goods_dose,
               brazil_sdid_dose_placebo_definition_check,
               brazil_sdid_dose_placebo_goods_rank_one_check,
               brazil_sdid_dose_placebo_all_sector_rank_one_check
             )),
  tar_target(brazil_sdid_dose_placebo_results,
             compute_brazil_sdid_dose_placebo_results(
               brazil_sdid_dose_placebo_dataset
             )),
  tar_target(brazil_sdid_dose_placebo_summary_file,
             write_brazil_sdid_dose_placebo_summary(
               brazil_sdid_dose_placebo_results,
               here("data", "processed", "diagnostics",
                    "brazil_sdid_dose_response_placebo",
                    "dose_response_summary.csv")
             ),
             format = "file"),
  tar_target(brazil_sdid_dose_placebo_ranks_file,
             write_brazil_sdid_dose_placebo_ranks(
               brazil_sdid_dose_placebo_results,
               brazil_sdid_dose_placebo_rank_reference_file,
               here("data", "processed", "diagnostics",
                    "brazil_sdid_dose_response_placebo",
                    "dose_response_rank_inference.csv")
             ),
             format = "file"),
  # Per-donor doses on both bases. Without this file the summary's claims about
  # Singapore's position and about how closely the two bases order the donors
  # are unfalsifiable from the shipped outputs alone.
  tar_target(brazil_sdid_dose_placebo_donors_file,
             write_brazil_sdid_dose_placebo_donors(
               brazil_sdid_dose_placebo_results,
               here("data", "processed", "diagnostics",
                    "brazil_sdid_dose_response_placebo",
                    "dose_response_donor_doses.csv")
             ),
             format = "file"),
  # The ggplot is built inside these file targets instead of being stored as its
  # own target. A ggplot object captures plot_env, and serializing that
  # environment is session-dependent: bit-identical inputs produced two
  # different object hashes in two different sessions, so a stored-plot target
  # (and this figure downstream of it) would report outdated and rebuild on a
  # replication machine with nothing substantive having changed.
  # Alternative discarded: keep a plot-object target, which is the convention
  # elsewhere in this pipeline because the manuscript tar_read()s those objects
  # directly. That reason does not apply here -- this figure is consumed only as
  # a PNG file, so the object has no consumer worth the spurious invalidation.
  #
  # The PRIMARY (goods-only) figure keeps the unqualified filename and carries
  # its arm in the subtitle, axis label and caption; the robustness figure gets
  # an explicitly qualified name. Alternative discarded: renaming both files to
  # arm-qualified names, which would leave the phase-1
  # dose_response_placebo_scatter.png on disk as an orphan produced by no
  # target -- a stale all-sector figure sitting beside the new ones, which is
  # exactly the arm ambiguity this design exists to remove.
  tar_target(brazil_sdid_dose_placebo_figure_file,
             write_brazil_sdid_dose_placebo_figure(
               brazil_sdid_dose_placebo_results,
               here("data", "processed", "diagnostics",
                    "brazil_sdid_dose_response_placebo",
                    "dose_response_placebo_scatter.png"),
               arm_key = "primary_goods"
             ),
             format = "file"),
  tar_target(brazil_sdid_dose_placebo_robustness_figure_file,
             write_brazil_sdid_dose_placebo_figure(
               brazil_sdid_dose_placebo_results,
               here("data", "processed", "diagnostics",
                    "brazil_sdid_dose_response_placebo",
                    "dose_response_placebo_scatter_all_sector_robustness.png"),
               arm_key = "robustness_all_sector"
             ),
             format = "file"),
  # Phase 1.2: Sensitivity analysis
  tar_target(synth_data_extended, clean_synth_data(final_df, trade_data_goods_ranked, year_end = 2020,
                                                  dpi_data=dpi_data, trade_agreement_data=trade_agreement_data)),
  tar_target(sensitivity_results, sensitivity_analysis(synth_data, synth_data_extended)),
  # Phase 1.3: Extended sample (2009-2019)
  tar_target(synth_fit_extended, simple_fit(synth_data_extended, time_end = 2020)),
  tar_target(se_synth_extended, se_sdid(synth_fit_extended, replications = 5000L)),
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
                                                                B = 10000L)),
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
  tar_target(china_top_m2_goods_panel_countries,
             build_m2_goods_panel_countries(unga_data, min_year = 1990L)),
  tar_target(china_top_m2_goods_trade_aggregation,
             aggregate_itpde_goods_exports(
               trade_file,
               china_top_m2_goods_panel_countries,
               start_year = 1990L,
               end_year = 2023L,
               goods_sector_values = c("Agriculture", "Mining and Energy",
                                        "Manufacturing")
             )),
  tar_target(china_top_m2_goods_exports,
             china_top_m2_goods_trade_aggregation$goods_exports),
  tar_target(china_top_m2_goods_sector_audit,
             china_top_m2_goods_trade_aggregation$sector_audit),
  # Side-by-side corrected construction for the migration gate. Unlike the
  # legacy branch above, this branch ranks every raw-source exporter, forms the
  # union with UNGA, and defines treatment before filtering missing outcomes.
  tar_target(china_top_m2_goods_full_union_trade_aggregation,
             aggregate_itpde_goods_exports_all_exporters(
               trade_file,
               start_year = 1990L,
               end_year = 2023L,
               goods_sector_values = c("Agriculture", "Mining and Energy",
                                        "Manufacturing")
             )),
  tar_target(china_top_m2_goods_full_union_exports,
             china_top_m2_goods_full_union_trade_aggregation$goods_exports),
  tar_target(china_top_m2_goods_full_union_sector_audit,
             china_top_m2_goods_full_union_trade_aggregation$sector_audit),
  tar_target(china_top_m2_goods_full_union_trade_rank,
             rank_itpde_goods_export_destinations(
               china_top_m2_goods_full_union_exports
             )),
  tar_target(china_top_m2_goods_full_union_master_panel,
             build_country_year_full_union_master(
               china_top_m2_goods_full_union_trade_rank,
               unga_data,
               min_year = 1990L,
               max_year = 2023L
             )),
  tar_target(china_top_m2_goods_full_union_status_panel_bundle,
             make_full_union_status_panel_bundle(
               china_top_m2_goods_full_union_master_panel,
               duration_thresholds = c(3L, 5L, 7L),
               min_entry_year = 2000L,
               min_untreated_observations = 5L
             )),
  tar_target(china_top_m2_goods_full_union_status_sample_counts,
             china_top_m2_goods_full_union_status_panel_bundle$sample_counts),
  tar_target(china_top_m2_goods_full_union_status_unit_summary,
             china_top_m2_goods_full_union_status_panel_bundle$unit_summary),
  tar_target(china_top_m2_goods_full_union_treatment_unit_summary,
             china_top_m2_goods_full_union_status_panel_bundle$treatment_unit_summary),
  tar_target(china_top_m2_goods_full_union_status_period_summary,
             china_top_m2_goods_full_union_status_panel_bundle$period_summary),
  tar_target(china_top_m2_goods_full_union_status_row_audit,
             china_top_m2_goods_full_union_status_panel_bundle$row_audit),
  tar_target(china_top_m2_goods_full_union_status_validation,
             validate_full_union_status_bundle(
               china_top_m2_goods_full_union_master_panel,
               china_top_m2_goods_full_union_status_panel_bundle
             )),
  tar_target(china_top_m2_goods_full_union_status_validation_gate,
             assert_full_union_status_validation(
               china_top_m2_goods_full_union_status_validation
             )),
  # Candidate estimations stay side-by-side until old/new outputs have been
  # compared and adjudicated. Promotion later replaces the legacy production
  # dependencies atomically; it does not happen merely because these run.
  tar_target(china_top_m2_goods_full_union_status_model_bundle,
             {
               stopifnot(all(
                 china_top_m2_goods_full_union_status_validation_gate$passed
               ))
               fit_status_current_fect_models(
                 china_top_m2_goods_full_union_status_panel_bundle,
                 nboots = 10000L
               )
             }),
  tar_target(china_top_m2_goods_full_union_status_model_results,
             china_top_m2_goods_full_union_status_model_bundle$model_results),
  tar_target(china_top_m2_goods_full_union_status_dynamic_results,
             china_top_m2_goods_full_union_status_model_bundle$dynamic_results),
  tar_target(fect_ife_china_top_m2_goods_full_union_min5_risk_set,
             china_top_m2_goods_full_union_status_model_bundle$main_fit),
  tar_target(china_top_m2_goods_full_union_min5_recent_pretrend_f_test,
             reconstruct_fect_recent_pretrend_f_test(
               fect_ife_china_top_m2_goods_full_union_min5_risk_set,
               model = "M2 goods-only full-union risk set: fect IFE",
               max_recent_periods = 12L,
               max_event_time = -1L
             )),
  tar_target(plot_china_top_m2_goods_full_union_dynamic,
             plot_status_current_dynamic(
               china_top_m2_goods_full_union_status_dynamic_results,
               min_duration_years = 5L,
               specification = "risk_set_restricted"
             )),
  tar_target(china_top_m2_goods_panel,
             build_china_top_partner_panel(
               china_top_m2_goods_exports,
               unga_data,
               min_year = 1990L,
               min_entry_year = 2000L
             )),
  tar_target(china_top_m2_goods_status_current_panel_bundle,
             make_status_current_panel_bundle(
               china_top_m2_goods_panel,
               duration_thresholds = c(3L, 5L, 7L),
               min_entry_year = 2000L
             )),
  tar_target(china_top_m2_goods_status_current_sample_counts,
             china_top_m2_goods_status_current_panel_bundle$sample_counts),
  tar_target(china_top_m2_goods_status_current_unit_summary,
             china_top_m2_goods_status_current_panel_bundle$unit_summary),
  tar_target(china_top_m2_goods_status_current_period_summary,
             china_top_m2_goods_status_current_panel_bundle$period_summary),
  tar_target(china_top_m2_goods_status_current_country_audit,
             make_country_exclusion_audit(
               china_top_m2_goods_panel,
               duration_thresholds = c(3L, 5L, 7L),
               min_entry_year = 2000L
             ) |>
               dplyr::left_join(
                 china_top_m2_goods_status_current_unit_summary |>
                   dplyr::select(
                     min_duration_years, sample, iso3c, ever_treated,
                     treated_years, untreated_years, first_treat
                   ),
                 by = c("min_duration_years", "iso3c")
               ) |>
               dplyr::arrange(min_duration_years, audit_role, sample, iso3c)),
  tar_target(china_top_m2_goods_status_current_model_bundle,
             fit_status_current_fect_models(
               china_top_m2_goods_status_current_panel_bundle,
               nboots = 10000L
             )),
  tar_target(china_top_m2_goods_status_current_model_results,
             china_top_m2_goods_status_current_model_bundle$model_results),
  tar_target(china_top_m2_goods_status_current_dynamic_results,
             china_top_m2_goods_status_current_model_bundle$dynamic_results),
  tar_target(fect_ife_china_top_m2_goods_status_current_min5_risk_set,
             china_top_m2_goods_status_current_model_bundle$main_fit),
  tar_target(fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test,
             reconstruct_fect_recent_pretrend_f_test(
               fect_ife_china_top_m2_goods_status_current_min5_risk_set,
               model = "M2 goods-only status-current risk set: fect IFE",
               max_recent_periods = 12L,
               max_event_time = -1L
             )),
  tar_target(china_top_m2_goods_status_current_pretrend_summary,
             fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test$summary),
  tar_target(china_top_m2_goods_status_current_pretrend_periods,
             fect_ife_china_top_m2_goods_status_current_min5_recent_pretrend_f_test$selected_periods),
  tar_target(plot_china_top_m2_goods_status_current_dynamic,
             plot_status_current_dynamic(
               china_top_m2_goods_status_current_dynamic_results,
               min_duration_years = 5L,
               specification = "risk_set_restricted"
             )),
  tar_target(plot_china_top_m2_goods_status_current_entry_years,
             plot_treated_entry_year_distribution(
               china_top_m2_goods_status_current_unit_summary,
               min_duration_years = 5L,
               sample_name = "risk_set_restricted",
               reference_year = 2009L,
               highlight_iso3c = "BRA"
             )),
  tar_target(china_top_m2_goods_status_current_runtime_report,
             write_status_current_runtime_report(
               china_top_m2_goods_status_current_model_results,
               china_top_m2_goods_status_current_sample_counts
             ),
             format = "file"),
  # Status-evidence acquisition remains outside targets. The graph starts from
  # frozen raw checksum manifests and author-owned source-coding ledgers.
  tar_target(status_cue_raw_checksums_file,
             here("data", "raw", "status_cue_salience", "checksums.sha256"),
             format = "file"),
  tar_target(status_cue_raw_paths_candidate,
             status_evidence_raw_paths(
               status_cue_raw_checksums_file,
               here("data", "raw", "status_cue_salience"),
               89L
             )),
  tar_target(status_cue_raw_files_candidate,
             status_cue_raw_paths_candidate,
             format = "file"),
  tar_target(status_cue_raw_validation_candidate,
             validate_status_evidence_raw_archive(
               status_cue_raw_checksums_file,
               status_cue_raw_files_candidate,
               here("data", "raw", "status_cue_salience"),
               89L,
               "9be41ee4805289fb6b32bf21cea39146363053d2a2970d26e20e9bc1aaaa0675"
             )),
  tar_target(ex_top1_raw_checksums_file,
             here("data", "raw", "ex_top1_salience", "checksums.sha256"),
             format = "file"),
  tar_target(ex_top1_raw_paths_candidate,
             status_evidence_raw_paths(
               ex_top1_raw_checksums_file,
               here("data", "raw", "ex_top1_salience"),
               48L
             )),
  tar_target(ex_top1_raw_files_candidate,
             ex_top1_raw_paths_candidate,
             format = "file"),
  tar_target(ex_top1_raw_validation_candidate,
             validate_status_evidence_raw_archive(
               ex_top1_raw_checksums_file,
               ex_top1_raw_files_candidate,
               here("data", "raw", "ex_top1_salience"),
               48L,
               "7f92a5822b396ee204e9e8eb4ea5682d791abdddecf5758134b97447ee69d8c3"
             )),
  tar_target(ex_top1_source_evidence_file,
             here("data", "processed", "ex_top1_salience",
                  "ex_top1_source_evidence.csv"),
             format = "file"),
  tar_target(status_cue_source_evidence_file,
             here("data", "processed", "status_cue_salience",
                  "status_cue_source_evidence.csv"),
             format = "file"),
  tar_target(status_cue_source_evidence_candidate,
             read_status_evidence_source_ledger(
               status_cue_source_evidence_file,
               "status"
             )),
  tar_target(ex_top1_source_evidence_candidate,
             read_status_evidence_source_ledger(
               ex_top1_source_evidence_file,
               "ex_top1"
             )),
  tar_target(status_cue_source_validation_candidate,
             validate_status_evidence_source_ledger(
               status_cue_source_evidence_candidate,
               status_cue_source_evidence_file,
               "status",
               status_cue_raw_files_candidate,
               here("data", "raw", "status_cue_salience"),
               21L
             )),
  tar_target(ex_top1_source_validation_candidate,
             validate_status_evidence_source_ledger(
               ex_top1_source_evidence_candidate,
               ex_top1_source_evidence_file,
               "ex_top1",
               ex_top1_raw_files_candidate,
               here("data", "raw", "ex_top1_salience"),
               22L
             )),
  tar_target(status_cue_archive_gate_candidate,
             assert_status_evidence_validation(
               dplyr::bind_rows(
                 status_cue_raw_validation_candidate,
                 status_cue_source_validation_candidate
               )
             )),
  tar_target(ex_top1_archive_gate_candidate,
             assert_status_evidence_validation(
               dplyr::bind_rows(
                 ex_top1_raw_validation_candidate,
                 ex_top1_source_validation_candidate
               )
             )),
  tar_target(status_evidence_audit_universe_file,
             here("data", "manual", "status_evidence", "audit_universe.csv"),
             format = "file"),
  tar_target(status_country_overrides_file,
             here("data", "manual", "status_evidence",
                  "status_country_overrides.csv"),
             format = "file"),
  tar_target(ex_top1_country_annotations_file,
             here("data", "manual", "status_evidence",
                  "ex_top1_country_annotations.csv"),
             format = "file"),
  tar_target(status_evidence_audit_universe_candidate,
             read_status_evidence_audit_universe(
               status_evidence_audit_universe_file
             )),
  tar_target(status_country_overrides_candidate,
             read_status_country_overrides(status_country_overrides_file)),
  tar_target(ex_top1_country_annotations_candidate,
             read_ex_top1_country_annotations(
               ex_top1_country_annotations_file
             )),
  tar_target(status_evidence_manual_validation_candidate,
             validate_status_evidence_manual_inputs(
               status_evidence_audit_universe_candidate,
               status_country_overrides_candidate,
               ex_top1_country_annotations_candidate
             )),
  tar_target(status_evidence_manual_gate_candidate,
             assert_status_evidence_validation(
               status_evidence_manual_validation_candidate
             )),
  tar_target(status_evidence_incumbent_file,
             here("data", "processed", "diagnostics",
                  "incumbent_salience_moderators_2026-05-19.csv"),
             format = "file"),
  tar_target(status_evidence_incumbent_validation_candidate,
             validate_status_evidence_incumbent_file(
               status_evidence_incumbent_file
             )),
  tar_target(status_evidence_incumbent_gate_candidate,
             assert_status_evidence_validation(
               status_evidence_incumbent_validation_candidate
             )),
  tar_target(status_evidence_incumbent_data_candidate,
             {
               status_evidence_incumbent_gate_candidate
               readr::read_csv(
                 status_evidence_incumbent_file,
                 show_col_types = FALSE
               )
             }),
  tar_target(status_evidence_incumbent_base_candidate,
             build_ex_top1_incumbent_base_candidate(
               status_evidence_audit_universe_candidate,
               status_evidence_incumbent_data_candidate,
               file.path(
                 "data", "processed", "diagnostics",
                 "incumbent_salience_moderators_2026-05-19.csv"
               )
             )),
  tar_target(status_cue_country_codes_candidate,
             {
               status_cue_archive_gate_candidate
               status_evidence_manual_gate_candidate
               build_status_cue_country_codes_candidate(
                 status_evidence_audit_universe_candidate,
                 status_cue_source_evidence_candidate,
                 status_country_overrides_candidate
               )
             }),
  tar_target(ex_top1_country_codes_candidate,
             {
               ex_top1_archive_gate_candidate
               status_evidence_manual_gate_candidate
               status_evidence_incumbent_gate_candidate
               build_ex_top1_country_codes_candidate(
                 status_evidence_audit_universe_candidate,
                 ex_top1_source_evidence_candidate,
                 status_evidence_incumbent_base_candidate,
                 ex_top1_country_annotations_candidate
               )
             }),
  tar_target(ex_top1_status_comparison_candidate,
             build_status_ex_top1_comparison_candidate(
               ex_top1_country_codes_candidate,
               status_cue_country_codes_candidate
             )),
  tar_target(status_evidence_derivation_validation_candidate,
             validate_status_evidence_derivations(
               status_cue_country_codes_candidate,
               ex_top1_country_codes_candidate,
               ex_top1_status_comparison_candidate,
               status_evidence_audit_universe_candidate,
               status_evidence_incumbent_base_candidate,
               ex_top1_source_evidence_candidate
             )),
  tar_target(status_evidence_derivation_gate_candidate,
             assert_status_evidence_validation(
               dplyr::bind_rows(
                 status_evidence_manual_validation_candidate,
                 status_evidence_derivation_validation_candidate
               ),
               status_evidence_validation_names()
             )),
  tar_target(status_cue_country_codes_file,
             {
               status_evidence_derivation_gate_candidate
               write_status_evidence_csv_candidate(
                 status_cue_country_codes_candidate,
                 here("data", "processed", "status_cue_salience",
                      "status_cue_country_codes.csv"),
                 lowercase_logical = TRUE
               )
             },
             format = "file"),
  tar_target(ex_top1_country_codes_file,
             {
               status_evidence_derivation_gate_candidate
               write_status_evidence_csv_candidate(
                 ex_top1_country_codes_candidate,
                 here("data", "processed", "ex_top1_salience",
                      "ex_top1_country_codes.csv")
               )
             },
             format = "file"),
  tar_target(ex_top1_status_comparison_file,
             {
               status_evidence_derivation_gate_candidate
               write_status_evidence_csv_candidate(
                 ex_top1_status_comparison_candidate,
                 here("data", "processed", "ex_top1_salience",
                      "status_cue_vs_ex_top1_coverage.csv")
               )
             },
             format = "file"),
  tar_target(ex_top1_salience_input_validation,
             validate_ex_top1_salience_inputs(
               ex_top1_status_comparison_file,
               ex_top1_country_codes_file,
               ex_top1_source_evidence_file,
               status_cue_country_codes_file,
               status_cue_source_evidence_file
             )),
  tar_target(ex_top1_salience_appendix_tables,
             {
               stopifnot(all(ex_top1_salience_input_validation$passed))
               build_ex_top1_salience_appendix_tables(
                 ex_top1_status_comparison_file,
                 ex_top1_country_codes_file,
                 ex_top1_source_evidence_file,
                 status_cue_country_codes_file,
                 status_cue_source_evidence_file
               )
             }),
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
