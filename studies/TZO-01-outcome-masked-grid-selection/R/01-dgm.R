## Study TZO-01: data-generating mechanism and coarsening operator.

expit <- function(x) {
  out <- numeric(length(x))
  pos <- x >= 0
  out[pos] <- 1 / (1 + exp(-x[pos]))
  z <- exp(x[!pos])
  out[!pos] <- z / (1 + z)
  out
}

rtrunc_age <- function(n) {
  out <- numeric(n)
  open <- seq_len(n)
  while (length(open)) {
    draw <- stats::rnorm(length(open), 60, 10)
    keep <- draw >= 40 & draw <= 80
    out[open[keep]] <- draw[keep]
    open <- open[!keep]
  }
  out
}

first_true_column <- function(x) {
  any <- rowSums(x) > 0L
  first <- max.col(x, ties.method = 'first')
  ifelse(any, first, NA_integer_)
}

## Integral of exp(slope * u) from zero through x.
linear_exponential_integral <- function(x, slope) {
  x <- pmax(x, 0)
  out <- x
  nz <- abs(slope) > 1e-12
  out[nz] <- expm1(slope[nz] * x[nz]) / slope[nz]
  out
}

log_hr_value <- function(profile, s, comorbidity) {
  s <- pmax(s, 0)
  if (profile == 'exact-null') return(rep(0, length(s)))
  if (profile == 'immediate-benefit') {
    return(ifelse(comorbidity == 0L, log(0.60), log(0.80)))
  }
  if (profile == 'biphasic') {
    harm <- ifelse(comorbidity == 0L, log(1.40), log(1.60))
    benefit <- ifelse(comorbidity == 0L, log(0.55), log(0.75))
    return(ifelse(s < 2, harm, ifelse(s < 6, 0, benefit)))
  }
  if (profile == 'delayed-smooth') {
    target <- ifelse(comorbidity == 0L, log(0.60), log(0.80))
    return(ifelse(s <= 4, 0, ifelse(s < 10, target * (s - 4) / 6, target)))
  }
  if (profile == 'negligible-smooth') {
    target <- ifelse(comorbidity == 0L, log(0.95), log(0.98))
    return(ifelse(s < 8, target * s / 8, target))
  }
  if (profile == 'off-grid') {
    d10 <- 10 / 7
    d17 <- 17 / 7
    d31 <- 31 / 7
    d45 <- 45 / 7
    harm <- ifelse(comorbidity == 0L, log(1.20), log(1.30))
    benefit <- ifelse(comorbidity == 0L, log(0.70), log(0.85))
    return(ifelse(
      s <= d10, 0,
      ifelse(s < d17, harm * (s - d10) / (d17 - d10),
             ifelse(s <= d31, harm,
                    ifelse(s < d45,
                           harm + (benefit - harm) * (s - d31) / (d45 - d31),
                           benefit)))
    ))
  }
  stop('unknown outcome profile: ', profile)
}

