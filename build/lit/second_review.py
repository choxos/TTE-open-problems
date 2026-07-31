#!/usr/bin/env python3
"""Second-review the high-stakes reading findings with an external model.

The paper readers and this reviewer are different models with different failure
modes, which is the point: a finding that survives both is worth acting on. The
reviewer sees the registered problem, the claimed effect and the verbatim quote,
and is asked to be hard on exactly the claims that would retire a problem.

The reviewer runs read-only with no tools, so it answers from the payload and its
own knowledge and prints JSON to stdout, which this script extracts and stores.

Usage:
  python3 build/lit/second_review.py --batch rev-01
  python3 build/lit/second_review.py --all --parallel 4
"""

import argparse
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REVIEW = os.path.join(ROOT, "documentation", "audit", "reading", "review")
MODEL = "gpt-5.6-terra"

PROMPT = """You are an independent second reviewer for a catalog of open problems in
target trial emulation and the g-methods used to estimate the effects of
sustained treatment strategies.

Another model read a set of methodology papers and claimed each one bears on a
registered open problem. Your job is to judge those claims. Answer from the
payload and your own knowledge of this literature. Do not use tools, do not spawn
sub-agents, do not load skills.

Two kinds of item appear.

**kind: finding.** A paper is claimed to have a given effect on a registered
problem. `resolves` means the problem as stated is solved. `partially-addresses`
means a named part is solved, or it is solved under conditions the problem does
not assume. `contradicts` means the problem's premise is false. Judge whether the
claimed effect is right given the problem statement and the quoted evidence. Be
hard on `resolves` and `contradicts`: those retire a problem, and a wrong one
deletes a real research gap from the catalog. Be alert to a quote that supports a
weaker claim than the one made, to a paper solving a neighbouring problem rather
than this one, and to an applied paper being read as a methods contribution.
Return one of:
  agree            the claimed effect is right
  downgrade        real but weaker; say what effect it should be
  upgrade          stronger than claimed; say what effect it should be
  reject           the paper does not bear on this problem, or the quote does not
                   support the claim
  uncertain        cannot be judged from the payload; say what is missing

**kind: new-problem.** A problem is proposed as missing from the registry. Judge
whether it is a genuine, well-posed methodological gap and whether it is really
distinct from what exists. Return one of: accept, merge (name the id it belongs
to), reject (say why: already covered, not a methods problem, too vague, or
false). You are not shown the full registry, so when you suspect duplication name
the id you suspect and say so rather than asserting it.

Reply with JSON only, no prose before or after:

{"verdicts":[{"index":0,"verdict":"agree|downgrade|upgrade|reject|uncertain|accept|merge","corrected_effect":"...or null","merge_into":"...or null","confidence":"high|medium|low","reason":"two or three sentences"}]}

Index each verdict by the item's position in the payload, starting at 0. Return
exactly one verdict per item.

PAYLOAD:
"""


def extract_json(text):
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
                if '"verdicts"' in blob:
                    try:
                        return json.loads(blob)
                    except json.JSONDecodeError:
                        pass
                start = None
    return None


def run_batch(bid, timeout=1500):
    src = os.path.join(REVIEW, f"{bid}.json")
    payload = json.load(open(src, encoding="utf8"))
    prompt = PROMPT + json.dumps(payload["items"], ensure_ascii=False, indent=1)
    cmd = ["codex", "exec", "-m", MODEL, "-c", "model_reasoning_effort=high",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules", prompt]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return bid, None, "timeout"
    out = p.stdout.decode("utf8", "ignore")
    raw = os.path.join(REVIEW, f"raw-{bid}.txt")
    open(raw, "w", encoding="utf8").write(out)
    d = extract_json(out)
    if not d:
        return bid, None, "no JSON in output"
    v = d.get("verdicts", [])
    if len(v) != len(payload["items"]):
        note = f"{len(v)} verdicts for {len(payload['items'])} items"
    else:
        note = "ok"
    for x in v:
        i = x.get("index")
        if isinstance(i, int) and 0 <= i < len(payload["items"]):
            x["item"] = payload["items"][i]
    json.dump({"batch": bid, "model": MODEL, "verdicts": v},
              open(os.path.join(REVIEW, f"verdict-{bid}.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    return bid, len(v), note


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--parallel", type=int, default=4)
    args = ap.parse_args()

    if args.batch:
        batches = [args.batch]
    elif args.all:
        batches = sorted(os.path.splitext(os.path.basename(f))[0]
                         for f in os.listdir(REVIEW)
                         if re.fullmatch(r"rev-\d+\.json", f))
        batches = [b for b in batches
                   if not os.path.exists(os.path.join(REVIEW, f"verdict-{b}.json"))]
    else:
        sys.exit("pass --batch or --all")

    print(f"{len(batches)} batches to review with {MODEL}")
    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        futs = {pool.submit(run_batch, b): b for b in batches}
        for f in as_completed(futs):
            bid, n, note = f.result()
            print(f"  {bid}: {n if n is not None else 'FAILED'} verdicts ({note})",
                  flush=True)


if __name__ == "__main__":
    main()
