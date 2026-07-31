#!/usr/bin/env python3
"""Search the screened corpus by title and abstract, for the literature check.

The literature auditor's job is to find work that already resolves a claimed open
problem. Doing that from memory is how invented citations get written, so this
searches what is actually on disk: the harvested records, restricted by default to
the ones screening kept.

Terms are ANDed; each term may be a `;`-separated set of alternatives, and each
alternative is matched as a regular expression against title plus abstract. The
separator is `;` rather than `|` so that alternation inside a regex group still
works, which is the form these queries naturally take.

  python3 build/lit/corpus_search.py "grace period" "sensitiv;choice"
  python3 build/lit/corpus_search.py "competing (event|risk)" "separable"
  python3 build/lit/corpus_search.py --all "positivity" --show 300
"""

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")


def load(kept_only=True):
    path = os.path.join(OUT, "screened.jsonl")
    if not os.path.exists(path):
        path = os.path.join(OUT, "records.jsonl")
        kept_only = False
    if not os.path.exists(path):
        sys.exit("No corpus. Run build/lit/search.py first.")
    recs = []
    for line in open(path, encoding="utf8"):
        r = json.loads(line)
        if kept_only and (r.get("screen") or {}).get("decision") != "include":
            continue
        recs.append(r)
    return recs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("terms", nargs="+")
    ap.add_argument("--all", action="store_true",
                    help="search every harvested record, not only the ones screening kept")
    ap.add_argument("--show", type=int, default=0,
                    help="print this many characters of each abstract")
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--from-year", type=int, default=0)
    args = ap.parse_args()

    recs = load(kept_only=not args.all)
    pats = [[re.compile(alt, re.I) for alt in t.split(";")] for t in args.terms]

    hits = []
    for r in recs:
        hay = f"{r.get('title') or ''}\n{r.get('abstract') or ''}\n{' '.join(r.get('keywords') or [])}"
        if int(r.get("year") or 0) < args.from_year:
            continue
        if all(any(p.search(hay) for p in group) for group in pats):
            hits.append(r)

    hits.sort(key=lambda r: -int(r.get("year") or 0))
    print(f"# {len(hits)} of {len(recs)} records match {args.terms}")
    for r in hits[:args.limit]:
        print(f"{r.get('year')} | {r.get('doi') or r.get('pmid')} | "
              f"{(r.get('journal') or '')[:38]} | {(r.get('title') or '')[:110]}")
        if args.show:
            a = re.sub(r"\s+", " ", r.get("abstract") or "")[:args.show]
            if a:
                print(f"        {a}")


if __name__ == "__main__":
    main()
