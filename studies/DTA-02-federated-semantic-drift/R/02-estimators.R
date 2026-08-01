## DTA-02: site estimators, pooling, exact truths, and diagnostic gates.

canonical_q <- function(kappa = 0, gamma = 0) {
  mass <- numeric(nrow(X_GRID))
  for (j in seq_len(N_SITES)) {
    a <- mechanism_atoms(j, kappa, gamma)
    for (xx in X_GRID$x) {
      mass[[xx]] <- mass[[xx]] + sum(a$prob[a$x == xx & a$renal >= 1L]) / N_SITES
    }
  }
  stats::setNames(mass / sum(mass), as.character(X_GRID$x))
}

binary_sample_variance <- function(y, n) {
  if (!is.finite(n) || n <= 1) return(NA_real_)
  y * (n - y) / (n * (n - 1))
}

estimate_sites <- function(tab, q) {
  rows <- vector('list', N_SITES)
  for (j in seq_len(N_SITES)) {
    d <- tab[tab$site == j, ]
    nx <- vapply(X_GRID$x, function(xx) sum(d$n_elig[d$x == xx]), numeric(1))
    n1 <- vapply(X_GRID$x, function(xx) sum(d$n_elig[d$x == xx & d$arm == 1L]), numeric(1))
    n0 <- vapply(X_GRID$x, function(xx) sum(d$n_elig[d$x == xx & d$arm == 0L]), numeric(1))
    y1 <- vapply(X_GRID$x, function(xx) sum(d$n_elig[d$x == xx & d$arm == 1L] *
                                               d$event[d$x == xx & d$arm == 1L]), numeric(1))
    y0 <- vapply(X_GRID$x, function(xx) sum(d$n_elig[d$x == xx & d$arm == 0L] *
                                               d$event[d$x == xx & d$arm == 0L]), numeric(1))
    mu1 <- y1 / n1; mu0 <- y0 / n0
    delta <- mu1 - mu0
    represented <- nx > 0
    local_ok <- sum(nx) > 1 && all(n1[represented] >= 5) && all(n0[represented] >= 5)
    q_ok <- all(n1[q > 0] >= 5) && all(n0[q > 0] >= 5)

    theta_local <- v_local <- NA_real_
    if (local_ok) {
      ## Critique fix: p_jx is estimated from every locally eligible record
      ## before treatment-category exclusion. Excluded categories contribute the
      ## target-distribution term to the influence function.
      theta_local <- sum(nx / sum(nx) * delta)
      pi1 <- n1 / nx; pi0 <- n0 / nx
      phi <- delta[d$x] - theta_local
      a1 <- d$arm == 1L
      a0 <- d$arm == 0L
      phi[a1] <- phi[a1] + (d$event[a1] - mu1[d$x[a1]]) / pi1[d$x[a1]]
      phi[a0] <- phi[a0] - (d$event[a0] - mu0[d$x[a0]]) / pi0[d$x[a0]]
      w <- d$n_elig
      mphi <- sum(w * phi) / sum(w)
      v_local <- sum(w * (phi - mphi)^2) / ((sum(w) - 1) * sum(w))
      local_ok <- is.finite(theta_local) && is.finite(v_local) && v_local > 0
    }

    theta_q <- v_q <- NA_real_
    if (q_ok) {
      s1 <- mapply(binary_sample_variance, y1, n1)
      s0 <- mapply(binary_sample_variance, y0, n0)
      theta_q <- sum(q * delta)
      v_q <- sum(q^2 * (s1 / n1 + s0 / n0))
      q_ok <- is.finite(theta_q) && is.finite(v_q) && v_q > 0
    }
    rows[[j]] <- data.frame(
      site = j, theta_local = theta_local, v_local = v_local,
      theta_q = theta_q, v_q = v_q,
      local_ok = local_ok, q_ok = q_ok, n_eligible = sum(nx)
    )
  }
  do.call(rbind, rows)
}

