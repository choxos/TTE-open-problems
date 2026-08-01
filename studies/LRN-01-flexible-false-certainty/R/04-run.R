## LRN-01 support stress study: resumable replicate driver.
## Usage: Rscript R/04-run.R [i:j]

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUTDIR <- here("results")
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
manifest_file <- file.path(OUTDIR, "projection-manifest.csv")
manifest <- projection_manifest_frame()
if (file.exists(manifest_file)) {
  old <- utils::read.csv(manifest_file, stringsAsFactors = FALSE)
  if (!isTRUE(all.equal(old, manifest, check.attributes = FALSE)))
    stop("the projection manifest differs from the frozen manifest")
} else utils::write.csv(manifest, manifest_file, row.names = FALSE)

empty_rows <- function(scen, rep_id, why) {
  data.frame(observed_law = scen$observed_law, rep_id = rep_id, method = METHODS,
             n = scen$n, complexity = scen$complexity,
             support_key = scen$support_key, support_kind = scen$support_kind,
             geometry = scen$geometry, boundary = scen$boundary,
             est = NA_real_, se = NA_real_, lo = NA_real_, hi = NA_real_,
             fail = why, numerical_warning = FALSE,
             logical_range_flag = NA, conventional_green = FALSE,
             support_red = NA, competitive_loss = NA,
             factual_below_001 = NA_real_, common_follow0 = NA_real_,
             common_follow1 = NA_real_, common_ess0 = NA_real_, common_ess1 = NA_real_,
             common_maxw0 = NA_real_, common_maxw1 = NA_real_,
             method_follow0 = NA_real_, method_follow1 = NA_real_,
             method_ess0 = NA_real_, method_ess1 = NA_real_,
             method_maxw0 = NA_real_, method_maxw1 = NA_real_,
             method_capped0 = NA_real_, method_capped1 = NA_real_,
             jacobian_condition = NA_real_, score_residual = NA_real_,
             jacobian_seconds = NA_real_, ridge_seconds = NA_real_,
             outcome_loss_flex = NA_real_, outcome_loss_main = NA_real_,
             elapsed_seconds = NA_real_, memory_mb = NA_real_,
             stringsAsFactors = FALSE)
}

add_dynamic_columns <- function(out) {
  for (t in VISITS) {
    out[[paste0("treat_loss_flex_t", t)]] <- NA_real_
    out[[paste0("treat_loss_main_t", t)]] <- NA_real_
    out[[paste0("retained_g_t", t)]] <- NA_character_
    out[[paste0("rich_p_t", t)]] <- NA_real_
    for (a in 0:1) {
      out[[paste0("trunc_a", a, "_t", t)]] <- NA_real_
      out[[paste0("map_any_a", a, "_t", t)]] <- NA_real_
      out[[paste0("map_prob_a", a, "_t", t)]] <- NA_real_
      out[[paste0("map_lev_a", a, "_t", t)]] <- NA_real_
    }
  }
  out
}

