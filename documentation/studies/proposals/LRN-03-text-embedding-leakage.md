# LRN-03: when a note embedding used as a baseline covariate leaks treatment information, and which check can tell

**Catalog problem.** Learned embeddings from clinical text can carry post-treatment information into a baseline adjustment set. Verdict `overstated`; triage: simulation plus case study, answerable in part, feasibility 2, not a target trial emulation problem.

**Bearing on target trial emulation.** Time zero is the protocol element that defines what "baseline" means; this study measures what happens when the text entering a baseline adjustment set was written, or describes events, after time zero, which is the same problem in a point-treatment cohort and in an emulation.

**Residual claim this design tests.** Treatment leakage in text-as-confounder analyses is defined in prior work (Daoud 2022), and grok recorded a 2026 preprint with distillation methods and a leakage sensitivity analysis; it has no CrossRef record and is not cited. An operational emulation framework proposes language processing for eligibility and phenotyping with no leakage audit (Wang 2026). Codex narrowed the entry: the risk comes from the timing and content of the text, not from representation learning; a deterministic embedding of baseline text stays baseline; and the entry's proposed audit (does the embedding predict treatment better than structured covariates?) cannot separate leakage from legitimate confounder information or from instruments. GLM noted that "no test distinguishes" overstates impossibility when it means no standard test. What survives: nobody has measured, for a fixed estimand, how much each kind of leaked content (a recorded treatment decision, an early response on the causal path, a post-treatment marker that is a collider) biases or destabilizes an embedding-adjusted estimate, how much a timing lock costs in lost confounder information, and whether any check with access to the text's timestamps detects the harmful cases. This design measures those.

## Questions

**Q1.** For a point-treatment risk difference, how much bias and variance does an embedding of notes timestamped before time zero add when a fraction of them carries decision, mediator or collider content, relative to an embedding of strictly locked notes?

**Q2.** What is the sensitivity and specificity of three checks for harmful leakage: the entry's audit (incremental treatment-prediction AUC over structured covariates), the same AUC increment measured against the locked embedding, and a lock-shift test on the effect estimate?

**Q3.** In a real ICU database, how often do notes charted before time zero describe the treatment or were stored after it?

## What this leaves unanswered

Language models and their pretraining corpora are not simulated: the encoder is a fixed linear map, so the study says nothing about leakage through encoder weights trained on the same patients' later notes (flagged as a threat in the case study). Imaging and device data; time-varying treatments; proximal uses of text, which need their own identification conditions (codex). No general leakage test is sought, since the triage records that none can exist without timing information.

## Simulation design

### Data-generating mechanism

Structured covariates `X1, X2, X3 ~ N(0, 1)`, `X4 ~ Bernoulli(0.4)`; `U ~ N(0, 1)`, severity recorded only in notes; `Q ~ N(0, 1)`, an unrecorded cause of the outcome. Treatment at time zero: `A ~ Bernoulli(expit(-0.5 + 0.4*X1 + 0.3*X2 + 0.3*X4 + 0.8*U))`. Post-treatment variables: an early response on the causal path, `R ~ Bernoulli(0.5-0.2*A)`; a marker caused by treatment and by `Q`, `M = 0.8*A + 0.8*Q + N(0, 1)`. Outcome at 30 days: `P(Y = 1) = 0.05 + 0.5*expit(-1.5 + 0.3*X1 + 0.3*X3 + 0.8*U + 0.8*Q)-0.03*A + 0.10*R`, which stays in [0.02, 0.65].

Notes: each patient has `1 + Poisson(3)` notes with timestamps before time zero, each a bag of about 60 words over a 400-term vocabulary. Word log-rates are a fixed background plus topic loadings (20 terms per topic, fixed once): a severity topic scaled by `w_U*U` and a structured-covariate topic scaled by `0.5*X1` in every note. A contaminated note, chosen with probability `rho`, adds one of: a decision topic scaled by `gamma*(2A-1)` (the note documents the treatment decision made in the last 6 hours before time zero); a response topic scaled by `gamma*(2R-1)` (a late entry describing the early response, backdated); or a marker topic scaled by `gamma*M`.

Encoder: fixed before any replicate from an independent corpus of 20,000 notes generated with random intensities on every topic (so the map spans all content and was not fit to any study label): TF-IDF with that corpus's inverse document frequencies, then projection on its top 32 singular vectors. A patient's embedding is the projection of the pooled TF-IDF of their notes.

Locked notes: the patient's notes whose timestamp precedes time zero by at least 6 hours and whose storage time precedes time zero. By construction they contain no contaminated content and lose one eighth of clean notes.

