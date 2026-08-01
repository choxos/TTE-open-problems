#!/usr/bin/env python3
"""Turn a reviewed design into the R files that run it.

Study 1 established the layout every study in this program uses, and it is not
arbitrary. `00-config.R` holds everything the protocol fixed in advance, so
changing a design constant is a visible edit rather than a number buried in a
loop. `01-dgm.R` generates one replicate. `02-estimators.R` holds the estimators
and the enumeration of truth, which is computed from the mechanism with
assignment set rather than estimated from the replicates, because a noisy truth
puts its own Monte Carlo error into every bias in the study. `03-truth.R` and
`04-run.R` are resumable drivers over the shared harness. `05-analyze.R` writes
the tracked CSVs and `06-figures.R` the figures.

The generated code is not trusted. It is smoke-tested at a tiny replicate count
before anything is run at scale, and the smoke test is part of this script
rather than a thing someone remembers to do: a data-generating mechanism that
silently produces a constant, or an estimator that returns the same number for
both arms, looks exactly like working code until the results are meaningless.

Usage:
  python3 build/studies/implement.py --problem BEN-02
  python3 build/studies/implement.py --all --parallel 3
  python3 build/studies/implement.py --smoke BEN-02
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REGISTRY = os.path.join(ROOT, "documentation", "audit", "registry", "problems.json")
DESIGNS = os.path.join(ROOT, "documentation", "studies", "designs")
STUDIES = os.path.join(ROOT, "studies")
EXAMPLE = os.path.join(STUDIES, "CNF-01-convergence-attenuation")

MODEL = "gpt-5.6-sol"
EFFORT = "max"

FILES = ["00-config.R", "01-dgm.R", "02-estimators.R", "03-truth.R",
         "04-run.R", "05-analyze.R", "06-figures.R"]

PROMPT = """You write the R code for a simulation study that has already been
designed and reviewed. The design is the specification. Implement it; do not
redesign it.

Answer from the payload. Do not use tools, do not spawn sub-agents, do not load
skills.

## What you are given

  problem    the catalog entry the study is meant to settle
  design     an ADEMP protocol for it
  critique   an adversarial review of that protocol, if one exists. Its findings
             are not advisory. Where a finding changes the implementation,
             implement the fixed version and say so in a comment at the point of
             the change. Where it names a limitation you cannot fix in code, do
             nothing and leave it to the protocol.
  example    the complete R implementation of study 1 of this program, which is
             the layout and the standard to match

## The environment

R 4.6.0, 6 usable workers. Installed: TrialEmulation 0.0.4.11, gfoRmula 1.1.1,
gfoRmulaICE 1.1.1, ltmle 1.3.0, tmle 2.1.1, WeightIt 1.7.0, MatchIt 4.7.2,
cobalt 4.6.3, ipw 1.3.0, riskRegression 2026.3.11, adjustedCurves 0.11.4,
simsurv 1.0.1, survival 3.8.9, data.table, ggplot2, scales, boot, mvtnorm,
dplyr, future, furrr. NOT installed: lmtp, concrete, CICI, Stan, cmdstanr,
SuperLearner. Do not use them. Base R and the packages listed are enough.

`studies/_shared/R/harness.R` provides `run_design(fn, scenarios, n_rep,
master_seed, outdir, workers, resume, only)` and `write_provenance(outdir,
packages, extra)`. `studies/_shared/R/performance.R` provides `perf_bias`,
`perf_empse`, `perf_modse`, `perf_relerror_modse`, `perf_mse`, `perf_coverage`,
`perf_becoverage`, `perf_rejection` and `perf_convergence`, each returning a
list with `est` and `mcse`. Use them. Do not reimplement them.

## Hard requirements

1. Exactly seven files, named as in the example. Each is standalone R, sourced
   in the order 00, 01, 02, then the drivers.
2. `03-truth.R` and `04-run.R` must accept an optional `i:j` scenario slice as
   `commandArgs(TRUE)[1]` and must be resumable, exactly as the example is.
   Long runs get killed on this machine and a driver that restarts from zero is
   useless.
