# GMT-04: interface fixed, blocked on compute

## Resolved 2026-09-22

The ltmle interface is fixed and passes its contract test.

1. **Outcome coding.** ltmle's survival contract needs an event indicator that
   stays 1, and censoring nodes coded censored/uncensored. The study's wide data
   carry `S` as alive and `R` as 1 for uncensored. `ltmle_wide()` recodes both
   for the ltmle call only; every other consumer of `S` is unchanged. ltmle then
   estimates the 36-month risk directly and its influence curve needs no sign
   change.
2. **Influence curve.** ltmle 1.3 returns `IC` as a named list of unnamed
   vectors. The extractor searched for a named numeric and never found it, so
   every call failed as "influence curve not found".

Known-answer check on the C0 control (n = 4000, true risks 0.352 and 0.352, true
RD 0): ltmle returns 0.364 and 0.351, RD −0.013, SE 0.022.

ltmle reports that L1 to L5 are dropped from `Qform` because each sits in a block
with the preceding outcome node. That is correct: with no intervention node
between S_k and L_k, one regression at the head of the block integrates over
both.

## Not a defect

The nuisance-adjusted IPTW variance is missing when a regime-by-interval cell has
no events (1 of 3 test replicates at s = 1.0). The protocol registers a
saturated pooled logistic event model, whose logit-scale sandwich is singular at
a zero hazard. The protocol records such common invalid outputs as a separate
outcome, so this is behavior to report, not to repair.

## Remaining block: compute

One replicate takes 110 to 470 seconds per run scenario on this machine, which is
shared and at load average about 200. At the registered 2000 replicates across 14
run scenarios that is roughly 1500 CPU hours. The run needs either more compute
or a registered reduction in replicates.
