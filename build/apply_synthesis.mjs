#!/usr/bin/env node
// Applies the audited rewrites to the registry.
//
// The synthesis pass rewrote each entry to the claim that survived audit. This merges those
// rewrites onto the adjudicated records, keeping the original statement and the correction
// note so the change is visible on the page rather than silent.
//
// Idempotent: re-running with the same synthesis output produces the same registry, and
// original_statement is only ever set from a statement that has not already been rewritten.
//
// Usage: node build/apply_synthesis.mjs

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const AUDIT = join(ROOT, 'documentation/audit')
const REGISTRY = join(AUDIT, 'registry/problems.json')
const SYNTH = join(AUDIT, 'synthesis')

function main() {
  if (!existsSync(SYNTH)) {
    console.error(`No synthesis output at ${SYNTH}.`)
    process.exit(1)
  }
  const problems = JSON.parse(readFileSync(REGISTRY, 'utf8'))
  const byId = Object.fromEntries(problems.map((p) => [p.id, p]))

  let applied = 0
  let corrected = 0
  let refsAdded = 0
  const missing = []
  const cats = []

  for (const f of readdirSync(SYNTH).filter((x) => x.endsWith('.json'))) {
    let blob
    try {
      blob = JSON.parse(readFileSync(join(SYNTH, f), 'utf8'))
    } catch {
      console.error(`  unparseable: ${f}`)
      continue
    }
    cats.push(blob.category)
    for (const s of blob.problems || []) {
      const p = byId[s.id]
      if (!p) { missing.push(s.id); continue }

      // Capture the original only once, and only when the rewrite actually differs.
      if (s.original_statement && !p.original_statement && s.statement !== p.statement) {
        p.original_statement = s.original_statement
        corrected++
      }
      if (s.correction_note) p.correction_note = s.correction_note

      if (s.statement) p.statement = s.statement
      if (s.why_open) p.why_open = s.why_open
      if (s.proposed_direction) p.proposed_direction = s.proposed_direction

      if (Array.isArray(s.prior_work) && s.prior_work.length) {
        const before = (p.prior_work || []).length
        const seen = new Set()
        p.prior_work = s.prior_work.filter((w) => {
          const k = (w.doi_or_url || w.cite || '').trim().toLowerCase()
          if (!k || seen.has(k)) return false
          seen.add(k)
          return true
        })
        refsAdded += Math.max(0, p.prior_work.length - before)
      }
      applied++
    }
  }

  writeFileSync(REGISTRY, JSON.stringify(problems, null, 1))

  const withOriginal = problems.filter((p) => p.original_statement).length
  console.log(`Applied rewrites to ${applied} entries from ${cats.length} categories: ${cats.sort().join(' ')}`)
  console.log(`  ${corrected} statements materially corrected this run (${withOriginal} carry an original overall)`)
  console.log(`  ${refsAdded} references added from auditor findings`)
  if (missing.length) console.log(`  ${missing.length} synthesis records had no matching id: ${missing.slice(0, 6).join(' ')}`)

  const notRewritten = problems.filter((p) => !cats.includes(p.category))
  if (notRewritten.length) {
    const byCat = {}
    for (const p of notRewritten) byCat[p.category] = (byCat[p.category] || 0) + 1
    console.log(`  ${notRewritten.length} entries still carry source text, pending synthesis: ${Object.entries(byCat).map(([k, v]) => `${k}(${v})`).join(' ')}`)
  }
}

main()
