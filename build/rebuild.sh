#!/usr/bin/env bash
# Rebuilds the registry and the site from the collected opinions, in the one order that works.
#
# The order matters and the failure is silent. adjudicate.mjs regenerates
# registry/problems.json from the opinions, which discards anything apply_synthesis.mjs wrote
# onto it: the audited statements revert to what the source said and the pages still render,
# still validate and still publish. Running these two by hand in the wrong order once is how
# a catalog loses its corrections without any check noticing.
#
# Usage: build/rebuild.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== collect opinions"
node build/collect_opinions.mjs
echo
echo "== adjudicate"
node build/adjudicate.mjs
echo
echo "== apply the audited rewrites"
node build/apply_synthesis.mjs
echo
echo "== render"
node build/render_site.mjs
echo
echo "== checks"
node tests/adjudicate.test.mjs | tail -1
node tools/check-calibration.mjs
node tools/check-opinion-alignment.mjs | head -1
node tools/check-registry.mjs | tail -1
