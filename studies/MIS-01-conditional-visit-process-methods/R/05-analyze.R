## Study MIS-01: performance, paired contrasts, diagnostics, and decision.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1])))) else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))

OUT <- here('results')
raw_files <- sort(list.files(file.path(OUT, 'scenario-runs'),
                             pattern = '^scenario-[0-9]+[.]rds$',
                             recursive = TRUE, full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, 'truth.rds'))
scenarios <- build_scenarios()
res <- merge(res, scenarios, by = 'sid', all.x = TRUE, suffixes = c('', '_scenario'))
res <- merge(res, truth[, c('sid', 'estimand', 'truth', 'risk1', 'risk0')],
             by = c('sid', 'estimand'), all.x = TRUE,
             suffixes = c('', '_truth'))

metric <- function(expr) {
  tryCatch(expr, error = function(e) list(est = NA_real_, mcse = NA_real_))
}

perf <- do.call(rbind, lapply(split(res, list(res$sid, res$method, res$variant, res$estimand), drop = TRUE), function(d) {
  valid <- is.na(d$fail) & is.finite(d$est) & is.finite(d$se)
  est <- d$est[valid]; se <- d$se[valid]
  lo <- d$lo[valid]; hi <- d$hi[valid]; tv <- d$truth[1]
  b <- metric(perf_bias(est, tv))
  es <- metric(perf_empse(est))
  ms <- metric(perf_modse(se))
  re <- metric(perf_relerror_modse(est, se))
  mse <- metric(perf_mse(est, tv))
  cv <- metric(perf_coverage(lo, hi, tv))
  bec <- metric(perf_becoverage(est, lo, hi))
  rej <- metric(perf_rejection(lo, hi, 0))
  cg <- metric(perf_convergence(ifelse(valid, d$est, NA_real_), nrow(d)))
  data.frame(
    sid = d$sid[1], method = d$method[1], variant = d$variant[1],
    estimand = d$estimand[1], panel = d$panel[1], profile_id = d$profile_id[1],
    beta_AL = d$beta_AL[1], beta_YL = d$beta_YL[1],
    beta_YAL = d$beta_YAL[1], beta_LL = d$beta_LL[1],
    gamma_L = d$gamma_L[1], gamma_A = d$gamma_A[1], obs_target = d$obs_target[1],
    truth = tv, bias = b$est, bias_mcse = b$mcse,
    abs_bias = abs(b$est), empse = es$est, empse_mcse = es$mcse,
    modse = ms$est, modse_mcse = ms$mcse,
    relerror_modse = re$est, relerror_modse_mcse = re$mcse,
    mse = mse$est, mse_mcse = mse$mcse,
    coverage = cv$est, coverage_mcse = cv$mcse,
    bias_eliminated_coverage = bec$est, bias_eliminated_coverage_mcse = bec$mcse,
    rejection = rej$est, rejection_mcse = rej$mcse,
    convergence = cg$est, convergence_mcse = cg$mcse,
    procedural_success = mean(valid & d$lo <= tv & d$hi >= tv),
    n_used = sum(valid), n_attempted = nrow(d),
    stringsAsFactors = FALSE
  )
}))
rownames(perf) <- NULL
utils::write.csv(perf, file.path(OUT, 'performance.csv'), row.names = FALSE)

failures <- as.data.frame(table(method = res$method, variant = res$variant,
                                stage = ifelse(is.na(res$fail_stage), 'none', res$fail_stage),
                                fail = ifelse(is.na(res$fail), 'none', res$fail)))
failures <- failures[failures$Freq > 0, ]
utils::write.csv(failures, file.path(OUT, 'failure-rates.csv'), row.names = FALSE)

runtime <- stats::aggregate(cbind(runtime_sec, memory_mb) ~ method + variant,
                            data = res, FUN = function(x) c(median = stats::median(x, na.rm = TRUE),
                                                           p90 = unname(stats::quantile(x, 0.90, na.rm = TRUE)),
                                                           p99 = unname(stats::quantile(x, 0.99, na.rm = TRUE))))
