# Unrecorded eligibility changes who is eligible more than it changes
the effect among them
Ahmad Sofi-Mahmudi
2026-09-24

# Abstract

**Background.** When the measurement that defines eligibility is missing
for some patients, an emulation cannot tell from its records who was
eligible. Catalog entry ELG-01 states that latent eligibility makes the
target population unidentified without validation data. We asked whether
that ambiguity changes the treatment effect materially, and how
estimators with and without internal validation perform.

**Methods.** Paired full-data laws with identical observed records but
different eligibility among people with unrecorded measurements (a shift
of log odds λ of 0, log 2 or log 4) were crossed with the share
unrecorded (0.20, 0.50), the expected validation sample (100, 400), a
homogeneous or heterogeneous treatment effect, and whether comorbidity,
the effect modifier, enters eligibility directly: 48 scenarios, 4000
replicates each, 4000 people per replicate. The registered structural
contrast Δ<sub>ID</sub> compares the true risk difference among the
eligible at λ = log 4 and λ = 0 in the pair most likely to show a
difference.

**Results.** Δ<sub>ID</sub> was -0.00066 (90% interval -0.000661 to
-0.000660), inside the registered equivalence band of ±0.005: not
materially different. The same shift moved the true prevalence of
eligibility from 0.705 to 0.787, which estimators assuming eligibility
is missing at random missed by up to 0.082. Every estimator’s risk
difference was unbiased within ±0.005 in every scenario.

**Conclusions.** In this design, unrecorded eligibility changes how many
people are eligible far more than the effect among them. Validation data
are needed to count the eligible; the effect estimate is robust unless
the hidden eligibility shifts the share of an effect modifier
substantially.

# Introduction

