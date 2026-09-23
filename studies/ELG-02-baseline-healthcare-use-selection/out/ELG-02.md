# Selection on prior healthcare use: bias, target shift, and a
screen-and-respond policy
Ahmad Sofi-Mahmudi
2026-09-23

# Abstract

**Background.** Restricting an emulated trial to people with prior
healthcare use conditions on a variable that treatment propensity and
outcome risk may both cause. Catalog entry ELG-02 states that such
criteria are used without checking whether they are colliders. We
measured the bias this restriction produces under known graphs, how much
of the restricted-versus-broad contrast is a change of target, and
whether screening an external sample for a collider signal improves
estimation.

**Methods.** Eighteen generated cells crossed three eligibility
topologies (noncollider, concordant collider, discordant collider),
three edge strengths and two retention probabilities, with 2000
replicates each. Augmented inverse probability weighted estimators of
the restricted 60-month risk difference were compared with a policy that
screened a 4000-person audit sample and chose an estimator from the
result, in a view where the collider parents were measured and one where
they were not.

**Results.** The minimal estimator’s absolute bias reached 0.036, with
coverage down to 0.728. Five of the twelve collider cells had a lower
bound of at least 0.010, spanning both orientations, both retention
levels and two edge strengths: materially consequential by the
registered rule, though the two-strength condition rests on one cell.
With the parents measured the policy reduced bias in 7 of 12 collider
cells, but adjusting for every measured variable without screening did
as well, and pooling the audit sample into the analysis did better in
every cell. With the parents unmeasured the screen never warned and the
policy did nothing.

**Conclusions.** Selection on healthcare use can bias an emulation
materially when the criterion is a collider. A screen adds nothing that
adjusting for the measured variables does not already give, and it
cannot see a collider whose parents are not recorded.

# Introduction

