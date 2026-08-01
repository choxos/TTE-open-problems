## Study 2 (BEN-02): performance, paired bootstrap and decision rule.
##
##   Rscript R/05-analyze.R

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_paths <- file.path(
  OUT, "raw", sprintf("scenario-%03d.rds", seq_len(nrow(build_scenarios())))
)
if (!all(file.exists(raw_paths))) {
  stop("all 16 structural scenario files are required for analysis")
}
res <- do.call(rbind, lapply(raw_paths, readRDS))
scenarios <- build_scenarios()

needed_meta <- c("family", "baseline_risk", "mismatch")
if (!all(needed_meta %in% names(res))) {
  res <- merge(res, scenarios, by = "scenario", all.x = TRUE)
}

truth <- readRDS(file.path(OUT, "truth.rds"))
truth_core <- truth[, c(
  "scenario", "psi_t_true", "psi_e_true", "delta_raw_true",
  "psi_e_to_t_lz_true", "delta_observed_align_true",
  "delta_latent_align_true", "summation_error", "truth_check"
)]
res <- merge(res, truth_core, by = "scenario", all.x = TRUE)
res$precision <- factor(res$precision, levels = PRECISION$precision, ordered = TRUE)
res <- res[order(res$scenario, res$replicate, res$precision), ]
rownames(res) <- NULL

rep_counts <- stats::aggregate(
  replicate ~ scenario + precision, res,
  function(x) length(unique(x))
)
if (any(rep_counts$replicate != N_REP)) {
  stop("each structural scenario and precision level must contain N_REP families")
}

metric <- function(x, name) unname(x[[name]])
event_summary <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) return(c(est = NA_real_, mcse = NA_real_, n = 0))
  out <- perf_bias(x, 0)
  c(est = metric(out, "est"), mcse = metric(out, "mcse"), n = length(x))
}

## Estimator performance uses the shared ADEMP functions. Failures remain in
## each attempted denominator through perf_convergence.
ESTIMANDS <- data.frame(
  estimand = c(
    "psiT", "psiE", "deltaRaw", "psiEtoT_LZ", "deltaObservedAlign"
  ),
  estimate = c(
    "psi_t", "psi_e", "delta_raw", "psi_transport",
    "delta_observed_align"
  ),
  model_se = c(
    "se_t", "se_e", "se_delta_raw", "se_transport",
    "se_delta_observed_align"
  ),
  truth = c(
    "psi_t_true", "psi_e_true", "delta_raw_true",
    "psi_e_to_t_lz_true", "delta_observed_align_true"
  ),
  stringsAsFactors = FALSE
)

groups <- split(res, interaction(res$scenario, res$precision, drop = TRUE))
perf_rows <- list()
k <- 0L
for (d in groups) {
  for (j in seq_len(nrow(ESTIMANDS))) {
    est <- d[[ESTIMANDS$estimate[[j]]]]
    se <- d[[ESTIMANDS$model_se[[j]]]]
    tv <- d[[ESTIMANDS$truth[[j]]]][[1]]
    lo <- est - Z95 * se
    hi <- est + Z95 * se
    b <- perf_bias(est, tv)
    es <- perf_empse(est)
    ms <- perf_modse(se)
    re <- perf_relerror_modse(est, se)
    mse <- perf_mse(est, tv)
    cv <- perf_coverage(lo, hi, tv)
    cg <- perf_convergence(est, nrow(d))
    k <- k + 1L
    perf_rows[[k]] <- data.frame(
      scenario = d$scenario[[1]],
      family = d$family[[1]],
      baseline_risk = d$baseline_risk[[1]],
      mismatch = d$mismatch[[1]],
      precision = as.character(d$precision[[1]]),
      n_trial = d$n_trial[[1]],
      n_emulation = d$n_emulation[[1]],
      estimand = ESTIMANDS$estimand[[j]],
      truth = tv,
      bias = metric(b, "est"), bias_mcse = metric(b, "mcse"),
      relative_bias = if (abs(tv) > 1e-12) metric(b, "est") / tv else NA_real_,
      empse = metric(es, "est"), empse_mcse = metric(es, "mcse"),
      modse = metric(ms, "est"), modse_mcse = metric(ms, "mcse"),
      relerror_modse = metric(re, "est"),
      relerror_modse_mcse = metric(re, "mcse"),
      mse = metric(mse, "est"), mse_mcse = metric(mse, "mcse"),
      coverage = metric(cv, "est"), coverage_mcse = metric(cv, "mcse"),
      convergence = metric(cg, "est"),
      n_used = sum(is.finite(est)), n_attempted = nrow(d),
      stringsAsFactors = FALSE
    )
  }
}
performance <- do.call(rbind, perf_rows)
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, "performance.csv"), row.names = FALSE)

