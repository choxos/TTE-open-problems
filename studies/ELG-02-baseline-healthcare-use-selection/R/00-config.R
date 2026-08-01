## Study ELG-02: configuration.
##
## This is a conditional mechanism and policy benchmark. It does not discover
## or certify collider status in an unknown eligibility graph.

MASTER_SEED <- 20260801L
ANALYSIS_SEED <- 20261801L
WORKERS <- 6L

N_AUDIT <- 4000L
N_ANALYSIS <- 4000L
N_REP <- 2000L

## The protocol requires 18 * 2000 = 36000 replicate pairs. Each pair uses
## 8000 records and, after reusing identical fits across information views,
## requires 22 probit fits. This gives 792000 fits. The protocol estimates
## 10 to 24 hours on six workers, which reaches but does not exceed the stated
## overnight ceiling. No design component is scaled down.

SCREEN_ALPHA <- 0.01
QUAD_NODES <- c(30L, 40L, 50L)
QUAD_FALLBACK <- 60L
QUAD_TOL <- 1e-7
N_BOOT <- 2000L

MATERIAL_BIAS <- 0.010
NEGLIGIBLE_BIAS <- 0.005
POLICY_BENEFIT <- 0.005
MAX_FAILURE_RATE <- 0.10
MIN_PAIRED <- 1900L

TOPOLOGIES <- c("noncollider", "concordant-collider", "discordant-collider")
STRENGTHS <- c(0.10, 0.45, 1.10)
RETENTIONS <- c(0.30, 0.70)
VIEWS <- c("full", "reduced")
NOISE_VARS <- paste0("N_", seq_len(8L))
FULL_CANDIDATES <- c("P", "D", NOISE_VARS)
REDUCED_CANDIDATES <- NOISE_VARS

ESTIMATOR_METHODS <- c(
  "minimal", "role_based", "all_measured", "oracle", "broad", "policy",
  "pooled_all"
)

alpha_for_retention <- function(retention, lambda_p, lambda_d) {
  r <- sqrt(1 + 0.20^2 + lambda_p^2 + lambda_d^2)
  objective <- function(alpha) {
    0.5 * stats::pnorm(alpha / r) +
      0.5 * stats::pnorm((alpha + 0.30) / r) - retention
  }
  stats::uniroot(objective, interval = c(-12, 12), tol = 1e-12)$root
}

build_scenarios <- function() {
  g <- expand.grid(
    topology = TOPOLOGIES,
    strength = STRENGTHS,
    retention = RETENTIONS,
    stringsAsFactors = FALSE
  )
  g$lambda_p <- ifelse(g$topology == "noncollider", 0, g$strength)
  g$lambda_d <- ifelse(
    g$topology == "discordant-collider", -g$strength, g$strength
  )
  g$alpha_h <- mapply(
    alpha_for_retention, g$retention, g$lambda_p, g$lambda_d
  )
  g$scenario <- seq_len(nrow(g))

  ## Critique fix: information view is an analysis condition applied to each
  ## generated distribution. It does not duplicate a DGM cell.
  g[, c("scenario", "topology", "strength", "retention", "lambda_p",
        "lambda_d", "alpha_h")]
}
