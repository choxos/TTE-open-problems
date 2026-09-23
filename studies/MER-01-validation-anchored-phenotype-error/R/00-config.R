## Study 2 (MER-01): configuration.

MASTER_SEED <- 20260801L
WORKERS <- 6L
N_PER_REP <- 4000L
N_MONTHS <- 12L
N_TRUTH <- 4000000L

## The frozen protocol requires at least 81 * 1000 * 50 = 4,050,000
## completed-data MI analyses before extensions, calibration, exact filtering,
## numerical sandwich work, or four-times-M checks. Even at an optimistic ten
## seconds per completed-data analysis, that lower bound is 1,875 worker-hours.
## The default is therefore an overnight feasibility-scale run. It retains all
## 81 scenarios, 4000 participants, the four-million-person truth, all methods,
## and every numerical decision threshold, but uses 12 replicates and M up to
## 20. Its upper MI count is 81 * 12 * 20 = 19,440 completed-data analyses,
## approximately 9 worker-hours at the same rate on six workers. Because it is
## below the first 1000-replicate look, 05-analyze.R must classify the primary
## result as uninformative. Set MER01_FULL=1 and optionally MER01_N_REP to run
## the frozen replication schedule after the feasibility benchmark passes.
FULL_PROTOCOL <- identical(Sys.getenv("MER01_FULL"), "1")
N_REP <- as.integer(Sys.getenv(
  "MER01_N_REP", if (FULL_PROTOCOL) "1000" else "12"))
SCALED_RUN <- !FULL_PROTOCOL || N_REP < 1000L

if (FULL_PROTOCOL) {
  MI_CANDIDATES <- c(50L, 100L, 200L, 400L)
  MI_FALLBACK <- 800L
  MI_CAL_DRAWS <- 1600L
  MI_CAL_DATASETS <- 30L
  MC_BOOT <- 1999L
} else {
  MI_CANDIDATES <- c(5L, 10L, 20L)
  MI_FALLBACK <- 20L
  MI_CAL_DRAWS <- 40L
  MI_CAL_DATASETS <- 8L
  MC_BOOT <- 499L
}
MI_CAL_THRESHOLD <- 0.001
MI_PRIOR_SD <- 2.5
MI_PRIOR_SENSITIVITY <- c(5, 10)

ESTIMANDS <- c("dynamic", "dynamic_x2_0", "dynamic_x2_1", "static")
PATTERNS <- c("none", "A", "L", "AL")
PROFILES <- c("nondifferential", "aligned", "reversed", "unrelated", "no_effect_modification")
SPECIFICATIONS <- c("core", "treatment", "confounder", "outcome", "error_transition")
VALIDATION_SIZES <- c(100L, 250L, 500L, 1000L)

DECISION <- list(
  no_error_bias = 0.005,
  key_oracle_bias = 0.010,
  material_bias = 0.020,
  negligible_bias = 0.010,
  interaction_equivalence = 0.005,
  coverage_low = 0.925,
  coverage_high = 0.975,
  material_coverage = 0.900,
  convergence = 0.950,
  minimum_ess = 200,
  required_cells = 6L,
  required_interactions = 4L,
  family_alpha = 0.01,
  looks = c(1000L, 2000L, 4000L)
)

make_scenario <- function(block, profile, accuracy, nodes, validation_n,
                          specification = "core", outcome_error = FALSE) {
  data.frame(
    block = block,
    profile = profile,
    accuracy = as.numeric(accuracy),
    nodes = nodes,
    validation_n = as.integer(validation_n),
    specification = specification,
    outcome_error = as.logical(outcome_error),
    stringsAsFactors = FALSE
  )
}

build_scenarios <- function() {
  rows <- list()
  add <- function(x) rows[[length(rows) + 1L]] <<- x

  ## Critique fix: the primary block excludes terminal outcome error and crosses
  ## neutral, aligned, reversed, unrelated, and absent effect modification.
  g <- expand.grid(
    profile = PROFILES,
    accuracy = c(0.70, 0.85),
    nodes = c("A", "L", "AL"),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(nrow(g))) {
    add(make_scenario("primary", g$profile[i], g$accuracy[i], g$nodes[i], 500L))
  }

  for (p in PROFILES) {
    add(make_scenario("near_null", p, 0.99, "AL", 500L))
  }

  ## Critique fix: symmetric Y error is a separate component and cannot enter
  ## the eight primary decision cells.
  for (a in c(0.70, 0.85, 0.99)) {
    add(make_scenario("outcome_component", "nondifferential", a, "AL", 500L,
                      outcome_error = TRUE))
  }

  add(make_scenario("no_error_core", "nondifferential", 1, "none", 500L))
  add(make_scenario("no_error_core", "no_effect_modification", 1, "none", 500L))

  ## Critique fix: validation size is crossed with each one-at-a-time model
  ## stress in both benchmark mechanisms. The two core n=500 cells already in
  ## the primary block are not duplicated.
  benchmarks <- data.frame(
    profile = c("nondifferential", "unrelated"),
    accuracy = c(0.70, 0.85),
    stringsAsFactors = FALSE
  )
  for (b in seq_len(nrow(benchmarks))) {
    for (sp in SPECIFICATIONS) {
      for (nv in VALIDATION_SIZES) {
        overlap <- sp == "core" && nv == 500L
        if (!overlap) {
          add(make_scenario("robustness", benchmarks$profile[b],
                            benchmarks$accuracy[b], "AL", nv, sp))
        }
      }
    }
  }

  for (sp in c("treatment", "confounder", "outcome")) {
    add(make_scenario("no_error_stress", "nondifferential", 1, "none", 500L, sp))
  }

  out <- do.call(rbind, rows)
  out$scenario <- seq_len(nrow(out))
  out$effect_modification <- out$profile != "no_effect_modification"
  out$differential_error <- !out$profile %in% c("nondifferential") & out$accuracy < 1
  out$high_error_stratum <- ifelse(
    out$profile %in% c("aligned", "no_effect_modification"), "X2=1",
    ifelse(out$profile == "reversed", "X2=0",
           ifelse(out$profile == "unrelated", "X3=1", "none")))
  out$benchmark <- ifelse(
    out$profile == "nondifferential" & out$accuracy == 0.70 & out$nodes == "AL",
    "nondifferential_070",
    ifelse(out$profile == "unrelated" & out$accuracy == 0.85 & out$nodes == "AL",
           "unrelated_085", ""))
  out$truth_law <- ifelse(
    !out$effect_modification, "no_effect_modification",
    ifelse(out$specification == "confounder", "confounder_stress",
           ifelse(out$specification == "outcome", "outcome_stress", "core")))
  out$decision_cell <- out$block == "primary" & out$nodes == "AL" &
    out$accuracy %in% c(0.70, 0.85) &
    out$profile %in% c("nondifferential", "reversed", "unrelated",
                       "no_effect_modification")
  out$pair_family <- paste(out$profile, out$accuracy, out$validation_n,
                           out$specification, sep = "|")
  out <- out[, c("scenario", setdiff(names(out), "scenario"))]
  stopifnot(nrow(out) == 81L, sum(out$decision_cell) == 8L)
  rownames(out) <- NULL
  out
}
