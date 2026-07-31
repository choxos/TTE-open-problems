#!/usr/bin/env python3
"""Stage 3: download the open-access full text and supplements for included records.

Resolution order per article:
  1. Europe PMC   -- JATS full text, the rendered PDF, and the supplements zip.
     Preferred because it fetches only what is wanted; the NCBI package bundles
     every figure bitmap as well, which for one test article meant 76 MB to
     obtain a 200 KB paper.
  2. PMC Open Access package (tar.gz) -- fallback when Europe PMC has no full
     text. Note the packages now live under .../pub/pmc/deprecated/oa_package/ ;
     the path oa.fcgi still advertises returns 404.
  3. Unpaywall    -- a free publisher or repository PDF for articles with no PMC
     deposit at all.

Anything still closed is recorded as unavailable rather than worked around.

Layout: documentation/refs/systematic/<TOPIC>/<Author><Year>_<PMID>/
            article.pdf, article.xml, supplements/, meta.json

Usage: python3 build/lit/fetch.py [--limit N] [--topic TTE] [--dry-run]
"""

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from xml.etree import ElementTree as ET

EMAIL = "ahmad.pub@gmail.com"
UA = f"TTE-open-problems/1.0 (mailto:{EMAIL})"
EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
OA_FCGI = "https://www.ncbi.nlm.nih.gov/pmc/utils/oa/oa.fcgi"
IDCONV = "https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/"
EPMC = "https://www.ebi.ac.uk/europepmc/webservices/rest"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")

# Directory names match the ones already in documentation/refs.
TOPIC_DIR = {"ccw": "CCW", "emul": "EMUL", "gform": "GFORM", "msm": "MSM",
             "itb": "ITB", "tte": "TTE", "temu": "TEMU", "tt": "TT"}
TOPIC_ORDER = ["ccw", "emul", "gform", "msm", "itb", "tte", "temu", "tt"]

MAX_PACKAGE_MB = 250
MIN_FREE_GB = 5

# Title-overlap thresholds: report anything doubtful, throw away only what is
# unambiguously a different paper.
FLAG_BELOW = 0.5
DISCARD_BELOW = 0.2

_ncbi_lock = threading.Lock()
_ncbi_last = [0.0]


def throttled_ncbi():
    """NCBI allows three requests a second without an API key."""
    with _ncbi_lock:
        wait = 0.36 - (time.time() - _ncbi_last[0])
        if wait > 0:
            time.sleep(wait)
        _ncbi_last[0] = time.time()


def get(url, binary=False, timeout=180, tries=3, cap_mb=None, ncbi=False):
    for attempt in range(tries):
        if ncbi:
            throttled_ncbi()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                if cap_mb:
                    n = r.headers.get("Content-Length")
                    if n and int(n) > cap_mb * 1024 * 1024:
                        raise ValueError(f"oversize: {int(n) // 1048576} MB > {cap_mb} MB")
                data = r.read()
            return data if binary else data.decode("utf8", "ignore")
        except ValueError:
            raise
        except Exception:  # noqa: BLE001 - network flakiness is expected
            if attempt == tries - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
    return None


def slug(s, n=48):
    s = re.sub(r"[^A-Za-z0-9]+", "-", (s or "")).strip("-")
    return s[:n] or "untitled"


def topic_of(rec):
    for t in TOPIC_ORDER:
        if t in rec.get("found_by", []):
            return t
    # Unreachable while every record carries at least one phrase from the
    # search; TOPIC_ORDER[-1] is the broadest set, so a record that somehow
    # lost its provenance still lands in a real folder rather than a KeyError.
    return TOPIC_ORDER[-1]


def folder_for(rec):
    # An author entry can be blank when PubMed carries a collective name only.
    names = [a for a in (rec.get("authors") or []) if (a or "").strip()]
    author = slug(names[0].split()[0], 28) if names else "anon"
    ident = rec.get("pmid") or rec.get("pmcid") or slug(rec.get("doi", ""), 20)
    return os.path.join(OUT, TOPIC_DIR[topic_of(rec)],
                        f"{author}{rec.get('year') or ''}_{ident}")


