# DTA-02: no design amendment; a code defect and the run plan

Decision: the registered design (`documentation/studies/designs/DTA-02-averaging-site-estimates-in-a-federated-emul-revised.json`) can answer its question on this machine within budget, so no registered amendment is proposed. The study must not run as committed, however: every replicate estimates nothing. The section headings below follow the amendment template so that the evidence is in the usual place.

## 1. Why the registered design cannot answer as committed

**The stated blocker is not a blocker.** The status note records a 44-hour forecast on a shared machine and a ceiling raised to 72 hours. That forecast is wall time for six workers at a load average near 200, not CPU time. Measured in scratch, one block-replicate (one common-random-number block producing all 12 formal scenarios of that block) costs 2.6 CPU-seconds as committed and 5.5 to 5.9 CPU-seconds (blocks 6 and 1) once the defect below is fixed.

**The committed code estimates nothing.** In `R/01-dgm.R`, `basic_contingencies` builds the eligibility confusion table with

```r
aggregate(tab$n_elig, list(site = tab$site, pred = 1L, true = tab$e_ref), sum)
```

and the same with `pred = 0L`. `aggregate` requires every grouping vector to have the length of the data; a scalar `1L` stops it with "arguments must have same length". `run_validation` calls this for every formal scenario, `one_rep` catches the error, and `blank_formal` then writes `validation-failed` for all 11 methods, including the ungated estimators that never depend on validation. A scratch replicate of block 1 with the committed code returned 132 of 132 rows `validation-failed` and no estimate. With `pred = rep(1L, nrow(tab))` and `pred = rep(0L, nrow(tab))`, the same replicate returned 132 of 132 rows estimated; over 15 replicates of block 1, 180 of 180 rows per method estimated.

Two consequences follow. The 44-hour benchmark timed the failing path, which skips all validation sampling, so it understates the real cost by about half. And `results/benchmark.rds` gates the run: `04-run.R` reuses it whenever it exists, so it must be deleted and remeasured after the fix, together with any raw replicate caches written before the fix, which `run_design(resume = TRUE)` would otherwise reuse.

## 2. What changes

Nothing in the registered design. Code: the two grouping vectors above. Operations: delete the stale benchmark and caches and remeasure.

## 3. The gates can pass

Checked in scratch with the fix applied in memory only (15 replicates of block 1, kappa = 0, gamma = 0; the aggregate gate was not evaluated because its frozen calibration files live under `results/`):

| gate or branch | measured | registered requirement |
|---|---|---|
| compatible common-q estimator valid | 180 of 180 | validity checks pass |
| numerical nonconvergence | 0 of 180 per method | at most 0.10 |
| compatible release, local validation, perfect reference | 1.00 at 50, 100 and 200 records per class | lower bound at least 0.90 for adequacy |
| compatible release, local validation, 5% reference error | 0.00 at 50, 0.27 at 100, 1.00 at 200 | upper bound at most 0.88 for inadequacy |
| mechanism, not-real branch | exact change 0 for every applied mapping at kappa = 0 (committed truth) | exact change at most 1e-8 and interval inside plus or minus 0.002 |
| mechanism, real branch | exact six-site change 0.01 (broad exposure) and 0.02 (broad outcome) at kappa = 1 | exact change above 1e-8 and interval excluding zero |

Both validation branches are therefore reachable: small validation samples cannot certify a compatible network when the reference itself errs at 5%, while 200 records per class can. Whether the aggregate gate releases compatible networks at 0.90 or more depends on the frozen calibration and is measured by the run; both of its branches are reachable by construction because its critical values are calibrated to compatible counts.

## 4. Cost

Base run: 6 blocks by 5000 replicates by at most 5.9 CPU-seconds is at most 177,000 CPU-seconds, 49 CPU-hours. Each adaptive batch of 5000 over all six blocks adds another 49 CPU-hours, so the registered cap of 50,000 replicates is 490 CPU-hours if every block extends to it, which it will not: a block extends only while one of its cells has a bound crossing a threshold.

**Run plan.**

1. Apply the two-line fix; add a check that `run_validation` returns without error on one block before any batch starts.
2. Delete `results/benchmark.rds`, `results/benchmark/` and any raw replicate files written before the fix.
3. `Rscript R/03-truth.R` only if the frozen calibration files are absent; the truth table is unaffected by the defect.
4. `TTE_BATCH_ID=1 Rscript R/04-run.R`: benchmark then base run. The remeasured wall forecast will be about twice the old one at the same machine load (about 100 hours at load 200), and `04-run.R` refuses to start when the forecast exceeds `OVERNIGHT_SECONDS`, now 72 hours. Either benchmark and run when the load is lower or raise that operational ceiling again with the reason recorded; it is not a statistical parameter.
5. Analyze; list the cells whose bounds still cross a threshold.
6. `TTE_BATCH_ID=2` restricted to the blocks containing those cells. This keeps the total near 100 CPU-hours. Continuing further toward the registered 50,000 needs the owner's allocation of about 49 CPU-hours per additional all-block batch; cells still unresolved when the allocation ends are uninformative, as the registered rule already provides at the cap.

## 5. What the amended study no longer answers

Nothing is dropped. If the owner caps the adaptive continuation below 50,000 replicates, cells that would have resolved between the cap and 50,000 are reported as uninformative instead.
