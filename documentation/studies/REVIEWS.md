# Peer review of the study designs

17 designs reviewed by gpt-5.6-sol at max reasoning effort, each in a fresh context that saw the catalog entry and the proposed design and nothing else.

The reviewer is told the design was written by someone competent who wants a particular conclusion, because that is the situation, and it is asked to find what is wrong rather than to improve the presentation. Design and review come from the same model, which is weaker than two models and much stronger than none.

A finding is not advisory. It goes into the protocol as a design decision or as a declared limitation, and the protocol names which.

| # | problem | verdict | critical | major | minor | citation problems |
|---|---|---|---:|---:|---:|---:|
| 1 | BEN-02 | unsound | 0 | 0 | 1 | 4 |
| 2 | CNF-01 | unsound | 0 | 0 | 2 | 2 |
| 3 | DTA-02 | unsound | 0 | 0 | 2 | 1 |
| 4 | ELG-01 | unsound | 0 | 0 | 2 | 2 |
| 5 | ELG-02 | unsound | 0 | 0 | 0 | 5 |
| 6 | GMT-01 | unsound | 0 | 0 | 0 | 2 |
| 7 | GMT-03 | unsound | 0 | 0 | 2 | 4 |
| 8 | GMT-04 | unsound | 0 | 0 | 2 | 5 |
| 9 | LRN-01 | unsound | 0 | 0 | 3 | 1 |
| 10 | LRN-05 | needs-revision | 0 | 0 | 2 | 2 |
| 11 | MER-01 | unsound | 0 | 0 | 3 | 0 |
| 12 | MIS-01 | needs-revision | 0 | 0 | 0 | 2 |
| 13 | OUT-01 | unsound | 0 | 0 | 3 | 2 |
| 14 | PRO-02 | unsound | 0 | 0 | 1 | 2 |
| 15 | PRO-04 | unsound | 0 | 0 | 3 | 3 |
| 16 | SEQ-01 | unsound | 0 | 0 | 2 | 3 |
| 17 | TZO-01 | unsound | 0 | 0 | 3 | 3 |

---

## 1. BEN-02

**Verdict.** unsound

The protocol is unsound as a study intended to settle BEN-02. It studies a narrower pair-level equivalence-testing problem, while the surviving open problem concerns estimand alignment, joint uncertainty, and calibration across benchmark portfolios after graded metrics already exist. The main verdict and the apparent success of the tolerance rule are largely predetermined by the chosen discrepancies, precision span, ideal model specification, and nominal Wald procedures. The marginal estimand calculations, independence-based variance formulas, Monte Carlo standard-error arithmetic, and workload count are otherwise mostly sound.

**[FATAL] answers-problem**

The study answers the operating-characteristic question for selected pair-level rules under a known absolute-risk tolerance. BEN-02 asks how to compare sufficiently aligned estimands without conflating estimand mismatch and random error; its adjudication also establishes that continuous and graded metrics already exist. The design omits those existing graded methods, between-pair heterogeneity, prediction calibration, measurement mismatch, database calibration, and prospective forecasting. Its own bears_on statement correctly concedes that it answers only part of the problem.

*Fix:* Either relabel the study as a narrow demonstration that cannot settle BEN-02, or add a portfolio-level design comparing existing graded methods under multiple alignment and mismatch mechanisms, with joint uncertainty, heterogeneity, and externally specified decision losses.

**[SERIOUS] answers-problem**

The simulated positive and negative controls are DGM checks, not the positive and negative controls requested by the open problem. Removing effect modification or setting a large known discrepancy verifies code behavior; it does not calibrate residual bias or data-source performance alongside a trial comparison.

*Fix:* Do not claim that these scenarios implement the proposed control strategy. A study of that strategy needs realistic control questions whose known effects can reveal bias across databases and clinical questions.

**[FATAL] dgm-builds-in-finding**

Nearly every headline result is encoded. The A by Z coefficient of 0.16, or the logistic interaction of 1.00, is combined with qE values solved specifically to produce the requested risk-difference discrepancies. Sample size then increases fiftyfold at fixed nonzero discrepancy, which necessarily changes overlap and point-null decisions as their standard errors shrink. The exact-null stratum makes independent estimated signs disagree about half the time asymptotically; psiT equal to zero or approximately 0.00013 guarantees ratio instability. Known Z, shared outcome models, correct nuisance models, and known population weights guarantee that transport removes the discrepancy. Finally, the 90% tolerance interval gives approximately 5% one-sided boundary errors by construction, while the correctly specified estimators are designed to attain the required 95% coverage.

*Fix:* Treat these scenarios as implementation checks and derive their expected behavior analytically. Evidence about competing methods requires DGMs not calibrated on the proposed method's preferred scale, varied baseline risks and mismatch mechanisms, imperfect alignment information, and sample-size choices made independently of the desired decision thresholds.

**[SERIOUS] estimand**

The causal estimands and their algebraic superpopulation truths are correctly defined, but the performance truth assigned to the comparator rules is not generally their estimand. Direction agreement answers whether estimated signs match, not whether two marginal risk differences differ by less than 0.02. At delta equal to 0 with both effects null, there is no true positive or negative direction, yet opposite random signs are labeled a false conclusion. Conversely, two effects can have the same true direction and differ by 0.04; the protocol then calls a correct directional statement false reassurance. Failure to reject delta equal to zero also is not an affirmative statement that the tolerance criterion holds.

*Fix:* Define the common decision each method is alleged to answer and evaluate false conclusions only for methods that claim to answer it. Otherwise report each rule's operating characteristic without converting it into error against an unrelated tolerance truth.

**[SERIOUS] fair-comparison**

The proposed method may return indeterminate, whereas every comparator is forced into agreement or disagreement. Its false-definitive error will therefore be lower partly because it can abstain. Reporting decisiveness only for delta equal to zero and 0.04 at the highest precision does not establish a fair risk comparison across the remaining scenarios. The design also omits the cited sceptical p-value and other existing graded procedures, so it compares the proposal mainly with the practices already selected for failure.

*Fix:* Compare methods under a common loss function that prices indeterminate decisions, or report error versus decision-rate curves throughout the grid. Include the actual graded alternatives identified in the literature and apply their published interpretations.

**[FATAL] decision-rule**

The real and not-real criteria are structurally asymmetric. A real verdict needs poor behavior from two rules in any selected scenarios, while a not-real verdict requires every rule to perform well in every scenario. The exact-null, near-null direction scenario alone makes the universal not-real condition effectively impossible, and the low-precision delta equal to 0.04 scenarios make high agreement likely for overlap or point-null rules. The fiftyfold precision increase then supplies the required probability change. The verdict is therefore selected by the scenario grid rather than discovered by the simulation.

*Fix:* Remove the binary verdict or define symmetric criteria over a prespecified distribution of scientifically relevant scenarios. Require uncertainty-adjusted evidence for the same aggregate performance contrast in both directions.

**[SERIOUS] decision-rule**

The Monte Carlo calculations are correct, but the decision logic does not use them correctly. At a true boundary error of 0.05, the MCSE is 0.00436, so the cutoff of 0.06 is only about 2.3 MCSEs away; requiring every one of 24 boundary scenarios to remain below it creates a material chance of failure from simulation noise alone. The uninformative criterion requires an interval to overlap both 0.10 and 0.30. With 2500 replicates, even the widest pointwise interval is far too narrow to do that, so the clause does not protect decisions near either threshold.

*Fix:* Base each conclusion on threshold-specific Monte Carlo confidence limits, account for the maximum across scenarios, and increase replicates where simultaneous boundary control is required. Classify any interval crossing its relevant threshold as inconclusive.

**[SERIOUS] citation**

No citation maps the four status quo rules to their exact published definitions and recommended interpretations. The Wang citation supports the claim that multiple metrics were reported, but it does not by itself establish that pure direction agreement, confidence-interval overlap, trial-only standardization, and combined-SE null testing are all author-recommended replication decisions. Without that mapping, the fairness of the implementations cannot be audited.

*Fix:* Cite the exact source and equation for every comparator. If a rule represents downstream misuse rather than a recommended method, label it as such and provide evidence that it is actually used to make the claimed binary conclusion.

**[MINOR] citation**

The BMJ record is incomplete and internally inconsistent: the protocol omits authors and publication year, while the payload elsewhere labels the same DOI as both 2025 and 2026. The BMC citation spells Köppe as Koppe. The Fieller procedure is uncited, and calling the set exact can be misread as exact finite-sample coverage even though the component estimates and standard errors use Wald approximations.

*Fix:* Resolve the BMJ metadata from the DOI, use the authors' published spelling, add the complete Fieller reference, and describe the interval as exact inversion of the stated quadratic but approximate in coverage.

**[LIMITATION] answers-problem**

A replicate containing one independent benchmark pair cannot estimate prediction-interval calibration, between-question heterogeneity, between-database calibration, or behavioral contamination from retrospective knowledge of the trial result. The protocol acknowledges these exclusions, and they cannot be repaired within the current pair-level DGM.

*Fix:* Keep these as explicit scope limits if the study is reframed. Settling those parts of BEN-02 requires a separate portfolio or prospective multi-database design.

**[CITATION]** Concordance between target trial emulation and randomised controlled trials: systematic review and meta-analysis. BMJ. DOI 10.1136/bmj-2025-086810: Authors and publication year are missing, and the payload gives conflicting 2025 and 2026 years for the same work.

**[CITATION]** Koppe and colleagues. Assessing the replicability of RCTs in RWE emulations. BMC Medical Research Methodology. 2025. DOI 10.1186/s12874-025-02589-z: The surname is Köppe, not Koppe; the abbreviated attribution should be replaced with verified bibliographic metadata.

**[CITATION]** Wang SV, Schneeweiss S, RCT-DUPLICATE Initiative. Emulation of randomized clinical trials with nonrandomized database analyses: results of 32 clinical trials: The cited work supports use of multiple agreement metrics, but the protocol does not show that all four exact binary rules are definitions or recommendations from this source.

**[CITATION]** Fieller confidence set: No source is supplied. The quadratic inversion is exact algebraically, but coverage is not exact finite-sample coverage for these Wald-based estimators.


---

## 2. CNF-01

**Verdict.** unsound

The marginal estimands and superpopulation truth calculations are largely coherent, and 2,000 replicates are adequate for the stated cellwise coverage MCSE. The study nevertheless cannot settle CNF-01 because it evaluates an oracle sustained-strategy truth that the proposed applied analysis cannot identify, while the unresolved problem concerns interpreting real null results from observed treatment trajectories and choosing context-dependent horizons. Its principal materiality conclusion is structurally favored because six of nine comparisons impose persistent benefit and earlier permanent initiation, while only five qualifying comparisons are required. The AIPW variance calculation, ratio-based decision rules, universal-threshold claim, and runtime estimate also require revision before the simulation is run.

**[FATAL] answers-problem**

The protocol explicitly says that it only "answers-part" of CNF-01. It quantifies a DGM-specific difference between treatment-policy and sustained-strategy truths, but CNF-01's unresolved applied issue is whether observed treatment trajectories make a long-horizon null interpretable and whether a meaningful horizon convention can be established. RD_S and r are unavailable from the proposed baseline-assignment analysis, so the simulation cannot show that reporting S_cum distinguishes ineffective treatment from convergence in an applied emulation. It also contains no investigation of how often trajectories are reported or how local prescribing data should determine a horizon.

*Fix:* Register this as a mechanistic stress test that does not settle CNF-01. Settling the broader problem would require an empirical reporting study plus an identifiable sensitivity-analysis framework or externally anchored validation showing what trajectory reporting adds to interpretation.

**[SERIOUS] dgm-builds-in-finding**

For P1 and P2, treatment is permanently beneficial at every treated month because eta_t is always negative once treatment begins. Increasing p60 from 0.10 to 0.70 makes comparator initiation stochastically earlier while leaving the treated arm unchanged, so comparator risk necessarily moves toward treated-arm risk and r_high cannot exceed r_low. These profiles supply six of the nine matched comparisons, but the materiality rule requires only five. The simulation therefore establishes only whether the deliberately strong odds ratio, event rate, and switching levels cross the chosen magnitude cutoffs; the directional majority is built in.

*Fix:* Do not use a majority vote across deliberately constructed profiles to declare the phenomenon real. Treat monotone P1 and P2 results as quantitative calibration, report every profile separately, and base any nontrivial conclusion on prespecified nonmonotone or externally anchored mechanisms.

**[SERIOUS] dgm-builds-in-finding**

The rule declaring a convergence rate alone inadequate takes the range of r across switching mechanisms and different causal effect profiles. Because the protocol deliberately changes effect modification and initiation toxicity within that range, variation in r is expected even if convergence were held fixed perfectly. This demonstrates that different treatment-effect mechanisms produce different effects, not that an initiation percentage is an inadequate summary of convergence.

*Fix:* Evaluate adequacy of the convergence summary within each fixed causal effect profile. Compare switching timing and selection while holding the treatment-effect mechanism and sustained-strategy effect fixed.

**[SERIOUS] estimand**

G and r are called estimated quantities, but the methods specify no estimator for RD_S. The reported operational r is the estimated treatment-policy effect divided by oracle RD_S truth. That is legitimate as a simulation validation target, but it is not an observable quantity in the applied analysis for which the trajectory rule is proposed.

*Fix:* Label G, r, and the retention classification as oracle validation targets. Do not claim that the standardized trajectory report estimates retention or separates biological inefficacy from convergence without an additional sustained-strategy identification analysis.

**[SERIOUS] fair-comparison**

The status quo arm uses IPTW, while the proposed reporting package uses AIPW with a richer outcome model. Any difference in bias, precision, coverage, or failure rate therefore combines augmentation with trajectory reporting. Reporting a trajectory cannot itself change the treatment-policy point estimate or interval.

*Fix:* Separate estimator performance from diagnostic performance. Use the same effect estimator with and without trajectory reporting, or include both IPTW and AIPW versions of the reporting package and avoid attributing estimator differences to the report.

**[SERIOUS] fair-comparison**

The proposed empirical influence-function SE is generally invalid under the specified DGM. The cumulative outcome regression is misspecified because cumulative event risk integrates nonlinear discrete hazards, longitudinal L, and selective switching. With the propensity model correct but the outcome model misspecified, estimating the propensity contributes an additional first-order term that the plug-in influence-function variance omits. The IPTW method receives a full stacked sandwich, while the AIPW method does not receive the corresponding nuisance-estimation correction.

*Fix:* Use a stacked estimating-equation sandwich including the propensity and outcome score equations, or bootstrap the complete fitting procedure. Another option is a demonstrably consistent cross-fitted outcome estimator with variance theory matching the implementation.

**[SERIOUS] decision-rule**

The rules require r for all non-null scenario-horizon cells and nine matched pairs, but the estimand definition suppresses r whenever abs(RD_S) is below 0.005. P3 can place RD_S near zero as initiation toxicity gives way to benefit. The protocol does not say whether such cells are excluded, counted as failures, or change the five-of-nine denominator.

*Fix:* Prespecify handling of every undefined-r cell and adjust all denominators explicitly. Prefer additive G for decisions that must remain defined when RD_S is near zero.

**[SERIOUS] decision-rule**

Requiring each risk-difference truth to have MCSE at most 0.0005 does not adequately resolve ratio thresholds. At the permitted denominator abs(RD_S)=0.005, a 0.0005 component MCSE is already 10% relative uncertainty, so the MCSE of r can be around 0.1 or larger despite common random numbers. Labels at r=0.75 and differences of 0.20 can therefore be decided by truth-simulation noise.

*Fix:* Set precision requirements directly for r, r_low-r_high, and threshold distances. Continue truth simulation whenever a confidence interval intersects 0.75, 0.20, or another decision boundary.

**[SERIOUS] decision-rule**

Sensitivity and specificity are calculated over a hand-selected factorial grid, not a target distribution of clinical settings. The 162 non-null cells contain at most 36 distinct S_cum values because S_cum depends only on p60, k, and horizon, with values repeatedly weighted across profiles and mechanisms. Passing 0.80 on this grid cannot justify accepting a general horizon convention, particularly when the protocol separately concedes that it cannot establish a universal clinical horizon.

*Fix:* Describe the result as in-grid discrimination. Prespecify a target distribution and weighting of mechanisms, then validate the cutoff on separate externally anchored scenarios before proposing a general convention.

**[MINOR] decision-rule**

The replicate calculation is correct for one coverage or rejection proportion, but the reported minimum across 216 estimator-horizon cells is downward-selected. With cellwise MCSE about 0.00487, an apparently low minimum can arise from Monte Carlo variation even when every true coverage probability is identical.

*Fix:* Provide Monte Carlo intervals for every cell and use a simultaneous or multiplicity-aware interpretation for the minimum. Do not use the raw minimum as an unstated pass or fail criterion.

**[SERIOUS] feasibility**

The runtime justification emphasizes 504,000 GLM fits but omits the dominant longitudinal workload. Replicate generation alone entails 34.56 billion person-month updates. The 36 two-million-person truth runs add 8.64 billion longitudinal person-months plus outcome recursions under several intervention worlds. A six-to-ten-hour claim is not credible from the fit count alone, especially with stacked sandwiches, serialization, summaries, and possible truth extensions.

*Fix:* Run and report an end-to-end pilot containing data generation, all models, sandwiches, truth worlds, and serialization. Extrapolate separately for worker scaling and truth extensions, with measured memory and output sizes.

**[MINOR] citation**

The four established methodological references have plausible bibliographic identities and uses. The 2025 scoping-review citation omits every author and its final publication metadata. The Cain citation establishes how to define and estimate dynamic switching strategies, but it does not by itself establish the broader normative claim that such strategies should not be viewed as corrections to a treatment-policy estimand.

