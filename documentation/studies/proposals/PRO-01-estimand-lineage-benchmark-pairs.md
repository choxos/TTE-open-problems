# PRO-01: an estimand lineage raters can code, and whether it explains why emulations disagree with their trials

**Catalog problem.** No decomposition separates scientific-target mismatch from protocol compromise, mapping loss and estimation error. Verdict `overstated`; triage: consensus, answerable in part, feasibility 1.

**Residual claim this design tests.** Codex found the decomposition undefined as stated: the entry names four objects but three transitions; under valid identification the observed-data functional equals the target estimand and contributes no loss; when identification fails the resulting bias is not identified from the same data; effects defined on different populations, interventions or outcomes have no canonical additive distance; and differences in support or composition do not bound effect differences without bridge assumptions. Its restatement, which the adjudication adopted: emulations should document separately the changes from the decision question to the operational estimand, the assumptions mapping that estimand to an observed-data functional, and estimation uncertainty, as a lineage that need not add up numerically. The ideal, target and actual trial distinction is published (Moreno-Betancur 2026), as are frameworks that ask for differences between the question's estimand and the one "implied or imposed by the study design or data analysis" to be "noted and accounted for" (Lu 2025) and a vocabulary for the parts of a causal estimand (Shiba 2026). A survey of emulation reports found that most "did not justify the choice of trial to emulate" (Ren 2026). What does not exist is a lineage specified tightly enough for two people to code it the same way, evidence of whether current reports carry it, or evidence that it tracks anything.

The one setting where the estimand of the decision question has an observed estimate is an emulation of an existing trial. There the trial plays the ideal trial, the emulation's protocol and analysis are the later steps, and the estimation error of both is known from their standard errors. Benchmarking studies already list the ways the two can differ (Matthews 2022) and have related design differences and emulation closeness to disagreement (Heyard 2024; Wang C 2026). This design fixes the lineage by consensus, codes it on every published benchmark pair, and tests whether the coded estimand changes explain discrepancy beyond sampling error.

## Questions

**Q1, consensus.** Can methodologists, trialists, regulators and editors agree on a lineage schema: for each protocol component and each transition, which kinds of change count as a change of estimand, which change only the identifying assumptions, and which change only precision?

**Q2, reliability and recoverability.** Can two trained coders apply the schema to a benchmark pair reproducibly, and how much of the lineage coded from all available documents can be recovered from the published emulation report alone?

**Q3, validity.** Among emulation-trial pairs, does the number of estimand-changing transitions predict the size of the discrepancy beyond what sampling error and the existing closeness rating predict?

## What this leaves unanswered

A distance between estimands for emulations of hypothetical trials, where no benchmark exists; codex's argument that no canonical additive distance exists is accepted, not tested. Whether requiring a lineage changes practice. The split of residual discrepancy between identification failure and unexplained design differences, which the benchmark data cannot separate.

## Design, stage 1: modified Delphi

### Panel

Invited and nominated, in four groups: methodologists who have published a target trial emulation or a methods paper on emulation (12); trialists and trial statisticians (6); regulatory and health technology assessment reviewers (6); journal editors and statistical reviewers who handle emulation manuscripts (6). Target 30; floor 20 completing round 3, at which one panelist moves an agreement share by 5 points. Nobody who codes in stage 2 sits on the panel. Reported under ACCORD (Gattrell 2024).

### Round 0: candidate schema

