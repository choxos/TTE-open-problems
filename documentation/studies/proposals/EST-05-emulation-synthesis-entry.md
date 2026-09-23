# EST-05: how emulations enter syntheses with randomized trials, and whether a benchmark-calibrated discrepancy would transport

**Catalog problem.** An emulation enters a synthesis with randomized trials through a discrepancy parameter that nothing identifies. Verdict `confirmed-open`, supported with caveat; triage: corpus, answerable in part, feasibility 2.

**Residual claim this design tests.** Two qualifications survive adjudication. First (codex): once outcome, horizon, strategies, intercurrent events and population are aligned, an unanchored synthesis still cannot decompose a trial and emulation difference into residual emulation bias and real effect heterogeneity, so pooling needs explicit exchangeability or transport assumptions, external data, or a prior; a discrepancy distribution learned from benchmark pairs is itself a transport assumption, not identification. Second (literature auditor): estimand alignment before pooling has been worked out for the external comparator route since 2024 and remains unaddressed for entry into a network meta-analysis and substitution into an economic model. The non-identification is a mathematical statement that no corpus can test. What a corpus can test is the practice half, how published syntheses set the discrepancy in fact, and the entry's proposed remedy, whether a discrepancy distribution estimated from benchmark programs predicts the discrepancy in a program it was not estimated from.

## Questions

**A (primary).** Among published quantitative syntheses that combine at least one emulation estimate with at least one randomized estimate, what fraction admit the emulation with no stated admission criterion, no statement of which contrast each source identifies, and a discrepancy term that is either absent or set by judgment with no sensitivity analysis over it?

**B (secondary).** Across benchmark programs that pair emulations with the trials they emulate, does the discrepancy distribution estimated from the other programs cover the discrepancies of a held-out program, and how much would entering emulations through that distribution change the syntheses found in A?

## What this leaves unanswered

The bias of any single emulation, which is not identified. Health technology assessment submissions that never reach a journal, except as a supplementary count. Whether balancing post-baseline treatment patterns inside a borrowing method works, which is a simulation question. The entry's numerical rheumatoid arthritis example is not used: the audit showed its stated between-source odds ratio of 0.30 is inconsistent with the probabilities 0.215 and 0.650, which imply 0.147.

## Design, component A: the synthesis corpus

### Sampling frame

A census of three sources, each retrieved on 2026-09-23 and frozen as an ID list.

(a) PubMed, exactly:

```
("target trial"[tiab] OR "target trials"[tiab] OR "trial emulation"[tiab] OR "trial emulations"[tiab] OR "emulated trial"[tiab] OR "emulated trials"[tiab]) AND ("network meta-analysis"[tiab] OR "meta-analysis"[tiab] OR "evidence synthesis"[tiab] OR "cost-effectiveness"[tiab] OR "external control"[tiab] OR "hybrid control"[tiab] OR "synthetic control arm"[tiab] OR "power prior"[tiab] OR "borrowing"[tiab]) AND ("2016/01/01"[dp] : "2026/06/30"[dp])
```

89 records. It retrieves the three known instances in the catalog entry (Bujkiewicz 2022, Lai 2024, Singh 2026), checked by DOI on the same date.

(b) Forward citations of five seed works through OpenAlex, `https://api.openalex.org/works?filter=cites:<id>`: W2575452307 (Efthimiou 2017, 191 citing works), W2141408576 (Schmitz 2013, 124), W4401345771 (Hamza 2024, 6), W4285604427 (Bujkiewicz 2022, 10), W3195798356 (Tan 2022, 23). About 354 before deduplication. The borrowing and cross-design literature is poorly indexed by emulation phrases: the repository's literature audit found that power prior, dynamic borrowing and commensurate prior together matched one of 1,376 screened records.

