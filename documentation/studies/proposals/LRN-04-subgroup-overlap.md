# LRN-04: subgroup effects under differential overlap and differential measurement, with a check of the protected-group premise

**Catalog problem.** Subgroup effects are estimated where overlap is worst, and the groups with worst overlap are often the protected ones. Verdict `partially-addressed`; triage: simulation plus case study, answerable in part, feasibility 2, not a target trial emulation problem.

**Bearing on target trial emulation.** Subgroup effects in an emulation are conditional causal contrasts under the emulation's own identification conditions, so the answer here applies to any emulation that reports them; nothing in the design depends on the emulation structure.

**Residual claim this design tests.** The literature auditor found subgroup work inside emulations the entry does not credit (a subgroup extension of an emulation, heterogeneous statin effects estimated with causal machine learning inside an emulation, and a framework for effects on disparities). Causal machine learning inherits the identification conditions of the base analysis (Feuerriegel 2024), and poor overlap can defeat otherwise well-specified adjustment (Takayama 2026). Codex narrowed the rest: multiplicity is a problem for adaptively selected subgroups, not for every conditional estimator; that protected groups have the worst overlap is an empirical claim to be shown in data; shrinkage stabilizes but cannot repair nonidentification or differential measurement; restriction to overlap changes the target population. Grok agreed that honesty, trimming and shrinkage exist as components. What survives and is testable: whether prespecified subgroup estimators fail statistically where overlap is worst or merely become wide, whether a heterogeneity test's false declarations come from the worst-supported groups, what restriction and shrinkage buy at what cost, whether anything signals false heterogeneity produced by differential measurement, and whether the premise about protected groups holds in a real cohort.

## Questions

**Q1.** When overlap deteriorates in small prespecified subgroups, do stratified AIPW, a pooled model with subgroup interactions, and a causal forest keep nominal coverage in the worst-supported group?

**Q2.** Under no heterogeneity, how often does each method declare heterogeneity, and which groups drive the declarations?

**Q3.** What do overlap restriction and empirical Bayes shrinkage buy, and at what cost (estimand change, pull toward the pooled effect when heterogeneity is real)?

**Q4.** When a confounder is measured with error only in small groups, is the resulting false heterogeneity signaled by any overlap diagnostic?

**Q5.** In a public cohort, is overlap worst in the protected groups?

## What this leaves unanswered

Adaptive subgroup discovery and selective inference (the subgroups here are prespecified, which is the case codex identified as free of the multiplicity problem); differential access to care; subgroup validity of outcome ascertainment; and whether the premise holds beyond the one cohort examined.

## Simulation design

### Data-generating mechanism

Six prespecified groups `g = 1, ..., 6` with prevalences 0.50, 0.20, 0.12, 0.08, 0.06, 0.04. Covariates: `X1 ~ N(mu_g, 1)` with `mu = (0, 0.2, -0.2, 0.3, -0.3, 0.4)`; `X2 ~ N(0, 1)`; `X3 ~ Bernoulli(0.4)`; `X4 ~ N(0, 1)`. Treatment: `logit P(A = 1) = -0.6 + kappa_g*(0.8*X1 + 0.5*X2 + 0.4*X3-0.8*mu_g-0.16)`, centered so about 38% are treated in every group. Outcome, additive in treatment so subgroup truths are exact: `P(Y = 1) = p0 + tau*A`, with `p0 = 0.12 + 0.25*expit(-0.5 + 0.7*X1 + 0.4*X2 + 0.3*X3 + 0.2*X4 + 0.1*(g-1))` and `tau = -0.06 + delta*1{g >= 4} + 0.01*clip(X2, -2, 2)`; risks stay in [0, 1] for every covariate value.

Factors:

- Overlap: uniform, `kappa_g = 1`; differential, `kappa = (1, 1, 1.5, 2, 2.5, 3)`, steepest in the smallest groups.
- Heterogeneity: null, `delta = 0`; present, `delta = -0.04`.
- Measurement: exact; differential, where groups 4 to 6 record `X1* = X1 + N(0, 0.75^2)` (reliability 0.64) and the analyst uses `X1*`.
- `n` in {5000, 20000}; group 6 then has about 200 and 800 members.

16 scenarios. Deliberately true: consistency, no unmeasured confounding apart from the measurement factor, fixed prespecified groups.

Overlap measured on 2 million draws for this proposal: under uniform overlap 95% of every group has true propensity in [0.1, 0.9]; under differential overlap the shares are 0.95, 0.95, 0.84, 0.72, 0.62 and 0.54 by group. The case-study cohort's measured range, 0.75 to 0.90 across race, insurance and income levels, lies inside the grid.

### Estimands and truth

