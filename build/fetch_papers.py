#!/usr/bin/env python3
"""Collect open-access copies of every work cited in the corpus, for local reference.

Resolution order per DOI:
  1. Unpaywall  -- the canonical index of legally free copies (publisher OA, PMC, repositories)
  2. Europe PMC -- open-access full text where a PMCID exists
  3. arXiv      -- for preprints

Paywalled works are recorded in the manifest as unavailable rather than worked around.
Output lands in documentation/refs/ , which is gitignored.
"""

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

EMAIL = "ahmad.pub@gmail.com"
UA = f"ITC-open-problems/1.0 (mailto:{EMAIL})"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "documentation")
OUT = os.path.join(DOCS, "refs")
MANIFEST = os.path.join(DOCS, "refs", "manifest.json")


def get(url, timeout=45, binary=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data if binary else data.decode("utf8", "ignore")


def slug(s, n=70):
    s = re.sub(r"[^A-Za-z0-9]+", "-", s).strip("-")
    return s[:n] or "untitled"


def scan_corpus():
    """Pull every DOI, arXiv id and PubMed id out of the source markdown."""
    dois, arxivs, pmids = set(), set(), set()
    for fn in os.listdir(DOCS):
        if not fn.endswith(".md"):
            continue
        text = open(os.path.join(DOCS, fn), encoding="utf8", errors="ignore").read()
        for m in re.findall(r"10\.\d{4,9}/[^\s)\"<>\]]+", text):
            dois.add(re.sub(r"[.,;]+$", "", m).split("](")[0])
        for m in re.findall(r"arxiv\.org/abs/([0-9]{4}\.[0-9]{4,5})", text, re.I):
            arxivs.add(m)
        for m in re.findall(r"pubmed\.ncbi\.nlm\.nih\.gov/(\d{7,9})", text):
            pmids.add(m)
    return sorted(dois), sorted(arxivs), sorted(pmids)


def crossref(doi):
    try:
        m = json.loads(get("https://api.crossref.org/works/" + urllib.parse.quote(doi, safe="")))["message"]
        return {
            "title": (m.get("title") or ["untitled"])[0],
            "year": (m.get("issued", {}).get("date-parts") or [[None]])[0][0],
            "author": (m.get("author") or [{}])[0].get("family", "anon"),
            "journal": (m.get("container-title") or [""])[0],
        }
    except Exception:
        return {"title": "untitled", "year": None, "author": "anon", "journal": ""}


def unpaywall(doi):
    """Return the best legally-free PDF url for a DOI, or None."""
    try:
        d = json.loads(get(f"https://api.unpaywall.org/v2/{urllib.parse.quote(doi, safe='')}?email={EMAIL}"))
    except Exception:
        return None, None
    if not d.get("is_oa"):
        return None, None
    best = d.get("best_oa_location") or {}
    cands = [best] + (d.get("oa_locations") or [])
    for loc in cands:
        if not loc:
            continue
        url = loc.get("url_for_pdf")
        if url:
            return url, loc.get("host_type")
    for loc in cands:
        if loc and loc.get("url"):
            return loc["url"], loc.get("host_type")
    return None, None


def europepmc_pdf(doi):
    """Europe PMC serves open-access full text for works with a PMCID."""
    try:
        q = urllib.parse.quote(f'DOI:"{doi}"')
        d = json.loads(get(f"https://www.ebi.ac.uk/europepmc/webservices/rest/search?query={q}&format=json"))
        hits = d.get("resultList", {}).get("result", [])
        if not hits:
            return None
        h = hits[0]
        if h.get("isOpenAccess") == "Y" and h.get("pmcid"):
            return f"https://www.ebi.ac.uk/europepmc/webservices/rest/{h['pmcid']}/fullTextPDF"
    except Exception:
        pass
    return None


def download(url, path):
    try:
        data = get(url, binary=True, timeout=90)
    except Exception as e:
        return False, str(e)[:70]
    if len(data) < 12000:
        return False, f"too small ({len(data)}B), probably a landing page"
    if not data[:5].startswith(b"%PDF"):
        return False, "not a PDF"
    with open(path, "wb") as f:
        f.write(data)
    return True, f"{len(data)//1024} KB"


def main():
    os.makedirs(OUT, exist_ok=True)
    dois, arxivs, pmids = scan_corpus()
    print(f"corpus: {len(dois)} DOIs, {len(arxivs)} arXiv, {len(pmids)} PubMed ids\n")

    manifest, got, missed = [], 0, 0

    for i, doi in enumerate(dois, 1):
        meta = crossref(doi)
        name = f"{meta['author']}_{meta['year']}_{slug(meta['title'], 55)}.pdf"
        path = os.path.join(OUT, name)
        rec = {"doi": doi, **meta, "file": None, "source": None, "note": None}

        if os.path.exists(path):
            rec.update(file=name, source="cached")
            print(f"[{i:2}/{len(dois)}] cached   {meta['author']} {meta['year']}")
            manifest.append(rec)
            got += 1
            continue

        url, host = unpaywall(doi)
        src = f"unpaywall:{host}" if url else None
        if not url:
            url = europepmc_pdf(doi)
            src = "europepmc" if url else None

        if url:
            ok, note = download(url, path)
            if ok:
                rec.update(file=name, source=src, note=note)
                got += 1
                print(f"[{i:2}/{len(dois)}] OK       {meta['author']} {meta['year']}  ({src}, {note})")
            else:
                rec.update(source=src, note=f"failed: {note}")
                missed += 1
                print(f"[{i:2}/{len(dois)}] fail     {meta['author']} {meta['year']}  ({note})")
        else:
            rec["note"] = "no open-access copy indexed (paywalled)"
            missed += 1
            print(f"[{i:2}/{len(dois)}] paywall  {meta['author']} {meta['year']}")

        manifest.append(rec)
        time.sleep(0.4)

    for aid in arxivs:
        name = f"arXiv_{aid}.pdf"
        path = os.path.join(OUT, name)
        rec = {"arxiv": aid, "file": None, "source": "arxiv", "note": None}
        if os.path.exists(path):
            rec["file"] = name
            got += 1
        else:
            ok, note = download(f"https://arxiv.org/pdf/{aid}", path)
            if ok:
                rec.update(file=name, note=note)
                got += 1
                print(f"[arXiv] OK  {aid} ({note})")
            else:
                rec["note"] = f"failed: {note}"
                missed += 1
                print(f"[arXiv] fail {aid} ({note})")
        manifest.append(rec)
        time.sleep(0.4)

    with open(MANIFEST, "w") as f:
        json.dump({"retrieved": got, "unavailable": missed, "items": manifest}, f, indent=1)

    print(f"\n{got} retrieved, {missed} unavailable -> {OUT}")
    print(f"manifest: {MANIFEST}")


if __name__ == "__main__":
    main()