*Fix:* Complete the scoping-review citation from the publisher record. Attribute the estimand distinction to an explicit estimand source or present it as the protocol's causal interpretation rather than as a result of Cain et al.

**[CITATION]** Statistical methods to adjust for treatment switching in real-world clinical studies: a scoping review and decision framework. Clinical Pharmacology and Therapeutics. 2025. DOI 10.1002/cpt.70013.: All authors and final volume, issue, pages, or article number are absent, so author attribution cannot be checked from the protocol as written.

**[CITATION]** Cain LE, Robins JM, Lanoy E, Logan R, Costagliola D, Hernan MA. Using observational data to emulate a randomized trial of dynamic treatment-switching strategies.: The work supports explicit dynamic strategies. The additional claim that they should not be treated as a correction to the treatment-policy effect is an estimand interpretation that needs separate support or clearer attribution.


---

## 3. DTA-02

**Verdict.** unsound

The protocol addresses a relevant, explicitly scoped part of DTA-02, and its main marginal superpopulation estimand is coherent. However, the DGM deliberately links each important mapping error to effect modifiers or treatments with different effects, so the proposed conclusion that the problem is consequential is largely constructed. The diagnostic decision is also invalid because the aggregate gate tests homogeneity that the compatible DGM expressly violates. Major revision is required before running the study.

**[LIMITATION] answers-problem**

The simulation answers what happens under five known record-level mapping errors when canonical reference labels are available locally. DTA-02 also concerns how sites establish that their coding systems and clinical constructs implement the same trial when no unquestioned reference mapping exists. The proposed validation analysis begins after that hardest semantic problem has been solved.

*Fix:* Retain the explicit answers-part claim and describe the study as a conditional stress test. Resolving the broader problem would require empirical multisite work on constructing and validating reference definitions; this DGM cannot supply that evidence.

**[MINOR] answers-problem**

The within-cell outcome permutation changes individual labels but preserves every treatment and covariate conditional outcome distribution. It therefore does not create a different marginal causal estimand, even though the records are semantically discordant. It is an identifiability control, not an example of averaging estimates of different questions.

*Fix:* Keep it explicitly separate from the trial-incompatibility scenarios and do not use it to support claims about different estimands.

**[FATAL] dgm-builds-in-finding**

Every applied mismatch is connected by construction to a causal consequence. G contains -10U while tau_1 contains +0.30U, and the stealth mapping explicitly selects on U. Broad exposure mixes D = 1 with 25 percent D = 2 even though tau_1 is centered at -0.65 and tau_2 at -0.10. The composite adds W, whose D = 1 coefficient is only -0.05. These choices predetermine the direction of the mapping effects; freezing them before simulation does not remove that construction.

*Fix:* Replace the real versus not-real claim with scenario-conditional operating characteristics, or cross each mapping mechanism with null, weak, and strong relationships between the mapping discrepancy and potential outcomes. Any claim about practical consequentiality also requires externally calibrated parameter ranges.

**[SERIOUS] estimand**

The local fixed-effect estimator defines p_jx using the locally mapped analysis cohort after D = 2 and D = 3 are excluded. Its influence function therefore targets the X distribution among records whose observed treatment falls in D = 0 or D = 1. The declared intended truth conditions on G >= 45 but not on realized treatment category. Those are different populations whenever treatment-category probabilities vary with X.

*Fix:* Estimate p_jx from every locally eligible record before arm restriction, or redefine the local estimand and its truth as conditional on observed D being in {0,1}. State exactly which records contribute to p_jx and use the corresponding influence function.

**[SERIOUS] estimand**

Inverse-variance fixed-effect and random-effects pooling do not target the declared equal-site common-q estimand under heterogeneous site effects. Their probability limits use variance-dependent weights, while Psi weights sites equally and imposes q_x in every site. Calling their error relative to Psi bias conflates semantic incompatibility with a different aggregation estimand.

*Fix:* Report each pooling estimator against its own probability-limit estimand, and separately report its discrepancy from the scientific target. Add an equal-site pooling comparator using the same correctly mapped q-standardized site estimates so semantic and weighting effects can be isolated.

**[SERIOUS] fair-comparison**

The proposed standardization method receives the exact superpopulation q_x without uncertainty, while the conventional methods estimate local target distributions and use estimated inverse-variance weights. In addition, the DerSimonian-Laird comparator uses a normal interval with six sites and ignores uncertainty in tau-squared, a combination known to produce poor interval coverage. This makes interval and target-error comparisons favor the proposed method for reasons unrelated to semantic validation.

*Fix:* Give matched comparators the same target information where scientifically applicable. Include a currently recommended small-k random-effects analysis, such as REML or Paule-Mandel with Hartung-Knapp-style uncertainty, and distinguish it from the historical DerSimonian-Laird analysis.

**[FATAL] decision-rule**

The aggregate gate tests raw homogeneity even though compatible sites are deliberately heterogeneous. Exposure probabilities differ by site through 0.35 s_j in Q, and outcome risks differ through 0.10 s_j and, when gamma = 0.16, through the treatment interaction. Because all three adjusted tests must pass, compatible-network release will be low by construction. The real-problem rule then treats that manufactured false-abstention as supporting evidence, so the diagnostic conclusion is circular.

*Fix:* Do not use raw cross-site homogeneity as a semantic-validity test. Test mapping-specific audit quantities or deviations from prespecified site-specific expected distributions. Remove diagnostic failure from the definition of whether mapping incompatibility is consequential; evaluate harm and diagnostic performance as separate questions.

**[SERIOUS] decision-rule**

The protocol does not show that at least two mappings can cross the 0.02 bias or 0.20 unsafe-release thresholds after only two of six sites are affected. For broad exposure, the largest logit-effect separation is 0.75, so the maximum affected-site risk difference change from its 25 percent D = 2 mixture is about 0.046; averaging two affected sites among six caps network bias near 0.0155. Exact probability-limit values are already available and should have been checked before committing to the rule. The rule may therefore default to uninformative even though the directions of all effects were constructed.

*Fix:* Calculate and disclose every scenario probability limit before simulation. Revise the DGM, affected-site fraction, or decision thresholds if the prespecified classifications cannot occur without Monte Carlo error.

**[SERIOUS] decision-rule**

The replicate calculation targets a worst-case Monte Carlo standard error of 0.01, but the decisions compare raw estimates with 0.90 and 0.05 boundaries across many scenarios. At 2500 replicates, the approximate 95 percent Monte Carlo half-width is 0.012 near 0.90 and 0.009 near 0.05. A true performance value near either boundary can therefore change classification across runs.

*Fix:* Use prespecified Monte Carlo confidence bounds or indifference regions for every adequacy criterion. Increase replicates adaptively or in a prespecified second stage when a bound intersects a decision threshold.

**[SERIOUS] feasibility**

The three-to-eight-hour estimate is unsupported by a benchmark. The run creates 1.08 billion row instances, requires several random variables and mappings per row, performs 360000 site analyses, and repeatedly samples validation records. R-level allocation, grouping, parallel serialization, and batch checkpointing can dominate the simple count of model fits.

*Fix:* Benchmark complete batches that include generation, all mappings, validation sampling, aggregation, serialization, and checkpointing. Scale measured wall time and peak memory to 60000 replicates and include restart overhead before asserting an overnight budget.

**[MINOR] citation**

The five supplied citations have no evident author or title mismatch, and their stated uses are appropriately limited to simulation design, federated feasibility, transport motivation, and governance. However, the exact fixed-effect, DerSimonian-Laird, Q, I-squared, Wilson, and Holm implementations are uncited, despite the protocol calling some of them conventional status quo.

*Fix:* Cite the original methods and current methodological guidance, especially guidance on random-effects inference with few sites. Explain whether the selected implementations represent historical practice or current recommendations.

**[CITATION]** Uncited meta-analysis and decision procedures: No references support the exact DerSimonian-Laird normal interval, the combined Q and I-squared gate, or the claim that these implementations represent current status quo practice.


---

## 4. ELG-01

**Verdict.** unsound

The protocol cannot settle ELG-01 because internal probability validation makes latent eligibility point identified; the study evaluates an ideal two-phase sampling problem rather than the open nonidentification problem. Its expected qualitative result is largely constructed through eligibility-dependent recording, comorbidity-dependent eligibility, effect modification by comorbidity, correctly specified validation models, and known validation probabilities. The primary estimand and its true-value calculation are sound, but several comparisons mix estimands or information sets, and the decision rule is not adequately resolved by the planned Monte Carlo precision. The protocol should not run under its current claims and decision rule.

**[FATAL] answers-problem**

ELG-01 concerns indistinguishable latent states when eligibility recording is nonignorable and suitable validation data may be absent or nonrepresentative. The protocol reveals eligibility in an internal Bernoulli validation sample with known inclusion probabilities and perfect transportability. That converts the central problem into an identified two-phase missing-data problem. A simulation of one identified DGM cannot settle the underlying nonidentification question or establish that the problem is empirically material.

*Fix:* Either relabel the study as an operating-characteristics study for internal probability validation and state that it only partially answers ELG-01, or add an identification component. The latter should exhibit observationally equivalent DGMs with different eligible-population effects, establish which validation assumptions distinguish them, and study violations such as unknown inclusion probabilities, nontransportability, and outcome-dependent recording.

**[SERIOUS] dgm-builds-in-finding**

The positive qualitative result is constructed. Setting gamma to log(2) or log(4) makes recording depend on latent E; the -1.10 coefficient of C in the eligibility model associates eligibility with the only effect modifier; and delta changes by 0.08 across C. With correct treatment adjustment, heterogeneous-effect bias is exactly -0.08 times the error in the recovered P(C=1 | E=1). Conversely, known rho makes two-phase weighting and the augmented estimator consistent, while the exactly logistic pE and pR models favor joint-model imputation. OR 1 and homogeneous effects merely switch these pathways off; they do not make the positive cells non-tautological.

*Fix:* Treat the results as consequences of stipulated mechanisms rather than evidence that the problem is real. Add independently varied eligibility-effect-modifier association, recording mechanisms, effect-modification strength, continuous latent-value dependence, nuisance-model misspecification, and empirically calibrated parameter values.

**[SERIOUS] estimand**

The complete-case estimator naturally targets RD60 conditional on E=1 and R=1, while performance is assessed against RD60 conditional only on E=1. The resulting difference is an estimand shift, not estimation bias for the complete-case estimand. Calling it bias and evaluating its interval against the all-eligible truth will make valid inference for the selected population appear statistically defective.

*Fix:* Compute the true recorded-eligible effect for every recording scenario. Report estimation bias and coverage for that estimand separately from the transport or target-population discrepancy relative to the all-eligible effect.

**[SERIOUS] estimand**

The eligible-population outcome mixes three quantities: superpopulation prevalence PE, the realized count sum(E), and ascertainment yield sum(RE). Mean(RE) is not an implied estimate of PE from complete-case analysis, and mean absolute error in an implied count out of 4000 is undefined until the comparison target is specified.

*Fix:* Report superpopulation prevalence bias against PE, realized-sample total error against sum(E), and recorded-eligible yield mean(RE) as separate quantities. Do not describe ascertainment yield as an estimate of true eligibility prevalence.

**[SERIOUS] fair-comparison**

The main contrast changes both method and information. Validation methods receive E for a probability sample and known rho; MAR methods receive neither. The partial-identification method then discards the available validation data entirely. This can quantify the value of additional information, but it cannot support a ranking of methods on equal data. The design also cites Tompsett et al. for MNAR sensitivity analysis while omitting that comparator.

*Fix:* Separate comparisons by information set. Within the no-validation set, include prespecified pattern-mixture or selection-model sensitivity analyses over a gamma grid, including the true gamma as an oracle diagnostic. Within the validation set, compare joint MI, two-phase weighting, augmentation, and any validation-informed bounds using the same observations.

**[SERIOUS] fair-comparison**

Rubin inference for the validation-anchored MI estimator is not justified by drawing coefficients from a robust sandwich covariance. Phase-two weighted pseudo-score estimates are not automatically proper posterior draws, and Rubin rules do not automatically incorporate their dependence on the completed-data analysis. Coverage differences could therefore reflect an invalid variance construction rather than the eligibility method.

*Fix:* Derive the repeated-sampling variance for the complete procedure or use a bootstrap that repeats validation sampling, nuisance fitting, imputation, and outcome analysis. Validate the chosen variance estimator under the OR-1 and homogeneous controls before making coverage decision-critical.

**[SERIOUS] decision-rule**

The replicate derivation targets a bias MCSE of 0.003, but the decision boundaries require finer resolution. At MCSE 0.003, an observed absolute bias of 0.005 has a normal upper limit of 0.01088, and an observed bias of 0.015 has a lower limit of 0.00912; neither passes its paired confidence-bound condition. The rule also requires every homogeneous control to have absolute bias below 0.005. When true bias is zero and MCSE is 0.003, one such check fails by simulation noise about 9.6% of the time, before accounting for the many control cells.

*Fix:* Base replication counts on the joint numerical rule, with decision-critical bias MCSE below 0.0025 or a larger prespecified separation zone. Define the confidence construction for absolute bias, account for the collection of control checks, and replace raw all-cell thresholds with Monte Carlo intervals around signed bias.

**[SERIOUS] decision-rule**

The monotonicity requirement is not operationally defined. It does not state which estimator must be monotone, whether every pairwise contrast must satisfy the ordering, how validation-size duplicates are handled, or how Monte Carlo uncertainty in differences is treated. Different reasonable implementations can therefore produce different verdicts from the same results.

*Fix:* Write explicit contrasts for named methods and scenario pairs, including the direction of each expected contrast and a confidence rule for each difference.

**[MINOR] feasibility**

The 6 to 12 hour estimate is not yet supported and omits material work. Repeating three MI methods with 50 imputations on 10% of 48,000 replicates adds up to 720,000 completed-data analyses if implemented literally. The estimate also treats millions of stacked-sandwich and finite-difference calculations as inexpensive without timing them.

*Fix:* Benchmark all methods in the slowest scenario, including sandwich construction, the M=50 subset, serialization, and failure handling. Extrapolate from successful wall-clock worker time before committing to the overnight budget.

**[MINOR] citation**

The interval attributed to Imbens and Manski is not their specific confidence-interval construction; it is a generic Bonferroni expansion of estimated endpoints. Tompsett et al. are accurately invoked for MNAR sensitivity analysis, but that cited method is absent from the proposed comparator set. No clear author or title mismatch is apparent in the remaining citations.

*Fix:* Cite a source that directly justifies the proposed Bonferroni endpoint region or implement the Imbens-Manski construction. Either add the Tompsett-style sensitivity comparator or remove the claim that it serves as a comparator.

**[CITATION]** Imbens GW, Manski CF. Confidence Intervals for Partially Identified Parameters. Econometrica. 2004: The proposed endpoint-wise Bonferroni region is not the specific Imbens-Manski interval construction. The citation is too imprecise for the method actually implemented.

**[CITATION]** Tompsett D, et al. Target Trial Emulation and Bias Through Missing Eligibility Data. American Journal of Epidemiology. 2023: The attribution to MNAR sensitivity analysis is consistent with the work, but the protocol does not include that cited approach despite calling it an existing comparator.


---

## 5. ELG-02

**Verdict.** unsound

The protocol is unsound as a study intended to settle ELG-02, although several internal simulation components are technically careful. It replaces the open problem of auditing an unknown eligibility graph with regression tests in a DAG whose variables, temporal ordering, functional form, and missing causes are supplied to the screen. Collider bias, target shift, screen sensitivity, specificity, and latent-case abstention are consequently favored or guaranteed by construction. The design could support a narrow mechanism benchmark after revision, but it cannot resolve the catalog problem.

**[FATAL] answers-problem**

ELG-02 concerns prospective auditing when collider status depends on an uncertain causal structure that observational data cannot generally identify. The proposed screen is handed the exact relevant variables P and D, their temporal order, the four associations to test, correctly specified parametric models, and even knowledge that named causal parents are unavailable in latent scenarios. It never learns an unknown graph, recognizes an unknown latent cause, evaluates realistic healthcare-use processes, or performs domain review. It answers whether a known four-node collider produces bias and whether direct edges can be detected, which is a neighboring and largely settled question.

*Fix:* Either relabel the study as a narrow mechanism benchmark that answers only part of ELG-02, or evaluate a genuinely blinded auditor across diverse hidden graphs, indirect paths, common causes, proxies, nonlinearities, timestamp errors, and healthcare-use mechanisms. The auditor must receive only information that would exist at protocol review.

**[SERIOUS] answers-problem**

The proposed direction identifies reduction in bias after acting on warnings as the most important endpoint. The protocol separately evaluates screen sensitivity and an always-applied observed-parent repair, but its decision rule never evaluates the complete advisory procedure selected by the audit result. Successful edge detection plus successful oracle repair does not establish that the actual screen-and-response policy improves bias, coverage, or mean squared error.

*Fix:* Make the replicate-level advisory response a prespecified method. Evaluate its unconditional bias, coverage, mean squared error, failure rate, and abstention rate against routine analysis using the independent audit decision generated in that replicate.

**[FATAL] dgm-builds-in-finding**

The central qualitative finding is true by construction. In collider scenarios, lambda_P equals s and lambda_D equals plus or minus s, P affects treatment with coefficient 0.55, and D affects outcome with coefficient 0.65. Conditioning on H therefore opens A <- P -> H <- D -> Y. The screen then tests exactly those generating coefficients; its smallest H-edge coefficient is 0.45 with an audit sample of 4000, while the other tested coefficients are 0.55 and 0.65. Its noncollider false-positive probability is essentially the nominal 0.01 test size, already below the 0.05 success threshold. Latent-case abstention and zero silent-error probability are also programmed by explicitly telling the screen that P or D is unavailable.

