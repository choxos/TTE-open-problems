## Study 2 (BEN-02): run nested benchmark-pair replicates.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:4
##
## Completed structural scenarios are cached by the shared harness. Absolute
## scenario indices determine seed streams, so sliced and full runs are equal.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
stopifnot(file.exists(here("R", "00-config.R")))

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUTDIR <- here("results")
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUTDIR, "truth.rds")))
truth <- readRDS(file.path(OUTDIR, "truth.rds"))
stopifnot(all(truth$truth_check), max(truth$summation_error) < 1e-12)

## The literature method is blocked unless its frozen source-equation checks
## pass. This is a protocol-integrity gate, not a replicate-level failure.
source_checks <- sceptical_source_checks()
utils::write.csv(
  source_checks,
  file.path(OUTDIR, "sceptical-source-checks.csv"),
  row.names = FALSE
)
if (!all(source_checks$passed)) stop("sceptical source checks failed")

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[[1]])) {
  bounds <- as.integer(strsplit(args[[1]], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(bounds[[1]], bounds[[2]]), sel)
}
if (!length(sel)) stop("scenario slice is empty")

## A cached 100-replicate pilot reports observed fits per second before the full
## run. It estimates runtime only. It cannot alter mechanisms, thresholds or
## replicate counts.
pilot_file <- file.path(OUTDIR, "pilot-runtime.csv")
if (!file.exists(pilot_file)) {
  pilot_out <- file.path(OUTDIR, "pilot")
  t0 <- proc.time()[["elapsed"]]
  invisible(run_design(
    run_replicate, scenarios,
    n_rep = PILOT_REP,
    master_seed = MASTER_SEED + 1000000L,
    outdir = pilot_out,
    workers = WORKERS,
    resume = TRUE,
    only = sel[[1]]
  ))
  elapsed <- max(proc.time()[["elapsed"]] - t0, 0.001)
  pilot_fits <- PILOT_REP * nrow(PRECISION)
  full_fits <- nrow(scenarios) * N_REP * nrow(PRECISION)
  fits_per_second <- pilot_fits / elapsed
  projected_hours <- full_fits / fits_per_second / 3600
  pilot <- data.frame(
    pilot_scenario = sel[[1]],
    pilot_replicates = PILOT_REP,
    pilot_fits = pilot_fits,
    elapsed_seconds = elapsed,
    fits_per_second = fits_per_second,
    projected_full_fits = full_fits,
    projected_full_hours = projected_hours,
    overnight_ceiling_hours = OVERNIGHT_HOURS,
    stringsAsFactors = FALSE
  )
  utils::write.csv(pilot, pilot_file, row.names = FALSE)
  message(sprintf(
    "pilot: %.2f fits/second; revised full runtime %.2f hours",
    fits_per_second, projected_hours
  ))
  if (projected_hours > OVERNIGHT_HOURS) {
    warning("pilot projection exceeds the overnight ceiling; the prespecified full design is unchanged")
  }
}

if (identical(Sys.getenv("BEN02_PILOT_ONLY"), "1")) {
  message("pilot complete; BEN02_PILOT_ONLY requested no full run")
  quit(save = "no", status = 0)
}

res <- run_design(
  run_replicate, scenarios,
  n_rep = N_REP,
  master_seed = MASTER_SEED,
  outdir = OUTDIR,
  workers = WORKERS,
  resume = TRUE,
  only = sel
)

write_provenance(
  OUTDIR,
  packages = c("stats", "future", "furrr"),
  extra = list(
    study = "BEN-02 pair-level precision sensitivity",
    structural_scenarios = nrow(scenarios),
    replicates_per_scenario = N_REP,
    precision_levels = paste(PRECISION$precision, collapse = ", "),
    trial_sizes = paste(PRECISION$n_trial, collapse = ", "),
    emulation_sizes = paste(PRECISION$n_emulation, collapse = ", "),
    master_seed = MASTER_SEED,
    primary_delta = DELTA_PRIMARY,
    bootstrap_resamples = N_BOOT,
    sceptical_source = SCEPTICAL_SOURCE,
    sceptical_locator = SCEPTICAL_LOCATOR,
    sceptical_equation = SCEPTICAL_EQUATION
  )
)

message(sprintf("done: %d returned rows", nrow(res)))
