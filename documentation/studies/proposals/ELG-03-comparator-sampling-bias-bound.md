# ELG-03: a pre-sampling bound on the bias of comparator sampling schemes, and what it cannot be built from

**Catalog problem.** No procedure bounds the bias a comparator sampling scheme introduces before the study is run. Verdict `overstated`; triage: analytic, answerable in part, feasibility 3, scope applies.

**Residual claim this design tests.** The audit kept the mechanism: random-order sampling without replacement conditions on comparators' future survival, and chronological sampling without replacement exhausts sparse strata (Heide-Jørgensen 2018). Codex removed the universal form: bias is undefined until a target is named, and no nontrivial bound follows from the sampling ratio, the pool-to-index ratio and the marginal comparator hazard alone, because settings that share those three summaries can differ in direction and size. The triage asks for a bound for defined schemes under a specified index-time, depletion and survival model. This design derives that bound, proves the counterexample that fixes which inputs it needs, and checks both by simulating the schemes literally.

## Questions

**Q1.** Under a stated pool-depletion model, what is the expected comparator risk under sampling with replacement (WR), without replacement in random order (WOR-R) and without replacement in chronological order (WOR-C), relative to the risk of a member of the eligible pool at the index date?

**Q2.** Is there a single pre-sampling quantity that orders the three schemes' failures, and does it give a valid, informative bound for WOR-R bias and a prediction of WOR-C exhaustion?

**Q3.** Which inputs beyond the sampling ratio, the pool ratio and the marginal hazard does any such bound need?

## What this leaves unanswered

Pools with new entrants during accrual; matching on time-varying characteristics; how comparator-risk bias propagates into an adjusted effect estimate; the prevalence of high-consumption strata in published studies; and whether journals should require the scheme to be reported. The bound is model-based and is not distribution-free, which codex showed cannot exist.

## Setting and assumptions

One matching stratum; the analysis is repeated per stratum. Calendar accrual window `[0, tau]`. The index cohort has `n` patients whose index dates are independent draws from a density `g` on `[0, tau]` with distribution function `G`. The comparator pool has `N` members eligible at time 0; member `j` leaves the pool (death, emigration, or acquiring the index condition) at `D_j`, independently, with calendar survivor function `S(u) = P(D > u)`, and whether a member is sampled does not affect `D_j`. Each index patient at date `t` receives `m` comparators drawn uniformly from members still in the pool at `t` (and, for the WOR schemes, not yet used). A comparator matched at `t` contributes `Y = 1` if the outcome occurs in `(t, t + h]`.

**Target.** `r(t) = P(Y = 1 | D > t)`, the `h`-year risk of a member of the eligible pool at the index date. WR draws from exactly this distribution, so it is the reference; codex's objection that "bias" needs a named target is met by this definition.

**Consumption index.** With sampling fraction `f = m n / N`, define `Lambda(a, b) = f * integral from a to b of g(u)/S(u) du`: the expected number of draws landing on one surviving pool member over `(a, b]`, in the large-pool limit.

## Claims to be proved or refuted

**C1 (WR).** The expected comparator risk equals `r(t)` for every `t`. Reuse inflates the variance of the comparator risk by at most `1 + Lambda(0, tau)` relative to independent draws.

**C2 (WOR-C).** Matched comparators have expected risk `r(t)`, since whether a member has been used depends only on the past. In the large-pool limit the unused pool at `u` is `N S(u) (1-Lambda(0, u))`, so no index patient is unmatched when `Lambda(0, tau) < 1`; otherwise every patient dated after `u*`, where `Lambda(0, u*) = 1`, is unmatched, a fraction `1-G(u*)`. Dropping them changes the index population, not the comparator risk.

**C3 (WOR-R).** Processing index patients in random order, a member with exit time `D > t` is still unused when a patient dated `t` draws with probability approximately `pi(D) = exp(-Lambda(0, min(D, tau)) / 2)` (each other patient precedes with probability one half), which decreases in `D`. Hence the expected comparator risk is `E[Y pi(D) | D > t] / E[pi(D) | D > t]`. When the outcome is pool exit (death as outcome and exit), this gives

`r(t) <= r_R(t) <= r(t) / [ r(t) + (1-r(t)) rho(t) ]`, with `rho(t) = exp(-Lambda(t, tau) / 2)`,

