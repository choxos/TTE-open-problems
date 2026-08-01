## MER-01: data-generating mechanism.
##
## All individual operations are vectorized. Loops are over the twelve visits,
## finite states, scenarios, or truth chunks, never over participants.

expit <- function(x) stats::plogis(x)
xor_int <- function(x, e) as.integer((x + e) %% 2L)

lp_l0 <- function(X1, X2) -0.40 + 0.50 * X1 + 0.40 * X2
lp_a0 <- function(L0, X1, X2) -0.70 + 0.80 * L0 + 0.25 * X1 + 0.20 * X2

lp_lt <- function(Lprev, Aprev, X1, X2, month, specification) {
  z <- -0.80 + 1.40 * Lprev - 0.50 * Aprev + 0.35 * X1 +
    0.30 * X2 + 0.03 * month
  if (specification == 'confounder_stress')
    z <- z + 0.60 * Lprev * X2 - 0.50 * (X1 < -0.5)
  z
}

lp_at <- function(Aprev, Lcur, X1, X2, month, specification) {
  z <- -1.40 + 2.00 * Aprev + 0.90 * Lcur + 0.25 * X1 +
    0.20 * X2 + 0.02 * month
  if (specification == 'treatment_stress')
    z <- z + 0.60 * Aprev * Lcur + 0.50 * (X1 > 0.5)
  z
}

lp_y <- function(X1, X2, L11, A11, effect_modification, specification) {
  z <- -2.00 + 0.40 * X1 + 0.30 * X2 + 0.90 * L11
  if (effect_modification) {
    z <- z - 0.60 * A11 - 0.40 * A11 * X2
  } else {
    z <- z - 0.80 * A11
  }
  if (specification == 'outcome_stress')
    z <- z - 0.60 * A11 * (X1 > 0.5)
  z
}

gen_latent <- function(scen, n = N_PER_REPLICATE) {
  X1 <- stats::rnorm(n)
  X2 <- stats::rbinom(n, 1, 0.5)
  X3 <- stats::rbinom(n, 1, 0.5)
  L <- matrix(0L, n, N_MONTHS)
  A <- matrix(0L, n, N_MONTHS)

  L[, 1] <- stats::rbinom(n, 1, expit(lp_l0(X1, X2)))
  A[, 1] <- stats::rbinom(n, 1, expit(lp_a0(L[, 1], X1, X2)))
  if (N_MONTHS > 1L) {
    for (tt in 2:N_MONTHS) {
      month <- tt - 1L
      L[, tt] <- stats::rbinom(
        n, 1, expit(lp_lt(L[, tt - 1L], A[, tt - 1L], X1, X2,
                          month, scen$specification)))
      A[, tt] <- stats::rbinom(
        n, 1, expit(lp_at(A[, tt - 1L], L[, tt], X1, X2,
                          month, scen$specification)))
    }
  }
  Y <- stats::rbinom(
    n, 1, expit(lp_y(X1, X2, L[, N_MONTHS], A[, N_MONTHS],
                      scen$effect_modification, scen$specification)))

  ranking <- integer(n)
  ranking[sample.int(n)] <- seq_len(n)
  list(X1 = X1, X2 = X2, X3 = X3, L = L, A = A, Y = Y,
       validation_rank = ranking)
}

error_probability <- function(scen, X2, X3) {
  if (scen$accuracy >= 1) return(rep(0, length(X2)))
  if (scen$profile == 'nondifferential')
    return(rep(1 - scen$accuracy, length(X2)))
  pair <- error_rate_pair(scen$accuracy)
  high <- switch(scen$profile,
    aligned = X2 == 1L,
    reversed = X2 == 0L,
    unrelated = X3 == 1L,
    no_effect_modification = X2 == 1L,
    stop('unknown error profile: ', scen$profile)
  )
  ifelse(high, pair[['high']], pair[['low']])
}

draw_error_noise <- function(n, n_months = N_MONTHS) {
  list(
    A_fresh = matrix(stats::runif(n * n_months), n),
    A_mix = matrix(stats::runif(n * n_months), n),
    L_fresh = matrix(stats::runif(n * n_months), n),
    L_mix = matrix(stats::runif(n * n_months), n),
    Y = stats::runif(n)
  )
}

error_path <- function(p, fresh_u, mix_u, second_order = FALSE) {
  n <- nrow(fresh_u)
  k <- ncol(fresh_u)
  fresh <- fresh_u < p
  E <- matrix(FALSE, n, k)
  E[, 1] <- fresh[, 1]
  if (k > 1L) {
    for (tt in 2:k) {
      if (!second_order || tt == 2L) {
        E[, tt] <- ifelse(mix_u[, tt] < 0.80, E[, tt - 1L], fresh[, tt])
      } else {
        u <- mix_u[, tt]
        E[, tt] <- ifelse(u < 0.55, E[, tt - 1L],
                          ifelse(u < 0.80, E[, tt - 2L], fresh[, tt]))
      }
    }
  }
  matrix(as.integer(E), n, k)
}

