#!/usr/bin/env python3
"""Check that each extracted full text is the paper its library record claims.

`fetch.py` already scores title containment against the whole document. That check is
defeated by reference lists: an article that cites the wanted paper by its full title
scores 1.0 even when the retrieval resolved to the wrong publication entirely. Restricting
the same containment score to the head of the document removes that failure mode, because
a reference list never appears in the first few thousand characters.

Two failures are reported separately because they have different causes and different fixes.

  wrong-paper   the head of the extracted text does not carry the record's title. Retrieval
                resolved a DOI to a different publication. Nothing read from this file may
                be attributed to this record.

  shared-text   two records extract to byte-identical text. One DOI resolved to the other's
                deposit, which is what happens when a reply or a comment shares a repository
                copy with the article it replies to. The findings of the second record would
                silently duplicate the first.

Usage:
  python3 build/lit/check_fulltext_identity.py                 # every extracted text
  python3 build/lit/check_fulltext_identity.py --batch core-27
  python3 build/lit/check_fulltext_identity.py --threshold 0.6
"""

import argparse
import collections
import hashlib
import json
import os
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "documentation" / "refs" / "library.json"
SCRATCH = ROOT / "scratch"

HEAD_CHARS = 6000
DEFAULT_THRESHOLD = 0.55
MIN_TITLE_WORDS = 4

STOP = {
    "a", "an", "the", "of", "in", "on", "for", "to", "and", "with", "using",
    "from", "by", "at", "as", "is", "are", "that", "this",
}


def norm(text):
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", text.lower())


def title_words(title):
    return {w for w in norm(title or "").split() if len(w) > 3 and w not in STOP}


def load_library():
    data = json.loads(LIBRARY.read_text())
    records = data.get("papers", data) if isinstance(data, dict) else data
    if isinstance(records, dict):
        records = list(records.values())
    return {r["id"]: r for r in records if r.get("id")}


def extracted_texts(batch):
    pattern = f"{batch}/L*.txt" if batch else "*/L*.txt"
    for path in sorted(SCRATCH.glob(pattern)):
        yield path.stem, path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", help="restrict to one reading batch")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    ap.add_argument("--quiet", action="store_true", help="print only failures")
    args = ap.parse_args()

    library = load_library()
    scores = []
    skipped = []
    digests = collections.defaultdict(set)

    for paper_id, path in extracted_texts(args.batch):
        record = library.get(paper_id)
        if record is None:
            skipped.append((paper_id, "no library record"))
            continue
        raw = path.read_bytes()
        digests[hashlib.md5(raw).hexdigest()].add(paper_id)
        words = title_words(record.get("title"))
        if len(words) < MIN_TITLE_WORDS:
            skipped.append((paper_id, "title too short to score"))
            continue
        head = norm(raw[: HEAD_CHARS * 2].decode("utf-8", "replace")[:HEAD_CHARS])
        hits = sum(1 for w in words if w in head)
        scores.append((hits / len(words), paper_id, record, path))

    scores.sort()
    wrong = [s for s in scores if s[0] < args.threshold]
    shared = {d: ids for d, ids in digests.items() if len(ids) > 1}

    if not args.quiet:
        print(f"checked {len(scores)} extracted texts, skipped {len(skipped)}")
        if scores:
            worst = scores[: min(5, len(scores))]
            print("lowest head title containment:")
            for frac, paper_id, record, _ in worst:
                print(f"  {frac:.2f} {paper_id} {(record.get('title') or '')[:64]}")

    for frac, paper_id, record, path in wrong:
        print(
            f"wrong-paper {paper_id} score={frac:.2f} {path.parent.name} "
            f"doi={record.get('doi')} title={(record.get('title') or '')[:70]}"
        )
    for _, ids in sorted(shared.items()):
        print(f"shared-text {' '.join(sorted(ids))}")

    failures = len(wrong) + len(shared)
    print(f"{failures} identity failures ({len(wrong)} wrong-paper, {len(shared)} shared-text)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
