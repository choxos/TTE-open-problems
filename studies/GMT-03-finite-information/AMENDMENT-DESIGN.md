# GMT-03 proposed registered amendment

Proposed amendment to the registered protocol in
`documentation/studies/designs/GMT-03-large-databases-yield-small-effective-sample-revised.json`.
It would be committed before any replicate of the amended run is drawn, under a new master seed
(20260923) with new calibration, validation, pilot and analysis seeds (20260924 to 20260927). Nothing
has been run under the registered seeds, so there are no replicates to keep or discard.

## 1. Why the registered design cannot answer

**The compatibility factor cannot be calibrated (BLOCKED.md, confirmed).** The registered mechanism
reaches C_min = 0.1714 at κ = 0 and falls only to 0.1344 at κ = 2.25. Extending κ does not help: a
scratch recomputation with 20,000 histories gives C_min = 0.1326 at κ = 3, 0.1282 at 4 and 0.1189 at
6. The reason is structural. The treatment predictor multiplied by κ is
b_t = −0.75 + 0.7X + 0.6G + 0.9L_t (t ≥ 1). For G = 1 and X > 0.214, b_t > 0 whatever L_t is, so as κ
grows those people become deterministic always-treaters and stay compatible with the always-treat
regime; this sign-stable subpopulation alone holds 0.25 × 0.39 ≈ 0.10 of the population, and people with
L_t = 1 throughout add to it. C_1(κ) therefore has a floor near 0.13, and the targets 0.12, 0.08, 0.04
and 0.02 cannot be reached by any κ.

**The stated reason is incomplete: the pipeline cannot return a single estimate.** BLOCKED.md says
everything other than calibration is in place. Running `estimate_exact` and `fit_msm` on one generated
data set (scratch copies only) raised the first two defects below, and the third is visible in the code
once they are patched. Each turns every replicate into a `replicate-error` row without stopping the
run:

1. `path_diagnostics(paths, dat, method, fail = NULL)` passes `fail = NULL` to `data.frame()`, which in
   R 4.6 raises "arguments imply differing number of rows: 1, 0". `estimate_exact` calls it with the
   default and `estimate_replicate` passes `mf$fail`, which is `NULL` whenever the fit succeeds.
2. In `build_stabilized_long`, each element of `pieces` stores `cell = gg * N_MONTHS + tt` and
   `strategy = gg` as scalars, so `long$cell` has one entry per arm-month rather than one per row and
   `rowsum(..., long$cell)` in `fit_weighted_multinomial` fails with "incorrect length for 'group'".
3. `cat <- ifelse(dat$event_month[idx] == tt, dat$event_type[idx], 0L)` is `NA` for everyone who never
   has an event, because `event_month` is `NA` for them. The outcome category is then missing on most
   person-months, which is the `NA == x` failure recorded in CLAUDE.md for SEQ-01.

A fourth, smaller one: `exact_t` sets `df <- floor(min(ESS)) − 1`, which is 0 when the smallest cell
ESS lies in (1, 2), and `qt(0.975, 0)` is `NaN`; the protocol covers only ESS ≤ 1.

**The marginal structural model cannot converge as registered.** It saturates the multinomial outcome
model in arm by month: 120 cells per endpoint. At the common event rates the monthly hazard is about
0.0017, so even at n = 16,000 and C_min near 0.13 the weaker arm expects about 3.4 events per cell, the
probability that none of the 240 endpoint-cells is empty is below 10⁻³, and the model returns
`outcome-separation`. With the three defects patched in a scratch copy, a yearly collapse of the cells
(10 per endpoint) still separated at n = 1000 (common events, κ = 1.075) and at n = 4000 (κ = 2.175).
MSM availability would be near zero in every cell, including K0, so the operational-failure rule
(which needs K0 availability ≥ 0.98) cannot fire and every MSM cell is indeterminate. The MSM
co-primary family is unreachable as registered.

**The registered size does not fit.** The protocol has 180 scenarios × 4000 replicates = 720,000
replicates, plus 16 sentinel cells × 4000 replicates × 399 bootstrap refits. Measured CPU per replicate
on this machine (patched scratch copy, candidate-C mechanism below, common events, κ = 1.075):
exact-regime methods 1.7 s at n = 1000, 2.5 s at n = 4000 and 8.6 s at n = 16,000; the MSM with a
smooth baseline adds 4.3 s at n = 4000 and 16.8 s at n = 16,000. That is roughly 11 s per replicate on
average, about 2200 CPU-hours for the core and validation replicates alone; the sentinel bootstrap adds
two orders of magnitude more. The in-code "overnight profile" (20 replicates) could never classify a
cell, as its own comment says.

## 2. What changes

Everything not listed stays as registered.

