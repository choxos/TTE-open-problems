## Study 2 (MER-01): performance measures and decision rule.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(file.path(OUT, "raw"), "^scenario-.*\\.rds$", full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))
res <- merge(res, truth[, c("scenario", "estimand", "truth", "truth_mcse")],
             by = c("scenario", "estimand"), all.x = TRUE)

get_est_mcse <- function(x) if (is.list(x)) unname(x[["est"]]) else unname(x[1L])
get_mcse <- function(x) if (is.list(x)) unname(x[["mcse"]]) else unname(x[2L])

## The signature is (est, lower, upper). What stood here inspected
## `formals(perf_becoverage)` and dispatched on what it found, which is a way of
## being wrong that survives review. Shifting each interval by the bias and
## asking whether it covers the truth, which is what the last branch reached
## for, is the same question as asking whether the unshifted interval covers the
## mean estimate: `lo - bias <= truth <= hi - bias` holds exactly when
## `lo <= truth + bias <= hi`, and `truth + bias` is `mean(est)`.
call_becoverage <- function(est, se, lo, hi, truth_value, bias) {
  perf_becoverage(est, lo, hi)
}

group_key <- interaction(res$scenario, res$method, res$analysis_pattern,
                         res$estimand, drop = TRUE)
groups <- split(res, group_key)
perf <- do.call(rbind, lapply(groups, function(d) {
  d <- d[order(d$rep_id), ]
  est <- d$est
  se <- d$se
  tv <- d$truth[1L]
  lo <- d$lo
  hi <- d$hi
  b <- perf_bias(est, tv)
  es <- perf_empse(est)
  ms <- perf_modse(se)
  re <- perf_relerror_modse(est, se)
  mse <- perf_mse(est, tv)
  cv <- perf_coverage(lo, hi, tv)
  bec <- call_becoverage(est, se, lo, hi, tv, get_est_mcse(b))
  rej <- perf_rejection(lo, hi, 0)
  conv <- perf_convergence(est, nrow(d))
  valid <- is.finite(est) & is.finite(se) & is.na(d$fail)
  covered <- valid & lo <= tv & hi >= tv
  data.frame(
    scenario = d$scenario[1L], block = d$block[1L], profile = d$profile[1L],
    accuracy = d$accuracy[1L], nodes = d$nodes[1L],
    validation_n = d$validation_n[1L], specification = d$specification[1L],
    outcome_error = d$outcome_error[1L], benchmark = d$benchmark[1L],
    decision_cell = d$decision_cell[1L], method = d$method[1L],
    analysis_pattern = d$analysis_pattern[1L], estimand = d$estimand[1L],
    truth = tv,
    bias = get_est_mcse(b), bias_mcse = get_mcse(b),
    abs_bias = abs(get_est_mcse(b)),
    empse = get_est_mcse(es), empse_mcse = get_mcse(es),
    modse = get_est_mcse(ms), modse_mcse = get_mcse(ms),
    relerror_modse = get_est_mcse(re), relerror_modse_mcse = get_mcse(re),
    mse = get_est_mcse(mse), mse_mcse = get_mcse(mse),
    coverage = get_est_mcse(cv), coverage_mcse = get_mcse(cv),
    becoverage = get_est_mcse(bec), becoverage_mcse = get_mcse(bec),
    rejection = get_est_mcse(rej), rejection_mcse = get_mcse(rej),
    convergence = get_est_mcse(conv), convergence_mcse = get_mcse(conv),
    failure_as_noncoverage = mean(covered),
    interval_width = mean(hi - lo, na.rm = TRUE),
    ess_g1_median = stats::median(d$ess_g1, na.rm = TRUE),
    ess_g0_median = stats::median(d$ess_g0, na.rm = TRUE),
    median_weight = stats::median(d$median_weight, na.rm = TRUE),
    p99_weight = stats::median(d$p99_weight, na.rm = TRUE),
    adherence_g1 = mean(d$adherence_g1, na.rm = TRUE),
    adherence_g0 = mean(d$adherence_g0, na.rm = TRUE),
    oracle_adherence_g1 = mean(d$oracle_adherence_g1, na.rm = TRUE),
    oracle_adherence_g0 = mean(d$oracle_adherence_g0, na.rm = TRUE),
    censor_change_l = mean(d$censor_change_l, na.rm = TRUE),
    n_used = sum(valid), n_attempted = nrow(d), stringsAsFactors = FALSE)
}))
rownames(perf) <- NULL

