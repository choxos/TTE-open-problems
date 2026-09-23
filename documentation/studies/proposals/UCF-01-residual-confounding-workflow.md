# UCF-01: does a prespecified sequence of negative controls, proxies and validation data signal its own failure?

**Catalog problem.** Negative controls, proxies and validation data are not integrated into a standard emulation workflow. Verdict `partially-addressed`; triage: simulation plus case study, answerable in part, feasibility 2, not a target trial emulation problem.

**Bearing on target trial emulation.** A correctly specified target trial removes design-induced bias and leaves confounding (Hubbard 2024); this study answers the residual-confounding question for a point-initiation emulation (an intention-to-treat analogue), and says nothing about sustained strategies with time-varying unmeasured confounding.

**Residual claim this design tests.** The full-text reading found 20 papers applying one of these tools inside an emulation, among them a proximal emulation with declared negative control exposures and outcomes (Guo 2025) and a crystalloid emulation whose prespecified negative control outcomes flagged residual confounding but were themselves length-of-stay dependent (Dai 2026). Codex corrected the entry: negative controls often diagnose rather than correct, instrument and proxy relevance are partly testable, and the tools can target different estimands, so they cannot be ordered or combined mechanically. What survives is the entry's operational claim: no agreed sequence exists, and its central hazards (a negative control that shares only part of the confounding, weak proxies whose instability looks like imprecision, validation subsamples selected nonrandomly) have not been evaluated as a sequence that must either correct the estimate or say that it cannot. This design builds that sequence, gives it one estimand, and measures how often it fails without saying so.

## Questions

**Q1.** Under which violations of each tool's own assumptions does a prespecified sequence (conventional estimate, negative control outcome test, then validation-based or proximal correction, else a red flag) return a wrong interval while reporting that it corrected the estimate?

**Q2.** How often does each tool's available diagnostic (negative control test, first-stage proxy strength) signal the failure of that tool's assumptions?

**Q3.** Applied to a public dataset with a published proxy declaration, do the tools agree, and how much of the spread is due to the choice of proxies?

## What this leaves unanswered

Sustained strategies, time-varying unmeasured confounding and longitudinal proximal estimators; instrumental variables (no instrument is simulated); how to combine disagreeing tools into one estimate, which the triage records as not generally answerable; and whether the sequence tested is the best one. The simulation uses linear risk models in the unmeasured confounder so that the proximal bridge is correctly specified whenever its structural assumptions hold; nonlinear bridges are out of scope.

## Simulation design

### Data-generating mechanism

`X`, `U`, `V`, and the proxy noise are independent `Uniform(-sqrt(3), sqrt(3))` (unit variance, bounded so risks stay in [0, 1]). `U` is an unmeasured confounder shared with the controls; `V` is a second unmeasured confounder that the controls do not see.

- Treatment-inducing proxy (negative control exposure): `Z = zeta*U + 0.3*X + e_Z`.
- Treatment at time zero: `A ~ Bernoulli(expit(-0.3 + 0.4*X + 0.6*U + 0.6*lambda_V*V + 0.3*Z))`.
- Outcome-inducing proxy (negative control outcome), binary and measured at baseline: `P(W = 1) = 0.30 + 0.05*U + 0.03*X`.
- One-year outcome: `P(Y = 1) = 0.40-0.05*A + 0.02*X + beta_U*U + 0.04*lambda_V*V + gamma_Z*Z`.
- Validation indicators, all drawn on every dataset: `R1 ~ Bernoulli(0.10)` (random, known); `R2 ~ Bernoulli(0.05 + 0.15*Y)` (outcome-dependent, probabilities known); `R3 ~ Bernoulli(expit(-2.4 + 0.3*A + 0.4*Y + 0.3*A*Y))` (selection on treatment and outcome, unknown to the analyst). In validated records `U` and `V` are measured without error.