1. **Treatment mechanism.** Replace the κ-multiplied predictors by
   b_0 = −1.40 + 0.8X + 0.6G + 2.7L_0 at t = 0 and b_t = −1.35 + 0.7X + 0.6G + 2.7L_t for t ≥ 1.
   The X and G coefficients, the persistence term 4.0(2A_{t−1} − 1), the κ grid (0 to 2.25 by 0.025),
   the targets 0.12, 0.08, 0.04, 0.02, the 0.01 tolerance and the outcome-blind calibration procedure
   are unchanged. Reason: with these coefficients the sign of b_t is set by L_t for every (X, G) on
   their support (b_t ≤ −0.05 when L_t = 0 and b_t ≥ 0.65 when L_t = 1; b_0 < 0 when L_0 = 0 and
   b_0 ≥ 0.50 when L_0 = 1), so no subpopulation is deterministically compatible and C_min(κ) falls
   toward zero as κ grows. The formula appears in three functions,
   `gen_replicate`, `compatibility_pass` and `mechanism_expected_counts`; all three must change
   together, or the calibration and the validation quadrants will describe a mechanism that is not
   the one simulated.
2. **Implementation defects 1 to 4 above are fixed before any seed is used.** For defect 4, an ESS in
   (1, 2) makes the t interval unavailable with the reason `insufficient-cell`, the same outcome the
   protocol gives ESS ≤ 1. A smoke run (`TTE_SMOKE=2`) in the four corners (n ∈ {1000, 4000},
   κ ∈ {K0, K4}, common events) must return no `replicate-error` row and a non-missing exact_fixed
   estimate for the overall primary-event risk difference before the pilot starts.
3. **MSM baseline hazard.** Replace the saturated strategy-by-month intercepts with, for each endpoint
   and strategy, an intercept plus a natural cubic spline in month with fixed interior knots at months
   20 and 40 and boundary knots at 1 and 60 (3 basis columns). The covariate terms X, G, L_0 and
   strategy-by-G are unchanged. Separation is now declared only when an endpoint has zero weighted
   events in an arm, which is a genuine failure the availability measures should record. Reason: the
   saturated model is not estimable at the registered event rates (section 1).
4. **Scope of the run (the smallest informative version; see section 4).**
   - Core: n ∈ {1000, 4000} × K0 to K4 × primary {rare, common} × competing {rare, common}:
     40 scenarios, R = 1000 replicates each.
   - High-information arm: n = 16,000 × {K0, K2, K4} × primary {rare, common} × competing common:
     6 scenarios, R = 500. This keeps the registered purpose of the 16,000 level (rare-event compatible
     counts above 20) at three compatibility levels.
   - Sentinel bootstrap: n = 4000, {K0, K4}, common/common; the first 25 replicates of each; B = 199
     resamples; available if at least 190 succeed (registered 380 of 399, the same 95%).
   - The 120-scenario held-out validation of the warning rule becomes a separately registered stage 2
     with its own budget (section 5). Its manifest is built and frozen now, from the amended mechanism,
     so that stage 2 cannot be shaped by stage 1 results.
5. **Classification denominators follow R.** A cell needs at least 0.9R valid intervals (registered:
   3600 of 4000, the same fraction). The Wilson-bound thresholds (availability 0.95 and 0.90, K0
   availability 0.98, coverage 0.90 and 0.925, attribution 0.05 and −0.02) are unchanged.

## 3. The gates can pass

- **Calibration (0.01 tolerance).** With 20,000 histories the amended mechanism reaches C_min = 0.1209,
  0.0794, 0.0406 and 0.0197 at κ = 0.625, 1.075, 1.650 and 2.175: distance from target 0.0009, 0.0006,
  0.0006 and 0.0003, margin at least 0.009. Near K4 the curve falls about 0.0015 per grid step of 0.025,
  so grid resolution alone cannot open a gap above 0.001. C_min at the grid edge (κ = 2.25) is 0.0176,
  below the lowest target. The registered 2,000,000-history calibration will move these values in the
  fourth decimal place at most.
- **Monotone compatibility and distinct levels.** C_min decreases monotonically on the checked grid
  (0.1714 to 0.0176), so the four selected κ values are distinct and ordered.
- **Treatment probabilities inside [1e−8, 1 − 1e−8].** The largest linear predictor at K4 is
  4 + 2.175 × 2.65 ≈ 9.8, a probability of 1 − 5.5 × 10⁻⁵. The bound cannot be hit.
- **Weights below 1e12.** A compatible never-treat path accumulates −log(1 − p_t) over 60 months; for
  the scratch replicate at n = 4000, K4, the minimum monthly risk-set ESS was 3.4 and nothing
  overflowed. Weights of order 10⁵ need dozens of months at p_t near 0.9 while staying untreated, which
  the persistence term makes rare.
