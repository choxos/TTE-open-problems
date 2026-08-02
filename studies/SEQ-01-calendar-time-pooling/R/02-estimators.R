## Study SEQ-01: estimators, joint linearization, truth, and calibration.

weighted_tabulate <- function(bin, weights, nbins) {
  ## base::tabulate has no `weights` argument. The generated code invented one,
  ## which is the failure mode this program has to assume: an invented base-R
  ## argument reads exactly like a correct call. A grouped sum is the intended
  ## operation, and rowsum keeps empty bins at zero rather than dropping them.
  out <- numeric(nbins)
  if (!length(bin)) return(out)
  s <- rowsum(as.numeric(weights), bin, reorder = FALSE)
  idx <- as.integer(rownames(s))
  keep <- idx >= 1L & idx <= nbins
  out[idx[keep]] <- s[keep]
  out
}

aggregate_id_score <- function(X, scalar, id, n) {
  out <- matrix(0, nrow = n, ncol = ncol(X))
  z <- rowsum(X * scalar, id, reorder = FALSE)
  out[as.integer(rownames(z)), ] <- z
  out
}

safe_logit_fit <- function(X, y, weights = rep(1, length(y)),
                           probability_check = FALSE) {
  use <- is.finite(y) & is.finite(weights) & weights > 0 &
    apply(X, 1L, function(z) all(is.finite(z)))
  if (sum(use) <= ncol(X)) return(list(ok = FALSE, why = "insufficient-model-rows"))
  fit <- try(suppressWarnings(stats::glm.fit(
    x = X[use, , drop = FALSE], y = y[use], weights = weights[use],
    family = stats::binomial(), intercept = FALSE,
    control = stats::glm.control(epsilon = 1e-9, maxit = 60L)
  )), silent = TRUE)
  if (inherits(fit, "try-error") || !isTRUE(fit$converged))
    return(list(ok = FALSE, why = "glm-nonconvergence"))
  if (fit$rank < ncol(X) || anyNA(fit$coefficients))
    return(list(ok = FALSE, why = "rank-deficient-model"))
  if (any(!is.finite(fit$coefficients)) || any(abs(fit$coefficients) > 20))
    return(list(ok = FALSE, why = "invalid-model-coefficient"))
  p <- expit(drop(X %*% fit$coefficients))
  if (probability_check && any(p < 1e-6 | p > 0.999999))
    return(list(ok = FALSE, why = "extreme-initiation-probability"))
  list(ok = TRUE, coef = unname(fit$coefficients), p = p, fit = fit)
}

CELL_GRID <- transform(
  expand.grid(
    start_idx = seq_along(STARTS), j = 0:(N_FOLLOW - 1L), G = 0:1,
    KEEP.OUT.ATTRS = FALSE
  ),
  start = STARTS[start_idx], q_start = START_Q[start_idx]
)
N_CELL <- nrow(CELL_GRID)
.X_CACHE <- new.env(parent = emptyenv())

make_cell_X <- function(type) {
  if (exists(type, envir = .X_CACHE, inherits = FALSE))
    return(get(type, envir = .X_CACHE, inherits = FALSE))
  g <- CELL_GRID
  F <- diag(N_FOLLOW)[g$j + 1L, , drop = FALSE]
  S <- START_BASIS[g$start_idx, , drop = FALSE]
  FS <- do.call(cbind, lapply(seq_len(ncol(S)), function(z) F * S[, z]))
  GF <- F * g$G
  GFS <- FS * g$G

  X <- switch(
    type,
    package_like = cbind(
      intercept = 1, G = g$G, j = g$j, j2 = g$j^2,
      Gj = g$G * g$j, Gj2 = g$G * g$j^2,
      q = g$q_start, q2 = g$q_start^2
    ),
    equal_common = cbind(F, FS, GF),
    ## Critique fix: the full hierarchical surface contains treatment by
    ## follow-up by start-time terms.
    equal_flexible = cbind(F, FS, GF, GFS),
    ## Critique fix: baseline calendar adjustment changes while the complete
    ## treatment surface remains identical across the ablation family.
    calendar_omitted = cbind(F, GF, GFS),
    calendar_quadratic = cbind(F, F * g$q_start, F * g$q_start^2, GF, GFS),
    stop("unknown outcome model: ", type)
  )
  colnames(X) <- paste0("x", seq_len(ncol(X)))
  assign(type, X, envir = .X_CACHE)
  X
}

prepare_analysis <- function(hist) {
  nat <- try(natural_initiation_rows(hist), silent = TRUE)
  expd <- try(expand_sequential_trials(hist), silent = TRUE)
  if (inherits(nat, "try-error") || inherits(expd, "try-error") || !nrow(expd))
    return(list(ok = FALSE, why = "expansion-failed"))
  arm <- table(factor(expd$start_idx, levels = seq_along(STARTS)),
               factor(expd$G, levels = 0:1))
  if (any(arm == 0)) return(list(ok = FALSE, why = "missing-required-arm"))
  nat$freq <- 1
  ## `nat` is a data.table, and assigning a matrix into one of its columns goes
  ## through set(), which flattens it: a six-column design matrix became 173,916
  ## values assigned to 28,986 rows and every replicate in the study died as
  ## `estimation-error`. The matrices travel in the returned list instead, which
  ## is where the only consumer reads them from.
  list(ok = TRUE, hist = hist, nat = nat, expd = expd,
       Xd = cbind(1, nat$q, nat$Sex, nat$R, nat$C, nat$L),
       Xn = cbind(1, nat$q))
}

