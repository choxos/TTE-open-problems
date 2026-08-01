## Study GMT-03: data-generating mechanism and frozen design preparation.

expit <- function(x) stats::plogis(x)

## Vectorized generation uses one loop over months. There is no loop over
## patients. Follow-up begins after restriction, so n is the inferential count.
gen_replicate <- function(scen, n = as.integer(scen$n)) {
  n <- as.integer(n)
  X <- stats::runif(n, -1, 1)
  G <- stats::rbinom(n, 1, as.numeric(scen$p_g))
  L <- matrix(0L, n, N_MONTHS)
  A <- matrix(NA_integer_, n, N_MONTHS)
  p_true <- matrix(NA_real_, n, N_MONTHS)
  at_risk <- matrix(FALSE, n, N_MONTHS)
  L[, 1L] <- stats::rbinom(n, 1, expit(-0.2 + 0.6 * X + 0.8 * G))
  event_month <- rep(NA_integer_, n)
  event_type <- rep(0L, n)
  alive <- rep(TRUE, n)

  for (tt in seq_len(N_MONTHS)) {
    at_risk[, tt] <- alive
    if (tt > 1L) {
      ap <- A[, tt - 1L]
      ap[is.na(ap)] <- 0L
      p_l <- expit(-0.7 + 1.3 * L[, tt - 1L] + 0.5 * X +
                     0.6 * G - 0.5 * ap)
      l_new <- stats::rbinom(n, 1, p_l)
      L[, tt] <- ifelse(alive, l_new, L[, tt - 1L])
    }
    lp_a <- if (tt == 1L) {
      as.numeric(scen$kappa) * (-0.75 + 0.8 * X + 0.6 * G + 0.8 * L[, tt])
    } else {
      ap <- A[, tt - 1L]
      ap[is.na(ap)] <- 0L
      as.numeric(scen$persistence) * (2 * ap - 1) +
        as.numeric(scen$kappa) * (-0.75 + 0.7 * X + 0.6 * G + 0.9 * L[, tt])
    }
    pa <- expit(lp_a)
    a_draw <- stats::rbinom(n, 1, pa)
    A[alive, tt] <- a_draw[alive]
    p_true[alive, tt] <- pa[alive]

    eta_y <- as.numeric(scen$alpha_y) + 0.35 * X + 0.55 * G +
      0.80 * L[, tt] - 0.287682 * a_draw + 0.287682 * a_draw * G
    eta_d <- as.numeric(scen$alpha_d) + 0.45 * X + 0.80 * G +
      0.60 * L[, tt]
    m <- pmax(0, eta_y, eta_d)
    ey <- exp(eta_y - m)
    ed <- exp(eta_d - m)
    den <- exp(-m) + ey + ed
    py <- ey / den
    pd <- ed / den
    u <- stats::runif(n)
    new_y <- alive & u < py
    new_d <- alive & !new_y & u < py + pd
    hit <- new_y | new_d
    event_month[hit] <- tt
    event_type[new_y] <- 1L
    event_type[new_d] <- 2L
    alive[hit] <- FALSE
  }

  list(n = n, X = X, G = G, L0 = L[, 1L], L = L, A = A,
       p_true = p_true, at_risk = at_risk,
       event_month = event_month, event_type = event_type)
}

