#!/usr/bin/env python3
"""Recover the publication year for library entries that have none.

The catalog reads a year out of PubMed or Crossref metadata. The hand-collected
entries have neither: they are PDFs and arXiv source bundles dropped in a folder,
and for 30 of them the year came out empty and the title came out as whatever
the first line of the PDF happened to be, usually an author list or an
affiliation footnote.

That did not matter while findings were only ever pooled. It matters now that
they are read in publication order, because an undated finding cannot take part
in a chronology at all, and the entries affected are not marginal: they are the
population-adjustment papers the registry is mostly about. 172 findings were
sitting outside the timeline for want of a four-digit number.

The year is almost always recoverable from the filename, which is how these were
saved:

  Remiro-Azócar_2021_Methods-for-population-adjustment...pdf   Zotero export
  arXiv_2602.17041.pdf, arXiv-2606.20341v1/                    arXiv id: 26 06
  10.1186/s13643-025-02804-4                                   Crossref

and where none of those applies, from the copyright or received line in the
paper's own text. Whatever is used is recorded in `year_source` so a wrong year
can be traced to the rule that produced it rather than looking authoritative.

The same pass reports entries that share an arXiv id, which is how one paper
gets read twice: the source bundle and the compiled PDF are different files in
different folders with no DOI between them, so nothing else in the pipeline can
see they are the same work.

Usage:
  python3 build/lit/fix_years.py            # report only
  python3 build/lit/fix_years.py --write    # patch library.json
"""

import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_citations import crossref, load_cache, CACHE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REFS = os.path.join(ROOT, "documentation", "refs")
LIB = os.path.join(REFS, "library.json")

NOW = 2027                      # nothing in this corpus can be later
ZOTERO = re.compile(r"_((?:19|20)\d{2})_")
ARXIV = re.compile(r"arxiv[-_](\d{2})(\d{2})\.(\d{4,5})", re.I)
# A dated line the publisher put there, as opposed to any four digits on the
# page: a reference list is full of years that have nothing to do with this
# paper, and the first one to match would win.
DATED = re.compile(
    r"(?:©|\(c\)\s|copyright|published\s+online|first\s+published|received|"
    r"accepted|submitted)([^\n]{0,80})", re.I)
YEAR = re.compile(r"(?:19|20)\d{2}")


def from_name(path):
    m = ZOTERO.search(os.path.basename(path or ""))
    return (int(m.group(1)), "filename") if m else (None, None)


def from_arxiv(entry):
    """arXiv ids are YYMM.NNNNN, so the id itself carries the year."""
    for s in (entry.get("pdf") or "", entry.get("text") or "", entry.get("path") or ""):
        m = ARXIV.search(s)
        if m:
            return 2000 + int(m.group(1)), "arxiv-id"
    return None, None


def arxiv_id(entry):
    for s in (entry.get("pdf") or "", entry.get("text") or "", entry.get("path") or ""):
        m = ARXIV.search(s)
        if m:
            return f"{m.group(1)}{m.group(2)}.{m.group(3)}"
    return None


def from_doi(entry, cache):
    doi = (entry.get("doi") or "").strip()
    if not doi:
        return None, None
    rec = crossref(doi, cache)
    if rec.get("ok") and rec.get("year"):
        return int(rec["year"]), "crossref"
    return None, None


def from_text(entry):
    path = entry.get("pdf") or entry.get("text") or entry.get("xml")
    if not path:
        return None, None
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return None, None
    try:
        if full.endswith(".pdf"):
            # Six pages, not two: a journal article states its year on page one,
            # but a book puts it on a copyright page behind the half-title,
            # series page and title page.
            txt = subprocess.run(["pdftotext", "-l", "6", full, "-"],
                                 capture_output=True, text=True, timeout=60).stdout
        else:
            txt = open(full, encoding="utf8", errors="replace").read(20000)
    except Exception:  # noqa: BLE001
        return None, None
    # Every year on the line, not the first: a second edition's copyright reads
    # "© Springer Nature Switzerland AG 2009, 2021", and the first number there
    # is the edition this book replaced.
    hits = [int(y) for m in DATED.finditer(txt[:20000])
            for y in YEAR.findall(m.group(1))]
    hits = [h for h in hits if 1980 <= h <= NOW]
    # The latest such line is the publication event; an earlier one is usually a
    # journal's own founding date or a superseded edition.
    return (max(hits), "text") if hits else (None, None)


def reader_titles():
    """Titles the paper-readers transcribed, keyed by library id.

    An entry whose year is missing almost always has a broken title too: both
    come from the same failed metadata pass, so the title is whatever the first
    line of the PDF was, usually an author list or an affiliation footnote. The
    reader read the whole paper and wrote down its actual title, which is a
    better source than anything that can be parsed out of a filename, and unlike
    a filename it is not truncated.
    """
    import glob
    out = {}
    for f in glob.glob(os.path.join(ROOT, "documentation", "audit", "reading",
                                    "findings", "*.json")):
        for p in json.load(open(f, encoding="utf8")).get("papers", []):
            t = (p.get("title") or "").strip()
            if t and p.get("read"):
                out[p["id"]] = t
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    lib = json.load(open(LIB, encoding="utf8"))
    cache = load_cache()
    titles = reader_titles()

    fixed, unresolved = [], []
    for e in lib:
        if str(e.get("year") or "").isdigit():
            continue
        for fn in (from_arxiv, lambda x: from_name(x.get("pdf") or x.get("text") or ""),
                   lambda x: from_doi(x, cache), from_text):
            y, how = fn(e)
            if y and 1980 <= y <= NOW:
                e["year"] = str(y)
                e["year_source"] = how
                if titles.get(e["id"]):
                    e["title"] = titles[e["id"]]
                    e["title_source"] = "reader"
                fixed.append((e["id"], y, how,
                              (titles.get(e["id"]) or e.get("title") or "")))
                break
        else:
            unresolved.append(e)

    # Two entries for one arXiv id is one paper read twice: the source bundle and
    # the compiled PDF sit in different folders and neither carries a DOI, so no
    # other check in the pipeline can match them.
    byax = {}
    for e in lib:
        a = arxiv_id(e)
        if a:
            byax.setdefault(a, []).append(e)
    dupes = {a: v for a, v in byax.items() if len(v) > 1}

    if args.write:
        json.dump(cache, open(CACHE, "w", encoding="utf8"), indent=1, ensure_ascii=False)
        json.dump(lib, open(LIB, "w", encoding="utf8"), indent=1, ensure_ascii=False)

    print(f"{len(fixed)} years recovered, {len(unresolved)} still unresolved"
          + ("" if args.write else "  (report only; pass --write to apply)"))
    for i, y, how, f in fixed:
        print(f"  {i}  {y}  via {how:9s} {f[:62]}")
    for e in unresolved:
        print(f"  ?? {e['id']}  {(e.get('title') or '')[:60]}  "
              f"{os.path.basename(e.get('pdf') or e.get('text') or '(no file)')}")
    if dupes:
        print(f"\n{len(dupes)} arXiv ids appear on more than one entry:")
        for a, v in dupes.items():
            print(f"  arXiv:{a}")
            for e in v:
                print(f"    {e['id']}  {os.path.basename(e.get('pdf') or e.get('text') or '')}")


if __name__ == "__main__":
    main()
