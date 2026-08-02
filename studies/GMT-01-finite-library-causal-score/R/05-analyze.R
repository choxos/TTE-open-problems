## GMT-01: ADEMP performance measures and prespecified decisions.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw_files <- sort(list.files(file.path(OUT, "raw"), "^scenario-.*\\.rds$", full.names = TRUE))
stopifnot(length(raw_files) > 0L)
res <- do.call(rbind, lapply(raw_files, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))
scenarios <- build_scenarios()
if (!"replicate" %in% names(res)) stop("raw results lack replicate identifiers")
res <- merge(res, truth[, c("scenario", "truth", "truth_mean1", "truth_mean0",
                             "truth_mcse", "truth_n")], by = "scenario", all.x = TRUE)

## The simulation-only oracle is selected with every replicate excluded from
## the MSE calculation used to select its configuration.
make_oracle <- function(d) {
  z <- d[grepl("^oracle-config-", d$method), ]
  reps <- sort(unique(z$replicate)); configs <- seq_len(nrow(CONFIG_GRID))
  key <- expand.grid(replicate = reps, config_id = configs)
  key$key <- paste(key$replicate, key$config_id)
  z$key <- paste(z$replicate, z$config_id)
  z <- z[match(key$key, z$key), ]
  nr <- length(reps); nc <- length(configs)
  E <- matrix(z$est, nr, nc, byrow = FALSE)
  tv <- d$truth[1L]
  sq <- (E - tv)^2
  total <- colSums(sq, na.rm = TRUE); count <- colSums(is.finite(sq))
  loo_num <- matrix(total, nr, nc, byrow = TRUE) - ifelse(is.finite(sq), sq, 0)
  loo_den <- matrix(count, nr, nc, byrow = TRUE) - is.finite(sq)
  loo <- loo_num / loo_den; loo[loo_den <= 0] <- Inf
  selected <- max.col(-loo, ties.method = "first")
  pick <- cbind(seq_len(nr), selected)
  flat <- (selected - 1L) * nr + seq_len(nr)
  out <- z[flat, , drop = FALSE]
  out$method <- "oracle-ostep"
  out$selector <- "oracle"
  out$config_id <- selected
  out
}

oracle <- do.call(rbind, lapply(split(res, res$scenario), make_oracle))
analysis_rows <- rbind(res[!grepl("^oracle-config-", res$method), ], oracle)

safe_measure <- function(x) {
  if (is.null(x) || !is.list(x)) return(c(est = NA_real_, mcse = NA_real_))
  c(est = unname(x[["est"]]), mcse = unname(x[["mcse"]]))
}

## These calls use the shared performance implementation. IPW coverage is saved
## as a descriptive fixed-weight sensitivity and is excluded from every rule.
performance <- do.call(rbind, lapply(
  split(analysis_rows, list(analysis_rows$scenario, analysis_rows$method), drop = TRUE),
  function(d) {
    est <- d$est; se <- d$se; tv <- d$truth[1L]
    lo <- d$lo; hi <- d$hi
    b <- safe_measure(perf_bias(est, tv))
    es <- safe_measure(perf_empse(est))
    ms <- safe_measure(perf_modse(se))
    re <- safe_measure(perf_relerror_modse(est, se))
    mse <- safe_measure(perf_mse(est, tv))
    cv <- safe_measure(perf_coverage(lo, hi, tv))
    bec <- safe_measure(perf_becoverage(est, lo, hi))
    reject <- safe_measure(perf_rejection(lo, hi, 0))
    conv <- safe_measure(perf_convergence(est, nrow(d)))
    data.frame(
      scenario = d$scenario[1L], method = d$method[1L], selector = d$selector[1L],
      family = d$family[1L], separation_key = d$separation_key[1L],
      gamma_z_key = d$gamma_z_key[1L], gamma_z = d$gamma_z[1L],
      shape = d$shape[1L], truth = tv,
      bias = b["est"], bias_mcse = b["mcse"], absolute_bias = abs(b["est"]),
      empse = es["est"], empse_mcse = es["mcse"],
      modse = ms["est"], modse_mcse = ms["mcse"],
      relerror_modse = re["est"], relerror_modse_mcse = re["mcse"],
      mse = mse["est"], mse_mcse = mse["mcse"],
      coverage = cv["est"], coverage_mcse = cv["mcse"],
      becoverage = bec["est"], becoverage_mcse = bec["mcse"],
      rejection = reject["est"], rejection_mcse = reject["mcse"],
      convergence = conv["est"], convergence_mcse = conv["mcse"],
      mean1_bias = mean(d$mean1 - d$truth_mean1, na.rm = TRUE),
      mean0_bias = mean(d$mean0 - d$truth_mean0, na.rm = TRUE),
      n_used = sum(is.finite(est)), n_attempted = nrow(d),
      interval_label = if (d$family[1L] == "ipw")
        "descriptive fixed-weight sensitivity band" else "95% Wald interval",
      stringsAsFactors = FALSE
    )
  }))
