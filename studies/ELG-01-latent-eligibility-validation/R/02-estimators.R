## ELG-01: enumerated truth and estimators.

`%||%` <- function(x, y) if (is.null(x)) y else x

failure_result <- function(why) {
  list(est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
       pe_est = NA_real_, ne_est = NA_real_, pe_se = NA_real_,
       within_var = NA_real_, between_var = NA_real_, df = NA_real_,
       ess0 = NA_real_, ess1 = NA_real_, max_weight = NA_real_,
       bound_lo = NA_real_, bound_hi = NA_real_, bound_ci_lo = NA_real_,
       bound_ci_hi = NA_real_, bound_se_lo = NA_real_, bound_se_hi = NA_real_,
       pe_lower = NA_real_, pe_upper = NA_real_, fail = as.character(why))
}

truth_for <- function(scen, n = N_TRUTH, chunk = 250000L) {
  sum_v <- numeric(4L)
  cross_v <- matrix(0, 4L, 4L)
  done <- 0L
  while (done < n) {
    k <- min(chunk, n - done)
    x <- truth_covariates(k)
    r <- expit(scen$alpha_m + 0.50 * x$Z + 0.80 * x$C +
               0.70 * x$I - 0.60 * x$H)
    eta <- 0.85 - 0.65 * x$Z - scen$kappa * x$C +
      0.25 * x$S + 0.50 * x$H
    e1 <- expit(eta)
    e0 <- expit(eta + scen$lambda)
    w <- r * e1 + (1 - r) * e0
    w_re <- r * e1
    v <- cbind(w, x$C * w, w_re, x$C * w_re)
    sum_v <- sum_v + colSums(v)
    cross_v <- cross_v + crossprod(v)
    done <- done + k
  }
  mean_v <- sum_v / n
  cov_i <- (cross_v - n * tcrossprod(mean_v)) / (n - 1)
  pe <- mean_v[1L]
  pc <- mean_v[2L] / pe
  pre <- mean_v[3L]
  pc_re <- mean_v[4L] / pre

  if (scen$effect == 'homogeneous') {
    rd_e <- rd_re <- -0.06
    rd_e_mcse <- rd_re_mcse <- 0
  } else {
    rd_e <- -0.04 - 0.08 * pc
    rd_re <- -0.04 - 0.08 * pc_re
    g_e <- -0.08 * c(-mean_v[2L] / pe^2, 1 / pe)
    g_re <- -0.08 * c(-mean_v[4L] / pre^2, 1 / pre)
    rd_e_mcse <- sqrt(max(0, drop(t(g_e) %*% cov_i[1:2, 1:2] %*% g_e) / n))
    rd_re_mcse <- sqrt(max(0, drop(t(g_re) %*% cov_i[3:4, 3:4] %*% g_re) / n))
  }
  data.frame(
    pe = pe,
    pe_mcse = sqrt(max(0, cov_i[1L, 1L] / n)),
    pc_eligible = pc,
    rd_e = rd_e,
    rd_e_mcse = rd_e_mcse,
    recorded_eligible_prevalence = pre,
    pc_recorded_eligible = pc_re,
    rd_re = rd_re,
    rd_re_mcse = rd_re_mcse,
    target_discrepancy = rd_re - rd_e,
    truth_n = n,
    stringsAsFactors = FALSE
  )
}

