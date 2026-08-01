## GMT-04 benchmark: the three named point implementations and IPTW comparator.

`%||%` <- function(x, y) if (is.null(x)) y else x

finite_max <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) max(x) else NA_real_
}

finite_min <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) min(x) else NA_real_
}

result_shell <- function() {
  list(
    risk0 = NA_real_, risk1 = NA_real_, est = NA_real_, var = NA_real_,
    se = NA_real_, lo = NA_real_, hi = NA_real_, output_valid = FALSE,
    fail = NA_character_, software_error = NA_character_,
    rank_deficient = NA, max_coef = NA_real_, condition_number = NA_real_,
    clip_rate = NA_real_, max_weight = NA_real_, ess_min = NA_real_,
    sparse_min = NA_real_, mass_error = NA_real_, gradient_ok = NA,
    clever_max = NA_real_, zero_ic_variance = NA,
    convergence_warning = NA, bootstrap_se = NA_real_,
    diagnostic_note = NA_character_
  )
}

finish_result <- function(x = list()) {
  z <- utils::modifyList(result_shell(), x)
  if (!is.na(z$software_error)) {
    z$fail <- paste0('software-error: ', gsub('[\r\n]+', ' ', z$software_error))
    return(z)
  }
  valid <- all(is.finite(c(z$risk0, z$risk1, z$est, z$var))) &&
    z$risk0 >= 0 && z$risk0 <= 1 && z$risk1 >= 0 && z$risk1 <= 1 &&
    z$est >= -1 && z$est <= 1 && z$var >= 0
  z$output_valid <- valid
  if (valid) {
    z$se <- sqrt(z$var)
    z$lo <- z$est - 1.96 * z$se
    z$hi <- z$est + 1.96 * z$se
    z$fail <- NA_character_
  } else {
    z$fail <- 'invalid-output'
  }
  z
}

fit_binary <- function(formula, data, bound = FALSE) {
  warnings <- character()
  fit <- tryCatch(
    withCallingHandlers(
      stats::glm(formula, family = stats::binomial(), data = data,
                 na.action = stats::na.omit),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart('muffleWarning')
      }
    ),
    error = function(e) e
  )
  if (inherits(fit, 'error')) return(list(error = conditionMessage(fit)))
  X <- stats::model.matrix(fit)
  beta <- stats::coef(fit)
  active <- is.finite(beta)
  p_raw <- fit$fitted.values
  p <- if (bound) bound_probability(p_raw) else p_raw
  info <- if (any(active)) {
    crossprod(X[, active, drop = FALSE] * sqrt(p * (1 - p)))
  } else matrix(NA_real_, 1, 1)
  condition <- tryCatch(kappa(info), error = function(e) Inf)
  list(
    fit = fit, X = X[, active, drop = FALSE], beta = beta[active],
    p_raw = p_raw, p = p, active = active,
    rank_deficient = fit$rank < ncol(X) || any(!active),
    max_coef = finite_max(abs(beta[active])),
    condition = condition,
    converged = isTRUE(fit$converged), warnings = warnings,
    clip_rate = if (bound) mean(p_raw < PROB_BOUNDS[1] |
                                 p_raw > PROB_BOUNDS[2]) else NA_real_,
    error = NULL
  )
}

predict_binary <- function(fitted_object, newdata, beta = fitted_object$beta) {
  tt <- stats::delete.response(stats::terms(fitted_object$fit))
  X <- stats::model.matrix(tt, newdata)
  X <- X[, names(beta), drop = FALSE]
  expit(drop(X %*% beta))
}

cluster_sum <- function(values, id, n) {
  values <- as.matrix(values)
  out <- matrix(0, nrow = n, ncol = ncol(values))
  z <- rowsum(values, id, reorder = FALSE)
  out[as.integer(rownames(z)), ] <- z
  colnames(out) <- colnames(values)
  out
}

safe_inverse <- function(x) {
  tryCatch(solve(x), error = function(e) NULL)
}

