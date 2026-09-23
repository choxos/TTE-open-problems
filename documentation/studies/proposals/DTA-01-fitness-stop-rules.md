# DTA-01: how often a published emulation carries a data-fitness criterion that could have stopped it

**Catalog problem.** Data-fitness assessment is narrative and has no thresholds that would stop a study. Verdict `overstated`; triage: corpus, answerable in part, feasibility 1, depends on BEN-02.

**Residual claim this design tests.** The adjudicated restatement: outside tightly gated regulatory or network feasibility processes, many published emulations assert data suitability narratively, and no field-standard, protocol-component fitness score with prespecified stop rules exists, is routinely published when it fails, or has been validated against trial concordance. The entry's stronger half, that quantitative fitness assessment does not exist at all, is already refuted in the audit trail by CARE (Levy 2026), SPIFD2 (Gatto 2023), the substance-use feasibility study with its 80% ascertainability rule (Janda 2024) and the thresholded OHDSI checks (Blacketer 2021). This design does not retest it.

## Questions

**A.** Among applied emulations published from January 2024 to June 2026, what fraction report a data-fitness criterion that is quantitative, tied to a protocol component, and carries a threshold that the report says would stop or did change the study? How often is a failed fitness assessment the published result?

**B.** Can component-level fitness be scored reliably from a registered protocol and a data-source description alone, and do scores assigned without sight of the results track the size of the trial-emulation discrepancy across the RCT-DUPLICATE pairs?

## What this leaves unanswered

Which threshold is correct for a given decision; that is normative and belongs to REG-01. Whether gating happens before publication in sponsor, network or regulatory pipelines: the corpus sees only what was printed, so a low prevalence in print is compatible with studies being stopped unseen. Whether fitness scores validate outside one claims-based, largely cardiometabolic benchmark program. The entry's statement that a pipeline without stop rules always returns an estimate is a claim about software and is not tested.

## Design, part A: prevalence in the shared applied-emulation sample

### Sampling frame

This frame and the drawn sample are shared with REG-03 and SFW-03, which apply their own extraction forms to the same papers; sharing is an owner decision and saves about two thirds of screening and full-text acquisition. PubMed, through E-utilities `esearch`, with the query exactly:

```
(("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) AND ("2024/01/01"[dp] : "2026/06/30"[dp]) AND english[la]) NOT (review[pt] OR systematic review[pt] OR meta-analysis[pt] OR editorial[pt] OR comment[pt] OR letter[pt] OR news[pt])
```

It returned 1,321 records on 2026-09-23; 847 (64%) carry a PMC identifier and have free full text. The phrases are the ones the repository's harvest (`build/lit/search.py`) measured PubMed to index as phrases; wording such as "emulate a target trial" is split into words by PubMed and is not used. The PMID list is frozen with its retrieval date, and the frozen list is the frame.

Two strata by the earlier of the electronic and print dates in the PubMed record: S1, 2024-01-01 to 2025-09-22 (before the TARGET statement, published 2025-09-23); S2, 2025-09-23 to 2026-06-30. A record dated to the year only is assigned by year where that is unambiguous (2024 to S1, 2026 to S2); a record dated only "2025" is excluded from sampling and counted. Because S2 includes papers submitted before TARGET appeared, each paper is also coded for whether it cites TARGET, which is the sharper marker for the before and after contrast.

Each stratum's PMIDs are permuted with a registered seed (`set.seed(20260923)`, then `x[sample.int(length(x))]`) and screened in that order until 100 eligible papers per stratum are reached. Screening a random order to a quota yields a simple random sample of eligible papers within each stratum. Expected screening load at an eligibility fraction near 0.65 is about 310 abstracts and 230 full texts.

### Inclusion

Included: a study in humans estimating the effect of a health intervention or treatment strategy on an outcome, using routinely collected, registry or cohort data, that describes itself as emulating a target trial or as a trial emulation. Feasibility studies whose result is a fitness verdict are included; they are positive cases for item F4. Because the sample is drawn once, they are also in the REG-03 and SFW-03 samples, where they have no effect claim and no estimation pipeline; those forms code them "not applicable", exclude them from their denominators, and report the count.

