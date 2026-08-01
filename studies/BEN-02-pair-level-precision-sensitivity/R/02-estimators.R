## Study 2 (BEN-02): count-based estimators and reporting procedures.

OBS_CELLS <- expand.grid(
  L1 = 0:1, L2 = 0:1, Z = 0:1, A = 0:1, Y = 0:1,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)
XA_CELLS <- expand.grid(
  x = seq_len(nrow(X_CELLS)), A = 0:1,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)

key_obs <- function(d) paste(d$L1, d$L2, d$Z, d$A, d$Y, sep = "|")
key_xa <- function(x, a) paste(x, a, sep = "|")

FULL_TO_OBS <- match(key_obs(FULL_CELLS), key_obs(OBS_CELLS))
OBS_TO_X <- match(key_x(OBS_CELLS), key_x(X_CELLS))
OBS_TO_XA <- match(key_xa(OBS_TO_X, OBS_CELLS$A),
                   key_xa(XA_CELLS$x, XA_CELLS$A))

map_matrix <- function(index, n_group) {
  m <- matrix(0, nrow = n_group, ncol = length(index))
  m[cbind(index, seq_along(index))] <- 1
  m
}

MAP_OBS_FROM_FULL <- map_matrix(FULL_TO_OBS, nrow(OBS_CELLS))
MAP_X_FROM_OBS <- map_matrix(OBS_TO_X, nrow(X_CELLS))
MAP_XA_FROM_OBS <- map_matrix(OBS_TO_XA, nrow(XA_CELLS))
PS_MATRIX <- stats::model.matrix(~ L1 + L2 + Z, data = X_CELLS)

collapse_observed <- function(full_counts) {
  drop(MAP_OBS_FROM_FULL %*% full_counts)
}

weighted_sample_variance <- function(x, counts) {
  n <- sum(counts)
  if (n <= 1L || any(!is.finite(x))) return(NA_real_)
  mu <- sum(counts * x) / n
  sum(counts * (x - mu)^2) / (n - 1)
}

estimation_failure <- function(reason) list(ok = FALSE, reason = reason)

estimate_trial <- function(full_counts) {
  counts <- collapse_observed(full_counts)
  n <- sum(counts)
  a <- OBS_CELLS$A
  y <- OBS_CELLS$Y

  n1 <- sum(counts[a == 1L])
  n0 <- sum(counts[a == 0L])
  if (n1 == 0L || n0 == 0L) return(estimation_failure("empty-trial-arm"))

  r1 <- sum(counts[a == 1L] * y[a == 1L]) / n1
  r0 <- sum(counts[a == 0L] * y[a == 0L]) / n0
  est <- r1 - r0
  variance <- r1 * (1 - r1) / n1 + r0 * (1 - r0) / n0
  if (!is.finite(variance) || variance <= 0) {
    return(estimation_failure("nonpositive-trial-variance"))
  }

  p_a <- n1 / n
  if_rd <- ifelse(
    a == 1L,
    (y - r1) / p_a,
    -(y - r0) / (1 - p_a)
  )

  list(
    ok = TRUE,
    counts = counts,
    n = n,
    nx = drop(MAP_X_FROM_OBS %*% counts),
    est = est,
    se = sqrt(variance),
    if_rd = if_rd
  )
}

