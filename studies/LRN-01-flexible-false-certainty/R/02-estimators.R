## LRN-01 support stress study: estimators and diagnostics.

model_failure <- function(why) list(fail = why)
model_ok <- function(x) is.list(x) && is.null(x$fail)

main_history_matrix <- function(dat, t) {
  cols <- list(`(Intercept)` = rep(1, nrow(dat)), B1 = dat$B1, B2 = dat$B2,
               B3 = dat$B3, tanh_B1 = tanh(dat$B1),
               Lt = dat[[paste0("L", t)]],
               tanh_Lt = tanh(dat[[paste0("L", t)]]),
               Mt = dat[[paste0("M", t)]])
  if (t > 0) {
    cols$prev_A <- dat[[paste0("A", t - 1L)]]
    cols$mean_A_prev <- mean_columns(dat, "A", 0:(t - 1L))
    cols$mean_L_prev <- mean_columns(dat, "L", 0:(t - 1L))
    cols$mean_M_prev <- mean_columns(dat, "M", 0:(t - 1L))
  }
  as.matrix(as.data.frame(cols, check.names = FALSE))
}

main_q_matrix <- function(dat, t, action = NULL) {
  x <- main_history_matrix(dat, t)
  a <- if (is.null(action)) dat[[paste0("A", t)]] else rep(action, nrow(dat))
  cbind(x, At = a, At_B3 = a * dat$B3,
        At_B1pos = a * as.integer(dat$B1 > 0),
        At_tanhLt = a * tanh(dat[[paste0("L", t)]]))
}

spline_specs <- function(dat, t) {
  vars <- c("B1", paste0("L", 0:t))
  out <- list()
  for (v in vars) {
    b <- splines::ns(dat[[v]], df = 4)
    out[[v]] <- list(knots = attr(b, "knots"),
                     boundary = attr(b, "Boundary.knots"))
  }
  out
}

eval_spline <- function(x, spec) {
  suppressWarnings(splines::ns(x, knots = spec$knots,
                                Boundary.knots = spec$boundary,
                                intercept = FALSE))
}

rich_matrix <- function(dat, t, q_model = FALSE, action = NULL, specs = NULL) {
  if (is.null(specs)) specs <- spline_specs(dat, t)
  cols <- list(`(Intercept)` = rep(1, nrow(dat)), B1 = dat$B1,
               B2 = dat$B2, B3 = dat$B3)
  for (j in 0:t) cols[[paste0("L", j)]] <- dat[[paste0("L", j)]]
  for (j in 0:t) cols[[paste0("M", j)]] <- dat[[paste0("M", j)]]
  if (t > 0) for (j in 0:(t - 1L)) cols[[paste0("A", j)]] <- dat[[paste0("A", j)]]
  if (t > 0) {
    cols$mean_A_prev <- mean_columns(dat, "A", 0:(t - 1L))
    cols$mean_L_prev <- mean_columns(dat, "L", 0:(t - 1L))
    cols$mean_M_prev <- mean_columns(dat, "M", 0:(t - 1L))
  }
  for (v in names(specs)) {
    b <- eval_spline(dat[[v]], specs[[v]])
    for (k in seq_len(ncol(b))) cols[[paste0("ns_", v, "_", k)]] <- b[, k]
  }
  current <- eval_spline(dat[[paste0("L", t)]], specs[[paste0("L", t)]])
  modifiers <- list(B3 = dat$B3, Mt = dat[[paste0("M", t)]])
  if (t > 0) {
    modifiers$prev_A <- dat[[paste0("A", t - 1L)]]
    modifiers$mean_A_prev <- mean_columns(dat, "A", 0:(t - 1L))
  }
  for (m in names(modifiers)) for (k in seq_len(ncol(current))) {
    cols[[paste0("ns_Lt_", k, "_x_", m)]] <- current[, k] * modifiers[[m]]
  }
  if (q_model) {
    a <- if (is.null(action)) dat[[paste0("A", t)]] else rep(action, nrow(dat))
    cols$At <- a
    cols$At_B3 <- a * dat$B3
    cols$At_B1pos <- a * as.integer(dat$B1 > 0)
    cols$At_Mt <- a * dat[[paste0("M", t)]]
    for (k in seq_len(ncol(current))) cols[[paste0("At_ns_Lt_", k)]] <- a * current[, k]
  }
  attr(cols, "specs") <- specs
  as.matrix(as.data.frame(cols, check.names = FALSE))
}

