## OUT-01 mechanism study: performance and decision branches.
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
raw_paths <- sort(list.files(file.path(OUT, "raw"),
                             "^scenario-.*\\.rds$", full.names = TRUE))
if (!length(raw_paths)) stop("no raw scenario results found")
res <- do.call(rbind, lapply(raw_paths, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))

truth_numeric <- truth[, c("scenario", "horizon", "total_rd", "net_rd",
                            "displacement", "absolute_displacement",
                            "displacement_ci_low", "displacement_ci_high",
                            "absolute_displacement_ci_low",
                            "absolute_displacement_ci_high",
                            "direction_class", "displacement_class",
                            "truth_mcse_max")]
res <- merge(res, truth_numeric, by = c("scenario", "horizon"), all.x = TRUE)

binomial_interval <- function(success, attempts) {
  if (!is.finite(attempts) || attempts < 1L)
    return(c(low = NA_real_, high = NA_real_))
  ci <- stats::binom.test(success, attempts)$conf.int
  c(low = unname(ci[1]), high = unname(ci[2]))
}

invoke_becoverage <- function(est, se, truth_value) {
  formal_names <- tolower(names(formals(perf_becoverage)))
  first <- if (length(formal_names)) formal_names[1] else ""
  if (grepl("lower|lcl|^lo$", first)) {
    bias <- mean(est) - truth_value
    lo <- est - bias - WALD_MULTIPLIER * se
    hi <- est - bias + WALD_MULTIPLIER * se
    perf_becoverage(lo, hi, truth_value)
  } else if (length(formal_names) >= 3L) {
    perf_becoverage(est, se, truth_value)
  } else {
    perf_becoverage(est, se)
  }
}

invoke_rejection <- function(lo, hi) {
  if (length(formals(perf_rejection)) >= 3L) {
    perf_rejection(lo, hi, 0)
  } else {
    perf_rejection(lo, hi)
  }
}

performance_one <- function(d) {
  target <- if (d$method[1] == "death_censored_net") d$net_rd[1] else d$total_rd[1]
  usable <- (is.na(d$fail) | !nzchar(d$fail)) &
    is.finite(d$est) & is.finite(d$se)
  est <- d$est[usable]
  se <- d$se[usable]
  convergence <- perf_convergence(ifelse(usable, d$est, NA_real_), nrow(d))

  if (!length(est)) {
    return(data.frame(
      scenario = d$scenario[1], horizon = d$horizon[1], method = d$method[1],
      mortality_key = d$mortality_key[1], death_effect_key = d$death_effect_key[1],
      outcome_effect_key = d$outcome_effect_key[1], q_key = d$q_key[1],
      truth = target, bias = NA_real_, bias_mcse = NA_real_, empse = NA_real_,
      empse_mcse = NA_real_, modse = NA_real_, modse_mcse = NA_real_,
      relerror_modse_pct = NA_real_, relerror_modse_mcse = NA_real_,
      mse = NA_real_, mse_mcse = NA_real_, coverage = NA_real_,
      coverage_mcse = NA_real_, coverage_ci_low = NA_real_,
      coverage_ci_high = NA_real_, becoverage = NA_real_,
      becoverage_mcse = NA_real_, rejection = NA_real_,
      rejection_mcse = NA_real_, convergence = convergence$est,
      convergence_mcse = convergence$mcse, warning_frequency = mean(!is.na(d$warning)),
      wrong_target_inclusion = NA_real_, wrong_target_ci_low = NA_real_,
      wrong_target_ci_high = NA_real_, n_used = 0L, n_attempted = nrow(d),
      type_i_applicable = abs(target) <= SIGN_TOLERANCE,
      stringsAsFactors = FALSE
    ))
  }

  lo <- est - WALD_MULTIPLIER * se
  hi <- est + WALD_MULTIPLIER * se
  bias <- perf_bias(est, target)
  empse <- perf_empse(est)
  modse <- perf_modse(se)
  relse <- perf_relerror_modse(est, se)
  mse <- perf_mse(est, target)
  coverage <- perf_coverage(lo, hi, target)
  becoverage <- invoke_becoverage(est, se, target)
  rejection <- invoke_rejection(lo, hi)
  coverage_success <- sum(lo <= target & hi >= target)
  coverage_ci <- binomial_interval(coverage_success, length(est))

  ## Critique fix: inclusion of the total-effect truth by the net-risk interval
  ## is explicitly a wrong-target, sample-size-specific diagnostic.
  if (d$method[1] == "death_censored_net") {
    wrong_success <- sum(lo <= d$total_rd[1] & hi >= d$total_rd[1])
    wrong <- wrong_success / length(est)
    wrong_ci <- binomial_interval(wrong_success, length(est))
  } else {
    wrong <- NA_real_
    wrong_ci <- c(low = NA_real_, high = NA_real_)
  }

  data.frame(
    scenario = d$scenario[1], horizon = d$horizon[1], method = d$method[1],
    mortality_key = d$mortality_key[1], death_effect_key = d$death_effect_key[1],
    outcome_effect_key = d$outcome_effect_key[1], q_key = d$q_key[1],
    truth = target,
    bias = bias$est, bias_mcse = bias$mcse,
    empse = empse$est, empse_mcse = empse$mcse,
    modse = modse$est, modse_mcse = modse$mcse,
    relerror_modse_pct = relse$est,
    relerror_modse_mcse = relse$mcse,
    mse = mse$est, mse_mcse = mse$mcse,
    coverage = coverage$est, coverage_mcse = coverage$mcse,
    coverage_ci_low = coverage_ci[["low"]],
    coverage_ci_high = coverage_ci[["high"]],
    becoverage = becoverage$est, becoverage_mcse = becoverage$mcse,
    rejection = rejection$est, rejection_mcse = rejection$mcse,
    convergence = convergence$est, convergence_mcse = convergence$mcse,
    warning_frequency = mean(!is.na(d$warning) & nzchar(d$warning)),
    wrong_target_inclusion = wrong,
    wrong_target_ci_low = wrong_ci[["low"]],
    wrong_target_ci_high = wrong_ci[["high"]],
    n_used = length(est), n_attempted = nrow(d),
    type_i_applicable = abs(target) <= SIGN_TOLERANCE,
    stringsAsFactors = FALSE
  )
}

