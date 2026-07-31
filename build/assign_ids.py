#!/usr/bin/env python3
"""Turn the raw seed extraction into canonical per-category files with final ids.

In the sibling project this step was a merge: thirteen extraction agents worked
overlapping slices of the source, so the same problem arrived three or four
times and an agent per category decided which records were one problem. Here the
extraction was done in one pass over the whole document by a reader who could see
all of it, so cluster_raw.py finds no duplicate pairs and there is nothing to
adjudicate. What remains is mechanical and belongs in code rather than in a
prompt: group by category, assign ids in source order, and carry the cross-link
hints through.

The id is load-bearing. render_site.mjs writes `problems/<id>-<slug>.qmd` and each
category page globs `../problems/<CODE>-*.qmd`, so the code prefixes the id, which
prefixes the filename, which is the published URL. Assigning ids in source order
means re-running this on an unchanged extraction produces identical ids.

Input   documentation/audit/raw/*.json
Output  documentation/audit/canonical/<CODE>.json

Usage: python3 build/assign_ids.py
"""

import glob
import json
import os
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "documentation", "audit", "raw")
OUT = os.path.join(ROOT, "documentation", "audit", "canonical")

# Must agree with CATEGORIES in build/render_site.mjs. check-registry.mjs imports
# that list and validates every published id against it, so a code that exists
# here and not there fails the build rather than shipping an unreachable page.
CODES = ["PRO", "ELG", "TZO", "STR", "EST", "CNF", "GMT", "OVL", "UCF",
         "MER", "MIS", "OUT", "SEQ", "DTA", "BEN", "REG", "SFW", "LRN"]

# Fields that travel from the raw record to the registry unchanged. Anything not
# listed is extraction bookkeeping and is dropped here rather than published.
CARRY = ["title", "statement", "why_open", "prior_work", "proposed_direction",
         "priority", "maturity", "tractability", "severity",
         "protocol_component", "data_setting", "related_hint",
         "implementation_specific"]


def main():
    files = sorted(glob.glob(os.path.join(RAW, "*.json")))
    if not files:
        sys.exit(f"No raw extraction in {os.path.relpath(RAW, ROOT)}")

    by_cat = defaultdict(list)
    raw_ids = {}
    for path in files:
        blob = json.load(open(path, encoding="utf8"))
        for p in blob["problems"]:
            cat = p["category"]
            if cat not in CODES:
                sys.exit(f"{os.path.basename(path)}: unknown category {cat!r}")
            p["_slice"] = blob["slice"]
            p["_raw_id"] = p["id"]
            by_cat[cat].append(p)

    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "*.json")):
        if os.path.basename(f) != "problems.json":
            os.remove(f)

    total = 0
    for code in CODES:
        group = by_cat.get(code)
        if not group:
            print(f"  {code}: no entries")
            continue
        out = []
        for i, p in enumerate(group, 1):
            pid = f"{code}-{i:02d}"
            raw_ids[p["_raw_id"]] = pid
            rec = {"id": pid, "category": code}
            for k in CARRY:
                if p.get(k) is not None:
                    rec[k] = p[k]
            rec["source"] = {"slice": p["_slice"], "raw_id": p["_raw_id"],
                             "locator": p.get("source_locator")}
            out.append(rec)
        json.dump({"group": code, "problems": out},
                  open(os.path.join(OUT, f"{code}.json"), "w", encoding="utf8"),
                  indent=1, ensure_ascii=False)
        total += len(out)
        print(f"  {code}: {len(out)} -> {code}-01 .. {code}-{len(out):02d}")

    print(f"{total} problems in {len([c for c in CODES if by_cat.get(c)])} categories "
          f"-> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
