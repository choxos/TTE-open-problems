## Study LRN-05: deterministic truth, metric estimators, and sandwiches.

## Deterministic Gaussian quadrature for the standard normal, applied on the
## probability scale: Gauss-Legendre on u in (0,1) with x = qnorm(u).
##
## The Gauss-Hermite rule this replaces spends almost all of its nodes where
## there is no mass. Its weights underflow to zero past |x| near 26, so at
## order 4096 only 528 of 4096 nodes survive and effective resolution grows
## like the square root of the order while the cost grows like its cube. The
## protocol's own tolerance, every cut point and bin risk moving by less than
## 0.00025, then needs order 56,000, which is not reachable in double
## precision. Hermite converged the smooth components to 4e-6, far inside their
## 1e-4 tolerance, and left 67 of 116 curve components outside theirs, because
## cut points and bin risks are quantiles of the score distribution rather than
## smooth integrals and quantile error is set by node spacing where the mass
## is.
##
## Legendre weights are all of order 1/n, so every node is usable. This changes
## the numerical rule for a fixed integral, not the estimand, and it is the
## same class of rule the protocol names. The order-doubling convergence rule,
## both tolerances, and the independent two-million-profile Monte Carlo check
## are all unchanged, and that check is what establishes the answer is right.
##
## Nodes and weights come from Newton iteration on the Legendre polynomial
## rather than an eigendecomposition, which makes high orders cheap.
normal_quadrature <- function(order) {
  m <- (order + 1L) %/% 2L
  i <- seq_len(m)
  ## Tricomi's asymptotic starting values, accurate enough that Newton needs a
  ## handful of steps at any order.
  z <- cos(pi * (i - 0.25) / (order + 0.5))
  for (step in seq_len(100L)) {
    p0 <- rep(1, m)
    p1 <- rep(0, m)
    for (k in seq_len(order)) {
      p2 <- p1
      p1 <- p0
      p0 <- ((2 * k - 1) * z * p1 - (k - 1) * p2) / k
    }
    dp <- order * (z * p0 - p1) / (z * z - 1)
    dz <- p0 / dp
    z <- z - dz
    if (max(abs(dz)) < 1e-15) break
  }
  ## Legendre on (-1, 1), mirrored to the full set, then mapped to (0, 1).
  xl <- c(-z, if (order %% 2L == 1L) rev(z)[-1L] else rev(z))
  wl <- 2 / ((1 - z * z) * dp * dp)
  wl <- c(wl, if (order %% 2L == 1L) rev(wl)[-1L] else rev(wl))
  u <- 0.5 * (xl + 1)
  w <- wl / 2
  keep <- u > 0 & u < 1 & is.finite(w) & w > 0
  list(x = stats::qnorm(u[keep]), w = w[keep] / sum(w[keep]))
}

weighted_quantile <- function(x, w, probabilities) {
  o <- order(x)
  x <- x[o]
  w <- w[o]
  cw <- cumsum(w) / sum(w)
  vapply(probabilities, function(p) {
    stats::approx(c(0, cw), c(x[1L], x), xout = p,
                  method = 'linear', ties = 'ordered', rule = 2)$y
  }, numeric(1))
}

assign_bins <- function(score, cuts) {
  findInterval(score, c(-Inf, cuts, Inf), rightmost.closed = TRUE)
}

weighted_auc_value <- function(score, case_weight, control_weight) {
  wc <- sum(case_weight)
  wn <- sum(control_weight)
  if (!is.finite(wc) || !is.finite(wn) || wc <= 0 || wn <= 0) return(NA_real_)
  o <- order(score)
  rr <- rle(score[o])
  group_sorted <- rep(seq_along(rr$lengths), rr$lengths)
  group <- integer(length(score))
  group[o] <- group_sorted
  ## `reorder` must stay at its default. Group labels number the distinct
  ## scores in increasing order, and everything below reads `m` positionally:
  ## `cumsum` treats row k as the k-th smallest score and `concordance[group]`
  ## indexes by label. With `reorder = FALSE` the rows arrive in order of first
  ## appearance in the input instead, so the answer depends on how the caller
  ## happened to sort its data. It was right on the quadrature grid, which is
  ## nearly sorted by score already, and wrong on everything else: 0.5900
  ## against a true 0.6288 on the same 900 records. The truth verification
  ## compared a nearly-sorted grid against a randomly ordered Monte Carlo
  ## sample and reported a 0.0385 disagreement, which is how this was found.
  m <- rowsum(cbind(case_weight, control_weight), group)
  before <- c(0, head(cumsum(m[, 2L]), -1L))
  concordance <- (before + 0.5 * m[, 2L]) / wn
  sum(case_weight * concordance[group]) / wc
}

population_grid <- function(order, delta) {
  gh <- normal_quadrature(order)
  ii <- rep(seq_len(order), each = 4L)
  x1 <- gh$x[ii]
  x2 <- rep(rep(0:1, each = 2L), times = order)
  l0 <- rep(0:1, times = 2L * order)
  p0 <- baseline_l_probability(x1, x2, 0)
  p1 <- baseline_l_probability(x1, x2, 1)
  pl <- (1 - P_U) * p0 + P_U * p1
  w <- gh$w[ii] * 0.50 * ifelse(l0 == 1L, pl, 1 - pl)

  ## Gauss-Hermite nodes reach |x1| near 64 at order 1024 and near 90 at 2048,
  ## and the outermost weights underflow to exactly zero long before that. Those
  ## nodes carry no mass, but the risk recursion overflows on them, and 0 * NaN
  ## is NaN, so nodes contributing nothing to the integral destroyed it: at
  ## order 2048 every truth value came back NA. Dropping them is what lets the
  ## protocol's rule, doubling the order until the change falls below tolerance,
  ## run past 1024 at all.
  keep <- w > 0 & is.finite(w)
  w <- w[keep] / sum(w[keep])
  list(x1 = x1[keep], x2 = x2[keep], l0 = l0[keep], w = w, delta = delta)
}

