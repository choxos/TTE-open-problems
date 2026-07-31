# Open Problems in Target Trial Emulation

An audited catalog of open methodological problems in target trial emulation (TTE).

Each entry states what the problem is, why it stays open, what has already been tried, and the
most probable route to a solution. Every entry carries a verification verdict recording what
happened when its claims were checked, and the evidence behind that verdict is shown on the page.

## Why the verdicts are there

The source material was produced by a large language model. Publishing a machine-generated
research agenda as settled fact would be a disservice, so nothing appears here without having
been checked first:

- every DOI, arXiv identifier, PubMed identifier, CRAN version, and repository claim resolved
  against its registry;
- each cited work checked for whether it supports the claim attributed to it;
- an adversarial pass instructed to refute that each problem is open;
- independent frontier models auditing the same claims blind to each other;
- claims about a software package re-checked against that package's pinned source.

Where auditors disagreed, the site shows the disagreement rather than resolving it silently.

## Building

```bash
node build/render_site.mjs      # registry -> problem and category pages
node tools/check-registry.mjs   # validate the generated pages
node --test tests/              # adjudication rule tests
quarto render                   # -> docs/
quarto preview                  # live preview
```

Rendering needs Quarto 1.8 or later and Node 18 or later. Nothing else; the site has no R
execution at render time. Pushing to `main` renders and publishes to the `gh-pages` branch via
GitHub Actions.

Unlike its sibling project, the registry is tracked, so `node build/render_site.mjs` works on a
fresh clone. `.gitignore` explains which four files that covers and why.

## Layout

| Path | What it is |
|---|---|
| `build/render_site.mjs` | Registry to Quarto source. Owns the 18 category codes |
| `build/adjudicate.mjs` | Auditor opinions to a published verdict, by a fixed rule |
| `build/make_audit_batches.mjs` | Registry to batched prompts for the external auditors |
| `build/collect_opinions.mjs` | Auditor output to opinions attached to the registry |
| `build/lit/` | Search, screening, full-text retrieval, reading, drafting |
| `tools/check-registry.mjs` | Validates the generated pages; runs in CI before the render |
| `tools/check-calibration.mjs` | Asserts the known-answer fixtures before the site is built |
| `documentation/` | Source documents, reference corpus, audit working files. Mostly untracked |

## The pipeline

```bash
# 1. harvest
python3 build/lit/search.py
python3 build/lit/validate_against_tte_review.py

# 2. screen by hand, in batches of 200
python3 build/lit/batches.py build --size 200
python3 build/lit/batches.py decide --batch 1 --include 111,222
python3 build/lit/batches.py finalize

# 3. retrieve full text and catalog it
python3 build/lit/fetch.py --workers 6
python3 build/lit/library.py
python3 build/lit/index.py

# 4. read, verify, review
python3 build/lit/batch_reading.py --tier core --size 12
python3 build/lit/verify_quotes.py --write-report
python3 build/lit/second_review.py --all --parallel 4
python3 build/lit/merge_review.py

# 5. draft and audit
python3 build/lit/draft_problems.py --build --batches 10
node build/make_audit_batches.mjs --size 6
bash build/run_external_auditors.sh all 3
node build/collect_opinions.mjs
node build/adjudicate.mjs
```

`documentation/audit/calibration.json` holds known-answer cases verified by hand. Any audit
configuration that fails to reproduce them is miscalibrated, so they are asserted before the site
is built.

## License

MIT. See `LICENSE`.
