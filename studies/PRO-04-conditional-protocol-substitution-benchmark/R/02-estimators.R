## Study PRO-04: estimators, diagnostics, and power selection.

failed_effect <- function(n, why) {
  list(est = NA_real_, se = NA_real_, influence = rep(NA_real_, n),
       ess_active = NA_real_, ess_control = NA_real_, low_ess = NA,
       fail = why, classification = NA_character_)
}

effective_n <- function(w) {
  if (!length(w) || sum(w^2) <= 0) return(0)
  sum(w)^2 / sum(w^2)
}

hajek_effect_from_h <- function(h_active, h_control, w) {
  n <- length(w)
  d_active <- mean(h_active)
  d_control <- mean(h_control)
  if (!is.finite(d_active) || !is.finite(d_control) ||
      d_active <= 0 || d_control <= 0) return(failed_effect(n, 'zero-denominator'))
  mu_active <- mean(h_active * w) / d_active
  mu_control <- mean(h_control * w) / d_control
  influence <- h_active * (w - mu_active) / d_active -
    h_control * (w - mu_control) / d_control
  est <- mu_active - mu_control
  se <- stats::sd(influence) / sqrt(n)
  if (!is.finite(est) || !is.finite(se)) return(failed_effect(n, 'nonfinite'))
  ess_active <- effective_n(h_active[h_active > 0])
  ess_control <- effective_n(h_control[h_control > 0])
  list(est = est, se = se, influence = influence,
       ess_active = ess_active, ess_control = ess_control,
       low_ess = min(ess_active, ess_control) < 20,
       fail = NA_character_, classification = NA_character_)
}

## Critique fix: eligibility and outcome substitutions use ideal arms 2 and 0.
## Only the strategy substitution uses operational arms 1 and 0.
operational_effect <- function(dat, h, validation_only = FALSE) {
  validation_weight <- if (validation_only) dat$V / VALIDATION_PROB else 1
  if (h$component == 'strategy') {
    selection <- dat$E
    h_active <- validation_weight * selection * (dat$A_star == 1L) / 0.50
    h_control <- validation_weight * selection * (dat$A_star == 0L) / 0.50
    return(hajek_effect_from_h(h_active, h_control, dat$Y))
  }
  selection <- if (h$component == 'eligibility') dat$E_star else dat$E
  endpoint <- if (h$component == 'outcome') dat$Y_star else dat$Y
  h_active <- validation_weight * selection * (dat$Z == 2L) / 0.40
  h_control <- validation_weight * selection * (dat$Z == 0L) / 0.50
  hajek_effect_from_h(h_active, h_control, endpoint)
}

ideal_effect <- function(dat, h, validation_only = FALSE) {
  validation_weight <- if (validation_only) dat$V / VALIDATION_PROB else 1
  pi2 <- if (h$component == 'strategy') {
    0.50 * strategy_q_prob(h, dat$X1)
  } else rep(0.40, nrow(dat))
  pi0 <- rep(0.50, nrow(dat))
  h_active <- validation_weight * dat$E * (dat$Z == 2L) / pi2
  h_control <- validation_weight * dat$E * (dat$Z == 0L) / pi0
  hajek_effect_from_h(h_active, h_control, dat$Y)
}

independent_columns <- function(x, tol = 1e-10) {
  keep <- integer()
  for (j in seq_len(ncol(x))) {
    candidate <- c(keep, j)
    rank_candidate <- qr(x[, candidate, drop = FALSE], tol = tol)$rank
    if (rank_candidate == length(candidate)) keep <- candidate
  }
  keep
}

