## Study TZO-01: nuisance fitting, CCW estimators, selector, and truth.

## base::tabulate has no `weights` argument. Generated code invents it, which is
## the failure mode this program has to assume: an invented argument on a real
## function parses, sources, and dies only when the line is reached. This is the
## grouped sum it was meant to be, keeping empty bins at zero.
wtabulate <- function(bin, nbins, weights) {
  out <- numeric(nbins)
  if (!length(bin)) return(out)
  s <- rowsum(as.numeric(weights), bin, reorder = FALSE)
  idx <- as.integer(rownames(s))
  keep <- idx >= 1L & idx <= nbins
  out[idx[keep]] <- s[keep]
  out
}

cloglog_parts <- function(eta) {
  q <- exp(pmin(eta, 25))
  mu <- -expm1(-q)
  mu <- pmin(pmax(mu, 1e-9), 1 - 1e-9)
  derivative <- pmax(q * exp(-q), 1e-12)
  list(mu = mu, derivative = derivative)
}

irls_equations <- function(d, coefficient, response = d$y) {
  K <- d$n_period
  q <- ncol(d$x)
  eta <- coefficient[d$period] + drop(d$x %*% coefficient[K + seq_len(q)])
  parts <- cloglog_parts(eta)
  variance <- parts$mu * (1 - parts$mu)
  weight <- parts$derivative^2 / variance
  working <- eta + (response - parts$mu) / parts$derivative

  aa <- wtabulate(d$period, nbins = K, weights = weight)
  ab <- matrix(0, K, q)
  tmp <- rowsum(d$x * weight, d$period, reorder = FALSE)
  ab[as.integer(rownames(tmp)), ] <- tmp
  bb <- crossprod(d$x, d$x * weight)
  rhs_a <- wtabulate(d$period, nbins = K, weights = weight * working)
  rhs_b <- drop(crossprod(d$x, weight * working))
  matrix <- rbind(cbind(diag(aa), ab), cbind(t(ab), bb))
  list(matrix = matrix, rhs = c(rhs_a, rhs_b), mu = parts$mu,
       derivative = parts$derivative)
}

fit_compact_cloglog <- function(d, response = d$y, maxit = 30L, tolerance = 1e-8) {
  K <- d$n_period
  q <- ncol(d$x)
  means <- tapply(response, d$period, mean)
  means <- pmin(pmax(means[as.character(seq_len(K))], 1e-5), 1 - 1e-5)
  coefficient <- c(log(-log1p(-means)), rep(0, q))
  if (any(!is.finite(coefficient))) coefficient <- c(rep(-3, K), rep(0, q))
  converged <- FALSE
  equations <- NULL
  for (iteration in seq_len(maxit)) {
    equations <- irls_equations(d, coefficient, response)
    next_coefficient <- tryCatch(
      solve(equations$matrix, equations$rhs),
      error = function(e) rep(NA_real_, length(coefficient))
    )
    if (any(!is.finite(next_coefficient))) break
    change <- max(abs(next_coefficient - coefficient))
    coefficient <- next_coefficient
    if (change < tolerance) {
      converged <- TRUE
      break
    }
  }
  equations <- irls_equations(d, coefficient, response)
  condition <- tryCatch(kappa(equations$matrix, exact = FALSE),
                        error = function(e) Inf)
  information_inverse <- tryCatch(solve(equations$matrix),
                                  error = function(e) NULL)
  valid <- converged && all(is.finite(coefficient)) && is.finite(condition) &&
    condition <= 1e12 && !is.null(information_inverse)
  list(
    coefficient = coefficient,
    converged = converged,
    valid = valid,
    condition = condition,
    information = equations$matrix,
    information_inverse = information_inverse,
    n_period = K,
    q = q,
    iterations = iteration
  )
}

predict_compact <- function(fit, d) {
  K <- d$n_period
  eta <- fit$coefficient[d$period] +
    drop(d$x %*% fit$coefficient[K + seq_len(ncol(d$x))])
  cloglog_parts(eta)$mu
}

subset_init_data <- function(d, keep) {
  out <- d
  out$id <- d$id[keep]
  out$period <- d$period[keep]
  out$x <- d$x[keep, , drop = FALSE]
  out$y <- d$y[keep]
  out$oracle_p <- d$oracle_p[keep]
  out$width <- d$width[keep]
  out$row_index <- NULL
  out
}

