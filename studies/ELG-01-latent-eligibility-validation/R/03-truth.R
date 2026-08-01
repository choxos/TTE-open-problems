## ELG-01: calibrate recording and enumerate truth from the mechanism.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:8
##
## Scenario caches make both calibration and truth enumeration resumable.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

OUT <- here('results')
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
CAL_FILE <- file.path(OUT, 'recording-calibration.rds')
if (file.exists(CAL_FILE)) {
  calibration <- readRDS(CAL_FILE)
} else {
  calibration <- calibrate_recording()
  saveRDS(calibration, CAL_FILE)
  utils::write.csv(calibration, file.path(OUT, 'recording-calibration.csv'),
                   row.names = FALSE)
}
set_recording_alphas(calibration)

scenarios <- build_scenarios()
CACHE <- file.path(OUT, 'truth-cache')
CORE <- file.path(OUT, 'truth-core-cache')
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(CORE, recursive = TRUE, showWarnings = FALSE)

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl('^\\d+:\\d+$', args[1L])) {
  p <- as.integer(strsplit(args[1L], ':', fixed = TRUE)[[1L]])
  sel <- intersect(seq.int(p[1L], p[2L]), sel)
}

core_name <- function(s) {
  paste0(
    'm', sprintf('%02d', round(100 * s$m)),
    '-k', gsub('\\.', 'p', sprintf('%.2f', s$kappa)),
    '-', s$lambda_key, '-', s$effect, '.rds'
  )
}

for (i in sel) {
  scenario_file <- file.path(CACHE, sprintf('scenario-%03d.rds', i))
  if (file.exists(scenario_file)) {
    message(sprintf('scenario %d/%d: cached', i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  core_file <- file.path(CORE, core_name(s))
  if (file.exists(core_file)) {
    core <- readRDS(core_file)
  } else {
    ## Every scenario restarts the same shared truth stream. Consequently paired
    ## laws are integrated over exactly the same 10,000,000 covariate records.
    set.seed(TRUTH_SEED)
    t0 <- proc.time()[['elapsed']]
    core <- truth_for(s)
    saveRDS(core, core_file)
    message(sprintf('truth core %s: %.1fs', basename(core_file),
                    proc.time()[['elapsed']] - t0))
  }
  out <- cbind(s, core)
  rownames(out) <- NULL
  saveRDS(out, scenario_file)
  message(sprintf('scenario %d/%d: PE %.5f, RD_E %.5f, RD_RE %.5f',
                  i, nrow(scenarios), out$pe, out$rd_e, out$rd_re))
}

ID_FILE <- file.path(OUT, 'identification-truth.rds')
if (!file.exists(ID_FILE)) {
  set.seed(TRUTH_SEED)
  id_truth <- truth_identification(ALPHA_M[match(0.50, MISSING_PROPORTIONS)])
  saveRDS(id_truth, ID_FILE)
  utils::write.csv(id_truth, file.path(OUT, 'identification-truth.csv'),
                   row.names = FALSE)
} else {
  id_truth <- readRDS(ID_FILE)
}

finished <- sort(list.files(CACHE, '^scenario-.*\\.rds$', full.names = TRUE))
if (length(finished) < nrow(scenarios)) {
  message(sprintf('%d of %d scenario truths cached; rerun or continue with a slice',
                  length(finished), nrow(scenarios)))
  quit(save = 'no', status = 0)
}
truth <- do.call(rbind, lapply(finished, readRDS))
truth <- truth[order(truth$scenario), ]
rownames(truth) <- NULL
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth, file.path(OUT, 'truth.csv'), row.names = FALSE)
message(sprintf('truth written for %d scenarios; Delta_ID %.6f, MCSE %.6g',
                nrow(truth), id_truth$delta_id, id_truth$mcse))
