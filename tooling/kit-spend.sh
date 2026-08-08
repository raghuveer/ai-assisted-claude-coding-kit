#!/usr/bin/env bash
# kit-spend.sh — record what a unit of work actually cost.
#
# Invoked from the SubagentStop and Stop hooks with the hook JSON on stdin. Nobody types it,
# which is the whole point: a spend record that needs remembering is missing exactly on the
# busy tasks that matter, and a partial cost table reads as CHEAP work rather than UNMEASURED
# work -- the same failure escape rate had while the findings loop was open circuit.
#
# WHERE THE NUMBERS COME FROM. No hook payload carries token usage, so transcripts are the
# only source. There are two kinds and they do not overlap:
#
#   <project>/<session-id>.jsonl                        the MAIN LOOP's turns
#   <project>/<session-id>/subagents/**/agent-<id>.jsonl  one file per subagent
#
# The session transcript contains NO subagent records at all -- measured, 0 of 347 records
# sidechain on a 105-subagent run. The first version of this script read only that file and
# labelled the result with whichever agent had just stopped, so every "per-agent" row held
# main-loop cost. Populated, plausible and wrong, which is worse than empty. Hence the rule
# below: a row is labelled with an agent only when it was read from that agent's own file.
#
# WHAT IS AND IS NOT COST. Four surfaces report subagent tokens and they disagree by 5-215x,
# because they measure three different things (T-20260808 spike):
#
#   sum of raw usage fields   17,148,335   prices a cache read like fresh input
#   harness subagent_tokens    2,463,029   final CONTEXT SIZE summed -- blind to work done
#   summed output_tokens         169,383   work, but only the generated part
#   billing-weighted             6,378,878 what was actually billed
#
# So this records the four raw counters PER TURN-SUM plus the final context size, and leaves
# the weighting to kit-status.sh, where the multipliers live in one place. Storing a
# pre-weighted total would freeze today's price list into a committed log.
#
# ONE ROW PER TRANSCRIPT, keyed on the agent id (opaque already) or on a hash of the session
# transcript path (which names the project directory, and this log is committed). Totals are
# cumulative for the transcript, so the row is REPLACED, never summed -- and an unchanged
# total is not appended at all, which is what stops Stop and SubagentStop writing nine
# events for four agent runs.
#
#   kit-spend.sh                      # hook JSON on stdin
#   kit-spend.sh --transcript F [--agent NAME] [--agent-id ID] [--session ID]
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0
PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")

TRANSCRIPT=""; AGENT=""; SESSION=""; AGENT_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --transcript) TRANSCRIPT=${2:-}; shift; shift ;;
    --agent)      AGENT=${2:-};      shift; shift ;;
    --agent-id)   AGENT_ID=${2:-};   shift; shift ;;
    --session)    SESSION=${2:-};    shift; shift ;;
    -h|--help)    sed -n '2,44p' "$0"; exit 0 ;;
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
  [ -n "$AGENT" ]    || AGENT=$(jf "$HOOK" agent_type)
  [ -n "$SESSION" ]  || SESSION=$(jf "$HOOK" session_id)
  # Both spellings: the payload key is agent_id, and nothing guarantees it stays that way.
  [ -n "$AGENT_ID" ] || AGENT_ID=$(jf "$HOOK" agent_id)
  [ -n "$AGENT_ID" ] || AGENT_ID=$(jf "$HOOK" agentId)
fi

# Silent, not failing. A hook that errors on every turn is a hook the operator removes, and
# this one is instrumentation -- it must never be the reason a session stops.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

EVENTS="$ROOT/$STATE_DIR/events.ndjson"
SUBDIR="${TRANSCRIPT%.jsonl}/subagents"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$ROOT/$STATE_DIR"

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Which files this invocation is responsible for.
#
#   SubagentStop  the one agent that just stopped, by id. Its agent_type is the only place
#                 the real role is available -- .meta.json carries a generic type for
#                 workflow agents.
#   Stop          the main loop, PLUS a sweep of every agent transcript under this session.
#                 The sweep is what catches agents whose SubagentStop never fired: workflow
#                 subagents, and agents that died mid-stream. Those burned real tokens, and
#                 dropping them makes retried work look cheap.
#
# Both write the same rows keyed the same way, so a swept agent and its own SubagentStop
# produce one row, not two.
MAIN=""; FILES=""
if [ -n "$AGENT_ID" ]; then
  FILES=$(find "$SUBDIR" -type f -name "agent-$AGENT_ID.jsonl" 2>/dev/null | head -1)
  if [ -z "$FILES" ]; then
    # Criterion 3 of the defect: record nothing rather than a row labelled with an agent
    # name that holds someone else's cost -- but say so, because unmeasured must not read
    # as free. kit-status.sh counts these. The directory searched is deliberately not in the
    # message: it sits under the operator's home, and this log is committed.
    grep -q "\"spend-gap\".*\"agent_id\":\"$AGENT_ID\"" "$EVENTS" 2>/dev/null || \
    printf '{"task":"","kind":"spend-gap","at":"%s","agent":"%s","agent_id":"%s","session":"%s","reason":"no per-agent transcript found for this agent"}\n' \
      "$NOW" "$(esc "$AGENT")" "$(esc "$AGENT_ID")" "$(esc "$SESSION")" \
      >> "$EVENTS"
    exit 0
  fi
