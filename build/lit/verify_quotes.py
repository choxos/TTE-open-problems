#!/usr/bin/env python3
"""Check that every quote in a findings file really appears in the paper.

The readers are told a finding without a verbatim quote will be discarded, and
they report having checked their own work. This checks it independently, because
a quote that drifted is a claim with no evidence behind it, and the drift is
invisible downstream: the second reviewer sees the quote, not the paper.

Matching is on collapsed text. PDF extraction inserts line breaks, ligatures and
hyphenation wherever the layout demanded them, so an exact substring test would
fail on quotes that are in fact verbatim. Letters and digits are kept, everything
else is dropped, on both sides.

Usage:
  python3 build/lit/verify_quotes.py                       # every findings file
  python3 build/lit/verify_quotes.py --batch cnma-02       # one batch
  python3 build/lit/verify_quotes.py --write-report        # + a markdown report
"""

import argparse
import glob
import json
import os
import re
import subprocess
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
READING = os.path.join(ROOT, "documentation", "audit", "reading")
CACHE = os.path.join(READING, ".text-cache")
MIN_LEN = 12          # shorter than this and a match means nothing
SHORTEN = 60          # if the whole quote misses, try this many leading chars
NEAR = 0.90           # ordered word coverage that still counts as the same sentence


ELISION = re.compile(r"\s*(?:\[\s*\.\.\.\s*\]|\[…\]|\.\.\.|…)\s*")

# Readers type math as ASCII: a PDF's "τ²" is quoted as "tau^2", "Δ_BC" as
# "Delta_BC". Spelling the symbol out on both sides makes the two comparable.
GREEK = {
    "α": "alpha", "β": "beta", "γ": "gamma", "δ": "delta", "ε": "epsilon",
    "ζ": "zeta", "η": "eta", "θ": "theta", "ϑ": "theta", "ι": "iota",
    "κ": "kappa", "λ": "lambda", "μ": "mu", "ν": "nu", "ξ": "xi",
    "π": "pi", "ρ": "rho", "σ": "sigma", "ς": "sigma", "τ": "tau",
    "υ": "upsilon", "φ": "phi", "ϕ": "phi", "χ": "chi", "ψ": "psi",
    "ω": "omega",
    "Γ": "gamma", "Δ": "delta", "Θ": "theta", "Λ": "lambda", "Ξ": "xi",
    "Π": "pi", "Σ": "sigma", "Φ": "phi", "Ψ": "psi", "Ω": "omega",
    # Typesetters reach for the maths glyphs, which are separate codepoints from
    # the Greek letters they look like: INCREMENT, N-ARY SUMMATION, N-ARY PRODUCT.
    "∆": "delta", "∑": "sigma", "∏": "pi", "µ": "mu",
}
GREEK_RE = re.compile("|".join(map(re.escape, GREEK)))


def norm(s):
    """Letters and digits only, lowercased, ligatures and Greek spelled out."""
    s = (s or "").replace("ﬁ", "fi").replace("ﬂ", "fl")
    s = GREEK_RE.sub(lambda m: GREEK[m.group()], s)
    s = unicodedata.normalize("NFKD", s)
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def tokens(s):
    """Words long enough to carry meaning, for the near-verbatim fallback."""
    s = (s or "").replace("ﬁ", "fi").replace("ﬂ", "fl")
    s = GREEK_RE.sub(lambda m: " " + GREEK[m.group()] + " ", s)
    s = unicodedata.normalize("NFKD", s).lower()
    return [t for t in re.findall(r"[a-z0-9]+", s) if len(t) >= 3]


def coverage(blob, toks):
    """Fraction of the quote's words found in `blob`, in order.

    Exact containment is the right test for a quote, but it fails on a quote
    that is verbatim apart from a symbol the reader had to type as a word, or a
    hyphen the extractor put somewhere else. This says how much of the quote is
    really there, so a near-miss can be told apart from an invention.
    """
    if not toks:
        return 0.0
    at, hit = 0, 0
    for t in toks:
        i = blob.find(t, at)
        if i >= 0:
            hit += 1
            at = i + len(t)
    return hit / len(toks)


