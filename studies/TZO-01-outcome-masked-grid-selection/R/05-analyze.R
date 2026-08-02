## Study TZO-01: performance measures and cell-specific decision rules.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))
suppressPackageStartupMessages(library(mvtnorm))

OUT <- here('results')
raw_files <- sort(list.files(file.path(OUT, 'raw'), '^scenario-.*\\.rds$',
                             full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, 'truth.rds'))

truth_key <- truth[, c(
  'cell', 'delta', 'rd_full', 'rd_full_mcse', 'rd_panel', 'rd_panel_mcse',
  'rd_panel_oracle', 'rd_panel_oracle_mcse', 'approximation_error',
  'approximation_error_mcse', 'delta_g', 'delta_g_mcse', 'precision_met'
)]
res <- merge(res, truth_key, by.x = c('cell', 'grid'),
             by.y = c('cell', 'delta'), all.x = TRUE)
res$truth_target <- ifelse(
  res$method == 'panel-oracle', res$rd_panel_oracle,
  ifelse(res$method == 'full-history', res$rd_full, res$rd_panel)
)
res$method_id <- ifelse(
  res$method %in% c('panel', 'panel-cap20', 'panel-p0199', 'panel-oracle'),
  paste0(res$method, '-', res$grid), res$method
)

safe_metric <- function(expression) {
  tryCatch(expression, error = function(e) list(est = NA_real_, mcse = NA_real_))
}

performance <- do.call(rbind, lapply(
  split(res, list(res$cell, res$method_id), drop = TRUE),
  function(d) {
    ok <- is.na(d$fail) & is.finite(d$est) & is.finite(d$se) &
      is.finite(d$truth_target)
    estimate <- d$est[ok]
    se <- d$se[ok]
    target <- d$truth_target[ok]
    full <- d$rd_full[ok]
    error <- estimate - target
    lo_error <- estimate - 1.96 * se - target
    hi_error <- estimate + 1.96 * se - target
    bias <- safe_metric(perf_bias(error, 0))
    empse <- safe_metric(perf_empse(estimate))
    modse <- safe_metric(perf_modse(se))
    relative_se <- safe_metric(perf_relerror_modse(estimate, se))
    mse <- safe_metric(perf_mse(error, 0))
    coverage <- safe_metric(perf_coverage(lo_error, hi_error, 0))
    becoverage <- safe_metric(perf_becoverage(error, lo_error, hi_error))
    rejection <- safe_metric(perf_rejection(estimate - 1.96 * se,
                                             estimate + 1.96 * se, 0))
    approximation_coverage <- safe_metric(perf_coverage(
      estimate - 1.96 * se - full,
      estimate + 1.96 * se - full,
      0
    ))
    convergence <- safe_metric(perf_convergence(
      ifelse(ok, d$est, NA_real_), nrow(d)
    ))
    mean_target <- if (length(target)) mean(target) else NA_real_
    data.frame(
      cell = d$cell[1L], method = d$method[1L], method_id = d$method_id[1L],
      grid = if (all(is.na(d$grid))) NA_integer_ else d$grid[1L],
      profile = d$profile[1L], G = d$G[1L],
      visit_key = d$visit_key[1L], pressure_key = d$pressure_key[1L],
      truth_target = mean_target, rd_full = d$rd_full[1L],
      bias = bias$est, bias_mcse = bias$mcse,
      absolute_bias = abs(bias$est),
      relative_bias = if (is.finite(mean_target) && abs(mean_target) > 1e-10)
        bias$est / mean_target else NA_real_,
      empse = empse$est, empse_mcse = empse$mcse,
      modse = modse$est, modse_mcse = modse$mcse,
      relerror_modse = relative_se$est,
      relerror_modse_mcse = relative_se$mcse,
      mse = mse$est, mse_mcse = mse$mcse,
      coverage = coverage$est, coverage_mcse = coverage$mcse,
      becoverage = becoverage$est, becoverage_mcse = becoverage$mcse,
      approximation_coverage = approximation_coverage$est,
      approximation_coverage_mcse = approximation_coverage$mcse,
      rejection = rejection$est, rejection_mcse = rejection$mcse,
      convergence = convergence$est,
      n_used = sum(ok), n_attempted = nrow(d),
      stringsAsFactors = FALSE
    )
  }
))
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, 'performance.csv'), row.names = FALSE)

