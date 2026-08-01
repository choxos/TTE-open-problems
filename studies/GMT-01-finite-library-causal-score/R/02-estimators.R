## GMT-01: candidate libraries, nested selection, and estimators.

`%||%` <- function(x, y) if (is.null(x)) y else x
clip_prob <- function(x) pmin(pmax(x, PROB_FLOOR), 1 - PROB_FLOOR)

matrix_from <- function(cols, n) {
  z <- c(list(`(Intercept)` = rep(1, n)), cols)
  X <- do.call(cbind, z)
  colnames(X) <- names(z)
  storage.mode(X) <- "double"
  X
}

add_col <- function(x, name, value) {
  x[[name]] <- value
  x
}

g_matrix <- function(d, t, candidate) {
  cols <- list(W1 = d$W1, W2 = d$W2, W3 = d$W3)
  if (t > 0L) cols <- add_col(cols, paste0("A", t - 1L), d[[paste0("A", t - 1L)]])
  if (candidate >= 1L) cols <- add_col(cols, paste0("L", t), d[[paste0("L", t)]])
  if (candidate == 2L || candidate == 4L) {
    L <- d[[paste0("L", t)]]
    cols <- add_col(cols, paste0("L", t, "_sq"), L^2)
    cols <- add_col(cols, paste0("W1_L", t), d$W1 * L)
  }
  if (candidate == 3L || candidate == 4L) {
    Z <- d[[paste0("Z", t)]]
    L <- d[[paste0("L", t)]]
    cols <- add_col(cols, paste0("Z", t), Z)
    if (candidate == 4L) {
      cols <- add_col(cols, paste0("Z", t, "_sq"), Z^2)
      cols <- add_col(cols, paste0("W1_Z", t), d$W1 * Z)
      cols <- add_col(cols, paste0("L", t, "_Z", t), L * Z)
    }
  }
  matrix_from(cols, nrow(d))
}

c_matrix <- function(d, t, candidate) {
  A <- d[[paste0("A", t)]]
  L <- d[[paste0("L", t)]]
  cols <- list(W1 = d$W1, W2 = d$W2, W3 = d$W3)
  cols <- add_col(cols, paste0("A", t), A)
  if (candidate >= 1L) cols <- add_col(cols, paste0("L", t), L)
  if (candidate == 2L) {
    cols <- add_col(cols, paste0("L", t, "_sq"), L^2)
    cols <- add_col(cols, paste0("W1_L", t), d$W1 * L)
    cols <- add_col(cols, paste0("A", t, "_L", t), A * L)
    cols <- add_col(cols, paste0("W3_L", t), d$W3 * L)
  }
  matrix_from(cols, nrow(d))
}

q_matrix <- function(d, t, candidate) {
  cols <- list(W1 = d$W1, W2 = d$W2, W3 = d$W3)
  ## Critique fix: the current regime-fixed A_t is omitted. At t = 0 no
  ## treatment column enters. Only earlier, varying treatment columns remain.
  if (t > 0L) for (j in 0:(t - 1L)) {
    A <- d[[paste0("A", j)]]
    cols <- add_col(cols, paste0("A", j), A)
    cols <- add_col(cols, paste0("A", j, "_W3"), A * d$W3)
  }
  if (candidate >= 1L) for (j in 0:t)
    cols <- add_col(cols, paste0("L", j), d[[paste0("L", j)]])

  if (candidate == 2L) {
    for (j in 0:t) {
      L <- d[[paste0("L", j)]]
      Z <- d[[paste0("Z", j)]]
      cols <- add_col(cols, paste0("Z", j), Z)
      cols <- add_col(cols, paste0("L", j, "_sq"), L^2)
      cols <- add_col(cols, paste0("W1_L", j), d$W1 * L)
    }
    if (t > 0L) for (a in 0:(t - 1L)) for (j in 0:t)
      cols <- add_col(cols, paste0("A", a, "_L", j),
                      d[[paste0("A", a)]] * d[[paste0("L", j)]])
    if (t > 0L) for (j in 0:(t - 1L)) for (k in (j + 1L):t)
      cols <- add_col(cols, paste0("L", j, "_L", k),
                      d[[paste0("L", j)]] * d[[paste0("L", k)]])
  }

  if (candidate == 3L) {
    ## Critique fix: this is the prespecified algebraic closure basis. It adds
    ## the terms created by backward integration in the nonlinear-outcome cell.
    if (t == 2L) {
      cols <- add_col(cols, "L2_sq", d$L2^2)
      cols <- add_col(cols, "W1_L2", d$W1 * d$L2)
    } else if (t == 1L) {
      cols <- add_col(cols, "L1_sq", d$L1^2)
      cols <- add_col(cols, "W1_sq", d$W1^2)
      cols <- add_col(cols, "W1_L1", d$W1 * d$L1)
      cols <- add_col(cols, "L1_W3", d$L1 * d$W3)
      cols <- add_col(cols, "W1_W3", d$W1 * d$W3)
    } else {
      cols <- add_col(cols, "L0_sq", d$L0^2)
      cols <- add_col(cols, "W1_sq", d$W1^2)
      cols <- add_col(cols, "W1_L0", d$W1 * d$L0)
      cols <- add_col(cols, "L0_W3", d$L0 * d$W3)
      cols <- add_col(cols, "W1_W3", d$W1 * d$W3)
    }
  }
  matrix_from(cols, nrow(d))
}

