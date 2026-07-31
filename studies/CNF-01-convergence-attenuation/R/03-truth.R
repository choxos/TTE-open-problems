## Study 1 (CNF-01): enumerate truth once per scenario and cache it.
##
##   Rscript R/03-truth.R
##
## Separate from the replicate run because it is the expensive deterministic
## part and because a truth recomputed per replicate would carry its own Monte
## Carlo error into every bias in the study.

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

scen <- build_scenarios()

## Resumable per scenario, and each scenario seeded from the master seed plus its
## own index. Enumerating 24 scenarios at two million individuals each takes
## about three quarters of an hour, which is longer than one session will
## reliably hold, and a truth that silently changes because the run was
## restarted would be worse than one that took longer.
CACHE <- file.path(OUT, "truth-cache")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

## `--only i:j` runs a slice of the scenario list, so a long enumeration can be
## walked through in pieces without losing what is already done.
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scen))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":")[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

for (i in sel) {
  f <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(f)) { message(sprintf("scenario %2d/%d: cached", i, nrow(scen))); next }
  s <- scen[i, , drop = FALSE]
  set.seed(MASTER_SEED + i)
  t0 <- proc.time()[["elapsed"]]
  tr <- truth_for(s)
  tr <- cbind(s[rep(1L, nrow(tr)), , drop = FALSE], tr)
  rownames(tr) <- NULL
  saveRDS(tr, f)
  message(sprintf("scenario %2d/%d (%s, C120=%.2f, %s, %s): %.0fs  RD_ITT(120)=%.4f  RD_PP(120)=%.4f  A(120)=%.3f",
                  i, nrow(scen), s$shape, s$target_c120, s$alpha_l_key, s$persistence,
                  proc.time()[["elapsed"]] - t0,
                  tr$rd_itt[tr$horizon == 120L], tr$rd_pp[tr$horizon == 120L],
                  tr$attenuation[tr$horizon == 120L]))
}

done <- sort(list.files(CACHE, "^scenario-.*\\.rds$", full.names = TRUE))
if (length(done) < nrow(scen)) {
  message(sprintf("%d of %d scenarios enumerated; rerun to continue",
                  length(done), nrow(scen)))
  quit(save = "no", status = 0)
}
truth <- do.call(rbind, lapply(done, readRDS))
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)
message(sprintf("truth written for %d scenarios x %d horizons",
                nrow(scen), length(HORIZONS)))
