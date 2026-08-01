## Study SEQ-01: performance measures and prespecified decision branches.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(file.path(OUT, "raw"), "^scenario-[0-9]+\\.rds$",
                             full.names = TRUE))
stopifnot(length(raw_files) == 12L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))
scenarios <- build_scenarios()
for (nm in setdiff(names(scenarios), "scenario"))
  res[[nm]] <- scenarios[[nm]][match(res$scenario, scenarios$scenario)]

truth_target <- rbind(
  data.frame(scenario = truth$curves$scenario, estimand = "rd_k",
             start = truth$curves$start, true = truth$curves$rd),
  data.frame(scenario = truth$scenarios$scenario, estimand = "theta_equal",
             start = NA_integer_, true = truth$scenarios$theta_equal),
  data.frame(scenario = truth$scenarios$scenario, estimand = "theta_pt",
             start = NA_integer_, true = truth$scenarios$theta_pt)
)
res$.start_key <- ifelse(is.na(res$start), -1L, res$start)
truth_target$.start_key <- ifelse(is.na(truth_target$start), -1L, truth_target$start)
res <- merge(res, truth_target[, c("scenario", "estimand", ".start_key", "true")],
             by = c("scenario", "estimand", ".start_key"), all.x = TRUE,
             sort = FALSE)

metric_est <- function(x) if (is.list(x)) unname(x$est) else unname(x)
call_becoverage <- function(est, se, lo, hi, truth_value) {
  candidates <- list(
    list(est, se, truth_value),
    list(lo, hi, truth_value, mean(est, na.rm = TRUE) - truth_value),
    list(lo, hi, truth_value)
  )
  for (a in candidates) {
    z <- try(do.call(perf_becoverage, a), silent = TRUE)
    if (!inherits(z, "try-error")) return(z)
  }
  list(est = NA_real_, mcse = NA_real_)
}

parts <- split(res, interaction(res$scenario, res$method, res$estimand,
                                res$.start_key, drop = TRUE))
