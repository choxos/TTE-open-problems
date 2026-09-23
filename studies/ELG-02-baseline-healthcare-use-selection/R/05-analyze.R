## Study ELG-02: performance measures and decision rules.
##
##   Rscript R/05-analyze.R

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.file_arg)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .file_arg[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(
  file.path(OUT, "raw"), "^scenario-[0-9]+\\.rds$", full.names = TRUE
))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))

rep_column <- intersect(c("replicate", "rep", "rep_id"), names(res))
if (!length(rep_column)) stop("the harness output has no replicate identifier")
res$replicate_id <- res[[rep_column[1]]]
if (length(unique(res$scenario)) != nrow(build_scenarios())) {
  stop("all 18 unique DGM cells must finish before decision analysis")
}

truth_columns <- c(
  "scenario", "rd_h", "rd_all", "delta_target", "contribution_b",
  "contribution_x", "contribution_d", "decomposition_error",
  "quadrature_nodes", "quadrature_convergence_error", "quadrature_ok",
  "rd_all_identity_error", "identity_ok", "cor_pd_h_truth"
)
res <- merge(res, truth[, truth_columns], by = "scenario", all.x = TRUE)
res$truth_value <- ifelse(res$method == "broad", res$rd_all, res$rd_h)
res$available <- !(res$view == "reduced" & res$method == "role_based")
res$valid <- res$available & is.na(res$fail) & is.finite(res$est) &
  is.finite(res$se) & is.finite(res$lo) & is.finite(res$hi)

mean_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) mean(x) else NA_real_
}

## The signature is (est, lower, upper), and counting `formals` cannot tell you
## what the third argument means. Passing a standard error as a lower bound and
## the truth as an upper bound is not a fallback, it is a different quantity.
call_becoverage <- function(est, lo, hi) {
  perf_becoverage(est, lo, hi)
}

call_rejection <- function(lo, hi) {
  n_args <- length(formals(perf_rejection))
  if (n_args >= 3L) perf_rejection(lo, hi, 0) else perf_rejection(lo, hi)
}

performance_one <- function(d) {
  available <- isTRUE(d$available[1])
  base <- data.frame(
    scenario = d$scenario[1], topology = d$topology[1],
    strength = d$strength[1], retention = d$retention[1],
    view = d$view[1], method = d$method[1], available = available,
    truth = d$truth_value[1], stringsAsFactors = FALSE
  )
  if (!available) {
    return(cbind(
      base, bias = NA_real_, bias_mcse = NA_real_, abs_bias = NA_real_,
      mse = NA_real_, mse_mcse = NA_real_, empse = NA_real_,
      empse_mcse = NA_real_, modse = NA_real_, modse_mcse = NA_real_,
      relerror_modse = NA_real_, relerror_modse_mcse = NA_real_,
      coverage = NA_real_, coverage_mcse = NA_real_,
      bias_eliminated_coverage = NA_real_,
      bias_eliminated_coverage_mcse = NA_real_, rejection = NA_real_,
      rejection_mcse = NA_real_, convergence = NA_real_,
      failure_rate = NA_real_, n_used = 0L, n_attempted = nrow(d),
      mean_min_ps = NA_real_, mean_max_weight = NA_real_, mean_ess = NA_real_,
      mean_selected_n = mean_or_na(d$selected_n),
      mean_treatment_prevalence = mean_or_na(d$treatment_prevalence),
      mean_outcome_risk = mean_or_na(d$outcome_risk),
      mean_cor_pd_selected = mean_or_na(d$cor_pd_selected),
      warning_rate = mean(d$screen_result == "collider-candidate", na.rm = TRUE),
      unresolved_rate = mean(d$screen_result == "unresolved-audit", na.rm = TRUE)
    ))
  }

  est <- d$est
  se <- d$se
  lo <- d$lo
  hi <- d$hi
  tv <- d$truth_value[1]
  bias <- perf_bias(est, tv)
  mse <- perf_mse(est, tv)
  empse <- perf_empse(est)
  modse <- perf_modse(se)
  relative_se <- perf_relerror_modse(est, se)
  coverage <- perf_coverage(lo, hi, tv)
  becoverage <- call_becoverage(est, lo, hi)
  rejection <- call_rejection(lo, hi)
  convergence <- perf_convergence(est, nrow(d))

  cbind(
    base,
    bias = bias[["est"]], bias_mcse = bias[["mcse"]],
    abs_bias = abs(bias[["est"]]),
    mse = mse[["est"]], mse_mcse = mse[["mcse"]],
    empse = empse[["est"]], empse_mcse = empse[["mcse"]],
    modse = modse[["est"]], modse_mcse = modse[["mcse"]],
    relerror_modse = relative_se[["est"]],
    relerror_modse_mcse = relative_se[["mcse"]],
    coverage = coverage[["est"]], coverage_mcse = coverage[["mcse"]],
    bias_eliminated_coverage = becoverage[["est"]],
    bias_eliminated_coverage_mcse = becoverage[["mcse"]],
    rejection = rejection[["est"]], rejection_mcse = rejection[["mcse"]],
    convergence = convergence[["est"]],
    failure_rate = 1 - convergence[["est"]],
    n_used = sum(d$valid), n_attempted = nrow(d),
    mean_min_ps = mean_or_na(d$min_ps[d$valid]),
    mean_max_weight = mean_or_na(d$max_weight[d$valid]),
    mean_ess = mean_or_na(d$ess[d$valid]),
    mean_selected_n = mean_or_na(d$selected_n),
    mean_treatment_prevalence = mean_or_na(d$treatment_prevalence),
    mean_outcome_risk = mean_or_na(d$outcome_risk),
    mean_cor_pd_selected = mean_or_na(d$cor_pd_selected),
    warning_rate = mean(d$screen_result == "collider-candidate", na.rm = TRUE),
    unresolved_rate = mean(d$screen_result == "unresolved-audit", na.rm = TRUE)
  )
}