fit_reduced_glm <- function(raw, y, family, standardize, meta) {
  if (nrow(raw) != length(y) || any(!is.finite(raw)) || any(!is.finite(y)))
    return(model_failure("nonfinite-design"))
  center <- setNames(rep(0, ncol(raw)), colnames(raw))
  scale <- setNames(rep(1, ncol(raw)), colnames(raw))
  variable <- rep(TRUE, ncol(raw)); names(variable) <- colnames(raw)
  for (j in seq_len(ncol(raw))) {
    if (colnames(raw)[j] == "(Intercept)") next
    variable[j] <- diff(range(raw[, j])) > 0
    if (standardize && variable[j]) {
      center[j] <- mean(raw[, j])
      scale[j] <- stats::sd(raw[, j])
      variable[j] <- is.finite(scale[j]) && scale[j] > 0
    }
  }
  keep0 <- names(variable)[variable]
  if (!length(keep0)) return(model_failure("empty-design"))
  x <- raw[, keep0, drop = FALSE]
  x <- sweep(x, 2, center[keep0], "-")
  x <- sweep(x, 2, scale[keep0], "/")

  ## Critique fix: constants and aliases are removed before every fit by the
  ## same fixed-tolerance pivoted QR policy. Visit is never entered as a constant.
  qr_x <- qr(x, tol = QR_TOL, LAPACK = FALSE)
  if (qr_x$rank < 1L) return(model_failure("rank-zero"))
  kept <- colnames(x)[sort(qr_x$pivot[seq_len(qr_x$rank)])]
  x <- x[, kept, drop = FALSE]
  warnings <- character()
  fit <- tryCatch(
    withCallingHandlers(
      stats::glm.fit(x = x, y = y, family = family),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }),
    error = function(e) e)
  if (inherits(fit, "error")) return(model_failure(paste0("glm-error: ", conditionMessage(fit))))
  if (!isTRUE(fit$converged)) return(model_failure("glm-nonconvergence"))
  if (any(!is.finite(fit$coefficients))) return(model_failure("nonfinite-coefficients"))
  list(coef = unname(fit$coefficients), raw_names = colnames(raw),
       center = center, scale = scale, kept = kept, warnings = unique(warnings),
       meta = meta, fail = NULL)
}

raw_for_model <- function(model, dat, action = NULL) {
  m <- model$meta
  if (m$kind == "main" && m$role == "g") main_history_matrix(dat, m$t) else
  if (m$kind == "main" && m$role == "q") main_q_matrix(dat, m$t, action) else
  rich_matrix(dat, m$t, q_model = m$role == "q", action = action, specs = m$specs)
}

model_matrix <- function(model, dat, action = NULL) {
  raw <- raw_for_model(model, dat, action)
  if (!all(model$raw_names %in% colnames(raw))) stop("required prediction column missing")
  x <- raw[, model$raw_names, drop = FALSE]
  x <- sweep(x, 2, model$center[model$raw_names], "-")
  x <- sweep(x, 2, model$scale[model$raw_names], "/")
  x[, model$kept, drop = FALSE]
}

predict_model <- function(model, dat, action = NULL) {
  if (!model_ok(model)) stop(model$fail)
  p <- expit(drop(model_matrix(model, dat, action) %*% model$coef))
  if (any(!is.finite(p))) stop("nonfinite-prediction")
  p
}