utils::write.csv(runtime, file.path(OUT, 'runtime.csv'), row.names = FALSE)

diagnostics <- stats::aggregate(
  cbind(obs_brier, obs_cal_intercept, obs_cal_slope, latent_brier,
        weight_max, weight_p99, weight_cv, weight_ess_fraction, max_gap,
        gamma_l_hat, gamma_l_se, gamma_boundary, profile_drop) ~
    sid + method + variant,
  data = res, FUN = function(x) mean(x, na.rm = TRUE), na.action = na.pass)
utils::write.csv(diagnostics, file.path(OUT, 'diagnostics.csv'), row.names = FALSE)

beta_interval <- function(x, n, alpha = 0.05) {
  c(low = if (x == 0) 0 else stats::qbeta(alpha / 2, x, n - x + 1),
    high = if (x == n) 1 else stats::qbeta(1 - alpha / 2, x + 1, n - x))
}
one_sided_lower <- function(x, n, alpha = 0.025) {
  if (x == 0) 0 else stats::qbeta(alpha, x, n - x + 1)
}

gates <- perf[perf$estimand == 'rd24', ]
gates$abs_bias_lower <- pmax(0, gates$abs_bias - 1.96 * gates$bias_mcse)
gates$abs_bias_upper <- gates$abs_bias + 1.96 * gates$bias_mcse
gates$coverage_low <- gates$coverage_high <- NA_real_
gates$convergence_lower <- NA_real_
for (i in seq_len(nrow(gates))) {
  nc <- gates$n_used[i]
  covered <- round(gates$coverage[i] * nc)
  ci <- if (nc > 0) beta_interval(covered, nc) else c(NA, NA)
  gates$coverage_low[i] <- ci[1]
  gates$coverage_high[i] <- ci[2]
  converged <- gates$n_used[i]
  gates$convergence_lower[i] <- one_sided_lower(converged, gates$n_attempted[i])
}
gates$oracle_valid <- with(gates,
  method == 'oracle' & abs_bias_upper <= DECISION$oracle_abs_bias_upper &
  coverage_low >= DECISION$oracle_coverage_low &
  coverage_high <= DECISION$oracle_coverage_high &
  convergence_lower >= DECISION$oracle_convergence_lower)
gates$adequate <- with(gates,
  abs_bias_upper <= DECISION$adequate_abs_bias_upper &
  coverage_low >= DECISION$adequate_coverage_low &
  coverage_high <= DECISION$adequate_coverage_high &
  convergence_lower >= DECISION$adequate_convergence_lower)
gates$material <- with(gates,
  abs_bias_lower >= DECISION$material_abs_bias_lower |
  coverage_high <= DECISION$material_coverage_upper)
utils::write.csv(gates, file.path(OUT, 'decision-gates.csv'), row.names = FALSE)

confirm <- scenarios[scenarios$panel == 'confirmatory', ]
pair_index <- unique(confirm[, c('profile_id', 'beta_AL', 'beta_YAL', 'gamma_A', 'obs_target')])
pair_index$pair_id <- seq_len(nrow(pair_index))
pairs <- merge(pair_index, confirm[confirm$gamma_L == 0, c('sid', 'profile_id', 'gamma_A', 'obs_target')],
               by = c('profile_id', 'gamma_A', 'obs_target'))
names(pairs)[names(pairs) == 'sid'] <- 'sid_noninformative'
pairs <- merge(pairs, confirm[confirm$gamma_L == 1.386294, c('sid', 'profile_id', 'gamma_A', 'obs_target')],
               by = c('profile_id', 'gamma_A', 'obs_target'))
names(pairs)[names(pairs) == 'sid'] <- 'sid_informative'