groups <- split(res, interaction(res$scenario, res$horizon, res$method,
                                 drop = TRUE))
performance <- do.call(rbind, lapply(groups, performance_one))
performance <- performance[order(performance$scenario, performance$horizon,
                                 performance$method), , drop = FALSE]
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, "performance.csv"), row.names = FALSE)

net_se <- performance[performance$method == "death_censored_net",
                      c("scenario", "horizon", "modse")]
names(net_se)[3] <- "mean_death_censored_se"
displacement <- merge(truth, net_se, by = c("scenario", "horizon"), all.x = TRUE)
displacement$absolute_displacement_over_mean_se <-
  displacement$absolute_displacement / displacement$mean_death_censored_se
utils::write.csv(displacement, file.path(OUT, "estimand-displacement.csv"),
                 row.names = FALSE)

replicate_rows <- res[res$method == METHODS[1] & res$horizon == HORIZONS[1], ]
overlap <- do.call(rbind, lapply(split(replicate_rows, replicate_rows$scenario),
                                 function(d) data.frame(
  scenario = d$scenario[1],
  treatment_prevalence = mean(d$treatment_prevalence, na.rm = TRUE),
  mean_prop_extreme_true_ps = mean(d$prop_extreme_true_ps, na.rm = TRUE),
  overlap_flag_frequency = mean(d$overlap_flag, na.rm = TRUE),
  n_replicates = nrow(d), stringsAsFactors = FALSE
)))
utils::write.csv(overlap, file.path(OUT, "overlap-flags.csv"), row.names = FALSE)

truth60 <- truth[truth$horizon == 60L, , drop = FALSE]
factors <- c("mortality_key", "death_effect_key", "outcome_effect_key", "q_key")
factor_ranges <- do.call(rbind, lapply(factors, function(factor_name) {
  do.call(rbind, lapply(split(truth60, truth60[[factor_name]]), function(d) {
    data.frame(
      factor = factor_name,
      level = as.character(d[[factor_name]][1]),
      signed_displacement_min = min(d$displacement),
      signed_displacement_max = max(d$displacement),
      absolute_displacement_min = min(d$absolute_displacement),
      absolute_displacement_max = max(d$absolute_displacement),
      stringsAsFactors = FALSE
    )
  }))
}))
utils::write.csv(factor_ranges, file.path(OUT, "factor-ranges.csv"),
                 row.names = FALSE)

validation_path <- file.path(OUT, "variance-validation.rds")
reasons <- character()
if (length(unique(res$scenario)) < nrow(build_scenarios()))
  reasons <- c(reasons, "production results are incomplete")
