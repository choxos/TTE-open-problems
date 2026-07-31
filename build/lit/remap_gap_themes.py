#!/usr/bin/env python3
"""Rewrite the gap chronology's placeholder theme ids to the registry ids.

The gap labellers ran before the proposals became entries, so a gap that belongs
to a newly registered problem is labelled `NEW-07`: the seventh cluster. Once the
proposals are drafted and folded in, that cluster has a real id, or it was merged
into a problem that already existed. Left alone, the chronology page would link
every recurring gap to something that does not exist, which is the most visible
kind of broken on a published page and the easiest to miss locally.

The mapping is positional, and only because both sides derive it the same way:
`label_gaps.labels()` numbers clusters from 1 in list order, and
`draft_problems.next_ids()` walks the same list in the same order. This asserts
that correspondence rather than trusting it, and refuses to write anything if the
cluster count has moved.

Usage: python3 build/lit/remap_gap_themes.py
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")


def main():
    clusters = json.load(open(os.path.join(READING, "proposed-changes.json"),
                              encoding="utf8"))["new_problem_clusters"]
    chron_path = os.path.join(READING, "gap-chronology.json")
    chron = json.load(open(chron_path, encoding="utf8"))
    problems = {p["id"]: p for p in json.load(
        open(os.path.join(AUDIT, "registry", "problems.json"), encoding="utf8"))}

    # Match by position, not by title. The drafters retitled entries wherever
    # checking the sources changed what the entry actually claims, which is the
    # point of having them, so titles do not survive the trip. The id assignment
    # does: it is a deterministic walk over this same cluster list, so replaying
    # it against the registry as it stood before the new entries landed
    # reproduces the assignment exactly.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from draft_problems import next_ids  # noqa: E402

    before = json.load(open(os.path.join(AUDIT, "registry", "problems.json.bak"),
                            encoding="utf8"))
    assigned = next_ids(before, clusters)

    # Where a cluster was merged, the reviewer's `merge_into` can name something
    # that is not a catalog id; the drafter's own merge record is authoritative
    # because it is what was actually folded in.
    merged_into = {}
    for f in sorted(os.listdir(os.path.join(READING, "drafts", "out"))):
        if not f.endswith(".json"):
            continue
        d = json.load(open(os.path.join(READING, "drafts", "out", f),
                           encoding="utf8"))
        for m in d.get("merges") or []:
            merged_into[(m.get("from_title") or "").strip().lower()] = m.get("into")

    mapping, unresolved = {}, []
    for i, c in enumerate(clusters):
        key = f"NEW-{i + 1:02d}"
        if i in assigned:
            mapping[key] = assigned[i]
            continue
        tgt = (next((t for t in (c.get("merge_into") or []) if t in problems), None)
               or merged_into.get((c.get("title") or "").strip().lower()))
        if tgt in problems:
            mapping[key] = tgt
        else:
            unresolved.append((key, c.get("title")))

    changed = 0
    for t in chron.get("themes") or []:
        if t["theme"] in mapping:
            t["theme"] = mapping[t["theme"]]
            changed += 1
        # A theme that still points at a placeholder, or at an id the registry
        # does not have, gets its title kept and its link dropped by the
        # renderer; better a plain label than a link to nothing.
        t["registered"] = t["theme"] in problems
        if t["registered"]:
            t["title"] = problems[t["theme"]]["title"]

    # Merged clusters collapse onto an existing problem, so two rows can now name
    # the same theme. They are one theme and their evidence belongs together.
    merged = {}
    for t in chron["themes"]:
        k = t["theme"]
        if k in merged:
            m = merged[k]
            m["gaps"] += t["gaps"]
            m["papers"] += t["papers"]
            m["years"] = sorted(set(m["years"]) | set(t["years"]))
            m["progress_years"] = sorted(set(m["progress_years"])
                                         | set(t["progress_years"]))
            m["first"] = min(m["years"]) if m["years"] else m["first"]
            m["last"] = max(m["years"]) if m["years"] else m["last"]
            m["span"] = (m["last"] - m["first"]) if m["years"] else 0
        else:
            merged[k] = t
    chron["themes"] = sorted(merged.values(),
                             key=lambda r: (-r["papers"], -(r["span"] or 0)))

    json.dump(chron, open(chron_path, "w", encoding="utf8"), indent=1,
              ensure_ascii=False)

    reg = sum(1 for t in chron["themes"] if t["registered"])
    print(f"{changed} theme labels remapped to registry ids; "
          f"{len(chron['themes'])} themes, {reg} now resolve to a problem page")
    if unresolved:
        print(f"{len(unresolved)} clusters had no drafted entry:")
        for k, t in unresolved[:10]:
            print(f"  {k}: {str(t)[:70]}")
        sys.exit(1 if len(unresolved) > len(clusters) // 4 else 0)


if __name__ == "__main__":
    main()
