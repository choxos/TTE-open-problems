#!/usr/bin/env node
// Makes `related` reciprocal in the canonical registry.
//
// `related` is editorial metadata and it lives in canonical/problems.json, because
// adjudicate.mjs rebuilds registry/problems.json from canonical on every run. Anything
// written only into the registry is therefore erased the next time the auditors are
// collected, which is exactly what happened to the back-links that uncovered.py --apply
// had added: they survived one render and vanished on the next adjudication.
//
// A one-way link is not fatal, and check-registry.mjs says so, but it is invisible in the
// direction that matters. An entry added late points at its neighbors; the neighbors, which
// are the pages a reader is far more likely to arrive on first, point back at nothing.
//
// Idempotent by construction, so it is safe to run before every adjudication.
//
// Usage: node build/symmetrize_related.mjs [--dry-run]

import { readFileSync, writeFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CANONICAL = join(ROOT, 'documentation/audit/canonical/problems.json')
const DRY = process.argv.includes('--dry-run')

const problems = JSON.parse(readFileSync(CANONICAL, 'utf8'))
const byId = Object.fromEntries(problems.map((p) => [p.id, p]))

const added = []
const dangling = []
for (const p of problems) {
  // A link to an id the registry does not have is a different fault and reciprocating it
  // would invent a page. Report and drop it from consideration rather than mirroring it.
  for (const r of p.related || []) {
    if (!byId[r] || r === p.id) { dangling.push(`${p.id} -> ${r}`); continue }
    const target = byId[r]
    target.related ||= []
    if (!target.related.includes(p.id)) {
      target.related.push(p.id)
      added.push(`${r} -> ${p.id}`)
    }
  }
}
for (const p of problems) {
  if (p.related) p.related = [...new Set(p.related)].filter((r) => byId[r] && r !== p.id).sort()
}

if (!DRY) writeFileSync(CANONICAL, JSON.stringify(problems, null, 1))

console.log(`${added.length} back-link(s) ${DRY ? 'would be' : ''} added across ${problems.length} entries`)
for (const a of added) console.log(`  + ${a}`)
if (dangling.length) {
  console.log(`\n${dangling.length} link(s) point at no entry and were dropped:`)
  for (const d of dangling) console.log(`  ! ${d}`)
}
