## Study 2 (PRO-02): run the registered simulation.
##
##   Rscript R/03-truth.R
##   Rscript R/04-run.R
##   Rscript R/04-run.R 1:4
##
## Completed generated-data scenarios are cached by the shared harness.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
stopifnot(file.exists(here("R", "00-config.R")))

source(here("R", "00-config.R"))
source(here("R", "01-dgm.R"))
source(here("R", "02-estimators.R"))
source(here("..", "_shared", "R", "harness.R"))

OUTDIR <- here("results")
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(file.path(OUTDIR, "truth.rds")))
stopifnot(file.exists(file.path(OUTDIR, "design-diagnostics.rds")))
lambda_table <- readRDS(file.path(OUTDIR, "lambda.rds"))

fixed_rows <- function(family, candidates) {
  do.call(rbind, lapply(candidates$candidate, function(id) {
    output_row("candidate", "fixed", "fixed", id, family, Z_95)
  }))
}

selected_pair <- function(selector_name, selection, family, K,
                          method = c("naive", "bonferroni")) {
  method <- match.arg(method)
  selection_fail <- selection$fail %||% NA_character_
  family_fail <- if (any(!is.na(family$table$fail))) {
    "family-nonestimable"
  } else NA_character_
  if (method == "naive") {
    fail <- selection_fail
    critical <- Z_95
  } else {
    ## Critique fix: selected Bonferroni inference fails if any member of the
    ## declared family is nonestimable, and it uses the original declared K.
    fail <- if (!is.na(selection_fail)) selection_fail else family_fail
    critical <- bonferroni_critical(K)
  }
  stage <- if (!is.na(selection_fail)) "selection" else
    if (!is.na(fail)) "simultaneous-family" else NA_character_
  output_row("selector", method, selector_name, selection$candidate,
             family, critical, fail = fail, fail_stage = stage,
             no_threshold = selection$no_threshold %||% NA)
}

tag_rows <- function(out, scen, rep_id) {
  out$replicate <- as.integer(rep_id)
  out$score_alignment <- NA_character_
  out$analysis_scenario <- NA_integer_
  high <- grepl("prognostic_high", out$selector, fixed = TRUE)
  low <- grepl("prognostic_low", out$selector, fixed = TRUE)
  out$score_alignment[high] <- "higher"
  out$score_alignment[low] <- "reduced"
  out$analysis_scenario[high] <- analysis_scenario_id(scen$scenario, "higher")
  out$analysis_scenario[low] <- analysis_scenario_id(scen$scenario, "reduced")
  out
}

blank_rows <- function(scen, rep_id, why) {
  candidates <- candidate_library(scen$K)
  family <- empty_family(candidates, why)
  rows <- list(fixed_rows(family, candidates))
  selectors <- c("workability", "prognostic_high", "prognostic_low",
                 "effect_seeking", "outcome_blinded")
  for (method in c("naive", "bonferroni")) {
    for (selector in selectors) {
      rows[[length(rows) + 1L]] <- output_row(
        "selector", method, selector, family = family,
        critical = if (method == "naive") Z_95 else bonferroni_critical(scen$K),
        fail = why, fail_stage = "replicate")
    }
  }
  for (selector in c("workability", "prognostic_high", "prognostic_low")) {
    rows[[length(rows) + 1L]] <- output_row(
      "selector", "split", selector, family = family,
      critical = Z_95, fail = why, fail_stage = "replicate")
  }
  rows[[length(rows) + 1L]] <- output_row(
    "multiverse", "multiverse", "multiverse",
    fail = why, fail_stage = "replicate")
  tag_rows(do.call(rbind, rows), scen, rep_id)
}

