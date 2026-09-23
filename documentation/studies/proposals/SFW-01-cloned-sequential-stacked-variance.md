# SFW-01: a person-clustered stacked variance for cloned sequential emulations, and when the fixed-weight sandwich understates it

**Catalog problem.** Variance estimation after cloning and sequence expansion has no scalable, correct default. Verdict `partially-addressed`; triage: analytic, answerable in part, feasibility 2.

**Residual claim this design tests.** The audit removed two parts of the entry. Rows created by repeated eligibility and by cloning all belong to one original person, so clustering on that person handles the dependence among them; clone dependence is not a separate sampling level (codex). The sequence-expansion half has been studied: sandwich, bootstrap, jackknife and a linearized estimating-function bootstrap were compared for sequential trial emulation with survival outcomes, with setting-specific recommendations (Limozin 2025). The pinned `TrialEmulation` source computes a person-clustered sandwich for the fitted outcome model (`sandwich::vcovCL` clustered on the original identifier, quoted in the audit), which treats the estimated weights as fixed. What remains, for parametric nuisance models, is narrower than the entry: (a) whether a person-clustered stacked sandwich that includes the weight-model scores is correct for the cloned sequential estimator and computable in one pass over the expanded rows, and (b) whether the fixed-weight person-clustered sandwich is safe to use in its place. The usual argument that ignoring estimation of a correctly specified, maximum-likelihood weight model is conservative assumes each treatment decision contributes once to the weight-model score. In expanded data a decision contributes once for every trial and clone in which it appears, so the weight model is fitted with person-specific multiplicities, and that argument no longer applies.

A preliminary calculation shows the sign can flip. Take a point-treatment Horvitz-Thompson estimator of E[Y^1] with X ∈ {0, 1, 2} (probabilities 0.4, 0.4, 0.2), a correctly specified propensity logit e(X) = −0.5 + X, and binary Y^1 with means 0.2, 0.5, 0.9. Fit the propensity model by solving Σ m(X_i) S_i(β) = 0, where S is the logistic score and m(X) a multiplicity. The influence function is φ_0 − c M⁻¹ m(X) S with φ_0 the known-weight influence function, c = E[φ_0 S] and M = E[m(X) S Sᵀ], so the variance change relative to known weights is −2 c M⁻¹ E[m S φ_0] + c M⁻¹ E[m² S Sᵀ] M⁻¹ cᵀ, which is exact to first order. With m ≡ 1 (maximum likelihood) it is −23% of the known-weight variance of 0.542, so the fixed-weight sandwich is conservative. With m = (1, 32, 32) it is +2.2%, so the fixed-weight sandwich is anticonservative. The magnitude in realistic sequential designs is unknown.

The pinned `TrialEmulation` 0.0.4.11 source (`documentation/refs/packages/cran/TrialEmulation`) fits its switching and censoring weight models on the unexpanded person-period data: `calculate_weights()` runs before `expand_trials()` in the package vignette (`new-interface.Rmd`, lines 167 and 251), and `data_extension.R` carries the resulting `wt` into the expansion as a cumulative product by person. That is convention U below, under which Claim 2 predicts the package's fixed-weight sandwich is conservative when the weight model is correctly specified. Convention E arises whenever a weight model is fitted on cloned or expanded rows; how often applied analyses do so is not established here.

## Question

For one fully specified cloned sequential estimator with parametric weight and outcome models:

1. What is its person-level influence function when the artificial-censoring weights are estimated, and is the person-clustered stacked sandwich built from it consistent whatever the number of trials and clones per person?
2. Under which weight-fitting conventions is the fixed-weight person-clustered sandwich conservative, and how large can its anticonservative error be when the weight model is fitted on expanded rows?
3. Can the stacked sandwich be computed in one pass over person-sorted expanded rows with memory that does not grow with the number of rows?

## What this leaves unanswered

Weights or outcome models fitted by machine learning, for which the stacked estimating equations do not exist in closed form; cross-fitted orthogonal estimators are the route there and are not studied. Sites as the independent sampling unit. Small-sample coverage with rare events, where Limozin 2025 found setting-specific behavior; the analytic results here are first-order. Other estimands (hazard ratios, restricted mean survival) and grace-period designs with more than two strategies are not derived, although the algebra should extend.

