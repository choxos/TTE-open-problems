## Study LRN-05: precision pilot, final run, benchmark, and bootstrap gate.
##
## Main usage:
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:4
##
## Optional execution modes:
##   LRN05_MODE=benchmark Rscript R/04-run.R
##   LRN05_MODE=bootstrap Rscript R/04-run.R

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))
source(here('..', '_shared', 'R', 'harness.R'))

OUT <- here('results')
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUT, 'truth.rds')))
TRUTH <- readRDS(file.path(OUT, 'truth.rds'))
scenarios <- build_scenarios()

args <- commandArgs(TRUE)
selected <- seq_len(nrow(scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1L])) {
  p <- as.integer(strsplit(args[1L], ':', fixed = TRUE)[[1L]])
  selected <- intersect(seq(p[1L], p[2L]), selected)
}

blank_all <- function(reason, rep_id) {
  out <- do.call(rbind, lapply(METHODS, blank_method, reason = reason))
  out$rep_id <- rep_id
  out
}

one_rep <- function(scen, rep_id) {
  dat <- tryCatch(gen_replicate(scen, N_PER_REP), error = function(e) NULL)
  if (is.null(dat)) return(blank_all('dgm-failed', rep_id))
  cuts <- TRUTH$cuts[TRUTH$cuts$scenario == scen$scenario,
                     c('strategy', 'score', 'cut', 'value'), drop = FALSE]
  out <- tryCatch(estimate_all(dat, scen, cuts),
                  error = function(e) blank_all('analysis-failed', rep_id))
  out$rep_id <- rep_id
  out
}

key_columns <- c('strategy', 'score', 'metric', 'bin_key')
with_bin_key <- function(x) {
  x$bin_key <- ifelse(is.na(x$bin), 0L, as.integer(x$bin))
  x
}

precision_plan <- function(pilot, scenario_id) {
  pilot <- with_bin_key(pilot)
  a <- pilot[pilot$method == 'full_history',
             c('rep_id', key_columns, 'est')]
  b <- pilot[pilot$method == 'exact_complete',
             c('rep_id', key_columns, 'est')]
  names(a)[names(a) == 'est'] <- 'full'
  names(b)[names(b) == 'est'] <- 'complete'
  paired <- merge(a, b, by = c('rep_id', key_columns), all = TRUE)
  paired$difference <- paired$complete - paired$full
  paired$family <- vapply(paired$metric, metric_family, character(1))
  paired <- paired[paired$family %in% c('cal_intercept',
                                        'calibration_curve', 'brier', 'auc') &
                     paired$strategy %in% STRATEGIES, , drop = FALSE]
  groups <- split(paired, interaction(paired$strategy, paired$score,
                                      paired$metric, paired$bin_key, drop = TRUE))
  details <- do.call(rbind, lapply(groups, function(d) {
    target <- precision_target(d$metric[1L])
    z <- d$difference[is.finite(d$difference)]
    s <- if (length(z) > 1L) stats::sd(z) else Inf
    raw <- if (is.finite(s)) ceiling((target['z'] * s / target['h'])^2) else Inf
    required <- if (is.finite(raw))
      max(N_REP_MIN, ceiling(raw / 1000) * 1000) else Inf
    data.frame(
      scenario = scenario_id, strategy = d$strategy[1L], score = d$score[1L],
      metric = d$metric[1L], bin_key = d$bin_key[1L], pilot_n = length(z),
      pilot_sd = s, required_uncapped = required,
      protocol_cap_exceeded = !is.finite(required) || required > N_REP_PROTOCOL_CAP,
      stringsAsFactors = FALSE
    )
  }))
  maximum <- suppressWarnings(max(details$required_uncapped, na.rm = TRUE))
  protocol_n <- if (!is.finite(maximum) || maximum > N_REP_PROTOCOL_CAP)
    N_REP_PROTOCOL_CAP else maximum
  protocol_n <- max(N_REP_MIN, protocol_n)
  run_n <- min(protocol_n, N_REP_BUDGET_CAP)
  summary <- data.frame(
    scenario = scenario_id, required_uncapped = maximum,
    protocol_n = protocol_n, run_n = run_n,
    budget_precision_shortfall = !is.finite(maximum) || run_n < protocol_n,
    stringsAsFactors = FALSE
  )
  list(summary = summary, details = details)
}

