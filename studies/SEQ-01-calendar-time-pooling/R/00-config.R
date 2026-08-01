## Study SEQ-01: configuration.
##
## This implementation addresses calendar-time pooling, start-specific reporting,
## restricted-model projections, diagnostics, and conditional efficiency. It does
## not address identification under survival-conditioned later eligibility.

MASTER_SEED <- 20260801L
TRUTH_SEED_OFFSET <- 100000L

N_PEOPLE <- 2000L
STARTS <- seq.int(0L, 22L, by = 2L)
N_STARTS <- length(STARTS)
N_FOLLOW <- 12L
N_CAL_MONTHS <- max(STARTS) + N_FOLLOW
WORKERS <- 6L

## Computational scaling from the reviewed protocol:
##
## The original main experiment required 12 * 2000 = 24000 replicates. The full
## calibration overlay required 4 * 200 * 399 = 319200 complete person-bootstrap
## refits. That refit count cannot fit an overnight six-worker allocation.
## Defaults therefore use 12 * 500 = 6000 main replicates and
## 4 * 50 * 99 = 19800 calibration refits. These are reductions by factors of
## 4 and 16.12, respectively. The minimum valid counts retain the original
## 95 percent requirements: 475 main replicates, 45 calibration replicates, and
## 95 successful bootstrap samples. Coverage Monte Carlo SE at 0.95 is 0.00975.
## Truth and metric resampling use 1999 and 4999 draws instead of 9999, reducing
## those resampling workloads by factors of 5.00 and 2.00. The 999 joint
## linearized multiplier draws are retained.
N_REP <- 500L
MIN_VALID <- 475L
N_LEF <- 999L
N_PERSON_BOOT <- 99L
N_CALIB_REP <- 50L
MIN_PERSON_BOOT <- 95L
MIN_CALIB_REP <- 45L
N_TRUTH_BOOT <- 1999L
N_TRUTH_BOOT_INTERIM <- 499L
N_METRIC_BOOT <- 4999L

TRUTH_CHUNK <- 100000L
TRUTH_INITIAL_CHUNKS <- 20L
TRUTH_BATCH_CHUNKS <- 10L
TRUTH_MAX_CHUNKS <- 100L

PILOT_REP <- 20L
PILOT_WORKERS <- c(1L, 2L, 4L, 6L)
OVERNIGHT_SECONDS <- 12 * 60 * 60

BIAS_ADEQUATE <- 0.005
BIAS_INADEQUATE <- 0.010
COVERAGE_ADEQUATE <- 0.93
COVERAGE_INADEQUATE <- 0.90
HET_NEAR <- 0.005
HET_MATERIAL <- 0.020
DIAG_SENS_ADEQUATE <- 0.80
DIAG_SPEC_ADEQUATE <- 0.90
DIAG_SENS_INADEQUATE <- 0.60
DIAG_SPEC_INADEQUATE <- 0.80
CALENDAR_CONSEQUENTIAL <- 0.005
CALENDAR_NEGLIGIBLE <- 0.0025
ESS_MIN <- 10

H_KEYS <- c("none", "monotone", "cosine")
A_LEVELS <- c(0, 0.80)
B_LEVELS <- c(0, 0.35)

q_of <- function(t) pmax(-1, pmin(1, (t - 11) / 11))
START_Q <- q_of(STARTS)
START_BASIS <- splines::ns(START_Q, df = 4)

build_scenarios <- function() {
  g <- expand.grid(
    h_key = H_KEYS,
    a = A_LEVELS,
    b = B_LEVELS,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  g$scenario <- seq_len(nrow(g))
  g$h_label <- c(
    none = "no conditional effect modification",
    monotone = "monotone conditional effect modification",
    cosine = "transient loss of benefit"
  )[g$h_key]
  g$adoption <- ifelse(g$a == 0, "none", "strong")
  g$background <- ifelse(g$b == 0, "none", "strong")
  g$sentinel <- (g$h_key == "none" & g$a == 0 & g$b == 0) |
    (g$a == 0.80 & g$b == 0.35)
  g[, c("scenario", "h_key", "h_label", "a", "adoption", "b",
        "background", "sentinel")]
}

MODEL_METHODS <- c(
  "package_like", "equal_common", "equal_flexible",
  "calendar_omitted", "calendar_quadratic"
)
ALL_METHODS <- c(MODEL_METHODS, "start_saturated", "standalone_12")
PROJECTION_METHODS <- c(
  "package_like", "equal_common", "calendar_omitted", "calendar_quadratic"
)

FUNCTION_NAMES <- c(paste0("rd_", STARTS), "theta_equal", "theta_pt")
PAIR_INDEX <- utils::combn(seq_along(STARTS), 2L)

is_sentinel <- function(scen) {
  isTRUE(as.logical(scen$sentinel[[1]]))
}
