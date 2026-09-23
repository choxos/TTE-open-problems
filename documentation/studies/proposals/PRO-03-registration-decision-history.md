# PRO-03: what emulation registrations preserve of the decisions that produced them

**Catalog problem.** Registrations record the final protocol and not the alternatives that were rejected. Verdict `partially-addressed`; triage: corpus, answerable in part, feasibility 4.

**Residual claim this design tests.** Codex found the categorical wording unestablished and the problem mainly one of governance: prospective versioning, amendment records, decision logs and trusted timestamps can preserve the history; an unlogged history is unavailable to an auditor but not necessarily destroyed; a hash proves integrity only with a trusted timestamp; and a multiverse over components that change the estimand is not an uncertainty distribution for one parameter. The literature auditor found no paper reporting a decision log. The full-text reading found partial coverage: a framework that prespecifies permitted deviations from a base-case emulation and the diagnostics that trigger them (Weckstein 2025); a benchmarking program that commits to "document the reason for dropping the set" of trials it abandons (Wang 2025); an emulation that revised draft exposure and eligibility definitions during an outcome-blind feasibility step and said so (Barbulescu 2022); guidance calling for "an audit trail of revisions to the plan" (Patorno 2020). On the denominator, a cross-sectional study of nonrandomized drug-treatment studies found that few "mentioned registration on a trial registry (7%), or had an available protocol (3%)" (Yaacoub 2024). The reporting guideline asks only "State whether, when, and where the study protocol was registered" (Cashin 2025). What is not known is what registered emulations actually keep: alternatives, chronology, or an executable specification. This design measures that from the registries themselves.

**Relation to SFW-03.** SFW-03 samples publications and records registration and decision-log statements as they appear in papers (its items A4 and A5). This design samples registrations and reads every archived version of the record. If both run, A4 and A5 of SFW-03 are the publication-side check of R5 below (owner decision).

## Questions

**Q1.** Among registered target trial emulations, what fraction of registration records, across all their archived versions, document (a) an alternative specification that was considered and rejected, (b) a dated chronology of design changes, or (c) an executable specification with a trusted timestamp?

**Q2.** Among those with a linked publication, how often does the published protocol differ from the first registered version on each protocol component, and how often is the difference disclosed with a date and a reason?

**Q3.** Do the registries' own structures (public version history, amendment fields, attachment of files) predict whether history is kept?

## What this leaves unanswered

Alternatives never recorded anywhere, which no audit can recover. Whether logging a decision history improves validity, which needs a comparison of outcomes, not of records. Unregistered emulations, which are most of them (Yaacoub 2024), and whose history is covered only through SFW-03's publication-side items.

## Design

### Sampling frame

A census of registrations, not a sample, because the frame is small. Three registries, each searched on one day with the query recorded verbatim and the returned identifiers frozen:

- **ClinicalTrials.gov**, API v2, `query.term="trial emulation" OR "target trial"`: 133 records on 2026-09-23, 92 of them observational and 94 first submitted in 2024 to 2026.
- **OSF Registries**, registrations with "target trial" in the title: 96 on 2026-09-23, plus a full-text search for "trial emulation", deduplicated.
- **HMA-EMA Catalogue of real-world data studies** (the former EU PAS Register), searched for the same two phrases; the count is recorded at frame construction.

Records describing the same study in more than one registry are linked by title, investigators and dates and counted once, with all registry versions retained.

### Inclusion

A registration of an observational study that describes itself as emulating a target trial or as using the target trial framework to estimate the effect of a treatment, intervention or strategy on a health outcome; first registered from 2016-01-01 to 2026-06-30, so that every included record has had at least three months in which to be revised. Excluded: interventional trials that cite the framework, methods studies, registrations withdrawn before any content was posted. Two screeners; a third resolves.

### Extraction items

Every archived version of each record is saved as text (ClinicalTrials.gov record history, OSF registration and its updates, catalogue versions), one file per version, with its registry timestamp.