Excluded: papers whose stated aim is a method, with the application illustrative; protocols without results; benchmarking studies that emulate an existing randomized trial to compare results (the part B population); duplicate reports of one analysis (the first is kept); conference abstracts. Two screeners work independently at both stages; disagreements go to a third.

### Extraction items (DTA-01 form)

- **F1, fitness statement class**, the highest level the report reaches. 0: the data source is described and nothing is said about its suitability for this protocol. 1, narrative: suitability is asserted without a measured quantity ("well suited", "previously validated" with no figure). 2, quantitative without a threshold: at least one measured quantity bearing on whether a protocol component can be operationalized in these data, such as completeness of an eligibility variable, the fraction of trial criteria ascertainable, the positive predictive value or sensitivity of an outcome or exposure algorithm in this source, continuity of capture, or eligible counts per arm against a required size. 3, quantitative with a decision threshold: a class 2 quantity with a threshold the report states would stop, or did change, the study. A power calculation counts as class 3 only when stated as a gate on proceeding. Covariate balance and propensity-score overlap are analysis diagnostics (REG-02) and count only when stated as a gate on whether the question can be asked in these data.
- **F2, prespecification** of a class 3 threshold: in a registered protocol that predates the analysis (registry and date), stated as set before outcome analysis, or neither.
- **F3, component** addressed by any class 2 or 3 quantity: eligibility, treatment strategy or assignment, time zero, outcome, capture and follow-up, confounders.
- **F4, result of the fitness assessment**: passed; failed and the study stopped, so the report is the negative result; failed and the protocol changed (quote what changed); failed and the study proceeded unchanged.
- **F5, validation source** for an outcome or exposure algorithm: none, the same database, an external source.

The primary item is F1 = 3.

### Part A2: census of published negative fitness verdicts

A second PubMed query, exactly:

```
("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) AND (feasibility[tiab] OR "fit-for-purpose"[tiab] OR "fitness"[tiab] OR "emulability"[tiab] OR "emulable"[tiab] OR "not feasible"[tiab] OR "could not be emulated"[tiab]) AND ("2016/01/01"[dp] : "2026/06/30"[dp]) AND english[la]
```

It returned 60 records on 2026-09-23, and retrieves CARE, SPIFD2 and Janda 2024. It does not retrieve Sloot 2024, which concluded from ten negative control outcomes that its comparative effectiveness question should not be run in its data and which the repository's reading records as a published negative fitness assessment, so verdicts reached through diagnostics rather than a feasibility framing are missed and the census is a lower bound. Every F4 "failed and stopped" paper found in part A is added. From each included report: the number of candidate trial and database combinations assessed, the number judged not emulable, the criterion that failed (quote), and whether its threshold was prespecified.

### Extraction record and verification

Every item is one JSON record: `{"paper": PMID, "item": "F1", "value": 3, "quote": "...", "locator": "Methods, Data source, paragraph 2", "extractor": "E1", "source_file": "..."}`. A positive value carries a verbatim quote and a locator (section and paragraph, or table or supplement item). An absence value (F1 = 0 or 1) instead carries the sections read and the output of a scripted search of the full text and supplements for a registered term list (feasib, fitness, fit-for-purpose, complete, missing, validat, positive predictive, sensitivity of, ascertain, capture, continuous enrollment, threshold, criterion); every hit is shown to both extractors, and absence stands only when both confirm that no hit qualifies.

Text is extracted with `pdftotext` into the study's scratch directory, one file per paper, and read from the file. Records are appended one paper at a time by a script in the pattern of `build/lit/add_finding.py`. Quotes are checked against the text with the collapsed-text matcher already in `build/lit/verify_quotes.py` (import `norm`, `split_elisions`, `spans` and `coverage`; do not reimplement them); a quote that returns NOT-FOUND voids its item value until corrected.