make_observed <- function(dat, scen, noise = NULL) {
  n <- length(dat$X1)
  if (is.null(noise)) noise <- draw_error_noise(n)
  p <- error_probability(scen, dat$X2, dat$X3)
  stress <- scen$specification == 'error_transition_stress'

  EA <- if (scen$error_nodes %in% c('A', 'AL'))
    error_path(p, noise$A_fresh, noise$A_mix, stress) else matrix(0L, n, N_MONTHS)
  EL <- if (scen$error_nodes %in% c('L', 'AL'))
    error_path(p, noise$L_fresh, noise$L_mix, stress) else matrix(0L, n, N_MONTHS)

  ## Critique fix: Y error is generated only in the separate component block.
  EY <- if (isTRUE(scen$outcome_error)) as.integer(noise$Y < (1 - scen$accuracy))
        else integer(n)
  list(A = xor_int(dat$A, EA), L = xor_int(dat$L, EL),
       Y = xor_int(dat$Y, EY), EA = EA, EL = EL, EY = EY,
       error_probability = p)
}

simulate_intervention_arm <- function(X1, X2, X3, uL, uY, scen, regime) {
  n <- length(X1)
  L <- matrix(0L, n, N_MONTHS)
  A <- matrix(0L, n, N_MONTHS)
  L[, 1] <- as.integer(uL[, 1] < expit(lp_l0(X1, X2)))
  A[, 1] <- switch(regime,
    dynamic_one = L[, 1], dynamic_zero = 0L,
    static_one = 1L, static_zero = 0L)
  if (N_MONTHS > 1L) {
    for (tt in 2:N_MONTHS) {
      month <- tt - 1L
      L[, tt] <- as.integer(uL[, tt] < expit(lp_lt(
        L[, tt - 1L], A[, tt - 1L], X1, X2, month,
        scen$specification)))
      A[, tt] <- switch(regime,
        dynamic_one = L[, tt], dynamic_zero = 0L,
        static_one = 1L, static_zero = 0L)
    }
  }
  py <- expit(lp_y(X1, X2, L[, N_MONTHS], A[, N_MONTHS],
                   scen$effect_modification, scen$specification))
  as.integer(uY < py)
}

truth_for <- function(scen, n = N_TRUTH, chunk = 100000L) {
  keys <- CONTRASTS
  acc <- lapply(keys, function(x)
    list(n = 0, y1 = 0, y0 = 0, d = 0, d2 = 0))
  names(acc) <- keys
  done <- 0L

  update_acc <- function(a, y1, y0, keep) {
    d <- y1[keep] - y0[keep]
    a$n <- a$n + length(d)
    a$y1 <- a$y1 + sum(y1[keep])
    a$y0 <- a$y0 + sum(y0[keep])
    a$d <- a$d + sum(d)
    a$d2 <- a$d2 + sum(d * d)
    a
  }

  while (done < n) {
    m <- min(chunk, n - done)
    X1 <- stats::rnorm(m)
    X2 <- stats::rbinom(m, 1, 0.5)
    X3 <- stats::rbinom(m, 1, 0.5)
    uL <- matrix(stats::runif(m * N_MONTHS), m)
    uY <- stats::runif(m)

    yd1 <- simulate_intervention_arm(X1, X2, X3, uL, uY, scen, 'dynamic_one')
    yd0 <- simulate_intervention_arm(X1, X2, X3, uL, uY, scen, 'dynamic_zero')
    ys1 <- simulate_intervention_arm(X1, X2, X3, uL, uY, scen, 'static_one')
    ys0 <- simulate_intervention_arm(X1, X2, X3, uL, uY, scen, 'static_zero')

    acc$dynamic <- update_acc(acc$dynamic, yd1, yd0, rep(TRUE, m))
    acc$dynamic_x2_0 <- update_acc(acc$dynamic_x2_0, yd1, yd0, X2 == 0L)
    acc$dynamic_x2_1 <- update_acc(acc$dynamic_x2_1, yd1, yd0, X2 == 1L)
    acc$static <- update_acc(acc$static, ys1, ys0, rep(TRUE, m))
    done <- done + m
  }

  out <- do.call(rbind, lapply(keys, function(key) {
    a <- acc[[key]]
    v <- if (a$n > 1L) (a$d2 - a$d * a$d / a$n) / (a$n - 1L) else NA_real_
    data.frame(contrast = key, risk_1 = a$y1 / a$n, risk_0 = a$y0 / a$n,
               truth = a$d / a$n, truth_mcse = sqrt(v / a$n),
               truth_n = a$n, stringsAsFactors = FALSE)
  }))
  rownames(out) <- NULL
  out
}
