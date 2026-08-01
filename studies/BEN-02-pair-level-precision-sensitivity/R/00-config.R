## Study 2 (BEN-02): configuration.
##
## This implementation is restricted to the pair-level precision-conflation
## question stated in the reviewed protocol. The mismatch scenarios are
## alignment diagnostics. They are not positive or negative controls.

MASTER_SEED <- 20260801L
BOOT_SEED   <- 20260802L

N_REP       <- 10000L
N_BOOT      <- 20000L
PILOT_REP   <- 100L
WORKERS     <- 6L

## The full design is retained. There are 16 * 10000 * 3 = 480000 small
## propensity fits. The protocol budgets 3 to 10 hours, which is below the
## 12 hour overnight ceiling. No factor, precision level or replicate was cut.
OVERNIGHT_HOURS <- 12

PRECISION <- data.frame(
  precision   = c("small", "medium", "large"),
  n_trial     = c(500L, 2500L, 25000L),
  n_emulation = c(5000L, 25000L, 250000L),
  stringsAsFactors = FALSE
)

DELTA_PRIMARY <- 0.02
DELTA_GRID    <- c(0.01, 0.02, 0.03, 0.05)
COMPATIBILITY_CUTOFFS <- seq(0.50, 0.99, by = 0.01)
LOSS_LAMBDAS <- seq(0, 1, by = 0.05)

Z95 <- 1.959964
Z90 <- 1.644854
SCEPTICAL_ALPHA <- 0.05
PRIMARY_S_THRESHOLD <- 0.10
SENSITIVITY_THRESHOLDS <- c(0.05, 0.10, 0.15)

OUTCOME_FAMILIES <- c("logit", "probit")
BASELINE_RISKS   <- c("lower", "common")
MISMATCHES <- c(
  "aligned",
  "observed_z_shift",
  "hidden_u_shift",
  "measurement_mismatch"
)

## Critique implementation fix: mechanism constants and sample sizes are fixed
## here before any marginal risk difference or tolerance classification is
## computed. Nothing in the mechanism is solved against DELTA_PRIMARY.
build_scenarios <- function() {
  g <- expand.grid(
    family = OUTCOME_FAMILIES,
    baseline_risk = BASELINE_RISKS,
    mismatch = MISMATCHES,
    stringsAsFactors = FALSE
  )
  g$scenario <- seq_len(nrow(g))
  g <- g[, c("scenario", "family", "baseline_risk", "mismatch")]
  stopifnot(nrow(g) == 16L)
  g
}
