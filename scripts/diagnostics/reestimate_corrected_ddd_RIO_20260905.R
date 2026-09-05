#!/usr/bin/env Rscript
# RIO-R1-001: authorized direct reestimation; reads caches without touching targets.
# Run from repository root: Rscript scripts/diagnostics/reestimate_corrected_ddd_RIO_20260905.R
# No network, random draws, tar_make, SDiD, IFE, or source-data writes.
suppressPackageStartupMessages({library(dplyr); library(fixest)})
options(encoding = "UTF-8")
fixest::setFixest_nthreads(1)
out_dir <- "data/processed/diagnostics/RIO_20260905_ddd"
rev_dir <- "quality_reports/revisions/paper_v4/20260905_RIO_selected_fixes"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(rev_dir, recursive = TRUE, showWarnings = FALSE)
log_path <- file.path(out_dir, "execution.log")
sink(log_path, split = TRUE)
cat("Started:", format(Sys.time(), tz = "UTC"), "UTC\n")
started <- proc.time()[[3]]
write_csv <- function(x, name) readr::write_csv(x, file.path(out_dir, name), na = "NA")
sha <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
cache <- "_targets/objects/selective_china_alignment_unga_targets_bundle"
cached_models <- "_targets/objects/selective_china_alignment_ddd_hr_nonhr_models"
inputs <- c(cache, cached_models, "scripts/functions.R",
            "scripts/diagnostics/diagnose_selective_china_alignment_unga.R",
            "scripts/diagnostics/reestimate_corrected_ddd_RIO_20260905.R",
            file.path(rev_dir, "paper_v4.before.Rmd"), file.path(rev_dir, "paper_v4.before.pdf"),
            "quality_reports/adjudication/paper_v4/6c3b215df4f4/adjudication_round1.json",
            "quality_reports/argument_contracts/paper_v4/6c3b215df4f4/argument_contract.json")
input_manifest <- tibble(path = inputs, sha256 = vapply(inputs, sha, character(1)))
write_csv(input_manifest, "input_manifest.csv")
bundle <- readRDS(cache)
old_cached <- readRDS(cached_models)
d <- bundle$vote_panel |> filter(china_usa_divergent) |>
  mutate(human_rights_binary = as.integer(issue_domain == "Human rights"),
         brazil_hr = brazil * human_rights_binary,
         brazil_post_hr = brazil_post_2009 * human_rights_binary,
         observation_weight = 1)
outcomes <- c("distance_china_minus_usa", "agreement_china_minus_usa")
stopifnot(nrow(d) == 55190L, n_distinct(d$iso3c) == 95L, n_distinct(d$rcid) == 612L,
          !anyDuplicated(d[c("iso3c", "rcid")]), all(d$year %in% 2005:2012),
          !anyNA(d[c(outcomes, "human_rights_binary", "iso3c", "rcid")]),
          all(d$brazil == as.integer(d$iso3c == "BRA")),
          all(d$post_2009 == as.integer(d$year >= 2009)),
          all(d$brazil_post_2009 == d$brazil * d$post_2009),
          all(d$distance_china_minus_usa == abs(d$vote_ordinal-d$china_score)-abs(d$vote_ordinal-d$usa_score)),
          all(d$agreement_china_minus_usa == (d$vote_ordinal==d$china_score)-(d$vote_ordinal==d$usa_score)))
stopifnot(all((d |> summarise(n = n_distinct(human_rights_binary), .by = rcid))$n == 1L))
saveRDS(d, file.path(out_dir, "estimation_sample.rds"), version = 3)
write_csv(d |> dplyr::select(iso3c, rcid, year, issue_domain, brazil, post_2009,
  human_rights_binary, brazil_hr, brazil_post_2009, brazil_post_hr,
  all_of(outcomes), observation_weight), "estimation_sample.csv")
write_csv(d |> summarise(n_obs = n(), n_resolutions = n_distinct(rcid),
                        .by = c(iso3c, year, issue_domain)), "sample_country_year_domain.csv")
write_csv(d |> summarise(n_obs = n(), n_countries = n_distinct(iso3c),
                        n_resolutions = n_distinct(rcid), .by = c(year, issue_domain)), "sample_year_domain.csv")
write_csv(d |> summarise(n_obs = n(), relative_distance = mean(distance_china_minus_usa),
                        relative_agreement = mean(agreement_china_minus_usa),
                        .by = c(brazil, post_2009, human_rights_binary)), "raw_group_period_domain_means.csv")