cache_matrices <- function(d) {
  list(
    g = lapply(0:4, function(k) lapply(0:2, function(t) g_matrix(d, t, k))),
    c = lapply(0:2, function(k) lapply(0:2, function(t) c_matrix(d, t, k))),
    q = lapply(0:3, function(k) lapply(0:2, function(t) q_matrix(d, t, k)))
  )
}

has_duplicate_column <- function(X) {
  if (ncol(X) < 2L) return(FALSE)
  for (j in 2:ncol(X)) for (k in seq_len(j - 1L))
    if (isTRUE(all.equal(X[, j], X[, k], tolerance = 0))) return(TRUE)
  FALSE
}

check_design <- function(X, rows, label) {
  X <- X[rows & stats::complete.cases(X), , drop = FALSE]
  rank <- if (nrow(X)) qr(X, tol = 1e-10)$rank else 0L
  v <- if (nrow(X)) apply(X, 2, stats::var) else rep(NA_real_, ncol(X))
  zero <- any(!is.finite(v[-1L]) | v[-1L] <= 1e-12)
  duplicate <- if (nrow(X)) has_duplicate_column(X) else TRUE
  data.frame(label = label, n = nrow(X), columns = ncol(X), rank = rank,
             zero_variance = zero, duplicate = duplicate,
             ok = nrow(X) > ncol(X) && !zero && !duplicate && rank == ncol(X))
}

validate_candidate_matrices <- function(scen, n = N_DRY_RUN) {
  d <- gen_replicate(scen, n = n)
  m <- cache_matrices(d)
  z <- list()
  for (g in 0:4) for (t in 0:2) {
    r <- d[[paste0("R", t)]] == 1L
    z[[length(z) + 1L]] <- check_design(m$g[[g + 1L]][[t + 1L]], r,
                                        sprintf("G%d_t%d", g, t))
  }
  for (cc in 0:2) for (t in 0:2) {
    r <- d[[paste0("R", t)]] == 1L
    z[[length(z) + 1L]] <- check_design(m$c[[cc + 1L]][[t + 1L]], r,
                                        sprintf("C%d_t%d", cc, t))
  }
  for (q in 0:3) for (a in 0:1) for (t in 0:2) {
    r <- d[[paste0("R", t + 1L)]] == 1L & d[[paste0("A", t)]] == a
    z[[length(z) + 1L]] <- check_design(m$q[[q + 1L]][[t + 1L]], r,
                                        sprintf("QL%d_a%d_t%d", q, a, t))
  }
  out <- do.call(rbind, z)
  if (any(!out$ok)) stop("structural candidate-matrix failure: ",
                         paste(out$label[!out$ok], collapse = ", "))
  out
}

safe_glm_fit <- function(X, y) {
  keep <- is.finite(y) & stats::complete.cases(X)
  X <- X[keep, , drop = FALSE]; y <- y[keep]
  if (nrow(X) <= ncol(X) || length(unique(y)) < 2L ||
      qr(X, tol = 1e-10)$rank < ncol(X)) return(NULL)
  fit <- suppressWarnings(try(stats::glm.fit(X, y, family = stats::binomial()),
                              silent = TRUE))
  if (inherits(fit, "try-error") || !isTRUE(fit$converged)) return(NULL)
  b <- fit$coefficients
  if (any(!is.finite(b)) || any(abs(b) > MAX_LOGIT_COEF)) return(NULL)
  list(beta = b)
}

safe_lm_fit <- function(X, y) {
  keep <- is.finite(y) & stats::complete.cases(X)
  X <- X[keep, , drop = FALSE]; y <- y[keep]
  if (nrow(X) <= ncol(X) || qr(X, tol = 1e-10)$rank < ncol(X)) return(NULL)
  fit <- try(stats::lm.fit(X, y), silent = TRUE)
  if (inherits(fit, "try-error") || any(!is.finite(fit$coefficients))) return(NULL)
  list(beta = fit$coefficients)
}

fit_binary_candidate <- function(d, mats, type, candidate, train) {
  n <- nrow(d); pred <- matrix(NA_real_, n, 3L); ok <- TRUE
  lib <- mats[[type]][[candidate + 1L]]
  for (t in 0:2) {
    X <- lib[[t + 1L]]
    risk <- d[[paste0("R", t)]] == 1L
    y <- if (type == "g") d[[paste0("A", t)]] else d[[paste0("R", t + 1L)]]
    fit <- safe_glm_fit(X[train & risk, , drop = FALSE], y[train & risk])
    if (is.null(fit)) { ok <- FALSE; next }
    use <- risk & stats::complete.cases(X)
    pred[use, t + 1L] <- expit(drop(X[use, , drop = FALSE] %*% fit$beta))
  }
  list(ok = ok, pred = pred)
}

