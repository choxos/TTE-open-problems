## MER-01: estimators, exact filtering, and latent-state correction.

empty_estimate <- function(why) {
  data.frame(
    contrast = CONTRASTS, est = NA_real_, se = NA_real_, lo = NA_real_,
    hi = NA_real_, ess_0 = NA_real_, ess_1 = NA_real_,
    median_weight = NA_real_, p99_weight = NA_real_,
    adherence_0 = NA_real_, adherence_1 = NA_real_,
    censor_change_L = NA_real_, interval_df = NA_real_, fail = why,
    stringsAsFactors = FALSE
  )
}

weighted_quantile <- function(x, p) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  unname(stats::quantile(x, p, names = FALSE, type = 8))
}

ess <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w) || sum(w * w) == 0) return(NA_real_)
  sum(w)^2 / sum(w * w)
}

first_deviation <- function(A, required) {
  d <- A != required
  any <- rowSums(d) > 0L
  z <- rep(N_MONTHS + 1L, nrow(A))
  z[any] <- max.col(d[any, , drop = FALSE], ties.method = 'first')
  z
}

cluster_score <- function(block, beta, n) {
  eta <- drop(block$X %*% beta)
  p <- expit(eta)
  s <- block$X * (block$y - p)
  if (is.null(block$id)) return(s)
  z <- rowsum(s, block$id, reorder = FALSE)
  out <- matrix(0, n, ncol(block$X))
  out[as.integer(rownames(z)), ] <- z
  out
}

numeric_bread <- function(block, beta, n) {
  q <- length(beta)
  A <- matrix(NA_real_, q, q)
  for (j in seq_len(q)) {
    h <- BREAD_STEP * (1 + abs(beta[j]))
    bp <- bm <- beta
    bp[j] <- bp[j] + h
    bm[j] <- bm[j] - h
    A[, j] <- -(colMeans(cluster_score(block, bp, n)) -
                  colMeans(cluster_score(block, bm, n))) / (2 * h)
  }
  (A + t(A)) / 2
}

fit_block <- function(X, y, n, id = NULL) {
  fit <- try(suppressWarnings(stats::glm.fit(X, y, family = stats::binomial())),
             silent = TRUE)
  if (inherits(fit, 'try-error') || !isTRUE(fit$converged) ||
      fit$rank != ncol(X) || any(!is.finite(fit$coefficients)) ||
      any(!is.finite(fit$fitted.values)))
    return(list(fail = 'propensity-fit-failed'))
  block <- list(X = X, y = y, id = id, beta = fit$coefficients)
  block$score <- cluster_score(block, block$beta, n)
  block$bread <- numeric_bread(block, block$beta, n)
  kap <- try(kappa(block$bread, exact = TRUE), silent = TRUE)
  if (inherits(kap, 'try-error') || !is.finite(kap) || kap > BREAD_KAPPA_MAX)
    return(list(fail = 'bread-ill-conditioned'))
  block$condition <- kap
  block$fitted <- fit$fitted.values
  block$fail <- NULL
  block
}

fit_first_order <- function(A, L, dat) {
  n <- nrow(A)
  X0 <- cbind(1, L[, 1], dat$X1, dat$X2, dat$X3)
  b0 <- fit_block(X0, A[, 1], n)
  if (!is.null(b0$fail)) return(list(fail = b0$fail))

  id <- rep(seq_len(n), N_MONTHS - 1L)
  month <- rep(seq_len(N_MONTHS - 1L), each = n)
  Xf <- cbind(1, as.vector(A[, -N_MONTHS, drop = FALSE]),
              as.vector(L[, -1L, drop = FALSE]),
              rep(dat$X1, N_MONTHS - 1L),
              rep(dat$X2, N_MONTHS - 1L),
              rep(dat$X3, N_MONTHS - 1L), month)
  yf <- as.vector(A[, -1L, drop = FALSE])
  bf <- fit_block(Xf, yf, n, id)
  if (!is.null(bf$fail)) return(list(fail = bf$fail))

  p <- matrix(NA_real_, n, N_MONTHS)
  p[, 1] <- b0$fitted
  p[, -1L] <- matrix(bf$fitted, n)
  list(p = p, blocks = list(b0, bf), fail = NULL)
}

run_length_matrix <- function(x) {
  z <- matrix(1, nrow(x), ncol(x))
  if (ncol(x) > 1L)
    for (tt in 2:ncol(x))
      z[, tt] <- ifelse(x[, tt] == x[, tt - 1L], z[, tt - 1L] + 1, 1)
  z
}

