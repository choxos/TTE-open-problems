# TZO-01 cannot answer as registered

Earlier defects are fixed: an off-by-one in the panel builder, invented base-R
arguments, the end of follow-up treated as an initiation decision, and a
diverged population model counted as converged. What remains is below.
`AMENDMENT-DESIGN.md` proposes the changes that would let it answer.

## The truth precision gate cannot pass

The registered truth draws batches until every decisive Monte Carlo standard
error is at most 0.0005, to a cap of four million people. The check matched
`approx-panel` while the columns are named `approx|panel|...`, so it ignored the
approximation-error columns and stopped at 500,000 people reporting precision
met. Those columns have standard errors up to 0.0058 (one-week grid). Standard
errors fall as one over the square root of n, so the four-million cap reaches
about 0.002. The analysis marks a cell uninformative when its truth misses the
target, so every cell would be uninformative. The check is fixed
(commit bf779f1); the committed `results/truth.csv` still carries the
incorrect `precision_met` values and is superseded by any recomputation.

## The one-week comparator fails in the higher-pressure scenarios

The initiation model carries one intercept per interval. In process scenarios
3 and 4, 97 to 100% of 4000-person cohorts have a week with no initiations
(weeks 62 to 104, with 18 to 190 people at risk); at the two-week grid, 40% and
7%. The intercept diverges and the Hessian condition number exceeds the
registered 1e12, so the fit fails by the registered rule, and a cell whose
required comparator fails in more than 5% of replicates is uninformative.

## The selector can only choose one week

The selector compares each grid's cross-validated log loss with the one-week
grid's, in the 1000-person design sample. The one-week model fails there in
every scenario because late weeks have no starts, so the reference is missing,
no coarser grid qualifies, and the rule falls back to one week in every
replicate.

## Support in the early arm is marginal

At 4000 people the one-week early-arm effective sample size is 56 to 84 in
scenarios 1 and 2 (five replicates each). The cell-level median per arm, pooled
over grids, is 124 to 153 and passes the registered 100; the one-week grid on its
own does not.

A run of scenarios 1 and 2 was started under the registered design and stopped
when the truth defect was found.