fit_q_candidate <- function(d, mats, candidate, regime, train) {
  n <- nrow(d); pred <- matrix(NA_real_, n, 3L); ok <- TRUE
  for (t in 2:0) {
    X <- mats$q[[candidate + 1L]][[t + 1L]]
    retained <- d[[paste0("R", t + 1L)]] == 1L
    current <- d[[paste0("A", t)]] == regime
    y <- if (t == 2L) d$Y else pred[, t + 2L]
    fit <- safe_lm_fit(X[train & retained & current, , drop = FALSE],
                       y[train & retained & current])
    if (is.null(fit)) { ok <- FALSE; next }
    risk <- d[[paste0("R", t)]] == 1L & stats::complete.cases(X)
    pred[risk, t + 1L] <- drop(X[risk, , drop = FALSE] %*% fit$beta)
  }
  list(ok = ok, pred = pred)
}

binary_deviance <- function(d, pred, type, validation) {
  values <- numeric()
  for (t in 0:2) {
    risk <- validation & d[[paste0("R", t)]] == 1L
    y <- if (type == "g") d[[paste0("A", t)]] else d[[paste0("R", t + 1L)]]
    p <- pred[, t + 1L]
    keep <- risk & is.finite(y) & is.finite(p)
    if (!any(keep)) return(Inf)
    pp <- clip_prob(p[keep])
    values <- c(values, -2 * (y[keep] * log(pp) + (1 - y[keep]) * log(1 - pp)))
  }
  mean(values)
}

q_squared_loss <- function(d, fits, validation) {
  loss <- numeric()
  for (a in 0:1) {
    p <- fits[[a + 1L]]$pred
    for (t in 2:0) {
      keep <- validation & d[[paste0("R", t + 1L)]] == 1L &
        d[[paste0("A", t)]] == a
      target <- if (t == 2L) d$Y else p[, t + 2L]
      keep <- keep & is.finite(target) & is.finite(p[, t + 1L])
      if (!any(keep)) return(Inf)
      loss <- c(loss, mean((target[keep] - p[keep, t + 1L])^2))
    }
  }
  sum(loss)
}

history_weights <- function(d, idx, gp, cp, a) {
  ii <- which(idx); n <- length(ii); H <- matrix(0, n, 3L)
  prior <- rep(1, n); raw <- numeric(); ok <- TRUE
  for (t in 0:2) {
    A <- d[[paste0("A", t)]][ii]
    Rn <- d[[paste0("R", t + 1L)]][ii]
    pg <- gp[ii, t + 1L]
    pc <- cp[ii, t + 1L]
    gden <- if (a == 1L) pg else 1 - pg
    need_g <- prior > 0
    need_c <- need_g & !is.na(A) & A == a
    if (any(!is.finite(gden[need_g])) || any(!is.finite(pc[need_c]))) ok <- FALSE
    raw <- c(raw, gden[need_g], pc[need_c])
    h <- rep(0, n)
    keep <- need_c & !is.na(Rn) & Rn == 1L & is.finite(gden) & is.finite(pc)
    h[keep] <- prior[keep] /
      (clip_prob(gden[keep]) * clip_prob(pc[keep]))
    H[, t + 1L] <- h
    prior <- h
  }
  list(ok = ok, H = H, raw = raw, index = ii)
}

balance_sds <- function(d, train) {
  vars <- c("W1", "W2", "W3", "L0", "L1", "L2")
  out <- vapply(vars, function(v) stats::sd(d[[v]][train], na.rm = TRUE), numeric(1))
  out[!is.finite(out) | out <= 0] <- NA_real_
  out
}

weighted_mean_safe <- function(x, w) {
  keep <- is.finite(x) & is.finite(w) & w > 0
  if (!any(keep) || sum(w[keep]) <= 0) return(NA_real_)
  sum(x[keep] * w[keep]) / sum(w[keep])
}

balance_score <- function(d, idx, gp, cp, sds) {
  diffs <- numeric()
  for (a in 0:1) {
    hw <- history_weights(d, idx, gp, cp, a)
    if (!hw$ok) return(list(ok = FALSE, B = Inf, max = Inf, rms = Inf))
    ii <- hw$index
    for (t in 0:2) {
      prior <- if (t == 0L) rep(1, length(ii)) else hw$H[, t]
      A <- d[[paste0("A", t)]][ii]
      Rn <- d[[paste0("R", t + 1L)]][ii]
      pg <- gp[ii, t + 1L]
      pcv <- cp[ii, t + 1L]
      gden <- if (a == 1L) pg else 1 - pg
      wt_a <- rep(0, length(ii))
      ka <- prior > 0 & !is.na(A) & A == a & is.finite(gden)
      wt_a[ka] <- prior[ka] / clip_prob(gden[ka])
      wt_r <- rep(0, length(ii))
      kr <- ka & !is.na(Rn) & Rn == 1L & is.finite(pcv)
      wt_r[kr] <- wt_a[kr] / clip_prob(pcv[kr])
      vars <- c("W1", "W2", "W3", paste0("L", 0:t))
      for (v in vars) {
        sdv <- sds[[v]]
        if (!is.finite(sdv)) return(list(ok = FALSE, B = Inf, max = Inf, rms = Inf))
        x <- d[[v]][ii] / sdv
        mt <- weighted_mean_safe(x, prior)
        ma <- weighted_mean_safe(x, wt_a)
        mc <- weighted_mean_safe(x, wt_r)
        if (any(!is.finite(c(mt, ma, mc))))
          return(list(ok = FALSE, B = Inf, max = Inf, rms = Inf))
        ## Critique fix: people dropping after A_t remain in the pre-retention
        ## target through wt_a. Only retained people receive the inverse factor.
        diffs <- c(diffs, ma - mt, mc - ma)
      }
    }
  }
  mx <- max(abs(diffs)); rms <- sqrt(mean(diffs^2))
  list(ok = TRUE, B = 0.5 * mx + 0.5 * rms, max = mx, rms = rms)
}