## Cumulative integral of the treatment hazard-ratio multiplier from initiation
## through time s. This preserves the day 10, 17, 31, and 45 knots exactly.
cumulative_hr_multiplier <- function(profile, s, comorbidity) {
  s <- pmax(s, 0)
  if (profile == 'exact-null') return(s)
  if (profile == 'immediate-benefit') {
    hr <- ifelse(comorbidity == 0L, 0.60, 0.80)
    return(hr * s)
  }
  if (profile == 'biphasic') {
    harm <- ifelse(comorbidity == 0L, 1.40, 1.60)
    benefit <- ifelse(comorbidity == 0L, 0.55, 0.75)
    return(harm * pmin(s, 2) + pmax(pmin(s, 6) - 2, 0) +
             benefit * pmax(s - 6, 0))
  }
  if (profile == 'delayed-smooth') {
    target <- ifelse(comorbidity == 0L, log(0.60), log(0.80))
    u <- pmax(pmin(s, 10) - 4, 0)
    slope <- target / 6
    middle <- linear_exponential_integral(u, slope)
    full_middle <- linear_exponential_integral(rep(6, length(s)), slope)
    return(pmin(s, 4) + middle + exp(target) * pmax(s - 10, 0) +
             ifelse(s > 10, full_middle - middle, 0))
  }
  if (profile == 'negligible-smooth') {
    target <- ifelse(comorbidity == 0L, log(0.95), log(0.98))
    u <- pmin(s, 8)
    slope <- target / 8
    return(linear_exponential_integral(u, slope) +
             exp(target) * pmax(s - 8, 0))
  }
  if (profile == 'off-grid') {
    d10 <- 10 / 7
    d17 <- 17 / 7
    d31 <- 31 / 7
    d45 <- 45 / 7
    harm <- ifelse(comorbidity == 0L, log(1.20), log(1.30))
    benefit <- ifelse(comorbidity == 0L, log(0.70), log(0.85))
    u1 <- pmax(pmin(s, d17) - d10, 0)
    slope1 <- harm / (d17 - d10)
    part1 <- linear_exponential_integral(u1, slope1)
    part1_full <- linear_exponential_integral(rep(d17 - d10, length(s)), slope1)
    u2 <- pmax(pmin(s, d45) - d31, 0)
    slope2 <- (benefit - harm) / (d45 - d31)
    part2 <- exp(harm) * linear_exponential_integral(u2, slope2)
    part2_full <- exp(harm) *
      linear_exponential_integral(rep(d45 - d31, length(s)), slope2)
    out <- pmin(s, d10) + part1
    out <- out + ifelse(s > d17, part1_full - part1, 0)
    out <- out + exp(harm) * pmax(pmin(s, d31) - d17, 0)
    out <- out + part2
    out <- out + ifelse(s > d45, part2_full - part2, 0)
    out + exp(benefit) * pmax(s - d45, 0)
  } else {
    stop('unknown outcome profile: ', profile)
  }
}

gen_process <- function(scen, n) {
  age <- rtrunc_age(n)
  xage <- (age - 60) / 10
  female <- stats::rbinom(n, 1, 0.50)
  comorbidity <- stats::rbinom(n, 1, 0.35)
  state0 <- stats::rnorm(n, 0.30 * xage + 0.40 * comorbidity - 0.20 * female, 1)
  marker0 <- state0 + stats::rnorm(n, 0, 0.15)

  state <- matrix(NA_real_, n, N_WEEKS)
  marker_boundary <- matrix(NA_real_, n, N_WEEKS + 1L)
  marker_boundary[, 1L] <- marker0
  visits <- matrix(FALSE, n, N_WEEKS)
  visit_time <- matrix(NA_real_, n, N_WEEKS)
  p_start <- matrix(NA_real_, n, N_WEEKS)
  start_hit <- matrix(FALSE, n, N_WEEKS)

  u_start <- matrix(stats::runif(n * N_WEEKS), n, N_WEEKS)
  u_visit <- matrix(stats::runif(n * N_WEEKS), n, N_WEEKS)
  u_visit_time <- matrix(stats::runif(n * N_WEEKS, 0.05, 0.95), n, N_WEEKS)
  state_error <- matrix(stats::rnorm(n * N_WEEKS, 0, 0.35), n, N_WEEKS)
  marker_error <- matrix(stats::rnorm(n * N_WEEKS, 0, 0.15), n, N_WEEKS)

  current_state <- state0
  current_marker <- marker0
  prior_visit <- numeric(n)
  weeks_since_visit <- numeric(n)

  for (j in seq_len(N_WEEKS)) {
    k <- j - 1L
    lp_a <- scen$alphaA + 0.75 * current_marker + 0.35 * comorbidity +
      0.20 * xage - 0.15 * female + 0.30 * prior_visit + 0.20 * k / 52
    p <- -expm1(-exp(pmin(lp_a, 30)))
    p <- pmin(pmax(p, 1e-10), 1 - 1e-10)
    p_start[, j] <- p
    start_hit[, j] <- u_start[, j] < p

    next_state <- 0.90 * current_state + 0.05 * xage +
      0.08 * comorbidity - 0.04 * female + state_error[, j]
    lp_v <- scen$alphaV + 0.35 * comorbidity + 0.25 * female +
      0.35 * pmax(current_marker, 0) + 0.12 * pmin(weeks_since_visit, 12) +
      0.10 * sin(2 * pi * k / 52)
    visited <- u_visit[, j] < expit(lp_v)
    visits[, j] <- visited
    visit_time[visited, j] <- k + u_visit_time[visited, j]
    current_marker <- ifelse(visited, next_state + marker_error[, j], current_marker)
    weeks_since_visit <- ifelse(visited, 0, weeks_since_visit + 1)
    prior_visit <- as.numeric(visited)
    current_state <- next_state
    state[, j] <- current_state
    marker_boundary[, j + 1L] <- current_marker
  }

  first <- first_true_column(start_hit)
  natural_start <- ifelse(is.na(first), Inf, first - 1L)
  list(
    n = n,
    baseline = data.frame(
      id = seq_len(n), age = age, xage = xage, female = female,
      comorbidity = comorbidity, state0 = state0, marker0 = marker0
    ),
    state = state,
    marker_boundary = marker_boundary,
    visits = visits,
    visit_time = visit_time,
    p_start = p_start,
    start_hit = start_hit,
    natural_start = natural_start
  )
}

