## Study 2 (BEN-02): enumerate and cache exact finite-cell truths.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:4

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
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[[1]])) {
  bounds <- as.integer(strsplit(args[[1]], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(bounds[[1]], bounds[[2]]), sel)
}

for (i in sel) {
  path <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(path)) {
    message(sprintf("scenario %2d/%d: cached", i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  tr <- cbind(s, truth_for(s))
  if (!isTRUE(tr$truth_check[[1]])) {
    stop(sprintf("finite-cell truth check failed for scenario %d", i))
  }
  saveRDS(tr, path)
  message(sprintf(
    "scenario %2d/%d: deltaRaw=%.6f deltaObservedAlign=%.6f error=%.3g",
    i, nrow(scenarios), tr$delta_raw_true,
    tr$delta_observed_align_true, tr$summation_error
  ))
}

paths <- file.path(CACHE, sprintf("scenario-%03d.rds", seq_len(nrow(scenarios))))
if (!all(file.exists(paths))) {
  message(sprintf(
    "%d of %d scenarios enumerated; rerun or request another slice to continue",
    sum(file.exists(paths)), length(paths)
  ))
  quit(save = "no", status = 0)
}

truth <- do.call(rbind, lapply(paths, readRDS))
truth <- truth[order(truth$scenario), ]
rownames(truth) <- NULL
stopifnot(all(truth$truth_check), max(truth$summation_error) < 1e-12)
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
message(sprintf("truth written for %d structural scenarios", nrow(truth)))
