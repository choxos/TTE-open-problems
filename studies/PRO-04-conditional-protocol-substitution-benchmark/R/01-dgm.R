## Study PRO-04: data-generating mechanism and deterministic truth.

`%||%` <- function(a, b) if (is.null(a)) b else a
expit <- function(x) 1 / (1 + exp(-x))

.gl_cache <- new.env(parent = emptyenv())
.grid_cache <- new.env(parent = emptyenv())

## Base R Gauss-Legendre nodes. Newton updates are vectorized over all roots.
gauss_legendre <- function(n) {
  key <- as.character(n)
  if (!is.null(.gl_cache[[key]])) return(.gl_cache[[key]])
  stopifnot(n >= 2L)
  k <- seq_len(n)
  x <- cos(pi * (4 * k - 1) / (4 * n + 2))
  for (iteration in seq_len(50L)) {
    pm2 <- rep(1, n)
    pm1 <- x
    for (j in 2:n) {
      p <- ((2 * j - 1) * x * pm1 - (j - 1) * pm2) / j
      pm2 <- pm1
      pm1 <- p
    }
    derivative <- n * (x * pm1 - pm2) / (x^2 - 1)
    step <- pm1 / derivative
    x <- x - step
    if (max(abs(step)) < 1e-15) break
  }
  pm2 <- rep(1, n)
  pm1 <- x
  for (j in 2:n) {
    p <- ((2 * j - 1) * x * pm1 - (j - 1) * pm2) / j
    pm2 <- pm1
    pm1 <- p
  }
  derivative <- n * (x * pm1 - pm2) / (x^2 - 1)
  w <- 2 / ((1 - x^2) * derivative^2)
  ord <- order(x)
  out <- list(x = x[ord], w = w[ord])
  .gl_cache[[key]] <- out
  out
}

## Finite summation over X1, X3, and E, combined with quadrature over X2.
baseline_grid <- function(n_nodes) {
  key <- as.character(n_nodes)
  if (!is.null(.grid_cache[[key]])) return(.grid_cache[[key]])
  gl <- gauss_legendre(n_nodes)
  g <- expand.grid(
    node = seq_len(n_nodes), X1 = c(0L, 1L), X3 = c(0L, 1L),
    E = c(0L, 1L), KEEP.OUT.ATTRS = FALSE
  )
  g$X2 <- gl$x[g$node]
  p_x3 <- expit(-0.30 + 0.60 * g$X1 + 0.50 * g$X2)
  p_e <- stats::pnorm(0.70 * g$X1 + 0.60 * g$X2 + 0.80 * g$X3 - 0.65)
  g$w <- gl$w[g$node] / 2 * 0.50 *
    ifelse(g$X3 == 1L, p_x3, 1 - p_x3) *
    ifelse(g$E == 1L, p_e, 1 - p_e)
  g$node <- NULL
  g$w <- g$w / sum(g$w)
  .grid_cache[[key]] <- g
  g
}

outcome_parts <- function(x1, x2, x3, e, lambda) {
  p0 <- 0.16 + 0.05 * x1 + 0.04 * x2 + 0.06 * x3 + 0.05 * (1 - e)
  g1 <- 0.04 + 0.02 * (1 - e) + 0.02 * x1
  g2 <- -0.04 + 0.08 * (1 - e) + 0.04 * x1
  list(p0 = p0, d1 = -0.06 + lambda * g1,
       d2 = -0.06 + lambda * g2)
}

empty_mechanism <- function(scen) {
  s <- as.list(scen[1, , drop = FALSE])
  list(
    component = as.character(s$component),
    fidelity = as.character(s$fidelity),
    effect_modification = as.character(s$effect_modification),
    dependence = as.character(s$dependence),
    lambda = if (s$effect_modification == 'absent') 0 else NA_real_,
    elig_sens_target = NA_real_, elig_spec_target = NA_real_,
    strategy_q_target = NA_real_,
    outcome_sens_target = NA_real_, outcome_spec_target = NA_real_,
    elig_sens_slope = 0, elig_spec_slope = 0,
    strategy_q_slope = 0, outcome_sens_slope = 0,
    elig_sens_intercept = NA_real_, elig_spec_intercept = NA_real_,
    strategy_q_intercept = NA_real_,
    outcome_sens_intercept = NA_real_, outcome_spec_intercept = NA_real_,
    calibration_error = NA_real_, calibration_ok = FALSE
  )
}