interaction_columns <- function(V) {
  if (ncol(V) < 2L) return(matrix(numeric(0), nrow(V), 0L))
  cmb <- utils::combn(seq_len(ncol(V)), 2L)
  z <- vapply(seq_len(ncol(cmb)), function(j)
    V[, cmb[1, j]] * V[, cmb[2, j]], numeric(nrow(V)))
  if (is.null(dim(z))) z <- matrix(z, ncol = 1L)
  colnames(z) <- paste(colnames(V)[cmb[1, ]], colnames(V)[cmb[2, ]], sep = ':')
  z
}

rich_matrix <- function(A, L, dat, tt, spline_basis, runA, runL) {
  n <- nrow(A)
  curL <- L[, tt]
  base <- cbind('(Intercept)' = 1, spline_basis,
                X2 = dat$X2, X3 = dat$X3, Lcur = curL,
                X1_hi = as.integer(dat$X1 > 0.5),
                X1_lo = as.integer(dat$X1 < -0.5))
  if (tt > 1L) {
    Ah <- A[, seq_len(tt - 1L), drop = FALSE]
    Lh <- L[, seq_len(tt - 1L), drop = FALSE]
    colnames(Ah) <- paste0('A', seq_len(tt - 1L) - 1L)
    colnames(Lh) <- paste0('L', seq_len(tt - 1L) - 1L)
    base <- cbind(base, Ah, Lh,
                  runA = runA[, tt - 1L], runL = runL[, tt])
    ## The numeric cumulative counts are exact linear combinations of the full
    ## prior histories already present. Their duplicate columns are omitted at
    ## construction, which leaves the specified prediction space unchanged and
    ## avoids manufacturing the rank deficiency the protocol forbids.
    recent <- cbind(Lcur = curL,
                    A_lag1 = A[, tt - 1L],
                    L_lag1 = L[, tt - 1L],
                    X2 = dat$X2, X3 = dat$X3)
    if (tt > 2L)
      recent <- cbind(recent, A_lag2 = A[, tt - 2L],
                      L_lag2 = L[, tt - 2L])
  } else {
    recent <- cbind(Lcur = curL, X2 = dat$X2, X3 = dat$X3)
  }
  cbind(base, interaction_columns(recent))
}

fit_rich_history <- function(A, L, dat) {
  n <- nrow(A)
  spline_basis <- splines::ns(dat$X1, df = 4)
  colnames(spline_basis) <- paste0('X1_rcs', seq_len(ncol(spline_basis)))
  runA <- run_length_matrix(A)
  runL <- run_length_matrix(L)
  p <- matrix(NA_real_, n, N_MONTHS)
  blocks <- vector('list', N_MONTHS)
  for (tt in seq_len(N_MONTHS)) {
    X <- rich_matrix(A, L, dat, tt, spline_basis, runA, runL)
    b <- fit_block(X, A[, tt], n)
    if (!is.null(b$fail)) return(list(fail = b$fail))
    p[, tt] <- b$fitted
    blocks[[tt]] <- b
  }
  list(p = p, blocks = blocks, fail = NULL)
}

mean_with_if <- function(consistent, w, Y, subgroup, blocks) {
  use <- consistent & subgroup
  D <- mean(ifelse(use, w, 0))
  if (!is.finite(D) || D <= 0) return(list(fail = TRUE))
  mu <- sum(w[use] * Y[use]) / sum(w[use])
  u <- ifelse(use, w * (Y - mu), 0)
  adj <- numeric(length(Y))
  for (b in blocks) {
    G <- -colMeans(b$score * u)
    v <- try(solve(b$bread, G), silent = TRUE)
    if (inherits(v, 'try-error') || any(!is.finite(v)))
      return(list(fail = TRUE))
    adj <- adj + drop(b$score %*% v)
  }
  list(mu = mu, influence = (u + adj) / D, fail = FALSE)
}