## Critique implementation fix: the transported discrepancy uses a stacked
## influence function. Its trial component subtracts the trial risk-difference
## influence function from the empirical target-distribution component, which
## retains their covariance.
estimate_pair <- function(trial_full, emulation_full) {
  trial <- estimate_trial(trial_full)
  if (!isTRUE(trial$ok)) return(trial)

  counts <- collapse_observed(emulation_full)
  n_e <- sum(counts)
  nxa <- matrix(drop(MAP_XA_FROM_OBS %*% counts),
                nrow = nrow(X_CELLS), ncol = 2L)
  yxa <- matrix(drop(MAP_XA_FROM_OBS %*% (counts * OBS_CELLS$Y)),
                nrow = nrow(X_CELLS), ncol = 2L)

  if (any(nxa <= 0L)) return(estimation_failure("empty-emulation-x-a-cell"))

  fit <- tryCatch(
    suppressWarnings(stats::glm.fit(
      x = PS_MATRIX,
      y = cbind(nxa[, 2L], nxa[, 1L]),
      family = stats::binomial()
    )),
    error = function(e) NULL
  )
  if (is.null(fit) || !isTRUE(fit$converged)) {
    return(estimation_failure("propensity-fit-failed"))
  }
  if (fit$rank < ncol(PS_MATRIX) || any(!is.finite(fit$coefficients))) {
    return(estimation_failure("propensity-rank-deficient"))
  }

  e <- fit$fitted.values
  if (any(!is.finite(e)) || any(e < 1e-6 | e > 1 - 1e-6)) {
    return(estimation_failure("propensity-out-of-bounds"))
  }

  m <- yxa / nxa
  m0 <- m[, 1L]
  m1 <- m[, 2L]
  contrast <- m1 - m0

  x_index <- OBS_TO_X
  a <- OBS_CELLS$A
  y <- OBS_CELLS$Y
  residual <- ifelse(
    a == 1L,
    (y - m1[x_index]) / e[x_index],
    -(y - m0[x_index]) / (1 - e[x_index])
  )
  h <- contrast[x_index] + residual
  psi_e <- sum(counts * h) / n_e
  var_h <- weighted_sample_variance(h, counts)
  if (!is.finite(var_h) || var_h <= 0) {
    return(estimation_failure("nonpositive-emulation-variance"))
  }
  se_e <- sqrt(var_h / n_e)

  f_e <- drop(MAP_X_FROM_OBS %*% counts) / n_e
  f_t <- trial$nx / trial$n
  if (any(f_t > 0 & f_e <= 0)) {
    return(estimation_failure("no-emulation-target-support"))
  }
  ratio <- ifelse(f_t == 0, 0, f_t / f_e)
  if (any(!is.finite(ratio))) return(estimation_failure("nonfinite-density-ratio"))

  transported_residual <- ratio[x_index] * residual
  transported_base <- sum(f_t * contrast)
  psi_transport <- transported_base + sum(counts * transported_residual) / n_e

  var_e_transport <- weighted_sample_variance(transported_residual, counts)
  trial_target_if <- contrast[OBS_TO_X] - transported_base
  var_t_target <- weighted_sample_variance(trial_target_if, trial$counts)
  trial_delta_if <- trial_target_if - trial$if_rd
  var_t_delta <- weighted_sample_variance(trial_delta_if, trial$counts)

  variance_transport <- var_e_transport / n_e + var_t_target / trial$n
  variance_delta_align <- var_e_transport / n_e + var_t_delta / trial$n
  if (any(!is.finite(c(variance_transport, variance_delta_align))) ||
      variance_transport <= 0 || variance_delta_align <= 0) {
    return(estimation_failure("nonpositive-stacked-variance"))
  }

  delta_raw <- psi_e - trial$est
  se_delta_raw <- sqrt(se_e^2 + trial$se^2)
  delta_align <- psi_transport - trial$est

  if (any(!is.finite(c(
    trial$est, trial$se, psi_e, se_e, delta_raw, se_delta_raw,
    psi_transport, variance_transport, delta_align, variance_delta_align
  )))) return(estimation_failure("nonfinite-estimate"))

  list(
    ok = TRUE,
    psi_t = trial$est,
    se_t = trial$se,
    psi_e = psi_e,
    se_e = se_e,
    delta_raw = delta_raw,
    se_delta_raw = se_delta_raw,
    psi_transport = psi_transport,
    se_transport = sqrt(variance_transport),
    delta_observed_align = delta_align,
    se_delta_observed_align = sqrt(variance_delta_align)
  )
}

## Critique implementation fix: this is the published sceptical construction,
## not a combined-standard-error surrogate. The original study is the trial,
## the replication is the emulation, and c is their variance ratio.
SCEPTICAL_SOURCE <- "Köppe et al. 2025, BMC Medical Research Methodology, DOI 10.1186/s12874-025-02589-z"
SCEPTICAL_LOCATOR <- "Methods section, equation defining the sceptical z-value and two-sided sceptical p-value"
SCEPTICAL_EQUATION <- "zS^2=(zo^2+zr^2)/2-sqrt(((zo^2-zr^2)/2)^2+c); c=se_o^2/se_r^2; pS=2*Phi(-zS)"

