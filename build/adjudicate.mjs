#!/usr/bin/env node
// Turns auditor opinions into a published verdict, by a fixed rule.
//
// The rule is deliberately mechanical and its decision path is recorded on every record,
// so "why does this say partially-addressed?" is answerable from the artifact without
// re-running anything.
//
// Two principles drive the design:
//   1. A "solved" vote without a locator is not evidence. It is downgraded, not counted.
//   2. Evidence beats votes. A lone dissenter holding an unrebutted verbatim quote is not
//      silently outvoted by three auditors holding opinions.
//
// Usage: node build/adjudicate.mjs

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const AUDIT = join(ROOT, 'documentation/audit')

export const RULE_VERSION = 'adjudicate.v3'

// Auditors whose votes are counted. The refuter is excluded on purpose: it sees the others'
// opinions, so counting it would double-count whatever it was persuaded by.
//
// This list must name the auditors that actually run. The sibling ITC project declares a
// 'solved-hunter' that never casts an opinion, which leaves the corroboration guard on R1
// permanently inert and lets R2 fire on any solitary solved vote.
export const INDEPENDENT = ['literature', 'codex', 'grok', 'glm']

// Auditors told to assume the problem is already solved and go find who solved it. Their prior
// is inverted by construction, so a solved vote from one of them needs corroboration from an
// auditor that was not primed that way before it can close a problem on its own.
const INVERTED_PRIOR = ['grok']

const hasLocator = (w) => w && typeof w.locator === 'string' && w.locator.trim().length > 3

// Coverage is uneven: external models run out of quota mid-run, so one entry may be reached by
// four auditors and the next by two. A bare ">= 2" therefore means "half" on one entry and "a
// quarter" on another. Every majority test is taken over the auditors that actually returned a
// non-abstaining vote ON THAT AXIS FOR THAT ENTRY, and the denominator is recorded in the
// decision path so the strength of a verdict is visible rather than implied.
export const majorityOf = (n, voters) => n >= 2 && n * 2 >= voters.length

