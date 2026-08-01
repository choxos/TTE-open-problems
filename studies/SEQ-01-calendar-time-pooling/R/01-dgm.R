## Study SEQ-01: data-generating mechanism.
##
## All random primitives are generated before scenario-specific probabilities are
## applied. Running each one-row scenario through the harness with the same master
## seed therefore supplies common random numbers across factorial cells.

expit <- function(x) plogis(x)

h_value <- function(h_key, first_month) {
  q <- q_of(first_month)
  switch(
    as.character(h_key),
    none = rep(0, length(q)),
    monotone = 0.30 * q,
    cosine = 0.30 * cos(pi * q),
    stop("unknown treatment-effect pattern: ", h_key)
  )
}

make_noise <- function(n) {
  list(
    age = stats::rbeta(n, 3, 3),
    sex = stats::runif(n),
    comorbidity = stats::runif(n),
    severity = stats::rnorm(n),
    initiation = matrix(stats::runif(n * N_CAL_MONTHS), nrow = n),
    failure = matrix(stats::runif(n * N_CAL_MONTHS), nrow = n),
    innovation = matrix(stats::rnorm(n * N_CAL_MONTHS, sd = 0.70), nrow = n)
  )
}

## Critique fix: covariate effects on initiation, prognosis, and survival remain
## active in every cell. There is no survival-selection factor that changes them
## together.
gen_natural_history <- function(scen, noise) {
  n <- length(noise$age)
  age <- 40 + 50 * noise$age
  R <- (age - 65) / 10
  Sex <- as.integer(noise$sex < 0.5)
  pC <- expit(-0.8 + 0.45 * R + 0.35 * Sex)
  C <- as.integer(noise$comorbidity < pC)
  L <- matrix(NA_real_, nrow = n, ncol = N_CAL_MONTHS)
  L[, 1L] <- 0.35 * R + 0.50 * C + 0.20 * Sex + noise$severity

  initiated <- matrix(FALSE, nrow = n, ncol = N_CAL_MONTHS)
  first_treatment <- rep(NA_integer_, n)
  event_time <- rep(NA_integer_, n)

  for (tt in seq_len(N_CAL_MONTHS)) {
    t <- tt - 1L
    alive <- is.na(event_time)
    untreated <- is.na(first_treatment)
    eligible <- alive & untreated

    pI <- expit(-3.60 + 0.20 * Sex + 0.30 * R + 0.45 * C +
                  0.55 * L[, tt] + scen$a[[1]] * q_of(t))
    new_treatment <- eligible & noise$initiation[, tt] < pI
    initiated[new_treatment, tt] <- TRUE
    first_treatment[new_treatment] <- t

    Z <- !is.na(first_treatment) & first_treatment <= t
    hS <- numeric(n)
    hS[Z] <- h_value(scen$h_key[[1]], first_treatment[Z])

    ## Critique fix: the former C by treatment interaction is absent. Scenarios
    ## labeled h = 0 do not retain another imposed conditional effect modifier.
    pY <- expit(-4.50 + 0.15 * Sex + 0.55 * R + 0.55 * C +
                  0.45 * L[, tt] + scen$b[[1]] * q_of(t) +
                  Z * (log(0.70) + hS))
    failed <- alive & noise$failure[, tt] < pY
    event_time[failed] <- t + 1L

    if (tt < N_CAL_MONTHS) {
      L[, tt + 1L] <- 0.65 * L[, tt] + 0.20 * R + 0.30 * C +
        0.10 * Sex + 0.10 * q_of(t) - 0.30 * Z + noise$innovation[, tt]
    }
  }

  list(
    n = n, age = age, R = R, Sex = Sex, C = C, L = L,
    initiated = initiated, first_treatment = first_treatment,
    event_time = event_time
  )
}

eligible_ids <- function(hist, k) {
  alive <- is.na(hist$event_time) | hist$event_time > k
  untreated_before <- is.na(hist$first_treatment) | hist$first_treatment >= k
  which(alive & untreated_before)
}