fit_g_models <- function(dat, rows, kind = c("main", "rich")) {
  kind <- match.arg(kind)
  out <- vector("list", N_VISITS)
  train <- dat[rows, , drop = FALSE]
  for (t in VISITS) {
    if (kind == "main") {
      raw <- main_history_matrix(train, t); specs <- NULL
    } else {
      specs <- spline_specs(train, t)
      raw <- rich_matrix(train, t, specs = specs)
    }
    out[[t + 1L]] <- fit_reduced_glm(
      raw, train[[paste0("A", t)]], stats::binomial(), kind == "rich",
      list(kind = kind, role = "g", t = t, specs = specs))
  }
  out
}

fit_q_models <- function(dat, rows, kind = c("main", "rich"), action) {
  kind <- match.arg(kind)
  train <- dat[rows, , drop = FALSE]
  target <- train$Y
  out <- vector("list", N_VISITS)
  for (t in rev(VISITS)) {
    if (kind == "main") {
      raw <- main_q_matrix(train, t); specs <- NULL
    } else {
      specs <- spline_specs(train, t)
      raw <- rich_matrix(train, t, q_model = TRUE, specs = specs)
    }
    fam <- if (t == 5L) stats::binomial() else stats::quasibinomial()
    out[[t + 1L]] <- fit_reduced_glm(
      raw, target, fam, kind == "rich",
      list(kind = kind, role = "q", t = t, specs = specs))
    if (!model_ok(out[[t + 1L]])) return(out)
    target <- predict_model(out[[t + 1L]], train, action)
  }
  out
}

all_models_ok <- function(x) all(vapply(x, model_ok, logical(1)))
models_warned <- function(x) any(vapply(x, function(z) model_ok(z) && length(z$warnings), logical(1)))

balanced_folds <- function(dat) {
  strata <- interaction(dat$B3, dat$Y, drop = TRUE)
  fold <- integer(nrow(dat))
  for (idx in split(seq_len(nrow(dat)), strata)) {
    idx <- sample(idx, length(idx), replace = FALSE)
    fold[idx] <- rep(1:2, length.out = length(idx))
  }
  fold
}

log_loss <- function(y, p) {
  p <- clip(p, 1e-6, 1 - 1e-6)
  mean(-y * log(p) - (1 - y) * log(1 - p))
}

phi_from_models <- function(dat, g, q, action) {
  qpred <- lapply(VISITS, function(t) predict_model(q[[t + 1L]], dat, action))
  phi <- qpred[[1L]]
  adherence <- rep(TRUE, nrow(dat)); denom <- rep(1, nrow(dat))
  truncation <- numeric(N_VISITS)
  for (t in VISITS) {
    p1 <- predict_model(g[[t + 1L]], dat)
    req <- if (action == 1) p1 else 1 - p1
    truncation[t + 1L] <- mean(req < PROB_TRUNC[1] | req > PROB_TRUNC[2])
    denom <- denom * clip(req, PROB_TRUNC[1], PROB_TRUNC[2])
    adherence <- adherence & dat[[paste0("A", t)]] == action
    next_q <- if (t == 5L) dat$Y else qpred[[t + 2L]]
    phi <- phi + adherence / denom * (next_q - qpred[[t + 1L]])
  }
  list(phi = phi, truncation = truncation)
}

numeric_jacobian <- function(fn, theta) {
  p <- length(theta); out <- matrix(NA_real_, p, p)
  for (j in seq_len(p)) {
    h <- .Machine$double.eps^(1/3) * (abs(theta[j]) + 1)
    up <- theta; down <- theta
    up[j] <- up[j] + h; down[j] <- down[j] - h
    out[, j] <- (fn(up) - fn(down)) / (2 * h)
  }
  out
}

