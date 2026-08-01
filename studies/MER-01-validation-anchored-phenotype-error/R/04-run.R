## Study 2 (MER-01): run the resumable simulation.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUTDIR <- here("results")
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUTDIR, "truth.rds")))
scenarios <- build_scenarios()

## Critique fix: M is selected before the full replicate run by conditional
## Monte Carlo calibration. The calibration object is cached and therefore does
## not change when a scenario slice is resumed.
cal_file <- file.path(OUTDIR, "mi-calibration.rds")
if (!file.exists(cal_file)) {
  set.seed(MASTER_SEED + 900000L)
  calibration <- calibrate_imputations(scenarios)
  saveRDS(calibration, cal_file)
} else calibration <- readRDS(cal_file)
MI_M <- calibration$selected_M
if (FULL_PROTOCOL && !isTRUE(calibration$passed) && MI_M < 800L) {
  stop("full-protocol MI calibration failed and did not reach M=800")
}

patterns_for <- function(scen) {
  ## Joint-error cells also analyze A-only, L-only, and no-error views of the
  ## same latent cohort and error draws. This supplies genuinely paired
  ## contributions for B_AL - B_A - B_L + B_0.
  if (scen$nodes == "AL") PATTERNS else scen$nodes
}

scheduled_methods <- function(scen, rep_id) {
  rows <- list()
  for (pattern in patterns_for(scen)) {
    for (method in c("first_order", "rich", "exact_filter")) {
      rows[[length(rows) + 1L]] <- c(method = method, pattern = pattern,
                                     M = NA, prior = NA)
    }
  }
  rows[[length(rows) + 1L]] <- c(method = "oracle", pattern = "latent", M = NA, prior = NA)
  rows[[length(rows) + 1L]] <- c(method = "corrected", pattern = scen$nodes,
                                 M = MI_M, prior = MI_PRIOR_SD)
  if (scen$benchmark != "" && rep_id %% 10L == 0L) {
    rows[[length(rows) + 1L]] <- c(method = "corrected_4M", pattern = scen$nodes,
                                   M = 4L * MI_M, prior = MI_PRIOR_SD)
  }
  ## Critique fix: prior sensitivity uses existing n=100 benchmark cells at
  ## accuracies 0.70 and 0.85, not a nonexistent n=100, accuracy-0.99 cell.
  if (scen$benchmark != "" && scen$validation_n == 100L &&
      scen$specification == "core") {
    for (ps in MI_PRIOR_SENSITIVITY) {
      rows[[length(rows) + 1L]] <- c(method = paste0("corrected_prior", ps),
                                     pattern = scen$nodes, M = MI_M, prior = ps)
    }
  }
  rows
}

blank_replicate <- function(scen, rep_id, why) {
  do.call(rbind, lapply(scheduled_methods(scen, rep_id), function(z)
    empty_rows(z[["method"]], z[["pattern"]], why,
               as.integer(z[["M"]]), as.numeric(z[["prior"]]))))
}

one_rep <- function(scen, rep_id) {
  dat <- try(gen_replicate(scen, N_PER_REP), silent = TRUE)
  if (inherits(dat, "try-error")) {
    out <- blank_replicate(scen, rep_id, "dgm-failed")
    out$rep_id <- rep_id
    return(out)
  }

  rows <- list()
  ## Critique fix: both a practical rich-history model and the known-law exact
  ## filter accompany the first-order status quo comparator.
  for (pattern in patterns_for(scen)) {
    rows[[length(rows) + 1L]] <- tryCatch(
      est_threshold(dat, scen, pattern, "first_order"),
      error = function(e) empty_rows("first_order", pattern, "estimator-error"))
    rows[[length(rows) + 1L]] <- tryCatch(
      est_threshold(dat, scen, pattern, "rich"),
      error = function(e) empty_rows("rich", pattern, "estimator-error"))
    rows[[length(rows) + 1L]] <- tryCatch(
      est_exact_filtered(dat, scen, pattern),
      error = function(e) empty_rows("exact_filter", pattern, "estimator-error"))
  }
  rows[[length(rows) + 1L]] <- tryCatch(
    est_oracle(dat, scen),
    error = function(e) empty_rows("oracle", "latent", "estimator-error"))
  rows[[length(rows) + 1L]] <- tryCatch(
    est_corrected(dat, scen, scen$nodes, MI_M),
    error = function(e) empty_rows("corrected", scen$nodes, "estimator-error", MI_M, MI_PRIOR_SD))

  if (scen$benchmark != "" && rep_id %% 10L == 0L) {
    rows[[length(rows) + 1L]] <- tryCatch(
      est_corrected(dat, scen, scen$nodes, 4L * MI_M, method = "corrected_4M"),
      error = function(e) empty_rows("corrected_4M", scen$nodes,
                                     "estimator-error", 4L * MI_M, MI_PRIOR_SD))
  }
  if (scen$benchmark != "" && scen$validation_n == 100L &&
      scen$specification == "core") {
    for (ps in MI_PRIOR_SENSITIVITY) {
      method <- paste0("corrected_prior", ps)
      rows[[length(rows) + 1L]] <- tryCatch(
        est_corrected(dat, scen, scen$nodes, MI_M, ps, method),
        error = function(e) empty_rows(method, scen$nodes, "estimator-error", MI_M, ps))
    }
  }
  out <- do.call(rbind, rows)
  out$rep_id <- rep_id
  out
}

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1L])) {
  p <- as.integer(strsplit(args[1L], ":", fixed = TRUE)[[1L]])
  sel <- intersect(seq.int(p[1L], p[2L]), sel)
}

res <- run_design(
  one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUTDIR, workers = WORKERS, resume = TRUE, only = sel)

write_provenance(
  OUTDIR,
  packages = c("stats", "splines", "mvtnorm", "data.table", "future", "furrr"),
  extra = list(
    study = "MER-01 validation-anchored longitudinal phenotype error",
    scenarios = nrow(scenarios), replicates = N_REP,
    n_per_replicate = N_PER_REP, truth_n = N_TRUTH,
    selected_M = MI_M, full_protocol = FULL_PROTOCOL,
    scaled_run = SCALED_RUN, master_seed = MASTER_SEED)
)
message(sprintf("done: %d rows; selected M=%d", nrow(res), MI_M))
