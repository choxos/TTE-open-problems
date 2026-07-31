#!/usr/bin/env bash
# Fetches the CRAN sources pinned in documentation/audit/calibration.json into
# documentation/refs/packages/cran/, which is where the codex auditor reads package claims from
# and where tools/check-calibration.mjs looks for its ground truth.
#
# The tree is not committed: it is large and fully reproducible from the pins. Re-run this after
# a fresh clone, or whenever calibration.json changes a version.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAL="$ROOT/documentation/audit/calibration.json"
DEST="$ROOT/documentation/refs/packages/cran"
UA="TTE-open-problems/1.0 (mailto:ahmad.pub@gmail.com)"

mkdir -p "$DEST"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["packages"]; [print(k, v["version"]) for k,v in d.items()]' "$CAL" |
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
echo "vendored into $DEST"