## Critique fix: decisive movement uses paired expected-estimate differences.
## The mean within-replicate range remains descriptive and cannot establish the
## material-consequence branch.
set.seed(MASTER_SEED + 9090L)
max_t_intervals <- function(x, labels) {
  complete <- stats::complete.cases(x)
  x <- x[complete, , drop = FALSE]
  if (nrow(x) < 2L) {
    return(data.frame(label = labels, mean = NA_real_, se = NA_real_,
                      lower = NA_real_, upper = NA_real_, n = nrow(x)))
  }
  means <- colMeans(x)
  sample_sd <- apply(x, 2, stats::sd)
  se <- sample_sd / sqrt(nrow(x))
  active <- is.finite(sample_sd) & sample_sd > 0
  critical <- stats::qnorm(0.975)
  if (sum(active) > 1L) {
    correlation <- stats::cor(x[, active, drop = FALSE])
    draws <- mvtnorm::rmvnorm(MAXT_DRAWS, sigma = correlation)
    critical <- unname(stats::quantile(apply(abs(draws), 1, max), 0.95))
  }
  data.frame(
    label = labels, mean = means, se = se,
    lower = means - critical * se,
    upper = means + critical * se,
    n = nrow(x), stringsAsFactors = FALSE
  )
}

fixed <- res[res$method == 'panel', ]
movement_rows <- list()
pair_rows <- list()
spread_rows <- list()
for (cell in sort(unique(fixed$cell))) {
  d <- fixed[fixed$cell == cell, ]
  wide <- reshape(
    d[, c('rep_id', 'grid', 'est')],
    idvar = 'rep_id', timevar = 'grid', direction = 'wide'
  )
  names_needed <- paste0('est.', GRIDS)
  for (name in names_needed) if (!name %in% names(wide)) wide[[name]] <- NA_real_
  estimates <- as.matrix(wide[, names_needed])
  colnames(estimates) <- GRIDS
  pairs <- combn(seq_along(GRIDS), 2L)
  differences <- sapply(seq_len(ncol(pairs)), function(j)
    estimates[, pairs[1L, j]] - estimates[, pairs[2L, j]])
  labels <- apply(pairs, 2, function(z) paste0(GRIDS[z[1L]], '-vs-', GRIDS[z[2L]]))
  pair_ci <- max_t_intervals(differences, labels)
  grid_ci <- max_t_intervals(estimates, as.character(GRIDS))
  pair_ci$cell <- cell
  pair_rows[[length(pair_rows) + 1L]] <- pair_ci

  complete <- stats::complete.cases(estimates)
  spreads <- ifelse(complete, apply(estimates, 1, max) - apply(estimates, 1, min), NA_real_)
  spread_rows[[length(spread_rows) + 1L]] <- data.frame(
    cell = cell, rep_id = wide$rep_id, within_dataset_spread = spreads
  )

  truth_cell <- truth[truth$cell == cell, ]
  rd_full <- truth_cell$rd_full[1L]
  grid_truth <- truth_cell$rd_panel[match(GRIDS, truth_cell$delta)]
  means <- grid_ci$mean
  materially_different <- any(
    pair_ci$lower > GRID_MARGIN | pair_ci$upper < -GRID_MARGIN,
    na.rm = TRUE
  )
  opposite_decisions <- any(grid_ci$upper < UTILITY_BOUNDARY, na.rm = TRUE) &&
    any(grid_ci$lower > UTILITY_BOUNDARY, na.rm = TRUE)
  equivalent <- all(
    pair_ci$lower >= -GRID_MARGIN & pair_ci$upper <= GRID_MARGIN
  ) && all((means + TREATMENT_BURDEN < 0) == (rd_full + TREATMENT_BURDEN < 0))

  failures <- vapply(GRIDS, function(grid) {
    z <- d[d$grid == grid, ]
    mean(!is.na(z$fail) | !is.finite(z$est))
  }, numeric(1))
  ess <- c(d$ess_early, d$ess_delay)
  median_ess <- stats::median(ess[is.finite(ess)], na.rm = TRUE)
  truth_bad <- any(!truth_cell$precision_met) ||
    any(truth_cell$rd_full_mcse > TRUTH_MCSE_TARGET) ||
    any(truth_cell$approximation_error_mcse > TRUTH_MCSE_TARGET)
  utility_near <- abs(rd_full - UTILITY_BOUNDARY) < GRID_MARGIN
  base_branch <- if (materially_different || opposite_decisions) {
    'material-consequence'
  } else if (equivalent) {
    'cell-specific-equivalence'
  } else {
    'uninformative'
  }
  if (any(failures > MAX_FAILURE_RATE) || !is.finite(median_ess) ||
      median_ess < ANALYSIS_ESS_MIN || truth_bad || utility_near) {
    base_branch <- 'uninformative'
  }
  movement_rows[[length(movement_rows) + 1L]] <- data.frame(
    cell = cell,
    profile = d$profile[1L], G = d$G[1L],
    visit_key = d$visit_key[1L], pressure_key = d$pressure_key[1L],
    rd_full = rd_full,
    expected_range = max(means, na.rm = TRUE) - min(means, na.rm = TRUE),
    truth_range = max(grid_truth, na.rm = TRUE) - min(grid_truth, na.rm = TRUE),
    material_pair = materially_different,
    opposite_utility_decisions = opposite_decisions,
    all_pairs_equivalent = equivalent,
    maximum_failure_rate = max(failures),
    median_arm_ess = median_ess,
    truth_precision_failure = truth_bad,
    utility_boundary_ambiguous = utility_near,
    branch = base_branch,
    stringsAsFactors = FALSE
  )
}
movement <- do.call(rbind, movement_rows)
pairwise <- do.call(rbind, pair_rows)
spreads <- do.call(rbind, spread_rows)