empirical_sandwich <- function(scores, derivative) {
  inv <- safe_inverse(derivative)
  if (is.null(inv)) return(NULL)
  n <- nrow(scores)
  centered <- sweep(scores, 2, colMeans(scores), '-')
  B <- crossprod(centered) / n
  inv %*% B %*% t(inv) / n
}

iptw_components <- function(long, observed_u, inference = TRUE) {
  treatment_rhs <- paste(c('kfac', 'W1', 'W2', if (observed_u) 'U',
                           'L', 'Aprev'), collapse = ' + ')
  retention_rhs <- paste(c('kfac', 'W1', 'W2', if (observed_u) 'U',
                           'L', 'A'), collapse = ' + ')
  fit_a <- fit_binary(stats::as.formula(paste('A ~', treatment_rhs)), long,
                      bound = TRUE)
  fit_r <- fit_binary(stats::as.formula(paste('retained ~', retention_rhs)),
                      long, bound = TRUE)
  if (!is.null(fit_a$error)) stop(fit_a$error)
  if (!is.null(fit_r$error)) stop(fit_r$error)

  n <- max(long$id)
  pa <- ncol(fit_a$X); pr <- ncol(fit_r$X)
  p_a_obs <- ifelse(long$A == 1L, fit_a$p, 1 - fit_a$p)
  p_r_obs <- ifelse(long$retained == 1L, fit_r$p, 1 - fit_r$p)
  score_a_increment <- fit_a$X * (long$A - fit_a$p)
  score_r_increment <- fit_r$X * (long$retained - fit_r$p)

  clone_rows <- list(); clone_da <- list(); clone_dr <- list(); at <- 0L
  for (regime in 0:1) {
    adherent <- rep(TRUE, n)
    cumulative_log_weight <- numeric(n)
    cumulative_da <- matrix(0, nrow = n, ncol = pa)
    cumulative_dr <- matrix(0, nrow = n, ncol = pr)
    for (k in VISITS) {
      idx <- which(long$k == k)
      id <- long$id[idx]
      adherent[id] <- adherent[id] & long$A[idx] == regime
      cumulative_log_weight[id] <- cumulative_log_weight[id] -
        log(p_a_obs[idx]) - log(p_r_obs[idx])
      cumulative_da[id, ] <- cumulative_da[id, , drop = FALSE] -
        score_a_increment[idx, , drop = FALSE]
      cumulative_dr[id, ] <- cumulative_dr[id, , drop = FALSE] -
        score_r_increment[idx, , drop = FALSE]
      keep <- adherent[id] & long$retained[idx] == 1L
      if (any(keep)) {
        at <- at + 1L
        ids <- id[keep]
        clone_rows[[at]] <- data.frame(
          id = ids, cell = regime * N_VISITS + k + 1L,
          event = long$event[idx[keep]],
          raw_weight = exp(cumulative_log_weight[ids]),
          stringsAsFactors = FALSE
        )
        clone_da[[at]] <- cumulative_da[ids, , drop = FALSE]
        clone_dr[[at]] <- cumulative_dr[ids, , drop = FALSE]
      }
    }
  }
  clone <- do.call(rbind, clone_rows)
  dlog_a <- do.call(rbind, clone_da)
  dlog_r <- do.call(rbind, clone_dr)
  cells <- seq_len(2L * N_VISITS)
  counts <- vapply(cells, function(z) sum(clone$cell == z), integer(1))
  if (any(counts == 0L)) stop('empty clone cell')
  mu <- vapply(cells, function(z) mean(clone$raw_weight[clone$cell == z]),
               numeric(1))
  scaled_weight <- clone$raw_weight / mu[clone$cell]
  hazard <- vapply(cells, function(z) {
    q <- clone$cell == z
    stats::weighted.mean(clone$event[q], scaled_weight[q])
  }, numeric(1))
  risk0 <- 1 - prod(1 - hazard[seq_len(N_VISITS)])
  risk1 <- 1 - prod(1 - hazard[N_VISITS + seq_len(N_VISITS)])

  base <- list(
    risk0 = risk0, risk1 = risk1, est = risk1 - risk0,
    hazard = hazard, mu = mu, clone = clone, scaled_weight = scaled_weight,
    max_weight = max(clone$raw_weight),
    ess_min = min(vapply(cells, function(z) {
      w <- clone$raw_weight[clone$cell == z]
      sum(w)^2 / sum(w^2)
    }, numeric(1))),
    sparse_min = min(counts),
    clip_rate = mean(c(fit_a$p_raw < PROB_BOUNDS[1],
                       fit_a$p_raw > PROB_BOUNDS[2],
                       fit_r$p_raw < PROB_BOUNDS[1],
                       fit_r$p_raw > PROB_BOUNDS[2])),
    rank_deficient = fit_a$rank_deficient || fit_r$rank_deficient,
    max_coef = finite_max(c(abs(fit_a$beta), abs(fit_r$beta),
                            abs(stats::qlogis(hazard)))),
    condition_number = finite_max(c(fit_a$condition, fit_r$condition)),
    convergence_warning = !fit_a$converged || !fit_r$converged ||
      length(fit_a$warnings) > 0L || length(fit_r$warnings) > 0L
  )
  if (!inference) return(base)

  score_a <- cluster_sum(score_a_increment, long$id, n)
  score_r <- cluster_sum(score_r_increment, long$id, n)
  score_n <- matrix(0, nrow = n, ncol = length(cells))
  score_e <- matrix(0, nrow = n, ncol = length(cells))
  score_n[cbind(clone$id, clone$cell)] <- clone$raw_weight - mu[clone$cell]
  score_e[cbind(clone$id, clone$cell)] <- scaled_weight *
    (clone$event - hazard[clone$cell])

  ia <- seq_len(pa)
  ir <- pa + seq_len(pr)
  inorm <- pa + pr + cells
  ievent <- pa + pr + length(cells) + cells
  dimension <- pa + pr + 2L * length(cells)
  derivative <- matrix(0, nrow = dimension, ncol = dimension)
  derivative[ia, ia] <- -crossprod(
    fit_a$X, fit_a$X * (fit_a$p * (1 - fit_a$p))
  ) / n
  derivative[ir, ir] <- -crossprod(
    fit_r$X, fit_r$X * (fit_r$p * (1 - fit_r$p))
  ) / n

  for (cell in cells) {
    q <- clone$cell == cell
    derivative[inorm[cell], ia] <- colSums(
      clone$raw_weight[q] * dlog_a[q, , drop = FALSE]
    ) / n
    derivative[inorm[cell], ir] <- colSums(
      clone$raw_weight[q] * dlog_r[q, , drop = FALSE]
    ) / n
    derivative[inorm[cell], inorm[cell]] <- -sum(q) / n
    residual <- clone$event[q] - hazard[cell]
    derivative[ievent[cell], ia] <- colSums(
      scaled_weight[q] * residual * dlog_a[q, , drop = FALSE]
    ) / n
    derivative[ievent[cell], ir] <- colSums(
      scaled_weight[q] * residual * dlog_r[q, , drop = FALSE]
    ) / n
    derivative[ievent[cell], inorm[cell]] <-
      -sum(clone$raw_weight[q] * residual / mu[cell]^2) / n
    derivative[ievent[cell], ievent[cell]] <-
      -sum(scaled_weight[q] * hazard[cell] * (1 - hazard[cell])) / n
  }

  scores <- cbind(score_a, score_r, score_n, score_e)
  covariance <- empirical_sandwich(scores, derivative)
  survival0 <- prod(1 - hazard[seq_len(N_VISITS)])
  survival1 <- prod(1 - hazard[N_VISITS + seq_len(N_VISITS)])
  gradient <- numeric(dimension)
  gradient[ievent[seq_len(N_VISITS)]] <- -survival0 *
    hazard[seq_len(N_VISITS)]
  gradient[ievent[N_VISITS + seq_len(N_VISITS)]] <- survival1 *
    hazard[N_VISITS + seq_len(N_VISITS)]
  variance_nuisance <- if (is.null(covariance)) NA_real_ else
    drop(t(gradient) %*% covariance %*% gradient)

  derivative_fixed <- derivative[ievent, ievent, drop = FALSE]
  covariance_fixed <- empirical_sandwich(score_e, derivative_fixed)
  gradient_fixed <- gradient[ievent]
  variance_fixed <- if (is.null(covariance_fixed)) NA_real_ else
    drop(t(gradient_fixed) %*% covariance_fixed %*% gradient_fixed)

  base$variance_nuisance <- variance_nuisance
  base$variance_fixed <- variance_fixed
  base$condition_number <- finite_max(c(
    base$condition_number,
    tryCatch(kappa(derivative), error = function(e) Inf),
    tryCatch(kappa(derivative_fixed), error = function(e) Inf)
  ))
  base
}