*Fix:* Do not use these simulations to declare that the problem is real. Use them only to quantify consequences conditional on specified DAGs. For method validation, include near-null edges, externally calibrated effect sizes, indirect relations, misspecified models, and noncollider graphs that produce the same observed associations through confounding. Hide the graph and latent-variable identities from the screen.

**[SERIOUS] estimand**

B is not the sole effect modifier on the reported risk-difference scale. With z = -1.50 + 0.45B + 0.35X + 0.65D and delta_B = -0.35 + 0.25B, the conditional risk difference is Phi(z + delta_B) - Phi(z), which varies with X and D even without product terms. Because H depends on X and D, the target-population shift is partly caused by changes in their distributions. In latent-parent scenarios, part of that mechanism is not observed, contrary to the claim that the source of the target shift is observed and exactly specified.

*Fix:* Either use an outcome DGM with treatment effects additive on the risk scale and bounded valid probabilities, or explicitly recognize scale-induced effect modification and decompose Delta_target across B, X, and D rather than attributing it to B.

**[SERIOUS] fair-comparison**

When P and D are observed, routine AIPW is deliberately denied a strong treatment predictor and a strong outcome predictor. Conventional nuisance modeling could include P in the propensity model and D in the outcome model, or include all measured baseline variables in both. Either approach can block the selected path without a collider screen. The proposed observed-parent repair is therefore also a conventional richer-nuisance comparator, but the design attributes its advantage to auditing.

*Fix:* Add a prespecified conventional comparator that includes measured treatment predictors in the propensity model and prognostic variables in the outcome model without consulting the screen. Also compare with an all-measured-baseline model.

**[SERIOUS] fair-comparison**

The advisory procedure receives an additional independent sample of 4000 people, while routine analysis is evaluated using only the analysis sample of 4000. This gives the proposed procedure twice the data resources for deciding what analysis to report. The extra sample may be a legitimate design requirement, but it cannot be ignored in a comparative claim.

*Fix:* Use a fixed total sample allocation for all procedures, give comparators equivalent access to the audit data, or state that performance is conditional on an external audit dataset and report the associated data cost.

**[SERIOUS] decision-rule**

Visibility is not a DGM factor for routine AIPW. The 16 collider scenarios contain only eight distinct generated distributions, and the eight noncollider scenarios contain only four. Consequently, the requirement that four collider scenarios qualify can be satisfied by only two distinct DGM cells duplicated across observed and latent visibility. The noncollider specificity count has the same duplication problem.

*Fix:* Treat visibility as an analysis condition rather than a separate DGM for routine performance. Base all scenario counts on the eight unique collider cells and four unique noncollider cells, with explicit requirements across strength, retention, and orientation.

**[SERIOUS] decision-rule**

The declaration that collider bias is real requires both absolute bias and severe coverage failure at a fixed sample size. Coverage depends on bias relative to the standard error, so the same structural bias can pass or fail this rule solely because sample size changes. This conflates practical bias magnitude with inferential precision.

*Fix:* Use the prespecified absolute-bias threshold for the materiality conclusion. Report coverage failure as a separate operating characteristic rather than a necessary condition for whether the bias exists.

**[SERIOUS] citation**

The established citations are mostly accurate, but the two 2026 works are used for substantive claims despite having no authors in the bibliography and null supporting quotations in the audit payload. The title of the Frontiers article does not by itself establish that eligibility changes the resulting effect, and the temporal-selection title does not establish relevance to prospective collider auditing. No citation defines the claimed status quo AIPW implementation or supports deliberately excluding P and D, so the fairness claim cannot be checked against method guidance.

*Fix:* Resolve full metadata and extract supporting passages for both 2026 works before relying on them. Add primary references for AIPW, nuisance-variable selection, and stacked M-estimation variance, then define the status quo comparator from those recommendations.

**[CITATION]** From negative trial to positive clinical impact: mitigating eligibility criteria-induced temporal selection. 2026. DOI 10.1038/s44401-026-00082-3: Authors and journal are omitted, and the associated audit record has no supporting quotation. The title alone does not show that the work evaluates a prospective collider auditor or resolves any part of that problem.

**[CITATION]** Data-driven trial design: use of target trial emulation to evaluate eligibility criteria in asthma and COPD. Frontiers in Medicine. 2026. DOI 10.3389/fmed.2026.1863026: Authors are omitted, and the associated audit record has no supporting quotation. The title establishes evaluation of eligibility criteria but not the claimed finding that both target population and treatment effect changed.

**[CITATION]** Hansford HJ, Cashin AG, Jones MD, et al. Transparent reporting of observational studies emulating a target trial: the TARGET statement. JAMA. 2025.: The attribution appears correct, but TARGET supports reporting eligibility criteria and their emulation. It does not support the validity or performance of collider assessment and should be used only as evidence of the reporting boundary.

**[CITATION]** Weiskopf et al. 2023; Digitale et al. 2023; Wang et al. 2026; Tran et al. 2026: These works appear only as abbreviated attributions in the audit rationale, without sufficient titles, identifiers, locators, or quotations to check their claimed contents.

**[CITATION]** Routine restricted-cohort AIPW and stacked M-estimation sandwich: No methodological citation is supplied for the estimator, the recommended nuisance-variable sets, or the finite-difference stacked sandwich. The label status quo is therefore unsupported.


---

## 6. GMT-01

**Verdict.** unsound

The protocol cannot settle GMT-01 because it evaluates a hand-built rank score over a finite GLM library and explicitly substitutes split stability for the influence-function remainder named in the problem. Most scenarios construct the familiar treatment-only-predictor conflict, so favorable results could demonstrate a known propensity-score variable-selection phenomenon rather than the stated longitudinal machine-learning problem. The marginal estimand and superpopulation truth calculation are sound, but the nonlinear sequential outcome library is misspecified and the written model matrices contain structural constants that trigger the protocol's own failure rule. The published-calibration comparison, IPW inference, and decision thresholds also require revision before simulation.

**[FATAL] answers-problem**

GMT-01 concerns genuinely machine-learned longitudinal nuisance functions, a criterion containing an estimate of the influence-function remainder, and applicability across several longitudinal estimators. The protocol studies a prespecified 4 by 3 by 3 GLM menu, only IPW and a longitudinal one-step estimator, and a D component explicitly defined as split-to-split stability rather than a remainder estimate. A favorable result would show that one heuristic ranks one finite library well; it would not settle GMT-01.

*Fix:* Either relabel the study as a finite-library proof of concept that answers only part of GMT-01, or add actual ensemble and highly adaptive learners, estimator-specific implementations, and a defensible connection between the observable score and causal remainder or risk.

**[SERIOUS] dgm-builds-in-finding**

The desired prediction-versus-weight-dispersion conflict is constructed in 16 of 24 scenarios. With gamma_Z equal to 0.75 or 1.50, Z predicts treatment, has no prognostic role except through treatment, is available only in the larger G candidates, and is therefore rewarded by predictive deviance while worsening propensity tails. The positive rule requires only two gamma_Z equals zero successes, so the scenario count and median can still be dominated by the constructed instrument cells.

*Fix:* Make conclusions gamma_Z-stratified and require convincing performance across several gamma_Z equals zero cells. Add other mechanisms for predictive and causal ranking disagreement, and provide a correctly specified reduced-history propensity candidate when Z is excluded.

**[SERIOUS] dgm-builds-in-finding**

The stated odds ratios for Z are wrong because the equation multiplies gamma_Z by s. The actual per-SD odds ratios are approximately 1.63 and 2.65 under s equals 0.65, and 2.55 and 6.52 under s equals 1.25, rather than 2.12 and 4.48 in both overlap conditions. Consequently, the overlap factor also changes instrument and confounding strength, amplifying the constructed conflict in poor-overlap cells.

*Fix:* Correct the reported odds ratios and separate the overlap manipulation from the treatment-predictor coefficient if their effects are meant to be interpreted independently.

**[SERIOUS] estimand**

The claim that every scenario contains a correctly specified sequential outcome model is false in the nonlinear-outcome cells. Backward integration of L2 squared generates terms including W1 squared, L1:W3, and W1:W3 in the Q1 regression, with further corresponding terms at Q0. The stated Q2 candidate family includes L squares, W1:L terms, and L:L terms, but not these required terms. Apparent selector differences in those cells would therefore mix selection performance with universal Q misspecification.

*Fix:* Derive each sequential conditional mean algebraically and add every induced term, or explicitly designate the nonlinear-outcome cells as all-candidate-misspecified scenarios and prevent them from supporting claims about selection among correctly specified candidates.

**[SERIOUS] estimand**

The marginal estimand itself and its superpopulation truth are correctly aligned, but the material-effect scale is not. Setting the residual SD to one does not make the marginal outcome SD one because the systematic outcome component has nonzero variance. Thus coefficients and thresholds described as outcome standard deviations are actually residual-SD units, and regime-specific marginal SDs need not equal one.

*Fix:* Either call the units residual standard deviations or rescale Y using a prespecified marginal SD from a named reference population and regime before applying the 0.01 and 0.02 thresholds.

**[FATAL] fair-comparison**

The balance comparator is not the calibrated-weight method cited as the published alternative. It is a new maximum-plus-RMS balance score, and the protocol expressly disclaims reproducing a published implementation. Its censoring component is also underdefined because it compares retained and dropped people using cumulative retention weights without defining the dropped-person weight or calibration target. Beating this comparator cannot establish improvement beyond published calibrated weighting.

*Fix:* Implement the cited calibrated-weight procedure according to its published objective, risk-set definitions, normalization, and recommended inference. Otherwise restrict the claim to comparison with a bespoke balance heuristic.

**[SERIOUS] fair-comparison**

The IPW intervals knowingly treat estimated, selected weights as fixed. Cross-fitting does not remove the first-order contribution of propensity and censoring estimation for a nonorthogonal IPW estimator. These intervals therefore do not provide valid 95% coverage and give the one-step family a better-supported variance procedure, although point-estimator comparisons within the IPW family remain fair.

*Fix:* Use a valid influence function accounting for weight estimation or an outer bootstrap that repeats selection and fitting. Retain fixed-weight intervals only as a labeled sensitivity analysis.

**[SERIOUS] decision-rule**

The positive and negative rules are arranged so that the most plausible intended result is uninformative. In gamma_Z equals zero cells, predictive CV chooses among nested models containing the truth and has little reason to lose by 0.02 bias units or 0.05 coverage points. In the 16 nonzero-gamma_Z cells, the protocol deliberately creates the conflict, but improvements confined there cannot satisfy the positive rule, while enough such improvements prevent the 20-of-24 negative rule from firing.

*Fix:* Define separate decisions for the no-instrument and instrument mechanisms. Treat instrument-cell results as evidence about that known mechanism rather than requiring one global verdict about GMT-01.

**[SERIOUS] decision-rule**

The replicate calculation is based on the MCSE of one Bernoulli coverage proportion, whereas the primary statistic is a paired coverage difference whose variance depends on discordant coverage indicators. The 0.05 threshold is probably resolvable with 1000 replicates, but the 0.03 rules, scenario median, and exact 0.95 convergence cutoff have no precision-based acceptance rule. A method truly near 95% convergence has MCSE about 0.0069 and can pass or fail mainly by simulation noise.

*Fix:* Base replicate count on paired discordance, and apply Monte Carlo confidence bounds or prespecified indifference bands to coverage differences, convergence, and scenario medians.

**[FATAL] feasibility**

As written, the model matrices are rank deficient and violate the nonconvergence rule. Every t equals zero treatment model includes A(-1), which is identically zero. Regime-specific backward Q regressions also include treatment indicators and treatment-by-W3 terms that are fixed after conditioning on A_t equals a. stats::glm.fit or ordinary least squares will produce aliased coefficients, and the rule declaring any nonfinite coefficient a failure can therefore reject every replicate.

*Fix:* Specify full-rank time-specific model matrices that omit structurally constant and aliased columns. Define alias handling explicitly and test every candidate in a small dry run before timing the simulation.

**[SERIOUS] citation**

The 2022 calibrated-weights citation supports the existence of a particular calibrated longitudinal weighting approach, but it does not validate the protocol's bespoke B selector as that published method. Brookhart et al. supports the precision cost of treatment-only variables in point-treatment propensity-score models; it does not establish the longitudinal composite-selection result being tested. No apparent wrong-author or DOI mismatch is present in the other listed citations.

*Fix:* Use the 2022 work only after implementing its actual method, and cite Brookhart only as motivation for the treatment-only-predictor mechanism. Do not use either citation to generalize results to the full GMT-01 claim.

**[CITATION]** Marginal structural models using calibrated weights with SuperLearner: application to type II diabetes cohort. IEEE Journal of Biomedical and Health Informatics. 2022. DOI 10.1109/JBHI.2022.3175862: The work supports calibrated longitudinal weighting, but the protocol does not reproduce that method. The bespoke balance selector therefore cannot stand in for the cited published comparator.

**[CITATION]** Brookhart MA, Schneeweiss S, Rothman KJ, Glynn RJ, Avorn J, Sturmer T. Variable selection for propensity score models. American Journal of Epidemiology. 2006. DOI 10.1093/aje/kwj149: This is point-treatment propensity-score variable-selection evidence. It supports the treatment-only-predictor mechanism but not the longitudinal four-component selection criterion or its generality.


---

## 7. GMT-03

**Verdict.** unsound

The marginal estimands and superpopulation truth calculations are largely correct, and undercoverage is not algebraically guaranteed. The protocol nevertheless cannot settle GMT-03 because it studies one exact-regime IPW implementation, while the nominal million records have no inferential role and the confirmatory decision ignores subgroup and competing-event coverage. The diagnostic result is heavily encoded by the rare-event and cumulative-adherence parameters, then evaluated using only 24 scenario-level observations. The target claim, status quo comparator, endpoint-specific decisions, and diagnostic validation must be repaired before running.

**[FATAL] answers-problem**

GMT-03 concerns estimator-specific and time-varying information, inference accounting for estimated weights and outcome models, reporting practice, and failures for rare competing events and subgroups. This study evaluates one correctly specified, unstabilized, exact-regime sequential-IPW estimator with no fitted outcome model. Independent binomial retention means that the one-million-record source count is merely a label: directly drawing the retained sample would produce the same experiment. Consequently, the study can characterize one narrow coverage problem but cannot declare GMT-03 real or not real.

*Fix:* Frame the result strictly as coverage of the specified estimator within this DGM family and remove the field-level real or not-real declarations. Settling GMT-03 would require multiple estimator families, realistic restriction mechanisms, outcome-model methods, and a separate empirical assessment of reporting practice.

**[SERIOUS] answers-problem**

The confirmatory endpoint is coverage of the overall primary-event risk difference at 60 months. Nevertheless, a scenario qualifies through either a rare primary event or a rare competing event. A low competing-event count does not establish failure of primary-event inference; common competing events, not rare ones, are what substantially deplete the primary-event risk set. Coverage failure for competing-event and subgroup estimands remains secondary and is never required.

*Fix:* Define endpoint-specific decisions. Primary-event rarity must be judged against primary-event coverage, competing-event rarity against competing-event coverage, and subgroup claims against subgroup coverage. Analyze depletion of the primary-event risk set using the frequency of competing events separately.

**[SERIOUS] dgm-builds-in-finding**

The longitudinal support collapse is largely determined by the treatment parameters. At kappa=2.25, the stated minimum monthly adherence probability is about 0.676; repeating it for 59 decisions gives a cumulative probability near 1e-10 before the baseline probability is included. At kappa=1.25, a worst-history monthly probability near 0.899 still yields about 0.0019 over 59 decisions. With at most 4000 retained people, important histories therefore have essentially no sustained-regime support by construction. Matched kappa comparisons prevent small ESS alone from being called a finding, but they do not turn this extreme grid into an empirical boundary study.

*Fix:* Calibrate overlap levels using the distribution of cumulative regime probabilities and expected compatible counts over 60 months. Include several levels on both sides of the anticipated failure boundary rather than relying on acceptable-looking one-month probabilities.

**[SERIOUS] dgm-builds-in-finding**

The 20-effective-event component of the warning rule is nearly encoded by the factor levels. A 1% risk produces about 10 or 40 total events at retained n of 1000 or 4000 before division between strategies and loss through exact-strategy incompatibility. Kish event ESS cannot exceed the number of compatible events, so the median minimum event ESS will almost inevitably be below 20 in the rare-event cells. The resulting diagnostic evaluation will largely compare the prespecified rare-event indicator with coverage rather than discover whether 20 is a useful threshold.

*Fix:* Choose retained sizes and risks that produce effective event counts both below and above 20 after accounting for expected strategy compatibility. Validate the fixed cutoff on an independent and more densely sampled set of scenarios.

**[MINOR] dgm-builds-in-finding**

Any substantive finding that G modifies treatment effects is predetermined. The coefficient 0.287682 exactly cancels the direct treatment coefficient for G=1, while treatment-mediated changes in L create additional subgroup differences.

*Fix:* Restrict subgroup conclusions to estimator performance and coverage. Do not present the existence or direction of subgroup heterogeneity as a simulation result.

**[SERIOUS] fair-comparison**

The primary method is labeled status quo although it combines unstabilized exact-regime weights, a terminal Hajek estimator, and an HC1 variance that ignores propensity-score estimation. The cited MSM literature does not establish this exact combination as the recommended longitudinal analysis. Common implementations use stabilized weights and may use joint estimating equations, robust weighted outcome-model inference, or patient-level bootstrap inference. Failure of the selected method therefore cannot be generalized to conventional asymptotic inference.