coefficient_contributions <- function(fit, d) {
  if (!fit$valid) return(NULL)
  K <- d$n_period
  p <- length(fit$coefficient)
  predicted <- predict_compact(fit, d)
  parts <- cloglog_parts(
    fit$coefficient[d$period] +
      drop(d$x %*% fit$coefficient[K + seq_len(ncol(d$x))])
  )
  score_factor <- (d$y - predicted) * parts$derivative /
    (predicted * (1 - predicted))
  score <- matrix(0, d$n, p)
  score[cbind(d$id, d$period)] <- score_factor
  continuous <- rowsum(d$x * score_factor, d$id, reorder = FALSE)
  score[as.integer(rownames(continuous)), K + seq_len(ncol(d$x))] <- continuous
  score %*% t(fit$information_inverse)
}

fit_panel_model <- function(panel, influence = TRUE) {
  start <- proc.time()[['elapsed']]
  d <- init_data(panel)
  fit <- tryCatch(fit_compact_cloglog(d), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(valid = FALSE, fail = 'initiation-model-failed', elapsed =
                  proc.time()[['elapsed']] - start, data = d))
  }
  predicted <- if (fit$valid) predict_compact(fit, d) else rep(NA_real_, length(d$y))
  probability <- matrix(NA_real_, panel$n, length(panel$boundaries))
  if (fit$valid) probability[cbind(d$id, d$period)] <- predicted
  contribution <- if (fit$valid && influence) coefficient_contributions(fit, d) else NULL
  list(
    valid = fit$valid,
    fail = if (fit$valid) NA_character_ else 'initiation-model-failed',
    fit = fit,
    data = d,
    probability = probability,
    coefficient_contribution = contribution,
    elapsed = proc.time()[['elapsed']] - start
  )
}

weight_paths <- function(panel, probability, G, arm) {
  n <- panel$n
  ni <- length(panel$boundaries) - 1L
  weight <- matrix(0, n, ni)
  adherent_matrix <- matrix(FALSE, n, ni)
  adherent <- rep(TRUE, n)
  log_weight <- numeric(n)
  for (j in seq_len(ni)) {
    boundary <- panel$boundaries[j]
    status <- panel$status[, j]
    previous_status <- if (j == 1L) rep(FALSE, n) else panel$status[, j - 1L]
    transition <- status & !previous_status
    p <- probability[, j]
    if (arm == 'delay' && boundary < G) {
      staying <- adherent & !status
      log_weight[staying] <- log_weight[staying] - log1p(-p[staying])
      adherent[adherent & status] <- FALSE
    }
    if (arm == 'early' && boundary == G) {
      starting <- adherent & transition
      log_weight[starting] <- log_weight[starting] - log(p[starting])
      adherent[adherent & !status] <- FALSE
    }
    weight[, j] <- ifelse(adherent, exp(log_weight), 0)
    adherent_matrix[, j] <- adherent
  }
  list(weight = weight, adherent = adherent_matrix)
}

ess_by_interval <- function(weight) {
  apply(weight, 2, function(w) {
    if (!any(w > 0)) return(0)
    sum(w)^2 / sum(w^2)
  })
}

weight_diagnostics <- function(paths) {
  w <- paths$weight[paths$weight > 0]
  ess <- ess_by_interval(paths$weight)
  c(
    maximum = if (length(w)) max(w) else NA_real_,
    cv = if (length(w) > 1L) stats::sd(w) / mean(w) else NA_real_,
    ess_min = if (length(ess)) min(ess) else 0,
    ess_median = if (length(ess)) stats::median(ess) else 0
  )
}

clip_limits <- function(paths, truncation) {
  w <- paths$weight[paths$weight > 0]
  if (!length(w)) return(c(NA_real_, NA_real_))
  if (truncation == 'cap20') return(c(0, 20))
  if (truncation == 'p0199') return(unname(stats::quantile(w, c(0.01, 0.99))))
  c(0, Inf)
}

