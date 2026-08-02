## LRN-01 support stress study: performance and decision rules.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(file.path(OUT, "raw"), "^scenario-.*\\.rds$", full.names = TRUE))
stopifnot(length(raw_files) > 0, file.exists(file.path(OUT, "truth.rds")))
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))
laws <- build_observed_laws()

safe_perf <- function(expr) tryCatch(expr, error = function(e) list(est = NA_real_, mcse = NA_real_))

expanded <- merge(res, truth[, c("estimand_scenario", "observed_law", "delta",
                                  "truth_rd", "truth_rd_mcse")],
                  by = "observed_law", all.x = TRUE)
perf <- do.call(rbind, lapply(split(expanded,
  list(expanded$observed_law, expanded$method, expanded$delta), drop = TRUE), function(d) {
  est <- d$est; se <- d$se; tv <- d$truth_rd[1]
  lo <- est - 1.96 * se; hi <- est + 1.96 * se
  b <- safe_perf(perf_bias(est, tv)); es <- safe_perf(perf_empse(est))
  ms <- safe_perf(perf_modse(se)); re <- safe_perf(perf_relerror_modse(est, se))
  mse <- safe_perf(perf_mse(est, tv)); cv <- safe_perf(perf_coverage(lo, hi, tv))
  be <- safe_perf(perf_becoverage(est, lo, hi))
  rj <- safe_perf(perf_rejection(lo, hi, 0))
  cg <- safe_perf(perf_convergence(est, nrow(d)))
  data.frame(observed_law = d$observed_law[1], method = d$method[1],
             n = d$n[1], complexity = d$complexity[1],
             support_key = d$support_key[1], support_kind = d$support_kind[1],
             geometry = d$geometry[1], boundary = d$boundary[1], delta = d$delta[1],
             truth = tv, truth_mcse = d$truth_rd_mcse[1],
             bias = b$est, bias_mcse = b$mcse,
             empse = es$est, empse_mcse = es$mcse,
             modse = ms$est, modse_mcse = ms$mcse,
             relerror_modse = re$est, relerror_modse_mcse = re$mcse,
             mse = mse$est, mse_mcse = mse$mcse,
             coverage = cv$est, coverage_mcse = cv$mcse,
             becoverage = be$est, becoverage_mcse = be$mcse,
             rejection = rj$est, rejection_mcse = rj$mcse,
             convergence = cg$est, convergence_mcse = cg$mcse,
             numerical_warning = mean(d$numerical_warning %in% TRUE),
             interval_width_median = stats::median(2 * 1.96 * se, na.rm = TRUE),
             interval_width_p90 = unname(stats::quantile(2 * 1.96 * se, 0.9,
                                                         na.rm = TRUE, names = FALSE)),
             n_used = sum(is.finite(est)), n_attempted = nrow(d),
             stringsAsFactors = FALSE)
}))
rownames(perf) <- NULL
utils::write.csv(perf, file.path(OUT, "performance.csv"), row.names = FALSE)

wilson <- function(x, n, alpha, success = TRUE) {
  if (!n) return(c(lower = NA_real_, upper = NA_real_))
  if (!success) x <- n - x
  p <- x / n; z <- stats::qnorm(1 - alpha)
  den <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(lower = max(0, center - half), upper = min(1, center + half))
}

exact_laws <- laws[laws$support_kind == "exact", ]
fc_rep <- list(); compatible <- list()
for (i in seq_len(nrow(exact_laws))) for (m in COMPLETION_MAGNITUDES) {
  law <- exact_laws$observed_law[i]
  tr <- truth[truth$observed_law == law &
                vapply(truth$delta, function(x) any(abs(x - c(-m, 0, m)) < 1e-12), logical(1)), ]
  low_truth <- min(tr$truth_rd); high_truth <- max(tr$truth_rd)
  for (method in METHODS) {
    d <- res[res$observed_law == law & res$method == method, ]
    covered <- is.finite(d$lo) & is.finite(d$hi) & d$lo <= low_truth & d$hi >= high_truth
    green <- is.na(d$fail) & d$conventional_green %in% TRUE
    if (method == "flex_aipw_map") green <- green & !(d$support_red %in% TRUE)
    f <- as.integer(green & !covered)
    fc_rep[[length(fc_rep) + 1L]] <- data.frame(
      observed_law = law, rep_id = d$rep_id, magnitude = m, method = method,
      compatible_coverage = covered, green = green, false_certainty = f,
      competitive_loss = d$competitive_loss, stringsAsFactors = FALSE)
    compatible[[length(compatible) + 1L]] <- data.frame(
      observed_law = law, n = d$n[1], complexity = d$complexity[1],
      support_key = d$support_key[1], geometry = d$geometry[1], boundary = d$boundary[1],
      method = method, magnitude = m, truth_min = low_truth, truth_max = high_truth,
      truth_span = high_truth - low_truth,
      compatible_coverage = mean(covered), false_certainty = mean(f),
      false_certainty_competitive = if (any(d$competitive_loss %in% TRUE))
        mean(f[d$competitive_loss %in% TRUE]) else NA_real_,
      n_attempted = nrow(d), stringsAsFactors = FALSE)
  }
}
fc_rep <- do.call(rbind, fc_rep); compatible <- do.call(rbind, compatible)
saveRDS(fc_rep, file.path(OUT, "false-certainty-replicates.rds"))
utils::write.csv(compatible, file.path(OUT, "compatible-performance.csv"), row.names = FALSE)

