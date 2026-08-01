## Study 2 (PRO-02): performance measures and registered decision rules.
##
##   Rscript R/05-analyze.R

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(file.path(OUT, "raw"),
                             "^scenario-.*\\.rds$", full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))

truth_keep <- truth[, c("n", "event_target", "effect", "candidate", "c", "h",
                         "truth", "truth_mcse", "truth_draws",
                         "truth_mcse_pass")]
res <- merge(res, truth_keep,
             by = c("n", "event_target", "effect", "candidate", "c", "h"),
             all.x = TRUE, sort = FALSE)
ref <- truth[truth$c == REFERENCE_C & truth$h == REFERENCE_H,
             c("n", "event_target", "effect", "truth")]
names(ref)[names(ref) == "truth"] <- "reference_truth"
res <- merge(res, ref, by = c("n", "event_target", "effect"),
             all.x = TRUE, sort = FALSE)

res$success <- is.na(res$fail) & is.finite(res$est) & is.finite(res$se) &
  res$se > 0 & is.finite(res$truth)
res$lo <- res$est - res$critical * res$se
res$hi <- res$est + res$critical * res$se
res$covered <- res$success & res$lo <= res$truth & res$hi >= res$truth
res$rejected <- res$success & (res$lo > 0 | res$hi < 0)
res$target_movement <- res$truth - res$reference_truth
res$interval_width <- 2 * res$critical * res$se

metric <- function(fun, ...) {
  z <- tryCatch(fun(...), error = function(e) NULL)
  if (is.null(z)) return(c(est = NA_real_, mcse = NA_real_))
  c(est = as.numeric(z[["est"]]), mcse = as.numeric(z[["mcse"]]))
}

## Selected estimands vary by replicate. Shifting estimates and intervals by
## their replicate-specific truths lets the shared performance functions score
## the registered randomly indexed estimand without treating target movement as
## bias.
analysis_rows <- res[res$row_type %in% c("candidate", "selector"), , drop = FALSE]
analysis_rows$group_id <- ifelse(
  analysis_rows$method == "fixed",
  paste("fixed", analysis_rows$candidate, sep = ":"),
  paste(analysis_rows$method, analysis_rows$selector, sep = ":"))
parts <- split(analysis_rows,
               interaction(analysis_rows$scenario, analysis_rows$group_id,
                           drop = TRUE))

perf <- do.call(rbind, lapply(parts, function(d) {
  ok <- d$success
  err <- d$est[ok] - d$truth[ok]
  se <- d$se[ok]
  lo_err <- d$lo[ok] - d$truth[ok]
  hi_err <- d$hi[ok] - d$truth[ok]
  lo_uncond <- ifelse(ok, d$lo - d$truth, 1)
  hi_uncond <- ifelse(ok, d$hi - d$truth, -1)

  b <- metric(perf_bias, err, 0)
  es <- metric(perf_empse, err)
  ms <- metric(perf_modse, se)
  re <- metric(perf_relerror_modse, err, se)
  mse <- metric(perf_mse, err, 0)
  cv <- metric(perf_coverage, lo_uncond, hi_uncond, 0)
  cvc <- metric(perf_coverage, lo_err, hi_err, 0)
  bec <- metric(perf_becoverage, err, se, 0)
  rej <- metric(perf_rejection, d$lo[ok], d$hi[ok], 0)
  conv <- metric(perf_convergence, ifelse(ok, d$est, NA_real_), nrow(d))

  data.frame(
    scenario = d$scenario[1], n = d$n[1], event_target = d$event_target[1],
    event_regime = d$event_regime[1], K = d$K[1], effect = d$effect[1],
    method = d$method[1], selector = d$selector[1],
    candidate = if (d$method[1] == "fixed") d$candidate[1] else NA_character_,
    mean_truth = if (any(ok)) mean(d$truth[ok]) else NA_real_,
    bias = b[["est"]], bias_mcse = b[["mcse"]],
    empse = es[["est"]], empse_mcse = es[["mcse"]],
    modse = ms[["est"]], modse_mcse = ms[["mcse"]],
    relerror_modse = re[["est"]], relerror_modse_mcse = re[["mcse"]],
    mse = mse[["est"]], mse_mcse = mse[["mcse"]],
    coverage = cv[["est"]], coverage_mcse = cv[["mcse"]],
    coverage_conditional = cvc[["est"]], coverage_conditional_mcse = cvc[["mcse"]],
    bias_eliminated_coverage = bec[["est"]],
    bias_eliminated_coverage_mcse = bec[["mcse"]],
    rejection = rej[["est"]], rejection_mcse = rej[["mcse"]],
    convergence = conv[["est"]], convergence_mcse = conv[["mcse"]],
    failure_probability = 1 - conv[["est"]],
    median_width = if (any(ok)) stats::median(d$interval_width[ok]) else NA_real_,
    median_ess1 = if (any(ok)) stats::median(d$ess1[ok]) else NA_real_,
    median_ess0 = if (any(ok)) stats::median(d$ess0[ok]) else NA_real_,
    median_max_weight = if (any(ok)) stats::median(d$max_weight[ok]) else NA_real_,
    n_used = sum(ok), n_attempted = nrow(d),
    stringsAsFactors = FALSE)
}))
rownames(perf) <- NULL
utils::write.csv(perf, file.path(OUT, "performance.csv"), row.names = FALSE)

