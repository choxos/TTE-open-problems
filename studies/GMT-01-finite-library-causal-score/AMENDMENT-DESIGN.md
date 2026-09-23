# GMT-01 proposed registered amendment

Proposed amendment to the registered protocol in
`documentation/studies/designs/GMT-01-cross-validation-for-longitudinal-nuisance-m-revised.json`.
It would be committed before any replicate of the amended run is drawn, under a new master seed
(20260923) and a new calibration seed (20260924). Only the 80-replicate feasibility check (seed
777001) has been run; it is not part of any analysis.

## 1. Why the registered design cannot answer

**FEASIBILITY.md is right in direction and wrong in magnitude and scope.** Its figure of a never-treat
effective sample size of 1.4 per 4000 people is `true_ess_a0` from `results/dgm-check.csv` (71.7 at
n = 200,000) divided by 50. The ESS of heavy-tailed weights does not scale linearly with n, and the
population check is itself unstable: scenarios 2 and 20 have identical treatment and retention laws and
report 71.7 and 770.2. Measured directly on 400 datasets per scenario at n = 4000 with the true weights
(`true_regime_weight`), the never-treat ESS in scenario 2 has median 33.5, not 1.4, and the minimum
regime ESS falls below the registered floor of 10 in 15% of datasets.

**The binding gate is the positive branch, not the uninformative floor.** The positive branch requires
a Wilson lower bound of at least 0.93 for combined-selector convergence in every one of the eight
γ_Z = 0 scenarios. That needs a true convergence rate of about 0.96 at the implemented 500 replicates
and about 0.945 at the registered 2000. Every `low-ess` failure is a dataset in which the terminal
weights of one regime have ESS below 10, and the probability of that under the true weights at
n = 4000 is:

| scenario | shape | s | P(min regime ESS < 10) |
|---:|---|---:|---:|
| 1 | all main effects | 0.65 | 0.015 |
| 7 | nonlinear treatment | 0.65 | 0.072 |
| 13 | nonlinear censoring | 0.65 | 0.058 |
| 19 | nonlinear outcome | 0.65 | 0.015 |
| 2 | all main effects | 1.25 | 0.152 |
| 8 | nonlinear treatment | 1.25 | 0.110 |
| 14 | nonlinear censoring | 1.25 | 0.158 |
| 20 | nonlinear outcome | 1.25 | 0.207 |

True-weight failure tracks the estimator's: across the eight scenarios the feasibility run's
predictive-CV failure rate was 10 of 80 (0.125) against a true-weight mean of 0.098. The gate fails in
six of eight scenarios, including two with good separation. FEASIBILITY.md attributes the problem to the
poor-separation level only; the nonlinear treatment and censoring shapes fail at s = 0.65 as well. The
cause is structural: treatment prevalence is 53% to 61% at every visit, so the never-treat regime is the
starved one (median ESS 75 against 263 for always-treat in scenario 1), and the quadratic terms in L
act on an unbounded Gaussian L, so a handful of people with extreme L who stayed untreated carry most of
the never-treat weight.

**The implemented replicate count also blocks the negative branch.** `00-config.R` runs 500 replicates
rather than the registered 2000. At 500 and paired discordance 0.20, the 95% half-width for the
coverage difference is 1.96 √(0.20/500) = 0.039, so a true gain of zero has an upper bound near 0.039,
above the 0.03 the negative branch requires. Only the registered 2000 (half-width 0.0196) makes that
branch reachable.

**Levers already tested, all on the data-generating mechanism only (no estimator output).** Lowering the
poor level to 0.75 at n = 4000 leaves 0.033 to 0.062 in the poor cells. Doubling n to 8000 brings
scenario 1 to 0.005 and the poor cells at s = 0.75 to 0.005 to 0.04, but scenario 7 stays at 0.06.
Truncating every Gaussian draw at ±2.5 and ±2 SD barely helps (scenario 7: 0.050); at ±1.5 SD,
scenario 7 is 0.065 and the poor cells 0.115 to 0.140. Shifting the treatment intercept by −0.6, which
brings prevalence to about 40% and balances the two regimes, gives 0.003 to 0.045 in the good cells at
n = 4000, and at n = 8000 with s_poor = 0.85 gives 0.020 (scenario 2), 0.047 (7), 0.053 (8), 0.007 (13)
and 0.013 (14). The nonlinear-treatment shape stays between 0.045 and 0.07 under every lever tried.

