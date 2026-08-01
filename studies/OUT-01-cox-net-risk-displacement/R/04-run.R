## OUT-01 mechanism study: validation, benchmark, and production run.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:6

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUTDIR <- here("results")
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
IIDDIR <- file.path(OUTDIR, "iid-audit")
dir.create(IIDDIR, recursive = TRUE, showWarnings = FALSE)

truth_path <- file.path(OUTDIR, "truth.rds")
lock_path <- file.path(OUTDIR, "truth.lock.rds")
if (!file.exists(truth_path) || !file.exists(lock_path))
  stop("run 03-truth.R to completion before estimator replication")
TRUTH <- readRDS(truth_path)
LOCK <- readRDS(lock_path)
if (!identical(LOCK$spec, truth_lock_spec()) ||
    length(unique(TRUTH$scenario)) != nrow(build_scenarios()))
  stop("the truth lock does not match the current mechanism")

atomic_save_rds <- function(object, path) {
  temporary <- paste0(path, ".tmp-", Sys.getpid())
  saveRDS(object, temporary)
  if (!file.rename(temporary, path)) stop("could not atomically write ", path)
  invisible(path)
}

append_replicate_diagnostics <- function(out, dat, rep_id) {
  out$rep_id <- rep_id
  out$treatment_prevalence <- mean(dat$A)
  out$n_treated <- sum(dat$A == 1L)
  out$n_untreated <- sum(dat$A == 0L)
  out$prop_extreme_true_ps <- mean(dat$pA < 0.05 | dat$pA > 0.95)
  out$overlap_flag <- out$n_treated < 500L | out$n_untreated < 500L |
    out$prop_extreme_true_ps > 0.01
  out$n_primary_events <- sum(dat$status == 1L)
  out$n_deaths <- sum(dat$status == 2L)
  out
}

one_rep <- function(scen, rep_id) {
  generated <- capture_conditions(gen_replicate(scen, N_PER_REPLICATE))
  if (!is.null(generated$error)) {
    out <- blank_estimates(paste0("DGM error: ", generated$error))
    out$rep_id <- rep_id
    out$treatment_prevalence <- NA_real_
    out$n_treated <- NA_integer_
    out$n_untreated <- NA_integer_
    out$prop_extreme_true_ps <- NA_real_
    out$overlap_flag <- NA
    out$n_primary_events <- NA_integer_
    out$n_deaths <- NA_integer_
    out$warning <- collapse_reasons(generated$warnings)
    return(out)
  }

  dat <- generated$value
  ## Retain complete subject-level iid contributions for the first production
  ## replicate in every scenario. The three fixed validation datasets are also
  ## retained below, providing independent checks without multi-gigabyte raw
  ## duplication across all production replicates.
  keep_iid <- rep_id == 1L
  out <- estimate_both(dat, need_se = TRUE, keep_iid = keep_iid)
  iid <- attr(out, "iid")
  attr(out, "iid") <- NULL
  if (keep_iid && length(iid)) {
    path <- file.path(IIDDIR, sprintf("scenario-%03d-rep-%04d.rds",
                                     scen$scenario[[1]], rep_id))
    atomic_save_rds(list(scenario = scen$scenario[[1]], rep_id = rep_id,
                         iid = iid), path)
  }
  if (length(generated$warnings)) {
    out$warning <- collapse_reasons(c(out$warning, generated$warnings))
  }
  append_replicate_diagnostics(out, dat, rep_id)
}

estimate_vector <- function(fit, keys) {
  value <- rep(NA_real_, length(keys))
  names(value) <- keys
  k <- paste(fit$method, fit$horizon, sep = "@")
  value[k] <- fit$est
  value
}

validation_spec <- function() {
  list(truth = truth_lock_spec(), bootstrap_b = BOOTSTRAP_B,
       n = N_PER_REPLICATE, tolerance = IF_BOOTSTRAP_TOLERANCE)
}

assert_validation <- function(object) {
  s <- object$summary
  if (any(!is.finite(s$relative_disagreement)) ||
      any(s$relative_disagreement > IF_BOOTSTRAP_TOLERANCE))
    stop("unresolved influence-function and bootstrap SE disagreement exceeds 5%")
  if (any(s$bootstrap_convergence < 0.98))
    stop("bootstrap validation convergence is below 0.98")
  invisible(object)
}

