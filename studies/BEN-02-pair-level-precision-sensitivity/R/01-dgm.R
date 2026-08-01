## Study 2 (BEN-02): exact finite-cell data-generating mechanism.
##
## Each cohort is generated as multinomial counts over L1, L2, Z, U, A and Y.
## Independent multinomial increments create the three nested precision levels.
## No individual records and no per-individual loops are used.

expit <- function(x) stats::plogis(x)

bernoulli_mass <- function(x, q) ifelse(x == 1L, q, 1 - q)

latent_probability <- function(eta, family) {
  switch(
    as.character(family),
    logit = stats::plogis(eta),
    probit = stats::pnorm(eta),
    stop("unknown outcome family: ", family)
  )
}

scenario_parameters <- function(scen) {
  family <- as.character(scen$family[[1]])
  baseline <- as.character(scen$baseline_risk[[1]])
  mismatch <- as.character(scen$mismatch[[1]])

  alpha <- if (family == "logit") {
    c(lower = -2.20, common = -1.00)[[baseline]]
  } else {
    c(lower = -1.40, common = -0.45)[[baseline]]
  }

  qzt <- qze <- qut <- que <- 0.50
  imperfect_emulation_measurement <- FALSE

  if (mismatch == "observed_z_shift") {
    qzt <- 0.35
    qze <- 0.65
  } else if (mismatch == "hidden_u_shift") {
    qut <- 0.35
    que <- 0.65
  } else if (mismatch == "measurement_mismatch") {
    imperfect_emulation_measurement <- TRUE
  }

  list(
    family = family,
    baseline = baseline,
    mismatch = mismatch,
    alpha = unname(alpha),
    qzt = qzt,
    qze = qze,
    qut = qut,
    que = que,
    imperfect_emulation_measurement = imperfect_emulation_measurement
  )
}

COV_CELLS <- expand.grid(
  L1 = 0:1, L2 = 0:1, Z = 0:1, U = 0:1,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)

X_CELLS <- expand.grid(
  L1 = 0:1, L2 = 0:1, Z = 0:1,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)

FULL_CELLS <- expand.grid(
  L1 = 0:1, L2 = 0:1, Z = 0:1, U = 0:1, A = 0:1, Y = 0:1,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)

key_x <- function(d) paste(d$L1, d$L2, d$Z, sep = "|")
COV_TO_X <- match(key_x(COV_CELLS), key_x(X_CELLS))
MAP_COV_X <- matrix(0, nrow = nrow(X_CELLS), ncol = nrow(COV_CELLS))
MAP_COV_X[cbind(COV_TO_X, seq_len(nrow(COV_CELLS)))] <- 1

linear_predictor <- function(d, a, pars) {
  pars$alpha + 0.45 * d$L1 - 0.35 * d$L2 + 0.20 * d$L1 * d$L2 +
    0.55 * d$Z + 0.30 * d$U +
    a * (-0.85 + 0.65 * d$Z + 0.45 * d$U)
}

latent_risk <- function(d, a, pars) {
  latent_probability(linear_predictor(d, a, pars), pars$family)
}

measured_risk <- function(p, cohort, pars) {
  if (cohort == "emulation" && pars$imperfect_emulation_measurement) {
    0.02 + 0.83 * p
  } else {
    p
  }
}

covariate_weights <- function(d, qz, qu) {
  bernoulli_mass(d$L1, 0.50) *
    bernoulli_mass(d$L2, 0.40) *
    bernoulli_mass(d$Z, qz) *
    bernoulli_mass(d$U, qu)
}

x_weights <- function(d, qz) {
  bernoulli_mass(d$L1, 0.50) *
    bernoulli_mass(d$L2, 0.40) *
    bernoulli_mass(d$Z, qz)
}

