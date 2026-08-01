## DTA-02: exact mechanism and sufficient-statistic generator.
##
## Source records are never allocated in the main simulation. One multinomial
## draw per site generates counts over X, U, renal category, treatment category,
## and multinomial outcome. Loops below range over six sites or finite cells,
## never over individuals.

expit <- function(x) 1 / (1 + exp(-x))
bern_mass <- function(x, p) ifelse(x == 1L, p, 1 - p)

X_GRID <- expand.grid(x1 = 0:1, x2 = 0:1, x3 = 0:1)
X_GRID$x <- seq_len(nrow(X_GRID))

xu_distribution <- function(site) {
  s <- SITE_CONTEXT[[site]]
  g <- X_GRID[rep(seq_len(nrow(X_GRID)), each = 2L), ]
  g$u <- rep(0:1, times = nrow(X_GRID))
  p1 <- expit(-0.20 + 0.45 * s)
  p2 <- expit(0.10 - 0.15 * s)
  p3 <- expit(-0.80 + 0.70 * g$x1 - 0.20 * g$x2 + 0.25 * s)
  pu <- expit(-1.00 + 0.40 * g$x1 + 0.60 * g$x3)
  g$prob <- bern_mass(g$x1, p1) * bern_mass(g$x2, p2) *
    bern_mass(g$x3, p3) * bern_mass(g$u, pu)
  g
}

.atom_cache <- new.env(parent = emptyenv())

mechanism_atoms <- function(site, kappa, gamma) {
  key <- paste(site, kappa, gamma, sep = '|')
  if (!is.null(.atom_cache[[key]])) return(.atom_cache[[key]])

  xu <- xu_distribution(site)
  g <- expand.grid(
    row = seq_len(nrow(xu)), renal = 0:2, d = 0:3, outcome = 0:2,
    KEEP.OUT.ATTRS = FALSE
  )
  z <- xu[g$row, ]
  s <- SITE_CONTEXT[[site]]

  mean_g <- 75 - 10 * z$x1 - 12 * z$x3 - 10 * z$u
  c45 <- stats::pnorm((45 - mean_g) / 12)
  c60 <- stats::pnorm((60 - mean_g) / 12)
  pr <- cbind(c45, c60 - c45, 1 - c60)

  pq <- expit(-0.35 + 0.35 * s + 0.30 * z$x1 - 0.20 * z$x2 + 0.50 * z$x3)
  pd <- cbind(1 - pq, 0.60 * pq, 0.20 * pq, 0.20 * pq)

  base <- expit(-1.80 + 0.35 * z$x1 + 0.20 * z$x2 + 0.55 * z$x3 +
                  0.30 * kappa * z$u + 0.05 * s)
  delta1 <- -0.06 - kappa * (0.03 * z$x3 + 0.06 * z$u) + gamma * s
  delta <- ifelse(g$d == 0L, 0,
                  ifelse(g$d == 1L, delta1,
                         ifelse(g$d == 2L, delta1 + 0.12 * kappa, 0.02)))
  py <- base + delta
  pw0 <- expit(-3.00 + 0.20 * z$x1 + 0.10 * z$x3)
  pw <- pw0 + ifelse(g$d == 1L, 0.06 * kappa,
                     ifelse(g$d == 2L, 0.02 * kappa,
                            ifelse(g$d == 3L, 0.08 * kappa, 0)))
  if (any(py <= 0 | pw <= 0 | py + pw >= 1)) {
    stop('outcome probability outside the prespecified multinomial simplex')
  }
  po <- ifelse(g$outcome == 1L, py,
               ifelse(g$outcome == 2L, pw, 1 - py - pw))

  out <- data.frame(
    site = site, x = z$x, x1 = z$x1, x2 = z$x2, x3 = z$x3,
    u = z$u, renal = g$renal, d = g$d, outcome = g$outcome,
    prob = z$prob * pr[cbind(seq_len(nrow(g)), g$renal + 1L)] *
      pd[cbind(seq_len(nrow(g)), g$d + 1L)] * po,
    stringsAsFactors = FALSE
  )
  out$prob <- out$prob / sum(out$prob)
  .atom_cache[[key]] <- out
  out
}

