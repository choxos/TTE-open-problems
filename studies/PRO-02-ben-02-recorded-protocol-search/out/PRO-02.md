# Naive intervals after a recorded, effect-blind search over emulated
protocols
Ahmad Sofi-Mahmudi
2026-09-23

# Abstract

**Background.** Emulation protocols are often revised after
investigators see the data, and the reported interval ignores that
search. Catalog entry PRO-02 states that this invalidates coverage. We
measured how much coverage a naive interval loses when the search is
recorded and the selector never sees the treatment effect.

**Methods.** Thirty-six generated-data cells crossed cohort size,
expected event count, library size (4 or 16 candidate protocols over age
thresholds and outcome horizons) and treatment effect, with 2,000
replicates each. Effect-blind selectors chose a protocol by arm sizes
and pooled events, by prognostic associations, or by covariate balance;
an effect-seeking selector was the positive control. Estimands were the
global coverage deficits D_all and D_nonboundary against a registered
materiality threshold of 0.02. This is a registered replication: the
first run failed its calibration gate by chance.

**Results.** All 360 fixed-candidate evaluations passed the calibration
gate. D_all was 0.0015 (simultaneous 95% interval -0.0001 to 0.0030) and
D_nonboundary 0.0023 (0.0004 to 0.0042). The effective library size was
at most 1.85. Noncoverage rose to 0.083 when candidate estimates spanned
more than two standard errors. The effect-seeking control lowered
coverage to 0.894 in the worst cell.

**Conclusions.** In this design a recorded, effect-blind search costs
naive intervals almost nothing on average, because the candidates barely
differ. When they do differ, the selected interval undercovers.

# Introduction