Two extractors independently extract F1, F2 and F4 for every paper; F3 and F5 are double-extracted on a random 25%. A third reviewer adjudicates disagreements seeing both records and the text. Cohen's kappa and Gwet's AC1 are reported per item; an item with kappa below 0.60 is reported as unreliable and cannot enter a decision rule.

### Sample size

100 eligible papers per stratum, 200 in all. The overall prevalence is weighted by stratum (frame count times the observed eligibility fraction); with two strata of similar weight the Kish design effect is below 1.05, so the operating characteristics below, computed for a simple random sample of 200 with Wilson intervals, hold approximately. They are exact binomial sums over the number of positive papers, classifying each outcome by where its Wilson interval falls. Under the decision rule below: at a true prevalence of 0.06 the "real" branch is reached with probability 0.99, at 0.08 with 0.88; at 0.40 the "not real" branch is reached with probability 0.86, at 0.45 with 0.99; at 0.20 the result is always intermediate, which is the correct report for a middling prevalence. The S1 and S2 contrast (100 each, two-sided 0.05) has power 0.80 for 0.10 against 0.25.

## Design, part B: reliability and predictive validity of component scores

**Pairs.** The 32 RCT-database pairs of RCT-DUPLICATE (Wang 2023), whose emulation protocols were registered on ClinicalTrials.gov before analysis. The discrepancy outcome per pair is the log ratio of the database and trial estimates with its standard error, taken from the published results; 29 pairs report hazard ratios (Heyard 2024) and enter the regression, and all 32 enter the reliability analysis. BEN-02 showed that a binary agreement label moves with precision alone at a fixed true discrepancy, so no binary agreement label is used as an outcome.

**Instrument.** Six components scored 0 to 3 against anchors written before scoring: eligibility observability (fraction of trial criteria operationalizable, key criteria named), treatment-start observability (for example, initiation in hospital, which claims do not record), comparator support (an active comparator available, or placebo emulated by nonuse), outcome validity (a validated algorithm in the same data type), capture continuity, and measurement of the confounders the trial protocol names. The anchors are piloted on three benchmark pairs from outside RCT-DUPLICATE, taken from the pair frame defined in the EST-05 proposal (or, if that is not run, from its PubMed benchmark query), and then frozen.

**Blinding.** Three pharmacoepidemiologists who state in writing that they have not read the RCT-DUPLICATE results each score every pair from the ClinicalTrials.gov registration of the emulation, the trial's methods with results redacted, and the database documentation. Blinding cannot be verified for published results; after scoring, raters record which pairs' results they recall, and the association is repeated without those pairs.

**Analysis.** B1: two-way random-effects ICC(2,1) per component and for the summed score, with 95% intervals. B2: random-effects meta-regression, `d_i ~ N(b0 + b1 * s_i, tau^2 + v_i)` by REML, where `d_i` is the log ratio of hazard ratios, `s_i` the mean summed score and `v_i` the sampling variance; the reported quantities are `b1` and the proportional reduction in `tau^2`, alongside the Spearman correlation between the fitness deficit (the summed score reversed, so that higher means worse fitness) and the absolute standardized difference. Heyard 2024 already found that three design-emulation differences explain most of the heterogeneity in these pairs; the three are reported for context, and the question here is whether prospectively scored data-fitness components carry the same signal.

**Power.** With 29 pairs, a two-sided test at 0.05 reaches power 0.80 only for a correlation of magnitude 0.50 or more. Part B is therefore a reliability study with an underpowered validity check, and it says so.

## What would show the problem real or not real

**Part A.**
- Real: the upper 95% bound of the weighted prevalence of F1 = 3 is below 0.15. Fewer than one report in seven exposes a criterion that could have returned no, which is the entry's claim about practice.
- Not real: the lower bound exceeds 0.30. Gating with a stated threshold is common published practice and the entry's practice claim is wrong rather than overstated.
- Intermediate: the interval lies within 0.15 to 0.30 or straddles either bound; reported as the estimate with no verdict. Uninformative: F1 kappa below 0.60.
- A2 is a count with no threshold: the number of published not-emulable verdicts and the share of assessed combinations they represent.