## Critique fix: every declared candidate enters the calibration gate, without
## a selection-frequency exemption. Failures count as noncoverage.
fixed <- res[res$row_type == "candidate" & res$method == "fixed", , drop = FALSE]
calibration_parts <- split(fixed,
  interaction(fixed$scenario, fixed$candidate, drop = TRUE))
calibration <- do.call(rbind, lapply(calibration_parts, function(d) {
  coverage <- mean(d$covered)
  failure <- mean(!d$success)
  data.frame(
    scenario = d$scenario[1], n = d$n[1], event_target = d$event_target[1],
    K = d$K[1], effect = d$effect[1], candidate = d$candidate[1],
    coverage = coverage,
    coverage_mcse = sqrt(coverage * (1 - coverage) / nrow(d)),
    failure_probability = failure,
    failure_mcse = sqrt(failure * (1 - failure) / nrow(d)),
    truth_mcse = d$truth_mcse[1], truth_draws = d$truth_draws[1],
    n_attempted = nrow(d),
    pass = nrow(d) == N_REP && coverage >= CALIBRATION_RANGE[1] &&
      coverage <= CALIBRATION_RANGE[2] && failure < MAX_FAILURE &&
      isTRUE(d$truth_mcse_pass[1]),
    stringsAsFactors = FALSE)
}))
rownames(calibration) <- NULL
utils::write.csv(calibration, file.path(OUT, "calibration.csv"), row.names = FALSE)

stratified_mean <- function(d, value) {
  cell <- split(d[[value]], d$scenario)
  if (!length(cell) || any(vapply(cell, length, integer(1)) < 2L)) {
    return(c(est = NA_real_, se = NA_real_, cells = length(cell)))
  }
  means <- vapply(cell, mean, numeric(1))
  variances <- vapply(cell, stats::var, numeric(1))
  sizes <- vapply(cell, length, integer(1))
  c(est = mean(means),
    se = sqrt(sum(variances / sizes) / length(cell)^2),
    cells = length(cell))
}

