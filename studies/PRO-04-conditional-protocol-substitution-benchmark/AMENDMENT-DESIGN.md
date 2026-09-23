# PRO-04 amendment: tiered replicates at the registered sample size

Proposed registered amendment to `documentation/studies/designs/PRO-04-an-unobservable-protocol-component-produces-revised.json`. It is committed before any replicate of the amended run is drawn, under a new master seed. Nothing below has been run under it. Every number attributed to a scratch check was produced by the scripts in the design agent's scratch directory, which source this study's `R/00-config.R`, `R/01-dgm.R` and `R/02-estimators.R` after `_shared/R/guards.R` and write nothing under `results/`; together they used about 1.5 CPU-minutes.

## 1. Why the registered design cannot answer

`FEASIBILITY.md` says the study is blocked by cost: the power rule selects N = 948,000, one replicate takes 87 s and 565 MB, and the run needs about 580 CPU-hours at the implemented 1,000 replicates per stratum and 1,450 at the registered 2,500. The sample size is correct. `FEASIBILITY.md` records the load average of about 200, but it multiplies the 87 s out as though it were CPU cost, and cost is not what stops the study from answering.

**The 87 s is wall time on a saturated machine, not CPU time.** One full replicate (all seven methods) at N = 948,000, drawn from scratch-seed mechanisms in strata 22, 23 and 24 (severe, effect modification present, differential; one per component), used 7.1, 4.8 and 6.7 CPU-seconds (user plus system) and 78.6, 63.6 and 80.1 s of wall time at load averages of 262 to 548. At the mean of 6.2 CPU-seconds the implemented design (24 strata by 1,000) costs about 41 CPU-hours and the registered design (24 by 2,500) about 103; at the slowest measured replicate, 47 and 118. The wall-clock problem is real, but it is a property of the shared machine and no design change fixes it except spending fewer CPU-seconds.

**The primary answer does not use a single replicate.** `R/05-analyze.R` computes P_M, P_P and the response surface from `truth` alone, and truth is deterministic quadrature from the mechanism parameters. Truth for 24,000 mechanisms under the registered seed already exists and passes every truth gate: all 24,000 converged at 256 nodes with the margin class resolved, all 24,000 calibrations are within 1e-9, and the largest |Delta| among the 8,000 lambda-zero eligibility and strategy controls is 2.6e-16. Replicates enter the primary conclusion only through the global validity gate on oracle and operational calibration.

**That gate cannot pass as implemented.** It requires, for each of 24 strata and each of the oracle and explicitly labeled operational methods, that the 95% Wilson interval for coverage lie wholly inside [0.93, 0.97]: 48 checks. By exact binomial summation, with true coverage exactly 0.95 in every stratum and the checks treated as independent, all 48 pass with probability 3.5e-9 at the implemented R = 1,000 and 0.49 at the registered R = 2,500. The oracle and operational rows of a stratum share datasets and are positively correlated, which raises these figures somewhat, but not to a usable level at R = 1,000. At R = 1,000 one check passes only when observed coverage falls between 0.9460 and 0.9590, which happens with probability 0.67. The comment in `R/00-config.R` that records the cut from 2,500 to 1,000 names only the rise in probability MCSE and misses this. It is the failure that made PRO-02's first run inconclusive.

**The augmented recovery label has the same defect and an unreachable branch.** It applies the same coverage window to 24 strata: all pass with probability 5.9e-5 at R = 1,000 and 0.70 at R = 2,500 under exact calibration. Its precision criteria are vacuous at N = 948,000: the worst-case expected augmented psi_I interval width is 0.0091 against a limit of 0.04, and the largest stratum-mean asymptotic SE is about 0.002 against an RMSE limit of 0.015. "Calibrated but imprecise" would need finite-sample standard errors four times the asymptotic ones.

**Two registered labels are settled before any replicate is drawn.** The study's own `truth_for_mechanism` and `power_variances` (64 nodes) were evaluated on 2,400 scratch-seed mechanisms, 100 per stratum.

