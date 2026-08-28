#!/usr/bin/env Rscript

# Análise descritiva do piloto de coautoria/coapresentação na OMC.
# Entrada produzida por code_wto_coauthorship_pilot.py; nenhuma rede ou targets.

invisible(Sys.setlocale("LC_CTYPE", "pt_BR.UTF-8"))

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(tidyr)
})

options(scipen = 999)
set.seed(20260828)

repo_root <- normalizePath(".", mustWork = TRUE)
processed_dir <- file.path(repo_root, "data", "processed", "wto_coauthorship")
report_dir <- file.path(repo_root, "quality_reports", "wto_coauthorship")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

event_path <- file.path(processed_dir, "wto_strict_dyad_family_events_2000_2014.csv")
events <- readr::read_csv(event_path, show_col_types = FALSE) |>
  dplyr::mutate(year = as.integer(year))

partners <- c("CHN", "IND", "ZAF", "MEX", "IDN", "TUR", "ARG")
partner_labels <- c(
  CHN = "China", IND = "Índia", ZAF = "África do Sul", MEX = "México",
  IDN = "Indonésia", TUR = "Turquia", ARG = "Argentina"
)

dyad_year <- tidyr::expand_grid(
  partner = partners,
  year = 2000:2014
) |>
  dplyr::left_join(
    events |>
      dplyr::count(partner, year, name = "n_new_coauthored_families"),
    by = c("partner", "year")
  ) |>
  dplyr::mutate(
    n_new_coauthored_families = tidyr::replace_na(n_new_coauthored_families, 0L),
    post_2009 = as.integer(year >= 2009),
    window_2005_2012 = as.integer(year >= 2005 & year <= 2012),
    share_all_brazilian_submissions_with_partner = NA_real_,
    denominator_status = "indisponível: o piloto não coletou todas as submissões brasileiras"
  ) |>
  dplyr::arrange(partner, year)

readr::write_csv(
  dyad_year,
  file.path(processed_dir, "wto_dyad_year_outcomes.csv"),
  na = ""
)

summarize_window <- function(data, first_year, last_year, window_label) {
  data |>
    dplyr::filter(year >= first_year, year <= last_year) |>
    dplyr::mutate(period = if_else(year >= 2009, "post", "pre")) |>
    dplyr::group_by(partner, period) |>
    dplyr::summarise(
      total_new_families = sum(n_new_coauthored_families),
      annual_mean = mean(n_new_coauthored_families),
      n_years = dplyr::n(),
      share_zero_years = mean(n_new_coauthored_families == 0),
      .groups = "drop"
    ) |>
    dplyr::mutate(window = window_label, .before = 1)
}

pre_post_long <- dplyr::bind_rows(
  summarize_window(dyad_year, 2000, 2014, "2000-2014"),
  summarize_window(dyad_year, 2005, 2012, "2005-2012")
)

pre_post <- pre_post_long |>
  dplyr::select(window, partner, period, total_new_families, annual_mean, n_years, share_zero_years) |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(total_new_families, annual_mean, n_years, share_zero_years)
  ) |>
  dplyr::mutate(
    change_in_annual_mean = annual_mean_post - annual_mean_pre,
    rate_ratio_post_pre = if_else(annual_mean_pre > 0, annual_mean_post / annual_mean_pre, NA_real_)
  ) |>
  dplyr::arrange(window, partner)

readr::write_csv(pre_post, file.path(processed_dir, "wto_pre_post_summary.csv"), na = "")

compute_did <- function(summary_data, window_label, pool_label, pool_partners) {
  changes <- summary_data |>
    dplyr::filter(window == window_label, partner %in% pool_partners) |>
    dplyr::select(partner, change_in_annual_mean)
  china_change <- changes |>
    dplyr::filter(partner == "CHN") |>
    dplyr::pull(change_in_annual_mean)
  control_change <- changes |>
    dplyr::filter(partner != "CHN") |>
    dplyr::summarise(value = mean(change_in_annual_mean)) |>
    dplyr::pull(value)
  tibble::tibble(
    window = window_label,
    donor_pool = pool_label,
    china_pre_post_change = china_change,
    donors_mean_pre_post_change = control_change,
    descriptive_did = china_change - control_change,
    inference_status = "ponto descritivo; sem erro-padrão causal válido com uma única díade tratada"
  )
}

did_points <- dplyr::bind_rows(
  compute_did(pre_post, "2000-2014", "primário: IND+ZAF", c("CHN", "IND", "ZAF")),
  compute_did(pre_post, "2000-2014", "ampliado: seis parceiros", partners),
  compute_did(pre_post, "2005-2012", "primário: IND+ZAF", c("CHN", "IND", "ZAF")),
  compute_did(pre_post, "2005-2012", "ampliado: seis parceiros", partners)
)
readr::write_csv(did_points, file.path(processed_dir, "wto_descriptive_did_points.csv"))

compute_placebos <- function(summary_data, window_label, pool_label, pool_partners) {
  changes <- summary_data |>
    dplyr::filter(window == window_label, partner %in% pool_partners) |>
    dplyr::select(partner, change_in_annual_mean)
  estimates <- lapply(pool_partners, function(pseudo_treated) {
    treated_change <- changes |>
      dplyr::filter(partner == pseudo_treated) |>
      dplyr::pull(change_in_annual_mean)
    donor_change <- changes |>
      dplyr::filter(partner != pseudo_treated) |>
      dplyr::summarise(value = mean(change_in_annual_mean)) |>
      dplyr::pull(value)
    tibble::tibble(
      window = window_label,
      donor_pool = pool_label,
      pseudo_treated = pseudo_treated,
      reassignment_estimate = treated_change - donor_change
    )
  }) |>
    dplyr::bind_rows()
  china_abs <- estimates |>
    dplyr::filter(pseudo_treated == "CHN") |>
    dplyr::pull(reassignment_estimate) |>
    abs()
  estimates |>
    dplyr::mutate(
      china_two_sided_randomization_p = mean(abs(reassignment_estimate) >= china_abs),
      number_of_possible_assignments = dplyr::n(),
      minimum_attainable_p = 1 / dplyr::n()
    )
}

