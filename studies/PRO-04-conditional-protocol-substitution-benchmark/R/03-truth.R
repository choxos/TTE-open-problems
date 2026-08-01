## Study PRO-04: enumerate mechanism-specific truth and cache by scenario.
##
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:4

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
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()

parse_slice <- function(arg, n) {
  if (!length(arg)) return(seq_len(n))
  parts <- strsplit(arg[1], ':', fixed = TRUE)[[1]]
  if (length(parts) != 2L) return(seq_len(n))
  values <- suppressWarnings(as.integer(parts))
  if (anyNA(values)) return(seq_len(n))
  intersect(seq(values[1], values[2]), seq_len(n))
}
sel <- parse_slice(commandArgs(TRUE)[1], nrow(scenarios))

## The power calculation is deterministic and is frozen before any mechanism or
## dataset replicate is drawn.
POWER_FILE <- file.path(OUT, 'sample-size.rds')
if (file.exists(POWER_FILE)) {
  power <- readRDS(POWER_FILE)
  if (!identical(power$rule_version, POWER_RULE_VERSION) ||
      !identical(power$config_signature, CONFIG_SIGNATURE)) {
    stop('Existing sample-size cache was created under a different configuration')
  }
} else {
  message('Selecting N by deterministic worst-case variance search')
  power <- select_sample_size(scenarios)
  saveRDS(power, POWER_FILE)
}
utils::write.csv(power$search, file.path(OUT, 'power-search.csv'), row.names = FALSE)
utils::write.csv(power$criteria, file.path(OUT, 'sample-size.csv'), row.names = FALSE)
message(sprintf('Power-selected N = %d', power$n))

for (i in sel) {
  file <- file.path(CACHE, sprintf('scenario-%03d.rds', i))
  if (file.exists(file)) {
    cached <- readRDS(file)
    valid_cache <- nrow(cached) == N_REP &&
      all(cached$config_signature == CONFIG_SIGNATURE)
    if (!valid_cache) stop('Stale truth cache for scenario ', i)
    message(sprintf('scenario %d/%d: cached', i, nrow(scenarios)))
    next
  }
  set.seed(MASTER_SEED + 100000L * i)
  s <- scenarios[i, , drop = FALSE]
  rows <- vector('list', N_REP)
  t0 <- proc.time()[['elapsed']]
  for (r in seq_len(N_REP)) {
    h <- draw_mechanism(s)
    truth <- truth_for_mechanism(h)
    rows[[r]] <- cbind(
      data.frame(scenario = i, mechanism_id = r,
                 config_signature = CONFIG_SIGNATURE,
                 stringsAsFactors = FALSE),
      as.data.frame(h, stringsAsFactors = FALSE), truth
    )
    if (r %% 100L == 0L) message(sprintf('scenario %d: truth %d/%d', i, r, N_REP))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  saveRDS(out, file)
  message(sprintf('scenario %d/%d: %.1f seconds, material %.3f, preserving %.3f',
                  i, nrow(scenarios), proc.time()[['elapsed']] - t0,
                  mean(abs(out$delta) >= MATERIAL_MARGIN),
                  mean(abs(out$delta) <= PRESERVATION_MARGIN)))
}

files <- list.files(CACHE, full.names = TRUE)
done <- sort(files[startsWith(basename(files), 'scenario-') & endsWith(files, '.rds')])
if (length(done) < nrow(scenarios)) {
  message(sprintf('%d of %d scenarios enumerated; rerun or use another slice to continue',
                  length(done), nrow(scenarios)))
  quit(save = 'no', status = 0)
}
truth <- do.call(rbind, lapply(done, readRDS))
if (nrow(truth) != nrow(scenarios) * N_REP) stop('Truth cache is incomplete')
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth, file.path(OUT, 'truth.csv'), row.names = FALSE)
message(sprintf('truth written for %d mechanisms across %d strata',
                nrow(truth), nrow(scenarios)))
