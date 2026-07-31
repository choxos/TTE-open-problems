#!/usr/bin/env python3
"""Work up the themes the gap labellers wanted and could not find.

Twelve labellers attached 3,619 future-research gaps to a fixed theme set and
were asked, at the end, what they had wanted and not found. Nine absences were
named by more than one labeller working on disjoint gaps, which is independent
agreement about a hole rather than one model's opinion.

They are only candidates. Unlike the proposals that became entries, these have
had no reading and no second review: nobody checked the papers behind them, and
nobody asked whether they are a gap for the field or a to-do for those authors.
There is also a specific reason they might already be wrong. The labellers ran
against 232 registered problems plus 115 accepted proposals, and those proposals
have since been drafted into entries that were retitled and rescoped as their
authors checked the sources. A candidate can have been absorbed by that work
without anyone noticing.

So each goes out with the evidence behind it and the whole current registry, and
the first question is not "is this a good problem" but "is it still missing".

Outputs:
  reading/uncovered/batch_NN.json   payloads for the assessors
  reading/uncovered/out/NN.json     their entries and rejections

Usage:
  python3 build/lit/uncovered.py --build --batches 5
  python3 build/lit/uncovered.py --apply
"""

import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
REGISTRY = os.path.join(AUDIT, "registry")
OUT = os.path.join(READING, "uncovered")
REFS = os.path.join(ROOT, "documentation", "refs")

GAP_ID = re.compile(r"L\d{4}#\d+")


def library():
    return {c["id"]: c for c in json.load(
        open(os.path.join(REFS, "library.json"), encoding="utf8"))}


def all_gaps(lib):
    out = {}
    for f in sorted(glob.glob(os.path.join(READING, "findings", "*.json"))):
        for p in json.load(open(f, encoding="utf8")).get("papers", []):
            for j, g in enumerate(p.get("future_research") or []):
                out[f"{p['id']}#{j}"] = {
                    "paper_id": p["id"],
                    "paper": p.get("title"),
                    "doi": p.get("doi"),
                    "year": (lib.get(p["id"]) or {}).get("year"),
                    "gap": g.get("gap"),
                    "kind": g.get("kind"),
                    "quote": g.get("quote"),
                    "locator": g.get("locator"),
                }
    return out


def candidates():
    """Parse the table in UNCOVERED.md back into rows.

    The file is written for a person to read, so it is the source of truth for
    what was claimed and this reads it rather than a parallel data file that
    could drift from it.
    """
    t = open(os.path.join(READING, "UNCOVERED.md"), encoding="utf8").read()
    rows = []
    for line in t.splitlines():
        if not line.startswith("| ") or "---" in line or "labellers" in line:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 3:
            continue
        rows.append({"absence": cells[0], "labellers": cells[1],
                     "gap_ids": GAP_ID.findall(cells[2])})
    return rows


