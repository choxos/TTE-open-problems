# SFW-03: what is released with published emulations, and whether it runs

**Catalog problem.** Code, phenotype logic, weight diagnostics and rejected protocol versions are not available for emulations. Verdict `partially-addressed`; triage: corpus, answerable in part, feasibility 4.

**Residual claim this design tests.** The audit (codex) narrowed the claim: an emulation is not externally auditable when its final analysis code, complete versioned phenotype logic and weight diagnostics are unavailable; where real data cannot be shared, code with a documented schema, a container and synthetic fixtures can establish that the pipeline executes but cannot reproduce the published estimate; and material protocol amendments belong in a versioned decision log, with every discarded draft a lower priority. The audit also found partial infrastructure (the OHDSI phenotype library, machine-readable Strategus specifications) and noted that TARGET's item on data and code availability is satisfied by a statement that materials are not available. This design measures the three decision-critical artifacts as the primary outcome, treats protocol history as a decision log rather than a store of rejected drafts, and adds an execution test, because a link to code is not evidence that the code runs.

## Questions

**Q1.** Among applied emulations published January 2024 to June 2026, what fraction release complete analysis code, complete versioned phenotype logic, and, where weights are used, weight diagnostics?

**Q2.** Of the released pipelines that come with data an outsider can use (public data or a synthetic dataset), what fraction can an independent analyst retrieve, build and run within a fixed time budget, and reproduce a prespecified output?

**Q3.** How often are protocol registration with a visible amendment history, a synthetic test dataset and an environment specification provided, and how does release vary with the journal's code policy and the data's access type?

## What this leaves unanswered

Whether releasing phenotype logic held under license is legally possible for a given data environment. Reproduction of the real-data estimate, which needs the data; REPEAT did that for 150 real-world evidence studies by re-implementing them from their reports in the same databases (Wang 2022), which is a different question from artifact availability. Whether rejected protocol versions should be published at all.

## Design

### Sampling frame and sample

The shared applied-emulation sample, drawn once and extracted with three forms (DTA-01, REG-03, SFW-03); sharing is an owner decision. PubMed, E-utilities `esearch`, exactly:

```
(("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) AND ("2024/01/01"[dp] : "2026/06/30"[dp]) AND english[la]) NOT (review[pt] OR systematic review[pt] OR meta-analysis[pt] OR editorial[pt] OR comment[pt] OR letter[pt] OR news[pt])
```

1,321 records on 2026-09-23, 847 in PMC, frozen as a PMID list. Two strata by the earlier of the electronic and print dates, before TARGET (2024-01-01 to 2025-09-22) and after (2025-09-23 to 2026-06-30); records dated "2025" with no month are excluded and counted. Each stratum is permuted with `set.seed(20260923)` and `x[sample.int(length(x))]` and screened in order to a quota of 100 eligible papers. Inclusion: an applied study in humans estimating the effect of an intervention or treatment strategy on a health outcome from routinely collected, registry or cohort data, describing itself as a target trial emulation or trial emulation. Exclusion: method papers with illustrative applications, protocols, benchmarking of an existing trial, duplicates, conference abstracts. Two screeners at each stage; a third resolves. Feasibility studies whose result is a fitness verdict are in the shared sample for DTA-01; they have no estimation pipeline, so this form codes them "not applicable", excludes them from every SFW-03 denominator, and reports their count. The weight-diagnostics item applies to the subset using inverse probability weights of any kind (treatment, censoring, clone-censor-weight, marginal structural models), expected to be 80 to 120 papers.

### Extraction items (SFW-03 form)

- **A1, analysis code**: 0, none or "available on request"; 1, a link or supplement with part of the pipeline (for example only the estimation step); 2, the complete pipeline from cohort construction to reported estimates. The availability statement is quoted; for a link, the URL, the commit hash or archive DOI and a file listing are recorded on the extraction date, and the link is checked to resolve.
- **A2, phenotype logic**: 0, prose only; 1, code lists for some definitions; 2, code lists for every eligibility, exposure, outcome and key covariate definition, with the coding system and its version (for example the ICD-10-CM fiscal year, the ATC year, or an OMOP vocabulary version or concept set identifier).
- **A3, weight diagnostics**, weighted analyses only: 0, none; 1, truncation stated only; 2, a distribution summary by arm or time (mean and a maximum or upper percentiles); 3, that plus effective sample size or time-specific summaries.
- **A4, protocol registration**: registry and identifier; registration date before the analysis or not; amendment history visible in the registry or in an amendment log; any statement of changes after registration.
- **A5, design decision log**: any record of alternatives considered and dropped (a decision log, or statements such as "we initially planned"), quoted.
- **A6, runnable data**: none; public source data; a synthetic dataset.
- **A7, environment**: package versions stated; a lockfile or container provided.
- **A8, journal code policy** on the extraction date, from the journal's author guidelines: sharing mandatory; statement required; encouraged; none. Quoted with URL and access date, coded once per journal.
- **A9, data access type**: public; controlled access by application; licensed commercial; institutional only.

