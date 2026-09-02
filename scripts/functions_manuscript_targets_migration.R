# Functions used only to connect already-defined analytical targets to the
# manuscript. They do not estimate models or access the network.

assert_manuscript_target_columns <- function(data, required, object_name) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop(
      object_name,
      " is missing required column(s): ",
      paste(missing, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

build_full_union_country_audit_candidate <- function(
    treatment_unit_summary,
    period_summary,
    min_entry_year = 2000L) {
  unit_required <- c(
    "min_duration_years", "iso3c", "country_name", "trade_rank_years",
    "ever_china_top_observed"
  )
  period_required <- c(
    "min_duration_years", "iso3c", "period_entry_year", "duration_years",
    "prior_china_top_status", "eligible_entry", "qualifies_min_duration"
  )
  assert_manuscript_target_columns(
    treatment_unit_summary,
    unit_required,
    "treatment_unit_summary"
  )
  assert_manuscript_target_columns(
    period_summary,
    period_required,
    "period_summary"
  )
  if (length(min_entry_year) != 1L || is.na(min_entry_year) ||
      min_entry_year < 1990L) {
    stop("min_entry_year must be one valid scalar year.", call. = FALSE)
  }
  if (anyDuplicated(
    treatment_unit_summary[c("min_duration_years", "iso3c")]
  )) {
    stop(
      "treatment_unit_summary has duplicate duration-country keys.",
      call. = FALSE
    )
  }
  if (anyNA(treatment_unit_summary$iso3c) ||
      any(treatment_unit_summary$iso3c == "")) {
    stop("treatment_unit_summary has missing country keys.", call. = FALSE)
  }

  period_counts <- period_summary |>
    dplyr::mutate(
      short_eligible_period = eligible_entry & !qualifies_min_duration,
      pre_min_entry_period = period_entry_year < min_entry_year,
      no_clean_prior_period = period_entry_year >= min_entry_year &
        !(prior_china_top_status %in% 0L)
    ) |>
    dplyr::group_by(min_duration_years, iso3c) |>
    dplyr::summarise(
      n_observed_china_top_periods = dplyr::n(),
      n_qualifying_periods = sum(qualifies_min_duration, na.rm = TRUE),
      n_short_eligible_periods = sum(short_eligible_period, na.rm = TRUE),
      n_pre_min_entry_periods = sum(pre_min_entry_period, na.rm = TRUE),
      n_no_clean_prior_periods = sum(no_clean_prior_period, na.rm = TRUE),
      longest_observed_china_top_period = max(duration_years, na.rm = TRUE),
      .groups = "drop"
    )

  audit <- treatment_unit_summary |>
    dplyr::select(dplyr::all_of(unit_required)) |>
    dplyr::left_join(
      period_counts,
      by = c("min_duration_years", "iso3c"),
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      dplyr::across(
        c(
          n_observed_china_top_periods,
          n_qualifying_periods,
          n_short_eligible_periods,
          n_pre_min_entry_periods,
          n_no_clean_prior_periods,
          longest_observed_china_top_period
        ),
        ~ dplyr::coalesce(.x, 0L)
      ),
      audit_role = dplyr::case_when(
        n_qualifying_periods > 0L ~ "treated_qualifying",
        trade_rank_years == 0L ~ "excluded_no_observed_trade_rank",
        !ever_china_top_observed ~ "never_china_top_control",
        n_pre_min_entry_periods > 0L &
          n_short_eligible_periods == 0L &
          n_no_clean_prior_periods == 0L ~ "excluded_pre_2000",
        n_no_clean_prior_periods > 0L &
          n_short_eligible_periods == 0L ~ "excluded_no_clean_prior",
        n_short_eligible_periods > 0L ~ "excluded_short_duration",
        TRUE ~ "excluded_other_nonqualifying"
      ),
      .before = iso3c
    ) |>
    dplyr::arrange(min_duration_years, audit_role, iso3c)

  if (anyNA(audit$audit_role)) {
    stop("The full-union country audit has unclassified units.", call. = FALSE)
  }
  if (any(audit$n_qualifying_periods > 0L &
          audit$audit_role != "treated_qualifying")) {
    stop("A qualifying treated unit was misclassified.", call. = FALSE)
  }
  audit
}

publish_manuscript_file_set_transactionally <- function(
    staged,
    outputs,
    move_file = file.rename,
    copy_file = file.copy,
    remove_file = function(path) unlink(path, force = TRUE)) {
  if (!is.character(staged) || !is.character(outputs) ||
      !is.function(move_file) || !is.function(copy_file) ||
      !is.function(remove_file)) {
    stop("Paths must be character vectors and filesystem operations functions.",
         call. = FALSE)
  }
  if (length(staged) == 0L || length(staged) != length(outputs) ||
      anyNA(staged) || anyNA(outputs) || any(staged == "") ||
      any(outputs == "")) {
    stop("Staged and final paths must form a nonempty one-to-one file set.",
         call. = FALSE)
  }

  path_is_link <- function(paths) {
    links <- Sys.readlink(paths)
    !is.na(links) & nzchar(links)
  }
  path_exists_or_link <- function(paths) {
    file.exists(paths) | path_is_link(paths)
  }
  path_identity <- function(paths) {
    parents <- dirname(paths)
    if (any(!dir.exists(parents))) {
      stop("Every artifact parent directory must already exist.",
           call. = FALSE)
    }
    file.path(
      normalizePath(parents, winslash = "/", mustWork = TRUE),
      basename(paths)
    )
  }
  staged_identity <- path_identity(staged)
  output_identity <- path_identity(outputs)
  if (anyDuplicated(staged_identity) || anyDuplicated(output_identity) ||
      length(intersect(staged_identity, output_identity)) > 0L) {
    stop(
      "Staged and final paths must remain distinct after path normalization.",
      call. = FALSE
    )
  }

  staged_info <- fs::file_info(staged)
  staged_types <- as.character(staged_info$type)
  if (any(!file.exists(staged)) || anyNA(staged_types) ||
      any(staged_types != "file") ||
      any(path_is_link(staged)) ||
      anyNA(staged_info$size) || any(staged_info$size <= 0L)) {
    stop("Every staged artifact must be a nonempty regular file.",
         call. = FALSE)
  }

  output_exists <- path_exists_or_link(outputs)
  output_info <- fs::file_info(outputs)
  output_types <- as.character(output_info$type)
  if (any(path_is_link(outputs)) ||
      any(output_exists &
          (is.na(output_types) | output_types != "file"))) {
    stop("Existing final artifact paths must be regular files, not ",
         "directories, symbolic links, or special files.",
         call. = FALSE)
  }

  staged_size <- staged_info$size
  staged_md5 <- unname(tools::md5sum(staged))
  if (anyNA(staged_md5)) {
    stop("Could not hash every staged artifact.", call. = FALSE)
  }
  backups <- rep(NA_character_, length(outputs))
  preserve_backups <- FALSE
  backups_cleaned <- FALSE
  remove_paths_checked <- function(paths) {
    paths <- paths[!is.na(paths)]
    if (length(paths) == 0L) return(TRUE)
    status <- vapply(
      paths,
      function(path) {
        if (!path_exists_or_link(path)) return(0L)
        result <- tryCatch(remove_file(path), error = function(error) 1L)
        if (length(result) != 1L || is.na(result)) return(1L)
        as.integer(result)
      },
      integer(1)
    )
    all(status == 0L) && !any(path_exists_or_link(paths))
  }
  on.exit({
    if (!preserve_backups && !backups_cleaned) {
      invisible(remove_paths_checked(backups))
    }
  }, add = TRUE)

  backup_error <- tryCatch(
    {
      for (index in which(output_exists)) {
        backups[[index]] <- tempfile(
          "manuscript-artifact-backup-",
          tmpdir = dirname(outputs[[index]]),
          fileext = paste0(".", tools::file_ext(outputs[[index]]))
        )
        copied <- copy_file(
          outputs[[index]],
          backups[[index]],
          overwrite = FALSE,
          copy.mode = TRUE,
          copy.date = TRUE
        )
        backup_type <- as.character(fs::file_info(backups[[index]])$type)
        if (!isTRUE(copied) || !file.exists(backups[[index]]) ||
            is.na(backup_type) || backup_type != "file" ||
            unname(tools::md5sum(backups[[index]])) !=
              unname(tools::md5sum(outputs[[index]]))) {
          stop("Could not create a verified backup before publishing artifacts.",
               call. = FALSE)
        }
      }
      NULL
    },
    error = identity
  )
  if (inherits(backup_error, "error")) {
    backups_cleaned <- remove_paths_checked(backups)
    if (!backups_cleaned) {
      preserve_backups <- TRUE
      residual_backups <- backups[
        !is.na(backups) & path_exists_or_link(backups)
      ]
      stop(
        conditionMessage(backup_error),
        " Backup setup cleanup also failed; preserved at: ",
        paste(residual_backups, collapse = ", "),
        call. = FALSE
      )
    }
    stop(conditionMessage(backup_error), call. = FALSE)
  }

  publish_error <- tryCatch(
    {
      for (index in seq_along(outputs)) {
        moved <- move_file(staged[[index]], outputs[[index]])
        if (!isTRUE(moved)) {
          stop("Could not atomically publish artifact ", index, ".",
               call. = FALSE)
        }
        published_info <- fs::file_info(outputs[[index]])
        published_type <- as.character(published_info$type)
        if (!file.exists(outputs[[index]]) ||
            is.na(published_type) || published_type != "file" ||
            path_is_link(outputs[[index]]) ||
            is.na(published_info$size) ||
            published_info$size != staged_size[[index]] ||
            unname(tools::md5sum(outputs[[index]])) != staged_md5[[index]]) {
          stop("Published artifact ", index,
               " does not match its staged file.", call. = FALSE)
        }
      }
      NULL
    },
    error = identity
  )

  if (inherits(publish_error, "error")) {
    rollback_ok <- logical(length(outputs))
    for (index in seq_along(outputs)) {
      if (output_exists[[index]]) {
        if (file.exists(outputs[[index]]) &&
            identical(
              as.character(fs::file_info(outputs[[index]])$type),
              "file"
            )) {
          remove_file(outputs[[index]])
        }
        restored <- !file.exists(outputs[[index]]) &&
          isTRUE(copy_file(backups[[index]], outputs[[index]],
                           overwrite = FALSE, copy.mode = TRUE,
                           copy.date = TRUE))
        rollback_ok[[index]] <- restored &&
          file.exists(outputs[[index]]) &&
          identical(
            as.character(fs::file_info(outputs[[index]])$type),
            "file"
          ) &&
          unname(tools::md5sum(outputs[[index]])) ==
            unname(tools::md5sum(backups[[index]]))
      } else {
        if (path_exists_or_link(outputs[[index]]) &&
            !identical(
              as.character(fs::file_info(outputs[[index]])$type),
              "directory"
            )) {
          remove_file(outputs[[index]])
        }
        rollback_ok[[index]] <- !path_exists_or_link(outputs[[index]])
      }
    }
    if (!all(rollback_ok)) {
      preserve_backups <- TRUE
      stop(
        conditionMessage(publish_error),
        " Rollback also failed; preserved backups at: ",
        paste(backups[!is.na(backups)], collapse = ", "),
        call. = FALSE
      )
    }
    backups_cleaned <- remove_paths_checked(backups)
    if (!backups_cleaned) {
      preserve_backups <- TRUE
      stop(
        conditionMessage(publish_error),
        " Rollback succeeded, but backup cleanup failed; preserved at: ",
        paste(backups[!is.na(backups)], collapse = ", "),
        call. = FALSE
      )
    }
    stop(conditionMessage(publish_error),
         " All final paths were rolled back.", call. = FALSE)
  }

  backups_cleaned <- remove_paths_checked(backups)
  if (!backups_cleaned) {
    preserve_backups <- TRUE
    stop(
      "Artifacts were published, but verified backup cleanup failed; ",
      "preserved at: ",
      paste(backups[!is.na(backups)], collapse = ", "),
      call. = FALSE
    )
  }
  outputs
}

run_brazil_sdid_dose_response_panel_candidate <- function(
    script_path,
    donor_path,
    summary_path,
    output_pdf,
    output_png) {
  inputs <- c(script_path, donor_path, summary_path)
  if (any(!file.exists(inputs)) || any(file.info(inputs)$isdir)) {
    stop("Dose-response panel inputs must be existing regular files.",
         call. = FALSE)
  }
  outputs <- c(output_pdf, output_png)
  if (anyNA(outputs) || any(outputs == "") || anyDuplicated(outputs)) {
    stop("Dose-response panel outputs must be two distinct paths.",
         call. = FALSE)
  }
  if (!identical(tolower(tools::file_ext(outputs)), c("pdf", "png"))) {
    stop("Dose-response panel outputs must be ordered PDF then PNG.",
         call. = FALSE)
  }
  invisible(lapply(unique(dirname(outputs)), dir.create,
                   recursive = TRUE, showWarnings = FALSE))

  staged <- c(
    tempfile("dose-response-panel-", tmpdir = dirname(output_pdf),
             fileext = ".pdf"),
    tempfile("dose-response-panel-", tmpdir = dirname(output_png),
             fileext = ".png")
  )
  on.exit(unlink(staged, force = TRUE), add = TRUE)

  command <- file.path(R.home("bin"), "Rscript")
  command_output <- suppressWarnings(system2(
    command,
    args = c(
      "--vanilla",
      shQuote(script_path),
      shQuote(donor_path),
      shQuote(summary_path),
      shQuote(staged[[1L]]),
      shQuote(staged[[2L]])
    ),
    stdout = TRUE,
    stderr = TRUE
  ))
  status <- attr(command_output, "status")
  if (is.null(status)) status <- 0L
  if (!identical(as.integer(status), 0L)) {
    stop(
      "Dose-response panel script failed with status ",
      status,
      if (length(command_output) > 0L) {
        paste0(": ", paste(utils::tail(command_output, 20L), collapse = "\n"))
      } else {
        "."
      },
      call. = FALSE
    )
  }
  publish_manuscript_file_set_transactionally(staged, outputs)
}

write_cross_country_dynamic_with_pooled_att_candidate <- function(
    dynamic_results,
    model_results,
    output_path,
    min_duration_years = 5L,
    specification = "risk_set_restricted",
    display_min = -12L,
    display_max = 15L) {
  required_dynamic <- c(
    "min_duration_years", "specification", "event_time", "count",
    "att", "se", "ci_lo", "ci_hi"
  )
  required_model <- c(
    "min_duration_years", "specification", "att", "ci_lo", "ci_hi",
    "n_treated_country_years"
  )
  assert_manuscript_target_columns(
    dynamic_results,
    required_dynamic,
    "dynamic_results"
  )
  assert_manuscript_target_columns(
    model_results,
    required_model,
    "model_results"
  )
  if (length(output_path) != 1L || is.na(output_path) || output_path == "" ||
      tolower(tools::file_ext(output_path)) != "png") {
    stop("The cross-country figure output must be one PNG path.",
         call. = FALSE)
  }
  if (display_min >= display_max) {
    stop("display_min must be smaller than display_max.", call. = FALSE)
  }

  dynamic_main <- dynamic_results |>
    dplyr::filter(
      .data$min_duration_years == .env$min_duration_years,
      .data$specification == .env$specification
    ) |>
    dplyr::arrange(event_time)
  model_main <- model_results |>
    dplyr::filter(
      .data$min_duration_years == .env$min_duration_years,
      .data$specification == .env$specification
    )

  if (nrow(model_main) != 1L || nrow(dynamic_main) == 0L) {
    stop("The preferred cross-country specification is not unique and complete.",
         call. = FALSE)
  }
  if (anyDuplicated(dynamic_main$event_time)) {
    stop("Event times are duplicated in the preferred specification.",
         call. = FALSE)
  }
  dynamic_numeric <- dynamic_main |>
    dplyr::select(event_time, count, att, se, ci_lo, ci_hi)
  if (any(!vapply(dynamic_numeric, is.numeric, logical(1))) ||
      any(!is.finite(as.matrix(dynamic_numeric))) ||
      any(dynamic_main$count <= 0L) ||
      any(dynamic_main$ci_lo > dynamic_main$ci_hi)) {
    stop("Dynamic estimates contain invalid values, counts, or intervals.",
         call. = FALSE)
  }
  model_numeric <- model_main |>
    dplyr::select(att, ci_lo, ci_hi, n_treated_country_years)
  if (any(!vapply(model_numeric, is.numeric, logical(1))) ||
      any(!is.finite(as.matrix(model_numeric))) ||
      model_main$n_treated_country_years[[1L]] <= 0L ||
      model_main$ci_lo[[1L]] > model_main$ci_hi[[1L]]) {
    stop("The pooled model row contains invalid values or intervals.",
         call. = FALSE)
  }

  post_all <- dynamic_main |>
    dplyr::filter(event_time >= 1L)
  if (nrow(post_all) == 0L) {
    stop("No post-entry dynamic estimates are available.", call. = FALSE)
  }
  pooled_from_dynamic <- stats::weighted.mean(post_all$att, post_all$count)
  if (!isTRUE(all.equal(
    sum(post_all$count),
    model_main$n_treated_country_years[[1L]],
    tolerance = 0
  ))) {
    stop("Dynamic counts do not match the pooled ATT denominator.",
         call. = FALSE)
  }
  if (!isTRUE(all.equal(
    pooled_from_dynamic,
    model_main$att[[1L]],
    tolerance = 1e-10
  ))) {
    stop("The event-time weighted mean does not reproduce the pooled ATT.",
         call. = FALSE)
  }

  plot_data <- dynamic_main |>
    dplyr::filter(
      event_time >= display_min,
      event_time <= display_max
    ) |>
    dplyr::mutate(
      period = dplyr::if_else(
        event_time >= 1L,
        "Post-entry effect",
        "Pre-entry diagnostic"
      )
    )
  if (nrow(plot_data) == 0L) {
    stop("No dynamic estimates fall inside the requested display window.",
         call. = FALSE)
  }
  support_labels <- plot_data |>
    dplyr::filter(event_time %in% c(1L, 5L, 10L, 15L)) |>
    dplyr::mutate(label = paste0("N=", count)) |>
    dplyr::select(event_time, label)
  pooled_label <- sprintf(
    "Pooled ATT = %.3f\n95%% CI [%.3f, %.3f]",
    model_main$att[[1L]],
    model_main$ci_lo[[1L]],
    model_main$ci_hi[[1L]]
  )

  figure <- ggplot2::ggplot() +
    ggplot2::annotate(
      "rect",
      xmin = 0.5,
      xmax = display_max + 0.5,
      ymin = model_main$ci_lo[[1L]],
      ymax = model_main$ci_hi[[1L]],
      fill = "#E69F00",
      alpha = 0.16
    ) +
    ggplot2::geom_hline(
      yintercept = 0,
      linewidth = 0.35,
      linetype = "dashed",
      color = "grey45"
    ) +
    ggplot2::geom_vline(
      xintercept = 0.5,
      linewidth = 0.45,
      color = "grey35"
    ) +
    ggplot2::geom_errorbar(
      data = plot_data,
      ggplot2::aes(
        x = event_time,
        ymin = ci_lo,
        ymax = ci_hi,
        color = period
      ),
      width = 0,
      linewidth = 0.45,
      alpha = 0.82
    ) +
    ggplot2::geom_line(
      data = plot_data,
      ggplot2::aes(x = event_time, y = att, color = period, group = period),
      linewidth = 0.65
    ) +
    ggplot2::geom_point(
      data = plot_data,
      ggplot2::aes(x = event_time, y = att, color = period),
      size = 1.9
    ) +
    ggplot2::annotate(
      "segment",
      x = 0.5,
      xend = display_max + 0.5,
      y = model_main$att[[1L]],
      yend = model_main$att[[1L]],
      color = "#B45F06",
      linewidth = 0.75,
      linetype = "longdash"
    ) +
    ggplot2::annotate(
      "label",
      x = 3.9,
      y = -0.225,
      label = pooled_label,
      color = "#8C4A00",
      fill = "white",
      linewidth = 0.2,
      size = 3.0,
      hjust = 0
    ) +
    ggplot2::geom_text(
      data = support_labels,
      ggplot2::aes(x = event_time, y = 0.155, label = label),
      inherit.aes = FALSE,
      color = "grey35",
      size = 2.7
    ) +
    ggplot2::annotate(
      "text",
      x = 0.75,
      y = 0.185,
      label = "Treatment begins at +1",
      hjust = 0,
      color = "grey25",
      size = 3.0
    ) +
    ggplot2::scale_color_manual(
      values = c(
        "Pre-entry diagnostic" = "#7A7A7A",
        "Post-entry effect" = "#1F4E79"
      ),
      breaks = c("Pre-entry diagnostic", "Post-entry effect"),
      name = NULL
    ) +
    ggplot2::scale_x_continuous(
      breaks = seq(-10L, 15L, by = 5L),
      limits = c(display_min - 0.5, display_max + 0.5)
    ) +
    ggplot2::coord_cartesian(ylim = c(-0.38, 0.21), clip = "off") +
    ggplot2::labs(
      title = "Dynamic effects and the pooled post-entry ATT",
      subtitle = paste0(
        "Durable China top-export status; restricted-risk-set IFE specification"
      ),
      x = "Periods relative to entry as the top goods-export destination",
      y = "Effect on UNGA ideal-point distance to China",
      caption = paste(
        paste0(
          "Points and vertical bars: event-time estimates and pointwise ",
          "95% bootstrap CIs."
        ),
        sprintf(
          paste0(
            "Orange band and dashed line: pooled ATT and its 95%% CI over ",
            "all %d treated country-years (h=+1 to +20)."
          ),
          model_main$n_treated_country_years[[1L]]
        ),
        paste0(
          "This is a pooled average, not a cumulative sum. Display: ",
          "h=-12 to +15."
        ),
        paste0(
          "N labels show contributing treated countries at selected ",
          "post-entry horizons."
        ),
        sep = "\n"
      )
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "bottom",
      legend.justification = "left",
      plot.title = ggplot2::element_text(face = "bold", size = 13),
      plot.subtitle = ggplot2::element_text(color = "grey30", size = 10.5),
      plot.caption = ggplot2::element_text(
        color = "grey35",
        size = 8.2,
        hjust = 0,
        margin = ggplot2::margin(t = 8)
      ),
      plot.margin = ggplot2::margin(8, 12, 8, 8)
    )

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    filename = output_path,
    plot = figure,
    width = 7,
    height = 5.4,
    units = "in",
    dpi = 300,
    bg = "white"
  )
  output_info <- file.info(output_path)
  if (is.na(output_info$size) || output_info$size <= 0L) {
    stop("The cross-country dynamic figure was not written or is empty.",
         call. = FALSE)
  }
  output_path
}
