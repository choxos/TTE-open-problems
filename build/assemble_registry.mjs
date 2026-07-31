#!/usr/bin/env node
// Combines the per-category merge outputs into one registry, and turns the free-text
// related_hint strings into resolved cross-links.
//
// The merge agents worked one category at a time, so they could name a related problem in
// another category but not know its id. Resolution happens here, once every id exists.
//
// Input   documentation/audit/canonical/<GROUP>.json
// Output  documentation/audit/canonical/problems.json

import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DIR = join(ROOT, 'documentation/audit/canonical')
const OUT = join(DIR, 'problems.json')

const STOP = new Set(`a an the and or of for to in on with without that this these those is are be
may can could should would must not no non problem problems open remain remains method methods
effect effects treatment treatments population populations study studies trial trials data model
models estimate estimates estimation estimand estimands
tte target emulation emulations emulated emulate emulating causal inference observational rwd rwe`
  .split(/\s+/))

const tokens = (s) =>
  new Set((s || '').toLowerCase().match(/[a-z0-9]+/g)?.filter((w) => w.length > 2 && !STOP.has(w)) || [])

const overlap = (a, b) => {
  if (!a.size || !b.size) return 0
  let n = 0
  for (const t of a) if (b.has(t)) n++
  return n / Math.min(a.size, b.size)
}

function main() {
  const files = readdirSync(DIR).filter((f) => f.endsWith('.json') && f !== 'problems.json')
  const problems = []
  for (const f of files) {
    const blob = JSON.parse(readFileSync(join(DIR, f), 'utf8'))
    for (const p of blob.problems || []) {
      p._group = blob.group
      problems.push(p)
    }
  }

  const ids = new Set()
  const dupes = []
  for (const p of problems) {
    if (ids.has(p.id)) dupes.push(p.id)
    ids.add(p.id)
  }
  if (dupes.length) {
    console.error(`Duplicate ids across groups: ${[...new Set(dupes)].join(', ')}`)
    process.exit(1)
  }

  // Resolve related_hint titles against the full id space. A hint is free text written by an
  // agent that could not see other categories, so match on token overlap rather than equality.
  const titleTokens = problems.map((p) => ({ id: p.id, toks: tokens(p.title) }))
  let resolved = 0
  let unresolved = 0

  for (const p of problems) {
    const hits = new Set()
    for (const hint of p.related_hint || []) {
      const h = tokens(hint)
      let best = null
      let bestScore = 0
      for (const t of titleTokens) {
        if (t.id === p.id) continue
        const s = overlap(h, t.toks)
        if (s > bestScore) { bestScore = s; best = t.id }
      }
      if (best && bestScore >= 0.6) { hits.add(best); resolved++ } else { unresolved++ }
    }
    p.related = [...hits].sort()
    delete p.related_hint
  }

  // Make cross-links symmetric. A one-way link is almost always an oversight at this scale,
  // and a reader arriving from either side should see the other.
  const byId = Object.fromEntries(problems.map((p) => [p.id, p]))
  let added = 0
  for (const p of problems) {
    for (const r of p.related) {
      const t = byId[r]
      if (t && !t.related.includes(p.id)) { t.related.push(p.id); added++ }
    }
  }
  for (const p of problems) p.related.sort()

  problems.sort((a, b) => a.id.localeCompare(b.id))
  writeFileSync(OUT, JSON.stringify(problems, null, 1))

  const byCat = {}
  for (const p of problems) byCat[p.category] = (byCat[p.category] || 0) + 1
  const unsourced = problems.filter((p) => p.source_unsourced).length
  const implSpecific = problems.filter((p) => p.implementation_specific).length
  const claims = problems.reduce((n, p) => n + (p.claims_to_check || []).length, 0)
  const withCites = problems.filter((p) => (p.prior_work || []).length).length

  console.log(`${problems.length} canonical problems from ${files.length} groups -> ${OUT}`)
  console.log(`  ${claims} claims to check`)
  console.log(`  ${withCites} entries carry at least one citation`)
  console.log(`  ${unsourced} derive partly from the unsourced document`)
  console.log(`  ${implSpecific} are implementation-specific`)
  console.log(`  cross-links: ${resolved} hints resolved, ${unresolved} unmatched, ${added} added for symmetry`)
  console.log('\nper category:')
  for (const [k, v] of Object.entries(byCat).sort((a, b) => b[1] - a[1])) console.log(`  ${k}  ${v}`)
}

main()
