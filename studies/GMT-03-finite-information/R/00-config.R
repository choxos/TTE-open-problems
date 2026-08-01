## Study GMT-03: configuration.
##
## The full protocol requires 180 * 4000 = 720000 replicates. Even at the
## smallest n, that is at least 34.56 billion person-months before model fitting
## or cloning. The 16 sentinel cells add 16 * 4000 * 399 = 25536000 bootstrap
## refits. That does not fit an overnight budget on six workers.
##
## The default overnight profile retains all 180 scenarios and every factor,
## but uses 20 replicates, 19 bootstrap resamples, 20000 calibration histories,
## and smaller truth batches. This reduces the replicate count by 200-fold and
## bootstrap refits to 6080, about 4200-fold fewer. Confirmatory thresholds are
## not relaxed. Consequently, default-profile results will normally be
## classified as indeterminate. Set GMT03_PROFILE=full only on suitable compute.

PROFILE <- tolower(Sys.getenv("GMT03_PROFILE", "overnight"))
if (!PROFILE %in% c("overnight", "full")) stop("GMT03_PROFILE must be overnight or full")
FULL_DESIGN <- identical(PROFILE, "full")

MASTER_SEED      <- 20260801L
CALIBRATION_SEED <- 20260802L
VALIDATION_SEED  <- 20260803L
PILOT_SEED       <- 20260804L
ANALYSIS_SEED    <- 20260805L

N_MONTHS <- 60L
HORIZONS <- c(12L, 36L, 60L)
WORKERS  <- 6L

N_REP <- if (FULL_DESIGN) 4000L else 20L
BOOT_B <- if (FULL_DESIGN) 399L else 19L
BOOT_MIN_SUCCESS <- if (FULL_DESIGN) 380L else 18L
ANALYSIS_BOOT_B <- if (FULL_DESIGN) 999L else 199L

N_CALIBRATION <- if (FULL_DESIGN) 2000000L else 20000L
N_TRUTH_CORE_INITIAL <- if (FULL_DESIGN) 2000000L else 200000L
N_TRUTH_VALID_INITIAL <- if (FULL_DESIGN) 500000L else 50000L
N_TRUTH_CORE_STEP <- N_TRUTH_CORE_INITIAL
N_TRUTH_VALID_STEP <- N_TRUTH_VALID_INITIAL
MAX_TRUTH_CORE <- if (FULL_DESIGN) Inf else 600000L
MAX_TRUTH_VALID <- if (FULL_DESIGN) Inf else 300000L

PROTOCOL_TRUTH_TOL_OVERALL <- 0.0005
PROTOCOL_TRUTH_TOL_SUBGROUP <- 0.001
TRUTH_TOL_OVERALL <- if (FULL_DESIGN) PROTOCOL_TRUTH_TOL_OVERALL else 0.0015
TRUTH_TOL_SUBGROUP <- if (FULL_DESIGN) PROTOCOL_TRUTH_TOL_SUBGROUP else 0.003

N_VALIDATION <- 120L
VALIDATION_POOL <- if (FULL_DESIGN) 2400L else 1200L
VALIDATION_QUADRATURE_N <- if (FULL_DESIGN) 101L else 41L

KAPPA_GRID <- seq(0, 2.25, by = 0.025)
KAPPA_TARGETS <- c(K1 = 0.12, K2 = 0.08, K3 = 0.04, K4 = 0.02)
CORE_N <- c(1000L, 4000L, 16000L)
CORE_ALPHA_Y <- c(rare = -9.35, common = -6.95)
CORE_ALPHA_D <- c(rare = -9.40, common = -7.00)
CORE_P_G <- 0.25
CORE_PERSISTENCE <- 4.0

RISKSET_ESS_FLAG <- 100
EVENT_ESS_FLAG <- 20
MIN_INTERVALS <- 3600L
FAIL_AVAIL_LB <- 0.95
FAIL_COVERAGE_UB <- 0.90
OPERATIONAL_AVAIL_UB <- 0.90
K0_AVAIL_LB <- 0.98
ADEQUATE_COVERAGE_LB <- 0.925
ADEQUATE_AVAIL_LB <- 0.95
DIAGNOSTIC_BOUNDARY <- 0.80
MIN_VALIDATION_CLASS <- 30L
NORMAL_CRIT <- 1.959964
WEIGHT_LIMIT <- 1e12
PROBABILITY_FLOOR <- 1e-8

METHODS <- c("exact_fixed", "exact_stacked", "exact_t", "oracle", "msm", "msm_boot")

