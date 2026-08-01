## Study MIS-01: estimators and variance procedures.

cluster_sum <- function(x, id, n) {
  x <- as.matrix(x)
  z <- rowsum(x, id, reorder = FALSE)
  out <- matrix(0, n, ncol(x))
  out[as.integer(rownames(z)), ] <- z
  colnames(out) <- colnames(x)
  out
}

safe_inverse <- function(x) {
  out <- try(solve(x), silent = TRUE)
  if (inherits(out, 'try-error') || any(!is.finite(out))) NULL else out
}

safe_binomial_fit <- function(X, y, id, n, weights = NULL, link = 'logit') {
  X <- as.matrix(X)
  y <- as.numeric(y)
  if (is.null(weights)) weights <- rep(1, length(y))
  if (!length(y) || length(unique(y[weights > 0])) < 2L || qr(X[weights > 0, , drop = FALSE])$rank < ncol(X)) {
    return(list(ok = FALSE, stage = 'rank-or-response'))
  }
  family <- stats::binomial(link = link)
  fit <- try(stats::glm.fit(X, y, weights = weights, family = family,
                            control = stats::glm.control(maxit = 80, epsilon = 1e-9)),
             silent = TRUE)
  if (inherits(fit, 'try-error') || !isTRUE(fit$converged) ||
      any(!is.finite(fit$coefficients)) || any(abs(fit$coefficients) > 25)) {
    return(list(ok = FALSE, stage = 'regression'))
  }
  eta <- drop(X %*% fit$coefficients)
  mu <- clamp_probability(family$linkinv(eta))
  mueta <- family$mu.eta(eta)
  variance <- family$variance(mu)
  info_weight <- weights * mueta^2 / variance
  bread <- crossprod(X, X * info_weight)
  cond <- try(kappa(bread, exact = FALSE), silent = TRUE)
  if (inherits(cond, 'try-error') || !is.finite(cond) || cond > COND_LIMIT) {
    return(list(ok = FALSE, stage = 'information'))
  }
  score_factor <- weights * (y - mu) * mueta / variance
  score <- cluster_sum(X * score_factor, id, n)
  list(ok = TRUE, beta = fit$coefficients, X = X, y = y, id = id,
       weights = weights, mu = mu, mueta = mueta, variance = variance,
       bread = bread, score = score, condition = cond, link = link)
}

transition_x <- function(d, scen, variant, current = 'Ltrue',
                         previous = 'Lprev', previous2 = 'Lprev2') {
  X <- cbind(1, d[[previous]], d$B, d$C, d$Aprev, d$time)
  colnames(X) <- c('intercept', 'Lprev', 'B', 'C', 'Aprev', 'time')
  if (variant == 'aware' && isTRUE(scen$dep_transition)) {
    X <- cbind(X, d[[previous2]], d[[previous]] * d$C)
    colnames(X)[(ncol(X) - 1):ncol(X)] <- c('Lprev2', 'Lprev_C')
  }
  X
}

outcome_x <- function(d, scen, variant, current = 'Ltrue') {
  L <- d[[current]]
  X <- cbind(1, L, d$C, d$B, d$A, d$A * L)
  colnames(X) <- c('intercept', 'L', 'C', 'B', 'A', 'A_L')
  if (variant == 'aware' && isTRUE(scen$dep_treatment_outcome)) {
    X <- cbind(X, d$A * d$C, d$sin_time)
    colnames(X)[(ncol(X) - 1):ncol(X)] <- c('A_C', 'sin_time')
  }
  X
}

required_cells_ok <- function(a, l, y) {
  tab <- table(factor(a, 0:1), factor(l, 0:1), factor(y, 0:1))
  all(tab > 0)
}

baseline_information <- function(dat, n) {
  b <- dat[t == 0L]
  cell <- 1L + b$L0 + 2L * b$C + 4L * b$F + 8L * b$B
  counts <- tabulate(cell, nbins = 16L)
  p <- counts / n
  q <- p[1:15]
  score <- -matrix(q, nrow = n, ncol = 15L, byrow = TRUE)
  j <- which(cell <= 15L)
  score[cbind(b$id[j], cell[j])] <- score[cbind(b$id[j], cell[j])] + 1
  list(p = p, q = q, score = score, bread = diag(n, 15L))
}

fitted_transition_probability <- function(beta, scen, variant, t, Lprev,
                                          Lprev2, B, C, Aprev) {
  d <- data.frame(Lprev = Lprev, Lprev2 = Lprev2, B = B, C = C,
                  Aprev = Aprev, time = t / 24)
  expit(drop(transition_x(d, scen, variant) %*% beta))
}

fitted_outcome_probability <- function(beta, scen, variant, t, L, B, C, A) {
  d <- data.frame(Ltrue = L, C = C, B = B, A = A,
                  sin_time = sin(pi * t / 24))
  expit(drop(outcome_x(d, scen, variant) %*% beta))
}

fitted_intervention_risks <- function(beta_t, beta_y, q, scen, variant) {
  base <- baseline_cells()
  base$prob <- c(q, 1 - sum(q))
  one <- function(strategy) {
    x <- base
    x$Lprev <- x$L0
    x$Lprev2 <- x$L0
    pY <- fitted_outcome_probability(beta_y, scen, variant, 0L,
                                     x$L0, x$B, x$C, strategy)
    x$prob <- x$prob * (1 - pY)
    risk <- numeric(24L)
    risk[1] <- 1 - sum(x$prob)
    for (t in 1:23) {
      pL <- fitted_transition_probability(beta_t, scen, variant, t,
                                          x$Lprev, x$Lprev2,
                                          x$B, x$C, strategy)
      old <- x$Lprev
      x <- branch_binary(x, pL, 'L')
      old <- rep(old, each = 2L)
      pY <- fitted_outcome_probability(beta_y, scen, variant, t,
                                       x$L, x$B, x$C, strategy)
      x$prob <- x$prob * (1 - pY)
      x$Lprev2 <- old
      x$Lprev <- x$L
      x$L <- NULL
      x <- stats::aggregate(prob ~ B + F + C + L0 + cell + Lprev + Lprev2,
                            data = x, FUN = sum)
      risk[t + 1L] <- 1 - sum(x$prob)
    }
    risk
  }
  r1 <- one(1L)
  r0 <- one(0L)
  list(value = c(rd12 = r1[12] - r0[12],
                 rd24 = r1[24] - r0[24],
                 log_rr24 = log(r1[24] / r0[24])),
       risk1 = c(rd12 = r1[12], rd24 = r1[24], log_rr24 = r1[24]),
       risk0 = c(rd12 = r0[12], rd24 = r0[24], log_rr24 = r0[24]))
}

numeric_gradient <- function(fn, theta) {
  p <- length(theta)
  f0 <- fn(theta)
  G <- matrix(NA_real_, length(f0), p)
  for (j in seq_len(p)) {
    h <- 1e-5 * max(1, abs(theta[j]))
    up <- down <- theta
    up[j] <- up[j] + h
    down[j] <- down[j] - h
    G[, j] <- (fn(up) - fn(down)) / (2 * h)
  }
  G
}