def build(n_batches):
    lib = library()
    gaps = all_gaps(lib)
    problems = json.load(open(os.path.join(REGISTRY, "problems.json"),
                              encoding="utf8"))
    # The whole registry, trimmed to what a coverage check needs. Every entry,
    # not just the obvious category: the labellers' absences cut across
    # categories, and half the point is that a candidate may have been absorbed
    # by an entry filed somewhere unexpected.
    index = [{"id": p["id"], "title": p["title"], "category": p["category"],
              "verdict": p["verdict"], "statement": (p.get("statement") or "")[:340]}
             for p in problems]

    items = []
    for c in candidates():
        ev = [dict(gaps[g], gap_id=g) for g in c["gap_ids"] if g in gaps]
        ev.sort(key=lambda e: -(int(e["year"]) if str(e.get("year") or "").isdigit()
                                else 0))
        items.append({
            "absence_as_reported": c["absence"],
            "named_by_labellers": c["labellers"],
            "evidence_gaps": ev,
            "distinct_papers": len({e["paper_id"] for e in ev}),
        })

    os.makedirs(os.path.join(OUT, "out"), exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "batch_*.json")):
        os.remove(f)
    json.dump(index, open(os.path.join(OUT, "registry-index.json"), "w",
                          encoding="utf8"), indent=1, ensure_ascii=False)

    size = -(-len(items) // n_batches)
    n = 0
    for i in range(0, len(items), size):
        n += 1
        json.dump({"batch": f"{n:02d}",
                   "registry_index": "documentation/audit/reading/uncovered/"
                                     "registry-index.json",
                   "output": f"documentation/audit/reading/uncovered/out/"
                             f"{n:02d}.json",
                   "items": items[i:i + size]},
                  open(os.path.join(OUT, f"batch_{n:02d}.json"), "w",
                       encoding="utf8"), indent=1, ensure_ascii=False)
    print(f"{len(items)} candidates, {sum(len(x['evidence_gaps']) for x in items)} "
          f"evidence gaps, {len(index)} registry entries to check against, "
          f"{n} batches")


# `id` is deliberately absent: the assessors are told not to assign one, because
# they run in parallel and cannot see each other's choices, so ids are handed out
# below. Requiring one here rejected every entry that followed instructions.
REQUIRED = ("title", "category", "statement", "why_open", "prior_work",
            "proposed_direction", "priority", "maturity", "verdict",
            "verdict_rationale")
ENUM = {
    "priority": {"Very high", "High", "Medium-high", "Medium"},
    "maturity": {"Established", "Promising", "Emerging", "Speculative"},
    "verdict": {"confirmed-open", "partially-addressed", "overstated",
                "resolved-since-report", "not-supported", "unverifiable"},
}


def apply():
    problems = json.load(open(os.path.join(REGISTRY, "problems.json"),
                              encoding="utf8"))
    known = {p["id"] for p in problems}
    top = {}
    for pid in known:
        m = re.fullmatch(r"([A-Z]{3})-(\d+)", pid)
        if m:
            top[m.group(1)] = max(top.get(m.group(1), 0), int(m.group(2)))

    entries, rejected = [], []
    for f in sorted(glob.glob(os.path.join(OUT, "out", "*.json"))):
        d = json.load(open(f, encoding="utf8"))
        entries += d.get("entries") or []
        rejected += d.get("rejected") or []

    ok, bad = [], []
    for e in entries:
        why = [f"missing {k}" for k in REQUIRED if not e.get(k)]
        why += [f"{k}={e.get(k)!r} not allowed" for k, vals in ENUM.items()
                if e.get(k) and e[k] not in vals]
        if not (e.get("prior_work") or []):
            why.append("prior_work is empty")
        if why:
            bad.append((e.get("id"), "; ".join(why)))
            continue
        # Assessors work in parallel and cannot see each other, so ids are
        # assigned here. Whatever they proposed is treated as a request.
        cat = e.get("category")
        top[cat] = top.get(cat, 0) + 1
        e["id"] = f"{cat}-{top[cat]:02d}"
        ok.append(e)

    for e in ok:
        e.setdefault("merged_from", [])
        e["source_refs"] = ["reading:uncovered"]
        e.setdefault("tractability", None)
        e.setdefault("severity", None)
        e.setdefault("claims_to_check", [])
        e["source_unsourced"] = False
        e.setdefault("implementation_specific", False)
        e["_group"] = e["category"]
        e.setdefault("related", [])
        e.setdefault("audit", {})
        e["audit"]["provenance"] = (
            "named independently by more than one gap labeller as a theme the "
            "registry lacked, then checked against the whole registry for "
            "coverage and against the cited papers for substance")
        e.setdefault("original_statement", None)
        e.setdefault("correction_note", None)

    final = {p["id"]: p for p in problems}
    for e in ok:
        final[e["id"]] = e
    for e in ok:
        e["related"] = [r for r in e.get("related", []) if r in final and r != e["id"]]
        for r in e["related"]:
            t = final[r]
            t.setdefault("related", [])
            if e["id"] not in t["related"]:
                t["related"] = sorted(t["related"] + [e["id"]])

    json.dump(list(final.values()),
              open(os.path.join(REGISTRY, "problems.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    json.dump(rejected, open(os.path.join(READING, "uncovered-rejected.json"), "w",
                             encoding="utf8"), indent=1, ensure_ascii=False)

    for i, w in bad:
        print(f"  !! rejected draft {i}: {w}")
    for e in ok:
        print(f"  + {e['id']:8s} {e['verdict']:20s} {e['title'][:60]}")
    for r in rejected:
        print(f"  - dropped: {(r.get('absence') or '')[:58]} "
              f"({r.get('why', '')[:60]})")
    print(f"\n{len(ok)} entries added, {len(rejected)} candidates rejected, "
          f"registry now {len(final)} problems")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--batches", type=int, default=5)
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if a.build:
        build(a.batches)
    elif a.apply:
        apply()
    else:
        sys.exit("pass --build or --apply")


if __name__ == "__main__":
    main()
