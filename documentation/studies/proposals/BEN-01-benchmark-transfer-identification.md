# BEN-01: when benchmark agreement licenses a claim about a new question, and when it cannot

**Catalog problem.** There is no theory for extrapolating successful replication of selected trials to new questions. Verdict `overstated`; triage: analytic, answerable in part, feasibility 3.

**Residual claim this design tests.** Codex's restatement, which the adjudication adopted: a successful replication identifies calibration only for the evaluated trial, protocol and database; quantitative transfer to another question or database requires a prespecified target performance estimand, an explicit selection or transport model, conditional exchangeability and overlap in the relevant modifiers, and outside that support transfer is model-dependent rather than identified. Grok found partial frameworks: BenchExCal calibrates a second-stage emulation by the discrepancy observed in a benchmarked first stage and states its assumption that "the net effect of the design differences and bias is similar for the stage 1 completed RCT‐database pair and the stage 2 hypothetical RCT‐database pair" (Wang 2025); trial calibration makes the same move (Kirchgesner 2024); agreement has been modeled as a function of design differences (Heyard 2024) and of emulation closeness across 107 pairs (Wang C 2026, with a published correction); and prospective prediction of a pending trial has been done (Mahesri 2026). Benchmarking an analysis before using it for a question trials do not answer has been proposed and applied (Matthews 2022), and the selection-diagram theory of transportability (Pearl and Bareinboim 2014) supplies the conditional-independence language used below. None states the transfer estimand, proves its identification conditions, or bounds it when they fail. That is what this design does, with a worked example on published benchmark results.

## Question

Define the error of an emulation for a new question in a stated design class. Under what conditions is its mean, and its predictive distribution, identified from a set of benchmarked pairs; what is the identified set when the benchmarked questions were selected on anticipated agreement; and, on the published RCT-DUPLICATE results, how wide is the resulting interval for a new question as the selection sensitivity grows?

**Left unanswered.** Which of the six causes the entry lists produced any single discrepancy, which needs the trial's own adherence and measurement data. Whether any particular new question lies inside the support of a benchmark program, which is a judgment the theory makes explicit but cannot make. Prospective blinded benchmarking itself, which is a program, not a study.

## Setting and assumptions

A population of candidate question-database pairs q with design features W_q (database, clinical area, outcome type, comparator type, protocol-match rating). For each, theta_T,q is the effect the trial's protocol targets and theta_E,q the probability limit of the emulation; the emulation error is b_q = theta_E,q − theta_T,q on the log hazard ratio scale. For benchmarked pairs (S_q = 1) the observed discrepancy is d_q = b_q + e_q with e_q normal, mean zero and known variance v_q (the sum of both estimates' squared standard errors). The transfer estimand for design class w is the predictive distribution of b_q among unbenchmarked pairs, with mean m_0(w) = E[b | W = w, S = 0] and spread tau_0^2(w).

## Claims

**B1, identification.** m_0(w) = E[d | W = w, S = 1] and tau_0^2(w) = Var(d | W = w, S = 1) − E[v | W = w, S = 1] if (i) benchmark-selection exchangeability, S independent of b given W; (ii) positivity, P(S = 1 | W = w) > 0; (iii) no selective reporting of benchmarked estimates given W, so that e has mean zero among published pairs. Condition (i) is BenchExCal's stated assumption written as a conditional independence; the theorem makes its scope explicit. Proof: iterated expectations and deconvolution of a normal location mixture.

**B2, nonidentification.** Without (i), construct two benchmark processes with the same law of (W, d, v) among benchmarked pairs and the same P(S = 1 | W) but different m_0(w); the construction lets selection depend on b through anticipated agreement. Without (ii), any m_0(w) is compatible with the data. Without (iii), a model in which emulation protocols are revised after the trial result until |d| falls below a tolerance shrinks the observed discrepancy distribution; derive the shrinkage for a single revision round with a declared tolerance.

**B3, bounds under bounded selection.** If the odds of benchmarking a pair given (W, b) differ from those given W alone by a factor of at most Gamma (a marginal sensitivity model in the direction of favoring small |b|), derive the sharp bounds on m_0(w) and on the 95% predictive interval for b, as functions of the benchmarked distribution of d and Gamma. At Gamma = 1 the bounds reduce to B1.

**B4, hierarchical extrapolation.** A hierarchical model that conditions on W extrapolates into cells with P(S = 1 | W = w) = 0 only through its parametric form; show the identified set for such a cell is unbounded without that form, so the model's interval there is an assumption, not an estimate.

## How the results are checked

**Proofs** of B1 to B4, with B2's construction verified numerically: two explicit parameter sets whose benchmarked distributions agree to 1e-10 in every moment used by the estimators, with different m_0.

**Simulation of B3.** A population of 10^5 synthetic questions with b ~ N(mu, tau^2) and selection by the marginal sensitivity model at Gamma in {1, 1.25, 1.5, 2}; benchmark sets of 32 and 107 pairs with v drawn from the empirical distribution in the worked example. The B3 bounds must contain the true m_0 in at least 95% of 2,000 benchmark-set draws at every Gamma, and be sharp in the sense that the true m_0 attains the bound in the extreme selection model.

