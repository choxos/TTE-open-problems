#!/usr/bin/env bash
# Fetches the package sources pinned in documentation/audit/calibration.json into
# documentation/refs/packages/, which is where the codex auditor reads package claims from and
# where tools/check-calibration.mjs looks for its ground truth. Each pin declares its own
# source, CRAN or PyPI, because target trial emulation tooling is split across both languages
# and a claim about a Python implementation is no less checkable than one about an R package.
#
# The tree is not committed: it is large and fully reproducible from the pins. Re-run this after
# a fresh clone, or whenever calibration.json changes a version.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAL="$ROOT/documentation/audit/calibration.json"
DEST="$ROOT/documentation/refs/packages/cran"
UA="TTE-open-problems/1.0 (mailto:ahmad.pub@gmail.com)"

PYDEST="$ROOT/documentation/refs/packages/pypi"
mkdir -p "$DEST" "$PYDEST"

# PyPI first: sdist URLs are not predictable from name and version, so the download URL comes
# from the JSON API rather than being constructed.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["packages"]; [print(k, v["version"]) for k,v in d.items() if v.get("source")=="PyPI"]' "$CAL" |
while read -r pkg ver; do
  if [ -d "$PYDEST/$pkg" ]; then echo "  have $pkg $ver (pypi)"; continue; fi
  echo "  fetch $pkg $ver (pypi)"
  url="$(curl -sSfL -m 60 -A "$UA" "https://pypi.org/pypi/$pkg/$ver/json" |
    python3 -c 'import json,sys; u=[f["url"] for f in json.load(sys.stdin)["urls"] if f["packagetype"]=="sdist"]; print(u[0] if u else "")')"
  if [ -z "$url" ]; then echo "    no sdist for $pkg $ver, skipped"; continue; fi
  tmp="$(mktemp -d)"
  curl -sSfL -m 300 -A "$UA" -o "$tmp/src" "$url"
  case "$url" in
    *.zip) (cd "$tmp" && unzip -q src) ;;
    *)     tar xzf "$tmp/src" -C "$tmp" ;;
  esac
  # sdists unpack to <name>-<version>/; normalise so the pinned path is stable.
  d="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$d" ] && mv "$d" "$PYDEST/$pkg"
  rm -rf "$tmp"
done

python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["packages"]; [print(k, v["version"]) for k,v in d.items() if v.get("source")!="PyPI"]' "$CAL" |
while read -r pkg ver; do
  if [ -d "$DEST/$pkg" ]; then echo "  have $pkg $ver"; continue; fi
  echo "  fetch $pkg $ver"
  tmp="$(mktemp -d)"
  if curl -sSfL -m 180 -A "$UA" \
       -o "$tmp/$pkg.tar.gz" \
       "https://cran.r-project.org/src/contrib/${pkg}_${ver}.tar.gz"; then
    tar xzf "$tmp/$pkg.tar.gz" -C "$DEST"
  else
    # CRAN moves superseded versions out of contrib/ into contrib/Archive/<pkg>/.
    curl -sSfL -m 180 -A "$UA" \
      -o "$tmp/$pkg.tar.gz" \
      "https://cran.r-project.org/src/contrib/Archive/$pkg/${pkg}_${ver}.tar.gz"
    tar xzf "$tmp/$pkg.tar.gz" -C "$DEST"
  fi
  rm -rf "$tmp"
done
echo "vendored into $DEST and $PYDEST"
