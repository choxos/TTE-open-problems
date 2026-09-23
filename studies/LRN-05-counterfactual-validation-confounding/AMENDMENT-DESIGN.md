# LRN-05 proposed registered amendment

Proposed amendment to the registered protocol in
`documentation/studies/designs/LRN-05-a-counterfactual-prediction-is-validated-und-revised.json`.
It would be committed before any replicate of the amended run is drawn, under a new master seed
(20260923). The deterministic truths (`results/truth.rds`) do not depend on n and stand.

## The five completed scenarios cannot be kept

Scenarios 1 to 5 (P0 to P4 under adequate support) were run to 2000 replicates under the registered
seed 20260801 before the pause. The amended run starts fresh and does not pool them, for four reasons,
any one of which is sufficient:

1. **They were drawn at n = 1000.** The registered n is 4000, and this amendment restores it
   (section 2). Replicates of a different sample size estimate different operating characteristics.
2. **They have been analyzed, and this amendment was written knowing the results.** `performance.csv`
   and `decisions.csv` hold scenario 1's summaries, and LIMITATIONS.md quotes its bias and gate values.
   Pooling them would let results that shaped the amendment enter the decisions it governs.
3. **A new master seed is required.** An amendment is committed before any of its replicates is drawn;
   replicates from the registered seed's streams are, by definition, not draws of the amended run.
4. **Their pilot cannot plan the amended run.** The precision pilot that set their replication counts
   was at n = 1000; the registered procedure sets R from a pilot of the design actually run.

They are kept, unmodified, as a record of the pre-amendment run, but not where the amended run can see
them. `run_design(..., resume = TRUE)` skips any scenario whose `results/raw/scenario-NN.rds` exists
(`drive.log` shows "scenario 1/24: cached"), so leaving them in place would make the amended run reuse
five n = 1000 scenarios under the old seed without any error. Before the amended run, `results/raw/`,
`results/pilot/`, `results/replication-plan-cache/` and the summary CSVs move to
`results-pre-amendment/`; only `results/truth.rds` and `results/truth-cache/` stay. CLAUDE.md records
that a cache keyed on the scenario index outlived the pilot it summarized in this very study.

## 1. Why the registered design, as run, cannot answer

**At the implemented n = 1000 the positive-control gate fails where it should pass.** In the joint null
(scenario 1, γ = δ = 0), the full-history oracle's g0 calibration intercept has bias 0.0326 (Monte Carlo
SE 0.0113 over 2000 replicates), so the gate quantity |bias| + 1.96 × MCSE is 0.055 against a limit of
0.05, and every g0 intercept classification in scenario 1 is `positive-control-failed`. The bias is the
finite-sample bias of a weighted logistic calibration fit whose weights have an ESS of about 170 to 210
people; it is a property of n, not of confounding.

**At n = 1000 the negligible branch is barely reachable even in the null.** It requires the Monte Carlo
interval for exact complete-history coverage to lie within [0.93, 0.97]. In scenario 1 that coverage
was 0.9215 for the g0 intercept and 0.9405 for the g1 intercept (the primary quantity), with lower
bounds 0.910 and 0.930; the primary cell ended in `indifference-region` although its paired omission
effect is identically zero.

**At n = 1000 stressed support leaves almost no always-treat information.** In P7 under stressed support
(scenario 20), one dataset at n = 1000 had 113 always-treat adherers with a weight ESS of 2.2; at
n = 4000, 457 adherers and ESS 89.5. The pilot's replication requirements for the primary quantity
(g1 oracle-score intercept) at n = 1000 exceed the registered cap of 10,000 in nine of the twelve
stressed scenarios (15, 19, 20, 22, 23 and 24 need 53,000 to 132,000; 14, 18 and 21 need 12,000 to
17,000), so the primary classification would be Monte Carlo inconclusive there by the registered rule,
and the implementation's own budget cap of 2000 made it inconclusive in thirteen scenarios.

**Cost is not the obstacle once the fitted comparator is separated.** Measured CPU per replicate at
n = 4000: data generation and exact probabilities 0.6 to 0.8 s and the three known-weight methods 0.5 s,
against 12.2 to 13.0 s for `fitted_reduced`, which is 90% of the replicate. That method enters no
classification (`classify_scalar` reads `full_history` and `exact_complete`; the protocol says its
failure does not determine the omission classification), fails in about 39% of adequate-support
replicates, and fails in every stressed-support replicate because of the stacking defect LIMITATIONS.md
describes (`estimate_fitted_method` stacks non-finite influence columns that `estimate_known_method`
drops).

**The implemented oracle gate cannot be passed at large R.** `05-analyze.R` requires the full-history
coverage Wilson interval to contain 0.95 exactly. With up to 10,000 replicates, a true coverage of 0.945
or 0.955 excludes 0.95, so the gate's pass probability falls toward zero as precision rises unless
coverage is exactly nominal. The registered text does not define this part of the gate.