result_template <- function(method, variant, why = NA_character_, stage = NA_character_) {
  data.frame(
    method = method, variant = variant, estimand = ESTIMANDS,
    est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_, df = NA_real_,
    risk1 = NA_real_, risk0 = NA_real_, fail = why, fail_stage = stage,
    obs_brier = NA_real_, obs_cal_intercept = NA_real_, obs_cal_slope = NA_real_,
    latent_brier = NA_real_, weight_max = NA_real_, weight_p99 = NA_real_,
    weight_cv = NA_real_, weight_ess_fraction = NA_real_, max_gap = NA_real_,
    gamma_l_hat = NA_real_, gamma_l_se = NA_real_, gamma_boundary = NA_real_,
    profile_drop = NA_real_, runtime_sec = NA_real_, memory_mb = NA_real_,
    stringsAsFactors = FALSE
  )
}

rows_from_fit <- function(method, variant, values, ses, risks, diag = list(),
                          dfs = rep(Inf, 3L)) {
  out <- result_template(method, variant)
  out$est <- unname(values[ESTIMANDS])
  out$se <- unname(ses[ESTIMANDS])
  out$df <- dfs
  crit <- ifelse(is.finite(dfs), stats::qt(0.975, dfs), 1.96)
  out$lo <- out$est - crit * out$se
  out$hi <- out$est + crit * out$se
  out$risk1 <- unname(risks$risk1[ESTIMANDS])
  out$risk0 <- unname(risks$risk0[ESTIMANDS])
  for (nm in intersect(names(diag), names(out))) out[[nm]] <- diag[[nm]]
  bad <- !is.finite(out$est) | !is.finite(out$se)
  out$fail[bad] <- 'nonfinite-result'
  out$fail_stage[bad] <- 'recursion-or-variance'
  out
}

fit_standard_gformula <- function(data, scen, variant, method,
                                  source = c('oracle', 'complete', 'locf', 'imputed')) {
  source <- match.arg(source)
  dat <- data$long
  n <- data$n
  if (source == 'oracle') {
    cur <- 'Ltrue'; prev <- 'Lprev'; prev2 <- 'Lprev2'
    tr <- dat[t > 0L]; ev <- dat
  } else if (source == 'complete') {
    cur <- 'Lobs'; prev <- 'Lprev'; prev2 <- 'Lprev2'
    tr <- dat[t > 0L & R == 1L & Rprev == 1L]
    ev <- dat[t == 0L | R == 1L]
  } else if (source == 'locf') {
    cur <- 'Llocf'; prev <- 'Llocf_prev'; prev2 <- 'Llocf_prev2'
    tr <- dat[t > 0L]; ev <- dat
  } else {
    cur <- 'Limp'; prev <- 'Limp_prev'; prev2 <- 'Limp_prev2'
    tr <- dat[t > 0L]; ev <- dat
  }
  if (!nrow(tr) || !nrow(ev) ||
      !required_cells_ok(tr$Aprev, tr[[prev]], tr[[cur]]) ||
      !required_cells_ok(ev$A, ev[[cur]], ev$y)) {
    return(result_template(method, variant, 'unsupported-cell', 'regression'))
  }
  ft <- safe_binomial_fit(transition_x(tr, scen, variant, cur, prev, prev2),
                          tr[[cur]], tr$id, n)
  fy <- safe_binomial_fit(outcome_x(ev, scen, variant, cur),
                          ev$y, ev$id, n)
  if (!ft$ok) return(result_template(method, variant, ft$stage, 'transition'))
  if (!fy$ok) return(result_template(method, variant, fy$stage, 'outcome'))
  base <- baseline_information(dat, n)
  score <- cbind(ft$score, fy$score, base$score)
  p <- ncol(score)
  A <- matrix(0, p, p)
  it <- seq_len(length(ft$beta))
  iy <- max(it) + seq_len(length(fy$beta))
  ib <- max(iy) + seq_len(15L)
  A[it, it] <- ft$bread
  A[iy, iy] <- fy$bread
  A[ib, ib] <- base$bread
  Ainv <- safe_inverse(A)
  if (is.null(Ainv)) return(result_template(method, variant, 'singular-stack', 'variance'))
  V <- Ainv %*% crossprod(score) %*% t(Ainv)
  theta <- c(ft$beta, fy$beta, base$q)
  fn <- function(z) {
    bt <- z[it]; by <- z[iy]; q <- z[ib]
    fitted_intervention_risks(bt, by, q, scen, variant)$value
  }
  G <- numeric_gradient(fn, theta)
  VV <- G %*% V %*% t(G)
  ses <- sqrt(pmax(0, diag(VV)))
  names(ses) <- ESTIMANDS
  risks <- fitted_intervention_risks(ft$beta, fy$beta, base$q, scen, variant)
  rows_from_fit(method, variant, risks$value, ses, risks,
                diag = list(max_gap = data$max_gap))
}

obs_x <- function(d, scen, variant) {
  X <- cbind(1, d$B, d$F, d$C, d$Aprev, d$Rprev, d$lastL_pre,
             d$gap_pre, d$time, d$time2)
  colnames(X) <- c('intercept', 'B', 'F', 'C', 'Aprev', 'Rprev',
                   'lastL', 'gap', 'time', 'time2')
  if (variant == 'aware' && isTRUE(scen$dep_observation)) {
    X <- cbind(X, d$lastL_pre * d$C, d$sin_time)
    colnames(X)[(ncol(X) - 1):ncol(X)] <- c('lastL_C', 'sin_time')
  }
  X
}

fit_observation_model <- function(data, scen, variant) {
  d <- data$long[t > 0L]
  n <- data$n
  link <- if (variant == 'aware' && isTRUE(scen$dep_observation)) 'cloglog' else 'logit'
  X <- obs_x(d, scen, variant)
  fit <- safe_binomial_fit(X, d$R, d$id, n, link = link)
  if (!fit$ok) return(fit)

  ## Critique fix: observable calibration uses subject-level five-fold held-out
  ## predictions. In-sample intercepts and slopes are not reported.
  fold <- 1L + ((d$id - 1L) %% 5L)
  pred <- rep(NA_real_, nrow(d))
  for (k in 1:5) {
    train <- fold != k
    fk <- safe_binomial_fit(X[train, , drop = FALSE], d$R[train], d$id[train],
                            n, link = link)
    if (!fk$ok) return(list(ok = FALSE, stage = 'crossfit-observation'))
    pred[!train] <- stats::binomial(link)$linkinv(drop(X[!train, , drop = FALSE] %*% fk$beta))
  }
  pred <- clamp_probability(pred)
  lp <- stats::qlogis(pred)
  ci <- try(stats::coef(stats::glm(d$R ~ 1 + offset(lp), family = stats::binomial()))[1],
            silent = TRUE)
  cs <- try(stats::coef(stats::glm(d$R ~ lp, family = stats::binomial()))[2],
            silent = TRUE)
  true_p <- observation_probability(scen, d$t, d$Ltrue, d$Aprev, d$Rprev, d$C)
  fit$data <- d
  fit$X <- X
  fit$p <- fit$mu
  fit$dp <- X * fit$mueta
  fit$diag <- list(
    obs_brier = mean((d$R - pred)^2),
    obs_cal_intercept = if (inherits(ci, 'try-error')) NA_real_ else unname(ci),
    obs_cal_slope = if (inherits(cs, 'try-error')) NA_real_ else unname(cs),
    latent_brier = mean((d$R - true_p)^2),
    max_gap = data$max_gap
  )
  fit
}

