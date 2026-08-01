## GMT-04 benchmark: data-generating mechanism and exact truth recursion.

expit <- function(x) 1 / (1 + exp(-x))
bound_probability <- function(x, bounds = PROB_BOUNDS) {
  pmin(bounds[2], pmax(bounds[1], x))
}

is_control <- function(scen, label) {
  !is.null(scen$control) && !is.na(scen$control[1]) && scen$control[1] == label
}

mechanism_values <- function(scen) {
  list(
    c0 = is_control(scen, 'C0'),
    c1 = is_control(scen, 'C1'),
    s = ifelse(is.na(scen$s[1]), 1, scen$s[1]),
    delta_g = scen$delta_g[1],
    delta_q = scen$delta_q[1]
  )
}

treatment_probability <- function(k, W1, W2, U, L, Lprev, Aprev, Aprev2,
                                  mechanism) {
  if (mechanism$c0) {
    if (k == 0L) return(rep(0.50, length(L)))
    return(ifelse(Aprev == 1L, 0.80, 0.20))
  }
  lp <- -0.20 + mechanism$s * (
    1.20 * L + 0.50 * W1 - 0.50 * W2 + 0.70 * U +
      1.10 * Aprev - 0.70
  ) + mechanism$delta_g * (
    1.00 * Lprev * (W2 - 0.35) - 0.80 * Aprev2 * (W1 - 0.50)
  )
  expit(lp)
}

retention_probability <- function(k, W1, W2, U, L, Lprev, A, Aprev, Aprev2,
                                  mechanism) {
  if (mechanism$c0) return(rep(0.98, length(L)))
  p_loss <- expit(
    -4.00 + 0.70 * L + 0.35 * W2 + 0.30 * A + 0.25 * U + 0.12 * k +
      mechanism$delta_g * (
        0.80 * Lprev * (Aprev - 0.50) -
          0.50 * Aprev2 * (W1 - 0.50)
      )
  )
  1 - p_loss
}

transition_probability <- function(k, W1, W2, U, L, Lprev, A, mechanism) {
  treatment_coefficient <- if (mechanism$c0) 0 else -0.75
  expit(
    -0.80 + 1.35 * L + 0.45 * W1 + 0.35 * W2 + 0.55 * U +
      treatment_coefficient * A + 0.15 * k +
      mechanism$delta_q * (
        0.65 * Lprev * (W2 - 0.35) -
          0.45 * Lprev * (L - 0.50)
      )
  )
}

event_probability <- function(k, W1, W2, U, L, Lprev, A, mechanism) {
  direct <- if (mechanism$c0) 0 else -0.45
  modification <- if (mechanism$c0) 0 else -0.30
  expit(
    -4.60 + 0.20 * k + 1.00 * L + 0.55 * W1 + 0.35 * W2 +
      0.75 * U + direct * A + modification * A * W1 +
      mechanism$delta_q * (
        0.70 * Lprev * (W2 - 0.35) -
          0.50 * Lprev * (L - 0.50)
      )
  )
}

gen_replicate <- function(scen, n = N_PER_REPLICATE) {
  mechanism <- mechanism_values(scen)
  W1 <- stats::rbinom(n, 1, 0.50)
  W2 <- stats::rbinom(n, 1, 0.35)
  U <- stats::rbinom(n, 1, 0.30)
  L <- matrix(NA_integer_, nrow = n, ncol = N_VISITS)
  A <- matrix(NA_integer_, nrow = n, ncol = N_VISITS)
  loss <- matrix(0L, nrow = n, ncol = N_VISITS)
  event <- matrix(0L, nrow = n, ncol = N_VISITS)
  alive_start <- matrix(FALSE, nrow = n, ncol = N_VISITS)
  lost_before <- matrix(FALSE, nrow = n, ncol = N_VISITS)

  L[, 1] <- stats::rbinom(
    n, 1, expit(-0.70 + 1.00 * W1 + 0.70 * W2 +
                  0.50 * W1 * W2 + 0.80 * U)
  )
  alive <- rep(TRUE, n)
  lost <- rep(FALSE, n)

  ## The visit loop has six iterations. Every operation within a visit is
  ## vectorized over individuals. Loss does not stop latent trajectory draws.
  for (j in seq_len(N_VISITS)) {
    k <- j - 1L
    alive_start[, j] <- alive
    lost_before[, j] <- lost
    idx <- which(alive)
    if (!length(idx)) next

    Lprev <- if (k == 0L) rep(0L, length(idx)) else L[idx, j - 1L]
    Aprev <- if (k == 0L) rep(0L, length(idx)) else A[idx, j - 1L]
    Aprev2 <- if (k <= 1L) rep(0L, length(idx)) else A[idx, j - 2L]

    pA <- treatment_probability(k, W1[idx], W2[idx], U[idx], L[idx, j],
                                Lprev, Aprev, Aprev2, mechanism)
    A[idx, j] <- stats::rbinom(length(idx), 1, pA)

    loss_idx <- idx[!lost[idx]]
    if (length(loss_idx)) {
      pos <- match(loss_idx, idx)
      pR <- retention_probability(
        k, W1[loss_idx], W2[loss_idx], U[loss_idx], L[loss_idx, j],
        Lprev[pos], A[loss_idx, j], Aprev[pos], Aprev2[pos], mechanism
      )
      loss[loss_idx, j] <- stats::rbinom(length(loss_idx), 1, 1 - pR)
      lost[loss_idx[loss[loss_idx, j] == 1L]] <- TRUE
    }

    pE <- event_probability(k, W1[idx], W2[idx], U[idx], L[idx, j],
                            Lprev, A[idx, j], mechanism)
    event[idx, j] <- stats::rbinom(length(idx), 1, pE)
    alive[idx[event[idx, j] == 1L]] <- FALSE

    if (j < N_VISITS) {
      next_idx <- which(alive)
      if (length(next_idx)) {
        previous_l <- if (k == 0L) rep(0L, length(next_idx)) else L[next_idx, j - 1L]
        pL <- transition_probability(k, W1[next_idx], W2[next_idx], U[next_idx],
                                     L[next_idx, j], previous_l, A[next_idx, j],
                                     mechanism)
        L[next_idx, j + 1L] <- stats::rbinom(length(next_idx), 1, pL)
      }
    }
  }

  list(n = n, W1 = W1, W2 = W2, U = U, L = L, A = A, loss = loss,
       event = event, alive_start = alive_start, lost_before = lost_before,
       mechanism = mechanism)
}