one_rep_impl <- function(scen, rep_id) {
  candidates <- candidate_library(scen$K)
  dat <- gen_replicate(scen, n = scen$n)
  family <- fit_ipw_family(dat, candidates)
  rows <- list(fixed_rows(family, candidates))

  selections <- list(
    workability = workability_select(dat, candidates),
    prognostic_high = prognostic_select(
      dat, candidates, score_higher(dat$Z, dat$S, dat$C, dat$B)),
    prognostic_low = prognostic_select(
      dat, candidates, score_reduced(dat$Z, dat$S, dat$C, dat$B)),
    effect_seeking = effect_seeking_select(family),
    outcome_blinded = balance_select(dat, candidates, family$e)
  )

  for (selector in names(selections)) {
    rows[[length(rows) + 1L]] <- selected_pair(
      selector, selections[[selector]], family, scen$K, "naive")
  }
  for (selector in names(selections)) {
    rows[[length(rows) + 1L]] <- selected_pair(
      selector, selections[[selector]], family, scen$K, "bonferroni")
  }

  ## Critique fix: sample splitting is a separate policy. Selection uses only
  ## the design partition, thresholds are halved, and inference is refitted in
  ## the independent analysis partition.
  analysis_flag <- sample(rep(c(FALSE, TRUE), length.out = nrow(dat)))
  design_dat <- dat[!analysis_flag, , drop = FALSE]
  analysis_dat <- dat[analysis_flag, , drop = FALSE]
  split_family <- fit_ipw_family(analysis_dat, candidates)
  split_selections <- list(
    workability = workability_select(
      design_dat, candidates, CUT_SPLIT_ARM, CUT_SPLIT_EVENTS),
    prognostic_high = prognostic_select(
      design_dat, candidates,
      score_higher(design_dat$Z, design_dat$S, design_dat$C, design_dat$B),
      CUT_SPLIT_ARM),
    prognostic_low = prognostic_select(
      design_dat, candidates,
      score_reduced(design_dat$Z, design_dat$S, design_dat$C, design_dat$B),
      CUT_SPLIT_ARM)
  )
  for (selector in names(split_selections)) {
    s <- split_selections[[selector]]
    stage <- if (!is.na(s$fail %||% NA_character_)) "design-selection" else NA_character_
    rows[[length(rows) + 1L]] <- output_row(
      "selector", "split", selector, s$candidate, split_family, Z_95,
      fail = s$fail %||% NA_character_, fail_stage = stage,
      no_threshold = s$no_threshold %||% NA)
  }

  mv <- multiverse_summary(family)
  rows[[length(rows) + 1L]] <- output_row(
    "multiverse", "multiverse", "multiverse",
    fail = mv$fail, fail_stage = if (!is.na(mv$fail)) "estimation" else NA_character_,
    mv_range = mv$range, mv_iqr = mv$iqr,
    mv_std_range = mv$standardized_range)

  tag_rows(do.call(rbind, rows), scen, rep_id)
}

## Every replicate returns exactly K candidate rows plus 14 registered rows.
## Critique fix: every failure remains in the unconditional denominator.
one_rep <- function(scen, rep_id) {
  tryCatch(one_rep_impl(scen, rep_id), error = function(e) {
    blank_rows(scen, rep_id, paste0("replicate-error:", conditionMessage(e)))
  })
}

scenarios <- attach_lambdas(build_scenarios(), lambda_table)
args <- commandArgs(TRUE)
sel <- seq_len(nrow(scenarios))
if (length(args) && grepl("^\\d+:\\d+$", args[1])) {
  p <- as.integer(strsplit(args[1], ":", fixed = TRUE)[[1]])
  sel <- intersect(seq(p[1], p[2]), sel)
}

res <- run_design(
  one_rep, scenarios, n_rep = N_REP, master_seed = MASTER_SEED,
  outdir = OUTDIR, workers = WORKERS, resume = TRUE, only = sel)

write_provenance(
  OUTDIR,
  packages = c("stats", "future", "furrr"),
  extra = list(
    study = "PRO-02 recorded finite protocol search",
    generated_scenarios = nrow(scenarios),
    registered_analysis_scenarios = 2L * nrow(scenarios),
    replicates = N_REP,
    workers = WORKERS,
    master_seed = MASTER_SEED,
    scope = "recorded finite searches only"
  )
)

message(sprintf("run returned %d rows", if (is.data.frame(res)) nrow(res) else 0L))