population_bundle <- function(x1, x2, l0, w, delta) {
  p <- list(
    g0 = counterfactual_risk(x1, x2, l0, delta, 'g0'),
    g1 = counterfactual_risk(x1, x2, l0, delta, 'g1')
  )
  rows <- list()
  cuts_out <- list()
  values <- list()
  add_row <- function(strategy, score, metric, truth, bin = NA_integer_,
                      score_mean = NA_real_) {
    rows[[length(rows) + 1L]] <<- data.frame(
      strategy = strategy, score = score, metric = metric, bin = bin,
      truth = truth, score_mean = score_mean, stringsAsFactors = FALSE)
  }

  for (g in STRATEGIES) {
    score_set <- list(
      oracle = p[[g]],
      miscalibrated = expit(-0.35 + 0.75 * logit(clip_probability(p[[g]])))
    )
    for (sk in SCORES) {
      r <- score_set[[sk]]
      if (sk == 'oracle') {
        add_row(g, sk, 'cal_intercept', 0)
        add_row(g, sk, 'cal_slope', 1)
      } else {
        add_row(g, sk, 'cal_intercept', 0.35 / 0.75)
        add_row(g, sk, 'cal_slope', 1 / 0.75)
      }

      ## Critique implementation: each strategy receives its own deterministic
      ## population partition. No kth-bin subtraction across strategies exists.
      cuts <- weighted_quantile(r, w, seq(0.1, 0.9, by = 0.1))
      cuts_out[[length(cuts_out) + 1L]] <- data.frame(
        strategy = g, score = sk, cut = seq_along(cuts), value = cuts,
        stringsAsFactors = FALSE)
      bin <- assign_bins(r, cuts)
      for (k in 1:10) {
        wk <- w * (bin == k)
        risk_k <- sum(wk * p[[g]]) / sum(wk)
        mean_k <- sum(wk * r) / sum(wk)
        metric <- sprintf('cal_bin_%02d', k)
        add_row(g, sk, metric, risk_k, k, mean_k)
        values[[paste(g, sk, metric, sep = '|')]] <- risk_k
      }

      brier <- sum(w * (p[[g]] * (1 - p[[g]]) + (p[[g]] - r)^2))
      auc <- weighted_auc_value(r, w * p[[g]], w * (1 - p[[g]]))
      add_row(g, sk, 'brier', brier)
      add_row(g, sk, 'auc', auc)
      values[[paste(g, sk, 'brier', sep = '|')]] <- brier
      values[[paste(g, sk, 'auc', sep = '|')]] <- auc
    }
    risk <- sum(w * p[[g]])
    add_row(g, 'oracle', 'risk', risk)
    values[[paste(g, 'oracle', 'risk', sep = '|')]] <- risk
  }

  for (sk in SCORES) for (metric in c('brier', 'auc')) {
    v <- values[[paste('g1', sk, metric, sep = '|')]] -
      values[[paste('g0', sk, metric, sep = '|')]]
    add_row('g1-g0', sk, metric, v)
  }
  add_row('g1-g0', 'oracle', 'risk',
          values[['g1|oracle|risk']] - values[['g0|oracle|risk']])

  list(rows = do.call(rbind, rows), cuts = do.call(rbind, cuts_out))
}

truth_vector <- function(bundle) {
  r <- bundle$rows
  key <- paste('row', r$strategy, r$score, r$metric,
               ifelse(is.na(r$bin), '00', sprintf('%02d', r$bin)), sep = '|')
  out <- stats::setNames(r$truth, key)
  use_mean <- is.finite(r$score_mean)
  out <- c(out, stats::setNames(r$score_mean[use_mean],
                                paste0('mean_score|', key[use_mean])))
  ctab <- bundle$cuts
  c(out, stats::setNames(ctab$value,
                         paste('cut', ctab$strategy, ctab$score,
                               sprintf('%02d', ctab$cut), sep = '|')))
}