run_benchmark <- function() {
  anchors <- anchor_scenarios(scenarios)
  set.seed(MASTER_SEED + 600000L)
  elapsed <- numeric()
  for (i in anchors) for (r in seq_len(50L)) {
    started <- proc.time()[['elapsed']]
    invisible(one_rep(scenarios[i, , drop = FALSE], r))
    elapsed <- c(elapsed, proc.time()[['elapsed']] - started)
  }
  serial_total <- sum(elapsed)

  parallel_out <- file.path(tempdir(), paste0('lrn05-benchmark-', Sys.getpid()))
  started <- proc.time()[['elapsed']]
  invisible(run_design(one_rep, scenarios, n_rep = 50L,
                       master_seed = MASTER_SEED + 610000L,
                       outdir = parallel_out, workers = WORKERS,
                       resume = TRUE, only = anchors))
  parallel_elapsed <- proc.time()[['elapsed']] - started
  efficiency <- min(1, serial_total / (WORKERS * parallel_elapsed))

  s <- scenarios[anchors[1L], , drop = FALSE]
  cuts <- TRUTH$cuts[TRUTH$cuts$scenario == s$scenario,
                     c('strategy', 'score', 'cut', 'value'), drop = FALSE]
  dat <- gen_replicate(s, N_PER_REP)
  boot_time <- numeric(200L)
  for (b in seq_len(200L)) {
    idx <- sample.int(N_PER_REP, N_PER_REP, replace = TRUE)
    started <- proc.time()[['elapsed']]
    invisible(point_estimates_all(subset_replicate(dat, idx), s, cuts))
    boot_time[b] <- proc.time()[['elapsed']] - started
  }

  main_reps <- nrow(scenarios) * N_REP_BUDGET_CAP
  projected_main <- stats::quantile(elapsed, 0.90, names = FALSE) *
    main_reps / (WORKERS * efficiency) * 1.20
  projected_bootstrap <- stats::quantile(boot_time, 0.90, names = FALSE) *
    (4 * 25 * 199) / (WORKERS * efficiency) * 1.20
  report <- data.frame(
    replicate_median_seconds = stats::median(elapsed),
    replicate_p90_seconds = stats::quantile(elapsed, 0.90, names = FALSE),
    parallel_200_seconds = parallel_elapsed,
    parallel_efficiency = efficiency,
    bootstrap_median_seconds = stats::median(boot_time),
    bootstrap_p90_seconds = stats::quantile(boot_time, 0.90, names = FALSE),
    projected_main_hours_with_margin = projected_main / 3600,
    projected_bootstrap_hours_with_margin = projected_bootstrap / 3600
  )
  utils::write.csv(report, file.path(OUT, 'runtime-benchmark.csv'), row.names = FALSE)
  print(report)
}

run_bootstrap_gate <- function() {
  anchors <- anchor_scenarios(scenarios)
  cache <- file.path(OUT, 'bootstrap-cache')
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  set.seed(MASTER_SEED + 700000L)
  for (i in anchors) for (d in seq_len(25L)) {
    path <- file.path(cache, sprintf('scenario-%03d-dataset-%02d.rds', i, d))
    ## Same two-level cache as the replication plan, and the same hazard: these
    ## datasets are estimated against TRUTH$cuts, so replacing truth strands
    ## them without changing anything an existence check can see.
    if (file.exists(path) &&
        file.mtime(path) > file.mtime(file.path(OUT, 'truth.rds'))) next
    s <- scenarios[i, , drop = FALSE]
    cuts <- TRUTH$cuts[TRUTH$cuts$scenario == i,
                       c('strategy', 'score', 'cut', 'value'), drop = FALSE]
    dat <- gen_replicate(s, N_PER_REP)
    original <- estimate_all(dat, s, cuts)
    boot <- vector('list', 199L)
    for (b in seq_len(199L)) {
      idx <- sample.int(N_PER_REP, N_PER_REP, replace = TRUE)
      z <- point_estimates_all(subset_replicate(dat, idx), s, cuts)
      z$bootstrap <- b
      boot[[b]] <- z
    }
    boot <- do.call(rbind, boot)
    boot <- with_bin_key(boot)
    original <- with_bin_key(original)
    split_boot <- split(boot, interaction(boot$method, boot$strategy, boot$score,
                                          boot$metric, boot$bin_key, drop = TRUE))
    summary <- do.call(rbind, lapply(split_boot, function(z) data.frame(
      method = z$method[1L], strategy = z$strategy[1L], score = z$score[1L],
      metric = z$metric[1L], bin_key = z$bin_key[1L],
      bootstrap_se = stats::sd(z$est, na.rm = TRUE),
      bootstrap_n = sum(is.finite(z$est)), stringsAsFactors = FALSE)))
    summary <- merge(summary,
                     original[, c('method', 'strategy', 'score', 'metric',
                                  'bin_key', 'se')],
                     by = c('method', 'strategy', 'score', 'metric', 'bin_key'),
                     all.x = TRUE)
    summary$scenario <- i
    summary$dataset <- d
    summary$relative_difference <- abs(summary$se - summary$bootstrap_se) /
      summary$bootstrap_se
    saveRDS(summary, path)
  }
  files <- list.files(cache, '^scenario-.*[.]rds$', full.names = TRUE)
  result <- do.call(rbind, lapply(files, readRDS))
  utils::write.csv(result, file.path(OUT, 'bootstrap-se-check.csv'), row.names = FALSE)
  bad <- is.finite(result$relative_difference) & result$bootstrap_n >= 190L &
    result$relative_difference > 0.10
  if (any(bad)) stop('bootstrap SE gate failed; correct the sandwich and rerun')
  message('bootstrap SE gate passed')
}