fit_weight_models <- function(prep, freq = rep(1, prep$hist$n), scores = TRUE) {
  nat <- prep$nat
  Xd <- prep$Xd
  Xn <- prep$Xn
  fw <- freq[nat$id]
  fd <- safe_logit_fit(Xd, nat$I, fw, probability_check = TRUE)
  if (!fd$ok) return(fd)
  fn <- safe_logit_fit(Xn, nat$I, fw, probability_check = TRUE)
  if (!fn$ok) return(fn)

  out <- list(ok = TRUE, bd = fd$coef, bn = fn$coef, pd = fd$p, pn = fn$p)
  if (scores) {
    n <- prep$hist$n
    Ud <- aggregate_id_score(Xd, fw * (nat$I - fd$p), nat$id, n)
    Un <- aggregate_id_score(Xn, fw * (nat$I - fn$p), nat$id, n)
    Ad <- crossprod(Xd, Xd * (fw * fd$p * (1 - fd$p))) / n
    An <- crossprod(Xn, Xn * (fw * fn$p * (1 - fn$p))) / n
    A <- matrix(0, nrow = ncol(Xd) + ncol(Xn), ncol = ncol(Xd) + ncol(Xn))
    A[seq_len(ncol(Xd)), seq_len(ncol(Xd))] <- Ad
    ni <- ncol(Xd) + seq_len(ncol(Xn))
    A[ni, ni] <- An
    out$U <- cbind(Ud, Un)
    out$A <- A
  }
  out
}

calc_analysis_weights <- function(prep, wf, derivatives = TRUE) {
  d <- prep$expd
  Xd0 <- cbind(1, d$q_start, d$Sex, d$R, d$C, d$L_start)
  Xn0 <- cbind(1, d$q_start)
  Xd <- cbind(1, d$q, d$Sex, d$R, d$C, d$L)
  Xn <- cbind(1, d$q)
  pd0 <- expit(drop(Xd0 %*% wf$bd))
  pn0 <- expit(drop(Xn0 %*% wf$bn))
  pd <- expit(drop(Xd %*% wf$bd))
  pn <- expit(drop(Xn %*% wf$bn))
  if (any(c(pd0, pn0, pd, pn) < 1e-6 | c(pd0, pn0, pd, pn) > 0.999999))
    return(list(ok = FALSE, why = "extreme-initiation-probability"))

  logw <- ifelse(d$G == 1L, log(pn0) - log(pd0),
                 log1p(-pn0) - log1p(-pd0))
  D <- if (derivatives) matrix(0, nrow = nrow(d), ncol = 8L) else NULL
  if (derivatives) {
    D[, 1:6] <- Xd0 * (pd0 - d$G)
    D[, 7:8] <- Xn0 * (d$G - pn0)
  }

  for (s in seq_along(STARTS)) {
    si <- which(d$start_idx == s)
    if (!length(si)) next
    np <- max(d$pos[si])
    clog <- numeric(np)
    cd <- if (derivatives) matrix(0, np, 6L) else NULL
    cn <- if (derivatives) matrix(0, np, 2L) else NULL
    for (j in 1:(N_FOLLOW - 1L)) {
      z <- which(d$start_idx == s & d$j == j)
      ctrl <- z[d$G[z] == 0L]
      if (length(ctrl)) {
        p <- d$pos[ctrl]
        clog[p] <- clog[p] + log1p(-pn[ctrl]) - log1p(-pd[ctrl])
        if (derivatives) {
          cd[p, ] <- cd[p, , drop = FALSE] + Xd[ctrl, , drop = FALSE] * pd[ctrl]
          cn[p, ] <- cn[p, , drop = FALSE] - Xn[ctrl, , drop = FALSE] * pn[ctrl]
        }
      }
      if (length(z)) {
        p <- d$pos[z]
        logw[z] <- logw[z] + clog[p]
        if (derivatives) {
          D[z, 1:6] <- D[z, 1:6, drop = FALSE] + cd[p, , drop = FALSE]
          D[z, 7:8] <- D[z, 7:8, drop = FALSE] + cn[p, , drop = FALSE]
        }
      }
    }
  }
  w <- exp(logw)
  if (any(!is.finite(w))) return(list(ok = FALSE, why = "nonfinite-weight"))
  list(ok = TRUE, w = w, D = D)
}

fit_outcome <- function(prep, w, type, freq = rep(1, prep$hist$n), normalize = FALSE) {
  d <- prep$expd
  basew <- w * freq[d$id]
  norm_c <- rep(1, N_STARTS)
  if (normalize) {
    Wk <- weighted_tabulate(d$start_idx, basew, N_STARTS)
    if (any(!is.finite(Wk) | Wk <= 0))
      return(list(ok = FALSE, why = "invalid-start-normalizer"))
    norm_c <- sum(Wk) / (N_STARTS * Wk)
  }
  wa <- basew * norm_c[d$start_idx]
  sw <- weighted_tabulate(d$cell, wa, N_CELL)
  swy <- weighted_tabulate(d$cell, wa * d$Y, N_CELL)
  use <- sw > 0
  X <- make_cell_X(type)
  fit <- safe_logit_fit(X[use, , drop = FALSE], swy[use] / sw[use], sw[use])
  if (!fit$ok) return(fit)
  mu <- expit(drop(X %*% fit$coef))
  list(ok = TRUE, coef = fit$coef, X = X, mu = mu, sw = sw, swy = swy,
       basew = basew, wa = wa, norm_c = norm_c, normalized = normalize)
}

