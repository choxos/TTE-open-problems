## Study GMT-03: enumerate and cache mechanism truth.
##
## Usage: Rscript R/03-truth.R
##        Rscript R/03-truth.R 1:20

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1L])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
design <- prepare_design(OUT)
scenarios <- design$scenarios

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1L])) {
  p <- as.integer(strsplit(args[1L], ":", fixed = TRUE)[[1L]])
  sel <- intersect(seq(p[1L], p[2L]), sel)
}

CACHE <- file.path(OUT, paste0("truth-cache-", PROFILE))
MECH <- file.path(OUT, paste0("truth-mechanisms-", PROFILE))
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(MECH, recursive = TRUE, showWarnings = FALSE)

for (i in sel) {
  target <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(target)) {
    message(sprintf("scenario %d/%d: cached", i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  key <- truth_key(s)
  mechanism_file <- file.path(MECH, paste0(key, ".rds"))
  if (file.exists(mechanism_file)) {
    tr <- readRDS(mechanism_file)
  } else {
    set.seed(truth_seed(s))
    t0 <- proc.time()[["elapsed"]]
    tr <- truth_for(s)
    saveRDS(tr, mechanism_file)
    message(sprintf("truth mechanism %s: %.1fs", key,
                    proc.time()[["elapsed"]] - t0))
  }
  out <- cbind(s[rep(1L, nrow(tr)), , drop = FALSE], tr)
  rownames(out) <- NULL
  saveRDS(out, target)
  message(sprintf("scenario %d/%d: truth cached", i, nrow(scenarios)))
}

files <- file.path(CACHE, sprintf("scenario-%03d.rds", seq_len(nrow(scenarios))))
if (!all(file.exists(files))) {
  message(sprintf("%d of %d scenario truth files exist; rerun or use another slice",
                  sum(file.exists(files)), length(files)))
  quit(save = "no", status = 0)
}
truth <- do.call(rbind, lapply(files, readRDS))
rownames(truth) <- NULL
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
message(sprintf("truth written for %d scenarios and %d estimands",
                nrow(scenarios), nrow(endpoint_grid())))