run_variance_validation <- function() {
  final_path <- file.path(OUTDIR, "variance-validation.rds")
  if (file.exists(final_path)) {
    object <- readRDS(final_path)
    if (!identical(object$spec, validation_spec()))
      stop("cached variance validation does not match the current design")
    assert_validation(object)
    utils::write.csv(object$summary,
                     file.path(OUTDIR, "variance-validation.csv"),
                     row.names = FALSE)
    return(object)
  }

  cache_dir <- file.path(OUTDIR, "variance-validation-cache")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  scenarios <- benchmark_scenarios()
  keys <- paste(rep(METHODS, each = length(HORIZONS)),
                rep(HORIZONS, times = length(METHODS)), sep = "@")
  summaries <- list()
  boot_benchmarks <- list()

  for (i in seq_len(nrow(scenarios))) {
    scen <- scenarios[i, , drop = FALSE]
    set.seed(VALIDATION_DATA_SEED + i)
    dat <- gen_replicate(scen, N_PER_REPLICATE)
    fixed <- estimate_both(dat, need_se = TRUE, keep_iid = TRUE)
    if (any(!is.na(fixed$fail)))
      stop("fixed validation dataset failed for mortality level ", scen$mortality_key)
    iid_path <- file.path(IIDDIR,
                          paste0("validation-", scen$mortality_key, ".rds"))
    atomic_save_rds(list(scenario = scen, iid = attr(fixed, "iid")), iid_path)
    attr(fixed, "iid") <- NULL

    state_path <- file.path(cache_dir,
                            paste0("bootstrap-", scen$mortality_key, ".rds"))
    if (file.exists(state_path)) {
      state <- readRDS(state_path)
      if (!identical(state$spec, validation_spec()))
        stop("bootstrap checkpoint does not match the current design")
      assign(".Random.seed", state$rng, envir = .GlobalEnv)
    } else {
      set.seed(VALIDATION_BOOTSTRAP_SEED + i)
      state <- list(
        spec = validation_spec(),
        completed = 0L,
        estimates = matrix(NA_real_, nrow = BOOTSTRAP_B, ncol = length(keys),
                           dimnames = list(NULL, keys)),
        elapsed = rep(NA_real_, BOOTSTRAP_B),
        rng = get(".Random.seed", envir = .GlobalEnv)
      )
    }

    if (state$completed < BOOTSTRAP_B) {
      for (b in seq.int(state$completed + 1L, BOOTSTRAP_B)) {
        started <- proc.time()[["elapsed"]]
        index <- sample.int(nrow(dat), nrow(dat), replace = TRUE)
        boot_fit <- estimate_both(dat[index, , drop = FALSE], need_se = FALSE)
        state$estimates[b, ] <- estimate_vector(boot_fit, keys)
        state$elapsed[b] <- proc.time()[["elapsed"]] - started
        state$completed <- b
        if (b %% BOOTSTRAP_CHECKPOINT == 0L || b == BOOTSTRAP_B) {
          state$rng <- get(".Random.seed", envir = .GlobalEnv)
          atomic_save_rds(state, state_path)
        }
      }
    }

    boot_se <- apply(state$estimates, 2L, stats::sd, na.rm = TRUE)
    boot_convergence <- colMeans(is.finite(state$estimates))
    fixed_se <- setNames(fixed$se, paste(fixed$method, fixed$horizon, sep = "@"))
    rows <- data.frame(
      mortality_key = scen$mortality_key,
      scenario = scen$scenario,
      method = rep(METHODS, each = length(HORIZONS)),
      horizon = rep(HORIZONS, times = length(METHODS)),
      if_se = unname(fixed_se[keys]),
      bootstrap_se = unname(boot_se[keys]),
      bootstrap_convergence = unname(boot_convergence[keys]),
      n_bootstrap = BOOTSTRAP_B,
      stringsAsFactors = FALSE
    )
    rows$relative_disagreement <- abs(rows$if_se / rows$bootstrap_se - 1)
    summaries[[i]] <- rows
    boot_benchmarks[[i]] <- data.frame(
      mortality_key = scen$mortality_key,
      median_sec = stats::median(state$elapsed, na.rm = TRUE),
      p95_sec = unname(stats::quantile(state$elapsed, 0.95, na.rm = TRUE)),
      stringsAsFactors = FALSE
    )
  }

  object <- list(
    spec = validation_spec(),
    summary = do.call(rbind, summaries),
    bootstrap_benchmark = do.call(rbind, boot_benchmarks)
  )
  assert_validation(object)
  atomic_save_rds(object, final_path)
  utils::write.csv(object$summary,
                   file.path(OUTDIR, "variance-validation.csv"),
                   row.names = FALSE)
  object
}

r_peak_memory_mb <- function() {
  g <- gc()
  if (ncol(g) >= 6L) sum(g[, 6L]) else sum(g[, 2L])
}

benchmark_spec <- function() {
  list(truth = truth_lock_spec(), n = N_PER_REPLICATE,
       replicates = BENCHMARK_REPLICATES)
}

