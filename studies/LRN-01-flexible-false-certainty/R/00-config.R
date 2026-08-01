## LRN-01 support stress study: configuration.

MASTER_SEED <- 20260801L
PROJECTION_SEED <- 7312026L
WORKERS <- 6L
VISITS <- 0:5
N_VISITS <- length(VISITS)

## Scale-down required by the overnight ceiling. The reviewed design requires
## 68 * 2000 = 136000 observed datasets and estimates about 50 GLM fits per
## dataset, or 6.8 million fits before numerical Jacobians and ridge operations.
## This executable pilot uses 68 * 100 = 6800 datasets and about 340000 GLM
## fits, which is 5 percent of the production workload. Because fewer than 1500
## replicates are available per cell, 05-analyze.R must classify the decision
## branches as uninformative. Restoring 2000 requires a reviewed runtime amendment.
N_REP <- 100L
N_LEVELS <- c(1000L, 4000L)
COMPLEXITY <- 0:1

N_TRUTH_START <- 2000000L
N_TRUTH_BATCH <- 20000L
N_TRUTH_EXTEND <- 1000000L
TRUTH_MCSE_MAX <- 0.0005

WEIGHT_CAP <- 50
PROB_TRUNC <- c(0.01, 0.99)
SUPPORT_PROB_THRESHOLD <- 0.025
SUPPORT_MASS_THRESHOLD <- 0.05
STRONG_SPECIFICITY_MASS <- 0.005
QR_TOL <- 1e-10
JACOBIAN_CONDITION_MAX <- 1e12
RIDGE_MULTIPLIER <- 1e-6
RIDGE_QUANTILE <- 0.995
MIN_ACTION_ROWS <- 50L

COMPLETION_MAGNITUDES <- log(c(1.5, 2, 3))
COMPLETION_DELTAS <- c(-log(3), -log(2), -log(1.5), 0,
                       log(1.5), log(2), log(3))
PRIMARY_MAGNITUDE <- log(2)

## Critique fix: three fixed linear boundaries and four independently projected
## nonlinear geometries replace the favorable single linear boundary.
SUPPORTS <- data.frame(
  support_key = c(
    "strong", "moderate", "severe",
    "linear-exact-100", "linear-practical-100",
    "linear-exact-125", "linear-practical-125",
    "linear-exact-150", "linear-practical-150",
    "curved-exact", "curved-practical",
    "disconnected-exact", "disconnected-practical",
    "interaction-exact", "interaction-practical",
    "accumulated-exact", "accumulated-practical"),
  support_label = c(
    "Strong overlap", "Moderate overlap", "Severe practical nonoverlap",
    "Exact linear holes, b=1.00", "Practical linear holes, b=1.00",
    "Exact linear holes, b=1.25", "Practical linear holes, b=1.25",
    "Exact linear holes, b=1.50", "Practical linear holes, b=1.50",
    "Exact curved holes", "Practical curved holes",
    "Exact disconnected holes", "Practical disconnected holes",
    "Exact interaction-dependent holes", "Practical interaction-dependent holes",
    "Exact accumulated holes", "Practical accumulated holes"),
  support_kind = c(rep("soft", 3), rep(c("exact", "practical"), 7)),
  geometry = c(rep("soft", 3),
               "linear", "linear", "linear", "linear", "linear", "linear",
               "curved", "curved", "disconnected", "disconnected",
               "interaction", "interaction", "accumulated", "accumulated"),
  boundary = c(NA, NA, NA, 1, 1, 1.25, 1.25, 1.5, 1.5,
               rep(NA, 8)),
  eta_scale = c(0.5, 1, 2.5, rep(NA, 14)),
  stringsAsFactors = FALSE
)
stopifnot(nrow(SUPPORTS) == 17L)

METHODS <- c("ipw", "main_aipw", "flex_aipw", "flex_aipw_map")

build_observed_laws <- function() {
  g <- expand.grid(
    n = N_LEVELS,
    complexity = COMPLEXITY,
    support_index = seq_len(nrow(SUPPORTS)),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  g <- cbind(g[, c("n", "complexity"), drop = FALSE],
             SUPPORTS[g$support_index, , drop = FALSE])
  rownames(g) <- NULL
  g$observed_law <- seq_len(nrow(g))
  g$scenario <- g$observed_law
  g[, c("scenario", "observed_law", "n", "complexity",
        names(SUPPORTS)), drop = FALSE]
}

build_scenarios <- function() {
  laws <- build_observed_laws()
  out <- lapply(seq_len(nrow(laws)), function(i) {
    d <- if (laws$support_kind[i] == "exact") COMPLETION_DELTAS else 0
    z <- laws[rep(i, length(d)), setdiff(names(laws), "scenario"), drop = FALSE]
    z$delta <- d
    z
  })
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out$estimand_scenario <- seq_len(nrow(out))
  out$scenario <- out$estimand_scenario
  out <- out[, c("scenario", "estimand_scenario", "observed_law", "n",
                 "complexity", names(SUPPORTS), "delta"), drop = FALSE]
  stopifnot(nrow(out) == 236L)
  out
}

projection_history_names <- function(t) {
  c("B1", "B2", "B3", paste0("L", 0:t), paste0("M", 0:t),
    if (t > 0) paste0("A", 0:(t - 1L)) else character())
}

## The projection RNG state is restored before this file returns. Consequently,
## sourcing the configuration cannot alter a replicate stream owned by the harness.
make_projection_manifest <- function(seed = PROJECTION_SEED) {
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    do.call("RNGkind", as.list(old_kind))
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  RNGkind("L'Ecuyer-CMRG")
  set.seed(seed)
  out <- list()
  for (geometry in c("curved", "disconnected", "interaction")) {
    for (t in VISITS) {
      nm <- projection_history_names(t)
      u <- stats::rnorm(length(nm)); u <- u / sqrt(sum(u^2))
      v <- stats::rnorm(length(nm)); v <- v / sqrt(sum(v^2))
      names(u) <- names(v) <- nm
      out[[paste(geometry, t, sep = "|")]] <- list(U = u, V = v)
    }
  }
  out
}

PROJECTION_MANIFEST <- make_projection_manifest()

projection_manifest_frame <- function() {
  do.call(rbind, lapply(names(PROJECTION_MANIFEST), function(k) {
    p <- strsplit(k, "|", fixed = TRUE)[[1]]
    z <- PROJECTION_MANIFEST[[k]]
    rbind(
      data.frame(geometry = p[1], visit = as.integer(p[2]),
                 projection = "U", feature = names(z$U), coefficient = unname(z$U)),
      data.frame(geometry = p[1], visit = as.integer(p[2]),
                 projection = "V", feature = names(z$V), coefficient = unname(z$V))
    )
  }))
}

DECISION <- list(
  excess_support_lower = 0.10,
  excess_not_supported_upper = 0.05,
  map_sensitivity_lower = 0.90,
  map_specificity_lower = 0.90,
  map_reduction_lower = 0.40,
  map_failure_sensitivity_upper = 0.80,
  map_failure_specificity_upper = 0.80,
  map_failure_reduction_upper = 0.20,
  minimum_completed = 1500L,
  strong_convergence_lower = 0.90,
  family_alpha = 0.05
)
