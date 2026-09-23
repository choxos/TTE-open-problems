# REG-01: what regulatory and HTA assessors accept, elicited on identical dossiers

**Catalog problem.** Regulators have no thresholds for adequate emulation, acceptable residual confounding or sufficient sensitivity analysis. Verdict `partially-addressed`; triage: consensus, answerable in part, feasibility 1, not a target trial emulation methods problem.

**Bearing on target trial emulation.** The acceptance boundary decides whether an emulation enters a regulatory or reimbursement decision at all; decision-specific criteria are what an emulation protocol would be written against.

**Residual claim this design tests.** The audit (codex) held that universal numerical cutoffs for adequacy, residual confounding and sensitivity analysis are not technically defensible, and that regulators can instead apply prespecified, decision-specific criteria built from protocol fidelity, identification plausibility, data fitness, diagnostics, quantitative bias analysis and decision robustness. BenchExCal, which the reading found to partly address the entry, says the same from inside a regulatory evaluation: decision-changing thresholds "must be defined in conjunction with the relevant decision-making organization and aligned with the specific context being considered" (Wang 2025, Methods, calibration step). So this design never seeks a universal threshold. It tests the entry's second claim, that reviewers have no consistent basis on which to accept or reject a submission, as between-reviewer agreement on identical dossiers, and it attempts the decision-specific criteria the audit says are defensible.

## Questions

**Q1.** Given identical synthetic emulation dossiers, do regulatory and HTA assessors agree on whether each suffices for its stated decision, and within a decision context do their implicit tolerances for residual confounding coincide?

**Q2.** Can a panel of such assessors reach consensus on written, decision-context-specific criteria for protocol fidelity, residual confounding and the minimum set of sensitivity analyses?

## What this leaves unanswered

Whether any agency adopts the criteria. Whether the criteria are correct: there is no empirical truth for acceptable bias, and the only empirical calibration route is benchmarking (EST-05, BEN-02). Agency positions: participants take part in a personal capacity, so results describe experienced assessors, not institutions.

## Design

Three stages: a document check of the premise, a dossier-rating experiment for Q1, and a modified Delphi for Q2. Reported under ACCORD (Gattrell 2024).

### Stage 0: premise check

Documents: the three guidance instruments listed in the entry's prior work, plus the real-world evidence guidance found by searching the website of each agency represented on the panel for "real-world evidence" and "target trial", with the search strings and dates recorded. Two people independently extract every statement that sets a number, a rule, or a required analysis for accepting non-randomized evidence of effectiveness or safety, each as a record with a verbatim quote and a locator (page and section). Quotes are checked against `pdftotext` output with the collapsed-text matcher in `build/lit/verify_quotes.py`. Output: per agency, whether any threshold exists, which confirms or refutes the entry's premise; and the criteria in use, which seed the dossier attributes and the Delphi statements.

### Stage 1: dossier rating

**Dossiers.** 48 synthetic dossiers of two pages each in one fixed template: the question; the target trial protocol and its emulation in the TARGET layout (Cashin 2025); a data-source and fitness summary; a diagnostics panel; the main result with its interval; sensitivity analyses; and benchmark evidence. The products are fictional to prevent recognition. Six attributes vary:

1. **Decision context** (3 levels): extension of indication for an approved drug; comparative effectiveness for reimbursement; refutation of a post-marketing safety signal.
2. **Margin** (2): the interval clears the decision threshold widely; the point estimate is beyond the threshold and the interval touches it.
3. **Protocol fidelity** (2): every component emulated; one essential component replaced and the replacement stated (an active comparator standing in for placebo, or an eligibility criterion unobservable).
4. **Residual confounding robustness** (3): an E-value for the interval limit (VanderWeele and Ding 2017) of 1.3, 1.8 or 2.5, beside a fixed statement that the strongest measured confounder has a risk ratio of 1.6 with the outcome.
5. **Diagnostics** (2): clean; strained (effective sample size 30% of nominal, extreme weights truncated).
6. **Benchmark evidence** (2): the same source and design emulated a related trial and agreed closely; none.