truth_for_delta <- function(delta) {
  previous <- NULL
  final <- NULL
  converged <- FALSE
  last_curve_change <- Inf
  last_scalar_change <- Inf

  for (order in TRUTH_QUAD_ORDERS) {
    g <- population_grid(order, delta)
    current <- population_bundle(g$x1, g$x2, g$l0, g$w, delta)
    vec <- truth_vector(current)
    if (!is.null(previous) && order >= 512L) {
      common <- intersect(names(previous), names(vec))
      dif <- abs(vec[common] - previous[common])
      curve <- grepl('^cut[|]|^mean_score[|]|[|]cal_bin_', common)
      last_curve_change <- max(dif[curve], na.rm = TRUE)
      last_scalar_change <- max(dif[!curve], na.rm = TRUE)
      if (last_curve_change < TRUTH_CURVE_TOL &&
          last_scalar_change < TRUTH_SCALAR_TOL) {
        converged <- TRUE
        final <- current
        break
      }
    }
    previous <- vec
    final <- current
  }

  ## Critique implementation: every batch rebuilds its own cut points. The
  ## verification uncertainty therefore includes quantile construction rather
  ## than conditioning on one random set of cuts.
  batch_n <- as.integer(N_TRUTH_MC / N_TRUTH_BATCHES)
  batch <- vector('list', N_TRUTH_BATCHES)
  for (b in seq_len(N_TRUTH_BATCHES)) {
    x1 <- stats::rnorm(batch_n)
    x2 <- stats::rbinom(batch_n, 1, 0.50)
    pl <- (1 - P_U) * baseline_l_probability(x1, x2, 0) +
      P_U * baseline_l_probability(x1, x2, 1)
    l0 <- stats::rbinom(batch_n, 1, pl)
    z <- population_bundle(x1, x2, l0, rep(1 / batch_n, batch_n), delta)
    batch[[b]] <- truth_vector(z)
  }
  common <- Reduce(intersect, lapply(batch, names))
  mc <- do.call(cbind, lapply(batch, function(z) z[common]))
  mc_mean <- rowMeans(mc)
  mcse <- apply(mc, 1L, stats::sd) / sqrt(N_TRUTH_BATCHES)
  quad <- truth_vector(final)[common]
  difference <- mc_mean - quad
  auc_component <- grepl('[|]auc[|]00$', common)
  verification_ok <- all(abs(difference) <= TRUTH_MC_TOL + MC_Z * mcse) &&
    all(mcse[auc_component] < TRUTH_MC_TOL)

  verification <- data.frame(
    component = common, quadrature = unname(quad), mc_mean = unname(mc_mean),
    mcse = unname(mcse), difference = unname(difference),
    stringsAsFactors = FALSE
  )
  checks <- data.frame(
    delta = delta, quadrature_order = order,
    quadrature_converged = converged,
    max_curve_change = last_curve_change,
    max_scalar_change = last_scalar_change,
    verification_ok = verification_ok,
    max_verification_difference = max(abs(difference)),
    max_auc_mcse = max(mcse[auc_component]), stringsAsFactors = FALSE
  )
  c(final, list(checks = checks, verification = verification))
}

weight_diagnostics <- function(w, prescribed = NULL) {
  n <- length(w)
  positive <- is.finite(w) & w > 0
  mean_w <- mean(w, na.rm = TRUE)
  max_norm <- if (is.finite(mean_w) && mean_w > 0)
    max(w, na.rm = TRUE) / mean_w else Inf
  p99 <- if (any(positive)) unname(stats::quantile(w[positive], 0.99,
                                                   names = FALSE)) else NA_real_
  ess <- if (sum(w, na.rm = TRUE) > 0 && sum(w^2, na.rm = TRUE) > 0)
    sum(w, na.rm = TRUE)^2 / sum(w^2, na.rm = TRUE) else 0
  low <- if (is.null(prescribed)) NA_real_ else mean(prescribed < DIAG_LOW_PROB)
  flag <- (ess / n < DIAG_ESS_FRAC) || max_norm > DIAG_MAX_WEIGHT ||
    (!is.na(low) && low > DIAG_LOW_PROPORTION)
  list(n_adherent = sum(w > 0, na.rm = TRUE), max_weight_norm = max_norm,
       p99_weight = p99, ess = ess, ess_fraction = ess / n,
       probability_below_005 = low, diagnostic_flag = as.integer(flag))
}

weights_from_probabilities <- function(dat, probability, strategy) {
  g <- if (strategy == 'g1') 1L else 0L
  required <- !is.na(dat$a)
  prescribed <- if (g == 1L) probability else 1 - probability
  q <- prescribed[required]
  if (any(!is.finite(q) | q < -1e-12 | q > 1 + 1e-12))
    stop('invalid prescribed-action probability')
  q <- clip_probability(q)
  bad <- matrix(FALSE, nrow = nrow(dat$a), ncol = ncol(dat$a))
  bad[required] <- dat$a[required] != g
  adherent <- rowSums(bad) == 0L
  log_path <- rowSums(ifelse(required, log(clip_probability(prescribed)), 0))
  w <- ifelse(adherent, exp(-log_path), 0)
  list(w = w, prescribed = q, diagnostics = weight_diagnostics(w, q))
}

unweighted_weights <- function(dat, strategy) {
  g <- if (strategy == 'g1') 1L else 0L
  required <- !is.na(dat$a)
  bad <- matrix(FALSE, nrow = nrow(dat$a), ncol = ncol(dat$a))
  bad[required] <- dat$a[required] != g
  w <- as.numeric(rowSums(bad) == 0L)
  list(w = w, prescribed = NULL, diagnostics = weight_diagnostics(w, NULL))
}

calibration_newton <- function(y, score, w) {
  x <- cbind(1, logit(clip_probability(score)))
  theta <- c(0, 1)
  converged <- FALSE
  for (iteration in seq_len(NEWTON_MAXIT)) {
    mu <- expit(drop(x %*% theta))
    score_eq <- colSums(x * (w * (y - mu)))
    hessian <- crossprod(x, x * (w * mu * (1 - mu)))
    if (any(!is.finite(hessian))) break
    step <- try(solve(hessian, score_eq), silent = TRUE)
    if (inherits(step, 'try-error') || any(!is.finite(step))) break
    theta <- theta + step
    mu <- expit(drop(x %*% theta))
    score_eq <- colSums(x * (w * (y - mu)))
    if (max(abs(score_eq)) < NEWTON_TOL) {
      converged <- TRUE
      break
    }
  }
  mu <- expit(drop(x %*% theta))
  hessian <- crossprod(x, x * (w * mu * (1 - mu)))
  condition <- try(kappa(hessian, exact = TRUE), silent = TRUE)
  if (!converged || inherits(condition, 'try-error') || !is.finite(condition) ||
      condition > HESSIAN_KAPPA_MAX)
    return(list(fail = 'calibration-nonconvergence'))
  j <- hessian / length(y)
  inv <- try(solve(j), silent = TRUE)
  if (inherits(inv, 'try-error')) return(list(fail = 'calibration-singular'))
  psi <- x * (w * (y - mu))
  influence <- psi %*% t(inv)
  colnames(influence) <- c('cal_intercept', 'cal_slope')
  list(fail = NULL, estimate = stats::setNames(theta,
                                                c('cal_intercept', 'cal_slope')),
       influence = influence)
}