Factors: leakage type (decision, mediator, collider) by `rho` in {0.1, 0.3} by `gamma` in {1, 3} with `w_U = 1` (12 scenarios); the same 6 type-by-`rho` combinations at `gamma = 3` with weak note information `w_U = 0.3` (6); and no leakage at `w_U` in {1, 0.3} (2). 20 scenarios, `n = 5000`.

### Estimand and truth

The 30-day risk difference for treatment versus no treatment at time zero, a total effect including the path through `R`: `-0.03 + 0.10*(-0.2) = -0.05` exactly, from the additive outcome law, in every scenario.

### Methods

All use two-fold cross-fitted AIPW with propensities truncated to [0.01, 0.99] and influence-function Wald intervals. Nuisance models are ridge logistic (propensity) and ridge linear (outcome) regressions on standardized inputs; the penalty for each input set is chosen once per scenario by 5-fold cross-validation on 20 pilot datasets that are not reused, then frozen.

- **T0, structured.** Inputs `X`. Status quo without text.
- **T1, oracle.** Inputs `X` and `U`. Implementation benchmark.
- **T2, naive embedding.** Inputs `X` and the embedding of all notes timestamped before time zero.
- **T3, locked embedding.** Inputs `X` and the embedding of locked notes.
- **T4, treatment-direction removal.** T2 after projecting the embedding off its cross-fitted treatment-predictive direction, the simplest form of the distillation idea.

Checks, each computed on every replicate:

- **D1, the entry's audit.** Cross-fitted propensity AUC with `X` and the naive embedding minus AUC with `X` alone; flags above 0.02.
- **D2, lock-contrast AUC.** AUC with `X` and the naive embedding minus AUC with `X` and the locked embedding; flags above 0.02.
- **D3, lock-shift test.** T2 minus T3, with the variance of the difference of their influence functions; flags when the 95% interval excludes zero.

Failure: nonconvergent ridge logistic fit, nonfinite estimate or standard error. Counted, not dropped.

### Performance

**Primary.** (a) The excess bias and excess root mean squared error of T2 over T3 in each leakage scenario. (b) For D1, D2 and D3: sensitivity, the flag rate in scenarios where T2 is harmful, defined as T2's root mean squared error exceeding T3's by at least 25% or its bias exceeding T3's by at least 0.01 in absolute value, each by a Monte Carlo interval; specificity, one minus the flag rate in the two no-leakage scenarios.

**Secondary.** Bias, empirical and model standard errors, coverage and width for T0 to T4; T4 against T2 and T3; T3 against T1, which is the price of locking.

### Replicates

1000 per scenario, 20,000 in all, planned and reported in the ADEMP structure (Morris 2019). Estimator standard deviations were 0.010 to 0.027 in the check below, so bias has a Monte Carlo standard error of at most 0.0009; flag rates have worst-case Monte Carlo standard error 0.016.

### Gates, with a scratch check

A numpy implementation (ridge penalty fixed at 10 rather than tuned; 20 to 30 replicates per cell) was run for this proposal. T0 was biased by +0.038 to +0.047 in every configuration, and T1 within 0.005 of the truth. Without leakage T2 cut T0's bias to +0.005 to +0.009 at `w_U = 1` and +0.016 at `w_U = 0.3`; T3 kept +0.008 to +0.011 at `w_U = 1` and +0.017 at `w_U = 0.3`. Decision leakage at `rho = 0.3` raised the propensity AUC from 0.71 to 0.90 and doubled T2's standard deviation (0.027 against 0.012), as conditioning on a strong predictor of treatment does (Myers 2011); at `rho = 0.1` the AUC was 0.77. Mediator leakage at `rho = 0.3, gamma = 3` moved T2 to -0.028, a bias of +0.022 against T3's +0.014, with the AUC essentially unchanged (0.72 against 0.71 without leakage). Collider leakage left T2 within 0.002 of the truth in every configuration tried, closer than without leakage. D1's increment was about 0.09 without any leakage, so its specificity is expected to be near zero whenever notes carry confounder information: that part of Q2 confirms codex and is reported, not decided. The mediator case shows harm without an AUC signal, and the collider case shows content that is harmless here, so whether D2 and D3 separate harmful from harmless leakage is open.

Registered gates: T0 bias at least 0.02 in every scenario; T1 coverage at least 0.93 in every scenario; without leakage at `w_U = 1`, T2 removes at least half of T0's bias. If a gate fails the study stops for implementation review.

## What would show the problem real or not real

- **Real**: at `rho = 0.1` for at least one leakage type, T2 is harmful as defined above; and neither D2 nor D3 reaches sensitivity of at least 0.80 with specificity of at least 0.90 (Wilson bounds), so no check with timestamp access separates harmful from harmless leakage.
- **Not real, as a detection problem**: D2 or D3 reaches sensitivity of at least 0.80 and specificity of at least 0.90. Leakage can still harm, but a timing-based check that any analyst with timestamps can run detects it, and the entry's "no test distinguishes" is refuted in favor of codex's position that provenance, not predictiveness, is the evidence.
- **Not real, as a harm problem**: T2 is not harmful in any scenario at `rho = 0.1` and harmful in at most two at `rho = 0.3`: realistic leakage fractions then do not move a dense embedding enough to matter in this mechanism.
- **Uninformative**: a gate fails.

