#!/usr/bin/env Rscript

###############################################################################
# diagnose_goal4_h2_scope_condition.R
#
# Standalone diagnostic for Goal 4 / H2:
# Does the China top-rank effect look larger when China displaces the United
# States than when it displaces another incumbent top export destination?
#
# This script does not modify _targets.R, _targets/, _targets.yaml, or any
# manuscript file. It reads existing targets and writes diagnostic outputs under:
# quality_reports/goal4_h2_scope_condition/
###############################################################################

options(scipen = 999)

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(countrycode)
  library(here)
})

source(here::here("scripts", "functions.R"))

analysis_date <- as.character(Sys.Date())
out_dir <- here::here("quality_reports", "goal4_h2_scope_condition")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

stamp <- gsub("-", "", analysis_date)

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, format = "f", digits = digits))
}

fmt_pct <- function(x, digits = 1) {
  ifelse(is.na(x), "NA", paste0(formatC(100 * x, format = "f", digits = digits), "%"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, "<0.001", formatC(x, format = "f", digits = 3)))
}

partner_name <- function(iso3c) {
  iso3c_chr <- as.character(iso3c)
  out <- rep(NA_character_, length(iso3c_chr))
  observed <- !is.na(iso3c_chr)
  out[observed] <- countrycode::countrycode(
    iso3c_chr[observed],
    origin = "iso3c",
    destination = "country.name",
    warn = FALSE
  )
  out
}

md_table <- function(df) {
  if (nrow(df) == 0L) {
    return("_Sem linhas._")
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  df[] <- lapply(df, function(x) {
    x <- as.character(x)
    x[is.na(x)] <- ""
    gsub("\\|", "/", x)
  })
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(df)), collapse = " | "), " |")
  rows <- apply(df, 1, function(row) paste0("| ", paste(row, collapse = " | "), " |"))
  paste(c(header, separator, rows), collapse = "\n")
}

first_or_na <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA)
  }
  x[1]
}

compute_incumbent_tenure <- function(iso, entry_year, incumbent, top_partner_history) {
  if (is.na(iso) || is.na(entry_year) || is.na(incumbent)) {
    return(tibble::tibble(
      incumbent_tenure_observed = NA_integer_,
      incumbent_tenure_left_censored = NA,
      incumbent_tenure_start_observed = NA_integer_,
      incumbent_tenure_end_observed = NA_integer_
    ))
  }

  history <- top_partner_history |>
    dplyr::filter(iso3c == iso, year < entry_year) |>
    dplyr::arrange(dplyr::desc(year))

  if (nrow(history) == 0L) {
    return(tibble::tibble(
      incumbent_tenure_observed = 0L,
      incumbent_tenure_left_censored = TRUE,
      incumbent_tenure_start_observed = NA_integer_,
      incumbent_tenure_end_observed = NA_integer_
    ))
  }

  expected_year <- entry_year - 1L
  tenure <- 0L
  years_in_streak <- integer(0)

  for (i in seq_len(nrow(history))) {
    row_year <- history$year[i]
    row_partner <- history$top_partner[i]
    if (is.na(row_year) || row_year != expected_year) {
      break
    }
    if (is.na(row_partner) || row_partner != incumbent) {
      break
    }
    tenure <- tenure + 1L
    years_in_streak <- c(years_in_streak, row_year)
    expected_year <- expected_year - 1L
  }

  country_min_year <- min(history$year, na.rm = TRUE)
  tenure_left_censored <- tenure > 0L && min(years_in_streak) == country_min_year

  tibble::tibble(
    incumbent_tenure_observed = tenure,
    incumbent_tenure_left_censored = tenure_left_censored,
    incumbent_tenure_start_observed = ifelse(tenure > 0L, min(years_in_streak), NA_integer_),
    incumbent_tenure_end_observed = ifelse(tenure > 0L, max(years_in_streak), NA_integer_)
  )
}

safe_fect <- function(panel, label, nboots = 500) {
  result <- tryCatch(
    {
      fit <- run_fect_analysis(
        panel,
        method = "ife",
        nboots = nboots,
        fml = abs_distance_china ~ china_top
      )
      s <- fect_att_summary(fit)
      list(ok = TRUE, fit = fit, summary = s, error = "")
    },
    error = function(e) {
      list(ok = FALSE, fit = NULL, summary = NULL, error = conditionMessage(e))
    }
  )

  result$label <- label
  result
}

