# Uncovered-theme assessor prompt (canonical)

Substitute `{BATCH}`, then pass as the agent prompt. See `build/lit/uncovered.py`
for how the payload is built and how the result is folded in.

---

Repo root: /Users/choxos/Documents/GitHub/ITC-open-problems

You assess candidate gaps for a published catalog of open problems in indirect
treatment comparisons. The catalog has 331 entries and they were written to a
standard.

These candidates are weaker evidence than anything already in the catalog. They
were not proposed by anyone who read a paper and argued for them. They came from
gap labellers who were attaching thousands of future-research sentences to a
fixed theme set and reported, at the end, what they had wanted and not found.
More than one labeller named each of these independently while working on
different gaps, which is why they are worth checking, and that is all it is.

Your job is to kill the ones that do not survive and write proper entries for
the ones that do. Rejecting is the expected outcome for some of these; an
assessor that promotes all of its candidates has not assessed them.

## Inputs
1. `documentation/audit/reading/uncovered/batch_{BATCH}.json` — your candidates.
   Each has the absence as the labellers described it, how many named it, and
   the `evidence_gaps`: the actual future-research sentences behind it, each
   with the paper, its year, a verbatim quote and a locator.
2. `documentation/audit/reading/uncovered/registry-index.json` — **all 331**
   current entries with id, title, category, verdict and the opening of each
   statement. Read all of it.

## Step 1, and most candidates should die here: is it still missing?

The labellers ran against 232 registered problems plus 115 accepted proposals.
Those proposals have since been written into entries, and their authors retitled
and rescoped many of them while checking sources. A candidate can have been
absorbed by that work.

Search the registry index properly. Match by substance, not title words: an
entry filed under a different category, or named differently, can still be the
same problem. When you find a plausible match, read that entry in full in
`documentation/audit/registry/problems.json` before deciding.

Reject with `already_covered` and name the id if the registry now covers it.

## Step 2: is it a gap for the field, or a to-do for those authors?

Read the evidence gaps and the quotes. Then read enough of the underlying papers
to know what they actually claim; they are catalogued in
`documentation/refs/library.json` by the `paper_id`, and extraction to a file
first is the way to read a PDF (do not paste extractions into your reply).

Reject with `not-a-field-gap` when the sentences are authors describing the
limits of their own study, a call for more trials, or a complaint about adoption
rather than a missing method. Reject with `not-substantiated` when the papers do
not say what the labellers took them to say.

A real one names something specific that does not exist: an estimator, a
diagnostic with known operating characteristics, a criterion, an identification
result, a validated instrument.

## Step 3: check it is actually absent from the literature

You have the papers the gaps came from, which say the thing is missing. That is
the authors' view and often dated. Before writing an entry, satisfy yourself
that nothing has since supplied it. If something has, either reject with
`resolved` or write the entry with verdict `partially-addressed` and say what
covers which part.

## Writing an entry

Same standard as the catalog. Match the voice of the existing entries.

- **`statement`**, 4 to 8 sentences: what the gap is, as a methodological fact.
  Name the specific missing thing. Use the concrete numbers from the evidence.
- **`why_open`**, 3 to 6 sentences: why it has not been solved, structurally.
  The good reasons are that the quantity is not identified from available data,
  the check needs information the design destroys, or two requirements conflict.
  If the honest answer is that nobody has tried, say so and say why it is
  unattractive.
- **`prior_work`**: `{cite, doi_or_url, what_it_does}`. **Every citation must be
  real and you must verify it before writing it.** An invented citation is the
  worst thing you can produce here.
- **`proposed_direction`**, 3 to 6 sentences: what would close it, or the first
  tractable step.
- **`category`**: one of EVB EST IDN QBA OVL COV MOD HET DIS CMP OUT MIS DIA CMU
  DEC ADJ SFW. Do **not** assign an id; that is done centrally.
- **`verdict`**, `priority`, `maturity`, `tractability` (1 to 5 or null),
  `severity`, `related` (ids from the registry index only).
- **`verdict_rationale`**: say plainly that this came from labeller-reported
  absence rather than from a paper arguing for it, how many labellers named it,
  how many distinct papers the gaps span, and what you checked. A reader should
  be able to see this entry rests on weaker provenance than its neighbours.

## House style
- **Never use a dash as a sentence connector or parenthetical.** No em dash, no
  en dash, no spaced hyphen, no double hyphen. Semicolon, colon or period.
- American spelling. No hedging filler. Do not write "this paper" or "the
  authors": an entry describes the field.

## Output

Write JSON to the `output` path in the batch file, incrementally with a script,
using a batch-scoped scratch directory.

```json
{"batch":"{BATCH}",
 "entries":[{"title":"...","category":"DEC","statement":"...","why_open":"...",
   "prior_work":[{"cite":"...","doi_or_url":"...","what_it_does":"..."}],
   "proposed_direction":"...","priority":"High","tractability":3,
   "maturity":"Emerging","severity":"...","verdict":"confirmed-open",
   "verdict_rationale":"...","related":["DEC-08"]}],
 "rejected":[{"absence":"...","why":"already_covered|not-a-field-gap|not-substantiated|resolved",
   "covered_by":"DEC-04 or null","reasoning":"three or four sentences"}]}
```

Every candidate in your batch must appear exactly once, in `entries` or in
`rejected`.

Your final message: which candidates you promoted and which you killed and why,
in a few lines each. Be specific about what decided each call.
