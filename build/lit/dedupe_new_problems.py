#!/usr/bin/env python3
"""Group the proposed new problems that name the same gap.

The second reviewer judges one batch at a time, so it never sees that readers
working on disjoint papers proposed the same missing method in different words.
Left ungrouped, one gap enters the registry once per reader who noticed it.

Word-overlap clustering does not work here. Every proposal is written in the same
domain vocabulary, so the shared terms swamp the distinguishing ones: measured
across the accepted set, a pair saying the same thing in different words scores
lower than a pair about genuinely different things. Ordering is wrong, not just
the threshold, so no cutoff rescues it. The grouping is a semantic judgement and
is made by a model that sees every proposal at once.

Independent proposal is evidence, not noise. A gap three readers reached from
three different literatures is better attested than one raised once, so the
group keeps its members and its size rather than discarding duplicates.

Output: reading/review/new-problem-groups.json

Usage: python3 build/lit/dedupe_new_problems.py [--dry-run]
"""

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
READING = os.path.join(ROOT, "documentation", "audit", "reading")
REVIEW = os.path.join(READING, "review")
MODEL = "gpt-5.6-terra"

PROMPT = """You are consolidating proposed additions to a catalog of open problems in
indirect treatment comparisons, population-adjusted indirect comparisons and
component network meta-analysis.

Below are proposals written independently by readers who each saw a different set
of papers. Because they worked separately, the same gap is often proposed more
than once in different words, and under different category codes. Your job is to
group them.

Two proposals belong in the same group when a single registry entry would cover
both: they name the same missing method, diagnostic, or convention. They do NOT
belong together merely because they concern the same object. "No publication-bias
test at the component level" and "no sample-size method for component NMA" are
both about component NMA and are different gaps. "No reporting-bias diagnostic
for component estimates" and "no test for small-study effects at the component
level" are the same gap.

Be conservative about merging: wrongly merging two gaps deletes one of them from
the catalog, which is worse than listing a near-duplicate that a human can spot.
When a group spans two category codes, choose the one that best fits the merged
statement.

For each group write a title and a statement that covers what all its members
say, in the voice of a registry entry: what is missing, and for what.

Answer from the payload. Do not use tools, do not spawn sub-agents, do not load
skills.

Reply with JSON only, no prose before or after:

{"groups":[{"members":[0,4],"category":"CMP","title":"...","statement":"the gap, precisely, covering every member","why_open":"why nothing existing closes it","rationale":"why these belong together, or why a tempting neighbour was left out"}]}

`members` are payload indices, starting at 0. Every index must appear in exactly
one group. A proposal that duplicates nothing is a group of one.

PAYLOAD:
"""


def extract_json(text, key):
    """Pull the JSON object out of the CLI's output, which wraps it in chatter."""
    depth, start = 0, None
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                blob = text[start:i + 1]
                if f'"{key}"' in blob:
                    try:
                        return json.loads(blob)
                    except json.JSONDecodeError:
                        pass
                start = None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="print the payload and stop")
    ap.add_argument("--timeout", type=int, default=1800)
    args = ap.parse_args()

    src = os.path.join(READING, "proposed-changes.json")
    if not os.path.exists(src):
        sys.exit("run build/lit/merge_review.py first")
    items = json.load(open(src, encoding="utf8"))["new_problems"]
    if not items:
        sys.exit("no accepted new problems to group")

    payload = [{
        "index": i,
        "category": n.get("category"),
        "title": n.get("proposed_title"),
        "statement": (n.get("statement") or "")[:900],
        "why_open": (n.get("why_open") or "")[:700],
        "from_paper": n.get("paper_title"),
    } for i, n in enumerate(items)]

    prompt = PROMPT + json.dumps(payload, ensure_ascii=False, indent=1)
    if args.dry_run:
        print(prompt)
        return

    print(f"grouping {len(items)} proposals with {MODEL}")
    cmd = ["codex", "exec", "-m", MODEL, "-c", "model_reasoning_effort=high",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules", prompt]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=args.timeout,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        sys.exit("timed out")
    out = p.stdout.decode("utf8", "ignore")
    open(os.path.join(REVIEW, "raw-new-problem-groups.txt"), "w",
         encoding="utf8").write(out)
    d = extract_json(out, "groups")
    if not d:
        sys.exit("no JSON in output; see review/raw-new-problem-groups.txt")

    groups = d.get("groups", [])
    seen, bad = set(), []
    for g in groups:
        for i in g.get("members") or []:
            if not isinstance(i, int) or not 0 <= i < len(items):
                bad.append(i)
            elif i in seen:
                bad.append(i)
            else:
                seen.add(i)
    missing = sorted(set(range(len(items))) - seen)
    # Anything the model dropped or double-counted stays in the catalog as its
    # own entry. Silently losing a proposal here would delete a real gap.
    for i in missing:
        groups.append({"members": [i], "category": items[i].get("category"),
                       "title": items[i].get("proposed_title"),
                       "statement": items[i].get("statement"),
                       "why_open": items[i].get("why_open"),
                       "rationale": "not placed by the grouping pass; kept alone"})

    for g in groups:
        g["members"] = [i for i in (g.get("members") or [])
                        if isinstance(i, int) and 0 <= i < len(items)]
        g["proposed_by"] = len(g["members"])
        g["batches"] = sorted({items[i].get("batch") for i in g["members"]
                               if items[i].get("batch")})
        g["papers"] = sorted({(items[i].get("paper_title") or "")[:70]
                              for i in g["members"]})
    groups.sort(key=lambda g: (-g["proposed_by"], g.get("category") or ""))

    json.dump({"model": MODEL, "n_proposals": len(items), "groups": groups},
              open(os.path.join(REVIEW, "new-problem-groups.json"), "w",
                   encoding="utf8"), indent=1, ensure_ascii=False)

    multi = [g for g in groups if g["proposed_by"] > 1]
    print(f"{len(items)} proposals -> {len(groups)} distinct gaps")
    print(f"  {len(multi)} proposed independently by more than one reader")
    if bad:
        print(f"  {len(bad)} indices were invalid or repeated")
    if missing:
        print(f"  {len(missing)} not placed by the model, kept as singletons")
    for g in multi:
        print(f"  [{g.get('category')}] x{g['proposed_by']} "
              f"{(g.get('title') or '')[:80]}")


if __name__ == "__main__":
    main()
