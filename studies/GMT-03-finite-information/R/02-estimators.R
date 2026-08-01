## Study GMT-03: truth accumulation, exact-regime estimators, and the
## stabilized clone-censor-weighted marginal structural model.

fit_binomial_checked <- function(X, y, weights = NULL, guard = TRUE) {
  if (is.null(weights)) weights <- rep(1, length(y))
  fit <- try(suppressWarnings(stats::glm.fit(
    x = X, y = y, weights = weights, family = stats::binomial(),
    control = stats::glm.control(maxit = 60L, epsilon = 1e-9))), silent = TRUE)
  fail <- NULL
  if (inherits(fit, "try-error")) fail <- "treatment-fit"
  if (is.null(fail) && (!isTRUE(fit$converged) || fit$rank < ncol(X)))
    fail <- "treatment-rank-or-convergence"
  if (is.null(fail) && any(!is.finite(fit$coefficients)))
    fail <- "treatment-nonfinite"
  p <- if (is.null(fail)) as.numeric(fit$fitted.values) else rep(NA_real_, length(y))
  if (is.null(fail) && guard && any(p < PROBABILITY_FLOOR | p > 1 - PROBABILITY_FLOOR))
    fail <- "treatment-probability-bound"
  list(fit = fit, coef = if (is.null(fail)) fit$coefficients else rep(NA_real_, ncol(X)),
       p = p, fail = fail,
       info = if (is.null(fail)) crossprod(X, X * (weights * p * (1 - p))) else NULL)
}

rows_by_id <- function(x, id, n) {
  out <- matrix(0, n, ncol(x))
  z <- rowsum(x, id, reorder = FALSE)
  out[as.integer(rownames(z)), ] <- z
  out
}

fit_assignment_models <- function(dat) {
  x0 <- cbind(1, dat$X, dat$G, dat$L0)
  y0 <- dat$A[, 1L]
  b0 <- fit_binomial_checked(x0, y0)
  mask <- dat$at_risk[, -1L, drop = FALSE]
  ix <- which(mask, arr.ind = TRUE)
  id <- ix[, 1L]
  tt <- ix[, 2L] + 1L
  xp <- cbind(1, dat$A[cbind(id, tt - 1L)], dat$X[id], dat$G[id],
              dat$L[cbind(id, tt)])
  yp <- dat$A[cbind(id, tt)]
  bp <- fit_binomial_checked(xp, yp)
  fail <- b0$fail %||% bp$fail
  p <- matrix(NA_real_, dat$n, N_MONTHS)
  if (is.null(fail)) {
    p[, 1L] <- b0$p
    p[cbind(id, tt)] <- bp$p
  }
  score0 <- if (is.null(fail)) x0 * (y0 - b0$p) else matrix(NA_real_, dat$n, 4L)
  scorep <- if (is.null(fail)) rows_by_id(xp * (yp - bp$p), id, dat$n) else
    matrix(NA_real_, dat$n, 5L)
  list(fail = fail, p = p, x0 = x0, y0 = y0, baseline = b0,
       post = list(X = xp, y = yp, id = id, month = tt, fit = bp),
       score = cbind(score0, scorep),
       info = if (is.null(fail)) {
         b <- matrix(0, 9L, 9L)
         b[1:4, 1:4] <- b0$info
         b[5:9, 5:9] <- bp$info
         b
       } else NULL)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

make_weight_paths <- function(dat, p) {
  arms <- vector("list", 2L)
  for (gg in 0:1) {
    compat <- matrix(FALSE, dat$n, N_MONTHS)
    logpi <- matrix(0, dat$n, N_MONTHS)
    current_c <- rep(TRUE, dat$n)
    current_l <- numeric(dat$n)
    for (tt in seq_len(N_MONTHS)) {
      obs <- dat$at_risk[, tt]
      pg <- if (gg == 1L) p[, tt] else 1 - p[, tt]
      current_l[obs] <- current_l[obs] + log(pg[obs])
      current_c[obs] <- current_c[obs] & dat$A[obs, tt] == gg
      compat[, tt] <- current_c
      logpi[, tt] <- current_l
    }
    w <- exp(-logpi) * compat
    arms[[gg + 1L]] <- list(compat = compat, logpi = logpi, w = w)
  }
  arms
}

strategy_score_sums <- function(dat, p, gg, h) {
  x0 <- cbind(1, dat$X, dat$G, dat$L0)
  s0 <- x0 * (gg - p[, 1L])
  s1 <- matrix(0, dat$n, 5L)
  if (h > 1L) {
    for (tt in 2:h) {
      id <- which(dat$at_risk[, tt])
      x <- cbind(1, dat$A[id, tt - 1L], dat$X[id], dat$G[id], dat$L[id, tt])
      s1[id, ] <- s1[id, , drop = FALSE] + x * (gg - p[id, tt])
    }
  }
  cbind(s0, s1)
}

weighted_ess <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w) || sum(w^2) == 0) return(0)
  sum(w)^2 / sum(w^2)
}