# Evaluate only the named helper; sourcing the whole file is unnecessary.
helper_env <- new.env(parent = globalenv())
load_helper <- function(path, name) {
  expr <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
    identical(e[[2]], as.name(name)), as.list(parse(path)))
  stopifnot(length(expr) == 1L)
  eval(expr[[1]], envir = helper_env)
  helper_env[[name]]
}
helper <- load_helper("scripts/functions.R", "selective_unga_fit_ddd_model")
legacy_helper <- load_helper("scripts/diagnostics/diagnose_selective_china_alignment_unga.R", "fit_ddd_model")
production_ddd <- load_helper("scripts/functions.R", "build_selective_unga_corrected_ddd")
vcovs <- list(country = ~iso3c, country_resolution = ~iso3c + rcid)
vcov_labels <- c(country = "country-clustered SE", country_resolution = "two-way clustered SE by country and resolution")
tidy_fit <- function(fit, outcome, specification, covariance) {
  terms <- names(coef(fit)); ci <- confint(fit)
  tibble(outcome, specification, covariance, term = terms, estimate = unname(coef(fit)),
    se = unname(fixest::se(fit)), p_value = unname(fixest::pvalue(fit)),
    ci_95_low = ci[, 1], ci_95_high = ci[, 2], n_obs = nobs(fit),
    n_countries = n_distinct(d$iso3c), n_resolutions = n_distinct(d$rcid))
}
results <- list(); fits <- list(); compatible <- list(); comparisons <- list()
for (outcome in outcomes) for (covariance in names(vcovs)) {
  for (specification in c("original_restricted", "corrected_ddd")) {
    rhs <- if (specification == "corrected_ddd") "brazil_post_2009 + brazil_hr + brazil_post_hr" else "brazil_post_2009 + brazil_post_hr"
    fit <- feols(as.formula(paste(outcome, "~", rhs, "| iso3c + rcid")),
                 data = d, vcov = vcovs[[covariance]], notes = FALSE)
    key <- paste(outcome, covariance, specification, sep = "__")
    fits[[key]] <- fit
    results[[key]] <- tidy_fit(fit, outcome, specification, covariance)
    stopifnot(nobs(fit) == nrow(d))
  }
  current <- helper(d, outcome, vcovs[[covariance]], vcov_labels[[covariance]])
  legacy <- legacy_helper(d, outcome, vcovs[[covariance]], vcov_labels[[covariance]])
  stopifnot(isTRUE(all.equal(current, legacy, tolerance = 1e-12)))
  compatible[[paste(outcome, covariance)]] <- current
  before <- results[[paste(outcome, covariance, "original_restricted", sep = "__")]]
  cached <- old_cached |> filter(.data$outcome == .env$outcome, model == current$model[1])
  check <- before |> inner_join(cached, by = c("outcome", "term"), suffix = c("_rerun", "_cached"))
  stopifnot(nrow(check) == 2L)
  fields <- c("estimate", "se", "p_value", "ci_95_low", "ci_95_high", "n_obs")
  for (field in fields) stopifnot(max(abs(check[[paste0(field,"_rerun")]]-check[[paste0(field,"_cached")]])) < 1e-10)
  comparisons[[paste(outcome, covariance)]] <- check |> mutate(covariance = covariance)
}
results <- bind_rows(results)
compatible <- bind_rows(compatible) |> mutate(
  expected_direction = case_when(
    outcome == "distance_china_minus_usa" & term == "brazil_post_hr" ~ "negative incremental HR effect",
    outcome == "agreement_china_minus_usa" & term == "brazil_post_hr" ~ "positive incremental HR effect",
    term == "brazil_post_2009" ~ "non-HR Brazil post component", TRUE ~ "diagnostic"),
  direction_matches_expected = case_when(expected_direction == "negative incremental HR effect" ~ estimate < 0,
    expected_direction == "positive incremental HR effect" ~ estimate > 0, TRUE ~ NA))
write_csv(results, "model_results_before_after.csv")
write_csv(bind_rows(comparisons), "baseline_cache_reproduction.csv")
write_csv(compatible, "corrected_ddd_models.csv")
saveRDS(compatible, file.path(out_dir, "corrected_ddd_models.rds"), version = 3)
saveRDS(fits, file.path(out_dir, "fitted_models.rds"), version = 3)
print(results |> filter(term == "brazil_post_hr"))

