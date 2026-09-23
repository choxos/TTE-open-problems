## Study 2 (PRO-02): configuration.
##
## This study addresses only a recorded finite protocol search. It cannot settle
## undocumented or sequential human protocol development.

MASTER_SEED     <- 20260801L

## The separately registered replication (REPLICATION-PROTOCOL.md) draws every
## replicate from a new seed and writes under results/replication, so the first
## run's data are neither reused nor overwritten. Truth, lambda and the design
## diagnostics are deterministic given their own seeds and are shared.
REPLICATION <- identical(Sys.getenv("PRO02_REPLICATION"), "1")
if (REPLICATION) MASTER_SEED <- 20260922L
LAMBDA_SEED     <- 20260802L
DIAGNOSTIC_SEED <- 20260803L
TRUTH_SEED      <- 20261000L

WORKERS <- 6L
N_REP   <- 2000L

N_LEVELS      <- c(4000L, 8000L)
EVENT_TARGETS <- c(35L, 70L, 140L)
LIBRARY_SIZES <- c(4L, 16L)

## The requested design fits the overnight budget without reduction:
## 36 generated-data cells x 2000 replicates = 72,000 datasets. Each dataset
## requires two low-dimensional propensity fits, for about 144,000 fits. The
## protocol estimates 6 to 12 hours on 6 workers, below the overnight ceiling.

N_LAMBDA      <- 10000000L
N_DIAGNOSTIC  <- 2000000L
N_TRUTH_START <- 2000000L
N_TRUTH_STEP  <- 1000000L
N_TRUTH_MAX   <- 10000000L
TRUTH_BATCHES <- 200L
TRUTH_MCSE_MAX <- 0.00005

CUT_WORK_EVENTS <- 70L
CUT_WORK_ARM    <- 100L
CUT_SPLIT_EVENTS <- 35L
CUT_SPLIT_ARM    <- 50L
MIN_ESS          <- 20

Z_95 <- 1.959964
GLOBAL_Z <- stats::qnorm(0.9875)
MATERIAL_DEFICIT <- 0.02
CALIBRATION_RANGE <- c(0.93, 0.97)
MAX_FAILURE <- 0.05
## Replication gate: familywise error over every fixed-candidate evaluation.
GATE_FAMILYWISE_ALPHA <- 0.05

HORIZONS_ALL <- c(24L, 36L, 48L, 60L)
CUTS_ALL <- c(45L, 50L, 55L, 60L)
REFERENCE_C <- 55L
REFERENCE_H <- 60L

EFFECTS <- data.frame(
  effect = c("null", "homogeneous", "heterogeneous"),
  theta0 = c(0, -0.287682072, -0.287682072),
  theta1 = c(0, 0, 0.25),
  stringsAsFactors = FALSE
)

## Critique fix: the oracle prognostic score was replaced by two fixed scores
## with different alignment, neither of which copies the outcome predictor.
score_higher <- function(Z, S, C, B) {
  0.30 * Z + 0.20 * (S - 0.5) + 0.40 * (C - 0.5) + 0.20 * B
}
score_reduced <- function(Z, S, C, B) {
  0.30 * Z + 0.20 * (S - 0.5)
}

candidate_library <- function(K) {
  if (K == 4L) {
    cuts <- c(55L, 50L)
    horizons <- c(36L, 60L)
  } else if (K == 16L) {
    cuts <- c(60L, 55L, 50L, 45L)
    horizons <- HORIZONS_ALL
  } else {
    stop("K must be 4 or 16")
  }
  out <- do.call(rbind, lapply(cuts, function(cc) {
    data.frame(c = cc, h = horizons, stringsAsFactors = FALSE)
  }))
  out$candidate <- sprintf("c%02d-h%02d", out$c, out$h)
  out$order <- seq_len(nrow(out))
  rownames(out) <- NULL
  out
}

build_scenarios <- function() {
  ## Critique fix: below-boundary, at-boundary, and above-boundary regimes are
  ## crossed with every other generated-data factor.
  g <- expand.grid(
    n = N_LEVELS,
    event_target = EVENT_TARGETS,
    K = LIBRARY_SIZES,
    effect = EFFECTS$effect,
    stringsAsFactors = FALSE
  )
  j <- match(g$effect, EFFECTS$effect)
  g$theta0 <- EFFECTS$theta0[j]
  g$theta1 <- EFFECTS$theta1[j]
  g$event_regime <- factor(
    g$event_target,
    levels = EVENT_TARGETS,
    labels = c("below", "boundary", "above")
  )
  g$scenario <- seq_len(nrow(g))
  g[, c("scenario", "n", "event_target", "event_regime", "K",
        "effect", "theta0", "theta1")]
}

build_truth_scenarios <- function() {
  g <- expand.grid(
    n = N_LEVELS,
    event_target = EVENT_TARGETS,
    effect = EFFECTS$effect,
    stringsAsFactors = FALSE
  )
  j <- match(g$effect, EFFECTS$effect)
  g$theta0 <- EFFECTS$theta0[j]
  g$theta1 <- EFFECTS$theta1[j]
  g$truth_scenario <- seq_len(nrow(g))
  g[, c("truth_scenario", "n", "event_target", "effect", "theta0", "theta1")]
}

attach_lambdas <- function(scenarios, lambda_table) {
  z <- merge(scenarios, lambda_table, by = c("n", "event_target"),
             all.x = TRUE, sort = FALSE)
  id <- if ("scenario" %in% names(z)) "scenario" else "truth_scenario"
  z <- z[order(z[[id]]), , drop = FALSE]
  rownames(z) <- NULL
  stopifnot(all(is.finite(z$lambda)))
  z
}

bonferroni_critical <- function(K) stats::qnorm(1 - 0.05 / (2 * K))

analysis_scenario_id <- function(generated_scenario, score_key) {
  offset <- match(score_key, c("higher", "reduced"))
  2L * (as.integer(generated_scenario) - 1L) + offset
}
