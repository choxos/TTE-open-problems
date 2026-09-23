# MER-01 cannot pass its own validity gate as registered

## The gate

The registered decision rule requires, in every key error cell, a median oracle
effective sample size above 200 in both arms, and calls the study uninformative
otherwise. The oracle applies the clone-censor Hajek estimator to the true
treatment and confounder histories with the true natural-treatment
probabilities, so it measures support in the generating law itself, before any
measurement error.

## What the registered law gives

The dynamic strategy g1 sets A(t) = L(t) at every month from 0 to 11; g0 never
treats. A clone contributes only if its whole 12-month history agrees with the
strategy. The registered natural-treatment law is strongly persistent
(coefficient 2.00 on A(t-1)), while L(t) changes state often, so a person
follows either strategy for 12 consecutive months only rarely.

Twenty generated cohorts of 4000 per latent law (`est_oracle`, estimand
`dynamic`):

| latent law | adherence g1 | adherence g0 | median ESS g1 | median ESS g0 | median oracle SE |
|---|---:|---:|---:|---:|---:|
| core | 0.0071 | 0.0118 | 6.4 | 10.6 | 0.158 |
| treatment stress | 0.0097 | 0.0116 | 6.4 | 17.2 | 0.158 |
| confounder stress | 0.0132 | 0.0140 | 11.4 | 9.0 | 0.144 |
| outcome stress | 0.0071 | 0.0118 | 6.4 | 10.6 | 0.153 |
| error-transition stress | 0.0071 | 0.0118 | 6.4 | 10.6 | 0.158 |

The true dynamic risk difference is -0.086 (core law); the oracle's standard
error is nearly twice that. Effective sample size scales with cohort size, so
a median of 200 needs roughly 125,000 people per replicate, thirty times the
registered 4000, with 50 or more imputations per replicate for the corrected
method. The gate fails at every replicate count, so running the registered
design can only return "uninformative".

The implemented treatment, confounder and outcome laws match the registered
design term by term; this is a property of the design, not of the code.

## Defects fixed on the way

The study had never run: its data-generating code did not parse, and scenario
construction stopped on a vector `&&`. After those fixes the pre-run check
found two more:

- `bern(x, p)` was `ifelse(x == 1L, p, 1 - p)`. The imputation filter calls it
  with a scalar latent state and a per-person probability vector, so it returned
  the first person's probability for everyone. The truth computation never
  calls it with a scalar state and ran under the ifelse guard, so the committed
  truth is unaffected.
- `measurement_counts` read eleven monthly transitions from the outcome's
  one-column error matrix and stopped on a subscript error.

## What unblocks it

A registered amendment, committed before any replicate is drawn, that gives
the strategies practical support. Options, each a scientific choice:

- a natural-treatment law that tracks L(t) closely enough for the dynamic
  strategy to be followed, with g0 still supported;
- a shorter strategy horizon;
- a grace period, so adherence is judged over windows rather than every month.

Raising the cohort size to about 125,000 keeps the design but is not feasible
with multiple imputation at this replicate count.
