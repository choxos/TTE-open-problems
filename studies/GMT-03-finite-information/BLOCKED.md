# GMT-03 is blocked: the mechanism cannot reach the compatibility levels the design requires

The implementation stops before generating anything, with

```
Error in calibrate_overlap(outdir) :
  Cumulative compatibility calibration missed a target by more than 0.01
```

That is the code refusing to proceed, and it is right to refuse.

## What the design asks for

`KAPPA_TARGETS` sets four cumulative-compatibility levels, 0.12, 0.08, 0.04 and
0.02, and `calibrate_overlap` searches `KAPPA_GRID = seq(0, 2.25, by = 0.025)`
for a value of the tuning parameter achieving each within 0.01. Those four levels
are the study's main factor: they are how it varies the severity of the
positivity problem it exists to measure.

## What the mechanism actually produces

Sweeping the whole grid, the achieved minimum compatibility runs from 0.1714 at
kappa = 0 down to 0.1338 at kappa = 2.25, and it is flat from about kappa = 1.4
onward, changing in the fourth decimal place thereafter. The lowest value the
mechanism can produce is 0.134. The easiest target is 0.12.

The gap is not a tolerance problem and widening the grid cannot fix it, because
the curve has already asymptoted well above the target range. The other
parameters of the data-generating mechanism would have to change to make these
compatibility levels reachable at all.

## Why the tolerance was not relaxed

Relaxing to 0.05, or taking the nearest grid point regardless of distance, makes
the code run. It would run all four levels of the study's principal factor at a
compatibility of roughly 0.134, which is to say with the factor not varying. The
study would complete, produce performance measures with Monte Carlo standard
errors, and report a comparison across four conditions that were the same
condition. That is the exact failure this catalog exists to document, and it
would arrive with a number attached.

## What this needs

A design change, not a code fix: either the mechanism is reparameterized so
those compatibility levels are attainable, or the targets are moved to a range
the mechanism can produce and the protocol says why. Both are decisions about
the protocol and belong in a revision pass rather than in an implementation.

Everything else in the study is in place. The truth enumeration and the run
drivers are written and resumable, and nothing has been run.