truth_identification <- function(alpha_m, n = N_TRUTH, chunk = 250000L) {
  sum_v <- numeric(4L)
  cross_v <- matrix(0, 4L, 4L)
  done <- 0L
  while (done < n) {
    k <- min(chunk, n - done)
    x <- truth_covariates(k)
    r <- expit(alpha_m + 0.50 * x$Z + 0.80 * x$C +
               0.70 * x$I - 0.60 * x$H)
    eta <- 0.85 - 0.65 * x$Z - 1.10 * x$C +
      0.25 * x$S + 0.50 * x$H
    w0 <- r * expit(eta) + (1 - r) * expit(eta)
    w4 <- r * expit(eta) + (1 - r) * expit(eta + log(4))
    v <- cbind(w0, x$C * w0, w4, x$C * w4)
    sum_v <- sum_v + colSums(v)
    cross_v <- cross_v + crossprod(v)
    done <- done + k
  }
  mv <- sum_v / n
  cv <- (cross_v - n * tcrossprod(mv)) / (n - 1)
  pc0 <- mv[2L] / mv[1L]
  pc4 <- mv[4L] / mv[3L]
  rd0 <- -0.04 - 0.08 * pc0
  rd4 <- -0.04 - 0.08 * pc4
  delta <- rd4 - rd0
  grad <- c(
    -0.08 * mv[2L] / mv[1L]^2,
     0.08 / mv[1L],
     0.08 * mv[4L] / mv[3L]^2,
    -0.08 / mv[3L]
  )
  mcse <- sqrt(max(0, drop(t(grad) %*% cv %*% grad) / n))
  data.frame(
    m = 0.50, kappa = 1.10, effect = 'heterogeneous',
    lambda_low = 0, lambda_high = log(4),
    rd_low = rd0, rd_high = rd4, delta_id = delta,
    mcse = mcse,
    ci95_lo = delta - stats::qnorm(0.975) * mcse,
    ci95_hi = delta + stats::qnorm(0.975) * mcse,
    ci90_lo = delta - stats::qnorm(0.950) * mcse,
    ci90_hi = delta + stats::qnorm(0.950) * mcse,
    truth_n = n,
    stringsAsFactors = FALSE
  )
}

safe_logit <- function(X, y, weights = NULL, coefficient_limit = 20) {
  X <- unname(as.matrix(X))
  storage.mode(X) <- 'double'
  y <- as.numeric(y)
  if (is.null(weights)) weights <- rep(1, length(y))
  fit <- try(suppressWarnings(stats::glm.fit(
    x = X, y = y, weights = weights, family = stats::binomial()
  )), silent = TRUE)
  if (inherits(fit, 'try-error') || !isTRUE(fit$converged) ||
      fit$rank < ncol(X) || any(!is.finite(fit$coefficients)) ||
      any(abs(fit$coefficients) > coefficient_limit)) {
    return(list(fail = 'logit-failed-or-separated'))
  }
  q <- expit(drop(X %*% fit$coefficients))
  if (any(!is.finite(q))) return(list(fail = 'nonfinite-logit-probability'))
  info <- crossprod(X, X * (weights * q * (1 - q)))
  vc <- try(solve(info), silent = TRUE)
  if (inherits(vc, 'try-error') || any(!is.finite(vc))) {
    return(list(fail = 'singular-logit-covariance'))
  }
  list(coef = fit$coefficients, vcov = (vc + t(vc)) / 2,
       X = X, q = q, y = y, weights = weights, fail = NA_character_)
}

extend_logit <- function(fit, X) {
  if (!is.na(fit$fail[1L])) return(fit)
  fit$X <- unname(as.matrix(X))
  fit$q <- expit(drop(fit$X %*% fit$coef))
  fit
}

safe_ols <- function(X, y) {
  X <- unname(as.matrix(X))
  storage.mode(X) <- 'double'
  fit <- try(stats::lm.fit(X, y), silent = TRUE)
  if (inherits(fit, 'try-error') || fit$rank < ncol(X) ||
      any(!is.finite(fit$coefficients))) return(list(fail = 'laboratory-model-rank-failure'))
  df <- nrow(X) - ncol(X)
  if (df <= 0) return(list(fail = 'laboratory-model-no-residual-df'))
  residuals <- as.numeric(fit$residuals - mean(fit$residuals))
  sigma2 <- sum(residuals^2) / df
  vc <- try(sigma2 * solve(crossprod(X)), silent = TRUE)
  if (inherits(vc, 'try-error') || any(!is.finite(vc))) {
    return(list(fail = 'laboratory-model-covariance-failure'))
  }
  ev <- eigen((vc + t(vc)) / 2, symmetric = TRUE, only.values = TRUE)$values
  if (min(ev) < -1e-10 * max(1, max(abs(ev)))) {
    return(list(fail = 'laboratory-model-covariance-not-psd'))
  }
  list(coef = fit$coefficients, vcov = (vc + t(vc)) / 2,
       residuals = residuals, fail = NA_character_)
}

draw_mvn <- function(mu, V) {
  ev <- eigen((V + t(V)) / 2, symmetric = TRUE)
  tol <- 1e-10 * max(1, max(abs(ev$values)))
  if (min(ev$values) < -tol) return(NULL)
  drop(mu + ev$vectors %*% (sqrt(pmax(ev$values, 0)) * stats::rnorm(length(mu))))
}

