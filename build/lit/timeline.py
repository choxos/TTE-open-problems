#!/usr/bin/env python3
"""Put the findings in publication order and ask what the chronology says.

The reading pools evidence per problem but throws away when it was written, and
that loses the thing a research agenda most needs to know. A gap named in 2013
and answered in 2022 is not open. A gap partly closed in 2015 and then named
again in 2024 is open despite the progress, and the entry should cite both. A
gap restated by six papers across twelve years with nothing in between is a
different kind of open from one mentioned once.

None of those are visible in a pooled count of effects. They are only visible
when each finding carries the year of the paper that made it.

Classification is mechanical and stated on the page, so a reader can disagree
with a call by looking at the same table:

  answered-later            the newest word is progress, and it postdates the
                            newest paper that called the problem open
  reasserted-after-progress later work still calls it open despite earlier
                            partial progress
  concurrent                progress and a fresh assertion of openness land in
                            the same year
  progress-only             every finding is progress; nothing calls it open
  open-only                 nothing but assertions that it is open

with two orthogonal flags:

  piecewise   two or more partial results from different papers in different
              years, so the problem is being closed in pieces
  recurrent   three or more papers across eight or more years all saying open

`answered-later` is a candidate, not a verdict. The mechanism cannot tell
whether the later paper answers the same question the earlier one asked; that
needs reading, and build/lit/verify_timeline.py puts each candidate to the
second reviewer.

Outputs:
  documentation/audit/reading/TIMELINE.md
  documentation/audit/reading/timeline.json

Usage: python3 build/lit/timeline.py
"""

import json
import os
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
REFS = os.path.join(ROOT, "documentation", "refs")

PROGRESS = ("resolves", "partially-addresses")
MARK = {"resolves": "solved", "partially-addresses": "part",
        "supports-open": "open", "contradicts": "contra"}

LONG_SPAN = 8      # years across which a restatement counts as long-standing
LONG_PAPERS = 3    # distinct papers needed before a restatement counts


def year_of(lib, pid):
    y = (lib.get(pid) or {}).get("year")
    try:
        y = int(y)
    except (TypeError, ValueError):
        return None
    # A four-digit sanity band: a stray 20 or 202 in the metadata would sort
    # ahead of everything real and silently become the "earliest" mention.
    return y if 1900 <= y <= 2100 else None


def classify(events):
    """events: list of (year, effect, paper, ...). Years are already non-null."""
    op = [e for e in events if e[1] == "supports-open"]
    pr = [e for e in events if e[1] in PROGRESS]
    if not op and not pr:
        return "other"
    if not pr:
        return "open-only"
    if not op:
        return "progress-only"
    lo, lp = max(e[0] for e in op), max(e[0] for e in pr)
    if lp > lo:
        return "answered-later"
    if lo > lp:
        return "reasserted-after-progress"
    return "concurrent"


def flags(events):
    out = []
    pr = [e for e in events if e[1] in PROGRESS]
    if len({e[2] for e in pr}) >= 2 and len({e[0] for e in pr}) >= 2:
        out.append("piecewise")
    op = [e for e in events if e[1] == "supports-open"]
    if op and len({e[2] for e in op}) >= LONG_PAPERS:
        if max(e[0] for e in op) - min(e[0] for e in op) >= LONG_SPAN:
            out.append("recurrent")
    return out


def trail(events, limit=14):
    """A compact year-ordered string: 2013 open · 2019 part · 2024 solved."""
    seen, bits = set(), []
    for y, eff, _, _ in events:
        k = (y, eff)
        if k in seen:
            continue
        seen.add(k)
        bits.append(f"{y} {MARK.get(eff, eff)}")
    if len(bits) > limit:
        bits = bits[:limit - 1] + ["…"]
    return " · ".join(bits)


