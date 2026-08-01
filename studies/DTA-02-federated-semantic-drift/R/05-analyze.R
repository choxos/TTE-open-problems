## DTA-02: performance, paired changes, gate operating characteristics, and
## the prespecified decision branches.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

source(here('R', '00-config.R'))
source(here('..', '_shared', 'R', 'performance.R'))

OUT <- here('results')
TRUTH <- readRDS(file.path(OUT, 'truth.rds'))
stopifnot(isTRUE(TRUTH$complete), isTRUE(TRUTH$verification$pass))

raw <- list.files(file.path(OUT, 'raw'), '^scenario-.*\\.rds$', full.names = TRUE)
adaptive_dirs <- list.dirs(file.path(OUT, 'adaptive'), recursive = FALSE,
                           full.names = TRUE)
if (length(adaptive_dirs)) {
  raw <- c(raw, unlist(lapply(adaptive_dirs, function(d)
    list.files(file.path(d, 'raw'), '^scenario-.*\\.rds$', full.names = TRUE))))
}
stopifnot(length(raw) > 0)
res <- do.call(rbind, lapply(sort(unique(raw)), readRDS))
rownames(res) <- NULL

truth <- TRUTH$scenario
res <- merge(res, truth,
             by = c('formal_scenario', 'pair_id', 'method'), all.x = TRUE)

parse_mask <- function(x) {
  if (is.na(x) || !nzchar(x)) return(integer(0))
  which(strsplit(x, '', fixed = TRUE)[[1]] == '1')
}

passing_truth <- function(formal_scenario, pair_id, mask) {
  keep <- parse_mask(mask)
  if (length(keep) < 4L) return(NA_real_)
  d <- TRUTH$site[TRUTH$site$formal_scenario == formal_scenario &
                    TRUTH$site$pair_id == pair_id & TRUTH$site$site %in% keep, ]
  if (nrow(d) != length(keep)) return(NA_real_)
  mean(d$theta_q)
}

is_exclusion <- res$method == 'site-exclusion-200'
res$own_target[is_exclusion] <- mapply(
  passing_truth, res$formal_scenario[is_exclusion], res$pair_id[is_exclusion],
  res$pass_mask[is_exclusion])
res$functional_discrepancy[is_exclusion] <-
  res$own_target[is_exclusion] - res$psi[is_exclusion]

safe_perf <- function(expr) {
  tryCatch(expr, error = function(e) list(est = NA_real_, mcse = NA_real_))
}

perf <- do.call(rbind, lapply(
  split(res, list(res$formal_scenario, res$method), drop = TRUE),
  function(d) {
    ok <- is.na(d$fail) & is.finite(d$latent_est) & is.finite(d$own_target)
    err <- ifelse(ok, d$latent_est - d$own_target, NA_real_)
    se <- ifelse(ok, d$latent_se, NA_real_)
    lo <- ifelse(ok, d$latent_lo - d$own_target, NA_real_)
    hi <- ifelse(ok, d$latent_hi - d$own_target, NA_real_)
    b <- safe_perf(perf_bias(err, 0))
    es <- safe_perf(perf_empse(err))
    ms <- safe_perf(perf_modse(se))
    re <- safe_perf(perf_relerror_modse(err, se))
    mse <- safe_perf(perf_mse(err, 0))
    cv <- safe_perf(perf_coverage(lo, hi, 0))
    bec <- safe_perf(perf_becoverage(err, se, 0))
    rej <- safe_perf(perf_rejection(lo, hi, 0))
    cg <- safe_perf(perf_convergence(ifelse(ok, d$latent_est, NA_real_), nrow(d)))

    released <- d$release & ok
    cb <- if (any(released)) safe_perf(perf_bias(d$est[released] - d$own_target[released], 0)) else list(est = NA, mcse = NA)
    cc <- if (any(released)) safe_perf(perf_coverage(d$lo[released] - d$own_target[released],
                                                    d$hi[released] - d$own_target[released], 0)) else list(est = NA, mcse = NA)
    data.frame(
      formal_scenario = d$formal_scenario[1], method = d$method[1],
      mapping = d$mapping[1], kappa = d$kappa[1], gamma = d$gamma[1],
      reference = d$reference[1], own_target = mean(d$own_target, na.rm = TRUE),
      psi = d$psi[1], functional_discrepancy = mean(d$functional_discrepancy, na.rm = TRUE),
      bias = b$est, bias_mcse = b$mcse,
      empse = es$est, empse_mcse = es$mcse,
      modse = ms$est, modse_mcse = ms$mcse,
      relerror_modse = re$est, relerror_modse_mcse = re$mcse,
      mse = mse$est, mse_mcse = mse$mcse,
      coverage = cv$est, coverage_mcse = cv$mcse,
      bias_eliminated_coverage = bec$est,
      bias_eliminated_coverage_mcse = bec$mcse,
      rejection = rej$est, rejection_mcse = rej$mcse,
      convergence = cg$est, convergence_mcse = cg$mcse,
      release_probability = mean(d$release),
      conditional_bias = cb$est, conditional_bias_mcse = cb$mcse,
      conditional_coverage = cc$est, conditional_coverage_mcse = cc$mcse,
      n_attempted = nrow(d), n_numerical = sum(ok), n_released = sum(released),
      stringsAsFactors = FALSE
    )
  }))