est_iptw <- function(long, observed_u) {
  z <- tryCatch(iptw_components(long, observed_u, inference = TRUE),
                error = function(e) e)
  if (inherits(z, 'error')) {
    bad <- finish_result(list(software_error = conditionMessage(z)))
    return(list(nuisance = bad, fixed = bad))
  }
  common <- z[c('risk0', 'risk1', 'est', 'rank_deficient', 'max_coef',
                'condition_number', 'clip_rate', 'max_weight', 'ess_min',
                'sparse_min', 'convergence_warning')]
  nuisance <- finish_result(c(common, list(
    var = z$variance_nuisance,
    diagnostic_note = 'nuisance-adjusted stacked sandwich'
  )))
  fixed <- finish_result(c(common, list(
    var = z$variance_fixed,
    diagnostic_note = 'fixed-weight historical sandwich comparator'
  )))
  list(nuisance = nuisance, fixed = fixed)
}

iptw_point_only <- function(long, observed_u) {
  z <- tryCatch(iptw_components(long, observed_u, inference = FALSE),
                error = function(e) NULL)
  if (is.null(z)) NA_real_ else z$est
}

bootstrap_iptw_se <- function(long, observed_u, B = BOOTSTRAP_REPS) {
  n <- max(long$id)
  estimates <- rep(NA_real_, B)
  dt <- data.table::as.data.table(long)
  for (b in seq_len(B)) {
    map <- data.table::data.table(old_id = sample.int(n, n, replace = TRUE),
                                  new_id = seq_len(n))
    boot <- dt[map, on = c(id = 'old_id'), allow.cartesian = TRUE, nomatch = 0L]
    boot[, id := new_id]
    boot[, new_id := NULL]
    data.table::setorder(boot, id, k)
    estimates[b] <- iptw_point_only(as.data.frame(boot), observed_u)
  }
  if (sum(is.finite(estimates)) < 2L) NA_real_ else
    stats::sd(estimates, na.rm = TRUE)
}