calibration_z <- function(d) {
  Z <- cbind(d$B, d$F, d$C, d$Aprev, d$Rprev, d$lastL_pre,
             d$gap_pre, d$Aprev * d$lastL_pre)
  colnames(Z) <- c('B', 'F', 'C', 'Aprev', 'Rprev', 'lastL', 'gap', 'Aprev_lastL')
  center <- colMeans(Z)
  scale <- apply(Z, 2, stats::sd)
  scale[!is.finite(scale) | scale < 1e-8] <- 1
  sweep(sweep(Z, 2, center), 2, scale, '/')
}

solve_tilting <- function(raw, Z, month) {
  lambda <- numeric(ncol(Z))
  for (iter in seq_len(CALIBRATION_MAXIT)) {
    e <- exp(pmin(30, pmax(-30, drop(Z %*% lambda))))
    base <- raw * e
    cmonth <- vapply(1:23, function(t) mean(base[month == t]), numeric(1))
    if (any(!is.finite(cmonth)) || any(cmonth <= 0)) return(NULL)
    w <- base / cmonth[month]
    moment <- colMeans((w - 1) * Z)
    if (max(abs(moment)) < CALIBRATION_TOL) {
      return(list(lambda = lambda, cmonth = cmonth, w = w, base = base,
                  residual = max(abs(moment))))
    }
    J <- matrix(0, ncol(Z), ncol(Z))
    for (t in 1:23) {
      j <- month == t
      zw <- colSums(Z[j, , drop = FALSE] * w[j]) / sum(w[j])
      Zc <- sweep(Z[j, , drop = FALSE], 2, zw)
      J <- J + crossprod(Zc, Z[j, , drop = FALSE] * w[j]) / length(raw)
    }
    step <- try(solve(J, moment), silent = TRUE)
    if (inherits(step, 'try-error') || any(!is.finite(step))) return(NULL)
    lambda <- lambda - step
  }
  NULL
}

make_weight_process <- function(d, raw, draw, qdim, n, type) {
  month <- d$t
  stopifnot(all(month %in% 1:23))
  cmonth <- vapply(1:23, function(t) mean(raw[month == t]), numeric(1))
  if (any(!is.finite(cmonth)) || any(cmonth <= 0)) return(NULL)

  if (type == 'raw') {
    local_dim <- 23L
    score <- matrix(0, n, local_dim)
    A <- matrix(0, local_dim, qdim + local_dim)
    dw <- matrix(0, nrow(d), qdim + local_dim)
    w <- raw / cmonth[month]
    for (t in 1:23) {
      j <- month == t
      score[, t] <- cluster_sum(raw[j] - cmonth[t], d$id[j], n)[, 1]
      A[t, seq_len(qdim)] <- -colSums(draw[j, , drop = FALSE])
      A[t, qdim + t] <- sum(j)
      dw[j, seq_len(qdim)] <- draw[j, , drop = FALSE] / cmonth[t]
      dw[j, qdim + t] <- -raw[j] / cmonth[t]^2
    }
  } else if (type == 'capped') {
    local_dim <- 46L
    v <- raw / cmonth[month]
    capv <- pmin(WEIGHT_CAP, v)
    dmonth <- vapply(1:23, function(t) mean(capv[month == t]), numeric(1))
    if (any(!is.finite(dmonth)) || any(dmonth <= 0)) return(NULL)
    score <- matrix(0, n, local_dim)
    A <- matrix(0, local_dim, qdim + local_dim)
    dw <- matrix(0, nrow(d), qdim + local_dim)
    w <- capv / dmonth[month]
    for (t in 1:23) {
      j <- month == t
      active <- v[j] < WEIGHT_CAP
      dvq <- draw[j, , drop = FALSE] / cmonth[t]
      dvc <- -raw[j] / cmonth[t]^2
      dcq <- dvq * active
      dcc <- dvc * active
      score[, t] <- cluster_sum(raw[j] - cmonth[t], d$id[j], n)[, 1]
      score[, 23L + t] <- cluster_sum(capv[j] - dmonth[t], d$id[j], n)[, 1]
      A[t, seq_len(qdim)] <- -colSums(draw[j, , drop = FALSE])
      A[t, qdim + t] <- sum(j)
      A[23L + t, seq_len(qdim)] <- -colSums(dcq)
      A[23L + t, qdim + t] <- -sum(dcc)
      A[23L + t, qdim + 23L + t] <- sum(j)
      dw[j, seq_len(qdim)] <- dcq / dmonth[t]
      dw[j, qdim + t] <- dcc / dmonth[t]
      dw[j, qdim + 23L + t] <- -capv[j] / dmonth[t]^2
    }
  } else {
    Z <- calibration_z(d)
    sol <- solve_tilting(raw, Z, month)
    if (is.null(sol)) return(NULL)
    k <- ncol(Z)
    local_dim <- 23L + k
    lambda <- sol$lambda
    base <- sol$base
    cmonth <- sol$cmonth
    w <- sol$w
    score <- matrix(0, n, local_dim)
    A <- matrix(0, local_dim, qdim + local_dim)
    dw <- matrix(0, nrow(d), qdim + local_dim)
    e <- exp(pmin(30, pmax(-30, drop(Z %*% lambda))))
    dbaseq <- draw * e
    for (t in 1:23) {
      j <- month == t
      score[, t] <- cluster_sum(base[j] - cmonth[t], d$id[j], n)[, 1]
      A[t, seq_len(qdim)] <- -colSums(dbaseq[j, , drop = FALSE])
      A[t, qdim + t] <- sum(j)
      A[t, qdim + 23L + seq_len(k)] <- -colSums(base[j] * Z[j, , drop = FALSE])
      dw[j, seq_len(qdim)] <- dbaseq[j, , drop = FALSE] / cmonth[t]
      dw[j, qdim + t] <- -base[j] / cmonth[t]^2
      dw[j, qdim + 23L + seq_len(k)] <- Z[j, , drop = FALSE] * w[j]
    }
    score_lambda <- cluster_sum((1 - w) * Z, d$id, n)
    score[, 23L + seq_len(k)] <- score_lambda
    il <- 23L + seq_len(k)
    for (a in seq_len(k)) {
      A[il[a], seq_len(qdim)] <- colSums(Z[, a] * dw[, seq_len(qdim), drop = FALSE])
      A[il[a], qdim + seq_len(local_dim)] <-
        colSums(Z[, a] * dw[, qdim + seq_len(local_dim), drop = FALSE])
    }
    ## Critique and citation fix: this is a study-specific visit-only
    ## exponential tilt. Month equations reproduce totals of 1 and therefore of
    ## time and squared time. The remaining explicit moments are in Z. It is not
    ## labeled as the published Kalia estimator.
  }
  list(w = w, dw = dw, score = score, A = A, local_dim = local_dim,
       max = max(w), p99 = unname(stats::quantile(w, 0.99)),
       cv = stats::sd(w) / mean(w),
       ess = sum(w)^2 / (nrow(d) * sum(w^2)))
}

