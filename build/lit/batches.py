#!/usr/bin/env python3
"""Stage 2 plumbing: prepare records for hand screening and record the decisions.

This script makes no screening judgments. It formats records for reading and
stores the decisions that come back. Every include/exclude call is made by hand
against the title and, where the title is not decisive, the abstract.

Batches are ordered by journal then year so that runs of the same venue read
together, which is how a human screener actually works through a list.

  build    write screening batches to screening/batch_NNNN.txt
  abstract print the full abstract for specific ids (second-pass reading)
  decide   record decisions for one batch
  list     the ids currently carrying one decision, e.g. everything uncertain
  resolve  record a second-pass decision for named ids, leaving the batch alone
  status   how far screening has got, and the running tally

Decision file: screening/decisions.jsonl , one {"id", "decision", "batch"} per
line, append-only so an interrupted session resumes where it stopped.

Usage:
  python3 build/lit/batches.py build --size 200
  python3 build/lit/batches.py abstract 12345678 23456789
  python3 build/lit/batches.py decide --batch 1 --include 111,222 --uncertain 333
  python3 build/lit/batches.py status
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")
SCREEN = os.path.join(OUT, "screening")
RECORDS = os.path.join(OUT, "records.jsonl")
DECISIONS = os.path.join(SCREEN, "decisions.jsonl")

TOPIC_ORDER = ["mlnmr", "stc", "maic", "cnma", "nma"]


def rid(r):
    return r.get("pmid") or r.get("pmcid") or (r.get("doi") or "")[:60] or r["title"][:40]


def load_records():
    if not os.path.exists(RECORDS):
        sys.exit(f"No records at {RECORDS}. Run build/lit/search.py first.")
    recs = [json.loads(l) for l in open(RECORDS, encoding="utf8")]
    return OrderedDict((rid(r), r) for r in recs)


def topic_of(r):
    for t in TOPIC_ORDER:
        if t in r.get("found_by", []):
            return t
    return "nma"


def squash(s, n):
    s = re.sub(r"\s+", " ", s or "").strip()
    return s[:n]


def cmd_build(args):
    recs = load_records()
    os.makedirs(SCREEN, exist_ok=True)

    # The four niche phrases come first and in their own batches: they are the
    # heart of the collection and deserve to be read before fatigue sets in.
    def sort_key(r):
        return (TOPIC_ORDER.index(topic_of(r)),
                (r.get("journal") or "~").lower(),
                -int(r.get("year") or 0))

    ordered = sorted(recs.values(), key=sort_key)
    # Do not mix topics within a batch; a batch should read as one coherent list.
    groups, cur, cur_topic = [], [], None
    for r in ordered:
        t = topic_of(r)
        if t != cur_topic or len(cur) >= args.size:
            if cur:
                groups.append((cur_topic, cur))
            cur, cur_topic = [], t
        cur.append(r)
    if cur:
        groups.append((cur_topic, cur))

    for f in os.listdir(SCREEN):
        if f.startswith("batch_"):
            os.remove(os.path.join(SCREEN, f))

    index = []
    for i, (topic, group) in enumerate(groups, 1):
        path = os.path.join(SCREEN, f"batch_{i:04d}.txt")
        with open(path, "w", encoding="utf8") as fh:
            fh.write(f"# batch {i} | phrase set: {topic} | {len(group)} records\n")
            fh.write("# id | year | journal | title\n")
            for r in group:
                fh.write(f"{rid(r)} | {r.get('year') or '????'} | "
                         f"{squash(r.get('journal'), 38)} | {squash(r.get('title'), 190)}\n")
        index.append({"batch": i, "topic": topic, "n": len(group),
                      "file": os.path.relpath(path, ROOT),
                      "ids": [rid(r) for r in group]})
    json.dump(index, open(os.path.join(SCREEN, "index.json"), "w"), indent=1)
    print(f"{len(recs)} records -> {len(groups)} batches in {os.path.relpath(SCREEN, ROOT)}")
    for t, n in Counter(topic_of(r) for r in recs.values()).most_common():
        print(f"  {t:6s} {n}")


def cmd_abstract(args):
    recs = load_records()
    for i in args.ids:
        r = recs.get(i)
        if not r:
            print(f"--- {i}: not found\n")
            continue
        print(f"--- {i} | {r.get('year')} | {r.get('journal')}")
        print(f"TITLE: {squash(r.get('title'), 400)}")
        print(f"ABSTRACT: {squash(r.get('abstract'), args.chars) or '(none)'}")
        kw = ", ".join(r.get("keywords") or [])[:300]
        if kw:
            print(f"KEYWORDS: {kw}")
        print()


def cmd_decide(args):
    index = {b["batch"]: b for b in json.load(open(os.path.join(SCREEN, "index.json")))}
    b = index.get(args.batch)
    if not b:
        sys.exit(f"No batch {args.batch}")
    inc = {x.strip() for x in args.include.split(",") if x.strip()}
    unc = {x.strip() for x in args.uncertain.split(",") if x.strip()}
    unknown = (inc | unc) - set(b["ids"])
    if unknown:
        sys.exit(f"ids not in batch {args.batch}: {', '.join(sorted(unknown))}")

    os.makedirs(SCREEN, exist_ok=True)
    with open(DECISIONS, "a", encoding="utf8") as fh:
        for i in b["ids"]:
            d = "include" if i in inc else "uncertain" if i in unc else "exclude"
            fh.write(json.dumps({"id": i, "decision": d, "batch": args.batch}) + "\n")
    print(f"batch {args.batch} ({b['topic']}, {b['n']} records): "
          f"{len(inc)} include, {len(unc)} uncertain, "
          f"{b['n'] - len(inc) - len(unc)} exclude")


def cmd_list(args):
    """Ids sitting on one decision, for the second-pass abstract read."""
    recs, dec = load_records(), latest()
    hits = [(i, d) for i, d in dec.items() if d["decision"] == args.decision]
    for i, d in hits:
        r = recs.get(i, {})
        print(f"{i} | b{d['batch']:03d} | {squash(r.get('journal'), 34)} | "
              f"{squash(r.get('title'), 120)}")
    print(f"# {len(hits)} {args.decision}")


def cmd_resolve(args):
    """Second-pass decision for named ids; the rest of the batch is untouched."""
    dec = latest()
    inc = [x.strip() for x in args.include.split(",") if x.strip()]
    exc = [x.strip() for x in args.exclude.split(",") if x.strip()]
    unknown = [i for i in inc + exc if i not in dec]
    if unknown:
        sys.exit(f"never screened: {', '.join(unknown)}")
    with open(DECISIONS, "a", encoding="utf8") as fh:
        for ids, d in ((inc, "include"), (exc, "exclude")):
            for i in ids:
                fh.write(json.dumps({"id": i, "decision": d,
                                     "batch": dec[i]["batch"]}) + "\n")
    print(f"resolved {len(inc)} include, {len(exc)} exclude")


def latest():
    """Last decision per id, so a re-decided batch supersedes the earlier pass."""
    out = {}
    if os.path.exists(DECISIONS):
        for line in open(DECISIONS, encoding="utf8"):
            d = json.loads(line)
            out[d["id"]] = d
    return out


def cmd_status(args):
    index = json.load(open(os.path.join(SCREEN, "index.json")))
    dec = latest()
    done = {b["batch"] for b in index if all(i in dec for i in b["ids"])}
    tally = Counter(d["decision"] for d in dec.values())
    total = sum(b["n"] for b in index)
    print(f"batches {len(done)}/{len(index)} complete, "
          f"{len(dec)}/{total} records decided")
    for k, v in tally.most_common():
        print(f"  {k:10s} {v}")
    remaining = [b["batch"] for b in index if b["batch"] not in done]
    if remaining:
        print(f"next: batch {remaining[0]} ({index[remaining[0] - 1]['topic']}, "
              f"{index[remaining[0] - 1]['n']} records)")
        print(f"remaining batches: {len(remaining)}")


def cmd_finalize(args):
    """Write screened.jsonl from the hand decisions, for the fetch stage."""
    recs, dec = load_records(), latest()
    missing = [i for i in recs if i not in dec]
    if missing and not args.allow_partial:
        sys.exit(f"{len(missing)} records still undecided; pass --allow-partial to proceed")
    n = 0
    with open(os.path.join(OUT, "screened.jsonl"), "w", encoding="utf8") as fh:
        for i, r in recs.items():
            d = dec.get(i)
            if not d:
                continue
            r["screen"] = {"decision": d["decision"], "batch": d["batch"], "by": "manual"}
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
            n += 1
    print(f"{n} screened records written to screened.jsonl")
    print(Counter(d["decision"] for d in dec.values()))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--size", type=int, default=200)
    a = sub.add_parser("abstract")
    a.add_argument("ids", nargs="+")
    a.add_argument("--chars", type=int, default=1200)
    d = sub.add_parser("decide")
    d.add_argument("--batch", type=int, required=True)
    d.add_argument("--include", default="")
    d.add_argument("--uncertain", default="")
    l = sub.add_parser("list")
    l.add_argument("--decision", default="uncertain")
    r = sub.add_parser("resolve")
    r.add_argument("--include", default="")
    r.add_argument("--exclude", default="")
    sub.add_parser("status")
    f = sub.add_parser("finalize")
    f.add_argument("--allow-partial", action="store_true")
    args = ap.parse_args()
    {"build": cmd_build, "abstract": cmd_abstract, "decide": cmd_decide,
     "list": cmd_list, "resolve": cmd_resolve,
     "status": cmd_status, "finalize": cmd_finalize}[args.cmd](args)


if __name__ == "__main__":
    main()
