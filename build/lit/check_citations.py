#!/usr/bin/env python3
"""Check every citation in the registry against what its DOI actually points at.

In the sibling project a reader found an entry crediting one group for a paper
whose DOI resolves to an entirely different set of authors. Nothing in the
pipeline could have caught that: the readers report on whether a problem is
open, not on whether the registry cites correctly, and a plausible name attached
to a real DOI reads as sound to everyone downstream.

The failure mode is misattribution, not fabrication. The DOI resolves, the paper
exists, and the described work is real; only the names and the year are wrong.
So resolving the DOI is not enough. This compares the cited surname and year
against CrossRef's record and reports the disagreements.

Output: documentation/audit/registry/CITATIONS.md and citation-check.json

Usage:
  python3 build/lit/check_citations.py              # cached results reused
  python3 build/lit/check_citations.py --refresh    # re-query every DOI
"""

import argparse
import json
import os
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REGISTRY = os.path.join(ROOT, "documentation", "audit", "registry")
CACHE = os.path.join(REGISTRY, ".crossref-cache.json")
API = "https://api.crossref.org/works/"
MAILTO = "ahmad.pub@gmail.com"          # CrossRef asks for a contact; it raises rate limits
DOI_IN = re.compile(r"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+")
YEAR_IN = re.compile(r"\b(19|20)\d{2}\b")


def fold(s):
    """Strip accents, case and punctuation so spellings of one name compare equal.

    Umlauts get a second pass. A German name is romanized either by dropping the
    diaeresis or by spelling it out, so the registry's "Ruecker" and CrossRef's
    "Rücker" are the same person written two correct ways; collapsing ue to u on
    both sides is what stops that reading as a misattribution.
    """
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"[^a-z]", "", s.lower())
    for a, b in (("ue", "u"), ("oe", "o"), ("ae", "a"), ("ss", "s")):
        s = s.replace(a, b)
    return s


def load_cache():
    if os.path.exists(CACHE):
        return json.load(open(CACHE, encoding="utf8"))
    return {}


def crossref(doi, cache, refresh=False):
    if not refresh and doi in cache:
        return cache[doi]
    url = API + urllib.parse.quote(doi, safe="") + f"?mailto={MAILTO}"
    try:
        with urllib.request.urlopen(url, timeout=45) as r:
            m = json.load(r)["message"]
        # `issued` is the earliest date CrossRef holds, which for a journal that
        # posts online ahead of an issue is the online date. A citation gives the
        # issue year, and some journals run two years behind: three papers in
        # Statistical Methods in Medical Research are cited here correctly by
        # issue year and were all reported as wrong against `issued`. Compare
        # against the version of record where there is one.
        rec = {
            "ok": True,
            "title": (m.get("title") or [""])[0],
            "authors": [a.get("family", "") for a in m.get("author", []) if a.get("family")],
            "year": (m.get("issued", {}).get("date-parts") or [[None]])[0][0],
            "print_year": ((m.get("published-print", {}).get("date-parts")
                            or [[None]])[0][0]),
            "type": m.get("type"),
            "container": (m.get("container-title") or [""])[0],
        }
    except urllib.error.HTTPError as e:
        rec = {"ok": False, "error": f"HTTP {e.code}"}
    except Exception as e:  # noqa: BLE001
        rec = {"ok": False, "error": str(e)[:120]}
    cache[doi] = rec
    time.sleep(0.15)
    return rec


# Citations here read "Authors, Title, Journal Year", so the capitalised word
# next to the year is the journal, not a person. Authors only ever sit at the
# front, and only an opening run punctuated as a name list attributes the work to
# anyone: "Hernán, Sauer, Hernández-Díaz & Platt" and "Maringe et al." do, while
# "Observational Medical Outcomes Partnership" and "TARGET 2025 statement" do
# not. Requiring that punctuation is what keeps a title from being read as a
# misattribution.
NAME = r"[A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]{2,}"
OPENS_WITH_AUTHORS = re.compile(
    rf"^\s*({NAME})(?=\s*,\s*{NAME}|\s*&|\s+et\s+al\.?|\s+and\s+{NAME})")