Target trial emulations specify eligibility, treatment strategies,
follow-up and outcomes before analysis, and reporting guidance asks that
the specification and its revisions be recorded
([1](#ref-cashin2025target)). In practice thresholds and horizons are
revised after inspecting the data. Even a selector that never sees the
effect estimate can use outcome frequency or covariate-outcome
associations, and those are correlated with the estimate. The interval
reported for the chosen protocol conditions on a choice that was itself
data dependent.

PRO-02 treats this as a coverage problem. This study measures its size
for the part that can be simulated: a finite, recorded search whose
selector is blind to the treatment effect. Undocumented, sequential
development by an analyst who has seen results is outside its scope.

# Methods

The study follows the ADEMP structure ([2](#ref-morris2019simulation)).
The design was reviewed and revised before any code was written.

## Data-generating mechanism

Age is 55 + 10Z with Z a standard normal truncated at ±2; S and C are
binary covariates and B continuous. Baseline initiation depends on Z, S,
C and B, and time to event follows a constant-hazard model with the same
covariates. The treatment effect is null, a hazard ratio of 0.75, or a
hazard ratio exp(−0.288 + 0.25Z) that changes with age, so candidate
protocols with different age thresholds target different effects. The
baseline hazard was solved, before the study and from event counts only,
so that the anchor protocol (age at least 55, 36 months) has 35, 70 or
140 expected pooled events. There is no loss to follow-up. The
four-candidate library crosses age thresholds of 50 and 55 with horizons
of 36 and 60 months; the sixteen-candidate library crosses thresholds of
45 to 60 with horizons of 24 to 60 months.

## Estimands and selectors

For each candidate the estimand is the risk difference at its horizon
among people meeting its age threshold. Each protocol’s effect was
estimated by Hajek inverse probability weighting with a correctly
specified propensity model and a Wald interval. Selectors: a workability
rule (the first candidate with at least 100 per arm and 70 pooled
events); two prognostic-association rules, whose fixed score tracks the
outcome more or less closely; an outcome-blinded rule that picks the
eligibility threshold with the best covariate balance; and, as a
positive control, the candidate with the most beneficial standardized
estimate. Two remedies were evaluated: Bonferroni over the declared
library and a fifty-fifty split between a design half that selects and
an analysis half that estimates.

## Decision rule

A calibration gate comes first: every declared candidate in every cell
must have fixed-candidate coverage compatible with \[0.93, 0.97\],
judged by a Wilson interval at familywise confidence 1 − 0.05/360, and
failure probability compatible with at most 0.05. If it passes, the
problem is materially real if both simultaneous 95% lower limits of
D_all and D_nonboundary exceed 0.02, not materially real if both upper
limits are below 0.02, and mixed otherwise.

## Why this is a replication

The first run used the same design with a gate that required all 360
coverage estimates to lie inside \[0.93, 0.97\]. One came in at 0.9285,
0.26 Monte Carlo standard errors outside, and the registered
classification was held at uninformative. A gate applied without
allowance for Monte Carlo error to 360 estimates fails almost surely
even when every candidate is calibrated. The replication protocol,
committed before any of its replicates were drawn, changed only the seed
and the gate. The first run’s deficits, 0.0003 and 0.0000, were also far
below the threshold.

# Results

## Calibration and the primary comparison

All 360 fixed-candidate evaluations passed the gate; fixed-candidate
coverage ran from 0.9295 to 0.9610 and no candidate failed to estimate.
D_all was 0.0015 (-0.0001 to 0.0030) and D_nonboundary 0.0023 (0.0004 to
0.0042). Both upper limits lie more than 0.015 below the threshold. The
registered branch is that the recorded-search problem is not materially
real in this design. The nonboundary deficit is detectably above zero
but equals about a fifth of a percentage point.

## Why the average deficit is small

Nested age thresholds and horizons produce highly correlated candidates.
The effective library size (the squared sum of the eigenvalues of the
candidates’ correlation matrix divided by the sum of their squares) was
1.36 to 1.40 with 4 candidates and 1.75 to 1.85 with 16. Choosing among
them is close to not choosing.

## The design can detect a loss

The effect-seeking selector lowered naive coverage to 0.930 on average
and to 0.894 to 0.928 across the 16-candidate cells, against 0.947 to
0.949 for the effect-blind selectors
(<a href="#tbl-coverage" class="quarto-xref">Table 1</a>).

<div id="tbl-coverage">

Table 1: Mean naive coverage of the selected protocol’s interval, by
selector and treatment effect.

<div class="cell-output-display">

| selector        | heterogeneous | homogeneous |  null |
|:----------------|--------------:|------------:|------:|
| effect_seeking  |         0.934 |       0.936 | 0.922 |
| outcome_blinded |         0.950 |       0.948 | 0.950 |
| prognostic_high |         0.951 |       0.948 | 0.949 |
| prognostic_low  |         0.948 |       0.947 | 0.946 |
| workability     |         0.950 |       0.948 | 0.949 |

</div>

</div>

## The average hides a conditional failure

Naive noncoverage depended on how far the candidates’ estimates spread
(<a href="#tbl-multiverse" class="quarto-xref">Table 2</a>). When the
range across candidates was below one median standard error, noncoverage
was 0.022 to 0.025; between one and two, 0.041 to 0.044; above two,
0.082 to 0.083. The standardized range predicted noncoverage with an AUC
of 0.66 to 0.68.

<div id="tbl-multiverse">

Table 2: Naive noncoverage by the standardized range of the candidate
estimates (range divided by the median candidate standard error).

<div class="cell-output-display">

| selector        | below 1 | 1 to 2 | above 2 |
|:----------------|--------:|-------:|--------:|
| prognostic_high |   0.022 |  0.041 |   0.083 |
| prognostic_low  |   0.025 |  0.044 |   0.083 |
| workability     |   0.023 |  0.041 |   0.082 |

</div>

</div>

## Remedies

Bonferroni intervals for the selected protocol covered 0.9915, above
nominal. Sample splitting covered 0.9468, with intervals a median 1.42
times as wide as the full-sample interval for the same candidate, close
to the square root of two.

# Discussion

A recorded search whose selector cannot see the effect does little
damage to average coverage when the candidates are variations on one
protocol. The damage concentrates in the replicates where the candidates
disagree, which is also where the choice matters. Reporting every
candidate’s estimate, as a multiverse display, therefore carries
information about the reliability of the selected interval that the
interval itself does not.

Bonferroni and sample splitting both restore coverage. Bonferroni
overshoots; splitting pays in width about what halving the data
predicts.

## What this study does not establish

The result covers deterministic recorded searches over nested age
thresholds and horizons, libraries of 4 or 16 highly correlated
candidates, effect-blind selectors and correctly specified weights. It
does not cover sequential protocol development by an analyst who has
seen results, other protocol components such as grace periods or
treatment definitions, libraries of weakly correlated protocols, or
misspecified weights. The replication’s gate controls false failure
across 360 comparisons and would pass a candidate miscalibrated by less
than about two percentage points.

## Review

The design was reviewed and revised before any code was written. The
first run was reviewed twice; the reviewer held its classification at
uninformative and recommended a separately registered replication, which
is this study. The replication’s results have not yet been reviewed.

# Data and code availability

Code, both protocols and result files:
<https://github.com/choxos/TTE-open-problems/tree/main/studies/PRO-02-ben-02-recorded-protocol-search>.

# References

<div id="refs" class="references csl-bib-body">

<div id="ref-cashin2025target" class="csl-entry">

<span class="csl-left-margin">1.
</span><span class="csl-right-inline">Aidan G. Cashin, Harrison J.
Hansford, Miguel A. Hernán, Sonja A. Swanson, Hopin Lee, Matthew D.
Jones, others. Transparent reporting of observational studies emulating
a target trial: The TARGET statement. JAMA. 2025;334(12):1084.
doi:[10.1001/jama.2025.13350](https://doi.org/10.1001/jama.2025.13350)</span>

</div>

<div id="ref-morris2019simulation" class="csl-entry">

<span class="csl-left-margin">2.
</span><span class="csl-right-inline">Tim P. Morris, Ian R. White,
Michael J. Crowther. Using simulation studies to evaluate statistical
methods. Statistics in Medicine. 2019;38(11):2074–102.
doi:[10.1002/sim.8086](https://doi.org/10.1002/sim.8086)</span>

</div>

</div>
