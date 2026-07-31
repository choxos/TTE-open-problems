#!/usr/bin/env python3
"""Write the compact registry index the paper readers read first.

A reader has to hold the whole registry in view while reading a paper, and the
registry entries run to a page each. This is the same information at the density
a reader can scan: id, verdict, priority, title, and the opening of the statement.

The count is emitted rather than typed, because a reader told there are N
problems and shown a different number stops trusting the file.

Usage: python3 build/problems_index.py
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIT = os.path.join(ROOT, "documentation", "audit")
REGISTRY = os.path.join(AUDIT, "registry", "problems.json")
OUT = os.path.join(AUDIT, "problems-index.md")

VERDICT = {
    "confirmed-open": "OPEN",
    "partially-addressed": "PARTIAL",
    "overstated": "OVERSTATED",
    "resolved-since-report": "RESOLVED",
    "not-supported": "NOT-SUPPORTED",
    "unverifiable": "UNVERIFIABLE",
}


def gist(statement, n=240):
    s = re.sub(r"\s+", " ", statement or "").strip()
    return s[:n] + ("..." if len(s) > n else "")


def main():
    problems = json.load(open(REGISTRY, encoding="utf8"))
    by_cat = {}
    for p in problems:
        by_cat.setdefault(p["category"], []).append(p)

    lines = [
        "# Registered open problems, compact index",
        "",
        f"{len(problems)} entries. This is the whole registry at reading density: match a "
        "paper against it by substance rather than by keyword, and read all of it before "
        "judging that a paper raises something new.",
        "",
    ]
    for cat in sorted(by_cat):
        lines.append(f"## {cat}")
        lines.append("")
        for p in sorted(by_cat[cat], key=lambda x: x["id"]):
            lines.append(
                f"- **{p['id']}** [{VERDICT.get(p['verdict'], p['verdict'])}] "
                f"[{p['priority']}] {p['title']}"
            )
            lines.append(f"  - {gist(p.get('statement'))}")
        lines.append("")

    with open(OUT, "w", encoding="utf8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)} ({len(problems)} entries, "
          f"{len(by_cat)} categories)")


if __name__ == "__main__":
    main()
