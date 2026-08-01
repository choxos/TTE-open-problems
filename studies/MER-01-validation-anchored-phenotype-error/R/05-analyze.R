## MER-01: performance measures, simultaneous inference, and decisions.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
         else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))

OUT <- here('results')
raw_files <- sort(list.files(OUT, '^scenario-[0-9]+[.]rds$', recursive = TRUE,
                             full.names = TRUE))
if (!length(raw_files)) stop('no raw scenario files found')
res <- do.call(rbind, lapply(raw_files, readRDS))
scenarios <- build_scenarios()
truth <- readRDS(file.path(OUT, 'truth.rds'))
res <- merge(res, truth[, c('cell_id', 'contrast', 'truth', 'truth_mcse')],
             by = c('cell_id', 'contrast'), all.x = TRUE)
res <- merge(res, scenarios, by.x = 'cell_id', by.y = 'scenario', all.x = TRUE)
res <- res[!duplicated(res[, c('cell_id', 'rep_global', 'method', 'contrast')]), ]

safe_perf <- function(expr) {
  tryCatch(expr, error = function(e) list(est = NA_real_, mcse = NA_real_))
}

summarize_group <- function(d) {
  attempted <- nrow(d)
  ok <- is.finite(d$est) & is.finite(d$se)
  est <- d$est[ok]
  se <- d$se[ok]
  tv <- d$truth[1]
  lo <- d$lo[ok]
  hi <- d$hi[ok]
  if (!length(est)) {
    b <- es <- ms <- re <- mse <- cv <- bec <- rej <- list(est = NA_real_, mcse = NA_real_)
  } else {
    b <- safe_perf(perf_bias(est, tv))
    es <- safe_perf(perf_empse(est))
    ms <- safe_perf(perf_modse(se))
    re <- safe_perf(perf_relerror_modse(est, se))
    mse <- safe_perf(perf_mse(est, tv))
    cv <- safe_perf(perf_coverage(lo, hi, tv))
    bec <- safe_perf(perf_becoverage(est, se, tv))
    rej <- safe_perf(perf_rejection(lo, hi, 0))
  }
  conv <- safe_perf(perf_convergence(d$est, attempted))
  data.frame(
    cell_id = d$cell_id[1], method = d$method[1], contrast = d$contrast[1],
    truth = tv, bias = b$est, bias_mcse = b$mcse,
    abs_bias = abs(b$est), empse = es$est, empse_mcse = es$mcse,
    modse = ms$est, modse_mcse = ms$mcse,
    relerror_modse = re$est, relerror_modse_mcse = re$mcse,
    mse = mse$est, mse_mcse = mse$mcse,
    coverage = cv$est, coverage_mcse = cv$mcse,
    becoverage = bec$est, becoverage_mcse = bec$mcse,
    rejection = rej$est, rejection_mcse = rej$mcse,
    convergence = conv$est, convergence_mcse = conv$mcse,
    failure_noncoverage = mean(ok & d$lo <= tv & d$hi >= tv),
    mean_width = mean(d$hi[ok] - d$lo[ok]),
    median_ess_0 = stats::median(d$ess_0[ok], na.rm = TRUE),
    median_ess_1 = stats::median(d$ess_1[ok], na.rm = TRUE),
    median_weight = stats::median(d$median_weight[ok], na.rm = TRUE),
    p99_weight = stats::median(d$p99_weight[ok], na.rm = TRUE),
    mean_adherence_0 = mean(d$adherence_0[ok], na.rm = TRUE),
    mean_adherence_1 = mean(d$adherence_1[ok], na.rm = TRUE),
    mean_censor_change_L = mean(d$censor_change_L[ok], na.rm = TRUE),
    n_used = sum(ok), n_attempted = attempted,
    stringsAsFactors = FALSE)
}

eligible <- res$eligible %in% TRUE
perf <- do.call(rbind, lapply(split(res[eligible, ],
                                    interaction(res$cell_id[eligible],
                                                res$method[eligible],
                                                res$contrast[eligible], drop = TRUE)),
                              summarize_group))
perf <- merge(perf, scenarios, by.x = 'cell_id', by.y = 'scenario', all.x = TRUE)

