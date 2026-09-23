# UCF-02: when the joint identification region differs from a combination of one-at-a-time sensitivity analyses

**Catalog problem.** Sensitivity analyses vary one violated assumption at a time when several are violated together. Verdict `overstated`; triage: analytic, answerable in part, feasibility 2, scope applies.

**Residual claim this design tests.** The audit removed three parts of the entry. Joint multiple-bias theory and software exist: composite bounds for confounding, selection and misclassification on the risk-ratio scale (Smith 2021), simultaneous adjustment by imputation and weighting (Brendel 2023, implemented in the CRAN package `multibias`), and joint versus product sensitivity models for sequential unmeasured confounding in longitudinal studies (Tan 2025). Codex showed that a Bayesian posterior over unidentified bias parameters is prior-sensitive and is not an identification region, that unrestricted simultaneous violations give vacuous bounds, and that omitted bias does not always favor the claim. What survives, per grok and the counter-evidence of Gao (2025): nothing combines practical or structural positivity failure with confounding and misclassification for a sustained-strategy g-formula estimand, and it is not established when the shortcut that practice uses (reading one-at-a-time analyses side by side, or adding their worst-case shifts) under- or overstates the joint region. The entry asserts that the joint region "is typically not a product of the marginal regions" and that the convenient answer is "also the wrong one". This design sets out to prove when that is true, when it is false, and in which direction.

**Scope.** A correctly specified emulation still leaves several identifying assumptions in doubt at once (Hubbard 2024); the design fixes one estimand, a two-decision sustained-strategy risk difference, and asks what their joint failure does to it.

## Questions

**Q1.** For a sustained-strategy risk difference with bounded sequential confounding, nondifferential outcome misclassification, selection and structural nonpositivity, when does the joint identification region equal (a) the hull of the one-at-a-time regions, (b) their additive combination?

**Q2.** When they differ, is the error of each shortcut signed, and what determines the sign?

**Q3.** Which parameterization do the joint multiple-bias tools in current use adopt, and therefore which case applies to them?

**Q4.** Does a plug-in estimate of the joint region, with an Imbens-Manski interval, cover the joint identified set at nominal rates in samples of emulation size?

## What this leaves unanswered

The choice of bias-parameter ranges, which is substantive and cannot be settled analytically; dependence restrictions across periods beyond the box (independent ranges) and the per-history shift model used here; unmeasured confounding models other than the additive shift (for example the marginal sensitivity model); and whether journals should require joint regions, which is a policy question.

## Setting

Two decisions, binary `L_0`, `L_1` and `Y`; always-treat versus never-treat; estimand the risk difference `psi` in the eligible population. Four bias models, each with a box of parameters and a null value:

- **C, sequential confounding.** At each decision and each history, the counterfactual mean among those not following the strategy is shifted from that among followers by `d_t(h)`, with `|d_t(h)| <= delta`. Parameters for the two strategies are variation independent.
- **M, outcome misclassification.** Nondifferential sensitivity in `[Se_lo, 1]` and specificity in `[Sp_lo, 1]`; the true mean is `(p*-(1-Sp)) / (Se+Sp-1)`.
- **S, selection.** The analyzed cohort is a known fraction `s` of the target population; the counterfactual mean in the unselected part is shifted by at most `eta` from that in the selected part within each `L_0` stratum.
- **P, structural nonpositivity.** At listed histories no one follows the strategy; the counterfactual mean there lies in [0, 1].

The joint region is the image of the product of the boxes under the bias-corrected g-formula. The one-at-a-time region for a violation sets every other violation to its null value; for P the null value is the standard analysis's extrapolation from a main-effects outcome model. The hull is the smallest interval containing all one-at-a-time regions; the additive combination adds each one-at-a-time region's shifts from the reference estimate.

## Claims to be proved or refuted