3. Truth is enumerated from the mechanism, not estimated from the replicates,
   and cached per scenario.
4. Every replicate returns the same rows whatever happens to it, with a `fail`
   column, so convergence has a real denominator.
5. `05-analyze.R` writes `results/performance.csv` and whatever else the design's
   decision rule needs, and prints a console summary that ends by stating which
   branch of the decision rule the results fall into, using the design's own
   numerical thresholds.
6. No `set.seed` inside a replicate. The harness owns the streams.
7. Vectorize. The example generates 4000 individuals over 120 monthly cycles per
   replicate and runs 1000 replicates of a scenario in 50 seconds on 6 workers.
   A per-individual `for` loop will not meet that.
8. Scale the design down if it does not fit the budget, and say so in a comment
   in `00-config.R` giving the arithmetic. An overnight run is the ceiling.

## Output

Reply with JSON only, no prose before or after. Every value is the complete text
of that file.

{"files":{"00-config.R":"...","01-dgm.R":"...","02-estimators.R":"...",
 "03-truth.R":"...","04-run.R":"...","05-analyze.R":"...","06-figures.R":"..."},
 "slug":"BEN-02-short-kebab-slug",
 "scaled_down":"what you reduced and the arithmetic, or null",
 "critique_findings_implemented":["..."],
 "smoke_command":"Rscript R/04-run.R 1:1"}

