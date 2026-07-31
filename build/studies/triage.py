#!/usr/bin/env python3
"""Decide which registered problems a simulation or case study could answer.

The catalog has 43 problems. Only some are target trial emulation problems as
opposed to problems any observational analysis would have, and only some of
those are the kind of question a study can settle. A keyword screen cannot tell
the difference: "positivity" and "estimand" appear in most of the entries,
including ones that are really about reporting, and "no procedure defines" reads
like a methods gap while sometimes needing a consensus exercise rather than a
simulation.

So each entry goes to an external model with the two questions kept separate:

  1. Is this a target trial emulation problem? The specification of an emulated
     protocol, the g-methods used to estimate the effects of sustained treatment
     strategies, and the benchmarking of emulations against the trials they
     emulate are in scope. A problem that would be the same problem in a
     point-treatment cohort study is not, however much the entry uses the
     vocabulary.

  2. What kind of study would answer it? A simulation can measure bias,
     coverage and error rates and can demonstrate a nonidentification. It cannot
     establish that clinicians misread a plot, that a package is missing, or
     that a field does not report something. Those need a case study, a
     meta-research corpus, a consensus exercise, or code.

Splitting them matters because the failure mode is a study that is beautifully
executed against a problem it cannot settle.

Outputs:
  documentation/studies/triage/batch_NN.json   payloads
  documentation/studies/triage/verdict_NN.json verdicts
  documentation/studies/triage/QUEUE.md        the ranked program
  studies/queue.json                           the tracked copy the site reads

Usage:
  python3 build/studies/triage.py --build
  python3 build/studies/triage.py --run --parallel 4
  python3 build/studies/triage.py --report
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REGISTRY = os.path.join(ROOT, "documentation", "audit", "registry")
OUT = os.path.join(ROOT, "documentation", "studies", "triage")

MODEL = "gpt-5.6-sol"
EFFORT = "high"
BATCH_SIZE = 14

PROMPT = """You triage a catalog of open methodological problems in target trial
emulation, to decide which ones a research study could actually answer and in
what order to attempt them.

Answer from the payload and your own knowledge of this literature. Do not use
tools, do not spawn sub-agents, do not load skills.

## Scope

The program covers TARGET TRIAL EMULATION only:

  the specification of an emulated protocol and its seven components
  eligibility, time zero and the alignment of assignment with follow-up
  sustained and dynamic treatment strategies, grace periods, cloning
  g-methods for treatment-confounder feedback: IPTW and marginal structural
    models, the parametric g-formula, iterated conditional expectation,
    g-estimation, longitudinal targeted learning, modified treatment policies
  sequential nested trials
  benchmarking an emulation against the randomized trial it emulates

A problem that would be exactly the same problem in a point-treatment cohort
study is OUT of scope on its own. Measurement error, missing data, competing
risks and unmeasured confounding are general observational problems; they are in
scope only when the entry names something the emulation structure adds, such as
a covariate history that must be observed at each time point, artificial
censoring created by cloning, or an estimand defined by a strategy rather than
by a single assignment. Judge the problem, not its wording.

Set `tte`:
  core     the problem is specifically about the emulated protocol, sustained
           strategies, the g-methods for them, or emulation-versus-trial
           benchmarking
  applies  a general observational problem, but it bites on emulation in a
           specific way you can name
  no       the problem is about point-treatment analysis, data infrastructure,
           policy or reporting, and the emulation structure is incidental

## What kind of study would settle it

Set `study_type` to the single best fit:
  simulation      a Monte Carlo study with a known data-generating mechanism can
                  measure the quantity in dispute: bias, coverage, type I error,
                  power, discrimination of a diagnostic, or a demonstrated
                  nonidentification
  case-study      needs real data: a reanalysis of a published emulation, or an
                  applied worked example where the point is what happens on data
                  nobody simulated
  simulation+case both, and the case study is not decoration
  analytic        the answer is a proof or an identification result; simulation
                  could illustrate it but cannot establish it
  corpus          needs a meta-research review of published emulations to
                  measure what the field does
  consensus       needs a Delphi panel, a psychometric validation, or a
                  standards process
  software        the gap is that no implementation exists; the deliverable is
                  code, not a finding
  none            no study design would settle this

