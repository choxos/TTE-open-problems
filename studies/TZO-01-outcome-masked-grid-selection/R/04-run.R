## Study TZO-01: run the finite-sample design.
##
## Usage: Rscript R/03-truth.R
##        Rscript R/04-run.R
##        Rscript R/04-run.R 1:12
##
## The optional slice addresses published cells. The harness caches the coupled
## process blocks, so selecting any cell runs its process block once.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))

OUTDIR <- here('results')
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUTDIR, 'truth.rds')))

method_template <- function() {
  fixed <- do.call(rbind, lapply(
    c('panel', 'panel-cap20', 'panel-p0199', 'panel-oracle'),
    function(method) data.frame(method = method, grid = GRIDS)
  ))
  rbind(
    fixed,
    data.frame(
      method = c('selected', 'one-week-4000', 'one-week-5000', 'full-history'),
      grid = c(NA_integer_, 1L, 1L, 1L)
    )
  )
}

blank_result <- function(scen, rep_id, why) {
  specifications <- method_template()
  g <- expand.grid(
    profile = OUTCOME_PROFILES,
    G = GRACES,
    specification = seq_len(nrow(specifications)),
    stringsAsFactors = FALSE
  )
  g$method <- specifications$method[g$specification]
  g$grid <- specifications$grid[g$specification]
  g$specification <- NULL
  g$cell <- mapply(function(profile, G) cell_number(scen, profile, G), g$profile, g$G)
  g$rep_id <- rep_id
  numeric_names <- c(
    'est', 'se', 'lo', 'hi', 'risk_early', 'risk_delay',
    'outcome_first', 'treatment_first', 'max_weight_early',
    'max_weight_delay', 'cv_weight_early', 'cv_weight_delay',
    'ess_early', 'ess_delay', 'condition', 'nuisance_p', 'person_periods',
    'peak_memory_mb', 'estimator_time', 'selection_time', 'total_worker_time',
    'serialization_bytes', 'alias_multiple', 'alias_multiple_upper',
    'alias_marker_treatment', 'alias_marker_treatment_upper', 'cv_logloss',
    'calibration_error', 'predicted_ess_early', 'predicted_ess_delay',
    'selected_grid', 'design_starts', 'design_visits'
  )
  for (name in numeric_names) g[[name]] <- NA_real_
  g$selector_support <- NA
  g$selector_pass <- NA
  g$fail <- why
  g
}

estimator_row <- function(scen, rep_id, profile, G, method, grid, result,
                          selector, process_diag, total_worker_time) {
  row <- blank_result(scen, rep_id, NA_character_)[1L, , drop = FALSE]
  row$profile <- profile
  row$G <- G
  row$method <- method
  row$grid <- grid
  row$cell <- cell_number(scen, profile, G)
  row$rep_id <- rep_id
  row$fail <- result$fail %||% NA_character_
  fields <- c(
    est = 'est', se = 'se', lo = 'lo', hi = 'hi',
    risk_early = 'risk_early', risk_delay = 'risk_delay',
    outcome_first = 'outcome_first', treatment_first = 'treatment_first',
    max_weight_early = 'max_weight_early', max_weight_delay = 'max_weight_delay',
    cv_weight_early = 'cv_weight_early', cv_weight_delay = 'cv_weight_delay',
    ess_early = 'ess_early', ess_delay = 'ess_delay', condition = 'condition',
    nuisance_p = 'nuisance_p', person_periods = 'rows',
    peak_memory_mb = 'memory_mb', estimator_time = 'elapsed'
  )
  for (name in names(fields)) {
    value <- result[[fields[[name]]]]
    if (!is.null(value)) row[[name]] <- value
  }
  row$selection_time <- selector$elapsed
  row$total_worker_time <- total_worker_time
  row$selected_grid <- selector$selected
  row$selector_support <- selector$support
  row$design_starts <- selector$starts
  row$design_visits <- selector$visits
  if (!is.null(process_diag) && nrow(process_diag)) {
    row$alias_multiple <- process_diag$alias_multiple
    row$alias_multiple_upper <- process_diag$alias_multiple_upper
    row$alias_marker_treatment <- process_diag$alias_marker_treatment
    row$alias_marker_treatment_upper <- process_diag$alias_marker_treatment_upper
    row$cv_logloss <- process_diag$cv_logloss
    row$calibration_error <- process_diag$calibration_error
    row$predicted_ess_early <- process_diag$ess_early
    row$predicted_ess_delay <- process_diag$ess_delay
    row$selector_pass <- process_diag$passes
  }
  row
}

