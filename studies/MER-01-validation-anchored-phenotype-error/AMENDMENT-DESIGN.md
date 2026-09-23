# MER-01 proposed registered amendment

Proposed for registration before any replicate of the amended run is drawn, with a new master seed. It amends `documentation/studies/designs/MER-01-phenotypes-enter-emulations-as-error-free-bi-revised.json`. Everything not listed under "What changes" stays as registered, including every decision threshold.

## 1. Why the registered design cannot answer

**The support gate cannot pass.** BLOCKED.md measured the oracle clone-censor estimator on 20 cohorts of 4000 per latent law: 0.7 to 1.4% of people follow either strategy for all 12 months and the median oracle effective sample size is 6.4 to 17.2, against the registered requirement of more than 200 in both arms of every key error cell. The implemented laws match the registered design term by term. This is correct.

**An amended natural-treatment law would not need new truth.** `truth_for_law` never calls `latent_predictor_A`, and the registered design states that "natural-treatment and measurement-error changes do not alter intervention truth". Only a change to the confounder law, the outcome law or the horizon requires new truth.

**No natural-treatment law in the registered model class can rescue a 12-month horizon.** The first-order and exact-filtered comparators are only valid if the natural law stays inside the class they model (treatment on its own lag, current L, X1, X2 and month). In that class the two strategies conflict at every month with A(t-1) = 0 and L(t) = 1: g1 needs treatment there and g0 needs none, so one arm pays a factor of at least 2 in weight at every such month, and L is 1 in about half of all months. A scratch computation of the expected effective sample size, n divided by E_g[1/pi] under counterfactual L paths of the registered confounder law, shows this directly (values for n = 4000; this is a conservative guide, since the median in finite samples runs higher):

| natural-treatment law | 12 months, g1 / g0 | 8 months | 6 months | 4 months |
|---|---|---|---|---|
| registered (2.00 on A(t-1), 0.90 on L(t)) | 3 / 2 | 36 / 47 | 121 / 164 | 403 / 501 |
| no persistence, P(A=1 given L=1) = 0.5 | 37 / 0 | 176 / 11 | 385 / 70 | 845 / 349 |
| moderate persistence (1.00 on A(t-1)) | 86 / 1 | 299 / 25 | 561 / 120 | 1058 / 468 |
| registered law, treatment stress | 2 / 0 | 31 / 8 | 108 / 58 | 376 / 309 |

No law reaches 200 in both arms at 12 or 8 months. Keeping 12 months would need about 125,000 people per replicate (BLOCKED.md), which multiple imputation cannot afford.

**The ESS gate is not the only blocker; cost is the other.** R/00-config.R already records that the frozen protocol needs at least 81 by 1000 by 50 = 4,050,000 completed-data analyses. Measured in scratch at a 4-month horizon on one decisive cell: the rich-history estimator 2.4 CPU-seconds, the exact filter 2.7, the first-order estimator 0.25, the oracle 0.03, and the corrected method 5.0 at M = 2, about 2.5 per imputation. At the registered minimum M = 50 the correction alone costs about 125 CPU-seconds per cell and replicate, so the registered grid at 1000 replicates is about 3100 CPU-hours before extensions, calibration (30 data sets by 1600 imputations, about 33 CPU-hours) or the four-times-M check, and larger again at 12 months.

## 2. What changes

1. **Strategy horizon: 12 months to 4 months.** Follow-up is t = 0 to 3; Y is generated after month-3 treatment from the registered outcome law with L3 and A3 in place of L11 and A11. Every treatment, confounder, outcome and error law is otherwise unchanged term by term, including the time terms 0.03t and 0.02t and the serially persistent error processes. Reason: the table above; 4 months is the longest horizon at which the registered laws give the oracle more than 200 in both arms of every latent law. Consequence: truth must be recomputed for the four causal laws with the registered `truth_for_law` at 4,000,000 people and the registered Monte Carlo SE gate below 0.0005. A scratch run at 400,000 gives a core dynamic risk difference of about -0.075 (static -0.117), comparable in size to the registered 12-month -0.086.

2. **Scope: the primary question only.** The run contains the eight decisive cells (joint A and L error at accuracies 0.70 and 0.85 under the nondifferential, reversed, unrelated and no-effect-modification profiles, validation n = 500, core specification), each analyzing the paired none, A-only, L-only and joint patterns on one latent cohort as registered, and the two core no-error controls. The five near-null cells (accuracy 0.99) and the three outcome-error component cells are kept as descriptive cells. The correction arm (validation-anchored multiple imputation), its M calibration, the four-times-M check, the prior sensitivity, the 38 robustness scenarios, the three stress no-error controls, the aligned profile and the standalone A-only and L-only scenarios are removed. Reason: cost; multiple imputation is more than 85% of the registered compute and none of it enters the primary classification.

3. **Rich-history thresholded estimator in decisive cells: joint pattern only.** It stays in every pattern of the no-error controls. The first-order, exact-filtered and oracle estimators run in all four patterns as registered. Reason: the decision rule uses the rich-history estimator only in the joint-error decisive cells and the core no-error controls; its A-only and L-only fits are descriptive and cost 4.8 CPU-seconds per cell and replicate.

4. **Replication schedule.** Decisive families start at 1000 replicates and unresolved families extend to 2000 together with their paired controls. The 4000 look is removed. Each look keeps the registered familywise alpha allocation of 0.01 divided by 3; a family still crossing a threshold at 2000 is uninformative. Using the registered per-look alpha with one fewer look spends less than the registered familywise 0.01, so no bound is loosened. Descriptive near-null and outcome-component cells run 500 replicates.