one_rep <- function(scen, rep_id) {
  started <- proc.time()[["elapsed"]]
  dat <- tryCatch(gen_replicate(scen, scen$n), error = function(e) e)
  if (inherits(dat, "error")) return(add_dynamic_columns(empty_rows(scen, rep_id, "dgm-failed")))
  folds <- balanced_folds(dat)
  cross <- tryCatch(estimate_crossfit(dat, folds),
                    error = function(e) crossfit_failure(paste0("crossfit-error: ", conditionMessage(e))))
  gmain <- tryCatch(fit_g_models(dat, seq_len(nrow(dat)), "main"), error = function(e) NULL)
  ipw <- if (is.null(gmain)) model_failure("treatment-model-error") else
    tryCatch(estimate_ipw(dat, gmain), error = function(e) model_failure(paste0("ipw-error: ", conditionMessage(e))))
  main <- if (is.null(gmain)) model_failure("treatment-model-error") else
    tryCatch(estimate_main_aipw(dat, gmain), error = function(e) model_failure(paste0("aipw-error: ", conditionMessage(e))))
  objects <- list(ipw = ipw, main_aipw = main, flex_aipw = cross, flex_aipw_map = cross)
  out <- add_dynamic_columns(empty_rows(scen, rep_id, NA_character_))

  if (model_ok(cross)) {
    out$factual_below_001 <- cross$factual_below_001
    out$common_follow0 <- cross$weight0$followers; out$common_follow1 <- cross$weight1$followers
    out$common_ess0 <- cross$weight0$ess; out$common_ess1 <- cross$weight1$ess
    out$common_maxw0 <- cross$weight0$max; out$common_maxw1 <- cross$weight1$max
    out$support_red <- cross$support_red
    out$competitive_loss <- cross$competitive_loss
    out$ridge_seconds <- cross$ridge_seconds
    out$outcome_loss_flex <- cross$outcome_loss_flex
    out$outcome_loss_main <- cross$outcome_loss_main
    for (t in VISITS) {
      out[[paste0("treat_loss_flex_t", t)]] <- cross$treatment_loss_flex[t + 1L]
      out[[paste0("treat_loss_main_t", t)]] <- cross$treatment_loss_main[t + 1L]
      out[[paste0("rich_p_t", t)]] <- cross$rich_p[t + 1L]
      for (a in 0:1) {
        out[[paste0("trunc_a", a, "_t", t)]] <- cross$truncation[t + 1L, a + 1L]
        out[[paste0("map_any_a", a, "_t", t)]] <- cross$support_mass[t + 1L, a + 1L]
        out[[paste0("map_prob_a", a, "_t", t)]] <- cross$probability_mass[t + 1L, a + 1L]
        out[[paste0("map_lev_a", a, "_t", t)]] <- cross$leverage_mass[t + 1L, a + 1L]
      }
    }
  }

  for (i in seq_along(METHODS)) {
    method <- METHODS[i]; obj <- objects[[method]]
    out$fail[i] <- if (model_ok(obj)) NA_character_ else obj$fail
    if (model_ok(obj)) {
      out$est[i] <- obj$est; out$se[i] <- obj$se
      out$lo[i] <- obj$est - 1.96 * obj$se; out$hi[i] <- obj$est + 1.96 * obj$se
      out$numerical_warning[i] <- isTRUE(obj$numerical_warning)
      out$logical_range_flag[i] <- obj$est < -1 || obj$est > 1
      out$conventional_green[i] <- isTRUE(cross$common_diagnostic_green)
      if (method == "flex_aipw_map" && isTRUE(cross$support_red))
        out$conventional_green[i] <- FALSE
      if (!is.null(obj$condition)) out$jacobian_condition[i] <- obj$condition
      if (!is.null(obj$score_residual)) out$score_residual[i] <- obj$score_residual
      if (!is.null(obj$jacobian_seconds)) out$jacobian_seconds[i] <- obj$jacobian_seconds
    }
  }
  if (model_ok(ipw)) {
    i <- match("ipw", METHODS)
    for (a in 0:1) {
      z <- ipw$diagnostics[[paste0("a", a)]]
      out[[paste0("method_follow", a)]][i] <- z$followers
      out[[paste0("method_ess", a)]][i] <- z$ess
      out[[paste0("method_maxw", a)]][i] <- z$max_weight
      out[[paste0("method_capped", a)]][i] <- z$n_capped
    }
    for (t in VISITS) out[[paste0("retained_g_t", t)]][i] <- ipw$diagnostics$retained[t + 1L]
  }
  if (model_ok(main)) {
    i <- match("main_aipw", METHODS)
    for (t in VISITS) for (a in 0:1)
      out[[paste0("trunc_a", a, "_t", t)]][i] <- main$truncation[t + 1L, a + 1L]
  }
  elapsed <- proc.time()[["elapsed"]] - started
  out$elapsed_seconds <- elapsed
  out$memory_mb <- sum(gc()[, 2])
  out
}

scenarios <- build_observed_laws()
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

res <- run_design(one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
                  outdir = OUTDIR, workers = WORKERS, resume = TRUE, only = sel)
write_provenance(
  OUTDIR,
  packages = c("stats", "splines", "future", "furrr"),
  extra = list(study = "LRN-01 estimator-specific false certainty",
               observed_laws = nrow(scenarios), replicates = N_REP,
               workers = WORKERS, master_seed = MASTER_SEED,
               scaled_pilot = TRUE,
               projection_seed = PROJECTION_SEED,
               weight_cap = WEIGHT_CAP,
               support_probability_threshold = SUPPORT_PROB_THRESHOLD,
               support_mass_threshold = SUPPORT_MASS_THRESHOLD))
message(sprintf("done: %d returned rows", nrow(res)))