## Critique fix: all decision-bearing signed-bias intervals use a replicate-level
## max-t multiplier and the familywise alpha is divided across three looks.
max_t_bias <- function(d, alpha, B = MULTIPLIER_DRAWS) {
  d$key <- interaction(d$cell_id, d$method, d$contrast, drop = TRUE)
  groups <- split(d, d$key)
  ids <- sort(unique(d$rep_global))
  X <- matrix(NA_real_, length(ids), length(groups),
              dimnames = list(ids, names(groups)))
  for (j in seq_along(groups)) {
    g <- groups[[j]]
    m <- match(g$rep_global, ids)
    X[m, j] <- g$est - g$truth
  }
  n <- colSums(is.finite(X))
  mu <- colMeans(X, na.rm = TRUE)
  s <- apply(X, 2, stats::sd, na.rm = TRUE)
  se <- s / sqrt(n)
  Z <- sweep(X, 2, mu, '-')
  Z <- sweep(Z, 2, s * sqrt(n), '/')
  Z[!is.finite(Z)] <- 0
  set.seed(MASTER_SEED + 800001L)
  G <- matrix(stats::rnorm(B * nrow(Z)), B, nrow(Z))
  boot <- G %*% Z
  critical <- unname(stats::quantile(apply(abs(boot), 1, max), 1 - alpha,
                                      names = FALSE, type = 8))
  data.frame(key = names(groups), bias_lo = mu - critical * se,
             bias_hi = mu + critical * se,
             max_t_critical = critical, stringsAsFactors = FALSE)
}

decision_raw <- res[eligible & res$contrast == 'dynamic' &
                      res$method %in% c('first_order', 'rich_history',
                                        'exact_filtered', 'corrected_mi',
                                        'oracle_complete'), ]
current_look <- max(decision_raw$look)
alpha_look <- SIM_ALPHA / SIM_LOOKS
bias_ci <- max_t_bias(decision_raw, alpha_look)
perf$key <- interaction(perf$cell_id, perf$method, perf$contrast, drop = TRUE)
perf <- merge(perf, bias_ci, by = 'key', all.x = TRUE)

clopper <- function(success, total, alpha) {
  if (!is.finite(total) || total <= 0) return(c(NA_real_, NA_real_))
  unname(stats::binom.test(success, total, conf.level = 1 - alpha)$conf.int)
}

K <- nrow(perf[perf$contrast == 'dynamic' & perf$method %in%
                 c('first_order', 'rich_history', 'exact_filtered',
                   'corrected_mi', 'oracle_complete'), ])
binom_alpha <- alpha_look / max(1L, K)
perf$coverage_lo <- perf$coverage_hi <- NA_real_
perf$convergence_lo <- perf$convergence_hi <- NA_real_
for (i in seq_len(nrow(perf))) {
  if (perf$contrast[i] != 'dynamic') next
  d <- res[eligible & res$cell_id == perf$cell_id[i] &
             res$method == perf$method[i] & res$contrast == perf$contrast[i], ]
  ok <- is.finite(d$est) & is.finite(d$se)
  covered <- ok & d$lo <= d$truth & d$hi >= d$truth
  ci <- clopper(sum(covered[ok]), sum(ok), binom_alpha)
  perf$coverage_lo[i] <- ci[1]
  perf$coverage_hi[i] <- ci[2]
  ci <- clopper(sum(ok), length(ok), binom_alpha)
  perf$convergence_lo[i] <- ci[1]
  perf$convergence_hi[i] <- ci[2]
}
utils::write.csv(perf, file.path(OUT, 'performance.csv'), row.names = FALSE)

## Paired A and L nonadditivity. The four estimates were generated inside one
## replicate from a common latent cohort and common error uniforms.
int_raw <- decision_raw[decision_raw$method %in% c('rich_history', 'exact_filtered') &
                          is.finite(decision_raw$interaction_est), ]
