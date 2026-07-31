#!/usr/bin/env python3
"""Render one summary per article: what it did, and what it said still needs doing.

The reading agents produce structured findings; this turns them into something a
person reads. Each article gets what was done, the gaps its own authors named
(quoted, so the claim is theirs and not ours), and the registered problems it
bears on.

Output: documentation/refs/SUMMARIES.md, plus summaries.json for downstream use.

Usage: python3 build/lit/write_summaries.py
"""

import glob
import json
import os
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REFS = os.path.join(ROOT, "documentation", "refs")
READING = os.path.join(ROOT, "documentation", "audit", "reading")

EFFECT_MARK = {"resolves": "resolves", "partially-addresses": "partly addresses",
               "contradicts": "contradicts", "supports-open": "confirms open"}

FLAGGED = {
    "retracted": "This paper has been retracted.",
    "concern": "This paper carries an expression of concern.",
    "corrected-republished": "This paper was corrected and republished.",
    "notice": "This record is a correction or retraction notice, not a paper.",
}


def main():
    lib = {c["id"]: c for c in
           json.load(open(os.path.join(REFS, "library.json"), encoding="utf8"))}
    problems = {x["id"]: x for x in json.load(open(
        os.path.join(ROOT, "documentation", "audit", "registry", "problems.json"),
        encoding="utf8"))}

    papers = []
    for path in sorted(glob.glob(os.path.join(READING, "findings", "*.json"))):
        d = json.load(open(path, encoding="utf8"))
        for p in d.get("papers", []):
            p["batch"] = d.get("batch")
            papers.append(p)

    # One entry can be read twice if a batch was re-run; the later file wins.
    # A paper catalogued twice under two ids is a different problem, and would
    # otherwise appear as two articles saying the same thing. See
    # build/lit/fix_years.py for how those are found.
    by_id = {}
    for p in papers:
        if lib.get(p["id"], {}).get("duplicate_of"):
            continue
        by_id[p["id"]] = p
    papers = list(by_id.values())

    def sort_key(p):
        c = lib.get(p["id"], {})
        return (c.get("topic") or "zz", -int(c.get("year") or 0),
                (p.get("title") or "").lower())

    papers.sort(key=sort_key)
    json.dump(papers, open(os.path.join(REFS, "summaries.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    flagged = [p for p in papers if lib.get(p["id"], {}).get("status") in FLAGGED]
    gaps = sum(len(p.get("future_research") or []) for p in papers
               if lib.get(p["id"], {}).get("status") not in FLAGGED)
    lines = ["# Article summaries", "",
             f"{len(papers)} articles read in full. For each: what the work did, "
             f"the future research its own authors called for, and the registered "
             f"open problems it bears on. Every gap carries the authors' own words; "
             f"`stated` means they named it, `implied` means it follows from what "
             f"they did without being named.", "",
             f"{gaps} future-research gaps recorded across the set."
             + (f" {len(flagged)} articles are retracted, carry an expression of "
                f"concern, or are correction notices rather than papers; they are "
                f"kept for the record, marked in place, and their gaps are "
                f"excluded from that count." if flagged else ""), ""]

    by_topic = defaultdict(list)
    for p in papers:
        by_topic[(lib.get(p["id"], {}).get("topic") or "other")].append(p)

    lines += ["| set | articles | gaps recorded |", "|---|---:|---:|"]
    for t, ps in sorted(by_topic.items()):
        lines.append(f"| {t} | {len(ps)} | "
                     f"{sum(len(x.get('future_research') or []) for x in ps if lib.get(x['id'], {}).get('status') not in FLAGGED)} |")
    lines.append("")

    for topic, ps in sorted(by_topic.items()):
        lines += [f"## {topic}", ""]
        for p in ps:
            c = lib.get(p["id"], {})
            head = f"### {p.get('title') or c.get('title') or p['id']}"
            lines.append(head)
            bits = [b for b in (c.get("year"), c.get("journal"),
                                (f"doi:{p['doi']}" if p.get("doi") else None),
                                f"relevance {p.get('relevance')}") if b]
            lines += ["", "*" + " · ".join(str(b) for b in bits) + "*", ""]
            # A retracted paper's own call for future work is not a research
            # agenda, and a reader of this file must not have to know that
            # separately. See build/lit/retractions.py.
            if c.get("status") in FLAGGED:
                lines += [f"> **{FLAGGED[c['status']]}** "
                          "Nothing below is treated as evidence.", ""]
            if not p.get("read", True):
                lines += ["Not read: " + (p.get("one_line") or "extraction failed"), ""]
                continue
            lines += ["**What was done.** " + (p.get("what_was_done")
                                               or p.get("one_line") or ""), ""]
            fr = p.get("future_research") or []
            if fr:
                lines += ["**What is still open, in the authors' terms.**", ""]
                for g in fr:
                    q = (g.get("quote") or "").strip().replace("\n", " ")
                    loc = f" ({g['locator']})" if g.get("locator") else ""
                    lines.append(f"- {g.get('gap')} [{g.get('kind')}]")
                    if q:
                        lines.append(f"  > {q[:400]}{loc}")
                lines.append("")
            else:
                lines += ["**What is still open, in the authors' terms.** "
                          "The paper names no specific gap.", ""]
            fnd = p.get("problems") or []
            if fnd:
                lines += ["**Bears on.** " + ", ".join(
                    f"{f['problem_id']} ({EFFECT_MARK.get(f['effect'], f['effect'])})"
                    for f in fnd), ""]
            np_ = p.get("new_problems") or []
            if np_:
                lines += ["**Raises, not yet in the registry.** " + "; ".join(
                    (n.get("proposed_title") or "") for n in np_), ""]

    out = os.path.join(REFS, "SUMMARIES.md")
    open(out, "w", encoding="utf8").write("\n".join(lines) + "\n")
    print(f"{len(papers)} article summaries -> {os.path.relpath(out, ROOT)}")
    print(f"  future-research gaps: {gaps}")
    rel = Counter(p.get("relevance") for p in papers)
    for k, v in rel.most_common():
        print(f"  relevance {k or '?':8s} {v}")
    print(f"  size: {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