## Paired sustained-strategy simulation uses common baseline, covariate, and
## outcome uniforms. It enumerates truth from the mechanism and never uses
## performance replicates.
simulate_regime_pair <- function(scen, n) {
  X <- stats::runif(n, -1, 1)
  G <- stats::rbinom(n, 1, as.numeric(scen$p_g))
  u0 <- stats::runif(n)
  p_l0 <- expit(-0.2 + 0.6 * X + 0.8 * G)
  L0 <- as.integer(u0 < p_l0)
  L <- list(L0, L0)
  alive <- list(rep(TRUE, n), rep(TRUE, n))
  month <- list(rep(NA_integer_, n), rep(NA_integer_, n))
  type <- list(rep(0L, n), rep(0L, n))

  for (tt in seq_len(N_MONTHS)) {
    u_l <- if (tt > 1L) stats::runif(n) else NULL
    u_o <- stats::runif(n)
    for (gg in 0:1) {
      j <- gg + 1L
      if (tt > 1L) {
        pl <- expit(-0.7 + 1.3 * L[[j]] + 0.5 * X + 0.6 * G - 0.5 * gg)
        l_new <- as.integer(u_l < pl)
        L[[j]][alive[[j]]] <- l_new[alive[[j]]]
      }
      eta_y <- as.numeric(scen$alpha_y) + 0.35 * X + 0.55 * G +
        0.80 * L[[j]] - 0.287682 * gg + 0.287682 * gg * G
      eta_d <- as.numeric(scen$alpha_d) + 0.45 * X + 0.80 * G + 0.60 * L[[j]]
      m <- pmax(0, eta_y, eta_d)
      ey <- exp(eta_y - m)
      ed <- exp(eta_d - m)
      den <- exp(-m) + ey + ed
      py <- ey / den
      pd <- ed / den
      new_y <- alive[[j]] & u_o < py
      new_d <- alive[[j]] & !new_y & u_o < py + pd
      hit <- new_y | new_d
      month[[j]][hit] <- tt
      type[[j]][new_y] <- 1L
      type[[j]][new_d] <- 2L
      alive[[j]][hit] <- FALSE
    }
  }
  list(X = X, G = G, month0 = month[[1L]], month1 = month[[2L]],
       type0 = type[[1L]], type1 = type[[2L]])
}

## Outcome-blind cumulative compatibility calibration. The fixed seed is used
## only before performance simulation. Each pass uses the same regime-specific
## covariate histories for every kappa value.
compatibility_pass <- function(kappas, regime, n, keep = FALSE,
                               chunk = if (FULL_DESIGN) 25000L else 5000L) {
  set.seed(CALIBRATION_SEED)
  sums <- numeric(length(kappas))
  values <- if (keep) matrix(NA_real_, n, length(kappas)) else NULL
  done <- 0L
  while (done < n) {
    m <- min(chunk, n - done)
    X <- stats::runif(m, -1, 1)
    G <- stats::rbinom(m, 1, CORE_P_G)
    L <- stats::rbinom(m, 1, expit(-0.2 + 0.6 * X + 0.8 * G))
    log_c <- matrix(0, m, length(kappas))
    for (tt in seq_len(N_MONTHS)) {
      base <- if (tt == 1L) {
        -0.75 + 0.8 * X + 0.6 * G + 0.8 * L
      } else {
        -0.75 + 0.7 * X + 0.6 * G + 0.9 * L
      }
      offset <- if (tt == 1L) 0 else CORE_PERSISTENCE * (2 * regime - 1)
      p <- expit(outer(base, kappas, "*") + offset)
      log_c <- log_c + if (regime == 1L) log(p) else log1p(-p)
      if (tt < N_MONTHS) {
        L <- stats::rbinom(m, 1, expit(-0.7 + 1.3 * L + 0.5 * X +
                                        0.6 * G - 0.5 * regime))
      }
    }
    cp <- exp(log_c)
    sums <- sums + colSums(cp)
    if (keep) values[done + seq_len(m), ] <- cp
    done <- done + m
  }
  list(mean = sums / n, values = values)
}