`tau_g = E[Y^1-Y^0 | G = g]`, equal to -0.06 in every group under the null and -0.10 in groups 4 to 6 otherwise, exactly, because `X2` is symmetric about zero and independent of group. The overlap-restricted estimand `tau_g^OR`, the same contrast among group members with true propensity in [0.1, 0.9], is computed per scenario by Monte Carlo on 2 million draws per group, averaging the conditional effect rather than drawing outcomes (standard error below 0.0002). The heterogeneity contrast is the vector of `tau_g-tau_1`.

### Methods

- **E1, stratified AIPW (status quo).** Within each group: main-effects logistic propensity model in `X1*`, `X2`, `X3`, `X4`, probabilities truncated to [0.01, 0.99]; arm-specific linear outcome regressions; influence-function variance; Wald interval.
- **E2, pooled AIPW.** One logistic propensity model with group indicators and common slopes, the specification most analyses use; outcome regression with treatment-by-group interactions; subgroup estimates are group means of the AIPW scores, variance from their influence functions.
- **E3, causal forest.** `grf::causal_forest` with honest splitting, 500 trees (the subgroup intervals come from the doubly robust scores, not from the forest's own variance estimate, so the package default of 2000 trees buys little here), default tuning otherwise, covariates `X1*`, `X2`, `X3`, `X4` and group indicators; subgroup estimates from `average_treatment_effect(subset = G == g)`; the heterogeneity test is a Wald test on the forest's doubly robust scores (Wager and Athey 2018; Athey, Tibshirani and Wager 2019).
- **E4, overlap restriction.** E1 among units with estimated propensity in [0.1, 0.9] (Crump 2009), evaluated against `tau_g^OR` and, separately, against `tau_g`; the retained fraction is reported.
- **E5, empirical Bayes shrinkage.** Normal-normal model on the six E1 estimates with REML between-group variance; posterior means and 95% intervals.
- Heterogeneity tests for E1 and E2: Cochran's Q across the six estimates (5 degrees of freedom) at 0.05.

Failure: fewer than 10 treated or 10 untreated in a group, a nonconvergent propensity model, or a nonfinite estimate or standard error. Failures are counted per group and never dropped silently.

### Performance

**Primary.** Coverage of `tau_6` by E1, E2 and E3 under differential overlap with exact measurement, at each `n`; and the rate at which E1, E2 and E3 declare heterogeneity under the null.

**Secondary.** Bias, empirical and model standard errors, coverage and interval width by group and method; simultaneous coverage across the six groups with Bonferroni intervals; power under `delta = -0.04`; among false declarations, the share in which group 5 or 6 has the largest standardized deviation from the pooled estimate; E4 coverage of `tau_g^OR` and of `tau_g`, and retained fraction; E5 bias toward the pooled effect in groups 4 to 6 when heterogeneity is present; under differential measurement, false declarations and the estimated in-band share in groups 4 to 6, since error in a confounder flattens the estimated propensity and makes overlap look better while biasing the estimate.

### Replicates

1000 per scenario for E1, E2, E4 and E5 in all 16 scenarios, and for E3 in the 8 scenarios at `n = 5000`. At `n = 20000`, E3 runs 500 replicates in the 4 scenarios with exact measurement only; this is where the primary comparison sits, and differential measurement at that size is evaluated with E1, E2, E4 and E5. Coverage at 0.95 has Monte Carlo standard error 0.0069 with 1000 replicates and 0.0097 with 500, worst case 0.016 and 0.022. Decisions use one-sided Wilson bounds, Bonferroni-adjusted across the three methods; the study is planned and reported in the ADEMP structure (Morris 2019).

### Gates, with a scratch check

A numpy implementation of E1 was run for this proposal, 150 replicates per cell. Under uniform overlap, group-6 coverage was 0.96 (`n = 5000`) and 0.95 (`n = 20000`); under differential overlap 0.93 and 0.91, with group-6 empirical standard errors of 0.132 and 0.068 against 0.018 and 0.009 in group 1, and group-6 bias under 0.015. The primary coverage question is therefore open at the planned precision rather than settled by construction. Registered gates: E1 coverage of `tau_1` at least 0.93 in every scenario with exact measurement (implementation check), and at most 5% failures per group in the uniform-overlap scenarios.

## What would show the problem real or not real

- **Real, as a statistical failure**: under differential overlap with exact measurement at `n = 20000`, group-6 coverage has an upper bound of at most 0.92 for both E1 and E3 while group-1 coverage has a lower bound of at least 0.93; or the null heterogeneity-declaration rate has a lower bound of at least 0.10 for E1 or E3, with group 5 or 6 carrying the largest standardized deviation in at least half of false declarations.
- **Not real, as a statistical failure**: group-6 coverage has a lower bound of at least 0.93 for E1 and E3, and the null declaration rate has an upper bound of at most 0.07. Poor overlap then appears as honest width, and the entry's concern reduces to reading a wide interval as a finding, which a reporting rule (support and width next to every subgroup estimate) addresses without a new estimator.
- **Q3 and Q4** are reported, not decided: restriction and shrinkage are expected to trade coverage of `tau_g` for precision, and nothing observable is expected to flag differential measurement; the measured magnitudes are the result.
- **Uninformative**: a gate fails.

## Case study: the SUPPORT right heart catheterization data (Q5)

**Data.** 5735 adults, 2184 catheterized within 24 hours, 30-day death as outcome (Connors 1996); public at `https://hbiostat.org/data/repo/rhc.csv`, downloaded for this proposal. Protected characteristics recorded: race (black 920, white 4460, other 355), insurance class (six levels, including Medicaid 647 and no insurance 322) and income (four levels).

**Analysis.** For each level of race, insurance and income: the share with estimated propensity in [0.1, 0.9] and the overlap-weight effective sample size fraction, from a pooled main-effects propensity model on all baseline covariates and from a level-specific model, with 1000-resample bootstrap intervals for the difference from the best-supported level. Then E1, E3, E4 and E5 for 30-day mortality by level.

**Preliminary measurement** (pooled main-effects model, no intervals, fitted for this proposal): in-band shares by race 0.83 (black), 0.87 (other), 0.84 (white); by insurance from 0.75 (Medicaid) to 0.90 (no insurance); by income from 0.82 (under $11,000) to 0.88. The premise holds for Medicaid and weakly for the lowest income level and not for race, which is why it must be tested rather than assumed.

**Decision for Q5.** The premise is supported in this cohort if, for at least two of the three characteristics, the worst-supported level is a protected one (black or other race, Medicaid or no insurance, lowest income) with a difference from the best level of at least 0.05 and a bootstrap interval excluding zero. It is not supported if that holds for none, and inconclusive if it holds for exactly one. One cohort cannot establish how often the premise holds.

## Cost

Compute: per replicate, E1, E2, E4 and E5 need about 20 logistic and linear fits and cost 0.045 CPU-seconds in the numpy check (six stratified AIPW fits); the causal forest dominates. Measured on this machine for this proposal, one `causal_forest` fit with 2000 trees and 10 covariates took 50.9 CPU-seconds at `n = 5000` and 278 at `n = 20000`, and six subgroup averages under 0.3; at 500 trees that is about 12.7 and 70 seconds. E3: 8000 fits at `n = 5000` (28 CPU-hours) and 2000 at `n = 20000` (39 CPU-hours). The other estimators need about 20 GLM and least-squares fits per replicate; a logistic GLM at `n = 5000` took 0.026 CPU-seconds, so about 0.5 seconds per replicate at `n = 5000` and 2 at `n = 20000`, 6 CPU-hours for 16,000 replicates. Total about 73 CPU-hours, inside the 100-hour ceiling; with 2000 trees and 1000 replicates everywhere the forest alone would need over 700, which is why E3's schedule is reduced rather than the grid. The case study is under 1 CPU-hour including bootstrap. Person-hours: simulation code and tests 40, case study 20, analysis and write-up 30.

## Threats to validity

Additive risk models make subgroup truths exact but are favorable to linear outcome regressions; the causal forest does not benefit from that. Six fixed groups with a monotone link between size and overlap is one configuration; the reversed pattern (worst overlap in the largest group) is not simulated. Differential measurement is modeled as classical error in one confounder. The case study uses a pooled model's covariate set for every level, and its protected characteristics are coarse.

## Citations

- Wager S, Athey S. Estimation and Inference of Heterogeneous Treatment Effects using Random Forests. Journal of the American Statistical Association. 2018;113:1228-1242. doi:10.1080/01621459.2017.1319839
- Athey S, Tibshirani J, Wager S. Generalized random forests. The Annals of Statistics. 2019;47. doi:10.1214/18-AOS1709
- Crump RK, Hotz VJ, Imbens GW, Mitnik OA. Dealing with limited overlap in estimation of average treatment effects. Biometrika. 2009;96:187-199. doi:10.1093/biomet/asn055
- Feuerriegel S, Frauen D, Melnychuk V, et al. Causal machine learning for predicting treatment outcomes. Nature Medicine. 2024;30:958-968. doi:10.1038/s41591-024-02902-1
- Takayama A, Tanaka S, Kawakami K. Target trial emulation under nonmutually exclusive assignment: structural pitfalls and methodological remedies. American Journal of Epidemiology. 2026;195:1045-1055. doi:10.1093/aje/kwag014. The catalog entry records this paper under doi:10.1093/aje/kwaf018, which CrossRef resolves to an unrelated article.
- Connors AF, et al. The Effectiveness of Right Heart Catheterization in the Initial Care of Critically Ill Patients. JAMA. 1996;276:889. doi:10.1001/jama.1996.03540110043030
- Morris TP, White IR, Crowther MJ. Using simulation studies to evaluate statistical methods. Statistics in Medicine. 2019;38:2074-2102. doi:10.1002/sim.8086