failure_data <- data.frame(
  scenario = res$scenario,
  family = res$family,
  baseline_risk = res$baseline_risk,
  mismatch = res$mismatch,
  precision = as.character(res$precision),
  failed = as.numeric(!is.na(res$fail) & nzchar(res$fail)),
  stringsAsFactors = FALSE
)
failure_summary <- stats::aggregate(
  failed ~ scenario + family + baseline_risk + mismatch + precision,
  failure_data, mean
)
names(failure_summary)[names(failure_summary) == "failed"] <- "failure_rate"
utils::write.csv(
  failure_summary, file.path(OUT, "nonconvergence.csv"), row.names = FALSE
)
structural_failure <- stats::aggregate(
  failure_rate ~ scenario + family + baseline_risk + mismatch,
  failure_summary, max
)

## Marginal agreement probabilities describe each illustrative operator on its
## own terms. Critique implementation fix: neither operator is scored against
## the unrelated absolute-tolerance truth.
agreement_rows <- list()
k <- 0L
for (d in groups) {
  for (operator in c("direction", "overlap")) {
    column <- paste0(operator, "_agree")
    p <- event_summary(d[[column]])
    k <- k + 1L
    agreement_rows[[k]] <- data.frame(
      scenario = d$scenario[[1]], family = d$family[[1]],
      baseline_risk = d$baseline_risk[[1]], mismatch = d$mismatch[[1]],
      precision = as.character(d$precision[[1]]),
      n_trial = d$n_trial[[1]], n_emulation = d$n_emulation[[1]],
      operator = operator,
      agreement_probability = p[["est"]],
      agreement_mcse = p[["mcse"]],
      n_used = p[["n"]], n_attempted = nrow(d),
      stringsAsFactors = FALSE
    )
  }
}
agreement <- do.call(rbind, agreement_rows)
utils::write.csv(
  agreement, file.path(OUT, "agreement-probabilities.csv"), row.names = FALSE
)

label_matrix <- function(d) {
  ids <- sort(unique(d$replicate))
  out <- matrix(NA_integer_, nrow = length(ids), ncol = 6L)
  colnames(out) <- c(
    paste0("direction_", PRECISION$precision),
    paste0("overlap_", PRECISION$precision)
  )
  for (j in seq_len(nrow(PRECISION))) {
    z <- d[as.character(d$precision) == PRECISION$precision[[j]], ]
    ii <- match(z$replicate, ids)
    out[ii, j] <- z$direction_agree
    out[ii, 3L + j] <- z$overlap_agree
  }
  out
}

## A complete three-precision label vector has 64 possible patterns. Resampling
## its multinomial pattern count is exactly the stratified paired bootstrap and
## avoids materializing 3.2 billion sampled replicate indices.
set.seed(BOOT_SEED)
BIT_PATTERNS <- sapply(0:5, function(bit) {
  as.integer(bitwAnd(0:63, bitwShiftL(1L, bit)) != 0L)
})
COMPARISONS <- list(c(1L, 2L), c(2L, 3L), c(1L, 3L))
N_CHANGES <- nrow(scenarios) * 2L * length(COMPARISONS)
boot_signed <- matrix(NA_real_, nrow = N_BOOT, ncol = N_CHANGES)
boot_flip <- matrix(NA_real_, nrow = N_BOOT, ncol = N_CHANGES)
point_signed <- point_flip <- numeric(N_CHANGES)
change_meta <- vector("list", N_CHANGES)
range_rows <- list()
paired_probability_rows <- list()
boot_v_direction <- numeric(N_BOOT)
boot_v_overlap <- numeric(N_BOOT)
point_v_direction <- 0
point_v_overlap <- 0
change_index <- 0L
range_index <- 0L
probability_index <- 0L

