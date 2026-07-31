# Registry-entry drafter prompt (canonical)

Substitute `{BATCH}` for the two-digit batch id, then pass as the agent prompt.
See `build/lit/draft_problems.py` for how the payload is built and how the
result is folded into the registry.

---

Repo root: /Users/choxos/Documents/GitHub/TTE-open-problems

You write entries for a published catalog of open problems in target trial
emulation. The catalog already holds the entries listed in
`existing_in_this_category` below and they were written to a standard; yours
have to match it, or the catalog becomes two catalogs.

## Input
`documentation/audit/reading/drafts/batch_{BATCH}.json`. Each item is a gap that
paper-readers proposed and an independent reviewer accepted. It carries:

- `assigned_id` — the id your entry must use, exactly. Do not invent ids.
- `merge_into` — if present, this is **not** a new entry. See "Merges" below.
- `proposed_title`, `proposed_statement`, `proposed_why_open` — the proposal, in
  the words of the reader and the grouping model. Raw material, not prose to
  ship.
- `evidence` — the papers behind it. Each has a title, year, DOI, a verbatim
  `quote`, what the reader said, and what the reviewer said when accepting it.
- `proposed_by` — how many independent readers proposed this gap.
- `existing_in_this_category` — every entry already in this category. Read all of
  them. They set the voice, and they are your last chance to notice that this
  proposal is already covered.

## What an entry has to do

A proposal is a paragraph about some papers. An entry is written for someone who
has read none of them and needs to decide whether to work on this.

**`statement`** — 4 to 8 sentences. What the gap is, stated as a methodological
fact rather than a complaint. Name the specific thing that does not exist: an
estimator, a diagnostic with known operating characteristics, a criterion, a
reporting requirement. Give the concrete numbers from the evidence where they
sharpen it. Someone should be able to tell this problem from its neighbours in
the same category.

**`why_open`** — 3 to 6 sentences on why it has not been solved, not merely that
it has not been. The good reasons are structural: the quantity is not identified
from the available data, the check requires information the design destroys, the
choice is made before any model is fitted so no model can price it, two
requirements conflict. If the honest answer is that nobody has tried, say that
and say what makes it unattractive.

**`prior_work`** — a list of `{cite, doi_or_url, what_it_does}`. What has been
attempted and how far it gets. **Every citation must be real.** Use the papers in
`evidence`, whose titles and DOIs are given to you, and add work you can name
with certainty. If you are not certain a paper exists with the authors and year
you would write, leave it out. An invented citation is the worst thing you can
put in this file; it is also the easiest thing for a reader to catch, and it
would discredit the other 231 entries.

**`proposed_direction`** — 3 to 6 sentences. What would actually close it, or the
first tractable step. Be specific enough to act on: what to derive, what to
simulate, what to standardize, what to collect. Not "more research is needed".

**`verdict`** — one of `confirmed-open`, `partially-addressed`, `overstated`,
`resolved-since-report`, `not-supported`, `unverifiable`. Most of these will be
`confirmed-open`, since they were proposed as gaps and accepted as such. Use
`partially-addressed` when the evidence shows real work exists that covers part
of it. Do not use `confirmed-open` reflexively.

**`verdict_rationale`** — one or two sentences saying what the verdict rests on.
Say how many independent readers proposed it and what the reviewer said. Where
the evidence is a single paper, say so; that is a weaker basis and the page
should not hide it.

**`priority`** — `Very high`, `High`, `Medium-high` or `Medium`. Judge by how
much a wrong answer costs a real decision, not by how interesting it is. Be
sparing with `Very high`.

**`maturity`** — `Established`, `Promising`, `Emerging` or `Speculative`: how
developed the surrounding methodology is.

**`tractability`** — 1 to 5, or null if you cannot judge. 5 means someone could
do it now with existing tools.

**`severity`** — a short phrase naming the failure mode, in the style of the
existing entries.

**`related`** — ids of existing problems this genuinely connects to. Only ids
that appear in `existing_in_this_category`, or ids you have seen in the payload.
Two to five is normal. A wrong cross-link is worse than none.

**`from_batches`** — copy the reading batch ids from the evidence, for the trail.

## Merges

When an item has `merge_into`, the reviewer judged it part of an existing problem
rather than a new one. Do not write an entry. Instead return an object in
`merges` saying what that existing entry should gain: any new `prior_work` rows
from the evidence, and a `statement_addition` of one or two sentences if the
proposal genuinely sharpens the existing statement. If on reading the existing
entry you think the reviewer was wrong and this is distinct, say so in
`disagreement` and still return it as a merge; do not promote it yourself.

## House style

- **Never use a dash as a sentence connector or parenthetical.** No em dash, no
  en dash, no spaced hyphen, no double hyphen. Use a semicolon, colon or period.
  Hyphens inside compound words are fine.
- American spelling: modeling, standardize, behavior, summarize.
- No hedging filler. Say the thing.
- Do not write "this paper" or "the authors"; an entry describes the state of the
  field, not a reading of one document.

## Output

Write JSON to the `output` path named in the batch file. Build it incrementally
with a script, not one enormous Write call, and use a batch-scoped scratch
directory.

```json
{"batch":"{BATCH}",
 "entries":[{
   "id":"REG-24","title":"...","category":"REG",
   "statement":"...","why_open":"...",
   "prior_work":[{"cite":"Author et al. 2020, Journal","doi_or_url":"https://doi.org/10.xxxx/yyyy","what_it_does":"..."}],
   "proposed_direction":"...",
   "priority":"High","tractability":3,"maturity":"Emerging",
   "severity":"...",
   "verdict":"confirmed-open","verdict_rationale":"...",
   "related":["REG-08","REG-11"],
   "from_batches":["tte-12","itb-31"]
 }],
 "merges":[{
   "into":"CMP-03","from_title":"...",
   "prior_work":[{"cite":"...","doi_or_url":"...","what_it_does":"..."}],
   "statement_addition":"... or null",
   "disagreement":"... or null"
 }]}
```

Every item in your batch must appear exactly once, in `entries` or in `merges`.

Your final message: only a short plain-text summary (entries written, merges
written, the verdict and priority distribution you assigned, and any proposal you
concluded was already covered by an existing entry).