## Critique fix: continuous decision statistics receive a simultaneous maximum-t
## multiplier critical value. Coverage and convergence use conservative exact
## binomial intervals. The family alpha of 0.01 is divided across three looks.
alpha_look <- DECISION$family_alpha / length(DECISION$looks)
boot_items <- lapply(groups, function(d) {
  ok <- is.finite(d$est)
  x <- d$est[ok] - d$truth[1L]
  if (length(x) < 2L) return(NULL)
  M <- cbind(bias = x, mse = x^2)
  se <- apply(M, 2L, stats::sd) / sqrt(nrow(M))
  list(M = M, se = se)
})
boot_items <- Filter(Negate(is.null), boot_items)
set.seed(MASTER_SEED + 700001L)
mx <- numeric(MC_BOOT)
for (b in seq_len(MC_BOOT)) {
  zmax <- 0
  for (item in boot_items) {
    g <- sample(c(-1, 1), nrow(item$M), replace = TRUE)
    centered <- sweep(item$M, 2L, colMeans(item$M), "-")
    z <- abs(colSums(centered * g) / nrow(item$M) / item$se)
    z <- z[is.finite(z)]
    if (length(z)) zmax <- max(zmax, z)
  }
  mx[b] <- zmax
}
max_t <- unname(stats::quantile(mx, 1 - alpha_look, names = FALSE))
if (!is.finite(max_t) || max_t <= 0) max_t <- stats::qnorm(1 - alpha_look / 2)
perf$bias_lo <- perf$bias - max_t * perf$bias_mcse
perf$bias_hi <- perf$bias + max_t * perf$bias_mcse
perf$mse_lo <- perf$mse - max_t * perf$mse_mcse
perf$mse_hi <- perf$mse + max_t * perf$mse_mcse

binom_exact <- function(x, n, alpha) {
  if (!is.finite(x) || n <= 0) return(c(NA_real_, NA_real_))
  k <- round(x * n)
  lo <- if (k == 0L) 0 else stats::qbeta(alpha / 2, k, n - k + 1L)
  hi <- if (k == n) 1 else stats::qbeta(1 - alpha / 2, k + 1L, n - k)
  c(lo, hi)
}
alpha_binom <- alpha_look / max(1, 3L * nrow(perf))
cv_ci <- t(mapply(binom_exact, perf$coverage, perf$n_used,
                  MoreArgs = list(alpha = alpha_binom)))
cn_ci <- t(mapply(binom_exact, perf$convergence, perf$n_attempted,
                  MoreArgs = list(alpha = alpha_binom)))
fn_ci <- t(mapply(binom_exact, perf$failure_as_noncoverage, perf$n_attempted,
                  MoreArgs = list(alpha = alpha_binom)))
perf$coverage_lo <- cv_ci[, 1L]; perf$coverage_hi <- cv_ci[, 2L]
perf$convergence_lo <- cn_ci[, 1L]; perf$convergence_hi <- cn_ci[, 2L]
perf$failure_coverage_lo <- fn_ci[, 1L]; perf$failure_coverage_hi <- fn_ci[, 2L]
utils::write.csv(perf, file.path(OUT, "performance.csv"), row.names = FALSE)

nonlinear_ci <- function(X, fun, B = MC_BOOT, alpha = alpha_look) {
  ok <- stats::complete.cases(X)
  X <- as.matrix(X[ok, , drop = FALSE])
  if (nrow(X) < 2L) return(c(est = NA, lo = NA, hi = NA))
  mu <- colMeans(X)
  point <- fun(mu)
  draws <- numeric(B)
  centered <- sweep(X, 2L, mu, "-")
  for (b in seq_len(B)) {
    g <- sample(c(-1, 1), nrow(X), replace = TRUE)
    draws[b] <- fun(mu + colSums(centered * g) / nrow(X))
  }
  q <- unname(stats::quantile(abs(draws - point), 1 - alpha, names = FALSE))
  c(est = point, lo = point - q, hi = point + q)
}