*Fix:* Name the method as the exact fixed-nuisance procedure under study. Add at least one literature-faithful stabilized MSM or clone-censor-weight implementation with its recommended variance procedure and bootstrap comparator.

**[SERIOUS] fair-comparison**

The oracle comparison does not uniquely separate weight-estimation instability from weight-tail behavior. Estimated propensity scores can improve calibration and reduce variance relative to known probabilities, while kappa simultaneously changes cumulative compatibility, weight dispersion, propensity-model information, and treatment-confounding strength. The formal weight-tail attribution rule does not require any supporting pattern from the oracle or nuisance-aware analyses. Method-specific conditional coverage also compares different selected sets when convergence differs.

*Fix:* Treat the oracle analysis as a benchmark rather than a decomposition. Require prespecified agreement across oracle, fixed-nuisance, and nuisance-aware contrasts before making mechanistic attributions, and report comparisons on a common converged-replicate set alongside unconditional successful coverage.

**[SERIOUS] decision-rule**

The decision regions overlap. Coverage equal to 0.90 is both positive under the <=0.90 rule and inconclusive under the stated 0.90 through 0.93 interval; 0.93 can likewise overlap the inconclusive and no-failure regions. The Wilson requirement adds essentially no protection: with at least 3600 replicates, any observed coverage at or below 0.90 already has a 95% upper limit far below 0.925.

*Fix:* Use mutually exclusive inequalities and align the confidence bound with the inferential claim. If the claim is true coverage below 0.90, require the upper confidence limit below 0.90; otherwise define a distinct material boundary such as 0.925 and use it consistently.

**[SERIOUS] decision-rule**

Four thousand replicates estimate coverage adequately, but they do not provide 4000 observations for diagnostic sensitivity and specificity. Those quantities use only 24 scenario-level units, with an unknown and potentially very small number of failing or nonfailing scenarios. Their attainable values are coarse, their uncertainty is large, and sensitivity or specificity is undefined if every scenario receives the same coverage label. Using the replicate-median diagnostic also does not represent applying the warning rule to one realized study.

*Fix:* Use a substantially larger held-out set of independently specified DGM scenarios, require minimum numbers of failing and nonfailing scenarios, and report confidence intervals. Also evaluate the observed study-level flag across replicates or estimate coverage conditional on observed diagnostic values.

**[SERIOUS] feasibility**

The six-to-twelve-hour estimate is unsupported by a benchmark. The main experiment contains up to 14.4 billion person-months before event stopping, 192000 glm fits with repeated IRLS passes, and repeated sandwich, horizon, endpoint, subgroup, and monthly diagnostic calculations. The truth runs add up to roughly 960 million person-strategy months. Base R glm and data.table do not make the stated wall time credible without measured throughput.

*Fix:* Benchmark complete replicates from every retention and overlap extreme, including all summaries and checkpointing, then extrapolate from observed CPU time and memory. Benchmark the paired truth calculation separately.

**[SERIOUS] citation**

Robins, Hernan, and Brumback support marginal structural models and sequential weighting, but that citation does not establish the protocol's exact terminal Hajek estimator and fixed-nuisance HC1 interval as the recommended status quo. No method-specific citation supports that pivotal characterization.

*Fix:* Cite the source that defines and recommends the exact estimator and variance procedure, or remove the status quo label and add a literature-faithful comparator.

**[MINOR] citation**

The Zhang, Bujkiewicz, and Jackson title is given as a generic weighted-analysis title rather than its population-adjusted indirect-comparison title. That work does not validate a longitudinal risk-set ESS or the 100-or-20 rule. The 2025 Biometrical Journal citation also omits its authors and full bibliographic details.

*Fix:* Use the exact DOI-resolved metadata and state the population-adjustment scope of the Zhang work. Complete the Biometrical Journal citation and do not imply that either source validates the proposed cutoff.

**[CITATION]** Robins JM, Hernan MA, Brumback B. Marginal structural models and causal inference in epidemiology.: Correctly attributed and relevant to MSM weighting, but it does not support labeling this exact Hajek plus fixed-nuisance HC1 procedure as the recommended status quo.

**[CITATION]** Impact of near-positivity violations on IPTW-estimated marginal structural survival models with time-dependent covariates. Biometrical Journal. 2025.: The citation omits authors and complete publication metadata. Its motivational use is plausible, but it does not establish the proposed diagnostic threshold.

**[CITATION]** Zhang, Bujkiewicz and Jackson. Effective sample size estimators for weighted analyses.: The title is inaccurate or abbreviated relative to the DOI-resolved population-adjusted indirect-comparison work. Its setting does not validate longitudinal cumulative-weight ESS or the 100-or-20 cutoff.

**[CITATION]** No citation supplied for the 100-patient or 20-effective-event cutoff.: Prespecification prevents post hoc threshold selection, but it does not provide a scientific basis for these cutoff values.


---

## 8. GMT-04

**Verdict.** unsound

The protocol is unsound as a study claimed to settle GMT-04. It could provide a useful benchmark of three fixed parametric implementations, but it cannot establish a universal estimator default or a reporting requirement, and its main estimator-ranking reversal is encouraged by construction. The marginal estimand and superpopulation truth strategy are conceptually correct, and the primary Bernoulli Monte Carlo calculation is arithmetically sound. The scope, confirmatory DGM, comparison rules, decision criteria, fallback design, and citation support must be revised before running.

**[FATAL] answers-problem**

GMT-04 concerns whether any estimator is defensible as a general default and whether studies should be required to compare estimator families. A simulation of IPTW, one parametric g-formula, and one formula-based LTMLE implementation under static binary strategies cannot answer either normative question. It excludes matching, baseline regression and propensity approaches, g-estimation, structural nested models, data-adaptive targeted learning, irregular treatment, and most data structures named or implied by the problem. The protocol itself concedes that it answers only part of GMT-04, which contradicts the proposed real versus not-real declaration.

*Fix:* Reframe the study as a bounded benchmark of three prespecified implementations and remove claims that it settles GMT-04. Settling the broader problem would require a synthesis of existing simulations, multiple independently motivated DGMs and interventions, additional estimator families, and a separate basis for any reporting requirement.

**[SERIOUS] answers-problem**

The design attributes differences to estimator family even though family, nuisance-model specification, software implementation, truncation, and numerical failure rules all change together. It therefore answers whether these three implementations disagree under these formulas, not whether choosing IPTW, g-formula, or LTMLE generally matters.

*Fix:* Either restrict every conclusion to the named implementations or cross estimator family with common nuisance-learning strategies and implementation choices. Do not report a family ranking from a design that changes the estimator and its nuisance fitting simultaneously.

**[FATAL] dgm-builds-in-finding**

The confirmatory family-reversal condition is loaded into the nuisance quadrants. Under G1Q0, the treatment and censoring models omit the delta_g terms with coefficients 1.00, -0.80, 0.80, and -0.50 while the outcome side is correct. Under G0Q1, the transition and event models omit the delta_Q terms with coefficients 0.65, -0.45, 0.70, and -0.50 while the weighting side is correct. The rule then requires the lowest-MSE family to reverse between exactly those two quadrants. This is a positive-control demonstration of known robustness properties, not independent evidence that estimator choice is consequential in practice. The exact MSE ratio is not guaranteed, but the validity contrast is true by construction.

*Fix:* Keep these quadrants as labeled positive controls, but exclude them from any declaration that GMT-04 is real. Base the confirmatory conclusion on externally calibrated DGMs whose misspecification was not assigned according to the dependencies of the competing estimators.

**[SERIOUS] dgm-builds-in-finding**

Removing U creates more than treatment-outcome confounding. U also affects L0 by 0.80, later L by 0.55, censoring by 0.25, treatment by 0.70 before scaling, and the event hazard by 0.75. Hidden-U results therefore combine treatment confounding, dependent censoring, and misspecified covariate evolution. The claim that there are six benign G0Q0 scenarios is also false: three of those six hide U and are deliberately nonidentifiable.

*Fix:* Describe hidden U as a composite identification failure, or separate treatment confounding and dependent censoring into distinct factors. Correct the benign-scenario count and do not attribute the resulting bias to one pathway.

**[SERIOUS] estimand**

The estimand definition and recursion target are coherent, but the protocol withholds the two exact numerical truths even though they can already be computed. Consequently, the placement of the sign boundary, the benefit threshold of -0.03, and the absolute-error thresholds of 0.02 and 0.03 cannot be audited. If the true risks are far from -0.03, threshold crossing will be nearly impossible; if a truth lies close to -0.03, that endpoint is partly determined by the chosen coefficients.

*Fix:* Compute and freeze the exact regime risks and RD for delta_Q equal to 0 and 1 before simulation. Report their distances from zero and -0.03, and justify the practical thresholds without reference to simulated estimator performance.

**[SERIOUS] fair-comparison**

The nuisance-model flexibility is unequal. LTMLE receives separate time-specific regressions saturated in W1, W2, U, L_k, and A_k, while the g-formula receives pooled main-effect models plus only A_k by W1. Under omitted-lag scenarios, the saturated current-state interactions can absorb projections of omitted history that the g-formula specification cannot. Conversely, prohibiting SuperLearner removes the data-adaptive fitting commonly used to realize targeted learning's advertised robustness.

*Fix:* Use a common prespecified learner library and comparable time structure where possible, preferably with cross-fitting, or treat nuisance specification as a separate factorial variable. Otherwise label the methods as specific parametric implementations rather than estimator families.

**[SERIOUS] fair-comparison**

The interval comparison is not prespecified fairly. G-formula receives a full nuisance-adjusted M-estimation sandwich and LTMLE receives influence-curve inference, while the method labeled current-practice IPTW treats estimated and clipped weights as fixed. A nuisance-adjusted IPTW interval is included, but the decision rule does not say which IPTW coverage represents the family. This permits the worse IPTW interval to determine the desired conclusion.

*Fix:* Make the nuisance-adjusted IPTW interval the primary family interval, validate it against a subject-level bootstrap in a subset, and retain the fixed-weight interval only as a separately labeled historical comparator. Specify which interval enters every decision criterion.

**[SERIOUS] fair-comparison**

The primary Z endpoint treats method-specific numerical rules as estimator failure. Absolute coefficient limits, condition-number cutoffs, rank checks, and the number of fitted submodels differ substantially across methods. LTMLE has many more opportunities to cross a coefficient or rank threshold, so Z can be driven by arbitrary implementation guards rather than failure to estimate the causal contrast.

*Fix:* Separate software or guard-trigger failures from statistical nonidentification and estimand failures. Use common output-level validity criteria for the primary endpoint, report method-specific diagnostics separately, and perform sensitivity analyses over numerical cutoffs.

**[SERIOUS] decision-rule**

The positive and negative declarations are asymmetric. The positive rule needs lower bounds above 0.20 in only two of eight scenarios, while the negative rule requires upper bounds below 0.10 and near-equivalence on every metric in all eight scenarios, including G1Q1 scenarios deliberately constructed without a robustness guarantee. The realistic outcomes are therefore positive or uninformative; a negative declaration has been made implausible by design.

*Fix:* Calibrate both declarations under explicit null and alternative DGMs and report their operating characteristics. Use symmetric evidence thresholds, define precedence when an uninformative condition overlaps another declaration, and avoid treating failure under deliberate misspecification as evidence for a field-wide problem.

**[SERIOUS] decision-rule**

The hidden-U declaration uses a spread of scenario mean estimates below 0.01. Similar means do not establish that methods agree within individual datasets; large within-replicate disagreements can average away. It therefore does not test the stated concern that a real analysis can show reassuring three-method agreement while all three estimates are wrong.

*Fix:* Base the declaration on a prespecified probability of the joint within-replicate event: three-family range below 0.01 and every estimate more than 0.02 from truth. Report its Monte Carlo interval and the corresponding conditional error distribution.

**[SERIOUS] decision-rule**

Eight hundred replicates were justified only for an unconditional Bernoulli probability. The decision also depends on heavy-tailed MSE estimates, selected minimum-MSE families, correlated MSE ratios, coverage, bias, sensitivity among gross failures, and false-positive rates among nonfailures. Those conditional denominators can be much smaller than 800. The protocol also leaves the Monte Carlo interval method, paired MSE comparison, and multiplicity across scenarios unspecified.

*Fix:* Derive replicate requirements for every quantity that can determine the verdict. Prespecify paired replicate-level MSE contrasts, interval methods, minimum diagnostic denominators, and multiplicity handling. Increase the replicate count if a blinded pilot shows inadequate MSE or conditional-rate precision.

**[SERIOUS] feasibility**

The runtime fallback is not compatible with the decision rule. Removing s equal to 1.70 leaves eight hidden-U scenarios, but the agreement rule still requires six of twelve hidden-U scenarios, and several other statements still refer to 24 scenarios. The fallback is therefore a different protocol without a valid declared decision rule.

*Fix:* Choose and freeze one design after an end-to-end timing pilot, or preregister a complete alternative analysis and decision rule for the 16-scenario design, including revised denominators.

**[MINOR] feasibility**

The fit-count arithmetic is correct, but five seconds per ltmle call and near-ideal six-worker scaling are assumptions rather than measurements. The estimate also gives little allowance for stacked derivatives, diagnostics, repeated data construction, serialization, memory contention, and the 5,000,000-person validation runs.

*Fix:* Run a stratified timing pilot covering benign, misspecified, hidden-U, and severe-overlap cases using the entire pipeline and six workers. Base the final wall-time and storage estimates on observed throughput and peak memory.

**[MINOR] citation**

The gfoRmula citation gives an incorrect author presentation. The DOI corresponds to work by McGrath, Lin, Zhang, Petito, Logan, Hernán, and Young; listing only McGrath, Young, and Hernán without et al. misstates the authorship.

*Fix:* Use the complete author list or a valid first-author et al. form.

**[SERIOUS] citation**

No cited source supports the exact fixed-weight sandwich as the recommended current-practice comparator for this clone-censor estimator. The Robins and Cole-Hernán references support MSMs and weight construction, but they do not by themselves validate this particular covariance calculation, its clipping treatment, or its status-quo label. The generic Bang-Robins citation also does not establish the exact longitudinal TMLE implementation and influence-curve conditions used here.

*Fix:* Add method-specific sources for clone-censor inference, estimated-weight variance, and longitudinal TMLE. Tie each implementation claim to a versioned source or manual and remove the current-practice label unless it is directly documented.

**[CITATION]** McGrath S, Young JG, Hernán MA. gfoRmula: An R package for estimating the effects of sustained treatment strategies via the parametric g-formula: The author list is not a valid rendering of the DOI's authorship. The work includes Lin, Zhang, Petito, and Logan, and Young follows Hernán in the full list.

**[CITATION]** Robins JM, Hernán MA, Brumback B; Cole SR, Hernán MA: These works support MSMs and inverse-probability weighting, but the protocol overextends them to an uncited claim that its exact fixed-weight clone-censor sandwich is the current-practice variance estimator.

**[CITATION]** Bang H, Robins JM. Doubly robust estimation in missing data and causal inference models: This supports the general double-robustness concept. It is not sufficient documentation for the longitudinal sequential conditions, survival implementation, or influence-curve extraction used by ltmle here.

**[CITATION]** ltmle: Longitudinal Targeted Maximum Likelihood Estimation. CRAN: A rolling CRAN page does not pin the claimed package version or establish the exact behavior of Qform, gform, survivalOutcome, internal convergence checks, and returned influence curves. A versioned manual, source archive, and methodological paper are needed.

**[CITATION]** 10.1093/jamia/ocaf204; 10.1038/s41467-026-74999-6; the 16 DOI-only reading-update references: The payload supplies no verbatim quotations for the two resolving-work citations and no claim-specific locators for the DOI-only reading update. Their asserted coverage of GMT-04 cannot be checked from the supplied evidence.


---

## 9. LRN-01

**Verdict.** unsound

The protocol cannot settle LRN-01 as stated. It evaluates one series AIPW estimator and one support warning for observable positivity violations; it neither tests the applied claim that flexibility substitutes for identification nor addresses identification failures invisible in the observed law. The marginal estimand and observational-equivalence construction are largely coherent, but the principal finding is partly determined by the chosen structural completion and an especially favorable diagnostic test. Comparator aliasing, invalid or incomplete variance procedures, ambiguous decision metrics, and an undercounted runtime require correction before execution.

**[FATAL] answers-problem**

LRN-01 concerns flexible estimation being offered as a remedy for failed identification from confounding or positivity, plus the absence of a generally used interpolation versus extrapolation diagnostic. This study examines only positivity violations that are functions of recorded history and only one bespoke diagnostic for one series learner. It cannot study unmeasured confounding, cannot determine whether applied work presents flexibility as an identification remedy, and cannot establish a diagnostic applicable to flexible learners generally. The protocol itself concedes this by labeling the relation as answers-part.

*Fix:* Treat the study as resolving only a narrower support-diagnostic subproblem and prohibit a binary verdict on LRN-01. Settling the broader entry requires separate evidence about applied claims and must retain the impossibility of diagnosing exchangeability violations from the observed distribution.

**[FATAL] answers-problem**

The structural construction is not specific to flexible estimation. Every estimator sees the same observed law under all three completions, yet the primary false-certainty outcome is defined only for the flexible series estimator. The experiment can show that an ordinary point interval is not an identified-set interval, but it cannot show that flexibility especially disguises or worsens the problem.

*Fix:* Apply the identical compatible-truth coverage criterion to every estimator and make the prespecified contrast between flexible and conventional workflows primary. Otherwise remove all flexible-estimation-specific conclusions.