for (s in scenarios$scenario) {
  d <- res[res$scenario == s, ]
  labels <- label_matrix(d)
  labels <- labels[stats::complete.cases(labels), , drop = FALSE]
  if (!nrow(labels)) stop("a structural scenario has no complete label vectors")

  code <- as.integer(rowSums(sweep(labels, 2L, 2^(0:5), `*`)))
  frequencies <- tabulate(code + 1L, nbins = 64L)
  draws <- stats::rmultinom(
    N_BOOT, size = nrow(labels), prob = frequencies / sum(frequencies)
  )
  p_boot <- (t(BIT_PATTERNS) %*% draws) / nrow(labels)
  p_point <- colMeans(labels)

  range_direction <- max(p_point[1:3]) - min(p_point[1:3])
  range_overlap <- max(p_point[4:6]) - min(p_point[4:6])
  point_v_direction <- point_v_direction + range_direction / nrow(scenarios)
  point_v_overlap <- point_v_overlap + range_overlap / nrow(scenarios)
  boot_v_direction <- boot_v_direction +
    (pmax(p_boot[1, ], p_boot[2, ], p_boot[3, ]) -
       pmin(p_boot[1, ], p_boot[2, ], p_boot[3, ])) / nrow(scenarios)
  boot_v_overlap <- boot_v_overlap +
    (pmax(p_boot[4, ], p_boot[5, ], p_boot[6, ]) -
       pmin(p_boot[4, ], p_boot[5, ], p_boot[6, ])) / nrow(scenarios)

  meta <- scenarios[scenarios$scenario == s, , drop = FALSE]
  for (operator in c("direction", "overlap")) {
    offset <- if (operator == "direction") 0L else 3L
    range_index <- range_index + 1L
    range_rows[[range_index]] <- data.frame(
      meta,
      operator = operator,
      probability_range = if (operator == "direction") range_direction else range_overlap,
      n_complete_vectors = nrow(labels),
      stringsAsFactors = FALSE
    )
    for (j in seq_len(nrow(PRECISION))) {
      probability_index <- probability_index + 1L
      paired_probability_rows[[probability_index]] <- data.frame(
        meta,
        operator = operator,
        precision = PRECISION$precision[[j]],
        agreement_probability = p_point[[offset + j]],
        n_complete_vectors = nrow(labels),
        stringsAsFactors = FALSE
      )
    }

    for (pair in COMPARISONS) {
      from <- offset + pair[[1]]
      to <- offset + pair[[2]]
      change_index <- change_index + 1L
      signed_boot <- p_boot[to, ] - p_boot[from, ]
      flip_pattern <- as.numeric(BIT_PATTERNS[, to] != BIT_PATTERNS[, from])
      flip_boot <- drop(crossprod(flip_pattern, draws)) / nrow(labels)
      boot_signed[, change_index] <- signed_boot
      boot_flip[, change_index] <- flip_boot
      point_signed[[change_index]] <- p_point[[to]] - p_point[[from]]
      point_flip[[change_index]] <- mean(labels[, to] != labels[, from])
      change_meta[[change_index]] <- data.frame(
        meta,
        operator = operator,
        from_precision = PRECISION$precision[[pair[[1]]]],
        to_precision = PRECISION$precision[[pair[[2]]]],
        n_complete_vectors = nrow(labels),
        stringsAsFactors = FALSE
      )
    }
  }
}

ranges <- do.call(rbind, range_rows)
paired_probabilities <- do.call(rbind, paired_probability_rows)
utils::write.csv(
  ranges, file.path(OUT, "precision-ranges.csv"), row.names = FALSE
)
utils::write.csv(
  paired_probabilities,
  file.path(OUT, "paired-agreement-probabilities.csv"),
  row.names = FALSE
)

## Secondary paired contrasts use one bootstrap max statistic for each family.
critical_signed <- stats::quantile(
  apply(abs(sweep(boot_signed, 2L, point_signed, `-`)), 1L, max),
  0.95, names = FALSE, type = 8
)
critical_flip <- stats::quantile(
  apply(abs(sweep(boot_flip, 2L, point_flip, `-`)), 1L, max),
  0.95, names = FALSE, type = 8
)
changes <- do.call(rbind, change_meta)
changes$signed_change <- point_signed
changes$signed_simultaneous_lower <- pmax(-1, point_signed - critical_signed)
changes$signed_simultaneous_upper <- pmin(1, point_signed + critical_signed)
changes$flip_probability <- point_flip
changes$flip_simultaneous_lower <- pmax(0, point_flip - critical_flip)
changes$flip_simultaneous_upper <- pmin(1, point_flip + critical_flip)
utils::write.csv(changes, file.path(OUT, "label-changes.csv"), row.names = FALSE)