auc_estimate_and_if <- function(score, y, w) {
  case_mass <- sum(w * y)
  control_mass <- sum(w * (1 - y))
  if (!is.finite(case_mass) || !is.finite(control_mass) ||
      case_mass <= 0 || control_mass <= 0)
    return(list(fail = 'zero-case-or-control-mass'))
  o <- order(score)
  rr <- rle(score[o])
  group_sorted <- rep(seq_along(rr$lengths), rr$lengths)
  group <- integer(length(score))
  group[o] <- group_sorted
  ## Same ordering requirement as `weighted_auc_value`, and the same reason.
  ## Here it also reaches the influence function, so the AUC standard error and
  ## every interval built from it moved with the row order of the replicate.
  m <- rowsum(cbind(w * y, w * (1 - y)), group)
  control_before <- c(0, head(cumsum(m[, 2L]), -1L))
  case_after <- case_mass - cumsum(m[, 1L])
  case_concordance <- (control_before + 0.5 * m[, 2L]) / control_mass
  control_concordance <- (case_after + 0.5 * m[, 1L]) / case_mass
  auc <- sum(w * y * case_concordance[group]) / case_mass
  a <- case_mass / length(y)
  b <- control_mass / length(y)
  influence <- w * y / a * (case_concordance[group] - auc) +
    w * (1 - y) / b * (control_concordance[group] - auc)
  list(fail = NULL, estimate = auc, influence = influence)
}

metric_core <- function(y, score, bin, w, strict_bins = TRUE,
                        need_influence = TRUE) {
  if (any(!is.finite(w)) || sum(w) <= 0)
    return(list(fail = 'nonfinite-weight'))
  if (sum(w * y) <= 0 || sum(w * (1 - y)) <= 0)
    return(list(fail = 'zero-case-or-control-mass'))

  cal <- calibration_newton(y, score, w)
  if (!is.null(cal$fail)) return(list(fail = cal$fail))
  auc <- auc_estimate_and_if(score, y, w)
  if (!is.null(auc$fail)) return(list(fail = auc$fail))

  estimates <- cal$estimate
  influence <- if (need_influence) cal$influence else NULL
  nonempty <- integer()
  empty <- character()
  for (k in 1:10) {
    wk <- w * (bin == k)
    metric <- sprintf('cal_bin_%02d', k)
    if (sum(wk) <= 0) {
      estimates[metric] <- NA_real_
      empty <- c(empty, metric)
      if (need_influence) {
        ## setNames(vector, metric) names the ELEMENTS of a length-n vector, not
        ## the column, so the metric names never reached colnames(influence) and
        ## the later lookup influence[, keep] was out of bounds. Every replicate
        ## in the study failed there. Name the column after binding it.
        influence <- cbind(influence, rep(NA_real_, length(y)))
        colnames(influence)[ncol(influence)] <- metric
      }
    } else {
      m <- sum(wk * y) / sum(wk)
      estimates[metric] <- m
      nonempty <- c(nonempty, k)
      if (need_influence) {
        z <- wk * (y - m) / mean(wk)
        influence <- cbind(influence, as.vector(z))
        colnames(influence)[ncol(influence)] <- metric
      }
    }
  }
  if ((strict_bins && length(empty)) || length(nonempty) < 2L)
    return(list(fail = 'insufficient-calibration-bins'))

  brier_value <- (y - score)^2
  brier <- sum(w * brier_value) / sum(w)
  risk <- sum(w * y) / sum(w)
  estimates['brier'] <- brier
  estimates['auc'] <- auc$estimate
  estimates['risk'] <- risk
  if (need_influence) {
    influence <- cbind(
      influence,
      brier = w * (brier_value - brier) / mean(w),
      auc = auc$influence,
      risk = w * (y - risk) / mean(w)
    )
  }
  list(fail = NULL, estimate = estimates, influence = influence,
       empty = empty)
}