Eligibility criteria defined by a laboratory value or a clinical
assessment are often unrecorded for part of the cohort. Restricting to
recorded eligibles, or imputing eligibility under a missing-at-random
assumption, then targets a population that may differ from the truly
eligible one ([1](#ref-tompsett2023missing),[2](#ref-benz2025missing)).
Catalog entry ELG-01 states that without validation data the eligible
population is not identified. That is true by construction: two
data-generating laws can produce identical records and different
eligibility among the unrecorded. Whether the difference matters for the
effect estimate is a separate question, and it is the one this study
asks.

# Methods

The study follows the ADEMP structure ([3](#ref-morris2019simulation));
the protocol and decision rule were registered before any replicate was
drawn.

## Data-generating mechanism

Each replicate has 4000 people with baseline covariates age, sex,
specialist access H, comorbidity C and recorded treatment intent, and a
single baseline treatment decision. A clinical recording indicator R is
drawn with P(R = 0) calibrated to m (0.20 or 0.50). A latent laboratory
value G = 45 + 5T defines eligibility E = 1 when G is at least 45, where
T is logistic with linear predictor 0.85 − 0.65Z − κC + 0.25S + 0.50H +
λ(1 − R); κ is 0 or 1.10. Changing λ changes eligibility only among
people whose value is unrecorded, and leaves every observed variable
bitwise identical, so paired λ arms are observationally equivalent. The
60-month outcome has baseline risk depending on covariates and a
treatment effect of −0.06 for everyone (homogeneous) or −0.04 without
and −0.12 with comorbidity (heterogeneous). A Bernoulli validation
sample with known inclusion probability reveals G for some unrecorded
people.

## Estimands and methods

The primary estimand is the 60-month risk difference among the truly
eligible, RD<sub>E</sub>; the complete-case analysis is evaluated
against the risk difference among recorded eligibles, and the difference
between the two is reported as a target discrepancy. Truth was computed
from ten million simulated people per law. Methods without validation:
complete case; multiple imputation of G or of E under missing at random
(M = 20, with an M = 50 check); inverse probability of ascertainment
weighting; and a pattern-mixture sensitivity analysis at assumed λ\* of
0, log 2 and log 4. Methods with validation: known-design two-phase
weighting, validation-anchored fractional imputation and an augmented
two-phase estimator. An oracle with full eligibility is the benchmark.

## Decision rule

The structural result uses one prespecified pair: heterogeneous effect,
m = 0.50, κ = 1.10, λ = log 4 against λ = 0. It is material if the 95%
paired Monte Carlo interval for Δ<sub>ID</sub> lies wholly outside
±0.010, and not materially different if the 90% interval lies wholly
within ±0.005, provided the observed records and the no-validation
method outputs are identical across the pair. An estimator’s bias is
material if its 95% interval lies wholly outside ±0.010 and equivalent
if its 90% interval lies wholly within ±0.005.

# Results

## Structural contrast

The observed records and every no-validation method’s output were
identical across the pair. Δ<sub>ID</sub> was -0.00066, with Monte Carlo
standard error 4.4e-07 and a 90% interval of -0.000661 to -0.000660,
wholly inside ±0.005. The registered classification is not materially
different.

Latent eligibility did change the population. In the decisive pair, the
true prevalence of eligibility was 0.705 at λ = 0, 0.755 at log 2 and
0.787 at log 4. The effect among the eligible hardly moved because the
share of comorbid patients among them changed by less than one
percentage point: with effects of −0.04 and −0.12, a Δ<sub>ID</sub> of
−0.0007 corresponds to a shift of about 0.008 in that share.

## Estimators

Every estimator’s bias for its declared risk difference was classed
equivalent in all 48 scenarios
(<a href="#tbl-methods" class="quarto-xref">Table 1</a>). The largest
absolute bias at M = 20 or without imputation was 0.0017, and coverage
ran from 0.940 to 0.974. The complete-case analysis estimates the effect
among recorded eligibles, which differed from the effect among all
eligibles by at most 0.0090.

<div id="tbl-methods">

Table 1: Risk-difference performance across the 48 scenarios: largest
absolute bias and the range of coverage of the nominal 95% interval. The
M = 50 imputation check ran on 80 replicates per scenario and is not
shown.

<div class="cell-output-display">

| method                        | information   | max_abs_bias | coverage       |
|:------------------------------|:--------------|:-------------|:---------------|
| complete_case primary         | no_validation | 0.0004       | 0.942 to 0.956 |
| mar_ipaw primary              | no_validation | 0.0009       | 0.942 to 0.954 |
| mi_continuous m20             | no_validation | 0.0011       | 0.954 to 0.973 |
| mi_indicator m20              | no_validation | 0.0011       | 0.955 to 0.974 |
| oracle_recording_ipaw primary | no_validation | 0.0009       | 0.942 to 0.955 |
| sensitivity lambda_0          | no_validation | 0.0011       | 0.944 to 0.953 |
| sensitivity lambda_log2       | no_validation | 0.0008       | 0.945 to 0.953 |
| sensitivity lambda_log4       | no_validation | 0.0007       | 0.944 to 0.953 |
| oracle primary                | oracle        | 0.0005       | 0.943 to 0.954 |
| augmented intercept_r         | validation    | 0.0008       | 0.944 to 0.962 |
| augmented primary             | validation    | 0.0007       | 0.944 to 0.957 |
| fractional omit_c_h           | validation    | 0.0011       | 0.943 to 0.953 |
| fractional primary            | validation    | 0.0005       | 0.943 to 0.953 |
| two_phase_ipw primary         | validation    | 0.0017       | 0.940 to 0.955 |

</div>

</div>

Prevalence tells the other half
(<a href="#tbl-prevalence" class="quarto-xref">Table 2</a>). Without
validation, the missing-at-random estimators and the sensitivity
analysis at λ\* = 0 recovered prevalence at λ = 0 but underestimated it
by up to 0.082 at λ = log 4. The sensitivity analysis recovered it only
when its assumed λ\* equaled the true λ. The three validation-based
estimators were within 0.0015 at every λ.

<div id="tbl-prevalence">

Table 2: Bias in the prevalence of eligibility by the true λ, in the
decisive setting (heterogeneous effect, m = 0.50, κ = 1.10, expected
validation sample 100). The complete-case row is the recorded yield,
which is not a prevalence estimator.

<div class="cell-output-display">

|                               |   λ = 0 | λ = log 2 | λ = log 4 |
|:------------------------------|--------:|----------:|----------:|
| augmented intercept_r         |  0.0001 |   -0.0004 |   -0.0004 |
| augmented primary             |  0.0002 |   -0.0002 |   -0.0003 |
| complete_case primary         | -0.3772 |   -0.4267 |   -0.4590 |
| fractional omit_c_h           |  0.0002 |   -0.0003 |   -0.0003 |
| fractional primary            |  0.0002 |   -0.0002 |   -0.0003 |
| mar_ipaw primary              |  0.0000 |   -0.0495 |   -0.0817 |
| mi_continuous m20             | -0.0003 |   -0.0497 |   -0.0820 |
| mi_indicator m20              | -0.0003 |   -0.0498 |   -0.0820 |
| oracle primary                |  0.0002 |    0.0000 |    0.0001 |
| oracle_recording_ipaw primary | -0.0001 |   -0.0496 |   -0.0818 |
| sensitivity lambda_0          |  0.0000 |   -0.0495 |   -0.0818 |
| sensitivity lambda_log2       |  0.0493 |   -0.0001 |   -0.0324 |
| sensitivity lambda_log4       |  0.0816 |    0.0322 |   -0.0001 |
| two_phase_ipw primary         | -0.0009 |   -0.0014 |   -0.0015 |

</div>

</div>

# Discussion

The structural claim of ELG-01 holds: records alone cannot tell which of
two eligibility laws produced them. Whether that matters depends on the
quantity. The number of eligible people is not identified, and
estimators that assume eligibility is missing at random miss it by as
much as the hidden shift moves it. The risk difference among the
eligible differs by less than 0.001 between laws that produce the same
records, because the effect differs across patients only through
comorbidity and hidden eligibility barely changes comorbidity’s share.
For the effect to change by 0.010 with these effect sizes, the share
would have to move by about 12 percentage points.

A validation sample with known inclusion probabilities repairs both
quantities. Without one, an emulation can report the effect among the
eligible with some confidence and the size of the eligible population
with none, unless the missing measurement is itself strongly tied to who
benefits.

## What this study does not establish

The result is conditional on one baseline threshold criterion, a binary
60-month outcome, correctly specified models and a single effect
modifier. It cannot estimate a real-world λ or establish empirical
materiality. It does not cover external, nonprobability or
unknown-probability validation, validation measured with error,
time-varying eligibility, treatment switching, censoring or unmeasured
treatment confounding. A hidden eligibility mechanism tied more strongly
to the effect modifier than this one could change the effect materially.

## Review

The design was reviewed and revised before any code was written. An
earlier version of the analysis called the bias-eliminated coverage
function with its arguments in the wrong order; that was fixed across
all studies before this run. The results have not yet been reviewed.

# Data and code availability

Code, protocol and result files:
<https://github.com/choxos/TTE-open-problems/tree/main/studies/ELG-01-latent-eligibility-validation>.

# References

<div id="refs" class="references csl-bib-body">

<div id="ref-tompsett2023missing" class="csl-entry">

<span class="csl-left-margin">1.
</span><span class="csl-right-inline">Daniel Tompsett, Ania
Zylbersztejn, Pia Hardelid, Bianca De Stavola. Target trial emulation
and bias through missing eligibility data: An application to a study of
palivizumab for the prevention of hospitalization due to infant
respiratory illness. American Journal of Epidemiology.
2023;192(4):600–11.
doi:[10.1093/aje/kwac202](https://doi.org/10.1093/aje/kwac202)</span>

</div>

<div id="ref-benz2025missing" class="csl-entry">

<span class="csl-left-margin">2.
</span><span class="csl-right-inline">Luke Benz, Rajarshi Mukherjee, Rui
Wang, David Arterburn, Heidi Fischer, Catherine Lee, others. Adjusting
for selection bias due to missing eligibility criteria in emulated
target trials. American Journal of Epidemiology. 2025;194(11):3126–39.
doi:[10.1093/aje/kwae471](https://doi.org/10.1093/aje/kwae471)</span>

</div>

<div id="ref-morris2019simulation" class="csl-entry">

<span class="csl-left-margin">3.
</span><span class="csl-right-inline">Tim P. Morris, Ian R. White,
Michael J. Crowther. Using simulation studies to evaluate statistical
methods. Statistics in Medicine. 2019;38(11):2074–102.
doi:[10.1002/sim.8086](https://doi.org/10.1002/sim.8086)</span>

</div>

</div>