scope_counts <- function(panel, label) {
  count_panel <- panel |>
    dplyr::filter(iso3c != "CHN") |>
    dplyr::filter(!is.na(china_top), !is.na(abs_distance_china))

  count_panel |>
    dplyr::arrange(iso3c, year) |>
    dplyr::group_by(iso3c) |>
    dplyr::mutate(
      lag_treat = dplyr::lag(china_top),
      entry = china_top == 1L & !is.na(lag_treat) & lag_treat == 0L,
      exit = china_top == 0L & !is.na(lag_treat) & lag_treat == 1L
    ) |>
    dplyr::summarise(
      ever_treated = any(china_top == 1L, na.rm = TRUE),
      treated_years = sum(china_top == 1L, na.rm = TRUE),
      entries = sum(entry, na.rm = TRUE),
      exits = sum(exit, na.rm = TRUE),
      left_censored = dplyr::first(china_top) == 1L,
      .groups = "drop"
    ) |>
    dplyr::summarise(
      specification = label,
      n_obs = nrow(count_panel),
      n_countries = dplyr::n_distinct(count_panel$iso3c),
      n_treated_countries = sum(ever_treated, na.rm = TRUE),
      n_control_countries = sum(!ever_treated, na.rm = TRUE),
      n_treated_country_years = sum(treated_years, na.rm = TRUE),
      n_entries = sum(entries, na.rm = TRUE),
      n_exits = sum(exits, na.rm = TRUE),
      n_left_censored = sum(left_censored, na.rm = TRUE),
      .groups = "drop"
    )
}

fit_row <- function(fit_result, panel, label) {
  counts <- scope_counts(panel, label)
  if (!fit_result$ok) {
    return(counts |>
      dplyr::mutate(
        att = NA_real_,
        se = NA_real_,
        ci_lo = NA_real_,
        ci_hi = NA_real_,
        p = NA_real_,
        r_cv = NA_real_,
        status = "failed",
        error = fit_result$error
      ))
  }

  counts |>
    dplyr::mutate(
      att = as.numeric(fit_result$summary$att),
      se = as.numeric(fit_result$summary$se),
      ci_lo = as.numeric(fit_result$summary$ci_lo),
      ci_hi = as.numeric(fit_result$summary$ci_hi),
      p = as.numeric(fit_result$summary$p),
      r_cv = as.numeric(fit_result$summary$r_cv),
      status = "ok",
      error = ""
    )
}

make_scope_panel <- function(panel, scope) {
  panel_scope <- panel |>
    dplyr::mutate(
      active_us = china_top == 1L & previous_top_partner_at_entry == "USA",
      active_non_us = china_top == 1L &
        !is.na(previous_top_partner_at_entry) &
        previous_top_partner_at_entry != "USA",
      scope_treat = dplyr::case_when(
        scope == "us_displacement" & active_us ~ 1L,
        scope == "us_displacement" & active_non_us ~ NA_integer_,
        scope == "non_us_displacement" & active_non_us ~ 1L,
        scope == "non_us_displacement" & active_us ~ NA_integer_,
        TRUE ~ 0L
      ),
      china_top = scope_treat
    ) |>
    dplyr::filter(!is.na(china_top)) |>
    dplyr::mutate(country_id = as.integer(as.factor(iso3c))) |>
    dplyr::arrange(country_id, year)

  as.data.frame(panel_scope)
}

run_twfe_interaction <- function(panel) {
  if (!requireNamespace("fixest", quietly = TRUE)) {
    return(tibble::tibble(
      model = "TWFE interaction",
      term = c("US displacement", "Non-US displacement", "US minus non-US"),
      estimate = NA_real_,
      se = NA_real_,
      p = NA_real_,
      status = "failed",
      error = "Package fixest is not installed."
    ))
  }

  twfe_data <- panel |>
    dplyr::mutate(
      china_top_us = as.integer(china_top == 1L & previous_top_partner_at_entry == "USA"),
      china_top_non_us = as.integer(
        china_top == 1L &
          !is.na(previous_top_partner_at_entry) &
          previous_top_partner_at_entry != "USA"
      )
    )

  fit <- tryCatch(
    fixest::feols(
      abs_distance_china ~ china_top_us + china_top_non_us | iso3c + year,
      data = twfe_data,
      cluster = ~iso3c
    ),
    error = function(e) e
  )

  if (inherits(fit, "error")) {
    return(tibble::tibble(
      model = "TWFE interaction",
      term = c("US displacement", "Non-US displacement", "US minus non-US"),
      estimate = NA_real_,
      se = NA_real_,
      p = NA_real_,
      status = "failed",
      error = conditionMessage(fit)
    ))
  }

  coefs <- stats::coef(fit)
  vc <- stats::vcov(fit)
  us_term <- "china_top_us"
  non_us_term <- "china_top_non_us"
  delta <- unname(coefs[us_term] - coefs[non_us_term])
  delta_se <- sqrt(vc[us_term, us_term] + vc[non_us_term, non_us_term] - 2 * vc[us_term, non_us_term])
  delta_p <- 2 * stats::pnorm(-abs(delta / delta_se))

  tibble::tibble(
    model = "TWFE interaction",
    term = c("US displacement", "Non-US displacement", "US minus non-US"),
    estimate = c(unname(coefs[us_term]), unname(coefs[non_us_term]), delta),
    se = c(sqrt(vc[us_term, us_term]), sqrt(vc[non_us_term, non_us_term]), delta_se),
    p = c(
      2 * stats::pnorm(-abs(unname(coefs[us_term]) / sqrt(vc[us_term, us_term]))),
      2 * stats::pnorm(-abs(unname(coefs[non_us_term]) / sqrt(vc[non_us_term, non_us_term]))),
      delta_p
    ),
    status = "ok",
    error = ""
  )
}