weight_diagnostic <- function(d, idx, gp, cp) {
  out <- numeric(2)
  for (a in 0:1) {
    h <- history_weights(d, idx, gp, cp, a)
    if (!h$ok) return(Inf)
    w <- h$H[, 3L]; w <- w[is.finite(w) & w > 0]
    if (!length(w)) return(Inf)
    med <- stats::median(w); p99 <- unname(stats::quantile(w, 0.99))
    ess <- weighted_ess(w)
    if (med <= 0 || ess <= 0) return(Inf)
    out[a + 1L] <- log(p99 / med) + log(length(w) / ess)
  }
  max(out)
}

phi_values <- function(d, idx, gp, cp, qp, a) {
  h <- history_weights(d, idx, gp, cp, a)
  if (!h$ok) return(NULL)
  ii <- h$index; q <- qp[ii, , a + 1L, drop = FALSE]
  q <- matrix(q, ncol = 3L)
  if (any(!is.finite(q[, 1L]))) return(NULL)
  term <- function(w, x) { z <- numeric(length(w)); k <- w > 0; z[k] <- w[k] * x[k]; z }
  p <- q[, 1L] + term(h$H[, 1L], q[, 2L] - q[, 1L]) +
    term(h$H[, 2L], q[, 3L] - q[, 2L]) +
    term(h$H[, 3L], d$Y[ii] - q[, 3L])
  if (any(!is.finite(p))) return(NULL)
  list(phi = p, history = h)
}

drift_statistic <- function(d, train, validation, gp, cp, qp) {
  z <- numeric(2)
  for (a in 0:1) {
    tr <- phi_values(d, train, gp, cp, qp, a)
    va <- phi_values(d, validation, gp, cp, qp, a)
    if (is.null(tr) || is.null(va)) return(Inf)
    D <- va$phi - mean(tr$phi)
    den <- sqrt(mean(D^2))
    z[a + 1L] <- if (den == 0 && mean(D) == 0) 0 else abs(mean(D)) / den
  }
  max(z)
}

fractional_rank <- function(x) {
  out <- rep(1, length(x)); k <- is.finite(x)
  if (!any(k)) return(out)
  if (sum(k) == 1L) out[k] <- 0 else
    out[k] <- (rank(x[k], ties.method = "average") - 1) / (sum(k) - 1)
  out
}

inner_fold_metrics <- function(d, mats, train, validation) {
  gf <- lapply(0:4, function(g) fit_binary_candidate(d, mats, "g", g, train))
  cf <- lapply(0:2, function(cc) fit_binary_candidate(d, mats, "c", cc, train))
  qf <- lapply(0:3, function(q)
    lapply(0:1, function(a) fit_q_candidate(d, mats, q, a, train)))
  gl <- vapply(gf, function(x) if (x$ok) binary_deviance(d, x$pred, "g", validation) else Inf, numeric(1))
  cl <- vapply(cf, function(x) if (x$ok) binary_deviance(d, x$pred, "c", validation) else Inf, numeric(1))
  ql <- vapply(qf, function(x) if (all(vapply(x, `[[`, logical(1), "ok")))
    q_squared_loss(d, x, validation) else Inf, numeric(1))
  sds <- balance_sds(d, train)

  gcB <- gcW <- matrix(Inf, 5L, 3L)
  for (g in 0:4) for (cc in 0:2) if (gf[[g + 1L]]$ok && cf[[cc + 1L]]$ok) {
    b <- balance_score(d, validation, gf[[g + 1L]]$pred,
                       cf[[cc + 1L]]$pred, sds)
    gcB[g + 1L, cc + 1L] <- b$B
    gcW[g + 1L, cc + 1L] <- weight_diagnostic(
      d, validation, gf[[g + 1L]]$pred, cf[[cc + 1L]]$pred)
  }

  grid <- CONFIG_GRID
  grid$P <- grid$B <- grid$W <- grid$D <- Inf
  rg <- fractional_rank(gl); rc <- fractional_rank(cl); rq <- fractional_rank(ql)
  for (i in seq_len(nrow(grid))) {
    g <- grid$g[i]; cc <- grid$c[i]; q <- grid$q[i]
    grid$P[i] <- mean(c(rg[g + 1L], rc[cc + 1L], rq[q + 1L]))
    grid$B[i] <- gcB[g + 1L, cc + 1L]
    grid$W[i] <- gcW[g + 1L, cc + 1L]
    if (is.finite(grid$B[i]) && is.finite(grid$W[i]) && is.finite(ql[q + 1L])) {
      qp <- array(NA_real_, c(nrow(d), 3L, 2L))
      qp[, , 1L] <- qf[[q + 1L]][[1L]]$pred
      qp[, , 2L] <- qf[[q + 1L]][[2L]]$pred
      grid$D[i] <- drift_statistic(d, train, validation,
                                    gf[[g + 1L]]$pred, cf[[cc + 1L]]$pred, qp)
    }
  }
  grid$rP <- fractional_rank(grid$P)
  grid$rB <- fractional_rank(grid$B)
  grid$rW <- fractional_rank(grid$W)
  grid$rD <- fractional_rank(grid$D)
  grid$ok <- is.finite(grid$P) & is.finite(grid$B) &
    is.finite(grid$W) & is.finite(grid$D)
  list(grid = grid, gl = gl, cl = cl, ql = ql)
}

