# SFW-02: does distributional fidelity screen out synthetic-data generators that distort a sustained-strategy effect?

**Catalog problem.** Generative models are evaluated on distributional fidelity and used for causal work. Verdict `partially-addressed`; triage: simulation, answerable in part, feasibility 3, not a target trial emulation problem.

**Bearing on target trial emulation.** Synthetic copies of routine data are used to develop emulation code and to benchmark estimators; the estimand tested here is a sustained-strategy g-formula risk difference with treatment-confounder feedback, so the answer is directly the one an emulation developer needs.

**Residual claim this design tests.** Causally annotated synthetic data with ground-truth effects exist (Shi 2022), and grok recorded a 2025 preprint that defines causal-use metrics and a generator factorized along the treatment mechanism; it has no CrossRef record and is not cited. Codex corrected the entry: observationally equivalent models disagree on some interventions, not every one; a generator that reproduces the full joint law preserves overlap and every identified effect; temporal ordering and conditional support are observable and testable. So, for a generator trained on observational data, "causal fidelity" under the emulation's own assumptions is fidelity to one identified functional of the joint law, and the real question is whether the fidelity metrics used in practice detect distortion of that functional. The triage leaves counterfactual fidelity without identifying assumptions out of reach, and so does this design.

## Questions

**Q1.** Among generators trained on the same observational data, does a joint distributional fidelity metric (the propensity-score mean squared error, pMSE, of Snoke 2018) rank generators the way their distortion of the sustained-strategy risk difference ranks them?

**Q2.** Does any generator pass the joint fidelity criterion while distorting the population effect, the effect in a rare stratum, or the support of the strategy in that stratum?

**Q3.** How much do leaf-size suppression (a privacy device), variable ordering and parametric simplification each contribute?

## What this leaves unanswered

Counterfactual fidelity for generators whose training data do not identify the effect; formal differential privacy mechanisms (leaf-size suppression is the only privacy device here); deep generative models, which are too expensive to train 14,000 times (7 per replicate) on this machine and are named as the main extension; and disclosure risk beyond a distance-to-closest-record summary.

## Simulation design

### Data-generating mechanism

`V ~ Bernoulli(pi_R)`, a rare stratum; `B ~ Bernoulli(0.4)`; `L0 ~ N(0, 1)`. `A0 ~ Bernoulli(expit(-0.3 + 0.6*L0 + 0.3*B-1.5*V))`. `L1 = 0.6*L0-0.5*A0 + 0.3*B + e`, `e ~ N(0, 0.8^2)`, so treatment moves the next confounder. `A1 ~ Bernoulli(expit(-0.5 + 0.6*L1 + 1.5*A0-1.5*V))`. `Y ~ Bernoulli(expit(-1.5 + 0.5*L1 + 0.3*L0 + 0.3*B-0.4*(A0 + A1) + V*(0.8 + 0.9*(A0 + A1))))`: treatment helps outside the stratum and harms inside it, and is rarely given inside it. Factors: `pi_R` in {0.08, 0.03}; `n` in {2000, 10000}. Four scenarios. Deliberately true: consistency, sequential exchangeability given the recorded history, positivity of both strategies in every stratum (always-treat is rare inside the stratum, not absent), no censoring.

### Estimands and truth

The risk difference for always-treat versus never-treat at the end of follow-up, `RD`; the same contrast within `V = 1`, `RD_V1`; the probability of following always-treat within `V = 1` under the observed law. Truth by Monte Carlo on 2 million common draws per scenario, averaging `expit` of the outcome predictor under each strategy rather than drawing outcomes (Monte Carlo standard error below 0.0003). Values computed for this proposal: `RD` = -0.107 (`pi_R` = 0.08) and -0.122 (0.03); `RD_V1` = +0.164 in both; always-treat is followed by 6.5% of the stratum. Expected always-treat followers inside the stratum: 52 at `n = 10000, pi_R = 0.08`; 20, 10 and 4 in the other three scenarios.

### Generators

Each is trained on the observed data and generates one synthetic dataset of the same size.

- **G0, oracle.** A fresh draw from the true mechanism: the noise floor.
- **G1, CART, time order.** `synthpop::syn` with CART, visit sequence `V, B, L0, A0, L1, A1, Y`, default minimum leaf size (Nowok 2016).
- **G2, CART with suppression.** As G1 with minimum leaf size 50, a privacy device that removes small cells.
- **G3, CART, reversed order.** Visit sequence `Y, A1, L1, A0, L0, B, V`.
- **G4, Gaussian copula.** Normal scores of each variable, their correlation matrix, multivariate normal draws, back-transformation through each variable's empirical quantiles (binary variables by thresholding at their observed proportion). Preserves marginals and pairwise rank association, not interactions.
- **G5a, sequential GLM, main effects.** Logistic and linear models in time order with main effects only; omits the stratum-by-treatment interaction.
- **G5b, sequential GLM, correct.** As G5a with the interaction; a positive control that is faithful by construction.

### Analysis applied to real and synthetic data alike

Iterated conditional expectation g-formula: logistic regression of `Y` on the full history including `V*(A0 + A1)`; the fitted values under each strategy regressed on the time-0 history by quasibinomial regression; the risk difference, and the same within `V = 1`. The outcome regression is correctly specified for the true mechanism; the second regression is a logistic approximation to an integral, whose error is common to real and synthetic analyses and largely cancels in the paired distortion below. Any excess distortion is the generator's. Variance: the sandwich from the stacked estimating equations of the two regressions and the standardization, computed identically on real and synthetic data, with a Wald 95% interval.