build_weight_system <- function(data, obs, type) {
  dat <- data$long
  n <- data$n
  qdim <- length(obs$beta)
  pfull <- rep(1, nrow(dat))
  dpfull <- matrix(0, nrow(dat), qdim)
  idx <- dat$t > 0L
  pfull[idx] <- obs$p
  dpfull[idx, ] <- obs$dp

  dy <- dat[t > 0L]
  iy <- dy$rowid
  rawy <- ifelse(dy$R == 1L, 1 / pfull[iy], 0)
  drawy <- -dy$R * dpfull[iy, , drop = FALSE] / pfull[iy]^2

  dt <- dat[t > 0L]
  it <- dt$rowid
  ip <- it - 1L
  pair <- dt$R == 1L & dt$Rprev == 1L
  rawt <- ifelse(pair, 1 / (pfull[it] * pfull[ip]), 0)
  drawt <- -rawt * (dpfull[it, , drop = FALSE] / pfull[it] +
                    dpfull[ip, , drop = FALSE] / pfull[ip])

  py <- make_weight_process(dy, rawy, drawy, qdim, n, type)
  pt <- make_weight_process(dt, rawt, drawt, qdim, n, type)
  if (is.null(py) || is.null(pt)) return(NULL)

  p <- qdim + py$local_dim + pt$local_dim
  score <- cbind(obs$score, py$score, pt$score)
  A <- matrix(0, p, p)
  iq <- seq_len(qdim)
  iyl <- qdim + seq_len(py$local_dim)
  itl <- qdim + py$local_dim + seq_len(pt$local_dim)
  A[iq, iq] <- obs$bread
  A[iyl, c(iq, iyl)] <- py$A
  A[itl, c(iq, itl)] <- pt$A

  dwy <- matrix(0, nrow(dy), p)
  dwt <- matrix(0, nrow(dt), p)
  dwy[, c(iq, iyl)] <- py$dw
  dwt[, c(iq, itl)] <- pt$dw
  list(score = score, A = A, p = p, dy = dy, dt = dt,
       wy = py$w, wt = pt$w, dwy = dwy, dwt = dwt,
       diag = list(weight_max = max(py$max, pt$max),
                   weight_p99 = max(py$p99, pt$p99),
                   weight_cv = max(py$cv, pt$cv),
                   weight_ess_fraction = min(py$ess, pt$ess)))
}

fit_weighted_gformula <- function(data, scen, variant, method, obs, type) {
  if (!obs$ok) return(result_template(method, variant, obs$stage, 'observation'))
  ws <- build_weight_system(data, obs, type)
  if (is.null(ws)) return(result_template(method, variant, 'normalization-or-calibration', 'weights'))
  n <- data$n
  jt <- ws$dt$R == 1L & ws$dt$Rprev == 1L & ws$wt > 0
  jy <- ws$dy$R == 1L & ws$wy > 0
  tr <- ws$dt[jt]
  ev <- ws$dy[jy]
  if (!nrow(tr) || !nrow(ev) ||
      !required_cells_ok(tr$Aprev, tr$Lprev, tr$Ltrue) ||
      !required_cells_ok(ev$A, ev$Ltrue, ev$y)) {
    return(result_template(method, variant, 'unsupported-cell', 'weighted-regression'))
  }
  ft <- safe_binomial_fit(transition_x(tr, scen, variant), tr$Ltrue, tr$id, n,
                          weights = ws$wt[jt])
  fy <- safe_binomial_fit(outcome_x(ev, scen, variant), ev$y, ev$id, n,
                          weights = ws$wy[jy])
  if (!ft$ok) return(result_template(method, variant, ft$stage, 'transition'))
  if (!fy$ok) return(result_template(method, variant, fy$stage, 'outcome'))
  base <- baseline_information(data$long, n)

  pn <- ws$p
  pt <- length(ft$beta)
  py <- length(fy$beta)
  p <- pn + pt + py + 15L
  score <- cbind(ws$score, ft$score, fy$score, base$score)
  A <- matrix(0, p, p)
  inuis <- seq_len(pn)
  itr <- pn + seq_len(pt)
  iout <- pn + pt + seq_len(py)
  ib <- pn + pt + py + seq_len(15L)
  A[inuis, inuis] <- ws$A
  A[itr, itr] <- ft$bread
  A[iout, iout] <- fy$bread
  A[ib, ib] <- base$bread
  rt <- tr$Ltrue - ft$mu
  ry <- ev$y - fy$mu
  A[itr, inuis] <- -crossprod(transition_x(tr, scen, variant) * rt,
                               ws$dwt[jt, , drop = FALSE])
  A[iout, inuis] <- -crossprod(outcome_x(ev, scen, variant) * ry,
                                ws$dwy[jy, , drop = FALSE])

  ## Critique fix: every monthly normalization, post-cap renormalization, and
  ## calibration multiplier has an equation in this stack. The capped analysis
  ## shares only the observation fit and is independent of any raw-regression
  ## or raw-sandwich failure.
  Ainv <- safe_inverse(A)
  if (is.null(Ainv)) return(result_template(method, variant, 'singular-stack', 'variance'))
  V <- Ainv %*% crossprod(score) %*% t(Ainv)
  theta <- c(rep(0, pn), ft$beta, fy$beta, base$q)
  fn <- function(z) fitted_intervention_risks(z[itr], z[iout], z[ib], scen, variant)$value
  G <- numeric_gradient(fn, theta)
  VV <- G %*% V %*% t(G)
  ses <- sqrt(pmax(0, diag(VV))); names(ses) <- ESTIMANDS
  risks <- fitted_intervention_risks(ft$beta, fy$beta, base$q, scen, variant)
  diag <- c(obs$diag, ws$diag)
  rows_from_fit(method, variant, risks$value, ses, risks, diag = diag)
}

measurement_x <- function(d, scen, variant) {
  X <- cbind(1, d$lastL_pre, d$B, d$C, d$Aprev, d$time)
  colnames(X) <- c('intercept', 'lastL', 'B', 'C', 'Aprev', 'time')
  if (variant == 'aware' && isTRUE(scen$dep_transition)) {
    X <- cbind(X, d$lastL_pre * d$C, d$sin_time)
    colnames(X)[(ncol(X) - 1):ncol(X)] <- c('lastL_C', 'sin_time')
  }
  X
}

visit_outcome_x <- function(d, scen, variant) {
  X <- cbind(1, d$Llocf, d$gap, d$R, d$C, d$B, d$A, d$A * d$Llocf)
  colnames(X) <- c('intercept', 'lastL', 'gap', 'R', 'C', 'B', 'A', 'A_lastL')
  if (variant == 'aware' && isTRUE(scen$dep_treatment_outcome)) {
    X <- cbind(X, d$A * d$C, d$sin_time)
    colnames(X)[(ncol(X) - 1):ncol(X)] <- c('A_C', 'sin_time')
  }
  X
}

