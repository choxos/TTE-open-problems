## Study PRO-04: performance, standardized mechanism probabilities, and decision.
##
##   Rscript R/05-analyze.R

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))

OUT <- here('results')
raw_dir <- file.path(OUT, 'raw')
raw_files <- if (dir.exists(raw_dir)) sort(list.files(raw_dir, full.names = TRUE)) else character()
raw_files <- raw_files[startsWith(basename(raw_files), 'scenario-') & endsWith(raw_files, '.rds')]
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, 'truth.rds'))
scenarios <- build_scenarios()
if (!all(res$config_signature == CONFIG_SIGNATURE)) stop('Raw results use a stale configuration')

meta <- truth[, c('scenario', 'mechanism_id', 'lambda',
                  'quadrature_converged', 'class_resolved',
                  'calibration_ok', 'calibration_ok_verified')]
res <- merge(res, meta, by = c('scenario', 'mechanism_id'), all.x = TRUE)
complete_run <- length(unique(res$scenario)) == nrow(scenarios)

wilson_ci <- function(successes, n, level = 0.95) {
  if (!is.finite(n) || n <= 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- successes / n
  denominator <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denominator
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denominator
  c(lower = center - half, upper = center + half)
}

## Performance is computed on estimation errors because truth varies by
## mechanism within every stratum.
perf_rows <- lapply(split(res, list(res$scenario, res$method), drop = TRUE), function(d) {
  error <- d$est - d$target_value
  lo_centered <- d$lo95 - d$target_value
  hi_centered <- d$hi95 - d$target_value
  bias <- perf_bias(error, 0)
  empse <- perf_empse(error)
  modse <- perf_modse(d$se)
  relse <- perf_relerror_modse(error, d$se)
  mse <- perf_mse(error, 0)
  coverage <- perf_coverage(lo_centered, hi_centered, 0)
  convergence <- perf_convergence(d$est, nrow(d))
  covered <- is.finite(lo_centered) & is.finite(hi_centered) &
    lo_centered <= 0 & hi_centered >= 0
  coverage_n <- sum(is.finite(lo_centered) & is.finite(hi_centered))
  coverage_ci <- wilson_ci(sum(covered), coverage_n)
  s <- scenarios[scenarios$scenario == d$scenario[1], , drop = FALSE]
  rmse <- sqrt(mse[['est']])
  data.frame(
    scenario = d$scenario[1], component = s$component,
    fidelity = s$fidelity, effect_modification = s$effect_modification,
    dependence = s$dependence, method = d$method[1],
    bias = bias[['est']], bias_mcse = bias[['mcse']],
    bias_lower = bias[['est']] - 1.96 * bias[['mcse']],
    bias_upper = bias[['est']] + 1.96 * bias[['mcse']],
    empse = empse[['est']], empse_mcse = empse[['mcse']],
    modse = modse[['est']], modse_mcse = modse[['mcse']],
    relerror_modse = relse[['est']], relerror_modse_mcse = relse[['mcse']],
    mse = mse[['est']], mse_mcse = mse[['mcse']], rmse = rmse,
    coverage = coverage[['est']], coverage_mcse = coverage[['mcse']],
    coverage_lower = coverage_ci[['lower']], coverage_upper = coverage_ci[['upper']],
    mean_interval_width = mean(d$interval_width, na.rm = TRUE),
    interval_width_mcse = stats::sd(d$interval_width, na.rm = TRUE) /
      sqrt(sum(is.finite(d$interval_width))),
    convergence = convergence[['est']],
    low_ess_rate = mean(d$low_ess %in% TRUE),
    n_used = sum(is.finite(d$est)), n_attempted = nrow(d),
    stringsAsFactors = FALSE
  )
})
performance <- do.call(rbind, perf_rows)
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, 'performance.csv'), row.names = FALSE)

## Stratum probabilities retain every mechanism draw, including gray cases.
stratum_rows <- lapply(split(truth, truth$scenario), function(d) {
  s <- scenarios[scenarios$scenario == d$scenario[1], , drop = FALSE]
  data.frame(
    scenario = d$scenario[1], component = s$component,
    fidelity = s$fidelity, effect_modification = s$effect_modification,
    dependence = s$dependence, n = nrow(d),
    p_material = mean(abs(d$delta) >= MATERIAL_MARGIN),
    p_preserving = mean(abs(d$delta) <= PRESERVATION_MARGIN),
    p_gray = mean(abs(d$delta) > PRESERVATION_MARGIN & abs(d$delta) < MATERIAL_MARGIN),
    mean_delta = mean(d$delta), mean_abs_delta = mean(abs(d$delta)),
    stringsAsFactors = FALSE
  )
})
stratum_probabilities <- do.call(rbind, stratum_rows)
utils::write.csv(stratum_probabilities,
                 file.path(OUT, 'mechanism-probabilities.csv'), row.names = FALSE)

