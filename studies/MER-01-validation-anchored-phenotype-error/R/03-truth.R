## Study 2 (MER-01): enumerate and cache intervention truth.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
CACHE <- file.path(OUT, "truth-cache")
LAW_CACHE <- file.path(CACHE, "laws")
dir.create(LAW_CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1L])) {
  p <- as.integer(strsplit(args[1L], ":", fixed = TRUE)[[1L]])
  sel <- intersect(seq.int(p[1L], p[2L]), sel)
}

laws <- unique(scenarios$truth_law)
for (i in sel) {
  target <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(target)) {
    message(sprintf("scenario %d/%d: cached", i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  law_file <- file.path(LAW_CACHE, paste0(s$truth_law, ".rds"))
  if (!file.exists(law_file)) {
    law_index <- match(s$truth_law, laws)
    set.seed(MASTER_SEED + 100000L + law_index)
    tr <- truth_for_law(s$truth_law, N_TRUTH)
    if (any(tr$truth_mcse >= 0.0005)) {
      stop("truth Monte Carlo SE gate failed for ", s$truth_law)
    }
    saveRDS(tr, law_file)
  }
  tr <- readRDS(law_file)
  tr <- cbind(s[rep(1L, nrow(tr)), , drop = FALSE], tr)
  rownames(tr) <- NULL
  saveRDS(tr, target)
  message(sprintf("scenario %d/%d: %s, RDdyn %.5f, MCSE %.6f",
                  i, nrow(scenarios), s$truth_law,
                  tr$truth[tr$estimand == "dynamic"],
                  tr$truth_mcse[tr$estimand == "dynamic"]))
}

done <- file.path(CACHE, sprintf("scenario-%03d.rds", seq_len(nrow(scenarios))))
if (!all(file.exists(done))) {
  message(sprintf("%d of %d scenario truth files complete; rerun or use another slice",
                  sum(file.exists(done)), length(done)))
  quit(save = "no", status = 0)
}
truth <- do.call(rbind, lapply(done, readRDS))
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
message("truth written for 81 scenarios")
