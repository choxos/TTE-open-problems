#!/usr/bin/env node
// Renders the audited problem registry into Quarto source.
//
// Input   documentation/audit/registry/problems.json   (array of adjudicated records)
//         documentation/audit/reading/timeline.json     (evidence in publication order)
//         documentation/audit/reading/gap-chronology.json (recurring gaps by year)
// Output  problems/<id>-<slug>.qmd                     (one page per problem)
//         categories/<slug>.qmd                        (one listing page per category)
//         chronology.qmd                               (what the dates say)
//         references.bib                               (only cites that survived verification)
//
// The registry is the source of truth. These files are generated; edit the registry,
// not the .qmd. Running this twice with the same registry produces identical output.
//
// The chronology inputs are optional. They come from the full-text reading, which is a
// separate and much slower pass, and the site has to render without them: a missing
// timeline.json costs the dated sections and nothing else.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const REGISTRY = join(ROOT, 'documentation/audit/registry/problems.json')
const READING = join(ROOT, 'documentation/audit/reading')
const PROBLEMS_DIR = join(ROOT, 'problems')
const CATEGORIES_DIR = join(ROOT, 'categories')

const readJson = (p, fallback) =>
  existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : fallback

// Populated in main(). Empty when the reading has not been run, which every
// consumer below has to tolerate.
let TIMELINE = {}
let TIMELINE_VERDICT = {}
// Our own simulation and case studies, keyed by problem id. Unlike the two
// above this is tracked in the repository rather than derived from the
// gitignored working directory, because the studies are published output.
let STUDIES = {}

export const CATEGORIES = [
  { code: 'PRO', slug: 'protocol', name: 'Protocol specification & well-defined interventions',
    blurb: 'The protocol is the analysis. What a complete statement of the seven components requires, and what an emulation silently assumes when a component is left implicit.' },
  { code: 'ELG', slug: 'eligibility', name: 'Eligibility, cohort entry & the new-user question',
    blurb: 'Trial eligibility is written for a screening visit; a database records billing codes and encounters. Prevalent users, criteria that cannot be verified at all, and the comparator that decides who is comparable to whom.' },
  { code: 'TZO', slug: 'time-zero', name: 'Time zero, alignment & time-related bias',
    blurb: 'Eligibility, treatment assignment and the start of follow-up must coincide. Immortal time, time-lag bias and depletion of susceptibles are what happens when they do not; several of them survive correct alignment.' },
  { code: 'STR', slug: 'strategies', name: 'Treatment strategies, grace periods & cloning',
    blurb: 'Sustained and dynamic strategies, the grace period that makes them achievable, and the cloning that makes them estimable. A grace period is not a nuisance parameter; it changes the estimand.' },
  { code: 'EST', slug: 'estimands', name: 'Estimands, causal contrasts & target populations',
    blurb: 'What is being estimated, for whom, on which scale: the observational analogue of intention to treat, the per-protocol effect nobody randomized, and the transport step to the population that will act on the answer.' },
  { code: 'CNF', slug: 'confounding', name: 'Confounding control & the assignment assumption',
    blurb: 'Randomization is replaced by an assumption about how treatment was assigned. Which confounders, measured when, at what frequency, and whether an active comparator buys back what conditioning cannot.' },
  { code: 'GMT', slug: 'g-methods', name: 'G-methods: specification, estimation & inference',
    blurb: 'Inverse probability weighting, the parametric g-formula, marginal structural models and g-estimation. What each demands of the analyst, and the specification choices that never reach the write-up.' },
  { code: 'OVL', slug: 'positivity', name: 'Positivity, structural violations & extrapolation',
    blurb: 'A sustained strategy over long follow-up puts probability mass where the data have none. Structural violations are not repaired by truncation, and effective sample size does not reveal them.' },
  { code: 'UCF', slug: 'unmeasured-confounding', name: 'Unmeasured confounding, negative controls & bias analysis',
    blurb: 'Exchangeability is the assumption nobody can check. E-values, negative controls, empirical calibration, proximal methods and instruments: what each rules out, and what it leaves standing.' },
  { code: 'MER', slug: 'measurement', name: 'Measurement error & misclassification in routine data',
    blurb: 'Exposure, outcome, covariate and eligibility are all algorithmic constructs in claims and electronic health records. Error in each propagates differently through a longitudinal estimator.' },
  { code: 'MIS', slug: 'missing-data', name: 'Missing data, censoring & loss to follow-up',
    blurb: 'A missing covariate history, artificial censoring created by the design, administrative censoring created by disenrollment, and loss to follow-up that is informative. Four problems that one weight is asked to solve.' },
  { code: 'OUT', slug: 'outcomes', name: 'Outcomes, competing events & the time scale',
    blurb: 'Ascertainment windows, competing events that make the estimand a choice rather than a nuisance, recurrent and composite endpoints, and hazard contrasts that are not causal effects.' },
  { code: 'SEQ', slug: 'sequential', name: 'Sequential emulation & nested trials',
    blurb: 'One person contributes to many nested trials opened at successive eligibility windows. What the pooled estimator targets, and how its variance behaves under overlapping person-trials.' },
  { code: 'DTA', slug: 'data-sources', name: 'Data sources, linkage & federated infrastructure',
    blurb: 'Claims, electronic health records, registries, linked national data and federated networks each destroy different information. Whether a trial can be emulated in a source is a finding, not a preliminary.' },
  { code: 'BEN', slug: 'benchmarking', name: 'Benchmarking, falsification & empirical validation',
    blurb: 'An emulation and the trial it emulates disagree. Nothing in the current toolkit attributes that difference to confounding, measurement, population, estimand or chance.' },
  { code: 'REG', slug: 'reporting', name: 'Reporting, regulation & decision acceptance',
    blurb: 'TARGET, STaRT-RWE, HARPER and regulatory real-world evidence guidance state what to report. Their scope stops where the disputes start: sustained strategies, time-varying confounding and cloning.' },
  { code: 'SFW', slug: 'software', name: 'Software, computation & reproducibility',
    blurb: 'The package landscape and the gaps between packages, the computational cost of the g-formula at national scale, and the fact that a published emulation is rarely rerunnable by anyone who did not write it.' },
  { code: 'LRN', slug: 'learning', name: 'Machine learning, high-dimensional adjustment & automated emulation',
    blurb: 'High-dimensional confounder selection, targeted and doubly robust learning, and language models pointed at clinical text. What each adds to an emulation, and what it adds that cannot be checked.' },
]