- *Primary decision.* Scratch P_M = 0.227 (MCSE 0.0045) and P_P = 0.666 (MCSE 0.0040). The positive branch needs the lower 95% bound of P_M above 0.30; the negative branch needs the upper bound of P_M below 0.10 and the lower bound of P_P above 0.80. With the registered 2,500 mechanisms per stratum the MCSE of P_M is about 0.0009, so the interval lies roughly 80 MCSEs from either threshold. The registered rule returns "mixed or threshold-indeterminate" with probability indistinguishable from 1, for any N, replicate count or seed, because P_M is a property of the declared mechanism distribution. The registered-seed truth already on disk will give the same classification. P_M and P_P were not computed from it in preparing this amendment; the tail of `results/truth.log`, printed while locating files, showed the registered-seed material and preserving rates of strata 22 to 24, and no other registered-seed truth summary was read.
- *Diagnostic label at N = 948,000.* From each mechanism's Delta and asymptotic gap variance, the expected pooled preserving sensitivity is 0.9996, changed sensitivity 1.0000, and the indeterminate rates 0.0004 and 0.0000. Of the 1,265 scored preserving mechanisms, 800 (63%) are exact lambda-zero controls. "Usable" is certain unless finite-sample behavior departs from the normal approximation.

What the simulation can still add is finite-sample calibration: whether the Wald intervals, the augmented estimator and the gap diagnostic behave as their asymptotic calculations predict, at the sample sizes where each registered criterion binds. The amendment spends replicates on that and keeps every margin, threshold, estimand, mechanism distribution and the power rule.

**What the owner must decide.** The primary branch is fixed at "mixed" by the registered design. The choices are to run this amendment and publish the registered classification with the stratum probabilities and the response surface, which the registered rule already requires in the mixed branch, or to treat the primary aim as answered by quadrature and keep only the calibration tiers. Changing the decision thresholds or the mechanism distribution now would be done with the answer in view; that is a new study, not an amendment.

## 2. What changes

Everything not listed stays as registered: the DGM, the 24 strata, the mechanism distributions, psi_I, psi_O and Delta, the seven methods and their variance and failure rules, the margins (0.01 and 0.02, alternatives 0.005 and 0.015, 0.02 and 0.03), the diagnostic truths (0.005 and 0.03), the power rule `pro04-power-v1` and its N = 948,000, validation probability 0.50, every threshold in the decision table, and the bootstrap for P_M and P_P.

1. **Seed.** `MASTER_SEED = 20260924L`. Mechanisms are drawn as in `R/03-truth.R`, `set.seed(MASTER_SEED + 100000L * i)` for stratum i. The tiers share one stream sequence: the scenario table is extended to 48 rows, strata 1 to 24 at N = 948,000 (tiers G and D) and strata 25 to 48 repeating them at N_C (tier C), with a `tier` and an `n` column, and a single `run_design` call with `n_rep = 5000` and `MASTER_SEED` draws every replicate from `make_streams(48 * 5000, MASTER_SEED)`, so no two replicates share a stream. Two sequences from adjacent seeds are not guaranteed disjoint. Mechanisms are enumerated for strata 1 to 24 only; row i + 24 reads the mechanism table of stratum i. `CONFIG_SIGNATURE` changes, so every registered-seed truth and replicate cache is invalid. The power search does not depend on the seed; its registered result (`results/sample-size.rds`, N = 948,000) is carried over under a signature that omits replicate counts, and the run stops if the carried value differs from 948,000. *Reason:* the registered-seed truth has been computed and is on disk.

2. **Mechanism enumeration.** T = 5,000 mechanisms per stratum. P_M, P_P, the stratum probabilities, the margin sensitivity and the response surface use mechanisms 1 to 2,500 of each stratum, exactly the registered count. Mechanisms 2,501 to 5,000 are used only by the calibration tiers. *Reason:* each calibration replicate needs its own mechanism draw, and the primary estimate must not gain precision after its value is known.

3. **Tier G: calibration at the registered N.** N = 948,000; replicates r = 1 to 5,000 per stratum, replicate r on mechanism r; methods: operational (with its stipulated silent-labeling rows, which are the same numbers against psi_I) and oracle. The registered bias, coverage and convergence criteria are applied to these rows exactly as written. *Reason:* the coverage window needs 4,000 to 5,000 replicates per stratum to pass reliably under exact calibration (section 3). A calibration-only replicate costs 0.73 to 1.04 CPU-seconds against 4.8 to 7.1 for a full one, because the augmented estimator's cross-fitted regressions are about 85% of a full replicate.