paired_abs_bias <- function(method, variant, s0, s1) {
  a <- res[res$sid == s0 & res$method == method & res$variant == variant & res$estimand == 'rd24',
           c('rep_id', 'est', 'truth', 'fail')]
  b <- res[res$sid == s1 & res$method == method & res$variant == variant & res$estimand == 'rd24',
           c('rep_id', 'est', 'truth', 'fail')]
  z <- merge(a, b, by = 'rep_id', suffixes = c('0', '1'))
  ok <- is.na(z$fail0) & is.na(z$fail1) & is.finite(z$est0) & is.finite(z$est1)
  z <- z[ok, ]
  if (nrow(z) < 2L) return(c(change = NA, low = NA, high = NA, n = nrow(z)))
  e0 <- z$est0 - z$truth0; e1 <- z$est1 - z$truth1
  b0 <- mean(e0); b1 <- mean(e1)
  se0 <- stats::sd(e0) / sqrt(nrow(z)); se1 <- stats::sd(e1) / sqrt(nrow(z))
  change <- abs(b1) - abs(b0)
  if (abs(b0) >= 2 * se0 && abs(b1) >= 2 * se1) {
    delta <- sign(b1) * e1 - sign(b0) * e0
    se <- stats::sd(delta) / sqrt(nrow(z))
    return(c(change = change, low = change - 1.96 * se,
             high = change + 1.96 * se, n = nrow(z)))
  }
  ## Critique fix: near zero, simultaneous signed-bias intervals are projected
  ## through the absolute-value contrast instead of using absolute errors.
  zsim <- stats::qnorm(0.99375)
  range_abs <- function(b, se) {
    lo <- b - zsim * se; hi <- b + zsim * se
    c(min = if (lo <= 0 && hi >= 0) 0 else min(abs(lo), abs(hi)),
      max = max(abs(lo), abs(hi)))
  }
  r0 <- range_abs(b0, se0); r1 <- range_abs(b1, se1)
  c(change = change, low = r1['min'] - r0['max'],
    high = r1['max'] - r0['min'], n = nrow(z))
}

matched <- do.call(rbind, lapply(seq_len(nrow(pairs)), function(i) {
  do.call(rbind, lapply(METHODS, function(m) {
    z <- paired_abs_bias(m, 'compatible', pairs$sid_noninformative[i], pairs$sid_informative[i])
    data.frame(pairs[i, ], method = m, change_abs_bias = z['change'],
               change_low = z['low'], change_high = z['high'], n_pair = z['n'])
  }))
}))
rownames(matched) <- NULL
utils::write.csv(matched, file.path(OUT, 'matched-pairs.csv'), row.names = FALSE)

oracle <- gates[gates$method == 'oracle' & gates$variant == 'compatible' & gates$panel == 'confirmatory', ]
ov <- setNames(oracle$oracle_valid, oracle$sid)
pairs$oracle_eligible <- ov[as.character(pairs$sid_noninformative)] & ov[as.character(pairs$sid_informative)]
eligible_pairs <- sum(pairs$oracle_eligible, na.rm = TRUE)

informative <- gates[gates$panel == 'confirmatory' & gates$gamma_L == 1.386294 &
                     gates$variant == 'compatible', ]
informative <- merge(informative, pairs[, c('sid_informative', 'oracle_eligible')],
                     by.x = 'sid', by.y = 'sid_informative', all.x = TRUE)
locf_bad <- informative[informative$method == 'locf' & informative$oracle_eligible & informative$material, ]
locf_bad_count <- nrow(locf_bad)
locf_bad_profiles <- length(unique(locf_bad$profile_id))
locf_null_al <- sum(locf_bad$beta_AL == 0)
locf_null_yal <- sum(locf_bad$beta_YAL == 0)
locf_pair <- matched[matched$method == 'locf' & matched$pair_id %in% pairs$pair_id[pairs$oracle_eligible] &
                     matched$change_low >= DECISION$paired_abs_bias_lower, ]