## Estimator

Monthly time over 36 months. A trial starts at each month k = 0, ..., 11 among people eligible then (not yet treated, event-free). Strategies: s1, initiate within a grace period of G months; s0, do not initiate. With G = 0 each person-trial is assigned to the strategy it follows at trial start and no cloning occurs; with G = 2 every eligible person-trial is cloned into both arms. A clone is artificially censored at its first deviation. The adherence model is pooled logistic regression of initiation on month since trial start, trial month and the time-varying covariate L, fitted either on unexpanded person-months (each decision once; convention U) or on the expanded clone-trial rows (each decision once per trial and clone in which it appears; convention E). Weights are inverse cumulative probabilities of remaining uncensored. The outcome model is weighted pooled logistic regression of the event on arm, follow-up month (natural spline, 4 degrees of freedom) and their interaction. The target is the risk difference at 24 months, standardized over trial-baseline covariates pooled across trials.

## Claims to be proved or refuted

**Claim 1 (stacked influence function).** Write the adherence-model score, the weighted outcome-model score and the standardization equation as one estimating function U_i(θ) summed over all rows belonging to original person i. Under independence across persons, bounded weights and finitely many trials and clones per person, √n(θ̂ − θ) is asymptotically normal with variance A⁻¹BA⁻ᵀ, A = E[∂U_i/∂θ], B = E[U_i U_iᵀ], and the person-clustered stacked sandwich is consistent under both conventions U and E. The derivation must give the cross-derivative block ∂(outcome score)/∂(adherence parameters) explicitly, since that block carries the weight-estimation correction.

**Claim 2 (sign of the fixed-weight error).** Let V_fix be the person-clustered sandwich of the outcome block alone. Under convention U with a correctly specified adherence model, V_fix is asymptotically no smaller than the true variance (projection argument: the stacked influence function is the fixed-weight one minus its projection on the adherence score). Under convention E this ordering fails in general; give a counterexample in the sequential design (the preliminary point-treatment calculation is the template) and a bound on (V_true − V_fix)/V_true in terms of the dispersion of person-specific multiplicities and their correlation with the covariates that enter the adherence model.

**Claim 3 (single pass).** With rows sorted by person, the stacked sandwich needs per-person sums of the stacked score (dimension p) and running sums for A (p by p), so one pass over the rows costs O(R p²) time and O(p²) memory, where R is the number of expanded rows, plus a second pass for the scores at θ̂. No bootstrap is needed.

## How the result is checked

Simulation with the estimator above; n = 2000 people per replicate. L is a binary time-varying confounder with logit P(L_t = 1) = −1 + 1.5 L_{t−1} − 0.5 A_{t−1}; initiation depends on L_t (log odds ratio 1.0); the monthly event hazard is logit⁻¹(−5 + 0.8 L_t − 0.4 A_t). The factors: convention U or E; grace period G = 0 or 2; trial-eligibility multiplicity independent of L or increasing with L (eligibility probability 0.5 + 0.4 L_k at each trial month). Eight settings.

- **Truth.** Risk difference at 24 months from 2 × 10^6 people simulated under each strategy with common random numbers; Monte Carlo standard error below 0.0005.
- **Replicates.** 1000 per setting. The empirical standard deviation of the estimate then has relative Monte Carlo error about 1/√(2 × 999) = 2.2%, so a relative SE error of 5% is resolvable; coverage of a nominal 95% interval has Monte Carlo standard error 0.007.
- **Variance estimators compared.** Row-level naive; fixed-weight person-clustered (the `TrialEmulation` construction); stacked person-clustered (Claim 1); person-level nonparametric bootstrap refitting both models (B = 100, in the first 50 replicates of each setting).
- **Measures.** Relative error of each mean SE against the empirical SD, with Monte Carlo interval; coverage with Wilson interval; CPU time and peak memory of the one-pass algorithm against the number of expanded rows at n = 2000, 8000 and 32000.

