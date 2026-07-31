// Golden cases for the adjudication rule. Every one of these is a decision shape the rule has
// to keep producing; if a rule edit changes one of them, that change is a deliberate act and the
// RULE_VERSION goes up with it.
import { adjudicate, majorityOf, INDEPENDENT, RULE_VERSION } from '../build/adjudicate.mjs'

const mk = (id, opinions) => ({ id, audit: { opinions } })
const L = (loc) => [{ locator: loc, what_it_resolves: 'x' }]

const cases = [
  // ---- the six decision shapes carried over from the source project ----
  { name: 'two corroborating substantiated solved votes close a problem',
    rec: mk('SFW-07', [
      { auditor: 'codex', status_vote: 'solved', support_vote: 'supported',
        resolving_work: L('cran:TrialEmulation@0.0.4.11'), rationale: 'NAMESPACE exports it.' },
      { auditor: 'literature', status_vote: 'solved', support_vote: 'supported',
        resolving_work: L('cran:TrialEmulation@0.0.4.11'), rationale: 'same' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'no new literature' },
    ]),
    expect: 'resolved-since-report' },

  { name: 'unanimous open with no counterevidence stays open (negative control)',
    rec: mk('TZO-02', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'the sentence negates the phrase it contains' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no resolving work' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'nothing since' },
    ]),
    expect: 'confirmed-open' },

  // The refuter is a dormant hook: no refuting auditor runs in this configuration, and
  // INDEPENDENT does not name one, so nothing about the published verdicts depends on it. It is
  // tested anyway. A branch that is retained and never exercised is how the sibling project
  // ended up declaring an auditor that casts no opinions, and the point of keeping the hook is
  // that it will work if a refuter is ever added rather than that it exists.
  { name: 'R15: a refuter veto downgrades supported, and cannot do more than downgrade',
    rec: mk('REF-01', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'nothing since' },
      { auditor: 'refuter', status_vote: 'not-a-problem', support_vote: 'overstated',
        rationale: 'the strong form does not hold' },
    ]),
    // The verdict label does not move: the veto acts on the support axis only, and the status
    // axis is untouched, so a refuter cannot reopen or close anything on its own. That is the
    // property being pinned, and the path token is what proves the veto fired at all.
    expect: 'confirmed-open', pathIncludes: 'R15:refuter-veto-downgrade' },

  { name: 'R14: a refuter counter-quote forces a contest rather than a downgrade',
    rec: mk('REF-02', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'refuter', status_vote: 'open', support_vote: 'misattributed',
        counter_evidence: [{ locator: '10.1000/x', quote: 'the cited work says the opposite' }],
        rationale: 'the citation does not support the claim' },
    ]),
    expect: 'unverifiable', pathIncludes: 'R14:refuter-counter-quote-forces-contested' },

  { name: 'R0: a solved vote with no locator is downgraded, not counted',
    rec: mk('X-01', [
      { auditor: 'grok', status_vote: 'solved', support_vote: 'supported', rationale: 'I believe this is solved' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
    ]),
    expect: 'confirmed-open' },

  { name: 'R8: an overstated majority carries',
    rec: mk('UCF-01', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'overstated',
        weakest_true_restatement: 'The literature is thin, not empty.', rationale: 'x' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'overstated', rationale: 'y' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'z' },
    ]),
    expect: 'overstated' },

  { name: 'R9: one careful reader with a weaker restatement caveats rather than overturns',
    rec: mk('STR-01', [
      { auditor: 'grok', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'overstated',
        weakest_true_restatement: 'Only the deterministic-strategy part is unidentified.', rationale: 'reads more carefully' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
      { auditor: 'glm', status_vote: 'open', support_vote: 'supported', rationale: 'holds' },
    ]),
    expect: 'confirmed-open' },

  { name: 'R2: a solitary solved vote from the inverted-prior auditor contests, it does not close',
    rec: mk('BEN-03', [
      { auditor: 'grok', status_vote: 'solved', support_vote: 'supported',
        resolving_work: L('10.1001/jama.2023.4221'), rationale: 'found it' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'glm', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
    ]),
    expect: 'unverifiable' },

  // ---- cases pinning the v2 changes ----
  { name: 'v2: an opinion from an auditor not on the roster is ignored entirely',
    rec: mk('Z-01', [
      // 'solved-hunter' is declared in the source project but never votes there. If one ever
      // appears here it must not be able to close a problem on its own.
      { auditor: 'solved-hunter', status_vote: 'solved', support_vote: 'supported',
        resolving_work: L('10.1000/fake'), rationale: 'phantom auditor' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
    ]),
    expect: 'confirmed-open' },

  { name: 'v2: the inverted-prior auditor cannot corroborate itself into a closure',
    rec: mk('Z-02', [
      { auditor: 'grok', status_vote: 'solved', support_vote: 'supported',
        resolving_work: L('10.1000/a'), rationale: 'a' },
      { auditor: 'glm', status_vote: 'solved', support_vote: 'supported',
        resolving_work: L('10.1000/b'), rationale: 'b' },
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
      { auditor: 'literature', status_vote: 'open', support_vote: 'supported', rationale: 'no' },
    ]),
    // glm is not inverted-prior, so it corroborates: 2 of 4 solved is exactly half and carries.
    expect: 'resolved-since-report' },

  { name: 'v2: uneven coverage is recorded in the decision path',
    rec: mk('Z-03', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'supported', rationale: 'only auditor that reached this entry' },
    ]),
    expect: 'confirmed-open',
    pathIncludes: 'R5:default-open' },

  { name: 'v2: an abstention is not a vote and does not pad the denominator',
    rec: mk('Z-04', [
      { auditor: 'codex', status_vote: 'open', support_vote: 'overstated',
        weakest_true_restatement: 'narrower', rationale: 'x' },
      { auditor: 'grok', status_vote: 'open', support_vote: 'overstated', rationale: 'y' },
      { auditor: 'literature', status_vote: 'abstain', support_vote: 'abstain', rationale: 'could not reach sources' },
      { auditor: 'glm', status_vote: 'abstain', support_vote: 'abstain', rationale: 'could not reach sources' },
    ]),
    // 2 of the 2 auditors that actually voted called it overstated.
    expect: 'overstated',
    pathIncludes: 'R8:overstated-majority(n=2/2)' },
]

