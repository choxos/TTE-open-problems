# PRO-02 ran cleanly and cannot be classified

The study is complete. 36 scenarios, 1,728,000 rows, zero replicate errors,
truth enumerated to a maximum Monte Carlo standard error of 0.0000166. Two
rounds of results review. It does not go on the site as an answer to PRO-02,
and the reason is worth more than the answer would have been.

## What the numbers say

Naive intervals after a recorded, treatment-effect-blind search over protocol
components were essentially nominal. Global coverage 94.966 percent, nonboundary
coverage 94.998 percent. The registered deficits were 0.00034 and 0.000016 with
simultaneous upper bounds of about 0.0019, against a prespecified threshold of
0.02: roughly 29 and 24 Monte Carlo standard errors below it.

## Why that is not the published answer

The protocol requires a calibration gate to pass before either substantive
branch can be used: every fixed candidate in every cell must have coverage
between 0.93 and 0.97. One of 360 evaluations came in at 0.9285.

That miss is 0.0015 below the gate, which is 0.26 of its own Monte Carlo
standard error of 0.0058. It is not evidence of undercoverage. It is what
happens when a hard two-sided window is applied 360 times with no allowance for
multiplicity: some evaluations land outside it by chance, and the gate is
close to certain to fail.

## Why the gate was not relaxed

Relaxing a prespecified gate after seeing which side of it the result landed on
is the single move that would make every threshold in this program worthless.
The reviewer said so in both rounds and it is right. The registered
classification stays uninformative.

A decisive classification needs a separately prespecified replication whose
calibration rule accounts for Monte Carlo uncertainty and for 360 simultaneous
comparisons. That is a new registration, not an edit to this one.

## One real defect, found and fixed

`perf_becoverage(est, lower, upper)` was called as `(err, se, 0)`, so the
interval had a standard error for a lower bound and zero for an upper bound.
Bias-eliminated coverage was therefore identically zero with a Monte Carlo error
of zero, printed beside an ordinary coverage of 0.946. After the fix it runs
0.9335 to 0.9995 with a median of 0.951.

The same wrong call appears in at least three other generated studies. The
shared measure now refuses an interval whose lower bound exceeds its upper bound
on most rows, so the next one fails loudly instead of exporting a zero.

## Scope, from the review

Whatever is eventually concluded covers deterministic recorded searches over
nested age thresholds and outcome horizons, libraries of 4 or 16 highly
correlated candidates with effective library sizes near 1.35 to 1.85, and clean
correctly specified inverse-probability weighting. Undocumented human protocol
development and the other protocol components are untouched.
