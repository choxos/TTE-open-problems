# SEQ-01 proposed registered amendment

Proposed for registration before any replicate of the amended run is drawn, with a new master seed. It amends `documentation/studies/designs/SEQ-01-sequential-emulation-creates-repeated-partic-revised.json`. Everything not listed under "What changes" stays as registered.

## 1. Why the registered design cannot answer

**The stated reason is correct.** BLOCKED.md shows that the three models carrying the `G` by `factor(j)` by `ns(q_k, df = 4)` surface fail the registered coefficient guard (any required coefficient above 20) in 2000-person cohorts: 0 of 8 replicates of scenario 1 fit `equal_flexible`, with a median maximum coefficient of 11,710 and 77 of 144 treated cells empty. At 20,000 people 3 of 3 fit, the median maximum coefficient is 3.98 and 5 of 144 cells are empty. The flexible estimator is the reference for every attribution the decision rule makes, so every conclusion that needs it is uninformative at 2000.

**It is incomplete in two ways.**

*The near-homogeneous truth set is empty, at every cohort size.* The committed truth (`results/truth-scenarios.csv`) classifies 10 of the 12 scenarios as material (simultaneous lower bound of `Delta_RD` from 0.034 to 0.093) and scenarios 7 and 10 as indifference (bounds 0.0070 to 0.0083 and 0.0105 to 0.0121). No scenario has an upper bound at or below 0.005, so the near-homogeneous set N is empty. The registered rule makes a conclusion uninformative "when fewer than three scenarios enter H or fewer than two enter N". Three of the four primary conclusions need N: the pooling conclusion (both branches require adequacy counts over N), the diagnostic (specificity is defined over N), and pooling efficiency (counted over N). Only calendar omission can be decided. The cause is in the mechanism, not the code: with h = 0 the marginal risk difference still changes across starts because treatment lowers later severity (a mediated effect) and because the population eligible at later starts is selected on remaining untreated and event-free. The design fixed both deliberately, and truth is a superpopulation quantity, so a larger cohort cannot move any scenario into N.

*The cost is out of reach, and the implemented reduction cannot reach its own coverage bound.* Measured in scratch on this machine (one replicate of scenario 12 at 20,000 people, all seven methods fitted, `min_ess` 167): 56.4 CPU-seconds for the estimators and 6.1 CPU-seconds per full person-bootstrap refit. The registered 24,000 replicates therefore cost about 380 CPU-hours and the registered calibration overlay (4 sentinels by 200 replicates by 399 refits) about 540 CPU-hours. The implemented 500 replicates fall short in a different way: adequacy needs a simultaneous lower coverage bound of at least 0.93, and with a max-t multiplier near 3 over a manifest of several dozen entries, 500 replicates give 0.95 minus 3 times 0.0097, about 0.921, even when true coverage is exactly 0.95.

## 2. What changes

1. **Cohort size: 2000 to 20,000 people.** Reason: the flexible surface needs about ten times the treated events (BLOCKED.md). Truth does not depend on cohort size, so the committed truth for retained scenarios is reused.

2. **Scenario grid: 12 to 5.** Retain scenarios 1 (h none, a = 0, b = 0), 11 (monotone, a = 0.80, b = 0.35) and 12 (cosine, a = 0.80, b = 0.35), the three registered sentinels whose truth is material. Add two scenarios with no treatment effect: the direct term `log(0.70)` is replaced by 0 and the treatment term `-0.30 Z` in the severity transition is replaced by 0, with h none, at (a = 0, b = 0) and (a = 0.80, b = 0.35). Every other coefficient is unchanged. Reason: under paired common-random-number truth every `RD_k` is exactly zero in these two, so N has two members by construction, and the minimum grid that satisfies |H| at least 3 and |N| at least 2 has five scenarios. Membership in H and N is still decided by the registered truth computation. This conflicts with the registered statement that "no scenario is designated an exact marginal-effect null from its factor labels": these two scenarios are nulls by construction. The conflict is unavoidable, because the registered mechanism cannot populate N at any cohort size, so an empty N is a design failure rather than a result; it is the owner's decision.

3. **Replicates: 2000 to 1200 per scenario; minimum valid paired replicates 1900 to 1140.** The minimum keeps the registered 95% proportion. Reason: cost (section 4).

4. **Decision manifest.** The calendar-ablation signed biases leave the max-t manifest because the calendar-omission conclusion is dropped (item 5). All other manifest entries, the 9999 two-layer metric resamples and every threshold stay as registered.

5. **Calendar-omission conclusion dropped.** Its factorial interaction needs all four a by b cells within at least two h patterns, which the five-scenario grid does not contain. The omitted, quadratic and flexible variants are still fitted in every replicate and their biases are reported descriptively.

