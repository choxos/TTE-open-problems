#!/usr/bin/env python3
"""Get a simulation-study design from an external model.

The design pass sends the catalog entry in full, including its prior work and
its own proposed direction, and asks for an ADEMP protocol. It produces
something plausible, and plausible is not the same as sound: a simulation study
is uniquely vulnerable to answering a neighbouring question, because the
data-generating mechanism is chosen by whoever wants a particular conclusion and
nothing in the output announces it. A critique pass exists for that and is not
run by `--all`, which exists to get a first design on every queued problem
rather than to finish any of them.

Every citation either model produces is unverified. Both have been observed
inventing plausible attributions in this repository. Nothing a design cites goes
into a catalog entry without going through build/lit/check_citations.py first.

Usage:
  python3 build/studies/design.py --problems TZO-01 --slug TZO-01-grace-period
  python3 build/studies/design.py --all --parallel 4
  python3 build/studies/design.py --critique --slug TZO-01-grace-period
"""

import argparse
import glob
import re
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REGISTRY = os.path.join(ROOT, "documentation", "audit", "registry", "problems.json")
OUT = os.path.join(ROOT, "documentation", "studies", "designs")

MODEL = "gpt-5.6-sol"
EFFORT = "max"

ENVIRONMENT = """
## What the study will be run in

R 4.6.0 on a laptop, 8 cores, 6 usable workers. Installed and current, verified
by loading them: TrialEmulation 0.0.4.11, gfoRmula 1.1.1, gfoRmulaICE 1.1.1,
ltmle 1.3.0, tmle 2.1.1, WeightIt 1.7.0, MatchIt 4.7.2, cobalt 4.6.3, ipw 1.3.0,
riskRegression 2026.3.11, adjustedCurves 0.11.4, simsurv 1.0.1, survival 3.8.9,
data.table 1.18.4, ggplot2 4.0.3, boot, mvtnorm, dplyr, future, furrr.

`lmtp`, `concrete` and `CICI` are NOT installed and should not be assumed; name
them only if they are genuinely necessary, and say so explicitly if you do.
There is no Stan and no cmdstanr.

A seeded, resumable, parallel replicate harness already exists at
studies/_shared/R/harness.R, as do ADEMP performance measures with Monte Carlo
standard errors for bias, empirical SE, model SE, relative error in model SE,
MSE, coverage, bias-eliminated coverage, rejection rate and convergence. Do not
design those; use them.

Study 1 of this program established the working budget empirically, on this
machine. A discrete-time longitudinal mechanism generating 4000 individuals over
120 monthly cycles, with two closed-form estimators fitted at six horizons, ran
1000 replicates of a scenario in 50 seconds on 6 workers, so 24 scenarios cost
about 20 minutes. Enumerating the truth by brute force at two million
individuals per scenario cost about four minutes per scenario, which is the
larger bill and the one people forget.

So a design whose per-replicate cost is a handful of `glm` fits can be large. A
design that fits a longitudinal TMLE with SuperLearner per replicate cannot: at
5 seconds per fit, 24,000 fits is 33 hours on one core. If `ltmle` or a
SuperLearner ensemble is in the comparison, say explicitly how many scenarios by
replicates by fits that implies and whether it fits the budget, and offer a
smaller design if it does not.

Budget: about a week of one person's time, and the run itself should finish
overnight at worst.
"""