visit_intervention_risks <- function(bo, bm, by, q, scen, variant) {
  base <- baseline_cells(); base$prob <- c(q, 1 - sum(q))
  one <- function(a) {
    x <- base
    x$lastL <- x$L0; x$gap <- 0; x$Rprev <- 1L
    d0 <- data.frame(Llocf = x$lastL, gap = 0, R = 1, C = x$C,
                     B = x$B, A = a, sin_time = 0)
    py <- expit(drop(visit_outcome_x(d0, scen, variant) %*% by))
    x$prob <- x$prob * (1 - py)
    risk <- numeric(24L); risk[1] <- 1 - sum(x$prob)
    for (t in 1:23) {
      x$gap_pre <- pmin(12, x$gap + 1)
      od <- data.frame(B = x$B, F = x$F, C = x$C, Aprev = a,
                       Rprev = x$Rprev, lastL_pre = x$lastL,
                       gap_pre = x$gap_pre, time = t / 24,
                       time2 = (t / 24)^2, sin_time = sin(pi * t / 24))
      pr <- stats::binomial(if (variant == 'aware' && scen$dep_observation) 'cloglog' else 'logit')$linkinv(
        drop(obs_x(od, scen, variant) %*% bo))
      x <- branch_binary(x, pr, 'R')
      md <- data.frame(lastL_pre = x$lastL, B = x$B, C = x$C,
                       Aprev = a, time = t / 24, sin_time = sin(pi * t / 24))
      pm <- expit(drop(measurement_x(md, scen, variant) %*% bm))
      observed <- x$R == 1L
      if (any(observed)) {
        xo <- branch_binary(x[observed, , drop = FALSE], pm[observed], 'newL')
        xu <- x[!observed, , drop = FALSE]
        xu$newL <- xu$lastL
        x <- rbind(xo, xu)
      } else x$newL <- x$lastL
      x$lastL <- ifelse(x$R == 1L, x$newL, x$lastL)
      x$gap <- ifelse(x$R == 1L, 0, x$gap_pre)
      yd <- data.frame(Llocf = x$lastL, gap = x$gap, R = x$R,
                       C = x$C, B = x$B, A = a,
                       sin_time = sin(pi * t / 24))
      py <- expit(drop(visit_outcome_x(yd, scen, variant) %*% by))
      x$prob <- x$prob * (1 - py)
      x$Rprev <- x$R
      x$newL <- x$R <- x$gap_pre <- NULL
      x <- stats::aggregate(prob ~ B + F + C + L0 + cell + lastL + gap + Rprev,
                            data = x, FUN = sum)
      risk[t + 1L] <- 1 - sum(x$prob)
    }
    risk
  }
  r1 <- one(1L); r0 <- one(0L)
  list(value = c(rd12 = r1[12] - r0[12], rd24 = r1[24] - r0[24],
                 log_rr24 = log(r1[24] / r0[24])),
       risk1 = c(rd12 = r1[12], rd24 = r1[24], log_rr24 = r1[24]),
       risk0 = c(rd12 = r0[12], rd24 = r0[24], log_rr24 = r0[24]))
}

fit_visit_process <- function(data, scen, variant, obs) {
  method <- 'visit_process'
  if (!obs$ok) return(result_template(method, variant, obs$stage, 'observation'))
  n <- data$n; dat <- data$long
  dm <- dat[t > 0L & R == 1L]
  if (!nrow(dm)) return(result_template(method, variant, 'no-measurements', 'measurement'))
  fm <- safe_binomial_fit(measurement_x(dm, scen, variant), dm$Ltrue, dm$id, n)
  fy <- safe_binomial_fit(visit_outcome_x(dat, scen, variant), dat$y, dat$id, n)
  if (!fm$ok) return(result_template(method, variant, fm$stage, 'measurement'))
  if (!fy$ok) return(result_template(method, variant, fy$stage, 'outcome'))
  base <- baseline_information(dat, n)
  score <- cbind(obs$score, fm$score, fy$score, base$score)
  dims <- c(length(obs$beta), length(fm$beta), length(fy$beta), 15L)
  ends <- cumsum(dims); starts <- c(1L, head(ends, -1L) + 1L)
  ii <- Map(seq, starts, ends)
  A <- matrix(0, sum(dims), sum(dims))
  A[ii[[1]], ii[[1]]] <- obs$bread
  A[ii[[2]], ii[[2]]] <- fm$bread
  A[ii[[3]], ii[[3]]] <- fy$bread
  A[ii[[4]], ii[[4]]] <- base$bread
  Ainv <- safe_inverse(A)
  if (is.null(Ainv)) return(result_template(method, variant, 'singular-stack', 'variance'))
  V <- Ainv %*% crossprod(score) %*% t(Ainv)
  theta <- c(obs$beta, fm$beta, fy$beta, base$q)
  fn <- function(z) visit_intervention_risks(z[ii[[1]]], z[ii[[2]]],
                                             z[ii[[3]]], z[ii[[4]]],
                                             scen, variant)$value
  G <- numeric_gradient(fn, theta)
  ses <- sqrt(pmax(0, diag(G %*% V %*% t(G)))); names(ses) <- ESTIMANDS
  risks <- visit_intervention_risks(obs$beta, fm$beta, fy$beta, base$q, scen, variant)
  rows_from_fit(method, variant, risks$value, ses, risks, diag = obs$diag)
}

latent_layout <- function(scen, variant, mar = FALSE) {
  base <- c('base_0', 'base_B', 'base_C', 'base_F')
  tr <- c('tr_0', 'tr_Lprev', 'tr_B', 'tr_C', 'tr_Aprev', 'tr_time')
  if (variant == 'aware' && scen$dep_transition) tr <- c(tr, 'tr_Lprev2', 'tr_Lprev_C')
  if (mar) {
    ob <- c('ob_0', 'ob_B', 'ob_F', 'ob_C', 'ob_Aprev', 'ob_Rprev',
            'ob_lastL', 'ob_gap', 'ob_time', 'ob_time2')
    if (variant == 'aware' && scen$dep_observation) ob <- c(ob, 'ob_lastL_C', 'ob_sin')
  } else {
    ob <- c('ob_0', 'ob_L', 'ob_Aprev', 'ob_Rprev', 'ob_C')
    if (variant == 'aware' && scen$dep_observation) ob <- c(ob, 'ob_L_C', 'ob_sin')
  }
  at <- c('a_0', 'a_Aprev', 'a_L', 'a_C', 'a_B', 'a_R')
  if (variant == 'aware' && scen$dep_treatment_outcome) at <- c(at, 'a_L_C', 'a_time2')
  yy <- c('y_0', 'y_L', 'y_C', 'y_B', 'y_A', 'y_A_L')
  if (variant == 'aware' && scen$dep_treatment_outcome) yy <- c(yy, 'y_A_C', 'y_sin')
  names <- c(base, tr, ob, at, yy)
  list(names = names,
       base = match(base, names), tr = match(tr, names), ob = match(ob, names),
       at = match(at, names), yy = match(yy, names), mar = mar)
}