treatment_matrix <- function(dat) {
  cbind('(Intercept)' = 1, Z = dat$Z, S = dat$S, C = dat$C,
        H = dat$H, I = dat$I)
}

eligibility_matrix <- function(dat, type = 'recorded') {
  R0 <- 1 - dat$R
  switch(
    type,
    recorded = cbind('(Intercept)' = 1, Z = dat$Z, S = dat$S, C = dat$C,
                     H = dat$H, I = dat$I),
    validation_primary = cbind('(Intercept)' = 1, Z = dat$Z, S = dat$S,
                               C = dat$C, H = dat$H, I = dat$I, R0 = R0),
    validation_omit_ch = cbind('(Intercept)' = 1, Z = dat$Z, S = dat$S,
                               I = dat$I, R0 = R0),
    intercept_r = cbind('(Intercept)' = 1, R0 = R0),
    stop('unknown eligibility matrix type')
  )
}

recording_matrix <- function(dat) {
  stats::model.matrix(
    ~ splines::ns(Z, df = 4) * (S + C + H + I) + (S + C + H + I)^2,
    data = dat
  )
}

fit_treatment <- function(dat) {
  X <- treatment_matrix(dat)
  fit <- safe_logit(X, dat$A)
  if (!is.na(fit$fail[1L])) return(fit)
  if (any(fit$q < 1e-8 | 1 - fit$q < 1e-8)) {
    return(list(fail = 'treatment-positivity-failure'))
  }
  fit
}

cov_from_scores <- function(D, psi) {
  if (any(!is.finite(D)) || any(!is.finite(psi)) || nrow(psi) <= ncol(psi)) return(NULL)
  if (qr(D, tol = 1e-10)$rank < ncol(D)) return(NULL)
  centered <- sweep(psi, 2L, colMeans(psi), '-')
  B <- crossprod(centered) / nrow(centered)
  invD <- try(solve(D), silent = TRUE)
  if (inherits(invD, 'try-error')) return(NULL)
  V <- invD %*% B %*% t(invD) / nrow(centered)
  V <- (V + t(V)) / 2
  if (any(!is.finite(V)) || any(diag(V) < -1e-10)) return(NULL)
  V
}

fd_covariance <- function(theta, score_fun, relative_step = 1e-6) {
  psi <- score_fun(theta)
  p <- length(theta)
  D <- matrix(NA_real_, p, p)
  for (j in seq_len(p)) {
    h <- relative_step * max(1, abs(theta[j]))
    plus <- minus <- theta
    plus[j] <- plus[j] + h
    minus[j] <- minus[j] - h
    D[, j] <- (colMeans(score_fun(plus)) - colMeans(score_fun(minus))) / (2 * h)
  }
  cov_from_scores(D, psi)
}

effective_n <- function(w) {
  d <- sum(w^2)
  if (!is.finite(d) || d <= 0) return(0)
  sum(w)^2 / d
}