add_logweight_gradient <- function(gradient, ids, period, multiplier, model) {
  if (!length(ids)) return(gradient)
  d <- model$data
  K <- d$n_period
  rows <- d$row_index[cbind(ids, rep(period, length(ids)))]
  gradient[cbind(ids, rep(period, length(ids)))] <-
    gradient[cbind(ids, rep(period, length(ids)))] + multiplier
  gradient[ids, K + seq_len(ncol(d$x))] <-
    gradient[ids, K + seq_len(ncol(d$x)), drop = FALSE] +
    d$x[rows, , drop = FALSE] * multiplier
  gradient
}

risk_arm <- function(panel, probability, event_time, G, arm, model = NULL,
                     limits = c(0, Inf), treatment_first = FALSE,
                     influence = TRUE) {
  n <- panel$n
  ni <- length(panel$boundaries) - 1L
  estimated <- !is.null(model)
  pcoef <- if (estimated) length(model$fit$coefficient) else 0L
  coefficient_delta <- if (estimated) model$coefficient_contribution else NULL
  adherent <- rep(TRUE, n)
  log_weight <- numeric(n)
  gradient <- if (estimated && influence) matrix(0, n, pcoef) else NULL
  hazard <- numeric(ni)
  direct <- if (influence) matrix(0, n, ni) else NULL
  hazard_gradient <- if (estimated && influence) matrix(0, ni, pcoef) else NULL

  for (j in seq_len(ni)) {
    left <- panel$boundaries[j]
    right <- panel$boundaries[j + 1L]
    status <- panel$status[, j]
    previous_status <- if (j == 1L) rep(FALSE, n) else panel$status[, j - 1L]
    transition <- status & !previous_status
    p <- probability[, j]

    if (arm == 'delay' && left < G) {
      staying <- which(adherent & !status)
      if (length(staying)) {
        log_weight[staying] <- log_weight[staying] - log1p(-p[staying])
        if (estimated && influence) {
          eta <- model$fit$coefficient[j] +
            drop(model$data$x[model$data$row_index[cbind(staying, j)], , drop = FALSE] %*%
                   model$fit$coefficient[model$data$n_period + seq_len(ncol(model$data$x))])
          parts <- cloglog_parts(eta)
          multiplier <- parts$derivative / (1 - parts$mu)
          gradient <- add_logweight_gradient(gradient, staying, j, multiplier, model)
        }
      }
      adherent[adherent & status] <- FALSE
    }
    if (arm == 'early' && left == G) {
      starting <- which(adherent & transition)
      if (length(starting)) {
        log_weight[starting] <- log_weight[starting] - log(p[starting])
        if (estimated && influence) {
          eta <- model$fit$coefficient[j] +
            drop(model$data$x[model$data$row_index[cbind(starting, j)], , drop = FALSE] %*%
                   model$fit$coefficient[model$data$n_period + seq_len(ncol(model$data$x))])
          parts <- cloglog_parts(eta)
          multiplier <- -parts$derivative / parts$mu
          gradient <- add_logweight_gradient(gradient, starting, j, multiplier, model)
        }
      }
      adherent[adherent & !status] <- FALSE
    }

    raw_weight <- ifelse(adherent, exp(log_weight), 0)
    used_weight <- pmin(pmax(raw_weight, limits[1]), limits[2])
    used_weight[!adherent] <- 0
    alive <- is.na(event_time) | event_time > left
    event <- !is.na(event_time) & event_time > left & event_time <= right
    if (treatment_first && arm == 'delay' && right < G) {
      transition_at_right <- panel$status[, j + 1L] & !panel$status[, j]
      event[event & transition_at_right] <- FALSE
    }
    risk <- adherent & alive
    denominator <- sum(used_weight[risk])
    if (!is.finite(denominator) || denominator <= 0) {
      return(list(valid = FALSE, fail = 'empty-arm-risk-set'))
    }
    hazard[j] <- sum(used_weight[risk] * event[risk]) / denominator
    if (!is.finite(hazard[j]) || hazard[j] < 0 || hazard[j] >= 1) {
      return(list(valid = FALSE, fail = 'invalid-weighted-hazard'))
    }
    if (influence) {
      direct[, j] <- used_weight * risk * (as.numeric(event) - hazard[j]) / denominator
      if (estimated) {
        active_derivative <- raw_weight > limits[1] & raw_weight < limits[2] & risk
        hazard_gradient[j, ] <- colSums(
          gradient * (used_weight * active_derivative *
                        (as.numeric(event) - hazard[j]))
        ) / denominator
      }
    }
  }

  survival <- prod(1 - hazard)
  risk <- 1 - survival
  if (!influence) return(list(valid = TRUE, risk = risk, hazard = hazard))
  derivative_hazard <- survival / (1 - hazard)
  person_contribution <- drop(direct %*% derivative_hazard)
  if (estimated) {
    derivative_coefficient <- drop(crossprod(derivative_hazard, hazard_gradient))
    person_contribution <- person_contribution +
      drop(coefficient_delta %*% derivative_coefficient)
  }
  list(valid = TRUE, risk = risk, hazard = hazard,
       contribution = person_contribution)
}