Factors: `beta_U` in {0.05, 0.10}: at 0.05 the negative control outcome carries the same confounding bias on the risk-difference scale as `Y`, at 0.10 it carries half. `lambda_V` in {0, 1}: whether a confounder exists that no control shares. `zeta` in {1.5, 0.5}: strong or weak proxies. `gamma_Z` in {0, 0.015}: whether the treatment proxy affects the outcome directly (exclusion violated). `n` in {5000, 20000}. 32 scenarios. Deliberately true: consistency, no interference, no censoring, positivity (all propensities lie strictly inside (0, 1)), correct linear form of the outcome and proxy laws in `U`.

### Estimand and truth

The one-year risk difference for initiating versus not initiating at time zero in the eligible population. The outcome law is additive in `A` with no effect modification, so the truth is -0.05 exactly in every scenario and needs no Monte Carlo evaluation.

### Methods

- **M1, conventional.** AIPW adjusting for `X`: logistic propensity model, linear outcome regression, Wald interval from the influence-function variance. Status quo.
- **M2, negative control outcome test.** The same AIPW with `W` as outcome (Lipsitch 2010); confounding is flagged when its 95% interval excludes zero. A diagnostic, not an estimator.
- **M3, negative-control calibration.** M1 minus the M2 estimate, variance from the difference of the two influence functions. Assumes equal confounding bias on the risk-difference scale.
- **M4, proximal two-stage least squares.** First stage `W ~ A + Z + X`; second stage `Y ~ A + W_hat + X`; coefficient of `A`; heteroskedasticity-robust two-stage sandwich variance (Miao 2018; Tchetgen Tchetgen 2024). Proxy strength: first-stage partial F for `Z`, weak when below 10.
- **M5a, M5b, M5c, validation-based.** AIPW adjusting for `X`, `Z`, `U`, `V` within the validated records, weighted by the inverse known sampling probability for `R1` and `R2` and unweighted for `R3`, where the analyst takes the subsample as random. Influence-function variance with the weights.
- **M6, oracle.** AIPW adjusting for `X`, `Z`, `U`, `V` in the full data; the implementation benchmark.
- **Workflow, prespecified.** Fit M1 and M2. If M2 does not flag, report M1 (green). If it flags: report M5 when validation data exist (amber); otherwise report M4 when `F >= 10` (amber); otherwise report M1 marked red, meaning confounding detected and no admissible correction. Three variants by validation availability: none, known design (`R2`), unknown selection (`R3`). A secondary variant places M4 before M5. The E-value for M1 (VanderWeele and Ding 2017) is recorded with every report.

Failure: nonconvergent propensity model, fewer than 50 validated records or fewer than 10 treated or untreated among them, singular first stage, nonfinite estimate or standard error. Failures are counted and the workflow treats a failed step as unavailable.

### Performance

**Primary.** For each workflow variant and scenario, the silent failure rate: the proportion of replicates whose final 95% interval excludes -0.05 while the flag is green or amber.

**Secondary.** Bias, empirical and model standard errors, coverage and interval width for M1 to M6; M2's flag rate (its sensitivity, since confounding is present in every scenario); the weak-proxy flag rate and M4's coverage among replicates with `F >= 10` and with `F < 10`; for each method, the share of replicates in scenarios violating its own assumptions in which its diagnostic flags; the rate at which M4 and M5 disagree (difference test at 0.05) and which is closer to the truth; the E-value distribution by scenario.

### Replicates

2000 per scenario, 64,000 in all. A proportion has worst-case Monte Carlo standard error 0.011, and 0.005 at a coverage of 0.95; bias for the noisiest method (weak-proxy M4, empirical standard error about 0.035 at `n = 5000` in the check below) has Monte Carlo standard error 0.0008. Decisions use one-sided Wilson bounds with Bonferroni adjustment over the 32 scenarios; the study is planned and reported in the ADEMP structure (Morris 2019).

### Gates, with a scratch check

A numpy implementation of M1 to M5 was run for this proposal at `n = 400,000` in all 16 parameter combinations, and 40 replicates at `n = 5000` in two:

- Material confounding: M1 bias between 0.034 and 0.125 across combinations (gate: at least 0.02 everywhere).
- Correct implementation where assumptions hold: M3 bias 0.004 and -0.001 when `beta_U = 0.05`, `lambda_V = 0`, `gamma_Z = 0`; M4 bias between -0.004 and 0.005 whenever `lambda_V = 0` and `gamma_Z = 0`; M5 with random or known-design sampling within 0.017 in every combination, in single draws whose validated subsamples of about 40,000 carry a Monte Carlo standard error of about 0.005.
- Violations are material: M3 bias 0.019 to 0.085 when `beta_U = 0.10` or `lambda_V = 1`; M4 bias up to 0.030 when `lambda_V = 1` and down to -0.024 when `gamma_Z = 0.015`; M5 under unknown selection biased by 0.035 to 0.062.
- The proxy-strength diagnostic is not decided in advance: first-stage F scaled to `n = 5000` is about 30 for strong and 8 to 10 for weak proxies, so the weak-proxy flag fires in some replicates and not others; at `n = 20000` it is about 4 times larger.
- At `n = 5000`, in a first run of the same mechanism with `zeta` of 1.0 and 0.4 (median first-stage F 22 and 5.5), M1 had standard error 0.014 and M4 an empirical standard error of 0.022 and 0.035, with a median model standard error of 0.029 in the weak case: the weak-proxy case already shows instability that reads as imprecision, with the model standard error too small.

The registered gates: M6 coverage at least 0.93 in every scenario, and M4 coverage at least 0.93 in the four scenarios where its assumptions hold with strong proxies. Either failing means an implementation defect.

## What would show the problem real or not real

- **Real**: in at least 8 of the 32 scenarios the lower bound of the silent failure rate is at least 0.20 for the no-validation or unknown-selection workflow, and in those scenarios the available diagnostics flag the failing tool in at most half of replicates. The sequence then does not integrate the tools in the sense the entry needs: it corrects in the wrong direction without saying so.
- **Not real**: the upper bound of the silent failure rate is at most 0.10 in every scenario for every workflow variant; the sequence then either corrects or raises a red flag, and the missing piece is only adoption.
- **Also reported, not decisive**: that M3 is biased when the control carries half the confounding is algebra, not a finding; what matters is the rate at which M2 flags confounding in those scenarios (so M3 would be applied) and the size of the resulting silent failure.
- **Uninformative**: a gate fails, or more than 5% of replicates fail numerically in any scenario at `n = 20000`.

## Case study: the SUPPORT right heart catheterization data

**Data.** The SUPPORT right heart catheterization dataset (Connors 1996), 5735 critically ill adults, 2184 of whom received catheterization within 24 hours of ICU admission, public at `https://hbiostat.org/data/repo/rhc.csv` (downloaded and checked for this proposal: 5735 rows, 2184 treated, 1918 deaths by 30 days). A proximal analysis of these data declared `Z` = (pafi1, paco21) and `W` = (ph1, hema1), from ten physiological measurements taken in the first 24 hours, with the remaining covariates as `X` (Cui 2024). The data contain no validation subsample and no candidate negative control outcome beyond the declared `W`.

**Target trial framing.** Eligible: adults in the SUPPORT intensive care cohort meeting the study's entry criteria; strategies: catheterization within 24 hours versus not; outcome: death by 30 days; estimand: risk difference, intention-to-treat analogue.

**Analysis.** The simulation's workflow without validation, unchanged: M1 with every covariate except the four proxies; M2 on each element of `W`; M3; M4 with the published allocation; the E-value. Then proxy-choice sensitivity: the four allocations obtained by removing one variable from `Z` or `W`, the exchange of `Z` and `W`, and every allocation of two of the ten physiological measurements to each role that passes the first-stage strength rule, reported as the distribution of proximal estimates. The report is the set of estimates on the one estimand with their intervals, the workflow's flag, and the ratio of the spread across allocations to the published allocation's interval width.

**What it can show.** Whether the tools agree on real data, and whether proxy choice moves the proximal estimate by more than its sampling interval. With no truth, it cannot show which estimate is right. The workflow's validation step cannot run on these data, which is itself a finding about what public data allow.