## Five-fold cross-fitting for all four numerator and denominator contributions.
## The same reduced design matrix is fitted jointly to avoid repeated QR work.
augmented_intended_effect <- function(dat, h) {
  n <- nrow(dat)
  pi2 <- if (h$component == 'strategy') {
    0.50 * strategy_q_prob(h, dat$X1)
  } else rep(0.40, n)
  pi0 <- rep(0.50, n)
  q_values <- cbind(
    G2 = dat$E * (dat$Z == 2L) * dat$Y / pi2,
    H2 = dat$E * (dat$Z == 2L) / pi2,
    G0 = dat$E * (dat$Z == 0L) * dat$Y / pi0,
    H0 = dat$E * (dat$Z == 0L) / pi0
  )
  x <- operational_basis(dat, h$component)
  fold <- (seq_len(n) - 1L) %% 5L + 1L
  prediction <- matrix(NA_real_, nrow = n, ncol = ncol(q_values),
                       dimnames = list(NULL, colnames(q_values)))

  for (k in seq_len(5L)) {
    train <- fold != k & dat$V == 1L
    test <- fold == k
    if (sum(train) <= ncol(x) + 2L) return(failed_effect(n, 'augmentation-small-fold'))
    keep <- independent_columns(x[train, , drop = FALSE])
    if (!length(keep)) return(failed_effect(n, 'augmentation-no-columns'))
    x_train <- x[train, keep, drop = FALSE]
    fit_qr <- qr(x_train, tol = 1e-10)
    ## Prespecified redundant-column removal has already occurred. Remaining
    ## rank deficiency is therefore a declared augmentation failure.
    if (fit_qr$rank < ncol(x_train)) return(failed_effect(n, 'augmentation-rank-deficient'))
    coefficients <- qr.coef(fit_qr, q_values[train, , drop = FALSE])
    if (is.null(dim(coefficients))) coefficients <- matrix(coefficients, ncol = 1L)
    if (any(!is.finite(coefficients))) return(failed_effect(n, 'augmentation-nonfinite-fit'))
    prediction[test, ] <- x[test, keep, drop = FALSE] %*% coefficients
  }
  if (any(!is.finite(prediction))) return(failed_effect(n, 'augmentation-no-prediction'))

  pseudo <- prediction + dat$V / VALIDATION_PROB * (q_values - prediction)
  theta <- colMeans(pseudo)
  if (theta[['H2']] <= 0 || theta[['H0']] <= 0 || any(!is.finite(theta))) {
    return(failed_effect(n, 'augmentation-nonpositive-denominator'))
  }
  mu2 <- theta[['G2']] / theta[['H2']]
  mu0 <- theta[['G0']] / theta[['H0']]
  if2 <- (pseudo[, 'G2'] - mu2 * pseudo[, 'H2']) / theta[['H2']]
  if0 <- (pseudo[, 'G0'] - mu0 * pseudo[, 'H0']) / theta[['H0']]
  influence <- if2 - if0
  est <- mu2 - mu0
  se <- stats::sd(influence) / sqrt(n)
  if (!is.finite(est) || !is.finite(se)) return(failed_effect(n, 'augmentation-nonfinite'))
  comparator <- ideal_effect(dat, h, validation_only = TRUE)
  list(est = est, se = se, influence = influence,
       ess_active = comparator$ess_active, ess_control = comparator$ess_control,
       low_ess = comparator$low_ess, fail = NA_character_,
       classification = NA_character_)
}

classify_gap <- function(est, se) {
  if (!is.finite(est) || !is.finite(se)) return(NA_character_)
  lo90 <- est - 1.645 * se
  hi90 <- est + 1.645 * se
  lo95 <- est - 1.96 * se
  hi95 <- est + 1.96 * se
  if (lo90 >= -PRESERVATION_MARGIN && hi90 <= PRESERVATION_MARGIN) {
    return('preserving')
  }
  if (lo95 > DIAGNOSTIC_CHANGE_BOUNDARY || hi95 < -DIAGNOSTIC_CHANGE_BOUNDARY) {
    return('changed')
  }
  'indeterminate'
}