def split_elisions(q):
    """A quote with `...` in it is two quotes with text cut out between them.

    Stripping punctuation would weld the halves into a string that appears
    nowhere, so an honest abridgement would read as a fabrication. Split on the
    elision and check the pieces in order instead.
    """
    return ELISION.split(q or "")


def spans(blob, parts):
    """True when every fragment occurs in `blob`, in order and without overlap."""
    at = 0
    for p in parts:
        i = blob.find(p, at)
        if i < 0:
            return False
        at = i + len(p)
    return True


def text_of(path, layout=False):
    """Extracted text for a PDF or XML, cached: pdftotext is slow and we reread.

    Two extractions per PDF. Reading order decides how a table comes out: the
    default flow reads a row's cells in a different order than `-layout`, so a
    quote lifted from a table matches one and not the other.
    """
    full = path if os.path.isabs(path) else os.path.join(ROOT, path)
    if not os.path.exists(full):
        return None
    tag = "_layout" if layout else ""
    key = os.path.join(CACHE, re.sub(r"[^A-Za-z0-9]+", "_", path)[-180:] + tag + ".txt")
    if os.path.exists(key) and os.path.getmtime(key) >= os.path.getmtime(full):
        return open(key, encoding="utf8", errors="replace").read()
    if full.lower().endswith(".pdf"):
        cmd = ["pdftotext", "-q"] + (["-layout"] if layout else []) + [full, "-"]
        r = subprocess.run(cmd, capture_output=True)
        txt = r.stdout.decode("utf8", "replace")
    elif layout:
        return None
    else:
        txt = open(full, encoding="utf8", errors="replace").read()
    os.makedirs(CACHE, exist_ok=True)
    open(key, "w", encoding="utf8").write(txt)
    return txt


# Directories that hold something belonging to a paper rather than the paper, so
# a reader pointed at one was expected to read the article above it too.
SUBDIR = ("appendices", "supplements", "supplement", "appendix",
          "media", "figures", "figs", "images", "anc")
READABLE = (".pdf", ".xml", ".tex")


def docs_under(rel, depth=1):
    """Every PDF/XML at or below a repo-relative directory, to `depth` levels."""
    d = os.path.join(ROOT, rel)
    if not os.path.isdir(d):
        return []
    found = []
    for f in sorted(os.listdir(d)):
        full = os.path.join(d, f)
        if os.path.isfile(full) and f.lower().endswith(READABLE):
            found.append(os.path.join(rel, f))
        elif os.path.isdir(full) and depth > 0 and f.lower() in SUBDIR:
            found += docs_under(os.path.join(rel, f), depth - 1)
    return found


def batch_paths(bid):
    """id -> every file a reader could legitimately have quoted for that paper.

    Not just the file the batch named. Where the catalog entry is an appendix,
    the reader was told to read the article it belongs to, so the parent folder
    counts; and a reader given the main article may quote its supplements. Both
    directions have to be in scope or a verbatim quote reads as fabricated.
    """
    bf = os.path.join(READING, f"batch_{bid}.json")
    if not os.path.exists(bf):
        return {}
    out = {}
    for p in json.load(open(bf, encoding="utf8"))["papers"]:
        files = [f for f in (p.get("pdf"), p.get("xml"), p.get("text")) if f]
        rel = p.get("dir") or ""
        roots, up = [rel], rel
        # Climb out of nesting like media/media/ until a real paper folder.
        for _ in range(3):
            if os.path.basename(up).lower() not in SUBDIR:
                break
            up = os.path.dirname(up)
            roots.append(up)
        for r in roots:
            for f in docs_under(r):
                if f not in files:
                    files.append(f)
        out[p["id"]] = files
    return out


