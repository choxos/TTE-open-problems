## The fitted reduced-history method must be able to produce an estimate.
##
## It produced none, in any replicate of any scenario, for the whole study. The
## gate that rejected it is a check for a degenerate estimating-function system,
## and it was firing on two artifacts rather than on degeneracy.
##
## The stack holds one column per distinct quantity. The miscalibrated score is
## expit(-0.35 + 0.75 logit(p)), so its weak-calibration slope is exactly 4/3 of
## the oracle slope and its intercept is the oracle intercept plus 7/15 of the
## oracle slope. Those columns are affine functions of columns already present.
## The exclusion list already dropped the miscalibrated calibration bins and AUC,
## which are redundant by equality; these are redundant by an affine map, which
## is why they were missed and why no amount of looking at the values would have
## shown it.
##
## And an eigenvalue taken relative to the largest is not scale free. These
## columns are calibration slopes beside bin risks beside an AUC, their standard
## deviations span six hundredfold, and eigenvalue ratios move with the square
## of that. A full-rank stack still failed a 1e-10 threshold on the covariance
## scale while clearing it by five orders of magnitude on the correlation scale.
##
##   Rscript tests/test-stack.R

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

fail <- 0L
check <- function(label, ok, detail = '') {
  cat(sprintf('%-56s %s  %s\n', label, if (ok) 'PASS' else 'FAIL', detail))
  if (!ok) fail <<- fail + 1L
}

truth_file <- here('results', 'truth.rds')
if (!file.exists(truth_file)) {
  cat('truth.rds absent; run R/03-truth.R first\n')
  quit(save = 'no', status = 0L)
}
TRUTH <- readRDS(truth_file)
scen <- build_scenarios()[1L, , drop = FALSE]
cuts <- TRUTH$cuts[TRUTH$cuts$scenario == 1,
                   c('strategy', 'score', 'cut', 'value'), drop = FALSE]

set.seed(99)
dat <- gen_replicate(scen, N_PER_REP)
scores <- make_scores(dat, scen)
fit <- fit_reduced_models(dat)
check('the treatment model fits on this replicate', is.null(fit$fail),
      if (is.null(fit$fail)) '' else fit$fail)
if (!is.null(fit$fail)) quit(save = 'no', status = 1L)

p <- fitted_probability_matrix(dat, fit)
w <- list(g0 = weights_from_probabilities(dat, p, 'g0'),
          g1 = weights_from_probabilities(dat, p, 'g1'))
comp <- compute_base_metrics(dat, scores, cuts, w, TRUE, TRUE)
nu <- nuisance_influence(dat, fit)
C <- comp$influence
finite_col <- apply(C, 2L, function(z) all(is.finite(z)))

## The affine identity, stated as arithmetic rather than asserted.
for (g in STRATEGIES) {
  o_i <- C[, paste(g, 'oracle', 'cal_intercept', sep = '|')]
  o_s <- C[, paste(g, 'oracle', 'cal_slope', sep = '|')]
  m_i <- C[, paste(g, 'miscalibrated', 'cal_intercept', sep = '|')]
  m_s <- C[, paste(g, 'miscalibrated', 'cal_slope', sep = '|')]
  check(sprintf('%s miscalibrated slope is 4/3 of the oracle slope', g),
        max(abs(m_s - o_s / 0.75)) < 1e-8)
  check(sprintf('%s miscalibrated intercept is the oracle affine map', g),
        max(abs(m_i - (o_i + (0.35 / 0.75) * o_s))) < 1e-8)
}

drop_old <- !grepl('[|]miscalibrated[|]cal_bin_', colnames(C)) &
  !grepl('[|]miscalibrated[|]auc$', colnames(C))
drop_new <- drop_old &
  !grepl('[|]miscalibrated[|]cal_(intercept|slope)$', colnames(C))
S_old <- cbind(nu$influence, C[, finite_col & drop_old, drop = FALSE])
S_new <- cbind(nu$influence, C[, finite_col & drop_new, drop = FALSE])
check('the old exclusion leaves a rank-deficient stack',
      qr(S_old)$rank < ncol(S_old),
      sprintf('rank %d of %d', qr(S_old)$rank, ncol(S_old)))
check('the new exclusion leaves a full-rank stack',
      qr(S_new)$rank == ncol(S_new),
      sprintf('rank %d of %d', qr(S_new)$rank, ncol(S_new)))

ratio <- function(M, correlation) {
  M <- sweep(M, 2L, colMeans(M), '-')
  V <- crossprod(M) / nrow(M)^2
  V <- (V + t(V)) / 2
  if (correlation) {
    d <- sqrt(diag(V))
    V <- V / outer(d, d)
  }
  e <- eigen((V + t(V)) / 2, symmetric = TRUE, only.values = TRUE)$values
  min(e) / max(e)
}
check('a full-rank stack still fails the covariance-scale test',
      ratio(S_new, FALSE) < SINGULAR_RATIO,
      sprintf('%.3g against %.0e', ratio(S_new, FALSE), SINGULAR_RATIO))
check('the same stack clears the correlation-scale test',
      ratio(S_new, TRUE) > SINGULAR_RATIO,
      sprintf('%.3g against %.0e', ratio(S_new, TRUE), SINGULAR_RATIO))

## What all of it is for.
got <- 0L
for (i in 1:4) {
  set.seed(500 + i)
  fr <- estimate_all(gen_replicate(scen, N_PER_REP), scen, cuts)
  fr <- fr[fr$method == 'fitted_reduced', ]
  if (sum(is.finite(fr$est)) > 0L) got <- got + 1L
}
check('the fitted method estimates on some replicates', got > 0L,
      sprintf('%d of 4', got))

cat(sprintf('\n%s\n', if (fail) sprintf('%d failed', fail) else 'all passed'))
quit(save = 'no', status = if (fail) 1L else 0L)
