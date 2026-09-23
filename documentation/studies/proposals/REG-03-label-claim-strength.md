# REG-03: whether the emulation label buys causal language that the documented assumptions do not

**Catalog problem.** Calling an analysis a target trial emulation is treated as evidence about its assumption burden. Verdict `partially-addressed`; triage: corpus, answerable in part, feasibility 4, not a target trial emulation methods problem.

**Bearing on target trial emulation.** Causal claims that outrun their documented assumptions are common to observational research; what is specific here is whether adopting the emulation label is associated with stronger causal language than the same documented support earns without it.

**Residual claim this design tests.** The audit (codex) rejected the entry's single ladder: the requirements are not nested one at a time. Sustained strategies need history-specific consistency, sequential exchangeability and sequential positivity; transport adds population exchangeability and support; and target trial specification contributes temporal alignment, protocol clarity and estimand definition while guaranteeing none of consistency, exchangeability, positivity, valid measurement, correct estimation or transportability. This design therefore codes each identification requirement separately and never assigns a paper a rung. PLOS Medicine now requires every manuscript that relies on emulation to follow TARGET (Lumbard 2025), which makes the label cost a protocol and a mapping table but ties it to no assumption burden; that is the setting in which the label is measured.

## Questions

**Q1.** Among applied emulations published January 2024 to June 2026, what fraction draw a causal conclusion while neither arguing nor probing the core requirements that conclusion needs?

**Q2.** At the same level of documented support, do labeled emulations use causal language more often than unlabeled comparative-effectiveness studies from the same journals and months?

**Q3.** How often is the label itself offered as the reason a result is causal, unbiased or trial-like?

## What this leaves unanswered

How readers, reviewers and editors interpret the label, which is the literal claim of the entry; a corpus sees only what authors wrote. The direct test is a randomized experiment in which reviewers rate the credibility of the same abstract with and without the label, which this design does not run. Whether a named vocabulary of requirements would change practice.

## Design

### Sampling frame and sample

Labeled papers are the shared applied-emulation sample, drawn once and extracted with three forms (DTA-01, REG-03, SFW-03); sharing is an owner decision. PubMed, E-utilities `esearch`, exactly:

```
(("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) AND ("2024/01/01"[dp] : "2026/06/30"[dp]) AND english[la]) NOT (review[pt] OR systematic review[pt] OR meta-analysis[pt] OR editorial[pt] OR comment[pt] OR letter[pt] OR news[pt])
```

1,321 records on 2026-09-23, 847 in PMC, frozen as a PMID list. The window starts after the period Hansford 2023 reviewed (200 emulations, March 2012 to October 2022, of which 43% did not describe all key emulation components), so the sample measures practice since then. Two strata by the earlier of the electronic and print dates: before TARGET (2024-01-01 to 2025-09-22) and after (2025-09-23 to 2026-06-30); records dated "2025" with no month are excluded and counted. Each stratum is permuted with `set.seed(20260923)` and `x[sample.int(length(x))]` and screened in that order to a quota of 100 eligible papers. Inclusion: an applied study in humans estimating the effect of an intervention or treatment strategy on a health outcome from routinely collected, registry or cohort data, describing itself as a target trial emulation or trial emulation. Exclusion: method papers with illustrative applications, protocols, benchmarking of an existing trial, duplicates, conference abstracts. Two screeners at each stage, a third resolves. Feasibility studies whose result is a fitness verdict are in the shared sample for DTA-01; they carry no effect claim, so this form codes them "not applicable", excludes them from every REG-03 denominator, and reports their count.

**Unlabeled comparators.** For a seeded random 100 of the 200 labeled papers, one unlabeled study from the same journal within six months of its publication date, found with:

```
"<journal>"[ta] AND ("<date minus 6 months>"[dp] : "<date plus 6 months>"[dp]) AND (cohort[tiab] OR "real-world"[tiab] OR registry[tiab] OR claims[tiab] OR "electronic health records"[tiab]) AND (effectiveness[tiab] OR effect[tiab] OR "risk of"[tiab] OR associated[tiab]) NOT ("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) NOT (review[pt] OR systematic review[pt] OR meta-analysis[pt] OR editorial[pt] OR comment[pt] OR letter[pt])
```

screened in seeded random order until the first observational comparison of two or more treatment strategies on a health outcome whose full text does not use the emulation label. The window widens to twelve months if needed; a labeled paper with no match is dropped from Q2 and counted.

### Extraction items (REG-03 form)

- **K1, claim strength** of the principal conclusion, read from the abstract conclusion and the first paragraph of the discussion, highest level reached. 1: association with an explicit statement that it may not be causal. 2: association language without that statement. 3: causal language for the study population ("reduced", "prevented", "led to", "the effect of", "benefit"). 4: causal language with a clinical or policy recommendation. 5: causal language extended beyond the study population.
- **K2, documentation of each identification requirement**, coded 0 not mentioned, 1 named only ("assuming no unmeasured confounding"), 2 argued (a reason is given: a confounder-selection rationale or causal diagram, a validation citation, a definition of what counts as deviating from a strategy), 3 probed (a diagnostic or sensitivity analysis bearing on it: negative controls, quantitative bias analysis or the E-value of VanderWeele and Ding 2017, positivity diagnostics, alternative model specifications, a validation statistic in the same data). Requirements: baseline exchangeability; sequential exchangeability, coded only when a sustained or per-protocol strategy is estimated; positivity; consistency; measurement validity; model specification; transport, coded only when K1 is 5. Temporal alignment of eligibility, assignment and time zero is coded separately as implemented or not, from the methods.
- **K3, label as warrant**: a sentence offering the emulation framework as the reason the result is causal, unbiased or equivalent to a trial. A sentence that correctly scopes what the framework secures, such as preventing immortal time by aligning time zero, is coded "correct scope", not warrant.
- **K4**: where the label appears (title, abstract, methods only). **K5**: whether TARGET is cited.