run_production_benchmark <- function() {
  path <- file.path(OUTDIR, "production-benchmark.rds")
  if (file.exists(path)) {
    object <- readRDS(path)
    if (!identical(object$spec, benchmark_spec()))
      stop("cached production benchmark does not match the current design")
    return(object)
  }

  scenarios <- benchmark_scenarios()
  rows <- list()
  for (i in seq_len(nrow(scenarios))) {
    scen <- scenarios[i, , drop = FALSE]
    set.seed(BENCHMARK_SEED + i)
    invisible(gc(reset = TRUE))
    elapsed <- numeric(BENCHMARK_REPLICATES)
    output <- vector("list", BENCHMARK_REPLICATES)
    for (b in seq_len(BENCHMARK_REPLICATES)) {
      started <- proc.time()[["elapsed"]]
      dat <- gen_replicate(scen, N_PER_REPLICATE)
      output[[b]] <- estimate_both(dat, need_se = TRUE, keep_iid = FALSE)
      elapsed[b] <- proc.time()[["elapsed"]] - started
    }
    temporary <- tempfile(fileext = ".rds")
    checkpoint_sec <- unname(system.time(saveRDS(output, temporary))[["elapsed"]])
    serialized_bytes <- file.info(temporary)$size
    unlink(temporary)
    rows[[i]] <- data.frame(
      mortality_key = scen$mortality_key,
      scenario = scen$scenario,
      n_benchmarked = BENCHMARK_REPLICATES,
      median_sec = stats::median(elapsed),
      p95_sec = unname(stats::quantile(elapsed, 0.95)),
      peak_r_memory_mb = r_peak_memory_mb(),
      serialized_bytes = serialized_bytes,
      checkpoint_sec = checkpoint_sec,
      stringsAsFactors = FALSE
    )
  }
  object <- list(spec = benchmark_spec(), summary = do.call(rbind, rows))
  atomic_save_rds(object, path)
  utils::write.csv(object$summary, file.path(OUTDIR, "benchmark.csv"),
                   row.names = FALSE)
  object
}

safe_system_value <- function(command, args) {
  value <- try(system2(command, args, stdout = TRUE, stderr = FALSE), silent = TRUE)
  if (inherits(value, "try-error") || !length(value)) NA_character_ else value[1]
}

write_runtime_report <- function(production_benchmark, validation) {
  p <- production_benchmark$summary
  b <- validation$bootstrap_benchmark
  truth_seconds <- sum(TRUTH$truth_elapsed_sec[match(unique(TRUTH$scenario),
                                                       TRUTH$scenario)])
  production_seconds <- max(p$p95_sec) * nrow(build_scenarios()) * N_REP / WORKERS
  bootstrap_seconds <- max(b$p95_sec) * nrow(b) * BOOTSTRAP_B
  serialization_seconds <- mean(p$checkpoint_sec) * nrow(build_scenarios()) *
    N_REP / BENCHMARK_REPLICATES
  subtotal <- truth_seconds + production_seconds + bootstrap_seconds +
    serialization_seconds
  total <- 1.20 * subtotal
  components <- data.frame(
    component = c("truth", "production fitting and prediction",
                  "bootstrap validation", "serialization and checkpointing",
                  "20 percent operational overhead", "total"),
    projected_hours = c(truth_seconds, production_seconds, bootstrap_seconds,
                        serialization_seconds, 0.20 * subtotal, total) / 3600,
    stringsAsFactors = FALSE
  )
  utils::write.csv(components, file.path(OUTDIR, "runtime-extrapolation.csv"),
                   row.names = FALSE)

  metadata <- data.frame(
    field = c("system", "release", "machine", "processor", "physical_memory_bytes",
              "workers", "production_replicates", "projected_output_bytes",
              "overnight_ceiling_hours"),
    value = c(Sys.info()[["sysname"]], Sys.info()[["release"]],
              Sys.info()[["machine"]],
              safe_system_value("sysctl", c("-n", "machdep.cpu.brand_string")),
              safe_system_value("sysctl", c("-n", "hw.memsize")),
              as.character(WORKERS), as.character(N_REP),
              as.character(mean(p$serialized_bytes) * nrow(build_scenarios()) *
                             N_REP / BENCHMARK_REPLICATES),
              as.character(OVERNIGHT_HOURS)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(metadata, file.path(OUTDIR, "benchmark-metadata.csv"),
                   row.names = FALSE)

  if (!is.finite(total) || total > OVERNIGHT_HOURS * 3600)
    stop(sprintf("benchmarked projection %.2f hours exceeds the %.1f-hour ceiling",
                 total / 3600, OVERNIGHT_HOURS))
  invisible(components)
}

## Critique fix: production is authorized only after representative production
## timing, all 3000 bootstrap resamples, retained iid checks, hardware recording,
## serialization measurement, and the 20% operational allowance have passed.
production_benchmark <- run_production_benchmark()
validation <- run_variance_validation()
write_runtime_report(production_benchmark, validation)

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  bounds <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(bounds[1], bounds[2]), sel)
}

res <- run_design(
  one_rep,
  scenarios,
  n_rep = N_REP,
  master_seed = MASTER_SEED,
  outdir = OUTDIR,
  workers = WORKERS,
  resume = TRUE,
  only = sel
)

write_provenance(
  OUTDIR,
  packages = c("survival", "riskRegression", "future", "furrr"),
  extra = list(
    study = "OUT-01 standardized Cox net-risk displacement",
    scenarios = nrow(scenarios),
    replicates = N_REP,
    protocol_replicates = N_REP_PROTOCOL,
    n_per_replicate = N_PER_REPLICATE,
    master_seed = MASTER_SEED,
    truth_initial_n = N_TRUTH_INITIAL,
    truth_mcse_limit = TRUTH_MCSE_LIMIT,
    bootstrap_resamples_per_dataset = BOOTSTRAP_B,
    workers = WORKERS
  )
)

message(sprintf("run complete or resumed: %d returned rows", nrow(res)))