## Critique fix: uncertainty is obtained by nonparametric resampling within each
## random-mechanism stratum. It is not a binomial interval over 24 fixed cells.
set.seed(MASTER_SEED + 900001L)
probability_summary <- function(preservation, material, label) {
  p_preserving <- p_material <- numeric(nrow(scenarios))
  boot_preserving <- boot_material <- numeric(BOOTSTRAP_REPS)
  split_truth <- split(truth, truth$scenario)
  for (i in seq_along(split_truth)) {
    d <- split_truth[[i]]
    category <- ifelse(abs(d$delta) <= preservation, 1L,
                       ifelse(abs(d$delta) >= material, 2L, 3L))
    probabilities <- tabulate(category, nbins = 3L) / length(category)
    draws <- stats::rmultinom(BOOTSTRAP_REPS, length(category), probabilities)
    p_preserving[i] <- probabilities[1]
    p_material[i] <- probabilities[2]
    boot_preserving <- boot_preserving + draws[1, ] / length(category) / nrow(scenarios)
    boot_material <- boot_material + draws[2, ] / length(category) / nrow(scenarios)
  }
  data.frame(
    label = label, preservation_margin = preservation, material_margin = material,
    p_preserving = mean(p_preserving),
    p_preserving_lower = unname(stats::quantile(boot_preserving, 0.025)),
    p_preserving_upper = unname(stats::quantile(boot_preserving, 0.975)),
    p_material = mean(p_material),
    p_material_lower = unname(stats::quantile(boot_material, 0.025)),
    p_material_upper = unname(stats::quantile(boot_material, 0.975)),
    stringsAsFactors = FALSE
  )
}
standardized <- do.call(rbind, lapply(seq_len(nrow(MARGIN_PAIRS)), function(i) {
  probability_summary(MARGIN_PAIRS$preservation[i], MARGIN_PAIRS$material[i],
                      MARGIN_PAIRS$label[i])
}))
utils::write.csv(standardized, file.path(OUT, 'standardized-probabilities.csv'),
                 row.names = FALSE)

## Continuous response surface. Each curve averages over the generated fidelity
## parameters and dependence slopes within its declared stratum.
surface_rows <- lapply(split(truth, list(truth$component, truth$fidelity,
                                         truth$dependence), drop = TRUE), function(d) {
  fit <- stats::lm(delta ~ lambda + I(lambda^2) + I(lambda^3), data = d)
  grid <- data.frame(lambda = seq(0, 1, by = 0.025))
  prediction <- stats::predict(fit, newdata = grid, se.fit = TRUE)
  critical <- stats::qt(0.975, df = fit$df.residual)
  data.frame(
    component = d$component[1], fidelity = d$fidelity[1],
    dependence = d$dependence[1], lambda = grid$lambda,
    mean_delta = as.numeric(prediction$fit),
    lower = as.numeric(prediction$fit - critical * prediction$se.fit),
    upper = as.numeric(prediction$fit + critical * prediction$se.fit),
    stringsAsFactors = FALSE
  )
})
response_surface <- do.call(rbind, surface_rows)
utils::write.csv(response_surface, file.path(OUT, 'response-surface.csv'),
                 row.names = FALSE)

metric_row <- function(d, method, truth_group, metric, success) {
  n <- nrow(d)
  count <- sum(success, na.rm = TRUE)
  ci <- wilson_ci(count, n)
  data.frame(method = method, truth_group = truth_group, metric = metric,
             estimate = if (n) count / n else NA_real_,
             lower = ci[['lower']], upper = ci[['upper']], n = n,
             stringsAsFactors = FALSE)
}

