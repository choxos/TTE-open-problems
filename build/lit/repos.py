#!/usr/bin/env python3
"""Stage 4: pull down the code and data the included articles point to.

Scans each downloaded full text for repository and data-archive links, then
retrieves what can be retrieved. A link is only followed when it names a
specific repository or deposit; bare host mentions ("available on GitHub") are
recorded as unresolvable rather than guessed at.

Layout: <article dir>/code/<host>_<slug>/  plus <article dir>/code/links.json

Usage: python3 build/lit/repos.py [--limit N] [--max-mb 200] [--links-only]
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed

EMAIL = "ahmad.pub@gmail.com"
UA = f"ITC-open-problems/1.0 (mailto:{EMAIL})"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "documentation", "refs", "systematic")

# Hosts worth following. Ordered so the more specific patterns match first.
PATTERNS = [
    ("github", re.compile(r"https?://(?:www\.)?github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", re.I)),
    ("gitlab", re.compile(r"https?://(?:www\.)?gitlab\.com/([A-Za-z0-9._/-]+?)/([A-Za-z0-9._-]+)(?=[/\s\)\"'<]|$)", re.I)),
    ("bitbucket", re.compile(r"https?://(?:www\.)?bitbucket\.org/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", re.I)),
    ("zenodo", re.compile(r"(?:https?://(?:www\.)?zenodo\.org/(?:record|records|doi)/|10\.5281/zenodo\.)([0-9]+)", re.I)),
    ("figshare", re.compile(r"https?://(?:www\.)?figshare\.com/(?:articles|s)/[^\s\"'<>)]*?([0-9]{6,})", re.I)),
    ("osf", re.compile(r"https?://(?:www\.)?osf\.io/([a-z0-9]{5})", re.I)),
    ("dryad", re.compile(r"(?:datadryad\.org/(?:stash/)?dataset/doi:|10\.5061/dryad\.)([A-Za-z0-9./]+)", re.I)),
    ("cran", re.compile(r"https?://(?:cran\.r-project\.org|CRAN\.R-project\.org)/(?:web/)?packages?/([A-Za-z0-9._]+)", re.I)),
    ("bioconductor", re.compile(r"https?://(?:www\.)?bioconductor\.org/packages/(?:release/bioc/html/)?([A-Za-z0-9._]+)", re.I)),
    ("dataverse", re.compile(r"https?://[a-z0-9.-]*dataverse[a-z0-9.-]*/[^\s\"'<>)]+", re.I)),
    ("codeocean", re.compile(r"https?://(?:www\.)?codeocean\.com/capsule/([0-9]+)", re.I)),
    ("sourceforge", re.compile(r"https?://(?:[a-z0-9-]+\.)?sourceforge\.(?:net|io)/(?:projects/)?([A-Za-z0-9._-]+)", re.I)),
]

# Repository paths that are references to tooling, not the authors' own deposit.
NOISE = re.compile(
    r"^(?:features?|about|pricing|login|signup|orgs?|topics?|search|blog|explore|"
    r"apps?|marketplace|settings|notifications|readme|actions|site)$", re.I)
NOISE_REPOS = {
    ("rstudio", "rstudio"), ("stan-dev", "stan"), ("stan-dev", "cmdstan"),
    ("tidyverse", "ggplot2"), ("hadley", "ggplot2"),
}


def get(url, binary=False, timeout=120, cap_mb=None, tries=2):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                n = r.headers.get("Content-Length")
                if cap_mb and n and int(n) > cap_mb * 1024 * 1024:
                    raise ValueError(f"oversize {int(n) // 1048576} MB")
                data = r.read(cap_mb * 1024 * 1024 + 1 if cap_mb else None)
            if cap_mb and len(data) > cap_mb * 1024 * 1024:
                raise ValueError("oversize (streamed)")
            return data if binary else data.decode("utf8", "ignore")
        except ValueError:
            raise
        except Exception:  # noqa: BLE001
            if attempt == tries - 1:
                raise
            time.sleep(1.5)
    return None


def slug(s, n=60):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", str(s)).strip("-")[:n] or "item"


def article_text(d):
    """Full text to scan: the JATS XML if present, else text pulled from the PDF."""
    parts = []
    x = os.path.join(d, "article.xml")
    if os.path.exists(x):
        parts.append(open(x, encoding="utf8", errors="ignore").read())
    p = os.path.join(d, "article.pdf")
    if os.path.exists(p) and not parts:
        try:
            parts.append(subprocess.run(["pdftotext", "-q", p, "-"], capture_output=True,
                                        timeout=120).stdout.decode("utf8", "ignore"))
        except Exception:  # noqa: BLE001
            pass
    sup = os.path.join(d, "supplements")
    if os.path.isdir(sup):
        for f in sorted(os.listdir(sup))[:40]:
            if f.lower().endswith((".txt", ".md", ".r", ".do", ".py", ".csv", ".xml", ".html")):
                try:
                    parts.append(open(os.path.join(sup, f), encoding="utf8",
                                      errors="ignore").read()[:400000])
                except Exception:  # noqa: BLE001
                    pass
    # PDFs break URLs across lines; rejoin so the patterns can see them whole.
    return re.sub(r"-\s*\n\s*", "", "\n".join(parts))


def find_links(text):
    found = {}
    for host, pat in PATTERNS:
        for m in pat.finditer(text):
            groups = [g for g in m.groups() if g]
            if host in ("github", "gitlab", "bitbucket"):
                owner, repo = groups[0], re.sub(r"\.git$", "", groups[1])
                if NOISE.match(owner) or NOISE.match(repo):
                    continue
                if (owner.lower(), repo.lower()) in NOISE_REPOS:
                    continue
                ident = f"{owner}/{repo}"
            elif groups:
                ident = groups[0]
            else:
                ident = m.group(0)
            found.setdefault((host, ident), m.group(0))
    return [{"host": h, "id": i, "url": u} for (h, i), u in found.items()]


# --------------------------------------------------------------- fetchers ---

def fetch_git(host, ident, dest, max_mb):
    base = {"github": "https://github.com", "gitlab": "https://gitlab.com",
            "bitbucket": "https://bitbucket.org"}[host]
    if host == "github":
        try:
            info = json.loads(subprocess.run(
                ["gh", "api", f"repos/{ident}"], capture_output=True, timeout=60
            ).stdout.decode() or "{}")
        except Exception:  # noqa: BLE001
            info = {}
        if info.get("message") in ("Not Found", "Moved Permanently"):
            return {"status": "not-found"}
        size_mb = (info.get("size") or 0) / 1024
        if size_mb > max_mb:
            return {"status": "skipped-oversize", "size_mb": round(size_mb, 1)}
    r = subprocess.run(["git", "clone", "--depth", "1", "--quiet",
                        f"{base}/{ident}.git", dest],
                       capture_output=True, timeout=600)
    if r.returncode != 0:
        return {"status": "clone-failed",
                "error": r.stderr.decode("utf8", "ignore")[-200:].strip()}
    subprocess.run(["rm", "-rf", os.path.join(dest, ".git")], capture_output=True)
    return {"status": "ok"}


def save_blob(dest, name, blob):
    os.makedirs(dest, exist_ok=True)
    if blob[:2] == b"PK":
        try:
            with zipfile.ZipFile(io.BytesIO(blob)) as zf:
                for n in zf.namelist():
                    if n.endswith("/") or ".." in n:
                        continue
                    target = os.path.join(dest, os.path.normpath(n).lstrip("/"))
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    with open(target, "wb") as fh:
                        fh.write(zf.read(n))
            return
        except Exception:  # noqa: BLE001
            pass
    with open(os.path.join(dest, name), "wb") as fh:
        fh.write(blob)


def fetch_zenodo(ident, dest, max_mb):
    d = json.loads(get(f"https://zenodo.org/api/records/{ident}"), strict=False)
    files = d.get("files") or []
    if not files:
        return {"status": "no-files"}
    total = sum(f.get("size", 0) for f in files) / 1e6
    if total > max_mb:
        return {"status": "skipped-oversize", "size_mb": round(total, 1)}
    for f in files:
        url = (f.get("links") or {}).get("self") or (f.get("links") or {}).get("download")
        if url:
            save_blob(dest, slug(f.get("key") or "file"), get(url, binary=True, cap_mb=max_mb))
    return {"status": "ok", "n_files": len(files)}


def fetch_figshare(ident, dest, max_mb):
    files = json.loads(get(f"https://api.figshare.com/v2/articles/{ident}/files"), strict=False)
    if not isinstance(files, list) or not files:
        return {"status": "no-files"}
    total = sum(f.get("size", 0) for f in files) / 1e6
    if total > max_mb:
        return {"status": "skipped-oversize", "size_mb": round(total, 1)}
    for f in files:
        save_blob(dest, slug(f.get("name") or "file"),
                  get(f["download_url"], binary=True, cap_mb=max_mb))
    return {"status": "ok", "n_files": len(files)}


def fetch_osf(ident, dest, max_mb):
    blob = get(f"https://files.osf.io/v1/resources/{ident}/providers/osfstorage/?zip=",
               binary=True, cap_mb=max_mb)
    if not blob or blob[:2] != b"PK":
        return {"status": "no-archive"}
    save_blob(dest, "osfstorage.zip", blob)
    return {"status": "ok"}


def fetch_cran(pkg, dest, max_mb):
    d = json.loads(get(f"https://crandb.r-pkg.org/{urllib.parse.quote(pkg)}"), strict=False)
    ver = d.get("Version")
    if not ver:
        return {"status": "not-on-cran"}
    blob = get(f"https://cran.r-project.org/src/contrib/{pkg}_{ver}.tar.gz",
               binary=True, cap_mb=max_mb)
    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(dest, f"{pkg}_{ver}.tar.gz"), "wb") as fh:
        fh.write(blob)
    return {"status": "ok", "version": ver}


def fetch_dryad(ident, dest, max_mb):
    doi = ident if ident.startswith("10.") else f"10.5061/dryad.{ident}"
    enc = urllib.parse.quote(f"doi:{doi}", safe="")
    blob = get(f"https://datadryad.org/api/v2/datasets/{enc}/download",
               binary=True, cap_mb=max_mb)
    if not blob:
        return {"status": "no-archive"}
    save_blob(dest, "dryad.zip", blob)
    return {"status": "ok"}


FETCHERS = {
    "github": lambda i, d, m: fetch_git("github", i, d, m),
    "gitlab": lambda i, d, m: fetch_git("gitlab", i, d, m),
    "bitbucket": lambda i, d, m: fetch_git("bitbucket", i, d, m),
    "zenodo": fetch_zenodo,
    "figshare": fetch_figshare,
    "osf": fetch_osf,
    "cran": fetch_cran,
    "dryad": fetch_dryad,
}


def handle(entry, max_mb, links_only):
    d = os.path.join(ROOT, entry["dir"])
    if not os.path.isdir(d):
        return None
    links = find_links(article_text(d))
    if not links:
        return {"dir": entry["dir"], "links": []}
    code = os.path.join(d, "code")
    os.makedirs(code, exist_ok=True)
    for l in links:
        dest = os.path.join(code, f"{l['host']}_{slug(l['id'].replace('/', '_'))}")
        if os.path.isdir(dest) and os.listdir(dest):
            l["status"] = "already-present"
            continue
        fn = FETCHERS.get(l["host"])
        if links_only or fn is None:
            l["status"] = "link-recorded"
            continue
        try:
            l.update(fn(l["id"], dest, max_mb))
        except Exception as e:  # noqa: BLE001
            l["status"] = "failed"
            l["error"] = str(e)[:200]
        if l.get("status") != "ok" and os.path.isdir(dest) and not os.listdir(dest):
            os.rmdir(dest)
    json.dump(links, open(os.path.join(code, "links.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    return {"dir": entry["dir"], "links": links}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--max-mb", type=int, default=200)
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--links-only", action="store_true",
                    help="find and record links without downloading")
    args = ap.parse_args()

    man = os.path.join(OUT, "manifest.json")
    if not os.path.exists(man):
        sys.exit(f"No manifest at {man}. Run build/lit/fetch.py first.")
    entries = [e for e in json.load(open(man, encoding="utf8")) if e.get("dir")]
    if args.limit:
        entries = entries[:args.limit]
    print(f"scanning {len(entries)} article folders for code and data links")

    out, done = [], 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = [pool.submit(handle, e, args.max_mb, args.links_only) for e in entries]
        for f in as_completed(futs):
            done += 1
            r = f.result()
            if r:
                out.append(r)
            if done % 25 == 0:
                print(f"  {done}/{len(entries)}", end="\r", file=sys.stderr)
    print(file=sys.stderr)

    json.dump(out, open(os.path.join(OUT, "code-manifest.json"), "w", encoding="utf8"),
              indent=1, ensure_ascii=False)
    by_host, by_status = {}, {}
    for r in out:
        for l in r["links"]:
            by_host[l["host"]] = by_host.get(l["host"], 0) + 1
            s = l.get("status", "?")
            by_status[s] = by_status.get(s, 0) + 1
    print(f"{sum(len(r['links']) for r in out)} links across "
          f"{sum(1 for r in out if r['links'])} articles")
    for k, v in sorted(by_host.items(), key=lambda kv: -kv[1]):
        print(f"  {k:14s} {v}")
    print("status:")
    for k, v in sorted(by_status.items(), key=lambda kv: -kv[1]):
        print(f"  {k:20s} {v}")


if __name__ == "__main__":
    main()