performance <- do.call(rbind, lapply(
  split(res, list(res$scenario, res$view, res$method), drop = TRUE),
  performance_one
))
rownames(performance) <- NULL
performance <- performance[order(
  performance$scenario, match(performance$view, VIEWS),
  match(performance$method, ESTIMATOR_METHODS)
), ]
utils::write.csv(performance, file.path(OUT, "performance.csv"), row.names = FALSE)

wilson_interval <- function(k, n, level = 0.95) {
  if (n <= 0L) return(c(est = NA_real_, lo = NA_real_, hi = NA_real_))
  z <- stats::qnorm(1 - (1 - level) / 2)
  p <- k / n
  denominator <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denominator
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denominator
  c(est = p, lo = center - half, hi = center + half)
}

screen_rows <- res[res$method == "minimal", ]
screen_performance <- do.call(rbind, lapply(
  split(screen_rows, list(screen_rows$scenario, screen_rows$view), drop = TRUE),
  function(d) {
    n <- nrow(d)
    collider <- d$topology[1] != "noncollider"
    warning <- d$screen_result == "collider-candidate"
    unresolved <- d$screen_result == "unresolved-audit"
    silent <- collider & d$screen_result == "no-observable-collider-signal"
    w <- wilson_interval(sum(warning, na.rm = TRUE), n)
    u <- wilson_interval(sum(unresolved, na.rm = TRUE), n)
    s <- wilson_interval(sum(silent, na.rm = TRUE), n)
    fp <- if (!collider) wilson_interval(sum(warning, na.rm = TRUE), n) else rep(NA_real_, 3)
    data.frame(
      scenario = d$scenario[1], topology = d$topology[1],
      strength = d$strength[1], retention = d$retention[1], view = d$view[1],
      n = n, warning = w[1], warning_lo = w[2], warning_hi = w[3],
      false_positive = fp[1], false_positive_lo = fp[2], false_positive_hi = fp[3],
      unresolved = u[1], unresolved_lo = u[2], unresolved_hi = u[3],
      silent_error = s[1], silent_error_lo = s[2], silent_error_hi = s[3],
      stringsAsFactors = FALSE
    )
  }
))
rownames(screen_performance) <- NULL
utils::write.csv(
  screen_performance, file.path(OUT, "screen-performance.csv"), row.names = FALSE
)