one_rep <- function(scen, rep_id) {
  ## No seed is set here. run_design owns this replicate's random stream.
  started <- proc.time()[['elapsed']]
  design_started <- proc.time()[['elapsed']]
  design <- tryCatch(gen_process(scen, N_DESIGN), error = function(e) NULL)
  design_time <- proc.time()[['elapsed']] - design_started
  if (is.null(design)) return(blank_result(scen, rep_id, 'design-dgm-failed'))

  ## Critique fix: both grace protocols lock an outcome-masked process selector
  ## before any outcome is generated for the design sample.
  selectors <- lapply(GRACES, function(G)
    tryCatch(selector_for(design, G), error = function(e) NULL))
  names(selectors) <- as.character(GRACES)
  for (G in GRACES) {
    if (is.null(selectors[[as.character(G)]])) {
      selectors[[as.character(G)]] <- list(
        G = G, selected = 1L, support = FALSE, fail = 'selector-failed',
        starts = sum(is.finite(design$natural_start)), visits = sum(design$visits),
        table = data.frame(), elapsed = NA_real_
      )
    }
  }

  analysis_started <- proc.time()[['elapsed']]
  analysis <- tryCatch(gen_process(scen, N_ANALYSIS), error = function(e) NULL)
  analysis_process_time <- proc.time()[['elapsed']] - analysis_started
  if (is.null(analysis)) return(blank_result(scen, rep_id, 'analysis-dgm-failed'))

  outcome_started <- proc.time()[['elapsed']]
  analysis_outcome <- tryCatch(gen_outcomes(analysis), error = function(e) NULL)
  analysis_outcome_time <- proc.time()[['elapsed']] - outcome_started
  if (is.null(analysis_outcome)) return(blank_result(scen, rep_id, 'outcome-dgm-failed'))

  ## Critique fix: design-sample outcomes are generated only after both grids
  ## have been locked. They are then used solely by the 5000-person comparator.
  design_outcome_started <- proc.time()[['elapsed']]
  design_outcome <- tryCatch(gen_outcomes(design), error = function(e) NULL)
  design_outcome_time <- proc.time()[['elapsed']] - design_outcome_started
  if (is.null(design_outcome)) return(blank_result(scen, rep_id, 'design-outcome-failed'))
  combined <- combine_process(design, analysis)
  combined_outcome <- rbind(design_outcome, analysis_outcome)

  rows <- list()
  for (G in GRACES) {
    selector <- selectors[[as.character(G)]]
    panels <- list()
    models <- list()
    panel_build_time <- numeric(length(GRIDS))
    names(panel_build_time) <- GRIDS
    for (delta in GRIDS) {
      tick <- proc.time()[['elapsed']]
      panels[[as.character(delta)]] <- make_panel(analysis, delta, G)
      panel_build_time[as.character(delta)] <- proc.time()[['elapsed']] - tick
      models[[as.character(delta)]] <- fit_panel_model(
        panels[[as.character(delta)]], influence = TRUE
      )
    }
    combined_tick <- proc.time()[['elapsed']]
    combined_panel <- make_panel(combined, 1L, G)
    combined_build_time <- proc.time()[['elapsed']] - combined_tick
    combined_model <- fit_panel_model(combined_panel, influence = TRUE)

    primary_results <- list()
    for (profile in OUTCOME_PROFILES) {
      event <- analysis_outcome[, profile]
      for (delta in GRIDS) {
        key <- as.character(delta)
        panel <- panels[[key]]
        model <- models[[key]]
        diag <- selector$table[selector$table$delta == delta, , drop = FALSE]
        primary <- tryCatch(
          estimate_ccw(panel, model, event, G, 'none', oracle = FALSE),
          error = function(e) list(valid = FALSE, fail = 'estimator-error')
        )
        primary_results[[paste(profile, delta, sep = '|')]] <- primary
        base_time <- analysis_process_time + analysis_outcome_time +
          panel_build_time[key] + model$elapsed + (primary$elapsed %||% 0)
        rows[[length(rows) + 1L]] <- estimator_row(
          scen, rep_id, profile, G, 'panel', delta, primary,
          selector, diag, base_time
        )

        cap20 <- tryCatch(
          estimate_ccw(panel, model, event, G, 'cap20', oracle = FALSE),
          error = function(e) list(valid = FALSE, fail = 'estimator-error')
        )
        rows[[length(rows) + 1L]] <- estimator_row(
          scen, rep_id, profile, G, 'panel-cap20', delta, cap20,
          selector, diag, base_time + (cap20$elapsed %||% 0)
        )

        percentile <- tryCatch(
          estimate_ccw(panel, model, event, G, 'p0199', oracle = FALSE),
          error = function(e) list(valid = FALSE, fail = 'estimator-error')
        )
        rows[[length(rows) + 1L]] <- estimator_row(
          scen, rep_id, profile, G, 'panel-p0199', delta, percentile,
          selector, diag, base_time + (percentile$elapsed %||% 0)
        )

        oracle <- tryCatch(
          estimate_ccw(panel, NULL, event, G, 'none', oracle = TRUE),
          error = function(e) list(valid = FALSE, fail = 'estimator-error')
        )
        rows[[length(rows) + 1L]] <- estimator_row(
          scen, rep_id, profile, G, 'panel-oracle', delta, oracle,
          selector, diag,
          analysis_process_time + analysis_outcome_time + panel_build_time[key] +
            (oracle$elapsed %||% 0)
        )
      }

      selected_delta <- selector$selected
      selected_result <- primary_results[[paste(profile, selected_delta, sep = '|')]]
      if (!selector$support) selected_result$fail <- selector$fail
      selected_diag <- selector$table[
        selector$table$delta == selected_delta, , drop = FALSE
      ]
      ## Critique fix: selection cost and the independent design sample are
      ## charged to the adaptive method's measured worker time.
      adaptive_time <- design_time + selector$elapsed + analysis_process_time +
        analysis_outcome_time + panel_build_time[as.character(selected_delta)] +
        models[[as.character(selected_delta)]]$elapsed +
        (selected_result$elapsed %||% 0)
      rows[[length(rows) + 1L]] <- estimator_row(
        scen, rep_id, profile, G, 'selected', selected_delta, selected_result,
        selector, selected_diag, adaptive_time
      )

      one <- primary_results[[paste(profile, 1L, sep = '|')]]
      one_diag <- selector$table[selector$table$delta == 1L, , drop = FALSE]
      rows[[length(rows) + 1L]] <- estimator_row(
        scen, rep_id, profile, G, 'one-week-4000', 1L, one,
        selector, one_diag,
        analysis_process_time + analysis_outcome_time + panel_build_time['1'] +
          models[['1']]$elapsed + (one$elapsed %||% 0)
      )

      combined_result <- tryCatch(
        estimate_ccw(combined_panel, combined_model, combined_outcome[, profile],
                     G, 'none', oracle = FALSE),
        error = function(e) list(valid = FALSE, fail = 'estimator-error')
      )
      resource_time <- design_time + analysis_process_time + design_outcome_time +
        analysis_outcome_time + combined_build_time + combined_model$elapsed +
        (combined_result$elapsed %||% 0)
      rows[[length(rows) + 1L]] <- estimator_row(
        scen, rep_id, profile, G, 'one-week-5000', 1L, combined_result,
        selector, one_diag, resource_time
      )

      ## Critique fix: the fixed one-week estimator receives exact weekly
      ## treatment boundaries and exact event times. Exact histories are never
      ## supplied to a coarse-grid method.
      full_result <- one
      rows[[length(rows) + 1L]] <- estimator_row(
        scen, rep_id, profile, G, 'full-history', 1L, full_result,
        selector, one_diag,
        analysis_process_time + analysis_outcome_time + panel_build_time['1'] +
          models[['1']]$elapsed + (full_result$elapsed %||% 0)
      )
    }
  }

  out <- do.call(rbind, rows)
  out$serialization_bytes <- as.numeric(object.size(out))
  out$replicate_worker_time <- proc.time()[['elapsed']] - started
  out
}

