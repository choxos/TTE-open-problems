## Study MIS-01: run the resumable simulation.
##
## Usage: Rscript R/04-run.R
##        Rscript R/04-run.R 1:1

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1])))) else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))

OUT <- here('results')
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUT, 'truth.rds')))
truth <- readRDS(file.path(OUT, 'truth.rds'))
scenarios <- build_scenarios()
prepared <- unique(truth[, c(names(scenarios), 'kappa', 'alpha',
                             'calibrated_severity12', 'calibrated_observation_rate')])
prepared <- prepared[order(prepared$sid), ]

args <- commandArgs(TRUE)
sel <- seq_len(nrow(prepared))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1])) {
  p <- as.integer(strsplit(args[1], ':', fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

pilot_file <- file.path(OUT, 'mi-pilot.rds')
if (!file.exists(pilot_file)) {
  ## Critique fix: m is selected on independent sparse-corner pilot data using
  ## point-estimate and standard-error reproducibility. Likelihood, path,
  ## completed-analysis, and combination failures remain separate.
  sparse <- prepared[prepared$panel == 'confirmatory' &
                     prepared$profile_id == 'ALw-YLw-YALw-LLw' &
                     prepared$gamma_L == 1.386294 &
                     prepared$gamma_A == 0.693147 &
                     prepared$obs_target == 0.08, ][1, ]
  set.seed(MASTER_SEED + 900000L)
  datasets <- lapply(seq_len(MI_PILOT_DATASETS), function(i) gen_replicate(sparse, N_PEOPLE))
  pilot_rows <- list()
  selected <- NA_integer_
  for (m in MI_CANDIDATES) {
    dif_est <- dif_se <- rep(NA_real_, MI_PILOT_DATASETS)
    for (i in seq_along(datasets)) {
      a <- fit_mar_mi(datasets[[i]], sparse, 'compatible', m)
      b <- fit_mar_mi(datasets[[i]], sparse, 'compatible', m)
      ia <- match('rd24', a$estimand); ib <- match('rd24', b$estimand)
      if (is.na(a$fail[ia]) && is.na(b$fail[ib])) {
        dif_est[i] <- abs(a$est[ia] - b$est[ib])
        dif_se[i] <- abs(a$se[ia] - b$se[ib]) / max(a$se[ia], b$se[ib], 1e-12)
      }
    }
    qest <- if (sum(is.finite(dif_est)) == MI_PILOT_DATASETS) unname(stats::quantile(dif_est, 0.95)) else Inf
    qse <- if (sum(is.finite(dif_se)) == MI_PILOT_DATASETS) unname(stats::quantile(dif_se, 0.95)) else Inf
    pilot_rows[[length(pilot_rows) + 1L]] <- data.frame(m = m, q95_estimate_difference = qest,
                                                        q95_relative_se_difference = qse,
                                                        pass = qest <= MI_POINT_TOL && qse <= MI_RELSE_TOL)
    if (qest <= MI_POINT_TOL && qse <= MI_RELSE_TOL) { selected <- m; break }
  }
  pilot <- do.call(rbind, pilot_rows)
  saveRDS(list(selected = selected, results = pilot), pilot_file)
  utils::write.csv(pilot, file.path(OUT, 'mi-pilot.csv'), row.names = FALSE)
  if (is.na(selected)) stop('MI pilot did not authorize the main run at m=800')
}
MI_PILOT <- readRDS(pilot_file)
if (is.na(MI_PILOT$selected)) stop('MI main run is not authorized')
MI_M_SELECTED <- MI_PILOT$selected

grid_blank <- function(scen, rep_id, why) {
  variants <- analysis_variants(scen)
  out <- do.call(rbind, lapply(variants, function(v) do.call(rbind, lapply(METHODS, function(m) {
    result_template(m, v, why, 'dgm')
  }))))
  out$sid <- scen$sid
  out$rep_id <- rep_id
  out$dgm_ok <- FALSE
  out
}

one_rep <- function(scen, rep_id) {
  dat <- tryCatch(gen_replicate(scen, N_PEOPLE), error = function(e) NULL)
  if (is.null(dat)) return(grid_blank(scen, rep_id, 'dgm-failed'))
  rows <- lapply(analysis_variants(scen), function(v) {
    tryCatch(estimate_replicate(dat, scen, v, MI_M_SELECTED),
             error = function(e) {
               do.call(rbind, lapply(METHODS, function(m) result_template(m, v, 'replicate-failed', 'estimator')))
             })
  })
  out <- do.call(rbind, rows)
  out$sid <- scen$sid
  out$rep_id <- rep_id
  out$dgm_ok <- TRUE
  out
}

crn_levels <- unique(prepared$crn_group)
for (i in sel) {
  s <- prepared[i, , drop = FALSE]
  destination <- file.path(OUT, 'scenario-runs', sprintf('scenario-%03d', s$sid))
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  ## Each run_design call receives a one-row job and the same master seed for
  ## every member of its CRN group. Since gen_replicate consumes fixed-size
  ## uniform blocks, matched observation mechanisms use common random numbers.
  job <- s
  job$scenario <- 1L
  group_seed <- MASTER_SEED + 10000L * match(s$crn_group, crn_levels)
  run_design(one_rep, job, n_rep = N_REP, master_seed = group_seed,
             outdir = destination, workers = WORKERS, resume = TRUE, only = 1L)
  message(sprintf('scenario %d/%d complete or cached', s$sid, nrow(prepared)))
}

write_provenance(
  OUT,
  packages = c('stats', 'data.table', 'mvtnorm', 'future', 'furrr'),
  extra = list(
    study = 'MIS-01 conditional visit-process comparison',
    scenarios = nrow(prepared), replicates = N_REP,
    people = N_PEOPLE, months = N_MONTHS, workers = WORKERS,
    master_seed = MASTER_SEED, mi_m = MI_M_SELECTED,
    scaled_person_months = nrow(prepared) * N_REP * N_PEOPLE * N_MONTHS,
    confirmatory_decision_authorized = N_REP >= DECISION$minimum_valid_datasets
  )
)