interaction <- do.call(rbind, lapply(split(int_raw,
                                           interaction(int_raw$cell_id,
                                                       int_raw$method, drop = TRUE)),
                                     function(d) {
  x <- d$interaction_est
  bal <- d$est - d$truth
  n <- length(x)
  point <- mean(x)
  composite <- abs(point) - 0.25 * abs(mean(bal))
  set.seed(MASTER_SEED + 800002L + d$cell_id[1])
  G <- matrix(stats::rnorm(MULTIPLIER_DRAWS * n), MULTIPLIER_DRAWS, n)
  xb <- point + drop(G %*% (x - point)) / n
  mb <- mean(bal) + drop(G %*% (bal - mean(bal))) / n
  cb <- abs(xb) - 0.25 * abs(mb)
  a <- alpha_look / max(1L, 2L * length(unique(int_raw$cell_id)))
  data.frame(
    cell_id = d$cell_id[1], method = d$method[1], interaction = point,
    interaction_lo = unname(stats::quantile(xb, a / 2)),
    interaction_hi = unname(stats::quantile(xb, 1 - a / 2)),
    composite = composite,
    composite_lo = unname(stats::quantile(cb, a / 2)),
    composite_hi = unname(stats::quantile(cb, 1 - a / 2)),
    stringsAsFactors = FALSE)
}))
interaction <- merge(interaction, scenarios, by.x = 'cell_id', by.y = 'scenario')
utils::write.csv(interaction, file.path(OUT, 'interaction.csv'), row.names = FALSE)

## Paired correction versus rich-history criteria for the validation grid.
correction_raw <- merge(
  res[eligible & res$method == 'corrected_mi' & res$contrast == 'dynamic',
      c('cell_id', 'rep_global', 'est', 'truth')],
  res[eligible & res$method == 'rich_history' & res$contrast == 'dynamic',
      c('cell_id', 'rep_global', 'est')],
  by = c('cell_id', 'rep_global'), suffixes = c('_corrected', '_rich'))
correction_raw <- correction_raw[is.finite(correction_raw$est_corrected) &
                                   is.finite(correction_raw$est_rich), ]
correction_metrics <- do.call(rbind, lapply(split(correction_raw,
                                                  correction_raw$cell_id),
                                            function(d) {
  ec <- d$est_corrected - d$truth
  er <- d$est_rich - d$truth
  point_bias <- abs(mean(ec)) - 0.5 * abs(mean(er))
  point_mse <- mean(ec^2) - 1.25 * mean(er^2)
  n <- nrow(d)
  set.seed(MASTER_SEED + 810000L + d$cell_id[1])
  G <- matrix(stats::rnorm(MULTIPLIER_DRAWS * n), MULTIPLIER_DRAWS, n)
  bc <- mean(ec) + drop(G %*% (ec - mean(ec))) / n
  br <- mean(er) + drop(G %*% (er - mean(er))) / n
  bg <- abs(bc) - 0.5 * abs(br)
  mg <- point_mse + drop(G %*% ((ec^2 - 1.25 * er^2) - point_mse)) / n
  a <- alpha_look / max(1L, 2L * length(unique(correction_raw$cell_id)))
  data.frame(cell_id = d$cell_id[1], bias_gain = point_bias,
             bias_gain_lo = unname(stats::quantile(bg, a / 2)),
             bias_gain_hi = unname(stats::quantile(bg, 1 - a / 2)),
             mse_gain = point_mse,
             mse_gain_lo = unname(stats::quantile(mg, a / 2)),
             mse_gain_hi = unname(stats::quantile(mg, 1 - a / 2)),
             stringsAsFactors = FALSE)
}))
correction_metrics <- merge(correction_metrics, scenarios,
                            by.x = 'cell_id', by.y = 'scenario')

getrow <- function(cell, method) {
  z <- perf[perf$cell_id == cell & perf$method == method &
              perf$contrast == 'dynamic', ]
  if (nrow(z)) z[1, ] else NULL
}

correction_metrics$qualifies <- FALSE
for (i in seq_len(nrow(correction_metrics))) {
  z <- getrow(correction_metrics$cell_id[i], 'corrected_mi')
  if (is.null(z)) next
  correction_metrics$qualifies[i] <-
    correction_metrics$bias_gain_hi[i] < 0 &&
    z$bias_lo > -0.01 && z$bias_hi < 0.01 &&
    z$coverage_lo > 0.925 && z$coverage_hi < 0.975 &&
    correction_metrics$mse_gain_hi[i] < 0 &&
    z$convergence_lo >= 0.95
}

