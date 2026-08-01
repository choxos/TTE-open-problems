## LRN-01 support stress study: enumerate and cache mechanism truth.
## Usage: Rscript R/03-truth.R [i:j]

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))

OUT <- here("results")
CACHE <- file.path(OUT, "truth-cache")
BUNDLE <- file.path(CACHE, "complexity")
dir.create(BUNDLE, recursive = TRUE, showWarnings = FALSE)

manifest <- projection_manifest_frame()
manifest_file <- file.path(OUT, "projection-manifest.csv")
if (file.exists(manifest_file)) {
  old <- utils::read.csv(manifest_file, stringsAsFactors = FALSE)
  if (!isTRUE(all.equal(old, manifest, check.attributes = FALSE)))
    stop("the frozen projection manifest differs from the cached manifest")
} else utils::write.csv(manifest, manifest_file, row.names = FALSE)

scenarios <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

for (complexity in sort(unique(scenarios$complexity[sel]))) {
  f <- file.path(BUNDLE, sprintf("complexity-%d.rds", complexity))
  if (!file.exists(f)) {
    RNGkind("L'Ecuyer-CMRG")
    set.seed(MASTER_SEED + 10000L + complexity)
    message("enumerating common truth paths for complexity ", complexity)
    b <- truth_for_complexity(complexity)
    saveRDS(b, f)
    message(sprintf("complexity %d: %d paths, max MCSE %.6f",
                    complexity, b$n_paths, b$max_mcse))
  }
}

for (i in sel) {
  f <- file.path(CACHE, sprintf("scenario-%03d.rds", i))
  if (file.exists(f)) next
  s <- scenarios[i, , drop = FALSE]
  b <- readRDS(file.path(BUNDLE, sprintf("complexity-%d.rds", s$complexity)))
  key <- if (s$support_kind == "exact") s$support_key else "common"
  r <- b$rd[b$rd$support_key == key & abs(b$rd$delta - s$delta) < 1e-12, ]
  stopifnot(nrow(r) == 1L)
  sm <- b$support[b$support$support_key == s$support_key, ]
  sp <- b$spans[b$spans$support_key == s$support_key, ]
  span_at <- function(m) {
    z <- sp$span[abs(sp$magnitude - m) < 1e-12]
    if (length(z)) z else NA_real_
  }
  span_mcse_at <- function(m) {
    z <- sp$span_mcse[abs(sp$magnitude - m) < 1e-12]
    if (length(z)) z else NA_real_
  }
  tr <- data.frame(
    estimand_scenario = s$estimand_scenario, observed_law = s$observed_law,
    n = s$n, complexity = s$complexity, support_key = s$support_key,
    support_label = s$support_label, support_kind = s$support_kind,
    geometry = s$geometry, boundary = s$boundary, delta = s$delta,
    risk0 = r$risk0, risk1 = r$risk1, truth_rd = r$rd,
    truth_rd_mcse = r$rd_mcse,
    zero_mass_max = max(sm$zero_mass),
    below_0025_mass_max = max(sm$below_0025_mass),
    span_log15 = span_at(log(1.5)), span_log2 = span_at(log(2)),
    span_log3 = span_at(log(3)),
    span_log15_mcse = span_mcse_at(log(1.5)),
    span_log2_mcse = span_mcse_at(log(2)),
    span_log3_mcse = span_mcse_at(log(3)),
    truth_n = b$n_paths, truth_max_mcse = b$max_mcse,
    stringsAsFactors = FALSE)
  saveRDS(tr, f)
  message(sprintf("truth scenario %d/%d cached", i, nrow(scenarios)))
}

done <- sort(list.files(CACHE, "^scenario-[0-9]+\\.rds$", full.names = TRUE))
if (length(done) < nrow(scenarios)) {
  message(sprintf("%d of %d truth scenarios cached; rerun or request another slice",
                  length(done), nrow(scenarios)))
  quit(save = "no", status = 0)
}
truth <- do.call(rbind, lapply(done, readRDS))
truth <- truth[order(truth$estimand_scenario), ]
rownames(truth) <- NULL
saveRDS(truth, file.path(OUT, "truth.rds"))
utils::write.csv(truth, file.path(OUT, "truth.csv"), row.names = FALSE)

laws <- build_observed_laws()
support_detail <- do.call(rbind, lapply(seq_len(nrow(laws)), function(i) {
  b <- readRDS(file.path(BUNDLE, sprintf("complexity-%d.rds", laws$complexity[i])))
  z <- b$support[b$support$support_key == laws$support_key[i], ]
  cbind(laws[i, c("observed_law", "n", "complexity", "support_key")], z)
}))
rownames(support_detail) <- NULL
saveRDS(support_detail, file.path(OUT, "truth-support.rds"))
utils::write.csv(support_detail, file.path(OUT, "truth-support.csv"), row.names = FALSE)
message(sprintf("truth written for %d estimand scenarios from %d observed laws",
                nrow(truth), nrow(laws)))
