## Study MIS-01: mechanism, calibration, and exact mechanism recursion.

expit <- function(x) {
  out <- numeric(length(x))
  pos <- x >= 0
  out[pos] <- 1 / (1 + exp(-x[pos]))
  ex <- exp(x[!pos])
  out[!pos] <- ex / (1 + ex)
  out
}

cloglog_inv <- function(x) 1 - exp(-exp(pmin(x, 35)))
## x first, so a matrix keeps its dimensions (pmin and pmax copy attributes
## from their first argument).
clamp_probability <- function(x, eps = 1e-10) pmin(pmax(x, eps), 1 - eps)

baseline_cells <- function() {
  g <- expand.grid(L0 = 0:1, C = 0:1, F = 0:1, B = 0:1)
  pB <- ifelse(g$B == 1, 0.45, 0.55)
  pF <- ifelse(g$F == 1, 0.52, 0.48)
  pc1 <- expit(-2 + 0.80 * g$B + 0.30 * g$F)
  pC <- ifelse(g$C == 1, pc1, 1 - pc1)
  pl1 <- expit(-1.20 + 0.55 * g$B + 0.80 * g$C - 0.15 * g$F)
  pL <- ifelse(g$L0 == 1, pl1, 1 - pl1)
  g$prob <- pB * pF * pC * pL
  g$cell <- seq_len(nrow(g))
  g
}

transition_probability <- function(scen, t, Lprev, Lprev2, B, C, Aprev) {
  eta <- scen$kappa + scen$beta_LL * Lprev + 0.45 * B + 0.70 * C -
    0.55 * Aprev + 0.10 * (t / 24)
  if (isTRUE(scen$dep_transition) && t >= 2L) {
    eta <- eta + 0.40 * Lprev2 + 0.25 * Lprev * C
  }
  expit(eta)
}

observation_probability <- function(scen, t, L, Aprev, Rprev, C) {
  eta <- scen$alpha + scen$gamma_L * L + scen$gamma_A * Aprev +
    0.405 * Rprev + 0.30 * C
  if (isTRUE(scen$dep_observation)) {
    eta <- eta + 0.35 * L * C + 0.20 * sin(pi * t / 24)
    return(cloglog_inv(eta))
  }
  expit(eta)
}

treatment_probability <- function(scen, t, L, Aprev, R, B, C) {
  eta <- -1.15 + 1.60 * Aprev + scen$beta_AL * L + 0.35 * C +
    0.20 * B + 0.25 * R
  if (isTRUE(scen$dep_treatment_outcome)) {
    eta <- eta + 0.30 * L * C + 0.20 * (t / 24)^2
  }
  expit(eta)
}

outcome_probability <- function(scen, t, L, A, B, C) {
  eta <- -5.10 + scen$beta_YL * L + 0.40 * C + 0.25 * B -
    0.50 * A + scen$beta_YAL * A * L
  if (isTRUE(scen$dep_treatment_outcome)) {
    eta <- eta + 0.25 * A * C + 0.20 * sin(pi * t / 24)
  }
  expit(eta)
}

branch_binary <- function(d, p, name) {
  j <- rep(seq_len(nrow(d)), each = 2L)
  z <- d[j, , drop = FALSE]
  value <- rep(0:1, times = nrow(d))
  z[[name]] <- value
  pp <- rep(p, each = 2L)
  z$prob <- z$prob * ifelse(value == 1L, pp, 1 - pp)
  z
}

aggregate_natural_state <- function(d) {
  stats::aggregate(prob ~ B + F + C + L0 + Lprev + Lprev2 + Aprev + Rprev,
                   data = d, FUN = sum)
}

natural_course_summary <- function(scen) {
  x <- baseline_cells()
  x$Lprev <- x$L0
  x$Lprev2 <- x$L0
  x$Aprev <- 0L
  x$Rprev <- 1L

  pA <- treatment_probability(scen, 0L, x$L0, 0L, 1L, x$B, x$C)
  x <- branch_binary(x, pA, 'A')
  pY <- outcome_probability(scen, 0L, x$L0, x$A, x$B, x$C)
  x$prob <- x$prob * (1 - pY)
  x$Aprev <- x$A
  x$Rprev <- 1L
  x$A <- NULL
  x <- aggregate_natural_state(x)

  obs_num <- 0
  obs_den <- 0
  sev12_num <- NA_real_
  sev12_den <- NA_real_

  for (t in 1:23) {
    pL <- transition_probability(scen, t, x$Lprev, x$Lprev2,
                                 x$B, x$C, x$Aprev)
    old_l <- x$Lprev
    x <- branch_binary(x, pL, 'L')
    old_l <- rep(old_l, each = 2L)
    if (t == 12L) {
      sev12_num <- sum(x$prob * x$L)
      sev12_den <- sum(x$prob)
    }
    pR <- observation_probability(scen, t, x$L, x$Aprev, x$Rprev, x$C)
    obs_num <- obs_num + sum(x$prob * pR)
    obs_den <- obs_den + sum(x$prob)
    x <- branch_binary(x, pR, 'R')
    pA <- treatment_probability(scen, t, x$L, x$Aprev, x$R, x$B, x$C)
    x <- branch_binary(x, pA, 'A')
    pY <- outcome_probability(scen, t, x$L, x$A, x$B, x$C)
    x$prob <- x$prob * (1 - pY)
    x$Lprev2 <- old_l[rep(seq_along(old_l), each = 4L)]
    x$Lprev <- x$L
    x$Aprev <- x$A
    x$Rprev <- x$R
    x$L <- x$R <- x$A <- NULL
    x <- aggregate_natural_state(x)
  }
  list(severity12 = sev12_num / sev12_den, observation_rate = obs_num / obs_den)
}

