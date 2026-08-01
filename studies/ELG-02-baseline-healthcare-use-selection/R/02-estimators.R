## Study ELG-02: truth, audit screen, and causal estimators.

`%||%` <- function(a, b) if (is.null(a)) b else a

fit_probit_matrix <- function(x, y) {
  if (length(unique(y)) < 2L) {
    return(list(ok = FALSE, reason = "empty-outcome-level"))
  }
  fit <- tryCatch(
    suppressWarnings(stats::glm.fit(
      x = x, y = y, family = stats::binomial(link = "probit"),
      control = stats::glm.control(maxit = 50L)
    )),
    error = function(e) NULL
  )
  if (is.null(fit)) return(list(ok = FALSE, reason = "fit-error"))
  if (!isTRUE(fit$converged)) {
    return(list(ok = FALSE, reason = "nonconvergence"))
  }
  if (fit$rank < ncol(x)) {
    return(list(ok = FALSE, reason = "rank-deficiency"))
  }
  if (length(fit$coefficients) != ncol(x) ||
      any(!is.finite(fit$coefficients))) {
    return(list(ok = FALSE, reason = "nonfinite-coefficient"))
  }
  list(ok = TRUE, fit = fit, coef = fit$coefficients)
}

unresolved_screen <- function(reason) {
  list(
    result = "unresolved-audit", fail = reason,
    n_ha = NA_integer_, n_hy = NA_integer_, n_pairs = NA_integer_
  )
}

screen_pvalues <- function(fit, candidates) {
  sm <- tryCatch(summary(fit$fit)$coefficients, error = function(e) NULL)
  if (is.null(sm) || !all(candidates %in% rownames(sm))) return(NULL)
  se <- sm[candidates, "Std. Error"]
  est <- sm[candidates, "Estimate"]
  if (any(!is.finite(se)) || any(se <= 0) || any(!is.finite(est))) return(NULL)
  2 * stats::pnorm(-abs(est / se))
}

screen_eligibility <- function(dat, view, timestamps_available = TRUE) {
  if (!isTRUE(timestamps_available)) return(unresolved_screen("timestamps-unavailable"))
  candidates <- switch(
    view,
    full = FULL_CANDIDATES,
    reduced = REDUCED_CANDIDATES,
    stop("unknown information view: ", view)
  )

  ## Critique fix: candidates are unlabeled measured variables. The screen is
  ## not given the causal roles of P or D. In the reduced view it receives no
  ## indication that either variable exists or is relevant.
  core <- cbind(`(Intercept)` = 1, B = dat$B, X = dat$X)
  z <- as.matrix(dat[, candidates, drop = FALSE])
  x_h <- cbind(core, z)
  x_a <- cbind(core, z)
  x_y <- cbind(
    `(Intercept)` = 1, A = dat$A, B = dat$B, X = dat$X,
    `A:B` = dat$A * dat$B, z
  )

  fits <- list(
    H = fit_probit_matrix(x_h, dat$H),
    A = fit_probit_matrix(x_a, dat$A),
    Y = fit_probit_matrix(x_y, dat$Y)
  )
  if (any(!vapply(fits, function(x) isTRUE(x$ok), logical(1)))) {
    return(unresolved_screen("required-audit-model-failed"))
  }

  p_h <- screen_pvalues(fits$H, candidates)
  p_a <- screen_pvalues(fits$A, candidates)
  p_y <- screen_pvalues(fits$Y, candidates)
  if (is.null(p_h) || is.null(p_a) || is.null(p_y)) {
    return(unresolved_screen("audit-inference-failed"))
  }

  adjusted <- stats::p.adjust(c(p_h, p_a, p_y), method = "holm")
  j <- length(candidates)
  q_h <- adjusted[seq_len(j)]
  q_a <- adjusted[j + seq_len(j)]
  q_y <- adjusted[2L * j + seq_len(j)]

  ha <- candidates[q_h <= SCREEN_ALPHA & q_a <= SCREEN_ALPHA]
  hy <- candidates[q_h <= SCREEN_ALPHA & q_y <= SCREEN_ALPHA]
  n_pairs <- if (length(ha) && length(hy)) {
    sum(outer(ha, hy, FUN = "!="))
  } else 0L

  list(
    result = if (n_pairs > 0L) {
      "collider-candidate"
    } else {
      "no-observable-collider-signal"
    },
    fail = NA_character_, n_ha = length(ha), n_hy = length(hy),
    n_pairs = as.integer(n_pairs)
  )
}

make_g_matrix <- function(dat, covariates) {
  cbind(`(Intercept)` = 1, as.matrix(dat[, covariates, drop = FALSE]))
}