make_observed_long <- function(generated) {
  rows <- vector('list', N_VISITS)
  for (j in seq_len(N_VISITS)) {
    k <- j - 1L
    observed <- generated$alive_start[, j] & !generated$lost_before[, j]
    id <- which(observed)
    retained <- 1L - generated$loss[id, j]
    observed_event <- ifelse(retained == 1L, generated$event[id, j], NA_integer_)
    next_l <- rep(NA_integer_, length(id))
    if (j < N_VISITS) {
      usable <- retained == 1L & observed_event == 0L
      next_l[usable] <- generated$L[id[usable], j + 1L]
    }
    rows[[j]] <- data.frame(
      id = id,
      k = k,
      kfac = factor(k, levels = VISITS),
      W1 = generated$W1[id], W2 = generated$W2[id], U = generated$U[id],
      L = generated$L[id, j],
      Lprev = if (k == 0L) 0L else generated$L[id, j - 1L],
      A = generated$A[id, j],
      Aprev = if (k == 0L) 0L else generated$A[id, j - 1L],
      Aprev2 = if (k <= 1L) 0L else generated$A[id, j - 2L],
      retained = retained,
      event = observed_event,
      Lnext = next_l,
      stringsAsFactors = FALSE
    )
  }
  out <- data.table::rbindlist(rows, use.names = TRUE, fill = TRUE)
  data.table::setorder(out, id, k)
  as.data.frame(out)
}

make_ltmle_wide <- function(generated, observed_u) {
  out <- data.frame(W1 = generated$W1, W2 = generated$W2,
                    stringsAsFactors = FALSE)
  if (observed_u) out$U <- generated$U
  out$L0 <- generated$L[, 1]

  for (j in seq_len(N_VISITS)) {
    k <- j - 1L
    known_start <- generated$alive_start[, j] & !generated$lost_before[, j]
    a <- rep(NA_integer_, generated$n)
    r <- rep(NA_integer_, generated$n)
    s <- rep(NA_integer_, generated$n)
    a[known_start] <- generated$A[known_start, j]
    r[known_start] <- 1L - generated$loss[known_start, j]

    known_event <- known_start & r == 1L
    s[known_event] <- 1L - generated$event[known_event, j]
    prior_event <- !generated$alive_start[, j] & !generated$lost_before[, j]
    s[prior_event] <- 0L

    out[[paste0('A', k)]] <- a
    out[[paste0('R', k)]] <- r
    out[[paste0('S', k + 1L)]] <- s
    if (j < N_VISITS) {
      lnext <- rep(NA_integer_, generated$n)
      next_known <- generated$alive_start[, j + 1L] &
        !generated$lost_before[, j + 1L]
      lnext[next_known] <- generated$L[next_known, j + 1L]
      out[[paste0('L', k + 1L)]] <- lnext
    }
  }
  out
}

truth_mechanism <- function(key) {
  switch(
    key,
    deltaQ0 = list(c0 = FALSE, c1 = FALSE, s = 1, delta_g = 0, delta_q = 0),
    deltaQ1 = list(c0 = FALSE, c1 = FALSE, s = 1, delta_g = 0, delta_q = 1),
    C0 = list(c0 = TRUE, c1 = FALSE, s = 1, delta_g = 0, delta_q = 0),
    C1 = list(c0 = FALSE, c1 = TRUE, s = 1, delta_g = 0, delta_q = 2),
    stop('unknown truth key: ', key)
  )
}