gen_base_counts <- function(scen, n = N_PER_SITE) {
  out <- vector('list', N_SITES)
  for (j in seq_len(N_SITES)) {
    a <- mechanism_atoms(j, scen$kappa, scen$gamma)
    a$n <- as.integer(stats::rmultinom(1L, n, a$prob))
    out[[j]] <- a
  }
  do.call(rbind, out)
}

rmvhyper_counts <- function(sizes, draw) {
  sizes <- as.integer(sizes)
  draw <- as.integer(draw)
  ans <- integer(length(sizes))
  if (!length(sizes) || draw <= 0L) return(ans)
  if (draw >= sum(sizes)) return(sizes)
  left <- draw
  total <- sum(sizes)
  if (length(sizes) > 1L) {
    for (i in seq_len(length(sizes) - 1L)) {
      ans[[i]] <- stats::rhyper(1L, sizes[[i]], total - sizes[[i]], left)
      left <- left - ans[[i]]
      total <- total - sizes[[i]]
    }
  }
  ans[[length(sizes)]] <- left
  ans
}

reference_exposure <- function(d) {
  ifelse(d == 0L, 0L, ifelse(d == 1L, 1L, 2L))
}

apply_mapping_counts <- function(tab, mapping, pair_id) {
  affected <- affected_sites(mapping, pair_id)
  tab$e_ref <- as.integer(tab$renal >= 1L)
  tab$n_elig <- tab$n * tab$e_ref

  if (mapping == 'eligibility-visible' && length(affected)) {
    hit <- tab$site %in% affected
    tab$n_elig[hit] <- tab$n[hit] * as.integer(tab$renal[hit] == 2L)
  }

  if (mapping == 'eligibility-stealth' && length(affected)) {
    for (j in affected) {
      for (xx in X_GRID$x) {
        idx <- which(tab$site == j & tab$x == xx)
        target <- sum(tab$n[idx] * tab$e_ref[idx])
        tab$n_elig[idx] <- 0L
        i1 <- idx[tab$u[idx] == 1L]
        i0 <- idx[tab$u[idx] == 0L]
        take1 <- min(target, sum(tab$n[i1]))
        if (length(i1)) tab$n_elig[i1] <- rmvhyper_counts(tab$n[i1], take1)
        take0 <- target - take1
        if (length(i0)) tab$n_elig[i0] <- rmvhyper_counts(tab$n[i0], take0)
      }
    }
  }

  tab$arm <- ifelse(tab$d == 0L, 0L, ifelse(tab$d == 1L, 1L, -1L))
  if (mapping == 'exposure-broad' && length(affected)) {
    hit <- tab$site %in% affected
    tab$arm[hit] <- ifelse(tab$d[hit] == 0L, 0L,
                           ifelse(tab$d[hit] %in% c(1L, 2L), 1L, -1L))
  }
  tab$prod_class <- ifelse(tab$arm < 0L, 2L, tab$arm)

  tab$event <- as.integer(tab$outcome == 1L)
  if (mapping == 'outcome-broad' && length(affected)) {
    hit <- tab$site %in% affected
    tab$event[hit] <- as.integer(tab$outcome[hit] %in% c(1L, 2L))
  }
  ## Critique fix: the permutation is an identifiability control. Estimation
  ## summaries remain exactly unchanged. Only row-level validation sees the
  ## permuted labels, so it cannot support a different-estimand claim.
  tab
}

mapping_probabilities <- function(site, kappa, gamma, mapping, pair_id) {
  tab <- mechanism_atoms(site, kappa, gamma)
  affected <- affected_sites(mapping, pair_id)
  tab$e_ref <- as.integer(tab$renal >= 1L)
  tab$select_prob <- tab$e_ref

  if (mapping == 'eligibility-visible' && site %in% affected) {
    tab$select_prob <- as.numeric(tab$renal == 2L)
  }
  if (mapping == 'eligibility-stealth' && site %in% affected) {
    for (xx in X_GRID$x) {
      idx <- which(tab$x == xx)
      px <- sum(tab$prob[idx])
      pe <- sum(tab$prob[idx] * tab$e_ref[idx]) / px
      pu1 <- sum(tab$prob[idx] * tab$u[idx]) / px
      r1 <- if (pu1 > 0) min(1, pe / pu1) else 0
      r0 <- if (pu1 < 1) max(0, (pe - pu1) / (1 - pu1)) else 0
      tab$select_prob[idx] <- ifelse(tab$u[idx] == 1L, r1, r0)
    }
  }
  tab$n <- tab$prob
  tab$n_elig <- tab$prob * tab$select_prob
  tab$arm <- ifelse(tab$d == 0L, 0L, ifelse(tab$d == 1L, 1L, -1L))
  if (mapping == 'exposure-broad' && site %in% affected) {
    tab$arm <- ifelse(tab$d == 0L, 0L,
                      ifelse(tab$d %in% c(1L, 2L), 1L, -1L))
  }
  tab$prod_class <- ifelse(tab$arm < 0L, 2L, tab$arm)
  tab$event <- as.integer(tab$outcome == 1L)
  if (mapping == 'outcome-broad' && site %in% affected) {
    tab$event <- as.integer(tab$outcome %in% c(1L, 2L))
  }
  tab
}