estimate_ccw <- function(panel, model, event_time, G, truncation = 'none',
                         oracle = FALSE, bounds = TRUE) {
  started <- proc.time()[['elapsed']]
  if (!oracle && (is.null(model) || !isTRUE(model$valid))) {
    return(list(valid = FALSE, fail = 'initiation-model-failed',
                elapsed = proc.time()[['elapsed']] - started))
  }
  probability <- if (oracle) panel$oracle_p else model$probability
  if (any(!is.finite(probability[panel$eligible]))) {
    return(list(valid = FALSE, fail = 'nonfinite-weight-probability',
                elapsed = proc.time()[['elapsed']] - started))
  }
  early_paths <- weight_paths(panel, probability, G, 'early')
  delay_paths <- weight_paths(panel, probability, G, 'delay')
  early_limits <- clip_limits(early_paths, truncation)
  delay_limits <- clip_limits(delay_paths, truncation)
  influence_model <- if (oracle) NULL else model
  early <- risk_arm(panel, probability, event_time, G, 'early', influence_model,
                    early_limits, influence = TRUE)
  delay <- risk_arm(panel, probability, event_time, G, 'delay', influence_model,
                    delay_limits, influence = TRUE)
  if (!isTRUE(early$valid) || !isTRUE(delay$valid)) {
    why <- if (!isTRUE(early$valid)) early$fail else delay$fail
    return(list(valid = FALSE, fail = why,
                elapsed = proc.time()[['elapsed']] - started))
  }
  estimate <- early$risk - delay$risk
  contribution <- early$contribution - delay$contribution
  variance <- sum(contribution^2)
  if (!is.finite(variance) || variance <= 0) {
    return(list(valid = FALSE, fail = 'nonpositive-sandwich-variance',
                elapsed = proc.time()[['elapsed']] - started))
  }
  se <- sqrt(variance)
  treatment_first <- NA_real_
  if (bounds) {
    delay_first <- risk_arm(panel, probability, event_time, G, 'delay', NULL,
                            delay_limits, treatment_first = TRUE, influence = FALSE)
    if (isTRUE(delay_first$valid)) treatment_first <- early$risk - delay_first$risk
  }
  de <- weight_diagnostics(early_paths)
  dd <- weight_diagnostics(delay_paths)
  list(
    valid = TRUE,
    fail = NA_character_,
    est = estimate,
    se = se,
    lo = estimate - 1.96 * se,
    hi = estimate + 1.96 * se,
    risk_early = early$risk,
    risk_delay = delay$risk,
    outcome_first = estimate,
    treatment_first = treatment_first,
    max_weight_early = de[['maximum']],
    max_weight_delay = dd[['maximum']],
    cv_weight_early = de[['cv']],
    cv_weight_delay = dd[['cv']],
    ess_early = de[['ess_min']],
    ess_delay = dd[['ess_min']],
    condition = if (oracle) NA_real_ else model$fit$condition,
    nuisance_p = if (oracle) 0L else length(model$fit$coefficient),
    rows = panel$n * (length(panel$boundaries) - 1L),
    memory_mb = as.numeric(object.size(panel)) / 1024^2,
    elapsed = proc.time()[['elapsed']] - started
  )
}

wilson_upper <- function(x, n, level = 0.95) {
  if (n <= 0) return(1)
  z <- stats::qnorm(level)
  p <- x / n
  center <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  min(1, center + half)
}

