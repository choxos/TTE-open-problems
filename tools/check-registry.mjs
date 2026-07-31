#!/usr/bin/env node
// Validates the generated problem pages before a render.
//
// Quarto's own `field-required` is unreliable for custom listing fields in 1.8.26
// (it rejects a field that demonstrably renders), so the invariants live here
// instead. This also catches the things Quarto structurally cannot: ID uniqueness,
// cross-link symmetry, and enum membership.
//
// Usage: node tools/check-registry.mjs

import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { CATEGORIES } from '../build/render_site.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const PROBLEMS = join(ROOT, 'problems')

// Imported rather than restated: render_site.mjs writes the filename from the id
// and the category page globs by code, so a code that exists in one list and not
// the other is a page that renders and cannot be reached.
const BY_CODE = Object.fromEntries(CATEGORIES.map((c) => [c.code, c]))
const ID_PATTERN = new RegExp(`^(${Object.keys(BY_CODE).join('|')})-\\d{2}$`)

const ENUMS = {
  priority: ['Very high', 'High', 'Medium-high', 'Medium'],
  verdict: [
    'Confirmed open', 'Partially addressed', 'Overstated',
    'Resolved since report', 'Not supported', 'Unverifiable',
  ],
  maturity: ['Established', 'Promising', 'Emerging', 'Speculative'],
}

const REQUIRED = ['title', 'description', 'pid', 'topic', 'priority', 'prank', 'verdict', 'maturity']

// Minimal front-matter reader: the generator emits one `key: value` per line with
// quoted scalars, so a full YAML parser would be a dependency for no gain.
function frontMatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/)
  if (!m) return null
  const out = {}
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^([A-Za-z][\w-]*):\s*(.*)$/)
    if (!kv) continue
    let v = kv[2].trim()
    if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1).replace(/\\"/g, '"')
    out[kv[1]] = v
  }
  return out
}

function main() {
  // An absent problems/ and an empty problems/ are the same state, because git does not track
  // an empty directory: a fresh clone of a repository whose registry is still empty has no
  // problems/ at all. Both are handled together below.
  const files = existsSync(PROBLEMS)
    ? readdirSync(PROBLEMS).filter((f) => f.endsWith('.qmd'))
    : []
  if (!files.length) {
    // An empty registry is the state before the first audit has run, and the
    // site is expected to build and deploy in that state. Only treat it as a
    // failure when the registry itself has entries, which means render_site.mjs
    // did not run or wrote nothing.
    const registry = join(ROOT, 'documentation/audit/registry/problems.json')
    const n = existsSync(registry) ? JSON.parse(readFileSync(registry, 'utf8')).length : 0
    if (n) {
      console.error(`No problem pages found, but the registry holds ${n} entries. Run build/render_site.mjs.`)
      process.exit(1)
    }
    console.log('No problem pages yet, and the registry is empty. Nothing to validate.')
    process.exit(0)
  }

  const errors = []
  const byId = new Map()
  const related = new Map()

  for (const f of files) {
    const text = readFileSync(join(PROBLEMS, f), 'utf8')
    const fm = frontMatter(text)
    const where = `problems/${f}`

    if (!fm) {
      errors.push(`${where}: no front matter`)
      continue
    }

    for (const k of REQUIRED) {
      if (!fm[k]) errors.push(`${where}: missing required field '${k}'`)
    }

    for (const [field, allowed] of Object.entries(ENUMS)) {
      if (fm[field] && !allowed.includes(fm[field])) {
        errors.push(`${where}: ${field} '${fm[field]}' is not one of ${allowed.join(' | ')}`)
      }
    }

    // The rank column exists so sorting is numeric; if it disagrees with the label,
    // the table sorts in an order that contradicts what it displays.
    const expectedRank = ENUMS.priority.indexOf(fm.priority) + 1
    if (fm.priority && Number(fm.prank) !== expectedRank) {
      errors.push(`${where}: prank ${fm.prank} disagrees with priority '${fm.priority}' (expected ${expectedRank})`)
    }

    if (fm.pid) {
      if (byId.has(fm.pid)) errors.push(`${where}: duplicate id '${fm.pid}', also in ${byId.get(fm.pid)}`)
      byId.set(fm.pid, where)
      if (!f.startsWith(`${fm.pid}-`)) {
        errors.push(`${where}: filename does not start with its id '${fm.pid}'`)
      }
      // The id prefix is not decoration. render_site.mjs writes the filename from
      // the id and each category page globs `../problems/<CODE>-*.qmd`, so an id
      // whose prefix disagrees with the page's category still renders a page and
      // still vanishes from the listing that should reach it: present, but
      // unfindable, and nothing else in the pipeline notices.
      if (!ID_PATTERN.test(fm.pid)) {
        errors.push(`${where}: id '${fm.pid}' does not match <CODE>-NN for a known category code`)
      } else {
        const expected = BY_CODE[fm.pid.split('-')[0]].name
        if (fm.topic && fm.topic !== expected) {
          errors.push(`${where}: id '${fm.pid}' belongs to '${expected}' but the page is filed under '${fm.topic}'`)
        }
      }
    }

    // A statement that leaks display math into the listing table renders as raw TeX.
    if (fm.description && /\$\$|\\\[/.test(fm.description)) {
      errors.push(`${where}: description contains display math, which does not render in the listing table`)
    }

    const links = [...text.matchAll(/\]\(([A-Z]{3}-\d+)-[^)]*\.qmd\)/g)].map((m) => m[1])
    if (links.length) related.set(fm.pid, links)
  }

  // Dangling and asymmetric cross-links. Asymmetry is not fatal, but at this scale
  // one-way links are almost always an oversight rather than a decision.
  const asymmetric = []
  for (const [id, targets] of related) {
    for (const t of targets) {
      if (!byId.has(t)) errors.push(`${byId.get(id)}: links to '${t}', which does not exist`)
      else if (!(related.get(t) || []).includes(id)) asymmetric.push(`${id} -> ${t}`)
    }
  }

  console.log(`Checked ${files.length} problem pages, ${byId.size} unique ids.`)
  if (asymmetric.length) {
    console.log(`\n${asymmetric.length} one-way cross-links (not fatal):`)
    for (const a of asymmetric.slice(0, 12)) console.log(`  ${a}`)
    if (asymmetric.length > 12) console.log(`  ... and ${asymmetric.length - 12} more`)
  }
  if (errors.length) {
    console.error(`\n${errors.length} error${errors.length === 1 ? '' : 's'}:`)
    for (const e of errors) console.error(`  ${e}`)
    process.exit(1)
  }
  console.log('\nRegistry is valid.')
}

main()