make_q_matrix <- function(dat, covariates, treatment = dat$A) {
  cbind(
    `(Intercept)` = 1, A = treatment,
    as.matrix(dat[, covariates, drop = FALSE]),
    `A:B` = treatment * dat$B
  )
}

failed_estimator <- function(reason, n = NA_integer_) {
  list(
    est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
    fail = reason, min_ps = NA_real_, max_weight = NA_real_,
    ess = NA_real_, n = as.integer(n)
  )
}

aipw_fit <- function(dat, g_covariates, q_covariates) {
  n <- nrow(dat)
  if (n == 0L) return(failed_estimator("empty-analysis-cohort", n))
  if (length(unique(dat$A)) < 2L) return(failed_estimator("empty-treatment-arm", n))

  tryCatch({
    x_g <- make_g_matrix(dat, g_covariates)
    x_q <- make_q_matrix(dat, q_covariates)
    x_q1 <- make_q_matrix(dat, q_covariates, rep(1, n))
    x_q0 <- make_q_matrix(dat, q_covariates, rep(0, n))

    fit_g <- fit_probit_matrix(x_g, dat$A)
    if (!isTRUE(fit_g$ok)) {
      return(failed_estimator(paste0("treatment-", fit_g$reason), n))
    }
    fit_q <- fit_probit_matrix(x_q, dat$Y)
    if (!isTRUE(fit_q$ok)) {
      return(failed_estimator(paste0("outcome-", fit_q$reason), n))
    }

    beta_g <- unname(fit_g$coef)
    beta_q <- unname(fit_q$coef)
    g <- stats::pnorm(drop(x_g %*% beta_g))
    q1 <- stats::pnorm(drop(x_q1 %*% beta_q))
    q0 <- stats::pnorm(drop(x_q0 %*% beta_q))

    phi1 <- q1 + dat$A * (dat$Y - q1) / g
    phi0 <- q0 + (1 - dat$A) * (dat$Y - q0) / (1 - g)
    psi1 <- mean(phi1)
    psi0 <- mean(phi0)
    theta <- c(beta_g, beta_q, psi1, psi0)

    estimating_equations <- function(par) {
      pg <- length(beta_g)
      pq <- length(beta_q)
      bg <- par[seq_len(pg)]
      bq <- par[pg + seq_len(pq)]
      p1 <- par[pg + pq + 1L]
      p0 <- par[pg + pq + 2L]

      eta_g <- drop(x_g %*% bg)
      mu_g <- stats::pnorm(eta_g)
      score_g <- x_g * ((dat$A - mu_g) * stats::dnorm(eta_g) /
                          (mu_g * (1 - mu_g)))

      eta_q <- drop(x_q %*% bq)
      mu_q <- stats::pnorm(eta_q)
      score_q <- x_q * ((dat$Y - mu_q) * stats::dnorm(eta_q) /
                          (mu_q * (1 - mu_q)))

      mu1 <- stats::pnorm(drop(x_q1 %*% bq))
      mu0 <- stats::pnorm(drop(x_q0 %*% bq))
      u1 <- mu1 + dat$A * (dat$Y - mu1) / mu_g - p1
      u0 <- mu0 + (1 - dat$A) * (dat$Y - mu0) / (1 - mu_g) - p0
      cbind(score_g, score_q, u1, u0)
    }

    u <- estimating_equations(theta)
    if (any(!is.finite(u)) || any(!is.finite(theta))) {
      return(failed_estimator("nonfinite-estimating-equation", n))
    }

    ## The finite-difference loop is over parameters. Every operation within a
    ## parameter evaluation is vectorized over subjects.
    p <- length(theta)
    bread <- matrix(NA_real_, p, p)
    for (k in seq_len(p)) {
      step <- 1e-6 * (1 + abs(theta[k]))
      plus <- theta
      minus <- theta
      plus[k] <- plus[k] + step
      minus[k] <- minus[k] - step
      bread[, k] <- (colMeans(estimating_equations(plus)) -
                       colMeans(estimating_equations(minus))) / (2 * step)
    }
    if (any(!is.finite(bread))) return(failed_estimator("nonfinite-bread", n))

    condition <- tryCatch(kappa(bread, exact = TRUE), error = function(e) Inf)
    if (!is.finite(condition) || condition > 1e12) {
      return(failed_estimator("ill-conditioned-bread", n))
    }
    inverse <- tryCatch(solve(bread), error = function(e) NULL)
    if (is.null(inverse)) return(failed_estimator("bread-inversion-failed", n))

    meat <- crossprod(u) / n
    vcov_theta <- inverse %*% meat %*% t(inverse) / n
    contrast <- c(rep(0, p - 2L), 1, -1)
    variance <- drop(t(contrast) %*% vcov_theta %*% contrast)
    estimate <- psi1 - psi0
    if (!is.finite(estimate) || !is.finite(variance) || variance < 0) {
      return(failed_estimator("nonfinite-estimate-or-se", n))
    }
    se <- sqrt(variance)
    if (!is.finite(se)) return(failed_estimator("nonfinite-estimate-or-se", n))

    weights <- ifelse(dat$A == 1L, 1 / g, 1 / (1 - g))
    if (any(!is.finite(weights))) return(failed_estimator("nonfinite-weight", n))

    list(
      est = estimate, se = se,
      lo = estimate - 1.96 * se, hi = estimate + 1.96 * se,
      fail = NA_character_, min_ps = min(pmin(g, 1 - g)),
      max_weight = max(weights), ess = sum(weights)^2 / sum(weights^2),
      n = n
    )
  }, error = function(e) failed_estimator("estimator-error", n))
}