mode <- Sys.getenv('LRN05_MODE', 'main')
if (mode == 'benchmark') {
  run_benchmark()
  quit(save = 'no', status = 0)
}
if (mode == 'bootstrap') {
  run_bootstrap_gate()
  quit(save = 'no', status = 0)
}

## The excluded precision pilot has its own cache. The final cache never contains
## pilot rows, and both phases retain the harness's scenario-indexed RNG streams.
PILOT_OUT <- file.path(OUT, 'pilot')
invisible(run_design(one_rep, scenarios, n_rep = N_PILOT,
                     master_seed = MASTER_SEED + 200000L,
                     outdir = PILOT_OUT, workers = WORKERS,
                     resume = TRUE, only = selected))

PLAN_CACHE <- file.path(OUT, 'replication-plan-cache')
dir.create(PLAN_CACHE, recursive = TRUE, showWarnings = FALSE)
for (i in selected) {
  path <- file.path(PLAN_CACHE, sprintf('scenario-%03d.rds', i))
  raw <- file.path(PILOT_OUT, 'raw', sprintf('scenario-%03d.rds', i))
  stopifnot(file.exists(raw))
  ## A cache keyed only on the scenario number outlives the pilot it summarizes.
  ## Deleting the pilot and every result to rerun a corrected study left this
  ## directory untouched, so the replication requirements were still those of a
  ## run in which nothing had estimated: the paired pilot standard deviation was
  ## Inf on all 1248 rows, every requirement was Inf, and 56 decisions were
  ## published as protocol-cap-exceeded. Regenerating is seconds of work, so
  ## tie it to the pilot rather than to the file merely existing.
  if (file.exists(path) &&
      file.mtime(path) > file.mtime(raw)) next
  saveRDS(precision_plan(readRDS(raw), i), path)
}

plan_files <- list.files(PLAN_CACHE, '^scenario-.*[.]rds$', full.names = TRUE)
plans <- lapply(plan_files, readRDS)
if (length(plans)) {
  utils::write.csv(do.call(rbind, lapply(plans, `[[`, 'summary')),
                   file.path(OUT, 'replication-plan.csv'), row.names = FALSE)
  utils::write.csv(do.call(rbind, lapply(plans, `[[`, 'details')),
                   file.path(OUT, 'replication-requirements.csv'), row.names = FALSE)
}

res <- run_design(one_rep, scenarios, n_rep = N_REP_BUDGET_CAP,
                  master_seed = MASTER_SEED, outdir = OUT,
                  workers = WORKERS, resume = TRUE, only = selected)

write_provenance(
  OUT,
  packages = c('stats', 'splines', 'future', 'furrr'),
  extra = list(
    study = 'LRN-05 counterfactual validation under omitted binary confounding',
    scenarios = nrow(scenarios), pilot_replicates = N_PILOT,
    final_replicates = N_REP_BUDGET_CAP,
    individuals_per_replicate = N_PER_REP, months = N_MONTHS,
    master_seed = MASTER_SEED,
    scaling = '4000 to 1000 individuals; final replication cap 10000 to 2000'
  )
)
message(sprintf('done: %d returned rows', nrow(res)))
