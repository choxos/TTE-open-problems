## Study 2 (MER-01): truth, filtering, estimators, and latent-state correction.

`%||%` <- function(x, y) if (is.null(x)) y else x
## Probability of x under Bernoulli(p). The filter calls this with a scalar
## latent state and a per-person vector p; ifelse() took its length from x and
## returned the first person's probability for everyone.
bern <- function(x, p) {
  one <- x == 1L
  one * p + (!one) * (1 - p)
}
log1pexp <- function(x) pmax(x, 0) + log1p(exp(-abs(x)))

## Truth is generated under interventions, never from finite-sample replicates.
truth_for_law <- function(law, n = N_TRUTH, chunk = 100000L) {
  scen <- list(
    specification = if (law == "confounder_stress") "confounder" else
      if (law == "outcome_stress") "outcome" else "core",
    effect_modification = law != "no_effect_modification"
  )
  acc <- lapply(ESTIMANDS, function(z) list(n = 0, sy1 = 0, sy0 = 0, sd = 0, sd2 = 0))
  names(acc) <- ESTIMANDS
  done <- 0L
  while (done < n) {
    m <- min(chunk, n - done)
    X1 <- stats::rnorm(m)
    X2 <- stats::rbinom(m, 1L, 0.5)
    uL <- matrix(stats::runif(m * N_MONTHS), nrow = m)
    uY <- stats::runif(m)
    L0 <- as.integer(uL[, 1L] < expit(-0.40 + 0.50 * X1 + 0.40 * X2))

    arm <- function(rule) {
      L <- matrix(0L, m, N_MONTHS)
      A <- matrix(0L, m, N_MONTHS)
      L[, 1L] <- L0
      A[, 1L] <- switch(rule, dynamic = L0, zero = 0L, one = 1L)
      for (tt in 2L:N_MONTHS) {
        L[, tt] <- as.integer(uL[, tt] < expit(latent_predictor_L(
          tt, L[, tt - 1L], A[, tt - 1L], X1, X2, scen$specification)))
        A[, tt] <- switch(rule, dynamic = L[, tt], zero = 0L, one = 1L)
      }
      py <- outcome_probability(X1, X2, L[, N_MONTHS], A[, N_MONTHS],
                                scen$effect_modification, scen$specification)
      as.integer(uY < py)
    }
    yd <- arm("dynamic")
    y0 <- arm("zero")
    y1 <- arm("one")

    update_acc <- function(a, yy1, yy0, keep) {
      d <- yy1[keep] - yy0[keep]
      a$n <- a$n + length(d)
      a$sy1 <- a$sy1 + sum(yy1[keep])
      a$sy0 <- a$sy0 + sum(yy0[keep])
      a$sd <- a$sd + sum(d)
      a$sd2 <- a$sd2 + sum(d^2)
      a
    }
    acc$dynamic <- update_acc(acc$dynamic, yd, y0, rep(TRUE, m))
    acc$dynamic_x2_0 <- update_acc(acc$dynamic_x2_0, yd, y0, X2 == 0L)
    acc$dynamic_x2_1 <- update_acc(acc$dynamic_x2_1, yd, y0, X2 == 1L)
    acc$static <- update_acc(acc$static, y1, y0, rep(TRUE, m))
    done <- done + m
  }

  out <- do.call(rbind, lapply(names(acc), function(k) {
    a <- acc[[k]]
    truth <- a$sd / a$n
    vv <- (a$sd2 - a$sd^2 / a$n) / max(1, a$n - 1L)
    data.frame(
      estimand = k,
      risk_g1 = a$sy1 / a$n,
      risk_g0 = a$sy0 / a$n,
      truth = truth,
      truth_mcse = sqrt(max(0, vv) / a$n),
      truth_n = a$n,
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

empty_rows <- function(method, pattern, fail, mi_m = NA_integer_,
                       prior_sd = NA_real_) {
  data.frame(
    method = method, analysis_pattern = pattern, estimand = ESTIMANDS,
    est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
    ess_g1 = NA_real_, ess_g0 = NA_real_, median_weight = NA_real_,
    p99_weight = NA_real_, adherence_g1 = NA_real_, adherence_g0 = NA_real_,
    oracle_adherence_g1 = NA_real_, oracle_adherence_g0 = NA_real_,
    censor_change_l = NA_real_, n_system = NA_integer_, mi_m = mi_m,
    prior_sd = prior_sd, fail = fail, stringsAsFactors = FALSE
  )
}

run_length_matrix <- function(Z) {
  R <- matrix(1L, nrow(Z), ncol(Z))
  if (ncol(Z) >= 2L) {
    for (tt in 2L:ncol(Z)) {
      R[, tt] <- ifelse(Z[, tt] == Z[, tt - 1L], R[, tt - 1L] + 1L, 1L)
    }
  }
  R
}

pair_products <- function(M) {
  if (ncol(M) < 2L) return(NULL)
  cmb <- utils::combn(seq_len(ncol(M)), 2L)
  out <- M[, cmb[1L, ], drop = FALSE] * M[, cmb[2L, ], drop = FALSE]
  colnames(out) <- paste(colnames(M)[cmb[1L, ]], colnames(M)[cmb[2L, ]], sep = ":")
  out
}

canonical_basis <- function(X, tol = 1e-10) {
  keep_var <- apply(X, 2L, function(z) length(unique(z)) > 1L)
  keep_var[1L] <- TRUE
  X <- X[, keep_var, drop = FALSE]
  q <- qr(X, tol = tol)
  if (q$rank < ncol(X)) {
    ## Raw cumulative counts are structurally aliased with their complete binary
    ## histories. Removing exact aliases preserves the requested column space;
    ## sample-induced rank deficiency after this canonicalization still fails.
    X <- X[, sort(q$pivot[seq_len(q$rank)]), drop = FALSE]
  }
  X
}

rich_matrices <- function(A, L, X1, X2, X3) {
  nsx <- splines::ns(X1, df = 4L)
  colnames(nsx) <- paste0("x1s", seq_len(ncol(nsx)))
  rA <- run_length_matrix(A)
  rL <- run_length_matrix(L)
  out <- vector("list", N_MONTHS)
  for (tt in seq_len(N_MONTHS)) {
    base <- cbind(`(Intercept)` = 1, nsx, X2 = X2, X3 = X3,
                  Lcur = L[, tt], X1hi = X1 > 0.5, X1lo = X1 < -0.5)
    if (tt > 1L) {
      Ah <- A[, seq_len(tt - 1L), drop = FALSE]
      Lh <- L[, seq_len(tt - 1L), drop = FALSE]
      colnames(Ah) <- paste0("A", 0:(tt - 2L))
      colnames(Lh) <- paste0("L", 0:(tt - 2L))
      base <- cbind(base, Ah, Lh,
                    cumA = rowSums(Ah), cumL = rowSums(Lh),
                    runA = rA[, tt], runL = rL[, tt])
    }
    recent <- cbind(Lcur = L[, tt], X2 = X2, X3 = X3)
    if (tt > 1L) recent <- cbind(recent, Aprev1 = A[, tt - 1L], Lprev1 = L[, tt - 1L])
    if (tt > 2L) recent <- cbind(recent, Aprev2 = A[, tt - 2L], Lprev2 = L[, tt - 2L])
    out[[tt]] <- canonical_basis(cbind(base, pair_products(recent)))
  }
  out
}

safe_glm_group <- function(Xlist, ylist) {
  X <- do.call(rbind, Xlist)
  y <- unlist(ylist, use.names = FALSE)
  fit <- try(stats::glm.fit(x = X, y = y, family = stats::binomial()), silent = TRUE)
  if (inherits(fit, "try-error") || !isTRUE(fit$converged) ||
      fit$rank < ncol(X) || any(!is.finite(fit$coefficients))) {
    return(list(fail = "propensity-fit-failed"))
  }
  p <- expit(drop(X %*% fit$coefficients))
  if (any(!is.finite(p))) return(list(fail = "nonfinite-propensity"))
  list(X = Xlist, y = ylist, beta = fit$coefficients, fail = NA_character_)
}

fit_propensity <- function(A, L, X1, X2, X3, kind = c("first_order", "rich")) {
  kind <- match.arg(kind)
  if (kind == "first_order") {
    X0 <- cbind(1, L[, 1L], X1, X2, X3)
    XF <- lapply(2L:N_MONTHS, function(tt)
      cbind(1, A[, tt - 1L], L[, tt], X1, X2, X3, tt - 1L))
    groups <- list(
      safe_glm_group(list(X0), list(A[, 1L])),
      safe_glm_group(XF, lapply(2L:N_MONTHS, function(tt) A[, tt]))
    )
    times <- list(1L, 2L:N_MONTHS)
  } else {
    XX <- rich_matrices(A, L, X1, X2, X3)
    groups <- lapply(seq_len(N_MONTHS), function(tt)
      safe_glm_group(list(XX[[tt]]), list(A[, tt])))
    times <- lapply(seq_len(N_MONTHS), identity)
  }
  if (any(vapply(groups, function(g) !is.na(g$fail), logical(1)))) {
    return(list(fail = "propensity-fit-failed"))
  }
  sizes <- vapply(groups, function(g) length(g$beta), integer(1))
  starts <- cumsum(c(1L, head(sizes, -1L)))
  list(groups = groups, times = times, sizes = sizes, starts = starts,
       beta = unlist(lapply(groups, `[[`, "beta"), use.names = FALSE),
       n = nrow(A), fail = NA_character_)
}

propensity_pobs <- function(object, beta, A) {
  pobs <- matrix(NA_real_, nrow(A), ncol(A))
  for (gg in seq_along(object$groups)) {
    ix <- object$starts[gg] + seq_len(object$sizes[gg]) - 1L
    for (jj in seq_along(object$groups[[gg]]$X)) {
      tt <- object$times[[gg]][jj]
      p <- expit(drop(object$groups[[gg]]$X[[jj]] %*% beta[ix]))
      pobs[, tt] <- ifelse(A[, tt] == 1L, p, 1 - p)
    }
  }
  pobs
}

propensity_scores <- function(object, beta) {
  S <- matrix(0, object$n, length(beta))
  for (gg in seq_along(object$groups)) {
    ix <- object$starts[gg] + seq_len(object$sizes[gg]) - 1L
    sg <- matrix(0, object$n, object$sizes[gg])
    for (jj in seq_along(object$groups[[gg]]$X)) {
      X <- object$groups[[gg]]$X[[jj]]
      y <- object$groups[[gg]]$y[[jj]]
      p <- expit(drop(X %*% beta[ix]))
      sg <- sg + X * (y - p)
    }
    S[, ix] <- sg
  }
  S
}

propensity_bread <- function(object, beta) {
  p <- length(beta)
  A <- matrix(0, p, p)
  for (gg in seq_along(object$groups)) {
    ix <- object$starts[gg] + seq_len(object$sizes[gg]) - 1L
    block <- matrix(0, length(ix), length(ix))
    for (X in object$groups[[gg]]$X) {
      pr <- expit(drop(X %*% beta[ix]))
      block <- block - crossprod(X, X * (pr * (1 - pr))) / object$n
    }
    A[ix, ix] <- block
  }
  A
}

risk_quantities <- function(A, L, Y, X2, pobs, dat) {
  if (any(!is.finite(pobs)) || any(pobs <= 0)) return(list(fail = "invalid-weight-probability"))
  lw <- -rowSums(log(pobs))
  if (any(!is.finite(lw)) || any(lw > log(.Machine$double.xmax))) {
    return(list(fail = "nonfinite-weight"))
  }
  w <- exp(lw)
  dyn1 <- rowSums(A != L) == 0L
  dyn0 <- rowSums(A != 0L) == 0L
  sta1 <- rowSums(A != 1L) == 0L
  sta0 <- dyn0
  subsets <- list(rep(TRUE, nrow(A)), X2 == 0L, X2 == 1L, rep(TRUE, nrow(A)))
  a1 <- list(dyn1, dyn1, dyn1, sta1)
  a0 <- list(dyn0, dyn0, dyn0, sta0)
  q <- matrix(0, nrow(A), 2L * length(ESTIMANDS))
  r <- numeric(ncol(q))
  diag <- vector("list", length(ESTIMANDS))
  oracle_dyn1 <- rowSums(dat$A != dat$L) == 0L
  oracle_dyn0 <- rowSums(dat$A != 0L) == 0L
  c_proxy <- first_censor_month(A, L)
  c_latent_rule <- first_censor_month(A, dat$L)
  for (j in seq_along(ESTIMANDS)) {
    keep <- subsets[[j]]
    q[, 2L * j - 1L] <- keep * a1[[j]] * w
    q[, 2L * j] <- keep * a0[[j]] * w
    if (sum(q[, 2L * j - 1L]) <= 0 || sum(q[, 2L * j]) <= 0) {
      return(list(fail = "empty-consistent-arm"))
    }
    r[2L * j - 1L] <- sum(q[, 2L * j - 1L] * Y) / sum(q[, 2L * j - 1L])
    r[2L * j] <- sum(q[, 2L * j] * Y) / sum(q[, 2L * j])
    active <- q[, c(2L * j - 1L, 2L * j), drop = FALSE]
    ww <- active[active > 0]
    diag[[j]] <- data.frame(
      ess_g1 = sum(active[, 1L])^2 / sum(active[, 1L]^2),
      ess_g0 = sum(active[, 2L])^2 / sum(active[, 2L]^2),
      median_weight = stats::median(ww),
      p99_weight = unname(stats::quantile(ww, 0.99, names = FALSE)),
      adherence_g1 = mean(a1[[j]][keep]), adherence_g0 = mean(a0[[j]][keep]),
      oracle_adherence_g1 = if (j < 4L) mean(oracle_dyn1[keep]) else
        mean((rowSums(dat$A != 1L) == 0L)[keep]),
      oracle_adherence_g0 = mean(oracle_dyn0[keep]),
      censor_change_l = if (j < 4L) mean(c_proxy[keep] != c_latent_rule[keep]) else NA_real_
    )
  }
  list(q = q, r = r, diagnostics = do.call(rbind, diag), w = w, fail = NA_character_)
}

risk_score_matrix <- function(q, Y, r) q * (Y - matrix(r, nrow(q), length(r), byrow = TRUE))

rows_from_covariance <- function(method, pattern, rq, V, n_system,
                                 mi_m = NA_integer_, prior_sd = NA_real_) {
  rows <- vector("list", length(ESTIMANDS))
  for (j in seq_along(ESTIMANDS)) {
    cc <- numeric(length(rq$r))
    cc[2L * j - 1L] <- 1
    cc[2L * j] <- -1
    est <- rq$r[2L * j - 1L] - rq$r[2L * j]
    vv <- drop(t(cc) %*% V %*% cc)
    if (!is.finite(vv) || vv < 0) return(empty_rows(method, pattern, "invalid-variance", mi_m, prior_sd))
    se <- sqrt(vv)
    rows[[j]] <- cbind(
      data.frame(method = method, analysis_pattern = pattern,
                 estimand = ESTIMANDS[j], est = est, se = se,
                 lo = est - 1.96 * se, hi = est + 1.96 * se,
                 stringsAsFactors = FALSE),
      rq$diagnostics[j, , drop = FALSE],
      data.frame(n_system = n_system, mi_m = mi_m, prior_sd = prior_sd,
                 fail = NA_character_, stringsAsFactors = FALSE)
    )
  }
  do.call(rbind, rows)
}

fixed_probability_estimator <- function(A, L, Y, X2, pobs, dat, method, pattern) {
  rq <- risk_quantities(A, L, Y, X2, pobs, dat)
  if (!is.na(rq$fail)) return(empty_rows(method, pattern, rq$fail))
  S <- risk_score_matrix(rq$q, Y, rq$r)
  bread <- -diag(colMeans(rq$q))
  if (any(!is.finite(bread)) || kappa(bread, exact = TRUE) > 1e12) {
    return(empty_rows(method, pattern, "ill-conditioned-bread"))
  }
  inv <- solve(bread)
  meat <- crossprod(S) / nrow(S)
  V <- inv %*% meat %*% t(inv) / nrow(S)
  rows_from_covariance(method, pattern, rq, V, ncol(S))
}

fitted_probability_estimator <- function(A, L, Y, X1, X2, X3, dat,
                                         kind, method, pattern) {
  fit <- fit_propensity(A, L, X1, X2, X3, kind)
  if (!is.na(fit$fail)) return(empty_rows(method, pattern, fit$fail))
  beta <- fit$beta
  pobs <- propensity_pobs(fit, beta, A)
  rq <- risk_quantities(A, L, Y, X2, pobs, dat)
  if (!is.na(rq$fail)) return(empty_rows(method, pattern, rq$fail))
  Sb <- propensity_scores(fit, beta)
  Sr <- risk_score_matrix(rq$q, Y, rq$r)
  S <- cbind(Sb, Sr)
  pb <- length(beta)
  pr <- length(rq$r)
  bread <- matrix(0, pb + pr, pb + pr)
  bread[seq_len(pb), seq_len(pb)] <- propensity_bread(fit, beta)
  bread[pb + seq_len(pr), pb + seq_len(pr)] <- -diag(colMeans(rq$q))

  ## The prescribed numerical step is used for every nonzero risk-equation
  ## derivative with respect to fitted propensity parameters. Logistic score
  ## blocks use their algebraically identical derivative to avoid hundreds of
  ## redundant full score evaluations in each rich-history fit.
  base_mean <- colMeans(Sr)
  for (k in seq_len(pb)) {
    h <- 1e-6 * (1 + abs(beta[k]))
    bp <- beta
    bp[k] <- bp[k] + h
    pp <- propensity_pobs(fit, bp, A)
    rqp <- risk_quantities(A, L, Y, X2, pp, dat)
    if (!is.na(rqp$fail)) return(empty_rows(method, pattern, rqp$fail))
    sp <- risk_score_matrix(rqp$q, Y, rq$r)
    bread[pb + seq_len(pr), k] <- (colMeans(sp) - base_mean) / h
  }
  if (any(!is.finite(bread)) || kappa(bread, exact = TRUE) > 1e12) {
    return(empty_rows(method, pattern, "ill-conditioned-bread"))
  }
  inv <- try(solve(bread), silent = TRUE)
  if (inherits(inv, "try-error")) return(empty_rows(method, pattern, "singular-bread"))
  meat <- crossprod(S) / nrow(S)
  Vfull <- inv %*% meat %*% t(inv) / nrow(S)
  V <- Vfull[pb + seq_len(pr), pb + seq_len(pr), drop = FALSE]
  out <- rows_from_covariance(method, pattern, rq, V, ncol(S))
  attr(out, "df_complete") <- nrow(A) - ncol(S)
  out
}

error_transition_probability <- function(enew, eprev, elag, pfresh,
                                         second_order, t_index) {
  if (!second_order || t_index == 2L) {
    0.80 * (enew == eprev) + 0.20 * bern(enew, pfresh)
  } else {
    0.55 * (enew == eprev) + 0.25 * (enew == elag) + 0.20 * bern(enew, pfresh)
  }
}

## Exact filtering uses normalized forward probabilities at every month. This is
## algebraically equivalent to log-sum-exp scaling over the finite state space.
exact_proxy_pobs <- function(dat, scen, pattern) {
  view <- proxy_view(dat, pattern)
  Aobs <- view$A
  Lobs <- view$L
  use_A <- grepl("A", pattern, fixed = TRUE)
  use_L <- grepl("L", pattern, fixed = TRUE)
  pfA <- if (use_A) dat$p_error else rep(0, nrow(Aobs))
  pfL <- if (use_L) dat$p_error else rep(0, nrow(Aobs))
  states <- expand.grid(L = 0:1, A = 0:1, eL = 0:1, eA = 0:1,
                        lagL = 0:1, lagA = 0:1)
  S <- nrow(states)
  n <- nrow(Aobs)
  pre <- matrix(0, n, S)
  pL0 <- expit(-0.40 + 0.50 * dat$X1 + 0.40 * dat$X2)
  for (j in seq_len(S)) {
    s <- states[j, ]
    if (s$lagL != s$eL || s$lagA != s$eA) next
    pA0 <- expit(-0.70 + 0.80 * s$L + 0.25 * dat$X1 + 0.20 * dat$X2)
    pre[, j] <- bern(s$L, pL0) * bern(s$eL, pfL) *
      ((s$L + s$eL) %% 2L == Lobs[, 1L]) *
      bern(s$A, pA0) * bern(s$eA, pfA)
  }
  den <- rowSums(pre)
  obs <- vapply(seq_len(S), function(j)
    as.numeric((states$A[j] + states$eA[j]) %% 2L == Aobs[, 1L]), numeric(n))
  num <- rowSums(pre * obs)
  if (any(!is.finite(den)) || any(den <= 0) || any(num <= 0)) {
    return(list(fail = "filter-normalizer", pobs = NULL))
  }
  pobs <- matrix(NA_real_, n, N_MONTHS)
  pobs[, 1L] <- num / den
  post <- pre * obs / num

  for (tt in 2L:N_MONTHS) {
    nxt <- matrix(0, n, S)
    for (i in seq_len(S)) {
      old <- states[i, ]
      ai <- post[, i]
      if (!any(ai > 0)) next
      for (j in seq_len(S)) {
        nw <- states[j, ]
        if (nw$lagL != old$eL || nw$lagA != old$eA) next
        pL <- expit(latent_predictor_L(
          tt, old$L, old$A, dat$X1, dat$X2, scen$specification))
        pA <- expit(latent_predictor_A(
          tt, old$A, nw$L, dat$X1, dat$X2, scen$specification))
        peL <- error_transition_probability(
          nw$eL, old$eL, old$lagL, pfL,
          scen$specification == "error_transition", tt)
        peA <- error_transition_probability(
          nw$eA, old$eA, old$lagA, pfA,
          scen$specification == "error_transition", tt)
        emitL <- (nw$L + nw$eL) %% 2L == Lobs[, tt]
        nxt[, j] <- nxt[, j] + ai * bern(nw$L, pL) * peL * emitL *
          bern(nw$A, pA) * peA
      }
    }
    den <- rowSums(nxt)
    obs <- vapply(seq_len(S), function(j)
      as.numeric((states$A[j] + states$eA[j]) %% 2L == Aobs[, tt]), numeric(n))
    num <- rowSums(nxt * obs)
    if (any(!is.finite(den)) || any(den <= 0) || any(num <= 0)) {
      return(list(fail = "filter-normalizer", pobs = NULL))
    }
    pobs[, tt] <- num / den
    post <- nxt * obs / num
  }
  list(fail = NA_character_, pobs = pobs)
}

natural_true_pobs <- function(dat, scen) {
  p <- matrix(NA_real_, nrow(dat$A), N_MONTHS)
  pa <- expit(-0.70 + 0.80 * dat$L[, 1L] + 0.25 * dat$X1 + 0.20 * dat$X2)
  p[, 1L] <- ifelse(dat$A[, 1L] == 1L, pa, 1 - pa)
  for (tt in 2L:N_MONTHS) {
    pa <- expit(latent_predictor_A(
      tt, dat$A[, tt - 1L], dat$L[, tt], dat$X1, dat$X2, scen$specification))
    p[, tt] <- ifelse(dat$A[, tt] == 1L, pa, 1 - pa)
  }
  p
}

est_threshold <- function(dat, scen, pattern, kind) {
  view <- proxy_view(dat, pattern)
  method <- if (kind == "first_order") "first_order" else "rich"
  fitted_probability_estimator(view$A, view$L, view$Y,
                               dat$X1, dat$X2, dat$X3, dat,
                               kind, method, pattern)
}

est_exact_filtered <- function(dat, scen, pattern) {
  view <- proxy_view(dat, pattern)
  fp <- exact_proxy_pobs(dat, scen, pattern)
  if (!is.na(fp$fail)) return(empty_rows("exact_filter", pattern, fp$fail))
  fixed_probability_estimator(view$A, view$L, view$Y, dat$X2,
                              fp$pobs, dat, "exact_filter", pattern)
}

est_oracle <- function(dat, scen) {
  fixed_probability_estimator(dat$A, dat$L, dat$Y, dat$X2,
                              natural_true_pobs(dat, scen), dat,
                              "oracle", "latent")
}

penalized_logit <- function(X, y, prior_sd_nonintercept = MI_PRIOR_SD,
                            tol = 1e-7, maxit = 100L) {
  sd <- c(5, rep(prior_sd_nonintercept, ncol(X) - 1L))
  prec <- 1 / sd^2
  b <- numeric(ncol(X))
  objective <- function(bb) {
    eta <- drop(X %*% bb)
    sum(y * eta - log1pexp(eta)) - 0.5 * sum(prec * bb^2)
  }
  converged <- FALSE
  for (it in seq_len(maxit)) {
    eta <- drop(X %*% b)
    p <- expit(eta)
    grad <- drop(crossprod(X, y - p)) - prec * b
    H <- crossprod(X, X * (p * (1 - p))) + diag(prec)
    step <- try(solve(H, grad), silent = TRUE)
    if (inherits(step, "try-error")) break
    scale <- 1
    old <- objective(b)
    repeat {
      candidate <- b + scale * step
      if (objective(candidate) >= old || scale < 2^-20) break
      scale <- scale / 2
    }
    b <- candidate
    if (max(abs(grad)) < tol) {
      converged <- TRUE
      break
    }
  }
  eta <- drop(X %*% b)
  p <- expit(eta)
  grad <- drop(crossprod(X, y - p)) - prec * b
  H <- crossprod(X, X * (p * (1 - p))) + diag(prec)
  ch <- try(chol(H), silent = TRUE)
  if (!converged || max(abs(grad)) >= tol || inherits(ch, "try-error")) {
    return(list(fail = "latent-fit-failed"))
  }
  list(beta = b, covariance = chol2inv(ch), fail = NA_character_)
}

fit_latent_laws <- function(dat, scen, idx, prior_sd) {
  T <- N_MONTHS
  L <- dat$L[idx, , drop = FALSE]
  A <- dat$A[idx, , drop = FALSE]
  X1 <- dat$X1[idx]
  X2 <- dat$X2[idx]
  fits <- list(
    L0 = penalized_logit(cbind(1, X1, X2), L[, 1L], prior_sd),
    A0 = penalized_logit(cbind(1, L[, 1L], X1, X2), A[, 1L], prior_sd)
  )
  XL <- do.call(rbind, lapply(2L:T, function(tt)
    cbind(1, L[, tt - 1L], A[, tt - 1L], X1, X2, tt - 1L)))
  XA <- do.call(rbind, lapply(2L:T, function(tt)
    cbind(1, A[, tt - 1L], L[, tt], X1, X2, tt - 1L)))
  fits$Lt <- penalized_logit(XL, as.vector(t(L[, 2L:T, drop = FALSE])), prior_sd)
  fits$At <- penalized_logit(XA, as.vector(t(A[, 2L:T, drop = FALSE])), prior_sd)
  XY <- if (scen$effect_modification) {
    cbind(1, X1, X2, L[, T], A[, T], A[, T] * X2)
  } else cbind(1, X1, X2, L[, T], A[, T])
  fits$Y <- penalized_logit(XY, dat$Y[idx], prior_sd)
  if (any(vapply(fits, function(z) !is.na(z$fail), logical(1)))) {
    return(list(fail = "latent-fit-failed"))
  }
  fits$fail <- NA_character_
  fits
}

measurement_counts <- function(E, strata, idx) {
  s <- strata[idx]
  Ei <- E[idx, , drop = FALSE]
  init1 <- init0 <- numeric(4L)
  tr1 <- tr0 <- matrix(0, 4L, 2L)
  for (g in 1:4) {
    take <- s == g
    init1[g] <- sum(Ei[take, 1L] == 1L)
    init0[g] <- sum(Ei[take, 1L] == 0L)
    ## The outcome is measured once, so its matrix has one column and no
    ## transitions; only its initial counts are drawn from.
    if (any(take) && ncol(Ei) > 1L) {
      prev <- Ei[take, 1L:(N_MONTHS - 1L), drop = FALSE]
      now <- Ei[take, 2L:N_MONTHS, drop = FALSE]
      for (ep in 0:1) {
        tr1[g, ep + 1L] <- sum(prev == ep & now == 1L)
        tr0[g, ep + 1L] <- sum(prev == ep & now == 0L)
      }
    }
  }
  list(init1 = init1, init0 = init0, tr1 = tr1, tr0 = tr0)
}

fit_measurement_laws <- function(dat, pattern, idx) {
  strata <- 1L + 2L * dat$X2 + dat$X3
  list(
    strata = strata,
    use_A = grepl("A", pattern, fixed = TRUE),
    use_L = grepl("L", pattern, fixed = TRUE),
    A = measurement_counts(dat$EA, strata, idx),
    L = measurement_counts(dat$EL, strata, idx),
    Y = measurement_counts(matrix(dat$EY, ncol = 1L), strata, idx)
  )
}

draw_measurement_law <- function(fit, outcome_error) {
  draw_one <- function(z) list(
    init = stats::rbeta(4L, z$init1 + 0.5, z$init0 + 0.5),
    trans = matrix(stats::rbeta(8L, as.vector(z$tr1) + 0.5,
                                as.vector(z$tr0) + 0.5), 4L, 2L)
  )
  list(A = draw_one(fit$A), L = draw_one(fit$L),
       Y = if (outcome_error) draw_one(fit$Y)$init else rep(0, 4L),
       use_A = fit$use_A, use_L = fit$use_L, strata = fit$strata)
}

draw_latent_coefficients <- function(fits) {
  lapply(fits[c("L0", "A0", "Lt", "At", "Y")], function(z)
    drop(mvtnorm::rmvnorm(1L, mean = z$beta, sigma = z$covariance)))
}

draw_categorical <- function(P) {
  u <- stats::runif(nrow(P))
  cs <- numeric(nrow(P))
  out <- integer(nrow(P))
  for (j in seq_len(ncol(P))) {
    cs <- cs + P[, j]
    take <- out == 0L & u <= cs
    out[take] <- j
  }
  out[out == 0L] <- ncol(P)
  out
}

normalize_rows <- function(P) {
  z <- rowSums(P)
  if (any(!is.finite(z)) || any(z <= 0)) return(NULL)
  P / z
}

ffbs_impute <- function(dat, scen, pattern, idx_validation, beta, meas) {
  idx <- setdiff(seq_along(dat$X1), idx_validation)
  if (!length(idx)) return(list(A = dat$A, L = dat$L, Y = dat$Y))
  X1 <- dat$X1[idx]
  X2 <- dat$X2[idx]
  X3 <- dat$X3[idx]
  stratum <- meas$strata[idx]
  Aobs <- proxy_view(dat, pattern)$A[idx, , drop = FALSE]
  Lobs <- proxy_view(dat, pattern)$L[idx, , drop = FALSE]
  Yobs <- dat$Ystar[idx]
  states <- expand.grid(L = 0:1, A = 0:1)
  S <- nrow(states)
  alpha <- vector("list", N_MONTHS)
  q <- matrix(0, length(idx), S)

  for (j in seq_len(S)) {
    st <- states[j, ]
    pL <- expit(beta$L0[1] + beta$L0[2] * X1 + beta$L0[3] * X2)
    pA <- expit(beta$A0[1] + beta$A0[2] * st$L +
                  beta$A0[3] * X1 + beta$A0[4] * X2)
    eL <- as.integer(st$L != Lobs[, 1L])
    eA <- as.integer(st$A != Aobs[, 1L])
    mL <- if (meas$use_L) bern(eL, meas$L$init[stratum]) else as.numeric(eL == 0L)
    mA <- if (meas$use_A) bern(eA, meas$A$init[stratum]) else as.numeric(eA == 0L)
    q[, j] <- bern(st$L, pL) * bern(st$A, pA) * mL * mA
  }
  alpha[[1L]] <- normalize_rows(q)
  if (is.null(alpha[[1L]])) stop("imputation-filter-normalizer")

  transition <- function(old, newL, newA, tt) {
    pL <- expit(beta$Lt[1] + beta$Lt[2] * old$L + beta$Lt[3] * old$A +
                  beta$Lt[4] * X1 + beta$Lt[5] * X2 + beta$Lt[6] * (tt - 1L))
    pA <- expit(beta$At[1] + beta$At[2] * old$A + beta$At[3] * newL +
                  beta$At[4] * X1 + beta$At[5] * X2 + beta$At[6] * (tt - 1L))
    eLp <- as.integer(old$L != Lobs[, tt - 1L])
    eAp <- as.integer(old$A != Aobs[, tt - 1L])
    eL <- as.integer(newL != Lobs[, tt])
    eA <- as.integer(newA != Aobs[, tt])
    mL <- if (meas$use_L) bern(eL, meas$L$trans[cbind(stratum, eLp + 1L)]) else
      as.numeric(eL == 0L)
    mA <- if (meas$use_A) bern(eA, meas$A$trans[cbind(stratum, eAp + 1L)]) else
      as.numeric(eA == 0L)
    bern(newL, pL) * bern(newA, pA) * mL * mA
  }

  for (tt in 2L:N_MONTHS) {
    q <- matrix(0, length(idx), S)
    for (i in seq_len(S)) for (j in seq_len(S)) {
      q[, j] <- q[, j] + alpha[[tt - 1L]][, i] *
        transition(states[i, ], states$L[j], states$A[j], tt)
    }
    alpha[[tt]] <- normalize_rows(q)
    if (is.null(alpha[[tt]])) stop("imputation-filter-normalizer")
  }

  terminal_likelihood <- matrix(0, length(idx), S)
  for (j in seq_len(S)) {
    st <- states[j, ]
    eta <- beta$Y[1] + beta$Y[2] * X1 + beta$Y[3] * X2 +
      beta$Y[4] * st$L + beta$Y[5] * st$A
    if (scen$effect_modification) eta <- eta + beta$Y[6] * st$A * X2
    py <- expit(eta)
    if (scen$outcome_error) {
      pe <- meas$Y[stratum]
      terminal_likelihood[, j] <-
        py * bern(as.integer(Yobs != 1L), pe) +
        (1 - py) * bern(as.integer(Yobs != 0L), pe)
    } else terminal_likelihood[, j] <- bern(Yobs, py)
  }
  alpha[[N_MONTHS]] <- normalize_rows(alpha[[N_MONTHS]] * terminal_likelihood)
  if (is.null(alpha[[N_MONTHS]])) stop("imputation-outcome-normalizer")

  state_path <- matrix(0L, length(idx), N_MONTHS)
  state_path[, N_MONTHS] <- draw_categorical(alpha[[N_MONTHS]])
  for (tt in (N_MONTHS - 1L):1L) {
    nxt <- state_path[, tt + 1L]
    q <- matrix(0, length(idx), S)
    newL <- states$L[nxt]
    newA <- states$A[nxt]
    for (i in seq_len(S)) {
      q[, i] <- alpha[[tt]][, i] * transition(states[i, ], newL, newA, tt + 1L)
    }
    q <- normalize_rows(q)
    if (is.null(q)) stop("imputation-backward-normalizer")
    state_path[, tt] <- draw_categorical(q)
  }

  Limp <- dat$L
  Aimp <- dat$A
  Limp[idx, ] <- matrix(states$L[state_path], nrow = length(idx))
  Aimp[idx, ] <- matrix(states$A[state_path], nrow = length(idx))
  Yimp <- dat$Y
  if (scen$outcome_error) {
    L11 <- Limp[idx, N_MONTHS]
    A11 <- Aimp[idx, N_MONTHS]
    eta <- beta$Y[1] + beta$Y[2] * X1 + beta$Y[3] * X2 +
      beta$Y[4] * L11 + beta$Y[5] * A11
    if (scen$effect_modification) eta <- eta + beta$Y[6] * A11 * X2
    py <- expit(eta)
    pe <- meas$Y[stratum]
    l1 <- py * bern(as.integer(Yobs != 1L), pe)
    l0 <- (1 - py) * bern(as.integer(Yobs != 0L), pe)
    post_y <- l1 / (l1 + l0)
    if (any(!is.finite(post_y))) stop("imputation-y-normalizer")
    Yimp[idx] <- stats::rbinom(length(idx), 1L, post_y)
  } else Yimp[idx] <- Yobs
  list(A = Aimp, L = Limp, Y = Yimp)
}

est_corrected <- function(dat, scen, pattern, M, prior_sd = MI_PRIOR_SD,
                          method = "corrected", return_draws = FALSE) {
  idx <- validation_index(dat, scen$validation_n)
  laws <- fit_latent_laws(dat, scen, idx, prior_sd)
  if (!is.na(laws$fail)) return(empty_rows(method, pattern, laws$fail, M, prior_sd))
  mf <- fit_measurement_laws(dat, pattern, idx)
  estimates <- matrix(NA_real_, M, length(ESTIMANDS))
  variances <- matrix(NA_real_, M, length(ESTIMANDS))
  diagnostics <- array(NA_real_, c(M, length(ESTIMANDS), 9L))
  dfs <- numeric(M)
  for (mm in seq_len(M)) {
    beta <- draw_latent_coefficients(laws)
    meas <- draw_measurement_law(mf, scen$outcome_error)
    imp <- try(ffbs_impute(dat, scen, pattern, idx, beta, meas), silent = TRUE)
    if (inherits(imp, "try-error")) {
      return(empty_rows(method, pattern, "imputation-filter-failed", M, prior_sd))
    }
    fit <- fitted_probability_estimator(
      imp$A, imp$L, imp$Y, dat$X1, dat$X2, dat$X3, dat,
      "rich", method, pattern)
    if (any(!is.na(fit$fail))) {
      return(empty_rows(method, pattern, "completed-analysis-failed", M, prior_sd))
    }
    fit <- fit[match(ESTIMANDS, fit$estimand), ]
    estimates[mm, ] <- fit$est
    variances[mm, ] <- fit$se^2
    diagnostics[mm, , ] <- as.matrix(fit[, c(
      "ess_g1", "ess_g0", "median_weight", "p99_weight",
      "adherence_g1", "adherence_g0", "oracle_adherence_g1",
      "oracle_adherence_g0", "censor_change_l")])
    dfs[mm] <- attr(fit, "df_complete") %||% (N_PER_REP - fit$n_system[1L])
  }

  rows <- vector("list", length(ESTIMANDS))
  for (j in seq_along(ESTIMANDS)) {
    qbar <- mean(estimates[, j])
    W <- mean(variances[, j])
    B <- if (M > 1L) stats::var(estimates[, j]) else 0
    Tvar <- W + (1 + 1 / M) * B
    if (!is.finite(Tvar) || Tvar < 0) {
      return(empty_rows(method, pattern, "invalid-mi-variance", M, prior_sd))
    }
    dfcom <- max(1, min(dfs, na.rm = TRUE))
    if (B <= 0 || W <= 0) {
      df <- dfcom
    } else {
      r <- (1 + 1 / M) * B / W
      nu_old <- (M - 1) * (1 + 1 / r)^2
      lambda <- (1 + 1 / M) * B / Tvar
      nu_obs <- ((dfcom + 1) / (dfcom + 3)) * dfcom * (1 - lambda)
      df <- 1 / (1 / nu_old + 1 / nu_obs)
    }
    se <- sqrt(Tvar)
    crit <- stats::qt(0.975, df = df)
    dg <- colMeans(diagnostics[, j, , drop = FALSE], na.rm = TRUE)
    rows[[j]] <- data.frame(
      method = method, analysis_pattern = pattern, estimand = ESTIMANDS[j],
      est = qbar, se = se, lo = qbar - crit * se, hi = qbar + crit * se,
      ess_g1 = dg[1], ess_g0 = dg[2], median_weight = dg[3], p99_weight = dg[4],
      adherence_g1 = dg[5], adherence_g0 = dg[6],
      oracle_adherence_g1 = dg[7], oracle_adherence_g0 = dg[8],
      censor_change_l = dg[9], n_system = N_PER_REP - dfcom,
      mi_m = M, prior_sd = prior_sd, fail = NA_character_, stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, rows)
  if (return_draws) attr(out, "mi_draws") <- list(est = estimates, se = sqrt(variances))
  out
}

calibrate_imputations <- function(scenarios) {
  candidates <- MI_CANDIDATES
  bench <- scenarios[scenarios$benchmark != "", , drop = FALSE]
  keys <- unique(bench[, c("benchmark", "specification", "validation_n")])
  keys <- keys[rep(seq_len(nrow(keys)), length.out = MI_CAL_DATASETS), , drop = FALSE]
  q99_est <- q99_se <- setNames(rep(NA_real_, length(candidates)), candidates)
  records <- vector("list", nrow(keys))
  for (i in seq_len(nrow(keys))) {
    take <- bench$benchmark == keys$benchmark[i] &
      bench$specification == keys$specification[i] &
      bench$validation_n == keys$validation_n[i]
    s <- bench[which(take)[1L], , drop = FALSE]
    dat <- gen_replicate(s, N_PER_REP)
    fit <- est_corrected(dat, s, "AL", MI_CAL_DRAWS,
                         method = "calibration", return_draws = TRUE)
    dr <- attr(fit, "mi_draws")
    if (is.null(dr)) stop("MI calibration failed in dataset ", i)
    records[[i]] <- list(q = dr$est[, 1L], se = dr$se[, 1L])
  }
  for (M in candidates) {
    sdq <- sds <- numeric()
    for (z in records) {
      qbar <- sebar <- numeric(100L)
      for (b in seq_len(100L)) {
        ix <- sample.int(length(z$q), M, replace = FALSE)
        qbar[b] <- mean(z$q[ix])
        W <- mean(z$se[ix]^2)
        B <- stats::var(z$q[ix])
        sebar[b] <- sqrt(W + (1 + 1 / M) * B)
      }
      sdq <- c(sdq, stats::sd(qbar))
      sds <- c(sds, stats::sd(sebar))
    }
    q99_est[as.character(M)] <- unname(stats::quantile(sdq, 0.99))
    q99_se[as.character(M)] <- unname(stats::quantile(sds, 0.99))
  }
  pass <- candidates[q99_est <= MI_CAL_THRESHOLD & q99_se <= MI_CAL_THRESHOLD]
  selected <- if (length(pass)) min(pass) else MI_FALLBACK
  list(selected_M = selected, q99_est = q99_est, q99_se = q99_se,
       passed = length(pass) > 0L)
}
