#!/usr/bin/env python3
"""Split the consolidated library into reading batches for the paper-reader agents.

Ordering is by how much a paper is likely to bear on the registry, not
alphabetically: the population-adjustment literature first, then component
methods, then the general network meta-analysis corpus, which is the largest and
the thinnest per paper. Batches are written as small JSON files so each agent
gets an explicit file list and an explicit output path, and so a batch can be
re-run without disturbing the others.

Usage:
  python3 build/lit/batch_reading.py --tier core --size 12
  python3 build/lit/batch_reading.py --list
"""

import argparse
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REFS = os.path.join(ROOT, "documentation", "refs")
READING = os.path.join(ROOT, "documentation", "audit", "reading")

# Tier by topic: the phrases the registry is actually about come first.
TIERS = {
    # Ordered by expected yield: the narrow phrases are where the methodological argument
    # lives, and the two broad ones return mostly applied emulations that a reader will mark
    # relevance: none. Reading the narrow tiers first means the registry is already populated
    # when the expensive, low-yield tiers run.
    "core": [("systematic", "CCW"), ("manual", "CCW"),
             ("systematic", "GFORM"), ("manual", "GFORM"),
             ("systematic", "ITB"), ("systematic", "EMUL"),
             ("systematic", "TTE"), ("manual", "TTE"),
             ("manual", "Guidance"), ("manual", "General"),
             ("manual", "Protocol"), ("manual", "BENCH")],
    "msm": [("systematic", "MSM"), ("manual", "MSM")],
    "broad": [("systematic", "TEMU"), ("systematic", "TT")],
}


def load():
    lib = json.load(open(os.path.join(REFS, "library.json"), encoding="utf8"))
    # A retracted paper is not evidence, and a correction notice is not a paper.
    # Both cost a reader a slot and can only produce a finding that has to be
    # withdrawn later. See build/lit/retractions.py for how they are marked.
    return [c for c in lib
            if (c.get("pdf") or c.get("xml") or c.get("text"))
            and not c.get("duplicate_of")
            and c.get("status") not in ("retracted", "notice")]


def pool(tier):
    want = TIERS[tier]
    order = {k: i for i, k in enumerate(want)}
    hits = [c for c in load() if (c["source"], c.get("topic")) in order]
    # Newest first inside a topic: recent work is what can have closed a problem.
    return sorted(hits, key=lambda c: (order[(c["source"], c.get("topic"))],
                                       -int(c.get("year") or 0),
                                       c.get("title") or ""))


def under(c, key):
    """Repo-relative path to a file. The systematic tree stores a bare filename
    beside its folder; the hand-collected entries store a full path already."""
    v = c.get(key)
    if not v:
        return None
    return v if os.sep in v else os.path.join(c["path"], v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", default="core", choices=list(TIERS))
    ap.add_argument("--size", type=int, default=12)
    ap.add_argument("--offset", type=int, default=0, help="skip this many papers")
    ap.add_argument("--batches", type=int, default=0, help="0 for all remaining")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        for t in TIERS:
            print(f"{t:6s} {len(pool(t)):4d} readable papers")
        return

    recs = pool(args.tier)[args.offset:]
    if args.batches:
        recs = recs[:args.batches * args.size]
    os.makedirs(os.path.join(READING, "findings"), exist_ok=True)

    written = []
    for i in range(0, len(recs), args.size):
        chunk = recs[i:i + args.size]
        n = args.offset // args.size + i // args.size + 1
        bid = f"{args.tier}-{n:02d}"
        path = os.path.join(READING, f"batch_{bid}.json")
        json.dump({
            "batch": bid,
            "output": os.path.relpath(
                os.path.join(READING, "findings", f"{bid}.json"), ROOT),
            "problems_index": "documentation/audit/problems-index.md",
            "papers": [{
                "id": c["id"],
                "source": c["source"],
                "topic": c.get("topic"),
                "year": c.get("year"),
                "title": c.get("title"),
                "doi": c.get("doi"),
                "pdf": under(c, "pdf"),
                "xml": under(c, "xml"),
                "text": under(c, "text"),
                "dir": c["path"],
            } for c in chunk],
        }, open(path, "w", encoding="utf8"), indent=1, ensure_ascii=False)
        written.append((bid, len(chunk), os.path.relpath(path, ROOT)))

    for bid, n, path in written:
        print(f"{bid}  {n:3d} papers  {path}")
    print(f"{len(written)} batches, {len(recs)} papers, tier {args.tier}")


if __name__ == "__main__":
    main()
