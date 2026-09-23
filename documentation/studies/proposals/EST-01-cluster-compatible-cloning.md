# EST-01: what individual cloning estimates under interference, and whether cluster-level cloning repairs it

**Catalog problem.** Emulation assumes no interference, and cloning individuals can produce joint strategies nobody could implement. Verdict `partially-addressed`; triage: analytic, answerable in part, feasibility 1.

**Residual claim this design tests.** Codex found the cloning account imprecise: cloning creates strategy-specific copies of each person and does not itself assign a realized cluster a joint strategy; identification fails when individual strategies are read as an infeasible or unsupported joint allocation, which is a failure of intervention definition, consistency or joint positivity rather than censoring on an impossible world. Estimands for cluster and population allocation programs exist (Hudgens and Halloran 2008; Tchetgen Tchetgen and VanderWeele 2012; Papadogeorgou 2019), and one application defines a target trial for spillover effects within provider clusters from routinely collected data (Buchanan 2022). Not found by any auditor: a statement of what the standard individual clone-censor-weight contrast identifies under partial interference, a proof or refutation of the entry's joint-realizability claim, and a cluster-level clone-censor-weight procedure with its positivity condition and finite-sample behavior. This design supplies those three, for one grace-period strategy and one family of cluster policies. Partitioned from PRO-05, which treats jurisdiction-level policies, treatment versions and cluster counts; here treatment is chosen by individuals inside clusters.

## Question

Under partial interference within clusters: (1) what does the individual clone-censor-weight contrast between "initiate within the grace period" and "never initiate" identify, and how far is it from the contrast between the cluster policies "every member initiates" and "no member initiates"; (2) are the worlds pooled in one individual arm jointly realizable by any single cluster allocation; (3) does cloning clusters rather than individuals identify cluster-policy effects with a grace period, and at what cluster counts and levels of cluster-level support is it calibrated?

**Left unanswered.** The choice of exposure mapping, network measurement error, interference between clusters, contagion versus homophily, and any policy defined over a network rather than disjoint clusters.

## Setting and assumptions

Clusters j = 1, ..., J of m members, all eligible at month 0; months k = 0, ..., 12; grace period of 3 months; initiation absorbing; Y_ij the outcome event by month 12. Partial interference: Y_ij depends on the treatment histories of cluster j only, so potential outcomes are Y_ij(a_j) for a cluster history a_j. Others' treatment may respond to i's (treatment contagion, or a shared capacity), so A_-ij(g) denotes the others' natural course when i follows g.

Individual strategies, emulated by cloning, artificial censoring and inverse probability weighting (Cain 2010; Hernán 2018): g_1, initiate within the grace period; g_0, never initiate. Cluster policies: h_1, every member initiates within the grace period; h_0, no member initiates; h_c, at least a fraction c of members initiate within the grace period, members chosen by the natural process. The policy effect is OE = E[Ybar_j(h_1)] − E[Ybar_j(h_0)], with Ybar_j the cluster-average risk.

## Claims

**C1, what individual cloning identifies.** With weights for each person's own adherence conditional on own history and the cluster's treatment history, and under sequential exchangeability for own adherence given those histories, positivity and consistency under partial interference, the individual contrast identifies

mu(g_1) − mu(g_0), with mu(g) = average over i of E[Y_ij(g_ij, A_-ij(g_ij))],

the unit-level effect of intervening on one person while the others follow their natural course. When the others' course does not depend on i's treatment, this is the direct effect at the natural allocation (Hudgens and Halloran 2008). OE − [mu(g_1) − mu(g_0)] = S_1 − S_0, where S_1 = E[Y_ij(1, all others treated)] − E[Y_ij(1, A_-ij(g_1))] and S_0 = E[Y_ij(0, no others treated)] − E[Y_ij(0, A_-ij(g_0))]: spillover terms that vanish only without outcome interference or when the natural course coincides with the policy. If the weight model omits the cluster history while others' treatment confounds own treatment and outcome, the contrast is biased for mu as well; the size of that bias is derived.

