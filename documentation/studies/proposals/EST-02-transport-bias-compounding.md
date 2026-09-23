# EST-02: how confounding and transport violations combine in a transported observational effect

**Catalog problem.** Transporting an observational estimate compounds sampling assumptions on top of confounding assumptions with no accounting. Verdict `partially-addressed`; triage: analytic, answerable in part, feasibility 1, not a target trial emulation problem.

**Bearing on target trial emulation.** An emulation estimated in one database and standardized to a decision population, as in post hoc population standardization within RCT-DUPLICATE (Htoo 2026), carries exactly this stack of treatment exchangeability in the source and effect exchangeability across populations.

**Residual claim this design tests.** The audit (codex) found the entry overstated: identification needs a sufficient transport set rather than every effect modifier, a scalar sensitivity parameter can represent an aggregate joint bias, and the inability to charge a discrepancy to one assumption is nonidentification rather than a missing report. What survives: no result states how the two violations combine in the transported estimate, whether varying one assumption at a time understates the joint uncertainty, or when correlated violations add and when they cancel. Transport methods themselves are established (Westreich 2017; Dahabreh 2020), as are bias-function sensitivity analyses for transport from a trial (Dahabreh 2023) and for confounding (VanderWeele and Ding 2017).

## Question

For a transported risk difference estimated from an observational source, (1) is the total bias uniquely attributable to the treatment-exchangeability violation and the sampling-exchangeability violation; (2) is the sharp joint bound under bounded violations of both the sum of the two one-at-a-time bounds, the larger of them, or something in between; (3) when both violations arise from one unmeasured variable, which configurations make them add and which make them cancel?

**Left unanswered.** Empirical plausibility of any bound in a given application, which needs subject-matter elicitation or external data. Identification: nothing here identifies either bias term from the source outcomes and target covariates. Reporting practice, which is a corpus question.

## Setting and assumptions

Point treatment A in {0, 1}, binary outcome Y at a fixed horizon, measured covariates X, one or two unmeasured variables U. Source population S (observational: A, X, Y observed) and target population T (X observed). The analyst transports the source conditional risk difference by standardizing over the target's X, for example with inverse odds of sampling weights, so the observed functional is

psi_hat = E_T[ tau_obs(X) ], with tau_obs(x) = E_S[Y | A = 1, x] − E_S[Y | A = 0, x].

The target estimand is psi_T = E_T[ tau_T(X) ], where tau_T(x) is the conditional causal risk difference in the target. Define the intermediate tau_S(x), the conditional causal risk difference in the source, and assume positivity for treatment in S and for sampling given X.

## Claims

**T1, decomposition.** psi_hat − psi_T = B_conf + B_trans exactly, with B_conf = E_T[tau_obs(X) − tau_S(X)], which is zero under conditional treatment exchangeability in the source, and B_trans = E_T[tau_S(X) − tau_T(X)], which is zero under conditional effect exchangeability across populations. The identity telescopes through the source causal effect standardized to target covariates, so it holds for any outcome model, and on the log scale for ratio measures of standardized risks. Attribution is therefore unique given that intermediate estimand; neither term is identified. A preliminary scratch check by exact enumeration with binary X and U found the residual B − B_conf − B_trans at most 8e-17 over 1,000 random parameter sets under an additive risk model, with B_conf and B_trans computed from the closed forms of T3 below; a companion run under a logistic outcome model confirms only the telescoping identity, which holds there by construction. If T1 holds as stated, the part of the entry that asks which assumption a discrepancy should be charged to is answered as "defined but not identified", which is the codex position.

**T2, variation-independent bias functions.** With bias functions b_c(x) = tau_obs(x) − tau_S(x) and b_t(x) = tau_S(x) − tau_T(x) bounded by |b_c| <= Gamma_c and |b_t| <= Gamma_t, and no restriction linking them, the sharp bound on psi_hat − psi_T is Gamma_c + Gamma_t. Either one-at-a-time analysis understates the joint half-width by the other's bound.

**T3, one shared unmeasured U.** Let the outcome model be additive in (A, U, A by U) with coefficients beta_U and beta_AU, let p_1(x) = P_S(U = 1 | A = 1, x), p_0(x) = P_S(U = 1 | A = 0, x), pi_S(x) = P_S(U = 1 | x) and pi_T(x) = P_T(U = 1 | x). Then

B_conf = E_T[ beta_U (p_1 − p_0) + beta_AU (p_1 − pi_S) ], B_trans = E_T[ beta_AU (pi_S − pi_T) ].

The coefficient beta_AU appears in both terms, so the violations are correlated through it; summing, pi_S cancels and the total bias is beta_U (p_1 − p_0) + beta_AU (p_1 − pi_T).

*Lemma, already settled in design.* Since p_1 − pi_S = (1 − e)(p_1 − p_0), with e the source treatment prevalence given x, under independent box bounds on (beta_U, beta_AU, p_1 − p_0, pi_T − pi_S) the shared coefficient can take the same sign in both terms and the sharp joint bound equals the sum of the one-at-a-time sharp bounds: the violations compound fully on this scale. Two further consequences are stated and checked, not tested: the effect-modification parts have the same sign, and add, when the target's U prevalence departs from the source in the direction opposite to the treated group's departure (pi_T < pi_S < p_1, or the reverse), and opposite signs otherwise; and when the target resembles the source's treated group (pi_T = p_1) they cancel and the bias reduces to beta_U (p_1 − p_0).

