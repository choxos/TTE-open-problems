## GMT-01: longitudinal data-generating mechanism and enumerated truth.

expit <- stats::plogis

scenario_value <- function(scen, name) unname(scen[[name]][1])

linear_treatment_predictor <- function(t, W1, W2, W3, L, previous_A,
                                       Z, scen) {
  base <- 0.40 * W1 + 0.25 * W2 + 0.50 * W3 + 0.75 * L
  if (t > 0L) base <- base - 0.25 * previous_A
  nonlinear <- scenario_value(scen, "I_G") *
    (0.45 * (L^2 - 1) + 0.35 * W1 * L)
  ## Critique fix: gamma_Z is outside the s multiplier, so its conditional odds
  ## ratio is 2.12 or 4.48 at both propensity-separation levels.
  -0.20 + 0.15 * t + scenario_value(scen, "s") * (base + nonlinear) +
    scenario_value(scen, "gamma_z") * Z
}

linear_retention_predictor <- function(t, W1, W3, L, A, scen) {
  2.80 - 0.20 * t - 0.25 * W1 - 0.35 * W3 - 0.45 * L + 0.15 * A +
    scenario_value(scen, "I_C") *
    (-0.40 * (L^2 - 1) + 0.30 * W1 * L)
}

gen_replicate <- function(scen, n = N_PERSON, regime = NULL,
                          eliminate_censoring = FALSE, observed = TRUE) {
  W1 <- stats::rnorm(n)
  W2 <- stats::rbinom(n, 1, 0.5)
  W3 <- stats::rbinom(n, 1, expit(-0.4 + 0.5 * W1 + 0.4 * W2))

  Z0 <- stats::rnorm(n)
  Z1 <- 0.60 * Z0 + 0.80 * stats::rnorm(n)
  Z2 <- 0.60 * Z1 + 0.80 * stats::rnorm(n)

  L0 <- 0.40 * W1 + 0.50 * W3 + stats::rnorm(n, sd = 0.8)
  pA0 <- expit(linear_treatment_predictor(0L, W1, W2, W3, L0,
                                           NULL, Z0, scen))
  A0 <- if (is.null(regime)) stats::rbinom(n, 1, pA0) else rep(regime, n)
  pR0 <- expit(linear_retention_predictor(0L, W1, W3, L0, A0, scen))
  R1 <- if (eliminate_censoring) rep(1L, n) else stats::rbinom(n, 1, pR0)

  L1 <- 0.45 * L0 + 0.25 * W1 + 0.35 * W3 - 0.35 * A0 + 0.15 +
    stats::rnorm(n, sd = 0.8)
  pA1 <- expit(linear_treatment_predictor(1L, W1, W2, W3, L1,
                                           A0, Z1, scen))
  A1 <- if (is.null(regime)) stats::rbinom(n, 1, pA1) else rep(regime, n)
  pR1 <- expit(linear_retention_predictor(1L, W1, W3, L1, A1, scen))
  R2 <- if (eliminate_censoring) rep(1L, n) else
    R1 * stats::rbinom(n, 1, pR1)

  L2 <- 0.45 * L1 + 0.25 * W1 + 0.35 * W3 - 0.35 * A1 + 0.30 +
    stats::rnorm(n, sd = 0.8)
  pA2 <- expit(linear_treatment_predictor(2L, W1, W2, W3, L2,
                                           A1, Z2, scen))
  A2 <- if (is.null(regime)) stats::rbinom(n, 1, pA2) else rep(regime, n)
  pR2 <- expit(linear_retention_predictor(2L, W1, W3, L2, A2, scen))
  R3 <- if (eliminate_censoring) rep(1L, n) else
    R2 * stats::rbinom(n, 1, pR2)

  mu_Y <- 0.25 * W1 + 0.20 * W2 + 0.45 * W3 +
    0.15 * L0 + 0.25 * L1 + 0.35 * L2 +
    (-0.12 - 0.08 * W3) * (A0 + A1 + A2) +
    scenario_value(scen, "I_Q") *
    (0.30 * (L2^2 - 1) + 0.25 * W1 * L2)
  Y <- mu_Y + stats::rnorm(n)

  out <- data.frame(
    id = seq_len(n), W1, W2, W3, Z0, Z1, Z2, L0, L1, L2,
    A0, A1, A2, R0 = 1L, R1, R2, R3, Y, mu_Y,
    pA0_true = pA0, pA1_true = pA1, pA2_true = pA2,
    pR0_true = pR0, pR1_true = pR1, pR2_true = pR2
  )

  if (observed) {
    gone1 <- out$R1 == 0L
    gone2 <- out$R2 == 0L
    gone3 <- out$R3 == 0L
    out[gone1, c("Z1", "L1", "A1", "pA1_true", "pR1_true")] <- NA
    out[gone2, c("Z2", "L2", "A2", "pA2_true", "pR2_true")] <- NA
    out$Y[gone3] <- NA
    out$mu_Y[gone3] <- NA
  }
  out
}