truth_regime_risk <- function(key, regime) {
  mechanism <- truth_mechanism(key)
  state <- expand.grid(W1 = 0:1, W2 = 0:1, U = 0:1, Lprev = 0L,
                       L = 0:1, stringsAsFactors = FALSE)
  pW <- stats::dbinom(state$W1, 1, 0.50) *
    stats::dbinom(state$W2, 1, 0.35) *
    stats::dbinom(state$U, 1, 0.30)
  pL0 <- expit(-0.70 + state$W1 + 0.70 * state$W2 +
                 0.50 * state$W1 * state$W2 + 0.80 * state$U)
  state$mass <- pW * stats::dbinom(state$L, 1, pL0)
  event_mass <- 0

  for (k in VISITS) {
    h <- event_probability(k, state$W1, state$W2, state$U, state$L,
                           state$Lprev, regime, mechanism)
    event_mass <- event_mass + sum(state$mass * h)
    survivor_mass <- state$mass * (1 - h)

    if (k < max(VISITS)) {
      pL <- transition_probability(k, state$W1, state$W2, state$U,
                                   state$L, state$Lprev, regime, mechanism)
      z0 <- data.frame(W1 = state$W1, W2 = state$W2, U = state$U,
                       Lprev = state$L, L = 0L,
                       mass = survivor_mass * (1 - pL))
      z1 <- data.frame(W1 = state$W1, W2 = state$W2, U = state$U,
                       Lprev = state$L, L = 1L,
                       mass = survivor_mass * pL)
      state <- stats::aggregate(
        mass ~ W1 + W2 + U + Lprev + L,
        data = rbind(z0, z1), FUN = sum
      )
    } else {
      state$mass <- survivor_mass
    }
    err <- abs(event_mass + sum(state$mass) - 1)
    if (!is.finite(err) || err > TRUTH_MASS_TOLERANCE) {
      stop(sprintf('truth mass error at k=%d: %.17g', k, err))
    }
  }
  event_mass
}

truth_for_key <- function(key) {
  risk0 <- truth_regime_risk(key, 0L)
  risk1 <- truth_regime_risk(key, 1L)
  data.frame(truth_key = key, risk0 = risk0, risk1 = risk1,
             rd = risk1 - risk0, mass_tolerance = TRUTH_MASS_TOLERANCE,
             stringsAsFactors = FALSE)
}

simulate_intervention_pair <- function(key, n = TRUTH_VALIDATION_N,
                                       chunk = TRUTH_VALIDATION_CHUNK) {
  mechanism <- truth_mechanism(key)
  sum0 <- 0; sum1 <- 0; sumd <- 0; sumd2 <- 0; done <- 0L
  while (done < n) {
    m <- min(chunk, n - done)
    W1 <- stats::rbinom(m, 1, 0.50)
    W2 <- stats::rbinom(m, 1, 0.35)
    U <- stats::rbinom(m, 1, 0.30)
    u0 <- stats::runif(m)
    pL0 <- expit(-0.70 + W1 + 0.70 * W2 + 0.50 * W1 * W2 + 0.80 * U)
    L0 <- as.integer(u0 < pL0)
    L <- list(L0, L0)
    Lprev <- list(integer(m), integer(m))
    alive <- list(rep(TRUE, m), rep(TRUE, m))
    y <- list(integer(m), integer(m))

    for (k in VISITS) {
      uE <- stats::runif(m)
      uL <- if (k < max(VISITS)) stats::runif(m) else NULL
      for (a in 0:1) {
        z <- a + 1L
        idx <- which(alive[[z]])
        if (length(idx)) {
          h <- event_probability(k, W1[idx], W2[idx], U[idx], L[[z]][idx],
                                 Lprev[[z]][idx], a, mechanism)
          hit <- idx[uE[idx] < h]
          if (length(hit)) {
            y[[z]][hit] <- 1L
            alive[[z]][hit] <- FALSE
          }
        }
        if (k < max(VISITS)) {
          idx <- which(alive[[z]])
          old_l <- L[[z]]
          if (length(idx)) {
            pL <- transition_probability(k, W1[idx], W2[idx], U[idx],
                                         old_l[idx], Lprev[[z]][idx], a,
                                         mechanism)
            L[[z]][idx] <- as.integer(uL[idx] < pL)
          }
          Lprev[[z]] <- old_l
        }
      }
    }
    d <- y[[2]] - y[[1]]
    sum0 <- sum0 + sum(y[[1]])
    sum1 <- sum1 + sum(y[[2]])
    sumd <- sumd + sum(d)
    sumd2 <- sumd2 + sum(d * d)
    done <- done + m
  }
  p0 <- sum0 / n; p1 <- sum1 / n; rd <- sumd / n
  var_d <- if (n > 1L) (sumd2 - sumd * sumd / n) / (n - 1L) else NA_real_
  data.frame(
    truth_key = key,
    sim_risk0 = p0,
    sim_risk1 = p1,
    sim_rd = rd,
    sim_mcse_risk0 = sqrt(p0 * (1 - p0) / n),
    sim_mcse_risk1 = sqrt(p1 * (1 - p1) / n),
    sim_mcse_rd = sqrt(max(0, var_d) / n),
    validation_n = n,
    stringsAsFactors = FALSE
  )
}
