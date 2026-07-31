#!/usr/bin/env python3
"""Flag retracted and corrected papers in the library before they are read as evidence.

A reader found a retracted paper in a batch and declined to draw findings from it.
Nothing in the pipeline had checked, so that catch depended on the retraction
being mentioned in the copy that happened to be fetched. It is not always: a PDF
downloaded before the retraction carries no notice at all, and reads as ordinary
evidence forever.

PubMed records this in two places, and both matter. `PublicationType` marks the
article itself once it has been retracted or has published errata; the comments
and corrections list points at the notice. Papers with no PMID cannot be checked
this way and are reported as unchecked rather than clean.

Output: documentation/refs/RETRACTIONS.md and retractions.json, plus a `status`
field written back onto the affected library entries.

Usage:
  python3 build/lit/retractions.py              # from the cached efetch XML
  python3 build/lit/retractions.py --online     # + query NCBI for uncached PMIDs
"""

import argparse
import glob
import json
import os
import re
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REFS = os.path.join(ROOT, "documentation", "refs")
SYS = os.path.join(REFS, "systematic")
CACHE = os.path.join(SYS, "_cache")
EFETCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"

# The publication types that say something is wrong with the paper itself, as
# opposed to the types that mark the notice announcing it.
BAD_TYPES = {
    "Retracted Publication": "retracted",
    "Expression of Concern": "concern",
    "Corrected and Republished Article": "corrected-republished",
}
NOTICE_TYPES = {
    "Retraction of Publication", "Published Erratum",
    "Expression of Concern (Published Item)",
}
# RefType values on CommentsCorrections that point from a paper to its notice.
BAD_REFTYPE = {
    "RetractionIn": "retracted",
    "ExpressionOfConcernIn": "concern",
    "ErratumIn": "erratum",
    "RepublishedIn": "corrected-republished",
}
SEVERITY = ["retracted", "concern", "corrected-republished", "erratum", "notice"]
# A notice announces itself in its title. PubMed does not always give the notice
# a distinguishing publication type, so the title is the more reliable signal.
NOTICE_TITLE = re.compile(
    r"^\W*(retraction|expression of concern|erratum|corrigendum|correction|"
    r"withdrawal|notice of (retraction|concern)|republished|"
    r"authors?'? repl(y|ies))\b", re.I)


def scan_cache():
    """pmid -> what PubMed says is wrong with it, from the harvest's own XML."""
    flags = defaultdict(dict)
    for path in sorted(glob.glob(os.path.join(CACHE, "*_pubmed_*.xml"))):
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            continue
        for art in root.iter("PubmedArticle"):
            pm = art.findtext("MedlineCitation/PMID")
            if not pm:
                continue
            rec = flags[pm.strip()]
            for t in art.findall(
                    "MedlineCitation/Article/PublicationTypeList/PublicationType"):
                kind = BAD_TYPES.get((t.text or "").strip())
                if kind:
                    rec[kind] = rec.get(kind) or {"via": "publication-type"}
                if (t.text or "").strip() in NOTICE_TYPES:
                    rec["is_notice"] = True
            for cc in art.findall("MedlineCitation/CommentsCorrectionsList/"
                                  "CommentsCorrections"):
                kind = BAD_REFTYPE.get(cc.get("RefType") or "")
                if not kind:
                    continue
                rec[kind] = {"via": "comments-corrections",
                             "notice_pmid": cc.findtext("PMID"),
                             "notice": (cc.findtext("RefSource") or "").strip()}
    return {k: v for k, v in flags.items() if v}


def fetch_online(pmids, chunk=180, pause=0.4):
    """Ask NCBI directly for PMIDs the cache never covered."""
    out = {}
    pmids = sorted(pmids)
    for i in range(0, len(pmids), chunk):
        part = pmids[i:i + chunk]
        q = urllib.parse.urlencode({"db": "pubmed", "retmode": "xml",
                                    "id": ",".join(part)})
        try:
            with urllib.request.urlopen(f"{EFETCH}?{q}", timeout=120) as r:
                blob = r.read()
        except Exception as e:  # noqa: BLE001
            print(f"  efetch failed for {len(part)} pmids: {e}")
            continue
        tmp = os.path.join(CACHE, f"retraction_check_{i:06d}.xml")
        os.makedirs(CACHE, exist_ok=True)
        open(tmp, "wb").write(blob)
        time.sleep(pause)
    return out