# Balanced algebraic toy: persistent B x H gap alone must have zero triple difference.
toy <- expand.grid(B = 0:1, H = 0:1, P = 0:1, replicate = 1:3)
toy$iso3c <- paste0("unit", toy$B); toy$rcid <- interaction(toy$H, toy$P, toy$replicate)
toy$BP <- toy$B*toy$P; toy$BH <- toy$B*toy$H; toy$BPH <- toy$B*toy$P*toy$H
toy_checks <- bind_rows(lapply(c(0, 0.4), function(delta) {
  toy$y <- toy$BH + delta*toy$BPH
  coefficient <- function(rhs) unname(coef(lm(as.formula(paste("y ~", rhs, "+factor(iso3c)+factor(rcid)")), toy))["BPH"])
  corrected <- coefficient("BP+BH+BPH"); restricted <- coefficient("BP+BPH")
  algebra <- with(toy, mean(y[B==1 & P==1 & H==1])-mean(y[B==0 & P==1 & H==1])-
    mean(y[B==1 & P==0 & H==1])+mean(y[B==0 & P==0 & H==1])-
    mean(y[B==1 & P==1 & H==0])+mean(y[B==0 & P==1 & H==0])+
    mean(y[B==1 & P==0 & H==0])-mean(y[B==0 & P==0 & H==0]))
  stopifnot(abs(corrected-algebra) < 1e-12, abs(algebra-delta) < 1e-12)
  tibble(true_ddd = delta, algebraic_ddd = algebra, restricted_estimate = restricted, corrected_estimate = corrected)
}))
write_csv(toy_checks, "toy_contrast_checks.csv")

# FWL verifies the precise OLS weighting of the unbalanced vote-level sample.
# w_i = residual(BPH | BP, BH, country FE, resolution FE)_i / sum(residual^2).
residual_fit <- feols(brazil_post_hr ~ brazil_post_2009 + brazil_hr | iso3c + rcid, d, notes = FALSE)
z <- resid(residual_fit); weights <- z / sum(z^2)
write_csv(d |> dplyr::select(iso3c, rcid, year, issue_domain, brazil, post_2009) |>
  mutate(observation_weight = 1, fwl_residual = z, ddd_outcome_weight = weights), "ddd_implicit_weights.csv")
fwl_checks <- bind_rows(lapply(outcomes, function(outcome) {
  direct <- results |> filter(.data$outcome == .env$outcome, covariance == "country", specification == "corrected_ddd", term == "brazil_post_hr")
  weighted <- sum(weights*d[[outcome]])
  stopifnot(abs(direct$estimate-weighted) < 1e-8)
  tibble(outcome, corrected_estimate = direct$estimate, fwl_weighted_contrast = weighted,
         max_abs_orthogonality = max(abs(c(sum(z), sum(z*d$brazil_hr), sum(z*d$brazil_post_2009)))))
}))
write_csv(fwl_checks, "fwl_checks.csv")
write_csv(d |> mutate(ddd_outcome_weight = weights) |>
  summarise(sum_ddd_outcome_weight = sum(ddd_outcome_weight), n_obs = n(),
            .by = c(brazil, post_2009, human_rights_binary)), "ddd_weights_by_group_period_domain.csv")

# Estimand-matched placebos: reassign all treated-country interactions, same rows/FE.
# Every observed country is eligible, including Brazil: 95 units; no donor filtering.
units <- sort(unique(d$iso3c))
stopifnot(identical(units, sort(unique(bundle$country_placebos$placebo_unit))))
placebo_started <- proc.time()[[3]]
placebos <- bind_rows(lapply(units, function(unit) {
  pd <- d |> mutate(placebo_post = as.integer(iso3c == unit)*post_2009,
                    placebo_hr = as.integer(iso3c == unit)*human_rights_binary,
                    placebo_post_hr = placebo_post*human_rights_binary)
  bind_rows(lapply(outcomes, function(outcome) {
    fit <- feols(as.formula(paste(outcome, "~ placebo_post + placebo_hr + placebo_post_hr | iso3c + rcid")),
                 data = pd, vcov = ~iso3c, notes = FALSE)
    stopifnot(nobs(fit) == nrow(d), "placebo_post_hr" %in% names(coef(fit)))
    tidy_fit(fit, outcome, "corrected_ddd_country_placebo", "country") |>
      filter(term == "placebo_post_hr") |> mutate(placebo_unit = unit)
  }))
}))
placebo_seconds <- proc.time()[[3]]-placebo_started
placebo_summary <- bind_rows(lapply(outcomes, function(outcome) {
  p <- placebos |> filter(.data$outcome == .env$outcome)
  b <- p$estimate[p$placebo_unit == "BRA"]
  direction <- if (outcome == "distance_china_minus_usa") -1 else 1
  score <- direction*p$estimate; bscore <- direction*b; donor <- p$placebo_unit != "BRA"
  # Small tolerance treats numerical equality as a tie; all ranks are tie-inclusive.
  tol <- 1e-10
  n_ge <- sum(score >= bscore-tol); n_gt <- sum(score > bscore+tol)
  tibble(outcome, brazil_estimate = b, expected_direction = ifelse(direction == -1,"negative","positive"),
    n_placebo_units = nrow(p), n_donors = sum(donor), n_failed = 0L,
    brazil_rank_expected_direction = 1L+n_gt,
    directional_ge_count = n_ge, directional_gt_donor_count = sum(score[donor] > bscore+tol),
    ties_including_brazil = sum(abs(score-bscore) <= tol),
    randomization_p_directional = n_ge/nrow(p),
    randomization_p_directional_strict_donor = sum(score[donor] > bscore+tol)/sum(donor),
    randomization_p_two_sided = mean(abs(p$estimate) >= abs(b)-tol),
    randomization_p_two_sided_strict_donor = mean(abs(p$estimate[donor]) > abs(b)+tol),
    tie_tolerance = tol,
    interpretation = "Descriptive reassignment benchmark; causal randomization inference additionally requires exchangeability of country assignment.")
}))
for (outcome in outcomes) {
  actual <- results |> filter(.data$outcome == .env$outcome, specification == "corrected_ddd", covariance == "country", term == "brazil_post_hr")
  placebo <- placebos |> filter(.data$outcome == .env$outcome, placebo_unit == "BRA")
  stopifnot(abs(actual$estimate-placebo$estimate) < 1e-12, abs(actual$se-placebo$se) < 1e-12)
}
write_csv(placebos, "ddd_country_placebos.csv")
write_csv(placebo_summary, "ddd_country_placebo_summary.csv")
saveRDS(placebo_summary, file.path(out_dir, "ddd_country_placebo_summary.rds"), version = 3)
# Execute the DDD-only producer directly, with no targets access beyond the input read.
production <- production_ddd(bundle$vote_panel)
stopifnot(isTRUE(all.equal(production$ddd_models, compatible, tolerance = 1e-12)),
          isTRUE(all.equal(production$country_placebo_summary, placebo_summary, tolerance = 1e-12)))
