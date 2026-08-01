## Study TZO-01: configuration.
##
## The selector is evaluated on four coupled process blocks. Each block produces
## all six outcome profiles and both grace-period cells from common histories.

MASTER_SEED <- 20260801L
WORKERS <- 6L
N_WEEKS <- 104L
N_DESIGN <- 1000L
N_ANALYSIS <- 4000L
N_TOTAL <- N_DESIGN + N_ANALYSIS

## The reviewed design requested 2000 replicates. Coupling the outcome and grace
## twins still requires 4 * 2000 * 5000 * 104 = 4,160,000,000 generated
## person-weeks before model fitting. The overnight ceiling therefore fixes 500
## replicates before outcomes are examined. This reduces generation to
## 4 * 500 * 5000 * 104 = 1,040,000,000 person-weeks. Coverage MCSE at 0.95 is
## sqrt(0.95 * 0.05 / 500) = 0.00975. Monte Carlo intervals remain mandatory,
## so cells lacking enough precision become uninformative rather than decisive.
N_REP <- 500L
ORIGINAL_N_REP <- 2000L

GRIDS <- c(1L, 2L, 4L, 8L)
GRACES <- c(4L, 12L)
CV_FOLDS <- 2L

TRUTH_BATCH <- 250000L
TRUTH_FIT_N <- 250000L
TRUTH_CHUNK <- 5000L
TRUTH_MAX <- 4000000L
TRUTH_MCSE_TARGET <- 0.00050

GRID_MARGIN <- 0.002
TREATMENT_BURDEN <- 0.01
UTILITY_BOUNDARY <- -TREATMENT_BURDEN
COVERAGE_ACCEPT <- c(0.925, 0.975)
SELECTOR_ALIAS_LIMIT <- 0.10
SELECTOR_LOGLOSS_RATIO <- 1.02
SELECTOR_ESS_MIN <- 200
ANALYSIS_ESS_MIN <- 100
MAX_FAILURE_RATE <- 0.05
MIN_TIME_REDUCTION <- 0.25
MAXT_DRAWS <- 50000L

VISIT_LEVELS <- c(frequent = -1.75, sparse = -3.45)
PRESSURE_LEVELS <- c(lower = -4.05, higher = -2.85)
OUTCOME_PROFILES <- c(
  'exact-null',
  'immediate-benefit',
  'biphasic',
  'delayed-smooth',
  'negligible-smooth',
  'off-grid'
)

INIT_FEATURES <- c(
  'xage', 'female', 'comorbidity', 'marker',
  'prior_visit', 'elapsed_intervals',
  'xage_comorbidity', 'female_comorbidity'
)

build_process_scenarios <- function() {
  g <- expand.grid(
    visit_key = names(VISIT_LEVELS),
    pressure_key = names(PRESSURE_LEVELS),
    stringsAsFactors = FALSE
  )
  g$alphaV <- unname(VISIT_LEVELS[g$visit_key])
  g$alphaA <- unname(PRESSURE_LEVELS[g$pressure_key])
  g$scenario <- seq_len(nrow(g))
  g[, c('scenario', 'visit_key', 'pressure_key', 'alphaV', 'alphaA')]
}

build_cells <- function() {
  g <- expand.grid(
    visit_key = names(VISIT_LEVELS),
    pressure_key = names(PRESSURE_LEVELS),
    profile = OUTCOME_PROFILES,
    G = GRACES,
    stringsAsFactors = FALSE
  )
  process <- build_process_scenarios()
  key <- paste(process$visit_key, process$pressure_key, sep = '|')
  g$process_scenario <- match(paste(g$visit_key, g$pressure_key, sep = '|'), key)
  g$cell <- seq_len(nrow(g))
  g[, c('cell', 'process_scenario', 'visit_key', 'pressure_key', 'profile', 'G')]
}

cell_number <- function(scen, profile, G) {
  cells <- build_cells()
  hit <- cells$visit_key == scen$visit_key &
    cells$pressure_key == scen$pressure_key &
    cells$profile == profile & cells$G == G
  stopifnot(sum(hit) == 1L)
  cells$cell[hit]
}
