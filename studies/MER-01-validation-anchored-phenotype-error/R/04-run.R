## MER-01: run one sequential look of the resumable design.
##
## First run R/03-truth.R. Optional environment variable MER01_LOOK selects
## look 1, 2, or 3. The positional i:j argument selects scenario cells.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
         else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))

OUTDIR <- here('results')
stopifnot(file.exists(file.path(OUTDIR, 'truth.rds')),
          file.exists(file.path(OUTDIR, 'mi-calibration.rds')))
calibration <- readRDS(file.path(OUTDIR, 'mi-calibration.rds'))
if (!isTRUE(calibration$passed) || !is.finite(calibration$selected_M))
  stop('full run cannot start because MI calibration failed')
SELECTED_M <- as.integer(calibration$selected_M)

look <- as.integer(Sys.getenv('MER01_LOOK', '1'))
if (!look %in% seq_along(N_REP_LOOKS)) stop('MER01_LOOK must be 1, 2, or 3')
rep_offset <- if (look == 1L) 0L else N_REP_LOOKS[look - 1L]
n_rep_stage <- LOOK_INCREMENT[look]
stage_out <- if (look == 1L) OUTDIR else file.path(OUTDIR, paste0('look-', look))
dir.create(stage_out, recursive = TRUE, showWarnings = FALSE)

blank_rows <- function(reason, rep_id, scen) {
  g <- expand.grid(method = METHODS, contrast = CONTRASTS,
                   stringsAsFactors = FALSE)
  data.frame(
    g, est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
    ess_0 = NA_real_, ess_1 = NA_real_, median_weight = NA_real_,
    p99_weight = NA_real_, adherence_0 = NA_real_, adherence_1 = NA_real_,
    censor_change_L = NA_real_, interval_df = NA_real_, fail = reason,
    eligible = TRUE, interaction_est = NA_real_, outcome_base_est = NA_real_,
    cell_id = scen$scenario, rep_global = rep_offset + rep_id, look = look,
    selected_M = SELECTED_M, stringsAsFactors = FALSE)
}

method_rows <- function(method, result, eligible, rep_id, scen) {
  if (is.null(result)) result <- empty_estimate('not-applicable')
  result$method <- method
  result$eligible <- eligible
  result$interaction_est <- NA_real_
  result$outcome_base_est <- NA_real_
  result$cell_id <- scen$scenario
  result$rep_global <- rep_offset + rep_id
  result$look <- look
  result$selected_M <- SELECTED_M
  result[, c('method', 'contrast', 'est', 'se', 'lo', 'hi', 'ess_0', 'ess_1',
             'median_weight', 'p99_weight', 'adherence_0', 'adherence_1',
             'censor_change_L', 'interval_df', 'fail', 'eligible',
             'interaction_est', 'outcome_base_est', 'cell_id', 'rep_global',
             'look', 'selected_M')]
}

safe_call <- function(expr) {
  tryCatch(expr, error = function(e) empty_estimate('estimator-error'))
}

extract_est <- function(x, contrast) {
  z <- x$est[x$contrast == contrast]
  if (length(z) == 1L) z else NA_real_
}