cv_process_loss <- function(panel, folds = CV_FOLDS) {
  d <- init_data(panel)
  fold <- ((d$id - 1L) %% folds) + 1L
  loss <- numeric(length(d$y))
  valid <- TRUE
  for (f in seq_len(folds)) {
    train <- subset_init_data(d, fold != f)
    test <- subset_init_data(d, fold == f)
    fit <- tryCatch(fit_compact_cloglog(train), error = function(e) NULL)
    if (is.null(fit) || !fit$valid) {
      valid <- FALSE
      break
    }
    p <- predict_compact(fit, test)
    loss[fold == f] <- -(test$y * log(p) + (1 - test$y) * log1p(-p)) /
      test$width
  }
  if (!valid) return(NA_real_)
  mean(loss)
}

selector_for <- function(proc, G) {
  ## Critique fix: the selector uses process records only. No outcome is
  ## generated before this function returns and freezes its selected grid.
  started <- proc.time()[['elapsed']]
  starts <- sum(is.finite(proc$natural_start))
  visits <- sum(proc$visits)
  support <- starts >= 50L && visits >= 500L
  rows <- vector('list', length(GRIDS))
  for (i in seq_along(GRIDS)) {
    delta <- GRIDS[i]
    panel <- make_panel(proc, delta, G)
    model <- fit_panel_model(panel, influence = FALSE)
    loss <- if (model$valid) cv_process_loss(panel) else NA_real_
    nonempty <- sum(panel$nonempty)
    alias1 <- sum(panel$alias_multiple)
    alias2 <- sum(panel$alias_marker_treatment)
    p1 <- if (nonempty) alias1 / nonempty else 0
    p2 <- if (nonempty) alias2 / nonempty else 0
    if (model$valid) {
      early <- weight_paths(panel, model$probability, G, 'early')
      delay <- weight_paths(panel, model$probability, G, 'delay')
      ess_early <- min(ess_by_interval(early$weight))
      ess_delay <- min(ess_by_interval(delay$weight))
      predicted <- model$probability[panel$eligible]
      observed <- panel$transition[panel$eligible]
      calibration_error <- abs(mean(observed) - mean(predicted))
      brier <- mean((observed - predicted)^2)
    } else {
      ess_early <- ess_delay <- calibration_error <- brier <- NA_real_
    }
    rows[[i]] <- data.frame(
      G = G, delta = delta,
      alias_multiple = p1,
      alias_multiple_upper = wilson_upper(alias1, nonempty),
      alias_marker_treatment = p2,
      alias_marker_treatment_upper = wilson_upper(alias2, nonempty),
      cv_logloss = loss,
      calibration_error = calibration_error,
      brier = brier,
      ess_early = ess_early,
      ess_delay = ess_delay,
      person_periods = panel$n * (length(panel$boundaries) - 1L),
      nuisance_p = if (model$valid) length(model$fit$coefficient) else NA_integer_,
      condition = if (model$valid) model$fit$condition else Inf,
      memory_mb = as.numeric(object.size(panel)) / 1024^2,
      model_valid = model$valid,
      stringsAsFactors = FALSE
    )
  }
  table <- do.call(rbind, rows)
  reference <- table$cv_logloss[table$delta == 1L]
  table$passes <- support & table$model_valid &
    table$alias_multiple_upper <= SELECTOR_ALIAS_LIMIT &
    table$alias_marker_treatment_upper <= SELECTOR_ALIAS_LIMIT &
    is.finite(table$cv_logloss) & is.finite(reference) &
    table$cv_logloss <= SELECTOR_LOGLOSS_RATIO * reference &
    table$ess_early >= SELECTOR_ESS_MIN & table$ess_delay >= SELECTOR_ESS_MIN
  passing <- sort(table$delta[table$passes], decreasing = TRUE)
  selected <- if (length(passing)) passing[1L] else 1L
  list(
    G = G,
    selected = selected,
    support = support,
    fail = if (support) NA_character_ else 'selector-support',
    starts = starts,
    visits = visits,
    table = table,
    elapsed = proc.time()[['elapsed']] - started
  )
}