combine_process <- function(a, b) {
  stopifnot(N_WEEKS == ncol(a$state), N_WEEKS == ncol(b$state))
  base <- rbind(a$baseline, b$baseline)
  base$id <- seq_len(nrow(base))
  list(
    n = a$n + b$n,
    baseline = base,
    state = rbind(a$state, b$state),
    marker_boundary = rbind(a$marker_boundary, b$marker_boundary),
    visits = rbind(a$visits, b$visits),
    visit_time = rbind(a$visit_time, b$visit_time),
    p_start = rbind(a$p_start, b$p_start),
    start_hit = rbind(a$start_hit, b$start_hit),
    natural_start = c(a$natural_start, b$natural_start)
  )
}

regime_start <- function(proc, G, arm) {
  weeks <- 0:(N_WEEKS - 1L)
  if (arm == 'early') {
    before <- which(weeks < G)
    first <- first_true_column(proc$start_hit[, before, drop = FALSE])
    observed <- ifelse(is.na(first), Inf, weeks[before][first])
    return(ifelse(is.finite(observed), observed, G))
  }
  if (arm == 'delay') {
    after <- which(weeks >= G)
    first <- first_true_column(proc$start_hit[, after, drop = FALSE])
    return(ifelse(is.na(first), Inf, weeks[after][first]))
  }
  stop('unknown regime arm: ', arm)
}

hazard_increments <- function(proc, profile, start_week = proc$natural_start) {
  n <- proc$n
  weeks <- 0:(N_WEEKS - 1L)
  base_lp <- matrix(
    -6.10 + 0.30 * proc$baseline$xage + 0.40 * proc$baseline$comorbidity -
      0.20 * proc$baseline$female,
    n, N_WEEKS
  ) + 0.55 * proc$state + matrix(0.15 * weeks / 52, n, N_WEEKS, byrow = TRUE)
  multiplier <- matrix(1, n, N_WEEKS)
  for (j in seq_len(N_WEEKS)) {
    k <- j - 1L
    treated <- is.finite(start_week) & k >= start_week
    if (any(treated)) {
      s0 <- k - start_week[treated]
      c0 <- proc$baseline$comorbidity[treated]
      multiplier[treated, j] <-
        cumulative_hr_multiplier(profile, s0 + 1, c0) -
        cumulative_hr_multiplier(profile, s0, c0)
    }
  }
  exp(base_lp) * multiplier
}

conditional_risk <- function(proc, profile, start_week) {
  1 - exp(-rowSums(hazard_increments(proc, profile, start_week)))
}