saveRDS(production, file.path(out_dir, "corrected_ddd_bundle.rds"), version = 3)
print(placebo_summary)
cat("DDD placebo seconds:", placebo_seconds, "\n")
settings <- list(source = "Archived unvotes-derived vote panel in existing targets cache; no new acquisition",
  accessed_at_utc = format(Sys.time(), tz = "UTC"), years = 2005:2012,
  n_obs = nrow(d), n_countries = n_distinct(d$iso3c), n_resolutions = n_distinct(d$rcid),
  missingness = "Only originally observed yes/no/abstain votes; no imputation; original selection unchanged",
  domain = "Any human-rights issue tag -> HR; all remaining resolutions -> non-HR, mutually exclusive",
  outcome_encoding = "yes=1, abstain=0, no=-1; relative distance in [-2,2], relative agreement in [-1,1]",
  weighting = "Unweighted OLS: each observed country-resolution row has weight 1; no SDiD donor weights; exact FWL contrast weights exported",
  corrected_formula = "outcome ~ brazil_post_2009 + brazil_hr + brazil_post_hr | iso3c + rcid",
  original_formula = "outcome ~ brazil_post_2009 + brazil_post_hr | iso3c + rcid",
  lower_order_components = "country FE absorb B; resolution FE absorb P,H,PH; BP and BH explicitly controlled",
  covariance = c("~iso3c", "~iso3c + rcid"), fixest_version = as.character(packageVersion("fixest")),
  small_sample_correction = unclass(fixest::getFixest_ssc()), n_threads = 1L,
  placebo_seconds = placebo_seconds, elapsed_seconds = proc.time()[[3]]-started,
  tests = c("original point estimates/SE/p/CI/n match archived cache within 1e-10", "both DDD helpers agree",
            "same rows in every fit", "two algebraic toy contrasts", "FWL contrast equals corrected coefficient",
            "Brazil reassignment equals actual DDD", "95 of 95 placebo units estimated in each outcome",
            "DDD-only production helper matches direct fits and placebo summary"),
  implementation_status = "Executed; independent review pending", targets_store_modified = FALSE)
jsonlite::write_json(settings, file.path(out_dir, "run_metadata.json"), pretty = TRUE, auto_unbox = TRUE)
capture.output(sessionInfo(), file = file.path(out_dir, "session_info.txt"))
stopifnot(all(input_manifest$sha256[1:2] == vapply(inputs[1:2], sha, character(1))))
cat("Completed:", format(Sys.time(), tz = "UTC"), "UTC; independent review pending\n")
sink()
outputs <- list.files(out_dir, full.names = TRUE)
outputs <- outputs[basename(outputs) != "output_manifest.csv"]
write_csv(tibble(path = outputs, sha256 = vapply(outputs, sha, character(1))), "output_manifest.csv")
