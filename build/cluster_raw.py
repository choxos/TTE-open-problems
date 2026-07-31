#!/usr/bin/env python3
"""Pre-cluster the raw extraction output so the merge agent adjudicates only borderline pairs.

Thirteen extraction agents worked on overlapping slices of the same corpus, so the same
problem is often stated three or four times: once in the master matrix, once in the prose
section that discusses it, once in the package-specific list, and once in the agenda tiers.
Handing all 409 records to an agent and asking it to find duplicates wastes most of the
work on obvious cases.

This does the obvious cases mechanically and leaves the judgment calls.

Output: documentation/audit/clusters.json
  certain     pairs above the high threshold; merged without review
  borderline  pairs in the middle band; an agent decides
  singletons  everything else
"""

import json
import glob
import os
import re
import itertools
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "documentation/audit/raw")
OUT = os.path.join(ROOT, "documentation/audit/clusters.json")

HIGH = 0.62   # above this, the same problem
LOW = 0.34    # below this, different problems

# Words that appear in nearly every record and so carry no discriminating signal.
STOP = set("""
a an the and or of for to in on with without that this these those is are be being been
may can could should would must not no non
problem problems open remain remains method methods approach analysis analyses
effect effects treatment treatments population populations study studies trial trials
data model models estimate estimates estimation estimand estimands
itc paic nma cnma maic stc ml nmr agd ipd
""".split())


def norm(text):
    return [w for w in re.findall(r"[a-z0-9]+", (text or "").lower()) if w not in STOP and len(w) > 2]


def load():
    recs = []
    for path in sorted(glob.glob(os.path.join(RAW, "*.json"))):
        if os.path.basename(path) == "a-assets.json":
            continue
        blob = json.load(open(path, encoding="utf8"))
        slice_id = blob.get("slice", os.path.basename(path))
        for i, p in enumerate(blob.get("problems", [])):
            p["_slice"] = slice_id
            # Raw ids collide across slices by design; give each a unique handle.
            p["_uid"] = f"{slice_id}#{p.get('id', i)}"
            recs.append(p)
    return recs


def signature(rec):
    """Title carries the most signal, so weight it by repeating it."""
    title = norm(rec.get("title", ""))
    body = norm(rec.get("statement", ""))[:40]
    return set(title * 3 + body)


def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def main():
    recs = load()
    sigs = {r["_uid"]: signature(r) for r in recs}
    by_cat = defaultdict(list)
    for r in recs:
        by_cat[r.get("category", "?")].append(r)

    certain, borderline = [], []

    # Only compare within a category. A cross-category duplicate is possible but rare,
    # and comparing all 409^2 pairs across categories buys noise.
    for cat, group in by_cat.items():
        for a, b in itertools.combinations(group, 2):
            s = jaccard(sigs[a["_uid"]], sigs[b["_uid"]])
            if s >= HIGH:
                certain.append({"a": a["_uid"], "b": b["_uid"], "sim": round(s, 3),
                                "a_title": a.get("title"), "b_title": b.get("title")})
            elif s >= LOW:
                borderline.append({"a": a["_uid"], "b": b["_uid"], "sim": round(s, 3),
                                   "a_title": a.get("title"), "b_title": b.get("title"),
                                   "a_statement": (a.get("statement") or "")[:260],
                                   "b_statement": (b.get("statement") or "")[:260],
                                   "a_slice": a["_slice"], "b_slice": b["_slice"]})

    # Union-find over the certain pairs only.
    parent = {r["_uid"]: r["_uid"] for r in recs}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[ry] = rx

    for pair in certain:
        union(pair["a"], pair["b"])

    groups = defaultdict(list)
    for r in recs:
        groups[find(r["_uid"])].append(r["_uid"])

    clusters = [{"members": m, "size": len(m)} for m in groups.values()]
    multi = [c for c in clusters if c["size"] > 1]

    json.dump({
        "n_raw": len(recs),
        "n_clusters_after_certain_merge": len(clusters),
        "n_multi_member": len(multi),
        "n_borderline_pairs": len(borderline),
        "thresholds": {"high": HIGH, "low": LOW},
        "clusters": clusters,
        "certain_pairs": certain,
        "borderline_pairs": sorted(borderline, key=lambda p: -p["sim"]),
        "records": {r["_uid"]: {k: v for k, v in r.items() if not k.startswith("_")} for r in recs},
    }, open(OUT, "w"), indent=1)

    print(f"{len(recs)} raw records")
    print(f"{len(certain)} certain duplicate pairs -> {len(clusters)} clusters ({len(multi)} with >1 member)")
    print(f"{len(borderline)} borderline pairs need adjudication")
    print(f"-> {OUT}")

    print("\nlargest clusters:")
    for c in sorted(multi, key=lambda c: -c["size"])[:10]:
        titles = [recs[[r["_uid"] for r in recs].index(m)].get("title", "?") for m in c["members"][:1]]
        print(f"  {c['size']:2d}  {titles[0][:70]}")


if __name__ == "__main__":
    main()