paired_gap <- function(operational, intended, failure_prefix) {
  n <- length(operational$influence)
  if (!is.na(operational$fail)) return(failed_effect(n, paste0(failure_prefix, ':', operational$fail)))
  if (!is.na(intended$fail)) return(failed_effect(n, paste0(failure_prefix, ':', intended$fail)))
  est <- operational$est - intended$est
  influence <- operational$influence - intended$influence
  se <- stats::sd(influence) / sqrt(n)
  if (!is.finite(est) || !is.finite(se)) return(failed_effect(n, paste0(failure_prefix, ':nonfinite')))
  list(est = est, se = se, influence = influence,
       ess_active = min(operational$ess_active, intended$ess_active),
       ess_control = min(operational$ess_control, intended$ess_control),
       low_ess = isTRUE(operational$low_ess) || isTRUE(intended$low_ess),
       fail = NA_character_, classification = classify_gap(est, se))
}

complete_case_gap <- function(dat, h) {
  paired_gap(operational_effect(dat, h, validation_only = TRUE),
             ideal_effect(dat, h, validation_only = TRUE), 'gap-cc')
}

## Critique fix: the primary gap diagnostic uses the full operational estimator
## and the augmented two-phase intended estimator. Their joint influence
## functions retain covariance from the shared full sample.
augmented_gap <- function(operational, augmented) {
  paired_gap(operational, augmented, 'gap-aug')
}

## Embedded unit tests guard the component-specific active-arm indices.
unit_test_arm_indices <- function() {
  z <- rep(c(0L, 1L, 2L), each = 4L)
  y <- c(1L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 1L, 1L, 1L, 0L)
  dat <- data.frame(
    X1 = 0L, X2 = 0, X3 = 0L, E = 1L, E_star = 1L,
    Z = z, A_star = as.integer(z > 0L), Y = y, Y_star = y, V = 1L
  )
  h_e <- list(component = 'eligibility')
  h_o <- list(component = 'outcome')
  h_s <- list(component = 'strategy')
  stopifnot(abs(operational_effect(dat, h_e)$est - 0.50) < 1e-12)
  stopifnot(abs(operational_effect(dat, h_o)$est - 0.50) < 1e-12)
  stopifnot(abs(operational_effect(dat, h_s)$est - 0.125) < 1e-12)
  invisible(TRUE)
}

## Deterministic population states used only for the pre-study power calculation.
population_states <- function(h, n_nodes) {
  base <- baseline_grid(n_nodes)
  pieces <- list()
  push <- function(d) pieces[[length(pieces) + 1L]] <<- d
  for (z in 0:2) {
    if (h$component == 'strategy') {
      q <- strategy_q_prob(h, base$X1)
      p_z_assign <- if (z == 0L) rep(0.50, nrow(base)) else
        if (z == 1L) 0.50 * (1 - q) else 0.50 * q
    } else {
      p_z_assign <- rep(c(0.50, 0.10, 0.40)[z + 1L], nrow(base))
    }
    op <- outcome_parts(base$X1, base$X2, base$X3, base$E, h$lambda)
    p_y <- op$p0 + if (z == 0L) 0 else if (z == 1L) op$d1 else op$d2
    for (y in 0:1) {
      d <- base
      d$Z <- z
      d$A_star <- as.integer(z > 0L)
      d$Y <- y
      d$w <- d$w * p_z_assign * ifelse(y == 1L, p_y, 1 - p_y)
      if (h$component == 'eligibility') {
        p_es <- ifelse(d$E == 1L, elig_sens_prob(h, d$X1),
                       1 - elig_spec_prob(h, d$X1))
        for (es in 0:1) {
          de <- d
          de$E_star <- es
          de$Y_star <- y
          de$w <- de$w * ifelse(es == 1L, p_es, 1 - p_es)
          push(de)
        }
      } else if (h$component == 'outcome') {
        p_ys <- if (y == 1L) outcome_sens_prob(h, z) else 1 - outcome_spec_prob(h)
        for (ys in 0:1) {
          dy <- d
          dy$E_star <- dy$E
          dy$Y_star <- ys
          dy$w <- dy$w * ifelse(ys == 1L, p_ys, 1 - p_ys)
          push(dy)
        }
      } else {
        d$E_star <- d$E
        d$Y_star <- y
        push(d)
      }
    }
  }
  out <- do.call(rbind, pieces)
  out <- out[out$w > 1e-18, , drop = FALSE]
  out$w <- out$w / sum(out$w)
  rownames(out) <- NULL
  out
}