latent_designs <- function(scen, variant, mar, t, L, Lprev, Lprev2,
                           Aprev, Rprev, R, B, F, C, lastL, gap) {
  tr <- cbind(1, Lprev, B, C, Aprev, t / 24)
  if (variant == 'aware' && scen$dep_transition) tr <- cbind(tr, Lprev2, Lprev * C)
  if (mar) {
    ob <- cbind(1, B, F, C, Aprev, Rprev, lastL, gap, t / 24, (t / 24)^2)
    if (variant == 'aware' && scen$dep_observation) ob <- cbind(ob, lastL * C, sin(pi * t / 24))
  } else {
    ob <- cbind(1, L, Aprev, Rprev, C)
    if (variant == 'aware' && scen$dep_observation) ob <- cbind(ob, L * C, sin(pi * t / 24))
  }
  at <- cbind(1, Aprev, L, C, B, R)
  if (variant == 'aware' && scen$dep_treatment_outcome) at <- cbind(at, L * C, (t / 24)^2)
  yy <- cbind(1, L, C, B, R * 0 + 1, L)
  list(tr = tr, ob = ob, at = at, yy = yy)
}

bern_likelihood <- function(y, p) ifelse(y == 1L, p, 1 - p)

latent_forward <- function(theta, data, scen, variant, mar = FALSE, keep = FALSE) {
  w <- data$wide; n <- data$n; lay <- latent_layout(scen, variant, mar)
  bb <- theta[lay$base]; bt <- theta[lay$tr]; bo <- theta[lay$ob]
  ba <- theta[lay$at]; by <- theta[lay$yy]
  baseX <- cbind(1, w$B, w$C, w$F)
  pbase <- expit(drop(baseX %*% bb))
  alpha <- cbind((w$L0 == 0L) * (1 - pbase), (w$L0 == 1L) * pbase)
  filters <- if (keep) vector('list', 24L) else NULL
  loglik <- numeric(n)

  emission <- function(t, Lstate) {
    j <- t + 1L
    Aprev <- if (t == 0L) 0L else w$A[, j - 1L]
    Rprev <- if (t == 0L) 1L else w$R[, j - 1L]
    Rcur <- w$R[, j]
    if (mar) {
      d <- data.frame(B = w$B, F = w$F, C = w$C, Aprev = Aprev,
                      Rprev = Rprev, lastL_pre = w$last_pre[, j],
                      gap_pre = w$gap_pre[, j], time = t / 24,
                      time2 = (t / 24)^2, sin_time = sin(pi * t / 24))
      po <- stats::binomial(if (variant == 'aware' && scen$dep_observation) 'cloglog' else 'logit')$linkinv(
        drop(obs_x(d, scen, variant) %*% bo))
    } else {
      xo <- cbind(1, Lstate, Aprev, Rprev, w$C)
      if (variant == 'aware' && scen$dep_observation) xo <- cbind(xo, Lstate * w$C, sin(pi * t / 24))
      po <- stats::binomial(if (variant == 'aware' && scen$dep_observation) 'cloglog' else 'logit')$linkinv(drop(xo %*% bo))
    }
    xa <- cbind(1, Aprev, Lstate, w$C, w$B, Rcur)
    if (variant == 'aware' && scen$dep_treatment_outcome) xa <- cbind(xa, Lstate * w$C, (t / 24)^2)
    pa <- expit(drop(xa %*% ba))
    xy <- cbind(1, Lstate, w$C, w$B, w$A[, j], w$A[, j] * Lstate)
    if (variant == 'aware' && scen$dep_treatment_outcome) xy <- cbind(xy, w$A[, j] * w$C, sin(pi * t / 24))
    py <- expit(drop(xy %*% by))
    e <- bern_likelihood(w$A[, j], pa) * bern_likelihood(w$Y[, j], py)
    if (t > 0L) {
      e <- e * bern_likelihood(Rcur, po)
      e <- e * ifelse(Rcur == 1L, as.integer(w$Lobs[, j] == Lstate), 1)
    }
    e[!w$risk[, j]] <- 1
    clamp_probability(e)
  }

  for (s in 0:1) alpha[, s + 1L] <- alpha[, s + 1L] * emission(0L, s)
  sc <- rowSums(alpha); loglik <- log(sc); alpha <- alpha / sc
  if (keep) filters[[1]] <- alpha

  second <- variant == 'aware' && isTRUE(scen$dep_transition)
  if (!second) {
    for (t in 1:23) {
      j <- t + 1L; active <- w$risk[, j] == 1L
      nexta <- matrix(0, n, 2L)
      for (lp in 0:1) {
        xt <- cbind(1, lp, w$B, w$C, w$A[, j - 1L], t / 24)
        pL <- expit(drop(xt %*% bt))
        nexta[, 1] <- nexta[, 1] + alpha[, lp + 1L] * (1 - pL)
        nexta[, 2] <- nexta[, 2] + alpha[, lp + 1L] * pL
      }
      for (s in 0:1) nexta[, s + 1L] <- nexta[, s + 1L] * emission(t, s)
      sc <- rowSums(nexta)
      loglik[active] <- loglik[active] + log(sc[active])
      alpha[active, ] <- nexta[active, , drop = FALSE] / sc[active]
      if (keep) filters[[j]] <- alpha
    }
  } else {
    pair_prev <- rep(0:1, each = 2L); pair_cur <- rep(0:1, times = 2L)
    t <- 1L; j <- 2L
    nexta <- matrix(0, n, 4L)
    for (k in 1:4) {
      lp <- pair_prev[k]; lc <- pair_cur[k]
      xt <- cbind(1, lp, w$B, w$C, w$A[, 1], t / 24, lp, lp * w$C)
      pL <- expit(drop(xt %*% bt))
      nexta[, k] <- alpha[, lp + 1L] * ifelse(lc == 1L, pL, 1 - pL) * emission(t, lc)
    }
    sc <- rowSums(nexta); active <- w$risk[, j] == 1L
    loglik[active] <- loglik[active] + log(sc[active])
    nexta[active, ] <- nexta[active, , drop = FALSE] / sc[active]
    alpha4 <- nexta
    if (keep) filters[[j]] <- alpha4
    for (t in 2:23) {
      j <- t + 1L; active <- w$risk[, j] == 1L
      nexta <- matrix(0, n, 4L)
      for (k in 1:4) {
        lp2 <- pair_prev[k]; lp <- pair_cur[k]
        xt <- cbind(1, lp, w$B, w$C, w$A[, j - 1L], t / 24,
                    lp2, lp * w$C)
        pL <- expit(drop(xt %*% bt))
        for (lc in 0:1) {
          knew <- 1L + 2L * lp + lc
          nexta[, knew] <- nexta[, knew] + alpha4[, k] *
            ifelse(lc == 1L, pL, 1 - pL) * emission(t, lc)
        }
      }
      sc <- rowSums(nexta)
      loglik[active] <- loglik[active] + log(sc[active])
      alpha4[active, ] <- nexta[active, , drop = FALSE] / sc[active]
      if (keep) filters[[j]] <- alpha4
    }
  }
  if (any(!is.finite(loglik))) loglik[] <- -Inf
  list(loglik = loglik, filters = filters, layout = lay, second = second)
}