fixed_membership_estimate <- function(dat, trt, M, include_prevalence = FALSE,
                                      finite_difference = FALSE) {
  if (!is.na(trt$fail[1L])) return(failure_result(trt$fail))
  if (length(M) != nrow(dat) || any(!is.finite(M))) return(failure_result('invalid-membership'))
  X <- trt$X
  p <- ncol(X)
  A <- dat$A
  Y <- dat$Y
  e <- trt$q
  z1 <- A / e
  z0 <- (1 - A) / (1 - e)
  w1 <- M * z1
  w0 <- M * z0
  d1 <- sum(w1)
  d0 <- sum(w0)
  if (!is.finite(d1) || !is.finite(d0) || d1 <= 1e-8 || d0 <= 1e-8) {
    return(failure_result('empty-analysis-arm'))
  }
  ess1 <- effective_n(w1)
  ess0 <- effective_n(w0)
  if (ess1 < 10 || ess0 < 10) return(failure_result('arm-ess-below-10'))
  mu1 <- sum(w1 * Y) / d1
  mu0 <- sum(w0 * Y) / d0
  pe <- mean(M)

  theta <- c(trt$coef, if (include_prevalence) pe, mu1, mu0)
  score_fun <- function(th) {
    beta <- th[seq_len(p)]
    ee <- expit(drop(X %*% beta))
    zz1 <- A / ee
    zz0 <- (1 - A) / (1 - ee)
    pos <- p
    pieces <- list(X * (A - ee))
    if (include_prevalence) {
      pos <- pos + 1L
      pieces[[length(pieces) + 1L]] <- M - th[pos]
    }
    pieces[[length(pieces) + 1L]] <- M * zz1 * (Y - th[pos + 1L])
    pieces[[length(pieces) + 1L]] <- M * zz0 * (Y - th[pos + 2L])
    do.call(cbind, pieces)
  }

  if (finite_difference) {
    ## The oracle protocol explicitly requires a central finite-difference
    ## Jacobian with relative step 1e-6.
    V <- fd_covariance(theta, score_fun, relative_step = 1e-6)
  } else {
    psi <- score_fun(theta)
    q <- length(theta)
    D <- matrix(0, q, q)
    D[seq_len(p), seq_len(p)] <- -crossprod(X, X * (e * (1 - e))) / nrow(dat)
    pos <- p
    if (include_prevalence) {
      D[pos + 1L, pos + 1L] <- -1
      pos <- pos + 1L
    }
    i1 <- pos + 1L
    i0 <- pos + 2L
    D[i1, seq_len(p)] <- colMeans(X * (-M * z1 * (1 - e) * (Y - mu1)))
    D[i0, seq_len(p)] <- colMeans(X * ( M * z0 * e * (Y - mu0)))
    D[i1, i1] <- -mean(w1)
    D[i0, i0] <- -mean(w0)
    V <- cov_from_scores(D, psi)
  }
  if (is.null(V)) return(failure_result('singular-or-nonfinite-sandwich'))
  i1 <- length(theta) - 1L
  i0 <- length(theta)
  vr <- V[i1, i1] + V[i0, i0] - 2 * V[i1, i0]
  if (!is.finite(vr) || vr < -1e-10) return(failure_result('invalid-rd-variance'))
  se <- sqrt(max(0, vr))
  pe_index <- if (include_prevalence) p + 1L else NA_integer_
  list(
    est = mu1 - mu0, se = se,
    lo = mu1 - mu0 - stats::qnorm(0.975) * se,
    hi = mu1 - mu0 + stats::qnorm(0.975) * se,
    pe_est = pe, ne_est = sum(M),
    pe_se = if (include_prevalence) sqrt(max(0, V[pe_index, pe_index])) else NA_real_,
    within_var = NA_real_, between_var = NA_real_, df = Inf,
    ess0 = ess0, ess1 = ess1,
    max_weight = max(abs(c(w0, w1))), fail = NA_character_
  )
}