let pass = 0, fail = 0
console.log(`rule: ${RULE_VERSION}   roster: ${INDEPENDENT.join(', ')}\n`)
for (const c of cases) {
  const r = adjudicate(c.rec)
  const p = r.audit.adjudication.decision_path
  let ok = r.verdict === c.expect
  if (ok && c.pathIncludes) ok = p.some((s) => s === c.pathIncludes || s.startsWith(c.pathIncludes))
  ok ? pass++ : fail++
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.name}`)
  if (!ok) console.log(`      got '${r.verdict}', expected '${c.expect}'  path=${p.join(' ')}`)
  else console.log(`      -> ${r.verdict}   [${p.join(' ')}]`)
}

// ---- the majority helper, tested directly ----
// With a four-auditor roster two votes is always at least half, so the denominator only starts
// rejecting blocs once a fifth auditor votes. It is tested here rather than through adjudicate()
// so the guard is pinned before the roster grows and not after.
const M = [
  [2, 2, true,  'two of two'],
  [2, 3, true,  'two of three'],
  [2, 4, true,  'two of four is exactly half'],
  [2, 5, false, 'two of five is a minority and must not carry'],
  [3, 5, true,  'three of five'],
  [1, 1, false, 'a single vote is never a majority'],
  [1, 2, false, 'one of two'],
  [3, 6, true,  'three of six is exactly half'],
]
console.log('\nmajorityOf:')
for (const [n, d, want, label] of M) {
  const got = majorityOf(n, { length: d })
  const ok = got === want
  ok ? pass++ : fail++
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label} -> ${got}`)
}

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