.calibration_cache <- new.env(parent = emptyenv())

prepare_scenario <- function(scen) {
  key <- as.character(scen$sid)
  if (!is.null(.calibration_cache[[key]])) return(.calibration_cache[[key]])
  s <- scen

  if (is.na(s$alpha_fixed)) {
    alpha_for <- function(kappa) {
      s$kappa <- kappa
      f <- function(alpha) {
        s$alpha <- alpha
        natural_course_summary(s)$observation_rate - s$obs_target
      }
      stats::uniroot(f, c(-12, 4), tol = 1e-10)$root
    }
    f_kappa <- function(kappa) {
      s$kappa <- kappa
      s$alpha <- alpha_for(kappa)
      natural_course_summary(s)$severity12 - 0.25
    }
    s$kappa <- stats::uniroot(f_kappa, c(-10, 4), tol = 1e-10)$root
    s$alpha <- alpha_for(s$kappa)
  } else {
    s$alpha <- s$alpha_fixed
    f_kappa <- function(kappa) {
      s$kappa <- kappa
      natural_course_summary(s)$severity12 - 0.25
    }
    s$kappa <- stats::uniroot(f_kappa, c(-10, 4), tol = 1e-10)$root
  }
  check <- natural_course_summary(s)
  s$calibrated_severity12 <- check$severity12
  s$calibrated_observation_rate <- check$observation_rate
  ## Critique fix: calibrated scenarios solve the transition intercept and the
  ## observation intercept together. This holds both month-12 severity and the
  ## marginal event-free observation frequency at their specified targets.
  .calibration_cache[[key]] <- s
  s
}

mechanism_intervention_risks <- function(scen, strategy) {
  x <- baseline_cells()
  x$Lprev <- x$L0
  x$Lprev2 <- x$L0
  pY <- outcome_probability(scen, 0L, x$L0, strategy, x$B, x$C)
  x$prob <- x$prob * (1 - pY)
  risk <- numeric(N_MONTHS)
  risk[1] <- 1 - sum(x$prob)

  for (t in 1:23) {
    pL <- transition_probability(scen, t, x$Lprev, x$Lprev2,
                                 x$B, x$C, strategy)
    old_l <- x$Lprev
    x <- branch_binary(x, pL, 'L')
    old_l <- rep(old_l, each = 2L)
    pY <- outcome_probability(scen, t, x$L, strategy, x$B, x$C)
    x$prob <- x$prob * (1 - pY)
    x$Lprev2 <- old_l
    x$Lprev <- x$L
    x$L <- NULL
    x <- stats::aggregate(prob ~ B + F + C + L0 + Lprev + Lprev2,
                          data = x, FUN = sum)
    risk[t + 1L] <- 1 - sum(x$prob)
  }
  risk
}

truth_from_mechanism <- function(scen) {
  r1 <- mechanism_intervention_risks(scen, 1L)
  r0 <- mechanism_intervention_risks(scen, 0L)
  data.frame(
    estimand = c('rd12', 'rd24', 'log_rr24'),
    truth = c(r1[12] - r0[12], r1[24] - r0[24], log(r1[24] / r0[24])),
    risk1 = c(r1[12], r1[24], r1[24]),
    risk0 = c(r0[12], r0[24], r0[24]),
    stringsAsFactors = FALSE
  )
}

