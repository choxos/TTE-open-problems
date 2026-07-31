#!/usr/bin/env python3
"""Bring across what the tte-review project already established.

That project is a separate review, of the concordance between target trial emulations and the
randomized trials they emulate. It screened a large TTE corpus by hand and retrieved full text
for a curated methodological subset. Three things from it are worth reusing here, and one thing
is worth being careful about.

  --screening   screening_master.csv -> screening/prior.jsonl
                A PRIOR, not a set of decisions. Every record it flags as methodological was
                EXCLUDED there, because a methods paper cannot contribute an effect estimate to
                a concordance analysis. Here the same records are the ones we want. The two
                projects also disagree about benchmarking studies, which that review excluded
                and this one keeps. And of its 428 methodological flags, 236 carry the exclusion
                reason "not_tte" rather than "methodological_or_review", so the flag is a hint
                about where to look and nothing stronger. Screening still happens here, record
                by record; the prior only changes the order things are read in and is reported
                as an agreement statistic afterwards.

  --curated     tte_methodological.csv + tte_methodological_categories.csv -> curated.json
                179 records with full PubMed metadata, and a hand-assigned decision, group and
                category for 176 of them. A human read these abstracts and placed them, which
                is a stronger prior than the screening flag.

  --fulltext    Copies the PDFs and HTML that project already retrieved into the layout
                fetch.py expects. MUST run after search.py, because the destination folder is
                derived from which phrase found the record and that is only known once the
                harvest has run.

  --reconcile   Patches manifest.json so imported files are visible to library.py. Without
                this step the copied PDFs sit on disk and no reader ever sees them.

Usage:
  python3 build/lit/import_tte_review.py --screening --curated
  python3 build/lit/search.py
  python3 build/lit/import_tte_review.py --fulltext
  python3 build/lit/fetch.py
  python3 build/lit/import_tte_review.py --reconcile
"""

import argparse
import csv
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")
SCREEN = os.path.join(OUT, "screening")
REFS = os.path.join(ROOT, "documentation", "refs")

SRC = os.environ.get("TTE_REVIEW",
                     os.path.join(os.path.dirname(ROOT), "tte-review"))
METH = os.path.join(SRC, "data", "raw", "fulltext", "Methodological")

csv.field_size_limit(10_000_000)


def _norm_doi(d):
    d = (d or "").strip().lower()
    d = re.sub(r"^(https?://(dx\.)?doi\.org/|doi:)", "", d)
    return d if d.startswith("10.") else ""


def _clean(v):
    v = (v or "").strip()
    return "" if v in ("NA", "N/A", "null", "None", "nan") else v


def rid(pmid, doi, title):
    """The same identity precedence batches.py uses, so the prior joins on the same key."""
    if _clean(pmid):
        return _clean(pmid)
    d = _norm_doi(doi)
    if d:
        return d[:60]
    return re.sub(r"[^a-z0-9]+", "", (title or "").lower())[:40]