diagnostic_rows <- list()
for (method in c('gap_cc', 'gap_aug')) {
  d <- res[res$method == method & is.finite(res$est), , drop = FALSE]
  preserving <- d[abs(d$target_value) <= DIAGNOSTIC_PRESERVING_TRUTH, , drop = FALSE]
  changed <- d[abs(d$target_value) >= DIAGNOSTIC_CHANGED_TRUTH, , drop = FALSE]
  diagnostic_rows[[length(diagnostic_rows) + 1L]] <- metric_row(
    preserving, method, 'preserving', 'preserving_sensitivity',
    preserving$classification == 'preserving')
  diagnostic_rows[[length(diagnostic_rows) + 1L]] <- metric_row(
    preserving, method, 'preserving', 'false_changed_rate',
    preserving$classification == 'changed')
  diagnostic_rows[[length(diagnostic_rows) + 1L]] <- metric_row(
    preserving, method, 'preserving', 'indeterminate_rate',
    preserving$classification == 'indeterminate')
  diagnostic_rows[[length(diagnostic_rows) + 1L]] <- metric_row(
    changed, method, 'changed', 'changed_sensitivity',
    changed$classification == 'changed')
  diagnostic_rows[[length(diagnostic_rows) + 1L]] <- metric_row(
    changed, method, 'changed', 'indeterminate_rate',
    changed$classification == 'indeterminate')
}
diagnostics <- do.call(rbind, diagnostic_rows)
utils::write.csv(diagnostics, file.path(OUT, 'diagnostic-performance.csv'),
                 row.names = FALSE)

cc <- res[res$method == 'gap_cc', c('scenario', 'mechanism_id', 'est', 'target_value')]
aug <- res[res$method == 'gap_aug', c('scenario', 'mechanism_id', 'est')]
names(cc)[3:4] <- c('est_cc', 'truth_delta')
names(aug)[3] <- 'est_aug'
eff <- merge(cc, aug, by = c('scenario', 'mechanism_id'))
eff <- eff[is.finite(eff$est_cc) & is.finite(eff$est_aug), ]
error_cc <- eff$est_cc - eff$truth_delta
error_aug <- eff$est_aug - eff$truth_delta
efficiency <- data.frame(
  n = nrow(eff), empse_cc = stats::sd(error_cc), empse_aug = stats::sd(error_aug),
  variance_ratio_cc_to_aug = stats::var(error_cc) / stats::var(error_aug),
  rmse_ratio_cc_to_aug = sqrt(mean(error_cc^2)) / sqrt(mean(error_aug^2))
)
utils::write.csv(efficiency, file.path(OUT, 'gap-efficiency.csv'), row.names = FALSE)

## Ordered and exhaustive decision table from the revised protocol.
truth_quadrature_ok <- all(truth$quadrature_converged %in% TRUE) &&
  all(truth$class_resolved %in% TRUE)
truth_calibration_ok <- all(truth$calibration_ok %in% TRUE) &&
  all(truth$calibration_ok_verified %in% TRUE)
controls <- truth$component %in% c('eligibility', 'strategy') &
  truth$effect_modification == 'absent'
control_ok <- all(abs(truth$delta[controls]) <= 1e-7)
calibration_methods <- performance[performance$method %in% c('oracle', 'operational'), ]
calibration_rows_complete <- nrow(calibration_methods) == 2L * nrow(scenarios)
bias_calibrated <- calibration_rows_complete &&
  all(is.finite(calibration_methods$bias_lower)) &&
  all(calibration_methods$bias_lower >= -0.005 & calibration_methods$bias_upper <= 0.005)
coverage_calibrated <- calibration_rows_complete &&
  all(is.finite(calibration_methods$coverage_lower)) &&
  all(calibration_methods$coverage_lower >= 0.93 &
      calibration_methods$coverage_upper <= 0.97)
convergence_calibrated <- calibration_rows_complete &&
  all(calibration_methods$convergence == 1)
global_valid <- complete_run && truth_quadrature_ok && truth_calibration_ok &&
  control_ok && bias_calibrated && coverage_calibrated && convergence_calibrated

aug_perf <- performance[performance$method == 'augmented', ]
aug_bias_ok <- nrow(aug_perf) == nrow(scenarios) &&
  all(aug_perf$bias_lower >= -0.005 & aug_perf$bias_upper <= 0.005)
aug_coverage_ok <- nrow(aug_perf) == nrow(scenarios) &&
  all(aug_perf$coverage_lower >= 0.93 & aug_perf$coverage_upper <= 0.97)
aug_precision_ok <- nrow(aug_perf) == nrow(scenarios) &&
  all(aug_perf$rmse <= 0.015 & aug_perf$mean_interval_width <= 0.04)
