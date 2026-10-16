# Public-cue cases, specifications and outcomes for the exploratory cross-country
# round of 2026-09-24 (plan, revised after the devil's-advocate review:
# quality_reports/plans/2026-09-24_public_cue_fourteen_case_round.md).
# Sourced by the staggered SDiD, pre-trend and pooled fect scripts.
#
# Cue year: calendar year of the first counted public cue; a cue published in
# December counts from the next year (South Africa: 11 December 2009 -> 2010).
# Sources in data/processed/status_cue_salience/: status_cue_country_codes*.csv,
# chile_public_cue_2007_2008_*, status_cue_country_codes_targeted.csv (Codex
# targeted search of the 15 absorbing `unknown` countries, fact-check PASS,
# 2026-09-24) and status_cue_subannual_reaudit_2026.csv (the seven earlier dates
# hold under the author's sub-annual rule; Uruguay moves to 23 May 2013, same year).

public_cue_cases <- tibble::tribble(
  ~iso3c, ~cue_year, ~salience_code, ~search_round,
  "KOR", 2003L, "high", "original",
  "AUS", 2007L, "high", "original",
  "CHL", 2007L, "high", "original",
  "BRA", 2009L, "high", "original",
  "ZAF", 2010L, "high", "original",
  "URY", 2013L, "high", "original",
  "NZL", 2013L, "high", "original",
  "JPN", 2007L, "high", "targeted_2026",
  "MYS", 2010L, "high", "targeted_2026",
  "PER", 2011L, "medium", "targeted_2026",
  "RUS", 2011L, "high", "targeted_2026",
  "TKM", 2011L, "medium", "targeted_2026",
  "SAU", 2013L, "high", "targeted_2026",
  "MMR", 2014L, "medium", "targeted_2026"
)

# Cases on the US side of China (signed distance > 0) in every pre-cue year from
# 1997; MYS, TKM, SAU and MMR are beyond China in part or all of their pre-cue
# years, where "moving toward China" has no single direction. public_cue_side_table()
# recomputes the classification.
public_cue_us_side <- c("KOR", "AUS", "CHL", "JPN", "BRA", "ZAF", "PER", "RUS", "NZL", "URY")

public_cue_spec_cases <- list(
  seven_case = public_cue_cases$iso3c[public_cue_cases$search_round == "original"],
  fourteen_case = public_cue_cases$iso3c,
  us_side_ten = public_cue_us_side
)

public_cue_spec <- function(spec_id) {
  stopifnot(spec_id %in% names(public_cue_spec_cases))
  public_cue_cases |>
    dplyr::filter(iso3c %in% public_cue_spec_cases[[spec_id]]) |>
    dplyr::select(iso3c, cue_year)
}

# Documented cue cases outside the pooled design, dropped rather than used as
# controls under full switching: Gabon and Qatar (too few post-cue years), Ukraine
# (two post-cue years, leaves the rank in 2022, war), Cameroon and Ghana (medium
# cues, intermittent status). The cases of this round that a specification does
# not treat are dropped too (rule of the original pooled script).
public_cue_other_cue_cases <- c("GAB", "QAT", "UKR", "CMR", "GHA")

public_cue_dropped <- function(spec_id) {
  sort(c(public_cue_other_cue_cases,
         setdiff(public_cue_cases$iso3c, public_cue_spec_cases[[spec_id]])))
}

# Outcomes. `abs_distance_china` is the paper's outcome, |q50 - q50 of China|
# (get_unga_data() in scripts/functions.R). `signed_distance_china` is the same
# difference with its sign, from the same raw file: positive on the US side of
# China, negative beyond China. With year effects it equals the country's own
# ideal point, so moving toward China is moving away from the US.
public_cue_outcomes <- c(abs = "abs_distance_china", signed = "signed_distance_china")

public_cue_signed_distance <- function() {
  raw <- data.table::fread(targets::tar_read(unga_file))
  d <- tibble::tibble(
    year = as.integer(raw$session + 1945L),
    iso3c = as.character(raw$iso3c),
    q50 = as.numeric(raw[["Q50%All"]])
  ) |>
    dplyr::filter(year > 1989L)
  china <- d |>
    dplyr::filter(iso3c == "CHN") |>
    dplyr::select(year, china_q50 = q50)
  stopifnot(!anyDuplicated(china$year))
  d |>
    dplyr::inner_join(china, by = "year") |>
    dplyr::transmute(iso3c, year, signed_distance_china = q50 - china_q50)
}