rownames(perf) <- NULL
utils::write.csv(perf, file.path(OUT, 'performance.csv'), row.names = FALSE)

wilson_interval <- function(x, n, confidence = 0.95) {
  if (!is.finite(n) || n <= 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - confidence) / 2)
  p <- x / n
  den <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(lower = max(0, center - half), upper = min(1, center + half))
}

## Paired changes use one clinical count draw for all six mappings. Reference
## accuracy does not alter an effect estimate, so the perfect-reference copy is
## used once rather than counted twice.
eq <- res[res$method == 'equalq' & res$reference == 'perfect', ]
compatible <- eq[eq$mapping == 'compatible',
                 c('batch_id', 'rep_id', 'pair_id', 'kappa', 'gamma',
                   'latent_est', 'fail')]
names(compatible)[6:7] <- c('compatible_est', 'compatible_fail')
paired_rows <- list()
for (mapping in setdiff(MAPPING_LEVELS, 'compatible')) {
  d <- eq[eq$mapping == mapping, ]
  z <- merge(d, compatible,
             by = c('batch_id', 'rep_id', 'pair_id', 'kappa', 'gamma'), all.x = TRUE)
  z$paired_ok <- is.na(z$fail) & is.na(z$compatible_fail) &
    is.finite(z$latent_est) & is.finite(z$compatible_est)
  z$change <- ifelse(z$paired_ok, z$latent_est - z$compatible_est, NA_real_)
  paired_rows[[mapping]] <- z
}
paired_data <- do.call(rbind, paired_rows)
N_PRIMARY_CELLS <- (length(MAPPING_LEVELS) - 1L) * length(KAPPA_LEVELS) * length(GAMMA_LEVELS)
critical_familywise <- stats::qnorm(1 - 0.05 / (2 * N_PRIMARY_CELLS))

paired <- do.call(rbind, lapply(
  split(paired_data, list(paired_data$mapping, paired_data$kappa, paired_data$gamma),
        drop = TRUE),
  function(d) {
    change <- d$change
    n <- sum(is.finite(change))
    mean_change <- mean(change, na.rm = TRUE)
    mcse <- stats::sd(change, na.rm = TRUE) / sqrt(n)
    exact <- mean(d$exact_change[d$paired_ok], na.rm = TRUE)
    lo <- mean_change - critical_familywise * mcse
    hi <- mean_change + critical_familywise * mcse
    nonconv <- 1 - n / nrow(d)
    branch <- if (!TRUTH$verification$pass || nonconv > NONCONVERGENCE_LIMIT || !is.finite(exact)) {
      'uninformative'
    } else if (abs(exact) > EXACT_ZERO_TOLERANCE &&
               ((exact > 0 && lo > 0) || (exact < 0 && hi < 0))) {
      'scoped-mechanism-supported'
    } else if (abs(exact) <= EXACT_ZERO_TOLERANCE &&
               lo >= -EQUIVALENCE_MARGIN && hi <= EQUIVALENCE_MARGIN) {
      'no-numerical-change'
    } else {
      'uninformative'
    }
    data.frame(
      mapping = d$mapping[1], kappa = d$kappa[1], gamma = d$gamma[1],
      exact_change = exact, paired_mean_change = mean_change,
      paired_mcse = mcse, familywise_lower = lo, familywise_upper = hi,
      familywise_critical = critical_familywise,
      nonconvergence = nonconv, n_paired = n, branch = branch,
      stringsAsFactors = FALSE
    )
  }))
