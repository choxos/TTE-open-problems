#!/usr/bin/env python3
"""Stage 1: harvest citation records for the eight target-trial-emulation search phrases.

Searches PubMed and PMC for each phrase in title, abstract and author keywords,
then fetches the full citation record for every hit. PMC is searched as well as
PubMed because PMC carries some records PubMed does not index (author
manuscripts, a few non-MEDLINE journals, deposited preprints).

Output: documentation/refs/systematic/records.jsonl , one JSON object per unique
article, with the phrases that found it and the databases it came from.

Usage: python3 build/lit/search.py [--refresh]
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from xml.etree import ElementTree as ET

EMAIL = "ahmad.pub@gmail.com"
UA = f"TTE-open-problems/1.0 (mailto:{EMAIL})"
EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")
CACHE = os.path.join(OUT, "_cache")

# Ordered narrowest first, by measured PubMed size. The order is load-bearing downstream:
# topic assignment is first-match-wins and the phrases nest. "target trial emulation" contains
# "trial emulation" and is contained by "target trial", so a paper matching the specific phrase
# must be filed under it rather than under the broad one that also matches.
#
# Each topic carries every surface form, because PubMed does NOT stem inside a quoted phrase.
# Measured: "target trial" returns 1930 and "target trials" 415, and a paper titled "Emulating
# target trials to study ICU interventions" is retrieved by the plural and NOT by the singular.
# A singular-only phrase set silently loses those. Counts measured 2026-07-30.
PHRASES = {
    "ccw":   ["clone censor weight", "clone-censor-weight", "cloning censoring weighting"],
    "emul":  ["emulated trial", "emulated trials",
              # ~50 records, most of them electroencephalography, where a "pseudotrial" is a
              # resampled epoch and nothing to do with causal inference. Kept anyway: the
              # handful that are ours include a propensity-score paper that no other phrase
              # retrieves, and screening 40 obvious excludes is cheaper than missing it.
              "pseudotrial", "pseudotrials", "pseudo-trial", "pseudo-trials"],
    # PubMed normalizes the hyphen, so "g formula" and "g-formula" return an identical 558 and
    # only one is needed. It also breaks a quoted phrase it cannot find in its phrase index into
    # words and ANDs them, so "g-formula" is really "g AND formula" and retrieves infant formula,
    # intraocular lens power formulas, MDRD, and chemical formulas. "parametric g-formula" is
    # clean but returns 223 of the 558. The broad form is kept: this is a systematic search, the
    # noise is obvious on sight during screening, and a missed methods paper is not recoverable.
    "gform": ["parametric g-formula", "g-formula"],
    "msm":   ["marginal structural model", "marginal structural models"],
    "itb":   ["immortal time bias", "immortal person-time bias", "immortal time"],
    "tte":   ["target trial emulation", "target trial emulations", "emulation of a target trial"],
    "temu":  ["trial emulation", "trial emulations", "emulating a trial"],
    "tt":    ["target trial", "target trials"],
}

# NCBI allows 3 requests/second without an API key.
THROTTLE = 0.36
_last = [0.0]


def get(url, data=None, tries=5):
    for attempt in range(tries):
        wait = THROTTLE - (time.time() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.time()
        try:
            req = urllib.request.Request(
                url,
                data=data.encode() if data else None,
                headers={"User-Agent": UA, "Accept": "*/*"},
            )
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read().decode("utf8", "ignore")
        except Exception as e:  # noqa: BLE001 - transient NCBI failures are routine
            if attempt == tries - 1:
                raise
            print(f"    retry {attempt + 1} after {e}", file=sys.stderr)
            time.sleep(2 ** attempt)
    return ""


CEILING = 9999  # NCBI will not return more than this many ids for one query


def esearch(db, term, retmax=CEILING):
    q = urllib.parse.urlencode(
        {"db": db, "term": term, "retmax": retmax, "retmode": "json",
         "email": EMAIL, "tool": "TTE-open-problems"}
    )
    # strict=False: NCBI echoes the query back with raw control characters,
    # which the default decoder rejects.
    d = json.loads(get(f"{EUTILS}/esearch.fcgi?{q}"), strict=False)["esearchresult"]
    return d.get("idlist", []), int(d["count"])


def collect_ids(db, term):
    """Every id for a term, splitting by publication date when the query is too big.

    Neither the id-list form nor the history server will hand back more than
    about 10 000 records for a single query, and the broader phrases here are
    well past that. Partitioning by year keeps every sub-query under the ceiling; the
    partition totals are checked against the unpartitioned count so a silent
    truncation cannot pass unnoticed.
    """
    ids, total = esearch(db, term)
    if total <= CEILING:
        return ids, total, total

    seen, harvested = [], 0
    for y in range(1990, 2029):
        sub = f'({term}) AND ("{y}/01/01"[PDAT] : "{y}/12/31"[PDAT])'
        sids, stotal = esearch(db, sub)
        if stotal > CEILING:
            for m in range(1, 13):
                msub = f'({term}) AND ("{y}/{m:02d}/01"[PDAT] : "{y}/{m:02d}/31"[PDAT])'
                mids, mtotal = esearch(db, msub)
                seen.extend(mids)
                harvested += mtotal
        else:
            seen.extend(sids)
            harvested += stotal
    uniq = list(dict.fromkeys(seen))
    return uniq, total, harvested


def _text(node):
    """Flatten an element's text, including markup children like <i> and <sup>."""
    return re.sub(r"\s+", " ", "".join(node.itertext())).strip() if node is not None else ""


