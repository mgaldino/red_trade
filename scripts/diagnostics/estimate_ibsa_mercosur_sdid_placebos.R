# Placebos SDiD com pontos ideais alternativos: IBAS e Mercosul.
#
# O script apenas le objetos ja construidos no armazenamento local de targets.
# Ele nao executa tar_make() nem modifica o pipeline. A comparacao usa a mesma
# janela (1997-2015), o mesmo inicio de tratamento (2009) e a mesma especificacao
# sem covariaveis do SDiD principal. Em cada exercicio, os paises que formam o
# ponto ideal de referencia sao retirados do pool de doadores para evitar
# sobreposicao mecanica entre o outcome alternativo e o contrafactual sintetico.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(tidyr)
})

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()

year_start <- 1997L
year_end <- 2015L
treat_year <- 2009L
target_store <- "_targets"
analysis_version <- "2026-08-28-v1"
parallel_cores <- sdid_available_cores(cap = 8L)

out_dir <- file.path(
  "data", "processed", "diagnostics", "ibsa_mercosur_sdid_placebos"
)
checkpoint_dir <- file.path(out_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

read_target <- function(name) {
  targets::tar_read_raw(name, store = target_store)
}

synth_data <- read_target("synth_data")
unga_path <- read_target("unga_file")
trade_rank <- read_target("trade_data_goods_ranked")

required_synth <- c("year", "iso3c", "abs_distance_china")
if (!all(required_synth %in% names(synth_data))) {
  stop("O target `synth_data` nao tem as colunas esperadas.", call. = FALSE)
}
if (!is.character(unga_path) || length(unga_path) != 1L || !file.exists(unga_path)) {
  stop("O arquivo de pontos ideais referenciado por `unga_file` nao existe.",
       call. = FALSE)
}

ideal_points <- data.table::fread(unga_path) |>
  mutate(
    year = as.integer(session) + 1945L,
    iso3c = as.character(iso3c),
    ideal_point_q50 = as.numeric(`Q50%All`)
  ) |>
  dplyr::select(year, iso3c, ideal_point_q50) |>
  filter(
    year >= year_start,
    year <= year_end,
    !is.na(iso3c),
    !is.na(ideal_point_q50)
  )

duplicate_ideal <- ideal_points |>
  count(iso3c, year, name = "n") |>
  filter(n != 1L)
if (nrow(duplicate_ideal) > 0L) {
  stop("Ha pais-ano duplicado nos pontos ideais.", call. = FALSE)
}

base_panel <- synth_data |>
  filter(year >= year_start, year <= year_end) |>
  dplyr::select(year, iso3c, abs_distance_china)

base_counts <- base_panel |>
  count(iso3c, name = "n_years")
expected_years <- year_end - year_start + 1L
if (any(base_counts$n_years != expected_years)) {
  stop("O painel-base nao e balanceado em 1997-2015.", call. = FALSE)
}

base_units <- sort(unique(base_panel$iso3c))

anchor_specs <- tibble::tribble(
  ~comparison_id, ~comparison_label, ~anchor_members,
  "ibsa", "IBAS: India e Africa do Sul", list(c("IND", "ZAF")),
  "mercosur", "Mercosul: Argentina e Paraguai", list(c("ARG", "PRY"))
)

rank_summary <- function(distribution, estimate_col, treated_iso3c = "BRA") {
  valid <- distribution |>
    filter(status == "estimated", !is.na(.data[[estimate_col]]))
  treated <- valid |>
    filter(iso3c == treated_iso3c)
  if (nrow(treated) != 1L) {
    stop("Brasil ausente da distribuicao placebo.", call. = FALSE)
  }
  treated_estimate <- treated[[estimate_col]][[1L]]
  tibble::tibble(
    rank_one_sided_negative = sum(valid[[estimate_col]] <= treated_estimate),
    rank_two_sided_absolute = sum(
      abs(valid[[estimate_col]]) >= abs(treated_estimate)
    ),
    denominator = nrow(valid),
    p_rank_one_sided_negative = mean(
      valid[[estimate_col]] <= treated_estimate
    ),
    p_rank_two_sided_absolute = mean(
      abs(valid[[estimate_col]]) >= abs(treated_estimate)
    )
  )
}

estimate_comparison <- function(comparison_id, comparison_label,
                                anchor_members) {
  anchor_members <- unlist(anchor_members, use.names = FALSE)
  message("Estimando ", comparison_label, ".")

  anchor_by_year <- ideal_points |>
    filter(iso3c %in% anchor_members) |>
    group_by(year) |>
    summarise(
      n_anchor_members = n_distinct(iso3c),
      anchor_ideal = stats::median(ideal_point_q50),
      .groups = "drop"
    )

  if (nrow(anchor_by_year) != expected_years ||
      any(anchor_by_year$n_anchor_members != length(anchor_members))) {
    stop(
      "O ponto de referencia ", comparison_id,
      " nao tem todos os membros em todos os anos.",
      call. = FALSE
    )
  }

  removed_from_pool <- intersect(anchor_members, base_units)
  analysis_units <- setdiff(base_units, anchor_members)

  china_panel <- base_panel |>
    filter(iso3c %in% analysis_units) |>
    arrange(iso3c, year)

  anchor_panel <- ideal_points |>
    filter(iso3c %in% analysis_units) |>
    inner_join(
      anchor_by_year |>
        dplyr::select(year, anchor_ideal),
      by = "year"
    ) |>
    mutate(abs_distance_china = abs(ideal_point_q50 - anchor_ideal)) |>
    dplyr::select(year, iso3c, abs_distance_china) |>
    arrange(iso3c, year)

  china_keys <- china_panel |>
    dplyr::select(iso3c, year)
  anchor_keys <- anchor_panel |>
    dplyr::select(iso3c, year)
  support_mismatch <- nrow(anti_join(china_keys, anchor_keys,
                                     by = c("iso3c", "year"))) +
    nrow(anti_join(anchor_keys, china_keys, by = c("iso3c", "year")))
  if (support_mismatch > 0L) {
    stop(
      "Os outcomes China e ", comparison_id,
      " nao tem o mesmo suporte pais-ano.",
      call. = FALSE
    )
  }
  if (anyNA(anchor_panel$abs_distance_china)) {
    stop("O outcome alternativo contem valores ausentes.", call. = FALSE)
  }

  fit_china <- sdid_fit_spec(
    china_panel,
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year
  )
  fit_anchor <- sdid_fit_spec(
    anchor_panel,
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year
  )

  china_distribution <- sdid_rank_distribution(
    china_panel,
    label = paste0(comparison_id, "_china"),
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year,
    cores = parallel_cores,
    checkpoint_dir = checkpoint_dir
  ) |>
    dplyr::select(
      iso3c,
      estimate_china = estimate,
      rmspe_pre_china = rmspe_pre,
      status_china = status,
      error_china = error
    )

  anchor_distribution <- sdid_rank_distribution(
    anchor_panel,
    label = paste0(comparison_id, "_anchor"),
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year,
    cores = parallel_cores,
    checkpoint_dir = checkpoint_dir
  ) |>
    dplyr::select(
      iso3c,
      estimate_anchor = estimate,
      rmspe_pre_anchor = rmspe_pre,
      status_anchor = status,
      error_anchor = error
    )

  paired_distribution <- china_distribution |>
    inner_join(anchor_distribution, by = "iso3c") |>
    mutate(
      estimate_difference = estimate_china - estimate_anchor,
      status = if_else(
        status_china == "estimated" & status_anchor == "estimated",
        "estimated",
        "error"
      )
    )

  if (nrow(paired_distribution) != length(analysis_units)) {
    stop("A distribuicao placebo pareada ficou incompleta.", call. = FALSE)
  }

  anchor_rank <- rank_summary(paired_distribution, "estimate_anchor")
  difference_rank <- rank_summary(
    paired_distribution,
    "estimate_difference"
  )
  china_rank <- rank_summary(paired_distribution, "estimate_china")

  readr::write_csv(
    paired_distribution,
    file.path(out_dir, paste0(comparison_id, "_paired_placebo_distribution.csv"))
  )

  fit_china_summary <- sdid_fit_summary_row(
    fit_china,
    paste0(comparison_id, "_china")
  )
  fit_anchor_summary <- sdid_fit_summary_row(
    fit_anchor,
    paste0(comparison_id, "_anchor")
  )

  tibble::tibble(
    comparison_id = comparison_id,
    comparison_label = comparison_label,
    anchor_members = paste(anchor_members, collapse = ";"),
    anchor_members_removed_from_donor_pool = paste(
      removed_from_pool,
      collapse = ";"
    ),
    anchor_statistic = "Mediana anual; com dois membros, igual ao ponto medio",
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year,
    n_units = fit_china_summary$n_units,
    n_donors = fit_china_summary$n_donors,
    att_distance_china = as.numeric(fit_china),
    att_distance_anchor = as.numeric(fit_anchor),
    att_china_minus_anchor = as.numeric(fit_china) - as.numeric(fit_anchor),
    rmspe_pre_china = fit_china_summary$rmspe_pre,
    rmspe_pre_anchor = fit_anchor_summary$rmspe_pre,
    china_rank_one_sided_negative = china_rank$rank_one_sided_negative,
    china_rank_two_sided_absolute = china_rank$rank_two_sided_absolute,
    china_rank_denominator = china_rank$denominator,
    china_p_rank_one_sided_negative = china_rank$p_rank_one_sided_negative,
    china_p_rank_two_sided_absolute = china_rank$p_rank_two_sided_absolute,
    anchor_rank_one_sided_negative = anchor_rank$rank_one_sided_negative,
    anchor_rank_two_sided_absolute = anchor_rank$rank_two_sided_absolute,
    anchor_rank_denominator = anchor_rank$denominator,
    anchor_p_rank_one_sided_negative = anchor_rank$p_rank_one_sided_negative,
    anchor_p_rank_two_sided_absolute = anchor_rank$p_rank_two_sided_absolute,
    difference_rank_one_sided_negative =
      difference_rank$rank_one_sided_negative,
    difference_rank_two_sided_absolute =
      difference_rank$rank_two_sided_absolute,
    difference_rank_denominator = difference_rank$denominator,
    difference_p_rank_one_sided_negative =
      difference_rank$p_rank_one_sided_negative,
    difference_p_rank_two_sided_absolute =
      difference_rank$p_rank_two_sided_absolute
  )
}

results <- purrr::pmap_dfr(anchor_specs, estimate_comparison)
readr::write_csv(
  results,
  file.path(out_dir, "ibsa_mercosur_sdid_placebo_results.csv")
)

mercosur_trade_audit <- trade_rank |>
  filter(
    iso3c %in% c("ARG", "PRY", "URY"),
    year >= year_start,
    year <= year_end
  ) |>
  transmute(
    year = as.integer(year),
    iso3c,
    country = countrycode::countrycode(iso3c, "iso3c", "country.name"),
    china_export_rank = as.integer(rank_from_i),
    china_rank_1 = treatment_first == 1,
    china_rank_2 = treatment_second == 1,
    retained_in_brazil_sdid_panel = iso3c %in% base_units
  ) |>
  arrange(iso3c, year)

mercosur_trade_summary <- mercosur_trade_audit |>
  group_by(iso3c, country) |>
  summarise(
    first_china_rank_1_year = {
      if (any(china_rank_1)) min(year[china_rank_1]) else NA_integer_
    },
    china_rank_1_years = paste(year[china_rank_1], collapse = ";"),
    china_rank_2_years = paste(year[china_rank_2], collapse = ";"),
    retained_in_brazil_sdid_panel = first(retained_in_brazil_sdid_panel),
    .groups = "drop"
  )

readr::write_csv(
  mercosur_trade_audit,
  file.path(out_dir, "mercosur_china_export_rank_by_year.csv")
)
readr::write_csv(
  mercosur_trade_summary,
  file.path(out_dir, "mercosur_treatment_eligibility_summary.csv")
)

manifest <- tibble::tibble(
  analysis_version = analysis_version,
  run_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  target_store = target_store,
  unga_file = normalizePath(unga_path),
  unga_file_sha256 = digest::digest(file = unga_path, algo = "sha256"),
  synth_data_sha256 = digest::digest(synth_data, algo = "sha256"),
  trade_data_goods_ranked_sha256 = digest::digest(trade_rank, algo = "sha256"),
  helper_sha256 = digest::digest(
    file = file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"),
    algo = "sha256"
  ),
  script_sha256 = digest::digest(
    file = file.path(
      "scripts", "diagnostics", "estimate_ibsa_mercosur_sdid_placebos.R"
    ),
    algo = "sha256"
  ),
  parallel_cores = parallel_cores,
  note = paste(
    "Leitura somente de targets existentes; tar_make() nao foi executado;",
    "a inferencia reportada usa ranks placebo-in-space exatos."
  )
)
readr::write_csv(manifest, file.path(out_dir, "run_manifest.csv"))

session_text <- capture.output(utils::sessionInfo())
writeLines(enc2utf8(session_text), file.path(out_dir, "session_info.txt"))

message("Resultados salvos em: ", out_dir)
print(results, width = Inf)
