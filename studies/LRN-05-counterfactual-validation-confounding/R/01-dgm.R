## Study LRN-05: data-generating mechanism and exact treatment probabilities.

expit <- function(x) stats::plogis(x)
logit <- function(x) stats::qlogis(x)
clip_probability <- function(x, eps = 1e-12) pmin(1 - eps, pmax(eps, x))

event_probability <- function(eta) -expm1(-exp(eta))

baseline_l_probability <- function(x1, x2, u) {
  expit(-0.40 + 0.45 * x1 + 0.65 * x2 + 0.80 * u)
}

later_l_probability <- function(previous_l, x1, x2, previous_a) {
  expit(-0.70 + 1.35 * previous_l + 0.25 * x1 + 0.35 * x2 -
          0.50 * previous_a)
}

baseline_a_probability <- function(x1, x2, l0, u, alpha, gamma) {
  expit(alpha + 0.35 * x1 + 0.50 * x2 + 0.90 * l0 + gamma * u)
}

later_a_probability <- function(previous_a, x1, x2, l, u, alpha, gamma) {
  expit(alpha + 3.50 * (2 * previous_a - 1) + 0.25 * x1 +
          0.35 * x2 + 0.75 * l + gamma * u)
}

outcome_eta <- function(x1, x2, l, a, u, delta) {
  -4.80 + 0.30 * x1 + 0.40 * x2 + 0.50 * l + delta * u -
    0.40 * a - 0.30 * a * x2
}

posterior_u_at_baseline <- function(x1, x2, l0) {
  p0 <- baseline_l_probability(x1, x2, 0)
  p1 <- baseline_l_probability(x1, x2, 1)
  q0 <- ifelse(l0 == 1L, p0, 1 - p0)
  q1 <- ifelse(l0 == 1L, p1, 1 - p1)
  num <- P_U * q1
  num / (num + (1 - P_U) * q0)
}

## Generate one replicate. The monthly loop is over the 24 decision times;
## every operation within a month is vectorized over individuals still at risk.
gen_replicate <- function(scen, n = N_PER_REP) {
  x1 <- stats::rnorm(n)
  x2 <- stats::rbinom(n, 1, 0.50)
  u <- stats::rbinom(n, 1, P_U)
  l <- matrix(NA_integer_, nrow = n, ncol = N_MONTHS)
  a <- matrix(NA_integer_, nrow = n, ncol = N_MONTHS)
  y <- integer(n)
  event_month <- rep(NA_integer_, n)
  alive <- rep(TRUE, n)

  l[, 1L] <- stats::rbinom(n, 1, baseline_l_probability(x1, x2, u))

  for (tt in seq_len(N_MONTHS)) {
    idx <- which(alive)
    if (!length(idx)) break

    if (tt > 1L) {
      l[idx, tt] <- stats::rbinom(
        length(idx), 1,
        later_l_probability(l[idx, tt - 1L], x1[idx], x2[idx],
                            a[idx, tt - 1L])
      )
    }

    pa <- if (tt == 1L) {
      baseline_a_probability(x1[idx], x2[idx], l[idx, tt], u[idx],
                             scen$alpha, scen$gamma)
    } else {
      later_a_probability(a[idx, tt - 1L], x1[idx], x2[idx], l[idx, tt],
                          u[idx], scen$alpha, scen$gamma)
    }
    a[idx, tt] <- stats::rbinom(length(idx), 1, pa)

    py <- event_probability(outcome_eta(x1[idx], x2[idx], l[idx, tt],
                                        a[idx, tt], u[idx], scen$delta))
    hit <- stats::rbinom(length(idx), 1, py) == 1L
    if (any(hit)) {
      who <- idx[hit]
      y[who] <- 1L
      event_month[who] <- tt - 1L
      alive[who] <- FALSE
    }
  }

  list(x1 = x1, x2 = x2, u = u, l0 = l[, 1L], l = l, a = a,
       y = y, event_month = event_month)
}