## Critique implementation fix: both substantive branches use the same scalar
## S and opposite endpoints of one paired-bootstrap interval.
s_boot <- pmax(boot_v_direction, boot_v_overlap)
s_point <- max(point_v_direction, point_v_overlap)
s_interval <- stats::quantile(
  s_boot, c(0.025, 0.975), names = FALSE, type = 8
)

truth_ok <- all(truth$truth_check) && max(truth$summation_error) < 1e-12
source_check_path <- file.path(OUT, "sceptical-source-checks.csv")
source_ok <- FALSE
if (file.exists(source_check_path)) {
  source_checks <- utils::read.csv(source_check_path, stringsAsFactors = FALSE)
  source_ok <- nrow(source_checks) > 0L && all(source_checks$passed)
}
nonconvergence_ok <- all(structural_failure$failure_rate <= 0.01)

branch <- if (!truth_ok || !source_ok || !nonconvergence_ok) {
  "METHODOLOGICALLY UNINFORMATIVE"
} else if (s_interval[[1]] > PRIMARY_S_THRESHOLD) {
  "PROBLEM IS REAL FOR THE PAIR-LEVEL PRECISION-CONFLATION COMPONENT"
} else if (s_interval[[2]] < PRIMARY_S_THRESHOLD) {
  "PROBLEM IS NOT REAL FOR THE PAIR-LEVEL PRECISION-CONFLATION COMPONENT"
} else {
  "INCONCLUSIVE"
}

primary <- data.frame(
  v_direction = point_v_direction,
  v_overlap = point_v_overlap,
  s = s_point,
  mc_interval_lower = s_interval[[1]],
  mc_interval_upper = s_interval[[2]],
  threshold = PRIMARY_S_THRESHOLD,
  bootstrap_resamples = N_BOOT,
  truth_checks_passed = truth_ok,
  sceptical_source_checks_passed = source_ok,
  all_structural_nonconvergence_at_most_1_percent = nonconvergence_ok,
  decision_branch = branch,
  stringsAsFactors = FALSE
)
utils::write.csv(
  primary, file.path(OUT, "primary-statistic.csv"), row.names = FALSE
)

sensitivity_base <- list(data.frame(
  weighting = "all_structural_scenarios",
  mismatch = "all",
  v_direction = point_v_direction,
  v_overlap = point_v_overlap,
  s = s_point,
  stringsAsFactors = FALSE
))
for (mismatch in MISMATCHES) {
  z <- ranges[ranges$mismatch == mismatch, ]
  vd <- mean(z$probability_range[z$operator == "direction"])
  vo <- mean(z$probability_range[z$operator == "overlap"])
  sensitivity_base[[length(sensitivity_base) + 1L]] <- data.frame(
    weighting = "equal_within_mismatch",
    mismatch = mismatch,
    v_direction = vd,
    v_overlap = vo,
    s = max(vd, vo),
    stringsAsFactors = FALSE
  )
}
sensitivity_base <- do.call(rbind, sensitivity_base)
sensitivity <- do.call(rbind, lapply(SENSITIVITY_THRESHOLDS, function(threshold) {
  transform(
    sensitivity_base,
    materiality_threshold = threshold,
    s_at_or_above_threshold = s >= threshold
  )
}))
utils::write.csv(
  sensitivity, file.path(OUT, "precision-sensitivity.csv"), row.names = FALSE
)

## Tolerance procedures alone are scored against tolerance truth. The forced
## classifier and abstaining procedures share the same truth and common loss.
decision_rates <- function(decision, truth_class) {
  valid <- !is.na(decision)
  n <- sum(valid)
  if (!n) {
    return(c(
      wrong = NA_real_, wrong_mcse = NA_real_,
      correct = NA_real_, correct_mcse = NA_real_,
      indeterminate = NA_real_, indeterminate_mcse = NA_real_,
      decision_rate = NA_real_, decision_rate_mcse = NA_real_,
      convergence = 0, n_used = 0
    ))
  }
  dec <- decision[valid]
  indeterminate <- dec == "indeterminate"
  definitive <- !indeterminate
  if (truth_class == "boundary") {
    wrong <- correct <- rep(NA_real_, n)
  } else {
    wrong <- definitive & dec != truth_class
    correct <- definitive & dec == truth_class
  }
  rw <- event_summary(wrong)
  rc <- event_summary(correct)
  ri <- event_summary(indeterminate)
  rd <- event_summary(definitive)
  cg <- perf_convergence(ifelse(valid, 0, NA_real_), length(valid))
  c(
    wrong = rw[["est"]], wrong_mcse = rw[["mcse"]],
    correct = rc[["est"]], correct_mcse = rc[["mcse"]],
    indeterminate = ri[["est"]], indeterminate_mcse = ri[["mcse"]],
    decision_rate = rd[["est"]], decision_rate_mcse = rd[["mcse"]],
    convergence = metric(cg, "est"), n_used = n
  )
}

