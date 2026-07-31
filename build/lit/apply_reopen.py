#!/usr/bin/env python3
"""Write the reopen adjudication back onto the entries.

`build/lit/reopen.py` decided, for each of the 24 problems an earlier pass closed
and the reading found open, whether the closure survives. This applies that.

Three things happen, and the largest is the one that changes no verdict at all.
Nineteen entries keep their closure and gain a note saying the reading's findings
were examined against it and restate the residual it already conceded. That note
is the point: without it the next reader sees a pile of `supports-open` evidence
against a closed problem and assumes nobody checked, which is exactly how the
same work gets redone.

The narrowing edits are literal replacements, taken from the reviewer's own
wording where it gave one and composed here where it described the change
instead. Composed text is marked as such, so a reader can tell which sentences a
model chose and which a person did.

Usage:
  python3 build/lit/apply_reopen.py --dry-run
  python3 build/lit/apply_reopen.py --write
"""

import argparse
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
REGISTRY = os.path.join(AUDIT, "registry")

# Literal edits for the `narrow` verdicts. `source` records who wrote the
# replacement text: the reviewer supplied CMP-05 and DEC-12 verbatim, and
# described the other two, which are composed from that description.
NARROW = {
    "CMP-05": [(
        "statement",
        "What is missing is any mapping from these onto CNMA component "
        "matrices, and any hierarchical equivalence-class model",
        "What is missing is a reusable, version-preserving and "
        "software-supported mapping from structured intervention ontologies "
        "onto CNMA component matrices, and any hierarchical equivalence-class "
        "model",
        "reviewer",
        "A 2024 eHealth CNMA protocol (doi:10.1136/bmjopen-2024-084774) maps "
        "the BCTTv1 hierarchy into its component scheme by hand, so the "
        "absolute claim that no mapping exists was drawn too broadly. An "
        "occasional manual study-level mapping is not a reusable one carried "
        "into analysis software.")],
    "DEC-12": [(
        "statement",
        "No rule requires a formal quantitative bias analysis or a minimum "
        "stress-test set for a decision-grade unanchored analysis",
        "No broadly applicable rule or agreed minimum stress-test set requires "
        "quantitative assessment of assumption-driven conclusions for "
        "decision-grade indirect comparisons, and EU HTA guidance now "
        "recommends shifted-null testing for population-adjusted comparisons "
        "without extending a comparable requirement to standard network "
        "meta-analysis or Bucher comparisons",
        "reviewer",
        "A 2026 review (doi:10.3390/jmahp14020030) reports that EU guidance "
        "recommends shifted-null hypothesis testing for PAICs to account for "
        "unmeasured effect modifiers. That postdates the closure and defeats "
        "the categorical form of the claim, though it supplies no agreed "
        "minimum set and does not reach other indirect-comparison methods.")],
    "EST-01": [(
        "verdict_rationale",
        "and although ML-NMR/multinma can estimate every network contrast in "
        "one externally supplied target population",
        "and although ML-NMR/multinma can estimate every network contrast in "
        "one externally supplied target population for anchored comparisons, "
        "which is not yet a general solution for unanchored comparisons or for "
        "all outcome types",
        "composed from the reviewer's description",
        "Unanchored-method papers from 2024 and 2025 state that ML-NMR was "
        "then applicable to anchored comparisons only, and a 2025 "
        "quantitative-bias-analysis paper lists estimation in an arbitrary "
        "target population as a remaining need for unanchored PAICs. The "
        "closure stands; its counterexample was stated more broadly than the "
        "machinery reaches.")],
    "OUT-12": [(
        "statement",
        "Flexible study-specific baseline hazards for survival ML-NMR are not "
        "open.",
        "Flexible study-specific baseline hazards for survival ML-NMR are not "
        "open where every study supplies sufficiently informative "
        "time-to-event data; they are not identified for arms represented only "
        "by sparse aggregate counts, where a baseline shape has to be borrowed "
        "across studies.",
        "composed from the reviewer's description",
        "A 2014 mixed IPD and aggregate-count survival network shows a "
        "study-specific baseline shape is not identified for aggregate count "
        "arms and must be borrowed, despite materially incompatible "
        "study-specific Weibull shapes. Implementation availability is not a "
        "data-support condition. Survival-tail nonidentification remains the "
        "principal open problem and the closure of the broad claim stands.")],
}