# ------------------------------------------------------------ identifiers ---

def resolve_pmcids(recs):
    """Fill in missing PMCIDs from PMIDs and DOIs via the NCBI ID converter.

    One id type per request: the service rejects a mixed list outright, and it
    returns pmid as a JSON number, so keys are compared as strings.
    """
    todo = [r for r in recs if not r.get("pmcid") and (r.get("pmid") or r.get("doi"))]
    by_type = {"pmid": [r for r in todo if r.get("pmid")],
               "doi": [r for r in todo if not r.get("pmid") and r.get("doi")]}
    for idtype, group in by_type.items():
        for i in range(0, len(group), 190):
            chunk = group[i:i + 190]
            ids = ",".join(str(r[idtype]) for r in chunk)
            try:
                d = json.loads(get(f"{IDCONV}?tool=TTE-open-problems&email={EMAIL}"
                                   f"&format=json&idtype={idtype}"
                                   f"&ids={urllib.parse.quote(ids)}", ncbi=True), strict=False)
            except Exception as e:  # noqa: BLE001
                print(f"  idconv {idtype} batch failed: {e}", file=sys.stderr)
                continue
            found = {}
            for x in d.get("records", []):
                key = str(x.get("requested-id") or x.get(idtype) or "").lower()
                if key:
                    found[key] = x
            for r in chunk:
                hit = found.get(str(r[idtype]).lower())
                if hit and hit.get("pmcid"):
                    r["pmcid"] = hit["pmcid"]
            print(f"  id conversion {idtype} {min(i + 190, len(group))}/{len(group)}",
                  end="\r", file=sys.stderr)
        if group:
            print(file=sys.stderr)


# --------------------------------------------------------------- fetchers ---

def oa_package(pmcid):
    """Return (href, license) for the OA package, or (None, reason).

    oa.fcgi still advertises .../pub/pmc/oa_package/... , which now 404s; the
    tree was moved under deprecated/ without the service being updated.
    """
    xml = get(f"{OA_FCGI}?id={pmcid}", ncbi=True)
    root = ET.fromstring(xml)
    err = root.find("error")
    if err is not None:
        return None, (err.get("code") or "error")
    rec = root.find(".//record")
    if rec is None:
        return None, "no record"
    best = None
    for link in rec.iter("link"):
        if link.get("format") == "tgz":
            best = link.get("href")
    if not best:
        return None, "no tgz link"
    href = best.replace("ftp://ftp.ncbi.nlm.nih.gov/pub/pmc/",
                        "https://ftp.ncbi.nlm.nih.gov/pub/pmc/deprecated/")
    return href, rec.get("license", "")


SUPP_HINT = re.compile(
    r"(supp|appendix|additional|online[-_]?only|mmc\d|sm\d|s\d+\b|figure|table|data)", re.I)

# How a supplement announces itself on its own first page. Some packages deposit
# the appendix but not the article PDF, and the appendix repeats the paper's
# title, so no title comparison can tell them apart. The opening words can.
SUPP_OPENING = re.compile(
    r"^\W*(supplement(al|ary)?(\s+(online\s+)?(content|material|information|"
    r"appendix|file|data|methods|results|table|figure))?|appendix|additional\s+file|"
    r"web[- ]based\s+supplementary|table\s+of\s+contents\s+supplement|"
    r"e-?(appendix|methods|figures?|tables?))\b", re.I)


def is_supplement_pdf(path):
    """Whether a PDF announces itself as supplementary matter on its first page."""
    try:
        text = subprocess.run(["pdftotext", "-f", "1", "-l", "1", path, "-"],
                              capture_output=True, timeout=60).stdout.decode("utf8", "ignore")
    except Exception:  # noqa: BLE001
        return False
    return bool(SUPP_OPENING.match(" ".join(text.split())[:200]))