- **P1 (the hull never overstates).** Each one-at-a-time region lies in the joint region, so the hull is contained in it, strictly when two violations move `psi`.
- **P2 (additive exactness).** If the corrected functional is additively separable in the violation-specific parameters over a product box, the additive combination equals the joint region.
- **P3 (absorption makes the additive combination conservative).** When one violation leaves another's parameters without effect on part of the functional, the additive combination double counts. Nonpositivity absorbs the confounding shift at unsupported histories, because everyone there is a non-follower; the overstatement equals `2 * delta` times the strategy-induced probability of reaching those histories.
- **P4 (rescaling makes it anti-conservative).** When misclassification rescales the functional by `1/J`, `J = Se+Sp-1`, and confounding shifts are specified on the observed-outcome scale, the joint endpoint lies beyond the additive one by the cross term `(C_end-psi_ref) * (1/J_lo-1)`. With shifts specified on the true-outcome scale, P2 applies and the combination is exact. The discrepancy is therefore a property of the bias parameterization, not of the violations.
- **P5 (non-nesting).** With three violations the additive interval can be neither inside nor outside the joint region.
- **P6 (the direction of the error is not fixed).** P3 and P4 together refute the entry's clause that the misstatement always favors the claim; this part of the entry was flagged by codex and is settled by exhibiting both signs.

Extremes are attained at vertices of the box: for fixed misclassification parameters the functional is linear in the shifts and in the unidentified means, and in the misclassification parameters it is linear-fractional, hence quasilinear, so a finite vertex enumeration computes the joint region exactly.

## Worked example (exact vertex enumeration)

`P(L_0 = 1) = 0.4`; `P(A_0 = 1 | L_0) = (0.3, 0.6)`; `P(L_1 = 1 | L_0, A_0)` equal to 0.2, 0.3, 0.5, 0.6 for (0,0), (0,1), (1,0), (1,1). Among always-treat histories, `P(A_1 = 1)` is 0.9, 0.6, 0.8 for `(L_0, L_1)` = (0,0), (0,1), (1,0) and 0 at (1,1), which is structurally unsupported; the observed outcome means among followers are 0.10, 0.20, 0.18, and the main-effects extrapolation to (1,1) is 0.28. Among never-treat histories `P(A_1 = 1)` is 0.1, 0.3, 0.2, 0.4 and follower outcome means 0.15, 0.28, 0.25, 0.40. Ranges: `delta = 0.03`, `Se` in [0.85, 1], `Sp` in [0.97, 1]. Reference estimate -0.062. One-at-a-time regions: C [-0.109, -0.014], M [-0.075, -0.062], P [-0.129, 0.111].

| Violations | Joint region (width) | Hull width | Additive combination (width) | Additive vs joint |
| --- | --- | --- | --- | --- |
| C and M, shifts on observed scale | [-0.133, -0.014] (0.119) | 0.095 | [-0.123, -0.014] (0.109) | understates by 0.010 |
| C and M, shifts on true scale | [-0.123, -0.014] (0.109) | 0.095 | [-0.123, -0.014] (0.109) | exact |
| C and P | [-0.169, 0.152] (0.321) | 0.240 | [-0.177, 0.159] (0.335) | overstates by 0.014 |
| M and P | [-0.152, 0.115] (0.266) | 0.240 | [-0.142, 0.111] (0.254) | understates by 0.013 |
| C, M and P, observed scale | [-0.199, 0.156] (0.356) | 0.240 | [-0.190, 0.159] (0.349) | not nested |

The C and P overstatement, 0.0144, equals `2 * 0.03 * 0.24`, where 0.24 is the always-treat probability of reaching the unsupported history, as P3 states. The C and M understatement, 0.0105, equals `0.048 * (1/0.82-1)`, as P4 states. The hull understates in every row. The table was produced by a 70-line enumeration run for this proposal; the study re-implements it independently as the known-answer test for Q4.

## Design

**Stage 1, proofs.** State and prove P1 to P6 for `K` decisions, finite covariate histories and the four bias models, then extend P3 to selection (which acts on a disjoint part of the population, like P) and P4 to exposure misclassification. Each proof is checked by a second statistician and by the enumeration on 200 randomly drawn observed laws and boxes: any draw violating a proved inequality is a counterexample and returns the claim to stage 1.

**Stage 2, classification of current tools (Q3).** Read the source of the CRAN packages `multibias` and `episensr` at pinned versions and the bound formula of Smith (2021), and record for each: the order in which corrections are applied, the scale on which each bias parameter is defined, whether bias parameters of different violations enter separably, and whether positivity is represented at all. Each record carries the file, line and a verbatim excerpt, and is checked against a known-answer input by running the tool once. The classification decides which of P2 to P4 governs each tool.