so the bias is nonnegative, is zero when `Lambda(t, tau) = 0`, and is approximately at most `r(1-r) Lambda(t, tau) / 2` when that is small. Early-dated patients are the ones affected. For an outcome other than exit, the bias is `Cov(Y, pi(D) | D > t) / E[pi(D) | D > t]`: zero when the outcome is independent of exit time, whatever the sampling fraction. The derivation must add pool depletion by earlier draws, which makes the tilt stronger; the preliminary check below shows the simple form stops being a bound once `Lambda(0, tau)` exceeds about 1.

**C4 (delimiting counterexample).** Two strata with the same `N`, `n`, `m` and `S`, hence the same sampling ratio, pool ratio and hazard, one with every index date equal and one with dates spread over `[0, tau]`, have zero and positive WOR-R bias respectively, because `Lambda(t, tau) = 0` in the first. So no function of those three summaries bounds the bias nontrivially, and the extra inputs any bound needs are `g` and `S` over the accrual window. Both are available before sampling: index dates come from the index cohort and `S` from the pool's own exit records or period life tables.

C1 to C3 place all three failure modes on one per-stratum quantity: WOR-C exhausts when `Lambda(0, tau)` reaches 1, WOR-R bias grows with `Lambda(t, tau)`, and WR pays in variance up to `1 + Lambda(0, tau)`. This is consistent with the reported pattern that the schemes nearly coincide at one comparator per patient and separate at five in an elderly cohort, since `Lambda` scales with `m` and with `1/S`.

## Preliminary numerical check