gformula_recursion <- function(fit_l, fit_y, beta_l, beta_y, baseline,
                               regime) {
  n <- nrow(baseline)
  mass <- cbind(as.numeric(baseline$L0 == 0L),
                as.numeric(baseline$L0 == 1L))
  risk <- numeric(n)
  max_error <- 0
  for (k in VISITS) {
    next_mass <- matrix(0, nrow = n, ncol = 2L)
    final_survival <- numeric(n)
    for (l in 0:1) {
      current <- mass[, l + 1L]
      newdata <- baseline
      newdata$kfac <- factor(k, levels = VISITS)
      newdata$L <- l
      newdata$A <- regime
      py <- predict_binary(fit_y, newdata, beta_y)
      risk <- risk + current * py
      survivor <- current * (1 - py)
      if (k < max(VISITS)) {
        pl <- predict_binary(fit_l, newdata, beta_l)
        next_mass[, 1] <- next_mass[, 1] + survivor * (1 - pl)
        next_mass[, 2] <- next_mass[, 2] + survivor * pl
      } else {
        final_survival <- final_survival + survivor
      }
    }
    if (k < max(VISITS)) {
      mass <- next_mass
      error <- max(abs(risk + rowSums(mass) - 1))
    } else {
      error <- max(abs(risk + final_survival - 1))
    }
    max_error <- max(max_error, error)
  }
  list(risk = risk, mass_error = max_error)
}

