## Study 1 (CNF-01): run the design.
##
##   Rscript R/03-truth.R      (first, and once)
##   Rscript R/04-run.R
##
## Resumable: completed scenarios are cached under results/raw/ and skipped.

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
TRUTH <- readRDS(file.path(OUTDIR, "truth.rds"))

METHODS <- c("gformula", "iptw")

## Every replicate returns the same rows whatever happens to it, so convergence
## has a real denominator and a scenario where one method fails more often is
## visible rather than silently better-behaved.
blank <- function(why) {
  g <- expand.grid(method = METHODS, horizon = HORIZONS,
                   stringsAsFactors = FALSE)
  data.frame(g, est = NA_real_, se = NA_real_, c_obs = NA_real_,
             fail = why, stringsAsFactors = FALSE)
}

one_rep <- function(scen, rep_id) {
  dat <- tryCatch(gen_replicate(scen, n = N_PER_ARM), error = function(e) NULL)
  if (is.null(dat)) return(blank("dgm-failed"))

  rows <- list()
  for (h in HORIZONS) {
    ## The diagnostic exactly as an applied paper would compute it: from the
    ## observed comparator arm of this replicate, not from the mechanism.
    c_obs <- init_incidence(dat, h)
    g <- tryCatch(est_gformula(dat, h),
                  error = function(e) c(est = NA_real_, se = NA_real_))
    i <- tryCatch(est_iptw(dat, h),
                  error = function(e) c(est = NA_real_, se = NA_real_))
    rows[[length(rows) + 1L]] <- data.frame(
      method = c("gformula", "iptw"), horizon = h,
      est = c(g[["est"]], i[["est"]]), se = c(g[["se"]], i[["se"]]),
      c_obs = c_obs, stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, rows)
  out$fail <- ifelse(is.na(out$est), "no-estimate", NA_character_)
  out
}

scenarios <- build_scenarios()

## `Rscript R/04-run.R 16:18` runs a slice. run_design already caches per
## scenario and skips what is done, but a process killed part way through a
## scenario loses that scenario's work, so on a machine that will not hold a
## long process the slice is what makes progress monotone. The seed streams are
## indexed by absolute scenario number, so a slice draws exactly the data the
## full run would have drawn for those scenarios.
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":")[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

res <- run_design(one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
                  outdir = OUTDIR, only = sel)

write_provenance(
  OUTDIR,
  packages = c("stats", "future", "furrr"),
  extra = list(
    study = "CNF-01 convergence attenuation",
    scenarios = nrow(scenarios),
    replicates = N_REP,
    n_per_replicate = N_PER_ARM,
    master_seed = MASTER_SEED,
    truth_n = N_TRUTH,
    horizons = paste(HORIZONS, collapse = ", ")
  )
)

message(sprintf("done: %d rows", nrow(res)))