bootstrap_difference <- function(us_fit, non_us_fit) {
  if (!us_fit$ok || !non_us_fit$ok) {
    return(tibble::tibble(
      contrast = "US fect ATT minus non-US fect ATT",
      estimate = NA_real_,
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_boot = NA_integer_,
      note = "One or both fect fits failed."
    ))
  }

  us_boot <- as.numeric(us_fit$fit$att.avg.boot)
  non_us_boot <- as.numeric(non_us_fit$fit$att.avg.boot)
  us_boot <- us_boot[is.finite(us_boot)]
  non_us_boot <- non_us_boot[is.finite(non_us_boot)]
  n_boot <- min(length(us_boot), length(non_us_boot))

  if (n_boot < 50L) {
    return(tibble::tibble(
      contrast = "US fect ATT minus non-US fect ATT",
      estimate = as.numeric(us_fit$summary$att - non_us_fit$summary$att),
      se = NA_real_,
      ci_lo = NA_real_,
      ci_hi = NA_real_,
      p = NA_real_,
      n_boot = n_boot,
      note = "Too few finite bootstrap draws for a diagnostic difference."
    ))
  }

  diff_boot <- us_boot[seq_len(n_boot)] - non_us_boot[seq_len(n_boot)]
  estimate <- as.numeric(us_fit$summary$att - non_us_fit$summary$att)
  se <- stats::sd(diff_boot)
  tibble::tibble(
    contrast = "US fect ATT minus non-US fect ATT",
    estimate = estimate,
    se = se,
    ci_lo = estimate - 1.96 * se,
    ci_hi = estimate + 1.96 * se,
    p = 2 * stats::pnorm(-abs(estimate / se)),
    n_boot = n_boot,
    note = "Exploratory paired-draw contrast from two separately estimated fect bootstraps; not a definitive joint bootstrap."
  )
}

cat("Loading target objects...\n")
trade_data <- targets::tar_read(trade_data)
unga_data <- targets::tar_read(unga_data)
classified_events <- targets::tar_read(classified_events)
usa_top_countries <- targets::tar_read(usa_top_countries)
china_top_panel_target <- targets::tar_read(china_top_panel)
fect_ife_china_top_summary <- targets::tar_read(fect_ife_china_top_summary)

switching_panel_old <- tryCatch(targets::tar_read(switching_panel), error = function(e) NULL)

cat("Rebuilding China-top panel from existing helper for validation...\n")
china_top_panel_rebuilt <- build_china_top_partner_panel(
  trade_data = trade_data,
  unga_data = unga_data,
  classified_events = classified_events,
  usa_top_countries = usa_top_countries,
  min_year = 1990,
  min_entry_year = 2000
)

target_compare <- china_top_panel_target |>
  dplyr::select(iso3c, year, target_china_top = china_top) |>
  dplyr::full_join(
    china_top_panel_rebuilt |>
      dplyr::select(iso3c, year, rebuilt_china_top = china_top),
    by = c("iso3c", "year")
  ) |>
  dplyr::mutate(
    match = (is.na(target_china_top) & is.na(rebuilt_china_top)) |
      (!is.na(target_china_top) & !is.na(rebuilt_china_top) &
         target_china_top == rebuilt_china_top)
  )

top_partner_history <- trade_data |>
  dplyr::group_by(year, exporter_iso3) |>
  dplyr::arrange(dplyr::desc(exports), .by_group = TRUE) |>
  dplyr::slice(1L) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    iso3c = exporter_iso3,
    year = year,
    top_partner = importer_iso3,
    top_exports = exports
  )

panel <- china_top_panel_target |>
  dplyr::arrange(iso3c, year) |>
  dplyr::group_by(iso3c) |>
  dplyr::mutate(
    china_top_lag = dplyr::lag(china_top),
    treatment_spell_start = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L,
    left_censored_current_panel = dplyr::first(china_top) == 1L,
    treatment_spell_id = cumsum(treatment_spell_start)
  ) |>
  dplyr::ungroup()

treated_spells_base <- panel |>
  dplyr::filter(china_top == 1L) |>
  dplyr::group_by(
    iso3c,
    country_name,
    treatment_spell_id,
    entry_year,
    previous_observed_year_at_entry,
    previous_china_is_top_at_entry,
    previous_top_partner_at_entry,
    previous_trade_observed_at_entry
  ) |>
  dplyr::summarise(
    first_treated_year = min(year),
    last_treated_year = max(year),
    treated_years = dplyr::n(),
    entry_rank_china = first_or_na(rank_CHN[year == min(year)]),
    entry_rank_usa = first_or_na(rank_USA[year == min(year)]),
    entry_top_partner = first_or_na(top_partner[year == min(year)]),
    .groups = "drop"
  ) |>
  dplyr::arrange(entry_year, iso3c, treatment_spell_id)