def pick_main(names, stem):
    """Which of several same-suffix files in an OA package is the article itself.

    A package puts the paper and its appendices side by side in one flat
    directory, in no dependable order, so taking the first PDF encountered lands
    on a supplement often enough to matter. The article's own file shares its
    stem with the JATS; failing that, prefer a name with no supplement wording.
    """
    if not names:
        return None
    if stem:
        for n in names:
            if os.path.splitext(n)[0] == stem:
                return n
    plain = [n for n in names if not SUPP_HINT.search(os.path.splitext(n)[0])]
    return (plain or names)[0]


def unpack_oa(tgz_bytes, dest, have=()):
    """Extract an OA package: the article's PDF and XML to the root, rest to supplements/.

    `have` names the files Europe PMC already wrote. Those win: the package is
    fetched only to fill gaps, and some packages carry the supplement PDF but not
    the article's, so writing over a good article.pdf loses the paper itself.
    """
    got = {"pdf": None, "xml": None, "supplements": []}
    with tarfile.open(fileobj=io.BytesIO(tgz_bytes), mode="r:gz") as tf:
        members = [m for m in tf.getmembers()
                   if m.isfile() and not os.path.basename(m.name).startswith(".")]
        by_name = {os.path.basename(m.name): m for m in members}
        names = list(by_name)
        xmls = [n for n in names if n.lower().endswith(".nxml")] or \
               [n for n in names if n.lower().endswith(".xml")]
        main_xml = pick_main(sorted(xmls), "")
        stem = os.path.splitext(main_xml)[0] if main_xml else ""
        main_pdf = pick_main(sorted(n for n in names if n.lower().endswith(".pdf")), stem)
        if "pdf" in have:
            main_pdf = None
        if "xml" in have:
            main_xml = None

        for name, m in by_name.items():
            data = tf.extractfile(m)
            if data is None:
                continue
            payload = data.read()
            if name == main_pdf:
                path, got["pdf"] = os.path.join(dest, "article.pdf"), "article.pdf"
            elif name == main_xml:
                path, got["xml"] = os.path.join(dest, "article.xml"), "article.xml"
            else:
                os.makedirs(os.path.join(dest, "supplements"), exist_ok=True)
                path = os.path.join(dest, "supplements", name)
                got["supplements"].append(name)
            with open(path, "wb") as fh:
                fh.write(payload)
    return got


def europepmc(pmcid, dest):
    """Full text XML, rendered PDF and supplements zip from Europe PMC."""
    got = {"pdf": None, "xml": None, "supplements": []}
    try:
        xml = get(f"{EPMC}/{pmcid}/fullTextXML")
        if xml and xml.lstrip().startswith("<") and "<body" in xml:
            with open(os.path.join(dest, "article.xml"), "w", encoding="utf8") as fh:
                fh.write(xml)
            got["xml"] = "article.xml"
    except Exception:  # noqa: BLE001
        pass
    try:
        blob = get(f"https://europepmc.org/articles/{pmcid}?pdf=render",
                   binary=True, cap_mb=MAX_PACKAGE_MB)
        if blob and blob[:4] == b"%PDF":
            with open(os.path.join(dest, "article.pdf"), "wb") as fh:
                fh.write(blob)
            got["pdf"] = "article.pdf"
    except Exception:  # noqa: BLE001
        pass
    try:
        blob = get(f"{EPMC}/{pmcid}/supplementaryFiles", binary=True, cap_mb=MAX_PACKAGE_MB)
        if blob and blob[:2] == b"PK":
            with zipfile.ZipFile(io.BytesIO(blob)) as zf:
                for n in zf.namelist():
                    if n.endswith("/"):
                        continue
                    base = os.path.basename(n)
                    if not base or base.startswith("."):
                        continue
                    os.makedirs(os.path.join(dest, "supplements"), exist_ok=True)
                    with open(os.path.join(dest, "supplements", base), "wb") as fh:
                        fh.write(zf.read(n))
                    got["supplements"].append(base)
    except Exception:  # noqa: BLE001
        pass
    return got