rownames(performance) <- NULL
utils::write.csv(performance, file.path(OUT, "performance.csv"), row.names = FALSE)

wilson <- function(x, n, z = Z975) {
  if (!is.finite(n) || n <= 0) return(c(lower = NA, upper = NA))
  p <- x / n; den <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / den
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  c(lower = max(0, center - half), upper = min(1, center + half))
}

bootstrap_pair <- function(combined, comparator, B = BOOT_REPS) {
  keep <- is.finite(combined$est) & is.finite(comparator$est)
  ec <- combined$est[keep] - combined$truth[keep]
  ep <- comparator$est[keep] - comparator$truth[keep]
  cc <- combined$lo[keep] <= combined$truth[keep] & combined$hi[keep] >= combined$truth[keep]
  cp <- comparator$lo[keep] <= comparator$truth[keep] & comparator$hi[keep] >= comparator$truth[keep]
  n <- length(ec)
  if (n < 2L) return(list(point = rep(NA_real_, 4), lower = rep(NA_real_, 4),
                          upper = rep(NA_real_, 4), n = n,
                          coverage_mcse = NA_real_, coverage_halfwidth = Inf))
  names4 <- c("absolute_bias_gain", "coverage_gain", "mse_ratio", "mse_increase")
  point <- c(abs(mean(ep)) - abs(mean(ec)), mean(cc - cp),
             mean(ec^2) / mean(ep^2), mean(ec^2) / mean(ep^2) - 1)
  boot <- matrix(NA_real_, B, 4L, dimnames = list(NULL, names4))
  block <- 250L
  starts <- seq.int(1L, B, by = block)
  pos <- 1L
  for (first in starts) {
    nb <- min(block, B - first + 1L)
    id <- matrix(sample.int(n, n * nb, replace = TRUE), nrow = n)
    bec <- matrix(ec[id], nrow = n); bep <- matrix(ep[id], nrow = n)
    bcc <- matrix(as.numeric(cc)[id], nrow = n)
    bcp <- matrix(as.numeric(cp)[id], nrow = n)
    ratio <- colMeans(bec^2) / colMeans(bep^2)
    rows <- pos:(pos + nb - 1L)
    boot[rows, 1L] <- abs(colMeans(bep)) - abs(colMeans(bec))
    boot[rows, 2L] <- colMeans(bcc - bcp)
    boot[rows, 3L] <- ratio
    boot[rows, 4L] <- ratio - 1
    pos <- pos + nb
  }
  lower <- apply(boot, 2, stats::quantile, 0.025, na.rm = TRUE)
  upper <- apply(boot, 2, stats::quantile, 0.975, na.rm = TRUE)
  d <- as.numeric(cc) - as.numeric(cp)
  mcse <- stats::sd(d) / sqrt(n)
  list(point = setNames(point, names4), lower = lower, upper = upper,
       n = n, coverage_mcse = mcse, coverage_halfwidth = Z975 * mcse,
       boot = boot)
}

paired_one <- function(scenario, comparator_method) {
  d <- analysis_rows[analysis_rows$scenario == scenario, ]
  c0 <- d[d$method == "combined-ostep", ]
  p0 <- d[d$method == comparator_method, ]
  p0 <- p0[match(c0$replicate, p0$replicate), ]
  set.seed(MASTER_SEED + 300000L + 100L * scenario +
             match(comparator_method, c("predictive-ostep", "balance-ostep")))
  b <- bootstrap_pair(c0, p0)
  conv_d <- as.numeric(is.finite(c0$est)) - as.numeric(is.finite(p0$est))
  conv_est <- mean(conv_d); conv_se <- stats::sd(conv_d) / sqrt(length(conv_d))
  data.frame(
    scenario = scenario,
    comparator = sub("-ostep$", "", comparator_method),
    absolute_bias_gain = b$point[["absolute_bias_gain"]],
    absolute_bias_lower = b$lower[["absolute_bias_gain"]],
    absolute_bias_upper = b$upper[["absolute_bias_gain"]],
    coverage_gain = b$point[["coverage_gain"]],
    coverage_lower = b$lower[["coverage_gain"]],
    coverage_upper = b$upper[["coverage_gain"]],
    coverage_mcse = b$coverage_mcse,
    coverage_halfwidth = b$coverage_halfwidth,
    mse_ratio = b$point[["mse_ratio"]],
    mse_ratio_lower = b$lower[["mse_ratio"]],
    mse_ratio_upper = b$upper[["mse_ratio"]],
    mse_increase = b$point[["mse_increase"]],
    mse_increase_lower = b$lower[["mse_increase"]],
    mse_increase_upper = b$upper[["mse_increase"]],
    convergence_difference = conv_est,
    convergence_lower = conv_est - Z975 * conv_se,
    convergence_upper = conv_est + Z975 * conv_se,
    paired_successes = b$n,
    stringsAsFactors = FALSE
  )
}