stacked_covariance <- function(theta, equations) {
  t0 <- proc.time()[["elapsed"]]
  mean_fn <- function(z) equations(z, individual = FALSE)
  jac <- numeric_jacobian(mean_fn, theta)
  condition <- tryCatch(kappa(jac, exact = FALSE), error = function(e) Inf)
  if (!is.finite(condition) || condition > JACOBIAN_CONDITION_MAX)
    return(list(fail = "ill-conditioned-jacobian", condition = condition,
                seconds = proc.time()[["elapsed"]] - t0))
  u <- equations(theta, individual = TRUE)
  uc <- sweep(u, 2, colMeans(u), "-")
  meat <- crossprod(uc) / nrow(u)
  inv <- tryCatch(solve(jac), error = function(e) NULL)
  if (is.null(inv)) return(list(fail = "singular-jacobian", condition = condition,
                                 seconds = proc.time()[["elapsed"]] - t0))
  vcov <- inv %*% meat %*% t(inv) / nrow(u)
  if (any(!is.finite(vcov))) return(list(fail = "nonfinite-sandwich",
                                        condition = condition,
                                        seconds = proc.time()[["elapsed"]] - t0))
  list(vcov = vcov, condition = condition,
       score_residual = max(abs(mean_fn(theta))), fail = NULL,
       seconds = proc.time()[["elapsed"]] - t0)
}

pack_g <- function(g) {
  theta <- numeric(); idx <- vector("list", N_VISITS)
  for (t in VISITS) {
    idx[[t + 1L]] <- length(theta) + seq_along(g[[t + 1L]]$coef)
    theta <- c(theta, g[[t + 1L]]$coef)
  }
  list(theta = theta, idx = idx)
}

ipw_weight_quantities <- function(dat, xg, theta, idx, action, mu = NULL) {
  follow <- rep(TRUE, nrow(dat)); denom <- rep(1, nrow(dat))
  for (t in VISITS) {
    p <- expit(drop(xg[[t + 1L]] %*% theta[idx[[t + 1L]]]))
    req <- if (action == 1) p else 1 - p
    denom <- denom * req
    follow <- follow & dat[[paste0("A", t)]] == action
  }
  w <- numeric(nrow(dat))
  if (any(denom[follow] <= 0 | !is.finite(denom[follow]))) stop("invalid-ipw-denominator")
  w[follow] <- 1 / denom[follow]
  wc <- pmin(w, WEIGHT_CAP)
  if (sum(wc) <= 0) stop("zero-weighted-denominator")
  if (is.null(mu)) mu <- sum(wc * dat$Y) / sum(wc)
  list(mu = mu, score = wc * (dat$Y - mu), uncapped = w,
       capped = wc, followers = sum(follow),
       max_weight = if (any(follow)) max(w[follow]) else Inf,
       n_capped = sum(w[follow] > WEIGHT_CAP),
       ess = sum(wc)^2 / sum(wc^2))
}