joint_logit_membership_estimate <- function(dat, trt, qfit, score_y,
                                             score_weight, M, dM,
                                             require_ess = TRUE) {
  if (!is.na(trt$fail[1L])) return(failure_result(trt$fail))
  if (!is.na(qfit$fail[1L])) return(failure_result(qfit$fail))
  X <- trt$X
  Xg <- qfit$X
  p <- ncol(X)
  g <- ncol(Xg)
  n <- nrow(dat)
  A <- dat$A
  Y <- dat$Y
  e <- trt$q
  q <- qfit$q
  if (!is.matrix(dM)) dM <- matrix(dM, ncol = g)
  if (nrow(dM) != n || ncol(dM) != g || any(!is.finite(M)) || any(!is.finite(dM))) {
    return(failure_result('invalid-fractional-membership'))
  }
  z1 <- A / e
  z0 <- (1 - A) / (1 - e)
  w1 <- M * z1
  w0 <- M * z0
  d1 <- sum(w1)
  d0 <- sum(w0)
  if (!is.finite(d1) || !is.finite(d0) || d1 <= 1e-8 || d0 <= 1e-8) {
    return(failure_result('augmented-or-weighted-denominator-failure'))
  }
  ess1 <- effective_n(w1)
  ess0 <- effective_n(w0)
  if (require_ess && (ess1 < 10 || ess0 < 10)) return(failure_result('arm-ess-below-10'))
  mu1 <- sum(w1 * Y) / d1
  mu0 <- sum(w0 * Y) / d0
  pe <- mean(M)

  psi_beta <- X * (A - e)
  psi_gamma <- Xg * (score_weight * (score_y - q))
  psi <- cbind(
    psi_beta, psi_gamma, M - pe,
    M * z1 * (Y - mu1), M * z0 * (Y - mu0)
  )
  total <- p + g + 3L
  D <- matrix(0, total, total)
  ib <- seq_len(p)
  ig <- p + seq_len(g)
  ipe <- p + g + 1L
  i1 <- p + g + 2L
  i0 <- p + g + 3L
  D[ib, ib] <- -crossprod(X, X * (e * (1 - e))) / n
  D[ig, ig] <- -crossprod(Xg, Xg * (score_weight * q * (1 - q))) / n
  D[ipe, ig] <- colMeans(dM)
  D[ipe, ipe] <- -1
  D[i1, ib] <- colMeans(X * (-M * z1 * (1 - e) * (Y - mu1)))
  D[i0, ib] <- colMeans(X * ( M * z0 * e * (Y - mu0)))
  D[i1, ig] <- colMeans(dM * (z1 * (Y - mu1)))
  D[i0, ig] <- colMeans(dM * (z0 * (Y - mu0)))
  D[i1, i1] <- -mean(w1)
  D[i0, i0] <- -mean(w0)
  V <- cov_from_scores(D, psi)
  if (is.null(V)) return(failure_result('singular-or-nonfinite-sandwich'))
  vr <- V[i1, i1] + V[i0, i0] - 2 * V[i1, i0]
  if (!is.finite(vr) || vr < -1e-10) return(failure_result('invalid-rd-variance'))
  se <- sqrt(max(0, vr))
  list(
    est = mu1 - mu0, se = se,
    lo = mu1 - mu0 - stats::qnorm(0.975) * se,
    hi = mu1 - mu0 + stats::qnorm(0.975) * se,
    pe_est = pe, ne_est = sum(M), pe_se = sqrt(max(0, V[ipe, ipe])),
    within_var = NA_real_, between_var = NA_real_, df = Inf,
    ess0 = ess0, ess1 = ess1, max_weight = max(abs(c(w0, w1))),
    fail = NA_character_
  )
}

pool_mi <- function(results, M) {
  z <- results[seq_len(M)]
  ok <- vapply(z, function(x) {
    is.list(x) && (is.null(x$fail) || is.na(x$fail[1L])) &&
      is.finite(x$est) && is.finite(x$se)
  }, logical(1))
  if (sum(ok) < M) return(failure_result(sprintf('fewer-than-%d-finite-imputations', M)))
  est <- vapply(z, `[[`, numeric(1), 'est')
  U <- vapply(z, function(x) x$se^2, numeric(1))
  pe <- vapply(z, `[[`, numeric(1), 'pe_est')
  ne <- vapply(z, `[[`, numeric(1), 'ne_est')
  within <- mean(U)
  between <- stats::var(est)
  total <- within + (1 + 1 / M) * between
  if (!is.finite(total) || total < 0) return(failure_result('nonfinite-rubin-variance'))
  if (between <= .Machine$double.eps * max(1, within)) {
    df <- Inf
    critical <- stats::qnorm(0.975)
  } else {
    df <- (M - 1) * (1 + within / ((1 + 1 / M) * between))^2
    critical <- stats::qt(0.975, df)
  }
  point <- mean(est)
  se <- sqrt(total)
  list(
    est = point, se = se, lo = point - critical * se, hi = point + critical * se,
    pe_est = mean(pe), ne_est = mean(ne), pe_se = NA_real_,
    within_var = within, between_var = between, df = df,
    ess0 = mean(vapply(z, `[[`, numeric(1), 'ess0')),
    ess1 = mean(vapply(z, `[[`, numeric(1), 'ess1')),
    max_weight = max(vapply(z, `[[`, numeric(1), 'max_weight')),
    fail = NA_character_
  )
}

