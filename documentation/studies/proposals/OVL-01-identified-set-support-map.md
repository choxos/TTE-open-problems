# OVL-01: the identified set under longitudinal nonpositivity, and what a support map has to report

**Catalog problem.** Positivity diagnostics describe weights instead of naming which patient histories are unsupported. Verdict `partially-addressed`; triage: analytic, answerable in part, feasibility 2, scope core.

**Residual claim this design tests.** The audit narrowed the entry. Diagnostics that name unsupported subgroups exist: PoRT for a point treatment (Danelian 2023), sPoRT for sequential static and dynamic strategies (Chatton 2025), an estimand-specific sparsity diagnostic for continuous treatments and modified policies (Ring and Schomaker 2026), and the `feasible()` workflow of the CRAN package CICI, whose pinned source codex read and found to mis-weight its probability-mass threshold when bin widths differ from one. Codex also separated structural nonpositivity, which is an identification failure, from practical near-nonpositivity, which is an estimation problem, and noted that truncation changes the estimating functional rather than defining a coherent new estimand. An applied example shows poor overlap defeating otherwise well-specified adjustment (Takayama 2026). What no audited work supplies: the identified set for a sustained strategy once some histories lack support, a statement of which population quantity carries the unsupported fraction (the observed cohort, the observed followers, or the history distribution the strategy itself induces), and what an inverse-probability-weighted estimate converges to when support fails. This design sets out to prove those three things and checks them numerically.

## Questions

**Q1.** For a deterministic sustained strategy with structurally unsupported histories, what is the sharp identified set for the strategy-specific risk and for the risk difference, and which identified quantity sets its width?

**Q2.** What do the Horvitz-Thompson and Hajek inverse-probability-weighted estimators converge to under structural nonpositivity, and does weight truncation change that?

**Q3.** Is any summary of the follower weight distribution (histogram, maximum, effective sample size ratio, percentiles) a function of the unsupported mass? Is any weight functional?

**Q4.** Which denominator gives the unsupported fraction: the observed cohort, unweighted followers, or followers weighted to the strategy's history distribution?

**Q5.** In finite samples with a parametric propensity model, how well is the unsupported mass estimated, and do conventional weight diagnostics raise an alarm when a structural hole of material size is present?

## What this leaves unanswered

