#!/usr/bin/env python3
"""Combine the paper readings with the second reviewer's verdicts.

A finding counts only if both models back it. Where they disagree the reviewer's
call stands, because it saw the registered problem statement and the quote side
by side and was asked specifically to be hard on claims that retire a problem.

Nothing here edits the registry. It produces the change set that would be applied
so it can be read before it is.

Output: reading/proposed-changes.json and reading/PROPOSED.md

Usage: python3 build/lit/merge_review.py
"""

import glob
import json
import os
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")

# What a surviving claim implies for a problem whose verdict is currently open.
IMPLIES = {
    "resolves": "resolved-since-report",
    "contradicts": "not-supported",
    "partially-addresses": "partially-addressed",
}

# How many `supports-open` findings on an `overstated` problem are enough to ask
# whether the downgrade was right. One or two are consistent with a real but
# narrower core; a pile of them is not.
REOPEN_WEIGHT = 5


def cluster_new_problems(items):
    """Attach the grouping produced by build/lit/dedupe_new_problems.py.

    Grouping is not done here. Readers working on disjoint papers propose the
    same gap in different words and under different category codes, and word
    overlap cannot tell those apart: every proposal shares the same domain
    vocabulary, so across this set a pair saying the same thing scores lower
    than a pair about different things. It is a semantic judgement, made by a
    model that sees all the proposals at once, and read back here.

    Until that has run, every proposal stands alone, which over-counts the
    additions rather than silently merging two real gaps into one.
    """
    path = os.path.join(READING, "review", "new-problem-groups.json")
    if not os.path.exists(path):
        return [{"title": n.get("proposed_title"), "category": n.get("category"),
                 "statement": n.get("statement"), "why_open": n.get("why_open"),
                 "proposed_by": 1, "grouped": False,
                 "batches": [n["batch"]] if n.get("batch") else [],
                 "papers": [(n.get("paper_title") or "")[:70]],
                 "members": [n]} for n in items]

    groups = json.load(open(path, encoding="utf8"))["groups"]
    out = []
    for g in groups:
        members = [items[i] for i in g.get("members", []) if i < len(items)]
        if not members:
            continue
        out.append({
            "title": g.get("title"),
            "category": g.get("category"),
            "statement": g.get("statement"),
            "why_open": g.get("why_open"),
            "rationale": g.get("rationale"),
            "proposed_by": len(members),
            "grouped": True,
            "batches": sorted({m.get("batch") for m in members if m.get("batch")}),
            "papers": sorted({(m.get("paper_title") or "")[:70] for m in members}),
            "merge_into": sorted({m["merge_into"] for m in members
                                  if m.get("merge_into")}),
            "members": members,
        })
    out.sort(key=lambda c: (-c["proposed_by"], c["category"] or "", c["title"] or ""))
    return out


