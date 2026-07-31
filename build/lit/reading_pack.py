#!/usr/bin/env python3
"""Assemble one reading pack per batch from the extracted paper text.

A pack is not a summary. Every character in it is verbatim source, so a quote
copied out of a pack passes verify_quotes.py against the paper it came from.
What the pack does is choose which parts of a paper the reader sees, and it
chooses the three places methodological open problems are actually stated:

  HEAD        title, abstract and the opening of the introduction, which is
              where a paper says what it set out to do;
  DISCUSSION  everything from the first discussion or limitations heading to
              the end of the body, which the reader prompt calls the richest
              source of open problems;
  SIGNAL      paragraphs anywhere else that concede a limit, name an
              assumption, or call for work that has not been done.

The rest of a methods paper is derivation and results tables. A reader who
needs them greps scratch/<batch>/<id>.txt, which holds the full text.

Usage:
  python3 build/lit/reading_pack.py core-04
  python3 build/lit/reading_pack.py core-04 core-05
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
READING = os.path.join(ROOT, "documentation", "audit", "reading")
SCRATCH = os.path.join(ROOT, "scratch")

HEAD_CHARS = 3600
DISC_CHARS = 8200
SIG_CHARS = 4600

# Where the body stops. Taken as the last match in the back half of the file so
# an in-text mention of "References" in the introduction cannot truncate a paper.
END = re.compile(r"\n\s*(?:##\s*)?(references?|bibliography|literature cited|"
                 r"works cited|reference list|r e f e r e n c e s)\s*\n", re.I)

# Publisher furniture that pdftotext interleaves with the prose on every page.
# Left in, it costs a reader several hundred characters per page and can land in
# the middle of a sentence they are about to quote.
NOISE = re.compile(
    r"^\s*(author manuscript|hhs public access|downloaded from https?://|"
    r"\d{6,}, \d{4}, \d+, downloaded from|see the terms and conditions|"
    r"wileyonlinelibrary\.com|available in pmc |published in final edited form|"
    r"licen[cs]e|this is an open access article|pmc-(?:status|prop|license)|"
    r"click here for additional data file|refer to web version on pubmed)",
    re.I)

DISC = re.compile(r"\n\s*(?:##\s*)?(?:\d+[.)]?\s*)?"
                  r"(discussion|limitations?|concluding remarks|conclusions?|"
                  r"discussion and conclusions?|summary and discussion|"
                  r"strengths and limitations)\b[^\n]{0,60}\n", re.I)

# A paragraph matching any of these is worth the reader's attention wherever it
# sits. The list is deliberately about concession and futurity, not about topic:
# a topic filter would only return what the search phrases already returned.
SIGNAL = re.compile(
    r"\b(future (?:research|work|studies|directions)|further (?:research|work|study)|"
    r"remains? (?:an )?(?:open|unclear|unknown|unresolved|to be)|"
    r"open (?:question|problem|challenge)|no (?:consensus|guidance|agreement|"
    r"established|standard|formal|general|accepted|method|approach|procedure|"
    r"software|estimator)|"
    r"is not (?:known|available|established|straightforward|possible|clear)|"
    r"cannot (?:be |currently )?(?:identif|estimat|distinguish|test|verif|estab)|"
    r"we (?:do not|did not|cannot|could not) (?:address|consider|examine|"
    r"account|evaluate|know|derive|provide)|"
    r"beyond the scope|out of scope|left for future|"
    r"an? (?:important|major|key|critical|outstanding) (?:limitation|challenge|"
    r"gap|question|issue)|"
    r"has (?:not|yet to) been (?:studied|developed|investigated|established|"
    r"addressed|examined|proposed|evaluated)|"
    r"little (?:is known|guidance|attention|work)|"
    r"lack (?:of )?(?:consensus|guidance|methods?|a )|"
    r"warrants? (?:further|additional)|merits? further|"
    r"untestable|unverifiable|cannot be verified|sensitive to (?:the )?"
    r"(?:choice|specification)|"
    r"require(?:s|d)? (?:strong|untestable|further) assumption)",
    re.I)


def paragraphs(text):
    """Rejoin pdftotext's hard-wrapped lines into paragraph-sized chunks."""
    out, buf = [], []
    for line in text.split("\n"):
        if line.strip():
            buf.append(line.rstrip())
        elif buf:
            out.append(" ".join(buf))
            buf = []
    if buf:
        out.append(" ".join(buf))
    return out


def body_of(text):
    text = "\n".join(l for l in text.split("\n") if not NOISE.match(l))
    half = len(text) // 2
    cuts = [m.start() for m in END.finditer(text) if m.start() > half]
    return text[:cuts[-1]] if cuts else text


def stop_at_refs(chunk):
    """A slice taken from a discussion heading runs into the reference list when
    the paper is short. Quoting from there would quote some other paper."""
    m = END.search(chunk)
    return chunk[:m.start()] if m else chunk


def build(paper, batch):
    path = os.path.join(SCRATCH, batch, paper["id"] + ".txt")
    if not os.path.exists(path):
        return f"### {paper['id']} UNREADABLE (no extracted text)\n"
    raw = open(path, encoding="utf8", errors="replace").read()
    body = body_of(raw)

    head = body[:HEAD_CHARS]

    m = DISC.search(body, HEAD_CHARS)
    disc = stop_at_refs(body[m.start():m.start() + DISC_CHARS] if m
                        else body[-DISC_CHARS:])
    disc_span = (m.start() if m else len(body) - DISC_CHARS,
                 (m.start() if m else len(body) - DISC_CHARS) + DISC_CHARS)

    seen, sig, used = set(), [], 0
    for para in paragraphs(body[HEAD_CHARS:disc_span[0]]):
        if used >= SIG_CHARS or len(para) < 120:
            continue
        if not SIGNAL.search(para):
            continue
        key = para[:80]
        if key in seen:
            continue
        seen.add(key)
        sig.append(para)
        used += len(para)

    parts = [f"### {paper['id']} | {paper.get('year')} | {paper.get('topic')} | "
             f"{paper.get('title')}",
             f"doi: {paper.get('doi') or '(none)'}  chars: {len(raw)}  "
             f"file: scratch/{batch}/{paper['id']}.txt",
             "\n--- HEAD ---\n" + head,
             "\n--- SIGNAL PARAGRAPHS ---\n" + ("\n\n".join(sig) or "(none matched)"),
             "\n--- DISCUSSION ONWARD ---\n" + disc]
    return "\n".join(parts) + "\n\n" + "=" * 78 + "\n\n"


def run(batch):
    blob = json.load(open(os.path.join(READING, f"batch_{batch}.json"),
                          encoding="utf8"))
    out = os.path.join(SCRATCH, "packs")
    os.makedirs(out, exist_ok=True)
    dest = os.path.join(out, f"{batch}.txt")
    with open(dest, "w", encoding="utf8") as fh:
        fh.write(f"# Reading pack {batch} | {len(blob['papers'])} papers\n"
                 f"# Verbatim source slices. Full text: scratch/{batch}/<id>.txt\n\n")
        for p in blob["papers"]:
            fh.write(build(p, batch))
    print(f"{dest}  {os.path.getsize(dest) // 1024} KB  "
          f"{len(blob['papers'])} papers")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for b in sys.argv[1:]:
        run(b)


if __name__ == "__main__":
    main()