## Critique fix: the cap is fixed at 50, so no empirical-quantile parameter is
## omitted. The sandwich stacks every treatment score and both Hajek equations.
estimate_ipw <- function(dat, g) {
  if (!all_models_ok(g)) return(model_failure("treatment-model-failed"))
  xg <- lapply(g, model_matrix, dat = dat)
  pg <- pack_g(g); theta <- pg$theta; idx <- pg$idx
  q0 <- tryCatch(ipw_weight_quantities(dat, xg, theta, idx, 0L), error = identity)
  q1 <- tryCatch(ipw_weight_quantities(dat, xg, theta, idx, 1L), error = identity)
  if (inherits(q0, "error") || inherits(q1, "error")) return(model_failure("ipw-weight-failed"))
  mu_idx <- length(theta) + 1:2
  theta <- c(theta, q0$mu, q1$mu)
  equations <- function(th, individual) {
    blocks <- lapply(VISITS, function(t) {
      p <- expit(drop(xg[[t + 1L]] %*% th[idx[[t + 1L]]]))
      xg[[t + 1L]] * (dat[[paste0("A", t)]] - p)
    })
    w0 <- ipw_weight_quantities(dat, xg, th, idx, 0L, th[mu_idx[1]])
    w1 <- ipw_weight_quantities(dat, xg, th, idx, 1L, th[mu_idx[2]])
    blocks <- c(blocks, list(w0$score, w1$score))
    if (individual) do.call(cbind, blocks) else unlist(lapply(blocks, colMeans))
  }
  sw <- tryCatch(stacked_covariance(theta, equations), error = function(e)
    list(fail = paste0("sandwich-error: ", conditionMessage(e))))
  if (!is.null(sw$fail)) return(c(model_failure(sw$fail), sw[setdiff(names(sw), "fail")]))
  contrast <- numeric(length(theta)); contrast[mu_idx] <- c(-1, 1)
  se <- sqrt(drop(t(contrast) %*% sw$vcov %*% contrast))
  est <- q1$mu - q0$mu
  if (!is.finite(est) || !is.finite(se)) return(model_failure("nonfinite-estimate"))
  list(est = est, se = se, fail = NULL, numerical_warning = models_warned(g),
       condition = sw$condition, score_residual = sw$score_residual,
       jacobian_seconds = sw$seconds,
       diagnostics = list(a0 = q0, a1 = q1,
                          retained = vapply(g, function(z) paste(z$kept, collapse = ";"), "")))
}

pack_main_aipw <- function(g, q) {
  p <- pack_g(g); theta <- p$theta; idx_q <- list(`0` = vector("list", N_VISITS),
                                                  `1` = vector("list", N_VISITS))
  for (a in 0:1) for (t in VISITS) {
    fit <- q[[as.character(a)]][[t + 1L]]
    idx_q[[as.character(a)]][[t + 1L]] <- length(theta) + seq_along(fit$coef)
    theta <- c(theta, fit$coef)
  }
  list(theta = theta, idx_g = p$idx, idx_q = idx_q)
}

main_phi_theta <- function(dat, xg, xq_set, th, idx_g, idx_q, action) {
  qpred <- lapply(VISITS, function(t)
    expit(drop(xq_set[[as.character(action)]][[t + 1L]] %*%
                 th[idx_q[[as.character(action)]][[t + 1L]]])))
  phi <- qpred[[1L]]; adhere <- rep(TRUE, nrow(dat)); denom <- rep(1, nrow(dat))
  for (t in VISITS) {
    p <- expit(drop(xg[[t + 1L]] %*% th[idx_g[[t + 1L]]]))
    req <- if (action == 1) p else 1 - p
    denom <- denom * clip(req, PROB_TRUNC[1], PROB_TRUNC[2])
    adhere <- adhere & dat[[paste0("A", t)]] == action
    target <- if (t == 5L) dat$Y else qpred[[t + 2L]]
    phi <- phi + adhere / denom * (target - qpred[[t + 1L]])
  }
  phi
}