**[SERIOUS] dgm-builds-in-finding**

The term delta*Z, together with Z=0 for every observed structural trajectory, creates observational equivalence and different counterfactual truths by construction. The choices delta=-log(2), 0, and log(2), the R thresholds of -1.25 and 1.25, and the interval-width cutoff determine whether one interval can cover the compatible truths. This is a valid witness of nonidentification, but a high false-certainty rate under these choices is not evidence about how often flexible estimation creates the problem. The delta values are symmetric on the conditional logit scale, not on the marginal risk-difference scale.

*Fix:* Use the construction as a design check or identified-set benchmark, not as evidence that the field-level problem is real. Report sensitivity to several prespecified completion magnitudes and support boundaries, and limit conclusions to those stress tests.

**[SERIOUS] dgm-builds-in-finding**

The proposed map is tested against an unusually favorable support violation. The deterministic boundary R=L+0.40*M+0.30*B3 is a simple function of variables supplied directly to the diagnostic, while exact zero probabilities create action-specific empty regions. The truth label requires 0.05 unsupported mass, but the map turns red at 0.02. These choices do not mathematically guarantee success, but they strongly favor the desired sensitivity result.

*Fix:* Add independently generated support holes with curved, disconnected, interaction-dependent, and longitudinally accumulated boundaries, while retaining the same recorded conditioning variables. Evaluate practical near-zero support separately from exact deterministic holes.

**[MINOR] estimand**

Under a sustained intervention, the observational treatment-probability mechanism is overridden. Therefore, with C and delta fixed, the superpopulation risk difference is identical across strong, moderate, severe, and structural treatment-assignment mechanisms. The claim that eight distinct intervention trajectory simulations are needed obscures this equality and could produce support-specific truths that differ only through Monte Carlo noise.

*Fix:* Generate one common pair of intervention path sets per complexity level, evaluate every delta completion on those paths, and calculate the different support-mass functionals from the same paths.

**[SERIOUS] fair-comparison**

The status quo treatment models contain exact aliases. Each visit-specific model includes both an intercept and t/5, although t is constant within that model. At t=0 several previous-history variables are also constants, and at t=1 previous mean A equals A[t-1]. stats::glm will return aliased coefficients, while the protocol declares nonfinite coefficients to be nonconvergence. The IPW estimator and the main-effects AIPW estimator that reuses these models will consequently fail by definition.

*Fix:* Construct visit-specific design matrices that omit constants and exact duplicates, using the same prespecified alias-removal policy applied to the flexible models.

**[SERIOUS] fair-comparison**

The IPW sandwich does not fully account for estimating the sample 99th-percentile weight cap. Recomputing the cap while perturbing treatment coefficients captures its dependence on coefficients conditional on the realized sample, but treating capped contributions as independent person-level scores omits the empirical quantile's sampling influence. The main-effects AIPW also uses an efficient-influence-function variance without accounting for nuisance estimation in C=1, where both nuisance families may be misspecified.

*Fix:* For IPW, include the cap as a parameter with a quantile estimating equation or bootstrap the entire capped estimator. For the non-cross-fitted AIPW comparator, derive the influence function under its fitted nuisance models or bootstrap its complete fitting procedure.

**[SERIOUS] fair-comparison**

The heldout-loss comparison used to classify the flexible workflow as green is not implementable as written. The main-effects treatment and Q models are described as full-sample fits, no fold-specific comparator fits are specified or counted, and terminal-outcome log loss does not identify which regression, strategy, or aggregation is used. In addition, the leverage cutoff is estimated from heldout factual rows that contribute to the same diagnostic evaluation, which mechanically favors specificity.

*Fix:* Define every loss mathematically, fit both model classes on identical training folds, and evaluate them on identical validation folds. Estimate leverage cutoffs from training data or a separate calibration sample.

**[SERIOUS] decision-rule**

Structural sensitivity and strong-overlap specificity are singular quantities in the decision rule, but the protocol does not say whether they are pooled, averaged, or required in every sample-size and complexity cell. Pooling would allow favorable cells to hide diagnostic failure in another cell. False certainty after adding the map is also not explicitly defined, although the claimed paired reduction depends on that definition.

*Fix:* Specify cell-level denominators and aggregation before simulation. Prefer a minimum-across-cells requirement, and define false certainty under the map as the original event plus a green support status.

**[MINOR] decision-rule**

One thousand replicates can resolve the broad 0.10 versus 0.50 alternatives, and the stated worst-case MCSE calculation is correct. However, decisions use raw point estimates at 0.50 and 0.90, so estimates separated from a threshold by much less than their Monte Carlo uncertainty receive opposite verdicts. The achieved-primary-MCSE-above-0.02 clause cannot fire for an unconditional Bernoulli rate based on all 1000 replicates, whose MCSE is at most 0.01581.

*Fix:* Base threshold decisions on prespecified one-sided Monte Carlo confidence bounds or add indifference margins. Remove the impossible MCSE clause or define a smaller effective denominator that could make it relevant.

**[SERIOUS] feasibility**

The arithmetic of 16000 distinct observed datasets and 864000 listed GLM fits is correct, but it is not a complete workload estimate. It excludes the fold-specific main-effects fits needed for the heldout comparisons, repeated full-data evaluations for the numerically differentiated IPW sandwich, empirical-cap calculations, ridge matrix operations, counterfactual predictions, diagnostics, and checkpoint serialization. A 6 to 12 hour forecast based only on fit counts and a truth-simulation benchmark is not substantiated.

*Fix:* Implement one complete replicate at each sample size, including every variance estimator and diagnostic, benchmark at least 100 representative replicates, and extrapolate from observed wall time and memory use with the intended six-worker configuration.

**[MINOR] citation**

The citation to Target trial emulation under nonmutually exclusive assignment is incomplete and is used for a stronger claim than the supplied record establishes. Its title concerns nonmutually exclusive assignment; neither the title nor the payload's citation record demonstrates that poor overlap defeats advanced adjustment. No authors, page range, quotation, or specific result are supplied.

*Fix:* Verify the full text, provide the complete attribution and exact result supporting the overlap claim, or narrow the statement to what the work actually evaluates.

**[CITATION]** Target trial emulation under nonmutually exclusive assignment. American Journal of Epidemiology. 2026;195(4):1045. doi:10.1093/aje/kwaf018: The authors and full pagination are absent, and the stated poor-overlap claim is not established by the citation information supplied.


---

## 10. LRN-05

**Verdict.** needs-revision

The protocol directly answers the operating-characteristics portion of LRN-05, but it cannot settle the full problem and correctly should be presented as answering only one part. The principal marginal and conditional estimands, oracle calibration values, and superpopulation truths are mostly correct. The strategy-specific decile contrast is not a valid population contrast, and the current-practice comparator is deliberately misspecified relative to the exact observed-history benchmark. The real versus not real declaration is partly built into the confounding grid, its boundary ignores Monte Carlo classification error, and the runtime estimate omits substantial bootstrap work.

**[LIMITATION] answers-problem**

The study answers the specific question of how selected artificial-censoring IPW performance estimators behave under one form of exchangeability failure. It does not answer the broader LRN-05 questions concerning sensitivity intervals, continuous or dynamic strategies, transport between databases, learned-rule training, or mapping predictions to decisions. The protocol acknowledges this, so the design is aligned only if no later claim says that LRN-05 itself has been settled.

*Fix:* State in the title, abstract, decision rule, and catalog attachment that the study supplies scenario-specific operating characteristics for static binary sustained strategies. Do not change the overall catalog verdict solely because this simulation succeeds.

**[SERIOUS] dgm-builds-in-finding**

In every cell with gamma not equal to zero and delta greater than zero, U is deliberately made a cause of both treatment and outcome and is then omitted from the primary weights. The parameter combinations gamma in {log(0.40), log(2.50), log(4.00)} and delta in {log(1.50), log(2.00)} therefore make sequential exchangeability false by construction, while the full-history oracle restores it by conditioning on U. The simulation can reveal the size, direction, metric dependence, false reassurance, and diagnostic behavior of the resulting distortion, but it cannot discover whether unmeasured confounding can matter. Calling three threshold crossings proof that the problem is real mistakes a constructed premise for an empirical finding, especially because neighboring strong-confounding cells are counted as separate demonstrations.

*Fix:* Replace the binary problem-is-real declaration with scenario-specific statements about consequential distortion. Prespecify a response surface over weaker, stronger, opposite-direction, and partially canceling mechanisms, and interpret repeated cells as sensitivity points rather than independent confirmations.

**[SERIOUS] estimand**

The contrast c_g1k minus c_g0k does not compare the same population stratum. Each strategy has its own score and its own strategy-specific decile cut points, so the kth always-treat decile can contain different people from the kth never-treat decile. The resulting number is a difference between two differently selected subpopulations, not a strategy contrast.

*Fix:* Either report each strategy's calibration curve separately or define common baseline strata before assigning strategies, using a fixed prognostic score or another prespecified partition shared by g0 and g1.

**[MINOR] estimand**

The calibration-bin truths are described as population-decile quantities, but the cut points are estimated from 200000 simulated profiles. Batch Monte Carlo error calculated only from the remaining 1.8 million profiles is conditional on those random cut points and does not measure their error relative to the stated superpopulation deciles.

*Fix:* Include cut-point construction in the truth-sample batching, use a much larger independent cut-point sample, or compute the score quantiles by deterministic integration. Apply the truth-precision rule to the complete procedure.

**[SERIOUS] fair-comparison**

The estimated measured-history comparator is not an estimated version of the exact observed-history benchmark. The benchmark conditions on the entire observed history through a latent-state filter, whereas the fitted follow-up model uses only X1, X2, current L, and previous A, with no time or earlier history. Once gamma is nonzero, marginalizing U makes the observed process non-Markov and generally nonlogistic in that reduced predictor set. Consequently, their difference combines parameter estimation, functional-form misspecification, and omission of measured historical information. It cannot be described as quantifying nuisance-model error alone or as a fair representation of recommended longitudinal IPW practice.

*Fix:* Give the applied comparator the full measured history and a sufficiently flexible treatment model, including time and summaries or flexible representations of prior L and A. Alternatively, compute an exact propensity conditional on the same reduced history and label the remaining difference precisely. Report a commonly recommended stabilized or truncation sensitivity analysis if claims about current practice are retained.

**[SERIOUS] decision-rule**

The replicate calculation establishes an MCSE of 0.00671 when estimated coverage is 0.90, but the declaration compares the raw estimate directly with 0.90. A cell whose true coverage is slightly above the boundary can cross it by Monte Carlo error, and the at-least-three-cells rule compounds that classification uncertainty. No corresponding precision calculation is given for bias thresholds, the maximum across ten bins, convergence, or diagnostic sensitivity.

*Fix:* Base cell declarations on prespecified Monte Carlo confidence bounds or an indifference region. For example, require the upper Monte Carlo confidence bound for coverage to be at most 0.90, and require bias confidence bounds to clear their consequential thresholds. Derive the replicate count for every quantity used by the final rule, including the selected maximum-bin statistic.

**[SERIOUS] feasibility**

The main run processes up to 4.608 billion person-months and fits 96000 GLMs, in addition to filtering, weighted regressions, rank statistics, numerical Jacobians, and covariance calculations. The bootstrap check adds 4 times 25 times 199, or 19900, full resampled analyses. If the fitted comparator is checked, that alone adds up to 39800 GLM refits, which is not reflected in the stated 96000 fits. Assigning only one additional hour to work amounting to roughly 41 percent of the main GLM count is not credible without an end-to-end benchmark.

*Fix:* Benchmark complete replicates from representative adequate-support and stressed-support cells, including numerical derivatives and output, then benchmark full bootstrap resamples with refitting. Extrapolate from those measurements with worker-scaling and checkpoint overhead before committing to the overnight schedule.

**[MINOR] citation**

Sachs, Sjolander, and Gabriel support constructing and evaluating an explicit decision rule, but one framework does not establish that the prediction-to-decision component is generally resolved for multi-arm, dynamic, or utility-sensitive decisions. Lin and colleagues document an immature literature and call for broader treatment and model classes; that review does not itself justify beginning with another discrete sustained-strategy design.

*Fix:* Describe Sachs and colleagues as prior work demonstrating one explicit decision-rule framework, not closure of the component. Use Lin and colleagues only for the scoping findings and requested extensions, while presenting the binary starting point as this protocol's deliberate restriction.

**[CITATION]** Sachs MC, Sjolander A, Gabriel EE. Aim for clinical utility, not just predictive accuracy. Epidemiology 2020;31(3):359-364: The authorship and methodological attribution are consistent, but the citation supports an example and argument for explicit decision rules rather than the broad claim that prediction-to-decision mapping is already addressed.

**[CITATION]** Lin L, Sperrin M, Jenkins DA, Martin GP, Peek N. A scoping review of causal methods enabling predictions under hypothetical interventions. Diagnostic and Prognostic Research 2021;5(1):3: The bibliographic attribution and scoping claims are consistent. Its request for non-discrete treatments and nonparametric models does not support the stated justification for beginning with discrete sustained strategies.


---

## 11. MER-01

**Verdict.** unsound

The protocol is unsound as a study intended to settle MER-01, although it could support a narrower simulation claim. Its static strategy omits the stated mechanism through which confounder misclassification changes artificial censoring. The primary decision is also largely predetermined by symmetric outcome misclassification, while the correction receives its own correctly specified latent model and the thresholded comparator receives a misspecified proxy treatment model. The marginal estimand and superpopulation truth are otherwise specified correctly.

**[FATAL] answers-problem**

The central confounder-error and censoring mechanism in MER-01 is absent. Clones are censored only when Astar differs from the static regime. Lstar never determines strategy membership, eligibility, or censoring, so L error can distort fitted weights but cannot change which patients are censored. The proposed B_AL contrast therefore studies treatment misclassification combined with covariate measurement error in a propensity model, not the stated interaction between confounder misclassification and artificial censoring.

*Fix:* Add dynamic strategies, eligibility rules, or censoring rules that depend on latent L but are implemented using Lstar. Otherwise rename the question and restrict the conclusion to weight-model distortion under static sustained strategies.

**[LIMITATION] answers-problem**

The design explicitly excludes convenience validation, external validation transport, imperfect gold standards, irregular observation, and eligibility error. These are substantive reasons MER-01 remains open, not peripheral details. The study can answer only the internal random-validation subproblem and cannot support changing the catalog entry to resolved.

*Fix:* Retain an answers-part classification. Resolving the broader problem requires separate scenarios with selected or externally transported validation data and imperfect reference measurements.

**[FATAL] dgm-builds-in-finding**

The primary problem-real rule is driven by all-node cells that include terminal outcome error. Under the odds-ratio-1 mechanism, Ystar equals Y XOR E with E independent and probability e, so RD using Ystar equals (1 minus 2e) times the corresponding RD using Y. The e values 0.30 and 0.15 therefore impose attenuation factors of 0.40 and 0.70 by construction. Given the deliberately substantial treatment effect, large bias and undercoverage are expected even if longitudinal A and L error have no important interaction. The separate nonadditivity condition does not prevent this because it can be satisfied by a small A-L interaction while the required 0.02 bias comes from textbook outcome attenuation.

*Fix:* Base the primary real versus not-real decision on the A-and-L cells without Y error. Treat B_ALY minus B_AL as a separate component result and compare it with the analytic attenuation implied by the bit-flip model.

**[SERIOUS] dgm-builds-in-finding**

Favorable correction performance is asymptotically built into the core scenarios. The correction uses exactly the latent transition and outcome formulas that generated the data, exactly the Markov error structure that generated the proxies, a simple random validation sample, and perfect longitudinal gold standards. The four stress cells misspecify only one outcome interaction and do not evaluate validation-size thresholds under misspecification.

*Fix:* Cross validation size with misspecification of the treatment, confounder, outcome, and error-transition models. Make any worth-it conclusion conditional on performance outside the congruent core model.

**[SERIOUS] dgm-builds-in-finding**

X2 is deliberately used both to strengthen the treatment effect, from log odds coefficients of minus 0.60 to minus 1.00, and to increase the odds of phenotype error fourfold. This aligns the largest errors with the subgroup having the largest effect. Without neutral and reversed alignments, the study cannot distinguish a general consequence of differential error from the chosen correlation between effect magnitude and measurement quality.

*Fix:* Cross effect modification with error heterogeneity. Include no effect modification, differential error through an unrelated covariate, and reversed alignment in which the larger error occurs in the weaker-effect stratum.

**[SERIOUS] fair-comparison**

Serial proxy error makes the observed Astar process a hidden-state mixture. Consequently, Pr(Astar_t given Astar_(t-1), Lstar_t, X1, X2, and t) is generally neither first-order Markov nor logistic linear; it depends on more of the observed proxy history. The thresholded propensity model is therefore knowingly misspecified, while the oracle and corrected analyses receive correctly specified latent treatment models. Bias attributed to thresholding will partly be ordinary nuisance-model misspecification.

*Fix:* Add a best-case thresholded comparator using the exact observed-history propensity obtained by filtering the known DGM, and add a practical flexible comparator using sufficiently rich proxy histories. Attribute residual differences only after these comparisons.

**[MINOR] fair-comparison**

The statement that M equals 20 gives at least 95.2 percent relative efficiency is mathematically correct for point-estimate efficiency, but it does not establish stable between-imputation variance or interval coverage. Almost every nonvalidated participant has many latent nodes, so conclusions about correction MSE and coverage may depend materially on the arbitrary imputation count.

*Fix:* Choose M using the Monte Carlo error of the MI estimate and SE, then repeat representative cells with substantially larger M. Report whether worth-it classifications change.