endpoint_grid <- function() {
  rbind(
    expand.grid(endpoint = "Y", subgroup = c("all", "G0", "G1"),
                horizon = HORIZONS, stringsAsFactors = FALSE),
    expand.grid(endpoint = "D", subgroup = "all", horizon = HORIZONS,
                stringsAsFactors = FALSE)
  )
}

## Critique fix: decisions are endpoint-specific. A competing-event diagnostic
## cannot trigger a primary-event conclusion, and subgroup rows remain distinct.
estimate_grid <- function() {
  merge(data.frame(method = METHODS, stringsAsFactors = FALSE), endpoint_grid(),
        by = NULL)
}

build_core_scenarios <- function(calibration) {
  g <- expand.grid(
    n = CORE_N,
    k_level = calibration$k_level,
    alpha_y_key = names(CORE_ALPHA_Y),
    alpha_d_key = names(CORE_ALPHA_D),
    stringsAsFactors = FALSE
  )
  g$kappa <- calibration$kappa[match(g$k_level, calibration$k_level)]
  g$alpha_y <- unname(CORE_ALPHA_Y[g$alpha_y_key])
  g$alpha_d <- unname(CORE_ALPHA_D[g$alpha_d_key])
  g$p_g <- CORE_P_G
  g$persistence <- CORE_PERSISTENCE
  g$phase <- "core"
  g$validation_quadrant <- NA_character_
  g$expected_y <- NA_real_
  g$expected_d <- NA_real_
  g$is_sentinel <- g$n %in% c(1000L, 16000L) &
    g$k_level %in% c("K0", "K4")
  g$scenario <- seq_len(nrow(g))
  g[, c("scenario", "phase", "n", "k_level", "kappa", "alpha_y_key",
        "alpha_d_key", "alpha_y", "alpha_d", "p_g", "persistence",
        "validation_quadrant", "expected_y", "expected_d", "is_sentinel")]
}

build_scenarios <- function(calibration, validation) {
  core <- build_core_scenarios(calibration)
  validation$is_sentinel <- FALSE
  validation$alpha_y_key <- "continuous"
  validation$alpha_d_key <- "continuous"
  validation$k_level <- "V"
  validation$phase <- "validation"
  validation$scenario <- nrow(core) + seq_len(nrow(validation))
  validation <- validation[, names(core)]
  out <- rbind(core, validation)
  rownames(out) <- NULL
  stopifnot(nrow(out) == 180L, all(out$scenario == seq_len(nrow(out))))
  out
}

wilson_interval <- function(x, n, level = 0.95) {
  if (!is.finite(n) || n <= 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- x / n
  den <- 1 + z^2 / n
  mid <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(lower = max(0, mid - half), upper = min(1, mid + half))
}

RESULT_COLUMNS <- c(
  "row_type", "method", "endpoint", "subgroup", "horizon", "month",
  "strategy", "est", "se", "lo", "hi", "fail", "boot_success",
  "n_compatible", "cum_y", "cum_d", "sum_w", "sum_w2", "kish_ess",
  "ess_fraction", "max_normalized_weight", "p99_p50", "event_ess",
  "nonevent_ess", "min_riskset_ess", "warning"
)

complete_result <- function(x) {
  defaults <- list(
    row_type = NA_character_, method = NA_character_, endpoint = NA_character_,
    subgroup = NA_character_, horizon = NA_integer_, month = NA_integer_,
    strategy = NA_integer_, est = NA_real_, se = NA_real_, lo = NA_real_,
    hi = NA_real_, fail = NA_character_, boot_success = NA_real_,
    n_compatible = NA_real_, cum_y = NA_real_, cum_d = NA_real_,
    sum_w = NA_real_, sum_w2 = NA_real_, kish_ess = NA_real_,
    ess_fraction = NA_real_, max_normalized_weight = NA_real_,
    p99_p50 = NA_real_, event_ess = NA_real_, nonevent_ess = NA_real_,
    min_riskset_ess = NA_real_, warning = NA
  )
  for (nm in RESULT_COLUMNS) {
    if (!nm %in% names(x)) x[[nm]] <- rep(defaults[[nm]], nrow(x))
  }
  x[, RESULT_COLUMNS]
}

SCALE_NOTE <- if (FULL_DESIGN) NULL else paste(
  "Default overnight profile: 20 rather than 4000 replicates per scenario;",
  "19 rather than 399 bootstrap resamples; 20000 rather than 2000000",
  "calibration histories; smaller truth batches and relaxed pilot truth",
  "tolerances. All confirmatory numerical thresholds remain unchanged."
)
