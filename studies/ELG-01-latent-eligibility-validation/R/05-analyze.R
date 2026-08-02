## ELG-01: performance analysis and decision rule.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))

OUT <- here('results')
set_recording_alphas(readRDS(file.path(OUT, 'recording-calibration.rds')))
scenarios <- build_scenarios()
truth <- readRDS(file.path(OUT, 'truth.rds'))
id_truth <- readRDS(file.path(OUT, 'identification-truth.rds'))
raw_files <- sort(list.files(file.path(OUT, 'raw'), '^scenario-.*\\.rds$',
                             full.names = TRUE))
stopifnot(length(raw_files) > 0)
res <- do.call(rbind, lapply(raw_files, readRDS))

keep <- c(
  'target_scenario', 'pair_rep', 'method', 'variant', 'information_set',
  'target', 'lambda_star', 'est', 'se', 'lo', 'hi', 'pe_est', 'ne_est',
  'pe_se', 'within_var', 'between_var', 'df', 'ess0', 'ess1', 'max_weight',
  'bound_lo', 'bound_hi', 'bound_ci_lo', 'bound_ci_hi', 'bound_se_lo',
  'bound_se_hi', 'pe_lower', 'pe_upper', 'true_ne', 'nre', 'nre_yield',
  'obs_identity', 'nv_identity', 'scheduled', 'fail'
)
res <- res[, intersect(keep, names(res)), drop = FALSE]
meta <- scenarios
names(meta)[names(meta) == 'scenario'] <- 'target_scenario'
res <- merge(res, meta, by = 'target_scenario', all.x = TRUE, sort = FALSE)
truth_small <- truth[, c('scenario', 'pe', 'rd_e', 'rd_re',
                         'target_discrepancy'), drop = FALSE]
names(truth_small)[1L] <- 'target_scenario'
res <- merge(res, truth_small, by = 'target_scenario', all.x = TRUE, sort = FALSE)
res$truth_value <- ifelse(res$target == 'recorded_eligible', res$rd_re, res$rd_e)

metric <- function(expr) {
  tryCatch(expr, error = function(e) list(est = NA_real_, mcse = NA_real_))
}
value <- function(x, name) {
  z <- x[[name]]
  if (is.null(z) || !length(z)) NA_real_ else as.numeric(z[1L])
}