make_family_w <- function(method) {
  d <- res[res$row_type == "selector" & res$method == method &
             res$selector %in% c("workability", "prognostic_high",
                                 "prognostic_low"), , drop = FALSE]
  key <- c("scenario", "replicate", "n", "event_target", "event_regime",
           "K", "effect")
  take <- function(selector, suffix) {
    z <- d[d$selector == selector, c(key, "covered", "success"), drop = FALSE]
    names(z)[names(z) == "covered"] <- paste0("covered_", suffix)
    names(z)[names(z) == "success"] <- paste0("success_", suffix)
    z
  }
  z <- merge(take("workability", "w"), take("prognostic_high", "h"),
             by = key, all = TRUE)
  z <- merge(z, take("prognostic_low", "l"), by = key, all = TRUE)
  z$W <- (as.numeric(z$covered_w) +
            (as.numeric(z$covered_h) + as.numeric(z$covered_l)) / 2) / 2
  z$F <- (as.numeric(!z$success_w) +
            (as.numeric(!z$success_h) + as.numeric(!z$success_l)) / 2) / 2
  z
}

naive_w <- make_family_w("naive")
bonf_w <- make_family_w("bonferroni")
split_w <- make_family_w("split")

## Critique fix: the undefined paired fixed-versus-selected contrast is absent.
## The registered quantities are deficits from 0.95 with a simultaneous
## rectangle that retains within-replicate covariance through W.
deficit_row <- function(label, d) {
  s <- stratified_mean(d, "W")
  deficit <- 0.95 - s[["est"]]
  data.frame(
    estimand = label, coverage = s[["est"]], deficit = deficit,
    mcse = s[["se"]], lower = deficit - GLOBAL_Z * s[["se"]],
    upper = deficit + GLOBAL_Z * s[["se"]], cells = s[["cells"]],
    stringsAsFactors = FALSE)
}
global_deficits <- rbind(
  deficit_row("D_all", naive_w),
  deficit_row("D_nonboundary",
              naive_w[naive_w$event_target %in% c(35L, 140L), , drop = FALSE]),
  deficit_row("D_boundary",
              naive_w[naive_w$event_target == 70L, , drop = FALSE]))
utils::write.csv(global_deficits, file.path(OUT, "global-deficits.csv"),
                 row.names = FALSE)

## Critique fix: fixed-family Bonferroni tail calibration is evaluated before
## selected Bonferroni coverage is interpreted.
family_parts <- split(fixed, interaction(fixed$scenario, fixed$replicate,
                                         drop = TRUE))
family_rep <- do.call(rbind, lapply(family_parts, function(d) {
  q <- bonferroni_critical(d$K[1])
  ok <- d$success
  covered <- all(ok) && all(abs(d$est - d$truth) <= q * d$se)
  data.frame(
    scenario = d$scenario[1], replicate = d$replicate[1], n = d$n[1],
    event_target = d$event_target[1], K = d$K[1], effect = d$effect[1],
    family_covered = as.numeric(covered), family_failed = as.numeric(!all(ok)),
    stringsAsFactors = FALSE)
}))
family_summary <- do.call(rbind, lapply(split(family_rep, family_rep$scenario),
                                       function(d) {
  p <- mean(d$family_covered)
  f <- mean(d$family_failed)
  data.frame(
    scenario = d$scenario[1], n = d$n[1], event_target = d$event_target[1],
    K = d$K[1], effect = d$effect[1], coverage = p,
    coverage_mcse = sqrt(p * (1 - p) / nrow(d)),
    failure_probability = f,
    n_attempted = nrow(d), stringsAsFactors = FALSE)
}))
utils::write.csv(family_summary, file.path(OUT, "familywise-calibration.csv"),
                 row.names = FALSE)

fixed_global <- stratified_mean(family_rep, "family_covered")
bonf_global <- stratified_mean(bonf_w, "W")
bonf_failure <- stratified_mean(bonf_w, "F")
split_global <- stratified_mean(split_w, "W")
split_failure <- stratified_mean(split_w, "F")