const BY_CODE = Object.fromEntries(CATEGORIES.map((c) => [c.code, c]))

const PRIORITY_RANK = { 'Very high': 1, High: 2, 'Medium-high': 3, Medium: 4 }

const EFFECT_LABEL = {
  'supports-open': 'confirms it is open',
  'partially-addresses': 'partly addresses it',
  resolves: 'resolves it',
  contradicts: 'contradicts its premise',
}

const VERDICT_LABEL = {
  'confirmed-open': 'Confirmed open',
  'partially-addressed': 'Partially addressed',
  overstated: 'Overstated',
  'resolved-since-report': 'Resolved since report',
  'not-supported': 'Not supported',
  unverifiable: 'Unverifiable',
}

const slugify = (s) =>
  s.toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 60)

// YAML scalars here can contain colons, quotes, and em-dash-free prose; always quote.
const y = (s) => `"${String(s ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`

// Pandoc attribute syntax needs a dot on every class, not just the first.
const chipClass = (p) => `.chip .chip-priority-${slugify(p || 'medium')}`


// Auditors return locators in several shapes: bare DOI, "doi:10.x", "arxiv:1234.5678",
// "cran:pkg", "owner/repo@sha", or a full URL. Turn each into something clickable.
function normalizeLocator(loc) {
  const s = String(loc).trim()
  if (/^https?:\/\//i.test(s)) return s
  if (/^10\.\d{4,9}\//.test(s)) return `https://doi.org/${s}`
  const m = s.match(/^(doi|arxiv|pmid|cran)[:\s]+(.+)$/i)
  if (m) {
    const [, kind, id] = m
    if (/doi/i.test(kind)) return `https://doi.org/${id}`
    if (/arxiv/i.test(kind)) return `https://arxiv.org/abs/${id.replace(/^arxiv:/i, '')}`
    if (/pmid/i.test(kind)) return `https://pubmed.ncbi.nlm.nih.gov/${id}/`
    if (/cran/i.test(kind)) return `https://cran.r-project.org/package=${id.split(/[\s,]/)[0]}`
  }
  if (/^[\w.-]+\/[\w.-]+(@\w+)?$/.test(s)) return `https://github.com/${s.split('@')[0]}`
  return s
}

const REPO = 'https://github.com/choxos/TTE-open-problems'

// The catalog says a problem is open. A study on this page says what happened
// when someone tried to settle it. The two must not blur together: the study is
// our own work and carries our own uncertainty, so it is labelled as such and
// kept structurally separate from the audited catalog entry above it, and it
// always states what it did not answer.
function studySection(s) {
  if (!s) return []
  // Keys match FORMATS in build/studies/publish.py, where Markdown is 'gfm'.
  const dl = Object.entries({ pdf: 'PDF', gfm: 'Markdown', odt: 'OpenDocument' })
    .filter(([k]) => s.downloads?.[k])
    .map(([k, label]) => `[${label}](/${s.downloads[k]})`)
    .join(' · ')

  if (s.status !== 'complete') {
    return [
      '## Our study', '',
      '::: {.callout-note}',
      `## ${s.status === 'running' ? 'A study is running' : 'A study is designed'}`,
      '',
      `**Question.** ${s.question}`,
      '',
      s.design ? `**Design.** ${s.design}` : null,
      '',
      s.protocol ? `The protocol is registered before any result is seen: [read it](/${s.protocol}).` : null,
      ':::', '',
    ].filter((x) => x !== null)
  }

  const out = [
    '## Our study', '',
    '::: {.study-result}',
    `**${s.title}**`, '',
    // A study aimed at a neighbouring entry may still be the best evidence on
    // this one, but a reader must not mistake it for a study of this problem.
    s.secondary
      ? `*This study was designed against [${s.primary_problem}](${REPO}/tree/main/${s.code}) ` +
        `and bears on this entry in part. What it does not answer is stated below.*\n`
      : null,
    `**The question put to it.** ${s.question}`, '',
    `**What it found.** ${s.answer}`, '',
  ].filter((x) => x !== null)

  if (s.findings?.length) {
    out.push('**Results.**', '')
    for (const f of s.findings) out.push(`- ${f}`)
    out.push('')
  }

  out.push('**Design.**', '')
  out.push(
    [
      s.estimand ? `Estimand\n:   ${s.estimand}` : null,
      s.methods_compared?.length
        ? `Methods compared\n:   ${s.methods_compared.join(', ')}`
        : null,
      s.design ? `Data-generating mechanism\n:   ${s.design}` : null,
      s.n_sim ? `Replicates\n:   ${s.n_sim}` : null,
    ].filter(Boolean).join('\n\n'),
    ''
  )

  // Placed after the result on purpose. A reader who stops early should still
  // have seen the claim; a reader who continues must not be able to miss the
  // limits of it.
  out.push(`**What this does not answer.** ${s.not_answered}`, '')

  if (s.review) {
    out.push(
      `**Peer review.** ${s.review_rounds || 2} rounds, two independent reviewers. ` +
        'The reports, the point-by-point responses and the editorial decision are ' +
        `published in full: [read the review](/${s.review}).`,
      ''
    )
  }

  const links = [
    dl ? `Read it: ${dl}` : null,
    `Code and data: [${s.code}](${REPO}/tree/main/${s.code})`,
    s.protocol ? `Protocol: [registered before the run](/${s.protocol})` : null,
    s.review ? `Review: [full history](/${s.review})` : null,
  ].filter(Boolean)
  out.push(links.join(' · '), '')
  out.push(':::', '')
  return out
}

function problemPage(p) {
  const cat = BY_CODE[p.category] || { name: p.category, slug: slugify(p.category) }
  const verdictLabel = VERDICT_LABEL[p.verdict] || p.verdict
  const rank = PRIORITY_RANK[p.priority] ?? 4

  const fm = [
    '---',
    `title: ${y(p.title)}`,
    `description: ${y(p.statement)}`,
    `pid: ${y(p.id)}`,
    `topic: ${y(cat.name)}`,
    `categories: [${[cat.name, `${p.priority} priority`, verdictLabel].map(y).join(', ')}]`,
    `priority: ${y(p.priority)}`,
    `prank: ${rank}`,
    `verdict: ${y(verdictLabel)}`,
    `verdictslug: ${y(p.verdict)}`,
    `maturity: ${y(p.maturity)}`,
    p.tractability != null ? `tractability: ${p.tractability}` : null,
    '---',
    '',
  ].filter(Boolean).join('\n')

  const meta = [
    '::: {.problem-meta}',
    `[${p.id}]{.problem-id}`,
    `[${verdictLabel}]{.verdict .verdict-${p.verdict}}`,
    `[${p.priority} priority]{${chipClass(p.priority)}}`,
    `[${p.maturity}]{.chip .chip-maturity-${slugify(p.maturity || '')}}`,
    p.tractability != null ? `[Tractability ${p.tractability}/5]{.chip}` : null,
    p.implementation_specific ? '[Implementation-specific]{.chip}' : null,
    ':::',
    '',
  ].filter(Boolean).join('\n')

  const out = [fm, meta]

  if (p.source_unsourced) {
    out.push(
      '::: {.source-unsourced}',
      '**Source note.** This entry derives in part from a source document whose inline citations',
      'were ChatGPT interface tokens rather than references, and so resolve to nothing. Claims',
      'below are attributed to that document and were checked independently where possible;',
      'anything that could not be independently sourced is marked in the verification trail.',
      ':::',
      ''
    )
  }

  if (p.implementation_specific) {
    out.push(
      '::: {.callout-note appearance="simple"}',
      '## Scope',
      '',
      'This entry describes a limitation of a specific implementation rather than of the field.',
      'It is catalogued because the underlying methodological problem is general, and because a',
      'reference implementation is where such problems become concrete and checkable.',
      ':::',
      ''
    )
  }

  // A reader landing here must learn in the first screen that this entry has
  // been tested, not discover it below a thousand words of background.
  const study = STUDIES[p.id]
  if (study?.status === 'complete') {
    out.push(
      '::: {.callout-important appearance="simple"}',
      '## A study has been run against this problem',
      '',
      `${study.answer} [Read the study below](#our-study).`,
      ':::',
      ''
    )
  }

  out.push('## Statement', '', p.statement, '')
  out.push('## Why it is open', '', p.why_open, '')

  out.push('## What has been tried', '')
  if (p.prior_work?.length) {
    out.push('::: {.table-scroll}', '', '| Work | What it contributes |', '|---|---|')
    for (const w of p.prior_work) {
      // Through normalizeLocator, not raw. Prior-work entries carry the same
      // mixed locator shapes the auditors returned, so a bare "owner/repo@sha"
      // was being emitted as a relative link and resolving to nothing.
      const link = w.doi_or_url ? `[${w.cite}](${normalizeLocator(w.doi_or_url)})` : w.cite
      out.push(`| ${link} | ${w.what_it_does} |`)
    }
    out.push('', ':::', '')
  } else {
    out.push('No prior work is identified for this problem in the reviewed sources.', '')
  }

  out.push('## Probable solution or research direction', '', p.proposed_direction, '')

  out.push(...studySection(study))

  out.push('## Verification', '')
  out.push('::: {.verification-trail}')
  out.push(`**Verdict.** ${verdictLabel}. ${p.verdict_rationale}`, '')

  // Where the audit changed the claim, the corrected version is what the page states above.
  // The original belongs here, so the correction is checkable rather than silent.
  if (p.original_title && p.title_correction) {
    out.push(`**The source titled this.** "${p.original_title}" ${p.title_correction}`, '')
  }
  if (p.original_statement && p.original_statement !== p.statement) {
    out.push(`**The source said.** "${p.original_statement}"`, '')
    if (p.correction_note) out.push(`**What was wrong with it.** ${p.correction_note}`, '')
  }
  if (p.audit?.dissent) {
    out.push(`**Dissent.** ${p.audit.dissent}`, '')
  }

  // What the full-text reading changed, including what it deliberately did not.
  // A verdict that moves without a trail is worse than one that never moved: the
  // page still reads as authoritative and there is nothing left to check it
  // against. `verdict-held` rows exist for the same reason in reverse, so a
  // reader who sees the evidence and not the decision does not assume it was
  // missed.
  const ru = p.reading_update
  if (ru?.changes?.length) {
    const LABEL = {
      erratum: 'Corrected',
      citation: 'Citation corrected',
      verdict: 'Verdict changed',
      'verdict-held': 'Verdict left unchanged',
      'reopen-candidate': 'Flagged for reopening',
    }
    out.push(`**Revised by the full-text reading.** Applied ${ru.applied}.`, '')
    for (const c of ru.changes) {
      out.push(`${LABEL[c.kind] || c.kind}`)
      out.push(`:   **${c.what}** ${c.evidence || ''}`)
      if (c.previous_text) {
        out.push(`    Previously: "${String(c.previous_text).slice(0, 600)}"`)
      }
      out.push('')
    }
  }
  // A definition list reads better than bullets here: each auditor is a named term with
  // its finding underneath, and the trail is meant to be skimmed by auditor.
  const opinions = p.audit?.opinions || []
  const label = {
    literature: 'Literature and prior-art check',
    'solved-hunter': 'Prior-art search (inverted prior)',
    codex: 'GPT-5.6 Sol, technical and source-code lens',
    grok: 'Grok 4.5, recency lens',
    refuter: 'Adversarial refutation',
  }
  for (const o of opinions) {
    const votes = [o.status_vote, o.support_vote].filter(Boolean).join(' / ')
    out.push(`${label[o.auditor] || o.auditor}`)
    out.push(`:   **${votes}.** ${o.rationale || ''}`)
    for (const w of o.resolving_work || []) {
      out.push(`    Cites ${w.locator}${w.what_it_resolves ? `: ${w.what_it_resolves}` : ''}.`)
    }
    out.push('')
  }
  if (p.audit?.adjudication?.decision_path?.length) {
    out.push('Decision path')
    out.push(`:   \`${p.audit.adjudication.decision_path.join(' → ')}\``)
    out.push('')
  }
  out.push(':::', '')

  // The evidence in publication order. A pooled count of findings cannot show
  // that a gap was named in 2013 and again in 2024, or that partial progress
  // landed in between and later authors kept finding the gap anyway. Those are
  // different states and they matter to anyone deciding what to work on.
  const tl = TIMELINE[p.id]
  if (tl) {
    const span = tl.span ? `${tl.first} to ${tl.last}` : `${tl.first}`
    const CLASS_LINE = {
      'answered-later':
        'The most recent paper to touch this reports progress on it, and every paper calling it open is older.',
      'reasserted-after-progress':
        'Partial progress is on the record, and later work still calls this open. Both belong in view.',
      concurrent:
        'Progress and a fresh assertion of openness land in the same year.',
      'progress-only':
        'Every paper found here reports progress; none asserts the problem is open.',
      'open-only':
        'Every paper found here asserts the problem is open; none reports progress.',
    }
    out.push('## How the evidence falls in time', '')
    out.push(
      `${tl.papers} paper${tl.papers === 1 ? '' : 's'} in the reviewed corpus bear` +
        `${tl.papers === 1 ? 's' : ''} on this problem, published ${span}. ` +
        (CLASS_LINE[tl.class] || ''),
      ''
    )
    if (tl.flags?.includes('recurrent')) {
      out.push(
        'This problem is **recurrent**: three or more papers spanning at least eight years ' +
          'assert it independently. Sustained restatement by authors who mostly do not cite ' +
          'each other is the strongest evidence this reading can offer that a gap is real ' +
          'rather than one group\'s framing.',
        ''
      )
    }
    if (tl.flags?.includes('piecewise')) {
      out.push(
        'It is also being **closed in pieces**: partial results come from more than one paper ' +
          'in more than one year, each covering a different part.',
        ''
      )
    }
    const tv = TIMELINE_VERDICT[p.id]
    if (tv) {
      const VERD = {
        answers: 'answers what the earlier work left open',
        'answers-part': 'answers a component of it, leaving a named part',
        'different-question': 'is about a different question and leaves the earlier gap untouched',
        no: 'does not answer it',
        uncertain: 'could not be judged from the claims alone',
      }
      out.push(
        `**Does the later work answer the earlier work?** Put to an independent reviewer with ` +
          `the older and newer claims side by side, it judged that the later work ` +
          `${VERD[tv.verdict] || tv.verdict} (${tv.confidence} confidence). ${tv.reason}` +
          (tv.what_remains ? ` What remains: ${tv.what_remains}` : ''),
        ''
      )
    }
    out.push('::: {.table-scroll}', '', '| Year | Says | Paper |', '|---|---|---|')
    for (const e of tl.events) {
      out.push(`| ${e.year} | ${EFFECT_LABEL[e.effect] || e.effect} | ${e.paper_title || e.paper} |`)
    }
    out.push('', ':::', '')
  }

  if (p.related?.length) {
    out.push('## Related problems', '')
    out.push('::: {.related-links}')
    for (const r of p.related) {
      const t = REGISTRY_INDEX[r]
      if (t) out.push(`- [${r} — ${t.title}](${t.filename})`)
    }
    out.push(':::', '')
  }

  out.push('## Source', '')
  out.push(`Derived from ${p.source_refs.join(', ')} of the reviewed corpus.`, '')

  return out.join('\n')
}

function categoryPage(cat, problems) {
  const n = problems.length
  return `---
title: ${y(cat.name)}
subtitle: ${y(`${n} open problem${n === 1 ? '' : 's'}`)}
toc: false
listing:
  id: cat-${cat.slug}
  contents: "../problems/${cat.code}-*.qmd"
  type: table
  fields: [pid, title, priority, verdict, maturity, prank]
  field-display-names:
    pid: "ID"
    title: "Problem"
    priority: "Priority"
    verdict: "Verdict"
    maturity: "Maturity"
  field-types:
    prank: number
  field-links: [pid, title]
  sort: ["prank asc", "pid asc"]
  sort-ui: [pid, title, prank, verdict, maturity]
  filter-ui: [pid, title, priority, verdict, maturity]
  categories: false
  page-size: 100
  table-hover: true
---

${cat.blurb}

::: {#cat-${cat.slug}}
:::

[Back to the full catalog](../catalog.qmd)
`
}

// A problem's evidence read in publication order rather than pooled. The three
// things this shows and a count cannot: whether later work answered what earlier
// work left open, whether a gap kept being named after partial progress landed,
// and whether a gap has simply sat there being restated.
// The program page. Two things it must not do: imply the queue is a promise,
// and hide what was excluded. The exclusions are the more informative half,
// because "this problem cannot be settled by a simulation" is itself a finding
// about the problem, and a queue shown without them reads as though the other
// 226 entries were simply not got to yet.
function studiesPage(queue, index) {
  // index is keyed by problem, and one study appears under every problem it
  // bears on, so listing it directly would show the same study several times.
  const entries = Object.entries(index).filter(([, s]) => !s.secondary)
  const alsoOn = {}
  for (const [pid, s] of Object.entries(index)) {
    if (s.secondary) (alsoOn[s.primary_problem] ||= []).push(pid)
  }
  const done = entries.filter(([, s]) => s.status === 'complete')
  const active = entries.filter(([, s]) => s.status !== 'complete')
  const link = (id) => {
    const t = REGISTRY_INDEX[id]
    return t ? `[${id}](problems/${t.filename})` : id
  }

  const out = [`---
title: "Studies"
subtitle: ${y(`Closing the catalog, one problem a week`)}
toc: true
---

The catalog records what is open. This is the attempt to close some of it: one study a
week, each aimed at a single entry, taken in priority order.

Scope is population-adjusted indirect comparison only, meaning MAIC, STC, ML-NMR, ML-UMR
and NMI. Standard network meta-analysis is out of scope because it does not adjust for
population differences, which is where these problems live.

`, '']

  if (done.length) {
    out.push('## Completed', '')
    for (const [pid, s] of done) {
      out.push(`### ${link(pid)} — ${s.title}`, '')
      if (alsoOn[pid]?.length) {
        out.push(`Also bears on ${alsoOn[pid].map(link).join(', ')}.`, '')
      }
      out.push(`**Question.** ${s.question}`, '')
      out.push(`**Answer.** ${s.answer}`, '')
      out.push(`**What it does not answer.** ${s.not_answered}`, '')
      // Keys match FORMATS in build/studies/publish.py, where Markdown is 'gfm'.
  const dl = Object.entries({ pdf: 'PDF', gfm: 'Markdown', odt: 'OpenDocument' })
        .filter(([k]) => s.downloads?.[k])
        .map(([k, l]) => `[${l}](/${s.downloads[k]})`).join(' · ')
      if (dl) out.push(`Read it: ${dl}`, '')
    }
  } else {
    out.push('## Completed', '', 'None yet. The first study is under way.', '')
  }

  if (active.length) {
    out.push('## Under way', '')
    out.push('::: {.table-scroll}', '', '| Problem | Study | Status |', '|---|---|---|')
    for (const [pid, s] of active) {
      out.push(`| ${link(pid)} | ${s.title} | ${s.status} |`)
    }
    out.push('', ':::', '')
  }

  out.push(
    '## How a problem gets chosen', '',
    'Not every open problem can be settled by a study, and the difference is not cosmetic.',
    'A simulation can measure bias, coverage and error rates, and it can show how badly a',
    'known nonidentification bites at realistic sample sizes. It cannot establish that a',
    'package is missing, that clinicians misread a plot, that a field under-reports',
    'something, or that a quantity is unidentifiable in principle. Those need software, a',
    'case study, a meta-research corpus, or a proof.',
    '',
    `Every one of the ${Object.values(queue.excluded || {}).reduce((a, b) => a + b, 0) + (queue.queue?.length || 0)} catalog entries was judged on both questions separately,`,
    'by an external model, before the program started: is this a population-adjustment',
    'problem, and what kind of study would settle it. The queue below is the intersection.',
    '',
    '::: {.table-scroll}', '', '| Why an entry is not in the program | n |', '|---|---:|'
  )
  for (const [k, n] of Object.entries(queue.excluded || {}).sort((a, b) => b[1] - a[1])) {
    out.push(`| ${k} | ${n} |`)
  }
  out.push('', ':::', '')

  out.push(
    '## The queue', '',
    `${queue.queue?.length || 0} problems, in order. This is an ordering, not a schedule:`,
    'a study that turns out to answer two entries closes both, and a study whose design',
    'review finds it would answer a neighbouring question rather than the stated one gets',
    'sent back before it is run.',
    '',
    '::: {.table-scroll}', '',
    '| # | Problem | Methods | Study | Answers | Feasibility | Catalog priority |',
    '|---|---|---|---|---|---|---|'
  )
  for (const [i, r] of (queue.queue || []).entries()) {
    out.push(
      `| ${i + 1} | ${link(r.id)} ${r.title} | ${(r.methods || []).join(', ') || '—'} ` +
        `| ${r.study_type} | ${r.answerable} | ${r.feasibility ?? '—'}/5 | ${r.priority} |`
    )
  }
  out.push('', ':::', '')

  out.push(
    '## What each study has to do', '',
    'Simulation studies follow ADEMP: aims, data-generating mechanisms, estimands, methods,',
    'performance measures ([Morris, White and Crowther 2019](https://doi.org/10.1002/sim.8086)).',
    'Two rules follow from it and are enforced rather than encouraged.',
    '',
    'Every performance measure carries a Monte Carlo standard error.',
    ':   A bias of 0.02 is uninterpretable without knowing whether the Monte Carlo error is',
    '    0.001 or 0.03. The replicate count is derived in the protocol from a target Monte',
    '    Carlo standard error, not chosen because it is a round number.',
    '',
    'Failed replicates are results.',
    ':   A method that converges on 60% of replicates and is unbiased on those is not an',
    '    unbiased method. Convergence is reported for every method in every scenario.',
    '',
    'The protocol is committed before the run.',
    ':   It fixes the design and states in advance what result would count as showing the',
    '    problem is real and what would count as showing it is not. The commit that adds it',
    '    is the timestamp.',
    '',
    'Code, protocols and results are at',
    '[github.com/choxos/ITC-open-problems/tree/main/studies](https://github.com/choxos/TTE-open-problems/tree/main/studies).',
    ''
  )
  return out.join('\n')
}

function chronologyPage(tl, gaps) {
  const rows = tl.problems || []
  const link = (id) => {
    const t = REGISTRY_INDEX[id]
    return t ? `[${id}](problems/${t.filename})` : id
  }
  const PROGRESS = new Set(['resolves', 'partially-addresses'])
  const byClass = (k) => rows.filter((r) => r.class === k)
  const recurrent = rows.filter((r) => r.flags?.includes('recurrent'))
  const untouched = recurrent.filter((r) => !r.events.some((e) => PROGRESS.has(e.effect)))
  const verdicts = Object.values(TIMELINE_VERDICT)
  const vcount = (k) => verdicts.filter((v) => v.verdict === k).length

  const out = [`---
title: "The chronology of the evidence"
subtitle: "What the dates say that a count of findings cannot"
toc: true
---

Every finding in this catalog carries the publication year of the paper that made it,
so a problem's evidence can be read as a sequence rather than a pile. That answers three
questions a pooled count cannot: has later work answered what an earlier paper left open,
is a problem being closed in pieces by different groups, and is a problem simply being
restated across the years with nothing happening in between.

${rows.length} problems carry at least one dated finding, drawn from a full-text reading of
${gaps.gaps ? '687 papers' : 'the reviewed corpus'} published between 2010 and 2026.
`]

  if (verdicts.length) {
    out.push(`## Did the later work answer the earlier work?

${verdicts.length} problems had progress as their newest evidence and every assertion of
openness older. Publication order alone proves nothing there: two papers can straddle a date
and be about different questions, and a later paper can close a corner of a problem whose
earlier statement was about something else. Each was put to an independent reviewer with the
older and newer claims side by side, and without the classification, so it could not agree
with the mechanism by reading its label.

**None was fully answered.**

| The later work | Problems |
|---|---:|
| answers what the earlier work left open | ${vcount('answers')} |
| answers a component; a named part survives | ${vcount('answers-part')} |
| is about a different question | ${vcount('different-question')} |
| does not answer it | ${vcount('no')} |
| could not be judged from the claims | ${vcount('uncertain')} |

The five in the bottom two rows are where the dates mislead, and each is recorded on its own
page alongside the reviewer's reasoning.
`)
  }

  const reasserted = byClass('reasserted-after-progress')
  if (reasserted.length) {
    out.push(`## Reasserted after progress

${reasserted.length} problems have partial progress on the record and a later paper still
calling them open. These are the entries most likely to be reported as settled by someone
reading only the newest method paper, and the ones whose prior work should cite both sides.

::: {.table-scroll}

| Problem | Registry says | Papers | Span | Chronology |
|---|---|---:|---|---|`)
    for (const r of reasserted.sort((a, b) => b.papers - a.papers).slice(0, 30)) {
      out.push(`| ${link(r.id)} ${r.title} | ${VERDICT_LABEL[r.verdict] || r.verdict} | ${r.papers} | ${r.first} to ${r.last} | ${r.trail} |`)
    }
    out.push('', ':::', '')
  }

  if (untouched.length) {
    out.push(`## Restated across the years, with nothing in between

${untouched.length} problems were called open by at least three papers spanning at least
eight years, and no paper in the corpus reports any progress on them at all. Independent
restatement over a long period, by authors who mostly do not cite each other, is the
strongest evidence this reading can give that a gap is real rather than an artifact of one
author's framing.

::: {.table-scroll}

| Problem | Registry says | Papers | Span |
|---|---|---:|---|`)
    for (const r of untouched.sort((a, b) => b.papers - a.papers)) {
      out.push(`| ${link(r.id)} ${r.title} | ${VERDICT_LABEL[r.verdict] || r.verdict} | ${r.papers} | ${r.first} to ${r.last} |`)
    }
    out.push('', ':::', '')
  }

  const themes = (gaps.themes || []).filter((t) => t.papers >= 3 && t.span >= 8)
  if (themes.length) {
    const dry = themes.filter((t) => !t.progress_years.length)
    out.push(`## The same gap, named again and again

Papers name the gaps they leave behind, in their own words. Across the corpus the same gap
gets named repeatedly by authors who never cite each other, and that repetition is invisible
while the gaps sit as free text under the paper that wrote them. Clustering the text does not
find it, because a recurrence is a paraphrase rather than a near duplicate. So all
${gaps.gaps} future-research gaps were read and attached to a theme instead, and the
chronology falls out.

${themes.length} themes were named by three or more papers across eight or more years;
**${dry.length} of those have no paper in the corpus reporting any progress at all**.

The most-restated of them are not registered problems yet. They are candidates from this
reading, and they need the same scrutiny as any other entry before they become one.

::: {.table-scroll}

| Theme | Papers | Named in | Progress reported |
|---|---:|---|---|`)
    for (const t of themes.sort((a, b) => b.papers - a.papers).slice(0, 40)) {
      const yrs = t.years.slice(0, 12).join(', ') + (t.years.length > 12 ? '…' : '')
      out.push(`| ${link(t.theme)} ${t.title || ''} | ${t.papers} | ${yrs} | ${t.progress_years.join(', ') || 'none'} |`)
    }
    out.push('', ':::', '')
  }

  const years = Object.entries(tl.by_year || {}).sort((a, b) => Number(a[0]) - Number(b[0]))
  if (years.length) {
    out.push(`## Findings by publication year

What the corpus says about these problems, by the year it was said.

::: {.table-scroll}

| Year | Confirms open | Partly addresses | Resolves | Contradicts |
|---|---:|---:|---:|---:|`)
    for (const [y, c] of years) {
      out.push(`| ${y} | ${c['supports-open'] || 0} | ${c['partially-addresses'] || 0} | ${c.resolves || 0} | ${c.contradicts || 0} |`)
    }
    out.push('', ':::', '')
  }

  return out.join('\n')
}

let REGISTRY_INDEX = {}

function main() {
  if (!existsSync(REGISTRY)) {
    console.error(`No registry at ${REGISTRY}. Run the audit workflows first.`)
    process.exit(1)
  }
  const problems = JSON.parse(readFileSync(REGISTRY, 'utf8'))

  STUDIES = readJson(join(ROOT, 'studies/index.json'), {})

  const timeline = readJson(join(READING, 'timeline.json'), { problems: [], by_year: {} })
  const gapChron = readJson(join(READING, 'gap-chronology.json'), { themes: [] })
  TIMELINE = Object.fromEntries((timeline.problems || []).map((r) => [r.id, r]))
  for (const f of existsSync(join(READING, 'review'))
    ? readdirSync(join(READING, 'review')).filter((f) => /^verdict-timeline-\d+\.json$/.test(f))
    : []) {
    for (const v of readJson(join(READING, 'review', f), { verdicts: [] }).verdicts || []) {
      const id = v.item?.problem_id
      if (id) TIMELINE_VERDICT[id] = v
    }
  }

  // Filenames must start with the category code so the per-category listing glob works.
  REGISTRY_INDEX = Object.fromEntries(
    problems.map((p) => [p.id, { title: p.title, filename: `${p.id}-${slugify(p.title)}.qmd` }])
  )

  for (const dir of [PROBLEMS_DIR, CATEGORIES_DIR]) {
    if (existsSync(dir)) {
      for (const f of readdirSync(dir)) if (f.endsWith('.qmd')) rmSync(join(dir, f))
    } else {
      mkdirSync(dir, { recursive: true })
    }
  }

  for (const p of problems) {
    writeFileSync(join(PROBLEMS_DIR, REGISTRY_INDEX[p.id].filename), problemPage(p))
  }

  for (const cat of CATEGORIES) {
    const mine = problems.filter((p) => p.category === cat.code)
    writeFileSync(join(CATEGORIES_DIR, `${cat.slug}.qmd`), categoryPage(cat, mine))
  }

  const queue = readJson(join(ROOT, 'studies/queue.json'), { queue: [], excluded: {} })
  if (queue.queue?.length) {
    writeFileSync(join(ROOT, 'studies.qmd'), studiesPage(queue, STUDIES))
  }

  if (timeline.problems?.length) {
    writeFileSync(join(ROOT, 'chronology.qmd'), chronologyPage(timeline, gapChron))
  }

  // ---- references, from every citation that survived verification ----
  // Includes work the auditors themselves surfaced: an entry narrowed by a paper the source
  // never cited should carry that paper.
  const refs = new Map()
  for (const p of problems) {
    for (const w of p.prior_work || []) {
      const key = (w.doi_or_url || w.cite || '').trim()
      if (key && !refs.has(key)) {
        refs.set(key, {
          cite: w.cite,
          url: w.doi_or_url ? normalizeLocator(w.doi_or_url) : w.doi_or_url,
          from: 'source',
        })
      }
    }
    for (const o of p.audit?.opinions || []) {
      for (const w of o.resolving_work || []) {
        const key = (w.locator || '').trim()
        if (key && !refs.has(key)) {
          refs.set(key, { cite: w.title || w.locator, url: normalizeLocator(key), from: 'audit', year: w.year })
        }
      }
    }
  }
  const bib = ['% Generated by build/render_site.mjs from the audited registry. Do not edit.',
    `% ${refs.size} works: cited by the source material, or surfaced by the audit.`, '']
  let n = 0
  for (const [key, r] of refs) {
    n++
    bib.push(`@misc{ref${n},`,
      `  title = {${String(r.cite || key).replace(/[{}]/g, '')}},`,
      r.year ? `  year = {${r.year}},` : '  year = {},',
      `  note = {${r.from === 'audit' ? 'surfaced during verification' : 'cited by the source material'}},`,
      `  howpublished = {\\url{${r.url || key}}}`, '}', '')
  }
  writeFileSync(join(ROOT, 'references.bib'), bib.join('\n'))

  // ---- headline counts for the landing page ----
  const counts = {}
  for (const p of problems) counts[p.verdict] = (counts[p.verdict] || 0) + 1
  // Guarded: an empty registry is a legitimate state before the first audit
  // runs, and 0/0 would otherwise print "NaN%" into the landing page.
  const pct = (k) => (problems.length ? Math.round(((counts[k] || 0) / problems.length) * 100) : 0)
  // Emitted from the counts rather than typed into the prose. The sibling ITC
  // project hardcodes its own finding here, which then ships regardless of what
  // the table above it says.
  const partly = pct('partially-addressed')
  const closing = !problems.length
    ? 'The registry is empty. Entries appear here once the first audit has run.'
    : counts['partially-addressed']
      ? `${partly}% of the problems presented as open turn out to be partly addressed already, ` +
        'usually by work the source material does not cite. Those entries name what covers which part.'
      : 'No entry has yet been found to be partly addressed by work the source material does not cite.'
  const stats = `::: {.callout-note appearance="simple"}
## What the audit found

**${problems.length} problems** across ${CATEGORIES.length} categories, carrying
${problems.reduce((t, p) => t + (p.claims_to_check || []).length, 0)} individual claims that
were checked.

| Verdict | Entries | |
|---|---:|---:|
| [Confirmed open]{.verdict .verdict-confirmed-open} | ${counts['confirmed-open'] || 0} | ${pct('confirmed-open')}% |
| [Partially addressed]{.verdict .verdict-partially-addressed} | ${counts['partially-addressed'] || 0} | ${pct('partially-addressed')}% |
| [Overstated]{.verdict .verdict-overstated} | ${counts.overstated || 0} | ${pct('overstated')}% |
| [Unverifiable]{.verdict .verdict-unverifiable} | ${counts.unverifiable || 0} | ${pct('unverifiable')}% |
| [Not supported]{.verdict .verdict-not-supported} | ${counts['not-supported'] || 0} | ${pct('not-supported')}% |
| [Resolved since report]{.verdict .verdict-resolved-since-report} | ${counts['resolved-since-report'] || 0} | ${pct('resolved-since-report')}% |

${closing}
:::
`
  writeFileSync(join(ROOT, '_stats.md'), stats)

  console.log(`Rendered ${problems.length} problems across ${CATEGORIES.length} categories.`)
  console.log(`references.bib: ${refs.size} works`)
  console.log('Verdicts:', counts)
}

main()
