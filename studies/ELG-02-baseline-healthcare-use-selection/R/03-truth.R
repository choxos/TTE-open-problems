## Study ELG-02: enumerate and cache deterministic truth by DGM cell.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:6

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.file_arg)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .file_arg[1]))))
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
selected <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  bounds <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  selected <- intersect(seq(bounds[1], bounds[2]), selected)
}

for (i in selected) {
  cache_file <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(cache_file)) {
    message(sprintf("scenario %d/%d: cached", i, nrow(scenarios)))
    next
  }
  scen <- scenarios[i, , drop = FALSE]
  started <- proc.time()[["elapsed"]]
  truth <- truth_for(scen)
  truth <- cbind(scen, truth)
  saveRDS(truth, cache_file)
  message(sprintf(
    "scenario %d/%d: %.1fs; RD_H=%.6f; RD_all=%.6f; nodes=%d; converged=%s",
    i, nrow(scenarios), proc.time()[["elapsed"]] - started,
    truth$rd_h, truth$rd_all, truth$quadrature_nodes, truth$quadrature_ok
  ))
}

cached <- sort(list.files(CACHE, "^scenario-[0-9]+\\.rds$", full.names = TRUE))
if (length(cached) < nrow(scenarios)) {
  message(sprintf(
    "%d of %d truth cells cached; rerun another slice to continue",
    length(cached), nrow(scenarios)
  ))
  quit(save = "no", status = 0)
}

truth <- do.call(rbind, lapply(cached, readRDS))
truth <- truth[order(truth$scenario), ]
rownames(truth) <- NULL
stopifnot(identical(truth$scenario, seq_len(nrow(scenarios))))
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
message(sprintf("truth written for %d unique DGM cells", nrow(truth)))