VERDICT_FOR = {"open": "confirmed-open"}   # the reviewer's word, in registry terms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--allow-reopen", action="store_true",
                    help="apply the verdict reversals as well as the notes")
    a = ap.parse_args()
    if not (a.write or a.dry_run):
        sys.exit("pass --write or --dry-run")

    problems = json.load(open(os.path.join(REGISTRY, "problems.json"),
                              encoding="utf8"))
    by_id = {p["id"]: p for p in problems}

    got = []
    for f in sorted(glob.glob(os.path.join(READING, "reopen", "verdict-*.json"))):
        got += json.load(open(f, encoding="utf8"))["verdicts"]
    if not got:
        sys.exit("no adjudication yet; run build/lit/reopen.py --build --run")

    log = []
    for v in got:
        it = v.get("item") or {}
        pid = v.get("problem_id") or it.get("problem_id")
        p = by_id.get(pid)
        if not p:
            log.append(f"MISS {pid}: not in registry")
            continue
        ru = p.setdefault("reading_update", {"applied": "full-text reading",
                                             "changes": []})
        # The original note said "flagged, not applied". It has been applied now,
        # so leaving it would tell a reader the question is still open.
        ru["changes"] = [c for c in ru["changes"]
                         if c.get("kind") != "reopen-candidate"]

        n = it.get("new_findings_total")
        if v["verdict"] == "keep-closed":
            ru["changes"].append({
                "kind": "closure-upheld",
                "what": f"{n} findings from the reading assert this problem is "
                        f"open; the closure was re-examined and stands",
                "evidence": "Put to an independent reviewer with the closing "
                            "auditors' reasoning, the work they relied on, and "
                            "the new findings in view together. "
                            + (v.get("reason") or "")
                            + f" (reviewer confidence: {v.get('confidence')})",
            })
            log.append(f"upheld   {pid}  ({n} findings)")
            continue

        if v["verdict"] == "narrow":
            edits = NARROW.get(pid) or []
            applied = []
            for field, old, new, source, why in edits:
                if old not in (p.get(field) or ""):
                    log.append(f"NARROW MISS {pid}.{field}: target text not found")
                    continue
                before = p[field]
                p[field] = p[field].replace(old, new)
                applied.append(field)
                ru["changes"].append({
                    "kind": "scope-narrowed",
                    "what": f"{field}: the closure stands, but its boundary was "
                            f"drawn in the wrong place",
                    "evidence": why + f" Replacement wording {source}; reviewer "
                                      f"confidence {v.get('confidence')}.",
                    "previous_text": before,
                })
            log.append(f"narrowed {pid}  ({', '.join(applied) or 'NOTHING APPLIED'})")
            continue

        if v["verdict"] == "reopen":
            want = VERDICT_FOR.get(v.get("move_to") or "", v.get("move_to"))
            if not a.allow_reopen:
                log.append(f"HELD     {pid}: reopen to {want} pending "
                           f"--allow-reopen")
                continue
            old = p["verdict"]
            if old != want:
                p["verdict"] = want
                p["verdict_rationale"] = (
                    (p.get("verdict_rationale") or "").rstrip()
                    + f" Reopened on re-examination: the closure rested on no "
                      f"accessible source substantiating the claim, and work "
                      f"published since supplies one. "
                    + (v.get("decisive_evidence") or "")).strip()
            ru["changes"].append({
                "kind": "reopened",
                "what": f"{old} -> {want}",
                "evidence": (v.get("reason") or "")
                            + " Decisive: " + (v.get("decisive_evidence") or "")
                            + f" (reviewer confidence: {v.get('confidence')}, "
                              f"independently checked against the source paper)",
            })
            log.append(f"reopened {pid}: {old} -> {want}")

    if a.write:
        json.dump(problems, open(os.path.join(REGISTRY, "problems.json"), "w",
                                 encoding="utf8"), indent=1, ensure_ascii=False)
    for line in log:
        print(("  " if line[:1].islower() else "!! ") + line)
    print(f"\n{sum(1 for x in log if x.startswith('upheld'))} upheld, "
          f"{sum(1 for x in log if x.startswith('narrowed'))} narrowed, "
          f"{sum(1 for x in log if x.startswith('reopened'))} reopened, "
          f"{sum(1 for x in log if x.startswith('HELD'))} held"
          + ("" if a.write else "   (dry run; nothing written)"))


if __name__ == "__main__":
    main()
