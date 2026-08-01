## Study LRN-05: enumerate and verify truth once per scenario.
##
## Usage:
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:4

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

OUT <- here('results')
CACHE <- file.path(OUT, 'truth-cache')
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

save_atomic <- function(object, path) {
  tmp <- tempfile(pattern = 'truth-', tmpdir = dirname(path), fileext = '.rds')
  saveRDS(object, tmp)
  if (!file.rename(tmp, path)) stop('could not install truth cache: ', path)
}

decorate <- function(x, scen) {
  cbind(scen[rep(1L, nrow(x)), , drop = FALSE], x, row.names = NULL)
}

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
selected <- seq_len(nrow(scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1L])) {
  p <- as.integer(strsplit(args[1L], ':', fixed = TRUE)[[1L]])
  selected <- intersect(seq(p[1L], p[2L]), selected)
}

for (i in selected) {
  scenario_file <- file.path(CACHE, sprintf('scenario-%03d.rds', i))
  if (file.exists(scenario_file)) {
    message(sprintf('scenario %d/%d: cached', i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  group_file <- file.path(CACHE, sprintf('truth-group-%02d.rds', s$truth_group))
  if (file.exists(group_file)) {
    base <- readRDS(group_file)
  } else {
    set.seed(MASTER_SEED + 100000L + s$truth_group)
    started <- proc.time()[['elapsed']]
    base <- truth_for_delta(s$delta)
    save_atomic(base, group_file)
    message(sprintf('truth group %d: %.1f seconds, order %d, verified %s',
                    s$truth_group, proc.time()[['elapsed']] - started,
                    base$checks$quadrature_order, base$checks$verification_ok))
  }
  item <- list(rows = decorate(base$rows, s),
               cuts = decorate(base$cuts, s),
               checks = decorate(base$checks, s),
               verification = decorate(base$verification, s))
  save_atomic(item, scenario_file)
}

files <- file.path(CACHE, sprintf('scenario-%03d.rds', seq_len(nrow(scenarios))))
if (!all(file.exists(files))) {
  message(sprintf('%d of %d scenario caches complete; rerun or use another slice',
                  sum(file.exists(files)), length(files)))
  quit(save = 'no', status = 0)
}

items <- lapply(files, readRDS)
truth <- list(
  rows = do.call(rbind, lapply(items, `[[`, 'rows')),
  cuts = do.call(rbind, lapply(items, `[[`, 'cuts')),
  checks = do.call(rbind, lapply(items, `[[`, 'checks')),
  verification = do.call(rbind, lapply(items, `[[`, 'verification'))
)
rownames(truth$rows) <- rownames(truth$cuts) <- NULL
rownames(truth$checks) <- rownames(truth$verification) <- NULL
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth$rows, file.path(OUT, 'truth.csv'), row.names = FALSE)
utils::write.csv(truth$cuts, file.path(OUT, 'truth-cutpoints.csv'), row.names = FALSE)
utils::write.csv(truth$checks, file.path(OUT, 'truth-checks.csv'), row.names = FALSE)
utils::write.csv(truth$verification, file.path(OUT, 'truth-verification.csv'),
                 row.names = FALSE)
message(sprintf('truth written for %d scenarios', nrow(scenarios)))