make_tolerance_row <- function(d, delta, method, decision,
                               cutoff = NA_real_, g_mean = NA_real_) {
  truth_value <- d$delta_raw_true[[1]]
  boundary <- abs(abs(truth_value) - delta) < 1e-12
  truth_class <- if (boundary) {
    "boundary"
  } else if (abs(truth_value) < delta) {
    "aligned"
  } else {
    "mismatched"
  }
  rates <- decision_rates(decision, truth_class)
  data.frame(
    scenario = d$scenario[[1]], family = d$family[[1]],
    baseline_risk = d$baseline_risk[[1]], mismatch = d$mismatch[[1]],
    precision = as.character(d$precision[[1]]),
    n_trial = d$n_trial[[1]], n_emulation = d$n_emulation[[1]],
    delta = delta, delta_raw_true = truth_value,
    truth_class = truth_class, method = method, cutoff = cutoff,
    wrong_definitive = rates[["wrong"]],
    wrong_definitive_mcse = rates[["wrong_mcse"]],
    correct_definitive = rates[["correct"]],
    correct_definitive_mcse = rates[["correct_mcse"]],
    indeterminate = rates[["indeterminate"]],
    indeterminate_mcse = rates[["indeterminate_mcse"]],
    decision_rate = rates[["decision_rate"]],
    decision_rate_mcse = rates[["decision_rate_mcse"]],
    convergence = rates[["convergence"]],
    n_used = rates[["n_used"]], compatibility_mean = g_mean,
    stringsAsFactors = FALSE
  )
}

tolerance_rows <- list()
k <- 0L
for (d in groups) {
  estimate <- d$delta_raw
  se <- d$se_delta_raw
  for (delta in DELTA_GRID) {
    forced <- ifelse(
      is.finite(estimate),
      ifelse(abs(estimate) < delta, "aligned", "mismatched"),
      NA_character_
    )
    k <- k + 1L
    tolerance_rows[[k]] <- make_tolerance_row(
      d, delta, "forced-plugin", forced
    )

    lo90 <- estimate - Z90 * se
    hi90 <- estimate + Z90 * se
    joint <- ifelse(
      !is.finite(lo90) | !is.finite(hi90),
      NA_character_,
      ifelse(
        lo90 >= -delta & hi90 <= delta,
        "aligned",
        ifelse(lo90 > delta | hi90 < -delta,
               "mismatched", "indeterminate")
      )
    )
    k <- k + 1L
    tolerance_rows[[k]] <- make_tolerance_row(
      d, delta, "joint-uncertainty", joint
    )

    compatibility <- stats::pnorm((delta - estimate) / se) -
      stats::pnorm((-delta - estimate) / se)
    compatibility[!is.finite(estimate) | !is.finite(se) | se <= 0] <- NA_real_
    for (cutoff in COMPATIBILITY_CUTOFFS) {
      compatibility_decision <- ifelse(
        !is.finite(compatibility),
        NA_character_,
        ifelse(
          compatibility >= cutoff,
          "aligned",
          ifelse(compatibility <= 1 - cutoff,
                 "mismatched", "indeterminate")
        )
      )
      k <- k + 1L
      tolerance_rows[[k]] <- make_tolerance_row(
        d, delta, "compatibility", compatibility_decision,
        cutoff = cutoff, g_mean = mean(compatibility, na.rm = TRUE)
      )
    }
  }
}
tolerance_performance <- do.call(rbind, tolerance_rows)
utils::write.csv(
  tolerance_performance,
  file.path(OUT, "tolerance-performance.csv"),
  row.names = FALSE
)