AUTHOR_RUN = re.compile(rf"({NAME})(?=\s*(?:,|&|\s+and\s+|\s+et\s+al\.?))")


def cited_names(cite):
    """Surnames the citation attributes the work to, if it names anyone at all.

    Returns nothing for a title-only citation. A citation that names no one
    cannot misattribute, and treating its title words as authors is exactly how
    a correct entry gets reported as wrong.
    """
    cite = cite or ""
    if not OPENS_WITH_AUTHORS.match(cite):
        return []
    # Only the opening segment: past the first title-like phrase the capitalised
    # words are journal and title words again.
    head = re.split(r"\bet\s+al\.?|,\s*[A-Z][a-z]+\s+[a-z]", cite, maxsplit=1)[0]
    out, seen = [], set()
    for m in AUTHOR_RUN.finditer(head[:160]):
        w = m.group(1)
        if w.lower() in ("and", "the", "for", "van", "der", "with"):
            continue
        if w.lower() not in seen:
            seen.add(w.lower())
            out.append(w)
    return out or [OPENS_WITH_AUTHORS.match(cite).group(1)]


def names_agree(cited, actual):
    """True when any cited surname matches any real one, either containing it.

    Compound and particle surnames are written both ways in practice: a registry
    that says "Costa" and a record that says "da Costa" are the same person, and
    so are "Tchetgen" and "Tchetgen Tchetgen".
    """
    for c in (fold(x) for x in cited):
        for a in (fold(x) for x in actual):
            if c and a and (c in a or a in c):
                return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    args = ap.parse_args()

    problems = json.load(open(os.path.join(REGISTRY, "problems.json"), encoding="utf8"))
    cache = load_cache()

    rows, checked = [], 0
    for p in problems:
        for w in p.get("prior_work") or []:
            cite = w.get("cite") or ""
            src = w.get("doi_or_url") or ""
            hit = DOI_IN.search(src)
            if not hit:
                rows.append({"id": p["id"], "cite": cite, "doi": None,
                             "status": "no-doi", "detail": src[:90]})
                continue
            doi = hit.group(0).rstrip(".,;)")
            checked += 1
            rec = crossref(doi, cache, args.refresh)
            if not rec.get("ok"):
                rows.append({"id": p["id"], "cite": cite, "doi": doi,
                             "status": "unresolved", "detail": rec.get("error")})
                continue

            want = cited_names(cite)
            have = rec["authors"]
            problems_found = []
            if want and have and not names_agree(want, have):
                problems_found.append(
                    f"cites {', '.join(want)}; CrossRef says "
                    f"{', '.join(have[:4])}"
                    + (" et al." if len(have) > 4 else ""))
            ym = YEAR_IN.search(cite)
            # Either date is a defensible citation year, so a cite matching
            # either one is right. Only a year matching neither is a mistake.
            cand = {y for y in (rec.get("year"), rec.get("print_year")) if y}
            if ym and cand and all(abs(int(ym.group(0)) - int(y)) > 1 for y in cand):
                problems_found.append(
                    f"cites {ym.group(0)}; CrossRef says "
                    + " online, ".join(str(y) for y in sorted(cand)))

            rows.append({"id": p["id"], "cite": cite, "doi": doi,
                         "status": "mismatch" if problems_found else "ok",
                         "detail": "; ".join(problems_found),
                         "crossref_title": rec.get("title"),
                         "crossref_authors": rec.get("authors"),
                         "crossref_year": rec.get("print_year") or rec.get("year")})

    json.dump(cache, open(CACHE, "w", encoding="utf8"), indent=1, ensure_ascii=False)
    json.dump(rows, open(os.path.join(REGISTRY, "citation-check.json"), "w",
                         encoding="utf8"), indent=1, ensure_ascii=False)

    # One DOI cited with two different years across entries is wrong in at least
    # one place, and neither entry looks wrong on its own. The registry is the
    # only place the disagreement is visible.
    years = {}
    for r in rows:
        if r.get("doi"):
            ym = YEAR_IN.search(r["cite"] or "")
            if ym:
                years.setdefault(r["doi"], {}).setdefault(ym.group(0), []).append(r["id"])
    inconsistent = [
        {"doi": d, "years": {y: sorted(set(ids)) for y, ids in ys.items()},
         "crossref_year": next((r.get("crossref_year") for r in rows
                                if r.get("doi") == d), None)}
        for d, ys in years.items() if len(ys) > 1]

    bad = [r for r in rows if r["status"] == "mismatch"]
    gone = [r for r in rows if r["status"] == "unresolved"]
    nodoi = [r for r in rows if r["status"] == "no-doi"]

    lines = ["# Registry citation check", "",
             f"{len(rows)} citations across {len(problems)} problems; "
             f"{checked} carry a DOI and were checked against CrossRef. "
             f"{len(bad)} name an author or year that disagrees with the record "
             f"the DOI resolves to, {len(gone)} did not resolve, and {len(nodoi)} "
             f"cite something with no DOI and are unchecked here. A citation "
             f"that gives only a title is not checked for attribution, since it "
             f"attributes the work to no one.", "",
             "The fault this looks for is misattribution, not fabrication: the "
             "DOI resolves, the paper is real, and the work described is real, "
             "but the names on it are not the ones cited. Nothing downstream can "
             "see that, because a plausible name on a working DOI reads as "
             "sound.", ""]
    if bad:
        lines += ["## Attribution disagrees with CrossRef", "",
                  "| problem | cited as | actually | title |", "|---|---|---|---|"]
        for r in bad:
            lines.append(
                f"| {r['id']} | {r['cite'][:44]} | "
                f"{', '.join((r.get('crossref_authors') or [])[:3])}"
                f"{' et al.' if len(r.get('crossref_authors') or []) > 3 else ''} "
                f"{r.get('crossref_year')} | {(r.get('crossref_title') or '')[:56]} |")
    if inconsistent:
        lines += ["", "## One DOI, two different years", "",
                  f"{len(inconsistent)} works are cited with disagreeing years in "
                  f"different entries. Each entry reads as correct alone; only "
                  f"the registry as a whole shows the conflict. Where CrossRef "
                  f"gives a year it is the one to trust, though an epub-ahead-of-"
                  f"print date can make both defensible.", "",
                  "| doi | cited as | CrossRef | entries |", "|---|---|---|---|"]
        for c in inconsistent:
            for y, ids in sorted(c["years"].items()):
                lines.append(f"| {c['doi']} | {y} | {c['crossref_year']} | "
                             f"{', '.join(ids)} |")

    if gone:
        lines += ["", "## DOIs that did not resolve", "",
                  "| problem | cite | doi | error |", "|---|---|---|---|"]
        for r in gone:
            lines.append(f"| {r['id']} | {r['cite'][:40]} | {r['doi']} | "
                         f"{r['detail']} |")

    open(os.path.join(REGISTRY, "CITATIONS.md"), "w", encoding="utf8").write(
        "\n".join(lines) + "\n")

    print(f"{len(rows)} citations, {checked} with a DOI checked")
    print(f"  attribution mismatch  {len(bad)}")
    print(f"  unresolved DOI        {len(gone)}")
    print(f"  no DOI, unchecked     {len(nodoi)}")
    print(f"  one doi, two years    {len(inconsistent)}")
    for c in inconsistent:
        print(f"  ~~ {c['doi']}: "
              + "; ".join(f"{y} in {', '.join(i)}" for y, i in sorted(c["years"].items()))
              + f" (CrossRef {c['crossref_year']})")
    for r in bad:
        print(f"  !! {r['id']}: {r['detail']}")
    for r in gone:
        print(f"  ?? {r['id']}: {r['doi']} {r['detail']}")


if __name__ == "__main__":
    main()