gen_replicate <- function(scen, n = N_PEOPLE) {
  Tn <- N_MONTHS
  B <- as.integer(stats::runif(n) < 0.45)
  F <- as.integer(stats::runif(n) < 0.52)
  C <- as.integer(stats::runif(n) < expit(-2 + 0.80 * B + 0.30 * F))
  L0 <- as.integer(stats::runif(n) < expit(-1.20 + 0.55 * B + 0.80 * C - 0.15 * F))

  ## All uniforms are allocated before the monthly recursion. Calls therefore
  ## consume the same stream in matched gamma_L scenarios even when histories
  ## and event times diverge. The driver assigns one harness stream per CRN
  ## group. No replicate calls set.seed.
  uL <- matrix(stats::runif(n * Tn), nrow = n)
  uR <- matrix(stats::runif(n * Tn), nrow = n)
  uA <- matrix(stats::runif(n * Tn), nrow = n)
  uY <- matrix(stats::runif(n * Tn), nrow = n)

  L <- R <- A <- Y <- risk <- matrix(NA_integer_, n, Tn)
  last_pre <- gap_pre <- last_after <- gap_after <- matrix(NA_real_, n, Tn)
  alive <- rep(TRUE, n)

  for (j in seq_len(Tn)) {
    t <- j - 1L
    risk[, j] <- as.integer(alive)
    if (t == 0L) {
      L[, j] <- L0
      R[, j] <- 1L
      last_pre[, j] <- L0
      gap_pre[, j] <- 0
      last_after[, j] <- L0
      gap_after[, j] <- 0
      Aprev <- 0L
      Rprev <- 1L
    } else {
      Lprev <- L[, j - 1L]
      Lprev2 <- if (t >= 2L) L[, j - 2L] else L0
      Aprev <- A[, j - 1L]
      Rprev <- R[, j - 1L]
      pL <- transition_probability(scen, t, Lprev, Lprev2, B, C, Aprev)
      L[, j] <- as.integer(uL[, j] < pL)
      last_pre[, j] <- last_after[, j - 1L]
      gap_pre[, j] <- pmin(12, gap_after[, j - 1L] + 1)
      pR <- observation_probability(scen, t, L[, j], Aprev, Rprev, C)
      R[, j] <- as.integer(uR[, j] < pR)
      last_after[, j] <- ifelse(R[, j] == 1L, L[, j], last_pre[, j])
      gap_after[, j] <- ifelse(R[, j] == 1L, 0, gap_pre[, j])
    }
    pA <- treatment_probability(scen, t, L[, j], Aprev, R[, j], B, C)
    A[, j] <- as.integer(uA[, j] < pA)
    pY <- outcome_probability(scen, t, L[, j], A[, j], B, C)
    Y[, j] <- as.integer(alive & uY[, j] < pY)
    alive <- alive & Y[, j] == 0L
  }

  Lobs <- L
  Lobs[R != 1L] <- NA_integer_
  Llocf <- last_after

  pieces <- vector('list', Tn)
  for (j in seq_len(Tn)) {
    keep <- risk[, j] == 1L
    t <- j - 1L
    pieces[[j]] <- data.table::data.table(
      id = which(keep), t = t, B = B[keep], F = F[keep], C = C[keep],
      L0 = L0[keep], Ltrue = L[keep, j], Lobs = Lobs[keep, j],
      Llocf = Llocf[keep, j], R = R[keep, j], A = A[keep, j], y = Y[keep, j],
      Lprev = if (t == 0L) L0[keep] else L[keep, j - 1L],
      Lprev2 = if (t < 2L) L0[keep] else L[keep, j - 2L],
      Llocf_prev = if (t == 0L) L0[keep] else Llocf[keep, j - 1L],
      Llocf_prev2 = if (t < 2L) L0[keep] else Llocf[keep, j - 2L],
      Rprev = if (t == 0L) 1L else R[keep, j - 1L],
      Aprev = if (t == 0L) 0L else A[keep, j - 1L],
      lastL_pre = last_pre[keep, j], gap_pre = gap_pre[keep, j],
      gap = gap_after[keep, j], time = t / 24, time2 = (t / 24)^2,
      sin_time = sin(pi * t / 24)
    )
  }
  long <- data.table::rbindlist(pieces)
  data.table::setorder(long, id, t)
  long[, rowid := .I]

  wide <- list(B = B, F = F, C = C, L0 = L0, L = L, Lobs = Lobs,
               R = R, A = A, Y = Y, risk = risk,
               last_pre = last_pre, gap_pre = gap_pre)
  list(long = long, wide = wide, n = n,
       max_gap = max(gap_pre[risk == 1L], na.rm = TRUE))
}

simulate_strategy <- function(scen, strategy, n = TRUTH_CHECK_N,
                              chunk = TRUTH_CHECK_CHUNK) {
  events12 <- events24 <- done <- 0L
  while (done < n) {
    m <- min(chunk, n - done)
    B <- as.integer(stats::runif(m) < 0.45)
    F <- as.integer(stats::runif(m) < 0.52)
    C <- as.integer(stats::runif(m) < expit(-2 + 0.80 * B + 0.30 * F))
    L0 <- as.integer(stats::runif(m) < expit(-1.20 + 0.55 * B + 0.80 * C - 0.15 * F))
    Lprev <- Lprev2 <- L0
    alive <- rep(TRUE, m)
    event_month <- rep(NA_integer_, m)
    for (t in 0:23) {
      if (t == 0L) {
        L <- L0
      } else {
        pL <- transition_probability(scen, t, Lprev, Lprev2, B, C, strategy)
        L <- as.integer(stats::runif(m) < pL)
      }
      pY <- outcome_probability(scen, t, L, strategy, B, C)
      hit <- alive & stats::runif(m) < pY
      event_month[hit] <- t + 1L
      alive[hit] <- FALSE
      Lprev2 <- Lprev
      Lprev <- L
    }
    events12 <- events12 + sum(!is.na(event_month) & event_month <= 12L)
    events24 <- events24 + sum(!is.na(event_month) & event_month <= 24L)
    done <- done + m
  }
  c(risk12 = events12 / n, risk24 = events24 / n)
}