**C2, joint realizability.** Conjecture: the member-level outcome laws pooled in one individual arm are the member-level laws of a single cluster allocation law if and only if there is no outcome interference, or the others' natural course under g_1 already equals the allocation g_1 imposes on everyone. Proof by construction for m = 2 (member 1's clone lives in the world "1 treated, 2 natural", member 2's in "2 treated, 1 natural"; with interference no single allocation gives both marginals) and by induction for general m, with a capacity-constrained example in which the others' course depends on own treatment. The pooled contrast then remains a well-defined average of single-person interventions, which reconciles the entry with codex: the estimand exists and is realizable one person at a time; it is not the effect of any cluster policy. A counterexample to the "only if" direction refutes the entry's claim in this form.

**C3, cluster-level cloning.** Clone each cluster into the policy arms. A cluster clone in arm h is censored at the first month at which its realized initiations make h impossible (for h_1, at the end of the grace period if any member has not initiated; for h_0, at the first initiation; for h_c, at the end of the grace period if fewer than c m have initiated). Weights are inverse probabilities of remaining compatible given the cluster history. Claim: under cluster-level sequential exchangeability (the cluster's next initiation vector independent of cluster-average potential outcomes given cluster history), cluster-level positivity (the probability of remaining compatible is bounded away from zero) and consistency, the weighted mean of Ybar_j among compatible clusters identifies E[Ybar_j(h)]. The effective number of clusters is about J times the compatibility probability, and cluster-level positivity can fail while individual positivity holds: if members initiate independently with probability p within the grace period, compatibility with h_1 is p^m.

## How the results are checked

C1 and C2 by proof, each checked by exact enumeration for m = 2 and m = 3 with binary treatment and outcome, where every potential-outcome law is a finite table; C1's gap formula must hold to 1e-12 over 1,000 random tables.

C3 and the size of C1's gap by simulation.

- **Data-generating model.** m = 10. Cluster covariate W_j ~ N(0, 1), measured; cluster initiation propensity u_j ~ N(0, 2^2), unmeasured and unrelated to outcomes; individual covariate L_ij ~ N(0, 1). Monthly initiation hazard logit^(-1)(a_0 + u_j + 0.5 W_j + 0.5 L_ij + kappa x share of cluster already initiated), with kappa in {0, 1} (no treatment contagion, contagion). Monthly outcome hazard logit^(-1)(-5 + 0.4 W_j + 0.4 L_ij − 0.5 own treatment − 0.8 x share of cluster treated + b_j), b_j ~ N(0, 0.25). W_j confounds at the cluster level; the wide spread of u_j gives both "every member initiates" and "no member initiates" support. a_0 is set so that the probabilities of remaining compatible with h_1 and with h_0 are both close to q, for q in {0.30, 0.15, 0.08}; if one value cannot equalize both, the smaller of the two is set to q. The values are found by simulation before any replicate and recorded.
- **Grid.** J in {30, 100, 300} by kappa in {0, 1} by q in {0.30, 0.15, 0.08}: 18 scenarios. The expected number of compatible clusters per arm runs from 2.4 (J = 30, q = 0.08) to 90 (J = 300, q = 0.30).
- **Truth.** For each of the 6 combinations of kappa and q, E[Ybar_j(h)] for h_1, h_0 and h_0.5, and mu(g_1) and mu(g_0), from 10^5 clusters simulated under each intervention; Monte Carlo standard error below 0.0005.
- **Estimators.** Individual clone-censor-weight with pooled logistic adherence models including the cluster share treated, Hajek risks at month 12. Cluster clone-censor-weight with a pooled logistic compatibility model on cluster-month rows (covariates: W_j, cluster mean of L, share initiated, month), Hajek estimate of the cluster-average risk. Variance by stacked estimating equations over clusters (sandwich). Failure: fewer than 5 compatible clusters in an arm, or a nonfinite estimate or SE; the failure rate is reported and counts against calibration when above 5%.
- **Performance.** Bias against truth, empirical and model SE, coverage of the 95% Wald interval, failure rate; for the individual estimator, its distance from OE, compared with C1's gap formula evaluated at the true spillover terms.
- **Replicates.** 5,000 per scenario. A scenario is calibrated when its 95% Monte Carlo interval for bias lies within plus or minus 0.005 and its 95% Wilson interval for coverage lies within [0.93, 0.97]. At 5,000 replicates a single coverage check passes when observed coverage is between 0.9372 and 0.9652, and all 18 checks pass together with probability 0.9995 under exact calibration (exact binomial summation), so the window is reachable; a scenario whose true coverage is 0.93 fails with probability about 0.98. The bias MCSE is below 0.0003 for an empirical SE up to 0.02.

## What would show the problem real or not real

The entry makes two claims and they are decided separately.

- **Joint realizability.** *Supported*: C2 is proved, so the individual contrast is the average of single-person interventions and differs from OE by C1's spillover terms whenever there is outcome interference. *Refuted*: a counterexample shows a single allocation law realizing the pooled member laws under outcome interference.
- **Repair by cluster-level cloning.** The decisive cell is J = 100 with q = 0.15, about 15 compatible clusters per arm. *Real (not repairable at realistic cluster counts)*: cluster clone-censor-weight is not calibrated in that cell in either contagion setting. *Not real (repairable)*: it is calibrated in that cell in both contagion settings. One setting calibrated and the other not is reported as conditional on treatment contagion. The whole grid is reported as the smallest calibrated J at each q.
- **Uninformative.** The positive control fails: cluster clone-censor-weight is not calibrated at J = 300 with q = 0.30 and kappa = 0.

## Cost

Person-hours: C1 and C2 proofs and enumeration, 50; C3 identification, 30; simulation code and pilot, 40; write-up, 25; about 145. CPU, from assumed unit costs that a 20-replicate pilot per scenario must confirm: about 0.3 CPU-seconds per replicate averaged over J (both estimators and the sandwich; the largest cells have 36,000 person-months), so 18 x 5,000 x 0.3 s = 7.5 CPU-hours; truth, 6 settings x 5 interventions x 10^5 clusters x 120 person-months, vectorized, under 1 CPU-hour; pilot under 0.1. Total under 10 CPU-hours. No data access.

## Threats to validity

- One exposure structure (share of cluster treated) and disjoint clusters. Other mappings give other, equally valid, estimands; the result is conditional on this one.
- The data-generating model satisfies cluster-level exchangeability by construction, so C3's simulation checks estimation and positivity, not unmeasured cluster confounding.
- Initiation is absorbing; discontinuation, which adds a second source of incompatibility, is out of scope.
- The compatibility probabilities are chosen to span easy to hard support; they are not estimates from any application. The cluster propensity spread (standard deviation 2 on the logit scale) is what gives both cluster policies support at all; with homogeneous clusters, "no member initiates" and "every member initiates" cannot both be supported at m = 10.

## Citations

- Hudgens MG, Halloran ME. Toward causal inference with interference. Journal of the American Statistical Association. 2008;103:832-842. doi:10.1198/016214508000000292
- Tchetgen Tchetgen EJ, VanderWeele TJ. On causal inference in the presence of interference. Statistical Methods in Medical Research. 2012;21:55-75. doi:10.1177/0962280210386779
- Papadogeorgou G, Mealli F, Zigler CM. Causal inference with interfering units for cluster and population level treatment allocation programs. Biometrics. 2019;75:778-787. doi:10.1111/biom.13049
- Buchanan A, Sun T, Wu J, Aroke H, Bratberg J, Rich J, Kogut S, Hogan J. Toward evaluation of disseminated effects of medications for opioid use disorder within provider-based clusters using routinely-collected health data. Statistics in Medicine. 2022;41:3449-3465. doi:10.1002/sim.9427
- Hernán MA. How to estimate the effect of treatment duration on survival outcomes using observational data. BMJ. 2018:k182. doi:10.1136/bmj.k182
- Cain LE, Robins JM, Lanoy E, Logan R, Costagliola D, Hernán MA. When to start treatment? A systematic approach to the comparison of dynamic regimes using observational data. International Journal of Biostatistics. 2010;6. doi:10.2202/1557-4679.1212
