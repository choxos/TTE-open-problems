# Study queue

43 of 43 catalog problems triaged. 17 are target trial emulation problems that a simulation or case study could answer; they are the program, in order.

## Why entries are excluded

| reason | n |
| --- | --- |
| needs analytic, not a simulation or case study | 9 |
| not a target trial emulation problem | 8 |
| needs corpus, not a simulation or case study | 5 |
| needs consensus, not a simulation or case study | 3 |
| needs software, not a simulation or case study | 1 |

## The program

| # | id | problem | scope | methods | type | answers | feas | catalog priority |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | [CNF-01](../../audit/registry/problems.json) | Convergence of treatment in the comparator arm attenuates the ob | core | intention-to-treat-analogue, sustained-strategies, clone-censor-weight | simulation | yes | 5 | High |
| 2 | [BEN-02](../../audit/registry/problems.json) | Replication is reported as a binary label rather than as a calib | core | trial-benchmarking, estimand-alignment | simulation+case | yes | 3 | High |
| 3 | [GMT-01](../../audit/registry/problems.json) | Cross-validation for longitudinal nuisance models optimizes pred | core | marginal-structural-model, parametric-g-formula, longitudinal-tmle, sequential-cross-fitting | simulation | partly | 3 | Very high |
| 4 | [TZO-01](../../audit/registry/problems.json) | No outcome-blind procedure selects the time grid or the grace pe | core | clone-censor-weight, sequential-nested-trials, continuous-time-g-computation, marginal-structural-model | simulation | partly | 3 | Very high |
| 5 | [PRO-04](../../audit/registry/problems.json) | An unobservable protocol component produces a different, data-de | core | protocol-specification, estimand-mapping, trial-benchmarking | simulation+case | partly | 1 | Very high |
| 6 | [PRO-02](../../audit/registry/problems.json) | Inference conditions on a fixed target trial that was in fact se | core | protocol-specification, clone-censor-weight, sequential-nested-trials | simulation | partly | 4 | High |
| 7 | [SEQ-01](../../audit/registry/problems.json) | Sequential emulation creates repeated participation and calendar | core | sequential-nested-trials, pooled-outcome-model, person-clustered-sandwich, person-level-bootstrap | simulation | partly | 3 | High |
| 8 | [GMT-04](../../audit/registry/problems.json) | No estimator is defensible as a default, and no study is require | core | IPTW, marginal-structural-models, parametric-g-formula, iterated-conditional-expectation, g-estimation, longitudinal-targeted-learning | simulation+case | partly | 2 | High |
| 9 | [LRN-05](../../audit/registry/problems.json) | A counterfactual prediction is validated under the assumptions t | core | counterfactual-prediction, artificial-censoring, inverse-probability-weighting, sustained-strategies | simulation | partly | 3 | Medium-high |
| 10 | [MER-01](../../audit/registry/problems.json) | Phenotypes enter emulations as error-free binary variables | applies | clone-censor-weight, IPTW, marginal-structural-models, parametric-g-formula, longitudinal-targeted-learning | simulation | partly | 3 | Very high |
| 11 | [MIS-01](../../audit/registry/problems.json) | The visit process is treated as a nuisance to be imputed rather  | applies | inverse-intensity-of-visit-weighting, marginal-structural-models, parametric-g-formula, longitudinal-targeted-learning | simulation | partly | 3 | Very high |
| 12 | [LRN-01](../../audit/registry/problems.json) | Flexible estimation is presented as a remedy for identification  | applies | IPTW, parametric-g-formula, longitudinal-targeted-learning, modified-treatment-policies | simulation | partly | 4 | High |
| 13 | [OUT-01](../../audit/registry/problems.json) | Censoring at death is applied as data cleaning rather than as an | applies | sustained-treatment-strategies, parametric-g-formula, longitudinal-targeted-learning, competing-risks | simulation | partly | 3 | High |
| 14 | [DTA-02](../../audit/registry/problems.json) | Averaging site estimates in a federated emulation can conceal th | applies | federated-estimation, transportability, component-validation | simulation+case | partly | 2 | High |
| 15 | [ELG-01](../../audit/registry/problems.json) | An unrecorded eligibility criterion is indistinguishable from a  | applies | eligibility-modeling, multiple-imputation, inverse-probability-weighting, partial-identification | simulation+case | partly | 2 | High |
| 16 | [GMT-03](../../audit/registry/problems.json) | Large databases yield small effective samples after eligibility, | applies | clone-censor-weight, IPTW, marginal-structural-models | simulation | partly | 4 | Medium-high |
| 17 | [ELG-02](../../audit/registry/problems.json) | Eligibility criteria built from healthcare-use variables can ind | applies | eligibility-specification, causal-graph-auditing | simulation | partly | 3 | Medium-high |

## The first twelve, in detail