4. **Tier D: diagnostic at the registered N.** Replicates r = 1 to 100 of tier G in every stratum also run validation-only, augmented, complete-case gap and augmented gap on the same dataset. The registered diagnostic label (preserving and changed sensitivity lower bounds at least 0.80, indeterminate upper bounds at most 0.20, scored only at |Delta| <= 0.005 and >= 0.03) is computed on these 2,400 replicates, pooled as registered. *Reason:* the label is pooled, its expected margins are large (section 3), and 100 per stratum keeps the stratum mix of the registered pool.

5. **Tier C: recovery at the width-criterion sample size.** N_C = 50,000; replicates r = 1 to 5,000 per stratum on mechanism r, independent datasets from tier G; all seven methods. N_C is the smallest multiple of 1,000 at which the registered width criterion (expected augmented psi_I 95% interval width at most 0.04 under the registered inflated worst-case variance 5.16) holds: 3.92 multiplied by the square root of 5.16/50,000 is 0.0398. It comes from the registered `criteria_at` with only that criterion active and was fixed without reference to any result. The registered global gate criteria are applied here as well, and the augmented recovery label (bias interval within plus or minus 0.005, coverage interval within [0.93, 0.97], RMSE at most 0.015, mean width at most 0.04, all per stratum) is evaluated here. The gap diagnostic is reported descriptively. *Reason:* at N = 948,000 the recovery label's precision branch is unreachable and its 24 coverage checks cannot be afforded at a passable replicate count (5,000 full replicates per stratum at the registered N would cost about 207 CPU-hours). At N_C the registered precision criteria bind.

6. **Global validity gate.** The registered oracle and operational bias, coverage and convergence criteria must hold in tier G and in tier C. This is stricter than the registered single application. `R/05-analyze.R` splits performance by (scenario, method, tier) through the extended scenario table, so rows at the two sample sizes never pool.

7. **Silent labeling.** Coverage of the operational interval for psi_I is reported at N_C (tier C) and N = 948,000 (tier G), beside the normal-theory curve Phi(1.96 − Delta/SE_N) − Phi(-1.96 − Delta/SE_N) evaluated per mechanism. *Reason:* the protocol already calls it a sample-size-dependent illustration; two sample sizes illustrate the dependence.

8. **Asymptotic operating characteristics.** For every enumerated mechanism, `power_variances` at 64 nodes, where the registered power search found every variance converged, gives the predicted preserving, changed and indeterminate probabilities at N_C and at 948,000 and the predicted augmented width at N_C. These are reported beside the simulated rates. They have no role in any decision.

9. **Pilot.** 100 replicates per stratum in tier C and 10 full replicates per stratum at N = 948,000, written to `results/pilot`, with the registered hardware, software, throughput and memory record. *Reason:* full-replicate cost at the registered N is already measured, and the registered 100 per stratum at that N would cost 4 CPU-hours for no new information.

### Alternatives considered and rejected

N below is what the registered `criteria_at` selects with the registered inflated worst-case variances (gap 3.83, psi_I 5.16) when one element changes. Expected pooled preserving sensitivity is from the 2,400 scratch mechanisms, under that row's classification rule; the last column is the sensitivity among mechanisms with 0.004 < |Delta| <= 0.005, the band the power guarantee is written for.

| Change | N | CPU per replicate relative to registered | Pooled preserving sensitivity | Band 0.004 to 0.005 |
|---|---:|---:|---:|---:|
| none (power 0.80 at \|Delta\| = 0.005, margin 0.01) | 948,000 | 1 | 1.000 | 0.993 |
| power target 0.70 | 722,000 | 0.76 | 0.999 | 0.980 |
| power target 0.50 | 416,000 | 0.44 | 0.988 | 0.907 |
| preserving truth scored at 0 instead of 0.005 | 329,000 | 0.35 | 0.973 | 0.853 |
| preservation margin 0.015 | 238,000 | 0.25 | 0.999 | 0.990 |
| preservation margin 0.02 | 108,000 | 0.11 | 0.997 | 0.990 |
| drop the preservation criterion | 76,000 | 0.08 | 0.347 | 0.338 |

