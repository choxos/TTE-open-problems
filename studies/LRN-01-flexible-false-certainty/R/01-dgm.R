## LRN-01 support stress study: data-generating mechanism and truth engine.

expit <- stats::plogis
clip <- function(x, lo, hi) pmin(hi, pmax(lo, x))
mean_columns <- function(dat, prefix, idx) {
  rowMeans(as.matrix(dat[paste0(prefix, idx)]))
}

raw_projection_history <- function(dat, t) {
  cols <- list(
    B1 = dat$B1,
    B2 = 2 * dat$B2 - 1,
    B3 = 2 * dat$B3 - 1
  )
  for (j in 0:t) cols[[paste0("L", j)]] <- dat[[paste0("L", j)]] / 1.5
  for (j in 0:t) cols[[paste0("M", j)]] <- 2 * dat[[paste0("M", j)]] - 1
  if (t > 0) {
    for (j in 0:(t - 1L)) cols[[paste0("A", j)]] <- 2 * dat[[paste0("A", j)]] - 1
  }
  x <- as.matrix(as.data.frame(cols, check.names = FALSE))
  stopifnot(identical(colnames(x), projection_history_names(t)))
  x
}

projection_scores <- function(dat, t, geometry) {
  z <- PROJECTION_MANIFEST[[paste(geometry, t, sep = "|")]]
  x <- raw_projection_history(dat, t)
  list(U = drop(x %*% z$U[colnames(x)]),
       V = drop(x %*% z$V[colnames(x)]))
}

support_region <- function(dat, t, geometry, boundary = NA_real_) {
  n <- nrow(dat)
  if (geometry == "soft") return(list(forbid1 = rep(FALSE, n), forbid0 = rep(FALSE, n)))
  Lt <- dat[[paste0("L", t)]]
  Mt <- dat[[paste0("M", t)]]
  if (geometry == "linear") {
    s <- Lt + 0.40 * Mt + 0.30 * dat$B3
    out <- list(forbid1 = s < -boundary, forbid0 = s > boundary)
  } else if (geometry == "curved") {
    uv <- projection_scores(dat, t, geometry)
    r2 <- uv$U^2 + uv$V^2
    out <- list(forbid1 = r2 > 0.35 & r2 < 0.75,
                forbid0 = r2 > 1.35 & r2 < 2.00)
  } else if (geometry == "disconnected") {
    uv <- projection_scores(dat, t, geometry)
    corner <- abs(uv$U) > 1 & abs(uv$V) > 1
    out <- list(forbid1 = corner & sign(uv$U) == sign(uv$V),
                forbid0 = corner & sign(uv$U) != sign(uv$V))
  } else if (geometry == "interaction") {
    uv <- projection_scores(dat, t, geometry)
    w <- uv$U * uv$V + 0.40 * (2 * Mt - 1) * tanh(Lt)
    out <- list(forbid1 = w < -1, forbid0 = w > 1)
  } else if (geometry == "accumulated") {
    ml <- mean_columns(dat, "L", 0:t) / 1.5
    mm <- rowMeans(2 * as.matrix(dat[paste0("M", 0:t)]) - 1)
    ma <- if (t == 0) rep(0, n) else
      rowMeans(2 * as.matrix(dat[paste0("A", 0:(t - 1L))]) - 1)
    w <- 0.45 * ml + 0.35 * mm + 0.25 * ma + 0.20 * dat$B1
    out <- list(forbid1 = w < -0.75, forbid0 = w > 0.75)
  } else stop("unknown geometry: ", geometry)
  if (any(out$forbid1 & out$forbid0)) stop("overlapping forbidden regions")
  out
}

treatment_linear_predictor <- function(dat, t, complexity) {
  Lt <- dat[[paste0("L", t)]]
  Mt <- dat[[paste0("M", t)]]
  eta <- -0.15 + 0.80 * tanh(Lt) + 0.45 * Mt + 0.35 * dat$B3 +
    0.25 * tanh(dat$B1) + 0.10 * t / 5
  if (t > 0) {
    prev <- dat[[paste0("A", t - 1L)]]
    mean_a <- mean_columns(dat, "A", 0:(t - 1L))
    eta <- eta + 1.10 * (prev - 0.5) - 0.30 * (mean_a - 0.5)
  }
  if (complexity == 1) {
    eta <- eta + 0.35 * sin(Lt) + 0.25 * dat$B1 * tanh(Lt) -
      0.20 * as.integer(Lt > 0.75)
  }
  eta
}

treatment_probability <- function(dat, t, support, complexity) {
  eta <- treatment_linear_predictor(dat, t, complexity)
  if (support$support_kind == "soft") return(expit(support$eta_scale * eta))
  r <- support_region(dat, t, support$geometry, support$boundary)
  p <- expit(eta)
  if (support$support_kind == "exact") {
    p[r$forbid1] <- 0
    p[r$forbid0] <- 1
  } else {
    p[r$forbid1] <- 0.005
    p[r$forbid0] <- 0.995
  }
  p
}

