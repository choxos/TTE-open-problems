# GMT-04 is blocked on its ltmle interface

Three defects fixed, one structural problem left that is a rewrite rather than
a fix. Nothing has been run and nothing is published.

## Fixed: provenance by download

`ensure_ltmle_vendor` fetched the ltmle source archive and reference manual from
CRAN. CRAN moves superseded versions to Archive and the plain contrib URL
returns 404, so the study could not start on a machine that already had the
correct version installed. It also made the provenance of a run depend on what
CRAN was serving that day.

This repository already vendors a version-pinned ltmle at
`documentation/refs/packages/cran/ltmle`, which is the tree the technical
auditor reads and the one `calibration.json` pins. The check now hashes those
sources. CRAN writes the version as `1.3-0` and R reports `1.3.0`, so the
comparison is on the parsed version rather than the string.

## Fixed: Qform unnamed, then the wrong length

ltmle requires every element of `Qform` to be named after the L or Y node it
models. The spec builder stripped the names with `unname()`, so ltmle rejected
the call outright.

With names attached it then rejected the length. The builder produced one
formula per visit, six of them, where the data carries eleven L and Y nodes
(`S1 L1 S2 L2 S3 L3 S4 L4 S5 L5 S6`). `Qform` is now derived from the nodes
present in the data, in data order, with each formula built from the last
covariate and treatment preceding its node.

## Blocked: the outcome coding contradicts ltmle's survival contract

ltmle requires a survival Ynode to be an event indicator that stays at 1 once it
reaches 1. This study codes `S` the other way round, as an indicator of being
alive, and `est_ltmle` depends on that: it reads ltmle's estimate as a survival
probability and converts with `risk <- 1 - survival`.

So the fix is not local. Flipping `S` to an event indicator satisfies ltmle and
changes what every downstream consumer of `S` means, including the risk
extraction and its influence-function terms. Keeping the survival coding and
declaring the outcome non-survival changes what ltmle estimates.

Either way the study's central estimator interface has to be rewritten and
re-verified against a known answer, which is a design and implementation
question rather than a defect to patch. Patching it far enough to run and
publishing whatever comes out is the failure this program exists to avoid: the
result would arrive with a number attached.

## Also noted

The contract test asserts `length(Qform) == N_VISITS`, which was the wrong
length in the first place and is now wrong for a second reason. It has to be
rewritten alongside the interface.
