## Study 2 (PRO-02): IPW estimation, joint sandwich inference, and selectors.

`%||%` <- function(a, b) if (is.null(a)) b else a

empty_family <- function(candidates, reason) {
  tab <- data.frame(
    candidates[, c("candidate", "c", "h")],
    est = NA_real_, se = NA_real_, mu1 = NA_real_, mu0 = NA_real_,
    ess1 = NA_real_, ess0 = NA_real_, max_weight = NA_real_,
    fail = rep(reason, nrow(candidates)), stringsAsFactors = FALSE)
  list(table = tab, e = NULL,
       cov_rd = matrix(NA_real_, nrow(candidates), nrow(candidates)),
       model_fail = reason)
}

## Fit one propensity model and jointly estimate every candidate. The stacked
## sandwich contains the propensity score and both Hajek mean equations for all
## candidates that pass the denominator and effective-sample-size checks.
fit_ipw_family <- function(dat, candidates) {
  n <- nrow(dat)
  X <- cbind(1, dat$Z, dat$S - 0.5, dat$C - 0.5, dat$B)
  Aobs <- dat$A
  fit <- try(suppressWarnings(stats::glm.fit(
    x = X, y = Aobs, family = stats::binomial())), silent = TRUE)
  if (inherits(fit, "try-error") || !isTRUE(fit$converged) ||
      fit$rank < ncol(X) || any(!is.finite(fit$coefficients))) {
    return(empty_family(candidates, "propensity-failed"))
  }
  e <- as.vector(fit$fitted.values)
  if (any(!is.finite(e)) || any(e <= 0 | e >= 1)) {
    return(empty_family(candidates, "propensity-probability"))
  }

  K <- nrow(candidates)
  tab <- data.frame(
    candidates[, c("candidate", "c", "h")],
    est = NA_real_, se = NA_real_, mu1 = NA_real_, mu0 = NA_real_,
    ess1 = NA_real_, ess0 = NA_real_, max_weight = NA_real_,
    fail = rep(NA_character_, K), stringsAsFactors = FALSE)
  w1_list <- vector("list", K)
  w0_list <- vector("list", K)
  y_list <- vector("list", K)

  for (k in seq_len(K)) {
    use <- dat$age >= candidates$c[k]
    y <- as.numeric(dat$T_event <= candidates$h[k])
    w1 <- use * Aobs / e
    w0 <- use * (1 - Aobs) / (1 - e)
    d1 <- sum(w1)
    d0 <- sum(w0)
    ess1 <- if (sum(w1^2) > 0) d1^2 / sum(w1^2) else 0
    ess0 <- if (sum(w0^2) > 0) d0^2 / sum(w0^2) else 0
    observed_weight <- ifelse(Aobs == 1, 1 / e, 1 / (1 - e))

    tab$ess1[k] <- ess1
    tab$ess0[k] <- ess0
    tab$max_weight[k] <- if (any(use)) max(observed_weight[use]) else NA_real_
    y_list[[k]] <- y
    w1_list[[k]] <- w1
    w0_list[[k]] <- w0

    if (!is.finite(d1) || !is.finite(d0) || d1 <= 0 || d0 <= 0) {
      tab$fail[k] <- "weighted-denominator"
    } else if (ess1 < MIN_ESS || ess0 < MIN_ESS) {
      tab$fail[k] <- "effective-sample-size"
    } else {
      tab$mu1[k] <- sum(w1 * y) / d1
      tab$mu0[k] <- sum(w0 * y) / d0
      tab$est[k] <- tab$mu1[k] - tab$mu0[k]
    }
  }

  valid <- which(is.na(tab$fail))
  cov_rd <- matrix(NA_real_, K, K,
                   dimnames = list(candidates$candidate, candidates$candidate))
  if (!length(valid)) {
    return(list(table = tab, e = e, cov_rd = cov_rd,
                model_fail = "no-estimable-candidate"))
  }

  p <- ncol(X)
  q <- length(valid)
  dim_total <- p + 2L * q
  scores <- matrix(0, n, dim_total)
  scores[, seq_len(p)] <- X * as.vector(Aobs - e)
  Ahat <- matrix(0, dim_total, dim_total)
  Ahat[seq_len(p), seq_len(p)] <-
    crossprod(X, X * as.vector(e * (1 - e))) / n

  mu1_index <- integer(q)
  mu0_index <- integer(q)
  for (j in seq_along(valid)) {
    k <- valid[j]
    i1 <- p + 2L * j - 1L
    i0 <- p + 2L * j
    mu1_index[j] <- i1
    mu0_index[j] <- i0
    y <- y_list[[k]]
    w1 <- w1_list[[k]]
    w0 <- w0_list[[k]]
    r1 <- y - tab$mu1[k]
    r0 <- y - tab$mu0[k]
    scores[, i1] <- w1 * r1
    scores[, i0] <- w0 * r0
    Ahat[i1, seq_len(p)] <- colMeans(X * (w1 * (1 - e) * r1))
    Ahat[i0, seq_len(p)] <- colMeans(X * (-w0 * e * r0))
    Ahat[i1, i1] <- mean(w1)
    Ahat[i0, i0] <- mean(w0)
  }

  Bhat <- crossprod(scores) / n
  inverse <- try(solve(Ahat), silent = TRUE)
  if (inherits(inverse, "try-error") || any(!is.finite(inverse))) {
    tab$fail[valid] <- "sandwich-inversion"
    tab$est[valid] <- NA_real_
    return(list(table = tab, e = e, cov_rd = cov_rd,
                model_fail = "sandwich-inversion"))
  }
  V <- inverse %*% Bhat %*% t(inverse) / n
  contrast <- matrix(0, q, dim_total)
  for (j in seq_len(q)) {
    contrast[j, mu1_index[j]] <- 1
    contrast[j, mu0_index[j]] <- -1
  }
  Vrd <- contrast %*% V %*% t(contrast)
  cov_rd[valid, valid] <- Vrd
  se <- sqrt(pmax(diag(Vrd), 0))
  tab$se[valid] <- se
  bad <- valid[!is.finite(tab$est[valid]) | !is.finite(tab$se[valid]) |
                 tab$se[valid] <= 0]
  if (length(bad)) {
    tab$fail[bad] <- "nonfinite-estimate-or-se"
    tab$est[bad] <- NA_real_
    tab$se[bad] <- NA_real_
  }
  list(table = tab, e = e, cov_rd = cov_rd, model_fail = NA_character_)
}