tenure_rows <- lapply(seq_len(nrow(treated_spells_base)), function(i) {
  compute_incumbent_tenure(
    iso = treated_spells_base$iso3c[i],
    entry_year = treated_spells_base$entry_year[i],
    incumbent = treated_spells_base$previous_top_partner_at_entry[i],
    top_partner_history = top_partner_history
  )
})

treated_spells <- dplyr::bind_cols(
  treated_spells_base,
  dplyr::bind_rows(tenure_rows)
) |>
  dplyr::mutate(
    displaced_partner = previous_top_partner_at_entry,
    displaced_partner_name = partner_name(displaced_partner),
    us_displacement = displaced_partner == "USA",
    us_displacement_indicator = as.integer(us_displacement),
    scope_group = dplyr::if_else(us_displacement, "U.S. displacement", "Non-U.S. displacement"),
    previous_year_adjacent = previous_observed_year_at_entry == entry_year - 1L,
    treatment_left_censored = is.na(previous_china_is_top_at_entry),
    entry_is_china_top = entry_top_partner == "CHN" & entry_rank_china == 1L
  )

exit_rows <- panel |>
  dplyr::select(
    iso3c,
    exit_year = year,
    exit_top_partner = top_partner,
    exit_rank_china = rank_CHN,
    exit_rank_usa = rank_USA,
    exit_china_top = china_top
  )

treated_spells <- treated_spells |>
  dplyr::mutate(exit_year = last_treated_year + 1L) |>
  dplyr::left_join(exit_rows, by = c("iso3c", "exit_year")) |>
  dplyr::mutate(
    exit_observed = !is.na(exit_china_top),
    switching_status = dplyr::case_when(
      exit_observed & exit_china_top == 0L ~ "switched_off_observed",
      exit_observed & exit_china_top == 1L ~ "still_treated_in_next_year",
      !exit_observed ~ "right_censored_at_panel_end",
      TRUE ~ "unclassified"
    ),
    exit_top_partner_name = partner_name(exit_top_partner)
  )

treated_cases <- treated_spells |>
  dplyr::transmute(
    country = country_name,
    iso3c = iso3c,
    treatment_year = entry_year,
    displaced_partner = displaced_partner,
    displaced_partner_name = displaced_partner_name,
    us_displacement_indicator = us_displacement_indicator,
    incumbent_tenure_observed = incumbent_tenure_observed,
    incumbent_tenure_left_censored = incumbent_tenure_left_censored,
    treated_years = treated_years,
    first_treated_year = first_treated_year,
    last_treated_year = last_treated_year,
    switching_status = switching_status,
    exit_year = exit_year,
    exit_top_partner = exit_top_partner,
    exit_top_partner_name = exit_top_partner_name,
    previous_year_adjacent = previous_year_adjacent,
    treatment_left_censored = treatment_left_censored
  ) |>
  dplyr::arrange(treatment_year, iso3c)

country_scope_mixing <- treated_cases |>
  dplyr::group_by(iso3c, country) |>
  dplyr::summarise(
    n_spells = dplyr::n(),
    n_us_spells = sum(us_displacement_indicator == 1L, na.rm = TRUE),
    n_non_us_spells = sum(us_displacement_indicator == 0L, na.rm = TRUE),
    has_both_scope_types = n_us_spells > 0L & n_non_us_spells > 0L,
    spells = paste0(treatment_year, ":", displaced_partner, collapse = "; "),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(has_both_scope_types), country)

validation_checks <- tibble::tibble(
  check = c(
    "target_rebuild_country_year_mismatch",
    "duplicate_country_years_in_target_panel",
    "missing_outcome_in_target_panel",
    "missing_treatment_in_target_panel",
    "treated_rows_where_china_not_literal_top",
    "treated_spells_without_observed_previous_top_partner",
    "treated_spells_where_previous_partner_is_china",
    "treated_spells_without_adjacent_previous_year",
    "treated_spells_with_nonpositive_incumbent_tenure",
    "treated_spells_left_censored",
    "treated_spells_without_observed_switch_status"
  ),
  n_fail = c(
    sum(is.na(target_compare$match) | !target_compare$match, na.rm = TRUE),
    sum(duplicated(china_top_panel_target[, c("iso3c", "year")])),
    sum(is.na(china_top_panel_target$abs_distance_china)),
    sum(is.na(china_top_panel_target$china_top)),
    panel |>
      dplyr::filter(china_top == 1L) |>
      dplyr::summarise(n = sum(!china_is_top, na.rm = TRUE)) |>
      dplyr::pull(n),
    sum(is.na(treated_cases$displaced_partner)),
    sum(treated_cases$displaced_partner == "CHN", na.rm = TRUE),
    sum(!treated_cases$previous_year_adjacent, na.rm = TRUE),
    sum(treated_cases$incumbent_tenure_observed <= 0L, na.rm = TRUE),
    sum(treated_cases$treatment_left_censored, na.rm = TRUE),
    sum(treated_cases$switching_status == "unclassified", na.rm = TRUE)
  )
) |>
  dplyr::mutate(
    status = dplyr::case_when(
      check == "missing_treatment_in_target_panel" & n_fail > 0L ~ "INFO",
      n_fail == 0L ~ "PASS",
      TRUE ~ "CHECK"
    ),
    implication = dplyr::case_when(
      check == "target_rebuild_country_year_mismatch" & n_fail == 0L ~
        "The stored china_top_panel matches the rebuilt helper output.",
      check == "target_rebuild_country_year_mismatch" ~
        "The stored panel differs from the helper rebuild; inspect before using estimates.",
      check == "treated_spells_without_adjacent_previous_year" & n_fail > 0L ~
        "Some displaced-partner labels are based on non-adjacent prior observations.",
      check == "treated_spells_with_nonpositive_incumbent_tenure" & n_fail > 0L ~
        "Some incumbent-tenure values are not supported by an observed prior-year streak.",
      check == "missing_treatment_in_target_panel" & n_fail > 0L ~
        "Rows with missing trade-rank treatment are dropped from the fect estimation sample; this is documented rather than a substantive treatment-rule failure.",
      TRUE ~ ""
    )
  )