exact_site_stats <- function(tab, q) {
  pex <- vapply(X_GRID$x, function(xx) sum(tab$n_elig[tab$x == xx]), numeric(1))
  p1 <- vapply(X_GRID$x, function(xx) sum(tab$n_elig[tab$x == xx & tab$arm == 1L]), numeric(1))
  p0 <- vapply(X_GRID$x, function(xx) sum(tab$n_elig[tab$x == xx & tab$arm == 0L]), numeric(1))
  y1 <- vapply(X_GRID$x, function(xx) sum(tab$n_elig[tab$x == xx & tab$arm == 1L] *
                                             tab$event[tab$x == xx & tab$arm == 1L]), numeric(1))
  y0 <- vapply(X_GRID$x, function(xx) sum(tab$n_elig[tab$x == xx & tab$arm == 0L] *
                                             tab$event[tab$x == xx & tab$arm == 0L]), numeric(1))
  mu1 <- y1 / p1; mu0 <- y0 / p0
  delta <- mu1 - mu0
  theta_local <- sum(pex / sum(pex) * delta)
  pi1 <- p1 / pex; pi0 <- p0 / pex
  phi <- delta[tab$x] - theta_local
  a1 <- tab$arm == 1L; a0 <- tab$arm == 0L
  phi[a1] <- phi[a1] + (tab$event[a1] - mu1[tab$x[a1]]) / pi1[tab$x[a1]]
  phi[a0] <- phi[a0] - (tab$event[a0] - mu0[tab$x[a0]]) / pi0[tab$x[a0]]
  mphi <- sum(tab$n_elig * phi) / sum(tab$n_elig)
  varphi <- sum(tab$n_elig * (phi - mphi)^2) / sum(tab$n_elig)
  v_local <- varphi / (N_PER_SITE * sum(tab$n_elig))

  theta_q <- sum(q * delta)
  v_q <- sum(q^2 * (mu1 * (1 - mu1) / (N_PER_SITE * p1) +
                         mu0 * (1 - mu0) / (N_PER_SITE * p0)))
  c(theta_local = theta_local, v_local = v_local,
    theta_q = theta_q, v_q = v_q)
}

fixed_pool <- function(theta, variance) {
  w <- 1 / variance
  c(est = sum(w * theta) / sum(w), var = 1 / sum(w))
}

heterogeneity_stats <- function(theta, variance) {
  w <- 1 / variance
  mu <- sum(w * theta) / sum(w)
  q <- sum(w * (theta - mu)^2)
  df <- length(theta) - 1L
  c(Q = q, p = stats::pchisq(q, df, lower.tail = FALSE),
    I2 = if (q > 0) max(0, (q - df) / q) else 0)
}

dl_pool <- function(theta, variance) {
  w <- 1 / variance
  h <- heterogeneity_stats(theta, variance)
  cden <- sum(w) - sum(w^2) / sum(w)
  if (!is.finite(cden) || cden <= 0) stop('invalid DerSimonian-Laird denominator')
  tau2 <- max(0, (h[['Q']] - length(theta) + 1) / cden)
  wr <- 1 / (variance + tau2)
  c(est = sum(wr * theta) / sum(wr), var = 1 / sum(wr), tau2 = tau2,
    Q = h[['Q']], I2 = h[['I2']], p = h[['p']])
}

pm_tau <- function(theta, variance) {
  k <- length(theta)
  score <- function(tau2) {
    w <- 1 / (variance + tau2)
    mu <- sum(w * theta) / sum(w)
    sum(w * (theta - mu)^2) - (k - 1)
  }
  if (score(0) <= 0) return(0)
  upper <- max(stats::var(theta), max(variance), 1e-8)
  while (score(upper) > 0 && upper < 1e6) upper <- upper * 2
  if (score(upper) > 0) stop('Paule-Mandel root was not bracketed')
  stats::uniroot(score, c(0, upper), tol = 1e-12)$root
}

pm_pool <- function(theta, variance) {
  tau2 <- pm_tau(theta, variance)
  w <- 1 / (variance + tau2)
  mu <- sum(w * theta) / sum(w)
  q <- sum(w * (theta - mu)^2)
  scale <- max(1, q / (length(theta) - 1L))
  c(est = mu, var = scale / sum(w), tau2 = tau2, Q = q)
}