def article_ids(art, paths):
    """The record's own identifiers, from its ArticleIdList and nowhere else.

    A blanket art.iter("ArticleId") also walks ReferenceList and
    CommentsCorrectionsList, so the DOI and PMCID that come back belong to the
    last work the article happens to cite. Restrict to the declared paths.
    """
    ids = {}
    for path in paths:
        for i in art.findall(path):
            t, v = i.get("IdType"), (i.text or "").strip()
            if t and v and t not in ids:
                ids[t] = v
    pmc = ids.get("pmc", "")
    if pmc and not pmc.upper().startswith("PMC"):
        ids["pmc"] = "PMC" + pmc
    return ids


def parse_pubmed(xml):
    root = ET.fromstring(xml)
    out = []
    for art in root.iter("PubmedBookArticle"):
        rec = parse_pubmed_book(art)
        if rec:
            out.append(rec)
    for art in root.iter("PubmedArticle"):
        cit = art.find("MedlineCitation")
        a = cit.find(".//Article")
        if a is None:
            continue
        ids = article_ids(art, ("PubmedData/ArticleIdList/ArticleId",))
        j = a.find("Journal")
        year = ""
        for tag in (".//ArticleDate/Year", ".//JournalIssue/PubDate/Year",
                    ".//JournalIssue/PubDate/MedlineDate"):
            v = _text(a.find(tag)) or _text(cit.find(tag))
            if v:
                year = v[:4]
                break
        abstract = " ".join(
            (seg.get("Label", "") + ": " if seg.get("Label") else "") + _text(seg)
            for seg in a.iter("AbstractText")
        ).strip()
        out.append({
            "pmid": _text(cit.find("PMID")),
            "pmcid": ids.get("pmc", ""),
            "doi": ids.get("doi", "").lower(),
            "title": _text(a.find("ArticleTitle")),
            "abstract": abstract,
            "journal": _text(j.find("Title")) if j is not None else "",
            "journal_abbrev": _text(j.find("ISOAbbreviation")) if j is not None else "",
            "year": year,
            "pubtypes": [_text(p) for p in a.iter("PublicationType")],
            "keywords": [_text(k) for k in cit.iter("Keyword")],
            "mesh": [_text(m.find("DescriptorName")) for m in cit.iter("MeshHeading")],
            "authors": [
                (_text(au.find("LastName")) + " " + _text(au.find("Initials"))).strip()
                for au in a.iter("Author")
            ][:12],
            "language": _text(a.find(".//Language")),
        })
    return out


