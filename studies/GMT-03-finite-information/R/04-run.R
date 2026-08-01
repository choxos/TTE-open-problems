## Study GMT-03: run the resumable simulation.
##
## Usage: Rscript R/04-run.R
##        Rscript R/04-run.R 1:1

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1L])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUT <- here("results")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
design <- prepare_design(OUT)
scenarios <- design$scenarios
if (!file.exists(file.path(OUT, "truth.rds")))
  stop("Run R/03-truth.R before the replicate driver")

## The nuisance-aware exact sandwich is admitted to the main run only after 20
## fixed pilot replicates pass the analytic derivative check.
pilot_file <- file.path(OUT, paste0("derivative-validation-", PROFILE, ".csv"))
if (!file.exists(pilot_file)) {
  pilot_s <- scenarios[scenarios$phase == "core" & scenarios$k_level == "K0" &
                         scenarios$n == 1000L, , drop = FALSE]
  differences <- numeric()
  attempt <- 0L
  while (length(differences) < 20L && attempt < 100L) {
    attempt <- attempt + 1L
    set.seed(PILOT_SEED + attempt)
    dat <- gen_replicate(pilot_s[(attempt - 1L) %% nrow(pilot_s) + 1L, , drop = FALSE])
    z <- validate_exact_derivative(dat)
    if (is.finite(z)) differences <- c(differences, z)
  }
  if (length(differences) < 20L || max(differences) >= 1e-6)
    stop("Analytic exact-sandwich derivatives failed the 20-replicate pilot")
  utils::write.csv(data.frame(pilot = seq_along(differences),
                              maximum_absolute_disagreement = differences),
                   pilot_file, row.names = FALSE)
}

## Critique fix: the K0 pilot checks standardized cumulative-incidence code
## against independently calculated weighted arm-month cumulative incidences.
msm_pilot_file <- file.path(OUT, paste0("msm-k0-validation-", PROFILE, ".csv"))
if (!file.exists(msm_pilot_file)) {
  ps <- scenarios[scenarios$phase == "core" & scenarios$k_level == "K0" &
                    scenarios$n == 16000L & scenarios$alpha_y_key == "common" &
                    scenarios$alpha_d_key == "common", , drop = FALSE][1L, ]
  set.seed(PILOT_SEED + 1000L)
  pv <- validate_msm_k0(gen_replicate(ps))
  utils::write.csv(pv, msm_pilot_file, row.names = FALSE)
}

## Every replicate has a fixed 72-row estimand grid and a fixed 720-row monthly
## diagnostic grid. Errors therefore remain in the convergence denominator.
blank_replicate <- function(why) {
  est <- blank_estimates(METHODS, why)
  diag <- expand.grid(method = c("exact_fixed", "msm"),
                      subgroup = c("all", "G0", "G1"), strategy = 0:1,
                      month = seq_len(N_MONTHS), stringsAsFactors = FALSE)
  diag$row_type <- "diagnostic"
  diag$fail <- why
  complete_result(rbind(est, complete_result(diag)))
}

one_rep <- function(scen, rep_id) {
  dat <- try(gen_replicate(scen, n = as.integer(scen$n)), silent = TRUE)
  if (inherits(dat, "try-error")) return(blank_replicate("dgm-failed"))
  ans <- try(estimate_replicate(dat, scen), silent = TRUE)
  if (inherits(ans, "try-error")) return(blank_replicate("replicate-error"))
  ans
}

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1L])) {
  p <- as.integer(strsplit(args[1L], ":", fixed = TRUE)[[1L]])
  sel <- intersect(seq(p[1L], p[2L]), sel)
}

res <- run_design(
  one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUT, workers = WORKERS, resume = TRUE, only = sel
)

write_provenance(
  OUT,
  packages = c("stats", "future", "furrr"),
  extra = list(
    study = "GMT-03 finite-information performance",
    profile = PROFILE,
    scenarios = nrow(scenarios),
    replicates = N_REP,
    months = N_MONTHS,
    calibration_histories = N_CALIBRATION,
    bootstrap_resamples = BOOT_B,
    master_seed = MASTER_SEED,
    scaled_down = SCALE_NOTE
  )
)
message(sprintf("done: %d rows returned by the selected scenario run", nrow(res)))
