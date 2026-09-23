#!/usr/bin/env bash
# Drive one study's run to completion, detached, restarting after every exit.
#
# The run itself is checkpointed per block, so a restart costs at most one
# partial block. What this adds is that the loop survives a killed shell: the
# study directory is polled for its finished scenario files and the driver only
# stops when they are all there or when the attempt budget runs out.
#
#   nohup build/studies/drive.sh <study-dir> <expected-scenarios> \
#         > <study-dir>/results/drive.log 2>&1 &
#
# Every attempt kills orphaned multisession workers first. Without that, killed
# runs leak six R workers apiece and the machine ends up spending its time on
# context switches: a fifty-second scenario has taken over ten minutes.

set -u
STUDY="${1:?study directory}"
WANT="${2:?expected scenario count}"
MAX_ATTEMPTS="${3:-200}"
# TTE_SLICE (for example 1:2) runs only those scenarios; pass their count as
# <expected-scenarios>.
# TTE_RAW points the completion count at a run that writes elsewhere, such as a
# registered replication under results/replication/raw.
RAW="${TTE_RAW:-$STUDY/results/raw}"

# One driver per study. Two drivers on the same study each begin an attempt by
# killing the study's R processes, so each kills the other's run and neither
# finishes: a second launch looked like progress and was a treadmill.
LOCK="$STUDY/results/drive.pid"
mkdir -p "$STUDY/results"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK")" 2>/dev/null; then
  echo "[drive] already running as pid $(cat "$LOCK"); not starting a second driver"
  exit 3
fi
echo $$ > "$LOCK"

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

count() { ls "$RAW"/scenario-*.rds 2>/dev/null | wc -l | tr -d ' '; }

stalled=0
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  have=$(count)
  if [ "$have" -ge "$WANT" ]; then
    echo "[drive] complete: $have of $WANT scenarios"
    exit 0
  fi
  echo "[drive] attempt $attempt, $have of $WANT scenarios, $(date '+%H:%M:%S')"
  kill_study_r "$STUDY"
  sleep 2
  ( cd "$STUDY" && Rscript R/04-run.R ${TTE_SLICE:-} ) 2>&1 | tail -n 40

  # A restart loop that makes no progress is not resilience, it is a machine
  # burning cores on the same failure. Blocks land inside a scenario, so
  # progress is counted in parts as well as in finished scenarios.
  parts=$(ls "$RAW"/scenario-*-parts/*.rds 2>/dev/null | wc -l | tr -d ' ')
  if [ "$(count)" -le "$have" ] && [ "${parts:-0}" -le "${last_parts:-0}" ]; then
    stalled=$(( stalled + 1 ))
  else
    stalled=0
  fi
  last_parts="$parts"
  if [ "$stalled" -ge 3 ]; then
    echo "[drive] no progress across three consecutive attempts; stopping"
    exit 2
  fi
done

echo "[drive] attempt budget exhausted at $(count) of $WANT scenarios"
exit 1
