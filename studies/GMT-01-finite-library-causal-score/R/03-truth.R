## GMT-01: enumerate and cache truth, DGM checks, and structural checks.
## Usage: Rscript R/03-truth.R [i:j]

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
CACHE <- file.path(OUT, "truth-cache")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":")[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

for (i in sel) {
  file <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(file)) {
    message(sprintf("scenario %d/%d: cached", i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  t0 <- proc.time()[["elapsed"]]
  set.seed(MASTER_SEED + i)
  truth <- truth_for(s)
  set.seed(MASTER_SEED + 100000L + i)
  check <- dgm_population_check(s)
  set.seed(MASTER_SEED + 200000L + i)
  matrix_check <- validate_candidate_matrices(s)
  saveRDS(list(version = DESIGN_VERSION, scenario = s, truth = truth,
               dgm_check = check, matrix_check = matrix_check), file)
  message(sprintf("scenario %d/%d: %.1fs, truth %.6f, MCSE %.6f, N %d",
                  i, nrow(scenarios), proc.time()[["elapsed"]] - t0,
                  truth$truth, truth$truth_mcse, truth$truth_n))
}

files <- file.path(CACHE, sprintf("scenario-%03d.rds", seq_len(nrow(scenarios))))
if (!all(file.exists(files))) {
  message(sprintf("%d of %d scenarios complete; rerun or supply another slice",
                  sum(file.exists(files)), length(files)))
  quit(save = "no", status = 0)
}
objects <- lapply(files, readRDS)
if (any(vapply(objects, function(x) !identical(x$version, DESIGN_VERSION), logical(1))))
  stop("truth cache has a different design version")

truth <- do.call(rbind, lapply(objects, function(x)
  cbind(x$scenario, x$truth, row.names = NULL)))
dgm <- do.call(rbind, lapply(objects, function(x)
  cbind(x$scenario, x$dgm_check, row.names = NULL)))
mat <- do.call(rbind, lapply(objects, function(x)
  cbind(x$scenario, x$matrix_check, row.names = NULL)))
rownames(truth) <- rownames(dgm) <- rownames(mat) <- NULL
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
utils::write.csv(dgm, file.path(OUT, "dgm-check.csv"), row.names = FALSE)
utils::write.csv(mat, file.path(OUT, "matrix-diagnostics.csv"), row.names = FALSE)
message("truth and preflight diagnostics written for all scenarios")