paired <- do.call(rbind, lapply(scenarios$scenario, function(s)
  rbind(paired_one(s, "predictive-ostep"), paired_one(s, "balance-ostep"))))
paired <- merge(paired, scenarios, by = "scenario", all.x = TRUE)
utils::write.csv(paired, file.path(OUT, "paired-comparisons.csv"), row.names = FALSE)

median_bootstrap <- function(primary_scenarios, comparator_method) {
  draws_bias <- draws_cov <- matrix(NA_real_, BOOT_REPS, length(primary_scenarios))
  points_bias <- points_cov <- numeric(length(primary_scenarios))
  for (j in seq_along(primary_scenarios)) {
    s <- primary_scenarios[j]
    d <- analysis_rows[analysis_rows$scenario == s, ]
    cc <- d[d$method == "combined-ostep", ]
    pp <- d[d$method == comparator_method, ]
    pp <- pp[match(cc$replicate, pp$replicate), ]
    set.seed(MASTER_SEED + 400000L + 100L * s + j)
    b <- bootstrap_pair(cc, pp)
    points_bias[j] <- b$point[["absolute_bias_gain"]]
    points_cov[j] <- b$point[["coverage_gain"]]
    if (!is.null(b$boot)) {
      draws_bias[, j] <- b$boot[, "absolute_bias_gain"]
      draws_cov[, j] <- b$boot[, "coverage_gain"]
    }
  }
  mb <- apply(draws_bias, 1, stats::median, na.rm = TRUE)
  mc <- apply(draws_cov, 1, stats::median, na.rm = TRUE)
  list(
    absolute_bias = c(est = stats::median(points_bias),
      lower = stats::quantile(mb, 0.025, na.rm = TRUE),
      upper = stats::quantile(mb, 0.975, na.rm = TRUE)),
    coverage = c(est = stats::median(points_cov),
      lower = stats::quantile(mc, 0.025, na.rm = TRUE),
      upper = stats::quantile(mc, 0.975, na.rm = TRUE))
  )
}

primary_ids <- scenarios$scenario[scenarios$gamma_z_key == "absent"]
med_pred <- median_bootstrap(primary_ids, "predictive-ostep")
med_bal <- median_bootstrap(primary_ids, "balance-ostep")
median_results <- data.frame(
  comparator = c("predictive", "balance"),
  absolute_bias_gain = c(med_pred$absolute_bias["est"], med_bal$absolute_bias["est"]),
  absolute_bias_lower = c(med_pred$absolute_bias["lower"], med_bal$absolute_bias["lower"]),
  absolute_bias_upper = c(med_pred$absolute_bias["upper"], med_bal$absolute_bias["upper"]),
  coverage_gain = c(med_pred$coverage["est"], med_bal$coverage["est"]),
  coverage_lower = c(med_pred$coverage["lower"], med_bal$coverage["lower"]),
  coverage_upper = c(med_pred$coverage["upper"], med_bal$coverage["upper"])
)
utils::write.csv(median_results, file.path(OUT, "median-improvements.csv"), row.names = FALSE)

conv_rows <- do.call(rbind, lapply(
  split(analysis_rows[analysis_rows$method %in% c("predictive-ostep", "balance-ostep",
                                                  "combined-ostep", "oracle-ostep"), ],
        list(analysis_rows$scenario[analysis_rows$method %in% c("predictive-ostep", "balance-ostep",
                                                                 "combined-ostep", "oracle-ostep")],
             analysis_rows$method[analysis_rows$method %in% c("predictive-ostep", "balance-ostep",
                                                               "combined-ostep", "oracle-ostep")]),
        drop = TRUE),
  function(d) {
    x <- sum(is.finite(d$est)); ci <- wilson(x, nrow(d))
    data.frame(scenario = d$scenario[1L], method = d$method[1L],
               converged = x / nrow(d), lower = ci["lower"], upper = ci["upper"])
  }))
