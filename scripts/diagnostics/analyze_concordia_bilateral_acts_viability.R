#!/usr/bin/env Rscript

# Análise preliminar de viabilidade dos atos bilaterais do Concórdia.

options(scipen = 999)
set.seed(20260828)

locale_result <- Sys.setlocale("LC_ALL", "pt_BR.UTF-8")
if (is.na(locale_result)) {
  stop("Não foi possível ativar o locale pt_BR.UTF-8 exigido pela análise.")
}

required_packages <- c(
  "dplyr", "tidyr", "readr", "ggplot2", "stringr", "tibble", "scales",
  "here", "jsonlite"
)
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Pacotes R ausentes: ", paste(missing_packages, collapse = ", "))
}

project_root <- here::here()
processed_base <- file.path(
  project_root,
  "data", "processed", "diagnostics", "concordia_bilateral_acts"
)

args <- commandArgs(trailingOnly = TRUE)
run_arg <- args[stringr::str_detect(args, "^--processed-run=")]
if (length(run_arg) > 0) {
  processed_dir <- sub("^--processed-run=", "", run_arg[[1]])
  if (!grepl("^/", processed_dir)) {
    processed_dir <- file.path(project_root, processed_dir)
  }
} else {
  processed_runs <- list.dirs(processed_base, recursive = FALSE, full.names = TRUE)
  if (length(processed_runs) == 0) {
    stop("Nenhuma execução processada encontrada em ", processed_base)
  }
  processed_dir <- sort(processed_runs)[[length(processed_runs)]]
}

run_id <- basename(processed_dir)
output_dir <- file.path(project_root, "quality_reports", "concordia_bilateral_acts", run_id)
table_dir <- file.path(output_dir, "tables")
figure_dir <- file.path(output_dir, "figures")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

hits <- readr::read_csv(
  file.path(processed_dir, "concordia_search_hits_2000_2014.csv"),
  locale = readr::locale(encoding = "UTF-8"),
  show_col_types = FALSE
)
acts <- readr::read_csv(
  file.path(processed_dir, "concordia_bilateral_acts_2000_2014.csv"),
  locale = readr::locale(encoding = "UTF-8"),
  show_col_types = FALSE
)
subjects <- readr::read_csv(
  file.path(processed_dir, "concordia_bilateral_act_subjects_2000_2014.csv"),
  locale = readr::locale(encoding = "UTF-8"),
  show_col_types = FALSE
)

partners <- c(
  "China", "Índia", "África do Sul", "México", "Indonésia", "Turquia",
  "Argentina", "Paraguai", "Uruguai"
)
main_donors <- c("Índia", "África do Sul", "México", "Indonésia", "Turquia")
secondary_donors <- c("Argentina", "Paraguai")
expanded_donors <- c(main_donors, secondary_donors)

partner_group <- tibble::tibble(
  partner = partners,
  group = c(
    "Tratada", rep("Doador prioritário", 5), rep("Regional secundário", 2),
    "Excluído: tratamento comercial posterior"
  )
)

date_counts <- acts |>
  dplyr::count(query_partner, date_celebration, name = "acts_on_date")

