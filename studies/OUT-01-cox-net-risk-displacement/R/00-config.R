## OUT-01 mechanism study: configuration.
##
## This implementation is deliberately limited to standardized death-censored
## Cox net-risk displacement. It does not issue a verdict for OUT-01 as a whole.

MASTER_SEED <- 20260801L
TRUTH_PROFILE_SEED <- 31000000L
VALIDATION_DATA_SEED <- 32000000L
VALIDATION_BOOTSTRAP_SEED <- 33000000L
BENCHMARK_SEED <- 34000000L

N_PER_REPLICATE <- 4000L
HORIZONS <- c(12L, 36L, 60L)
INTERVAL_ENDS <- HORIZONS
INTERVAL_WIDTHS <- c(12, 24, 24)
WORKERS <- 6L
WALD_MULTIPLIER <- 1.959964

## Budget scaling. The protocol requests 36 * 4000 * 2 = 288000 production
## Cox fits. The required bootstrap validation adds 3 * 1000 * 2 = 6000 fits,
## and the required production benchmark adds 3 * 100 * 2 = 600 fits. The
## unscaled total is therefore 294600 fits before retries. Using 1000 replicates
## gives 72000 production fits and 78600 total fits, a 73.3% reduction, while
## retaining n = 4000 and all 1000 bootstrap resamples. The runtime benchmark in
## 04-run.R must still project completion within the 12-hour ceiling.
N_REP_PROTOCOL <- 4000L
N_REP <- 1000L
OVERNIGHT_HOURS <- 12

N_TRUTH_INITIAL <- 2000000L
TRUTH_BATCH_SIZE <- 10000L
TRUTH_INITIAL_BATCHES <- N_TRUTH_INITIAL %/% TRUTH_BATCH_SIZE
TRUTH_MCSE_LIMIT <- 0.0005
DISPLACEMENT_THRESHOLD <- 0.010
SIGN_TOLERANCE <- 0.001

BOOTSTRAP_B <- 1000L
BOOTSTRAP_CHECKPOINT <- 25L
IF_BOOTSTRAP_TOLERANCE <- 0.05
BENCHMARK_REPLICATES <- 100L

PRIMARY_BASE_HAZARDS <- c(0.0025, 0.0040, 0.0060)
DEATH_BASE_HAZARDS <- list(
  low = c(0.0005, 0.0008, 0.0012),
  moderate = c(0.0018, 0.0030, 0.0045),
  high = c(0.0040, 0.0070, 0.0100)
)

BETA_DA <- c(
  harmful = 0.510826,
  neutral = 0,
  protective = -0.510826
)

## Critique fix: harmful and protective death effects are log-symmetric around
## the neutral effect. The grid therefore examines both opportunity directions.
PRIMARY_EFFECTS <- data.frame(
  outcome_effect_key = c("null", "heterogeneous_protective"),
  beta_YA = c(0, -0.510826),
  beta_YAC = c(0, 0.405465),
  stringsAsFactors = FALSE
)

## Critique fix: this factor is additional Q prognosis. Z, M, C, and S remain
## shared prognostic causes even when gamma equals zero.
GAMMA_Q <- c(none = 0, strong = 0.693147)

METHODS <- c("death_censored_net", "multistate_total")

build_scenarios <- function() {
  g <- expand.grid(
    mortality_key = names(DEATH_BASE_HAZARDS),
    death_effect_key = names(BETA_DA),
    outcome_effect_key = PRIMARY_EFFECTS$outcome_effect_key,
    q_key = names(GAMMA_Q),
    stringsAsFactors = FALSE
  )
  g$scenario <- seq_len(nrow(g))
  g$beta_DA <- unname(BETA_DA[g$death_effect_key])
  g$gamma <- unname(GAMMA_Q[g$q_key])
  m <- match(g$outcome_effect_key, PRIMARY_EFFECTS$outcome_effect_key)
  g$beta_YA <- PRIMARY_EFFECTS$beta_YA[m]
  g$beta_YAC <- PRIMARY_EFFECTS$beta_YAC[m]
  g[, c("scenario", "mortality_key", "death_effect_key",
        "outcome_effect_key", "q_key", "beta_DA", "gamma",
        "beta_YA", "beta_YAC")]
}

death_hazards_for <- function(scen) {
  DEATH_BASE_HAZARDS[[as.character(scen$mortality_key[[1]])]]
}

benchmark_scenarios <- function() {
  g <- build_scenarios()
  keep <- g$death_effect_key == "neutral" &
    g$outcome_effect_key == "heterogeneous_protective" &
    g$q_key == "strong"
  g <- g[keep, , drop = FALSE]
  g[match(names(DEATH_BASE_HAZARDS), g$mortality_key), , drop = FALSE]
}

truth_lock_spec <- function() {
  list(
    horizons = HORIZONS,
    interval_widths = INTERVAL_WIDTHS,
    primary_base_hazards = PRIMARY_BASE_HAZARDS,
    death_base_hazards = DEATH_BASE_HAZARDS,
    scenarios = build_scenarios(),
    truth_batch_size = TRUTH_BATCH_SIZE,
    truth_initial_batches = TRUTH_INITIAL_BATCHES,
    truth_mcse_limit = TRUTH_MCSE_LIMIT
  )
}