def check_paper(paper, files):
    """Every quote on one paper, against every file that paper could come from."""
    blobs, word_blobs = [], []
    for f in files:
        for lay in (False, True):
            t = text_of(f, layout=lay)
            if t:
                blobs.append(norm(t))
                word_blobs.append(" " + " ".join(tokens(t)) + " ")
    quotes = []
    for g in paper.get("future_research") or []:
        quotes.append(("gap", g.get("quote"), g.get("gap")))
    for f in paper.get("problems") or []:
        quotes.append((f.get("problem_id") or "finding", f.get("quote"),
                       f.get("evidence")))
    for n in paper.get("new_problems") or []:
        quotes.append(("new", n.get("quote"), n.get("proposed_title")))

    res = []
    for where, q, ctx in quotes:
        parts = [p for p in (norm(x) for x in split_elisions(q)) if p]
        n = "".join(parts)
        if not n:
            res.append((where, "missing", q, ctx))
        elif len(n) < MIN_LEN:
            res.append((where, "too-short", q, ctx))
        elif not blobs:
            res.append((where, "no-text", q, ctx))
        elif any(spans(b, parts) for b in blobs):
            res.append((where, "ok", q, ctx))
        else:
            cov = max((coverage(b, tokens(q)) for b in word_blobs), default=0.0)
            if cov >= NEAR:
                res.append((where, "near", q, ctx))
            elif any(parts[0][:SHORTEN] in b for b in blobs):
                res.append((where, "partial", q, ctx))
            else:
                res.append((where, f"NOT-FOUND ({cov:.0%})", q, ctx))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", action="append", default=None)
    ap.add_argument("--write-report", action="store_true")
    args = ap.parse_args()

    wanted = set(args.batch or [])
    files = sorted(glob.glob(os.path.join(READING, "findings", "*.json")))
    if wanted:
        files = [f for f in files
                 if os.path.basename(f)[:-5] in wanted]

    rows, tally, per_paper = [], {}, {}
    for path in files:
        d = json.load(open(path, encoding="utf8"))
        bid = d.get("batch") or os.path.basename(path)[:-5]
        paths = batch_paths(bid)
        for p in d.get("papers", []):
            if not p.get("read", True):
                continue
            res = check_paper(p, paths.get(p["id"], []))
            good = sum(1 for r in res if r[1] in ("ok", "near"))
            per_paper[(bid, p["id"])] = (good, len(res), p.get("title") or "")
            for where, status, q, ctx in res:
                tally[status] = tally.get(status, 0) + 1
                if status not in ("ok", "near"):
                    rows.append((bid, p["id"], where, status, q, ctx))

    total = sum(tally.values())
    print(f"{total} quotes checked across {len(files)} batches")
    for k in sorted(tally, key=lambda k: -tally[k]):
        print(f"  {k:18s} {tally[k]:5d}  ({100*tally[k]/total:.1f}%)")

    bad = [r for r in rows if r[3].startswith("NOT-FOUND")]
    # A paper where nothing matches is an extraction or file-routing failure, not
    # a reader inventing forty quotes. Separate the two before reading the list.
    dead = sorted(k for k, (g, n, _) in per_paper.items() if n >= 3 and g == 0)
    if dead:
        print(f"\n{len(dead)} papers where no quote matched at all "
              f"(suspect the source file, not the reader):")
        for bid, pid in dead:
            print(f"  {bid} {pid}  {per_paper[(bid, pid)][2][:70]}")
    if bad:
        loose = [r for r in bad if (r[0], r[1]) not in set(dead)]
        print(f"\n{len(bad)} quotes not found, {len(loose)} of them in papers "
              f"whose other quotes did match:")
        for bid, pid, where, _, q, _ in loose[:40]:
            print(f"  {bid} {pid} {where}: {(q or '')[:110]!r}")
        if len(loose) > 40:
            print(f"  ... and {len(loose) - 40} more")

    if args.write_report:
        out = os.path.join(READING, "QUOTE-CHECK.md")
        lines = ["# Quote verification", "",
                 f"{total} quotes checked. `partial` means the opening "
                 f"{SHORTEN} characters matched but the full quote did not, "
                 "usually an elision or a run-on across a column break.", "",
                 "| status | n |", "|---|---:|"]
        for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
            lines.append(f"| {k} | {v} |")
        if rows:
            lines += ["", "## Quotes needing a look", "",
                      "| batch | paper | attached to | status | quote |",
                      "|---|---|---|---|---|"]
            for bid, pid, where, status, q, _ in rows:
                lines.append(f"| {bid} | {pid} | {where} | {status} | "
                             f"{(q or '').replace('|', '/')[:160]} |")
        open(out, "w", encoding="utf8").write("\n".join(lines) + "\n")
        print(f"\nreport -> {os.path.relpath(out, ROOT)}")


if __name__ == "__main__":
    main()
