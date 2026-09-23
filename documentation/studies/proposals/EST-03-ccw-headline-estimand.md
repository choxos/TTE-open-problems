# EST-03: what clone-censor-weight emulations put at the head of their results

**Catalog problem.** A hazard ratio is reported where the estimand was a weighted per-protocol effect among the grace-period compatible. Verdict `partially-addressed`; triage: corpus, answerable in part, feasibility 4.

**Residual claim this design tests.** The audit corrected the entry's population. A correctly weighted clone-censor-weight analysis reweights uncensored clone time to represent the artificially censored, so it targets the baseline eligible population under the specified strategies, given exchangeability and positivity; when censoring enforces adherence the contrast is per-protocol (Maringe 2020, quoted in the audit trail). The claim that survives is about disclosure: a bare hazard ratio names neither the intervention, the strategy, the population, the horizon nor the handling of intercurrent events, and can be read as an intention-to-treat contrast. TARGET (Cashin 2025) already asks for these items, so the question is adoption. This design codes whether a report states the population and strategy at all, and separately whether it misdescribes them; the entry's own wording, "among the grace-period compatible", would be coded as a misdescription.

## Question

Among applied clone-censor-weight emulations published from January 2021 to June 2026: how often does the abstract lead with a relative effect measure while stating neither the adherence condition of the strategies nor an absolute measure at a named horizon; how often does the full text state all five estimand attributes; how often is the contrast misdescribed, as intention-to-treat or as an effect among adherers; and did these change after TARGET?

## What this leaves unanswered

Whether readers actually misread a bare hazard ratio as an intention-to-treat effect; that needs a randomized reader experiment, and the corpus shows only what is on the page. Whether a one-sentence estimand statement or a timeline diagram improves comprehension. Whether the hazard ratio itself has a causal interpretation; that is a methods fact, not a reporting prevalence. Per-protocol analyses built on sequential trials with artificial censoring are outside the frame.

## Design

### Sampling frame

A census of the union of two searches, both run on 2026-09-23 and frozen as ID lists.

(a) PubMed, exactly:

```
(("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) AND (clone[tiab] OR clones[tiab] OR cloning[tiab] OR cloned[tiab] OR "grace period"[tiab] OR "grace periods"[tiab]) AND ("2021/01/01"[dp] : "2026/06/30"[dp]) AND english[la]) NOT (review[pt] OR systematic review[pt] OR meta-analysis[pt] OR editorial[pt] OR comment[pt] OR letter[pt] OR news[pt])
```

120 records.

(b) PMC full text, exactly:

```
("target trial" OR "trial emulation" OR "emulated trial") AND ("clone-censor-weight" OR "clone censor weight" OR "cloning" OR "cloned" OR "clones") AND ("artificial censoring" OR "artificially censored") AND ("2021/01/01"[pdat] : "2026/06/30"[pdat])
```

106 records.

Search (a) misses emulations whose abstracts name neither cloning nor a grace period; search (b) covers only PMC and requires the artificial-censoring wording in the body. The union is deduplicated on PMID, then DOI. The overlap among eligible papers gives a two-source capture estimate of the eligible total, `N = n_a * n_b / m`, and so the share of eligible papers the union captured. The two sources are not independent: a paper that names cloning in its abstract is more likely to say "artificial censoring" in its body, and PMC deposit tracks journal, so the dependence is positive, `N` is underestimated and the captured share is optimistic. The share is reported with that direction stated, and if even this optimistic share is below 0.70 the prevalence is reported as conditional on retrieval and a third source (Embase through institutional access, same terms) is added before analysis. The expected eligible count after screening is 80 to 130.

### Inclusion

Included: an applied emulation in humans that clones individuals into every strategy compatible with their baseline data and artificially censors each clone at deviation (the construction set out by Hernán 2018), with or without a grace period, with results. Excluded: papers whose stated aim is a method or a tutorial; protocols without results; reviews; duplicate reports of one analysis. Where a paper reports several clone-censor-weight analyses, the one reported first in the abstract is coded. Two screeners independently at both stages; a third resolves disagreements.

### Extraction items

Abstract items, which define the primary outcome:

- **E1, headline measure**: the first effect estimate in the abstract's results: hazard ratio, odds ratio, risk ratio, risk difference, absolute risks by arm, restricted mean survival difference, other.
- **E2, absolute measure at a named horizon** in the abstract: a risk, risk difference or restricted mean with a stated time.
- **E3, strategy disclosure** in the abstract: the strategies are stated with their initiation window or grace period, or with an adherence or per-protocol qualifier. The definition is lenient to the report on purpose, so the primary outcome is conservative.

**Primary outcome P1, bare relative headline**: E1 is a relative measure, and E2 and E3 are both absent.

Full-text items, worded to match the TARGET protocol items and the component list Hansford 2023 extracted from 200 emulations published to October 2022, so the two can be compared:

- **E4, strategies**: each strategy with its grace period and what happens to a clone on deviation.
- **E5, population**: the population to which the estimate refers, stated as the eligible population at time zero or equivalent.
- **E6, outcome and horizon** of the reported contrast.
- **E7, intercurrent events**: handling of deviation (artificial censoring and whether it is weighted), death or competing events, and loss to follow-up.
- **E8, summary measure** named as the causal contrast; if a hazard ratio, whether any statement about its interpretation is given.
- **C5** = E4 through E8 all stated.
- **E9, estimand sentence**: one sentence or one table row that names at least the strategies, the population and the horizon together.
- **E10a, misdescription as assignment**: in the abstract conclusion or the first interpretive paragraph of the discussion, the contrast is called intention-to-treat, or described as the effect of initiating treatment with no adherence qualifier.
- **E10b, misdescription as a subset effect**: the estimate is described as applying to patients who adhered, or to those whose observed treatment matched a strategy.
- **E11, weighting**: whether artificial censoring is weighted (unweighted cloning is recorded, not excluded).
- **E12, TARGET**: whether the paper cites TARGET, and its stratum by the earlier of electronic and print date: before or on and after 2025-09-23.

### Extraction record and verification

Each item is a JSON record `{"paper", "item", "value", "quote", "locator", "extractor", "source_file"}`. Every positive value carries a verbatim quote and a locator (abstract section, or section and paragraph, table or figure legend). An absent value carries the sections read and the output of a scripted search of the full text for a registered term list (intention-to-treat, per-protocol, adher, grace, clone, artificial, censor, horizon, restricted mean, absolute risk, risk difference, estimand); absence stands only when both extractors confirm no hit qualifies. Text comes from `pdftotext` into a scratch directory, one file per paper; records are appended one paper at a time by a script in the pattern of `build/lit/add_finding.py`; quotes are checked with the collapsed-text matcher in `build/lit/verify_quotes.py` (import its `norm`, `split_elisions`, `spans` and `coverage`), and a NOT-FOUND quote voids its value until corrected. The census is small enough to double-extract every item for every paper. A third reviewer adjudicates. Kappa and Gwet's AC1 are reported per item; an item with kappa below 0.60 cannot enter a decision rule.

### Sample size

A census; its size is what the frame yields. Operating characteristics of the rule below, from exact binomial sums with Wilson intervals: at 90 eligible papers, a true P1 prevalence of 0.40 reaches "real" with probability 0.88 and a true prevalence of 0.02 reaches "not real" with probability 0.89; at 120 papers the same figures are 0.95 and 0.85 (at 0.03). A true prevalence near 0.05 reaches "not real" with probability only 0.34 at 90 papers, so a low but nonzero prevalence may come out intermediate; that is stated in advance. The before and after TARGET contrast is secondary and descriptive, since the later stratum will hold perhaps a quarter of the census.

## What would show the problem real or not real

- **Real**: the lower 95% bound of P1 exceeds 0.25. At least one clone-censor-weight abstract in four leads with a relative measure while disclosing neither the adherence condition nor an absolute measure at a horizon, which is the entry's "systematic rather than occasional".
- **Not real**: the upper bound is below 0.10. Bare relative headlines are occasional, and the entry's residual claim is wrong for this design.
- **Intermediate**: otherwise, reported as the estimate. **Uninformative**: kappa for E1, E2 or E3 below 0.60, or a captured share below 0.70 with no third source added.

C5, E9 and E10 are reported with intervals and without thresholds. E10b in particular measures how often the misdescription the entry itself made appears in print.

## Cost

Person-hours: screening about 190 records at 1.5 minutes by two screeners, 10; full-text eligibility, about 140 papers at 5 minutes by two, 23; full-text acquisition for records outside PMC, 5; extraction, about 110 papers at 30 minutes by two, 110; adjudication 12; analysis and write-up 20. Total about 180 hours. Compute is negligible. Data access: institutional full text for the part of search (a) not in PMC; Embase only if the capture check fails.

## Threats to validity

Abstract word limits constrain what can lead; a journal with a 250-word structured abstract may leave no room for absolute risks, so P1 partly measures journal format. The journal's abstract limit is recorded as a covariate. E3 is deliberately lenient, so P1 understates the problem if strategy names imply more than they state. The frame depends on the emulation label; clone-censor-weight analyses that do not describe themselves as emulations are missed. The census reflects a design whose early users were methodologists, so reporting may be better than in later adoption.

## Citations

- Maringe C, Benitez Majano S, Exarchakou A, et al. Reflection on modern methods: trial emulation in the presence of immortal-time bias. Assessing the benefit of major surgery for elderly lung cancer patients using observational data. International Journal of Epidemiology. 2020;49(5):1719-1729. doi:10.1093/ije/dyaa057
- Hernán MA. How to estimate the effect of treatment duration on survival outcomes using observational data. BMJ. 2018:k182. doi:10.1136/bmj.k182
- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334(12):1084. doi:10.1001/jama.2025.13350
- Hansford HJ, Cashin AG, Jones MD, et al. Reporting of Observational Studies Explicitly Aiming to Emulate Randomized Trials. JAMA Network Open. 2023;6(9):e2336023. doi:10.1001/jamanetworkopen.2023.36023