Be honest here. A simulation that assumes what is in dispute settles nothing. If
the problem says a quantity is not identified, a simulation can DEMONSTRATE the
nonidentification but cannot prove it, so that is `analytic` with simulation
support unless the open question is how badly it bites in practice.

Set `answerable`:
  yes     one well-designed study gives a defensible answer to the problem as
          stated
  partly  a study answers a named part; say which part in `answerable_part`
  no      the problem is too broad, or the study type above is not available

Set `feasibility` 1 to 5: could one competent statistician design, run and write
this in about a week using R on a laptop, with existing packages (TrialEmulation,
gfoRmula, gfoRmulaICE, lmtp, ltmle, concrete, CICI, WeightIt, survival,
riskRegression, adjustedCurves) and no new data collection?
  5 straightforward   4 comfortable   3 tight but real
  2 needs a month     1 needs a team or a year

Set `design_sketch`: one or two sentences naming the estimand, the factor that
would be varied, and the performance measure that would decide the question. Be
concrete: "vary the grace period from 0 to 180 days and compare the cloned
per-protocol estimate against the true counterfactual 5-year risk on bias and
interval coverage" is useful, "investigate the behavior of the estimator" is not.

Set `depends_on`: ids of other problems in the catalog that a study would have
to settle first, or an empty list. You see only this batch, so name ids only
when you are confident from the statement itself.

Set `priority_note`: one sentence on whether this deserves to run early. Say so
plainly if a problem is highly rated in the catalog but would make a weak study,
or is rated lower but is a clean, decisive experiment.

## Output

Reply with JSON only, no prose before or after.

{"verdicts":[{"id":"TZO-01","tte":"core|applies|no","methods":["clone-censor-weight","g-formula"],
  "study_type":"simulation","answerable":"yes|partly|no","answerable_part":"...or null",
  "feasibility":4,"design_sketch":"...","depends_on":[],"priority_note":"...",
  "confidence":"high|medium|low"}]}

Return exactly one verdict per item, with the `id` copied from the item.

PAYLOAD:
"""


def clip(s, n):
    s = (s or "").strip()
    return s if len(s) <= n else s[:n].rsplit(" ", 1)[0] + " ..."


def build():
    problems = json.load(open(os.path.join(REGISTRY, "problems.json"), encoding="utf8"))
    items = [{
        "id": p["id"],
        "title": p["title"],
        "category": p["category"],
        "priority": p.get("priority"),
        "verdict": p.get("verdict"),
        "maturity": p.get("maturity"),
        "statement": clip(p.get("statement"), 1100),
        "why_open": clip(p.get("why_open"), 600),
        "proposed_direction": clip(p.get("proposed_direction"), 600),
    } for p in problems]

    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "batch_*.json")):
        os.remove(f)
    n = 0
    for i in range(0, len(items), BATCH_SIZE):
        n += 1
        json.dump({"batch": f"{n:02d}", "items": items[i:i + BATCH_SIZE]},
                  open(os.path.join(OUT, f"batch_{n:02d}.json"), "w", encoding="utf8"),
                  indent=1, ensure_ascii=False)
    print(f"{len(items)} problems -> {n} batches of {BATCH_SIZE}")


def extract_json(text):
    """Pull the JSON object out of the CLI's output, which wraps it in chatter."""
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
                if '"verdicts"' in blob:
                    try:
                        return json.loads(blob)
                    except json.JSONDecodeError:
                        pass
                start = None
    return None


