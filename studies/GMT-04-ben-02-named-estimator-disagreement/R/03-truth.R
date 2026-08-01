## GMT-04 benchmark: exact truth manifest and independent simulation check.
##
## Rscript R/03-truth.R
## Rscript R/03-truth.R 1:8

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
VALIDATION_CACHE <- file.path(OUT, 'truth-validation-cache')
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(VALIDATION_CACHE, recursive = TRUE, showWarnings = FALSE)

immutable_rds <- function(object, path, tolerance = 1e-14) {
  if (file.exists(path)) {
    old <- readRDS(path)
    equal <- isTRUE(all.equal(old, object, tolerance = tolerance,
                              check.attributes = TRUE))
    if (!equal) stop('immutable truth artifact differs: ', path)
    return(invisible(FALSE))
  }
  saveRDS(object, path)
  invisible(TRUE)
}

keys <- c('deltaQ0', 'deltaQ1', 'C0', 'C1')
exact <- do.call(rbind, lapply(keys, truth_for_key))
rownames(exact) <- NULL

validation <- vector('list', length(keys))
for (i in seq_along(keys)) {
  key <- keys[i]
  path <- file.path(VALIDATION_CACHE, paste0(key, '.rds'))
  if (file.exists(path)) {
    validation[[i]] <- readRDS(path)
    message(key, ': independent validation cached')
    next
  }
  set.seed(TRUTH_VALIDATION_SEED + i)
  z <- simulate_intervention_pair(key)
  saveRDS(z, path)
  validation[[i]] <- z
  message(key, ': independent intervention simulation complete')
}
validation <- do.call(rbind, validation)
manifest <- merge(exact, validation, by = 'truth_key', sort = FALSE)
manifest$distance_risk0 <- abs(manifest$sim_risk0 - manifest$risk0)
manifest$distance_risk1 <- abs(manifest$sim_risk1 - manifest$risk1)
manifest$distance_rd <- abs(manifest$sim_rd - manifest$rd)
manifest$pass_risk0 <- manifest$distance_risk0 <=
  TRUTH_MCSE_MULTIPLIER * manifest$sim_mcse_risk0
manifest$pass_risk1 <- manifest$distance_risk1 <=
  TRUTH_MCSE_MULTIPLIER * manifest$sim_mcse_risk1
manifest$pass_rd <- manifest$distance_rd <=
  TRUTH_MCSE_MULTIPLIER * manifest$sim_mcse_rd + .Machine$double.eps
manifest$verified <- manifest$pass_risk0 & manifest$pass_risk1 & manifest$pass_rd
if (!all(manifest$verified)) {
  utils::write.csv(manifest, file.path(OUT, 'truth-validation-failed.csv'),
                   row.names = FALSE)
  stop('independent truth validation exceeded three simulation MCSEs')
}

## Critique fix: exact numerical truths are frozen before any estimator run.
manifest_path <- file.path(OUT, 'truth-manifest.rds')
immutable_rds(manifest, manifest_path)
utils::write.csv(manifest, file.path(OUT, 'truth-manifest.csv'), row.names = FALSE)

amendment <- data.frame(
  amendment_date = as.character(Sys.Date()),
  truth_key = manifest$truth_key,
  risk0 = manifest$risk0,
  risk1 = manifest$risk1,
  rd = manifest$rd,
  distance_from_zero = abs(manifest$rd),
  independently_verified = manifest$verified,
  stringsAsFactors = FALSE
)
amendment_path <- file.path(
  OUT, paste0('truth-amendment-', as.character(Sys.Date()), '.csv')
)
if (!file.exists(amendment_path))
  utils::write.csv(amendment, amendment_path, row.names = FALSE)

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
selected <- seq_len(nrow(scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1])) {
  bounds <- as.integer(strsplit(args[1], ':', fixed = TRUE)[[1]])
  selected <- intersect(seq(bounds[1], bounds[2]), selected)
}

for (i in selected) {
  path <- file.path(CACHE, sprintf('scenario-%03d.rds', i))
  if (file.exists(path)) {
    message(sprintf('scenario %d/%d: cached', i, nrow(scenarios)))
    next
  }
  scenario <- scenarios[i, , drop = FALSE]
  truth <- manifest[manifest$truth_key == scenario$truth_key, ]
  row <- cbind(
    scenario,
    truth[, c('risk0', 'risk1', 'rd', 'verified', 'validation_n',
              'sim_risk0', 'sim_risk1', 'sim_rd', 'sim_mcse_risk0',
              'sim_mcse_risk1', 'sim_mcse_rd')]
  )
  rownames(row) <- NULL
  saveRDS(row, path)
  message(sprintf('scenario %d/%d: RD %.8f', i, nrow(scenarios), row$rd))
}

files <- file.path(CACHE, sprintf('scenario-%03d.rds', seq_len(nrow(scenarios))))
if (!all(file.exists(files))) {
  message(sprintf('%d of %d scenario truths cached; rerun to continue',
                  sum(file.exists(files)), length(files)))
  quit(save = 'no', status = 0)
}
truth <- do.call(rbind, lapply(files, readRDS))
rownames(truth) <- NULL
immutable_rds(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth, file.path(OUT, 'truth.csv'), row.names = FALSE)
message('verified immutable truth written for 26 analysis scenarios')