central_gradient <- function(beta, fn) {
  out <- numeric(length(beta))
  for (j in seq_along(beta)) {
    h <- 1e-5 * max(1, abs(beta[j]))
    plus <- minus <- beta
    plus[j] <- plus[j] + h
    minus[j] <- minus[j] - h
    out[j] <- (fn(plus) - fn(minus)) / (2 * h)
  }
  out
}

est_gformula <- function(generated, long, observed_u) {
  transition_data <- long[long$k < max(VISITS) & long$retained == 1L &
                            long$event == 0L & !is.na(long$Lnext), ]
  event_data <- long[long$retained == 1L & !is.na(long$event), ]
  common <- c('kfac', 'W1', 'W2', if (observed_u) 'U', 'L', 'A')
  transition_formula <- stats::as.formula(
    paste('Lnext ~', paste(common, collapse = ' + '))
  )
  event_formula <- stats::as.formula(
    paste('event ~', paste(c(common, 'A:W1'), collapse = ' + '))
  )
  fit_l <- fit_binary(transition_formula, transition_data, bound = FALSE)
  fit_y <- fit_binary(event_formula, event_data, bound = FALSE)
  if (!is.null(fit_l$error) || !is.null(fit_y$error)) {
    return(finish_result(list(software_error =
      paste(c(fit_l$error, fit_y$error), collapse = '; '))))
  }

  baseline <- data.frame(W1 = generated$W1, W2 = generated$W2,
                         U = generated$U, L0 = generated$L[, 1])
  r0 <- gformula_recursion(fit_l, fit_y, fit_l$beta, fit_y$beta,
                           baseline, 0L)
  r1 <- gformula_recursion(fit_l, fit_y, fit_l$beta, fit_y$beta,
                           baseline, 1L)
  psi0 <- mean(r0$risk); psi1 <- mean(r1$risk)

  gradient_l0 <- central_gradient(fit_l$beta, function(beta) {
    mean(gformula_recursion(fit_l, fit_y, beta, fit_y$beta,
                            baseline, 0L)$risk)
  })
  gradient_l1 <- central_gradient(fit_l$beta, function(beta) {
    mean(gformula_recursion(fit_l, fit_y, beta, fit_y$beta,
                            baseline, 1L)$risk)
  })
  gradient_y0 <- central_gradient(fit_y$beta, function(beta) {
    mean(gformula_recursion(fit_l, fit_y, fit_l$beta, beta,
                            baseline, 0L)$risk)
  })
  gradient_y1 <- central_gradient(fit_y$beta, function(beta) {
    mean(gformula_recursion(fit_l, fit_y, fit_l$beta, beta,
                            baseline, 1L)$risk)
  })
  gradient_ok <- all(is.finite(c(gradient_l0, gradient_l1,
                                 gradient_y0, gradient_y1)))

  n <- generated$n
  score_l <- cluster_sum(
    fit_l$X * (transition_data$Lnext - fit_l$p),
    transition_data$id, n
  )
  score_y <- cluster_sum(
    fit_y$X * (event_data$event - fit_y$p),
    event_data$id, n
  )
  derivative_l <- -crossprod(
    fit_l$X, fit_l$X * (fit_l$p * (1 - fit_l$p))
  ) / n
  derivative_y <- -crossprod(
    fit_y$X, fit_y$X * (fit_y$p * (1 - fit_y$p))
  ) / n
  inverse_l <- safe_inverse(derivative_l)
  inverse_y <- safe_inverse(derivative_y)
  variance <- NA_real_
  if (!is.null(inverse_l) && !is.null(inverse_y) && gradient_ok) {
    influence_l <- -score_l %*% t(inverse_l)
    influence_y <- -score_y %*% t(inverse_y)
    parameter_if <- cbind(influence_l, influence_y)
    influence0 <- r0$risk - psi0 + parameter_if %*%
      c(gradient_l0, gradient_y0)
    influence1 <- r1$risk - psi1 + parameter_if %*%
      c(gradient_l1, gradient_y1)
    influence_rd <- drop(influence1 - influence0)
    variance <- stats::var(influence_rd) / n
  }

  ## Critique fix: conclusions concern this pooled parametric implementation,
  ## not the g-formula family. The empirical-baseline influence term is retained.
  finish_result(list(
    risk0 = psi0, risk1 = psi1, est = psi1 - psi0, var = variance,
    rank_deficient = fit_l$rank_deficient || fit_y$rank_deficient,
    max_coef = finite_max(c(abs(fit_l$beta), abs(fit_y$beta))),
    condition_number = finite_max(c(
      fit_l$condition, fit_y$condition,
      tryCatch(kappa(derivative_l), error = function(e) Inf),
      tryCatch(kappa(derivative_y), error = function(e) Inf)
    )),
    sparse_min = min(table(transition_data$k), table(event_data$k)),
    mass_error = max(r0$mass_error, r1$mass_error),
    gradient_ok = gradient_ok,
    convergence_warning = !fit_l$converged || !fit_y$converged ||
      length(fit_l$warnings) > 0L || length(fit_y$warnings) > 0L,
    diagnostic_note = 'pooled main-effect longitudinal g-formula'
  ))
}