5. **Truth laws needed.** Core and no-effect-modification (decision-bearing); confounder-stress and outcome-stress truths are no longer needed.

## 3. The gates can pass

Measured with the study's own `gen_replicate` and `est_oracle` at 4 months, all laws unchanged, 5 cohorts of 4000 per row (scratch; nothing written to `results/`):

| latent law or cell | median oracle ESS g1 | median oracle ESS g0 | minimum over the 5 | adherence g1 / g0 |
|---|---:|---:|---:|---|
| core | 399 | 528 | 386 | 0.18 / 0.19 |
| treatment stress | 317 | 329 | 234 | 0.19 / 0.18 |
| confounder stress | 480 | 484 | 456 | 0.20 / 0.19 |
| decisive, nondifferential 0.70 | 406 | 485 | 363 | 0.17 / 0.19 |
| decisive, nondifferential 0.85 | 407 | 504 | 353 | 0.17 / 0.19 |

The same check at 6 months gave medians of 94 and 83 under treatment stress and 139 and 173 under the core law, so 6 months fails; 4 months passes with a margin of 2.0 in the decisive cells and 1.6 in the worst stress law (which leaves the amended run but was checked because it bounds how fragile the margin is).

- **Oracle bias and coverage in key cells (bias within plus or minus 0.01, coverage interval within 0.925 to 0.975, convergence at least 0.95).** The oracle uses the exact natural-treatment probabilities, so its bias is zero in expectation. Its standard error at 4 months is 0.022 to 0.031 in the core law and the decisive cells (scratch). At 2000 replicates the Monte Carlo SE of bias is about 0.0006, and with a multiplier near 3.5 for alpha 0.0033 the interval is plus or minus 0.002, well inside 0.01. The exact binomial coverage interval at true 0.95 is about 0.933 to 0.966 at 2000 replicates, inside the band; at 1000 it is about 0.926 to 0.974, marginal, which is what the registered extension to 2000 is for. All 25 scratch oracle fits and all exact-filter and first-order fits converged.
- **No-error controls (exact-filtered and oracle bias within plus or minus 0.005; first-order and rich-history must also pass).** With true A and L the exact filter reduces to the known-law probabilities, and the registered first-order model contains the registered treatment predictors (plus X3), so all four are correctly specified; the interval half-width at 2000 replicates is about 0.002.
- **Decisive branches.** Supporting the problem needs point absolute bias at least 0.02 with the bias interval outside plus or minus 0.01 and coverage at most 0.90 with upper limit below 0.925; the not-real branch needs bias intervals inside plus or minus 0.01 and coverage intervals inside 0.925 to 0.975. With estimator SEs near 0.027 the bias interval half-width is about 0.003 at 1000 replicates and 0.002 at 2000, so the real branch is reachable for true absolute bias above about 0.013 and the not-real branch for true absolute bias below about 0.008. In the scratch datasets the exact-filtered estimate in the accuracy-0.70 decisive cell had a median of -0.023 against the approximate truth of -0.075, so material bias is not excluded by construction; five datasets are not evidence for either branch.
- **Interaction.** The exact-filtered B_AL minus B_A minus B_L plus B_0 uses the four patterns fitted on one cohort, as registered; paired differences remove the common cohort noise, so its interval is narrower than the bias intervals and both the "outside plus or minus 0.005" and "inside" branches are reachable.
- **Valid replicates at least 95% per key cell.** Every scratch fit returned an estimate. Proxy-adherent clones remain plentiful at 4 months (median exact-filter ESS 276 to 326 in g1 and 583 to 602 in g0 in the two nondifferential decisive cells), whereas at 12 months the thresholded arms would have had a few consistent clones each.

## 4. Cost

Per replicate, from the scratch timings at 4 months: each decisive cell costs 4 first-order fits (1.0 s), 4 exact filters (10.7 s), 1 rich-history fit (2.4 s) and the oracle, about 14.2 CPU-seconds; each no-error control about 5.4. Decisive families: 8 by 14.2 plus 2 by 5.4 is 124 CPU-seconds per replicate, 34.5 CPU-hours at 1000 replicates and 69 CPU-hours if every family extends to 2000. Descriptive cells: 8 by 14.2 by 500 replicates is 15.8 CPU-hours. Truth: two laws at 4,000,000 people over 4 months, under 0.5 CPU-hours. Total 51 CPU-hours if every family resolves at 1000 and 85 CPU-hours in the worst case. The timings were taken at load averages above 300 and are inflated rather than optimistic.

## 5. What the amended study no longer answers

- The second aim in full: what internal validation sample makes latent-state correction worth its variance, whether it survives treatment, confounder, outcome or error-transition misspecification, its prior sensitivity, and its imputation-count stability. At 2.5 CPU-seconds per imputation the smallest version of that aim (2 benchmarks by 5 specifications by 4 sizes by 1000 replicates by M = 50) needs about 1400 CPU-hours and is not feasible on this machine; it needs its own registration and allocation.
- The 12-month strategy. Over 4 months there are fewer months in which confounder error can change the required treatment and the censoring time, so phenotype effects may be smaller than over 12; a not-real result at 4 months does not imply one at 12.
- The aligned profile, the standalone A-only and L-only scenarios, rich-history fits in the A-only and L-only patterns, and the stress-law no-error controls.
- Decisions at the 4000-replicate look; families unresolved at 2000 are reported as uninformative.
