#!/usr/bin/env bash
# kit-review-findings.sh — harvest a reviewer's findings without anyone remembering to.
#
# Invoked from the SubagentStop hook with the hook JSON on stdin. The defect it closes:
# reviewers emitted correctly formatted `Findings (recordable)` blocks and NOTHING consumed
# them. On a real project that had run a T2 implementation review and a T3 design review the
# finding table held zero rows; 19 appeared the moment the blocks were piped in by hand. Every
# escape-rate and accelerator number in the README was computed from an empty table, and
# `T3 0/13` read as "nothing escaped" while meaning "nothing was recorded".
#
# WHY THIS HOOK AND NOT THE CHECKPOINT. The task filed against this assumed kit-checkpoint.sh
# was the home and worried that findings would need somewhere to accumulate, because a
# checkpoint fires per work unit while reviews happen mid-unit. SubagentStop fires when a
# reviewer stops, which is exactly when its findings exist -- no buffer, no accumulation, and
# the agent's own transcript is reachable by the same path kit-spend.sh already uses.
#
# WHICH TASK A FINDING BELONGS TO. Nothing in this kit tracks a current task: kit-spend.sh and
# kit-checkpoint.sh both write `"task":""` and let the indexer attribute afterwards. So does
# this. The tempting alternative -- read HEAD's `Task-Id` trailer -- is right whenever the
# documented rhythm was followed (commit `Task-Status: progress`, then review) and SILENTLY
# WRONG otherwise: an approach review that runs before the task's first commit files its
# findings against the previous task. Post-hoc attribution can be wrong too, but it is wrong
# the same way spend is, and it reports what it could not attribute instead of inventing it.
#
# Instrumentation never fails the session. Every exit here is 0.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0
PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")

TRANSCRIPT=""; AGENT=""; AGENT_ID=""; SESSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --transcript) TRANSCRIPT=${2:-}; shift; shift ;;
    --agent)      AGENT=${2:-};      shift; shift ;;
    --agent-id)   AGENT_ID=${2:-};   shift; shift ;;
    -h|--help)    sed -n '2,10p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

# Same reader as kit-spend.sh: enough for a flat hook payload, not a JSON parser.
jf() {
  printf '%s' "$1" | awk -v k="\"$2\":" '
    { i = index($0, k); if (i == 0) next
      r = substr($0, i + length(k))
      sub(/^[ \t]*"/, "", r); i = index(r, "\"")
      if (i > 1) print substr(r, 1, i-1) }' | head -1
}

if [ -z "$TRANSCRIPT" ] && [ ! -t 0 ]; then
  HOOK=$(cat)
  TRANSCRIPT=$(jf "$HOOK" transcript_path)
  [ -n "$AGENT" ]    || AGENT=$(jf "$HOOK" agent_type)
  [ -n "$SESSION" ]  || SESSION=$(jf "$HOOK" session_id)
  [ -n "$AGENT_ID" ] || AGENT_ID=$(jf "$HOOK" agent_id)
  [ -n "$AGENT_ID" ] || AGENT_ID=$(jf "$HOOK" agentId)
fi

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

EVENTS="$ROOT/$STATE_DIR/events.ndjson"
SUBDIR="${TRANSCRIPT%.jsonl}/subagents"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$ROOT/$STATE_DIR"
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Only the agent that just stopped. The main loop is not a reviewer, and sweeping every agent
# file on Stop would re-harvest findings already recorded -- the duplicate-firing shape that
# produced four spend rows for two events before kit-spend.sh keyed them.
[ -n "$AGENT_ID" ] || exit 0
FILE=$(find "$SUBDIR" -type f -name "agent-$AGENT_ID.jsonl" 2>/dev/null | head -1)
[ -n "$FILE" ] || exit 0

# Idempotent by agent id: a hook that fires twice must not record twice. kit-spend.sh solves
# the same problem with OR REPLACE on a transcript key; findings are append-only events, so the
# guard has to be here.
grep -q "\"kind\":\"finding\".*\"agent_id\":\"$AGENT_ID\"" "$EVENTS" 2>/dev/null && exit 0
grep -q "\"finding-gap\".*\"agent_id\":\"$AGENT_ID\"" "$EVENTS" 2>/dev/null && exit 0

# Pull the block out of the transcript. Anchored on the heading and stopped at the next one, so
# an agent that QUOTES the format in prose -- reviewers do, when explaining what they emit -- is
# not harvested. The vocabulary is not checked here: kit-finding.sh owns it, rejects what it
# does not recognise, and says so per line. Duplicating the list here is how it drifted before.
LINES=$(awk '
  /"type":"assistant"/ || /"role":"assistant"/ { buf = buf $0 "\n" }
  END { print buf }' "$FILE" |
  sed 's/\\n/\n/g' |
  awk '
    /Findings \(recordable\)/ { inblock = 1; next }
    inblock && /^[^|]*##[^#]/  { inblock = 0 }
    inblock {
      line = $0
      gsub(/^[ \t>*`-]+/, "", line); gsub(/[ \t`]+$/, "", line)
      # class|severity|lang|pattern[|domain] -- at least three fields, first two non-empty.
      if (line ~ /^[a-z-]+\|[a-z]+\|[a-zA-Z0-9+#-]*\|/) print line
    }')

EMITTED=$(printf '%s' "$LINES" | grep -c . 2>/dev/null || true)
[ "${EMITTED:-0}" -gt 0 ] || exit 0

# Recorded with no task. The indexer binds it to the task whose next status transition follows,
# exactly as it does for spend, and reports what it cannot bind rather than guessing.
OUT=$(printf '%s\n' "$LINES" |
      bash "$(dirname "$0")/kit-finding.sh" --unattributed --agent "${AGENT:-subagent}" \
           --agent-id "$AGENT_ID" --batch 2>&1)
RECORDED=$(printf '%s' "$OUT" | sed -n 's/.*recorded \([0-9]*\) finding(s).*/\1/p' | head -1)
printf '%s\n' "$OUT" >&2

# A review that produced findings and recorded none is the failure this task exists to end, so
# it is an EVENT rather than a line in a terminal nobody kept -- the same standing spend-gap
# has. It is also how the vocabulary problem gets measured instead of estimated: the sibling
# task says "roughly half" are rejected for unknown classes, and roughly is not a number.
if [ "${RECORDED:-0}" -lt "$EMITTED" ]; then
  printf '{"task":"","kind":"finding-gap","at":"%s","agent":"%s","agent_id":"%s","session":"%s","emitted":%d,"recorded":%d}\n' \
    "$NOW" "$(esc "${AGENT:-subagent}")" "$(esc "$AGENT_ID")" "$(esc "$SESSION")" \
    "${EMITTED:-0}" "${RECORDED:-0}" >> "$EVENTS"
fi
exit 0
