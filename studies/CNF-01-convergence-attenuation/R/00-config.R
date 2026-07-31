## Study 1 (CNF-01): configuration.
##
## Everything the protocol fixes in advance lives here, so that a reader can see
## the design without reading the mechanism, and so that changing a design
## constant is a visible edit rather than a number buried in a loop.

MASTER_SEED <- 20260731L

N_PER_ARM   <- 4000L      # individuals per replicate
N_REP       <- 1000L      # replicates per scenario, derived in protocol section 5
N_MONTHS    <- 120L       # follow-up horizon in months
HORIZONS    <- c(12L, 24L, 36L, 60L, 84L, 120L)

## Truth is enumerated once per scenario at this size and stored, rather than
## estimated from the replicates. A truth that is itself noisy would put its
## Monte Carlo error into every bias and every attenuation.
N_TRUTH     <- 2000000L

## Outcome model. beta_A is negative throughout: the treatment works. A null
## treatment would answer nothing, because the question is whether convergence
## alone can make a working treatment look null.
BETA0 <- -5.4          # baseline monthly event hazard on the logit scale
BETA_L <- 0.45
BETA_Z <- 0.35
BETA_A <- -0.90        # log-odds reduction in the monthly hazard while exposed

## Baseline initiation. Confounded by both covariates, so the contrast needs
## baseline adjustment to mean anything.
GAMMA0 <- -0.40
GAMMA_L <- 0.60
GAMMA_Z <- 0.40

## Legacy exposure ramps in over this many months after initiation. Under
## `transient` the exposure switches on the month after initiation instead.
RAMP_MONTHS <- 12L

## The design grid. The two timing shapes are tuned in 01-dgm.R to the SAME
## cumulative initiation at month 120, which is the experiment that decides
## aim A2: same reported diagnostic, different timing, and the question is
## whether the attenuation differs.
TARGET_C120 <- c(0.20, 0.45, 0.70)
SHAPES      <- c("early", "late")
ALPHA_L     <- c(neutral = 0, prognostic = 0.60)
PERSISTENCE <- c("transient", "legacy")

build_scenarios <- function() {
  g <- expand.grid(
    target_c120 = TARGET_C120,
    shape       = SHAPES,
    alpha_l_key = names(ALPHA_L),
    persistence = PERSISTENCE,
    stringsAsFactors = FALSE
  )
  g$alpha_l <- unname(ALPHA_L[g$alpha_l_key])
  g$scenario <- seq_len(nrow(g))
  g[, c("scenario", "target_c120", "shape", "alpha_l_key", "alpha_l", "persistence")]
}
