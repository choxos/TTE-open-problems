## DTA-02: benchmark and run the resumable design.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:1
##   TTE_BATCH_ID=2 Rscript R/04-run.R
##
## The optional slice addresses the six common-random-number blocks. Batch one
## is the prespecified initial 5000 replicates. Later batch identifiers add
## independent streams of 5000 replicates without replacing completed work.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))

OUT <- here('results')
CAL <- file.path(OUT, 'calibration')
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUT, 'truth.rds')))
TRUTH <- readRDS(file.path(OUT, 'truth.rds'))
stopifnot(isTRUE(TRUTH$complete), isTRUE(TRUTH$verification$pass))
Q_TARGET <- TRUTH$q

blocks <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(blocks))
if (length(args) && grepl('^\\d+:\\d+$', args[1])) {
  p <- as.integer(strsplit(args[1], ':')[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

blank_formal <- function(s, rep_id, pair_id, why) {
  out <- do.call(rbind, lapply(METHODS, function(m) method_row(m, fail = why)))
  out$formal_scenario <- s$formal_scenario
  out$mapping <- s$mapping
  out$reference <- s$reference
  out$kappa <- s$kappa
  out$gamma <- s$gamma
  out$rep_id <- rep_id
  out$pair_id <- pair_id
  out$batch_id <- BATCH_ID
  out
}

decorate <- function(rows, s, rep_id, pair_id) {
  rows$formal_scenario <- s$formal_scenario
  rows$mapping <- s$mapping
  rows$reference <- s$reference
  rows$kappa <- s$kappa
  rows$gamma <- s$gamma
  rows$rep_id <- rep_id
  rows$pair_id <- pair_id
  rows$batch_id <- BATCH_ID
  rows
}

one_rep <- function(scen, rep_id) {
  pair_id <- pair_for_replicate(rep_id)
  fs <- formal_scenarios_for(scen$kappa, scen$gamma)
  counts <- tryCatch(gen_base_counts(scen), error = function(e) NULL)
  if (is.null(counts)) {
    return(do.call(rbind, lapply(seq_len(nrow(fs)), function(i)
      blank_formal(fs[i, ], rep_id, pair_id, 'dgm-failed'))))
  }

  all_rows <- list()
  for (mapping in MAPPING_LEVELS) {
    current <- fs[fs$mapping == mapping, , drop = FALSE]
    mapped <- tryCatch(apply_mapping_counts(counts, mapping, pair_id),
                       error = function(e) NULL)
    if (is.null(mapped)) {
      for (i in seq_len(nrow(current))) {
        all_rows[[length(all_rows) + 1L]] <-
          blank_formal(current[i, ], rep_id, pair_id, 'mapping-failed')
      }
      next
    }

    affected <- affected_sites(mapping, pair_id)
    base <- tryCatch(network_base(mapped, Q_TARGET, scen$kappa, scen$gamma,
                                  CAL, affected), error = function(e) NULL)
    if (is.null(base)) {
      for (i in seq_len(nrow(current))) {
        all_rows[[length(all_rows) + 1L]] <-
          blank_formal(current[i, ], rep_id, pair_id, 'estimation-failed')
      }
      next
    }

    for (i in seq_len(nrow(current))) {
      s <- current[i, ]
      validation <- tryCatch(run_validation(mapped, mapping, pair_id, s$reference),
                             error = function(e) NULL)
      if (is.null(validation)) {
        all_rows[[length(all_rows) + 1L]] <-
          blank_formal(s, rep_id, pair_id, 'validation-failed')
        next
      }
      rows <- c(base$rows, validation_rows(base, validation, affected))
      rows <- do.call(rbind, rows[METHODS])
      all_rows[[length(all_rows) + 1L]] <- decorate(rows, s, rep_id, pair_id)
    }
  }
  out <- do.call(rbind, all_rows)
  stopifnot(nrow(out) == nrow(fs) * length(METHODS))
  rownames(out) <- NULL
  out
}

## Critique fix: the unsupported runtime assertion is replaced by a complete
## benchmark containing generation, every mapping, validation, all estimators,
## serialization, checkpointing, and a cached restart.
benchmark_file <- file.path(OUT, 'benchmark.rds')
if (!file.exists(benchmark_file)) {
  bench_dir <- file.path(OUT, 'benchmark')
  t0 <- proc.time()[['elapsed']]
  invisible(run_design(
    one_rep, blocks, n_rep = BENCHMARK_REP,
    master_seed = MASTER_SEED - 10000L, outdir = bench_dir,
    workers = N_WORKERS, resume = TRUE, only = seq_len(nrow(blocks))))
  elapsed <- proc.time()[['elapsed']] - t0
  raw_bench <- list.files(file.path(bench_dir, 'raw'), full.names = TRUE)
  checkpoint_bytes <- sum(file.info(raw_bench)$size, na.rm = TRUE)
  t1 <- proc.time()[['elapsed']]
  invisible(run_design(
    one_rep, blocks, n_rep = BENCHMARK_REP,
    master_seed = MASTER_SEED - 10000L, outdir = bench_dir,
    workers = N_WORKERS, resume = TRUE, only = seq_len(nrow(blocks))))
  restart_seconds <- proc.time()[['elapsed']] - t1
  benchmark <- list(
    elapsed_seconds = elapsed,
    restart_seconds = restart_seconds,
    checkpoint_bytes = checkpoint_bytes,
    base_seconds = elapsed * N_REP / BENCHMARK_REP * RESTART_ALLOWANCE,
    maximum_seconds = elapsed * MAX_REP / BENCHMARK_REP * RESTART_ALLOWANCE,
    base_checkpoint_bytes = checkpoint_bytes * N_REP / BENCHMARK_REP,
    maximum_checkpoint_bytes = checkpoint_bytes * MAX_REP / BENCHMARK_REP,
    benchmark_replicates_per_formal_scenario = BENCHMARK_REP
  )
  saveRDS(benchmark, benchmark_file)
} else {
  benchmark <- readRDS(benchmark_file)
}

if (benchmark$base_seconds > OVERNIGHT_SECONDS) {
  stop(sprintf('base forecast %.2f hours exceeds the 12-hour ceiling; main run not started',
               benchmark$base_seconds / 3600))
}

RUN_OUT <- if (BATCH_ID == 1L) OUT else
  file.path(OUT, 'adaptive', sprintf('batch-%03d', BATCH_ID))
dir.create(RUN_OUT, recursive = TRUE, showWarnings = FALSE)

batch_seed <- MASTER_SEED + (BATCH_ID - 1L) * 1000000L
res <- run_design(
  one_rep, blocks, n_rep = BATCH_SIZE, master_seed = batch_seed,
  outdir = RUN_OUT, workers = N_WORKERS, resume = TRUE, only = sel)

write_provenance(
  RUN_OUT,
  packages = c('stats', 'future', 'furrr'),
  extra = list(
    study = 'DTA-02 federated semantic drift', formal_scenarios = 72L,
    common_random_number_blocks = nrow(blocks), batch_id = BATCH_ID,
    replicates_per_batch = BATCH_SIZE, maximum_replicates = MAX_REP,
    records_represented_per_replicate = N_SITES * N_PER_SITE,
    aggregate_calibration_draws = N_CALIBRATION,
    benchmark_base_hours = benchmark$base_seconds / 3600,
    benchmark_maximum_hours = benchmark$maximum_seconds / 3600,
    master_seed = batch_seed
  )
)
message(sprintf('batch %d done: %d rows; base forecast %.2f hours',
                BATCH_ID, nrow(res), benchmark$base_seconds / 3600))