bootstrap_abs_bias <- function(x, truth_value) {
  x <- x[is.finite(x)]
  if (!length(x)) return(c(est = NA_real_, lo = NA_real_, hi = NA_real_))
  observed <- abs(mean(x) - truth_value)
  boot <- vapply(seq_len(N_BOOT), function(i) {
    abs(mean(x[sample.int(length(x), length(x), replace = TRUE)]) - truth_value)
  }, numeric(1))
  interval <- stats::quantile(boot, c(0.025, 0.975), names = FALSE, type = 6)
  c(est = observed, lo = interval[1], hi = interval[2])
}

bootstrap_policy_benefit <- function(minimal, policy, truth_value) {
  observed <- abs(mean(minimal) - truth_value) - abs(mean(policy) - truth_value)
  n <- length(minimal)
  boot <- vapply(seq_len(N_BOOT), function(i) {
    index <- sample.int(n, n, replace = TRUE)
    abs(mean(minimal[index]) - truth_value) -
      abs(mean(policy[index]) - truth_value)
  }, numeric(1))
  interval <- stats::quantile(boot, c(0.025, 0.975), names = FALSE, type = 6)
  c(est = observed, lo = interval[1], hi = interval[2])
}

set.seed(ANALYSIS_SEED)
minimal_unique <- res[res$method == "minimal" & res$view == "full", ]
bias_bounds <- do.call(rbind, lapply(split(minimal_unique, minimal_unique$scenario), function(d) {
  valid <- d$valid
  bound <- bootstrap_abs_bias(d$est[valid], d$rd_h[1])
  data.frame(
    scenario = d$scenario[1], topology = d$topology[1],
    strength = d$strength[1], retention = d$retention[1],
    n_valid = sum(valid), abs_bias = bound[1], abs_bias_lo = bound[2],
    abs_bias_hi = bound[3], stringsAsFactors = FALSE
  )
}))
rownames(bias_bounds) <- NULL
utils::write.csv(bias_bounds, file.path(OUT, "bias-bounds.csv"), row.names = FALSE)

minimal_rows <- res[res$method == "minimal", c(
  "scenario", "view", "replicate_id", "est", "fail", "rd_h", "topology",
  "strength", "retention"
)]
policy_rows <- res[res$method == "policy", c(
  "scenario", "view", "replicate_id", "est", "fail"
)]
paired <- merge(
  minimal_rows, policy_rows,
  by = c("scenario", "view", "replicate_id"),
  suffixes = c("_minimal", "_policy")
)

primary <- do.call(rbind, lapply(
  split(paired, list(paired$scenario, paired$view), drop = TRUE),
  function(d) {
    valid <- is.na(d$fail_minimal) & is.na(d$fail_policy) &
      is.finite(d$est_minimal) & is.finite(d$est_policy)
    minimal <- d$est_minimal[valid]
    policy <- d$est_policy[valid]
    tv <- d$rd_h[1]
    if (length(minimal)) {
      benefit <- bootstrap_policy_benefit(minimal, policy, tv)
      minimal_bias <- abs(mean(minimal) - tv)
      policy_bias <- abs(mean(policy) - tv)
    } else {
      benefit <- rep(NA_real_, 3)
      minimal_bias <- policy_bias <- NA_real_
    }
    data.frame(
      scenario = d$scenario[1], topology = d$topology[1],
      strength = d$strength[1], retention = d$retention[1], view = d$view[1],
      n_paired = length(minimal), minimal_abs_bias = minimal_bias,
      policy_abs_bias = policy_bias, benefit = benefit[1],
      benefit_lo = benefit[2], benefit_hi = benefit[3],
      harm = -benefit[1], harm_lo = -benefit[3], harm_hi = -benefit[2],
      stringsAsFactors = FALSE
    )
  }
))
rownames(primary) <- NULL
utils::write.csv(primary, file.path(OUT, "primary-policy.csv"), row.names = FALSE)

mean_mc <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return(c(est = NA_real_, mcse = NA_real_))
  c(est = mean(x), mcse = if (length(x) > 1L) stats::sd(x) / sqrt(length(x)) else NA_real_)
}