# Adds the signed outcome to a panel with abs_distance_china and checks that its
# absolute value reproduces the paper's outcome.
public_cue_add_signed <- function(panel) {
  out <- dplyr::left_join(panel, public_cue_signed_distance(), by = c("iso3c", "year"))
  check <- !is.na(out$abs_distance_china)
  stopifnot(!anyNA(out$signed_distance_china[check]),
            max(abs(abs(out$signed_distance_china[check]) -
                      out$abs_distance_china[check])) < 1e-10)
  out
}

# Years beyond China (signed distance < 0) before the cue (1997 to cue - 1) and
# in the seven post-cue years.
public_cue_side_table <- function(panel, cases = public_cue_cases, start = 1997L) {
  dplyr::bind_rows(lapply(seq_len(nrow(cases)), function(k) {
    s <- dplyr::filter(panel, iso3c == cases$iso3c[k], year >= start)
    pre <- s$year < cases$cue_year[k]
    post <- s$year >= cases$cue_year[k] & s$year <= cases$cue_year[k] + 6L
    tibble::tibble(
      iso3c = cases$iso3c[k], cue_year = cases$cue_year[k],
      pre_years = sum(pre), pre_years_beyond_china = sum(s$signed_distance_china[pre] < 0),
      post_years_beyond_china = sum(s$signed_distance_china[post] < 0),
      us_side_all_pre = all(s$signed_distance_china[pre] > 0)
    )
  }))
}

# ---- Sign of theta (author, 2026-09-29) ------------------------------------
# Plan: quality_reports/plans/2026-09-29_public_cue_theta_groups.md. The author
# coded the sign of theta, the leadership's net evaluation of closer ties with
# China (paper_v4.Rmd, "A simple model of public status cues"), case by case:
# aligned with the US or the liberal international order -> theta < 0; more
# independent -> theta > 0. Myanmar is left undetermined.
public_cue_theta <- tibble::tribble(
  ~iso3c, ~theta_sign, ~theta_reason,
  "KOR", -1L, "aligned with the liberal order; China displaces a historical ally (US)",
  "AUS", -1L, "aligned with the liberal order",
  "JPN", -1L, "aligned with the liberal order; China displaces a historical ally (US)",
  "NZL", -1L, "aligned with the liberal order",
  "SAU", -1L, "close US ally",
  "CHL",  1L, "more independent; not an OECD member at the 2007 cue",
  "BRA",  1L, "more independent",
  "PER",  1L, "more independent, like Brazil",
  "RUS",  1L, "close to China",
  "ZAF",  1L, "more independent, like Brazil",
  "URY",  1L, "more independent",
  "MYS",  1L, "more independent, like Brazil",
  "TKM",  1L, "little attached to the liberal order",
  "MMR", NA_integer_, "undetermined"
)
stopifnot(setequal(public_cue_theta$iso3c, public_cue_cases$iso3c))

# Magnitude prediction within theta < 0 (author, 2026-09-29, from theory, without
# looking at per-case estimates): |theta| larger for JPN, KOR and SAU than for AUS
# and NZL.
public_cue_theta_mag <- list(large = c("JPN", "KOR", "SAU"), small = c("AUS", "NZL"))

# Cases in the group contrast, by outcome family.
#   signed: US side of China in every pre-cue year (public_cue_us_side); on the
#           ideal-point axis the predicted direction is undefined beyond China.
#   votes:  pre-cue position on China-US divergent roll calls of at least 0.05
#           (0 = votes with China, 1 = with the US); ZAF, MYS and TKM sit at the
#           floor and cannot move toward China (author's threshold, 2026-09-29).
public_cue_theta_groups <- list(
  signed = list(neg = c("KOR", "AUS", "JPN", "NZL"),
                pos = c("CHL", "BRA", "PER", "RUS", "ZAF", "URY")),
  votes = list(neg = c("KOR", "AUS", "JPN", "NZL", "SAU"),
               pos = c("CHL", "BRA", "PER", "RUS", "URY"))
)
local({
  sign_of <- stats::setNames(public_cue_theta$theta_sign, public_cue_theta$iso3c)
  for (g in public_cue_theta_groups) {
    stopifnot(all(sign_of[g$neg] == -1L), all(sign_of[g$pos] == 1L),
              !anyDuplicated(c(g$neg, g$pos)))
  }
  stopifnot(setequal(unlist(public_cue_theta_groups$signed), public_cue_us_side))
})