aware_summary <- do.call(rbind, lapply(VISIT_AWARE, function(m) {
  x <- informative[informative$method == m & informative$oracle_eligible & informative$adequate, ]
  data.frame(method = m, adequate_count = nrow(x), profiles = length(unique(x$profile_id)),
             passes = nrow(x) >= DECISION$aware_adequate_count &&
               length(unique(x$profile_id)) >= DECISION$aware_adequate_profiles)
}))
utils::write.csv(aware_summary, file.path(OUT, 'visit-aware-adequacy.csv'), row.names = FALSE)

material_branch <- eligible_pairs >= DECISION$minimum_oracle_pairs &&
  locf_bad_count >= DECISION$material_count &&
  locf_bad_profiles >= DECISION$material_profiles &&
  locf_null_al >= DECISION$material_null_al &&
  locf_null_yal >= DECISION$material_null_yal &&
  nrow(locf_pair) >= DECISION$paired_material_count &&
  length(unique(locf_pair$profile_id)) >= DECISION$paired_material_profiles

negative_method <- function(m) {
  x <- informative[informative$method == m & informative$oracle_eligible, ]
  adequate <- x[x$adequate, ]
  mp <- matched[matched$method == m & matched$pair_id %in% pairs$pair_id[pairs$oracle_eligible], ]
  nrow(adequate) >= DECISION$negative_count &&
    length(unique(adequate$profile_id)) == 16L &&
    sum(mp$change_high < DECISION$negative_pair_upper, na.rm = TRUE) >= DECISION$negative_count &&
    sum(x$material, na.rm = TRUE) <= DECISION$negative_material_max
}
negative_branch <- eligible_pairs >= DECISION$minimum_oracle_pairs &&
  negative_method('locf') && negative_method('complete_record')
valid_generated <- tapply(res$dgm_ok, res$sid, function(x) length(unique(which(x))))
resource_invalid <- N_REP < DECISION$minimum_valid_datasets || any(valid_generated < DECISION$minimum_valid_datasets)
branch <- if (resource_invalid) 'UNINFORMATIVE: fewer than 900 valid generated data sets remain in at least one confirmatory environment' else if (material_branch) 'PROBLEM IS REAL WITHIN THE PRESPECIFIED GRIDDED ENVELOPE' else if (negative_branch) 'PROBLEM IS NOT REAL WITHIN THE NULL-TO-WEAK GRIDDED ENVELOPE' else 'UNINFORMATIVE: neither substantive branch meets every uncertainty-confirmed threshold'

decision <- data.frame(
  branch = branch, eligible_oracle_pairs = eligible_pairs,
  locf_material_scenarios = locf_bad_count, locf_material_profiles = locf_bad_profiles,
  locf_material_beta_AL_zero = locf_null_al,
  locf_material_beta_YAL_zero = locf_null_yal,
  locf_paired_deterioration = nrow(locf_pair),
  material_branch = material_branch, negative_branch = negative_branch,
  scaled_run_forces_uninformative = resource_invalid,
  stringsAsFactors = FALSE
)
utils::write.csv(decision, file.path(OUT, 'decision.csv'), row.names = FALSE)

cat('\n== co-primary performance ==\n')
cat(sprintf('minimum conditional coverage %.3f; minimum convergence %.3f\n',
            min(perf$coverage, na.rm = TRUE), min(perf$convergence, na.rm = TRUE)))
cat(sprintf('oracle-valid confirmatory pairs: %d; required: %d\n',
            eligible_pairs, DECISION$minimum_oracle_pairs))
cat(sprintf('LOCF material informative scenarios: %d; required: %d\n',
            locf_bad_count, DECISION$material_count))
cat(sprintf('LOCF paired absolute-bias deterioration: %d; required: %d at lower bound %.3f\n',
            nrow(locf_pair), DECISION$paired_material_count,
            DECISION$paired_abs_bias_lower))
cat(sprintf('visit-aware methods meeting the 48-scenario and 12-profile adequacy gate: %s\n',
            paste(aware_summary$method[aware_summary$passes], collapse = ', ')))
cat(sprintf('Decision branch under the protocol thresholds: %s\n', branch))