(c) Supplementary and reported separately: NICE technology appraisal documents found by searching the NICE website for "target trial emulation" and "trial emulation" on the retrieval date. These are where the entry says pooled estimates reach decisions, but the search is not reproducible to the standard of (a) and (b), so they do not enter the primary estimate.

### Inclusion

Included: a quantitative synthesis or decision model in which an effect estimate from a study described, by itself or by the synthesis, as a target trial emulation or trial emulation is combined in one parameter with at least one randomized estimate: pooled in a pairwise or network meta-analysis, used as or inside a prior, borrowed into a randomized arm, used as an external control with any borrowing weight, or pooled into an economic model input. Excluded: side-by-side presentation with no combination (counted as "compared only"); benchmarking studies whose aim is to compare an emulation with its trial (these are component B); methods papers on simulated data only. Two screeners independently; a third resolves.

### Extraction items

- **S1, route**: network meta-analysis; pairwise meta-analysis; three-level or cross-design hierarchical model; hybrid control; external control with borrowing; economic model input.
- **S2, entry mechanism**: face value, as if randomized; fixed design adjustment; variance inflation; power or commensurate prior with a fixed weight; dynamic borrowing with the weight driven by outcome agreement; hierarchical model with a design-level variance; bias adjustment with an elicited or external bias distribution.
- **S3, source of the discrepancy term**: none; fixed by judgment with no stated source; estimated from outcome agreement in the data being combined; calibrated on external benchmark data (which, quoted); elicited from experts.
- **S4, admission criterion**: an explicit rule for which emulations may enter.
- **S5, estimand alignment**: a statement of which contrast each source identifies (assignment or per-protocol, horizon, population) and any reweighting or re-emulation to align them. Coded by route, so the external comparator route, where alignment methods exist, is reported apart from the network and economic routes.
- **S6, sensitivity over the discrepancy**: the pooled estimate reported under at least two values of the bias term or borrowing weight.
- **S7**: source-specific estimates reported beside the pooled estimate. **S8**: the emulation's implied weight or contribution reported.
- **S9**: the source-specific estimates themselves (scale, estimate, standard error or interval), needed for the re-analysis in component B.

**Primary outcome P, unanchored entry**: S4 absent, S5 absent, S3 is "none" or "judgment", and S6 absent.

### Extraction record and verification

Each item is a JSON record `{"paper", "item", "value", "quote", "locator", "extractor", "source_file"}`; every positive value carries a verbatim quote and a locator (section and paragraph, table, supplement item, or the page of a NICE document). An absent value carries the sections read and the output of a scripted search of the full text and supplements for a registered term list (bias, discount, down-weight, power prior, commensurate, borrow, exchangeab, admission, inclusion criteria, estimand, intention-to-treat, per-protocol, sensitivity). Text comes from `pdftotext` into a scratch directory, one file per paper; records are appended one paper at a time by a script in the pattern of `build/lit/add_finding.py`; quotes are checked with the collapsed-text matcher in `build/lit/verify_quotes.py` (import `norm`, `split_elisions`, `spans`, `coverage`), and a NOT-FOUND quote voids its value until corrected. Every item is double-extracted; a third reviewer adjudicates; kappa and Gwet's AC1 per item, with items below kappa 0.60 barred from the decision rule.

### Sample size

A census; the expected eligible count is 30 to 60. From exact binomial sums with Wilson intervals: with 45 eligible syntheses, a true P of 0.75 reaches "real" with probability 0.93 and a true P of 0.10 reaches "not real" with probability 0.71; with 60, the figures are 0.99 and 0.86. Below 30 eligible syntheses the result is reported descriptively, since the rule would then rarely leave the intermediate zone.

## Design, component B: discrepancy calibration and transport

### Pair frame

The 29 hazard-ratio pairs of RCT-DUPLICATE analyzed by Heyard 2024 (from the 32 of Wang 2023), plus pairs from PubMed, exactly:

```
("RCT-DUPLICATE"[tiab] OR ((benchmark*[tiab] OR "replicate"[tiab] OR "replication"[tiab] OR "calibrat*"[tiab]) AND ("target trial"[tiab] OR "trial emulation"[tiab] OR "emulated trial"[tiab] OR "emulating"[tiab] OR "emulate"[tiab]) AND (randomized[tiab] OR randomised[tiab] OR RCT[tiab] OR RCTs[tiab]))) AND ("2016/01/01"[dp] : "2026/06/30"[dp])
```

86 records on 2026-09-23, plus any component A synthesis that reports both source-specific estimates for one contrast. A pair is included when an emulation was designed to answer a named randomized trial's question and reports the trial's primary outcome on a ratio scale with an interval, and the trial's result on the same scale is available.

### Alignment coding

Double-coded per pair, each with quote and locator: whether the treatment contrast matches; the estimand type on each side (assignment analog or per-protocol); horizon; outcome definition; population match on the trial's key eligibility criteria; data source type; therapeutic area; and program (RCT-DUPLICATE, oncology external control programs, other). The alignment score is the count of matched attributes among contrast, estimand type, horizon, outcome and population.

### Model

`d_i = log(ratio_emulation / ratio_trial)`, with `d_i ~ N(mu_p + x_i * b, tau^2 + v_i)` and `mu_p ~ N(mu, omega^2)` over programs, where `v_i` is the sum of the two sampling variances and `x_i` the alignment score. Bayesian fit with half-normal(0, 0.5) priors on `tau` and `omega`, normal(0, 1) on `mu` and `b`; prior sensitivity with half-normal(0, 1). Convergence rule: an estimate is used only if every R-hat is at most 1.01 and bulk effective sample size at least 400; a fit that fails is refit with longer chains once and otherwise reported as failed, not summarized.

**Transport check.** Leave one program out: fit on the others, form the 90% predictive interval `N(mu + x_i * b, omega^2 + tau^2 + v_i)` for each held-out pair, and record coverage. Repeat leaving out one therapeutic area. Because coverage can be bought with width, the predictive standard deviation of `d` is reported against the median trial standard error: a calibrated prior wider than twice that makes an entering emulation nearly uninformative, which is itself the answer to "how much of the pooled number is borrowed".

**Re-analysis.** For every component A synthesis with S9 available, recompute the pooled estimate with the emulation entering as `theta_E ~ N(theta + mu_hat, v_E + s_pred^2)`, using the calibrated `mu_hat` and predictive variance `s_pred^2`, and report the change in the pooled estimate, in the emulation's weight, and whether the synthesis's own stated conclusion (an interval excluding the null, or a stated decision threshold) changes.

### Size and compute

Expected 60 to 90 pairs over four to six programs. The leave-one-program-out check needs at least three programs with eight or more pairs each; if fewer qualify it is reported as not estimable, and component B reduces to the pooled discrepancy distribution and the re-analysis. Compute: a hierarchical normal model on under 100 observations fits in seconds; with the leave-one-out fits, two prior settings and the re-analyses, the total is under one CPU-hour on one core.

## What would show the problem real or not real

**Component A.**
- Real: the lower 95% bound of P exceeds 0.50. Most syntheses admit emulations with no admission rule, no alignment statement and a discrepancy set by assumption, as the entry says.
- Not real: the upper bound is below 0.25. Anchored entry is the norm and the practice half of the entry is wrong.
- Intermediate otherwise; uninformative if fewer than 30 syntheses qualify or kappa for S3, S4, S5 or S6 is below 0.60.

**Component B.**
- The remedy transports: pooled held-out coverage of the nominal 90% intervals is at least 0.85 and no held-out program with eight or more pairs falls below 0.70.
- The remedy does not transport: pooled held-out coverage is below 0.75, or any such program falls below 0.60. The discrepancy then depends on the program, and a benchmark-calibrated prior imported into a new domain is a judgment in another form, which supports the entry's structural claim in practice.
- Uninformative: fewer than three programs with eight or more pairs, or coverage between the two bounds.
- The re-analysis is reported as the share of syntheses whose stated conclusion changes, without a threshold.