## Gauss-Hermite nodes and weights for expectations under a standard normal.
gh_normal <- function(n) {
  jacobi <- matrix(0, n, n)
  off <- sqrt(seq_len(n - 1L) / 2)
  jacobi[cbind(seq_len(n - 1L), 2:n)] <- off
  jacobi[cbind(2:n, seq_len(n - 1L))] <- off
  eig <- eigen(jacobi, symmetric = TRUE)
  ord <- order(eig$values)
  list(
    nodes = sqrt(2) * eig$values[ord],
    weights = eig$vectors[1, ord]^2
  )
}

truth_core <- function(scen, n_nodes) {
  gh <- gh_normal(n_nodes)
  grid <- expand.grid(
    B = c(0, 1), ix = seq_len(n_nodes), ip = seq_len(n_nodes),
    id = seq_len(n_nodes)
  )
  B <- grid$B
  X <- gh$nodes[grid$ix]
  P <- gh$nodes[grid$ip]
  D <- gh$nodes[grid$id]
  mass <- 0.5 * gh$weights[grid$ix] * gh$weights[grid$ip] *
    gh$weights[grid$id]

  h_prob <- stats::pnorm(
    get_scenario_value(scen, "alpha_h") + 0.30 * B + 0.20 * X +
      get_scenario_value(scen, "lambda_p") * P +
      get_scenario_value(scen, "lambda_d") * D
  )
  z <- -1.50 + 0.45 * B + 0.35 * X + 0.65 * D
  delta <- -0.35 + 0.25 * B
  rd <- stats::pnorm(z + delta) - stats::pnorm(z)

  retention <- sum(mass * h_prob)
  selected_mass <- mass * h_prob
  mean_p <- sum(selected_mass * P) / retention
  mean_d <- sum(selected_mass * D) / retention
  var_p <- sum(selected_mass * (P - mean_p)^2) / retention
  var_d <- sum(selected_mass * (D - mean_d)^2) / retention
  cov_pd <- sum(selected_mass * (P - mean_p) * (D - mean_d)) / retention

  list(
    rd_h = sum(selected_mass * rd) / retention,
    rd_all = sum(mass * rd),
    retention = retention,
    cor_pd_h = cov_pd / sqrt(var_p * var_d)
  )
}

rd_all_identity <- function() {
  scale <- sqrt(1 + 0.35^2 + 0.65^2)
  values <- vapply(c(0, 1), function(B) {
    base <- -1.50 + 0.45 * B
    delta <- -0.35 + 0.25 * B
    stats::pnorm((base + delta) / scale) - stats::pnorm(base / scale)
  }, numeric(1))
  mean(values)
}