make_ltmle_spec <- function(wide, observed_u) {
  anames <- paste0('A', VISITS)
  rnames <- paste0('R', VISITS)
  ynames <- paste0('S', seq_len(N_VISITS))
  lnames <- paste0('L', 1:(N_VISITS - 1L))
  qform <- vapply(VISITS, function(k) {
    terms <- c('W1', 'W2', if (observed_u) 'U', paste0('L', k), paste0('A', k))
    paste('Q.kplus1 ~', paste(terms, collapse = ' * '))
  }, character(1))
  g_by_name <- character()
  for (k in VISITS) {
    a_terms <- c('W1', 'W2', if (observed_u) 'U', paste0('L', k),
                 if (k > 0L) paste0('A', k - 1L))
    r_terms <- c('W1', 'W2', if (observed_u) 'U', paste0('L', k), paste0('A', k))
    g_by_name[paste0('A', k)] <- paste(paste0('A', k), '~',
                                       paste(a_terms, collapse = ' + '))
    g_by_name[paste0('R', k)] <- paste(paste0('R', k), '~',
                                       paste(r_terms, collapse = ' + '))
  }
  gnodes <- sort(c(match(anames, names(wide)), match(rnames, names(wide))))
  list(
    Anodes = match(anames, names(wide)),
    Cnodes = match(rnames, names(wide)),
    Lnodes = match(lnames, names(wide)),
    Ynodes = match(ynames, names(wide)),
    Qform = unname(qform),
    gform = unname(g_by_name[names(wide)[gnodes]])
  )
}

find_named_numeric <- function(x, target, depth = 0L) {
  if (depth > 8L) return(NULL)
  if (is.numeric(x) && !is.null(names(x)) && target %in% names(x)) {
    return(as.numeric(x[[target]]))
  }
  if (is.matrix(x) && !is.null(colnames(x)) && target %in% colnames(x)) {
    return(as.numeric(x[, target]))
  }
  if (is.list(x)) {
    for (z in x) {
      hit <- find_named_numeric(z, target, depth + 1L)
      if (!is.null(hit)) return(hit)
    }
  }
  NULL
}

extract_ltmle_ic <- function(fit, n) {
  candidates <- list(fit$IC, fit$ic, fit$influence.curve)
  for (x in candidates) {
    if (is.null(x)) next
    if (is.numeric(x) && length(x) == n) return(as.numeric(x))
    if (is.matrix(x) && nrow(x) == n) {
      if (!is.null(colnames(x)) && 'tmle' %in% colnames(x))
        return(as.numeric(x[, 'tmle']))
      if (ncol(x) == 1L) return(as.numeric(x[, 1]))
    }
    if (is.list(x)) {
      hit <- find_named_numeric(x, 'tmle')
      if (!is.null(hit) && length(hit) == n) return(hit)
    }
  }
  NULL
}

collect_glms <- function(x, depth = 0L) {
  if (depth > 8L) return(list())
  if (inherits(x, 'glm')) return(list(x))
  if (!is.list(x)) return(list())
  unlist(lapply(x, collect_glms, depth = depth + 1L), recursive = FALSE)
}