def unpaywall_pdf(doi, dest):
    try:
        d = json.loads(get(f"https://api.unpaywall.org/v2/"
                           f"{urllib.parse.quote(doi, safe='')}?email={EMAIL}"), strict=False)
    except Exception:  # noqa: BLE001
        return None
    if not d.get("is_oa"):
        return None
    locs = [d.get("best_oa_location") or {}] + (d.get("oa_locations") or [])
    for loc in locs:
        url = (loc or {}).get("url_for_pdf")
        if not url:
            continue
        try:
            blob = get(url, binary=True, cap_mb=MAX_PACKAGE_MB)
        except Exception:  # noqa: BLE001
            continue
        if blob and blob[:4] == b"%PDF":
            with open(os.path.join(dest, "article.pdf"), "wb") as fh:
                fh.write(blob)
            return "article.pdf"
    return None


# ---------------------------------------------------------- verification ---

def _words(s):
    return set(re.findall(r"[a-z0-9]+", (s or "").lower())) - {
        "a", "an", "the", "of", "for", "and", "in", "on", "to", "with", "using"}


def pdf_title_match(dest, expected):
    """Fraction of the record's title words that appear on the PDF's first pages.

    The Unpaywall route returns a publisher PDF with no metadata to compare, and
    that is exactly the route most likely to land on the wrong document, so it
    is worth reading the page. Returns None when pdftotext is unavailable.
    """
    path = os.path.join(dest, "article.pdf")
    if not os.path.exists(path):
        return None
    try:
        text = subprocess.run(["pdftotext", "-f", "1", "-l", "2", path, "-"],
                              capture_output=True, timeout=60).stdout.decode("utf8", "ignore")
    except Exception:  # noqa: BLE001 - no pdftotext, or a PDF it cannot read
        return None
    a, b = _words(expected), _words(text)
    if not a or not b:
        return None
    return round(len(a & b) / len(a), 3)


def title_match(dest, expected):
    """How well the downloaded full text's own title matches the record's.

    Cheap insurance against fetching the wrong article: an identifier that has
    drifted produces a real PDF for a real paper, which no download-level check
    would otherwise notice. Returns None when there is no XML to check against.
    """
    if not expected:
        return None
    path = os.path.join(dest, "article.xml")
    if not os.path.exists(path):
        return pdf_title_match(dest, expected)
    try:
        root = ET.parse(path).getroot()
    except Exception:  # noqa: BLE001
        return pdf_title_match(dest, expected)
    meta = root.find(".//article-meta")
    scope = meta if meta is not None else root
    parts = []
    for tag in ("article-title", "subtitle"):
        node = scope.find(f".//{tag}")
        if node is not None:
            parts.append("".join(node.itertext()))
    got = re.sub(r"\s+", " ", " ".join(parts)).strip()
    if not got:
        return None
    a, b = _words(expected), _words(got)
    if not a or not b:
        return None
    # Containment, not Jaccard: publishers routinely deposit a short form of the
    # title, and a paper whose deposited title is a subset of the record's is
    # still the right paper. What matters is whether the two describe the same
    # work at all, which a wholly different article fails outright.
    return round(len(a & b) / min(len(a), len(b)), 3)


def note(out, msg):
    """Append a note once; verification re-runs on every resume."""
    cur = out.get("note") or ""
    if msg in cur:
        return
    out["note"] = f"{cur}; {msg}" if cur else msg


def verify_files(dest, rec, out):
    """Check that what landed in the folder really is the article, and score it."""
    pdf = os.path.join(dest, "article.pdf")
    if out["files"].get("pdf") and is_supplement_pdf(pdf):
        os.makedirs(os.path.join(dest, "supplements"), exist_ok=True)
        name = "supplementary.pdf"
        os.replace(pdf, os.path.join(dest, "supplements", name))
        out["files"]["pdf"] = None
        out["files"]["supplements"] = sorted(set(out["files"]["supplements"]) | {name})
        note(out, "the only PDF deposited is supplementary matter, filed as such")
    out["title_match"] = title_match(dest, rec.get("title"))
    if out["title_match"] is not None and out["title_match"] < FLAG_BELOW:
        note(out, f"title mismatch ({out['title_match']}): check the identifiers")
        # Some PMIDs resolve to a container deposit rather than the article
        # itself, e.g. a whole conference supplement. Keeping that file would
        # be worse than having none: it looks like the paper and is not.
        if out["title_match"] < DISCARD_BELOW:
            for f in os.listdir(dest):
                p = os.path.join(dest, f)
                shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
            out["files"] = {"pdf": None, "xml": None, "supplements": []}
            note(out, "fetched document discarded, it is a different article")
    return out