large <- res[res$eligible & res$method == 'corrected_mi_4M' &
               res$contrast == 'dynamic' & is.finite(res$est), ]
large_flag <- aggregate(est ~ cell_id, large, length)
names(large_flag)[2] <- 'large_M_n'
correction_metrics <- merge(correction_metrics, large_flag, by = 'cell_id', all.x = TRUE)
correction_metrics$large_M_n[is.na(correction_metrics$large_M_n)] <- 0L
correction_metrics$large_M_check <- correction_metrics$large_M_n >= 2L
utils::write.csv(correction_metrics, file.path(OUT, 'validation-size.csv'),
                 row.names = FALSE)

## Separate outcome-error identity check.
outcome <- res[res$block == 'outcome_component' & res$contrast == 'dynamic' &
                 res$method %in% c('rich_history', 'exact_filtered') &
                 is.finite(res$est) & is.finite(res$outcome_base_est), ]
outcome_summary <- if (nrow(outcome)) do.call(rbind, lapply(split(outcome,
  interaction(outcome$cell_id, outcome$method, drop = TRUE)), function(d) {
    attenuation <- 1 - 2 * (1 - d$accuracy[1])
    data.frame(cell_id = d$cell_id[1], method = d$method[1],
               accuracy = d$accuracy[1], mean_with_error = mean(d$est),
               mean_without_error = mean(d$outcome_base_est),
               analytic_target = attenuation * mean(d$outcome_base_est),
               identity_difference = mean(d$est - attenuation * d$outcome_base_est),
               stringsAsFactors = FALSE)
  })) else data.frame()
utils::write.csv(outcome_summary, file.path(OUT, 'outcome-error.csv'), row.names = FALSE)

## Validity gates and the two six-of-eight branches.
inside <- function(lo, hi, bound) is.finite(lo) && is.finite(hi) &&
  lo > -bound && hi < bound
coverage_ok <- function(z) is.finite(z$coverage_lo) &&
  z$coverage_lo > 0.925 && z$coverage_hi < 0.975
conv_ok <- function(z) is.finite(z$convergence_lo) && z$convergence_lo >= 0.95

controls <- scenarios$scenario[scenarios$block == 'control']
core_controls <- scenarios$scenario[scenarios$block == 'control' &
                                      scenarios$specification == 'core']
stress_controls <- setdiff(controls, core_controls)
gates <- logical(0)
for (cell in controls) {
  for (method in c('exact_filtered', 'oracle_complete')) {
    z <- getrow(cell, method)
    gates <- c(gates, !is.null(z) && inside(z$bias_lo, z$bias_hi, 0.005) &&
                 coverage_ok(z) && conv_ok(z))
  }
}
for (cell in core_controls) {
  for (method in c('first_order', 'rich_history')) {
    z <- getrow(cell, method)
    gates <- c(gates, !is.null(z) && inside(z$bias_lo, z$bias_hi, 0.005) &&
                 coverage_ok(z) && conv_ok(z))
  }
}
for (cell in stress_controls) {
  z <- getrow(cell, 'rich_history')
  gates <- c(gates, !is.null(z) && inside(z$bias_lo, z$bias_hi, 0.005) &&
               coverage_ok(z) && conv_ok(z))
}

decisive_cells <- scenarios$scenario[scenarios$decisive]
for (cell in decisive_cells) {
  z <- getrow(cell, 'oracle_complete')
  gates <- c(gates, !is.null(z) && inside(z$bias_lo, z$bias_hi, 0.01) &&
               coverage_ok(z) && conv_ok(z) &&
               z$median_ess_0 > 200 && z$median_ess_1 > 200)
}
validity_pass <- length(gates) > 0L && all(gates)

cell_decision <- data.frame(cell_id = decisive_cells,
                            supports_real = FALSE, supports_not_real = FALSE,
                            interaction_real = FALSE, stringsAsFactors = FALSE)
