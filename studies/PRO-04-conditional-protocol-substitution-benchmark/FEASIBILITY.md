# PRO-04 feasibility

## The power rule, run correctly, selects N = 948,000

The protocol fixes N per replicate by a worst-case influence-function power
calculation before any replicate is drawn: at least 80% probability of
classifying a preserving mechanism (true |Delta| = 0.005) as preserving against
a 0.01 margin, and of detecting a changed one (|Delta| = 0.03), with the
intended-effect interval no wider than 0.04.

The first attempt never finished: a scalar `ifelse` put every state on the
first quadrature node's outcome probability (fixed in commit 3274a43). On the
correct population the largest inflated gap variance is 3.83. Classifying a
true |Delta| of 0.005 inside a 0.01 margin with 80% probability, after the
1.645-SE shrinkage of the margin, needs a gap standard error of at most 0.0020,
which gives N = 948,000 (`results/sample-size.csv`: preservation power 0.800, change power
1.000, interval width 0.009).

## Correction

The cost below is wrong. The 87 s is wall time on a machine at load average
200; a full replicate at N = 948,000 uses 4.8 to 7.1 CPU-seconds, so the
implemented design costs about 41 CPU-hours and the registered one about 103.
Cost does not block the study. `AMENDMENT-DESIGN.md` records what does: the
48-way coverage gate passes with probability 3.5e-9 at 1000 replicates, and
the primary branch is fixed at "mixed" by the mechanism distribution.

## Cost

One replicate at N = 948,000 takes 87 seconds and 565 MB on this machine,
which is shared and at load average about 200:

| replicates per stratum | strata | CPU hours |
|---:|---:|---:|
| 1,000 (implemented) | 24 | about 580 |
| 2,500 (registered) | 24 | about 1,450 |

## What this needs

More compute, or a registered amendment. The size of N is a property of the
registered power target, not a defect: distinguishing |Delta| = 0.005 from a
0.01 margin with 80% power needs a very small standard error. An amendment that
relaxes the power target or widens the margin changes what the diagnostic
evaluation can claim and has to be registered before any replicate is run.