material <- unique(truth[truth$support_kind == "exact",
  c("observed_law", "n", "complexity", "support_key", "geometry", "boundary",
    "zero_mass_max", "span_log2")])
material$material <- material$zero_mass_max >= SUPPORT_MASS_THRESHOLD &
  material$span_log2 >= SUPPORT_MASS_THRESHOLD

paired_raw <- list()
primary_fc <- fc_rep[abs(fc_rep$magnitude - PRIMARY_MAGNITUDE) < 1e-12, ]
for (i in seq_len(nrow(material))) {
  law <- material$observed_law[i]
  flex <- primary_fc[primary_fc$observed_law == law & primary_fc$method == "flex_aipw",
                     c("rep_id", "false_certainty")]
  for (cmp in c("ipw", "main_aipw")) {
    other <- primary_fc[primary_fc$observed_law == law & primary_fc$method == cmp,
                        c("rep_id", "false_certainty")]
    z <- merge(flex, other, by = "rep_id", suffixes = c("_flex", "_other"))
    z$difference <- z$false_certainty_flex - z$false_certainty_other
    paired_raw[[length(paired_raw) + 1L]] <- data.frame(
      observed_law = law, comparison = paste0("flex-minus-", cmp),
      rep_id = z$rep_id, difference = z$difference)
  }
}
paired_raw <- do.call(rbind, paired_raw)
K_excess <- length(unique(interaction(paired_raw$observed_law, paired_raw$comparison)))
paired <- do.call(rbind, lapply(split(paired_raw,
  list(paired_raw$observed_law, paired_raw$comparison), drop = TRUE), function(d) {
  n <- nrow(d); est <- mean(d$difference); mcse <- stats::sd(d$difference) / sqrt(n)
  crit <- stats::qt(1 - DECISION$family_alpha / K_excess, df = n - 1)
  data.frame(observed_law = d$observed_law[1], comparison = d$comparison[1],
             estimate = est, mcse = mcse, lower = est - crit * mcse,
             upper = est + crit * mcse, n = n)
}))
paired <- merge(paired, material, by = "observed_law", all.x = TRUE)
utils::write.csv(paired, file.path(OUT, "paired-excess.csv"), row.names = FALSE)

map_red <- res[res$method == "flex_aipw_map", ]
warning_cells <- rbind(
  laws[laws$support_kind == "exact", ],
  laws[laws$support_kind == "practical", ],
  laws[laws$support_key == "strong", ])
warning_cells <- warning_cells[!duplicated(warning_cells$observed_law), ]
warning_rates <- do.call(rbind, lapply(seq_len(nrow(warning_cells)), function(i) {
  d <- map_red[map_red$observed_law == warning_cells$observed_law[i], ]
  tr <- truth[truth$observed_law == warning_cells$observed_law[i], ][1, ]
  target <- if (warning_cells$support_key[i] == "strong") "specificity" else "sensitivity"
  successes <- if (target == "specificity") sum(!(d$support_red %in% TRUE)) else
    sum(d$support_red %in% TRUE)
  data.frame(observed_law = warning_cells$observed_law[i], n = warning_cells$n[i],
             complexity = warning_cells$complexity[i], support_key = warning_cells$support_key[i],
             support_kind = warning_cells$support_kind[i], geometry = warning_cells$geometry[i],
             target = target, successes = successes, attempted = nrow(d),
             estimate = successes / nrow(d), zero_mass = tr$zero_mass_max,
             below_0025_mass = tr$below_0025_mass_max)
}))
K_warning <- nrow(warning_rates)
wb <- t(vapply(seq_len(nrow(warning_rates)), function(i)
  wilson(warning_rates$successes[i], warning_rates$attempted[i],
         DECISION$family_alpha / K_warning), numeric(2)))
