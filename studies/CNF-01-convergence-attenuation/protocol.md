# Study 1. Does reporting comparator-arm initiation recover the attenuation it is supposed to explain?

Registered against catalog entry
[CNF-01](../../problems/CNF-01-convergence-of-treatment-in-the-comparator-arm-attenuates-th.qmd),
catalog verdict `overstated`, triage scope `core`, study type `simulation`,
answerable `yes`, feasibility 5.

This protocol is committed before the run. The commit that adds it is the timestamp.

## 1. Aims

CNF-01 states that the observational analogue of an intention-to-treat effect attenuates with
follow-up length because the comparator group does not stay untreated, and that the attenuation
is rarely reported as such, so a null result at a long horizon cannot be distinguished from an
ineffective treatment. Its proposed direction asks for two things: publish the cumulative
incidence of initiation in both arms, and quantify by simulation how much attenuation a given
convergence rate produces at each horizon.

The audit downgraded the entry to `overstated` on the ground that the phenomenon and its
remedies are known. What the audit did not settle, and what nobody has published, is whether the
diagnostic the entry proposes actually works. That is this study.

**A1.** Quantify the attenuation of the assignment-effect risk difference as a function of the
follow-up horizon and the comparator-arm initiation rate.

**A2.** Decide whether the reported diagnostic recovers it. Specifically: given the cumulative
incidence of comparator-arm initiation at the horizon, `C(h)`, how tightly is the attenuation
`A(h)` determined? If `A(h)` is a function of `C(h)`, the entry's fix is sufficient and this
study supplies the conversion table. If `A(h)` varies materially at fixed `C(h)`, the fix is
necessary and not sufficient, and the study names what else has to be reported.

A2 is the decisive aim. A1 alone would restate what the entry already says.

## 2. Data-generating mechanism

Discrete monthly time, horizon 120 months, `n = 4000` per replicate.

**Baseline.** One continuous confounder `L ~ N(0, 1)` and one binary `Z ~ Bern(0.4)`. Baseline
initiation `A0 ~ Bern(expit(-0.4 + 0.6 L + 0.4 Z))`, so assignment is confounded and baseline
adjustment is required for the contrast to mean anything, as the entry states.

**Comparator-arm initiation.** Individuals with `A0 = 0` may initiate in any later month with
monthly hazard

```
h_init(t) = expit(alpha0 + alpha_t * g(t) + alpha_L * L)
```

`alpha0` sets the overall rate. `g(t)` is the timing shape, standardized so that two shapes can
be tuned to the same cumulative incidence at 120 months while differing in when initiation
happens. `alpha_L` makes initiation depend on prognosis, so that the comparator patients who
initiate are or are not the ones at higher risk.

Individuals with `A0 = 1` remain treated. Discontinuation is out of scope for this study and is
declared a limitation in section 7: this study is about the comparator arm converging upward,
not about the treated arm converging downward.

**Outcome.** Monthly event hazard

```
h_Y(t) = expit(beta0 + beta_L * L + beta_Z * Z + beta_A * E(t))
```

where `E(t)` is treatment exposure at `t`. Two persistence regimes:

- **transient**: `E(t) = 1` only while currently treated, so a comparator patient who initiates
  at month `m` gets the benefit from `m` onward and none before
- **legacy**: `E(t)` rises to 1 over a 12-month ramp after initiation and stays at 1 thereafter
  even under later cessation, which is not simulated here, so in this study legacy differs from
  transient only through the ramp

`beta_A < 0` throughout: the treatment works. That is deliberate. The question is whether a
working treatment can be made to look null by convergence alone, so a null treatment would
answer nothing.

Administrative censoring at 120 months. No loss to follow-up, and that is a declared
simplification: informative censoring is MIS-01's problem and folding it in here would confound
the attenuation with a second mechanism.

## 3. Estimands

All on the risk-difference scale at horizon `h` in months, `h` in {12, 24, 36, 60, 84, 120}.

**ITT-analogue.** `RD_ITT(h) = P(Y(h) | assign A0 = 1) - P(Y(h) | assign A0 = 0)`, where later
initiation proceeds in both arms exactly as the mechanism dictates. This is the estimand an
emulation reports, and it is the one that attenuates.

**Sustained-strategy reference.** `RD_PP(h) = P(Y(h) | always treated) - P(Y(h) | never
treated)`. This is the contrast the comparator arm would have supported if it had stayed
untreated.

