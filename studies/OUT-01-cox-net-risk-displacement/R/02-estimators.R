## OUT-01 mechanism study: truth and estimators.

truth_for <- function(scen) {
  batches <- list()
  b <- 0L

  repeat {
    b <- b + 1L
    ## Truth streams are separate from replicate streams. Resetting by batch
    ## makes the same covariate profiles available to every scenario.
    set.seed(TRUTH_PROFILE_SEED + b)
    x <- draw_covariates(TRUTH_BATCH_SIZE)
    r1 <- profile_risks(x, scen, 1L)
    r0 <- profile_risks(x, scen, 0L)
    total_rd <- colMeans(r1$total - r0$total)
    net_rd <- colMeans(r1$net - r0$net)

    batches[[b]] <- data.frame(
      batch = b,
      horizon = HORIZONS,
      total_risk_1 = colMeans(r1$total),
      total_risk_0 = colMeans(r0$total),
      net_risk_1 = colMeans(r1$net),
      net_risk_0 = colMeans(r0$net),
      total_rd = total_rd,
      net_rd = net_rd,
      displacement = net_rd - total_rd,
      stringsAsFactors = FALSE
    )

    if (b >= TRUTH_INITIAL_BATCHES) {
      z <- do.call(rbind, batches)
      metric_names <- c("total_rd", "net_rd", "displacement")
      mcse <- vapply(metric_names, function(v) {
        max(vapply(split(z[[v]], z$horizon), function(q)
          stats::sd(q) / sqrt(length(q)), numeric(1)))
      }, numeric(1))
      if (all(is.finite(mcse)) && max(mcse) <= TRUTH_MCSE_LIMIT) break
    }
  }

  z <- do.call(rbind, batches)
  out <- do.call(rbind, lapply(HORIZONS, function(h) {
    d <- z[z$horizon == h, , drop = FALSE]
    means <- vapply(d[c("total_risk_1", "total_risk_0", "net_risk_1",
                        "net_risk_0", "total_rd", "net_rd", "displacement")],
                    mean, numeric(1))
    mcse <- vapply(d[c("total_risk_1", "total_risk_0", "net_risk_1",
                       "net_risk_0", "total_rd", "net_rd", "displacement")],
                   function(q) stats::sd(q) / sqrt(length(q)), numeric(1))
    critical <- stats::qt(0.975, df = nrow(d) - 1L)
    signed_lo <- means[["displacement"]] - critical * mcse[["displacement"]]
    signed_hi <- means[["displacement"]] + critical * mcse[["displacement"]]
    if (signed_lo <= 0 && signed_hi >= 0) {
      absolute_lo <- 0
    } else {
      absolute_lo <- min(abs(c(signed_lo, signed_hi)))
    }
    absolute_hi <- max(abs(c(signed_lo, signed_hi)))

    ## Critique fix: a 0.001 tolerance separates genuine reversals from a
    ## zero-versus-nonzero contrast.
    direction_class <- if (abs(means[["net_rd"]]) <= SIGN_TOLERANCE &&
                           abs(means[["total_rd"]]) <= SIGN_TOLERANCE) {
      "joint-null"
    } else if (abs(means[["net_rd"]]) <= SIGN_TOLERANCE ||
               abs(means[["total_rd"]]) <= SIGN_TOLERANCE) {
      "zero-versus-nonzero"
    } else if (sign(means[["net_rd"]]) != sign(means[["total_rd"]])) {
      "genuine-reversal"
    } else {
      "concordant-direction"
    }

    displacement_class <- if (absolute_lo > DISPLACEMENT_THRESHOLD) {
      "material"
    } else if (absolute_hi < DISPLACEMENT_THRESHOLD) {
      "not-material"
    } else {
      "indeterminate"
    }

    data.frame(
      horizon = h,
      total_risk_1 = means[["total_risk_1"]],
      total_risk_0 = means[["total_risk_0"]],
      net_risk_1 = means[["net_risk_1"]],
      net_risk_0 = means[["net_risk_0"]],
      total_rd = means[["total_rd"]],
      net_rd = means[["net_rd"]],
      displacement = means[["displacement"]],
      absolute_displacement = abs(means[["displacement"]]),
      total_rd_mcse = mcse[["total_rd"]],
      net_rd_mcse = mcse[["net_rd"]],
      displacement_mcse = mcse[["displacement"]],
      displacement_ci_low = signed_lo,
      displacement_ci_high = signed_hi,
      absolute_displacement_ci_low = absolute_lo,
      absolute_displacement_ci_high = absolute_hi,
      direction_class = direction_class,
      displacement_class = displacement_class,
      truth_batches = nrow(d),
      truth_n = nrow(d) * TRUTH_BATCH_SIZE,
      truth_mcse_max = max(mcse[c("total_rd", "net_rd", "displacement")]),
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

capture_conditions <- function(expr) {
  warnings <- character()
  error <- NULL
  value <- tryCatch(
    withCallingHandlers(
      force(expr),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )
  list(value = value, warnings = unique(warnings), error = error)
}

collapse_reasons <- function(x) {
  x <- unique(x[!is.na(x) & nzchar(x)])
  if (length(x)) paste(x, collapse = "; ") else NA_character_
}

find_cause_model <- function(csc, cause) {
  models <- csc$models
  if (is.null(models) || !length(models)) stop("CSC did not retain cause models")
  nm <- names(models)
  idx <- integer()
  if (!is.null(nm)) {
    idx <- grep(paste0("(^|[^0-9])", cause, "([^0-9]|$)"), nm)
  }
  if (!length(idx) && length(models) >= cause) idx <- cause
  if (!length(idx)) stop("could not locate cause model ", cause)
  model <- models[[idx[1]]]
  if (inherits(model, "coxph")) return(model)
  for (slot in c("fit", "model", "object")) {
    if (!is.null(model[[slot]]) && inherits(model[[slot]], "coxph"))
      return(model[[slot]])
  }
  stop("retained cause model is not a coxph fit")
}

cox_failure_reasons <- function(fit, label) {
  reasons <- character()
  beta <- try(stats::coef(fit), silent = TRUE)
  if (inherits(beta, "try-error") || any(!is.finite(beta)))
    reasons <- c(reasons, paste0(label, " coefficient failure"))
  V <- try(stats::vcov(fit), silent = TRUE)
  if (inherits(V, "try-error") || any(!is.finite(V))) {
    reasons <- c(reasons, paste0(label, " covariance failure"))
  } else {
    rank <- qr(V)$rank
    if (rank < ncol(V)) reasons <- c(reasons, paste0(label, " singular covariance"))
    condition <- try(kappa(V, exact = TRUE), silent = TRUE)
    if (inherits(condition, "try-error") || !is.finite(condition) ||
        condition > 1e10) {
      reasons <- c(reasons, paste0(label, " information condition number"))
    }
  }
  base <- try(survival::basehaz(fit, centered = FALSE), silent = TRUE)
  if (inherits(base, "try-error") || !nrow(base) ||
      any(!is.finite(base$hazard))) {
    reasons <- c(reasons, paste0(label, " cumulative baseline hazard"))
  }
  reasons
}

prediction_matrix <- function(object, newdata, times, cause = NULL) {
  args <- list(object = object, newdata = newdata, times = times)
  if (!is.null(cause)) args$cause <- cause
  p <- do.call(riskRegression::predictRisk, args)
  p <- as.matrix(p)
  if (nrow(p) == length(times) && ncol(p) == nrow(newdata)) p <- t(p)
  if (nrow(p) != nrow(newdata) || ncol(p) != length(times))
    stop("unexpected predictRisk dimensions")
  storage.mode(p) <- "double"
  p
}

run_ate <- function(object, dat, cause = NULL) {
  args <- list(object, treatment = "A", data = dat, times = HORIZONS,
               se = TRUE, iid = TRUE, band = FALSE)
  if (!is.null(cause)) args$cause <- cause
  do.call(riskRegression::ate, args)
}

## Read the standardized risk difference and its standard error from ate's own
## difference table. This used to scrape every table in the ate object and keep
## the row whose estimate was closest to the target. Another table carries the
## same point estimates with smaller standard errors, so the scraper returned
## those: 0.0067 and 0.0092 at 36 and 60 months where the difference table,
## the bootstrap and the replicate spread all give about 0.009 and 0.014. Every
## interval was 30% too narrow, and the registered bootstrap check caught it.
extract_ate_se <- function(ate_object, target_estimates) {
  d <- as.data.frame(ate_object$diffRisk)
  if (!all(c("time", "A", "B", "estimate", "se") %in% names(d)))
    stop("ate diffRisk table has an unexpected layout")
  if ("estimator" %in% names(d)) d <- d[d$estimator == "GFORMULA", , drop = FALSE]
  d <- d[as.character(d$A) == "0" & as.character(d$B) == "1", , drop = FALSE]
  k <- match(HORIZONS, d$time)
  if (anyNA(k)) stop("ate diffRisk lacks a registered horizon")
  if (max(abs(d$estimate[k] - target_estimates)) > 1e-8)
    stop("ate difference does not match the point estimate")
  d$se[k]
}

extract_iid_payload <- function(x) {
  found <- list()
  walk <- function(z, path = "root", depth = 0L) {
    if (!is.list(z) || depth > 4L) return()
    nm <- names(z)
    if (is.null(nm)) nm <- as.character(seq_along(z))
    for (i in seq_along(z)) {
      child_path <- paste(path, nm[i], sep = "$")
      if (grepl("iid|influence", nm[i], ignore.case = TRUE)) {
        found[[child_path]] <<- z[[i]]
      } else {
        walk(z[[i]], child_path, depth + 1L)
      }
    }
  }
  walk(x)
  found
}

iid_has_subject_axis <- function(x, n) {
  if (is.numeric(x)) {
    d <- dim(x)
    return((is.null(d) && length(x) == n) || (!is.null(d) && any(d == n)))
  }
  if (is.list(x)) return(any(vapply(x, iid_has_subject_axis, logical(1), n = n)))
  FALSE
}

iid_all_finite <- function(x) {
  if (is.numeric(x)) return(all(is.finite(x)))
  if (is.list(x)) return(all(vapply(x, iid_all_finite, logical(1))))
  TRUE
}

blank_estimates <- function(why) {
  data.frame(
    method = rep(METHODS, each = length(HORIZONS)),
    horizon = rep(HORIZONS, times = length(METHODS)),
    est = NA_real_,
    se = NA_real_,
    fail = why,
    warning = NA_character_,
    iid_retained = FALSE,
    stringsAsFactors = FALSE
  )
}

estimate_both <- function(dat, need_se = TRUE, keep_iid = FALSE) {
  out <- blank_estimates("not run")
  ## riskRegression::ate requires a factor treatment, and ate re-reads the CSC
  ## formula looking for a bare Hist(); with prodlim::Hist it stops with "The
  ## left side of the formula must contain Hist() or Surv()". Every replicate
  ## failed on one or the other. prodlim is attached here, not only in the
  ## calling session, so multisession workers find Hist too.
  suppressPackageStartupMessages(library(prodlim))
  dat$A <- factor(dat$A, levels = c(0L, 1L))
  common_warnings <- character()

  if (!any(dat$status == 1L)) {
    out$fail <- "no primary events"
    return(out)
  }

  ## Critique fix: CSC constructs its two internal Cox models using the literal
  ## indicators Surv(time, event = (status == 1)) and
  ## Surv(time, event = (status == 2)). Hist is used here so CSC fits exactly
  ## those two retained cause-specific coxph models in one call.
  fitted <- capture_conditions(
    riskRegression::CSC(
      Hist(time, status) ~ A + Z + M + C + S + Q + A:C,
      data = dat,
      cause = 1
    )
  )
  common_warnings <- c(common_warnings, fitted$warnings)
  if (!is.null(fitted$error)) {
    out$fail <- paste0("CSC fit error: ", fitted$error)
    out$warning <- collapse_reasons(common_warnings)
    return(out)
  }

  csc <- fitted$value
  primary_model <- try(find_cause_model(csc, 1L), silent = TRUE)
  death_model <- try(find_cause_model(csc, 2L), silent = TRUE)
  primary_reasons <- if (inherits(primary_model, "try-error")) {
    "primary model unavailable"
  } else {
    cox_failure_reasons(primary_model, "primary model")
  }
  death_reasons <- if (!any(dat$status == 2L)) {
    "no death events"
  } else if (inherits(death_model, "try-error")) {
    "death model unavailable"
  } else {
    cox_failure_reasons(death_model, "death model")
  }

  d1 <- dat
  d0 <- dat
  d1$A <- factor(1L, levels = c(0L, 1L))
  d0$A <- factor(0L, levels = c(0L, 1L))
  retained <- list()

  net_rows <- out$method == "death_censored_net"
  if (length(primary_reasons)) {
    out$fail[net_rows] <- collapse_reasons(primary_reasons)
  } else {
    net <- capture_conditions({
      p1 <- prediction_matrix(primary_model, d1, HORIZONS)
      p0 <- prediction_matrix(primary_model, d0, HORIZONS)
      if (any(p1 < -1e-10 | p1 > 1 + 1e-10 |
              p0 < -1e-10 | p0 > 1 + 1e-10))
        stop("net risk outside zero to one")
      est <- colMeans(p1 - p0)
      if (need_se) {
        a <- run_ate(primary_model, dat)
        se <- extract_ate_se(a, est)
        iid <- extract_iid_payload(a)
        if (!length(iid) || !iid_has_subject_axis(iid, nrow(dat)))
          stop("net-risk iid contributions unavailable")
        if (!iid_all_finite(iid)) stop("non-finite net-risk iid contribution")
      } else {
        se <- rep(NA_real_, length(HORIZONS))
        iid <- NULL
      }
      if (any(!is.finite(est)) ||
          (need_se && any(!is.finite(se) | se <= 0)))
        stop("non-finite net-risk estimate or SE")
      list(est = est, se = se, iid = iid)
    })
    common_warnings <- c(common_warnings, net$warnings)
    if (!is.null(net$error)) {
      out$fail[net_rows] <- paste0("net-risk error: ", net$error)
    } else {
      out$est[net_rows] <- net$value$est
      out$se[net_rows] <- net$value$se
      out$fail[net_rows] <- NA_character_
      out$iid_retained[net_rows] <- need_se
      if (keep_iid) retained$death_censored_net <- net$value$iid
    }
  }

  total_rows <- out$method == "multistate_total"
  total_model_reasons <- c(primary_reasons, death_reasons)
  if (length(total_model_reasons)) {
    out$fail[total_rows] <- collapse_reasons(total_model_reasons)
  } else {
    total <- capture_conditions({
      py1 <- prediction_matrix(csc, d1, HORIZONS, cause = 1L)
      py0 <- prediction_matrix(csc, d0, HORIZONS, cause = 1L)
      pd1 <- prediction_matrix(csc, d1, HORIZONS, cause = 2L)
      pd0 <- prediction_matrix(csc, d0, HORIZONS, cause = 2L)
      all_predictions <- c(py1, py0, pd1, pd0)
      if (any(!is.finite(all_predictions))) stop("non-finite cumulative incidence")
      if (any(all_predictions < -1e-10 | all_predictions > 1 + 1e-10))
        stop("cumulative incidence outside zero to one")
      if (any(py1 + pd1 > 1 + 1e-10 | py0 + pd0 > 1 + 1e-10))
        stop("cause probabilities sum above one")
      est <- colMeans(py1 - py0)
      if (need_se) {
        a <- run_ate(csc, dat, cause = 1L)
        se <- extract_ate_se(a, est)
        iid <- extract_iid_payload(a)
        if (!length(iid) || !iid_has_subject_axis(iid, nrow(dat)))
          stop("multistate iid contributions unavailable")
        if (!iid_all_finite(iid)) stop("non-finite multistate iid contribution")
      } else {
        se <- rep(NA_real_, length(HORIZONS))
        iid <- NULL
      }
      if (any(!is.finite(est)) ||
          (need_se && any(!is.finite(se) | se <= 0)))
        stop("non-finite multistate estimate or SE")
      list(est = est, se = se, iid = iid)
    })
    common_warnings <- c(common_warnings, total$warnings)
    if (!is.null(total$error)) {
      out$fail[total_rows] <- paste0("multistate error: ", total$error)
    } else {
      out$est[total_rows] <- total$value$est
      out$se[total_rows] <- total$value$se
      out$fail[total_rows] <- NA_character_
      out$iid_retained[total_rows] <- need_se
      if (keep_iid) retained$multistate_total <- total$value$iid
    }
  }

  out$warning <- collapse_reasons(common_warnings)
  if (keep_iid) attr(out, "iid") <- retained
  out
}