## What would show the problem real, not real, or leave it open

- **Real for this estimator class.** The fixed-weight person-clustered sandwich (the construction `TrialEmulation` computes, here applied under both fitting conventions) is anticonservative by a material amount in a realistic setting: in at least one convention-E setting its relative SE error has an upper Monte Carlo bound below −0.05, or its coverage has a Wilson upper bound below 0.93, and Claim 2's bound shows the error is not a small-sample artifact. Any analysis that fits its weight models on expanded or cloned rows and reports the fixed-weight sandwich would then understate uncertainty.
- **Not real for this estimator class.** Claim 1 proved; the stacked sandwich's relative SE error lies within ±0.05 and its coverage interval within [0.93, 0.97] in all eight settings, and matches the bootstrap within Monte Carlo error; the one-pass algorithm's memory is flat in the number of rows; and the fixed-weight sandwich is conservative or within 2.5% everywhere. A scalable correct default would then exist for parametric cloned sequential designs, and the residual problem would be confined to flexible nuisance learning and site-level sampling.
- **Uninformative.** The stacked sandwich disagrees with the bootstrap and the Monte Carlo SD in a setting where Claim 1 should hold and the discrepancy is not resolved, or the Monte Carlo interval for a relative SE error is wider than ±0.05.

Both substantive branches are reachable: the preliminary calculation gives an anticonservative error of 2.2% in variance, about 1.1% in SE, which would fall in the not-real branch if typical, while stronger multiplicity patterns in sequential designs could push it past the 5% bound. For the `TrialEmulation` pipeline itself, which uses convention U, the expected outcome with correctly specified parametric weight models is the not-real branch; the real branch, if reached, concerns weight models fitted on expanded rows.

## Cost

Person-hours: derivation of Claims 1 to 3, 30 to 50 hours; simulation code, reusing the stacked-sandwich pattern already written for GMT-03 and GMT-04 in this repository, 20 hours; write-up, 10 hours. Compute, from an assumed 1 CPU-second per fit at n = 2000 with about 50,000 expanded rows (to be replaced by a timing pilot of 20 replicates): 8 settings × 1000 replicates × 2 seconds (fit plus stacked sandwich) is 4.4 CPU-hours; the bootstrap is 8 × 50 × 100 fits, 11 CPU-hours; truth and the scaling runs, 2 CPU-hours. About 18 CPU-hours in all.

## Threats to validity

- **One estimator.** Results bind only the specified clone-censor-weight sequential estimator with pooled logistic nuisance models; the claims are stated so the algebra, not the simulation, carries the generality.
- **The multiplicity pattern drives Claim 2.** The simulation varies it in one direction only (eligibility increasing with L); the bound in Claim 2 is what generalizes, and the write-up must state the pattern that maximizes it.
- **Grace-period cloning makes early censoring deterministic for some clones.** The weights for those clones are 0 or a probability of not initiating by the end of the grace period; the derivation must handle the deterministic part without dividing by zero.
- **Standardization across trials.** Pooling trial-specific baseline distributions defines a particular target population; the variance claims hold for that target and are not a recommendation of it.

## Citations

- Limozin JM, Seaman SR, Su L. Inference procedures in sequential trial emulation with survival outcomes: comparing confidence intervals based on the sandwich variance estimator, bootstrap and jackknife. Statistical Methods in Medical Research. 2025;34(10):2011-2033. doi:10.1177/09622802251356594
- Stefanski LA, Boos DD. The calculus of M-estimation. The American Statistician. 2002;56(1):29-38. doi:10.1198/000313002753631330
- Lunceford JK, Davidian M. Stratification and weighting via the propensity score in estimation of causal treatment effects: a comparative study. Statistics in Medicine. 2004;23(19):2937-2960. doi:10.1002/sim.1903 (large-sample variance of inverse-weighting estimators that accounts for estimation of the propensity score).
- Morris TP, White IR, Crowther MJ. Using simulation studies to evaluate statistical methods. Statistics in Medicine. 2019;38(11):2074-2102. doi:10.1002/sim.8086