candidate_counts <- function(dat, candidates) {
  do.call(rbind, lapply(seq_len(nrow(candidates)), function(k) {
    use <- dat$age >= candidates$c[k]
    data.frame(
      candidate = candidates$candidate[k],
      n1 = sum(use & dat$A == 1),
      n0 = sum(use & dat$A == 0),
      events = sum(use & dat$T_event <= candidates$h[k]),
      outcome_variation = length(unique(dat$T_event[use] <= candidates$h[k])) > 1L,
      stringsAsFactors = FALSE)
  }))
}

## The 70-event rule is an arbitrary recorded behavior rule. It is not an
## adequacy threshold for Hajek IPW or sandwich inference.
workability_select <- function(dat, candidates, arm_min = CUT_WORK_ARM,
                               event_min = CUT_WORK_EVENTS) {
  counts <- candidate_counts(dat, candidates)
  qualifies <- counts$n1 >= arm_min & counts$n0 >= arm_min &
    counts$events >= event_min
  if (any(qualifies)) {
    j <- which(qualifies)[1]
    no_threshold <- FALSE
  } else {
    j <- which.max(counts$events)
    no_threshold <- TRUE
  }
  list(candidate = counts$candidate[j], fail = NA_character_,
       no_threshold = no_threshold, counts = counts)
}

prognostic_select <- function(dat, candidates, score,
                              arm_min = CUT_WORK_ARM) {
  sdev <- stats::sd(score)
  if (!is.finite(sdev) || sdev <= 0) {
    return(list(candidate = NA_character_, fail = "score-standardization"))
  }
  zscore <- (score - mean(score)) / sdev
  counts <- candidate_counts(dat, candidates)
  value <- rep(NA_real_, nrow(candidates))
  for (k in seq_len(nrow(candidates))) {
    if (counts$n1[k] < arm_min || counts$n0[k] < arm_min ||
        !counts$outcome_variation[k]) next
    use <- dat$age >= candidates$c[k]
    y <- as.numeric(dat$T_event[use] <= candidates$h[k])
    value[k] <- suppressWarnings(stats::cor(zscore[use], y)^2)
  }
  if (!any(is.finite(value))) {
    return(list(candidate = NA_character_, fail = "no-prognostic-candidate"))
  }
  list(candidate = candidates$candidate[which.max(value)],
       fail = NA_character_, score = value)
}