# -------------------------------------------------------------- per record ---

def handle(rec):
    dest = folder_for(rec)
    meta_path = os.path.join(dest, "meta.json")
    if os.path.exists(meta_path):
        try:
            prior = json.load(open(meta_path, encoding="utf8"))
        except Exception:  # noqa: BLE001 - a truncated meta means redo the article
            pass
        else:
            # Re-verify on every resume: the checks are local and free, so a
            # sharpened rule reaches articles fetched under the previous one.
            before = json.dumps(prior, sort_keys=True)
            prior.setdefault("files", {"pdf": None, "xml": None, "supplements": []})
            verify_files(dest, rec, prior)
            if not (prior["files"]["pdf"] or prior["files"]["xml"]):
                prior["source"] = "unavailable"
            if json.dumps(prior, sort_keys=True) != before:
                with open(meta_path, "w", encoding="utf8") as fh:
                    json.dump(prior, fh, indent=1, ensure_ascii=False)
            return prior
    os.makedirs(dest, exist_ok=True)

    out = {k: rec.get(k) for k in ("pmid", "pmcid", "doi", "title", "journal", "year",
                                   "authors", "found_by", "dbs")}
    out["topic"] = TOPIC_DIR[topic_of(rec)]
    out["screen"] = rec.get("screen")
    out["dir"] = os.path.relpath(dest, ROOT)
    out["files"] = {"pdf": None, "xml": None, "supplements": []}
    out["source"] = None
    out["note"] = None

    pmcid = rec.get("pmcid") or ""
    if pmcid:
        got = europepmc(pmcid, dest)
        if got["xml"] or got["pdf"] or got["supplements"]:
            out["files"], out["source"] = got, "europepmc"
        if not (out["files"]["xml"] and out["files"]["pdf"]):
            try:
                href, lic = oa_package(pmcid)
            except Exception as e:  # noqa: BLE001
                href, lic = None, f"oa service error: {e}"
            if href:
                try:
                    blob = get(href, binary=True, cap_mb=MAX_PACKAGE_MB)
                    pkg = unpack_oa(blob, dest,
                                    have={k for k in ("pdf", "xml") if out["files"][k]})
                    out["license"] = lic
                    # Keep whatever Europe PMC already supplied; fill the gaps.
                    for k in ("pdf", "xml"):
                        out["files"][k] = out["files"][k] or pkg[k]
                    out["files"]["supplements"] = sorted(
                        set(out["files"]["supplements"]) | set(pkg["supplements"]))
                    out["source"] = "europepmc+oa-package" if out["source"] else "pmc-oa-package"
                except Exception as e:  # noqa: BLE001
                    out["note"] = f"oa package failed: {e}"
            else:
                out["note"] = f"not in oa package set ({lic})"

    if not out["files"]["pdf"] and rec.get("doi"):
        pdf = unpaywall_pdf(rec["doi"], dest)
        if pdf:
            out["files"]["pdf"] = pdf
            out["source"] = out["source"] or "unpaywall"

    verify_files(dest, rec, out)

    if not (out["files"]["pdf"] or out["files"]["xml"]):
        out["source"] = "unavailable"
        # Leave no empty directory behind for articles nothing could be fetched for.
        if not os.listdir(dest):
            os.rmdir(dest)
            out["dir"] = None
            return out

    with open(meta_path, "w", encoding="utf8") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
    return out