DESIGN_PROMPT = """You design a simulation study that will be run, published, and
attached to a public catalog entry as the answer to a stated open problem.

Answer from the payload and your own knowledge of this literature. Do not use
tools, do not spawn sub-agents, do not load skills.

## What you are given

One or more entries from an audited catalog of open problems in target trial
emulation. Each entry states the problem, why it
is open, what has already been tried with citations, and what the catalog thinks
the research direction is. These entries have been through full-text review and
external audit; where an entry says a part of the problem is already solved and
names the work that solved it, believe it and do not redesign that part.

The FIRST entry is the target. Any others are related entries the same study
might also bear on; say at the end which of them it answers, partly answers, or
does not touch.
{ENVIRONMENT}
## What to produce

An ADEMP protocol, following Morris, White and Crowther (2019). Be specific
enough that someone else could implement it without asking you a question.

**Aims.** State the question as something with a numerical answer. "Investigate
the impact of X" is not a question. "By how much does the estimated risk
difference at five years move when the grace period is doubled, across
convergence rates between 10 and 70 percent, and does diagnostic Y predict the
move" is.

**Data-generating mechanisms.** Give the full generative model: covariate
distributions with their parameters, the outcome model with its coefficients on a
named scale, the treatment effect structure, and the effect-modification
structure. Give actual numbers, not symbols. Say which quantities are varied
across scenarios, at which levels, and why those levels are the realistic ones;
anchor to published applied values where you can. State whether the design is
fully factorial and how many scenarios result.

Say what the mechanism deliberately makes true, and therefore what the study
cannot detect. If the visit process is generated at fixed monthly
cycles, the study says nothing about irregular observation, and that belongs in
the protocol rather than in a reviewer's report.

**Estimands.** Name the target quantity precisely: which strategy contrast, at
which horizon, on which scale, marginal or conditional, and for a
superpopulation or the realized sample. In an emulation the estimand is a
function of the protocol, so the protocol has to be part of the mechanism rather
than of the analysis; that is where studies in this area go wrong. Say how the true
value is computed; if it needs a large-sample Monte Carlo evaluation rather than
a closed form, say how large and why that is enough.

**Methods.** The estimators compared, each with the exact variance estimator and
interval construction, since that is often the thing under test. Include the
naive or current-practice comparator, because a study with no status quo in it
cannot say anything is worse than what people already do. Say what constitutes
non-convergence for each.

**Performance measures.** Which ones, and which is the primary. Give the number
of replicates and DERIVE it from a target Monte Carlo standard error on the
primary measure; show the arithmetic.

**The decision rule, written before the results exist.** State what result would
count as showing the problem is real, what would count as showing it is not, and
what result would be uninformative. Give the numerical thresholds.

## What to be careful about

Name the ways this design could produce a misleading answer, and what you did
about each. Be concrete about the one that matters most here: a simulation whose
DGM is built to make the studied effect appear will make it appear.

## Output

Reply with JSON only, no prose before or after.

{{"title":"...","question":"...","aims":"...",
 "dgm":{{"covariates":"...","outcome_model":"...","treatment_effect":"...",
        "effect_modification":"...","factors":[{{"name":"...","levels":["..."],
        "rationale":"..."}}],"n_scenarios":24,"deliberately_true":"...",
        "cannot_detect":"..."}},
 "estimands":[{{"name":"...","definition":"...","true_value_computation":"..."}}],
 "methods":[{{"name":"...","point_estimator":"...","variance_estimator":"...",
        "interval":"...","is_status_quo":false,"nonconvergence":"...",
        "implementation":"..."}}],
 "performance":{{"primary":"...","secondary":["..."],
        "n_rep":2000,"n_rep_derivation":"..."}},
 "decision_rule":{{"problem_is_real_if":"...","problem_is_not_real_if":"...",
        "uninformative_if":"..."}},
 "threats":[{{"threat":"...","mitigation":"..."}}],
 "runtime_estimate":"...",
 "bears_on":[{{"id":"...","relation":"answers|answers-part|does-not-touch",
        "what":"..."}}],
 "citations":[{{"cite":"...","doi_or_url":"...","used_for":"..."}}]}}

PAYLOAD:
"""

