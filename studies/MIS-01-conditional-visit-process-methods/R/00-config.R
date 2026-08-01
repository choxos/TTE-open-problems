## Study MIS-01: configuration.
##
## The reviewed ADEMP protocol is the specification. Constants, scenario axes,
## method labels, and decision thresholds are centralized here.

MASTER_SEED <- 20260801L
WORKERS <- 6L
N_PEOPLE <- 1000L
N_REP <- 20L
N_MONTHS <- 24L
HORIZONS <- c(12L, 24L)

## Runtime scaling is required. The full design contains 208000 data sets and
## 19.968 billion person-months. With six workers, a 12 hour ceiling, and the
## required 25 percent reserve, it allows only 0.997 CPU seconds per data set.
## That is less than the cost of one 50-imputation analysis. The executable
## default contains 4160 data sets and 99.84 million person-months, a 200-fold
## reduction. It allows 49.8 CPU seconds per data set under the same ceiling.
## Critique fix: this is explicitly a resource-gated scaled run. With fewer than
## 900 replicates per confirmatory environment, its decision must be reported as
## uninformative under the protocol thresholds.

MI_CANDIDATES <- c(50L, 100L, 200L, 400L, 800L)
MI_PILOT_DATASETS <- 10L
MI_POINT_TOL <- 0.001
MI_RELSE_TOL <- 0.02

## The independent MI pilot was specified for 100 data sets. It is reduced to
## 10 here, a further ten-fold reduction required by the overnight limit. The
## candidate grid and acceptance tolerances are unchanged.

TRUTH_CHECK_N <- 200000L
TRUTH_CHECK_CHUNK <- 50000L
## Exact truth is not scaled. Only the stochastic cross-check is reduced from
## two million to 200000 people per strategy. Its acceptance radius remains the
## larger of 0.001 and three simulation standard errors.

WEIGHT_CAP <- 10
CALIBRATION_TOL <- 1e-8
CALIBRATION_MAXIT <- 80L
COND_LIMIT <- 1e12

METHODS <- c(
  'oracle', 'complete_record', 'locf', 'mar_mi', 'iiw_raw',
  'iiw_capped', 'iiw_calibrated', 'visit_process', 'joint_latent'
)
ESTIMANDS <- c('rd12', 'rd24', 'log_rr24')
VISIT_AWARE <- c('mar_mi', 'iiw_raw', 'iiw_capped',
                 'iiw_calibrated', 'visit_process', 'joint_latent')

DECISION <- list(
  minimum_oracle_pairs = 56L,
  oracle_abs_bias_upper = 0.005,
  oracle_coverage_low = 0.925,
  oracle_coverage_high = 0.975,
  oracle_convergence_lower = 0.99,
  material_count = 24L,
  material_profiles = 8L,
  material_abs_bias_lower = 0.02,
  material_coverage_upper = 0.90,
  material_null_al = 8L,
  material_null_yal = 8L,
  paired_material_count = 16L,
  paired_material_profiles = 6L,
  paired_abs_bias_lower = 0.01,
  aware_adequate_count = 48L,
  aware_adequate_profiles = 12L,
  adequate_abs_bias_upper = 0.01,
  adequate_coverage_low = 0.925,
  adequate_coverage_high = 0.975,
  adequate_convergence_lower = 0.95,
  negative_count = 56L,
  negative_pair_upper = 0.005,
  negative_material_max = 4L,
  minimum_valid_datasets = 900L
)

profile_grid <- function() {
  g <- expand.grid(
    beta_AL = c(0, 0.45),
    beta_YL = c(0, 0.60),
    beta_YAL = c(0, 0.15),
    beta_LL = c(0, 1.05),
    stringsAsFactors = FALSE
  )
  g$profile_id <- sprintf('AL%s-YL%s-YAL%s-LL%s',
    ifelse(g$beta_AL == 0, '0', 'w'),
    ifelse(g$beta_YL == 0, '0', 'w'),
    ifelse(g$beta_YAL == 0, '0', 'w'),
    ifelse(g$beta_LL == 0, '0', 'w'))
  g
}

scenario_columns <- c(
  'panel', 'profile_id', 'beta_AL', 'beta_YL', 'beta_YAL', 'beta_LL',
  'gamma_L', 'gamma_A', 'obs_target', 'alpha_fixed',
  'dep_transition', 'dep_observation', 'dep_treatment_outcome'
)

complete_columns <- function(x) {
  for (nm in scenario_columns) if (!nm %in% names(x)) x[[nm]] <- NA
  x[, scenario_columns, drop = FALSE]
}

