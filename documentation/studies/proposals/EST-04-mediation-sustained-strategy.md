# EST-04: an interventional indirect effect for a sustained strategy emulated by cloning

**Catalog problem.** No mediated effect is defined for a sustained treatment strategy, and emulations report a proportion mediated anyway. Verdict `partially-addressed`; triage: analytic, answerable in part, feasibility 2.

**Residual claim this design tests.** The audit narrowed the entry in two directions. Codex: fixed longitudinal exposure histories are static sustained strategies, and the mediational g-formula already defines and identifies direct and indirect effects for them (VanderWeele and Tchetgen Tchetgen 2017; Tai 2023); cloning and artificial censoring are estimation devices, and a censoring model that conditions on mediator history corrects selection without conditioning the contrast on the mediator. What remains, in codex's words, is the case where grace-period or dynamic strategies interact with the mediator. The literature auditor added a third estimand family the entry omits: separable effects, which decompose the treatment rather than intervene on the mediator (Didelez 2019; Stensrud 2021). Undisputed: a proportion mediated computed from hazard or subdistribution hazard ratios, as in two 2026 emulations (Eun 2026; Jang 2026), is not a ratio of counterfactual risk contrasts, and randomized interventional indirect effects fail the sharp mediational null (Miles 2023). This design proves or refutes codex's position for the static case and settles the two cases codex leaves open.

## Question

For two sustained strategies emulated by cloning and artificial censoring, with a mediator measured once at a prespecified time and 24-month risk as the outcome: (1) is the interventional indirect effect identified by the inverse-probability-of-censoring weighted mediational g-formula when the censoring model includes the mediator; (2) is it still defined and identified when the grace period extends past the mediator's measurement time, or when the strategy's deviation rule reads the mediator; (3) how far is the hazard-scale proportion mediated from the risk-scale ratio of the indirect to the overall effect?

**Left unanswered.** Repeated mediators, mediators observed only at care visits (the informative-observation part of the entry, which MIS-01 addresses for covariates), sequential emulations in which one person enters many trials, competing events, and any mechanistic reading of a nonzero interventional effect. No proportion mediated is endorsed.

## Setting and assumptions

Monthly time k = 0, ..., 24. Eligibility and baseline covariates L_0 at k = 0. Strategy g_1: initiate treatment by the end of a grace period of m months and continue through month 24. Strategy g_0: do not initiate through month 24. Time-varying covariates L_k, a mediator M measured for everyone alive and uncensored at month t_M = 6, and Y, the indicator of the outcome event by month 24. Each person is cloned into both arms at k = 0 and a clone is censored when its observed treatment first becomes incompatible with its arm.

