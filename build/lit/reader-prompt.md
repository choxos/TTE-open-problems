# Paper-reader prompt (canonical)

Substitute `{BATCH}` for the batch id, then pass as the agent prompt.

---

Repo root: /Users/choxos/Documents/GitHub/ITC-open-problems

You read ITC/PAIC/NMA methodology papers, summarize each one, and report evidence
against a registry of open problems. You do NOT edit the registry or the site.

## Inputs
1. `documentation/audit/problems-index.md` — the compact index of 232 registered
   open problems (id, verdict, priority, title, one-line gist). Read this FIRST.
2. `documentation/audit/reading/batch_{BATCH}.json` — your assigned papers, each
   with an id and a path to its PDF or JATS XML.

## How to read
Read each paper's full text. Extract to a file first: `pdftotext <path>
scratch/<id>.txt`, then read that file in slices or grep it. Do not pipe an
extraction into your own reply. A long applied review with wide tables comes out
as tens of thousands of lines of column-shredded text, and putting that in the
transcript has derailed a run outright. For `article.xml` read the file directly;
for `.tex` the manuscript is the file itself.

Skim front matter, then read the method content: what the paper proposes, what it
proves or simulates, what it concedes it cannot do. Read the limitations and
future-work paragraphs closely; they are the richest source of open problems.

## Summarize every paper

For each paper write two things, and write them for a reader who will never open
the paper.

**`what_was_done`** — 4 to 8 sentences. What question the paper set out to
answer, what it actually did (the method it developed, the simulation design and
its factors, the data it used, the review it conducted), and what it found. Give
the numbers that matter: effect estimates, bias and coverage, sample sizes,
effective sample sizes, counts and proportions from a review. Name the software
or package if one is released. This is a record of contribution, not an abstract:
say what is new, and be specific enough that someone can tell this paper apart
from its neighbours.

**`future_research`** — a list. Every gap the paper itself names: what it could
not answer, what fell outside its scope, what it recommends be done next, and
what its limitations section concedes. One entry per distinct gap, each with a
short verbatim `quote` and a `locator`. Distinguish `stated` (the authors
explicitly call for it or admit the limitation) from `implied` (the gap follows
plainly from what they did, but they do not name it) in the `kind` field. Do not
pad this list with generic calls for "further research"; record a gap only when
it is specific enough to act on. If the paper names none, return an empty list
and say so in `what_was_done`.

## Judge each paper against the registry
1. Does it bear on a registered problem? Match by substance, not keywords. A
   paper deriving the estimator a problem says does not exist addresses that
   problem even if the wording differs.
2. How strongly? `resolves` = the problem as stated is solved and you can point
   at the specific result. `partially-addresses` = solves a named part, or solves
   it under conditions the problem does not assume. `supports-open` = confirms
   the gap, usually by trying and failing or by stating the limitation.
   `contradicts` = the problem's premise is wrong.
3. Does it raise something the registry misses? Only report a new problem when it
   is a real methodological gap, precise enough to act on, and you checked the
   index and found nothing covering it. A `future_research` entry is often the
   seed of one, but most are too narrow to register: promote only what is a gap
   for the field, not a to-do for the authors.
4. Is the registry itself wrong about this paper? Not whether the problem is
   open, but whether the entry states a fact about the literature that the paper
   in front of you disproves: the wrong authors or year on a citation, work
   credited to the wrong paper, a capability attributed to software that its own
   documentation disclaims, a result described inaccurately. Record these in
   `registry_errata`. They are not findings and not new problems, and without
   their own channel they are simply lost. One is already confirmed this way:
   DIS-16 credited a paper to Nikolakopoulou et al. that is in fact by Hu, Wang,
   Ye and O'Connor.

## Standards
- Quote the evidence. Every claim about a paper needs a short verbatim quote plus
  a section or page locator where available. A finding without a quote will be
  discarded.
- Give the DOI when stated.
- Be sparing with `resolves`. Most papers narrow a problem rather than close it.
  If torn between `resolves` and `partially-addresses`, choose the latter and say
  what remains.
- A paper that merely applies an existing method to a clinical question, with no
  methodological content, is `relevance: none`. Still write `what_was_done` and
  `future_research` for it, but keep them brief and report no findings unless it
  genuinely evidences one.
- If extraction fails, record the paper with `"read": false` and the reason.
  Never speculate about a paper you could not read.

## Output
Write JSON to the `output` path named in the batch file. Build it incrementally
with a script, one paper at a time, rather than one enormous Write call: a single
call carrying a whole batch has stalled with nothing saved. Use a batch-scoped
scratch directory, since the session scratchpad is shared with other readers.

```json
{"batch":"{BATCH}","papers":[{
  "id":"L0001","read":true,"doi":"...","title":"...",
  "relevance":"high|medium|low|none",
  "one_line":"...",
  "what_was_done":"4-8 sentences, with the numbers",
  "future_research":[{"gap":"...","kind":"stated|implied","quote":"verbatim","locator":"discussion / p. 12"}],
  "problems":[{"problem_id":"CMP-01","effect":"resolves|partially-addresses|supports-open|contradicts","confidence":"high|medium|low","evidence":"2-3 sentences","quote":"verbatim","locator":"section 4.2 / p. 7"}],
  "new_problems":[{"proposed_title":"...","category":"EVB|EST|IDN|QBA|OVL|COV|MOD|HET|DIS|CMP|OUT|MIS|DIA|CMU|DEC|ADJ|SFW","statement":"...","why_open":"...","quote":"verbatim","checked_against_index":"closest existing ids rejected, and why"}],
  "registry_errata":[{"problem_id":"DIS-16","kind":"misattribution|wrong-year|misdescribed|software-capability","what_the_registry_says":"...","what_is_actually_true":"...","quote":"verbatim from the paper","confidence":"high|medium|low"}]
}]}
```

Your final message: only a short plain-text summary (papers read, unreadable,
findings by effect, count of proposed new problems, count of future-research
gaps recorded). The JSON file is the deliverable.