export function adjudicate(record) {
  const path = []
  const dissent = []

  // Pre-pass: an unsubstantiated "solved" claim is an opinion, not a finding.
  const cleaned = (record.audit?.opinions || []).map((o) => {
    const claimsSolved = o.status_vote === 'solved' || o.status_vote === 'partially-solved'
    const substantiated = Array.isArray(o.resolving_work) && o.resolving_work.some(hasLocator)
    if (claimsSolved && !substantiated) {
      path.push(`R0:downgrade-unsubstantiated-solved:${o.auditor}`)
      return { ...o, status_vote: 'open', _downgraded: true }
    }
    return o
  })

  const indep = cleaned.filter((o) => INDEPENDENT.includes(o.auditor))
  const refuter = cleaned.find((o) => o.auditor === 'refuter') || null

  // ---- Axis A: is it still open? ----
  const statusVoters = indep.filter((o) => o.status_vote && o.status_vote !== 'abstain')
  const sD = statusVoters.length
  const solved = indep.filter((o) => o.status_vote === 'solved')
  const partial = indep.filter((o) => o.status_vote === 'partially-solved')
  const notAProblem = indep.filter((o) => o.status_vote === 'not-a-problem')
  const solvedCorroborating = solved.filter((o) => !INVERTED_PRIOR.includes(o.auditor))

  let status
  if (solved.length >= 2 && solvedCorroborating.length >= 1 && majorityOf(solved.length, statusVoters)) {
    status = 'solved'
    path.push(`R1:solved-corroborated(n=${solved.length}/${sD})`)
  } else if (solved.length >= 1) {
    // Either a lone solved vote, or a solved bloc that did not reach a majority of the auditors
    // that actually voted. Both are contests, not closures.
    status = 'contested'
    path.push(`R2:solitary-or-minority-solved-claim(n=${solved.length}/${sD})`)
  } else if (partial.length >= 1) {
    // Deliberately a single-vote trigger. R0 has already downgraded any partially-solved vote
    // that arrived without a locator, so what survives here is substantiated.
    status = 'partially-solved'
    path.push(`R3:partially-solved(n=${partial.length}/${sD})`)
  } else if (majorityOf(notAProblem.length, statusVoters)) {
    status = 'not-a-problem'
    path.push(`R4:not-a-problem(n=${notAProblem.length}/${sD})`)
  } else {
    status = 'open'
    path.push('R5:default-open')
  }

  // ---- Axis B: is the claim, as stated, faithful and proportionate? ----
  const counters = indep.filter((o) => (o.counter_evidence || []).length > 0)
  const supporters = indep.filter((o) => o.support_vote === 'supported')
  const over = indep.filter((o) => o.support_vote === 'overstated')
  const misattr = indep.filter((o) => o.support_vote === 'misattributed')
  const unver = indep.filter((o) => o.support_vote === 'unverifiable')
  const caveated = indep.filter((o) => o.support_vote === 'supported-with-caveat')
  const supportVoters = indep.filter((o) => o.support_vote && o.support_vote !== 'abstain')
  const pD = supportVoters.length

  let support
  if (misattr.length >= 1 && counters.length >= 1 && supporters.length === 0) {
    support = 'misattributed'
    path.push('R6:counter-quote-uncontested')
  } else if (counters.length >= 1 && supporters.length >= counters.length) {
    // A contest needs two sides. The ported rule fired on any counter-quote as long as one
    // auditor voted plainly 'supported', which made a single affirming vote holding no evidence
    // enough to neutralize two auditors holding quotes. That contradicts this rule's own second
    // principle, that evidence beats votes, and it matters in practice: on the first run of this
    // registry, ten of thirteen 'unverifiable' verdicts rested on one affirming vote, eight of
    // them from the single most permissive auditor. Requiring the affirming side not to be
    // outnumbered leaves a genuine disagreement contested and lets an outnumbered affirmation
    // fall through to the overstatement rules below, where the evidence is weighed rather than
    // cancelled.
    support = 'contested'
    path.push(`R7:counter-and-support-both-present(support=${supporters.length}/counter=${counters.length})`)
  } else if (majorityOf(over.length, supportVoters)) {
    support = 'overstated'
    path.push(`R8:overstated-majority(n=${over.length}/${pD})`)
  } else if (over.length >= 1 && over.some((o) => o.weakest_true_restatement)) {
    // An overstatement flag that comes with a concrete weaker restatement is evidence, not
    // merely a vote, so it is not outvoted by auditors who simply agreed with the claim. This
    // is the case where one auditor read more carefully than the others. It also catches an
    // overstated bloc that failed the majority test above: a minority that did the reading
    // still qualifies the claim rather than being discarded.
    support = 'supported-with-caveat'
    const flagged = over.filter((o) => o.weakest_true_restatement).map((o) => o.auditor)
    path.push(`R9:substantiated-overstatement(n=${over.length}/${pD}):${flagged.join('+')}`)
  } else if (majorityOf(unver.length, supportVoters) && supporters.length === 0 && caveated.length === 0) {
    support = 'unverifiable'
    path.push(`R10:no-accessible-source(n=${unver.length}/${pD})`)
  } else if (caveated.length >= supporters.length && caveated.length >= 1) {
    // The most common outcome by far: the problem is real and the framing needs qualifying.
    // Treating a caveat as equivalent to plain support would erase the qualification, which
    // is usually the most useful thing the audit produced.
    support = 'supported-with-caveat'
    path.push(`R11:caveated(n=${caveated.length})`)
  } else if (supporters.length >= 1) {
    support = 'supported'
    path.push('R12:supported')
  } else if (unver.length >= 1) {
    support = 'unverifiable'
    path.push('R13:unverifiable')
  } else {
    support = 'unverifiable'
    path.push('R16:no-opinion-reached-support')
  }

  // The refuter holds a veto that can only downgrade, and can only force a contest with
  // a quote. Argument alone constrains tone, not verdict.
  if (refuter) {
    if (refuter.support_vote === 'misattributed' && (refuter.counter_evidence || []).length > 0) {
      if (support === 'supported') support = 'contested'
      path.push('R14:refuter-counter-quote-forces-contested')
    } else if (support === 'supported' &&
               ['supported-with-caveat', 'overstated', 'contested'].includes(refuter.support_vote)) {
      support = 'supported-with-caveat'
      path.push('R15:refuter-veto-downgrade')
    }
  }

  // Evidence beats votes. A dissenter who brought a locator or a quote, and whom nobody
  // rebutted, escalates instead of being outvoted.
  for (const o of cleaned) {
    const broughtEvidence =
      (o.counter_evidence || []).length > 0 || (o.resolving_work || []).some(hasLocator)
    const disagrees =
      (o.status_vote !== status && o.status_vote !== 'abstain') ||
      (o.support_vote !== support && o.support_vote !== 'abstain')
    if (!broughtEvidence || !disagrees) continue

    // An auditor rebuts by writing the literal token REBUT:<auditor> in its rationale.
    // Machine-readable on purpose: it is how a dissent gets marked addressed.
    const rebuttedBy = cleaned
      .filter((p) => p.auditor !== o.auditor && String(p.rationale || '').includes(`REBUT:${o.auditor}`))
      .map((p) => p.auditor)

    dissent.push({
      auditor: o.auditor,
      axis: o.status_vote !== status ? 'status' : 'support',
      verdict: o.status_vote !== status ? o.status_vote : o.support_vote,
      evidence: [...(o.counter_evidence || []), ...(o.resolving_work || [])],
      rationale: o.rationale,
      addressed_by: rebuttedBy.length ? rebuttedBy.join(',') : null,
    })
  }

  const unaddressed = dissent.filter((d) => d.addressed_by === null)
  const needsHuman =
    status === 'contested' || support === 'contested' ||
    support === 'misattributed' || unaddressed.length > 0

  // Collapse the two axes into the single verdict the site publishes.
  //
  // The published verdict answers "is this problem open?", so STATUS leads. The support axis
  // governs how the entry is worded, and only overrides the verdict when the claim is so far
  // off that publishing it as open would mislead. A problem that is genuinely open but whose
  // framing needed qualifying is still CONFIRMED OPEN: the qualification belongs in the text
  // and the trail, not in a badge that implies someone has partly solved it.
  // `misattributed` deliberately does NOT appear here. It means the source cited the wrong
  // paper for a claim, which is a fault in the provenance and not in the claim: the problem
  // can be entirely real and still be credited to the wrong authors. Letting it set
  // `not-supported` published four entries as unsubstantiated whose own auditors had every
  // one of them voted open or partly solved, which is the opposite of what the trail said.
  // A misattribution belongs in the wording and the trail, and it already sets `needsHuman`.
  let verdict
  if (status === 'solved') verdict = 'resolved-since-report'
  else if (status === 'not-a-problem') verdict = 'not-supported'
  else if (support === 'unverifiable') verdict = 'unverifiable'
  else if (support === 'contested' || status === 'contested') verdict = 'unverifiable'
  else if (support === 'overstated') verdict = 'overstated'
  else if (status === 'partially-solved') verdict = 'partially-addressed'
  else verdict = 'confirmed-open'

  const rationale =
    verdict === 'resolved-since-report'
      ? `Closed by later work: ${solved.flatMap((o) => (o.resolving_work || []).map((w) => w.locator)).join(', ')}.`
      : verdict === 'overstated'
        ? `${over.length} independent auditors judged the claim as stated too strong. ${over[0]?.weakest_true_restatement || ''}`
        : verdict === 'partially-addressed'
          ? 'Part of this problem is addressed by existing work; the entry names which part.'
          : verdict === 'unverifiable'
            ? 'Auditors disagreed and the disagreement was evidence-bearing on both sides.'
            : verdict === 'not-supported'
              // Only reachable via status `not-a-problem` now. The old wording,
              // "no accessible source substantiates the claim", described a
              // misattribution rather than this, and was the giveaway that the
              // two axes had been collapsed into one.
              ? 'Auditors judged this is not a real methodological problem.'
              : 'Auditors agreed the problem is open and no counterevidence surfaced.'

  return {
    ...record,
    verdict,
    verdict_rationale: rationale,
    audit: {
      ...record.audit,
      adjudication: {
        rule_version: RULE_VERSION,
        status,
        support,
        decision_path: path,
        status_tally: tally(cleaned, 'status_vote'),
        support_tally: tally(cleaned, 'support_vote'),
        dissent,
        human_review_required: needsHuman,
      },
      dissent: unaddressed.length
        ? unaddressed
            .map((d) => `${d.auditor} dissented (${d.verdict}): ${d.rationale}`)
            .join(' ')
        : dissent.length
          ? dissent.map((d) => `${d.auditor} dissented (${d.verdict}), rebutted by ${d.addressed_by}: ${d.rationale}`).join(' ')
          : undefined,
    },
  }
}

const tally = (ops, key) =>
  ops.reduce((acc, o) => ({ ...acc, [o[key]]: (acc[o[key]] || 0) + 1 }), {})

function main() {
  const src = join(AUDIT, 'opinions/records-with-opinions.json')
  if (!existsSync(src)) {
    console.error(`No opinion set at ${src}. Run the verification workflows first.`)
    process.exit(1)
  }
  const records = JSON.parse(readFileSync(src, 'utf8'))
  const out = records.map(adjudicate)

  writeFileSync(join(AUDIT, 'registry/problems.json'), JSON.stringify(out, null, 1))

  const counts = {}
  for (const r of out) counts[r.verdict] = (counts[r.verdict] || 0) + 1
  const human = out.filter((r) => r.audit.adjudication.human_review_required)
  writeFileSync(join(AUDIT, 'registry/human-queue.json'), JSON.stringify(human, null, 1))

  console.log(`Adjudicated ${out.length} problems under ${RULE_VERSION}`)
  console.log('Verdicts:', counts)
  console.log(`Needing human review: ${human.length} -> registry/human-queue.json`)
}

if (import.meta.url === `file://${process.argv[1]}`) main()