augmented_label <- if (aug_bias_ok && aug_coverage_ok && aug_precision_ok) {
  'useful'
} else if (aug_bias_ok && aug_coverage_ok) {
  'calibrated but imprecise'
} else {
  'not calibrated'
}

get_diag <- function(metric, group) {
  diagnostics[diagnostics$method == 'gap_aug' & diagnostics$metric == metric &
                diagnostics$truth_group == group, , drop = FALSE]
}
d_preserve <- get_diag('preserving_sensitivity', 'preserving')
d_change <- get_diag('changed_sensitivity', 'changed')
d_ind_p <- get_diag('indeterminate_rate', 'preserving')
d_ind_c <- get_diag('indeterminate_rate', 'changed')
diagnostic_usable <- nrow(d_preserve) == 1L && nrow(d_change) == 1L &&
  nrow(d_ind_p) == 1L && nrow(d_ind_c) == 1L &&
  is.finite(d_preserve$lower) && is.finite(d_change$lower) &&
  is.finite(d_ind_p$upper) && is.finite(d_ind_c$upper) &&
  d_preserve$lower >= 0.80 && d_change$lower >= 0.80 &&
  d_ind_p$upper <= 0.20 && d_ind_c$upper <= 0.20
diagnostic_label <- if (diagnostic_usable) 'usable' else 'not usable'

main <- standardized[standardized$label == 'main', , drop = FALSE]
if (!global_valid) {
  branch <- 'GLOBAL NUMERICAL CONCLUSION INVALID'
} else if (main$p_material_lower > 0.30) {
  branch <- 'MATERIAL NUMERICAL CONSEQUENCES COMMON IN THE DECLARED SYNTHETIC DISTRIBUTION'
} else if (main$p_material_upper < 0.10 && main$p_preserving_lower > 0.80) {
  branch <- 'NO IMPORTANT NUMERICAL DISCREPANCY DEMONSTRATED IN THE DECLARED SYNTHETIC DISTRIBUTION'
} else {
  branch <- 'MIXED OR THRESHOLD-INDETERMINATE'
}

decision <- data.frame(
  complete_run = complete_run, truth_quadrature_ok = truth_quadrature_ok,
  truth_calibration_ok = truth_calibration_ok, lambda_zero_controls_ok = control_ok,
  oracle_operational_bias_ok = bias_calibrated,
  oracle_operational_coverage_ok = coverage_calibrated,
  oracle_operational_convergence_ok = convergence_calibrated,
  global_valid = global_valid,
  p_material = main$p_material, p_material_lower = main$p_material_lower,
  p_material_upper = main$p_material_upper,
  p_preserving = main$p_preserving, p_preserving_lower = main$p_preserving_lower,
  p_preserving_upper = main$p_preserving_upper,
  augmented_recovery = augmented_label,
  augmented_diagnostic = diagnostic_label,
  branch = branch, stringsAsFactors = FALSE
)
utils::write.csv(decision, file.path(OUT, 'decision.csv'), row.names = FALSE)

cat('\n== standardized numerical consequences ==\n')
cat(sprintf('  P_M = %.3f, stratified bootstrap 95%% CI %.3f to %.3f\n',
            main$p_material, main$p_material_lower, main$p_material_upper))
cat(sprintf('  P_P = %.3f, stratified bootstrap 95%% CI %.3f to %.3f\n',
            main$p_preserving, main$p_preserving_lower, main$p_preserving_upper))
cat(sprintf('  signed Delta range %.4f to %.4f; median absolute Delta %.4f\n',
            min(truth$delta), max(truth$delta), stats::median(abs(truth$delta))))
cat('\n== validity gates ==\n')
cat(sprintf('  quadrature %s; calibration %s; lambda-zero controls %s\n',
            truth_quadrature_ok, truth_calibration_ok, control_ok))
cat(sprintf('  oracle and operational bias %s; coverage %s; convergence %s\n',
            bias_calibrated, coverage_calibrated, convergence_calibrated))
cat(sprintf('  augmented recovery: %s\n', augmented_label))
cat(sprintf('  augmented diagnostic: %s\n', diagnostic_label))
cat(sprintf('\nDECISION BRANCH: %s. Positive requires lower P_M > 0.30; negative requires upper P_M < 0.10 and lower P_P > 0.80.\n',
            branch))