scenarios <- build_process_scenarios()
cells <- build_cells()
args <- commandArgs(TRUE)
selected_cells <- seq_len(nrow(cells))
if (length(args) && grepl('^\\d+:\\d+$', args[1L])) {
  ends <- as.integer(strsplit(args[1L], ':', fixed = TRUE)[[1L]])
  selected_cells <- intersect(seq.int(ends[1L], ends[2L]), selected_cells)
}
selected_process <- unique(cells$process_scenario[selected_cells])

res <- run_design(
  one_rep,
  scenarios,
  n_rep = N_REP,
  master_seed = MASTER_SEED,
  outdir = OUTDIR,
  workers = WORKERS,
  resume = TRUE,
  only = selected_process
)

write_provenance(
  OUTDIR,
  packages = c('stats', 'future', 'furrr', 'mvtnorm'),
  extra = list(
    study = 'TZO-01 outcome-masked grid selection',
    published_cells = nrow(cells),
    coupled_process_blocks = nrow(scenarios),
    replicates = N_REP,
    requested_replicates = ORIGINAL_N_REP,
    design_sample = N_DESIGN,
    analysis_sample = N_ANALYSIS,
    weeks = N_WEEKS,
    grids = paste(GRIDS, collapse = ', '),
    graces = paste(GRACES, collapse = ', '),
    master_seed = MASTER_SEED
  )
)
message(sprintf('done: %d rows', nrow(res)))