For strategies g and g', let G_{g'} be a random draw from the distribution of the mediator under g' given L_0, and Q(g, g') = P(Y^{g, G_{g'}} = 1), the risk under strategy g with the mediator set at month t_M to that draw. Then

IIE = Q(g_1, g_1) − Q(g_1, g_0), IDE = Q(g_1, g_0) − Q(g_0, g_0),

and their sum, the overall effect, differs from the total effect P(Y^{g_1} = 1) − P(Y^{g_0} = 1) whenever a post-treatment confounder of the mediator and the outcome exists (VanderWeele, Vansteelandt and Robins 2014). Assumptions: consistency; sequential exchangeability for treatment, and hence for artificial censoring, given the history of L, M and treatment; exchangeability for the mediator given L_0, the history of L to t_M and treatment; positivity for remaining compatible given history; no competing events.

## Claims

**E1, static strategies with the grace period ending before t_M (m < 6).** Q(g, g') is identified by a two-part weighted g-formula: the mediator law under g' from clones compatible with g' through t_M, weighted by the inverse probability of remaining compatible given history before t_M; the outcome law under g from clones compatible with g through month 24, weighted by the inverse probability of remaining compatible given history including M and post-t_M covariates; the mediator node is then replaced by an independent draw from the first law given L_0. The proof is the longitudinal mediational g-formula (VanderWeele and Tchetgen Tchetgen 2017) specialized to static regimes, with the censoring weights justified by sequential exchangeability. If E1 holds, codex is right for the static case: conditioning the weight model on M corrects selection and does not condition the contrast.

**E2, grace period extending past t_M (m >= 6).** Under g_1 with such a grace period, clones compatible with g_1 at month 6 include people who have not yet initiated, so the mediator law under g_1 is a mixture over initiation times whose weights are the natural initiation hazard among compatible clones. Claim: Q(g_1, g_1) and the IIE are then effects of the stochastic regime defined by the observed initiation hazard, not of "initiating", and they change with the grace period length at fixed outcome and mediator models. To be shown: the IIE as a function of m for m from 2 to 9 in the verification model, and a pair of data-generating laws with identical g_1-compatible outcome risk but different IIE.

**E3, deviation rule reading M.** If g_1 is "continue, and intensify when M >= c" (a dynamic strategy), then setting the mediator to a draw G raises a question the protocol must answer: does the rule read G or the value M would have taken under g_1? The first gives Q_a(g_1, g') identified by the E1 formula with the rule applied to the draw; the second requires the joint law of the natural and the drawn mediator, a cross-world quantity. Claim: Q_a and Q_b differ whenever the rule's threshold is crossed with positive probability, and coincide when the strategy is static after t_M. The IIE is not defined until the protocol fixes which M the rule reads.

**E4, sharp null within this design.** Construct two latent types: in one, treatment shifts M and M does not affect Y; in the other, treatment does not shift M and M affects Y. No individual has a mediated effect; the interventional draw mixes the types' mediator laws and produces a nonzero IIE. The construction instantiates Miles (2023) inside the cloned design and reports its size on the 24-month risk scale.

**E5, hazard-scale proportion mediated.** In the verification model, compare the proportion mediated from the difference of Cox coefficients with and without M (the method used in the applied emulations) with IIE divided by the overall effect on the risk scale, across the scenarios below.

**E6, separable effects.** State, for the same design, the separable-effects estimand (treatment decomposed into a component acting through M and a component not acting through it) and its dismissible-component conditions following Stensrud (2021), and list which conditions replace the mediator exchangeability of E1. Statement only; no derivation beyond the existing theory.

## How the results are checked

**Model.** L_k binary (monthly, affected by past treatment), M continuous at month 6 (mean shifted by treatment duration by then), a discrete-time outcome hazard depending on L, current treatment and M. Treatment initiation hazard depends on L; discontinuation after month 6 depends on M in E3 and in the "M triggers deviation" arm of E1. Six scenarios: E1 with and without M-triggered discontinuation; E2 with m = 3, 6 and 9; E3 with an intensification threshold at the 70th percentile of M.

**Truth.** Q(g, g') computed by simulating 10^6 counterfactual individuals under each regime and draw, with the draw taken from a separately simulated 10^6 under g' matched on L_0. Monte Carlo standard error below 0.0005 on each risk.

**Estimator.** Pooled logistic models for initiation, discontinuation, L_k, M and the outcome hazard, correctly specified; the weighted g-formula of E1 evaluated by Monte Carlo integration over 10 draws per person. n = 5,000 per replicate.

**Performance and replicate count.** 500 replicates per scenario. With an empirical SE of about 0.01 for the IIE at n = 5,000 (to be measured in a 50-replicate pilot), the MCSE of bias is about 0.00045, enough to separate a bias of 0.002 from 0.005. Coverage is checked in the two E1 scenarios only, 250 replicates each with a 200-resample nonparametric bootstrap. At 250 replicates a 95% Wilson interval has half-width about 0.027, so a test requiring it to lie inside [0.93, 0.97] could not pass even under exact calibration (at 500 replicates it passes with probability 0.08, by exact binomial summation). Coverage is therefore reported with its interval and carries no decision.

**Positive control.** E1 without M-triggered discontinuation is the textbook case. Bias outside plus or minus 0.002 there means the implementation or the truth is wrong, and nothing else is interpreted.

## What would show the problem real or not real

The dependence of the IIE on the grace-period length (E2) and on which mediator the rule reads (E3) follows from the constructions themselves and is reported as a finding; it does not decide, because codex's position is that a fully written strategy component already fixes both choices. The decision rests on whether the existing estimator, applied as it would be for a static strategy, recovers the IIE of the strategy as stated.

- **Real.** E1 holds, and in at least one E2 or E3 scenario the weighted g-formula applied as for a static strategy (mediator law from compatible clones at month 6, rule applied to the drawn mediator, no adjustment for pending initiation) is biased by 0.005 or more on the 24-month risk scale against the IIE of the stated strategy, with a 95% Monte Carlo interval excluding zero. Emulations that append the standard mediational g-formula to a clone-censor-weight analysis then report the wrong quantity whenever the grace period covers the mediator's measurement time or the deviation rule reads the mediator, and the correction is the E2 or E3 formula.
- **Not real.** The same estimator is within plus or minus 0.002 of the stated strategy's IIE in every E2 and E3 scenario. The entry's gap is then a corollary of existing longitudinal theory, as codex argued, and what remains is the hazard-scale reporting error of E5.
- **Intermediate.** A bias between 0.002 and 0.005 in some scenario and none at 0.005 or above, reported by scenario.
- **Uninformative.** The positive control fails.
- E4 and E5 are reported as findings whichever branch holds.

## Cost

Person-hours: identification results E1 to E3, 80; E4 and E6, 20; simulation code and pilot, 40; write-up, 30; about 170 in total. CPU, from assumed unit costs that the 50-replicate pilot must confirm before any performance replicate is drawn: at 3 CPU-seconds per weighted g-formula fit at n = 5,000, the bias checks cost 6 x 500 x 3 s = 2.5 CPU-hours; the bootstrap check, at 0.5 s per resample (refitting the models and reusing the Monte Carlo draws), costs 2 x 250 x 200 x 0.5 s = 13.9 CPU-hours; truth for 6 scenarios, about 4 regimes each and 2 x 10^6 simulated people per regime is vectorized and under 1 CPU-hour. Total about 17 CPU-hours. If the pilot's unit costs are higher, the bootstrap replicate count is cut first, since coverage carries no decision. No data access.

## Threats to validity

- One mediator at one fixed time is the tractable case. Repeated or visit-driven mediators are the harder half of the entry and are outside scope.
- Correct parametric models make the verification a check of identification, not of robustness to misspecification.
- The interventional estimand is chosen because it is identified from a single world; its failure of the sharp null (E4) means a nonzero IIE is not evidence of mechanism, and the report says so beside every number.
- The applied examples use hazard or subdistribution hazard scales with competing risks; E5 omits competing events, so it shows the scale mismatch, not its size in those studies.

## Citations

- VanderWeele TJ, Tchetgen Tchetgen EJ. Mediation analysis with time varying exposures and mediators. Journal of the Royal Statistical Society Series B: Statistical Methodology. 2017;79:917-938. doi:10.1111/rssb.12194
- VanderWeele TJ, Vansteelandt S, Robins JM. Effect decomposition in the presence of an exposure-induced mediator-outcome confounder. Epidemiology. 2014;25:300-306. doi:10.1097/EDE.0000000000000034
- Vansteelandt S, Daniel RM. Interventional effects for mediation analysis with multiple mediators. Epidemiology. 2017;28:258-265. doi:10.1097/EDE.0000000000000596
- Miles CH. On the causal interpretation of randomised interventional indirect effects. Journal of the Royal Statistical Society Series B: Statistical Methodology. 2023;85:1154-1172. doi:10.1093/jrsssb/qkad066
- Tai AS, Lin SH, Chu YC, Yu T, Puhan MA, VanderWeele T. Causal mediation analysis with multiple time-varying mediators. Epidemiology. 2023;34:8-19. doi:10.1097/EDE.0000000000001555
- Didelez V. Defining causal mediation with a longitudinal mediator and a survival outcome. Lifetime Data Analysis. 2019;25:593-610. doi:10.1007/s10985-018-9449-0
- Stensrud MJ, Hernán MA, Tchetgen Tchetgen EJ, Robins JM, Didelez V, Young JG. A generalized theory of separable effects in competing event settings. Lifetime Data Analysis. 2021;27:588-631. doi:10.1007/s10985-021-09530-8
- Moreno-Betancur M, Moran P, Becker D, Patton GC, Carlin JB. Mediation effects that emulate a target randomised trial: simulation-based evaluation of ill-defined interventions on multiple mediators. Statistical Methods in Medical Research. 2021;30:1395-1412. doi:10.1177/0962280221998409
- Hernán MA. How to estimate the effect of treatment duration on survival outcomes using observational data. BMJ. 2018:k182. doi:10.1136/bmj.k182
- Eun Y, Bong S, Koh HY, Trousdale RK, Cho YM, Jang Y, Lee ST. Semaglutide and risk of adult-onset seizure. Neurology. 2026;107:e218174. doi:10.1212/WNL.0000000000218174
- Jang H, Kim Y, Lim YK, Lee DH, Joo SK, Koo BK, Kim GA, Lee W, et al. Outcomes of oral antidiabetic drugs in metabolic dysfunction-associated steatotic liver disease: a nationwide target trial emulation study. Clinical and Molecular Hepatology. 2026;32:737-750. doi:10.3350/cmh.2025.1006
