# GMT-04 proposed registered amendment

Proposed amendment to the registered protocol in
`documentation/studies/designs/GMT-04-no-estimator-is-defensible-as-a-default-and-revised.json`.
It would be committed before any replicate of the amended run is drawn, under a new master seed
(20260923; bootstrap and analysis seeds 20260924 and 20260925). The truth manifest and its amendment of
2026-08-01 stand: the truths do not depend on n.

**Disclosure.** The registered protocol says the replicate count cannot change after implementation
labels or performance results are viewed. This amendment was written after viewing (a) the smoke rows in
`results/pilot/smoke.rds` (one replicate in each of three run scenarios at n = 1200, with estimates) and
(b) scratch checks that recorded IPTW output validity in the four primary scenarios and in C0, and the
difference between the IPTW and g-formula point estimates in C0 and C1. The same scratch script also
computed that difference in two primary scenarios; those lines were not read, and the scratch log has
been truncated to its C0 lines. Every change below is justified by a validity gate, a calibration
control or cost, not by any primary-scenario disagreement.

## 1. Why the registered design cannot answer

**The stated block, compute, is overstated more than tenfold.** BLOCKED.md quotes 110 to 470 seconds
per replicate and about 1500 CPU-hours at the implemented n = 1200. Those are elapsed times: the harness's `secs` column is
`proc.time()[["elapsed"]]`, and the machine's load average was about 200. `results/smoke.log` shows a
whole scenario-1 smoke process, including R start-up and the n = 4000 ltmle contract test, using 69 s
user and 7 s system CPU over 13 minutes of wall time. Measured CPU for one observed-U analysis
(s = 1.00, G0Q0): IPTW 0.5 s, g-formula 3.8 s and ltmle for both regimes 4.7 s at n = 1200; 0.4, 7.7 and
7.4 s at n = 4000. A factorial run scenario analyzes each generated dataset twice (U observed and
hidden), so a replicate costs about 18 CPU-s at n = 1200 and 31 at n = 4000. The registered design,
12 factorial run scenarios and 2 controls at 2000 replicates, is about 130 CPU-hours at the implemented
n = 1200 and about 224 at the registered n = 4000.

**The real block is that two validity gates cannot pass at the implemented n = 1200.** `00-config.R`
cut n from the registered 4000 to 1200 before any pilot, on the assumption that ltmle time is linear
in n, to keep 2000 replicates.

- *Complete-triplet gate* (at least 0.95 complete triplets in every primary scenario). A triplet needs a
  valid nuisance-adjusted IPTW output. In 20 generated datasets per scenario, IPTW output was valid in
  8 (s = 0.60, G0Q0), 9 (s = 0.60, G1Q1), 14 (s = 1.00, G0Q0) and 7 (s = 1.00, G1Q1) at n = 1200; in 19
  of 20 in each at n = 4000; and in 20 of 20 in each at n = 8000. The smoke run agrees: IPTW output was
  invalid in four of its six analyses. BLOCKED.md calls the invalid IPTW variance "not a defect", which
  is right about its cause and wrong about its size: at n = 1200 it removes 30% to 65% of triplets.
- *C0 calibration gate* (upper 95% bound for Pr(range of the three RDs > 0.03) below 0.20). The range
  is at least |IPTW − g-formula|. In C0, with the true RD 0, that difference had standard deviation
  0.033 at n = 1200 and exceeded 0.03 in 10 of 25 datasets, and 0.018 with 4 of 25 at n = 4000. So
  Pr(D = 1) in C0 is at least about 0.40 at n = 1200 and at least about 0.16 at n = 4000, before ltmle
  adds its own spread. The calibration control fails at 1200. At 4000 it is marginal: 0.16 alone gives
  an upper bound of 0.176 at 2000 replicates, so any ltmle contribution above a few points fails it,
  and the complete-triplet rate there (19 of 20 in each primary scenario) sits at the 0.95 gate itself. The 0.03 range threshold and the 0.20 probability threshold cannot
  be loosened; the sampling spread has to shrink.

## 2. What changes

Everything not listed stays as registered.

1. **n = 8000 per generated dataset** (registered 4000, implemented 1200). Reason: section 1; it is the
   smallest of the three sizes checked at which both gates have margin.
2. **Replicates.** 500 per run scenario for the four primary run scenarios (s ∈ {0.60, 1.00} ×
   {G0Q0, G1Q1}, each analyzed with U observed and hidden) and for C0 and C1; 250 for the four
   selective positive-control run scenarios and the four s = 1.70 run scenarios. The gate "all planned
   replicates completed in every primary scenario" refers to these counts. Reason: cost (section 4);
   the primary interval still resolves the 0.20 threshold except within ±0.022 of it (section 3).
3. **The primary Monte Carlo interval** keeps its registered form,
   p_primary ± 1.96 √{Σ_s p_s(1 − p_s)/R}/4, with R = 500.
4. **Timing pilot as a validity stop.** The registered pilot (10 replicates in each of four cases)
   runs at n = 8000 with the amended seeds' pilot stream, together with 10 replicates of C0 and of C1.
   If any primary scenario in it has fewer than 10 of 10 complete triplets, C0 has 4 or more of 10
   replicates with D = 1, or C1 has fewer than 5 of 10, the main run does not start and a further
   amendment is required. These are validity and calibration quantities, not the primary endpoint.
