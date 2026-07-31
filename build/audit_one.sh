#!/usr/bin/env bash
# Runs one auditor over one batch prompt file. Called by run_external_auditors.sh via xargs.
#
# Usage: audit_one.sh <codex|grok> <prompt-file>
#
# The prompt is fed on stdin, not as an argument: batch prompts run to ~25 KB and passing one
# as argv blows past ARG_MAX. Feeding a real file on stdin also avoids the hang where a
# backgrounded `codex exec` with no prompt argument waits forever on an open terminal.

set -uo pipefail

AUDITOR="$1"
PROMPT="$2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="$ROOT/documentation/audit"
SCHEMA="$AUDIT/schema/external-verdict.json"
BATCH="$(basename "$PROMPT" .txt)"
DIR="$AUDIT/auditors/$AUDITOR/out"
OUT="$DIR/$BATCH.json"

mkdir -p "$DIR"

# Restartable: never redo a batch that already produced output.
if [ -s "$OUT" ]; then
  echo "  skip $AUDITOR/$BATCH (cached)"
  exit 0
fi

echo "  start $AUDITOR/$BATCH"
start=$SECONDS

case "$AUDITOR" in
  codex)
    # `-` reads the prompt from stdin. --ignore-rules stops codex loading the user's global
    # skills, which otherwise turn a verdict request into a multi-agent manuscript review.
    timeout 1200 codex exec \
      -m gpt-5.6-sol \
      -c model_reasoning_effort=max \
      -s read-only \
      --skip-git-repo-check \
      --ignore-rules \
      -C /Users/choxos/Documents/GitHub \
      --output-schema "$SCHEMA" \
      -o "$OUT" \
      - < "$PROMPT" > "$DIR/$BATCH.log" 2> "$DIR/$BATCH.err"
    rc=$?
    ;;
  grok)
    # Write to a temp file and move on success. grok streams into stdout, so redirecting
    # straight at $OUT leaves a partial file that a later run would treat as cached.
    tmp="$DIR/.$BATCH.partial"
    timeout 1200 grok \
      --prompt-file "$PROMPT" \
      --model grok-4.5 \
      --effort high \
      --no-subagents \
      --max-turns 60 \
      --permission-mode plan \
      --output-format json \
      --json-schema "$(cat "$SCHEMA")" \
      < /dev/null > "$tmp" 2> "$DIR/$BATCH.err"
    rc=$?
    if [ $rc -eq 0 ] && [ -s "$tmp" ]; then mv "$tmp" "$OUT"; else rm -f "$tmp"; fi
    ;;
  *)
    echo "unknown auditor: $AUDITOR" >&2
    exit 2
    ;;
esac

took=$((SECONDS - start))

if [ $rc -ne 0 ] || [ ! -s "$OUT" ]; then
  echo "  FAIL  $AUDITOR/$BATCH (rc=$rc, ${took}s)"
  # Leave nothing behind that a rerun would mistake for a cached success.
  rm -f "$OUT"
  exit 1
fi

echo "  ok    $AUDITOR/$BATCH (${took}s)"
