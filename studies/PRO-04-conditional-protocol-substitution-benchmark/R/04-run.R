## Study PRO-04: run the finite-sample design.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:4
##
## Set PRO04_PILOT=1 to run the mandatory 100-replicate runtime pilot into
## results/pilot without affecting resumable main-run checkpoints.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))
unit_test_arm_indices()

BASE_OUT <- here('results')
stopifnot(file.exists(file.path(BASE_OUT, 'truth.rds')))
stopifnot(file.exists(file.path(BASE_OUT, 'sample-size.rds')))
TRUTH <- readRDS(file.path(BASE_OUT, 'truth.rds'))
POWER <- readRDS(file.path(BASE_OUT, 'sample-size.rds'))
if (!identical(POWER$config_signature, CONFIG_SIGNATURE)) stop('Stale sample-size cache')
N_PER_REP <- as.integer(POWER$n)
MECHANISMS <- split(TRUTH, TRUTH$scenario)

PILOT <- identical(Sys.getenv('PRO04_PILOT', unset = '0'), '1')
RUN_REP <- if (PILOT) PILOT_REP else N_REP
OUTDIR <- if (PILOT) file.path(BASE_OUT, 'pilot') else BASE_OUT
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

parse_slice <- function(arg, n) {
  if (!length(arg)) return(seq_len(n))
  parts <- strsplit(arg[1], ':', fixed = TRUE)[[1]]
  if (length(parts) != 2L) return(seq_len(n))
  values <- suppressWarnings(as.integer(parts))
  if (anyNA(values)) return(seq_len(n))
  intersect(seq(values[1], values[2]), seq_len(n))
}

blank_rows <- function(truth, why) {
  targets <- c(truth$psi_i, truth$psi_o, truth$psi_i, truth$psi_i,
               truth$psi_i, truth$delta, truth$delta)
  data.frame(
    mechanism_id = truth$mechanism_id,
    method = METHODS,
    target_name = c('psi_i_wrong_label', 'psi_o', 'psi_i', 'psi_i',
                    'psi_i', 'delta', 'delta'),
    target_value = targets,
    est = NA_real_, se = NA_real_, lo95 = NA_real_, hi95 = NA_real_,
    interval_width = NA_real_, classification = NA_character_,
    ess_active = NA_real_, ess_control = NA_real_, low_ess = NA,
    fail = why, config_signature = CONFIG_SIGNATURE,
    stringsAsFactors = FALSE
  )
}

row_for <- function(method, target_name, target_value, result, mechanism_id) {
  finite <- is.finite(result$est) && is.finite(result$se)
  lo <- if (finite) result$est - 1.96 * result$se else NA_real_
  hi <- if (finite) result$est + 1.96 * result$se else NA_real_
  data.frame(
    mechanism_id = mechanism_id, method = method,
    target_name = target_name, target_value = target_value,
    est = result$est, se = result$se, lo95 = lo, hi95 = hi,
    interval_width = if (finite) hi - lo else NA_real_,
    classification = result$classification %||% NA_character_,
    ess_active = result$ess_active %||% NA_real_,
    ess_control = result$ess_control %||% NA_real_,
    low_ess = result$low_ess %||% NA,
    fail = result$fail %||% NA_character_,
    config_signature = CONFIG_SIGNATURE,
    stringsAsFactors = FALSE
  )
}

safe_effect <- function(expr, n, label) {
  tryCatch(expr, error = function(e)
    failed_effect(n, paste0(label, ':', conditionMessage(e))))
}