placebos <- dplyr::bind_rows(
  compute_placebos(pre_post, "2000-2014", "primário: CHN+IND+ZAF", c("CHN", "IND", "ZAF")),
  compute_placebos(pre_post, "2000-2014", "ampliado: sete parceiros", partners),
  compute_placebos(pre_post, "2005-2012", "primário: CHN+IND+ZAF", c("CHN", "IND", "ZAF")),
  compute_placebos(pre_post, "2005-2012", "ampliado: sete parceiros", partners)
)
readr::write_csv(placebos, file.path(processed_dir, "wto_placebo_reattribution.csv"))

topic_composition <- events |>
  dplyr::count(partner, period_2009, topic, name = "n_new_families") |>
  dplyr::group_by(partner, period_2009) |>
  dplyr::mutate(share_within_partner_period = n_new_families / sum(n_new_families)) |>
  dplyr::ungroup() |>
  dplyr::arrange(partner, period_2009, dplyr::desc(n_new_families), topic)
readr::write_csv(topic_composition, file.path(processed_dir, "wto_topic_composition.csv"))

discriminating_subsets <- dplyr::bind_rows(
  events |>
    dplyr::filter(partner == "CHN", china_without_india_or_south_africa == 1) |>
    dplyr::count(period_2009, name = "n_family_events") |>
    dplyr::mutate(subset = "Brasil-China sem Índia nem África do Sul"),
  events |>
    dplyr::filter(partner == "IND", india_or_south_africa_without_china == 1) |>
    dplyr::count(period_2009, name = "n_family_events") |>
    dplyr::mutate(subset = "Brasil-Índia sem China"),
  events |>
    dplyr::filter(partner == "ZAF", india_or_south_africa_without_china == 1) |>
    dplyr::count(period_2009, name = "n_family_events") |>
    dplyr::mutate(subset = "Brasil-África do Sul sem China")
) |>
  dplyr::select(subset, period_2009, n_family_events) |>
  tidyr::complete(
    subset,
    period_2009 = c("pre", "post"),
    fill = list(n_family_events = 0L)
  ) |>
  dplyr::arrange(subset, period_2009)
readr::write_csv(discriminating_subsets, file.path(processed_dir, "wto_discriminating_subsets.csv"))

feasibility <- did_points |>
  dplyr::mutate(
    treated_dyads = 1L,
    donor_dyads = if_else(grepl("primário", donor_pool), 2L, 6L),
    pre_years = if_else(window == "2000-2014", 9L, 4L),
    post_years = if_else(window == "2000-2014", 6L, 4L),
    possible_treatment_reassignments = donor_dyads + 1L,
    minimum_two_sided_randomization_p = 1 / possible_treatment_reassignments,
    design_assessment = paste(
      "SDiD/efeitos fixos são calculáveis apenas como diagnóstico;",
      "uma díade tratada, poucos doadores, desfecho de contagem esparso e composição temática mutável",
      "não sustentam inferência causal definitiva."
    )
  ) |>
  dplyr::select(
    window, donor_pool, treated_dyads, donor_dyads, pre_years, post_years,
    possible_treatment_reassignments, minimum_two_sided_randomization_p,
    descriptive_did, design_assessment
  )
readr::write_csv(feasibility, file.path(processed_dir, "wto_design_feasibility_diagnostics.csv"))

plot_data <- dyad_year |>
  dplyr::filter(partner %in% c("CHN", "IND", "ZAF")) |>
  dplyr::mutate(partner_label = factor(partner_labels[partner], levels = c("China", "Índia", "África do Sul")))

figure_1 <- ggplot(plot_data, aes(x = year, y = n_new_coauthored_families, color = partner_label)) +
  geom_vline(xintercept = 2009, linetype = "dashed", linewidth = 0.45, color = "grey35") +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.8) +
  scale_x_continuous(breaks = seq(2000, 2014, by = 2)) +
  scale_y_continuous(breaks = scales::pretty_breaks()) +
  scale_color_manual(values = c("China" = "#B22222", "Índia" = "#D18F00", "África do Sul" = "#2B6F8A")) +
  labs(
    title = "Figura 1. Novas famílias documentais coapresentadas com o Brasil",
    subtitle = "Piloto de busca por título; a linha tracejada marca 2009",
    x = "Ano",
    y = "Número de novas famílias documentais",
    color = "Parceiro",
    caption = paste0(
      "Fonte: WTO Documents Online, acesso em 28 ago. 2026.\n",
      "Série provisória, deduplicada por família; não é um censo das submissões brasileiras."
    )
  ) +
  theme_minimal(base_size = 10) +
  theme(
    legend.position = "top",
    panel.grid.minor = element_blank(),
    plot.title.position = "plot",
    plot.caption.position = "plot",
    plot.caption = element_text(hjust = 0, size = 8),
    plot.margin = margin(10, 15, 15, 15)
  )

ggsave(
  filename = file.path(report_dir, "figure_1_wto_primary_dyad_year.pdf"),
  plot = figure_1,
  width = 7.2,
  height = 4.6,
  units = "in",
  device = "pdf"
)
ggsave(
  filename = file.path(report_dir, "figure_1_wto_primary_dyad_year.png"),
  plot = figure_1,
  width = 7.2,
  height = 4.6,
  units = "in",
  dpi = 180
)

message("Análise concluída. Outputs em ", processed_dir, " e ", report_dir)
