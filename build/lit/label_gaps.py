#!/usr/bin/env python3
"""Attach every future-research gap to a theme, so gaps can be read in time order.

Each paper names the gaps it leaves behind, in its own words. Across the corpus
the same gap is named again and again by authors who never cite each other, and
that repetition is the most interesting thing the reading produces: a gap three
groups name independently over a decade is real in a way that one author's
closing paragraph is not. None of it is visible while the gaps sit as free text
under the paper that wrote them.

Clustering the text does not work. A recurrence is a paraphrase, not a near
duplicate: "the correlation between components is not identifiable from
aggregate data" and "we could not estimate how components interact without
patient-level data" share almost no words and are the same gap. Word overlap
found nothing when it was tried on the proposed new problems, and there are far
more gaps here.

So this labels instead of clusters. The label set is fixed and already exists:
the registered problems, plus the new problems the reading proposed and the
reviewer accepted. A model reads each gap and names the theme it belongs to, or
`none` when it belongs to no theme in the set. That is a bounded judgement per
gap rather than an open-ended similarity search over thousands of pairs.

With every gap carrying a theme and every paper carrying a year, the chronology
falls out: which themes were named in which years, by how many independent
papers, and whether any paper in the corpus later reported progress on them.

Usage:
  python3 build/lit/label_gaps.py --build --batches 12   # payloads for the labellers
  python3 build/lit/label_gaps.py --report               # the chronology
"""

import argparse
import glob
import json
import os
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
GAPS = os.path.join(READING, "gaps")
REFS = os.path.join(ROOT, "documentation", "refs")

PROGRESS = ("resolves", "partially-addresses")


def library():
    return {c["id"]: c for c in
            json.load(open(os.path.join(REFS, "library.json"), encoding="utf8"))}


def year_of(lib, pid):
    try:
        y = int((lib.get(pid) or {}).get("year"))
    except (TypeError, ValueError):
        return None
    return y if 1900 <= y <= 2100 else None


def labels():
    """The theme set: registered problems plus accepted new ones.

    A new problem gets an id of the form NEW-07 from its position in the
    clustering, so a gap can be attached to something the registry does not yet
    contain. Without that, every gap pointing at a genuinely unregistered theme
    would land in `none` and the most interesting recurrences would be invisible.
    """
    out = []
    for p in json.load(open(os.path.join(AUDIT, "registry", "problems.json"),
                            encoding="utf8")):
        out.append({"id": p["id"], "title": p.get("title"),
                    "gist": (p.get("statement") or "")[:220]})
    path = os.path.join(READING, "proposed-changes.json")
    if os.path.exists(path):
        for i, c in enumerate(json.load(open(path, encoding="utf8"))
                              .get("new_problem_clusters") or [], 1):
            out.append({"id": f"NEW-{i:02d}",
                        "title": c.get("title") or (c.get("members") or [{}])[0]
                        .get("proposed_title"),
                        "gist": (c.get("statement") or "")[:220]})
    return out


def all_gaps(lib):
    gaps = []
    dup = {c["id"] for c in lib.values() if c.get("duplicate_of")}
    for f in sorted(glob.glob(os.path.join(READING, "findings", "*.json"))):
        d = json.load(open(f, encoding="utf8"))
        for p in d.get("papers", []):
            if p.get("id") in dup or not p.get("read"):
                continue
            # A retracted paper's call for future work is not a research agenda.
            if (lib.get(p["id"]) or {}).get("status") in ("retracted", "notice"):
                continue
            for j, g in enumerate(p.get("future_research") or []):
                gaps.append({
                    "gap_id": f"{p['id']}#{j}",
                    "paper": p["id"],
                    "year": year_of(lib, p["id"]),
                    "paper_title": (p.get("title") or "")[:120],
                    "kind": g.get("kind"),
                    "gap": g.get("gap"),
                })
    return gaps