5. **Bootstrap validation** of the nuisance-adjusted IPTW SE keeps its four anchors and 400 resamples
   for the first 25 replicate identifiers.

## 3. The gates can pass

- **Truth manifest and independent check.** Already verified (`results/truth-manifest.csv`, amendment
  of 2026-08-01); the truths are properties of the mechanism, not of n.
- **Implementation audit.** The ltmle interface passed its contract test (BLOCKED.md): on C0 at
  n = 4000, RD −0.013 with SE 0.022 against a true 0, well inside its interval.
- **Complete triplets ≥ 0.95 in every primary scenario.** IPTW output valid in 20 of 20 datasets in each
  of the four primary scenarios at n = 8000 (80 of 80 pooled; Wilson lower bound 0.954). g-formula and
  ltmle returned valid output in every analysis profiled and in all six smoke analyses. The pilot stop
  in change 4 catches a shortfall before the main run.
- **C0: upper bound of Pr(D = 1) below 0.20.** Scaling the measured standard deviation of the IPTW
  minus g-formula difference by √(4000/8000) gives 0.0127 at n = 8000, so Pr(|IPTW − g-formula| > 0.03)
  ≈ 2Φ(−2.36) = 0.018. If ltmle's spread raises Pr(D = 1) to 0.10, the Wilson upper bound at R = 500 is
  0.129; the gate fails only if Pr(D = 1) exceeds about 0.17, ten times the IPTW and g-formula
  component.
- **C1: lower bound of Pr(D = 1) above 0.20.** C1 doubles the omitted transition and event interactions
  so that the pooled g-formula is misspecified while IPTW is not. Its separation is a difference in
  asymptotic bias, which does not shrink with n; had that difference been below 0.03, a larger n would
  have driven Pr(D = 1) in C1 toward zero. Measured on 8 C1 datasets at n = 8000: |IPTW − g-formula|
  had median 0.040 (range 0.014 to 0.095) and exceeded 0.03 in 6 of 8, so Pr(D = 1) is at least about
  0.75 before ltmle is counted. At R = 500 the gate needs about 0.24; the Wilson lower bound at 0.75 is
  about 0.71. The pilot stop in change 4 still requires at least 5 of 10 C1 pilot replicates with
  D = 1.
- **Both branches reachable.** With R = 500 in each of four primary scenarios the worst-case Monte Carlo
  SE of p_primary is 0.25/√500 = 0.0112, a half-width of 0.022. p_primary near 0.10 gives an upper bound
  near 0.12 (not real); near 0.30 a lower bound near 0.28 (real); results within 0.022 of 0.20 are
  uninformative.
- **Scenario-specific secondary proportions** (coverage, the hidden-U joint event H) have worst-case
  half-widths of 0.044 at 500 and 0.062 at 250; they are descriptive, as registered, and conditional
  diagnostic rates keep their minimum denominator of 400, which the 250-replicate scenarios cannot
  reach and will report as imprecise.

## 4. Cost

Per-analysis CPU at n = 8000 is taken as twice the n = 4000 measurement, 31 s (the g-formula recursion
and ltmle's per-time regressions both scale at most linearly in n; the n = 1200 to 4000 step grew by
only 1.7 times). A factorial replicate is two analyses, 62 s; a control replicate one, 31 s.

| Component | Replicates | CPU-s each | CPU-hours |
|---|---:|---:|---:|
| Primary run scenarios (4) | 2000 | 62 | 34.4 |
| C0 and C1 | 1000 | 31 | 8.6 |
| Positive controls and s = 1.70 (8) | 2000 | 62 | 34.4 |
| Bootstrap: 4 anchors × 25 × 400 IPTW point refits | 40,000 | 1.0 | 11.1 |
| Pilot (40 replicates plus 10 each of C0 and C1) and ltmle audit | | | about 1 |
| **Total** | | | **about 90** |

If the pilot shows per-analysis CPU above 40 s, the positive-control and s = 1.70 scenarios drop to 150
replicates before the main run, keeping the total under 100.

## 5. What the amended study no longer answers

- **Disagreement at n = 4000.** The answer is for n = 8000. Sampling spread falls with n, so the
  probability that three implementations differ by more than 0.03 on the same data is lower at 8000
  than it would be at 4000; a "no material dependence" result is more reachable here than in the
  registered design, and a "material dependence" result is correspondingly stronger evidence.
- **Precision.** The uninformative zone around 0.20 doubles from ±0.011 to ±0.022.
- **Positive controls and severe overlap** run at 250 replicates; their scenario-specific proportions
  have half-widths up to 0.062, and conditional diagnostic rates there fall below the registered
  denominator of 400.
- Nothing else in the registered scope is dropped: all 26 analysis scenarios, all four named methods,
  the hidden-U joint event and the bootstrap check remain.

The checks behind sections 1 and 3 (scratch scripts `c0_gate.R`, `c1_gate.R`, `validity.R` and
`profile.R`) used about 15 CPU-minutes and wrote nothing under `results/`; `smoke.rds` and `smoke.log`
were only read.