rownames(paired) <- NULL
utils::write.csv(paired, file.path(OUT, 'paired-changes.csv'), row.names = FALSE)

GATED_METHODS <- c('historical-q-gate', 'aggregate-gate',
                   'validation-50', 'validation-100', 'validation-200',
                   'site-exclusion-200')
gate_rows <- res[res$method %in% GATED_METHODS, ]
gate_perf <- do.call(rbind, lapply(
  split(gate_rows, list(gate_rows$formal_scenario, gate_rows$method), drop = TRUE),
  function(d) {
    release_n <- sum(d$release)
    release_ci <- wilson_interval(release_n, nrow(d))
    do.call(rbind, lapply(UNSAFE_TOLERANCES, function(tol) {
      unsafe <- d$release & is.finite(d$est) & abs(d$est - d$psi) > tol
      unsafe_ci <- wilson_interval(sum(unsafe), nrow(d))
      data.frame(
        formal_scenario = d$formal_scenario[1], method = d$method[1],
        mapping = d$mapping[1], kappa = d$kappa[1], gamma = d$gamma[1],
        reference = d$reference[1], exact_change = mean(d$exact_change),
        tolerance = tol, release_probability = release_n / nrow(d),
        release_lower = release_ci[['lower']], release_upper = release_ci[['upper']],
        unsafe_release = mean(unsafe),
        unsafe_lower = unsafe_ci[['lower']], unsafe_upper = unsafe_ci[['upper']],
        n = nrow(d), stringsAsFactors = FALSE
      )
    }))
  }))
rownames(gate_perf) <- NULL
utils::write.csv(gate_perf, file.path(OUT, 'gate-performance.csv'), row.names = FALSE)

site_accuracy <- do.call(rbind, lapply(
  split(gate_rows[gate_rows$method != 'historical-q-gate', ],
        list(gate_rows$method[gate_rows$method != 'historical-q-gate'],
             gate_rows$reference[gate_rows$method != 'historical-q-gate']), drop = TRUE),
  function(d) {
    tp <- sum(d$site_tp, na.rm = TRUE); fp <- sum(d$site_fp, na.rm = TRUE)
    tn <- sum(d$site_tn, na.rm = TRUE); fn <- sum(d$site_fn, na.rm = TRUE)
    sens <- wilson_interval(tp, tp + fn)
    spec <- wilson_interval(tn, tn + fp)
    ppv <- wilson_interval(tp, tp + fp)
    npv <- wilson_interval(tn, tn + fn)
    data.frame(
      method = d$method[1], reference = d$reference[1],
      sensitivity = tp / (tp + fn), sensitivity_lower = sens[['lower']],
      sensitivity_upper = sens[['upper']], specificity = tn / (tn + fp),
      specificity_lower = spec[['lower']], specificity_upper = spec[['upper']],
      ppv = tp / (tp + fp), ppv_lower = ppv[['lower']], ppv_upper = ppv[['upper']],
      npv = tn / (tn + fn), npv_lower = npv[['lower']], npv_upper = npv[['upper']],
      tp = tp, fp = fp, tn = tn, fn = fn, stringsAsFactors = FALSE
    )
  }))
rownames(site_accuracy) <- NULL
utils::write.csv(site_accuracy, file.path(OUT, 'site-detection.csv'), row.names = FALSE)

ADEQUACY_METHODS <- c('aggregate-gate', 'validation-50', 'validation-100',
                      'validation-200', 'site-exclusion-200')