## 2. What changes

Everything not listed stays as registered.

1. **Sample size n = 8000** (registered 4000). Reason: at 4000 no separation level above 0.70 keeps the
   poor cells below the convergence the positive branch needs.
2. **Treatment intercept −0.80** (registered −0.20), so the linear predictor is
   −0.80 + 0.15t + s[...] + γ_Z Z_t. Reason: at −0.20 the never-treat regime carries 3.5 times less ESS
   than always-treat; at −0.80 their medians are 198 and 92 in scenario 1 at n = 4000, and the binding
   regime is no longer always the same one. The truth is unchanged: `truth_block` does not involve the
   treatment mechanism, and the registered truths (Monte Carlo SE 8.4 × 10⁻⁵ to 3.3 × 10⁻⁴) stand.
3. **A registered, outcome-blind calibration of the poor-separation level and the nonlinear-treatment
   term.** Good separation stays s = 0.65. The criterion throughout is: with the calibration seed and
   1000 datasets of n = 8000 per scenario drawn from the mechanism alone (no estimator is run), the
   true-weight P(min regime ESS < 10) is at most 0.02 (Monte Carlo SE 0.0044).
   - s_poor is the largest value in {0.85, 0.75} meeting the criterion in scenarios 2, 14 and 20, the
     poor cells the next step cannot affect. Measured on 150 datasets at s = 0.85 with the amended
     intercept: 0.020 (scenario 2) and 0.013 (14); scenario 20 has scenario 2's weight law. At 0.75
     without the intercept shift they were already 0.010, 0.020 and 0.005. If neither value passes, the
     positive branch is declared unreachable before any replicate is drawn and the study does not run.
   - The I_G term becomes c_G × I_G{0.45(L_t² − 1) + 0.35 W1 L_t}, with c_G the largest value in
     {1, 0.75, 0.5} meeting the criterion (scenario 7 measured 0.047 at c_G = 1 with the amended
     intercept at n = 8000, so c_G = 1 will fail and the outcome is 0.75, 0.5 or removal of the shape) in scenarios 7 and 8 at the chosen s_poor, and in scenarios
     1, 13 and 19 unchanged. The functional form is unchanged, so candidates G2 and G4 remain correctly
     specified. If no grid value passes, the nonlinear-treatment shape leaves the primary stratum:
     scenarios 7 and 8 run as descriptive cells, and the primary counts are restated in proportion with
     the stricter rounding (favorable in at least 3 of 6 rather than 4 of 8; negative in at least 5 of 6
     rather than 6 of 8; oracle failure in more than 1 of 6 rather than 2 of 8; the bespoke-balance
     comparison in at least 3 of 6 rather than 3 of 8).
   - The calibration table is frozen and published with the amendment before the run. The factor still
     changes the confounding coefficients by 31% at s_poor = 0.85 and by 15% at 0.75.
4. **Replicates.** The eight γ_Z = 0 scenarios run the registered 2000. The precision extension is kept
   but capped at one block of 500 per scenario; a scenario that still misses the 0.02 half-width is
   uninformative, which is the registered outcome when the target is not met.
5. **Stage 2.** The sixteen γ_Z ≠ 0 positive controls run as a second stage at 500 replicates, on the
   same amended mechanism and seed, only if the budget allows (section 4). The primary decision never
   depends on them, as registered.

## 3. The gates can pass

- **Combined-selector convergence, Wilson lower bound ≥ 0.93 in every γ_Z = 0 scenario (positive
  branch).** After the calibration in change 3, true-weight ESS failure is at most 0.02 in each
  primary scenario by construction, or the study stops before drawing a replicate. Allowing estimated-weight failure to be 1.5 times the true-weight rate (the
  feasibility run gave 1.3 times), convergence is at least 0.97, and at 2000 replicates its Wilson
  lower bound is 0.962, a margin of 0.032. Measured values indicating the calibration can pass outside the
  nonlinear-treatment cells: 0.020 (scenario 2, s = 0.85), 0.013 (14, s = 0.85) and 0.007 (13,
  s = 0.65) at n = 8000 with the amended intercept; 0.003 (1) and 0.005 (19) at n = 4000.