truth_block <- function(scen, n) {
  W1 <- stats::rnorm(n)
  W2 <- stats::rbinom(n, 1, 0.5)
  W3 <- stats::rbinom(n, 1, expit(-0.4 + 0.5 * W1 + 0.4 * W2))
  Z0 <- stats::rnorm(n)
  Z1 <- 0.60 * Z0 + 0.80 * stats::rnorm(n)
  Z2 <- 0.60 * Z1 + 0.80 * stats::rnorm(n)
  invisible(Z2)

  e0 <- stats::rnorm(n, sd = 0.8)
  e1 <- stats::rnorm(n, sd = 0.8)
  e2 <- stats::rnorm(n, sd = 0.8)
  L0 <- 0.40 * W1 + 0.50 * W3 + e0

  make_mu <- function(a) {
    L1 <- 0.45 * L0 + 0.25 * W1 + 0.35 * W3 - 0.35 * a + 0.15 + e1
    L2 <- 0.45 * L1 + 0.25 * W1 + 0.35 * W3 - 0.35 * a + 0.30 + e2
    0.25 * W1 + 0.20 * W2 + 0.45 * W3 + 0.15 * L0 +
      0.25 * L1 + 0.35 * L2 + 3 * (-0.12 - 0.08 * W3) * a +
      scenario_value(scen, "I_Q") *
      (0.30 * (L2^2 - 1) + 0.25 * W1 * L2)
  }
  mu1 <- make_mu(1)
  mu0 <- make_mu(0)
  cbind(mu1 = mu1, mu0 = mu0, difference = mu1 - mu0)
}

truth_for <- function(scen, block = N_TRUTH_BLOCK,
                      mcse_max = TRUTH_MCSE_MAX) {
  sums <- setNames(numeric(3), c("mu1", "mu0", "difference"))
  sums2 <- sums
  n <- 0L
  repeat {
    x <- truth_block(scen, block)
    sums <- sums + colSums(x)
    sums2 <- sums2 + colSums(x^2)
    n <- n + block
    means <- sums / n
    vars <- pmax((sums2 - n * means^2) / (n - 1), 0)
    ses <- sqrt(vars / n)
    if (ses[["difference"]] <= mcse_max) break
  }
  data.frame(
    truth_mean1 = means[["mu1"]], truth_mean0 = means[["mu0"]],
    truth = means[["difference"]], truth_mcse = ses[["difference"]],
    truth_mean1_mcse = ses[["mu1"]], truth_mean0_mcse = ses[["mu0"]],
    marginal_sd1 = sqrt(vars[["mu1"]] + 1),
    marginal_sd0 = sqrt(vars[["mu0"]] + 1), truth_n = n
  )
}

weighted_ess <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w) || sum(w^2) == 0) return(0)
  sum(w)^2 / sum(w^2)
}

true_regime_weight <- function(dat, a) {
  w <- rep(1, nrow(dat))
  for (t in 0:2) {
    at <- dat[[paste0("A", t)]]
    rn <- dat[[paste0("R", t + 1L)]]
    pg <- dat[[paste0("pA", t, "_true")]]
    pc <- dat[[paste0("pR", t, "_true")]]
    den_g <- if (a == 1L) pg else 1 - pg
    w <- w * as.integer(at == a & rn == 1L) /
      (pmax(den_g, PROB_FLOOR) * pmax(pc, PROB_FLOOR))
    w[!is.finite(w)] <- 0
  }
  w
}

dgm_population_check <- function(scen, n = N_DGM_CHECK) {
  d <- gen_replicate(scen, n = n, observed = FALSE)
  qfun <- function(x) stats::quantile(x, c(0.001, 0.01, 0.5, 0.99, 0.999),
                                      na.rm = TRUE, names = FALSE)
  out <- list()
  for (t in 0:2) {
    risk <- d[[paste0("R", t)]] == 1L
    qa <- qfun(d[[paste0("pA", t, "_true")]][risk])
    qr <- qfun(d[[paste0("pR", t, "_true")]][risk])
    out[[paste0("treat_prev_t", t)]] <- mean(d[[paste0("A", t)]][risk])
    for (j in seq_along(qa)) out[[paste0("pA_t", t, "_q", j)]] <- qa[j]
    for (j in seq_along(qr)) out[[paste0("pR_t", t, "_q", j)]] <- qr[j]
  }
  out$retention_12 <- mean(d$R1)
  out$retention_24 <- mean(d$R2)
  out$retention_36 <- mean(d$R3)
  out$true_ess_a0 <- weighted_ess(true_regime_weight(d, 0L))
  out$true_ess_a1 <- weighted_ess(true_regime_weight(d, 1L))
  as.data.frame(out, check.names = FALSE)
}