fill_component <- function(z, grid) {
  out <- merge(grid, z, by = intersect(names(grid), names(z)), all.x = TRUE)
  out$n[is.na(out$n)] <- 0
  out
}

component_summaries <- function(tab) {
  sites <- sort(unique(tab$site))

  e1 <- aggregate(tab$n_elig, list(site = tab$site, stratum = as.character(tab$x)), sum)
  names(e1)[3] <- 'n'; e1$class <- 1L
  e0 <- aggregate(tab$n - tab$n_elig,
                  list(site = tab$site, stratum = as.character(tab$x)), sum)
  names(e0)[3] <- 'n'; e0$class <- 0L
  elig <- rbind(e0, e1)
  elig <- fill_component(elig, expand.grid(
    site = sites, stratum = as.character(X_GRID$x), class = 0:1,
    stringsAsFactors = FALSE))

  expo <- aggregate(tab$n_elig,
                    list(site = tab$site, stratum = as.character(tab$x),
                         class = tab$prod_class), sum)
  names(expo)[4] <- 'n'
  expo <- fill_component(expo, expand.grid(
    site = sites, stratum = as.character(X_GRID$x), class = 0:2,
    stringsAsFactors = FALSE))

  refd <- reference_exposure(tab$d)
  ostratum <- paste(tab$x, refd, sep = ':')
  outcome <- aggregate(tab$n_elig,
                       list(site = tab$site, stratum = ostratum,
                            class = tab$event), sum)
  names(outcome)[4] <- 'n'
  outcome <- fill_component(outcome, expand.grid(
    site = sites,
    stratum = as.vector(outer(as.character(X_GRID$x), 0:2, paste, sep = ':')),
    class = 0:1, stringsAsFactors = FALSE))

  list(eligibility = elig, exposure = expo, outcome = outcome)
}

basic_contingencies <- function(tab, mapping, pair_id) {
  affected <- affected_sites(mapping, pair_id)

  e1 <- aggregate(tab$n_elig,
                  list(site = tab$site, pred = 1L, true = tab$e_ref), sum)
  e0 <- aggregate(tab$n - tab$n_elig,
                  list(site = tab$site, pred = 0L, true = tab$e_ref), sum)
  names(e1)[4] <- names(e0)[4] <- 'n'
  eligibility <- rbind(e0, e1)
  eligibility$component <- 'eligibility'

  exposure <- aggregate(tab$n,
                        list(site = tab$site, pred = tab$prod_class,
                             true = reference_exposure(tab$d)), sum)
  names(exposure)[4] <- 'n'
  exposure$component <- 'exposure'

  if (mapping != 'label-permutation') {
    outcome <- aggregate(tab$n,
                         list(site = tab$site, pred = tab$event,
                              true = as.integer(tab$outcome == 1L)), sum)
    names(outcome)[4] <- 'n'
  } else {
    pieces <- rbind(
      transform(tab, part = tab$n_elig, epart = 1L),
      transform(tab, part = tab$n - tab$n_elig, epart = 0L)
    )
    pieces <- pieces[pieces$part > 0, , drop = FALSE]
    pieces$refd <- reference_exposure(pieces$d)
    pieces$true_y <- as.integer(pieces$outcome == 1L)
    agg <- aggregate(pieces$part,
                     list(site = pieces$site, x = pieces$x, refd = pieces$refd,
                          epart = pieces$epart, true_y = pieces$true_y), sum)
    names(agg)[6] <- 'n'
    rows <- list()
    groups <- unique(agg[, c('site', 'x', 'refd', 'epart')])
    for (ii in seq_len(nrow(groups))) {
      g <- groups[ii, ]
      d <- agg[agg$site == g$site & agg$x == g$x & agg$refd == g$refd &
                 agg$epart == g$epart, ]
      n1 <- sum(d$n[d$true_y == 1L])
      n0 <- sum(d$n[d$true_y == 0L])
      if (g$site %in% affected) {
        both1 <- if (n1 > 0L) stats::rhyper(1L, n1, n0, n1) else 0L
        move <- n1 - both1
        cell <- data.frame(
          site = g$site,
          pred = c(1L, 0L, 1L, 0L),
          true = c(1L, 1L, 0L, 0L),
          n = c(both1, move, move, n0 - move)
        )
      } else {
        cell <- data.frame(site = g$site, pred = c(1L, 0L),
                           true = c(1L, 0L), n = c(n1, n0))
      }
      rows[[length(rows) + 1L]] <- cell
    }
    outcome <- do.call(rbind, rows)
    outcome <- aggregate(outcome$n,
                         list(site = outcome$site, pred = outcome$pred,
                              true = outcome$true), sum)
    names(outcome)[4] <- 'n'
  }
  outcome$component <- 'outcome'
  rbind(eligibility, exposure, outcome)
}