conditional_interval_expectations <- function(H, boundaries) {
  cumulative <- H
  if (ncol(H) > 1L) {
    for (j in 2:ncol(H)) cumulative[, j] <- cumulative[, j - 1L] + H[, j]
  }
  n <- nrow(H)
  ni <- length(boundaries) - 1L
  survival_left <- matrix(NA_real_, n, ni)
  event <- matrix(NA_real_, n, ni)
  for (j in seq_len(ni)) {
    left <- boundaries[j]
    right <- boundaries[j + 1L]
    h_left <- if (left == 0L) rep(0, n) else cumulative[, left]
    h_right <- cumulative[, right]
    survival_left[, j] <- exp(-h_left)
    event[, j] <- exp(-h_left) - exp(-h_right)
  }
  list(survival = survival_left, event = event)
}

expected_weighted_risk <- function(paths, expectation) {
  numerator <- colSums(paths$weight * expectation$event)
  denominator <- colSums(paths$weight * expectation$survival)
  if (any(!is.finite(denominator)) || any(denominator <= 0)) return(NA_real_)
  hazard <- numerator / denominator
  if (any(!is.finite(hazard)) || any(hazard < 0) || any(hazard >= 1)) return(NA_real_)
  1 - prod(1 - hazard)
}

truth_seeded_process <- function(scen, seed, n) {
  ## Truth owns a separate deterministic stream. This is not a simulation
  ## replicate, so it does not interfere with the harness streams.
  set.seed(as.integer(seed %% (.Machine$integer.max - 1L)) + 1L)
  gen_process(scen, n)
}

fit_population_models <- function(scen) {
  definitions <- expand.grid(G = GRACES, delta = GRIDS, stringsAsFactors = FALSE)
  definitions$key <- paste0('g', definitions$G, 'd', definitions$delta)
  models <- vector('list', nrow(definitions))
  names(models) <- definitions$key
  for (i in seq_len(nrow(definitions))) {
    ## Decision boundaries only; the terminal boundary carries no intercept.
    K <- length(panel_boundaries(definitions$delta[i], definitions$G[i])) - 1L
    models[[i]] <- list(
      coefficient = c(rep(-3, K), rep(0, length(INIT_FEATURES))),
      n_period = K,
      q = length(INIT_FEATURES),
      valid = TRUE
    )
  }
  chunks <- ceiling(TRUTH_FIT_N / TRUTH_CHUNK)
  for (iteration in seq_len(20L)) {
    accum <- lapply(models, function(m) list(
      matrix = matrix(0, length(m$coefficient), length(m$coefficient)),
      rhs = numeric(length(m$coefficient))
    ))
    for (chunk in seq_len(chunks)) {
      n <- min(TRUTH_CHUNK, TRUTH_FIT_N - (chunk - 1L) * TRUTH_CHUNK)
      proc <- truth_seeded_process(
        scen, MASTER_SEED + 1000000L + 10000L * scen$scenario + chunk, n
      )
      for (i in seq_len(nrow(definitions))) {
        panel <- make_panel(proc, definitions$delta[i], definitions$G[i])
        d <- init_data(panel)
        eq <- irls_equations(d, models[[i]]$coefficient, d$oracle_p)
        accum[[i]]$matrix <- accum[[i]]$matrix + eq$matrix
        accum[[i]]$rhs <- accum[[i]]$rhs + eq$rhs
      }
    }
    change <- numeric(length(models))
    for (i in seq_along(models)) {
      next_coefficient <- tryCatch(
        solve(accum[[i]]$matrix, accum[[i]]$rhs),
        error = function(e) rep(NA_real_, length(models[[i]]$coefficient))
      )
      if (any(!is.finite(next_coefficient))) {
        models[[i]]$valid <- FALSE
        change[i] <- Inf
      } else {
        change[i] <- max(abs(next_coefficient - models[[i]]$coefficient))
        models[[i]]$coefficient <- next_coefficient
        models[[i]]$information <- accum[[i]]$matrix
      }
    }
    if (all(change < 1e-8)) break
  }
  for (i in seq_along(models)) {
    condition <- tryCatch(kappa(models[[i]]$information, exact = FALSE),
                          error = function(e) Inf)
    models[[i]]$condition <- condition
    models[[i]]$converged <- isTRUE(models[[i]]$valid) && condition <= 1e12
    models[[i]]$valid <- models[[i]]$converged
  }
  attr(models, 'definitions') <- definitions
  models
}

population_probability <- function(model, d) {
  fit <- model
  fit$valid <- model$valid
  predict_compact(fit, d)
}

