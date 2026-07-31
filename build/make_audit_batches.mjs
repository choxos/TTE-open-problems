#!/usr/bin/env node
// Turns the canonical registry into batched prompt files for the two external auditors.
//
// The auditors are slow (minutes per call), so problems are batched. Batches are grouped
// by category: a batch of related problems shares context, and one failed call loses six
// verdicts rather than the run.
//
// Usage: node build/make_audit_batches.mjs [--size 6]

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const AUDIT = join(ROOT, 'documentation/audit')
const CANONICAL = join(AUDIT, 'canonical/problems.json')

const sizeArg = process.argv.indexOf('--size')
const BATCH_SIZE = sizeArg > -1 ? Number(process.argv[sizeArg + 1]) : 6

const CODEX_HEADER = `ROLE
You are a senior methodological statistician auditing an AI-generated research agenda on
indirect treatment comparisons (ITC), population-adjusted indirect comparisons (PAIC),
component PAIC, and quantitative bias analysis. It is about to be published as a public
website under a named researcher's byline. You have read-only filesystem access rooted at
/Users/choxos/Documents/GitHub. You have no web access.

Do not use sub-agents. Do not load skills. Work directly.

YOUR LENS, and only this lens:
  (1) TECHNICAL CORRECTNESS. Is the statistical or mathematical claim right on its own
      terms, independent of whether anyone has published it? Non-collapsibility,
      identification, rank and row-space arguments, estimand definitions, weighting theory,
      numerical integration.
  (2) SOURCE-CODE GROUND TRUTH. For any claim about the R package 'cpaic', read
      /Users/choxos/Documents/GitHub/cpaic and decide from the code, not from the report,
      whether the claim currently holds. HEAD is 9d150e9 (2026-07-25).

Do NOT assess novelty or literature coverage. You have no web access and another auditor
covers it. Existence of every cited paper is already confirmed; do not re-check it.

CALIBRATION. These three are established by hand. Match this standard of proof, and if your
method cannot reproduce all three, your method is wrong.

  A. STALE. The report says cpaic "uses netmeta for frequentist CNMA, maicplus for
     weighting, and cmdstanr for Bayesian models". cpaic/DESCRIPTION says the Stan models
     are "fitted with 'rstan' by default, or with 'cmdstanr' on request". cmdstanr is
     optional, not the engine. Correct verdict: support_vote "overstated".

  B. ALREADY FIXED. The report says cpaic documentation "may imply full rank is necessary".
     cpaic/README.md says "Full column rank of X is sufficient but *not necessary*, so a
     rank-deficient network can still identify useful cross-sub-network contrasts."
     Correct verdict: status_vote "solved", with the README line as resolving_work.

  C. STILL OPEN, the negative control. The report says cML-NMR lacks a marginal
     standardized effect path. cpaic/R/effects.R documents the return as "the conditional
     contrast at the covariate profile x, not the marginal effect standardized over a
     population with a distribution of covariates". Note the sentence NEGATES the phrase it
     contains: a keyword match flips this to "solved". Correct verdict: status_vote "open",
     support_vote "supported".

WHAT TO HUNT
  * FABRICATED CAPABILITY. Does every R function the report names actually exist in
    cpaic/NAMESPACE, and does it do what the report says?
  * OVERSTATED IMPOSSIBILITY. Claims of the form "no method exists", "untestable",
    "cannot be validated", "no goodness-of-fit statistic can". Is the claim literally true,
    or true only for a stated class? Give the precise condition under which it holds, and
    the weakest restatement that is still true.
  * MATHEMATICAL SLOPPINESS. Check estimand algebra and any bias decomposition.
  * SEVERITY INFLATION. Which items are genuinely critical for a decision-grade analysis,
    and which are roadmap items?

For each problem below, judge the listed claims_to_check. Report one opinion per problem.
Emit ONLY JSON matching the supplied output schema.
`