Scratch run of the three algorithms (`wor.R` in the design agent's scratch directory): one stratum of `N` = 2000 pool members, `m` = 5, index dates uniform on `[0, 5]` years or all at 2.5 years, constant exit hazard 0.0725 per year, outcome death within `h` = 1 year, so `r` = 0.0699 at every `t`; 200 replicates per cell. The Monte Carlo SE of each scheme's mean risk is about 0.0013 at `f` = 0.1 and 0.0004 at `f` = 1.

| f | index dates | Lambda(0, tau) | WR | WOR-R | WOR-C | fluid WOR-R | simple bound | WOR-C unmatched, simulated / predicted |
|---|---|---:|---:|---:|---:|---:|---:|---|
| 0.1 | uniform | 0.12 | 0.0686 | 0.0725 | 0.0687 | 0.0715 | 0.0720 | 0 / 0 |
| 0.5 | uniform | 0.60 | 0.0693 | 0.0805 | 0.0700 | 0.0784 | 0.0813 | 0 / 0 |
| 1.0 | uniform | 1.21 | 0.0702 | 0.1501 | 0.0699 | 0.0882 | 0.0948 | 0.148 / 0.146 |
| 1.5 | uniform | 1.81 | 0.0696 | 0.1908 | 0.0701 | 0.0992 | 0.1109 | 0.403 / 0.402 |
| 0.1 | single | 0.12 | 0.0697 | 0.0684 | 0.0689 | 0.0699 | 0.0699 | 0 / 0 |
| 0.5 | single | 0.60 | 0.0691 | 0.0688 | 0.0694 | 0.0699 | 0.0699 | 0 / 0 |
| 1.0 | single | 1.20 | 0.0695 | 0.0697 | 0.0702 | 0.0699 | 0.0699 | 0.167 / 0.166 |
| 1.5 | single | 1.80 | 0.0701 | 0.0699 | 0.0702 | 0.0699 | 0.0699 | 0.444 / 0.444 |

At an exit hazard of 0.01 per year the simulated WOR-C unmatched fractions were 0.025 and 0.345 (uniform dates) and 0.026 and 0.350 (single date) at `f` = 1.0 and 1.5, against predictions of 0.024, 0.344, 0.025 and 0.350.

Reading: WR and WOR-C match the target in every cell, and the exhaustion prediction of C2 is within 0.003 in all eight exhausting cells. WOR-R bias is zero at every `f` when all index dates coincide, which is C4. With spread dates the simple form of C3 holds while `Lambda(0, tau)` is at most 0.6 (bias 0.0106 against a bound of 0.0114), and fails by a factor of about three once `Lambda(0, tau)` exceeds 1 (bias 0.080 against 0.025), where depletion by earlier draws dominates. The depletion-corrected form is therefore necessary, and whether it gives a valid and informative bound near exhaustion is the open part this study decides.

## Numerical verification

The verification simulates the three algorithms literally, not the fluid limit. Factors: pool size `N` in {200, 1000, 5000}; `f` in {0.05, 0.2, 0.5, 1.0, 1.5}; `m` in {1, 5}; index dates as a point mass, uniform, or front-loaded (Beta(1, 3) on `[0, tau]`); exit hazard constant at 0.005, 0.03 or 0.12 per year, and a Gompertz version with aging inside the window; `tau` of 5 and 10 years; `h` = 1 year; outcomes: death, and a nonfatal outcome sharing a gamma frailty with exit at three strengths (none, moderate, strong). A fractional design of about 200 cells is used; each cell runs until the Monte Carlo SE of the WOR-R bias is below 0.0005 or one tenth of the bound, at most 2000 replicates. The target `r(t)` is computed exactly from `S`.

Checks: (V1) WR mean risk equals `r` within two Monte Carlo SEs in every cell; (V2) WOR-R bias lies in `[0, bound + 2 SE]` in every cell meeting the assumptions; (V3) tightness, the ratio of simulated bias to bound; (V4) the simulated WOR-C unmatched fraction against `1-G(u*)`; (V5) zero WOR-R bias within Monte Carlo error in point-mass cells and in cells with an outcome independent of exit.

## What would show the problem real or not real

- **Answered within the model (entry overstated, as the audit found).** V1, V2 and V5 hold; the bound is informative, meaning it is at most twice the simulated bias in every cell with simulated bias of at least 0.005, and at most 0.002 in every cell with `Lambda(0, tau)` at most 0.05; and V4 is within 0.02 absolute for `N` of at least 1000. A pre-sampling procedure then exists for the stated model, needing `m`, `n`, `N`, `g` and `S`.
- **Problem stands.** V2 fails beyond Monte Carlo error in cells meeting the assumptions with `N` of at least 1000, so the fluid bound is invalid where it matters; or it is vacuous, above five times the simulated bias in at least half the cells with bias of at least 0.005; or at fixed `r` the bias is not monotone in `Lambda(t, tau)`, so no pre-sampling summary of this form orders the schemes.
- **Uninformative.** More than 10% of cells have Monte Carlo intervals straddling a threshold at 2000 replicates.

Both substantive branches are reachable: the fluid argument ignores depletion feedback and discreteness, which can break the bound at large `f` or small `N`, while a depletion-corrected bound can become loose. C4 holds in either branch and settles the codex point on its own.

## Cost

About 85 person-hours: derivation and proofs 40, simulation code 15, runs and checks 10, writing 20. Compute under 10 CPU-hours: each replicate is at most a few million comparisons (for example `N` = 5000 and `n` = 7500), about 0.1 CPU-second, and 200 cells by up to 2000 replicates by three schemes is well under that. No data access is needed.

## Threats to validity

- The fluid limit may be poor in small strata; V2 and V4 are stratified by `N` for this reason.
- Exit independent of being sampled holds by construction in simulation and in registries.
- Pools that gain members during accrual (people reaching an eligible age) are excluded from the claims; with entrants `S` is replaced by the pool-size curve and the argument needs rework.
- "Random order" has implementation variants (for example retrying unmatched patients); the proof covers the single-pass version and the simulation reports the retry variant separately.
- The target `r(t)` is the eligible-pool risk; an analyst targeting a different comparator population needs a different reference, and the bound does not transfer.

## Citations

- Heide-Jørgensen U, Adelborg K, Kahlert J, Sørensen HT, Pedersen L. Sampling strategies for selecting general population comparison cohorts. *Clinical Epidemiology*. 2018;10:1325-1337. doi:10.2147/CLEP.S164456
- Suissa S. Immortal time bias in pharmacoepidemiology. *American Journal of Epidemiology*. 2008;167(4):492-499. doi:10.1093/aje/kwm324
- Lubin JH, Gail MH. Biased selection of controls for case-control analyses of cohort studies. *Biometrics*. 1984;40(1):63 (first page as indexed). doi:10.2307/2530744. The analogous result for control sampling from a cohort: excluding controls who later become cases conditions on the future.
- Morris TP, White IR, Crowther MJ. Using simulation studies to evaluate statistical methods. *Statistics in Medicine*. 2019;38(11):2074-2102. doi:10.1002/sim.8086
