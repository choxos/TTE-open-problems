## GMT-01: finite-library causal-score selection configuration.

MASTER_SEED <- 20260801L
DESIGN_VERSION <- "gmt01.v1"

N_PERSON <- 4000L
N_REP_PROTOCOL <- 2000L
## Budget reduction: 24 x 2000 x 288 = 13,824,000 fitted models was estimated
## at 18 to 36 hours. The overnight ceiling permits one quarter of that work:
## 24 x 500 x 288 = 3,456,000 fits, or about 4.5 to 9 hours, plus 1.5 to 2
## hours for truth. This reduction preserves n = 4000 and all 24 scenarios but
## weakens Monte Carlo precision. The analysis therefore retains the protocol's
## confidence-bound rules and returns the uninformative branch when the reduced
## run cannot resolve them.
N_REP <- 500L
WORKERS <- 6L
OUTER_FOLDS <- 2L
INNER_FOLDS <- 2L

N_TRUTH_BLOCK <- 2000000L
TRUTH_MCSE_MAX <- 0.0005
N_DGM_CHECK <- 200000L
N_DRY_RUN <- 20000L
BOOT_REPS <- 5000L

PROB_FLOOR <- 1e-6
EXTREME_PROB_FRACTION <- 0.005
MAX_LOGIT_COEF <- 30
MIN_ESS <- 10
MAX_WEIGHT <- 1e6
Z975 <- 1.959964

S_LEVELS <- c(good = 0.65, poor = 1.25)
GAMMA_Z_LEVELS <- c(absent = 0, moderate = log(2.12), strong = log(4.48))
SHAPES <- c("all-main", "nonlinear-treatment", "nonlinear-censoring",
            "nonlinear-outcome")

G_NAMES <- paste0("G", 0:4)
C_NAMES <- paste0("C", 0:2)
Q_NAMES <- paste0("QL", 0:3)
CONFIG_GRID <- expand.grid(g = 0:4, c = 0:2, q = 0:3)
CONFIG_GRID$config_id <- seq_len(nrow(CONFIG_GRID))

SCORE_WEIGHTS <- list(
  combined = c(P = 0.25, B = 0.25, W = 0.25, D = 0.25),
  prediction_heavy = c(P = 0.40, B = 0.20, W = 0.20, D = 0.20),
  no_P = c(P = 0, B = 1 / 3, W = 1 / 3, D = 1 / 3),
  no_B = c(P = 1 / 3, B = 0, W = 1 / 3, D = 1 / 3),
  no_W = c(P = 1 / 3, B = 1 / 3, W = 0, D = 1 / 3),
  no_D = c(P = 1 / 3, B = 1 / 3, W = 1 / 3, D = 0)
)

## Critique fix: gamma_Z = 0 scenarios are the exclusive primary stratum.
## Nonzero gamma_Z scenarios are separate mechanistic positive controls.
build_scenarios <- function() {
  g <- expand.grid(
    separation_key = names(S_LEVELS),
    gamma_z_key = names(GAMMA_Z_LEVELS),
    shape = SHAPES,
    stringsAsFactors = FALSE
  )
  g$s <- unname(S_LEVELS[g$separation_key])
  g$gamma_z <- unname(GAMMA_Z_LEVELS[g$gamma_z_key])
  g$I_G <- as.integer(g$shape == "nonlinear-treatment")
  g$I_C <- as.integer(g$shape == "nonlinear-censoring")
  g$I_Q <- as.integer(g$shape == "nonlinear-outcome")
  g$scenario <- seq_len(nrow(g))
  g[, c("scenario", "separation_key", "s", "gamma_z_key", "gamma_z",
        "shape", "I_G", "I_C", "I_Q")]
}

DECISION <- list(
  favorable_abs_bias = 0.01,
  favorable_coverage = 0.03,
  median_abs_bias = 0.005,
  median_coverage = 0.015,
  combined_convergence_lower = 0.93,
  minimum_primary_convergence_lower = 0.80,
  paired_convergence_lower = -0.02,
  alignment_relative_mse_upper = 0.10,
  oracle_abs_bias = 0.02,
  oracle_coverage = 0.90,
  coverage_mc_halfwidth = 0.02
)