prediction_from_beta <- function(type, beta, eligibility) {
  X <- make_cell_X(type)
  h <- expit(drop(X %*% beta))
  risk <- matrix(NA_real_, nrow = N_STARTS, ncol = 2L)
  for (s in seq_along(STARTS)) {
    for (g in 0:1) {
      z <- which(CELL_GRID$start_idx == s & CELL_GRID$G == g)
      risk[s, g + 1L] <- 1 - prod(1 - h[z])
    }
  }
  rd <- risk[, 2L] - risk[, 1L]
  c(rd, theta_equal = mean(rd), theta_pt = sum(eligibility * rd) / sum(eligibility))
}

prediction_draws <- function(type, beta_draws, eligibility) {
  X <- make_cell_X(type)
  eta <- X %*% beta_draws
  h <- expit(eta)
  out <- matrix(NA_real_, nrow = length(FUNCTION_NAMES), ncol = ncol(beta_draws))
  for (s in seq_along(STARTS)) {
    z0 <- which(CELL_GRID$start_idx == s & CELL_GRID$G == 0L)
    z1 <- which(CELL_GRID$start_idx == s & CELL_GRID$G == 1L)
    out[s, ] <- (1 - apply(1 - h[z1, , drop = FALSE], 2L, prod)) -
      (1 - apply(1 - h[z0, , drop = FALSE], 2L, prod))
  }
  out[N_STARTS + 1L, ] <- colMeans(out[seq_len(N_STARTS), , drop = FALSE])
  out[N_STARTS + 2L, ] <- colSums(out[seq_len(N_STARTS), , drop = FALSE] * eligibility) /
    sum(eligibility)
  rownames(out) <- FUNCTION_NAMES
  out
}

numeric_prediction_gradient <- function(type, beta, eligibility) {
  base <- prediction_from_beta(type, beta, eligibility)
  G <- matrix(NA_real_, nrow = length(base), ncol = length(beta))
  for (j in seq_along(beta)) {
    e <- 1e-6 * max(1, abs(beta[j]))
    up <- beta; up[j] <- up[j] + e
    dn <- beta; dn[j] <- dn[j] - e
    G[, j] <- (prediction_from_beta(type, up, eligibility) -
                  prediction_from_beta(type, dn, eligibility)) / (2 * e)
  }
  G
}

model_with_inference <- function(prep, wf, wo, fit, type, XI, eligibility) {
  d <- prep$expd
  n <- prep$hist$n
  X <- fit$X
  r <- fit$wa * (d$Y - fit$mu[d$cell])
  M <- matrix(0, nrow = n, ncol = N_CELL)
  M[cbind(d$id, d$cell)] <- r
  Uo <- M %*% X
  Q <- vapply(seq_len(8L), function(z)
    weighted_tabulate(d$cell, r * wo$D[, z], N_CELL), numeric(N_CELL))
  Aow <- -crossprod(X, Q) / n
  Aoo <- crossprod(X, X * (fit$sw * fit$mu * (1 - fit$mu))) / n

  if (!fit$normalized) {
    A <- rbind(cbind(wf$A, matrix(0, 8L, ncol(X))), cbind(Aow, Aoo))
    U <- cbind(wf$U, Uo)
    oi <- 8L + seq_len(ncol(X))
  } else {
    key <- (d$id - 1L) * N_STARTS + d$start_idx
    wk <- matrix(weighted_tabulate(key, wo$w, n * N_STARTS),
                 nrow = n, byrow = TRUE)
    total <- rowSums(wk)
    Uc <- matrix(total / N_STARTS, nrow = n, ncol = N_STARTS) -
      sweep(wk, 2L, fit$norm_c, "*")

    allwd <- colSums(wo$w * wo$D)
    startwd <- vapply(seq_len(8L), function(z)
      weighted_tabulate(d$start_idx, wo$w * wo$D[, z], N_STARTS),
      numeric(N_STARTS))
    Acw <- sweep(startwd, 1L, fit$norm_c, "*") -
      matrix(allwd / N_STARTS, nrow = N_STARTS, ncol = 8L, byrow = TRUE)
    Acw <- Acw / n
    Acc <- diag(fit$norm_c * colSums(wk) / n, N_STARTS)

    cell_r <- weighted_tabulate(d$cell, r, N_CELL)
    Aoc <- matrix(0, nrow = ncol(X), ncol = N_STARTS)
    for (s in seq_along(STARTS)) {
      z <- which(CELL_GRID$start_idx == s)
      Aoc[, s] <- -drop(crossprod(X[z, , drop = FALSE], cell_r[z])) / n
    }

    p <- 8L + N_STARTS + ncol(X)
    A <- matrix(0, p, p)
    A[1:8, 1:8] <- wf$A
    ci <- 8L + seq_len(N_STARTS)
    oi <- 8L + N_STARTS + seq_len(ncol(X))
    A[ci, 1:8] <- Acw
    A[ci, ci] <- Acc
    A[oi, 1:8] <- Aow
    A[oi, ci] <- Aoc
    A[oi, oi] <- Aoo
    U <- cbind(wf$U, Uc, Uo)
  }

  if (qr(A, tol = 1e-8)$rank < ncol(A) || any(!is.finite(A)))
    return(list(ok = FALSE, why = "singular-joint-linearization"))
  rhs <- crossprod(U, XI) / n
  delta <- try(solve(A, rhs), silent = TRUE)
  if (inherits(delta, "try-error") || any(!is.finite(delta)))
    return(list(ok = FALSE, why = "failed-joint-linearization"))
  beta_draws <- fit$coef + delta[oi, , drop = FALSE]
  draws <- prediction_draws(type, beta_draws, eligibility)
  if (any(!is.finite(draws)))
    return(list(ok = FALSE, why = "nonfinite-standardized-draw"))
  point <- prediction_from_beta(type, fit$coef, eligibility)
  se <- apply(draws, 1L, stats::sd)
  lo <- apply(draws, 1L, stats::quantile, probs = 0.025, type = 1)
  hi <- apply(draws, 1L, stats::quantile, probs = 0.975, type = 1)

  fixed_se <- fixed_lo <- fixed_hi <- rep(NA_real_, length(point))
  if (type == "package_like") {
    Vb <- try(solve(Aoo) %*% (crossprod(Uo) / n^2) %*% solve(Aoo), silent = TRUE)
    if (!inherits(Vb, "try-error") && all(is.finite(Vb))) {
      G <- numeric_prediction_gradient(type, fit$coef, eligibility)
      Vf <- G %*% Vb %*% t(G)
      fixed_se <- sqrt(pmax(0, diag(Vf)))
      fixed_lo <- point - 1.96 * fixed_se
      fixed_hi <- point + 1.96 * fixed_se
    }
  }
  list(ok = TRUE, point = point, draws = draws, se = se, lo = lo, hi = hi,
       fixed_se = fixed_se, fixed_lo = fixed_lo, fixed_hi = fixed_hi)
}