CRITIQUE_PROMPT = """You are reviewing a simulation-study protocol before it is
run. Your job is to find what is wrong with it, not to improve its presentation.

Answer from the payload and your own knowledge of this literature. Do not use
tools, do not spawn sub-agents, do not load skills.

You are given the open problem the study is meant to settle, and the proposed
design. Assume the design was written by someone competent who wants a
particular conclusion, because that is the usual situation.

Attack it on these axes, in this order of importance.

1. **Does the study answer the stated problem, or a neighbouring one?** This is
   the most common fatal flaw and the hardest to see. A study can be internally
   flawless and measure something the catalog entry did not ask about. Compare
   the aims to the problem statement word by word.

2. **Is the finding built into the data-generating mechanism?** If the DGM makes
   the studied effect true by construction, the study demonstrates arithmetic
   rather than a property of the methods. Say precisely which parameter choice
   does this, if any.

3. **Is the estimand right, and is the true value right?** In population
   adjustment the usual errors are conflating a conditional with a marginal
   effect, conflating the realized target sample with the target superpopulation,
   and computing a "true value" that is the truth for a different population than
   the estimator targets. Check each.

4. **Is the comparison fair?** A status quo method given a worse variance
   estimator than the proposed one is a rigged comparison. Check that each method
   gets the treatment its own authors recommend.

5. **Would the decision rule actually fire?** Check the thresholds against what
   the design can resolve given its replicate count and Monte Carlo error. A rule
   that cannot be triggered by any realistic result is not a rule.

6. **Feasibility.** Is the runtime estimate honest?

Also check every citation. If a work is attributed to the wrong authors, or does
not say what the design claims, say so; that error has occurred repeatedly in
this area and is not caught by anything downstream.

For each finding give a severity:
  fatal      the study would not answer the problem; must be fixed before running
  serious    the answer would be materially wrong or misread
  minor      worth fixing, does not threaten the conclusion
  limitation not fixable within this design; must be stated in the protocol

Be willing to say the design is sound on an axis. A critique that finds
something fatal on every axis is not a critique.

## Output

Reply with JSON only, no prose before or after.

{"verdict":"sound|needs-revision|unsound",
 "summary":"three or four sentences",
 "findings":[{"axis":"answers-problem|dgm-builds-in-finding|estimand|fair-comparison|decision-rule|feasibility|citation",
   "severity":"fatal|serious|minor|limitation","what":"...","fix":"..."}],
 "citation_problems":[{"cite":"...","problem":"..."}],
 "what_is_sound":["..."]}

PAYLOAD:
"""