## Case study: MIMIC-III notes around vasopressor initiation (Q3)

**Data.** MIMIC-III (Johnson 2016), credentialed access through PhysioNet (training certificate and data use agreement, no fee), whose notes table records a chart time and a separate storage time for each note. The owner decides whether to pursue credentialing; the simulation stands without the case study.

**Target trial.** Adults on their first ICU stay in the MetaVision era of the database, still in the ICU and not on vasopressors at hour 6 after admission; treatment: norepinephrine started between hours 6 and 12, from the MetaVision input events table, versus not; outcome: death within 30 days. Time zero is hour 6 for everyone.

**Measures.** (a) The share of notes charted before time zero but stored after it, by note category. (b) Decision leakage: the share of initiators and non-initiators with a note charted before time zero that mentions norepinephrine or a vasopressor by a prespecified term list, and the difference between the two. (c) D1, D2 and D3 as in the simulation, with the encoder fit on notes of patients outside the cohort, locking by storage time before time zero and chart time at least 6 hours before it. (d) T0, T2 and T3 estimates, reported as a sensitivity comparison with no truth.

**What it can show.** Whether decision leakage and backdated storage occur at the rates the simulation's `rho` levels assume, and whether the checks behave on real text as they do on synthetic text. A widely used clinical encoder (Alsentzer 2019) was pretrained on MIMIC notes, including later notes of these same patients; using it would add a leakage path through the weights, so the case study uses the independently fit encoder as primary and reports the pretrained one only as a sensitivity analysis.

## Cost

Compute: the numpy check cost 0.61 CPU-seconds per replicate for four estimators, including note generation and embedding, on the loaded machine. On this machine a single-penalty `glmnet` fit at `n = 5000` took 0.01 CPU-seconds and a 5-fold `cv.glmnet` ridge logistic fit 3.3. With frozen penalties, a replicate of five estimators is about 20 single-penalty fits plus generation, about 1 CPU-second: 20,000 replicates need about 6 CPU-hours; penalty tuning, 20 scenarios by 20 pilot datasets by 6 input sets, about 2 more. Budget 15 CPU-hours. Case study: extraction and term matching under 5 CPU-hours; the optional pretrained encoder a few CPU-hours for the cohort's pre-time-zero notes. Person-hours: simulation code and tests 40; credentialing and case study 50; analysis and write-up 30.

## Threats to validity

The encoder is linear and fixed, which makes leakage easier to dilute than for an encoder tuned on outcomes; results are specific to that choice. Contamination is modeled as whole notes; real leakage is often one sentence in an otherwise clean note, which the `gamma` factor approximates. The locked embedding is assumed free of leakage, which is true by construction here and depends on storage times being trustworthy in real data. Additive risk models make the truth exact and favor linear outcome regressions. The case study's term list will miss paraphrases, so decision leakage there is a lower bound.

## Citations

- Daoud A, Jerzak C, Johansson R. Conceptualizing Treatment Leakage in Text-based Causal Inference. Proceedings of the 2022 Conference of the North American Chapter of the Association for Computational Linguistics: Human Language Technologies. 2022:5638-5645. doi:10.18653/v1/2022.naacl-main.413
- Wang Y, Li Y, Lin T, Guo Y. An operational target trial emulation framework for causal inference using electronic health record data. npj Digital Medicine. 2026;9:424. doi:10.1038/s41746-026-02563-z
- Myers JA, Rassen JA, Gagne JJ, Huybrechts KF, Schneeweiss S, Rothman KJ, et al. Effects of Adjusting for Instrumental Variables on Bias and Precision of Effect Estimates. American Journal of Epidemiology. 2011;174(11):1213-1222. doi:10.1093/aje/kwr364
- Johnson AEW, Pollard TJ, Shen L, Lehman LH, Feng M, Ghassemi M, et al. MIMIC-III, a freely accessible critical care database. Scientific Data. 2016;3:160035. doi:10.1038/sdata.2016.35
- Alsentzer E, Murphy J, Boag W, Weng W-H, Jindi D, Naumann T, McDermott M. Publicly Available Clinical BERT Embeddings. Proceedings of the 2nd Clinical Natural Language Processing Workshop. 2019:72-78. doi:10.18653/v1/W19-1909
- Morris TP, White IR, Crowther MJ. Using simulation studies to evaluate statistical methods. Statistics in Medicine. 2019;38:2074-2102. doi:10.1002/sim.8086