**T3', the same question on the scale analysts elicit.** Sensitivity parameters are usually elicited as odds ratios: U's association with treatment, U's log-odds effect on the outcome, a U by treatment interaction on the log-odds scale, and a shift in U prevalence. Under a logistic outcome model with bounds on those parameters, the baseline risk and the log-odds coefficients enter both terms, and their maximizers need not coincide, so the joint bound on the risk difference can fall anywhere between the larger one-at-a-time bound and their sum. Where it falls is not settled on paper and is the open question of this study. Define the compounding fraction phi = (joint bound − larger single bound) / (smaller single bound): phi = 1 is full compounding, as in the lemma, and phi = 0 is none.

**T4, what standard one-at-a-time tools omit.** A confounding sensitivity analysis without U by treatment interaction omits beta_AU (p_1 − pi_S); a transport sensitivity analysis that assumes no source confounding omits the whole of B_conf. The omitted share of the sharp joint bound is derived in closed form under T3 and evaluated over the region below.

## How the results are checked

- **Exact enumeration.** Binary X (two or three levels) and U, all quantities computed as finite sums, as in the preliminary check; T1, the closed forms in T3 and the lemma must match to 1e-12 over 10,000 random parameter sets.
- **Estimator check.** One source of 10^6 and one target of 10^6 simulated per configuration; the inverse odds of sampling weighted estimator with the correct X-only models must converge to psi_hat, and psi_hat − psi_T must equal the closed-form bias within Monte Carlo error (standard error below 0.001). Twenty configurations.
- **Sharp bounds.** For T2 and the lemma, the closed-form joint bound is compared with numerical maximization (multistart box-constrained optimization, 20 starts); disagreement above 1% is a failure of the derivation. For T3', the one-at-a-time and joint bounds are computed by the same optimizer on a grid of 500 points over the declared region's nuisance dimensions (baseline risk, treatment prevalence), and phi is reported at each point; convergence is checked by doubling the starts.
- **Declared region.** beta_U in [-0.10, 0.10] and beta_AU in [-0.05, 0.05] on the risk scale; p_1 − p_0 in [-0.3, 0.3]; pi_T − pi_S in [-0.3, 0.3]; baseline risks 0.05 to 0.40; source treatment prevalence 0.2 to 0.8. For T3', the bounds are log odds ratios of U on treatment and of U on the outcome in [0, 1.5], a U by treatment log-odds interaction in [-1, 1], source U prevalence 0.1 to 0.5 and a shift pi_T − pi_S in [-0.3, 0.3]; baseline risk and treatment prevalence are the grid dimensions.

## What would show the problem real or not real

The decision rests on T3', the only claim not settled in design. T1, T2 and the lemma are reported as results whichever branch holds.

- **Real (compounding on the elicited scale).** The median of phi over the declared region is at least 0.75. Two one-at-a-time analyses, each at its worst case, then understate the joint bound by most of the smaller one, and the report of a transported observational estimate needs the joint bound, which T2 and the lemma supply.
- **Not real.** The median of phi is at most 0.25. The shared parameters' conflicting maximizers then keep the joint bound close to the larger single bound, and reporting the worse of the two one-at-a-time analyses is nearly sufficient.
- **Intermediate.** A median between 0.25 and 0.75, reported with phi's distribution over the region.
- **Uninformative.** The optimizer does not converge: doubling the starts moves phi by more than 0.05 at more than 5% of grid points.

## Cost

Person-hours: derivations 40; enumeration and simulation code 20; bound optimization 15; write-up 25; about 100 in total. CPU: the estimator check is 20 configurations of 2 x 10^6 records at under 1 CPU-second each; T3' is 500 grid points by 3 bounds by 40 starts of an optimizer over closed-form enumeration, about 10^7 function evaluations at microseconds each; under 1 CPU-hour. No data access.

## Threats to validity

- The additive model makes T1 through T3 and the lemma clean. T1 does not depend on it; T3' is numerical only.
- A single binary U is the simplest correlated structure. Two unmeasured variables, one confounding and one modifying, give variation-independent terms and fall under T2; intermediate structures are not covered.
- The declared region is a convention. The closed forms are reported so that any region can be substituted.
- Nothing here makes either term estimable. The contribution is how bounds combine, not how large they are in a given study.

## Citations

- Htoo PT, Patorno E, Schneeweiss S, Wang SV. Post hoc population standardization of trial emulation studies in claims data: an RCT-DUPLICATE analysis. Clinical Pharmacology and Therapeutics. 2026;119:1362-1370. doi:10.1002/cpt.70241
- Westreich D, Edwards JK, Lesko CR, Stuart E, Cole SR. Transportability of trial results using inverse odds of sampling weights. American Journal of Epidemiology. 2017;186:1010-1014. doi:10.1093/aje/kwx164
- Dahabreh IJ, Robertson SE, Steingrimsson JA, Stuart EA, Hernán MA. Extending inferences from a randomized trial to a new target population. Statistics in Medicine. 2020;39:1999-2014. doi:10.1002/sim.8426
- Dahabreh IJ, Robins JM, Haneuse SJA, Saeed I, et al. Sensitivity analysis using bias functions for studies extending inferences from a randomized trial to a target population. Statistics in Medicine. 2023;42:2029-2043. doi:10.1002/sim.9550
- VanderWeele TJ, Ding P. Sensitivity analysis in observational research: introducing the E-value. Annals of Internal Medicine. 2017;167:268-274. doi:10.7326/M16-2607
- Manke-Reimers F, Brugger V, Bärnighausen T, Kohler S. When, why and how are estimated effects transported between populations? A scoping review of studies applying transportability methods. European Journal of Epidemiology. 2025;40:255-273. doi:10.1007/s10654-025-01217-w