def build(n_batches):
    lib = library()
    gaps, lab = all_gaps(lib), labels()
    os.makedirs(os.path.join(GAPS, "labels"), exist_ok=True)
    for f in glob.glob(os.path.join(GAPS, "batch_*.json")):
        os.remove(f)

    json.dump(lab, open(os.path.join(GAPS, "themes.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    # Round-robin, not contiguous slices: consecutive gaps come from one paper,
    # so a slice would hand one labeller a whole subject area and leave another
    # with none. Every labeller should see the same mix.
    size = -(-len(gaps) // n_batches)
    for b in range(n_batches):
        chunk = gaps[b::n_batches]
        bid = f"{b + 1:02d}"
        json.dump({"batch": bid,
                   "themes": "documentation/audit/reading/gaps/themes.json",
                   "output": f"documentation/audit/reading/gaps/labels/{bid}.json",
                   "gaps": chunk},
                  open(os.path.join(GAPS, f"batch_{bid}.json"), "w", encoding="utf8"),
                  indent=1, ensure_ascii=False)
    print(f"{len(gaps)} gaps, {len(lab)} themes, {n_batches} batches "
          f"(~{size} gaps each)")
    print(f"  themes:  {os.path.relpath(os.path.join(GAPS, 'themes.json'), ROOT)}")
    print(f"  batches: {os.path.relpath(GAPS, ROOT)}/batch_NN.json")


def report():
    lib = library()
    gaps = {g["gap_id"]: g for g in all_gaps(lib)}
    lab = {t["id"]: t for t in labels()}

    seen = {}
    for f in sorted(glob.glob(os.path.join(GAPS, "labels", "*.json"))):
        for r in json.load(open(f, encoding="utf8")).get("labels", []):
            if r.get("gap_id") in gaps:
                seen[r["gap_id"]] = r
    if not seen:
        sys.exit("no labels yet; run --build, label the batches, then --report")

    # Where the corpus says progress was made, and when.
    prog = defaultdict(list)
    ch = json.load(open(os.path.join(READING, "proposed-changes.json"),
                        encoding="utf8"))["changes"]
    for c in ch:
        for f in c["findings"]:
            if f.get("effect") in PROGRESS:
                y = year_of(lib, f.get("paper"))
                if y:
                    prog[c["id"]].append((y, f.get("paper"), f.get("paper_title")))

    by_theme = defaultdict(list)
    for gid, r in seen.items():
        t = r.get("theme")
        if t and t != "none":
            by_theme[t].append(gaps[gid])

    rows = []
    for t, gs in by_theme.items():
        yrs = sorted({g["year"] for g in gs if g["year"]})
        papers = {g["paper"] for g in gs}
        pr = sorted(prog.get(t, []))
        rows.append({
            "theme": t,
            "title": (lab.get(t) or {}).get("title") or t,
            "gaps": len(gs), "papers": len(papers),
            "first": yrs[0] if yrs else None, "last": yrs[-1] if yrs else None,
            "span": (yrs[-1] - yrs[0]) if len(yrs) > 1 else 0,
            "years": yrs,
            "progress_years": sorted({y for y, _, _ in pr}),
            # Named as open by a paper published after the newest paper that
            # reported progress: the restatement is not ignorance of the earlier
            # work, it is a later author still finding the gap there.
            "restated_after_progress": bool(pr and yrs and yrs[-1] > max(y for y, _, _ in pr)),
        })
    rows.sort(key=lambda r: (-r["papers"], -(r["span"] or 0)))

    json.dump({"themes": rows, "labelled": len(seen), "gaps": len(gaps)},
              open(os.path.join(READING, "gap-chronology.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    unlabelled = len(gaps) - len(seen)
    none_ = sum(1 for r in seen.values() if r.get("theme") in (None, "none"))
    recur = [r for r in rows if r["papers"] >= 3 and r["span"] >= 8]
    unmoved = [r for r in recur if not r["progress_years"]]
    after = [r for r in rows if r["restated_after_progress"] and r["papers"] >= 2]

    L = ["# The same gap, named again and again", "",
         f"{len(gaps)} future-research gaps were read out of the papers that "
         f"named them and attached to a theme: a registered problem, or one of "
         f"the new problems the reading proposed and the reviewer accepted. "
         f"{len(seen) - none_} landed on a theme, {none_} on none, and "
         f"{unlabelled} are unlabelled.", "",
         f"With a theme on every gap and a year on every paper, a gap stops "
         f"being one author's closing paragraph and becomes a record of who "
         f"asked for what, and when. {len(rows)} themes were named by at least "
         f"one paper.", "",
         f"**{len(recur)} themes were named by three or more papers across eight "
         f"or more years**, and **{len(unmoved)} of those have no paper in the "
         f"corpus reporting any progress at all**. Independent restatement over "
         f"a long period, by authors who mostly do not cite each other, is the "
         f"strongest evidence this reading can produce that a gap is real rather "
         f"than one group's framing.", ""]

    def tbl(rs, n=None):
        out = ["| theme | papers | asked in | progress reported |",
               "|---|---:|---|---|"]
        for r in (rs[:n] if n else rs):
            ys = ", ".join(str(y) for y in r["years"][:12]) + \
                 ("…" if len(r["years"]) > 12 else "")
            pg = ", ".join(str(y) for y in r["progress_years"]) or "none"
            out.append(f"| {r['theme']} {(r['title'] or '')[:52]} | "
                       f"{r['papers']} | {ys} | {pg} |")
        return out

    if unmoved:
        L += ["## Named repeatedly across the years, never moved", ""] + \
             tbl(sorted(unmoved, key=lambda r: (-r["papers"], -r["span"]))) + [""]
    if after:
        L += ["## Named as open after the progress was published", "",
              f"{len(after)} themes were named as open by a paper published "
              f"later than the newest paper reporting progress on them. The "
              f"restatement is not ignorance of the earlier work; it is a later "
              f"author still finding the gap there.", ""] + \
             tbl(sorted(after, key=lambda r: -r["papers"])) + [""]

    L += ["## Every theme by how many papers named it", ""] + tbl(rows) + [""]

    open(os.path.join(READING, "GAP-CHRONOLOGY.md"), "w", encoding="utf8").write(
        "\n".join(L) + "\n")
    print(f"{len(seen)}/{len(gaps)} gaps labelled, {none_} on no theme")
    print(f"  themes named            {len(rows)}")
    print(f"  recurrent (3+ papers, 8+ yrs)  {len(recur)}")
    print(f"  of those, no progress   {len(unmoved)}")
    print(f"  restated after progress {len(after)}")
    for r in sorted(unmoved, key=lambda r: -r["papers"])[:12]:
        print(f"  >> {r['theme']:8s} {r['papers']:2d} papers {r['first']}-{r['last']}"
              f"  {(r['title'] or '')[:52]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--batches", type=int, default=12)
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if args.build:
        build(args.batches)
    if args.report:
        report()
    if not (args.build or args.report):
        sys.exit("pass --build or --report")


if __name__ == "__main__":
    main()
