## MER-01: enumerate and cache mechanism truth, then calibrate MI.
##
## Usage:
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:20

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
         else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

OUT <- here('results')
CACHE <- file.path(OUT, 'truth-cache')
LAW_CACHE <- file.path(OUT, 'truth-law-cache')
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(LAW_CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1])) {
  p <- as.integer(strsplit(args[1], ':', fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

truth_keys <- unique(vapply(seq_len(nrow(scenarios)), function(i)
  truth_key_for(scenarios[i, ]), character(1)))

for (i in sel) {
  scenario_file <- file.path(CACHE, sprintf('scenario-%03d.rds', i))
  if (file.exists(scenario_file)) {
    message(sprintf('scenario %d/%d: cached', i, nrow(scenarios)))
    next
  }
  scen <- scenarios[i, ]
  key <- truth_key_for(scen)
  law_file <- file.path(LAW_CACHE, paste0(key, '.rds'))
  if (!file.exists(law_file)) {
    law_index <- match(key, truth_keys)
    set.seed(MASTER_SEED + 100000L + law_index)
    t0 <- proc.time()[['elapsed']]
    truth <- truth_for(scen)
    if (any(!is.finite(truth$truth_mcse)) ||
        max(truth$truth_mcse) >= TRUTH_MCSE_MAX)
      stop('truth Monte Carlo SE gate failed for ', key)
    saveRDS(truth, law_file)
    message(sprintf('truth law %s: %.1f seconds, max MCSE %.6f', key,
                    proc.time()[['elapsed']] - t0,
                    max(truth$truth_mcse)))
  }
  truth <- readRDS(law_file)
  truth$cell_id <- scen$scenario
  truth$truth_key <- key
  truth <- truth[, c('cell_id', 'truth_key', 'contrast', 'risk_1', 'risk_0',
                     'truth', 'truth_mcse', 'truth_n')]
  saveRDS(truth, scenario_file)
}

done <- sort(list.files(CACHE, '^scenario-[0-9]+[.]rds$', full.names = TRUE))
if (length(done) < nrow(scenarios)) {
  message(sprintf('%d of %d scenario truths cached; rerun another slice',
                  length(done), nrow(scenarios)))
  quit(save = 'no', status = 0)
}
truth <- do.call(rbind, lapply(done, readRDS))
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth, file.path(OUT, 'truth.csv'), row.names = FALSE)

calibration_file <- file.path(OUT, 'mi-calibration.rds')
if (!file.exists(calibration_file)) {
  calibration <- calibrate_mi(scenarios)
  saveRDS(calibration, calibration_file)
  if (!isTRUE(calibration$passed))
    stop('MI calibration gate failed: ', calibration$failure)
  utils::write.csv(calibration$summary,
                   file.path(OUT, 'mi-calibration.csv'), row.names = FALSE)
  message('selected M = ', calibration$selected_M,
          if (isTRUE(calibration$used_fallback)) ' using fallback' else '')
}
message(sprintf('truth written for %d scenarios and %d contrasts',
                nrow(scenarios), length(CONTRASTS)))
