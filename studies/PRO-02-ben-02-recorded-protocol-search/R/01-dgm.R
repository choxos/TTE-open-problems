## Study 2 (PRO-02): data-generating mechanism and enumerated truth.

expit <- function(x) stats::plogis(x)

## Independent covariate vectors. All operations are vectorized over people.
draw_covariates <- function(n) {
  u <- stats::runif(n, stats::pnorm(-2), stats::pnorm(2))
  Z <- stats::qnorm(u)
  age <- 55 + 10 * Z
  S <- stats::rbinom(n, 1, 0.50)
  C <- stats::rbinom(n, 1, expit(-0.40 + 0.50 * Z + 0.35 * S))
  B <- 0.30 * Z + 0.40 * (C - 0.5) + 0.20 * (S - 0.5) +
    0.80 * stats::rnorm(n)
  data.frame(Z = Z, age = age, S = S, C = C, B = B)
}

treatment_probability <- function(x) {
  expit(-0.30 + 0.45 * x$Z + 0.35 * (x$S - 0.5) +
          0.60 * (x$C - 0.5) + 0.35 * x$B)
}

outcome_linear_predictor <- function(x) {
  0.35 * x$Z + 0.25 * (x$S - 0.5) +
    0.50 * (x$C - 0.5) + 0.30 * x$B
}

## Generate one observed cohort. The split indicator is deliberately not drawn
## here. The driver draws it after all data variables, using fresh random values
## from the replicate stream owned by the harness.
gen_replicate <- function(scen, n = scen$n) {
  x <- draw_covariates(n)
  e <- treatment_probability(x)
  A <- stats::rbinom(n, 1, e)
  eta <- outcome_linear_predictor(x) +
    A * (scen$theta0 + scen$theta1 * x$Z)
  u_t <- stats::runif(n)
  T_event <- -log(u_t) / (scen$lambda * exp(eta))
  data.frame(x, A = A, T_event = T_event,
             time = pmin(T_event, 60), delta = as.integer(T_event <= 60),
             stringsAsFactors = FALSE)
}