run_mi_continuous <- function(dat, trt, ols, Mmax = MI_PRIMARY) {
  if (!is.na(ols$fail[1L])) return(list(m20 = failure_result(ols$fail)))
  X <- eligibility_matrix(dat, 'recorded')
  missing <- which(dat$R == 0L)
  completed <- vector('list', Mmax)
  for (j in seq_len(Mmax)) {
    beta <- draw_mvn(ols$coef, ols$vcov)
    if (is.null(beta)) {
      completed[[j]] <- failure_result('laboratory-coefficient-draw-failed')
      next
    }
    G <- dat$Gobs
    G[missing] <- drop(X[missing, , drop = FALSE] %*% beta) +
      ols$residuals[sample.int(length(ols$residuals), length(missing), replace = TRUE)]
    E <- as.integer(G >= 45)
    completed[[j]] <- fixed_membership_estimate(dat, trt, E)
  }
  out <- list(m20 = pool_mi(completed, MI_PRIMARY))
  if (Mmax >= MI_CHECK) out$m50 <- pool_mi(completed, MI_CHECK)
  out
}

run_mi_indicator <- function(dat, trt, efit, X, Mmax = MI_PRIMARY) {
  if (!is.na(efit$fail[1L])) return(list(m20 = failure_result(efit$fail)))
  missing <- which(dat$R == 0L)
  completed <- vector('list', Mmax)
  for (j in seq_len(Mmax)) {
    beta <- draw_mvn(efit$coef, efit$vcov)
    if (is.null(beta)) {
      completed[[j]] <- failure_result('eligibility-coefficient-draw-failed')
      next
    }
    prob <- expit(drop(X[missing, , drop = FALSE] %*% beta))
    E <- as.integer(dat$Eobs)
    E[missing] <- stats::rbinom(length(missing), 1, prob)
    completed[[j]] <- fixed_membership_estimate(dat, trt, E)
  }
  out <- list(m20 = pool_mi(completed, MI_PRIMARY))
  if (Mmax >= MI_CHECK) out$m50 <- pool_mi(completed, MI_CHECK)
  out
}

estimate_mar_ipaw <- function(dat, trt, rfit) {
  if (!is.na(rfit$fail[1L])) return(failure_result(rfit$fail))
  s <- rfit$q
  if (any(s < 1e-8 | 1 - s < 1e-8)) return(failure_result('recording-positivity-failure'))
  M <- dat$RE / s
  dM <- rfit$X * (-dat$RE * (1 - s) / s)
  joint_logit_membership_estimate(
    dat, trt, rfit, score_y = dat$R, score_weight = rep(1, nrow(dat)),
    M = M, dM = dM, require_ess = TRUE
  )
}

estimate_sensitivity <- function(dat, trt, efit, lambda_star) {
  if (!is.na(efit$fail[1L])) return(failure_result(efit$fail))
  q_star <- expit(drop(efit$X %*% efit$coef) + lambda_star)
  M <- dat$RE + (1 - dat$R) * q_star
  dM <- efit$X * ((1 - dat$R) * q_star * (1 - q_star))
  y_score <- ifelse(dat$R == 1L, dat$Eobs, 0)
  joint_logit_membership_estimate(
    dat, trt, efit, score_y = y_score, score_weight = dat$R,
    M = M, dM = dM, require_ess = TRUE
  )
}

fit_phase_eligibility <- function(dat, E, Q, rho, type) {
  X <- eligibility_matrix(dat, type)
  idx <- which(Q == 1L)
  fit <- safe_logit(X[idx, , drop = FALSE], E[idx], weights = 1 / rho[idx])
  if (!is.na(fit$fail[1L])) return(fit)
  extend_logit(fit, X)
}

estimate_fractional <- function(dat, trt, E, Q, rho, qfit) {
  if (!is.na(qfit$fail[1L])) return(failure_result(qfit$fail))
  q <- qfit$q
  M <- Q * E + (1 - Q) * q
  dM <- qfit$X * ((1 - Q) * q * (1 - q))
  joint_logit_membership_estimate(
    dat, trt, qfit, score_y = E, score_weight = Q / rho,
    M = M, dM = dM, require_ess = TRUE
  )
}

estimate_augmented <- function(dat, trt, E, Q, rho, qfit) {
  if (!is.na(qfit$fail[1L])) return(failure_result(qfit$fail))
  q <- qfit$q
  M <- q + Q / rho * (E - q)
  dM <- qfit$X * ((1 - Q / rho) * q * (1 - q))
  joint_logit_membership_estimate(
    dat, trt, qfit, score_y = E, score_weight = Q / rho,
    M = M, dM = dM, require_ess = FALSE
  )
}

