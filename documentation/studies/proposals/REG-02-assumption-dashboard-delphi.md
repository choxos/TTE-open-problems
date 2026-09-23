# REG-02: a consensus assumption dashboard, and whether reviewers can use it

**Catalog problem.** There is no assumption dashboard, so diagnosable and undiagnosable assumptions are reported alike. Verdict `partially-addressed`; triage: consensus, answerable in part, feasibility 1.

**Residual claim this design tests.** The audit (codex) found the entry's testable versus untestable split too coarse. Observed data cannot establish exchangeability or consistency; empirical positivity problems, nuisance-model behavior and measured-covariate balance can be investigated, but finite-sample diagnostics cannot establish population positivity or model correctness; measurement validity needs labeled, replicated or external data; and balance is a property of the fitted analysis rather than a causal assumption. A dashboard can reveal or falsify particular problems and cannot certify identification. What survives: no standard panel exists, TARGET asks authors to describe the assumptions for each estimand without asking which of them any diagnostic bears on (Cashin 2025; the repository's reading of item 7g), and an unreported diagnostic cannot be told apart from an unrun one. The Delphi items below therefore ask, for each diagnostic, which identification requirement it bears on, what it can reveal, and what it cannot establish, never whether an assumption is "testable".

## Questions

**Q1.** Can methodologists, editors and assessors agree, for each candidate diagnostic in a longitudinal emulation, on the requirement it bears on, what it can reveal and what it cannot establish; on which panels a report must carry; and on one summary statistic for longitudinal balance and one for support by treatment history?

**Q2.** Does the resulting dashboard let independent reviewers detect a diagnostic that was run and not reported, and map diagnostics to requirements, better than reading the report as published?

**Q3.** In published longitudinal emulations, how often does the text present a diagnostic as establishing a requirement it cannot establish?

## What this leaves unanswered

Adoption by journals or regulators, which needs an adopting body. Whether a chosen summary statistic is the best one; that is a simulation question, and the Delphi only fixes a convention. Nothing here makes an untestable assumption testable.

## Design, stage 1: modified Delphi

### Panel

Four groups, recruited by invitation and nomination: causal-inference statisticians and pharmacoepidemiologists who have published a longitudinal emulation or a methods paper on g-methods (15); journal editors and statistical reviewers who handle emulation manuscripts (8); regulatory and health technology assessment reviewers (7); maintainers of software for weighting, balance or emulation (5). Target 35, floor 25 completing round 3. With 25 raters one panelist moves an agreement percentage by 4 points, so no single person decides a 70% rule.

### Round 0

A steering group of three drafts the candidate list from the entry's proposed direction, the repository's reading findings, and the causal roadmap's requirement that every identification assumption be delineated (Dang 2023). Diagnostic panels: covariate balance at each time by treatment history; effective sample size by arm and time; weight distribution, tails and truncation; support by treatment history (person-time with low estimated probability of following the assigned strategy); artificial-censoring rates by arm and time; missingness by variable and time; phenotype validity from a validation source; comparison of the modeled natural course with the observed data; negative control outcomes or exposures; sensitivity analysis for unmeasured confounding (for example the E-value of VanderWeele and Ding 2017, or a tipping point); alternative model specifications. Identification requirements, the rows every panel is mapped to: consistency with well-defined strategies; baseline exchangeability; sequential exchangeability; positivity; no informative censoring given the measured covariates; measurement validity; correct model specification.

### Rounds 1 to 3

For each candidate panel, each panelist gives: (a) inclusion in the required core, on a 1 to 9 scale; (b) the requirement or requirements it bears on, multi-select from the rows; (c) its function, one of "can reveal a violation", "quantifies sensitivity to a violation", "describes the fitted analysis only"; (d) what it cannot establish, free text in round 1 and coded into options for rounds 2 and 3. For longitudinal balance and for support by history, panelists also choose among candidate summaries and propose a reporting cut point. Balance options: the maximum absolute standardized mean difference over times and history strata after weighting; the history-adjusted approach of Jackson 2016; a person-time weighted average over times. Support options: the share of person-time with estimated probability below 0.025, below 0.01, the minimum probability, or effective sample size by history stratum. After each round panelists see the group distribution and anonymized rationales. No item is rated after round 3. Reported under ACCORD (Gattrell 2024).

### Agreement thresholds

- Core inclusion: at least 70% rate 7 to 9 and at most 15% rate 1 to 3; exclusion symmetrically.
- Mapping: at least 75% select the same requirement set, and the same function code.
- Summary statistic: at least 70% choose one option; otherwise "no agreed summary" is itself the reported result for that component.

### Output that counts as a solution

Dashboard version 1: a fixed two-part layout. The first part lists every identification requirement with the argument or external evidence the report offers for it and the sensitivity analysis that bears on it, under the heading that these cannot be established from the study data. The second part lists the core diagnostic panels, each labeled with the requirement it bears on and what it cannot establish, in a fixed order, with an empty panel printed as "not reported" rather than omitted. Delivered as a template document and a machine-readable field list.

## Design, stage 2: validation

### Reports

40 published longitudinal emulations that use weights or the g-formula (inverse probability of censoring weights, clone-censor-weight, marginal structural models, sequential trials with weights, parametric g-formula). They are drawn from the shared applied-emulation sample defined in DTA-01, REG-03 and SFW-03 if that is run (owner decision); otherwise from the same PubMed query and seeded random order, screening to a quota of 40 such reports.

