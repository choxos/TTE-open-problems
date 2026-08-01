## ELG-01: configuration.
##
## This implementation follows the revised protocol. It answers only the
## structural no-validation question and the operating characteristics of
## internal probability validation. It does not claim to settle external or
## nonprobability validation.

MASTER_SEED      <- 20260731L
TRUTH_SEED       <- 20260731L
CALIBRATION_SEED <- 81001L

N_PER_REP    <- 4000L
N_REP        <- 4000L
N_TRUTH      <- 10000000L
N_CALIBRATION <- 10000000L
WORKERS      <- 6L

MI_PRIMARY <- 20L
MI_CHECK   <- 50L
MI_CHECK_MODULUS <- 50L       # Exactly 2 percent: 4000 / 50 = 80 per run cell.

## No decision-critical replicate or factor was removed. Pairing packs the 48
## scenario combinations into eight generated cohorts per replicate. Thus the
## production run generates 8 * 4000 = 32,000 cohorts and expands each cohort
## to the six lambda by validation-budget combinations. A naive unpaired run
## would generate 48 * 4000 = 192,000 cohorts. This preserves 4000 paired
## replicates per scenario while making the specified overnight ceiling
## plausible. The protocol still requires a complete timing pilot before the
## production run.

MISSING_PROPORTIONS <- c(0.20, 0.50)
LAMBDA_VALUES <- c(lambda_0 = 0, lambda_log2 = log(2), lambda_log4 = log(4))
VALIDATION_N <- c(100L, 400L)
EFFECT_STRUCTURES <- c('homogeneous', 'heterogeneous')
KAPPA_VALUES <- c(0, 1.10)
SENSITIVITY_VALUES <- LAMBDA_VALUES

## These values are populated from the deterministic calibration cache written
## by 03-truth.R. The critique required explicit separation of stipulated
## mechanisms from empirical calibration. Lambda and kappa remain sensitivity
## settings; only the recording intercept is numerically calibrated.
ALPHA_M <- rep(NA_real_, length(MISSING_PROPORTIONS))
names(ALPHA_M) <- paste0('m', sprintf('%02d', 100 * MISSING_PROPORTIONS))

set_recording_alphas <- function(calibration) {
  stopifnot(all(c('m', 'alpha', 'error') %in% names(calibration)))
  idx <- match(MISSING_PROPORTIONS, calibration$m)
  if (anyNA(idx) || any(abs(calibration$error[idx]) >= 0.0001)) {
    stop('recording calibration is absent or outside tolerance')
  }
  ALPHA_M <<- stats::setNames(calibration$alpha[idx], names(ALPHA_M))
  invisible(ALPHA_M)
}

build_scenarios <- function() {
  if (any(!is.finite(ALPHA_M))) stop('recording intercepts have not been loaded')
  g <- expand.grid(
    m = MISSING_PROPORTIONS,
    lambda_key = names(LAMBDA_VALUES),
    validation_n = VALIDATION_N,
    effect = EFFECT_STRUCTURES,
    kappa = KAPPA_VALUES,
    stringsAsFactors = FALSE
  )
  g$lambda <- unname(LAMBDA_VALUES[g$lambda_key])
  g$alpha_m <- ALPHA_M[match(g$m, MISSING_PROPORTIONS)]
  g$validation_prob <- g$validation_n / (N_PER_REP * g$m)
  stopifnot(all(g$validation_prob > 0 & g$validation_prob <= 1))
  g$scenario <- seq_len(nrow(g))

  ## Critique fix: eligibility association and effect modification are crossed
  ## independently. Pairing changes computation only; it does not collapse the
  ## 48-factor scenario grid.
  cell_key <- paste(g$m, g$effect, g$kappa, sep = '|')
  g$run_cell <- match(cell_key, unique(cell_key))
  g[, c('scenario', 'run_cell', 'm', 'lambda_key', 'lambda',
        'validation_n', 'validation_prob', 'effect', 'kappa', 'alpha_m')]
}

build_run_cells <- function(scenarios = build_scenarios()) {
  keep <- !duplicated(scenarios$run_cell)
  out <- scenarios[keep, c('run_cell', 'm', 'effect', 'kappa'), drop = FALSE]
  out$scenario <- out$run_cell
  out <- out[, c('scenario', 'run_cell', 'm', 'effect', 'kappa')]
  rownames(out) <- NULL
  out
}

method_grid <- function() {
  data.frame(
    method = c(
      'oracle', 'complete_case', 'mi_continuous', 'mi_indicator',
      'mar_ipaw', 'oracle_recording_ipaw',
      rep('sensitivity', 3L),
      rep('fractional', 2L), 'two_phase_ipw',
      rep('augmented', 2L), 'bounds',
      'mi_continuous_m50', 'mi_indicator_m50'
    ),
    variant = c(
      'primary', 'primary', 'm20', 'm20', 'primary', 'primary',
      names(SENSITIVITY_VALUES),
      'primary', 'omit_c_h', 'primary',
      'primary', 'intercept_r', 'primary', 'm50', 'm50'
    ),
    information_set = c(
      'oracle', rep('no_validation', 5L), rep('no_validation', 3L),
      rep('validation', 2L), 'validation', rep('validation', 2L),
      'no_validation', rep('no_validation', 2L)
    ),
    target = c(
      'all_eligible', 'recorded_eligible', rep('all_eligible', 15L)
    ),
    lambda_star = c(
      rep(NA_real_, 6L), unname(SENSITIVITY_VALUES),
      rep(NA_real_, 8L)
    ),
    stringsAsFactors = FALSE
  )
}
