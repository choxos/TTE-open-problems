## ELG-01: run the paired design.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:1
##
## The optional slice uses the published 48-scenario numbering. Selecting one
## scenario runs its packed cell and therefore also writes its five paired arms.

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
stopifnot(file.exists(file.path(OUTDIR, 'recording-calibration.rds')))
stopifnot(file.exists(file.path(OUTDIR, 'truth.rds')))
set_recording_alphas(readRDS(file.path(OUTDIR, 'recording-calibration.rds')))
ALL_SCENARIOS <- build_scenarios()
RUN_CELLS <- build_run_cells(ALL_SCENARIOS)
METHODS <- method_grid()

key_for <- function(method, variant) paste(method, variant, sep = '|')
try_est <- function(fn) tryCatch(fn(), error = function(e) {
  failure_result(paste0('error:', conditionMessage(e)))
})

result_row <- function(spec, target_scenario, pair_rep, x, true_ne, nre,
                       observed_identity, nv_identity, m50_scheduled) {
  getv <- function(name, default = NA_real_) {
    if (is.null(x) || is.null(x[[name]])) default else x[[name]]
  }
  scheduled <- if (spec$method %in% c('mi_continuous_m50', 'mi_indicator_m50')) {
    m50_scheduled
  } else TRUE
  if (!is.null(x$scheduled)) scheduled <- isTRUE(x$scheduled)
  data.frame(
    target_scenario = as.integer(target_scenario),
    pair_rep = as.integer(pair_rep),
    method = spec$method,
    variant = spec$variant,
    information_set = spec$information_set,
    target = spec$target,
    lambda_star = spec$lambda_star,
    est = getv('est'), se = getv('se'), lo = getv('lo'), hi = getv('hi'),
    pe_est = getv('pe_est'), ne_est = getv('ne_est'), pe_se = getv('pe_se'),
    within_var = getv('within_var'), between_var = getv('between_var'),
    df = getv('df'), ess0 = getv('ess0'), ess1 = getv('ess1'),
    max_weight = getv('max_weight'),
    bound_lo = getv('bound_lo'), bound_hi = getv('bound_hi'),
    bound_ci_lo = getv('bound_ci_lo'), bound_ci_hi = getv('bound_ci_hi'),
    bound_se_lo = getv('bound_se_lo'), bound_se_hi = getv('bound_se_hi'),
    pe_lower = getv('pe_lower'), pe_upper = getv('pe_upper'),
    true_ne = true_ne, nre = nre, nre_yield = nre / N_PER_REP,
    obs_identity = observed_identity, nv_identity = nv_identity,
    scheduled = scheduled,
    fail = as.character(getv('fail', NA_character_)),
    stringsAsFactors = FALSE
  )
}

blank_cell <- function(cell, rep_id, why) {
  targets <- ALL_SCENARIOS[ALL_SCENARIOS$run_cell == cell$run_cell, , drop = FALSE]
  m50 <- ((rep_id - 1L) %% MI_CHECK_MODULUS) == 0L
  rows <- vector('list', nrow(targets) * nrow(METHODS))
  at <- 0L
  for (i in seq_len(nrow(targets))) {
    for (j in seq_len(nrow(METHODS))) {
      at <- at + 1L
      scheduled <- !(METHODS$method[j] %in% c('mi_continuous_m50',
                                              'mi_indicator_m50')) || m50
      fail <- if (scheduled) why else 'not-scheduled'
      x <- failure_result(fail)
      x$scheduled <- scheduled
      rows[[at]] <- result_row(METHODS[j, ], targets$scenario[i], rep_id, x,
                               NA_real_, NA_real_, FALSE, FALSE, m50)
    }
  }
  do.call(rbind, rows)
}