adjudicate_contingencies <- function(cont, reference) {
  eps <- if (reference == 'error05') 0.05 else 0
  rows <- list()
  for (i in seq_len(nrow(cont))) {
    d <- cont[i, ]
    classes <- if (d$component == 'exposure') 0:2 else 0:1
    if (eps == 0) {
      draw <- integer(length(classes)); draw[d$true + 1L] <- d$n
    } else if (length(classes) == 2L) {
      flip <- stats::rbinom(1L, d$n, eps)
      draw <- integer(2L)
      draw[d$true + 1L] <- d$n - flip
      draw[2L - d$true] <- flip
    } else {
      p <- rep(eps / 2, 3L); p[d$true + 1L] <- 1 - eps
      draw <- as.integer(stats::rmultinom(1L, d$n, p))
    }
    rows[[i]] <- data.frame(
      component = d$component, site = d$site, pred = d$pred,
      ref = classes, n = draw, stringsAsFactors = FALSE
    )
  }
  z <- do.call(rbind, rows)
  z$discord <- z$n * as.integer(z$pred != z$ref)
  out <- aggregate(cbind(n, discord) ~ component + site + pred, z, sum)
  out
}

wilson_upper <- function(x, n, confidence = VALIDATION_CONFIDENCE) {
  if (!is.finite(n) || n <= 0) return(NA_real_)
  z <- stats::qnorm(confidence)
  p <- x / n
  (p + z^2 / (2 * n) + z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))) /
    (1 + z^2 / n)
}