## Cost

Compute: the numpy check cost 0.028 CPU-seconds per replicate for three estimators at `n = 5000` on the loaded machine. An R implementation of all methods (about ten GLM and least-squares fits per replicate) is budgeted at 0.15 CPU-seconds at `n = 5000` and 0.6 at `n = 20000`, five times the numpy rate per fit: 32,000 replicates at each size give 1.3 plus 5.3, about 7 CPU-hours; the budget is 20 to cover truth checks, smoke runs and reruns. The case study is under 1 CPU-hour. Person-hours: simulation code and tests 40, case study 20, analysis and write-up 30.

## Threats to validity

Linear risk models make the proximal bridge easy; with a nonlinear bridge M4's performance where assumptions hold would be worse, so the study is favorable to proximal methods. The workflow ordering is one of several; the secondary ordering tests the most obvious alternative. A validated record measuring every confounder without error is optimistic. Equal-bias calibration with one control is the simplest form of calibration; empirical calibration over many controls (Schuemie 2014) is not simulated. The case study's proxies are measured at the same time as the treatment decision, so whether they could have affected it is a clinical judgment the data cannot check.

## Citations

- Hubbard RA, Gatsonis CA, Hogan JW, Hunter DJ, Normand S-LT, Troxel AB. "Target Trial Emulation" for Observational Studies: Potential and Pitfalls. New England Journal of Medicine. 2024;391(21):1975-1977. doi:10.1056/NEJMp2407586. The catalog entry attributes this article to Hubbard and Hernán; CrossRef lists the six authors given here.
- Guo J, Wang T, Liu Z, Zeng W, Shen P, Sun Y, Zhan S, et al. Estimating cardiovascular effects of influenza vaccination in older adults: a target trial emulation using proximal causal inference. eClinicalMedicine. 2025;87:103449. doi:10.1016/j.eclinm.2025.103449
- Dai Q, Hao Y, Shen J, Ren X, Jin C. Exposure definition sensitivity unmasks hidden confounding in crystalloid target trial emulation. iScience. 2026;29(7):116584. doi:10.1016/j.isci.2026.116584
- Lipsitch M, Tchetgen Tchetgen E, Cohen T. Negative Controls: A Tool for Detecting Confounding and Bias in Observational Studies. Epidemiology. 2010;21(3):383-388. doi:10.1097/EDE.0b013e3181d61eeb
- Miao W, Geng Z, Tchetgen Tchetgen EJ. Identifying causal effects with proxy variables of an unmeasured confounder. Biometrika. 2018;105(4):987-993. doi:10.1093/biomet/asy038
- Tchetgen Tchetgen EJ, Ying A, Cui Y, Shi X, Miao W. An Introduction to Proximal Causal Inference. Statistical Science. 2024;39(3). doi:10.1214/23-STS911
- Cui Y, Pu H, Shi X, Miao W, Tchetgen Tchetgen E. Semiparametric Proximal Causal Inference. Journal of the American Statistical Association. 2024;119(546):1348-1359 (online 2023). doi:10.1080/01621459.2023.2191817
- VanderWeele TJ, Ding P. Sensitivity Analysis in Observational Research: Introducing the E-Value. Annals of Internal Medicine. 2017;167(4):268-274. doi:10.7326/M16-2607
- Schuemie MJ, Ryan PB, DuMouchel W, Suchard MA, Madigan D. Interpreting observational studies: why empirical calibration is needed to correct p-values. Statistics in Medicine. 2014;33(2):209-218 (online 2013). doi:10.1002/sim.5925
- Connors AF, et al. The Effectiveness of Right Heart Catheterization in the Initial Care of Critically Ill Patients. JAMA. 1996;276:889. doi:10.1001/jama.1996.03540110043030
- Morris TP, White IR, Crowther MJ. Using simulation studies to evaluate statistical methods. Statistics in Medicine. 2019;38:2074-2102. doi:10.1002/sim.8086