comparison_methods <- c("minimal", "role_based", "all_measured", "oracle", "pooled_all")
policy_comparisons <- list()
for (view in VIEWS) {
  policy_view <- res[res$view == view & res$method == "policy", ]
  for (method in comparison_methods) {
    comparator <- res[res$view == view & res$method == method, ]
    joined <- merge(
      policy_view[, c("scenario", "replicate_id", "est", "lo", "hi", "valid", "rd_h")],
      comparator[, c("scenario", "replicate_id", "est", "lo", "hi", "valid")],
      by = c("scenario", "replicate_id"), suffixes = c("_policy", "_comparator")
    )
    for (scenario_id in sort(unique(joined$scenario))) {
      d <- joined[joined$scenario == scenario_id, ]
      valid <- d$valid_policy & d$valid_comparator
      tv <- d$rd_h[1]
      if (any(valid)) {
        mse_difference <- (d$est_policy[valid] - tv)^2 -
          (d$est_comparator[valid] - tv)^2
        coverage_difference <-
          as.integer(d$lo_policy[valid] <= tv & d$hi_policy[valid] >= tv) -
          as.integer(d$lo_comparator[valid] <= tv & d$hi_comparator[valid] >= tv)
        md <- mean_mc(mse_difference)
        cd <- mean_mc(coverage_difference)
      } else {
        md <- cd <- c(est = NA_real_, mcse = NA_real_)
      }
      policy_comparisons[[length(policy_comparisons) + 1L]] <- data.frame(
        scenario = scenario_id, view = view, comparator = method,
        n_paired = sum(valid), mse_policy_minus_comparator = md[1],
        mse_difference_mcse = md[2], coverage_policy_minus_comparator = cd[1],
        coverage_difference_mcse = cd[2], stringsAsFactors = FALSE
      )
    }
  }
}
policy_comparisons <- do.call(rbind, policy_comparisons)
utils::write.csv(
  policy_comparisons, file.path(OUT, "policy-comparisons.csv"), row.names = FALSE
)

movement_rows <- list()
restricted_methods <- c("minimal", "role_based", "all_measured", "oracle", "policy", "pooled_all")
for (view in VIEWS) {
  broad <- res[res$view == view & res$method == "broad", ]
  for (method in restricted_methods) {
    restricted <- res[res$view == view & res$method == method, ]
    joined <- merge(
      restricted[, c("scenario", "replicate_id", "est", "valid", "rd_h", "rd_all", "delta_target")],
      broad[, c("scenario", "replicate_id", "est", "valid")],
      by = c("scenario", "replicate_id"), suffixes = c("_restricted", "_broad")
    )
    for (scenario_id in sort(unique(joined$scenario))) {
      d <- joined[joined$scenario == scenario_id, ]
      valid <- d$valid_restricted & d$valid_broad
      if (any(valid)) {
        movement <- d$est_restricted[valid] - d$est_broad[valid]
        mm <- mean_mc(movement)
        bias_h <- mean(d$est_restricted[valid]) - d$rd_h[1]
        bias_all <- mean(d$est_broad[valid]) - d$rd_all[1]
        rhs <- d$delta_target[1] + bias_h - bias_all
      } else {
        mm <- c(est = NA_real_, mcse = NA_real_)
        bias_h <- bias_all <- rhs <- NA_real_
      }
      movement_rows[[length(movement_rows) + 1L]] <- data.frame(
        scenario = scenario_id, view = view, restricted_method = method,
        n_paired = sum(valid), mean_estimated_movement = mm[1],
        movement_mcse = mm[2], delta_target = d$delta_target[1],
        restricted_bias = bias_h, broad_bias = bias_all,
        decomposition_rhs = rhs, identity_error = mm[1] - rhs,
        stringsAsFactors = FALSE
      )
    }
  }
}
movement <- do.call(rbind, movement_rows)
utils::write.csv(movement, file.path(OUT, "estimate-movement.csv"), row.names = FALSE)

