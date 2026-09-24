#!/usr/bin/env python3
"""Render a completed study's manuscript and register its downloads.

Renders studies/<slug>/manuscript/manuscript.qmd to Markdown, PDF and
OpenDocument, moves the outputs to studies/<slug>/out/<ID>.<ext>, checks that
they are real rather than merely present, and records their paths under
`downloads` in the study's study.json and in studies/index.json, which
build/render_site.mjs reads. Ported from the sibling ITC project, whose checks
are kept: a render can succeed and still leave "?@fig-x" in a PDF or literal
dollar signs in an ODT.

index.json is maintained by hand for studies that are not complete, so this
updates one entry's `downloads` and leaves every other field alone.

Usage:
  python3 build/studies/publish.py --study CNF-01
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUDIES = os.path.join(ROOT, "studies")
FORMATS = {"gfm": ".md", "pdf": ".pdf", "odt": ".odt"}


def find(study):
    for f in sorted(glob.glob(os.path.join(STUDIES, "*", "study.json"))):
        d = json.load(open(f, encoding="utf8"))
        slug = os.path.basename(os.path.dirname(f))
        if study in (slug, d.get("problem_id")):
            d["_dir"], d["_slug"], d["_file"] = os.path.dirname(f), slug, f
            return d
    sys.exit(f"no study.json matching {study!r}")


def render(d):
    src = os.path.join(d["_dir"], "manuscript", "manuscript.qmd")
    if not os.path.exists(src):
        return [f"no manuscript at {os.path.relpath(src, ROOT)}"]
    out = os.path.join(d["_dir"], "out")
    os.makedirs(out, exist_ok=True)
    problems = []
    for fmt, ext in FORMATS.items():
        p = subprocess.run(["quarto", "render", "manuscript.qmd", "--to", fmt],
                           cwd=os.path.dirname(src), capture_output=True, text=True)
        if p.returncode != 0:
            problems.append(f"{fmt} render failed: {(p.stderr or p.stdout).strip()[-400:]}")
            continue
        produced = os.path.join(os.path.dirname(src), "manuscript" + ext)
        if not os.path.exists(produced):
            problems.append(f"{fmt}: quarto reported success but wrote no {ext}")
            continue
        shutil.move(produced, os.path.join(out, d["problem_id"] + ext))
    return problems + verify(d, out)


def verify(d, out):
    bad = []
    md_path = os.path.join(out, d["problem_id"] + ".md")
    if os.path.exists(md_path):
        md = open(md_path, encoding="utf8").read()
        if "?@" in md:
            bad.append("markdown has unresolved cross-references (?@)")
        if len(md) < 2000:
            bad.append(f"markdown is only {len(md)} chars; render likely truncated")
        for img in re.findall(r"!\[[^\]]*\]\(([^)\s]+)", md):
            if not img.startswith(("http", "data:")) and \
                    not os.path.exists(os.path.join(out, img)):
                bad.append(f"markdown references missing image {img}")
    pdf = os.path.join(out, d["problem_id"] + ".pdf")
    if os.path.exists(pdf) and os.path.getsize(pdf) < 20000:
        bad.append(f"pdf is only {os.path.getsize(pdf)} bytes")
    # The default LaTeX font has no Greek, so a PDF can render with every α and
    # λ silently missing. Any non-ASCII character in the Markdown must survive.
    if os.path.exists(pdf) and os.path.exists(md_path):
        p = subprocess.run(["pdftotext", pdf, "-"], capture_output=True, text=True)
        if p.returncode == 0:
            md_chars = {c for c in open(md_path, encoding="utf8").read()
                        if ord(c) > 127 and not c.isspace()}
            lost = sorted(md_chars - set(p.stdout) - set("‘’“”…"))
            if lost:
                bad.append(f"pdf is missing characters: {''.join(lost)}")
    odt = os.path.join(out, d["problem_id"] + ".odt")
    if os.path.exists(odt):
        try:
            with zipfile.ZipFile(odt) as z:
                names = z.namelist()
                body = z.read("content.xml").decode("utf8", "ignore")
            if not any(n.startswith("Formula") for n in names) and "$" in body:
                bad.append("odt has literal $ and no formula objects")
        except zipfile.BadZipFile:
            bad.append("odt is not a valid zip")
    missing = [e for e in FORMATS.values()
               if not os.path.exists(os.path.join(out, d["problem_id"] + e))]
    if missing:
        bad.append(f"no output for {', '.join(missing)}")
    return bad


def register(d):
    have = {k: f"studies/{d['_slug']}/out/{d['problem_id']}{e}"
            for k, e in FORMATS.items()
            if os.path.exists(os.path.join(d["_dir"], "out", d["problem_id"] + e))}
    sj = json.load(open(d["_file"], encoding="utf8"))
    sj["downloads"] = have
    json.dump(sj, open(d["_file"], "w", encoding="utf8"), indent=1, ensure_ascii=False)
    idx_path = os.path.join(STUDIES, "index.json")
    idx = json.load(open(idx_path, encoding="utf8"))
    if d["problem_id"] in idx:
        idx[d["problem_id"]]["downloads"] = have
    json.dump(idx, open(idx_path, "w", encoding="utf8"), indent=1, ensure_ascii=False)
    open(idx_path, "a").write("\n")
    return have


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--study", required=True)
    d = find(ap.parse_args().study)
    problems = render(d)
    for p in problems:
        print(f"!! {p}")
    print(f"{d['problem_id']}: downloads {sorted(register(d))}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
