## Study 1 (CNF-01): the data-generating mechanism.
##
## Discrete monthly time. Baseline initiation is confounded; individuals who did
## not initiate at baseline may initiate later, which is the convergence the
## catalog entry is about; the outcome hazard falls while exposed.
##
## The one design subtlety is the timing shape. Two shapes have to produce the
## SAME cumulative initiation at month 120 while differing in when the
## initiation happened, because that is the contrast that decides whether
## reporting a single diagnostic number is enough. Matching them is done by
## solving for the intercept numerically rather than by picking parameters that
## look about right, so the match is exact to the tolerance below and not
## approximate in a way that would blur the comparison it exists to make.

expit <- function(x) 1 / (1 + exp(-x))

## Timing shapes, on the linear predictor scale, standardized to mean zero over
## the follow-up so that the intercept alone controls the level. `early` puts
## the initiation hazard up front and lets it decay; `late` does the reverse.
shape_curve <- function(shape, n_months = N_MONTHS) {
  t <- seq_len(n_months)
  raw <- switch(
    shape,
    early = -1.6 * (t - 1) / (n_months - 1),
    late  =  1.6 * (t - 1) / (n_months - 1),
    stop("unknown shape: ", shape)
  )
  raw - mean(raw)
}

## Cumulative probability that an untreated individual with covariate value `l`
## has initiated by each month, under a given intercept and shape. Closed form,
## so the tuning below is fast and deterministic.
cum_init <- function(alpha0, shape_lp, alpha_l, l) {
  h <- expit(alpha0 + shape_lp + alpha_l * l)
  1 - cumprod(1 - h)
}

## Solve for the intercept that makes the marginal cumulative initiation at
## month 120 equal the target. Marginal over the covariate distribution among
## baseline non-initiators, which is not the population distribution: baseline
## initiation is confounded, so non-initiators are shifted low on L.
tune_alpha0 <- function(target, shape, alpha_l, l_grid, w_grid, tol = 1e-6) {
  shape_lp <- shape_curve(shape)
  f <- function(a0) {
    cs <- vapply(l_grid, function(l) cum_init(a0, shape_lp, alpha_l, l)[N_MONTHS],
                 numeric(1))
    sum(cs * w_grid) - target
  }
  stats::uniroot(f, interval = c(-12, 2), tol = tol)$root
}

## The covariate distribution among baseline non-initiators, as a weighted grid.
## Used only for tuning; the simulation itself draws individuals.
nonintiator_grid <- function(n_grid = 61L) {
  l <- seq(-4, 4, length.out = n_grid)
  dens <- stats::dnorm(l)
  ## P(A0 = 0 | L = l), averaged over Z
  pz <- c(0.6, 0.4)
  p_no <- vapply(l, function(li)
    sum(pz * (1 - expit(GAMMA0 + GAMMA_L * li + GAMMA_Z * c(0, 1)))), numeric(1))
  w <- dens * p_no
  list(l = l, w = w / sum(w))
}

## Cache the tuned intercepts: the grid is small and the solve is the same for
## every replicate of a scenario.
.alpha0_cache <- new.env(parent = emptyenv())

alpha0_for <- function(target, shape, alpha_l) {
  key <- paste(target, shape, alpha_l, sep = "|")
  if (!is.null(.alpha0_cache[[key]])) return(.alpha0_cache[[key]])
  g <- nonintiator_grid()
  a0 <- tune_alpha0(target, shape, alpha_l, g$l, g$w)
  .alpha0_cache[[key]] <- a0
  a0
}

## Exposure trajectory for one person given the month they initiated.
## `init_month` is NA for never-initiated, 0 for baseline initiators.
##
## transient: exposure is 1 from the month after initiation onward
## legacy:    exposure ramps 0 -> 1 linearly over RAMP_MONTHS after initiation
exposure_path <- function(init_month, persistence, n_months = N_MONTHS) {
  e <- numeric(n_months)
  if (is.na(init_month)) return(e)
  start <- max(1L, init_month + 1L)
  if (start > n_months) return(e)
  if (persistence == "transient") {
    e[start:n_months] <- 1
  } else {
    k <- seq_len(n_months - start + 1L)
    e[start:n_months] <- pmin(1, k / RAMP_MONTHS)
  }
  e
}

## Generate one replicate and return the individual-level data an estimator
## needs: baseline covariates, baseline assignment, the month of any later
## initiation, and the event time subject to administrative censoring.
##
## `force_a0` overrides baseline assignment, which is how the oracle quantities
## in 02-estimators.R are computed: the same mechanism run with assignment set
## rather than drawn.
gen_replicate <- function(scen, n = N_PER_ARM, force_a0 = NULL,
                          block_later_initiation = FALSE) {
  L <- stats::rnorm(n)
  Z <- stats::rbinom(n, 1, 0.4)
  A0 <- if (is.null(force_a0)) {
    stats::rbinom(n, 1, expit(GAMMA0 + GAMMA_L * L + GAMMA_Z * Z))
  } else {
    rep(as.integer(force_a0), n)
  }

  a0_int <- alpha0_for(scen$target_c120, scen$shape, scen$alpha_l)
  shape_lp <- shape_curve(scen$shape)

  ## Month of initiation. Baseline initiators get 0. Non-initiators draw a
  ## discrete-time hazard month by month, unless later initiation is blocked,
  ## which is how the never-treated reference arm is generated.
  init_month <- ifelse(A0 == 1L, 0L, NA_integer_)
  if (!block_later_initiation) {
    idx <- which(A0 == 0L)
    if (length(idx)) {
      h <- expit(outer(scen$alpha_l * L[idx], shape_lp, "+") + a0_int)
      u <- matrix(stats::runif(length(idx) * N_MONTHS), nrow = length(idx))
      first <- max.col(u < h, ties.method = "first")
      any_init <- rowSums(u < h) > 0
      init_month[idx] <- ifelse(any_init, first, NA_integer_)
    }
  }

  ## Exposure and event times.
  lp_base <- BETA0 + BETA_L * L + BETA_Z * Z
  E <- vapply(seq_len(n), function(i)
    exposure_path(init_month[i], scen$persistence), numeric(N_MONTHS))
  E <- t(E)                                        # n x months
  hY <- expit(lp_base + BETA_A * E)
  u <- matrix(stats::runif(n * N_MONTHS), nrow = n)
  hit <- u < hY
  ever <- rowSums(hit) > 0
  tev <- ifelse(ever, max.col(hit, ties.method = "first"), NA_integer_)

  data.frame(L = L, Z = Z, A0 = A0, init_month = init_month,
             event_month = tev, stringsAsFactors = FALSE)
}

## Cumulative risk by a horizon, from the event-month column.
risk_by <- function(dat, h) mean(!is.na(dat$event_month) & dat$event_month <= h)

## The diagnostic the catalog entry asks authors to publish: cumulative
## incidence of initiation among those who did not initiate at baseline.
init_incidence <- function(dat, h) {
  comp <- dat[dat$A0 == 0L, , drop = FALSE]
  if (!nrow(comp)) return(NA_real_)
  mean(!is.na(comp$init_month) & comp$init_month <= h)
}