candidate_complexity <- function(mats) {
  list(
    g = vapply(mats$g, function(x) sum(vapply(x, ncol, integer(1))), integer(1)),
    c = vapply(mats$c, function(x) sum(vapply(x, ncol, integer(1))), integer(1)),
    q = vapply(mats$q, function(x) sum(vapply(x, ncol, integer(1))), integer(1))
  )
}

mean_complete <- function(x) if (all(is.finite(x))) mean(x) else Inf
pick_tied <- function(value, complexity, order, tolerance = 1e-8) {
  if (!any(is.finite(value))) return(NA_integer_)
  k <- which(value <= min(value, na.rm = TRUE) + tolerance)
  k <- k[complexity[k] == min(complexity[k])]
  k[which.min(order[k])]
}

nested_select <- function(d, mats, outer_train) {
  ids <- which(outer_train)
  shuffled <- sample(ids)
  fold <- rep(seq_len(INNER_FOLDS), length.out = length(ids))
  inner_id <- integer(nrow(d)); inner_id[shuffled] <- fold
  met <- lapply(seq_len(INNER_FOLDS), function(k)
    inner_fold_metrics(d, mats, outer_train & inner_id != k,
                       outer_train & inner_id == k))
  cx <- candidate_complexity(mats)
  gl <- vapply(0:4, function(g) mean_complete(vapply(met, function(x) x$gl[g + 1L], numeric(1))), numeric(1))
  cl <- vapply(0:2, function(cc) mean_complete(vapply(met, function(x) x$cl[cc + 1L], numeric(1))), numeric(1))
  ql <- vapply(0:3, function(q) mean_complete(vapply(met, function(x) x$ql[q + 1L], numeric(1))), numeric(1))
  pg <- pick_tied(gl, cx$g, 0:4) - 1L
  pc <- pick_tied(cl, cx$c, 0:2) - 1L
  pq <- pick_tied(ql, cx$q, 0:3) - 1L

  avg_grid <- met[[1L]]$grid
  numeric_cols <- c("P", "B", "W", "D", "rP", "rB", "rW", "rD")
  for (v in numeric_cols) avg_grid[[v]] <- rowMeans(do.call(cbind, lapply(met, function(x) x$grid[[v]])))
  avg_grid$ok <- Reduce(`&`, lapply(met, function(x) x$grid$ok))

  gc <- unique(avg_grid[, c("g", "c")])
  gc$value <- vapply(seq_len(nrow(gc)), function(i) {
    z <- avg_grid$B[avg_grid$g == gc$g[i] & avg_grid$c == gc$c[i]]
    if (all(is.finite(z))) z[1L] else Inf
  }, numeric(1))
  gc$pred <- gl[gc$g + 1L] + cl[gc$c + 1L]
  gc$complexity <- cx$g[gc$g + 1L] + cx$c[gc$c + 1L]
  if (any(is.finite(gc$value))) {
    k <- which(gc$value <= min(gc$value) + 1e-8)
    k <- k[gc$pred[k] <= min(gc$pred[k]) + 1e-8]
    k <- k[gc$complexity[k] == min(gc$complexity[k])][1L]
    balance <- c(g = gc$g[k], c = gc$c[k], q = pq)
  } else balance <- c(g = NA, c = NA, q = pq)
  predictive <- c(g = pg, c = pc, q = pq)

  choose_score <- function(weights) {
    score <- weights[["P"]] * avg_grid$rP + weights[["B"]] * avg_grid$rB +
      weights[["W"]] * avg_grid$rW + weights[["D"]] * avg_grid$rD
    score[!avg_grid$ok] <- Inf
    if (!any(is.finite(score))) return(c(g = NA, c = NA, q = NA))
    comp <- cx$g[avg_grid$g + 1L] + cx$c[avg_grid$c + 1L] + cx$q[avg_grid$q + 1L]
    k <- pick_tied(score, comp, avg_grid$config_id)
    c(g = avg_grid$g[k], c = avg_grid$c[k], q = avg_grid$q[k])
  }
  scores <- lapply(SCORE_WEIGHTS, choose_score)
  names(scores) <- names(SCORE_WEIGHTS)
  configs <- c(list(predictive = predictive, balance = balance), scores)

  diagnostics <- lapply(configs, function(cfg) {
    if (anyNA(cfg)) return(rep(NA_real_, 9L))
    r <- avg_grid[avg_grid$g == cfg[["g"]] & avg_grid$c == cfg[["c"]] &
                    avg_grid$q == cfg[["q"]], ][1L, ]
    c(P = r$P, B = r$B, W = r$W, D = r$D,
      rP = r$rP, rB = r$rB, rW = r$rW, rD = r$rD,
      score = mean(c(r$rP, r$rB, r$rW, r$rD)))
  })
  list(configs = configs, diagnostics = diagnostics)
}