**Attenuation.** `A(h) = 1 - RD_ITT(h) / RD_PP(h)`, the fraction of the sustained-strategy
effect that convergence has removed at horizon `h`.

**Diagnostic.** `C(h) = P(comparator-arm patient has initiated by h)`, the quantity the entry
asks authors to publish.

Truth for `RD_ITT` and `RD_PP` is computed by direct enumeration of the DGM at `n = 2,000,000`
per scenario, once per scenario rather than per replicate, and stored. Truth is not estimated
from the replicates.

## 4. Methods

This is not primarily an estimator comparison. Two estimators of `RD_ITT(h)` are run, to
establish that the attenuation being measured is a property of the estimand and not of the
estimator:

1. **g-formula standardization** over `(L, Z)`, the conventional baseline-adjusted analogue
2. **IPTW** on the baseline propensity score with stabilized weights

Both should be approximately unbiased for `RD_ITT(h)`. If they are, attenuation is not an
estimation problem, which is itself worth publishing, because the entry's phrasing leaves room
for a reader to think it is.

The substantive method under test is the diagnostic itself:

3. **`C(h)` as a predictor of `A(h)`**, evaluated across the scenario grid rather than within a
   replicate

## 5. Design

Full factorial, 2 x 2 x 3 x 2 = 24 scenarios, 1000 replicates each.

| Factor | Levels |
|---|---|
| Convergence rate, tuned to `C(120)` | 0.20, 0.45, 0.70 |
| Timing shape at matched `C(120)` | early, late |
| Initiation depends on prognosis | `alpha_L = 0` (neutral), `alpha_L = 0.6` (high-risk initiate first) |
| Effect persistence | transient, legacy |

The **timing contrast at matched `C(120)`** is the experiment that decides A2. Two scenarios
report the same diagnostic value at the horizon and differ only in when the initiation happened.
If their attenuations differ materially, then publishing `C(h)` at the horizon is not enough and
the whole curve is required. This is why the shapes are tuned to match rather than left free.

Replicate count is set from the target Monte Carlo standard error rather than chosen round. With
a risk difference of roughly 0.06 and an empirical SE near 0.015 at `n = 4000`, 1000 replicates
give an MCSE on bias near 0.0005, which is an order of magnitude below the smallest attenuation
difference the study needs to resolve.

## 6. Performance measures

Every measure carries a Monte Carlo standard error, computed by
`studies/_shared/R/performance.R`.

| Target | Measures |
|---|---|
| Estimator correctness for `RD_ITT(h)` | bias, empirical SE, model SE, relative error in model SE, 95% coverage, convergence |
| Attenuation | `A(h)` with its MCSE, by scenario and horizon |
| Diagnostic adequacy | spread of `A(h)` across scenarios sharing a value of `C(h)`; the maximum difference in `A(h)` between the matched early and late timing pairs |

Failed replicates are results. Convergence is reported for every method in every scenario, and
performance is reported both over converged replicates and counting failures as non-coverage.

## 7. What would count as which answer

Declared in advance.

**The diagnostic is sufficient.** If, at every horizon, attenuation between matched early and
late scenarios differs by less than 0.05 on the attenuation scale, and `C(h)` explains
essentially all between-scenario variation in `A(h)`, then reporting `C(h)` lets a reader recover
the attenuation, the entry's proposed fix works as stated, and this study supplies the
conversion table.

**The diagnostic is necessary but not sufficient.** If matched pairs differ by 0.05 or more,
then two emulations reporting the same diagnostic can carry materially different attenuation,
and the recommendation has to become the full initiation curve plus the persistence assumption
rather than a single number.

**The premise fails.** If the g-formula and IPTW estimators are biased for `RD_ITT(h)`, the
attenuation measured here is contaminated by estimation error and the study reports that instead,
without claiming anything about the diagnostic.

## 8. Limitations declared before the run

- No discontinuation in the treated arm. Convergence is simulated in one direction only.
- No loss to follow-up and no competing events. Both are other entries' problems and folding
  them in would confound the mechanism under test.
- One outcome scale. The attenuation of a hazard ratio is a different question, because the
  hazard ratio is not collapsible and would mix the mechanism under test with a second one.
- The DGM is chosen by the same people who want a particular conclusion. The matched-timing
  contrast is the guard: it fixes the diagnostic and varies only the thing the diagnostic
  cannot see, so the decisive comparison is internal rather than against an assumed baseline.
