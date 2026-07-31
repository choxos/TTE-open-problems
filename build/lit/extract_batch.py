#!/usr/bin/env python3
"""Extract every paper in a reading batch to plain text under scratch/<batch>/.

The reader prompt says to extract to a file and then read the file, never to
pipe an extraction into a reply. This does that step for a whole batch so the
reader starts from text and spends no turns on shell plumbing.

Preference order per paper is JATS XML, then PDF, then a bare text file. The XML
is preferred where both exist: it carries real section headings, which the pack
builder keys off, and pdftotext loses them on a two-column layout.

Usage:
  python3 build/lit/extract_batch.py core-04
  python3 build/lit/extract_batch.py core-04 core-05 core-06
  python3 build/lit/extract_batch.py --all-core
"""

import html
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
READING = os.path.join(ROOT, "documentation", "audit", "reading")
SCRATCH = os.path.join(ROOT, "scratch")

# Tags whose text is not part of the article: the reference list alone can be
# half the character count, and a reader quoting from it would be quoting some
# other paper.
DROP = ("ref-list", "back", "table-wrap", "fn-group", "front-stub",
        "journal-meta", "article-categories", "permissions", "history")


def xml_to_text(path):
    raw = open(path, encoding="utf8", errors="replace").read()
    for tag in DROP:
        raw = re.sub(rf"<{tag}\b.*?</{tag}>", "\n", raw, flags=re.S)
    raw = re.sub(r"<!--.*?-->", " ", raw, flags=re.S)
    # Keep the heading and paragraph structure the pack builder needs.
    raw = re.sub(r"<title>", "\n\n## ", raw)
    raw = re.sub(r"</title>", "\n", raw)
    raw = re.sub(r"</(p|sec|abstract|list-item|caption)>", "\n\n", raw)
    raw = re.sub(r"<[^>]+>", " ", raw)
    raw = html.unescape(raw)
    raw = re.sub(r"[ \t]+", " ", raw)
    raw = re.sub(r"\n{3,}", "\n\n", raw)
    return raw.strip()


def pdf_to_text(path, dest):
    subprocess.run(["pdftotext", "-q", path, dest], check=True)
    return open(dest, encoding="utf8", errors="replace").read()


def extract(paper, outdir):
    dest = os.path.join(outdir, paper["id"] + ".txt")
    if os.path.exists(dest) and os.path.getsize(dest) > 2000:
        return "cached", os.path.getsize(dest)
    for key in ("xml", "pdf", "text"):
        src = paper.get(key)
        if not src:
            continue
        src = os.path.join(ROOT, src)
        if not os.path.exists(src):
            continue
        try:
            if key == "xml":
                body = xml_to_text(src)
                if len(body) < 3000:      # a metadata-only stub, not a full text
                    continue
                open(dest, "w", encoding="utf8").write(body)
            elif key == "pdf":
                body = pdf_to_text(src, dest)
            else:
                body = open(src, encoding="utf8", errors="replace").read()
                open(dest, "w", encoding="utf8").write(body)
        except Exception as exc:                                   # noqa: BLE001
            print(f"  {paper['id']} {key} failed: {exc}", file=sys.stderr)
            continue
        if len(body) > 1500:
            return key, len(body)
    return "FAILED", 0


def run(batch):
    path = os.path.join(READING, f"batch_{batch}.json")
    blob = json.load(open(path, encoding="utf8"))
    outdir = os.path.join(SCRATCH, batch)
    os.makedirs(outdir, exist_ok=True)
    bad = []
    for p in blob["papers"]:
        how, n = extract(p, outdir)
        if how == "FAILED":
            bad.append(p["id"])
        print(f"{batch} {p['id']:6s} {how:7s} {n:8d}")
    if bad:
        print(f"{batch}: UNREADABLE {', '.join(bad)}")
    return bad


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "--all-core":
        args = sorted(b[6:-5] for b in os.listdir(READING)
                      if b.startswith("batch_core-"))
    bad = []
    for b in args:
        bad += run(b)
    print(f"done; {len(bad)} unreadable")


if __name__ == "__main__":
    main()
