## OUT-01 mechanism study: data-generating mechanism.
##
## Event times arise from two conditionally independent piecewise-exponential
## clocks. All operations over individuals are vectorized. The only loops have
## three iterations, one for each prespecified hazard interval.

expit <- function(x) stats::plogis(x)

draw_covariates <- function(n) {
  Z <- stats::rnorm(n)
  M <- stats::rbinom(n, 1L, 0.50)
  C <- stats::rbinom(n, 1L, expit(-0.40 + 0.35 * Z + 0.25 * M))
  ## N(0, 0.64) denotes variance 0.64, hence standard deviation 0.8.
  S <- 0.30 * Z + 0.50 * C + stats::rnorm(n, sd = sqrt(0.64))
  Q <- stats::rnorm(n)
  data.frame(Z = Z, M = M, C = C, S = S, Q = Q)
}

treatment_probability <- function(x) {
  expit(-0.20 + 0.25 * x$Z + 0.20 * x$M + 0.50 * x$C +
          0.35 * x$S + 0.20 * x$Q)
}

invert_piecewise_exponential <- function(threshold, multiplier,
                                         base_hazards) {
  target <- threshold / multiplier
  cumulative <- cumsum(base_hazards * INTERVAL_WIDTHS)
  previous <- c(0, cumulative[-length(cumulative)])
  starts <- c(0, INTERVAL_ENDS[-length(INTERVAL_ENDS)])
  interval <- rep(NA_integer_, length(target))

  for (j in seq_along(base_hazards)) {
    use <- is.na(interval) & target <= cumulative[j]
    interval[use] <- j
  }

  out <- rep(Inf, length(target))
  for (j in seq_along(base_hazards)) {
    use <- interval == j
    use[is.na(use)] <- FALSE
    out[use] <- starts[j] +
      (target[use] - previous[j]) / base_hazards[j]
  }
  out
}

cause_multipliers <- function(x, scen, treatment) {
  a <- rep(as.numeric(treatment), nrow(x))
  primary_lp <- 0.20 * x$Z + 0.10 * x$M + 0.45 * x$C +
    0.30 * x$S + scen$gamma[[1]] * x$Q +
    scen$beta_YA[[1]] * a + scen$beta_YAC[[1]] * a * x$C
  death_lp <- 0.45 * x$Z + 0.15 * x$M + 0.65 * x$C +
    0.35 * x$S + scen$gamma[[1]] * x$Q + scen$beta_DA[[1]] * a
  list(primary = exp(primary_lp), death = exp(death_lp))
}

gen_replicate <- function(scen, n = N_PER_REPLICATE) {
  x <- draw_covariates(n)
  pA <- treatment_probability(x)
  A <- stats::rbinom(n, 1L, pA)
  mult <- cause_multipliers(x, scen, A)

  threshold_y <- stats::rexp(n)
  threshold_d <- stats::rexp(n)
  time_y <- invert_piecewise_exponential(
    threshold_y, mult$primary, PRIMARY_BASE_HAZARDS)
  time_d <- invert_piecewise_exponential(
    threshold_d, mult$death, death_hazards_for(scen))

  primary_first <- time_y <= 60 & time_y <= time_d
  death_first <- time_d <= 60 & time_d < time_y
  status <- integer(n)
  status[primary_first] <- 1L
  status[death_first] <- 2L
  time <- pmin(time_y, time_d, 60)

  data.frame(x, A = A, pA = pA, time = time, status = status,
             stringsAsFactors = FALSE)
}

## Conditional counterfactual risks under one fixed treatment strategy.
## `total` retains treatment-specific competing death. `net` sets its hazard to
## zero while leaving the primary-event structural hazard unchanged.
profile_risks <- function(x, scen, treatment) {
  mult <- cause_multipliers(x, scen, treatment)
  death_base <- death_hazards_for(scen)
  n <- nrow(x)
  survival_both <- rep(1, n)
  cumulative_y <- rep(0, n)
  cif_y <- rep(0, n)
  total <- matrix(NA_real_, nrow = n, ncol = length(HORIZONS))
  net <- matrix(NA_real_, nrow = n, ncol = length(HORIZONS))

  for (j in seq_along(HORIZONS)) {
    lambda_y <- PRIMARY_BASE_HAZARDS[j] * mult$primary
    lambda_d <- death_base[j] * mult$death
    lambda_all <- lambda_y + lambda_d
    width <- INTERVAL_WIDTHS[j]
    cif_y <- cif_y + survival_both * lambda_y / lambda_all *
      (1 - exp(-lambda_all * width))
    survival_both <- survival_both * exp(-lambda_all * width)
    cumulative_y <- cumulative_y + lambda_y * width
    total[, j] <- cif_y
    net[, j] <- 1 - exp(-cumulative_y)
  }
  colnames(total) <- colnames(net) <- as.character(HORIZONS)
  list(total = total, net = net)
}