**Overclaim O**, the primary item for Q1: K1 is 3 or higher, and at least one of the following holds: baseline exchangeability below 2; sequential exchangeability below 2 where a sustained strategy is estimated; temporal alignment not implemented; transport below 2 where K1 is 5. The definition is restricted to the requirements that carry the confounding burden, so that O does not become near universal merely because few papers argue positivity; the full requirement profile is reported descriptively.

### Blinding the claim coding

K1 is what Q2 compares, so it is coded blind to label status. A script replaces every emulation phrase and every word beginning "emulat" with the token `[DESIGN]` in the extracted abstract conclusion and first discussion paragraph of both labeled and unlabeled papers, and the K1 coders see only those masked passages, in random order across the two groups. K2 cannot be blinded, since the methods name the design, so K2 is coded by different people from K1.

### Extraction record and verification

Each item is a JSON record `{"paper", "item", "value", "quote", "locator", "extractor", "source_file"}`; every positive value carries a verbatim quote and a locator; K1 always carries the quote of the sentence coded. An absent K2 value carries the sections read and a scripted term search of text and supplements (confound, exchangeab, unmeasured, causal diagram, directed acyclic, positivity, overlap, consistency, validat, negative control, E-value, bias analysis, sensitivity analys, transport, generaliz). Text from `pdftotext`, one file per paper in a scratch directory; records appended one paper at a time in the pattern of `build/lit/add_finding.py`; quotes checked with the collapsed-text matcher in `build/lit/verify_quotes.py` (import `norm`, `split_elisions`, `spans`, `coverage`), with a NOT-FOUND quote voiding its value. K1, K2 and K3 are double-extracted for every paper; K4 and K5 on a random 25%. A third reviewer adjudicates. Kappa and Gwet's AC1 per item; any item below kappa 0.60 is barred from the decision rules.

### Sample size

**Q1**, 200 labeled papers. From exact binomial sums with Wilson intervals under the rule below: a true O of 0.35 reaches "real" with probability 0.87 and 0.40 with 0.995; a true O of 0.05 reaches "not real" with probability 0.70 and 0.03 with 0.98.

**Q2**, 100 matched pairs, analyzed by conditional logistic regression of K1 at 3 or higher on label, with the difference in core documentation score (the sum of K2 over baseline exchangeability, positivity, consistency and measurement validity, 0 to 12) as covariate. With causal-language shares of 0.55 labeled and 0.35 unlabeled, about 51 pairs are discordant and a McNemar-type test has power near 0.80 at two-sided 0.05. If the label has no effect, the 95% upper bound of the odds ratio falls near 1.7 with 50 discordant pairs, so the "no large effect" branch below is set at 2.0: it rules out a doubling of the odds and does not rule out a smaller effect. Resolving an odds ratio of 1.5 would need about 100 discordant pairs, roughly 200 matched pairs and 117 more hours, which is an owner decision.

## What would show the problem real or not real

**Q1.**
- Real: the lower 95% bound of O exceeds 0.25; at least one labeled emulation in four draws a causal conclusion without arguing or probing its confounding requirements.
- Not real: the upper bound is below 0.10.
- Intermediate otherwise; uninformative if kappa for K1 or for baseline exchangeability in K2 is below 0.60.

**Q2.**
- The label carries credibility: the lower 95% bound of the adjusted odds ratio exceeds 1. At equal documented support, the label goes with more causal language, which is the substitution the entry describes.
- No large label effect: the upper bound is below 2.0. Overclaiming, if present, is not attributable to the label, and the problem becomes the general one of observational reporting.
- Uninformative otherwise, or if fewer than 80 pairs are matched.

**Q3** is reported as a share with its interval and every K3 quote, without a threshold.

## Cost

Person-hours, with shared screening (about 50) and full-text acquisition (about 17) charged once across DTA-01, REG-03 and SFW-03: masking script 4; K1 on 200 labeled papers at 10 minutes by two, 67; K2 to K5 on 200 at 25 minutes by two, 167; comparator searching and screening, 100 at 15 minutes, 25; K1 on 100 comparators, 33; K2 on 100 comparators, 83; adjudication 30; analysis and write-up 30. REG-03 alone: about 440 hours, 505 with the shared screening charged here. Compute negligible. Data access: institutional full text for the roughly 36% of labeled papers outside PMC and for comparators outside PMC.

## Threats to validity

Claim strength is read from text whose conventions differ by journal; matching on journal and month holds house style roughly constant. The masking removes the label but not other cues (a protocol table, grace-period language), so K1 coders may still infer the design; after coding, each K1 coder guesses the label status of every passage, and the analysis is repeated in passages where the guess was wrong. Unlabeled comparators may differ from labeled studies in question and data, which the documentation covariate addresses only in part. The labeled frame depends on phrase use in titles and abstracts.

## Citations

- Lumbard H, on behalf of the PLOS Medicine Staff Editors. Raising the bar for causal inference: PLOS Medicine adopts the TARGET guidelines for target trial emulation studies. PLOS Medicine. 2025;22(10):e1004796. doi:10.1371/journal.pmed.1004796
- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334(12):1084. doi:10.1001/jama.2025.13350
- Hansford HJ, Cashin AG, Jones MD, et al. Reporting of Observational Studies Explicitly Aiming to Emulate Randomized Trials. JAMA Network Open. 2023;6(9):e2336023. doi:10.1001/jamanetworkopen.2023.36023
- VanderWeele TJ, Ding P. Sensitivity Analysis in Observational Research: Introducing the E-Value. Annals of Internal Medicine. 2017;167(4):268-274. doi:10.7326/m16-2607