method_row <- function(method, latent_est = NA_real_, variance = NA_real_,
                       critical = 1.96, release = FALSE, abstain = FALSE,
                       fail = NA_character_, tau2 = NA_real_, Q = NA_real_,
                       I2 = NA_real_, min_gate_p = NA_real_,
                       pass_mask = NA_character_, workload = NA_real_,
                       site_tp = NA_integer_, site_fp = NA_integer_,
                       site_tn = NA_integer_, site_fn = NA_integer_) {
  numeric_ok <- is.finite(latent_est) && is.finite(variance) && variance > 0
  if (!numeric_ok && is.na(fail) && !abstain) fail <- 'no-estimate'
  se0 <- if (numeric_ok) sqrt(variance) else NA_real_
  l0 <- if (numeric_ok) latent_est - critical * se0 else NA_real_
  h0 <- if (numeric_ok) latent_est + critical * se0 else NA_real_
  publish <- isTRUE(release) && numeric_ok && is.na(fail)
  data.frame(
    method = method, latent_est = latent_est, latent_se = se0,
    latent_lo = l0, latent_hi = h0,
    est = if (publish) latent_est else NA_real_,
    se = if (publish) se0 else NA_real_,
    lo = if (publish) l0 else NA_real_, hi = if (publish) h0 else NA_real_,
    release = publish, abstain = isTRUE(abstain), fail = fail,
    tau2 = tau2, Q = Q, I2 = I2, min_gate_p = min_gate_p,
    pass_mask = pass_mask, workload = workload,
    site_tp = site_tp, site_fp = site_fp, site_tn = site_tn, site_fn = site_fn,
    stringsAsFactors = FALSE
  )
}

site_confusion <- function(site_pass, affected) {
  flagged <- !site_pass
  truth <- seq_len(N_SITES) %in% affected
  c(tp = sum(flagged & truth), fp = sum(flagged & !truth),
    tn = sum(!flagged & !truth), fn = sum(!flagged & truth))
}

calibration_file <- function(dir, kappa, gamma, site, component) {
  file.path(dir, sprintf('k%02d-g%02d-site-%d-%s.rds',
                         as.integer(round(10 * kappa)),
                         as.integer(round(100 * gamma)), site, component))
}

component_expected <- function(site, kappa, gamma, component) {
  p <- mapping_probabilities(site, kappa, gamma, 'compatible', 1L)
  s <- component_summaries(p)[[component]]
  s <- s[s$site == site, , drop = FALSE]
  den <- ave(s$n, s$stratum, FUN = sum)
  s$conditional <- ifelse(den > 0, s$n / den, 0)
  s$mass <- s$n
  s
}

component_deviance <- function(observed, expected) {
  d <- merge(observed[, c('stratum', 'class', 'n')],
             expected[, c('stratum', 'class', 'conditional')],
             by = c('stratum', 'class'), all.x = TRUE)
  total <- ave(d$n, d$stratum, FUN = sum)
  ex <- total * d$conditional
  keep <- d$n > 0 & ex > 0
  2 * sum(d$n[keep] * log(d$n[keep] / ex[keep]))
}

calibrate_component <- function(site, kappa, gamma, component,
                                n_draw = N_CALIBRATION, chunk = 5000L) {
  e <- component_expected(site, kappa, gamma, component)
  probs <- e$mass
  other <- max(0, 1 - sum(probs))
  if (other > 1e-12) probs <- c(probs, other)
  stats <- numeric(n_draw)
  done <- 0L
  while (done < n_draw) {
    m <- min(chunk, n_draw - done)
    z <- stats::rmultinom(m, N_PER_SITE, probs)
    score <- numeric(m)
    for (st in unique(e$stratum)) {
      idx <- which(e$stratum == st)
      obs <- z[idx, , drop = FALSE]
      nt <- colSums(obs)
      ex <- e$conditional[idx] * rep(nt, each = length(idx))
      dim(ex) <- dim(obs)
      keep <- obs > 0 & ex > 0
      term <- matrix(0, nrow(obs), ncol(obs))
      term[keep] <- obs[keep] * log(obs[keep] / ex[keep])
      score <- score + 2 * colSums(term)
    }
    stats[done + seq_len(m)] <- score
    done <- done + m
  }
  sort(stats)
}

.calibration_cache <- new.env(parent = emptyenv())

calibrated_p <- function(statistic, path) {
  if (!file.exists(path)) return(NA_real_)
  if (is.null(.calibration_cache[[path]])) {
    .calibration_cache[[path]] <- readRDS(path)
  }
  ref <- .calibration_cache[[path]]
  (1 + length(ref) - findInterval(statistic, ref)) / (length(ref) + 1)
}

