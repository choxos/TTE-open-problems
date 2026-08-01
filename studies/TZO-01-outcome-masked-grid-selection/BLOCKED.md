# TZO-01 is blocked on this machine, not on its science

Two real defects were found and fixed, and a third obstacle is environmental.

## Fixed: an off-by-one that stopped it generating anything

`marker_boundary` is boundary-indexed and carries `N_WEEKS + 1` columns;
`p_start` is interval-indexed and carries `N_WEEKS`. The panel builder read both
at `b + 1`, so on the last interval it indexed one column past the end of
`p_start` and the study died before producing a single replicate.

## Fixed: two more invented base-R arguments

`tabulate(d$period, nbins = K, weights = weight)`. `base::tabulate` has no
`weights` argument. Same defect as SEQ-01, now replaced by the grouped sum it
was meant to be and swept across every generated file rather than fixed one at
a time.

## Blocked: one uninterruptible step is longer than the execution window

Truth is adaptive. It draws quarter-million batches until the Monte Carlo
standard error on every decisive column is under 0.0005, to a ceiling of four
million, and the sparse-visit higher-pressure cells reach that ceiling. 39 of
the 48 cells are enumerated and cached.

Within-cell batch checkpointing was added for exactly this, and it does not
help, because the bottleneck is upstream of it. `fit_population_models` runs
once per process scenario at `TRUTH_FIT_N = 250000` before any batch is drawn,
and for process scenario 4 it does not finish in nine minutes. It is a single
call, so there is nothing inside it to resume from.

Long processes are killed on this machine, so a step that cannot finish inside
that window and cannot checkpoint can never complete however many times it is
resumed. That is a property of where this is being run, not of the study: an
overnight run on a machine that will hold a process would finish it.

## What this needs

Either a machine that will hold the process, or `fit_population_models` made
resumable by caching its fitted models per process scenario, which is
deterministic given the scenario and would need only the first successful fit.

The batch checkpointing added here is kept either way: it is correct, and the
batches are deterministic given the scenario and batch index, so a cached batch
is the batch the run would have drawn.