solve_logistic_intercept <- function(target, lp, w) {
  den <- sum(w)
  f <- function(a) sum(w * expit(a + lp)) / den - target
  stats::uniroot(f, interval = c(-35, 35), tol = 1e-12)$root
}

elig_sens_prob <- function(h, x1) {
  expit(h$elig_sens_intercept + h$elig_sens_slope * x1)
}
elig_spec_prob <- function(h, x1) {
  expit(h$elig_spec_intercept + h$elig_spec_slope * x1)
}
strategy_q_prob <- function(h, x1) {
  expit(h$strategy_q_intercept + h$strategy_q_slope * x1)
}
outcome_sens_prob <- function(h, z) {
  expit(h$outcome_sens_intercept + h$outcome_sens_slope * (z - 1))
}
outcome_spec_prob <- function(h) expit(h$outcome_spec_intercept)

outcome_event_calibration <- function(h, n_nodes) {
  g <- baseline_grid(n_nodes)
  g <- g[g$E == 1L, , drop = FALSE]
  assignment <- c('0' = 0.50, '1' = 0.10, '2' = 0.40)
  pieces <- lapply(0:2, function(z) {
    op <- outcome_parts(g$X1, g$X2, g$X3, g$E, h$lambda)
    pz <- op$p0 + if (z == 0L) 0 else if (z == 1L) op$d1 else op$d2
    data.frame(score = z - 1, w = g$w * assignment[as.character(z)] * pz)
  })
  do.call(rbind, pieces)
}

## Critique fix: differential mechanisms are calibrated to the same relevant
## marginal fidelity as their nondifferential counterparts. Only dependence
## changes between those factor levels.
calibrate_mechanism <- function(h, n_nodes = CALIBRATION_NODES) {
  g <- baseline_grid(n_nodes)
  errors <- numeric()
  if (h$component == 'eligibility') {
    g1 <- g[g$E == 1L, , drop = FALSE]
    g0 <- g[g$E == 0L, , drop = FALSE]
    h$elig_sens_intercept <- solve_logistic_intercept(
      h$elig_sens_target, h$elig_sens_slope * g1$X1, g1$w)
    h$elig_spec_intercept <- solve_logistic_intercept(
      h$elig_spec_target, h$elig_spec_slope * g0$X1, g0$w)
    errors <- c(
      sum(g1$w * elig_sens_prob(h, g1$X1)) / sum(g1$w) - h$elig_sens_target,
      sum(g0$w * elig_spec_prob(h, g0$X1)) / sum(g0$w) - h$elig_spec_target
    )
  }
  if (h$component == 'strategy') {
    g1 <- g[g$E == 1L, , drop = FALSE]
    h$strategy_q_intercept <- solve_logistic_intercept(
      h$strategy_q_target, h$strategy_q_slope * g1$X1, g1$w)
    errors <- sum(g1$w * strategy_q_prob(h, g1$X1)) / sum(g1$w) -
      h$strategy_q_target
  }
  if (h$component == 'outcome') {
    ev <- outcome_event_calibration(h, n_nodes)
    h$outcome_sens_intercept <- solve_logistic_intercept(
      h$outcome_sens_target, h$outcome_sens_slope * ev$score, ev$w)
    h$outcome_spec_intercept <- stats::qlogis(h$outcome_spec_target)
    errors <- c(
      sum(ev$w * outcome_sens_prob(h, ev$score + 1)) / sum(ev$w) -
        h$outcome_sens_target,
      outcome_spec_prob(h) - h$outcome_spec_target
    )
  }
  h$calibration_error <- max(abs(errors))
  h$calibration_ok <- is.finite(h$calibration_error) &&
    h$calibration_error <= CALIBRATION_TOL
  h
}

draw_signed_slope <- function() {
  sample(c(-1, 1), size = 1L) *
    stats::runif(1L, DIFFERENTIAL_SLOPE_RANGE[1], DIFFERENTIAL_SLOPE_RANGE[2])
}