old_rule_audit <- tibble::tibble(
  metric = character(),
  value = numeric()
)

if (!is.null(switching_panel_old)) {
  old_rule_compare <- switching_panel_old |>
    dplyr::select(iso3c, year, old_china_top = china_top) |>
    dplyr::inner_join(
      china_top_panel_target |>
        dplyr::select(iso3c, year, exact_china_top = china_top),
      by = c("iso3c", "year")
    )

  old_rule_audit <- tibble::tibble(
    metric = c(
      "old_switching_panel_rows_compared",
      "old_switching_panel_treated_country_years",
      "exact_china_top_treated_country_years_on_same_rows",
      "old_rule_treated_but_exact_not_treated",
      "exact_treated_but_old_rule_not_treated",
      "old_exact_treatment_mismatches"
    ),
    value = c(
      nrow(old_rule_compare),
      sum(old_rule_compare$old_china_top == 1L, na.rm = TRUE),
      sum(old_rule_compare$exact_china_top == 1L, na.rm = TRUE),
      sum(old_rule_compare$old_china_top == 1L & old_rule_compare$exact_china_top == 0L, na.rm = TRUE),
      sum(old_rule_compare$old_china_top == 0L & old_rule_compare$exact_china_top == 1L, na.rm = TRUE),
      sum(old_rule_compare$old_china_top != old_rule_compare$exact_china_top, na.rm = TRUE)
    )
  )
}

descriptive_counts <- dplyr::bind_rows(
  scope_counts(panel, "Pooled exact China-top panel"),
  scope_counts(make_scope_panel(panel, "us_displacement"), "U.S.-displacement active spells"),
  scope_counts(make_scope_panel(panel, "non_us_displacement"), "Non-U.S.-displacement active spells")
) |>
  dplyr::mutate(
    share_treated_countries = n_treated_countries / n_countries,
    share_treated_country_years = n_treated_country_years / n_obs
  )

scope_spell_counts <- treated_cases |>
  dplyr::count(us_displacement_indicator, name = "n_spells") |>
  dplyr::mutate(scope_group = dplyr::if_else(us_displacement_indicator == 1L, "U.S. displacement", "Non-U.S. displacement")) |>
  dplyr::select(scope_group, us_displacement_indicator, n_spells)

cat("Running fect IFE subgroup diagnostics with 500 bootstrap replications...\n")
panel_us <- make_scope_panel(panel, "us_displacement")
panel_non_us <- make_scope_panel(panel, "non_us_displacement")
fit_us <- safe_fect(panel_us, "U.S.-displacement active spells", nboots = 500)
fit_non_us <- safe_fect(panel_non_us, "Non-U.S.-displacement active spells", nboots = 500)

fect_subgroup_results <- dplyr::bind_rows(
  fit_row(fit_us, panel_us, "U.S.-displacement active spells"),
  fit_row(fit_non_us, panel_non_us, "Non-U.S.-displacement active spells")
)

fect_difference <- bootstrap_difference(fit_us, fit_non_us)
twfe_results <- run_twfe_interaction(panel)

confirmatory_status <- dplyr::case_when(
  any(fect_subgroup_results$status != "ok") ~
    "Demover H2: pelo menos um modelo fect de subgrupo falhou.",
  min(fect_subgroup_results$n_treated_countries, na.rm = TRUE) < 10L ~
    "Demover H2: pelo menos um subgrupo tem menos de dez países tratados.",
  is.na(fect_difference$p[1]) ~
    "Tratar H2 como exploratória: não há estimativa defensável de incerteza para a diferença entre subgrupos.",
  TRUE ~
    "Tratar H2 como exploratória, salvo se um desenho confirmatório futuro sustentar uma conclusão mais forte."
)

