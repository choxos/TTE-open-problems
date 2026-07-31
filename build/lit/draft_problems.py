#!/usr/bin/env python3
"""Turn accepted new-problem proposals into registry entries, and fold them in.

A proposal is a paragraph a paper-reader wrote and an independent reviewer
accepted. A registry entry is a different object: it states the problem for
someone who has read none of the papers, says why it is open rather than merely
unsolved, lists what has been tried with real citations, proposes a direction,
and carries the trail that lets a reader check all of it. The 232 existing
entries were written that way and the new ones have to match, or the catalog
becomes two catalogs.

So the proposals are drafted into entries by agents that see the full evidence
behind each cluster and the existing entries in the same category, and the ids
are assigned here rather than by the agents, because an id has to be unique
across the registry and no single agent can see all of it.

Sixteen clusters carry a `merge_into` from the reviewer: it judged them part of
an existing problem rather than a new one. Those do not become entries. They
become additions to the entry they belong to, which is the whole point of having
asked.

Usage:
  python3 build/lit/draft_problems.py --build --batches 12
  python3 build/lit/draft_problems.py --apply
"""

import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
REGISTRY = os.path.join(AUDIT, "registry")
DRAFTS = os.path.join(READING, "drafts")


def registry():
    return json.load(open(os.path.join(REGISTRY, "problems.json"), encoding="utf8"))


def next_ids(problems, clusters):
    """Assign each new cluster the next free id in its category.

    Ids must not collide with an existing entry or with each other, and the
    agents draft in parallel and cannot see one another, so this is decided
    before anything is drafted rather than reconciled afterwards.
    """
    top = defaultdict(int)
    for p in problems:
        m = re.fullmatch(r"([A-Z]{3})-(\d+)", p["id"])
        if m:
            top[m.group(1)] = max(top[m.group(1)], int(m.group(2)))
    out = {}
    for i, c in enumerate(clusters):
        if c.get("merge_into"):
            continue
        cat = c.get("category") or "DEC"
        top[cat] += 1
        out[i] = f"{cat}-{top[cat]:02d}"
    return out


def library():
    return {c["id"]: c for c in json.load(open(
        os.path.join(ROOT, "documentation", "refs", "library.json"), encoding="utf8"))}