- **At least 0.9R valid exact_fixed intervals per cell.** exact_fixed fails only on a zero arm
  denominator or overflow. The smallest expected compatible count is n × C_min × subgroup share =
  1000 × 0.02 × 0.25 = 5 at 60 months in the G1 subgroup at K4, so P(zero denominator) ≈ e⁻⁵ = 0.007
  and availability is about 0.99 even there. The overall cells have 20 or more.
- **MSM availability.** With the spline baseline, failure requires zero weighted events of an endpoint
  in an arm. Expected events in the weaker arm at the horizon are n × C × 60-month risk: common events at
  n = 4000, K4 give 4000 × 0.02 × 0.10 = 8, P(zero) ≈ e⁻⁸; rare events at n = 1000, K4 give 0.2, so the
  MSM is mostly unavailable there. That cell then reaches operational failure only if its matched K0
  cell has availability lower bound ≥ 0.98: at n = 1000, rare, K0 the expectation is
  1000 × 0.17 × 0.01 = 1.7 events, P(zero) = 0.18, so it will be indeterminate. That is the honest
  outcome for the lowest-information cells, and the rule handles it without change. Common-event and
  n ≥ 4000 cells can reach failure or adequacy.
- **Interval failure and adequacy are both reachable at R = 1000.** With 1000 intervals, observed
  coverage 0.88 gives a Wilson upper bound of 0.899 (< 0.90, failure) and observed coverage 0.94 gives
  a lower bound of 0.924, 0.945 gives 0.929 (≥ 0.925, adequate). The registered example (coverage near
  0.85 or 0.95) still separates. At R = 500 (the n = 16,000 arm) the corresponding observed values are
  0.87 and 0.95.
- **Support attribution.** The K0 comparison uses common random numbers. The coverage difference for
  independent arms at 0.95 and 0.90 has standard error about 0.0116 at R = 1000; the required upper
  bound below −0.02 is met when the true drop is at least about 0.043, and the protocol's 0.05 change
  threshold is reachable. Positive correlation from common random numbers only narrows this.
- **Truth tolerance.** Unchanged: truth depends only on α_Y, α_D and the strategies, not on κ, so the
  four core truths are shared by all K levels and the registered batch extension applies.
- **Derivative validation (maximum disagreement below 1e−6).** Unchanged and cheap; it is run on the
  amended mechanism after the defect fixes.

## 4. Cost

From the measured CPU per replicate (section 1), with 1 s added for data generation and diagnostics:
about 3.5 s at n = 1000, 8 s at n = 4000 and 27 s at n = 16,000.

| Component | Replicates | CPU-s each | CPU-hours |
|---|---:|---:|---:|
| Core, n = 1000 (20 scenarios) | 20,000 | 3.5 | 19.4 |
| Core, n = 4000 (20 scenarios) | 20,000 | 8 | 44.4 |
| n = 16,000 arm (6 scenarios) | 3,000 | 27 | 22.5 |
| Sentinel bootstrap (2 cells × 25 × 199 MSM refits without the sandwich) | 9,950 | 3 | 8.3 |
| Calibration (2,000,000 histories, grid of 91), truths (4 core), pilot, derivative check | | | about 4 |
| **Total** | | | **about 99** |

The machine's load changes wall time, not these figures; the registered benchmark before launch
replaces them with measured medians and 90th percentiles by cell.

## 5. What the amended study no longer answers

- **Validation of the candidate warning rule** (Kish risk-set ESS below 100 or effective event count
  below 20) is not answered by this stage. Stage 2, registered separately, would run the frozen
  120-scenario manifest at R = 300 (enough to classify coverage 0.95 as adequate at a Wilson lower
  bound of 0.925 and coverage 0.85 as failure); at about 10.3 CPU-s per replicate for the manifest's
  log-uniform n on [800, 20,000] it needs about 103 CPU-hours. Without it, the study describes when
  coverage fails but does not say whether the flag predicts it out of sample.
- **Precision.** R falls from 4000 to 1000 (500 at n = 16,000), so cells whose coverage lies between
  about 0.88 and 0.94 become indeterminate rather than classified.
- **The n = 16,000 level** covers three compatibility levels and common competing events only; rare
  competing events at n = 16,000 are not studied.
- **The confounding structure differs from the registered one.** The L_t coefficient in the treatment
  predictor triples (0.9 to 2.7), so time-varying confounding through L is much stronger at every
  K > 0. Results describe that mechanism.
- **The MSM is a different estimator.** A smooth spline baseline hazard replaces saturated
  arm-by-month intercepts; its bias reflects that smoothing. The registered saturated MSM is not
  evaluated, because it cannot be fitted at these event rates.
- **The bootstrap comparator** is checked in 2 of the 16 registered sentinel cells, on 25 replicates
  each, and supports no claim outside them.