## Calibrate the six baseline hazards on one separate, fixed 10,000,000-vector
## design draw. Under the null, treatment does not enter the event probability.
calibrate_lambdas <- function(n_draw = N_LAMBDA, chunk = 250000L) {
  q_parts <- vector("list", ceiling(n_draw / chunk))
  done <- 0L
  part <- 0L
  while (done < n_draw) {
    m <- min(chunk, n_draw - done)
    x <- draw_covariates(m)
    part <- part + 1L
    keep <- x$age >= 55
    q_parts[[part]] <- exp(outcome_linear_predictor(x)[keep])
    done <- done + m
  }
  q <- unlist(q_parts, use.names = FALSE)
  rows <- list()
  for (nn in N_LEVELS) {
    for (mm in EVENT_TARGETS) {
      target <- function(lambda) {
        nn * sum(-expm1(-lambda * 36 * q)) / n_draw - mm
      }
      root <- stats::uniroot(target, interval = c(1e-12, 0.1),
                             tol = 1e-12)$root
      rows[[length(rows) + 1L]] <- data.frame(
        n = nn, event_target = mm, lambda = root,
        calibration_draws = n_draw, stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, rows)
}

## Enumerate every candidate truth with common covariate draws for both
## strategies. Each extension adds the same number of observations to all 200
## batches, so the current total is always divided into exactly 200 batches.
truth_for <- function(scen, initial = N_TRUTH_START, step = N_TRUTH_STEP,
                      maximum = N_TRUTH_MAX, n_batches = TRUTH_BATCHES) {
  candidates <- candidate_library(16L)
  K <- nrow(candidates)
  sum0 <- matrix(0, n_batches, K)
  sum1 <- matrix(0, n_batches, K)
  eligible <- matrix(0, n_batches, K)
  total <- 0L

  repeat {
    add <- if (total == 0L) initial else step
    add <- min(add, maximum - total)
    stopifnot(add > 0L, add %% n_batches == 0L)
    per_batch <- add %/% n_batches

    for (b in seq_len(n_batches)) {
      x <- draw_covariates(per_batch)
      lp <- outcome_linear_predictor(x)
      q0 <- scen$lambda * exp(lp)
      q1 <- scen$lambda * exp(lp + scen$theta0 + scen$theta1 * x$Z)
      p0 <- outer(q0, HORIZONS_ALL, function(q, h) -expm1(-q * h))
      p1 <- outer(q1, HORIZONS_ALL, function(q, h) -expm1(-q * h))

      ## This loop is over at most 16 protocols, never over individuals.
      for (k in seq_len(K)) {
        use <- x$age >= candidates$c[k]
        hj <- match(candidates$h[k], HORIZONS_ALL)
        eligible[b, k] <- eligible[b, k] + sum(use)
        sum0[b, k] <- sum0[b, k] + sum(p0[use, hj])
        sum1[b, k] <- sum1[b, k] + sum(p1[use, hj])
      }
    }

    total <- total + add
    rd_batch <- sum1 / eligible - sum0 / eligible
    rd <- colSums(sum1) / colSums(eligible) -
      colSums(sum0) / colSums(eligible)
    mcse <- apply(rd_batch, 2, stats::sd) / sqrt(n_batches)
    if (all(mcse <= TRUTH_MCSE_MAX) || total >= maximum) break
  }

  data.frame(
    candidates[, c("candidate", "c", "h")],
    truth = rd,
    truth_mcse = mcse,
    truth_draws = total,
    truth_mcse_pass = mcse <= TRUTH_MCSE_MAX,
    stringsAsFactors = FALSE
  )
}

## Compute locked pre-run diagnostics from an independent design draw. Expected
## treatment-group sizes integrate over the treatment propensity. Correlations
## integrate over the Bernoulli treatment and outcome distributions.
design_diagnostics <- function(scenarios, n_draw = N_DIAGNOSTIC) {
  x <- draw_covariates(n_draw)
  e <- treatment_probability(x)
  lp <- outcome_linear_predictor(x)
  scores <- list(
    higher = score_higher(x$Z, x$S, x$C, x$B),
    reduced = score_reduced(x$Z, x$S, x$C, x$B)
  )
  truth_cells <- attach_lambdas(build_truth_scenarios(),
                                unique(scenarios[, c("n", "event_target", "lambda")]))
  candidates <- candidate_library(16L)
  base_rows <- list()

  for (i in seq_len(nrow(truth_cells))) {
    s <- truth_cells[i, , drop = FALSE]
    q0 <- s$lambda * exp(lp)
    q1 <- s$lambda * exp(lp + s$theta0 + s$theta1 * x$Z)
    p0 <- outer(q0, HORIZONS_ALL, function(q, h) -expm1(-q * h))
    p1 <- outer(q1, HORIZONS_ALL, function(q, h) -expm1(-q * h))

    for (k in seq_len(nrow(candidates))) {
      use <- x$age >= candidates$c[k]
      hj <- match(candidates$h[k], HORIZONS_ALL)
      py <- (1 - e) * p0[, hj] + e * p1[, hj]
      n_eligible <- sum(use)
      mean_y <- sum(py[use]) / n_eligible

      for (score_key in names(scores)) {
        r <- scores[[score_key]][use]
        py_use <- py[use]
        mean_r <- mean(r)
        var_r <- mean((r - mean_r)^2)
        var_y <- mean_y * (1 - mean_y)
        cov_ry <- mean(r * py_use) - mean_r * mean_y
        r2 <- if (var_r > 0 && var_y > 0) cov_ry^2 / (var_r * var_y) else NA_real_
        base_rows[[length(base_rows) + 1L]] <- data.frame(
          truth_scenario = s$truth_scenario,
          n = s$n, event_target = s$event_target, effect = s$effect,
          candidate = candidates$candidate[k], c = candidates$c[k],
          h = candidates$h[k], score_key = score_key,
          lambda = s$lambda,
          expected_eligible = s$n * n_eligible / n_draw,
          expected_treated = s$n * sum(e[use]) / n_draw,
          expected_control = s$n * sum(1 - e[use]) / n_draw,
          expected_events = s$n * sum(py[use]) / n_draw,
          distance_from_70 = s$n * sum(py[use]) / n_draw - 70,
          population_r2 = r2,
          diagnostic_draws = n_draw,
          stringsAsFactors = FALSE)
      }
    }
  }

  base <- do.call(rbind, base_rows)
  out <- list()
  for (i in seq_len(nrow(scenarios))) {
    s <- scenarios[i, , drop = FALSE]
    allowed <- candidate_library(s$K)$candidate
    d <- base[base$n == s$n & base$event_target == s$event_target &
                base$effect == s$effect & base$candidate %in% allowed, , drop = FALSE]
    d$scenario <- s$scenario
    d$K <- s$K
    d$analysis_scenario <- analysis_scenario_id(
      s$scenario, d$score_key)
    out[[i]] <- d
  }
  ans <- do.call(rbind, out)
  ans <- ans[order(ans$scenario, ans$score_key, ans$c, ans$h), ]
  rownames(ans) <- NULL
  ans
}