weighted_projection <- function(x, y, w) {
  sw <- sqrt(w)
  xw <- x * sw
  yw <- y * sw
  keep <- independent_columns(xw)
  fit_qr <- qr(xw[, keep, drop = FALSE], tol = 1e-10)
  if (fit_qr$rank < length(keep)) stop('Population projection rank failure')
  coefficients <- qr.coef(fit_qr, yw)
  if (is.null(dim(coefficients))) coefficients <- matrix(coefficients, ncol = 1L)
  x[, keep, drop = FALSE] %*% coefficients
}

population_hajek <- function(h_active, h_control, endpoint, w) {
  d_active <- sum(w * h_active)
  d_control <- sum(w * h_control)
  mu_active <- sum(w * h_active * endpoint) / d_active
  mu_control <- sum(w * h_control * endpoint) / d_control
  influence <- h_active * (endpoint - mu_active) / d_active -
    h_control * (endpoint - mu_control) / d_control
  list(est = mu_active - mu_control, influence = influence)
}

power_variances <- function(h, n_nodes) {
  d <- population_states(h, n_nodes)
  pi2 <- if (h$component == 'strategy') 0.50 * strategy_q_prob(h, d$X1) else 0.40
  pi0 <- 0.50
  q_values <- cbind(
    G2 = d$E * (d$Z == 2L) * d$Y / pi2,
    H2 = d$E * (d$Z == 2L) / pi2,
    G0 = d$E * (d$Z == 0L) * d$Y / pi0,
    H0 = d$E * (d$Z == 0L) / pi0
  )
  x <- operational_basis(d, h$component)
  prediction <- weighted_projection(x, q_values, d$w)
  pseudo0 <- prediction
  pseudo1 <- prediction + (q_values - prediction) / VALIDATION_PROB
  pseudo <- rbind(pseudo0, pseudo1)
  wv <- c(d$w * (1 - VALIDATION_PROB), d$w * VALIDATION_PROB)
  theta <- colSums(pseudo * wv)
  mu2 <- theta[['G2']] / theta[['H2']]
  mu0 <- theta[['G0']] / theta[['H0']]
  if_aug <- (pseudo[, 'G2'] - mu2 * pseudo[, 'H2']) / theta[['H2']] -
    (pseudo[, 'G0'] - mu0 * pseudo[, 'H0']) / theta[['H0']]

  if (h$component == 'strategy') {
    op <- population_hajek(d$E * (d$A_star == 1L) / 0.50,
                           d$E * (d$A_star == 0L) / 0.50, d$Y, d$w)
  } else {
    selection <- if (h$component == 'eligibility') d$E_star else d$E
    endpoint <- if (h$component == 'outcome') d$Y_star else d$Y
    op <- population_hajek(selection * (d$Z == 2L) / 0.40,
                           selection * (d$Z == 0L) / 0.50, endpoint, d$w)
  }
  if_op <- rep(op$influence, 2L)
  if_gap <- if_op - if_aug
  center_var <- function(x) sum(wv * (x - sum(wv * x))^2)
  c(var_psi_i = center_var(if_aug), var_gap = center_var(if_gap))
}

power_parameter_layout <- function(scen) {
  component <- as.character(scen$component)
  bounds <- fidelity_bounds(component, as.character(scen$fidelity))
  lower <- upper <- numeric()
  add <- function(name, range) {
    lower[[name]] <<- range[1]
    upper[[name]] <<- range[2]
  }
  if (component == 'eligibility') {
    add('elig_sens_target', bounds$sensitivity)
    add('elig_spec_target', bounds$specificity)
  } else if (component == 'strategy') {
    add('strategy_q_target', bounds$q)
  } else {
    add('outcome_sens_target', bounds$sensitivity)
    add('outcome_spec_target', bounds$specificity)
  }
  if (scen$effect_modification == 'present') add('lambda', c(0, 1))
  if (scen$dependence == 'differential') {
    if (component == 'eligibility') {
      add('elig_sens_mag', DIFFERENTIAL_SLOPE_RANGE)
      add('elig_spec_mag', DIFFERENTIAL_SLOPE_RANGE)
    } else if (component == 'strategy') {
      add('strategy_q_mag', DIFFERENTIAL_SLOPE_RANGE)
    } else {
      add('outcome_sens_mag', DIFFERENTIAL_SLOPE_RANGE)
    }
  }
  list(lower = lower, upper = upper)
}