def parse_pubmed_book(art):
    """Bookshelf records, which PubMed returns as PubmedBookArticle.

    Worth parsing rather than dropping: the NICE Decision Support Unit technical
    support documents, the canonical methods guidance for this field, are indexed
    here and nowhere else in PubMed.
    """
    cit = art.find("BookDocument")
    if cit is None:
        return None
    ids = article_ids(art, ("BookDocument/ArticleIdList/ArticleId",
                            "PubmedBookData/ArticleIdList/ArticleId"))
    book = cit.find("Book")
    title = _text(cit.find("ArticleTitle")) or _text(book.find("BookTitle") if book is not None else None)
    abstract = " ".join(
        (seg.get("Label", "") + ": " if seg.get("Label") else "") + _text(seg)
        for seg in cit.iter("AbstractText")
    ).strip()
    return {
        "pmid": _text(cit.find("PMID")),
        "pmcid": ids.get("pmc", ""),
        "doi": ids.get("doi", "").lower(),
        "title": title,
        "abstract": abstract,
        "journal": _text(book.find("BookTitle")) if book is not None else "",
        "journal_abbrev": _text(book.find("Publisher/PublisherName")) if book is not None else "",
        "year": (_text(book.find("PubDate/Year")) if book is not None else "")[:4],
        "pubtypes": [_text(p) for p in cit.iter("PublicationType")] or ["Book Chapter"],
        "keywords": [_text(k) for k in cit.iter("Keyword")],
        "mesh": [],
        "authors": [
            (_text(au.find("LastName")) + " " + _text(au.find("Initials"))).strip()
            for au in cit.iter("Author")
        ][:12],
        "language": _text(cit.find(".//Language")),
    }


def parse_pmc(xml):
    """PMC efetch returns full JATS; take only the front matter we need."""
    out = []
    root = ET.fromstring(xml)
    for art in list(root.iter("article")) + list(root.iter("book")):
        meta = art.find(".//article-meta")
        if meta is None:
            continue
        ids = {i.get("pub-id-type"): (i.text or "").strip() for i in meta.iter("article-id")}
        # PMC's own JATS labels the accession "pmcid"; "pmc" appears in
        # publisher-deposited files. Take either, and always store it prefixed.
        pmcid = ids.get("pmcid") or ids.get("pmc") or ""
        if pmcid and not pmcid.upper().startswith("PMC"):
            pmcid = "PMC" + pmcid
        jm = art.find(".//journal-meta")
        jtitle = _text(jm.find(".//journal-title")) if jm is not None else ""
        abbrev = ""
        if jm is not None:
            for jid in jm.iter("journal-id"):
                if jid.get("journal-id-type") in ("nlm-ta", "iso-abbrev"):
                    abbrev = _text(jid)
                    break
        year = ""
        for pd in meta.iter("pub-date"):
            y = _text(pd.find("year"))
            if y:
                year = y
                break
        out.append({
            "pmid": ids.get("pmid", ""),
            "pmcid": pmcid,
            "doi": ids.get("doi", "").lower(),
            "title": _text(meta.find(".//article-title")),
            "abstract": " ".join(_text(ab) for ab in meta.iter("abstract")).strip(),
            "journal": jtitle,
            "journal_abbrev": abbrev,
            "year": year,
            "pubtypes": [art.get("article-type", "")],
            "keywords": [_text(k) for k in meta.iter("kwd")],
            "mesh": [],
            "authors": [
                (_text(c.find("surname")) + " " + _text(c.find("given-names"))).strip()
                for c in meta.iter("name")
            ][:12],
            "language": "",
        })
    return out