calibrate_overlap <- function(outdir) {
  f <- file.path(outdir, "calibration.rds")
  if (file.exists(f)) {
    old <- readRDS(f)
    if (identical(old$profile, PROFILE) && old$n_histories == N_CALIBRATION)
      return(old$table)
  }
  c0 <- compatibility_pass(KAPPA_GRID, 0L, N_CALIBRATION)
  c1 <- compatibility_pass(KAPPA_GRID, 1L, N_CALIBRATION)
  cmin <- pmin(c0$mean, c1$mean)
  selected <- 1L
  for (target in unname(KAPPA_TARGETS)) {
    ord <- order(abs(cmin - target), KAPPA_GRID)
    pick <- ord[!ord %in% selected][1L]
    if (abs(cmin[pick] - target) > 0.01)
      stop("Cumulative compatibility calibration missed a target by more than 0.01")
    selected <- c(selected, pick)
  }
  kappas <- KAPPA_GRID[selected]
  q0 <- compatibility_pass(kappas, 0L, N_CALIBRATION, keep = TRUE)
  q1 <- compatibility_pass(kappas, 1L, N_CALIBRATION, keep = TRUE)
  probs <- c(0.01, 0.10, 0.25, 0.50, 0.75, 0.90, 0.99)
  tab <- data.frame(k_level = paste0("K", 0:4), kappa = kappas,
                    C0 = q0$mean, C1 = q1$mean,
                    Cmin = pmin(q0$mean, q1$mean), stringsAsFactors = FALSE)
  for (gg in 0:1) {
    q <- apply(if (gg == 0L) q0$values else q1$values, 2L,
               stats::quantile, probs = probs, names = FALSE)
    for (j in seq_along(probs))
      tab[[sprintf("q%02d_g%d", round(100 * probs[j]), gg)]] <- q[j, ]
  }
  obj <- list(profile = PROFILE, n_histories = N_CALIBRATION, table = tab)
  saveRDS(obj, f)
  utils::write.csv(tab, file.path(outdir, "calibration.csv"), row.names = FALSE)
  tab
}

## Deterministic quadrature supplies preperformance expected compatible event
## counts. It uses the DGM only and does not inspect coverage or convergence.
mechanism_expected_counts <- function(scen, nx = VALIDATION_QUADRATURE_N) {
  x0 <- -1 + (seq_len(nx) - 0.5) * 2 / nx
  base_x <- rep(x0, 2L)
  base_g <- rep(0:1, each = nx)
  base_w <- rep(c(1 - as.numeric(scen$p_g), as.numeric(scen$p_g)), each = nx) / nx
  pl0 <- expit(-0.2 + 0.6 * base_x + 0.8 * base_g)
  out <- matrix(0, 2L, 2L, dimnames = list(c("g0", "g1"), c("Y", "D")))
  B <- length(base_x)

  for (gg in 0:1) {
    X <- c(base_x, base_x)
    G <- c(base_g, base_g)
    L <- c(rep(0L, B), rep(1L, B))
    mass <- c(base_w * (1 - pl0), base_w * pl0)
    ey <- 0
    ed <- 0
    for (tt in seq_len(N_MONTHS)) {
      lp_a <- if (tt == 1L) {
        as.numeric(scen$kappa) * (-0.75 + 0.8 * X + 0.6 * G + 0.8 * L)
      } else {
        as.numeric(scen$persistence) * (2 * gg - 1) +
          as.numeric(scen$kappa) * (-0.75 + 0.7 * X + 0.6 * G + 0.9 * L)
      }
      pa <- if (gg == 1L) expit(lp_a) else 1 - expit(lp_a)
      eta_y <- as.numeric(scen$alpha_y) + 0.35 * X + 0.55 * G +
        0.80 * L - 0.287682 * gg + 0.287682 * gg * G
      eta_d <- as.numeric(scen$alpha_d) + 0.45 * X + 0.80 * G + 0.60 * L
      mm <- pmax(0, eta_y, eta_d)
      py <- exp(eta_y - mm) / (exp(-mm) + exp(eta_y - mm) + exp(eta_d - mm))
      pd <- exp(eta_d - mm) / (exp(-mm) + exp(eta_y - mm) + exp(eta_d - mm))
      after_a <- mass * pa
      ey <- ey + sum(after_a * py)
      ed <- ed + sum(after_a * pd)
      mass <- after_a * (1 - py - pd)
      if (tt < N_MONTHS) {
        pn <- expit(-0.7 + 1.3 * L + 0.5 * X + 0.6 * G - 0.5 * gg)
        m0 <- mass[seq_len(B)] * (1 - pn[seq_len(B)]) +
          mass[B + seq_len(B)] * (1 - pn[B + seq_len(B)])
        m1 <- mass[seq_len(B)] * pn[seq_len(B)] +
          mass[B + seq_len(B)] * pn[B + seq_len(B)]
        mass <- c(m0, m1)
      }
    }
    out[gg + 1L, ] <- c(ey, ed)
  }
  c(expected_y = as.numeric(scen$n) * min(out[, "Y"]),
    expected_d = as.numeric(scen$n) * min(out[, "D"]))
}

