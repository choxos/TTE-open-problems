# SEQ-01 ran to completion and estimated nothing

The run finished all 12 scenarios and produced 510,000 rows. Every one of them
is `estimation-error` or, after the first fix below, a recorded failure. Zero
finite estimates. The analysis then reported `uninformative` on all four of its
conclusions, which is the correct reading of the data it was given and is why
this was caught at all: the decision rule declared an uninformative branch
before the run, and the branch fired.

A study that completes, writes performance measures with Monte Carlo standard
errors, and reports four conclusions, while having estimated nothing, is the
most dangerous artifact this program can produce. It is worth stating plainly
that the thing which caught it was a decision rule written in advance with a
reachable negative branch, which is exactly what the peer review insisted on
across the whole program.

## Defect 1, fixed

`nat` is a `data.table`, and

```r
nat$Xd <- I(cbind(1, nat$q, nat$Sex, nat$R, nat$C, nat$L))
```

assigns a six-column matrix into one column. `data.table` routes that through
`set()`, which flattens it: 173,916 values assigned to 28,986 rows. Every
replicate died there. The design matrices now travel in the returned list, which
is where their only consumer reads them from.

## Defect 2, open

With that fixed the replicate runs, and all 85 returned rows are still
non-finite: 70 `insufficient-model-rows` and 15 `life-table-inference-error`.

The first is not the weight model. `natural_initiation_rows` returns 29,265 rows
with all six design columns finite, ids spanning 1 to 2,000 against `hist$n` of
2,000, so `safe_logit_fit` sees 29,265 usable rows against 6 columns and its
guard `sum(use) <= ncol(X)` cannot fire there. The failure is in a later call
with a degenerate design, and locating it needs the kind of tracing that is a
debugging session rather than a fix.

## What this needs

Someone to work through `fit_all_estimators` call by call and find which design
matrix is degenerate and why. The mechanism, the drivers, the truth enumeration
and the analysis are all in place and the run is cheap: 12 scenarios at about 68
seconds each.

## What it does not need

Loosening the `safe_logit_fit` guard. The guard is the only reason this study
announced its own failure instead of reporting numbers.
