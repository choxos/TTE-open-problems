#!/usr/bin/env python3
"""Apply the reviewed change set to the registry.

Everything applied here has already been through both models and, where it could
be, a mechanical check. This does the editing, records what it changed on the
entry itself, and refuses to touch anything it was not told to.

Four kinds of change:

  errata     factual corrections to what an entry says about the literature or
             about software, each confirmed by build/lit/errata.py
  citations  a cited surname that does not match the DOI, and works cited with
             two different years in different entries
  verdicts   problems whose verdict moves because findings survived both the
             reader and the second reviewer, minus the ones the chronology
             reviewer blocked
  reopen     problems an earlier audit closed that the reading found open again

Every edit writes a `reading_update` block onto the entry saying what changed and
on what evidence, because a verdict that moves without a trail is worse than one
that never moved: the page still looks authoritative and there is nothing to
check.

Usage:
  python3 build/lit/apply_changes.py --dry-run
  python3 build/lit/apply_changes.py --write
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIT = os.path.join(ROOT, "documentation", "audit")
READING = os.path.join(AUDIT, "reading")
REGISTRY = os.path.join(AUDIT, "registry")
STAMP = "2026-07-26 full-text reading of the consolidated library (687 papers)"


# ---- errata ---------------------------------------------------------------
# Each is a literal substring replacement, so a change that does not land is
# reported rather than silently skipped. The wording is the minimum edit that
# makes the sentence true; nothing else about the entry is touched.
ERRATA = [
    ("ADJ-12", "statement",
     "that articulation and minimal cut-set enumeration and removal "
     "vulnerability are still missing",
     "that articulation and minimal cut-set enumeration are still missing",
     "netmeta exports netimpact(), which measures a study's importance by the "
     "loss of precision when it is removed, citing Rucker et al. 2020. Removal "
     "vulnerability has shipped on CRAN for years and does not belong on a list "
     "of what is missing."),
    ("ADJ-12", "proposed_direction",
     "and add what is genuinely missing, articulation and minimal cut-set "
     "enumeration and removal vulnerability.",
     "and add what is genuinely missing, articulation and minimal cut-set "
     "enumeration.",
     "Same correction as the statement: removal vulnerability is implemented."),
    ("HET-04", "why_open",
     "have never been measured",
     "have not been measured for the population-indexed comparison this entry "
     "describes, though Song et al. 2012 measured them for the ordinary "
     "unadjusted test by simulation",
     "Song et al. 2012 (BMC Med Res Methodol 12:138) ran 5000 replicates per "
     "scenario across four heterogeneity levels and six network sizes, "
     "reporting type I error and power for the unadjusted test. The flat claim "
     "that these were never measured is false; the narrower population-indexed "
     "claim in the statement stands."),
    ("EVB-04", "statement",
     "conditional trial design sizes and configures a new trial against an "
     "existing network",
     "conditional trial design sizes and configures a new trial against an "
     "existing network to reach a target power or precision rather than by "
     "expected decision value",
     "Salanti et al. 2018 minimizes sample size for a target conditional power "
     "or precision. The words 'net benefit' and 'utility' do not appear in it. "
     "The entry's other citation, Heath et al. 2022 on expected value of sample "
     "information, is decision-value and is correctly described."),
]

# Where the registry credits a method to the wrong paper. The replacement adds
# the originator ahead of the paper that refined it; it does not remove the
# later work, which is correctly cited for what it actually contributed.
CALDWELL = {
    "cite": "Caldwell et al. 2016, Journal of Clinical Epidemiology",
    "doi_or_url": "https://doi.org/10.1016/j.jclinepi.2016.07.003",
    "what_it_does": "proposes threshold analysis for network meta-analysis and "
                    "computes, by a two-stage numerical procedure, the smallest "
                    "changes to the evidence that would change a recommendation; "
                    "Phillippo et al. credit this paper as the origin of the "
                    "method and describe their own contribution as replacing the "
                    "numerical procedure with an algebraic one",
}

KIEFER_NOTE = (
    "The rationale cited a Kiefer, Sturtz and Bender simulation with no year or "
    "DOI. The Kiefer, Sturtz and Bender paper in the corpus "
    "(doi:10.3238/arztebl.2015.0803) contains no simulation; it is a narrative "
    "review producing an appraisal checklist. The citation is unresolvable as "
    "written and has been withdrawn from the rationale."
)

DIS16_CITE = ("Hu, Wang, Ye and O'Connor 2022, BMC Medical Research Methodology")


def crossref_print_year(doi, cache):
    """The year on the version of record, not the online-first year.

    A work published online in one year and in an issue the next is cited both
    ways, and the registry does both. The issue year is the conventional
    citation, so that is what everything is normalized to; where a work has no
    print date the online year stands.
    """
    if doi in cache:
        return cache[doi]
    url = ("https://api.crossref.org/works/" + urllib.parse.quote(doi, safe="")
           + "?mailto=ahmad.pub@gmail.com")
    try:
        with urllib.request.urlopen(url, timeout=45) as r:
            m = json.load(r)["message"]
        pp = (m.get("published-print") or {}).get("date-parts") or [[None]]
        on = (m.get("issued") or {}).get("date-parts") or [[None]]
        cache[doi] = {"print": pp[0][0], "online": on[0][0]}
    except Exception as e:  # noqa: BLE001
        cache[doi] = {"print": None, "online": None, "error": str(e)[:90]}
    time.sleep(0.15)
    return cache[doi]


def note(p, kind, what, evidence):
    """Record a change, once. Returns False if this exact change is already there.

    This script has to be safe to re-run: a fix to one part of the change set
    should not append a second verdict sentence and a second trail entry to
    every problem that was already moved. Idempotence is checked on the note
    rather than on the field, because a verdict assignment is naturally
    idempotent while the rationale text appended beside it is not.
    """
    p.setdefault("reading_update", {"applied": STAMP, "changes": []})
    for c in p["reading_update"]["changes"]:
        if c.get("kind") == kind and c.get("what") == what:
            return False
    p["reading_update"]["changes"].append(
        {"kind": kind, "what": what, "evidence": evidence})
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if not (a.write or a.dry_run):
        sys.exit("pass --write or --dry-run")

    problems = json.load(open(os.path.join(REGISTRY, "problems.json"),
                              encoding="utf8"))
    by_id = {p["id"]: p for p in problems}
    pc = json.load(open(os.path.join(READING, "proposed-changes.json"),
                        encoding="utf8"))
    log = []

    # ---- 1. errata --------------------------------------------------------
    for pid, field, old, new, why in ERRATA:
        p = by_id.get(pid)
        if not p or old not in (p.get(field) or ""):
            log.append(f"ERRATUM MISS  {pid}.{field}: target text not found")
            continue
        # Keep what the field said before this edit. The entry already carries
        # the source's original wording from the first audit; without this the
        # intermediate version, which is what the published page said until now,
        # would vanish and the correction would not be checkable against it.
        before = p[field]
        p[field] = p[field].replace(old, new)
        note(p, "erratum", f"{field}: corrected a factual claim", why)
        p["reading_update"]["changes"][-1]["previous_text"] = before
        log.append(f"erratum       {pid}.{field}")

    # DIA-07's bad citation sits inside a recorded auditor opinion, not in the
    # entry's own prose. An opinion is a record of what someone said at the time,
    # so it is annotated rather than edited; rewriting it would make the trail
    # agree with the correction and destroy the evidence that the correction was
    # needed.
    p = by_id.get("DIA-07")
    if p:
        hit = next((o for o in (p.get("audit", {}).get("opinions") or [])
                    if "Kiefer" in (o.get("rationale") or "")), None)
        if hit:
            note(p, "erratum",
                 "an auditor opinion cites a simulation that does not exist; "
                 "the opinion text is left as recorded",
                 KIEFER_NOTE)
            hit["contested"] = KIEFER_NOTE
            log.append("erratum       DIA-07 auditor opinion annotated")
        else:
            log.append("ERRATUM MISS  DIA-07: no Kiefer citation found")

    # The method both entries describe was proposed by Caldwell et al. 2016, and
    # the paper the registry credits says so itself. The later work stays cited
    # for what it did contribute, an algebraic procedure in place of a numerical
    # one; what changes is who is named as having had the idea.
    for pid, old, new in (
        ("DIS-15",
         "Phillippo et al. 2018 derive bias-adjustment thresholds",
         "Caldwell et al. 2016 proposed threshold analysis for network "
         "meta-analysis and computed it numerically, and Phillippo et al. 2018 "
         "derive bias-adjustment thresholds algebraically"),
        ("DEC-12",
         "decision tipping points are",
         "decision tipping points, proposed by Caldwell et al. 2016 and given an "
         "algebraic form by Phillippo et al. 2018, are"),
    ):
        p = by_id.get(pid)
        if not p or old not in (p.get("statement") or ""):
            log.append(f"CALDWELL MISS {pid}: target text not found")
            continue
        before = p["statement"]
        p["statement"] = p["statement"].replace(old, new)
        have = {(w.get("doi_or_url") or "").lower()
                for w in p.get("prior_work") or []}
        if CALDWELL["doi_or_url"].lower() not in have:
            p.setdefault("prior_work", []).insert(0, dict(CALDWELL))
        if note(p, "citation", "corrected who is credited with threshold analysis",
                "Phillippo et al. (doi:10.1111/rssa.12341) state in their own "
                "text that 'Threshold analysis has previously been proposed by "
                "Caldwell et al. (2016)' and that their contribution avoids the "
                "limitations of that approach. Caldwell et al. 2016 is now cited "
                "as the origin; the later work remains cited for the algebraic "
                "procedure."):
            p["reading_update"]["changes"][-1]["previous_text"] = before
        log.append(f"citation      {pid} attribution corrected to Caldwell 2016")

    # ---- 2. citations -----------------------------------------------------
    p = by_id.get("DIS-16")
    if p:
        hit = False
        for w in p.get("prior_work") or []:
            if "10.1186/s12874-022-01792-6" in (w.get("doi_or_url") or ""):
                old = w["cite"]
                w["cite"] = DIS16_CITE
                note(p, "citation", f"corrected attribution: {old!r} -> "
                     f"{DIS16_CITE!r}",
                     "CrossRef resolves this DOI to Hu, Wang, Ye and O'Connor, "
                     "'Using information from network meta-analyses to optimize "
                     "the power and sample allocation of a subsequent trial with "
                     "a new treatment'.")
                log.append("citation      DIS-16 attribution corrected")
                hit = True
        if not hit:
            log.append("CITATION MISS DIS-16: DOI not found in prior_work")

    rows = json.load(open(os.path.join(REGISTRY, "citation-check.json"),
                          encoding="utf8"))
    years = {}
    for r in rows:
        if r.get("doi"):
            m = re.search(r"\b(19|20)\d{2}\b", r.get("cite") or "")
            if m:
                years.setdefault(r["doi"], set()).add(m.group(0))
    split = {d for d, ys in years.items() if len(ys) > 1}
    cache_path = os.path.join(REGISTRY, ".crossref-print-cache.json")
    cache = json.load(open(cache_path, encoding="utf8")) if os.path.exists(
        cache_path) else {}
    fixed = 0
    for doi in sorted(split):
        rec = crossref_print_year(doi, cache)
        want = rec.get("print") or rec.get("online")
        if not want:
            log.append(f"YEAR MISS     {doi}: no CrossRef date")
            continue
        for p in problems:
            for w in p.get("prior_work") or []:
                if doi.lower() not in (w.get("doi_or_url") or "").lower():
                    continue
                m = re.search(r"\b(19|20)\d{2}\b", w.get("cite") or "")
                if m and m.group(0) != str(want):
                    old = w["cite"]
                    # Naturally idempotent: after this the cited year equals
                    # `want`, so a re-run does not match. note() dedupes the trail.
                    w["cite"] = w["cite"].replace(m.group(0), str(want))
                    note(p, "citation",
                         f"normalized a citation year: {old!r} -> {w['cite']!r}",
                         f"{doi} is cited with two different years across the "
                         f"registry. CrossRef gives {rec.get('online')} online "
                         f"and {rec.get('print')} in print; the issue year is "
                         f"used throughout.")
                    fixed += 1
    json.dump(cache, open(cache_path, "w", encoding="utf8"), indent=1)
    log.append(f"citation      {fixed} year references normalized across "
               f"{len(split)} works")

    # ---- 3. verdict changes ----------------------------------------------
    flips = [c for c in pc["changes"] if c.get("proposed_verdict")]
    for c in flips:
        p = by_id.get(c["id"])
        if not p:
            continue
        # Guard on the destination, not on a note key built from the current
        # verdict. The change set is computed against the registry as it was
        # before any of this ran, so on a second pass `p["verdict"]` is already
        # the target and a key like "confirmed-open -> partially-addressed"
        # silently becomes "partially-addressed -> partially-addressed": a
        # different string, which the dedupe then lets through. Asking whether
        # the entry is already where it is being sent cannot drift that way.
        if p["verdict"] == c["proposed_verdict"]:
            continue
        old = p["verdict"]
        note(p, "verdict", f"{old} -> {c['proposed_verdict']}", "placeholder")
        p["verdict"] = c["proposed_verdict"]
        cites = sorted({f.get("doi") for f in c["findings"]
                        if f.get("doi") and f.get("effect") != "supports-open"})
        drv = c["flip_drivers"]
        p["verdict_rationale"] = (
            (p.get("verdict_rationale") or "").rstrip()
            + f" Reopened by the full-text reading: {drv} finding"
            + ("" if drv == 1 else "s")
            + f" from {len(c['flip_papers'])} paper"
            + ("" if len(c["flip_papers"]) == 1 else "s")
            + " survived both the reader and an independent second reviewer, so "
              "the verdict moves from " + old + " to " + c["proposed_verdict"]
            + ("." if drv > 1 else ", on a single finding.")).strip()
        p["reading_update"]["changes"][-1]["evidence"] = (
            f"{drv} surviving finding" + ("" if drv == 1 else "s")
            + " from: " + "; ".join(c["flip_papers"])
            + (f". New citations: {', '.join(cites)}" if cites else ""))
        log.append(f"verdict       {c['id']}: {old} -> {c['proposed_verdict']} "
                   f"({drv} driver{'' if drv == 1 else 's'})")

    # Problems whose flip was suppressed still gain the record of why, because a
    # reader who sees the evidence and not the decision will assume it was missed.
    for c in pc["changes"]:
        b = c.get("flip_blocked_by_timeline")
        t = c.get("flip_blocked_as_thin")
        p = by_id.get(c["id"])
        if not p:
            continue
        if b:
            note(p, "verdict-held", "verdict left unchanged",
                 f"Later work reports progress, but on the chronology review the "
                 f"second reviewer judged it '{b['verdict']}' at {b['confidence']} "
                 f"confidence: {b['reason']}")
            log.append(f"held          {c['id']}: blocked by chronology review")
        if t:
            note(p, "verdict-held", "verdict left unchanged",
                 f"The only finding arguing for a change came from one paper and "
                 f"its reader marked it low confidence: {t['paper']}")
            log.append(f"held          {c['id']}: single low-confidence finding")

    # ---- 4. reopen candidates --------------------------------------------
    for r in pc["reopen_candidates"]:
        p = by_id.get(r["id"])
        if not p:
            continue
        note(p, "reopen-candidate",
             f"{r.get('open_findings', r.get('evidence_count'))} findings from "
             f"the reading assert this problem is open while the registry "
             f"carries `{p['verdict']}`",
             "Flagged, not applied: reversing an earlier audit's closure needs "
             "the closure's own evidence re-examined alongside this, which the "
             "reading did not do. See documentation/audit/reading/PROPOSED.md.")
        log.append(f"reopen-flag   {r['id']} ({p['verdict']})")

    if a.write:
        json.dump(problems, open(os.path.join(REGISTRY, "problems.json"), "w",
                                 encoding="utf8"), indent=1, ensure_ascii=False)
    for line in log:
        print(("  " if not line[:1].isupper() else "!! ") + line)
    print(f"\n{len(flips)} verdicts changed, {len(pc['reopen_candidates'])} "
          f"reopen candidates flagged, {fixed} citation years normalized"
          + ("" if a.write else "   (dry run; nothing written)"))


if __name__ == "__main__":
    main()