6. **Full person-bootstrap overlay: descriptive only, owner's decision.** Run it in scenario 12 on the first 25 valid replicates with 99 resamples and report bootstrap versus linearized standard errors. Remove the two triggers tied to it ("fewer than 180 full-bootstrap calibration replicates" and "simultaneous difference between full-bootstrap and linearized coverage exceeds 0.02"). Reason: the registered overlay alone costs about 540 CPU-hours, and the quantity it guards, coverage of the linearized intervals, is measured directly against truth in the main run. This removes a validity check rather than relaxing a threshold, so it needs the owner's explicit approval; if it is refused, the overlay at its registered size must be budgeted separately.

7. **Pilot stop rule (added).** Before the main run, 20 replicates of scenario 1 at 20,000 people. If fewer than 19 fit `equal_flexible`, stop and re-amend the cohort size.

## 3. The gates can pass

| gate or branch | quantity under the amendment | registered requirement | margin |
|---|---|---|---|
| flexible model fits | 3 of 3 (BLOCKED.md) and 1 of 1 (scratch, scenario 12), median maximum coefficient 3.98 | at least 95% valid paired replicates | pilot rule above; not provable before the run |
| effective sample size per cell | minimum 167 (scratch, scenario 12, 20,000 people) | at least 10 in 90% of replicates | 16-fold |
| size of H | scenarios 1, 11, 12: truth lower bounds 0.034, 0.070, 0.061 | at least 3 with lower bound at least 0.020 | met exactly |
| size of N | two null scenarios: `Delta_RD` exactly 0 | at least 2 with upper bound at most 0.005 | met exactly |
| truth precision for `theta_equal` | committed half-widths about 0.0001 to 0.0002 | below 0.001 | 5-fold or more |
| coverage adequate | simultaneous lower bound at true 0.95: 0.95 minus 2.9 times 0.0063, about 0.932 | at least 0.93 | reachable when true coverage is at least about 0.948 |
| coverage inadequate | upper bound at true 0.85: about 0.88 | at most 0.90 | reachable |
| bias adequate | SE of `theta_equal` at 20,000 about 0.006 (scratch); Monte Carlo SE 0.00018; bound 2.9 times that, 0.0005 | upper absolute-bias bound at most 0.005 | adequate for true absolute bias up to about 0.0045 |
| bias inadequate | same Monte Carlo error | lower bound at least 0.010 | reachable for true absolute bias of about 0.0105 or more |
| diagnostic sensitivity (H, 3 scenarios) | Monte Carlo SE of the equal-scenario mean about 0.008 | lower bound at least 0.80 adequate, upper at most 0.60 inadequate | adequate when true mean sensitivity is at least about 0.83 |
| diagnostic specificity (N, 2 scenarios) | about 0.0045 at true 0.95 | lower bound at least 0.90 | adequate when true specificity is at least about 0.92 |
| pooling efficiency | variance ratio of flexible pooled to standalone `RD_12`, relative Monte Carlo error about 4% | upper bound below 1 in both N scenarios, or lower bound at least 1 | either branch reachable when the true ratio is below about 0.88 or above about 1.12 |

The multiplier 2.9 is the approximate 95% max-t critical value for the amended manifest (about 27 correlated entries: signed bias and coverage for two estimators in five scenarios, sensitivity, specificity and five variance ratios); the registered procedure computes it from the replicates. Both pooling branches keep their registered form: with |H| = 3 and |N| = 2, "degrades" needs the matched common estimator inadequate and the flexible adequate in 2 of 3 H scenarios with both adequate in both N scenarios; "accurate averaging despite heterogeneity" needs both adequate in 2 of 3 H and both N.

## 4. Cost

Main run: 5 scenarios by 1200 replicates by 57 CPU-seconds (56.4 for estimators plus 0.3 for generation, measured at 20,000 people) is 342,000 CPU-seconds, 95 CPU-hours. Truth for the two null scenarios with the registered adaptive rule: the committed scenarios took 68 to 253 seconds each, under 0.2 CPU-hours. Descriptive overlay: 25 by 99 refits by 6.1 seconds is 4.2 CPU-hours. Total about 100 CPU-hours. The timings were taken at load averages of 300 to 700 and are, if anything, inflated by contention. Holding the registered 2000 replicates in the same five scenarios would cost 158 CPU-hours and make coverage adequacy reachable down to a true coverage of about 0.945; this is the owner's choice between budget and margin.

## 5. What the amended study no longer answers

- Whether omitting or quadratically modeling calendar time is consequential, as a decided conclusion; biases are reported without a verdict.
- Nine of the twelve registered scenarios: every setting with a single calendar trend, the monotone and cosine patterns without calendar trends, and h none with both trends.
- Near-homogeneity with a nonzero effect: N contains only null-effect scenarios, so "accurate averaging despite heterogeneity" and pooling efficiency are judged against a null control, not against a homogeneous nonzero effect. The registered mechanism cannot produce the latter without solving h for homogeneity, which the design forbids.
- Agreement between full person-bootstrap and linearized inference as a gate; it becomes a descriptive check in one scenario.
- Results describe 20,000-person cohorts, not the 2000-person cohorts named in the registered limitations.
