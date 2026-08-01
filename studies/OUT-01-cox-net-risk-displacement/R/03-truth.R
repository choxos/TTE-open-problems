## OUT-01 mechanism study: enumerate and lock truth.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:6

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
CACHE <- file.path(OUT, "truth-cache")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()
spec <- truth_lock_spec()

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  bounds <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(bounds[1], bounds[2]), sel)
}

for (i in sel) {
  path <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(path)) {
    cached <- readRDS(path)
    if (!identical(cached$spec, spec))
      stop("truth cache does not match the current mechanism: ", path)
    message(sprintf("scenario %02d/%d: cached", i, nrow(scenarios)))
    next
  }

  started <- proc.time()[["elapsed"]]
  tr <- truth_for(scenarios[i, , drop = FALSE])
  elapsed <- proc.time()[["elapsed"]] - started
  tr <- cbind(scenarios[i, , drop = FALSE][rep(1L, nrow(tr)), , drop = FALSE], tr)
  tr$truth_elapsed_sec <- elapsed
  rownames(tr) <- NULL
  saveRDS(list(spec = spec, truth = tr), path)
  message(sprintf(
    "scenario %02d/%d: %.1fs, batches %d, max MCSE %.6f, displacement60 %.4f",
    i, nrow(scenarios), elapsed, max(tr$truth_batches),
    max(tr$truth_mcse_max), tr$displacement[tr$horizon == 60L]
  ))
}

paths <- sort(list.files(CACHE, "^scenario-.*\\.rds$", full.names = TRUE))
if (length(paths) < nrow(scenarios)) {
  message(sprintf("%d of %d scenarios complete; rerun another slice",
                  length(paths), nrow(scenarios)))
  quit(save = "no", status = 0)
}

objects <- lapply(paths, readRDS)
if (!all(vapply(objects, function(x) identical(x$spec, spec), logical(1))))
  stop("at least one truth cache has a different mechanism specification")
truth <- do.call(rbind, lapply(objects, `[[`, "truth"))
truth <- truth[order(truth$scenario, truth$horizon), , drop = FALSE]
rownames(truth) <- NULL
if (length(unique(truth$scenario)) != nrow(scenarios) ||
    any(truth$truth_mcse_max > TRUTH_MCSE_LIMIT))
  stop("the complete truth surface did not satisfy its lock conditions")

## Critique fix: the full truth surface is archived and locked before any
## estimator replication. 04-run.R refuses a missing or mismatched lock.
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
saveRDS(list(spec = spec, scenarios = nrow(scenarios), locked = Sys.time()),
        file.path(OUT, "truth.lock.rds"))
message(sprintf("truth locked for %d scenarios and %d horizons",
                nrow(scenarios), length(HORIZONS)))