- **Convergence Wilson lower bound ≥ 0.80 (uninformative floor).** Implied by the above.
- **Paired convergence difference versus predictive CV, lower bound > −0.02.** Both selectors fail on
  the same datasets when the true regime ESS is below 10, because they share the data; the remaining
  difference comes from different G choices. With failure rates at most about 0.03 for each, the paired
  difference has standard deviation at most √0.06 and a 95% half-width of 0.011 at 2000 replicates, so
  a true difference of zero gives a lower bound near −0.011.
- **Coverage-difference precision (half-width ≤ 0.02).** At 2000 replicates and discordance ≤ 0.20 the
  half-width is 0.0196, as registered; larger discordance triggers the capped extension.
- **Negative branch (upper bounds below 0.01 for bias reduction and 0.03 for coverage gain in at least
  6 of 8).** With a true gain of zero the coverage upper bound is about 0.02, a margin of 0.01. The bias
  bound needs the standard deviation of paired absolute-error differences below
  0.01 × √2000 / 1.96 = 0.23 residual-SD units; the replicate at n = 4000 gave one-step SEs of 0.10 to
  0.20 per method, so at n = 8000 paired differences of that order are expected to fall below it.
- **Library oracle, bias ≤ 0.02 and coverage ≥ 0.90 in all but at most 2 of 8.** The oracle's Monte
  Carlo SE for bias at 2000 replicates is about 0.1/√2000 = 0.002, so a correctly specified cross-fitted
  one-step is resolvable against 0.02.
- **Truth Monte Carlo SE ≤ 0.0005.** Already met; unchanged by the amendment.
- **Stale derived files.** `results/dgm-check.csv` and `results/matrix-diagnostics.csv`, which
  `04-run.R` requires and reads, describe the registered mechanism; they are deleted and regenerated
  before the amended preflight, so the run cannot start from them.
- **Matrix preflight.** Must be rerun on the amended mechanism; it depends on the data only through
  rank and variance checks, which the intercept shift does not threaten (treatment prevalence stays
  between 0.40 and 0.47 at t = 0).

## 4. Cost

Measured with `run_estimators` on one n = 4000 replicate: 8.5 CPU-seconds (scenario 1) and 7.1
(scenario 2), including all 60 oracle configurations. Model fitting is `glm.fit` and `lm.fit` on
matrices whose rows scale with n, so n = 8000 is taken as 16 CPU-seconds; the registered 100-replicate
timing pilot must confirm it.

| Component | Replicates | CPU-hours |
|---|---:|---:|
| Primary stratum, 8 scenarios × 2000 | 16,000 | 71 |
| Capped precision extension, worst case 8 × 500 | 4,000 | 18 |
| Calibration, 24 scenarios × 1000 mechanism-only datasets × 3 grid values | | about 2 |
| Matrix preflight, timing pilot | | about 1 |
| **Stage 1 total** | | **about 74, at most 92** |
| Stage 2, 16 positive controls × 500 | 8,000 | 36 |

Stage 1 is the smallest informative version and fits in 100 CPU-hours. Stages 1 and 2 together need
about 110 to 128 and do not fit; the owner decides whether stage 2 runs.

## 5. What the amended study no longer answers

- **Poor separation is milder.** s = 0.85 or 0.75 instead of 1.25, and treatment prevalence falls from 53% to
  61% to about 40% to 47%. The study no longer says anything about selection when the never-treat
  regime is as starved as the registered mechanism made it; at that level no selector can converge
  often enough for the comparison to be made.
- **Results pertain to n = 8000**, not 4000.
- **The nonlinear-treatment shape is attenuated** (c_G of 0.75 or 0.5) or, if the calibration fails,
  leaves the primary stratum; the registered coefficient is not retained in either case, and the
  outcome is fixed before any replicate is drawn.
- **Without stage 2 there is no treatment-only-predictor classification.** That label was always
  separate from the primary question and is a known mechanism.
- **Precision extension beyond 2500 replicates** is not available; a scenario with discordance high
  enough to need it is uninformative rather than extended to 5000.

The checks behind section 1 used about 25 CPU-minutes, more than the 15 allowed, partly because two
copies of the first check ran at once by mistake. They are the scratch scripts `ess_check.R`, `ess2.R`
to `ess5.R` and `timing.R` in the design agent's scratch directory; none wrote to `results/`.
