#!/usr/bin/env node
// Applies audited title corrections to the registry.
//
// Titles are the catalog's primary browse surface, so a title asserting something the
// entry's own audit disproved is a real defect, not a cosmetic one. The old title is kept
// on the record so the change stays visible.

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const REGISTRY = join(ROOT, 'documentation/audit/registry/problems.json')
const CORRECTIONS = join(ROOT, 'documentation/audit/title-corrections.json')

if (!existsSync(CORRECTIONS)) {
  console.error('No title-corrections.json yet.')
  process.exit(1)
}

const problems = JSON.parse(readFileSync(REGISTRY, 'utf8'))
const byId = Object.fromEntries(problems.map((p) => [p.id, p]))
const { corrections } = JSON.parse(readFileSync(CORRECTIONS, 'utf8'))

let n = 0
const missing = []
for (const c of corrections) {
  const p = byId[c.id]
  if (!p) { missing.push(c.id); continue }
  if (!c.new_title || c.new_title === p.title) continue
  p.original_title = p.title
  p.title_correction = c.why
  p.title = c.new_title
  n++
}

writeFileSync(REGISTRY, JSON.stringify(problems, null, 1))
console.log(`Corrected ${n} of ${problems.length} titles.`)
if (missing.length) console.log(`  ${missing.length} unknown ids: ${missing.slice(0, 5).join(' ')}`)
