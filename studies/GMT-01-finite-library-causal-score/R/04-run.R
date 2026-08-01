## GMT-01: run the resumable simulation.
## Usage: Rscript R/04-run.R [i:j]

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUT <- here("results")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUT, "truth.rds")),
          file.exists(file.path(OUT, "matrix-diagnostics.csv")),
          file.exists(file.path(OUT, "dgm-check.csv")))
preflight <- utils::read.csv(file.path(OUT, "matrix-diagnostics.csv"))
if (any(!preflight$ok)) stop("matrix preflight did not pass")

one_rep <- function(scen, rep_id) {
  t0 <- proc.time()[["elapsed"]]
  dat <- tryCatch(gen_replicate(scen, n = N_PERSON), error = function(e) NULL)
  if (is.null(dat)) {
    out <- blank_results("dgm-failed")
  } else {
    out <- tryCatch(run_estimators(dat), error = function(e) {
      z <- blank_results("estimator-error")
      attr(z, "error") <- conditionMessage(e)
      z
    })
  }
  out$replicate <- rep_id
  out$runtime_seconds <- proc.time()[["elapsed"]] - t0
  out
}

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":")[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

res <- run_design(
  one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUT, workers = WORKERS, resume = TRUE, only = sel
)

write_provenance(
  OUT,
  packages = c("stats", "future", "furrr"),
  extra = list(
    study = "GMT-01 finite-library causal-score selection",
    design_version = DESIGN_VERSION,
    scenarios = nrow(scenarios), n_per_replicate = N_PERSON,
    protocol_replicates = N_REP_PROTOCOL, implemented_replicates = N_REP,
    workers = WORKERS, outer_folds = OUTER_FOLDS, inner_folds = INNER_FOLDS,
    truth_block = N_TRUTH_BLOCK, master_seed = MASTER_SEED,
    scale = "residual-standard-deviation units"
  )
)
message(sprintf("done: %d returned rows", nrow(res)))
