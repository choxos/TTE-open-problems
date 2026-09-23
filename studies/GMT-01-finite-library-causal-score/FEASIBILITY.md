# GMT-01 feasibility check

Run before the registered simulation, from a seed (777001) disjoint from its
streams: 10 replicates in each of the eight gamma_Z = 0 scenarios, n = 4000.

## Registered criterion at stake

The primary result is uninformative "if any primary one-step method has a
convergence Wilson lower bound below 0.80 in a gamma_Z = 0 scenario".

## Result

Proportion of replicates with a finite estimate (all failures were `low-ess`,
effective sample size below 10 in one regime):

| scenario | separation | shape | predictive | balance | combined |
|---:|---|---|---:|---:|---:|
| 1 | good | all-main | 1.0 | 1.0 | 1.0 |
| 2 | poor | all-main | 0.6 | 0.6 | 0.6 |
| 7 | good | nonlinear treatment | 1.0 | 1.0 | 1.0 |
| 8 | poor | nonlinear treatment | 0.9 | 1.0 | 1.0 |
| 13 | good | nonlinear censoring | 0.9 | 1.0 | 0.9 |
| 14 | poor | nonlinear censoring | 0.8 | 0.8 | 1.0 |
| 19 | good | nonlinear outcome | 1.0 | 1.0 | 1.0 |
| 20 | poor | nonlinear outcome | 0.8 | 0.9 | 0.9 |

The population check in `results/dgm-check.csv` gives the cause. Scaled to
n = 4000, the never-treat regime's true effective sample size is 1.4 in
scenario 2 and 1.7 in scenario 14, against the registered floor of 10. The
poor-separation level (s = 1.25) leaves that regime almost unsupported.

## Implication

At the implemented 500 replicates, a true convergence rate of 0.6 gives a
Wilson lower bound near 0.56, and 0.8 gives about 0.76. Unless every
poor-separation scenario converges on at least about 84 percent of replicates,
the registered primary branch is uninformative. Scenario 2 (6 of 10; 95% Wilson
upper limit 0.83) makes that the expected outcome. The secondary
treatment-only-predictor classification is not affected by this criterion.

The run is therefore deferred behind studies whose registered decision can
still resolve. Reaching a primary answer needs a registered amendment to the
separation level or the sample size, which is a protocol decision.