ltmle_regime <- function(wide, observed_u, regime) {
  spec <- make_ltmle_spec(wide, observed_u)
  warnings <- character()
  fit <- tryCatch(
    withCallingHandlers(
      ltmle::ltmle(
        wide,
        Anodes = spec$Anodes,
        Cnodes = spec$Cnodes,
        Lnodes = spec$Lnodes,
        Ynodes = spec$Ynodes,
        abar = rep(regime, N_VISITS),
        Qform = spec$Qform,
        gform = spec$gform,
        survivalOutcome = TRUE,
        gbounds = PROB_BOUNDS,
        SL.library = 'glm'
      ),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart('muffleWarning')
      }
    ),
    error = function(e) e
  )
  if (inherits(fit, 'error')) return(list(error = conditionMessage(fit)))
  estimate <- find_named_numeric(fit$estimates, 'tmle')
  if (is.null(estimate)) estimate <- find_named_numeric(fit, 'tmle')
  if (is.null(estimate) || length(estimate) != 1L)
    return(list(error = 'ltmle TMLE estimate was not found'))
  ic <- extract_ltmle_ic(fit, nrow(wide))
  if (is.null(ic)) return(list(error = 'ltmle subject-level influence curve was not found'))

  glms <- collect_glms(fit)
  coefficients <- unlist(lapply(glms, stats::coef), use.names = FALSE)
  rank_deficient <- if (length(glms)) any(vapply(glms, function(z) {
    z$rank < length(stats::coef(z)) || any(!is.finite(stats::coef(z)))
  }, logical(1))) else NA
  conditions <- if (length(glms)) vapply(glms, function(z) {
    tryCatch(kappa(stats::crossprod(stats::model.matrix(z))),
             error = function(e) Inf)
  }, numeric(1)) else NA_real_
  cumg <- fit$cum.g %||% fit$cumG
  clever_max <- if (is.null(cumg)) NA_real_ else {
    positive <- as.numeric(cumg)[is.finite(cumg) & as.numeric(cumg) > 0]
    if (length(positive)) max(1 / positive) else NA_real_
  }
  list(
    survival = estimate,
    ic_survival = ic,
    warnings = warnings,
    rank_deficient = rank_deficient,
    max_coef = finite_max(abs(coefficients)),
    condition_number = finite_max(conditions),
    clever_max = clever_max,
    fit = fit,
    spec = spec,
    error = NULL
  )
}

est_ltmle <- function(generated, observed_u) {
  wide <- make_ltmle_wide(generated, observed_u)
  z0 <- ltmle_regime(wide, observed_u, 0L)
  z1 <- ltmle_regime(wide, observed_u, 1L)
  if (!is.null(z0$error) || !is.null(z1$error)) {
    return(finish_result(list(software_error =
      paste(c(z0$error, z1$error), collapse = '; '))))
  }
  risk0 <- 1 - z0$survival
  risk1 <- 1 - z1$survival
  ic0 <- -z0$ic_survival
  ic1 <- -z1$ic_survival
  ic_rd <- ic1 - ic0
  variance <- stats::var(ic_rd) / generated$n

  ## Critique fix: this is the formula-based implementation with its specified
  ## time-specific saturated Q regressions. It is not a family-wide comparison.
  finish_result(list(
    risk0 = risk0, risk1 = risk1, est = risk1 - risk0, var = variance,
    rank_deficient = isTRUE(z0$rank_deficient) || isTRUE(z1$rank_deficient),
    max_coef = finite_max(c(z0$max_coef, z1$max_coef)),
    condition_number = finite_max(c(z0$condition_number, z1$condition_number)),
    clever_max = finite_max(c(z0$clever_max, z1$clever_max)),
    zero_ic_variance = is.finite(variance) && variance == 0,
    convergence_warning = length(z0$warnings) > 0L || length(z1$warnings) > 0L,
    diagnostic_note = 'formula-based longitudinal TMLE with glm only'
  ))
}

