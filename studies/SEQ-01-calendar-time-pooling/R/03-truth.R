## Study SEQ-01: enumerate and cache mechanism-based truth.
##
## Usage:
##   Rscript R/03-truth.R
##   Rscript R/03-truth.R 1:4
##
## Each scenario is resumable at the 100000-person chunk level.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
CACHE <- file.path(OUT, "truth-cache")
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()

args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq.int(p[1], p[2]), sel)
}

for (i in sel) {
  scen <- scenarios[i, , drop = FALSE]
  sdir <- file.path(CACHE, sprintf("scenario-%03d", i))
  dir.create(sdir, recursive = TRUE, showWarnings = FALSE)
  final_file <- file.path(sdir, "summary.rds")
  if (file.exists(final_file)) {
    message(sprintf("scenario %d/%d: cached", i, nrow(scenarios)))
    next
  }

  chunk_files <- sort(list.files(sdir, "^chunk-[0-9]+\\.rds$", full.names = TRUE))
  nchunk <- length(chunk_files)
  target <- max(TRUTH_INITIAL_CHUNKS, nchunk)
  repeat {
    if (nchunk < target) {
      for (j in seq.int(nchunk + 1L, target)) {
        ## Scenario-independent seeds and fixed-size primitive arrays implement
        ## common random numbers across all factorial cells.
        set.seed(MASTER_SEED + TRUTH_SEED_OFFSET + j)
        x <- truth_chunk(scen, TRUTH_CHUNK)
        saveRDS(x, file.path(sdir, sprintf("chunk-%03d.rds", j)))
        message(sprintf("scenario %d, truth chunk %d: %.1fs", i, j, x$elapsed))
      }
      nchunk <- target
    }
    chunk_files <- sort(list.files(sdir, "^chunk-[0-9]+\\.rds$", full.names = TRUE))
    chunks <- lapply(chunk_files, readRDS)
    set.seed(MASTER_SEED + TRUTH_SEED_OFFSET + 50000L + nchunk)
    interim <- truth_summary(chunks, scen, N_TRUTH_BOOT_INTERIM)
    s <- interim$scenarios
    message(sprintf(
      "scenario %d: n=%d, theta=%.5f [%.5f, %.5f], Delta=%.5f [%.5f, %.5f], %s",
      i, s$n_truth, s$theta_equal, s$theta_equal_lo, s$theta_equal_hi,
      s$delta_rd, s$delta_lo, s$delta_hi, s$truth_class
    ))
    if (truth_ready(interim) || nchunk >= TRUTH_MAX_CHUNKS) break
    target <- min(TRUTH_MAX_CHUNKS, nchunk + TRUTH_BATCH_CHUNKS)
  }

  ## Critique fix: final classification uses joint chunk resampling for every RD,
  ## every pairwise contrast, Delta_RD, and each population projection.
  set.seed(MASTER_SEED + TRUTH_SEED_OFFSET + 70000L + nchunk)
  final <- truth_summary(chunks, scen, N_TRUTH_BOOT)
  final$scenarios$at_cap <- nchunk >= TRUTH_MAX_CHUNKS
  if (final$scenarios$at_cap && final$scenarios$truth_class == "threshold-crossing")
    final$scenarios$truth_class <- "indifference"
  saveRDS(final, final_file)
}

summary_files <- file.path(CACHE, sprintf("scenario-%03d", seq_len(nrow(scenarios))),
                           "summary.rds")
if (!all(file.exists(summary_files))) {
  message(sprintf("%d of %d scenarios complete; rerun another slice to continue",
                  sum(file.exists(summary_files)), length(summary_files)))
  quit(save = "no", status = 0)
}

parts <- lapply(summary_files, readRDS)
truth <- list(
  curves = do.call(rbind, lapply(parts, `[[`, "curves")),
  scenarios = do.call(rbind, lapply(parts, `[[`, "scenarios")),
  projections = do.call(rbind, lapply(parts, `[[`, "projections")),
  chunks = setNames(lapply(parts, `[[`, "chunks"),
                    sprintf("scenario-%03d", seq_len(nrow(scenarios))))
)
truth$scenarios <- merge(truth$scenarios, scenarios, by = "scenario", sort = TRUE)
truth$curves <- merge(truth$curves, scenarios, by = "scenario", sort = TRUE)
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth$curves, file.path(OUT, "truth.csv"), row.names = FALSE)
utils::write.csv(truth$scenarios, file.path(OUT, "truth-scenarios.csv"), row.names = FALSE)
utils::write.csv(truth$projections, file.path(OUT, "truth-projections.csv"), row.names = FALSE)
message(sprintf("truth written for %d scenarios and %d starts",
                nrow(scenarios), N_STARTS))