sample_validation <- function(totals) {
  rows <- list()
  for (i in seq_len(nrow(totals))) {
    d <- totals[i, ]
    left_n <- as.integer(d$n)
    left_bad <- as.integer(d$discord)
    reviewed <- 0L
    bad <- 0L
    for (target in VALIDATION_SIZES) {
      add <- target - reviewed
      available <- left_n >= add
      if (available) {
        got <- if (add > 0L) stats::rhyper(1L, left_bad, left_n - left_bad, add) else 0L
        reviewed <- reviewed + add
        bad <- bad + got
        left_n <- left_n - add
        left_bad <- left_bad - got
        upper <- wilson_upper(bad, reviewed)
        pass <- is.finite(upper) && upper <= VALIDATION_DISCORDANCE_LIMIT
      } else {
        upper <- NA_real_; pass <- FALSE
      }
      rows[[length(rows) + 1L]] <- data.frame(
        component = d$component, site = d$site, pred = d$pred,
        target = target, available = available,
        reviewed = if (available) reviewed else d$n,
        discord = if (available) bad else NA_integer_,
        upper = upper, pass = pass, stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

run_validation <- function(tab, mapping, pair_id, reference) {
  totals <- adjudicate_contingencies(
    basic_contingencies(tab, mapping, pair_id), reference)
  classes <- sample_validation(totals)
  by_size <- list()
  for (target in VALIDATION_SIZES) {
    d <- classes[classes$target == target, ]
    pass <- vapply(seq_len(N_SITES), function(j) {
      z <- d[d$site == j, ]
      nrow(z) == 7L && all(z$available) && all(z$pass)
    }, logical(1))
    workload <- vapply(seq_len(N_SITES), function(j)
      sum(d$reviewed[d$site == j]), numeric(1))
    by_size[[as.character(target)]] <- list(
      site_pass = pass, workload = workload, classes = d)
  }
  list(totals = totals, classes = classes, by_size = by_size)
}

## A vectorized row generator exists only for the prespecified generator check.
direct_row_moments <- function(site, kappa, gamma, n) {
  s <- SITE_CONTEXT[[site]]
  x1 <- stats::rbinom(n, 1L, expit(-0.20 + 0.45 * s))
  x2 <- stats::rbinom(n, 1L, expit(0.10 - 0.15 * s))
  x3 <- stats::rbinom(n, 1L, expit(-0.80 + 0.70 * x1 - 0.20 * x2 + 0.25 * s))
  u <- stats::rbinom(n, 1L, expit(-1.00 + 0.40 * x1 + 0.60 * x3))
  g <- 75 - 10 * x1 - 12 * x3 - 10 * u + 12 * stats::rnorm(n)
  q <- stats::rbinom(n, 1L, expit(-0.35 + 0.35 * s + 0.30 * x1 - 0.20 * x2 + 0.50 * x3))
  d <- integer(n)
  on <- which(q == 1L)
  if (length(on)) d[on] <- sample.int(3L, length(on), replace = TRUE,
                                      prob = c(0.60, 0.20, 0.20))
  base <- expit(-1.80 + 0.35 * x1 + 0.20 * x2 + 0.55 * x3 +
                  0.30 * kappa * u + 0.05 * s)
  delta1 <- -0.06 - kappa * (0.03 * x3 + 0.06 * u) + gamma * s
  delta <- ifelse(d == 0L, 0, ifelse(d == 1L, delta1,
                  ifelse(d == 2L, delta1 + 0.12 * kappa, 0.02)))
  py <- base + delta
  pw0 <- expit(-3.00 + 0.20 * x1 + 0.10 * x3)
  pw <- pw0 + ifelse(d == 1L, 0.06 * kappa,
                     ifelse(d == 2L, 0.02 * kappa,
                            ifelse(d == 3L, 0.08 * kappa, 0)))
  r <- stats::runif(n)
  y <- as.integer(r < py)
  w <- as.integer(r >= py & r < py + pw)
  c(x1 = mean(x1), x2 = mean(x2), x3 = mean(x3), u = mean(u),
    eligible = mean(g >= 45), d1 = mean(d == 1L), d2 = mean(d == 2L),
    y = mean(y), w = mean(w))
}

count_moments <- function(tab, site) {
  d <- tab[tab$site == site, ]
  n <- sum(d$n)
  c(x1 = sum(d$n * d$x1) / n, x2 = sum(d$n * d$x2) / n,
    x3 = sum(d$n * d$x3) / n, u = sum(d$n * d$u) / n,
    eligible = sum(d$n * (d$renal >= 1L)) / n,
    d1 = sum(d$n * (d$d == 1L)) / n,
    d2 = sum(d$n * (d$d == 2L)) / n,
    y = sum(d$n * (d$outcome == 1L)) / n,
    w = sum(d$n * (d$outcome == 2L)) / n)
}

verify_aggregate_generator <- function(n = 20000L) {
  scen <- data.frame(kappa = 1, gamma = 0.02)
  direct <- lapply(seq_len(N_SITES), direct_row_moments,
                   kappa = 1, gamma = 0.02, n = n)
  counts <- gen_base_counts(scen, n = n)
  aggregate <- lapply(seq_len(N_SITES), count_moments, tab = counts)
  z <- unlist(Map(function(a, b) {
    pooled <- pmin(0.999999, pmax(0.000001, (a + b) / 2))
    (a - b) / sqrt(2 * pooled * (1 - pooled) / n)
  }, direct, aggregate))
  list(pass = all(is.finite(z)) && max(abs(z)) < 6,
       max_abs_z = max(abs(z)), z = z, n_per_site = n)
}