**Failure.** A generator fails when it errors or returns a dataset with a constant column. An analysis fails when a regression does not converge, shows separation (fitted probabilities below 1e-8 or above 1-1e-8 for every member of a covariate cell) or returns a nonfinite estimate or standard error. Failures are counted per generator and scenario; distortion is computed on replicates where both the real and the synthetic analysis succeed, and a generator failing in more than 10% of a scenario's replicates is reported as failing that scenario rather than summarized.

### Fidelity and disclosure metrics

- Joint fidelity: pMSE and its standardized ratio from `synthpop::utility.gen` with `method = "logit"` and its default interaction order (pinned at synthpop 1.9.2). A generator passes when its standardized pMSE is at or below the 95th percentile of G0's in the same scenario, meaning the metric cannot distinguish it from a perfect generator.
- Marginal fidelity, the common practice: every standardized mean difference below 0.1 and every binary proportion within 0.02.
- Disclosure: share of 2000 sampled synthetic records whose nearest real record, in standardized Euclidean distance, is closer than the 1st percentile of real-to-real nearest-neighbor distances.

### Performance

**Primary.** For each generator and scenario, the paired distortion `RD_synth-RD_real` on the same training data: its mean, and its root mean square minus G0's (excess error). Across the 6 non-oracle generators by 4 scenarios, the Spearman correlation between median standardized pMSE and excess error (Q1).

**Secondary.** Pass rates for joint and marginal fidelity; `RD_V1` distortion in the scenario with at least 50 expected followers in the stratum; the ratio of always-treat followers inside the stratum in synthetic versus real data; bias and coverage of `RD` computed on synthetic data against the truth; disclosure share; failure rates.

### Replicates

500 per scenario, 2000 in all, each training all 7 generators. The distortion of `RD` should have a standard deviation of about 0.017 at `n = 10000` if the risk difference has a standard error of about 0.012 and the synthetic draw adds a second sampling variance, and about 0.04 at `n = 2000`; its Monte Carlo standard error is then 0.001 to 0.002 (the smoke run confirms the standard deviation before the main run); pass rates have worst-case Monte Carlo standard error 0.022. The study is planned and reported in the ADEMP structure (Morris 2019).

### Gates

G0's excess error is zero by definition and its root mean square distortion must be below 0.03 at `n = 10000`; G5b's mean distortion must be within 0.005 of zero with its Monte Carlo interval covering zero (implementation check); at least two non-oracle generators must pass marginal fidelity in at least 80% of replicates, otherwise the comparison the entry describes does not arise. The rare-stratum question is evaluated only where at least 50 always-treat followers are expected inside the stratum (one scenario, 52 expected), because below that the real data cannot estimate `RD_V1` either.

## What would show the problem real or not real

- **Real**: some non-oracle generator passes joint fidelity in at least 80% of replicates of a scenario while its mean `RD` distortion has a Monte Carlo interval lying beyond 0.02 in absolute value, or its `RD_V1` distortion lies beyond 0.05, or it retains fewer than half the real data's always-treat followers inside the stratum; or the Spearman correlation in Q1 is at most 0.3.
- **Not real**: every generator passing joint fidelity in at least 80% of replicates has mean `RD` distortion within 0.01 and retains at least 75% of stratum followers, every generator with material distortion fails joint fidelity in at least 80% of replicates, and the correlation is at least 0.8. The joint metric then screens effect distortion in this mechanism, and the residual problem is only that practice reports marginal metrics.
- **Predetermined, reported but not decisive**: G4 passes marginal fidelity by construction, so its marginal pass with material distortion is a demonstration of the entry's point about marginal metrics, not evidence for it.
- **Uninformative**: a gate fails.

## Cost

Measured on this machine for this proposal: `synthpop::syn` with CART on 5000 rows and 6 variables, 1.16 CPU-seconds (0.53 with minimum leaf size 100); a single-penalty `glmnet` fit, 0.01. The default `utility.gen` (CART propensity with permutation) took 26 CPU-seconds, which is why the logistic version is specified. Per replicate at `n = 10000`: three CART syntheses at about 2.5 seconds each, three parametric generators under 0.5 seconds together, seven logistic pMSE fits of about 0.3 seconds, seven g-formula analyses of about 0.1 seconds, seven disclosure summaries of about 0.5 seconds: about 14 CPU-seconds; at `n = 2000` about 3.5. Total 1000 by 14 plus 1000 by 3.5, about 5 CPU-hours; the budget is 15 to cover truth, smoke runs and the loaded machine. Person-hours: code and tests 40, analysis and write-up 25.

## Threats to validity

The outcome regression is correctly specified, which isolates generator error but is favorable; with a misspecified analysis model generator and analysis errors could cancel. One mechanism with one rare stratum; the conclusions are conditional on it. The joint fidelity criterion uses the oracle's distribution, which a practitioner does not have; the practical analogue, a fixed threshold on the standardized ratio, is reported alongside. Only one privacy device is studied.

## Citations

- Shi J, Wang D, Tesei G, Norgeot B. Generating high-fidelity privacy-conscious synthetic patient data for causal effect estimation with multiple treatments. Frontiers in Artificial Intelligence. 2022;5:918813. doi:10.3389/frai.2022.918813
- Nowok B, Raab GM, Dibben C. synthpop: Bespoke Creation of Synthetic Data in R. Journal of Statistical Software. 2016;74(11). doi:10.18637/jss.v074.i11
- Snoke J, Raab GM, Nowok B, Dibben C, Slavkovic A. General and Specific Utility Measures for Synthetic Data. Journal of the Royal Statistical Society Series A: Statistics in Society. 2018;181(3):663-688. doi:10.1111/rssa.12358
- Morris TP, White IR, Crowther MJ. Using simulation studies to evaluate statistical methods. Statistics in Medicine. 2019;38:2074-2102. doi:10.1002/sim.8086