effect_seeking_select <- function(family) {
  ok <- is.na(family$table$fail) & is.finite(family$table$est) &
    is.finite(family$table$se) & family$table$se > 0
  if (!any(ok)) {
    return(list(candidate = NA_character_, fail = "no-effect-candidate"))
  }
  z <- family$table$est / family$table$se
  z[!ok] <- Inf
  list(candidate = family$table$candidate[which.min(z)], fail = NA_character_)
}

weighted_moments <- function(x, w) {
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(c(mean = NA_real_, var = NA_real_))
  mu <- sum(w * x) / sw
  c(mean = mu, var = sum(w * (x - mu)^2) / sw)
}

balance_select <- function(dat, candidates, e) {
  if (is.null(e) || any(!is.finite(e))) {
    return(list(candidate = NA_character_, fail = "propensity-failed"))
  }
  cuts <- unique(candidates$c)
  rows <- list()
  covariates <- data.frame(Z = dat$Z, S = dat$S, C = dat$C, B = dat$B)
  for (cc in cuts) {
    use <- dat$age >= cc
    w1 <- use * dat$A / e
    w0 <- use * (1 - dat$A) / (1 - e)
    ess1 <- if (sum(w1^2) > 0) sum(w1)^2 / sum(w1^2) else 0
    ess0 <- if (sum(w0^2) > 0) sum(w0)^2 / sum(w0^2) else 0
    max_smd <- NA_real_
    if (ess1 >= MIN_ESS && ess0 >= MIN_ESS) {
      smd <- vapply(covariates, function(v) {
        a <- weighted_moments(v, w1)
        b <- weighted_moments(v, w0)
        den <- sqrt((a[["var"]] + b[["var"]]) / 2)
        if (is.finite(den) && den > 0) abs(a[["mean"]] - b[["mean"]]) / den else Inf
      }, numeric(1))
      max_smd <- max(smd)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      c = cc, max_smd = max_smd, ess1 = ess1, ess0 = ess0)
  }
  z <- do.call(rbind, rows)
  z <- z[is.finite(z$max_smd), , drop = FALSE]
  if (!nrow(z)) {
    return(list(candidate = NA_character_, fail = "no-balanced-threshold"))
  }
  z <- z[order(z$max_smd, abs(z$c - REFERENCE_C), z$c), , drop = FALSE]
  id <- sprintf("c%02d-h%02d", z$c[1], REFERENCE_H)
  list(candidate = id, fail = NA_character_, balance = z)
}

multiverse_summary <- function(family) {
  ok <- is.na(family$table$fail)
  if (!all(ok)) {
    return(list(range = NA_real_, iqr = NA_real_, standardized_range = NA_real_,
                fail = "incomplete-family"))
  }
  est <- family$table$est
  se <- family$table$se
  r <- diff(range(est))
  list(range = r, iqr = stats::IQR(est),
       standardized_range = r / stats::median(se), fail = NA_character_)
}

output_row <- function(row_type, method, selector, candidate = NA_character_,
                       family = NULL, critical = NA_real_, fail = NA_character_,
                       fail_stage = NA_character_, no_threshold = NA,
                       mv_range = NA_real_, mv_iqr = NA_real_,
                       mv_std_range = NA_real_) {
  tab <- NULL
  if (!is.null(family) && !is.na(candidate)) {
    tab <- family$table[match(candidate, family$table$candidate), , drop = FALSE]
  }
  inherited <- if (!is.null(tab) && nrow(tab)) tab$fail[1] else NA_character_
  final_fail <- if (!is.na(fail)) fail else inherited
  if (is.na(fail_stage) && !is.na(final_fail)) fail_stage <- "estimation"
  data.frame(
    row_type = row_type, method = method, selector = selector,
    candidate = candidate,
    c = if (!is.null(tab) && nrow(tab)) tab$c[1] else NA_integer_,
    h = if (!is.null(tab) && nrow(tab)) tab$h[1] else NA_integer_,
    est = if (!is.null(tab) && nrow(tab)) tab$est[1] else NA_real_,
    se = if (!is.null(tab) && nrow(tab)) tab$se[1] else NA_real_,
    critical = critical,
    ess1 = if (!is.null(tab) && nrow(tab)) tab$ess1[1] else NA_real_,
    ess0 = if (!is.null(tab) && nrow(tab)) tab$ess0[1] else NA_real_,
    max_weight = if (!is.null(tab) && nrow(tab)) tab$max_weight[1] else NA_real_,
    no_threshold = as.logical(no_threshold),
    mv_range = mv_range, mv_iqr = mv_iqr, mv_std_range = mv_std_range,
    fail = final_fail, fail_stage = fail_stage,
    stringsAsFactors = FALSE)
}
