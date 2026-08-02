## Study GMT-03: performance measures and prespecified decisions.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1L])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(file.path(OUT, "raw"), "^scenario-.*\\.rds$",
                             full.names = TRUE))
if (!length(raw_files)) stop("No raw scenario files exist")
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))
rep_col <- intersect(c("replicate", "rep", "rep_id"), names(res))[1L]
if (is.na(rep_col)) {
  res$replicate <- ave(seq_len(nrow(res)), res$scenario, res$row_type,
                       FUN = function(x) ceiling(seq_along(x) /
                         ifelse(res$row_type[x[1L]] == "estimate", nrow(estimate_grid()),
                                2L * 3L * 2L * N_MONTHS)))
  rep_col <- "replicate"
}
names(res)[names(res) == rep_col] <- "replicate"

est <- res[res$row_type == "estimate", , drop = FALSE]
diag <- res[res$row_type == "diagnostic", , drop = FALSE]
key <- c("scenario", "endpoint", "subgroup", "horizon")
est <- merge(est, truth[, c(key, "true", "truth_mcse")], by = key, all.x = TRUE)
est$success <- is.na(est$fail) & is.finite(est$est) & is.finite(est$lo) & is.finite(est$hi)
est$covered <- est$success & est$lo <= est$true & est$hi >= est$true

safe_metric <- function(fun, ...) {
  z <- try(fun(...), silent = TRUE)
  if (inherits(z, "try-error")) list(est = NA_real_, mcse = NA_real_) else z
}
safe_becoverage <- function(e, lower, upper) {
  z <- try(perf_becoverage(e, lower, upper), silent = TRUE)
  if (inherits(z, "try-error")) list(est = NA_real_, mcse = NA_real_) else z
}
safe_rejection <- function(lo, hi) {
  z <- try(perf_rejection(lo, hi, 0), silent = TRUE)
  if (inherits(z, "try-error")) z <- try(perf_rejection(lo, hi), silent = TRUE)
  if (inherits(z, "try-error")) list(est = NA_real_, mcse = NA_real_) else z
}

summarize_cell <- function(d) {
  tv <- d$true[1L]
  e <- ifelse(d$success, d$est, NA_real_)
  s <- ifelse(d$success, d$se, NA_real_)
  lo <- ifelse(d$success, d$lo, NA_real_)
  hi <- ifelse(d$success, d$hi, NA_real_)
  b <- safe_metric(perf_bias, e, tv)
  es <- safe_metric(perf_empse, e)
  ms <- safe_metric(perf_modse, s)
  re <- safe_metric(perf_relerror_modse, e, s)
  mse <- safe_metric(perf_mse, e, tv)
  cv <- safe_metric(perf_coverage, lo, hi, tv)
  bec <- safe_becoverage(e, lo, hi)
  rej <- safe_rejection(lo, hi)
  av <- safe_metric(perf_convergence, e, nrow(d))
  ulo <- ifelse(d$success, d$lo, Inf)
  uhi <- ifelse(d$success, d$hi, -Inf)
  ucv <- safe_metric(perf_coverage, ulo, uhi, tv)
  n_ok <- sum(d$success)
  cov_n <- sum(d$covered)
  ai <- wilson_interval(n_ok, nrow(d))
  ci <- wilson_interval(cov_n, n_ok)
  first <- d[1L, , drop = FALSE]
  data.frame(
    scenario = first$scenario, phase = first$phase, n = first$n,
    k_level = first$k_level, kappa = first$kappa,
    alpha_y = first$alpha_y, alpha_d = first$alpha_d, p_g = first$p_g,
    persistence = first$persistence, method = first$method,
    endpoint = first$endpoint, subgroup = first$subgroup, horizon = first$horizon,
    truth = tv, truth_mcse = first$truth_mcse,
    bias = b$est, bias_mcse = b$mcse,
    empse = es$est, empse_mcse = es$mcse,
    modse = ms$est, modse_mcse = ms$mcse,
    relerror_modse = re$est, relerror_modse_mcse = re$mcse,
    mse = mse$est, mse_mcse = mse$mcse,
    coverage = cv$est, coverage_mcse = cv$mcse,
    unconditional_successful_coverage = ucv$est,
    unconditional_successful_coverage_mcse = ucv$mcse,
    bias_eliminated_coverage = bec$est,
    bias_eliminated_coverage_mcse = bec$mcse,
    rejection = rej$est, rejection_mcse = rej$mcse,
    availability = av$est, availability_mcse = av$mcse,
    availability_lower = ai["lower"], availability_upper = ai["upper"],
    coverage_lower = ci["lower"], coverage_upper = ci["upper"],
    n_used = n_ok, n_attempted = nrow(d),
    median_event_ess = stats::median(d$event_ess[d$success], na.rm = TRUE),
    median_nonevent_ess = stats::median(d$nonevent_ess[d$success], na.rm = TRUE),
    median_min_riskset_ess = stats::median(d$min_riskset_ess[d$success], na.rm = TRUE),
    warning_rate = mean(d$warning[d$success], na.rm = TRUE),
    stringsAsFactors = FALSE)
}