**[SERIOUS] decision-rule**

The rules are numerically reachable, but 500 replicates do not resolve their coverage boundaries reliably. At true coverage 0.90, the probability that empirical coverage is at most 0.90 is only about one half; the same boundary instability occurs at 0.925. The claimed 0.025 separation is only about two Monte Carlo standard errors. Nonadditivity and MSE thresholds also lack Monte Carlo confidence requirements, and selecting the smallest qualifying validation size amplifies boundary noise.

*Fix:* Use one-sided or equivalence Monte Carlo confidence limits for every decision component, including paired nonadditivity and MSE contrasts. Increase or sequentially extend replicates until the relevant confidence limits fall wholly on one side of a threshold; otherwise return uninformative.

**[MINOR] decision-rule**

The prior-sensitivity threat refers to validation n equal to 100 combined with accuracy 0.99, but that cell does not exist. Accuracy 0.99 is evaluated only at validation n equal to 500.

*Fix:* Either add the stated n equal to 100, accuracy 0.99 boundary cells or rewrite the prior-sensitivity plan to name the cells that are actually simulated.

**[MINOR] feasibility**

The claimed wall time of 7 to 11 hours is not supported by timing evidence in the protocol. The workload includes roughly 420000 completed-data analyses, 840000 treatment GLM fits, about 105000 penalized latent-model fits, and on the order of 18 billion participant-month imputation updates. The finite-state recursion and repeated base-R optimization may dominate the simple fit count.

*Fix:* Treat the planned timing run as a binding feasibility gate. Benchmark the complete workload, including imputation, Hessians, sandwich derivatives, serialization, and six-worker scaling, before stating a wall-time estimate.


---

## 12. MIS-01

**Verdict.** needs-revision

The narrow question and marginal estimand are coherent, but the protocol is not ready to run. It addresses the comparative, gridded component of MIS-01; it cannot settle the identification problem, which the protocol appropriately acknowledges. The main defects are a DGM favoring the desired failures, unequal misspecification in challenge scenarios, invalid diagnostic validation, and a decision rule that conflates convergence with coverage. The runtime estimate also contradicts the stated computational workload.

**[LIMITATION] answers-problem**

The study answers how selected estimators behave under a known monthly latent-state selection model. It cannot answer the central open question of which structure is credible when latent-state-dependent visiting is not identified from observed data. It also excludes direct effects of healthcare use, encounter-gated treatment, and informative outcome ascertainment. The payload acknowledges this, so the study is relevant rather than neighboring, but it cannot settle MIS-01 as a whole.

*Fix:* Bind all conclusions and any catalog update to the comparative gridded subproblem. Describe results as conditional on the specified selection models, not as showing that MIS-01 is solved or that one visit-aware method is generally adequate.

**[SERIOUS] dgm-builds-in-finding**

The DGM strongly favors status-quo failure. Positive gamma_L makes recording depend on unobserved current L; L then has coefficient 0.95 in treatment, 1.20 in the event hazard, and 0.30 in the treatment interaction, while the first-order persistence coefficient is 2.10. These choices make current L important for confounding, prognosis, effect modification, and prediction while LOCF substitutes a stale value. The simulation primarily measures the magnitude of a deliberately installed failure.

*Fix:* Factorially vary the treatment, outcome, interaction, and persistence coefficients, including null and weak settings. A conclusion about practical materiality should require failure across settings where informative observation is not automatically coupled to strong latent confounding and effect modification.

**[SERIOUS] dgm-builds-in-finding**

Holding alpha fixed while increasing gamma_L changes both selective dependence and the marginal amount of observation. Increasing gamma_A likewise changes observation frequency differently by treatment history. The matched gamma_L comparisons therefore do not isolate informativeness; they mix selection with increased data availability.

*Fix:* Add scenarios in which alpha is recalibrated to hold marginal observation frequency constant across gamma_L and gamma_A levels. Report the current fixed-intercept comparisons separately.

**[SERIOUS] dgm-builds-in-finding**

The joint latent-state likelihood exactly reproduces every core generator component. A core-scenario victory therefore demonstrates correct parametric specification. The four challenge cells alter only the state-transition order and do not probe wrong observation links, additional latent states, heterogeneous measurement effects, or treatment and outcome misspecification.

*Fix:* Add generators not nested in the joint likelihood and vary misspecification along independent axes. Do not interpret performance under the 12 core cells as evidence beyond correct-model compatibility.

**[SERIOUS] fair-comparison**

In the second-order scenarios, the oracle alone receives the correct second-order transition model. Complete-record, LOCF, MI, inverse-intensity, and joint methods retain first-order working models. Requiring a visit-aware method to pass both informative second-order cells therefore mixes visit handling with ordinary transition-model misspecification.

*Fix:* Give each method a correctly specified second-order analysis variant when technically possible, then evaluate a separate shared-misspecification analysis. Do not use the latter cells in the primary adequacy gate.

**[SERIOUS] fair-comparison**

The capped-weight method is declared failed whenever the raw weighted fit fails. Capping is specifically intended to prevent failures caused by extreme weights, so inheriting failures from the uncapped outcome, transition, or sandwich calculation removes one of its legitimate advantages.

*Fix:* Propagate only failures of the shared observation-probability model. Fit and assess the capped weighted regressions and variance calculation independently of the uncapped versions.

**[SERIOUS] fair-comparison**

The raw and capped weight sandwiches mention visit-model uncertainty but omit estimating equations for the data-dependent monthly normalization constants and post-cap renormalization constants. Month-specific scaling changes the relative contribution of months to pooled regressions, so treating those constants as fixed can understate uncertainty.

*Fix:* Include every normalization constant in the stacked system, or differentiate the complete estimating procedure numerically with normalization and capping recomputed during perturbation.

**[SERIOUS] fair-comparison**

Twenty imputations are not justified for scenarios with roughly 92 percent reference-month nonobservation and potentially very high fractions of missing information. This gives MI avoidable Monte Carlo noise while the other methods are essentially deterministic conditional on a dataset. Requiring all 20 completed-data fits to succeed further penalizes MI as an implementation rather than as a method.

*Fix:* Choose the number of imputations from a pilot targeting prespecified Monte Carlo reproducibility of estimates and standard errors. Use enough imputations for the sparse scenarios and distinguish imputation-generation failure from analysis-model failure.

**[SERIOUS] decision-rule**

Counting every nonconverged replicate as noncoverage makes the primary measure joint convergence-and-coverage, not confidence-interval coverage. A method with 0.95 convergence and nominal 0.95 conditional coverage has only 0.9025 joint success, so it cannot satisfy the stated 0.925 coverage threshold despite meeting the explicit 0.95 convergence requirement. The effective convergence requirement is approximately 0.974.

*Fix:* Use coverage among converged replicates as the coverage criterion and convergence as a separate criterion. Alternatively, call the endpoint joint procedural success and set internally consistent thresholds.

**[SERIOUS] decision-rule**

Observable calibration intercept and slope appear to be calculated on the same rows used to fit the logistic observation model. With an intercept, those values are approximately 0 and 1 by construction from the score equations, even under important misspecification. They cannot diagnose the omitted current latent state.

*Fix:* Calculate all observable prediction diagnostics from cross-fitted or genuinely held-out predictions. Preserve the simulation-only conditional-on-L diagnostics as explanatory quantities rather than observable validation.

**[SERIOUS] decision-rule**

The diagnostic classifier is not defined by estimator, training model, pooling rule, or handling of single-class held-out scenarios. Replicates within a scenario do not provide 1000 independent tests of transport across mechanisms; there are only 16 DGM environments, and a held-out environment may contain almost all errors or almost no errors above 0.02. A pooled AUC could mostly distinguish scenarios rather than detect replicate-level failure.

*Fix:* Specify the estimator-specific classifier and validation calculation. Add many more independently varied DGM settings, use scenario-clustered uncertainty, prespecify handling of single-class folds, and distinguish within-scenario discrimination from across-scenario transport.

**[SERIOUS] decision-rule**

Binary conclusions use raw Monte Carlo point estimates at hard boundaries. With 1000 replicates, coverage MCSE is 0.00689 at 0.95 and about 0.0083 at 0.925, so a scenario can cross a threshold through simulation noise and thereby change a count-based verdict. In addition, the oracle may fail one scenario while that scenario still contributes to the substantive decision.

*Fix:* Use Monte Carlo confidence bounds or prespecified indifference zones for every threshold. Require the oracle gate separately in every scenario allowed to contribute to a materiality or adequacy count.

**[SERIOUS] decision-rule**

Common-random-number differences directly estimate changes in signed bias, not changes in absolute bias. The target quantity is |mean error at gamma_L=1.386294| minus |mean error at gamma_L=0|; its Monte Carlo error is not generally the standard error of replicate-level absolute-error differences and is nonregular when either bias is near zero.

*Fix:* Define the estimator explicitly and use a paired bootstrap or the appropriate delta method with bias signs. Alternatively, base the rule on paired change in signed bias.

**[SERIOUS] feasibility**

The 7 to 11 hour estimate is inconsistent with the workload. Six workers over that interval allow only about 9.5 to 14.9 CPU seconds per replicate. Fifty-six GLMs alone would receive only 0.17 to 0.27 seconds each, leaving no time for path imputation, recursions, individual scores, Hessians, sandwiches, calibration, or input and output. The claimed two likelihood optimizations also undercount one MAR optimization plus three joint-model starts, which is at least four optimizer runs per replicate.

*Fix:* Do not authorize the full run until an end-to-end timing pilot includes all starts, Hessians, scores, imputations, variance calculations, failure handling, and disk writes. Extrapolate wall time from complete batches and report tail runtime and aggregate memory.

**[SERIOUS] citation**

The gfoRmula citation supports the existence of random visit-process functionality, but it does not establish numerical equivalence between that implementation and the proposed last-recorded-state recursion. A stochastic gfoRmula calculation cannot agree with an exact recursion to 1e-8 unless its Monte Carlo component is removed.

*Fix:* Validate the recursion against a separate deterministic enumeration, or compare with gfoRmula using a tolerance derived from its Monte Carlo error. Document the exact mapping between the package model and the proposed state representation.

**[CITATION]** gfoRmula: An R Package for Estimating the Effects of Sustained Treatment Strategies via the Parametric g-Formula. Patterns 2020; 10.1016/j.patter.2020.100008: The work documents random measurement or visit-process support, but it does not make the custom finite-state recursion algorithmically equivalent or provide a deterministic 1e-8 validation oracle.

**[CITATION]** Kalia et al. Estimation of marginal structural models under irregular visits and unmeasured confounder: calibrated inverse probability weights. BMC Medical Research Methodology 2023; 10.1186/s12874-022-01831-2: The citation is relevant, but the protocol does not map the paper's calibration equations and weight factorization to its own visit-only exponential tilting moments and adjacent-pair weights. Unless those equations match, the proposed method should be described as an adaptation rather than the literature estimator itself.


---

## 13. OUT-01

**Verdict.** unsound

The protocol is unsound as a study meant to settle OUT-01 because it answers only a narrow, favorable mechanism experiment and cannot address the silent protocol decision, its prevalence, or the sustained recurrent-terminal method gap. Its key contrast is largely constructed by the no-death intervention and selected hazards and treatment effects. The marginal truth calculations and own-target estimators are otherwise coherent, and the variance comparison is fair. Before running, the claim, factor grid, decision rule, implementation syntax, runtime basis, and citation metadata require revision.

**[FATAL] answers-problem**

OUT-01 concerns an estimand choice being made silently during data preparation, failure to match estimators to causal questions, and unresolved recurrent-terminal estimation under sustained strategies. This study prespecifies both estimands and studies one baseline-assigned, first-event setting under favorable identification assumptions. It cannot determine whether applied emulations are silent, how often estimands are mismatched, whether death elimination is meaningful, or whether the broader estimator and reporting gaps remain. The bears_on field itself concedes that the design only answers part of the entry.

*Fix:* Either redefine the study explicitly as a mechanism experiment that quantifies one special-case estimand displacement without claiming to settle OUT-01, or add separate work capable of answering the practice, reporting, and recurrent-terminal parts. A simulation alone cannot establish the prevalence of silent censoring.

**[SERIOUS] answers-problem**

The simulated status quo is only one neighboring interpretation of censoring at death. It fits a correctly specified cause-specific Cox model and converts it to a standardized net risk. Applied analyses may instead report a cause-specific hazard ratio, a Kaplan-Meier risk, or another quantity. Results for this sophisticated net-risk implementation do not establish the consequences of the broader applied behavior described in OUT-01.

*Fix:* Name the target narrowly as standardized Cox net-risk interpretation error, or include the actual estimators and reported contrasts whose applied use motivates the entry.

**[SERIOUS] dgm-builds-in-finding**

The DGM forces the qualitative result. Conditional independence of the latent clocks, complete measurement, and the intervention that sets the death hazard to zero while leaving the primary-event hazard unchanged make the death-censored estimator correct for the no-death risk by construction. More importantly, when beta_YA and beta_YAC are zero but beta_DA is -0.510826, the no-death risk difference is exactly zero while treatment strictly increases the total primary-event cumulative incidence by preventing death whenever the death hazard is positive. The six exact-null controls cannot falsify this mechanism because they are excluded from the 18 active scenarios. The high death hazards and hazard ratios of 0.60 then tune the magnitude toward the desired thresholds.

*Fix:* Treat own-target calibration as an implementation check, not a finding. Precompute the entire displacement surface before running estimator replicates, justify factor values from an external scenario distribution, and report the resulting surface descriptively instead of treating a selected grid as evidence that the general problem is real.

**[SERIOUS] dgm-builds-in-finding**

The shared-prognosis factor is mislabeled. At gamma equal to zero, Z, M, C, and S remain common causes of both event hazards, so latent event and death times remain marginally dependent. The factor contrasts no additional Q effect with a strong additional Q effect; it does not contrast no shared prognosis with strong shared prognosis.

*Fix:* Rename the factor to additional shared Q prognosis, or set every shared covariate loading to zero at the intended none level.

**[SERIOUS] estimand**

Coverage of the death-censored interval against the total-effect truth is not coverage of that method's estimand. It is the probability that an interval for the no-death estimand happens to contain a different estimand. For every nonzero displacement this probability depends strongly on sample size and tends to zero as sample size increases, even with a perfect point and variance estimator.

*Fix:* Call this wrong-target interval inclusion rather than coverage. Make estimand displacement the primary result, keep own-target coverage as the calibration result, and report displacement relative to standard error or across several sample sizes if interval inclusion remains of interest.

**[SERIOUS] decision-rule**

The real-problem rule counts the same constructed fact multiple times. After own-target calibration, death-censored bias against the total effect is asymptotically identical to the defined estimand displacement. Wrong-target interval inclusion is then largely determined by that displacement and the fixed sample size. Requiring all three does not provide three independent pieces of evidence. The unweighted count across 18 designer-selected cells also has no interpretation as how often the problem occurs in practice.

*Fix:* Base any scenario-level classification on one estimand-displacement criterion. Analyze estimator calibration separately. Remove frequency language unless scenarios are sampled or weighted using an externally justified distribution of applied settings.

**[SERIOUS] decision-rule**

The rule can fire when coverage is far below 0.90, but 4000 replicates do not resolve the 0.90 boundary as claimed. The stated 0.00474 is a standard error, not a 95% precision bound; the approximate 95% Monte Carlo half-width at coverage 0.90 is 0.0093. An empirical result just above or below 0.90 could therefore change the verdict through Monte Carlo noise.

*Fix:* Require a binomial Monte Carlo confidence bound to lie entirely on the relevant side of 0.90, with a prespecified indeterminate zone. If a 95% half-width of 0.005 is required at 0.90, use at least about 13830 replicates per scenario.

**[MINOR] decision-rule**

Sign reversal and wrong-sign rates are undefined in the six active scenarios with a null primary-event effect and protective death effect because the no-death risk difference is exactly zero. A positive total-effect difference versus a zero no-death difference is not a sign reversal.

*Fix:* Define sign using a nonzero tolerance and classify zero-versus-nonzero contrasts separately from genuine reversals.

**[SERIOUS] feasibility**

The stated R call Surv(time, status = 1) does not create an indicator for the primary event and is not a valid literal specification of the intended model. The comparison operator is missing.

*Fix:* Specify Surv(time, event = (status == 1)) for the primary-event Cox model and the corresponding status == 2 indicator for death.

**[MINOR] feasibility**

The overnight runtime estimate is unsupported by a timed pilot and omits hardware specifications. Ninety-six thousand datasets require two Cox fits plus influence-function standardization and retained contributions; this prediction and storage work may dominate the Cox fitting. The three thousand bootstrap resamples are also not demonstrated to fit within one hour.

*Fix:* Benchmark at least 100 production-equivalent replicates and a representative bootstrap batch on the intended hardware. Report median and upper-tail wall time, peak memory, output size, worker count, and an extrapolation that includes checkpointing and serialization.

**[MINOR] citation**

The gfoRmula paper has its first two authors reversed. The lmtp package citation supports the software capability but cannot substantiate the comparative claim that it is one of only a few such implementations.

*Fix:* Correct the gfoRmula citation to begin McGrath S, Lin V, Zhang Z, et al. Support the rarity claim with a documented literature or software search, or remove that claim.

**[CITATION]** Lin V, McGrath S, Zhang Z, et al. gfoRmula: An R Package for Estimating the Effects of Sustained Treatment Strategies via the Parametric g-formula: The author order is wrong. The citation begins McGrath S, Lin V, Zhang Z, et al. The DOI and substantive use are otherwise consistent with the work.