loss_source <- tolerance_performance[
  tolerance_performance$truth_class != "boundary" &
    is.finite(tolerance_performance$wrong_definitive),
]
tolerance_loss <- do.call(rbind, lapply(LOSS_LAMBDAS, function(lambda) {
  z <- loss_source
  z$lambda <- lambda
  z$risk <- z$wrong_definitive + lambda * z$indeterminate
  second_moment <- z$wrong_definitive + lambda^2 * z$indeterminate
  z$risk_mcse <- sqrt(pmax(
    0,
    (second_moment - z$risk^2) / pmax(1, z$n_used)
  ))
  z
}))
utils::write.csv(
  tolerance_loss, file.path(OUT, "tolerance-loss.csv"), row.names = FALSE
)

compatibility_curves <- tolerance_performance[
  tolerance_performance$method == "compatibility" &
    tolerance_performance$truth_class != "boundary",
]
compatibility_curves <- stats::aggregate(
  cbind(wrong_definitive, decision_rate, indeterminate) ~
    precision + delta + cutoff,
  compatibility_curves, mean
)
utils::write.csv(
  compatibility_curves,
  file.path(OUT, "compatibility-curves.csv"),
  row.names = FALSE
)

## The sceptical p-value is summarized under its published interpretation. It is
## not reinterpreted as an absolute-risk tolerance classifier.
sceptical_rows <- list()
k <- 0L
for (d in groups) {
  p <- d$sceptical_p
  valid_p <- p[is.finite(p)]
  success <- event_summary(d$sceptical_success)
  finite_ci <- is.finite(d$sceptical_ci_lower) & is.finite(d$sceptical_ci_upper)
  finite_rate <- event_summary(finite_ci)
  zero_rate <- event_summary(
    finite_ci & d$sceptical_ci_lower <= 0 & d$sceptical_ci_upper >= 0
  )
  cv_t <- perf_coverage(
    d$sceptical_ci_lower, d$sceptical_ci_upper, d$psi_t_true[[1]]
  )
  cv_e <- perf_coverage(
    d$sceptical_ci_lower, d$sceptical_ci_upper, d$psi_e_true[[1]]
  )
  qs <- stats::quantile(
    valid_p, c(0.05, 0.25, 0.50, 0.75, 0.95),
    names = FALSE, type = 8
  )
  k <- k + 1L
  sceptical_rows[[k]] <- data.frame(
    scenario = d$scenario[[1]], family = d$family[[1]],
    baseline_risk = d$baseline_risk[[1]], mismatch = d$mismatch[[1]],
    precision = as.character(d$precision[[1]]),
    p_mean = mean(valid_p), p_q05 = qs[[1]], p_q25 = qs[[2]],
    p_median = qs[[3]], p_q75 = qs[[4]], p_q95 = qs[[5]],
    source_success_probability = success[["est"]],
    source_success_mcse = success[["mcse"]],
    inversion_finite = finite_rate[["est"]],
    interval_contains_zero = zero_rate[["est"]],
    interval_contains_trial_truth = metric(cv_t, "est"),
    interval_contains_emulation_truth = metric(cv_e, "est"),
    mean_interval_width = mean(
      d$sceptical_ci_upper[finite_ci] - d$sceptical_ci_lower[finite_ci]
    ),
    stringsAsFactors = FALSE
  )
}
sceptical_summary <- do.call(rbind, sceptical_rows)
utils::write.csv(
  sceptical_summary, file.path(OUT, "sceptical-summary.csv"), row.names = FALSE
)

## Plug-in normal calculations are implementation benchmarks. Mean reported
## component standard errors supply their precision, while finite simulation
## remains the performance result.
normal_interval_probability <- function(lower, upper, mean, sd) {
  if (!is.finite(sd) || sd <= 0 || lower > upper) return(0)
  stats::pnorm((upper - mean) / sd) - stats::pnorm((lower - mean) / sd)
}

