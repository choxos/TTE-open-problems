#!/usr/bin/env python3
"""Append one paper's reading result to a batch findings file.

The reader prompt warns that a single Write carrying a whole batch has stalled
with nothing saved. This appends one paper at a time to
documentation/audit/reading/findings/<batch>.json, creating the file on first
use and replacing any earlier entry for the same paper id, so a re-read of one
paper does not duplicate it.

Usage: python3 build/lit/add_finding.py <batch> <paper.json>
       cat paper.json | python3 build/lit/add_finding.py <batch> -
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "audit", "reading", "findings")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    batch, src = sys.argv[1], sys.argv[2]
    rec = json.load(sys.stdin) if src == "-" else json.load(open(src, encoding="utf8"))
    path = os.path.join(OUT, f"{batch}.json")
    os.makedirs(OUT, exist_ok=True)
    blob = {"batch": batch, "papers": []}
    if os.path.exists(path):
        blob = json.load(open(path, encoding="utf8"))
    blob["papers"] = [p for p in blob["papers"] if p["id"] != rec["id"]] + [rec]
    blob["papers"].sort(key=lambda p: p["id"])
    json.dump(blob, open(path, "w", encoding="utf8"), indent=1, ensure_ascii=False)
    n_find = sum(len(p.get("problems") or []) for p in blob["papers"])
    print(f"{batch}: {len(blob['papers'])} papers, {n_find} findings "
          f"(+{len(rec.get('problems') or [])} from {rec['id']})")


if __name__ == "__main__":
    main()
