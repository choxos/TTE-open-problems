## GMT-04 benchmark: resumable replicate driver.
##
## Rscript R/03-truth.R
## Rscript R/04-run.R
## Rscript R/04-run.R 1:1

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
stopifnot(file.exists(here('R', '00-config.R')))

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))

OUTDIR <- here('results')
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(file.path(OUTDIR, 'truth.rds')) ||
    !file.exists(file.path(OUTDIR, 'truth-manifest.rds'))) {
  stop('run R/03-truth.R before generating estimator replicates')
}
truth_manifest <- readRDS(file.path(OUTDIR, 'truth-manifest.rds'))
if (!all(truth_manifest$verified)) stop('truth manifest is not verified')

vendor_audit <- ensure_ltmle_vendor(STUDY)
set.seed(MASTER_SEED + 700000L)
audit_scenario <- RUN_SCENARIOS[RUN_SCENARIOS$control == 'C0' &
                                  !is.na(RUN_SCENARIOS$control), , drop = FALSE]
audit_data <- gen_replicate(audit_scenario, n = 4000L)
contract_audit <- ltmle_contract_test(audit_data)
implementation_audit <- list(
  status = isTRUE(vendor_audit$status) && isTRUE(contract_audit$status),
  date = as.character(Sys.Date()),
  vendor = vendor_audit,
  contract = contract_audit,
  protocols = c(always = '111111', never = '000000'),
  horizon_months = HORIZON_MONTHS,
  population = 'all eligible individuals at month 0',
  loss_intervention = 'no loss',
  effect_scale = '36-month marginal risk difference'
)
saveRDS(implementation_audit, file.path(OUTDIR, 'implementation-audit.rds'))
if (!implementation_audit$status)
  stop('ltmle implementation audit failed; the study remains uninformative')

METHODS <- c('iptw_nuisance', 'iptw_fixed', 'gformula_pooled', 'ltmle_formula')
PRIMARY_POINT_METHODS <- c('iptw_nuisance', 'gformula_pooled', 'ltmle_formula')

canonical_signature <- function(generated, long) {
  loss_time <- apply(generated$loss, 1, function(x) {
    hit <- which(x == 1L)
    if (length(hit)) hit[1] else 0L
  })
  paste(
    'A0=000000', 'A1=111111',
    paste0('n=', generated$n),
    paste0('horizon=', HORIZON_MONTHS),
    paste0('risksets=', paste(tabulate(long$k + 1L, nbins = N_VISITS),
                              collapse = ':')),
    paste0('loss-check=', sum(loss_time * seq_along(loss_time))),
    paste0('baseline-weight=', format(sum(rep(1 / generated$n, generated$n)),
                                     digits = 17)),
    sep = '|'
  )
}

row_from_result <- function(x, method, analysis_scenario, rep_id, signature) {
  data.frame(
    analysis_scenario = analysis_scenario,
    rep_id = rep_id,
    method = method,
    primary_point_method = method %in% PRIMARY_POINT_METHODS,
    risk0 = x$risk0, risk1 = x$risk1, est = x$est, var = x$var,
    se = x$se, lo = x$lo, hi = x$hi,
    output_valid = isTRUE(x$output_valid),
    common_output_failure = !isTRUE(x$output_valid),
    fail = x$fail,
    software_error = !is.na(x$software_error),
    software_message = x$software_error,
    rank_deficient = x$rank_deficient,
    max_coef = x$max_coef,
    condition_number = x$condition_number,
    clip_rate = x$clip_rate,
    max_weight = x$max_weight,
    ess_min = x$ess_min,
    sparse_min = x$sparse_min,
    mass_error = x$mass_error,
    gradient_ok = x$gradient_ok,
    clever_max = x$clever_max,
    zero_ic_variance = x$zero_ic_variance,
    convergence_warning = x$convergence_warning,
    bootstrap_se = x$bootstrap_se,
    diagnostic_note = x$diagnostic_note,
    protocol_signature = signature,
    alignment_ok = TRUE,
    stringsAsFactors = FALSE
  )
}

blank_rows <- function(analysis_ids, rep_id, why) {
  out <- list(); at <- 0L
  for (id in analysis_ids) {
    for (method in METHODS) {
      at <- at + 1L
      bad <- finish_result(list(software_error = why))
      out[[at]] <- row_from_result(bad, method, id, rep_id, NA_character_)
    }
  }
  do.call(rbind, out)
}