fixed_lower <- fixed_global[["est"]] - GLOBAL_Z * fixed_global[["se"]]
fixed_upper <- fixed_global[["est"]] + GLOBAL_Z * fixed_global[["se"]]
bonf_lower <- bonf_global[["est"]] - GLOBAL_Z * bonf_global[["se"]]
bonf_upper <- bonf_global[["est"]] + GLOBAL_Z * bonf_global[["se"]]
split_lower <- split_global[["est"]] - Z_95 * split_global[["se"]]
split_upper <- split_global[["est"]] + Z_95 * split_global[["se"]]

bonf_class <- if (is.finite(fixed_lower) && is.finite(bonf_lower) &&
                    fixed_lower > 0.93 && bonf_lower > 0.93 &&
                    bonf_failure[["est"]] < 0.05) {
  "adequate"
} else if (is.finite(fixed_upper) && is.finite(bonf_upper) &&
           (fixed_upper < 0.93 || bonf_upper < 0.93)) {
  "inadequate"
} else "inconclusive"

split_class <- if (is.finite(split_lower) && split_lower > 0.93 &&
                     split_failure[["est"]] < 0.05) {
  "adequate"
} else if (is.finite(split_upper) && split_upper < 0.93) {
  "inadequate"
} else "inconclusive"

remedies <- data.frame(
  policy = c("fixed_family_bonferroni", "selected_bonferroni", "sample_split"),
  coverage = c(fixed_global[["est"]], bonf_global[["est"]], split_global[["est"]]),
  mcse = c(fixed_global[["se"]], bonf_global[["se"]], split_global[["se"]]),
  lower = c(fixed_lower, bonf_lower, split_lower),
  upper = c(fixed_upper, bonf_upper, split_upper),
  failure_probability = c(mean(family_rep$family_failed),
                          bonf_failure[["est"]], split_failure[["est"]]),
  classification = c("calibration gate", bonf_class, split_class),
  stringsAsFactors = FALSE)
utils::write.csv(remedies, file.path(OUT, "remedy-performance.csv"),
                 row.names = FALSE)

selector_rows <- res[res$row_type == "selector", , drop = FALSE]
selector_rows$candidate_label <- ifelse(is.na(selector_rows$candidate),
                                        "none", selector_rows$candidate)
selection_parts <- split(selector_rows,
  interaction(selector_rows$scenario, selector_rows$method,
              selector_rows$selector, selector_rows$candidate_label, drop = TRUE))
selection_frequency <- do.call(rbind, lapply(selection_parts, function(d) {
  denominator <- sum(selector_rows$scenario == d$scenario[1] &
                       selector_rows$method == d$method[1] &
                       selector_rows$selector == d$selector[1])
  data.frame(
    scenario = d$scenario[1], n = d$n[1], event_target = d$event_target[1],
    K = d$K[1], effect = d$effect[1], method = d$method[1],
    selector = d$selector[1], candidate = d$candidate_label[1],
    frequency = nrow(d) / denominator, count = nrow(d), denominator = denominator,
    stringsAsFactors = FALSE)
}))
utils::write.csv(selection_frequency, file.path(OUT, "selection-frequency.csv"),
                 row.names = FALSE)

target_parts <- split(selector_rows,
  interaction(selector_rows$scenario, selector_rows$method,
              selector_rows$selector, drop = TRUE))
target_summary <- do.call(rbind, lapply(target_parts, function(d) {
  ok <- is.finite(d$target_movement)
  data.frame(
    scenario = d$scenario[1], n = d$n[1], event_target = d$event_target[1],
    K = d$K[1], effect = d$effect[1], method = d$method[1],
    selector = d$selector[1],
    mean_target_movement = if (any(ok)) mean(d$target_movement[ok]) else NA_real_,
    probability_abs_gt_001 = if (any(ok)) mean(abs(d$target_movement[ok]) > 0.01) else NA_real_,
    stringsAsFactors = FALSE)
}))
utils::write.csv(target_summary, file.path(OUT, "target-movement.csv"),
                 row.names = FALSE)

