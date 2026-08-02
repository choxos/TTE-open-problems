## GMT-04 benchmark: performance, diagnostics, calibration, and decision.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))

OUT <- here('results')
raw_files <- sort(list.files(file.path(OUT, 'raw'),
                             pattern = '^scenario-.*[.]rds$', full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, 'truth.rds'))
truth_small <- truth[, c('analysis_scenario', 'risk0', 'risk1', 'rd',
                         'verified', 'scenario_label', 'type', 'control',
                         's', 'role', 'observed_u', 'primary', 'hidden_u',
                         'selective_positive_control', 'bootstrap_anchor')]
names(truth_small)[names(truth_small) == 'risk0'] <- 'truth_risk0'
names(truth_small)[names(truth_small) == 'risk1'] <- 'truth_risk1'
names(truth_small)[names(truth_small) == 'rd'] <- 'truth_rd'
res <- merge(res, truth_small, by = 'analysis_scenario', all.x = TRUE)

metric_value <- function(x, name) if (is.null(x[[name]])) NA_real_ else x[[name]]

performance <- do.call(rbind, lapply(
  split(res, interaction(res$analysis_scenario, res$method, drop = TRUE)),
  function(d) {
    d <- d[order(d$rep_id), ]
    estimate <- ifelse(d$output_valid, d$est, NA_real_)
    se <- ifelse(d$output_valid, d$se, NA_real_)
    truth_value <- d$truth_rd[1]
    lower <- estimate - 1.96 * se
    upper <- estimate + 1.96 * se
    bias <- perf_bias(estimate, truth_value)
    empse <- perf_empse(estimate)
    modse <- perf_modse(se)
    relative_se <- perf_relerror_modse(estimate, se)
    mse <- perf_mse(estimate, truth_value)
    coverage <- perf_coverage(lower, upper, truth_value)
    becoverage <- perf_becoverage(estimate, lower, upper)
    rejection <- perf_rejection(lower, upper, 0)
    convergence <- perf_convergence(estimate, nrow(d))
    data.frame(
      analysis_scenario = d$analysis_scenario[1],
      scenario_label = d$scenario_label[1], method = d$method[1],
      type = d$type[1], control = d$control[1], s = d$s[1],
      role = d$role[1], observed_u = d$observed_u[1],
      primary = d$primary[1], truth_rd = truth_value,
      bias = metric_value(bias, 'est'), bias_mcse = metric_value(bias, 'mcse'),
      empse = metric_value(empse, 'est'), empse_mcse = metric_value(empse, 'mcse'),
      modse = metric_value(modse, 'est'), modse_mcse = metric_value(modse, 'mcse'),
      relerror_modse = metric_value(relative_se, 'est'),
      relerror_modse_mcse = metric_value(relative_se, 'mcse'),
      mse = metric_value(mse, 'est'), mse_mcse = metric_value(mse, 'mcse'),
      coverage = metric_value(coverage, 'est'),
      coverage_mcse = metric_value(coverage, 'mcse'),
      becoverage = metric_value(becoverage, 'est'),
      becoverage_mcse = metric_value(becoverage, 'mcse'),
      rejection = metric_value(rejection, 'est'),
      rejection_mcse = metric_value(rejection, 'mcse'),
      convergence = metric_value(convergence, 'est'),
      convergence_mcse = metric_value(convergence, 'mcse'),
      n_used = sum(is.finite(estimate)), n_attempted = nrow(d),
      common_output_failure_rate = mean(!d$output_valid),
      software_error_rate = mean(d$software_error),
      rank_deficiency_rate = mean(d$rank_deficient %in% TRUE),
      coefficient_gt20_rate = mean(is.finite(d$max_coef) & d$max_coef > 20),
      condition_gt1e12_rate = mean(is.finite(d$condition_number) &
                                     d$condition_number > 1e12),
      clipping_rate = mean(d$clip_rate, na.rm = TRUE),
      convergence_warning_rate = mean(d$convergence_warning %in% TRUE),
      zero_ic_variance_rate = mean(d$zero_ic_variance %in% TRUE),
      stringsAsFactors = FALSE
    )
  }
))
performance$clipping_rate[is.nan(performance$clipping_rate)] <- NA_real_
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, 'performance.csv'), row.names = FALSE)