- **R1a, alternatives retained.** Alternative specifications registered as prespecified sensitivity analyses, by component: eligibility, comparator, time zero, grace period, treatment episode construction, washout, censoring rules, follow-up length, outcome definition. Coded 0 or 1 per component, with the quoted text.
- **R1b, alternatives rejected (primary).** Any version records at least one specification that was considered and not adopted for any listed component, with or without a reason. 0, none; 1, alternative named without a reason; 2, alternative named with a reason.
- **R2, chronology (primary).** Number of versions; for each change between versions, the component changed, the registry date, and whether a reason is given; whether the record states the date of data access and of outcome analysis. Coded 1 when at least one substantive design change is dated in the record or the record contains a dated decision log, else 0.
- **R3, executable specification.** Analysis code, a machine-readable protocol or a hash registered or archived with a trusted timestamp (registry version date or DOI-minted archive) before the stated outcome-analysis date. 0 or 1, with the locator.
- **R4, outcome-blind feasibility.** Feasibility counts or balance diagnostics registered or reported as obtained before outcome analysis. 0 or 1.
- **R5, publication agreement.** For registrations with a linked publication (found by searching PubMed and Europe PMC for the registration identifier and by the registry's own results links), each of the seven components compared between the first registered version and the publication: same; changed and disclosed with date or reason; changed and undisclosed.
- **R6, registry structure.** Public version history available; free-text amendment field; file attachment permitted.

### Extraction record and verification

Each item is a JSON record `{"registration", "version", "item", "value", "quote", "locator", "extractor", "source_file"}`. A positive value carries a verbatim quote from the saved version text and a locator (registry field name and version date); a value of 0 carries the list of versions and fields read. Records are appended one registration at a time. Quotes are checked with the collapsed-text matcher in `build/lit/verify_quotes.py` against the saved version files; a quote not found voids its value. Because the census is small, every registration is extracted independently by two people; a third adjudicates. Kappa and Gwet's AC1 are reported per item, and an item with kappa below 0.60 is barred from the decision rule.

### Sample size

The census size is not chosen. From exact binomial sums with Wilson intervals under the rule below: with 100 eligible registrations, a true R1b proportion of 0.10 reaches "real" with probability 0.80 and 0.05 with probability 1.00, and a true proportion of 0.55 reaches "not real" with probability 0.87; with 60 registrations, the same three probabilities are 0.44, 0.92 and 0.65. Below 60 eligible registrations the study is declared uninformative in advance. R5 is reported as proportions with intervals and without a threshold, since the publication-linked subset may be small.

## What would show the problem real or not real

- **Real.** The upper 95% Wilson bound for the proportion with R1b at least 1 is below 0.20, and the upper bound for R2 is below 0.30. Registered emulations then keep neither the rejected alternatives nor a dated record of how the design changed, and the entry's claim holds for the registered minority.
- **Not real.** The lower bound for R1b at least 1 is above 0.40, or the lower bound for R2 is above 0.50. A substantial share of registrations then keep the decision history, and the entry overstates.
- **Intermediate.** Anything else, reported with both intervals and by registry.
- **Uninformative.** Fewer than 60 eligible registrations, or kappa below 0.60 on R1b or R2.

## Cost

Person-hours: frame construction and version capture, 30; screening by two, 20; dual extraction at about 1.5 hours per registration per extractor for 150 registrations, 450; adjudication, 40; publication linkage and R5, 60; analysis and write-up, 40; about 640. No compute of note. Data access: public registry records and archived versions; publications through institutional access.

## Threats to validity

- Registries differ in how they expose history. ClinicalTrials.gov keeps a public record history; other registries may overwrite, so an absence of chronology can be an artifact of the registry, which R6 records and the analysis stratifies by.
- The census covers registered emulations only. Registration is itself a sign of transparency, so the registered minority is likely the best case; the result bounds practice from above.
- A registration can describe alternatives in an attached document rather than in fields. Attachments are read and saved as versions when the registry keeps them.
- "Considered and rejected" requires the record to say so. An alternative that appears only as a difference between versions is coded under R2, not R1b.

## Citations

- Weckstein AR, Frajzyngier V, Vititoe SE, Baglivo A, Beebe E, Govil P, Bradley MC, Perez-Vilar S, et al. Illustrating an adaptive prespecification framework for observational research: target trial emulations comparing immunomodulator treatments for COVID-19. Epidemiology. 2025;36:791-801. doi:10.1097/ede.0000000000001901
- Wang SV, Russo M, Glynn RJ, Bradley MC, He J, Concato J, Schneeweiss S. A Benchmark, Expand, and Calibration (BenchExCal) trial emulation approach for using real-world evidence to support indication expansions: design and process for a planned empirical evaluation. Clinical Pharmacology and Therapeutics. 2025;117:1820-1828. doi:10.1002/cpt.3621
- Barbulescu A, Askling J, Saevarsdottir S, Kim SC, Frisell T. Combined conventional synthetic disease modifying therapy vs. infliximab for rheumatoid arthritis: emulating a randomized trial in observational data. Clinical Pharmacology and Therapeutics. 2022;112:836-845. doi:10.1002/cpt.2673
- Patorno E, Schneeweiss S, Wang SV. Transparency in real-world evidence (RWE) studies to build confidence for decision-making: reporting RWE research in diabetes. Diabetes, Obesity and Metabolism. 2020;22:45-59. doi:10.1111/dom.13918
- Yaacoub S, Porcher R, Pellat A, Bonnet H, Tran VT, Ravaud P, Boutron I. Characteristics of non-randomised studies of drug treatments: cross sectional study. BMJ Medicine. 2024;3:e000932. doi:10.1136/bmjmed-2024-000932
- Cashin AG, Hansford HJ, Hernán MA, Swanson SA, Lee H, Jones MD, Dahabreh IJ, Dickerman BA, et al. Transparent reporting of observational studies emulating a target trial: the TARGET Statement. BMJ. 2025;390:e087179. doi:10.1136/bmj-2025-087179
