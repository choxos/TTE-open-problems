## AUC must not depend on the order the rows arrive in.
##
## Both AUC routines group tied scores with `rowsum` and then read the result
## positionally: `cumsum` treats row k as the k-th smallest score. `rowsum` only
## returns rows in that order when `reorder` is left at its default. Written
## with `reorder = FALSE` the rows come back in order of first appearance, so
## the answer became a function of how the caller sorted its data. It was
## correct on the quadrature truth grid, which is nearly sorted by score, and
## wrong everywhere else, so truth and estimates disagreed by 0.0385 with a
## Monte Carlo standard error of 0.00004.
##
## The shuffle is the whole test. Sorted input passes under either version.
##
##   Rscript tests/test-auc.R

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
source(here('R', '01-dgm.R'))
source(here('R', '02-estimators.R'))

## The definition, quadratic in n and therefore only usable on small inputs.
auc_direct <- function(score, case_weight, control_weight) {
  gt <- outer(score, score, '>')
  eq <- outer(score, score, '==')
  sum((case_weight %o% control_weight) * (gt + 0.5 * eq)) /
    (sum(case_weight) * sum(control_weight))
}

fail <- 0L
check <- function(label, got, want, tol = 1e-10) {
  ok <- is.finite(got) && is.finite(want) && abs(got - want) < tol
  cat(sprintf('%-58s %s  (%.8f vs %.8f)\n', label,
              if (ok) 'PASS' else 'FAIL', got, want))
  if (!ok) fail <<- fail + 1L
}

set.seed(20260802)
n <- 600L
x1 <- stats::rnorm(n)
x2 <- stats::rbinom(n, 1, 0.5)
pl <- (1 - P_U) * baseline_l_probability(x1, x2, 0) +
  P_U * baseline_l_probability(x1, x2, 1)
l0 <- stats::rbinom(n, 1, pl)
p <- counterfactual_risk(x1, x2, l0, 0, 'g0')
w <- rep(1 / n, n)
reference <- auc_direct(p, w * p, w * (1 - p))

check('weighted_auc_value, input sorted by score',
      weighted_auc_value(p[order(p)], (w * p)[order(p)],
                         (w * (1 - p))[order(p)]), reference)
check('weighted_auc_value, input shuffled',
      weighted_auc_value(p, w * p, w * (1 - p)), reference)
check('weighted_auc_value, input reverse sorted',
      weighted_auc_value(p[order(-p)], (w * p)[order(-p)],
                         (w * (1 - p))[order(-p)]), reference)

## The estimator carries the same grouping and feeds an influence function.
y <- stats::rbinom(n, 1, p)
est_ref <- auc_direct(p, w * y, w * (1 - y))
o <- order(p)
check('auc_estimate_and_if, input sorted by score',
      auc_estimate_and_if(p[o], y[o], w[o])$estimate, est_ref)
check('auc_estimate_and_if, input shuffled',
      auc_estimate_and_if(p, y, w)$estimate, est_ref)

## An influence function has mean zero by construction; a mis-ordered grouping
## breaks that before it breaks anything visible in the point estimate.
inf <- auc_estimate_and_if(p, y, w)$influence
check('influence function is centered', mean(inf) * n, 0, 1e-8)

## Ties are the case the grouping exists for.
tied <- round(p, 2)
check('weighted_auc_value with heavy ties',
      weighted_auc_value(tied, w * p, w * (1 - p)),
      auc_direct(tied, w * p, w * (1 - p)))

cat(sprintf('\n%s\n', if (fail) sprintf('%d failed', fail) else 'all passed'))
quit(save = 'no', status = if (fail) 1L else 0L)
