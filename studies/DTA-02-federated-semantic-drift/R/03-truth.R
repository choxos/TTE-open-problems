## DTA-02: enumerate exact truths and freeze aggregate-gate calibration.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:2
##
## The optional slice addresses the six common-random-number blocks. Each block
## contains twelve formal ADEMP scenarios. Scenario truth files remain separate
## and are skipped on restart.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

OUT <- here('results')
CACHE <- file.path(OUT, 'truth-cache')
CAL <- file.path(OUT, 'calibration')
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(CAL, recursive = TRUE, showWarnings = FALSE)

blocks <- build_scenarios()
formal <- build_ademp_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(blocks))
if (length(args) && grepl('^\\d+:\\d+$', args[1])) {
  p <- as.integer(strsplit(args[1], ':')[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

verification_file <- file.path(OUT, 'aggregate-generator-verification.rds')
if (!file.exists(verification_file)) {
  set.seed(MASTER_SEED - 1L)
  verification <- verify_aggregate_generator()
  saveRDS(verification, verification_file)
} else {
  verification <- readRDS(verification_file)
}
if (!isTRUE(verification$pass)) {
  stop('aggregate-count and row-level generator verification disagreed; max |z| = ',
       verification$max_abs_z)
}

q <- canonical_q()

for (bi in sel) {
  b <- blocks[bi, , drop = FALSE]
  fs <- formal_scenarios_for(b$kappa, b$gamma)

  ## Compatible critical distributions are frozen before mismatch replicates.
  for (j in seq_len(N_SITES)) {
    for (component in c('eligibility', 'exposure', 'outcome')) {
      path <- calibration_file(CAL, b$kappa, b$gamma, j, component)
      if (!file.exists(path)) {
        seed <- MASTER_SEED + 100000L + bi * 100L + j * 10L +
          match(component, c('eligibility', 'exposure', 'outcome'))
        set.seed(seed)
        ref <- calibrate_component(j, b$kappa, b$gamma, component)
        saveRDS(ref, path)
      }
    }
  }

  for (ii in seq_len(nrow(fs))) {
    s <- fs[ii, , drop = FALSE]
    path <- file.path(CACHE, sprintf('scenario-%03d.rds', s$formal_scenario))
    if (file.exists(path)) next
    tr <- truth_for_formal(s, q)
    tr$design <- s
    saveRDS(tr, path)
    message(sprintf('truth scenario %d/72: %s, kappa %.1f, gamma %.2f, %s',
                    s$formal_scenario, s$mapping, s$kappa, s$gamma, s$reference))
  }
}

paths <- file.path(CACHE, sprintf('scenario-%03d.rds', formal$formal_scenario))
if (!all(file.exists(paths))) {
  message(sum(file.exists(paths)), ' of 72 formal scenarios cached; rerun to continue')
  quit(save = 'no', status = 0)
}

truths <- lapply(paths, readRDS)
truth <- list(
  complete = TRUE,
  q = q,
  scenario = do.call(rbind, lapply(truths, `[[`, 'scenario')),
  site = do.call(rbind, lapply(truths, `[[`, 'site')),
  design = formal,
  verification = verification,
  calibration_draws = N_CALIBRATION
)
rownames(truth$scenario) <- NULL
rownames(truth$site) <- NULL
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth$scenario, file.path(OUT, 'truth.csv'), row.names = FALSE)
utils::write.csv(truth$site, file.path(OUT, 'site-truth.csv'), row.names = FALSE)
message('exact truth written for 72 scenarios; aggregate calibration uses ',
        N_CALIBRATION, ' draws per site and component')
