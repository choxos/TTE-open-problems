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
// Every quoted span, not the longest one. A ground truth that quotes six exported symbols is
// asserting all six; verifying only the longest lets the other five be deleted from the pinned
// source without the fixture noticing.
const quotedSpans = (s) =>
  [...(s || '').matchAll(/[“"']([^“”"']{20,})[”"']/g)].map((m) => m[1])

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
  const uninstantiated = []

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
      } else if (/\.(pdf|png|jpg)$/i.test(p)) {
        // Binary ground truth cannot be grepped from here. Named rather than passed over, so
        // the count of checked quotes is never mistaken for the count of fixtures with a file.
        skipped.push(`${tag}: ${f.ground_truth_file} is binary and cannot be checked textually`)
      } else {
        const spans = quotedSpans(f.ground_truth)
        if (spans.length) {
          const body = fold(readFileSync(p, 'utf8'))
          for (const span of spans) {
            truthChecked++
            if (!body.includes(fold(span))) {
              failures.push(
                `${tag}: the quoted ground truth "${span}" is no longer in ${f.ground_truth_file}. ` +
                'The pinned source moved, so the fixture is stale rather than the audit being wrong.')
            }
          }
        } else if (f.ground_truth_check === 'seed-citations-resolved') {
          // A negative claim cannot be checked by finding a string, since finding it would mean
          // the opposite of what the fixture asserts. This one is structural, so it is evaluated
          // as structure: every source reference must carry an identifier and none may be left
          // at the confidence value that marks an unresolved work.
          truthChecked++
          const seed = JSON.parse(readFileSync(p, 'utf8'))
          const entries = Object.values(seed)
          const unresolved = entries.filter((e) => e?.confidence === 'none')
          const idless = entries.filter((e) => !(e?.doi || e?.arxiv || e?.url || e?.pmid))
          if (unresolved.length || idless.length) {
            failures.push(
              `${tag}: ${unresolved.length} source reference(s) still marked unresolved and ` +
              `${idless.length} carry no identifier, so a claim resting only on one of them ` +
              'could ship as if it had been read.')
          }
        } else {
          // The file is here and readable and still nothing was verified, because the ground
          // truth was written as a summary rather than as a quotation. That is the failure mode
          // this whole file exists to prevent, so it is reported rather than skipped in silence.
          skipped.push(
            `${tag}: ground truth for ${f.ground_truth_file} carries no quoted span of 20 ` +
            'characters or more, so nothing was verified against the file')
        }
      }
    }

    // ---- 2. any registry entry carrying this claim has the expected verdict ----
    // Two shapes again. An entry decomposed into atomic claims is matched through
    // claims_to_check; an entry assessed whole is matched against its statement, and against
    // the statement it had before the audit rewrote it, since a fixture describes a claim the
    // source made rather than the one that survived. Matching only the first shape is how a
    // calibration check ends up passing while testing nothing.
    const target = fold(f.claim)
    let instances = 0
    for (const p of problems) {
      const fields = [
        ...(p.claims_to_check || []).map((c) => (typeof c === 'string' ? c : c.claim)),
        p.statement,
        p.original_statement,
      ]
      const carries = fields.some((c) => {
        const c1 = fold(c)
        return c1 && (c1 === target || c1.includes(target) || target.includes(c1))
      })
      if (!carries) continue
      instances++
      verdictChecked++
      if (p.verdict !== f.expected_verdict) {
        failures.push(
          `${tag}: entry ${p.id} carries this claim with verdict '${p.verdict}', ` +
          `but a calibrated audit must return '${f.expected_verdict}'.`)
      }
    }
    // A fixture with no instance in the registry has tested nothing. That is a legitimate
    // state, since a fixture describes a claim that may or may not have been made, and it must
    // be visible rather than absorbed into a total that looks like a pass.
    if (!instances) uninstantiated.push(tag)
  }

  console.log(`${fixtures.length} fixtures: ${truthChecked} ground-truth quotes checked, ` +
              `${verdictChecked} registry verdicts checked.`)
  if (uninstantiated.length) {
    console.log(`${uninstantiated.length} fixture${uninstantiated.length === 1 ? '' : 's'} ` +
                `matched no registry entry and therefore tested no verdict: ` +
                `${uninstantiated.join(', ')}.`)
    // These fixtures are known-answer controls for the auditors, not claims the catalog makes.
    // Every one of them uninstantiated is the expected and desirable state: it says none of
    // these wrong claims reached the registry. It is stated because a line reading "0 verdicts
    // checked" next to "Calibration OK" otherwise looks like a harness that does nothing.
    if (uninstantiated.length === fixtures.length) {
      console.log('  No fixture claim appears in the registry, which is the intended state: ' +
                  'these are controls for the auditors rather than claims the catalog makes. ' +
                  'The verdict axis bites only if one of them is ever asserted as an entry.')
    }
  }
  if (skipped.length) {
    console.log(`${skipped.length} ground-truth check(s) skipped:`)
    for (const s of skipped) console.log(`  - ${s}`)
    if (skipped.some((s) => s.includes('not vendored here'))) {
      console.log('  Run `bash build/vendor_packages.sh` to fetch the pinned sources and check these.')
    }
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