null_cells <- build_cells()
null_cells <- null_cells[null_cells$profile == 'exact-null',
                         c('cell', 'process_scenario', 'G')]
spreads <- merge(spreads, build_cells()[, c('cell', 'process_scenario', 'G', 'profile')],
                 by = 'cell', all.x = TRUE)
null_expectation <- aggregate(
  within_dataset_spread ~ process_scenario + G,
  data = spreads[spreads$profile == 'exact-null', ],
  FUN = function(x) mean(x, na.rm = TRUE)
)
names(null_expectation)[3L] <- 'null_expected_spread'
spreads <- merge(spreads, null_expectation, by = c('process_scenario', 'G'), all.x = TRUE)
spreads$centered_spread <- spreads$within_dataset_spread - spreads$null_expected_spread
utils::write.csv(spreads, file.path(OUT, 'descriptive-spread.csv'), row.names = FALSE)

normal_ci <- function(estimate, influence) {
  n <- sum(is.finite(influence))
  if (n < 2L || !is.finite(estimate)) return(c(estimate, NA_real_, NA_real_))
  se <- stats::sd(influence, na.rm = TRUE) / sqrt(n)
  c(estimate, estimate - 1.96 * se, estimate + 1.96 * se)
}

selector_rows <- list()
for (cell in sort(unique(res$cell))) {
  selected <- res[res$cell == cell & res$method == 'selected', ]
  comparator <- res[res$cell == cell & res$method == 'one-week-5000', ]
  paired <- merge(selected, comparator, by = 'rep_id', suffixes = c('_selected', '_one'))
  ok <- is.na(paired$fail_selected) & is.na(paired$fail_one) &
    is.finite(paired$est_selected) & is.finite(paired$est_one) &
    is.finite(paired$rd_full_selected)
  p <- paired[ok, , drop = FALSE]
  attempted <- nrow(paired)
  failure_rate <- if (attempted) 1 - nrow(p) / attempted else 1

  if (nrow(p) >= 2L) {
    error_selected <- p$est_selected - p$rd_full_selected
    error_one <- p$est_one - p$rd_full_selected
    bias_selected <- mean(error_selected)
    bias_one <- mean(error_one)
    bias_difference <- abs(bias_selected) - abs(bias_one)
    bias_if <- sign(bias_selected) * (error_selected - bias_selected) -
      sign(bias_one) * (error_one - bias_one)
    bias_ci <- normal_ci(bias_difference, bias_if)

    mse_selected <- mean(error_selected^2)
    mse_one <- mean(error_one^2)
    mse_ratio <- mse_selected / mse_one
    mse_if <- (error_selected^2 - mse_selected) / mse_one -
      mse_selected * (error_one^2 - mse_one) / mse_one^2
    mse_ci <- normal_ci(mse_ratio, mse_if)

    mean_selected_time <- mean(p$total_worker_time_selected)
    mean_one_time <- mean(p$total_worker_time_one)
    time_reduction <- 1 - mean_selected_time / mean_one_time
    time_if <- -(p$total_worker_time_selected - mean_selected_time) / mean_one_time +
      mean_selected_time * (p$total_worker_time_one - mean_one_time) / mean_one_time^2
    time_ci <- normal_ci(time_reduction, time_if)

    target_selected <- p$rd_panel_selected
    covered <- p$lo_selected <= target_selected & p$hi_selected >= target_selected
    coverage <- mean(covered)
    coverage_ci <- stats::binom.test(sum(covered), length(covered), conf.level = 0.95)$conf.int
  } else {
    bias_ci <- mse_ci <- time_ci <- c(NA_real_, NA_real_, NA_real_)
    coverage <- coverage_ci <- NA_real_
  }

  bias_state <- if (!all(is.finite(bias_ci))) 'crosses' else if (bias_ci[3L] <= GRID_MARGIN) {
    'success'
  } else if (bias_ci[2L] > GRID_MARGIN) 'failure' else 'crosses'
  coverage_state <- if (!all(is.finite(coverage_ci))) 'crosses' else if (
    coverage_ci[1L] >= COVERAGE_ACCEPT[1L] && coverage_ci[2L] <= COVERAGE_ACCEPT[2L]
  ) {
    'success'
  } else if (coverage_ci[2L] < COVERAGE_ACCEPT[1L] ||
             coverage_ci[1L] > COVERAGE_ACCEPT[2L]) 'failure' else 'crosses'
  mse_state <- if (!all(is.finite(mse_ci))) 'crosses' else if (mse_ci[3L] <= 1) {
    'success'
  } else if (mse_ci[2L] > 1) 'failure' else 'crosses'
  time_state <- if (!all(is.finite(time_ci))) 'crosses' else if (
    time_ci[2L] >= MIN_TIME_REDUCTION
  ) {
    'success'
  } else if (time_ci[3L] < MIN_TIME_REDUCTION) 'failure' else 'crosses'

  states <- c(bias_state, coverage_state, mse_state, time_state)
  verdict <- if (failure_rate > MAX_FAILURE_RATE || any(states == 'crosses')) {
    'uninformative'
  } else if (all(states == 'success')) {
    'successful-partial-solution'
  } else {
    'failed-partial-solution'
  }
  selector_rows[[length(selector_rows) + 1L]] <- data.frame(
    cell = cell,
    bias_deterioration = bias_ci[1L], bias_lower = bias_ci[2L], bias_upper = bias_ci[3L],
    nominal_coverage = coverage,
    coverage_lower = coverage_ci[1L], coverage_upper = coverage_ci[2L],
    mse_ratio = mse_ci[1L], mse_ratio_lower = mse_ci[2L], mse_ratio_upper = mse_ci[3L],
    time_reduction = time_ci[1L], time_reduction_lower = time_ci[2L],
    time_reduction_upper = time_ci[3L],
    failure_rate = failure_rate,
    bias_state = bias_state, coverage_state = coverage_state,
    mse_state = mse_state, time_state = time_state,
    selector_verdict = verdict,
    stringsAsFactors = FALSE
  )
}
selector_comparison <- do.call(rbind, selector_rows)
movement <- merge(movement, selector_comparison[, c('cell', 'selector_verdict')],
                  by = 'cell', all.x = TRUE)
