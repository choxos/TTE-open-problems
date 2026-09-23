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

# Kill R processes left behind by an earlier run of this study, and nothing else.
#
# This used to be `pkill -9 -f "R.framework/Resources/bin/exec/R"`, which kills every
# R process on the machine: other projects' test suites, other simulation studies, an
# interactive session. Multisession workers inherit the working directory of the run
# that spawned them, so the study directory identifies them exactly.
kill_study_r() {
  local dir; dir="$(cd "$1" && pwd -P)"
  for p in $(pgrep -f "R.framework/Resources/bin/exec/R" 2>/dev/null); do
    [ "$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$dir" ] \
      && kill -9 "$p" 2>/dev/null
  done
  return 0
}

D="${1:?pass a study directory}"
SLICE="${2:-}"
# Orphaned workers from an earlier killed run never exit. Sixteen scenarios into the
# first study the load average was 125 and a scenario that takes 50 seconds was
# taking more than ten minutes.
kill_study_r "$D"
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