latent_start <- function(scen, variant, mar) {
  lay <- latent_layout(scen, variant, mar)
  z <- setNames(numeric(length(lay$names)), lay$names)
  z[lay$base] <- c(-1.2, 0.55, 0.80, -0.15)
  z[lay$tr][seq_len(6)] <- c(-1.2, scen$beta_LL, 0.45, 0.70, -0.55, 0.10)
  if (mar) {
    z[lay$ob][1] <- scen$alpha
  } else {
    z[lay$ob][seq_len(5)] <- c(scen$alpha, scen$gamma_L, scen$gamma_A, 0.405, 0.30)
  }
  z[lay$at][seq_len(6)] <- c(-1.15, 1.60, scen$beta_AL, 0.35, 0.20, 0.25)
  z[lay$yy][seq_len(6)] <- c(-5.10, scen$beta_YL, 0.40, 0.25, -0.50, scen$beta_YAL)
  z
}

fit_latent_model <- function(data, scen, variant, mar = FALSE) {
  start <- latent_start(scen, variant, mar)
  lay <- latent_layout(scen, variant, mar)
  lower <- rep(-10, length(start)); upper <- rep(10, length(start))
  gamma_index <- if (!mar) match('ob_L', lay$names) else NA_integer_
  if (!is.na(gamma_index)) { lower[gamma_index] <- -3; upper[gamma_index] <- 3 }
  starts <- if (mar) list(start) else lapply(c(0, 0.693147, 1.386294), function(g) {
    s <- start; s[gamma_index] <- g; s
  })
  objective <- function(th) -sum(latent_forward(th, data, scen, variant, mar)$loglik)
  fits <- lapply(starts, function(s) try(stats::optim(
    s, objective, method = 'L-BFGS-B', lower = lower, upper = upper,
    control = list(maxit = 350, factr = 1e7, pgtol = 1e-8)), silent = TRUE))
  good <- vapply(fits, function(f) !inherits(f, 'try-error') && f$convergence == 0L && is.finite(f$value), logical(1))
  if (!any(good)) return(list(ok = FALSE, stage = 'likelihood-optimization'))
  fit <- fits[[which.min(vapply(fits, function(f) if (inherits(f, 'try-error')) Inf else f$value, numeric(1)))]]
  theta <- fit$par
  score_total <- numeric(length(theta))
  score_ind <- matrix(NA_real_, data$n, length(theta))
  for (j in seq_along(theta)) {
    h <- 1e-5 * max(1, abs(theta[j])); up <- down <- theta
    up[j] <- up[j] + h; down[j] <- down[j] - h
    sp <- latent_forward(up, data, scen, variant, mar)$loglik
    sm <- latent_forward(down, data, scen, variant, mar)$loglik
    score_ind[, j] <- (sp - sm) / (2 * h)
    score_total[j] <- sum(score_ind[, j])
  }
  if (max(abs(score_total)) > 1e-4) return(list(ok = FALSE, stage = 'likelihood-score'))
  H <- try(stats::optimHess(theta, objective), silent = TRUE)
  if (inherits(H, 'try-error') || any(!is.finite(H))) return(list(ok = FALSE, stage = 'hessian'))
  cond <- try(kappa(H, exact = FALSE), silent = TRUE)
  if (inherits(cond, 'try-error') || !is.finite(cond) || cond > COND_LIMIT) return(list(ok = FALSE, stage = 'hessian-condition'))
  Hi <- safe_inverse(H)
  if (is.null(Hi)) return(list(ok = FALSE, stage = 'hessian-singular'))
  boundary <- if (!is.na(gamma_index)) abs(theta[gamma_index] - lower[gamma_index]) < 0.01 ||
    abs(theta[gamma_index] - upper[gamma_index]) < 0.01 else FALSE
  if (boundary) return(list(ok = FALSE, stage = 'gamma-boundary'))
  profile_drop <- NA_real_
  if (!is.na(gamma_index)) {
    pp <- theta; pm <- theta
    pp[gamma_index] <- min(upper[gamma_index], theta[gamma_index] + 0.25)
    pm[gamma_index] <- max(lower[gamma_index], theta[gamma_index] - 0.25)
    profile_drop <- min(objective(pp), objective(pm)) - objective(theta)
  }
  list(ok = TRUE, theta = theta, layout = lay, H = H, Hinv = Hi,
       score = score_ind, gamma_index = gamma_index,
       profile_drop = profile_drop)
}

latent_risks <- function(theta, layout, q, scen, variant) {
  fitted_intervention_risks(theta[layout$tr], theta[layout$yy], q, scen, variant)
}

fit_joint_latent <- function(data, scen, variant) {
  method <- 'joint_latent'
  fit <- fit_latent_model(data, scen, variant, mar = FALSE)
  if (!fit$ok) return(result_template(method, variant, fit$stage, fit$stage))
  base <- baseline_information(data$long, data$n)
  ptheta <- length(fit$theta)
  score <- cbind(fit$score, base$score)
  A <- matrix(0, ptheta + 15L, ptheta + 15L)
  A[seq_len(ptheta), seq_len(ptheta)] <- fit$H
  ib <- ptheta + seq_len(15L); A[ib, ib] <- base$bread
  Ainv <- safe_inverse(A)
  if (is.null(Ainv)) return(result_template(method, variant, 'singular-stack', 'variance'))
  V <- Ainv %*% crossprod(score) %*% t(Ainv)
  theta <- c(fit$theta, base$q)
  fn <- function(z) latent_risks(z[seq_len(ptheta)], fit$layout, z[ib], scen, variant)$value
  G <- numeric_gradient(fn, theta)
  ses <- sqrt(pmax(0, diag(G %*% V %*% t(G)))); names(ses) <- ESTIMANDS
  risks <- latent_risks(fit$theta, fit$layout, base$q, scen, variant)
  gi <- fit$gamma_index
  gamma_se <- sqrt(fit$Hinv[gi, gi])
  rows_from_fit(method, variant, risks$value, ses, risks,
    diag = list(gamma_l_hat = fit$theta[gi], gamma_l_se = gamma_se,
                gamma_boundary = 0, profile_drop = fit$profile_drop,
                max_gap = data$max_gap))
}