movement$branch[movement$selector_verdict == 'uninformative'] <- 'uninformative'

selection_frequency <- aggregate(
  rep_id ~ cell + selected_grid,
  data = res[res$method == 'selected', ],
  FUN = length
)
names(selection_frequency)[3L] <- 'count'
totals <- aggregate(count ~ cell, selection_frequency, sum)
names(totals)[2L] <- 'total'
selection_frequency <- merge(selection_frequency, totals, by = 'cell')
selection_frequency$frequency <- selection_frequency$count / selection_frequency$total

resource_summary <- aggregate(
  cbind(total_worker_time, person_periods, nuisance_p, peak_memory_mb,
        max_weight_early, max_weight_delay, ess_early, ess_delay) ~
    cell + method_id,
  data = res,
  FUN = function(x) stats::median(x, na.rm = TRUE)
)

grace_contrast <- unique(truth[, c(
  'process_scenario', 'visit_key', 'pressure_key', 'profile',
  'delta_g', 'delta_g_mcse', 'truth_n', 'precision_met'
)])

utils::write.csv(movement, file.path(OUT, 'movement.csv'), row.names = FALSE)
utils::write.csv(pairwise, file.path(OUT, 'movement-pairs.csv'), row.names = FALSE)
utils::write.csv(selector_comparison, file.path(OUT, 'selector-comparison.csv'), row.names = FALSE)
utils::write.csv(selection_frequency, file.path(OUT, 'selection-frequency.csv'), row.names = FALSE)
utils::write.csv(resource_summary, file.path(OUT, 'resource-summary.csv'), row.names = FALSE)
utils::write.csv(grace_contrast, file.path(OUT, 'grace-contrast.csv'), row.names = FALSE)