build_scenarios <- function() {
  p <- profile_grid()
  caxis <- expand.grid(
    gamma_L = c(0, 1.386294),
    gamma_A = c(0, 0.693147),
    obs_target = c(0.30, 0.08),
    stringsAsFactors = FALSE
  )
  confirm <- merge(p, caxis)
  confirm$panel <- 'confirmatory'
  confirm$alpha_fixed <- NA_real_
  confirm$dep_transition <- FALSE
  confirm$dep_observation <- FALSE
  confirm$dep_treatment_outcome <- FALSE

  strong <- expand.grid(
    gamma_L = c(0, 0.693147, 1.386294),
    gamma_A = c(0, 0.693147),
    obs_target = c(0.30, 0.08),
    stringsAsFactors = FALSE
  )
  strong$panel <- 'strong_benchmark'
  strong$profile_id <- 'strong'
  strong$beta_AL <- 0.95
  strong$beta_YL <- 1.20
  strong$beta_YAL <- 0.30
  strong$beta_LL <- 2.10
  strong$alpha_fixed <- NA_real_
  strong$dep_transition <- FALSE
  strong$dep_observation <- FALSE
  strong$dep_treatment_outcome <- FALSE

  fixed_profiles <- data.frame(
    profile_id = c('all_null', 'all_weak', 'strong'),
    beta_AL = c(0, 0.45, 0.95),
    beta_YL = c(0, 0.60, 1.20),
    beta_YAL = c(0, 0.15, 0.30),
    beta_LL = c(0, 1.05, 2.10),
    stringsAsFactors = FALSE
  )
  faxis <- expand.grid(
    gamma_L = c(0, 0.693147, 1.386294),
    gamma_A = c(0, 0.693147),
    alpha_fixed = c(-0.847298, -2.442347),
    stringsAsFactors = FALSE
  )
  fixed <- merge(fixed_profiles, faxis)
  fixed$panel <- 'fixed_intercept'
  fixed$obs_target <- NA_real_
  fixed$dep_transition <- FALSE
  fixed$dep_observation <- FALSE
  fixed$dep_treatment_outcome <- FALSE

  challenge <- expand.grid(
    dep_transition = c(FALSE, TRUE),
    dep_observation = c(FALSE, TRUE),
    dep_treatment_outcome = c(FALSE, TRUE),
    gamma_L = c(0, 1.386294),
    obs_target = c(0.30, 0.08),
    stringsAsFactors = FALSE
  )
  challenge$panel <- 'challenge'
  challenge$profile_id <- 'all_weak'
  challenge$beta_AL <- 0.45
  challenge$beta_YL <- 0.60
  challenge$beta_YAL <- 0.15
  challenge$beta_LL <- 1.05
  challenge$gamma_A <- 0.693147
  challenge$alpha_fixed <- NA_real_

  ## Critique fixes: the confirmatory coefficients form the complete null and
  ## weak factorial; alpha is calibrated there; three misspecification axes are
  ## independently crossed. Fixed-intercept and strong mechanisms are labeled
  ## descriptive and cannot enter the primary decision.
  out <- rbind(
    complete_columns(confirm), complete_columns(strong),
    complete_columns(fixed), complete_columns(challenge)
  )
  stopifnot(nrow(out) == 208L)
  out$sid <- seq_len(nrow(out))
  out$decision_eligible <- out$panel == 'confirmatory'
  out$variant_set <- ifelse(out$panel == 'challenge', 'shared_and_aware',
                            'compatible')
  out$mechanism_family <- ifelse(
    out$panel == 'confirmatory', paste0('confirm-', out$profile_id),
    ifelse(out$panel == 'challenge',
      paste0('challenge-', as.integer(out$dep_transition),
             as.integer(out$dep_observation),
             as.integer(out$dep_treatment_outcome)),
      paste0(out$panel, '-', out$profile_id)))
  out$crn_group <- with(out, paste(
    panel, profile_id, beta_AL, beta_YL, beta_YAL, beta_LL,
    gamma_A, obs_target, alpha_fixed,
    dep_transition, dep_observation, dep_treatment_outcome, sep = '|'))
  out
}

analysis_variants <- function(scen) {
  if (scen$panel == 'challenge') c('shared', 'aware') else 'compatible'
}

truth_check_sids <- function(scenarios) {
  cc <- scenarios[scenarios$panel == 'confirmatory', ]
  ch <- scenarios[scenarios$panel == 'challenge', ]
  unique(c(head(cc$sid, 2L), tail(cc$sid, 2L),
           head(ch$sid, 2L), tail(ch$sid, 2L)))
}