## 2. What changes

Everything not listed stays as registered.

1. **n = 4000**, as registered; the implementation's reduction to 1000 is withdrawn.
2. **The registered precision plan is followed.** A 500-replicate pilot per scenario at n = 4000 under
   the new seed, excluded from summaries; R_s = max(2000, all applicable requirements rounded up to
   1000), capped at 10,000, frozen before the final run. The implementation's budget cap of 2000 and its
   `budget-precision-shortfall` reason are removed.
3. **`fitted_reduced` runs only in the four anchor scenarios** (P0 and P7 under both supports), at 1000
   replicates, with the stacking defect fixed by the finite-column subset `estimate_known_method` already
   uses. Its registered role (estimation plus sieve error against the exact reduced-history method) is
   kept there. Reason: it costs 90% of every replicate and enters no classification.
4. **Bootstrap SE validation** runs as registered (199 resamples, 25 datasets, 4 anchors) for the
   known-weight methods; for `fitted_reduced` it uses 5 datasets per anchor. Reason: cost; the fitted
   method's sandwich enters no classification.
5. **The oracle gate is written into the protocol** as: at least 95% successful replicates;
   |bias| + z × MCSE below the negligible limit, with the registered critical value for the family; and a
   full-history coverage Wilson interval that intersects [0.93, 0.97], the band the protocol already
   uses for the negligible coverage condition. This replaces the implementation's "interval contains
   0.95". The owner should confirm this reading, because it is a definition the registered text left
   open rather than a registered threshold.
6. **Stressed support at α = −1.25** (registered −2.0), recommended and left to the owner. At −2.0 the
   always-treat regime in strongly selected profiles is too thin for the full-history oracle itself:
   in P7 at n = 4000 its g1 intercept bias was −0.171 (MCSE 0.068) and the paired effect needed about
   28,000 replicates, so those cells cannot separate practical positivity from exchangeability failure,
   which is the factor's registered purpose. At −1.25, 100 replicates of P7 at n = 4000 gave 942
   always-treat adherers (ESS 256), oracle g1 intercept bias 0.012 (MCSE 0.039) and a paired-effect
   standard deviation of 0.295, a requirement of about 3,300 replicates; at −1.5 the corresponding
   values were 754 adherers, ESS 136, bias 0.080 (MCSE 0.046) and about 6,100. With α = −1.25 the
   baseline and continuation probabilities at X1 = X2 = L = U = 0 are 0.223 and 0.905, against 0.378
   and 0.953 for adequate support, so the factor still changes practical support. The choice uses only
   the oracle's bias and the paired-effect spread, not the mean omission effect or any coverage.

## 3. The gates can pass

Measured with the study's own `gen_replicate`, probability functions and `estimate_known_method` at
n = 4000, under seeds disjoint from every registered stream. The checks computed oracle bias, the
standard deviation of the paired effect and the coverage of the exact complete-history intercept
interval, which is itself part of the registered primary performance measure; this is disclosed here
because the negligible and consequential branches both use it as a gate. The mean paired omission
effect, the primary estimate, was not examined. No change in section 2 depends on the coverage values:
n and the precision plan restore the registered design, and the oracle-gate definition follows from
the arithmetic of a fixed band against a shrinking interval.

- **Truth and its verification.** Unchanged; the quadrature truths, cut points and the independent
  Monte Carlo check do not involve n.
- **Positive-control gate, bias part** (|bias| + 1.96 × MCSE below 0.05 for the intercept). Joint null,
  scenario 1, 600 replicates: full-history oracle intercept bias 0.0086 for g0 (MCSE 0.0106, SD 0.26)
  and −0.0097 for g1 (MCSE 0.0135, SD 0.33). At R = 2000 the gate quantity would be 0.020 (g0) and
  0.024 (g1), margins of 0.030 and 0.026; at n = 1000 it was 0.055 for g0. In P7 under adequate support
  (scenario 8, 150 replicates) the g1 bias was 0.0004 (MCSE 0.018), gate quantity about 0.010 at
  R = 2000. The g0 bias there was 0.076 (MCSE 0.040), so g0 cells in strong-selection profiles may still
  fail the gate; the primary quantity is g1.
- **Success fraction ≥ 0.95.** The full-history and exact complete-history methods returned finite g1
  intercepts in 750 of 750 replicates (scenarios 1 and 8).
- **Negligible branch coverage band** (exact complete-history coverage interval within [0.93, 0.97]).
  Scenario 1, 600 replicates: g1 coverage 0.945 (Wilson 0.924 to 0.961), g0 0.935 (0.912 to 0.952).
  If g1's true coverage is 0.945, its interval at R = 2000 is about [0.935, 0.954], inside the band;
  g0 at 0.935 would give about [0.924, 0.945] and miss it. The primary branch is reachable; the g0
  negligible label may not be.