### 1. CNF-01 Convergence of treatment in the comparator arm attenuates the observational intention-to-treat analogue with follow-up length

*High priority, catalog verdict `overstated`, scope `core`, feasibility 5, triage confidence high*

**Design sketch.** Target the risk difference for assignment to initiate at baseline versus not initiate at baseline at horizons from 1 to 10 years. Vary delayed initiation in the comparator arm and treatment-effect persistence, then measure attenuation relative to the true assignment-effect curve and assess whether observed treatment-trajectory summaries predict that attenuation.

**Sequencing.** Run early because it is inexpensive, directly interpretable and capable of producing a practical diagnostic relating treatment convergence to horizon-specific attenuation.

### 2. BEN-02 Replication is reported as a binary label rather than as a calibrated comparison of estimands

*High priority, catalog verdict `overstated`, scope `core`, feasibility 3, triage confidence high*

**Design sketch.** Estimate whether candidate agreement measures recover known concordance while independently varying estimand mismatch, trial standard error, emulation standard error and true effect heterogeneity. Apply the measures to existing paired trial-emulation results and compare binary labels with effect differences, effect ratios, standardized discrepancies and prediction-interval coverage.

**Sequencing.** This is a clean and consequential early study because binary agreement rules can be shown to fail under controlled conditions and replaced with interpretable graded summaries.

### 3. GMT-01 Cross-validation for longitudinal nuisance models optimizes prediction, not causal performance

*Very high priority, catalog verdict `partially-addressed`, scope `core`, feasibility 3, triage confidence high*

**Design sketch.** Target a sustained-strategy risk difference while varying treatment positivity, treatment-confounder feedback, nuisance-model misspecification and informative observation. Select nuisance learners using predictive loss, longitudinal balance, weight dispersion and estimated remainder criteria, then compare causal bias, interval coverage and estimator failure rates.

**Answers only part.** Determine which observable model-selection criteria best predict causal performance across prespecified longitudinal data-generating mechanisms; no finite simulation can establish a universally optimal causal cross-validation loss.

**Sequencing.** Run early with a narrowed estimator set because this is a direct, decision-relevant simulation, although a four-estimator comparison with extensive machine-learning libraries would exceed one week.

### 4. TZO-01 No outcome-blind procedure selects the time grid or the grace period

*Very high priority, catalog verdict `partially-addressed`, scope `core`, feasibility 3, triage confidence high*

**Design sketch.** Estimate the 5-year risk difference under a sustained initiation strategy while varying treatment latency, visit intensity, within-interval event ordering, and true adherence behavior. Select grids using masked treatment and visit intensities, vary grace periods from 0 to 180 days, and compare methods on bias, interval coverage, ordering conflicts, and regret relative to the best prespecified specification.

**Answers only part.** A simulation can compare outcome-blind selection rules and quantify sensitivity to grids and grace periods, but it cannot recover the clinically meaningful interval or grace period from treatment and observation processes alone.

**Sequencing.** Run this early because it offers a decisive comparison of prespecified procedures, while presenting any selected grid as a performance rule rather than a universal truth.

### 5. PRO-04 An unobservable protocol component produces a different, data-defined estimand rather than a noisy version of the intended one

*Very high priority, catalog verdict `partially-addressed`, scope `core`, feasibility 1, triage confidence medium*

**Design sketch.** Start from emulations with randomized-trial benchmarks, then systematically remove or coarsen observability of eligibility, strategy, outcome and follow-up components while writing the resulting estimand explicitly. Compare each substituted estimand with the intended trial estimand using population overlap, intervention-support loss, effect-estimate discrepancy and benchmark calibration.

**Answers only part.** A study can determine how selected component substitutions alter estimands and benchmark agreement in chosen settings, but cannot establish universal criteria separating innocuous operational refinements from changes of scientific question.

**Sequencing.** This is highly important but should not run first because credible benchmarking across multiple component substitutions needs substantial data access and methodological work.

### 6. PRO-02 Inference conditions on a fixed target trial that was in fact selected after seeing the data

*High priority, catalog verdict `partially-addressed`, scope `core`, feasibility 4, triage confidence high*

**Design sketch.** Estimate a sustained-strategy risk difference after selecting among candidate eligibility thresholds, grace periods and washout windows using sample size, event prevalence or covariate-outcome associations. Compare naive, split-sample and outcome-blinded procedures on coverage, type I error, bias and power.

**Answers only part.** A simulation can establish the inferential cost of explicit protocol-selection rules and compare design splitting or blinded design against naive inference, but cannot correct undocumented human searches in general.

**Sequencing.** Run this early because it is a clean, decisive simulation of a distinctly emulation-specific source of undercoverage.

### 7. SEQ-01 Sequential emulation creates repeated participation and calendar-time confounding that its efficiency gain conceals

*High priority, catalog verdict `overstated`, scope `core`, feasibility 3, triage confidence high*