## Paired nonadditivity uses four proxy views of the same latent cohort and the
## same error draws, generated inside each joint-error replicate.
interaction_rows <- list()
decisive_scenarios <- unique(res$scenario[res$decision_cell])
for (sid in decisive_scenarios) {
  for (method in c("exact_filter", "rich")) {
    d <- res[res$scenario == sid & res$method == method &
               res$estimand == "dynamic", c("rep_id", "analysis_pattern", "est")]
    w <- reshape(d, idvar = "rep_id", timevar = "analysis_pattern", direction = "wide")
    needed <- paste0("est.", c("none", "A", "L", "AL"))
    if (!all(needed %in% names(w))) next
    X <- w[, needed]
    names(X) <- c("B0", "BA", "BL", "BAL")
    inter <- nonlinear_ci(X, function(m) m["BAL"] - m["BA"] - m["BL"] + m["B0"])
    truth_value <- truth$truth[truth$scenario == sid & truth$estimand == "dynamic"][1L]
    Xbias <- X
    Xbias$BAL <- Xbias$BAL - truth_value
    comp <- nonlinear_ci(Xbias, function(m) {
      ii <- m["BAL"] - m["BA"] - m["BL"] + m["B0"]
      abs(ii) - 0.25 * abs(m["BAL"])
    })
    s <- res[match(sid, res$scenario), ]
    interaction_rows[[length(interaction_rows) + 1L]] <- data.frame(
      scenario = sid, profile = s$profile, accuracy = s$accuracy, method = method,
      interaction = inter["est"], interaction_lo = inter["lo"], interaction_hi = inter["hi"],
      composite = comp["est"], composite_lo = comp["lo"], composite_hi = comp["hi"],
      stringsAsFactors = FALSE)
  }
}
interactions <- if (length(interaction_rows)) do.call(rbind, interaction_rows) else data.frame()
utils::write.csv(interactions, file.path(OUT, "interactions.csv"), row.names = FALSE)

## Validation qualification compares corrected and rich estimates within each
## replicate. Nonlinear bias and paired MSE contrasts are recomputed in every
## multiplier draw.
qual_rows <- list()
robust_ids <- unique(res$scenario[res$benchmark != ""])
for (sid in robust_ids) {
  d <- res[res$scenario == sid & res$estimand == "dynamic" &
             ((res$method == "corrected") |
                (res$method == "rich" & res$analysis_pattern == "AL")), ]
  cdat <- d[d$method == "corrected", c("rep_id", "est")]
  rdat <- d[d$method == "rich", c("rep_id", "est")]
  names(cdat)[2L] <- "corrected"; names(rdat)[2L] <- "rich"
  z <- merge(cdat, rdat, by = "rep_id")
  tv <- truth$truth[truth$scenario == sid & truth$estimand == "dynamic"][1L]
  gain <- nonlinear_ci(z[, c("corrected", "rich")], function(m)
    abs(m["corrected"] - tv) - 0.5 * abs(m["rich"] - tv))
  mse_diff <- nonlinear_ci(z[, c("corrected", "rich")], function(m) NA_real_)
  md <- (z$corrected - tv)^2 - 1.25 * (z$rich - tv)^2
  md_se <- stats::sd(md) / sqrt(length(md))
  md_point <- mean(md)
  md_ci <- c(md_point - max_t * md_se, md_point + max_t * md_se)
  pc <- perf[perf$scenario == sid & perf$method == "corrected" &
               perf$estimand == "dynamic", ][1L, ]
  larger <- res[res$scenario == sid & res$method == "corrected_4M" &
                  res$estimand == "dynamic", ]
  larger_stable <- if (nrow(larger) < 2L) NA else
    abs(mean(larger$est, na.rm = TRUE) - pc$bias - tv) < 0.001
  qualifies <- is.finite(gain["hi"]) && gain["hi"] < 0 &&
    pc$bias_lo >= -DECISION$key_oracle_bias && pc$bias_hi <= DECISION$key_oracle_bias &&
    pc$coverage_lo >= DECISION$coverage_low && pc$coverage_hi <= DECISION$coverage_high &&
    md_ci[2L] < 0 && pc$convergence_lo >= DECISION$convergence &&
    isTRUE(larger_stable)
  s <- res[match(sid, res$scenario), ]
  qual_rows[[length(qual_rows) + 1L]] <- data.frame(
    scenario = sid, benchmark = s$benchmark, specification = s$specification,
    validation_n = s$validation_n,
    bias_gain = gain["est"], bias_gain_lo = gain["lo"], bias_gain_hi = gain["hi"],
    mse_contrast = md_point, mse_contrast_lo = md_ci[1L], mse_contrast_hi = md_ci[2L],
    larger_m_stable = larger_stable, qualifies = qualifies, stringsAsFactors = FALSE)
}
qualification <- if (length(qual_rows)) do.call(rbind, qual_rows) else data.frame()
utils::write.csv(qualification, file.path(OUT, "correction-qualification.csv"), row.names = FALSE)

