## Study PRO-04: configuration.
##
## This is a conditional benchmark for three coherently formalized protocol
## substitutions. It does not detect, name, or establish the causal coherence of
## an unknown operational target.

MASTER_SEED <- 20260731L
N_WORKERS <- 6L
VALIDATION_PROB <- 0.50

## The reviewed protocol requested 2,500 replicates in each of 24 strata. That
## requires 60,000 datasets and 300,000 five-fold fits after the power-selected
## sample size is applied. The overnight budget permits 1,000 replicates per
## stratum: 24,000 datasets and 120,000 fold fits. Person-record processing falls
## from 60,000 * N to 24,000 * N, a 60 percent reduction. Worst-case probability
## MCSE rises from 0.0100 to sqrt(0.25 / 1000) = 0.0158. The diagnostic sample
## size is not reduced because it is selected by the prespecified power rule.
N_REP_PROTOCOL <- 2500L
N_REP <- 1000L
PILOT_REP <- 100L

COMPONENTS <- c(
  eligibility = 'Eligibility',
  strategy = 'Treatment strategy',
  outcome = 'Outcome'
)
FIDELITY_LEVELS <- c('mild', 'severe')
EFFECT_MODIFICATION_LEVELS <- c('absent', 'present')
DEPENDENCE_LEVELS <- c('nondifferential', 'differential')

ELIGIBILITY_RANGES <- list(
  mild = list(sensitivity = c(0.88, 0.96), specificity = c(0.93, 0.98)),
  severe = list(sensitivity = c(0.65, 0.80), specificity = c(0.80, 0.90))
)
STRATEGY_Q_RANGES <- list(mild = c(0.75, 0.95), severe = c(0.40, 0.65))
OUTCOME_SENSITIVITY_RANGES <- list(mild = c(0.85, 0.95), severe = c(0.60, 0.80))
OUTCOME_SPECIFICITY_RANGE <- c(0.990, 0.999)
DIFFERENTIAL_SLOPE_RANGE <- c(0.5, 1.5)

PRESERVATION_MARGIN <- 0.01
MATERIAL_MARGIN <- 0.02
DIAGNOSTIC_PRESERVING_TRUTH <- 0.005
DIAGNOSTIC_CHANGED_TRUTH <- 0.03
DIAGNOSTIC_CHANGE_BOUNDARY <- 0.01

MARGIN_PAIRS <- data.frame(
  label = c('main', 'narrow', 'wide'),
  preservation = c(0.010, 0.005, 0.020),
  material = c(0.020, 0.015, 0.030),
  stringsAsFactors = FALSE
)

TRUTH_START_NODES <- 128L
TRUTH_MAX_NODES <- 2048L
TRUTH_TOL <- 1e-7
TRUTH_CLASS_TOL <- 1e-8
CALIBRATION_NODES <- 256L
CALIBRATION_TOL <- 1e-9

## Deterministic multistart search settings for the prespecified worst-case
## asymptotic variance calculation. Final candidates are re-evaluated with
## successively doubled quadrature before N is selected.
POWER_RULE_VERSION <- 'pro04-power-v1'
POWER_START_NODES <- 32L
POWER_MAX_NODES <- 256L
POWER_STARTS <- 3L
POWER_MAXIT <- 35L
POWER_VARIANCE_INFLATION <- 1.10
POWER_TARGET <- 0.80
MAX_EXPECTED_INTERVAL_WIDTH <- 0.04

BOOTSTRAP_REPS <- 2000L
METHODS <- c('silent', 'operational', 'validation', 'augmented',
             'oracle', 'gap_cc', 'gap_aug')

fidelity_bounds <- function(component, fidelity) {
  if (component == 'eligibility') return(ELIGIBILITY_RANGES[[fidelity]])
  if (component == 'strategy') return(list(q = STRATEGY_Q_RANGES[[fidelity]]))
  if (component == 'outcome') {
    return(list(sensitivity = OUTCOME_SENSITIVITY_RANGES[[fidelity]],
                specificity = OUTCOME_SPECIFICITY_RANGE))
  }
  stop('Unknown component: ', component)
}

build_scenarios <- function() {
  g <- expand.grid(
    component = names(COMPONENTS),
    fidelity = FIDELITY_LEVELS,
    effect_modification = EFFECT_MODIFICATION_LEVELS,
    dependence = DEPENDENCE_LEVELS,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  g$component_label <- unname(COMPONENTS[g$component])
  g$scenario <- seq_len(nrow(g))
  g[, c('scenario', 'component', 'component_label', 'fidelity',
        'effect_modification', 'dependence')]
}

CONFIG_SIGNATURE <- paste(
  'PRO-04', POWER_RULE_VERSION, N_REP, VALIDATION_PROB,
  TRUTH_START_NODES, TRUTH_MAX_NODES, sep = '|'
)