cell_information <- function(paths, dat, endpoint, subgroup, h) {
  group <- switch(subgroup, all = rep(TRUE, dat$n), G0 = dat$G == 0L,
                  G1 = dat$G == 1L)
  z <- dat$event_type == if (endpoint == "Y") 1L else 2L
  z <- z & !is.na(dat$event_month) & dat$event_month <= h
  e <- ne <- numeric(2L)
  minimum <- numeric(2L)
  for (gg in 0:1) {
    q <- paths[[gg + 1L]]$w[, h] * group
    e[gg + 1L] <- weighted_ess(q[z])
    ne[gg + 1L] <- weighted_ess(q[!z])
    monthly <- vapply(seq_len(h), function(tt) {
      at <- group & dat$at_risk[, tt]
      weighted_ess(paths[[gg + 1L]]$w[at, tt])
    }, numeric(1))
    minimum[gg + 1L] <- min(monthly)
  }
  list(event_ess = min(e), nonevent_ess = min(ne),
       all_cells = c(e, ne), min_riskset_ess = min(minimum),
       warning = min(minimum) < RISKSET_ESS_FLAG || min(e) < EVENT_ESS_FLAG)
}

path_diagnostics <- function(paths, dat, method, fail = NULL) {
  rows <- vector("list", 2L * 3L * N_MONTHS)
  k <- 0L
  for (subgroup in c("all", "G0", "G1")) {
    group <- switch(subgroup, all = rep(TRUE, dat$n), G0 = dat$G == 0L,
                    G1 = dat$G == 1L)
    denom_n <- sum(group)
    for (gg in 0:1) for (tt in seq_len(N_MONTHS)) {
      k <- k + 1L
      at <- group & dat$at_risk[, tt] & paths[[gg + 1L]]$compat[, tt]
      w <- paths[[gg + 1L]]$w[at, tt]
      sw <- sum(w)
      sw2 <- sum(w^2)
      nw <- if (sw > 0) w / sw else numeric()
      pos <- w[w > 0 & is.finite(w)]
      ratio <- if (length(pos)) {
        q <- stats::quantile(pos, c(0.50, 0.99), names = FALSE)
        if (q[1L] > 0) q[2L] / q[1L] else Inf
      } else NA_real_
      rows[[k]] <- data.frame(
        row_type = "diagnostic", method = method, endpoint = NA_character_,
        subgroup = subgroup, horizon = NA_integer_, month = tt, strategy = gg,
        fail = fail, n_compatible = sum(at),
        cum_y = sum(group & paths[[gg + 1L]]$compat[, tt] &
                      dat$event_type == 1L & !is.na(dat$event_month) &
                      dat$event_month <= tt),
        cum_d = sum(group & paths[[gg + 1L]]$compat[, tt] &
                      dat$event_type == 2L & !is.na(dat$event_month) &
                      dat$event_month <= tt),
        sum_w = sw, sum_w2 = sw2,
        kish_ess = if (sw2 > 0) sw^2 / sw2 else 0,
        ess_fraction = if (denom_n > 0 && sw2 > 0) sw^2 / sw2 / denom_n else 0,
        max_normalized_weight = if (length(nw)) max(nw) else NA_real_,
        p99_p50 = ratio, stringsAsFactors = FALSE)
    }
  }
  complete_result(do.call(rbind, rows))
}

blank_estimates <- function(methods = METHODS, why = "no-estimate") {
  g <- merge(data.frame(method = methods, stringsAsFactors = FALSE), endpoint_grid(), by = NULL)
  g$row_type <- "estimate"
  g$fail <- why
  complete_result(g)
}

hajek_fixed <- function(q0, q1, z, mask) {
  q0 <- q0 * mask
  q1 <- q1 * mask
  if (any(!is.finite(c(q0, q1))) || max(c(q0, q1)) > WEIGHT_LIMIT)
    return(list(fail = "weight-overflow"))
  if (sum(q0) <= 0 || sum(q1) <= 0)
    return(list(fail = "zero-arm-denominator"))
  m0 <- sum(q0 * z) / sum(q0)
  m1 <- sum(q1 * z) / sum(q1)
  phi <- q1 * (z - m1) / mean(q1) - q0 * (z - m0) / mean(q0)
  n <- length(z)
  se <- sqrt(stats::var(phi) / n * n / max(1, n - 2L))
  if (!is.finite(se)) return(list(fail = "nonfinite-estimate-or-se"))
  list(fail = NULL, est = m1 - m0, se = se, mu0 = m0, mu1 = m1,
       q0 = q0, q1 = q1)
}

stacked_hajek <- function(base, fit, dat, z, mask, h, return_bread = FALSE) {
  if (!is.null(base$fail)) return(base)
  n <- dat$n
  s0 <- strategy_score_sums(dat, fit$p, 0L, h)
  s1 <- strategy_score_sums(dat, fit$p, 1L, h)
  u0 <- base$q0 * (z - base$mu0)
  u1 <- base$q1 * (z - base$mu1)
  U <- cbind(fit$score, u0, u1)
  B <- matrix(0, 11L, 11L)
  B[1:9, 1:9] <- fit$info / n
  B[10L, 1:9] <- colMeans(u0 * s0)
  B[11L, 1:9] <- colMeans(u1 * s1)
  B[10L, 10L] <- mean(base$q0)
  B[11L, 11L] <- mean(base$q1)
  if (!is.finite(rcond(B)) || rcond(B) < 1e-12)
    return(list(fail = "singular-bread"))
  U <- sweep(U, 2L, colMeans(U), "-")
  M <- crossprod(U) / n
  ib <- solve(B)
  V <- ib %*% M %*% t(ib) / n * n / max(1, n - ncol(B))
  ev <- eigen((V + t(V)) / 2, symmetric = TRUE, only.values = TRUE)$values
  if (min(ev) < -1e-10) return(list(fail = "non-psd-covariance"))
  cc <- numeric(11L)
  cc[10L] <- -1
  cc[11L] <- 1
  vv <- drop(t(cc) %*% V %*% cc)
  if (!is.finite(vv) || vv < 0) return(list(fail = "negative-or-nonfinite-variance"))
  ans <- list(fail = NULL, est = base$est, se = sqrt(vv), V = V)
  if (return_bread) ans$bread <- B
  ans
}