power_sign_grid <- function(scen) {
  if (scen$dependence != 'differential') return(data.frame(sign1 = 1, sign2 = 1))
  if (scen$component == 'eligibility') {
    return(expand.grid(sign1 = c(-1, 1), sign2 = c(-1, 1)))
  }
  data.frame(sign1 = c(-1, 1), sign2 = 1)
}

power_mechanism <- function(parameters, scen, signs, calibration_nodes = 128L) {
  h <- empty_mechanism(scen)
  if (h$effect_modification == 'absent') h$lambda <- 0
  direct <- intersect(names(parameters), names(h))
  for (name in direct) h[[name]] <- unname(parameters[[name]])
  if ('elig_sens_mag' %in% names(parameters)) {
    h$elig_sens_slope <- signs$sign1 * parameters[['elig_sens_mag']]
    h$elig_spec_slope <- signs$sign2 * parameters[['elig_spec_mag']]
  }
  if ('strategy_q_mag' %in% names(parameters)) {
    h$strategy_q_slope <- signs$sign1 * parameters[['strategy_q_mag']]
  }
  if ('outcome_sens_mag' %in% names(parameters)) {
    h$outcome_sens_slope <- signs$sign1 * parameters[['outcome_sens_mag']]
  }
  calibrate_mechanism(h, calibration_nodes)
}

power_variances_converged <- function(h) {
  n <- POWER_START_NODES
  previous <- power_variances(h, n)
  converged <- FALSE
  repeat {
    n <- n * 2L
    current <- power_variances(h, n)
    if (max(abs(current - previous)) < 1e-7) {
      converged <- TRUE
      break
    }
    if (n >= POWER_MAX_NODES) break
    previous <- current
  }
  list(values = current, nodes = n, converged = converged)
}