- *Lower power target.* The worst-case guarantee is what lets a "not usable" verdict be read as a property of the method rather than of the sample size. At 0.50, a worst-case mechanism on the band edge is called preserving half the time by design, so a failed label says nothing about the two-phase design.
- *Score preservation at Delta = 0.* The guarantee then covers only exact preservation, and the mechanisms that matter in practice, small nonzero gaps, lose it.
- *Widen the preservation margin.* On an intended risk difference of -0.06, a margin of 0.015 or 0.02 calls a 25% to 33% change "preserving", and 0.02 removes the gray region between preservation and material change. The wide pair is already a registered sensitivity analysis for P_M and P_P; making it the diagnostic definition changes what preservation means.
- *Lower N with the registered rule, because the pooled label would pass anyway.* At 238,000 with the 0.01 margin the expected pooled sensitivity is 0.926, but only because 63% of the scored set are exact controls; in the band the guarantee is written for it is 0.757. That is a property of the declared mixture, not the worst-case guarantee.
- *Raise the replicate count of full replicates at the registered N.* 5,000 per stratum costs about 207 CPU-hours at the mean replicate cost.
- *Adopt PRO-02's replication gate* (fail a check only if its Bonferroni-adjusted Wilson interval lies wholly outside the window). It keeps the window but passes strata miscalibrated by up to about two points, which loosens the calibration test. It is not needed here, because calibration-only replicates are cheap enough to pass the registered test as written.

## 3. The gates can pass

Oracle and operational standard errors at N_C were measured on 48 scratch datasets (two per stratum): 0.0050 to 0.0061 and 0.0044 to 0.0058, minimum arm effective sample size 5,977. Standardized errors against the quadrature truth had mean -0.08 and SD 0.95 over 96 estimates, with the largest |z| 2.49. SEs at 948,000 are these multiplied by the square root of 50,000/948,000, about 0.23.

| Gate or branch | Quantity | Expected under the amendment | Threshold | Margin |
|---|---|---|---|---|
| Quadrature | convergence and class resolution per mechanism | 24,000 of 24,000 under the registered seed at 256 nodes; the amendment enumerates the same distribution | all | none failed in 24,000 |
| Mechanism calibration | max absolute calibration error | all 24,000 within tolerance under the registered seed | 1e-9 | none failed |
| Lambda-zero controls | \|Delta\| for eligibility and strategy with lambda = 0 | exactly 0: d1 = d2 = -0.06 everywhere, so psi_O = psi_I; observed maximum 2.6e-16 | 1e-7 | nine orders of magnitude |
| Bias, tier G | 95% MC interval for mean error, per stratum and method | true bias of order 1/N; half-width 1.96 SE/sqrt(5,000) at most 0.00004 | within plus or minus 0.005 | over 100-fold |
| Bias, tier C | same | half-width at most 0.00017 | within plus or minus 0.005 | about 30-fold |
| Coverage, each tier | 95% Wilson interval, 48 checks | a check passes when observed coverage is 0.9372 to 0.9652; all 48 pass with probability 0.9987 at true coverage 0.950, 0.982 at 0.948, 0.68 at 0.945 | inside [0.93, 0.97] | both tiers together: 0.997 at 0.950, 0.965 at 0.948 |
| Convergence | share of finite estimates | 1: a zero weighted denominator needs an empty arm, and the smallest arm effective size is about 6,000 at N_C | 1 | no failure possible in practice |
| Primary positive branch | lower bound of P_M | P_M about 0.227, interval half-width about 0.002 | above 0.30 | unreachable |
| Primary negative branch | upper P_M, lower P_P | 0.227 and 0.666 | below 0.10, above 0.80 | unreachable |
| Primary mixed branch | otherwise | probability about 1 | | as registered |
| Recovery label, tier C | bias, coverage, RMSE, mean width per stratum | bias half-width at most 0.0003; all 24 coverage checks pass with probability 0.9994 at 0.950; largest stratum-mean asymptotic SE 0.0085; largest stratum-mean width 0.0332, smallest 0.0254, largest single mechanism 0.0376 | 0.005; [0.93, 0.97]; 0.015; 0.04 | width 17% below the limit in the worst stratum |
| Diagnostic label, tier D | pooled Wilson bounds | expected 1,265 scored preserving and 319 changed replicates; expected lower bounds 0.996 (preserving) and 0.988 (changed); expected indeterminate upper bounds 0.004 and 0.012 | at least 0.80; at most 0.20 | about 0.19 on every criterion |
| Diagnostic, tier C (descriptive) | pooled rates | expected preserving sensitivity 0.096, changed 0.992 | none | |