material_diagnostic <- function(point, draws) {
  rd <- point[seq_len(N_STARTS)]
  rd_draw <- draws[seq_len(N_STARTS), , drop = FALSE]
  pd <- rd[PAIR_INDEX[1L, ]] - rd[PAIR_INDEX[2L, ]]
  dd <- rd_draw[PAIR_INDEX[1L, ], , drop = FALSE] -
    rd_draw[PAIR_INDEX[2L, ], , drop = FALSE]
  se <- apply(dd, 1L, stats::sd)
  Z <- sweep(dd, 1L, pd, "-")
  nz <- se > 0
  Z[nz, ] <- sweep(Z[nz, , drop = FALSE], 1L, se[nz], "/")
  Z[!nz, ] <- 0
  crit <- unname(stats::quantile(apply(abs(Z), 2L, max), 0.95, type = 1))
  lo <- pd - crit * se
  hi <- pd + crit * se
  diagnostic <- if (any(lo > HET_MATERIAL | hi < -HET_MATERIAL)) {
    "positive"
  } else if (all(lo >= -HET_MATERIAL & hi <= HET_MATERIAL)) {
    "negative"
  } else {
    "indeterminate"
  }

  C <- matrix(0, nrow = N_STARTS - 1L, ncol = N_STARTS)
  C[, 1L] <- -1
  C[cbind(seq_len(N_STARTS - 1L), 2:N_STARTS)] <- 1
  V <- stats::cov(t(rd_draw))
  q <- drop(C %*% rd)
  CV <- C %*% V %*% t(C)
  wald <- try(drop(t(q) %*% solve(CV, q)), silent = TRUE)
  p <- if (inherits(wald, "try-error") || !is.finite(wald)) NA_real_ else
    stats::pchisq(wald, df = N_STARTS - 1L, lower.tail = FALSE)
  list(class = diagnostic, exact_p = p, critical = crit,
       pair_lo = lo, pair_hi = hi)
}

life_table_with_inference <- function(prep, wf, wo, XI, eligibility) {
  d <- prep$expd
  n <- prep$hist$n
  sw <- weighted_tabulate(d$cell, wo$w, N_CELL)
  swy <- weighted_tabulate(d$cell, wo$w * d$Y, N_CELL)
  sw2 <- weighted_tabulate(d$cell, wo$w^2, N_CELL)
  ess <- sw^2 / sw2
  valid <- is.finite(sw) & sw > 0 & is.finite(ess) & ess >= ESS_MIN
  h <- swy / sw
  r <- wo$w * (d$Y - h[d$cell])
  Uh <- matrix(0, nrow = n, ncol = N_CELL)
  Uh[cbind(d$id, d$cell)] <- r
  Q <- vapply(seq_len(8L), function(z)
    weighted_tabulate(d$cell, r * wo$D[, z], N_CELL), numeric(N_CELL))
  Ahw <- -Q / n
  Ah <- sw / n
  rhsw <- crossprod(wf$U, XI) / n
  dw <- try(solve(wf$A, rhsw), silent = TRUE)
  if (inherits(dw, "try-error"))
    return(list(ok = FALSE, why = "failed-life-table-linearization"))
  rhsh <- crossprod(Uh, XI) / n
  dh <- sweep(rhsh - Ahw %*% dw, 1L, Ah, "/")
  hd <- h + dh

  life_fun <- function(hazard) {
    risk <- matrix(NA_real_, N_STARTS, 2L)
    for (s in seq_along(STARTS)) for (g in 0:1) {
      z <- which(CELL_GRID$start_idx == s & CELL_GRID$G == g)
      risk[s, g + 1L] <- 1 - prod(1 - hazard[z])
    }
    rd <- risk[, 2L] - risk[, 1L]
    c(rd, theta_equal = mean(rd), theta_pt = sum(eligibility * rd) / sum(eligibility))
  }
  point <- life_fun(h)
  draws <- vapply(seq_len(ncol(hd)), function(b) life_fun(hd[, b]),
                  numeric(length(FUNCTION_NAMES)))
  rownames(draws) <- FUNCTION_NAMES
  saturated_ok <- all(valid) && all(is.finite(draws))
  mid_cells <- which(CELL_GRID$start == 12L)
  standalone_ok <- all(valid[mid_cells]) && all(is.finite(draws[STARTS == 12L, ]))
  list(ok = saturated_ok || standalone_ok, point = point, draws = draws,
       se = apply(draws, 1L, stats::sd),
       lo = apply(draws, 1L, stats::quantile, 0.025, type = 1),
       hi = apply(draws, 1L, stats::quantile, 0.975, type = 1),
       saturated_ok = saturated_ok, standalone_ok = standalone_ok,
       ess = ess, why = "empty-or-low-ess-life-table-cell")
}

