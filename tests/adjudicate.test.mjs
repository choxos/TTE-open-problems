import { adjudicate } from '../build/adjudicate.mjs'

const mk = (id, opinions) => ({ id, audit: { opinions } })
const cases = [
  { name: 'CMP-07 already fixed in code (2 corroborating solved votes)',
    rec: mk('CMP-07', [
      { auditor: 'codex', status_vote: 'solved', support_vote: 'supported',
        resolving_work: [{ locator: 'choxos/cpaic@9d150e9', what_it_resolves: 'README states rank is sufficient but not necessary' }],
        rationale: 'README.md contradicts the claim.' },
      { auditor: 'literature', status_vote: 'solved', support_vote: 'supported',
        resolving_work: [{ locator: 'choxos/cpaic@9d150e9' }], rationale: 'same' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'no new literature' },
    ]),
    expect: 'resolved-since-report' },

  { name: 'CMP-12 still open (negative control)',
    rec: mk('CMP-12', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'R/effects.R negates the phrase' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no resolving work' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'nothing since' },
    ]),
    expect: 'confirmed-open' },

  { name: 'unsubstantiated solved vote must be downgraded, not counted',
    rec: mk('X-01', [
      { auditor: 'grok', status_vote: 'solved', support_vote: 'supported', rationale: 'I believe this is solved' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
    ]),
    expect: 'confirmed-open' },

  { name: 'QBA near-empty claim: two overstated votes',
    rec: mk('QBA-01', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'overstated',
        weakest_true_restatement: 'No unified framework exists; the literature is thin, not empty.', rationale: 'x' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'overstated', rationale: 'y' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'z' },
    ]),
    expect: 'overstated' },

  { name: 'CMP-01 split verdict: open, but framing caveated by one substantiated flag',
    rec: mk('CMP-01', [
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'overstated',
        weakest_true_restatement: 'Only the rank-deficient part is untestable.', rationale: 'redundancy permits testing' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
    ]),
    expect: 'confirmed-open' },

  { name: 'solo solved vote from the inverted-prior auditor -> contested, not closed',
    rec: mk('Y-01', [
      { auditor: 'solved-hunter', status_vote: 'solved', support_vote: 'supported',
        resolving_work: [{ locator: '10.1111/rssa.12579', what_it_resolves: 'ML-NMR does this' }], rationale: 'found it' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
    ]),
    expect: 'unverifiable' },
]

let pass = 0
for (const c of cases) {
  const r = adjudicate(c.rec)
  const ok = r.verdict === c.expect
  pass += ok
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.name}`)
  if (!ok) console.log(`      got '${r.verdict}', expected '${c.expect}'  path=${r.audit.adjudication.decision_path.join(' ')}`)
  else console.log(`      -> ${r.verdict}   [${r.audit.adjudication.decision_path.join(' ')}]`)
}
console.log(`\n${pass}/${cases.length} passed`)
process.exit(pass === cases.length ? 0 : 1)