normal_rows <- list()
k <- 0L
for (d in groups) {
  se_t <- mean(d$se_t, na.rm = TRUE)
  se_e <- mean(d$se_e, na.rm = TRUE)
  se_delta <- sqrt(se_t^2 + se_e^2)
  mu_t <- d$psi_t_true[[1]]
  mu_e <- d$psi_e_true[[1]]
  mu_delta <- d$delta_raw_true[[1]]

  p_t_positive <- stats::pnorm(mu_t / se_t)
  p_e_positive <- stats::pnorm(mu_e / se_e)
  direction_probability <- p_t_positive * p_e_positive +
    (1 - p_t_positive) * (1 - p_e_positive)
  overlap_width <- Z95 * (se_t + se_e)
  overlap_probability <- normal_interval_probability(
    -overlap_width, overlap_width, mu_delta, se_delta
  )

  for (delta in DELTA_GRID) {
    boundary <- abs(abs(mu_delta) - delta) < 1e-12
    truth_class <- if (boundary) {
      "boundary"
    } else if (abs(mu_delta) < delta) {
      "aligned"
    } else {
      "mismatched"
    }
    forced_aligned <- normal_interval_probability(
      -delta, delta, mu_delta, se_delta
    )
    joint_aligned <- normal_interval_probability(
      -delta + Z90 * se_delta,
      delta - Z90 * se_delta,
      mu_delta, se_delta
    )
    joint_mismatched <- stats::pnorm(
      (-delta - Z90 * se_delta - mu_delta) / se_delta
    ) + 1 - stats::pnorm(
      (delta + Z90 * se_delta - mu_delta) / se_delta
    )
    joint_indeterminate <- pmax(0, 1 - joint_aligned - joint_mismatched)
    forced_wrong <- if (truth_class == "boundary") {
      NA_real_
    } else if (truth_class == "aligned") {
      1 - forced_aligned
    } else {
      forced_aligned
    }
    joint_wrong <- if (truth_class == "boundary") {
      NA_real_
    } else if (truth_class == "aligned") {
      joint_mismatched
    } else {
      joint_aligned
    }

    k <- k + 1L
    normal_rows[[k]] <- data.frame(
      scenario = d$scenario[[1]], family = d$family[[1]],
      baseline_risk = d$baseline_risk[[1]], mismatch = d$mismatch[[1]],
      precision = as.character(d$precision[[1]]),
      delta = delta, truth_class = truth_class,
      mean_se_trial = se_t, mean_se_emulation = se_e,
      mean_se_delta = se_delta,
      direction_agreement = direction_probability,
      interval_overlap = overlap_probability,
      forced_aligned = forced_aligned,
      forced_wrong = forced_wrong,
      joint_aligned = joint_aligned,
      joint_mismatched = joint_mismatched,
      joint_indeterminate = joint_indeterminate,
      joint_wrong = joint_wrong,
      stringsAsFactors = FALSE
    )
  }
}
normal_theory <- do.call(rbind, normal_rows)
utils::write.csv(
  normal_theory, file.path(OUT, "normal-theory.csv"), row.names = FALSE
)

utils::write.csv(
  truth[, c(
    "scenario", "family", "baseline_risk", "mismatch",
    "psi_t_true", "psi_e_true", "delta_raw_true",
    "psi_e_to_t_lz_true", "delta_observed_align_true",
    "delta_latent_align_true", "summation_error"
  )],
  file.path(OUT, "truth-discrepancies.csv"), row.names = FALSE
)

cat("\n== estimator diagnostics ==\n")
cat(sprintf("  minimum convergence: %.4f\n", min(performance$convergence)))
cat(sprintf(
  "  coverage range: %.3f to %.3f\n",
  min(performance$coverage, na.rm = TRUE),
  max(performance$coverage, na.rm = TRUE)
))
cat(sprintf(
  "  maximum absolute bias: %.6f\n",
  max(abs(performance$bias), na.rm = TRUE)
))
cat(sprintf(
  "  maximum finite-cell summation error: %.3g\n",
  max(truth$summation_error)
))

cat("\n== illustrative operator precision sensitivity ==\n")
cat(sprintf("  Vdirection: %.4f\n", point_v_direction))
cat(sprintf("  Voverlap:   %.4f\n", point_v_overlap))
cat(sprintf("  S:          %.4f\n", s_point))
cat(sprintf(
  "  paired-bootstrap 95%% Monte Carlo interval: [%.4f, %.4f]\n",
  s_interval[[1]], s_interval[[2]]
))
cat(sprintf("  decision threshold: %.2f\n", PRIMARY_S_THRESHOLD))
cat(sprintf(
  "  largest structural nonconvergence rate: %.4f\n",
  max(structural_failure$failure_rate)
))
cat(sprintf("Decision-rule branch: %s\n", branch))
