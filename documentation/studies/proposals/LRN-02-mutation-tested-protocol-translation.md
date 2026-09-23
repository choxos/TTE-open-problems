# LRN-02: a mutation-tested reference harness for automated protocol translation

**Catalog problem.** Automated protocol translation can change the estimand while producing valid code. Verdict `confirmed-open`; triage: software, answerable in part, feasibility 2, scope core.

**Residual claim this design tests.** Codex rejected two parts of the entry: that such errors are necessarily invisible, and that no reference answer can exist. Independently authored specifications, expert-labeled records, reference implementations, differential testing and synthetic boundary-case patients all supply reference answers at the level of a protocol component, and the entry's own proposed direction depends on that. What survives: nobody has measured how often translators emit code that runs and implements a different estimand, and no harness exists that would catch it. The nearest system, THESEUS (Kim 2026), already routes translation through a typed intermediate form: a language model fills a JSON specification and rule-based logic emits OHDSI Strategus scripts. Its evaluation scores field-level agreement with reference specifications (0.93 to 0.97 overall standardization accuracy in 15 OHDSI studies, 0.82 to 0.95 in 15 others, per its abstract). Field agreement is not the same as the executed cohort being right on the temporal clauses that decide eligibility, time zero and assignment, and a field can be filled correctly while its compiled join is wrong. Grok also records a functional-correctness evaluation of generated trial-criteria queries and a 2026 preprint proposing adversarial validation with a structured protocol form; the preprint has no CrossRef record and is not cited.

## Questions

**Q1.** How often does an automated translator emit code that executes and produces a cohort, assignment, outcome or censoring status that differs from the reference reading, on a clause whose change alters the estimand (a silent estimand-changing error)?

**Q2.** Does routing through a typed specification and a deterministic compiler lower that rate relative to direct code generation, specifically on temporal clauses?

**Q3.** Does a suite of synthetic patients constructed to distinguish each clause's reference reading from its plausible wrong readings detect those errors, and is the suite itself valid?

**Q4.** Would the downstream effect estimate have revealed the error?

## What this leaves unanswered

Mapping protocol concepts to a particular database's codes and data quality: the harness tests semantics on a fixed common data model and cannot say whether a concept set is clinically right for a source. Clauses that are genuinely ambiguous in the published text are recorded and excluded from the error count; resolving them is a protocol-writing problem. Natural-language eligibility extraction from notes (the entry's second example) is out of scope.

## Design

### Protocol corpus

Sampling frame: the applied emulations among the 575 works of the repository's consolidated library (`documentation/refs/library.json`, full text on disk) whose text contains a protocol table listing eligibility, strategies, assignment, time zero, follow-up, outcome and causal contrast, the components of Hernán and Robins (2016) and TARGET (Cashin 2025). One screener identifies qualifying papers and a second checks every inclusion and a random fifth of exclusions; if fewer than 10 qualify in any stratum, the stratum is filled from a PubMed search for "target trial emulation" restricted to 2024 to 2026, screened the same way. Stratified random sample of 30 protocols: 10 point-initiation new-user designs, 10 sustained strategies with a grace period or per-protocol contrast, 10 with switching, dynamic strategies or cloning. For each, a perturbed twin is written by one team member who changes every window length, anchor and grace period to values that appear in no sampled paper, so that a system cannot succeed by recalling a published analysis. 60 protocol texts in total. Sample size: about 8 estimand-relevant clauses per text gives about 480 clauses per system; with 3 runs each and a design effect of 3 for clustering within text, a clause-level error rate of 0.10 is estimated to about plus or minus 0.03, and a protocol-level rate of 0.40 to about plus or minus 0.12.

### Reference specification