def main():
    problems = {x["id"]: x for x in json.load(
        open(os.path.join(AUDIT, "registry", "problems.json"), encoding="utf8"))}
    agg = json.load(open(os.path.join(READING, "aggregate.json"), encoding="utf8"))

    verdicts = []
    for f in sorted(glob.glob(os.path.join(READING, "review", "verdict-*.json"))):
        verdicts += json.load(open(f, encoding="utf8"))["verdicts"]

    # Key a review back to its finding by problem id plus the quote it was shown.
    reviewed = {}
    for v in verdicts:
        it = v.get("item") or {}
        if it.get("kind") == "finding":
            reviewed[(it.get("problem_id"), (it.get("quote") or "")[:120])] = v
        elif it.get("kind") == "new-problem":
            reviewed[("NEW", (it.get("quote") or "")[:120])] = v

    kept, dropped, weakened = [], [], []
    for f in agg["findings"]:
        r = reviewed.get((f.get("problem_id"), (f.get("quote") or "")[:120]))
        if r is None:
            # Not sent for review: supports-open reinforces the status quo and
            # cannot retire a problem, so it stands on the reader alone.
            f["review"] = "not-reviewed"
            kept.append(f)
            continue
        f["review"] = r["verdict"]
        f["review_reason"] = r.get("reason")
        if r["verdict"] == "reject":
            dropped.append(f)
        elif r["verdict"] == "downgrade":
            f["effect_original"] = f["effect"]
            f["effect"] = "supports-open"
            f["downgrade_note"] = r.get("corrected_effect")
            weakened.append(f)
            kept.append(f)
        else:
            kept.append(f)

    new_kept, new_dropped = [], []
    for n in agg["new_problems"]:
        r = reviewed.get(("NEW", (n.get("quote") or "")[:120]))
        n["review"] = r["verdict"] if r else "not-reviewed"
        n["review_reason"] = r.get("reason") if r else None
        if r and r.get("merge_into"):
            n["merge_into"] = r["merge_into"]
        (new_dropped if r and r["verdict"] == "reject" else new_kept).append(n)

    # ---- what would change --------------------------------------------------
    by_problem = defaultdict(list)
    for f in kept:
        by_problem[f["problem_id"]].append(f)

    # A finding is reviewed on its own terms: does this paper partly address this
    # problem? That is not the same question as whether the later paper answers
    # what the earlier one left open, and the two can disagree. Where
    # build/lit/verify_timeline.py put a problem's older and newer claims side by
    # side and the reviewer said the later work is about a different question, or
    # does not answer it, that judgement is the more specific one and wins: it
    # was made with both sides of the problem's history in view.
    blocked = {}
    for f in glob.glob(os.path.join(READING, "review",
                                    "verdict-timeline-*.json")):
        for v in json.load(open(f, encoding="utf8"))["verdicts"]:
            it = v.get("item") or {}
            if it.get("problem_id") and v.get("verdict") in ("no",
                                                             "different-question"):
                blocked[it["problem_id"]] = v

    changes = []
    for pid, fs in sorted(by_problem.items()):
        p = problems.get(pid)
        if not p:
            continue
        strong = [f for f in fs if f["effect"] in IMPLIES]
        proposed, drivers, papers = None, 0, []
        thin_note = None
        if strong and pid not in blocked:
            rank = ["resolves", "contradicts", "partially-addresses"]
            best = min(strong, key=lambda f: rank.index(f["effect"]))
            want = IMPLIES[best["effect"]]
            if p.get("verdict") != want and p.get("verdict") in (
                    "confirmed-open", "unverifiable"):
                proposed = want
                # Only findings with the triggering effect argue for the flip.
                # The rest are `supports-open` and argue the opposite way, so
                # reporting the total as the flip's evidence overstates it.
                on = [f for f in strong if f["effect"] == best["effect"]]
                # One paper, and the reader that read it was not sure. That is
                # the thinnest evidence the pipeline can produce, and it would
                # move a headline verdict off `confirmed-open`, which is the
                # claim a reader of the catalog acts on. Corroboration or
                # conviction is required; one hedged reading is neither.
                if len(on) == 1 and on[0].get("confidence") == "low":
                    proposed = None
                    thin_note = on[0]
                else:
                    drivers = len(on)
                    papers = sorted({(f.get("paper_title") or "")[:60] for f in on})
        changes.append({
            "id": pid,
            "title": p.get("title"),
            "current_verdict": p.get("verdict"),
            "proposed_verdict": proposed,
            "flip_drivers": drivers,
            "flip_papers": papers,
            "flip_blocked_as_thin": (
                {"paper": thin_note.get("paper_title"),
                 "confidence": thin_note.get("confidence"),
                 "evidence": thin_note.get("evidence")} if thin_note else None),
            "flip_blocked_by_timeline": (
                {"verdict": blocked[pid].get("verdict"),
                 "confidence": blocked[pid].get("confidence"),
                 "reason": blocked[pid].get("reason")} if pid in blocked else None),
            "evidence_count": len(fs),
            "effects": dict(Counter(f["effect"] for f in fs)),
            "new_citations": sorted({f.get("doi") for f in fs if f.get("doi")}),
            "findings": fs,
        })

    # ---- evidence pointing the other way ------------------------------------
    # Everything above can only move a problem toward `partially-addressed`. The
    # reading can equally find that a problem the earlier audit closed is alive,
    # and that never surfaced: a `supports-open` finding on a closed problem was
    # counted and then ignored. The two closed verdicts do not mean the same
    # thing, so they are not pooled. `not-supported` says the problem could not
    # be substantiated at all, and any solid evidence for it is a contradiction
    # worth acting on. `overstated` says the core is real but the severity claim
    # was too strong, so evidence often just confirms that narrower core; only a
    # weight of it suggests the downgrade went too far.
    reopen = []
    for c in changes:
        v = c["current_verdict"]
        so = c["effects"].get("supports-open", 0)
        if not so:
            continue
        if v == "not-supported":
            reopen.append({**{k: c[k] for k in
                              ("id", "title", "current_verdict", "evidence_count")},
                           "supports_open": so, "kind": "contradicts-closure",
                           "note": "closed as unsubstantiated, yet the reading "
                                   "found evidence it is real"})
        elif v in ("overstated", "resolved-since-report") and so >= REOPEN_WEIGHT:
            reopen.append({**{k: c[k] for k in
                              ("id", "title", "current_verdict", "evidence_count")},
                           "supports_open": so, "kind": "weight-of-evidence",
                           "note": f"{so} findings confirm the gap; check the "
                                   "downgrade still fits"})
    reopen.sort(key=lambda r: (r["kind"] != "contradicts-closure",
                               -r["supports_open"]))

    # ---- problems the reading disagrees with itself about --------------------
    # A `contradicts` says the problem's premise is false; a `supports-open` on
    # the same problem says it is real. Both surviving means two readers on two
    # papers reached opposite conclusions, and the counts alone hide it: the
    # verdict logic takes the strongest claim and moves on. These are the rows
    # where reading the underlying papers is not optional.
    disputed = []
    for c in changes:
        e = c["effects"]
        against = e.get("contradicts", 0)
        forr = e.get("supports-open", 0) + e.get("partially-addresses", 0)
        if against and forr:
            disputed.append({
                **{k: c[k] for k in ("id", "title", "current_verdict")},
                "contradicts": against, "supports": forr,
                "papers": [{"effect": f["effect"],
                            "paper": (f.get("paper_title") or "")[:70],
                            "evidence": (f.get("evidence") or "")[:300]}
                           for f in c["findings"]
                           if f["effect"] in ("contradicts", "supports-open",
                                              "partially-addresses")],
            })

    clusters = cluster_new_problems(new_kept)
    out = {"changes": changes, "new_problems": new_kept,
           "new_problem_clusters": clusters, "reopen_candidates": reopen,
           "disputed": disputed,
           "rejected_findings": dropped, "rejected_new_problems": new_dropped}
    json.dump(out, open(os.path.join(READING, "proposed-changes.json"), "w",
                        encoding="utf8"), indent=1, ensure_ascii=False)

    flips = [c for c in changes if c["proposed_verdict"]]
    lines = ["# Proposed changes from the reading so far", "",
             f"{len(agg['papers'])} papers read. {len(kept)} findings survive both "
             f"the reader and the second reviewer; {len(dropped)} were rejected on "
             f"review and {len(weakened)} were weakened to `supports-open`. "
             f"{len(by_problem)} of {len(problems)} registered problems gained "
             f"evidence.", "",
             f"{len(new_kept)} proposed new problems survive, {len(new_dropped)} "
             f"were rejected.", "",
             "## Verdict changes proposed", ""]
    if flips:
        thin = [c for c in flips if c["flip_drivers"] < 2]
        lines += [f"`for` counts only the findings with the effect that triggers "
                  f"the change; `against` counts the `supports-open` findings on "
                  f"the same problem, which argue it is still open. "
                  f"{len(thin)} of these {len(flips)} rest on a single paper and "
                  f"should be read before being applied.", "",
                  "| id | title | from | to | for | against |",
                  "|---|---|---|---|---:|---:|"]
        for c in sorted(flips, key=lambda c: (c["flip_drivers"], c["id"])):
            lines.append(f"| {c['id']} | {(c['title'] or '')[:66]} | "
                         f"{c['current_verdict']} | {c['proposed_verdict']} | "
                         f"{c['flip_drivers']} | "
                         f"{c['effects'].get('supports-open', 0)} |")
    else:
        lines.append("None. Every problem with new evidence keeps its verdict.")

    multi = [c for c in clusters if c["proposed_by"] > 1]
    grouped = any(c.get("grouped") for c in clusters)
    head = (f"{len(new_kept)} proposals collapse to {len(clusters)} distinct gaps. "
            f"{len(multi)} of those were proposed independently by more than one "
            f"reader working on a different set of papers, which is the strongest "
            f"signal in this set that the gap is real and not an artifact of one "
            f"paper's framing."
            if grouped else
            f"{len(new_kept)} proposals, not yet grouped: run "
            f"`build/lit/dedupe_new_problems.py`. Until then each is listed "
            f"separately and the same gap may appear more than once.")
    if disputed:
        lines += ["", "## Problems the reading disagrees with itself about", "",
                  f"{len(disputed)} problems drew both a surviving `contradicts` "
                  f"and evidence that they are real, from different papers. The "
                  f"verdict logic takes the strongest claim, so the disagreement "
                  f"does not otherwise show. Read the papers before acting on "
                  f"these.", "",
                  "| id | verdict | against | for | title |",
                  "|---|---|---:|---:|---|"]
        for r in disputed:
            lines.append(f"| {r['id']} | {r['current_verdict']} | "
                         f"{r['contradicts']} | {r['supports']} | "
                         f"{(r['title'] or '')[:60]} |")
        for r in disputed:
            lines += ["", f"**{r['id']} — {r['title']}**", ""]
            for p_ in r["papers"]:
                lines.append(f"- `{p_['effect']}` *{p_['paper']}*: {p_['evidence']}")

    if reopen:
        hard = [r for r in reopen if r["kind"] == "contradicts-closure"]
        lines += ["", "## Problems the reading argues are still open", "",
                  f"{len(reopen)} problems carry a verdict saying they are not "
                  f"open, yet gained `supports-open` evidence. "
                  f"{len(hard)} are marked `not-supported`, meaning the earlier "
                  f"audit could not substantiate them at all; evidence there "
                  f"contradicts the closure directly. The rest are `overstated`, "
                  f"where a real but narrower core is expected to attract some "
                  f"evidence, so only {REOPEN_WEIGHT} or more findings are "
                  f"listed.", "",
                  "| id | verdict | supports-open | title |", "|---|---|---:|---|"]
        for r in reopen:
            lines.append(f"| {r['id']} | {r['current_verdict']} | "
                         f"{r['supports_open']} | {(r['title'] or '')[:66]} |")

    lines += ["", "## New problems accepted by both models", "", head, "",
              "| category | gap | proposed by | batches |", "|---|---|---:|---|"]
    for c in clusters:
        lines.append(f"| {c['category']} | {(c['title'] or '')[:88]} | "
                     f"{c['proposed_by']} | {', '.join(c['batches'])} |")
    if multi:
        lines += ["", "### Independently proposed more than once", ""]
        for c in multi:
            lines += [f"**{c['category']} — {c['title']}** "
                      f"({c['proposed_by']} readers: {', '.join(c['batches'])})", "",
                      (c["statement"] or "").strip(), ""]
            for m in c["members"]:
                lines.append(f"- *{(m.get('paper_title') or '')[:70]}* — "
                             f"{(m.get('proposed_title') or '')[:100]}")
            lines.append("")

    lines += ["", "## Findings the reviewer rejected", "",
              "| problem | claimed | paper | why |", "|---|---|---|---|"]
    for f in dropped:
        lines.append(f"| {f['problem_id']} | {f.get('effect')} | "
                     f"{(f.get('paper_title') or '')[:40]} | "
                     f"{(f.get('review_reason') or '')[:110]} |")

    open(os.path.join(READING, "PROPOSED.md"), "w", encoding="utf8").write(
        "\n".join(lines) + "\n")

    print(f"{len(kept)} findings survive, {len(dropped)} rejected, "
          f"{len(weakened)} weakened")
    thin = sum(1 for c in flips if c["flip_drivers"] < 2)
    print(f"{len(by_problem)} problems gained evidence, "
          f"{len(flips)} verdict changes proposed ({thin} on a single paper)")
    hard = sum(1 for r in reopen if r["kind"] == "contradicts-closure")
    print(f"{len(reopen)} closed problems gained open-supporting evidence "
          f"({hard} marked not-supported)")
    if disputed:
        print(f"{len(disputed)} problems have surviving evidence on both sides: "
              + ", ".join(r["id"] for r in disputed))
    print(f"{len(new_kept)} new problems accepted, {len(new_dropped)} rejected")
    print(f"  collapse to {len(clusters)} distinct gaps; "
          f"{sum(1 for c in clusters if c['proposed_by'] > 1)} proposed "
          f"independently by more than one reader")


if __name__ == "__main__":
    main()
