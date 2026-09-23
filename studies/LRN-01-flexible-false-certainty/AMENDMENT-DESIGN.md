# LRN-01 proposed registered amendment

Proposed amendment to the registered protocol in
`documentation/studies/designs/LRN-01-flexible-estimation-is-presented-as-a-remedy-revised.json`.
It would be committed before any replicate of the amended run is drawn, under a new master seed
(20260923) and a calibration seed (20260924). The projection manifest (seed 7312026) is unchanged. No
performance replicate has been run; `results/smoke.rds` holds three smoke replicates.

## 1. Why the registered design cannot answer

**The cost figure is elapsed time, and still too large as CPU time.** The status note's 87 seconds per
replicate is the smoke run's `elapsed_seconds` (82 to 90 s) on a machine at load average near 500; the
main-effects AIPW Jacobian alone logged 38 to 42 s of elapsed time. Measured CPU for a complete replicate
(cross-fitted flexible AIPW with map, fixed-cap IPW with stacked sandwich, main-effects AIPW with
stacked sandwich): 10.2 s (strong overlap, C = 0, n = 1000), 8.8 s (curved exact holes, C = 1,
n = 1000) and 28.4 s (curved exact holes, C = 1, n = 4000). The registered 68 laws × 2000 replicates
cost about 34 × 2000 × 9.5 s + 34 × 2000 × 28.4 s ≈ 716 CPU-hours, not 3300, and still seven times the
budget. The implemented 100 replicates cannot classify anything (`00-config.R` says so).

**The primary outcome is fixed at zero by the diagnostic definition.** The primary event is
F = 1{common conventional green} × 1{compatible-set coverage fails}. Common green requires, in both
strategies, a maximum uncapped cumulative follower weight of at most 50, an ESS of at least 25% of
complete followers, and fewer than 1% of factual probabilities below 0.01. The registered treatment
persistence (1.10(A_{t−1} − 0.5)) makes six-visit sustained adherence rare: 19 to 37 never-treat
followers per 1000 in strong overlap, with follower weights near 1/0.03. With the *true* treatment
probabilities, the most favorable case, green occurred in 100 datasets per law at n = 1000 in:

| laws | green |
|---|---:|
| strong and moderate overlap (4 laws) | 0.00 |
| accumulated holes, exact and practical (4) | 0.00 |
| disconnected holes (4) | 0.00 to 0.02 |
| severe overlap (2) | 0.07 to 0.12 |
| curved and interaction holes (8) | 0.04 to 0.17 |
| linear holes (12) | 0.05 to 0.47 |

The binding criterion is the maximum weight (medians 30 to 200). F is then zero for every method in
nearly every replicate, the paired flexible-minus-conventional excesses are zero, the "not supported"
branch (upper bounds at most 0.05 in every material cell) fires by construction, and the "supported"
branch (lower bounds at least 0.10 in every cell) cannot be reached. This is the MER-01 pattern: a gate
the registered mechanism cannot pass.

**The implementation makes it worse by computing green from the wrong model.** In `estimate_crossfit`,
`p1_obs` and `p_req`, which feed `common_diagnostic_green` and the common ESS and weight columns, are the
cross-fitted predictions of the *rich* (flexible) treatment models. The protocol computes the common
diagnostics from the fold-specific main-effects treatment fits ("12 fold-specific main-effects treatment
fits for common diagnostics and loss comparison", runtime section; "diagnostic-only fold-specific
main-effects treatment fits use the same two folds as the flexible method", IPW method), and a status
meant to be common to all methods should not be defined by one method's overfitting. With the rich
predictions the median maximum follower weight was 3,555 to 73,464 at n = 1000 and 236 to 409 at
n = 4000, and green occurred in 0 of 64 datasets across strong-overlap and curved-exact laws even after
raising persistence to 5; with the main-effects predictions on the same datasets it occurred in 10 of 64.

**The map-success branch is at risk in the strong-overlap cells.** The smoke run's map was red in 3 of 3
strong-overlap replicates (C = 0, n = 1000), mostly from the leverage component at single visits
(weighted flagged mass 0.06 to 0.11 among about ten never-treat followers per validation fold). With
persistence 5 it was red in 1 of 8 (C = 0) and 4 of 8 (C = 1). Map success needs specificity of at least
0.90 in every strong-overlap cell. The specificity cell's truth is defined per visit (below-0.025 mass at
most 0.005), while the map's red status responds to cumulative sparsity of sustained followers; a red
map there may be detecting a real support problem that the truth definition does not count.

## 2. What changes

Everything not listed stays as registered.

1. **Which predictions define common green.** The primary-performance text says only "from cross-fitted
   treatment predictions", which admits both the flexible and the main-effects models; the runtime
   section assigns the fold-specific main-effects fits to "common diagnostics". This amendment fixes the
   main-effects reading: the common conventional green status and the common ESS, follower and
   maximum-weight diagnostics are computed from the fold-specific main-effects cross-fitted treatment
   predictions. The owner should confirm it. The flexible model's own predictions still drive the flexible
   estimator and the support map.
2. **Treatment persistence by outcome-blind calibration.** The coefficient 1.10 on (A_{t−1} − 0.5) in
   η_A becomes κ_A, the smallest value in {7, 8, 9, 10} such that, with the calibration seed and 100
   datasets per law drawn at n = 4000 from the mechanism alone:
   (a) main-effects cross-fitted common green occurs in at least 50% of datasets in every exact-hole
   law of the amended grid; and
   (b) every fold-specific rich and main-effects treatment model converges (`converged = TRUE`, finite
   predictions) in at least 97% of datasets in every law.
   Neither criterion uses Y, a coverage result or the support map's status. The risk truths,
   compatible spans and zero-probability masses are computed on intervention paths and do not depend on
   κ_A; the below-0.025 masses do, because the required-action probability on an intervention path
   includes the persistence term, so the practical-materiality and strong-overlap specificity labels
   must be recomputed. `results/truth-cache/` is deleted before the amended truth run. If no grid
   value passes, the primary aim is declared unreachable before any replicate is drawn and only the
   support-map aim runs.