utils::write.csv(conv_rows, file.path(OUT, "convergence-intervals.csv"), row.names = FALSE)

selection_frequency <- function(field) {
  d <- analysis_rows[analysis_rows$method == "combined-ostep", c("scenario", field)]
  values <- unlist(strsplit(d[[field]], "\\|", fixed = FALSE))
  values <- values[nzchar(values)]
  z <- as.data.frame(table(values), stringsAsFactors = FALSE)
  names(z) <- c("candidate", "count")
  z$field <- field
  z$proportion <- z$count / sum(z$count)
  z
}
selection <- rbind(selection_frequency("selected_g"),
                   selection_frequency("selected_c"),
                   selection_frequency("selected_q"))
utils::write.csv(selection, file.path(OUT, "selection-frequencies.csv"), row.names = FALSE)

diag_fields <- c("balance_max", "balance_rms", "ess0", "ess1", "w0_median",
                 "w0_p95", "w0_p99", "w1_median", "w1_p95", "w1_p99",
                 "component_D", "runtime_seconds")
diagnostics <- do.call(rbind, lapply(split(
  analysis_rows[analysis_rows$method == "combined-ostep", ],
  analysis_rows$scenario[analysis_rows$method == "combined-ostep"]), function(d) {
    z <- vapply(diag_fields, function(v) mean(d[[v]], na.rm = TRUE), numeric(1))
    data.frame(scenario = d$scenario[1L], as.list(z), check.names = FALSE)
  }))
utils::write.csv(diagnostics, file.path(OUT, "diagnostics-summary.csv"), row.names = FALSE)

## Critique fix: decisions are stratified. The fixed-weight IPW bands never enter.
pred <- paired[paired$comparator == "predictive", ]
bal <- paired[paired$comparator == "balance", ]
primary <- pred[pred$gamma_z_key == "absent", ]
primary$favorable <-
  (primary$absolute_bias_gain >= DECISION$favorable_abs_bias & primary$absolute_bias_lower > 0) |
  (primary$coverage_gain >= DECISION$favorable_coverage & primary$coverage_lower > 0)
favorable <- primary[primary$favorable, ]
count_rule <- nrow(favorable) >= 4L && length(unique(favorable$separation_key)) == 2L &&
  length(unique(favorable$shape)) >= 2L
median_rule <-
  (med_pred$absolute_bias["est"] >= DECISION$median_abs_bias &&
     med_pred$absolute_bias["lower"] > 0) ||
  (med_pred$coverage["est"] >= DECISION$median_coverage &&
     med_pred$coverage["lower"] > 0)

combined_conv <- conv_rows[conv_rows$method == "combined-ostep" &
                             conv_rows$scenario %in% primary_ids, ]
all_primary_conv <- conv_rows[conv_rows$method %in%
                                c("predictive-ostep", "balance-ostep", "combined-ostep") &
                                conv_rows$scenario %in% primary_ids, ]
conv_gate <- nrow(combined_conv) == 8L &&
  all(combined_conv$lower >= DECISION$combined_convergence_lower) &&
  all(primary$convergence_lower > DECISION$paired_convergence_lower)

alignment <- primary[primary$separation_key == "good" & primary$shape == "all-main", ]
alignment_gate <- nrow(alignment) == 1L &&
  alignment$mse_increase_upper <= DECISION$alignment_relative_mse_upper
incremental <- bal[bal$gamma_z_key == "absent", ]
incremental$favorable <-
  (incremental$absolute_bias_gain >= DECISION$favorable_abs_bias & incremental$absolute_bias_lower > 0) |
  (incremental$coverage_gain >= DECISION$favorable_coverage & incremental$coverage_lower > 0)
incremental_value <- sum(incremental$favorable) >= 3L

positive <- count_rule && median_rule && conv_gate && alignment_gate
negative_cells <- primary$absolute_bias_upper < DECISION$favorable_abs_bias &
  primary$coverage_upper < DECISION$favorable_coverage
negative <- sum(negative_cells) >= 6L &&
  med_pred$absolute_bias["upper"] < DECISION$median_abs_bias &&
  med_pred$coverage["upper"] < DECISION$median_coverage

oracle_perf <- performance[performance$method == "oracle-ostep" &
                             performance$scenario %in% primary_ids, ]