make_estimate_row <- function(method, spec, estimate, crit = NORMAL_CRIT,
                              info = NULL, lo = NULL, hi = NULL,
                              boot_success = NA_real_) {
  if (!is.null(estimate$fail))
    return(complete_result(data.frame(row_type = "estimate", method = method,
      endpoint = spec$endpoint, subgroup = spec$subgroup, horizon = spec$horizon,
      fail = estimate$fail, stringsAsFactors = FALSE)))
  if (is.null(lo)) lo <- estimate$est - crit * estimate$se
  if (is.null(hi)) hi <- estimate$est + crit * estimate$se
  d <- data.frame(row_type = "estimate", method = method,
                  endpoint = spec$endpoint, subgroup = spec$subgroup,
                  horizon = spec$horizon, est = estimate$est, se = estimate$se,
                  lo = lo, hi = hi, fail = NA_character_,
                  boot_success = boot_success, stringsAsFactors = FALSE)
  if (!is.null(info)) {
    d$event_ess <- info$event_ess
    d$nonevent_ess <- info$nonevent_ess
    d$min_riskset_ess <- info$min_riskset_ess
    d$warning <- info$warning
  }
  complete_result(d)
}

estimate_exact <- function(dat) {
  specs <- endpoint_grid()
  fit <- fit_assignment_models(dat)
  fitted_paths <- if (is.null(fit$fail)) make_weight_paths(dat, fit$p) else NULL
  oracle_paths <- make_weight_paths(dat, dat$p_true)
  rows <- list()

  for (i in seq_len(nrow(specs))) {
    s <- specs[i, , drop = FALSE]
    group <- switch(s$subgroup, all = rep(TRUE, dat$n), G0 = dat$G == 0L,
                    G1 = dat$G == 1L)
    z <- dat$event_type == if (s$endpoint == "Y") 1L else 2L
    z <- z & !is.na(dat$event_month) & dat$event_month <= s$horizon

    if (is.null(fit$fail)) {
      info <- cell_information(fitted_paths, dat, s$endpoint, s$subgroup, s$horizon)
      fixed <- hajek_fixed(fitted_paths[[1L]]$w[, s$horizon],
                           fitted_paths[[2L]]$w[, s$horizon], z, group)
      stacked <- stacked_hajek(fixed, fit, dat, z, group, s$horizon)
      rows[[length(rows) + 1L]] <- make_estimate_row("exact_fixed", s, fixed, info = info)
      rows[[length(rows) + 1L]] <- make_estimate_row("exact_stacked", s, stacked, info = info)
      tt <- stacked
      if (is.null(tt$fail)) {
        if (any(info$all_cells <= 1)) {
          tt <- list(fail = "insufficient-cell")
        } else {
          df <- floor(min(info$all_cells)) - 1L
          tt$df <- df
        }
      }
      rows[[length(rows) + 1L]] <- make_estimate_row(
        "exact_t", s, tt,
        crit = if (is.null(tt$fail)) stats::qt(0.975, tt$df) else NORMAL_CRIT,
        info = info)
    } else {
      for (m in c("exact_fixed", "exact_stacked", "exact_t"))
        rows[[length(rows) + 1L]] <- make_estimate_row(m, s, list(fail = fit$fail))
    }

    oinfo <- cell_information(oracle_paths, dat, s$endpoint, s$subgroup, s$horizon)
    oracle <- hajek_fixed(oracle_paths[[1L]]$w[, s$horizon],
                          oracle_paths[[2L]]$w[, s$horizon], z, group)
    rows[[length(rows) + 1L]] <- make_estimate_row("oracle", s, oracle, info = oinfo)
  }
  list(rows = do.call(rbind, rows), fit = fit, paths = fitted_paths,
       oracle_paths = oracle_paths,
       diagnostics = if (is.null(fit$fail)) path_diagnostics(fitted_paths, dat, "exact_fixed") else
         complete_result(transform(expand.grid(subgroup = c("all", "G0", "G1"),
           strategy = 0:1, month = seq_len(N_MONTHS), stringsAsFactors = FALSE),
           row_type = "diagnostic", method = "exact_fixed", fail = fit$fail)))
}

fit_numerator_models <- function(dat, den) {
  x0 <- matrix(1, dat$n, 1L)
  b0 <- fit_binomial_checked(x0, dat$A[, 1L])
  id <- den$post$id
  tt <- den$post$month
  xp <- cbind(1, (tt - 1) / (N_MONTHS - 1), dat$A[cbind(id, tt - 1L)])
  bp <- fit_binomial_checked(xp, den$post$y)
  fail <- b0$fail %||% bp$fail
  p <- matrix(NA_real_, dat$n, N_MONTHS)
  if (is.null(fail)) {
    p[, 1L] <- b0$p
    p[cbind(id, tt)] <- bp$p
  }
  score0 <- if (is.null(fail)) x0 * (dat$A[, 1L] - b0$p) else matrix(NA_real_, dat$n, 1L)
  scorep <- if (is.null(fail)) rows_by_id(xp * (den$post$y - bp$p), id, dat$n) else
    matrix(NA_real_, dat$n, 3L)
  info <- if (is.null(fail)) {
    z <- matrix(0, 4L, 4L)
    z[1L, 1L] <- b0$info
    z[2:4, 2:4] <- bp$info
    z
  } else NULL
  list(fail = fail, p = p, score = cbind(score0, scorep), info = info)
}

