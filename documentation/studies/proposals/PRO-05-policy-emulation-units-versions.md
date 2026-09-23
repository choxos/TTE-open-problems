# PRO-05: which protocol failures of a jurisdiction-level policy emulation change the estimand, and which only cost precision

**Catalog problem.** Emulation is proposed for non-pharmaceutical and policy interventions whose treatment versions and assignment units are not defined. Verdict `unverifiable` (the disagreement was evidence-bearing on both sides); triage: analytic, answerable in part, feasibility 2.

**Residual claim this design tests.** The auditors split. Codex: emulation is not restricted to individual assignment; policies can be assigned at the cluster level, multiple versions do not break consistency when the version rule is specified as a stochastic intervention (VanderWeele and Hernán 2013), the cluster-allocation framework supplies estimands (Papadogeorgou 2019), and no universal minimum jurisdiction count is defensible; what remains open is standardized protocols and finite-cluster guidance. Grok and the literature auditor: no protocol states which components a policy can satisfy, what estimand results when versions differ, or how many jurisdictions credible inference needs. Existing partial answers: a trial-emulation approach for policies with group-level longitudinal data (Ben-Michael, Feller and Stuart 2021); the weighting problems of two-way fixed effects under staggered timing and the group-time estimands that avoid them (Goodman-Bacon 2021; Callaway and Sant'Anna 2021); compound treatments and versions (Hernán and VanderWeele 2011). This design takes one bounded class, staggered adoption of a jurisdiction-level policy, and decides for three failures whether each changes the estimand or only precision. Partitioned from EST-01, which treats individual treatment inside clusters.

## Question

For a policy adopted by jurisdictions at staggered times, with a version chosen by each jurisdiction and individuals as the unit of measurement: (1) when versions differ and version choice depends on adoption time, what does the standard group-time analysis estimate, and does it equal the effect of the version mixture the protocol declares; (2) how do the variance of the policy effect and the coverage of individual-level and cluster-level intervals depend on the number of jurisdictions, and at what number do cluster-level methods become calibrated; (3) under spillover between neighboring jurisdictions, is the overall policy effect identified?

**Left unanswered.** Universal equivalence classes of versions, universal minimum counts (the result is a map over declared heterogeneity and correlation, not a rule), non-staggered or reversible policies, and interference inside jurisdictions (EST-01).

## Setting and assumptions

J jurisdictions observed for T = 10 periods. Adoption time T_j in {3, ..., 8}, or never for a fifth of jurisdictions; adoption is absorbing. Version V_j in {1, 2} chosen at adoption. Jurisdiction covariate W_j. n = 5,000 individuals per jurisdiction-period with binary outcome Y. Outcome model on the logit scale: jurisdiction and period effects, a jurisdiction-period shock epsilon_jt (AR(1), rho = 0.5, standard deviation sigma_e), and, after adoption, a version-specific effect tau_v plus jurisdiction heterogeneity N(0, sigma_tau^2); optionally a spillover term lambda times the share of adjacent jurisdictions (ring adjacency) that have adopted.

The target trial randomizes jurisdictions to adoption times and fixes the version rule in the protocol: either a named version, or a declared distribution D over versions given W_j. The policy estimand is the average effect on the risk in periods 0 to 2 after adoption among adopting jurisdictions, under the protocol's version rule, relative to not having adopted. Assumptions: parallel trends conditional on W_j for the not-yet-adopted comparison, no anticipation, consistency under the declared version rule.

## Claims

**P1, versions.** (a) With a named version v, the estimand is identified only if versions vary within strata of (W_j, adoption cohort) with positivity; if version is a function of adoption cohort, the version effects and cohort-specific effects are not separately identified. Proof by constructing two laws that agree on all jurisdiction-period observables and differ in tau_1. (b) With a declared version distribution D, the estimand is the effect of the stochastic intervention "adopt, with version drawn from D given W_j"; it is identified under the assumptions above when D is supported by the observed version choices. (c) The standard group-time estimator aggregated over cohorts targets a mixture whose version weights are those of the observed cohorts and their design weights, not D; the difference is derived in closed form and is zero when version choice does not depend on adoption time.

**P2, jurisdictions and precision.** For the group-time estimator on jurisdiction-period rates, Var = [sigma_tau^2 + c sigma_e^2] / J_a + O(1 / (J n)), with J_a the effective number of adopting jurisdictions and c a design constant derived for the staggered schedule. As n grows with J fixed, the individual-level standard error, which treats persons as independent, tends to zero while the true variance does not, so the coverage of the individual-level interval tends to zero whenever sigma_tau or sigma_e is positive. Closed form for the coverage as a function of J, n, sigma_tau and sigma_e.

**P3, spillover between jurisdictions.** With lambda not zero, the adopter versus not-yet-adopter contrast identifies own-adoption effects averaged over the neighbor-adoption shares that happen to coincide in calendar time, not the overall effect of every jurisdiction adopting versus none. Under an exposure mapping of own adoption plus neighbor share, the overall effect is identified only if neighbor share varies independently of own adoption time given W_j (joint positivity); a construction in which neighbor share is collinear with calendar time shows nonidentification.

## How the results are checked

Closed forms of P1(c) and P2 are checked against simulation; the nonidentification constructions of P1(a) and P3 are exhibited as explicit pairs of parameter values with identical observable distributions, verified by exact computation of the jurisdiction-period expected rates.

**Block A, precision (P2).** J in {6, 10, 20, 40, 80} by sigma_e in {0.05, 0.15} on the logit scale by sigma_tau in {0, 0.5 |tau|}: 20 scenarios; one version, no spillover, tau = log(0.85) at a baseline risk of 0.10. Outcomes are generated as binomial counts per jurisdiction-period, so no individual rows are stored. Methods: the group-time estimator with not-yet-adopted comparisons on jurisdiction-period rates, with (i) an individual-level standard error, (ii) a cluster-robust standard error with a small-sample correction and t reference on J − 1 degrees of freedom, (iii) a wild cluster bootstrap with 499 draws (Cameron, Gelbach and Miller 2008), (iv) randomization inference over the adoption schedule with 499 permutations, inverted to an interval. Truth: the risk-difference estimand computed exactly from the model by summation over the declared shocks' distribution (Gauss-Hermite quadrature, 64 nodes).

**Block B, estimands (P1, P3).** J = 40, sigma_e = 0.05, sigma_tau = 0: version effects equal or tau_2 = 2 tau_1, crossed with version choice independent of or dependent on adoption time (early adopters choose version 2 with probability 0.8, late adopters 0.2), plus two spillover settings (lambda = 0, lambda = 0.5 tau). Eight scenarios. For each, the estimator's probability limit is compared with three truths: the named-version effect, the declared-mixture effect with D set to the population version distribution, and the overall effect.

**Replicates.** Block A: 5,000 per scenario. A method is calibrated in a scenario when its 95% Wilson interval for coverage lies inside [0.93, 0.97]; at 5,000 replicates this passes with probability 0.99997 per check under exact calibration and fails with probability about 0.98 at a true coverage of 0.93 (exact binomial summation). Block B: 1,000 per scenario, bias only, MCSE below 0.001 at an empirical SE up to 0.03.

## What would show the problem real or not real

- **Real.** Either (a) under version choice that depends on adoption time, the aggregated estimator misses the declared-mixture effect by 10% or more of that effect in Block B, so a protocol that declares the version rule is still not honored by the standard analysis, and P1(c) gives the correction; or (b) no cluster-level method (ii to iv) is calibrated at J = 20 in the Block A scenarios with sigma_e = 0.15 and heterogeneous effects, so a credible policy emulation at that heterogeneity needs more than 20 jurisdictions and the entry's small-n concern is substantive. Either finding also yields the protocol item that fixes it: the declared version rule, or the minimum J at the declared heterogeneity.
- **Not real.** The aggregated estimator recovers the declared-mixture effect within 10% in every Block B scenario once the protocol declares the version rule, and at least one cluster-level method is calibrated at J = 10 in every Block A scenario. The failures are then either estimands the existing stochastic-intervention and cluster-allocation frameworks already define, or precision losses that standard cluster methods absorb, and the gap is a reporting template, as codex argued.
- **Uninformative.** A positive control fails: at J = 80 with sigma_tau = 0, the wild cluster bootstrap or randomization inference is not calibrated, or the Block B estimator misses the named-version effect when versions are equal and no spillover exists.

P1(a) and P3's nonidentification constructions are reported whichever branch holds; they are not in dispute and do not decide it.

## Cost

Person-hours: derivations P1 to P3, 60; simulation code and pilot, 35; write-up, 25; about 120. CPU, from assumed unit costs that a 50-replicate pilot per scenario must confirm: in Block A the estimator on at most 800 jurisdiction-period rates is cheap, and each replicate carries 499 bootstrap draws and 499 permutations, about 0.5 CPU-seconds, so 20 x 5,000 x 0.5 s = 13.9 CPU-hours; Block B, 8 x 1,000 x 0.02 s, under 0.1. Total about 14 CPU-hours. No data access.

## Threats to validity

- One policy class: absorbing, staggered, jurisdiction-level, two versions. Reversible policies, continuous intensities and dose-response in stringency are outside it.
- Conditional parallel trends and no anticipation hold by construction; the study separates estimand and precision failures from identification failures of the comparison itself.
- Ring adjacency is the simplest spillover structure; the P3 result is stated for a general exposure mapping, but the simulation checks only this one.
- The Block A grid of sigma_e and sigma_tau is declared, not estimated from applications; the output is a map that an analyst reads at their own heterogeneity.

## Citations

- VanderWeele TJ, Hernán MA. Causal inference under multiple versions of treatment. Journal of Causal Inference. 2013;1:1-20. doi:10.1515/jci-2012-0002
- Hernán MA, VanderWeele TJ. Compound treatments and transportability of causal inference. Epidemiology. 2011;22:368-377. doi:10.1097/EDE.0b013e3182109296
- Papadogeorgou G, Mealli F, Zigler CM. Causal inference with interfering units for cluster and population level treatment allocation programs. Biometrics. 2019;75:778-787. doi:10.1111/biom.13049
- Ben-Michael E, Feller A, Stuart EA. A trial emulation approach for policy evaluations with group-level longitudinal data. Epidemiology. 2021;32:533-540. doi:10.1097/EDE.0000000000001369
- Goodman-Bacon A. Difference-in-differences with variation in treatment timing. Journal of Econometrics. 2021;225:254-277. doi:10.1016/j.jeconom.2021.03.014
- Callaway B, Sant'Anna PH. Difference-in-differences with multiple time periods. Journal of Econometrics. 2021;225:200-230. doi:10.1016/j.jeconom.2020.12.001
- Cameron AC, Gelbach JB, Miller DL. Bootstrap-based improvements for inference with clustered errors. Review of Economics and Statistics. 2008;90:414-427. doi:10.1162/rest.90.3.414