- **Oracle gate, coverage part.** Under the amended definition (interval intersects [0.93, 0.97]) a true
  coverage of 0.945 passes at every R. Under the implemented "interval contains 0.95" it passes at
  R = 2000 and fails from about R = 5000.
- **Consequential branch** (lower bound of |effect| above 0.10 and exact coverage upper bound at most
  0.90). Reachable whenever the true effect exceeds about 0.11: the paired g1 effect in scenario 8 has
  standard deviation 0.109 at n = 4000, so R = 2000 gives a half-width of 0.005. Whether any profile
  produces such an effect is the study's finding.
- **Precision plan within the cap.** The paired g1 intercept effect in scenario 8 needs
  (1.96 × 0.109/0.01)² = 457 replicates, so the registered minimum of 2000 applies. The g0 oracle
  intercept effect there has standard deviation 0.43 and needs about 7,100, against 10,000 at n = 1000:
  quadrupling n did not quarter every requirement, so the planning total in section 4 (which divides the
  n = 1000 requirements by 4) is optimistic for the never-treat metrics under strong selection.
- **Stressed support: the primary gate still fails under strong selection.** One P7 stressed dataset
  at n = 4000 had 457 always-treat adherers and a g1 weight ESS of 89.5 (2.2 at n = 1000). Over 200
  replicates of P7 stressed (scenario 20) at n = 4000, the full-history oracle's g1 intercept bias was
  −0.171 (MCSE 0.068), so the positive-control gate fails for the primary quantity, and the paired g1
  effect had standard deviation 0.86, a requirement of about 28,000 replicates, above the cap. Restoring
  n = 4000 does not make the strongly selected stressed cells answerable: at α = −2.0 the always-treat
  regime is too thin for even the oracle to calibrate. Under the registered α those cells stay
  uninformative; change 6 is what makes them answerable. At α = −1.25 the oracle's g1 intercept had
  standard deviation 0.39 over 100 replicates, so at R = 2000 the gate quantity would be about
  0.012 + 1.96 × 0.39/√2000 = 0.029, a margin of 0.021; the paired-effect requirement of about 3,300
  is within the cap.

## 4. Cost

Measured CPU per replicate at n = 4000 (scenarios 8 and 20, one dataset each): 1.1 to 1.3 s for data
generation, the three exact probability sets and the three known-weight methods; 13.4 to 14.3 s with
`fitted_reduced`. The 600 scenario-1 and 200 scenario-20 gate replicates took 222 and 98 CPU-s for the
two known-weight methods, 0.4 to 0.5 s each, consistent with this. Taking 1.3 s:

| Component | Replicates | CPU-hours |
|---|---:|---:|
| Pilot, 24 scenarios × 500 | 12,000 | 4.3 |
| Final run, planning total (requirements at n = 1000 divided by 4, rounded up to 1000, 2000 to 10,000 per scenario) | 128,000 | 46.2 |
| `fitted_reduced`, 4 anchors × 1000 × 13.5 s | 4,000 | 15.0 |
| Bootstrap, known weights: 4 × 25 × 199 × 1.2 s | 19,900 | 6.6 |
| Bootstrap, fitted: 4 × 5 × 199 × 13.5 s | 3,980 | 14.9 |
| **Total** | | **about 87** |

The planning total uses the registered α; with change 6 the stressed requirements fall (P7 from above
the cap to about 3,300), so it is if anything high for the stressed half, and low for never-treat
metrics under strong selection (section 3). If every scenario required the cap of 10,000, the final
run would be 86.7 CPU-hours and the total about 128; the pilot decides, and the fitted-method
bootstrap is the first item to drop if the frozen plan exceeds 100.

## 5. What the amended study no longer answers

- **`fitted_reduced` outside the anchors.** Estimation and sieve error of the fitted reduced-history
  comparator are measured in four scenarios, not twenty-four. No classification depended on it.
- **Stressed scenarios above the cap.** Any scenario whose frozen requirement exceeds 10,000 remains
  Monte Carlo inconclusive for that metric, as registered.
- **The registered stressed level.** With change 6 the study says nothing about α = −2.0, where about
  11% of people in P7 adhere to always-treat and the oracle weights have an ESS near 90 at n = 4000;
  without change 6 it says nothing useful about the primary quantity there either, because the oracle
  fails its own gate.
- Relative to the registered protocol nothing else is dropped; relative to the pre-amendment run, the
  amended run is larger per replicate and follows the registered replication rule.

The checks behind sections 1 and 3 (scratch scripts `timing.R`, `gate_n4000.R` and `stress_alpha.R`)
used about 13 CPU-minutes, read `results/truth.rds` only, and wrote nothing under `results/`.