draw_exogenous <- function(n) {
  B1 <- stats::rnorm(n)
  B2 <- stats::rbinom(n, 1, 0.50)
  B3 <- stats::rbinom(n, 1, expit(-0.60 + 0.50 * B1 + 0.40 * B2))
  L0 <- 0.45 * B1 + 0.55 * B3 - 0.25 * B2 + stats::rnorm(n, 0, 0.8)
  M0 <- stats::rbinom(n, 1, expit(-1.10 + 0.45 * B3 + 0.50 * L0))
  list(B1 = B1, B2 = B2, B3 = B3, L0 = L0, M0 = M0,
       eL = matrix(stats::rnorm(n * 5L, 0, 0.75), nrow = n),
       uM = matrix(stats::runif(n * 5L), nrow = n))
}

start_history <- function(exo) {
  data.frame(B1 = exo$B1, B2 = exo$B2, B3 = exo$B3,
             L0 = exo$L0, M0 = exo$M0, check.names = FALSE)
}

advance_history <- function(dat, exo, t, complexity) {
  Lt <- dat[[paste0("L", t)]]
  Mt <- dat[[paste0("M", t)]]
  At <- dat[[paste0("A", t)]]
  next_t <- t + 1L
  mu_l <- 0.55 * Lt + 0.20 * dat$B1 + 0.30 * dat$B3 + 0.25 * Mt -
    0.40 * At + 0.15 * next_t / 5
  if (complexity == 1) {
    mu_l <- mu_l + 0.20 * sin(Lt) + 0.15 * dat$B3 * as.integer(Lt > 0.5)
  }
  dat[[paste0("L", next_t)]] <- mu_l + exo$eL[, next_t]
  eta_m <- -1.20 + 0.60 * Mt + 0.40 * Lt + 0.30 * dat$B3 - 0.35 * At +
    0.10 * next_t / 5
  if (complexity == 1) {
    eta_m <- eta_m + 0.25 * as.integer(Lt > 0.5) -
      0.20 * Lt^2 / (1 + Lt^2)
  }
  dat[[paste0("M", next_t)]] <- as.integer(exo$uM[, next_t] < expit(eta_m))
  dat
}

outcome_linear_predictor <- function(dat, complexity) {
  mean_l <- mean_columns(dat, "L", VISITS)
  mean_m <- mean_columns(dat, "M", VISITS)
  mean_a <- mean_columns(dat, "A", VISITS)
  L5 <- dat$L5
  eta <- -2.25 + 0.30 * dat$B1 + 0.20 * dat$B2 + 0.55 * dat$B3 +
    0.60 * L5 + 0.35 * dat$M5 + 0.20 * mean_l + 0.25 * mean_m -
    0.75 * mean_a + 0.45 * mean_a * dat$B3 +
    0.25 * mean_a * as.integer(dat$B1 > 0)
  if (complexity == 1) {
    eta <- eta + 0.55 * (L5^2 / (1 + L5^2) - 0.5) +
      0.35 * sin(pi * mean_l / 2) +
      0.35 * dat$M5 * as.integer(L5 > 0.5) -
      0.30 * mean_a * tanh(L5)
  }
  eta
}

## Vectorized over individuals. The only loops are the six fixed decisions.
gen_replicate <- function(scen, n = scen$n) {
  exo <- draw_exogenous(n)
  dat <- start_history(exo)
  support <- scen[1, names(SUPPORTS), drop = FALSE]
  for (t in VISITS) {
    p <- treatment_probability(dat, t, support, scen$complexity)
    dat[[paste0("A", t)]] <- as.integer(stats::runif(n) < p)
    dat[[paste0("ptrue", t)]] <- p
    if (t < 5) dat <- advance_history(dat, exo, t, scen$complexity)
  }
  dat$Y <- stats::rbinom(n, 1, expit(outcome_linear_predictor(dat, scen$complexity)))
  dat
}

intervention_paths <- function(exo, complexity, action) {
  dat <- start_history(exo)
  for (t in VISITS) {
    dat[[paste0("A", t)]] <- rep.int(as.integer(action), nrow(dat))
    if (t < 5) dat <- advance_history(dat, exo, t, complexity)
  }
  dat
}

structural_witness <- function(dat, support, action) {
  hit <- rep(FALSE, nrow(dat))
  for (t in VISITS) {
    r <- support_region(dat, t, support$geometry, support$boundary)
    hit <- hit | if (action == 1) r$forbid1 else r$forbid0
  }
  if (action == 1) as.integer(hit) else -as.integer(hit)
}