fixed_width <- fixed[, c("scenario", "replicate", "candidate", "interval_width")]
names(fixed_width)[4] <- "fixed_width"
split_rows <- selector_rows[selector_rows$method == "split", , drop = FALSE]
width_pairs <- merge(split_rows, fixed_width,
                     by = c("scenario", "replicate", "candidate"), all.x = TRUE)
width_pairs$width_ratio <- width_pairs$interval_width / width_pairs$fixed_width
width_summary <- do.call(rbind, lapply(split(width_pairs,
  interaction(width_pairs$scenario, width_pairs$selector, drop = TRUE)), function(d) {
  z <- d$width_ratio[is.finite(d$width_ratio)]
  data.frame(
    scenario = d$scenario[1], selector = d$selector[1],
    median_within_candidate_width_ratio = if (length(z)) stats::median(z) else NA_real_,
    q25 = if (length(z)) stats::quantile(z, 0.25) else NA_real_,
    q75 = if (length(z)) stats::quantile(z, 0.75) else NA_real_,
    n = length(z), stringsAsFactors = FALSE)
}))
utils::write.csv(width_summary, file.path(OUT, "width-comparisons.csv"),
                 row.names = FALSE)

mv <- res[res$row_type == "multiverse", c("scenario", "replicate",
                                           "mv_range", "mv_iqr", "mv_std_range")]
naive_pred <- selector_rows[selector_rows$method == "naive" &
  selector_rows$selector %in% c("workability", "prognostic_high", "prognostic_low"),
  c("scenario", "replicate", "selector", "covered")]
pred <- merge(naive_pred, mv, by = c("scenario", "replicate"), all.x = TRUE)
pred$noncoverage <- as.numeric(!pred$covered)
pred$range_category <- ifelse(pred$mv_std_range < 1, "below_1",
                              ifelse(pred$mv_std_range <= 2, "1_through_2", "above_2"))
