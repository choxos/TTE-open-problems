#!/usr/bin/env node
// Checks that each hand-written opinion is attached to the problem it is about.
//
// The opinions in documentation/audit/opinions/ are written by hand against problem ids. An id
// typed one position off attaches a whole assessment, with its citations, to the wrong entry,
// and nothing downstream notices: the schema is satisfied, the adjudication runs, and the page
// publishes reasoning about a different problem. Four opinions in the first literature pass
// were shifted exactly that way, because they were written against the intended ordering of a
// category rather than the ordering the id assignment produced.
//
// The check is deliberately crude. It compares the content words of an opinion against the
// titles of every entry and complains when some other entry is a clearly better match. That
// cannot prove an attachment correct; it catches the off-by-one, which is the failure that
// actually happened.
//
// Usage: node tools/check-opinion-alignment.mjs

import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OPINIONS = join(ROOT, 'documentation/audit/opinions')
const CANONICAL = join(ROOT, 'documentation/audit/canonical/problems.json')

const STOP = new Set(`the a an of for to in on with and or is are be that this it its no not can
does not from than then when where which what how any all more most some such these those`.split(/\s+/))
const toks = (s) => new Set((s || '').toLowerCase().match(/[a-z]+/g)?.filter((w) => w.length > 3 && !STOP.has(w)) || [])
const score = (a, b) => {
  if (!b.size) return 0
  let n = 0
  for (const t of a) if (b.has(t)) n++
  return n / b.size
}

// A margin rather than a bare comparison: titles in one category share vocabulary, so a small
// edge over the assigned entry is noise. Only a clear winner is worth reporting.
const MARGIN = 0.15

function main() {
  if (!existsSync(CANONICAL)) {
    console.log('No canonical registry yet. Nothing to align against.')
    return
  }
  const problems = JSON.parse(readFileSync(CANONICAL, 'utf8'))
  const titles = problems.map((p) => ({ id: p.id, t: toks(p.title) }))
  const byId = Object.fromEntries(problems.map((p) => [p.id, p]))

  const suspect = []
  let checked = 0
  for (const f of readdirSync(OPINIONS).filter((x) => x.endsWith('.json') && x !== 'records-with-opinions.json')) {
    const blob = JSON.parse(readFileSync(join(OPINIONS, f), 'utf8'))
    for (const o of blob.opinions || []) {
      const p = byId[o.problem_id]
      if (!p) { suspect.push(`${f}: ${o.problem_id} is not a problem id`); continue }
      checked++
      const w = toks(o.weakest_true_restatement || (o.rationale || '').slice(0, 500))
      const mine = score(w, toks(p.title))
      let best = null, bestScore = 0
      for (const t of titles) {
        const s = score(w, t.t)
        if (s > bestScore) { bestScore = s; best = t.id }
      }
      if (best && best !== o.problem_id && bestScore > mine + MARGIN) {
        suspect.push(`${f}: ${o.problem_id} (${mine.toFixed(2)}) reads like ${best} (${bestScore.toFixed(2)})\n` +
          `    attached to: ${p.title}\n` +
          `    better fit:  ${byId[best].title}`)
      }
    }
  }

  console.log(`Checked ${checked} opinions against ${problems.length} problem titles.`)
  if (!suspect.length) { console.log('No opinion reads like it belongs to a different entry.'); return }
  console.log(`\n${suspect.length} to look at:`)
  for (const s of suspect) console.log(`  ${s}`)
  // Advisory: a legitimately cross-cutting opinion can read like a neighbour, so this reports
  // rather than fails. It runs before the audit, where a human is already reading the output.
}

main()