def take_lock():
    """Refuse to run while another fetch is live.

    Two concurrent runs share the output tree and the manifest, and because a
    finished folder is trusted on sight, the slower run silently adopts whatever
    the other one wrote. Whichever finishes last wins the manifest. One at a time.
    """
    path = os.path.join(OUT, ".fetch.lock")
    if os.path.exists(path):
        try:
            pid = int(open(path).read().strip())
            os.kill(pid, 0)
        except (ValueError, ProcessLookupError, PermissionError):
            pass  # stale lock from a killed run
        else:
            sys.exit(f"another fetch is running (pid {pid}); "
                     f"stop it or remove {os.path.relpath(path, ROOT)}")
    os.makedirs(OUT, exist_ok=True)
    with open(path, "w") as fh:
        fh.write(str(os.getpid()))
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--topic", default="")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--decisions", default="include",
                    help="comma-separated screen decisions to fetch")
    args = ap.parse_args()

    src = os.path.join(OUT, "screened.jsonl")
    if not os.path.exists(src):
        sys.exit(f"No screening output at {src}. Run build/lit/batches.py finalize first.")
    wanted = set(args.decisions.split(","))
    recs = [json.loads(l) for l in open(src, encoding="utf8")]
    recs = [r for r in recs if r["screen"]["decision"] in wanted]
    if args.topic:
        recs = [r for r in recs if TOPIC_DIR[topic_of(r)] == args.topic]
    recs.sort(key=lambda r: (TOPIC_ORDER.index(topic_of(r)), -int(r.get("year") or 0)))
    if args.limit:
        recs = recs[:args.limit]

    print(f"{len(recs)} records to fetch")
    if not args.dry_run:
        lock = take_lock()
    if args.dry_run:
        for r in recs[:20]:
            print(f"  {TOPIC_DIR[topic_of(r)]:6s} {r.get('year','?'):4s} "
                  f"{(r.get('title') or '')[:90]}")
        return

    print("resolving PMCIDs")
    resolve_pmcids(recs)
    print(f"  {sum(1 for r in recs if r.get('pmcid'))} of {len(recs)} have a PMCID")

    free_gb = shutil.disk_usage(OUT).free / 1e9
    print(f"free disk: {free_gb:.1f} GB")

    results, done = [], 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = {pool.submit(handle, r): r for r in recs}
        for f in as_completed(futs):
            done += 1
            try:
                results.append(f.result())
            except Exception as e:  # noqa: BLE001
                r = futs[f]
                results.append({"pmid": r.get("pmid"), "title": r.get("title"),
                                "source": "error", "note": str(e)})
            if done % 25 == 0:
                free = shutil.disk_usage(OUT).free / 1e9
                print(f"  {done}/{len(recs)}  free {free:.1f} GB", end="\r", file=sys.stderr)
                if free < MIN_FREE_GB:
                    print(f"\nstopping: free disk below {MIN_FREE_GB} GB", file=sys.stderr)
                    for g in futs:
                        g.cancel()
                    break
    print(file=sys.stderr)

    manifest = os.path.join(OUT, "manifest.json")
    prior = json.load(open(manifest, encoding="utf8")) if os.path.exists(manifest) else []
    def ident(x):
        return x.get("pmid") or x.get("pmcid") or x.get("doi") or x.get("title")

    seen = {ident(x) for x in results}
    merged = results + [x for x in prior if ident(x) not in seen]
    json.dump(merged, open(manifest, "w", encoding="utf8"), indent=1, ensure_ascii=False)

    tally = {}
    for r in results:
        tally[r.get("source") or "none"] = tally.get(r.get("source") or "none", 0) + 1
    print(f"\n{len(results)} processed")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"  {k:20s} {v}")
    print(f"  with pdf         {sum(1 for r in results if (r.get('files') or {}).get('pdf'))}")
    print(f"  with xml         {sum(1 for r in results if (r.get('files') or {}).get('xml'))}")
    print(f"  with supplements {sum(1 for r in results if (r.get('files') or {}).get('supplements'))}")
    checked = [r for r in results if r.get("title_match") is not None]
    print(f"  title verified   {sum(1 for r in checked if r['title_match'] >= 0.5)}"
          f" of {len(checked)} checked, "
          f"{sum(1 for r in checked if r['title_match'] < 0.5)} mismatched")
    if os.path.exists(lock):
        os.remove(lock)


if __name__ == "__main__":
    main()
