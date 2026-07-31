#!/usr/bin/env python3
"""Ask the second reviewer whether the later paper answers the earlier one.

`build/lit/timeline.py` finds problems whose newest evidence is progress and
whose every assertion of openness is older. That ordering is suggestive and
nothing more. Two papers can sit either side of a date and be about different
questions, and a `partially-addresses` from 2024 may close a corner of a problem
whose 2019 statement was about something else entirely. Publication order cannot
tell those apart; only reading the two claims against each other can.

So each candidate goes to the same external reviewer that judges the findings,
with the older claims and the newer claims side by side and one question: does
the later work answer what the earlier work left open?

The reviewer never sees the classification, only the two sets of claims, so it
cannot agree with the mechanism by reading its label.

Outputs:
  documentation/audit/reading/review/timeline-NN.json         payloads
  documentation/audit/reading/review/verdict-timeline-NN.json verdicts
  documentation/audit/reading/TIMELINE-VERIFIED.md            the result

Usage:
  python3 build/lit/verify_timeline.py --build     # write the payloads
  python3 build/lit/verify_timeline.py --run       # send them to the reviewer
  python3 build/lit/verify_timeline.py --report    # render the verdicts
"""

import argparse
import glob
import json
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from second_review import extract_json, MODEL  # noqa: E402
from timeline import classify, year_of, PROGRESS  # noqa: E402
import subprocess  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
REVIEW = os.path.join(READING, "review")
PER_BATCH = 3        # these payloads are long; three problems is already a lot

PROMPT = """You are an independent reviewer for a catalog of open problems in indirect
treatment comparisons and population-adjusted indirect comparisons.

For each problem below you are shown two sets of claims made by papers that were
read in full, split by publication date. `called_open_by` are older papers that
say the problem is open. `reported_progress` are newer papers claimed to make
progress on it. Every claim carries a verbatim quote from the paper.

One question: **does the later work answer what the earlier work left open?**

Publication order alone proves nothing. Two papers can straddle a date and be
about different questions. A later paper can solve a corner of a problem whose
earlier statement was about something else. A later paper can also restate the
same gap while appearing to advance it. Judge the substance of the claims, not
their dates.

Answer from the payload and your own knowledge of this literature. Do not use
tools, do not spawn sub-agents, do not load skills.

Return one verdict per problem:
  answers            the later work answers the question the earlier work left
                     open; the problem should not be carried as fully open
  answers-part       the later work answers a component; a named part of the
                     earlier gap survives
  different-question the later work is about a neighbouring question and leaves
                     the earlier gap untouched
  no                 the later work does not answer it
  uncertain          cannot be judged from the payload; say what is missing

For `answers` and `answers-part`, say in `what_remains` what is left, or "nothing"
if the problem is genuinely closed. Be hard on `answers`: a wrong one deletes a
real research gap from the catalog.

Reply with JSON only, no prose before or after:

{"verdicts":[{"index":0,"verdict":"answers|answers-part|different-question|no|uncertain","confidence":"high|medium|low","what_remains":"...","reason":"two or three sentences"}]}

Index each verdict by the problem's position in the payload, starting at 0.
Return exactly one verdict per problem.

PAYLOAD:
"""


def candidates():
    """Problems whose newest evidence is progress and whose openness is older."""
    lib = {c["id"]: c for c in json.load(open(
        os.path.join(ROOT, "documentation", "refs", "library.json"), encoding="utf8"))}
    problems = {p["id"]: p for p in json.load(open(
        os.path.join(AUDIT, "registry", "problems.json"), encoding="utf8"))}
    changes = json.load(open(os.path.join(READING, "proposed-changes.json"),
                             encoding="utf8"))["changes"]
    out = []
    for ch in changes:
        dated = [(year_of(lib, f.get("paper")), f) for f in ch["findings"]]
        dated = [(y, f) for y, f in dated if y]
        if not dated:
            continue
        if classify([(y, f.get("effect"), f.get("paper"), "") for y, f in dated]) \
                != "answered-later":
            continue
        p = problems.get(ch["id"], {})

        def side(keep):
            return [{"year": y, "effect": f.get("effect"),
                     "confidence": f.get("confidence"),
                     "paper": f.get("paper_title"),
                     "evidence": f.get("evidence"), "quote": f.get("quote"),
                     "locator": f.get("locator")}
                    for y, f in sorted(dated, key=lambda t: t[0]) if keep(f)]

        out.append({
            "problem_id": ch["id"],
            "problem_title": ch["title"],
            "registry_verdict": ch.get("current_verdict"),
            "problem_statement": (p.get("statement") or "")[:1200],
            "called_open_by": side(lambda f: f.get("effect") == "supports-open"),
            "reported_progress": side(lambda f: f.get("effect") in PROGRESS),
        })
    return out