parts <- split(est, interaction(est$scenario, est$method, est$endpoint,
                                est$subgroup, est$horizon, drop = TRUE))
performance <- do.call(rbind, lapply(parts, summarize_cell))
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, "performance.csv"), row.names = FALSE)

## Monthly information is summarized separately by estimator family, subgroup,
## strategy, and time. Nominal n remains alongside every weighted diagnostic.
monthly_parts <- split(diag, interaction(diag$scenario, diag$method, diag$subgroup,
                                         diag$strategy, diag$month, drop = TRUE))
monthly <- do.call(rbind, lapply(monthly_parts, function(d) data.frame(
  scenario = d$scenario[1L], phase = d$phase[1L], n = d$n[1L],
  k_level = d$k_level[1L], kappa = d$kappa[1L], alpha_y = d$alpha_y[1L],
  alpha_d = d$alpha_d[1L], method = d$method[1L], subgroup = d$subgroup[1L],
  strategy = d$strategy[1L], month = d$month[1L],
  compatible_median = stats::median(d$n_compatible, na.rm = TRUE),
  cum_y_median = stats::median(d$cum_y, na.rm = TRUE),
  cum_d_median = stats::median(d$cum_d, na.rm = TRUE),
  kish_ess_median = stats::median(d$kish_ess, na.rm = TRUE),
  ess_fraction_median = stats::median(d$ess_fraction, na.rm = TRUE),
  max_normalized_weight_median = stats::median(d$max_normalized_weight, na.rm = TRUE),
  p99_p50_median = stats::median(d$p99_p50, na.rm = TRUE),
  stringsAsFactors = FALSE)))
rownames(monthly) <- NULL
utils::write.csv(monthly, file.path(OUT, "monthly-diagnostics.csv"), row.names = FALSE)

## Mutually exclusive Wilson-bound decisions implement the critique repair.
performance$truth_ok <- performance$truth_mcse <= ifelse(
  performance$subgroup == "all", PROTOCOL_TRUTH_TOL_OVERALL,
  PROTOCOL_TRUTH_TOL_SUBGROUP)
performance$matched_k0_availability_lower <- NA_real_
core <- performance$phase == "core"
match_keys <- c("n", "alpha_y", "alpha_d", "p_g", "persistence", "method",
                "endpoint", "subgroup", "horizon")
k0 <- performance[core & performance$k_level == "K0",
                  c(match_keys, "availability_lower")]
names(k0)[names(k0) == "availability_lower"] <- "k0_lower"
joined <- merge(performance, k0, by = match_keys, all.x = TRUE, sort = FALSE)
performance <- joined
performance$matched_k0_availability_lower <- performance$k0_lower
performance$interval_failure <- performance$truth_ok &
  performance$n_used >= MIN_INTERVALS &
  performance$availability_lower >= FAIL_AVAIL_LB &
  performance$coverage_upper < FAIL_COVERAGE_UB
performance$operational_failure <- performance$truth_ok &
  performance$availability_upper < OPERATIONAL_AVAIL_UB &
  performance$matched_k0_availability_lower >= K0_AVAIL_LB