aggregate_gate <- function(tab, kappa, gamma, calibration_dir) {
  ## Critique fix: this gate compares each site with its own compatible expected
  ## vector. It never tests raw homogeneity across deliberately different sites.
  obs <- component_summaries(tab)
  detail <- list()
  site_pass <- rep(FALSE, N_SITES)
  available <- TRUE
  for (j in seq_len(N_SITES)) {
    p <- numeric(3L)
    names(p) <- c('eligibility', 'exposure', 'outcome')
    for (component in names(p)) {
      o <- obs[[component]][obs[[component]]$site == j, ]
      e <- component_expected(j, kappa, gamma, component)
      stat <- component_deviance(o, e)
      path <- calibration_file(calibration_dir, kappa, gamma, j, component)
      p[[component]] <- calibrated_p(stat, path)
      detail[[length(detail) + 1L]] <- data.frame(
        site = j, component = component, statistic = stat, p = p[[component]])
    }
    if (any(!is.finite(p))) {
      available <- FALSE
    } else {
      site_pass[[j]] <- all(stats::p.adjust(p, method = 'holm') >= 0.05)
    }
  }
  list(available = available, site_pass = site_pass,
       release = available && all(site_pass), detail = do.call(rbind, detail))
}

network_base <- function(tab, q, kappa, gamma, calibration_dir, affected) {
  sites <- estimate_sites(tab, q)
  rows <- list()

  if (all(sites$local_ok)) {
    fe <- fixed_pool(sites$theta_local, sites$v_local)
    h <- heterogeneity_stats(sites$theta_local, sites$v_local)
    dl <- dl_pool(sites$theta_local, sites$v_local)
    rows[['historical-fixed']] <- method_row('historical-fixed', fe[['est']], fe[['var']], release = TRUE)
    rows[['historical-dl']] <- method_row('historical-dl', dl[['est']], dl[['var']],
                                           release = TRUE, tau2 = dl[['tau2']],
                                           Q = dl[['Q']], I2 = dl[['I2']])
    gate_release <- h[['p']] >= 0.10 && h[['I2']] <= 0.50
    rows[['historical-q-gate']] <- method_row(
      'historical-q-gate', fe[['est']], fe[['var']], release = gate_release,
      abstain = !gate_release, Q = h[['Q']], I2 = h[['I2']])
  } else {
    for (m in c('historical-fixed', 'historical-dl', 'historical-q-gate')) {
      rows[[m]] <- method_row(m, fail = 'local-site-estimator')
    }
  }

  equal <- list(ok = FALSE, est = NA_real_, var = NA_real_)
  if (all(sites$q_ok)) {
    cq <- fixed_pool(sites$theta_q, sites$v_q)
    pm <- pm_pool(sites$theta_q, sites$v_q)
    equal <- list(ok = TRUE, est = mean(sites$theta_q),
                  var = sum(sites$v_q) / N_SITES^2)
    rows[['commonq-fixed']] <- method_row('commonq-fixed', cq[['est']], cq[['var']], release = TRUE)
    rows[['pm-hk']] <- method_row('pm-hk', pm[['est']], pm[['var']],
                                   critical = stats::qt(0.975, N_SITES - 1L),
                                   release = TRUE, tau2 = pm[['tau2']], Q = pm[['Q']])
    rows[['equalq']] <- method_row('equalq', equal$est, equal$var, release = TRUE)
  } else {
    for (m in c('commonq-fixed', 'pm-hk', 'equalq')) {
      rows[[m]] <- method_row(m, fail = 'commonq-site-estimator')
    }
  }

  agg <- aggregate_gate(tab, kappa, gamma, calibration_dir)
  conf <- site_confusion(agg$site_pass, affected)
  if (equal$ok) {
    minp <- if (agg$available) min(agg$detail$p) else NA_real_
    rows[['aggregate-gate']] <- method_row(
      'aggregate-gate', equal$est, equal$var,
      release = agg$release, abstain = !agg$release,
      min_gate_p = minp, pass_mask = paste(as.integer(agg$site_pass), collapse = ''),
      site_tp = conf[['tp']], site_fp = conf[['fp']],
      site_tn = conf[['tn']], site_fn = conf[['fn']])
  } else {
    rows[['aggregate-gate']] <- method_row('aggregate-gate', fail = 'commonq-site-estimator')
  }
  list(rows = rows, sites = sites, equal = equal, aggregate = agg)
}