performance <- do.call(rbind, lapply(parts, function(d) {
  est <- d$est
  se <- d$se
  tv <- d$true[1]
  ok <- is.finite(est) & is.finite(se) & is.finite(d$lo) & is.finite(d$hi)
  b <- perf_bias(est, tv)
  es <- perf_empse(est)
  ms <- perf_modse(se)
  re <- perf_relerror_modse(est, se)
  mse <- perf_mse(est, tv)
  cv <- perf_coverage(d$lo, d$hi, tv)
  bec <- call_becoverage(est, se, d$lo, d$hi, tv)
  rj <- perf_rejection(d$lo, d$hi, 0)
  cg <- perf_convergence(est, nrow(d))
  data.frame(
    scenario = d$scenario[1], method = d$method[1], estimand = d$estimand[1],
    start = if (d$.start_key[1] < 0) NA_integer_ else d$.start_key[1],
    truth = tv, bias = metric_est(b), bias_mcse = b$mcse,
    empse = metric_est(es), empse_mcse = es$mcse,
    modse = metric_est(ms), modse_mcse = ms$mcse,
    relerror_modse = metric_est(re), relerror_modse_mcse = re$mcse,
    mse = metric_est(mse), mse_mcse = mse$mcse,
    coverage = metric_est(cv), coverage_mcse = cv$mcse,
    becoverage = metric_est(bec), becoverage_mcse = bec$mcse,
    rejection = metric_est(rj), rejection_mcse = rj$mcse,
    convergence = metric_est(cg), n_used = sum(ok), n_attempted = nrow(d),
    fixed_modse = mean(d$fixed_se, na.rm = TRUE),
    fixed_to_linearized = mean(d$fixed_se, na.rm = TRUE) /
      mean(d$se, na.rm = TRUE),
    bootstrap_to_linearized = mean(d$boot_se, na.rm = TRUE) /
      mean(d$se, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))
rownames(performance) <- NULL
performance <- merge(performance, scenarios, by = "scenario", sort = TRUE)
utils::write.csv(performance, file.path(OUT, "performance.csv"), row.names = FALSE)

trial_specific <- performance[performance$estimand == "rd_k" &
                                performance$method != "standalone_12", ]
utils::write.csv(trial_specific, file.path(OUT, "trial-specific.csv"), row.names = FALSE)

## Critique fix: restricted-model sampling bias is separated from the model's
## population projection discrepancy relative to theta_equal.
proj <- merge(
  performance[performance$estimand == "theta_equal" &
                performance$method %in% PROJECTION_METHODS, ],
  truth$projections,
  by = c("scenario", "method"), all.x = TRUE
)
proj$projection_minus_theta_equal <- proj$projection - proj$truth
proj$sampling_bias_to_projection <- proj$bias - proj$projection_minus_theta_equal
utils::write.csv(proj, file.path(OUT, "projections.csv"), row.names = FALSE)

curve_rep <- res[res$estimand == "rd_k" & res$method != "standalone_12", ]
curve_metrics <- do.call(rbind, lapply(
  split(curve_rep, interaction(curve_rep$scenario, curve_rep$method,
                               curve_rep$replicate_id, drop = TRUE)),
  function(d) data.frame(
    scenario = d$scenario[1], method = d$method[1],
    replicate_id = d$replicate_id[1],
    curve_rmse = if (all(is.finite(d$est))) sqrt(mean((d$est - d$true)^2)) else NA_real_,
    curve_max_error = if (all(is.finite(d$est))) max(abs(d$est - d$true)) else NA_real_,
    fail = if (all(is.finite(d$est))) NA_character_ else "incomplete-curve",
    stringsAsFactors = FALSE
  )
))
utils::write.csv(curve_metrics, file.path(OUT, "curve-performance.csv"), row.names = FALSE)

get_rows <- function(s, method, estimand = "theta_equal", start = NA_integer_) {
  z <- res$scenario == s & res$method == method & res$estimand == estimand
  if (!is.na(start)) z <- z & res$.start_key == start
  res[z, , drop = FALSE]
}

stores <- vector("list", 12L)
point <- numeric()
calendar_delta <- rep(NA_real_, 12L)
for (s in seq_len(12L)) {
  c0 <- get_rows(s, "equal_common")
  f0 <- get_rows(s, "equal_flexible")
  cf <- merge(c0[, c("replicate_id", "est", "lo", "hi", "min_ess")],
              f0[, c("replicate_id", "est", "lo", "hi", "diagnostic",
                      "homogeneity_p", "min_ess")],
              by = "replicate_id", suffixes = c("_common", "_flexible"))
  cf <- cf[is.finite(cf$est_common) & is.finite(cf$est_flexible) &
             is.finite(cf$lo_common) & is.finite(cf$hi_common) &
             is.finite(cf$lo_flexible) & is.finite(cf$hi_flexible), ]

  om <- get_rows(s, "calendar_omitted")
  qu <- get_rows(s, "calendar_quadratic")
  fl <- get_rows(s, "equal_flexible")
  ab <- Reduce(function(x, y) merge(x, y, by = "replicate_id"), list(
    om[, c("replicate_id", "est", "ablation_valid")],
    qu[, c("replicate_id", "est")], fl[, c("replicate_id", "est")]
  ))
  names(ab) <- c("replicate_id", "est_omit", "ablation_valid",
                 "est_quad", "est_flex")
  ab <- ab[ab$ablation_valid & apply(ab[, c("est_omit", "est_quad", "est_flex")],
                                     1L, function(x) all(is.finite(x))), ]

  pf <- get_rows(s, "equal_flexible", "rd_k", 12L)
  st <- get_rows(s, "standalone_12", "rd_k", 12L)
  ef <- merge(pf[, c("replicate_id", "est")], st[, c("replicate_id", "est")],
              by = "replicate_id", suffixes = c("_pooled", "_standalone"))
  ef <- ef[is.finite(ef$est_pooled) & is.finite(ef$est_standalone), ]

  tv <- truth$scenarios$theta_equal[truth$scenarios$scenario == s]
  rd12 <- truth$curves$rd[truth$curves$scenario == s & truth$curves$start == 12L]
  stores[[s]] <- list(cf = cf, ab = ab, ef = ef, theta = tv, rd12 = rd12)
  point[sprintf("common_bias_s%02d", s)] <- mean(cf$est_common) - tv
  point[sprintf("common_cov_s%02d", s)] <- mean(cf$lo_common <= tv & cf$hi_common >= tv)
  point[sprintf("flex_bias_s%02d", s)] <- mean(cf$est_flexible) - tv
  point[sprintf("flex_cov_s%02d", s)] <- mean(cf$lo_flexible <= tv & cf$hi_flexible >= tv)
  point[sprintf("omit_bias_s%02d", s)] <- mean(ab$est_omit) - tv
  point[sprintf("quad_bias_s%02d", s)] <- mean(ab$est_quad) - tv
  point[sprintf("eff_varratio_s%02d", s)] <- stats::var(ef$est_pooled) /
    stats::var(ef$est_standalone)
  calendar_delta[s] <- mean(ab$est_omit - ab$est_flex)
}

H <- truth$scenarios$scenario[truth$scenarios$truth_class == "material"]
N <- truth$scenarios$scenario[truth$scenarios$truth_class == "near"]
pos_rate <- vapply(seq_len(12L), function(s) {
  d <- stores[[s]]$cf
  mean(d$diagnostic == "positive", na.rm = TRUE)
}, numeric(1))
point["diagnostic_sensitivity"] <- if (length(H)) mean(pos_rate[H]) else NA_real_
point["diagnostic_specificity"] <- if (length(N)) mean(1 - pos_rate[N]) else NA_real_

calendar_interaction <- function(values, h_key) {
  ids <- scenarios$scenario[scenarios$h_key == h_key]
  cell <- function(a, b) values[scenarios$scenario[scenarios$h_key == h_key &
                                                    scenarios$a == a & scenarios$b == b]]
  cell(0.80, 0.35) - cell(0.80, 0) - cell(0, 0.35) + cell(0, 0)
}
for (h in H_KEYS)
  point[paste0("calendar_interaction_", h)] <- calendar_interaction(calendar_delta, h)

## Two-layer resampling uses paired replicate samples and independent truth-chunk
## samples. The max-t family is frozen by the names in point.
B <- N_METRIC_BOOT
truth_draw <- matrix(NA_real_, nrow = 12L, ncol = B)
for (s in seq_len(12L)) {
  chunks <- truth$chunks[[sprintf("scenario-%03d", s)]]
  nc <- length(chunks)
  E <- do.call(rbind, lapply(chunks, `[[`, "eligible"))
  Y1 <- do.call(rbind, lapply(chunks, `[[`, "event1"))
  Y0 <- do.call(rbind, lapply(chunks, `[[`, "event0"))
  counts <- t(replicate(B, tabulate(sample.int(nc, nc, replace = TRUE), nbins = nc)))
  Eb <- counts %*% E
  truth_draw[s, ] <- rowMeans((counts %*% Y1) / Eb - (counts %*% Y0) / Eb)
}

boot <- matrix(NA_real_, nrow = B, ncol = length(point),
               dimnames = list(NULL, names(point)))
set.seed(MASTER_SEED + 900000L)
for (b in seq_len(B)) {
  diag_rate <- rep(NA_real_, 12L)
  cal_delta_b <- rep(NA_real_, 12L)
  for (s in seq_len(12L)) {
    st <- stores[[s]]
    tv <- truth_draw[s, b]
    ic <- sample.int(nrow(st$cf), nrow(st$cf), replace = TRUE)
    dc <- st$cf[ic, ]
    boot[b, sprintf("common_bias_s%02d", s)] <- mean(dc$est_common) - tv
    boot[b, sprintf("common_cov_s%02d", s)] <-
      mean(dc$lo_common <= tv & dc$hi_common >= tv)
    boot[b, sprintf("flex_bias_s%02d", s)] <- mean(dc$est_flexible) - tv
    boot[b, sprintf("flex_cov_s%02d", s)] <-
      mean(dc$lo_flexible <= tv & dc$hi_flexible >= tv)
    diag_rate[s] <- mean(dc$diagnostic == "positive", na.rm = TRUE)

    ia <- sample.int(nrow(st$ab), nrow(st$ab), replace = TRUE)
    da <- st$ab[ia, ]
    boot[b, sprintf("omit_bias_s%02d", s)] <- mean(da$est_omit) - tv
    boot[b, sprintf("quad_bias_s%02d", s)] <- mean(da$est_quad) - tv
    cal_delta_b[s] <- mean(da$est_omit - da$est_flex)

    ie <- sample.int(nrow(st$ef), nrow(st$ef), replace = TRUE)
    de <- st$ef[ie, ]
    boot[b, sprintf("eff_varratio_s%02d", s)] <- stats::var(de$est_pooled) /
      stats::var(de$est_standalone)
  }
  boot[b, "diagnostic_sensitivity"] <- if (length(H)) mean(diag_rate[H]) else NA_real_
  boot[b, "diagnostic_specificity"] <- if (length(N)) mean(1 - diag_rate[N]) else NA_real_
  for (h in H_KEYS)
    boot[b, paste0("calendar_interaction_", h)] <- calendar_interaction(cal_delta_b, h)
}

mse <- apply(boot, 2L, stats::sd, na.rm = TRUE)
Z <- sweep(boot, 2L, point, "-")
nz <- is.finite(mse) & mse > 0
Z[, nz] <- sweep(Z[, nz, drop = FALSE], 2L, mse[nz], "/")
Z[, !nz] <- 0
critical_index <- min(B, ceiling(0.95 * (B + 1L)))
critical <- sort(apply(abs(Z), 1L, max, na.rm = TRUE))[critical_index]
manifest <- data.frame(
  metric = names(point), estimate = unname(point), bootstrap_se = mse,
  lower = ifelse(nz, point - critical * mse, point),
  upper = ifelse(nz, point + critical * mse, point),
  stringsAsFactors = FALSE
)
utils::write.csv(manifest, file.path(OUT, "decision-manifest.csv"), row.names = FALSE)

lookup <- function(name, field) manifest[[field]][match(name, manifest$metric)]
abs_bounds <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return(c(lower = NA_real_, upper = NA_real_))
  if (lo <= 0 && hi >= 0) {
    c(lower = 0, upper = max(abs(lo), abs(hi)))
  } else c(lower = min(abs(lo), abs(hi)), upper = max(abs(lo), abs(hi)))
}
status <- matrix("indeterminate", nrow = 12L, ncol = 2L,
                 dimnames = list(seq_len(12L), c("common", "flexible")))
for (s in seq_len(12L)) for (m in c("common", "flex")) {
  bb <- abs_bounds(lookup(sprintf("%s_bias_s%02d", m, s), "lower"),
                   lookup(sprintf("%s_bias_s%02d", m, s), "upper"))
  cl <- lookup(sprintf("%s_cov_s%02d", m, s), "lower")
  cu <- lookup(sprintf("%s_cov_s%02d", m, s), "upper")
  if (is.finite(bb["upper"]) && bb["upper"] <= BIAS_ADEQUATE &&
      is.finite(cl) && cl >= COVERAGE_ADEQUATE) status[s, ifelse(m == "common", 1, 2)] <- "adequate"
  if ((is.finite(bb["lower"]) && bb["lower"] >= BIAS_INADEQUATE) ||
      (is.finite(cu) && cu <= COVERAGE_INADEQUATE))
    status[s, ifelse(m == "common", 1, 2)] <- "inadequate"
}

calibration <- do.call(rbind, lapply(which(scenarios$sentinel), function(s) {
  do.call(rbind, lapply(c("equal_common", "equal_flexible"), function(m) {
    d <- get_rows(s, m)
    d <- d[is.finite(d$boot_lo) & is.finite(d$boot_hi) &
             d$boot_success >= MIN_PERSON_BOOT, ]
    tv <- truth$scenarios$theta_equal[truth$scenarios$scenario == s]
    data.frame(
      scenario = s, method = m, n = nrow(d),
      linearized_coverage = mean(d$lo <= tv & d$hi >= tv),
      bootstrap_coverage = mean(d$boot_lo <= tv & d$boot_hi >= tv),
      difference = mean((d$boot_lo <= tv & d$boot_hi >= tv) -
                          (d$lo <= tv & d$hi >= tv)),
      se_ratio = mean(d$boot_se / d$se), stringsAsFactors = FALSE
    )
  }))
}))
utils::write.csv(calibration, file.path(OUT, "bootstrap-calibration.csv"), row.names = FALSE)
calibration_suspend <- any(calibration$n < MIN_CALIB_REP) ||
  any(abs(calibration$difference) > 0.02, na.rm = TRUE)

valid_cf <- vapply(stores, function(x) nrow(x$cf), integer(1))
ess_bad <- vapply(seq_len(12L), function(s) {
  d <- stores[[s]]$cf
  mean(pmin(d$min_ess_common, d$min_ess_flexible) < ESS_MIN, na.rm = TRUE) > 0.10
}, logical(1))
core_uninformative <- length(H) < 3L || length(N) < 2L ||
  any(valid_cf[c(H, N)] < MIN_VALID) || any(ess_bad[c(H, N)]) ||
  calibration_suspend
reqH <- ceiling(2 * length(H) / 3)
reqN <- ceiling(2 * length(N) / 3)

if (core_uninformative) {

  pooling_branch <- "uninformative"

} else {
  degrade <- sum(status[H, "common"] == "inadequate" &
                   status[H, "flexible"] == "adequate") >= reqH &&
    sum(status[N, "common"] == "adequate" &
          status[N, "flexible"] == "adequate") >= reqN
  accurate <- sum(status[H, "common"] == "adequate" &
                    status[H, "flexible"] == "adequate") >= reqH &&
    sum(status[N, "common"] == "adequate" &
          status[N, "flexible"] == "adequate") >= reqN
  pooling_branch <- if (degrade) "common-effect restriction materially degrades equal-start averaging under the imposed DGM" else
    if (accurate) "accurate averaging despite heterogeneity" else "indeterminate"
}

sens_lo <- lookup("diagnostic_sensitivity", "lower")
sens_hi <- lookup("diagnostic_sensitivity", "upper")
spec_lo <- lookup("diagnostic_specificity", "lower")
spec_hi <- lookup("diagnostic_specificity", "upper")
diagnostic_branch <- if (length(H) < 3L || length(N) < 2L || calibration_suspend) "uninformative" else
  if (sens_lo >= DIAG_SENS_ADEQUATE && spec_lo >= DIAG_SPEC_ADEQUATE) "adequate" else
    if (sens_hi <= DIAG_SENS_INADEQUATE || spec_hi <= DIAG_SPEC_INADEQUATE) "inadequate" else
      "inconclusive"

eff_retained <- sum(vapply(N, function(s)
  lookup(sprintf("eff_varratio_s%02d", s), "upper") < 1, logical(1)))
eff_lost <- sum(vapply(N, function(s)
  lookup(sprintf("eff_varratio_s%02d", s), "lower") >= 1, logical(1)))
efficiency_branch <- if (length(N) < 2L || any(vapply(N, function(s) nrow(stores[[s]]$ef) < MIN_VALID,
                                                       logical(1)))) "uninformative" else
  if (eff_retained >= reqN) "pooling efficiency retained" else
    if (eff_lost >= reqN) "pooling efficiency not retained" else "indeterminate"

cal_bounds <- do.call(rbind, lapply(H_KEYS, function(h) {
  nm <- paste0("calendar_interaction_", h)
  ab <- abs_bounds(lookup(nm, "lower"), lookup(nm, "upper"))
  data.frame(h_key = h, interaction = lookup(nm, "estimate"),
             abs_lower = ab["lower"], abs_upper = ab["upper"])
}))
flex_ok_cells <- vapply(H_KEYS, function(h) {
  ids <- scenarios$scenario[scenarios$h_key == h]
  all(status[ids, "flexible"] == "adequate")
}, logical(1))
calendar_branch <- if (calibration_suspend) "uninformative" else
  if (sum(cal_bounds$abs_lower > CALENDAR_CONSEQUENTIAL & flex_ok_cells) >= 2L)
    "calendar omission consequential under the imposed DGM" else
      if (all(cal_bounds$abs_upper < CALENDAR_NEGLIGIBLE) && all(flex_ok_cells))
        "calendar omission not consequential within this DGM" else "indeterminate"

calendar_output <- merge(
  performance[performance$estimand == "theta_equal" &
                performance$method %in% c("calendar_omitted", "calendar_quadratic",
                                          "equal_flexible"), ],
  truth$scenarios[, c("scenario", "theta_equal")], by = "scenario"
)
utils::write.csv(calendar_output, file.path(OUT, "calendar-ablation.csv"), row.names = FALSE)
utils::write.csv(cal_bounds, file.path(OUT, "calendar-interactions.csv"), row.names = FALSE)

diagnostics <- data.frame(
  scenario = seq_len(12L), truth_class = truth$scenarios$truth_class,
  positive_rate = pos_rate,
  exact_rejection = vapply(seq_len(12L), function(s) {
    d <- stores[[s]]$cf
    mean(d$homogeneity_p < 0.05, na.rm = TRUE)
  }, numeric(1)),
  indeterminate_rate = vapply(seq_len(12L), function(s) {
    d <- stores[[s]]$cf
    mean(d$diagnostic == "indeterminate", na.rm = TRUE)
  }, numeric(1)), stringsAsFactors = FALSE
)
utils::write.csv(diagnostics, file.path(OUT, "diagnostics.csv"), row.names = FALSE)

efficiency <- data.frame(
  scenario = seq_len(12L), truth_class = truth$scenarios$truth_class,
  variance_ratio = vapply(seq_len(12L), function(s)
    point[sprintf("eff_varratio_s%02d", s)], numeric(1)),
  lower = vapply(seq_len(12L), function(s)
    lookup(sprintf("eff_varratio_s%02d", s), "lower"), numeric(1)),
  upper = vapply(seq_len(12L), function(s)
    lookup(sprintf("eff_varratio_s%02d", s), "upper"), numeric(1)),
  mse_ratio = vapply(seq_len(12L), function(s) {
    d <- stores[[s]]$ef
    mean((d$est_pooled - stores[[s]]$rd12)^2) /
      mean((d$est_standalone - stores[[s]]$rd12)^2)
  }, numeric(1)), stringsAsFactors = FALSE
)
utils::write.csv(efficiency, file.path(OUT, "efficiency.csv"), row.names = FALSE)

cat("\n== truth sets ==\n")
cat(sprintf("  material H: %s\n", paste(H, collapse = ", ")))
cat(sprintf("  near-homogeneous N: %s\n", paste(N, collapse = ", ")))
cat(sprintf("  truth thresholds: near <= %.3f; material >= %.3f\n",
            HET_NEAR, HET_MATERIAL))
cat(sprintf("  valid paired replicates: range %d to %d; required %d\n",
            min(valid_cf), max(valid_cf), MIN_VALID))

cat("\n== estimator adequacy ==\n")
cat(sprintf("  adequate: simultaneous |bias| upper <= %.3f and coverage lower >= %.2f\n",
            BIAS_ADEQUATE, COVERAGE_ADEQUATE))
cat(sprintf("  inadequate: simultaneous |bias| lower >= %.3f or coverage upper <= %.2f\n",
            BIAS_INADEQUATE, COVERAGE_INADEQUATE))
print(as.data.frame(status))

cat("\n== diagnostic and calibration ==\n")
cat(sprintf("  sensitivity %.3f [%.3f, %.3f]; adequate lower bound %.2f\n",
            point["diagnostic_sensitivity"], sens_lo, sens_hi,
            DIAG_SENS_ADEQUATE))
cat(sprintf("  specificity %.3f [%.3f, %.3f]; adequate lower bound %.2f\n",
            point["diagnostic_specificity"], spec_lo, spec_hi,
            DIAG_SPEC_ADEQUATE))
cat(sprintf("  calibration suspended: %s; coverage-difference threshold %.2f\n",
            calibration_suspend, 0.02))

cat("\n== separate conclusions ==\n")
cat("  pooling: ", pooling_branch, "\n", sep = "")
cat("  RD-scale diagnostic: ", diagnostic_branch, "\n", sep = "")
cat("  efficiency: ", efficiency_branch, "\n", sep = "")
cat("  calendar adjustment: ", calendar_branch, "\n", sep = "")
cat(sprintf("DECISION BRANCH: pooling=%s; diagnostic=%s; efficiency=%s; calendar=%s\n",
            pooling_branch, diagnostic_branch, efficiency_branch, calendar_branch))