size_rows <- lapply(VALIDATION_SIZES, function(nv) {
  q <- qualification[qualification$validation_n == nv, ]
  required <- 2L * length(SPECIFICATIONS)
  data.frame(validation_n = nv, cells_present = nrow(q),
             robust = nrow(q) == required && all(q$qualifies), stringsAsFactors = FALSE)
})
validation_sizes <- do.call(rbind, size_rows)
utils::write.csv(validation_sizes, file.path(OUT, "validation-size.csv"), row.names = FALSE)

## Outcome error remains descriptive and is checked against the symmetric
## attenuation identity. It cannot alter the primary classification.
outcome_rows <- list()
for (sid in unique(res$scenario[res$block == "outcome_component"])) {
  s <- res[match(sid, res$scenario), ]
  base_sid <- unique(res$scenario[res$block == "primary" &
                                    res$profile == "nondifferential" &
                                    res$accuracy == s$accuracy & res$nodes == "AL"])[1L]
  for (method in c("first_order", "rich", "exact_filter")) {
    yrow <- perf[perf$scenario == sid & perf$method == method &
                   perf$analysis_pattern == "AL" & perf$estimand == "dynamic", ][1L, ]
    brow <- perf[perf$scenario == base_sid & perf$method == method &
                   perf$analysis_pattern == "AL" & perf$estimand == "dynamic", ][1L, ]
    expected <- (1 - 2 * (1 - s$accuracy)) * (brow$truth + brow$bias)
    observed <- yrow$truth + yrow$bias
    outcome_rows[[length(outcome_rows) + 1L]] <- data.frame(
      scenario = sid, accuracy = s$accuracy, method = method,
      observed_rd = observed, expected_rd = expected,
      identity_difference = observed - expected, stringsAsFactors = FALSE)
  }
}
outcome_component <- do.call(rbind, outcome_rows)
utils::write.csv(outcome_component, file.path(OUT, "outcome-error.csv"), row.names = FALSE)

metric <- function(sid, method, pattern = NULL) {
  z <- perf[perf$scenario == sid & perf$method == method & perf$estimand == "dynamic", ]
  if (!is.null(pattern)) z <- z[z$analysis_pattern == pattern, ]
  z[1L, , drop = FALSE]
}
inside <- function(lo, hi, a, b) is.finite(lo) && is.finite(hi) && lo >= a && hi <= b
outside <- function(lo, hi, a, b) is.finite(lo) && is.finite(hi) && (hi < a || lo > b)

validity_ok <- TRUE
validity_reasons <- character()
noerr <- unique(res$scenario[res$block %in% c("no_error_core", "no_error_stress")])
for (sid in noerr) {
  s <- res[match(sid, res$scenario), ]
  methods <- c("exact_filter", "oracle")
  if (s$block == "no_error_core") methods <- c(methods, "first_order", "rich")
  if (s$block == "no_error_stress") methods <- c(methods, "rich")
  for (m in methods) {
    p <- if (m == "oracle") "latent" else "none"
    z <- metric(sid, m, p)
    ok <- nrow(z) && inside(z$bias_lo, z$bias_hi,
                            -DECISION$no_error_bias, DECISION$no_error_bias) &&
      inside(z$coverage_lo, z$coverage_hi,
             DECISION$coverage_low, DECISION$coverage_high) &&
      z$convergence_lo >= DECISION$convergence
    if (!isTRUE(ok)) {
      validity_ok <- FALSE
      validity_reasons <- c(validity_reasons, paste("no-error gate", sid, m))
    }
  }
}