## Parameters are redrawn independently for every mechanism. Fidelity, lambda,
## and dependence slopes are sampled independently of all decision margins.
draw_mechanism <- function(scen) {
  h <- empty_mechanism(scen)
  if (h$effect_modification == 'present') h$lambda <- stats::runif(1L)
  b <- fidelity_bounds(h$component, h$fidelity)
  if (h$component == 'eligibility') {
    h$elig_sens_target <- stats::runif(1L, b$sensitivity[1], b$sensitivity[2])
    h$elig_spec_target <- stats::runif(1L, b$specificity[1], b$specificity[2])
    if (h$dependence == 'differential') {
      h$elig_sens_slope <- draw_signed_slope()
      h$elig_spec_slope <- draw_signed_slope()
    }
  }
  if (h$component == 'strategy') {
    h$strategy_q_target <- stats::runif(1L, b$q[1], b$q[2])
    if (h$dependence == 'differential') h$strategy_q_slope <- draw_signed_slope()
  }
  if (h$component == 'outcome') {
    h$outcome_sens_target <- stats::runif(1L, b$sensitivity[1], b$sensitivity[2])
    h$outcome_spec_target <- stats::runif(1L, b$specificity[1], b$specificity[2])
    if (h$dependence == 'differential') h$outcome_sens_slope <- draw_signed_slope()
  }
  calibrate_mechanism(h)
}

calibration_error_at <- function(h, n_nodes) {
  g <- baseline_grid(n_nodes)
  errors <- numeric()
  if (h$component == 'eligibility') {
    g1 <- g[g$E == 1L, , drop = FALSE]
    g0 <- g[g$E == 0L, , drop = FALSE]
    errors <- c(
      sum(g1$w * elig_sens_prob(h, g1$X1)) / sum(g1$w) - h$elig_sens_target,
      sum(g0$w * elig_spec_prob(h, g0$X1)) / sum(g0$w) - h$elig_spec_target
    )
  }
  if (h$component == 'strategy') {
    g1 <- g[g$E == 1L, , drop = FALSE]
    errors <- sum(g1$w * strategy_q_prob(h, g1$X1)) / sum(g1$w) -
      h$strategy_q_target
  }
  if (h$component == 'outcome') {
    ev <- outcome_event_calibration(h, n_nodes)
    errors <- c(
      sum(ev$w * outcome_sens_prob(h, ev$score + 1)) / sum(ev$w) -
        h$outcome_sens_target,
      outcome_spec_prob(h) - h$outcome_spec_target
    )
  }
  max(abs(errors))
}

truth_at_nodes <- function(h, n_nodes) {
  g <- baseline_grid(n_nodes)
  op <- outcome_parts(g$X1, g$X2, g$X3, g$E, h$lambda)
  p0 <- op$p0
  p1 <- p0 + op$d1
  p2 <- p0 + op$d2
  eligible <- g$E == 1L
  den_e <- sum(g$w[eligible])
  psi_i <- sum(g$w[eligible] * (p2[eligible] - p0[eligible])) / den_e

  if (h$component == 'eligibility') {
    p_select <- ifelse(eligible, elig_sens_prob(h, g$X1),
                       1 - elig_spec_prob(h, g$X1))
    psi_o <- sum(g$w * p_select * (p2 - p0)) / sum(g$w * p_select)
  } else if (h$component == 'strategy') {
    q <- strategy_q_prob(h, g$X1)
    mixed <- q * p2 + (1 - q) * p1
    psi_o <- sum(g$w[eligible] * (mixed[eligible] - p0[eligible])) / den_e
  } else {
    fp <- 1 - outcome_spec_prob(h)
    p2_star <- fp + (outcome_sens_prob(h, 2L) - fp) * p2
    p0_star <- fp + (outcome_sens_prob(h, 0L) - fp) * p0
    psi_o <- sum(g$w[eligible] * (p2_star[eligible] - p0_star[eligible])) / den_e
  }
  c(psi_i = psi_i, psi_o = psi_o, delta = psi_o - psi_i)
}

class_delta <- function(delta, preservation = PRESERVATION_MARGIN,
                        material = MATERIAL_MARGIN) {
  if (!is.finite(delta)) return(NA_character_)
  if (abs(delta) <= preservation) return('preserving')
  if (abs(delta) >= material) return('material')
  'gray'
}

