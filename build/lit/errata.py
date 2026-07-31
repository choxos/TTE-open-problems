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
def check_dia07():
    c = counts("L0525", ["simulat", "monte carlo", "narrative review", "review"])
    ok = c["simulat"] == 0 and c["monte carlo"] == 0
    return ok, (f"Kiefer, Sturtz & Bender 2015 (L0525, doi:10.3238/arztebl.2015.0803): "
                f"'simulat' appears {c['simulat']} times, 'Monte Carlo' "
                f"{c['monte carlo']}, 'review' {c['review']}. The registry cites it "
                f"as a simulation and gives neither year nor DOI, so the citation "
                f"cannot be resolved to a different Kiefer paper either.")


def check_het04():
    c = counts("L0600", ["type i error", "5000", "simulation evaluation", "power"])
    ok = c["type i error"] > 0 and c["5000"] > 0
    return ok, (f"Song et al. 2012 (L0600) is titled 'Simulation evaluation of "
                f"statistical properties of methods for indirect and mixed treatment "
                f"comparisons' ({c['simulation evaluation']} occurrences), generated "
                f"5000 replicates per scenario ({c['5000']} occurrences of '5000') "
                f"and mentions 'type I error' {c['type i error']} times. HET-04's "
                f"`why_open` says these rates 'have never been measured'.")


def check_evb04():
    c = counts("L0441", ["net benefit", "utility", "cost", "sample size",
                         "power", "precision"])
    ok = c["net benefit"] == 0 and c["utility"] == 0 and c["sample size"] > 0
    return ok, (f"Salanti et al. 2018 (L0441, conditional trial design): "
                f"'net benefit' {c['net benefit']}, 'utility' {c['utility']}, "
                f"'cost' {c['cost']}, against 'sample size' {c['sample size']}, "
                f"'power' {c['power']}, 'precision' {c['precision']}. EVB-04 files "
                f"it under methods that choose data collection 'by expected decision "
                f"value'. The entry's other citation, Heath et al. 2022 on expected "
                f"value of sample information, is decision-value and is correctly "
                f"described; only the Salanti clause overreaches.")


def check_caldwell():
    t = paper_text("L0462")
    quotes = [q for q in (
        "Threshold analysis has previously been proposed by Caldwell et al. (2016)",
        "avoids the limitations of the approach that was taken by Caldwell et al. (2016)",
    ) if q in t]
    # Ask about the two entries that make the attribution, not about the whole
    # registry. Once other entries cite Caldwell correctly, a registry-wide count
    # stops being zero and the check silently reports the error as fixed while
    # DIS-15 and DEC-12 still credit the wrong paper.
    problems = {p["id"]: p for p in json.load(open(
        os.path.join(REGISTRY, "problems.json"), encoding="utf8"))}
    missing = [i for i in ("DIS-15", "DEC-12")
               if "caldwell" not in json.dumps(problems.get(i, {})).lower()]
    ok = bool(quotes) and bool(missing)
    return ok, ("Phillippo et al. (L0462, doi:10.1111/rssa.12341), the paper the "
                "registry credits, says of itself: "
                + "; ".join(f'"{q}"' for q in quotes)
                + ". Caldwell et al. 2016 is J Clin Epidemiol 80:68-76, "
                "doi:10.1016/j.jclinepi.2016.07.003, and is in this corpus as "
                "L0513. "
                + (f"Entries still crediting only the later paper: "
                   f"{', '.join(missing)}." if missing
                   else "Both DIS-15 and DEC-12 now cite it."))


def check_adj12():
    try:
        r = subprocess.run(
            ["R", "--vanilla", "-s", "-e",
             'cat(as.character("netimpact" %in% getNamespaceExports("netmeta")), '
             'as.character(packageVersion("netmeta")))'],
            capture_output=True, text=True, timeout=120)
        out = r.stdout.strip()
    except Exception as e:  # noqa: BLE001
        return None, f"could not run R: {e}"
    ok = out.lower().startswith("true")
    return ok, (f"`netimpact` exported from the installed netmeta: {out}. Its "
                f"documentation describes it as measuring 'the importance of "
                f"individual studies in network meta-analysis by the reduction of "
                f"the precision if the study is removed', citing Rucker et al. "
                f"2020. ADJ-12 lists removal vulnerability among the diagnostics "
                f"'still missing'; the neighbouring clause about articulation "
                f"points and minimal cut-set enumeration stands.")


def check_qba29():
    path = os.path.join(REGISTRY, "citation-check.json")
    if not os.path.exists(path):
        return None, "run build/lit/check_citations.py first"
    rows = json.load(open(path, encoding="utf8"))
    doi = "10.1177/0272989X17725740"
    years = {}
    for r in rows:
        if (r.get("doi") or "").lower() == doi.lower():
            m = re.search(r"\b(19|20)\d{2}\b", r.get("cite") or "")
            if m:
                years.setdefault(m.group(0), []).append(r["id"])
    cr = next((r.get("crossref_year") for r in rows
               if (r.get("doi") or "").lower() == doi.lower()), None)
    ok = len(years) > 1
    return ok, (f"{doi} is cited as "
                + "; ".join(f"{y} in {', '.join(sorted(set(v)))}"
                            for y, v in sorted(years.items()))
                + f". CrossRef gives {cr}. Both dates are defensible as epub versus "
                f"print; the registry disagreeing with itself is not.")


CHECKS = {
    "DIA-07": check_dia07,
    "HET-04": check_het04,
    "EVB-04": check_evb04,
    "DEC-12": check_caldwell,
    "DIS-15": check_caldwell,
    "ADJ-12": check_adj12,
    "QBA-29": check_qba29,
}


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