sceptical_components <- function(est_o, se_o, est_r, se_r, null = 0) {
  if (any(!is.finite(c(est_o, se_o, est_r, se_r, null))) ||
      se_o <= 0 || se_r <= 0) {
    return(c(z_o = NA_real_, z_r = NA_real_, c = NA_real_,
             z_s_squared = NA_real_, p_s = NA_real_))
  }
  z_o <- (est_o - null) / se_o
  z_r <- (est_r - null) / se_r
  c_rel <- se_o^2 / se_r^2
  z2 <- (z_o^2 + z_r^2) / 2 -
    sqrt(((z_o^2 - z_r^2) / 2)^2 + c_rel)
  p_s <- if (z_o * z_r <= 0 || z2 <= 0) {
    1
  } else {
    2 * stats::pnorm(-sqrt(z2))
  }
  c(z_o = z_o, z_r = z_r, c = c_rel,
    z_s_squared = max(0, z2), p_s = p_s)
}

sceptical_pvalue <- function(est_o, se_o, est_r, se_r, null = 0) {
  unname(sceptical_components(est_o, se_o, est_r, se_r, null)[["p_s"]])
}

## Numerical inversion keeps the source construction intact. Coverage remains
## approximate because the two component estimators use Wald standard errors.
sceptical_confidence_set <- function(est_o, se_o, est_r, se_r,
                                     alpha = SCEPTICAL_ALPHA) {
  p_at <- function(theta) sceptical_pvalue(est_o, se_o, est_r, se_r, theta)
  center_low <- min(est_o, est_r)
  center_high <- max(est_o, est_r)
  step <- max(se_o, se_r, abs(est_o - est_r), .Machine$double.eps) * 4

  lower <- center_low - step
  k <- 0L
  while (p_at(lower) > alpha && k < 30L) {
    step <- step * 2
    lower <- center_low - step
    k <- k + 1L
  }
  if (p_at(lower) > alpha) stop("could not bracket lower sceptical limit")

  step <- max(se_o, se_r, abs(est_o - est_r), .Machine$double.eps) * 4
  upper <- center_high + step
  k <- 0L
  while (p_at(upper) > alpha && k < 30L) {
    step <- step * 2
    upper <- center_high + step
    k <- k + 1L
  }
  if (p_at(upper) > alpha) stop("could not bracket upper sceptical limit")

  c(
    lower = stats::uniroot(function(x) p_at(x) - alpha,
                           c(lower, center_low), tol = 1e-10)$root,
    upper = stats::uniroot(function(x) p_at(x) - alpha,
                           c(center_high, upper), tol = 1e-10)$root
  )
}

## Frozen values exercise the source equation, relative precision and the
## required discordant-sign behavior before simulation starts.
sceptical_source_checks <- function() {
  a <- sceptical_components(sqrt(5), 1, sqrt(5), 1)
  b <- sceptical_components(6, 2, 3, 1)
  c0 <- sceptical_components(2, 1, -2, 1)
  observed <- c(a[["z_s_squared"]], a[["p_s"]],
                b[["z_s_squared"]], c0[["p_s"]])
  expected <- c(4, 0.0455002638963584, 7, 1)
  data.frame(
    check = c(
      "equal-precision-zs-squared",
      "equal-precision-two-sided-p",
      "relative-precision-zs-squared",
      "discordant-sign-p"
    ),
    expected = expected,
    observed = observed,
    tolerance = rep(1e-12, 4L),
    passed = abs(observed - expected) <= 1e-12,
    source = SCEPTICAL_SOURCE,
    locator = SCEPTICAL_LOCATOR,
    equation = SCEPTICAL_EQUATION,
    stringsAsFactors = FALSE
  )
}

blank_result_row <- function(rep_id, precision_index, why) {
  data.frame(
    replicate = as.integer(rep_id),
    precision = PRECISION$precision[[precision_index]],
    n_trial = PRECISION$n_trial[[precision_index]],
    n_emulation = PRECISION$n_emulation[[precision_index]],
    psi_t = NA_real_, se_t = NA_real_,
    psi_e = NA_real_, se_e = NA_real_,
    delta_raw = NA_real_, se_delta_raw = NA_real_,
    psi_transport = NA_real_, se_transport = NA_real_,
    delta_observed_align = NA_real_, se_delta_observed_align = NA_real_,
    direction_agree = NA_integer_, overlap_agree = NA_integer_,
    forced_delta02 = NA_character_, joint_delta02 = NA_character_,
    compatibility_delta02 = NA_real_,
    sceptical_p = NA_real_, sceptical_success = NA_integer_,
    sceptical_ci_lower = NA_real_, sceptical_ci_upper = NA_real_,
    sceptical_fail = NA_character_, fail = why,
    stringsAsFactors = FALSE
  )
}

