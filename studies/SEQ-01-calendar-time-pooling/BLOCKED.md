# SEQ-01 ran to completion and estimated nothing

The run finished all 12 scenarios and produced 510,000 rows. Every one of them
is `estimation-error` or, after the first two fixes below, a recorded failure.
Zero finite estimates. The analysis then reported `uninformative` on all four of
its conclusions, which is the correct reading of the data it was given and is
why this was caught at all: the decision rule declared an uninformative branch
before the run, and the branch fired.

A study that completes, writes performance measures with Monte Carlo standard
errors, and reports four conclusions, while having estimated nothing, is the
most dangerous artifact this program can produce. It is worth stating plainly
that the thing which caught it was a decision rule written in advance with a
reachable negative branch, which is exactly what the peer review insisted on
across the whole program.

Two code defects have been fixed. What remains is not a code defect.

## Defect 1, fixed

`nat` is a `data.table`, and

```r
nat$Xd <- I(cbind(1, nat$q, nat$Sex, nat$R, nat$C, nat$L))
```

assigns a six-column matrix into one column. `data.table` routes that through
`set()`, which flattens it: 173,916 values assigned to 28,986 rows. Every
replicate died there. The design matrices now travel in the returned list, which
is where their only consumer reads them from.

## Defect 2, fixed

With that fixed the replicate ran and every returned row was still non-finite:
70 `insufficient-model-rows` and 15 `life-table-inference-error`. The name was
misleading. Instrumenting `safe_logit_fit` showed it was handed all 288 cells
with positive weight and zero usable rows, which is not a shortage of rows; it
is a response that is missing everywhere.

`event_time` is `NA` for everyone who never fails, and `01-dgm.R` built the
outcome column as

```r
Y = as.integer(hist$event_time[ids[keep]] == t + 1L),
```

`NA == t + 1L` is `NA`, not `FALSE`. So `Y` was missing on every never-event
person-period, which is most of them; the weighted cell sums of the outcome were
`NA` in all 288 cells; `swy / sw` was `NA` everywhere; and every outcome model
received zero usable rows. The life-table benchmark carried the identical
comparison at `02-estimators.R:644` and failed the same way. Every other
comparison against `event_time` in the study already guarded for `NA`. Both
sites now call one named helper, `fails_at`, so the guard has a name and a
reason attached to it.

After the fix, 29 of 85 rows estimate.

## What remains is the design, not the code

The three models that carry the treatment by follow-up by start-time surface
fail in every replicate, and they fail on a criterion the protocol itself
registered: `any absolute required coefficient above 20`. Measured over eight
replicates of scenario 1:

| method | parameters | replicates that fit |
|---|---:|---:|
| `package_like` | 8 | 8 of 8 |
| `equal_common` | 72 | 8 of 8 |
| `standalone_12` | life table | 8 of 8 |
| `start_saturated` | life table | 2 of 8 |
| `equal_flexible` | 120 | **0 of 8** |
| `calendar_omitted` | 72 | **0 of 8** |
| `calendar_quadratic` | 96 | **0 of 8** |

The three that fail are exactly the three containing `G` by `factor(j)` by
`ns(q_k, df = 4)`. At `G = 1` that surface is a free five-parameter spline in
start time within each of twelve follow-up months: sixty parameters, estimated
from 144 treated cells. In a 2000-person cohort with low monthly initiation the
treated arm carries a median of 109 events, and 77 of those 144 cells are empty.
The fit is separated, the coefficient runs to five figures, and the registered
guard rejects it. The guard is behaving correctly.

Cohort size is the binding constraint, and the shortfall is about one order of
magnitude:

| cohort | treated events | empty treated cells | flexible model fits | median max abs coefficient |
|---:|---:|---:|---:|---:|
| 2,000 | 109 | 77 of 144 | 0 of 5 | 11,710 |
| 8,000 | 424 | 25 of 144 | 4 of 5 | 7.18 |
| 20,000 | 1,054 | 5 of 144 | 3 of 3 | 3.98 |
| 50,000 | 2,637 | 1 of 144 | 3 of 3 | 3.85 |

## What this needs

A protocol revision, registered and reviewed before it runs, not a patch. The
registered design fixes the cohort at 2000 people and lists that as a declared
limitation, while its own primary estimator needs roughly ten times that. The
decision rule already anticipates the consequence: a conclusion is uninformative
when the flexible estimator is not adequate where attribution to the
common-effect restriction is claimed. Under the registered design that branch
fires in every replicate, so running it as written produces a study that is
correct and empty.

The design review did not catch this. Nothing in it compares the parameter count
of the flexible surface against the number of treated events the data-generating
mechanism produces, and that comparison is the whole of the problem. A
feasibility check that fits the most demanding model once and reports its
maximum coefficient would have caught it in seconds.

## What it does not need

Loosening the coefficient guard, or dropping the three-way term to make the fit
succeed. The guard is registered in four separate methods in the protocol and is
the only reason this study announced its own failure instead of reporting
numbers. The three-way term is the estimator the study exists to evaluate.
