#!/usr/bin/env python3
"""Adjudicate the problems an earlier pass closed that the reading found open.

The reading produced `supports-open` findings against 24 problems the first audit
had marked `overstated` or `not-supported`. That looks like a contradiction and
mostly is not, because of how those closures were written: a closure usually
concedes a residual. EVB-02 says multiverse analysis over the evidence set has
been demonstrated, and that what remains open is that nobody requires it and no
criterion says which alternative networks are defensible. A reader who finds a
2024 paper complaining that nobody requires it has not contradicted the closure.
It has restated the part the closure already left open.

So the question is not "does new evidence say this is open", which is what
produced the list. It is:

    does the new evidence assert something the closure's own residual does
    not already cover?

Answering it needs both sides in view at once, which is exactly what the reading
did not have: readers saw the problem statement, never the audit trail that
closed it. This puts the closure's reasoning, the work it relied on, and the new
findings in front of one reviewer together, and defaults to leaving the closure
alone. Reversing a prior adjudication on evidence that merely repeats what it
already conceded would make the catalog oscillate.

Outputs:
  reading/reopen/NN.json           payloads
  reading/reopen/verdict-NN.json   verdicts
  reading/REOPEN.md                the assessment

Usage:
  python3 build/lit/reopen.py --build
  python3 build/lit/reopen.py --run --parallel 5
  python3 build/lit/reopen.py --report
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from second_review import extract_json, MODEL  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
OUT = os.path.join(READING, "reopen")
REFS = os.path.join(ROOT, "documentation", "refs")
PER_BATCH = 2          # these payloads carry a whole audit trail plus dozens of findings
MAX_FINDINGS = 40      # newest first; the tail repeats the head

PROMPT = """You are adjudicating whether to reverse an earlier verdict in a catalog of open
problems in target trial emulation.

Each problem below was closed by an earlier audit as `overstated` (the underlying
issue is real but the claim as written was too strong) or `not-supported` (the
claim could not be substantiated). A later full-text reading of {N_PAPERS} papers then
produced findings asserting the problem is open.

That is usually not a contradiction. A closure normally concedes a residual: it
says a method exists, or the strong form of the claim is false, and names what
genuinely remains. A later paper complaining about the part the closure already
conceded has restated the closure, not refuted it.

So the question is narrow:

    **Does the new evidence assert something the closure's own residual does not
    already cover?**

You are given, for each problem: the entry as it now stands, the verdict and the
rationale that closed it, the auditors' reasoning and the specific work they
relied on, and the new findings with verbatim quotes and publication years.

Default to leaving the closure alone. Reversing an adjudication on evidence that
repeats what it already conceded would make the catalog oscillate, and the
earlier auditors had the closing evidence in front of them while the readers did
not: readers saw only the problem statement, never the audit trail.

Reopen only when the new evidence does one of these:
  - contradicts the work the closure relied on, for example by showing that the
    method the auditors cited does not do what they said, or does not apply
  - shows the closed portion is not in fact covered, not merely not adopted
  - postdates the closure and supersedes its factual basis

Return one verdict per problem:
  keep-closed   the new evidence restates the residual the closure already
                names, or is weaker than the closure's counterevidence
  narrow        the closure stands, but its statement or residual is drawn in the
                wrong place; say in `what_to_change` how it should read
  reopen        the closure does not survive the new evidence; say which finding
                does the damage and to which verdict it should move

Answer from the payload and your own knowledge of this literature. Do not use
tools, do not spawn sub-agents, do not load skills.

Reply with JSON only, no prose before or after:

{"verdicts":[{"index":0,"problem_id":"EVB-02","verdict":"keep-closed|narrow|reopen","confidence":"high|medium|low","move_to":"...or null","what_to_change":"...or null","decisive_evidence":"...or null","reason":"three or four sentences"}]}

Index each verdict by the problem's position in the payload, starting at 0.
Return exactly one verdict per problem.

