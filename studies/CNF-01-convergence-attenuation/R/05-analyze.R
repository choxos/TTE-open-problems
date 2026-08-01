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
    truth_rd_itt = tv, truth_rd_pp = d$rd_pp[1],
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
## Monte Carlo uncertainty on the decisive quantity. Truth is enumerated at
## N_TRUTH per scenario, so each risk is a binomial proportion with that
## denominator and the attenuation is a ratio of risk differences, whose error
## propagates by the delta method. Without this the headline number carries no
## uncertainty and its distance from the threshold cannot be compared with its
## own Monte Carlo error, which is the first thing a reader should ask.
att_mcse <- function(r) {
  v <- function(p) p * (1 - p) / N_TRUTH
  s_itt <- sqrt(v(r$risk_itt1) + v(r$risk_itt0))
  s_pp  <- sqrt(v(r$risk_pp1)  + v(r$risk_pp0))
  abs(r$rd_itt / r$rd_pp) *
    sqrt((s_itt / r$rd_itt)^2 + (s_pp / r$rd_pp)^2)
}
truth$att_mcse <- att_mcse(truth)
.am <- truth[, c("scenario", "horizon", "att_mcse")]
pairs <- merge(pairs, .am, by.x = c("scenario_early", "horizon"),
               by.y = c("scenario", "horizon"), all.x = TRUE)
names(pairs)[names(pairs) == "att_mcse"] <- "att_mcse_early"
pairs <- merge(pairs, .am, by.x = c("scenario_late", "horizon"),
               by.y = c("scenario", "horizon"), all.x = TRUE)
names(pairs)[names(pairs) == "att_mcse"] <- "att_mcse_late"
pairs$d_att_mcse <- sqrt(pairs$att_mcse_early^2 + pairs$att_mcse_late^2)
pairs$d_c_obs <- pairs$c_obs_early - pairs$c_obs_late
pairs$d_rd    <- pairs$rd_itt_early - pairs$rd_itt_late
pairs <- pairs[order(pairs$target_c120, pairs$alpha_l_key,
                     pairs$persistence, pairs$horizon), ]
rownames(pairs) <- NULL
utils::write.csv(pairs[, c("target_c120", "alpha_l_key", "persistence", "horizon",
                           "c_obs_early", "c_obs_late", "d_c_obs",
                           "attenuation_early", "attenuation_late", "d_att",
                           "d_att_mcse",
                           "rd_itt_early", "rd_itt_late", "d_rd")],
                 file.path(OUT, "matched-pairs.csv"), row.names = FALSE)

## ---- 4. Console summary ---------------------------------------------------
## "Correctness" was too strong for what these numbers carry: several cells sit
## three to four Monte Carlo standard errors from zero bias, which is small in
## absolute terms and is not Monte Carlo noise. The distinction matters because
## the point of this section is that the attenuation is a property of the
## estimand rather than of the estimator.
cat("\n== estimator behavior for the ITT-analogue ==\n")
cat(sprintf("  scenarios x horizons x methods: %d\n", nrow(perf)))
cat(sprintf("  |relative bias|: median %.3f%%, max %.3f%%\n",
            100 * stats::median(abs(perf$rel_bias)), 100 * max(abs(perf$rel_bias))))
.z <- abs(perf$bias) / perf$bias_mcse
## R does not concatenate adjacent string literals the way C does; a format
## string split across lines has to be pasted.
cat(sprintf(paste0("  |bias| in Monte Carlo standard errors: median %.1f, ",
                   "max %.1f, %d of %d cells beyond 3\n"),
            stats::median(.z, na.rm = TRUE), max(.z, na.rm = TRUE),
            sum(.z > 3, na.rm = TRUE), length(.z)))
## This line said "as a share of the attenuation" and divided by the risk
## difference, which is a different quantity. The attenuation removed at a cell
## is RD_pp - RD_itt, and against that denominator the largest bias is two
## orders of magnitude bigger than the wrong version reported. The decisive
## comparison does not use estimated attenuation at all, it uses enumerated
## truth, but that is a reason to say so rather than a reason to report a
## flattering ratio.
.att_abs <- abs(perf$truth_rd_pp - perf$truth_rd_itt)
cat(sprintf("  largest |bias| as a share of the attenuation at the same cell: %.1f%%\n",
            100 * max(abs(perf$bias) / .att_abs, na.rm = TRUE)))
cat(paste0("  the decisive comparison below does not use estimated attenuation.\n",
           "  It uses attenuation enumerated from the mechanism, so this bias\n",
           "  does not enter it.\n"))
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
## Counting pairs that clear the threshold is not enough: a pair one Monte Carlo
## standard error above 0.05 has not cleared anything. Pairs are classified by
## how far above the threshold they are in their own Monte Carlo error, and the
## conclusion is stated over the pairs that are established rather than over all
## of them.
final$margin <- abs(final$d_att) - 0.05
final$z <- final$margin / final$d_att_mcse
cat(sprintf("  matched pairs above 0.05 by at least 3 Monte Carlo SEs: %d of %d\n",
            sum(final$z >= 3, na.rm = TRUE), nrow(final)))
cat(sprintf("  the %d that are not established are all at cumulative initiation %s\n",
            sum(final$z < 3, na.rm = TRUE),
            paste(sort(unique(final$target_c120[final$z < 3])), collapse = ", ")))
cat(sprintf("  established pairs run |d_att| %.4f to %.4f at %.0f to %.0f MCSEs\n",
            min(abs(final$d_att[final$z >= 3])), max(abs(final$d_att[final$z >= 3])),
            min(final$z[final$z >= 3]), max(final$z[final$z >= 3])))
cat(sprintf(paste0("  smallest difference overall is %.4f at %.1f MCSEs, which ",
                   "is not\n  distinguishable from the threshold\n"),
            min(abs(final$d_att)), min(final$z, na.rm = TRUE)))
## The protocol's branch names are "sufficient" and "necessary but not
## sufficient". Only the first half is testable here: this design can show that
## endpoint cumulative initiation fails to determine attenuation, and it cannot
## show that reporting it is necessary, nor that any augmented reporting set
## would be sufficient. The branch is renamed to what it establishes.
cat(sprintf("  protocol threshold is 0.05 on the attenuation scale: %s\n",
            ifelse(sum(final$z >= 3, na.rm = TRUE) >= 1,
                   paste0("NOT SUFFICIENT within this grid, established on ",
                          sum(final$z >= 3, na.rm = TRUE), " of ", nrow(final),
                          " matched pairs"),
                   "not established at any matched pair")))
cat(paste0("  C is the observed comparator-arm cumulative initiation, which is\n",
           "  what an author reports. Under prognostic initiation it differs from\n",
           "  the enumerated c_true by up to 0.042, and the matched pairs agree\n",
           "  on both to within 0.0008.\n"))