## Critique fix: nuisance estimation is included through a full stacked system.
## Separate backward Q systems implement the protocol's strategy-specific recursion.
estimate_main_aipw <- function(dat, g) {
  if (!all_models_ok(g)) return(model_failure("treatment-model-failed"))
  q <- list(`0` = fit_q_models(dat, seq_len(nrow(dat)), "main", 0L),
            `1` = fit_q_models(dat, seq_len(nrow(dat)), "main", 1L))
  if (!all_models_ok(q$`0`) || !all_models_ok(q$`1`)) return(model_failure("q-model-failed"))
  xg <- lapply(g, model_matrix, dat = dat)
  xq_obs <- lapply(q, function(qa) lapply(qa, model_matrix, dat = dat))
  xq_set <- list(
    `0` = lapply(q$`0`, model_matrix, dat = dat, action = 0L),
    `1` = lapply(q$`1`, model_matrix, dat = dat, action = 1L))
  packed <- pack_main_aipw(g, q)
  theta <- packed$theta; idx_g <- packed$idx_g; idx_q <- packed$idx_q
  phi0 <- main_phi_theta(dat, xg, xq_set, theta, idx_g, idx_q, 0L)
  phi1 <- main_phi_theta(dat, xg, xq_set, theta, idx_g, idx_q, 1L)
  mu_idx <- length(theta) + 1:2
  theta <- c(theta, mean(phi0), mean(phi1))
  equations <- function(th, individual) {
    blocks <- lapply(VISITS, function(t) {
      p <- expit(drop(xg[[t + 1L]] %*% th[idx_g[[t + 1L]]]))
      xg[[t + 1L]] * (dat[[paste0("A", t)]] - p)
    })
    for (a in 0:1) {
      qp <- lapply(VISITS, function(t)
        expit(drop(xq_set[[as.character(a)]][[t + 1L]] %*%
                     th[idx_q[[as.character(a)]][[t + 1L]]])))
      for (t in VISITS) {
        target <- if (t == 5L) dat$Y else qp[[t + 2L]]
        fitted <- expit(drop(xq_obs[[as.character(a)]][[t + 1L]] %*%
                              th[idx_q[[as.character(a)]][[t + 1L]]]))
        blocks[[length(blocks) + 1L]] <-
          xq_obs[[as.character(a)]][[t + 1L]] * (target - fitted)
      }
    }
    p0 <- main_phi_theta(dat, xg, xq_set, th, idx_g, idx_q, 0L)
    p1 <- main_phi_theta(dat, xg, xq_set, th, idx_g, idx_q, 1L)
    blocks <- c(blocks, list(p0 - th[mu_idx[1]], p1 - th[mu_idx[2]]))
    if (individual) do.call(cbind, blocks) else unlist(lapply(blocks, colMeans))
  }
  sw <- tryCatch(stacked_covariance(theta, equations), error = function(e)
    list(fail = paste0("sandwich-error: ", conditionMessage(e))))
  if (!is.null(sw$fail)) return(c(model_failure(sw$fail), sw[setdiff(names(sw), "fail")]))
  contrast <- numeric(length(theta)); contrast[mu_idx] <- c(-1, 1)
  est <- theta[mu_idx[2]] - theta[mu_idx[1]]
  se <- sqrt(drop(t(contrast) %*% sw$vcov %*% contrast))
  if (!is.finite(est) || !is.finite(se)) return(model_failure("nonfinite-estimate"))
  tr <- sapply(0:1, function(a) phi_from_models(dat, g, q[[as.character(a)]], a)$truncation)
  list(est = est, se = se, fail = NULL,
       numerical_warning = models_warned(g) || models_warned(q$`0`) || models_warned(q$`1`),
       condition = sw$condition, score_residual = sw$score_residual,
       jacobian_seconds = sw$seconds, truncation = tr)
}

ridge_support_flags <- function(train_x, train_a, validation_x, action) {
  z <- train_x[train_a == action, , drop = FALSE]
  p <- ncol(train_x)
  if (nrow(z) < max(MIN_ACTION_ROWS, 2L * p))
    return(list(flag = rep(TRUE, nrow(validation_x)), cutoff = NA_real_, automatic = TRUE))
  lambda <- RIDGE_MULTIPLIER * sum(z^2) / p
  inv <- tryCatch(chol2inv(chol(crossprod(z) + diag(lambda, p))),
                  error = function(e) NULL)
  if (is.null(inv)) return(list(flag = rep(TRUE, nrow(validation_x)),
                                cutoff = NA_real_, automatic = TRUE))
  h <- rowSums((z %*% inv) * z)
  deleted <- h / pmax(1 - h, .Machine$double.eps)
  cutoff <- unname(stats::quantile(deleted, RIDGE_QUANTILE, names = FALSE, type = 8))
  hv <- rowSums((validation_x %*% inv) * validation_x)
  list(flag = hv > cutoff, cutoff = cutoff, automatic = FALSE)
}