## Critique implementation fix: logit and probit laws, baseline risks and all
## mismatch parameters are fixed independently of the absolute-risk tolerance.
truth_for <- function(scen) {
  pars <- scenario_parameters(scen)

  wt <- covariate_weights(COV_CELLS, pars$qzt, pars$qut)
  we <- covariate_weights(COV_CELLS, pars$qze, pars$que)

  pt0_lat <- latent_risk(COV_CELLS, 0, pars)
  pt1_lat <- latent_risk(COV_CELLS, 1, pars)
  pe0 <- measured_risk(pt0_lat, "emulation", pars)
  pe1 <- measured_risk(pt1_lat, "emulation", pars)

  psi_t <- sum(wt * (pt1_lat - pt0_lat))
  psi_e <- sum(we * (pe1 - pe0))
  delta_raw <- psi_e - psi_t

  ## The available-information target averages emulation conditional effects
  ## over the trial distribution of L1, L2 and Z. U remains marginalized under
  ## the emulation law, and measurement remains the emulation measurement.
  wu_e <- bernoulli_mass(COV_CELLS$U, pars$que)
  m0_x <- drop(MAP_COV_X %*% (wu_e * pe0))
  m1_x <- drop(MAP_COV_X %*% (wu_e * pe1))
  ftx <- x_weights(X_CELLS, pars$qzt)
  psi_e_to_t_lz <- sum(ftx * (m1_x - m0_x))
  delta_observed_align <- psi_e_to_t_lz - psi_t

  ## This is a decomposition check, not an analyst-identified estimand.
  latent_trial_aligned <- sum(wt * (pt1_lat - pt0_lat))
  latent_emulation_aligned <- sum(wt * (pt1_lat - pt0_lat))
  delta_latent_align <- latent_emulation_aligned - latent_trial_aligned

  removable <- pars$mismatch %in% c("aligned", "observed_z_shift")
  identity_error <- if (removable) abs(delta_observed_align) else 0
  summation_error <- max(
    abs(sum(wt) - 1),
    abs(sum(we) - 1),
    abs(sum(ftx) - 1),
    abs(delta_raw - (psi_e - psi_t)),
    abs(delta_observed_align - (psi_e_to_t_lz - psi_t)),
    abs(delta_latent_align),
    identity_error
  )

  data.frame(
    psi_t_true = psi_t,
    psi_e_true = psi_e,
    delta_raw_true = delta_raw,
    psi_e_to_t_lz_true = psi_e_to_t_lz,
    delta_observed_align_true = delta_observed_align,
    delta_latent_align_true = delta_latent_align,
    qz_trial = pars$qzt,
    qz_emulation = pars$qze,
    qu_trial = pars$qut,
    qu_emulation = pars$que,
    emulation_sensitivity = if (pars$imperfect_emulation_measurement) 0.85 else 1,
    emulation_specificity = if (pars$imperfect_emulation_measurement) 0.98 else 1,
    summation_error = summation_error,
    truth_check = is.finite(summation_error) && summation_error < 1e-12,
    stringsAsFactors = FALSE
  )
}

cell_probabilities <- function(scen, cohort = c("trial", "emulation")) {
  cohort <- match.arg(cohort)
  pars <- scenario_parameters(scen)
  d <- FULL_CELLS

  qz <- if (cohort == "trial") pars$qzt else pars$qze
  qu <- if (cohort == "trial") pars$qut else pars$que
  pcov <- covariate_weights(d, qz, qu)

  pa1 <- if (cohort == "trial") {
    rep(0.50, nrow(d))
  } else {
    expit(-0.40 + 0.80 * d$L1 - 0.60 * d$L2 + 0.70 * d$Z)
  }
  pa <- ifelse(d$A == 1L, pa1, 1 - pa1)

  py1 <- measured_risk(latent_risk(d, d$A, pars), cohort, pars)
  py <- ifelse(d$Y == 1L, py1, 1 - py1)

  p <- pcov * pa * py
  total <- sum(p)
  if (!is.finite(total) || abs(total - 1) > 1e-12 || any(p < 0)) {
    stop("invalid finite-cell probabilities")
  }
  p / total
}

nested_multinomial_counts <- function(prob, sizes) {
  increments <- c(sizes[[1]], diff(sizes))
  draws <- vapply(
    increments,
    function(size) drop(stats::rmultinom(1L, size = size, prob = prob)),
    numeric(length(prob))
  )
  cumulative <- draws
  if (ncol(cumulative) > 1L) {
    for (j in 2:ncol(cumulative)) {
      cumulative[, j] <- cumulative[, j] + cumulative[, j - 1L]
    }
  }
  lapply(seq_along(sizes), function(j) cumulative[, j])
}

gen_nested_pair <- function(scen) {
  list(
    trial = nested_multinomial_counts(
      cell_probabilities(scen, "trial"), PRECISION$n_trial
    ),
    emulation = nested_multinomial_counts(
      cell_probabilities(scen, "emulation"), PRECISION$n_emulation
    )
  )
}