gen_outcomes <- function(proc) {
  threshold <- stats::rexp(proc$n)
  out <- matrix(NA_real_, proc$n, length(OUTCOME_PROFILES),
                dimnames = list(NULL, OUTCOME_PROFILES))
  for (profile in OUTCOME_PROFILES) {
    H <- hazard_increments(proc, profile, proc$natural_start)
    cumulative <- H
    if (N_WEEKS > 1L) {
      for (j in 2:N_WEEKS) cumulative[, j] <- cumulative[, j - 1L] + H[, j]
    }
    hit <- cumulative >= threshold
    first <- first_true_column(hit)
    ids <- which(!is.na(first))
    if (!length(ids)) next
    j <- first[ids]
    k <- j - 1L
    previous <- ifelse(j == 1L, 0, cumulative[cbind(ids, pmax(j - 1L, 1L))])
    residual <- threshold[ids] - previous
    increment <- H[cbind(ids, j)]
    fraction <- pmin(pmax(residual / increment, 0), 1)
    treated <- is.finite(proc$natural_start[ids]) & k >= proc$natural_start[ids]
    if (any(treated)) {
      ii <- ids[treated]
      kk <- k[treated]
      s0 <- kk - proc$natural_start[ii]
      cc <- proc$baseline$comorbidity[ii]
      total_multiplier <- cumulative_hr_multiplier(profile, s0 + 1, cc) -
        cumulative_hr_multiplier(profile, s0, cc)
      target_multiplier <- residual[treated] * total_multiplier / increment[treated]
      x <- s0 + fraction[treated]
      lower <- s0
      upper <- s0 + 1
      base_cumulative <- cumulative_hr_multiplier(profile, s0, cc)
      for (iteration in seq_len(8L)) {
        value <- cumulative_hr_multiplier(profile, x, cc) - base_cumulative -
          target_multiplier
        derivative <- exp(log_hr_value(profile, x, cc))
        x <- pmin(pmax(x - value / derivative, lower), upper)
      }
      fraction[treated] <- x - s0
    }
    out[ids, profile] <- k + fraction
  }
  out
}

panel_boundaries <- function(delta, G) {
  sort(unique(c(seq.int(0L, N_WEEKS, by = delta), G, N_WEEKS)))
}