sha256_file <- function(path) {
  executable <- Sys.which('shasum')
  if (!nzchar(executable)) stop('shasum is required for SHA-256 provenance')
  out <- system2(executable, c('-a', '256', shQuote(path)),
                 stdout = TRUE, stderr = TRUE)
  if (!length(out)) stop('SHA-256 calculation failed for ', path)
  strsplit(out[1], '[[:space:]]+')[[1]][1]
}

ensure_ltmle_vendor <- function(study_dir) {
  installed <- as.character(utils::packageVersion('ltmle'))
  if (installed != REQUIRED_LTMLE_VERSION) {
    stop('installed ltmle version is ', installed,
         '; required version is ', REQUIRED_LTMLE_VERSION)
  }
  vendor <- file.path(study_dir, 'vendor', 'ltmle')
  dir.create(vendor, recursive = TRUE, showWarnings = FALSE)
  archive <- file.path(vendor, paste0('ltmle_', REQUIRED_LTMLE_VERSION, '.tar.gz'))
  manual <- file.path(vendor, paste0('ltmle_', REQUIRED_LTMLE_VERSION, '.pdf'))
  if (!file.exists(archive)) {
    urls <- c(
      sprintf('https://cran.r-project.org/src/contrib/Archive/ltmle/ltmle_%s.tar.gz',
              REQUIRED_LTMLE_VERSION),
      sprintf('https://cran.r-project.org/src/contrib/ltmle_%s.tar.gz',
              REQUIRED_LTMLE_VERSION)
    )
    ok <- FALSE
    for (url in urls) {
      status <- try(utils::download.file(url, archive, mode = 'wb', quiet = TRUE),
                    silent = TRUE)
      if (!inherits(status, 'try-error') && file.exists(archive) &&
          file.info(archive)$size > 0) {
        ok <- TRUE
        break
      }
    }
    if (!ok) stop('the exact ltmle source archive could not be vendored')
  }
  check_dir <- tempfile('ltmle-source-')
  dir.create(check_dir)
  utils::untar(archive, files = 'ltmle/DESCRIPTION', exdir = check_dir)
  description <- read.dcf(file.path(check_dir, 'ltmle', 'DESCRIPTION'))
  if (description[1, 'Version'] != REQUIRED_LTMLE_VERSION)
    stop('vendored ltmle archive has the wrong version')

  if (!file.exists(manual)) {
    status <- try(utils::download.file(
      'https://cran.r-project.org/web/packages/ltmle/ltmle.pdf',
      manual, mode = 'wb', quiet = TRUE
    ), silent = TRUE)
    if (inherits(status, 'try-error') || !file.exists(manual) ||
        file.info(manual)$size == 0) {
      stop('the ltmle reference manual could not be vendored')
    }
  }
  list(
    status = TRUE,
    installed_version = installed,
    archive = normalizePath(archive),
    archive_sha256 = sha256_file(archive),
    manual = normalizePath(manual),
    manual_sha256 = sha256_file(manual)
  )
}

ltmle_contract_test <- function(generated) {
  observed <- make_ltmle_wide(generated, TRUE)
  hidden <- make_ltmle_wide(generated, FALSE)
  observed_spec <- make_ltmle_spec(observed, TRUE)
  hidden_spec <- make_ltmle_spec(hidden, FALSE)
  checks <- c(
    length(observed_spec$Qform) == N_VISITS,
    length(observed_spec$gform) == 2L * N_VISITS,
    all(grepl('U', observed_spec$Qform, fixed = TRUE)),
    !any(grepl('U', hidden_spec$Qform, fixed = TRUE)),
    identical(PROB_BOUNDS, c(0.01, 0.99))
  )
  estimate <- est_ltmle(generated, TRUE)
  checks <- c(checks, estimate$output_valid,
              is.finite(estimate$var), !is.na(estimate$convergence_warning))
  list(
    status = all(checks),
    checks = checks,
    observed_qform = observed_spec$Qform,
    observed_gform = observed_spec$gform,
    hidden_qform = hidden_spec$Qform,
    hidden_gform = hidden_spec$gform,
    bounds = PROB_BOUNDS,
    test_estimate = estimate
  )
}