const GROK_HEADER = `ROLE
You are a literature-recency auditor for a research agenda on indirect treatment
comparisons (ITC), population-adjusted indirect comparisons (PAIC), component PAIC, and
quantitative bias analysis. The agenda is dated 25 July 2026 and is about to be published
as a public website. Use web search aggressively; it is the reason you were called.

YOUR LENS, and only this lens:
RECENCY AND PRIOR ART. For each problem, answer one question: does anything in the
literature or in released software mean this problem is not open, or not open as stated?
You are the auditor whose value is knowing what the author could plausibly have missed.

Do NOT re-verify that cited papers exist. All 64 DOIs, both arXiv preprints, all PubMed IDs
and all CRAN versions in this corpus are already confirmed. Do NOT critique statistical
correctness; another auditor with source access covers that. Duplicating either is wasted.

ADOPT AN INVERTED PRIOR: assume each problem has already been solved, and go find who
solved it. An agenda that lists a solved problem as open is the most damaging error this
site can make, because the people most likely to read it are the people who solved it.

SEARCH, in priority order:
  1. The problem's OWN cited works, listed under prior_work below. A deep-research report
     routinely cites the very paper that resolves the gap it is describing. Check these
     first; this is the highest-yield search you will run.
  2. Research Synthesis Methods, Statistics in Medicine, Biometrical Journal, Medical
     Decision Making, BMC Medical Research Methodology, Journal of Clinical Epidemiology,
     Value in Health, Pharmaceutical Statistics, 2024 to 2026 including online-first.
  3. arXiv stat.ME / stat.AP and medRxiv.
  4. R package activity: CRAN release notes and GitHub merged PRs for multinma, maicplus,
     netmeta, drMAIC, outstandR, gemtc, MBNMAdose, crossnma, survSens. A merged PR that
     closes a gap the report calls open is a finding.
  5. NICE DSU, EUnetHTA, ISPOR, ICH guidance issued or revised in 2025 to 2026.

DISCIPLINE, so you do not manufacture false positives:
  * A paper that PROPOSES a method has not SOLVED the problem. Proposal without evaluation
    is "open".
  * A paper that FORMALIZES or proves an impossibility STRENGTHENS the claim that the
    problem is open. It does not resolve it.
  * A method for the anchored case does not solve the unanchored case; a method for binary
    outcomes does not solve survival. Name which case is covered.
  * A structurally untestable assumption cannot be solved by any paper. Sensitivity
    analysis quantifies the consequences of an assumption failing; it does not identify the
    effect. Do not credit a sensitivity-analysis paper with solving an identification
    problem.
  * NO INVENTED CITATIONS. Every locator must be one you actually retrieved. If unsure a
    DOI is real, omit it and describe the work in prose. A fabricated DOI inside an audit
    of fabrication risk destroys the credibility of this whole exercise.
  * If you searched and found nothing, vote "open" with confidence at or below 0.6 and say
    which queries you ran. That is a useful, honest result.

Any solved or partially-solved vote REQUIRES resolving_work with a real locator. A vote
without it is discarded downstream and you will have contributed nothing.

For each problem below, judge the listed claims_to_check. Report one opinion per problem.
Emit ONLY JSON matching the supplied output schema.
`

function renderProblem(p) {
  const prior = (p.prior_work || [])
    .map((w) => `    - ${w.cite}${w.doi_or_url ? ` (${w.doi_or_url})` : ''}: ${w.what_it_does}`)
    .join('\n')
  const claims = (p.claims_to_check || []).map((c, i) => `    C${i + 1}. ${c}`).join('\n')
  return `
--------------------------------------------------------------------------------
PROBLEM ${p.id}: ${p.title}
CATEGORY: ${p.category}
REPORT PRIORITY (as asserted, treat as weak evidence): ${p.priority}

STATEMENT
${p.statement}

WHY THE REPORT SAYS IT IS OPEN
${p.why_open}

WORKS THE REPORT CITES
${prior || '    (none cited)'}

DIRECTION THE REPORT PROPOSES
${p.proposed_direction}

CLAIMS TO JUDGE
${claims || '    (none extracted)'}
`
}

function main() {
  if (!existsSync(CANONICAL)) {
    console.error(`No canonical registry at ${CANONICAL}. Run extraction and merge first.`)
    process.exit(1)
  }
  const problems = JSON.parse(readFileSync(CANONICAL, 'utf8'))

  // Group by category so a batch shares context, then chunk.
  const byCat = {}
  for (const p of problems) (byCat[p.category] ||= []).push(p)

  const batches = []
  for (const [cat, list] of Object.entries(byCat)) {
    for (let i = 0; i < list.length; i += BATCH_SIZE) {
      batches.push({ id: `${cat}-${String(i / BATCH_SIZE + 1).padStart(2, '0')}`, problems: list.slice(i, i + BATCH_SIZE) })
    }
  }

  for (const auditor of ['codex', 'grok']) {
    const dir = join(AUDIT, 'auditors', auditor, 'prompts')
    mkdirSync(dir, { recursive: true })
    mkdirSync(join(AUDIT, 'auditors', auditor, 'out'), { recursive: true })
    const header = auditor === 'codex' ? CODEX_HEADER : GROK_HEADER
    for (const b of batches) {
      const body = b.problems.map(renderProblem).join('\n')
      writeFileSync(
        join(dir, `${b.id}.txt`),
        `${header}\nBATCH_ID: ${b.id}\nPROBLEMS IN THIS BATCH: ${b.problems.length}\n${body}\n`
      )
    }
  }

  console.log(`${problems.length} problems -> ${batches.length} batches of <=${BATCH_SIZE}, x2 auditors = ${batches.length * 2} CLI calls`)
  console.log('Batches:', batches.map((b) => `${b.id}(${b.problems.length})`).join(' '))
}

main()