real_support <- not_real_support <- logical()
interaction_support <- logical()
for (sid in decisive_scenarios) {
  oracle <- metric(sid, "oracle", "latent")
  oracle_ok <- nrow(oracle) && inside(oracle$bias_lo, oracle$bias_hi,
                                      -DECISION$key_oracle_bias, DECISION$key_oracle_bias) &&
    inside(oracle$coverage_lo, oracle$coverage_hi,
           DECISION$coverage_low, DECISION$coverage_high) &&
    oracle$convergence_lo >= DECISION$convergence &&
    oracle$ess_g1_median > DECISION$minimum_ess &&
    oracle$ess_g0_median > DECISION$minimum_ess
  if (!isTRUE(oracle_ok)) {
    validity_ok <- FALSE
    validity_reasons <- c(validity_reasons, paste("key oracle gate", sid))
  }
  rr <- lapply(c("exact_filter", "rich"), function(m) metric(sid, m, "AL"))
  real_support[as.character(sid)] <- all(vapply(rr, function(z)
    nrow(z) && z$abs_bias >= DECISION$material_bias &&
      outside(z$bias_lo, z$bias_hi, -DECISION$negligible_bias, DECISION$negligible_bias) &&
      z$coverage <= DECISION$material_coverage && z$coverage_hi < DECISION$coverage_low,
    logical(1)))
  ii <- interactions[interactions$scenario == sid & interactions$method == "exact_filter", ]
  interaction_support[as.character(sid)] <- nrow(ii) &&
    outside(ii$interaction_lo, ii$interaction_hi,
            -DECISION$interaction_equivalence, DECISION$interaction_equivalence) &&
    ii$composite_lo > 0
  not_real_support[as.character(sid)] <- all(vapply(rr, function(z)
    nrow(z) && inside(z$bias_lo, z$bias_hi,
                       -DECISION$negligible_bias, DECISION$negligible_bias) &&
      inside(z$coverage_lo, z$coverage_hi,
             DECISION$coverage_low, DECISION$coverage_high), logical(1))) &&
    nrow(ii) && inside(ii$interaction_lo, ii$interaction_hi,
                       -DECISION$interaction_equivalence, DECISION$interaction_equivalence) &&
    ii$composite_hi < 0
}

n_real <- sum(real_support)
n_not_real <- sum(not_real_support)
n_interaction <- sum(interaction_support)
minimum_reps <- min(perf$n_attempted[perf$decision_cell], na.rm = TRUE)
if (SCALED_RUN || minimum_reps < DECISION$looks[1L]) {
  branch <- "UNINFORMATIVE: feasibility-scale run is below the first 1000-replicate decision look"
} else if (!validity_ok || any(perf$convergence[perf$decision_cell] < 0.95)) {
  branch <- "UNINFORMATIVE: at least one required validity, convergence, or support gate failed"
} else if (n_real >= DECISION$required_cells &&
           n_interaction >= DECISION$required_interactions) {
  branch <- "PROBLEM REAL: at least 6 of 8 bias and coverage cells and at least 4 interaction cells passed"
} else if (n_not_real >= DECISION$required_cells) {
  branch <- "PROBLEM NOT REAL: at least 6 of 8 negligible-bias, calibrated-coverage, and negligible-interaction cells passed"
} else {
  branch <- "UNINFORMATIVE: neither prespecified six-of-eight branch was reached"
}
smallest <- validation_sizes$validation_n[validation_sizes$robust]
smallest_text <- if (length(smallest)) as.character(min(smallest)) else
  "no robust size up to 1000 identified"
decision_out <- data.frame(
  validity_ok = validity_ok, real_cells = n_real, not_real_cells = n_not_real,
  interaction_cells = n_interaction, smallest_robust_validation = smallest_text,
  branch = branch, stringsAsFactors = FALSE)
utils::write.csv(decision_out, file.path(OUT, "decision.csv"), row.names = FALSE)

cat("\n== MER-01 simulation summary ==\n")
cat(sprintf("validity gates: %s\n", if (validity_ok) "passed" else "failed"))
cat(sprintf("decisive cells supporting real: %d of 8; threshold 6\n", n_real))
cat(sprintf("decisive cells supporting not real: %d of 8; threshold 6\n", n_not_real))
cat(sprintf("material interaction cells: %d of 8; threshold 4\n", n_interaction))
cat(sprintf("smallest robust validation size: %s\n", smallest_text))
cat(sprintf("numerical thresholds: |bias| >= %.3f, coverage <= %.3f, bias equivalence %.3f, interaction equivalence %.3f\n",
            DECISION$material_bias, DECISION$material_coverage,
            DECISION$negligible_bias, DECISION$interaction_equivalence))
cat(sprintf("DECISION BRANCH: %s\n", branch))