make_panel <- function(proc, delta, G) {
  ## Critique fix: each candidate receives a genuinely coarsened treatment,
  ## visit, marker, and outcome clock. Exact weekly fields remain outside the
  ## returned estimator data, except for the labeled oracle probability.
  b <- panel_boundaries(delta, G)
  nb <- length(b)
  n <- proc$n
  status <- outer(proc$natural_start, b, '<=')
  storage.mode(status) <- 'logical'
  marker <- proc$marker_boundary[, b + 1L, drop = FALSE]
  prior_visit <- matrix(FALSE, n, nb)
  visit_count <- matrix(0L, n, nb - 1L)
  for (j in seq_len(nb - 1L)) {
    weeks <- (b[j] + 1L):b[j + 1L]
    visit_weeks <- b[j]:(b[j + 1L] - 1L)
    visit_count[, j] <- rowSums(proc$visits[, visit_weeks + 1L, drop = FALSE])
    prior_visit[, j + 1L] <- visit_count[, j] > 0L
  }
  elapsed <- matrix(0L, n, nb)
  if (nb > 1L) {
    for (j in 2:nb) {
      elapsed[, j] <- ifelse(prior_visit[, j], 0L, elapsed[, j - 1L] + 1L)
    }
  }

  predictor_marker <- matrix(NA_real_, n, nb)
  predictor_visit <- matrix(FALSE, n, nb)
  predictor_elapsed <- matrix(0L, n, nb)
  predictor_marker[, 1L] <- marker[, 1L]
  if (nb > 1L) {
    predictor_marker[, 2:nb] <- marker[, 1:(nb - 1L), drop = FALSE]
    predictor_visit[, 2:nb] <- prior_visit[, 1:(nb - 1L), drop = FALSE]
    predictor_elapsed[, 2:nb] <- elapsed[, 1:(nb - 1L), drop = FALSE]
  }

  transition <- matrix(FALSE, n, nb)
  transition[, 1L] <- status[, 1L]
  if (nb > 1L) transition[, 2:nb] <- status[, 2:nb] & !status[, 1:(nb - 1L)]
  eligible <- matrix(TRUE, n, nb)
  if (nb > 1L) eligible[, 2:nb] <- !status[, 1:(nb - 1L)]
  ## The last boundary is the end of follow-up, not a decision: no outcome
  ## interval follows it, so no weight uses it (protocol: status at t_j defines
  ## the risk set for (t_j, t_j+1]). On the weekly grid nobody can initiate
  ## there, its period intercept diverged, and the initiation model failed in
  ## every replicate, taking the full-history, one-week and selected methods
  ## with it.
  eligible[, nb] <- FALSE

  oracle_p <- matrix(NA_real_, n, nb)
  oracle_p[, 1L] <- proc$p_start[, 1L]
  if (nb > 1L) {
    for (j in 2:nb) {
      weeks <- (b[j - 1L] + 1L):b[j]
      ## `marker_boundary` is boundary-indexed and has N_WEEKS + 1 columns, so
      ## it is read at `b + 1`. `p_start` is interval-indexed: column j is the
      ## start probability for week j, and there are N_WEEKS of them bounded by
      ## N_WEEKS + 1 boundaries. Reading it at `weeks + 1` treated it as
      ## boundary-indexed too and ran one column past the end on the last
      ## interval, which is why the study died before generating anything.
      p <- proc$p_start[, weeks, drop = FALSE]
      oracle_p[, j] <- -expm1(rowSums(log1p(-p)))
    }
  }
  oracle_p <- pmin(pmax(oracle_p, 1e-10), 1 - 1e-10)

  start_in_bin <- status[, 2:nb, drop = FALSE] & !status[, 1:(nb - 1L), drop = FALSE]
  event_count <- visit_count + start_in_bin
  nonempty <- event_count > 0L

  list(
    n = n,
    delta = delta,
    G = G,
    boundaries = b,
    status = status,
    transition = transition,
    eligible = eligible,
    marker = marker,
    prior_visit = prior_visit,
    elapsed = elapsed,
    predictor_marker = predictor_marker,
    predictor_visit = predictor_visit,
    predictor_elapsed = predictor_elapsed,
    oracle_p = oracle_p,
    visit_count = visit_count,
    start_in_bin = start_in_bin,
    alias_multiple = nonempty & event_count > 1L,
    alias_marker_treatment = nonempty & visit_count > 0L & start_in_bin,
    nonempty = nonempty,
    baseline = proc$baseline
  )
}

init_data <- function(panel) {
  n <- panel$n
  nb <- length(panel$boundaries)
  index <- which(panel$eligible)
  id <- ((index - 1L) %% n) + 1L
  period <- ((index - 1L) %/% n) + 1L
  xage <- rep(panel$baseline$xage, nb)[index]
  female <- rep(panel$baseline$female, nb)[index]
  comorbidity <- rep(panel$baseline$comorbidity, nb)[index]
  marker <- as.vector(panel$predictor_marker)[index]
  prior_visit <- as.numeric(as.vector(panel$predictor_visit)[index])
  elapsed <- as.numeric(as.vector(panel$predictor_elapsed)[index])
  x <- cbind(
    xage = xage,
    female = female,
    comorbidity = comorbidity,
    marker = marker,
    prior_visit = prior_visit,
    elapsed_intervals = elapsed,
    xage_comorbidity = xage * comorbidity,
    female_comorbidity = female * comorbidity
  )
  row_index <- matrix(NA_integer_, n, nb)
  row_index[index] <- seq_along(index)
  widths <- c(1, diff(panel$boundaries))
  list(
    id = id,
    period = period,
    x = x,
    y = as.numeric(panel$transition[index]),
    oracle_p = panel$oracle_p[index],
    width = widths[period],
    n = n,
    ## One intercept per decision boundary; the terminal boundary has none.
    n_period = nb - 1L,
    row_index = row_index
  )
}