for (i in seq_along(decisive_cells)) {
  cell <- decisive_cells[i]
  e <- getrow(cell, 'exact_filtered')
  r <- getrow(cell, 'rich_history')
  ix <- interaction[interaction$cell_id == cell &
                      interaction$method == 'exact_filtered', ]
  if (is.null(e) || is.null(r) || !nrow(ix)) next
  outside01 <- function(z) z$bias_lo > 0.01 || z$bias_hi < -0.01
  cell_decision$supports_real[i] <-
    abs(e$bias) >= 0.02 && abs(r$bias) >= 0.02 &&
    outside01(e) && outside01(r) &&
    e$coverage <= 0.90 && r$coverage <= 0.90 &&
    e$coverage_hi < 0.925 && r$coverage_hi < 0.925
  cell_decision$interaction_real[i] <-
    (ix$interaction_lo > 0.005 || ix$interaction_hi < -0.005) &&
    ix$composite_lo > 0
  cell_decision$supports_not_real[i] <-
    inside(e$bias_lo, e$bias_hi, 0.01) &&
    inside(r$bias_lo, r$bias_hi, 0.01) &&
    coverage_ok(e) && coverage_ok(r) &&
    inside(ix$interaction_lo, ix$interaction_hi, 0.005) &&
    ix$composite_hi < 0
}
utils::write.csv(cell_decision, file.path(OUT, 'decision-metrics.csv'),
                 row.names = FALSE)

key_convergence <- perf$method %in% c('rich_history', 'exact_filtered',
                                       'oracle_complete') &
  perf$cell_id %in% decisive_cells & perf$contrast == 'dynamic'
convergence_pass <- all(perf$convergence[key_convergence] >= 0.95, na.rm = FALSE)
real_count <- sum(cell_decision$supports_real)
interaction_count <- sum(cell_decision$interaction_real)
not_real_count <- sum(cell_decision$supports_not_real)

if (!validity_pass || !convergence_pass) {
  branch <- 'PRIMARY STUDY UNINFORMATIVE: A REQUIRED VALIDITY OR 0.95 CONVERGENCE GATE FAILED'
} else if (real_count >= 6L && interaction_count >= 4L) {
  branch <- 'STUDIED INTERNAL-VALIDATION PART OF MER-01 IS REAL'
} else if (not_real_count >= 6L) {
  branch <- 'STUDIED INTERNAL-VALIDATION PART OF MER-01 IS NOT REAL'
} else if (current_look < length(N_REP_LOOKS)) {
  branch <- sprintf('PRIMARY STUDY UNINFORMATIVE AT LOOK %d: EXTEND THE MATCHED FAMILY',
                    current_look)
} else {
  branch <- 'PRIMARY STUDY UNINFORMATIVE AT THE SCALED 100-REPLICATE MAXIMUM'
}

benchmark_rows <- correction_metrics[!is.na(correction_metrics$benchmark), ]
robust_sizes <- integer(0)
for (v in c(100L, 250L, 500L, 1000L)) {
  z <- benchmark_rows[benchmark_rows$validation_n == v, ]
  if (nrow(z) == 10L && all(z$qualifies) && all(z$large_M_check))
    robust_sizes <- c(robust_sizes, v)
}
validation_result <- if (length(robust_sizes))
  paste('smallest robust validation size:', min(robust_sizes)) else
  'no robust validation size up to 1000 was identified'

cat('\n== MER-01 estimator performance ==\n')
cat(sprintf('  accumulated look: %d; target replicates: %d\n',
            current_look, N_REP_LOOKS[current_look]))
cat(sprintf('  validity gates passed: %s\n', validity_pass))
cat(sprintf('  decisive real cells: %d/8; required at least 6/8\n', real_count))
cat(sprintf('  decisive interaction cells: %d/8; required at least 4/8\n',
            interaction_count))
cat(sprintf('  decisive not-real cells: %d/8; required at least 6/8\n',
            not_real_count))
cat('  real thresholds: |bias| >= 0.02, bias CI outside [-0.01, 0.01], coverage <= 0.90, coverage upper < 0.925\n')
cat('  interaction thresholds: CI outside [-0.005, 0.005] and composite CI above 0\n')
cat('  not-real thresholds: bias CI inside [-0.01, 0.01], coverage CI inside [0.925, 0.975], interaction CI inside [-0.005, 0.005]\n')
cat('  correction result: ', validation_result, '\n', sep = '')
cat('Decision branch: ', branch, '\n', sep = '')
writeLines(c(paste('Decision branch:', branch),
             paste('Correction result:', validation_result)),
           file.path(OUT, 'decision.txt'))
