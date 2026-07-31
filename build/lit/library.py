#!/usr/bin/env python3
"""Consolidate the hand-collected refs and the systematic harvest into one catalog.

Two collections grew side by side: documentation/refs/<TOPIC>/, assembled by hand
over time, and documentation/refs/systematic/, produced by the PubMed and PMC
search. They overlap, they use different layouts, and neither alone is the
reading list. This builds a single catalog over both, deduplicated on DOI and
then on title, so every paper is read once and referred to by one id.

Files are left where they are. Moving 4 GB across two layouts buys nothing that
a catalog does not, and it would break the provenance the systematic tree
records. What the catalog adds is a stable id, a single path, and one place that
knows which papers exist.

Output: documentation/refs/library.json and LIBRARY.md

Usage: python3 build/lit/library.py
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REFS = os.path.join(ROOT, "documentation", "refs")
SYS = os.path.join(REFS, "systematic")
MANUAL_TOPICS = ["General", "IPD-MA", "MAIC", "ML-NMR", "ML-UMR", "NMA",
                 "NMI", "QBA", "STC", "cNMA"]

DOI_RE = re.compile(r"\b10\.\d{4,9}/[-._;()/:A-Za-z0-9]+\b")
JUNK_TAIL = re.compile(r"[.,;:)\]]+$")


def norm_title(s):
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())[:90]


def norm_doi(s):
    return JUNK_TAIL.sub("", (s or "").strip().lower())


def pdf_head(path, pages=1):
    try:
        out = subprocess.run(["pdftotext", "-f", "1", "-l", str(pages), path, "-"],
                             capture_output=True, timeout=60).stdout
        return out.decode("utf8", "ignore")
    except Exception:  # noqa: BLE001
        return ""


def guess_title(text, fallback):
    """First plausible title line of a PDF: the longest early line that is prose."""
    best = ""
    for line in text.split("\n")[:40]:
        s = " ".join(line.split())
        if len(s) < 20 or len(s) > 240:
            continue
        if s.lower().startswith(("downloaded", "http", "doi:", "www.", "see discussions")):
            continue
        letters = sum(c.isalpha() for c in s)
        if letters < 0.6 * len(s):
            continue
        if len(s) > len(best):
            best = s
        if len(best) > 60:
            break
    return best or fallback


def systematic_entries():
    path = os.path.join(SYS, "manifest.json")
    if not os.path.exists(path):
        sys.exit("no systematic manifest; run build/lit/fetch.py first")
    out = []
    for m in json.load(open(path, encoding="utf8")):
        if not m.get("dir"):
            continue
        f = m.get("files") or {}
        out.append({
            "source": "systematic",
            "topic": m.get("topic"),
            "path": m["dir"],
            "pmid": m.get("pmid") or "",
            "pmcid": m.get("pmcid") or "",
            "doi": norm_doi(m.get("doi")),
            "title": m.get("title") or "",
            "journal": m.get("journal") or "",
            "year": m.get("year") or "",
            "authors": m.get("authors") or [],
            "pdf": f.get("pdf"),
            "xml": f.get("xml"),
            "supplements": len(f.get("supplements") or []),
            "title_match": m.get("title_match"),
        })
    return out


def manual_entries():
    out = []
    roots = [(t, os.path.join(REFS, t)) for t in MANUAL_TOPICS]
    roots.append(("General", REFS))  # loose PDFs sitting at the top level
    for topic, base in roots:
        if not os.path.isdir(base):
            continue
        for item in sorted(os.listdir(base)):
            p = os.path.join(base, item)
            if item.startswith(".") or item == "systematic" or item in MANUAL_TOPICS:
                continue
            if os.path.isdir(p):
                pdfs, tex, others = [], [], []
                for r, _, files in os.walk(p):
                    asset = is_asset_dir(os.path.relpath(r, p))
                    for f in files:
                        if f.startswith("."):
                            continue
                        full = os.path.join(r, f)
                        low = f.lower()
                        if low.endswith(".pdf") and not asset:
                            pdfs.append(full)
                        elif low.endswith(".tex") and not asset:
                            tex.append(full)
                        else:
                            others.append(full)
                if pdfs:
                    main = max(pdfs, key=os.path.getsize)
                    out.append(entry_for_pdf(main, topic, item,
                                             len(pdfs) - 1 + len(tex) + len(others)))
                elif tex:
                    # An arXiv source drop: the manuscript is LaTeX and the only
                    # PDFs are figures and tables. Taking the largest PDF here
                    # would file a table asset as the paper.
                    main = max(tex, key=os.path.getsize)
                    out.append(entry_for_tex(main, topic, item,
                                             len(tex) - 1 + len(others)))
                elif others:
                    # A code drop or data folder rather than a paper. Recorded so
                    # nothing silently vanishes, but it is not sent out to read.
                    out.append({"source": "manual", "topic": topic,
                                "path": os.path.relpath(p, ROOT), "kind": "materials",
                                "title": item, "files": len(others),
                                "doi": "", "pdf": None})
            elif item.lower().endswith(".pdf"):
                out.append(entry_for_pdf(p, topic, os.path.splitext(item)[0], 0))
    return out


ASSET_DIRS = {"media", "figures", "figure", "figs", "fig", "images", "img",
              "anc", "graphics", "plots", "tables"}
TEX_TITLE = re.compile(r"\\title\s*(?:\[[^\]]*\])?\s*\{", re.S)


def is_asset_dir(rel):
    """True for a subpath that holds figures rather than the manuscript."""
    return any(part.lower() in ASSET_DIRS
               for part in rel.split(os.sep) if part not in (".", ""))


def tex_title(text):
    """The braced argument of \\title, with the brace nesting respected."""
    m = TEX_TITLE.search(text)
    if not m:
        return ""
    depth, out = 1, []
    for ch in text[m.end():m.end() + 4000]:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
    s = re.sub(r"\\[a-zA-Z]+\s*", " ", "".join(out))
    return " ".join(s.replace("{", " ").replace("}", " ").split())[:240]


def entry_for_tex(path, topic, label, extras):
    """A LaTeX manuscript. The .tex is the full text a reader should be given."""
    text = open(path, encoding="utf8", errors="replace").read()
    hit = DOI_RE.search(text[:20000])
    ym = re.search(r"\b(19|20)\d{2}\b", label)
    return {
        "source": "manual",
        "topic": topic,
        "kind": "paper",
        "path": os.path.relpath(os.path.dirname(path), ROOT),
        "pdf": None,
        "text": os.path.relpath(path, ROOT),
        "doi": norm_doi(hit.group(0)) if hit else "",
        "title": tex_title(text) or label,
        "label": label,
        "year": ym.group(0) if ym else "",
        "extras": extras,
    }


def entry_for_pdf(path, topic, label, extras):
    text = pdf_head(path, 2)
    doi = ""
    hit = DOI_RE.search(text)
    if hit:
        doi = norm_doi(hit.group(0))
    year = ""
    ym = re.search(r"\b(19|20)\d{2}\b", label)
    if ym:
        year = ym.group(0)
    return {
        "source": "manual",
        "topic": topic,
        "kind": "paper",
        "path": os.path.relpath(os.path.dirname(path), ROOT),
        "pdf": os.path.relpath(path, ROOT),
        "doi": doi,
        "title": guess_title(text, label),
        "label": label,
        "year": year,
        "extras": extras,
    }


def content_hash(it):
    """Digest of the entry's PDF, for the copies DOI and title matching miss.

    A hand-filed copy often carries a publisher filename with no extractable DOI
    and a title guess that does not match the PubMed record, so the same file
    lands twice. The bytes settle it.
    """
    p = it.get("pdf")
    if not p:
        return None
    if os.sep not in p:
        p = os.path.join(it["path"], p)
    full = os.path.join(ROOT, p) if not os.path.isabs(p) else p
    if not os.path.exists(full):
        return None
    import hashlib
    with open(full, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def main():
    items = systematic_entries() + manual_entries()
    by_doi, by_title, by_hash, catalog = {}, {}, {}, []
    dupes = 0
    for it in items:
        d, t = it.get("doi"), norm_title(it.get("title"))
        h = content_hash(it)
        prior = ((by_doi.get(d) if d else None) or (by_title.get(t) if t else None)
                 or (by_hash.get(h) if h else None))
        if prior is not None:
            # The systematic record wins: it carries real PubMed metadata. The
            # hand-collected copy is kept as an alternate path, not a new entry.
            prior.setdefault("also_at", []).append(it.get("pdf") or it["path"])
            dupes += 1
            continue
        it["id"] = f"L{len(catalog) + 1:04d}"
        catalog.append(it)
        if d:
            by_doi[d] = it
        if t:
            by_title[t] = it
        if h:
            by_hash[h] = it

    readable = [c for c in catalog if c.get("pdf") or c.get("xml")]
    json.dump(catalog, open(os.path.join(REFS, "library.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)

    lines = ["# Consolidated reference library", "",
             f"{len(catalog)} distinct works, {len(readable)} with a readable full text. "
             f"{dupes} duplicates folded into the entry that already covered them.", "",
             "| id | source | topic | year | title | files |", "|---|---|---|---|---|---|"]
    for c in sorted(catalog, key=lambda c: (c["source"], c.get("topic") or "",
                                            -(int(c.get("year") or 0)))):
        got = [k for k in ("pdf", "xml") if c.get(k)]
        if c.get("supplements"):
            got.append(f"{c['supplements']} supp")
        if c.get("kind") == "materials":
            got.append(f"{c.get('files')} files, no paper")
        lines.append(f"| {c['id']} | {c['source']} | {c.get('topic') or ''} | "
                     f"{c.get('year') or ''} | {(c.get('title') or '')[:110].replace('|', '/')} "
                     f"| {', '.join(got) or '-'} |")
    open(os.path.join(REFS, "LIBRARY.md"), "w", encoding="utf8").write("\n".join(lines) + "\n")

    print(f"{len(catalog)} works catalogued ({dupes} duplicates merged)")
    print(f"  readable full text: {len(readable)}")
    for s in ("systematic", "manual"):
        n = sum(1 for c in catalog if c["source"] == s)
        r = sum(1 for c in catalog if c["source"] == s and (c.get("pdf") or c.get("xml")))
        print(f"  {s:11s} {n:4d} entries, {r:4d} readable")


if __name__ == "__main__":
    main()