adequacy <- do.call(rbind, lapply(ADEQUACY_METHODS, function(method) {
  gp <- gate_perf[gate_perf$method == method, ]
  harmful <- gp[abs(gp$exact_change) >= 0.01 - 1e-12, ]
  compatible_gp <- gp[gp$mapping == 'compatible', ]
  sa <- site_accuracy[site_accuracy$method == method, ]
  safety_state <- if (nrow(harmful) && all(harmful$unsafe_upper <= SAFETY_ADEQUATE_UPPER)) {
    'adequate'
  } else if (nrow(harmful) && any(harmful$unsafe_lower >= SAFETY_INADEQUATE_LOWER)) {
    'inadequate'
  } else 'unclassified'
  release_state <- if (nrow(compatible_gp) && all(compatible_gp$release_lower >= DIAGNOSTIC_ADEQUATE_LOWER)) {
    'adequate'
  } else if (nrow(compatible_gp) && any(compatible_gp$release_upper <= DIAGNOSTIC_INADEQUATE_UPPER)) {
    'inadequate'
  } else 'unclassified'
  accuracy_state <- if (nrow(sa) && all(sa$sensitivity_lower >= DIAGNOSTIC_ADEQUATE_LOWER, na.rm = TRUE) &&
                        all(sa$specificity_lower >= DIAGNOSTIC_ADEQUATE_LOWER, na.rm = TRUE)) {
    'adequate'
  } else if (nrow(sa) && (any(sa$sensitivity_upper <= DIAGNOSTIC_INADEQUATE_UPPER, na.rm = TRUE) ||
                            any(sa$specificity_upper <= DIAGNOSTIC_INADEQUATE_UPPER, na.rm = TRUE))) {
    'inadequate'
  } else 'unclassified'
  overall <- if (all(c(safety_state, release_state, accuracy_state) == 'adequate')) 'adequate'
  else if (any(c(safety_state, release_state, accuracy_state) == 'inadequate')) 'inadequate'
  else 'unclassified'
  data.frame(method = method, safety = safety_state,
             compatible_release = release_state, site_accuracy = accuracy_state,
             overall = overall, stringsAsFactors = FALSE)
}))
utils::write.csv(adequacy, file.path(OUT, 'gate-adequacy.csv'), row.names = FALSE)

n_batches <- max(res$batch_id, na.rm = TRUE)
current_rep <- n_batches * BATCH_SIZE
need_cells <- paired[paired$branch == 'uninformative', ]
need_gates <- adequacy[adequacy$overall == 'unclassified', ]
if (current_rep < MAX_REP && (nrow(need_cells) || nrow(need_gates))) {
  blocks <- unique(merge(
    need_cells[, c('kappa', 'gamma'), drop = FALSE], build_scenarios(),
    by = c('kappa', 'gamma'), all.x = TRUE))
  adaptive <- data.frame(
    next_batch = n_batches + 1L,
    scenario = if (nrow(blocks)) blocks$scenario else seq_len(nrow(build_scenarios())),
    reason = 'confidence bound intersects a prespecified decision region',
    stringsAsFactors = FALSE
  )
} else {
  adaptive <- data.frame(next_batch = integer(), scenario = integer(), reason = character())
}
utils::write.csv(adaptive, file.path(OUT, 'adaptive-needed.csv'), row.names = FALSE)
utils::write.csv(paired, file.path(OUT, 'decision-cells.csv'), row.names = FALSE)

cat('\n== exact and paired mapping changes ==\n')
print(paired[, c('mapping', 'kappa', 'gamma', 'exact_change',
                 'familywise_lower', 'familywise_upper', 'branch')], row.names = FALSE)
cat(sprintf('\nExact nonzero threshold: %.8f; equivalence margin: [%.3f, %.3f].\n',
            EXACT_ZERO_TOLERANCE, -EQUIVALENCE_MARGIN, EQUIVALENCE_MARGIN))
cat(sprintf('Safety evidence regions: upper <= %.2f or lower >= %.2f.\n',
            SAFETY_ADEQUATE_UPPER, SAFETY_INADEQUATE_LOWER))
cat(sprintf('Release, sensitivity, and specificity regions: lower >= %.2f or upper <= %.2f.\n',
            DIAGNOSTIC_ADEQUATE_LOWER, DIAGNOSTIC_INADEQUATE_UPPER))
cat('\n== gate adequacy ==\n')
print(adequacy, row.names = FALSE)

if (nrow(adaptive)) {
  final_branch <- sprintf('ADAPTIVE CONTINUATION REQUIRED at %d replicates; run TTE_BATCH_ID=%d because at least one bound remains in an indifference region',
                          current_rep, n_batches + 1L)
} else if (any(paired$branch == 'scoped-mechanism-supported') &&
           any(paired$branch == 'no-numerical-change')) {
  final_branch <- 'BOTH CELL-LEVEL BRANCHES REACHED: scoped mechanism support in nonzero cells and no numerical change in equivalence cells'
} else if (all(paired$branch == 'no-numerical-change')) {
  final_branch <- 'NO-NUMERICAL-CHANGE BRANCH'
} else if (any(paired$branch == 'scoped-mechanism-supported')) {
  final_branch <- 'SCOPED-MECHANISM-SUPPORTED BRANCH'
} else {
  final_branch <- 'UNINFORMATIVE BRANCH at the replication cap'
}
cat('\nDECISION BRANCH: ', final_branch, '\n', sep = '')