result_from_counts <- function(trial_counts, emulation_counts, rep_id,
                               precision_index) {
  fit <- tryCatch(
    estimate_pair(trial_counts, emulation_counts),
    error = function(e) estimation_failure("estimator-error")
  )
  if (!isTRUE(fit$ok)) {
    return(blank_result_row(rep_id, precision_index, fit$reason))
  }

  lower_t <- fit$psi_t - Z95 * fit$se_t
  upper_t <- fit$psi_t + Z95 * fit$se_t
  lower_e <- fit$psi_e - Z95 * fit$se_e
  upper_e <- fit$psi_e + Z95 * fit$se_e

  direction <- as.integer(sign(fit$psi_t) == sign(fit$psi_e))
  overlap <- as.integer(max(lower_t, lower_e) <= min(upper_t, upper_e))

  forced <- if (abs(fit$delta_raw) < DELTA_PRIMARY) {
    "aligned"
  } else {
    "mismatched"
  }
  lo90 <- fit$delta_raw - Z90 * fit$se_delta_raw
  hi90 <- fit$delta_raw + Z90 * fit$se_delta_raw
  joint <- if (lo90 >= -DELTA_PRIMARY && hi90 <= DELTA_PRIMARY) {
    "aligned"
  } else if (lo90 > DELTA_PRIMARY || hi90 < -DELTA_PRIMARY) {
    "mismatched"
  } else {
    "indeterminate"
  }
  compatibility <- stats::pnorm(
    (DELTA_PRIMARY - fit$delta_raw) / fit$se_delta_raw
  ) - stats::pnorm(
    (-DELTA_PRIMARY - fit$delta_raw) / fit$se_delta_raw
  )

  p_s <- sceptical_pvalue(fit$psi_t, fit$se_t, fit$psi_e, fit$se_e)
  ci_s <- try(sceptical_confidence_set(
    fit$psi_t, fit$se_t, fit$psi_e, fit$se_e
  ), silent = TRUE)
  sceptical_failed <- inherits(ci_s, "try-error") || any(!is.finite(ci_s))
  if (sceptical_failed) ci_s <- c(lower = NA_real_, upper = NA_real_)

  data.frame(
    replicate = as.integer(rep_id),
    precision = PRECISION$precision[[precision_index]],
    n_trial = PRECISION$n_trial[[precision_index]],
    n_emulation = PRECISION$n_emulation[[precision_index]],
    psi_t = fit$psi_t, se_t = fit$se_t,
    psi_e = fit$psi_e, se_e = fit$se_e,
    delta_raw = fit$delta_raw, se_delta_raw = fit$se_delta_raw,
    psi_transport = fit$psi_transport, se_transport = fit$se_transport,
    delta_observed_align = fit$delta_observed_align,
    se_delta_observed_align = fit$se_delta_observed_align,
    direction_agree = direction,
    overlap_agree = overlap,
    forced_delta02 = forced,
    joint_delta02 = joint,
    compatibility_delta02 = compatibility,
    sceptical_p = p_s,
    sceptical_success = as.integer(p_s <= SCEPTICAL_ALPHA),
    sceptical_ci_lower = ci_s[["lower"]],
    sceptical_ci_upper = ci_s[["upper"]],
    sceptical_fail = if (sceptical_failed) "inversion-failed" else NA_character_,
    fail = NA_character_,
    stringsAsFactors = FALSE
  )
}

run_replicate <- function(scen, rep_id) {
  pair <- tryCatch(gen_nested_pair(scen), error = function(e) NULL)
  if (is.null(pair)) {
    return(do.call(rbind, lapply(
      seq_len(nrow(PRECISION)),
      function(k) blank_result_row(rep_id, k, "dgm-failed")
    )))
  }

  do.call(rbind, lapply(seq_len(nrow(PRECISION)), function(k) {
    result_from_counts(pair$trial[[k]], pair$emulation[[k]], rep_id, k)
  }))
}
