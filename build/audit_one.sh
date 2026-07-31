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

# Restartable: never redo a batch that already produced a real verdict. A non-empty file is
# not enough. Grok returns a well-formed envelope carrying an empty opinions array when it
# short-circuits, using about 140 output tokens instead of several thousand, and a size check
# treats that as a completed audit. It is the same silent-coverage-loss failure the roster gate
# in collect_opinions.mjs exists to catch, one level further down, so the skip condition is
# "this file contains at least one opinion" rather than "this file exists".
if [ -s "$OUT" ] && python3 - "$OUT" <<'PYEOF'
import json, re, sys
raw = open(sys.argv[1], encoding="utf8", errors="ignore").read()
best = 0
for m in re.finditer(r"\{", raw):
    i = m.start()
    for end in range(len(raw), i, -1):
        if raw[end - 1] != "}":
            continue
        try:
            o = json.loads(raw[i:end])
        except Exception:
            continue
        ops = (o.get("structuredOutput") or {}).get("opinions") or o.get("opinions")
        if isinstance(ops, list):
            best = max(best, len(ops))
        break
sys.exit(0 if best else 1)
PYEOF
then
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
  glm)
    # GLM runs through Ollama's HTTP API rather than a CLI.
    #
    # Two things this has to work around, both measured rather than assumed:
    #
    #  1. Passing the schema in `format` is NOT enough. GLM ignores it and returns an object
    #     with invented keys wrapped in a markdown code fence. The same schema therefore also
    #     goes into the prompt body as literal text, which does produce conformant JSON.
    #  2. Whatever fencing survives is handled downstream: collect_opinions.mjs scans for any
    #     parseable object carrying an `opinions` array, so no unwrapping is needed here.
    tmp="$DIR/.$BATCH.partial"
    req="$DIR/.$BATCH.req.json"
    python3 - "$PROMPT" "$SCHEMA" "$req" <<'PY'
import json, sys
prompt = open(sys.argv[1], encoding='utf-8').read()
schema = json.load(open(sys.argv[2], encoding='utf-8'))
instruction = (
    "\n\n---\n"
    "Return ONLY a single JSON object and nothing else. No prose before or after it, no "
    "markdown code fence. It must validate against exactly this JSON Schema:\n\n"
    + json.dumps(schema, indent=1)
    + "\n\nEvery opinion you return must carry problem_id, status_vote, support_vote, "
      "confidence, rationale, weakest_true_restatement, resolving_work and counter_evidence. "
      "Use null for weakest_true_restatement when it does not apply, and [] for the two arrays "
      "when you have nothing to put in them.\n"
)
json.dump({
    "model": "glm-5.2:cloud",
    "stream": False,
    "format": schema,
    "options": {"temperature": 0.2, "num_ctx": 32768},
    "messages": [{"role": "user", "content": prompt + instruction}],
}, open(sys.argv[3], 'w'))
PY
    timeout 1200 curl -sS --fail-with-body \
      -X POST http://localhost:11434/api/chat \
      -H 'Content-Type: application/json' \
      --data-binary "@$req" \
      2> "$DIR/$BATCH.err" \
      | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.stdout.write(d.get("message",{}).get("content","")) if not d.get("error") else sys.exit(json.dumps(d["error"]))' \
      > "$tmp" 2>> "$DIR/$BATCH.err"
    rc=${PIPESTATUS[0]}
    rm -f "$req"
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