def read_csv(path):
    if not os.path.exists(path):
        sys.exit(f"missing: {path}\nSet TTE_REVIEW to the tte-review checkout.")
    with open(path, encoding="utf8-sig" if False else "utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def do_screening():
    rows = read_csv(os.path.join(SRC, "search", "screening", "screening_master.csv"))
    os.makedirs(SCREEN, exist_ok=True)
    out, seen = [], set()
    for r in rows:
        key = rid(r.get("pmid"), r.get("doi") or r.get("doi_norm"), r.get("title"))
        if not key or key in seen:
            continue
        seen.add(key)
        meth = _clean(r.get("is_methodological")).lower()
        out.append({
            "id": key,
            "prior": {"yes": "likely-include", "no": "likely-exclude"}.get(meth, "unknown"),
            "prior_reason": _clean(r.get("exclusion_reason")) or None,
            "prior_include": _clean(r.get("include")) or None,
            "prior_by": _clean(r.get("reviewer")) or None,
        })
    path = os.path.join(SCREEN, "prior.jsonl")
    with open(path, "w", encoding="utf8") as fh:
        for o in out:
            fh.write(json.dumps(o, ensure_ascii=False) + "\n")
    n_yes = sum(1 for o in out if o["prior"] == "likely-include")
    print(f"prior.jsonl: {len(out)} records, {n_yes} likely-include")
    print("  This is a prior. It orders reading; it does not decide anything.")


def do_curated():
    meta = {}
    for r in read_csv(os.path.join(METH, "tte_methodological.csv")):
        pmid = _clean(r.get("pmid") or r.get("﻿pmid") or r.get("PMID"))
        if not pmid:
            continue
        pmc = _clean(r.get("pmc_id"))
        if pmc and not pmc.upper().startswith("PMC"):
            pmc = "PMC" + pmc
        meta[pmid] = {
            "pmid": pmid,
            "pmcid": pmc or None,
            "doi": _norm_doi(r.get("doi")) or None,
            "title": _clean(r.get("title")),
            "abstract": _clean(r.get("abstract")),
            "journal": _clean(r.get("journal")),
            "year": _clean(r.get("publication_date"))[:4] or None,
            "authors": [a.strip() for a in _clean(r.get("authors")).split(";") if a.strip()][:12],
            "mesh": [m.strip() for m in _clean(r.get("mesh_terms")).split(";") if m.strip()],
            "pubtypes": [p.strip() for p in _clean(r.get("publication_type")).split(";") if p.strip()],
        }
    n_dec = 0
    for r in read_csv(os.path.join(METH, "tte_methodological_categories.csv")):
        pmid = _clean(r.get("PMID") or r.get("﻿PMID"))
        if pmid not in meta:
            continue
        dec = _clean(r.get("Decision"))
        if not dec:
            continue
        meta[pmid].update({
            "curated_decision": dec,
            "curated_group": _clean(r.get("Group")) or None,
            "curated_group_name": _clean(r.get("Group_Name")) or None,
            "curated_category": _clean(r.get("Category")) or None,
        })
        n_dec += 1
    os.makedirs(REFS, exist_ok=True)
    path = os.path.join(REFS, "curated.json")
    json.dump(list(meta.values()), open(path, "w", encoding="utf8"),
              ensure_ascii=False, indent=1)
    inc = sum(1 for m in meta.values() if m.get("curated_decision") == "INCLUDE")
    print(f"curated.json: {len(meta)} records, {n_dec} with a hand decision, {inc} INCLUDE")


def _fetch_mod():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import fetch
    return fetch


def do_fulltext():
    fetch = _fetch_mod()
    recs_path = os.path.join(OUT, "records.jsonl")
    if not os.path.exists(recs_path):
        sys.exit("records.jsonl not found. Run build/lit/search.py first: the destination "
                 "folder depends on which phrase found the record.")
    by_pmid = {}
    for line in open(recs_path, encoding="utf8"):
        r = json.loads(line)
        if r.get("pmid"):
            by_pmid[str(r["pmid"])] = r

    pdfs = {os.path.splitext(f)[0]: os.path.join(METH, "pdfs", f)
            for f in os.listdir(os.path.join(METH, "pdfs")) if f.endswith(".pdf")}
    htmls = {os.path.splitext(f)[0]: os.path.join(METH, "html", f)
             for f in os.listdir(os.path.join(METH, "html")) if f.endswith(".html")}

    copied = skipped = unmatched = 0
    for pmid in sorted(set(pdfs) | set(htmls)):
        rec = by_pmid.get(pmid)
        if not rec:
            unmatched += 1
            continue
        dest = fetch.folder_for(rec)
        # fetch.handle() returns early on any folder that already has meta.json, so writing one
        # here would block the Europe PMC fetch that produces real JATS. Only files are copied.
        if os.path.exists(os.path.join(dest, "meta.json")):
            skipped += 1
            continue
        os.makedirs(dest, exist_ok=True)
        if pmid in pdfs and not os.path.exists(os.path.join(dest, "article.pdf")):
            shutil.copy2(pdfs[pmid], os.path.join(dest, "article.pdf"))
            copied += 1
        if pmid in htmls:
            # Never into the article slot: title_match and repos.article_text both parse that
            # as JATS, and a publisher HTML page is not JATS.
            sup = os.path.join(dest, "supplements")
            os.makedirs(sup, exist_ok=True)
            tgt = os.path.join(sup, "publisher.html")
            if not os.path.exists(tgt):
                shutil.copy2(htmls[pmid], tgt)
    print(f"full text imported: {copied} PDFs placed, {skipped} folders already fetched, "
          f"{unmatched} PMIDs not in the harvest")
    if unmatched:
        print("  Unmatched means the phrase set did not retrieve that paper. Worth reading: "
              "it is a direct test of whether the eight phrases cover the curated set.")


def do_reconcile():
    fetch = _fetch_mod()
    path = os.path.join(OUT, "manifest.json")
    if not os.path.exists(path):
        sys.exit("manifest.json not found. Run build/lit/fetch.py first.")
    man = json.load(open(path, encoding="utf8"))
    fixed = 0
    for m in man:
        d = m.get("dir")
        if not d:
            continue
        adir = d if os.path.isabs(d) else os.path.join(ROOT, d)
        pdf = os.path.join(adir, "article.pdf")
        if (m.get("files") or {}).get("pdf") or not os.path.exists(pdf):
            continue
        m.setdefault("files", {})["pdf"] = "article.pdf"
        m["source"] = "tte-review-import"
        # Re-verify so an imported PDF gets the same title-containment score and the same
        # supplement demotion a fetched one would. An import that skips this is an import
        # nobody checked. verify_files takes (dest, record, manifest_entry) and mutates the
        # third, which is the entry we are already holding.
        m["files"].setdefault("supplements", [])
        try:
            fetch.verify_files(adir, m, m)
        except Exception as exc:            # noqa: BLE001
            m["note"] = f"import verification failed: {exc}"
        fixed += 1
    json.dump(man, open(path, "w", encoding="utf8"), ensure_ascii=False, indent=1)
    print(f"manifest reconciled: {fixed} imported PDFs are now visible to library.py")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screening", action="store_true")
    ap.add_argument("--curated", action="store_true")
    ap.add_argument("--fulltext", action="store_true")
    ap.add_argument("--reconcile", action="store_true")
    a = ap.parse_args()
    if not any(vars(a).values()):
        ap.error("pick at least one of --screening --curated --fulltext --reconcile")
    if a.screening:
        do_screening()
    if a.curated:
        do_curated()
    if a.fulltext:
        do_fulltext()
    if a.reconcile:
        do_reconcile()


if __name__ == "__main__":
    main()