outer_fit_all <- function(d, mats, train) {
  gf <- lapply(0:4, function(g) fit_binary_candidate(d, mats, "g", g, train))
  cf <- lapply(0:2, function(cc) fit_binary_candidate(d, mats, "c", cc, train))
  qf <- lapply(0:3, function(q)
    lapply(0:1, function(a) fit_q_candidate(d, mats, q, a, train)))
  list(g = gf, c = cf, q = qf)
}

new_result_row <- function(method, selector, family, config_id = NA_integer_) {
  data.frame(
    method = method, selector = selector, family = family, config_id = config_id,
    est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
    mean1 = NA_real_, mean0 = NA_real_, fixed_weight_band = FALSE,
    selected_g = NA_character_, selected_c = NA_character_, selected_q = NA_character_,
    component_P = NA_real_, component_B = NA_real_, component_W = NA_real_,
    component_D = NA_real_, rank_P = NA_real_, rank_B = NA_real_,
    rank_W = NA_real_, rank_D = NA_real_, selector_score = NA_real_,
    balance_max = NA_real_, balance_rms = NA_real_,
    ess0 = NA_real_, ess1 = NA_real_, adherers0 = NA_integer_, adherers1 = NA_integer_,
    w0_median = NA_real_, w0_p95 = NA_real_, w0_p99 = NA_real_,
    w1_median = NA_real_, w1_p95 = NA_real_, w1_p99 = NA_real_,
    probability_min = NA_real_, probability_p01 = NA_real_,
    probability_p99 = NA_real_, probability_max = NA_real_,
    extreme_probability_fraction = NA_real_, range_flag = FALSE,
    runtime_seconds = NA_real_, fail = NA_character_, stringsAsFactors = FALSE
  )
}

expected_specs <- function() {
  z <- list(
    c("predictive-ipw", "predictive", "ipw"),
    c("predictive-ipw-truncated", "predictive", "ipw"),
    c("balance-ipw", "balance", "ipw"),
    c("combined-ipw", "combined", "ipw"),
    c("predictive-ostep", "predictive", "ostep"),
    c("balance-ostep", "balance", "ostep"),
    c("combined-ostep", "combined", "ostep")
  )
  for (s in c("prediction_heavy", "no_P", "no_B", "no_W", "no_D")) {
    z[[length(z) + 1L]] <- c(paste0(s, "-ipw"), s, "ipw")
    z[[length(z) + 1L]] <- c(paste0(s, "-ostep"), s, "ostep")
  }
  out <- do.call(rbind, lapply(z, function(x) new_result_row(x[1], x[2], x[3])))
  for (i in seq_len(nrow(CONFIG_GRID))) out <- rbind(out,
    new_result_row(sprintf("oracle-config-%02d", i), "oracle-config", "ostep", i))
  out
}

blank_results <- function(why) {
  out <- expected_specs(); out$fail <- why; out
}

weight_summary <- function(w) {
  z <- w[is.finite(w) & w > 0]
  if (!length(z)) return(c(n = 0, ess = 0, median = NA, p95 = NA, p99 = NA, max = NA))
  c(n = length(z), ess = weighted_ess(z), median = stats::median(z),
    p95 = unname(stats::quantile(z, 0.95)),
    p99 = unname(stats::quantile(z, 0.99)), max = max(z))
}

ipw_from_history <- function(d, histories, truncate = FALSE) {
  n <- nrow(d); mu <- numeric(2); D <- matrix(0, n, 2L)
  used <- vector("list", 2L)
  for (a in 0:1) {
    h <- histories[[a + 1L]]; w <- h$H[, 3L]
    if (truncate) {
      k <- is.finite(w) & w > 0
      if (!any(k)) return(NULL)
      cut <- stats::quantile(w[k], c(0.01, 0.99), names = FALSE)
      w[k] <- pmin(pmax(w[k], cut[1L]), cut[2L])
    }
    y <- d$Y[h$index]
    k <- is.finite(w) & w > 0 & is.finite(y)
    if (!any(k) || sum(w[k]) <= 0) return(NULL)
    mu[a + 1L] <- sum(w[k] * y[k]) / sum(w[k])
    residual <- numeric(length(w)); residual[k] <- y[k] - mu[a + 1L]
    D[, a + 1L] <- w * residual / mean(w)
    used[[a + 1L]] <- w
  }
  est <- mu[2L] - mu[1L]
  se <- stats::sd(D[, 2L] - D[, 1L]) / sqrt(n)
  list(est = est, se = se, mean1 = mu[2L], mean0 = mu[1L], weights = used)
}

