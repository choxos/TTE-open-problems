#!/usr/bin/env python3
"""Review a finished study's results before it is published.

The design review asked whether the study would answer the question. This asks
whether the study that ran did answer it, which is a different question and is
the one nobody asks. A protocol can be sound and the run can still produce a
conclusion the numbers do not support: an estimator that failed silently, a
decision-rule branch reached by a threshold comparison on a quantity that is
mostly Monte Carlo error, a headline that generalizes past the grid.

The reviewer sees the catalog entry, the protocol, the analysis output, and the
tracked result files themselves. It does not see the study's own summary of what
it found, because the point is to derive that independently and then compare.

A study is publishable when the reviewer returns `supported`. Anything else goes
back: the finding is either fixed in the analysis, or the claim is narrowed to
what the numbers carry, and the round is recorded. Rounds are kept, not
overwritten, so the trail shows what the first pass claimed and what survived.

Usage:
  python3 build/studies/verify.py --study studies/CNF-01-convergence-attenuation
  python3 build/studies/verify.py --study <dir> --round 2
"""

import argparse
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REGISTRY = os.path.join(ROOT, "documentation", "audit", "registry", "problems.json")
DESIGNS = os.path.join(ROOT, "documentation", "studies", "designs")
OUT = os.path.join(ROOT, "documentation", "studies", "verify")

MODEL = "gpt-5.6-sol"
EFFORT = "max"
MAX_CSV_BYTES = 90000

PROMPT = """You review the RESULTS of a simulation study before it is published
against a public catalog entry as the answer to a stated open problem.

Answer from the payload. Do not use tools, do not spawn sub-agents, do not load
skills.

The design was reviewed separately and revised. You are not reviewing the design
again except where the run reveals something the design review could not see.

## What you are given

  problem     the catalog entry the study is meant to settle
  protocol    the revised design, including the decision rule and its numerical
              thresholds, written before the run
  analysis    the console output of the analysis step, which ends by stating
              which branch of the decision rule the results fall into
  results     the tracked result files, truncated where large

You are NOT given the study's own prose summary. Derive what the numbers say
first, then say whether the branch the analysis reported is the branch the
numbers support.

## What to check, in this order

1. **Did the study estimate anything?** Convergence, failure counts, the number
   of usable replicates against the number attempted. A study that completed and
   estimated nothing will still produce a full set of performance measures and a
   decision-rule branch. This has already happened once in this program.

2. **Is the reported branch the branch the numbers support?** Recompute the
   decision-rule comparison from the results. Check the threshold, the direction
   of the inequality, and whether the quantity compared is the one the protocol
   named.

3. **Is the margin larger than the Monte Carlo error?** A finding whose distance
   from its threshold is within a few Monte Carlo standard errors is not a
   finding. Say so with the arithmetic.

4. **Does the headline claim exceed the grid?** A result established at three
   levels of a factor does not hold "generally". Name any claim that reaches
   past the scenarios actually run.

5. **Are the performance measures internally consistent?** Coverage against
   nominal, empirical against model-based standard error, bias against its own
   Monte Carlo standard error. An estimator that is unbiased with 60 percent
   coverage is telling you its variance estimator is wrong, and that changes
   what the study can claim.

6. **Is anything in the results contradicted by something else in the results?**

## Verdict

  supported          the reported conclusion is what the numbers say, at the
                     stated strength, within the stated scope
  overstated         the direction holds and the claim is stronger than the
                     numbers carry; say what the defensible claim is
  unsupported        the numbers do not support the reported branch
  uninformative      the study ran and cannot distinguish; say why

## Output

Reply with JSON only, no prose before or after.

{"verdict":"supported|overstated|unsupported|uninformative",
 "what_the_numbers_say":"your independent reading, before comparing",
 "branch_check":{"protocol_threshold":"...","observed":"...",
   "monte_carlo_margin":"...","branch_supported":true},
 "findings":[{"severity":"fatal|serious|minor","axis":"...","what":"...",
   "fix":"..."}],
 "defensible_claim":"the strongest sentence the results support, in one or two
   sentences, written as the study would state it",
 "scope_limits":["..."],
 "publishable":true}

PAYLOAD:
"""


def clip(s, n):
    s = s or ""
    return s if len(s) <= n else s[:n] + f"\n... [truncated, {len(s)} bytes total]"