shift <- truth[, c(
  "scenario", "topology", "strength", "retention", "rd_h", "rd_all",
  "delta_target", "contribution_b", "contribution_x", "contribution_d",
  "decomposition_error", "cor_pd_h_truth"
)]
utils::write.csv(shift, file.path(OUT, "target-shift.csv"), row.names = FALSE)

minimal_perf <- performance[performance$method == "minimal", c(
  "scenario", "view", "bias"
)]
reduction_perf <- performance[performance$method %in% c(
  "role_based", "all_measured", "oracle", "policy", "pooled_all"
), ]
reduction_perf <- merge(
  reduction_perf, minimal_perf,
  by = c("scenario", "view"), suffixes = c("", "_minimal")
)
reduction_perf$absolute_bias_reduction <-
  abs(reduction_perf$bias_minimal) - abs(reduction_perf$bias)
utils::write.csv(
  reduction_perf[, c(
    "scenario", "topology", "strength", "retention", "view", "method",
    "bias_minimal", "bias", "absolute_bias_reduction"
  )],
  file.path(OUT, "bias-reductions.csv"), row.names = FALSE
)

spans_required_cells <- function(d) {
  nrow(d) >= 4L &&
    all(c("concordant-collider", "discordant-collider") %in% d$topology) &&
    all(RETENTIONS %in% d$retention) &&
    length(unique(d$strength)) >= 2L
}

## Critique fix: materiality uses unique generated cells and absolute bias only.
## Coverage is reported in performance.csv and cannot trigger this branch.
collider_bounds <- bias_bounds[bias_bounds$topology != "noncollider", ]
material_cells <- collider_bounds[
  is.finite(collider_bounds$abs_bias_lo) & collider_bounds$abs_bias_lo >= MATERIAL_BIAS,
]
material <- spans_required_cells(material_cells)
negligible <- nrow(collider_bounds) == 12L &&
  all(is.finite(collider_bounds$abs_bias_hi) & collider_bounds$abs_bias_hi < NEGLIGIBLE_BIAS)
materiality_branch <- if (material) {
  "materially consequential"
} else if (negligible) {
  "negligible"
} else {
  "mixed"
}

policy_branch_for <- function(view) {
  d <- primary[primary$view == view, ]
  collider <- d[d$topology != "noncollider", ]
  noncollider <- d[d$topology == "noncollider", ]
  favorable <- collider[
    is.finite(collider$benefit_lo) & collider$benefit_lo >= POLICY_BENEFIT,
  ]
  no_material_harm <- !any(
    is.finite(noncollider$harm_lo) & noncollider$harm_lo >= POLICY_BENEFIT
  )
  beneficial <- spans_required_cells(favorable) && no_material_harm
  not_beneficial <- nrow(collider) == 12L &&
    all(is.finite(collider$benefit_hi) & collider$benefit_hi < POLICY_BENEFIT)
  if (beneficial) {
    "conditionally beneficial"
  } else if (not_beneficial) {
    "not beneficial"
  } else {
    "mixed"
  }
}
policy_branches <- stats::setNames(vapply(VIEWS, policy_branch_for, character(1)), VIEWS)

technical_reasons <- character()
required_performance <- performance[performance$available, ]
if (any(required_performance$failure_rate > MAX_FAILURE_RATE, na.rm = TRUE)) {
  technical_reasons <- c(technical_reasons, "required estimator failure above 10 percent")
}
if (any(primary$n_paired < MIN_PAIRED, na.rm = TRUE)) {
  technical_reasons <- c(technical_reasons, "fewer than 1900 paired policy outputs")
}
## The screen is a required component of the policy. A screen that errors takes
## the unresolved-audit fallback, which looks like a policy decision rather than
## a failure; the first complete run failed its screen in every replicate and
## this check did not exist. Timestamp unavailability is a registered state, not
## a failure, and is excluded.
screen_rows <- res[res$method == "policy" & res$view %in% VIEWS, , drop = FALSE]
screen_failed <- !is.na(screen_rows$screen_fail) &
  screen_rows$screen_fail != "timestamps-unavailable"
screen_fail_rate <- tapply(screen_failed,
                           paste(screen_rows$scenario, screen_rows$view), mean)