ostep_from_history <- function(d, idx, gp, cp, qp) {
  p0 <- phi_values(d, idx, gp, cp, qp, 0L)
  p1 <- phi_values(d, idx, gp, cp, qp, 1L)
  if (is.null(p0) || is.null(p1)) return(NULL)
  mu0 <- mean(p0$phi); mu1 <- mean(p1$phi)
  E <- (p1$phi - mu1) - (p0$phi - mu0)
  list(est = mu1 - mu0, se = stats::sd(E) / sqrt(length(E)),
       mean1 = mu1, mean0 = mu0,
       weights = list(p0$history$H[, 3L], p1$history$H[, 3L]))
}

method_result <- function(d, bundle, method, selector, family,
                          config_id = NA_integer_, truncate = FALSE,
                          require_q = family == "ostep") {
  out <- new_result_row(method, selector, family, config_id)
  out$selected_g <- bundle$selected_g
  out$selected_c <- bundle$selected_c
  out$selected_q <- bundle$selected_q
  if (!is.null(bundle$diagnostic)) {
    x <- bundle$diagnostic
    out$component_P <- x[["P"]]; out$component_B <- x[["B"]]
    out$component_W <- x[["W"]]; out$component_D <- x[["D"]]
    out$rank_P <- x[["rP"]]; out$rank_B <- x[["rB"]]
    out$rank_W <- x[["rW"]]; out$rank_D <- x[["rD"]]
    out$selector_score <- x[["score"]]
  }
  if (!bundle$ok || (require_q && is.null(bundle$qp))) {
    out$fail <- "outer-fit-failed"; return(out)
  }
  idx <- rep(TRUE, nrow(d))
  histories <- lapply(0:1, function(a) history_weights(d, idx, bundle$gp, bundle$cp, a))
  if (any(!vapply(histories, `[[`, logical(1), "ok"))) {
    out$fail <- "missing-probability"; return(out)
  }
  raw <- unlist(lapply(histories, `[[`, "raw"), use.names = FALSE)
  out$probability_min <- min(raw, na.rm = TRUE)
  out$probability_p01 <- unname(stats::quantile(raw, 0.01, na.rm = TRUE))
  out$probability_p99 <- unname(stats::quantile(raw, 0.99, na.rm = TRUE))
  out$probability_max <- max(raw, na.rm = TRUE)
  out$extreme_probability_fraction <- mean(raw < PROB_FLOOR | raw > 1 - PROB_FLOOR)
  if (!is.finite(out$extreme_probability_fraction) ||
      out$extreme_probability_fraction > EXTREME_PROB_FRACTION) {
    out$fail <- "probability-tail"; return(out)
  }

  ws <- lapply(histories, function(h) weight_summary(h$H[, 3L]))
  out$adherers0 <- as.integer(ws[[1L]][["n"]]); out$adherers1 <- as.integer(ws[[2L]][["n"]])
  out$ess0 <- ws[[1L]][["ess"]]; out$ess1 <- ws[[2L]][["ess"]]
  out$w0_median <- ws[[1L]][["median"]]; out$w0_p95 <- ws[[1L]][["p95"]]
  out$w0_p99 <- ws[[1L]][["p99"]]; out$w1_median <- ws[[2L]][["median"]]
  out$w1_p95 <- ws[[2L]][["p95"]]; out$w1_p99 <- ws[[2L]][["p99"]]
  if (any(c(out$adherers0, out$adherers1) == 0L)) {
    out$fail <- "no-adherers"; return(out)
  }
  if (min(out$ess0, out$ess1) < MIN_ESS) {
    out$fail <- "low-ess"; return(out)
  }
  if (max(ws[[1L]][["max"]], ws[[2L]][["max"]]) > MAX_WEIGHT) {
    out$fail <- "weight-overflow"; return(out)
  }

  b <- balance_score(d, idx, bundle$gp, bundle$cp, balance_sds(d, idx))
  if (b$ok) { out$balance_max <- b$max; out$balance_rms <- b$rms }
  est <- if (family == "ipw") ipw_from_history(d, histories, truncate) else
    ostep_from_history(d, idx, bundle$gp, bundle$cp, bundle$qp)
  if (is.null(est) || any(!is.finite(c(est$est, est$se)))) {
    out$fail <- "nonfinite-estimate"; return(out)
  }
  out$est <- est$est; out$se <- est$se
  out$mean1 <- est$mean1; out$mean0 <- est$mean0
  out$lo <- out$est - Z975 * out$se; out$hi <- out$est + Z975 * out$se
  out$fixed_weight_band <- family == "ipw"
  if (family == "ostep") {
    yr <- range(d$Y, na.rm = TRUE)
    out$range_flag <- out$mean0 < yr[1L] || out$mean0 > yr[2L] ||
      out$mean1 < yr[1L] || out$mean1 > yr[2L]
  }
  out
}