## Every replicate returns these same seven rows, including failures.
one_rep <- function(scen, rep_id) {
  truth <- MECHANISMS[[as.character(scen$scenario)]][rep_id, , drop = FALSE]
  h <- as.list(truth[1, , drop = FALSE])
  dat <- tryCatch(gen_replicate(h, N_PER_REP), error = function(e) e)
  if (inherits(dat, 'error')) return(blank_rows(truth, paste0('dgm:', conditionMessage(dat))))

  operational <- safe_effect(operational_effect(dat, h), nrow(dat), 'operational')
  validation <- safe_effect(ideal_effect(dat, h, validation_only = TRUE),
                            nrow(dat), 'validation')
  augmented <- safe_effect(augmented_intended_effect(dat, h),
                           nrow(dat), 'augmented')
  oracle <- safe_effect(ideal_effect(dat, h, validation_only = FALSE),
                        nrow(dat), 'oracle')
  gap_cc <- safe_effect(complete_case_gap(dat, h), nrow(dat), 'gap-cc')
  gap_aug <- safe_effect(augmented_gap(operational, augmented),
                         nrow(dat), 'gap-aug')

  ## The silent and explicitly labeled operational rows are numerically
  ## identical. Only their declared targets differ.
  out <- rbind(
    row_for('silent', 'psi_i_wrong_label', truth$psi_i, operational, rep_id),
    row_for('operational', 'psi_o', truth$psi_o, operational, rep_id),
    row_for('validation', 'psi_i', truth$psi_i, validation, rep_id),
    row_for('augmented', 'psi_i', truth$psi_i, augmented, rep_id),
    row_for('oracle', 'psi_i', truth$psi_i, oracle, rep_id),
    row_for('gap_cc', 'delta', truth$delta, gap_cc, rep_id),
    row_for('gap_aug', 'delta', truth$delta, gap_aug, rep_id)
  )
  rownames(out) <- NULL
  out
}

scenarios <- build_scenarios()
sel <- parse_slice(commandArgs(TRUE)[1], nrow(scenarios))
t0 <- proc.time()[['elapsed']]
res <- run_design(
  one_rep, scenarios, n_rep = RUN_REP, master_seed = MASTER_SEED,
  outdir = OUTDIR, workers = N_WORKERS, resume = TRUE, only = sel
)
elapsed <- proc.time()[['elapsed']] - t0

raw_dir <- file.path(OUTDIR, 'raw')
raw_files <- if (dir.exists(raw_dir)) list.files(raw_dir, full.names = TRUE) else character()
checkpoint_bytes <- if (length(raw_files)) sum(file.info(raw_files)$size, na.rm = TRUE) else 0
serialization_seconds <- NA_real_
serialization_bytes <- NA_real_
if (PILOT && length(raw_files)) {
  sample_object <- readRDS(raw_files[1])
  temporary <- tempfile(fileext = '.rds')
  serialization_seconds <- system.time(saveRDS(sample_object, temporary))[['elapsed']]
  serialization_bytes <- file.info(temporary)$size
  unlink(temporary)
}
gc_record <- gc()
peak_memory_mb <- sum(gc_record[, 'max used (Mb)'])
completed_scenarios <- length(unique(res$scenario))
person_records <- completed_scenarios * RUN_REP * N_PER_REP

write_provenance(
  OUTDIR,
  packages = c('stats', 'future', 'furrr'),
  extra = list(
    study = 'PRO-04 conditional protocol substitution benchmark',
    pilot = PILOT,
    scenarios_completed = completed_scenarios,
    replicates_per_scenario = RUN_REP,
    n_per_replicate = N_PER_REP,
    validation_probability = VALIDATION_PROB,
    workers = N_WORKERS,
    elapsed_seconds = elapsed,
    person_records = person_records,
    person_records_per_second = person_records / max(elapsed, .Machine$double.eps),
    peak_memory_mb = peak_memory_mb,
    checkpoint_bytes = checkpoint_bytes,
    serialization_seconds = serialization_seconds,
    serialization_bytes = serialization_bytes,
    operating_system = paste(Sys.info()[c('sysname', 'release', 'machine')], collapse = ' '),
    r_version = R.version.string,
    master_seed = MASTER_SEED,
    scaled_from_replicates = N_REP_PROTOCOL,
    power_rule_version = POWER_RULE_VERSION
  )
)
message(sprintf('done: %d rows, N=%d, elapsed %.1f seconds',
                nrow(res), N_PER_REP, elapsed))