h2_directional_result <- if (
  all(fect_subgroup_results$status == "ok") &&
    all(is.finite(fect_subgroup_results$att)) &&
    nrow(fect_subgroup_results) == 2L
) {
  us_att <- fect_subgroup_results$att[fect_subgroup_results$specification == "U.S.-displacement active spells"]
  non_us_att <- fect_subgroup_results$att[fect_subgroup_results$specification == "Non-U.S.-displacement active spells"]
  if (us_att < non_us_att) {
    "direcionalmente consistente com H2, porque o ATT de U.S.-displacement é mais negativo"
  } else {
    "não é direcionalmente consistente com H2, porque o ATT de U.S.-displacement não é mais negativo"
  }
} else {
  "não é avaliável porque pelo menos um modelo de subgrupo falhou"
}

write.csv(
  treated_cases,
  file.path(out_dir, paste0("goal4_h2_treated_cases_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  validation_checks,
  file.path(out_dir, paste0("goal4_h2_validation_checks_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  old_rule_audit,
  file.path(out_dir, paste0("goal4_h2_old_rule_audit_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  descriptive_counts,
  file.path(out_dir, paste0("goal4_h2_descriptive_counts_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  country_scope_mixing,
  file.path(out_dir, paste0("goal4_h2_country_scope_mixing_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  fect_subgroup_results,
  file.path(out_dir, paste0("goal4_h2_fect_subgroup_results_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  fect_difference,
  file.path(out_dir, paste0("goal4_h2_fect_difference_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)
write.csv(
  twfe_results,
  file.path(out_dir, paste0("goal4_h2_twfe_interaction_results_", stamp, ".csv")),
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

pooled_summary <- fect_ife_china_top_summary |>
  dplyr::mutate(specification = "Pooled exact China-top fect IFE target") |>
  dplyr::select(
    specification,
    n_obs,
    n_countries,
    n_treated,
    n_control,
    n_treated_country_years,
    n_entries,
    n_exits,
    n_left_censored,
    att,
    se,
    ci_lo,
    ci_hi,
    p,
    r_cv
  )

report_path <- file.path(out_dir, paste0("goal4_h2_methodological_report_", stamp, ".md"))

report_lines <- c(
  "# Relatório metodológico: Goal 4 / H2",
  "",
  paste0("Data: ", analysis_date),
  "",
  "Escopo: este relatório avalia se a H2 pode ser testada diretamente no painel cross-country ou se deve ser demovida para condição de escopo. Nenhum arquivo principal do manuscrito foi editado.",
  "",
  "Regra operacional: quem revisa não implementa; quem implementa não revisa. Este arquivo é o produto do implementador analítico e deve passar por revisão separada antes de orientar qualquer edição do paper.",
  "",
  "## Resumo executivo",
  "",
  paste0(
    "- A amostra estimável do painel exato de `china_top_panel` contém ",
    descriptive_counts$n_treated_countries[descriptive_counts$specification == "Pooled exact China-top panel"],
    " países tratados e ",
    descriptive_counts$n_entries[descriptive_counts$specification == "Pooled exact China-top panel"],
    " entradas de tratamento. No nível dos spells, ",
    scope_spell_counts$n_spells[scope_spell_counts$scope_group == "U.S. displacement"],
    " entradas deslocam os EUA e ",
    scope_spell_counts$n_spells[scope_spell_counts$scope_group == "Non-U.S. displacement"],
    " deslocam outro parceiro."
  ),
  paste0(
    "- O ATT pooled já existente é ",
    fmt_num(pooled_summary$att[1]), " (SE bootstrap = ",
    fmt_num(pooled_summary$se[1]), ", p = ", fmt_p(pooled_summary$p[1]),
    "). Esse ATT não testa H2 porque agrega condições de escopo heterogêneas."
  ),
  paste0(
    "- A comparação fect por subgrupo ", h2_directional_result,
    ". A diferença US menos non-US é ",
    fmt_num(fect_difference$estimate[1]), " (SE exploratório = ",
    fmt_num(fect_difference$se[1]), ", p = ", fmt_p(fect_difference$p[1]), ")."
  ),
  paste0("- Veredito operacional: ", confirmatory_status),
  "",
  "## Desenho causal reconstruído",
  "",
  "- Unidade: país-ano.",
  "- Período do painel: 1990-2022 no painel cross-country atualmente armazenado.",
  "- Outcome: distância absoluta entre o país e a China em ideal points da AGNU (`abs_distance_china`). Valores menores indicam convergência em direção à China.",
  "- Tratamento principal: `china_top = 1` nos anos em que a China é o principal destino de exportações do país, desde que a entrada no top rank ocorra a partir de 2000 e após um ano observado em que a China ainda não era número 1.",
  "- H2 não é um tratamento separado. O deslocamento dos EUA é uma condição de escopo/moderador/intensificador do tratamento principal.",
  "- Estimando substantivo de H2: diferença entre o efeito de anos tratados em spells nos quais a China desloca os EUA e o efeito de anos tratados em spells nos quais a China desloca outro incumbente.",
  "",
  "## Auditoria da definição de tratamento",
  "",
  "Tabela 1. Auditoria da regra antiga `switching_panel` versus o painel exato `china_top_panel`.",
  "",
  md_table(old_rule_audit),
  "",
  "Interpretação: a regra antiga `switching_panel` é conceitualmente frágil para H2 porque mede se a China ultrapassa os EUA no ranking, não necessariamente se a China se torna o destino de exportação número 1. A análise abaixo usa o painel exato `china_top_panel`.",
  "",
  "Tabela 2. Checagens lógicas do painel e dos spells tratados.",
  "",
  md_table(validation_checks),
  "",
  "## Casos tratados",
  "",
  "Tabela 3. Entradas de tratamento por país, ano, parceiro deslocado, indicador de deslocamento dos EUA, tenure do incumbente e status de switching.",
  "",
  md_table(treated_cases |>
    dplyr::select(
      country,
      iso3c,
      treatment_year,
      displaced_partner,
      us_displacement_indicator,
      incumbent_tenure_observed,
      incumbent_tenure_left_censored,
      treated_years,
      switching_status
    )),
  "",
  "Observação: alguns países têm múltiplos spells e alguns combinam spells de U.S.-displacement e non-U.S.-displacement. Isso dificulta uma leitura country-level simples de H2.",
  "",
  "Tabela 4. Países com mistura de tipos de escopo ao longo de múltiplos spells.",
  "",
  md_table(country_scope_mixing |>
    dplyr::filter(has_both_scope_types) |>
    dplyr::select(country, iso3c, n_spells, n_us_spells, n_non_us_spells, spells)),
  "",
  "## Resultados exploratórios",
  "",
  "Tabela 5. Sumário do modelo pooled existente.",
  "",
  md_table(pooled_summary |>
    dplyr::mutate(
      att = fmt_num(att),
      se = fmt_num(se),
      ci_lo = fmt_num(ci_lo),
      ci_hi = fmt_num(ci_hi),
      p = fmt_p(p)
    )),
  "",
  "Tabela 6. fect IFE por tipo de spell ativo. Os anos tratados do outro tipo de spell são removidos da respectiva subamostra para reduzir contaminação mecânica.",
  "",
  md_table(fect_subgroup_results |>
    dplyr::mutate(
      att = fmt_num(att),
      se = fmt_num(se),
      ci_lo = fmt_num(ci_lo),
      ci_hi = fmt_num(ci_hi),
      p = fmt_p(p)
    )),
  "",
  "Tabela 7. Diferença exploratória entre ATTs fect por subgrupo.",
  "",
  md_table(fect_difference |>
    dplyr::mutate(
      estimate = fmt_num(estimate),
      se = fmt_num(se),
      ci_lo = fmt_num(ci_lo),
      ci_hi = fmt_num(ci_hi),
      p = fmt_p(p)
    )),
  "",
  "Tabela 8. TWFE com interação por tipo de deslocamento. Esta regressão é apenas descritiva, pois não substitui a estrutura IFE nem resolve heterogeneidade dinâmica.",
  "",
  md_table(twfe_results |>
    dplyr::mutate(
      estimate = fmt_num(estimate),
      se = fmt_num(se),
      p = fmt_p(p)
    )),
  "",
  "## Parecer de identificação causal",
  "",
  "### Suposições necessárias",
  "",
  "| Suposição | Evidência disponível | Diagnóstico possível | Status | Implicação |",
  "| --- | --- | --- | --- | --- |",
  "| Top-rank status é comparável entre spells US e non-US | O painel mede a mesma entrada da China no top rank | Tabela de spells e parceiros deslocados | Parcial | O tratamento base é comum, mas a intensidade simbólica varia |",
  "| U.S.-displacement é uma condição de escopo pré-determinada no momento do tratamento | O parceiro deslocado é medido no ano anterior à entrada | Checagens de adjacência e tenure | Razoável, mas não randomizado | A comparação é heterogeneidade, não experimento separado |",
  "| Ausência de choques contemporâneos diferenciais por grupo | Não é diretamente testável | Placebos, event-time diagnostics e covariáveis pré-tratamento | Frágil | Países em que os EUA eram incumbentes podem ser geopoliticamente diferentes |",
  "| SUTVA/no spillovers | Não há teste direto | Discussão substantiva de spillovers regionais e sistêmicos | Não testado | Spillovers podem contaminar controles e non-US spells |",
  "| Estabilidade da estrutura de fatores latentes | fect IFE permite fatores comuns heterogêneos | Placebo/equivalence tests | Parcial | Ajuda o pooled, mas subgrupos têm menor suporte |",
  "",
  "### Veredito de identificação",
  "",
  "H2 deve ser entendida como heterogeneidade por condição de escopo. A comparação é substantivamente útil, mas não tem a força de um teste causal confirmatório porque U.S.-displacement não é designado de forma plausivelmente as-if random e está associado a geopolítica, integração comercial e história diplomática distintas.",
  "",
  "## Parecer de estimação causal",
  "",
  "- O estimador pooled atual responde à pergunta geral: o que ocorre, em média, quando a China entra e permanece no top rank de exportações.",
  "- O estimador pooled não responde diretamente à H2, porque mistura U.S.-displacement e non-U.S.-displacement.",
  "- A estratégia fect por subgrupo aproxima a pergunta de H2, mas muda o conjunto efetivo de comparação e sofre com menor número de tratados em cada subamostra.",
  "- A regressão TWFE com duas dummies de tratamento é útil como diagnóstico de sinal e diferença, mas não deve ser vendida como estimador principal em painel com tratamento reversível e efeitos heterogêneos.",
  "- A unidade substantiva de heterogeneidade é spell-level, não apenas country-level, porque há países com múltiplos spells e tipos diferentes de parceiro deslocado.",
  "",
  "### Veredito de estimação",
  "",
  "A estimação permite uma análise exploratória de H2, mas não uma alegação confirmatória forte. Para implementação futura, a opção mais honesta é reportar a tabela de spells e uma comparação exploratória por subgrupo, com linguagem de scope condition.",
  "",
  "## Parecer de inferência causal",
  "",
  "- A inferência é limitada por poucos tratados efetivos no subgrupo de U.S.-displacement e por múltiplos spells em alguns países.",
  "- O contraste bootstrap reportado emparelha draws de dois modelos estimados separadamente; ele é um diagnóstico de incerteza, não um bootstrap conjunto definitivo.",
  "- A inferência clusterizada do TWFE é apenas auxiliar e não resolve serial correlation, heterogeneidade dinâmica nem contaminação por tratamento reversível.",
  "- Placebos e equivalence tests são mais relevantes para avaliar plausibilidade do modelo pooled do que para provar H2.",
  "",
  "### Veredito de inferência",
  "",
  "A inferência para H2 é frágil. Ela é adequada para demarcar escopo e sugerir heterogeneidade, não para sustentar a frase de que H2 foi testada de modo conclusivo.",
  "",
  "## Notas de reprodutibilidade do implementador",
  "",
  "Este script segue o padrão de análise em R do repositório, usa caminhos relativos via `here::here()`, não altera o pipeline `targets`, grava outputs em diretório próprio e usa `dplyr::select()` ao selecionar colunas. Isto não é uma revisão formal do próprio trabalho. A revisão formal de código deve ser feita por um revisor separado, sem edição de arquivos, conforme a regra operacional.",
  "",
  "## Sugestões de revisão futura do paper",
  "",
  "1. Não apresentar o ATT pooled como teste de H2.",
  "2. Tratar U.S.-displacement como condição de escopo ou heterogeneidade teoricamente esperada.",
  "3. Incluir uma tabela de casos tratados com parceiro deslocado, tenure e switching status.",
  "4. Se os resultados exploratórios forem mencionados, rotulá-los como exploratory heterogeneity estimates.",
  "5. Usar linguagem cautelosa: o painel cross-country informa a generalidade do top-rank claim, mas tem poder limitado para adjudicar a hipótese de substituição hegemônica.",
  "6. Em implementação futura, considerar uma sensibilidade `first spell only` ou censura após o primeiro tratamento para avaliar carryover entre spells em países com múltiplas entradas e escopos mistos.",
  "",
  "## Veredito final antes da revisão separada",
  "",
  paste0("H2 deve ser demovida para condição de escopo com evidência exploratória, salvo se uma revisão posterior identificar uma estratégia inferencial mais forte. Resultado direcional: ", h2_directional_result, "."),
  "",
  "## Histórico de revisão separada",
  "",
  "Rodada 1: revisor separado atribuiu nota A. Não houve bloqueios para aprovação. O revisor confirmou que não editou arquivos, aprovou o relatório para handoff de implementação futura e considerou defensável o veredito de que H2 deve ser tratada como análise exploratória/condição de escopo. Melhoria não bloqueante incorporada como sugestão futura: explicitar possível carryover entre spells e considerar sensibilidade `first spell only` ou censura após primeiro tratamento."
)

writeLines(report_lines, report_path, useBytes = TRUE)

cat("\nWrote outputs to:\n")
cat("- ", report_path, "\n", sep = "")
cat("- ", file.path(out_dir, paste0("goal4_h2_treated_cases_", stamp, ".csv")), "\n", sep = "")
cat("- ", file.path(out_dir, paste0("goal4_h2_validation_checks_", stamp, ".csv")), "\n", sep = "")
cat("- ", file.path(out_dir, paste0("goal4_h2_fect_subgroup_results_", stamp, ".csv")), "\n", sep = "")
cat("- ", file.path(out_dir, paste0("goal4_h2_twfe_interaction_results_", stamp, ".csv")), "\n", sep = "")