No theorem supplies the practical-support threshold; the design reports the unsupported mass as a curve over thresholds so the threshold becomes a stated choice, not a hidden one. The design does not evaluate sPoRT, PoRT or CICI as algorithms (LRN-01's registered study evaluates one prediction-level support map empirically), does not treat continuous treatments or stochastic policies beyond the one modified strategy defined below, and does not supply bounds sharper than worst case, which need substantive restrictions on the unidentified outcome law (monotonicity, smoothness across the support boundary) that are outside the entry.

## Setting and assumptions

Discrete decision times `t = 0, ..., K-1`, history `H_t = (L_0, A_0, ..., L_t)`, binary treatment, outcome `Y` in [0, 1] measured after `K-1`. A deterministic static or dynamic strategy `g` assigns `g_t(H_t)`. Consistency, sequential exchangeability given `H_t`, no censoring. Let `pi_t(h) = P(A_t = g_t(h) | H_t = h)`. For a threshold `eps >= 0`, the unsupported set is `U_t(eps) = {h : pi_t(h) <= eps}`; `eps = 0` is structural nonpositivity. Let `P^g` be the g-formula law of histories under `g`, `T` the first time the history enters `U_t`, and

- `q_g(eps) = P^g(T <= K-1)`, the mass of the strategy's own history distribution that reaches an unsupported history;
- `m_g = E^g[Y 1{T = infinity}]`, the outcome mass carried by paths that never leave support;
- `W_g = prod_t 1{A_t = g_t(H_t)} / pi_t(H_t)`, the unnormalized inverse-probability weight, zero for anyone who departs from `g`.

The modified strategy `g'` follows `g` on supported histories and, after entry into `U`, the natural treatment process. It is a realistic individualized rule in the sense of the positivity literature (Petersen 2012) and is identified by construction. Incremental propensity-score interventions (Kennedy 2019) and longitudinal modified treatment policies (Díaz 2023) are the other standard ways of changing the estimand to restore support; the claims below concern what is lost when the deterministic strategy is kept.

## Claims to be proved or refuted

- **C1 (identification of the unsupported mass).** `q_g(eps)` is identified: it equals `sum_t E[W_{g,t-1} 1{H_t in U_t, T >= t}]`, where `W_{g,t-1}` is the weight through `t-1`, because the law of paths up to the first entry into `U` involves only supported conditionals.
- **C2 (sharp set).** With no restriction on the law after entry into `U`, the sharp identified set for `E[Y^g]` is `[m_g, m_g + q_g(0)]`. For two strategies whose unidentified components are variation independent, the risk difference has sharp width `q_{g1}(0) + q_{g0}(0)`. Proof: attainment by completions that set the post-entry outcome mean to 0 or 1.
- **C3 (what weighting estimates).** With the true propensities, `E[W_g] = 1-q_g(0)`, the Horvitz-Thompson mean `E[W_g Y]` converges to `m_g`, the lower endpoint, and the Hajek mean converges to `E^g[Y | T = infinity]`: a mean conditional on a post-baseline event whose probability depends on the strategy. A Hajek contrast of two strategies therefore compares two different, strategy-defined subpopulations. A weight cap cannot repair this: no one follows `g` at an unsupported history, so the weights there are zero before any cap, and the cap acts only on supported histories, where it adds bias of its own.
- **C4 (follower weights are blind).** There exist observed laws with identical normalized follower-weight distributions and different `q_g`. Counterexample, point treatment: `X` in {1, 2, 3} with probabilities (0.5, 0.3, 0.2); law 1 has `P(A = 1 | X) = (0.5, 0.5, 0.5)`, law 2 has (0.5, 0.5, 0). Every follower weight equals 2 under both laws, so the histogram, maximum, effective sample size ratio and every percentile coincide, while `q = 0` and `q = 0.2`. The unnormalized mean `E[W]` is 1 and 0.8. So C4 holds for follower summaries and fails for the unnormalized mean, which carries `q_g` when, and only when, the propensity model can represent zero.
- **C5 (the denominator).** The time-`t` component of `q_g` is the share of followers through `t-1` weighted by `W_{g,t-1}`. The share of the observed cohort in `U_t`, and the unweighted share among followers, can each be larger or smaller than it.
- **C6 (the retained estimand lies in the set).** `E[Y^{g'}]` is identified and lies in `[m_g, m_g + q_g(0)]`, since `g` and `g'` agree before `T`. A report of `(q_g, m_g, E[Y^{g'}])` therefore states both what the named strategy loses and one identified strategy that keeps the full population.

Step 1 of the study is a literature check of each claim in longitudinal form. The point-treatment versions of C2 and C3 are elementary worst-case bounding arguments; any claim already proved in longitudinal form is cited rather than re-proved, and the study then reduces to C5, C6 and Q5.

## Worked example (computed exactly from the parameters given)

Two decisions. Frailty `L_0` with `P(L_0 = 1) = 0.3`; `P(A_0 = 1 | L_0) = (0.2, 0.5)`. A contraindication `L_1` develops with `P(L_1 = 1 | L_0, A_0)` equal to 0.05, 0.25, 0.20, 0.60 for `(L_0, A_0)` = (0,0), (0,1), (1,0), (1,1): treatment raises it. No one with `L_1 = 1` is treated at time 1, so always-treat is structurally unsupported there. With `E[Y | L_0, followers, L_1 = 0] = (0.10, 0.20)` and `E[Y | L_0, A_0 = 1, L_1 = 1, A_1 = 0] = (0.30, 0.50)`:

| Quantity | Value |
| --- | --- |
| `q_g`, weighted-follower share (C5) | 0.355 |
| Share of the observed cohort with `L_1 = 1` | 0.183 |
| Unweighted share among time-0 followers | 0.431 |
| Sharp set for `E[Y^g]` (C2) | [0.077, 0.432] |
| Horvitz-Thompson limit (C3) | 0.077 |
| Hajek limit (C3) | 0.119 |
| Modified strategy `E[Y^{g'}]` (C6) | 0.219 |

A Monte Carlo check with 400,000 draws and true propensities gave mean weight 0.643 (1-q = 0.645), Horvitz-Thompson 0.076 and Hajek 0.118. The cohort share understates the unsupported mass by half and the unweighted follower share overstates it, which is the practical content of C5.

## Numerical verification (Q5)

A small simulation, in the schema of the registered designs, checks the finite-sample behavior that the proofs do not settle.

**Data-generating mechanism.** Three decisions `t = 0, 1, 2`. `V ~ Bernoulli(0.3)`; `L_0` in {0, 1} with `P(L_0 = 1 | V) = 0.2 + 0.3V`. For `L_t` in {0, 1}, `logit P(A_t = 1) = -0.4 + 0.6V + 0.5*1{L_t = 1} + 1.5*A_{t-1}` (last term absent at `t = 0`). `L_{t+1} = 2` is absorbing and occurs with probability `expit(-3.2 + 1.2*1{L_t = 1} + 0.9*A_t + 0.6V)`; otherwise `L_{t+1} = 1` with probability `expit(-1 + 1.5*1{L_t = 1} + 0.5V-0.3*A_t)`, else 0. `P(Y = 1) = expit(-2.2 + 0.7V + 0.5*1{L_2 = 1} + 1.2*1{L_2 = 2}-0.6*mean(A_0, A_1, A_2))`. Three support laws at `L_t = 2`: structural hole, `P(A_t = 1) = 0`; practical hole, 0.01; no hole, `logit P(A_t = 1) = -0.4 + 0.6V + 1.3 + 1.5*A_{t-1}`. The outcome and covariate laws, hence every causal truth, are identical across support laws; the counterfactual completion inside the hole uses the same formulas with `A_t = 1`.

**Estimands and truth.** Always-treat and never-treat risks at the end of follow-up, their difference, `q_g(eps)` for `eps` in {0, 0.01, 0.025, 0.05}, `m_g`, the sharp set, the Hajek limit and `E[Y^{g'}]`, all computed by exact enumeration over the 36 covariate paths (no Monte Carlo error). Values from the enumeration: always-treat risk 0.126, never-treat 0.181, risk difference -0.055; `q_g(0)` = 0.305 for always-treat and 0 for never-treat; sharp set for the risk difference [-0.123, 0.182]; Hajek limit of the risk difference -0.097, which is 0.042 from the truth.

**Methods.** (a) Hajek IPW with a correctly specified saturated propensity model; (b) Hajek IPW with a main-effects logistic propensity model (cannot represent a zero); (c) both with a fixed cap of 50; (d) the plug-in estimate `1-mean(W_g)` of `q_g(0)` and the thresholded plug-in of `q_g(eps)` under each propensity model; (e) bounds `[m_hat, m_hat + q_hat]` with the Imbens-Manski 95% interval, standard errors from the stacked estimating equations of the propensity models and the two means; (f) conventional diagnostics: maximum weight, effective sample size as a share of followers, 99th weight percentile, and the mean of stabilized weights, whose closeness to 1 is the usual check (Cole and Hernán 2008). Failure: nonconvergent GLM, zero followers, or nonfinite estimate; failures are counted, not dropped.

**Scenarios and replicates.** Three support laws by `n` in {1000, 5000}: six scenarios. 2000 replicates each; worst-case Monte Carlo standard error for a proportion is 0.011, and 0.005 at a coverage of 0.95.

**Performance.** Bias of `q_hat` against `q_g(eps)`; coverage of the true sharp set by the Imbens-Manski interval; distance of the Hajek estimate from the true risk difference; the share of structural-hole replicates in which any conventional diagnostic crosses its usual alarm (maximum weight above 100, effective sample size below 50% of followers, or stabilized-weight mean outside [0.9, 1.1]), against the same share in the no-hole scenario.

**Gates, checked on paper.** Material hole: `q_g(0) >= 0.10` (0.305). Material estimand change: Hajek-limit distance from truth at least 0.02 (0.042). Non-vacuous estimate: every scenario has at least 100 always-treat and 100 never-treat followers in the median replicate at `n = 1000`; the enumeration gives always-treat follower probabilities of 0.21 (structural hole), 0.21 (practical hole) and 0.34 (no hole), and never-treat probabilities of 0.18, 0.18 and 0.13, so the smallest expectation is about 130.

## What would show the problem real or not real

- **Real**: C3 to C5 are proved; in the structural-hole scenario at `n = 5000` the Hajek estimate is at least 0.02 from the truth with its 95% Monte Carlo interval excluding 0.02; and the conventional diagnostics alarm in at most 20% more replicates than in the no-hole scenario (upper simultaneous Monte Carlo bound). A reader of the standard report cannot then tell that the estimand changed.
- **Not real**: a standard follower-weight summary is shown to determine `q_g`, contradicting C4; or the conventional diagnostics alarm in at least 90% of structural-hole replicates and at most 10% of no-hole replicates, so the weight report already signals the failure even though it names no histories. The second branch is reachable because a main-effects logistic model gives small, not zero, probabilities near the boundary and can produce large weights there.
- **Solution component**: `1-mean(W_g)` estimates `q_g(0)` within 0.02 absolute bias under the main-effects model at `n = 5000`, and the Imbens-Manski interval covers the sharp set in at least 0.93 of replicates. Otherwise the report must carry the unsupported mass only from a model able to represent zeros, which is itself the finding.
- **Uninformative**: a gate fails, or more than 5% of replicates fail numerically in the no-hole scenario.

## Cost

Analytic work: literature check 15 person-hours, proofs of C1 to C6 in longitudinal form 40, internal review of the proofs by a second statistician 15, simulation code and known-answer tests 20, write-up 20. Total about 110 person-hours. Compute: each replicate fits three logistic models under two specifications and evaluates closed-form means; a logistic GLM at `n = 5000` took 0.026 CPU-seconds on this machine, so a replicate is about 0.2 CPU-seconds with the means and diagnostics, and 12,000 replicates need under 2 CPU-hours. A smoke run of 20 replicates per scenario under the shared harness fixes the figure before the main run.

## Threats to validity

Worst-case bounds are wide by construction; the value of the set is that it states the loss, not that it is informative. The completion used for truth inside the hole is one of infinitely many observationally equivalent completions, so bias of the Hajek estimate is reported against the sharp set as well as against that truth. The example is binary and discrete so that truth is exact; continuous histories change the estimation of `U_t`, not the claims. Choosing the alarm thresholds of conventional diagnostics is a convention; the thresholds are fixed above and results are reported for a grid.

## Citations

- Danelian G, Foucher Y, Léger M, Le Borgne F, Chatton A. Identification of in-sample positivity violations using regression trees: The PoRT algorithm. Journal of Causal Inference. 2023;11:20220032. doi:10.1515/jci-2022-0032
- Chatton A, Schomaker M, Luque-Fernandez M-A, Platt RW, Schnitzer ME. Is Checking for Sequential Positivity Violations Getting You Down? Try sPoRT! Epidemiology. 2025;36:751-759. doi:10.1097/EDE.0000000000001902
- Ring K, Schomaker M. A diagnostic to find and help combat stochastic positivity issues, with a focus on continuous treatments. Journal of Causal Inference. 2026;14:20250007. doi:10.1515/jci-2025-0007
- Petersen ML, Porter KE, Gruber S, Wang Y, van der Laan MJ. Diagnosing and responding to violations in the positivity assumption. Statistical Methods in Medical Research. 2012;21:31-54 (online 2010). doi:10.1177/0962280210386207
- Cole SR, Hernán MA. Constructing Inverse Probability Weights for Marginal Structural Models. American Journal of Epidemiology. 2008;168:656-664. doi:10.1093/aje/kwn164
- Takayama A, Tanaka S, Kawakami K. Target trial emulation under nonmutually exclusive assignment: structural pitfalls and methodological remedies. American Journal of Epidemiology. 2026;195:1045-1055. doi:10.1093/aje/kwag014. The catalog entry records this paper under doi:10.1093/aje/kwaf018, which CrossRef resolves to an unrelated article.
- Kennedy EH. Nonparametric Causal Effects Based on Incremental Propensity Score Interventions. Journal of the American Statistical Association. 2019;114:645-656 (online 2018). doi:10.1080/01621459.2017.1422737
- Díaz I, Williams N, Hoffman KL, Schenck EJ. Nonparametric Causal Effects Based on Longitudinal Modified Treatment Policies. Journal of the American Statistical Association. 2023;118:846-857 (online 2021). doi:10.1080/01621459.2021.1955691