warning_rates$lower <- wb[, 1]; warning_rates$upper <- wb[, 2]
utils::write.csv(warning_rates, file.path(OUT, "support-warning-performance.csv"), row.names = FALSE)

reduction_raw <- merge(
  primary_fc[primary_fc$method == "flex_aipw", c("observed_law", "rep_id", "false_certainty")],
  primary_fc[primary_fc$method == "flex_aipw_map", c("observed_law", "rep_id", "false_certainty")],
  by = c("observed_law", "rep_id"), suffixes = c("_flex", "_map"))
reduction_raw$difference <- reduction_raw$false_certainty_flex - reduction_raw$false_certainty_map
K_reduction <- length(unique(reduction_raw$observed_law))
reduction <- do.call(rbind, lapply(split(reduction_raw, reduction_raw$observed_law), function(d) {
  n <- nrow(d); est <- mean(d$difference); mcse <- stats::sd(d$difference) / sqrt(n)
  crit <- stats::qt(1 - DECISION$family_alpha / K_reduction, df = n - 1)
  data.frame(observed_law = d$observed_law[1], estimate = est, mcse = mcse,
             lower = est - crit * mcse, upper = est + crit * mcse, n = n)
}))
reduction <- merge(reduction, material, by = "observed_law", all.x = TRUE)
utils::write.csv(reduction, file.path(OUT, "map-reduction.csv"), row.names = FALSE)

strong <- res[res$support_key == "strong" & res$n == 4000, ]
conv <- do.call(rbind, lapply(split(strong, list(strong$complexity, strong$method), drop = TRUE), function(d) {
  x <- sum(is.na(d$fail)); n <- nrow(d)
  data.frame(complexity = d$complexity[1], method = d$method[1], converged = x,
             attempted = n, estimate = x / n)
}))
K_conv <- nrow(conv)
cb <- t(vapply(seq_len(nrow(conv)), function(i)
  wilson(conv$converged[i], conv$attempted[i], DECISION$family_alpha / K_conv), numeric(2)))
conv$lower <- cb[, 1]; conv$upper <- cb[, 2]
utils::write.csv(conv, file.path(OUT, "strong-overlap-convergence.csv"), row.names = FALSE)

loss <- list()
flex_rows <- res[res$method == "flex_aipw", ]
for (t in VISITS) for (class in c("flex", "main")) {
  v <- flex_rows[[paste0("treat_loss_", class, "_t", t)]]
  z <- split(seq_along(v), flex_rows$observed_law)
  loss <- c(loss, lapply(z, function(idx) data.frame(
    observed_law = flex_rows$observed_law[idx[1]], model_class = class,
    outcome = "treatment", visit = t, mean_loss = mean(v[idx], na.rm = TRUE),
    mcse = stats::sd(v[idx], na.rm = TRUE) / sqrt(sum(is.finite(v[idx]))))))
}
for (class in c("flex", "main")) {
  v <- flex_rows[[paste0("outcome_loss_", class)]]
  z <- split(seq_along(v), flex_rows$observed_law)
  loss <- c(loss, lapply(z, function(idx) data.frame(
    observed_law = flex_rows$observed_law[idx[1]], model_class = class,
    outcome = "terminal-Y", visit = 5L, mean_loss = mean(v[idx], na.rm = TRUE),
    mcse = stats::sd(v[idx], na.rm = TRUE) / sqrt(sum(is.finite(v[idx]))))))
}
utils::write.csv(do.call(rbind, loss), file.path(OUT, "predictive-loss.csv"), row.names = FALSE)

runtime <- aggregate(cbind(elapsed_seconds, jacobian_seconds, ridge_seconds, memory_mb) ~ n,
                     data = res[res$method == "flex_aipw", ],
                     FUN = function(x) c(mean = mean(x, na.rm = TRUE),
                                        p90 = unname(stats::quantile(x, 0.9, na.rm = TRUE))))
utils::write.csv(runtime, file.path(OUT, "runtime-benchmark.csv"), row.names = FALSE)

required_complete <- aggregate(rep_id ~ observed_law, res, function(x) length(unique(x)))
missing_replicates <- nrow(required_complete) < nrow(laws) ||
  any(required_complete$rep_id < DECISION$minimum_completed)
truth_ok <- all(truth$truth_max_mcse <= TRUTH_MCSE_MAX)
score_values <- res$score_residual[res$method %in% c("ipw", "main_aipw") & is.na(res$fail)]
validation_ok <- truth_ok && length(score_values) > 0 && all(score_values <= 1e-5) &&
  file.exists(file.path(OUT, "projection-manifest.csv"))