truth_batch_for <- function(scen, models, batch_id) {
  definitions <- attr(models, 'definitions')
  chunks <- ceiling(TRUTH_BATCH / TRUTH_CHUNK)
  full_sum <- list()
  panel_acc <- list()
  for (chunk in seq_len(chunks)) {
    n <- min(TRUTH_CHUNK, TRUTH_BATCH - (chunk - 1L) * TRUTH_CHUNK)
    seed <- MASTER_SEED + 100000000L + 1000000L * scen$scenario +
      10000L * batch_id + chunk
    proc <- truth_seeded_process(scen, seed, n)

    for (profile in OUTCOME_PROFILES) {
      for (G in GRACES) {
        early <- conditional_risk(proc, profile, regime_start(proc, G, 'early'))
        delay <- conditional_risk(proc, profile, regime_start(proc, G, 'delay'))
        for (arm in c('early', 'delay')) {
          key <- paste('full', profile, G, arm, sep = '|')
          value <- if (arm == 'early') early else delay
          full_sum[[key]] <- (full_sum[[key]] %||% 0) + sum(value)
        }
      }
    }

    natural_hazard <- lapply(OUTCOME_PROFILES, function(profile)
      hazard_increments(proc, profile, proc$natural_start))
    names(natural_hazard) <- OUTCOME_PROFILES

    for (i in seq_len(nrow(definitions))) {
      G <- definitions$G[i]
      delta <- definitions$delta[i]
      key_model <- definitions$key[i]
      panel <- make_panel(proc, delta, G)
      d <- init_data(panel)
      estimated_p <- matrix(NA_real_, n, length(panel$boundaries))
      if (models[[key_model]]$valid) {
        estimated_p[cbind(d$id, d$period)] <-
          population_probability(models[[key_model]], d)
      }
      probabilities <- list(estimated = estimated_p, oracle = panel$oracle_p)
      for (kind in names(probabilities)) {
        p <- probabilities[[kind]]
        if (any(!is.finite(p[panel$eligible]))) next
        paths <- list(
          early = weight_paths(panel, p, G, 'early'),
          delay = weight_paths(panel, p, G, 'delay')
        )
        for (profile in OUTCOME_PROFILES) {
          expectation <- conditional_interval_expectations(
            natural_hazard[[profile]], panel$boundaries
          )
          for (arm in c('early', 'delay')) {
            key <- paste(kind, profile, G, delta, arm, sep = '|')
            if (is.null(panel_acc[[key]])) {
              panel_acc[[key]] <- list(
                numerator = numeric(ncol(expectation$event)),
                denominator = numeric(ncol(expectation$event))
              )
            }
            panel_acc[[key]]$numerator <- panel_acc[[key]]$numerator +
              colSums(paths[[arm]]$weight * expectation$event)
            panel_acc[[key]]$denominator <- panel_acc[[key]]$denominator +
              colSums(paths[[arm]]$weight * expectation$survival)
          }
        }
      }
    }
  }

  values <- numeric()
  for (profile in OUTCOME_PROFILES) {
    full_rd <- numeric(length(GRACES))
    names(full_rd) <- GRACES
    for (G in GRACES) {
      re <- full_sum[[paste('full', profile, G, 'early', sep = '|')]] / TRUTH_BATCH
      rd <- full_sum[[paste('full', profile, G, 'delay', sep = '|')]] / TRUTH_BATCH
      full_rd[as.character(G)] <- re - rd
      values[paste('risk-full-early', profile, G, sep = '|')] <- re
      values[paste('risk-full-delay', profile, G, sep = '|')] <- rd
      values[paste('rd-full', profile, G, sep = '|')] <- re - rd
      for (delta in GRIDS) {
        for (kind in c('estimated', 'oracle')) {
          a <- panel_acc[[paste(kind, profile, G, delta, 'early', sep = '|')]]
          d <- panel_acc[[paste(kind, profile, G, delta, 'delay', sep = '|')]]
          if (is.null(a) || is.null(d)) {
            panel_rd <- NA_real_
          } else {
            ra <- 1 - prod(1 - a$numerator / a$denominator)
            rd0 <- 1 - prod(1 - d$numerator / d$denominator)
            panel_rd <- ra - rd0
          }
          label <- if (kind == 'estimated') 'panel' else 'oracle'
          values[paste('rd', label, profile, G, delta, sep = '|')] <- panel_rd
          values[paste('approx', label, profile, G, delta, sep = '|')] <-
            panel_rd - full_rd[as.character(G)]
        }
      }
    }
    values[paste('delta-g', profile, sep = '|')] <- full_rd['12'] - full_rd['4']
  }
  values
}

