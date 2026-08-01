## MER-01: configuration.
##
## The critique fixes are encoded in the frozen grid below. The study addresses
## only simple random internal validation with a perfect longitudinal reference.

MASTER_SEED <- 20260801L
N_PER_REPLICATE <- 4000L
N_MONTHS <- 12L
N_TRUTH <- 4000000L
WORKERS <- 6L

## Budget reduction, fixed before results are inspected. The original minimum
## workload was 81 * 1000 * 50 * 12 = 48,600,000 rich monthly propensity fits,
## before calibration, exact filtering, latent optimization, or numerical bread.
## Even at an optimistic 0.01 seconds per fit and perfect six-worker scaling,
## those fits alone require 22.5 hours. The overnight implementation therefore
## uses looks of 25, 50, and 100 replicates and MI candidates of 10, 20, and 40,
## with 80 as the fallback. All 81 scenarios, 4000 participants, four-million
## person truths, estimands, model stresses, and numerical decision thresholds
## remain unchanged. A boundary crossed at the scaled maximum is uninformative.
N_REP_LOOKS <- c(25L, 50L, 100L)
LOOK_INCREMENT <- diff(c(0L, N_REP_LOOKS))
N_REP <- N_REP_LOOKS[1]

## Critique fix: the fixed imputation count is calibrated rather than set to 20.
MI_CANDIDATES <- c(10L, 20L, 40L)
MI_FALLBACK <- 80L
MI_CAL_REFERENCE <- 160L
MI_CAL_REPEATS <- 40L
MI_CAL_TARGET <- 0.001
MI_LARGE_FACTOR <- 4L
MI_LARGE_FRACTION <- 0.10
PRIOR_SENSITIVITY_SD <- c(5, 10)

BREAD_STEP <- 1e-6
BREAD_KAPPA_MAX <- 1e12
TRUTH_MCSE_MAX <- 0.0005
SIM_ALPHA <- 0.01
SIM_LOOKS <- 3L
MULTIPLIER_DRAWS <- 1999L

CONTRASTS <- c('dynamic', 'dynamic_x2_0', 'dynamic_x2_1', 'static')
METHODS <- c('first_order', 'rich_history', 'exact_filtered',
             'corrected_mi', 'oracle_complete', 'corrected_mi_4M',
             'corrected_prior5', 'corrected_prior10')
PROFILES <- c('nondifferential', 'aligned', 'reversed', 'unrelated',
              'no_effect_modification')
SPECIFICATIONS <- c('core', 'treatment_stress', 'confounder_stress',
                    'outcome_stress', 'error_transition_stress')

error_rate_pair <- function(accuracy) {
  key <- sprintf('%.2f', accuracy)
  switch(key,
    '0.70' = c(low = 0.1627, high = 0.4373),
    '0.85' = c(low = 0.0696, high = 0.2304),
    '0.99' = c(low = 0.0040, high = 0.0160),
    '1.00' = c(low = 0, high = 0),
    stop('unsupported accuracy: ', accuracy)
  )
}

build_scenarios <- function() {
  rows <- list()
  add <- function(block, profile, accuracy, error_nodes, validation_n,
                  specification = 'core', outcome_error = FALSE,
                  benchmark = NA_character_, decisive = FALSE) {
    rows[[length(rows) + 1L]] <<- data.frame(
      block = block,
      profile = profile,
      accuracy = as.numeric(accuracy),
      error_nodes = error_nodes,
      validation_n = as.integer(validation_n),
      specification = specification,
      outcome_error = isTRUE(outcome_error),
      benchmark = benchmark,
      decisive = isTRUE(decisive),
      effect_modification = profile != 'no_effect_modification',
      stringsAsFactors = FALSE
    )
  }

  ## Critique fix: dynamic A and L error cells exclude terminal outcome error.
  ## Critique fix: aligned cells remain descriptive, while neutral, reversed,
  ## unrelated, and absent effect-modification cells form the decisive set.
  for (profile in PROFILES) {
    for (accuracy in c(0.70, 0.85)) {
      for (nodes in c('A', 'L', 'AL')) {
        add('primary', profile, accuracy, nodes, 500L,
            decisive = nodes == 'AL' && profile != 'aligned')
      }
    }
  }

  for (profile in PROFILES)
    add('near_null', profile, 0.99, 'AL', 500L)

  ## Critique fix: outcome error is a separate component and cannot determine
  ## the primary MER-01 classification.
  for (accuracy in c(0.70, 0.85, 0.99))
    add('outcome_component', 'nondifferential', accuracy, 'AL', 500L,
        outcome_error = TRUE)

  add('control', 'nondifferential', 1, 'none', 500L)
  add('control', 'no_effect_modification', 1, 'none', 500L)

  ## Critique fix: each validation size is crossed with all four one-at-a-time
  ## latent or error model stresses in both benchmark mechanisms.
  benchmarks <- list(
    nd70 = list(profile = 'nondifferential', accuracy = 0.70),
    un85 = list(profile = 'unrelated', accuracy = 0.85)
  )
  for (b in names(benchmarks)) {
    z <- benchmarks[[b]]
    for (specification in SPECIFICATIONS) {
      for (validation_n in c(100L, 250L, 500L, 1000L)) {
        overlap <- specification == 'core' && validation_n == 500L
        if (!overlap)
          add('robustness', z$profile, z$accuracy, 'AL', validation_n,
              specification = specification, benchmark = b)
      }
    }
  }

  for (specification in c('treatment_stress', 'confounder_stress',
                           'outcome_stress'))
    add('control', 'nondifferential', 1, 'none', 500L,
        specification = specification)

  out <- do.call(rbind, rows)
  out$scenario <- seq_len(nrow(out))

  ## The two core n=500 benchmark cells already occur in the primary block.
  out$benchmark[out$block == 'primary' & out$profile == 'nondifferential' &
                  out$accuracy == 0.70 & out$error_nodes == 'AL'] <- 'nd70'
  out$benchmark[out$block == 'primary' & out$profile == 'unrelated' &
                  out$accuracy == 0.85 & out$error_nodes == 'AL'] <- 'un85'

  out$pair_family <- with(out, paste(profile, sprintf('%.2f', accuracy),
                                     specification, sep = ':'))
  out <- out[, c('scenario', 'block', 'profile', 'accuracy', 'error_nodes',
                 'validation_n', 'specification', 'outcome_error', 'benchmark',
                 'decisive', 'effect_modification', 'pair_family')]
  stopifnot(nrow(out) == 81L)
  rownames(out) <- NULL
  out
}

truth_key_for <- function(scen) {
  if (scen$specification == 'confounder_stress') return('confounder_stress')
  if (scen$specification == 'outcome_stress') return('outcome_stress')
  if (!isTRUE(scen$effect_modification)) return('core_no_effect_modification')
  'core_effect_modified'
}