def worst(rec):
    for s in SEVERITY:
        if s in rec:
            return s
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--online", action="store_true",
                    help="query NCBI for PMIDs the cache does not cover")
    ap.add_argument("--write-library", action="store_true",
                    help="write a status field onto affected library entries")
    args = ap.parse_args()

    lib = json.load(open(os.path.join(REFS, "library.json"), encoding="utf8"))
    by_pmid = {}
    for c in lib:
        if c.get("pmid"):
            by_pmid.setdefault(str(c["pmid"]).strip(), []).append(c)

    if args.online:
        flags_before = scan_cache()
        missing = [p for p in by_pmid if p not in flags_before]
        print(f"querying NCBI for {len(missing)} PMIDs not in the cache")
        fetch_online(missing)

    flags = scan_cache()
    hits = []
    for pmid, rec in flags.items():
        cats = by_pmid.get(pmid)
        if not cats:
            continue
        kind = worst(rec)
        # A notice carries the same publication type as the paper it is about.
        # Calling the notice a flawed paper is wrong twice over: it is sound, and
        # it is not a paper at all, so it should not be read as evidence either.
        if rec.get("is_notice") or any(
                NOTICE_TITLE.match(c.get("title") or "") for c in cats):
            kind = "notice"
        if not kind:
            continue
        for c in cats:
            hits.append({"id": c["id"], "pmid": pmid, "kind": kind,
                         "title": c.get("title"), "doi": c.get("doi"),
                         "topic": c.get("topic"), "detail": rec.get(kind),
                         "path": c.get("path")})
    hits.sort(key=lambda h: (SEVERITY.index(h["kind"]), h["id"]))

    unchecked = [c["id"] for c in lib
                 if not c.get("pmid") and (c.get("pdf") or c.get("xml")
                                           or c.get("text"))
                 and not c.get("duplicate_of")]

    json.dump({"flagged": hits, "unchecked_no_pmid": unchecked},
              open(os.path.join(REFS, "retractions.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    tally = Counter(h["kind"] for h in hits)
    lines = ["# Retractions, concerns and errata in the library", "",
             f"{len(by_pmid)} of {len(lib)} catalog entries carry a PMID and could "
             f"be checked against PubMed. {len(hits)} are flagged. "
             f"{len(unchecked)} readable entries have no PMID and could not be "
             f"checked this way; absence of a flag there is not evidence of "
             f"anything.", "",
             "`retracted` means the paper must not be used as evidence. "
             "`concern` and `corrected-republished` mean read the notice before "
             "relying on it. `erratum` is usually minor but is listed so a "
             "finding can be checked against the correction. `notice` means the "
             "catalog entry is itself a retraction or erratum announcement rather "
             "than a paper, so there is nothing in it to read.", "",
             "| kind | n |", "|---|---:|"]
    for k, v in tally.most_common():
        lines.append(f"| {k} | {v} |")
    if hits:
        lines += ["", "| id | kind | title | notice |", "|---|---|---|---|"]
        for h in hits:
            d = h.get("detail") or {}
            note = d.get("notice") or d.get("via") or ""
            lines.append(f"| {h['id']} | {h['kind']} | "
                         f"{(h.get('title') or '')[:70]} | {note[:60]} |")

    open(os.path.join(REFS, "RETRACTIONS.md"), "w", encoding="utf8").write(
        "\n".join(lines) + "\n")

    if args.write_library and hits:
        mark = {h["id"]: h for h in hits}
        for c in lib:
            h = mark.get(c["id"])
            if h:
                c["status"] = h["kind"]
                c["status_detail"] = h.get("detail")
        json.dump(lib, open(os.path.join(REFS, "library.json"), "w",
                            encoding="utf8"), indent=1, ensure_ascii=False)
        print(f"marked {len(mark)} library entries")

    print(f"{len(by_pmid)} entries checkable by PMID, {len(hits)} flagged")
    for k, v in tally.most_common():
        print(f"  {k:24s} {v}")
    print(f"  no PMID, unchecked     {len(unchecked)}")
    for h in hits:
        if h["kind"] in ("retracted", "concern", "notice"):
            print(f"  !! {h['id']} {h['kind']}: {(h.get('title') or '')[:64]}")


if __name__ == "__main__":
    main()