weight_diagnostic <- function(dat, p_required, action) {
  follow <- rowSums(as.matrix(dat[paste0("A", VISITS)]) == action) == N_VISITS
  den <- apply(p_required, 1, prod)
  w <- numeric(nrow(dat)); w[follow] <- 1 / den[follow]
  finite <- is.finite(w[follow])
  if (!any(follow) || !all(finite)) return(list(followers = sum(follow), ess = 0, max = Inf))
  wf <- w[follow]
  list(followers = sum(follow), ess = sum(wf)^2 / sum(wf^2), max = max(wf))
}

crossfit_failure <- function(why) list(fail = why, est = NA_real_, se = NA_real_,
                                       numerical_warning = FALSE,
                                       support_red = NA, common_diagnostic_green = FALSE)

## Critique fix: both model classes use identical folds and explicit heldout
## losses. Deleted-row training leverage alone calibrates every cutoff.
estimate_crossfit <- function(dat, folds) {
  n <- nrow(dat)
  phi <- matrix(NA_real_, n, 2, dimnames = list(NULL, c("a0", "a1")))
  p1_obs <- matrix(NA_real_, n, N_VISITS)
  p_req <- array(NA_real_, c(n, N_VISITS, 2))
  prob_flag <- array(FALSE, c(n, N_VISITS, 2))
  lev_flag <- array(FALSE, c(n, N_VISITS, 2))
  loss_flex <- loss_main <- numeric(N_VISITS)
  loss_out_flex <- loss_out_main <- numeric(2)
  truncation <- matrix(NA_real_, N_VISITS, 2)
  warned <- FALSE; ridge_seconds <- 0

  for (fold in 1:2) {
    train <- which(folds != fold); valid <- which(folds == fold)
    g <- fit_g_models(dat, train, "rich")
    gm <- fit_g_models(dat, train, "main")
    q <- list(`0` = fit_q_models(dat, train, "rich", 0L),
              `1` = fit_q_models(dat, train, "rich", 1L))
    terminal_main <- fit_reduced_glm(main_q_matrix(dat[train, , drop = FALSE], 5L),
                                     dat$Y[train], stats::binomial(), FALSE,
                                     list(kind = "main", role = "q", t = 5L, specs = NULL))
    if (!all_models_ok(g) || !all_models_ok(gm) || !all_models_ok(q$`0`) ||
        !all_models_ok(q$`1`) || !model_ok(terminal_main))
      return(crossfit_failure("crossfit-model-failed"))
    warned <- warned || models_warned(g) || models_warned(gm) ||
      models_warned(q$`0`) || models_warned(q$`1`) || length(terminal_main$warnings) > 0
    dv <- dat[valid, , drop = FALSE]
    dt <- dat[train, , drop = FALSE]
    for (t in VISITS) {
      pf <- predict_model(g[[t + 1L]], dv)
      pm <- predict_model(gm[[t + 1L]], dv)
      p1_obs[valid, t + 1L] <- pf
      loss_flex[t + 1L] <- loss_flex[t + 1L] + length(valid) *
        log_loss(dv[[paste0("A", t)]], pf)
      loss_main[t + 1L] <- loss_main[t + 1L] + length(valid) *
        log_loss(dv[[paste0("A", t)]], pm)
      tx <- model_matrix(g[[t + 1L]], dt)
      vx <- model_matrix(g[[t + 1L]], dv)
      for (a in 0:1) {
        req <- if (a == 1) pf else 1 - pf
        p_req[valid, t + 1L, a + 1L] <- req
        prob_flag[valid, t + 1L, a + 1L] <- req < SUPPORT_PROB_THRESHOLD
        rt <- proc.time()[["elapsed"]]
        rf <- ridge_support_flags(tx, dt[[paste0("A", t)]], vx, a)
        ridge_seconds <- ridge_seconds + proc.time()[["elapsed"]] - rt
        lev_flag[valid, t + 1L, a + 1L] <- rf$flag
      }
    }
    for (a in 0:1) {
      ph <- phi_from_models(dv, g, q[[as.character(a)]], a)
      phi[valid, a + 1L] <- ph$phi
      truncation[, a + 1L] <- ifelse(is.na(truncation[, a + 1L]), 0,
                                      truncation[, a + 1L]) +
        length(valid) * ph$truncation
    }
    pred_flex_y <- predict_model(q$`0`[[6L]], dv)
    pred_main_y <- predict_model(terminal_main, dv)
    loss_out_flex[fold] <- log_loss(dv$Y, pred_flex_y)
    loss_out_main[fold] <- log_loss(dv$Y, pred_main_y)
  }

  loss_flex <- loss_flex / n; loss_main <- loss_main / n
  truncation <- truncation / n
  rd_phi <- phi[, 2] - phi[, 1]
  est <- mean(rd_phi); se <- stats::sd(rd_phi) / sqrt(n)
  if (!is.finite(est) || !is.finite(se)) return(crossfit_failure("nonfinite-crossfit-estimate"))

  mass <- mass_prob <- mass_lev <- matrix(NA_real_, N_VISITS, 2)
  for (a in 0:1) for (t in VISITS) {
    prior <- if (t == 0) rep(TRUE, n) else
      rowSums(as.matrix(dat[paste0("A", 0:(t - 1L))]) == a) == t
    w <- rep(1, n)
    if (t > 0) w <- 1 / apply(clip(p_req[, seq_len(t), a + 1L, drop = FALSE],
                                  PROB_TRUNC[1], PROB_TRUNC[2]), 1, prod)
    denom <- sum(w[prior])
    any_flag <- prob_flag[, t + 1L, a + 1L] | lev_flag[, t + 1L, a + 1L]
    mass[t + 1L, a + 1L] <- sum(w[prior] * any_flag[prior]) / denom
    mass_prob[t + 1L, a + 1L] <- sum(w[prior] * prob_flag[prior, t + 1L, a + 1L]) / denom
    mass_lev[t + 1L, a + 1L] <- sum(w[prior] * lev_flag[prior, t + 1L, a + 1L]) / denom
  }
  factual <- ifelse(as.matrix(dat[paste0("A", VISITS)]) == 1, p1_obs, 1 - p1_obs)
  wd0 <- weight_diagnostic(dat, p_req[, , 1], 0L)
  wd1 <- weight_diagnostic(dat, p_req[, , 2], 1L)
  common_green <- mean(factual < 0.01) < 0.01 &&
    wd0$followers > 0 && wd1$followers > 0 &&
    wd0$ess >= 0.25 * wd0$followers && wd1$ess >= 0.25 * wd1$followers &&
    wd0$max <= WEIGHT_CAP && wd1$max <= WEIGHT_CAP
  competitive <- all(loss_flex <= loss_main + 0.01) &&
    mean(loss_out_flex) <= mean(loss_out_main) + 0.01
  list(est = est, se = se, fail = NULL, numerical_warning = warned,
       support_red = any(mass >= SUPPORT_MASS_THRESHOLD),
       support_mass = mass, probability_mass = mass_prob, leverage_mass = mass_lev,
       common_diagnostic_green = common_green,
       factual_below_001 = mean(factual < 0.01),
       weight0 = wd0, weight1 = wd1,
       treatment_loss_flex = loss_flex, treatment_loss_main = loss_main,
       outcome_loss_flex = mean(loss_out_flex), outcome_loss_main = mean(loss_out_main),
       competitive_loss = competitive, truncation = truncation,
       ridge_seconds = ridge_seconds,
       rich_p = vapply(fit_g_models(dat, which(folds != 1L), "rich"),
                       function(z) if (model_ok(z)) length(z$coef) else NA_integer_, integer(1)))
}