oracle_limited <- sum(oracle_perf$absolute_bias > DECISION$oracle_abs_bias |
                        oracle_perf$coverage < DECISION$oracle_coverage,
                      na.rm = TRUE) > 2L
low_convergence <- any(all_primary_conv$lower <
                         DECISION$minimum_primary_convergence_lower, na.rm = TRUE)
truth_imprecise <- any(truth$truth_mcse > TRUTH_MCSE_MAX)
precision_unresolved <- any(primary$coverage_halfwidth >
                              DECISION$coverage_mc_halfwidth, na.rm = TRUE)
uninformative_gate <- oracle_limited || low_convergence || truth_imprecise ||
  precision_unresolved

primary_branch <- if (uninformative_gate) "UNINFORMATIVE" else if (positive)
  "FINITE-LIBRARY CAUSAL-SELECTION EFFECT PRESENT" else if (negative)
  "MATERIAL IMPROVEMENT NOT DEMONSTRATED" else "UNINFORMATIVE"

positive_controls <- pred[pred$gamma_z_key != "absent", ]
positive_controls$favorable <-
  (positive_controls$absolute_bias_gain >= DECISION$favorable_abs_bias &
     positive_controls$absolute_bias_lower > 0) |
  (positive_controls$coverage_gain >= DECISION$favorable_coverage &
     positive_controls$coverage_lower > 0)
by_gamma <- table(positive_controls$gamma_z_key[positive_controls$favorable])
mechanism_positive <- sum(positive_controls$favorable) >= 8L &&
  all(by_gamma[c("moderate", "strong")] >= 3L)
mechanism_negative <- sum(positive_controls$absolute_bias_upper <
                            DECISION$favorable_abs_bias &
                            positive_controls$coverage_upper <
                            DECISION$favorable_coverage) >= 12L
mechanism_branch <- if (mechanism_positive) "TREATMENT-ONLY-PREDICTOR MECHANISM DETECTED" else
  if (mechanism_negative) "TREATMENT-ONLY-PREDICTOR MECHANISM NOT DETECTED" else
    "TREATMENT-ONLY-PREDICTOR RESULT UNINFORMATIVE"

decision <- data.frame(
  primary_branch = primary_branch,
  favorable_primary_scenarios = sum(primary$favorable),
  count_rule = count_rule, median_rule = median_rule,
  convergence_gate = conv_gate, alignment_mse_gate = alignment_gate,
  incremental_value_over_bespoke_balance = incremental_value,
  oracle_limited = oracle_limited, low_convergence = low_convergence,
  truth_imprecise = truth_imprecise, precision_unresolved = precision_unresolved,
  mechanism_branch = mechanism_branch,
  favorable_positive_controls = sum(positive_controls$favorable),
  implemented_replicates = N_REP, protocol_replicates = N_REP_PROTOCOL
)
utils::write.csv(decision, file.path(OUT, "decision.csv"), row.names = FALSE)

cat("\n== finite-library longitudinal nuisance-selection study ==\n")
cat(sprintf("implemented %d replicates per scenario at n=%d; protocol requested %d\n",
            N_REP, N_PERSON, N_REP_PROTOCOL))
cat(sprintf("gamma_Z=0 favorable scenarios versus predictive CV: %d of 8; threshold: at least 4\n",
            sum(primary$favorable)))
cat(sprintf("median absolute-bias gain %.4f; threshold %.3f with positive lower bound\n",
            med_pred$absolute_bias["est"], DECISION$median_abs_bias))
cat(sprintf("median coverage gain %.4f; threshold %.3f with positive lower bound\n",
            med_pred$coverage["est"], DECISION$median_coverage))
cat(sprintf("incremental favorable scenarios versus bespoke balance: %d of 8; threshold: at least 3\n",
            sum(incremental$favorable)))
cat(sprintf("combined convergence Wilson lower-bound threshold: %.2f; passed=%s\n",
            DECISION$combined_convergence_lower, conv_gate))
cat(sprintf("alignment relative-MSE upper-bound threshold: %.2f; passed=%s\n",
            DECISION$alignment_relative_mse_upper, alignment_gate))
cat(sprintf("unresolved coverage MC half-width above %.2f: %s\n",
            DECISION$coverage_mc_halfwidth, precision_unresolved))
cat(sprintf("PRIMARY DECISION BRANCH: %s\n", primary_branch))
cat(sprintf("FINAL DECISION BRANCHES: primary=%s; treatment-only-predictor=%s\n",
            primary_branch, mechanism_branch))
