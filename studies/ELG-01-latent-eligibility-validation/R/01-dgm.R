## ELG-01: data-generating mechanism.
##
## All individual-level draws are vectorized. The only loops below operate over
## calibration chunks or the three fixed lambda arms.

expit <- function(x) stats::plogis(x)

calibrate_recording <- function(n = N_CALIBRATION, seed = CALIBRATION_SEED,
                                chunk = 500000L) {
  ## This seed belongs to deterministic calibration, not to a replicate. The
  ## simulation harness owns every replicate stream.
  set.seed(seed)
  lp <- numeric(n)
  starts <- seq.int(1L, n, by = chunk)
  for (first in starts) {
    last <- min(n, first + chunk - 1L)
    k <- last - first + 1L
    Z <- stats::runif(k, -1, 1)
    S <- stats::rbinom(k, 1, 0.50)
    H <- stats::rbinom(k, 1, expit(0.10 - 0.50 * Z + 0.40 * S))
    C <- stats::rbinom(k, 1, expit(-1.00 + 0.80 * Z + 0.50 * S - 0.70 * H))
    I <- stats::rbinom(k, 1, expit(-0.50 + 0.50 * Z + 0.90 * C -
                                  0.60 * H + 0.30 * S))
    lp[first:last] <- 0.50 * Z + 0.80 * C + 0.70 * I - 0.60 * H
  }

  rows <- lapply(MISSING_PROPORTIONS, function(m) {
    objective <- function(alpha) mean(expit(alpha + lp)) - (1 - m)
    alpha <- stats::uniroot(objective, c(-12, 12), tol = 1e-12)$root
    achieved <- mean(1 - expit(alpha + lp))
    data.frame(m = m, alpha = alpha, achieved_missing = achieved,
               error = achieved - m)
  })
  out <- do.call(rbind, rows)
  if (any(abs(out$error) >= 0.0001)) stop('recording calibration missed tolerance')
  rownames(out) <- NULL
  out
}

## One harness replicate generates every lambda and validation-budget arm for a
## fixed m, effect structure, and kappa. This is the critique-required
## identification component: X, A, Y, R, and the observed laboratory fields are
## shared objects rather than independently regenerated approximations.
gen_paired_replicate <- function(cell, rep_id, n = N_PER_REP) {
  Z <- stats::runif(n, -1, 1)
  age <- 65 + 15 * Z
  S <- stats::rbinom(n, 1, 0.50)
  H <- stats::rbinom(n, 1, expit(0.10 - 0.50 * Z + 0.40 * S))
  C <- stats::rbinom(n, 1, expit(-1.00 + 0.80 * Z + 0.50 * S - 0.70 * H))
  I <- stats::rbinom(n, 1, expit(-0.50 + 0.50 * Z + 0.90 * C -
                                0.60 * H + 0.30 * S))
  pA <- expit(-0.30 + 0.35 * Z + 0.65 * C + 0.75 * I -
              0.40 * H + 0.20 * S)
  A <- stats::rbinom(n, 1, pA)

  pR <- expit(cell$alpha_m + 0.50 * Z + 0.80 * C + 0.70 * I - 0.60 * H)
  R <- stats::rbinom(n, 1, pR)

  epsilon <- stats::qlogis(stats::runif(n))
  p0 <- 0.20 + 0.04 * Z + 0.08 * C - 0.03 * H + 0.03 * I + 0.02 * S
  delta <- if (cell$effect == 'homogeneous') {
    rep(-0.06, n)
  } else {
    -0.04 - 0.08 * C
  }
  UY <- stats::runif(n)
  Y0 <- as.integer(UY <= p0)
  Y1 <- as.integer(UY <= p0 + delta)
  Y <- ifelse(A == 1L, Y1, Y0)
  u_validation <- stats::runif(n)

  dat <- data.frame(
    Z = Z, age = age, S = S, H = H, C = C, I = I,
    A = A, Y = Y, R = R, pR = pR, pA_true = pA,
    u_validation = u_validation,
    stringsAsFactors = FALSE
  )

  eta <- 0.85 - 0.65 * Z - cell$kappa * C + 0.25 * S + 0.50 * H
  arms <- lapply(seq_along(LAMBDA_VALUES), function(j) {
    lambda <- unname(LAMBDA_VALUES[j])
    T <- eta + lambda * (1 - R) + epsilon
    G <- 45 + 5 * T
    E <- as.integer(G >= 45)
    G_obs <- ifelse(R == 1L, G, NA_real_)
    E_obs <- ifelse(R == 1L, E, NA_integer_)
    view <- data.frame(
      Z = Z, S = S, C = C, H = H, I = I, A = A, Y = Y, R = R,
      G_obs = G_obs, E_obs = E_obs,
      stringsAsFactors = FALSE
    )
    list(lambda = lambda, G = G, E = E, G_obs = G_obs,
         E_obs = E_obs, view = view)
  })
  names(arms) <- names(LAMBDA_VALUES)

  reference <- arms[[1L]]$view
  observed_identical <- all(vapply(
    arms[-1L], function(x) identical(x$view, reference), logical(1)
  ))

  list(dat = dat, arms = arms, observed_identical = observed_identical,
       rep_id = rep_id)
}

truth_covariates <- function(n) {
  Z <- stats::runif(n, -1, 1)
  S <- stats::rbinom(n, 1, 0.50)
  H <- stats::rbinom(n, 1, expit(0.10 - 0.50 * Z + 0.40 * S))
  C <- stats::rbinom(n, 1, expit(-1.00 + 0.80 * Z + 0.50 * S - 0.70 * H))
  I <- stats::rbinom(n, 1, expit(-0.50 + 0.50 * Z + 0.90 * C -
                                0.60 * H + 0.30 * S))
  list(Z = Z, S = S, H = H, C = C, I = I)
}
