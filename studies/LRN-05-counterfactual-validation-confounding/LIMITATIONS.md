# Known implementation limitations of the run

Stated here rather than left for a reviewer to discover, because both are visible
in the result files and neither is a finding about the methods being compared.

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
