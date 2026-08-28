# India como unidade pseudo-tratada em 2009 no SDiD de distancia a China.
#
# Le somente o target `synth_data` existente. O Brasil, unidade realmente
# tratada em 2009, e retirado do pool de doadores da especificacao limpa.
# `targets::tar_make()` nao e executado.

suppressPackageStartupMessages(library(dplyr))

source(file.path("scripts", "diagnostics", "sdid_placebo_helpers.R"))
sdid_limit_blas_threads()

year_start <- 1997L
year_end <- 2015L
treat_year <- 2009L
out_dir <- file.path(
  "data", "processed", "diagnostics", "india_pseudo_treated_2009"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

synth_data <- targets::tar_read_raw("synth_data", store = "_targets") |>
  filter(year >= year_start, year <= year_end)

if (!all(c("IND", "BRA") %in% unique(synth_data$iso3c))) {
  stop("India ou Brasil ausente do painel SDiD.", call. = FALSE)
}

clean_panel <- synth_data |>
  filter(iso3c != "BRA")

fit_india <- sdid_fit_spec(
  clean_panel,
  treated_iso3c = "IND",
  year_start = year_start,
  year_end = year_end,
  treat_year = treat_year
)

distribution <- sdid_rank_distribution(
  clean_panel,
  label = "india_pseudo_treated_2009_excluding_brazil",
  year_start = year_start,
  year_end = year_end,
  treat_year = treat_year,
  cores = sdid_available_cores(cap = 8L)
)

rank_result <- sdid_rank_inference(
  distribution,
  comparison_set = "India pseudo-treated in 2009; Brazil excluded",
  treated_iso3c = "IND"
)

fit_summary <- sdid_fit_summary_row(
  fit_india,
  specification = "India pseudo-treated in 2009; Brazil excluded"
)

setup <- attr(fit_india, "setup")
weights <- attr(fit_india, "weights")
donor_outcomes <- setup$Y[seq_len(setup$N0), , drop = FALSE]
india_outcome <- as.numeric(setup$Y[setup$N0 + 1L, ])
synthetic_outcome <- as.numeric(
  t(as.numeric(weights$omega)) %*% donor_outcomes
)
years <- sort(unique(clean_panel$year))

series <- tibble::tibble(
  year = years,
  post_2009 = year >= treat_year,
  india_china_distance = india_outcome,
  synthetic_distance = synthetic_outcome,
  india_minus_synthetic = india_outcome - synthetic_outcome
)

canonical_distribution_path <- file.path(
  "data", "processed", "diagnostics",
  "paper_v4_brazil_sdid_no_covariates", "placebo_distribution.csv"
)
canonical_india <- if (file.exists(canonical_distribution_path)) {
  readr::read_csv(canonical_distribution_path, show_col_types = FALSE) |>
    filter(iso3c == "IND") |>
    dplyr::select(
      canonical_att_with_brazil_as_donor = estimate,
      canonical_rmspe_pre_with_brazil_as_donor = rmspe_pre
    )
} else {
  tibble::tibble(
    canonical_att_with_brazil_as_donor = NA_real_,
    canonical_rmspe_pre_with_brazil_as_donor = NA_real_
  )
}

summary_result <- fit_summary |>
  transmute(
    specification,
    year_start = year_start,
    year_end = year_end,
    treat_year = treat_year,
    n_units,
    n_donors,
    att = estimate,
    rmspe_pre,
    rmspe_post,
    rmspe_ratio,
    india_raw_pre_mean = mean(
      series$india_china_distance[!series$post_2009]
    ),
    india_raw_post_mean = mean(
      series$india_china_distance[series$post_2009]
    ),
    india_raw_post_minus_pre = india_raw_post_mean - india_raw_pre_mean,
    rank_one_sided_negative = rank_result$rank_one_sided_negative,
    rank_two_sided_absolute = rank_result$rank_two_sided_absolute,
    rank_denominator = rank_result$denominator,
    p_rank_one_sided_negative = rank_result$p_rank_one_sided_negative,
    p_rank_two_sided_absolute = rank_result$p_rank_two_sided_absolute,
    rmspe_pre_rank_ascending = sum(
      distribution$rmspe_pre <= rmspe_pre,
      na.rm = TRUE
    ),
    rmspe_pre_rank_denominator = sum(!is.na(distribution$rmspe_pre)),
    rmspe_pre_percentile = mean(
      distribution$rmspe_pre <= rmspe_pre,
      na.rm = TRUE
    ),
    placebo_median_rmspe_pre = stats::median(
      distribution$rmspe_pre,
      na.rm = TRUE
    )
  ) |>
  bind_cols(canonical_india)

readr::write_csv(
  summary_result,
  file.path(out_dir, "india_pseudo_treated_2009_summary.csv")
)
readr::write_csv(
  series,
  file.path(out_dir, "india_pseudo_treated_2009_series.csv")
)
readr::write_csv(
  distribution,
  file.path(out_dir, "india_pseudo_treated_2009_placebo_distribution.csv")
)

manifest <- tibble::tibble(
  run_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  synth_data_sha256 = digest::digest(synth_data, algo = "sha256"),
  script_sha256 = digest::digest(
    file = file.path(
      "scripts", "diagnostics", "estimate_india_pseudo_treated_2009.R"
    ),
    algo = "sha256"
  ),
  note = paste(
    "India pseudo-treated from 2009; Brazil excluded from donors;",
    "no tar_make() executed."
  )
)
readr::write_csv(manifest, file.path(out_dir, "run_manifest.csv"))
writeLines(
  enc2utf8(capture.output(utils::sessionInfo())),
  file.path(out_dir, "session_info.txt")
)

print(summary_result, width = Inf)