build_stabilized_long <- function(dat, den, num, derivatives = TRUE) {
  if (!is.null(den$fail) || !is.null(num$fail))
    return(list(fail = den$fail %||% num$fail))
  pieces <- list()
  dpieces <- list()
  paths <- vector("list", 2L)

  for (gg in 0:1) {
    compat <- matrix(FALSE, dat$n, N_MONTHS)
    wpath <- matrix(0, dat$n, N_MONTHS)
    current_c <- rep(TRUE, dat$n)
    logden <- lognum <- numeric(dat$n)
    sd0 <- den$x0 * (gg - den$p[, 1L])
    sd1 <- matrix(0, dat$n, 5L)
    sn0 <- matrix(gg - num$p[, 1L], dat$n, 1L)
    sn1 <- matrix(0, dat$n, 3L)
    current_w <- numeric(dat$n)

    for (tt in seq_len(N_MONTHS)) {
      obs <- dat$at_risk[, tt]
      pd <- if (gg == 1L) den$p[, tt] else 1 - den$p[, tt]
      pn <- if (gg == 1L) num$p[, tt] else 1 - num$p[, tt]
      logden[obs] <- logden[obs] + log(pd[obs])
      lognum[obs] <- lognum[obs] + log(pn[obs])
      current_c[obs] <- current_c[obs] & dat$A[obs, tt] == gg
      if (tt > 1L) {
        id <- which(obs)
        xd <- cbind(1, dat$A[id, tt - 1L], dat$X[id], dat$G[id], dat$L[id, tt])
        xn <- cbind(1, (tt - 1) / (N_MONTHS - 1), dat$A[id, tt - 1L])
        sd1[id, ] <- sd1[id, , drop = FALSE] + xd * (gg - den$p[id, tt])
        sn1[id, ] <- sn1[id, , drop = FALSE] + xn * (gg - num$p[id, tt])
      }
      idx <- which(obs & current_c)
      if (!length(idx)) return(list(fail = "zero-clone-risk-set"))
      raw <- exp(lognum[idx] - logden[idx])
      if (any(!is.finite(raw))) return(list(fail = "nonfinite-stabilized-weight"))
      norm <- mean(raw)
      current_w[obs & !current_c] <- 0
      current_w[idx] <- raw / norm
      compat[, tt] <- current_c
      wpath[, tt] <- current_w
      cat <- ifelse(dat$event_month[idx] == tt, dat$event_type[idx], 0L)
      pieces[[length(pieces) + 1L]] <- list(
        id = idx, cell = gg * N_MONTHS + tt, strategy = gg,
        category = cat, weight = current_w[idx],
        Z = cbind(dat$X[idx], dat$G[idx], dat$L0[idx], gg * dat$G[idx]))
      if (derivatives) {
        draw <- cbind(-sd0[idx, , drop = FALSE], -sd1[idx, , drop = FALSE],
                      sn0[idx, , drop = FALSE], sn1[idx, , drop = FALSE])
        center <- colSums(draw * raw) / sum(raw)
        dpieces[[length(dpieces) + 1L]] <- sweep(draw, 2L, center, "-")
      }
    }
    paths[[gg + 1L]] <- list(compat = compat, w = wpath)
  }

  long <- list(
    id = unlist(lapply(pieces, `[[`, "id"), use.names = FALSE),
    cell = unlist(lapply(pieces, `[[`, "cell"), use.names = FALSE),
    strategy = unlist(lapply(pieces, `[[`, "strategy"), use.names = FALSE),
    category = unlist(lapply(pieces, `[[`, "category"), use.names = FALSE),
    weight = unlist(lapply(pieces, `[[`, "weight"), use.names = FALSE),
    Z = do.call(rbind, lapply(pieces, `[[`, "Z")),
    dlog = if (derivatives) do.call(rbind, dpieces) else NULL)
  list(fail = NULL, long = long, paths = paths,
       nuisance_score = cbind(den$score, num$score),
       nuisance_info = {
         b <- matrix(0, 13L, 13L)
         b[1:9, 1:9] <- den$info
         b[10:13, 10:13] <- num$info
         b
       })
}

outcome_index <- function() {
  C <- 2L * N_MONTHS
  list(C = C, y_cell = seq_len(C), y_slope = C + seq_len(4L),
       d_cell = C + 4L + seq_len(C),
       d_slope = 2L * C + 4L + seq_len(4L),
       p = 2L * (C + 4L))
}