performance$adequate <- performance$truth_ok &
  performance$coverage_lower >= ADEQUATE_COVERAGE_LB &
  performance$availability_lower >= ADEQUATE_AVAIL_LB
performance$decision <- ifelse(performance$interval_failure, "interval-failure",
  ifelse(performance$operational_failure, "operational-failure",
    ifelse(performance$adequate, "adequate-within-scope", "indeterminate")))
utils::write.csv(performance, file.path(OUT, "cell-decisions.csv"), row.names = FALSE)

## Common-success coverage prevents convergence-selected samples from being
## mistaken for equivalent analysis sets.
exact <- est[est$method %in% c("exact_fixed", "exact_stacked", "exact_t"), ]
common_key <- c("scenario", "replicate", "endpoint", "subgroup", "horizon")
common <- aggregate(exact$success, exact[common_key], sum)
names(common)[ncol(common)] <- "n_methods_successful"
exact <- merge(exact, common, by = common_key, all.x = TRUE)
common_exact <- exact[exact$n_methods_successful == 3L, ]
common_perf <- if (nrow(common_exact)) do.call(rbind, lapply(
  split(common_exact, interaction(common_exact$scenario, common_exact$method,
                                  common_exact$endpoint, common_exact$subgroup,
                                  common_exact$horizon, drop = TRUE)), summarize_cell)) else
  data.frame()
utils::write.csv(common_perf, file.path(OUT, "common-set-performance.csv"), row.names = FALSE)

## Held-out validation reserves replicate 1 as the index study. Replicates 2
## onward classify coverage. Estimator families and endpoint families are never
## pooled.
family_name <- function(endpoint, subgroup) paste(endpoint, subgroup, sep = "_")
held <- est[est$phase == "validation" & est$method %in% c("exact_fixed", "msm") &
              est$horizon == 60L, ]
held$family <- family_name(held$endpoint, held$subgroup)
index <- held[held$replicate == 1L, c("scenario", "method", "family", "warning",
                                      "event_ess", "min_riskset_ess")]
coverage_reps <- held[held$replicate > 1L, ]
validation_perf <- if (nrow(coverage_reps)) do.call(rbind, lapply(
  split(coverage_reps, interaction(coverage_reps$scenario, coverage_reps$method,
                                   coverage_reps$family, drop = TRUE)), summarize_cell)) else
  data.frame()
if (nrow(validation_perf)) {
  validation_perf$family <- family_name(validation_perf$endpoint,
                                         validation_perf$subgroup)
  validation_perf$confirmed <- ifelse(
    validation_perf$truth_mcse <= ifelse(validation_perf$subgroup == "all",
      PROTOCOL_TRUTH_TOL_OVERALL, PROTOCOL_TRUTH_TOL_SUBGROUP) &
      validation_perf$n_used >= MIN_INTERVALS &
      validation_perf$availability_lower >= FAIL_AVAIL_LB &
      validation_perf$coverage_upper < FAIL_COVERAGE_UB, "failure",
    ifelse(validation_perf$coverage_lower >= ADEQUATE_COVERAGE_LB &
             validation_perf$availability_lower >= ADEQUATE_AVAIL_LB,
           "adequate", "indeterminate"))
  index <- merge(index, validation_perf[, c("scenario", "method", "family",
                                             "confirmed", "coverage",
                                             "coverage_lower", "coverage_upper")],
                 by = c("scenario", "method", "family"), all.x = TRUE)
}
utils::write.csv(index, file.path(OUT, "validation-index-studies.csv"), row.names = FALSE)