one_rep <- function(scen, rep_id) {
  analysis_ids <- as.integer(strsplit(scen$analysis_ids[1], ',', fixed = TRUE)[[1]])
  generated <- tryCatch(gen_replicate(scen, n = N_PER_REPLICATE),
                        error = function(e) e)
  if (inherits(generated, 'error'))
    return(blank_rows(analysis_ids, rep_id, paste('DGM failed:', conditionMessage(generated))))
  long <- make_observed_long(generated)
  signature <- canonical_signature(generated, long)
  rows <- list(); at <- 0L

  for (analysis_id in analysis_ids) {
    meta <- ANALYSIS_SCENARIOS[
      ANALYSIS_SCENARIOS$analysis_scenario == analysis_id, , drop = FALSE
    ]
    observed_u <- isTRUE(meta$observed_u)

    ## Critique fix: hidden U is a composite identification failure. The same
    ## generated individuals are analyzed with U shown and hidden.
    iptw <- tryCatch(est_iptw(long, observed_u), error = function(e) NULL)
    if (is.null(iptw)) {
      bad <- finish_result(list(software_error = 'unhandled IPTW error'))
      iptw <- list(nuisance = bad, fixed = bad)
    }
    gformula <- tryCatch(est_gformula(generated, long, observed_u),
                         error = function(e) finish_result(list(
                           software_error = conditionMessage(e))))
    tmle <- tryCatch(est_ltmle(generated, observed_u),
                     error = function(e) finish_result(list(
                       software_error = conditionMessage(e))))

    ## Critique fix: the nuisance-adjusted interval is primary. The fixed-weight
    ## interval shares its point estimate and cannot enter disagreement.
    if (isTRUE(meta$bootstrap_anchor) && rep_id %in% BOOTSTRAP_IDS &&
        isTRUE(iptw$nuisance$output_valid)) {
      iptw$nuisance$bootstrap_se <- bootstrap_iptw_se(long, observed_u)
    }

    estimates <- list(
      iptw_nuisance = iptw$nuisance,
      iptw_fixed = iptw$fixed,
      gformula_pooled = gformula,
      ltmle_formula = tmle
    )
    for (method in METHODS) {
      at <- at + 1L
      rows[[at]] <- row_from_result(estimates[[method]], method, analysis_id,
                                    rep_id, signature)
    }
  }
  out <- do.call(rbind, rows)
  signatures <- unique(out$protocol_signature[!is.na(out$protocol_signature)])
  out$alignment_ok <- length(signatures) == 1L
  out
}

run_scenarios <- build_run_scenarios()
args <- commandArgs(TRUE)
selected <- seq_len(nrow(run_scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1])) {
  bounds <- as.integer(strsplit(args[1], ':', fixed = TRUE)[[1]])
  selected <- intersect(seq(bounds[1], bounds[2]), selected)
}

## The run grid has 14 generated mechanisms. Twelve are analyzed twice with the
## same individuals, once with U observed and once hidden. This yields the 26
## prespecified analysis scenarios while preserving the paired comparison.
pilot_path <- file.path(OUTDIR, 'pilot-resource.rds')
if (!file.exists(pilot_path)) {
  pilot_ids <- unique(c(
    which(run_scenarios$s == 1.00 & run_scenarios$role == 'G0Q0'),
    which(run_scenarios$s == 1.00 & run_scenarios$role == 'G1Q1'),
    which(run_scenarios$s == 1.70 & run_scenarios$role == 'G0Q0')
  ))
  pilot_scenarios <- run_scenarios[pilot_ids, , drop = FALSE]
  pilot_out <- file.path(OUTDIR, 'pilot')
  t0 <- proc.time()[['elapsed']]
  pilot_result <- run_design(
    one_rep, pilot_scenarios, n_rep = PILOT_REPS,
    master_seed = MASTER_SEED + 900000L, outdir = pilot_out,
    workers = WORKERS, resume = TRUE, only = seq_len(nrow(pilot_scenarios))
  )
  elapsed <- proc.time()[['elapsed']] - t0
  pilot_files <- list.files(pilot_out, recursive = TRUE, full.names = TRUE)
  storage <- if (length(pilot_files))
    sum(file.info(pilot_files)$size, na.rm = TRUE) else 0
  rss <- tryCatch(as.numeric(system2('ps', c('-o', 'rss=', '-p', Sys.getpid()),
                                      stdout = TRUE)), error = function(e) NA_real_)
  resource <- list(
    date = as.character(Sys.Date()), elapsed_seconds = elapsed,
    generated_replicates = nrow(pilot_scenarios) * PILOT_REPS,
    analysis_rows = nrow(pilot_result), workers = WORKERS,
    parent_peak_rss_kb_observed = rss,
    storage_bytes = storage,
    naive_full_wall_hours = elapsed * nrow(run_scenarios) * N_REP /
      (nrow(pilot_scenarios) * PILOT_REPS) / 3600,
    note = 'Naive extrapolation is conservative because bootstrap validation is restricted to the first 25 identifiers.'
  )
  saveRDS(resource, pilot_path)
}

results <- run_design(
  one_rep, run_scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUTDIR, workers = WORKERS, resume = TRUE, only = selected
)

write_provenance(
  OUTDIR,
  packages = c('stats', 'data.table', 'ltmle', 'future', 'furrr'),
  extra = list(
    study = 'GMT-04 named implementation disagreement benchmark',
    analysis_scenarios = nrow(ANALYSIS_SCENARIOS),
    generated_mechanisms = nrow(run_scenarios),
    replicates = N_REP,
    n_per_replicate = N_PER_REPLICATE,
    master_seed = MASTER_SEED,
    probability_bounds = paste(PROB_BOUNDS, collapse = ', '),
    ltmle_archive_sha256 = vendor_audit$archive_sha256,
    ltmle_manual_sha256 = vendor_audit$manual_sha256
  )
)
message(sprintf('done: %d returned rows', nrow(results)))