The full factorial has 144 cells. A D-efficient fraction of 48, with 16 per decision context, estimating all main effects and the context by robustness and context by margin interactions, is generated with `AlgDesign::optFederov` under a registered seed and split into two blocks of 24 balanced on context. Each participant rates one block, assigned at random, in random order. Per dossier: sufficient for the stated decision, yes or no; confidence, 1 to 9. After the block, for one dossier per context shown again with the robustness line blank, the participant states the smallest E-value for the interval limit at which they would accept. About two hours per participant; a pilot with five assessors not on the panel fixes wording and timing.

**Analysis.** Agreement on the yes or no judgment within the decision-maker panel: Fleiss kappa and Gwet's AC1, overall and per context, with intervals from a bootstrap over dossiers and raters. A mixed logistic model, `accept ~ context + margin + fidelity + log(E) + diagnostics + benchmark + context:log(E) + context:margin + (1 + log(E) | rater)`, gives each rater's implicit threshold per context: the log E-value at which predicted acceptance is 0.5 with the other attributes at their reference levels. The between-rater standard deviation of that threshold, per context, and the ICC of the directly elicited minimum E-values are the reliability quantities. The model is used only if it converges with a nonsingular random-effects covariance; otherwise the random slope is dropped and that is reported.

### Stage 2: modified Delphi

Three online, anonymous rounds, then a 90-minute ratification meeting with no new ratings. Statements are drafted per decision context from stage 0 criteria and stage 1 results, in three dimensions: protocol fidelity ("for this context, an emulation is adequate only if no essential protocol component is replaced"), residual confounding ("for this context, the E-value for the interval limit is at least X, relative to the strongest measured confounder"), and sensitivity analyses ("for this context, the minimum set is ..."). Numeric values offered in round 2 are the quartiles of the stage 1 implicit thresholds for that context. Rating on a 1 to 9 scale (1 to 3 inappropriate, 4 to 6 uncertain, 7 to 9 appropriate). Consensus to include: at least 70% of the decision-maker panel rate 7 to 9 and at most 15% rate 1 to 3; exclusion symmetrically. Statements without consensus are revised with the rating distribution and anonymized rationales and re-rated; none is re-rated after round 3.

### Participants

**Decision-maker panel**: current or former clinical, statistical or epidemiological assessors at drug regulators (FDA; EMA and national competent authorities of the EU network; MHRA; Health Canada; PMDA; TGA; Swissmedic) and HTA bodies (NICE; CDA-AMC; IQWiG or G-BA; HAS; Zorginstituut Nederland; PBAC), with at least three years in assessment and at least one assessment of non-randomized evidence. Target 15 regulatory and 15 HTA, floor 10 of each completing stage 1 and round 3. Consensus is computed on this panel and reported separately for the regulatory and HTA halves.

**Advisory panel**: sponsor real-world evidence and statistics leads (10) and academic methodologists (10), rating the same material; their results are reported beside the decision-maker panel's and do not count toward consensus.

**Why these numbers.** With 30 decision-makers each block of 24 dossiers is rated by 15. A design-stage simulation drew each yes or no judgment from a logistic model with a normal dossier effect (standard deviation 1.5, 3 or 5) and a normal rater effect (standard deviation 0.5), and bootstrapped Fleiss kappa over dossiers and raters, 12 replicates per setting: 95% interval widths were 0.23 to 0.26 for kappa between 0.26 and 0.70, and 0.25 to 0.28 at the floor of 10 raters per block. At 24 dossiers rated by 30 the width was 0.26 to 0.32, which is why the design uses 48 dossiers in two blocks rather than 24 rated by everyone. With 20 raters in the Delphi, one panelist moves a percentage by 5 points, so no single person decides the 70% rule.