one_rep <- function(scen, rep_id) {
  targets <- ALL_SCENARIOS[ALL_SCENARIOS$run_cell == scen$run_cell, , drop = FALSE]
  cell <- scen
  cell$alpha_m <- ALPHA_M[match(cell$m, MISSING_PROPORTIONS)]
  paired <- tryCatch(gen_paired_replicate(cell, rep_id), error = function(e) e)
  if (inherits(paired, 'error')) {
    return(blank_cell(scen, rep_id, paste0('dgm-failed:', conditionMessage(paired))))
  }

  dat <- paired$dat
  reference <- paired$arms[['lambda_0']]
  dat$Gobs <- reference$G_obs
  dat$Eobs <- reference$E_obs
  dat$RE <- ifelse(dat$R == 1L, reference$E, 0)
  nre <- sum(dat$RE)
  m50_scheduled <- ((rep_id - 1L) %% MI_CHECK_MODULUS) == 0L
  trt <- fit_treatment(dat)
  common <- list()

  if (is.na(trt$fail[1L])) {
    common[[key_for('complete_case', 'primary')]] <- try_est(function() {
      ## Critique fix: this estimator is analyzed against RD60,RE, not RD60,E.
      fixed_membership_estimate(dat, trt, dat$RE)
    })

    XE <- eligibility_matrix(dat, 'recorded')
    observed <- which(dat$R == 1L)
    ols <- safe_ols(XE[observed, , drop = FALSE], dat$Gobs[observed])
    efit <- safe_logit(XE[observed, , drop = FALSE], dat$Eobs[observed])
    if (is.na(efit$fail[1L])) efit <- extend_logit(efit, XE)
    Mmax <- if (m50_scheduled) MI_CHECK else MI_PRIMARY

    mic <- try_est(function() run_mi_continuous(dat, trt, ols, Mmax))
    if (!is.null(mic$m20)) {
      common[[key_for('mi_continuous', 'm20')]] <- mic$m20
      common[[key_for('mi_continuous_m50', 'm50')]] <- if (m50_scheduled) {
        mic$m50
      } else {
        z <- failure_result('not-scheduled'); z$scheduled <- FALSE; z
      }
    } else {
      common[[key_for('mi_continuous', 'm20')]] <- mic
    }

    mie <- try_est(function() run_mi_indicator(dat, trt, efit, XE, Mmax))
    if (!is.null(mie$m20)) {
      common[[key_for('mi_indicator', 'm20')]] <- mie$m20
      common[[key_for('mi_indicator_m50', 'm50')]] <- if (m50_scheduled) {
        mie$m50
      } else {
        z <- failure_result('not-scheduled'); z$scheduled <- FALSE; z
      }
    } else {
      common[[key_for('mi_indicator', 'm20')]] <- mie
    }

    Xs <- recording_matrix(dat)
    rfit <- safe_logit(Xs, dat$R)
    if (is.na(rfit$fail[1L])) rfit <- extend_logit(rfit, Xs)
    common[[key_for('mar_ipaw', 'primary')]] <- try_est(function() {
      estimate_mar_ipaw(dat, trt, rfit)
    })
    common[[key_for('oracle_recording_ipaw', 'primary')]] <- try_est(function() {
      estimate_oracle_recording(dat, trt)
    })

    for (nm in names(SENSITIVITY_VALUES)) {
      lambda_star <- unname(SENSITIVITY_VALUES[nm])
      common[[key_for('sensitivity', nm)]] <- try_est(function() {
        estimate_sensitivity(dat, trt, efit, lambda_star)
      })
    }
    common[[key_for('bounds', 'primary')]] <- try_est(function() {
      ## Critique fix: this uses the width-adaptive Imbens-Manski construction.
      estimate_bounds(dat, trt)
    })
  }

  if (!m50_scheduled) {
    z <- failure_result('not-scheduled'); z$scheduled <- FALSE
    common[[key_for('mi_continuous_m50', 'm50')]] <- z
    common[[key_for('mi_indicator_m50', 'm50')]] <- z
  }

  oracle_cache <- list()
  if (is.na(trt$fail[1L])) {
    for (nm in names(LAMBDA_VALUES)) {
      oracle_cache[[nm]] <- try_est(function() {
        fixed_membership_estimate(
          dat, trt, paired$arms[[nm]]$E,
          finite_difference = TRUE
        )
      })
    }
  }

  rows <- vector('list', nrow(targets) * nrow(METHODS))
  at <- 0L
  for (i in seq_len(nrow(targets))) {
    target <- targets[i, , drop = FALSE]
    arm <- paired$arms[[target$lambda_key]]
    E <- arm$E
    V <- as.integer(dat$R == 0L & dat$u_validation < target$validation_prob)
    Q <- as.integer(dat$R == 1L | V == 1L)
    rho <- ifelse(dat$R == 1L, 1, target$validation_prob)
    vals <- common

    if (is.na(trt$fail[1L])) {
      vals[[key_for('oracle', 'primary')]] <- oracle_cache[[target$lambda_key]]
      q_primary <- fit_phase_eligibility(dat, E, Q, rho, 'validation_primary')
      q_omit <- fit_phase_eligibility(dat, E, Q, rho, 'validation_omit_ch')
      q_intercept <- fit_phase_eligibility(dat, E, Q, rho, 'intercept_r')

      vals[[key_for('fractional', 'primary')]] <- try_est(function() {
        ## Critique fix: deterministic fractional imputation uses one full
        ## repeated-sampling sandwich. Rubin pooling is not used here.
        estimate_fractional(dat, trt, E, Q, rho, q_primary)
      })
      vals[[key_for('fractional', 'omit_c_h')]] <- try_est(function() {
        ## Critique fix: the prespecified diagnostic omits C and H from q.
        estimate_fractional(dat, trt, E, Q, rho, q_omit)
      })
      vals[[key_for('two_phase_ipw', 'primary')]] <- try_est(function() {
        estimate_two_phase(dat, trt, E, Q, rho)
      })
      vals[[key_for('augmented', 'primary')]] <- try_est(function() {
        estimate_augmented(dat, trt, E, Q, rho, q_primary)
      })
      vals[[key_for('augmented', 'intercept_r')]] <- try_est(function() {
        ## Critique fix: known rho is retained while q is restricted to an
        ## intercept and recording-pattern indicator.
        estimate_augmented(dat, trt, E, Q, rho, q_intercept)
      })
    }

    true_ne <- sum(E)
    default_failure <- if (is.na(trt$fail[1L])) 'estimator-not-produced' else trt$fail
    for (j in seq_len(nrow(METHODS))) {
      at <- at + 1L
      k <- key_for(METHODS$method[j], METHODS$variant[j])
      x <- vals[[k]]
      if (is.null(x)) x <- failure_result(default_failure)
      rows[[at]] <- result_row(
        METHODS[j, ], target$scenario, rep_id, x, true_ne, nre,
        paired$observed_identical,
        ## Every no-validation result is computed once per observed-data cell
        ## and copied to its lambda and validation-budget rows. Equality is
        ## therefore bitwise and does not rely on tolerances.
        paired$observed_identical,
        m50_scheduled
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

args <- commandArgs(TRUE)
requested <- seq_len(nrow(ALL_SCENARIOS))
if (length(args) && grepl('^\\d+:\\d+$', args[1L])) {
  p <- as.integer(strsplit(args[1L], ':', fixed = TRUE)[[1L]])
  requested <- intersect(seq.int(p[1L], p[2L]), requested)
}
selected_cells <- sort(unique(ALL_SCENARIOS$run_cell[
  ALL_SCENARIOS$scenario %in% requested
]))

res <- run_design(
  one_rep, RUN_CELLS, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUTDIR, workers = WORKERS, resume = TRUE, only = selected_cells
)

write_provenance(
  OUTDIR,
  packages = c('stats', 'splines', 'future', 'furrr'),
  extra = list(
    study = 'ELG-01 latent eligibility',
    published_scenarios = nrow(ALL_SCENARIOS),
    packed_run_cells = nrow(RUN_CELLS),
    replicates_per_scenario = N_REP,
    n_per_replicate = N_PER_REP,
    truth_n = N_TRUTH,
    calibration_n = N_CALIBRATION,
    master_seed = MASTER_SEED,
    mi_primary = MI_PRIMARY,
    mi_check = MI_CHECK,
    mi_check_fraction = 1 / MI_CHECK_MODULUS
  )
)
message(sprintf('done: %d returned rows', nrow(res)))
