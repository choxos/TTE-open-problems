## Study LRN-05: performance summaries and scenario-specific decisions.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))
suppressPackageStartupMessages(library(data.table))

OUT <- here('results')
raw_files <- sort(list.files(file.path(OUT, 'raw'), '^scenario-.*[.]rds$',
                             full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- data.table::rbindlist(lapply(raw_files, readRDS), fill = TRUE)
truth_object <- readRDS(file.path(OUT, 'truth.rds'))
truth <- data.table::as.data.table(truth_object$rows)
checks <- data.table::as.data.table(truth_object$checks)
res[, bin_key := fifelse(is.na(bin), 0L, as.integer(bin))]
truth[, bin_key := fifelse(is.na(bin), 0L, as.integer(bin))]
res <- merge(res, truth[, .(scenario, strategy, score, metric, bin_key,
                            truth, score_mean)],
             by = c('scenario', 'strategy', 'score', 'metric', 'bin_key'),
             all.x = TRUE)

get_value <- function(x, name) if (is.list(x) && !is.null(x[[name]]))
  unname(x[[name]]) else NA_real_
safe_perf <- function(expr) tryCatch(expr, error = function(e)
  list(est = NA_real_, mcse = NA_real_))

call_becoverage <- function(est, se, truth) {
  nm <- names(formals(perf_becoverage))
  if (length(nm) {
    >= 3L) perf_becoverage(est, se, truth)
  } else perf_becoverage(est, se)
}

call_rejection <- function(est, se, lo, hi, truth) {
  nm <- names(formals(perf_rejection))
  if (length(nm) && grepl('lo|lower|lcl', nm[1L], ignore.case = TRUE))
    perf_rejection(lo, hi, truth)
  else if (length(nm) >= 3L) perf_rejection(est, se, truth)
  else perf_rejection(est, se)
}

summarize_performance <- function(d) {
  tv <- d$truth[which(is.finite(d$truth))[1L]]
  ok <- is.finite(d$est) & is.finite(d$se) & is.finite(tv)
  est <- d$est[ok]
  se <- d$se[ok]
  lo <- d$lo[ok]
  hi <- d$hi[ok]
  if (!length(est)) {
    conv <- safe_perf(perf_convergence(d$est, nrow(d)))
    return(data.frame(
      truth = tv, bias = NA, bias_mcse = NA, empse = NA, empse_mcse = NA,
      modse = NA, modse_mcse = NA, relerror_modse = NA,
      relerror_modse_mcse = NA, mse = NA, mse_mcse = NA, coverage = NA,
      coverage_mcse = NA, becoverage = NA, becoverage_mcse = NA,
      rejection = NA, rejection_mcse = NA,
      convergence = get_value(conv, 'est'),
      convergence_mcse = get_value(conv, 'mcse'), n_used = 0L,
      n_attempted = nrow(d)))
  }
  b <- safe_perf(perf_bias(est, tv))
  es <- safe_perf(perf_empse(est))
  ms <- safe_perf(perf_modse(se))
  re <- safe_perf(perf_relerror_modse(est, se))
  mse <- safe_perf(perf_mse(est, tv))
  cv <- safe_perf(perf_coverage(lo, hi, tv))
  bec <- safe_perf(call_becoverage(est, se, tv))
  rej <- safe_perf(call_rejection(est, se, lo, hi, tv))
  conv <- safe_perf(perf_convergence(d$est, nrow(d)))
  data.frame(
    truth = tv,
    bias = get_value(b, 'est'), bias_mcse = get_value(b, 'mcse'),
    empse = get_value(es, 'est'), empse_mcse = get_value(es, 'mcse'),
    modse = get_value(ms, 'est'), modse_mcse = get_value(ms, 'mcse'),
    relerror_modse = get_value(re, 'est'),
    relerror_modse_mcse = get_value(re, 'mcse'),
    mse = get_value(mse, 'est'), mse_mcse = get_value(mse, 'mcse'),
    coverage = get_value(cv, 'est'), coverage_mcse = get_value(cv, 'mcse'),
    becoverage = get_value(bec, 'est'),
    becoverage_mcse = get_value(bec, 'mcse'),
    rejection = get_value(rej, 'est'), rejection_mcse = get_value(rej, 'mcse'),
    convergence = get_value(conv, 'est'),
    convergence_mcse = get_value(conv, 'mcse'),
    n_used = length(est), n_attempted = nrow(d))
}

perf <- res[, summarize_performance(.SD),
            by = .(scenario, profile, profile_label, gamma, delta, support, alpha,
                   method, strategy, score, metric, bin_key)]
perf[, bin := fifelse(bin_key == 0L, NA_integer_, bin_key)]
data.table::setorder(perf, scenario, method, strategy, score, metric, bin_key)
utils::write.csv(perf, file.path(OUT, 'performance.csv'), row.names = FALSE)

wilson <- function(success, total, level = 0.95) {
  if (!is.finite(total) || total <= 0) return(c(est = NA, lo = NA, hi = NA))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- success / total
  den <- 1 + z^2 / total
  center <- (p + z^2 / (2 * total)) / den
  half <- z * sqrt(p * (1 - p) / total + z^2 / (4 * total^2)) / den
  c(est = p, lo = max(0, center - half), hi = min(1, center + half))
}

id <- c('scenario', 'rep_id', 'strategy', 'score', 'metric', 'bin_key')
full <- res[method == 'full_history', c(id, 'est', 'se', 'lo', 'hi', 'truth'),
            with = FALSE]
complete <- res[method == 'exact_complete',
                c(id, 'est', 'se', 'lo', 'hi', 'truth'), with = FALSE]
data.table::setnames(full, c('est', 'se', 'lo', 'hi', 'truth'),
                     c('est_full', 'se_full', 'lo_full', 'hi_full', 'truth'))
data.table::setnames(complete, c('est', 'se', 'lo', 'hi', 'truth'),
                     c('est_complete', 'se_complete', 'lo_complete',
                       'hi_complete', 'truth_complete'))
paired <- merge(full, complete, by = id, all = TRUE)
paired[, truth := fifelse(is.finite(truth), truth, truth_complete)]
paired[, difference := est_complete - est_full]
paired[, family := vapply(metric, metric_family, character(1))]

paired_summary <- paired[, {
  z <- difference[is.finite(difference)]
  critical <- if (metric_family(metric[1L]) == 'calibration_curve')
    MC_Z_BINS else MC_Z
  m <- if (length(z)) mean(z) else NA_real_
  s <- if (length(z) > 1L) stats::sd(z) / sqrt(length(z)) else NA_real_
  list(effect = m, effect_mcse = s,
       effect_lo = m - critical * s, effect_hi = m + critical * s,
       absolute_effect_lo = if (is.finite(m) && is.finite(s))
         max(0, abs(m) - critical * s) else NA_real_,
       absolute_effect_hi = if (is.finite(m) && is.finite(s))
         abs(m) + critical * s else NA_real_,
       n_used = length(z), n_attempted = .N)
}, by = .(scenario, strategy, score, metric, bin_key, family)]
paired_summary[, bin := fifelse(bin_key == 0L, NA_integer_, bin_key)]
utils::write.csv(paired_summary, file.path(OUT, 'omission-effects.csv'),
                 row.names = FALSE)

coverage_summary <- function(method_name) {
  res[method == method_name, {
    ok <- is.finite(est) & is.finite(se) & is.finite(truth)
    covered <- ok & lo <= truth & hi >= truth
    ci <- wilson(sum(covered), sum(ok))
    bias <- if (sum(ok)) mean(est[ok] - truth[ok]) else NA_real_
    bias_mcse <- if (sum(ok) > 1L) stats::sd(est[ok] - truth[ok]) /
      sqrt(sum(ok)) else NA_real_
    list(coverage = ci['est'], coverage_lo = ci['lo'], coverage_hi = ci['hi'],
         bias = bias, bias_mcse = bias_mcse,
         success_fraction = sum(ok) / .N, n_success = sum(ok), n_total = .N)
  }, by = .(scenario, strategy, score, metric, bin_key)]
}

cov_complete <- coverage_summary('exact_complete')
cov_full <- coverage_summary('full_history')
data.table::setnames(cov_complete,
                     c('coverage', 'coverage_lo', 'coverage_hi', 'bias',
                       'bias_mcse', 'success_fraction', 'n_success', 'n_total'),
                     paste0('complete_', c('coverage', 'coverage_lo', 'coverage_hi',
                                           'bias', 'bias_mcse', 'success_fraction',
                                           'n_success', 'n_total')))
data.table::setnames(cov_full,
                     c('coverage', 'coverage_lo', 'coverage_hi', 'bias',
                       'bias_mcse', 'success_fraction', 'n_success', 'n_total'),
                     paste0('full_', c('coverage', 'coverage_lo', 'coverage_hi',
                                       'bias', 'bias_mcse', 'success_fraction',
                                       'n_success', 'n_total')))

base <- merge(paired_summary, cov_complete,
              by = c('scenario', 'strategy', 'score', 'metric', 'bin_key'), all.x = TRUE)
base <- merge(base, cov_full,
              by = c('scenario', 'strategy', 'score', 'metric', 'bin_key'), all.x = TRUE)
base <- merge(base, unique(checks[, .(scenario, quadrature_converged,
                                      verification_ok)]), by = 'scenario', all.x = TRUE)
base <- merge(base, unique(as.data.table(build_scenarios())), by = 'scenario', all.x = TRUE)

requirement_file <- file.path(OUT, 'replication-requirements.csv')
if (file.exists(requirement_file)) {
  req <- fread(requirement_file)
  base <- merge(base, req[, .(scenario, strategy, score, metric, bin_key,
                              required_uncapped, protocol_cap_exceeded)],
                by = c('scenario', 'strategy', 'score', 'metric', 'bin_key'),
                all.x = TRUE)
} else {
  base[, `:=`(required_uncapped = N_REP_MIN,
              protocol_cap_exceeded = FALSE)]
}
base[is.na(required_uncapped), required_uncapped := N_REP_MIN]
base[, budget_precision_shortfall :=
       required_uncapped > N_REP_BUDGET_CAP]
base[, negligible_limit := vapply(family, decision_limit, numeric(1),
                                   column = 'negligible')]
base[, consequential_limit := vapply(family, decision_limit, numeric(1),
                                      column = 'consequential')]
base[, critical := fifelse(family == 'calibration_curve', MC_Z_BINS, MC_Z)]
base[, full_bias_abs_hi := abs(full_bias) + critical * full_bias_mcse]
base[, oracle_gate := quadrature_converged & verification_ok &
       full_success_fraction >= 0.95 &
       full_bias_abs_hi < negligible_limit &
       full_coverage_lo <= 0.95 & full_coverage_hi >= 0.95]

## Critique implementation: the following code never turns constructed
## confounding into a global verdict. It applies the reviewed numerical bounds
## separately to each scenario, strategy, score, and metric family.
classify_scalar <- function(r) {
  if (!isTRUE(r$quadrature_converged) || !isTRUE(r$verification_ok))
    return(c(classification = 'uninformative', reason = 'truth-check-failed'))
  if (!isTRUE(r$oracle_gate))
    return(c(classification = 'uninformative', reason = 'positive-control-failed'))
  if (!is.finite(r$complete_success_fraction) || r$complete_success_fraction < 0.95)
    return(c(classification = 'uninformative', reason = 'fewer-than-95-percent-successful'))
  if (isTRUE(r$protocol_cap_exceeded) || !is.finite(r$required_uncapped) ||
      r$required_uncapped > N_REP_PROTOCOL_CAP)
    return(c(classification = 'uninformative', reason = 'protocol-cap-exceeded'))
  if (isTRUE(r$budget_precision_shortfall))
    return(c(classification = 'uninformative', reason = 'budget-precision-shortfall'))
  if (is.finite(r$absolute_effect_lo) &&
      r$absolute_effect_lo > r$consequential_limit &&
      is.finite(r$complete_coverage_hi) && r$complete_coverage_hi <= 0.90)
    return(c(classification = 'consequential', reason = 'both-consequential-bounds-cleared'))
  if (is.finite(r$absolute_effect_hi) &&
      r$absolute_effect_hi < r$negligible_limit &&
      is.finite(r$complete_coverage_lo) && r$complete_coverage_lo >= 0.93 &&
      r$complete_coverage_hi <= 0.97)
    return(c(classification = 'negligible', reason = 'all-negligible-bounds-cleared'))
  c(classification = 'uninformative', reason = 'indifference-region')
}

scalar <- base[family %in% c('cal_intercept', 'brier', 'auc') &
                 strategy %in% STRATEGIES]
scalar_decisions <- lapply(seq_len(nrow(scalar)), function(i) {
  z <- classify_scalar(scalar[i])
  data.frame(scalar[i], classification = z['classification'], reason = z['reason'])
})
scalar_decisions <- rbindlist(scalar_decisions, fill = TRUE)

bins <- base[family == 'calibration_curve' & strategy %in% STRATEGIES]
bin_groups <- split(bins, interaction(bins$scenario, bins$strategy, bins$score,
                                      drop = TRUE))
bin_decisions <- rbindlist(lapply(bin_groups, function(d) {
  invalid_reason <- NULL
  if (!all(d$quadrature_converged & d$verification_ok))
    invalid_reason <- 'truth-check-failed'
  else if (!all(d$oracle_gate)) invalid_reason <- 'positive-control-failed'
  else if (any(d$complete_success_fraction < 0.95))
    invalid_reason <- 'fewer-than-95-percent-successful'
  else if (any(d$protocol_cap_exceeded | !is.finite(d$required_uncapped) |
               d$required_uncapped > N_REP_PROTOCOL_CAP))
    invalid_reason <- 'protocol-cap-exceeded'
  else if (any(d$budget_precision_shortfall))
    invalid_reason <- 'budget-precision-shortfall'

  consequential <- which(d$absolute_effect_lo > 0.02 &
                           d$complete_coverage_hi <= 0.90)
  negligible <- all(d$absolute_effect_hi < 0.01 &
                      d$complete_coverage_lo >= 0.93 &
                      d$complete_coverage_hi <= 0.97)
  if (!is.null(invalid_reason)) {
    classification <- 'uninformative'
    reason <- invalid_reason
  } else if (length(consequential)) {
    classification <- 'consequential'
    reason <- 'at-least-one-bin-cleared-simultaneous-bounds'
  } else if (negligible) {
    classification <- 'negligible'
    reason <- 'all-ten-bins-cleared-negligible-bounds'
  } else {
    classification <- 'uninformative'
    reason <- 'indifference-region'
  }
  data.frame(
    scenario = d$scenario[1L], strategy = d$strategy[1L], score = d$score[1L],
    family = 'calibration_curve', metric = 'calibration_curve',
    maximum_absolute_effect = max(abs(d$effect), na.rm = TRUE),
    maximum_absolute_effect_hi = max(d$absolute_effect_hi, na.rm = TRUE),
    trigger_bin = if (length(consequential)) d$bin[consequential[1L]] else NA_integer_,
    classification = classification, reason = reason,
    profile = d$profile[1L], profile_label = d$profile_label[1L],
    gamma = d$gamma[1L], delta = d$delta[1L], support = d$support[1L],
    alpha = d$alpha[1L], joint_confounding = d$joint_confounding[1L],
    stringsAsFactors = FALSE)
}), fill = TRUE)

scalar_out <- scalar_decisions[, .(
  scenario, strategy, score, family, metric,
  maximum_absolute_effect = abs(effect),
  maximum_absolute_effect_hi = absolute_effect_hi,
  trigger_bin = NA_integer_, classification, reason,
  profile, profile_label, gamma, delta, support, alpha, joint_confounding
)]
decisions <- rbindlist(list(scalar_out, bin_decisions), fill = TRUE)

## A consequential result in a gamma-zero or delta-zero family is a failed
## control check. It makes the matching family uninformative rather than becoming
## evidence for omitted-U distortion.
control_failure <- decisions[(abs(gamma) < 1e-14 | abs(delta) < 1e-14) &
                               classification == 'consequential',
                             unique(paste(strategy, score, family, sep = '|'))]
if (length(control_failure)) {
  key <- paste(decisions$strategy, decisions$score, decisions$family, sep = '|')
  take <- key %in% control_failure
  decisions$classification[take] <- 'uninformative'
  decisions$reason[take] <- 'familywise-control-profile-check-failed'
}
data.table::setorder(decisions, scenario, strategy, score, family)
utils::write.csv(decisions, file.path(OUT, 'decisions.csv'), row.names = FALSE)

## Method decomposition retains the four prespecified comparisons.
method_pairs <- list(
  omitted_u = c('exact_complete', 'full_history'),
  omitted_measured_history = c('exact_reduced', 'exact_complete'),
  fitted_estimation_and_sieve = c('fitted_reduced', 'exact_reduced'),
  adherer_selection = c('unweighted', 'full_history')
)
decomposition <- rbindlist(lapply(names(method_pairs), function(label) {
  pair <- method_pairs[[label]]
  x <- res[method == pair[1L], .(scenario, rep_id, strategy, score, metric,
                                  bin_key, first = est)]
  y <- res[method == pair[2L], .(scenario, rep_id, strategy, score, metric,
                                  bin_key, second = est)]
  z <- merge(x, y, by = id, all = TRUE)
  z[, difference := first - second]
  z[, .(effect = mean(difference, na.rm = TRUE),
        effect_mcse = stats::sd(difference, na.rm = TRUE) /
          sqrt(sum(is.finite(difference))),
        n_used = sum(is.finite(difference)), n_attempted = .N,
        comparison = label),
    by = .(scenario, strategy, score, metric, bin_key)]
}))
utils::write.csv(decomposition, file.path(OUT, 'method-decomposition.csv'),
                 row.names = FALSE)

mis <- paired[score == 'miscalibrated' &
                metric %in% c('cal_intercept', 'cal_slope') &
                strategy %in% STRATEGIES]
wide <- dcast(mis, scenario + rep_id + strategy ~ metric,
              value.var = c('est_full', 'est_complete'))
wide[, intercept_false_reassurance :=
       abs(est_complete_cal_intercept) <= abs(est_full_cal_intercept) - 0.10 &
       abs(est_complete_cal_intercept - 0.35 / 0.75) >
       abs(est_full_cal_intercept - 0.35 / 0.75)]
wide[, slope_false_reassurance :=
       abs(est_complete_cal_slope - 1) <= abs(est_full_cal_slope - 1) - 0.10 &
       abs(est_complete_cal_slope - 1 / 0.75) >
       abs(est_full_cal_slope - 1 / 0.75)]
false_reassurance <- wide[, {
  summarize_flag <- function(x) {
    ok <- !is.na(x)
    wilson(sum(x[ok]), sum(ok))
  }
  a <- summarize_flag(intercept_false_reassurance)
  b <- summarize_flag(slope_false_reassurance)
  c <- summarize_flag(intercept_false_reassurance | slope_false_reassurance)
  list(intercept_frequency = a['est'], intercept_lo = a['lo'], intercept_hi = a['hi'],
       slope_frequency = b['est'], slope_lo = b['lo'], slope_hi = b['hi'],
       either_frequency = c['est'], either_lo = c['lo'], either_hi = c['hi'])
}, by = .(scenario, strategy)]
utils::write.csv(false_reassurance, file.path(OUT, 'false-reassurance.csv'),
                 row.names = FALSE)

diag <- unique(res[strategy %in% STRATEGIES,
                   .(scenario, rep_id, method, strategy, diagnostic_flag,
                     max_weight_norm, p99_weight, ess, ess_fraction,
                     probability_below_005, n_adherent, n_events_adherent)])
diag_summary <- diag[, {
  ok <- !is.na(diagnostic_flag)
  ci <- wilson(sum(diagnostic_flag[ok] == 1L), sum(ok))
  list(flag_probability = ci['est'], flag_lo = ci['lo'], flag_hi = ci['hi'],
       mean_max_weight = mean(max_weight_norm, na.rm = TRUE),
       mean_p99_weight = mean(p99_weight, na.rm = TRUE),
       mean_ess = mean(ess, na.rm = TRUE),
       mean_ess_fraction = mean(ess_fraction, na.rm = TRUE),
       mean_probability_below_005 = mean(probability_below_005, na.rm = TRUE),
       mean_adherers = mean(n_adherent, na.rm = TRUE),
       mean_events = mean(n_events_adherent, na.rm = TRUE))
}, by = .(scenario, method, strategy)]
utils::write.csv(diag_summary, file.path(OUT, 'diagnostics.csv'), row.names = FALSE)

scenario_label <- decisions[score == 'oracle', {
  label <- if (any(classification == 'consequential')) 'consequential'
  else if (all(classification == 'negligible')) 'negligible' else 'uninformative'
  list(scenario_label = label)
}, by = .(scenario, strategy)]
diag_labeled <- merge(diag, scenario_label, by = c('scenario', 'strategy'), all.x = TRUE)
diagnostic_accuracy <- diag_labeled[, {
  positive <- scenario_label == 'consequential' & !is.na(diagnostic_flag)
  negative <- scenario_label == 'negligible' & !is.na(diagnostic_flag)
  sens <- wilson(sum(diagnostic_flag[positive] == 1L), sum(positive))
  spec <- wilson(sum(diagnostic_flag[negative] == 0L), sum(negative))
  list(sensitivity = sens['est'], sensitivity_lo = sens['lo'], sensitivity_hi = sens['hi'],
       specificity = spec['est'], specificity_lo = spec['lo'], specificity_hi = spec['hi'],
       positive_replicates = sum(positive), negative_replicates = sum(negative))
}, by = method]
utils::write.csv(diagnostic_accuracy, file.path(OUT, 'diagnostic-accuracy.csv'),
                 row.names = FALSE)

curves <- res[grepl('^cal_bin_', metric) & strategy %in% STRATEGIES,
              .(estimated_risk = mean(est, na.rm = TRUE),
                estimated_risk_mcse = stats::sd(est, na.rm = TRUE) /
                  sqrt(sum(is.finite(est))), truth_risk = truth[1L],
                score_mean = score_mean[1L], n_used = sum(is.finite(est))),
              by = .(scenario, profile, support, method, strategy, score, bin_key)]
curves[, bin := bin_key]
utils::write.csv(curves, file.path(OUT, 'calibration-curves.csv'), row.names = FALSE)

cat('\n== scenario-specific omission effects ==\n')
cat(sprintf('  decision rows: %d\n', nrow(decisions)))
cat(sprintf('  consequential: %d; negligible: %d; uninformative: %d\n',
            sum(decisions$classification == 'consequential'),
            sum(decisions$classification == 'negligible'),
            sum(decisions$classification == 'uninformative')))
cat('  consequential thresholds: intercept 0.10, bin risk 0.02, Brier 0.01, AUC 0.02\n')
cat('  negligible thresholds: intercept 0.05, every bin 0.01, Brier 0.005, AUC 0.01\n')
cat('  consequential coverage requires upper Monte Carlo bound <= 0.90\n')
cat('  negligible coverage requires the Monte Carlo interval inside 0.93 to 0.97\n')

n_con <- sum(decisions$classification == 'consequential')
n_neg <- sum(decisions$classification == 'negligible')
n_inf <- sum(decisions$classification == 'uninformative')
branch <- if (n_con > 0L && n_neg > 0L) {
  sprintf('MIXED SCENARIO-SPECIFIC BRANCH: %d consequential, %d negligible, %d uninformative',
          n_con, n_neg, n_inf)
} else if (n_con > 0L) {
  sprintf('CONSEQUENTIAL-DISTORTION BRANCH: %d consequential and %d uninformative',
          n_con, n_inf)
} else if (n_neg > 0L && n_inf == 0L) {
  sprintf('NO-CONSEQUENTIAL-DISTORTION BRANCH: all %d results are negligible', n_neg)
} else {
  sprintf('UNINFORMATIVE BRANCH: %d negligible and %d uninformative; no consequential result',
          n_neg, n_inf)
}
cat(sprintf('DECISION-RULE BRANCH: %s\n', branch))