result_template <- function(why = "not-run") {
  model <- expand.grid(method = c(MODEL_METHODS, "start_saturated"),
                       function_index = seq_along(FUNCTION_NAMES),
                       KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  model$estimand <- ifelse(model$function_index <= N_STARTS, "rd_k",
                           ifelse(model$function_index == N_STARTS + 1L,
                                  "theta_equal", "theta_pt"))
  model$start <- ifelse(model$function_index <= N_STARTS,
                        STARTS[model$function_index], NA_integer_)
  one <- data.frame(method = "standalone_12", function_index = which(STARTS == 12L),
                    estimand = "rd_k", start = 12L, stringsAsFactors = FALSE)
  out <- rbind(model, one)
  for (nm in c("est", "se", "lo", "hi", "fixed_se", "fixed_lo", "fixed_hi",
               "homogeneity_p", "max_weight", "min_ess", "boot_se", "boot_lo",
               "boot_hi", "linearization_seconds", "bootstrap_seconds",
               "memory_mb")) out[[nm]] <- NA_real_
  out$diagnostic <- NA_character_
  out$boot_diagnostic <- NA_character_
  out$boot_success <- NA_integer_
  out$ablation_valid <- NA
  out$fail <- why
  out
}

fill_result <- function(out, method, fit) {
  z <- which(out$method == method)
  idx <- out$function_index[z]
  out$est[z] <- fit$point[idx]
  out$se[z] <- fit$se[idx]
  out$lo[z] <- fit$lo[idx]
  out$hi[z] <- fit$hi[idx]
  if (!is.null(fit$fixed_se)) {
    out$fixed_se[z] <- fit$fixed_se[idx]
    out$fixed_lo[z] <- fit$fixed_lo[idx]
    out$fixed_hi[z] <- fit$fixed_hi[idx]
  }
  out$fail[z] <- NA_character_
  out
}

fit_bootstrap_pair <- function(prep, freq, eligibility) {
  wf <- fit_weight_models(prep, freq, scores = FALSE)
  if (!wf$ok) return(list(ok = FALSE))
  wo <- calc_analysis_weights(prep, wf, derivatives = FALSE)
  if (!wo$ok) return(list(ok = FALSE))
  fc <- fit_outcome(prep, wo$w, "equal_common", freq, normalize = TRUE)
  ff <- fit_outcome(prep, wo$w, "equal_flexible", freq, normalize = TRUE)
  if (!fc$ok || !ff$ok) return(list(ok = FALSE))
  list(ok = TRUE,
       common = prediction_from_beta("equal_common", fc$coef, eligibility),
       flexible = prediction_from_beta("equal_flexible", ff$coef, eligibility))
}

full_person_bootstrap <- function(prep, eligibility, common_point, flexible_point) {
  n <- prep$hist$n
  index <- matrix(sample.int(n, n * N_PERSON_BOOT, replace = TRUE), nrow = n)
  cb <- matrix(NA_real_, length(FUNCTION_NAMES), N_PERSON_BOOT)
  fb <- cb
  ok <- logical(N_PERSON_BOOT)
  for (b in seq_len(N_PERSON_BOOT)) {
    freq <- tabulate(index[, b], nbins = n)
    x <- fit_bootstrap_pair(prep, freq, eligibility)
    if (x$ok) {
      cb[, b] <- x$common
      fb[, b] <- x$flexible
      ok[b] <- TRUE
    }
  }
  success <- sum(ok)
  if (success < MIN_PERSON_BOOT)
    return(list(ok = FALSE, success = success))
  cb <- cb[, ok, drop = FALSE]
  fb <- fb[, ok, drop = FALSE]
  summarize <- function(x) list(
    se = apply(x, 1L, stats::sd),
    lo = apply(x, 1L, stats::quantile, 0.025, type = 1),
    hi = apply(x, 1L, stats::quantile, 0.975, type = 1)
  )
  ## Critique fix: calibration bands and classifications are built from the
  ## standardized risk-difference vector, not pooled-logit interaction terms.
  diag <- material_diagnostic(flexible_point, fb)
  list(ok = TRUE, success = success, common = summarize(cb),
       flexible = summarize(fb), diagnostic = diag$class)
}

fit_all_estimators <- function(hist, XI, calibrate = FALSE) {
  out <- result_template()
  prep <- prepare_analysis(hist)
  if (!prep$ok) { out$fail <- prep$why; return(out) }
  eligibility <- vapply(STARTS, function(k) length(eligible_ids(hist, k)), numeric(1))
  wf <- fit_weight_models(prep)
  if (!wf$ok) { out$fail <- wf$why; return(out) }
  wo <- calc_analysis_weights(prep, wf, derivatives = TRUE)
  if (!wo$ok) { out$fail <- wo$why; return(out) }

  specs <- list(
    package_like = c("package_like", FALSE),
    equal_common = c("equal_common", TRUE),
    equal_flexible = c("equal_flexible", TRUE),
    calendar_omitted = c("calendar_omitted", TRUE),
    calendar_quadratic = c("calendar_quadratic", TRUE)
  )
  fits <- list()
  tlin <- proc.time()[["elapsed"]]
  for (method in names(specs)) {
    type <- specs[[method]][1]
    normalize <- as.logical(specs[[method]][2])
    fo <- fit_outcome(prep, wo$w, type, normalize = normalize)
    if (!fo$ok) {
      out$fail[out$method == method] <- fo$why
      next
    }
    fi <- try(model_with_inference(prep, wf, wo, fo, type, XI, eligibility),
              silent = TRUE)
    if (inherits(fi, "try-error") || !isTRUE(fi$ok)) {
      out$fail[out$method == method] <- if (inherits(fi, "try-error"))
        "model-inference-error" else fi$why
      next
    }
    fits[[method]] <- fi
    out <- fill_result(out, method, fi)
  }
  linearization_seconds <- proc.time()[["elapsed"]] - tlin

  lt <- try(life_table_with_inference(prep, wf, wo, XI, eligibility), silent = TRUE)
  if (!inherits(lt, "try-error") && isTRUE(lt$ok)) {
    if (lt$saturated_ok) {
      out <- fill_result(out, "start_saturated", lt)
    } else out$fail[out$method == "start_saturated"] <- lt$why
    z <- which(out$method == "standalone_12")
    if (lt$standalone_ok) {
      i <- which(STARTS == 12L)
      out$est[z] <- lt$point[i]; out$se[z] <- lt$se[i]
      out$lo[z] <- lt$lo[i]; out$hi[z] <- lt$hi[i]
      out$fail[z] <- NA_character_
    } else out$fail[z] <- lt$why
  } else {
    out$fail[out$method %in% c("start_saturated", "standalone_12")] <-
      "life-table-inference-error"
  }

  ## Critique fix: the matched ablation is valid only when omitted, quadratic,
  ## and flexible fits all succeed on identical data and weights.
  ablation_ok <- all(c("equal_flexible", "calendar_omitted", "calendar_quadratic") %in%
                       names(fits))
  out$ablation_valid <- ablation_ok

  if (!is.null(fits$equal_flexible)) {
    dg <- material_diagnostic(fits$equal_flexible$point,
                              fits$equal_flexible$draws)
    z <- out$method == "equal_flexible"
    out$diagnostic[z] <- dg$class
    out$homogeneity_p[z] <- dg$exact_p
  }

  expd <- prep$expd
  maxw <- max(wo$w)
  cell_sw <- weighted_tabulate(expd$cell, wo$w, N_CELL)
  cell_sw2 <- weighted_tabulate(expd$cell, wo$w^2, N_CELL)
  miness <- min(cell_sw^2 / cell_sw2)
  out$max_weight <- maxw
  out$min_ess <- miness
  out$linearization_seconds <- linearization_seconds

  if (calibrate && !is.null(fits$equal_common) && !is.null(fits$equal_flexible)) {
    tb <- proc.time()[["elapsed"]]
    boot <- full_person_bootstrap(prep, eligibility, fits$equal_common$point,
                                  fits$equal_flexible$point)
    out$bootstrap_seconds <- proc.time()[["elapsed"]] - tb
    out$boot_success[out$method %in% c("equal_common", "equal_flexible")] <- boot$success
    if (boot$ok) {
      for (method in c("equal_common", "equal_flexible")) {
        z <- which(out$method == method)
        idx <- out$function_index[z]
        out$boot_se[z] <- boot[[sub("equal_", "", method)]]$se[idx]
        out$boot_lo[z] <- boot[[sub("equal_", "", method)]]$lo[idx]
        out$boot_hi[z] <- boot[[sub("equal_", "", method)]]$hi[idx]
      }
      out$boot_diagnostic[out$method == "equal_flexible"] <- boot$diagnostic
    }
  }
  out$memory_mb <- max(gc()[, 2L])
  out
}

## Truth support follows. Each chunk stores intervention event counts and
## denominator-only weighted natural-row totals. Numerator factors depend only on
## calendar time and are applied after the pooled population numerator score is
## solved.
projection_base_cells <- function(hist, scen) {
  bw <- bwy <- array(0, dim = c(N_STARTS, N_FOLLOW, 2L))
  for (s in seq_along(STARTS)) {
    k <- STARTS[s]
    ids <- eligible_ids(hist, k)
    if (!length(ids)) next
    G <- as.integer(hist$initiated[ids, k + 1L])
    L0 <- hist$L[ids, k + 1L]
    pd0 <- expit(-3.60 + 0.20 * hist$Sex[ids] + 0.30 * hist$R[ids] +
                   0.45 * hist$C[ids] + 0.55 * L0 + scen$a[[1]] * q_of(k))
    logbase <- -ifelse(G == 1L, log(pd0), log1p(-pd0))
    cumulative <- numeric(length(ids))
    for (j in 0:(N_FOLLOW - 1L)) {
      t <- k + j
      at_risk <- is.na(hist$event_time[ids]) | hist$event_time[ids] > t
      adherent <- G == 1L | is.na(hist$first_treatment[ids]) |
        hist$first_treatment[ids] > t
      keep <- at_risk & adherent
      if (j > 0L) {
        ctrl <- keep & G == 0L
        if (any(ctrl)) {
          pd <- expit(-3.60 + 0.20 * hist$Sex[ids[ctrl]] +
                        0.30 * hist$R[ids[ctrl]] + 0.45 * hist$C[ids[ctrl]] +
                        0.55 * hist$L[ids[ctrl], t + 1L] + scen$a[[1]] * q_of(t))
          cumulative[ctrl] <- cumulative[ctrl] - log1p(-pd)
        }
      }
      for (g in 0:1) {
        z <- which(keep & G == g)
        if (!length(z)) next
        w <- exp(logbase[z] + cumulative[z])
        bw[s, j + 1L, g + 1L] <- sum(w)
        bwy[s, j + 1L, g + 1L] <-
          sum(w * fails_at(hist$event_time[ids[z]], t))
      }
    }
  }
  list(w = bw, wy = bwy)
}

truth_chunk <- function(scen, n = TRUTH_CHUNK) {
  t0 <- proc.time()[["elapsed"]]
  noise <- make_noise(n)
  hist <- gen_natural_history(scen, noise)
  eligible <- event1 <- event0 <- numeric(N_STARTS)
  for (s in seq_along(STARTS)) {
    fu <- matrix(stats::runif(n * N_FOLLOW), nrow = n)
    ei <- matrix(stats::rnorm(n * N_FOLLOW, sd = 0.70), nrow = n)
    z <- simulate_intervention_pair(hist, scen, STARTS[s], fu, ei)
    eligible[s] <- z[["eligible"]]
    event1[s] <- z[["event1"]]
    event0[s] <- z[["event0"]]
  }
  init_n <- init_y <- numeric(N_CAL_MONTHS)
  for (tt in seq_len(N_CAL_MONTHS)) {
    t <- tt - 1L
    id <- which((is.na(hist$event_time) | hist$event_time > t) &
                  (is.na(hist$first_treatment) | hist$first_treatment >= t))
    init_n[tt] <- length(id)
    init_y[tt] <- sum(hist$initiated[id, tt])
  }
  base <- projection_base_cells(hist, scen)
  list(n = n, eligible = eligible, event1 = event1, event0 = event0,
       init_n = init_n, init_y = init_y, base_w = base$w,
       base_wy = base$wy,
       elapsed = proc.time()[["elapsed"]] - t0)
}

numerator_factor <- function(beta) {
  pn <- expit(beta[1L] + beta[2L] * q_of(0:(N_CAL_MONTHS - 1L)))
  out <- numeric(N_CELL)
  for (r in seq_len(N_CELL)) {
    k <- CELL_GRID$start[r]
    j <- CELL_GRID$j[r]
    if (CELL_GRID$G[r] == 1L) {
      out[r] <- pn[k + 1L]
    } else {
      months <- k + 0:j
      out[r] <- prod(1 - pn[months + 1L])
    }
  }
  out
}

fit_projection_cells <- function(sw, swy, type, eligibility, normalize) {
  if (normalize) {
    Wk <- weighted_tabulate(CELL_GRID$start_idx, sw, N_STARTS)
    if (any(Wk <= 0)) return(NA_real_)
    cc <- sum(Wk) / (N_STARTS * Wk)
    sw <- sw * cc[CELL_GRID$start_idx]
    swy <- swy * cc[CELL_GRID$start_idx]
  }
  use <- sw > 0
  X <- make_cell_X(type)
  fit <- safe_logit_fit(X[use, , drop = FALSE], swy[use] / sw[use], sw[use])
  if (!fit$ok) return(NA_real_)
  prediction_from_beta(type, fit$coef, eligibility)[["theta_equal"]]
}

projection_from_chunks <- function(chunks) {
  init_n <- Reduce(`+`, lapply(chunks, `[[`, "init_n"))
  init_y <- Reduce(`+`, lapply(chunks, `[[`, "init_y"))
  Xn <- cbind(1, q_of(0:(N_CAL_MONTHS - 1L)))
  fn <- safe_logit_fit(Xn, init_y / init_n, init_n)
  if (!fn$ok) return(setNames(rep(NA_real_, length(PROJECTION_METHODS)),
                              PROJECTION_METHODS))
  nf <- numerator_factor(fn$coef)
  bw <- Reduce(`+`, lapply(chunks, `[[`, "base_w"))
  bwy <- Reduce(`+`, lapply(chunks, `[[`, "base_wy"))
  sw <- as.vector(bw) * nf
  swy <- as.vector(bwy) * nf
  eligibility <- Reduce(`+`, lapply(chunks, `[[`, "eligible"))
  c(
    package_like = fit_projection_cells(sw, swy, "package_like", eligibility, FALSE),
    equal_common = fit_projection_cells(sw, swy, "equal_common", eligibility, TRUE),
    calendar_omitted = fit_projection_cells(sw, swy, "calendar_omitted", eligibility, TRUE),
    calendar_quadratic = fit_projection_cells(sw, swy, "calendar_quadratic", eligibility, TRUE)
  )
}

truth_point <- function(chunks) {
  E <- Reduce(`+`, lapply(chunks, `[[`, "eligible"))
  Y1 <- Reduce(`+`, lapply(chunks, `[[`, "event1"))
  Y0 <- Reduce(`+`, lapply(chunks, `[[`, "event0"))
  r1 <- Y1 / E
  r0 <- Y0 / E
  rd <- r1 - r0
  list(eligible = E, p_eligible = E / sum(vapply(chunks, `[[`, numeric(1), "n")),
       risk1 = r1, risk0 = r0, rd = rd, theta_equal = mean(rd),
       theta_pt = sum(E * rd) / sum(E), delta = max(rd) - min(rd))
}

truth_summary <- function(chunks, scen, nboot = N_TRUTH_BOOT) {
  point <- truth_point(chunks)
  nc <- length(chunks)
  boot_index <- matrix(sample.int(nc, nc * nboot, replace = TRUE), nrow = nc)
  rd_boot <- matrix(NA_real_, N_STARTS, nboot)
  theta_boot <- theta_pt_boot <- delta_boot <- numeric(nboot)
  projection_boot <- matrix(NA_real_, nrow = length(PROJECTION_METHODS), ncol = nboot,
                            dimnames = list(PROJECTION_METHODS, NULL))
  for (b in seq_len(nboot)) {
    cb <- chunks[boot_index[, b]]
    x <- truth_point(cb)
    rd_boot[, b] <- x$rd
    theta_boot[b] <- x$theta_equal
    theta_pt_boot[b] <- x$theta_pt
    delta_boot[b] <- x$delta
    projection_boot[, b] <- projection_from_chunks(cb)
  }

  pair_point <- point$rd[PAIR_INDEX[1L, ]] - point$rd[PAIR_INDEX[2L, ]]
  pair_boot <- rd_boot[PAIR_INDEX[1L, ], , drop = FALSE] -
    rd_boot[PAIR_INDEX[2L, ], , drop = FALSE]
  all_point <- c(point$rd, pair_point)
  all_boot <- rbind(rd_boot, pair_boot)
  all_se <- apply(all_boot, 1L, stats::sd)
  Z <- sweep(all_boot, 1L, all_point, "-")
  nz <- all_se > 0
  Z[nz, ] <- sweep(Z[nz, , drop = FALSE], 1L, all_se[nz], "/")
  Z[!nz, ] <- 0
  crit <- unname(stats::quantile(apply(abs(Z), 2L, max), 0.95, type = 1))
  rd_lo <- point$rd - crit * all_se[seq_len(N_STARTS)]
  rd_hi <- point$rd + crit * all_se[seq_len(N_STARTS)]
  delta_lo <- unname(stats::quantile(delta_boot, 0.025, type = 1))
  delta_hi <- unname(stats::quantile(delta_boot, 0.975, type = 1))
  theta_lo <- unname(stats::quantile(theta_boot, 0.025, type = 1))
  theta_hi <- unname(stats::quantile(theta_boot, 0.975, type = 1))
  truth_class <- if (delta_lo >= HET_MATERIAL) "material" else
    if (delta_hi <= HET_NEAR) "near" else
      if (delta_lo > HET_NEAR && delta_hi < HET_MATERIAL) "indifference" else
        "threshold-crossing"

  curves <- data.frame(
    scenario = scen$scenario[[1]], start = STARTS,
    p_eligible = point$p_eligible, risk1 = point$risk1, risk0 = point$risk0,
    rd = point$rd, rd_lo = rd_lo, rd_hi = rd_hi,
    stringsAsFactors = FALSE
  )
  scenarios <- data.frame(
    scenario = scen$scenario[[1]], theta_equal = point$theta_equal,
    theta_equal_lo = theta_lo, theta_equal_hi = theta_hi,
    theta_pt = point$theta_pt,
    theta_pt_lo = unname(stats::quantile(theta_pt_boot, 0.025, type = 1)),
    theta_pt_hi = unname(stats::quantile(theta_pt_boot, 0.975, type = 1)),
    delta_rd = point$delta, delta_lo = delta_lo, delta_hi = delta_hi,
    truth_class = truth_class, n_chunks = nc,
    n_truth = sum(vapply(chunks, `[[`, numeric(1), "n")),
    truth_seconds = sum(vapply(chunks, `[[`, numeric(1), "elapsed")),
    stringsAsFactors = FALSE
  )
  projection_point <- projection_from_chunks(chunks)
  projections <- data.frame(
    scenario = scen$scenario[[1]], method = names(projection_point),
    projection = unname(projection_point),
    projection_lo = apply(projection_boot, 1L, stats::quantile, 0.025,
                          type = 1, na.rm = TRUE),
    projection_hi = apply(projection_boot, 1L, stats::quantile, 0.975,
                          type = 1, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  list(curves = curves, scenarios = scenarios, projections = projections,
       chunks = chunks)
}

truth_ready <- function(summary) {
  s <- summary$scenarios
  half_width_ok <- (s$theta_equal_hi - s$theta_equal_lo) / 2 < 0.001
  separated <- s$truth_class != "threshold-crossing"
  isTRUE(half_width_ok && separated)
}
