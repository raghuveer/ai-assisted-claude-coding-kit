#!/usr/bin/env bash
# kit-spend.sh — record what a unit of work actually cost.
#
# Invoked from the SubagentStop and Stop hooks with the hook JSON on stdin. Nobody types it,
# which is the whole point: a spend record that needs remembering is missing exactly on the
# busy tasks that matter, and a partial cost table reads as CHEAP work rather than UNMEASURED
# work -- the same failure escape rate had while the findings loop was open circuit.
#
# No hook receives token usage, so the transcript is the only source. Every assistant record
# in it carries a `usage` block; this sums them.
#
# Totals are CUMULATIVE for the transcript at the moment of recording, and the row is keyed on
# the transcript rather than on the agent. That is correct whichever way the harness resolves
# transcript_path: if each subagent has its own, one row per subagent; if they share the
# session's, repeated recordings overwrite one row with a rising total. Summing distinct
# transcripts never double counts. Per-agent attribution is only meaningful in the first case,
# and the agent field says which agent last wrote the row rather than claiming more.
#
#   kit-spend.sh                      # hook JSON on stdin
#   kit-spend.sh --transcript F [--agent NAME] [--session ID]
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0
PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")

TRANSCRIPT=""; AGENT=""; SESSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --transcript) TRANSCRIPT=${2:-}; shift; shift ;;
    --agent)      AGENT=${2:-};      shift; shift ;;
    --session)    SESSION=${2:-};    shift; shift ;;
    -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

# jf <json> <key> -- first string value for a top-level key. Same shape as the reader in
# kit-index.sh: enough for flat hook payloads, and not a JSON parser.
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
  [ -n "$AGENT" ]   || AGENT=$(jf "$HOOK" agent_type)
  [ -n "$SESSION" ] || SESSION=$(jf "$HOOK" session_id)
fi

# Silent, not failing. A hook that errors on every turn is a hook the operator removes, and
# this one is instrumentation -- it must never be the reason a session stops.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# The transcript path names the project directory, and events.ndjson is COMMITTED. Hash it.
TID=$(printf '%s' "$TRANSCRIPT" | git hash-object --stdin 2>/dev/null | cut -c1-16)
[ -n "$TID" ] || exit 0

read -r TIN TOUT TCR TCW <<EOF
$(awk '
  function num(s, k,   i, r) {
    i = index(s, "\"" k "\":"); if (i == 0) return 0
    r = substr(s, i + length(k) + 3)
    sub(/^[^0-9-]*/, "", r)
    return r + 0
  }
  index($0, "\"usage\"") == 0 { next }
  {
    u = substr($0, index($0, "\"usage\""))
    tin += num(u, "input_tokens")
    tout += num(u, "output_tokens")
    tcr += num(u, "cache_read_input_tokens")
    tcw += num(u, "cache_creation_input_tokens")
  }
  END { printf "%d %d %d %d\n", tin, tout, tcr, tcw }
' "$TRANSCRIPT" 2>/dev/null)
EOF

# Nothing measured is not the same as zero cost, and recording a zero would make an
# unmeasured session look free.
[ "${TIN:-0}" = 0 ] && [ "${TOUT:-0}" = 0 ] && [ "${TCR:-0}" = 0 ] && exit 0

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
mkdir -p "$ROOT/$STATE_DIR"
printf '{"task":"","kind":"spend","at":"%s","transcript":"%s","agent":"%s","session":"%s","tok_in":%s,"tok_out":%s,"cache_read":%s,"cache_write":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TID" "$(esc "$AGENT")" "$(esc "$SESSION")" \
  "${TIN:-0}" "${TOUT:-0}" "${TCR:-0}" "${TCW:-0}" \
  >> "$ROOT/$STATE_DIR/events.ndjson"
