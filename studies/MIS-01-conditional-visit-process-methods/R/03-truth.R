## Study MIS-01: enumerate and cache exact truth.
##
## Usage: Rscript R/03-truth.R
##        Rscript R/03-truth.R 1:20

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1])))) else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

OUT <- here('results')
CACHE <- file.path(OUT, 'truth-cache')
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)
scenarios <- build_scenarios()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl('^[0-9]+:[0-9]+$', args[1])) {
  p <- as.integer(strsplit(args[1], ':', fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}
checks <- truth_check_sids(scenarios)

for (i in sel) {
  path <- file.path(CACHE, sprintf('scenario-%03d.rds', i))
  if (file.exists(path)) {
    message(sprintf('scenario %d/%d: cached', i, nrow(scenarios)))
    next
  }
  s <- prepare_scenario(scenarios[i, , drop = FALSE])
  tr <- truth_from_mechanism(s)
  validation <- data.frame()
  if (i %in% checks) {
    ## Critique fix: strict truth comes from deterministic finite-state
    ## enumeration. Simulation is only an independent stochastic cross-check,
    ## so its tolerance is based on Monte Carlo error rather than 1e-8.
    set.seed(MASTER_SEED + 500000L + i)
    sim1 <- simulate_strategy(s, 1L)
    sim0 <- simulate_strategy(s, 0L)
    exact1 <- tr$risk1[match(c('rd12', 'rd24'), tr$estimand)]
    exact0 <- tr$risk0[match(c('rd12', 'rd24'), tr$estimand)]
    sim <- c(sim1, sim0)
    exact <- c(exact1, exact0)
    se <- sqrt(exact * (1 - exact) / TRUTH_CHECK_N)
    tol <- pmax(0.001, 3 * se)
    validation <- data.frame(quantity = c('risk1_12', 'risk1_24', 'risk0_12', 'risk0_24'),
                             exact = exact, simulated = sim, mcse = se,
                             tolerance = tol, pass = abs(sim - exact) <= tol)
    if (!all(validation$pass)) stop('truth validation failed for scenario ', i)
  }
  payload <- list(scenario = s, truth = tr, validation = validation)
  saveRDS(payload, path)
  message(sprintf('scenario %d/%d: alpha %.6f, kappa %.6f, RD24 %.5f',
                  i, nrow(scenarios), s$alpha, s$kappa,
                  tr$truth[tr$estimand == 'rd24']))
}

done <- sort(list.files(CACHE, pattern = '^scenario-[0-9]+[.]rds$', full.names = TRUE))
if (length(done) < nrow(scenarios)) {
  message(sprintf('%d of %d scenarios cached; rerun or use another slice',
                  length(done), nrow(scenarios)))
  quit(save = 'no', status = 0)
}
objects <- lapply(done, readRDS)
truth <- do.call(rbind, lapply(objects, function(x) cbind(x$scenario[rep(1L, nrow(x$truth)), ], x$truth)))
validation <- do.call(rbind, lapply(objects, function(x) {
  if (!nrow(x$validation)) return(NULL)
  cbind(sid = x$scenario$sid, x$validation)
}))
rownames(truth) <- NULL
saveRDS(truth, file.path(OUT, 'truth.rds'))
utils::write.csv(truth, file.path(OUT, 'truth.csv'), row.names = FALSE)
utils::write.csv(validation, file.path(OUT, 'truth-validation.csv'), row.names = FALSE)
message(sprintf('exact truth written for %d scenarios', nrow(scenarios)))