one_rep <- function(scen, rep_id) {
  ## No set.seed occurs here. run_design owns this replicate's random stream.
  dat <- tryCatch(gen_latent(scen, N_PER_REPLICATE), error = function(e) NULL)
  if (is.null(dat)) return(blank_rows('dgm-failed', rep_id, scen))
  noise <- draw_error_noise(N_PER_REPLICATE)
  obs <- make_observed(dat, scen, noise)

  fitted <- list(
    first_order = safe_call(estimate_threshold(dat, obs, scen, 'first_order')),
    rich_history = safe_call(estimate_threshold(dat, obs, scen, 'rich_history')),
    exact_filtered = safe_call(estimate_threshold(dat, obs, scen, 'exact_filtered')),
    corrected_mi = safe_call(estimate_mi(dat, obs, scen, SELECTED_M)),
    oracle_complete = safe_call(estimate_oracle(dat, scen))
  )

  large_selected <- (rep_offset + rep_id) %% as.integer(1 / MI_LARGE_FRACTION) == 0L
  fitted$corrected_mi_4M <- if (large_selected)
    safe_call(estimate_mi(dat, obs, scen, MI_LARGE_FACTOR * SELECTED_M)) else NULL

  prior_cell <- !is.na(scen$benchmark) && scen$validation_n == 100L &&
    scen$accuracy %in% c(0.70, 0.85)
  fitted$corrected_prior5 <- if (prior_cell)
    safe_call(estimate_mi(dat, obs, scen, SELECTED_M, 5)) else NULL
  fitted$corrected_prior10 <- if (prior_cell)
    safe_call(estimate_mi(dat, obs, scen, SELECTED_M, 10)) else NULL

  rows <- do.call(rbind, lapply(METHODS, function(method) {
    eligible <- switch(method,
      corrected_mi_4M = large_selected,
      corrected_prior5 = prior_cell,
      corrected_prior10 = prior_cell,
      TRUE)
    method_rows(method, fitted[[method]], eligible, rep_id, scen)
  }))

  ## Critique fix: in each joint primary cell, A-only, L-only, joint, and
  ## no-error estimates use the same latent cohort and random error uniforms.
  ## This supplies genuinely paired nonadditivity contributions.
  if (scen$block == 'primary' && scen$error_nodes == 'AL') {
    for (method in c('rich_history', 'exact_filtered')) {
      components <- list(AL = fitted[[method]])
      for (nodes in c('A', 'L', 'none')) {
        shadow <- scen
        shadow$error_nodes <- nodes
        if (nodes == 'none') shadow$accuracy <- 1
        shadow_obs <- make_observed(dat, shadow, noise)
        components[[nodes]] <- safe_call(
          estimate_threshold(dat, shadow_obs, shadow, method))
      }
      for (contrast in CONTRASTS) {
        interaction <- extract_est(components$AL, contrast) -
          extract_est(components$A, contrast) -
          extract_est(components$L, contrast) +
          extract_est(components$none, contrast)
        rows$interaction_est[rows$method == method &
                               rows$contrast == contrast] <- interaction
      }
    }
  }

  ## Critique fix: outcome error is compared with the same joint A and L data
  ## with Y observed exactly. It is not included in the primary classification.
  if (scen$block == 'outcome_component') {
    base <- scen
    base$outcome_error <- FALSE
    base_obs <- make_observed(dat, base, noise)
    for (method in c('rich_history', 'exact_filtered')) {
      b <- safe_call(estimate_threshold(dat, base_obs, base, method))
      for (contrast in CONTRASTS)
        rows$outcome_base_est[rows$method == method &
                               rows$contrast == contrast] <- extract_est(b, contrast)
    }
  }
  rownames(rows) <- NULL
  rows
}

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1])) {
  p <- as.integer(strsplit(args[1], ':', fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

res <- run_design(one_rep, scenarios, n_rep = n_rep_stage,
                  master_seed = MASTER_SEED + 1000000L * (look - 1L),
                  outdir = stage_out, workers = WORKERS, resume = TRUE,
                  only = sel)

write_provenance(
  stage_out,
  packages = c('stats', 'splines', 'mvtnorm', 'data.table', 'future', 'furrr'),
  extra = list(
    study = 'MER-01 longitudinal phenotype error',
    scenarios = nrow(scenarios), look = look,
    stage_replicates = n_rep_stage,
    cumulative_replicates = N_REP_LOOKS[look],
    n_per_replicate = N_PER_REPLICATE, truth_n = N_TRUTH,
    selected_imputations = SELECTED_M, master_seed = MASTER_SEED
  )
)
message(sprintf('look %d complete: %d returned rows', look, nrow(res)))