def extract_json(text):
    depth, start = 0, None
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                blob = text[start:i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError:
                    pass
                start = None
    return None


def call(prompt, payload, tag, slug, timeout=5400):
    os.makedirs(OUT, exist_ok=True)
    full = prompt + json.dumps(payload, ensure_ascii=False, indent=1)
    open(os.path.join(OUT, f"{slug}-{tag}-prompt.txt"), "w", encoding="utf8").write(full)
    # `-` reads the prompt from stdin. A design payload carries a whole catalog
    # entry and runs well past the size at which passing it as argv started
    # losing batches in the triage step.
    cmd = ["codex", "exec", "-m", MODEL, "-c", f"model_reasoning_effort={EFFORT}",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules", "-"]
    print(f"  {MODEL} at {EFFORT} effort, {tag} pass ...", flush=True)
    p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                       input=full.encode("utf8"))
    out = p.stdout.decode("utf8", "ignore")
    open(os.path.join(OUT, f"{slug}-{tag}-raw.txt"), "w", encoding="utf8").write(out)
    d = extract_json(out)
    if not d:
        sys.exit(f"no JSON in {tag} output; see {OUT}/{slug}-{tag}-raw.txt")
    json.dump(d, open(os.path.join(OUT, f"{slug}-{tag}.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    return d


def slugify(s):
    s = re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")
    return re.sub(r"-+", "-", s)


def design_one(pid, entry, related, slug):
    """One design pass. Returns (pid, slug, summary) or (pid, slug, None)."""
    try:
        d = call(DESIGN_PROMPT.replace("{ENVIRONMENT}", ENVIRONMENT),
                 {"target": entry, "related": related}, "design", slug)
    except SystemExit as e:
        print(f"  {pid}: FAILED ({e})", flush=True)
        return pid, slug, None
    except Exception as e:
        print(f"  {pid}: FAILED ({type(e).__name__})", flush=True)
        return pid, slug, None
    print(f"  {pid}: {d.get('dgm', {}).get('n_scenarios')} scenarios x "
          f"{d.get('performance', {}).get('n_rep')} reps, "
          f"{len(d.get('methods') or [])} methods", flush=True)
    return pid, slug, d


def design_all(parallel):
    """Design every queued problem that does not already have one.

    A first design on every problem, not a finished protocol for any: the
    critique pass is what turns one into the other and is deliberately not run
    here. Each design names its own scenarios, replicate count and decision
    rule, so the output is directly comparable across the queue and the
    expensive ones are visible before anybody starts building them.
    """
    queue = json.load(open(os.path.join(ROOT, "studies", "queue.json"),
                           encoding="utf8"))["queue"]
    P = {p["id"]: p for p in json.load(open(REGISTRY, encoding="utf8"))}
    ## Keyed by problem id, not by slug. A design written by hand through
    ## --problems picks its own slug, and matching on the slug would then design
    ## the same problem twice from the same prompt, which is duplicate noise
    ## rather than a second opinion.
    done = {os.path.basename(f).split("-")[0] + "-" + os.path.basename(f).split("-")[1]
            for f in glob.glob(os.path.join(OUT, "*-design.json"))}

    todo = []
    for r in queue:
        pid = r["id"]
        if pid not in P:
            continue
        slug = f"{pid}-{slugify(r['title'])[:44]}".rstrip("-")
        if pid in done:
            print(f"  {pid}: cached")
            continue
        ## `depends_on` from triage names entries a study would have to settle
        ## first; they travel as related context so a design can say which of
        ## them it also bears on.
        rel = [P[i] for i in (r.get("depends_on") or []) if i in P and i != pid]
        todo.append((pid, P[pid], rel, slug))

    if not todo:
        print("every queued problem already has a design")
        return
    os.makedirs(OUT, exist_ok=True)
    print(f"{len(todo)} designs to write with {MODEL} at {EFFORT} effort, "
          f"{parallel} at a time", flush=True)

    got = {}
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futs = [pool.submit(design_one, pid, ent, rel, slug)
                for pid, ent, rel, slug in todo]
        for f in as_completed(futs):
            pid, slug, d = f.result()
            if d is not None:
                json.dump([pid], open(os.path.join(OUT, f"{slug}-problems.json"),
                                      "w", encoding="utf8"))
                got[pid] = (slug, d)
    print(f"\n{len(got)} of {len(todo)} designs written to {OUT}")


def report():
    """One table over every design, plus each design written out in full.

    The point of designing the whole queue at once is comparability: sixteen
    JSON files say nothing about which studies are cheap, which are expensive
    and which have quietly proposed the same experiment. This is the artifact
    that shows that.
    """
    queue = {r["id"]: r for r in json.load(
        open(os.path.join(ROOT, "studies", "queue.json"), encoding="utf8"))["queue"]}
    P = {p["id"]: p for p in json.load(open(REGISTRY, encoding="utf8"))}

    rows = []
    for f in sorted(glob.glob(os.path.join(OUT, "*-design.json"))):
        slug = os.path.basename(f).rsplit("-design.json", 1)[0]
        pid = slug.split("-")[0] + "-" + slug.split("-")[1]
        d = json.load(open(f, encoding="utf8"))
        rows.append({"pid": pid, "slug": slug, "d": d})
    rows.sort(key=lambda r: [q["id"] for q in
                             json.load(open(os.path.join(ROOT, "studies", "queue.json"),
                                            encoding="utf8"))["queue"]].index(r["pid"])
              if r["pid"] in queue else 999)

    L = ["# Designs for the study program", "",
         f"{len(rows)} of {len(queue)} queued problems have a first design. "
         f"Each was written by {MODEL} at {EFFORT} reasoning effort from the "
         f"catalog entry in full, against the measured budget of this machine.",
         "",
         "**These have not been critiqued.** The design pass produces something "
         "plausible, and a simulation study is uniquely vulnerable to answering "
         "a neighbouring question, because the data-generating mechanism is "
         "chosen by whoever wants a particular conclusion and nothing in the "
         "output announces it. Nothing here is ready to run. Citations are "
         "unverified and do not enter a catalog entry without going through "
         "`build/lit/check_citations.py`.", ""]

    ## Two things a reader should see before the table rather than after it, and
    ## both are computed from the designs rather than asserted. Designs were
    ## written independently, in parallel, each seeing only its own catalog
    ## entry, so agreement between them is either the field converging on the
    ## same right answer or one model reaching for the same template seventeen
    ## times. Which of those it is cannot be settled here, and the critique pass
    ## is where it would be, so the numbers go on the page unexplained.
    n_cov = sum(1 for r in rows
                if "coverage" in ((r["d"].get("performance") or {}).get("primary") or "").lower())
    n_24 = sum(1 for r in rows if (r["d"].get("dgm") or {}).get("n_scenarios") == 24)
    L += [f"**Convergence between designs.** {n_cov} of {len(rows)} make coverage "
          f"of a nominal 95 percent interval the primary measure, and {n_24} of "
          f"{len(rows)} land on exactly 24 scenarios. Each design was written "
          f"independently and saw only its own catalog entry, so that is either "
          f"the right measure for most of these questions or one model reaching "
          f"for one template. Nothing here decides which.", ""]

    L += ["| # | problem | scenarios | reps | methods | primary measure | runtime as estimated |",
          "|---|---|---:|---:|---:|---|---|"]
    for i, r in enumerate(rows, 1):
        d = r["d"]
        L.append(f"| {i} | {r['pid']} | {d.get('dgm', {}).get('n_scenarios', '?')} | "
                 f"{d.get('performance', {}).get('n_rep', '?')} | "
                 f"{len(d.get('methods') or [])} | "
                 f"{(d.get('performance', {}).get('primary') or '')[:52]} | "
                 f"{(d.get('runtime_estimate') or '')[:46]} |")

    for i, r in enumerate(rows, 1):
        d, pid = r["d"], r["pid"]
        L += ["", "---", "", f"## {i}. {pid}: {d.get('title', '')}", "",
              f"*Catalog entry: {(P.get(pid) or {}).get('title', '')}*", "",
              f"**Question.** {d.get('question', '')}", "",
              f"**Aims.** {d.get('aims', '')}", ""]
        g = d.get("dgm") or {}
        L += ["**Data-generating mechanism.**", "",
              f"- Covariates: {g.get('covariates', '')}",
              f"- Outcome model: {g.get('outcome_model', '')}",
              f"- Treatment effect: {g.get('treatment_effect', '')}",
              f"- Effect modification: {g.get('effect_modification', '')}",
              f"- Deliberately true: {g.get('deliberately_true', '')}",
              f"- Cannot detect: {g.get('cannot_detect', '')}", ""]
        if g.get("factors"):
            L += ["| factor | levels | why |", "|---|---|---|"]
            for fac in g["factors"]:
                L.append(f"| {fac.get('name')} | "
                         f"{', '.join(str(x) for x in (fac.get('levels') or []))} | "
                         f"{fac.get('rationale', '')} |")
            L.append("")
        if d.get("estimands"):
            L += ["**Estimands.**", ""]
            for e in d["estimands"]:
                L.append(f"- **{e.get('name')}**: {e.get('definition')} "
                         f"*Truth: {e.get('true_value_computation')}*")
            L.append("")
        if d.get("methods"):
            L += ["**Methods.**", "",
                  "| method | point estimator | variance | status quo | non-convergence |",
                  "|---|---|---|---|---|"]
            for m in d["methods"]:
                L.append(f"| {m.get('name')} | {m.get('point_estimator', '')} | "
                         f"{m.get('variance_estimator', '')} | "
                         f"{'yes' if m.get('is_status_quo') else 'no'} | "
                         f"{m.get('nonconvergence', '')} |")
            L.append("")
        pf = d.get("performance") or {}
        L += [f"**Performance.** Primary: {pf.get('primary', '')}. "
              f"Secondary: {', '.join(pf.get('secondary') or []) or 'none stated'}. "
              f"{pf.get('n_rep', '?')} replicates. {pf.get('n_rep_derivation', '')}", ""]
        dr = d.get("decision_rule") or {}
        L += ["**Decision rule, written before the results exist.**", "",
              f"- Problem is real if: {dr.get('problem_is_real_if', '')}",
              f"- Problem is not real if: {dr.get('problem_is_not_real_if', '')}",
              f"- Uninformative if: {dr.get('uninformative_if', '')}", ""]
        if d.get("threats"):
            L += ["**Threats the design names against itself.**", ""]
            for t in d["threats"]:
                L.append(f"- {t.get('threat')} *Mitigation: {t.get('mitigation')}*")
            L.append("")
        L += [f"**Runtime as estimated.** {d.get('runtime_estimate', '')}", ""]
        if d.get("bears_on"):
            L += ["**Also bears on.** " + "; ".join(
                f"{b.get('id')} ({b.get('relation')})" for b in d["bears_on"]), ""]
        if d.get("citations"):
            L += ["**Cited, unverified.** " + "; ".join(
                f"{c.get('cite')}" for c in d["citations"]), ""]

    path = os.path.join(ROOT, "documentation", "studies", "DESIGNS.md")
    open(path, "w", encoding="utf8").write("\n".join(L) + "\n")
    print(f"{len(rows)} designs -> {path}")
    tot = sum((r["d"].get("dgm", {}).get("n_scenarios") or 0) *
              (r["d"].get("performance", {}).get("n_rep") or 0) for r in rows)
    print(f"  {tot:,} replicates across the program as designed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--problems", nargs="+")
    ap.add_argument("--slug")
    ap.add_argument("--critique", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--parallel", type=int, default=4)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()

    if a.all:
        return design_all(a.parallel)
    if a.report:
        return report()
    if not a.slug:
        sys.exit("pass --slug, or --all, or --report")

    P = {p["id"]: p for p in json.load(open(REGISTRY, encoding="utf8"))}

    if a.critique:
        design = json.load(open(os.path.join(OUT, f"{a.slug}-design.json"),
                                encoding="utf8"))
        ids = json.load(open(os.path.join(OUT, f"{a.slug}-problems.json"),
                             encoding="utf8"))
        d = call(CRITIQUE_PROMPT,
                 {"problems": [P[i] for i in ids], "proposed_design": design},
                 "critique", a.slug)
        print(f"\nverdict: {d.get('verdict')}")
        print(d.get("summary", ""))
        for f in d.get("findings", []):
            print(f"\n  [{f.get('severity','?').upper()}] {f.get('axis')}")
            print(f"    {f.get('what')}")
            print(f"    fix: {f.get('fix')}")
        for c in d.get("citation_problems", []):
            print(f"\n  [CITATION] {c.get('cite')}: {c.get('problem')}")
        return

    if not a.problems:
        sys.exit("pass --problems")
    missing = [i for i in a.problems if i not in P]
    if missing:
        sys.exit(f"not in registry: {missing}")
    os.makedirs(OUT, exist_ok=True)
    json.dump(a.problems, open(os.path.join(OUT, f"{a.slug}-problems.json"), "w",
                               encoding="utf8"))
    d = call(DESIGN_PROMPT.replace("{ENVIRONMENT}", ENVIRONMENT),
             {"target": P[a.problems[0]],
              "related": [P[i] for i in a.problems[1:]]},
             "design", a.slug)
    print(f"\ntitle: {d.get('title')}")
    print(f"question: {d.get('question')}")
    print(f"scenarios: {d.get('dgm', {}).get('n_scenarios')}, "
          f"n_rep: {d.get('performance', {}).get('n_rep')}")
    print(f"runtime: {d.get('runtime_estimate')}")
    for m in d.get("methods", []):
        print(f"  method: {m.get('name')}"
              + ("  [status quo]" if m.get("is_status_quo") else ""))


if __name__ == "__main__":
    main()
