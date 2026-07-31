## Study 1 (CNF-01): performance measures and the decisive comparison.
##
##   Rscript R/05-analyze.R
##
## Writes results/performance.csv, results/attenuation.csv and
## results/matched-pairs.csv, which are the tracked artifacts the manuscript
## reads. The raw replicate files are regenerable from the seed and are not.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

source(here("R", "00-config.R"))
source(here("..", "_shared", "R", "performance.R"))

OUT <- here("results")
raw <- sort(list.files(file.path(OUT, "raw"), "^scenario-.*\\.rds$",
                       full.names = TRUE))
stopifnot(length(raw) > 0)
res <- do.call(rbind, lapply(raw, readRDS))
truth <- readRDS(file.path(OUT, "truth.rds"))

key <- c("scenario", "horizon")
res <- merge(res, truth[, c(key, "rd_itt", "rd_pp", "attenuation", "c_true")],
             by = key, all.x = TRUE)

## ---- 1. Is the attenuating estimand estimated without bias? --------------
##
## If it is not, the attenuation measured below is contaminated by estimation
## error and protocol section 7's third branch applies.
perf <- do.call(rbind, lapply(split(res, list(res$scenario, res$horizon, res$method),
                                    drop = TRUE), function(d) {
  est <- d$est; se <- d$se; tv <- d$rd_itt[1]
  lo <- est - 1.96 * se; hi <- est + 1.96 * se
  b  <- perf_bias(est, tv)
  es <- perf_empse(est)
  ms <- perf_modse(se)
  re <- perf_relerror_modse(est, se)
  cv <- perf_coverage(lo, hi, tv)
  cg <- perf_convergence(est, nrow(d))
  data.frame(
    scenario = d$scenario[1], horizon = d$horizon[1], method = d$method[1],
    target_c120 = d$target_c120[1], shape = d$shape[1],
    alpha_l_key = d$alpha_l_key[1], persistence = d$persistence[1],
    truth_rd_itt = tv,
    bias = b[["est"]], bias_mcse = b[["mcse"]],
    rel_bias = b[["est"]] / tv,
    empse = es[["est"]], empse_mcse = es[["mcse"]],
    modse = ms[["est"]], modse_mcse = ms[["mcse"]],
    relerror_modse = re[["est"]], relerror_modse_mcse = re[["mcse"]],
    coverage = cv[["est"]], coverage_mcse = cv[["mcse"]],
    converged = cg[["est"]], n_used = sum(!is.na(est)), n_attempted = nrow(d),
    stringsAsFactors = FALSE)
}))
rownames(perf) <- NULL
utils::write.csv(perf, file.path(OUT, "performance.csv"), row.names = FALSE)

## ---- 2. The attenuation curve --------------------------------------------
##
## True attenuation comes from the enumerated truth. The observed diagnostic is
## averaged over replicates with its Monte Carlo standard error, because that is
## what an applied paper would publish and its sampling error is part of what a
## reader would have to work with.
att <- do.call(rbind, lapply(split(res, list(res$scenario, res$horizon), drop = TRUE),
                             function(d) {
  co <- d$c_obs[d$method == "gformula"]
  data.frame(
    scenario = d$scenario[1], horizon = d$horizon[1],
    target_c120 = d$target_c120[1], shape = d$shape[1],
    alpha_l_key = d$alpha_l_key[1], persistence = d$persistence[1],
    rd_itt = d$rd_itt[1], rd_pp = d$rd_pp[1],
    attenuation = d$attenuation[1],
    c_true = d$c_true[1],
    c_obs = mean(co, na.rm = TRUE),
    c_obs_mcse = stats::sd(co, na.rm = TRUE) / sqrt(sum(!is.na(co))),
    stringsAsFactors = FALSE)
}))
att <- att[order(att$scenario, att$horizon), ]
rownames(att) <- NULL
utils::write.csv(att, file.path(OUT, "attenuation.csv"), row.names = FALSE)

## ---- 3. The decisive comparison ------------------------------------------
##
## Matched pairs: same target cumulative initiation, same prognostic dependence,
## same persistence, differing only in the timing shape. Both report the same
## diagnostic at month 120 by construction. The question is whether their
## attenuation differs, and by how much, at each horizon.
##
## `d_att` is the quantity protocol section 7 thresholds at 0.05.
pairs <- merge(
  att[att$shape == "early", ],
  att[att$shape == "late", ],
  by = c("target_c120", "alpha_l_key", "persistence", "horizon"),
  suffixes = c("_early", "_late"))
pairs$d_att   <- pairs$attenuation_early - pairs$attenuation_late
pairs$d_c_obs <- pairs$c_obs_early - pairs$c_obs_late
pairs$d_rd    <- pairs$rd_itt_early - pairs$rd_itt_late
pairs <- pairs[order(pairs$target_c120, pairs$alpha_l_key,
                     pairs$persistence, pairs$horizon), ]
rownames(pairs) <- NULL
utils::write.csv(pairs[, c("target_c120", "alpha_l_key", "persistence", "horizon",
                           "c_obs_early", "c_obs_late", "d_c_obs",
                           "attenuation_early", "attenuation_late", "d_att",
                           "rd_itt_early", "rd_itt_late", "d_rd")],
                 file.path(OUT, "matched-pairs.csv"), row.names = FALSE)

## ---- 4. Console summary ---------------------------------------------------
cat("\n== estimator correctness for the ITT-analogue ==\n")
cat(sprintf("  scenarios x horizons x methods: %d\n", nrow(perf)))
cat(sprintf("  |relative bias|: median %.3f%%, max %.3f%%\n",
            100 * stats::median(abs(perf$rel_bias)), 100 * max(abs(perf$rel_bias))))
cat(sprintf("  coverage: min %.3f, median %.3f, max %.3f\n",
            min(perf$coverage), stats::median(perf$coverage), max(perf$coverage)))
cat(sprintf("  convergence: min %.4f\n", min(perf$converged)))
cat(sprintf("  relative error in model SE: median %.1f%%, range %.1f%% to %.1f%%\n",
            stats::median(perf$relerror_modse), min(perf$relerror_modse),
            max(perf$relerror_modse)))

cat("\n== attenuation by horizon, pooled over scenarios ==\n")
for (h in HORIZONS) {
  a <- att$attenuation[att$horizon == h]
  cat(sprintf("  h=%3d  attenuation %.3f to %.3f (median %.3f)\n",
              h, min(a), max(a), stats::median(a)))
}

cat("\n== the decisive comparison: matched timing pairs ==\n")
cat("  same cumulative initiation at month 120, different timing\n")
for (h in HORIZONS) {
  p <- pairs[pairs$horizon == h, ]
  cat(sprintf("  h=%3d  |d_att| max %.3f  (d_c_obs max %.3f)\n",
              h, max(abs(p$d_att)), max(abs(p$d_c_obs))))
}
final <- pairs[pairs$horizon == 120L, ]
cat(sprintf("\n  at the matched horizon h=120: |d_c_obs| max %.4f, |d_att| max %.4f\n",
            max(abs(final$d_c_obs)), max(abs(final$d_att))))
cat(sprintf("  protocol threshold is 0.05 on the attenuation scale: %s\n",
            ifelse(max(abs(final$d_att)) >= 0.05,
                   "NECESSARY BUT NOT SUFFICIENT",
                   "diagnostic sufficient at the matched horizon")))
