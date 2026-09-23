# DTA-03: how far a protocol-defined contrast moves when only the code system under its variables changes, and whether routine diagnostics see it

**Catalog problem.** Common data models harmonize structure without guaranteeing that the same variable means the same thing. Verdict `partially-addressed`; triage: case study, answerable in part, feasibility 2, scope `no` (a general data-infrastructure problem).

**Bearing on target trial emulation.** An emulation's eligibility, treatment and outcome are exactly the variables whose code-level meaning drifts, so a target trial emulation inherits this error unchanged and cannot see it from its own protocol; this study measures its size on one protocol-defined contrast.

**Residual claim this design tests.** The audit accepted that a common data model standardizes representation without guaranteeing semantic equivalence, and that mapping histories are rarely published. Codex qualified two parts: drift is not necessarily invisible, because prevalence discontinuities, coding transitions and shifts in associations can flag it; and linkage error is not generically confounded. Interrupted time series studies already show that the ICD-9-CM to ICD-10-CM transition changed the measured frequency of coded conditions (Slavova 2018; Hsu 2021), CLIF (Rojas 2024) builds a common intensive care format, and open data-quality checks for OMOP databases test conformance, completeness and plausibility (Blacketer 2021), none of which establishes that a populated, plausible column carries the intended clinical meaning. What is not shown is whether such a change moves a causal contrast, and whether the diagnostics an analyst can run without the mapping history detect the changes that do. This study answers both in one source where the ground truth for one variable is recoverable from laboratory values.

## Questions

**Q1.** In one electronic health record source whose diagnosis coding changed from ICD-9-CM to ICD-10-CM during the study period, how much do eligibility counts, outcome ascertainment and a protocol-defined risk difference change across a prespecified finite set of defensible code definitions (native lists per code system, forward and backward General Equivalence Mapping translations, and standard-concept definitions from an OMOP conversion of the same source)?

**Q2.** How much do they change when one source of ascertainment is left out (diagnosis codes, laboratory values, medication orders)?