## Exact P(Y under g by month 24 | X1, X2, L0). Survivor mass is propagated
## over the two U states and the two current-L states. Treatment is set by the
## intervention, so alpha and gamma correctly do not enter this recursion.
counterfactual_risk <- function(x1, x2, l0, delta, strategy) {
  n <- length(x1)
  g <- if (identical(strategy, 'g1')) 1L else 0L
  post <- posterior_u_at_baseline(x1, x2, l0)

  m0 <- matrix(0, nrow = n, ncol = 2L)
  m1 <- matrix(0, nrow = n, ncol = 2L)
  m0[cbind(seq_len(n), l0 + 1L)] <- 1 - post
  m1[cbind(seq_len(n), l0 + 1L)] <- post

  for (tt in seq_len(N_MONTHS)) {
    if (tt > 1L) {
      p00 <- later_l_probability(0, x1, x2, g)
      p01 <- later_l_probability(1, x1, x2, g)
      n0 <- cbind(m0[, 1L] * (1 - p00) + m0[, 2L] * (1 - p01),
                  m0[, 1L] * p00 + m0[, 2L] * p01)
      n1 <- cbind(m1[, 1L] * (1 - p00) + m1[, 2L] * (1 - p01),
                  m1[, 1L] * p00 + m1[, 2L] * p01)
      m0 <- n0
      m1 <- n1
    }

    for (lv in 0:1) {
      m0[, lv + 1L] <- m0[, lv + 1L] *
        exp(-exp(outcome_eta(x1, x2, lv, g, 0, delta)))
      m1[, lv + 1L] <- m1[, lv + 1L] *
        exp(-exp(outcome_eta(x1, x2, lv, g, 1, delta)))
    }
  }

  1 - rowSums(m0 + m1)
}

make_scores <- function(dat, scen) {
  p0 <- counterfactual_risk(dat$x1, dat$x2, dat$l0, scen$delta, 'g0')
  p1 <- counterfactual_risk(dat$x1, dat$x2, dat$l0, scen$delta, 'g1')
  q0 <- expit(-0.35 + 0.75 * logit(clip_probability(p0)))
  q1 <- expit(-0.35 + 0.75 * logit(clip_probability(p1)))
  list(
    g0 = list(oracle = p0, miscalibrated = q0),
    g1 = list(oracle = p1, miscalibrated = q1)
  )
}

full_history_probabilities <- function(dat, scen) {
  p <- matrix(NA_real_, nrow = length(dat$y), ncol = N_MONTHS)
  for (tt in seq_len(N_MONTHS)) {
    idx <- which(!is.na(dat$a[, tt]))
    if (!length(idx)) next
    p[idx, tt] <- if (tt == 1L) {
      baseline_a_probability(dat$x1[idx], dat$x2[idx], dat$l[idx, tt],
                             dat$u[idx], scen$alpha, scen$gamma)
    } else {
      later_a_probability(dat$a[idx, tt - 1L], dat$x1[idx], dat$x2[idx],
                          dat$l[idx, tt], dat$u[idx], scen$alpha, scen$gamma)
    }
  }
  p
}

## Exact complete-history filter. Survival is informative about U when delta is
## nonzero. The new L value adds no further U information conditional on the
## complete preceding history because its transition model contains no U term.
complete_history_probabilities <- function(dat, scen) {
  n <- length(dat$y)
  pmat <- matrix(NA_real_, nrow = n, ncol = N_MONTHS)
  post <- posterior_u_at_baseline(dat$x1, dat$x2, dat$l0)

  for (tt in seq_len(N_MONTHS)) {
    idx <- which(!is.na(dat$a[, tt]))
    if (!length(idx)) next
    lv <- dat$l[idx, tt]
    if (tt == 1L) {
      pu0 <- baseline_a_probability(dat$x1[idx], dat$x2[idx], lv, 0,
                                    scen$alpha, scen$gamma)
      pu1 <- baseline_a_probability(dat$x1[idx], dat$x2[idx], lv, 1,
                                    scen$alpha, scen$gamma)
    } else {
      ap <- dat$a[idx, tt - 1L]
      pu0 <- later_a_probability(ap, dat$x1[idx], dat$x2[idx], lv, 0,
                                 scen$alpha, scen$gamma)
      pu1 <- later_a_probability(ap, dat$x1[idx], dat$x2[idx], lv, 1,
                                 scen$alpha, scen$gamma)
    }

    pp <- (1 - post[idx]) * pu0 + post[idx] * pu1
    if (any(pp < -1e-12 | pp > 1 + 1e-12 | !is.finite(pp)))
      stop('invalid complete-history treatment probability')
    pmat[idx, tt] <- clip_probability(pp)

    aa <- dat$a[idx, tt]
    z0 <- ifelse(aa == 1L, pu0, 1 - pu0)
    z1 <- ifelse(aa == 1L, pu1, 1 - pu1)
    den <- (1 - post[idx]) * z0 + post[idx] * z1
    post[idx] <- post[idx] * z1 / den

    if (tt < N_MONTHS) {
      survived <- is.na(dat$event_month[idx]) |
        dat$event_month[idx] > (tt - 1L)
      j <- idx[survived]
      if (length(j)) {
        sv0 <- exp(-exp(outcome_eta(dat$x1[j], dat$x2[j], dat$l[j, tt],
                                    dat$a[j, tt], 0, scen$delta)))
        sv1 <- exp(-exp(outcome_eta(dat$x1[j], dat$x2[j], dat$l[j, tt],
                                    dat$a[j, tt], 1, scen$delta)))
        den <- (1 - post[j]) * sv0 + post[j] * sv1
        post[j] <- post[j] * sv1 / den
      }
    }
  }
  pmat
}