lhs_pool <- function(n, d) {
  vapply(seq_len(d), function(j)
    (sample.int(n) - stats::runif(n)) / n, numeric(n))
}

build_validation_manifest <- function(outdir) {
  f <- file.path(outdir, "validation-manifest.rds")
  if (file.exists(f)) {
    old <- readRDS(f)
    if (identical(old$profile, PROFILE) && nrow(old$table) == N_VALIDATION)
      return(old$table)
  }
  set.seed(VALIDATION_SEED)
  U <- lhs_pool(VALIDATION_POOL, 6L)
  pool <- data.frame(
    n = as.integer(round(exp(log(800) + U[, 1L] * (log(20000) - log(800))))),
    kappa = min(KAPPA_GRID) + U[, 2L] * (max(KAPPA_GRID) - min(KAPPA_GRID)),
    alpha_y = -9.60 + U[, 3L] * 2.90,
    alpha_d = -9.60 + U[, 4L] * 2.90,
    p_g = 0.10 + U[, 5L] * 0.30,
    persistence = 3.5 + U[, 6L], stringsAsFactors = FALSE)
  counts <- t(vapply(seq_len(nrow(pool)), function(i)
    mechanism_expected_counts(pool[i, , drop = FALSE]), numeric(2)))
  pool$expected_y <- counts[, 1L]
  pool$expected_d <- counts[, 2L]
  pool$validation_quadrant <- paste0(
    ifelse(pool$expected_y < EVENT_ESS_FLAG, "Ylt20", "Yge20"), "_",
    ifelse(pool$expected_d < EVENT_ESS_FLAG, "Dlt20", "Dge20"))
  targets <- c("Ylt20_Dlt20", "Ylt20_Dge20", "Yge20_Dlt20", "Yge20_Dge20")
  if (any(vapply(targets, function(z) sum(pool$validation_quadrant == z), integer(1)) < 30L))
    stop("Validation candidate pool does not contain 30 scenarios in every quadrant")

  scaled <- scale(U)
  selected <- integer()
  used <- setNames(integer(length(targets)), targets)
  while (length(selected) < N_VALIDATION) {
    for (q in targets) {
      if (used[[q]] >= 30L) next
      cand <- which(pool$validation_quadrant == q & !seq_len(nrow(pool)) %in% selected)
      score <- if (!length(selected)) {
        rowSums((scaled[cand, , drop = FALSE])^2)
      } else {
        vapply(cand, function(i) min(rowSums((scaled[selected, , drop = FALSE] -
                                               matrix(scaled[i, ], nrow = length(selected),
                                                      ncol = ncol(scaled), byrow = TRUE))^2)),
               numeric(1))
      }
      selected <- c(selected, cand[which.max(score)])
      used[[q]] <- used[[q]] + 1L
    }
  }
  tab <- pool[selected, , drop = FALSE]
  rownames(tab) <- NULL
  obj <- list(profile = PROFILE, table = tab)
  saveRDS(obj, f)
  utils::write.csv(tab, file.path(outdir, "validation-manifest.csv"), row.names = FALSE)
  tab
}

## Critique fixes implemented here: compatibility is calibrated without outcome
## results, and validation uses 120 frozen scenarios with 30 in each expected
## endpoint-count quadrant.
prepare_design <- function(outdir) {
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  calibration <- calibrate_overlap(outdir)
  validation <- build_validation_manifest(outdir)
  scenarios <- build_scenarios(calibration, validation)
  list(calibration = calibration, validation = validation, scenarios = scenarios)
}

truth_key <- function(scen) paste(sprintf("%.6f", c(scen$alpha_y, scen$alpha_d,
                                                     scen$p_g, scen$persistence)),
                                  collapse = "_")

truth_seed <- function(scen) {
  z <- utf8ToInt(truth_key(scen))
  as.integer(MASTER_SEED + 100000L + sum(z * seq_along(z)) %% 1000000L)
}