multinom_components <- function(theta, long, need_info = TRUE) {
  ix <- outcome_index()
  ay <- theta[ix$y_cell]
  by <- theta[ix$y_slope]
  ad <- theta[ix$d_cell]
  bd <- theta[ix$d_slope]
  eta_y <- ay[long$cell] + drop(long$Z %*% by)
  eta_d <- ad[long$cell] + drop(long$Z %*% bd)
  mm <- pmax(0, eta_y, eta_d)
  ey <- exp(eta_y - mm)
  ed <- exp(eta_d - mm)
  en <- exp(-mm)
  den <- ey + ed + en
  py <- ey / den
  pd <- ed / den
  iy <- as.numeric(long$category == 1L)
  id <- as.numeric(long$category == 2L)
  ry <- long$weight * (iy - py)
  rd <- long$weight * (id - pd)
  cell_sum <- function(v) {
    ans <- numeric(ix$C)
    z <- rowsum(matrix(v, ncol = 1L), long$cell, reorder = FALSE)
    ans[as.integer(rownames(z))] <- z[, 1L]
    ans
  }
  cell_z <- function(v) {
    ans <- matrix(0, ix$C, 4L)
    z <- rowsum(long$Z * v, long$cell, reorder = FALSE)
    ans[as.integer(rownames(z)), ] <- z
    ans
  }
  score <- numeric(ix$p)
  score[ix$y_cell] <- cell_sum(ry)
  score[ix$y_slope] <- colSums(long$Z * ry)
  score[ix$d_cell] <- cell_sum(rd)
  score[ix$d_slope] <- colSums(long$Z * rd)
  ll <- sum(long$weight * (iy * eta_y + id * eta_d -
                            (mm + log(en + ey + ed))))
  if (!need_info) return(list(score = score, loglik = ll, py = py, pd = pd))

  wyy <- long$weight * py * (1 - py)
  wdd <- long$weight * pd * (1 - pd)
  wyd <- -long$weight * py * pd
  info <- matrix(0, ix$p, ix$p)
  info[cbind(ix$y_cell, ix$y_cell)] <- cell_sum(wyy)
  info[cbind(ix$d_cell, ix$d_cell)] <- cell_sum(wdd)
  info[cbind(ix$y_cell, ix$d_cell)] <- cell_sum(wyd)
  info[cbind(ix$d_cell, ix$y_cell)] <- cell_sum(wyd)
  zyy <- cell_z(wyy)
  zdd <- cell_z(wdd)
  zyd <- cell_z(wyd)
  info[ix$y_cell, ix$y_slope] <- zyy
  info[ix$y_slope, ix$y_cell] <- t(zyy)
  info[ix$d_cell, ix$d_slope] <- zdd
  info[ix$d_slope, ix$d_cell] <- t(zdd)
  info[ix$y_cell, ix$d_slope] <- zyd
  info[ix$d_slope, ix$y_cell] <- t(zyd)
  info[ix$d_cell, ix$y_slope] <- zyd
  info[ix$y_slope, ix$d_cell] <- t(zyd)
  info[ix$y_slope, ix$y_slope] <- crossprod(long$Z, long$Z * wyy)
  info[ix$d_slope, ix$d_slope] <- crossprod(long$Z, long$Z * wdd)
  info[ix$y_slope, ix$d_slope] <- crossprod(long$Z, long$Z * wyd)
  info[ix$d_slope, ix$y_slope] <- t(info[ix$y_slope, ix$d_slope])
  list(score = score, info = info, loglik = ll, py = py, pd = pd,
       ry = ry, rd = rd)
}

fit_weighted_multinomial <- function(long) {
  ix <- outcome_index()
  counts <- matrix(0, ix$C, 3L)
  z <- rowsum(cbind(long$weight * (long$category == 1L),
                    long$weight * (long$category == 2L),
                    long$weight * (long$category == 0L)),
              long$cell, reorder = FALSE)
  counts[as.integer(rownames(z)), ] <- z
  ## A zero category in an arm-month cell sends a saturated intercept to
  ## infinity. The protocol classifies that condition as separation.
  if (any(counts <= 0)) return(list(fail = "outcome-separation"))
  theta <- numeric(ix$p)
  theta[ix$y_cell] <- log(counts[, 1L] / counts[, 3L])
  theta[ix$d_cell] <- log(counts[, 2L] / counts[, 3L])
  converged <- FALSE
  for (iter in seq_len(40L)) {
    co <- multinom_components(theta, long, TRUE)
    if (!is.finite(rcond(co$info)) || rcond(co$info) < 1e-12)
      return(list(fail = "outcome-singular-information"))
    step <- try(solve(co$info, co$score), silent = TRUE)
    if (inherits(step, "try-error") || any(!is.finite(step)))
      return(list(fail = "outcome-model"))
    scale_step <- 1
    accepted <- FALSE
    while (scale_step >= 2^-12) {
      candidate <- theta + scale_step * step
      ll <- multinom_components(candidate, long, FALSE)$loglik
      if (is.finite(ll) && ll >= co$loglik - 1e-8) {
        theta <- candidate
        accepted <- TRUE
        break
      }
      scale_step <- scale_step / 2
    }
    if (!accepted) return(list(fail = "outcome-model"))
    if (max(abs(scale_step * step)) < 1e-8) {
      converged <- TRUE
      break
    }
  }
  if (!converged || any(abs(theta) > 30)) return(list(fail = "outcome-separation"))
  co <- multinom_components(theta, long, TRUE)
  if (any(!is.finite(c(co$py, co$pd))) || any(co$py + co$pd >= 1))
    return(list(fail = "invalid-predicted-hazard"))
  c(list(fail = NULL, theta = theta), co)
}