**Q3.** Do three diagnostics that need no mapping history (prevalence ratio against a laboratory anchor by coding era, agreement with the laboratory reference by era, and stability of the phenotype's association with fixed anchor covariates) flag every definition choice that moves the estimate materially?

## What this leaves unanswered

Probabilistic linkage error, which needs a linked multi-source database (an optional arm is described but not costed); semantic heterogeneity across sites of a network; how often material drift occurs in published emulations; and any proof of semantic equivalence, which no single-site reanalysis can supply.

## Data

MIMIC-IV (Johnson 2023), version fixed at protocol registration, through credentialed PhysioNet access. It records the ICD version of every hospital diagnosis, laboratory measurements and medication orders; calendar dates are shifted per patient, so the coding era is defined by the recorded ICD version, not by calendar date. The OMOP conversion arm uses the public MIMIC-IV to OMOP transformation at a fixed release. Access requires human-subjects training and a signed data use agreement; this is the owner's decision.

**Optional linkage arm (owner's decision, not costed).** A licensed database with separately held primary care, hospital and death records would add leave-one-source-out and linkage-threshold axes. It is not required for Q1 to Q3.

## Design

**Protocol held fixed.** Adults admitted with type 2 diabetes; treatment strategies are a scheduled basal insulin order within 24 hours of admission versus sliding-scale insulin only; outcome is hypoglycemia within 7 days of admission; risk difference by inverse probability weighting on a fixed baseline set (age, sex, admission type, prior-year admissions, first glucose and creatinine, HbA1c when measured). Medication strategies are defined from normalized drug names and route, not from drug codes, so the treatment definition does not change with a coding era. The clinical question is chosen because its outcome has a laboratory reference (glucose) and its code definitions differ structurally between systems: ICD-9-CM records hypoglycemia in diabetes largely through residual "other specified manifestation" codes, while ICD-10-CM has specific codes. A clinician fixes every code list in the first work package, before any estimate is computed.

**Definition arms (prespecified, finite).**

| arm | eligibility | outcome |
|---|---|---|
| A0 native | ICD-9-CM list in ICD-9 era, ICD-10-CM list in ICD-10 era | same rule |
| A1 forward map | ICD-9-CM list, translated by forward GEM in the ICD-10 era | same rule |
| A2 backward map | ICD-10-CM list, translated by backward GEM in the ICD-9 era | same rule |
| A3 standard concept | OMOP condition concept set with descendants, both eras | same rule |
| A4 laboratory outcome | as A0 | laboratory glucose below 70 mg/dL (reference) |
| A5 codes only | as A0 | codes only, no laboratory component |
| A6 broadened eligibility | codes, or a diabetes drug order, or HbA1c at least 6.5% | as A0 |

The laboratory reference is serum or plasma glucose from the laboratory table only; point-of-care values are excluded so that the reference does not change with bedside device changes.

**Paired comparisons.** Every arm is applied to the same admissions. Arms A1 and A2 are compared with A0 within one coding era, on identical patients, so the difference isolates mapping semantics from secular change in care. Cross-era comparisons are reported but are not decision-bearing because they confound the code system with calendar time.

**Estimates.** For each arm: eligible, treated and outcome counts; sensitivity, positive predictive value and kappa of the code outcome against the laboratory reference, by era; the weighted risk difference; and the paired difference from A0 with a 2000-draw admission-level bootstrap that resamples patients once for all arms. Simultaneous 95% intervals across the six contrasts use the max-t method on the bootstrap draws.

**Diagnostics (prespecified flags, computed without the mapping).**

- D1 anchor ratio: the ratio of code-defined to laboratory-defined outcome prevalence differs between eras by more than 25% (bootstrap interval excludes the band 0.80 to 1.25).
- D2 agreement: kappa against the laboratory reference differs between eras by at least 0.10 (interval excludes zero difference and the point difference is at least 0.10).
- D3 association: the odds ratio of the code phenotype with a fixed anchor (first glucose below 70 mg/dL) differs between eras by a ratio outside 0.80 to 1.25.

A definition choice is flagged if any diagnostic fires for the variable it changes.

## What would show the problem real, not real, or leave it undecided

- **Material change.** The simultaneous interval for an arm's paired difference from A0 lies wholly outside plus or minus 0.01 on the risk-difference scale. **No material change**: it lies wholly inside plus or minus 0.005.
- **Real and invisible (entry supported as stated).** At least one of A1, A2, A3, A5, A6 makes a material change, and at least one material change is not flagged by D1 to D3.
- **Real but visible (codex's qualification supported).** Material changes exist and every one is flagged.
- **Not real in this source.** Every arm shows no material change.
- **Uninformative.** Any interval crosses a margin; fewer than 5000 eligible admissions or fewer than 100 laboratory-defined outcome events in either era; or the coding era cannot be separated from a concurrent change in the laboratory reference (a step in laboratory glucose testing frequency of more than 20% between eras).

Both substantive branches are reachable: a GEM translation that maps a residual ICD-9-CM category onto several ICD-10-CM codes can change outcome ascertainment in either direction, and whether that moves a weighted contrast depends on whether the misclassification is associated with treatment, which is what the study measures. The size requirement follows from the paired design: if 2% of admissions change outcome class between two arms, the paired standard error of the difference is about sqrt(0.02/n), 0.002 at n = 5000.

## Cost

About 165 person-hours: access and training 15, code lists with a clinician 25 (plus 10 clinician hours), extraction pipeline 60, diagnostics and analysis 30, reporting 25. Compute is under 10 CPU-hours: 2000 bootstrap draws over seven arms of weighted estimators on at most a few tens of thousands of admissions. Data cost is nil beyond credentialing.

## Threats to validity

- Date shifting prevents a calendar interrupted time series; the design relies on within-era paired comparisons instead.
- The coding transition coincides with other institutional changes; this affects only cross-era comparisons, which are descriptive.
- The laboratory reference is itself a phenotype; hypoglycemia treated before a laboratory draw is missed. This biases agreement measures toward lower sensitivity equally across arms and eras.
- Forward and backward maps are approximate by design; the study measures their consequence and does not treat either as correct.
- One center and one clinical question: the result is an existence or bound statement for this source, not a prevalence.
- Code lists fixed by one clinician could favor one system; a second clinician reviews both lists blind to the estimates.

## Citations

- Johnson AEW, Bulgarelli L, Shen L, et al. MIMIC-IV, a freely accessible electronic health record dataset. *Scientific Data*. 2023;10(1). doi:10.1038/s41597-022-01899-x
- Slavova S, Costich JF, Luu H, et al. Interrupted time series design to evaluate the effect of the ICD-9-CM to ICD-10-CM coding transition on injury hospitalization trends. *Injury Epidemiology*. 2018;5(1):36. doi:10.1186/s40621-018-0165-8
- Hsu M, Wang C, Huang L, et al. Effect of ICD-9-CM to ICD-10-CM coding system transition on identification of common conditions: an interrupted time series analysis. *Pharmacoepidemiology and Drug Safety*. 2021;30(12):1653-1674. doi:10.1002/pds.5330
- Rojas JC, Lyons PG, Chhikara K, et al. A Common Longitudinal Intensive Care Unit data Format (CLIF) to enable multi-institutional federated critical illness research. medRxiv preprint, 2024. doi:10.1101/2024.09.04.24313058
- Blacketer C, Defalco FJ, Ryan PB, Rijnbeek PR. Increasing trust in real-world evidence through evaluation of observational data quality. *Journal of the American Medical Informatics Association*. 2021;28(10):2251-2257. doi:10.1093/jamia/ocab132