else
  MAIN="$TRANSCRIPT"
  FILES=$(find "$SUBDIR" -type f -name 'agent-*.jsonl' 2>/dev/null)
fi

# The session transcript path names the project directory and this log is committed. Hash it.
MAINKEY=""
[ -n "$MAIN" ] && MAINKEY=$(printf '%s' "$MAIN" | git hash-object --stdin 2>/dev/null | cut -c1-16)

# One awk over every file, not one per file: a sweep faces as many transcripts as the
# session spawned agents, and a hundred processes at every turn end is a hook the operator
# removes. Measured: 105 files, 5MB, 0.16s in a single pass.
#
# Two streams into the same reader. `M` lines carry each agent's declared type from its
# .meta.json, so a swept row can still say what kind of agent it was; `F` lines name the
# transcripts to read. Meta first, so the join is already built when the data arrives.
{
  # Newline-delimited, and expanded without basename(1) or word splitting: a home directory
  # with a space in it is not an error condition, and one process per file is what this
  # whole shape exists to avoid.
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    [ -n "$f" ] && [ -f "${f%.jsonl}.meta.json" ] || continue
    b=${f##*/}; b=${b%.jsonl}
    printf 'M\t%s\t%s\n' "$b" "${f%.jsonl}.meta.json"
  done
  [ -n "$MAINKEY" ] && printf 'F\t%s\t%s\n' "$MAINKEY" "$MAIN"
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    b=${f##*/}; b=${b%.jsonl}
    printf 'F\t%s\t%s\n' "$b" "$f"
  done
} | awk -v EV="$EVENTS" -v NOW="$NOW" -v SESSION="$SESSION" \
        -v HOOK_AGENT="$AGENT" -v HOOK_ID="$AGENT_ID" -v MAINKEY="$MAINKEY" '
  function num(s, k,   i, r) {
    i = index(s, "\"" k "\":"); if (i == 0) return 0
    r = substr(s, i + length(k) + 3)
    sub(/^[^0-9-]*/, "", r)
    return r + 0
  }
  function str(s, k,   i, r) {
    i = index(s, "\"" k "\":\""); if (i == 0) return ""
    r = substr(s, i + length(k) + 4)
    i = index(r, "\"")
    return (i > 1) ? substr(r, 1, i-1) : ""
  }
  function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }

  BEGIN {
    FS = "\t"
    # Every total already recorded, so an unchanged one is not appended again. Read once,
    # here, rather than grepping the log per agent -- same hundred processes by another name.
    while ((getline line < EV) > 0) {
      if (index(line, "\"spend\"") == 0) continue
      k = str(line, "transcript"); if (k == "") continue
      seen[k] = num(line, "tok_in") "|" num(line, "tok_out") "|" \
                num(line, "cache_read") "|" num(line, "cache_write")
    }
    close(EV)
  }

  $1 == "M" {
    while ((getline line < $3) > 0) {
      t = str(line, "agentType"); if (t != "") atype[$2] = t
    }
    close($3)
    next
  }

  $1 == "F" {
    key = $2; path = $3
    tin = tout = tcr = tcw = ctx = 0; model = ""; turns = 0
    while ((getline line < path) > 0) {
      if (index(line, "\"usage\"") == 0) continue
      u = substr(line, index(line, "\"usage\""))
      i = num(u, "input_tokens"); o = num(u, "output_tokens")
      r = num(u, "cache_read_input_tokens"); w = num(u, "cache_creation_input_tokens")
      tin += i; tout += o; tcr += r; tcw += w
      # Final context size: what the harness reports as subagent_tokens. Kept because it is
      # the one figure that reconciles against a second accounting (0.012% over 105 agents),
      # which is how a future reader checks this file is still reading the right records --
      # and because context pressure is worth watching even though it is not cost.
      ctx = i + r + w
      m = str(line, "model"); if (m != "") model = m
      turns++
    }
    close(path)

    # Nothing measured is not the same as zero cost, and recording a zero would make an
    # unmeasured session look free.
    if (turns == 0) next
    if (seen[key] == tin "|" tout "|" tcr "|" tcw) next

    if (key == MAINKEY) { scope = "main"; agent = ""; aid = "" }
    else {
      scope = "subagent"; aid = key
      sub(/^agent-/, "", aid)
      # The role, and only from a source that knows it: the hook payload for the agent that
      # actually stopped, otherwise the .meta.json sitting beside this very transcript.
      # Never a name carried in from elsewhere -- that is the defect this file was rewritten
      # for, and an empty label is the honest answer when no source knows.
      agent = (HOOK_ID != "" && HOOK_ID == aid) ? HOOK_AGENT : atype[key]
    }
    printf "{\"task\":\"\",\"kind\":\"spend\",\"at\":\"%s\",\"transcript\":\"%s\",\"scope\":\"%s\",\"agent\":\"%s\",\"agent_id\":\"%s\",\"session\":\"%s\",\"model\":\"%s\",\"turns\":%d,\"tok_in\":%d,\"tok_out\":%d,\"cache_read\":%d,\"cache_write\":%d,\"context\":%d}\n",
      NOW, esc(key), scope, esc(agent), esc(aid), esc(SESSION), esc(model), turns, tin, tout, tcr, tcw, ctx
  }
' >> "$EVENTS"