auc_value <- function(score, outcome) {
  ok <- is.finite(score) & !is.na(outcome)
  score <- score[ok]
  outcome <- outcome[ok]
  n1 <- sum(outcome == 1)
  n0 <- sum(outcome == 0)
  if (!n1 || !n0) return(NA_real_)
  r <- rank(score, ties.method = "average")
  (sum(r[outcome == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
prediction_summary <- do.call(rbind, lapply(split(pred, pred$selector), function(d) {
  data.frame(selector = d$selector[1],
             auc = auc_value(d$mv_std_range, d$noncoverage),
             n = sum(is.finite(d$mv_std_range)), stringsAsFactors = FALSE)
}))
risk_summary <- do.call(rbind, lapply(split(pred,
  interaction(pred$selector, pred$range_category, drop = TRUE)), function(d) {
  data.frame(selector = d$selector[1], category = d$range_category[1],
             noncoverage_risk = mean(d$noncoverage), n = nrow(d),
             stringsAsFactors = FALSE)
}))
utils::write.csv(prediction_summary, file.path(OUT, "multiverse-auc.csv"),
                 row.names = FALSE)
utils::write.csv(risk_summary, file.path(OUT, "multiverse-risk.csv"),
                 row.names = FALSE)

## Empirical candidate correlation matrices and the eigenvalue participation
## ratio as a transparent effective-library-size summary.
cor_rows <- list()
eff_rows <- list()
for (sid in sort(unique(fixed$scenario))) {
  d <- fixed[fixed$scenario == sid, c("replicate", "candidate", "est", "success")]
  d$est[!d$success] <- NA_real_
  wide <- reshape(d[, c("replicate", "candidate", "est")],
                  idvar = "replicate", timevar = "candidate", direction = "wide")
  mat <- as.matrix(wide[, setdiff(names(wide), "replicate"), drop = FALSE])
  colnames(mat) <- sub("^est\\.", "", colnames(mat))
  cm <- stats::cor(mat, use = "pairwise.complete.obs")
  grid <- expand.grid(candidate_1 = colnames(cm), candidate_2 = colnames(cm),
                      stringsAsFactors = FALSE)
  grid$correlation <- cm[cbind(match(grid$candidate_1, rownames(cm)),
                               match(grid$candidate_2, colnames(cm)))]
  grid$scenario <- sid
  cor_rows[[length(cor_rows) + 1L]] <- grid
  ev <- eigen(cm, symmetric = TRUE, only.values = TRUE)$values
  ev <- pmax(ev, 0)
  eff_rows[[length(eff_rows) + 1L]] <- data.frame(
    scenario = sid, K = ncol(cm),
    effective_library_size = sum(ev)^2 / sum(ev^2),
    stringsAsFactors = FALSE)
}
utils::write.csv(do.call(rbind, cor_rows),
                 file.path(OUT, "candidate-correlations.csv"), row.names = FALSE)
utils::write.csv(do.call(rbind, eff_rows),
                 file.path(OUT, "effective-library-size.csv"), row.names = FALSE)

expected_calibration_rows <- sum(vapply(seq_len(nrow(build_scenarios())),
                                        function(i) build_scenarios()$K[i], integer(1)))
complete_run <- length(unique(res$scenario)) == nrow(build_scenarios()) &&
  all(vapply(split(res$replicate, res$scenario),
             function(x) length(unique(x)) == N_REP, logical(1)))
calibration_complete <- nrow(calibration) == expected_calibration_rows &&
  all(calibration$n_attempted == N_REP)
calibration_pass <- calibration_complete && all(calibration$pass)

all_row <- global_deficits[global_deficits$estimand == "D_all", ]
nonboundary_row <- global_deficits[global_deficits$estimand == "D_nonboundary", ]

## Critique fix: correction success is classified separately and cannot alter
## the substantive naive-coverage decision.
if (!complete_run || !calibration_pass ||
    !all(is.finite(c(all_row$lower, all_row$upper,
                     nonboundary_row$lower, nonboundary_row$upper)))) {
  branch <- "MIXED OR UNINFORMATIVE: the complete-run or fixed-candidate calibration gate failed"
} else if (all_row$lower > MATERIAL_DEFICIT &&
           nonboundary_row$lower > MATERIAL_DEFICIT) {
  branch <- "MATERIALLY REAL: both simultaneous deficit lower bounds exceed 0.02"
} else if (all_row$upper < MATERIAL_DEFICIT &&
           nonboundary_row$upper < MATERIAL_DEFICIT) {
  branch <- "NOT MATERIALLY REAL: both simultaneous deficit upper bounds are below 0.02"
} else {
  branch <- "MIXED OR UNINFORMATIVE: at least one simultaneous interval intersects 0.02"
}

cat("\n== fixed-candidate calibration gate ==\n")
cat(sprintf("  complete run: %s\n", complete_run))
cat(sprintf("  candidates passing all thresholds: %d/%d\n",
            sum(calibration$pass), nrow(calibration)))
cat(sprintf("  coverage range: %.3f to %.3f\n",
            min(calibration$coverage), max(calibration$coverage)))
cat(sprintf("  maximum failure probability: %.3f\n",
            max(calibration$failure_probability)))
cat(sprintf("  maximum truth MCSE: %.7f\n", max(calibration$truth_mcse)))

cat("\n== registered global naive deficits ==\n")
for (i in seq_len(nrow(global_deficits))) {
  d <- global_deficits[i, ]
  cat(sprintf("  %s: deficit %.4f, simultaneous interval %.4f to %.4f\n",
              d$estimand, d$deficit, d$lower, d$upper))
}

cat("\n== separately classified policies ==\n")
cat(sprintf("  Bonferroni implementation: %s\n", bonf_class))
cat(sprintf("  sample-splitting policy: %s\n", split_class))
cat(sprintf("\nDECISION RULE BRANCH: %s\n", branch))
