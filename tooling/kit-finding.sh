#!/usr/bin/env bash
# kit-finding.sh --task ID --agent NAME --json     < one reviewer JSON object   [the main door]
# kit-finding.sh --task ID --agent NAME --class CLASS --severity SEV --summary TEXT
#                [--lang L] [--domain D] [--pattern P] [--model M]
# kit-finding.sh --vocab                           prints the accepted vocabularies
# kit-finding.sh --contract                        prints the shape of a finding
#
# Records review findings. This table is what the technology and industry accelerators are
# later derived from, so a silently mis-filled row is worse than a missing one: named
# flags, and vocabularies are validated.
#
# THIS SCRIPT DOES NOT SERIALISE. Every event line is built by kit_findings.py with json.dumps.
# It used to be built here with printf, and both T3 reviewers found the same critical: only
# `summary` was normalised, so `lang`, `pattern`, `domain` and `file` reached an append-only
# COMMITTED log raw. One quote corrupts the line permanently, and because the awk reader takes
# the first match, a crafted `lang` could inject a key the indexer would then prefer over the
# real one. Keep serialisation in one place with one writer.
#
# `--batch` was DELETED with that printf. It carried no `summary`, so it could only produce the
# bare-counter rows the contract exists to abolish, and its pipe-delimited format is one no
# reviewer emits any more. Deleting a component beats hardening it -- docs/LESSONS.md S5.
#
# --vocab exists because these lists were restated in the schema comment, in two skills and
# in the agent output contracts, and all four had drifted -- the agents emitted severities
# this script rejected outright, so most findings never recorded. Print the vocabulary
# rather than remembering it.
set -uo pipefail
. "$(dirname "$0")/kit-lib.sh"

# The one definition. Severity matches what the reviewer agents actually emit: a vocabulary
# its own producers do not use is a vocabulary that silently discards their output.
CLASSES="fail-open race false-rationale perf compliance correctness style unclassified"
SEVERITIES="critical major minor nit"

# Dispatched BEFORE the repository checks, because both answer "what may I send you" and that
# question is asked while reading the docs, not while standing in an adopted project. `--vocab`
# was already here; `--contract` was not, and outside a project it printed nothing and exited 0
# -- a T3 reviewer found the inconsistency.
case "${1:-}" in
  --vocab) printf 'class:    %s\nseverity: %s\n' "$CLASSES" "$SEVERITIES"; exit 0 ;;
  --contract) exec python3 "$(dirname "$0")/kit_findings.py" --contract ;;
esac

ROOT=$(kit_root) || exit 0
kit_active "$ROOT" || exit 0

task=""; agent=""; class=""; sev=""; lang=""; model=""; domain=""; pattern=""; json=0
agent_id=""; unattributed=0; summary=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) task=${2:-}; shift; shift ;;
    # An explicit flag, not an empty --task. A caller that does not know the task must SAY so,
    # because the alternative -- accepting a blank id -- turns every mistyped invocation into a
    # silently unattributed finding, which is the shape this whole file exists to refuse.
    --unattributed) unattributed=1; shift ;;
    --agent-id) agent_id=${2:-}; shift; shift ;;
    --agent) agent=${2:-}; shift; shift ;;
    --class) class=${2:-}; shift; shift ;;
    --severity) sev=${2:-}; shift; shift ;;
    --lang) lang=${2:-}; shift; shift ;;
    --domain) domain=${2:-}; shift; shift ;;
    --pattern) pattern=${2:-}; shift; shift ;;
    --summary) summary=${2:-}; shift; shift ;;
    --model) model=${2:-}; shift; shift ;;
    --json) json=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) kit_warn "unknown argument: $1"; exit 2 ;;
  esac
done

[ -n "$agent" ] || { kit_warn "missing --agent"; exit 2; }
if [ -z "$task" ] && [ "$unattributed" = 0 ]; then
  kit_warn "missing --task (or --unattributed if the caller genuinely cannot know it)"
  exit 2
fi
if [ -n "$task" ] && [ "$unattributed" = 1 ]; then
  kit_warn "--task and --unattributed are contradictory; refusing rather than picking one"
  exit 2
fi

PROFILE=$(kit_profile "$ROOT")
STATE_DIR=$(kit_cfg "$PROFILE" paths.state ".project")
mkdir -p "$ROOT/$STATE_DIR"
EV="$ROOT/$STATE_DIR/events.ndjson"