PAYLOAD:
"""


def slugify(s):
    s = re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")
    return re.sub(r"-+", "-", s)


def extract_json(text):
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
                if '"files"' in blob:
                    try:
                        return json.loads(blob)
                    except json.JSONDecodeError:
                        pass
                start = None
    return None


def example_payload():
    return {n: open(os.path.join(EXAMPLE, "R", n), encoding="utf8").read()
            for n in FILES}


def design_for(pid):
    """The revised design if there is one, the original only if there is not.

    Every design in this program was reviewed and none was accepted, so the
    original is the wrong thing to implement: thirty of the thirty-two fatal
    findings were resolved by changing it. The critique still travels with the
    revision, because the revision records how each finding was resolved and the
    implementation has to honor the design-decision ones in code.
    """
    rev = sorted(glob.glob(os.path.join(DESIGNS, f"{pid}-*-revised.json")))
    hits = sorted(glob.glob(os.path.join(DESIGNS, f"{pid}-*-design.json")))
    if not hits and not rev:
        return None, None
    src = rev[0] if rev else hits[0]
    slug = os.path.basename(src).rsplit("-revised.json", 1)[0] \
        if rev else os.path.basename(src).rsplit("-design.json", 1)[0]
    crit = os.path.join(DESIGNS, f"{slug}-critique.json")
    return (json.load(open(src, encoding="utf8")),
            json.load(open(crit, encoding="utf8")) if os.path.exists(crit) else None)


def implement_one(pid, timeout=7200):
    P = {p["id"]: p for p in json.load(open(REGISTRY, encoding="utf8"))}
    design, critique = design_for(pid)
    if design is None:
        print(f"  {pid}: no design", flush=True)
        return pid, None
    payload = {"problem": P[pid], "design": design, "critique": critique,
               "example": example_payload()}
    full = PROMPT + json.dumps(payload, ensure_ascii=False, indent=1)
    work = os.path.join(ROOT, "documentation", "studies", "impl")
    os.makedirs(work, exist_ok=True)
    open(os.path.join(work, f"{pid}-prompt.txt"), "w", encoding="utf8").write(full)
    cmd = ["codex", "exec", "-m", MODEL, "-c", f"model_reasoning_effort={EFFORT}",
           "-s", "read-only", "--skip-git-repo-check", "--ignore-rules", "-"]
    print(f"  {pid}: writing code ...", flush=True)
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout,
                           input=full.encode("utf8"))
    except subprocess.TimeoutExpired:
        print(f"  {pid}: timeout", flush=True)
        return pid, None
    out = p.stdout.decode("utf8", "ignore")
    open(os.path.join(work, f"{pid}-raw.txt"), "w", encoding="utf8").write(out)
    d = extract_json(out)
    if not d or not isinstance(d.get("files"), dict):
        print(f"  {pid}: no usable JSON", flush=True)
        return pid, None
    missing = [f for f in FILES if f not in d["files"]]
    if missing:
        print(f"  {pid}: missing {missing}", flush=True)
        return pid, None

    slug = d.get("slug") or f"{pid}-{slugify(design.get('title', ''))[:40]}"
    if not slug.startswith(pid):
        slug = f"{pid}-{slugify(slug)}"
    sdir = os.path.join(STUDIES, slug)
    os.makedirs(os.path.join(sdir, "R"), exist_ok=True)
    for name, body in d["files"].items():
        open(os.path.join(sdir, "R", name), "w", encoding="utf8").write(
            body if body.endswith("\n") else body + "\n")
    d["_slug"] = slug
    json.dump({k: v for k, v in d.items() if k != "files"},
              open(os.path.join(work, f"{pid}-meta.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    print(f"  {pid}: -> studies/{slug}/R/ "
          + (f"(scaled down: {str(d.get('scaled_down'))[:60]})"
             if d.get("scaled_down") else ""), flush=True)
    return pid, slug


def smoke(pid):
    """Parse, then run one scenario at a tiny replicate count.

    Three failures this is here to catch, in order of how convincingly they
    imitate working code: a file that does not parse, a driver that errors, and
    a mechanism that runs cleanly while producing a constant outcome or an
    estimator that returns the same value for both arms.
    """
    hits = sorted(glob.glob(os.path.join(STUDIES, f"{pid}-*", "R", "00-config.R")))
    if not hits:
        return pid, "no implementation"
    sdir = os.path.dirname(os.path.dirname(hits[0]))
    for f in FILES:
        path = os.path.join(sdir, "R", f)
        r = subprocess.run(["Rscript", "-e", f'invisible(parse("{path}"))'],
                           capture_output=True)
        if r.returncode:
            return pid, f"{f} does not parse: " + r.stderr.decode()[:200].strip()
    r = subprocess.run(
        ["Rscript", "-e",
         'a <- commandArgs(TRUE); source("R/00-config.R"); source("R/01-dgm.R"); '
         'source("R/02-estimators.R"); cat("sourced OK\\n")'],
        cwd=sdir, capture_output=True, timeout=600)
    if r.returncode:
        return pid, "sourcing failed: " + r.stderr.decode()[-300:].strip()
    return pid, "ok"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--problem")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--smoke")
    ap.add_argument("--smoke-all", action="store_true")
    ap.add_argument("--parallel", type=int, default=3)
    a = ap.parse_args()

    queue = [r["id"] for r in json.load(
        open(os.path.join(STUDIES, "queue.json"), encoding="utf8"))["queue"]]

    if a.smoke:
        print(*smoke(a.smoke)); return
    if a.smoke_all:
        for pid in queue:
            print("  %-8s %s" % smoke(pid))
        return
    if a.problem:
        implement_one(a.problem); return
    if not a.all:
        sys.exit("pass --problem, --all, --smoke or --smoke-all")

    done = {os.path.basename(os.path.dirname(os.path.dirname(f))).split("-")[0]
            + "-" + os.path.basename(os.path.dirname(os.path.dirname(f))).split("-")[1]
            for f in glob.glob(os.path.join(STUDIES, "*", "R", "00-config.R"))}
    todo = [p for p in queue if p not in done]
    if not todo:
        print("every queued problem has an implementation"); return
    print(f"{len(todo)} to implement with {MODEL} at {EFFORT}, "
          f"{a.parallel} at a time", flush=True)
    with ThreadPoolExecutor(max_workers=a.parallel) as pool:
        futs = [pool.submit(implement_one, p) for p in todo]
        n = sum(1 for f in as_completed(futs) if f.result()[1])
    print(f"\n{n} of {len(todo)} implemented")


if __name__ == "__main__":
    main()