## Truth is deterministic quadrature from the mechanism. Refinement continues
## whenever numerical movement could alter a margin classification.
truth_for_mechanism <- function(h) {
  n <- TRUTH_START_NODES
  previous <- truth_at_nodes(h, n)
  previous_class <- class_delta(previous[['delta']])
  converged <- FALSE
  class_resolved <- FALSE
  error <- Inf
  repeat {
    n <- n * 2L
    current <- truth_at_nodes(h, n)
    current_class <- class_delta(current[['delta']])
    error <- max(abs(current - previous))
    class_resolved <- identical(current_class, previous_class)
    target_stable <- error < TRUTH_TOL
    class_numerically_stable <- class_resolved ||
      abs(current[['delta']] - previous[['delta']]) < TRUTH_CLASS_TOL
    if (target_stable && class_numerically_stable) {
      converged <- class_resolved
      break
    }
    if (n >= TRUTH_MAX_NODES) break
    previous <- current
    previous_class <- current_class
  }
  calibration_error <- calibration_error_at(h, n)
  data.frame(
    psi_i = unname(current[['psi_i']]),
    psi_o = unname(current[['psi_o']]),
    delta = unname(current[['delta']]),
    preservation_class = if (class_resolved) current_class else 'boundary-unresolved',
    quadrature_nodes = n,
    quadrature_error = error,
    quadrature_converged = converged,
    class_resolved = class_resolved,
    calibration_error_verified = calibration_error,
    calibration_ok_verified = is.finite(calibration_error) &&
      calibration_error <= CALIBRATION_TOL,
    stringsAsFactors = FALSE
  )
}

## Generate one vectorized individual-level replicate. The harness owns the RNG
## stream, so this function never calls set.seed.
gen_replicate <- function(h, n) {
  X1 <- stats::rbinom(n, 1L, 0.50)
  X2 <- stats::runif(n, -1, 1)
  X3 <- stats::rbinom(n, 1L, expit(-0.30 + 0.60 * X1 + 0.50 * X2))
  B <- 0.70 * X1 + 0.60 * X2 + 0.80 * X3 + stats::rnorm(n)
  E <- as.integer(B >= 0.65)

  if (h$component == 'strategy') {
    A_star <- stats::rbinom(n, 1L, 0.50)
    q <- strategy_q_prob(h, X1)
    Z <- ifelse(A_star == 0L, 0L,
                ifelse(stats::runif(n) < q, 2L, 1L))
  } else {
    u_z <- stats::runif(n)
    Z <- ifelse(u_z < 0.50, 0L, ifelse(u_z < 0.60, 1L, 2L))
    A_star <- as.integer(Z > 0L)
  }

  op <- outcome_parts(X1, X2, X3, E, h$lambda)
  p_y <- op$p0 + ifelse(Z == 1L, op$d1, ifelse(Z == 2L, op$d2, 0))
  if (any(!is.finite(p_y) | p_y < 0 | p_y > 1)) stop('Outcome probability outside [0,1]')
  common_u_y <- stats::runif(n)
  Y <- as.integer(common_u_y < p_y)

  if (h$component == 'eligibility') {
    p_e_star <- ifelse(E == 1L, elig_sens_prob(h, X1),
                       1 - elig_spec_prob(h, X1))
    E_star <- stats::rbinom(n, 1L, p_e_star)
  } else {
    E_star <- E
  }

  if (h$component == 'outcome') {
    sensitivity <- outcome_sens_prob(h, Z)
    p_y_star <- ifelse(Y == 1L, sensitivity, 1 - outcome_spec_prob(h))
    Y_star <- stats::rbinom(n, 1L, p_y_star)
  } else {
    Y_star <- Y
  }

  V <- stats::rbinom(n, 1L, VALIDATION_PROB)
  data.frame(X1 = X1, X2 = X2, X3 = X3, E = E, E_star = E_star,
             Z = Z, A_star = A_star, Y = Y, Y_star = Y_star, V = V)
}

## Fixed nuisance basis in its declared order. Exact redundancies are removed by
## the prespecified rule in 02-estimators.R.
operational_basis <- function(dat, component) {
  common <- cbind(
    intercept = 1,
    X1 = dat$X1,
    X2 = dat$X2,
    X3 = dat$X3,
    X1_X2 = dat$X1 * dat$X2
  )
  if (component == 'eligibility') {
    op <- dat$E_star
    t1 <- as.integer(dat$Z == 1L)
    t2 <- as.integer(dat$Z == 2L)
    return(cbind(common, operational = op, treatment_1 = t1, treatment_2 = t2,
                 operational_treatment_1 = op * t1,
                 operational_treatment_2 = op * t2))
  }
  if (component == 'strategy') {
    op <- dat$A_star
    t1 <- dat$A_star
    return(cbind(common, operational = op, treatment_1 = t1,
                 operational_treatment_1 = op * t1))
  }
  op <- dat$Y_star
  t1 <- as.integer(dat$Z == 1L)
  t2 <- as.integer(dat$Z == 2L)
  cbind(common, operational = op, treatment_1 = t1, treatment_2 = t2,
        operational_treatment_1 = op * t1,
        operational_treatment_2 = op * t2)
}