wilson <- function(k, n, level = 0.95) {
  if (!is.finite(n) || n <= 0) return(c(NA_real_, NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- k / n
  den <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(max(0, center - half), min(1, center + half))
}

## The signature is (est, lower, upper) and it is not in doubt. What stood here
## inspected `formals(perf_becoverage)` and dispatched on the names it found,
## which is a way of being wrong that survives review: with the real signature
## it fell through to `perf_becoverage(lo - bias, hi - bias, truth_value)`,
## passing a lower bound as the estimate and the truth as an upper bound.
##
## That fallback does show what was intended, and it is worth keeping the
## algebra rather than the code. Shifting each interval by the bias and asking
## whether it covers the truth is the same question as asking whether the
## unshifted interval covers the mean estimate, because
## `lo - bias <= truth <= hi - bias` holds exactly when
## `lo <= truth + bias <= hi`, and `truth + bias` is `mean(est)`. So the direct
## call computes what the wrapper was reaching for.
call_becoverage <- function(est, se, lo, hi, truth_value) {
  metric(perf_becoverage(est, lo, hi))
}

summarize_point <- function(d) {
  attempted <- nrow(d)
  success_est <- is.finite(d$est)
  success_interval <- success_est & is.finite(d$se) & is.finite(d$lo) & is.finite(d$hi)
  est <- d$est[success_est]
  tv <- d$truth_value[1L]
  se <- d$se[success_interval]
  est_i <- d$est[success_interval]
  lo <- d$lo[success_interval]
  hi <- d$hi[success_interval]

  b <- if (length(est)) metric(perf_bias(est, tv)) else metric(stop('none'))
  es <- if (length(est) > 1L) metric(perf_empse(est)) else metric(stop('none'))
  mse <- if (length(est)) metric(perf_mse(est, tv)) else metric(stop('none'))
  ms <- if (length(se)) metric(perf_modse(se)) else metric(stop('none'))
  re <- if (length(se) > 1L) metric(perf_relerror_modse(est_i, se)) else metric(stop('none'))
  cv <- if (length(lo)) metric(perf_coverage(lo, hi, tv)) else metric(stop('none'))
  bec <- if (length(lo)) call_becoverage(est_i, se, lo, hi, tv) else metric(stop('none'))
  rj <- if (length(lo)) metric(perf_rejection(lo, hi, 0)) else metric(stop('none'))
  cg <- metric(perf_convergence(ifelse(success_est, d$est, NA_real_), attempted))

  conv_w <- wilson(sum(success_est), attempted)
  cov_w <- wilson(sum(lo <= tv & hi >= tv), length(lo))
  worst_low <- metric(perf_bias(ifelse(success_est, d$est, -1), tv))
  worst_high <- metric(perf_bias(ifelse(success_est, d$est, 1), tv))
  bias_est <- value(b, 'est')
  bias_mcse <- value(b, 'mcse')
  ci95 <- bias_est + c(-1, 1) * stats::qnorm(0.975) * bias_mcse
  ci90 <- bias_est + c(-1, 1) * stats::qnorm(0.950) * bias_mcse
  bias_class <- if (!all(is.finite(c(ci95, ci90)))) {
    'uninformative'
  } else if (ci95[1L] > 0.010 || ci95[2L] < -0.010) {
    'material'
  } else if (ci90[1L] > -0.010 && ci90[2L] < 0.010) {
    'equivalent'
  } else {
    'inconclusive'
  }

  list(
    truth = tv,
    bias = bias_est, bias_mcse = bias_mcse,
    bias_ci95_lo = ci95[1L], bias_ci95_hi = ci95[2L],
    bias_ci90_lo = ci90[1L], bias_ci90_hi = ci90[2L],
    bias_class = bias_class,
    worst_bias_low = value(worst_low, 'est'),
    worst_bias_high = value(worst_high, 'est'),
    empse = value(es, 'est'), empse_mcse = value(es, 'mcse'),
    modse = value(ms, 'est'), modse_mcse = value(ms, 'mcse'),
    relerror_modse = value(re, 'est'),
    relerror_modse_mcse = value(re, 'mcse'),
    mse = value(mse, 'est'), mse_mcse = value(mse, 'mcse'),
    coverage = value(cv, 'est'), coverage_mcse = value(cv, 'mcse'),
    coverage_wilson_lo = cov_w[1L], coverage_wilson_hi = cov_w[2L],
    becoverage = value(bec, 'est'), becoverage_mcse = value(bec, 'mcse'),
    rejection = value(rj, 'est'), rejection_mcse = value(rj, 'mcse'),
    convergence = value(cg, 'est'), convergence_mcse = value(cg, 'mcse'),
    convergence_wilson_lo = conv_w[1L], convergence_wilson_hi = conv_w[2L],
    n_used = sum(success_est), n_attempted = attempted,
    mean_ess0 = mean(d$ess0[success_est], na.rm = TRUE),
    mean_ess1 = mean(d$ess1[success_est], na.rm = TRUE),
    mean_max_weight = mean(d$max_weight[success_est], na.rm = TRUE)
  )
}

DT <- data.table::as.data.table(res)
point <- DT[scheduled == TRUE & method != 'bounds']
group_cols <- c(
  'target_scenario', 'method', 'variant', 'information_set', 'target',
  'm', 'lambda_key', 'lambda', 'validation_n', 'effect', 'kappa'
)
perf <- point[, summarize_point(.SD), by = group_cols]
perf[, decision_critical :=
       !(method %in% c('mi_continuous_m50', 'mi_indicator_m50',
                       'oracle_recording_ipaw')) &
       !(method == 'fractional' & variant != 'primary') &
       !(method == 'augmented' & variant != 'primary')]
perf[, needs_extension := decision_critical & is.finite(bias_mcse) & bias_mcse > 0.0025]
perf[, method_status := ifelse(
  convergence < 0.95 | needs_extension, 'uninformative', bias_class
)]
utils::write.csv(as.data.frame(perf), file.path(OUT, 'performance.csv'),
                 row.names = FALSE)

prevalence <- DT[scheduled == TRUE & is.finite(pe_est), {
  ok <- is.finite(pe_est)
  b <- metric(perf_bias(pe_est[ok], pe[1L]))
  m0 <- metric(perf_mse(pe_est[ok], pe[1L]))
  cg <- metric(perf_convergence(ifelse(ok, pe_est, NA_real_), .N))
  list(
    truth_pe = pe[1L], bias = value(b, 'est'), bias_mcse = value(b, 'mcse'),
    mse = value(m0, 'est'), mse_mcse = value(m0, 'mcse'),
    convergence = value(cg, 'est'), n_used = sum(ok), n_attempted = .N
  )
}, by = group_cols]
utils::write.csv(as.data.frame(prevalence),
                 file.path(OUT, 'prevalence-performance.csv'), row.names = FALSE)

totals <- DT[scheduled == TRUE & is.finite(ne_est) & is.finite(true_ne), {
  err <- ne_est - true_ne
  list(mean_error = mean(err), mcse = stats::sd(err) / sqrt(.N),
       mean_absolute_error = mean(abs(err)), rmse = sqrt(mean(err^2)), n = .N)
}, by = group_cols]
utils::write.csv(as.data.frame(totals), file.path(OUT, 'realized-total-performance.csv'),
                 row.names = FALSE)

yield <- DT[method == 'complete_case' & variant == 'primary',
            .(mean_nre = mean(nre), mcse_nre = stats::sd(nre) / sqrt(.N),
              mean_yield = mean(nre_yield),
              mcse_yield = stats::sd(nre_yield) / sqrt(.N)),
            by = .(target_scenario, m, lambda_key, validation_n, effect, kappa)]
utils::write.csv(as.data.frame(yield), file.path(OUT, 'recorded-eligible-yield.csv'),
                 row.names = FALSE)

bounds <- DT[method == 'bounds' & scheduled == TRUE, {
  ok <- is.na(fail) & is.finite(bound_lo) & is.finite(bound_hi)
  included <- bound_lo[ok] <= rd_e[1L] & bound_hi[ok] >= rd_e[1L]
  ci_included <- bound_ci_lo[ok] <= rd_e[1L] & bound_ci_hi[ok] >= rd_e[1L]
  width <- bound_hi[ok] - bound_lo[ok]
  list(
    truth = rd_e[1L], set_inclusion = mean(included),
    set_inclusion_mcse = stats::sd(as.numeric(included)) / sqrt(sum(ok)),
    confidence_inclusion = mean(ci_included),
    mean_width = mean(width), width_mcse = stats::sd(width) / sqrt(sum(ok)),
    practically_uninformative = mean(width) > 0.20,
    convergence = sum(ok) / .N, n_used = sum(ok), n_attempted = .N
  )
}, by = .(target_scenario, m, lambda_key, lambda, validation_n, effect, kappa)]
utils::write.csv(as.data.frame(bounds), file.path(OUT, 'bounds-performance.csv'),
                 row.names = FALSE)

discrepancy <- unique(truth[, c('scenario', 'm', 'lambda_key', 'lambda',
                                'validation_n', 'effect', 'kappa',
                                'rd_e', 'rd_re', 'target_discrepancy')])
utils::write.csv(discrepancy, file.path(OUT, 'target-discrepancy.csv'),
                 row.names = FALSE)

make_contrast <- function(d, factor_name, low, high, by, label) {
  a <- d[d[[factor_name]] == low, , drop = FALSE]
  b <- d[d[[factor_name]] == high, , drop = FALSE]
  z <- merge(a, b, by = by, suffixes = c('_low', '_high'))
  if (!nrow(z)) return(data.frame())
  data.frame(
    z[, by, drop = FALSE], contrast = label,
    bias_difference = z$bias_high - z$bias_low,
    bias_difference_mcse = sqrt(z$bias_mcse_high^2 + z$bias_mcse_low^2),
    mse_difference = z$mse_high - z$mse_low,
    stringsAsFactors = FALSE
  )
}

perf_df <- as.data.frame(perf)
nv <- perf_df[perf_df$information_set == 'no_validation' &
                perf_df$validation_n == 100L &
                !(perf_df$method %in% c('mi_continuous_m50', 'mi_indicator_m50')), ]
lambda_contrast <- make_contrast(
  nv, 'lambda_key', 'lambda_log2', 'lambda_log4',
  c('m', 'effect', 'kappa', 'method', 'variant', 'target'),
  'lambda log(4) minus log(2)'
)
missing_contrast <- make_contrast(
  nv, 'm', 0.20, 0.50,
  c('lambda_key', 'effect', 'kappa', 'method', 'variant', 'target'),
  'missingness 0.50 minus 0.20'
)
vv <- perf_df[perf_df$information_set == 'validation', ]
validation_contrast <- make_contrast(
  vv, 'validation_n', 100L, 400L,
  c('m', 'lambda_key', 'effect', 'kappa', 'method', 'variant', 'target'),
  'validation 400 minus 100'
)
factor_contrasts <- data.table::rbindlist(
  list(lambda_contrast, missing_contrast, validation_contrast),
  fill = TRUE, use.names = TRUE
)
utils::write.csv(as.data.frame(factor_contrasts),
                 file.path(OUT, 'factor-contrasts.csv'), row.names = FALSE)

perf_df$method_id <- paste(perf_df$method, perf_df$variant, sep = ':')
pairwise <- merge(perf_df, perf_df,
                  by = c('target_scenario', 'information_set', 'target'),
                  suffixes = c('_a', '_b'))
pairwise <- pairwise[pairwise$method_id_a < pairwise$method_id_b, ]
if (nrow(pairwise)) {
  pairwise <- data.frame(
    target_scenario = pairwise$target_scenario,
    information_set = pairwise$information_set,
    target = pairwise$target,
    method_a = pairwise$method_id_a,
    method_b = pairwise$method_id_b,
    bias_b_minus_a = pairwise$bias_b - pairwise$bias_a,
    mse_b_minus_a = pairwise$mse_b - pairwise$mse_a
  )
}
utils::write.csv(pairwise, file.path(OUT, 'within-information-set-comparisons.csv'),
                 row.names = FALSE)

mi_check_one <- function(primary_method, check_method) {
  a <- DT[method == primary_method & variant == 'm20']
  b <- DT[method == check_method & variant == 'm50' & scheduled == TRUE]
  z <- merge(a, b, by = c('target_scenario', 'pair_rep'),
             suffixes = c('_m20', '_m50'))
  if (!nrow(z)) return(data.frame())
  data.table::as.data.table(z)[, {
    tv <- rd_e_m20[1L]
    b20 <- metric(perf_bias(est_m20[is.finite(est_m20)], tv))
    b50 <- metric(perf_bias(est_m50[is.finite(est_m50)], tv))
    c20 <- metric(perf_coverage(lo_m20, hi_m20, tv))
    c50 <- metric(perf_coverage(lo_m50, hi_m50, tv))
    list(
      bias_m20 = value(b20, 'est'), bias_m50 = value(b50, 'est'),
      bias_change = value(b50, 'est') - value(b20, 'est'),
      coverage_m20 = value(c20, 'est'), coverage_m50 = value(c50, 'est'),
      coverage_change = value(c50, 'est') - value(c20, 'est'), n = .N
    )
  }, by = .(target_scenario)]
}
mi_check <- data.table::rbindlist(list(
  transform(mi_check_one('mi_continuous', 'mi_continuous_m50'),
            imputation = 'continuous'),
  transform(mi_check_one('mi_indicator', 'mi_indicator_m50'),
            imputation = 'indicator')
), fill = TRUE)
utils::write.csv(as.data.frame(mi_check), file.path(OUT, 'mi-m20-m50-check.csv'),
                 row.names = FALSE)

extension <- unique(perf[needs_extension == TRUE,
                         .(target_scenario, method, variant, bias_mcse)])
utils::write.csv(as.data.frame(extension), file.path(OUT, 'extension-needed.csv'),
                 row.names = FALSE)

## The paired generator uses identical() on the complete no-validation view.
## No-validation estimators are then evaluated once and copied to all six
## paired rows, which is the strongest available bitwise output check.
decisive_ids <- scenarios$scenario[
  scenarios$m == 0.50 & scenarios$kappa == 1.10 &
    scenarios$effect == 'heterogeneous' &
    scenarios$lambda_key %in% c('lambda_0', 'lambda_log4')
]
decisive <- DT[target_scenario %in% decisive_ids]
observed_identity <- nrow(decisive) > 0 && all(decisive$obs_identity %in% TRUE)
nv_decisive <- decisive[information_set == 'no_validation' & scheduled == TRUE]
method_identity <- nrow(nv_decisive) > 0 && all(nv_decisive$nv_identity %in% TRUE)
identity <- data.frame(
  check = c('observed_data_bitwise_identity',
            'no_validation_method_output_bitwise_identity'),
  passed = c(observed_identity, method_identity),
  stringsAsFactors = FALSE
)
utils::write.csv(identity, file.path(OUT, 'identity-checks.csv'), row.names = FALSE)

controls <- perf[
  target_scenario %in% decisive_ids &
    method %in% c('oracle', 'two_phase_ipw')
]
control_failure <- !nrow(controls) || any(
  controls$convergence < 0.95 |
    controls$needs_extension |
    controls$bias_class == 'material', na.rm = TRUE
)
precision_ok <- is.finite(id_truth$mcse) && id_truth$mcse <= 0.001
material <- id_truth$ci95_lo > 0.010 || id_truth$ci95_hi < -0.010
equivalent <- id_truth$ci90_lo > -0.005 && id_truth$ci90_hi < 0.005

branch <- if (!observed_identity || !method_identity) {
  'UNINFORMATIVE: paired observed-data or no-validation output identity failed'
} else if (!precision_ok) {
  'UNINFORMATIVE: paired numerical MCSE exceeds 0.001'
} else if (control_failure) {
  'UNINFORMATIVE: an oracle or known-design implementation control failed'
} else if (material) {
  'MATERIAL: the 95% paired numerical interval lies wholly beyond plus or minus 0.010'
} else if (equivalent) {
  'NOT MATERIALLY DIFFERENT: the 90% paired numerical interval lies within plus or minus 0.005'
} else {
  'UNINFORMATIVE: the paired contrast lies between the equivalence and materiality regions'
}

decision <- data.frame(
  delta_id = id_truth$delta_id,
  mcse = id_truth$mcse,
  ci95_lo = id_truth$ci95_lo, ci95_hi = id_truth$ci95_hi,
  ci90_lo = id_truth$ci90_lo, ci90_hi = id_truth$ci90_hi,
  material_margin = 0.010, equivalence_margin = 0.005,
  observed_identity = observed_identity, method_identity = method_identity,
  control_failure = control_failure, branch = branch,
  stringsAsFactors = FALSE
)
utils::write.csv(decision, file.path(OUT, 'decision.csv'), row.names = FALSE)

cat('\n== ELG-01 paired identification analysis ==\n')
cat(sprintf('Delta_ID: %.6f; paired numerical MCSE: %.6g\n',
            id_truth$delta_id, id_truth$mcse))
cat(sprintf('95%% interval: [%.6f, %.6f]\n', id_truth$ci95_lo, id_truth$ci95_hi))
cat(sprintf('90%% interval: [%.6f, %.6f]\n', id_truth$ci90_lo, id_truth$ci90_hi))
cat(sprintf('Observed-data identity: %s; no-validation output identity: %s\n',
            observed_identity, method_identity))
cat(sprintf('Point-method rows: %d; minimum convergence: %.4f\n',
            nrow(perf), min(perf$convergence, na.rm = TRUE)))
cat(sprintf('Methods requiring the prespecified precision extension: %d\n',
            nrow(extension)))
cat(sprintf('\nDECISION BRANCH: %s\n', branch))