**Part B.**
- Instrument reliable: the lower 95% bound of the summed-score ICC is at least 0.60. Instrument unreliable: the upper bound is below 0.60, meaning fitness cannot be scored reproducibly from documents with these anchors, so any stop threshold placed on such a score would be arbitrary. This supports the entry.
- Validity supported: the lower 95% bound of the correlation between fitness deficit and absolute standardized difference exceeds zero. Validity not supported for practical use: its upper bound is below 0.30. Anything else is uninformative. With 29 pairs and a Fisher-z interval, a true correlation of zero reaches the "not supported" branch with probability of only about 0.35, and a moderate correlation usually lands in neither; the validity result is expected to be uninformative, which is why the decision-bearing result of part B is reliability.

## Cost

Person-hours, with the shared screening counted once: shared screening about 50 and full-text acquisition about 17 (both charged once across DTA-01, REG-03 and SFW-03); F1 to F5 extraction, 200 papers at 15 minutes by two extractors, 100; adjudication 10; the A2 census 25; part B instrument and anchors 20, pilot 6, scoring 32 pairs by 3 raters at 40 minutes, 64, outcome extraction 16; analysis and write-up 30. DTA-01 alone: about 270 hours, 340 if the shared screening is charged here. Compute is under one CPU-hour. Data access: institutional full text for the roughly 36% of the frame outside PMC; ClinicalTrials.gov and the published RCT-DUPLICATE results are public.

## Threats to validity

The frame depends on self-labeling, so emulations that do not use the phrases are missed; the prevalence is for labeled emulations. Publication filters out gated studies, which biases part A toward the entry's claim; A2 and the "failed and stopped" code only partly offset this. The boundary between class 2 and class 3 is where extractors will disagree; the anchors above and the kappa floor are the protection. Part B uses one benchmark program built on US claims with trials selected for emulability, whose results are published, so blinding is imperfect and the range of fitness is restricted, which attenuates any association.

## Citations

- Levy N, Sheridan P, Campbell U, et al. Systematic Evaluation of Data and Trial Fitness for Oncology Trial Emulation: Empirical Findings from the CARE Initiative. Clinical Pharmacology & Therapeutics. 2026;120(2):440-451. doi:10.1002/cpt.70310
- Gatto NM, Vititoe SE, Rubinstein E, Reynolds RF, Campbell UB. A Structured Process to Identify Fit-for-Purpose Study Design and Data to Generate Valid and Transparent Real-World Evidence for Regulatory Uses. Clinical Pharmacology & Therapeutics. 2023;113(6):1235-1239. doi:10.1002/cpt.2883
- Janda GS, Jeffery MM, Ramachandran R, Ross JS, Wallach JD. Feasibility of using real-world data to emulate substance use disorder clinical trials: a cross-sectional study. BMC Medical Research Methodology. 2024;24(1):187. doi:10.1186/s12874-024-02307-1
- Blacketer C, Defalco FJ, Ryan PB, Rijnbeek PR. Increasing trust in real-world evidence through evaluation of observational data quality. Journal of the American Medical Informatics Association. 2021;28(10):2251-2257. doi:10.1093/jamia/ocab132
- Sloot R, Breskin A, Colantonio LD, et al. Comparing PCSK9 Monoclonal Antibody Treatment Strategies Following Myocardial Infarction Using Negative Control Outcomes: A Target Trial Emulation Study. Epidemiology. 2024;35(4):579-588. doi:10.1097/EDE.0000000000001730
- Wang SV, Schneeweiss S, RCT-DUPLICATE Initiative, et al. Emulation of Randomized Clinical Trials With Nonrandomized Database Analyses. JAMA. 2023;329(16):1376. doi:10.1001/jama.2023.4221
- Heyard R, Held L, Schneeweiss S, Wang SV. Design differences and variation in results between randomised trials and non-randomised emulations: meta-analysis of RCT-DUPLICATE data. BMJ Medicine. 2024;3(1):e000709. doi:10.1136/bmjmed-2023-000709
- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334(12):1084. doi:10.1001/jama.2025.13350
