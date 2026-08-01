#!/usr/bin/env bash
# Run one study end to end: truth, replicates, analysis, figures.
#
# Every step is resumable, because long processes get killed on this machine and
# a driver that restarts from zero is useless. Re-running this after an
# interruption picks up where it stopped.
#
# The last line of the analysis states which branch of the study's own decision
# rule the results fall into, using thresholds written before the run. That line
# is what this echoes back, so a study that completed and a study that produced
# an answer are not confused with each other.
#
# Usage: build/studies/run.sh <study-dir> [scenario-slice]

set -uo pipefail
D="${1:?pass a study directory}"
SLICE="${2:-}"
cd "$D" || exit 1
NAME="$(basename "$D")"

step() {
  local f="$1"; shift
  [ -f "R/$f" ] || { echo "  $NAME: no R/$f"; return 1; }
  Rscript "R/$f" "$@" 2>&1 | tail -3 | sed "s|^|  |"
  return "${PIPESTATUS[0]}"
}

echo "== $NAME"
if [ -f "R/03-truth.R" ]; then step 03-truth.R $SLICE || echo "  truth: nonzero exit"; fi
step 04-run.R $SLICE || echo "  run: nonzero exit"
step 05-analyze.R || echo "  analyze: nonzero exit"
[ -f "R/06-figures.R" ] && step 06-figures.R >/dev/null 2>&1

echo -n "  VERDICT: "
Rscript R/05-analyze.R 2>/dev/null | grep -iE "decision-rule branch|branch:" | tail -1 \
  || echo "(no decision-rule line)"