run_estimators <- function(d) {
  n <- nrow(d); mats <- cache_matrices(d)
  shuffled <- sample(seq_len(n)); outer_id <- integer(n)
  outer_id[shuffled] <- rep(seq_len(OUTER_FOLDS), length.out = n)
  selections <- vector("list", OUTER_FOLDS)
  fits <- vector("list", OUTER_FOLDS)
  for (k in seq_len(OUTER_FOLDS)) {
    train <- outer_id != k
    selections[[k]] <- nested_select(d, mats, train)
    fits[[k]] <- outer_fit_all(d, mats, train)
  }

  gpred <- array(NA_real_, c(n, 3L, 5L))
  cpred <- array(NA_real_, c(n, 3L, 3L))
  qpred <- array(NA_real_, c(n, 3L, 2L, 4L))
  for (k in seq_len(OUTER_FOLDS)) {
    test <- outer_id == k
    for (g in 0:4) gpred[test, , g + 1L] <- fits[[k]]$g[[g + 1L]]$pred[test, ]
    for (cc in 0:2) cpred[test, , cc + 1L] <- fits[[k]]$c[[cc + 1L]]$pred[test, ]
    for (q in 0:3) for (a in 0:1)
      qpred[test, , a + 1L, q + 1L] <- fits[[k]]$q[[q + 1L]][[a + 1L]]$pred[test, ]
  }

  assemble <- function(configs, diagnostic = NULL) {
    gp <- cp <- matrix(NA_real_, n, 3L)
    qp <- array(NA_real_, c(n, 3L, 2L)); ok <- TRUE
    sg <- sc <- sq <- character(OUTER_FOLDS)
    for (k in seq_len(OUTER_FOLDS)) {
      cfg <- configs[[k]]; test <- outer_id == k
      if (anyNA(cfg)) { ok <- FALSE; next }
      g <- cfg[["g"]]; cc <- cfg[["c"]]; q <- cfg[["q"]]
      gp[test, ] <- gpred[test, , g + 1L]
      cp[test, ] <- cpred[test, , cc + 1L]
      qp[test, , ] <- qpred[test, , , q + 1L]
      ok <- ok && fits[[k]]$g[[g + 1L]]$ok && fits[[k]]$c[[cc + 1L]]$ok &&
        all(vapply(fits[[k]]$q[[q + 1L]], `[[`, logical(1), "ok"))
      sg[k] <- paste0("G", g); sc[k] <- paste0("C", cc); sq[k] <- paste0("QL", q)
    }
    list(gp = gp, cp = cp, qp = qp, ok = ok,
         selected_g = paste(sg, collapse = "|"),
         selected_c = paste(sc, collapse = "|"),
         selected_q = paste(sq, collapse = "|"), diagnostic = diagnostic)
  }

  selector_keys <- c("predictive", "balance", "combined", "prediction_heavy",
                     "no_P", "no_B", "no_W", "no_D")
  bundles <- list()
  for (key in selector_keys) {
    cfg <- lapply(selections, function(x) x$configs[[key]])
    dg <- lapply(selections, function(x) x$diagnostics[[key]])
    diagnostic <- if (all(vapply(dg, function(x) all(is.finite(x)), logical(1))))
      colMeans(do.call(rbind, dg)) else NULL
    bundles[[key]] <- assemble(cfg, diagnostic)
  }

  rows <- list()
  add <- function(x) rows[[length(rows) + 1L]] <<- x
  add(method_result(d, bundles$predictive, "predictive-ipw", "predictive", "ipw",
                    require_q = FALSE))
  add(method_result(d, bundles$predictive, "predictive-ipw-truncated", "predictive", "ipw",
                    truncate = TRUE, require_q = FALSE))
  add(method_result(d, bundles$balance, "balance-ipw", "balance", "ipw",
                    require_q = FALSE))
  add(method_result(d, bundles$combined, "combined-ipw", "combined", "ipw"))
  add(method_result(d, bundles$predictive, "predictive-ostep", "predictive", "ostep"))
  add(method_result(d, bundles$balance, "balance-ostep", "balance", "ostep"))
  add(method_result(d, bundles$combined, "combined-ostep", "combined", "ostep"))
  for (key in c("prediction_heavy", "no_P", "no_B", "no_W", "no_D")) {
    add(method_result(d, bundles[[key]], paste0(key, "-ipw"), key, "ipw"))
    add(method_result(d, bundles[[key]], paste0(key, "-ostep"), key, "ostep"))
  }

  for (i in seq_len(nrow(CONFIG_GRID))) {
    cfg <- CONFIG_GRID[i, ]
    fixed <- replicate(OUTER_FOLDS, c(g = cfg$g, c = cfg$c, q = cfg$q), simplify = FALSE)
    b <- assemble(fixed)
    add(method_result(d, b, sprintf("oracle-config-%02d", i), "oracle-config",
                      "ostep", i))
  }
  do.call(rbind, rows)
}