A steering group of three drafts it. Components: eligibility, treatment strategies, assignment, follow-up start and duration, outcome, causal contrast, analysis plan. Transitions: decision question to specified target trial; target trial to emulated protocol; emulated protocol to analysis as run. For each component and transition: change present or absent; change type (restriction, substitution, coarsening, operational proxy, extension); consequence class (changes the estimand; changes only the identifying assumptions; changes only precision); and, where applicable, the computable evidence that accompanies it (standardized differences in effect-modifier distributions between the trial and emulation populations; share of person-time compatible with the trial's strategy; outcome definition validity where reported).

### Rounds 1 to 3

Each panelist rates each field for inclusion in the core schema (1 to 9), assigns each change type within each component to a consequence class, and rates each evidence item as required, optional or not useful. Distributions and anonymized rationales are fed back after each round. No item is rated after round 3.

### Agreement

A field enters the core at 70% or more rating 7 to 9 with at most 15% rating 1 to 3. A change type's consequence class is agreed at 70% or more choosing the same class. The schema is adopted when every core field is agreed and at least 80% of change types have an agreed class.

## Design, stage 2: coding benchmark pairs

### Corpus

A census: the 107 emulation-trial pairs of the concordance meta-analysis, with every pair and figure reconciled against its published correction (Wang C 2026), plus any pair from the RCT-DUPLICATE program (Wang 2023) not already among them; 107 to 139 pairs. For each pair the sources are the trial's protocol or design paper and registration, and the emulation's report, supplements, and protocol or registration where one exists.

### Blinding

A team member who does not code removes results sections, abstracts, figure captions and every numerical effect estimate from each source, so coders read methods and design material only. The discrepancy is merged into the data after coding is locked.

### Coding

- **Full coding.** From all sources, by two coders independently for every pair; disagreements adjudicated by a third. Produces the lineage record, the count S_Q of components with an estimand-changing transition and the count S_M with a change of identifying assumptions only.
- **Report-only coding.** From the published emulation report and its supplements alone, by one coder who did not full-code that pair; a random 30% by a second.
- **Recoverability.** The share of full-coding estimand-changing transitions that report-only coding also finds.

### Extraction record and verification

Each coded transition is a JSON record `{"pair", "component", "transition", "change_type", "class", "quote", "locator", "coder", "source_file"}` whose quote is verbatim from the redacted source text and checked with the collapsed-text matcher in `build/lit/verify_quotes.py` against `pdftotext` output kept one file per source; records are appended one pair at a time. A transition coded absent carries the sections read. Reliability is Gwet's AC1 and kappa per component for the consequence class; a component below AC1 0.60 is excluded from S_Q, and the exclusion is reported.

## Design, stage 3: validity

For each pair, d = log of the emulation's hazard ratio (or the effect measure the pair shares) minus log of the trial's, with sampling variance v from the two published intervals, and z = d / sqrt(v). Under no emulation error z^2 has expectation 1; each unit of true error b adds b^2 / v. The primary analysis regresses z^2 on S_Q with the meta-analysis's closeness rating as a covariate, with a robust standard error; the slope estimates the added squared standardized discrepancy per estimand-changing transition. A secondary analysis adds S_M. A location-scale random-effects meta-regression of d is reported descriptively.

### Sample size

The corpus is fixed by what exists. With about 107 pairs, S_Q with a standard deviation near 0.9, and a residual standard deviation of z^2 near 1.6 (1.4 under no emulation error), the slope's standard error is about 0.17: a slope of 0.5, a true error of about 0.7 sampling standard errors added per estimand-changing transition, is detected with power about 0.83 at two-sided alpha 0.05, and a slope of 0.25 with power about 0.3. Reliability: 107 double-coded pairs give an AC1 interval of about plus or minus 0.1 at AC1 near 0.7.

## What would show the problem real or not real

- **Real, in the adopted restatement.** The schema is adopted, the consequence class reaches AC1 0.60 on at least five of seven components, the upper 95% bound for recoverability from reports is below 0.60, and the validity slope's 95% interval lies above zero. A codable lineage then exists, current reports do not carry most of it, and the estimand changes it records explain disagreement that sampling error does not.
- **Not real.** Reliability is met and either the lower 95% bound for recoverability is above 0.80, so reports already expose the lineage, or the slope's 95% interval lies below 0.25, so estimand changes in benchmark pairs add less than half a sampling standard error of error per transition and a reader loses little by not being shown them.
- **Premise contested.** The panel fails to agree a consequence class for change types in three or more components. The separation of estimand change from mapping change is then not agreed among specialists, which supports codex's critique; the schema is released without the consequence class.
- **Uninformative.** AC1 below 0.40 on the consequence class, or fewer than 60 pairs with usable sources.

## Cost

Person-hours: steering group, schema and round materials, 60; source acquisition and redaction at about 1 hour per pair, 130; full coding at 2.5 hours per pair per coder, two coders, 139 pairs, 700; report-only coding at 1 hour per pair plus 30% double, 180; adjudication, 60; analysis, 40; write-up, 30; about 1,200 staff hours, plus about 90 panelist hours (30 at 3 hours). No compute of note. Data access: published articles, supplements, trial registrations and protocols; no patient data. Ethics: expert surveys typically need an exemption or minimal-risk approval.

## Threats to validity

- Benchmark pairs are emulations designed to match a trial, so their estimand changes are smaller and rarer than in emulations of hypothetical trials; a null validity slope here does not show that lineage is unimportant where no trial constrains the design.
- The concordance meta-analysis's pair set reflects its own selection; its correction must be applied before any figure is used.
- Redaction reduces but cannot remove a coder's knowledge of famous trial results.
- Discrepancy mixes estimand change, identification failure and trial-side issues (adherence, measurement). The slope measures association with the coded changes, not their causal share.

## Citations

- Moreno-Betancur M, Wijesuriya R, Carlin JB. The ideal trial: defining causal estimands that balance relevance and feasibility in target trial emulations and actual randomized trials. Epidemiology. 2026;37:153-162. doi:10.1097/EDE.0000000000001933
- Lu H, Li F, Lesko CR, Fink DS, Rudolph KE, Harhay MO, Rentsch CT, Fiellin DA, et al. Four targets: an enhanced framework for guiding causal inference from observational data. International Journal of Epidemiology. 2025;54:dyaf003 (published online January 2025; CrossRef records the issue date as 2024-12-16). doi:10.1093/ije/dyaf003
- Shiba K. Clarifying causal questions in population health research: anatomy of a causal estimand. American Journal of Epidemiology. 2026;195:1834-1838. doi:10.1093/aje/kwag079
- Ren Y, Jia Y, Liu L, Lyv H, Tao L, Li Y, Zhao P, Xiong Y, et al. Design and implementation of observational studies emulating a target trial. JAMA Network Open. 2026;9:e2558262. doi:10.1001/jamanetworkopen.2025.58262
- Matthews AA, Dahabreh IJ, Fröbert O, Lindahl B, James S, Feychting M, Jernberg T, Berglund A, et al. Benchmarking observational analyses before using them to address questions trials do not answer: an application to coronary thrombus aspiration. American Journal of Epidemiology. 2022;191:1652-1665. doi:10.1093/aje/kwac098
- Heyard R, Held L, Schneeweiss S, Wang SV. Design differences and variation in results between randomised trials and non-randomised emulations: meta-analysis of RCT-DUPLICATE data. BMJ Medicine. 2024;3:e000709. doi:10.1136/bmjmed-2023-000709
- Wang C, Tang D, von Dadelszen P, Ju C, Liu L, Wang Y, Magee LA. Concordance between target trial emulation and randomised controlled trials: systematic review and meta-analysis. BMJ. 2026;393:e086810. doi:10.1136/bmj-2025-086810; correction BMJ. 2026;394:e100303. doi:10.1136/bmj-2026-100303
- Wang SV, Schneeweiss S, RCT-DUPLICATE Initiative, Franklin JM, Desai RJ, et al. Emulation of randomized clinical trials with nonrandomized database analyses. JAMA. 2023;329:1376. doi:10.1001/jama.2023.4221
- Gattrell WT, Logullo P, van Zuuren EJ, Price A, Hughes EL, Blazey P, Winchester CC, Tovey D, et al. ACCORD (ACcurate COnsensus Reporting Document): a reporting guideline for consensus methods in biomedicine developed via a modified Delphi. PLOS Medicine. 2024;21:e1004326. doi:10.1371/journal.pmed.1004326