build_msm_joint <- function(dat, sw, outcome) {
  ix <- outcome_index()
  n <- dat$n
  p <- 13L + ix$p
  B <- matrix(0, p, p)
  B[1:13, 1:13] <- sw$nuisance_info / n
  B[13L + seq_len(ix$p), 13L + seq_len(ix$p)] <- outcome$info / n
  long <- sw$long
  cross <- matrix(0, ix$p, 13L)
  cy <- rowsum(long$dlog * outcome$ry, long$cell, reorder = FALSE)
  cd <- rowsum(long$dlog * outcome$rd, long$cell, reorder = FALSE)
  cross[ix$y_cell[as.integer(rownames(cy))], ] <- cy
  cross[ix$d_cell[as.integer(rownames(cd))], ] <- cd
  cross[ix$y_slope, ] <- crossprod(long$Z * outcome$ry, long$dlog)
  cross[ix$d_slope, ] <- crossprod(long$Z * outcome$rd, long$dlog)
  B[13L + seq_len(ix$p), 1:13] <- -cross / n
  if (!is.finite(rcond(B)) || rcond(B) < 1e-12)
    return(list(fail = "singular-stacked-bread"))

  Uout <- matrix(0, n, ix$p)
  key <- (long$id - 1L) * ix$C + long$cell
  ag <- rowsum(cbind(outcome$ry, outcome$rd), key, reorder = FALSE)
  keyv <- as.integer(rownames(ag))
  ids <- (keyv - 1L) %/% ix$C + 1L
  cells <- (keyv - 1L) %% ix$C + 1L
  Uout[cbind(ids, ix$y_cell[cells])] <- ag[, 1L]
  Uout[cbind(ids, ix$d_cell[cells])] <- ag[, 2L]
  slopes <- rows_by_id(cbind(long$Z * outcome$ry, long$Z * outcome$rd), long$id, n)
  Uout[, ix$y_slope] <- slopes[, 1:4, drop = FALSE]
  Uout[, ix$d_slope] <- slopes[, 5:8, drop = FALSE]
  U <- cbind(sw$nuisance_score, Uout)
  list(fail = NULL, B = B, U = U)
}

fit_msm <- function(dat, joint = TRUE) {
  den <- fit_assignment_models(dat)
  if (!is.null(den$fail)) return(list(fail = den$fail))
  num <- fit_numerator_models(dat, den)
  if (!is.null(num$fail)) return(list(fail = num$fail))
  sw <- build_stabilized_long(dat, den, num, derivatives = joint)
  if (!is.null(sw$fail)) return(sw)
  outcome <- fit_weighted_multinomial(sw$long)
  if (!is.null(outcome$fail))
    return(list(fail = outcome$fail, paths = sw$paths, long = sw$long))
  jj <- if (joint) build_msm_joint(dat, sw, outcome) else list(fail = NULL)
  if (!is.null(jj$fail)) return(list(fail = jj$fail, paths = sw$paths,
                                     long = sw$long, outcome = outcome))
  list(fail = NULL, den = den, num = num, sw = sw, paths = sw$paths,
       long = sw$long, outcome = outcome, joint = jj)
}

standardize_component <- function(fit, dat, strategy, subgroup, horizon,
                                  endpoint, gradient = TRUE) {
  ix <- outcome_index()
  keep <- switch(subgroup, all = rep(TRUE, dat$n), G0 = dat$G == 0L,
                 G1 = dat$G == 1L)
  ids <- which(keep)
  if (!length(ids)) return(list(fail = "empty-subgroup"))
  Z <- cbind(dat$X[ids], dat$G[ids], dat$L0[ids], strategy * dat$G[ids])
  theta <- fit$outcome$theta
  py <- pd <- matrix(NA_real_, length(ids), horizon)
  for (tt in seq_len(horizon)) {
    cell <- strategy * N_MONTHS + tt
    ey <- theta[ix$y_cell[cell]] + drop(Z %*% theta[ix$y_slope])
    ed <- theta[ix$d_cell[cell]] + drop(Z %*% theta[ix$d_slope])
    mm <- pmax(0, ey, ed)
    den <- exp(-mm) + exp(ey - mm) + exp(ed - mm)
    py[, tt] <- exp(ey - mm) / den
    pd[, tt] <- exp(ed - mm) / den
  }
  if (any(!is.finite(c(py, pd))) || any(py + pd >= 1))
    return(list(fail = "invalid-predicted-hazard"))
  S <- matrix(1, length(ids), horizon)
  if (horizon > 1L)
    for (tt in 2:horizon) S[, tt] <- S[, tt - 1L] * (1 - py[, tt - 1L] - pd[, tt - 1L])
  pk <- if (endpoint == "Y") py else pd
  contribution <- S * pk
  risk <- rowSums(contribution)
  if (!gradient) return(list(fail = NULL, risk = risk, ids = ids))

  grad <- numeric(ix$p)
  future <- numeric(length(ids))
  for (tt in horizon:1L) {
    remain <- 1 - py[, tt] - pd[, tt]
    if (endpoint == "Y") {
      dpy <- S[, tt] - future / remain
      dpd <- -future / remain
    } else {
      dpy <- -future / remain
      dpd <- S[, tt] - future / remain
    }
    de_y <- dpy * py[, tt] * (1 - py[, tt]) - dpd * py[, tt] * pd[, tt]
    de_d <- -dpy * py[, tt] * pd[, tt] + dpd * pd[, tt] * (1 - pd[, tt])
    cell <- strategy * N_MONTHS + tt
    grad[ix$y_cell[cell]] <- mean(de_y)
    grad[ix$d_cell[cell]] <- mean(de_d)
    grad[ix$y_slope] <- grad[ix$y_slope] + colMeans(Z * de_y)
    grad[ix$d_slope] <- grad[ix$d_slope] + colMeans(Z * de_d)
    future <- future + contribution[, tt]
  }
  list(fail = NULL, risk = risk, ids = ids, gradient = grad)
}