base_metric_specs <- function() {
  out <- list()
  for (g in STRATEGIES) for (sk in SCORES) {
    metrics <- c('cal_intercept', 'cal_slope', sprintf('cal_bin_%02d', 1:10),
                 'brier', 'auc')
    if (sk == 'oracle') metrics <- c(metrics, 'risk')
    out[[length(out) + 1L]] <- data.frame(
      strategy = g, score = sk, metric = metrics,
      bin = ifelse(grepl('^cal_bin_', metrics),
                   as.integer(sub('cal_bin_', '', metrics)), NA_integer_),
      stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

method_template <- function(method) {
  base <- base_metric_specs()
  contrast <- rbind(
    expand.grid(strategy = 'g1-g0', score = SCORES,
                metric = c('brier', 'auc'), stringsAsFactors = FALSE),
    data.frame(strategy = 'g1-g0', score = 'oracle', metric = 'risk',
               stringsAsFactors = FALSE)
  )
  contrast$bin <- NA_integer_
  out <- rbind(base, contrast[, names(base)])
  out$method <- method
  out[, c('method', 'strategy', 'score', 'metric', 'bin')]
}

row_key <- function(strategy, score, metric) paste(strategy, score, metric, sep = '|')

compute_base_metrics <- function(dat, scores, cuts, weights,
                                 strict_bins = TRUE, need_influence = TRUE) {
  estimate <- numeric()
  influence <- matrix(numeric(), nrow = length(dat$y), ncol = 0L)
  empty <- character()
  for (g in STRATEGIES) for (sk in SCORES) {
    r <- scores[[g]][[sk]]
    cp <- cuts$value[cuts$strategy == g & cuts$score == sk]
    cp <- cp[order(cuts$cut[cuts$strategy == g & cuts$score == sk])]
    bin <- assign_bins(r, cp)
    core <- metric_core(dat$y, r, bin, weights[[g]]$w,
                        strict_bins = strict_bins,
                        need_influence = need_influence)
    if (!is.null(core$fail)) return(list(fail = core$fail))
    keep <- names(core$estimate)
    if (sk != 'oracle') keep <- setdiff(keep, 'risk')
    keys <- row_key(g, sk, keep)
    z <- core$estimate[keep]
    names(z) <- keys
    estimate <- c(estimate, z)
    if (need_influence) {
      block <- core$influence[, keep, drop = FALSE]
      colnames(block) <- keys
      influence <- cbind(influence, block)
    }
    if (length(core$empty)) empty <- c(empty, row_key(g, sk, core$empty))
  }
  list(fail = NULL, estimate = estimate, influence = influence, empty = empty)
}

blank_method <- function(method, reason) {
  out <- method_template(method)
  out$est <- NA_real_
  out$se <- NA_real_
  out$lo <- NA_real_
  out$hi <- NA_real_
  out$n_adherent <- NA_real_
  out$n_events_adherent <- NA_real_
  out$max_weight_norm <- NA_real_
  out$p99_weight <- NA_real_
  out$ess <- NA_real_
  out$ess_fraction <- NA_real_
  out$probability_below_005 <- NA_real_
  out$diagnostic_flag <- NA_integer_
  out$fail <- reason
  out
}

apply_diagnostics <- function(out, weights, dat) {
  for (g in STRATEGIES) {
    take <- out$strategy == g
    d <- weights[[g]]$diagnostics
    out$n_adherent[take] <- d$n_adherent
    out$n_events_adherent[take] <- sum(dat$y[weights[[g]]$w > 0])
    out$max_weight_norm[take] <- d$max_weight_norm
    out$p99_weight[take] <- d$p99_weight
    out$ess[take] <- d$ess
    out$ess_fraction[take] <- d$ess_fraction
    out$probability_below_005[take] <- d$probability_below_005
    out$diagnostic_flag[take] <- d$diagnostic_flag
  }
  out
}

wald_interval <- function(est, se, metric, contrast = FALSE) {
  if (!is.finite(est) || !is.finite(se)) return(c(NA_real_, NA_real_))
  probability_metric <- grepl('^cal_bin_', metric) ||
    metric %in% c('brier', 'auc', 'risk')
  if (probability_metric && !contrast) {
    p <- clip_probability(est, 1e-8)
    s <- se / (p * (1 - p))
    return(expit(logit(p) + c(-1, 1) * MC_Z * s))
  }
  est + c(-1, 1) * MC_Z * se
}

finalize_method <- function(method, comp, influence, weights, dat) {
  out <- method_template(method)
  out$est <- out$se <- out$lo <- out$hi <- NA_real_
  out$n_adherent <- out$n_events_adherent <- NA_real_
  out$max_weight_norm <- out$p99_weight <- out$ess <- NA_real_
  out$ess_fraction <- out$probability_below_005 <- NA_real_
  out$diagnostic_flag <- NA_integer_
  out$fail <- NA_character_

  centered <- influence
  finite_col <- apply(centered, 2L, function(z) all(is.finite(z)))
  centered[, finite_col] <- sweep(centered[, finite_col, drop = FALSE], 2L,
                                  colMeans(centered[, finite_col, drop = FALSE]), '-')

  base <- out$strategy != 'g1-g0'
  for (i in which(base)) {
    key <- row_key(out$strategy[i], out$score[i], out$metric[i])
    j <- match(key, names(comp$estimate))
    if (is.na(j) || !is.finite(comp$estimate[j]) ||
        !all(is.finite(centered[, j]))) {
      out$fail[i] <- if (key %in% comp$empty) 'empty-bin' else 'no-estimate'
      next
    }
    out$est[i] <- comp$estimate[j]
    out$se[i] <- sqrt(sum(centered[, j]^2)) / nrow(centered)
    ci <- wald_interval(out$est[i], out$se[i], out$metric[i])
    out$lo[i] <- ci[1L]
    out$hi[i] <- ci[2L]
  }

  for (i in which(!base)) {
    k1 <- row_key('g1', out$score[i], out$metric[i])
    k0 <- row_key('g0', out$score[i], out$metric[i])
    j1 <- match(k1, names(comp$estimate))
    j0 <- match(k0, names(comp$estimate))
    if (anyNA(c(j1, j0)) || any(!is.finite(c(comp$estimate[j1], comp$estimate[j0])))) {
      out$fail[i] <- 'no-estimate'
      next
    }
    z <- centered[, j1] - centered[, j0]
    if (any(!is.finite(z))) {
      out$fail[i] <- 'nonfinite-covariance'
      next
    }
    out$est[i] <- comp$estimate[j1] - comp$estimate[j0]
    out$se[i] <- sqrt(sum(z^2)) / length(z)
    ci <- wald_interval(out$est[i], out$se[i], out$metric[i], contrast = TRUE)
    out$lo[i] <- ci[1L]
    out$hi[i] <- ci[2L]
  }

  out <- apply_diagnostics(out, weights, dat)
  bad <- !is.finite(out$est) & is.na(out$fail)
  out$fail[bad] <- 'no-estimate'
  out
}

estimate_known_method <- function(dat, scores, cuts, weights, method,
                                  strict_bins = TRUE) {
  comp <- compute_base_metrics(dat, scores, cuts, weights,
                               strict_bins = strict_bins, need_influence = TRUE)
  if (!is.null(comp$fail))
    return(apply_diagnostics(blank_method(method, comp$fail), weights, dat))
  finite <- apply(comp$influence, 2L, function(z) all(is.finite(z)))
  if (strict_bins && !all(finite))
    return(apply_diagnostics(blank_method(method, 'nonfinite-covariance'),
                             weights, dat))
  v <- crossprod(comp$influence[, finite, drop = FALSE]) / length(dat$y)^2
  if (any(!is.finite(v)))
    return(apply_diagnostics(blank_method(method, 'nonfinite-covariance'),
                             weights, dat))
  finalize_method(method, comp, comp$influence, weights, dat)
}

fit_reduced_models <- function(dat) {
  baseline <- data.frame(A = dat$a[, 1L], X1 = dat$x1, X2 = dat$x2,
                         L0 = dat$l0)
  fit0 <- suppressWarnings(stats::glm(
    A ~ splines::ns(X1, df = SPLINE_DF_X1) * X2 * L0,
    family = stats::binomial(), data = baseline,
    control = stats::glm.control(epsilon = 1e-8, maxit = 50), x = TRUE,
    y = TRUE, model = FALSE
  ))

  ij <- which(!is.na(dat$a[, -1L, drop = FALSE]), arr.ind = TRUE)
  if (!nrow(ij)) return(list(fail = 'no-follow-up-treatment-data'))
  id <- ij[, 1L]
  tt <- ij[, 2L] + 1L
  follow <- data.frame(
    id = id, A = dat$a[cbind(id, tt)], month = tt - 1L,
    X1 = dat$x1[id], X2 = dat$x2[id], L = dat$l[cbind(id, tt)],
    Aprev = dat$a[cbind(id, tt - 1L)]
  )
  ## These are the prespecified sieve interactions. Both fitted and exact
  ## reduced-history comparators condition on X1, X2, current L, previous A,
  ## survival, and month, with no earlier measured history.
  fit1 <- suppressWarnings(stats::glm(
    A ~ splines::ns(month, df = SPLINE_DF_MONTH) +
      splines::ns(X1, df = SPLINE_DF_X1) + X2 + L + Aprev +
      splines::ns(month, df = SPLINE_DF_MONTH):Aprev +
      splines::ns(month, df = SPLINE_DF_MONTH):L +
      splines::ns(X1, df = SPLINE_DF_X1):X2 +
      splines::ns(X1, df = SPLINE_DF_X1):L + X2:L + X2:Aprev + L:Aprev,
    family = stats::binomial(), data = follow,
    control = stats::glm.control(epsilon = 1e-8, maxit = 50), x = TRUE,
    y = TRUE, model = FALSE
  ))

  beta0 <- stats::coef(fit0)
  beta1 <- stats::coef(fit1)
  if (!isTRUE(fit0$converged) || !isTRUE(fit1$converged))
    return(list(fail = 'treatment-model-nonconvergence'))
  if (any(!is.finite(c(beta0, beta1))) || any(abs(c(beta0, beta1)) > 20))
    return(list(fail = 'invalid-treatment-model-coefficient'))

  list(fail = NULL, fit0 = fit0, fit1 = fit1, beta0 = beta0, beta1 = beta1,
       x0 = fit0$x, x1 = fit1$x, y0 = fit0$y, y1 = fit1$y,
       follow_id = follow$id, follow_month = tt)
}

fitted_probability_matrix <- function(dat, fit, beta0 = fit$beta0,
                                      beta1 = fit$beta1) {
  p <- matrix(NA_real_, nrow = length(dat$y), ncol = N_MONTHS)
  p[, 1L] <- expit(drop(fit$x0 %*% beta0))
  p[cbind(fit$follow_id, fit$follow_month)] <- expit(drop(fit$x1 %*% beta1))
  p
}

nuisance_influence <- function(dat, fit) {
  n <- length(dat$y)
  p0 <- expit(drop(fit$x0 %*% fit$beta0))
  p1 <- expit(drop(fit$x1 %*% fit$beta1))
  s0 <- fit$x0 * (fit$y0 - p0)
  s1row <- fit$x1 * (fit$y1 - p1)
  aggregate1 <- matrix(0, nrow = n, ncol = ncol(fit$x1))
  tmp <- rowsum(s1row, fit$follow_id, reorder = FALSE)
  aggregate1[as.integer(rownames(tmp)), ] <- tmp
  score <- cbind(s0, aggregate1)
  score <- sweep(score, 2L, colMeans(score), '-')

  j0 <- crossprod(fit$x0, fit$x0 * (p0 * (1 - p0))) / n
  j1 <- crossprod(fit$x1, fit$x1 * (p1 * (1 - p1))) / n
  j <- matrix(0, nrow = ncol(j0) + ncol(j1), ncol = ncol(j0) + ncol(j1))
  j[seq_len(ncol(j0)), seq_len(ncol(j0))] <- j0
  q <- ncol(j0) + seq_len(ncol(j1))
  j[q, q] <- j1
  ev <- eigen((j + t(j)) / 2, symmetric = TRUE, only.values = TRUE)$values
  if (max(ev) <= 0 || any(ev < SINGULAR_RATIO * max(ev)))
    return(list(fail = 'singular-treatment-score'))
  inv <- try(solve(j), silent = TRUE)
  if (inherits(inv, 'try-error')) return(list(fail = 'singular-treatment-score'))
  list(fail = NULL, influence = score %*% t(inv), information = j)
}

estimate_fitted_method <- function(dat, scores, cuts) {
  fit <- tryCatch(fit_reduced_models(dat), error = function(e)
    list(fail = 'treatment-model-error'))
  if (!is.null(fit$fail)) return(blank_method('fitted_reduced', fit$fail))
  p <- fitted_probability_matrix(dat, fit)
  weights <- list(
    g0 = weights_from_probabilities(dat, p, 'g0'),
    g1 = weights_from_probabilities(dat, p, 'g1')
  )
  ## Same registered rule as the other methods; see safe_known.
  comp <- compute_base_metrics(dat, scores, cuts, weights,
                               strict_bins = FALSE, need_influence = TRUE)
  if (!is.null(comp$fail))
    return(apply_diagnostics(blank_method('fitted_reduced', comp$fail), weights, dat))
  nuisance <- nuisance_influence(dat, fit)
  if (!is.null(nuisance$fail))
    return(apply_diagnostics(blank_method('fitted_reduced', nuisance$fail), weights, dat))

  beta <- c(fit$beta0, fit$beta1)
  p0n <- length(fit$beta0)
  derivative <- matrix(NA_real_, nrow = length(comp$estimate), ncol = length(beta),
                       dimnames = list(names(comp$estimate), names(beta)))

  ## The profiled form below is algebraically the metric block of the full
  ## centered finite-difference Jacobian. Every coefficient uses the protocol's
  ## symmetric step and both strategies are recomputed on the same records.
  for (j in seq_along(beta)) {
    h <- FINITE_DIFF_SCALE * max(1, abs(beta[j]))
    plus <- beta
    minus <- beta
    plus[j] <- plus[j] + h
    minus[j] <- minus[j] - h
    pp <- fitted_probability_matrix(dat, fit, plus[seq_len(p0n)], plus[-seq_len(p0n)])
    pm <- fitted_probability_matrix(dat, fit, minus[seq_len(p0n)], minus[-seq_len(p0n)])
    wp <- list(g0 = weights_from_probabilities(dat, pp, 'g0'),
               g1 = weights_from_probabilities(dat, pp, 'g1'))
    wm <- list(g0 = weights_from_probabilities(dat, pm, 'g0'),
               g1 = weights_from_probabilities(dat, pm, 'g1'))
    ## The Jacobian must not be stricter than the point estimate it differentiates.
    ep <- compute_base_metrics(dat, scores, cuts, wp, FALSE, FALSE)
    em <- compute_base_metrics(dat, scores, cuts, wm, FALSE, FALSE)
    if (!is.null(ep$fail) || !is.null(em$fail))
      return(apply_diagnostics(blank_method('fitted_reduced',
                                             'finite-difference-failure'), weights, dat))
    derivative[, j] <- (ep$estimate[names(comp$estimate)] -
                          em$estimate[names(comp$estimate)]) / (2 * h)
  }
  if (any(!is.finite(derivative)))
    return(apply_diagnostics(blank_method('fitted_reduced',
                                           'finite-difference-failure'), weights, dat))

  total_if <- comp$influence + nuisance$influence %*% t(derivative)
  ## This gate exists to notice a degenerate estimating-function system. It was
  ## rejecting every replicate in every scenario, so the method never produced a
  ## single estimate in the whole study, for two reasons that are both artifacts
  ## rather than degeneracy.
  ##
  ## First, the exclusion list holds one column per distinct quantity, and it
  ## missed two. The miscalibrated score is expit(-0.35 + 0.75 logit(p)), so its
  ## weak-calibration slope is exactly 4/3 of the oracle slope and its intercept
  ## is the oracle intercept plus 7/15 of the oracle slope. Those two columns per
  ## strategy are affine functions of columns already in the stack, which came
  ## out of the data as R-squared of 1.0000000000 and a rank of 93 out of 97.
  ## The list already drops the miscalibrated calibration bins and AUC for the
  ## same reason; these are redundant by an affine map rather than by equality,
  ## which is why they were missed.
  unique_metric <- !grepl('[|]miscalibrated[|]cal_bin_', colnames(total_if)) &
    !grepl('[|]miscalibrated[|]auc$', colnames(total_if)) &
    !grepl('[|]miscalibrated[|]cal_(intercept|slope)$', colnames(total_if))
  stack <- cbind(nuisance$influence, total_if[, unique_metric, drop = FALSE])
  stack <- sweep(stack, 2L, colMeans(stack), '-')
  covariance <- crossprod(stack) / nrow(stack)^2
  covariance <- (covariance + t(covariance)) / 2
  ## Second, an eigenvalue relative to the largest is not scale free, and these
  ## columns are calibration slopes beside bin risks beside an AUC: their
  ## standard deviations span six hundredfold, and eigenvalue ratios move with
  ## the square of that. On the covariance scale a full-rank stack still reports
  ## 3.8e-12 against the 1e-10 threshold; the same stack on the correlation
  ## scale reports 1.3e-07 and is comfortably clear. The threshold is a
  ## statement about singularity, so it is applied where it means that. Nothing
  ## downstream uses this matrix: it is built for this test and discarded.
  scale <- sqrt(diag(covariance))
  correlation <- if (all(is.finite(scale)) && all(scale > 0))
    covariance / outer(scale, scale) else covariance
  ev <- eigen((correlation + t(correlation)) / 2,
              symmetric = TRUE, only.values = TRUE)$values
  if (any(!is.finite(ev)) || max(ev) <= 0 ||
      any(ev < SINGULAR_RATIO * max(ev)))
    return(apply_diagnostics(blank_method('fitted_reduced',
                                           'singular-stacked-covariance'), weights, dat))

  finalize_method('fitted_reduced', comp, total_if, weights, dat)
}

estimate_all <- function(dat, scen, cuts) {
  scores <- make_scores(dat, scen)
  ## `strict` deletes a whole replicate when any one of the ten calibration bins
  ## is empty. The protocol's registered condition is different and much weaker:
  ## a method fails on "fewer than two nonempty calibration bins", which
  ## `metric_core` enforces separately and which survives this default. Nothing
  ## in the protocol asks for the stricter rule, and `performance/secondary[1]`
  ## asks for the Brier score, AUC and marginal risk as outputs; none of the
  ## three uses bins at all.
  ##
  ## The cost was half the design. Support is a designed factor and in the
  ## twelve stressed-support scenarios a population decile is often empty, so
  ## the three weighted methods returned nothing on 94.5 percent of replicates
  ## while `unweighted`, the only caller that passed FALSE, returned estimates
  ## on 91 percent of the same replicates. A study comparing these methods was
  ## holding them to different convergence rules, in the direction that deletes
  ## the oracle and keeps the confounded comparator.
  ##
  ## On stressed scenario 22 the registered rule returns 57 to 61 of 63 metrics
  ## where this one returned 0, including all 23 metrics that do not use bins,
  ## and reports the 2 to 6 genuinely empty bins as `empty-bin`, which is what
  ## the per-bin machinery in `metric_core` and `estimate_known_method` was
  ## written to do and could never reach.
  safe_known <- function(method, probability, strict = FALSE) {
    tryCatch({
      weights <- if (is.null(probability)) {
        list(g0 = unweighted_weights(dat, 'g0'),
             g1 = unweighted_weights(dat, 'g1'))
      } else {
        list(g0 = weights_from_probabilities(dat, probability, 'g0'),
             g1 = weights_from_probabilities(dat, probability, 'g1'))
      }
      estimate_known_method(dat, scores, cuts, weights, method, strict)
    }, error = function(e) blank_method(method, paste0(method, '-error')))
  }

  full <- tryCatch(full_history_probabilities(dat, scen), error = function(e) NULL)
  complete <- tryCatch(complete_history_probabilities(dat, scen),
                       error = function(e) NULL)
  reduced <- tryCatch(reduced_history_probabilities(dat, scen),
                      error = function(e) NULL)

  out <- list(
    if (is.null(full)) {
      blank_method('full_history', 'probability-error')
    } else safe_known('full_history', full),
    if (is.null(complete)) {
      blank_method('exact_complete', 'probability-error')
    } else safe_known('exact_complete', complete),
    if (is.null(reduced)) {
      blank_method('exact_reduced', 'probability-error')
    } else safe_known('exact_reduced', reduced),
    tryCatch(estimate_fitted_method(dat, scores, cuts),
             error = function(e) blank_method('fitted_reduced', 'fitted-error')),
    safe_known('unweighted', NULL, strict = FALSE)
  )
  do.call(rbind, out)
}

point_rows <- function(method, comp) {
  out <- method_template(method)
  out$est <- NA_real_
  for (i in which(out$strategy != 'g1-g0')) {
    key <- row_key(out$strategy[i], out$score[i], out$metric[i])
    out$est[i] <- comp$estimate[key]
  }
  for (i in which(out$strategy == 'g1-g0')) {
    k1 <- row_key('g1', out$score[i], out$metric[i])
    k0 <- row_key('g0', out$score[i], out$metric[i])
    out$est[i] <- comp$estimate[k1] - comp$estimate[k0]
  }
  out
}

## Point-only analysis is used by the full subject bootstrap. It refits both
## treatment models but avoids recursively computing a sandwich inside each
## bootstrap resample.
point_estimates_all <- function(dat, scen, cuts) {
  scores <- make_scores(dat, scen)
  probabilities <- list(
    full_history = full_history_probabilities(dat, scen),
    exact_complete = complete_history_probabilities(dat, scen),
    exact_reduced = reduced_history_probabilities(dat, scen)
  )
  out <- list()
  for (method in names(probabilities)) {
    p <- probabilities[[method]]
    w <- list(g0 = weights_from_probabilities(dat, p, 'g0'),
              g1 = weights_from_probabilities(dat, p, 'g1'))
    comp <- compute_base_metrics(dat, scores, cuts, w, TRUE, FALSE)
    out[[length(out) + 1L]] <- if (is.null(comp$fail)) point_rows(method, comp)
      else transform(method_template(method), est = NA_real_)
  }
  fit <- fit_reduced_models(dat)
  if (is.null(fit$fail)) {
    p <- fitted_probability_matrix(dat, fit)
    w <- list(g0 = weights_from_probabilities(dat, p, 'g0'),
              g1 = weights_from_probabilities(dat, p, 'g1'))
    comp <- compute_base_metrics(dat, scores, cuts, w, TRUE, FALSE)
    out[[length(out) + 1L]] <- if (is.null(comp$fail))
      point_rows('fitted_reduced', comp) else
        transform(method_template('fitted_reduced'), est = NA_real_)
  } else {
    out[[length(out) + 1L]] <- transform(method_template('fitted_reduced'),
                                         est = NA_real_)
  }
  w <- list(g0 = unweighted_weights(dat, 'g0'),
            g1 = unweighted_weights(dat, 'g1'))
  comp <- compute_base_metrics(dat, scores, cuts, w, FALSE, FALSE)
  out[[length(out) + 1L]] <- if (is.null(comp$fail))
    point_rows('unweighted', comp) else
      transform(method_template('unweighted'), est = NA_real_)
  do.call(rbind, out)
}