**Design sketch.** Estimate a pooled 5-year risk difference from sequential nested trials while varying calendar trends, treatment-effect modification by trial start, repeated eligibility, and survival-dependent re-entry. Compare naive, person-clustered, and person-bootstrap inference on bias, 95% interval coverage, and effective efficiency relative to a single baseline trial.

**Answers only part.** A simulation can determine the bias, coverage, and efficiency consequences of repeated participation, calendar-time heterogeneity, and alternative variance estimators under specified mechanisms, but it cannot establish that later eligibility is innocuous across all outcome models.

**Sequencing.** Run this early because it is a clean, consequential simulation even though the catalog statement overstates how unsettled person-level dependence is.

### 8. GMT-04 No estimator is defensible as a default, and no study is required to show that its choice mattered

*High priority, catalog verdict `partially-addressed`, scope `core`, feasibility 2, triage confidence high*

**Design sketch.** Target the same 5-year sustained-strategy risk difference with weighting, outcome-modeling and doubly robust estimators while varying treatment-confounder feedback, nuisance-model misspecification and positivity. Measure bias, coverage, convergence and failure signaling, then reanalyze one published emulation and quantify between-estimator disagreement.

**Answers only part.** A common benchmark can identify which estimator families are reliable under named failures and show whether choice matters in a real emulation, but no finite benchmark can establish a universally defensible default.

**Sequencing.** The problem is important but too broad for an early one-week study; first restrict it to a small set of estimators and prespecified failure modes.

### 9. LRN-05 A counterfactual prediction is validated under the assumptions that produced it, and nothing maps its output to a decision

*Medium-high priority, catalog verdict `partially-addressed`, scope `core`, feasibility 3, triage confidence high*

**Design sketch.** Simulate longitudinal treatment, time-varying confounding, and survival outcomes under sustained strategies; vary the strength of an omitted confounder and practical positivity while comparing IPW estimates of calibration, time-dependent AUC, c-index, and Brier score with their oracle counterfactual values on bias, interval coverage, and diagnostic sensitivity.

**Answers only part.** A simulation can quantify how counterfactual calibration, discrimination, and Brier-score estimators degrade under specified exchangeability and positivity violations, but it cannot validate those assumptions or determine how predictions should map to treatment decisions.

**Sequencing.** The catalog rating overstates its readiness as one problem; the operating-characteristics component is a clean early simulation, while assumption validation and decision mapping require separate questions.

### 10. MER-01 Phenotypes enter emulations as error-free binary variables

*Very high priority, catalog verdict `partially-addressed`, scope `applies`, feasibility 3, triage confidence high*

**Design sketch.** Estimate the 5-year risk difference between sustained treatment strategies while varying time-specific sensitivity, specificity, differential misclassification and validation-sample size for treatment and confounder histories. Compare thresholded, corrected and latent-variable analyses on regime-effect bias, interval coverage and weight distortion.

**Answers only part.** A simulation can characterize how repeated phenotype error propagates through artificial censoring, longitudinal weights and regime-effect estimates, including validation-sample requirements under specified transport assumptions.

**Sequencing.** Prioritize this relatively early because the longitudinal propagation mechanism is specific, important and amenable to a decisive simulation.

### 11. MIS-01 The visit process is treated as a nuisance to be imputed rather than as part of the causal structure

*Very high priority, catalog verdict `partially-addressed`, scope `applies`, feasibility 3, triage confidence high*

**Design sketch.** Estimate a 5-year sustained-strategy risk difference while varying the effects of prior treatment, latent severity and impending outcome on visit intensity. Compare last observation carried forward, imputation, inverse-intensity weighting and joint latent-state methods using bias, coverage, visit-model calibration and weight dispersion.

**Answers only part.** A study can compare methods under explicit treatment-dependent and severity-dependent visit mechanisms, but cannot identify a universally correct visit model when latent severity is unrestricted.

**Sequencing.** This is a strong target trial emulation problem, but its joint data-generating mechanism makes it a second-wave study after simpler weighting experiments.

### 12. LRN-01 Flexible estimation is presented as a remedy for identification failure

*High priority, catalog verdict `partially-addressed`, scope `applies`, feasibility 4, triage confidence high*

**Design sketch.** Estimate a sustained-strategy 5-year risk difference while varying the fraction and geometry of unsupported treatment-history regions and learner flexibility. Score diagnostics by sensitivity and specificity for unsupported predictions, then assess estimator bias, coverage and falsely reassuring interval rates.

**Answers only part.** A study can evaluate whether support diagnostics detect interpolation, practical positivity failure and extrapolation in longitudinal histories; it cannot empirically settle the already established fact that flexible estimation does not repair nonidentification.

**Sequencing.** Run an explicitly diagnostic study early, but do not frame the established identification principle itself as an unanswered simulation question.