**[CITATION]** lmtp: Non-Parametric Causal Effects of Feasible Interventions Based on Modified Treatment Policies. CRAN: The package documentation supports competing-risk functionality, but it does not establish the comparative claim that lmtp is one of only a few implementations.


---

## 14. PRO-02

**Verdict.** unsound

The protocol cannot settle PRO-02 because it replaces undocumented, sequential human protocol development with a frozen finite algorithmic search, which is the neighboring problem that existing simultaneous-inference theory already addresses. The selected superpopulation risk-difference estimand and its truth calculation are otherwise coherent, and the treatment-effect parameters do not mechanically create naive undercoverage. However, the primary coverage-loss comparator is undefined, failure handling can change coverage by the full decision threshold, and the rule incorrectly makes existence of the problem depend on a correction succeeding. The design could support a narrower study after those defects and the claimed scope are corrected.

**[FATAL] answers-problem**

PRO-02 concerns the undocumented sequence of human revisions across eligibility, comparators, grace periods, washouts, and outcome definitions. The simulation instead freezes two deterministic selectors over 4 or 16 combinations of age threshold and horizon. It assumes a known candidate family, selection rule, and tie rule, which removes the feature that makes the stated problem open. It can answer a recorded-algorithm subproblem but cannot settle PRO-02.

*Fix:* Describe the simulation as partial evidence about known finite searches and prohibit using it to close PRO-02. Addressing the stated problem requires a prospective or empirical component that records actual protocol-development paths, rejected specifications, and information viewed during each decision.

**[SERIOUS] dgm-builds-in-finding**

Success of both corrections is largely true by construction. Sample splitting makes the selected protocol independent of the analysis sample, so its marginal coverage is a mixture of fixed-candidate coverages. Bonferroni intervals are constructed so simultaneous coverage protects any selection from the declared family when the candidate pivots are valid. The simulation can reveal finite-sample failures and precision costs, but it cannot establish these principles as new findings.

*Fix:* Treat correction coverage as a calibration check. Make finite-sample tail behavior, failure rates, and precision loss the correction outcomes, and do not require correction success as evidence that naive post-selection inference has a problem.

**[SERIOUS] dgm-builds-in-finding**

The prognostic score is an oracle copy of the outcome linear predictor: R uses exactly the coefficients 0.35, 0.25, 0.50, and 0.30 appearing in eta. Results from maximizing its observed correlation with Y therefore concern perfect score-DGM alignment, not generic inspection of covariate-outcome associations. The n, lambda0, eligibility, horizon, and 70-event choices also make selection behavior depend heavily on whether expected counts lie near the cutoff. No factor varies score misspecification or distance from that boundary. The theta choices themselves do not force undercoverage because null and homogeneous scenarios are included.

*Fix:* Factorially vary prognostic-score alignment and expected event-count distance from the workability cutoff. Report the population selection probabilities or expected counts before running so conclusions cannot be driven only by tuned boundary cells.

**[FATAL] estimand**

The primary quantity called a paired coverage loss relative to candidatewise prespecified calibration has no operational definition. On replicate r, the interval for the selected k is exactly the same interval that would be labeled the fixed-k interval; using both on that replicate produces identical coverage indicators. Fixed-k coverage is instead an across-replicate quantity, so it is not a second paired outcome with the stated empirical covariance. The central five-percentage-point decision threshold therefore cannot be calculated as written.

*Fix:* Define loss as 0.95 minus selected coverage after demonstrating fixed-candidate calibration, or define an independently estimated benchmark such as the selection-frequency-weighted fixed-candidate coverage. Specify its estimator and Monte Carlo variance explicitly.

**[SERIOUS] fair-comparison**

Calibration of candidate Wald intervals only at the 1.96 critical value does not validate Bonferroni intervals in the relevant tails. The critical values are approximately 2.50 for K=4 and 2.96 for K=16. Sparse-event Wald pivots can appear calibrated at 95% while being badly calibrated at those tail probabilities, so Bonferroni success or failure could reflect tail approximation rather than selection adjustment.

*Fix:* Add fixed-family simultaneous calibration using the same Bonferroni critical values before evaluating selected coverage. Alternatively, use a simultaneously calibrated resampling procedure.

**[SERIOUS] fair-comparison**

Coverage denominators after nonconvergence are unspecified. Dropping failed replicates can alter reported coverage by nearly five percentage points, which equals the substantive decision threshold. Conditioning also differs across methods because naive inference fails only for the selected candidate, Bonferroni fails if any family member is nonestimable, and splitting can fail during either selection or analysis.

*Fix:* Predefine unconditional and conditional-on-success results. For the decision rule, use a composite success criterion that counts failure to produce an interval as failure, or otherwise prove that the chosen conditioning is common across methods.

**[SERIOUS] fair-comparison**

The split-sample procedure applies the same absolute event and sample-size thresholds to half the cohort. It consequently selects from a different protocol distribution than the full-data selector and often targets a different random estimand. Its interval width and coverage are therefore not direct correction-versus-status-quo comparisons for the same selection policy.

*Fix:* Present splitting as a different design-and-analysis policy, not merely a variance correction. Compare methods conditional on selected candidate and report policy-level target movement; do not interpret raw width or coverage differences as holding selection fixed.

**[SERIOUS] decision-rule**

The rule declares the problem materially real only if at least one correction succeeds in the same cells. Naive post-selection undercoverage remains evidence that the problem exists even if both proposed corrections fail because of sparse data, poor tail calibration, or nonconvergence. The rule therefore tests the conjunction of problem existence and remedy success rather than the stated problem.

*Fix:* Decide whether naive selection damages coverage using naive and fixed-candidate calibration alone. Evaluate each correction under a separate decision rule.

**[SERIOUS] decision-rule**

Calibration is required only for candidates selected in at least 5% of replicates. A candidate selected 4.9% of the time can have arbitrarily poor fixed-candidate coverage and still contribute directly to selected coverage. With 16 candidates, the omitted selection mass can be substantial.

*Fix:* Require fixed-candidate calibration for every estimable candidate in the declared library, or calibrate the complete selection-frequency-weighted benchmark with no per-candidate frequency exemption.

**[SERIOUS] decision-rule**

The global verdict uses pointwise 95% Monte Carlo limits across 48 cells without controlling the probability of a chance qualifying pattern. Requiring four cells is not a defined multiplicity correction, especially when cells and selectors are strongly correlated.

*Fix:* Use simultaneous Monte Carlo bounds, a prespecified global statistic with a simulation-based null distribution, or an independent confirmation run for cells that satisfy the screening thresholds.

**[MINOR] citation**

Peduzzi et al. studied events per variable for maximum-likelihood logistic regression. That result does not validate 70 pooled events as an adequacy threshold for a Hajek IPW risk difference with sandwich inference. The stated seven terms also require counting an intercept or an outcome model that is never fitted.

*Fix:* Describe 70 events solely as an arbitrary, prespecified example of investigator behavior. Do not present Peduzzi et al. as methodological support for adequacy of the proposed estimator.

**[LIMITATION] citation**

Berk et al. support the general simultaneous-coverage principle in a linear-model and model-selection setting. They do not establish finite-sample validity of normal-theory Bonferroni intervals for marginal IPW risk differences with an estimated propensity score.

*Fix:* Restrict the attribution to the generic simultaneous-inference principle and provide separate calibration or theory for the proposed IPW construction.

**[CITATION]** Peduzzi P, Concato J, Kemper E, Holford TR, Feinstein AR. A simulation study of the number of events per variable in logistic regression analysis. Journal of Clinical Epidemiology. 1996: The ten-events-per-variable result concerns logistic-regression maximum likelihood, not adequacy of Hajek IPW and sandwich inference. It cannot justify the 70-event threshold for the method being evaluated.

**[CITATION]** Berk R, Brown L, Buja A, Zhang K, Zhao L. Valid post-selection inference. Annals of Statistics. 2013: The citation supports the generic logic of simultaneous post-selection coverage, but not finite-sample validity of the specified IPW Wald-Bonferroni intervals.


---

## 15. PRO-04

**Verdict.** unsound

The protocol cannot settle PRO-04 as stated. It assumes that both targets are already coherent and named, then measures a numerical gap in three hand-built component mappings; the open problem concerns recognizing and naming the target when that work has not already been done. The severe strategy cells guarantee a material gap, MCAR validation guarantees asymptotic recovery, and the negative decision branch is impossible. The marginal estimands, paired truth computation, and influence-function variance logic are otherwise largely sound for this restricted simulation, but the implementation index, diagnostic power, and decision logic require revision before any run.

**[FATAL] answers-problem**

PRO-04 concerns detecting, naming, and reporting an operational substitution when the realized target may be only partially specified or lack a coherent intervention. This study supplies the intended and operational interventions, their measurement mechanisms, and both estimands before simulation. It therefore assumes away the central difficulty and answers the neighboring question of how large selected numerical gaps are after an expert has already solved the mapping problem. It also covers only three of seven components and does not test a reporting requirement, a language for partial interventions, or historical agreement with corresponding trials.

*Fix:* Do not present this study as settling PRO-04. Recast it as a conditional benchmark for three already formalized substitutions, or redesign the research around real conceptual-to-operational mappings with independent adjudication, all relevant protocol components, and explicit evaluation of whether the realized target can actually be named from available artifacts.

**[SERIOUS] answers-problem**

A different estimand can have exactly the same numerical value as the intended estimand. The protocol acknowledges this, but its problem-is-not-real branch is based on small absolute Delta and intended-effect coverage. Coverage of the wrong target also depends on sample size and standard error: any fixed nonzero Delta eventually produces zero coverage as sample size grows, while a very imprecise interval can cover both targets. These quantities measure numerical consequences at n = 4000, not whether substitution occurred.

*Fix:* Separate estimand identity from numerical discrepancy. Rename the negative conclusion to no important numerical discrepancy in this DGM at this sample size, treat wrong-target coverage as an illustration, and never use it to adjudicate whether PRO-04 is real.

**[FATAL] dgm-builds-in-finding**

The strategy result is guaranteed by construction. Among E = 1 under present effect modification, d1 minus d2 equals 0.08 minus 0.02 X1. With severe nondifferential coarsening, q = 0.55, so Delta equals 0.45 times the conditional mean of that quantity and must lie between 0.027 and 0.036. With severe differential coarsening, the X1-specific gaps are 0.024 and 0.036. Therefore at least one material strategy gap is certain and the rule requiring all 24 scenarios to have absolute Delta no greater than 0.01 can never fire. Negative-control cells verify algebra but do not make an existence claim noncircular.

*Fix:* Treat these cells as demonstrations rather than evidence that the problem is real. If a decision study is intended, derive the parameter grid independently of the desired threshold crossings and use a response-surface or parameter-distribution target rather than asking whether any hand-selected cell crosses 0.02.

**[SERIOUS] dgm-builds-in-finding**

Validation recovery is also largely built in. V is MCAR with known probability, the validated component is error-free, assignment probabilities are known, positivity holds, and complete follow-up is guaranteed. Under these assumptions the validation-only Hájek estimator is consistent for psi_I by construction. The simulation can study finite-sample Wald calibration, but it cannot discover whether validation recovers the intended target in the broader problem.

*Fix:* Describe this as finite-sample calibration under ideal two-phase sampling. Any broader recovery claim requires nonrandom validation, imperfect gold standards, unknown sampling probabilities, or bridge-model misspecification.

**[SERIOUS] dgm-builds-in-finding**

The accuracy and dependence factors are not factorially separated. The differential sensitivity, specificity, and strategy-mixture probabilities are not calibrated to have the same marginal accuracy as their nondifferential counterparts in the relevant target population. Consequently, a differential versus nondifferential comparison changes both dependence and average accuracy.

*Fix:* Calibrate the conditional differential parameters so their population-weighted sensitivity, specificity, or mixture fraction matches the corresponding nondifferential level. Otherwise abandon factorial main-effect language and interpret every cell only as a separate compound mechanism.

**[SERIOUS] estimand**

The silent and explicitly labeled methods say to report mu_1 minus mu_0 and use IF_1 minus IF_0, but eligibility and outcome scenarios define T as Z in the set containing 2 and 0 and specify pi_2, not pi_1. Implemented literally, these methods estimate or attempt to estimate the low-intensity contrast rather than the intended high-intensity contrast, or they fail because pi_1 is unspecified.

*Fix:* Use mu_2 minus mu_0 and IF_2 minus IF_0 for eligibility and outcome scenarios. Alternatively, explicitly recode Z = 2 to a generic active-arm indicator and use that recoding consistently in every formula and implementation.

**[SERIOUS] fair-comparison**

The paired diagnostic uses only V = 1 observations for both psi_O and psi_I even though operational variables are available for the full sample. This discards 80 percent of the information about psi_O and can manufacture indeterminacy. A failure would establish that this complete-case diagnostic is inefficient, not that a 20 percent validation design cannot distinguish the targets.

*Fix:* Benchmark the complete-case diagnostic against a standard two-phase or augmented estimator that combines the full operational sample with the validation correction and retains the relevant covariance.

**[SERIOUS] decision-rule**

The diagnostic thresholds have no supporting power calculation. At true absolute Delta = 0.02, the requirement that the point estimate itself be at least 0.02 limits changed classification probability to at most about 0.50 before applying the confidence-interval requirement. At true absolute Delta = 0.01, a calibrated 90 percent equivalence interval can lie wholly inside the margin with probability at most about 0.05. Moreover, even at Delta = 0, equivalence requires SE_Delta below approximately 0.0061, which is unlikely with roughly 800 validation records followed by eligibility and arm restrictions. The 2,500 replicates estimate this lack of power precisely but do not cure it.

*Fix:* Run a pre-study power calculation using scenario-specific SE_Delta values. Increase the sample or validation fraction, and define evaluation classes safely inside the decision boundaries, such as preserving at no more than 0.005 and changed at no less than 0.03.

**[SERIOUS] decision-rule**

The decision branches are not exhaustive. For example, calibration may pass while only the strategy family contains a material gap, silent coverage is 0.81, and fewer than half the scenarios are gray. That result satisfies neither the real, not-real, nor uninformative rule. The phrase binomial Monte Carlo intervals around scenario-count criteria is also undefined because the 24 scenarios are fixed design points, not a random sample of mechanisms.

*Fix:* Specify an ordered, exhaustive decision table covering every combination of calibration, material-gap distribution, coverage, and diagnostic performance. Define exactly how per-scenario Monte Carlo intervals propagate into each count.

**[SERIOUS] decision-rule**

Validation recovery can be declared successful using only bias and coverage. A nearly unbiased estimator with extremely wide intervals can meet both conditions while conveying little useful information, particularly because coverage often improves as intervals become less precise.

*Fix:* Add a precision requirement based on mean interval width, RMSE, or probability of resolving a prespecified clinically relevant difference.

**[MINOR] decision-rule**

The claim that the 0.01 and 0.02 margins are at least 14 times the truth MCSE does not establish reliable classification. Resolution depends on the distance between absolute Delta and the nearest boundary, not the distance between the boundary and zero.

*Fix:* Require a Monte Carlo confidence interval for each truth to lie wholly within its assigned class, or reduce truth MCSE until boundary classification is negligible.

**[MINOR] feasibility**

An overnight run is plausible because the methods require only weighted reductions, but the claimed established machine benchmark is not supplied. The estimate covers 240 million simulated person-records plus truth generation, parallel allocation, checkpointing, and summaries, so the stated one-to-two-hour replicate phase is not auditable from the protocol.

*Fix:* Record the hardware, software versions, benchmark code, rows per second, peak memory, and checkpoint cost from a representative pilot before accepting the three-to-five-hour estimate.

**[SERIOUS] citation**

No citation establishes that knowingly reporting psi_O as psi_I is the status quo analysis or how frequently this occurs. The supplied target-trial and estimand papers support explicit protocol specification; they do not establish the prevalence of the stipulated silent-labeling behavior.

*Fix:* Cite an empirical audit of reporting behavior or rename this arm a stipulated silent-labeling analysis rather than the status quo comparator.

**[MINOR] citation**

The Wang citation gives only an uninitialed first-author surname, and the Frontiers case-study citation gives no authors. Their DOIs identify works, but author attribution cannot be audited as written.

*Fix:* Supply the verified author lists and limit each claim to what the cited work directly demonstrates.

**[CITATION]** Silent operational analysis is the status quo comparator: This central characterization is uncited. None of the listed references establishes the frequency of silent estimand substitution in published target trial emulations.

**[CITATION]** Wang, et al. An operational target trial emulation framework for causal inference using electronic health records. npj Digital Medicine. 2026. 10.1038/s41746-026-02563-z: The author attribution is incomplete. The work can support operational component mapping, but it does not validate the proposed numerical accuracy bands or establish that these three simulated mechanisms are representative.

**[CITATION]** Applying the estimand and target trial frameworks to external control analyses using observational data: a case study. Frontiers in Pharmacology. 2024. 10.3389/fphar.2024.1223858: No authors are supplied. The case study supports one applied use of both frameworks, not a general reporting convention or evidence about the prevalence of silent substitution.


---

## 16. SEQ-01

**Verdict.** unsound

The protocol is unsound as a study intended to settle SEQ-01, although much of its simulation machinery is competent. Its global decision concerns accuracy for an equal-start average, so it can declare the problem absent while material start-specific heterogeneity remains, and it does not test the survival-conditioned later-eligibility claim. The diagnostic tests pooled-logit interactions rather than the declared marginal risk-difference heterogeneity, and several verdict calculations are undefined. The factorial DGM, superpopulation truth definitions, person clustering, and replicate-count arithmetic are otherwise strong.

**[FATAL] answers-problem**

