bc_unvotes_load_tables <- function(raw_tarball) {
  if (!file.exists(raw_tarball)) {
    stop("Missing raw unvotes tarball: ", raw_tarball)
  }
  if (file.info(raw_tarball)$size <= 0) {
    stop("Raw unvotes tarball exists but is empty: ", raw_tarball)
  }

  tmp_dir <- tempfile("unvotes_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  utils::untar(raw_tarball, exdir = tmp_dir, tar = "internal")

  load_unvotes_data <- function(name) {
    env <- new.env(parent = emptyenv())
    load(file.path(tmp_dir, "unvotes", "data", paste0(name, ".rda")), envir = env)
    env[[name]]
  }

  list(
    un_votes = load_unvotes_data("un_votes"),
    un_roll_calls = load_unvotes_data("un_roll_calls"),
    un_roll_call_issues = load_unvotes_data("un_roll_call_issues")
  )
}

bc_unvotes_clean_text <- function(x) {
  x |>
    iconv(from = "", to = "UTF-8", sub = "") |>
    stringr::str_replace_all("\u00a0", " ") |>
    stringr::str_replace_all("\u00c2", "") |>
    stringr::str_squish()
}

bc_unvotes_map_issue_family <- function(issue) {
  dplyr::case_when(
    is.na(issue) | issue == "" ~ "Other / uncoded",
    stringr::str_detect(issue, "Human rights") ~ "Human rights",
    stringr::str_detect(issue, "Arms control|Nuclear weapons|disarmament") ~
      "Arms/disarmament/nuclear",
    stringr::str_detect(issue, "Palestinian conflict") ~
      "Palestine/Middle East",
    stringr::str_detect(issue, "Economic development") ~
      "Economic development",
    stringr::str_detect(issue, "Colonialism") ~ "Decolonization",
    TRUE ~ "Other / uncoded"
  )
}

bc_unvotes_similarity_score <- function(vote_brazil, vote_china) {
  dplyr::case_when(
    vote_brazil == vote_china ~ 1,
    vote_brazil == "abstain" & vote_china %in% c("yes", "no") ~ 0.5,
    vote_china == "abstain" & vote_brazil %in% c("yes", "no") ~ 0.5,
    TRUE ~ 0
  )
}

build_brazil_china_unvotes_resolution_data <- function(raw_tarball, years = 2005:2012) {
  tables <- bc_unvotes_load_tables(raw_tarball)

  un_votes <- tables$un_votes |>
    dplyr::mutate(vote = as.character(vote))
  un_roll_calls <- tables$un_roll_calls
  un_roll_call_issues <- tables$un_roll_call_issues |>
    dplyr::mutate(issue = as.character(issue))

  issue_long <- un_roll_call_issues |>
    dplyr::mutate(
      issue_raw = bc_unvotes_clean_text(issue),
      issue_family = bc_unvotes_map_issue_family(issue_raw)
    ) |>
    dplyr::select(rcid, issue_raw, issue_family) |>
    dplyr::distinct()

  core_votes <- un_votes |>
    dplyr::filter(country_code %in% c("BR", "CN")) |>
    dplyr::select(rcid, country_code, vote) |>
    tidyr::pivot_wider(
      names_from = country_code,
      values_from = vote,
      names_prefix = "vote_"
    )

  resolution_votes <- core_votes |>
    dplyr::inner_join(un_roll_calls, by = "rcid") |>
    dplyr::mutate(
      year = lubridate::year(date),
      vote_brazil = as.character(vote_BR),
      vote_china = as.character(vote_CN)
    ) |>
    dplyr::filter(
      year %in% years,
      !is.na(vote_brazil),
      !is.na(vote_china),
      vote_brazil != "absent",
      vote_china != "absent"
    ) |>
    dplyr::mutate(
      identical_vote = vote_brazil == vote_china,
      similarity_score = bc_unvotes_similarity_score(vote_brazil, vote_china)
    ) |>
    dplyr::select(
      rcid,
      year,
      date,
      vote_brazil,
      vote_china,
      identical_vote,
      similarity_score
    )

  if (anyDuplicated(resolution_votes$rcid) > 0) {
    stop("Duplicate rcid values in Brazil-China resolution vote data.")
  }
  if (!all(resolution_votes$similarity_score %in% c(0, 0.5, 1))) {
    stop("Unexpected similarity score outside {0, 0.5, 1}.")
  }

  resolution_votes |>
    dplyr::left_join(issue_long, by = "rcid") |>
    dplyr::mutate(
      issue_raw = tidyr::replace_na(issue_raw, "Uncoded"),
      issue_family = tidyr::replace_na(issue_family, "Other / uncoded")
    ) |>
    dplyr::distinct(rcid, issue_family, .keep_all = TRUE) |>
    dplyr::arrange(year, rcid, issue_family)
}

summarise_brazil_china_unvotes_similarity_by_year <- function(resolution_data) {
  year_summary <- resolution_data |>
    dplyr::distinct(
      rcid,
      year,
      vote_brazil,
      vote_china,
      identical_vote,
      similarity_score
    ) |>
    dplyr::summarise(
      n_resolutions = dplyr::n(),
      identical_votes_n = sum(identical_vote, na.rm = TRUE),
      identical_votes_percent = 100 * mean(identical_vote, na.rm = TRUE),
      mean_similarity_score = mean(similarity_score, na.rm = TRUE),
      .by = year
    ) |>
    dplyr::arrange(year)

  expected_years <- 2005:2012
  if (!identical(as.integer(year_summary$year), expected_years)) {
    stop("Expected yearly summary for 2005-2012.")
  }
  if (any(year_summary$identical_votes_percent < 0 | year_summary$identical_votes_percent > 100)) {
    stop("Identical vote percentages outside [0, 100].")
  }

  year_summary
}

summarise_brazil_china_unvotes_similarity_by_issue_year <- function(resolution_data) {
  issue_year <- resolution_data |>
    dplyr::summarise(
      n_resolutions = dplyr::n_distinct(rcid),
      identical_votes_n = sum(identical_vote, na.rm = TRUE),
      identical_votes_percent = 100 * mean(identical_vote, na.rm = TRUE),
      mean_similarity_score = mean(similarity_score, na.rm = TRUE),
      .by = c(issue_family, year)
    ) |>
    dplyr::mutate(
      period_fit = dplyr::case_when(
        year <= 2008 ~ "2005-2008",
        year >= 2009 ~ "2009-2012",
        TRUE ~ NA_character_
      ),
      issue_family = factor(
        issue_family,
        levels = c(
          "Human rights",
          "Arms/disarmament/nuclear",
          "Economic development",
          "Decolonization",
          "Palestine/Middle East",
          "Other / uncoded"
        )
      )
    ) |>
    dplyr::arrange(issue_family, year)

  if (any(issue_year$identical_votes_percent < 0 | issue_year$identical_votes_percent > 100)) {
    stop("Issue-year identical vote percentages outside [0, 100].")
  }

  issue_year
}

plot_brazil_china_unvotes_similarity_by_issue_year <- function(issue_year_data) {
  ggplot2::ggplot(
    issue_year_data,
    ggplot2::aes(x = year, y = identical_votes_percent)
  ) +
    ggplot2::geom_vline(xintercept = 2008.5, color = "gray55", linewidth = 0.35) +
    ggplot2::geom_point(color = "#1F4E79", size = 2.5, alpha = 0.9) +
    ggplot2::geom_smooth(
      ggplot2::aes(group = period_fit),
      method = "loess",
      formula = y ~ x,
      method.args = list(degree = 1),
      span = 1,
      se = FALSE,
      color = "#B2182B",
      linewidth = 0.9,
      na.rm = TRUE
    ) +
    ggplot2::facet_wrap(~issue_family, ncol = 2) +
    ggplot2::scale_x_continuous(breaks = 2005:2012) +
    ggplot2::scale_y_continuous(
      limits = c(50, 100),
      breaks = seq(50, 100, 10),
      labels = function(x) paste0(x, "%")
    ) +
    ggplot2::labs(
      x = "Year",
      y = "Resolutions with identical Brazil-China votes (%)"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold")
    )
}