truth_batch <- function(complexity, n, batch_id) {
  exo <- draw_exogenous(n)
  d0 <- intervention_paths(exo, complexity, 0L)
  d1 <- intervention_paths(exo, complexity, 1L)
  eta0 <- outcome_linear_predictor(d0, complexity)
  eta1 <- outcome_linear_predictor(d1, complexity)

  rd <- list(data.frame(batch = batch_id, support_key = "common", delta = 0,
                        risk0 = mean(expit(eta0)), risk1 = mean(expit(eta1))))
  exact <- SUPPORTS[SUPPORTS$support_kind == "exact", , drop = FALSE]
  for (i in seq_len(nrow(exact))) {
    z0 <- structural_witness(d0, exact[i, , drop = FALSE], 0L)
    z1 <- structural_witness(d1, exact[i, , drop = FALSE], 1L)
    for (delta in COMPLETION_DELTAS) {
      rd[[length(rd) + 1L]] <- data.frame(
        batch = batch_id, support_key = exact$support_key[i], delta = delta,
        risk0 = mean(expit(eta0 + delta * z0)),
        risk1 = mean(expit(eta1 + delta * z1)))
    }
  }
  rd <- do.call(rbind, rd)
  rd$rd <- rd$risk1 - rd$risk0

  sm <- list()
  for (i in seq_len(nrow(SUPPORTS))) {
    s <- SUPPORTS[i, , drop = FALSE]
    for (a in 0:1) {
      da <- if (a == 0) d0 else d1
      for (t in VISITS) {
        p <- treatment_probability(da, t, s, complexity)
        req <- if (a == 1) p else 1 - p
        sm[[length(sm) + 1L]] <- data.frame(
          batch = batch_id, support_key = s$support_key,
          strategy = a, visit = t,
          zero_mass = mean(req == 0),
          below_0025_mass = mean(req < SUPPORT_PROB_THRESHOLD))
      }
    }
  }
  list(rd = rd, support = do.call(rbind, sm))
}

summarize_truth_batches <- function(rd, support) {
  kd <- unique(rd[, c("support_key", "delta")])
  rsum <- do.call(rbind, lapply(seq_len(nrow(kd)), function(i) {
    d <- rd[rd$support_key == kd$support_key[i] &
              abs(rd$delta - kd$delta[i]) < 1e-12, , drop = FALSE]
    data.frame(support_key = kd$support_key[i], delta = kd$delta[i],
               risk0 = mean(d$risk0), risk0_mcse = stats::sd(d$risk0) / sqrt(nrow(d)),
               risk1 = mean(d$risk1), risk1_mcse = stats::sd(d$risk1) / sqrt(nrow(d)),
               rd = mean(d$rd), rd_mcse = stats::sd(d$rd) / sqrt(nrow(d)))
  }))

  exact_keys <- SUPPORTS$support_key[SUPPORTS$support_kind == "exact"]
  spans <- list()
  for (key in exact_keys) for (m in COMPLETION_MAGNITUDES) {
    d <- rd[rd$support_key == key &
              vapply(rd$delta, function(x) any(abs(x - c(-m, 0, m)) < 1e-12), logical(1)), ]
    by_batch <- split(d, d$batch)
    bs <- vapply(by_batch, function(x) max(x$rd) - min(x$rd), numeric(1))
    means <- rsum$rd[rsum$support_key == key &
                      vapply(rsum$delta, function(x) any(abs(x - c(-m, 0, m)) < 1e-12), logical(1))]
    spans[[length(spans) + 1L]] <- data.frame(
      support_key = key, magnitude = m, span = max(means) - min(means),
      span_mcse = stats::sd(bs) / sqrt(length(bs)))
  }
  spans <- do.call(rbind, spans)

  ks <- unique(support[, c("support_key", "strategy", "visit")])
  ssum <- do.call(rbind, lapply(seq_len(nrow(ks)), function(i) {
    d <- support[support$support_key == ks$support_key[i] &
                   support$strategy == ks$strategy[i] &
                   support$visit == ks$visit[i], ]
    data.frame(support_key = ks$support_key[i], strategy = ks$strategy[i],
               visit = ks$visit[i], zero_mass = mean(d$zero_mass),
               zero_mass_mcse = stats::sd(d$zero_mass) / sqrt(nrow(d)),
               below_0025_mass = mean(d$below_0025_mass),
               below_0025_mass_mcse = stats::sd(d$below_0025_mass) / sqrt(nrow(d)))
  }))
  list(rd = rsum, spans = spans, support = ssum)
}

## Critique fix: one common intervention path pair supplies every support law,
## geometry, and completion. Truth extends in one-million-path blocks until the
## maximum batch MCSE for risk differences and spans is at most 0.0005.
truth_for_complexity <- function(complexity) {
  rd <- list(); sm <- list(); batch_id <- 0L
  target_batches <- N_TRUTH_START %/% N_TRUTH_BATCH
  repeat {
    while (batch_id < target_batches) {
      batch_id <- batch_id + 1L
      b <- truth_batch(complexity, N_TRUTH_BATCH, batch_id)
      rd[[batch_id]] <- b$rd
      sm[[batch_id]] <- b$support
    }
    summary <- summarize_truth_batches(do.call(rbind, rd), do.call(rbind, sm))
    max_mcse <- max(c(summary$rd$rd_mcse, summary$spans$span_mcse), na.rm = TRUE)
    if (is.finite(max_mcse) && max_mcse <= TRUTH_MCSE_MAX) break
    target_batches <- target_batches + N_TRUTH_EXTEND %/% N_TRUTH_BATCH
  }
  list(complexity = complexity, n_paths = batch_id * N_TRUTH_BATCH,
       n_batches = batch_id, max_mcse = max_mcse,
       rd = summary$rd, spans = summary$spans, support = summary$support)
}
