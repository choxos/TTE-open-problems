## Study 2 (PRO-02): calibrate the mechanism, enumerate truth, and lock diagnostics.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:3
##
## The slice addresses the 18 unique truth cells. Each completed cell is cached.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

lambda_file <- file.path(OUT, "lambda.rds")
if (!file.exists(lambda_file)) {
  set.seed(LAMBDA_SEED)
  message("calibrating six locked baseline hazards")
  lambda_table <- calibrate_lambdas()
  saveRDS(lambda_table, lambda_file)
  utils::write.csv(lambda_table, file.path(OUT, "lambda.csv"), row.names = FALSE)
} else {
  lambda_table <- readRDS(lambda_file)
}

scenarios <- attach_lambdas(build_truth_scenarios(), lambda_table)
CACHE <- file.path(OUT, "truth-cache")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

for (i in sel) {
  cache_file <- file.path(CACHE, sprintf("truth-%03d.rds", i))
  if (file.exists(cache_file)) {
    message(sprintf("truth cell %2d/%d: cached", i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  set.seed(TRUTH_SEED + i)
  t0 <- proc.time()[["elapsed"]]
  tr <- truth_for(s)
  tr <- cbind(s[rep(1L, nrow(tr)), , drop = FALSE], tr)
  rownames(tr) <- NULL
  saveRDS(tr, cache_file)
  message(sprintf(
    "truth cell %2d/%d: n=%d, events=%d, effect=%s, draws=%d, max MCSE=%.7f, %.0fs",
    i, nrow(scenarios), s$n, s$event_target, s$effect,
    max(tr$truth_draws), max(tr$truth_mcse),
    proc.time()[["elapsed"]] - t0))
}

expected <- file.path(CACHE, sprintf("truth-%03d.rds", seq_len(nrow(scenarios))))
if (!all(file.exists(expected))) {
  message(sprintf("%d of %d truth cells complete; rerun or run another slice",
                  sum(file.exists(expected)), length(expected)))
  quit(save = "no", status = 0)
}

truth <- do.call(rbind, lapply(expected, readRDS))
rownames(truth) <- NULL
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)

## Critique fixes: expected event-count distances and both non-oracle score
## alignments are locked before any coverage replicate is generated.
diagnostic_file <- file.path(OUT, "design-diagnostics.rds")
if (!file.exists(diagnostic_file)) {
  set.seed(DIAGNOSTIC_SEED)
  generated <- attach_lambdas(build_scenarios(), lambda_table)
  diagnostic <- design_diagnostics(generated)
  saveRDS(diagnostic, diagnostic_file)
  utils::write.csv(diagnostic, file.path(OUT, "design-diagnostics.csv"),
                   row.names = FALSE)
}

message(sprintf("truth locked for %d parameter cells and %d candidate rows",
                nrow(scenarios), nrow(truth)))