natural_initiation_rows <- function(hist) {
  rows <- vector("list", N_CAL_MONTHS)
  for (tt in seq_len(N_CAL_MONTHS)) {
    t <- tt - 1L
    id <- which((is.na(hist$event_time) | hist$event_time > t) &
                  (is.na(hist$first_treatment) | hist$first_treatment >= t))
    rows[[tt]] <- data.table::data.table(
      id = id,
      t = t,
      q = q_of(t),
      Sex = hist$Sex[id],
      R = hist$R[id],
      C = hist$C[id],
      L = hist$L[id, tt],
      I = as.integer(hist$initiated[id, tt])
    )
  }
  data.table::rbindlist(rows, use.names = TRUE)
}

expand_sequential_trials <- function(hist) {
  rows <- vector("list", N_STARTS * N_FOLLOW)
  z <- 0L
  for (s in seq_along(STARTS)) {
    k <- STARTS[s]
    ids <- eligible_ids(hist, k)
    if (!length(ids)) next
    G <- as.integer(hist$initiated[ids, k + 1L])
    L0 <- hist$L[ids, k + 1L]
    pos <- seq_along(ids)

    for (j in 0:(N_FOLLOW - 1L)) {
      t <- k + j
      at_risk <- is.na(hist$event_time[ids]) | hist$event_time[ids] > t
      adherent <- G == 1L | is.na(hist$first_treatment[ids]) |
        hist$first_treatment[ids] > t
      keep <- at_risk & adherent
      z <- z + 1L
      rows[[z]] <- data.table::data.table(
        id = ids[keep], pos = pos[keep], start_idx = s, start = k,
        j = j, t = t, q_start = START_Q[s], q = q_of(t), G = G[keep],
        Y = as.integer(hist$event_time[ids[keep]] == t + 1L),
        Sex = hist$Sex[ids[keep]], R = hist$R[ids[keep]],
        C = hist$C[ids[keep]], L = hist$L[ids[keep], t + 1L],
        L_start = L0[keep]
      )
    }
  }
  out <- data.table::rbindlist(rows[seq_len(z)], use.names = TRUE)
  out[, cell := start_idx + N_STARTS * j + N_STARTS * N_FOLLOW * G]
  data.table::setorder(out, start_idx, j, pos)
  out
}

resample_history <- function(hist, index) {
  list(
    n = length(index),
    age = hist$age[index], R = hist$R[index], Sex = hist$Sex[index],
    C = hist$C[index], L = hist$L[index, , drop = FALSE],
    initiated = hist$initiated[index, , drop = FALSE],
    first_treatment = hist$first_treatment[index],
    event_time = hist$event_time[index]
  )
}

## Paired intervention from a natural eligibility set. The two strategies share
## every failure uniform and severity innovation.
simulate_intervention_pair <- function(hist, scen, k, failure_u, innovation) {
  ids <- eligible_ids(hist, k)
  m <- length(ids)
  if (!m) return(c(eligible = 0, event1 = 0, event0 = 0))

  L1 <- hist$L[ids, k + 1L]
  L0 <- L1
  alive1 <- alive0 <- rep(TRUE, m)
  h1 <- h_value(scen$h_key[[1]], rep(k, m))

  for (jj in seq_len(N_FOLLOW)) {
    j <- jj - 1L
    t <- k + j
    p1 <- expit(-4.50 + 0.15 * hist$Sex[ids] + 0.55 * hist$R[ids] +
                  0.55 * hist$C[ids] + 0.45 * L1 + scen$b[[1]] * q_of(t) +
                  log(0.70) + h1)
    p0 <- expit(-4.50 + 0.15 * hist$Sex[ids] + 0.55 * hist$R[ids] +
                  0.55 * hist$C[ids] + 0.45 * L0 + scen$b[[1]] * q_of(t))
    alive1[alive1 & failure_u[ids, jj] < p1] <- FALSE
    alive0[alive0 & failure_u[ids, jj] < p0] <- FALSE

    if (jj < N_FOLLOW) {
      common <- 0.20 * hist$R[ids] + 0.30 * hist$C[ids] +
        0.10 * hist$Sex[ids] + 0.10 * q_of(t) + innovation[ids, jj]
      L1 <- 0.65 * L1 + common - 0.30
      L0 <- 0.65 * L0 + common
    }
  }

  c(eligible = m, event1 = sum(!alive1), event0 = sum(!alive0))
}
