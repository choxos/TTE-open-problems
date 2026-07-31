#!/usr/bin/env python3
"""Stage 5: write the human-readable index of what the search collected.

Reads the harvest log, the hand-screening decisions, the download manifest and
the code manifest, and writes INDEX.md next to them. Nothing is inferred here
that is not already recorded in those files.

Usage: python3 build/lit/index.py
"""

import json
import os
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")

TOPIC_ORDER = ["CCW", "EMUL", "GFORM", "MSM", "ITB", "TTE", "TEMU", "TT"]
TOPIC_PHRASE = {
    "CCW": "clone censor weight",
    "EMUL": "emulated trial",
    "GFORM": "parametric g-formula",
    "MSM": "marginal structural model",
    "ITB": "immortal time bias",
    "TTE": "target trial emulation",
    "TEMU": "trial emulation",
    "TT": "target trial",
}


def load(name, default):
    path = os.path.join(OUT, name)
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf8") as fh:
        return json.load(fh)


def main():
    log = load("search-log.json", [])
    hits = defaultdict(dict)
    for e in log:
        hits[e["phrase"]][e["db"]] = e["hits"]
    manifest = load("manifest.json", [])
    code = {c["dir"]: c["links"] for c in load("code-manifest.json", [])}

    screened = [json.loads(l) for l in
                open(os.path.join(OUT, "screened.jsonl"), encoding="utf8")]
    included = [r for r in screened if r["screen"]["decision"] == "include"]
    decisions = Counter(r["screen"]["decision"] for r in screened)

    by_dir = {m["dir"]: m for m in manifest if m.get("dir")}
    by_topic = defaultdict(list)
    for m in manifest:
        by_topic[m.get("topic") or "TT"].append(m)

    lines = []
    w = lines.append
    w("# Target trial emulation methodology reference collection")
    w("")
    w("Everything below came out of a PubMed and PMC search on the eight phrases, "
      "hand-screened title by title, with the open-access full text, supplements "
      "and linked code fetched for the records that were kept.")
    w("")
    w("## The search")
    w("")
    w("| phrase | PubMed | PMC |")
    w("|---|---:|---:|")
    for t in TOPIC_ORDER:
        phrase = TOPIC_PHRASE[t]
        h = hits.get(phrase, {})
        w(f"| {phrase} | {h.get('pubmed', '-')} | {h.get('pmc', '-')} |")
    w("")
    w(f"After deduplication on PMID, DOI, PMCID and title: "
      f"**{len(screened)} unique records**.")
    w("")
    w("## Screening")
    w("")
    w("Every record was read by hand, in batches of 200, ordered by phrase set "
      "then journal then year. A record was kept when it was methodological in "
      "at least some part: development or extension of a target trial emulation "
      "design, g-methods for sustained treatment strategies, simulation studies, "
      "method comparisons, emulation-versus-trial benchmarking studies, "
      "methodological or meta-research reviews of emulations, software, tutorials "
      "and worked protocols, reporting guidelines and regulatory guidance, "
      "data-source and linkage evaluations, and methodological critiques of "
      "published emulations. Purely clinical emulations that apply an existing "
      "design to answer a substantive question, regulatory submissions, protocols "
      "for a single applied study, and generic correspondence were dropped.")
    w("")
    for k in ("include", "exclude"):
        w(f"- {k}: {decisions.get(k, 0)}")
    w("")
    w("## What was downloaded")
    w("")
    w("| set | kept | with PDF | with XML | with supplements | with code or data |")
    w("|---|---:|---:|---:|---:|---:|")
    for t in TOPIC_ORDER:
        recs = by_topic.get(t, [])
        if not recs:
            continue
        pdf = sum(1 for m in recs if (m.get("files") or {}).get("pdf"))
        xml = sum(1 for m in recs if (m.get("files") or {}).get("xml"))
        sup = sum(1 for m in recs if (m.get("files") or {}).get("supplements"))
        cod = sum(1 for m in recs if code.get(m.get("dir")))
        w(f"| {t} | {len(recs)} | {pdf} | {xml} | {sup} | {cod} |")
    total = manifest
    w(f"| **all** | **{len(total)}** | "
      f"**{sum(1 for m in total if (m.get('files') or {}).get('pdf'))}** | "
      f"**{sum(1 for m in total if (m.get('files') or {}).get('xml'))}** | "
      f"**{sum(1 for m in total if (m.get('files') or {}).get('supplements'))}** | "
      f"**{sum(1 for m in total if code.get(m.get('dir')))}** |")
    w("")
    checked = [m for m in manifest if m.get("title_match") is not None]
    bad = [m for m in checked if m["title_match"] < 0.5]
    w("### Is it the right article?")
    w("")
    w("Every download was checked against its own contents: the title recorded "
      "inside the fetched JATS, or failing that the text of the PDF's first two "
      "pages, compared with the title in the citation record. Scoring is by "
      "containment of content words rather than Jaccard, because publishers "
      "routinely deposit a shortened title; what the check has to decide is "
      "whether the document is the same work at all. This matters because a "
      "drifted identifier does not fail, it returns a real paper for the wrong "
      "record, and nothing weaker notices.")
    w("")
    w(f"- checked against the fetched document: {len(checked)}")
    w(f"- every title word accounted for: "
      f"{sum(1 for m in checked if m['title_match'] == 1.0)}")
    demoted = [m for m in manifest
               if "supplementary matter" in (m.get("note") or "")]
    w(f"- below 0.5, discarded and flagged in `manifest.json`: {len(bad)}")
    if demoted:
        w(f"- PDFs that turned out to be the appendix rather than the paper, "
          f"moved into `supplements/`: {len(demoted)}. Some journals deposit the "
          f"supplement and not the article, and the supplement repeats the "
          f"title, so only its opening words give it away.")
    for m in bad:
        w(f"  - {m.get('pmid')} {m.get('pmcid')} — {(m.get('title') or '')[:80]}")
    w("")
    unavailable = [m for m in manifest if m.get("source") in ("unavailable", "error")]
    w(f"{len(unavailable)} of the kept records have no open-access copy anywhere "
      f"the pipeline could reach; they are listed in `manifest.json` with "
      f"`source: unavailable` and were not worked around.")
    w("")

    hosts = Counter(l["host"] for links in code.values() for l in links)
    if hosts:
        w("## Code and data repositories")
        w("")
        w("| host | links found |")
        w("|---|---:|")
        for h, n in hosts.most_common():
            w(f"| {h} | {n} |")
        w("")

    w("## The collection")
    w("")
    for t in TOPIC_ORDER:
        recs = sorted(by_topic.get(t, []),
                      key=lambda m: (-int(m.get("year") or 0),
                                     (m.get("title") or "").lower()))
        if not recs:
            continue
        w(f"### {t} — {TOPIC_PHRASE[t]} ({len(recs)})")
        w("")
        w("| year | article | journal | files |")
        w("|---|---|---|---|")
        for m in recs:
            f = m.get("files") or {}
            got = []
            if f.get("pdf"):
                got.append("pdf")
            if f.get("xml"):
                got.append("xml")
            if f.get("supplements"):
                got.append(f"{len(f['supplements'])} supp")
            links = code.get(m.get("dir")) or []
            ok = [l for l in links if l.get("status") == "ok"]
            if ok:
                got.append(f"{len(ok)} repo")
            if (m.get("title_match") or 1) < 0.5:
                got.append("**title mismatch**")
            title = (m.get("title") or "").replace("|", "/")[:150]
            d = m.get("dir")
            cell = f"[{title}]({os.path.relpath(d, OUT)})" if d else title
            w(f"| {m.get('year') or '?'} | {cell} | "
              f"{(m.get('journal') or '')[:44].replace('|', '/')} | "
              f"{', '.join(got) or '-'} |")
        w("")

    path = os.path.join(OUT, "INDEX.md")
    with open(path, "w", encoding="utf8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"wrote {os.path.relpath(path, ROOT)} "
          f"({len(included)} kept, {len(manifest)} with a download record)")


if __name__ == "__main__":
    main()
