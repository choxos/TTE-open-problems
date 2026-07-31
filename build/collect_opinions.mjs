#!/usr/bin/env node
// Gathers every auditor's opinions onto the canonical problem records.
//
// Three auditors write in three different shapes:
//   - the Claude verifier writes {auditor, category, opinions:[...]} directly
//   - codex writes the schema object directly, via its --output-schema / -o path
//   - grok wraps the result: the clean object is under `structuredOutput`, while `text`
//     holds a transcript that can contain several partial emissions before the real one
//
// Output: documentation/audit/opinions/records-with-opinions.json, which is what
// build/adjudicate.mjs consumes.

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const AUDIT = join(ROOT, 'documentation/audit')
const REGISTRY = join(AUDIT, 'canonical/problems.json')
const OPINIONS = join(AUDIT, 'opinions')
const OUT = join(OPINIONS, 'records-with-opinions.json')

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

// Grok output needs a forgiving reader. A run can concatenate several whole JSON documents
// at top level as it revises, and the clean object may sit under `structuredOutput` or at the
// root. Scan the raw text for every parseable object and keep whichever carries the most
// opinions; the early emissions are usually empty placeholders.
function unwrapGrok(raw) {
  if (typeof raw !== 'string') return null
  let best = null
  for (let i = 0; i < raw.length; i++) {
    if (raw[i] !== '{') continue
    for (let end = raw.length; end > i; end--) {
      if (raw[end - 1] !== '}') continue
      try {
        const o = JSON.parse(raw.slice(i, end))
        const ops = o?.structuredOutput?.opinions || o?.opinions
        if (Array.isArray(ops) && (!best || ops.length > best.opinions.length)) {
          best = { opinions: ops }
        }
        break
      } catch { /* shrink the candidate and retry */ }
    }
  }
  return best
}

function collect(dir, auditor, unwrap) {
  const out = []
  if (!existsSync(dir)) return { out, files: 0, failed: [] }
  const files = readdirSync(dir).filter((f) => f.endsWith('.json'))
  const failed = []
  for (const f of files) {
    const blob = readJson(join(dir, f))
    const parsed = unwrap ? unwrap(blob) : blob
    if (!parsed?.opinions?.length) {
      failed.push(f)
      continue
    }
    for (const o of parsed.opinions) out.push({ ...o, auditor })
  }
  return { out, files: files.length, failed }
}

function main() {
  const problems = JSON.parse(readFileSync(REGISTRY, 'utf8'))
  const byId = Object.fromEntries(problems.map((p) => [p.id, p]))

  const sources = [
    { dir: OPINIONS, auditor: 'literature', unwrap: null, skip: ['records-with-opinions.json'] },
    { dir: join(AUDIT, 'auditors/codex/out'), auditor: 'codex', unwrap: null },
    { dir: join(AUDIT, 'auditors/grok/out'), auditor: 'grok', unwrap: unwrapGrok },
  ]

  const perAuditor = {}
  const orphans = new Set()

  for (const s of sources) {
    let files = 0
    const failed = []
    const opinions = []
    if (existsSync(s.dir)) {
      for (const f of readdirSync(s.dir).filter((x) => x.endsWith('.json'))) {
        if (s.skip?.includes(f)) continue
        files++
        const parsed = s.unwrap
          ? s.unwrap(readFileSync(join(s.dir, f), 'utf8'))
          : readJson(join(s.dir, f))
        if (!parsed?.opinions?.length) { failed.push(f); continue }
        for (const o of parsed.opinions) opinions.push({ ...o, auditor: s.auditor })
      }
    }
    for (const o of opinions) {
      const p = byId[o.problem_id]
      if (!p) { orphans.add(o.problem_id); continue }
      p.audit ||= { opinions: [] }
      p.audit.opinions.push(o)
    }
    perAuditor[s.auditor] = { files, opinions: opinions.length, failed }
  }

  const coverage = {}
  for (const p of problems) {
    const n = p.audit?.opinions?.length || 0
    coverage[n] = (coverage[n] || 0) + 1
  }

  writeFileSync(OUT, JSON.stringify(problems, null, 1))

  console.log(`${problems.length} problems -> ${OUT}\n`)
  for (const [a, s] of Object.entries(perAuditor)) {
    console.log(`  ${a.padEnd(11)} ${String(s.files).padStart(3)} files, ${String(s.opinions).padStart(4)} opinions` +
      (s.failed.length ? `, ${s.failed.length} unparseable: ${s.failed.slice(0, 4).join(' ')}` : ''))
  }
  console.log('\n  opinions per problem:')
  for (const [n, count] of Object.entries(coverage).sort((a, b) => a[0] - b[0])) {
    console.log(`    ${n} auditor${n === '1' ? '' : 's'}: ${count} problems${n === '0' ? '  <- these cannot be adjudicated' : ''}`)
  }
  if (orphans.size) {
    console.log(`\n  ${orphans.size} opinions referenced unknown problem ids: ${[...orphans].slice(0, 8).join(' ')}`)
  }
}

main()