estimate_msm_rows <- function(fit, dat, with_se = TRUE) {
  specs <- endpoint_grid()
  rows <- list()
  if (!is.null(fit$fail)) return(blank_estimates("msm", fit$fail))
  for (i in seq_len(nrow(specs))) {
    s <- specs[i, , drop = FALSE]
    a0 <- standardize_component(fit, dat, 0L, s$subgroup, s$horizon,
                                s$endpoint, gradient = with_se)
    a1 <- standardize_component(fit, dat, 1L, s$subgroup, s$horizon,
                                s$endpoint, gradient = with_se)
    if (!is.null(a0$fail) || !is.null(a1$fail)) {
      rows[[i]] <- make_estimate_row("msm", s,
        list(fail = a0$fail %||% a1$fail))
      next
    }
    rd <- a1$risk - a0$risk
    est <- mean(rd)
    ans <- list(fail = NULL, est = est, se = NA_real_)
    if (with_se) {
      ix <- outcome_index()
      grad <- numeric(13L + ix$p)
      grad[13L + seq_len(ix$p)] <- a1$gradient - a0$gradient
      adj <- try(solve(t(fit$joint$B), grad), silent = TRUE)
      if (inherits(adj, "try-error") || any(!is.finite(adj))) {
        ans <- list(fail = "singular-stacked-bread")
      } else {
        base <- numeric(dat$n)
        psub <- length(a0$ids) / dat$n
        base[a0$ids] <- (rd - est) / psub
        influence <- base + drop(fit$joint$U %*% adj)
        vv <- stats::var(influence) / dat$n
        if (!is.finite(vv) || vv < 0) ans <- list(fail = "negative-or-nonfinite-variance")
        else ans$se <- sqrt(vv)
      }
    }
    info <- cell_information(fit$paths, dat, s$endpoint, s$subgroup, s$horizon)
    rows[[i]] <- make_estimate_row("msm", s, ans, info = info)
  }
  do.call(rbind, rows)
}

subset_replicate <- function(dat, idx) {
  list(n = length(idx), X = dat$X[idx], G = dat$G[idx], L0 = dat$L0[idx],
       L = dat$L[idx, , drop = FALSE], A = dat$A[idx, , drop = FALSE],
       p_true = dat$p_true[idx, , drop = FALSE],
       at_risk = dat$at_risk[idx, , drop = FALSE],
       event_month = dat$event_month[idx], event_type = dat$event_type[idx])
}

bootstrap_msm_rows <- function(dat, original_rows, sentinel) {
  specs <- endpoint_grid()
  if (!sentinel) return(blank_estimates("msm_boot", "not-sentinel"))
  values <- matrix(NA_real_, BOOT_B, nrow(specs))
  for (b in seq_len(BOOT_B)) {
    idx <- sample.int(dat$n, dat$n, replace = TRUE)
    fb <- try(fit_msm(subset_replicate(dat, idx), joint = FALSE), silent = TRUE)
    if (inherits(fb, "try-error") || !is.null(fb$fail)) next
    rb <- estimate_msm_rows(fb, subset_replicate(dat, idx), with_se = FALSE)
    values[b, ] <- rb$est
  }
  rows <- vector("list", nrow(specs))
  for (i in seq_len(nrow(specs))) {
    ok <- is.finite(values[, i])
    fraction <- mean(ok)
    if (sum(ok) < BOOT_MIN_SUCCESS) {
      rows[[i]] <- make_estimate_row("msm_boot", specs[i, , drop = FALSE],
                                     list(fail = "bootstrap-insufficient"),
                                     boot_success = fraction)
    } else {
      original <- original_rows[i, ]
      ans <- list(fail = NULL, est = original$est,
                  se = stats::sd(values[ok, i]))
      qq <- stats::quantile(values[ok, i], c(0.025, 0.975), names = FALSE)
      info <- list(event_ess = original$event_ess,
                   nonevent_ess = original$nonevent_ess,
                   min_riskset_ess = original$min_riskset_ess,
                   warning = original$warning)
      rows[[i]] <- make_estimate_row("msm_boot", specs[i, , drop = FALSE], ans,
                                     info = info, lo = qq[1L], hi = qq[2L],
                                     boot_success = fraction)
    }
  }
  do.call(rbind, rows)
}

## Critique fix: the fixed-nuisance estimator is not called a status quo. The
## stabilized outcome-model comparator, nuisance-aware inference, and sentinel
## bootstrap are implemented as separate named methods.
estimate_replicate <- function(dat, scen) {
  ex <- estimate_exact(dat)
  mf <- fit_msm(dat, joint = TRUE)
  mr <- estimate_msm_rows(mf, dat, with_se = TRUE)
  br <- bootstrap_msm_rows(dat, mr, isTRUE(scen$is_sentinel))
  md <- if (!is.null(mf$paths)) path_diagnostics(mf$paths, dat, "msm", mf$fail) else
    complete_result(transform(expand.grid(subgroup = c("all", "G0", "G1"),
      strategy = 0:1, month = seq_len(N_MONTHS), stringsAsFactors = FALSE),
      row_type = "diagnostic", method = "msm", fail = mf$fail %||% "msm-failed"))
  complete_result(rbind(ex$rows, mr, br, ex$diagnostics, md))
}

