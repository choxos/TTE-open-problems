// Asserts the known-answer cases in documentation/audit/calibration.json.
//
// The sibling ITC project's README says its calibration cases "are asserted before the site is
// built". No script there asserts them, so a miscalibrated audit would have shipped silently.
// This is that script.
//
// Two independent things are checked, because a fixture can rot in two different ways:
//
//   1. GROUND TRUTH. Where a fixture names a file and quotes it, the quote must still be in the
//      file. This is what tells you the package moved rather than the auditor being wrong. It
//      runs whether or not the registry has entries, so it is useful from day one.
//   2. VERDICT. Where an entry in the registry carries the fixture's claim, its adjudicated
//      verdict must equal the fixture's expected verdict.
//
// Exits non-zero on any failure.

import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const CAL = join(ROOT, 'documentation/audit/calibration.json')
const REGISTRY = join(ROOT, 'documentation/audit/registry/problems.json')

// Quotes are compared on letters and digits only. A quote copied out of a source file picks up
// whatever line breaks and spacing the layout demanded, and an exact substring test fails on
// text that is in fact verbatim.
const fold = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, '')

// The longest run of plain prose inside the ground-truth string, which is what is actually
// expected to appear in the file. Fixture text often wraps the quote in a locator.
const quotedSpan = (s) => {
  const quoted = [...(s || '').matchAll(/[“"']([^“”"']{20,})[”"']/g)].map((m) => m[1])
  return quoted.length ? quoted.sort((a, b) => b.length - a.length)[0] : null
}

function main() {
  if (!existsSync(CAL)) {
    console.error(`No calibration file at ${CAL}.`)
    process.exit(1)
  }
  const cal = JSON.parse(readFileSync(CAL, 'utf8'))
  const fixtures = cal.fixtures || []
  if (!fixtures.length) {
    console.error('Calibration file has no fixtures.')
    process.exit(1)
  }

  const problems = existsSync(REGISTRY) ? JSON.parse(readFileSync(REGISTRY, 'utf8')) : []
  const failures = []
  const skipped = []
  let truthChecked = 0
  let verdictChecked = 0

  for (const f of fixtures) {
    const tag = `${f.ref} (${f.type})`

    // ---- 1. ground truth still says what the fixture says it says ----
    if (f.ground_truth_file) {
      const p = join(ROOT, f.ground_truth_file)
      if (!existsSync(p)) {
        // The pinned package trees and guidance PDFs live under documentation/refs/, which is
        // not committed: they run to gigabytes and are reproducible from the pins recorded in
        // this file. So a missing ground-truth file means "not vendored on this machine", which
        // is the normal state in CI, and not "the fixture is broken". Skipped loudly rather
        // than silently, because a run where nothing was checkable must not read as a pass.
        skipped.push(`${tag}: ${f.ground_truth_file} not vendored here`)
      } else if (!/\.(pdf|png|jpg)$/i.test(p)) {
        const span = quotedSpan(f.ground_truth)
        if (span) {
          truthChecked++
          if (!fold(readFileSync(p, 'utf8')).includes(fold(span))) {
            failures.push(
              `${tag}: the quoted ground truth is no longer in ${f.ground_truth_file}. ` +
              'The pinned source moved, so the fixture is stale rather than the audit being wrong.')
          }
        }
      }
    }

    // ---- 2. any registry entry carrying this claim has the expected verdict ----
    const target = fold(f.claim)
    for (const p of problems) {
      const carries = (p.claims_to_check || []).some((c) => {
        const c1 = fold(typeof c === 'string' ? c : c.claim)
        return c1 && (c1 === target || c1.includes(target) || target.includes(c1))
      })
      if (!carries) continue
      verdictChecked++
      if (p.verdict !== f.expected_verdict) {
        failures.push(
          `${tag}: entry ${p.id} carries this claim with verdict '${p.verdict}', ` +
          `but a calibrated audit must return '${f.expected_verdict}'.`)
      }
    }
  }

  console.log(`${fixtures.length} fixtures: ${truthChecked} ground-truth quotes checked, ` +
              `${verdictChecked} registry verdicts checked.`)
  if (skipped.length) {
    console.log(`${skipped.length} ground-truth check(s) skipped:`)
    for (const s of skipped) console.log(`  - ${s}`)
    console.log('  Run `bash build/vendor_packages.sh` to fetch the pinned sources and check these.')
  }
  if (!problems.length) {
    console.log('Registry is empty, so only ground truth was checkable. That is expected before ' +
                'the first audit runs.')
  }
  if (failures.length) {
    console.error(`\n${failures.length} calibration failure(s):`)
    for (const f of failures) console.error(`  - ${f}`)
    process.exit(1)
  }
  console.log('Calibration OK.')
}

main()
