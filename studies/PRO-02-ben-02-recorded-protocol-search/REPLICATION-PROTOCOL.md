# PRO-02 replication protocol

Registered by the commit that adds this file, before any replicate is drawn.

The first run is recorded as inconclusive (`INCONCLUSIVE.md`): its gate required
all 360 fixed-candidate coverage estimates to lie in [0.93, 0.97] with no
allowance for Monte Carlo error or multiplicity, and one estimate was 0.9285
(0.26 MCSE below the window). That classification stands. The rule below is not
applied to the first run's data.

## Unchanged

Mechanism, 36 cells, candidate libraries, selectors, estimators, 2,000
replicates per cell, truth and its MCSE limit (0.00005), estimands D_all and
D_nonboundary, the simultaneous 95% Monte Carlo rectangle, the 0.02 threshold,
and the three branches of the decision rule. Truth, lambda and the design
diagnostics are deterministic and are reused.

## Changed

1. **Seed.** `MASTER_SEED = 20260922`. Output goes to `results/replication/`.
2. **Calibration gate.** For each of M = 360 fixed-candidate evaluations with
   R = 2,000 replicates, compute two-sided Wilson intervals at confidence
   1 − 0.05/M (z = 3.810). An evaluation fails if its coverage interval lies
   wholly outside [0.93, 0.97], or if the lower limit of its failure-probability
   interval exceeds 0.05. Truth MCSE and completeness requirements are
   unchanged. The gate passes if no evaluation fails. Its familywise false
   failure rate under exact calibration is at most 0.05.

## Sensitivity of the gate

A candidate fails when its estimated coverage is below about 0.908. Detection
probability is 0.89 at true coverage 0.90, 0.69 at 0.905 and 0.39 at 0.91.
Miscalibration smaller than about two percentage points can pass; the report
states this beside the verdict.

## Decision rule

- **Materially real:** gate passes and both simultaneous lower bounds exceed 0.02.
- **Not materially real:** gate passes and both simultaneous upper bounds are below
  0.02. Restricted to the declared selectors, score settings, protocol components
  and libraries of at most 16 candidates.
- **Mixed or uninformative:** otherwise.