def main():
    lib = {c["id"]: c for c in
           json.load(open(os.path.join(REFS, "library.json"), encoding="utf8"))}
    problems = {p["id"]: p for p in json.load(open(
        os.path.join(AUDIT, "registry", "problems.json"), encoding="utf8"))}
    changes = json.load(open(os.path.join(READING, "proposed-changes.json"),
                             encoding="utf8"))["changes"]

    rows, undated = [], 0
    for ch in changes:
        events = []
        for f in ch["findings"]:
            y = year_of(lib, f.get("paper"))
            if y is None:
                undated += 1
                continue
            events.append((y, f.get("effect"), f.get("paper"),
                           f.get("paper_title") or ""))
        if not events:
            continue
        events.sort(key=lambda e: (e[0], e[1]))
        p = problems.get(ch["id"], {})
        yrs = [e[0] for e in events]
        rows.append({
            "id": ch["id"],
            "title": ch["title"],
            "category": p.get("category"),
            "verdict": ch.get("current_verdict"),
            "class": classify(events),
            "flags": flags(events),
            "papers": len({e[2] for e in events}),
            "first": min(yrs),
            "last": max(yrs),
            "span": max(yrs) - min(yrs),
            "trail": trail(events),
            "events": [{"year": y, "effect": e, "paper": pa, "paper_title": t}
                       for y, e, pa, t in events],
        })

    rows.sort(key=lambda r: (-r["span"], -r["papers"], r["id"]))
    by_class = defaultdict(list)
    for r in rows:
        by_class[r["class"]].append(r)

    # ---- when the corpus itself was written --------------------------------
    per_year = defaultdict(Counter)
    for r in rows:
        for e in r["events"]:
            per_year[e["year"]][e["effect"]] += 1

    json.dump({"problems": rows, "by_year": {str(y): dict(c) for y, c in
                                             sorted(per_year.items())}},
              open(os.path.join(READING, "timeline.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    # ---- the page ----------------------------------------------------------
    L = ["# The chronology of the evidence", "",
         f"{len(rows)} registered problems carry at least one dated finding. "
         f"Every finding is stamped with the publication year of the paper that "
         f"made it, so a problem's evidence reads as a sequence rather than a "
         f"pile. {undated} findings come from papers with no usable year and are "
         f"excluded here; they are still counted everywhere else.", "",
         "This asks three questions a pooled count cannot: has a later paper "
         "answered what an earlier one left open, is a problem being closed in "
         "pieces by different papers, and is a problem being restated across "
         "years with nothing happening in between.", "",
         "| class | meaning | n |", "|---|---|---:|"]
    MEANING = {
        "answered-later": "the newest word is progress, and it postdates every "
                          "paper that called the problem open",
        "reasserted-after-progress": "later work still calls it open despite "
                                     "earlier partial progress",
        "concurrent": "progress and a fresh assertion of openness in the same year",
        "progress-only": "every finding is progress; nothing calls it open",
        "open-only": "nothing but assertions that it is open",
    }
    for k in ("answered-later", "reasserted-after-progress", "concurrent",
              "progress-only", "open-only"):
        if by_class.get(k):
            L.append(f"| `{k}` | {MEANING[k]} | {len(by_class[k])} |")

    piecewise = [r for r in rows if "piecewise" in r["flags"]]
    recurrent = [r for r in rows if "recurrent" in r["flags"]]
    L += ["", f"Two flags cut across those classes: **{len(piecewise)} problems "
          f"are being closed in pieces** (two or more partial results from "
          f"different papers in different years), and **{len(recurrent)} are "
          f"recurrent** (three or more papers across {LONG_SPAN} or more years, "
          f"all saying open).", ""]

    def table(rs, cols=("id", "verdict", "papers", "span", "trail"), n=None):
        head = {"id": "problem", "verdict": "registry says", "papers": "papers",
                "span": "span", "trail": "chronology"}
        out = ["| " + " | ".join(head[c] for c in cols) + " |",
               "|" + "|".join("---" for c in cols) + "|"]
        for r in (rs[:n] if n else rs):
            cell = {"id": f"{r['id']} {(r['title'] or '')[:58]}",
                    "verdict": r["verdict"], "papers": str(r["papers"]),
                    "span": f"{r['first']}–{r['last']}" if r["span"] else str(r["first"]),
                    "trail": r["trail"]}
            out.append("| " + " | ".join(cell[c] for c in cols) + " |")
        return out

    if by_class.get("answered-later"):
        rs = sorted(by_class["answered-later"], key=lambda r: -r["span"])
        L += ["## The newest word is progress", "",
              f"{len(rs)} problems where the most recent paper to touch the "
              f"problem reports progress on it, and every paper calling it open "
              f"is older. This is the strongest chronological reason to revisit "
              f"a verdict, and it is only a candidate: the mechanism cannot tell "
              f"whether the later paper answers the same question the earlier "
              f"one asked. `build/lit/verify_timeline.py` puts each of these to "
              f"the second reviewer.", ""] + table(rs) + [""]

    if by_class.get("reasserted-after-progress"):
        rs = sorted(by_class["reasserted-after-progress"], key=lambda r: -r["span"])
        L += ["## Reasserted after progress", "",
              f"{len(rs)} problems where partial progress is on the record and a "
              f"later paper still calls the problem open. These are the entries "
              f"most likely to be reported as settled by someone reading only "
              f"the newest method paper, and the ones whose prior-work section "
              f"should cite both.", ""] + table(rs) + [""]

    if piecewise:
        L += ["## Being closed in pieces", "",
              f"{len(piecewise)} problems have partial results from two or more "
              f"papers in different years. Each solved a part; the entry should "
              f"say which parts are done and which are not, rather than carrying "
              f"one undifferentiated verdict.", ""] + table(
                  sorted(piecewise, key=lambda r: -r["papers"])) + [""]

    if recurrent:
        # Recurrent and untouched is the stronger claim, and the one worth
        # leading with: the flag alone only says a gap was restated, not that
        # nothing happened in between.
        untouched = [r for r in recurrent
                     if not any(e["effect"] in PROGRESS for e in r["events"])]
        alongside = [r for r in recurrent if r not in untouched]
        L += ["## Restated across the years, with nothing in between", "",
              f"{len(untouched)} problems were called open by at least "
              f"{LONG_PAPERS} papers spanning at least {LONG_SPAN} years, and no "
              f"paper in the corpus reports any progress on them at all. "
              f"Independent restatement over a long period, by authors who mostly "
              f"do not cite each other, is the strongest evidence this reading can "
              f"give that a gap is real and not an artifact of one author's "
              f"framing.", ""] + table(
                  sorted(untouched, key=lambda r: (-r["span"], -r["papers"]))) + [""]
        if alongside:
            L += ["## Restated across the years, alongside partial progress", "",
                  f"{len(alongside)} more were restated on the same scale but do "
                  f"have progress on the record. The restatement is what matters "
                  f"here: later authors kept finding the gap after the partial "
                  f"results were published.", ""] + table(
                      sorted(alongside, key=lambda r: (-r["span"], -r["papers"]))) + [""]

    L += ["## Findings by publication year", "",
          "What the corpus says about these problems, by the year it was said. ",
          "", "| year | open | partial | resolves | contradicts |",
          "|---|---:|---:|---:|---:|"]
    for y, c in sorted(per_year.items()):
        L.append(f"| {y} | {c['supports-open']} | {c['partially-addresses']} | "
                 f"{c['resolves']} | {c['contradicts']} |")

    open(os.path.join(READING, "TIMELINE.md"), "w", encoding="utf8").write(
        "\n".join(L) + "\n")

    print(f"{len(rows)} problems with dated evidence ({undated} findings undated)")
    for k in ("answered-later", "reasserted-after-progress", "concurrent",
              "progress-only", "open-only"):
        if by_class.get(k):
            print(f"  {k:26s} {len(by_class[k])}")
    print(f"  piecewise                  {len(piecewise)}")
    print(f"  recurrent                  {len(recurrent)}"
          f" ({sum(1 for r in recurrent if not any(e['effect'] in PROGRESS for e in r['events']))}"
          f" with no progress at all)")
    for r in sorted(by_class.get("answered-later", []), key=lambda r: -r["span"])[:12]:
        print(f"  >> {r['id']:8s} {r['first']}–{r['last']}  {r['trail'][:70]}")


if __name__ == "__main__":
    main()