risk_estimates <- function(A, L, Y, p, blocks = list(), L_reference = L) {
  n <- nrow(A)
  q <- ifelse(A == 1L, p, 1 - p)
  if (any(!is.finite(q)) || any(q <= 0)) return(empty_estimate('invalid-probability'))
  logw <- -rowSums(log(q))
  if (any(!is.finite(logw))) return(empty_estimate('nonfinite-weight'))
  w <- exp(logw)
  if (any(!is.finite(w))) return(empty_estimate('nonfinite-weight'))

  required <- list(dynamic = L, static = matrix(1L, n, N_MONTHS),
                   zero = matrix(0L, n, N_MONTHS))
  consistent <- lapply(required, function(r) rowSums(A != r) == 0L)
  changed <- mean(first_deviation(A, L) != first_deviation(A, L_reference))

  specs <- list(
    dynamic = list(one = 'dynamic', zero = 'zero', subgroup = rep(TRUE, n)),
    dynamic_x2_0 = list(one = 'dynamic', zero = 'zero', subgroup = dat_placeholder <- NULL),
    dynamic_x2_1 = list(one = 'dynamic', zero = 'zero', subgroup = dat_placeholder),
    static = list(one = 'static', zero = 'zero', subgroup = rep(TRUE, n))
  )
  specs$dynamic_x2_0$subgroup <- attr(L_reference, 'X2') == 0L
  specs$dynamic_x2_1$subgroup <- attr(L_reference, 'X2') == 1L

  rows <- lapply(names(specs), function(key) {
    z <- specs[[key]]
    r1 <- mean_with_if(consistent[[z$one]], w, Y, z$subgroup, blocks)
    r0 <- mean_with_if(consistent[[z$zero]], w, Y, z$subgroup, blocks)
    if (isTRUE(r1$fail) || isTRUE(r0$fail))
      return(empty_estimate('empty-consistent-arm')[1, , drop = FALSE])
    est <- r1$mu - r0$mu
    se <- stats::sd(r1$influence - r0$influence) / sqrt(n)
    if (!is.finite(se) || se < 0)
      return(empty_estimate('invalid-variance')[1, , drop = FALSE])
    w1 <- w[consistent[[z$one]] & z$subgroup]
    w0 <- w[consistent[[z$zero]] & z$subgroup]
    data.frame(
      contrast = key, est = est, se = se, lo = est - 1.96 * se,
      hi = est + 1.96 * se, ess_0 = ess(w0), ess_1 = ess(w1),
      median_weight = stats::median(c(w0, w1)),
      p99_weight = weighted_quantile(c(w0, w1), 0.99),
      adherence_0 = mean(consistent[[z$zero]] & z$subgroup) / mean(z$subgroup),
      adherence_1 = mean(consistent[[z$one]] & z$subgroup) / mean(z$subgroup),
      censor_change_L = if (key == 'dynamic') changed else NA_real_,
      interval_df = Inf, fail = NA_character_, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  attr(out, 'system_dim') <- sum(vapply(blocks, function(b) ncol(b$X), integer(1))) + 8L
  rownames(out) <- NULL
  out
}

attach_x2 <- function(L, X2) {
  attr(L, 'X2') <- X2
  L
}

normalize_weights <- function(w) {
  good <- is.finite(w) & w > 0
  lw <- matrix(-Inf, nrow(w), ncol(w))
  lw[good] <- log(w[good])
  mx <- rep(-Inf, nrow(w))
  for (j in seq_len(ncol(w))) mx <- pmax(mx, lw[, j])
  bad <- !is.finite(mx)
  z <- exp(lw - mx)
  den <- rowSums(z)
  bad <- bad | !is.finite(den) | den <= 0
  z[!bad, , drop = FALSE] <- z[!bad, , drop = FALSE] / den[!bad]
  list(w = z, bad = bad)
}

state_table <- function(second_order = FALSE) {
  if (second_order) {
    expand.grid(L = 0:1, A = 0:1, eL = 0:1, eA = 0:1,
                lagL = 0:1, lagA = 0:1)
  } else {
    expand.grid(L = 0:1, A = 0:1, eL = 0:1, eA = 0:1)
  }
}

error_transition_probability <- function(new, prev, prev2, p, tt, stress) {
  fresh <- ifelse(new == 1L, p, 1 - p)
  if (!stress || tt == 2L)
    return(0.80 * (new == prev) + 0.20 * fresh)
  0.55 * (new == prev) + 0.25 * (new == prev2) + 0.20 * fresh
}

exact_proxy_probabilities <- function(dat, obs, scen) {
  n <- length(dat$X1)
  stress <- scen$specification == 'error_transition_stress'
  st <- state_table(stress)
  S <- nrow(st)
  pe <- error_probability(scen, dat$X2, dat$X3)
  if (!scen$error_nodes %in% c('L', 'AL')) peL <- rep(0, n) else peL <- pe
  if (!scen$error_nodes %in% c('A', 'AL')) peA <- rep(0, n) else peA <- pe

  pre <- matrix(0, n, S)
  pL0 <- expit(lp_l0(dat$X1, dat$X2))
  for (s in seq_len(S)) {
    valid_lag <- !stress || (st$lagL[s] == st$eL[s] && st$lagA[s] == st$eA[s])
    if (!valid_lag) next
    pl <- ifelse(st$L[s] == 1L, pL0, 1 - pL0)
    pa0 <- expit(lp_a0(st$L[s], dat$X1, dat$X2))
    pa <- ifelse(st$A[s] == 1L, pa0, 1 - pa0)
    pel <- ifelse(st$eL[s] == 1L, peL, 1 - peL)
    pea <- ifelse(st$eA[s] == 1L, peA, 1 - peA)
    compatible <- xor_int(st$L[s], st$eL[s]) == obs$L[, 1]
    pre[, s] <- pl * pa * pel * pea * compatible
  }
  den <- rowSums(pre)
  if (any(!is.finite(den) | den <= 0)) return(list(fail = 'filter-normalizer'))
  p <- matrix(NA_real_, n, N_MONTHS)
  proxy_a <- xor_int(st$A, st$eA)
  p[, 1] <- rowSums(pre[, proxy_a == 1L, drop = FALSE]) / den
  post <- pre * (matrix(proxy_a, n, S, byrow = TRUE) == obs$A[, 1])
  nz <- normalize_weights(post)
  if (any(nz$bad)) return(list(fail = 'filter-normalizer'))
  post <- nz$w

  if (N_MONTHS > 1L) {
    for (tt in 2:N_MONTHS) {
      nxt <- matrix(0, n, S)
      for (s in seq_len(S)) {
        compatible_l <- xor_int(st$L[s], st$eL[s]) == obs$L[, tt]
        if (!any(compatible_l)) next
        total <- numeric(n)
        for (r in seq_len(S)) {
          if (stress && (st$lagL[s] != st$eL[r] || st$lagA[s] != st$eA[r])) next
          pL <- expit(lp_lt(st$L[r], st$A[r], dat$X1, dat$X2,
                           tt - 1L, scen$specification))
          fL <- ifelse(st$L[s] == 1L, pL, 1 - pL)
          pA <- expit(lp_at(st$A[r], st$L[s], dat$X1, dat$X2,
                           tt - 1L, scen$specification))
          fA <- ifelse(st$A[s] == 1L, pA, 1 - pA)
          prev2L <- if (stress) st$lagL[r] else st$eL[r]
          prev2A <- if (stress) st$lagA[r] else st$eA[r]
          fEL <- error_transition_probability(st$eL[s], st$eL[r], prev2L,
                                               peL, tt, stress)
          fEA <- error_transition_probability(st$eA[s], st$eA[r], prev2A,
                                               peA, tt, stress)
          total <- total + post[, r] * fL * fA * fEL * fEA
        }
        nxt[, s] <- total * compatible_l
      }
      den <- rowSums(nxt)
      if (any(!is.finite(den) | den <= 0)) return(list(fail = 'filter-normalizer'))
      p[, tt] <- rowSums(nxt[, proxy_a == 1L, drop = FALSE]) / den
      nxt <- nxt * (matrix(proxy_a, n, S, byrow = TRUE) == obs$A[, tt])
      nz <- normalize_weights(nxt)
      if (any(nz$bad)) return(list(fail = 'filter-normalizer'))
      post <- nz$w
    }
  }
  list(p = p, blocks = list(), fail = NULL)
}

known_latent_probabilities <- function(dat, scen) {
  n <- length(dat$X1)
  p <- matrix(NA_real_, n, N_MONTHS)
  p[, 1] <- expit(lp_a0(dat$L[, 1], dat$X1, dat$X2))
  if (N_MONTHS > 1L)
    for (tt in 2:N_MONTHS)
      p[, tt] <- expit(lp_at(dat$A[, tt - 1L], dat$L[, tt], dat$X1,
                             dat$X2, tt - 1L, scen$specification))
  p
}

estimate_threshold <- function(dat, obs, scen, model) {
  fit <- switch(model,
    first_order = fit_first_order(obs$A, obs$L, dat),
    rich_history = fit_rich_history(obs$A, obs$L, dat),
    exact_filtered = exact_proxy_probabilities(dat, obs, scen),
    stop('unknown threshold model: ', model)
  )
  if (!is.null(fit$fail)) return(empty_estimate(fit$fail))
  Lref <- attach_x2(dat$L, dat$X2)
  Lobs <- attach_x2(obs$L, dat$X2)
  risk_estimates(obs$A, Lobs, obs$Y, fit$p, fit$blocks, Lref)
}

estimate_oracle <- function(dat, scen) {
  p <- known_latent_probabilities(dat, scen)
  L <- attach_x2(dat$L, dat$X2)
  risk_estimates(dat$A, L, dat$Y, p, list(), L)
}

log1pexp <- function(x) ifelse(x > 0, x + log1p(exp(-x)), log1p(exp(x)))

fit_laplace_logit <- function(X, y, nonintercept_sd = 2.5) {
  sd <- c(5, rep(nonintercept_sd, ncol(X) - 1L))
  precision <- 1 / sd^2
  lp <- function(beta) {
    eta <- drop(X %*% beta)
    sum(y * eta - log1pexp(eta)) - 0.5 * sum(precision * beta^2)
  }
  gr <- function(beta) drop(crossprod(X, y - expit(drop(X %*% beta)))) -
    precision * beta
  opt <- try(stats::optim(rep(0, ncol(X)), function(b) -lp(b),
                          function(b) -gr(b), method = 'BFGS',
                          control = list(maxit = 1000, reltol = 1e-12)), silent = TRUE)
  if (inherits(opt, 'try-error')) return(list(fail = 'latent-fit-failed'))
  g <- gr(opt$par)
  p <- expit(drop(X %*% opt$par))
  Hneg <- crossprod(X * sqrt(p * (1 - p)), X * sqrt(p * (1 - p))) +
    diag(precision, ncol(X))
  ch <- try(chol(Hneg), silent = TRUE)
  if (max(abs(g)) >= 1e-7 || inherits(ch, 'try-error'))
    return(list(fail = 'latent-fit-failed'))
  list(mode = opt$par, covariance = chol2inv(ch), fail = NULL)
}

fit_latent_models <- function(dat, obs, scen, validation_n,
                              nonintercept_sd = 2.5) {
  val <- dat$validation_rank <= validation_n
  if (sum(val) != validation_n) return(list(fail = 'validation-size'))
  X1 <- dat$X1[val]
  X2 <- dat$X2[val]
  L <- dat$L[val, , drop = FALSE]
  A <- dat$A[val, , drop = FALSE]
  Y <- dat$Y[val]
  n <- sum(val)

  XL0 <- cbind(1, X1, X2)
  XA0 <- cbind(1, L[, 1], X1, X2)
  ids <- rep(seq_len(n), N_MONTHS - 1L)
  month <- rep(seq_len(N_MONTHS - 1L), each = n)
  XLt <- cbind(1, as.vector(L[, -N_MONTHS, drop = FALSE]),
               as.vector(A[, -N_MONTHS, drop = FALSE]),
               rep(X1, N_MONTHS - 1L), rep(X2, N_MONTHS - 1L), month)
  XAt <- cbind(1, as.vector(A[, -N_MONTHS, drop = FALSE]),
               as.vector(L[, -1L, drop = FALSE]),
               rep(X1, N_MONTHS - 1L), rep(X2, N_MONTHS - 1L), month)
  if (scen$effect_modification) {
    XY <- cbind(1, X1, X2, L[, N_MONTHS], A[, N_MONTHS],
                A[, N_MONTHS] * X2)
  } else {
    XY <- cbind(1, X1, X2, L[, N_MONTHS], A[, N_MONTHS])
  }

  fits <- list(
    L0 = fit_laplace_logit(XL0, L[, 1], nonintercept_sd),
    A0 = fit_laplace_logit(XA0, A[, 1], nonintercept_sd),
    Lt = fit_laplace_logit(XLt, as.vector(L[, -1L, drop = FALSE]),
                           nonintercept_sd),
    At = fit_laplace_logit(XAt, as.vector(A[, -1L, drop = FALSE]),
                           nonintercept_sd),
    Y = fit_laplace_logit(XY, Y, nonintercept_sd)
  )
  bad <- vapply(fits, function(x) !is.null(x$fail), logical(1))
  if (any(bad)) return(list(fail = fits[[which(bad)[1]]]$fail))

  stratum <- 1L + dat$X2 + 2L * dat$X3
  beta_shapes <- function(E) {
    init_a <- init_b <- q0_a <- q0_b <- q1_a <- q1_b <- rep(0.5, 4L)
    for (s in 1:4) {
      v <- val & stratum == s
      init_a[s] <- init_a[s] + sum(E[v, 1] == 1L)
      init_b[s] <- init_b[s] + sum(E[v, 1] == 0L)
      if (N_MONTHS > 1L) {
        prev <- E[v, -N_MONTHS, drop = FALSE]
        cur <- E[v, -1L, drop = FALSE]
        q0_a[s] <- q0_a[s] + sum(cur[prev == 0L] == 1L)
        q0_b[s] <- q0_b[s] + sum(cur[prev == 0L] == 0L)
        q1_a[s] <- q1_a[s] + sum(cur[prev == 1L] == 1L)
        q1_b[s] <- q1_b[s] + sum(cur[prev == 1L] == 0L)
      }
    }
    list(init_a = init_a, init_b = init_b, q0_a = q0_a, q0_b = q0_b,
         q1_a = q1_a, q1_b = q1_b)
  }
  y_a <- y_b <- rep(0.5, 4L)
  for (s in 1:4) {
    v <- val & stratum == s
    y_a[s] <- y_a[s] + sum(obs$EY[v] == 1L)
    y_b[s] <- y_b[s] + sum(obs$EY[v] == 0L)
  }
  list(fits = fits, error_A = beta_shapes(obs$EA),
       error_L = beta_shapes(obs$EL), y_a = y_a, y_b = y_b,
       val = val, stratum = stratum, fail = NULL)
}

draw_laplace_models <- function(fitted) {
  lapply(fitted$fits, function(z)
    drop(mvtnorm::rmvnorm(1L, mean = z$mode, sigma = z$covariance)))
}

draw_error_model <- function(shape) {
  list(init = stats::rbeta(4L, shape$init_a, shape$init_b),
       q0 = stats::rbeta(4L, shape$q0_a, shape$q0_b),
       q1 = stats::rbeta(4L, shape$q1_a, shape$q1_b))
}

sample_rows <- function(prob) {
  z <- normalize_weights(prob)
  if (any(z$bad)) stop('sampling-normalizer')
  u <- stats::runif(nrow(prob))
  ans <- rep(ncol(prob), nrow(prob))
  cumulative <- numeric(nrow(prob))
  open <- rep(TRUE, nrow(prob))
  for (s in seq_len(ncol(prob))) {
    cumulative <- cumulative + z$w[, s]
    take <- open & u <= cumulative
    ans[take] <- s
    open[take] <- FALSE
  }
  ans
}

impute_latent_history <- function(dat, obs, scen, fitted) {
  draw <- draw_laplace_models(fitted)
  eA <- draw_error_model(fitted$error_A)
  eL <- draw_error_model(fitted$error_L)
  eY <- stats::rbeta(4L, fitted$y_a, fitted$y_b)
  if (!scen$error_nodes %in% c('A', 'AL'))
    eA <- list(init = rep(0, 4), q0 = rep(0, 4), q1 = rep(1, 4))
  if (!scen$error_nodes %in% c('L', 'AL'))
    eL <- list(init = rep(0, 4), q0 = rep(0, 4), q1 = rep(1, 4))
  if (!isTRUE(scen$outcome_error)) eY[] <- 0

  idx <- which(!fitted$val)
  if (!length(idx)) return(list(A = dat$A, L = dat$L, Y = dat$Y))
  X1 <- dat$X1[idx]
  X2 <- dat$X2[idx]
  X3 <- dat$X3[idx]
  stratum <- fitted$stratum[idx]
  Astar <- obs$A[idx, , drop = FALSE]
  Lstar <- obs$L[idx, , drop = FALSE]
  Ystar <- obs$Y[idx]
  n <- length(idx)
  st <- state_table(FALSE)
  S <- nrow(st)
  proxyA <- xor_int(st$A, st$eA)
  alpha <- vector('list', N_MONTHS)

  pL0 <- expit(drop(cbind(1, X1, X2) %*% draw$L0))
  w <- matrix(0, n, S)
  for (s in seq_len(S)) {
    pA0 <- expit(drop(cbind(1, st$L[s], X1, X2) %*% draw$A0))
    w[, s] <- ifelse(st$L[s] == 1L, pL0, 1 - pL0) *
      ifelse(st$A[s] == 1L, pA0, 1 - pA0) *
      ifelse(st$eL[s] == 1L, eL$init[stratum], 1 - eL$init[stratum]) *
      ifelse(st$eA[s] == 1L, eA$init[stratum], 1 - eA$init[stratum]) *
      (xor_int(st$L[s], st$eL[s]) == Lstar[, 1]) *
      (proxyA[s] == Astar[, 1])
  }
  z <- normalize_weights(w)
  if (any(z$bad)) stop('imputation-filter-normalizer')
  alpha[[1]] <- z$w

  if (N_MONTHS > 1L) {
    for (tt in 2:N_MONTHS) {
      w <- matrix(0, n, S)
      for (s in seq_len(S)) {
        total <- numeric(n)
        for (r in seq_len(S)) {
          pL <- expit(drop(cbind(1, st$L[r], st$A[r], X1, X2,
                                 tt - 1L) %*% draw$Lt))
          pA <- expit(drop(cbind(1, st$A[r], st$L[s], X1, X2,
                                 tt - 1L) %*% draw$At))
          pel <- ifelse(st$eL[r] == 0L, eL$q0[stratum], eL$q1[stratum])
          pea <- ifelse(st$eA[r] == 0L, eA$q0[stratum], eA$q1[stratum])
          total <- total + alpha[[tt - 1L]][, r] *
            ifelse(st$L[s] == 1L, pL, 1 - pL) *
            ifelse(st$A[s] == 1L, pA, 1 - pA) *
            ifelse(st$eL[s] == 1L, pel, 1 - pel) *
            ifelse(st$eA[s] == 1L, pea, 1 - pea)
        }
        w[, s] <- total *
          (xor_int(st$L[s], st$eL[s]) == Lstar[, tt]) *
          (proxyA[s] == Astar[, tt])
      }
      z <- normalize_weights(w)
      if (any(z$bad)) stop('imputation-filter-normalizer')
      alpha[[tt]] <- z$w
    }
  }

  ## The terminal proxy contributes to the forward filter before sampling.
  for (s in seq_len(S)) {
    XY <- if (scen$effect_modification)
      cbind(1, X1, X2, st$L[s], st$A[s], st$A[s] * X2) else
      cbind(1, X1, X2, st$L[s], st$A[s])
    py <- expit(drop(XY %*% draw$Y))
    ey <- eY[stratum]
    pstar1 <- py * (1 - ey) + (1 - py) * ey
    alpha[[N_MONTHS]][, s] <- alpha[[N_MONTHS]][, s] *
      ifelse(Ystar == 1L, pstar1, 1 - pstar1)
  }
  z <- normalize_weights(alpha[[N_MONTHS]])
  if (any(z$bad)) stop('imputation-outcome-normalizer')
  alpha[[N_MONTHS]] <- z$w

  selected <- matrix(NA_integer_, n, N_MONTHS)
  selected[, N_MONTHS] <- sample_rows(alpha[[N_MONTHS]])
  if (N_MONTHS > 1L) {
    for (tt in (N_MONTHS - 1L):1L) {
      ns <- selected[, tt + 1L]
      nextL <- st$L[ns]
      nextA <- st$A[ns]
      nextEL <- st$eL[ns]
      nextEA <- st$eA[ns]
      bw <- matrix(0, n, S)
      for (s in seq_len(S)) {
        pL <- expit(drop(cbind(1, st$L[s], st$A[s], X1, X2,
                               tt) %*% draw$Lt))
        pA <- expit(drop(cbind(1, st$A[s], nextL, X1, X2,
                               tt) %*% draw$At))
        pel <- ifelse(st$eL[s] == 0L, eL$q0[stratum], eL$q1[stratum])
        pea <- ifelse(st$eA[s] == 0L, eA$q0[stratum], eA$q1[stratum])
        bw[, s] <- alpha[[tt]][, s] *
          ifelse(nextL == 1L, pL, 1 - pL) *
          ifelse(nextA == 1L, pA, 1 - pA) *
          ifelse(nextEL == 1L, pel, 1 - pel) *
          ifelse(nextEA == 1L, pea, 1 - pea)
      }
      selected[, tt] <- sample_rows(bw)
    }
  }

  Limp <- dat$L
  Aimp <- dat$A
  for (tt in seq_len(N_MONTHS)) {
    Limp[idx, tt] <- st$L[selected[, tt]]
    Aimp[idx, tt] <- st$A[selected[, tt]]
  }

  final_state <- selected[, N_MONTHS]
  XY <- if (scen$effect_modification)
    cbind(1, X1, X2, st$L[final_state], st$A[final_state],
          st$A[final_state] * X2) else
    cbind(1, X1, X2, st$L[final_state], st$A[final_state])
  py <- expit(drop(XY %*% draw$Y))
  ey <- eY[stratum]
  like1 <- ifelse(Ystar == 1L, 1 - ey, ey)
  like0 <- ifelse(Ystar == 1L, ey, 1 - ey)
  postY <- py * like1 / (py * like1 + (1 - py) * like0)
  Yimp <- dat$Y
  Yimp[idx] <- stats::rbinom(n, 1, postY)
  list(A = Aimp, L = Limp, Y = Yimp)
}

mi_completed_draws <- function(dat, obs, scen, M, nonintercept_sd = 2.5) {
  fitted <- fit_latent_models(dat, obs, scen, scen$validation_n,
                              nonintercept_sd)
  if (!is.null(fitted$fail)) return(list(fail = fitted$fail))
  Q <- U <- matrix(NA_real_, M, length(CONTRASTS),
                   dimnames = list(NULL, CONTRASTS))
  diagnostics <- array(NA_real_, c(M, length(CONTRASTS), 5L),
                       dimnames = list(NULL, CONTRASTS,
                                       c('ess_0', 'ess_1', 'median_weight',
                                         'p99_weight', 'censor_change_L')))
  system_dim <- NA_integer_
  for (m in seq_len(M)) {
    comp <- try(impute_latent_history(dat, obs, scen, fitted), silent = TRUE)
    if (inherits(comp, 'try-error')) return(list(fail = 'imputation-filter-failed'))
    L <- attach_x2(comp$L, dat$X2)
    fit <- fit_rich_history(comp$A, comp$L, dat)
    if (!is.null(fit$fail)) return(list(fail = fit$fail))
    r <- risk_estimates(comp$A, L, comp$Y, fit$p, fit$blocks, L)
    if (any(!is.na(r$fail))) return(list(fail = r$fail[which(!is.na(r$fail))[1]]))
    Q[m, r$contrast] <- r$est
    U[m, r$contrast] <- r$se^2
    diagnostics[m, r$contrast, ] <- as.matrix(r[, dimnames(diagnostics)[[3]]])
    system_dim <- attr(r, 'system_dim')
  }
  list(Q = Q, U = U, diagnostics = diagnostics,
       system_dim = system_dim, fail = NULL)
}

pool_mi <- function(draws, indices = seq_len(nrow(draws$Q))) {
  M <- length(indices)
  nu_com <- max(1, N_PER_REPLICATE - draws$system_dim)
  rows <- lapply(CONTRASTS, function(key) {
    q <- draws$Q[indices, key]
    u <- draws$U[indices, key]
    qbar <- mean(q)
    W <- mean(u)
    B <- if (M > 1L) stats::var(q) else 0
    Tvar <- W + (1 + 1 / M) * B
    if (!is.finite(Tvar) || Tvar < 0)
      return(empty_estimate('invalid-mi-variance')[1, , drop = FALSE])
    if (B == 0 || W == 0) {
      nu <- nu_com
    } else {
      r <- (1 + 1 / M) * B / W
      nu_old <- (M - 1) * (1 + 1 / r)^2
      lambda <- (1 + 1 / M) * B / Tvar
      nu_obs <- ((nu_com + 1) / (nu_com + 3)) * nu_com * (1 - lambda)
      nu <- 1 / (1 / nu_old + 1 / nu_obs)
    }
    critical <- stats::qt(0.975, df = nu)
    d <- draws$diagnostics[indices, key, , drop = FALSE]
    data.frame(
      contrast = key, est = qbar, se = sqrt(Tvar),
      lo = qbar - critical * sqrt(Tvar), hi = qbar + critical * sqrt(Tvar),
      ess_0 = mean(d[, , 'ess_0']), ess_1 = mean(d[, , 'ess_1']),
      median_weight = mean(d[, , 'median_weight']),
      p99_weight = mean(d[, , 'p99_weight']),
      adherence_0 = NA_real_, adherence_1 = NA_real_,
      censor_change_L = mean(d[, , 'censor_change_L']),
      interval_df = nu, fail = NA_character_, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

estimate_mi <- function(dat, obs, scen, M, nonintercept_sd = 2.5) {
  draws <- mi_completed_draws(dat, obs, scen, M, nonintercept_sd)
  if (!is.null(draws$fail)) return(empty_estimate(draws$fail))
  pool_mi(draws)
}

calibrate_mi <- function(scenarios) {
  ## Fixed calibration seeds are outside simulation replicates. The harness
  ## remains the sole owner of every finite-sample replicate stream.
  set.seed(MASTER_SEED + 700000L)
  configurations <- expand.grid(
    benchmark = c('nd70', 'un85'),
    validation_n = c(100L, 500L),
    specification = SPECIFICATIONS,
    stringsAsFactors = FALSE
  )
  records <- list()
  failed <- NULL
  for (i in seq_len(nrow(configurations))) {
    z <- configurations[i, ]
    hit <- scenarios$benchmark == z$benchmark &
      scenarios$validation_n == z$validation_n &
      scenarios$specification == z$specification
    hit[is.na(hit)] <- FALSE
    if (!any(hit)) {
      template <- scenarios[scenarios$benchmark == z$benchmark &
                              !is.na(scenarios$benchmark), ][1, ]
      template$validation_n <- z$validation_n
      template$specification <- z$specification
      scen <- template
    } else scen <- scenarios[which(hit)[1], ]
    dat <- gen_latent(scen)
    obs <- make_observed(dat, scen)
    dr <- mi_completed_draws(dat, obs, scen, MI_CAL_REFERENCE)
    if (!is.null(dr$fail)) {
      failed <- sprintf('configuration %d: %s', i, dr$fail)
      break
    }
    for (M in MI_CANDIDATES) {
      qsd <- sesd <- numeric(MI_CAL_REPEATS * length(CONTRASTS))
      at <- 0L
      for (b in seq_len(MI_CAL_REPEATS)) {
        ind <- sample.int(MI_CAL_REFERENCE, M, replace = FALSE)
        pooled <- pool_mi(dr, ind)
        for (k in seq_along(CONTRASTS)) {
          at <- at + 1L
          qsd[at] <- pooled$est[k]
          sesd[at] <- pooled$se[k]
        }
      }
      records[[length(records) + 1L]] <- data.frame(
        configuration = i, M = M,
        point_sd = stats::sd(qsd), se_sd = stats::sd(sesd),
        stringsAsFactors = FALSE)
    }
  }
  if (!is.null(failed))
    return(list(selected_M = NA_integer_, passed = FALSE, failure = failed,
                diagnostics = do.call(rbind, records)))
  tab <- do.call(rbind, records)
  summary <- do.call(rbind, lapply(split(tab, tab$M), function(d)
    data.frame(M = d$M[1], point_q99 = unname(stats::quantile(d$point_sd, 0.99)),
               se_q99 = unname(stats::quantile(d$se_sd, 0.99)))))
  good <- summary$M[summary$point_q99 < MI_CAL_TARGET &
                      summary$se_q99 < MI_CAL_TARGET]
  selected <- if (length(good)) min(good) else MI_FALLBACK
  list(selected_M = selected, passed = TRUE, used_fallback = !length(good),
       diagnostics = tab, summary = summary)
}
