## Study LRN-05: configuration.
##
## This implementation supplies scenario-specific operating characteristics for
## static binary sustained strategies. It does not issue a catalog-level verdict.

MASTER_SEED <- 20260801L
WORKERS <- 6L

## Budget scaling required by the execution ceiling.
## The reviewed design requires 24 * 2000 * 4000 * 24 = 4,608,000,000 person-month
## updates in the minimum final run, plus 1,152,000,000 pilot updates. The fitted
## sandwich also requires centered finite differences after two GLM fits in every
## replicate. We retain the 2000-replicate Monte Carlo minimum but reduce each
## replicate from 4000 to 1000 individuals. The final run therefore contains
## 1,152,000,000 person-month updates and the pilot contains 288,000,000. The
## resource cap is 2000 final replicates per scenario. A pilot requirement above
## that cap is recorded as a precision shortfall and classified as uninformative.
N_PER_REP <- 1000L
N_MONTHS <- 24L
N_PILOT <- 500L
N_REP_MIN <- 2000L
N_REP_PROTOCOL_CAP <- 10000L
N_REP_BUDGET_CAP <- 2000L
N_REP <- N_REP_BUDGET_CAP

N_TRUTH_MC <- 2000000L
N_TRUTH_BATCHES <- 20L
TRUTH_QUAD_ORDERS <- c(128L, 256L, 512L, 1024L)
TRUTH_CURVE_TOL <- 0.00025
TRUTH_SCALAR_TOL <- 0.0001
TRUTH_MC_TOL <- 0.0005

P_U <- 0.30

PROFILE <- data.frame(
  profile = paste0('P', 0:11),
  gamma = c(0, log(0.80), log(4.00), 0, 0, log(1.25), log(2.50),
            log(4.00), log(0.80), log(0.40), log(2.50), log(0.40)),
  delta = c(0, 0, 0, log(1.25), log(2.00), log(1.25), log(1.50),
            log(2.00), log(1.25), log(2.00), log(0.75), log(0.75)),
  label = c(
    'joint null',
    'treatment-only weak reverse',
    'treatment-only strong positive',
    'outcome-only weak harmful',
    'outcome-only strong harmful',
    'weak positive and harmful',
    'moderate positive and harmful',
    'strong positive and harmful',
    'weak reverse and harmful',
    'strong reverse and harmful',
    'positive selection with partial cancellation',
    'reverse selection with partial cancellation'
  ),
  stringsAsFactors = FALSE
)

SUPPORT <- data.frame(
  support = c('adequate', 'stressed'),
  alpha = c(-0.50, -2.00),
  stringsAsFactors = FALSE
)

build_scenarios <- function() {
  z <- expand.grid(profile_index = seq_len(nrow(PROFILE)),
                   support_index = seq_len(nrow(SUPPORT)),
                   KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  z$scenario <- seq_len(nrow(z))
  z$profile <- PROFILE$profile[z$profile_index]
  z$profile_label <- PROFILE$label[z$profile_index]
  z$gamma <- PROFILE$gamma[z$profile_index]
  z$delta <- PROFILE$delta[z$profile_index]
  z$support <- SUPPORT$support[z$support_index]
  z$alpha <- SUPPORT$alpha[z$support_index]
  z$joint_confounding <- abs(z$gamma) > 1e-14 & abs(z$delta) > 1e-14
  delta_key <- format(z$delta, digits = 15, scientific = FALSE)
  z$truth_group <- match(delta_key, unique(delta_key))
  z[, c('scenario', 'profile', 'profile_label', 'gamma', 'delta',
        'support', 'alpha', 'joint_confounding', 'truth_group')]
}

METHODS <- c('full_history', 'exact_complete', 'exact_reduced',
             'fitted_reduced', 'unweighted')
STRATEGIES <- c('g0', 'g1')
SCORES <- c('oracle', 'miscalibrated')

SPLINE_DF_X1 <- 5L
SPLINE_DF_MONTH <- 5L
NEWTON_TOL <- 1e-8
NEWTON_MAXIT <- 50L
HESSIAN_KAPPA_MAX <- 1e12
FINITE_DIFF_SCALE <- 1e-6
SINGULAR_RATIO <- 1e-10

DIAG_ESS_FRAC <- 0.25
DIAG_MAX_WEIGHT <- 50
DIAG_LOW_PROB <- 0.05
DIAG_LOW_PROPORTION <- 0.01

MC_Z <- stats::qnorm(0.975)
MC_Z_BINS <- stats::qnorm(1 - 0.05 / (2 * 10))

## Critique implementation: declarations use Monte Carlo bounds and an
## indifference region. Calibration-bin bounds use the simultaneous critical
## value above. No count of scenarios becomes a catalog-level declaration.
DECISION_LIMITS <- data.frame(
  family = c('cal_intercept', 'calibration_curve', 'brier', 'auc'),
  consequential = c(0.10, 0.02, 0.01, 0.02),
  negligible = c(0.05, 0.01, 0.005, 0.01),
  stringsAsFactors = FALSE
)

metric_family <- function(metric) {
  if (identical(metric, 'cal_intercept')) return('cal_intercept')
  if (grepl('^cal_bin_', metric)) return('calibration_curve')
  if (identical(metric, 'brier')) return('brier')
  if (identical(metric, 'auc')) return('auc')
  if (identical(metric, 'cal_slope')) return('cal_slope')
  if (identical(metric, 'risk')) return('risk')
  metric
}

decision_limit <- function(family, column) {
  i <- match(family, DECISION_LIMITS$family)
  ifelse(is.na(i), NA_real_, DECISION_LIMITS[[column]][i])
}

precision_target <- function(metric) {
  fam <- metric_family(metric)
  switch(fam,
    cal_intercept = c(z = MC_Z, h = 0.01),
    calibration_curve = c(z = MC_Z_BINS, h = 0.005),
    brier = c(z = MC_Z, h = 0.002),
    auc = c(z = MC_Z, h = 0.005),
    c(z = NA_real_, h = NA_real_)
  )
}

anchor_scenarios <- function(scenarios = build_scenarios()) {
  which((scenarios$profile %in% c('P0', 'P7')) &
          (scenarios$support %in% c('adequate', 'stressed')))
}