An emulated trial restricted to people with prior healthcare use, such
as a recent visit or an earlier prescription, conditions on a variable
that treatment propensity and outcome risk may both cause. When they do,
the restriction opens a path between them that the analysis model does
not block ([1](#ref-hernan2004selection)). Catalog entry ELG-02 states
that eligibility criteria built from healthcare use are applied without
checking whether they are colliders. Restriction also changes the
population the effect refers to, so a difference between restricted and
unrestricted estimates mixes selection bias with a legitimate change of
target ([2](#ref-hernan2016bigdata)). Reporting guidance asks that
eligibility criteria and their emulation be stated
([3](#ref-cashin2025target)); it does not say how to assess them.

This study answers the part of ELG-02 that simulation can answer. Given
a known graph, how much bias does restriction on healthcare use produce,
how much of the restricted-versus-broad contrast is target shift, and
does a prespecified policy of screening an external sample for collider
signals and responding to the result estimate the restricted effect
better than analyses that do not screen? It does not determine whether
any real eligibility criterion is a collider.

# Methods

The study follows the ADEMP structure ([4](#ref-morris2019simulation)).
The protocol, decision rule and code were registered before any
replicate was drawn.

## Data-generating mechanism

Each replicate draws an audit sample and an analysis sample of 4000
people each from one superpopulation. Baseline variables are B ~
Bernoulli(0.5) and X, P, D and eight noise variables N<sub>1</sub> to
N<sub>8</sub>, each standard normal, all mutually independent. P is a
prescribing tendency that affects treatment only; D is preclinical
severity that affects outcome only. Healthcare use H, treatment A and
the 60-month outcome Y are probit:

- H: α<sub>H</sub> + 0.30B + 0.20X + λ<sub>P</sub>P + λ<sub>D</sub>D,
  with α<sub>H</sub> solved for the retention probability;
- A: −0.05 + 0.35B − 0.25X + 0.55P;
- Y under treatment a: −1.50 + 0.45B + 0.35X + 0.65D + a(−0.35 + 0.25B).

Eighteen cells cross three topologies, three edge strengths s (0.10,
0.45, 1.10) and two retention probabilities Pr(H = 1) (0.30, 0.70). The
noncollider topology sets λ<sub>P</sub> = 0 and λ<sub>D</sub> = s, so H
depends on outcome risk alone and restriction changes the population
without opening a path. The concordant and discordant collider
topologies set λ<sub>P</sub> = s with λ<sub>D</sub> = s or −s, so H
depends on both parents and restriction to H = 1 induces a negative or
positive association between P and D. There are twelve collider cells
and six noncollider cells.

## Estimands and truth

The primary estimand is the restricted 60-month risk difference
RD<sub>H</sub> = E(Y<sup>1</sup> − Y<sup>0</sup> \| H = 1). The broad
estimand RD<sub>all</sub> is the same contrast without restriction, and
the target shift is RD<sub>H</sub> − RD<sub>all</sub>, a difference
between two valid estimands rather than a bias. Both were computed by
product Gauss-Hermite quadrature over X, P and D with exact summation
over B, accepted when 30-, 40- and 50-node results agreed within
10<sup>−7</sup>. The target shift was decomposed across B, X and D by an
order-averaged chain-rule decomposition; the D component is an oracle
diagnostic because D is unmeasured in the reduced view.

## Methods compared

All causal estimators are augmented inverse probability weighted (AIPW)
with probit nuisance models and a stacked M-estimation sandwich
variance. Intervals are untruncated 95% Wald intervals.

- **Minimal**: restrict to H = 1; treatment model A ~ B + X; outcome
  model Y ~ A + B + X + A:B.
- **Role-based**: adds P to the treatment model and D to the outcome
  model, chosen from known covariate roles without screening.
  Unavailable in the reduced view.
- **All-measured**: every measured baseline variable in both models.
- **Oracle**: B, X, P and D in both models, including in the reduced
  view.
- **Broad**: criterion removed; estimates RD<sub>all</sub> over all 4000
  people and is compared only with RD<sub>all</sub>.
- **Pooled**: the all-measured specification on audit and analysis
  samples together (8000 people), to price the audit sample.
- **Policy**: a screen on the audit sample, locked before the analysis
  sample is examined. Probit models for H, A and Y on B, X and every
  other measured variable as unlabeled candidates, Holm correction at
  familywise α = 0.01 across candidates and models; the result is
  “collider candidate” if one candidate is associated with H and A and a
  different one with H and Y. On a collider-candidate result the policy
  reports the all-measured estimate, on “no signal” the minimal
  estimate, and on an unresolved audit the all-measured estimate with a
  flag.

Two analyst-information views are applied to every cell. In the full
view P and D are measured. In the reduced view they are not, and the
screen sees only the noise variables, so a hidden collider can pass
unnoticed.

## Decision rule

Collider bias is materially consequential if the lower 95% Monte Carlo
bound for absolute bias of the minimal estimator is at least 0.010 in at
least 4 of the 12 collider cells, the qualifying cells spanning both
collider orientations, both retention levels and at least two edge
strengths; it is negligible if the upper bound is below 0.005 in all 12.
The policy is conditionally beneficial in a view if the lower 95% bound
for the paired reduction in absolute bias relative to the minimal
estimator, \|Bias<sub>minimal</sub>\| − \|Bias<sub>policy</sub>\|, is at
least 0.005 in at least 4 spanning collider cells with no material harm
in noncollider cells, and not beneficial if the upper bound is below
0.005 in all 12. The run is technically uninformative if a required
estimator fails in more than 10% of replicates in any cell, fewer than
1900 paired outputs remain, the audit screen fails in more than 10% of
replicates in any cell-view, quadrature fails its check, the broad
estimator fails to recover RD<sub>all</sub>, or more than one
noncollider cell has an upper absolute-bias bound for the minimal
estimator of at least 0.005. Monte Carlo bounds come from 2000 bootstrap
resamples of replicates. Each cell has 2000 replicates, giving a Monte
Carlo standard error of 0.0049 for coverage near 0.95.

# Results

All 36,000 replicate pairs produced a valid estimate from every
available method, no audit was unresolved, quadrature met its tolerance
in every cell, and the broad estimator recovered RD<sub>all</sub>. The
run is technically informative.

## The screen

With the parents measured, the screen warned in 0.754 to 0.777 of
replicates at the near-null edge strength and in every replicate at
strengths 0.45 and 1.10. In noncollider cells it warned in at most
0.0005. With the parents unmeasured it never warned, so every collider
replicate in the reduced view was a silent error: the screen reported no
signal and the policy used the biased minimal estimator.

## Collider bias

Restriction biased the minimal estimator in the direction of the induced
association: negatively in concordant cells and positively in discordant
ones (<a href="#tbl-bias" class="quarto-xref">Table 1</a>). Absolute
bias reached 0.036 in the concordant cell at strength 1.10 and retention
0.30, where coverage fell to 0.728. At the near-null strength it was at
most 0.0011. In noncollider cells, where restriction changes the
population without opening a path, the upper bound for absolute bias
never exceeded 0.0024.

Five collider cells had a lower bound of at least 0.010: all four at
strength 1.10 and the concordant cell at 0.45 with retention 0.30. They
span both orientations, both retention levels and two edge strengths, so
the registered classification is materially consequential. The
two-strength requirement is met by that one cell, whose lower bound is
0.0112; without it the classification would be mixed.

<div id="tbl-bias">

Table 1: Minimal restricted estimator in the collider cells, full view:
absolute bias with its 95% Monte Carlo interval, coverage, and the
policy’s paired reduction in absolute bias with its lower bound.

<div class="cell-output-display">

| topology | strength | retention | bias | interval | coverage | reduction | lower |
|:---|---:|---:|:---|:---|:---|:---|:---|
| concordant | 0.10 | 0.3 | 0.0008 | 0.0001 to 0.0018 | 0.954 | 0.0002 | -0.0004 |
| concordant | 0.10 | 0.7 | 0.0011 | 0.0004 to 0.0017 | 0.949 | 0.0002 | -0.0001 |
| concordant | 0.45 | 0.3 | 0.0123 | 0.0112 to 0.0133 | 0.925 | 0.0117 | 0.0096 |
| concordant | 0.45 | 0.7 | 0.0065 | 0.0058 to 0.0071 | 0.923 | 0.0063 | 0.0051 |
| concordant | 1.10 | 0.3 | 0.0358 | 0.0346 to 0.0370 | 0.728 | 0.0358 | 0.0334 |
| concordant | 1.10 | 0.7 | 0.0180 | 0.0173 to 0.0187 | 0.768 | 0.0177 | 0.0169 |
| discordant | 0.10 | 0.3 | 0.0008 | 0.0001 to 0.0017 | 0.958 | 0.0007 | -0.0009 |
| discordant | 0.10 | 0.7 | 0.0006 | 0.0001 to 0.0011 | 0.945 | 0.0003 | -0.0003 |
| discordant | 0.45 | 0.3 | 0.0081 | 0.0073 to 0.0088 | 0.923 | 0.0077 | 0.0062 |
| discordant | 0.45 | 0.7 | 0.0059 | 0.0054 to 0.0064 | 0.937 | 0.0059 | 0.0048 |
| discordant | 1.10 | 0.3 | 0.0173 | 0.0166 to 0.0180 | 0.788 | 0.0169 | 0.0162 |
| discordant | 1.10 | 0.7 | 0.0152 | 0.0147 to 0.0157 | 0.732 | 0.0152 | 0.0142 |

</div>

</div>

## The policy

With the parents measured, the policy’s reduction in absolute bias had a
lower bound of at least 0.005 in 7 of 12 collider cells, spanning both
orientations, both retention levels and two strengths, with no harm in
the noncollider cells: conditionally beneficial by the registered rule.
The one cell at strength 0.45 or above that missed was the discordant
cell with retention 0.70, at 0.0048. With the parents unmeasured the
screen never warned, the policy reported the minimal estimate in every
replicate, and its benefit was exactly zero: not beneficial.

The benefit is not the screen’s. In the full-view collider cells the
policy and the all-measured estimator, which uses the same variables
without screening, differed in mean squared error by at most 2.4e-05,
and the policy was never the worse of the two. Pooling the audit and
analysis samples and adjusting for every measured variable gave a lower
mean squared error than the policy in 36 of 36 cell-views, each by more
than three Monte Carlo standard errors. The registered design calls the
policy data-efficient only if it beats that comparator, and it does not.

## Target shift

Restriction also changes the estimand. The target shift RD<sub>H</sub> −
RD<sub>all</sub> ran from -0.019 to 0.013, carried almost entirely by D:
its contribution reached 0.019 against at most 0.0021 for B and 0.0025
for X. Noncollider cells shift as much as collider cells, because H
selects on outcome risk in both. A difference between restricted and
unrestricted estimates is therefore not evidence of collider bias.

# Discussion

Restricting on a healthcare-use variable that is a collider biases a
correctly specified minimal analysis by up to 0.036 on the
risk-difference scale in this benchmark, enough to move coverage from
0.95 to 0.73. It is at most 0.001 when the edges into the criterion are
weak, 0.006 to 0.012 when they are moderate and 0.015 to 0.036 when they
are strong, and it takes the sign of the association the selection
induces. Restriction that selects only on outcome risk moves the
estimand by a similar amount without biasing it, so the movement between
a restricted and a broad estimate cannot distinguish the two.

The screen detects the collider when both parents are recorded, with
almost no false alarms, but that is exactly the situation in which it is
unnecessary: adjusting for every measured baseline variable removes the
bias without it, and spending the audit sample on the analysis instead
is better still. When the parents are not recorded the screen has
nothing to find. A measured-variable screen of this kind therefore does
not address the part of ELG-02 that matters, a criterion whose other
causes are unrecorded.

## What this study does not establish

The study is a mechanism benchmark under correctly specified probit
models and a four-node graph that is known to the simulation. It does
not discover or certify collider status for an unknown eligibility
criterion, identify an unnamed latent cause, or estimate how often real
criteria are colliders. The screen’s operating characteristics do not
transfer to indirect paths, association-mimicking noncolliders,
nonlinear mechanisms, noisy proxies, partial measurement or audit
samples of other sizes. The two views are extremes: every parent
measured perfectly, or neither measured at all. The policy’s performance
assumes access to an independent audit sample of 4000 people.

## Review

The design was reviewed and revised before any code was written. A first
complete run was analyzed and discarded: its audit screen returned
“unresolved” in every replicate, because it read standard errors from a
coefficient table that `glm.fit` does not produce, so every policy
estimate was the all-measured estimate and the policy branch it reported
meant nothing. The screen was fixed, and a check that counts screen
failures toward the registered failure ceiling was added, before the
rerun reported here. The results have not yet been reviewed.

# Data and code availability

Code, protocol and result files:
<https://github.com/choxos/TTE-open-problems/tree/main/studies/ELG-02-baseline-healthcare-use-selection>.

# References

<div id="refs" class="references csl-bib-body">

<div id="ref-hernan2004selection" class="csl-entry">

<span class="csl-left-margin">1.
</span><span class="csl-right-inline">Miguel A. Hernán, Sonia
Hernández-Díaz, James M. Robins. A structural approach to selection
bias. Epidemiology. 2004;15(5):615–25.
doi:[10.1097/01.ede.0000135174.63482.43](https://doi.org/10.1097/01.ede.0000135174.63482.43)</span>

</div>

<div id="ref-hernan2016bigdata" class="csl-entry">

<span class="csl-left-margin">2.
</span><span class="csl-right-inline">Miguel A. Hernán, James M. Robins.
Using big data to emulate a target trial when a randomized trial is not
available. American Journal of Epidemiology. 2016;183(8):758–64.
doi:[10.1093/aje/kwv254](https://doi.org/10.1093/aje/kwv254)</span>

</div>

<div id="ref-cashin2025target" class="csl-entry">

<span class="csl-left-margin">3.
</span><span class="csl-right-inline">Aidan G. Cashin, Harrison J.
Hansford, Miguel A. Hernán, Sonja A. Swanson, Hopin Lee, Matthew D.
Jones, others. Transparent reporting of observational studies emulating
a target trial: The TARGET statement. JAMA. 2025;334(12):1084.
doi:[10.1001/jama.2025.13350](https://doi.org/10.1001/jama.2025.13350)</span>

</div>

<div id="ref-morris2019simulation" class="csl-entry">

<span class="csl-left-margin">4.
</span><span class="csl-right-inline">Tim P. Morris, Ian R. White,
Michael J. Crowther. Using simulation studies to evaluate statistical
methods. Statistics in Medicine. 2019;38(11):2074–102.
doi:[10.1002/sim.8086](https://doi.org/10.1002/sim.8086)</span>

</div>

</div>