## Cost

Person-hours. Component A: screening about 440 records at 1.5 minutes by two, 22; full-text eligibility about 90 at 10 minutes by two, 30; extraction about 50 syntheses at 60 minutes by two, 100; adjudication 15; the NICE supplement 15. Component B: pair screening 5; pair extraction and alignment coding, about 80 pairs at 40 minutes by two, 107; model, transport check and re-analysis 45; write-up 25. Total about 365 hours. Compute under one CPU-hour, derived above. Data access: institutional full text for syntheses outside open access; OpenAlex and PubMed are public.

## Threats to validity

Benchmark pairs are selected for emulability (RCT-DUPLICATE chose trials on feasibility), so the discrepancy distribution is optimistic for syntheses that admit emulations of arbitrary questions. Program is confounded with data source and therapeutic area, so "does not transport" cannot say which of the three is responsible. Benchmark results may be published selectively. A discrepancy combines bias with real differences between trial and routine-care populations; the model calls the sum a discrepancy and never calls it bias. Component A depends on syntheses describing their inputs as emulations; a synthesis that pools an observational estimate without the label is outside the frame.

## Citations

- Efthimiou O, Mavridis D, Debray TPA, et al. Combining randomized and non-randomized evidence in network meta-analysis. Statistics in Medicine. 2017;36(8):1210-1226. doi:10.1002/sim.7223
- Schmitz S, Adams R, Walsh C. Incorporating data from various trial designs into a mixed treatment comparison model. Statistics in Medicine. 2013;32(17):2935-2949. doi:10.1002/sim.5764
- Hamza T, Schwarzer G, Salanti G. crossnma: An R package to synthesize cross-design evidence and cross-format data using network meta-analysis and network meta-regression. BMC Medical Research Methodology. 2024;24(1):169. doi:10.1186/s12874-023-02130-0
- Bujkiewicz S, Singh J, Wheaton L, et al. Bridging disconnected networks of first and second lines of biologic therapies in rheumatoid arthritis with registry data: bayesian evidence synthesis with target trial emulation. Journal of Clinical Epidemiology. 2022;150:171-178. doi:10.1016/j.jclinepi.2022.06.011
- Singh J, Stevenson M, Hyrich KL, Gillies CL, Abrams KR, Bujkiewicz S. Target Trial Emulation to Incorporate Real-World Data in the Estimation of the Clinical and Cost-Effectiveness of Biologic Treatment. Medical Decision Making. 2026;46(3):386-398. doi:10.1177/0272989X251408484
- Tan WK, Segal BD, Curtis MD, et al. Augmenting control arms with real-world data for cancer trials: Hybrid control arm methods and considerations. Contemporary Clinical Trials Communications. 2022;30:101000. doi:10.1016/j.conctc.2022.101000
- Lai PC, Lai CH, Lai ECC, Huang YT. Do We Need to Administer Fludrocortisone in Addition to Hydrocortisone in Adult Patients With Septic Shock? An Updated Systematic Review With Bayesian Network Meta-Analysis of Randomized Controlled Trials and an Observational Study With Target Trial Emulation. Critical Care Medicine. 2024;52(4):e193-e202. doi:10.1097/CCM.0000000000006161
- Wang SV, Schneeweiss S, RCT-DUPLICATE Initiative, et al. Emulation of Randomized Clinical Trials With Nonrandomized Database Analyses. JAMA. 2023;329(16):1376. doi:10.1001/jama.2023.4221
- Heyard R, Held L, Schneeweiss S, Wang SV. Design differences and variation in results between randomised trials and non-randomised emulations: meta-analysis of RCT-DUPLICATE data. BMJ Medicine. 2024;3(1):e000709. doi:10.1136/bmjmed-2023-000709