def clip_csv(text, n):
    """Reduce a long results table without biasing it toward the first rows.

    These files are written in scenario order, so a prefix is not a sample of
    the study: LRN-05's performance table is 1.3 MB across 24 scenarios, and
    the first 90 KB is scenarios 1 and 2. A reviewer asked whether a conclusion
    holds across the grid, and handed the first twelfth of the grid, cannot see
    the question. Keep the header, take rows at an even stride across the whole
    file, and say exactly what was dropped and how it was chosen; a reviewer
    that knows it is reading a sample can ask for more, one that thinks it read
    the file cannot.
    """
    if len(text) <= n:
        return text
    lines = text.splitlines()
    if len(lines) < 3:
        return clip(text, n)
    header, body = lines[0], lines[1:]
    # Budget rows by the average line length rather than guessing a count.
    avg = max(1, len(text) // max(1, len(lines)))
    keep = max(10, (n - len(header) - 200) // avg)
    if keep >= len(body):
        return clip(text, n)
    stride = len(body) / keep
    idx = sorted({min(len(body) - 1, int(i * stride)) for i in range(keep)})
    out = [header] + [body[i] for i in idx]
    out.append(f"... [sampled {len(idx)} of {len(body)} data rows at an even "
               f"stride across the file, {len(text)} bytes total. Rows are in "
               f"scenario order, so this is a spread across the grid and not "
               f"the first scenarios. No row was altered.]")
    return "\n".join(out)


def protocol_for(pid, study):
    """The protocol the study was actually registered under.

    A study directory carrying its own `protocol.md` was registered under that
    document, and the commit adding it is the timestamp. The generated designs
    under documentation/studies/designs are proposals for a study, and for a
    problem that already has a hand-written protocol the generated one describes
    a different study entirely.

    Reviewing a run against a protocol it was never run under produces a fatal
    "protocol identity" finding that is an artifact of the lookup. That happened
    on the first study reviewed here, which was registered and run before the
    design machinery existed.
    """
    own = os.path.join(study, "protocol.md")
    if os.path.exists(own):
        return {"source": "studies/%s/protocol.md" % os.path.basename(study),
                "registered_before_the_run": True,
                "text": open(own, encoding="utf8").read()}
    for pat in (f"{pid}-*-revised.json", f"{pid}-*-design.json"):
        hits = sorted(glob.glob(os.path.join(DESIGNS, pat)))
        if hits:
            return json.load(open(hits[0], encoding="utf8"))
    return None


def gather(study):
    res = {}
    for f in sorted(glob.glob(os.path.join(study, "results", "*.csv"))):
        res[os.path.basename(f)] = clip_csv(open(f, encoding="utf8").read(),
                                            MAX_CSV_BYTES)
    prov = os.path.join(study, "results", "provenance.md")
    if os.path.exists(prov):
        res["provenance.md"] = open(prov, encoding="utf8").read()
    return res


def analysis_output(study):
    r = subprocess.run(["Rscript", "R/05-analyze.R"], cwd=study,
                       capture_output=True, timeout=3600)
    return (r.stdout + r.stderr).decode("utf8", "ignore")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--study", required=True)
    ap.add_argument("--round", type=int, default=1)
    a = ap.parse_args()

    study = a.study.rstrip("/")
    pid = os.path.basename(study)[:6]
    P = {p["id"]: p for p in json.load(open(REGISTRY, encoding="utf8"))}
    if pid not in P:
        sys.exit(f"{pid} is not a registry id")
    proto = protocol_for(pid, study)
    if proto is None:
        sys.exit(f"no protocol for {pid}")

    print(f"running the analysis for {pid} ...", flush=True)
    out = analysis_output(study)
    payload = {"problem": P[pid], "protocol": proto,
               "analysis": clip(out, 40000), "results": gather(study)}

    os.makedirs(OUT, exist_ok=True)
    full = PROMPT + json.dumps(payload, ensure_ascii=False, indent=1)
    tag = f"{pid}-round{a.round}"
    open(os.path.join(OUT, f"{tag}-prompt.txt"), "w", encoding="utf8").write(full)
    print(f"  {MODEL} at {EFFORT} effort, results review round {a.round} ...",
          flush=True)
    p = subprocess.run(
        ["codex", "exec", "-m", MODEL, "-c", f"model_reasoning_effort={EFFORT}",
         "-s", "read-only", "--skip-git-repo-check", "--ignore-rules", "-"],
        capture_output=True, timeout=7200, input=full.encode("utf8"))
    raw = p.stdout.decode("utf8", "ignore")
    open(os.path.join(OUT, f"{tag}-raw.txt"), "w", encoding="utf8").write(raw)

    depth, start, d = 0, None, None
    for i, ch in enumerate(raw):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    cand = json.loads(raw[start:i + 1])
                    if "verdict" in cand:
                        d = cand
                        break
                except json.JSONDecodeError:
                    pass
                start = None
    if d is None:
        sys.exit(f"no JSON verdict; see {OUT}/{tag}-raw.txt")

    json.dump(d, open(os.path.join(OUT, f"{tag}.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    sev = [str(f.get("severity", "?")).lower() for f in (d.get("findings") or [])]
    print(f"\nverdict: {d.get('verdict')}  publishable: {d.get('publishable')}")
    print(f"findings: {sev.count('fatal')} fatal, {sev.count('serious')} serious, "
          f"{sev.count('minor')} minor")
    bc = d.get("branch_check") or {}
    print(f"branch: threshold {bc.get('protocol_threshold')} vs observed "
          f"{bc.get('observed')}; margin {bc.get('monte_carlo_margin')}")
    for f in d.get("findings") or []:
        print(f"\n  [{str(f.get('severity','?')).upper()}] {f.get('axis')}")
        print(f"    {f.get('what')}")
        print(f"    fix: {f.get('fix')}")
    print(f"\ndefensible claim:\n  {d.get('defensible_claim')}")


if __name__ == "__main__":
    main()