The not-real rule answers whether a restricted model can estimate theta_equal adequately, not whether pooling conceals incompatible start-specific effects. It permits true Delta_RD of at least 0.02 and can declare the problem not real when the pooled average is unbiased and the diagnostic rejects. An accurately estimated average does not make the homogeneity restriction true or make trial-specific effects dispensable.

*Fix:* Separate conclusions about theta_equal accuracy, material start heterogeneity, diagnostic performance, and efficiency. Do not negate the catalog problem merely because a pooled average is accurate. Report that result as accurate averaging despite heterogeneity.

**[FATAL] answers-problem**

The survival-conditioned later-eligibility arm of SEQ-01 is not tested. With truth defined separately within each natural E_k and treatment models always correct, changing s merely changes the target populations and finite-sample weighting problem. Nothing tests the claim that validity under later eligibility depends on outcome-model correctness.

*Fix:* Either label the study as a partial answer confined to the adjudicated calendar-time arm, or add a separate experiment that crosses selective survival with outcome-model misspecification while holding treatment assignment and the target estimand fixed.

**[SERIOUS] answers-problem**

The aims claim to separate calendar-time confounding from effect modification, but every estimator models q in both weighting and outcome analysis. Crossing a and b changes whether confounding exists in the DGM, but there is no method that omits or misspecifies calendar time, so the consequences of unmodeled calendar-time confounding are never measured.

*Fix:* Add prespecified omitted, conventional, and flexible calendar-time adjustment analyses, or remove the claim that the study evaluates calendar-time confounding.

**[SERIOUS] dgm-builds-in-finding**

The s factor does not isolate risk-selective later eligibility. Setting s from 0 to 1 simultaneously turns on covariate effects in treatment initiation and failure, thereby introducing measured confounding, prognostic heterogeneity, treatment-driven depletion, survival-driven depletion, and more variable weights.

*Fix:* Use separate parameters for untreated survival selection, covariate-dependent initiation, and within-trial confounding. Hold the latter two fixed when attributing a result to survival-conditioned eligibility.

**[LIMITATION] dgm-builds-in-finding**

Calendar treatment-effect heterogeneity is imposed directly by h(S)=0.30q_S or h(S)=0.30cos(pi q_S). The linear alternative lies in the proposed spline space, and the cosine alternative is a smooth four-degree-of-freedom target. The study can estimate consequences under these imposed alternatives, but it cannot establish that material heterogeneity is a real-world problem or that these magnitudes are representative.

*Fix:* Replace the label problem is real with conditional operating-characteristic language. Any claim about empirical prevalence or realistic magnitude requires external calibration rather than additional simulation.

**[FATAL] estimand**

The diagnostic and its truth label are on different scales. The four-coefficient Wald test tests G-by-q terms in a marginal pooled-logit hazard model against exact zero, while sensitivity and specificity are defined by the range of marginal 12-month risk differences. Noncollapsibility, changing baseline risk, and changing eligible populations can make either test positive while Delta_RD is small or make Delta_RD material without the tested coefficients representing that contrast. A 0.05 test of any interaction is also not a test of the material threshold 0.02.

*Fix:* Construct the diagnostic from the standardized RD_k vector and its full person-clustered covariance. Prespecify a global contrast or simultaneous band aligned with risk differences, and distinguish testing exact homogeneity from detecting heterogeneity exceeding 0.02.

**[SERIOUS] estimand**

The four scenarios labeled negative controls by h=0 and s=0 are not exact marginal-effect nulls. The C-specific treatment odds ratios remain 0.65 and 0.85 because that interaction is not multiplied by s. When b=0.35 changes baseline risk over q, noncollapsibility alone can produce start-varying marginal hazard effects and risk differences.

*Fix:* Turn off the C-by-treatment interaction in exact null scenarios, or define negative controls solely by enumerated Delta_RD below a prespecified tolerance rather than by h and s labels.

**[SERIOUS] estimand**

theta_PT is a valid eligibility-weighted causal summary, but it is not generally the implicit target of the pooled logistic estimator. The pooled estimating equation additionally weights starts through person-time, risk-set survival, treatment and censoring weights, and model information. Equal averaging of predictions after fitting does not make the shared treatment coefficient an equal-start projection.

*Fix:* Derive and report the actual population estimating-equation projection for each restricted model. If equal-start fitting is intended, explicitly equalize start contributions in the estimating equation and evaluate that estimator separately.

**[MINOR] estimand**

The stated truth MCSE bound applies to a single arm risk, not to the maximum-minus-minimum functional Delta_RD or to classification around 0.005 and 0.02. Treating the simulated truth as fixed can misclassify scenarios near those boundaries and understates bias uncertainty.

*Fix:* Estimate the joint uncertainty of the RD_k vector by independent truth chunks, propagate it to Delta_RD, and continue truth simulation until its interval lies wholly on one side of every threshold used for classification.

**[SERIOUS] fair-comparison**

The proposed spline model is not guaranteed to represent its own DGM after marginalization. It includes G-by-follow-up and G-by-q terms but no G-by-follow-up-by-q interaction. Treatment-mediated L and C-specific effects can make the marginal calendar interaction evolve over follow-up, especially when s=1.

*Fix:* Use a sufficiently flexible three-way treatment, follow-up, and start-time surface, or model the standardized 12-month risk directly. Require the proposed estimator itself to meet the bias criterion before attributing a difference to the common-effect restriction.

**[SERIOUS] fair-comparison**

Using the same fixed-weight sandwich for every method makes relative treatment symmetric, but it does not give the inferential procedures their recommended treatment in the sparse regime. The cited Limozin study reports that the simple sandwich can be conservative and that LEF bootstrap intervals perform better in small or sparse settings. Ordinary coverage and Wald diagnostic power can therefore reflect the deliberately retained variance approximation.

*Fix:* Include LEF or person-level bootstrap inference at least in a prespecified calibration subset for both common and effect-modified estimators. Keep point-estimator and empirical-variance conclusions separate from fixed-weight Wald performance.

**[FATAL] decision-rule**

The verdict is not reproducible as written. The construction of an absolute-bias interval is undefined near zero; sensitivity and specificity are not defined as scenario-wise, equally scenario-weighted, or replicate-pooled quantities; and MCSE procedures for variance and MSE ratios are absent. Different reasonable implementations can produce different verdicts.

*Fix:* Give formulas for every bound, including truth uncertainty, absolute-bias transformation, ratio uncertainty, scenario weighting, minimum denominators, and integer rounding. Prespecify whether Monte Carlo bounds are pointwise or simultaneous.

**[SERIOUS] decision-rule**

The evidentiary standards favor the desired positive conclusion. Problem real needs either bias or coverage failure in half the material scenarios and allows either the spline or saturated estimator to succeed. Problem not real requires four simultaneous successes in 90 percent of scenarios. A saturated estimator can therefore rescue a misspecified spline and support attribution to common-effect pooling even when that attribution has not been isolated.

*Fix:* Use a symmetric hierarchy with an explicit indifference region. Require the matched spline estimator to remove the rich-common failure when claiming that the common-effect restriction caused it; treat saturated estimation only as corroboration.

**[SERIOUS] feasibility**

The 5-second replicate assumption is unsupported and implausibly optimistic for three weighted outcome GLMs on as many as 288000 rows, with rich design matrices, clustered score aggregation, and nonlinear delta calculations. Truth generation also branches up to 12 eligible starts into two 12-month strategies for 2000000 people per scenario. Six workers may encounter substantial memory contention, so the 13-to-16-hour estimate is not credible without a pilot.

*Fix:* Benchmark complete replicates in median and worst-case scenarios, including expansion, covariance, prediction, serialization, and peak memory. Separately benchmark one full truth scenario, then extrapolate using observed parallel scaling rather than ideal division by six.

**[SERIOUS] citation**

Limozin, Seaman, and Su are accurately attributed, but their results do not support treating the exact fixed-weight Wald inference used here as settled for sparse scenarios. The supplied evidence says the simple sandwich is conservative and LEF bootstrap has better coverage in the motivating regime.

*Fix:* Cite the work as evidence that repeated-person inference methods exist and that the selected sandwich has known limitations. Do not use it to validate absolute coverage or diagnostic conclusions based solely on that sandwich.

**[MINOR] citation**

The 2024 TrialEmulation preprint cannot by itself establish the exact behavior of the installed 2026 package version or the precise robust covariance implementation being emulated.

*Fix:* Add a versioned citation to the package manual and source release used to define the package-like comparator, including the exact version and relevant implementation location.

**[CITATION]** Limozin L, Seaman SR, Su L. Statistical Methods in Medical Research. 2025. DOI 10.1177/09622802251356594: The attribution and topic are correct, but the paper does not validate the simple fixed-weight sandwich as the preferred procedure in the sparse setting. Its reported conservatism and LEF results must qualify the protocol's Wald coverage and diagnostic claims.

**[CITATION]** Su L, et al. TrialEmulation. arXiv:2402.12083: The preprint supports the general expansion, weighting, and pooled-MSM approach, but it is not sufficient evidence for exact behavior of a later installed package version. A versioned source citation is required.

**[CITATION]** DeMonte, Shook-Sa and Hudgens. arXiv:2403.18115: The work supports calendar-varying effects, trial-specific reporting, and a homogeneity test in nested vaccine trials. It does not validate this protocol's four-degree-of-freedom pooled-logit Wald test as a detector of a marginal risk-difference range of 0.02.


---

## 17. TZO-01

**Verdict.** unsound

The protocol is unsound as a study intended to settle TZO-01, although it could support a narrower CCW implementation study. It retains exact weekly histories and changes only how long known treatment deviations remain uncensored, so it does not study the full temporal-resolution problem or its fine-grid tradeoff. It explicitly does not select a grace period, and the nonnull outcome models make delayed endpoint censoring harmful by construction. The marginal estimands, superpopulation truths, outcome masking, sandwich variances, and primary Monte Carlo precision are otherwise well specified.

**[FATAL] answers-problem**

The candidate grids do not change the resolution of the treatment, observation, covariate, or nuisance-model histories. Every analysis retains exact weekly treatment decisions and fits the same weekly initiation model; the grid only determines how long a known prohibited initiation remains in the gDelay risk set. The study therefore answers whether deliberately delayed artificial censoring creates bias, not how to select the temporal resolution of a target-trial emulation. It also removes the fine-grid nuisance-model and weight-instability tradeoff named in TZO-01, making the one-week grid essentially free.

*Fix:* Either narrow the claim to within-interval artificial-censoring error under weekly decisions, or construct separately coarsened data versions in which each method observes and models only the information available at its grid resolution. A genuine selector study must include the statistical or computational cost of fine grids and compare valid estimators fitted at each resolution.

**[FATAL] answers-problem**

The protocol explicitly says it cannot select a clinically meaningful grace period. DeltaG measures the difference between two distinct causal estimands; it is not a procedure for choosing G. Consequently, the design addresses only part of a problem that asks for selection of the time grid or grace period and a measure of movement under alternatives.

*Fix:* Describe the study as resolving only the grid-diagnostic subproblem. Settling the grace-period component would require a separately defined clinical or decision-theoretic criterion using information beyond treatment and observation intensities; process data alone cannot identify a uniquely meaningful G.

**[SERIOUS] dgm-builds-in-finding**

The coarse-grid discrepancy is generated by construction. A prohibited start is known at its weekly boundary, but the endpoint estimator retains subsequent outcomes in the gDelay arm. Those outcomes are then generated under an instantaneous treatment effect: hazard ratios 0.60 and 0.80 under immediate benefit, and 1.40 and 1.60 for the first two weeks followed by 0.55 and 0.75 after week 6 under the biphasic profile. Wider bins mechanically retain treated follow-up for longer. The exact-null cells are useful controls, but they do not make the nonnull finding an emergent property of grid selection.

*Fix:* Interpret these cells only as stress tests of delayed censoring. Add independently calibrated mechanisms with delayed, smooth, negligible, and differently aligned effect onset, and apply each method to honestly coarsened observables. Do not use the resulting count of affected cells as evidence about prevalence in practice.

**[SERIOUS] fair-comparison**

The method labeled status quo is denied ordering information that the simulated data contain. Recommended CCW practice censors a clone when a known protocol deviation occurs before accepting later outcomes. Here the four-week method knows the weekly start time but waits until the interval endpoint, while the benchmark uses the correct order. That is a deliberately degraded hybrid implementation, not an established status quo comparator.

*Fix:* If exact ordering is available, give the fixed-grid method exact deviation censoring. If the intended setting has only coarsened records, remove exact ordering from every method's inputs and implement the convention recommended for such data. Label endpoint-delayed censoring as a stress-test method unless literature establishes it as routine practice.

**[SERIOUS] fair-comparison**

The adaptive rule is not required to improve on the trivial outcome-blind rule of always choosing one week, even though one week agrees with exact ordering and carries no increased nuisance-model burden in this DGM. It also consumes an additional 1000-person design sample. The selector could therefore be declared a partial solution while being dominated in bias, precision, or total data requirements by a prespecified finest-grid analysis.

*Fix:* Include always-one-week and resource-equivalent fixed-grid comparators. Require the selector to deliver a prespecified efficiency, computation, or data-use advantage without materially worsening bias or coverage.

**[SERIOUS] decision-rule**

Mean M is the expected range of four noisy estimates, not the range of their expected values. Because max minus min is nonnegative, mean M can exceed 0.02 even when all grid estimators have identical expectations. Its Monte Carlo confidence interval only estimates that noise-inflated quantity precisely. The real-problem rule can therefore fire because alternative analyses fluctuate, rather than because grid choice creates systematic movement.

*Fix:* Base the decision on paired mean differences or the range of scenario-specific expected estimates. If within-dataset multiverse spread remains an applied diagnostic, calibrate it against its null distribution and do not let it alone establish grid-induced bias.

**[SERIOUS] decision-rule**

The thresholds 0.01, 0.02, six of 24 scenarios, and 22 of 24 scenarios have no clinical or decision-theoretic justification. The 24 cells are hand-selected factorial conditions, not a probability sample from a domain; paired grace-period cells are correlated, and outcome profiles repeat the same treatment and visit laws. Counting cells cannot support a prevalence-like conclusion that the problem is practically real.

*Fix:* Justify materiality from a named application or utility scale, and define a distribution or weighting over mechanisms before summarizing across cells. Otherwise make only cell-specific conclusions.

**[SERIOUS] decision-rule**

The diagnostic sensitivity and specificity rule is underdefined and poorly resolved. The threat section implies that the unit is the 24 scenario cells, in which case 2000 replicates reduce within-cell Monte Carlo error but do not increase the number of validation mechanisms. Point sensitivity and specificity of 0.80 can then rest on only a few cells with very wide binomial uncertainty. O4 also counts the same post-deviation outcomes that directly create the endpoint discrepancy, making its association with M partly mechanical.

*Fix:* Define the classification unit explicitly, validate the fixed cutoff on a separate and substantially larger collection of mechanisms, and require lower confidence bounds rather than point sensitivity and specificity to exceed the target.

**[MINOR] decision-rule**

Two thousand replicates give coverage MCSE 0.00487 and an approximate 95% Monte Carlo half-width of 0.0095. This is adequate for detecting gross undercoverage, but the selector-success rule classifies raw coverage estimates at 0.93 and 0.97 without using their Monte Carlo intervals, so results close to either boundary will be classified arbitrarily.

*Fix:* Use one-sided Monte Carlo bounds or an explicit indifference region for the coverage criterion.

**[SERIOUS] feasibility**

The stated wall-time is unsupported and likely optimistic without compiled-kernel benchmarks. The design entails up to about 10 billion analysis-sample person-weeks, another 2.5 billion design-sample person-weeks, about 10 billion regime-person-weeks for truth generation, 24000 large weekly GLMs, joint scores for multiple grids and grace periods, and several sensitivity analyses. Completing this in roughly 6 to 10 wall-clock hours on six workers requires performance that has not yet been demonstrated.

*Fix:* Treat the runtime as unknown until timing both representative full replicates and the truth kernel. Extrapolate worker-hours separately for generation, fitting, scoring, sensitivity analyses, serialization, and expected reruns; include uncertainty rather than only a point range.

**[MINOR] citation**

The Epidemiology citation with DOI 10.1097/EDE.0000000000000043 is repeatedly attributed to Sperling. The first author is Sperrin, not Sperling.

*Fix:* Correct the author name everywhere and supply the complete reference.

**[SERIOUS] citation**

DOI 10.1002/pds.5071 concerns a specific systematic review of 14 DPP-4 inhibitor studies. Its reported 0-to-180-day range and absence of sensitivity analyses support a statement about that review sample, not the general clinical plausibility of four- and twelve-week grace periods across an unspecified target-trial domain.

*Fix:* Name the review and its population, restrict the claim to that evidence base, and calibrate G to a defined clinical application before calling either value practically meaningful.

**[MINOR] citation**

The PDS and Wanis references are given as descriptions rather than auditable bibliographic citations. The Wanis conceptual use is appropriate, but the protocol should cite the full work and its published version rather than only a generic label and arXiv URL.

*Fix:* Supply authors, title, year, journal or repository, and stable identifier for both references.

**[CITATION]** Sperling et al.; DOI 10.1097/EDE.0000000000000043: Wrong author surname. The cited paper is by Sperrin et al., not Sperling et al.

**[CITATION]** Pharmacoepidemiology and Drug Safety systematic review; DOI 10.1002/pds.5071: The reference is bibliographically incomplete, and evidence from 14 DPP-4 inhibitor studies is generalized beyond that review's setting.

**[CITATION]** Wanis et al.; arXiv:2212.11398: The conceptual attribution is appropriate, but the citation lacks a title, year, full author information, and the available published-version details.