A typed intermediate representation (JSON Schema, versioned). Each eligibility criterion, outcome and censoring event is a temporal predicate: concept set with descendant rule; occurrence quantifier (any, first, all, at least k); window `[lo, hi]` with unit, inclusivity of each bound, and anchor (index date, eligibility assessment date, first qualifying diagnosis, calendar date); required continuous observation. Strategies carry the initiation window, grace period and the arm it applies to, the deviation definition, and the version class of treatment. Assignment records cloning; the causal contrast records intention-to-treat or per-protocol. The fields follow the component-to-record mapping of an operational emulation framework (Wang 2026), which is the interface a compiler has to respect. Two analysts encode every text independently; a third adjudicates. Any clause the adjudicator judges to support two defensible readings is marked ambiguous with both readings recorded. Agreement per field (Cohen's kappa) is a reported result: it measures how much of the problem is ambiguity rather than translation.

### Reference compiler and data model

A deterministic compiler from the representation to SQL over a subset of the OMOP common data model v5.4 (person, observation period, visit, condition, drug exposure, procedure, measurement, death), executed in DuckDB. It is validated before use on 20 hand-computed toy cohorts covering every predicate type; any disagreement is a compiler defect and is fixed before the gate below is computed.

### Mutation operators and distinguishing patients

Operators act on the representation and each produces a plausible wrong reading: before and after exchanged; a bound's inclusivity flipped; anchor substituted (index for eligibility assessment, first diagnosis for index); window endpoint moved by one day or one unit; days read as months; any and first occurrence exchanged; lookback measured from cohort entry rather than index; grace period applied to both arms or to the wrong arm; deviation dated at the first missed refill rather than after the grace period; censoring at deviation dropped; outcome window starting at index rather than the day after; continuous-observation requirement dropped; concept descendants dropped. For each clause and mutant, a small constraint solver over event dates constructs a minimal patient whose status differs between the reference and the mutant, plus boundary patients one day either side of every window edge. Mutants that no patient can distinguish, given the rest of the protocol, are marked equivalent and excluded.

**Harness validity gate.** Applied to the reference compiler with each mutated representation, the suite must kill at least 95% of non-equivalent mutants. A lower score means the harness, not the translators, is what fails, and the study stops for repair.

### Systems under test

(1) Direct code generation by at least two general-purpose language models given the protocol text, the data-model schema and one worked example, asked for SQL or R. (2) Specification-mediated generation: the same models fill the typed representation and the reference compiler emits the code, so that representation-filling errors are isolated from code-generation errors. (3) THESEUS through its published web application or code, if either is accessible when the study starts; otherwise it is excluded and the exclusion recorded. Every system runs 3 times per text. Model identifiers, versions, dates and prompts are frozen before the first run.

### Outcomes

For each clause and run: whether the code executes; whether it matches the reference on every distinguishing patient for that clause; and a silent estimand-changing error, defined as executing without error while failing at least one distinguishing patient on an eligibility, time-zero, assignment, outcome or censoring clause, where the failing behavior matches neither recorded reading of an ambiguous clause. Primary measures: the clause-level silent error rate and the protocol-level rate of at least one such error, per system, with 95% intervals from a cluster bootstrap over protocol texts. Secondary: rates by operator class (temporal, occurrence, concept, arm-specific); the specification-mediated minus direct difference, paired by text; performance on original versus perturbed twins, which measures reliance on recall.

### Downstream visibility (Q4)

For the 10 sustained-strategy texts and their twins, a synthetic population of 50,000 persons is generated in the data model from a simulator that follows the protocol's structure with a known per-protocol risk difference of -0.03 at the protocol's horizon. The reference cohort is analyzed with one fixed estimator (pooled logistic inverse-probability weighting); every translation containing a silent error is analyzed identically. The measure is the share of silent errors whose estimate lies inside the reference estimate's 95% interval. This quantifies the entry's claim that a wrong cohort with a plausible number passes.

## What would show the problem real or not real

- **Real**: for at least one system under test, the protocol-level rate of at least one silent estimand-changing error has a lower 95% bound of at least 0.10, and at least half of silent errors fall inside the reference interval in Q4.
- **Not real**: every system has a clause-level silent error rate with upper bound at most 0.01 and a protocol-level rate with upper bound at most 0.05. THESEUS's reported field accuracy makes this branch plausible for specification-mediated systems, which is why it is tested rather than assumed.
- **Mixed and useful**: specification-mediated generation has a paired rate at least 0.05 lower than direct generation, with the interval excluding zero; the entry's proposed direction is then supported for the translation step and the remaining error is located in representation-filling.
- **Uninformative**: the harness gate fails after repair; or adjudicated reference agreement on temporal fields has kappa below 0.60, in which case the reference itself is not reliable and the finding is that published protocols underdetermine their estimand.

## Cost

Person-hours: representation schema and compiler 80; dual encoding of 60 texts at 1.5 hours each, 180, plus adjudication 30; perturbed twins 30; mutation and patient generator 60; harness and execution pipeline 40; Q4 simulator and analysis 40; analysis and write-up 40. About 500 hours. Language-model use: 60 texts by 3 runs by up to 5 system configurations, about 900 generations; token cost is modest (hundreds of US dollars at 2026 list prices) and is recorded. Compute: executing about 900 generated programs against suites of at most a few hundred patients, and weighted pooled logistic analyses of the 20 synthetic populations of 50,000 persons (one for the reference cohort and one for each erroneous translation, at most a few hundred fits), is under 10 CPU-hours. No patient data; full text of the 30 source papers.

## Threats to validity

The mutation set encodes the team's idea of plausible errors; an error outside it is still caught if it changes a boundary patient, but the suite's sensitivity to such errors is unknown and the gate cannot measure it. A fixed data model favors systems built for it, so THESEUS, built for OMOP, is advantaged, and direct generation is given the schema to offset that. Model behavior drifts across versions; results are dated and pinned. Published protocol tables are the better-reported part of the literature, so error rates on typical protocols are likely higher. Perturbed twins remove recall of published analyses but not of general conventions.

## Citations

- Kim H, Kim M, Kim S, You SC. From study design to executable code: automating target trial emulation with large language models. JAMIA Open. 2026;9(4):ooag131. doi:10.1093/jamiaopen/ooag131
- Wang Y, Li Y, Lin T, Guo Y. An operational target trial emulation framework for causal inference using electronic health record data. npj Digital Medicine. 2026;9:424. doi:10.1038/s41746-026-02563-z
- Hernán MA, Robins JM. Using Big Data to Emulate a Target Trial When a Randomized Trial Is Not Available. American Journal of Epidemiology. 2016;183(8):758-764. doi:10.1093/aje/kwv254
- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334:1084. doi:10.1001/jama.2025.13350