Why true coverage should be close to 0.950: each estimator is a smooth function of weighted means with known assignment and validation probabilities, the two-sided Wald interval's coverage error is of order 1/n, and the smallest arm has about 6,000 effective observations at N_C. A stratum whose true coverage is 0.93 fails its check with probability about 0.98, so the gate still detects real miscalibration.

Reachability of the secondary labels, stated plainly:

- Recovery at N_C: "useful" is expected. "Calibrated but imprecise" is reached if finite-sample widths exceed the asymptotic ones by 20% or more in some stratum, which would itself be a finding about the cross-fitted augmented estimator at this sample size. "Not calibrated" is reached if a stratum's coverage falls outside roughly [0.937, 0.965] or its bias exceeds 0.005.
- Diagnostic at 948,000: "not usable" is reached only if finite-sample classification departs from the normal approximation. That is how the registered power rule was built, and the amendment does not change it. The informative contrast is between tiers: expected preserving sensitivity 0.096 at 50,000 against 0.9996 at 948,000.

## 4. Cost

CPU-seconds are user plus system time from the scratch runs: full replicates at N_C in six runs (0.23 to 0.48, mean 0.29); calibration-only replicates at 948,000 in three runs (0.73 to 1.04, mean 0.83); full replicates at 948,000 in three runs (4.8 to 7.1, mean 6.2); truth plus asymptotic variances, 59.3 s for 2,400 mechanisms (0.025 per mechanism).

| Component | Units | CPU-hours at mean cost | at maximum cost |
|---|---|---:|---:|
| Truth and asymptotic variances | 24 x 5,000 mechanisms at 0.025 s | 0.8 | 0.8 |
| Tier C | 24 x 5,000 at 0.29 s (0.48) | 9.7 | 15.9 |
| Tier G, calibration only | 24 x 4,900 at 0.83 s (1.04) | 27.1 | 34.0 |
| Tier D, full at 948,000 | 24 x 100 at 6.2 s (7.1) | 4.1 | 4.7 |
| Pilot | 24 x 100 in tier C, 24 x 10 full at 948,000 | 0.6 | 0.8 |
| Total | | 42.4 | 56.2 |
| With the registered 1.25 contingency | | 53 | 70 |

The power search is not rerun (item 1). Peak memory is about 565 MB per worker at 948,000 (`FEASIBILITY.md`), about 3.4 GB on six workers. The scratch processes ran at `nice -n 19` and received 7% to 13% of a core at load averages of 262 to 548; at that share six workers deliver about 0.6 of a core, and 53 CPU-hours take about 90 hours of wall time. On an idle machine six workers would take about 9 hours.

## 5. What the amended study no longer answers

- **Recovery of psi_I at the registered N.** The validation-only and augmented estimators are evaluated at 50,000, not 948,000. Width and RMSE shrink as N^(-1/2) and the O(1/n) calibration terms shrink faster, so "useful" at 50,000 implies the registered precision criteria at 948,000; the converse does not hold. At 948,000 the recovery estimators run only in tier D, on 100 replicates per stratum, so per-stratum recovery at the registered N is not estimated with the registered precision.
- **Stratum-level diagnostic and efficiency summaries at the registered N.** These rest on 100 replicates per stratum instead of 2,500. The pooled diagnostic label and the pooled complete-case to augmented variance ratio (2,400 replicates) remain precise; per-stratum indeterminate rates at 948,000 are descriptive.
- **Nothing about the primary aim.** P_M, P_P, the response surface, the margins and the decision rule are computed exactly as registered from 2,500 mechanisms per stratum. The amendment neither creates nor removes the fact that the registered rule's substantive branches are unreachable under the declared distribution.
