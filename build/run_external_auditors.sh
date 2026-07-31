#!/usr/bin/env bash
# Runs the two external auditors over the batched prompts produced by
# build/make_audit_batches.mjs.
#
# These are deliberately NOT workflow agents. Each call takes minutes, the Bash tool caps a
# foreground call at 600s, and an agent slot spent waiting on a socket is an agent slot not
# doing work. Running them as detached shell jobs lets the Claude verification agents work in
# parallel with them.
#
# Restartable: a batch whose output file is already non-empty is skipped, so re-running after
# a crash only redoes what is missing.
#
# Usage: build/run_external_auditors.sh [codex|grok|both] [parallelism]

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="$ROOT/documentation/audit"
SCHEMA="$AUDIT/schema/external-verdict.json"
WHICH="${1:-both}"
PAR="${2:-3}"

run_auditor() {
  local who="$1"
  local dir="$AUDIT/auditors/$who"
  local n; n=$(ls "$dir"/prompts/*.txt 2>/dev/null | wc -l | tr -d ' ')
  echo "$who: $n batches, parallelism $PAR"
  # A worker script rather than an inline xargs body: the inline form could not be assembled
  # once the prompt paths and schema were substituted in.
  ls "$dir"/prompts/*.txt | xargs -P "$PAR" -I{} "$ROOT/build/audit_one.sh" "$who" "{}"
}

case "$WHICH" in
  codex) run_auditor codex ;;
  grok)  run_auditor grok ;;
  both)  run_auditor codex & run_auditor grok & wait ;;
  *)     echo "usage: $0 [codex|grok|both] [parallelism]"; exit 1 ;;
esac

echo
echo "codex outputs: $(ls "$AUDIT"/auditors/codex/out/*.json 2>/dev/null | wc -l | tr -d ' ')"
echo "grok  outputs: $(ls "$AUDIT"/auditors/grok/out/*.json 2>/dev/null | wc -l | tr -d ' ')"