truth_batch <- function(scen, n) {
  d <- simulate_regime_pair(scen, n)
  specs <- endpoint_grid()
  rows <- vector("list", nrow(specs))
  for (i in seq_len(nrow(specs))) {
    s <- specs[i, , drop = FALSE]
    keep <- switch(s$subgroup, all = rep(TRUE, n), G0 = d$G == 0L, G1 = d$G == 1L)
    code <- if (s$endpoint == "Y") 1L else 2L
    z0 <- as.numeric(d$type0 == code & !is.na(d$month0) & d$month0 <= s$horizon)
    z1 <- as.numeric(d$type1 == code & !is.na(d$month1) & d$month1 <= s$horizon)
    delta <- z1[keep] - z0[keep]
    rows[[i]] <- data.frame(endpoint = s$endpoint, subgroup = s$subgroup,
      horizon = s$horizon, n = length(delta), sum_delta = sum(delta),
      sumsq_delta = sum(delta^2), sum0 = sum(z0[keep]), sum1 = sum(z1[keep]),
      stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

truth_for <- function(scen) {
  core <- identical(as.character(scen$phase), "core")
  initial <- if (core) N_TRUTH_CORE_INITIAL else N_TRUTH_VALID_INITIAL
  step <- if (core) N_TRUTH_CORE_STEP else N_TRUTH_VALID_STEP
  maximum <- if (core) MAX_TRUTH_CORE else MAX_TRUTH_VALID
  acc <- NULL
  done <- 0L
  repeat {
    b <- truth_batch(scen, if (done == 0L) initial else step)
    if (is.null(acc)) acc <- b else {
      for (nm in c("n", "sum_delta", "sumsq_delta", "sum0", "sum1"))
        acc[[nm]] <- acc[[nm]] + b[[nm]]
    }
    done <- done + if (done == 0L) initial else step
    variance <- pmax(0, (acc$sumsq_delta - acc$sum_delta^2 / acc$n) /
                         pmax(1, acc$n - 1L))
    mcse <- sqrt(variance / acc$n)
    tol <- ifelse(acc$subgroup == "all", TRUTH_TOL_OVERALL, TRUTH_TOL_SUBGROUP)
    if (all(mcse <= tol) || done >= maximum) break
  }
  data.frame(endpoint = acc$endpoint, subgroup = acc$subgroup,
             horizon = acc$horizon, true = acc$sum_delta / acc$n,
             risk0 = acc$sum0 / acc$n, risk1 = acc$sum1 / acc$n,
             truth_mcse = mcse, n_truth = acc$n,
             truth_tolerance_met = mcse <= tol, stringsAsFactors = FALSE)
}

## Analytic derivative validation for the exact stacked sandwich.
validate_exact_derivative <- function(dat) {
  fit <- fit_assignment_models(dat)
  if (!is.null(fit$fail)) return(NA_real_)
  h <- 60L
  z <- dat$event_type == 1L & !is.na(dat$event_month) & dat$event_month <= h
  paths <- make_weight_paths(dat, fit$p)
  base <- hajek_fixed(paths[[1L]]$w[, h], paths[[2L]]$w[, h], z,
                      rep(TRUE, dat$n))
  st <- stacked_hajek(base, fit, dat, z, rep(TRUE, dat$n), h, TRUE)
  if (!is.null(st$fail)) return(NA_real_)
  theta <- c(fit$baseline$coef, fit$post$fit$coef, base$mu0, base$mu1)
  score_mean <- function(th) {
    p <- matrix(NA_real_, dat$n, N_MONTHS)
    p[, 1L] <- expit(drop(fit$x0 %*% th[1:4]))
    p[cbind(fit$post$id, fit$post$month)] <-
      expit(drop(fit$post$X %*% th[5:9]))
    pp <- make_weight_paths(dat, p)
    u0 <- pp[[1L]]$w[, h] * (z - th[10L])
    u1 <- pp[[2L]]$w[, h] * (z - th[11L])
    s0 <- colMeans(fit$x0 * (fit$y0 - p[, 1L]))
    sp <- colSums(fit$post$X * (fit$post$y - p[cbind(fit$post$id,
                                                     fit$post$month)])) / dat$n
    c(s0, sp, mean(u0), mean(u1))
  }
  eps <- 1e-5
  J <- vapply(seq_along(theta), function(j) {
    up <- dn <- theta
    up[j] <- up[j] + eps
    dn[j] <- dn[j] - eps
    (score_mean(up) - score_mean(dn)) / (2 * eps)
  }, numeric(length(theta)))
  max(abs(-J - st$bread))
}

validate_msm_k0 <- function(dat) {
  fit <- fit_msm(dat, joint = TRUE)
  if (!is.null(fit$fail)) return(data.frame(fail = fit$fail))
  model <- estimate_msm_rows(fit, dat, TRUE)
  long <- fit$long
  direct <- matrix(NA_real_, 2L, 2L)
  for (gg in 0:1) {
    sy <- sd <- numeric(N_MONTHS)
    for (tt in seq_len(N_MONTHS)) {
      cell <- gg * N_MONTHS + tt
      q <- long$cell == cell
      sy[tt] <- stats::weighted.mean(long$category[q] == 1L, long$weight[q])
      sd[tt] <- stats::weighted.mean(long$category[q] == 2L, long$weight[q])
    }
    surv <- cumprod(c(1, 1 - sy[-N_MONTHS] - sd[-N_MONTHS]))
    direct[gg + 1L, ] <- c(sum(surv * sy), sum(surv * sd))
  }
  data.frame(endpoint = c("Y", "D"),
             model_rd = c(model$est[model$endpoint == "Y" & model$subgroup == "all" &
                                      model$horizon == 60L],
                          model$est[model$endpoint == "D" & model$subgroup == "all" &
                                      model$horizon == 60L]),
             direct_weighted_rd = direct[2L, ] - direct[1L, ],
             fail = NA_character_)
}
