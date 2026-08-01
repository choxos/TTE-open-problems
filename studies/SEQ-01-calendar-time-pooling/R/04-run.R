## Study SEQ-01: feasibility pilot and replicate driver.
##
## Usage:
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:4
##
## Completed scenarios are cached separately. Each one-row harness call receives
## the same master seed, which preserves common random streams across scenarios.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)
stopifnot(file.exists(here("R", "00-config.R")))

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUT <- here("results")
RAW <- file.path(OUT, "raw")
dir.create(RAW, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()

blank_rep <- function(why) result_template(why)

one_rep <- function(scen, rep_id) {
  t0 <- proc.time()[["elapsed"]]
  noise <- make_noise(N_PEOPLE)
  hist <- try(gen_natural_history(scen, noise), silent = TRUE)
  if (inherits(hist, "try-error")) {
    out <- blank_rep("dgm-failed")
  } else {
    ## The harness owns the stream. There is deliberately no set.seed call here.
    XI <- matrix(sample(c(-1, 1), N_PEOPLE * N_LEF, replace = TRUE),
                 nrow = N_PEOPLE)
    calibrate <- is_sentinel(scen) && rep_id <= N_CALIB_REP
    if ("do_calibration" %in% names(scen))
      calibrate <- isTRUE(as.logical(scen$do_calibration[[1]]))
    out <- try(fit_all_estimators(hist, XI, calibrate = calibrate), silent = TRUE)
    if (inherits(out, "try-error")) out <- blank_rep("estimation-error")
  }
  out$replicate_id <- rep_id
  out$expanded_rows <- if (exists("hist") && !inherits(hist, "try-error")) {
    z <- try(nrow(expand_sequential_trials(hist)), silent = TRUE)
    if (inherits(z, "try-error")) NA_integer_ else z
  } else NA_integer_
  out$wall_seconds <- proc.time()[["elapsed"]] - t0
  out
}

run_feasibility <- function() {
  f <- file.path(OUT, "feasibility.rds")
  if (file.exists(f)) return(readRDS(f))
  stopifnot(file.exists(file.path(OUT, "truth.rds")))
  pilot_dir <- file.path(OUT, "pilot-cache")
  rows <- list()
  z <- 0L
  for (w in PILOT_WORKERS) for (sid in c(1L, 12L)) {
    s <- scenarios[sid, , drop = FALSE]
    s$do_calibration <- FALSE
    d <- file.path(pilot_dir, sprintf("workers-%d-scenario-%03d", w, sid))
    t0 <- proc.time()[["elapsed"]]
    x <- run_design(one_rep, s, n_rep = PILOT_REP, master_seed = MASTER_SEED,
                    outdir = d, workers = w, resume = TRUE, only = 1L)
    elapsed <- proc.time()[["elapsed"]] - t0
    u <- x[x$method == "equal_flexible" & x$estimand == "theta_equal", ]
    z <- z + 1L
    rows[[z]] <- data.frame(
      workers = w, scenario = sid, elapsed = elapsed,
      throughput = PILOT_REP / elapsed,
      median_rep_seconds = stats::median(u$wall_seconds, na.rm = TRUE),
      p90_rep_seconds = unname(stats::quantile(u$wall_seconds, 0.90, na.rm = TRUE)),
      median_expanded_rows = stats::median(u$expanded_rows, na.rm = TRUE),
      peak_worker_mb = max(u$memory_mb, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }

  ## One complete calibration replicate measures the expensive refit overlay.
  s <- scenarios[12L, , drop = FALSE]
  s$do_calibration <- TRUE
  d <- file.path(pilot_dir, "calibration-scenario-012")
  x <- run_design(one_rep, s, n_rep = 1L, master_seed = MASTER_SEED + 17L,
                  outdir = d, workers = 1L, resume = TRUE, only = 1L)
  u <- x[x$method == "equal_flexible" & x$estimand == "theta_equal", ]
  calibration_seconds <- u$bootstrap_seconds[[1]]

  tab <- do.call(rbind, rows)
  rate6 <- min(tab$throughput[tab$workers == max(PILOT_WORKERS)])
  main_seconds <- nrow(scenarios) * N_REP / rate6
  overlay_seconds <- 4 * N_CALIB_REP * calibration_seconds
  truth <- readRDS(file.path(OUT, "truth.rds"))
  truth_seconds <- sum(truth$scenarios$truth_seconds)
  forecast <- main_seconds + overlay_seconds + truth_seconds

  ram <- try(as.numeric(system("sysctl -n hw.memsize", intern = TRUE)) / 1024^2,
             silent = TRUE)
  aggregate_mb <- max(tab$peak_worker_mb[tab$workers == max(PILOT_WORKERS)]) *
    max(PILOT_WORKERS)
  workers_use <- WORKERS
  if (!inherits(ram, "try-error") && is.finite(ram) && aggregate_mb > 0.70 * ram)
    workers_use <- max(1L, floor(0.70 * ram /
                                  max(tab$peak_worker_mb, na.rm = TRUE)))

  result <- list(table = tab, calibration_seconds = calibration_seconds,
                 truth_seconds = truth_seconds, forecast_seconds = forecast,
                 aggregate_mb = aggregate_mb,
                 available_ram_mb = if (inherits(ram, "try-error")) NA_real_ else ram,
                 workers = min(WORKERS, workers_use))
  saveRDS(result, f)
  utils::write.csv(tab, file.path(OUT, "feasibility.csv"), row.names = FALSE)
  if (forecast > OVERNIGHT_SECONDS)
    stop(sprintf("scaled design forecast is %.1f hours, above the 12-hour ceiling",
                 forecast / 3600))
  result
}

stopifnot(file.exists(file.path(OUT, "truth.rds")))
pilot <- run_feasibility()

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq.int(p[1], p[2]), sel)
}

for (i in sel) {
  canonical <- file.path(RAW, sprintf("scenario-%03d.rds", i))
  if (file.exists(canonical)) {
    message(sprintf("scenario %d/%d: cached", i, nrow(scenarios)))
    next
  }
  s <- scenarios[i, , drop = FALSE]
  cache <- file.path(OUT, "harness-cache", sprintf("scenario-%03d", i))
  x <- run_design(one_rep, s, n_rep = N_REP, master_seed = MASTER_SEED,
                  outdir = cache, workers = pilot$workers, resume = TRUE, only = 1L)
  x$scenario <- i
  saveRDS(x, canonical)
  message(sprintf("scenario %d/%d: %d rows written", i, nrow(scenarios), nrow(x)))
}

write_provenance(
  OUT,
  packages = c("stats", "splines", "data.table", "future", "furrr",
               "TrialEmulation"),
  extra = list(
    study = "SEQ-01 conditional calendar-time pooling",
    scenarios = nrow(scenarios), replicates = N_REP,
    people = N_PEOPLE, starts = paste(STARTS, collapse = ","),
    linearized_draws = N_LEF, person_bootstrap_draws = N_PERSON_BOOT,
    calibration_replicates = N_CALIB_REP, master_seed = MASTER_SEED,
    workers = pilot$workers, forecast_hours = pilot$forecast_seconds / 3600
  )
)
message("selected scenarios complete")