`%||%` <- function(a, b) if (is.null(a)) b else a

truth_for_process <- function(scen, batch_cache = NULL) {
  models <- fit_population_models(scen)
  batches <- list()
  max_batches <- TRUTH_MAX %/% TRUTH_BATCH
  precision_met <- FALSE
  ## Checkpoint each batch. Truth here is adaptive: it draws quarter-million
  ## batches until the Monte Carlo standard error on every decisive column is
  ## under target, up to four million. The sparse-visit, higher-pressure cells
  ## reach that ceiling, and one of them takes longer than this machine will
  ## hold a process. Without a within-cell checkpoint a killed run loses the
  ## whole cell, so the expensive cells could never finish however many times
  ## the run was resumed. Batches are deterministic given the scenario and the
  ## batch index, so a cached batch is the batch the run would have drawn.
  if (!is.null(batch_cache)) dir.create(batch_cache, recursive = TRUE,
                                        showWarnings = FALSE)
  for (batch in seq_len(max_batches)) {
    bf <- if (is.null(batch_cache)) NULL else
      file.path(batch_cache, sprintf("batch-%03d.rds", batch))
    if (!is.null(bf) && file.exists(bf)) {
      batches[[batch]] <- readRDS(bf)
    } else {
      batches[[batch]] <- truth_batch_for(scen, models, batch)
      if (!is.null(bf)) saveRDS(batches[[batch]], bf)
    }
    if (batch < 2L) next
    matrix <- do.call(rbind, batches)
    decisive <- grepl('^(rd-full|approx-panel|approx-oracle|delta-g)', colnames(matrix))
    mcse <- apply(matrix[, decisive, drop = FALSE], 2, stats::sd) / sqrt(batch)
    precision_met <- all(is.finite(mcse) & mcse <= TRUTH_MCSE_TARGET)
    if (precision_met) break
  }
  matrix <- do.call(rbind, batches)
  means <- colMeans(matrix, na.rm = TRUE)
  mcse <- apply(matrix, 2, stats::sd, na.rm = TRUE) / sqrt(nrow(matrix))
  rows <- list()
  for (profile in OUTCOME_PROFILES) {
    delta_g_name <- paste('delta-g', profile, sep = '|')
    for (G in GRACES) {
      cell <- cell_number(scen, profile, G)
      full_name <- paste('rd-full', profile, G, sep = '|')
      for (delta in GRIDS) {
        panel_name <- paste('rd', 'panel', profile, G, delta, sep = '|')
        oracle_name <- paste('rd', 'oracle', profile, G, delta, sep = '|')
        approx_panel_name <- paste('approx', 'panel', profile, G, delta, sep = '|')
        approx_oracle_name <- paste('approx', 'oracle', profile, G, delta, sep = '|')
        rows[[length(rows) + 1L]] <- data.frame(
          cell = cell,
          process_scenario = scen$scenario,
          visit_key = scen$visit_key,
          pressure_key = scen$pressure_key,
          profile = profile,
          G = G,
          delta = delta,
          rd_full = means[[full_name]],
          rd_full_mcse = mcse[[full_name]],
          rd_panel = means[[panel_name]],
          rd_panel_mcse = mcse[[panel_name]],
          rd_panel_oracle = means[[oracle_name]],
          rd_panel_oracle_mcse = mcse[[oracle_name]],
          approximation_error = means[[approx_panel_name]],
          approximation_error_mcse = mcse[[approx_panel_name]],
          oracle_approximation_error = means[[approx_oracle_name]],
          oracle_approximation_error_mcse = mcse[[approx_oracle_name]],
          delta_g = means[[delta_g_name]],
          delta_g_mcse = mcse[[delta_g_name]],
          truth_n = nrow(matrix) * TRUTH_BATCH,
          truth_batches = nrow(matrix),
          precision_met = precision_met,
          population_models_valid = all(vapply(models, function(x) x$valid, logical(1))),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  do.call(rbind, rows)
}
