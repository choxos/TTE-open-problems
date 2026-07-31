# Gap-labeller prompt (canonical)

Substitute `{BATCH}` for the two-digit batch id, then pass as the agent prompt.
See `build/lit/label_gaps.py` for why this is a labelling task and not a
clustering one.

---

Repo root: /Users/choxos/Documents/GitHub/ITC-open-problems

You attach future-research gaps to themes. Each gap is one sentence a paper's
own authors wrote about what they could not do. Your job is to say which known
theme each one belongs to, so that gaps written by different authors in different
years can be read as one record instead of many.

You do NOT judge whether a gap is real, whether a theme is open, or whether the
paper is any good. Only: which theme is this gap an instance of?

## Inputs
1. `documentation/audit/reading/gaps/themes.json` — the theme set. Each entry has
   an `id`, a `title` and a `gist`. Ids beginning with a category prefix
   (`CMP-03`, `HET-11`, …) are registered problems; ids beginning `NEW-` are
   problems this reading proposed and an independent reviewer accepted. Read this
   FIRST and read all of it. A gap can only be labelled with an id that appears
   here.
2. `documentation/audit/reading/gaps/batch_{BATCH}.json` — your gaps. Each has a
   `gap_id`, the `gap` text, the paper it came from, and its year.

## How to label
Match by substance, not vocabulary. The whole point of this pass is that the same
gap gets written in words that do not overlap: "the correlation between components
is not identifiable from aggregate data" and "we could not estimate how components
interact without patient-level data" are one theme. Authors from different
subfields name the same thing differently, and a decade apart they name it
differently again.

- Read the gap, work out what would have to be built or shown for it to be
  closed, then find the theme that is about that same thing.
- Prefer a specific theme over a general one when both fit.
- One theme per gap: the single best fit.
- `none` is a real answer and should be used freely. Most papers name at least
  one gap that is a to-do for those authors rather than a gap for the field
  ("we did not have the resources to extend the simulation"), and many name gaps
  in areas this theme set does not cover at all. Forcing those onto the nearest
  theme is worse than leaving them out, because it manufactures a recurrence that
  nobody actually asserted.
- Do not label a gap by the paper's topic. A cardiology NMA can name a gap about
  heterogeneity priors; the theme is the heterogeneity prior, not cardiology.

Give a `confidence` of `high`, `medium` or `low`. Use `low` when two themes fit
about equally, and name the runner-up in `also`.

## Output
Write JSON to the `output` path named in the batch file. Build it incrementally
with a script rather than one enormous Write call, and use a batch-scoped scratch
directory.

```json
{"batch":"{BATCH}","labels":[
  {"gap_id":"L0123#4","theme":"HET-03","confidence":"high","also":null},
  {"gap_id":"L0123#5","theme":"none","confidence":"high","also":null},
  {"gap_id":"L0124#0","theme":"NEW-12","confidence":"low","also":"CMP-03"}
]}
```

Return exactly one label per gap in your batch, with the `gap_id` copied
verbatim. Every `theme` must be `none` or an `id` that exists in `themes.json`.

Your final message: only a short plain-text summary (gaps labelled, how many
landed on `none`, the five themes you used most, and any theme you found yourself
wanting that does not exist in the set).