act_year <- acts |>
  dplyr::left_join(date_counts, by = c("query_partner", "date_celebration")) |>
  dplyr::group_by(query_partner, year) |>
  dplyr::summarise(
    raw_acts = dplyr::n_distinct(act_id),
    distinct_dates = dplyr::n_distinct(date_celebration),
    strategic_instrument = as.integer(any(strategic_instrument, na.rm = TRUE)),
    acts_in_packages = sum(acts_on_date >= 2, na.rm = TRUE),
    max_package_size = max(acts_on_date, na.rm = TRUE),
    package_share = acts_in_packages / raw_acts,
    top_date_share = max(acts_on_date, na.rm = TRUE) / raw_acts,
    revision_share = mean(
      has_explicit_revision_relation | amendment_or_revision_title,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

subject_year <- subjects |>
  dplyr::group_by(query_partner, year) |>
  dplyr::summarise(distinct_subjects = dplyr::n_distinct(subject), .groups = "drop")

panel <- tidyr::expand_grid(partner = partners, year = 2000:2014) |>
  dplyr::left_join(
    act_year |>
      dplyr::rename(partner = query_partner),
    by = c("partner", "year")
  ) |>
  dplyr::left_join(
    subject_year |>
      dplyr::rename(partner = query_partner),
    by = c("partner", "year")
  ) |>
  dplyr::mutate(
    dplyr::across(
      c(
        raw_acts, distinct_dates, distinct_subjects, strategic_instrument,
        acts_in_packages, max_package_size, package_share, top_date_share,
        revision_share
      ),
      ~ tidyr::replace_na(.x, 0)
    ),
    post_2009 = year >= 2009
  ) |>
  dplyr::left_join(partner_group, by = "partner")

panel_path <- file.path(processed_dir, "concordia_dyad_year_outcomes_2000_2014.csv")
readr::write_csv(panel, panel_path, na = "")

collection_by_partner <- hits |>
  dplyr::group_by(query_partner) |>
  dplyr::summarise(
    search_hits = dplyr::n(),
    unique_ids = dplyr::n_distinct(act_id),
    bilateral_hits = sum(agreement_type == "BL", na.rm = TRUE),
    plurilateral_hits = sum(agreement_type == "TL", na.rm = TRUE),
    multilateral_hits = sum(agreement_type == "ML", na.rm = TRUE),
    analytic_bilateral_hits = sum(analytic_bilateral, na.rm = TRUE),
    years_with_bilateral_acts = dplyr::n_distinct(year[analytic_bilateral]),
    earliest_bilateral_year = min(year[analytic_bilateral], na.rm = TRUE),
    latest_bilateral_year = max(year[analytic_bilateral], na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(
    panel |>
      dplyr::group_by(partner) |>
      dplyr::summarise(zero_years = sum(raw_acts == 0), .groups = "drop") |>
      dplyr::rename(query_partner = partner),
    by = "query_partner"
  ) |>
  dplyr::left_join(
    partner_group |>
      dplyr::rename(query_partner = partner),
    by = "query_partner"
  )

audit_issues <- tibble::tribble(
  ~issue, ~count, ~denominator, ~rule,
  "IDs repetidos dentro da mesma consulta", sum(hits$duplicate_id_within_query, na.rm = TRUE), nrow(hits), "Mesmo act_id repetido para a mesma contraparte consultada",
  "IDs presentes em consultas de múltiplos parceiros", sum(hits$duplicate_id_across_partner_queries, na.rm = TRUE), nrow(hits), "Mesmo act_id retornado por mais de uma consulta; esperado para atos plurilaterais/multilaterais",
  "Atos não bilaterais retornados", sum(hits$agreement_type != "BL", na.rm = TRUE), nrow(hits), "TipoAcordo diferente de BL; preservado no bruto e excluído do painel",
  "Parceiro consultado ausente de OutrasPartes", sum(!hits$partner_in_other_parties, na.rm = TRUE), nrow(hits), "Validação literal do vetor OutrasPartes",
  "Datas ausentes", sum(hits$missing_date, na.rm = TRUE), nrow(hits), "DataCelebracao vazia",
  "Datas inválidas", sum(hits$invalid_date, na.rm = TRUE), nrow(hits), "DataCelebracao não interpretável como DD/MM/AAAA",
  "Registros fora da janela", sum(hits$outside_requested_window, na.rm = TRUE), nrow(hits), "Ano fora de 2000-2014 apesar do filtro da API",
  "Contrapartes ausentes", sum(hits$missing_counterparty, na.rm = TRUE), nrow(hits), "Campo OutraParte vazio",
  "Relação explícita de revisão/emenda/substituição", sum(hits$has_explicit_revision_relation, na.rm = TRUE), nrow(hits), "Campos Emendas, Emendendados, AcordoSubstituido ou AcordoSubstituiu no detalhe",
  "Título indica emenda/revisão", sum(hits$amendment_or_revision_title, na.rm = TRUE), nrow(hits), "Regra textual pré-especificada",
  "Duplicata exata de título e data na díade", sum(hits$same_title_date_duplicate, na.rm = TRUE), nrow(hits), "Mesmo título normalizado e mesma data na consulta",
  "Atos bilaterais sem assunto", sum(acts$n_subjects == 0, na.rm = TRUE), nrow(acts), "Campo Assuntos vazio no registro analítico",
  "Atos bilaterais com múltiplos assuntos", sum(acts$n_subjects > 1, na.rm = TRUE), nrow(acts), "Mais de uma categoria no campo Assuntos",
  "Atos bilaterais sem documento integral", sum(is.na(acts$full_document_id)), nrow(acts), "DocumentoIntegra ausente",
  "Atos bilaterais sem situação de vigência", sum(is.na(acts$status) | acts$status == ""), nrow(acts), "Campo Vigencia ausente ou vazio"
)

pre_post_means <- panel |>
  dplyr::filter(partner != "Uruguai") |>
  tidyr::pivot_longer(
    cols = c(raw_acts, distinct_dates, distinct_subjects, strategic_instrument),
    names_to = "outcome",
    values_to = "value"
  ) |>
  dplyr::mutate(period = ifelse(year < 2009, "pre_2009", "post_2009")) |>
  dplyr::group_by(partner, group, outcome, period) |>
  dplyr::summarise(
    mean = mean(value),
    sd = stats::sd(value),
    zero_share = mean(value == 0),
    total = sum(value),
    n_years = dplyr::n(),
    .groups = "drop"
  ) |>
  dplyr::select(partner, group, outcome, period, mean, sd, zero_share, total, n_years) |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(mean, sd, zero_share, total, n_years),
    names_glue = "{.value}_{period}"
  ) |>
  dplyr::mutate(mean_change = mean_post_2009 - mean_pre_2009)

panel_2005_2012 <- panel |>
  dplyr::filter(year >= 2005, year <= 2012) |>
  dplyr::select(
    partner, group, year, raw_acts, distinct_dates, distinct_subjects,
    strategic_instrument, package_share, top_date_share
  )

safe_cor <- function(x, y) {
  if (stats::sd(x) == 0 || stats::sd(y) == 0) {
    return(NA_real_)
  }
  stats::cor(x, y)
}

outcome_diagnostics <- panel |>
  dplyr::filter(partner != "Uruguai") |>
  dplyr::group_by(partner) |>
  dplyr::summarise(
    corr_acts_dates = safe_cor(raw_acts, distinct_dates),
    corr_acts_subjects = safe_cor(raw_acts, distinct_subjects),
    corr_dates_subjects = safe_cor(distinct_dates, distinct_subjects),
    raw_acts_zero_share = mean(raw_acts == 0),
    distinct_dates_zero_share = mean(distinct_dates == 0),
    distinct_subjects_zero_share = mean(distinct_subjects == 0),
    package_share_all_years = sum(acts_in_packages) / sum(raw_acts),
    maximum_single_date_share = max(top_date_share),
    strategic_years = sum(strategic_instrument),
    .groups = "drop"
  )

softmax <- function(theta) {
  shifted <- theta - max(theta)
  exp(shifted) / sum(exp(shifted))
}

fit_prefit <- function(data, outcome, donors, pool_label) {
  wide <- data |>
    dplyr::filter(year < 2009, partner %in% c("China", donors)) |>
    dplyr::select(partner, year, value = dplyr::all_of(outcome)) |>
    tidyr::pivot_wider(names_from = partner, values_from = value) |>
    dplyr::arrange(year)
  treated <- wide$China
  donor_matrix <- as.matrix(wide[, donors, drop = FALSE])
  objective <- function(theta) {
    weights <- softmax(theta)
    mean((treated - as.vector(donor_matrix %*% weights))^2)
  }
  fit <- stats::optim(rep(0, length(donors)), objective, method = "BFGS")
  weights <- softmax(fit$par)
  synthetic <- as.vector(donor_matrix %*% weights)
  rmse <- sqrt(mean((treated - synthetic)^2))
  treated_sd <- stats::sd(treated)
  equal_rmse <- sqrt(mean((treated - rowMeans(donor_matrix))^2))
  median_rmse <- sqrt(mean((treated - apply(donor_matrix, 1, stats::median))^2))
  list(
    diagnostic = tibble::tibble(
      pool = pool_label,
      outcome = outcome,
      n_donors = length(donors),
      n_pre_periods = length(treated),
      synthetic_rmse = rmse,
      equal_mean_rmse = equal_rmse,
      donor_median_rmse = median_rmse,
      china_pre_sd = treated_sd,
      rmse_over_china_sd = ifelse(treated_sd > 0, rmse / treated_sd, NA_real_),
      effective_donors = 1 / sum(weights^2),
      optimizer_convergence = fit$convergence
    ),
    weights = tibble::tibble(
      pool = pool_label,
      outcome = outcome,
      donor = donors,
      weight = weights
    )
  )
}

outcomes <- c("raw_acts", "distinct_dates", "distinct_subjects")
prefit_results <- c(
  lapply(outcomes, function(outcome) fit_prefit(panel, outcome, main_donors, "Prioritário")),
  lapply(outcomes, function(outcome) fit_prefit(panel, outcome, expanded_donors, "Expandido com regionais"))
)
prefit_diagnostics <- dplyr::bind_rows(lapply(prefit_results, `[[`, "diagnostic"))
synthetic_weights <- dplyr::bind_rows(lapply(prefit_results, `[[`, "weights"))

design_viability <- tibble::tibble(
  pool = c("Prioritário", "Expandido com regionais"),
  treated_units = 1L,
  donor_units = c(length(main_donors), length(expanded_donors)),
  total_reassignment_units = c(length(main_donors) + 1L, length(expanded_donors) + 1L),
  pre_periods = 9L,
  post_periods = 6L,
  earliest_one_sided_exact_p = 1 / total_reassignment_units,
  excluded_units = "Uruguai (entrada posterior no tratamento comercial)",
  caution = c(
    "Inferência por reatribuição muito grosseira; cinco doadores prioritários",
    "Ganha duas unidades, mas Argentina e Paraguai são comparadores regionais secundários"
  )
)

top_subjects <- subjects |>
  dplyr::count(query_partner, subject, name = "acts") |>
  dplyr::group_by(query_partner) |>
  dplyr::slice_max(order_by = acts, n = 5, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::arrange(query_partner, dplyr::desc(acts), subject)

package_events <- acts |>
  dplyr::group_by(query_partner, date_celebration, year) |>
  dplyr::summarise(
    acts = dplyr::n_distinct(act_id),
    distinct_subjects = dplyr::n_distinct(subject_names),
    act_ids = paste(sort(unique(act_id)), collapse = " | "),
    titles = paste(title, collapse = " || "),
    .groups = "drop"
  ) |>
  dplyr::filter(acts >= 2) |>
  dplyr::arrange(dplyr::desc(acts), query_partner, date_celebration)

revision_records <- acts |>
  dplyr::filter(has_explicit_revision_relation | amendment_or_revision_title) |>
  dplyr::select(
    query_partner, act_id, date_celebration, title, amendment_ids,
    amended_instrument_ids, replaced_instrument_id, replaced_instrument_title,
    replacing_instrument_id, replacing_instrument_title,
    has_explicit_revision_relation, amendment_or_revision_title, record_url
  ) |>
  dplyr::arrange(query_partner, date_celebration, act_id)

strategic_records <- acts |>
  dplyr::filter(strategic_instrument) |>
  dplyr::select(
    query_partner, act_id, date_celebration, title, strategic_rule_match,
    record_url
  ) |>
  dplyr::arrange(query_partner, date_celebration, act_id)

aggregate_comparison <- panel |>
  dplyr::filter(partner == "China" | partner %in% main_donors) |>
  tidyr::pivot_longer(
    cols = c(raw_acts, distinct_dates, distinct_subjects, strategic_instrument),
    names_to = "outcome",
    values_to = "value"
  ) |>
  dplyr::group_by(year, outcome) |>
  dplyr::summarise(
    China = value[partner == "China"],
    `Média dos doadores prioritários` = mean(value[partner %in% main_donors]),
    `Mediana dos doadores prioritários` = stats::median(value[partner %in% main_donors]),
    .groups = "drop"
  ) |>
  tidyr::pivot_longer(
    cols = c(
      China, `Média dos doadores prioritários`,
      `Mediana dos doadores prioritários`
    ),
    names_to = "series",
    values_to = "value"
  ) |>
  dplyr::mutate(period = ifelse(year < 2009, "pre_2009", "post_2009")) |>
  dplyr::group_by(series, outcome, period) |>
  dplyr::summarise(mean = mean(value), total = sum(value), .groups = "drop") |>
  tidyr::pivot_wider(
    names_from = period,
    values_from = c(mean, total),
    names_glue = "{.value}_{period}"
  ) |>
  dplyr::mutate(mean_change = mean_post_2009 - mean_pre_2009)

write_table <- function(data, name) {
  readr::write_csv(data, file.path(table_dir, name), na = "")
}
write_table(collection_by_partner, "table_1_collection_by_partner.csv")
write_table(audit_issues, "table_2_audit_issues.csv")
write_table(pre_post_means, "table_3_pre_post_means.csv")
write_table(panel_2005_2012, "table_4_panel_2005_2012.csv")
write_table(outcome_diagnostics, "table_5_outcome_diagnostics.csv")
write_table(design_viability, "table_6_design_viability.csv")
write_table(prefit_diagnostics, "table_7_prefit_diagnostics.csv")
write_table(synthetic_weights, "table_8_synthetic_weights.csv")
write_table(top_subjects, "table_9_top_subjects_by_partner.csv")
write_table(package_events, "table_10_same_day_packages.csv")
write_table(revision_records, "table_11_revision_and_amendment_records.csv")
write_table(strategic_records, "table_12_strategic_instruments.csv")
write_table(aggregate_comparison, "table_13_china_vs_priority_donor_aggregates.csv")

palette <- c(
  "Tratada" = "#D55E00",
  "Doador prioritário" = "#0072B2",
  "Regional secundário" = "#009E73",
  "Excluído: tratamento comercial posterior" = "#777777"
)

figure_1 <- ggplot2::ggplot(
  panel,
  ggplot2::aes(x = year, y = raw_acts, color = group, group = partner)
) +
  ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", color = "grey45") +
  ggplot2::geom_line(linewidth = 0.65) +
  ggplot2::geom_point(size = 1.2) +
  ggplot2::facet_wrap(~partner, ncol = 3, scales = "free_y") +
  ggplot2::scale_color_manual(values = palette) +
  ggplot2::scale_x_continuous(breaks = c(2000, 2005, 2009, 2014)) +
  ggplot2::scale_y_continuous(breaks = scales::breaks_pretty(n = 4), expand = ggplot2::expansion(mult = c(0, 0.08))) +
  ggplot2::labs(
    title = "Atos bilaterais por parceiro e ano",
    x = NULL,
    y = "Número de atos bilaterais",
    color = NULL,
    caption = stringr::str_wrap(
      "Figura 1. A linha tracejada marca 2009. Fonte: Concórdia/MRE, acesso em 28 ago. 2026. Apenas registros TipoAcordo = BL.",
      width = 105
    )
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.caption.position = "plot",
    plot.caption = ggplot2::element_text(hjust = 0, size = 8)
  )

comparison_long <- panel |>
  dplyr::filter(partner == "China" | partner %in% main_donors) |>
  tidyr::pivot_longer(
    cols = c(raw_acts, distinct_dates, distinct_subjects),
    names_to = "outcome",
    values_to = "value"
  )
china_series <- comparison_long |>
  dplyr::filter(partner == "China") |>
  dplyr::transmute(year, outcome, series = "China", value)
donor_series <- comparison_long |>
  dplyr::filter(partner %in% main_donors) |>
  dplyr::group_by(year, outcome) |>
  dplyr::summarise(
    `Média dos doadores prioritários` = mean(value),
    `Mediana dos doadores prioritários` = stats::median(value),
    .groups = "drop"
  ) |>
  tidyr::pivot_longer(
    cols = c(`Média dos doadores prioritários`, `Mediana dos doadores prioritários`),
    names_to = "series",
    values_to = "value"
  )
comparison_plot <- dplyr::bind_rows(china_series, donor_series) |>
  dplyr::mutate(
    outcome = dplyr::recode(
      outcome,
      raw_acts = "Número de atos",
      distinct_dates = "Datas distintas de assinatura",
      distinct_subjects = "Áreas substantivas distintas"
    )
  )

figure_2 <- ggplot2::ggplot(
  comparison_plot,
  ggplot2::aes(x = year, y = value, color = series, linetype = series)
) +
  ggplot2::geom_vline(xintercept = 2009, linetype = "dashed", color = "grey45") +
  ggplot2::geom_line(linewidth = 0.85) +
  ggplot2::geom_point(data = dplyr::filter(comparison_plot, series == "China"), size = 1.5) +
  ggplot2::facet_wrap(~outcome, ncol = 1, scales = "free_y") +
  ggplot2::scale_color_manual(values = c(
    "China" = "#D55E00",
    "Média dos doadores prioritários" = "#0072B2",
    "Mediana dos doadores prioritários" = "#009E73"
  )) +
  ggplot2::scale_linetype_manual(values = c(
    "China" = "solid",
    "Média dos doadores prioritários" = "longdash",
    "Mediana dos doadores prioritários" = "dotted"
  )) +
  ggplot2::scale_x_continuous(breaks = c(2000, 2005, 2009, 2014)) +
  ggplot2::scale_y_continuous(breaks = scales::breaks_pretty(n = 5), expand = ggplot2::expansion(mult = c(0, 0.08))) +
  ggplot2::labs(
    title = "Trajetória chinesa e referências do pool prioritário",
    x = NULL,
    y = NULL,
    color = NULL,
    linetype = NULL,
    caption = stringr::str_wrap(
      "Figura 2. Doadores prioritários: Índia, África do Sul, México, Indonésia e Turquia. A linha tracejada vertical marca 2009. Fonte: Concórdia/MRE.",
      width = 100
    )
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank(),
    strip.text = ggplot2::element_text(face = "bold"),
    plot.caption.position = "plot",
    plot.caption = ggplot2::element_text(hjust = 0, size = 8)
  )

package_partner <- acts |>
  dplyr::group_by(query_partner) |>
  dplyr::summarise(
    total_acts = dplyr::n_distinct(act_id),
    acts_in_packages = sum(in_same_day_package, na.rm = TRUE),
    package_share = acts_in_packages / total_acts,
    maximum_package_size = max(same_day_package_size, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::left_join(
    partner_group |>
      dplyr::rename(query_partner = partner),
    by = "query_partner"
  ) |>
  dplyr::arrange(package_share) |>
  dplyr::mutate(query_partner = factor(query_partner, levels = query_partner))

figure_3 <- ggplot2::ggplot(
  package_partner,
  ggplot2::aes(x = package_share, y = query_partner, fill = group)
) +
  ggplot2::geom_col(width = 0.7) +
  ggplot2::geom_text(
    ggplot2::aes(label = scales::percent(package_share, accuracy = 1)),
    hjust = -0.1,
    size = 3
  ) +
  ggplot2::scale_fill_manual(values = palette) +
  ggplot2::scale_x_continuous(
    labels = scales::label_percent(),
    limits = c(0, min(1, max(package_partner$package_share) * 1.18)),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(
    title = "Concentração de atos em pacotes de assinatura",
    x = "Proporção de atos em datas com dois ou mais instrumentos",
    y = NULL,
    fill = NULL,
    caption = stringr::str_wrap(
      "Figura 3. Pacote é uma regra mecânica: pelo menos dois atos bilaterais da mesma díade na mesma data. A figura não identifica a visita ou cúpula que gerou o pacote.",
      width = 95
    )
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    plot.caption.position = "plot",
    plot.caption = ggplot2::element_text(hjust = 0, size = 8)
  )

top_subject_names <- subjects |>
  dplyr::count(subject, sort = TRUE) |>
  dplyr::slice_head(n = 10) |>
  dplyr::pull(subject)
subject_heatmap <- subjects |>
  dplyr::filter(subject %in% top_subject_names) |>
  dplyr::count(query_partner, subject, name = "acts") |>
  tidyr::complete(query_partner = partners, subject = top_subject_names, fill = list(acts = 0)) |>
  dplyr::mutate(
    query_partner = factor(query_partner, levels = partners),
    subject = factor(subject, levels = rev(top_subject_names))
  )

figure_4 <- ggplot2::ggplot(
  subject_heatmap,
  ggplot2::aes(x = query_partner, y = subject, fill = acts)
) +
  ggplot2::geom_tile(color = "white", linewidth = 0.35) +
  ggplot2::geom_text(ggplot2::aes(label = ifelse(acts > 0, acts, "")), size = 2.8) +
  ggplot2::scale_fill_viridis_c(option = "cividis", begin = 0.08, end = 0.92) +
  ggplot2::labs(
    title = "Distribuição dos atos pelas dez áreas mais frequentes",
    x = NULL,
    y = NULL,
    fill = "Atos",
    caption = stringr::str_wrap(
      "Figura 4. Contagem de atos bilaterais em 2000-2014. Nesta amostra, cada ato bilateral tem exatamente uma categoria no campo Assuntos da API Concórdia/MRE.",
      width = 105
    )
  ) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 30, hjust = 1),
    panel.grid = ggplot2::element_blank(),
    plot.caption.position = "plot",
    plot.caption = ggplot2::element_text(hjust = 0, size = 8)
  )

save_figure <- function(plot, stem, width, height) {
  ggplot2::ggsave(
    filename = file.path(figure_dir, paste0(stem, ".pdf")),
    plot = plot,
    width = width,
    height = height,
    units = "in",
    device = grDevices::pdf
  )
  ggplot2::ggsave(
    filename = file.path(figure_dir, paste0(stem, ".png")),
    plot = plot,
    width = width,
    height = height,
    units = "in",
    dpi = 300
  )
}

save_figure(figure_1, "figure_1_annual_bilateral_counts", 7, 7.4)
save_figure(figure_2, "figure_2_china_vs_priority_donors", 7, 7.2)
save_figure(figure_3, "figure_3_same_day_package_share", 7, 4.8)
save_figure(figure_4, "figure_4_subject_distribution", 8.2, 5.6)

analysis_manifest <- list(
  processed_run = normalizePath(processed_dir, winslash = "/", mustWork = TRUE),
  output_dir = normalizePath(output_dir, winslash = "/", mustWork = TRUE),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  row_counts = list(
    search_hits = nrow(hits),
    bilateral_acts = nrow(acts),
    subject_rows = nrow(subjects),
    dyad_year_rows = nrow(panel)
  ),
  donor_pools = list(
    priority = main_donors,
    secondary = secondary_donors,
    excluded = "Uruguai"
  ),
  treatment = list(partner = "China", start_year = 2009),
  outcomes = c(
    "Número bruto de atos",
    "Número de datas distintas de assinatura",
    "Número de áreas substantivas distintas",
    "Indicador textual de instrumento estratégico (adicional)"
  ),
  caveat = "Diagnóstico descritivo e de pré-ajuste; nenhum efeito causal foi estimado."
)
jsonlite::write_json(
  analysis_manifest,
  file.path(output_dir, "analysis_manifest.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)

writeLines(capture.output(sessionInfo()), file.path(output_dir, "session_info.txt"), useBytes = TRUE)
cat(output_dir, "\n")
