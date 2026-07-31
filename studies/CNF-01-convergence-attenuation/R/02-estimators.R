## Study 1 (CNF-01): truth, and the two estimators of the attenuating estimand.
##
## Truth is enumerated from the mechanism with assignment set rather than drawn,
## at N_TRUTH individuals, once per scenario. It is never estimated from the
## replicates: a noisy truth puts its own Monte Carlo error into every bias and
## every attenuation, and the attenuation differences this study has to resolve
## are small enough that it would matter.

## The four counterfactual risk curves the protocol needs.
##
##   itt1 / itt0  assignment set at baseline, later initiation left to run,
##                which is the estimand an emulation reports
##   pp1  / pp0   always treated versus never treated, the sustained-strategy
##                contrast the comparator arm would have supported had it
##                stayed untreated
##
## `pp1` and `itt1` coincide by construction here, because discontinuation is
## out of scope for this study; both are computed anyway so that the assumption
## is visible in the output rather than folded into an algebraic shortcut.
truth_for <- function(scen, n = N_TRUTH, chunk = 200000L) {
  ## Named numeric vectors indexed by horizon, initialized to zero, so that the
  ## accumulation below is a plain sum rather than a first-iteration special
  ## case. A scalar 0 here indexes out of bounds instead of returning NULL.
  z <- stats::setNames(numeric(length(HORIZONS)), as.character(HORIZONS))
  acc <- list(itt1 = z, itt0 = z, pp1 = z, pp0 = z, c = z)
  done <- 0L
  while (done < n) {
    m <- min(chunk, n - done)
    d_itt1 <- gen_replicate(scen, n = m, force_a0 = 1L)
    d_itt0 <- gen_replicate(scen, n = m, force_a0 = 0L)
    d_pp1  <- gen_replicate(scen, n = m, force_a0 = 1L,
                            block_later_initiation = TRUE)
    d_pp0  <- gen_replicate(scen, n = m, force_a0 = 0L,
                            block_later_initiation = TRUE)
    for (h in HORIZONS) {
      k <- as.character(h)
      acc$itt1[[k]] <- acc$itt1[[k]] + risk_by(d_itt1, h) * m
      acc$itt0[[k]] <- acc$itt0[[k]] + risk_by(d_itt0, h) * m
      acc$pp1[[k]]  <- acc$pp1[[k]]  + risk_by(d_pp1,  h) * m
      acc$pp0[[k]]  <- acc$pp0[[k]]  + risk_by(d_pp0,  h) * m
    }
    ## The diagnostic, on the assignment-set comparator arm.
    for (h in HORIZONS) {
      k <- as.character(h)
      acc$c[[k]] <- acc$c[[k]] +
        mean(!is.na(d_itt0$init_month) & d_itt0$init_month <= h) * m
    }
    done <- done + m
  }
  out <- data.frame(horizon = HORIZONS)
  g <- function(x) unname(x[as.character(HORIZONS)] / n)
  out$risk_itt1 <- g(acc$itt1); out$risk_itt0 <- g(acc$itt0)
  out$risk_pp1  <- g(acc$pp1);  out$risk_pp0  <- g(acc$pp0)
  out$rd_itt <- out$risk_itt1 - out$risk_itt0
  out$rd_pp  <- out$risk_pp1  - out$risk_pp0
  out$attenuation <- 1 - out$rd_itt / out$rd_pp
  out$c_true <- g(acc$c)
  rownames(out) <- NULL
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a

## g-formula standardization of the horizon-h risk over the baseline covariates.
## Fits one pooled logistic model for the horizon-h indicator and standardizes,
## which is the conventional baseline-adjusted analogue an emulation reports.
est_gformula <- function(dat, h) {
  y <- as.integer(!is.na(dat$event_month) & dat$event_month <= h)
  fit <- try(stats::glm(y ~ A0 + L + Z, family = stats::binomial(),
                        data = data.frame(y = y, dat)), silent = TRUE)
  if (inherits(fit, "try-error")) return(c(est = NA_real_, se = NA_real_))
  d1 <- dat; d1$A0 <- 1L
  d0 <- dat; d0$A0 <- 0L
  p1 <- stats::predict(fit, newdata = d1, type = "response")
  p0 <- stats::predict(fit, newdata = d0, type = "response")
  est <- mean(p1) - mean(p0)
  ## Delta-method SE via the influence-function form, which is what an applied
  ## analysis would report if it reported one at all. A bootstrap would be
  ## defensible and is 1000 times more expensive per replicate.
  X1 <- stats::model.matrix(~ A0 + L + Z, data = d1)
  X0 <- stats::model.matrix(~ A0 + L + Z, data = d0)
  g <- colMeans(X1 * p1 * (1 - p1)) - colMeans(X0 * p0 * (1 - p0))
  V <- try(stats::vcov(fit), silent = TRUE)
  se <- if (inherits(V, "try-error")) NA_real_ else sqrt(drop(t(g) %*% V %*% g))
  c(est = est, se = se)
}

## Stabilized IPTW on the baseline propensity score.
est_iptw <- function(dat, h) {
  y <- as.integer(!is.na(dat$event_month) & dat$event_month <= h)
  ps <- try(stats::glm(A0 ~ L + Z, family = stats::binomial(), data = dat),
            silent = TRUE)
  if (inherits(ps, "try-error")) return(c(est = NA_real_, se = NA_real_))
  e <- stats::predict(ps, type = "response")
  pA <- mean(dat$A0)
  w <- ifelse(dat$A0 == 1L, pA / e, (1 - pA) / (1 - e))
  m1 <- stats::weighted.mean(y[dat$A0 == 1L], w[dat$A0 == 1L])
  m0 <- stats::weighted.mean(y[dat$A0 == 0L], w[dat$A0 == 0L])
  est <- m1 - m0
  ## Sandwich-flavored SE treating the weights as fixed. This deliberately
  ## ignores weight-estimation uncertainty, which is what most applied
  ## emulations do; the relative error in the model SE will show what it costs.
  n <- nrow(dat)
  psi <- w * (dat$A0 * (y - m1) / pA - (1 - dat$A0) * (y - m0) / (1 - pA))
  se <- stats::sd(psi) / sqrt(n)
  c(est = est, se = se)
}
