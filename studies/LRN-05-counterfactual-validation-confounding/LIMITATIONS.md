# Known implementation limitations of the run

Stated here rather than left for a reviewer to discover, because each is visible
in the result files and none is a finding about the methods being compared.

## The run uses the protocol's minimum replicate count, not its planned one

The protocol asks the precision pilot to set a scenario-specific replicate count
and permits up to 10,000 per scenario, and its decision rule declares a result
uninformative when the required count exceeds that 10,000. This run fixes every
scenario at 2,000, which is the registered minimum, through `N_REP_BUDGET_CAP`,
and reports cells needing more under a reason of its own, `budget-precision-shortfall`,
which is not in the registered decision rule.

The reason is resources rather than judgment. The pilot's requirements are mostly
2,000, but the calibration intercept needs 78,000 to 176,000 replicates in several
scenarios, so honoring the plan would run those scenarios at the 10,000 cap. At
roughly an hour a scenario for 2,000 replicates, that is on the order of eighty
hours for one study. The deviation is declared here and in the reason string
attached to every affected row rather than presented as the protocol's rule.

What it costs is specific and worth separating from genuine estimator bias,
because the two look identical in a table of uninformative rows. The positive
control gate compares `|bias| + 1.96 * bias_mcse` against the negligible limit,
and `bias_mcse` shrinks with replicates while `bias` does not. For the never-treat
oracle calibration intercept the bias is 0.0326 against a limit of 0.05, so the
gate quantity converges to 0.0326 and the cell would pass at 10,000 replicates and
fails at 2,000 only through Monte Carlo error. For the same intercept under the
miscalibrated score the bias is 0.0505, already past the limit on its own, and no
number of replicates rescues it. The first is a budget artifact; the second is the
estimator.

## The fitted reduced-history method does not estimate under stressed support

`fitted_reduced` returns estimates on about 61 percent of replicates in the
twelve adequate-support scenarios and on none of them in the twelve stressed-support
scenarios. The adequate-support figure is the method's real behavior: it fails
there at `invalid-treatment-model-coefficient`, which is separation in a spline
treatment model carrying interactions, and that is a registered failure mode.

The stressed-support figure is not. `estimate_known_method` subsets the influence
matrix to its finite columns before forming a covariance:

```r
finite <- apply(comp$influence, 2L, function(z) all(is.finite(z)))
v <- crossprod(comp$influence[, finite, drop = FALSE]) / length(dat$y)^2
```

`estimate_fitted_method` does not. It stacks every column:

```r
stack <- cbind(nuisance$influence, total_if[, unique_metric, drop = FALSE])
```

Under stressed support a population decile is often empty, an empty bin yields an
NA influence column by design, and the NA propagates through `crossprod` to the
eigenvalues, so the singularity test sees a non-finite value and the replicate is
recorded as `singular-stacked-covariance`. The two functions disagree about a case
they both meet.

It was left unfixed deliberately. Nothing published depends on it: `classify_scalar`
reads `full_history` and `exact_complete` only, `oracle_gate` reads `full_history`,
and the calibration-curve decision reads the same two, so `fitted_reduced` enters no
classification. The protocol says the same thing in its own words, that failure
confined to the fitted reduced-history method is treatment-model approximation or
estimation failure and does not determine the omission-of-U classification. At 61
percent it is below the 95 percent the protocol requires before any method can carry
a classification, so repairing the stressed-support case would not move a verdict.
Against that, the repair invalidates the run and costs about forty hours.

If a results review judges the method's behavior under stressed support to be part
of what the study must report, the fix is to mirror the finite-column subset from
`estimate_known_method` and rerun.

## Calibration bins under stressed support are missing by construction, not at random

In the stressed-support scenarios the per-bin success rate for the always-treat
strategy runs from about 20 percent in the lowest decile to about 99 percent in the
highest, while the never-treat strategy is near 99 percent throughout. That gradient
is the positivity mechanism the support factor exists to create, and the bins below
95 percent are declared uninformative by the registered rule rather than summarized
over the replicates that happened to succeed. Reading a bin risk conditional on the
bin being non-empty would condition on the outcome of the mechanism under study.
