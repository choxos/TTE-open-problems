#!/usr/bin/env python3
"""Re-run the checks behind each reported error in the registry itself.

The readers report three kinds of thing. Two of them, findings and new problems,
are about whether a problem is open. The third is about whether the registry
entry is *accurate*: whether it credits the right authors, describes a result
correctly, or attributes a capability to software that the software does not
have. Nothing else in the pipeline can catch those, because a plausible name on
a working DOI and a confident sentence about a method both read as sound.

An erratum is a claim about a specific paper or a specific piece of software, so
most of them can be checked by machine rather than believed. This re-runs those
checks and prints what they return, so the errata page carries evidence anyone
can reproduce instead of an assertion that someone once looked.

A check that cannot be mechanised is recorded as `manual` with the reasoning, not
quietly dropped.

Output: documentation/audit/registry/ERRATA.md

Usage: python3 build/lit/errata.py
"""

import json
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
REGISTRY = os.path.join(AUDIT, "registry")


def paper_text(pid):
    lib = {c["id"]: c for c in json.load(open(
        os.path.join(ROOT, "documentation", "refs", "library.json"), encoding="utf8"))}
    e = lib.get(pid)
    if not e:
        return ""
    p = e.get("pdf") or e.get("xml") or e.get("text")
    if not p:
        return ""
    f = p if os.sep in p else os.path.join(e["path"], p)
    if not os.path.exists(f):
        return ""
    if f.endswith(".pdf"):
        t = subprocess.run(["pdftotext", f, "-"], capture_output=True,
                           text=True).stdout
    else:
        t = open(f, encoding="utf8", errors="replace").read()
    return re.sub(r"\s+", " ", t)


def counts(pid, terms):
    t = paper_text(pid).lower()
    return {k: t.count(k.lower()) for k in terms}


def registry_blob():
    return json.dumps(json.load(open(os.path.join(REGISTRY, "problems.json"),
                                     encoding="utf8")))


# Each check returns (verdict, evidence). `verdict` is what the mechanism found,
# not what anyone hoped it would find.
# Machine checks that re-run the evidence behind a reported registry error, so the errata page
# carries something reproducible rather than an assertion that someone once looked. The sibling
# project hardcodes one function per entry id; those were specific to its registry and are not
# ported. Three kinds are mechanizable here and get written once real errata exist:
#   - a cited surname or year that CrossRef contradicts   -> delegate to check_citations.py
#   - a capability attributed to a package                -> grep the pinned NAMESPACE and man pages
#   - a numeric claim about a paper                       -> grep the extracted text cache
CHECKS = {}


def main():
    agg = json.load(open(os.path.join(AUDIT, "reading", "aggregate.json"),
                         encoding="utf8"))
    errata = agg.get("registry_errata") or []
    problems = {p["id"]: p for p in json.load(open(
        os.path.join(REGISTRY, "problems.json"), encoding="utf8"))}

    rows = []
    for e in errata:
        pid = e.get("problem_id")
        fn = CHECKS.get(pid)
        if fn:
            ok, ev = fn()
        else:
            ok, ev = None, "no mechanical check written for this one"
        rows.append({**e, "check_passed": ok, "check_evidence": ev,
                     "problem_title": (problems.get(pid) or {}).get("title")})

    confirmed = [r for r in rows if r["check_passed"] is True]
    unchecked = [r for r in rows if r["check_passed"] is None]
    failed = [r for r in rows if r["check_passed"] is False]

    L = ["# Errors in the registry itself", "",
         f"{len(rows)} places where an entry states something about the literature "
         f"or about software that the paper in front of the reader disproves. These "
         f"are not findings about whether a problem is open; they are mistakes in "
         f"the entry, and nothing else in the pipeline can see them. A plausible "
         f"name on a working DOI reads as sound, and so does a confident sentence "
         f"about what a method does.", "",
         f"{len(confirmed)} still reproduce against the paper or the installed "
         f"software, {len(unchecked)} carry no mechanical check, and "
         f"{len(failed)} no longer reproduce. Every check below re-runs from "
         f"`build/lit/errata.py`.", "",
         "A check that no longer reproduces means one of two things, and the "
         "evidence line says which: the entry has since been corrected, so the "
         "error the check looks for is genuinely gone, or the reported error "
         "could not be substantiated. Read the evidence rather than the heading.",
         ""]

    for title, rs in (("Still reproduce", confirmed),
                      ("No longer reproduce: corrected, or unsubstantiated", failed),
                      ("Reported, not mechanically checked", unchecked)):
        if not rs:
            continue
        L += [f"## {title}", ""]
        for r in rs:
            L += [f"### {r['problem_id']} — {r.get('problem_title') or ''}", "",
                  f"*{r.get('kind')}, reader confidence {r.get('confidence')}, "
                  f"from {r.get('paper')} ({(r.get('paper_title') or '')[:70]})*", "",
                  "**The registry says.** " + (r.get("what_the_registry_says") or ""),
                  "", "**What is actually true.** "
                  + (r.get("what_is_actually_true") or ""), "",
                  "**Check.** " + (r.get("check_evidence") or ""), ""]
            if r.get("quote"):
                L += ["> " + r["quote"].replace("\n", " ")[:500], ""]

    open(os.path.join(REGISTRY, "ERRATA.md"), "w", encoding="utf8").write(
        "\n".join(L) + "\n")
    json.dump(rows, open(os.path.join(REGISTRY, "errata.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    print(f"{len(rows)} errata: {len(confirmed)} confirmed, {len(failed)} did not "
          f"reproduce, {len(unchecked)} unchecked")
    for r in rows:
        mark = {True: "OK ", False: "!! ", None: "?? "}[r["check_passed"]]
        print(f"  {mark}{r['problem_id']:8s} {r.get('kind'):20s} "
              f"{(r.get('check_evidence') or '')[:74]}")


if __name__ == "__main__":
    main()