**Worked example.** The 32 trial-emulation pairs reported by the RCT-DUPLICATE program (Wang 2023), extracted as the published trial and emulation hazard ratios with 95% intervals, dual extraction with discrepancies resolved against the source; a sensitivity analysis uses the 107 pairs of the concordance meta-analysis, taking every figure from its corrected version (Wang C 2026 and its correction). Random-effects meta-analysis of d with REML gives the benchmark distribution; B1 then gives the transfer interval at Gamma = 1 and B3 at Gamma = 1.25, 1.5 and 2, all expressed as ratios of hazard ratios. Design class w: all pairs pooled, and closer versus less close emulation where the source provides that rating.

## What would show the problem real or not real

The equivalence region for a new question's ratio of hazard ratios is [0.80, 1.25]; [0.67, 1.50] is reported as a sensitivity region. Each criterion is evaluated separately in the 32-pair and the 107-pair data sets, with predictive intervals that carry the uncertainty in the between-pair variance (parametric bootstrap of the REML fit, 10,000 draws), so a between-pair variance that is poorly estimated widens the interval instead of being treated as known.

- **Real.** In both data sets, the 95% predictive interval for a new question's error in the pooled class extends outside [0.80, 1.25] at Gamma = 1, or its B3 bound does at Gamma = 1.25. Benchmark success then licenses no equivalence claim about a new question even under exchangeability, or only under selection assumptions no benchmark program can check, and the entry's claim holds in codex's restated form.
- **Not real.** In both data sets, the B3 bound at Gamma = 1.5 lies inside [0.80, 1.25]. B1 is then a transfer theory that the existing benchmark corpus supports within its support, and the entry's "no theory" becomes "a theory with stated conditions and a measured tolerance to selection".
- **Intermediate.** Inside the region at Gamma = 1.25 but outside at 1.5: transfer tolerates mild but not moderate selection. Reported as such.
- **Uninformative.** The two data sets reach different branches.
- If B1's proof fails, the problem is real in its strongest form, and B3 and the worked example are not interpreted.

## Cost

Person-hours: B1 to B4 proofs, 60; simulation, 20; extraction of 32 pairs by two people, 10, and of the 107 pairs with the correction, 25; meta-analysis and bounds, 15; write-up, 25; about 155. CPU: 4 Gamma values by 2 set sizes by 2,000 draws, each a closed-form bound and one REML fit, plus 2 x 10,000 bootstrap REML fits for the worked example's predictive intervals; at an assumed 0.05 CPU-seconds per fit, about 0.5 CPU-hours. Data: published tables and supplements only.

## Threats to validity

- The log hazard ratio scale and a normal error model are conventions of the benchmarking literature; B1 and B2 hold on any scale, but B3's numbers are scale-specific.
- The published pairs mix emulations designed before and after the trial result; condition (iii) is plausibly violated in the second group, and the worked example reports the two groups separately where the source identifies them.
- A marginal sensitivity model is one way to bound selection. It is chosen because Gamma has a direct reading as an odds ratio of being benchmarked; other models give other bounds.
- The worked example is illustrative of the theory's use, not an estimate of emulation accuracy in general; it inherits whatever selection produced the 32 pairs, which is the point of B3.

## Citations

- Wang SV, Schneeweiss S, RCT-DUPLICATE Initiative, Franklin JM, Desai RJ, et al. Emulation of randomized clinical trials with nonrandomized database analyses. JAMA. 2023;329:1376. doi:10.1001/jama.2023.4221
- Wang C, Tang D, von Dadelszen P, Ju C, Liu L, Wang Y, Magee LA. Concordance between target trial emulation and randomised controlled trials: systematic review and meta-analysis. BMJ. 2026;393:e086810. doi:10.1136/bmj-2025-086810
- Concordance between target trial emulation and randomised controlled trials: systematic review and meta-analysis [correction]. BMJ. 2026;394:e100303. doi:10.1136/bmj-2026-100303
- Heyard R, Held L, Schneeweiss S, Wang SV. Design differences and variation in results between randomised trials and non-randomised emulations: meta-analysis of RCT-DUPLICATE data. BMJ Medicine. 2024;3:e000709. doi:10.1136/bmjmed-2023-000709
- Wang SV, Russo M, Glynn RJ, Bradley MC, He J, Concato J, Schneeweiss S. A Benchmark, Expand, and Calibration (BenchExCal) trial emulation approach for using real-world evidence to support indication expansions: design and process for a planned empirical evaluation. Clinical Pharmacology and Therapeutics. 2025;117:1820-1828. doi:10.1002/cpt.3621
- Kirchgesner J, Wang SV, Schneeweiss S. Strengthening real-world evidence on question not answered by randomized trials: a trial calibration approach. Pharmacoepidemiology and Drug Safety. 2024;33:e70008. doi:10.1002/pds.70008
- Mahesri M, Schneeweiss S, Lin KJ, Zabotka L, Concato J, Bradley MC, Wang SV. Bleeding risk with apixaban versus rivaroxaban: a reference trial emulation predicting the results of COBRRA-VTE and COBRRA-AF using US health care claims. Circulation: Population Health and Outcomes. 2026;19. doi:10.1161/circoutcomes.125.012892
- Matthews AA, Dahabreh IJ, Fröbert O, Lindahl B, James S, Feychting M, Jernberg T, Berglund A, et al. Benchmarking observational analyses before using them to address questions trials do not answer: an application to coronary thrombus aspiration. American Journal of Epidemiology. 2022;191:1652-1665. doi:10.1093/aje/kwac098
- Pearl J, Bareinboim E. External validity: from do-calculus to transportability across populations. Statistical Science. 2014;29. doi:10.1214/14-STS486