**Stage 3, coverage (Q4).** Observed law of the worked example; `n` in {2000, 10000}; the observed law estimated by cell frequencies; joint region by enumeration on the estimated law; 95% interval by Imbens-Manski with endpoint standard errors from 200 nonparametric bootstrap draws. 1000 replicates per `n` give a Monte Carlo standard error of 0.007 at coverage 0.95. Truth is the enumeration on the true law, without Monte Carlo error. Failure: a bootstrap draw with an empty follower cell is redrawn and counted.

## What would show the problem real or not real

- **Real**: P1 holds and at least one tool classified in stage 2 uses a parameterization under which P4 or P5 applies, so that combining its one-at-a-time output additively misstates the joint region in a direction the user cannot know without the joint computation.
- **Not real**: every tool examined parameterizes its biases separably (P2), no tool combines positivity with other biases, and P4 has no instance in practice; the additive shortcut is then exact wherever it is used, and the residual problem reduces to P1, reporting one-at-a-time regions without combining them, which the tools already solve.
- **Settled by the proofs whatever stage 2 finds**: P3 and P4 give the additive shortcut errors of both signs, which refutes the entry's "always favors the claim"; where both have practical instances, the joint computation cannot be replaced by a rule of thumb.
- **Uninformative**: a proof fails and the enumeration finds no counterexample, leaving the claim numerical only; or coverage at `n = 10000` is below 0.90, in which case the region can be computed but not yet estimated reliably.

## Cost

Person-hours: proofs 40, second-statistician check 12, stage 2 source reading and known-answer runs 15, stage 3 code and tests 15, write-up 20; about 100 in total. Compute: one joint-region enumeration (2 strategies, 64 shift vertices each, 8 misclassification and positivity vertices) took 7 ms of CPU in the scratch implementation on the shared machine. Stage 3 needs the joint region and three one-at-a-time regions for each of 2000 replicates times 201 fits (the estimate and 200 bootstrap draws): 402,000 fits, 1.6 million enumerations, about 3 CPU-hours; the budget is 10 CPU-hours to allow for a slower R implementation. The 200-law counterexample search in stage 1 is negligible.

## Threats to validity

The per-history additive shift is one confounding model among several; P4 in particular depends on where the shift is defined, which is the finding, but other models may interact differently and are not covered. The positivity null value, the main-effects extrapolation, is the reference the additive shortcut is measured against; a different reference changes the magnitude of P3's overstatement, not its sign. Box parameter spaces ignore dependence among violations, for example confounding and selection sharing a cause; dependence can only shrink the joint region and is reported as an explicit restriction when used. Stage 2 classifies tools, not how analysts use them.

## Citations

- Smith LH, Mathur MB, VanderWeele TJ. Multiple-bias Sensitivity Analysis Using Bounds. Epidemiology. 2021;32(5):625-634. doi:10.1097/EDE.0000000000001380
- Brendel P, Torres A, Arah OA. Simultaneous adjustment of uncontrolled confounding, selection bias and misclassification in multiple-bias modelling. International Journal of Epidemiology. 2023;52(4):1220-1230. doi:10.1093/ije/dyad001
- Tan Z. Sensitivity models and bounds under sequential unmeasured confounding in longitudinal studies. Biometrika. 2025;112(1):asae044 (online 2024). doi:10.1093/biomet/asae044
- Gao C, Zhang X, Yang S. Doubly robust omnibus sensitivity analysis of externally controlled trials with intercurrent events. Biometrics. 2025;81(2):ujaf047. doi:10.1093/biomtc/ujaf047
- Hubbard RA, Gatsonis CA, Hogan JW, Hunter DJ, Normand S-LT, Troxel AB. "Target Trial Emulation" for Observational Studies: Potential and Pitfalls. New England Journal of Medicine. 2024;391(21):1975-1977. doi:10.1056/NEJMp2407586. The catalog entry attributes this article to Hubbard and Hernán; CrossRef lists the six authors given here.