def build(n_batches):
    problems, clusters = registry(), json.load(
        open(os.path.join(READING, "proposed-changes.json"),
             encoding="utf8"))["new_problem_clusters"]
    lib = library()
    ids = next_ids(problems, clusters)
    os.makedirs(os.path.join(DRAFTS, "out"), exist_ok=True)
    for f in glob.glob(os.path.join(DRAFTS, "batch_*.json")):
        os.remove(f)

    # The existing entries in the same category, trimmed to what a drafter needs:
    # the voice to match, and enough of each statement to notice that a proposal
    # is already covered. The reviewer checked that per batch; a drafter seeing a
    # whole category at once is the last chance to catch it.
    by_cat = defaultdict(list)
    for p in problems:
        by_cat[p["category"]].append({
            "id": p["id"], "title": p["title"], "verdict": p["verdict"],
            "statement": (p.get("statement") or "")[:420],
        })

    items = []
    for i, c in enumerate(clusters):
        ev = []
        for m in c["members"]:
            y = (lib.get(m.get("paper")) or {}).get("year")
            ev.append({"paper": m.get("paper_title"), "year": y,
                       "doi": m.get("doi"), "quote": m.get("quote"),
                       "reader_statement": m.get("statement"),
                       "reader_why_open": m.get("why_open"),
                       "reader_checked_against": m.get("checked_against_index"),
                       "reviewer_verdict": m.get("review"),
                       "reviewer_reason": m.get("review_reason")})
        items.append({
            "assigned_id": ids.get(i),
            "merge_into": c.get("merge_into") or None,
            "category": c["category"],
            "proposed_title": c.get("title"),
            "proposed_statement": c.get("statement"),
            "proposed_why_open": c.get("why_open"),
            "grouping_rationale": c.get("rationale"),
            "proposed_by": c.get("proposed_by"),
            "evidence": ev,
            "existing_in_this_category": by_cat.get(c["category"], []),
        })

    size = -(-len(items) // n_batches)
    for b in range(n_batches):
        chunk = items[b * size:(b + 1) * size]
        if not chunk:
            continue
        bid = f"{b + 1:02d}"
        json.dump({"batch": bid,
                   "output": f"documentation/audit/reading/drafts/out/{bid}.json",
                   "items": chunk},
                  open(os.path.join(DRAFTS, f"batch_{bid}.json"), "w",
                       encoding="utf8"), indent=1, ensure_ascii=False)
    n_new = sum(1 for x in items if x["assigned_id"])
    n_merge = sum(1 for x in items if x["merge_into"])
    print(f"{len(items)} clusters: {n_new} to draft as new entries, "
          f"{n_merge} to fold into an existing problem")
    print(f"  batches -> {os.path.relpath(DRAFTS, ROOT)}/batch_NN.json")


REQUIRED = ("id", "title", "category", "statement", "why_open", "prior_work",
            "proposed_direction", "priority", "maturity", "verdict",
            "verdict_rationale")
ENUM = {
    "priority": {"Very high", "High", "Medium-high", "Medium"},
    "maturity": {"Established", "Promising", "Emerging", "Speculative"},
    "verdict": {"confirmed-open", "partially-addressed", "overstated",
                "resolved-since-report", "not-supported", "unverifiable"},
}


def apply():
    problems = registry()
    known = {p["id"] for p in problems}
    drafts, merges, bad = [], [], []
    for f in sorted(glob.glob(os.path.join(DRAFTS, "out", "*.json"))):
        d = json.load(open(f, encoding="utf8"))
        drafts += d.get("entries") or []
        merges += d.get("merges") or []

    seen = set()
    ok = []
    for e in drafts:
        why = []
        for k in REQUIRED:
            if not e.get(k):
                why.append(f"missing {k}")
        for k, vals in ENUM.items():
            if e.get(k) and e[k] not in vals:
                why.append(f"{k}={e[k]!r} not allowed")
        if e.get("id") in known:
            why.append(f"id {e.get('id')} already exists")
        if e.get("id") in seen:
            why.append(f"id {e.get('id')} drafted twice")
        if not (e.get("prior_work") or []):
            why.append("prior_work is empty")
        if why:
            bad.append((e.get("id"), "; ".join(why)))
            continue
        seen.add(e["id"])
        ok.append(e)

    if bad:
        print(f"{len(bad)} drafts rejected:")
        for i, w in bad:
            print(f"  {i}: {w}")

    # Fill the fields the renderer and the validator expect but a drafter has no
    # business inventing. `source_refs` says where an entry came from, and for
    # these it is the reading, not the source documents.
    for e in ok:
        e.setdefault("merged_from", [])
        e.setdefault("source_refs", ["reading:" + b for b in
                                     sorted({m for m in e.get("from_batches") or []})]
                     or ["reading"])
        e.setdefault("tractability", None)
        e.setdefault("severity", None)
        e.setdefault("claims_to_check", [])
        e["source_unsourced"] = False
        e.setdefault("implementation_specific", False)
        e["_group"] = e["category"]
        e.setdefault("related", [])
        e.setdefault("audit", {})
        e["audit"].setdefault("provenance", "proposed by the full-text reading of "
                              "the consolidated library, accepted by an "
                              "independent second reviewer")
        e.setdefault("original_statement", None)
        e.setdefault("correction_note", None)

    # Cross-links must be symmetric and must resolve, which is what
    # tools/check-registry.mjs enforces at build time.
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

    # A merge is a proposal the reviewer judged part of an existing problem. It
    # still carries evidence, and dropping it would lose exactly the papers that
    # prompted someone to raise it. Where the drafter disagreed with the merge
    # call, the disagreement is recorded on the entry rather than acted on: a
    # drafter that could promote its own merges would make the reviewer's
    # judgement advisory.
    merged, missed = 0, []
    for m in merges:
        t = final.get(m.get("into"))
        if not t:
            missed.append(m.get("into"))
            continue
        have = {(w.get("doi_or_url") or w.get("cite") or "").lower()
                for w in t.get("prior_work") or []}
        added = [w for w in (m.get("prior_work") or [])
                 if (w.get("doi_or_url") or w.get("cite") or "").lower() not in have]
        t.setdefault("prior_work", []).extend(added)
        if m.get("statement_addition"):
            t["statement"] = (t["statement"].rstrip() + " "
                              + m["statement_addition"].strip())
        t.setdefault("reading_update", {"applied": "full-text reading",
                                        "changes": []})
        t["reading_update"]["changes"].append({
            "kind": "merged-in",
            "what": f"absorbed a proposal the reading raised separately: "
                    f"{m.get('from_title')}",
            "evidence": f"{len(added)} citation(s) added"
                        + (f". The drafter disagreed with placing it here: "
                           f"{m['disagreement']}" if m.get("disagreement") else ""),
        })
        merged += 1

    out = list(final.values())
    json.dump(out, open(os.path.join(REGISTRY, "problems.json"), "w",
                        encoding="utf8"), indent=1, ensure_ascii=False)
    json.dump(merges, open(os.path.join(READING, "pending-merges.json"), "w",
                           encoding="utf8"), indent=1, ensure_ascii=False)
    print(f"{len(ok)} new entries added; registry now {len(out)} problems")
    print(f"{merged} of {len(merges)} merges folded into their target entry")
    dis = [m for m in merges if m.get("disagreement")]
    if dis:
        print(f"  {len(dis)} carry a recorded disagreement with the merge target")
    for i in missed:
        print(f"  !! merge target not found: {i}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--batches", type=int, default=12)
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