**Primary outcome R3**: A1 is 2, A2 is 2, and either no weights are used or A3 is at least 2.

### Execution test

**Population.** Every paper with A1 at least 1 and A6 public or synthetic is attempted. From papers with A1 at least 1 and no runnable data, a seeded random 10 are attempted to the build stage only.

**Procedure.** In a clean container at a date-pinned tag (a Rocker `r-ver` image for R pipelines, an official Python image otherwise), with package installation allowed and nothing else fetched. Before starting, the analyst names the one output to reproduce: the cohort flow counts or the weight distribution table on the provided data, or, for public data, the main reported estimate within 1% relative. Fixes are limited to file paths and documented configuration; editing analysis logic ends the attempt at the level reached. Levels: E0, not retrievable (dead link, empty repository, access denied); E1, retrieved and the environment builds within 2 hours; E2, runs end to end on the provided data within 8 analyst hours; E3, reproduces the named output. Every command and error is logged, and the log is the locator for the attempt's record. A second analyst repeats a random 25% of attempts independently, and disagreement on the level assigned is adjudicated.

**Compute.** Attempts are capped at 2 CPU-hours each and run with `nice -n 19` on the shared machine; at most 20 attempts gives at most 40 CPU-hours, within the 100 CPU-hour ceiling.

### Extraction record and verification

Each item is a JSON record `{"paper", "item", "value", "quote", "locator", "extractor", "source_file"}`. A positive value carries a verbatim quote and a locator (the data availability statement, supplement table number, repository path at a commit). A value of 0 carries the sections read and a scripted term search of text and supplements (github, gitlab, zenodo, osf, code, script, repository, supplement, available, request, code list, ICD, ATC, concept, weight, truncat, effective sample, registered, protocol, amendment). Text from `pdftotext`, one file per paper in a scratch directory; records appended one paper at a time in the pattern of `build/lit/add_finding.py`; quotes checked with the collapsed-text matcher in `build/lit/verify_quotes.py` (import `norm`, `split_elisions`, `spans`, `coverage`), with a NOT-FOUND quote voiding its value. Repository contents are verified by the recorded commit and file listing rather than a quote. A1, A2 and A3 are double-extracted for every paper; A4 to A9 on a random 25%. A third reviewer adjudicates; kappa and Gwet's AC1 per item; items below kappa 0.60 are barred from decision rules.

### Sample size

200 papers, 100 per stratum. From exact binomial sums with Wilson intervals under the rule below: a true R3 of 0.10 reaches "real" with probability 0.97 and 0.13 with 0.71; a true R3 of 0.60 reaches "not real" with probability 0.83 and 0.65 with 0.99; a true R3 of 0.30 is always intermediate. The execution test is sized by what the sample releases, probably 5 to 20 attempts, and is reported as proportions with intervals and without a threshold.

## What would show the problem real or not real

- **Real**: the upper 95% bound of weighted R3 is below 0.20. Fewer than one emulation in five can be audited in its operative detail.
- **Not real**: the lower bound exceeds 0.50. Most emulations release the decision-critical artifacts, and the entry describes a minority.
- **Intermediate** otherwise. **Uninformative**: kappa for A1, A2 or A3 below 0.60.
- Q2 qualifies either branch: a high R3 with most attempts ending at E0 or E1 would show release without executability, which the entry's reasoning about unrunnable code predicts.

## Cost

Person-hours, with shared screening (about 50) and full-text acquisition (about 17) charged once across DTA-01, REG-03 and SFW-03: A1 to A9 extraction, 200 papers at 25 minutes by two, 167; link and repository checks 40; journal policies, about 120 journals at 10 minutes, 20; execution attempts, up to 20 at 8 hours, 160, plus 40 for the 25% repeat; adjudication 20; analysis and write-up 25. SFW-03 alone: about 470 hours, 540 with the shared screening charged here. Compute at most 40 CPU-hours, derived above. Data access: institutional full text for the roughly 36% of papers outside PMC; public repositories; public source data where a paper used it.

## Threats to validity

Availability decays: links checked in 2026 for papers from 2024 overstate what a reader at publication could get when repositories were later made public, and understate it when links later died; the check date is recorded and the analysis is repeated by publication year. "Available on request" is coded 0 without testing requests; a request audit would need contact with authors and is not part of this design. Code for proprietary data models may be complete yet unrunnable by construction, which is why Q2 is limited to papers that supply runnable data. The frame depends on the emulation label.

## Citations

- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334(12):1084. doi:10.1001/jama.2025.13350
- Wang SV, Sreedhara SK, Schneeweiss S, REPEAT Initiative, et al. Reproducibility of real-world evidence studies using clinical practice data to inform regulatory and coverage decisions. Nature Communications. 2022;13(1):5126. doi:10.1038/s41467-022-32310-3
