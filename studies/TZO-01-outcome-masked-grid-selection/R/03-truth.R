## Study TZO-01: enumerate and cache truth.
##
## Usage: Rscript R/03-truth.R
##        Rscript R/03-truth.R 1:12
##
## The optional slice addresses the 48 published cells. Coupled cells sharing a
## process mechanism are computed together, then cached separately.

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

cells <- build_cells()
process <- build_process_scenarios()
args <- commandArgs(TRUE)
selected_cells <- seq_len(nrow(cells))
if (length(args) && grepl('^\\d+:\\d+$', args[1L])) {
  ends <- as.integer(strsplit(args[1L], ':', fixed = TRUE)[[1L]])
  selected_cells <- intersect(seq.int(ends[1L], ends[2L]), selected_cells)
}
selected_process <- unique(cells$process_scenario[selected_cells])

for (i in selected_process) {
  group_file <- file.path(CACHE, sprintf('process-%02d.rds', i))
  if (file.exists(group_file)) {
    truth_group <- readRDS(group_file)
    message(sprintf('process %d/%d: cached', i, nrow(process)))
  } else {
    started <- proc.time()[['elapsed']]
    truth_group <- truth_for_process(
      process[i, , drop = FALSE],
      batch_cache = file.path(CACHE, sprintf('batches-%03d', i)))
    saveRDS(truth_group, group_file)
    message(sprintf(
      'process %d/%d: %.1f minutes, %d truth batches, precision %s',
      i, nrow(process), (proc.time()[['elapsed']] - started) / 60,
      max(truth_group$truth_batches),
      ifelse(all(truth_group$precision_met), 'met', 'not met')
    ))
  }
  for (cell in unique(truth_group$cell)) {
    cell_file <- file.path(CACHE, sprintf('scenario-%03d.rds', cell))
    if (!file.exists(cell_file)) {
      saveRDS(truth_group[truth_group$cell == cell, , drop = FALSE], cell_file)
    }
  }
}

cell_files <- file.path(CACHE, sprintf('scenario-%03d.rds', cells$cell))
if (!all(file.exists(cell_files))) {
  message(sprintf('%d of %d scenario truths cached; rerun or use another slice',
                  sum(file.exists(cell_files)), length(cell_files)))
  quit(save = 'no', status = 0)
}
truth <- do.call(rbind, lapply(cell_files, readRDS))
rownames(truth) <- NULL
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth, file.path(OUT, 'truth.csv'), row.names = FALSE)
message(sprintf('truth written for %d cells and %d grids', nrow(cells), length(GRIDS)))