strong_ok <- nrow(conv) == 2L * length(METHODS) &&
  all(conv$lower >= DECISION$strong_convergence_lower)
geometry_ok <- all(material$zero_mass_max >= SUPPORT_MASS_THRESHOLD &
                     material$span_log2 >= SUPPORT_MASS_THRESHOLD)

needed_pairs <- paired[paired$material, ]
excess_supported <- nrow(needed_pairs) > 0 &&
  all(needed_pairs$lower >= DECISION$excess_support_lower)
excess_not_supported <- nrow(needed_pairs) > 0 &&
  all(needed_pairs$upper <= DECISION$excess_not_supported_upper)
blocker <- missing_replicates || !validation_ok || !strong_ok || !geometry_ok
flex_branch <- if (blocker) "UNINFORMATIVE" else if (excess_supported) {
  "NARROW FLEXIBLE-SPECIFIC EXCESS SUPPORTED"
} else if (excess_not_supported) {
  "NARROW FLEXIBLE-SPECIFIC EXCESS NOT SUPPORTED"
} else "UNINFORMATIVE"

exact_sens <- warning_rates[warning_rates$support_kind == "exact" &
                              warning_rates$zero_mass >= SUPPORT_MASS_THRESHOLD, ]
practical_sens <- warning_rates[warning_rates$support_kind == "practical" &
                                  warning_rates$below_0025_mass >= SUPPORT_MASS_THRESHOLD, ]
specificity <- warning_rates[warning_rates$support_key == "strong" &
                               warning_rates$below_0025_mass <= STRONG_SPECIFICITY_MASS, ]
map_success <- nrow(exact_sens) > 0 && nrow(practical_sens) > 0 && nrow(specificity) > 0 &&
  all(exact_sens$lower >= DECISION$map_sensitivity_lower) &&
  all(practical_sens$lower >= DECISION$map_sensitivity_lower) &&
  all(specificity$lower >= DECISION$map_specificity_lower) &&
  all(reduction$lower[reduction$material] >= DECISION$map_reduction_lower)
map_failure <- any(exact_sens$upper <= DECISION$map_failure_sensitivity_upper) ||
  any(practical_sens$upper <= DECISION$map_failure_sensitivity_upper) ||
  any(specificity$upper <= DECISION$map_failure_specificity_upper) ||
  any(reduction$upper[reduction$material] <= DECISION$map_failure_reduction_upper)
map_branch <- if (blocker) "UNINFORMATIVE" else if (map_success) {
  "SUPPORT MAP SUCCESSFUL"
} else if (map_failure) "SUPPORT MAP UNSUCCESSFUL" else "UNINFORMATIVE"

decision <- data.frame(
  flexible_branch = flex_branch, map_branch = map_branch,
  minimum_completed_required = DECISION$minimum_completed,
  achieved_minimum_completed = if (nrow(required_complete)) min(required_complete$rep_id) else 0,
  geometry_material = geometry_ok, strong_overlap_convergence = strong_ok,
  implementation_validation = validation_ok,
  excess_supported_lower_threshold = DECISION$excess_support_lower,
  excess_not_supported_upper_threshold = DECISION$excess_not_supported_upper,
  map_sensitivity_lower_threshold = DECISION$map_sensitivity_lower,
  map_specificity_lower_threshold = DECISION$map_specificity_lower,
  map_reduction_lower_threshold = DECISION$map_reduction_lower,
  stringsAsFactors = FALSE)
utils::write.csv(decision, file.path(OUT, "decision.csv"), row.names = FALSE)

cat("\n== LRN-01 support stress study ==\n")
cat(sprintf("Observed laws with results: %d of %d; minimum completed replicates: %d.\n",
            nrow(required_complete), nrow(laws), decision$achieved_minimum_completed))
cat(sprintf("Primary compatible-set magnitude: log(2); materiality thresholds: mass %.2f and span %.2f.\n",
            SUPPORT_MASS_THRESHOLD, SUPPORT_MASS_THRESHOLD))
cat(sprintf("Flexible excess requires every simultaneous lower bound >= %.2f; not-supported requires every upper bound <= %.2f.\n",
            DECISION$excess_support_lower, DECISION$excess_not_supported_upper))
cat(sprintf("Map success requires sensitivity >= %.2f, specificity >= %.2f, and reduction >= %.2f by simultaneous lower bounds.\n",
            DECISION$map_sensitivity_lower, DECISION$map_specificity_lower,
            DECISION$map_reduction_lower))
cat("No branch is a binary verdict on the full LRN-01 catalog entry.\n")
cat(sprintf("Decision-rule branch: flexible-specific=%s; support-map=%s\n",
            flex_branch, map_branch))