PAYLOAD:
"""


def build():
    problems = {p["id"]: p for p in json.load(
        open(os.path.join(AUDIT, "registry", "problems.json"), encoding="utf8"))}
    pc = json.load(open(os.path.join(READING, "proposed-changes.json"),
                        encoding="utf8"))
    by_problem = {c["id"]: c for c in pc["changes"]}
    lib = {c["id"]: c for c in json.load(
        open(os.path.join(REFS, "library.json"), encoding="utf8"))}

    def year(pid):
        try:
            return int((lib.get(pid) or {}).get("year"))
        except (TypeError, ValueError):
            return None

    items = []
    for r in pc["reopen_candidates"]:
        p = problems.get(r["id"])
        if not p:
            continue
        fs = [f for f in by_problem.get(r["id"], {}).get("findings", [])
              if f.get("effect") == "supports-open"]
        # Newest first: a closure is most threatened by work that postdates it,
        # and the older findings tend to repeat the newer ones.
        fs.sort(key=lambda f: -(year(f.get("paper")) or 0))
        items.append({
            "problem_id": p["id"],
            "title": p["title"],
            "closed_as": p["verdict"],
            "statement": (p.get("statement") or "")[:1600],
            "why_open": (p.get("why_open") or "")[:900],
            "closure_rationale": p.get("verdict_rationale"),
            "closure_auditors": [{
                "auditor": o.get("auditor"),
                "status_vote": o.get("status_vote"),
                "support_vote": o.get("support_vote"),
                "confidence": o.get("confidence"),
                "reasoning": (o.get("rationale") or "")[:1800],
                "work_relied_on": [{"locator": w.get("locator"),
                                    "what_it_resolves": w.get("what_it_resolves")}
                                   for w in (o.get("resolving_work") or [])],
            } for o in (p.get("audit", {}).get("opinions") or [])],
            "closure_dissent": (p.get("audit", {}) or {}).get("dissent"),
            "new_findings_total": len(fs),
            "new_findings": [{
                "year": year(f.get("paper")),
                "paper": f.get("paper_title"),
                "doi": f.get("doi"),
                "confidence": f.get("confidence"),
                "evidence": f.get("evidence"),
                "quote": (f.get("quote") or "")[:420],
            } for f in fs[:MAX_FINDINGS]],
        })

    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "[0-9]*.json")):
        os.remove(f)
    n = 0
    for i in range(0, len(items), PER_BATCH):
        n += 1
        # n_papers travels with the payload so the prompt can state the real
        # size of the reading that produced these findings. Typing it into the
        # prompt would make it a number that is right once.
        json.dump({"batch": f"{n:02d}", "n_papers": len(lib),
                   "items": items[i:i + PER_BATCH]},
                  open(os.path.join(OUT, f"{n:02d}.json"), "w", encoding="utf8"),
                  indent=1, ensure_ascii=False)
    print(f"{len(items)} reopen candidates in {n} batches")
    for it in items:
        shown = len(it["new_findings"])
        print(f"  {it['problem_id']:8s} {it['closed_as']:15s} "
              f"{it['new_findings_total']:3d} new findings"
              + (f" ({shown} sent)" if shown < it["new_findings_total"] else "")
              + f"  {len(it['closure_auditors'])} closure opinions")


def run_one(bid, timeout=2400):
    payload = json.load(open(os.path.join(OUT, f"{bid}.json"), encoding="utf8"))
    cmd = ["codex", "exec", "-m", MODEL, "-c", "model_reasoning_effort=high",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules",
           PROMPT.replace("{N_PAPERS}", str(payload.get("n_papers", "the"))) +
           json.dumps(payload["items"], ensure_ascii=False, indent=1)]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return bid, None, "timeout"
    out = p.stdout.decode("utf8", "ignore")
    open(os.path.join(OUT, f"raw-{bid}.txt"), "w", encoding="utf8").write(out)
    d = extract_json(out)
    if not d:
        return bid, None, "no JSON in output"
    v = d.get("verdicts", [])
    for x in v:
        i = x.get("index")
        if isinstance(i, int) and 0 <= i < len(payload["items"]):
            x["item"] = payload["items"][i]
    json.dump({"batch": bid, "model": MODEL, "verdicts": v},
              open(os.path.join(OUT, f"verdict-{bid}.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    return bid, len(v), ("ok" if len(v) == len(payload["items"])
                         else f"{len(v)} for {len(payload['items'])}")


def run(parallel):
    batches = sorted(os.path.splitext(f)[0] for f in os.listdir(OUT)
                     if re.fullmatch(r"\d+\.json", f))
    batches = [b for b in batches
               if not os.path.exists(os.path.join(OUT, f"verdict-{b}.json"))]
    print(f"{len(batches)} batches to adjudicate with {MODEL}")
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futs = {pool.submit(run_one, b): b for b in batches}
        for f in as_completed(futs):
            bid, n, note = f.result()
            print(f"  {bid}: {n if n is not None else 'FAILED'} ({note})", flush=True)


def report():
    got = []
    for f in sorted(glob.glob(os.path.join(OUT, "verdict-*.json"))):
        got += json.load(open(f, encoding="utf8"))["verdicts"]
    if not got:
        sys.exit("no verdicts yet; run --build then --run")
    order = ["reopen", "narrow", "keep-closed"]
    got.sort(key=lambda v: (order.index(v["verdict"]) if v["verdict"] in order else 9,
                            v.get("problem_id") or ""))
    n = {k: sum(1 for v in got if v["verdict"] == k) for k in order}

    L = ["# The problems an earlier pass closed and the reading found open", "",
         f"{len(got)} problems carry a verdict of `overstated` or `not-supported` "
         f"from the first audit and `supports-open` findings from the full-text "
         f"reading. That looks like a contradiction and mostly is not: a closure "
         f"normally concedes a residual, and a later paper complaining about the "
         f"conceded part has restated the closure rather than refuted it.", "",
         "Each was put to an independent reviewer with the closure's reasoning, "
         "the work the auditors relied on, and the new findings in view at once, "
         "which is what the reading itself never had: readers saw the problem "
         "statement and never the audit trail. The instruction was to default to "
         "leaving the closure alone.", "",
         "| outcome | meaning | n |", "|---|---|---:|",
         f"| `reopen` | the closure does not survive the new evidence | {n['reopen']} |",
         f"| `narrow` | the closure stands, but its residual is drawn in the wrong "
         f"place | {n['narrow']} |",
         f"| `keep-closed` | the new evidence restates what the closure already "
         f"conceded | {n['keep-closed']} |", ""]

    for k in order:
        rs = [v for v in got if v["verdict"] == k]
        if not rs:
            continue
        L += [f"## {k}", ""]
        for v in rs:
            it = v.get("item", {})
            L += [f"### {it.get('problem_id')} — {it.get('title')}", "",
                  f"*Closed as `{it.get('closed_as')}`; "
                  f"{it.get('new_findings_total')} findings from the reading say "
                  f"it is open. Reviewer confidence {v.get('confidence')}."
                  + (f" Moves to `{v['move_to']}`." if v.get("move_to") else ""), "",
                  "**Closure said.** " + (it.get("closure_rationale") or ""), "",
                  "**Assessment.** " + (v.get("reason") or ""), ""]
            if v.get("decisive_evidence"):
                L += ["**What decides it.** " + v["decisive_evidence"], ""]
            if v.get("what_to_change"):
                L += ["**What to change.** " + v["what_to_change"], ""]

    open(os.path.join(READING, "REOPEN.md"), "w", encoding="utf8").write(
        "\n".join(L) + "\n")
    print(f"{len(got)} adjudicated -> documentation/audit/reading/REOPEN.md")
    for k in order:
        print(f"  {k:12s} {n[k]}")
    for v in got:
        if v["verdict"] != "keep-closed":
            print(f"  >> {v.get('problem_id'):8s} {v['verdict']:11s} "
                  f"{v.get('confidence'):6s} -> {v.get('move_to') or 'n/a'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--parallel", type=int, default=5)
    a = ap.parse_args()
    if a.build:
        build()
    if a.run:
        run(a.parallel)
    if a.report:
        report()
    if not (a.build or a.run or a.report):
        sys.exit("pass --build, --run or --report")


if __name__ == "__main__":
    main()