def run_batch(path, timeout=2400):
    bid = re.search(r"batch_(\d+)", path).group(1)
    payload = json.load(open(path, encoding="utf8"))
    # `-` reads the prompt from stdin. The sibling project passes it as argv, and
    # a batch of fourteen entries runs to about 30 KB; the auditor loop in this
    # repository already learned to feed a prompt of that size on stdin instead,
    # and the first run here lost three batches of four and kept the 2.6 KB one.
    cmd = ["codex", "exec", "-m", MODEL, "-c", f"model_reasoning_effort={EFFORT}",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules", "-"]
    prompt = PROMPT + json.dumps(payload["items"], ensure_ascii=False, indent=1)
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                           input=prompt.encode("utf8"))
    except subprocess.TimeoutExpired:
        return bid, None, "timeout"
    out = p.stdout.decode("utf8", "ignore")
    open(os.path.join(OUT, f"raw_{bid}.txt"), "w", encoding="utf8").write(out)
    d = extract_json(out)
    if not d:
        return bid, None, "no JSON in output"
    v = d.get("verdicts", [])
    want = {x["id"] for x in payload["items"]}
    got = {x.get("id") for x in v}
    note = "ok" if got == want else f"missing {sorted(want - got)}"
    json.dump({"batch": bid, "model": MODEL, "verdicts": v},
              open(os.path.join(OUT, f"verdict_{bid}.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    return bid, len(v), note


def run(parallel):
    todo = [f for f in sorted(glob.glob(os.path.join(OUT, "batch_*.json")))
            if not os.path.exists(f.replace("batch_", "verdict_"))]
    if not todo:
        sys.exit("nothing to do; all batches have verdicts")
    print(f"{len(todo)} batches to triage with {MODEL} at {EFFORT}", flush=True)
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futs = {pool.submit(run_batch, f): f for f in todo}
        for f in as_completed(futs):
            bid, n, note = f.result()
            print(f"  batch {bid}: {n if n is not None else 'FAILED'} ({note})",
                  flush=True)


# Ranking. Scope is a filter, not a score: an out-of-scope problem does not
# enter the program however good a study it would make. Within scope the catalog
# priority leads, because that ordering was itself audited, and feasibility only
# breaks ties. Deliberately not a weighted sum of everything: that would let a
# very feasible low-priority study outrank the problems the catalog says matter.
PRIORITY_RANK = {"Very high": 0, "High": 1, "Medium-high": 2, "Medium": 3}
TTE_RANK = {"core": 0, "applies": 1, "no": 2}
ANSWER_RANK = {"yes": 0, "partly": 1, "no": 2}
RUNNABLE = {"simulation", "simulation+case", "case-study"}


def excluded_counts(rows, queue):
    import collections
    inq = {r["id"] for r in queue}
    excl = collections.Counter()
    for r in rows:
        if r["id"] in inq:
            continue
        if r.get("tte") == "no":
            excl["not a target trial emulation problem"] += 1
        elif r.get("study_type") not in RUNNABLE:
            excl[f"needs {r.get('study_type')}, not a simulation or case study"] += 1
        else:
            excl["no study would answer it as stated"] += 1
    return excl


def report():
    problems = {p["id"]: p for p in json.load(
        open(os.path.join(REGISTRY, "problems.json"), encoding="utf8"))}
    v = {}
    for f in sorted(glob.glob(os.path.join(OUT, "verdict_*.json"))):
        for x in json.load(open(f, encoding="utf8"))["verdicts"]:
            if x.get("id") in problems:
                v[x["id"]] = x

    missing = sorted(set(problems) - set(v))
    rows = []
    for i, x in v.items():
        p = problems[i]
        rows.append({**x, "title": p["title"], "category": p["category"],
                     "priority": p.get("priority"), "verdict": p.get("verdict")})

    def key(r):
        return (TTE_RANK.get(r.get("tte"), 9),
                0 if r.get("study_type") in RUNNABLE else 1,
                ANSWER_RANK.get(r.get("answerable"), 9),
                PRIORITY_RANK.get(r.get("priority"), 9),
                -(r.get("feasibility") or 0),
                r["id"])

    rows.sort(key=key)
    queue = [r for r in rows if r.get("tte") in ("core", "applies")
             and r.get("study_type") in RUNNABLE
             and r.get("answerable") in ("yes", "partly")]

    json.dump({"queue": queue, "all": rows, "unjudged": missing},
              open(os.path.join(OUT, "triage.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    # A tracked copy, trimmed to what the site shows. The full triage lives in
    # the gitignored working directory with the raw model output beside it; the
    # queue is published output and has to survive a fresh clone.
    tracked = os.path.join(ROOT, "studies", "queue.json")
    os.makedirs(os.path.dirname(tracked), exist_ok=True)
    json.dump({
        "generated_from": f"{len(rows)} of {len(problems)} catalog problems, "
                          f"triaged by {MODEL} at {EFFORT} reasoning effort",
        "excluded": dict(excluded_counts(rows, queue)),
        "queue": [{k: r.get(k) for k in
                   ("id", "title", "category", "priority", "verdict", "tte",
                    "methods", "study_type", "answerable", "answerable_part",
                    "feasibility", "design_sketch", "priority_note", "confidence")}
                  for r in queue],
    }, open(tracked, "w", encoding="utf8"), indent=1, ensure_ascii=False)

    import collections
    L = ["# Study queue",
         "",
         f"{len(rows)} of {len(problems)} catalog problems triaged. "
         f"{len(queue)} are target trial emulation problems that a simulation or "
         f"case study could answer; they are the program, in order.",
         ""]
    if missing:
        L += [f"**{len(missing)} problems have no verdict**: "
              + ", ".join(missing), ""]

    L += ["## Why entries are excluded", "",
          "| reason | n |", "| --- | --- |"]
    for k, n in excluded_counts(rows, queue).most_common():
        L.append(f"| {k} | {n} |")

    L += ["", "## The program", "",
          "| # | id | problem | scope | methods | type | answers | feas | catalog priority |",
          "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for n, r in enumerate(queue, 1):
        L.append(f"| {n} | [{r['id']}](../../audit/registry/problems.json) | "
                 f"{r['title'][:64]} | {r['tte']} | "
                 f"{', '.join(r.get('methods') or []) or '-'} | {r['study_type']} | "
                 f"{r['answerable']} | {r.get('feasibility')} | {r['priority']} |")

    L += ["", "## The first twelve, in detail", ""]
    for n, r in enumerate(queue[:12], 1):
        L += [f"### {n}. {r['id']} {r['title']}", "",
              f"*{r['priority']} priority, catalog verdict `{r['verdict']}`, "
              f"scope `{r['tte']}`, feasibility {r.get('feasibility')}, "
              f"triage confidence {r.get('confidence')}*", "",
              f"**Design sketch.** {r.get('design_sketch')}", ""]
        if r.get("answerable") == "partly":
            L += [f"**Answers only part.** {r.get('answerable_part')}", ""]
        if r.get("depends_on"):
            L += [f"**Depends on.** {', '.join(r['depends_on'])}", ""]
        L += [f"**Sequencing.** {r.get('priority_note')}", ""]

    open(os.path.join(OUT, "QUEUE.md"), "w", encoding="utf8").write("\n".join(L) + "\n")
    print(f"{len(rows)} triaged, {len(queue)} in the program, {len(missing)} unjudged")
    print(f"  scope:      {collections.Counter(r.get('tte') for r in rows)}")
    print(f"  study type: {collections.Counter(r.get('study_type') for r in rows)}")
    print(f"  -> {os.path.join(OUT, 'QUEUE.md')}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--parallel", type=int, default=4)
    a = ap.parse_args()
    if a.build:
        build()
    elif a.run:
        run(a.parallel)
    elif a.report:
        report()
    else:
        sys.exit("pass --build, --run or --report")


if __name__ == "__main__":
    main()