def efetch(db, ids, parser, tag):
    """Fetch records in batches by explicit id, caching each batch.

    The cache file is named for the CONTENT of the batch, not its position. Keying on
    position alone is wrong the moment the query changes: batch 3 of the old id list and
    batch 3 of the new one get the same filename, so the second run reads the first run's
    records back and reports its own, larger, id count while parsing the older set. That
    failure is silent, because every count the run prints comes from esearch and is correct;
    only the parsed records are stale. Hashing the ids makes a changed batch a different
    file, so a changed query simply misses the cache and refetches.
    """
    recs, size, total = [], 200, len(ids)
    os.makedirs(CACHE, exist_ok=True)
    for i in range(0, total, size):
        digest = hashlib.sha1(",".join(ids[i:i + size]).encode()).hexdigest()[:12]
        path = os.path.join(CACHE, f"{tag}_{i:06d}_{digest}.xml")
        if os.path.exists(path) and os.path.getsize(path) > 200:
            xml = open(path, encoding="utf8", errors="ignore").read()
        else:
            xml = get(f"{EUTILS}/efetch.fcgi",
                      data=urllib.parse.urlencode(
                          {"db": db, "id": ",".join(ids[i:i + size]),
                           "retmode": "xml", "email": EMAIL}))
            open(path, "w", encoding="utf8").write(xml)
        try:
            recs.extend(parser(xml))
        except ET.ParseError as e:
            print(f"    unparseable batch {path}: {e}", file=sys.stderr)
        print(f"    {min(i + size, total)}/{total}", end="\r", file=sys.stderr)
    print(file=sys.stderr)
    return recs


def key(r):
    """Identity for deduplication: PMID wins, then DOI, then PMCID, then title."""
    if r.get("pmid"):
        return "pmid:" + r["pmid"]
    if r.get("doi"):
        return "doi:" + r["doi"]
    if r.get("pmcid"):
        return "pmcid:" + r["pmcid"]
    return "title:" + re.sub(r"[^a-z0-9]+", "", r["title"].lower())[:80]


def merge(store, rec, phrase, db):
    k = key(rec)
    cur = store.get(k)
    if cur is None:
        rec["found_by"] = [phrase]
        rec["dbs"] = [db]
        store[k] = rec
        return
    # PubMed records are richer, so let them fill gaps left by a PMC-only hit.
    for f, v in rec.items():
        if v and not cur.get(f):
            cur[f] = v
    if phrase not in cur["found_by"]:
        cur["found_by"].append(phrase)
    if db not in cur["dbs"]:
        cur["dbs"].append(db)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="ignore the XML cache")
    args = ap.parse_args()
    if args.refresh and os.path.isdir(CACHE):
        for f in os.listdir(CACHE):
            os.remove(os.path.join(CACHE, f))

    os.makedirs(OUT, exist_ok=True)
    store, log = {}, []

    for slug, variants in PHRASES.items():
        if isinstance(variants, str):
            variants = [variants]
        for db in ("pubmed", "pmc"):
            parts = []
            for v in variants:
                parts.append(f'"{v}"[Title/Abstract]')
                if db == "pubmed":
                    parts.append(f'"{v}"[Other Term]')
            term = " OR ".join(parts)
            ids, total, harvested = collect_ids(db, term)
            print(f"{slug:6s} {db:7s} {total:6d} hits, {len(ids):6d} ids retrieved",
                  file=sys.stderr)
            if len(ids) < total:
                print(f"    WARNING: {total - len(ids)} records not retrieved "
                      f"(partition sum {harvested})", file=sys.stderr)
            recs = efetch(db, ids, parse_pubmed if db == "pubmed" else parse_pmc,
                          f"{slug}_{db}")
            for r in recs:
                merge(store, r, slug, db)
            log.append({"phrase": variants[0], "variants": variants, "slug": slug, "db": db, "term": term,
                        "hits": total, "ids": len(ids), "parsed": len(recs)})

    with open(os.path.join(OUT, "records.jsonl"), "w", encoding="utf8") as fh:
        for r in store.values():
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    json.dump(log, open(os.path.join(OUT, "search-log.json"), "w"), indent=1)

    print(f"\n{len(store)} unique records -> {OUT}/records.jsonl")
    for e in log:
        print(f"  {e['slug']:6s} {e['db']:7s} hits={e['hits']:6d} "
              f"ids={e['ids']:6d} parsed={e['parsed']:6d}")


if __name__ == "__main__":
    main()