if (any(screen_fail_rate > 0.10)) {
  technical_reasons <- c(technical_reasons, sprintf(
    "audit screen failed in more than 10%% of replicates in %d cell-views",
    sum(screen_fail_rate > 0.10)))
}
if (any(!truth$quadrature_ok) || any(!truth$identity_ok)) {
  technical_reasons <- c(technical_reasons, "quadrature or probit identity failure")
}

## The broad truth-recovery check is a two-sided 95 percent Monte Carlo interval
## for signed bias. It fails when that interval excludes zero.
broad_check <- performance[
  performance$method == "broad" & performance$view == "full",
]
broad_check$bias_lo <- broad_check$bias - 1.96 * broad_check$bias_mcse
broad_check$bias_hi <- broad_check$bias + 1.96 * broad_check$bias_mcse
if (any(broad_check$bias_lo > 0 | broad_check$bias_hi < 0, na.rm = TRUE)) {
  technical_reasons <- c(technical_reasons, "broad AIPW truth-recovery failure")
}
noncollider_bad <- bias_bounds$topology == "noncollider" &
  is.finite(bias_bounds$abs_bias_hi) & bias_bounds$abs_bias_hi >= NEGLIGIBLE_BIAS
if (sum(noncollider_bad) > 1L) {
  technical_reasons <- c(
    technical_reasons,
    "more than one noncollider cell has upper absolute-bias bound at least 0.005"
  )
}
technical_branch <- if (length(technical_reasons)) {
  "technically uninformative"
} else {
  "technically informative"
}

decision <- data.frame(
  component = c("materiality", "policy", "policy", "technical"),
  view = c(NA, "full", "reduced", NA),
  branch = c(
    materiality_branch, policy_branches[["full"]],
    policy_branches[["reduced"]], technical_branch
  ),
  evidence = c(
    sprintf("%d collider cells have lower absolute-bias bound at least %.3f", nrow(material_cells), MATERIAL_BIAS),
    sprintf("paired benefit threshold %.3f", POLICY_BENEFIT),
    sprintf("paired benefit threshold %.3f", POLICY_BENEFIT),
    if (length(technical_reasons)) paste(technical_reasons, collapse = "; ") else "all technical checks passed"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(decision, file.path(OUT, "decision.csv"), row.names = FALSE)

cat("\n== ELG-02 conditional mechanism benchmark ==\n")
cat(sprintf("unique DGM cells: %d; replicates per cell: %d\n", nrow(truth), N_REP))
cat(sprintf(
  "minimal absolute-bias material cells: %d of 12 at lower bound >= %.3f\n",
  nrow(material_cells), MATERIAL_BIAS
))
cat(sprintf(
  "minimal absolute-bias negligible cells: %d of 12 at upper bound < %.3f\n",
  sum(collider_bounds$abs_bias_hi < NEGLIGIBLE_BIAS, na.rm = TRUE), NEGLIGIBLE_BIAS
))
for (view in VIEWS) {
  d <- primary[primary$view == view & primary$topology != "noncollider", ]
  cat(sprintf(
    "policy %s view: %d of 12 collider cells have lower benefit bound >= %.3f\n",
    view, sum(d$benefit_lo >= POLICY_BENEFIT, na.rm = TRUE), POLICY_BENEFIT
  ))
}
if (length(technical_reasons)) {
  cat("technical reasons: ", paste(technical_reasons, collapse = "; "), "\n", sep = "")
}
cat(sprintf(
  paste0(
    "DECISION RULE BRANCHES: materiality=%s; policy_full=%s; ",
    "policy_reduced=%s; technical=%s. Thresholds: material lower bound %.3f ",
    "in at least 4 spanning cells; negligible upper bound %.3f in all 12; ",
    "policy benefit lower bound %.3f in at least 4 spanning cells; ",
    "failure ceiling %.2f; paired minimum %d.\n"
  ),
  materiality_branch, policy_branches[["full"]], policy_branches[["reduced"]],
  technical_branch, MATERIAL_BIAS, NEGLIGIBLE_BIAS, POLICY_BENEFIT,
  MAX_FAILURE_RATE, MIN_PAIRED
))