**Recruitment and consent.** Invitation through professional networks and nomination by invitees; participation in a personal capacity, stated in the consent form; agency recorded only as regulatory or HTA and by region, to protect identity. Regulator participation is the binding constraint. The fallback is former regulators and HTA committee members; if that fallback supplies more than half the decision-maker panel, Q1 is read as a statement about experienced assessors and not about agency practice.

## What would show the problem real or not real

**Q1.**
- Real, no consistent basis: in the decision-maker panel the upper 95% bound of kappa is below 0.40; or, in any context, the between-rater standard deviation of implicit log E-value thresholds exceeds 0.25, meaning the central 80% of raters' thresholds spans more than the whole design range of 1.3 to 2.5.
- Not real, a consistent implicit basis exists without being written down: the lower bound of kappa exceeds 0.60 and in every context the between-rater standard deviation is below 0.10, the central 80% within a factor of 1.3.
- With interval widths near 0.24, a true kappa of 0.20 places the upper bound near 0.32, and a true kappa of 0.80 places the lower bound near 0.68, so both branches are reachable under plausible truths. Intermediate otherwise. Uninformative if fewer than 20 decision-makers complete stage 1.

**Q2.**
- Solution: in each of the three contexts, at least one statement per dimension reaches inclusion consensus. The deliverable is a context-by-dimension table of agreed criteria.
- Partial solution: consensus in some contexts or dimensions only; the table is published with its gaps.
- No solution, and why. If no statement reaches consensus in a context and stage 1 shows low within-context and high between-context variance in thresholds, the absence of a common threshold reflects decision dependence, as the entry's reasoning predicts. If stage 1 shows high within-context variance, the absence reflects disagreement among assessors about the same decision, which is the stronger form of the problem.
- Uninformative: fewer than 20 decision-makers complete round 3, or attrition from round 1 exceeds 35%.

## Cost

Person-hours: stage 0, 40; dossier template and 48 dossiers at 3 hours, 164; pilot 15; recruitment, consent and ethics submission 60; stage 1 analysis 30; Delphi facilitation, 3 rounds at 25, 75; meeting 10; write-up 40. Staff total about 435 hours. Participant time: about 2 hours in stage 1 and 2.25 hours in the Delphi for 50 participants, plus 1.5 hours of meeting for the 30 decision-makers, about 260 participant hours; honoraria are an owner decision. Compute: the kappa simulation and the mixed model take minutes. Data access: no patient data; minimal-risk ethics review and data protection compliance for participants in the European Union.

## Threats to validity

Hypothetical dossiers are not submissions; judgments made without consequence may be more lenient, and the pilot and the fixed TARGET template are the mitigation. The E-value is one summary of residual confounding among several; it is used because it is comparable across dossiers, and a rater who does not use it will show as noise, not as a threshold. Self-selection toward assessors interested in real-world evidence biases toward acceptance and toward agreement. Offering stage 1 quartiles in round 2 anchors the Delphi; this is deliberate, since the anchor is the panel's own revealed tolerance, and it is reported.

## Citations

- Wang SV, Russo M, Glynn RJ, et al. A Benchmark, Expand, and Calibration (BenchExCal) Trial Emulation Approach for Using Real-World Evidence to Support Indication Expansions: Design and Process for a Planned Empirical Evaluation. Clinical Pharmacology & Therapeutics. 2025;117(6):1820-1828. doi:10.1002/cpt.3621
- VanderWeele TJ, Ding P. Sensitivity Analysis in Observational Research: Introducing the E-Value. Annals of Internal Medicine. 2017;167(4):268-274. doi:10.7326/m16-2607
- Cashin AG, Hansford HJ, Hernán MA, et al. Transparent Reporting of Observational Studies Emulating a Target Trial: The TARGET Statement. JAMA. 2025;334(12):1084. doi:10.1001/jama.2025.13350
- Gattrell WT, Logullo P, van Zuuren EJ, et al. ACCORD (ACcurate COnsensus Reporting Document): A reporting guideline for consensus methods in biomedicine developed via a modified Delphi. PLOS Medicine. 2024;21(1):e1004326. doi:10.1371/journal.pmed.1004326