A steering-group pre-audit ranks the reports by how many candidate panels they report. The 20 most complete are seeded: in each, one reported panel is removed from the text and supplements, which creates an omission whose truth is known. The removed panel is chosen at random among those that are the only reported diagnostic bearing on their requirement in that report, so that the omission is visible at the requirement level as well as the panel level; a report with no such panel is replaced by the next most complete. Seeded reports exist only in seeded form. The other 20 are used as published.

### Reviewers and allocation

Eight methodologists not on the Delphi panel. Each assesses 20 reports: 10 with the dashboard template, which they complete from the report, and 10 without it, answering for each requirement "a diagnostic bearing on it is reported", "not reported" or "cannot tell". Allocation is randomized so that every report is assessed by two reviewers in each condition and no reviewer assesses the same report in both conditions: 40 reports by 4 assessments is 160, which is 8 reviewers by 20.

### Outcomes

- **O1, omission detection**: among assessments of seeded reports, the share that detects the omission. In the dashboard condition, detection is marking the removed panel "not reported"; in the other condition, it is marking the removed panel's requirement "not reported" or "cannot tell" rather than "reported". 40 opportunities per condition, analyzed paired by report.
- **O2, mapping accuracy**: the share of reviewer mappings from diagnostic to requirement that match the Delphi key.
- **O3, reliability**: kappa between the two reviewers of a report on each panel's status, dashboard condition.
- **O4, conflation**: in the 40 reports as published, the share with at least one statement that a diagnostic established a requirement it cannot establish according to the Delphi key (for example, that a balance table showed there was no unmeasured confounding). Coded by two people independently, adjudicated by a third.

### Extraction record and verification

O4 statements and every pre-audit panel status are JSON records `{"paper", "item", "value", "quote", "locator", "extractor", "source_file"}`, each positive value with a verbatim quote and a locator, checked with the collapsed-text matcher in `build/lit/verify_quotes.py` (import `norm`, `split_elisions`, `spans`, `coverage`) against `pdftotext` output kept one file per paper in a scratch directory; records are appended one paper at a time. A "not reported" status in the pre-audit carries the sections read and a scripted term search of text and supplements (balance, standardized, effective sample, weight, truncat, positivity, overlap, censor, missing, validat, negative control, E-value, tipping, natural course). The seeding key, which panel was removed from which report, is held by one steering member and released only after all assessments are in.

### Sample size

O1: 40 detection opportunities per condition. If the dashboard raises detection from 0.40 to 0.85, the paired difference is estimated with a 95% interval of roughly plus or minus 0.19, so the two conditions separate clearly; a difference of 0.15 would not be resolved, which is acceptable because only a large gain would justify a mandatory template. O4 with 40 reports: at a true share of 0.40 the lower 95% bound is near 0.26.

## What would show the problem real or not real

- **Real**: without the dashboard, O1 detection has an upper 95% bound below 0.50, meaning reviewers cannot tell an unreported diagnostic from an unrun one, which is the entry's central claim; or O4 has a lower 95% bound above 0.20.
- **Not real**: without the dashboard, O1 has a lower bound above 0.80 and O4 an upper bound below 0.10. Reports already make omissions visible and rarely overclaim.
- **Solution**: Delphi consensus on the core panels and on the mapping of every core panel, and with the dashboard O1 at least 0.80 with lower bound at least 0.65, O2 at least 0.80, and O3 kappa at least 0.60.
- **Premise contested**: mapping consensus fails for three or more core panels after round 3. The separation the entry assumes is then not agreed among specialists, which supports the audit's critique; the dashboard is released as a layout without the separation claim.
- **Uninformative**: fewer than 25 panelists complete round 3, or reviewer kappa is below 0.40 in both conditions.

## Cost

Person-hours: steering group, candidate list 20, round materials and analysis 75; report selection and pre-audit 40; seeding 30; reviewer assessments, 160 at 40 minutes, 107 (paid); O4 coding, 40 reports at 30 minutes by two, 40; analysis and write-up 40. Staff total about 350 hours, plus about 105 panelist hours (35 at 3 hours). No compute of note. Data access: full text of the 40 reports; no patient data. Ethics: expert surveys typically need an exemption or minimal-risk approval.

## Threats to validity

Seeded omissions are cleaner than real ones: a real unreported diagnostic leaves no trace, whereas a removed panel may leave a dangling reference, which inflates detection in both conditions; the steering member removing panels also removes cross-references. Reviewers in the no-dashboard condition answer structured questions, which is already more than a reader does, so the baseline is optimistic and a detected gain is conservative. Panel composition shapes the key; editors and assessors are the groups most likely to under-enroll, and their share is reported. The 40 reports come from a self-labeled emulation literature.

## Citations

- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334(12):1084. doi:10.1001/jama.2025.13350
- Jackson JW. Diagnostics for Confounding of Time-varying and Other Joint Exposures. Epidemiology. 2016;27(6):859-869. doi:10.1097/ede.0000000000000547
- VanderWeele TJ, Ding P. Sensitivity Analysis in Observational Research: Introducing the E-Value. Annals of Internal Medicine. 2017;167(4):268-274. doi:10.7326/m16-2607
- Gattrell WT, Logullo P, van Zuuren EJ, et al. ACCORD (ACcurate COnsensus Reporting Document): A reporting guideline for consensus methods in biomedicine developed via a modified Delphi. PLOS Medicine. 2024;21(1):e1004326. doi:10.1371/journal.pmed.1004326
- Dang LE, Balzer LB. Start with the Target Trial Protocol, Then Follow the Roadmap for Causal Inference. Epidemiology. 2023;34(5):619-623. doi:10.1097/ede.0000000000001637