3. **Grid: n = 4000 and C = 1 only.** Laws: the seven exact-hole geometries (linear b = 1.00, 1.25, 1.50,
   curved, disconnected, interaction, accumulated), their seven practical pairs, and strong overlap:
   15 laws, 57 estimand scenarios. Dropped: n = 1000, C = 0, moderate and severe soft overlap. Reason:
   cost (section 4). C = 1 at n = 4000 is where the flexible workflow has its registered approximation
   advantage and its intervals are narrowest, so it is where flexible-specific false certainty can
   appear if it exists at all.
4. **Replicates R = 600 per law.** The minimum completed per required cell becomes 450 (the registered
   1500 of 2000, the same 75%). The strong-overlap convergence gate, registered at n = 4000, is
   unchanged.
5. **The support-map gate is left as registered.** κ_A is not chosen with any reference to the map;
   calibrating the mechanism on the behavior of a method under study would tune the result.

## 3. The gates can pass

- **Material exact geometries** (zero-probability mass ≥ 0.05 and log(2) span ≥ 0.05). These are
  properties of the intervention paths and are untouched by κ_A; the truth run, not yet
  complete (`results/truth-cache` holds one scenario), decides them as registered.
- **Common green is reachable.** Main-effects cross-fitted green at C = 1, n = 1000 was 4 to 9 of 12 per
  exact-hole law at κ_A = 7 and 5 of 10 to 11 of 12 at κ_A = 9 (curved 11/12, disconnected 8/12,
  interaction 8/12, accumulated 5/10); strong overlap 9/12 and 11/12. The calibration criterion (a)
  makes at least 0.5 hold at n = 4000 in every exact-hole law by construction, or stops the primary aim.
- **Treatment-model convergence.** At κ_A = 9, n = 1000, the rich treatment models converged in 23 of 24
  fold fits (strong and curved-exact, C = 1); n = 4000 doubles the training rows. Criterion (b)
  guarantees at least 0.97.
- **Both primary branches are reachable.** The decision family has 7 cells × 2 comparators = 14
  one-sided bounds, Bonferroni critical value 2.69. With the paired-indicator standard deviation at
  most 0.7, the bound half-width at R = 600 is 2.69 × 0.7/√600 = 0.077. "Supported" needs a true excess of
  at least about 0.18 in every cell; F_flex can be as large as P(green), which is at least 0.5 by
  construction, so excesses of that size are possible.
  "Not supported" needs, at a true excess of zero, a paired standard deviation of at most
  0.05 × √600/2.69 = 0.455, that is a discordance between F_flex and F_conventional of at most about
  0.21.
- **Support-map branches.** Sensitivity and specificity use Wilson bounds with Bonferroni over 7
  material exact, 7 practical and 1 strong cell plus 7 reduction bounds (22, critical value 2.84). An
  observed rate of 0.96 at R = 600 has a lower bound of about 0.94, so the success thresholds of 0.90 are
  reachable; failure (upper bound ≤ 0.80) is reachable by an observed rate near 0.75. Whether the
  strong-overlap specificity passes is unknown (section 1) and is left to the run.
- **Strong-overlap convergence ≥ 0.90 (simultaneous lower bound) for every method at n = 4000.** Treatment
  models by criterion (b); the main-effects Q regressions are quasibinomial main-effects fits that
  converged in all smoke and timing replicates.

## 4. Cost

Measured CPU per replicate at n = 4000 (curved exact holes, C = 1): 28.4 s.

| Component | Count | CPU-hours |
|---|---:|---:|
| Main run: 15 laws × 600 replicates × 28.4 s | 9,000 | 71.0 |
| Calibration: up to 4 grid values × 15 laws × 100 datasets × about 6 s of treatment fits | 6,000 | at most 10.0 |
| Registered sandwich-versus-bootstrap check: 10 datasets × 100 resamples × 28.4 s | 1,000 | 7.9 |
| Truth (two complexity levels, registered; only C = 1 now needed) | | about 2 |
| **Total** | | **about 83 to 91** |

The calibration stops at the first κ_A that passes, so its expected cost is under half the maximum.

## 5. What the amended study no longer answers

- **n = 1000 and C = 0.** No result for small samples or for the main-effects law where conventional
  modeling is correctly specified. Removing those cells also removes places where the "supported"
  branch was least likely and the "not supported" branch most likely, so both branches are reached
  with fewer cells than registered; the conclusion is restricted to C = 1, n = 4000.
- **Moderate and severe soft overlap.** These were descriptive cells; they no longer appear.
- **Observed treatment patterns.** With κ_A of 7 or more, the observed continuation probability is
  about 0.97 or more at every visit, so observed treatment is nearly sustained after the first visit.
  Results describe that setting, not one with frequent switching.
- **Precision.** R falls from 2000 to 600, so the band of indeterminate results around 0.10 and 0.05
  widens (section 3).
- **The meaning of "strong overlap" for the map.** Unchanged in definition; see the last paragraph of
  section 1 for why its specificity may fail for a reason that is not the map's error.

The checks behind section 1 (scratch scripts `green_check.R`, `persist_check.R`, `green_xfit.R`,
`green_main.R`, `map_check.R`, `rich_conv.R` and `timing.R`) used about 12 CPU-minutes and wrote nothing
under `results/`.