truth_decomposition <- function(scen, n_nodes) {
  gh <- gh_normal(n_nodes)
  index <- expand.grid(
    B = seq_len(2L), X = seq_len(n_nodes), D = seq_len(n_nodes)
  )
  B <- c(0, 1)[index$B]
  X <- gh$nodes[index$X]
  D <- gh$nodes[index$D]
  f_all <- 0.5 * gh$weights[index$X] * gh$weights[index$D]

  base_h <- get_scenario_value(scen, "alpha_h") + 0.30 * B + 0.20 * X +
    get_scenario_value(scen, "lambda_d") * D
  h_matrix <- outer(
    base_h,
    get_scenario_value(scen, "lambda_p") * gh$nodes,
    "+"
  )
  h_given_bxd <- drop(stats::pnorm(h_matrix) %*% gh$weights)
  f_h <- f_all * h_given_bxd
  f_h <- f_h / sum(f_h)

  z <- -1.50 + 0.45 * B + 0.35 * X + 0.65 * D
  delta <- -0.35 + 0.25 * B
  effect <- stats::pnorm(z + delta) - stats::pnorm(z)

  marginal_mass <- function(prob, variables) {
    if (!length(variables)) return(rep(sum(prob), length(prob)))
    key <- do.call(
      interaction,
      c(index[, variables, drop = FALSE], list(drop = TRUE, lex.order = TRUE))
    )
    ave(prob, key, FUN = sum)
  }
  chain_factors <- function(prob, permutation) {
    lapply(seq_along(permutation), function(k) {
      marginal_mass(prob, permutation[seq_len(k)]) /
        marginal_mass(prob, permutation[seq_len(k - 1L)])
    })
  }

  permutations <- list(
    c("B", "X", "D"), c("B", "D", "X"), c("X", "B", "D"),
    c("X", "D", "B"), c("D", "B", "X"), c("D", "X", "B")
  )
  contributions <- matrix(
    0, nrow = length(permutations), ncol = 3L,
    dimnames = list(NULL, c("B", "X", "D"))
  )

  for (i in seq_along(permutations)) {
    permutation <- permutations[[i]]
    broad_factors <- chain_factors(f_all, permutation)
    selected_factors <- chain_factors(f_h, permutation)
    current <- Reduce(`*`, broad_factors)
    current_mean <- sum(current * effect)

    for (k in seq_along(permutation)) {
      mixed <- broad_factors
      mixed[seq_len(k)] <- selected_factors[seq_len(k)]
      next_distribution <- Reduce(`*`, mixed)
      next_mean <- sum(next_distribution * effect)
      contributions[i, permutation[k]] <- next_mean - current_mean
      current_mean <- next_mean
    }
  }

  averaged <- colMeans(contributions)
  rd_all <- sum(f_all * effect)
  rd_h <- sum(f_h * effect)
  delta_target <- rd_h - rd_all
  decomposition_error <- sum(averaged) - delta_target
  if (!is.finite(decomposition_error) || abs(decomposition_error) > QUAD_TOL) {
    stop("target-shift decomposition failed its 1e-7 identity")
  }

  list(
    contribution_b = averaged[["B"]],
    contribution_x = averaged[["X"]],
    contribution_d = averaged[["D"]],
    decomposition_error = decomposition_error
  )
}

truth_for <- function(scen) {
  core30 <- truth_core(scen, 30L)
  core40 <- truth_core(scen, 40L)
  core50 <- truth_core(scen, 50L)
  err30 <- max(abs(c(
    core40$rd_h - core30$rd_h,
    core40$rd_all - core30$rd_all
  )))
  err50 <- max(abs(c(
    core40$rd_h - core50$rd_h,
    core40$rd_all - core50$rd_all
  )))

  if (err30 < QUAD_TOL && err50 < QUAD_TOL) {
    chosen <- core40
    nodes <- 40L
    convergence_error <- max(err30, err50)
    quadrature_ok <- TRUE
  } else {
    core60 <- truth_core(scen, QUAD_FALLBACK)
    chosen <- core60
    nodes <- QUAD_FALLBACK
    convergence_error <- max(abs(c(
      core60$rd_h - core50$rd_h,
      core60$rd_all - core50$rd_all
    )))
    quadrature_ok <- convergence_error < QUAD_TOL
  }

  decomposition <- truth_decomposition(scen, nodes)
  identity <- rd_all_identity()
  identity_error <- chosen$rd_all - identity

  data.frame(
    rd_h = chosen$rd_h,
    rd_all = chosen$rd_all,
    delta_target = chosen$rd_h - chosen$rd_all,
    contribution_b = decomposition$contribution_b,
    contribution_x = decomposition$contribution_x,
    contribution_d = decomposition$contribution_d,
    decomposition_error = decomposition$decomposition_error,
    retention_truth = chosen$retention,
    retention_error = chosen$retention - get_scenario_value(scen, "retention"),
    cor_pd_h_truth = chosen$cor_pd_h,
    quadrature_nodes = nodes,
    quadrature_error_30 = err30,
    quadrature_error_50 = err50,
    quadrature_convergence_error = convergence_error,
    quadrature_ok = quadrature_ok,
    rd_all_identity = identity,
    rd_all_identity_error = identity_error,
    identity_ok = abs(identity_error) < QUAD_TOL,
    stringsAsFactors = FALSE
  )
}
