## Performance measures for simulation studies, with Monte Carlo standard errors.
##
## Every measure here is reported with its Monte Carlo standard error. A bias of
## 0.02 means nothing without knowing whether the MCSE is 0.001 or 0.03, and a
## simulation study that omits them cannot distinguish a real effect from the
## number of replicates it happened to run. Formulas follow Morris, White and
## Crowther (2019), "Using simulation studies to evaluate statistical methods",
## Statistics in Medicine 38:2074-2102, doi:10.1002/sim.8086, table 6.
##
## Replicates that failed are not silently dropped. Every function takes the full
## replicate set and reports how many were usable, because a method that
## converges on 60% of replicates and is unbiased on those is not an unbiased
## method.

## Bias: mean estimate minus the true value.
perf_bias <- function(est, truth) {
  ok <- is.finite(est)
  n <- sum(ok)
  if (n < 2L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  e <- est[ok]
  c(est = mean(e) - truth,
    mcse = sqrt(stats::var(e) / n),
    n = n)
}

## Empirical standard error: the actual spread of the estimator across
## replicates. This is the honest measure of precision; the model-based SE is a
## claim about it that may be wrong.
perf_empse <- function(est) {
  ok <- is.finite(est)
  n <- sum(ok)
  if (n < 2L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  s <- stats::sd(est[ok])
  c(est = s,
    mcse = s / sqrt(2 * (n - 1)),
    n = n)
}

## Model-based standard error: the average SE the methods report for themselves,
## on the variance scale as Morris et al. define it.
perf_modse <- function(se) {
  ok <- is.finite(se) & se > 0
  n <- sum(ok)
  if (n < 2L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  v <- se[ok]^2
  m <- sqrt(mean(v))
  c(est = m,
    mcse = sqrt(stats::var(v) / (4 * n * m^2)),
    n = n)
}

## Relative error in the model-based SE, as a percentage. This is the measure
## that catches an estimator whose point estimate is fine but whose inference is
## not: a MAIC that ignores weight estimation uncertainty shows up here as a
## large negative number long before coverage moves.
perf_relerror_modse <- function(est, se) {
  ok <- is.finite(est) & is.finite(se) & se > 0
  n <- sum(ok)
  if (n < 2L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  e <- est[ok]; v <- se[ok]^2
  emp <- stats::sd(e)
  mod <- sqrt(mean(v))
  rel <- 100 * (mod / emp - 1)
  ## MCSE of the ratio, delta method on the two components (Morris et al. table 6).
  mcse <- 100 * (mod / emp) * sqrt(
    stats::var(v) / (4 * n * mod^4) + 1 / (2 * (n - 1))
  )
  c(est = rel, mcse = mcse, n = n)
}

## Mean squared error.
perf_mse <- function(est, truth) {
  ok <- is.finite(est)
  n <- sum(ok)
  if (n < 2L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  d <- (est[ok] - truth)^2
  c(est = mean(d),
    mcse = sqrt(stats::var(d) / n),
    n = n)
}

## Interval coverage. `truth` on the same scale as the interval.
perf_coverage <- function(lower, upper, truth) {
  ok <- is.finite(lower) & is.finite(upper)
  n <- sum(ok)
  if (n < 1L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  hit <- lower[ok] <= truth & truth <= upper[ok]
  p <- mean(hit)
  c(est = p, mcse = sqrt(p * (1 - p) / n), n = n)
}

## Bias-eliminated coverage: coverage of the estimator's own expectation rather
## than of the truth. Reported alongside coverage because the two separate the
## two ways an interval fails. If coverage is 0.83 and bias-eliminated coverage
## is 0.95, the intervals are the right width and the point estimate is off. If
## both are 0.83, the intervals are too narrow.
perf_becoverage <- function(est, lower, upper) {
  ok <- is.finite(est) & is.finite(lower) & is.finite(upper)
  n <- sum(ok)
  if (n < 2L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  perf_coverage(lower[ok], upper[ok], mean(est[ok]))
}

## Rejection rate against a null value: type I error when `truth == null`,
## power otherwise.
perf_rejection <- function(lower, upper, null = 0) {
  ok <- is.finite(lower) & is.finite(upper)
  n <- sum(ok)
  if (n < 1L) return(c(est = NA_real_, mcse = NA_real_, n = n))
  rej <- !(lower[ok] <= null & null <= upper[ok])
  p <- mean(rej)
  c(est = p, mcse = sqrt(p * (1 - p) / n), n = n)
}

## Convergence: the share of attempted replicates that produced a usable
## estimate. Reported for every method in every scenario, never as a footnote.
perf_convergence <- function(est, n_attempted) {
  n <- sum(is.finite(est))
  p <- n / n_attempted
  c(est = p, mcse = sqrt(p * (1 - p) / n_attempted), n = n_attempted)
}

## Everything above for one method in one scenario, as a tidy one-row frame.
##
## `est`, `se`, `lower`, `upper` are vectors over replicates; `truth` is the
## estimand for this scenario. `n_attempted` defaults to length(est) but should
## be passed explicitly when failed replicates were dropped upstream, otherwise
## the convergence rate reads as 100% by construction.
performance_summary <- function(est, se = NULL, lower = NULL, upper = NULL,
                                truth, n_attempted = length(est),
                                null = 0, extra = list()) {
  g <- function(x, nm) stats::setNames(as.list(x[c("est", "mcse")]),
                                       c(nm, paste0(nm, "_mcse")))
  out <- c(
    list(n_attempted = n_attempted),
    g(perf_convergence(est, n_attempted), "convergence"),
    g(perf_bias(est, truth), "bias"),
    g(perf_empse(est), "empse"),
    g(perf_mse(est, truth), "mse")
  )
  if (!is.null(se)) {
    out <- c(out,
             g(perf_modse(se), "modse"),
             g(perf_relerror_modse(est, se), "relerror_modse"))
  }
  if (!is.null(lower) && !is.null(upper)) {
    out <- c(out,
             g(perf_coverage(lower, upper, truth), "coverage"),
             g(perf_becoverage(est, lower, upper), "becoverage"),
             g(perf_rejection(lower, upper, null), "rejection"))
  }
  out$n_used <- sum(is.finite(est))
  out$truth <- truth
  as.data.frame(c(extra, out), stringsAsFactors = FALSE)
}

## How many replicates are needed for a target Monte Carlo SE.
##
## Used to justify the replicate count in a protocol before running anything,
## rather than picking 1000 because it is a round number. For bias, the required
## count depends on the estimator's empirical SE, so pass a pilot value.
n_sim_for_bias <- function(target_mcse, empse) ceiling((empse / target_mcse)^2)

n_sim_for_coverage <- function(target_mcse, coverage = 0.95) {
  ceiling(coverage * (1 - coverage) / target_mcse^2)
}