cat('\n== finite-sample performance ==\n')
cat(sprintf('  cells analyzed: %d\n', length(unique(res$cell))))
cat(sprintf('  minimum convergence: %.3f\n', min(performance$convergence, na.rm = TRUE)))
cat(sprintf('  median absolute bias: %.5f\n',
            stats::median(performance$absolute_bias, na.rm = TRUE)))
cat(sprintf('  nominal coverage range: %.3f to %.3f\n',
            min(performance$coverage, na.rm = TRUE),
            max(performance$coverage, na.rm = TRUE)))

cat('\n== expected grid movement ==\n')
cat(sprintf('  equivalence margin: %.3f risk units\n', GRID_MARGIN))
cat(sprintf('  utility boundary: RD = %.3f\n', UTILITY_BOUNDARY))
cat(sprintf('  maximum expected range: %.5f\n',
            max(movement$expected_range, na.rm = TRUE)))

cat('\n== selector comparison with 5000-person one-week analysis ==\n')
print(table(selector_comparison$selector_verdict, useNA = 'ifany'))

branch_counts <- table(factor(
  movement$branch,
  levels = c('material-consequence', 'cell-specific-equivalence', 'uninformative')
))
successes <- sum(selector_comparison$selector_verdict == 'successful-partial-solution')
cat(sprintf(
  'Decision-rule branches at margin %.3f and utility boundary %.3f: %d material-consequence; %d cell-specific-equivalence; %d uninformative. Selector successful in %d informative cells.\n',
  GRID_MARGIN, UTILITY_BOUNDARY,
  branch_counts[['material-consequence']],
  branch_counts[['cell-specific-equivalence']],
  branch_counts[['uninformative']], successes
))
