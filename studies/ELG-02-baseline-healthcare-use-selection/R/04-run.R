## Study ELG-02: run the simulation.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:3
##
## Scenario outputs are resumable under results/raw. Absolute scenario indices
## preserve the harness seed streams when a slice is run.

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.file_arg)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .file_arg[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUTDIR <- here("results")
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUTDIR, "truth.rds")))

blank_replicate <- function(reason) {
  grid <- expand.grid(
    view = VIEWS, method = ESTIMATOR_METHODS,
    stringsAsFactors = FALSE
  )
  data.frame(
    grid, est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
    fail = reason, min_ps = NA_real_, max_weight = NA_real_, ess = NA_real_,
    n_fit = NA_integer_, screen_result = NA_character_,
    screen_fail = NA_character_, screen_n_ha = NA_integer_,
    screen_n_hy = NA_integer_, screen_n_pairs = NA_integer_,
    policy_source = NA_character_, selected_n = NA_integer_,
    treatment_prevalence = NA_real_, outcome_risk = NA_real_,
    cor_pd_selected = NA_real_, stringsAsFactors = FALSE
  )
}

safe_aipw <- function(...) {
  tryCatch(aipw_fit(...), error = function(e) failed_estimator("estimator-error"))
}

safe_screen <- function(dat, view) {
  tryCatch(
    screen_eligibility(dat, view, timestamps_available = TRUE),
    error = function(e) unresolved_screen("audit-error")
  )
}

estimator_row <- function(view, method, fit, screen, policy_source, common) {
  data.frame(
    view = view, method = method,
    est = fit$est, se = fit$se, lo = fit$lo, hi = fit$hi,
    fail = fit$fail, min_ps = fit$min_ps, max_weight = fit$max_weight,
    ess = fit$ess, n_fit = fit$n,
    screen_result = screen$result, screen_fail = screen$fail,
    screen_n_ha = screen$n_ha, screen_n_hy = screen$n_hy,
    screen_n_pairs = screen$n_pairs, policy_source = policy_source,
    selected_n = common$selected_n,
    treatment_prevalence = common$treatment_prevalence,
    outcome_risk = common$outcome_risk,
    cor_pd_selected = common$cor_pd_selected,
    stringsAsFactors = FALSE
  )
}

rows_for_view <- function(view, screen, fits, common) {
  ## Critique fix: this is the complete locked response policy. No failed
  ## analysis-sample estimator is replaced after its result is observed.
  policy_source <- if (screen$result == "no-observable-collider-signal") {
    "minimal"
  } else {
    "all_measured"
  }
  policy_fit <- fits[[policy_source]]

  rows <- lapply(ESTIMATOR_METHODS, function(method) {
    if (method == "policy") {
      estimator_row(view, method, policy_fit, screen, policy_source, common)
    } else {
      estimator_row(view, method, fits[[method]], screen, NA_character_, common)
    }
  })
  do.call(rbind, rows)
}

one_rep <- function(scen, rep_id) {
  pair <- tryCatch(gen_replicate_pair(scen), error = function(e) NULL)
  if (is.null(pair)) return(blank_replicate("dgm-failed"))

  ## The audit results are generated and locked before any analysis-sample fit.
  screen_full <- safe_screen(pair$audit, "full")
  screen_reduced <- safe_screen(pair$audit, "reduced")

  analysis_selected <- pair$analysis[pair$analysis$H == 1L, , drop = FALSE]
  pooled <- rbind(pair$audit, pair$analysis)
  pooled_selected <- pooled[pooled$H == 1L, , drop = FALSE]

  selected_n <- nrow(analysis_selected)
  cor_pd <- if (selected_n > 2L && stats::sd(analysis_selected$P) > 0 &&
                stats::sd(analysis_selected$D) > 0) {
    stats::cor(analysis_selected$P, analysis_selected$D)
  } else NA_real_
  common <- list(
    selected_n = selected_n,
    treatment_prevalence = if (selected_n) mean(analysis_selected$A) else NA_real_,
    outcome_risk = if (selected_n) mean(analysis_selected$Y) else NA_real_,
    cor_pd_selected = cor_pd
  )

  minimal <- safe_aipw(analysis_selected, c("B", "X"), c("B", "X"))
  role_based <- safe_aipw(
    analysis_selected, c("B", "X", "P"), c("B", "X", "D")
  )
  all_full <- safe_aipw(
    analysis_selected,
    c("B", "X", "P", "D", NOISE_VARS),
    c("B", "X", "P", "D", NOISE_VARS)
  )
  all_reduced <- safe_aipw(
    analysis_selected, c("B", "X", NOISE_VARS), c("B", "X", NOISE_VARS)
  )
  oracle <- safe_aipw(
    analysis_selected, c("B", "X", "P", "D"), c("B", "X", "P", "D")
  )
  broad <- safe_aipw(pair$analysis, c("B", "X"), c("B", "X"))
  pooled_full <- safe_aipw(
    pooled_selected,
    c("B", "X", "P", "D", NOISE_VARS),
    c("B", "X", "P", "D", NOISE_VARS)
  )
  pooled_reduced <- safe_aipw(
    pooled_selected, c("B", "X", NOISE_VARS), c("B", "X", NOISE_VARS)
  )

  ## Critique fixes: role-based and all-measured screen-free comparators are
  ## explicit. The pooled comparator receives the same total 8000 records as
  ## the audit plus analysis policy. The oracle remains available only as a
  ## simulation benchmark.
  fits_full <- list(
    minimal = minimal, role_based = role_based, all_measured = all_full,
    oracle = oracle, broad = broad, pooled_all = pooled_full
  )
  fits_reduced <- list(
    minimal = minimal,
    role_based = failed_estimator("unavailable", selected_n),
    all_measured = all_reduced, oracle = oracle, broad = broad,
    pooled_all = pooled_reduced
  )

  rbind(
    rows_for_view("full", screen_full, fits_full, common),
    rows_for_view("reduced", screen_reduced, fits_reduced, common)
  )
}

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
selected <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  bounds <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  selected <- intersect(seq(bounds[1], bounds[2]), selected)
}

results <- run_design(
  one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUTDIR, workers = WORKERS, resume = TRUE, only = selected
)

write_provenance(
  OUTDIR,
  packages = c("stats", "future", "furrr"),
  extra = list(
    study = "ELG-02 conditional healthcare-use selection benchmark",
    unique_dgm_cells = nrow(scenarios),
    analyst_information_views = paste(VIEWS, collapse = ", "),
    replicates = N_REP,
    audit_n = N_AUDIT,
    analysis_n = N_ANALYSIS,
    total_records_per_replicate = N_AUDIT + N_ANALYSIS,
    master_seed = MASTER_SEED,
    screen_familywise_alpha = SCREEN_ALPHA
  )
)
message(sprintf("run complete or resumed: %d returned rows", nrow(results)))