validation_rows <- function(base, validation, affected) {
  rows <- list()
  for (target in VALIDATION_SIZES) {
    v <- validation$by_size[[as.character(target)]]
    pass <- v$site_pass
    conf <- site_confusion(pass, affected)
    method <- paste0('validation-', target)
    if (base$equal$ok) {
      rows[[method]] <- method_row(
        method, base$equal$est, base$equal$var,
        release = all(pass), abstain = !all(pass),
        pass_mask = paste(as.integer(pass), collapse = ''),
        workload = sum(v$workload),
        site_tp = conf[['tp']], site_fp = conf[['fp']],
        site_tn = conf[['tn']], site_fn = conf[['fn']])
    } else {
      rows[[method]] <- method_row(method, fail = 'commonq-site-estimator')
    }
  }

  v <- validation$by_size[['200']]
  pass <- v$site_pass
  keep <- which(pass)
  conf <- site_confusion(pass, affected)
  if (length(keep) >= 4L && all(base$sites$q_ok[keep])) {
    est <- mean(base$sites$theta_q[keep])
    variance <- sum(base$sites$v_q[keep]) / length(keep)^2
    rows[['site-exclusion-200']] <- method_row(
      'site-exclusion-200', est, variance, release = TRUE,
      pass_mask = paste(as.integer(pass), collapse = ''),
      workload = sum(v$workload),
      site_tp = conf[['tp']], site_fp = conf[['fp']],
      site_tn = conf[['tn']], site_fn = conf[['fn']])
  } else if (length(keep) < 4L) {
    rows[['site-exclusion-200']] <- method_row(
      'site-exclusion-200', abstain = TRUE,
      pass_mask = paste(as.integer(pass), collapse = ''),
      workload = sum(v$workload),
      site_tp = conf[['tp']], site_fp = conf[['fp']],
      site_tn = conf[['tn']], site_fn = conf[['fn']])
  } else {
    rows[['site-exclusion-200']] <- method_row(
      'site-exclusion-200', fail = 'included-site-estimator',
      pass_mask = paste(as.integer(pass), collapse = ''))
  }
  rows
}

truth_for_formal <- function(scen, q) {
  scenario_rows <- list(); site_rows <- list()
  for (pair_id in seq_along(AFFECTED_PAIRS)) {
    intended <- lapply(seq_len(N_SITES), function(j)
      exact_site_stats(mapping_probabilities(j, scen$kappa, scen$gamma,
                                             'compatible', pair_id), q))
    intended <- do.call(rbind, intended)
    psi <- mean(intended[, 'theta_q'])

    mapped <- lapply(seq_len(N_SITES), function(j)
      exact_site_stats(mapping_probabilities(j, scen$kappa, scen$gamma,
                                             scen$mapping, pair_id), q))
    mapped <- do.call(rbind, mapped)
    fe <- fixed_pool(mapped[, 'theta_local'], mapped[, 'v_local'])
    dl <- dl_pool(mapped[, 'theta_local'], mapped[, 'v_local'])
    cq <- fixed_pool(mapped[, 'theta_q'], mapped[, 'v_q'])
    pm <- pm_pool(mapped[, 'theta_q'], mapped[, 'v_q'])
    equal <- mean(mapped[, 'theta_q'])

    ## Critique fix: inverse-variance and random-effects methods are evaluated
    ## against their exact method-specific functionals. Their discrepancies from
    ## the equal-site scientific target are separate columns.
    target <- c(
      'historical-fixed' = fe[['est']], 'historical-dl' = dl[['est']],
      'historical-q-gate' = fe[['est']], 'commonq-fixed' = cq[['est']],
      'pm-hk' = pm[['est']], 'equalq' = equal,
      'aggregate-gate' = equal, 'validation-50' = equal,
      'validation-100' = equal, 'validation-200' = equal,
      'site-exclusion-200' = NA_real_
    )
    scenario_rows[[pair_id]] <- data.frame(
      formal_scenario = scen$formal_scenario, pair_id = pair_id,
      method = names(target), own_target = unname(target), psi = psi,
      mapped_equal = equal, exact_change = equal - psi,
      functional_discrepancy = unname(target) - psi,
      stringsAsFactors = FALSE
    )
    site_rows[[pair_id]] <- data.frame(
      formal_scenario = scen$formal_scenario, pair_id = pair_id,
      site = seq_len(N_SITES), theta_local = mapped[, 'theta_local'],
      v_local = mapped[, 'v_local'], theta_q = mapped[, 'theta_q'],
      v_q = mapped[, 'v_q'], intended_theta_q = intended[, 'theta_q'],
      stringsAsFactors = FALSE
    )
  }
  list(scenario = do.call(rbind, scenario_rows), site = do.call(rbind, site_rows))
}