def build():
    items = candidates()
    os.makedirs(REVIEW, exist_ok=True)
    for f in glob.glob(os.path.join(REVIEW, "timeline-*.json")):
        os.remove(f)
    n = 0
    for i in range(0, len(items), PER_BATCH):
        n += 1
        bid = f"timeline-{n:02d}"
        json.dump({"batch": bid, "items": items[i:i + PER_BATCH]},
                  open(os.path.join(REVIEW, f"{bid}.json"), "w", encoding="utf8"),
                  indent=1, ensure_ascii=False)
    print(f"{len(items)} answered-later candidates in {n} batches")
    for it in items:
        print(f"  {it['problem_id']:8s} "
              f"open {len(it['called_open_by'])} / progress "
              f"{len(it['reported_progress'])}  {it['problem_title'][:56]}")
    return n


def run_one(bid, timeout=1800):
    payload = json.load(open(os.path.join(REVIEW, f"{bid}.json"), encoding="utf8"))
    cmd = ["codex", "exec", "-m", MODEL, "-c", "model_reasoning_effort=high",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules",
           PROMPT + json.dumps(payload["items"], ensure_ascii=False, indent=1)]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return bid, None, "timeout"
    out = p.stdout.decode("utf8", "ignore")
    open(os.path.join(REVIEW, f"raw-{bid}.txt"), "w", encoding="utf8").write(out)
    d = extract_json(out)
    if not d:
        return bid, None, "no JSON in output"
    v = d.get("verdicts", [])
    for x in v:
        i = x.get("index")
        if isinstance(i, int) and 0 <= i < len(payload["items"]):
            x["item"] = payload["items"][i]
    json.dump({"batch": bid, "model": MODEL, "verdicts": v},
              open(os.path.join(REVIEW, f"verdict-{bid}.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    return bid, len(v), ("ok" if len(v) == len(payload["items"])
                         else f"{len(v)} verdicts for {len(payload['items'])} items")


def run(parallel):
    batches = sorted(os.path.splitext(os.path.basename(f))[0]
                     for f in os.listdir(REVIEW)
                     if re.fullmatch(r"timeline-\d+\.json", f))
    batches = [b for b in batches
               if not os.path.exists(os.path.join(REVIEW, f"verdict-{b}.json"))]
    print(f"{len(batches)} timeline batches to review with {MODEL}")
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futs = {pool.submit(run_one, b): b for b in batches}
        for f in as_completed(futs):
            bid, n, note = f.result()
            print(f"  {bid}: {n if n is not None else 'FAILED'} verdicts ({note})",
                  flush=True)


def report():
    got = []
    for f in sorted(glob.glob(os.path.join(REVIEW, "verdict-timeline-*.json"))):
        got += json.load(open(f, encoding="utf8"))["verdicts"]
    if not got:
        sys.exit("no timeline verdicts yet; run --build then --run")

    order = ["answers", "answers-part", "different-question", "no", "uncertain"]
    got.sort(key=lambda v: (order.index(v.get("verdict")) if v.get("verdict") in order
                            else 9, v.get("item", {}).get("problem_id") or ""))
    counts = {k: sum(1 for v in got if v.get("verdict") == k) for k in order}

    L = ["# Did the later work answer the earlier work?", "",
         f"{len(got)} problems whose newest evidence is progress and whose every "
         f"assertion of openness is older were put to an independent reviewer "
         f"with the older and newer claims side by side. The reviewer was not "
         f"shown the classification, only the two sets of claims, so it could "
         f"not agree with the mechanism by reading its label.", "",
         "| verdict | meaning | n |", "|---|---|---:|",
         f"| `answers` | the later work answers what the earlier work left open |"
         f" {counts['answers']} |",
         f"| `answers-part` | a component is answered; a named part survives |"
         f" {counts['answers-part']} |",
         f"| `different-question` | the later work leaves the earlier gap untouched |"
         f" {counts['different-question']} |",
         f"| `no` | the later work does not answer it | {counts['no']} |",
         f"| `uncertain` | not decidable from the claims | {counts['uncertain']} |",
         ""]
    for k in order:
        rs = [v for v in got if v.get("verdict") == k]
        if not rs:
            continue
        L += [f"## {k}", "", "| problem | registry says | confidence | what remains |",
              "|---|---|---|---|"]
        for v in rs:
            it = v.get("item", {})
            L.append(f"| {it.get('problem_id')} "
                     f"{(it.get('problem_title') or '')[:52]} | "
                     f"{it.get('registry_verdict')} | {v.get('confidence')} | "
                     f"{(v.get('what_remains') or '')[:110]} |")
        L += [""]
        for v in rs:
            it = v.get("item", {})
            L += [f"**{it.get('problem_id')}** — {v.get('reason')}", ""]

    open(os.path.join(READING, "TIMELINE-VERIFIED.md"), "w",
         encoding="utf8").write("\n".join(L) + "\n")
    print(f"{len(got)} verdicts -> documentation/audit/reading/TIMELINE-VERIFIED.md")
    for k in order:
        print(f"  {k:20s} {counts[k]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--parallel", type=int, default=4)
    args = ap.parse_args()
    if args.build:
        build()
    if args.run:
        run(args.parallel)
    if args.report:
        report()
    if not (args.build or args.run or args.report):
        sys.exit("pass --build, --run or --report")


if __name__ == "__main__":
    main()