# Name the bad value AND the accepted set. A rejection that does not say what was expected
# just gets retried with another guess.
validate() {  # validate <class> <severity>
  case " $CLASSES " in *" $1 "*) ;; *)
    kit_warn "unknown class '$1' (one of: $CLASSES)"; return 1 ;; esac
  case " $SEVERITIES " in *" $2 "*) ;; *)
    kit_warn "unknown severity '$2' (one of: $SEVERITIES)"; return 1 ;; esac
  return 0
}

# No `record()` here any more. Every event line is serialised by kit_findings.py with
# json.dumps and appended by `emit` below in ONE operation. agent_id is still carried, so a
# second firing of a hook can tell whether THIS agent was already recorded.
emit() {  # emit <stdin: reviewer JSON object>
  # Built as a list rather than with `${unattributed:+...}`, because that variable holds 0 or 1
  # and 0 is NON-EMPTY -- the `:+` form passed --unattributed on every call and every recording
  # died as "contradictory with --task". Caught on the first run after the rewrite.
  set --
  [ -n "$task" ] && set -- "$@" --task "$task"
  [ "$unattributed" = 1 ] && set -- "$@" --unattributed
  _out=$(python3 "$PY" --emit-events "$@" \
           --agent "$agent" --agent-id "$agent_id" --model "$model" \
           --industries "$(declared_industries)") || return 2
  # One append. The validator emits nothing at all unless every finding passed, so there is no
  # arrangement in which some rows land and others do not -- which was true of the validator
  # before and NOT true of the writer, because the old loop appended per finding and could
  # exit partway. Both T3 reviewers found that; this is the fix.
  printf '%s\n' "$_out" >> "$EV"
  _n=$(printf '%s\n' "$_out" | grep -c '"kind":"finding"')
  _g=$(printf '%s\n' "$_out" | grep -c '"kind":"finding-gap"')
  if [ "${_g:-0}" -gt 0 ]; then
    printf 'kit: %s returned zero findings; recorded a finding-gap, not silence\n' "$agent" >&2
  else
    printf 'kit: recorded %s finding(s) from structured output\n' "$_n" >&2
  fi
  return 0
}

# A domain names an INDUSTRY and seeds the industry accelerator, so an arbitrary string
# there invents a vertical no project ever declared. Unlike an unknown class, which is
# rejected loudly, a wrong domain was accepted SILENTLY and polluted the thing it feeds.
#
# Reviewers reliably put the SUBJECT of the finding here instead -- `caching`,
# `cache-adapter-design` -- which is why `pattern` now exists: it was the axis they were
# reaching for. Accept a domain only if this project declared it.
# The declared list, passed to the writer rather than applied here, so the drop decision and
# the serialisation live in the same place.
declared_industries() {
  kit_cfg_all "$PROFILE" accelerator.industry |
    sed 's/[[:space:]]*->.*//' | sed 's|.*/||' | sed 's/\.md[[:space:]]*$//' | tr -d ' ' | tr '\n' ' '
}

PY="$(dirname "$0")/kit_findings.py"

# The structured path: a reviewer returns DATA and this records it. No block is scraped out of
# prose and nothing retypes fields by hand -- both were parsing, and every defect in the old
# harvester came from parsing (docs/LESSONS.md S5).
if [ "$json" = 1 ]; then
  emit || {
    kit_warn "findings rejected by the contract; nothing recorded (see above)"
    kit_warn "run \`kit-finding.sh --contract\` for the field list"
    exit 2
  }
  exit 0
fi

# The single-finding door, for a human recording one thing by hand. Routed through the SAME
# writer: a second serialiser is a second place to get escaping wrong, and this path used to be
# exactly that. The values are handed to python as ARGV rather than interpolated into a format
# string, so no quote an operator types can break the object.
#
# `--summary` is required here for the reason it is required in the contract: without one the
# row is a bare counter, and this door could still produce them after the contract closed the
# other one.
[ -n "$class" ] || { kit_warn "missing --class"; exit 2; }
[ -n "$sev" ]   || { kit_warn "missing --severity"; exit 2; }
[ -n "$summary" ] || {
  kit_warn "missing --summary (one line naming the defect, 8-200 characters)"
  kit_warn "  a finding without one cannot be told from any other row; see --contract"
  exit 2
}
validate "$class" "$sev" || exit 2

python3 -c 'import json,sys
k=("class","severity","summary","lang","pattern","domain")
print(json.dumps({"findings":[{a:b for a,b in zip(k,sys.argv[1:]) if b!=""}]}))' \
  "$class" "$sev" "$summary" "$lang" "$pattern" "$domain" | emit || {
    kit_warn "finding rejected by the contract; nothing recorded (see above)"
    exit 2
  }