if (any(truth$truth_mcse_max > TRUTH_MCSE_LIMIT))
  reasons <- c(reasons, "truth MCSE exceeds 0.0005")
if (!file.exists(validation_path)) {
  reasons <- c(reasons, "variance validation is missing")
} else {
  validation <- readRDS(validation_path)$summary
  if (any(!is.finite(validation$relative_disagreement)) ||
      any(validation$relative_disagreement > IF_BOOTSTRAP_TOLERANCE))
    reasons <- c(reasons, "influence-function and bootstrap SE disagreement exceeds 5%")
}

calibration60 <- performance[performance$horizon == 60L, , drop = FALSE]
calibration60$bad_bias <- abs(calibration60$bias) > 0.005
calibration60$bad_se <- abs(calibration60$relerror_modse_pct) > 10
calibration60$bad_convergence <- calibration60$convergence < 0.98
calibration60$bad_coverage <- calibration60$coverage_ci_high < 0.93 |
  calibration60$coverage_ci_low > 0.97
calibration60$bad_any <- calibration60$bad_bias | calibration60$bad_se |
  calibration60$bad_convergence | calibration60$bad_coverage

bad_counts <- setNames(integer(length(METHODS)), METHODS)
for (method in METHODS) {
  d <- calibration60[calibration60$method == method, , drop = FALSE]
  if (nrow(d) != nrow(build_scenarios()) || any(is.na(d$bad_any))) {
    reasons <- c(reasons, paste(method, "has incomplete calibration metrics"))
    bad_counts[[method]] <- NA_integer_
  } else {
    bad_counts[[method]] <- sum(d$bad_any)
    if (bad_counts[[method]] > 2L)
      reasons <- c(reasons, sprintf("%s fails calibration in %d scenarios",
                                    method, bad_counts[[method]]))
  }
}

## Critique fix: the decision uses only the prespecified absolute-displacement
## interval. It makes no count-based prevalence claim about applied settings.
branch_counts <- table(factor(truth60$displacement_class,
                              levels = c("material", "not-material", "indeterminate")))
branch <- if (length(reasons)) "uninformative" else "calibrated scenario branches"
decision <- data.frame(
  branch = branch,
  material_scenarios = unname(branch_counts[["material"]]),
  not_material_scenarios = unname(branch_counts[["not-material"]]),
  indeterminate_scenarios = unname(branch_counts[["indeterminate"]]),
  death_censored_bad_calibration = unname(bad_counts[["death_censored_net"]]),
  multistate_bad_calibration = unname(bad_counts[["multistate_total"]]),
  reasons = if (length(reasons)) paste(unique(reasons), collapse = "; ") else NA_character_,
  stringsAsFactors = FALSE
)
utils::write.csv(decision, file.path(OUT, "decision-summary.csv"), row.names = FALSE)

cat("\n== 60-month estimand displacement ==\n")
cat(sprintf("  signed range: %.4f to %.4f\n",
            min(truth60$displacement), max(truth60$displacement)))
cat(sprintf("  absolute range: %.4f to %.4f\n",
            min(truth60$absolute_displacement), max(truth60$absolute_displacement)))
cat(sprintf("  threshold branches: material %d, not material %d, indeterminate %d\n",
            branch_counts[["material"]], branch_counts[["not-material"]],
            branch_counts[["indeterminate"]]))
cat("\n== own-target calibration at 60 months ==\n")
for (method in METHODS) {
  d <- calibration60[calibration60$method == method, , drop = FALSE]
  cat(sprintf("  %s: max |bias| %.4f, max |SE error| %.1f%%, min convergence %.3f\n",
              method, max(abs(d$bias), na.rm = TRUE),
              max(abs(d$relerror_modse_pct), na.rm = TRUE),
              min(d$convergence, na.rm = TRUE)))
}
if (length(reasons)) {
  cat(sprintf("DECISION BRANCH: UNINFORMATIVE because %s.\n",
              paste(unique(reasons), collapse = "; ")))
} else {
  cat(sprintf(paste0("DECISION BRANCH: CALIBRATED; %d scenarios are MATERIAL ",
                     "because the lower absolute-displacement bound exceeds 0.010, ",
                     "%d are NOT MATERIAL because the upper bound is below 0.010, ",
                     "and %d are INDETERMINATE because the interval includes 0.010.\n"),
              branch_counts[["material"]], branch_counts[["not-material"]],
              branch_counts[["indeterminate"]]))
}