state_column <- function(u, l, a) 1L + u + 2L * l + 4L * a

normalize_state_mass <- function(mass) {
  z <- rowSums(mass)
  if (any(!is.finite(z) | z <= 0)) stop('reduced-history state mass vanished')
  mass / z
}

## Critique implementation: this recursion supplies an exact comparator using
## precisely the fitted model's reduced conditioning set. It marginalizes U and
## every earlier measured history rather than pretending the reduced process is
## logistic or Markov after marginalization.
reduced_history_probabilities <- function(dat, scen) {
  n <- length(dat$y)
  pmat <- matrix(NA_real_, nrow = n, ncol = N_MONTHS)
  post <- posterior_u_at_baseline(dat$x1, dat$x2, dat$l0)
  pu0 <- baseline_a_probability(dat$x1, dat$x2, dat$l0, 0,
                                scen$alpha, scen$gamma)
  pu1 <- baseline_a_probability(dat$x1, dat$x2, dat$l0, 1,
                                scen$alpha, scen$gamma)
  pmat[, 1L] <- clip_probability((1 - post) * pu0 + post * pu1)

  if (N_MONTHS == 1L) return(pmat)

  mass <- matrix(0, nrow = n, ncol = 8L)
  prior <- list(rep(1 - P_U, n), rep(P_U, n))
  for (u in 0:1) for (lv in 0:1) for (aa in 0:1) for (ln in 0:1) {
    pl0 <- baseline_l_probability(dat$x1, dat$x2, u)
    ml <- if (lv == 1L) pl0 else 1 - pl0
    pa <- baseline_a_probability(dat$x1, dat$x2, lv, u,
                                 scen$alpha, scen$gamma)
    ma <- if (aa == 1L) pa else 1 - pa
    sv <- exp(-exp(outcome_eta(dat$x1, dat$x2, lv, aa, u, scen$delta)))
    pln <- later_l_probability(lv, dat$x1, dat$x2, aa)
    mln <- if (ln == 1L) pln else 1 - pln
    k <- state_column(u, ln, aa)
    mass[, k] <- mass[, k] + prior[[u + 1L]] * ml * ma * sv * mln
  }
  mass <- normalize_state_mass(mass)

  for (tt in 2:N_MONTHS) {
    active <- !is.na(dat$a[, tt])
    for (lv in 0:1) for (ap in 0:1) {
      k0 <- state_column(0, lv, ap)
      k1 <- state_column(1, lv, ap)
      pa0 <- later_a_probability(ap, dat$x1, dat$x2, lv, 0,
                                 scen$alpha, scen$gamma)
      pa1 <- later_a_probability(ap, dat$x1, dat$x2, lv, 1,
                                 scen$alpha, scen$gamma)
      den <- mass[, k0] + mass[, k1]
      pp <- (mass[, k0] * pa0 + mass[, k1] * pa1) / den
      take <- active & dat$l[, tt] == lv & dat$a[, tt - 1L] == ap
      pmat[take, tt] <- clip_probability(pp[take])
    }

    if (tt == N_MONTHS) next
    next_mass <- matrix(0, nrow = n, ncol = 8L)
    for (u in 0:1) for (lv in 0:1) for (ap in 0:1) for (aa in 0:1) for (ln in 0:1) {
      old <- state_column(u, lv, ap)
      pa <- later_a_probability(ap, dat$x1, dat$x2, lv, u,
                                scen$alpha, scen$gamma)
      ma <- if (aa == 1L) pa else 1 - pa
      sv <- exp(-exp(outcome_eta(dat$x1, dat$x2, lv, aa, u, scen$delta)))
      pln <- later_l_probability(lv, dat$x1, dat$x2, aa)
      mln <- if (ln == 1L) pln else 1 - pln
      new <- state_column(u, ln, aa)
      next_mass[, new] <- next_mass[, new] + mass[, old] * ma * sv * mln
    }
    mass <- normalize_state_mass(next_mass)
  }

  needed <- !is.na(dat$a)
  if (any(!is.finite(pmat[needed]) | pmat[needed] < -1e-12 |
          pmat[needed] > 1 + 1e-12))
    stop('invalid reduced-history treatment probability')
  pmat
}

subset_replicate <- function(dat, index) {
  list(x1 = dat$x1[index], x2 = dat$x2[index], u = dat$u[index],
       l0 = dat$l0[index], l = dat$l[index, , drop = FALSE],
       a = dat$a[index, , drop = FALSE], y = dat$y[index],
       event_month = dat$event_month[index])
}
