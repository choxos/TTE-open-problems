## GMT-04 benchmark: frozen configuration.

MASTER_SEED <- 20260801L
TRUTH_VALIDATION_SEED <- 20260811L
ANALYSIS_SEED <- 20260821L

## Budget amendment applied before viewing results. The protocol estimate was
## 104000 ltmle fits times 5 seconds at n = 4000, or 144.4 core hours and 24.1
## ideal hours on six workers before overhead. Assuming fit time is linear in n,
## n = 1200 gives 1.5 seconds per fit, 43.3 core hours, and 7.2 ideal hours.
## This preserves all 2000 replicates and therefore preserves the declared Monte
## Carlo precision and decision thresholds. The timing pilot can still stop the
## main study if the measured resource estimate exceeds the overnight ceiling.
N_PER_REPLICATE <- 1200L
N_REP <- 2000L
N_VISITS <- 6L
VISITS <- 0:5
HORIZON_MONTHS <- 36L
WORKERS <- 6L
OVERNIGHT_HOURS <- 12

PROB_BOUNDS <- c(0.01, 0.99)
DISAGREEMENT_THRESHOLD <- 0.03
PRIMARY_PROBABILITY_THRESHOLD <- 0.20
COMPLETE_TRIPLET_THRESHOLD <- 0.95
HIDDEN_AGREEMENT_THRESHOLD <- 0.01
HIDDEN_ERROR_THRESHOLD <- 0.02
GROSS_ERROR_THRESHOLD <- 0.03

COEFFICIENT_CUTOFFS <- c(10, 20, 30)
CONDITION_CUTOFFS <- c(1e8, 1e10, 1e12)
BOOTSTRAP_REPS <- 400L
BOOTSTRAP_IDS <- 1:25
MSE_BOOTSTRAP_REPS <- 10000L
CALIBRATION_BOOTSTRAP_REPS <- 10000L
PILOT_REPS <- 10L

TRUTH_VALIDATION_N <- 5000000L
TRUTH_VALIDATION_CHUNK <- 250000L
TRUTH_MASS_TOLERANCE <- 1e-12
TRUTH_MCSE_MULTIPLIER <- 3
REQUIRED_LTMLE_VERSION <- '1.3.0'

OVERLAP_SCALES <- c(0.60, 1.00, 1.70)
NUISANCE_ROLES <- data.frame(
  role = c('G0Q0', 'G1Q0', 'G0Q1', 'G1Q1'),
  delta_g = c(0, 1, 0, 1),
  delta_q = c(0, 0, 1, 1),
  stringsAsFactors = FALSE
)

build_scenarios <- function() {
  mechanisms <- expand.grid(
    s = OVERLAP_SCALES,
    role = NUISANCE_ROLES$role,
    stringsAsFactors = FALSE
  )
  mechanisms <- merge(mechanisms, NUISANCE_ROLES, by = 'role', sort = FALSE)
  mechanisms <- mechanisms[order(match(mechanisms$s, OVERLAP_SCALES),
                                 match(mechanisms$role, NUISANCE_ROLES$role)), ]

  factorial <- do.call(rbind, lapply(seq_len(nrow(mechanisms)), function(i) {
    x <- mechanisms[rep(i, 2), , drop = FALSE]
    x$observed_u <- c(TRUE, FALSE)
    x
  }))
  factorial$type <- 'factorial'
  factorial$control <- NA_character_
  factorial$truth_key <- ifelse(factorial$delta_q == 0, 'deltaQ0', 'deltaQ1')

  controls <- data.frame(
    role = c('C0', 'C1'),
    s = c(NA_real_, 1.00),
    delta_g = c(0, 0),
    delta_q = c(0, 2),
    observed_u = TRUE,
    type = 'calibration',
    control = c('C0', 'C1'),
    truth_key = c('C0', 'C1'),
    stringsAsFactors = FALSE
  )

  out <- rbind(factorial[, names(controls)], controls)
  out$analysis_scenario <- seq_len(nrow(out))
  out$scenario_label <- ifelse(
    out$type == 'factorial',
    sprintf('s%.2f-%s-%s', out$s, out$role,
            ifelse(out$observed_u, 'observed-U', 'hidden-U')),
    out$control
  )
  out$primary <- out$type == 'factorial' & out$observed_u &
    out$s %in% c(0.60, 1.00) & out$role %in% c('G0Q0', 'G1Q1')
  out$hidden_u <- out$type == 'factorial' & !out$observed_u

  ## Critique fix: the selective quadrants are positive controls only.
  out$selective_positive_control <- out$role %in% c('G1Q0', 'G0Q1')

  ## Critique fix: four anchors validate the nuisance-adjusted IPTW interval.
  out$bootstrap_anchor <-
    (out$type == 'factorial' & out$observed_u & out$s == 1.00 & out$role == 'G0Q0') |
    (out$type == 'factorial' & out$observed_u & out$s == 1.00 & out$role == 'G1Q1') |
    (out$type == 'factorial' & !out$observed_u & out$s == 1.00 & out$role == 'G0Q0') |
    (out$type == 'factorial' & out$observed_u & out$s == 1.70 & out$role == 'G0Q0')

  rownames(out) <- NULL
  out
}

build_run_scenarios <- function() {
  analysis <- build_scenarios()
  factorial <- analysis[analysis$type == 'factorial', ]
  keys <- unique(factorial[, c('s', 'role', 'delta_g', 'delta_q')])
  runs <- lapply(seq_len(nrow(keys)), function(i) {
    z <- keys[i, ]
    ids <- factorial$analysis_scenario[factorial$s == z$s & factorial$role == z$role]
    data.frame(s = z$s, role = z$role, delta_g = z$delta_g,
               delta_q = z$delta_q, control = NA_character_,
               analysis_ids = paste(ids, collapse = ','), stringsAsFactors = FALSE)
  })
  runs <- do.call(rbind, runs)
  controls <- analysis[analysis$type == 'calibration', ]
  control_runs <- data.frame(
    s = controls$s, role = controls$role, delta_g = controls$delta_g,
    delta_q = controls$delta_q, control = controls$control,
    analysis_ids = as.character(controls$analysis_scenario),
    stringsAsFactors = FALSE
  )
  out <- rbind(runs, control_runs)
  out$scenario <- seq_len(nrow(out))
  out <- out[, c('scenario', 's', 'role', 'delta_g', 'delta_q',
                 'control', 'analysis_ids')]
  rownames(out) <- NULL
  out
}

ANALYSIS_SCENARIOS <- build_scenarios()
RUN_SCENARIOS <- build_run_scenarios()
stopifnot(nrow(ANALYSIS_SCENARIOS) == 26L)
