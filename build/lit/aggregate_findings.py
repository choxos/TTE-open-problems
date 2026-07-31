#!/usr/bin/env python3
"""Pool the paper-reader findings and prepare the high-stakes ones for review.

Not every finding is worth a second opinion. `supports-open` restates a gap the
registry already asserts, so a wrong one costs little. The claims that can change
the registry are the ones that retire or narrow a problem, or add a new one, and
those are what the external reviewer sees.

Outputs:
  reading/aggregate.json    every finding, keyed by problem
  reading/review/NN.json    review batches for the external auditor
  reading/SUMMARY.md        what the reading found, for a human

Usage: python3 build/lit/aggregate_findings.py [--per-batch 8]
"""

import argparse
import glob
import json
import os
import re
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
HIGH_STAKES = ("resolves", "contradicts", "partially-addresses")


def load_problems():
    p = json.load(open(os.path.join(AUDIT, "registry", "problems.json"), encoding="utf8"))
    return {x["id"]: x for x in p}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-batch", type=int, default=8)
    args = ap.parse_args()

    problems = load_problems()
    # One work catalogued twice is two papers to everything downstream: it
    # doubles its own evidence, inflates the count of independent papers behind
    # a problem, and puts the same claim in the chronology twice. See
    # build/lit/fix_years.py for how they are found.
    dup = {c["id"]: c["duplicate_of"] for c in json.load(open(
        os.path.join(ROOT, "documentation", "refs", "library.json"),
        encoding="utf8")) if c.get("duplicate_of")}

    findings, new_problems, papers, unread = [], [], [], []
    missing, errata, duplicated = [], [], []
    for path in sorted(glob.glob(os.path.join(READING, "findings", "*.json"))):
        d = json.load(open(path, encoding="utf8"))
        # A reader that drops a paper leaves no trace: the batch file says twelve,
        # the findings file says ten, and nothing downstream compares them. An
        # unread paper has to be visible, or the corpus quietly shrinks.
        bid = d.get("batch") or os.path.basename(path)[:-5]
        bf = os.path.join(READING, f"batch_{bid}.json")
        if os.path.exists(bf):
            want = [p["id"] for p in json.load(open(bf, encoding="utf8"))["papers"]]
            got = {pa.get("id") for pa in d.get("papers", [])}
            for pid in want:
                if pid not in got:
                    missing.append((bid, pid))
        for pa in d.get("papers", []):
            if pa.get("id") in dup:
                duplicated.append((pa["id"], dup[pa["id"]],
                                   len(pa.get("problems") or [])))
                continue
            papers.append({"batch": d.get("batch"), **{k: pa.get(k) for k in
                          ("id", "read", "doi", "title", "relevance", "one_line")}})
            if not pa.get("read"):
                unread.append(pa)
                continue
            for f in pa.get("problems", []):
                findings.append({"batch": d.get("batch"), "paper": pa.get("id"),
                                 "paper_title": pa.get("title"), "doi": pa.get("doi"),
                                 **f})
            for n in pa.get("new_problems", []):
                new_problems.append({"batch": d.get("batch"), "paper": pa.get("id"),
                                     "paper_title": pa.get("title"),
                                     "doi": pa.get("doi"), **n})
            # Not a finding and not a new problem: a fact the registry states
            # about the literature that the paper in hand disproves.
            for e in pa.get("registry_errata", []):
                errata.append({"batch": d.get("batch"), "paper": pa.get("id"),
                               "paper_title": pa.get("title"),
                               "doi": pa.get("doi"), **e})

    unknown = [f for f in findings if f.get("problem_id") not in problems]
    by_problem = defaultdict(list)
    for f in findings:
        by_problem[f.get("problem_id")].append(f)

    json.dump({"papers": papers, "findings": findings,
               "new_problems": new_problems, "missing_papers": missing,
               "registry_errata": errata},
              open(os.path.join(READING, "aggregate.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    # ---- review batches: only what could change the registry -----------------
    items = []
    for f in findings:
        if f.get("effect") not in HIGH_STAKES:
            continue
        p = problems.get(f["problem_id"], {})
        items.append({
            "kind": "finding",
            "problem_id": f["problem_id"],
            "problem_title": p.get("title"),
            "problem_verdict": p.get("verdict"),
            "problem_statement": (p.get("statement") or "")[:900],
            "paper": f.get("paper_title"),
            "doi": f.get("doi"),
            "claimed_effect": f.get("effect"),
            "claimed_confidence": f.get("confidence"),
            "evidence": f.get("evidence"),
            "quote": f.get("quote"),
            "locator": f.get("locator"),
        })
    for n in new_problems:
        items.append({
            "kind": "new-problem",
            "proposed_title": n.get("proposed_title"),
            "category": n.get("category"),
            "statement": n.get("statement"),
            "why_open": n.get("why_open"),
            "paper": n.get("paper_title"),
            "doi": n.get("doi"),
            "quote": n.get("quote"),
            "checked_against_index": n.get("checked_against_index"),
        })

    rev = os.path.join(READING, "review")
    os.makedirs(rev, exist_ok=True)

    # Anything already reviewed stays reviewed, and anything already queued stays
    # queued. Both matter: re-running this while a batch is still with the
    # reviewer would otherwise re-batch every pending item, and the reviewer
    # would answer the same question twice at full cost. Batch numbering keeps
    # climbing so an existing file is never overwritten.
    seen, taken = set(), 0
    for f in sorted(glob.glob(os.path.join(rev, "verdict-*.json"))):
        for v in json.load(open(f, encoding="utf8"))["verdicts"]:
            it = v.get("item") or {}
            seen.add((it.get("problem_id") or "NEW", (it.get("quote") or "")[:120]))
    # Take the high-water mark from verdicts too, not just from the batch files.
    # A batch file that gets removed would otherwise free its number for reuse,
    # and the next batch to claim it would silently inherit the old verdicts,
    # which answer entirely different items.
    for f in glob.glob(os.path.join(rev, "verdict-rev-*.json")):
        taken = max(taken, int(re.search(r"rev-(\d+)", f).group(1)))
    for f in glob.glob(os.path.join(rev, "rev-*.json")):
        taken = max(taken, int(re.search(r"rev-(\d+)", f).group(1)))
        for it in json.load(open(f, encoding="utf8"))["items"]:
            seen.add((it.get("problem_id") or "NEW", (it.get("quote") or "")[:120]))

    fresh = [x for x in items
             if (x.get("problem_id") or "NEW", (x.get("quote") or "")[:120]) not in seen]
    nb = 0
    for i in range(0, len(fresh), args.per_batch):
        nb += 1
        bid = f"rev-{taken + nb:02d}"
        json.dump({"batch": bid, "items": fresh[i:i + args.per_batch]},
                  open(os.path.join(rev, f"{bid}.json"), "w", encoding="utf8"),
                  indent=1, ensure_ascii=False)

    # ---- human summary -------------------------------------------------------
    eff = Counter(f.get("effect") for f in findings)
    rel = Counter(p.get("relevance") for p in papers)
    lines = ["# What the reading found so far", "",
             f"{len(papers)} papers read, {len(unread)} unreadable. "
             f"{len(findings)} findings against {len(by_problem)} of "
             f"{len(problems)} registered problems. "
             f"{len(new_problems)} new problems proposed.", "",
             "| effect | n |", "|---|---:|"]
    for k, v in eff.most_common():
        lines.append(f"| {k} | {v} |")
    lines += ["", "| paper relevance | n |", "|---|---:|"]
    for k, v in rel.most_common():
        lines.append(f"| {k} | {v} |")
    if unknown:
        lines += ["", f"**{len(unknown)} findings cite an id not in the registry**: "
                  + ", ".join(sorted({f['problem_id'] for f in unknown}))]
    if duplicated:
        lines += ["", f"**{len(duplicated)} read papers are duplicates of another "
                  f"catalog entry** and are excluded here so one work is not "
                  f"counted as two: "
                  + "; ".join(f"{a} = {b} ({n} findings dropped)"
                              for a, b, n in duplicated)]
    if missing:
        by_batch = defaultdict(list)
        for b, pid in missing:
            by_batch[b].append(pid)
        lines += ["", f"**{len(missing)} assigned papers are absent from their "
                  f"batch's findings file**, neither read nor recorded as "
                  f"unreadable: "
                  + "; ".join(f"{b} ({', '.join(v)})"
                              for b, v in sorted(by_batch.items()))]

    if errata:
        lines += ["", "## Errors the reading found in the registry itself", "",
                  f"{len(errata)} places where an entry states something about "
                  f"the literature that the paper disproves. These are not "
                  f"findings about whether a problem is open; they are mistakes "
                  f"in the entry.", "",
                  "| problem | kind | registry says | actually | from |",
                  "|---|---|---|---|---|"]
        for e in errata:
            lines.append(
                f"| {e.get('problem_id')} | {e.get('kind')} | "
                f"{(e.get('what_the_registry_says') or '')[:70]} | "
                f"{(e.get('what_is_actually_true') or '')[:70]} | "
                f"{(e.get('paper_title') or '')[:40]} |")

    lines += ["", "## Problems the reading would move", "",
              "Only `resolves`, `contradicts` and `partially-addresses` can change a "
              "verdict; `supports-open` reinforces what the registry already says.", "",
              "| problem | current verdict | claims |", "|---|---|---|"]
    movers = defaultdict(Counter)
    for f in findings:
        if f.get("effect") in HIGH_STAKES:
            movers[f["problem_id"]][f["effect"]] += 1
    for pid, c in sorted(movers.items(), key=lambda kv: (-sum(kv[1].values()), kv[0])):
        p = problems.get(pid, {})
        claims = ", ".join(f"{v}x {k}" for k, v in c.most_common())
        lines.append(f"| {pid} {(p.get('title') or '')[:70]} | "
                     f"{p.get('verdict')} | {claims} |")

    lines += ["", "## Proposed new problems", "", "| category | title | from |",
              "|---|---|---|"]
    for n in new_problems:
        lines.append(f"| {n.get('category')} | {(n.get('proposed_title') or '')[:90]} | "
                     f"{(n.get('paper_title') or '')[:50]} |")

    open(os.path.join(READING, "SUMMARY.md"), "w", encoding="utf8").write(
        "\n".join(lines) + "\n")

    print(f"{len(papers)} papers, {len(findings)} findings, "
          f"{len(new_problems)} proposed new problems")
    for k, v in eff.most_common():
        print(f"  {k:22s} {v}")
    print(f"  problems touched      {len(by_problem)}")
    print(f"  review batches        {nb} ({len(items)} items at {args.per_batch} each)")
    if unknown:
        print(f"  UNKNOWN problem ids   {len(unknown)}")
    if errata:
        print(f"  registry errata       {len(errata)}")
    if duplicated:
        print(f"  duplicate reads       {len(duplicated)} excluded")
        for a, b, n in duplicated:
            print(f"    {a} = {b}, {n} findings dropped")
    if missing:
        print(f"  MISSING from output   {len(missing)} assigned papers")
        for b, pid in missing:
            print(f"    {b} {pid}")


if __name__ == "__main__":
    main()