primary_methods <- c('iptw_nuisance', 'gformula_pooled', 'ltmle_formula')
primary_rows <- res[res$method %in% primary_methods, ]
wide <- reshape(
  primary_rows[, c('analysis_scenario', 'rep_id', 'method', 'est', 'output_valid')],
  idvar = c('analysis_scenario', 'rep_id'), timevar = 'method', direction = 'wide'
)
wide <- merge(wide, truth_small, by = 'analysis_scenario', all.x = TRUE)
estimate_columns <- paste0('est.', primary_methods)
valid_columns <- paste0('output_valid.', primary_methods)
wide$complete <- rowSums(is.finite(as.matrix(wide[, estimate_columns]))) == 3L &
  rowSums(as.matrix(wide[, valid_columns]) %in% TRUE) == 3L
wide$estimate_range <- apply(wide[, estimate_columns], 1, function(x) {
  if (all(is.finite(x))) max(x) - min(x) else NA_real_
})
wide$D <- ifelse(wide$complete,
                 wide$estimate_range > DISAGREEMENT_THRESHOLD, NA)

wilson_interval <- function(x, n, level = 0.95) {
  if (!is.finite(n) || n <= 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- x / n
  denominator <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denominator
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denominator
  c(lower = max(0, center - half), upper = min(1, center + half))
}

disagreement <- do.call(rbind, lapply(
  split(wide, wide$analysis_scenario),
  function(d) {
    used <- d$D[!is.na(d$D)]
    n <- length(used); x <- sum(used)
    interval <- wilson_interval(x, n)
    data.frame(
      analysis_scenario = d$analysis_scenario[1],
      scenario_label = d$scenario_label[1], type = d$type[1],
      control = d$control[1], s = d$s[1], role = d$role[1],
      observed_u = d$observed_u[1], primary = d$primary[1],
      n_planned = length(unique(d$rep_id)), n_complete = n,
      complete_frequency = n / length(unique(d$rep_id)),
      disagreement_probability = if (n) x / n else NA_real_,
      disagreement_mcse = if (n) sqrt((x / n) * (1 - x / n) / n) else NA_real_,
      disagreement_lower = interval['lower'],
      disagreement_upper = interval['upper'],
      stringsAsFactors = FALSE
    )
  }
))
rownames(disagreement) <- NULL
utils::write.csv(disagreement, file.path(OUT, 'disagreement.csv'), row.names = FALSE)

range_summary <- do.call(rbind, lapply(split(wide, wide$analysis_scenario), function(d) {
  x <- d$estimate_range[d$complete]
  data.frame(
    analysis_scenario = d$analysis_scenario[1], scenario_label = d$scenario_label[1],
    n_complete = length(x), mean_range = mean(x), median_range = stats::median(x),
    p90_range = unname(stats::quantile(x, 0.90)),
    p95_range = unname(stats::quantile(x, 0.95)), stringsAsFactors = FALSE
  )
}))
utils::write.csv(range_summary, file.path(OUT, 'range-summary.csv'), row.names = FALSE)

hidden <- wide[wide$hidden_u, ]
hidden$H <- hidden$complete & hidden$estimate_range < HIDDEN_AGREEMENT_THRESHOLD &
  abs(hidden[[paste0('est.', primary_methods[1])]] - hidden$truth_rd) > HIDDEN_ERROR_THRESHOLD &
  abs(hidden[[paste0('est.', primary_methods[2])]] - hidden$truth_rd) > HIDDEN_ERROR_THRESHOLD &
  abs(hidden[[paste0('est.', primary_methods[3])]] - hidden$truth_rd) > HIDDEN_ERROR_THRESHOLD
hidden_summary <- do.call(rbind, lapply(split(hidden, hidden$analysis_scenario), function(d) {
  applicable <- d$complete
  n <- sum(applicable); x <- sum(d$H[applicable])
  interval <- wilson_interval(x, n)
  data.frame(
    analysis_scenario = d$analysis_scenario[1], scenario_label = d$scenario_label[1],
    n_complete = n, h_count = x, h_probability = if (n) x / n else NA_real_,
    h_lower = interval['lower'], h_upper = interval['upper'],
    stringsAsFactors = FALSE
  )
}))
utils::write.csv(hidden_summary, file.path(OUT, 'hidden-agreement.csv'), row.names = FALSE)

hidden_errors <- list(); at <- 0L
for (scenario_id in unique(hidden$analysis_scenario)) {
  d <- hidden[hidden$analysis_scenario == scenario_id & hidden$H, ]
  for (method in primary_methods) {
    at <- at + 1L
    error <- d[[paste0('est.', method)]] - d$truth_rd
    hidden_errors[[at]] <- data.frame(
      analysis_scenario = scenario_id,
      method = method,
      n_given_h = length(error),
      mean_error = if (length(error)) mean(error) else NA_real_,
      median_error = if (length(error)) stats::median(error) else NA_real_,
      q10_error = if (length(error)) unname(stats::quantile(error, 0.10)) else NA_real_,
      q90_error = if (length(error)) unname(stats::quantile(error, 0.90)) else NA_real_,
      stringsAsFactors = FALSE
    )
  }
}
hidden_errors <- do.call(rbind, hidden_errors)
utils::write.csv(hidden_errors, file.path(OUT, 'hidden-errors-given-H.csv'),
                 row.names = FALSE)

set.seed(ANALYSIS_SEED)
method_pairs <- combn(primary_methods, 2, simplify = FALSE)
mse_rows <- list(); at <- 0L
for (scenario_id in unique(wide$analysis_scenario)) {
  d <- wide[wide$analysis_scenario == scenario_id & wide$complete, ]
  if (nrow(d) < 2L) next
  squared <- sapply(primary_methods, function(method) {
    (d[[paste0('est.', method)]] - d$truth_rd)^2
  })
  observed_mse <- colMeans(squared)
  boot_mse <- matrix(NA_real_, nrow = MSE_BOOTSTRAP_REPS,
                     ncol = length(primary_methods))
  colnames(boot_mse) <- primary_methods
  chunk <- 100L
  for (start in seq(1L, MSE_BOOTSTRAP_REPS, by = chunk)) {
    count <- min(chunk, MSE_BOOTSTRAP_REPS - start + 1L)
    index <- matrix(sample.int(nrow(d), nrow(d) * count, replace = TRUE),
                    nrow = nrow(d))
    for (m in seq_along(primary_methods)) {
      boot_mse[start:(start + count - 1L), m] <-
        colMeans(matrix(squared[, m][index], nrow = nrow(d)))
    }
  }
  for (pair in method_pairs) {
    at <- at + 1L
    difference <- squared[, pair[1]] - squared[, pair[2]]
    boot_difference <- boot_mse[, pair[1]] - boot_mse[, pair[2]]
    boot_ratio <- boot_mse[, pair[1]] / boot_mse[, pair[2]]
    p_value <- if (stats::sd(difference) == 0) {
      ifelse(mean(difference) == 0, 1, 0)
    } else {
      2 * stats::pnorm(-abs(mean(difference) /
        (stats::sd(difference) / sqrt(length(difference)))))
    }
    precision1 <- performance$mse_mcse[
      performance$analysis_scenario == scenario_id & performance$method == pair[1]
    ] / performance$mse[
      performance$analysis_scenario == scenario_id & performance$method == pair[1]
    ]
    precision2 <- performance$mse_mcse[
      performance$analysis_scenario == scenario_id & performance$method == pair[2]
    ] / performance$mse[
      performance$analysis_scenario == scenario_id & performance$method == pair[2]
    ]
    mse_rows[[at]] <- data.frame(
      analysis_scenario = scenario_id, method1 = pair[1], method2 = pair[2],
      n_paired = nrow(d), mse1 = observed_mse[pair[1]],
      mse2 = observed_mse[pair[2]],
      mse_difference = mean(difference),
      difference_lower = unname(stats::quantile(boot_difference, 0.025)),
      difference_upper = unname(stats::quantile(boot_difference, 0.975)),
      mse_ratio = observed_mse[pair[1]] / observed_mse[pair[2]],
      ratio_lower = unname(stats::quantile(boot_ratio, 0.025, na.rm = TRUE)),
      ratio_upper = unname(stats::quantile(boot_ratio, 0.975, na.rm = TRUE)),
      p_value = p_value,
      imprecise = any(c(precision1, precision2) > 0.10, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
}
mse_pairs <- do.call(rbind, mse_rows)
if (nrow(mse_pairs)) {
  mse_pairs$p_holm <- ave(mse_pairs$p_value, mse_pairs$analysis_scenario,
                          FUN = function(x) stats::p.adjust(x, method = 'holm'))
}
utils::write.csv(mse_pairs, file.path(OUT, 'paired-mse.csv'), row.names = FALSE)

res$gross_error <- !res$output_valid |
  (is.finite(res$est) & abs(res$est - res$truth_rd) > GROSS_ERROR_THRESHOLD) |
  (is.finite(res$lo) & res$lo > res$truth_rd) |
  (is.finite(res$hi) & res$hi < res$truth_rd)

diagnostic_rows <- list(); at <- 0L
for (coefficient_cutoff in COEFFICIENT_CUTOFFS) {
  for (condition_cutoff in CONDITION_CUTOFFS) {
    alert <- res$software_error | !res$output_valid |
      (res$rank_deficient %in% TRUE) |
      (is.finite(res$max_coef) & res$max_coef > coefficient_cutoff) |
      (is.finite(res$condition_number) & res$condition_number > condition_cutoff) |
      (is.finite(res$clip_rate) & res$clip_rate > 0) |
      (res$zero_ic_variance %in% TRUE)
    for (key in unique(interaction(res$analysis_scenario, res$method, drop = TRUE))) {
      q <- interaction(res$analysis_scenario, res$method, drop = TRUE) == key
      truth_positive <- res$gross_error[q]
      test_positive <- alert[q]
      tp <- sum(test_positive & truth_positive)
      fn <- sum(!test_positive & truth_positive)
      tn <- sum(!test_positive & !truth_positive)
      fp <- sum(test_positive & !truth_positive)
      at <- at + 1L
      diagnostic_rows[[at]] <- data.frame(
        analysis_scenario = res$analysis_scenario[q][1], method = res$method[q][1],
        coefficient_cutoff = coefficient_cutoff,
        condition_cutoff = condition_cutoff,
        gross_n = tp + fn, nongross_n = tn + fp, alert_n = tp + fp,
        sensitivity = if (tp + fn >= 400L) tp / (tp + fn) else NA_real_,
        specificity = if (tn + fp >= 400L) tn / (tn + fp) else NA_real_,
        false_positive_rate = if (tn + fp >= 400L) fp / (tn + fp) else NA_real_,
        positive_predictive_value = if (tp + fp >= 400L) tp / (tp + fp) else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
}
diagnostics <- do.call(rbind, diagnostic_rows)
utils::write.csv(diagnostics, file.path(OUT, 'diagnostic-performance.csv'),
                 row.names = FALSE)

bootstrap_rows <- res[res$method == 'iptw_nuisance' &
                        is.finite(res$bootstrap_se), ]
bootstrap_validation <- if (nrow(bootstrap_rows)) do.call(rbind, lapply(
  split(bootstrap_rows, bootstrap_rows$analysis_scenario), function(d) {
    analytic_cover <- d$lo <= d$truth_rd & d$hi >= d$truth_rd
    bootstrap_cover <- d$est - 1.96 * d$bootstrap_se <= d$truth_rd &
      d$est + 1.96 * d$bootstrap_se >= d$truth_rd
    data.frame(
      analysis_scenario = d$analysis_scenario[1],
      scenario_label = d$scenario_label[1], n_bootstrapped = nrow(d),
      mean_analytic_to_bootstrap_se = mean(d$se / d$bootstrap_se),
      median_analytic_to_bootstrap_se = stats::median(d$se / d$bootstrap_se),
      analytic_coverage = mean(analytic_cover),
      bootstrap_coverage = mean(bootstrap_cover),
      coverage_difference = mean(analytic_cover) - mean(bootstrap_cover),
      stringsAsFactors = FALSE
    )
  }
)) else data.frame()
utils::write.csv(bootstrap_validation,
                 file.path(OUT, 'iptw-bootstrap-validation.csv'), row.names = FALSE)

bootstrap_branch_rate <- function(values, branch, B = CALIBRATION_BOOTSTRAP_REPS) {
  values <- values[!is.na(values)]
  n <- length(values)
  if (!n) return(NA_real_)
  fired <- logical(B)
  for (b in seq_len(B)) {
    p <- mean(sample(values, n, replace = TRUE))
    se <- sqrt(p * (1 - p) / n)
    lower <- max(0, p - 1.96 * se)
    upper <- min(1, p + 1.96 * se)
    fired[b] <- if (branch == 'negative') upper < PRIMARY_PROBABILITY_THRESHOLD else
      lower > PRIMARY_PROBABILITY_THRESHOLD
  }
  mean(fired)
}

c0 <- disagreement[disagreement$control == 'C0' & !is.na(disagreement$control), ]
c1 <- disagreement[disagreement$control == 'C1' & !is.na(disagreement$control), ]
c0_values <- wide$D[wide$control == 'C0' & !is.na(wide$control)]
c1_values <- wide$D[wide$control == 'C1' & !is.na(wide$control)]
set.seed(ANALYSIS_SEED + 1L)
calibration <- data.frame(
  control = c('C0', 'C1'),
  expected_branch = c('negative', 'positive'),
  direct_probability = c(c0$disagreement_probability, c1$disagreement_probability),
  direct_lower = c(c0$disagreement_lower, c1$disagreement_lower),
  direct_upper = c(c0$disagreement_upper, c1$disagreement_upper),
  bootstrap_expected_branch_rate = c(
    bootstrap_branch_rate(c0_values, 'negative'),
    bootstrap_branch_rate(c1_values, 'positive')
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(calibration, file.path(OUT, 'calibration-bootstrap.csv'),
                 row.names = FALSE)

primary_ids <- ANALYSIS_SCENARIOS$analysis_scenario[ANALYSIS_SCENARIOS$primary]
primary_parts <- disagreement[match(primary_ids, disagreement$analysis_scenario), ]
p_primary <- mean(primary_parts$disagreement_probability)
p_primary_mcse <- sqrt(sum(
  primary_parts$disagreement_probability *
    (1 - primary_parts$disagreement_probability) /
    primary_parts$n_complete
) / 16)
p_primary_lower <- max(0, p_primary - 1.96 * p_primary_mcse)
p_primary_upper <- min(1, p_primary + 1.96 * p_primary_mcse)

truth_ok <- file.exists(file.path(OUT, 'truth-manifest.rds')) &&
  all(readRDS(file.path(OUT, 'truth-manifest.rds'))$verified) &&
  length(list.files(OUT, pattern = '^truth-amendment-.*[.]csv$')) > 0L
audit_ok <- file.exists(file.path(OUT, 'implementation-audit.rds')) &&
  isTRUE(readRDS(file.path(OUT, 'implementation-audit.rds'))$status)
replicate_ok <- all(primary_parts$n_planned >= N_REP)
complete_ok <- all(primary_parts$complete_frequency >= COMPLETE_TRIPLET_THRESHOLD)
alignment_ok <- all(res$alignment_ok[res$primary])
calibration_ok <- nrow(c0) == 1L && nrow(c1) == 1L &&
  c0$disagreement_upper < PRIMARY_PROBABILITY_THRESHOLD &&
  c1$disagreement_lower > PRIMARY_PROBABILITY_THRESHOLD

failed_gates <- c(
  if (!truth_ok) 'verified truth manifest or dated amendment absent',
  if (!audit_ok) 'implementation audit absent or failed',
  if (!replicate_ok) 'fewer than 2000 planned replicates in a primary scenario',
  if (!complete_ok) 'complete-triplet frequency below 0.95',
  if (!alignment_ok) 'protocol alignment check failed',
  if (!calibration_ok) 'C0 or C1 calibration bound failed'
)
if (length(failed_gates)) {
  branch <- 'UNINFORMATIVE'
} else if (p_primary_lower > PRIMARY_PROBABILITY_THRESHOLD) {
  branch <- 'MATERIAL IMPLEMENTATION DEPENDENCE'
} else if (p_primary_upper < PRIMARY_PROBABILITY_THRESHOLD) {
  branch <- 'NO MATERIAL IMPLEMENTATION DEPENDENCE DETECTED'
} else {
  branch <- 'UNINFORMATIVE'
  failed_gates <- c(failed_gates, 'the 95 percent Monte Carlo interval includes 0.20')
}

decision <- data.frame(
  p_primary = p_primary, mcse = p_primary_mcse,
  lower = p_primary_lower, upper = p_primary_upper,
  probability_threshold = PRIMARY_PROBABILITY_THRESHOLD,
  disagreement_threshold = DISAGREEMENT_THRESHOLD,
  complete_triplet_threshold = COMPLETE_TRIPLET_THRESHOLD,
  truth_gate = truth_ok, audit_gate = audit_ok, replicate_gate = replicate_ok,
  complete_gate = complete_ok, alignment_gate = alignment_ok,
  calibration_gate = calibration_ok,
  branch = branch,
  failed_gates = paste(failed_gates, collapse = '; '),
  scope = 'three named implementations in four observed-U benchmark scenarios',
  stringsAsFactors = FALSE
)
utils::write.csv(decision, file.path(OUT, 'primary-decision.csv'), row.names = FALSE)

cat('\n== named implementation performance ==\n')
cat(sprintf('rows in performance.csv: %d\n', nrow(performance)))
cat(sprintf('minimum convergence: %.3f\n', min(performance$convergence, na.rm = TRUE)))
cat(sprintf('maximum common output-failure rate: %.3f\n',
            max(performance$common_output_failure_rate, na.rm = TRUE)))
cat('\n== primary disagreement endpoint ==\n')
for (i in seq_len(nrow(primary_parts))) {
  cat(sprintf('%s: p=%.3f, 95%% MC interval %.3f to %.3f, complete %.3f\n',
              primary_parts$scenario_label[i],
              primary_parts$disagreement_probability[i],
              primary_parts$disagreement_lower[i],
              primary_parts$disagreement_upper[i],
              primary_parts$complete_frequency[i]))
}
cat(sprintf('equal-weight p_primary=%.3f, 95%% MC interval %.3f to %.3f\n',
            p_primary, p_primary_lower, p_primary_upper))
cat(sprintf('C0 upper bound %.3f must be below %.2f; C1 lower bound %.3f must exceed %.2f\n',
            c0$disagreement_upper, PRIMARY_PROBABILITY_THRESHOLD,
            c1$disagreement_lower, PRIMARY_PROBABILITY_THRESHOLD))
if (length(failed_gates)) cat('failed gates: ', paste(failed_gates, collapse = '; '), '\n', sep = '')
cat(sprintf('DECISION BRANCH: %s. The range threshold is %.2f, the probability threshold is %.2f, and the complete-triplet gate is %.2f.\n',
            branch, DISAGREEMENT_THRESHOLD, PRIMARY_PROBABILITY_THRESHOLD,
            COMPLETE_TRIPLET_THRESHOLD))