sample_states_ffbs <- function(theta, data, scen, variant, mar_fit) {
  fw <- latent_forward(theta, data, scen, variant, mar = TRUE, keep = TRUE)
  w <- data$wide; n <- data$n
  last <- rowSums(w$risk) - 1L
  L <- matrix(NA_integer_, n, 24L)
  L[, 1] <- w$L0
  lay <- mar_fit$layout; bt <- theta[lay$tr]

  if (!fw$second) {
    for (t in 23:0) {
      j <- t + 1L
      at_end <- last == t
      if (any(at_end)) {
        p1 <- fw$filters[[j]][at_end, 2]
        L[at_end, j] <- as.integer(stats::runif(sum(at_end)) < p1)
      }
      continuation <- last > t
      if (t < 23L && any(continuation)) {
        nxt <- L[continuation, j + 1L]
        Aprev <- w$A[continuation, j]
        x0 <- cbind(1, 0, w$B[continuation], w$C[continuation], Aprev, (t + 1L) / 24)
        x1 <- cbind(1, 1, w$B[continuation], w$C[continuation], Aprev, (t + 1L) / 24)
        p0n <- expit(drop(x0 %*% bt)); p1n <- expit(drop(x1 %*% bt))
        trans0 <- ifelse(nxt == 1L, p0n, 1 - p0n)
        trans1 <- ifelse(nxt == 1L, p1n, 1 - p1n)
        a <- fw$filters[[j]][continuation, ]
        pr1 <- a[, 2] * trans1 / (a[, 1] * trans0 + a[, 2] * trans1)
        L[continuation, j] <- as.integer(stats::runif(sum(continuation)) < pr1)
      }
    }
  } else {
    pair_prev <- rep(0:1, each = 2L); pair_cur <- rep(0:1, times = 2L)
    for (t in 23:1) {
      j <- t + 1L
      at_end <- last == t
      if (any(at_end)) {
        a <- fw$filters[[j]][at_end, , drop = FALSE]
        u <- stats::runif(sum(at_end))
        k <- 1L + rowSums(u > t(apply(a, 1, cumsum)))
        L[at_end, j - 1L] <- pair_prev[k]
        L[at_end, j] <- pair_cur[k]
      }
      continuation <- last > t
      if (t < 23L && any(continuation)) {
        lp <- L[continuation, j]
        ln <- L[continuation, j + 1L]
        a <- fw$filters[[j]][continuation, , drop = FALSE]
        k0 <- 1L + lp
        k1 <- 3L + lp
        x0 <- cbind(1, lp, w$B[continuation], w$C[continuation],
                    w$A[continuation, j], (t + 1L) / 24, 0, lp * w$C[continuation])
        x1 <- x0; x1[, 7] <- 1
        p0 <- expit(drop(x0 %*% bt)); p1 <- expit(drop(x1 %*% bt))
        q0 <- a[cbind(seq_len(sum(continuation)), k0)] * ifelse(ln == 1L, p0, 1 - p0)
        q1 <- a[cbind(seq_len(sum(continuation)), k1)] * ifelse(ln == 1L, p1, 1 - p1)
        draw <- as.integer(stats::runif(sum(continuation)) < q1 / (q0 + q1))
        L[continuation, j - 1L] <- draw
      }
    }
  }
  observed <- !is.na(w$Lobs)
  L[observed] <- w$Lobs[observed]
  L
}

fit_mar_mi <- function(data, scen, variant, m) {
  method <- 'mar_mi'
  latent <- fit_latent_model(data, scen, variant, mar = TRUE)
  if (!latent$ok) return(result_template(method, variant, latent$stage, 'likelihood'))
  Q <- U <- matrix(NA_real_, m, 3L, dimnames = list(NULL, ESTIMANDS))
  risks_acc <- NULL
  for (j in seq_len(m)) {
    draw <- NULL
    for (attempt in 1:3) {
      candidate <- try(drop(mvtnorm::rmvnorm(1L, latent$theta, latent$Hinv)), silent = TRUE)
      if (!inherits(candidate, 'try-error') && all(is.finite(candidate))) { draw <- candidate; break }
    }
    if (is.null(draw)) return(result_template(method, variant, 'parameter-draw', 'draw'))
    L <- try(sample_states_ffbs(draw, data, scen, variant, latent), silent = TRUE)
    if (inherits(L, 'try-error')) return(result_template(method, variant, 'path-generation', 'path'))
    completed <- data
    d <- data.table::copy(data$long)
    d[, Limp := L[cbind(id, t + 1L)]]
    d[, Limp_prev := ifelse(t == 0L, L0, L[cbind(id, t)])]
    d[, Limp_prev2 := ifelse(t < 2L, L0, L[cbind(id, t - 1L)])]
    completed$long <- d
    rr <- fit_standard_gformula(completed, scen, variant, method, 'imputed')
    if (any(!is.na(rr$fail))) return(result_template(method, variant, 'completed-analysis', 'completed-analysis'))
    Q[j, ] <- rr$est
    U[j, ] <- rr$se^2
    risks_acc <- if (is.null(risks_acc)) cbind(rr$risk1, rr$risk0) else
      risks_acc + cbind(rr$risk1, rr$risk0)
  }
  qbar <- colMeans(Q); ubar <- colMeans(U); between <- apply(Q, 2, stats::var)
  total <- ubar + (1 + 1 / m) * between
  if (any(!is.finite(total)) || any(total < 0)) return(result_template(method, variant, 'rubin-combination', 'combination'))
  dfs <- rep(Inf, 3L)
  positive <- between > .Machine$double.eps
  dfs[positive] <- (m - 1) * (1 + ubar[positive] / ((1 + 1 / m) * between[positive]))^2
  names(qbar) <- names(total) <- ESTIMANDS
  risks <- list(risk1 = setNames(risks_acc[, 1] / m, ESTIMANDS),
                risk0 = setNames(risks_acc[, 2] / m, ESTIMANDS))
  out <- rows_from_fit(method, variant, qbar, sqrt(total), risks, dfs = dfs,
                       diag = list(max_gap = data$max_gap))
  out$profile_drop <- mean((1 + 1 / m) * between / total)
  out
}

estimate_replicate <- function(data, scen, variant, mi_m) {
  jobs <- list(
    oracle = function() fit_standard_gformula(data, scen, variant, 'oracle', 'oracle'),
    complete_record = function() fit_standard_gformula(data, scen, variant, 'complete_record', 'complete'),
    locf = function() fit_standard_gformula(data, scen, variant, 'locf', 'locf')
  )
  out <- list()
  for (nm in names(jobs)) {
    t0 <- proc.time()[['elapsed']]
    out[[nm]] <- tryCatch(jobs[[nm]](), error = function(e) result_template(nm, variant, 'uncaught-error', 'estimator'))
    out[[nm]]$runtime_sec <- proc.time()[['elapsed']] - t0
  }

  obs <- fit_observation_model(data, scen, variant)
  weighted <- list(iiw_raw = 'raw', iiw_capped = 'capped', iiw_calibrated = 'calibrated')
  for (nm in names(weighted)) {
    t0 <- proc.time()[['elapsed']]
    out[[nm]] <- tryCatch(fit_weighted_gformula(data, scen, variant, nm, obs, weighted[[nm]]),
                          error = function(e) result_template(nm, variant, 'uncaught-error', 'weights'))
    out[[nm]]$runtime_sec <- proc.time()[['elapsed']] - t0
  }
  t0 <- proc.time()[['elapsed']]
  out$visit_process <- tryCatch(fit_visit_process(data, scen, variant, obs),
                                error = function(e) result_template('visit_process', variant, 'uncaught-error', 'visit-process'))
  out$visit_process$runtime_sec <- proc.time()[['elapsed']] - t0

  t0 <- proc.time()[['elapsed']]
  out$joint_latent <- tryCatch(fit_joint_latent(data, scen, variant),
                               error = function(e) result_template('joint_latent', variant, 'uncaught-error', 'joint-likelihood'))
  out$joint_latent$runtime_sec <- proc.time()[['elapsed']] - t0

  t0 <- proc.time()[['elapsed']]
  out$mar_mi <- tryCatch(fit_mar_mi(data, scen, variant, mi_m),
                         error = function(e) result_template('mar_mi', variant, 'uncaught-error', 'mi'))
  out$mar_mi$runtime_sec <- proc.time()[['elapsed']] - t0

  ans <- do.call(rbind, out[METHODS])
  ans$memory_mb <- sum(gc()[, 2])
  rownames(ans) <- NULL
  ans
}