validation <- do.call(rbind, lapply(split(index, interaction(index$method,
  index$family, drop = TRUE)), function(d) {
  nf <- sum(d$confirmed == "failure", na.rm = TRUE)
  na <- sum(d$confirmed == "adequate", na.rm = TRUE)
  sens_x <- sum(d$warning[d$confirmed == "failure"], na.rm = TRUE)
  spec_x <- sum(!d$warning[d$confirmed == "adequate"], na.rm = TRUE)
  sens <- wilson_interval(sens_x, nf)
  spec <- wilson_interval(spec_x, na)
  enough <- nf >= MIN_VALIDATION_CLASS && na >= MIN_VALIDATION_CLASS
  branch <- if (enough && sens["lower"] >= DIAGNOSTIC_BOUNDARY &&
                spec["lower"] >= DIAGNOSTIC_BOUNDARY) "validated" else
    if (enough && (sens["upper"] < DIAGNOSTIC_BOUNDARY ||
                   spec["upper"] < DIAGNOSTIC_BOUNDARY)) "rejected" else "indeterminate"
  data.frame(method = d$method[1L], family = d$family[1L],
    confirmed_failures = nf, confirmed_adequate = na,
    sensitivity = if (nf) sens_x / nf else NA_real_,
    sensitivity_lower = sens["lower"], sensitivity_upper = sens["upper"],
    specificity = if (na) spec_x / na else NA_real_,
    specificity_lower = spec["lower"], specificity_upper = spec["upper"],
    decision = branch, stringsAsFactors = FALSE)
}))
rownames(validation) <- NULL
utils::write.csv(validation, file.path(OUT, "diagnostic-validation.csv"), row.names = FALSE)

## Scenario-cluster bootstrap for coverage conditional on the observed flag.
set.seed(ANALYSIS_SEED)
conditional <- do.call(rbind, lapply(split(held, interaction(held$method,
  held$family, drop = TRUE)), function(d) {
  calc <- function(x) {
    ok <- x$success & !is.na(x$warning)
    x <- x[ok, ]
    if (!nrow(x) || length(unique(x$warning)) < 2L) return(c(flagged = NA, unflagged = NA, ncrd = NA))
    cf <- mean(x$covered[x$warning])
    cu <- mean(x$covered[!x$warning])
    c(flagged = cf, unflagged = cu, ncrd = (1 - cf) - (1 - cu))
  }
  point <- calc(d)
  ids <- unique(d$scenario)
  boot <- replicate(ANALYSIS_BOOT_B, {
    ## A group holding one scenario would make sample() draw from seq_len(id).
    take <- ids[sample.int(length(ids), replace = TRUE)]
    x <- do.call(rbind, lapply(take, function(z) d[d$scenario == z, ]))
    calc(x)
  })
  ci <- apply(boot, 1L, stats::quantile, probs = c(0.025, 0.975),
              na.rm = TRUE, names = FALSE)
  data.frame(method = d$method[1L], family = d$family[1L],
    coverage_flagged = point["flagged"], coverage_unflagged = point["unflagged"],
    noncoverage_risk_difference = point["ncrd"],
    ncrd_lower = ci[1L, "ncrd"], ncrd_upper = ci[2L, "ncrd"],
    stringsAsFactors = FALSE)
}))
utils::write.csv(conditional, file.path(OUT, "flag-conditional-coverage.csv"),
                 row.names = FALSE)

cat("\n== GMT-03 finite-information study ==\n")
cat(sprintf("profile: %s; scenarios analyzed: %d; attempted replicates per complete cell: %d\n",
            PROFILE, length(unique(est$scenario)), N_REP))
cat(sprintf("named interval failures: %d\n", sum(performance$decision == "interval-failure")))
cat(sprintf("named operational failures: %d\n", sum(performance$decision == "operational-failure")))
cat(sprintf("adequate cells within scope: %d\n", sum(performance$decision == "adequate-within-scope")))
cat(sprintf("indeterminate cells: %d\n", sum(performance$decision == "indeterminate")))
cat("diagnostic validation branches:\n")
for (i in seq_len(nrow(validation)))
  cat(sprintf("  %s, %s: %s; failures=%d, adequate=%d\n",
              validation$method[i], validation$family[i], validation$decision[i],
              validation$confirmed_failures[i], validation$confirmed_adequate[i]))
cat(sprintf("Decision-rule branch: %d interval-failure, %d operational-failure, %d adequate-within-scope, and %d indeterminate named cells; no field-level GMT-03 conclusion is permitted.\n",
            sum(performance$decision == "interval-failure"),
            sum(performance$decision == "operational-failure"),
            sum(performance$decision == "adequate-within-scope"),
            sum(performance$decision == "indeterminate")))