estimate_two_phase <- function(dat, trt, E, Q, rho) {
  M <- Q * E / rho
  fixed_membership_estimate(dat, trt, M, include_prevalence = TRUE)
}

estimate_oracle_recording <- function(dat, trt) {
  fixed_membership_estimate(dat, trt, dat$RE / dat$pR)
}

imbens_manski_critical <- function(width, max_se) {
  if (!is.finite(max_se) || max_se < 0) return(NA_real_)
  if (max_se == 0) return(if (width <= 1e-14) stats::qnorm(0.975) else 0)
  d <- max(0, width) / max_se
  f <- function(c) stats::pnorm(c + d) - stats::pnorm(-c) - 0.95
  stats::uniroot(f, c(0, 8), tol = 1e-10)$root
}

estimate_bounds <- function(dat, trt) {
  if (!is.na(trt$fail[1L])) return(failure_result(trt$fail))
  X <- trt$X
  p <- ncol(X)
  A <- dat$A
  Y <- dat$Y
  R0 <- 1 - dat$R
  RE <- dat$RE

  contributions <- function(beta) {
    e <- expit(drop(X %*% beta))
    z0 <- (1 - A) / (1 - e)
    z1 <- A / e
    cbind(
      z0 * RE * Y, z0 * RE, z0 * R0 * Y, z0 * R0 * (1 - Y),
      z1 * RE * Y, z1 * RE, z1 * R0 * Y, z1 * R0 * (1 - Y)
    )
  }
  initial_contrib <- contributions(trt$coef)
  moments <- colMeans(initial_contrib)
  theta <- c(trt$coef, moments)
  score_fun <- function(th) {
    beta <- th[seq_len(p)]
    mm <- th[p + seq_len(8L)]
    cbind(X * (A - expit(drop(X %*% beta))),
          sweep(contributions(beta), 2L, mm, '-'))
  }
  V <- fd_covariance(theta, score_fun, relative_step = 1e-6)
  if (is.null(V)) return(failure_result('bounds-sandwich-failure'))

  endpoint <- function(th) {
    m <- th[p + seq_len(8L)]
    L0 <- m[1L] / (m[2L] + m[4L])
    U0 <- (m[1L] + m[3L]) / (m[2L] + m[3L])
    L1 <- m[5L] / (m[6L] + m[8L])
    U1 <- (m[5L] + m[7L]) / (m[6L] + m[7L])
    c(lower = L1 - U0, upper = U1 - L0)
  }
  ep <- endpoint(theta)
  if (any(!is.finite(ep)) || ep[1L] > ep[2L] + 1e-10) {
    return(failure_result('invalid-bound-endpoint'))
  }
  G <- matrix(NA_real_, 2L, length(theta))
  for (j in seq_along(theta)) {
    h <- 1e-6 * max(1, abs(theta[j]))
    plus <- minus <- theta
    plus[j] <- plus[j] + h
    minus[j] <- minus[j] - h
    G[, j] <- (endpoint(plus) - endpoint(minus)) / (2 * h)
  }
  Ve <- G %*% V %*% t(G)
  if (any(!is.finite(Ve)) || any(diag(Ve) < -1e-10)) {
    return(failure_result('invalid-bound-endpoint-covariance'))
  }
  se <- sqrt(pmax(0, diag(Ve)))
  critical <- imbens_manski_critical(ep[2L] - ep[1L], max(se))
  if (!is.finite(critical)) return(failure_result('imbens-manski-critical-failure'))
  list(
    est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
    pe_est = NA_real_, ne_est = NA_real_, pe_se = NA_real_,
    within_var = NA_real_, between_var = NA_real_, df = NA_real_,
    ess0 = NA_real_, ess1 = NA_real_, max_weight = NA_real_,
    bound_lo = ep[1L], bound_hi = ep[2L],
    bound_ci_lo = max(-1, ep[1L] - critical * se[1L]),
    bound_ci_hi = min(1, ep[2L] + critical * se[2L]),
    bound_se_lo = se[1L], bound_se_hi = se[2L],
    pe_lower = mean(RE), pe_upper = mean(RE) + mean(R0),
    fail = NA_character_
  )
}
