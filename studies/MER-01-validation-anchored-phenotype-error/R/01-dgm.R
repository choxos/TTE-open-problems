## Study 2 (MER-01): data-generating mechanism.

expit <- function(x) stats::plogis(x)

error_probabilities <- function(accuracy, differential) {
  if (accuracy >= 1) return(c(low = 0, high = 0))
  if (!differential) return(c(low = 1 - accuracy, high = 1 - accuracy))
  key <- sprintf("%.2f", accuracy)
  switch(
    key,
    "0.70" = c(low = 0.1627, high = 0.4373),
    "0.85" = c(low = 0.0696, high = 0.2304),
    "0.99" = c(low = 0.0040, high = 0.0160),
    stop("unsupported accuracy: ", accuracy)
  )
}

individual_error_probability <- function(scen, X2, X3) {
  pp <- error_probabilities(scen$accuracy, scen$differential_error)
  high <- switch(
    scen$profile,
    aligned = X2 == 1L,
    reversed = X2 == 0L,
    unrelated = X3 == 1L,
    no_effect_modification = X2 == 1L,
    nondifferential = rep(FALSE, length(X2)),
    stop("unknown profile: ", scen$profile)
  )
  if (scen$profile == "nondifferential") rep(pp[["low"]], length(X2)) else
    ifelse(high, pp[["high"]], pp[["low"])
}

gen_error_process <- function(p_fresh, second_order = FALSE,
                              n_months = N_MONTHS) {
  n <- length(p_fresh)
  E <- matrix(0L, nrow = n, ncol = n_months)
  E[, 1L] <- stats::rbinom(n, 1L, p_fresh)
  if (n_months >= 2L) {
    redraw <- stats::runif(n) >= 0.80
    E[, 2L] <- ifelse(redraw, stats::rbinom(n, 1L, p_fresh), E[, 1L])
  }
  if (n_months >= 3L) {
    for (tt in 3L:n_months) {
      u <- stats::runif(n)
      fresh <- stats::rbinom(n, 1L, p_fresh)
      E[, tt] <- if (second_order) {
        ifelse(u < 0.55, E[, tt - 1L],
               ifelse(u < 0.80, E[, tt - 2L], fresh))
      } else {
        ifelse(u < 0.80, E[, tt - 1L], fresh)
      }
    }
  }
  storage.mode(E) <- "integer"
  E
}

latent_predictor_L <- function(t_index, L_prev, A_prev, X1, X2, specification) {
  tt <- t_index - 1L
  eta <- -0.80 + 1.40 * L_prev - 0.50 * A_prev +
    0.35 * X1 + 0.30 * X2 + 0.03 * tt
  if (specification == "confounder") {
    eta <- eta + 0.60 * L_prev * X2 - 0.50 * (X1 < -0.5)
  }
  eta
}

latent_predictor_A <- function(t_index, A_prev, L_now, X1, X2, specification) {
  tt <- t_index - 1L
  eta <- -1.40 + 2.00 * A_prev + 0.90 * L_now +
    0.25 * X1 + 0.20 * X2 + 0.02 * tt
  if (specification == "treatment") {
    eta <- eta + 0.60 * A_prev * L_now + 0.50 * (X1 > 0.5)
  }
  eta
}

outcome_probability <- function(X1, X2, L11, A11, effect_modification,
                                specification) {
  eta <- -2.00 + 0.40 * X1 + 0.30 * X2 + 0.90 * L11
  if (effect_modification) {
    eta <- eta - 0.60 * A11 - 0.40 * A11 * X2
  } else {
    eta <- eta - 0.80 * A11
  }
  if (specification == "outcome") {
    eta <- eta - 0.60 * A11 * (X1 > 0.5)
  }
  expit(eta)
}

gen_latent_cohort <- function(scen, n = N_PER_REP) {
  X1 <- stats::rnorm(n)
  X2 <- stats::rbinom(n, 1L, 0.5)
  X3 <- stats::rbinom(n, 1L, 0.5)
  L <- matrix(0L, nrow = n, ncol = N_MONTHS)
  A <- matrix(0L, nrow = n, ncol = N_MONTHS)

  L[, 1L] <- stats::rbinom(n, 1L, expit(-0.40 + 0.50 * X1 + 0.40 * X2))
  A[, 1L] <- stats::rbinom(
    n, 1L, expit(-0.70 + 0.80 * L[, 1L] + 0.25 * X1 + 0.20 * X2))
  for (tt in 2L:N_MONTHS) {
    L[, tt] <- stats::rbinom(
      n, 1L, expit(latent_predictor_L(
        tt, L[, tt - 1L], A[, tt - 1L], X1, X2, scen$specification)))
    A[, tt] <- stats::rbinom(
      n, 1L, expit(latent_predictor_A(
        tt, A[, tt - 1L], L[, tt], X1, X2, scen$specification)))
  }
  py <- outcome_probability(X1, X2, L[, N_MONTHS], A[, N_MONTHS],
                            scen$effect_modification, scen$specification)
  Y <- stats::rbinom(n, 1L, py)
  list(X1 = X1, X2 = X2, X3 = X3, L = L, A = A, Y = Y)
}

gen_replicate <- function(scen, n = N_PER_REP) {
  latent <- gen_latent_cohort(scen, n)
  p_error <- individual_error_probability(scen, latent$X2, latent$X3)
  second_order <- scen$specification == "error_transition"
  EA <- gen_error_process(p_error, second_order)
  EL <- gen_error_process(p_error, second_order)
  Astar_all <- (latent$A + EA) %% 2L
  Lstar_all <- (latent$L + EL) %% 2L

  ## Critique fix: outcome error is generated only in the separate component.
  if (isTRUE(scen$outcome_error)) {
    e <- 1 - scen$accuracy
    EY <- stats::rbinom(n, 1L, e)
    Ystar <- (latent$Y + EY) %% 2L
  } else {
    EY <- integer(n)
    Ystar <- latent$Y
  }

  ## One independent ranking defines every nested validation sample.
  validation_rank <- rank(stats::runif(n), ties.method = "first")
  c(latent, list(
    Astar_all = Astar_all,
    Lstar_all = Lstar_all,
    Ystar = as.integer(Ystar),
    EA = EA,
    EL = EL,
    EY = EY,
    p_error = p_error,
    validation_rank = validation_rank
  ))
}

proxy_view <- function(dat, pattern) {
  use_A <- grepl("A", pattern, fixed = TRUE)
  use_L <- grepl("L", pattern, fixed = TRUE)
  list(
    A = if (use_A) dat$Astar_all else dat$A,
    L = if (use_L) dat$Lstar_all else dat$L,
    Y = dat$Ystar
  )
}

validation_index <- function(dat, n_validation) {
  which(dat$validation_rank <= min(n_validation, length(dat$validation_rank)))
}

first_censor_month <- function(A, required) {
  bad <- A != required
  out <- rep.int(N_MONTHS + 1L, nrow(A))
  hit <- rowSums(bad) > 0L
  if (any(hit)) out[hit] <- max.col(bad[hit, , drop = FALSE], ties.method = "first")
  out
}