## Critique fix: N is selected before any performance replicate. The search
## maximizes augmented intended-effect and augmented-gap asymptotic variances
## over every compact mechanism stratum, then inflates the maxima by 10 percent.
select_sample_size <- function(scenarios = build_scenarios()) {
  records <- list()
  for (i in seq_len(nrow(scenarios))) {
    scen <- scenarios[i, , drop = FALSE]
    layout <- power_parameter_layout(scen)
    signs <- power_sign_grid(scen)
    best <- list(psi_i = list(value = -Inf), gap = list(value = -Inf))
    for (s in seq_len(nrow(signs))) {
      sign_values <- as.list(signs[s, , drop = FALSE])
      for (metric in c('psi_i', 'gap')) {
        field <- if (metric == 'psi_i') 'var_psi_i' else 'var_gap'
        for (start in seq_len(POWER_STARTS)) {
          fractions <- c(0.10, 0.50, 0.90)
          f <- fractions[start]
          pattern <- ifelse((seq_along(layout$lower) + start) %% 2L == 0L, f, 1 - f)
          initial <- layout$lower + (layout$upper - layout$lower) * pattern
          objective <- function(parameters) {
            value <- tryCatch({
              h <- power_mechanism(parameters, scen, sign_values, 64L)
              if (!h$calibration_ok) stop('calibration')
              -unname(power_variances(h, POWER_START_NODES)[[field]])
            }, error = function(e) .Machine$double.xmax / 100)
            value
          }
          fit <- try(stats::optim(initial, objective, method = 'L-BFGS-B',
                                  lower = layout$lower, upper = layout$upper,
                                  control = list(maxit = POWER_MAXIT, factr = 1e8)),
                     silent = TRUE)
          if (inherits(fit, 'try-error') || !is.finite(fit$value)) next
          candidate <- -fit$value
          if (candidate > best[[metric]]$value) {
            best[[metric]] <- list(value = candidate, parameters = fit$par,
                                   signs = sign_values)
          }
        }
      }
    }
    for (metric in c('psi_i', 'gap')) {
      if (!is.finite(best[[metric]]$value)) stop('Power search failed in scenario ', i)
      h <- power_mechanism(best[[metric]]$parameters, scen,
                           best[[metric]]$signs, CALIBRATION_NODES)
      verified <- power_variances_converged(h)
      field <- if (metric == 'psi_i') 'var_psi_i' else 'var_gap'
      records[[length(records) + 1L]] <- data.frame(
        scenario = scen$scenario, component = scen$component,
        fidelity = scen$fidelity, effect_modification = scen$effect_modification,
        dependence = scen$dependence, metric = metric,
        variance = unname(verified$values[[field]]),
        quadrature_nodes = verified$nodes,
        quadrature_converged = verified$converged,
        sign1 = best[[metric]]$signs$sign1,
        sign2 = best[[metric]]$signs$sign2,
        stringsAsFactors = FALSE
      )
    }
  }
  search <- do.call(rbind, records)
  if (!all(search$quadrature_converged)) stop('Power variance quadrature did not converge')
  max_psi <- max(search$variance[search$metric == 'psi_i']) * POWER_VARIANCE_INFLATION
  max_gap <- max(search$variance[search$metric == 'gap']) * POWER_VARIANCE_INFLATION

  criteria_at <- function(n) {
    se_gap <- sqrt(max_gap / n)
    se_psi <- sqrt(max_psi / n)
    lower_preserve <- -PRESERVATION_MARGIN + 1.645 * se_gap
    upper_preserve <- PRESERVATION_MARGIN - 1.645 * se_gap
    p_preserve <- if (lower_preserve >= upper_preserve) 0 else
      stats::pnorm(upper_preserve, mean = DIAGNOSTIC_PRESERVING_TRUTH, sd = se_gap) -
      stats::pnorm(lower_preserve, mean = DIAGNOSTIC_PRESERVING_TRUTH, sd = se_gap)
    p_changed <- stats::pnorm(
      DIAGNOSTIC_PRESERVING_TRUTH + 0.025 - DIAGNOSTIC_CHANGE_BOUNDARY,
      mean = 1.96 * se_gap, sd = se_gap, lower.tail = FALSE)
    ## The preceding expression is replaced by the exact two-tail probability
    ## at true Delta = 0.03 so both signs remain symmetric in the audit record.
    p_changed <- stats::pnorm(DIAGNOSTIC_CHANGE_BOUNDARY + 1.96 * se_gap,
                              mean = DIAGNOSTIC_CHANGED_TRUTH, sd = se_gap,
                              lower.tail = FALSE) +
      stats::pnorm(-DIAGNOSTIC_CHANGE_BOUNDARY - 1.96 * se_gap,
                   mean = DIAGNOSTIC_CHANGED_TRUTH, sd = se_gap)
    width <- 2 * 1.96 * se_psi
    c(p_preserve = p_preserve, p_changed = p_changed, psi_i_width = width)
  }

  n <- 1000L
  repeat {
    criteria <- criteria_at(n)
    if (criteria[['p_preserve']] >= POWER_TARGET &&
        criteria[['p_changed']] >= POWER_TARGET &&
        criteria[['psi_i_width']] <= MAX_EXPECTED_INTERVAL_WIDTH) break
    n <- n + 1000L
    if (n > 5000000L) stop('Power-selected N exceeded 5,000,000')
  }
  list(
    n = n,
    max_var_psi_i_inflated = max_psi,
    max_var_gap_inflated = max_gap,
    criteria = data.frame(n = n, t(criteria), row.names = NULL),
    search = search,
    rule_version = POWER_RULE_VERSION,
    config_signature = CONFIG_SIGNATURE
  )
}
